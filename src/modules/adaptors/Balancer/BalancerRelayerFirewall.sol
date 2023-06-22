// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, SwapRouter, Registry, PriceRouter } from "src/modules/adaptors/BaseAdaptor.sol";
import { IBalancerQueries } from "src/interfaces/external/Balancer/IBalancerQueries.sol";
import { IVault } from "src/interfaces/external/Balancer/IVault.sol";
import { IBalancerRelayer } from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import { IStakingLiquidityGauge } from "src/interfaces/external/Balancer/IStakingLiquidityGauge.sol";
import { IBalancerRelayer } from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import { ILiquidityGaugev3Custom } from "src/interfaces/external/Balancer/ILiquidityGaugev3Custom.sol";
import { IBasePool } from "src/interfaces/external/Balancer/typically-npm/IBasePool.sol";
import { ILiquidityGauge } from "src/interfaces/external/Balancer/ILiquidityGauge.sol";
import { Math } from "src/utils/Math.sol";
import { console } from "@forge-std/Test.sol";
import { IBalancerMinter } from "src/interfaces/external/IBalancerMinter.sol";

/**
 * @dev For both `joinPool` and `exitPool`, strategist must configure their multicall data such that:
 *      from: firewall address
 *      recipient: cellar address
 */
contract BalancerRelayerFirewall {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    /**
     * @notice The Balancer Vault contract
     * @notice For mainnet use 0xBA12222222228d8Ba445958a75a0704d566BF2C8
     */
    IVault public immutable vault;

    /**
     * @notice The Balancer Relayer contract adhering to `IBalancerRelayer
     * @notice For mainnet use 0xfeA793Aa415061C483D2390414275AD314B3F621
     */
    IBalancerRelayer public immutable relayer;

    constructor(address _vault, address _relayer) {
        vault = IVault(_vault);
        relayer = IBalancerRelayer(_relayer);
    }

    function joinPool(
        ERC20[] memory tokensIn,
        uint256[] memory amountsIn,
        ERC20 bptOut,
        bytes[] memory callData
    ) public {
        for (uint256 i; i < tokensIn.length; ++i) {
            tokensIn[i].safeTransferFrom(msg.sender, address(this), amountsIn[i]);
            tokensIn[i].approve(address(vault), amountsIn[i]);
        }
        relayer.multicall(callData);

        // revoke token in approval
        for (uint256 i; i < tokensIn.length; ++i) {
            _revokeExternalApproval(tokensIn[i], address(vault));
        }
    }

    function exitPool(ERC20 bptIn, uint256 amountIn, ERC20[] memory tokensOut, bytes[] memory callData) public {
        bptIn.safeTransferFrom(msg.sender, address(this), amountIn);
        relayer.multicall(callData);
    }

    /**
     * @notice Helper function that checks if `spender` has any more approval for `asset`, and if so revokes it.
     */
    function _revokeExternalApproval(ERC20 asset, address spender) internal {
        if (asset.allowance(address(this), spender) > 0) asset.safeApprove(spender, 0);
    }
}
