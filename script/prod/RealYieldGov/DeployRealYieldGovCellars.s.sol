// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { TEnv } from "script/test/TEnv.sol";
import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";

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
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";

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
    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 public LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);
    ERC20 public ONEINCH = ERC20(0x111111111117dC0aa78b770fA6A738034120C302);
    ERC20 public UNI = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    ERC20 public SNX = ERC20(0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F);
    ERC20 public ENS = ERC20(0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72);

    // Aave V2 Positions.
    ERC20 public aV2WETH = ERC20(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e);
    ERC20 public aV2WBTC = ERC20(0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656);
    ERC20 public aV2ONEINCH = ERC20(0xB29130CBcC3F791f077eAdE0266168E808E5151e);
    ERC20 public aV2LINK = ERC20(0xa06bC25B5805d5F8d82847D191Cb4Af5A3e873E0);
    ERC20 public aV2UNI = ERC20(0xB9D7CB55f463405CDfBe4E90a6D2Df01C2B92BF1);
    ERC20 public aV2SNX = ERC20(0x35f6B052C598d933D69A4EEC4D04c73A191fE6c2);
    ERC20 public aV2ENS = ERC20(0x9a14e23A58edf4EFDcB360f68cd1b95ce2081a2F);

    ERC20 public dV2WETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);

    // Aave V3 positions.
    ERC20 public aV3WETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 public aV3WBTC = ERC20(0x5Ee5bf7ae06D1Be5997A1A72006FE6C607eC6DE8);
    ERC20 public aV3SNX = ERC20(0xC7B4c17861357B8ABB91F25581E7263E08DCB59c);
    ERC20 public aV3UNI = ERC20(0xF6D2224916DDFbbab6e6bd0D1B7034f4Ae0CaB18);
    ERC20 public aV3LINK = ERC20(0x5E8C8A7243651DB1384C0dDfDbE39761E8e7E51a);

    ERC20 public dV3WETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);

    CellarInitializableV2_2 private cellar;

    PriceRouter private priceRouter = PriceRouter(0x545Ce2e5b603c260cC6b2D1B78A66404E12590d8);
    CellarFactory private factory = CellarFactory(0x9D30672eED8D514cD1ad009Cfe85Ea8f0019D37F);
    SwapRouter private swapRouter = SwapRouter(0x070f43E613B33aD3EFC6B2928f3C01d58D032020);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    FeesAndReserves private feesAndReserves = FeesAndReserves(0xF4279E93a06F9d4b5d0625b1F471AA99Ef9B686b);
    UniswapV3PositionTracker private tracker = UniswapV3PositionTracker(0xf2854d84D9Dd27eCcD6aB20b3F66111a51bb56d2);
    CellarInitializableV2_2 private rye = CellarInitializableV2_2(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);

    CellarAdaptor private cellarAdaptor;

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor = ERC20Adaptor(0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE);
    FeesAndReservesAdaptor private feesAndReservesAdaptor =
        FeesAndReservesAdaptor(0x647d264d800A2461E594796af61a39b7735d8933);
    AaveATokenAdaptor private aaveATokenAdaptor = AaveATokenAdaptor(0xe3A3b8AbbF3276AD99366811eDf64A0a4b30fDa2);
    AaveDebtTokenAdaptor private aaveDebtTokenAdaptor =
        AaveDebtTokenAdaptor(0xeC86ac06767e911f5FdE7cba5D97f082C0139C01);
    AaveV3ATokenAdaptor private aaveV3ATokenAdaptor = AaveV3ATokenAdaptor(0x3184CBEa47eD519FA04A23c4207cD15b7545F1A6);
    AaveV3DebtTokenAdaptor private aaveV3DebtTokenAdaptor =
        AaveV3DebtTokenAdaptor(0x6DEd49176a69bEBf8dC1a4Ea357faa555df188f7);
    UniswapV3Adaptor private uniswapV3Adaptor = UniswapV3Adaptor(0x0bD9a2c1917E3a932A4a712AEE38FF63D35733Fb);
    ZeroXAdaptor private zeroXAdaptor = ZeroXAdaptor(0x1039a9b61DFF6A3fb8dbF4e924AA749E5cFE35ef);
    SwapWithUniswapAdaptor private swapWithUniswapAdaptor =
        SwapWithUniswapAdaptor(0xd6BC6Df1ed43e3101bC27a4254593a06598a3fDD);
    OneInchAdaptor private oneInchAdaptor = OneInchAdaptor(0xB8952ce4010CFF3C74586d712a4402285A3a3AFb);

    function run() external {
        vm.startBroadcast();

        // // Deploy adaptors.
        cellarAdaptor = new CellarAdaptor();

        // // Trust all adaptors.
        registry.trustAdaptor(address(cellarAdaptor));

        uint32[] memory positionIds = new uint32[](16);

        // Add Positions to registry.
        // credit positions
        positionIds[0] = registry.trustPosition(address(cellarAdaptor), abi.encode(address(rye)));
        positionIds[1] = registry.trustPosition(address(erc20Adaptor), abi.encode(WBTC));
        positionIds[2] = registry.trustPosition(address(erc20Adaptor), abi.encode(LINK));
        positionIds[3] = registry.trustPosition(address(erc20Adaptor), abi.encode(ONEINCH));
        positionIds[4] = registry.trustPosition(address(erc20Adaptor), abi.encode(UNI));
        positionIds[5] = registry.trustPosition(address(erc20Adaptor), abi.encode(SNX));
        positionIds[6] = registry.trustPosition(address(erc20Adaptor), abi.encode(ENS));
        positionIds[7] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(aV2WBTC));
        positionIds[8] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(aV2ONEINCH));
        positionIds[9] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(aV2LINK));
        positionIds[10] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(aV2UNI));
        positionIds[11] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(aV2SNX));
        positionIds[12] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(aV2ENS));
        positionIds[13] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3WBTC));
        positionIds[14] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3SNX));
        positionIds[15] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3UNI));
        positionIds[16] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(aV3LINK));
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
