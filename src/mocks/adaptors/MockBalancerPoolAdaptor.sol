// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BalancerPoolAdaptor } from "src/modules/adaptors/Balancer/BalancerPoolAdaptor.sol";
import { IVault } from "src/interfaces/external/Balancer/IVault.sol";
import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { console } from "@forge-std/Test.sol";
import { IBalancerMinter } from "src/interfaces/external/IBalancerMinter.sol";

/**
 * @title MockBalancerPoolAdaptor
 * @author crispymangoes & 0xEinCodes
 * @notice Mock Balancer Pool Adaptor used for slippage check tests in BalancerPoolAdaptor.t.sol
 * Mocks should inherit BalancerPoolAdaptor, and then the constructor with it and all the imports. All the mock is doing is overriding the identifier and putting the test contract as the vault and relayer address.
 */
contract MockBalancerPoolAdaptor is BalancerPoolAdaptor {
    /**
     * @notice Override the Balancer adaptors identifier so both adaptors can be added to the same registry.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Mock BPT Adaptor V 1.0"));
    }

    constructor(
        address _vault,
        address _minter,
        uint32 _balancerSlippage
    ) BalancerPoolAdaptor(_vault, _minter, _balancerSlippage) {}
}
