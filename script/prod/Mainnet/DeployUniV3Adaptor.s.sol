// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/Mainnet/DeployUniV3Adaptor.s.sol:DeployUniV3AdaptorScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployUniV3AdaptorScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    UniswapV3Adaptor private uniswapV3Adaptor;
    address private positionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address private tracker = 0xf2854d84D9Dd27eCcD6aB20b3F66111a51bb56d2;

    function run() external {
        vm.startBroadcast();

        uniswapV3Adaptor = new UniswapV3Adaptor(positionManager, tracker);

        vm.stopBroadcast();
    }
}
