// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "./Cellar.sol";
import { WETH } from "@solmate/tokens/WETH.sol";
import { Math } from "../utils/Math.sol";
import { AddressArray } from "src/utils/AddressArray.sol";

import "../Errors.sol";

// TODO: maybe this should not be inheritable (get rid of virtual modifier from functions)
// TODO: move to /Cellars folder

// TODO: add extensive documentation for cellar creators
// TODO: add events
// TODO: handle positions with different WETHs
// TODO: add comment that positions using ETH or a different version of WETH can still be supported using a wrapper

contract MultipositionETHCellar is Cellar {
    using AddressArray for address[];
    using SafeTransferLib for ERC20;
    using Math for uint256;

    // ========================================= MULTI-POSITION CONFIG =========================================

    /**
     * @notice Emitted when a position is added.
     * @param position address of position that was added
     * @param index index that position was added at
     */
    event PositionAdded(address indexed position, uint256 index);

    /**
     * @notice Emitted when a position is removed.
     * @param position address of position that was removed
     * @param index index that position was removed from
     */
    event PositionRemoved(address indexed position, uint256 index);

    /**
     * @notice Emitted when a position is replaced.
     * @param oldPosition address of position at index before being replaced
     * @param newPosition address of position at index after being replaced
     * @param index index of position replaced
     */
    event PositionReplaced(address indexed oldPosition, address indexed newPosition, uint256 index);

    /**
     * @notice Emitted when the positions at two indexes are swapped.
     * @param newPosition1 address of position (previously at index2) that replaced index1.
     * @param newPosition2 address of position (previously at index1) that replaced index2.
     * @param index1 index of first position involved in the swap
     * @param index2 index of second position involved in the swap.
     */
    event PositionSwapped(address indexed newPosition1, address indexed newPosition2, uint256 index1, uint256 index2);

    // TODO: pack struct
    struct PositionData {
        bool isLossless;
        uint256 balance;
    }

    address[] public positions;

    mapping(address => PositionData) public getPositionData;

    function getPositions() external view returns (address[] memory) {
        return positions;
    }

    function isPositionUsed(address position) public view virtual returns (bool) {
        return positions.contains(position);
    }

    function addPosition(uint256 index, address position) public virtual onlyOwner whenNotShutdown {
        if (!isTrusted[position]) revert USR_UntrustedPosition(position);

        // Check if position is already being used.
        if (isPositionUsed(position)) revert USR_PositionAlreadyUsed(position);

        // Check if position has same underlying as cellar.
        ERC20 cellarAsset = asset;
        ERC20 positionAsset = ERC4626(position).asset();
        if (positionAsset != cellarAsset) revert USR_IncompatiblePosition(address(positionAsset), address(cellarAsset));

        // Add new position at a specified index.
        positions.add(index, position);

        emit PositionAdded(position, index);
    }

    /**
     * @dev If you know you are going to add a position to the end of the array, this is more
     *      efficient then `addPosition`.
     */
    function pushPosition(address position) public virtual onlyOwner whenNotShutdown {
        if (!isTrusted[position]) revert USR_UntrustedPosition(position);

        // Check if position is already being used.
        if (isPositionUsed(position)) revert USR_PositionAlreadyUsed(position);

        // Check if position has same underlying as cellar.
        ERC20 cellarAsset = asset;
        ERC20 positionAsset = ERC4626(position).asset();
        if (positionAsset != cellarAsset) revert USR_IncompatiblePosition(address(positionAsset), address(cellarAsset));

        // Add new position to the end of the positions.
        positions.push(position);

        emit PositionAdded(position, positions.length - 1);
    }

    function removePosition(uint256 index) public virtual onlyOwner {
        // Get position being removed.
        address position = positions[index];

        // Remove position at the given index.
        positions.remove(index);

        // Pull any assets that were in the removed position to the holding pool.
        _emptyPosition(position);

        emit PositionRemoved(position, index);
    }

    /**
     * @dev If you know you are going to remove a position from the end of the array, this is more
     *      efficient then `removePosition`.
     */
    function popPosition() public virtual onlyOwner {
        // Get the index of the last position and last position itself.
        uint256 index = positions.length - 1;
        address position = positions[index];

        // Remove last position.
        positions.pop();

        // Pull any assets that were in the removed position to the holding pool.
        _emptyPosition(position);

        emit PositionRemoved(position, index);
    }

    function replacePosition(address newPosition, uint256 index) public virtual onlyOwner whenNotShutdown {
        // Store the old position before its replaced.
        address oldPosition = positions[index];

        // Replace old position with new position.
        positions[index] = newPosition;

        // Pull any assets that were in the old position to the holding pool.
        _emptyPosition(oldPosition);

        emit PositionReplaced(oldPosition, newPosition, index);
    }

    function swapPositions(uint256 index1, uint256 index2) public virtual onlyOwner {
        // Get the new positions that will be at each index.
        address newPosition1 = positions[index2];
        address newPosition2 = positions[index1];

        // Swap positions.
        (positions[index1], positions[index2]) = (newPosition1, newPosition2);

        emit PositionSwapped(newPosition1, newPosition2, index1, index2);
    }

    // TODO: add functions to config position data

    // ============================================ TRUST CONFIG ============================================

    /**
     * @notice Emitted when trust for a position is changed.
     * @param position address of position that trust was changed for
     * @param isTrusted whether the position is trusted
     */
    event TrustChanged(address indexed position, bool isTrusted);

    mapping(address => bool) public isTrusted;

    function trustPosition(address position, bool isLossless) public virtual onlyOwner {
        // Trust position.
        isTrusted[position] = true;

        // Set position's lossless flag.
        getPositionData[position].isLossless = isLossless;

        // Set max approval to deposit into position if it is ERC4626.
        ERC4626(position).asset().safeApprove(position, type(uint256).max);

        emit TrustChanged(position, true);
    }

    function distrustPosition(address position) public virtual onlyOwner {
        // Distrust position.
        isTrusted[position] = false;

        // Remove position from the list of positions if it is present.
        positions.remove(position);

        // Pull any assets that were in the removed position to the holding pool.
        _emptyPosition(position);

        // Remove approval for position.
        ERC4626(position).asset().safeApprove(position, 0);

        emit TrustChanged(position, false);
    }

    // ============================================ ACCOUNTING STATE ============================================

    uint256 public totalLosslessBalance;

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

    // ============================================ HOLDINGS CONFIG ============================================

    /**
     * @dev Should be set high enough that the holding pool can cover the majority of weekly
     *      withdraw volume without needing to pull from positions. See `beforeWithdraw` for
     *      more information as to why.
     */
    // TODO: modularize this
    // TODO: consider changing default
    uint256 public targetHoldingsPercent = 0.05e18;

    function setTargetHoldings(uint256 targetPercent) external virtual onlyOwner {
        targetHoldingsPercent = targetPercent;
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
        address[] memory _positions,
        string memory _name,
        string memory _symbol
    ) Cellar(_WETH9, _name, _symbol) {
        // Initialize positions.
        for (uint256 i; i < _positions.length; i++) {
            address position = _positions[i];
            ERC20 positionAsset = ERC4626(position).asset();

            // Only allow positions with same underlying as cellar.
            if (positionAsset != _WETH9) revert USR_IncompatiblePosition(address(positionAsset), address(_WETH9));

            isTrusted[address(position)] = true;

            // Set max approval for deposits into position.
            _WETH9.safeApprove(position, type(uint256).max);
        }

        positions = _positions;
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
                ERC4626 position = ERC4626(positions[i]);

                uint256 totalPositionAssets = position.maxWithdraw(address(this));

                // Move on to next position if this one is empty.
                if (totalPositionAssets == 0) continue;

                // We want to pull as much as we can from this position, but no more than needed.
                uint256 assetsWithdrawn = Math.min(totalPositionAssets, assetsleftToWithdraw);

                PositionData storage positionData = getPositionData[address(position)];

                if (positionData.isLossless) newTotalLosslessBalance -= assetsWithdrawn;

                // Without this the next accrual would count this withdrawal as a loss.
                positionData.balance -= assetsWithdrawn;

                // Update the assets left to withdraw.
                assetsleftToWithdraw -= assetsWithdrawn;

                // Pull from this position.
                position.withdraw(assetsWithdrawn, address(this), address(this));

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
            address position = positions[i];

            if (getPositionData[position].isLossless) assets += ERC4626(position).maxWithdraw(address(this));
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
            ERC4626 position = ERC4626(positions[i]);
            PositionData storage positionData = getPositionData[address(position)];

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

    // TODO: test trying to enterPosition/rebalance into untrusted position (should revert bc approval not given)

    function enterPosition(address position, uint256 assets) public virtual onlyOwner {
        PositionData storage positionData = getPositionData[address(position)];

        if (positionData.isLossless) totalLosslessBalance += assets;

        positionData.balance += assets;

        // Deposit into position.
        ERC4626(position).deposit(assets, address(this));
    }

    function exitPosition(address position, uint256 assets) public virtual onlyOwner {
        PositionData storage positionData = getPositionData[address(position)];

        if (positionData.isLossless) totalLosslessBalance -= assets;

        positionData.balance -= assets;

        // Withdraw from specified position.
        ERC4626(position).withdraw(assets, address(this), address(this));
    }

    function rebalance(
        address fromPosition,
        address toPosition,
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
        ERC4626(fromPosition).withdraw(assets, address(this), address(this));

        // Deposit into destination position.
        ERC4626(toPosition).deposit(assets, address(this));
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

    function _emptyPosition(address position) internal virtual {
        PositionData storage positionData = getPositionData[position];

        uint256 balanceLastAccrual = positionData.balance;
        uint256 balanceThisAccrual = ERC4626(position).redeem(
            ERC4626(position).balanceOf(address(this)),
            address(this),
            address(this)
        );

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
