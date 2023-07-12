// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib, PriceRouter } from "src/base/Cellar.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// Import adaptors.
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract TimelockTest is Test {
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private otherDevAddress = 0xF3De89fAD937c11e770Bc6291cb5E04d8784aE0C;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;

    TimelockController private controller = TimelockController(payable(0xaDa78a5E01325B91Bc7879a63c309F7D54d42950));

    IUniswapV3Factory internal factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    Cellar private cellar = Cellar(0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E);
    PriceRouter private priceRouter;
    Registry private registry;
    UniswapV3Adaptor private uniswapV3Adaptor = UniswapV3Adaptor(0xDbd750F72a00d01f209FFc6C75e80301eFc789C1);

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    function setUp() external {}

    function testTimelock() external {
        if (block.number < 16828469) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16828469.");
            return;
        }

        registry = cellar.registry();
        priceRouter = PriceRouter(registry.getAddress(2));

        vm.startPrank(devOwner);
        controller.schedule(
            address(registry),
            0,
            abi.encodeWithSelector(Ownable.transferOwnership.selector, address(devOwner)),
            hex"00",
            hex"00",
            3 days
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 3 days);

        vm.startPrank(multisig);
        controller.execute(
            address(registry),
            0,
            abi.encodeWithSelector(Ownable.transferOwnership.selector, address(devOwner)),
            hex"00",
            hex"00"
        );
        vm.stopPrank();

        assertEq(registry.owner(), devOwner, "Owner should be dev");

        vm.prank(devOwner);
        registry.transferOwnership(address(controller));

        vm.startPrank(otherDevAddress);
        controller.schedule(
            address(registry),
            0,
            abi.encodeWithSelector(Ownable.transferOwnership.selector, address(otherDevAddress)),
            hex"00",
            hex"00",
            7 days
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        vm.startPrank(multisig);
        controller.execute(
            address(registry),
            0,
            abi.encodeWithSelector(Ownable.transferOwnership.selector, address(otherDevAddress)),
            hex"00",
            hex"00"
        );
        vm.stopPrank();

        assertEq(registry.owner(), otherDevAddress, "Owner should be other dev");
    }
}
