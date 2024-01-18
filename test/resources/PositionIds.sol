// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

contract PositionIds {
    /**
     * Native refers to tokens that are natively minted on target chain, USDC, wAVAX
     * Bridged refers to tokens that are bridged over from another chain using a custom bridge, USDCe
     * Axelar refers to tokens that are bridged over from another chain using axelar, axlUSDC
     */

    // ERC20 Native 1-10_000
    uint32 public wethNative = 1;
    uint32 public usdcNative = 2;
    uint32 public daiNative = 3;
    uint32 public usdtNative = 4;
    uint32 public wbtcNative = 5;
    uint32 public crvusdNative = 6;
    uint32 public osethNative = 7;
    uint32 public ethxNative = 8;
    uint32 public stethNative = 9;
    uint32 public wstethNative = 10;
    uint32 public rethNative = 11;
    uint32 public fraxNative = 12;
    uint32 public lusdNative = 13;

    // ERC20 Bridged 10_001-20_000
    uint32 public wethBridged = 10_001;
    uint32 public usdcBridged = 10_002;
    uint32 public daiBridged = 10_003;
    uint32 public usdtBridged = 10_004;
    uint32 public wbtcBridged = 10_005;

    // ERC20 Axelar Bridged 20_001-30_000
    uint32 public wethAxelar = 20_001;
    uint32 public usdcAxelar = 20_002;
    uint32 public daiAxelar = 20_003;
    uint32 public usdtAxelar = 20_004;
    uint32 public wbtcAxelar = 20_005;

    // ERC20 Future Reserved 30_001-100_000

    // Uniswap V3 Native-Native 100_001-110_000
    uint32 public osethNative_wethNative_uniswap_v3 = 100_001;
    uint32 public wstethNative_ethxNative_uniswap_v3 = 100_002;
    uint32 public wethNative_ethxNative_uniswap_v3 = 100_003;

    // Uniswap V3 Native-Bridged 110_001-120_000
    // Uniswap V3 Bridged-Bridged 120_001-130_000
    // Uniswap V3 Native-Axelar 130_001-140_000
    // Uniswap V3 Axelar-Axelar 140_001-150_000
    // Uniswap V3 Axelar-Bridged 150_001-160_000
    // Uniswap V3 Future Reserved 160_001-200_000

    // Aave V3 Native 200_001-210_000
    // Aave V3 Bridged 210_001-220_000
    // Aave V3 Axelar 220_001-230_000
    // Aave V2 Native 230_001-240_000
    // Aave V2 Bridged 240_001-250_000
    // Aave V2 Axelar 250_001-260_000
    // Aave Future Reserved 260_001-300_000

    // Compound V2 Native 300_001-310_000
    // Compound V2 Bridged 310_001-320_000
    // Compound V2 Axelar 320_001-330_000
    // Compound V2 Reserved 330_001-400_000

    // Compound V3 Native 400_001-410_000
    // Compound V3 Bridged 410_001-420_000
    // Compound V3 Axelar 420_001-430_000
    // Compound V3 Reserved 430_001-500_000

    // Fraxlend
    // Fraxlend Native 500_001-510_000
    // Fraxlend Bridged 510_001-520_000
    // Fraxlend Axelar 520_001-530_000
    // Fraxlend Reserved 530_001-600_000

    // Balancer V2 600_001-700_000
    uint32 public osethNative_wethNative_balancer_v2 = 600_001;
    uint32 public ethNative_ethxNative_balancer_v2 = 600_002;

    // Aura 700_001-800_000
    uint32 public osethNative_wethNative_aura = 700_001;
    uint32 public ethNative_ethxNative_aura = 700_002;

    // Curve 800_001-900_000
    uint32 public usdcNative_crvusdNative_curve = 800_001;
    uint32 public usdtNative_crvusdNative_curve = 800_002;
    uint32 public fraxNative_crvusdNative_curve = 800_003;
    uint32 public lusdNative_crvusdNative_curve = 800_004;
    uint32 public osethNative_rethNative_curve = 800_005;
    uint32 public wstethNative_ethxNative_curve = 800_006;
    uint32 public ethNative_ethxNative_curve = 800_007;

    // Convex 900_001-1_000_000
    uint32 public usdcNative_crvusdNative_convex = 900_001;
    uint32 public usdtNative_crvusdNative_convex = 900_002;
    uint32 public fraxNative_crvusdNative_convex = 900_003;
    uint32 public lusdNative_crvusdNative_convex = 900_004;
    uint32 public osethNative_rethNative_convex = 900_005;
    uint32 public wstethNative_ethxNative_convex = 900_006;
    uint32 public ethNative_ethxNative_convex = 900_007;

    // ERC4626 1_000_001-1_100_000
}
