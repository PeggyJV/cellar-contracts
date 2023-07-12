// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Owned, ERC20, SafeTransferLib, Address } from "src/base/Cellar.sol";
import { CellarInitializable } from "src/base/CellarInitializable.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

contract CellarFactory is Owned {
    using SafeTransferLib for ERC20;
    using Clones for address;
    using Address for address;

    /**
     * @notice Get a Cellar implementation by passing x, and y into getImplementation[x][y]
     *         Where:
     *              x - The major version number
     *              y - The minor version number
     *         Example:
     *                Version 1.5 => x = 1, and y = 5
     */
    mapping(uint256 => mapping(uint256 => address)) public getImplementation;

    /**
     * @notice Attempted to overwrite an existing implementation.
     */
    error CellarFactory__AlreadyExists();

    function addImplementation(
        address implementation,
        uint256 version,
        uint256 subVersion
    ) external onlyOwner {
        if (getImplementation[version][subVersion] != address(0)) revert CellarFactory__AlreadyExists();
        getImplementation[version][subVersion] = implementation;
    }

    /**
     * @notice Keep track of what addresses can create Cellars using this factory.
     */
    mapping(address => bool) public isDeployer;

    /**
     * @notice Allows owner to add/remove addresses from `isDeployer`.
     */
    function adjustIsDeployer(address _deployer, bool _state) external onlyOwner {
        isDeployer[_deployer] = _state;
    }

    /**
     * @notice Call Owned constructor to properly set up ownership.
     */
    constructor() Owned(msg.sender) {}

    /**
     * @notice Emitted when a Cellar is deployed.
     * @param cellar the address of the deployed cellar
     * @param implementation the address of the implementation used
     * @param salt the salt used to deterministically deploy the cellar
     */
    event CellarDeployed(address cellar, address implementation, bytes32 salt);

    /**
     * @notice Attempted to deploy a cellar from an account that is not a deployer.
     */
    error CellarFactory__NotADeployer();

    /**
     * @notice Deterministically deploys cellars using OpenZepplin Clones.
     * @param version the major version of the implementation to use.
     * @param subVersion the minor version of the implementation to use.
     * @param asset the ERC20 asset of the new cellar
     * @param initialDeposit if non zero, then this function will make the initial deposit into the cellar
     * @param salt salt used to deterministically deploy the cellar
     * @return clone the address of the cellar clone
     * @dev Initial Deposit shares are intentionally locked in the factory.
     *      This way there is always some liquidity and outstanding shares.
     */
    function deploy(
        uint256 version,
        uint256 subVersion,
        bytes calldata initializeData,
        ERC20 asset,
        uint256 initialDeposit,
        bytes32 salt
    ) external returns (address clone) {
        if (!isDeployer[msg.sender]) revert CellarFactory__NotADeployer();
        address implementation = getImplementation[version][subVersion];
        clone = implementation.cloneDeterministic(salt);
        CellarInitializable cellar = CellarInitializable(clone);
        cellar.initialize(initializeData);
        // Deposit into cellar if need be.
        if (initialDeposit > 0) {
            asset.safeTransferFrom(msg.sender, address(this), initialDeposit);
            asset.safeApprove(clone, initialDeposit);
            cellar.deposit(initialDeposit, address(this));
        }
        emit CellarDeployed(clone, implementation, salt);
    }

    /**
     * @notice Deployer address is this factory address.
     */
    function getCellar(address implementation, bytes32 salt) external view returns (address) {
        return implementation.predictDeterministicAddress(salt);
    }
}
