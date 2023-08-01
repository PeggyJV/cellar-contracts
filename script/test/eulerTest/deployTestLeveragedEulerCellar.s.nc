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
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";

// Import adaptors.
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { EulerETokenAdaptor } from "src/modules/adaptors/Euler/EulerETokenAdaptor.sol";
import { EulerDebtTokenAdaptor } from "src/modules/adaptors/Euler/EulerDebtTokenAdaptor.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/test/eulerTest/DeployTestLeveragedEulerCellar.s.sol:DeployTestLeveragedEulerCellarScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployTestLeveragedEulerCellarScript is Script, TEnv {
  using SafeTransferLib for ERC20;
  using Math for uint256;

  CellarInitializableV2_1 private cellar;
  FeesAndReserves private far;

  IEulerMarkets private markets = IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
  address private euler = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
  IEulerExec private exec = IEulerExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);

  IEulerEToken private eWETH;

  // IEulerDToken private dWETH;

  // Define Adaptors.
  EulerETokenAdaptor private eulerETokenAdaptor;
  EulerDebtTokenAdaptor private eulerDebtTokenAdaptor;
  FeesAndReservesAdaptor private feesAndReservesAdaptor;

  function run() external {
    PriceRouter.ChainlinkDerivativeStorage memory stor;
    PriceRouter.AssetSettings memory settings;
    uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
    settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);

    eWETH = IEulerEToken(markets.underlyingToEToken(address(WETH)));
    dWETH = IEulerDToken(markets.underlyingToDToken(address(WETH)));

    uint32[] memory positions = new uint32[](2);
    uint32[] memory debtPositions = new uint32[](1);
    bytes[] memory positionConfigs = new bytes[](2);
    bytes[] memory debtConfigs = new bytes[](1);

    vm.startBroadcast();

    // Deploy new contracts.
    far = new FeesAndReserves(registry);

    // Setup price feeds.
    priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

    // Deploy new adaptors.
    eulerETokenAdaptor = new EulerETokenAdaptor();
    eulerDebtTokenAdaptor = new EulerDebtTokenAdaptor();
    feesAndReservesAdaptor = new FeesAndReservesAdaptor();

    // Setup new registry positions.
    registry.trustAdaptor(address(eulerETokenAdaptor));
    registry.trustAdaptor(address(eulerDebtTokenAdaptor));
    registry.trustAdaptor(address(feesAndReservesAdaptor));
    uint32 eWethPositionV2 = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eWETH, 0));
    uint32 eWethLiquidPositionV2 = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eWETH, 1));
    uint32 debtWethPositionV2 = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dWETH, 0));

    // Cellar positions array.
    positions[0] = eWethLiquidPositionV2;
    positions[1] = eWethPositionV2;
    debtPositions[0] = debtWethPositionV2;

    // Deploy cellar using factory.
    bytes memory initializeCallData = abi.encode(
      devOwner,
      registry,
      WETH,
      "TEST Euler Cellar",
      "TEST-EC",
      abi.encode(
        positions,
        debtPositions,
        positionConfigs,
        debtConfigs,
        eWethPositionV2,
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
    cellar.addAdaptorToCatalogue(address(eulerETokenAdaptor));
    cellar.addAdaptorToCatalogue(address(eulerDebtTokenAdaptor));
    cellar.addAdaptorToCatalogue(address(feesAndReservesAdaptor));

    cellar.transferOwnership(strategist);

    vm.stopBroadcast();
  }
}
