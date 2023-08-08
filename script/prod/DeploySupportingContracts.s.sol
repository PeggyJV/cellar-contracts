// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeploySupportingContracts.s.sol:DeploySupportingContractsScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeploySupportingContractsScript is Script, MainnetAddresses {
    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address public sommDeployerDeployer = 0x61bfcdAFA35999FA93C10Ec746589EB93817a8b9;

    Deployer public deployer = Deployer(deployerAddress);
    ERC4626SharePriceOracle public oracle;

    function run() external {
        address rye = 0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec;
        ERC4626 _target = ERC4626(rye);
        uint64 _heartbeat = 1 days;
        uint64 _deviationTrigger = 0.0010e4;
        uint64 _gracePeriod = 8 * 60 * 60; // 8 hrs
        uint16 _observationsToUse = 7; // TWAA duration is heartbeat * (observationsToUse - 1), so ~6 days.
        address _automationRegistry = 0xd746F3601eA520Baf3498D61e1B7d976DbB33310;
        uint256 startingAnswer = 1.020e18;
        uint256 allowedAnswerChangeLower = 0.8e4;
        uint256 allowedAnswerChangeUpper = 10e4;

        vm.startBroadcast();

        bytes memory creationCode;
        bytes memory constructorArgs;

        creationCode = type(ERC4626SharePriceOracle).creationCode;
        constructorArgs = abi.encode(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

        oracle = ERC4626SharePriceOracle(
            deployer.deployContract("Real Yield Eth Share Price Oracle V0.0", creationCode, constructorArgs, 0)
        );

        vm.stopBroadcast();
    }
}
