// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {IPAllActionV3} from "@pendle/contracts/interfaces/IPAllActionV3.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Mainnet/production/HarvestPendle.s.sol:HarvestPendleScript --with-gas-price 30000000000 --slow --broadcast
 */
contract HarvestPendleScript is Script {
    uint256 public privateKey;
    IPAllActionV3 public pendleRouter = IPAllActionV3(0x00000000005BBB0EF59571E58418F9a4357b68A0);
    address vault = 0xeA1A6307D9b18F8d1cbf1c3Dd6aad8416C06a221;

    function setUp() external {
        privateKey = vm.envUint("SEVEN_SEAS_PRIVATE_KEY");
    }

    function run() external {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(privateKey);
        address[] memory sys = new address[](1);
        sys[0] = 0xAC0047886a985071476a1186bE89222659970d65;
        address[] memory yts = new address[](1);
        yts[0] = 0xfb35Fd0095dD1096b1Ca49AD44d8C5812A201677;
        address[] memory markets = new address[](1);
        markets[0] = 0xF32e58F92e60f4b0A37A69b95d642A471365EAe8;

        pendleRouter.redeemDueInterestAndRewards(vault, sys, yts, markets);

        vm.stopBroadcast();
    }
}
