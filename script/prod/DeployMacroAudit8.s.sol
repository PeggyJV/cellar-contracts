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
import { IPool } from "src/interfaces/external/IPool.sol";

import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

// Import adaptors.
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import { OneInchAdaptor } from "src/modules/adaptors/OneInch/OneInchAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";

// Import Morpho Adaptors.
import { MorphoAaveV2ATokenAdaptor, IMorphoV2 } from "src/modules/adaptors/Morpho/MorphoAaveV2ATokenAdaptor.sol";
import { MorphoAaveV2DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV2DebtTokenAdaptor.sol";
import { MorphoAaveV3ATokenP2PAdaptor, IMorphoV3 } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenP2PAdaptor.sol";
import { MorphoAaveV3ATokenCollateralAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenCollateralAdaptor.sol";
import { MorphoAaveV3DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3DebtTokenAdaptor.sol";

// Import FraxLend Adaptors.
import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import { FTokenAdaptorV1 } from "src/modules/adaptors/Frax/FTokenAdaptorV1.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployMacroAudit8.s.sol:DeployMacroAudit8Script --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployMacroAudit8Script is Script {
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
    ERC20 public FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);

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

    IMorphoV2 private morphoV2 = IMorphoV2(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);
    address private morphoLens = 0x507fA343d0A90786d86C7cd885f5C49263A91FF4;
    address private rewardHandler = 0x3B14E5C73e0A56D607A8688098326fD4b4292135;

    IMorphoV3 private morphoV3 = IMorphoV3(0x33333aea097c193e66081E930c33020272b33333);

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    CellarInitializableV2_2 private cellar;

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    CellarFactory private factory = CellarFactory(0x9D30672eED8D514cD1ad009Cfe85Ea8f0019D37F);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    FeesAndReserves private feesAndReserves = FeesAndReserves(0xF4279E93a06F9d4b5d0625b1F471AA99Ef9B686b);
    UniswapV3PositionTracker private tracker = UniswapV3PositionTracker(0xf2854d84D9Dd27eCcD6aB20b3F66111a51bb56d2);

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor;
    CellarAdaptor private cellarAdaptor;
    FeesAndReservesAdaptor private feesAndReservesAdaptor;
    UniswapV3Adaptor private uniswapV3Adaptor;
    ZeroXAdaptor private zeroXAdaptor;
    OneInchAdaptor private oneInchAdaptor;
    MorphoAaveV2ATokenAdaptor private morphoAaveV2ATokenAdaptor;
    MorphoAaveV2DebtTokenAdaptor private morphoAaveV2DebtTokenAdaptor;
    MorphoAaveV3ATokenP2PAdaptor private morphoAaveV3ATokenP2PAdaptor;
    MorphoAaveV3ATokenCollateralAdaptor private morphoAaveV3ATokenCollateralAdaptor;
    MorphoAaveV3DebtTokenAdaptor private morphoAaveV3DebtTokenAdaptor;
    FTokenAdaptor private fTokenAdaptorV2;
    FTokenAdaptorV1 private fTokenAdaptorV1;

    function run() external {
        vm.startBroadcast();

        // Deploy Cellar Adaptor
        cellarAdaptor = new CellarAdaptor();

        // // Deploy Morpho Adaptors
        // morphoAaveV2ATokenAdaptor = new MorphoAaveV2ATokenAdaptor(
        //     address(morphoV2),
        //     morphoLens,
        //     1.05e18,
        //     rewardHandler
        // );
        // morphoAaveV2DebtTokenAdaptor = new MorphoAaveV2DebtTokenAdaptor(address(morphoV2), morphoLens, 1.05e18);
        // morphoAaveV3ATokenP2PAdaptor = new MorphoAaveV3ATokenP2PAdaptor(address(morphoV3), rewardHandler);
        // morphoAaveV3ATokenCollateralAdaptor = new MorphoAaveV3ATokenCollateralAdaptor(
        //     address(morphoV3),
        //     1.05e18,
        //     rewardHandler
        // );
        // morphoAaveV3DebtTokenAdaptor = new MorphoAaveV3DebtTokenAdaptor(address(morphoV3), 1.05e18);

        // // Deploy FraxLend Adaptors
        // fTokenAdaptorV2 = new FTokenAdaptor(true, address(FRAX));
        // // fTokenAdaptorV1 = new FTokenAdaptorV1(true, address(FRAX));

        vm.stopBroadcast();
    }
}
