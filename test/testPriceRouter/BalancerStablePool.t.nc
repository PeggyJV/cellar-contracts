// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { IRETH } from "src/interfaces/external/IRETH.sol";
import { ICBETH } from "src/interfaces/external/ICBETH.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { UniswapV3Pool } from "src/interfaces/external/UniswapV3Pool.sol";
import { Registry } from "src/Registry.sol";
import { IBasePool } from "@balancer/interfaces/contracts/vault/IBasePool.sol";
import { IBalancerPool } from "src/interfaces/external/IBalancerPool.sol";

// import { PoolBalances } from "@balancer/vault/contracts/PoolBalances.sol";
// So I think the userData is an abi.encode min amount of BPTs, or maybe max amount(for exits)?

import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";

// import { IVault, VaultReentrancyLib } from "@balancer/pool-utils/contracts/lib/VaultReentrancyLib.sol";
import { IVault, IAsset, IERC20 } from "@balancer/interfaces/contracts/vault/IVault.sol";

import { Test, console, stdStorage, StdStorage } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract BalancerStablePoolTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    PriceRouter private priceRouter;

    BalancerStablePoolExtension private balancerStablePoolExtension;

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
    ERC20 private bb_a_USD_BPT = ERC20(0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016);
    // Linear
    ERC20 private bb_a_USDC_BPT = ERC20(0xcbFA4532D8B2ade2C261D3DD5ef2A2284f792692);
    ERC20 private bb_a_DAI_BPT = ERC20(0x6667c6fa9f2b3Fc1Cc8D85320b62703d938E4385);
    ERC20 private bb_a_USDT_BPT = ERC20(0xA1697F9Af0875B63DdC472d6EeBADa8C1fAB8568);

    IVault private vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    // Rate Providers
    address private cbethRateProvider = 0x7311E4BB8a72e7B300c5B8BDE4de6CdaA822a5b1;
    address private rethRateProvider = 0x1a8F81c256aee9C640e14bB0453ce247ea0DFE6F;

    Registry private registry;

    address private balancerRelayer = 0xfeA793Aa415061C483D2390414275AD314B3F621;
    // Balancer data to join bb-aUSD with 100 USDC
    bytes joinData =
        hex"ac9650d8000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000002042e6272ea00000000000000000000000000000000000000000000000000000000000001200000000000000000000000007FA9385bE102ac3EAc297483Dd6233D62b3e14960000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fea793aa415061c483d2390414275ad314b3f62100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006459107a0000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000005cbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000004fa0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000000000000000000000000000000000000000005f5e10000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003a48fe4624ffebb0bbf162e64fb9d0dfe186e517d84c395f0160000000000000000000005020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fea793aa415061c483d2390414275ad314b3f6210000000000000000000000007FA9385bE102ac3EAc297483Dd6233D62b3e149600000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000000ba100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000040000000000000000000000006667c6fa9f2b3fc1cc8d85320b62703d938e4385000000000000000000000000a1697f9af0875b63ddc472d6eebada8c1fab8568000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f792692000000000000000000000000febb0bbf162e64fb9d0dfe186e517d84c395f016000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000005644b476ee4704a53000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ba1000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000";

    modifier checkBlockNumber() {
        if (block.number < 16990614) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16990614.");
            return;
        }
        _;
    }

    function setUp() external checkBlockNumber {
        registry = new Registry(address(this), address(this), address(this));
        priceRouter = new PriceRouter(registry, WETH);

        // Deploy Required Extensions.
        balancerStablePoolExtension = new BalancerStablePoolExtension(priceRouter, vault);
    }

    // ======================================= HAPPY PATH =======================================

    function testPricingUSDC_DAI_USDT_Bpt(uint256 valueIn) external checkBlockNumber {
        valueIn = bound(valueIn, 1e6, 1_000_000e6);
        // Add required pricing.
        _addChainlinkAsset(USDC, USDC_USD_FEED, false);
        _addChainlinkAsset(DAI, DAI_USD_FEED, false);
        _addChainlinkAsset(USDT, USDT_USD_FEED, false);

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));

        uint8[8] memory rateProviderDecimals;
        address[8] memory rateProviders;
        ERC20[8] memory underlyings;
        underlyings[0] = USDC;
        underlyings[1] = DAI;
        underlyings[2] = USDT;
        BalancerStablePoolExtension.ExtensionStorage memory stor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: bytes32(0),
            poolDecimals: 18,
            rateProviderDecimals: rateProviderDecimals,
            rateProviders: rateProviders,
            underlyingOrConstituent: underlyings
        });

        priceRouter.addAsset(USDC_DAI_USDT_BPT, settings, abi.encode(stor), 1e8);

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

        uint8[8] memory rateProviderDecimals;
        rateProviderDecimals[1] = 18;
        address[8] memory rateProviders;
        rateProviders[1] = rethRateProvider;
        ERC20[8] memory underlyings;
        underlyings[0] = WETH;
        underlyings[1] = rETH;
        BalancerStablePoolExtension.ExtensionStorage memory stor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: bytes32(0),
            poolDecimals: 18,
            rateProviderDecimals: rateProviderDecimals,
            rateProviders: rateProviders,
            underlyingOrConstituent: underlyings
        });

        priceRouter.addAsset(rETH_wETH_BPT, settings, abi.encode(stor), 1915e8);

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

        uint8[8] memory rateProviderDecimals;
        address[8] memory rateProviders;
        ERC20[8] memory underlyings;
        underlyings[0] = WETH;
        underlyings[1] = STETH;
        BalancerStablePoolExtension.ExtensionStorage memory stor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: bytes32(0),
            poolDecimals: 18,
            rateProviderDecimals: rateProviderDecimals,
            rateProviders: rateProviders,
            underlyingOrConstituent: underlyings
        });

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));

        priceRouter.addAsset(wstETH_wETH_BPT, settings, abi.encode(stor), 1915e8);

        uint256 bptOut = _joinPool(address(WETH), valueIn, IBalancerPool(address(wstETH_wETH_BPT)));

        uint256 valueOut = priceRouter.getValue(wstETH_wETH_BPT, bptOut, WETH);
        assertApproxEqRel(valueOut, valueIn, 0.01e18, "Value out should approximately equal value in.");
    }

    function testPricingCBETH_WSTETH_Bpt(uint256 valueIn) external checkBlockNumber {
        valueIn = bound(valueIn, 0.1e18, 1_000e18);
        // valueIn = 1e18;

        // Add required pricing.
        _addChainlinkAsset(USDC, USDC_USD_FEED, false);
        _addChainlinkAsset(WETH, WETH_USD_FEED, false);
        _addChainlinkAsset(STETH, STETH_USD_FEED, false);
        _addChainlinkAsset(cbETH, CBETH_ETH_FEED, true);

        PriceRouter.AssetSettings memory settings;

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));

        uint8[8] memory rateProviderDecimals;
        rateProviderDecimals[0] = 18;
        address[8] memory rateProviders;
        rateProviders[0] = cbethRateProvider;
        ERC20[8] memory underlyings;
        underlyings[0] = cbETH;
        underlyings[1] = STETH;
        BalancerStablePoolExtension.ExtensionStorage memory stor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: bytes32(0),
            poolDecimals: 18,
            rateProviderDecimals: rateProviderDecimals,
            rateProviders: rateProviders,
            underlyingOrConstituent: underlyings
        });

        priceRouter.addAsset(wstETH_cbETH_BPT, settings, abi.encode(stor), 1865e8);

        uint256 bptOut = _joinPool(address(cbETH), valueIn, IBalancerPool(address(wstETH_cbETH_BPT)));

        uint256 valueOut = priceRouter.getValue(wstETH_cbETH_BPT, bptOut, cbETH);
        assertApproxEqRel(valueOut, valueIn, 0.0055e18, "Value out should approximately equal value in.");
    }

    function testPricingBb_a_Usd() external checkBlockNumber {
        // Add required pricing.
        _addChainlinkAsset(USDC, USDC_USD_FEED, false);
        _addChainlinkAsset(DAI, DAI_USD_FEED, false);
        _addChainlinkAsset(USDT, USDT_USD_FEED, false);

        PriceRouter.AssetSettings memory settings;

        uint8[8] memory rateProviderDecimals;
        address[8] memory rateProviders;
        ERC20[8] memory underlyings;
        underlyings[0] = USDC;
        underlyings[1] = DAI;
        underlyings[2] = USDT;
        BalancerStablePoolExtension.ExtensionStorage memory stor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: bytes32(0),
            poolDecimals: 18,
            rateProviderDecimals: rateProviderDecimals,
            rateProviders: rateProviders,
            underlyingOrConstituent: underlyings
        });

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));
        priceRouter.addAsset(bb_a_USD_BPT, settings, abi.encode(stor), 1e8);

        // Join the stable pool.
        uint256 valueIn = 100e6;
        deal(address(USDC), address(this), valueIn);
        USDC.approve(address(vault), valueIn);
        vault.setRelayerApproval(address(this), balancerRelayer, true);

        balancerRelayer.functionCall(joinData);
        uint256 bptOut = bb_a_USD_BPT.balanceOf(address(this));

        uint256 valueOut = priceRouter.getValue(bb_a_USD_BPT, bptOut, USDC);
        assertApproxEqRel(valueOut, valueIn, 0.01e18, "Value out should approximately equal value in.");
    }

    // ======================================= REVERTS =======================================

    function testPricingStablePoolWithUnsupportedUnderlying() external checkBlockNumber {
        // Add required pricing.
        _addChainlinkAsset(USDC, USDC_USD_FEED, false);
        _addChainlinkAsset(WETH, WETH_USD_FEED, false);

        PriceRouter.AssetSettings memory settings;

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));

        uint8[8] memory rateProviderDecimals;
        address[8] memory rateProviders;
        ERC20[8] memory underlyings;
        underlyings[0] = WETH;
        underlyings[1] = STETH;
        BalancerStablePoolExtension.ExtensionStorage memory stor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: bytes32(0),
            poolDecimals: 18,
            rateProviderDecimals: rateProviderDecimals,
            rateProviders: rateProviders,
            underlyingOrConstituent: underlyings
        });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    BalancerStablePoolExtension.BalancerStablePoolExtension__PoolTokensMustBeSupported.selector,
                    address(STETH)
                )
            )
        );
        priceRouter.addAsset(wstETH_wETH_BPT, settings, abi.encode(stor), 1915e8);
    }

    function testMisConfiguredStorageData() external checkBlockNumber {
        // Add required pricing.
        _addChainlinkAsset(USDC, USDC_USD_FEED, false);
        _addChainlinkAsset(WETH, WETH_USD_FEED, false);
        _addChainlinkAsset(rETH, RETH_ETH_FEED, true);

        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));

        uint8[8] memory rateProviderDecimals;
        address[8] memory rateProviders;
        rateProviders[1] = cbethRateProvider;
        ERC20[8] memory underlyings;
        underlyings[0] = WETH;
        underlyings[1] = rETH;
        BalancerStablePoolExtension.ExtensionStorage memory stor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: bytes32(0),
            poolDecimals: 18,
            rateProviderDecimals: rateProviderDecimals,
            rateProviders: rateProviders,
            underlyingOrConstituent: underlyings
        });

        // Try adding the asset without supplying rate provider decimals.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    BalancerStablePoolExtension.BalancerStablePoolExtension__RateProviderDecimalsNotProvided.selector
                )
            )
        );
        priceRouter.addAsset(rETH_wETH_BPT, settings, abi.encode(stor), 1915e8);

        // Update so we are providing the decimals.
        stor.rateProviderDecimals[1] = 18;

        // Call is now successful.
        priceRouter.addAsset(rETH_wETH_BPT, settings, abi.encode(stor), 1915e8);
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
