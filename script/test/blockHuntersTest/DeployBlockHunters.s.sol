// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { TEnv } from "script/test/TEnv.sol";
import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken, IEulerDToken } from "src/interfaces/external/IEuler.sol";

import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

// Import adaptors.
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/UniSwap/UniswapV3Adaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import { EulerETokenAdaptor } from "src/modules/adaptors/Euler/EulerETokenAdaptor.sol";
import { EulerDebtTokenAdaptor } from "src/modules/adaptors/Euler/EulerDebtTokenAdaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/test/blockHuntersTest/DeployBlockHunters.s.sol:DeployBlockHuntersScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployBlockHuntersScript is Script, TEnv {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    CellarInitializableV2_1 private cellar = CellarInitializableV2_1(0x7fE3F487eb7d36069c61F53FE4Ba777C2DE75B43);

    // Define Adaptors.
    AaveV3ATokenAdaptor private aaveV3ATokenAdaptor;
    AaveV3DebtTokenAdaptor private aaveV3DebtTokenAdaptor;

    function run() external {
        // uint32[] memory positions = new uint32[](3);
        // uint32[] memory debtPositions = new uint32[](3);
        // bytes[] memory positionConfigs = new bytes[](3);
        // bytes[] memory debtConfigs = new bytes[](3);

        vm.startBroadcast();

        // Deploy new adaptors.
        // feesAndReservesAdaptor = FeesAndReservesAdaptor(0xf260a0caD298BBB1b90c8D3EE24Ac896Ada65fA5);
        // aaveATokenAdaptor = AaveATokenAdaptor(0x3Dd3E51f1a1cD0E6767B5b2d939E8AAFdFcB20F3);
        // uniswapV3Adaptor = UniswapV3Adaptor(0x5038A79F9680E7Ca200EB7162CF374bce741a8f4);
        // zeroXAdaptor = ZeroXAdaptor(0x1bd161EF8EE43E72Ce8CfB156c2cA4f64E49c086);

        aaveV3ATokenAdaptor = new AaveV3ATokenAdaptor();
        aaveV3DebtTokenAdaptor = new AaveV3DebtTokenAdaptor();

        registry.trustAdaptor(address(aaveV3ATokenAdaptor), 0, 0);
        registry.trustAdaptor(address(aaveV3DebtTokenAdaptor), 0, 0);

        registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aWETH)), 0, 0);
        registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aRETH)), 0, 0);
        registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aCBETH)), 0, 0);

        registry.trustPosition(address(aaveV3DebtTokenAdaptor), abi.encode(address(dWETH)), 0, 0);
        registry.trustPosition(address(aaveV3DebtTokenAdaptor), abi.encode(address(dRETH)), 0, 0);
        registry.trustPosition(address(aaveV3DebtTokenAdaptor), abi.encode(address(dCBETH)), 0, 0);

        // Deploy cellar using factory.
        // bytes memory initializeCallData = abi.encode(
        //     devOwner,
        //     registry,
        //     WETH,
        //     "TEST Cellar",
        //     "TEST",
        //     abi.encode(
        //         positions,
        //         debtPositions,
        //         positionConfigs,
        //         debtConfigs,
        //         positions[3],
        //         strategist,
        //         type(uint128).max,
        //         type(uint128).max
        //     )
        // );
        // address implementation = factory.getImplementation(2, 0);
        // require(implementation != address(0), "Invalid implementation");

        // address clone = factory.deploy(2, 0, initializeCallData, WETH, 0, keccak256(abi.encode(block.timestamp)));
        // cellar = CellarInitializableV2_1(clone);

        // Setup all the adaptors the cellar will use.
        // cellar.setupAdaptor(address(feesAndReservesAdaptor));
        // cellar.setupAdaptor(address(aaveATokenAdaptor));
        // cellar.setupAdaptor(address(uniswapV3Adaptor));
        // cellar.setupAdaptor(address(zeroXAdaptor));

        // cellar.transferOwnership(strategist);

        // Add cbETH and rETH to price router.
        // PriceRouter.ChainlinkDerivativeStorage memory stor;
        // stor.inETH = true;
        // PriceRouter.AssetSettings memory settings;
        // uint256 price = uint256(IChainlinkAggregator(CBETH_ETH_FEED).latestAnswer());
        // price = price.mulDivDown(1656e8, 1e18);
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CBETH_ETH_FEED);
        // priceRouter.addAsset(cbETH, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        // price = price.mulDivDown(1656e8, 1e18);
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        // priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        vm.stopBroadcast();
    }
}
