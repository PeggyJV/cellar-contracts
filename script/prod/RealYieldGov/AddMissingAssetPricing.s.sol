// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Registry, PriceRouter, Math, ERC20 } from "src/base/Cellar.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/RealYieldGov/AddMissingAssetPricing.s.sol:AddMissingAssetPricingScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract AddMissingAssetPricingScript is Script {
    using Math for uint256;

    address private strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 public ONEINCH = ERC20(0x111111111117dC0aa78b770fA6A738034120C302);
    ERC20 public SNX = ERC20(0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F);
    ERC20 public ENS = ERC20(0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72);

    address public ONEINCH_USD_FEED = 0xc929ad75B72593967DE83E7F7Cda0493458261D9;
    address public SNX_USD_FEED = 0xDC3EA94CD0AC27d9A86C180091e7f78C683d3699;
    address public ENS_USD_FEED = 0x5C00128d4d1c2F4f652C267d7bcdD7aC99C16E16;

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    TimelockController private controller = TimelockController(payable(0xaDa78a5E01325B91Bc7879a63c309F7D54d42950));

    function run() external {
        vm.startBroadcast();

        // Add required assets to price router.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256[] memory prices = new uint256[](10);

        uint256 startingPrice = uint256(IChainlinkAggregator(ONEINCH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, ONEINCH_USD_FEED);
        prices[0] = startingPrice.mulDivDown(0.80e4, 1e4);
        for (uint256 i = 1; i < prices.length; ++i) prices[i] = prices[i - 1].mulDivDown(1.02e4, 0.98e4);
        for (uint256 i; i < prices.length; ++i) {
            bytes memory priceData = abi.encodeWithSelector(
                PriceRouter.addAsset.selector,
                ONEINCH,
                settings,
                abi.encode(stor),
                prices[i]
            );
            controller.schedule(address(priceRouter), 0, priceData, hex"", hex"", 3 days);
        }
        // priceRouter.addAsset(ONEINCH, settings, abi.encode(stor), price);

        startingPrice = uint256(IChainlinkAggregator(SNX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, SNX_USD_FEED);
        prices[0] = startingPrice.mulDivDown(0.80e4, 1e4);
        for (uint256 i = 1; i < prices.length; ++i) prices[i] = prices[i - 1].mulDivDown(1.02e4, 0.98e4);
        for (uint256 i; i < prices.length; ++i) {
            bytes memory priceData = abi.encodeWithSelector(
                PriceRouter.addAsset.selector,
                SNX,
                settings,
                abi.encode(stor),
                prices[i]
            );
            controller.schedule(address(priceRouter), 0, priceData, hex"", hex"", 3 days);
        }
        // priceRouter.addAsset(SNX, settings, abi.encode(stor), price);

        startingPrice = uint256(IChainlinkAggregator(ENS_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, ENS_USD_FEED);
        prices[0] = startingPrice.mulDivDown(0.80e4, 1e4);
        for (uint256 i = 1; i < prices.length; ++i) prices[i] = prices[i - 1].mulDivDown(1.02e4, 0.98e4);
        for (uint256 i; i < prices.length; ++i) {
            bytes memory priceData = abi.encodeWithSelector(
                PriceRouter.addAsset.selector,
                ENS,
                settings,
                abi.encode(stor),
                prices[i]
            );
            controller.schedule(address(priceRouter), 0, priceData, hex"", hex"", 3 days);
        }
        // priceRouter.addAsset(ENS, settings, abi.encode(stor), price);
        vm.stopBroadcast();
    }
}
