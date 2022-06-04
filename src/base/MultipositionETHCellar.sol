// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "./Cellar.sol";
import { WETH } from "@solmate/tokens/WETH.sol";
import { Math } from "../utils/Math.sol";

import "../Errors.sol";

// TODO: try separating logic into and inheriting from LossyMultipositionCellar (vs LosslessMultipositionCellar)
// TODO: try not making this inheritable (get rid of virtual modifier from functions)

// TODO: add extensive documentation for cellar creators
// TODO: add events
// TODO: handle positions with different WETHs
// TODO: add comment that positions using ETH or a different version of WETH can still be supported using a wrapper

/**
 * @notice Attempted to trust a position that had an incompatible underlying asset.
 * @param incompatibleAsset address of the asset is incompatible with the asset of this cellar
 * @param expectedAsset address of the cellar's underlying asset
 */
error USR_IncompatiblePosition(ERC20 incompatibleAsset, ERC20 expectedAsset);

abstract contract MultipositionETHCellar is Cellar {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    // ============================================ ACCOUNTING STATE ============================================

    uint256 public totalLosslessBalance;

    // ========================================= MULTI-POSITION CONFIG =========================================

    // TODO: pack struct
    struct PositionData {
        bool isLossless;
        uint256 balance;
    }

    ERC4626[] public positions;

    mapping(ERC4626 => PositionData) public getPositionData;

    function getPositions() external view returns (ERC4626[] memory) {
        return positions;
    }

    function addPosition(ERC4626 position) public virtual onlyOwner {
        if (!isTrusted[position]) revert USR_UntrustedPosition(address(position));

        positions.push(position);
    }

    function removePosition(ERC4626 position) public virtual onlyOwner {
        _removePosition(position);
    }

    // TODO: add more position functions

    function setPositions(ERC4626[] calldata newPositions) public virtual onlyOwner {
        // TODO: handle positions with non-zero balances being removed

        // Ensure positions are trusted.
        for (uint256 i; i < newPositions.length; i++) {
            ERC4626 newPosition = newPositions[i];

            if (!isTrusted[newPosition]) revert USR_UntrustedPosition(address(newPosition));
        }

        positions = newPositions;
    }

    // ============================================ HOLDINGS CONFIG ============================================

    /**
     * @dev Should be set high enough that the holding pool can cover the majority of weekly
     *      withdraw volume without needing to pull from positions. See `beforeWithdraw` for
     *      more information as to why.
     */
    // TODO: consider changing default
    uint256 public targetHoldingsPercent = 0.05e18;

    function setTargetHoldings(uint256 targetPercent) external virtual onlyOwner {
        targetHoldingsPercent = targetPercent;
    }

    // ======================================== ACCRUAL CONFIG ========================================

    /**
     * @notice Emitted when accrual period is changed.
     * @param oldPeriod time the period was changed from
     * @param newPeriod time the period was changed to
     */
    event AccrualPeriodChanged(uint32 oldPeriod, uint32 newPeriod);

    /**
     * @notice Period of time over which yield since the last accrual is linearly distributed to the cellar.
     * @dev Net gains are distributed gradually over a period to prevent frontrunning and sandwich attacks.
     *      Net losses are realized immediately otherwise users could time exits to sidestep losses.
     */
    uint32 public accrualPeriod = 7 days;

    /**
     * @notice Timestamp of when the last accrual occurred.
     */
    uint64 public lastAccrual;

    /**
     * @notice The amount of yield to be distributed to the cellar from the last accrual.
     */
    uint160 public maxLocked;

    /**
     * @notice Set the accrual period over which yield is distributed.
     * @param newAccrualPeriod period of time in seconds of the new accrual period
     */
    function setAccrualPeriod(uint32 newAccrualPeriod) external onlyOwner {
        // Ensure that the change is not disrupting a currently ongoing distribution of accrued yield.
        if (totalLocked() > 0) revert STATE_AccrualOngoing();

        emit AccrualPeriodChanged(accrualPeriod, newAccrualPeriod);

        accrualPeriod = newAccrualPeriod;
    }

    // ============================================ TRUST CONFIG ============================================

    mapping(ERC4626 => bool) public isTrusted;

    function trustPosition(ERC4626 position) public virtual override onlyOwner {
        ERC20 positionAsset = position.asset();
        if (positionAsset != asset) revert USR_IncompatiblePosition(positionAsset, asset);

        isTrusted[position] = true;

        emit TrustChanged(position, true);
    }

    function distrustPosition(ERC4626 position) public virtual override onlyOwner {
        isTrusted[position] = false;

        _removePosition(position);

        emit TrustChanged(position, false);
    }

    // =========================================== CONSTRUCTOR ===========================================

    /**
     * @dev Owner should be set to the Gravity Bridge, which relays instructions from the Steward
     *      module to the cellars.
     *      https://github.com/PeggyJV/steward
     *      https://github.com/cosmos/gravity-bridge/blob/main/solidity/contracts/Gravity.sol
     * @param _WETH9 address of the WETH9 implementation used as the asset of the cellar
     * @param _positions address of ERC4626-compatible positions using WETH9 as the underlying asset
     * @param _name name of this cellar's share token
     * @param _name symbol of this cellar's share token
     */
    constructor(
        ERC20 _WETH9,
        ERC4626[] memory _positions,
        string memory _name,
        string memory _symbol
    ) Cellar(_WETH9, _name, _symbol) {
        // Initialize positions.
        for (uint256 i; i < _positions.length; i++) {
            ERC4626 position = _positions[i];
            ERC20 positionAsset = position.asset();

            if (positionAsset != asset) revert USR_IncompatiblePosition(positionAsset, asset);

            isTrusted[position] = true;
        }

        positions = _positions;

        // Transfer ownership to the Gravity Bridge.
        transferOwnership(address(gravityBridge));
    }

    // ============================================ CORE LOGIC ============================================

    /**
     * @dev Check if holding position has enough funds to cover the withdraw and only pull from the
     *      current lending position if needed.
     */
    function beforeWithdraw(
        uint256 assets,
        uint256,
        address,
        address
    ) internal virtual override {
        uint256 totalAssetsInHolding = totalHoldings();

        // Only withdraw if not enough assets in the holding pool.
        if (assets > totalAssetsInHolding) {
            uint256 totalAssetsInCellar = totalAssets();

            // The amounts needed to cover this withdraw and reach the target holdings percentage.
            uint256 assetsMissingForWithdraw = assets - totalAssetsInHolding;
            uint256 assetsMissingForTargetHoldings = (totalAssetsInCellar - assets).mulWadDown(targetHoldingsPercent);

            // Pull enough to cover the withdraw and reach the target holdings percentage.
            uint256 assetsleftToWithdraw = assetsMissingForWithdraw + assetsMissingForTargetHoldings;

            uint256 newTotalLosslessBalance = totalLosslessBalance;

            for (uint256 i; ; i++) {
                ERC4626 position = positions[i];

                uint256 totalPositionAssets = position.maxWithdraw(address(this));

                // Move on to next position if this one is empty.
                if (totalPositionAssets == 0) continue;

                // We want to pull as much as we can from this position, but no more than needed.
                uint256 assetsWithdrawn = Math.min(totalPositionAssets, assetsleftToWithdraw);

                PositionData storage positionData = getPositionData[position];

                if (positionData.isLossless) newTotalLosslessBalance -= assetsWithdrawn;

                // Without this the next accrual would count this withdrawal as a loss.
                positionData.balance -= assetsWithdrawn;

                // Update the assets left to withdraw.
                assetsleftToWithdraw -= assetsWithdrawn;

                // Pull from this position.
                _withdrawFromPosition(position, assetsWithdrawn);

                if (assetsleftToWithdraw == 0) break;
            }

            totalLosslessBalance = newTotalLosslessBalance;
        }
    }

    // ========================================= ACCOUNTING LOGIC =========================================

    /**
     * @notice The total amount of assets in the cellar.
     * @dev Excludes locked yield that hasn't been distributed.
     */
    function totalAssets() public view virtual override returns (uint256 assets) {
        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];

            if (getPositionData[position].isLossless) assets += position.maxWithdraw(address(this));
        }

        assets += totalLosslessBalance + totalHoldings() - totalLocked();
    }

    /**
     * @notice The total amount of locked yield still being distributed.
     */
    function totalLocked() public view returns (uint256) {
        // Get the last accrual and accrual period.
        uint256 previousAccrual = lastAccrual;
        uint256 accrualInterval = accrualPeriod;

        // If the accrual period has passed, there is no locked yield.
        if (block.timestamp >= previousAccrual + accrualInterval) return 0;

        // Get the maximum amount we could return.
        uint256 maxLockedYield = maxLocked;

        // Get how much yield remains locked.
        return maxLockedYield - (maxLockedYield * (block.timestamp - previousAccrual)) / accrualInterval;
    }

    // ========================================= ACCRUAL LOGIC =========================================

    function accrue() public override {
        uint256 totalLockedYield = totalLocked();

        // Without this check, malicious actors could do a slowdown attack on the distribution of
        // yield by continuously resetting the accrual period.
        if (msg.sender != owner() && totalLockedYield > 0) revert STATE_AccrualOngoing();

        uint256 totalBalanceLastAccrual = totalLosslessBalance;
        uint256 totalBalanceThisAccrual;

        uint256 newTotalLosslessBalance;

        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];
            PositionData storage positionData = getPositionData[position];

            uint256 balanceThisAccrual = position.maxWithdraw(address(this));

            // Check whether position is lossless.
            if (positionData.isLossless) {
                // Update total lossless balance. No need to add to last accrual balance
                // because since it is already accounted for in `totalLosslessBalance`.
                newTotalLosslessBalance += balanceThisAccrual;
            } else {
                // Add to balance for last accrual.
                totalBalanceLastAccrual += positionData.balance;
            }

            // Add to balance for this accrual.
            totalBalanceThisAccrual += balanceThisAccrual;

            // Store position's balance this accrual.
            positionData.balance = balanceThisAccrual;
        }

        // Compute and store current exchange rate between assets and shares for gas efficiency.
        uint256 exchangeRate = convertToShares(1e18);

        // Calculate platform fees accrued.
        uint256 elapsedTime = block.timestamp - lastAccrual;
        uint256 platformFeeInAssets = (totalBalanceThisAccrual * elapsedTime * platformFee) / 1e18 / 365 days;
        uint256 platformFees = platformFeeInAssets.mulWadDown(exchangeRate); // Convert to shares.

        // Calculate performance fees accrued.
        uint256 yield = totalBalanceThisAccrual.subMinZero(totalBalanceLastAccrual);
        uint256 performanceFeeInAssets = yield.mulWadDown(performanceFee);
        uint256 performanceFees = performanceFeeInAssets.mulWadDown(exchangeRate); // Convert to shares.

        // Mint accrued fees as shares.
        _mint(address(this), platformFees + performanceFees);

        // Do not count assets set aside for fees as yield. Allows fees to be immediately withdrawable.
        maxLocked = uint160(totalLockedYield + yield.subMinZero(platformFeeInAssets + performanceFeeInAssets));

        lastAccrual = uint32(block.timestamp);

        totalLosslessBalance = uint240(newTotalLosslessBalance);

        emit Accrual(platformFees, performanceFees);
    }

    // ========================================= REBALANCE LOGIC =========================================

    // TODO: move to Cellar.sol
    function enterPosition(ERC4626 position, uint256 assets) public virtual onlyOwner {
        PositionData storage positionData = getPositionData[position];

        if (positionData.isLossless) totalLosslessBalance += assets;

        positionData.balance += assets;

        // Deposit into position.
        _depositIntoPosition(position, assets);
    }

    // TODO: move to Cellar.sol
    function exitPosition(ERC4626 position, uint256 assets) public virtual onlyOwner {
        PositionData storage positionData = getPositionData[position];

        if (positionData.isLossless) totalLosslessBalance -= assets;

        positionData.balance -= assets;

        // Withdraw from specified position.
        _withdrawFromPosition(position, assets);
    }

    function rebalance(
        ERC4626 fromPosition,
        ERC4626 toPosition,
        uint256 assets
    ) public virtual onlyOwner {
        PositionData storage fromPositionData = getPositionData[fromPosition];
        PositionData storage toPositionData = getPositionData[toPosition];

        fromPositionData.balance -= assets;
        toPositionData.balance += assets;

        uint256 newTotalLosslessBalance = totalLosslessBalance;

        if (fromPositionData.isLossless) newTotalLosslessBalance -= assets;
        if (toPositionData.isLossless) newTotalLosslessBalance += assets;

        totalLosslessBalance = newTotalLosslessBalance;

        // Withdraw from specified position.
        _withdrawFromPosition(fromPosition, assets);

        // Deposit into destination position.
        _depositIntoPosition(toPosition, assets);
    }

    // ========================================= RECOVERY LOGIC =========================================

    function sweep(
        ERC20 token,
        address to,
        uint256 amount
    ) public virtual override onlyOwner {
        for (uint256 i; i < positions.length; i++)
            if (address(token) == address(positions[i])) revert USR_ProtectedAsset(address(token));

        super.sweep(token, to, amount);
    }

    // ======================================== HELPER FUNCTIONS ========================================

    // TODO: move to Cellar.sol
    /**
     * @notice Deposits into a position.
     */
    function _depositIntoPosition(ERC4626 position, uint256 assets) internal virtual whenNotShutdown {
        if (!isTrusted[position]) revert USR_UntrustedPosition(address(position));

        position.asset().safeApprove(address(position), assets);
        position.deposit(assets, address(this));
    }

    // TODO: move to Cellar.sol
    /**
     * @notice Withdraws from a position.
     */
    function _withdrawFromPosition(ERC4626 position, uint256 assets) internal virtual {
        position.withdraw(assets, address(this), address(this));
    }

    function _emptyPosition(ERC4626 position) internal virtual {
        PositionData storage positionData = getPositionData[position];

        uint256 balanceLastAccrual = positionData.balance;
        uint256 balanceThisAccrual = position.redeem(position.balanceOf(address(this)), address(this), address(this));

        positionData.balance = 0;

        if (positionData.isLossless) totalLosslessBalance -= balanceLastAccrual;

        if (balanceThisAccrual == 0) return;

        // Calculate performance fees accrued.
        uint256 yield = balanceThisAccrual.subMinZero(balanceLastAccrual);
        uint256 performanceFeeInAssets = yield.mulWadDown(performanceFee);
        uint256 performanceFees = convertToShares(performanceFeeInAssets); // Convert to shares.

        // Mint accrued fees as shares.
        _mint(address(this), performanceFees);

        // Do not count assets set aside for fees as yield. Allows fees to be immediately withdrawable.
        maxLocked = uint160(totalLocked() + yield.subMinZero(performanceFeeInAssets));
    }

    function _removePosition(ERC4626 position) internal virtual {
        // Pull any assets that were in the removed position to the holding pool.
        _emptyPosition(position);

        // TODO: pop position if withdrawing from in `beforeWithdraw`
        // Remove position from the list of positions if it is present.
        uint256 len = positions.length;
        if (position == positions[len - 1]) {
            positions.pop();
        } else {
            for (uint256 i; i < len; i++) {
                if (positions[i] == position) {
                    for (i; i < len - 1; i++) positions[i] = positions[i + 1];

                    positions.pop();

                    break;
                }
            }
        }
    }

    // ====================================== RECEIVE ETHER LOGIC ======================================

    /**
     * @dev Deposits ETH sent by the caller and mints them shares.
     */
    receive() external payable {
        // Ignore if unwrapping WETH to ETH.
        if (msg.sender == address(asset)) return;

        uint256 assets = msg.value;
        uint256 shares = previewDeposit(assets);

        // Check for rounding error since assets are rounded down in `previewDeposit`.
        require(shares != 0, "ZERO_SHARES");

        beforeDeposit(assets, shares, msg.sender);

        // Wrap received ETH into WETH.
        WETH(payable(address(asset))).deposit{ value: assets }();

        _mint(msg.sender, shares);

        emit Deposit(msg.sender, msg.sender, assets, shares);

        afterDeposit(assets, shares, msg.sender);
    }
}
