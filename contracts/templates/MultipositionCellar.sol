// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "../interfaces/ERC4626.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC4626 } from "../interfaces/ERC4626.sol";
import { IGravity } from "../interfaces/IGravity.sol";
import { MathUtils } from "../utils/MathUtils.sol";
import { SwapUtils } from "../utils/SwapUtils.sol";

import "../Errors.sol";

// TODO: price all balances according to cellar's `asset` (the common denom)
// TODO: add extensive documentation for cellar creators
// TODO: add sweep
// TODO: add events

// TODO: delete
import "hardhat/console.sol";

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

    function setTargetHoldings(uint256 targetPercent) public virtual onlyOwner {
        targetHoldingsPercent = targetPercent;
    }

    // ============================================ ACCRUAL STORAGE ============================================

    /**
     * @dev Yield is distributed gradually over an accrual period to prevent frontrunning and sandwich attacks.
     *      Losses are realized immediately to prevent users from timing exits to sidestep losses.
     */

    // TODO: consider changing default accrual period and have it be configuarable
    uint64 public constant accrualPeriod = 7 days;

    uint64 public lastAccrual;

    uint128 public maxLocked;

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
        uint112 balance;
        address[] pathToAsset;
    }

    mapping(ERC4626 => PositionData) public getPositionData;

    function setPositions(ERC4626[] calldata newPositions, address[][] calldata pathsToAsset) public virtual onlyOwner {
        for (uint256 i; i < newPositions.length; i++) {
            PositionData storage positionData = getPositionData[newPositions[i]];

            // Ensure position is trusted.
            if (!positionData.isTrusted) revert USR_UntrustedPosition(address(newPositions[i]));

            positionData.pathToAsset = pathsToAsset[i];
        }

        positions = newPositions;
    }

    function setPositionPath(ERC4626 position, address[] memory pathToAsset) public virtual onlyOwner {
        getPositionData[position].pathToAsset = pathToAsset;
    }

    function setPositionMaxSlippage(ERC4626 position, uint32 maxSlippage) public virtual onlyOwner {
        getPositionData[position].maxSlippage = maxSlippage;
    }

    function setTrust(ERC4626 position, bool trust) public virtual onlyOwner {
        getPositionData[position].isTrusted = trust;

        // Remove the untrusted position.
        if (!trust) {
            for (uint256 i; i < positions.length; i++) {
                if (positions[i] == position) {
                    for (i; i < positions.length - 1; i++) positions[i] = positions[i + 1];

                    positions.pop();

                    break;
                }
            }
        }
    }

    // ====================================== CELLAR LIMIT LOGIC ======================================

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

    function setLiquidityLimit(uint256 limit) public virtual onlyOwner {
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

    function setDepositLimit(uint256 limit) public virtual onlyOwner {
        // Store for emitted event.
        uint256 oldLimit = depositLimit;

        // Change the deposit limit.
        depositLimit = limit;

        emit DepositLimitChanged(oldLimit, limit);
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
                balance: 0,
                pathToAsset: _pathsToAsset[i]
            });

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

    // =========================================== CORE LOGIC ===========================================

    /**
     *  @dev Although this behavior is not desired, it should be noted that attempting to withdraw
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
     */
    function beforeWithdraw(uint256 assets, uint256) internal virtual override {
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

                uint256 positionBalance = positionData.balance;

                // Move on if this position is empty.
                if (positionBalance == 0) continue;

                // We want to pull as much as we can from the strategy, but no more than needed.
                uint256 assetsToWithdraw = MathUtils.min(positionBalance, leftToWithdraw);
                leftToWithdraw -= assetsToWithdraw;

                // Withdraw and update position balances accordingly.
                getPositionData[position].balance -= uint112(assetsToWithdraw);
                position.withdraw(assetsToWithdraw, address(this), address(this));

                // TODO: make this compatible with positions not all priced in a common denom
                uint256 assetsOutMin = assetsToWithdraw.mulDivDown(DENOMINATOR - positionData.maxSlippage, DENOMINATOR);

                // If necessary, perform a swap to the to cellar's asset.
                address[] memory path = positionData.pathToAsset;
                if (path[0] != path[path.length - 1]) SwapUtils.swap(assetsToWithdraw, assetsOutMin, path);

                if (leftToWithdraw == 0) break;
            }

            totalBalance -= assets;
        }
    }

    function rebalance(
        ERC4626 fromPosition,
        ERC4626 toPosition,
        uint256 assetsFrom,
        uint256 assetsToMin,
        address[] memory path
    ) public virtual onlyOwner returns (uint256 assetsTo) {
        // Skip withdraw if rebalancing from holding position.
        if (address(fromPosition) != address(this)) _withdrawFromPosition(fromPosition, assetsFrom);

        // Performing a swap to the receiving position's asset if necessary.
        assetsTo = ERC20(path[0]) != ERC20(path[path.length - 1])
            ? SwapUtils.swap(assetsFrom, assetsToMin, path)
            : assetsFrom;

        // Skip deposit if rebalancing to holding position.
        if (address(toPosition) != address(this)) _depositIntoPosition(toPosition, assetsTo);
    }

    // ========================================= ACCRUAL LOGIC =========================================

    /**
     * @dev Accrual with positive performance will accrue yield, accrue fees, and start an accrual
     *      period over which yield is linearly distributed over the entirety of that period. Accrual
     *      with negative performance will realize losses immediately, accrue no fees, and not start an
     *      accrual period. Accrual with no performance will accrue no yield, accrue no fees, and not
     *      start an accrual period.
     */
    function accrue() public virtual onlyOwner {
        uint256 remainingAccrualPeriod = uint256(accrualPeriod).subMin0(block.timestamp - lastAccrual);
        if (remainingAccrualPeriod != 0) revert STATE_AccrualOngoing(remainingAccrualPeriod);

        uint256 yield;
        uint256 currentTotalBalance = totalBalance;

        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = positions[i];

            uint256 lastBalance = getPositionData[position].balance;
            uint256 currentBalance = position.maxWithdraw(address(this));

            getPositionData[position].balance = uint112(currentBalance);

            currentTotalBalance = currentTotalBalance + currentBalance - lastBalance;

            yield += currentBalance.subMin0(lastBalance);
        }

        if (yield != 0) {
            // Accrue any performance fees as shares minted to the cellar.
            uint256 performanceFeesInAssets = yield.mulDivDown(PERFORMANCE_FEE, DENOMINATOR);
            uint256 performanceFees = convertToShares(performanceFeesInAssets);

            _mint(address(this), performanceFees);

            maxLocked = uint128(totalLocked() + yield - performanceFeesInAssets);

            lastAccrual = uint64(block.timestamp);
        }

        // Update cellar's total balance.
        totalBalance = currentTotalBalance;
    }

    // =========================================== FEE LOGIC ===========================================

    function accruedPerformanceFees() public view virtual returns (uint256) {
        return balanceOf[address(this)];
    }

    // ======================================== HELPER FUNCTIONS ========================================

    function _depositIntoPosition(ERC4626 position, uint256 assets) internal virtual {
        if (!getPositionData[position].isTrusted) revert USR_UntrustedPosition(address(position));

        getPositionData[position].balance += uint112(assets);
        totalBalance += assets;

        position.asset().safeApprove(address(position), assets);
        position.deposit(assets, address(this));
    }

    function _withdrawFromPosition(ERC4626 position, uint256 assets) internal virtual {
        getPositionData[position].balance -= uint112(assets);
        totalBalance -= assets;

        position.withdraw(assets, address(this), address(this));
    }
}
