// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "../interfaces/ERC4626.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC4626 } from "../interfaces/ERC4626.sol";
import { IGravity } from "../interfaces/IGravity.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { MathUtils } from "../utils/MathUtils.sol";

import "../Errors.sol";

// TODO: add extensive documentation for cellar creators
// TODO: add events

abstract contract MultipositionCellar is ERC4626, Ownable {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    // ============================================ ACCOUNTING STATE ============================================

    uint256 public totalBalance;

    // ============================================ HOLDINGS CONFIG ============================================

    /**
     * @dev Should be set high enough that the holding pool can cover the majority of weekly
     *      withdraw volume without needing to pull from positions. See `beforeWithdraw` for
     *      more information as to why.
     */
    // TODO: consider changing default
    uint256 public targetHoldingsPercent = 5_00;

    function setTargetHoldings(uint256 targetPercent) external virtual onlyOwner {
        targetHoldingsPercent = targetPercent;
    }

    // ============================================ ACCRUAL STORAGE ============================================

    /**
     * @dev Yield is distributed gradually over an accrual period to prevent frontrunning and sandwich attacks.
     *      Losses are realized immediately to prevent users from timing exits to sidestep losses.
     */

    uint32 public accrualPeriod = 7 days;

    uint32 public nextAccrualPeriod;

    uint64 public lastAccrual;

    uint128 public maxLocked;

    function setAccrualPeriod(uint32 newAccrualPeriod) external virtual onlyOwner {
        nextAccrualPeriod = newAccrualPeriod;
    }

    // ============================================= FEES CONFIG =============================================

    // TODO: have fees read from the default set by the registry
    // TODO: experiment with accruing platform fees from all cellar at once through registry / another module

    uint256 public constant DENOMINATOR = 100_00;

    /**
     * @notice The percentage of platform fees taken off of active assets over a year.
     */
    uint256 public constant PLATFORM_FEE = 1_00; // 1%

    /**
     * @notice The percentage of performance fees taken off of cellar gains.
     */
    uint256 public constant PERFORMANCE_FEE = 10_00; // 10%

    // ========================================= MULTI-POSITION CONFIG =========================================

    ERC4626[] public positions;

    function getPositions() external view returns (ERC4626[] memory) {
        return positions;
    }

    /**
     * @dev `maxSlippage` should not be set too low as to cause all withdraws involving a swap to
     *      revert or too high as to have swaps be sandwich attacked.
     */
    struct PositionData {
        bool isTrusted;
        uint32 maxSlippage;
        uint112 assets;
        address[] pathToAsset;
    }

    mapping(ERC4626 => PositionData) public getPositionData;

    function addPosition(ERC4626 position) external virtual onlyOwner {
        if (!getPositionData[position].isTrusted) revert USR_UntrustedPosition(address(position));

        positions.push(position);
    }

    function removePosition(ERC4626 position) external virtual onlyOwner {
        _removePosition(position);
    }

    // TODO: consider moving position functions to own module
    function setPositions(
        ERC4626[] calldata newPositions,
        address[][] calldata pathsToAsset,
        uint32[] calldata maxSlippages
    ) external virtual onlyOwner {
        for (uint256 i; i < newPositions.length; i++) {
            PositionData storage positionData = getPositionData[newPositions[i]];

            // Ensure position is trusted.
            if (!positionData.isTrusted) revert USR_UntrustedPosition(address(newPositions[i]));

            positionData.maxSlippage = maxSlippages[i];
            positionData.pathToAsset = pathsToAsset[i];
        }

        positions = newPositions;
    }

    function setPositions(ERC4626[] calldata newPositions, uint32[] calldata maxSlippages) external virtual onlyOwner {
        for (uint256 i; i < newPositions.length; i++) {
            PositionData storage positionData = getPositionData[newPositions[i]];

            // Ensure position is trusted.
            if (!positionData.isTrusted) revert USR_UntrustedPosition(address(newPositions[i]));

            positionData.maxSlippage = maxSlippages[i];
        }

        positions = newPositions;
    }

    function setPositions(ERC4626[] calldata newPositions) external virtual onlyOwner {
        for (uint256 i; i < newPositions.length; i++)
            // Ensure position is trusted.
            if (!getPositionData[newPositions[i]].isTrusted) revert USR_UntrustedPosition(address(newPositions[i]));

        positions = newPositions;
    }

    function setPathToAsset(ERC4626 position, address[] memory pathToAsset) external virtual onlyOwner {
        getPositionData[position].pathToAsset = pathToAsset;
    }

    function setMaxSlippage(ERC4626 position, uint32 maxSlippage) external virtual onlyOwner {
        getPositionData[position].maxSlippage = maxSlippage;
    }

    function setTrust(ERC4626 position, bool isTrusted) external virtual onlyOwner {
        getPositionData[position].isTrusted = isTrusted;

        if (!isTrusted) _removePosition(position);
    }

    // ============================================= LIMITS CONFIG =============================================

    /**
     * @notice Emitted when the liquidity limit is changed.
     * @param oldLimit amount the limit was changed from
     * @param newLimit amount the limit was changed to
     */
    event LiquidityLimitChanged(uint256 oldLimit, uint256 newLimit);

    /**
     * @notice Emitted when the deposit limit is changed.
     * @param oldLimit amount the limit was changed from
     * @param newLimit amount the limit was changed to
     */
    event DepositLimitChanged(uint256 oldLimit, uint256 newLimit);

    /**
     * @notice Maximum amount of assets that can be managed by the cellar. Denominated in the same decimals
     *         as the current asset.
     * @dev Set to `type(uint256).max` to have no limit.
     */
    uint256 public liquidityLimit = type(uint256).max;

    function setLiquidityLimit(uint256 limit) external virtual onlyOwner {
        // Store for emitted event.
        uint256 oldLimit = liquidityLimit;

        // Change the liquidity limit.
        liquidityLimit = limit;

        emit LiquidityLimitChanged(oldLimit, limit);
    }

    /**
     * @notice Maximum amount of assets per account. Denominated in the same decimals as the current asset.
     * @dev Set to `type(uint256).max` to have no limit.
     */
    uint256 public depositLimit = type(uint256).max;

    function setDepositLimit(uint256 limit) external virtual onlyOwner {
        // Store for emitted event.
        uint256 oldLimit = depositLimit;

        // Change the deposit limit.
        depositLimit = limit;

        emit DepositLimitChanged(oldLimit, limit);
    }

    // =========================================== EMERGENCY LOGIC ===========================================

    bool public isShutdown;

    /**
     * @notice Stop or start the contract. Used in an emergency or if the cellar has been depreciated.
     */
    function setShutdown(bool shutdown, bool exitPositions) external virtual onlyOwner {
        isShutdown = shutdown;

        // Exit all positions.
        if (shutdown && exitPositions) for (uint256 i; i < positions.length; i++) _emptyPosition(positions[i]);
    }

    // =========================================== CONSTRUCTOR ===========================================

    // TODO: have cellar read gravity address from registry
    /**
     * @notice Cosmos Gravity Bridge contract. Used to transfer fees to `feeDistributor` on the Sommelier chain.
     */
    IGravity public constant gravityBridge = IGravity(0x69592e6f9d21989a043646fE8225da2600e5A0f7);
    ISwapRouter public immutable swapRouter;

    /**
     * @dev Owner should be set to the Gravity Bridge, which relays instructions from the Steward
     *      module to the cellars.
     *      https://github.com/PeggyJV/steward
     *      https://github.com/cosmos/gravity-bridge/blob/main/solidity/contracts/Gravity.sol
     */
    constructor(
        ERC20 _asset,
        ERC4626[] memory _positions,
        address[][] memory _pathsToAsset,
        uint32[] memory _maxSlippages,
        ISwapRouter _swapRouter,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC4626(_asset, _name, _symbol, _decimals) Ownable() {
        positions = _positions;
        swapRouter = _swapRouter;

        // TODO: add checks that maxSlippages are within a healthy range and that pathToAsset is to asset
        // Set holding limits for each position and trust all initial positions.
        for (uint256 i; i < _positions.length; i++)
            getPositionData[_positions[i]] = PositionData({
                isTrusted: true,
                maxSlippage: _maxSlippages[i],
                assets: 0,
                pathToAsset: _pathsToAsset[i]
            });

        lastAccrual = uint64(block.timestamp);

        // Transfer ownership to the Gravity Bridge.
        transferOwnership(address(gravityBridge));
    }

    // ========================================= ACCOUNTING LOGIC =========================================

    function totalAssets() public view virtual override returns (uint256) {
        return totalBalance - totalLocked() + totalHoldings();
    }

    function totalHoldings() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function totalLocked() public view virtual returns (uint256) {
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

    /**
     * @notice Denominate position assets in the cellar's asset.
     */
    function convertToAssets(ERC20 positionAsset, uint256 assets) public view virtual returns (uint256);

    // =========================================== CORE LOGIC ===========================================

    function beforeDeposit(
        uint256 assets,
        uint256,
        address receiver
    ) internal virtual override {
        if (isShutdown) revert STATE_ContractShutdown();

        uint256 maxDepositable = maxDeposit(receiver);
        if (assets > maxDepositable) revert USR_DepositRestricted(assets, maxDepositable);
    }

    /**
     *  @dev Although this behavior is not desired, it should be noted that attempting to withdraw
     *       exactly the cellar's total assets from positions using a different underlying asset as
     *       the holding position will likely revert due to a discrepency in the total assets
     *       reported by the cellar and the total assets that can actually be withdrawn when swap
     *       slippage is factored in. In this case, the withdrawn amount needed to empty the cellar
     *       (or get as close as possible to it) would need to factor in swap slippage. Normal
     *       withdraws do not need to worry about this. If the holding position cannot already cover
     *       a withdraw in full, the cellar will withdraw an excess amount from positions until it
     *       can cover not just that single withdraw but also subsequent withdraws up to
     *       configurable target. This is much more economic for users as it batches withdraws
     *       instead of doing potentially hundreds of withdraws from positions.
     */
    function beforeWithdraw(
        uint256 assets,
        uint256,
        address,
        address
    ) internal virtual override {
        uint256 currentHoldings = totalHoldings();

        // Only triggers if there are not enough assets in the holding position to cover the
        // withdraw. Ideally, this would rarely trigger if the cellar is active with deposits and
        // the strategy provider sets a high enough target holdings percentage.
        if (assets > currentHoldings) {
            uint256 currentTotalAssets = totalAssets();

            // The amounts needed to cover this withdraw and reach the target holdings percentage.
            uint256 holdingsMissingForWithdraw = assets - currentHoldings;
            uint256 holdingsMissingForTarget = currentTotalAssets.mulDivDown(targetHoldingsPercent, DENOMINATOR);

            // Pull enough to cover the withdraw and reach the target holdings percentage if possible.
            assets = MathUtils.min(holdingsMissingForWithdraw + holdingsMissingForTarget, currentTotalAssets);
            uint256 leftToWithdraw = assets;

            for (uint256 i = positions.length - 1; ; i--) {
                ERC4626 position = positions[i];
                PositionData memory positionData = getPositionData[position];

                uint256 totalPositionAssets = positionData.assets;

                // Move on if this position is empty.
                if (totalPositionAssets == 0) continue;

                // Exchange rate between the position asset and cellar's asset.
                uint256 onePositionAsset = 10**position.decimals();
                uint256 exchangeRate = convertToAssets(position.asset(), onePositionAsset);

                // We want to pull as much as we can from this position, but no more than needed.
                uint256 positionAssetsWithdrawn = MathUtils.min(
                    totalPositionAssets,
                    leftToWithdraw.mulDivDown(onePositionAsset, exchangeRate)
                );

                uint256 assetsWithdrawn = positionAssetsWithdrawn.mulDivDown(exchangeRate, onePositionAsset);

                leftToWithdraw -= assetsWithdrawn;

                // Pull from this position.
                _withdrawFromPosition(position, positionAssetsWithdrawn);

                // Minimum assets to receive from swap based on the max slippage set for this position.
                uint256 assetsOutMin = assetsWithdrawn.mulDivDown(DENOMINATOR - positionData.maxSlippage, DENOMINATOR);

                // Perform a swap to holding position asset if necessary.
                _swapTo(asset, positionAssetsWithdrawn, assetsOutMin, positionData.pathToAsset);

                if (leftToWithdraw == 0) break;
            }
        }
    }

    function rebalance(
        ERC4626 fromPosition,
        ERC4626 toPosition,
        uint256 assetsFrom,
        uint256 assetsToMin,
        address[] memory path
    ) external virtual onlyOwner returns (uint256 assetsTo) {
        // Withdraw from specified position if it is not the holding position.
        if (address(fromPosition) != address(this)) _withdrawFromPosition(fromPosition, assetsFrom);

        // Perform a swap to receiving position's asset if necessary.
        assetsTo = _swapTo(toPosition.asset(), assetsFrom, assetsToMin, path);

        // Deposit to destination if it is not the holding position.
        if (address(toPosition) != address(this)) _depositIntoPosition(toPosition, assetsTo);
    }

    // ============================================ LIMITS LOGIC ============================================

    function maxDeposit(address owner) public view virtual override returns (uint256) {
        if (isShutdown) return 0;

        if (depositLimit == type(uint256).max && liquidityLimit == type(uint256).max) return type(uint256).max;

        uint256 leftUntilDepositLimit = depositLimit.subFloor(maxWithdraw(owner));
        uint256 leftUntilLiquidityLimit = liquidityLimit.subFloor(totalAssets());

        // Only return the more relevant of the two.
        return MathUtils.min(leftUntilDepositLimit, leftUntilLiquidityLimit);
    }

    function maxMint(address owner) public view virtual override returns (uint256) {
        if (isShutdown) return 0;

        if (depositLimit == type(uint256).max && liquidityLimit == type(uint256).max) return type(uint256).max;

        uint256 leftUntilDepositLimit = depositLimit.subFloor(maxWithdraw(owner));
        uint256 leftUntilLiquidityLimit = liquidityLimit.subFloor(totalAssets());

        // Only return the more relevant of the two.
        return convertToShares(MathUtils.min(leftUntilDepositLimit, leftUntilLiquidityLimit));
    }

    // =========================================== ACCRUAL LOGIC ===========================================

    function accrue() external virtual onlyOwner {
        if (totalLocked() > 0) revert STATE_AccrualOngoing();

        uint256 yield;
        uint256 currentTotalBalance = totalBalance;

        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];

            uint256 lastPositionAssets = getPositionData[position].assets;
            uint256 currentPositionAssets = position.maxWithdraw(address(this));

            getPositionData[position].assets = uint112(currentPositionAssets);

            uint256 onePositionAsset = 10**position.decimals();
            uint256 exchangeRate = convertToAssets(position.asset(), onePositionAsset);

            uint256 lastAssets = lastPositionAssets.mulDivDown(exchangeRate, onePositionAsset);
            uint256 currentAssets = currentPositionAssets.mulDivDown(exchangeRate, onePositionAsset);

            currentTotalBalance = currentTotalBalance + currentAssets - lastAssets;

            yield += currentAssets.subFloor(lastAssets);
        }

        // Accrue performance and platform fees as shares minted to the cellar.

        uint256 performanceFeesInAssets;
        uint256 performanceFees;
        if (yield != 0) {
            performanceFeesInAssets = yield.mulDivDown(PERFORMANCE_FEE, DENOMINATOR);
            performanceFees = convertToShares(performanceFeesInAssets);
        }

        uint256 elapsedTime = block.timestamp - lastAccrual;
        uint256 platformFeeInAssets = (totalAssets() * elapsedTime * PLATFORM_FEE) / DENOMINATOR / 365 days;
        uint256 platformFees = convertToShares(platformFeeInAssets);

        _mint(address(this), performanceFees + platformFees);

        maxLocked = uint128(yield.subFloor(performanceFeesInAssets + platformFeeInAssets));

        lastAccrual = uint64(block.timestamp);

        // Update cellar's total balance.
        totalBalance = currentTotalBalance;

        // Update the accrual period if it was changed.
        uint32 newAccrualPeriod = nextAccrualPeriod;
        if (newAccrualPeriod != 0) {
            accrualPeriod = newAccrualPeriod;

            delete nextAccrualPeriod;
        }
    }

    // ======================================== SWEEP LOGIC ========================================

    function sweep(
        address token,
        uint256 amount,
        address to
    ) external virtual onlyOwner {
        // Prevent sweeping of assets managed by the cellar and shares minted to the cellar as fees.
        if (token == address(asset) || token == address(this)) revert USR_ProtectedAsset(token);
        for (uint256 i; i < positions.length; i++) if (token == address(positions[i])) revert USR_ProtectedAsset(token);

        // Transfer out tokens in this cellar that shouldn't be here.
        ERC20(token).safeTransfer(to, amount);
    }

    // ======================================== HELPER FUNCTIONS ========================================

    /**
     * @notice Deposits into an ERC4626-compatible position.
     */
    function _depositIntoPosition(ERC4626 position, uint256 assets) internal virtual {
        if (!getPositionData[position].isTrusted) revert USR_UntrustedPosition(address(position));
        if (isShutdown) revert STATE_ContractShutdown();

        getPositionData[position].assets += uint112(assets);
        ERC20 positionAsset = position.asset();
        totalBalance += convertToAssets(positionAsset, assets);

        positionAsset.safeApprove(address(position), assets);
        position.deposit(assets, address(this));
    }

    /**
     * @notice Withdraws from an ERC4626-compatible position.
     */
    function _withdrawFromPosition(ERC4626 position, uint256 assets) internal virtual {
        getPositionData[position].assets -= uint112(assets);
        totalBalance -= convertToAssets(position.asset(), assets);

        position.withdraw(assets, address(this), address(this));
    }

    function _swapTo(
        ERC20 toAsset,
        uint256 assets,
        uint256 assetsOutMin,
        address[] memory path
    ) internal virtual returns (uint256 assetsOut) {
        ERC20 assetIn = ERC20(path[0]);
        ERC20 assetOut = ERC20(path[path.length - 1]);

        // Check whether a swap is necessary. If not, just return back assets.
        if (assetIn == toAsset) return assets;

        // Ensure that the asset being swapped to is the asset expected.
        if (assetOut != toAsset) revert USR_InvalidSwap(address(assetOut), address(toAsset));

        // Approve assets to be swapped through the router.
        assetIn.safeApprove(address(swapRouter), assets);

        // Prepare the parameters for the swap.
        uint24 POOL_FEE = 3000;
        bytes memory encodePackedPath = abi.encodePacked(address(assetIn));
        for (uint256 i = 1; i < path.length; i++) {
            encodePackedPath = abi.encodePacked(encodePackedPath, POOL_FEE, path[i]);
        }

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: encodePackedPath,
            recipient: address(this),
            deadline: block.timestamp + 60,
            amountIn: assets,
            amountOutMinimum: assetsOutMin
        });

        // Executes the swap and return the amount out.
        assetsOut = swapRouter.exactInput(params);
    }

    function _emptyPosition(ERC4626 position) internal virtual {
        uint256 sharesOwned = position.balanceOf(address(this));

        if (sharesOwned != 0) {
            PositionData memory positionData = getPositionData[position];

            uint256 assets = convertToAssets(position.asset(), getPositionData[position].assets);

            totalBalance -= assets;
            getPositionData[position].assets = 0;

            uint256 totalPositionAssets = position.redeem(sharesOwned, address(this), address(this));

            uint256 assetsOutMin = assets.mulDivDown(DENOMINATOR - positionData.maxSlippage, DENOMINATOR);
            _swapTo(asset, totalPositionAssets, assetsOutMin, positionData.pathToAsset);
        }
    }

    function _removePosition(ERC4626 position) internal virtual {
        // Pull any assets that were in the removed position to the holding pool.
        _emptyPosition(position);

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
}
