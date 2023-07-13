// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract FeesAndReservesTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    FeesAndReserves private feesAndReserves;

    address private cosmos = vm.addr(10);
    address private strategist = vm.addr(11);

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address private automationRegistry = 0x02777053d6764996e594c3E88AF1D58D5363a2e6;
    address private fastGasFeed = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    // Values used to mimic cellar interface between test contract and FeesAndReserves.
    ERC20 public asset;
    uint8 public decimals = 18;
    Registry public registry;
    uint256 public totalAssets;
    uint256 public totalSupply;

    function feeData()
        public
        view
        returns (uint64 strategistPlatformCut, uint64 platformFee, uint64 lastAccrual, address strategistPayoutAddress)
    {
        return (0.8e18, 0, 0, strategist);
    }

    function setUp() external {
        registry = new Registry(address(this), address(this), address(this));
        feesAndReserves = new FeesAndReserves(address(this), automationRegistry, fastGasFeed);

        // Set this testing contracts `asset` to be USDC.
        asset = USDC;
    }

    function testMaliciousCallerChangingReserveAsset() external {
        feesAndReserves.setupMetaData(0.05e4, 0.2e4);
        feesAndReserves.changeUpkeepMaxGas(100e9);
        feesAndReserves.changeUpkeepFrequency(3_600);

        Cellar[] memory cellars = new Cellar[](1);
        cellars[0] = Cellar(address(this));
        totalAssets = 100e18;
        totalSupply = 100e18;
        (bool upkeepNeeded, bytes memory performData) = feesAndReserves.checkUpkeep(abi.encode(cellars));
        feesAndReserves.performUpkeep(performData);

        vm.warp(block.timestamp + 3_600);

        // Add assets to reserves.
        deal(address(USDC), address(this), 100e6);
        USDC.approve(address(feesAndReserves), 100e6);
        feesAndReserves.addAssetsToReserves(100e6);

        // Change asset to WETH.
        asset = WETH;

        // Try removing assets to take WETH from FeesAndReserves.
        feesAndReserves.withdrawAssetsFromReserves(100e6);

        assertEq(WETH.balanceOf(address(this)), 0, "Test contract should have no WETH.");
        assertEq(USDC.balanceOf(address(this)), 100e6, "Test contract should have original USDC balance.");

        // Withdrawing more assets should revert.
        vm.expectRevert(bytes(abi.encodeWithSelector(FeesAndReserves.FeesAndReserves__NotEnoughReserves.selector)));
        feesAndReserves.withdrawAssetsFromReserves(1);

        // Adjust totalAssets so that FeesAndReserves thinks there are performance fees owed.
        totalAssets = 200e18;
        vm.warp(block.timestamp + 365 days);

        (upkeepNeeded, performData) = feesAndReserves.checkUpkeep(abi.encode(cellars));
        assertEq(upkeepNeeded, true, "Upkeep should be needed.");
        feesAndReserves.performUpkeep(performData);

        // Add some assets to reserves.
        deal(address(USDC), address(this), 100e6);
        USDC.approve(address(feesAndReserves), 100e6);
        feesAndReserves.addAssetsToReserves(100e6);

        // Prepare fees.
        feesAndReserves.prepareFees(1e6);

        feesAndReserves.sendFees(Cellar(address(this)));

        // Strategist should have recieved USDC.
        assertGt(USDC.balanceOf(strategist), 0, "Strategist should have got USDC from performance fees.");

        // Even though caller maliciously changed their `asset`, FeesAndReserves did not use the new asset, it used the asset stored when `setupMetaData` was called.
    }

    // ========================================= GRAVITY FUNCTIONS =========================================

    // Since this contract is set as the Gravity Bridge, this will be called by
    // the Cellar's `sendFees` function to send funds Cosmos.
    function sendToCosmos(address token, bytes32, uint256 tokens) external {
        ERC20(token).transferFrom(msg.sender, cosmos, tokens);
    }
}
