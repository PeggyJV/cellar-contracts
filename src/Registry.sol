// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Cellar, ERC20 } from "src/base/Cellar.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

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

    // ============================================ TRUST CONFIG ============================================

    //TODO add natspec
    struct PositionData {
        bool isDebt;
        address adaptor;
        bytes adaptorData;
    }

    /**
     * @notice Emitted when trust for a position is changed.
     * @param position address of position that trust was changed for
     * @param isTrusted whether the position is trusted
     */
    event TrustChanged(address indexed position, bool isTrusted);

    /**
     * @notice Attempted to trust a position not being used.
     * @param position address of the invalid position
     */
    error Cellar__PositionPricingNotSetUp(address position);

    /**
     * @notice Addresses of the positions currently used by the cellar.
     */
    uint256 public constant PRICE_ROUTER_REGISTRY_SLOT = 2;

    /**
     * @notice Tell whether a position is trusted.
     */
    mapping(address => bool) public isTrusted;

    /**
     * @notice Get the type related to a position.
     */
    mapping(address => PositionData) public getPositionData;

    /**
     * @notice Trust a position to be used by the cellar.
     * @param position address of position to trust
     */
    function trustPosition(
        address position,
        bool isDebt,
        address adaptor,
        bytes memory adaptorData
    ) external onlyOwner {
        // Trust position.
        isTrusted[position] = true;

        // Set position debt.
        getPositionData[position].isDebt = isDebt;
        require(isAdaptorTrusted[adaptor], "Invalid Adaptor");
        getPositionData[position].adaptor = adaptor;
        getPositionData[position].adaptorData = adaptorData;

        // Check that asset of position is supported for pricing operations.
        //TODO could also check that withdrawable and balanceOf?
        ERC20 positionAsset = BaseAdaptor(adaptor).assetOf(adaptorData);
        if (!PriceRouter(getAddress[PRICE_ROUTER_REGISTRY_SLOT]).isSupported(positionAsset))
            revert Cellar__PositionPricingNotSetUp(address(positionAsset));

        emit TrustChanged(position, true);
    }

    mapping(address => bool) public isAdaptorTrusted;

    function trustAdaptor(address adaptor) external onlyOwner {
        isAdaptorTrusted[adaptor] = true;
    }
}
