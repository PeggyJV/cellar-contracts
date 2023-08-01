// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { TEnv } from "script/test/TEnv.sol";
import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import {  IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { IPool } from "src/interfaces/external/IPool.sol";

import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

// Import adaptors.
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { CTokenAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import { OneInchAdaptor } from "src/modules/adaptors/OneInch/OneInchAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/RealYieldEth/DeployRealYieldEth.s.sol:DeployRealYieldEthScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployRealYieldEthScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public cbETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    ERC20 public rETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);
    ERC20 public stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    // Compound positions
    CErc20 private cWETH = CErc20(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);

    // Aave V2 Positions.
    ERC20 public aV2WETH = ERC20(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e);
    ERC20 public dV2WETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);
    ERC20 public aV2STETH = ERC20(0x1982b2F5814301d4e9a8b0201555376e62F82428);

    // Aave V3 positions.
    ERC20 public aV3WETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 public dV3WETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);
    ERC20 public aV3CBETH = ERC20(0x977b6fc5dE62598B08C85AC8Cf2b745874E8b78c);
    ERC20 public dV3CBETH = ERC20(0x0c91bcA95b5FE69164cE583A2ec9429A569798Ed);
    ERC20 public aV3RETH = ERC20(0xCc9EE9483f662091a1de4795249E24aC0aC2630f);
    ERC20 public dV3RETH = ERC20(0xae8593DD575FE29A9745056aA91C4b746eee62C8);

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    CellarInitializableV2_2 private cellar;

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    CellarFactory private factory = CellarFactory(0x9D30672eED8D514cD1ad009Cfe85Ea8f0019D37F);
    SwapRouter private swapRouter = SwapRouter(0x070f43E613B33aD3EFC6B2928f3C01d58D032020);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    FeesAndReserves private feesAndReserves = FeesAndReserves(0xF4279E93a06F9d4b5d0625b1F471AA99Ef9B686b);
    UniswapV3PositionTracker private tracker = UniswapV3PositionTracker(0xf2854d84D9Dd27eCcD6aB20b3F66111a51bb56d2);
    VestingSimple private wethVestor;

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor;
    FeesAndReservesAdaptor private feesAndReservesAdaptor;
    CTokenAdaptor private cTokenAdaptor;
    AaveATokenAdaptor private aaveATokenAdaptor;
    AaveDebtTokenAdaptor private aaveDebtTokenAdaptor;
    AaveV3ATokenAdaptor private aaveV3ATokenAdaptor;
    AaveV3DebtTokenAdaptor private aaveV3DebtTokenAdaptor;
    UniswapV3Adaptor private uniswapV3Adaptor;
    ZeroXAdaptor private zeroXAdaptor;
    SwapWithUniswapAdaptor private swapWithUniswapAdaptor;
    OneInchAdaptor private oneInchAdaptor;
    VestingSimpleAdaptor private vestingSimpleAdaptor;

    address public oldATokenAdaptor = 0x25570a77dCA06fda89C1ef41FAb6eE48a2377E81;
    address public oldDebtTokenAdaptor = 0x5F4e81E1BC9D7074Fc30aa697855bE4e1AA16F0b;

    function run() external {
        vm.startBroadcast();

        // cTokenAdaptor = new CTokenAdaptor();

        // // Deploy Supporting contracts
        // wethVestor = new VestingSimple(WETH, 3 days, 0.001e18);

        // // Deploy adaptors.
        // uniswapV3Adaptor = new UniswapV3Adaptor();
        // feesAndReservesAdaptor = new FeesAndReservesAdaptor();

        // erc20Adaptor = new ERC20Adaptor();
        aaveATokenAdaptor = new AaveATokenAdaptor(address(pool), address(WETH), 1.05e18);
        aaveDebtTokenAdaptor = new AaveDebtTokenAdaptor(address(pool), 1.05e18);
        // aaveV3ATokenAdaptor = new AaveV3ATokenAdaptor();
        // aaveV3DebtTokenAdaptor = new AaveV3DebtTokenAdaptor();
        // zeroXAdaptor = new ZeroXAdaptor();
        // swapWithUniswapAdaptor = new SwapWithUniswapAdaptor();
        // oneInchAdaptor = new OneInchAdaptor();
        // vestingSimpleAdaptor = new VestingSimpleAdaptor();

        // // Trust all adaptors.
        // registry.trustAdaptor(address(uniswapV3Adaptor));
        // registry.trustAdaptor(address(feesAndReservesAdaptor));
        // registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(aaveATokenAdaptor));
        registry.trustAdaptor(address(aaveDebtTokenAdaptor));
        // registry.trustAdaptor(address(aaveV3ATokenAdaptor));
        // registry.trustAdaptor(address(aaveV3DebtTokenAdaptor));
        // registry.trustAdaptor(address(zeroXAdaptor));
        // registry.trustAdaptor(address(swapWithUniswapAdaptor));
        // registry.trustAdaptor(address(oneInchAdaptor));
        // registry.trustAdaptor(address(vestingSimpleAdaptor));

        // Distrust old positions and adaptors.
        registry.distrustAdaptor(oldATokenAdaptor);
        registry.distrustAdaptor(oldDebtTokenAdaptor);
        registry.distrustPosition(105);
        registry.distrustPosition(106);
        registry.distrustPosition(113);

        uint32[] memory positionIds = new uint32[](16);

        // // Add Positions to registry.
        // // credit positions
        // positionIds[0] = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));
        // positionIds[1] = registry.trustPosition(address(erc20Adaptor), abi.encode(cbETH));
        // positionIds[2] = registry.trustPosition(address(erc20Adaptor), abi.encode(rETH));
        // positionIds[3] = registry.trustPosition(address(erc20Adaptor), abi.encode(stETH));
        positionIds[4] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aV2WETH)));
        positionIds[5] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aV2STETH)));
        // positionIds[6] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aV3WETH)));
        // positionIds[7] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aV3RETH)));
        // positionIds[8] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aV3CBETH)));
        // positionIds[9] = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(cbETH, WETH));
        // positionIds[10] = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(rETH, WETH));
        // positionIds[11] = registry.trustPosition(address(vestingSimpleAdaptor), abi.encode(wethVestor));

        // // debt positions
        positionIds[12] = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dV2WETH)));
        // positionIds[13] = registry.trustPosition(address(aaveV3DebtTokenAdaptor), abi.encode(address(dV3WETH)));
        // positionIds[14] = registry.trustPosition(address(aaveV3DebtTokenAdaptor), abi.encode(address(dV3RETH)));
        // positionIds[15] = registry.trustPosition(address(aaveV3DebtTokenAdaptor), abi.encode(address(dV3CBETH)));

        // // Deploy new Cellar implementation.
        // CellarInitializableV2_2 implementation = new CellarInitializableV2_2(registry);

        // bytes memory params = abi.encode(
        //     address(0),
        //     registry,
        //     WETH,
        //     "Production Implementation",
        //     "Prod Imp",
        //     positionIds[0],
        //     abi.encode(0),
        //     address(0)
        // );

        // // Initialize Implementation.
        // implementation.initialize(params);

        // factory.addImplementation(address(implementation), 2, 2);

        // // Deploy cellar using factory.
        // bytes memory initializeCallData = abi.encode(
        //     devOwner,
        //     registry,
        //     WETH,
        //     "Real Yield ETH",
        //     "YieldETH",
        //     positionIds[6],
        //     abi.encode(1.05e18),
        //     strategist
        // );
        // address imp = factory.getImplementation(2, 2);
        // require(imp != address(0), "Invalid implementation");

        // uint256 initialDeposit = 0.001e18;
        // WETH.approve(address(factory), initialDeposit);
        // address clone = factory.deploy(
        //     2,
        //     2,
        //     initializeCallData,
        //     WETH,
        //     initialDeposit,
        //     keccak256(abi.encode(block.timestamp))
        // );
        // cellar = CellarInitializableV2_2(clone);

        // // Setup all the adaptors the cellar will use.
        // cellar.addAdaptorToCatalogue(address(uniswapV3Adaptor));
        // cellar.addAdaptorToCatalogue(address(feesAndReservesAdaptor));
        // cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        // cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
        // cellar.addAdaptorToCatalogue(address(aaveV3ATokenAdaptor));
        // cellar.addAdaptorToCatalogue(address(aaveV3DebtTokenAdaptor));
        // cellar.addAdaptorToCatalogue(address(zeroXAdaptor));
        // cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));
        // cellar.addAdaptorToCatalogue(address(oneInchAdaptor));
        // cellar.addAdaptorToCatalogue(address(vestingSimpleAdaptor));

        // // Setup all the positions the cellar will use.
        // cellar.addPositionToCatalogue(positionIds[0]);
        // cellar.addPositionToCatalogue(positionIds[1]);
        // cellar.addPositionToCatalogue(positionIds[2]);
        // cellar.addPositionToCatalogue(positionIds[3]);
        // cellar.addPositionToCatalogue(positionIds[4]);
        // cellar.addPositionToCatalogue(positionIds[5]);
        // cellar.addPositionToCatalogue(positionIds[7]);
        // cellar.addPositionToCatalogue(positionIds[8]);
        // cellar.addPositionToCatalogue(positionIds[9]);
        // cellar.addPositionToCatalogue(positionIds[10]);
        // cellar.addPositionToCatalogue(positionIds[11]);
        // cellar.addPositionToCatalogue(positionIds[12]);
        // cellar.addPositionToCatalogue(positionIds[13]);
        // cellar.addPositionToCatalogue(positionIds[14]);
        // cellar.addPositionToCatalogue(positionIds[15]);

        // cellar.transferOwnership(0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138);

        vm.stopBroadcast();
    }
}
