// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
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
 *      `source .env && forge script script/DeployRealYield.s.sol:DeployRealYieldScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 30000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --broadcast --slow`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployRealYieldScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address private sommMultiSig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private deployer = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    CellarFactory private factory;
    Registry private registry = Registry(0x2Cbd27E034FEE53f79b607430dA7771B22050741);
    CellarInitializableV2_1 private cellar;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

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

    // Define Adaptors.
    UniswapV3Adaptor private uniswapV3Adaptor = UniswapV3Adaptor(0x7C4262f83e6775D6ff6fE8d9ab268611Ed9d13Ee);
    AaveATokenAdaptor private aaveATokenAdaptor = AaveATokenAdaptor(0x8646F6A7658a7B6399dc238d6018d0344ad81D3d);
    CTokenAdaptor private cTokenAdaptor = CTokenAdaptor(0x26DbA82495f6189DDe7648Ae88bEAd46C402F078);
    VestingSimpleAdaptor private vestingAdaptor = VestingSimpleAdaptor(0x1eAA1a100a460f46A2032f0402Bc01FE89FaAB60);

    function run() external {
        vm.startBroadcast();

        // Deploy cellar using factory.
        factory = CellarFactory(0x9D30672eED8D514cD1ad009Cfe85Ea8f0019D37F);
        address implementation = address(new CellarInitializableV2_1(registry));

        factory.addImplementation(implementation, 2, 2);

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
            deployer,
            registry,
            USDC,
            "Real Yield USD",
            "YieldUSD",
            abi.encode(
                positions,
                debtPositions,
                positionConfigs,
                debtConfigs,
                aUSDCPosition,
                strategist,
                type(uint128).max,
                type(uint128).max
            )
        );
        require(false, "Was implementation 2, 2 added to the factory?");
        address clone = factory.deploy(2, 2, initializeCallData, USDC, 0, keccak256(abi.encode(2)));
        cellar = CellarInitializableV2_1(clone);

        // Setup all the adaptors the cellar will use.
        cellar.setupAdaptor(address(uniswapV3Adaptor));
        cellar.setupAdaptor(address(aaveATokenAdaptor));
        cellar.setupAdaptor(address(cTokenAdaptor));
        cellar.setupAdaptor(address(vestingAdaptor));

        cellar.transferOwnership(strategist);

        // Initialize implementation.
        CellarInitializableV2_1(implementation).initialize(initializeCallData);

        vm.stopBroadcast();
    }
}
