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
 *      `source .env && forge script script/DeployV2_1.s.sol:DeployV2Script --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 30000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --broadcast --slow`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployRealYieldScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private strategist = 0x4a1554ae3661661BA155c1Aa6c3d5B17251088a7;
    address private sommMultiSig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;

    CellarFactory private factory = CellarFactory(0x95f0eD6581AdF2ee1149fc7830594C7933C876AE);
    Registry private registry = Registry(0xeFFe069b1c62c2f55F41A501eCc3c6Ff4dB6D70a);
    CellarInitializable private cellar;

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
    UniswapV3Adaptor private uniswapV3Adaptor = UniswapV3Adaptor(0xc31137bbFd277E93ef36Aa7d1b6DE88a8ce8E487);
    AaveATokenAdaptor private aaveATokenAdaptor = AaveATokenAdaptor(0x9810F192D90fF4fdE38792e098c27914Cc05a039);
    CTokenAdaptor private cTokenAdaptor = CTokenAdaptor(0x55534e5F1f8dFB4db0f1D2A3a1D241cA5Cf0DC62);
    VestingSimpleAdaptor private vestingAdaptor = VestingSimpleAdaptor(0xf842b9545102CE21635F9f43bcc462080025DE62);

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

        address clone = factory.deploy(2, 1, initializeCallData, USDC, 0, keccak256(abi.encode(2)));
        cellar = CellarInitializable(clone);

        // Setup all the adaptors the cellar will use.
        cellar.setupAdaptor(address(uniswapV3Adaptor));
        cellar.setupAdaptor(address(aaveATokenAdaptor));
        cellar.setupAdaptor(address(cTokenAdaptor));
        cellar.setupAdaptor(address(vestingAdaptor));

        cellar.transferOwnership(sommMultiSig);

        vm.stopBroadcast();
    }
}
