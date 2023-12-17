// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Registry, ERC20, Math, SafeTransferLib } from "src/base/Cellar.sol";
import { IFlashLoanRecipient, IERC20 } from "@balancer/interfaces/contracts/vault/IFlashLoanRecipient.sol";
import { CellarWithOracleWithBalancerFlashLoans } from "src/base/permutations/CellarWithOracleWithBalancerFlashLoans.sol";
import { IWETH9 } from "src/interfaces/external/IWETH9.sol";

import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

contract CellarWithKitchenSink is CellarWithOracleWithBalancerFlashLoans {
    // /**
    //  * @notice The native token Wrapper contract on current chain.
    //  */
    // IWETH9 public immutable nativeWrapper;

    constructor(
        address _owner,
        Registry _registry,
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint32 _holdingPosition,
        bytes memory _holdingPositionConfig,
        uint256 _initialDeposit,
        uint192 _shareSupplyCap,
        address _balancerVault,
        address _nativeWrapper
    )
        CellarWithOracleWithBalancerFlashLoans(
            _owner,
            _registry,
            _asset,
            _name,
            _symbol,
            _holdingPosition,
            _holdingPositionConfig,
            _initialDeposit,
            0.8e18,
            _shareSupplyCap,
            _balancerVault
        )
    {
        // nativeWrapper = IWETH9(_nativeWrapper);
    }

    // TODO technically we do not need to auto wrap stuff, we could just have this empty then handle wrapping in the adaptor
    receive() external payable {
        // nativeWrapper.deposit{ value: msg.value }();
    }
}
