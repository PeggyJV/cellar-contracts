// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { UniswapV3Pool } from "src/interfaces/external/UniswapV3Pool.sol";
import { Registry } from "src/Registry.sol";
import { IBasePool } from "@balancer/interfaces/contracts/vault/IBasePool.sol";
import { IBalancerPool } from "src/interfaces/external/IBalancerPool.sol";

// import { PoolBalances } from "@balancer/vault/contracts/PoolBalances.sol";
// So I think the userData is an abi.encode min amount of BPTs, or maybe max amount(for exits)?

import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";
import { BalancerLinearPoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerLinearPoolExtension.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";

// import { IVault, VaultReentrancyLib } from "@balancer/pool-utils/contracts/lib/VaultReentrancyLib.sol";
import { IVault, IAsset, IERC20 } from "@balancer/interfaces/contracts/vault/IVault.sol";

import { Test, console, stdStorage, StdStorage } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract BalancerStableAndLinearPoolTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    PriceRouter private priceRouter;

    BalancerStablePoolExtension private balancerStablePoolExtension;
    BalancerLinearPoolExtension private balancerLinearPoolExtension;
    WstEthExtension private wstEthExtension;

    address private immutable sender = vm.addr(0xABCD);
    address private immutable receiver = vm.addr(0xBEEF);

    // Valid Derivatives
    uint8 private constant CHAINLINK_DERIVATIVE = 1;
    uint8 private constant TWAP_DERIVATIVE = 2;
    uint8 private constant EXTENSION_DERIVATIVE = 3;

    // Mainnet contracts:
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant rETH = ERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);
    ERC20 private constant STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ERC20 private constant WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ERC20 private constant cbETH = ERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    ERC20 private constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private constant USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private RETH_ETH_FEED = 0x536218f9E9Eb48863970252233c8F271f554C2d0;
    address private STETH_USD_FEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
    address private CBETH_ETH_FEED = 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

    // Balancer BPTs
    // Stable
    ERC20 private USDC_DAI_USDT_BPT = ERC20(0x79c58f70905F734641735BC61e45c19dD9Ad60bC);
    ERC20 private rETH_wETH_BPT = ERC20(0x1E19CF2D73a72Ef1332C882F20534B6519Be0276);
    ERC20 private wstETH_wETH_BPT = ERC20(0x32296969Ef14EB0c6d29669C550D4a0449130230);
    ERC20 private wstETH_cbETH_BPT = ERC20(0x9c6d47Ff73e0F5E51BE5FD53236e3F595C5793F2);
    ERC20 private bb_a_USD_BPT = ERC20(0xA13a9247ea42D743238089903570127DdA72fE44);
    // Linear
    ERC20 private bb_a_USDC_BPT = ERC20(0x82698aeCc9E28e9Bb27608Bd52cF57f704BD1B83);
    ERC20 private bb_a_DAI_BPT = ERC20(0xae37D54Ae477268B9997d4161B96b8200755935c);
    ERC20 private bb_a_USDT_BPT = ERC20(0x2F4eb100552ef93840d5aDC30560E5513DFfFACb);

    IVault private vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    Registry private registry;

    modifier checkBlockNumber() {
        if (block.number < 16990614) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16990614.");
            return;
        }
        _;
    }

    function setUp() external checkBlockNumber {
        registry = new Registry(address(this), address(this), address(this));
        priceRouter = new PriceRouter(registry);

        // Deploy Required Extensions.
        balancerStablePoolExtension = new BalancerStablePoolExtension(priceRouter, vault);
        balancerLinearPoolExtension = new BalancerLinearPoolExtension(priceRouter, vault);
        wstEthExtension = new WstEthExtension(priceRouter);
    }

    // ======================================= HAPPY PATH =======================================
    // TODO so I think all my tests will look like.
    // Add the BPT
    // Join the BPT pool, and confirm that the BPT I got out is similair in value to the
    // assets put into the pool.
    // https://docs.balancer.fi/reference/joins-and-exits/pool-joins.html

    // TODO remove below is for decoding userData
    // bytes
    //     memory userData = hex"000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000013f6f7ff3df11603b0130000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000e070816e3fb9df55b4000000000000000000000000000000000000000000000000000000008fa3258f50000000000000000000000000000000000000000000000000000000000000000";
    // (uint256 kind, uint256[] memory vals, uint256 minAmountOut) = abi.decode(
    //     userData,
    //     (uint256, uint256[], uint256)
    // );
    // console.log("Kind", kind);
    // console.log("Token Length", vals.length);
    // console.log("Token Amount 0", vals[0]);
    // console.log("Token Amount 1", vals[1]);
    // console.log("Token Amount 2", vals[2]);
    // console.log("Min out", minAmountOut);
    function testPricingUSDC_DAI_USDT_Bpt(uint256 valueIn) external checkBlockNumber {
        valueIn = bound(valueIn, 1e6, 1_000_000e6);
        // Add required pricing.
        _addChainlinkAsset(USDC, USDC_USD_FEED, false);
        _addChainlinkAsset(DAI, DAI_USD_FEED, false);
        _addChainlinkAsset(USDT, USDT_USD_FEED, false);

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));

        priceRouter.addAsset(USDC_DAI_USDT_BPT, settings, abi.encode(0), 1e8);

        uint256 bptOut = _joinPool(address(USDC), valueIn, IBalancerPool(address(USDC_DAI_USDT_BPT)));

        uint256 valueOut = priceRouter.getValue(USDC_DAI_USDT_BPT, bptOut, USDC);
        assertApproxEqRel(valueOut, valueIn, 0.001e18, "Value out should approximately equal value in.");
    }

    function testPricingRETH_WETH_Bpt(uint256 valueIn) external checkBlockNumber {
        valueIn = bound(valueIn, 0.1e18, 10_000e18);

        // Add required pricing.
        _addChainlinkAsset(USDC, USDC_USD_FEED, false);
        _addChainlinkAsset(WETH, WETH_USD_FEED, false);
        _addChainlinkAsset(rETH, RETH_ETH_FEED, true);

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));

        priceRouter.addAsset(rETH_wETH_BPT, settings, abi.encode(0), 1915e8);

        uint256 bptOut = _joinPool(address(WETH), valueIn, IBalancerPool(address(rETH_wETH_BPT)));

        uint256 valueOut = priceRouter.getValue(rETH_wETH_BPT, bptOut, WETH);
        assertApproxEqRel(valueOut, valueIn, 0.004e18, "Value out should approximately equal value in.");
    }

    function testPricingWstETH_WETH_Bpt(uint256 valueIn) external checkBlockNumber {
        valueIn = bound(valueIn, 0.1e18, 100_000e18);
        // valueIn = 1e18;

        // Add required pricing.
        _addChainlinkAsset(USDC, USDC_USD_FEED, false);
        _addChainlinkAsset(WETH, WETH_USD_FEED, false);
        _addChainlinkAsset(STETH, STETH_USD_FEED, false);

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstEthExtension));

        priceRouter.addAsset(WSTETH, settings, abi.encode(0), 2_100e8);

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));

        priceRouter.addAsset(wstETH_wETH_BPT, settings, abi.encode(0), 1915e8);

        uint256 bptOut = _joinPool(address(WETH), valueIn, IBalancerPool(address(wstETH_wETH_BPT)));

        uint256 valueOut = priceRouter.getValue(wstETH_wETH_BPT, bptOut, WETH);
        assertApproxEqRel(valueOut, valueIn, 0.004e18, "Value out should approximately equal value in.");
    }

    function testPricingCBETH_WETH_Bpt(uint256 valueIn) external checkBlockNumber {
        valueIn = bound(valueIn, 0.1e18, 1_000e18);
        // valueIn = 1e18;

        // Add required pricing.
        _addChainlinkAsset(USDC, USDC_USD_FEED, false);
        _addChainlinkAsset(WETH, WETH_USD_FEED, false);
        _addChainlinkAsset(STETH, STETH_USD_FEED, false);
        _addChainlinkAsset(cbETH, CBETH_ETH_FEED, true);

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstEthExtension));

        priceRouter.addAsset(WSTETH, settings, abi.encode(0), 2_100e8);

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));

        priceRouter.addAsset(wstETH_cbETH_BPT, settings, abi.encode(0), 1915e8);

        uint256 bptOut = _joinPool(address(cbETH), valueIn, IBalancerPool(address(wstETH_cbETH_BPT)));

        uint256 valueOut = priceRouter.getValue(wstETH_cbETH_BPT, bptOut, cbETH);
        // TODO I think this is so off bc chainlink under reports cbETH price?
        assertApproxEqRel(valueOut, valueIn, 0.03e18, "Value out should approximately equal value in.");
    }

    // ======================================= HELPER FUNCTIONS =======================================

    enum WeightedJoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT,
        ALL_TOKENS_IN_FOR_EXACT_BPT_OUT
    }

    enum StableJoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT
    }

    // TODO create a batch swap function for linear/boosted pools

    function _joinPool(address asset, uint256 amount, IBalancerPool pool) internal returns (uint256 bptOut) {
        // So the assets, and maxAmounts must include the BPT in their array,
        // but joinAmounts must NOT, and it needs to be in order of the tokens array - the BPT address.
        (IERC20[] memory tokens, , ) = vault.getPoolTokens(pool.getPoolId());
        bool includesBpt;
        for (uint256 i; i < tokens.length; ++i) {
            if (address(tokens[i]) == address(pool)) {
                includesBpt = true;
                break;
            }
        }
        if (includesBpt) {
            uint256 lengthToUse = tokens.length - 1;
            IAsset[] memory assets = new IAsset[](lengthToUse + 1);
            uint256[] memory maxAmounts = new uint256[](lengthToUse + 1);
            uint256[] memory joinAmounts = new uint256[](lengthToUse);

            uint256 targetIndex;
            uint256 currentIndex;
            for (uint256 i; i < tokens.length; ++i) {
                assets[i] = IAsset(address(tokens[i]));
                if (address(tokens[i]) == address(asset)) {
                    maxAmounts[i] = amount;
                    targetIndex = currentIndex;
                }
                if (address(tokens[i]) == address(pool)) continue;
                currentIndex++;
            }

            joinAmounts[targetIndex] = amount;
            bytes memory userData = abi.encode(StableJoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, joinAmounts, 0);

            deal(asset, address(this), amount);
            ERC20(asset).approve(address(vault), amount);

            uint256 balanceBefore = ERC20(address(pool)).balanceOf(address(this));
            vault.joinPool(
                pool.getPoolId(),
                address(this),
                address(this),
                IVault.JoinPoolRequest(assets, maxAmounts, userData, false)
            );
            return ERC20(address(pool)).balanceOf(address(this)) - balanceBefore;
        } else {
            uint256 lengthToUse = tokens.length;
            IAsset[] memory assets = new IAsset[](lengthToUse);
            uint256[] memory maxAmounts = new uint256[](lengthToUse);
            uint256[] memory joinAmounts = new uint256[](lengthToUse);

            for (uint256 i; i < tokens.length; ++i) {
                assets[i] = IAsset(address(tokens[i]));
                if (address(tokens[i]) == address(asset)) {
                    maxAmounts[i] = amount;
                    joinAmounts[i] = amount;
                }
            }

            bytes memory userData = abi.encode(StableJoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, joinAmounts, 0);

            deal(asset, address(this), amount);
            ERC20(asset).approve(address(vault), amount);

            uint256 balanceBefore = ERC20(address(pool)).balanceOf(address(this));
            vault.joinPool(
                pool.getPoolId(),
                address(this),
                address(this),
                IVault.JoinPoolRequest(assets, maxAmounts, userData, false)
            );
            return ERC20(address(pool)).balanceOf(address(this)) - balanceBefore;
        }
    }

    function _addChainlinkAsset(ERC20 asset, address priceFeed, bool inEth) internal {
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        stor.inETH = inEth;

        uint256 price = uint256(IChainlinkAggregator(priceFeed).latestAnswer());
        if (inEth) {
            price = priceRouter.getValue(WETH, price, USDC);
            price = price.changeDecimals(6, 8);
        }

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, priceFeed);
        priceRouter.addAsset(asset, settings, abi.encode(stor), price);
    }
}
