// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Deployer} from "src/Deployer.sol";
import {Registry} from "src/Registry.sol";
import {ProtocolFeeCollector} from "src/modules/ProtocolFeeCollector.sol";
import {PriceRouter} from "src/modules/price-router/PriceRouter.sol";
import {SequencerPriceRouter} from "src/modules/price-router/permutations/SequencerPriceRouter.sol";
import {ArbitrumAddresses} from "test/resources/Arbitrum/ArbitrumAddresses.sol";
import {ContractDeploymentNames} from "resources/ContractDeploymentNames.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Cellar} from "src/base/Cellar.sol";
import {PositionIds} from "resources/PositionIds.sol";
import {Math} from "src/utils/Math.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Arbitrum/production/TransferOwnershipOfProtocol.s.sol:TransferOwnershipOfProtocolScript --evm-version london --with-gas-price 100000000 --slow --broadcast --etherscan-api-key $ARBISCAN_KEY --verify
 * If you need to verify contracts after deployment run the following command
 *  source .env && forge script script/Arbitrum/production/TransferOwnershipOfProtocol.s.sol:TransferOwnershipOfProtocolScript --evm-version london --etherscan-api-key $ARBISCAN_KEY --verify --resume --rpc-url $ARBITRUM_RPC_URL
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract TransferOwnershipOfProtocolScript is Script, ArbitrumAddresses, ContractDeploymentNames, PositionIds {
    uint256 public privateKey;
    Deployer public deployer = Deployer(deployerAddress);
    Registry public registry;
    PriceRouter public priceRouter;
    ProtocolFeeCollector public protocolFeeCollector;
    TimelockController public timelock;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("arbitrum");
        registry = Registry(deployer.getAddress(registryName));
        priceRouter = PriceRouter(deployer.getAddress(priceRouterName));
        protocolFeeCollector = ProtocolFeeCollector(deployer.getAddress(protocolFeeCollectorName));
        timelock = TimelockController(payable(deployer.getAddress(timelockOwnerName)));
        require(address(timelock) == 0xD966233B04a0561a9C123d520cAe0f27aa92CaDA);
    }

    function run() external {
        vm.startBroadcast(privateKey);

        registry.setAddress(0, multisig);

        registry.transferOwnership(multisig);

        vm.stopBroadcast();
    }
}
