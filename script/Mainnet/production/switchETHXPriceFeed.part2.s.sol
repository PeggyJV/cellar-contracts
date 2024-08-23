// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Mainnet/production/switchETHXPriceFeed.part2.s.sol:switchEthXPriceFeed --rpc-url $MAINNET_RPC_URL --sender $MULTI_SIG --with-gas-price 25000000000`
 */
contract switchEthXPriceFeed is Script, MainnetAddresses {


    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);


    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    function run() external {

        //Complete EDIT asset

        uint256 ethx_price = uint256(IChainlinkAggregator(ETHX_ETH_FEED).latestAnswer());

        uint256 eth_price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());

        uint256 price = ethx_price * eth_price/1e18;

        PriceRouter.AssetSettings memory settings;


        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, ETHX_ETH_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        stor.inETH = true;

        vm.startBroadcast();

        priceRouter.completeEditAsset(ETHX, settings, abi.encode(stor), price);

        vm.stopBroadcast();
    }

}
