// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC20, SafeTransferLib, Address } from "src/base/Cellar.sol";
import { CREATE3 } from "@solmate/utils/CREATE3.sol";
import { Owned } from "@solmate/auth/Owned.sol";

contract Deployer is Owned {
    mapping(address => bool) public isDeployer;

    error Deployer__NotADeployer();

    /**
     * @notice Emitted on `deployContract` calls.
     * @param name string name used to derive salt for deployment
     * @param contractAddress the newly deployed contract address
     * @param creationCodeHash keccak256 hash of the creation code
     *        - useful to determine creation code is the same across multiple chains
     */
    event ContractDeployed(string name, address contractAddress, bytes32 creationCodeHash);

    constructor(address _owner, address[] memory _deployers) Owned(_owner) {
        for (uint256 i; i < _deployers.length; ++i) adjustDeployer(_deployers[i], true);
    }

    function adjustDeployer(address _deployer, bool _state) public onlyOwner {
        isDeployer[_deployer] = _state;
    }

    /**
     * @notice Deploy some contract to a deterministic address.
     * @param name string used to derive salt for deployment
     * @dev Should be of form:
     *      "ContractName Version 0.0"
     *      Where the numbers after version are VERSION . SUBVERSION
     * @param creationCode the contract creation code to deploy
     *        - can be obtained by calling type(contractName).creationCode
     * @param constructorArgs the contract constructor arguments if any
     *        - must be of form abi.encode(arg1, arg2, ...)
     * @param value non zero if constructor needs to be payable
     */
    function deployContract(
        string calldata name,
        bytes memory creationCode,
        bytes calldata constructorArgs,
        uint256 value
    ) external returns (address) {
        if (!isDeployer[msg.sender]) revert Deployer__NotADeployer();

        bytes32 creationCodeHash = keccak256(creationCode);

        if (constructorArgs.length > 0) {
            // Append constructor args to end of creation code.
            creationCode = abi.encodePacked(creationCode, constructorArgs);
        }

        bytes32 salt = convertNameToBytes32(name);

        address contractAddress = CREATE3.deploy(salt, creationCode, value);

        emit ContractDeployed(name, contractAddress, creationCodeHash);

        return contractAddress;
    }

    function getAddress(string calldata name) external view returns (address) {
        bytes32 salt = convertNameToBytes32(name);

        return CREATE3.getDeployed(salt);
    }

    function convertNameToBytes32(string calldata name) public pure returns (bytes32) {
        return keccak256(abi.encode(name));
    }
}
