// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

import { Cellar } from "src/base/Cellar.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeploySharePriceOracles.s.sol:DeploySharePriceOraclesScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeploySharePriceOraclesScript is Script, MainnetAddresses {
    Deployer public deployer = Deployer(deployerAddress);

    Cellar public ryusd = Cellar(0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E);
    Cellar public fraximal = Cellar(0xDBe19d1c3F21b1bB250ca7BDaE0687A97B5f77e6);

    function run() external {
        vm.startBroadcast();

        uint64 heartbeat = 1 days;
        uint64 deviationTrigger = 0.0010e4;
        uint64 gracePeriod = 1 days / 6;
        uint16 observationsToUse = 4;
        uint216 startingAnswer = 1e18;
        uint256 allowedAnswerChangeLower = 0.8e4;
        uint256 allowedAnswerChangeUpper = 10e4;
        _createSharePriceOracle(
            "Real Yield USD Share Price Oracle V0.0",
            address(ryusd),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

        _createSharePriceOracle(
            "FRAXIMAL Share Price Oracle V0.0",
            address(fraximal),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

        vm.stopBroadcast();
    }

    function _createSharePriceOracle(
        string memory _name,
        address _target,
        uint64 _heartbeat,
        uint64 _deviationTrigger,
        uint64 _gracePeriod,
        uint16 _observationsToUse,
        uint216 _startingAnswer,
        uint256 _allowedAnswerChangeLower,
        uint256 _allowedAnswerChangeUpper
    ) public returns (ERC4626SharePriceOracle) {
        bytes memory creationCode;
        bytes memory constructorArgs;
        {
            creationCode = type(ERC4626SharePriceOracle).creationCode;
            constructorArgs = abi.encode(
                _target,
                _heartbeat,
                _deviationTrigger,
                _gracePeriod,
                _observationsToUse,
                automationRegistryV2,
                automationRegistrarV2,
                devStrategist,
                address(LINK),
                _startingAnswer,
                _allowedAnswerChangeLower,
                _allowedAnswerChangeUpper
            );
        }

        return ERC4626SharePriceOracle(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }
}
