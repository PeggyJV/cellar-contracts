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
import { CurveHelper } from "src/modules/adaptors/Curve/CurveHelper.sol";

import { console } from "@forge-std/Test.sol";

// TODO Curve Gauges can TECHNICALLY have a non 18 decimal value :(
// TODO remove
/**
 * @title ERC20 Adaptor
 * @notice Allows Cellars to interact with Curve LP positions.
 * @author crispymangoes
 */
contract CurveAdaptor is BaseAdaptor, CurveHelper {
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

    address payable public immutable addressThis;
    uint32 public immutable curveSlippage;

    constructor(address _nativeWrapper, uint32 _curveSlippage) CurveHelper(_nativeWrapper) {
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
        if (balanceDelta < minValueOut) revert(":(0");

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

        // Approve adaptor to spend amounts
        for (uint256 i; i < tokens.length; ++i) {
            if (address(tokens[i]) == CURVE_ETH) {
                // If token is CURVE_ETH, then approve adaptor to spend native wrapper.
                ERC20(nativeWrapper).safeApprove(addressThis, orderedTokenAmounts[i]);
            } else {
                tokens[i].safeApprove(addressThis, orderedTokenAmounts[i]);
            }
        }

        uint256 lpOut = CurveHelper(addressThis).addLiquidityETHViaProxy(
            pool,
            token,
            tokens,
            orderedTokenAmounts,
            minLPAmount,
            useUnderlying
        );

        for (uint256 i; i < tokens.length; ++i) if (address(tokens[i]) == CURVE_ETH) tokens[i] = ERC20(nativeWrapper);
        uint256 lpValueIn = Cellar(address(this)).priceRouter().getValues(tokens, orderedTokenAmounts, token);
        uint256 minValueOut = lpValueIn.mulDivDown(curveSlippage, 1e4);
        if (lpOut < minValueOut) revert(":(1");

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
        lpTokenAmount = _maxAvailable(token, lpTokenAmount);
        bytes memory data = _curveRemoveLiquidityEncodedCalldata(lpTokenAmount, orderedTokenAmountsOut, false);

        uint256[] memory balanceDelta = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) balanceDelta[i] = ERC20(tokens[i]).balanceOf(address(this));

        pool.functionCall(data);

        for (uint256 i; i < tokens.length; ++i)
            balanceDelta[i] = ERC20(tokens[i]).balanceOf(address(this)) - balanceDelta[i];

        uint256 lpValueOut = Cellar(address(this)).priceRouter().getValues(tokens, balanceDelta, token);
        uint256 minValueOut = lpTokenAmount.mulDivDown(curveSlippage, 1e4);
        if (lpValueOut < minValueOut) revert(":(2");

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
        lpTokenAmount = _maxAvailable(token, lpTokenAmount);

        token.safeApprove(addressThis, lpTokenAmount);

        uint256[] memory tokensOut = CurveHelper(addressThis).removeLiquidityETHViaProxy(
            pool,
            token,
            lpTokenAmount,
            tokens,
            orderedTokenAmountsOut,
            useUnderlying
        );

        for (uint256 i; i < tokens.length; ++i) if (address(tokens[i]) == CURVE_ETH) tokens[i] = ERC20(nativeWrapper);
        uint256 lpValueOut = Cellar(address(this)).priceRouter().getValues(tokens, tokensOut, token);
        uint256 minValueOut = lpTokenAmount.mulDivDown(curveSlippage, 1e4);
        if (lpValueOut < minValueOut) revert(":(3");

        _revokeExternalApproval(token, addressThis);
    }

    function stakeInGauge(ERC20 token, CurveGauge gauge, uint256 amount) external {
        amount = _maxAvailable(token, amount);
        token.safeApprove(address(gauge), amount);
        gauge.deposit(amount, address(this));
        _revokeExternalApproval(token, address(gauge));
    }

    function unStakeFromGauge(CurveGauge gauge, uint256 amount) external {
        if (amount == type(uint256).max) amount = gauge.balanceOf(address(this));
        gauge.withdraw(amount);
    }

    function getRewards(CurveGauge gauge) external {
        gauge.claim_rewards();
    }
}
