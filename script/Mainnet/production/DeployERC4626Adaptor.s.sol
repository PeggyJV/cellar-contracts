// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {ERC4626Adaptor} from "src/modules/adaptors/ERC4626Adaptor.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Mainnet/production/DeployERC4626Adaptor.s.sol:DeployERC4626AdaptorScript --with-gas-price 30000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployERC4626AdaptorScript is Script {
    uint256 public privateKey;
    ERC4626Adaptor private erc4626Adaptor;

    function setUp() external {
        privateKey = vm.envUint("SEVEN_SEAS_PRIVATE_KEY");
    }

    function run() external {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(privateKey);

        erc4626Adaptor = new ERC4626Adaptor();

        vm.stopBroadcast();
    }
}
