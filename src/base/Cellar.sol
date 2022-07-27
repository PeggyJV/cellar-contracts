// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC4626, ERC20 } from "./ERC4626.sol";
import { Multicall } from "./Multicall.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Registry } from "src/Registry.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IGravity } from "../interfaces/IGravity.sol";
import { AddressArray } from "src/utils/AddressArray.sol";
import { Math } from "../utils/Math.sol";

import { Test, console } from "@forge-std/Test.sol";
import "../Errors.sol";

/**
 * @title Sommelier Cellar
 * @notice A composable ERC4626 that can use a set of other ERC4626 or ERC20 positions to earn yield.
 * @author Brian Le
 */
contract Cellar is ERC4626, Ownable, Multicall {
    using AddressArray for address[];
    using AddressArray for ERC20[];
    using SafeTransferLib for ERC20;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Math for uint256;

    // ========================================= POSITIONS CONFIG =========================================

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

    /**
     * @notice Value specifying the interface a position uses.
     * @param ERC20 an ERC20 token
     * @param ERC4626 an ERC4626 vault
     * @param Cellar a cellar
     */
    enum PositionType {
        ERC20,
        ERC4626,
        Cellar
    }

    /**
     * @notice Addresses of the positions current used by the cellar.
     */
    address[] public positions;

    /**
     * @notice Tell whether a position is currently used.
     */
    mapping(address => bool) public isPositionUsed;

    /**
     * @notice Get the type related to a position.
     */
    mapping(address => PositionType) public getPositionType;

    /**
     * @notice Get the addresses of the positions current used by the cellar.
     */
    function getPositions() external view returns (address[] memory) {
        return positions;
    }

    /**
     * @notice Insert a trusted position to the list of positions used by the cellar at a given index.
     * @param index index at which to insert the position
     * @param position address of position to add
     */
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
     * @notice Push a trusted position to the end of the list of positions used by the cellar.
     * @dev If you know you are going to add a position to the end of the array, this is more
     *      efficient then `addPosition`.
     * @param position address of position to add
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

    /**
     * @notice Remove the position at a given index from the list of positions used by the cellar.
     * @param index index at which to remove the position
     */
    function removePosition(uint256 index) external onlyOwner {
        // Get position being removed.
        address position = positions[index];

        // Only remove position if it is empty.
        uint256 positionBalance = _balanceOf(position);
        if (positionBalance > 0) revert USR_PositionNotEmpty(position, positionBalance);

        // Remove position at the given index.
        positions.remove(index);
        isPositionUsed[position] = false;

        emit PositionRemoved(position, index);
    }

    /**
     * @notice Remove the last position in the list of positions used by the cellar.
     * @dev If you know you are going to remove a position from the end of the array, this is more
     *      efficient then `removePosition`.
     */
    function popPosition() external onlyOwner {
        // Get the index of the last position and last position itself.
        uint256 index = positions.length - 1;
        address position = positions[index];

        // Only remove position if it is empty.
        uint256 positionBalance = _balanceOf(position);
        if (positionBalance > 0) revert USR_PositionNotEmpty(position, positionBalance);

        // Remove last position.
        positions.pop();
        isPositionUsed[position] = false;

        emit PositionRemoved(position, index);
    }

    /**
     * @notice Replace a position at a given index with a new position.
     * @param index index at which to replace the position
     * @param newPosition address of position to replace with
     */
    function replacePosition(uint256 index, address newPosition) external onlyOwner whenNotShutdown {
        // Store the old position before its replaced.
        address oldPosition = positions[index];

        // Only remove position if it is empty.
        uint256 positionBalance = _balanceOf(oldPosition);
        if (positionBalance > 0) revert USR_PositionNotEmpty(oldPosition, positionBalance);

        // Replace old position with new position.
        positions[index] = newPosition;
        isPositionUsed[oldPosition] = false;
        isPositionUsed[newPosition] = true;

        emit PositionReplaced(oldPosition, newPosition, index);
    }

    /**
     * @notice Swap the positions at two given indexes.
     * @param index1 index of first position to swap
     * @param index2 index of second position to swap
     */
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

    /**
     * @notice Tell whether a position is trusted.
     */
    mapping(address => bool) public isTrusted;

    /**
     * @notice Trust a position to be used by the cellar.
     * @param position address of position to trust
     * @param positionType value specifying the interface the position uses
     */
    function trustPosition(address position, PositionType positionType) external onlyOwner {
        // Trust position.
        isTrusted[position] = true;

        // Set position type.
        getPositionType[position] = positionType;

        emit TrustChanged(position, true);
    }

    /**
     * @notice Distrust a position to prevent it from being used by the cellar.
     * @param position address of position to distrust
     */
    function distrustPosition(address position) external onlyOwner {
        // Distrust position.
        isTrusted[position] = false;

        // Remove position from the list of positions if it is present.
        positions.remove(position);

        // NOTE: After position has been removed, SP should be notified on the UI that the position
        //       can no longer be used and to exit the position or rebalance its assets into another
        //       position ASAP.
        emit TrustChanged(position, false);
    }

    // ============================================ WITHDRAW CONFIG ============================================

    /**
     * @notice Emitted when withdraw type configuration is changed.
     * @param oldType previous withdraw type
     * @param newType new withdraw type
     */
    event WithdrawTypeChanged(WithdrawType oldType, WithdrawType newType);

    /**
     * @notice The withdraw type to use for the cellar.
     * @param ORDERLY use `positions` in specify the order in which assets are withdrawn (eg.
     *                `positions[0]` is withdrawn from first), least impactful position (position
     *                that will have its core positions impacted the least by having funds removed)
     *                should be first and most impactful position should be last
     * @param PROPORTIONAL pull assets from each position proportionally when withdrawing, used if
     *                     trying to maintain a specific ratio
     */
    enum WithdrawType {
        ORDERLY,
        PROPORTIONAL
    }

    /**
     * @notice The withdraw type to used by the cellar.
     */
    WithdrawType public withdrawType;

    /**
     * @notice Set the withdraw type used by the cellar.
     * @param newWithdrawType value of the new withdraw type to use
     */
    function setWithdrawType(WithdrawType newWithdrawType) external onlyOwner {
        emit WithdrawTypeChanged(withdrawType, newWithdrawType);

        withdrawType = newWithdrawType;
    }

    // ============================================ HOLDINGS CONFIG ============================================

    /**
     * @notice Emitted when the holdings position is changed.
     * @param oldPosition address of the old holdings position
     * @param newPosition address of the new holdings position
     */
    event HoldingPositionChanged(address indexed oldPosition, address indexed newPosition);

    /**
     * @notice The "default" position which uses the same asset as the cellar. It is the position
     *         deposited assets will automatically go into (perhaps while waiting to be rebalanced
     *         to other positions) and commonly the first position withdrawn assets will be pulled
     *         from if using orderly withdraws.
     * @dev MUST accept the same asset as the cellar's `asset`. MUST be a position present in
     *      `positions`. Should be a static (eg. just holding) or lossless (eg. lending on Aave)
     *      position. Should not be expensive to move assets in or out of as this will occur
     *      frequently. It is highly recommended to choose a "simple" holding position.
     */
    address public holdingPosition;

    /**
     * @notice Set the holding position used by the cellar.
     * @param newHoldingPosition address of the new holding position to use
     */
    function setHoldingPosition(address newHoldingPosition) external onlyOwner {
        if (!isPositionUsed[newHoldingPosition]) revert USR_InvalidPosition(newHoldingPosition);

        ERC20 holdingPositionAsset = _assetOf(newHoldingPosition);
        if (holdingPositionAsset == asset) revert USR_AssetMismatch(address(holdingPositionAsset), address(asset));

        emit HoldingPositionChanged(holdingPosition, newHoldingPosition);

        holdingPosition = newHoldingPosition;
    }

    // ============================================ ACCRUAL STORAGE ============================================

    /**
     * @notice Timestamp of when the last accrual occurred.
     * @dev Used for determining the amount of platform fees that can be taken during an accrual period.
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
     * @notice Emitted when strategist performance fee cut is changed.
     * @param oldPerformanceCut value strategist performance fee cut was changed from
     * @param newPerformanceCut value strategist performance fee cut was changed to
     */
    event StrategistPerformanceCutChanged(uint64 oldPerformanceCut, uint64 newPerformanceCut);

    /**
     * @notice Emitted when strategist platform fee cut is changed.
     * @param oldPlatformCut value strategist platform fee cut was changed from
     * @param newPlatformCut value strategist platform fee cut was changed to
     */
    event StrategistPlatformCutChanged(uint64 oldPlatformCut, uint64 newPlatformCut);

    /**
     * @notice Emitted when strategists payout address is changed.
     * @param oldPayoutAddress value strategists payout address was changed from
     * @param newPayoutAddress value strategists payout address was changed to
     */
    event StrategistPayoutAddressChanged(address oldPayoutAddress, address newPayoutAddress);

    /**
     * @notice Data related to fees.
     * @param highWatermark Stores the share price to be used as a High Watermark to calculate performance fees.
     * @param strategistPerformanceCut Determines how much performance fees go to strategist.
     *                                 This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     * @param strategistPlatformCut Determines how much platform fees go to strategist.
     *                              This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     * @param platformFee The percentage of total assets accrued as platform fees over a year.
                          This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     * @param performanceFee The percentage of total assets accrued as platform fees over a year.
     *                       This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     * @param feesDistributor Cosmos address of module that distributes fees, specified as a hex value.
     *                        The Gravity contract expects a 32-byte value formatted in a specific way.
     * @param strategistPayoutAddress Address to send the strategists fee shares.
     */
    struct FeeData {
        uint256 highWatermark;
        uint64 strategistPerformanceCut;
        uint64 strategistPlatformCut;
        uint64 platformFee;
        uint64 performanceFee;
        bytes32 feesDistributor;
        address strategistPayoutAddress;
    }

    /**
     * @notice Stores all fee data for cellar.
     */
    FeeData public feeData =
        FeeData({
            highWatermark: 0,
            strategistPerformanceCut: 0.75e18,
            strategistPlatformCut: 0.75e18,
            strategistPayoutAddress: address(0),
            platformFee: 0.01e18,
            performanceFee: 0.1e18,
            feesDistributor: hex"000000000000000000000000b813554b423266bbd4c16c32fa383394868c1f55"
        });

    /**
     * @notice Set the percentage of platform fees accrued over a year.
     * @param newPlatformFee value out of 1e18 that represents new platform fee percentage
     */
    function setPlatformFee(uint64 newPlatformFee) external onlyOwner {
        emit PlatformFeeChanged(feeData.platformFee, newPlatformFee);

        feeData.platformFee = newPlatformFee;
    }

    /**
     * @notice Set the percentage of performance fees accrued from yield.
     * @param newPerformanceFee value out of 1e18 that represents new performance fee percentage
     */
    function setPerformanceFee(uint64 newPerformanceFee) external onlyOwner {
        emit PerformanceFeeChanged(feeData.performanceFee, newPerformanceFee);

        feeData.performanceFee = newPerformanceFee;
    }

    /**
     * @notice Set the address of the fee distributor on the Sommelier chain.
     * @dev IMPORTANT: Ensure that the address is formatted in the specific way that the Gravity contract
     *      expects it to be.
     * @param newFeesDistributor formatted address of the new fee distributor module
     */
    function setFeesDistributor(bytes32 newFeesDistributor) external onlyOwner {
        emit FeesDistributorChanged(feeData.feesDistributor, newFeesDistributor);

        feeData.feesDistributor = newFeesDistributor;
    }

    /**
     * @notice Sets the Strategists cut of performance fees
     * @param cut the performance cut for the strategist
     */
    function setStrategistPerformanceCut(uint64 cut) external onlyOwner {
        if (cut > 1e18) revert INPUT_InvalidFeeCut();
        emit StrategistPerformanceCutChanged(feeData.strategistPerformanceCut, cut);

        feeData.strategistPerformanceCut = cut;
    }

    /**
     * @notice Sets the Strategists cut of platform fees
     * @param cut the platform cut for the strategist
     */
    function setStrategistPlatformCut(uint64 cut) external onlyOwner {
        if (cut > 1e18) revert INPUT_InvalidFeeCut();
        emit StrategistPlatformCutChanged(feeData.strategistPlatformCut, cut);

        feeData.strategistPlatformCut = cut;
    }

    /**
     * @notice Sets the Strategists payout address
     * @param payout the new strategist payout address
     */
    function setStrategistPayoutAddress(address payout) external onlyOwner {
        emit StrategistPayoutAddressChanged(feeData.strategistPayoutAddress, payout);

        feeData.strategistPayoutAddress = payout;
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

    /**
     * @notice Address of the platform's registry contract. Used to get the latest address of modules.
     */
    Registry public immutable registry;

    /**
     * @dev Owner should be set to the Gravity Bridge, which relays instructions from the Steward
     *      module to the cellars.
     *      https://github.com/PeggyJV/steward
     *      https://github.com/cosmos/gravity-bridge/blob/main/solidity/contracts/Gravity.sol
     * @param _registry address of the platform's registry contract
     * @param _asset address of underlying token used for the for accounting, depositing, and withdrawing
     * @param _positions addresses of the positions to initialize the cellar with
     * @param _positionTypes types of each positions used
     * @param _holdingPosition address of the position to use as the holding position
     * @param _withdrawType withdraw type to use for the cellar
     * @param _name name of this cellar's share token
     * @param _name symbol of this cellar's share token
     */
    constructor(
        Registry _registry,
        ERC20 _asset,
        address[] memory _positions,
        PositionType[] memory _positionTypes,
        address _holdingPosition,
        WithdrawType _withdrawType,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _name, _symbol, 18) Ownable() {
        registry = _registry;

        // Initialize positions.
        positions = _positions;

        for (uint256 i; i < _positions.length; i++) {
            address position = _positions[i];

            if (isPositionUsed[position]) revert USR_PositionAlreadyUsed(position);

            isTrusted[position] = true;
            isPositionUsed[position] = true;
            getPositionType[position] = _positionTypes[i];
        }

        // Initialize holding position.
        if (!isPositionUsed[_holdingPosition]) revert USR_InvalidPosition(_holdingPosition);

        ERC20 holdingPositionAsset = _assetOf(_holdingPosition);
        if (holdingPositionAsset != _asset) revert USR_AssetMismatch(address(holdingPositionAsset), address(_asset));

        holdingPosition = _holdingPosition;

        // Initialize withdraw type.
        withdrawType = _withdrawType;

        // Initialize last accrual timestamp to time that cellar was created, otherwise the first
        // `accrue` will take platform fees from 1970 to the time it is called.
        lastAccrual = uint64(block.timestamp);

        // Initialize highWatermark
        feeData.highWatermark = 10**decimals;

        // Transfer ownership to the Gravity Bridge.
        address gravityBridge = _registry.getAddress(0);
        transferOwnership(gravityBridge);
    }

    // =========================================== CORE LOGIC ===========================================

    event PulledFromPosition(address indexed position, uint256 amount);

    function beforeDeposit(
        uint256 assets,
        uint256,
        address receiver
    ) internal view override whenNotShutdown {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) revert USR_DepositRestricted(assets, maxAssets);
    }

    function afterDeposit(
        uint256 assets,
        uint256,
        address
    ) internal override {
        _depositTo(holdingPosition, assets);
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        uint256 _totalAssets = totalAssets();

        _takePerformanceFees(_totalAssets);
        // Check for rounding error since we round down in previewDeposit.
        if ((shares = _convertToShares(assets, _totalAssets)) == 0) revert USR_ZeroShares();

        beforeDeposit(assets, shares, receiver);

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares, receiver);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        uint256 _totalAssets = totalAssets();

        _takePerformanceFees(_totalAssets);

        assets = _previewMint(shares, _totalAssets); // No need to check for rounding error, previewMint rounds up.

        beforeDeposit(assets, shares, receiver);

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares, receiver);
    }

    /**
     * @notice Withdraw assets from the cellar by redeeming shares.
     * @dev Unlike conventional ERC4626 contracts, this may not always return one asset to the receiver.
     *      Since there are no swaps involved in this function, the receiver may receive multiple
     *      assets. The value of all the assets returned will be equal to the amount defined by
     *      `assets` denominated in the `asset` of the cellar (eg. if `asset` is USDC and `assets`
     *      is 1000, then the receiver will receive $1000 worth of assets in either one or many
     *      tokens).
     * @param assets equivalent value of the assets withdrawn, denominated in the cellar's asset
     * @param receiver address that will receive withdrawn assets
     * @param owner address that owns the shares being redeemed
     * @return shares amount of shares redeemed
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        // Get data efficiently.
        (
            uint256 _totalAssets, // Store totalHoldings and pass into _withdrawInOrder if no stack errors.
            address[] memory _positions,
            ERC20[] memory positionAssets,
            uint256[] memory positionBalances
        ) = _getData();

        _takePerformanceFees(_totalAssets);

        // No need to check for rounding error, `previewWithdraw` rounds up.
        shares = _previewWithdraw(assets, _totalAssets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        uint256 totalShares = totalSupply;

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        withdrawType == WithdrawType.ORDERLY
            ? _withdrawInOrder(assets, receiver, _positions, positionAssets, positionBalances)
            : _withdrawInProportion(shares, totalShares, receiver, _positions, positionBalances);
    }

    /**
     * @notice Redeem shares to withdraw assets from the cellar.
     * @dev Unlike conventional ERC4626 contracts, this may not always return one asset to the receiver.
     *      Since there are no swaps involved in this function, the receiver may receive multiple
     *      assets. The value of all the assets returned will be equal to the amount defined by
     *      `assets` denominated in the `asset` of the cellar (eg. if `asset` is USDC and `assets`
     *      is 1000, then the receiver will receive $1000 worth of assets in either one or many
     *      tokens).
     * @param shares amount of shares to redeem
     * @param receiver address that will receive withdrawn assets
     * @param owner address that owns the shares being redeemed
     * @return assets equivalent value of the assets withdrawn, denominated in the cellar's asset
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        // Get data efficiently.
        (
            uint256 _totalAssets, // Store totalHoldings and pass into _withdrawInOrder if no stack errors.
            address[] memory _positions,
            ERC20[] memory positionAssets,
            uint256[] memory positionBalances
        ) = _getData();

        _takePerformanceFees(_totalAssets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        if ((assets = _convertToAssets(shares, _totalAssets)) == 0) revert USR_ZeroAssets();

        uint256 totalShares = totalSupply;

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        withdrawType == WithdrawType.ORDERLY
            ? _withdrawInOrder(assets, receiver, _positions, positionAssets, positionBalances)
            : _withdrawInProportion(shares, totalShares, receiver, _positions, positionBalances);
    }

    /**
     * @dev Withdraw from positions in the order defined by `positions`. Used if the withdraw type
     *      is `ORDERLY`.
     */
    function _withdrawInOrder(
        uint256 assets,
        address receiver,
        address[] memory _positions,
        ERC20[] memory positionAssets,
        uint256[] memory positionBalances
    ) internal {
        // Get the price router.
        PriceRouter priceRouter = PriceRouter(registry.getAddress(2));

        for (uint256 i; ; i++) {
            // Move on to next position if this one is empty.
            if (positionBalances[i] == 0) continue;

            uint256 onePositionAsset = 10**positionAssets[i].decimals();
            uint256 exchangeRate = priceRouter.getExchangeRate(positionAssets[i], asset);

            // Denominate position balance in cellar's asset.
            uint256 totalPositionBalanceInAssets = positionBalances[i].mulDivDown(exchangeRate, onePositionAsset);

            // We want to pull as much as we can from this position, but no more than needed.
            uint256 amount;

            if (totalPositionBalanceInAssets > assets) {
                amount = assets.mulDivDown(onePositionAsset, exchangeRate);
                assets = 0;
            } else {
                amount = positionBalances[i];
                assets = assets - totalPositionBalanceInAssets;
            }

            // Withdraw from position.
            _withdrawFrom(_positions[i], amount, receiver);

            emit PulledFromPosition(_positions[i], amount);

            // Stop if no more assets to withdraw.
            if (assets == 0) break;
        }
    }

    /**
     * @dev Withdraw from each position proportional to that of shares redeemed. Used if the
     *      withdraw type is `PROPORTIONAL`.
     */
    function _withdrawInProportion(
        uint256 shares,
        uint256 totalShares,
        address receiver,
        address[] memory _positions,
        uint256[] memory positionBalances
    ) internal {
        // Withdraw assets from positions in proportion to shares redeemed.
        for (uint256 i; i < _positions.length; i++) {
            address position = _positions[i];
            uint256 positionBalance = positionBalances[i];

            // Move on to next position if this one is empty.
            if (positionBalance == 0) continue;

            // Get the amount of assets to withdraw from this position based on proportion to shares redeemed.
            uint256 amount = positionBalance.mulDivDown(shares, totalShares);

            // Withdraw from position to receiver.
            _withdrawFrom(position, amount, receiver);

            emit PulledFromPosition(position, amount);
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
            address position = positions[i];
            positionAssets[i] = _assetOf(position);
            balances[i] = _balanceOf(position);
        }

        PriceRouter priceRouter = PriceRouter(registry.getAddress(2));
        assets = priceRouter.getValues(positionAssets, balances, asset);
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
        uint256 _totalAssets = totalAssets();
        (uint256 feeInAssets, ) = _previewPerformanceFees(_totalAssets);
        assets = _previewMint(shares, _totalAssets - feeInAssets);
    }

    /**
     * @notice Simulate the effects of withdrawing assets at the current block, given current on-chain conditions.
     * @param assets amount of assets to withdraw
     * @return shares that will be redeemed
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        uint256 _totalAssets = totalAssets();
        (uint256 feeInAssets, ) = _previewPerformanceFees(_totalAssets);
        shares = _previewWithdraw(assets, _totalAssets - feeInAssets);
    }

    /**
     * @notice Simulate the effects of depositing assets at the current block, given current on-chain conditions.
     * @param assets amount of assets to deposit
     * @return shares that will be minted
     */
    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        uint256 _totalAssets = totalAssets();
        (uint256 feeInAssets, ) = _previewPerformanceFees(_totalAssets);
        shares = _convertToShares(assets, _totalAssets - feeInAssets);
    }

    /**
     * @notice Simulate the effects of redeeming shares at the current block, given current on-chain conditions.
     * @param shares amount of shares to redeem
     * @return assets that will be returned
     */
    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        uint256 _totalAssets = totalAssets();
        (uint256 feeInAssets, ) = _previewPerformanceFees(_totalAssets);
        assets = _convertToAssets(shares, _totalAssets - feeInAssets);
    }

    /**
     * @dev Used to more efficiently convert amount of shares to assets using a stored `totalAssets` value.
     */
    function _convertToAssets(uint256 shares, uint256 _totalAssets) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 assetDecimals = asset.decimals();
        uint256 totalAssetsNormalized = _totalAssets.changeDecimals(assetDecimals, 18);

        assets = totalShares == 0 ? shares : shares.mulDivDown(totalAssetsNormalized, totalShares);
        assets = assets.changeDecimals(18, assetDecimals);
    }

    /**
     * @dev Used to more efficiently convert amount of assets to shares using a stored `totalAssets` value.
     */
    function _convertToShares(uint256 assets, uint256 _totalAssets) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 assetDecimals = asset.decimals();
        uint256 assetsNormalized = assets.changeDecimals(assetDecimals, 18);
        uint256 totalAssetsNormalized = _totalAssets.changeDecimals(assetDecimals, 18);

        shares = totalShares == 0 ? assetsNormalized : assetsNormalized.mulDivDown(totalShares, totalAssetsNormalized);
    }

    /**
     * @dev Used to more efficiently simulate minting shares using a stored `totalAssets` value.
     */
    function _previewMint(uint256 shares, uint256 _totalAssets) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 assetDecimals = asset.decimals();
        uint256 totalAssetsNormalized = _totalAssets.changeDecimals(assetDecimals, 18);

        assets = totalShares == 0 ? shares : shares.mulDivUp(totalAssetsNormalized, totalShares);
        assets = assets.changeDecimals(18, assetDecimals);
    }

    /**
     * @dev Used to more efficiently simulate withdrawing assets using a stored `totalAssets` value.
     */
    function _previewWithdraw(uint256 assets, uint256 _totalAssets) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 assetDecimals = asset.decimals();
        uint256 assetsNormalized = assets.changeDecimals(assetDecimals, 18);
        uint256 totalAssetsNormalized = _totalAssets.changeDecimals(assetDecimals, 18);

        shares = totalShares == 0 ? assetsNormalized : assetsNormalized.mulDivUp(totalShares, totalAssetsNormalized);
    }

    /**
     * @dev Used to efficiently get and store accounting information to avoid having to expensively
     *      recompute it.
     */
    function _getData()
        internal
        view
        returns (
            uint256 _totalAssets,
            address[] memory _positions,
            ERC20[] memory positionAssets,
            uint256[] memory positionBalances
        )
    {
        uint256 len = positions.length;

        _positions = new address[](len);
        positionAssets = new ERC20[](len);
        positionBalances = new uint256[](len);

        for (uint256 i; i < len; i++) {
            address position = positions[i];

            _positions[i] = position;
            positionAssets[i] = _assetOf(position);
            positionBalances[i] = _balanceOf(position);
        }

        PriceRouter priceRouter = PriceRouter(registry.getAddress(2));
        _totalAssets = priceRouter.getValues(positionAssets, positionBalances, asset);
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
        address fromPosition,
        address toPosition,
        uint256 assetsFrom,
        SwapRouter.Exchange exchange,
        bytes calldata params
    ) external onlyOwner returns (uint256 assetsTo) {
        // Check that position being rebalanced to is currently being used.
        if (!isPositionUsed[toPosition]) revert USR_InvalidPosition(address(toPosition));

        // Withdraw from position.
        _withdrawFrom(fromPosition, assetsFrom, address(this));

        // Swap to the asset of the other position if necessary.
        ERC20 fromAsset = _assetOf(fromPosition);
        ERC20 toAsset = _assetOf(toPosition);
        assetsTo = fromAsset != toAsset ? _swap(fromAsset, assetsFrom, exchange, params, address(this)) : assetsFrom;

        // Deposit into position.
        _depositTo(toPosition, assetsTo);
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
     * @notice Calculates how many assets Strategist would earn performance fees
     * @param _totalAssets uint256 value of the total assets in the cellar
     * @return feeInAssets amount of assets
     * @return currentSharePrice current price of shares, used by _takePerformanceFee
     */
    function _previewPerformanceFees(uint256 _totalAssets)
        internal
        view
        returns (uint256 feeInAssets, uint256 currentSharePrice)
    {
        uint64 performanceFee = feeData.performanceFee;
        if (performanceFee == 0 || _totalAssets == 0) return (0, 0);
        uint256 highWatermark = feeData.highWatermark;
        uint256 singleShare = 10**(36 - asset.decimals()); // 36 comes from the high watermark desired precision(18) + decimals of cellar(18)
        currentSharePrice = _convertToAssets(singleShare, _totalAssets);
        if (highWatermark < currentSharePrice) {
            //find how many assets make up the fee
            uint256 yield = (currentSharePrice - highWatermark).mulDivDown(totalSupply, singleShare);
            feeInAssets = yield.mulWadDown(performanceFee);
        } else {
            return (0, 0);
        }
    }

    /**
     * @notice Mints cellar performance fee shares if current share price is above high watermark
     * @dev If performance fees are minted, the resulting HWM will be greater than the current share price
     *      since performance fees dilute share value.
     * @param _totalAssets uint256 value of the total assets in the cellar
     */
    function _takePerformanceFees(uint256 _totalAssets) internal {
        (uint256 feeInAssets, uint256 currentSharePrice) = _previewPerformanceFees(_totalAssets);
        if (feeInAssets > 0) {
            uint256 platformFeesInShares = _convertToFees(_convertToShares(feeInAssets, _totalAssets));
            if (platformFeesInShares > 0) {
                feeData.highWatermark = currentSharePrice;
                _mint(address(this), platformFeesInShares);
            }
        }
    }

    /**
     * @dev Calculate the amount of fees to mint such that value of fees after minting is not diluted.
     */
    function _convertToFees(uint256 feesInShares) internal view returns (uint256 fees) {
        // Saves an SLOAD.
        uint256 totalShares = totalSupply;

        // Get the amount of fees to mint. Without this, the value of fees minted would be slightly
        // diluted because total shares increased while total assets did not. This counteracts that.
        uint256 denominator = totalShares - feesInShares;
        fees = denominator > 0 ? feesInShares.mulDivUp(totalShares, denominator) : 0;
    }

    /**
     * @notice Emitted when platform fees are send to the Sommelier chain.
     * @param feesInSharesRedeemed amount of fees redeemed for assets to send
     * @param feesInAssetsSent amount of assets fees were redeemed for that were sent
     */
    event SendFees(uint256 feesInSharesRedeemed, uint256 feesInAssetsSent);

    /**
     * @notice Transfer accrued fees to the Sommelier chain to distribute.
     * @dev Fees are accrued as shares and redeemed upon transfer.
     * @dev assumes cellar's accounting asset is able to be transferred and sent to Cosmos
     */
    function sendFees() public onlyOwner {
        FeeData storage _feeData = feeData;
        if (_feeData.strategistPayoutAddress == address(0)) revert STATE_PayoutNotSet();
        uint256 _totalAssets = totalAssets();

        // Since this action mints shares, calculate outstanding performance fees due.
        _takePerformanceFees(_totalAssets);

        uint256 totalFees = balanceOf[address(this)];

        uint256 strategistFeeSharesDue = totalFees.mulWadDown(_feeData.strategistPerformanceCut);

        // Calculate platform fees earned.
        uint256 elapsedTime = block.timestamp - lastAccrual;
        uint256 platformFeeInAssets = (_totalAssets * elapsedTime * _feeData.platformFee) / 1e18 / 365 days;
        uint256 platformFees = _convertToFees(_convertToShares(platformFeeInAssets, _totalAssets));
        _mint(address(this), platformFees);
        totalFees += platformFees;

        strategistFeeSharesDue += platformFees.mulWadDown(_feeData.strategistPlatformCut);

        //transfer shares to strategist
        totalFees -= strategistFeeSharesDue;
        balanceOf[address(this)] = totalFees;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[_feeData.strategistPayoutAddress] += strategistFeeSharesDue;
        }

        emit Transfer(address(this), _feeData.strategistPayoutAddress, strategistFeeSharesDue);

        lastAccrual = uint32(block.timestamp);

        // Redeem our fee shares for assets to send to the fee distributor module.
        uint256 assets = _convertToAssets(totalFees, _totalAssets);
        if (assets == 0) revert USR_ZeroAssets();

        _burn(address(this), totalFees);

        // Transfer assets to a fee distributor on the Sommelier chain.
        IGravity gravityBridge = IGravity(registry.getAddress(0));
        asset.safeApprove(address(gravityBridge), assets);
        gravityBridge.sendToCosmos(address(asset), _feeData.feesDistributor, assets);

        emit SendFees(totalFees, assets);
    }

    // ========================================== HELPER FUNCTIONS ==========================================

    /**
     * @dev Deposit into a position according to its position type and update related state.
     */
    function _depositTo(address position, uint256 assets) internal {
        PositionType positionType = getPositionType[position];

        // Deposit into position.
        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            ERC4626(position).asset().safeApprove(position, assets);
            ERC4626(position).deposit(assets, address(this));
        }
    }

    /**
     * @dev Withdraw from a position according to its position type and update related state.
     */
    function _withdrawFrom(
        address position,
        uint256 assets,
        address receiver
    ) internal {
        PositionType positionType = getPositionType[position];

        // Withdraw from position.
        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            ERC4626(position).withdraw(assets, receiver, address(this));
        } else {
            if (receiver != address(this)) ERC20(position).safeTransfer(receiver, assets);
        }
    }

    /**
     * @dev Get the balance of a position according to its position type.
     */
    function _balanceOf(address position) internal view returns (uint256) {
        PositionType positionType = getPositionType[position];

        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            return ERC4626(position).maxWithdraw(address(this));
        } else {
            return ERC20(position).balanceOf(address(this));
        }
    }

    /**
     * @dev Get the asset of a position according to its position type.
     */
    function _assetOf(address position) internal view returns (ERC20) {
        PositionType positionType = getPositionType[position];

        if (positionType == PositionType.ERC4626 || positionType == PositionType.Cellar) {
            return ERC4626(position).asset();
        } else {
            return ERC20(position);
        }
    }

    /**
     * @dev Perform a swap using the swap router and check that it behaves as expected.
     */
    function _swap(
        ERC20 assetIn,
        uint256 amountIn,
        SwapRouter.Exchange exchange,
        bytes calldata params,
        address receiver
    ) internal returns (uint256 amountOut) {
        // Store the expected amount of the asset in that we expect to have after the swap.
        uint256 expectedAssetsInAfter = assetIn.balanceOf(address(this)) - amountIn;

        // Get the address of the latest swap router.
        SwapRouter swapRouter = SwapRouter(registry.getAddress(1));

        // Approve swap router to swap assets.
        assetIn.safeApprove(address(swapRouter), amountIn);

        // Perform swap.
        amountOut = swapRouter.swap(exchange, params, receiver);

        // Check that the amount of assets swapped is what is expected. Will revert if the `params`
        // specified a different amount of assets to swap then `amountIn`.
        if (assetIn.balanceOf(address(this)) != expectedAssetsInAfter) revert STATE_WrongSwapParams();
    }
}
