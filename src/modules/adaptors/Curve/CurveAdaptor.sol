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
 * @title ERC20 Adaptor
 * @notice Allows Cellars to interact with Curve LP positions.
 * @author crispymangoes
 */
contract CurveAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Address for address;
    using Strings for uint256;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address pool, address token, address gauge, bytes4)
    // Where:
    // TODO
    //================= Configuration Data Specification =================
    // TODO will probs be an isLiquid bool
    // Also maybe a bool indicating whether you want to deposit into the gauge or nah
    //====================================================================

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Curve Adaptor V 0.0"));
    }

    address public constant CURVE_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public immutable nativeWrapper;
    address payable public immutable addressThis;
    uint32 public immutable curveSlippage;

    constructor(address _nativeWrapper, uint32 _curveSlippage) {
        nativeWrapper = _nativeWrapper;
        addressThis = payable(address(this));
        curveSlippage = _curveSlippage;
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar already has possession of users Curve LP tokens by the time this function is called,
     *         so there is nothing to do.
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        (, ERC20 token, CurveGauge gauge) = abi.decode(adaptorData, (CurvePool, ERC20, CurveGauge));

        if (address(gauge) != address(0)) {
            // Deposit into gauge.
            token.safeApprove(address(gauge), assets);
            gauge.deposit(assets, address(this));
            _revokeExternalApproval(token, address(gauge));
        }
    }

    /**
     * @notice Cellar just needs to transfer ERC20 token to `receiver`.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets amount of `token` to send to receiver
     * @param receiver address to send assets to
     * @param adaptorData data needed to withdraw from this position
     * @dev configurationData is NOT used
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory) public override {
        _externalReceiverCheck(receiver);
        (CurvePool pool, ERC20 token, CurveGauge gauge, bytes4 selector) = abi.decode(
            adaptorData,
            (CurvePool, ERC20, CurveGauge, bytes4)
        );
        _callReentrancyFunction(pool, selector);

        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance < assets) {
            // Pull from gauge.
            gauge.withdraw(assets - tokenBalance, false);
        }

        token.safeTransfer(receiver, assets);
    }

    /**
     * @notice Identical to `balanceOf`, if an asset is used with a non ERC20 standard locking logic,
     *         then a NEW adaptor contract is needed.
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory configurationData
    ) public view override returns (uint256) {
        (, ERC20 token, CurveGauge gauge) = abi.decode(adaptorData, (CurvePool, ERC20, CurveGauge));
        bool isLiquid = abi.decode(configurationData, (bool));
        if (isLiquid) {
            return token.balanceOf(msg.sender) + gauge.balanceOf(msg.sender);
        } else return 0;
    }

    /**
     * @notice Returns the balance of `token`.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (, ERC20 token, CurveGauge gauge) = abi.decode(adaptorData, (CurvePool, ERC20, CurveGauge));
        return token.balanceOf(msg.sender) + gauge.balanceOf(msg.sender);
    }

    /**
     * @notice Returns `token`
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        (, ERC20 token) = abi.decode(adaptorData, (CurvePool, ERC20));
        return token;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    // TODO so use underlying is also used for aToken pools, where if it is true it will give you the vanilla ERC20 on withdraw vs the aToken...... :(((((((((
    function addLiquidity(
        address pool,
        ERC20 token,
        ERC20[] memory tokens,
        uint256[] memory orderedTokenAmounts,
        uint256 minLPAmount
    ) external {
        if (tokens.length != orderedTokenAmounts.length) revert("Bad data");
        bytes memory data = _curveAddLiquidityEncodedCallData(orderedTokenAmounts, minLPAmount, false);

        uint256 balanceDelta = token.balanceOf(address(this));

        // Approve pool to spend amounts
        for (uint256 i; i < tokens.length; ++i)
            if (orderedTokenAmounts[i] > 0) tokens[i].safeApprove(pool, orderedTokenAmounts[i]);

        pool.functionCall(data);

        balanceDelta = token.balanceOf(address(this)) - balanceDelta;

        uint256 lpValueIn = Cellar(address(this)).priceRouter().getValues(tokens, orderedTokenAmounts, token);
        uint256 minValueOut = lpValueIn.mulDivDown(curveSlippage, 1e4);
        if (balanceDelta < minValueOut) revert(":(");

        for (uint256 i; i < tokens.length; ++i)
            if (orderedTokenAmounts[i] > 0) _revokeExternalApproval(tokens[i], pool);
    }

    // Add liquidity to a pool using native ETH.
    function addLiquidityETH(
        address pool,
        ERC20 token,
        ERC20[] memory tokens,
        uint256[] memory orderedTokenAmounts,
        uint256 minLPAmount,
        bool useUnderlying
    ) external {
        if (tokens.length != orderedTokenAmounts.length) revert("Bad data");

        // Approve pool to spend amounts
        for (uint256 i; i < tokens.length; ++i) {
            if (address(tokens[i]) == CURVE_ETH) {
                // If token is CURVE_ETH, then approve adaptor to spend native wrapper.
                ERC20(nativeWrapper).safeApprove(addressThis, orderedTokenAmounts[i]);
            } else {
                tokens[i].safeApprove(addressThis, orderedTokenAmounts[i]);
            }
        }

        uint256 lpOut = CurveAdaptor(addressThis).addLiquidityETHViaProxy(
            pool,
            token,
            tokens,
            orderedTokenAmounts,
            minLPAmount,
            useUnderlying
        );

        uint256 lpValueIn = Cellar(address(this)).priceRouter().getValues(tokens, orderedTokenAmounts, token);
        uint256 minValueOut = lpValueIn.mulDivDown(curveSlippage, 1e4);
        if (lpOut < minValueOut) revert(":(");

        for (uint256 i; i < tokens.length; ++i) {
            if (address(tokens[i]) == CURVE_ETH) _revokeExternalApproval(ERC20(nativeWrapper), addressThis);
            else _revokeExternalApproval(tokens[i], addressThis);
        }
    }

    function removeLiquidity(
        address pool,
        ERC20 token,
        uint256 lpTokenAmount,
        ERC20[] memory tokens,
        uint256[] memory orderedTokenAmountsOut
    ) external {
        if (tokens.length != orderedTokenAmountsOut.length) revert("Bad data");
        bytes memory data = _curveRemoveLiquidityEncodedCalldata(lpTokenAmount, orderedTokenAmountsOut, false);

        uint256[] memory balanceDelta = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) balanceDelta[i] = ERC20(tokens[i]).balanceOf(address(this));

        pool.functionCall(data);

        for (uint256 i; i < tokens.length; ++i)
            balanceDelta[i] = ERC20(tokens[i]).balanceOf(address(this)) - balanceDelta[i];

        uint256 lpValueOut = Cellar(address(this)).priceRouter().getValues(tokens, balanceDelta, token);
        uint256 minValueOut = lpTokenAmount.mulDivDown(curveSlippage, 1e4);
        if (lpValueOut < minValueOut) revert(":(");

        _revokeExternalApproval(token, pool);
    }

    function removeLiquidityETH(
        address pool,
        ERC20 token,
        uint256 lpTokenAmount,
        ERC20[] memory tokens,
        uint256[] memory orderedTokenAmountsOut,
        bool useUnderlying
    ) external {
        if (tokens.length != orderedTokenAmountsOut.length) revert("Bad data");

        uint256[] memory balanceDelta = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) balanceDelta[i] = ERC20(tokens[i]).balanceOf(address(this));

        token.safeApprove(addressThis, lpTokenAmount);

        uint256[] memory tokensOut = CurveAdaptor(addressThis).removeLiquidityETHViaProxy(
            pool,
            token,
            lpTokenAmount,
            tokens,
            orderedTokenAmountsOut,
            useUnderlying
        );

        uint256 lpValueOut = Cellar(address(this)).priceRouter().getValues(tokens, tokensOut, token);
        uint256 minValueOut = lpTokenAmount.mulDivDown(curveSlippage, 1e4);
        if (lpValueOut < minValueOut) revert(":(");

        _revokeExternalApproval(token, addressThis);
    }

    // TODO remove_liquidity_one_coin
    function removeLiquidityOneCoin(
        address pool,
        ERC20 token,
        uint256 lpTokenAmount,
        uint256 i,
        uint256 minOut
    ) external {
        CurvePool curvePool = CurvePool(pool);

        ERC20 tokenOut = ERC20(curvePool.coins(i));

        if (address(tokenOut) == CURVE_ETH) revert("no no no");

        uint256 balanceDelta = tokenOut.balanceOf(address(this));

        curvePool.remove_liquidity_one_coin(lpTokenAmount, int128(uint128(i)), minOut);

        balanceDelta = tokenOut.balanceOf(address(this)) - balanceDelta;

        uint256 valueOut = Cellar(address(this)).priceRouter().getValue(tokenOut, balanceDelta, token);
        uint256 minValueOut = lpTokenAmount.mulDivDown(curveSlippage, 1e4);
        if (valueOut < minValueOut) revert(":(");
    }

    function removeLiquidityOneCoinETH(
        address pool,
        ERC20 token,
        uint256 lpTokenAmount,
        uint256 i,
        uint256 minOut
    ) external {
        CurvePool curvePool = CurvePool(pool);

        ERC20 tokenOut = ERC20(curvePool.coins(i));

        if (address(tokenOut) != CURVE_ETH) revert("no no no");

        token.safeApprove(addressThis, lpTokenAmount);

        uint256 wethOut = CurveAdaptor(addressThis).removeLiquidityOneCoinETHViaProxy(
            pool,
            token,
            lpTokenAmount,
            i,
            minOut
        );

        uint256 valueOut = Cellar(address(this)).priceRouter().getValue(ERC20(nativeWrapper), wethOut, token);
        uint256 minValueOut = lpTokenAmount.mulDivDown(curveSlippage, 1e4);
        if (valueOut < minValueOut) revert(":(");

        _revokeExternalApproval(token, addressThis);
    }

    // TODO remove liquidity imbalance?

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
        if (Cellar(address(this)).blockExternalReceiver()) revert("Not callable by strategist");

        uint256 nativeEthAmount;

        // Transfer assets to the adaptor.
        for (uint256 i; i < tokens.length; ++i) {
            if (address(tokens[i]) == CURVE_ETH) {
                // If token is CURVE_ETH, then approve adaptor to spend native wrapper.
                ERC20(nativeWrapper).safeTransferFrom(msg.sender, addressThis, orderedTokenAmounts[i]);
                // Unwrap native.
                IWETH9(nativeWrapper).withdraw(orderedTokenAmounts[i]);

                nativeEthAmount = orderedTokenAmounts[i];
            } else {
                tokens[i].safeTransferFrom(msg.sender, addressThis, orderedTokenAmounts[i]);
                // Approve pool to spend ERC20 assets.
                tokens[i].safeApprove(pool, orderedTokenAmounts[i]);
            }
        }

        bytes memory data = _curveAddLiquidityEncodedCallData(orderedTokenAmounts, minLPAmount, useUnderlying);

        pool.functionCallWithValue(data, nativeEthAmount);

        // Send LP tokens back to caller.
        ERC20 lpToken = ERC20(token);
        lpOut = lpToken.balanceOf(addressThis);
        lpToken.safeTransfer(msg.sender, lpOut);

        for (uint256 i; i < tokens.length; ++i) {
            if (address(tokens[i]) != CURVE_ETH) _revokeExternalApproval(tokens[i], addressThis);
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
        if (Cellar(address(this)).blockExternalReceiver()) revert("Not callable by strategist");

        if (tokens.length != orderedTokenAmountsOut.length) revert("Bad data");
        bytes memory data = _curveRemoveLiquidityEncodedCalldata(lpTokenAmount, orderedTokenAmountsOut, useUnderlying);

        // Transfer token in.
        token.safeTransferFrom(msg.sender, addressThis, lpTokenAmount);

        uint256[] memory balanceDelta = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) balanceDelta[i] = ERC20(tokens[i]).balanceOf(address(this));

        pool.functionCall(data);

        // Iterate through tokens, update tokensOut.
        tokensOut = new uint256[](tokens.length);

        for (uint256 i; i < tokens.length; ++i) {
            if (address(tokens[i]) == CURVE_ETH) {
                // Wrap any ETH we have.
                uint256 ethBalance = addressThis.balance;
                IWETH9(nativeWrapper).deposit{ value: ethBalance }();
                // Send WETH back to caller.
                ERC20(nativeWrapper).safeTransfer(msg.sender, ethBalance);
                tokensOut[i] = ethBalance;
            } else {
                // Send ERC20 back to caller
                ERC20 t = ERC20(tokens[i]);
                uint256 tBalance = t.balanceOf(addressThis);
                t.safeTransfer(msg.sender, tBalance);
                tokensOut[i] = tBalance;
            }
        }

        _revokeExternalApproval(token, pool);
    }

    function removeLiquidityOneCoinETHViaProxy(
        address pool,
        ERC20 token,
        uint256 lpTokenAmount,
        uint256 i,
        uint256 minOut
    ) external returns (uint256 ethOut) {
        if (Cellar(address(this)).blockExternalReceiver()) revert("Not callable by strategist");

        token.safeTransferFrom(msg.sender, addressThis, lpTokenAmount);

        CurvePool(pool).remove_liquidity_one_coin(lpTokenAmount, int128(uint128(i)), minOut);

        ethOut = addressThis.balance;

        IWETH9(nativeWrapper).deposit{ value: ethOut }();

        ERC20(nativeWrapper).safeTransfer(msg.sender, ethOut);
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
    ) private pure returns (bytes memory callData_) {
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
    ) private pure returns (bytes4 selector_) {
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

    // TODO move into a seperate contract since convex adaptor would use this as well.
    function _callReentrancyFunction(CurvePool pool, bytes4 selector) internal {
        if (selector == CurvePool.claim_admin_fees.selector) pool.claim_admin_fees();
        else if (selector == CurvePool.withdraw_admin_fees.selector) pool.withdraw_admin_fees();
    }
}
