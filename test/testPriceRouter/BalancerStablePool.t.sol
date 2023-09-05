// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IRETH } from "src/interfaces/external/IRETH.sol";
import { ICBETH } from "src/interfaces/external/ICBETH.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { UniswapV3Pool } from "src/interfaces/external/UniswapV3Pool.sol";
import { IBasePool } from "@balancer/interfaces/contracts/vault/IBasePool.sol";
import { IBalancerPool } from "src/interfaces/external/IBalancerPool.sol";

// import { PoolBalances } from "@balancer/vault/contracts/PoolBalances.sol";
// So I think the userData is an abi.encode min amount of BPTs, or maybe max amount(for exits)?

import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";

// import { IVault, VaultReentrancyLib } from "@balancer/pool-utils/contracts/lib/VaultReentrancyLib.sol";
import { IVault, IAsset, IERC20 } from "@balancer/interfaces/contracts/vault/IVault.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract BalancerStablePoolTest is MainnetStarterTest, AdaptorHelperFunctions {
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    BalancerStablePoolExtension private balancerStablePoolExtension;

    // Balancer data to join bb-aUSD with 100 USDC
    bytes joinData =
        hex"ac9650d8000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000002042e6272ea00000000000000000000000000000000000000000000000000000000000001200000000000000000000000007FA9385bE102ac3EAc297483Dd6233D62b3e14960000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fea793aa415061c483d2390414275ad314b3f62100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006459107a0000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000005cbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000004fa0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000000000000000000000000000000000000000005f5e10000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003a48fe4624ffebb0bbf162e64fb9d0dfe186e517d84c395f0160000000000000000000005020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fea793aa415061c483d2390414275ad314b3f6210000000000000000000000007FA9385bE102ac3EAc297483Dd6233D62b3e149600000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000000ba100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000040000000000000000000000006667c6fa9f2b3fc1cc8d85320b62703d938e4385000000000000000000000000a1697f9af0875b63ddc472d6eebada8c1fab8568000000000000000000000000cbfa4532d8b2ade2c261d3dd5ef2a2284f792692000000000000000000000000febb0bbf162e64fb9d0dfe186e517d84c395f016000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ba10000000000000000000000000000000000000000000000000000000000005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000005644b476ee4704a53000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ba1000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000";

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16990614;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        // Deploy Required Extensions.
        balancerStablePoolExtension = new BalancerStablePoolExtension(priceRouter, IVault(vault));
    }

    // ======================================= HAPPY PATH =======================================

    function testPricingUSDC_DAI_USDT_Bpt(uint256 valueIn) external {
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

    function testPricingRETH_WETH_Bpt(uint256 valueIn) external {
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

    function testPricingWstETH_WETH_Bpt(uint256 valueIn) external {
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

    function testPricingCBETH_WSTETH_Bpt(uint256 valueIn) external {
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

    function testPricingBb_a_Usd() external {
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
        USDC.approve(vault, valueIn);
        IVault(vault).setRelayerApproval(address(this), relayer, true);

        relayer.functionCall(joinData);
        uint256 bptOut = bb_a_USD_BPT.balanceOf(address(this));

        uint256 valueOut = priceRouter.getValue(bb_a_USD_BPT, bptOut, USDC);
        assertApproxEqRel(valueOut, valueIn, 0.01e18, "Value out should approximately equal value in.");
    }

    // ======================================= REVERTS =======================================

    function testPricingStablePoolWithUnsupportedUnderlying() external {
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

    function testMisConfiguredStorageData() external {
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
        (IERC20[] memory tokens, , ) = IVault(vault).getPoolTokens(pool.getPoolId());
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
            ERC20(asset).approve(vault, amount);

            uint256 balanceBefore = ERC20(address(pool)).balanceOf(address(this));
            IVault(vault).joinPool(
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
            ERC20(asset).approve(vault, amount);

            uint256 balanceBefore = ERC20(address(pool)).balanceOf(address(this));
            IVault(vault).joinPool(
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
