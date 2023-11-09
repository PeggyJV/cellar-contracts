// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Registry } from "src/Registry.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { CellarWithOracleWithBalancerFlashLoans } from "src/base/permutations/CellarWithOracleWithBalancerFlashLoans.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";
import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/FixTurboSOMMCellar.s.sol:FixTurboSOMMCellarScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract FixTurboSOMMCellarScript is Script, MainnetAddresses {
    using Math for uint256;

    address public automationAdmin = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);

    address turboSommCellar = 0x5195222f69c5821f8095ec565E71e18aB6A2298f;

    function run() external {
        vm.startBroadcast();

        // Deploy vesting adaptor.
        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(VestingSimpleAdaptor).creationCode;
        // constructorArgs = abi.encode(0); // None
        deployer.deployContract("VestingSimpleAdaptor V 1.1", creationCode, constructorArgs, 0);

        uint64 heartbeat = 1 days / 24;
        uint64 deviationTrigger = 0.0050e4;
        uint64 gracePeriod = 10 days;
        uint16 observationsToUse = 2;
        uint216 startingAnswer = 1e18;
        uint256 allowedAnswerChangeLower = 0.5e4;
        uint256 allowedAnswerChangeUpper = 5e4;

        _createSharePriceOracle(
            "Turbo SOMM Share Price Oracle V0.2",
            address(turboSommCellar),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            automationAdmin,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

        heartbeat = 1 days;
        deviationTrigger = 0.0050e4;
        gracePeriod = 1 days / 4;
        observationsToUse = 4;
        startingAnswer = 1e18;
        allowedAnswerChangeLower = 0.5e4;
        allowedAnswerChangeUpper = 5e4;

        _createSharePriceOracle(
            "Turbo SOMM Share Price Oracle V0.3",
            address(turboSommCellar),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            automationAdmin,
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
        address _automationAdmin,
        uint216 _startingAnswer,
        uint256 _allowedAnswerChangeLower,
        uint256 _allowedAnswerChangeUpper
    ) internal returns (ERC4626SharePriceOracle) {
        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(ERC4626SharePriceOracle).creationCode;
        constructorArgs = abi.encode(
            ERC4626(_target),
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            automationRegistryV2,
            automationRegistrarV2,
            _automationAdmin,
            address(LINK),
            _startingAnswer,
            _allowedAnswerChangeLower,
            _allowedAnswerChangeUpper
        );

        return ERC4626SharePriceOracle(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }
}
