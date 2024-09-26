// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import "../../../src/Registry.sol";


/**
 * @dev Run
 *
 source .env && forge script script/Arbitrum/peggyjv_production/RegisterAddress.s.sol:RegisterAddress --evm-version london --with-gas-price 20000000 --slow --broadcast --private-key $PRIVATE_KEY

 */

contract RegisterAddress is Script {
    using SafeTransferLib for ERC4626;
    address internal registryAddress = 0xc5bF3145B7Ab457c08352c02703197174E79D100;

    uint256 internal privateKey;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("arbitrum");
    }

    function run() external {
        vm.startBroadcast(privateKey);

        address cellar = 0x01a4A3E1E730D245F210EebC6aEE54F2381CAC63;
        address sharePriceOracle = 0xDDF603866d6d8D207C6200552655Df1eBdE5a641;

        Registry registry = Registry(registryAddress);

        registry.register(cellar);
        registry.register(sharePriceOracle);

        vm.stopBroadcast();
    }
}
