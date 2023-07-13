// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { AaveV2EnableAssetAsCollateralAdaptor } from "src/modules/adaptors/Aave/AaveV2EnableAssetAsCollateralAdaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";

// Import adaptors.
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract RYEstETHTest is Test {
    using Math for uint256;

    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private controller = 0xaDa78a5E01325B91Bc7879a63c309F7D54d42950;

    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    Cellar private rye = Cellar(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    // Aave V2 Positions.
    ERC20 public aV2WETH = ERC20(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e);
    ERC20 public dV2WETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);
    ERC20 public aV2stETH = ERC20(0x1982b2F5814301d4e9a8b0201555376e62F82428);

    address public swapWithUniswapAdaptor = 0xd6BC6Df1ed43e3101bC27a4254593a06598a3fDD;
    address public aaveV3AtokenAdaptor = 0x3184CBEa47eD519FA04A23c4207cD15b7545F1A6;

    address public aaveV2AtokenAdaptor = 0xe3A3b8AbbF3276AD99366811eDf64A0a4b30fDa2;
    address public aaveV2DebtTokenAdaptor = 0xeC86ac06767e911f5FdE7cba5D97f082C0139C01;

    address public erc20Adaptor = 0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE;

    IPool private aavePool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    function setUp() external {}

    function testAddingAaveV2EnableAssetAsCollateralAdaptor() external {
        if (block.number < 17034079) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 17034079.");
            return;
        }

        // Add stETH ERC20 position to cellar, so we can swap into it in a seperate rebalance.
        vm.prank(gravityBridge);
        rye.addPosition(0, 104, abi.encode(0), false);

        // Rebalance cellar to remove assets from Aave V3.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV3(WETH, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: aaveV3AtokenAdaptor, callData: adaptorCalls });
        }

        vm.prank(gravityBridge);
        rye.callOnAdaptor(data);

        // Strategist swaps 10 WETH to stETH, and supplies the stETH on Aave V2
        data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwap(WETH, stETH, 10e18);
            data[0] = Cellar.AdaptorCall({ adaptor: swapWithUniswapAdaptor, callData: adaptorCalls });
        }

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(stETH, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: aaveV2AtokenAdaptor, callData: adaptorCalls });
        }

        vm.prank(gravityBridge);
        rye.callOnAdaptor(data);

        // Strategist tries to borrow weth against their stETH.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(dV2WETH, 1e18);
            data[0] = Cellar.AdaptorCall({ adaptor: aaveV2DebtTokenAdaptor, callData: adaptorCalls });
        }

        vm.startPrank(gravityBridge);
        vm.expectRevert(bytes("11"));
        rye.callOnAdaptor(data);
        vm.stopPrank();

        // Add AaveV2EnableAssetAsCollateralAdaptor adaptor to registry and cellar.
        AaveV2EnableAssetAsCollateralAdaptor fix = new AaveV2EnableAssetAsCollateralAdaptor(address(aavePool), 1.05e18);
        vm.prank(multisig);
        registry.trustAdaptor(address(fix));

        vm.prank(gravityBridge);
        rye.addAdaptorToCatalogue(address(fix));

        // Strategist performs the same rebalance, but sets stETH up as collateral.
        data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                AaveV2EnableAssetAsCollateralAdaptor.setUserUseReserveAsCollateral.selector,
                address(stETH),
                true
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(fix), callData: adaptorCalls });
        }

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(dV2WETH, 7e18);
            data[1] = Cellar.AdaptorCall({ adaptor: aaveV2DebtTokenAdaptor, callData: adaptorCalls });
        }

        vm.prank(gravityBridge);
        rye.callOnAdaptor(data);

        // Strategist lends some WETH on V2.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WETH, 8.1e18);
            data[0] = Cellar.AdaptorCall({ adaptor: aaveV2AtokenAdaptor, callData: adaptorCalls });
        }

        vm.prank(gravityBridge);
        rye.callOnAdaptor(data);

        // Strategist tries to set collateral to false which lowers the HF below HFMIN().
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                AaveV2EnableAssetAsCollateralAdaptor.setUserUseReserveAsCollateral.selector,
                address(stETH),
                false
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(fix), callData: adaptorCalls });
        }
        vm.startPrank(gravityBridge);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    AaveV2EnableAssetAsCollateralAdaptor
                        .AaveV2EnableAssetAsCollateralAdaptor__HealthFactorTooLow
                        .selector
                )
            )
        );
        rye.callOnAdaptor(data);
        vm.stopPrank();

        // But if strategist adds more collateral, then they can set useAsCollateral to false.
        data = new Cellar.AdaptorCall[](2);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WETH, 10e18);
            data[0] = Cellar.AdaptorCall({ adaptor: aaveV2AtokenAdaptor, callData: adaptorCalls });
        }

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                AaveV2EnableAssetAsCollateralAdaptor.setUserUseReserveAsCollateral.selector,
                address(stETH),
                false
            );
            data[1] = Cellar.AdaptorCall({ adaptor: address(fix), callData: adaptorCalls });
        }

        vm.prank(gravityBridge);
        rye.callOnAdaptor(data);
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _createBytesDataForSwap(ERC20 from, ERC20 to, uint256 fromAmount) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV2.selector, path, fromAmount, 0);
    }

    function _createBytesDataToLend(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToBorrow(ERC20 debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToWithdrawFromAaveV3(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }
}
