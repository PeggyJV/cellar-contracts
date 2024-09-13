// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import "test/resources/Arbitrum/ArbitrumAddressesPeggyJV.sol";
/**
 * @dev Run
 *
 source .env && forge script script/Arbitrum/peggyjv_production/InitializePriceOracle.s.sol:InitializePriceOracle --evm-version london --with-gas-price 1000000 --slow --broadcast --private-key $PRIVATE_KEY

 */

contract InitializePriceOracle is Script, ArbitrumAddresses {
    using SafeTransferLib for ERC20;

    uint256 public privateKey;

    address internal contractAddress = 0xDDF603866d6d8D207C6200552655Df1eBdE5a641;
    uint96 internal initialUpkeepFunds = 1e18;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("arbitrum");
    }

    function run() external {
        vm.startBroadcast(privateKey);

        ERC4626SharePriceOracle contractInstance = ERC4626SharePriceOracle(contractAddress);
        LINK.safeApprove(contractAddress, initialUpkeepFunds);
        contractInstance.initialize(initialUpkeepFunds);

        vm.stopBroadcast();
    }
}
