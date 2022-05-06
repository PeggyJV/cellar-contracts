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

abstract contract MultipositionCellar is ERC4626, Ownable {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    // ============================================ ACCOUNTING STATE ============================================

    uint256 public totalBalance;

    // ============================================ HOLDINGS CONFIG ============================================

    // TODO: make adjustable by SP
    // TODO: consider changing default
    uint256 public targetHoldingsPercent = 5_00;

    function setTargetHoldings(uint256 targetPercent) public virtual onlyOwner {
        targetHoldingsPercent = targetPercent;
    }

    // ============================================ ACCRUAL STORAGE ============================================

    // Yield is unlocked gradually over an accrual period to prevent frontrunning and sandwich attacks.

    uint64 public constant accrualPeriod = 7 days;

    uint64 public lastAccrual;

    uint128 public maxLocked;

    // ============================================= FEES CONFIG =============================================

    uint256 public constant DENOMINATOR = 100_00;

    // TODO: have fees read from the default set by the registry
    // TODO: experiment with accruing platform fees from all cellar at once through registry / another module

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

    struct PositionData {
        bool isTrusted;
        uint32 maxSlippage;
        uint112 balance;
        address[] path;
    }

    mapping(ERC4626 => PositionData) public getPositionData;

    function setPositions(ERC4626[] calldata newPositions, address[][] calldata paths) public virtual onlyOwner {
        for (uint256 i; i < newPositions.length; i++) {
            PositionData storage positionData = getPositionData[newPositions[i]];

            // Ensure position is trusted.
            if (!positionData.isTrusted) revert USR_UntrustedPosition(address(newPositions[i]));

            positionData.path = paths[i];
        }

        positions = newPositions;
    }

    function setPositionPath(ERC4626 position, address[] memory path) public virtual onlyOwner {
        getPositionData[position].path = path;
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
        address[][] memory _paths,
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
                path: _paths[i]
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

    // TODO: write more thorough test for withdraws. spidey senses are tingling here
    function beforeWithdraw(uint256 assets, uint256) internal virtual override {
        uint256 currentHoldings = totalHoldings();

        // TODO: make note that when factoring in swap slippage, totalAssets is almost always going
        // to be slightly less than the reported amount (approx. <0.5% less). therefore, there is an
        // invisible "buffer" of the cellar's assets that should be maintained to provide enough exit
        // liquidity for withdraws. think about how to alleviate this

        // Only triggers if there are not enough assets in the holding position to cover the withdraw.
        if (assets > currentHoldings) {
            // The amount needed to cover this withdraw.
            uint256 holdingsMissingForWithdraw = assets - currentHoldings;

            // The amount needed to reach the target holdings percentage.
            uint256 holdingsMissingForTarget = (totalAssets() - assets).mulDivDown(targetHoldingsPercent, DENOMINATOR);

            // Pull enough to cover the withdraw and reach the target holdings percentage.
            uint256 leftToWithdraw = holdingsMissingForWithdraw + holdingsMissingForTarget;

            for (uint256 i = positions.length - 1; ; i--) {
                ERC4626 position = positions[i];
                PositionData memory positionData = getPositionData[position];

                uint256 positionBalance = positionData.balance;

                if (positionBalance == 0) continue;

                // We want to pull as much as we can from the strategy, but no more than we need.
                uint256 assetsToWithdraw = MathUtils.min(positionBalance, leftToWithdraw);

                leftToWithdraw -= assetsToWithdraw;

                _withdrawFromPosition(position, assetsToWithdraw);

                // TODO: make note of vulnerability introduced by SP setting maxSlippage too low and
                // preventing withdraws or too high to be sandwich attacked
                // TODO: make this compatible with positions not all priced in a common denom
                uint256 assetsOutMin = assetsToWithdraw.mulDivDown(DENOMINATOR - positionData.maxSlippage, DENOMINATOR);

                // Perform a swap to the to cellar's asset if necessary.
                address[] memory path = positionData.path;
                if (path[0] != path[path.length - 1]) SwapUtils.swap(assetsToWithdraw, assetsOutMin, path);

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

    function accrue() public virtual onlyOwner {
        uint256 remainingAccrualPeriod = uint256(accrualPeriod).subMin0(block.timestamp - lastAccrual);
        if (remainingAccrualPeriod != 0) revert STATE_AccrualOngoing(remainingAccrualPeriod);

        uint256 yield;
        uint256 currentTotalBalance = totalBalance;

        for (uint256 i = 0; i < positions.length; i++) {
            ERC4626 position = positions[i];

            uint256 lastBalance = getPositionData[position].balance;
            uint256 currentBalance = position.maxWithdraw(address(this));

            getPositionData[position].balance = uint112(currentBalance);

            currentTotalBalance = currentTotalBalance + currentBalance - lastBalance;

            yield += currentBalance.subMin0(lastBalance);
        }

        // Accrue any performance fees as shares minted to the cellar.
        uint256 performanceFeesInAssets = yield.mulDivDown(PERFORMANCE_FEE, DENOMINATOR);
        uint256 performanceFees = convertToShares(performanceFeesInAssets);

        _mint(address(this), performanceFees);

        maxLocked = uint128(totalLocked() + yield - performanceFeesInAssets);

        // Update cellar's total balance.
        totalBalance = currentTotalBalance;

        lastAccrual = uint64(block.timestamp);
    }

    // ======================================== HELPER FUNCTIONS ========================================

    function _depositIntoPosition(ERC4626 position, uint256 assets) internal virtual {
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
