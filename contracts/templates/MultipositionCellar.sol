// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "../interfaces/ERC4626.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC4626 } from "../interfaces/ERC4626.sol";
import { IGravity } from "../interfaces/IGravity.sol";
import { MathUtils } from "../utils/MathUtils.sol";
import { SwapUtils } from "../utils/SwapUtils.sol";

import "../Errors.sol";

/**
 * @title MultipositionCellar
 * @dev Implements the logic of interaction with different positions.
 */
abstract contract MultipositionCellar is ERC4626, Ownable {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    // ============================================ ACCOUNTING STATE ============================================

    /**
     * @notice Cellar total balance.
     */
    uint256 public totalBalance;

    // ============================================ HOLDINGS CONFIG ============================================

    /**
     * @dev Should be set high enough that the holding pool can cover the majority of weekly
     *      withdraw volume without needing to pull from positions. See `beforeWithdraw` for
     *      more information as to why.
     */
    // TODO: consider changing default
    uint256 public targetHoldingsPercent = 5_00;

    /**
     * @notice Sets target holdings percent.
     * @param targetPercent new value of target holdings percent
     */
    function setTargetHoldings(uint256 targetPercent) external virtual onlyOwner {
        targetHoldingsPercent = targetPercent;
    }

    // ============================================ ACCRUAL STORAGE ============================================

    /**
     * @dev Yield is distributed gradually over an accrual period to prevent frontrunning and sandwich attacks.
     *      Losses are realized immediately to prevent users from timing exits to sidestep losses.
     */

    /**
     * @notice Initial value of the accrual period.
     */
    uint32 public accrualPeriod = 7 days;

    /**
     * @notice New value of the accrual period.
     */
    uint32 public nextAccrualPeriod;

    /**
     * @notice Timestamp of last accrual.
     */
    uint64 public lastAccrual;

    /**
     * @notice Maximum amount we could return.
     */
    uint128 public maxLocked;

    /**
     * @notice Sets new accrual period.
     * @param newAccrualPeriod new accrual period
     */
    function setAccrualPeriod(uint32 newAccrualPeriod) external virtual onlyOwner {
        nextAccrualPeriod = newAccrualPeriod;
    }

    // ============================================= FEES CONFIG =============================================

    // TODO: have fees read from the default set by the registry
    // TODO: experiment with accruing platform fees from all cellar at once through registry / another module

    /**
     * @notice The value fees are divided by to get a percentage. Represents the maximum percent (100%).
     */
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

    /**
     * @notice List of ERC4626-compatible positions.
     */
    ERC4626[] public positions;

    /**
     * @notice Gets current positions.
     * @return list of ERC4626-compatible positions
     */
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

    /**
     * @notice Emitted when the position added.
     * @param position the address of the position whose have been added
     */
    event AddPosition(address position);

    /**
     * @notice Emitted when the position removed.
     * @param position the address of the position whose have been removed
     */
    event RemovePosition(address position);

    /**
     * @notice Add position.
     * @param position ERC4626-compatible position to be added
     **/
    function addPosition(ERC4626 position) external virtual onlyOwner {
        if (!getPositionData[position].isTrusted) revert USR_UntrustedPosition(address(position));

        positions.push(position);
        
        emit AddPosition(address(position));
    }

    /**
     * @notice Removes position.
     * @param position ERC4626-compatible position to be removed
     **/
    function removePosition(ERC4626 position) external virtual onlyOwner {
        _removePosition(position);
        
        emit RemovePosition(address(position));
    }

    // TODO: consider moving position funcitons to own module
    /**
     * @notice Sets new positions with paths and max slippages settings.
     * @param newPositions new list of ERC4626-compatible positions
     * @param pathsToAsset the array of swap paths
     * @param maxSlippages the array of maximum slippages values
     */
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

    /**
     * @notice Sets new positions with max slippages setting.
     * @param newPositions new list of ERC4626-compatible positions
     * @param maxSlippages the array of maximum slippages values
     */
    function setPositions(ERC4626[] calldata newPositions, uint32[] calldata maxSlippages) external virtual onlyOwner {
        for (uint256 i; i < newPositions.length; i++) {
            PositionData storage positionData = getPositionData[newPositions[i]];

            // Ensure position is trusted.
            if (!positionData.isTrusted) revert USR_UntrustedPosition(address(newPositions[i]));

            positionData.maxSlippage = maxSlippages[i];
        }

        positions = newPositions;
    }

    /**
     * @notice Sets new positions.
     * @param newPositions new list of ERC4626-compatible positions
     */
    function setPositions(ERC4626[] calldata newPositions) external virtual onlyOwner {
        for (uint256 i; i < newPositions.length; i++)
            // Ensure position is trusted.
            if (!getPositionData[newPositions[i]].isTrusted) revert USR_UntrustedPosition(address(newPositions[i]));

        positions = newPositions;
    }

    /**
     * @notice Sets position swap path to asset.
     * @param position ERC4626-compatible position
     * @param pathToAsset list of addresses that specify the position swap path to asset
     */
    function setPathToAsset(ERC4626 position, address[] memory pathToAsset) external virtual onlyOwner {
        getPositionData[position].pathToAsset = pathToAsset;
    }

    /**
     * @notice Sets position max slippage.
     * @param position ERC4626-compatible position
     * @param maxSlippage value of the max slippage
     */
    function setMaxSlippage(ERC4626 position, uint32 maxSlippage) external virtual onlyOwner {
        getPositionData[position].maxSlippage = maxSlippage;
    }

    /**
     * @notice Sets position trust.
     * @param position ERC4626-compatible position
     * @param isTrusted true to set position as trusted
     */
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

    /**
     * @notice Sets the maximum liquidity that cellar can manage.
     *         Careful to use the same decimals as the current asset.
     * @param limit amount the limit
     */
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

    /**
     * @notice Sets the per-wallet deposit limit.
     *         Careful to use the same decimals as the current asset.
     * @param limit amount the limit
     */
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
     * @notice Emitted when cellar contract is shutdown or started after shutdown.
     * @param isShutdown whether the contract is shutdown
     * @param exitPositions whether to exit all current positions
     */
    event Shutdown(bool isShutdown, bool exitPositions);

    /**
     * @notice Stop or start the contract. Used in an emergency or if the cellar has been depreciated.
     * @param shutdown true so that the contract is shutdown
     * @param exitPositions true to exit all current positions
     */
    function setShutdown(bool shutdown, bool exitPositions) external virtual onlyOwner {
        isShutdown = shutdown;

        // Exit all positions.
        if (shutdown && exitPositions) for (uint256 i; i < positions.length; i++) _emptyPosition(positions[i]);
        
        emit Shutdown(shutdown, exitPositions);
    }

    // =========================================== CONSTRUCTOR ===========================================

    // TODO: have cellar read gravity address from registry instead of declaring it within every contract
    /**
     * @notice Cosmos Gravity Bridge contract. Used to transfer fees to `feeDistributor` on the Sommelier chain.
     */
    IGravity public immutable gravityBridge = IGravity(0x69592e6f9d21989a043646fE8225da2600e5A0f7);

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
        uint32[] memory _maxSlippages, // Recommended default is 1%.
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC4626(_asset, _name, _symbol, _decimals) Ownable() {
        positions = _positions;

        // Set holding limits for each position and trust all initial positions.
        for (uint256 i; i < _positions.length; i++)
            getPositionData[_positions[i]] = PositionData({
                isTrusted: true,
                maxSlippage: _maxSlippages[i],
                assets: 0,
                pathToAsset: _pathsToAsset[i]
            });

        // Transfer ownership to the Gravity Bridge.
        transferOwnership(address(gravityBridge));
    }

    // ========================================= ACCOUNTING LOGIC =========================================

    /**
     * @notice Gets total assets.
     * @return the amount of total assets
     */
    function totalAssets() public view virtual override returns (uint256) {
        return totalBalance - totalLocked() + totalHoldings();
    }

    /**
     * @notice Gets total holdings.
     * @return the amount of total holdings
     */
    function totalHoldings() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @notice Gets how much yield remains locked.
     * @return the amount of locked yield
     */
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
     * @notice Price assets in another asset denomination.
     * @param fromAsset the address of asset to be converted
     * @param toAsset the address of asset to which to convert
     * @param assets the amount of assets
     * @return the amount of assets in another asset denomination
     */
    function priceAssetsFrom(
        ERC20 fromAsset,
        ERC20 toAsset,
        uint256 assets
    ) public view virtual returns (uint256);

    // =========================================== CORE LOGIC ===========================================
    
    /**
     * @notice Emitted on rebalance of position.
     * @param fromPosition the address of the position whose assets have been rebalanced
     * @param toPosition the address of the position into which assets have been rebalanced
     * @param assetsFrom the amount of assets that has been rebalanced
     * @param assetsTo the amount of the assets received from swap has after rebalancing
     */
    event Rebalance(
        address indexed fromPosition,
        address indexed toPosition,
        uint256 assetsFrom,
        uint256 assetsTo
    );    

    /**
     * @notice Internal hook before deposit to position
     * @param assets the amount of assets to deposit
     * @param receiver address receiving the shares
     */
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
     * @notice Internal hook before withdraw
     * @dev Although this behavior is not desired, it should be noted that attempting to withdraw
     *       exactly the cellar's total assets from positions using a different underlying asset as
     *       the holding position will likely revert due to a discrepency in the total assets
     *       reported by the cellar and the total assets that can actually be withdrawn when swap
     *       slippage is factored in. In this case, the withdrawn amount needed to empty the cellar
     *       (or get as close as possible to it) would need to factor in swap slippage.  Normal
     *       withdraws, luckily, do not need to worry about this. If the holding position cannot
     *       already cover a withdraw in full, the cellar will withdraw an excess amount from
     *       positions until it can cover not just that single withdraw but also subsequent
     *       withdraws up to configurable target. This is much more economic for users as it batches
     *       withdraws instead of doing potentially hundreds of withdraws from positions.
     * @param assets the amount of assets
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
                uint256 exchangeRate = priceAssetsFrom(position.asset(), asset, onePositionAsset);

                // We want to pull as much as we can from this position, but no more than needed.
                // TODO: test rounding here
                uint256 positionAssetsWithdrawn = MathUtils.min(
                    totalPositionAssets,
                    leftToWithdraw.mulDivUp(exchangeRate, onePositionAsset)
                );
                uint256 assetsWithdrawn = positionAssetsWithdrawn.mulDivDown(exchangeRate, 10**decimals);

                leftToWithdraw -= assetsWithdrawn;

                // Pull from this position.
                _withdrawFromPosition(position, positionAssetsWithdrawn);

                // Minimum assets to receive from swap based on the max slippage set for this position.
                uint256 assetsOutMin = assetsWithdrawn.mulDivDown(DENOMINATOR - positionData.maxSlippage, DENOMINATOR);

                // Perform a swap to holding position asset if necessary.
                _swap(asset, positionAssetsWithdrawn, assetsOutMin, positionData.pathToAsset);

                if (leftToWithdraw == 0) break;
            }
        }
    }

    /**
     * @notice Rebalances the selected asset position to another asset position.
     * @param fromPosition position whose assets will be rebalanced
     * @param toPosition the position into which assets will be rebalanced
     * @param assetsFrom the amount of assets to be rebalanced
     * @param assetsToMin the minimum amount of assets received from swap
     * @param path list of addresses that specify the swap path on Uniswap V3
     * @return assetsTo amount of assets received from swap
     */
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
        assetsTo = _swap(toPosition.asset(), assetsFrom, assetsToMin, path);

        // Deposit to destination if it is not the holding position.
        if (address(toPosition) != address(this)) _depositIntoPosition(toPosition, assetsTo);

        emit Rebalance(address(fromPosition), address(toPosition), assetsFrom, assetsTo);
    }

    // ============================================ LIMITS LOGIC ============================================

    /**
     * @notice Total number of assets that can be deposited by owner into the cellar.
     * @param owner address of account that would receive the shares
     * @return maximum amount of assets that can be deposited
     */
    function maxDeposit(address owner) public view virtual override returns (uint256) {
        if (isShutdown) return 0;

        if (depositLimit == type(uint256).max && liquidityLimit == type(uint256).max) return type(uint256).max;

        uint256 leftUntilDepositLimit = depositLimit.subFloor(maxWithdraw(owner));
        uint256 leftUntilLiquidityLimit = liquidityLimit.subFloor(totalAssets());

        // Only return the more relevant of the two.
        return MathUtils.min(leftUntilDepositLimit, leftUntilLiquidityLimit);
    }

    /**
     * @notice Total number of shares that can be minted for owner from the cellar.
     * @param owner address of account that would receive the shares
     * @return maximum amount of shares that can be minted
     */
    function maxMint(address owner) public view virtual override returns (uint256) {
        if (isShutdown) return 0;

        if (depositLimit == type(uint256).max && liquidityLimit == type(uint256).max) return type(uint256).max;

        uint256 leftUntilDepositLimit = depositLimit.subFloor(maxWithdraw(owner));
        uint256 leftUntilLiquidityLimit = liquidityLimit.subFloor(totalAssets());

        // Only return the more relevant of the two.
        return convertToShares(MathUtils.min(leftUntilDepositLimit, leftUntilLiquidityLimit));
    }

    // =========================================== ACCRUAL LOGIC ===========================================

    /**
     * @notice Emitted when performance fees accrued.
     * @param performanceFees amount of fees accrued on positive performance
     */
    event AccruedPerformanceFees(uint256 performanceFees);

    /**
     * @dev Accrual with positive performance will accrue yield, accrue fees, and start an accrual
     *      period over which yield is linearly distributed over the entirety of that period. Accrual
     *      with negative performance will realize losses immediately, accrue no fees, and not start an
     *      accrual period. Accrual with no performance will accrue no yield, accrue no fees, and not
     *      start an accrual period.
     */
    function accrue() external virtual onlyOwner {
        uint256 remainingAccrualPeriod = uint256(accrualPeriod).subFloor(block.timestamp - lastAccrual);
        if (remainingAccrualPeriod != 0) revert STATE_AccrualOngoing(remainingAccrualPeriod);

        uint256 yield;
        uint256 currentTotalBalance = totalBalance;

        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];

            uint256 lastPositionAssets = getPositionData[position].assets;
            uint256 currentPositionAssets = position.maxWithdraw(address(this));

            getPositionData[position].assets = uint112(currentPositionAssets);

            uint256 oneAsset = 10**decimals;
            uint256 exchangeRate = priceAssetsFrom(asset, position.asset(), oneAsset);

            uint256 lastAssets = lastPositionAssets.mulDivDown(exchangeRate, oneAsset);
            uint256 currentAssets = currentPositionAssets.mulDivDown(exchangeRate, oneAsset);

            currentTotalBalance = currentTotalBalance + currentAssets - lastAssets;

            yield += currentAssets.subFloor(lastAssets);
        }

        if (yield != 0) {
            // Accrue any performance fees as shares minted to the cellar.
            uint256 performanceFeesInAssets = yield.mulDivDown(PERFORMANCE_FEE, DENOMINATOR);
            uint256 performanceFees = convertToShares(performanceFeesInAssets);

            _mint(address(this), performanceFees);

            emit AccruedPerformanceFees(performanceFees);

            maxLocked = uint128(totalLocked() + yield - performanceFeesInAssets);

            lastAccrual = uint64(block.timestamp);
        }

        // Update cellar's total balance.
        totalBalance = currentTotalBalance;

        // Update the accrual period if it was changed.
        uint32 newAccrualPeriod = nextAccrualPeriod;
        if (newAccrualPeriod != 0) {
            accrualPeriod = newAccrualPeriod;

            nextAccrualPeriod = 0;
        }
    }

    // =========================================== FEE LOGIC ===========================================

    /**
     * @notice Amount of performance fees that have been accrued awaiting transfer.
     * @dev Fees are taken in shares and redeemed for assets at the time they are transferred from
     *      the cellar to Cosmos to be distributed.
     * @return accrued performance fees
     */
    function accruedPerformanceFees() public view virtual returns (uint256) {
        return balanceOf[address(this)];
    }

    // ======================================== HELPER FUNCTIONS ========================================

    /**
     * @notice Emitted when tokens accidentally sent to cellar are recovered.
     * @param token the address of the token
     * @param amount amount transferred out
     * @param to the address sweeped tokens were transferred to
     */
    event Sweep(address indexed token, uint256 amount, address indexed to);

    /**
     * @notice Sweep tokens sent here that are not managed by the cellar.
     * @dev This may be used in case the wrong tokens are accidentally sent to this contract.
     * @param token address of token to transfer out of this cellar
     * @param amount amount of token to transfer
     * @param to address to transfer sweeped tokens to
     */
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
        
        emit Sweep(token, amount, to);
    }

    // ======================================== INTERNAL HOOKS ========================================

    /**
     * @notice Deposits into an ERC4626-compatible position.
     * @param position ERC4626-compatible position for deposit
     * @param positionAssets amount of deposit assets
     */
    function _depositIntoPosition(ERC4626 position, uint256 positionAssets) internal virtual {
        if (!getPositionData[position].isTrusted) revert USR_UntrustedPosition(address(position));
        if (isShutdown) revert STATE_ContractShutdown();

        getPositionData[position].assets += uint112(positionAssets);
        ERC20 positionAsset = position.asset();
        // TODO: test rounding here
        totalBalance += priceAssetsFrom(positionAsset, asset, positionAssets);

        positionAsset.safeApprove(address(position), positionAssets);
        position.deposit(positionAssets, address(this));
    }

    /**
     * @notice Withdraws from an ERC4626-compatible position.
     * @param position ERC4626-compatible position to withdrawal
     * @param positionAssets amount of assets to withdrawal
     */
    function _withdrawFromPosition(ERC4626 position, uint256 positionAssets) internal virtual {
        getPositionData[position].assets -= uint112(positionAssets);
        // TODO: test rounding here
        totalBalance -= priceAssetsFrom(position.asset(), asset, positionAssets);

        position.withdraw(positionAssets, address(this), address(this));
    }

    /**
     * @notice Swaps assets.
     * @param positionAsset asset that the position expects to receive from swap
     * @param assets amount of the incoming token
     * @param assetsOutMin minimum value of the outgoing token
     * @param path list of addresses that specify the swap path
     * @return actual received amount of outgoing token (>=assetsOutMin)
     **/
    function _swap(
        ERC20 positionAsset,
        uint256 assets,
        uint256 assetsOutMin,
        address[] memory path
    ) internal virtual returns (uint256) {
        return SwapUtils.safeSwap(positionAsset, assets, assetsOutMin, path);
    }

    /**
     * @notice Pulls any assets that were in the removed position to the holding pool.
     * @param position the removed position
     **/
    function _emptyPosition(ERC4626 position) internal virtual {
        uint256 sharesOwned = position.balanceOf(address(this));

        if (sharesOwned != 0) {
            PositionData memory positionData = getPositionData[position];

            uint256 assets = priceAssetsFrom(position.asset(), asset, getPositionData[position].assets);

            totalBalance -= assets;
            getPositionData[position].assets = 0;

            uint256 totalPositionAssets = position.redeem(sharesOwned, address(this), address(this));

            uint256 assetsOutMin = assets.mulDivDown(DENOMINATOR - positionData.maxSlippage, DENOMINATOR);
            _swap(asset, totalPositionAssets, assetsOutMin, positionData.pathToAsset);
        }
    }

    /**
     * @notice Internal function to remove position
     * @param position ERC4626-compatible position to be removed
     **/
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
