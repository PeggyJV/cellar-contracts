// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC4626, ERC20 } from "./ERC4626.sol";
import { Multicall } from "./Multicall.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Registry, SwapRouter, PriceRouter } from "../Registry.sol";
import { IGravity } from "../interfaces/IGravity.sol";
import { AddressArray } from "src/utils/AddressArray.sol";
import { Math } from "../utils/Math.sol";

import "../Errors.sol";

contract Cellar is ERC4626, Ownable, Multicall {
    using AddressArray for address[];
    using SafeTransferLib for ERC20;
    using SafeCast for uint256;
    using SafeCast for int256;
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
        ERC4626,
        Cellar
    }

    // TODO: pack struct
    struct PositionData {
        PositionType positionType;
        int256 highWatermark;
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
        uint256 positionBalance = ERC4626(position).balanceOf(address(this));
        if (positionBalance > 0) revert USR_PositionNotEmpty(position, positionBalance);

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
        uint256 positionBalance = ERC4626(position).balanceOf(address(this));
        if (positionBalance > 0) revert USR_PositionNotEmpty(position, positionBalance);

        // Remove last position.
        positions.pop();
        isPositionUsed[position] = false;

        emit PositionRemoved(position, index);
    }

    function replacePosition(address newPosition, uint256 index) external onlyOwner whenNotShutdown {
        // Store the old position before its replaced.
        address oldPosition = positions[index];

        // Only remove position if it is empty.
        uint256 positionBalance = ERC4626(oldPosition).balanceOf(address(this));
        if (positionBalance > 0) revert USR_PositionNotEmpty(oldPosition, positionBalance);

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
        address[] memory _positions,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _name, _symbol, 18) Ownable() {
        registry = _registry;
        positions = _positions;

        for (uint256 i; i < _positions.length; i++) {
            address position = _positions[i];

            if (isPositionUsed[position]) revert USR_PositionAlreadyUsed(position);

            isTrusted[position] = true;
            isPositionUsed[position] = true;

            ERC4626(position).asset().safeApprove(position, type(uint256).max);
        }

        // Initialize last accrual timestamp to time that cellar was created, otherwise the first
        // `accrue` will take platform fees from 1970 to the time it is called.
        lastAccrual = uint64(block.timestamp);

        // Transfer ownership to the Gravity Bridge.
        transferOwnership(address(_registry.gravityBridge()));
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

    // TODO: move to ICellar once done
    event WithdrawFromPositions(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        ERC20[] receivedAssets,
        uint256[] amountsOut,
        uint256 shares
    );

    event PulledFromPosition(address indexed position, uint256 amount);

    function withdrawFromPositions(
        uint256 assets,
        address receiver,
        address owner
    )
        external
        returns (
            uint256 shares,
            ERC20[] memory receivedAssets,
            uint256[] memory amountsOut
        )
    {
        // Only withdraw if not enough assets in the holding pool.
        if (totalHoldings() >= assets) {
            receivedAssets = new ERC20[](1);
            amountsOut = new uint256[](1);

            receivedAssets[0] = asset;
            amountsOut[0] = assets;

            shares = withdraw(assets, receiver, owner);
        } else {
            // Would be more efficient to store `totalHoldings` to avoid calling twice, but will
            // cause stack errors.
            assets -= totalHoldings();

            // Get data efficiently.
            (
                uint256 _totalAssets,
                ,
                ERC4626[] memory _positions,
                ERC20[] memory positionAssets,
                uint256[] memory positionBalances
            ) = _getData();

            // Get the amount of share needed to redeem.
            shares = _previewWithdraw(assets, _totalAssets);

            if (msg.sender != owner) {
                uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

                if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
            }

            _burn(owner, shares);

            (uint256[] memory amountsReceived, uint256 numOfReceivedAssets) = _pullFromPositions(
                assets,
                _positions,
                positionAssets,
                positionBalances
            );

            receivedAssets = new ERC20[](numOfReceivedAssets);
            amountsOut = new uint256[](numOfReceivedAssets);

            uint256 j;
            for (uint256 i; i < amountsReceived.length; i++) {
                if (amountsReceived[i] == 0) continue;

                ERC20 positionAsset = positionAssets[i];
                receivedAssets[j] = positionAsset;
                amountsOut[j] = amountsReceived[i];
                j++;

                // Transfer withdrawn assets to the receiver.
                positionAsset.safeTransfer(receiver, amountsReceived[i]);
            }

            emit WithdrawFromPositions(msg.sender, receiver, owner, receivedAssets, amountsOut, shares);
        }
    }

    function _pullFromPositions(
        uint256 assets,
        ERC4626[] memory _positions,
        ERC20[] memory positionAssets,
        uint256[] memory positionBalances
    ) internal returns (uint256[] memory amountsReceived, uint256 numOfReceivedAssets) {
        amountsReceived = new uint256[](_positions.length);

        // Get the price router.
        PriceRouter priceRouter = registry.priceRouter();

        for (uint256 i; ; i++) {
            // Move on to next position if this one is empty.
            if (positionBalances[i] == 0) continue;

            uint256 onePositionAsset = 10**positionAssets[i].decimals();
            uint256 positionAssetToAssetExchangeRate = priceRouter.getExchangeRate(positionAssets[i], asset);

            // Denominate position balance in cellar's asset.
            uint256 totalPositionBalanceInAssets = positionBalances[i].mulDivDown(
                positionAssetToAssetExchangeRate,
                onePositionAsset
            );

            // We want to pull as much as we can from this position, but no more than needed.
            uint256 amount;
            (amount, assets) = totalPositionBalanceInAssets > assets
                ? (assets.mulDivDown(onePositionAsset, positionAssetToAssetExchangeRate), 0)
                : (positionBalances[i], assets - totalPositionBalanceInAssets);

            // Return the amount that will be received and increment number of received assets.
            amountsReceived[i] = amount;
            numOfReceivedAssets++;

            // Update position balance.
            getPositionData[address(_positions[i])].highWatermark -= amount.toInt256();

            // Withdraw from position.
            _positions[i].withdraw(amount, address(this), address(this));

            emit PulledFromPosition(address(_positions[i]), amount);

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
        uint256 numOfPositions = positions.length;
        ERC20[] memory positionAssets = new ERC20[](numOfPositions);
        uint256[] memory balances = new uint256[](numOfPositions);

        for (uint256 i; i < numOfPositions; i++) {
            ERC4626 position = ERC4626(positions[i]);

            positionAssets[i] = position.asset();
            balances[i] = position.maxWithdraw(address(this));
        }

        assets = registry.priceRouter().getValues(positionAssets, balances, asset) + totalHoldings();
    }

    /**
     * @notice The total amount of assets in holding position.
     */
    function totalHoldings() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @notice The amount of assets that the cellar would exchange for the amount of shares provided.
     * @param shares amount of shares to convert
     * @return assets the shares can be exchanged for
     */
    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        assets = _convertToAssets(shares, totalAssets());
    }

    /**
     * @notice The amount of shares that the cellar would exchange for the amount of assets provided.
     * @param assets amount of assets to convert
     * @return shares the assets can be exchanged for
     */
    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        shares = _convertToShares(assets, totalAssets());
    }

    /**
     * @notice Simulate the effects of minting shares at the current block, given current on-chain conditions.
     * @param shares amount of shares to mint
     * @return assets that will be deposited
     */
    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        assets = _previewMint(shares, totalAssets());
    }

    /**
     * @notice Simulate the effects of withdrawing assets at the current block, given current on-chain conditions.
     * @param assets amount of assets to withdraw
     * @return shares that will be redeemed
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        shares = _previewWithdraw(assets, totalAssets());
    }

    function _convertToAssets(uint256 shares, uint256 _totalAssets) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 assetDecimals = asset.decimals();
        uint256 totalAssetsNormalized = _totalAssets.changeDecimals(assetDecimals, 18);

        assets = totalShares == 0 ? shares : shares.mulDivDown(totalAssetsNormalized, totalShares);
        assets = assets.changeDecimals(18, assetDecimals);
    }

    function _convertToShares(uint256 assets, uint256 _totalAssets) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 assetDecimals = asset.decimals();
        uint256 assetsNormalized = assets.changeDecimals(assetDecimals, 18);
        uint256 totalAssetsNormalized = _totalAssets.changeDecimals(assetDecimals, 18);

        shares = totalShares == 0 ? assetsNormalized : assetsNormalized.mulDivDown(totalShares, totalAssetsNormalized);
    }

    function _previewMint(uint256 shares, uint256 _totalAssets) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 assetDecimals = asset.decimals();
        uint256 totalAssetsNormalized = _totalAssets.changeDecimals(assetDecimals, 18);

        assets = totalShares == 0 ? shares : shares.mulDivUp(totalAssetsNormalized, totalShares);
        assets = assets.changeDecimals(18, assetDecimals);
    }

    function _previewWithdraw(uint256 assets, uint256 _totalAssets) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 assetDecimals = asset.decimals();
        uint256 assetsNormalized = assets.changeDecimals(assetDecimals, 18);
        uint256 totalAssetsNormalized = _totalAssets.changeDecimals(assetDecimals, 18);

        shares = totalShares == 0 ? assetsNormalized : assetsNormalized.mulDivUp(totalShares, totalAssetsNormalized);
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
        // Get the latest address of the price router.
        PriceRouter priceRouter = registry.priceRouter();

        // Get data efficiently.
        (
            uint256 _totalAssets,
            ,
            ERC4626[] memory _positions,
            ERC20[] memory positionAssets,
            uint256[] memory positionBalances
        ) = _getData();

        // Record the total yield earned this accrual.
        uint256 totalYield;

        // Saves SLOADs during looping.
        ERC20 denominationAsset = asset;

        for (uint256 i; i < _positions.length; i++) {
            PositionData storage positionData = getPositionData[address(_positions[i])];

            // Get the current position balance.
            uint256 balanceThisAccrual = positionBalances[i];

            // Measure yield earned against this position's high watermark.
            int256 yield = balanceThisAccrual.toInt256() - positionData.highWatermark;

            // Move on if there is no yield to accrue.
            if (yield <= 0) continue;

            // Denominate yield in cellar's asset and count it towards our total yield for this accural.
            totalYield += priceRouter.getValue(positionAssets[i], yield.toUint256(), denominationAsset);

            // Update position's high watermark.
            positionData.highWatermark = balanceThisAccrual.toInt256();
        }

        // Compute and store current exchange rate between assets and shares for gas efficiency.
        uint256 exchangeRate = _convertToShares(1, _totalAssets);

        // Calculate platform fees accrued.
        uint256 elapsedTime = block.timestamp - lastAccrual;
        uint256 platformFeeInAssets = (_totalAssets * elapsedTime * platformFee) / 1e18 / 365 days;
        uint256 platformFees = _convertToFees(platformFeeInAssets, exchangeRate);

        // Calculate performance fees accrued.
        uint256 performanceFeeInAssets = totalYield.mulWadDown(performanceFee);
        uint256 performanceFees = _convertToFees(performanceFeeInAssets, exchangeRate);

        // Mint accrued fees as shares.
        _mint(address(this), platformFees + performanceFees);

        lastAccrual = uint32(block.timestamp);

        emit Accrual(platformFees, performanceFees);
    }

    // =========================================== POSITION LOGIC ===========================================

    /**
     * @notice Move assets between positions. To move assets from/to this cellar's holdings, specify
     *         the address of this cellar as the `fromPosition`/`toPosition`.
     * @param fromPosition address of the position to move assets from
     * @param toPosition address of the position to move assets to
     * @param assetsFrom amount of assets to move from the from position
     */
    function rebalance(
        ERC4626 fromPosition,
        ERC4626 toPosition,
        uint256 assetsFrom,
        SwapRouter.Exchange exchange,
        bytes calldata params
    ) external onlyOwner returns (uint256 assetsTo) {
        // Withdraw from position, if not the rebalancing from the holding pool.
        if (address(fromPosition) != address(this)) {
            // Without this, withdrawals from this position would be counted as losses during the
            // next fee accrual.
            getPositionData[address(fromPosition)].highWatermark -= assetsFrom.toInt256();

            fromPosition.withdraw(assetsFrom, address(this), address(this));
        }

        // Swap to the asset of the other position if necessary.
        ERC20 fromAsset = fromPosition.asset();
        ERC20 toAsset = toPosition.asset();
        assetsTo = fromAsset != toAsset ? _swap(fromAsset, assetsFrom, exchange, params) : assetsFrom;

        // Deposit to position, if not the rebalancing to the holding pool
        if (address(toPosition) != address(this)) {
            // Check that position being rebalanced to is currently being used.
            if (!isPositionUsed[address(toPosition)]) revert USR_InvalidPosition(address(toPosition));

            // Without this, deposits to this position would be counted as yield during the next fee
            // accrual.
            getPositionData[address(toPosition)].highWatermark += assetsTo.toInt256();

            toPosition.deposit(assetsTo, address(this));
        }
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

        // Get data efficiently.
        uint256 _totalAssets = totalAssets();
        uint256 ownedAssets = _convertToAssets(balanceOf[receiver], _totalAssets);

        uint256 leftUntilDepositLimit = asssetDepositLimit.subMinZero(ownedAssets);
        uint256 leftUntilLiquidityLimit = asssetLiquidityLimit.subMinZero(_totalAssets);

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

        // Get data efficiently.
        uint256 _totalAssets = totalAssets();
        uint256 ownedAssets = _convertToAssets(balanceOf[receiver], _totalAssets);

        uint256 leftUntilDepositLimit = asssetDepositLimit.subMinZero(ownedAssets);
        uint256 leftUntilLiquidityLimit = asssetLiquidityLimit.subMinZero(_totalAssets);

        // Only return the more relevant of the two.
        shares = _convertToShares(Math.min(leftUntilDepositLimit, leftUntilLiquidityLimit), _totalAssets);
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

    function _getData()
        internal
        view
        returns (
            uint256 _totalAssets,
            uint256 _totalHoldings,
            ERC4626[] memory _positions,
            ERC20[] memory positionAssets,
            uint256[] memory positionBalances
        )
    {
        uint256 len = positions.length;

        _positions = new ERC4626[](len);
        positionAssets = new ERC20[](len);
        positionBalances = new uint256[](len);

        for (uint256 i; i < len; i++) {
            ERC4626 position = ERC4626(positions[i]);

            _positions[i] = position;
            positionAssets[i] = position.asset();
            positionBalances[i] = position.maxWithdraw(address(this));
        }

        _totalHoldings = totalHoldings();
        _totalAssets = registry.priceRouter().getValues(positionAssets, positionBalances, asset) + _totalHoldings;
    }

    function _swap(
        ERC20 assetIn,
        uint256 amountIn,
        SwapRouter.Exchange exchange,
        bytes calldata params
    ) internal returns (uint256 amountOut) {
        // Store the expected amount of the asset in that we expect to have after the swap.
        uint256 expectedAssetsInAfter = assetIn.balanceOf(address(this)) - amountIn;

        // Get the address of the latest swap router.
        SwapRouter swapRouter = registry.swapRouter();

        // Approve swap router to swap assets.
        assetIn.safeApprove(address(swapRouter), amountIn);

        // Perform swap.
        amountOut = swapRouter.swap(exchange, params);

        // Check that the amount of assets swapped is what is expected. Will revert if the `params`
        // specified a different amount of assets to swap then `amountIn`.
        // TODO: consider replacing with revert statement
        require(assetIn.balanceOf(address(this)) == expectedAssetsInAfter, "INCORRECT_PARAMS_AMOUNT");
    }

    function _convertToFees(uint256 assets, uint256 exchangeRate) internal view returns (uint256 fees) {
        // Convert amount of assets to take as fees to shares.
        uint256 feesInShares = assets * exchangeRate;

        // Saves an SLOAD.
        uint256 totalShares = totalSupply;

        // Get the amount of fees to mint. Without this, the value of fees minted would be slightly
        // diluted because total shares increased while total assets did not. This counteracts that.
        uint256 denominator = totalShares - feesInShares;
        fees = denominator > 0 ? feesInShares.mulDivUp(totalShares, denominator) : 0;
    }
}
