// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";

// Import adaptors.
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployUniswapV3Adaptor.s.sol:DeployUniswapV3AdaptorScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployUniswapV3AdaptorScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    UniswapV3Adaptor private adaptor;

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    function run() external {
        vm.startBroadcast();

        adaptor = new UniswapV3Adaptor(address(positionManager), address(0));

        vm.stopBroadcast();
    }
}
