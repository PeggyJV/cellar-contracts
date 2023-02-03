// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken, IEulerDToken } from "src/interfaces/external/IEuler.sol";

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
 *      `source .env && forge script script/eulerTest/DeployTestLeveragedEulerCellar.s.sol:DeployTestLeveragedEulerCellarScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployTestLeveragedEulerCellarScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    CellarFactory private factory = CellarFactory(0xFCed747657ACfFc6FAfacD606E17D0988EDf3Fd9);
    Registry private registry = Registry(0xd1c18363F81d8E6260511b38FcF1e8b710E7e31D);

    CellarInitializableV2_1 private cellar;

    IEulerMarkets private markets = IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    address private euler = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    IEulerExec private exec = IEulerExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    IEulerEToken private eUSDC;
    IEulerEToken private eDAI;
    IEulerEToken private eUSDT;

    IEulerDToken private dUSDC;
    IEulerDToken private dDAI;
    IEulerDToken private dUSDT;

    // Define Adaptors.
    EulerETokenAdaptor private eulerETokenAdaptor = EulerETokenAdaptor(0x7291960D1E14a4369bcB26Df31077D7637491C81);
    EulerDebtTokenAdaptor private eulerDebtTokenAdaptor =
        EulerDebtTokenAdaptor(0xB079D4CcF8557b0dD9Ab829eEDb62FA70fEB1B38);

    // Chainlink PriceFeeds
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

    // Euler positions.
    uint32 private eUsdcPosition = 1;
    uint32 private eDaiPosition = 2;
    uint32 private eUsdtPosition = 3;
    uint32 private eUsdcLiquidPosition = 4;
    uint32 private eDaiLiquidPosition = 5;
    uint32 private eUsdtLiquidPosition = 6;
    uint32 private debtUsdcPosition;
    uint32 private debtDaiPosition;
    uint32 private debtUsdtPosition;

    function run() external {
        vm.startBroadcast();

        eUSDC = IEulerEToken(markets.underlyingToEToken(address(USDC)));
        eDAI = IEulerEToken(markets.underlyingToEToken(address(DAI)));
        eUSDT = IEulerEToken(markets.underlyingToEToken(address(USDT)));

        dUSDC = IEulerDToken(markets.underlyingToDToken(address(USDC)));
        dDAI = IEulerDToken(markets.underlyingToDToken(address(DAI)));
        dUSDT = IEulerDToken(markets.underlyingToDToken(address(USDT)));

        debtUsdcPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dUSDC, 0), 0, 0);
        debtDaiPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dDAI, 0), 0, 0);
        debtUsdtPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dUSDT, 0), 0, 0);

        // Cellar positions array.
        uint32[] memory positions = new uint32[](2);
        uint32[] memory debtPositions = new uint32[](1);

        positions[0] = eUsdcLiquidPosition;
        positions[1] = eUsdcPosition;

        debtPositions[0] = debtUsdcPosition;

        bytes[] memory positionConfigs = new bytes[](2);
        bytes[] memory debtConfigs = new bytes[](1);

        // Deploy cellar using factory.
        bytes memory initializeCallData = abi.encode(
            devOwner,
            registry,
            USDC,
            "Euler Leveraged USDC",
            "EL-USDC",
            abi.encode(
                positions,
                debtPositions,
                positionConfigs,
                debtConfigs,
                eUsdcPosition,
                strategist,
                type(uint128).max,
                type(uint128).max
            )
        );
        address clone = factory.deploy(2, 0, initializeCallData, USDC, 0, keccak256(abi.encode(2)));
        cellar = CellarInitializableV2_1(clone);

        // Setup all the adaptors the cellar will use.
        cellar.setupAdaptor(address(eulerETokenAdaptor));
        cellar.setupAdaptor(address(eulerDebtTokenAdaptor));

        cellar.transferOwnership(strategist);

        vm.stopBroadcast();
    }
}
