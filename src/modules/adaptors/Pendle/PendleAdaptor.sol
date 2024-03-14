// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math} from "src/modules/adaptors/BaseAdaptor.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IMarketFactory, IPendleMarket, ISyToken} from "src/interfaces/external/Pendle/IPendle.sol";
import {PositionlessAdaptor} from "src/modules/adaptors/PositionlessAdaptor.sol";
import {IPAllActionV3} from "@pendle/contracts/interfaces/IPAllActionV3.sol";
import {TokenInput, TokenOutput} from "@pendle/contracts/interfaces/IPAllActionTypeV3.sol";
import {SwapData, SwapType} from "@pendle/contracts/router/swap-aggregator/IPSwapAggregator.sol";
import {ApproxParams} from "@pendle/contracts/router/base/MarketApproxLib.sol";

contract PendleAdaptor is PositionlessAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has NO underlying position, its only purpose is to
    // expose the swap function to strategists during rebalances.
    //====================================================================

    IMarketFactory public immutable marketFactory;
    IPAllActionV3 public immutable router;

    constructor(address _marketFactory, address _router) {
        marketFactory = IMarketFactory(_marketFactory);
        router = IPAllActionV3(_router);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Pendle Adaptor V 0.0"));
    }

    //============================================ Strategist Functions ===========================================

    // TODO custom error messages
    // TODO natspec
    // TODO test reverts

    // mintSyFromToken
    function mintSyFromToken(IPendleMarket market, uint256 minSyOut, TokenInput memory input) external {
        _verifyMarket(market);
        _verifyDexAggregatorInputIsNotUsed(input);

        (address sy,,) = market.readTokens();

        // Approve router to spend input token.
        ERC20 inputToken = ERC20(input.tokenIn);
        input.netTokenIn = _maxAvailable(inputToken, input.netTokenIn);
        inputToken.safeApprove(address(router), input.netTokenIn);
        router.mintSyFromToken(address(this), sy, minSyOut, input);
        _revokeExternalApproval(inputToken, address(router));
    }

    // mintPyFromSy
    function mintPyFromSy(IPendleMarket market, uint256 netSyIn, uint256 minPyOut) external {
        _verifyMarket(market);

        (address sy,, address yt) = market.readTokens();
        ERC20 syIn = ERC20(sy);
        netSyIn = _maxAvailable(syIn, netSyIn);
        syIn.safeApprove(address(router), netSyIn);
        router.mintPyFromSy(address(this), yt, netSyIn, minPyOut);
        _revokeExternalApproval(syIn, address(router));
    }

    // swapExactPtForYt
    function swapExactPtForYt(
        IPendleMarket market,
        uint256 exactPtIn,
        uint256 minYtOut,
        ApproxParams calldata guessTotalYtToSwap
    ) external {
        _verifyMarket(market);
        (, address pt,) = market.readTokens();
        ERC20 ptIn = ERC20(pt);
        exactPtIn = _maxAvailable(ptIn, exactPtIn);
        ptIn.safeApprove(address(router), exactPtIn);
        router.swapExactPtForYt(address(this), address(market), exactPtIn, minYtOut, guessTotalYtToSwap);
        _revokeExternalApproval(ptIn, address(router));
    }

    // swapExactYtForPt
    function swapExactYtForPt(
        IPendleMarket market,
        uint256 exactYtIn,
        uint256 minPtOut,
        ApproxParams calldata guessTotalPtFromSwap
    ) external {
        _verifyMarket(market);
        (,, address yt) = market.readTokens();
        ERC20 ytIn = ERC20(yt);
        exactYtIn = _maxAvailable(ytIn, exactYtIn);
        ytIn.safeApprove(address(router), exactYtIn);
        router.swapExactYtForPt(address(this), address(market), exactYtIn, minPtOut, guessTotalPtFromSwap);
        _revokeExternalApproval(ytIn, address(router));
    }

    // addLiquidityDualSyAndPt
    function addLiquidityDualSyAndPt(IPendleMarket market, uint256 netSyDesired, uint256 netPtDesired, uint256 minLpOut)
        external
    {
        _verifyMarket(market);
        (address sy, address pt,) = market.readTokens();
        ERC20 syIn = ERC20(sy);
        ERC20 ptIn = ERC20(pt);
        netSyDesired = _maxAvailable(syIn, netSyDesired);
        netPtDesired = _maxAvailable(ptIn, netPtDesired);
        syIn.safeApprove(address(router), netSyDesired);
        ptIn.safeApprove(address(router), netPtDesired);
        router.addLiquidityDualSyAndPt(address(this), address(market), netSyDesired, netPtDesired, minLpOut);
        _revokeExternalApproval(syIn, address(router));
        _revokeExternalApproval(ptIn, address(router));
    }

    // removeLiquidityDualSyAndPt
    function removeLiquidityDualSyAndPt(IPendleMarket market, uint256 netLpToRemove, uint256 minSyOut, uint256 minPtOut)
        external
    {
        _verifyMarket(market);
        ERC20 lpIn = ERC20(address(market));
        netLpToRemove = _maxAvailable(lpIn, netLpToRemove);
        lpIn.safeApprove(address(router), netLpToRemove);
        router.removeLiquidityDualSyAndPt(address(this), address(market), netLpToRemove, minSyOut, minPtOut);
        _revokeExternalApproval(lpIn, address(router));
    }

    // redeemPyToSy
    function redeemPyToSy(IPendleMarket market, uint256 netPyIn, uint256 minSyOut) external {
        _verifyMarket(market);
        (, address pt, address yt) = market.readTokens();
        ERC20 ptIn = ERC20(pt);
        ERC20 ytIn = ERC20(yt);
        if (netPyIn == type(uint256).max) {
            uint256 ptBalance = ptIn.balanceOf(address(this));
            uint256 ytBalance = ytIn.balanceOf(address(this));
            // Choose the smaller of the two balances.
            netPyIn = ptBalance > ytBalance ? ytBalance : ptBalance;
        }
        ptIn.safeApprove(address(router), netPyIn);
        ytIn.safeApprove(address(router), netPyIn);
        router.redeemPyToSy(address(this), yt, netPyIn, minSyOut);
        _revokeExternalApproval(ptIn, address(router));
        _revokeExternalApproval(ytIn, address(router));
    }

    // redeemSyToToken
    function redeemSyToToken(IPendleMarket market, uint256 netSyIn, TokenOutput memory output) external {
        _verifyMarket(market);
        _verifyDexAggregatorOutputIsNotUsed(output);
        (address sy,,) = market.readTokens();
        ERC20 syIn = ERC20(sy);
        netSyIn = _maxAvailable(syIn, netSyIn);
        syIn.safeApprove(address(router), netSyIn);
        router.redeemSyToToken(address(this), sy, netSyIn, output);
        _revokeExternalApproval(syIn, address(router));
    }

    //============================================ Internal Helper Functions ===========================================

    function _verifyMarket(IPendleMarket market) internal view {
        if (!marketFactory.isValidMarket(address(market))) revert("Bad market");
    }

    function _verifyDexAggregatorInputIsNotUsed(TokenInput memory input) internal pure {
        if (
            input.tokenIn != input.tokenMintSy || input.pendleSwap != address(0)
                || input.swapData.extRouter != address(0) || input.swapData.swapType != SwapType.NONE
        ) revert("Use aggregator to swap");
    }

    function _verifyDexAggregatorOutputIsNotUsed(TokenOutput memory output) internal pure {
        if (
            output.tokenOut != output.tokenRedeemSy || output.pendleSwap != address(0)
                || output.swapData.extRouter != address(0) || output.swapData.swapType != SwapType.NONE
        ) revert("Use aggregator to swap");
    }
}
