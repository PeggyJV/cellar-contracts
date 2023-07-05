// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { TEnv } from "script/test/TEnv.sol";
import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { CellarStaking } from "src/modules/staking/CellarStaking.sol";

import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

// Import adaptors.
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
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
import { AaveV2EnableAssetAsCollateralAdaptor } from "src/modules/adaptors/Aave/AaveV2EnableAssetAsCollateralAdaptor.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";

// Import Morpho Adaptors.
import { MorphoAaveV2ATokenAdaptor, IMorphoV2 } from "src/modules/adaptors/Morpho/MorphoAaveV2ATokenAdaptor.sol";
import { MorphoAaveV2DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV2DebtTokenAdaptor.sol";
import { MorphoAaveV3ATokenP2PAdaptor, IMorphoV3 } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenP2PAdaptor.sol";
import { MorphoAaveV3ATokenCollateralAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenCollateralAdaptor.sol";
import { MorphoAaveV3DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3DebtTokenAdaptor.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/Mainnet/DeployRealYieldBtc.s.sol:DeployRealYieldBtcScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployRealYieldBtcScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 public cbETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    ERC20 public rETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);
    ERC20 public stETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    // Aave V2 Positions.
    ERC20 public aV2WETH = ERC20(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e);
    ERC20 public aV2WBTC = ERC20(0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656);
    ERC20 public dV2WETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);
    ERC20 public aV2STETH = ERC20(0x1982b2F5814301d4e9a8b0201555376e62F82428);

    // Aave V3 positions.
    ERC20 public aV3WETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 public dV3WETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);
    ERC20 public aV3CBETH = ERC20(0x977b6fc5dE62598B08C85AC8Cf2b745874E8b78c);
    ERC20 public dV3CBETH = ERC20(0x0c91bcA95b5FE69164cE583A2ec9429A569798Ed);
    ERC20 public aV3RETH = ERC20(0xCc9EE9483f662091a1de4795249E24aC0aC2630f);
    ERC20 public dV3RETH = ERC20(0xae8593DD575FE29A9745056aA91C4b746eee62C8);
    ERC20 public aV3WSTETH = ERC20(0x0B925eD163218f6662a35e0f0371Ac234f9E9371);
    ERC20 public aV3WBTC = ERC20(0x5Ee5bf7ae06D1Be5997A1A72006FE6C607eC6DE8);

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    CellarInitializableV2_2 private cellar;

    ERC20 private somm = ERC20(0xa670d7237398238DE01267472C6f13e5B8010FD1);
    CellarStaking private staker;

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    CellarFactory private factory = CellarFactory(0x9D30672eED8D514cD1ad009Cfe85Ea8f0019D37F);
    SwapRouter private swapRouter = SwapRouter(0x070f43E613B33aD3EFC6B2928f3C01d58D032020);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    FeesAndReserves private feesAndReserves = FeesAndReserves(0xF4279E93a06F9d4b5d0625b1F471AA99Ef9B686b);
    UniswapV3PositionTracker private tracker = UniswapV3PositionTracker(0xf2854d84D9Dd27eCcD6aB20b3F66111a51bb56d2);

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
    ZeroXAdaptor private zeroXAdaptor = ZeroXAdaptor(0x1039a9b61DFF6A3fb8dbF4e924AA749E5cFE35ef);
    SwapWithUniswapAdaptor private swapWithUniswapAdaptor =
        SwapWithUniswapAdaptor(0xd6BC6Df1ed43e3101bC27a4254593a06598a3fDD);
    OneInchAdaptor private oneInchAdaptor = OneInchAdaptor(0xB8952ce4010CFF3C74586d712a4402285A3a3AFb);
    VestingSimpleAdaptor private vestingSimpleAdaptor =
        VestingSimpleAdaptor(0x508E6aE090eA92Cb90571e4269B799257CD78CA1);
    AaveV2EnableAssetAsCollateralAdaptor private aaveV2EnableAssetAsCollateralAdaptor =
        AaveV2EnableAssetAsCollateralAdaptor(0x724FEb5819D1717Aec5ADBc0974a655a498b2614);
    MorphoAaveV2ATokenAdaptor private morphoAaveV2ATokenAdaptor =
        MorphoAaveV2ATokenAdaptor(0x1a4cB53eDB8C65C3DF6Aa9D88c1aB4CF35312b73);
    MorphoAaveV2DebtTokenAdaptor private morphoAaveV2DebtTokenAdaptor =
        MorphoAaveV2DebtTokenAdaptor(0x407D5489F201013EE6A6ca20fCcb05047C548138);
    MorphoAaveV3ATokenP2PAdaptor private morphoAaveV3ATokenP2PAdaptor =
        MorphoAaveV3ATokenP2PAdaptor(0x4fe068cAaD05B82bf3F86E1F7d1A7b8bbf516111);
    MorphoAaveV3ATokenCollateralAdaptor private morphoAaveV3ATokenCollateralAdaptor =
        MorphoAaveV3ATokenCollateralAdaptor(0xB46E8a03b1AaFFFb50f281397C57b5B87080363E);
    MorphoAaveV3DebtTokenAdaptor private morphoAaveV3DebtTokenAdaptor =
        MorphoAaveV3DebtTokenAdaptor(0x25a61f771aF9a38C10dDd93c2bBAb39a88926fa9);
    CellarAdaptor private cellarAdaptor = CellarAdaptor(0x3B5CA5de4d808Cd793d3a7b3a731D3E67E707B27);

    function run() external {
        vm.startBroadcast();

        uint32[] memory positionIds = new uint32[](26);

        positionIds[0] = 101; // ERC20 WETH
        positionIds[1] = 102; // ERC20 CBETH
        positionIds[2] = 103; // ERC20 RETH
        positionIds[3] = 104; // ERC20 stETH
        positionIds[4] = 142; // ERC20 wstETH
        positionIds[5] = 154; // Cellar RYE
        positionIds[6] = 117; // av2WETH
        positionIds[7] = 118; // av2STETH
        positionIds[8] = 119; // dv2WETH
        positionIds[9] = 107; // av3WETH
        positionIds[10] = 108; // av3 RETH
        positionIds[11] = 109; // av3cbETH
        positionIds[12] = 114; // dv3WETH
        positionIds[13] = 141; // av3wsteth
        positionIds[14] = 155; // morpho v2 steth
        positionIds[15] = 156; // morpho v2 weth
        positionIds[16] = 160; // morpho v2 wbtc
        positionIds[17] = 161; // morpho v2 debt weth
        positionIds[18] = 162; // morpho v3 p2p weth
        positionIds[19] = 163; // morpho v3 collateral wsteth
        positionIds[20] = 164; // morpho v3 collateral wbtc
        positionIds[21] = 165; // morpho v3 collateral reth
        positionIds[22] = 166; // morpho v3 debt weth
        positionIds[23] = 182; // av2WBTC
        positionIds[24] = 183; // av3WBTC
        positionIds[25] = 184; // ERC20 WBTC

        // Deploy cellar using factory.
        bytes memory initializeCallData = abi.encode(
            devOwner,
            registry,
            WBTC,
            "Real Yield BTC",
            "YieldBTC",
            positionIds[25],
            abi.encode(0),
            strategist
        );
        address imp = factory.getImplementation(2, 2);
        require(imp != address(0), "Invalid implementation");

        uint256 initialDeposit = 0;
        // WBTC.approve(address(factory), initialDeposit);
        address clone = factory.deploy(
            2,
            2,
            initializeCallData,
            WBTC,
            initialDeposit,
            keccak256(abi.encode(block.timestamp))
        );
        cellar = CellarInitializableV2_2(clone);

        // Setup all the adaptors the cellar will use.
        // cellar.addAdaptorToCatalogue(address(uniswapV3Adaptor));
        cellar.addAdaptorToCatalogue(address(feesAndReservesAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveV3ATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveV3DebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(zeroXAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));
        cellar.addAdaptorToCatalogue(address(oneInchAdaptor));
        cellar.addAdaptorToCatalogue(address(morphoAaveV2ATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(morphoAaveV2DebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(morphoAaveV3ATokenP2PAdaptor));
        cellar.addAdaptorToCatalogue(address(morphoAaveV3ATokenCollateralAdaptor));
        cellar.addAdaptorToCatalogue(address(morphoAaveV3DebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(cellarAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveV2EnableAssetAsCollateralAdaptor));

        for (uint256 i; i < positionIds.length - 1; ++i) cellar.addPositionToCatalogue(positionIds[i]);

        cellar.setShareLockPeriod(60 * 10);

        cellar.transferOwnership(0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138);

        staker = new CellarStaking(
            multisig,
            ERC20(address(cellar)),
            somm,
            30 days,
            0.1e18,
            0.3e18,
            0.5e18,
            7 days,
            14 days,
            21 days
        );

        vm.stopBroadcast();
    }
}
