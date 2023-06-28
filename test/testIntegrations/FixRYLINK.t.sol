// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract FixRYLINK is Test {
    using Math for uint256;

    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private controller = 0xaDa78a5E01325B91Bc7879a63c309F7D54d42950;

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    CellarInitializableV2_2 private rye = CellarInitializableV2_2(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);
    CellarInitializableV2_2 private ryLink = CellarInitializableV2_2(0x4068BDD217a45F8F668EF19F1E3A1f043e4c4934);

    CellarAdaptor private cellarAdaptor = CellarAdaptor(0x3B5CA5de4d808Cd793d3a7b3a731D3E67E707B27);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    // Aave V3 Positions
    ERC20 public aV3WETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 public dV3WETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);
    ERC20 public aV3Link = ERC20(0x5E8C8A7243651DB1384C0dDfDbE39761E8e7E51a);

    AaveV3ATokenAdaptor public aaveV3AtokenAdaptor = AaveV3ATokenAdaptor(0x3184CBEa47eD519FA04A23c4207cD15b7545F1A6);
    AaveV3DebtTokenAdaptor public aaveV3DebtTokenAdaptor =
        AaveV3DebtTokenAdaptor(0x6DEd49176a69bEBf8dC1a4Ea357faa555df188f7);
    AaveATokenAdaptor public aaveATokenAdaptor = AaveATokenAdaptor(0xe3A3b8AbbF3276AD99366811eDf64A0a4b30fDa2);
    AaveDebtTokenAdaptor public aaveDebtTokenAdaptor = AaveDebtTokenAdaptor(0xeC86ac06767e911f5FdE7cba5D97f082C0139C01);
    address public erc20Adaptor = 0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE;

    address public oldCellarAdaptor = 0x24EEAa1111DAc1c0fE0Cf3c03bBa03ADde1e7Fe4;

    uint32 oldRyePosition = 143;
    uint32 aaveV3ALinkPosition = 153;
    uint32 aaveV3DebtWethPosition = 114;
    uint32 vanillaLinkPosition = 144;

    modifier checkBlockNumber() {
        if (block.number < 17579366) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 17579366.");
            return;
        }
        _;
    }

    function testRealYieldLink() external {
        // Distrust old adaptor and position in registry.
        vm.startPrank(multisig);
        registry.distrustPosition(oldRyePosition);
        registry.distrustAdaptor(oldCellarAdaptor);
        vm.stopPrank();

        // Have Real Yield Link rebalance so it only holds LINK.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromCellar(address(rye), type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(oldCellarAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRepayDebt(address(WETH), type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromAave(address(LINK), type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }

        vm.prank(gravityBridge);
        ryLink.callOnAdaptor(data);

        uint256 ryeShareBalance = rye.balanceOf(address(ryLink));
        assertEq(ryeShareBalance, 0, "RYLINK should have no RYE shares.");

        // Strategist can now remove RYE position, and remove it from catalogues.
        // Also remove debt position, and Aave V2 aLink position.
        vm.startPrank(gravityBridge);
        ryLink.setHoldingPosition(vanillaLinkPosition);
        ryLink.removePosition(0, false);
        ryLink.removePosition(0, false);
        ryLink.removePosition(0, true);
        ryLink.removePositionFromCatalogue(oldRyePosition);
        ryLink.removeAdaptorFromCatalogue(address(oldCellarAdaptor));
        vm.stopPrank();

        vm.startPrank(multisig);
        // Add new adaptor and position to registry.
        registry.trustAdaptor(address(cellarAdaptor));
        uint32 newRyePosition = registry.trustPosition(address(cellarAdaptor), abi.encode(rye));
        vm.stopPrank();

        // Steward is upgraded to allow strategist to enter new RYE position using Aave V3.
        vm.startPrank(gravityBridge);
        ryLink.addAdaptorToCatalogue(address(cellarAdaptor));
        ryLink.addPositionToCatalogue(newRyePosition);
        ryLink.addPosition(1, newRyePosition, abi.encode(false), false);
        ryLink.addPosition(0, aaveV3ALinkPosition, abi.encode(1.1e18), false);
        ryLink.addPosition(0, aaveV3DebtWethPosition, abi.encode(0), true);
        vm.stopPrank();

        // Figure out how much WETH to borrow.
        uint256 linkLtv = 0.53e4;
        uint256 targetHealthFactor = 1.1e4;
        uint256 linkBalance = LINK.balanceOf(address(ryLink));
        // This debt is denominated in link.
        uint256 debt = linkBalance.mulDivDown(linkLtv, targetHealthFactor);
        // Convert debt to WETH.
        debt = priceRouter.getValue(LINK, debt, WETH);

        // Strategist can now rebalance into RYE.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToAave(address(LINK), type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(aaveV3AtokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(address(dV3WETH), debt);
            data[1] = Cellar.AdaptorCall({ adaptor: address(aaveV3DebtTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToCellar(address(rye), type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }

        vm.prank(gravityBridge);
        ryLink.callOnAdaptor(data);

        // Make sure we lent LINK on aave.
        assertApproxEqRel(
            aV3Link.balanceOf(address(ryLink)),
            linkBalance,
            0.005e18,
            "All link should have been deposited into Aave."
        );
        // Make sure we took out the right amount of debt.
        assertApproxEqAbs(
            dV3WETH.balanceOf(address(ryLink)),
            debt,
            0.005e18,
            "Cellar should have taken out correct amount of debt."
        );
        // Make sure we entered RYE.
        uint256 wethInRye = rye.previewRedeem(rye.balanceOf(address(ryLink)));
        assertApproxEqRel(wethInRye, debt, 0.005e18, "All the debt should have been deposited into RYE.");
    }

    function _createBytesDataToDepositToCellar(address cellar, uint256 assets) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CellarAdaptor.depositToCellar.selector, cellar, assets);
    }

    function _createBytesDataToWithdrawFromCellar(address cellar, uint256 assets) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CellarAdaptor.withdrawFromCellar.selector, cellar, assets);
    }

    function _createBytesDataToDepositToAave(
        address tokenToDeposit,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.depositToAave.selector, tokenToDeposit, amount);
    }

    function _createBytesDataToWithdrawFromAave(
        address tokenToWithdraw,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amount);
    }

    function _createBytesDataToRepayDebt(address tokenToRepay, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amount);
    }

    function _createBytesDataToBorrow(address tokenToBorrow, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.borrowFromAave.selector, tokenToBorrow, amount);
    }
}
