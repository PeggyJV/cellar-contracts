// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {WstEthExtension, PriceRouter} from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Mainnet/production/DeployWstEthExtension.s.sol:DeployWstEthExtensionScript --with-gas-price 30000000000 --slow --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployWstEthExtensionScript is Script {
    uint256 public privateKey;

    WstEthExtension public extension;
    PriceRouter public priceRouter = PriceRouter(0x693799805B502264f9365440B93C113D86a4fFF5);

    function setUp() external {
        privateKey = vm.envUint("SEVEN_SEAS_PRIVATE_KEY");
    }

    function run() external {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(privateKey);

        extension = new WstEthExtension(priceRouter);

        vm.stopBroadcast();
    }
}
