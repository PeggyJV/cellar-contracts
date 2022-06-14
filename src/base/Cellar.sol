// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC4626, ERC20 } from "./ERC4626.sol";
import { Multicall } from "./Multicall.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Registry } from "../Registry.sol";
import { IGravity } from "../interfaces/IGravity.sol";
import { AddressArray } from "src/utils/AddressArray.sol";
import { Math } from "../utils/Math.sol";

import "../Errors.sol";

contract Cellar is ERC4626, Ownable, Multicall {
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

    enum PositionType {
        ERC20,
        ERC4626
    }

    struct PositionData {
        PositionType positionType;
        bool isLossless;
        uint256 balance;
        address[] pathToAsset; // Left empty if position either is (if ERC20) or uses (if ERC4626) same asset as cellar.
    }

    address[] public positions;

    mapping(address => PositionData) public getPositionData;

    function getPositions() external view returns (address[] memory) {
        return positions;
    }

    function isPositionUsed(address position) public view returns (bool) {
        return positions.contains(position);
    }

    function isPositionUsingSameAsset(address position) public view returns (bool) {
        return getPositionData[position].pathToAsset.length == 0;
    }

    function addPosition(uint256 index, address position) public onlyOwner whenNotShutdown {
        if (!isTrusted[position]) revert USR_UntrustedPosition(position);

        // Add new position at a specified index.
        positions.add(index, position);

        emit PositionAdded(position, index);
    }

    /**
     * @dev If you know you are going to add a position to the end of the array, this is more
     *      efficient then `addPosition`.
     */
    function pushPosition(address position) public onlyOwner whenNotShutdown {
        if (!isTrusted[position]) revert USR_UntrustedPosition(position);

        // Check if position is already being used.
        if (isPositionUsed(position)) revert USR_PositionAlreadyUsed(position);

        // Add new position to the end of the positions.
        positions.push(position);

        emit PositionAdded(position, positions.length - 1);
    }

    function removePosition(uint256 index) public onlyOwner {
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
    function popPosition() public onlyOwner {
        // Get the index of the last position and last position itself.
        uint256 index = positions.length - 1;
        address position = positions[index];

        // Remove last position.
        positions.pop();

        // Pull any assets that were in the removed position to the holding pool.
        _emptyPosition(position);

        emit PositionRemoved(position, index);
    }

    function replacePosition(address newPosition, uint256 index) public onlyOwner whenNotShutdown {
        // Store the old position before its replaced.
        address oldPosition = positions[index];

        // Replace old position with new position.
        positions[index] = newPosition;

        // Pull any assets that were in the old position to the holding pool.
        _emptyPosition(oldPosition);

        emit PositionReplaced(oldPosition, newPosition, index);
    }

    function swapPositions(uint256 index1, uint256 index2) public onlyOwner {
        // Get the new positions that will be at each index.
        address newPosition1 = positions[index2];
        address newPosition2 = positions[index1];

        // Swap positions.
        (positions[index1], positions[index2]) = (newPosition1, newPosition2);

        emit PositionSwapped(newPosition1, newPosition2, index1, index2);
    }

    // ============================================ TRUST CONFIG ============================================

    /**
     * @notice Emitted when trust for a position is changed.
     * @param position address of position that trust was changed for
     * @param isTrusted whether the position is trusted
     */
    event TrustChanged(address indexed position, bool isTrusted);

    mapping(address => bool) public isTrusted;

    function trustPosition(
        address position,
        PositionType positionType,
        bool isLossless
    ) public onlyOwner {
        // Trust position.
        isTrusted[position] = true;

        // Set position type and lossless flag.
        PositionData storage positionData = getPositionData[position];
        positionData.positionType = positionType;
        positionData.isLossless = isLossless;

        // Set max approval to deposit into position if it is ERC4626.
        if (positionType == PositionType.ERC4626) ERC4626(position).asset().safeApprove(position, type(uint256).max);

        emit TrustChanged(position, true);
    }

    function distrustPosition(address position) public onlyOwner {
        // Distrust position.
        isTrusted[position] = false;

        // Remove position from the list of positions if it is present.
        positions.remove(position);

        // Pull any assets that were in the removed position to the holding pool.
        _emptyPosition(position);

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
    uint256 public targetHoldingsPercent;

    function setTargetHoldings(uint256 targetPercent) external onlyOwner {
        targetHoldingsPercent = targetPercent;
    }

    // ========================================= FEES CONFIG =========================================

    /**
     * @notice Emitted when platform fees is changed.
     * @param oldPlatformFee value platform fee was changed from
     * @param newPlatformFee value platform fee was changed to
     */
    event PlatformFeeChanged(uint64 oldPlatformFee, uint64 newPlatformFee);

    /**
     * @notice Emitted when performance fees is changed.
     * @param oldPerformanceFee value performance fee was changed from
     * @param newPerformanceFee value performance fee was changed to
     */
    event PerformanceFeeChanged(uint64 oldPerformanceFee, uint64 newPerformanceFee);

    /**
     * @notice Emitted when fees distributor is changed.
     * @param oldFeesDistributor address of fee distributor was changed from
     * @param newFeesDistributor address of fee distributor was changed to
     */
    event FeesDistributorChanged(bytes32 oldFeesDistributor, bytes32 newFeesDistributor);

    /**
     *  @notice The percentage of yield accrued as performance fees.
     *  @dev This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     */
    uint64 public platformFee = 0.01e18; // 1%

    /**
     * @notice The percentage of total assets accrued as platform fees over a year.
     * @dev This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     */
    uint64 public performanceFee = 0.1e18; // 10%

    /**
     * @notice Cosmos address of module that distributes fees, specified as a hex value.
     * @dev The Gravity contract expects a 32-byte value formatted in a specific way.
     */
    bytes32 public feesDistributor = hex"000000000000000000000000b813554b423266bbd4c16c32fa383394868c1f55";

    /**
     * @notice Set the percentage of platform fees accrued over a year.
     * @param newPlatformFee value out of 1e18 that represents new platform fee percentage
     */
    function setPlatformFee(uint64 newPlatformFee) external onlyOwner {
        emit PlatformFeeChanged(platformFee, newPlatformFee);

        platformFee = newPlatformFee;
    }

    /**
     * @notice Set the percentage of performance fees accrued from yield.
     * @param newPerformanceFee value out of 1e18 that represents new performance fee percentage
     */
    function setPerformanceFee(uint64 newPerformanceFee) external onlyOwner {
        emit PerformanceFeeChanged(performanceFee, newPerformanceFee);

        performanceFee = newPerformanceFee;
    }

    /**
     * @notice Set the address of the fee distributor on the Sommelier chain.
     * @dev IMPORTANT: Ensure that the address is formatted in the specific way that the Gravity contract
     *      expects it to be.
     * @param newFeesDistributor formatted address of the new fee distributor module
     */
    function setFeesDistributor(bytes32 newFeesDistributor) external onlyOwner {
        emit FeesDistributorChanged(feesDistributor, newFeesDistributor);

        feesDistributor = newFeesDistributor;
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
     * @notice Maximum amount of assets per wallet. Denominated in the same decimals as the current asset.
     * @dev Set to `type(uint256).max` to have no limit.
     */
    uint256 public depositLimit = type(uint256).max;

    /**
     * @notice Set the maximum liquidity that cellar can manage. Uses the same decimals as the current asset.
     * @param newLimit amount of assets to set as the new limit
     */
    function setLiquidityLimit(uint256 newLimit) external onlyOwner {
        emit LiquidityLimitChanged(liquidityLimit, newLimit);

        liquidityLimit = newLimit;
    }

    /**
     * @notice Set the per-wallet deposit limit. Uses the same decimals as the current asset.
     * @param newLimit amount of assets to set as the new limit
     */
    function setDepositLimit(uint256 newLimit) external onlyOwner {
        emit DepositLimitChanged(depositLimit, newLimit);

        depositLimit = newLimit;
    }

    // =========================================== EMERGENCY LOGIC ===========================================

    /**
     * @notice Emitted when cellar emergency state is changed.
     * @param isShutdown whether the cellar is shutdown
     */
    event ShutdownChanged(bool isShutdown);

    /**
     * @notice Whether or not the contract is shutdown in case of an emergency.
     */
    bool public isShutdown;

    /**
     * @notice Prevent a function from being called during a shutdown.
     */
    modifier whenNotShutdown() {
        if (isShutdown) revert STATE_ContractShutdown();

        _;
    }

    /**
     * @notice Shutdown the cellar. Used in an emergency or if the cellar has been deprecated.
     * @dev In the case where
     */
    function initiateShutdown() public whenNotShutdown onlyOwner {
        isShutdown = true;

        emit ShutdownChanged(true);
    }

    /**
     * @notice Restart the cellar.
     */
    function liftShutdown() public onlyOwner {
        isShutdown = false;

        emit ShutdownChanged(false);
    }

    // =========================================== CONSTRUCTOR ===========================================

    // TODO: since registry address should never change, consider hardcoding the address once
    //       registry is finalized and making this a constant
    Registry public immutable registry;

    /**
     * @dev Owner should be set to the Gravity Bridge, which relays instructions from the Steward
     *      module to the cellars.
     *      https://github.com/PeggyJV/steward
     *      https://github.com/cosmos/gravity-bridge/blob/main/solidity/contracts/Gravity.sol
     * @param _asset address of underlying token used for the for accounting, depositing, and withdrawing
     * @param _name name of this cellar's share token
     * @param _name symbol of this cellar's share token
     */
    constructor(
        Registry _registry,
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _name, _symbol, 18) Ownable() {
        registry = _registry;

        // Transfer ownership to the Gravity Bridge.
        transferOwnership(_registry.gravityBridge());
    }

    // =========================================== CORE LOGIC ===========================================

    function beforeDeposit(
        uint256 assets,
        uint256,
        address receiver
    ) internal view override whenNotShutdown {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) revert USR_DepositRestricted(assets, maxAssets);
    }

    // ========================================= ACCOUNTING LOGIC =========================================

    function denominateInAsset(address token, uint256 amount) public view returns (uint256 assets) {}

    /**
     * @notice The total amount of assets in the cellar.
     * @dev Excludes locked yield that hasn't been distributed.
     */
    function totalAssets() public view override returns (uint256 assets) {
        for (uint256 i; i < positions.length; i++) {
            address position = positions[i];

            if (getPositionData[position].isLossless) assets += ERC4626(position).maxWithdraw(address(this));
        }

        assets += totalLosslessBalance + totalHoldings() - totalLocked();
    }

    /**
     * @notice The total amount of assets in holding position.
     */
    function totalHoldings() public view returns (uint256) {
        return asset.balanceOf(address(this));
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

    // =========================================== ACCRUAL LOGIC ===========================================

    /**
     * @notice Emitted on accruals.
     * @param platformFees amount of shares minted as platform fees this accrual
     * @param performanceFees amount of shares minted as performance fees this accrual
     */
    event Accrual(uint256 platformFees, uint256 performanceFees);

    /**
     * @notice Accrue platform fees and performance fees. May also accrue yield.
     */
    function accrue() public {
        uint256 totalLockedYield = totalLocked();

        // Without this check, malicious actors could do a slowdown attack on the distribution of
        // yield by continuously resetting the accrual period.
        if (msg.sender != owner() && totalLockedYield > 0) revert STATE_AccrualOngoing();

        uint256 totalBalanceLastAccrual = totalLosslessBalance;
        uint256 totalBalanceThisAccrual;

        uint256 newTotalLosslessBalance;

        for (uint256 i; i < positions.length; i++) {
            address position = positions[i];
            PositionData storage positionData = getPositionData[position];

            uint256 balanceThisAccrual = positionData.positionType == PositionType.ERC4626
                ? ERC4626(position).maxWithdraw(address(this))
                : ERC20(position).balanceOf(address(this));

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

        totalLosslessBalance = newTotalLosslessBalance;

        emit Accrual(platformFees, performanceFees);
    }

    // =========================================== POSITION LOGIC ===========================================

    // TODO: add enterPosition, exitPosition, and rebalance functions

    // ============================================ LIMITS LOGIC ============================================

    /**
     * @notice Total amount of assets that can be deposited for a user.
     * @param receiver address of account that would receive the shares
     * @return assets maximum amount of assets that can be deposited
     */
    function maxDeposit(address receiver) public view override returns (uint256 assets) {
        if (isShutdown) return 0;

        uint256 asssetDepositLimit = depositLimit;
        uint256 asssetLiquidityLimit = liquidityLimit;
        if (asssetDepositLimit == type(uint256).max && asssetLiquidityLimit == type(uint256).max)
            return type(uint256).max;

        uint256 leftUntilDepositLimit = asssetDepositLimit.subMinZero(maxWithdraw(receiver));
        uint256 leftUntilLiquidityLimit = asssetLiquidityLimit.subMinZero(totalAssets());

        // Only return the more relevant of the two.
        assets = Math.min(leftUntilDepositLimit, leftUntilLiquidityLimit);
    }

    /**
     * @notice Total amount of shares that can be minted for a user.
     * @param receiver address of account that would receive the shares
     * @return shares maximum amount of shares that can be minted
     */
    function maxMint(address receiver) public view override returns (uint256 shares) {
        if (isShutdown) return 0;

        uint256 asssetDepositLimit = depositLimit;
        uint256 asssetLiquidityLimit = liquidityLimit;
        if (asssetDepositLimit == type(uint256).max && asssetLiquidityLimit == type(uint256).max)
            return type(uint256).max;

        uint256 leftUntilDepositLimit = asssetDepositLimit.subMinZero(maxWithdraw(receiver));
        uint256 leftUntilLiquidityLimit = asssetLiquidityLimit.subMinZero(totalAssets());

        // Only return the more relevant of the two.
        shares = convertToShares(Math.min(leftUntilDepositLimit, leftUntilLiquidityLimit));
    }

    // ========================================= FEES LOGIC =========================================

    /**
     * @notice Emitted when platform fees are send to the Sommelier chain.
     * @param feesInSharesRedeemed amount of fees redeemed for assets to send
     * @param feesInAssetsSent amount of assets fees were redeemed for that were sent
     */
    event SendFees(uint256 feesInSharesRedeemed, uint256 feesInAssetsSent);

    /**
     * @notice Transfer accrued fees to the Sommelier chain to distribute.
     * @dev Fees are accrued as shares and redeemed upon transfer.
     */
    function sendFees() public onlyOwner {
        // Redeem our fee shares for assets to send to the fee distributor module.
        uint256 totalFees = balanceOf[address(this)];
        uint256 assets = previewRedeem(totalFees);
        require(assets != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, 0, address(0), address(0));

        _burn(address(this), totalFees);

        // Transfer assets to a fee distributor on the Sommelier chain.
        IGravity gravityBridge = IGravity(registry.gravityBridge());
        asset.safeApprove(address(gravityBridge), assets);
        gravityBridge.sendToCosmos(address(asset), feesDistributor, assets);

        emit SendFees(totalFees, assets);
    }

    // ========================================== RECOVERY LOGIC ==========================================

    /**
     * @notice Emitted when tokens accidentally sent to cellar are recovered.
     * @param token the address of the token
     * @param to the address sweeped tokens were transferred to
     * @param amount amount transferred out
     */
    event Sweep(address indexed token, address indexed to, uint256 amount);

    function sweep(
        ERC20 token,
        address to,
        uint256 amount
    ) public onlyOwner {
        // Prevent sweeping of assets managed by the cellar and shares minted to the cellar as fees.
        if (token == asset || token == this) revert USR_ProtectedAsset(address(token));

        // Transfer out tokens in this cellar that shouldn't be here.
        token.safeTransfer(to, amount);

        emit Sweep(address(token), to, amount);
    }

    // ======================================== HELPER FUNCTIONS ========================================

    function _emptyPosition(address position) internal {
        PositionData storage positionData = getPositionData[position];

        uint256 balanceLastAccrual = positionData.balance;
        uint256 balanceThisAccrual;

        // uint256 totalPositionBalance = positionData.positionType == PositionType.ERC4626
        //     ? ERC4626(position).redeem(ERC4626(position).balanceOf(address(this)), address(this), address(this))
        //     : ERC20(position).balanceOf(address(this));

        // if (!isPositionUsingSameAsset(position))
        //     registry.getSwapRouter().swapExactAmount(
        //         totalPositionBalance,
        //         // amountOutMin,
        //         positionData.pathToAsset
        //     );

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
}
