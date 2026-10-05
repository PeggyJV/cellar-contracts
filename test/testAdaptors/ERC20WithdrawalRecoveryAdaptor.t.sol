// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Test} from "@forge-std/Test.sol";
import {ERC20Adaptor} from "src/modules/adaptors/ERC20Adaptor.sol";
import {ERC20WithdrawalRecoveryAdaptor} from "src/modules/adaptors/ERC20WithdrawalRecoveryAdaptor.sol";

contract ERC20WithdrawalRecoveryAdaptorTest is Test {
    ERC20WithdrawalRecoveryAdaptor private adaptor;

    function setUp() external {
        adaptor = new ERC20WithdrawalRecoveryAdaptor();
    }

    function testIdentifierIsIsolatedFromTheStandardERC20Adaptor() external {
        ERC20Adaptor standardAdaptor = new ERC20Adaptor();

        assertEq(standardAdaptor.identifier(), keccak256(abi.encode("ERC20 Adaptor V 1.0")));
        assertEq(adaptor.identifier(), keccak256(abi.encode("ERC20 Adaptor Withdrawal Recovery Candidate V 1.0")));
    }

    function testRecoveryPositionIsCollateral() external {
        assertFalse(adaptor.isDebt());
    }

    function testRuntimeMatchesDeployedSemanticBytecode() external {
        bytes memory runtimeCode = type(ERC20WithdrawalRecoveryAdaptor).runtimeCode;
        uint256 metadataLength = (uint256(uint8(runtimeCode[runtimeCode.length - 2])) << 8)
            | uint256(uint8(runtimeCode[runtimeCode.length - 1]));
        uint256 semanticLength = runtimeCode.length - metadataLength - 2;
        bytes32 semanticHash;

        assembly {
            semanticHash := keccak256(add(runtimeCode, 0x20), semanticLength)
        }

        assertEq(semanticHash, 0x5509c54323791d5da52562bf42d23f36858c1bd57454abe30ad056f5fc3ff0cb);
    }
}
