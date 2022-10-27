// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Cellar, ERC20 } from "src/base/Cellar.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { console } from "@forge-std/Test.sol"; //TODO remove this

contract Registry is Ownable {
    // ============================================= ADDRESS CONFIG =============================================

    /**
     * @notice Emitted when the address of a contract is changed.
     * @param id value representing the unique ID tied to the changed contract
     * @param oldAddress address of the contract before the change
     * @param newAddress address of the contract after the contract
     */
    event AddressChanged(uint256 indexed id, address oldAddress, address newAddress);

    /**
     * @notice Attempted to set the address of a contract that is not registered.
     * @param id id of the contract that is not registered
     */
    error Registry__ContractNotRegistered(uint256 id);

    /**
     * @notice Emitted when depositor privilege changes.
     * @param depositor depositor address
     * @param state the new state of the depositor privilege
     */
    event DepositorOnBehalfChanged(address depositor, bool state);

    /**
     * @notice The unique ID that the next registered contract will have.
     */
    uint256 public nextId;

    /**
     * @notice Get the address associated with an id.
     */
    mapping(uint256 => address) public getAddress;

    /**
     * @notice In order for an address to make deposits on behalf of users they must be approved.
     */
    mapping(address => bool) public approvedForDepositOnBehalf;

    /**
     * @notice toggles a depositors  ability to deposit into cellars on behalf of users.
     */
    function setApprovedForDepositOnBehalf(address depositor, bool state) external onlyOwner {
        approvedForDepositOnBehalf[depositor] = state;
        emit DepositorOnBehalfChanged(depositor, state);
    }

    /**
     * @notice Set the address of the contract at a given id.
     */
    function setAddress(uint256 id, address newAddress) external onlyOwner {
        if (id >= nextId) revert Registry__ContractNotRegistered(id);

        emit AddressChanged(id, getAddress[id], newAddress);

        getAddress[id] = newAddress;
    }

    // ============================================= INITIALIZATION =============================================

    /**
     * @param gravityBridge address of GravityBridge contract
     * @param swapRouter address of SwapRouter contract
     * @param priceRouter address of PriceRouter contract
     */
    constructor(
        address gravityBridge,
        address swapRouter,
        address priceRouter
    ) Ownable() {
        _register(gravityBridge);
        _register(swapRouter);
        _register(priceRouter);
    }

    // ============================================ REGISTER CONFIG ============================================

    /**
     * @notice Emitted when a new contract is registered.
     * @param id value representing the unique ID tied to the new contract
     * @param newContract address of the new contract
     */
    event Registered(uint256 indexed id, address indexed newContract);

    /**
     * @notice Register the address of a new contract.
     * @param newContract address of the new contract to register
     */
    function register(address newContract) external onlyOwner {
        _register(newContract);
    }

    function _register(address newContract) internal {
        getAddress[nextId] = newContract;

        emit Registered(nextId, newContract);

        nextId++;
    }

    // ============================================ POSITION LOGIC ============================================

    /**
     * @notice stores data related to Cellar positions.
     * @param adaptors address of the adaptor to use for this position
     * @param isDebt bool indicating whether this position takes on debt or not
     * @param adaptorData arbitrary data needed to correclty set up a position
     * @param configurationData arbitrary data settable by strategist to change cellar <-> adaptor interaction
     */
    struct PositionData {
        address adaptor;
        bool isDebt;
        bytes adaptorData;
        bytes configurationData;
    }

    /**
     * @notice stores data to help cellars manage their risk.
     * @param assetRisk number 0 -> type(uint128).max indicating how risky a cellars assets can be
     *                  0: Safest
     *                  1: Riskiest
     * @param protocolRisk number 0 -> type(uint128).max indicating how risky a cellars position protocol can be
     *                     0: Safest
     *                     1: Riskiest
     */
    struct RiskData {
        uint128 assetRisk;
        uint128 protocolRisk;
    }

    /**
     * @notice Emitted when a new position is added to the registry.
     * @param id the positions id
     * @param adaptor address of the adaptor this position uses
     * @param isDebt bool indicating whether this position takes on debt or not
     * @param adaptorData arbitrary bytes used to configure this position
     */
    event PositionAdded(uint32 id, address adaptor, bool isDebt, bytes adaptorData);

    /**
     * @notice Attempted to trust a position not being used.
     * @param position address of the invalid position
     */
    error Registry__PositionPricingNotSetUp(address position);

    /**
     * @notice Attempted to add a position with bad input values.
     */
    error Registry__InvalidPositionInput();

    /**
     * @notice Attempted to add a position with a risky asset.
     */
    error Registry__AssetTooRisky();

    /**
     * @notice Attempted to add a position with a risky protocol.
     */
    error Registry__ProtocolTooRisky();

    /**
     * @notice Attempted to add a position that does not exist.
     */
    error Registry__PositionDoesNotExist();

    /**
     * @notice Addresses of the positions currently used by the cellar.
     */
    uint256 public constant PRICE_ROUTER_REGISTRY_SLOT = 2;

    /**
     * @notice Maps a position Id to its risk data.
     */
    mapping(uint32 => RiskData) public getRiskData;

    /**
     * @notice Maps an adaptor to its risk data.
     */
    mapping(address => RiskData) public getAdaptorRiskData;

    /**
     * @notice Stores the number of positions that have been added to the registry.
     *         Starts at 1.
     */
    uint32 public positionCount;

    /**
     * @notice Maps a position hash to a position Id.
     * @dev can be used by adaptors to verify that a certain position is open during Cellar `callOnAdaptor` calls.
     */
    mapping(bytes32 => uint32) public getPositionHashToPositionId;

    /**
     * @notice Maps a position id to its position data.
     * @dev used by Cellars when adding new positions.
     */
    mapping(uint32 => PositionData) public getPositionIdToPositionData;

    /**
     * @notice Trust a position to be used by the cellar.
     * @param adaptor the adaptor address this position uses
     * @param isDebt bool indicating whether this position should be treated as debt
     * @param adaptorData arbitrary bytes used to configure this position
     * @param assetRisk the risk rating of this positions asset
     * @param protocolRisk the risk rating of this positions underlying protocol
     * @return positionId the position id of the newly added position
     */
    function trustPosition(
        address adaptor,
        bool isDebt,
        bytes memory adaptorData,
        uint128 assetRisk,
        uint128 protocolRisk
    ) external onlyOwner returns (uint32 positionId) {
        bytes32 identifier = BaseAdaptor(adaptor).identifier();
        bytes32 positionHash = keccak256(abi.encode(identifier, isDebt, adaptorData));
        positionId = positionCount + 1; //Add one so that we do not use Id 0.

        // Check that...
        // `adaptor` is a non zero address
        // position has not been already set up
        if (adaptor == address(0) || getPositionHashToPositionId[positionHash] != 0)
            revert Registry__InvalidPositionInput();

        if (!isAdaptorTrusted[adaptor]) revert Registry__AdaptorNotTrusted();

        // Set position data.
        getPositionIdToPositionData[positionId] = PositionData({
            adaptor: adaptor,
            isDebt: isDebt,
            adaptorData: adaptorData,
            configurationData: abi.encode(0)
        });

        getRiskData[positionId] = RiskData({ assetRisk: assetRisk, protocolRisk: protocolRisk });

        getPositionHashToPositionId[positionHash] = positionId;

        // Check that asset of position is supported for pricing operations.
        ERC20 positionAsset = BaseAdaptor(adaptor).assetOf(adaptorData);
        if (!PriceRouter(getAddress[PRICE_ROUTER_REGISTRY_SLOT]).isSupported(positionAsset))
            revert Registry__PositionPricingNotSetUp(address(positionAsset));

        positionCount = positionId;

        emit PositionAdded(positionId, adaptor, isDebt, adaptorData);
    }

    /**
     * @notice Called by Cellars to add a new position to themselves.
     * @param positionId the id of the position the cellar wants to add
     * @param assetRiskTolerance the cellars risk tolerance for assets
     * @param protocolRiskTolerance the cellars risk tolerance for protocols
     * @return adaptor the address of the adaptor, isDebt bool indicating whether position is
     *         debt or not, and adaptorData needed to interact with position
     */
    function cellarAddPosition(
        uint32 positionId,
        uint128 assetRiskTolerance,
        uint128 protocolRiskTolerance
    )
        external
        view
        returns (
            address adaptor,
            bool isDebt,
            bytes memory adaptorData
        )
    {
        if (positionId > positionCount || positionId == 0) revert Registry__PositionDoesNotExist();
        RiskData memory data = getRiskData[positionId];
        if (assetRiskTolerance < data.assetRisk) revert Registry__AssetTooRisky();
        if (protocolRiskTolerance < data.protocolRisk) revert Registry__ProtocolTooRisky();
        PositionData memory positionData = getPositionIdToPositionData[positionId];
        return (positionData.adaptor, positionData.isDebt, positionData.adaptorData);
    }

    // ============================================ ADAPTOR LOGIC ============================================

    /**
     * @notice Attempted to trust an adaptor with non unique identifier.
     */
    error Registry__IdentifierNotUnique();

    /**
     * @notice Attempted to use an untrusted adaptor.
     */
    error Registry__AdaptorNotTrusted();

    /**
     * @notice Maps an adaptor address to bool indicating whether it has been set up in the registry.
     */
    mapping(address => bool) public isAdaptorTrusted;

    /**
     * @notice Maps an adaptors identier to bool, to track if the indentifier is unique wrt the registry.
     */
    mapping(bytes32 => bool) public isIdentifierUsed;

    /**
     * @notice Trust an adaptor to be used by cellars
     * @param adaptor address of the adaptor to trust
     * @param assetRisk the asset risk level associated with this adaptor
     * @param protocolRisk the protocol risk level associated with this adaptor
     */
    function trustAdaptor(
        address adaptor,
        uint128 assetRisk,
        uint128 protocolRisk
    ) external onlyOwner {
        bytes32 identifier = BaseAdaptor(adaptor).identifier();
        if (isIdentifierUsed[identifier]) revert Registry__IdentifierNotUnique();
        isAdaptorTrusted[adaptor] = true;
        isIdentifierUsed[identifier] = true;
        getAdaptorRiskData[adaptor] = RiskData({ assetRisk: assetRisk, protocolRisk: protocolRisk });
    }

    /**
     * @notice Called by Cellars to allow them to use new adaptors.
     * @param adaptor address of the adaptor to use
     * @param assetRiskTolerance asset risk tolerance of the caller
     * @param protocolRiskTolerance protocol risk tolerance of the cellar
     */
    function cellarSetupAdaptor(
        address adaptor,
        uint128 assetRiskTolerance,
        uint128 protocolRiskTolerance
    ) external view {
        RiskData memory data = getAdaptorRiskData[adaptor];
        if (assetRiskTolerance < data.assetRisk) revert Registry__AssetTooRisky();
        if (protocolRiskTolerance < data.protocolRisk) revert Registry__ProtocolTooRisky();
        if (!isAdaptorTrusted[adaptor]) revert Registry__AdaptorNotTrusted();
    }
}
