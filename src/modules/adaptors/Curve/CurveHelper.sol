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

/**
 * @title Curve Helper
 * @notice Contains helper logic needed for safely interacting with multiple different Curve Pool implementations.
 * @author crispymangoes
 */
contract CurveHelper {
    using SafeTransferLib for ERC20;
    using Address for address;
    using Strings for uint256;
    using Math for uint256;

    //========================================= Reentrancy Guard Functions =======================================

    /**
     * @notice Attempted to read `locked` from unstructured storage, but found uninitialized value.
     * @dev Most likely an external contract made a delegate call to this contract.
     */
    error CurveHelper___StorageSlotNotInitialized();

    /**
     * @notice Attempted to reenter into this contract.
     */
    error CurveHelper___Reentrancy();

    /**
     * @notice Helper function to read `locked` from unstructured storage.
     */
    function readLockedStorage() internal view returns (uint256 locked) {
        bytes32 position = lockedStoragePosition;
        assembly {
            locked := sload(position)
        }
    }

    /**
     * @notice Helper function to set `locked` to unstructured storage.
     */
    function setLockedStorage(uint256 state) internal {
        bytes32 position = lockedStoragePosition;
        assembly {
            sstore(position, state)
        }
    }

    /**
     * @notice nonReentrant modifier that uses unstructured storage.
     */
    modifier nonReentrant() virtual {
        uint256 locked = readLockedStorage();
        if (locked == 0) revert CurveHelper___StorageSlotNotInitialized();
        if (locked != 1) revert CurveHelper___Reentrancy();

        setLockedStorage(2);

        _;

        setLockedStorage(1);
    }

    /**
     * @notice Attempted to call a function that requires caller implements `sharePriceOracle`.
     */
    error CurveHelper___CallerDoesNotUseOracle();

    /**
     * @notice Attempted to call a function that requires caller implements `decimals`.
     */
    error CurveHelper___CallerMustImplementDecimals();

    /**
     * @notice Provided arrays have mismatched lengths.
     */
    error CurveHelper___MismatchedLengths();

    /**
     * @notice Attempted to interact with Curve LP tokens while the pool is in a re-entered state.
     */
    error CurveHelper___PoolInReenteredState();

    /**
     * @notice While getting pool underlying tokens, more tokens were found than expected.
     */
    error CurveHelper___PoolHasMoreTokensThanExpected();

    /**
     * @notice Native asset repeated twice in add liquidity function.
     */
    error CurveHelper___NativeAssetRepeated();

    /**
     * @notice Attempted a token transfer with zero tokens.
     */
    error CurveHelper___ZeroTransferAmount();

    /**
     * @notice Native ETH(or token) address on current chain.
     */
    address public constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @notice The native token Wrapper contract on current chain.
     */
    address public immutable nativeWrapper;

    /**
     * @notice The slot to store value needed to check for re-entrancy.
     */
    bytes32 public immutable lockedStoragePosition;

    constructor(address _nativeWrapper) {
        nativeWrapper = _nativeWrapper;
        lockedStoragePosition =
            keccak256(abi.encode(uint256(keccak256("curve.helper.storage")) - 1)) &
            ~bytes32(uint256(0xff));

        // Initialize locked storage to 1;
        setLockedStorage(1);
    }

    //========================================= Native Helper Functions =======================================
    /**
     * @notice Cellars can not handle native ETH, so we will use the adaptor as a middle man between
     *         the Cellar and native ETH curve pools.
     */
    receive() external payable {}

    /**
     * @notice Allows Cellars to interact with Curve pools that use native ETH, by using the adaptor as a middle man.
     * @param pool the curve pool address
     * @param lpToken the curve pool token
     * @param underlyingTokens array of ERC20 tokens that make up the curve pool, in order of `pool.coins`
     * @param orderedUnderlyingTokenAmounts array of token amounts, in order of `pool.coins`
     * @param minLPAmount the minimum amount of LP out
     * @param useUnderlying bool indicating whether or not to add a true bool to the end of abi.encoded `addLiquidity` call
     */
    function addLiquidityETHViaProxy(
        address pool,
        ERC20 lpToken,
        ERC20[] memory underlyingTokens,
        uint256[] memory orderedUnderlyingTokenAmounts,
        uint256 minLPAmount,
        bool useUnderlying
    ) external nonReentrant returns (uint256 lpTokenDeltaBalance) {
        if (underlyingTokens.length != orderedUnderlyingTokenAmounts.length) revert CurveHelper___MismatchedLengths();

        uint256 nativeEthAmount;

        // Transfer assets to the adaptor.
        for (uint256 i; i < underlyingTokens.length; ++i) {
            if (address(underlyingTokens[i]) == CURVE_ETH) {
                if (nativeEthAmount != 0) revert CurveHelper___NativeAssetRepeated();

                // If token is CURVE_ETH, then approve adaptor to spend native wrapper.
                ERC20(nativeWrapper).safeTransferFrom(msg.sender, address(this), orderedUnderlyingTokenAmounts[i]);
                // Unwrap native.
                IWETH9(nativeWrapper).withdraw(orderedUnderlyingTokenAmounts[i]);

                nativeEthAmount = orderedUnderlyingTokenAmounts[i];
            } else {
                underlyingTokens[i].safeTransferFrom(msg.sender, address(this), orderedUnderlyingTokenAmounts[i]);
                // Approve pool to spend ERC20 assets.
                underlyingTokens[i].safeApprove(pool, orderedUnderlyingTokenAmounts[i]);
            }
        }

        // Generate `add_liquidity` function call data.
        bytes memory data = _curveAddLiquidityEncodedCallData(
            orderedUnderlyingTokenAmounts,
            minLPAmount,
            useUnderlying
        );

        // Track the change in lpToken balance.
        lpTokenDeltaBalance = lpToken.balanceOf(address(this));

        pool.functionCallWithValue(data, nativeEthAmount);

        // Send LP tokens back to caller.
        lpTokenDeltaBalance = lpToken.balanceOf(address(this)) - lpTokenDeltaBalance;
        if (lpTokenDeltaBalance == 0) revert CurveHelper___ZeroTransferAmount();
        lpToken.safeTransfer(msg.sender, lpTokenDeltaBalance);

        // Revoke any unused approvals.
        for (uint256 i; i < underlyingTokens.length; ++i) {
            if (address(underlyingTokens[i]) != CURVE_ETH) _zeroExternalApproval(underlyingTokens[i], address(this));
        }
    }

    /**
     * @notice Allows Cellars to interact with Curve pools that use native ETH, by using the adaptor as a middle man.
     * @param pool the curve pool address
     * @param lpToken the curve pool token
     * @param lpTokenAmount the amount of LP token
     * @param underlyingTokens array of ERC20 tokens that make up the curve pool, in order of `pool.coins`
     * @param orderedMinimumUnderlyingTokenAmountsOut array of minimum token amounts out, in order of `pool.coins`
     * @param useUnderlying bool indicating whether or not to add a true bool to the end of abi.encoded `removeLiquidity` call
     */
    function removeLiquidityETHViaProxy(
        address pool,
        ERC20 lpToken,
        uint256 lpTokenAmount,
        ERC20[] memory underlyingTokens,
        uint256[] memory orderedMinimumUnderlyingTokenAmountsOut,
        bool useUnderlying
    ) external nonReentrant returns (uint256[] memory balanceDelta) {
        if (underlyingTokens.length != orderedMinimumUnderlyingTokenAmountsOut.length)
            revert CurveHelper___MismatchedLengths();

        // Generate `remove_liquidity` function call data.
        bytes memory data = _curveRemoveLiquidityEncodedCalldata(
            lpTokenAmount,
            orderedMinimumUnderlyingTokenAmountsOut,
            useUnderlying
        );

        // Transfer token in.
        lpToken.safeTransferFrom(msg.sender, address(this), lpTokenAmount);

        // Track the changes in token balances.
        balanceDelta = new uint256[](underlyingTokens.length);
        for (uint256 i; i < underlyingTokens.length; ++i) {
            if (address(underlyingTokens[i]) == CURVE_ETH) {
                balanceDelta[i] = address(this).balance;
            } else {
                balanceDelta[i] = ERC20(underlyingTokens[i]).balanceOf(address(this));
            }
        }

        pool.functionCall(data);

        for (uint256 i; i < underlyingTokens.length; ++i) {
            if (address(underlyingTokens[i]) == CURVE_ETH) {
                balanceDelta[i] = address(this).balance - balanceDelta[i];
                if (balanceDelta[i] == 0) revert CurveHelper___ZeroTransferAmount();
                // Wrap any ETH we have.
                IWETH9(nativeWrapper).deposit{ value: balanceDelta[i] }();
                // Send WETH back to caller.
                ERC20(nativeWrapper).safeTransfer(msg.sender, balanceDelta[i]);
            } else {
                balanceDelta[i] = ERC20(underlyingTokens[i]).balanceOf(address(this)) - balanceDelta[i];
                if (balanceDelta[i] == 0) revert CurveHelper___ZeroTransferAmount();
                // Send ERC20 back to caller
                ERC20 token = ERC20(underlyingTokens[i]);
                token.safeTransfer(msg.sender, balanceDelta[i]);
            }
        }

        // Revoke any unused approval.
        _zeroExternalApproval(lpToken, pool);
    }

    //============================================ Helper Functions ===========================================
    /**
     * @notice Helper function to handle adding liquidity to Curve pools with different token lengths.
     */
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

    /**
     * @notice Helper function to handle adding liquidity to Curve pools with different token lengths.
     */
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

    /**
     * @notice Helper function to handle removing liquidity from Curve pools with different token lengths.
     */
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

    /**
     * @notice Helper function to handle removing liquidity from Curve pools with different token lengths.
     */
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

    /**
     * @notice Enforces that cellars using Curve positions, use a Share Price Oracle.
     * @dev This is done to help mitigate re-entrancy attacks that have historically targeted Curve Pools.
     */
    function _ensureCallerUsesOracle(address caller) internal view {
        // Try calling `sharePriceOracle` on caller.
        try CellarWithOracle(caller).sharePriceOracle() {} catch {
            revert CurveHelper___CallerDoesNotUseOracle();
        }
    }

    /**
     * @notice Call a reentrancy protected function in `pool`.
     * @dev Used to insure `pool` is not in a manipulated state.
     */
    function _callReentrancyFunction(CurvePool pool, bytes4 selector) internal {
        // address(pool).functionCall(abi.encodePacked(selector));
        (bool success, ) = address(pool).call(abi.encodePacked(selector));

        if (!success) revert CurveHelper___PoolInReenteredState();
    }

    /**
     * @notice Helper function that checks if `spender` has any more approval for `asset`, and if so revokes it.
     */
    function _zeroExternalApproval(ERC20 asset, address spender) private {
        if (asset.allowance(address(this), spender) > 0) asset.safeApprove(spender, 0);
    }

    /**
     * @notice Helper function to get the underlying tokens in a Curve pool.
     */
    function _getPoolUnderlyingTokens(
        CurvePool pool,
        uint256 expectedTokenCount
    ) internal view returns (ERC20[] memory underlyingTokens) {
        underlyingTokens = new ERC20[](expectedTokenCount);

        // It is expected behavior that if expectedTokenCount is > than the actual token count, this will revert.
        for (uint256 i; i < expectedTokenCount; ++i) underlyingTokens[i] = ERC20(pool.coins(i));

        // Make sure expectedTokenCount is correct, and that there are not more tokens.
        try pool.coins(expectedTokenCount) {
            revert CurveHelper___PoolHasMoreTokensThanExpected();
        } catch {
            // Do nothing we expect this to revert here.
        }
    }
}
