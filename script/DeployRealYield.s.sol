// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializable } from "src/base/CellarInitializable.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";

// Import adaptors.
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/UniSwap/UniswapV3Adaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { CTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

// Import Compound helpers.
import { CErc20 } from "@compound/CErc20.sol";
import { ComptrollerG7 as Comptroller } from "@compound/ComptrollerG7.sol";

// Import Aave helpers.
import { IPool } from "src/interfaces/external/IPool.sol";

// Import UniV3 helpers.
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/UltimateStablecoinCellar.s.sol:UltimateStablecoinCellarScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 10000000000 --verify --etherscan-api-key $ETHERSCAN_KEY`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract UltimateStablecoinCellarScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private strategist = 0x97238B45C626a4CA4C99E7Eb34e2DAD5e5107D32;
    address private deployer = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    CellarFactory private factory;
    CellarInitializable private cellar;

    PriceRouter private priceRouter;
    SwapRouter private swapRouter;
    VestingSimple private usdcVestor;

    Registry private registry;

    address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IUniswapV3Factory internal v3factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    Comptroller private comptroller = Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 private COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private aUSDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    ERC20 private dUSDC = ERC20(0x619beb58998eD2278e08620f97007e1116D5D25b);
    ERC20 private aDAI = ERC20(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
    ERC20 private dDAI = ERC20(0x6C3c78838c761c6Ac7bE9F59fe808ea2A6E4379d);
    ERC20 private aUSDT = ERC20(0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811);
    ERC20 private dUSDT = ERC20(0x531842cEbbdD378f8ee36D171d6cC9C4fcf475Ec);
    CErc20 private cUSDC = CErc20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    CErc20 private cDAI = CErc20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    CErc20 private cUSDT = CErc20(0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9);

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor;
    UniswapV3Adaptor private uniswapV3Adaptor;
    AaveATokenAdaptor private aaveATokenAdaptor;
    AaveDebtTokenAdaptor private aaveDebtTokenAdaptor;
    CTokenAdaptor private cTokenAdaptor;
    VestingSimpleAdaptor private vestingAdaptor;

    // Base positions.
    uint32 private usdcPosition = 1;
    uint32 private daiPosition = 2;
    uint32 private usdtPosition = 3;

    // Uniswap V3 positions.
    uint32 private usdcDaiPosition = 4;
    uint32 private usdcUsdtPosition = 5;

    // Aave positions.
    uint32 private aUSDCPosition = 6;
    uint32 private aDAIPosition = 7;
    uint32 private aUSDTPosition = 8;

    // Compound positions.
    uint32 private cUSDCPosition = 9;
    uint32 private cDAIPosition = 10;
    uint32 private cUSDTPosition = 11;

    // Vesting positions.
    uint32 private vUSDCPosition = 12;

    function run() external {
        vm.startBroadcast();

        // Cellar positions array.
        uint32[] memory positions = new uint32[](12);
        uint32[] memory debtPositions;

        positions[0] = vUSDCPosition;
        positions[1] = usdcPosition;
        positions[2] = daiPosition;
        positions[3] = usdtPosition;
        positions[4] = aUSDCPosition;
        positions[5] = aDAIPosition;
        positions[6] = aUSDTPosition;
        positions[7] = cUSDCPosition;
        positions[8] = cDAIPosition;
        positions[9] = cUSDTPosition;
        positions[10] = usdcDaiPosition;
        positions[11] = usdcUsdtPosition;

        bytes[] memory positionConfigs = new bytes[](12);
        bytes[] memory debtConfigs;

        uint256 minHealthFactor = 1.2e18;
        positionConfigs[4] = abi.encode(minHealthFactor);

        // Deploy cellar using factory.
        bytes memory initializeCallData = abi.encode(
            registry,
            USDC,
            "Real Yield USD",
            "TEST-USC-CLR", // TODO need this
            abi.encode(
                positions,
                debtPositions,
                positionConfigs,
                debtConfigs,
                aUSDCPosition,
                strategist, //TODO need this
                type(uint128).max,
                type(uint128).max
            )
        );

        address clone = factory.deploy(2, 0, initializeCallData, USDC, 0, keccak256(abi.encode(2)));
        cellar = CellarInitializable(clone);

        // Setup all the adaptors the cellar will use.
        // cellar.setupAdaptor(address(uniswapV3Adaptor));
        // cellar.setupAdaptor(address(aaveATokenAdaptor));
        // cellar.setupAdaptor(address(cTokenAdaptor));
        // cellar.setupAdaptor(address(vestingAdaptor));

        vm.stopBroadcast();
    }
}
