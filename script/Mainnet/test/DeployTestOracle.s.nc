// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { Deployer } from "src/Deployer.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/test/DeployTestOracle.s.sol:DeployTestOracleScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
//  TODO maybe this should be more of a Setup new Adaptor?
contract DeployTestOracleScript is Script {
    function run() external {
        address rye = 0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec;
        ERC4626 _target = ERC4626(rye);
        uint64 _heartbeat = 1 days;
        uint64 _deviationTrigger = 0.0010e4;
        uint64 _gracePeriod = 60 * 60; // 1 hr
        uint16 _observationsToUse = 5; // TWAA duration is heartbeat * (observationsToUse - 1), so ~4 days.
        address _automationRegistry = 0xd746F3601eA520Baf3498D61e1B7d976DbB33310;

        vm.startBroadcast();

        // Setup share price oracle.
        new ERC4626SharePriceOracle(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry,
            1.025e18,
            0.9e4,
            3e4
        );

        vm.stopBroadcast();
    }
}
