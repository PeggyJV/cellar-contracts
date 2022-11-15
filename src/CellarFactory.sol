// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, Owned, ERC20, SafeTransferLib, Address } from "src/base/Cellar.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

contract CellarFactory is Owned {
    using SafeTransferLib for ERC20;
    using Clones for address;
    using Address for address;

    mapping(address => bool) public isDeployer;

    function adjustIsDeployer(address _deployer, bool _state) external onlyOwner {
        isDeployer[_deployer] = _state;
    }

    constructor() Owned(msg.sender) {}

    event CellarDeployed(address cellar, address implementation, bytes32 salt);

    error CellarFactory__NotADeployer();

    function deploy(
        address implementation,
        bytes calldata initializeCallData,
        ERC20 asset,
        uint256 initialDeposit,
        bytes32 salt
    ) external returns (address clone) {
        if (!isDeployer[msg.sender]) revert CellarFactory__NotADeployer();
        clone = implementation.cloneDeterministic(salt);
        clone.functionCall(initializeCallData);
        // Deposit into cellar if need be.
        if (initialDeposit > 0) {
            asset.safeTransferFrom(msg.sender, address(this), initialDeposit);
            asset.safeApprove(clone, initialDeposit);
            Cellar(clone).deposit(initialDeposit, address(this));
            //TODO I guess we could transfer the shares out? Or do we wanna "lock" them in here to always have liquidity in the cellars?
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
