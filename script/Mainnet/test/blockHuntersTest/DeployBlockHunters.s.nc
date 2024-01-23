// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { TEnv } from "script/test/TEnv.sol";
import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import {  IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken, IEulerDToken } from "src/interfaces/external/IEuler.sol";

import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

// Import adaptors.
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
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

    function run() external {
        uint32[] memory positions = new uint32[](6);
        uint32[] memory debtPositions;
        bytes[] memory positionConfigs = new bytes[](6);
        bytes[] memory debtConfigs;
        aaveV3ATokenAdaptor = AaveV3ATokenAdaptor(0x4E19245459A74490de144caEFE724aA3521338E4);

        vm.startBroadcast();

        // Add assets to price router.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(AAVE_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, AAVE_USD_FEED);
        priceRouter.addAsset(AAVE, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(CRV_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CRV_USD_FEED);
        priceRouter.addAsset(CRV, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(UNI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, UNI_USD_FEED);
        priceRouter.addAsset(UNI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(COMP_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, COMP_USD_FEED);
        priceRouter.addAsset(COMP, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(MKR_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, MKR_USD_FEED);
        priceRouter.addAsset(MKR, settings, abi.encode(stor), price);

        // registry.trustAdaptor(address(erc20Adaptor), 0, 0);

        positions[0] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aUSDCV3)));
        positions[1] = registry.trustPosition(address(erc20Adaptor), abi.encode(address(AAVE)));
        positions[2] = registry.trustPosition(address(erc20Adaptor), abi.encode(address(CRV)));
        positions[3] = registry.trustPosition(address(erc20Adaptor), abi.encode(address(UNI)));
        positions[4] = registry.trustPosition(address(erc20Adaptor), abi.encode(address(COMP)));
        positions[5] = registry.trustPosition(address(erc20Adaptor), abi.encode(address(MKR)));

        positionConfigs[0] = abi.encode(1.1e18);

        // Deploy cellar using factory.
        bytes memory initializeCallData = abi.encode(
            devOwner,
            registry,
            USDC,
            "TEST Cellar",
            "TEST",
            abi.encode(
                positions,
                debtPositions,
                positionConfigs,
                debtConfigs,
                positions[0],
                strategist,
                type(uint128).max,
                type(uint128).max
            )
        );
        address implementation = factory.getImplementation(2, 0);
        require(implementation != address(0), "Invalid implementation");

        address clone = factory.deploy(2, 0, initializeCallData, USDC, 0, keccak256(abi.encode(block.timestamp)));
        cellar = CellarInitializableV2_1(clone);

        // Setup all the adaptors the cellar will use.
        cellar.addAdaptorToCatalogue(address(aaveV3ATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(feesAndReservesAdaptor));
        cellar.addAdaptorToCatalogue(address(zeroXAdaptor));

        cellar.transferOwnership(strategist);

        vm.stopBroadcast();
    }
}
