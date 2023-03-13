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
 *      `source .env && forge script script/test/realYieldEthTest/DeployRealYieldEth.s.sol:DeployRealYieldEthScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployRealYieldEthScript is Script, TEnv {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    CellarInitializableV2_1 private cellar;
    FeesAndReserves private far;
    UniswapV3PositionTracker private tracker;

    IEulerMarkets private markets = IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    address private euler = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    IEulerExec private exec = IEulerExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);

    IEulerEToken private eWETH;
    IEulerDToken private dWETH;
    IEulerEToken private eCBETH;
    IEulerDToken private dCBETH;
    IEulerEToken private eRETH;
    IEulerDToken private dRETH;

    // Define Adaptors.
    EulerETokenAdaptor private eulerETokenAdaptor;
    EulerDebtTokenAdaptor private eulerDebtTokenAdaptor;
    FeesAndReservesAdaptor private feesAndReservesAdaptor;
    AaveATokenAdaptor private aaveATokenAdaptor;
    UniswapV3Adaptor private uniswapV3Adaptor;

    // ZeroXAdaptor private zeroXAdaptor;

    function run() external {
        eWETH = IEulerEToken(markets.underlyingToEToken(address(WETH)));
        dWETH = IEulerDToken(markets.underlyingToDToken(address(WETH)));
        eCBETH = IEulerEToken(markets.underlyingToEToken(address(cbETH)));
        dCBETH = IEulerDToken(markets.underlyingToDToken(address(cbETH)));
        eRETH = IEulerEToken(markets.underlyingToEToken(address(rETH)));
        dRETH = IEulerDToken(markets.underlyingToDToken(address(rETH)));

        uint32[] memory positions = new uint32[](10);
        uint32[] memory debtPositions = new uint32[](3);
        bytes[] memory positionConfigs = new bytes[](10);
        bytes[] memory debtConfigs = new bytes[](3);

        vm.startBroadcast();

        // Add cbETH and rETH to price router.
        // PriceRouter.ChainlinkDerivativeStorage memory stor;
        // PriceRouter.AssetSettings memory settings;
        // uint256 price = uint256(IChainlinkAggregator(CBETH_ETH_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CBETH_ETH_FEED);
        // priceRouter.addAsset(cbETH, settings, abi.encode(stor), price);

        // price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        // priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        // far = new FeesAndReserves(registry);
        // tracker = new UniswapV3PositionTracker(positionManager);

        // Deploy new adaptors.
        eulerETokenAdaptor = new EulerETokenAdaptor();
        eulerDebtTokenAdaptor = new EulerDebtTokenAdaptor();
        feesAndReservesAdaptor = new FeesAndReservesAdaptor();
        aaveATokenAdaptor = new AaveATokenAdaptor();
        uniswapV3Adaptor = new UniswapV3Adaptor();
        zeroXAdaptor = new ZeroXAdaptor();

        // Setup new registry positions.
        registry.trustAdaptor(address(eulerETokenAdaptor), 0, 0);
        registry.trustAdaptor(address(eulerDebtTokenAdaptor), 0, 0);
        registry.trustAdaptor(address(feesAndReservesAdaptor), 0, 0);
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);
        registry.trustAdaptor(address(aaveATokenAdaptor), 0, 0);
        registry.trustAdaptor(address(uniswapV3Adaptor), 0, 0);
        registry.trustAdaptor(address(zeroXAdaptor), 0, 0);

        // Cellar positions array.
        positions[0] = registry.trustPosition(address(erc20Adaptor), abi.encode(cbETH), 0, 0);
        positions[1] = registry.trustPosition(address(erc20Adaptor), abi.encode(rETH), 0, 0);
        positions[2] = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH), 0, 0);
        positions[3] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aWETH)), 0, 0);
        positions[4] = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eWETH, 0), 0, 0);
        positions[5] = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eWETH, 1), 0, 0);
        positions[6] = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eCBETH, 1), 0, 0);
        positions[7] = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eRETH, 1), 0, 0);
        positions[8] = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(cbETH, WETH), 0, 0);
        positions[9] = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(rETH, WETH), 0, 0);

        uint32 debtWethPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dWETH, 1), 0, 0);
        uint32 debtCBethPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dCBETH, 1), 0, 0);
        uint32 debtRethPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dRETH, 1), 0, 0);

        positionConfigs[3] = abi.encode(1.1e18);

        debtPositions[0] = debtWethPosition;
        debtPositions[1] = debtCBethPosition;
        debtPositions[2] = debtRethPosition;

        // Deploy cellar using factory.
        bytes memory initializeCallData = abi.encode(
            devOwner,
            registry,
            WETH,
            "TEST Cellar",
            "TEST",
            abi.encode(
                positions,
                debtPositions,
                positionConfigs,
                debtConfigs,
                positions[5],
                strategist,
                type(uint128).max,
                type(uint128).max
            )
        );
        address implementation = factory.getImplementation(2, 0);
        require(implementation != address(0), "Invalid implementation");

        address clone = factory.deploy(2, 0, initializeCallData, WETH, 0, keccak256(abi.encode(block.timestamp)));
        cellar = CellarInitializableV2_1(clone);

        // Setup all the adaptors the cellar will use.
        cellar.setupAdaptor(address(eulerETokenAdaptor));
        cellar.setupAdaptor(address(eulerDebtTokenAdaptor));
        cellar.setupAdaptor(address(feesAndReservesAdaptor));
        cellar.setupAdaptor(address(aaveATokenAdaptor));
        cellar.setupAdaptor(address(uniswapV3Adaptor));
        cellar.setupAdaptor(address(zeroXAdaptor));

        // cellar.transferOwnership(strategist);

        vm.stopBroadcast();
    }
}
