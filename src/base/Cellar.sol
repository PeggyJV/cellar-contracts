// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Math} from "src/utils/Math.sol";
import {ERC4626} from "@solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
// import { ERC4626, SafeTransferLib, Math, ERC20 } from "src/base/ERC4626.sol";
import {Registry} from "src/Registry.sol";
import {PriceRouter} from "src/modules/price-router/PriceRouter.sol";
import {Uint32Array} from "src/utils/Uint32Array.sol";
import {BaseAdaptor} from "src/modules/adaptors/BaseAdaptor.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";

/**
 * @title Sommelier Cellar
 * @notice A composable ERC4626 that can use arbitrary DeFi assets/positions using adaptors.
 * @author crispymangoes
 */
contract Cellar is ERC4626, Auth, ERC721Holder {
    using Uint32Array for uint32[];
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    // ========================================= One Slot Values =========================================
    // Below values are frequently accessed in the same TXs. By moving them to the top
    // they will be stored in the same slot, reducing cold access reads.

    /**
     * @notice The maximum amount of shares that can be in circulation.
     * @dev Can be decreased by the strategist.
     * @dev Can be increased by Sommelier Governance.
     */
    uint192 public shareSupplyCap;

    /**
     * @notice `locked` is public, so that the state can be checked even during view function calls.
     */
    bool public locked;

    /**
     * @notice Whether or not the contract is shutdown in case of an emergency.
     */
    bool public isShutdown;

    /**
     * @notice Pauses all user entry/exits, and strategist rebalances.
     */
    bool public ignorePause;

    /**
     * @notice This bool is used to stop strategists from abusing Base Adaptor functions(deposit/withdraw).
     */
    bool public blockExternalReceiver;

    /**
     * @notice Stores the position id of the holding position in the creditPositions array.
     */
    uint32 public holdingPosition;

    // ========================================= MULTICALL =========================================

    /**
     * @notice Allows caller to call multiple functions in a single TX.
     * @dev Does NOT return the function return values.
     */
    function multicall(bytes[] calldata data) external {
        for (uint256 i = 0; i < data.length; i++) {
            address(this).functionDelegateCall(data[i]);
        }
    }

    // ========================================= REENTRANCY GUARD =========================================

    modifier nonReentrant() {
        require(!locked, "REENTRANCY");

        locked = true;

        _;

        locked = false;
    }

    // ========================================= _isAuthorized ========================================

    function _isAuthorized() internal requiresAuth {}

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
     * @param expectedPriceRouter The registry price router differed from the expected price router.
     * @dev `allowableRange` reverts from arithmetic underflow if it is greater than 10_000, this is
     *      desired behavior.
     * @dev Callable by Sommelier Governance.
     */
    function cachePriceRouter(bool checkTotalAssets, uint16 allowableRange, address expectedPriceRouter) external {
        _isAuthorized();
        uint256 minAssets;
        uint256 maxAssets;

        if (checkTotalAssets) {
            uint256 assetsBefore = totalAssets();
            minAssets = assetsBefore.mulDivDown(1e4 - allowableRange, 1e4);
            maxAssets = assetsBefore.mulDivDown(1e4 + allowableRange, 1e4);
        }

        // Make sure expected price router is equal to price router grabbed from registry.
        _checkRegistryAddressAgainstExpected(PRICE_ROUTER_REGISTRY_SLOT, expectedPriceRouter);

        priceRouter = PriceRouter(expectedPriceRouter);
        uint256 assetsAfter = totalAssets();

        if (checkTotalAssets) {
            if (assetsAfter < minAssets || assetsAfter > maxAssets) {
                revert Cellar__TotalAssetDeviatedOutsideRange(assetsAfter, minAssets, maxAssets);
            }
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
     * @notice Attempted to force out the wrong position.
     */
    error Cellar__FailedToForceOutPosition();

    /**
     * @notice Array of uint32s made up of cellars credit positions Ids.
     */
    uint32[] internal creditPositions;

    /**
     * @notice Array of uint32s made up of cellars debt positions Ids.
     */
    uint32[] internal debtPositions;

    /**
     * @notice Tell whether a position is currently used.
     */
    mapping(uint256 => bool) public isPositionUsed;

    /**
     * @notice Get position data given position id.
     */
    mapping(uint32 => Registry.PositionData) internal getPositionData;

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
    uint256 internal constant MAX_POSITIONS = 32;

    /**
     * @notice Allows owner to change the holding position.
     * @dev Callable by Sommelier Strategist.
     */
    function setHoldingPosition(uint32 positionId) public {
        _isAuthorized();
        if (!isPositionUsed[positionId]) revert Cellar__PositionNotUsed(positionId);
        if (_assetOf(positionId) != asset) revert Cellar__AssetMismatch(address(asset), address(_assetOf(positionId)));
        if (getPositionData[positionId].isDebt) revert Cellar__InvalidHoldingPosition(positionId);
        holdingPosition = positionId;
    }

    /**
     * @notice Positions the strategist is approved to use without any governance intervention.
     */
    mapping(uint32 => bool) internal positionCatalogue;

    /**
     * @notice Adaptors the strategist is approved to use without any governance intervention.
     */
    mapping(address => bool) internal adaptorCatalogue;

    /**
     * @notice Allows Governance to add positions to this cellar's catalogue.
     * @dev Callable by Sommelier Governance.
     */
    function addPositionToCatalogue(uint32 positionId) public {
        _isAuthorized();
        // Make sure position is not paused and is trusted.
        registry.revertIfPositionIsNotTrusted(positionId);
        positionCatalogue[positionId] = true;
        emit PositionCatalogueAltered(positionId, true);
    }

    /**
     * @notice Allows Governance to remove positions from this cellar's catalogue.
     * @dev Callable by Sommelier Strategist.
     */
    function removePositionFromCatalogue(uint32 positionId) external {
        _isAuthorized();
        positionCatalogue[positionId] = false;
        emit PositionCatalogueAltered(positionId, false);
    }

    /**
     * @notice Allows Governance to add adaptors to this cellar's catalogue.
     * @dev Callable by Sommelier Governance.
     */
    function addAdaptorToCatalogue(address adaptor) external {
        _isAuthorized();
        // Make sure adaptor is trusted.
        registry.revertIfAdaptorIsNotTrusted(adaptor);
        adaptorCatalogue[adaptor] = true;
        emit AdaptorCatalogueAltered(adaptor, true);
    }

    /**
     * @notice Allows Governance to remove adaptors from this cellar's catalogue.
     * @dev Callable by Sommelier Strategist.
     */
    function removeAdaptorFromCatalogue(address adaptor) external {
        _isAuthorized();
        adaptorCatalogue[adaptor] = false;
        emit AdaptorCatalogueAltered(adaptor, false);
    }

    /**
     * @notice Insert a trusted position to the list of positions used by the cellar at a given index.
     * @param index index at which to insert the position
     * @param positionId id of position to add
     * @param configurationData data used to configure how the position behaves
     * @dev Callable by Sommelier Strategist.
     */
    function addPosition(uint32 index, uint32 positionId, bytes memory configurationData, bool inDebtArray) public {
        _isAuthorized();
        _whenNotShutdown();

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
     * @dev Callable by Sommelier Strategist.
     */
    function removePosition(uint32 index, bool inDebtArray) external {
        _isAuthorized();
        // Get position being removed.
        uint32 positionId = inDebtArray ? debtPositions[index] : creditPositions[index];

        // Only remove position if it is empty, and if it is not the holding position.
        uint256 positionBalance = _balanceOf(positionId);
        if (positionBalance > 0) revert Cellar__PositionNotEmpty(positionId, positionBalance);

        _removePosition(index, positionId, inDebtArray);
    }

    /**
     * @notice Allows Sommelier Governance to forceably remove a position from the Cellar without checking its balance is zero.
     * @dev Callable by Sommelier Governance.
     */
    function forcePositionOut(uint32 index, uint32 positionId, bool inDebtArray) external {
        _isAuthorized();
        // Get position being removed.
        uint32 _positionId = inDebtArray ? debtPositions[index] : creditPositions[index];
        // Make sure position id right, and is distrusted.
        if (positionId != _positionId || registry.isPositionTrusted(positionId)) {
            revert Cellar__FailedToForceOutPosition();
        }

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
     * @dev Callable by Sommelier Strategist.
     */
    function swapPositions(uint32 index1, uint32 index2, bool inDebtArray) external {
        _isAuthorized();
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
     *                       This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
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
    FeeData public feeData = FeeData({
        strategistPlatformCut: 0.75e18,
        platformFee: 0.01e18,
        lastAccrual: 0,
        strategistPayoutAddress: address(0)
    });

    /**
     * @notice Sets the max possible performance fee for this cellar.
     */
    uint64 internal constant MAX_PLATFORM_FEE = 0.2e18;

    /**
     * @notice Sets the max possible fee cut for this cellar.
     */
    uint64 internal constant MAX_FEE_CUT = 1e18;

    /**
     * @notice Sets the Strategists cut of platform fees
     * @param cut the platform cut for the strategist
     * @dev Callable by Sommelier Governance.
     */
    function setStrategistPlatformCut(uint64 cut) external {
        _isAuthorized();
        if (cut > MAX_FEE_CUT) revert Cellar__InvalidFeeCut();
        emit StrategistPlatformCutChanged(feeData.strategistPlatformCut, cut);

        feeData.strategistPlatformCut = cut;
    }

    /**
     * @notice Sets the Strategists payout address
     * @param payout the new strategist payout address
     * @dev Callable by Sommelier Strategist.
     */
    function setStrategistPayoutAddress(address payout) external {
        _isAuthorized();
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
     * @dev Callable by Sommelier Governance.
     */
    function toggleIgnorePause() external {
        _isAuthorized();
        ignorePause = ignorePause ? false : true;
    }

    /**
     * @notice Prevent a function from being called during a shutdown.
     */
    function _whenNotShutdown() internal view {
        if (isShutdown) revert Cellar__ContractShutdown();
    }

    /**
     * @notice Shutdown the cellar. Used in an emergency or if the cellar has been deprecated.
     * @dev Callable by Sommelier Strategist.
     */
    function initiateShutdown() external {
        _isAuthorized();
        _whenNotShutdown();
        isShutdown = true;

        emit ShutdownChanged(true);
    }

    /**
     * @notice Restart the cellar.
     * @dev Callable by Sommelier Strategist.
     */
    function liftShutdown() external {
        _isAuthorized();
        if (!isShutdown) revert Cellar__ContractNotShutdown();
        isShutdown = false;

        emit ShutdownChanged(false);
    }

    // =========================================== CONSTRUCTOR ===========================================

    /**
     * @notice Id to get the gravity bridge from the registry.
     */
    uint256 internal constant GRAVITY_BRIDGE_REGISTRY_SLOT = 0;

    /**
     * @notice Id to get the price router from the registry.
     */
    uint256 internal constant PRICE_ROUTER_REGISTRY_SLOT = 2;

    /**
     * @notice The minimum amount of shares to be minted in the contructor.
     */
    uint256 internal constant MINIMUM_CONSTRUCTOR_MINT = 1e4;

    /**
     * @notice Attempted to deploy contract without minting enough shares.
     */
    error Cellar__MinimumConstructorMintNotMet();

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
     * @param _name name of this cellar's share token
     * @param _symbol symbol of this cellar's share token
     * @param _holdingPosition the holding position of the Cellar
     *        must use a position that does NOT call back to cellar on use(Like ERC20 positions).
     * @param _holdingPositionConfig configuration data for holding position
     * @param _initialDeposit initial amount of assets to deposit into the Cellar
     * @param _strategistPlatformCut platform cut to use
     * @param _shareSupplyCap starting share supply cap
     */
    constructor(
        address _owner,
        Registry _registry,
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint32 _holdingPosition,
        bytes memory _holdingPositionConfig,
        uint256 _initialDeposit,
        uint64 _strategistPlatformCut,
        uint192 _shareSupplyCap
    ) ERC4626(_asset, _name, _symbol) Auth(msg.sender, Authority(address(0))) {
        registry = _registry;
        priceRouter = PriceRouter(_registry.getAddress(PRICE_ROUTER_REGISTRY_SLOT));

        // Initialize holding position.
        addPositionToCatalogue(_holdingPosition);
        addPosition(0, _holdingPosition, _holdingPositionConfig, false);
        setHoldingPosition(_holdingPosition);

        // Update Share Supply Cap.
        shareSupplyCap = _shareSupplyCap;

        if (_initialDeposit < MINIMUM_CONSTRUCTOR_MINT) revert Cellar__MinimumConstructorMintNotMet();

        // Deposit into Cellar, and mint shares to Deployer address.
        _asset.safeTransferFrom(_owner, address(this), _initialDeposit);
        // Set the share price as 1:1 with underlying asset.
        _mint(msg.sender, _initialDeposit);
        // Deposit _initialDeposit into holding position.
        _depositTo(_holdingPosition, _initialDeposit);

        feeData.strategistPlatformCut = _strategistPlatformCut;
        transferOwnership(_owner);
    }

    // =========================================== CORE LOGIC ===========================================

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
     * @notice called at the beginning of deposit.
     */
    function beforeDeposit(ERC20, uint256, uint256, address) internal view virtual {
        _whenNotShutdown();
        _checkIfPaused();
    }

    /**
     * @notice called at the end of deposit.
     * @param position the position to deposit to.
     * @param assets amount of assets deposited by user.
     */
    function afterDeposit(uint32 position, uint256 assets, uint256, address) internal virtual {
        _depositTo(position, assets);
    }

    /**
     * @notice called at the beginning of withdraw.
     */
    function beforeWithdraw(uint256, uint256, address, address) internal view virtual {
        _checkIfPaused();
    }

    /**
     * @notice Called when users enter the cellar via deposit or mint.
     */
    function _enter(ERC20 depositAsset, uint32 position, uint256 assets, uint256 shares, address receiver)
        internal
        virtual
    {
        beforeDeposit(asset, assets, shares, receiver);

        // Need to transfer before minting or ERC777s could reenter.
        depositAsset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(position, assets, shares, receiver);
    }

    /**
     * @notice Deposits assets into the cellar, and returns shares to receiver.
     * @param assets amount of assets deposited by user.
     * @param receiver address to receive the shares.
     * @return shares amount of shares given for deposit.
     */
    function deposit(uint256 assets, address receiver) public virtual override nonReentrant returns (uint256 shares) {
        // Use `_calculateTotalAssetsOrTotalAssetsWithdrawable` instead of totalAssets bc re-entrancy is already checked in this function.
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(true);

        // Check for rounding error since we round down in previewDeposit.
        if ((shares = _convertToShares(assets, _totalAssets, _totalSupply)) == 0) revert Cellar__ZeroShares();

        if ((_totalSupply + shares) > shareSupplyCap) revert Cellar__ShareSupplyCapExceeded();

        _enter(asset, holdingPosition, assets, shares, receiver);
    }

    /**
     * @notice Mints shares from the cellar, and returns shares to receiver.
     * @param shares amount of shares requested by user.
     * @param receiver address to receive the shares.
     * @return assets amount of assets deposited into the cellar.
     */
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(true);

        // previewMint rounds up, but initial mint could return zero assets, so check for rounding error.
        if ((assets = _previewMint(shares, _totalAssets, _totalSupply)) == 0) revert Cellar__ZeroAssets();

        if ((_totalSupply + shares) > shareSupplyCap) revert Cellar__ShareSupplyCapExceeded();

        _enter(asset, holdingPosition, assets, shares, receiver);
    }

    /**
     * @notice Called when users exit the cellar via withdraw or redeem.
     */
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
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(false);

        // No need to check for rounding error, `previewWithdraw` rounds up.
        shares = _previewWithdraw(assets, _totalAssets, _totalSupply);

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
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(false);

        // Check for rounding error since we round down in previewRedeem.
        if ((assets = _convertToAssets(shares, _totalAssets, _totalSupply)) == 0) revert Cellar__ZeroAssets();

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
        pricingInfo.oneQuote = 10 ** decimals;
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
                    pricingInfo.priceBaseUSD, pricingInfo.oneBase
                );
                totalWithdrawableBalanceInAssets =
                    withdrawableBalanceInUSD.mulDivDown(pricingInfo.oneQuote, pricingInfo.priceQuoteUSD);
                totalWithdrawableBalanceInAssets = totalWithdrawableBalanceInAssets / PRECISION_MULTIPLIER;
            }

            // We want to pull as much as we can from this position, but no more than needed.
            uint256 amount;

            if (totalWithdrawableBalanceInAssets > assets) {
                // Convert assets into position asset.
                uint256 assetsInUSD =
                    (PRECISION_MULTIPLIER * assets).mulDivDown(pricingInfo.priceQuoteUSD, pricingInfo.oneQuote);
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

    /**
     * @notice Get the Cellars Total Assets, and Total Supply.
     * @dev bool input is not used, but if it were used the following is true.
     *      true: return the largest possible total assets
     *      false: return the smallest possible total assets
     */
    function _getTotalAssetsAndTotalSupply(bool)
        internal
        view
        virtual
        returns (uint256 _totalAssets, uint256 _totalSupply)
    {
        _totalAssets = _calculateTotalAssetsOrTotalAssetsWithdrawable(false);
        _totalSupply = totalSupply;
    }

    /**
     * @notice Internal accounting function that can report total assets, or total assets withdrawable.
     * @param reportWithdrawable if true, then the withdrawable total assets is reported,
     *                           if false, then the total assets is reported
     */
    function _calculateTotalAssetsOrTotalAssetsWithdrawable(bool reportWithdrawable)
        internal
        view
        returns (uint256 assets)
    {
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
        require(!locked, "REENTRANCY");
        assets = _calculateTotalAssetsOrTotalAssetsWithdrawable(false);
    }

    /**
     * @notice The total amount of withdrawable assets in the cellar.
     * @dev Run a re-entrancy check because totalAssetsWithdrawable can be wrong if re-entering from deposit/withdraws.
     */
    function totalAssetsWithdrawable() public view returns (uint256 assets) {
        _checkIfPaused();
        require(!locked, "REENTRANCY");
        assets = _calculateTotalAssetsOrTotalAssetsWithdrawable(true);
    }

    /**
     * @notice The amount of assets that the cellar would exchange for the amount of shares provided.
     * @dev Use preview functions to get accurate assets.
     * @dev Under estimates assets.
     * @param shares amount of shares to convert
     * @return assets the shares can be exchanged for
     */
    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(false);
        assets = _convertToAssets(shares, _totalAssets, _totalSupply);
    }

    /**
     * @notice The amount of shares that the cellar would exchange for the amount of assets provided.
     * @dev Use preview functions to get accurate shares.
     * @dev Under estimates shares.
     * @param assets amount of assets to convert
     * @return shares the assets can be exchanged for
     */
    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(true);
        shares = _convertToShares(assets, _totalAssets, _totalSupply);
    }

    /**
     * @notice Simulate the effects of minting shares at the current block, given current on-chain conditions.
     * @param shares amount of shares to mint
     * @return assets that will be deposited
     */
    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(true);
        assets = _previewMint(shares, _totalAssets, _totalSupply);
    }

    /**
     * @notice Simulate the effects of withdrawing assets at the current block, given current on-chain conditions.
     * @param assets amount of assets to withdraw
     * @return shares that will be redeemed
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(false);
        shares = _previewWithdraw(assets, _totalAssets, _totalSupply);
    }

    /**
     * @notice Simulate the effects of depositing assets at the current block, given current on-chain conditions.
     * @param assets amount of assets to deposit
     * @return shares that will be minted
     */
    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(true);
        shares = _convertToShares(assets, _totalAssets, _totalSupply);
    }

    /**
     * @notice Simulate the effects of redeeming shares at the current block, given current on-chain conditions.
     * @param shares amount of shares to redeem
     * @return assets that will be returned
     */
    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(false);
        assets = _convertToAssets(shares, _totalAssets, _totalSupply);
    }

    /**
     * @notice Finds the max amount of value an `owner` can remove from the cellar.
     * @param owner address of the user to find max value.
     * @param inShares if false, then returns value in terms of assets
     *                 if true then returns value in terms of shares
     */
    function _findMax(address owner, bool inShares) internal view virtual returns (uint256 maxOut) {
        _checkIfPaused();
        // Get amount of assets to withdraw.
        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(false);
        uint256 assets = _convertToAssets(balanceOf[owner], _totalAssets, _totalSupply);

        uint256 withdrawable = _calculateTotalAssetsOrTotalAssetsWithdrawable(true);
        maxOut = assets <= withdrawable ? assets : withdrawable;

        if (inShares) maxOut = _convertToShares(maxOut, _totalAssets, _totalSupply);
        // else leave maxOut in terms of assets.
    }

    /**
     * @notice Returns the max amount withdrawable by a user inclusive of performance fees
     * @dev EIP4626 states maxWithdraw must not revert, but it is possible for `totalAssets` to revert
     * so it does NOT conform to ERC4626 standards.
     * @param owner address to check maxWithdraw of.
     * @return the max amount of assets withdrawable by `owner`.
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        require(!locked, "REENTRANCY");
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
        require(!locked, "REENTRANCY");
        return _findMax(owner, true);
    }

    /**
     * @dev Used to more efficiently convert amount of shares to assets using a stored `totalAssets` value.
     */
    function _convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _totalSupply)
        internal
        pure
        returns (uint256 assets)
    {
        assets = shares.mulDivDown(_totalAssets, _totalSupply);
    }

    /**
     * @dev Used to more efficiently convert amount of assets to shares using a stored `totalAssets` value.
     */
    function _convertToShares(uint256 assets, uint256 _totalAssets, uint256 _totalSupply)
        internal
        pure
        returns (uint256 shares)
    {
        shares = assets.mulDivDown(_totalSupply, _totalAssets);
    }

    /**
     * @dev Used to more efficiently simulate minting shares using a stored `totalAssets` value.
     */
    function _previewMint(uint256 shares, uint256 _totalAssets, uint256 _totalSupply)
        internal
        pure
        returns (uint256 assets)
    {
        assets = shares.mulDivUp(_totalAssets, _totalSupply);
    }

    /**
     * @dev Used to more efficiently simulate withdrawing assets using a stored `totalAssets` value.
     */
    function _previewWithdraw(uint256 assets, uint256 _totalAssets, uint256 _totalSupply)
        internal
        pure
        returns (uint256 shares)
    {
        shares = assets.mulDivUp(_totalSupply, _totalAssets);
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
    uint64 internal constant MAX_REBALANCE_DEVIATION = 0.1e18;

    /**
     * @notice The percent the total assets of a cellar may deviate during a `callOnAdaptor`(rebalance) call.
     */
    uint256 internal allowedRebalanceDeviation = 0.0003e18;

    /**
     * @notice Allows governance to change this cellars rebalance deviation.
     * @param newDeviation the new rebalance deviation value.
     * @dev Callable by Sommelier Governance.
     */
    function setRebalanceDeviation(uint256 newDeviation) external {
        _isAuthorized();
        if (newDeviation > MAX_REBALANCE_DEVIATION) {
            revert Cellar__InvalidRebalanceDeviation(newDeviation, MAX_REBALANCE_DEVIATION);
        }

        uint256 oldDeviation = allowedRebalanceDeviation;
        allowedRebalanceDeviation = newDeviation;

        emit RebalanceDeviationChanged(oldDeviation, newDeviation);
    }

    /**
     * @notice Struct used to make calls to adaptors.
     * @param adaptor the address of the adaptor to make calls to
     * @param the abi encoded function calls to make to the `adaptor`
     */
    struct AdaptorCall {
        address adaptor;
        bytes[] callData;
    }

    /**
     * @notice Emitted when adaptor calls are made.
     */
    event AdaptorCalled(address adaptor, bytes data);

    /**
     * @notice Internal helper function that accepts an Adaptor Call array, and makes calls to each adaptor.
     */
    function _makeAdaptorCalls(AdaptorCall[] memory data) internal {
        for (uint256 i = 0; i < data.length; ++i) {
            address adaptor = data[i].adaptor;
            // Revert if adaptor not in catalogue, or adaptor is paused.
            if (!adaptorCatalogue[adaptor]) revert Cellar__CallToAdaptorNotAllowed(adaptor);
            for (uint256 j = 0; j < data[i].callData.length; j++) {
                adaptor.functionDelegateCall(data[i].callData[j]);
                emit AdaptorCalled(adaptor, data[i].callData[j]);
            }
        }
    }

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
     * @dev Callable by Sommelier Strategist, and Automation Actions contract.
     */
    function callOnAdaptor(AdaptorCall[] calldata data) external virtual nonReentrant {
        _isAuthorized();
        _whenNotShutdown();
        _checkIfPaused();
        blockExternalReceiver = true;

        // Record `totalAssets` and `totalShares` before making any external calls.
        uint256 minimumAllowedAssets;
        uint256 maximumAllowedAssets;
        uint256 totalShares;
        {
            uint256 assetsBeforeAdaptorCall = _calculateTotalAssetsOrTotalAssetsWithdrawable(false);
            minimumAllowedAssets = assetsBeforeAdaptorCall.mulDivUp((1e18 - allowedRebalanceDeviation), 1e18);
            maximumAllowedAssets = assetsBeforeAdaptorCall.mulDivUp((1e18 + allowedRebalanceDeviation), 1e18);
            totalShares = totalSupply;
        }

        // Run all adaptor calls.
        _makeAdaptorCalls(data);

        // After making every external call, check that the totalAssets has not deviated significantly, and that totalShares is the same.
        uint256 assets = _calculateTotalAssetsOrTotalAssetsWithdrawable(false);
        if (assets < minimumAllowedAssets || assets > maximumAllowedAssets) {
            revert Cellar__TotalAssetDeviatedOutsideRange(assets, minimumAllowedAssets, maximumAllowedAssets);
        }
        if (totalShares != totalSupply) revert Cellar__TotalSharesMustRemainConstant(totalSupply, totalShares);

        blockExternalReceiver = false;
    }

    // ============================================ LIMITS LOGIC ============================================

    /**
     * @notice Attempted entry would raise totalSupply above Share Supply Cap.
     */
    error Cellar__ShareSupplyCapExceeded();

    /**
     * @notice Proposed share supply cap is not logical.
     */
    error Cellar__InvalidShareSupplyCap();

    /**
     * @notice Increases the share supply cap.
     * @dev Callable by Sommelier Governance.
     */
    function increaseShareSupplyCap(uint192 _newShareSupplyCap) public {
        _isAuthorized();
        if (_newShareSupplyCap < shareSupplyCap) revert Cellar__InvalidShareSupplyCap();

        shareSupplyCap = _newShareSupplyCap;
    }

    /**
     * @notice Decreases the share supply cap.
     * @dev Callable by Sommelier Strategist.
     */
    function decreaseShareSupplyCap(uint192 _newShareSupplyCap) public {
        _isAuthorized();
        if (_newShareSupplyCap > shareSupplyCap) revert Cellar__InvalidShareSupplyCap();

        shareSupplyCap = _newShareSupplyCap;
    }

    /**
     * @notice Total amount of assets that can be deposited for a user.
     * @return assets maximum amount of assets that can be deposited
     */
    function maxDeposit(address) public view override returns (uint256) {
        if (isShutdown) return 0;

        uint192 _cap = shareSupplyCap;
        if ((_cap = shareSupplyCap) == type(uint192).max) return type(uint256).max;

        (uint256 _totalAssets, uint256 _totalSupply) = _getTotalAssetsAndTotalSupply(true);
        if (_totalSupply >= _cap) {
            return 0;
        } else {
            uint256 shareDelta = _cap - _totalSupply;
            return _convertToAssets(shareDelta, _totalAssets, _totalSupply);
        }
    }

    /**
     * @notice Total amount of shares that can be minted for a user.
     * @return shares maximum amount of shares that can be minted
     */
    function maxMint(address) public view override returns (uint256) {
        if (isShutdown) return 0;

        uint192 _cap;
        if ((_cap = shareSupplyCap) == type(uint192).max) return type(uint256).max;

        uint256 _totalSupply = totalSupply;

        return _totalSupply >= _cap ? 0 : _cap - _totalSupply;
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
        return BaseAdaptor(getPositionData[position].adaptor).withdrawableFrom(
            getPositionData[position].adaptorData, getPositionData[position].configurationData
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
     * @notice Attempted to use an address from the registry, but address was not expected.
     */
    error Cellar__ExpectedAddressDoesNotMatchActual();

    /**
     * @notice Attempted to set an address to registry Id 0.
     */
    error Cellar__SettingValueToRegistryIdZeroIsProhibited();

    /**
     * @notice Verify that `_registryId` in registry corresponds to expected address.
     */
    function _checkRegistryAddressAgainstExpected(uint256 _registryId, address _expected) internal view {
        if (_registryId == 0) revert Cellar__SettingValueToRegistryIdZeroIsProhibited();
        if (registry.getAddress(_registryId) != _expected) revert Cellar__ExpectedAddressDoesNotMatchActual();
    }
}
