// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IWETH9 } from "src/interfaces/external/IWETH9.sol";
import { CurvePool } from "src/interfaces/external/Curve/CurvePool.sol";
import { CurveGauge } from "src/interfaces/external/Curve/CurveGauge.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CellarWithOracle } from "src/base/permutations/CellarWithOracle.sol";

import { console } from "@forge-std/Test.sol";

// TODO remove
/**
 * @title ERC20 Adaptor
 * @notice Allows Cellars to interact with Curve LP positions.
 * @author crispymangoes
 */
contract CurveHelper {
    using SafeTransferLib for ERC20;
    using Address for address;
    using Strings for uint256;
    using Math for uint256;
    address public constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public immutable nativeWrapper;

    constructor(address _nativeWrapper) {
        nativeWrapper = _nativeWrapper;
    }

    //========================================= Native Helper Functions =======================================
    // Cellars do not natively use ETH, so to support interacting with native ETH curve pools, this adaptor will serve as a proxy to wrap and unwrap ETH.
    receive() external payable {}

    function addLiquidityETHViaProxy(
        address pool,
        ERC20 token,
        ERC20[] memory tokens,
        uint256[] memory orderedTokenAmounts,
        uint256 minLPAmount,
        bool useUnderlying
    ) external returns (uint256 lpOut) {
        // if (Cellar(msg.sender).blockExternalReceiver()) revert("Not callable by strategist");
        // TODO above check is probs not needed as long as I confirm that if a cellar calls this function direclty it reverts when it tries to unwrap the ETH

        uint256 nativeEthAmount;

        // Transfer assets to the adaptor.
        for (uint256 i; i < tokens.length; ++i) {
            if (address(tokens[i]) == CURVE_ETH) {
                // If token is CURVE_ETH, then approve adaptor to spend native wrapper.
                ERC20(nativeWrapper).safeTransferFrom(msg.sender, address(this), orderedTokenAmounts[i]);
                // Unwrap native.
                IWETH9(nativeWrapper).withdraw(orderedTokenAmounts[i]);

                nativeEthAmount = orderedTokenAmounts[i];
            } else {
                tokens[i].safeTransferFrom(msg.sender, address(this), orderedTokenAmounts[i]);
                // Approve pool to spend ERC20 assets.
                tokens[i].safeApprove(pool, orderedTokenAmounts[i]);
            }
        }

        bytes memory data = _curveAddLiquidityEncodedCallData(orderedTokenAmounts, minLPAmount, useUnderlying);

        pool.functionCallWithValue(data, nativeEthAmount);

        // Send LP tokens back to caller.
        ERC20 lpToken = ERC20(token);
        lpOut = lpToken.balanceOf(address(this));
        lpToken.safeTransfer(msg.sender, lpOut);

        for (uint256 i; i < tokens.length; ++i) {
            if (address(tokens[i]) != CURVE_ETH) _zeroExternalApproval(tokens[i], address(this));
        }
    }

    function removeLiquidityETHViaProxy(
        address pool,
        ERC20 token,
        uint256 lpTokenAmount,
        ERC20[] memory tokens,
        uint256[] memory orderedTokenAmountsOut,
        bool useUnderlying
    ) external returns (uint256[] memory tokensOut) {
        // if (Cellar(msg.sender).blockExternalReceiver()) revert("Not callable by strategist");

        if (tokens.length != orderedTokenAmountsOut.length) revert("Bad data");
        bytes memory data = _curveRemoveLiquidityEncodedCalldata(lpTokenAmount, orderedTokenAmountsOut, useUnderlying);

        // Transfer token in.
        token.safeTransferFrom(msg.sender, address(this), lpTokenAmount);

        pool.functionCall(data);

        // Iterate through tokens, update tokensOut.
        tokensOut = new uint256[](tokens.length);

        for (uint256 i; i < tokens.length; ++i) {
            if (address(tokens[i]) == CURVE_ETH) {
                // Wrap any ETH we have.
                uint256 ethBalance = address(this).balance;
                IWETH9(nativeWrapper).deposit{ value: ethBalance }();
                // Send WETH back to caller.
                ERC20(nativeWrapper).safeTransfer(msg.sender, ethBalance);
                tokensOut[i] = ethBalance;
            } else {
                // Send ERC20 back to caller
                ERC20 t = ERC20(tokens[i]);
                uint256 tBalance = t.balanceOf(address(this));
                t.safeTransfer(msg.sender, tBalance);
                tokensOut[i] = tBalance;
            }
        }

        _zeroExternalApproval(token, pool);
    }

    //============================================ Helper Functions ===========================================
    function _curveAddLiquidityEncodedCallData(
        uint256[] memory orderedTokenAmounts,
        uint256 minLPAmount,
        bool useUnderlying
    ) internal pure returns (bytes memory data) {
        bytes memory finalEncodedArgOrEmpty;
        if (useUnderlying) {
            finalEncodedArgOrEmpty = abi.encode(true);
        }

        data = abi.encodePacked(
            _curveAddLiquidityEncodeSelector(orderedTokenAmounts.length, useUnderlying),
            abi.encodePacked(orderedTokenAmounts),
            minLPAmount,
            finalEncodedArgOrEmpty
        );
    }

    function _curveAddLiquidityEncodeSelector(
        uint256 numberOfCoins,
        bool useUnderlying
    ) internal pure returns (bytes4 selector_) {
        string memory finalArgOrEmpty;
        if (useUnderlying) {
            finalArgOrEmpty = ",bool";
        }

        return
            bytes4(
                keccak256(
                    abi.encodePacked(
                        "add_liquidity(uint256[",
                        numberOfCoins.toString(),
                        "],",
                        "uint256",
                        finalArgOrEmpty,
                        ")"
                    )
                )
            );
    }

    function _curveRemoveLiquidityEncodedCalldata(
        uint256 lpTokenAmount,
        uint256[] memory orderedTokenAmounts,
        bool useUnderlyings
    ) internal pure returns (bytes memory callData_) {
        bytes memory finalEncodedArgOrEmpty;
        if (useUnderlyings) {
            finalEncodedArgOrEmpty = abi.encode(true);
        }

        return
            abi.encodePacked(
                _curveRemoveLiquidityEncodeSelector(orderedTokenAmounts.length, useUnderlyings),
                lpTokenAmount,
                abi.encodePacked(orderedTokenAmounts),
                finalEncodedArgOrEmpty
            );
    }

    /// @dev Helper to encode selector for a call to remove liquidity on Curve
    function _curveRemoveLiquidityEncodeSelector(
        uint256 numberOfCoins,
        bool useUnderlyings
    ) internal pure returns (bytes4 selector_) {
        string memory finalArgOrEmpty;
        if (useUnderlyings) {
            finalArgOrEmpty = ",bool";
        }

        return
            bytes4(
                keccak256(
                    abi.encodePacked(
                        "remove_liquidity(uint256,",
                        "uint256[",
                        numberOfCoins.toString(),
                        "]",
                        finalArgOrEmpty,
                        ")"
                    )
                )
            );
    }

    // TODO can we add a check in this adaptor, that verifies the calling Cellar has `sharePriceOracle` in it?
    // So if we put it in `balanceOf`, that would full stop all use of a non oracle cellar that adds it
    // But recovering from this would require us to call forcePositionOut, otherwise the cellar is bricked
    // I think in balance of if I can return zero before doing the check, then it would be fine.
    // An attacker would be able to send Curve LP to the cellar to temporaily brick it, but
    // if a lot of mistakes were made, and the position wasa added, then the second total assets call in callOnAdaptor would revert, and prevent
    // a strategist from moving money into it
    function _ensureCallerUsesOracle(address caller) internal view {
        // Try calling `sharePriceOracle` on caller.
        CellarWithOracle(caller).sharePriceOracle();
    }

    // TODO should this really restrict what can be called?
    function _callReentrancyFunction(CurvePool pool, bytes4 selector) internal {
        if (selector == CurvePool.claim_admin_fees.selector) pool.claim_admin_fees();
        else if (selector == CurvePool.withdraw_admin_fees.selector) pool.withdraw_admin_fees();
        else if (selector == bytes4(keccak256(abi.encodePacked("price_oracle()")))) pool.price_oracle();
        else if (selector == bytes4(CurvePool.get_virtual_price.selector)) pool.get_virtual_price();
        else revert("unknown selector");
    }

    /**
     * @notice Helper function that checks if `spender` has any more approval for `asset`, and if so revokes it.
     */
    function _zeroExternalApproval(ERC20 asset, address spender) private {
        if (asset.allowance(address(this), spender) > 0) asset.safeApprove(spender, 0);
    }
}
