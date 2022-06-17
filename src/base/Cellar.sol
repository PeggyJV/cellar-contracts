// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC4626, ERC20 } from "./ERC4626.sol";
import { Multicall } from "./Multicall.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Registry, SwapRouter, PriceRouter } from "../Registry.sol";
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

    // TODO: pack struct
    struct PositionData {
        uint256 balance;
        uint256 storedUnrealizedGains;
    }

    address[] public positions;

    mapping(address => bool) public isPositionUsed;

    mapping(address => PositionData) public getPositionData;

    function getPositions() external view returns (address[] memory) {
        return positions;
    }

    function addPosition(uint256 index, address position) external onlyOwner whenNotShutdown {
        if (!isTrusted[position]) revert USR_UntrustedPosition(position);

        // Check if position is already being used.
        if (isPositionUsed[position]) revert USR_PositionAlreadyUsed(position);

        // Add new position at a specified index.
        positions.add(index, position);
        isPositionUsed[position] = true;

        emit PositionAdded(position, index);
    }

    /**
     * @dev If you know you are going to add a position to the end of the array, this is more
     *      efficient then `addPosition`.
     */
    function pushPosition(address position) external onlyOwner whenNotShutdown {
        if (!isTrusted[position]) revert USR_UntrustedPosition(position);

        // Check if position is already being used.
        if (isPositionUsed[position]) revert USR_PositionAlreadyUsed(position);

        // Add new position to the end of the positions.
        positions.push(position);
        isPositionUsed[position] = true;

        emit PositionAdded(position, positions.length - 1);
    }

    function removePosition(uint256 index) external onlyOwner {
        // Get position being removed.
        address position = positions[index];

        // Only remove position if it is empty.
        if (ERC4626(position).balanceOf(address(this)) > 0) revert USR_PositionNotEmpty(position);

        // Remove position at the given index.
        positions.remove(index);
        isPositionUsed[position] = false;

        emit PositionRemoved(position, index);
    }

    /**
     * @dev If you know you are going to remove a position from the end of the array, this is more
     *      efficient then `removePosition`.
     */
    function popPosition() external onlyOwner {
        // Get the index of the last position and last position itself.
        uint256 index = positions.length - 1;
        address position = positions[index];

        // Only remove position if it is empty.
        if (ERC4626(position).balanceOf(address(this)) > 0) revert USR_PositionNotEmpty(position);

        // Remove last position.
        positions.pop();
        isPositionUsed[position] = false;

        emit PositionRemoved(position, index);
    }

    function replacePosition(address newPosition, uint256 index) external onlyOwner whenNotShutdown {
        // Store the old position before its replaced.
        address oldPosition = positions[index];

        // Only remove position if it is empty.
        if (ERC4626(oldPosition).balanceOf(address(this)) > 0) revert USR_PositionNotEmpty(oldPosition);

        // Replace old position with new position.
        positions[index] = newPosition;
        isPositionUsed[oldPosition] = false;
        isPositionUsed[newPosition] = true;

        emit PositionReplaced(oldPosition, newPosition, index);
    }

    function swapPositions(uint256 index1, uint256 index2) external onlyOwner {
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

    function trustPosition(address position) external onlyOwner {
        // Trust position.
        isTrusted[position] = true;

        // Set max approval to deposit into position if it is ERC4626.
        ERC4626(position).asset().safeApprove(position, type(uint256).max);

        emit TrustChanged(position, true);
    }

    function distrustPosition(address position) external onlyOwner {
        // Distrust position.
        isTrusted[position] = false;

        // Remove position from the list of positions if it is present.
        positions.remove(position);

        // Remove approval for position.
        ERC4626(position).asset().safeApprove(position, 0);

        // NOTE: After position has been removed, SP should be notified on the UI that the position
        // can no longer be used and to exit the position or rebalance its assets into another
        // position ASAP.
        emit TrustChanged(position, false);
    }

    // ============================================ ACCRUAL STORAGE ============================================

    /**
     * @notice Timestamp of when the last accrual occurred.
     */
    uint64 public lastAccrual;

    // =============================================== FEES CONFIG ===============================================

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

    function withdrawFromPositions(
        uint256 assets,
        uint256 minAssetsOut,
        SwapRouter.Exchanges[] calldata exchanges,
        bytes[] calldata params,
        address receiver,
        address owner
    ) external returns (uint256 assetsOut, uint256 shares) {
        // Only withdraw if not enough assets in the holding pool.
        if (assets > totalHoldings()) return (assets, withdraw(assets, receiver, owner));

        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        _burn(owner, shares);

        assetsOut = _withdrawAndSwapFromPositions(assets, exchanges, params);

        require(assetsOut >= minAssetsOut, "NOT_ENOUGH_ASSETS_OUT");

        asset.safeTransfer(receiver, assetsOut);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function _withdrawAndSwapFromPositions(
        uint256 assets,
        SwapRouter.Exchanges[] calldata exchanges,
        bytes[] calldata params
    ) internal returns (uint256 assetsOut) {
        for (uint256 i; ; i++) {
            ERC4626 position = ERC4626(positions[i]);

            uint256 totalPositionBalance = position.maxWithdraw(address(this));

            // Move on to next position if this one is empty.
            if (totalPositionBalance == 0) continue;

            // Although it would be more efficient to store `position.asset()` and
            // `registry.priceRouter()`, doing so would cause a stack error.
            uint256 onePositionAsset = 10**position.asset().decimals();
            uint256 positionAssetToAssetExchangeRate = registry.priceRouter().getExchangeRate(position.asset(), asset);

            // Denominate position balance in cellar's asset.
            uint256 totalPositionBalanceInAssets = totalPositionBalance.mulDivDown(
                positionAssetToAssetExchangeRate,
                onePositionAsset
            );

            // We want to pull as much as we can from this position, but no more than needed.
            uint256 amount;
            if (totalPositionBalanceInAssets > assets) {
                assets -= assets;
                amount = assets.mulDivDown(onePositionAsset, positionAssetToAssetExchangeRate);
            } else {
                assets -= totalPositionBalanceInAssets;
                amount = totalPositionBalance;
            }

            // Pull from this position.
            assetsOut += _withdrawAndSwapFromPosition(position, asset, amount, exchanges[i], params[i]);

            // Stop if no more assets to withdraw.
            if (assets == 0) break;
        }
    }

    // ========================================= ACCOUNTING LOGIC =========================================

    /**
     * @notice The total amount of assets in the cellar.
     * @dev Excludes locked yield that hasn't been distributed.
     */
    function totalAssets() public view override returns (uint256 assets) {
        assets = totalHoldings();

        PriceRouter priceRouter = PriceRouter(registry.priceRouter());

        ERC20 denominationAsset = asset;
        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = ERC4626(positions[i]);
            assets += priceRouter.getValue(position.asset(), position.maxWithdraw(address(this)), denominationAsset);
        }
    }

    /**
     * @notice The total amount of assets in holding position.
     */
    function totalHoldings() public view returns (uint256) {
        return asset.balanceOf(address(this));
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
        // Record the balance of this and last accrual.
        uint256 totalBalanceThisAccrual;
        uint256 totalBalanceLastAccrual;

        // Get the latest address of the price router.
        PriceRouter priceRouter = PriceRouter(registry.priceRouter());

        for (uint256 i; i < positions.length; i++) {
            ERC4626 position = ERC4626(positions[i]);
            PositionData storage positionData = getPositionData[address(position)];

            // Get the current position balance.
            uint256 balanceThisAccrual = position.maxWithdraw(address(this));

            // Get exchange rate.
            ERC20 positionAsset = position.asset();
            uint256 onePositionAsset = 10**positionAsset.decimals();
            uint256 positionAssetToAssetExchangeRate = priceRouter.getExchangeRate(positionAsset, asset);

            // Add to balance for last accrual.
            totalBalanceLastAccrual += positionData.balance.mulDivDown(
                positionAssetToAssetExchangeRate,
                onePositionAsset
            );

            // Add to balance for this accrual.
            totalBalanceThisAccrual += (balanceThisAccrual + positionData.storedUnrealizedGains).mulDivDown(
                positionAssetToAssetExchangeRate,
                onePositionAsset
            );

            // Update position's data.
            positionData.balance = balanceThisAccrual;
            positionData.storedUnrealizedGains = 0;
        }

        // Compute and store current exchange rate between assets and shares for gas efficiency.
        uint256 assetToSharesExchangeRate = convertToShares(1e18);

        // Calculate platform fees accrued.
        uint256 elapsedTime = block.timestamp - lastAccrual;
        uint256 platformFeeInAssets = (totalBalanceThisAccrual * elapsedTime * platformFee) / 1e18 / 365 days;
        uint256 platformFees = platformFeeInAssets.mulWadDown(assetToSharesExchangeRate); // Convert to shares.

        // Calculate performance fees accrued.
        uint256 yield = totalBalanceThisAccrual.subMinZero(totalBalanceLastAccrual);
        uint256 performanceFeeInAssets = yield.mulWadDown(performanceFee);
        uint256 performanceFees = performanceFeeInAssets.mulWadDown(assetToSharesExchangeRate); // Convert to shares.

        // Mint accrued fees as shares.
        _mint(address(this), platformFees + performanceFees);

        lastAccrual = uint32(block.timestamp);

        emit Accrual(platformFees, performanceFees);
    }

    // =========================================== POSITION LOGIC ===========================================

    // TODO: move to Errors.sol
    error USR_InvalidPosition(address position);
    error USR_PositionNotEmpty(address position);

    /**
     * @notice Pushes assets in holdings into a position.
     * @param position address of the position to enter holdings into
     * @param assets amount of assets to exit from the position
     */
    function enterPosition(ERC4626 position, uint256 assets) public onlyOwner {
        // Check that position is a valid position.
        if (!isPositionUsed[address(position)]) revert USR_InvalidPosition(address(position));

        // TODO:
        // // Swap to the holding pool asset if necessary.
        // ERC20 positionAsset = position.asset();
        // if (positionAsset != asset) _swap(positionAsset, assets, exchange, params);

        // Get position data.
        PositionData storage positionData = getPositionData[address(position)];

        // Update position balance.
        positionData.balance += assets;

        // Deposit into position.
        ERC4626(position).deposit(assets, address(this));
    }

    /**
     * @notice Pulls assets from a position back into holdings.
     * @param position address of the position to completely exit
     * @param assets amount of assets to exit from the position
     * @param params encoded arguments for the function that will perform the swap on the selected exchange
     */
    function exitPosition(
        ERC4626 position,
        uint256 assets,
        SwapRouter.Exchanges exchange,
        bytes calldata params
    ) external onlyOwner {
        _withdrawAndSwapFromPosition(position, asset, assets, exchange, params);
    }

    /**
     * @notice Move assets between positions.
     * @param fromPosition address of the position to move assets from
     * @param toPosition address of the position to move assets to
     * @param assetsFrom amount of assets to move from the from position
     */
    function rebalance(
        ERC4626 fromPosition,
        ERC4626 toPosition,
        uint256 assetsFrom,
        SwapRouter.Exchanges exchange,
        bytes calldata params
    ) external onlyOwner returns (uint256 assetsTo) {
        // Check that position being rebalanced to is a valid position.
        if (!isPositionUsed[address(toPosition)]) revert USR_InvalidPosition(address(toPosition));

        // Withdraw from the from position and update related position data.
        assetsTo = _withdrawAndSwapFromPosition(fromPosition, toPosition.asset(), assetsFrom, exchange, params);

        // Update stored balance of the to position.
        getPositionData[address(toPosition)].balance += assetsTo;

        // Deposit into the to position.
        toPosition.deposit(assetsTo, address(this));
    }

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
        asset.safeApprove(address(gravityBridge), assets); // TODO: change to send the asset withdrawn
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
    ) external onlyOwner {
        // Prevent sweeping of assets managed by the cellar and shares minted to the cellar as fees.
        if (token == asset || token == this) revert USR_ProtectedAsset(address(token));
        for (uint256 i; i < positions.length; i++)
            if (address(token) == address(positions[i])) revert USR_ProtectedAsset(address(token));

        // Transfer out tokens in this cellar that shouldn't be here.
        token.safeTransfer(to, amount);

        emit Sweep(address(token), to, amount);
    }

    // ========================================== HELPER FUNCTIONS ==========================================

    function _withdrawAndSwapFromPosition(
        ERC4626 position,
        ERC20 toAsset,
        uint256 amount,
        SwapRouter.Exchanges exchange,
        bytes calldata params
    ) internal returns (uint256 amountOut) {
        // Get position data.
        PositionData storage positionData = getPositionData[address(position)];

        // Update position balance.
        _subtractFromPositionBalance(positionData, amount);

        // Withdraw from position.
        position.withdraw(amount, address(this), address(this));

        // Swap to the holding pool asset if necessary.
        ERC20 positionAsset = position.asset();
        amountOut = positionAsset != toAsset ? _swap(positionAsset, amount, exchange, params) : amount;
    }

    function _subtractFromPositionBalance(PositionData storage positionData, uint256 amount) internal {
        // Update position balance.
        uint256 positionBalance = positionData.balance;
        if (positionBalance > amount) {
            positionData.balance -= amount;
        } else {
            positionData.balance = 0;

            // Without these, the unrealized gains that were withdrawn would be not be counted next accrual.
            positionData.storedUnrealizedGains = amount - positionBalance;
        }
    }

    function _swap(
        ERC20 assetIn,
        uint256 amountIn,
        SwapRouter.Exchanges exchange,
        bytes calldata params
    ) internal returns (uint256 assetsOut) {
        // Store the expected amount of the asset in that we expect to have after the swap.
        uint256 expectedAssetsInAfter = assetIn.balanceOf(address(this)) - amountIn;

        // Get the address of the latest swap router.
        SwapRouter swapRouter = registry.swapRouter();

        // Approve swap router to swap assets.
        assetIn.safeApprove(address(swapRouter), amountIn);

        // Perform swap.
        assetsOut = swapRouter.swap(exchange, params);

        // Check that the amount of assets swapped is what is expected. Will revert if the `params`
        // specified a different amount of assets to swap then `assets`.
        // TODO: consider replacing with revert statement
        require(assetIn.balanceOf(address(this)) == expectedAssetsInAfter, "INCORRECT_PARAMS_AMOUNT");
    }
}
