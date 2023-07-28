// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { TEnv } from "script/test/TEnv.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/test/AddNewImplementation.s.sol:AddNewImplementationScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
//  TODO maybe this should be more of a Setup new Adaptor?
contract AddPositionsToRegistryScript is Script, TEnv {
    function run() external {
        vm.startBroadcast();

        // Setup price feeds.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Trust any new adaptors.
        // registry.trustAdaptor(address(eulerETokenAdaptor), 0, 0);

        // Trust any new positions.
        // eUsdcPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eUSDC, 0), 0, 0);

        vm.stopBroadcast();
    }
}
