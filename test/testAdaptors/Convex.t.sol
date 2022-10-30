// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { ConvexAdaptor } from "src/modules/adaptors/Convex/ConvexAdaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { IBooster } from "src/interfaces/external/IBooster.sol";
import { IRewardPool } from "src/interfaces/external/IRewardPool.sol";

import { ICurvePool } from "src/interfaces/external/ICurvePool.sol";

import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";


import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarConvexTest is Test {
    using SafeERC20 for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    ConvexAdaptor private convexAdaptor;
    ERC20Adaptor private erc20Adaptor;
    MockCellar private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;

    address private immutable strategist = vm.addr(0xBEEF);

    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    ERC20 private LP3CRV = ERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    IBooster private booster = IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ICurvePool curve3Pool = ICurvePool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);

    uint256 private constant PID_3CRV = 9;

    IRewardPool rewardPool;

    uint32 private lp3crvPosition;
    uint32 private daiPosition;

    function setUp() external {

        convexAdaptor = new ConvexAdaptor();
        erc20Adaptor = new ERC20Adaptor();
        priceRouter = new PriceRouter();

        registry = new Registry(address(this), address(swapRouter), address(priceRouter));

        priceRouter.addAsset(DAI, 0, 0, false, 0);
        priceRouter.addAsset(USDT, 0, 0, false, 0);
        priceRouter.addAsset(USDC, 0, 0, false, 0);

        // Setup Cellar:
        // Cellar positions array.
        uint32[] memory positions = new uint32[](2);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(convexAdaptor), 0, 0);
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);

        daiPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(DAI), 0, 0);
        lp3crvPosition = registry.trustPosition(address(convexAdaptor), false, abi.encode(PID_3CRV, address(DAI), curve3Pool), 0, 0);

        positions[0] = daiPosition;
        positions[1] = lp3crvPosition;
        
        bytes[] memory positionConfigs = new bytes[](2);

        cellar = new MockCellar(registry, DAI, positions, positionConfigs, "Convex Cellar", "CONVEX-CLR", strategist);
        
        vm.label(address(curve3Pool), "curve pool");
        vm.label(address(convexAdaptor), "convexAdaptor");
        vm.label(address(this), "tester");
        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");
        vm.label(address(DAI), "dai token");
        vm.label(address(USDC), "usdc token");
        vm.label(address(USDT), "usdt token");

        cellar.setupAdaptor(address(convexAdaptor));

        DAI.safeApprove(address(cellar), type(uint256).max);
        USDC.safeApprove(address(cellar), type(uint128).max);
        USDT.safeApprove(address(cellar), type(uint128).max);

        // get initialize reward pool
        (, , ,address rp, ,) = booster.poolInfo(PID_3CRV);
        rewardPool = IRewardPool(rp);

        console.logAddress(rp);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testFaucet() external {
        uint256 amount = 100e18;
        deal(address(DAI), address(this), amount);
        assertEq(
            DAI.balanceOf(address(this)),
            amount,
            "Should be able to deal some tokens"
        );
    }

    function testOpenPosition() external {
        deal(address(LP3CRV), address(cellar), 100_000e18);
        // deal(address(DAI), address(cellar), 1e18);

        vm.prank(address(cellar));
        console.log(convexAdaptor.balanceOf(abi.encode(PID_3CRV, LP3CRV, curve3Pool)));

        // Use `callOnAdaptor` to deposit LP into curve pool
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToOpenPosition(
            PID_3CRV, 
            1e18, 
            LP3CRV
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(convexAdaptor), callData: adaptorCalls });

        cellar.callOnAdaptor(data);


        vm.prank(address(cellar));
        console.log(convexAdaptor.balanceOf(abi.encode(PID_3CRV, LP3CRV, curve3Pool)));
    }

    function _createBytesDataToOpenPosition(
        uint256 pid,
        uint256 amount,
        ERC20 lpToken
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                ConvexAdaptor.openPosition.selector,
                pid, 
                amount,
                lpToken
            );
    }

    function _createBytesDataToAddToPosition(
        uint256 pid,
        uint256 amount,
        ERC20 lpToken
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                ConvexAdaptor.addToPosition.selector,
                pid,
                amount, 
                lpToken
        );
    }

    function _createBytesDataToClosePosition(
        uint256 pid
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                ConvexAdaptor.closePosition.selector,
                pid
            );
    }

    function _createBytesDataToTakeFromPosition(
        uint256 pid,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                ConvexAdaptor.takeFromPosition.selector,
                pid,
                amount
            );
    }



}
