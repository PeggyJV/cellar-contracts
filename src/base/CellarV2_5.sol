// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, SafeTransferLib, Math, ERC20 } from "./ERC4626.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IGravity } from "src/interfaces/external/IGravity.sol";
import { Uint32Array } from "src/utils/Uint32Array.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { Owned } from "@solmate/auth/Owned.sol";

/**
 * @title Sommelier Cellar
 * @notice A composable ERC4626 that can use arbitrary DeFi assets/positions using adaptors.
 * @author crispymangoes
 */
contract CellarV2_5 is ERC4626, Owned, ERC721Holder {
    using Uint32Array for uint32[];
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    // ========================================= MULTICALL =========================================

    /**
     * @notice Allows caller to call multiple functions in a single TX.
     * @dev Does NOT return the function return values.
     */
    function multicall(bytes[] calldata data) external {
        for (uint256 i = 0; i < data.length; i++) address(this).functionDelegateCall(data[i]);
    }

    // ========================================= REENTRANCY GUARD =========================================

    /**
     * @notice `locked` is public, so that the state can be checked even during view function calls.
     */
    uint256 public locked = 1;

    modifier nonReentrant() {
        require(locked == 1, "REENTRANCY");

        locked = 2;

        _;

        locked = 1;
    }

    // ========================================= PRICE ROUTER CACHE =========================================

    /**
     * @notice Cached price router contract.
     * @dev This way cellar has to "opt in" to price router changes.
     */
    PriceRouter public priceRouter;

    /**
     * @notice Updates the cellar to use the lastest price router in the registry.
     * @param checkTotalAssets If true totalAssets is checked before and after updating the price router,
     *        and is verified to be withing a +- 5% envelope.
     *        If false totalAssets is only called after updating the price router.]
     * @param allowableRange The +- range the total assets may deviate between the old and new price router.
     *                       - 1_000 == 10%
     *                       - 500 == 5%
     * @dev `allowableRange` reverts from arithmetic underflow if it is greater than 10_000, this is
     *      desired behavior.
     */
    function cachePriceRouter(bool checkTotalAssets, uint16 allowableRange) external onlyOwner {
        uint256 minAssets;
        uint256 maxAssets;

        if (checkTotalAssets) {
            uint256 assetsBefore = totalAssets();
            minAssets = assetsBefore.mulDivDown(1e4 - allowableRange, 1e4);
            maxAssets = assetsBefore.mulDivDown(1e4 + allowableRange, 1e4);
        }

        priceRouter = PriceRouter(registry.getAddress(PRICE_ROUTER_REGISTRY_SLOT));
        uint256 assetsAfter = totalAssets();

        if (checkTotalAssets) {
            if (assetsAfter < minAssets || assetsAfter > maxAssets)
                revert Cellar__TotalAssetDeviatedOutsideRange(assetsAfter, minAssets, maxAssets);
        }
    }

    // ========================================= POSITIONS CONFIG =========================================

    /**
     * @notice Emitted when a position is added.
     * @param position id of position that was added
     * @param index index that position was added at
     */
    event PositionAdded(uint32 position, uint256 index);

    /**
     * @notice Emitted when a position is removed.
     * @param position id of position that was removed
     * @param index index that position was removed from
     */
    event PositionRemoved(uint32 position, uint256 index);

    /**
     * @notice Emitted when the positions at two indexes are swapped.
     * @param newPosition1 id of position (previously at index2) that replaced index1.
     * @param newPosition2 id of position (previously at index1) that replaced index2.
     * @param index1 index of first position involved in the swap
     * @param index2 index of second position involved in the swap.
     */
    event PositionSwapped(uint32 newPosition1, uint32 newPosition2, uint256 index1, uint256 index2);

    /**
     * @notice Emitted when Governance adds/removes a position to/from the cellars catalogue.
     */
    event PositionCatalogueAltered(uint32 positionId, bool inCatalogue);

    /**
     * @notice Emitted when Governance adds/removes an adaptor to/from the cellars catalogue.
     */
    event AdaptorCatalogueAltered(address adaptor, bool inCatalogue);

    /**
     * @notice Attempted to add a position that is already being used.
     * @param position id of the position
     */
    error Cellar__PositionAlreadyUsed(uint32 position);

    /**
     * @notice Attempted to make an unused position the holding position.
     * @param position id of the position
     */
    error Cellar__PositionNotUsed(uint32 position);

    /**
     * @notice Attempted to add a position that is not in the catalogue.
     * @param position id of the position
     */
    error Cellar__PositionNotInCatalogue(uint32 position);

    /**
     * @notice Attempted an action on a position that is required to be empty before the action can be performed.
     * @param position address of the non-empty position
     * @param sharesRemaining amount of shares remaining in the position
     */
    error Cellar__PositionNotEmpty(uint32 position, uint256 sharesRemaining);

    /**
     * @notice Attempted an operation with an asset that was different then the one expected.
     * @param asset address of the asset
     * @param expectedAsset address of the expected asset
     */
    error Cellar__AssetMismatch(address asset, address expectedAsset);

    /**
     * @notice Attempted to add a position when the position array is full.
     * @param maxPositions maximum number of positions that can be used
     */
    error Cellar__PositionArrayFull(uint256 maxPositions);

    /**
     * @notice Attempted to add a position, with mismatched debt.
     * @param position the posiiton id that was mismatched
     */
    error Cellar__DebtMismatch(uint32 position);

    /**
     * @notice Attempted to remove the Cellars holding position.
     */
    error Cellar__RemovingHoldingPosition();

    /**
     * @notice Attempted to add an invalid holding position.
     * @param positionId the id of the invalid position.
     */
    error Cellar__InvalidHoldingPosition(uint32 positionId);

    /**
     * @notice Array of uint32s made up of cellars credit positions Ids.
     */
    uint32[] public creditPositions;

    /**
     * @notice Array of uint32s made up of cellars debt positions Ids.
     */
    uint32[] public debtPositions;

    /**
     * @notice Tell whether a position is currently used.
     */
    mapping(uint256 => bool) public isPositionUsed;

    /**
     * @notice Get position data given position id.
     */
    mapping(uint32 => Registry.PositionData) public getPositionData;

    /**
     * @notice Get the ids of the credit positions currently used by the cellar.
     */
    function getCreditPositions() external view returns (uint32[] memory) {
        return creditPositions;
    }

    /**
     * @notice Get the ids of the debt positions currently used by the cellar.
     */
    function getDebtPositions() external view returns (uint32[] memory) {
        return debtPositions;
    }

    /**
     * @notice Maximum amount of positions a cellar can have in it's credit/debt arrays.
     */
    uint256 public constant MAX_POSITIONS = 16;

    /**
     * @notice Stores the index of the holding position in the creditPositions array.
     */
    uint32 public holdingPosition;

    /**
     * @notice Allows owner to change the holding position.
     */
    function setHoldingPosition(uint32 positionId) external onlyOwner {
        _setHoldingPosition(positionId);
    }

    function _setHoldingPosition(uint32 positionId) internal {
        if (!isPositionUsed[positionId]) revert Cellar__PositionNotUsed(positionId);
        if (_assetOf(positionId) != asset) revert Cellar__AssetMismatch(address(asset), address(_assetOf(positionId)));
        if (getPositionData[positionId].isDebt) revert Cellar__InvalidHoldingPosition(positionId);
        holdingPosition = positionId;
    }

    /**
     * @notice Positions the strategist is approved to use without any governance intervention.
     */
    mapping(uint32 => bool) public positionCatalogue;

    /**
     * @notice Adaptors the strategist is approved to use without any governance intervention.
     */
    mapping(address => bool) public adaptorCatalogue;

    /**
     * @notice Allows Governance to add positions to this cellar's catalogue.
     */
    function addPositionToCatalogue(uint32 positionId) external onlyOwner {
        _addPositionToCatalogue(positionId);
    }

    /**
     * @notice Helper function that checks the position is trusted.
     */
    function _addPositionToCatalogue(uint32 positionId) internal {
        // Make sure position is not paused and is trusted.
        registry.revertIfPositionIsNotTrusted(positionId);
        positionCatalogue[positionId] = true;
        emit PositionCatalogueAltered(positionId, true);
    }

    /**
     * @notice Allows Governance to remove positions from this cellar's catalogue.
     */
    function removePositionFromCatalogue(uint32 positionId) external onlyOwner {
        positionCatalogue[positionId] = false;
        emit PositionCatalogueAltered(positionId, false);
    }

    /**
     * @notice Allows Governance to add adaptors to this cellar's catalogue.
     */
    function addAdaptorToCatalogue(address adaptor) external onlyOwner {
        // Make sure adaptor is not paused and is trusted.
        registry.revertIfAdaptorIsNotTrusted(adaptor);
        adaptorCatalogue[adaptor] = true;
        emit AdaptorCatalogueAltered(adaptor, true);
    }

    /**
     * @notice Allows Governance to remove adaptors from this cellar's catalogue.
     */
    function removeAdaptorFromCatalogue(address adaptor) external onlyOwner {
        adaptorCatalogue[adaptor] = false;
        emit AdaptorCatalogueAltered(adaptor, false);
    }

    /**
     * @notice Insert a trusted position to the list of positions used by the cellar at a given index.
     * @param index index at which to insert the position
     * @param positionId id of position to add
     * @param configurationData data used to configure how the position behaves
     */
    function addPosition(
        uint32 index,
        uint32 positionId,
        bytes memory configurationData,
        bool inDebtArray
    ) external onlyOwner {
        _whenNotShutdown();
        _addPosition(index, positionId, configurationData, inDebtArray);
    }

    /**
     * @notice Internal function is used by `addPosition` and initialize function.
     */
    function _addPosition(uint32 index, uint32 positionId, bytes memory configurationData, bool inDebtArray) internal {
        // Check if position is already being used.
        if (isPositionUsed[positionId]) revert Cellar__PositionAlreadyUsed(positionId);

        // Check if position is in the position catalogue.
        if (!positionCatalogue[positionId]) revert Cellar__PositionNotInCatalogue(positionId);

        // Grab position data from registry.
        // Also checks if position is not trusted and reverts if so.
        (address adaptor, bool isDebt, bytes memory adaptorData) = registry.addPositionToCellar(positionId);

        if (isDebt != inDebtArray) revert Cellar__DebtMismatch(positionId);

        // Copy position data from registry to here.
        getPositionData[positionId] = Registry.PositionData({
            adaptor: adaptor,
            isDebt: isDebt,
            adaptorData: adaptorData,
            configurationData: configurationData
        });

        if (isDebt) {
            if (debtPositions.length >= MAX_POSITIONS) revert Cellar__PositionArrayFull(MAX_POSITIONS);
            // Add new position at a specified index.
            debtPositions.add(index, positionId);
        } else {
            if (creditPositions.length >= MAX_POSITIONS) revert Cellar__PositionArrayFull(MAX_POSITIONS);
            // Add new position at a specified index.
            creditPositions.add(index, positionId);
        }

        isPositionUsed[positionId] = true;

        emit PositionAdded(positionId, index);
    }

    /**
     * @notice Remove the position at a given index from the list of positions used by the cellar.
     * @dev Called by strategist.
     * @param index index at which to remove the position
     */
    function removePosition(uint32 index, bool inDebtArray) external onlyOwner {
        // Get position being removed.
        uint32 positionId = inDebtArray ? debtPositions[index] : creditPositions[index];
        // Only remove position if it is empty, and if it is not the holding position.
        uint256 positionBalance = _balanceOf(positionId);
        if (positionBalance > 0) revert Cellar__PositionNotEmpty(positionId, positionBalance);

        _removePosition(index, positionId, inDebtArray);
    }

    /**
     * @notice Allows Governance to force a cellar out of a position without making ANY external calls.
     */
    function forcePositionOut(uint32 index, uint32 positionId, bool inDebtArray) external onlyOwner {
        _removePosition(index, positionId, inDebtArray);
    }

    /**
     * @notice Internal helper function to remove positions from cellars tracked arrays.
     */
    function _removePosition(uint32 index, uint32 positionId, bool inDebtArray) internal {
        if (positionId == holdingPosition) revert Cellar__RemovingHoldingPosition();

        if (inDebtArray) {
            // Remove position at the given index.
            debtPositions.remove(index);
        } else {
            creditPositions.remove(index);
        }

        isPositionUsed[positionId] = false;
        delete getPositionData[positionId];

        emit PositionRemoved(positionId, index);
    }

    /**
     * @notice Swap the positions at two given indexes.
     * @param index1 index of first position to swap
     * @param index2 index of second position to swap
     * @param inDebtArray bool indicating to switch positions in the debt array, or the credit array.
     */
    function swapPositions(uint32 index1, uint32 index2, bool inDebtArray) external onlyOwner {
        // Get the new positions that will be at each index.
        uint32 newPosition1;
        uint32 newPosition2;

        if (inDebtArray) {
            newPosition1 = debtPositions[index2];
            newPosition2 = debtPositions[index1];
            // Swap positions.
            (debtPositions[index1], debtPositions[index2]) = (newPosition1, newPosition2);
        } else {
            newPosition1 = creditPositions[index2];
            newPosition2 = creditPositions[index1];
            // Swap positions.
            (creditPositions[index1], creditPositions[index2]) = (newPosition1, newPosition2);
        }

        emit PositionSwapped(newPosition1, newPosition2, index1, index2);
    }

    // =============================================== FEES CONFIG ===============================================

    /**
     * @notice Emitted when platform fees is changed.
     * @param oldPlatformFee value platform fee was changed from
     * @param newPlatformFee value platform fee was changed to
     */
    event PlatformFeeChanged(uint64 oldPlatformFee, uint64 newPlatformFee);

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
     * @notice Attempted to change strategist fee cut with invalid value.
     */
    error Cellar__InvalidFeeCut();

    /**
     * @notice Attempted to change platform fee with invalid value.
     */
    error Cellar__InvalidFee();

    /**
     * @notice Data related to fees.
     * @param strategistPlatformCut Determines how much platform fees go to strategist.
     *                              This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     * @param platformFee The percentage of total assets accrued as platform fees over a year.
                          This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     * @param strategistPayoutAddress Address to send the strategists fee shares.
     */
    struct FeeData {
        uint64 strategistPlatformCut;
        uint64 platformFee;
        uint64 lastAccrual;
        address strategistPayoutAddress;
    }

    /**
     * @notice Stores all fee data for cellar.
     */
    FeeData public feeData =
        FeeData({
            strategistPlatformCut: 0.75e18,
            platformFee: 0.01e18,
            lastAccrual: 0,
            strategistPayoutAddress: address(0)
        });

    /**
     * @notice Sets the max possible performance fee for this cellar.
     */
    uint64 public constant MAX_PLATFORM_FEE = 0.2e18;

    /**
     * @notice Sets the max possible fee cut for this cellar.
     */
    uint64 public constant MAX_FEE_CUT = 1e18;

    /**
     * @notice Sets the Strategists cut of platform fees
     * @param cut the platform cut for the strategist
     */
    function setStrategistPlatformCut(uint64 cut) external onlyOwner {
        if (cut > MAX_FEE_CUT) revert Cellar__InvalidFeeCut();
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

    // =========================================== EMERGENCY LOGIC ===========================================

    /**
     * @notice Emitted when cellar emergency state is changed.
     * @param isShutdown whether the cellar is shutdown
     */
    event ShutdownChanged(bool isShutdown);

    /**
     * @notice Attempted action was prevented due to contract being shutdown.
     */
    error Cellar__ContractShutdown();

    /**
     * @notice Attempted action was prevented due to contract not being shutdown.
     */
    error Cellar__ContractNotShutdown();

    /**
     * @notice Attempted to interact with the cellar when it is paused.
     */
    error Cellar__Paused();

    /**
     * @notice Whether or not the contract is shutdown in case of an emergency.
     */
    bool public isShutdown;

    /**
     * @notice Pauses all user entry/exits, and strategist rebalances.
     */
    bool public ignorePause;

    /**
     * @notice View function external contracts can use to see if the cellar is paused.
     */
    function isPaused() external view returns (bool) {
        if (!ignorePause) {
            return registry.isCallerPaused(address(this));
        }
        return false;
    }

    /**
     * @notice Pauses all user entry/exits, and strategist rebalances.
     */
    function _checkIfPaused() internal view {
        if (!ignorePause) {
            if (registry.isCallerPaused(address(this))) revert Cellar__Paused();
        }
    }

    /**
     * @notice Allows governance to choose whether or not to respect a pause.
     */
    function toggleIgnorePause(bool toggle) external onlyOwner {
        ignorePause = toggle;
    }

    /**
     * @notice Prevent a function from being called during a shutdown.
     */
    function _whenNotShutdown() internal view {
        if (isShutdown) revert Cellar__ContractShutdown();
    }

    /**
     * @notice Shutdown the cellar. Used in an emergency or if the cellar has been deprecated.
     * @dev In the case where
     */
    function initiateShutdown() external onlyOwner {
        _whenNotShutdown();
        isShutdown = true;

        emit ShutdownChanged(true);
    }

    /**
     * @notice Restart the cellar.
     */
    function liftShutdown() external onlyOwner {
        if (!isShutdown) revert Cellar__ContractNotShutdown();
        isShutdown = false;

        emit ShutdownChanged(false);
    }

    // =========================================== CONSTRUCTOR ===========================================

    /**
     * @notice Id to get the gravity bridge from the registry.
     */
    uint256 public constant GRAVITY_BRIDGE_REGISTRY_SLOT = 0;

    /**
     * @notice Id to get the price router from the registry.
     */
    uint256 public constant PRICE_ROUTER_REGISTRY_SLOT = 2;

    /**
     * @notice Address of the platform's registry contract. Used to get the latest address of modules.
     */
    Registry public registry;

    /**
     * @dev Owner should be set to the Gravity Bridge, which relays instructions from the Steward
     *      module to the cellars.
     *      https://github.com/PeggyJV/steward
     *      https://github.com/cosmos/gravity-bridge/blob/main/solidity/contracts/Gravity.sol
     * @param _registry address of the platform's registry contract
     * @param _asset address of underlying token used for the for accounting, depositing, and withdrawing
     * @param _name name of this cellar's share token
     * @param _symbol symbol of this cellar's share token
     * @param params abi encode values.
     *               -  _creditPositions ids of the credit positions to initialize the cellar with
     *               -  _debtPositions ids of the credit positions to initialize the cellar with
     *               -  _creditConfigurationData configuration data for each position
     *               -  _debtConfigurationData configuration data for each position
     *               -  _holdingIndex the index in _creditPositions to use as the holding position.
     *               -  _strategistPayout the address to send the strategists fee shares.
     *               -  _assetRiskTolerance this cellars risk tolerance for assets it is exposed to
     *               -  _protocolRiskTolerance this cellars risk tolerance for protocols it will use
     */
    constructor(
        Registry _registry,
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        bytes memory params
    ) ERC4626(_asset, _name, _symbol, 18) Owned(_registry.getAddress(GRAVITY_BRIDGE_REGISTRY_SLOT)) {
        registry = _registry;
        priceRouter = PriceRouter(registry.getAddress(PRICE_ROUTER_REGISTRY_SLOT));

        {
            (
                uint32[] memory _creditPositions,
                uint32[] memory _debtPositions,
                bytes[] memory _creditConfigurationData,
                bytes[] memory _debtConfigurationData,
                uint32 _holdingPosition
            ) = abi.decode(params, (uint32[], uint32[], bytes[], bytes[], uint8));

            // Initialize positions.
            for (uint32 i; i < _creditPositions.length; ++i) {
                _addPositionToCatalogue(_creditPositions[i]);
                _addPosition(i, _creditPositions[i], _creditConfigurationData[i], false);
            }
            for (uint32 i; i < _debtPositions.length; ++i) {
                _addPositionToCatalogue(_debtPositions[i]);
                _addPosition(i, _debtPositions[i], _debtConfigurationData[i], true);
            }
            // This check allows us to deploy an implementation contract.
            /// @dev No cellars will be deployed with a zero length credit positions array.
            if (_creditPositions.length > 0) _setHoldingPosition(_holdingPosition);
        }

        // Initialize last accrual timestamp to time that cellar was created, otherwise the first
        // `accrue` will take platform fees from 1970 to the time it is called.
        feeData.lastAccrual = uint64(block.timestamp);

        (, , , , , address _strategistPayout, , ) = abi.decode(
            params,
            (uint32[], uint32[], bytes[], bytes[], uint8, address, uint128, uint128)
        );

        feeData.strategistPayoutAddress = _strategistPayout;
    }

    // =========================================== CORE LOGIC ===========================================

    /**
     * @notice Emitted when share locking period is changed.
     * @param oldPeriod the old locking period
     * @param newPeriod the new locking period
     */
    event ShareLockingPeriodChanged(uint256 oldPeriod, uint256 newPeriod);

    /**
     * @notice Attempted an action with zero shares.
     */
    error Cellar__ZeroShares();

    /**
     * @notice Attempted an action with zero assets.
     */
    error Cellar__ZeroAssets();

    /**
     * @notice Withdraw did not withdraw all assets.
     * @param assetsOwed the remaining assets owed that were not withdrawn.
     */
    error Cellar__IncompleteWithdraw(uint256 assetsOwed);

    /**
     * @notice Attempted to withdraw an illiquid position.
     * @param illiquidPosition the illiquid position.
     */
    error Cellar__IlliquidWithdraw(address illiquidPosition);

    /**
     * @notice Attempted to set `shareLockPeriod` to an invalid number.
     */
    error Cellar__InvalidShareLockPeriod();

    /**
     * @notice Attempted to burn shares when they are locked.
     * @param timeSharesAreUnlocked time when caller can transfer/redeem shares
     * @param currentBlock the current block number.
     */
    error Cellar__SharesAreLocked(uint256 timeSharesAreUnlocked, uint256 currentBlock);

    /**
     * @notice Attempted deposit on behalf of a user without being approved.
     */
    error Cellar__NotApprovedToDepositOnBehalf(address depositor);

    /**
     * @notice Shares must be locked for at least 5 minutes after minting.
     */
    uint256 public constant MINIMUM_SHARE_LOCK_PERIOD = 5 * 60;

    /**
     * @notice Shares can be locked for at most 2 days after minting.
     */
    uint256 public constant MAXIMUM_SHARE_LOCK_PERIOD = 2 days;

    /**
     * @notice After deposits users must wait `shareLockPeriod` time before being able to transfer or withdraw their shares.
     */
    uint256 public shareLockPeriod = MAXIMUM_SHARE_LOCK_PERIOD;

    /**
     * @notice mapping that stores every users last time stamp they minted shares.
     */
    mapping(address => uint256) public userShareLockStartTime;

    // TODO remove sharelock period logic
    /**
     * @notice Allows share lock period to be updated.
     * @param newLock the new lock period
     */
    function setShareLockPeriod(uint256 newLock) external onlyOwner {
        if (newLock < MINIMUM_SHARE_LOCK_PERIOD || newLock > MAXIMUM_SHARE_LOCK_PERIOD)
            revert Cellar__InvalidShareLockPeriod();
        uint256 oldLockingPeriod = shareLockPeriod;
        shareLockPeriod = newLock;
        emit ShareLockingPeriodChanged(oldLockingPeriod, newLock);
    }

    /**
     * @notice helper function that checks enough time has passed to unlock shares.
     * @param owner the address of the user to check
     */
    function _checkIfSharesLocked(address owner) internal view {
        uint256 lockTime = userShareLockStartTime[owner];
        if (lockTime != 0) {
            uint256 timeSharesAreUnlocked = lockTime + shareLockPeriod;
            if (timeSharesAreUnlocked > block.timestamp)
                revert Cellar__SharesAreLocked(timeSharesAreUnlocked, block.timestamp);
        }
    }

    /**
     * @notice Override `transfer` to add share lock check.
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        _checkIfSharesLocked(msg.sender);
        return super.transfer(to, amount);
    }

    /**
     * @notice Override `transferFrom` to add share lock check.
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _checkIfSharesLocked(from);
        return super.transferFrom(from, to, amount);
    }

    /**
     * @notice Attempted deposit more than the max deposit.
     * @param assets the assets user attempted to deposit
     * @param maxDeposit the max assets that can be deposited
     */
    error Cellar__DepositRestricted(uint256 assets, uint256 maxDeposit);

    // TODO remove approvedForDepositOnBehalf logic
    /**
     * @notice called at the beginning of deposit.
     * @param assets amount of assets deposited by user.
     * @param receiver address receiving the shares.
     */
    function beforeDeposit(uint256 assets, uint256, address receiver) internal view override {
        _whenNotShutdown();
        _checkIfPaused();
        if (msg.sender != receiver) {
            if (!registry.approvedForDepositOnBehalf(msg.sender))
                revert Cellar__NotApprovedToDepositOnBehalf(msg.sender);
        }
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) revert Cellar__DepositRestricted(assets, maxAssets);
    }

    /**
     * @notice called at the end of deposit.
     * @param assets amount of assets deposited by user.
     */
    function afterDeposit(uint256 assets, uint256, address receiver) internal override {
        _depositTo(holdingPosition, assets);
        userShareLockStartTime[receiver] = block.timestamp;
    }

    /**
     * @notice called at the beginning of withdraw.
     */
    function beforeWithdraw(uint256, uint256, address, address owner) internal view override {
        _checkIfPaused();
        // Make sure users shares are not locked.
        _checkIfSharesLocked(owner);
    }

    function _enter(uint256 assets, uint256 shares, address receiver) internal {
        beforeDeposit(assets, shares, receiver);

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares, receiver);
    }

    // TODO refactor so they use a shareprice instead of totalAssets
    /**
     * @notice Deposits assets into the cellar, and returns shares to receiver.
     * @param assets amount of assets deposited by user.
     * @param receiver address to receive the shares.
     * @return shares amount of shares given for deposit.
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        // Use `_accounting` instead of totalAssets bc re-entrancy is already checked in this function.
        uint256 _totalAssets = _accounting(false);

        // Check for rounding error since we round down in previewDeposit.
        if ((shares = _convertToShares(assets, _totalAssets)) == 0) revert Cellar__ZeroShares();

        _enter(assets, shares, receiver);
    }

    /**
     * @notice Mints shares from the cellar, and returns shares to receiver.
     * @param shares amount of shares requested by user.
     * @param receiver address to receive the shares.
     * @return assets amount of assets deposited into the cellar.
     */
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        // Use `_accounting` instead of totalAssets bc re-entrancy is already checked in this function.
        uint256 _totalAssets = _accounting(false);

        // previewMint rounds up, but initial mint could return zero assets, so check for rounding error.
        if ((assets = _previewMint(shares, _totalAssets)) == 0) revert Cellar__ZeroAssets();

        _enter(assets, shares, receiver);
    }

    function _exit(uint256 assets, uint256 shares, address receiver, address owner) internal {
        beforeWithdraw(assets, shares, receiver, owner);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        _withdrawInOrder(assets, receiver);

        /// @notice `afterWithdraw` is currently not used.
        // afterWithdraw(assets, shares, receiver, owner);
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
    ) public override nonReentrant returns (uint256 shares) {
        // Use `_accounting` instead of totalAssets bc re-entrancy is already checked in this function.
        uint256 _totalAssets = _accounting(false);

        // No need to check for rounding error, `previewWithdraw` rounds up.
        shares = _previewWithdraw(assets, _totalAssets);

        _exit(assets, shares, receiver, owner);
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
    ) public override nonReentrant returns (uint256 assets) {
        // Use `_accounting` instead of totalAssets bc re-entrancy is already checked in this function.
        uint256 _totalAssets = _accounting(false);

        // Check for rounding error since we round down in previewRedeem.
        if ((assets = _convertToAssets(shares, _totalAssets)) == 0) revert Cellar__ZeroAssets();

        _exit(assets, shares, receiver, owner);
    }

    /**
     * @notice Struct used in `_withdrawInOrder` in order to hold multiple pricing values in a single variable.
     * @dev Prevents stack too deep errors.
     */
    struct WithdrawPricing {
        uint256 priceBaseUSD;
        uint256 oneBase;
        uint256 priceQuoteUSD;
        uint256 oneQuote;
    }

    /**
     * @notice Multipler used to insure calculations use very high precision.
     */
    uint256 private constant PRECISION_MULTIPLIER = 1e18;

    /**
     * @dev Withdraw from positions in the order defined by `positions`.
     * @param assets the amount of assets to withdraw from cellar
     * @param receiver the address to sent withdrawn assets to
     * @dev Only loop through credit array because debt can not be withdraw by users.
     */
    function _withdrawInOrder(uint256 assets, address receiver) internal {
        // Save asset price in USD, and decimals to reduce external calls.
        WithdrawPricing memory pricingInfo;
        pricingInfo.priceQuoteUSD = priceRouter.getPriceInUSD(asset);
        pricingInfo.oneQuote = 10 ** asset.decimals();
        uint256 creditLength = creditPositions.length;
        for (uint256 i; i < creditLength; ++i) {
            uint32 position = creditPositions[i];
            uint256 withdrawableBalance = _withdrawableFrom(position);
            // Move on to next position if this one is empty.
            if (withdrawableBalance == 0) continue;
            ERC20 positionAsset = _assetOf(position);

            pricingInfo.priceBaseUSD = priceRouter.getPriceInUSD(positionAsset);
            pricingInfo.oneBase = 10 ** positionAsset.decimals();
            uint256 totalWithdrawableBalanceInAssets;
            {
                uint256 withdrawableBalanceInUSD = (PRECISION_MULTIPLIER * withdrawableBalance).mulDivDown(
                    pricingInfo.priceBaseUSD,
                    pricingInfo.oneBase
                );
                totalWithdrawableBalanceInAssets = withdrawableBalanceInUSD.mulDivDown(
                    pricingInfo.oneQuote,
                    pricingInfo.priceQuoteUSD
                );
                totalWithdrawableBalanceInAssets = totalWithdrawableBalanceInAssets / PRECISION_MULTIPLIER;
            }

            // We want to pull as much as we can from this position, but no more than needed.
            uint256 amount;

            if (totalWithdrawableBalanceInAssets > assets) {
                // Convert assets into position asset.
                uint256 assetsInUSD = (PRECISION_MULTIPLIER * assets).mulDivDown(
                    pricingInfo.priceQuoteUSD,
                    pricingInfo.oneQuote
                );
                amount = assetsInUSD.mulDivDown(pricingInfo.oneBase, pricingInfo.priceBaseUSD);
                amount = amount / PRECISION_MULTIPLIER;
                assets = 0;
            } else {
                amount = withdrawableBalance;
                assets = assets - totalWithdrawableBalanceInAssets;
            }

            // Withdraw from position.
            _withdrawFrom(position, amount, receiver);

            // Stop if no more assets to withdraw.
            if (assets == 0) break;
        }
        // If withdraw did not remove all assets owed, revert.
        if (assets > 0) revert Cellar__IncompleteWithdraw(assets);
    }

    // ========================================= ACCOUNTING LOGIC =========================================

    // TODO probs need a new internal function to call to get totalAssets
    function _getSharePrice() internal view returns (uint256 lastUpdated, uint256 twasp) {
        // Grab info from oracle which could be this contract
        // See if we can use the oracle share price
        // if not either revert, or default to _accounting(false)
    }

    // TODO new view funcitons to see saved share price and get twasp? would be in the oracle
    /**
     * @notice Internal accounting function that can report total assets, or total assets withdrawable.
     * @param reportWithdrawable if true, then the withdrawable total assets is reported,
     *                           if false, then the total assets is reported
     */
    function _accounting(bool reportWithdrawable) internal view returns (uint256 assets) {
        uint256 numOfCreditPositions = creditPositions.length;
        ERC20[] memory creditAssets = new ERC20[](numOfCreditPositions);
        uint256[] memory creditBalances = new uint256[](numOfCreditPositions);
        // If we just need the withdrawable, then query credit array value.
        if (reportWithdrawable) {
            for (uint256 i; i < numOfCreditPositions; ++i) {
                uint32 position = creditPositions[i];
                // If the withdrawable balance is zero there is no point to query the asset since a zero balance has zero value.
                if ((creditBalances[i] = _withdrawableFrom(position)) == 0) continue;
                creditAssets[i] = _assetOf(position);
            }
            assets = priceRouter.getValues(creditAssets, creditBalances, asset);
        } else {
            uint256 numOfDebtPositions = debtPositions.length;
            ERC20[] memory debtAssets = new ERC20[](numOfDebtPositions);
            uint256[] memory debtBalances = new uint256[](numOfDebtPositions);
            for (uint256 i; i < numOfCreditPositions; ++i) {
                uint32 position = creditPositions[i];
                // If the balance is zero there is no point to query the asset since a zero balance has zero value.
                if ((creditBalances[i] = _balanceOf(position)) == 0) continue;
                creditAssets[i] = _assetOf(position);
            }
            for (uint256 i; i < numOfDebtPositions; ++i) {
                uint32 position = debtPositions[i];
                // If the balance is zero there is no point to query the asset since a zero balance has zero value.
                if ((debtBalances[i] = _balanceOf(position)) == 0) continue;
                debtAssets[i] = _assetOf(position);
            }
            assets = priceRouter.getValuesDelta(creditAssets, creditBalances, debtAssets, debtBalances, asset);
        }
    }

    /**
     * @notice The total amount of assets in the cellar.
     * @dev EIP4626 states totalAssets needs to be inclusive of fees.
     * Since performance fees mint shares, total assets remains unchanged,
     * so this implementation is inclusive of fees even though it does not explicitly show it.
     * @dev EIP4626 states totalAssets must not revert, but it is possible for `totalAssets` to revert
     * so it does NOT conform to ERC4626 standards.
     * @dev Run a re-entrancy check because totalAssets can be wrong if re-entering from deposit/withdraws.
     */
    function totalAssets() public view override returns (uint256 assets) {
        _checkIfPaused();
        require(locked == 1, "REENTRANCY");
        assets = _accounting(false);
    }

    /**
     * @notice The total amount of withdrawable assets in the cellar.
     * @dev Run a re-entrancy check because totalAssetsWithdrawable can be wrong if re-entering from deposit/withdraws.
     */
    function totalAssetsWithdrawable() public view returns (uint256 assets) {
        _checkIfPaused();
        require(locked == 1, "REENTRANCY");
        assets = _accounting(true);
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

    // TODO preview functions will need to get the share price and use the upper or lower value
    /**
     * @notice Simulate the effects of minting shares at the current block, given current on-chain conditions.
     * @param shares amount of shares to mint
     * @return assets that will be deposited
     */
    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        uint256 _totalAssets = totalAssets();
        assets = _previewMint(shares, _totalAssets);
    }

    /**
     * @notice Simulate the effects of withdrawing assets at the current block, given current on-chain conditions.
     * @param assets amount of assets to withdraw
     * @return shares that will be redeemed
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        uint256 _totalAssets = totalAssets();
        shares = _previewWithdraw(assets, _totalAssets);
    }

    /**
     * @notice Simulate the effects of depositing assets at the current block, given current on-chain conditions.
     * @param assets amount of assets to deposit
     * @return shares that will be minted
     */
    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        uint256 _totalAssets = totalAssets();
        shares = _convertToShares(assets, _totalAssets);
    }

    /**
     * @notice Simulate the effects of redeeming shares at the current block, given current on-chain conditions.
     * @param shares amount of shares to redeem
     * @return assets that will be returned
     */
    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        uint256 _totalAssets = totalAssets();
        assets = _convertToAssets(shares, _totalAssets);
    }

    /**
     * @notice Finds the max amount of value an `owner` can remove from the cellar.
     * @param owner address of the user to find max value.
     * @param inShares if false, then returns value in terms of assets
     *                 if true then returns value in terms of shares
     */
    function _findMax(address owner, bool inShares) internal view returns (uint256 maxOut) {
        _checkIfPaused();
        // Check if owner shares are locked, return 0 if so.
        uint256 lockTime = userShareLockStartTime[owner];
        if (lockTime != 0) {
            uint256 timeSharesAreUnlocked = lockTime + shareLockPeriod;
            if (timeSharesAreUnlocked > block.timestamp) return 0;
        }
        // Get amount of assets to withdraw.
        uint256 _totalAssets = _accounting(false);
        uint256 assets = _convertToAssets(balanceOf[owner], _totalAssets);

        uint256 withdrawable = _accounting(true);
        maxOut = assets <= withdrawable ? assets : withdrawable;

        if (inShares) maxOut = _convertToShares(maxOut, _totalAssets);
        // else leave maxOut in terms of assets.
    }

    // TODO helper functions to use share price to get shares in or share out, given assets

    /**
     * @notice Returns the max amount withdrawable by a user inclusive of performance fees
     * @dev EIP4626 states maxWithdraw must not revert, but it is possible for `totalAssets` to revert
     * so it does NOT conform to ERC4626 standards.
     * @param owner address to check maxWithdraw of.
     * @return the max amount of assets withdrawable by `owner`.
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        require(locked == 1, "REENTRANCY");
        return _findMax(owner, false);
    }

    /**
     * @notice Returns the max amount shares redeemable by a user
     * @dev EIP4626 states maxRedeem must not revert, but it is possible for `totalAssets` to revert
     * so it does NOT conform to ERC4626 standards.
     * @param owner address to check maxRedeem of.
     * @return the max amount of shares redeemable by `owner`.
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        require(locked == 1, "REENTRANCY");
        return _findMax(owner, true);
    }

    /**
     * @dev Used to more efficiently convert amount of shares to assets using a stored `totalAssets` value.
     */
    function _convertToAssets(uint256 shares, uint256 _totalAssets) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply;

        assets = totalShares == 0
            ? shares.changeDecimals(18, asset.decimals())
            : shares.mulDivDown(_totalAssets, totalShares);
    }

    /**
     * @dev Used to more efficiently convert amount of assets to shares using a stored `totalAssets` value.
     */
    function _convertToShares(uint256 assets, uint256 _totalAssets) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply;

        shares = totalShares == 0
            ? assets.changeDecimals(asset.decimals(), 18)
            : assets.mulDivDown(totalShares, _totalAssets);
    }

    /**
     * @dev Used to more efficiently simulate minting shares using a stored `totalAssets` value.
     */
    function _previewMint(uint256 shares, uint256 _totalAssets) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply;

        assets = totalShares == 0
            ? shares.changeDecimals(18, asset.decimals())
            : shares.mulDivUp(_totalAssets, totalShares);
    }

    /**
     * @dev Used to more efficiently simulate withdrawing assets using a stored `totalAssets` value.
     */
    function _previewWithdraw(uint256 assets, uint256 _totalAssets) internal view returns (uint256 shares) {
        uint256 totalShares = totalSupply;

        shares = totalShares == 0
            ? assets.changeDecimals(asset.decimals(), 18)
            : assets.mulDivUp(totalShares, _totalAssets);
    }

    // =========================================== ADAPTOR LOGIC ===========================================

    /**
     * @notice Emitted on when the rebalance deviation is changed.
     * @param oldDeviation the old rebalance deviation
     * @param newDeviation the new rebalance deviation
     */
    event RebalanceDeviationChanged(uint256 oldDeviation, uint256 newDeviation);

    /**
     * @notice totalAssets deviated outside the range set by `allowedRebalanceDeviation`.
     * @param assets the total assets in the cellar
     * @param min the minimum allowed assets
     * @param max the maximum allowed assets
     */
    error Cellar__TotalAssetDeviatedOutsideRange(uint256 assets, uint256 min, uint256 max);

    /**
     * @notice Total shares in a cellar changed when they should stay constant.
     * @param current the current amount of total shares
     * @param expected the expected amount of total shares
     */
    error Cellar__TotalSharesMustRemainConstant(uint256 current, uint256 expected);

    /**
     * @notice Total shares in a cellar changed when they should stay constant.
     * @param requested the requested rebalance  deviation
     * @param max the max rebalance deviation.
     */
    error Cellar__InvalidRebalanceDeviation(uint256 requested, uint256 max);

    /**
     * @notice Strategist attempted to use an adaptor that is either paused or is not trusted by governance.
     * @param adaptor the adaptor address that is paused or not trusted.
     */
    error Cellar__CallToAdaptorNotAllowed(address adaptor);

    /**
     * @notice Stores the max possible rebalance deviation for this cellar.
     */
    uint64 public constant MAX_REBALANCE_DEVIATION = 0.1e18;

    /**
     * @notice The percent the total assets of a cellar may deviate during a `callOnAdaptor`(rebalance) call.
     */
    uint256 public allowedRebalanceDeviation = 0.0003e18;

    /**
     * @notice Allows governance to change this cellars rebalance deviation.
     * @param newDeviation the new rebalance deviation value.
     */
    function setRebalanceDeviation(uint256 newDeviation) external onlyOwner {
        if (newDeviation > MAX_REBALANCE_DEVIATION)
            revert Cellar__InvalidRebalanceDeviation(newDeviation, MAX_REBALANCE_DEVIATION);

        uint256 oldDeviation = allowedRebalanceDeviation;
        allowedRebalanceDeviation = newDeviation;

        emit RebalanceDeviationChanged(oldDeviation, newDeviation);
    }

    // Set to true before any adaptor calls are made.
    /**
     * @notice This bool is used to stop strategists from abusing Base Adaptor functions(deposit/withdraw).
     */
    bool public blockExternalReceiver;

    /**
     * @notice Struct used to make calls to adaptors.
     * @param adaptor the address of the adaptor to make calls to
     * @param the abi encoded function calls to make to the `adaptor`
     */
    struct AdaptorCall {
        address adaptor;
        bytes[] callData;
    }

    event AdaptorCalled(address adaptor, bytes data);

    /**
     * @notice Allows strategists to manage their Cellar using arbitrary logic calls to adaptors.
     * @dev There are several safety checks in this function to prevent strategists from abusing it.
     *      - `blockExternalReceiver`
     *      - `totalAssets` must not change by much
     *      - `totalShares` must remain constant
     *      - adaptors must be set up to be used with this cellar
     * @dev Since `totalAssets` is allowed to deviate slightly, strategists could abuse this by sending
     *      multiple `callOnAdaptor` calls rapidly, to gradually change the share price.
     *      To mitigate this, rate limiting will be put in place on the Sommelier side.
     */
    function callOnAdaptor(AdaptorCall[] memory data) external onlyOwner nonReentrant {
        _whenNotShutdown();
        _checkIfPaused();
        blockExternalReceiver = true;

        // Record `totalAssets` and `totalShares` before making any external calls.
        uint256 minimumAllowedAssets;
        uint256 maximumAllowedAssets;
        uint256 totalShares;
        {
            uint256 assetsBeforeAdaptorCall = _accounting(false);
            minimumAllowedAssets = assetsBeforeAdaptorCall.mulDivUp((1e18 - allowedRebalanceDeviation), 1e18);
            maximumAllowedAssets = assetsBeforeAdaptorCall.mulDivUp((1e18 + allowedRebalanceDeviation), 1e18);
            totalShares = totalSupply;
        }
        // TODO make this an internal function so that flash loan contracts can use it
        // Run all adaptor calls.
        for (uint8 i = 0; i < data.length; ++i) {
            address adaptor = data[i].adaptor;
            // Revert if adaptor not in catalogue, or adaptor is paused.
            if (!adaptorCatalogue[adaptor]) revert Cellar__CallToAdaptorNotAllowed(adaptor);
            for (uint8 j = 0; j < data[i].callData.length; j++) {
                adaptor.functionDelegateCall(data[i].callData[j]);
                emit AdaptorCalled(adaptor, data[i].callData[j]);
            }
        }

        // After making every external call, check that the totalAssets haas not deviated significantly, and that totalShares is the same.
        uint256 assets = _accounting(false);
        if (assets < minimumAllowedAssets || assets > maximumAllowedAssets) {
            revert Cellar__TotalAssetDeviatedOutsideRange(assets, minimumAllowedAssets, maximumAllowedAssets);
        }
        if (totalShares != totalSupply) revert Cellar__TotalSharesMustRemainConstant(totalSupply, totalShares);

        blockExternalReceiver = false;
    }

    // ========================================= Aave Flash Loan Support =========================================
    // TODO move this logic to a helper contract, that inherits from cellar.
    // IE contract CellarWithAaveFlashLoans
    /**
     * @notice External contract attempted to initiate a flash loan.
     */
    error Cellar__ExternalInitiator();

    /**
     * @notice executeOperation was not called by the Aave Pool.
     */
    error Cellar__CallerNotAavePool();

    /**
     * @notice The Aave V2 Pool contract on Ethereum Mainnet.
     */
    address public aavePool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;

    /**
     * @notice Allows strategist to utilize Aave flashloans while rebalancing the cellar.
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        if (initiator != address(this)) revert Cellar__ExternalInitiator();
        if (msg.sender != aavePool) revert Cellar__CallerNotAavePool();

        AdaptorCall[] memory data = abi.decode(params, (AdaptorCall[]));

        // Run all adaptor calls.
        for (uint8 i = 0; i < data.length; ++i) {
            address adaptor = data[i].adaptor;
            // Revert if adaptor not in catalogue, or adaptor is paused.
            if (!adaptorCatalogue[adaptor]) revert Cellar__CallToAdaptorNotAllowed(adaptor);
            for (uint8 j = 0; j < data[i].callData.length; j++) {
                adaptor.functionDelegateCall(data[i].callData[j]);
            }
        }

        // Approve pool to repay all debt.
        for (uint256 i = 0; i < amounts.length; ++i) {
            ERC20(assets[i]).safeApprove(aavePool, (amounts[i] + premiums[i]));
        }

        return true;
    }

    // ============================================ LIMITS LOGIC ============================================
    // TODO add TVL cap loweest priority
    /**
     * @notice Total amount of assets that can be deposited for a user.
     * @return assets maximum amount of assets that can be deposited
     */
    function maxDeposit(address) public view override returns (uint256) {
        if (isShutdown) return 0;

        return type(uint256).max;
    }

    /**
     * @notice Total amount of shares that can be minted for a user.
     * @return shares maximum amount of shares that can be minted
     */
    function maxMint(address) public view override returns (uint256) {
        if (isShutdown) return 0;

        return type(uint256).max;
    }

    // ========================================== HELPER FUNCTIONS ==========================================

    /**
     * @dev Deposit into a position according to its position type and update related state.
     * @param position address to deposit funds into
     * @param assets the amount of assets to deposit into the position
     */
    function _depositTo(uint32 position, uint256 assets) internal {
        address adaptor = getPositionData[position].adaptor;
        adaptor.functionDelegateCall(
            abi.encodeWithSelector(
                BaseAdaptor.deposit.selector,
                assets,
                getPositionData[position].adaptorData,
                getPositionData[position].configurationData
            )
        );
    }

    /**
     * @dev Withdraw from a position according to its position type and update related state.
     * @param position address to withdraw funds from
     * @param assets the amount of assets to withdraw from the position
     * @param receiver the address to sent withdrawn assets to
     */
    function _withdrawFrom(uint32 position, uint256 assets, address receiver) internal {
        address adaptor = getPositionData[position].adaptor;
        adaptor.functionDelegateCall(
            abi.encodeWithSelector(
                BaseAdaptor.withdraw.selector,
                assets,
                receiver,
                getPositionData[position].adaptorData,
                getPositionData[position].configurationData
            )
        );
    }

    /**
     * @dev Get the withdrawable balance of a position according to its position type.
     * @param position position to get the withdrawable balance of
     */
    function _withdrawableFrom(uint32 position) internal view returns (uint256) {
        // Debt positions always return 0 for their withdrawable.
        if (getPositionData[position].isDebt) return 0;
        return
            BaseAdaptor(getPositionData[position].adaptor).withdrawableFrom(
                getPositionData[position].adaptorData,
                getPositionData[position].configurationData
            );
    }

    /**
     * @dev Get the balance of a position according to its position type.
     * @dev For ERC4626 position balances, this uses `previewRedeem` as opposed
     *      to `convertToAssets` so that balanceOf ERC4626 positions includes fees taken on withdraw.
     * @param position position to get the balance of
     */
    function _balanceOf(uint32 position) internal view returns (uint256) {
        address adaptor = getPositionData[position].adaptor;
        return BaseAdaptor(adaptor).balanceOf(getPositionData[position].adaptorData);
    }

    /**
     * @dev Get the asset of a position according to its position type.
     * @param position to get the asset of
     */
    function _assetOf(uint32 position) internal view returns (ERC20) {
        address adaptor = getPositionData[position].adaptor;
        return BaseAdaptor(adaptor).assetOf(getPositionData[position].adaptorData);
    }

    /**
     * @notice Get all the credit positions underlying assets.
     */
    function getPositionAssets() external view returns (ERC20[] memory assets) {
        assets = new ERC20[](creditPositions.length);
        for (uint256 i = 0; i < creditPositions.length; ++i) {
            assets[i] = _assetOf(creditPositions[i]);
        }
    }

    function viewPositionBalances()
        external
        view
        returns (ERC20[] memory assets, uint256[] memory balances, bool[] memory isDebt)
    {
        uint256 creditLen = creditPositions.length;
        uint256 debtLen = debtPositions.length;
        assets = new ERC20[](creditLen + debtLen);
        balances = new uint256[](creditLen + debtLen);
        isDebt = new bool[](creditLen + debtLen);
        for (uint256 i = 0; i < creditLen; ++i) {
            assets[i] = _assetOf(creditPositions[i]);
            balances[i] = _balanceOf(creditPositions[i]);
            isDebt[i] = false;
        }

        for (uint256 i = 0; i < debtLen; ++i) {
            assets[i + creditPositions.length] = _assetOf(debtPositions[i]);
            balances[i + creditPositions.length] = _balanceOf(debtPositions[i]);
            isDebt[i + creditPositions.length] = true;
        }
    }
}
