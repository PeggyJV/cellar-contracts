// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {BalancerPoolAdaptor} from "src/modules/adaptors/Balancer/BalancerPoolAdaptor.sol";
import { IBalancerRelayer } from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import {IVault} from "src/interfaces/external/Balancer/IVault.sol";
import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import {console} from "@forge-std/Test.sol";

/**
 * @title MockBalancerPoolAdaptor
 * @author crispymangoes & 0xEinCodes
 * @notice Mock Balancer Pool Adaptor used for slippage check tests in BalancerPoolAdaptor.t.sol
 */
contract MockBalancerPoolAdaptor is BalancerPoolAdaptor {
    /**
     * @notice Override the Balancer adaptors identifier so both adaptors can be added to the same registry.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Mock BPT Adaptor V 1.0"));
    }

    /**
     * @notice The Balancer Relayer contract on Ethereum Mainnet
     * @return relayer address adhering to `IBalancerRelayer`
     */
    function relayer() internal pure override returns (IBalancerRelayer) {
        return IBalancerRelayer(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496);
    }

    /**
     * @notice The Balancer Vault contract on Ethereum Mainnet
     * @return address adhering to `IVault`
     */
    function vault() internal pure override returns (IVault) {
        return IVault(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496);
    }

    /**
     * @notice external function to help adjust whether or not the relayer has been approved by cellar
     * @param _relayerChange proposed approval setting to relayer
     */
    function adjustRelayerApproval(bool _relayerChange) public override {
        // if relayer is already approved, continue
        // if it hasn't been approved, set it to approve.abi
        bool currentStatus = vault().hasApprovedRelayer(address(this), address(relayer()));
        if (currentStatus != _relayerChange) {
            vault().setRelayerApproval(address(this), address(relayer()), _relayerChange);
            // event RelayerApprovalChanged will be emitted by Balancer Vault
        }
    }

    // /**
    //  * NOTE: it would take multiple tokens and amounts in and a single bpt out
    //  */
    // function slippageSwap(ERC20 from, ERC20 to, uint256 inAmount, uint32 slippage) public override {
    //     // if (priceRouter.isSupported(from) && priceRouter.isSupported(to)) {
    //     //     // Figure out value in, quoted in `to`.
    //     //     uint256 fullValueOut = priceRouter.getValue(from, inAmount, to);
    //     //     uint256 valueOutWithSlippage = fullValueOut.mulDivDown(slippage, 1e4);
    //     //     // Deal caller new balances.
    //     //     deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
    //     //     deal(address(to), msg.sender, to.balanceOf(msg.sender) + valueOutWithSlippage);
    //     // } else {
    //     //     // Pricing is not supported, so just assume exchange rate is 1:1.
    //     //     deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
    //     //     deal(
    //     //         address(to),
    //     //         msg.sender,
    //     //         to.balanceOf(msg.sender) + inAmount.changeDecimals(from.decimals(), to.decimals())
    //     //     );
    //     // }

    //     console.log("howdy");
    // }
}
