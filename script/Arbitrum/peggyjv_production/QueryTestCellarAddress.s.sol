// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";
import { ArbitrumAddresses } from "test/resources/Arbitrum/ArbitrumAddressesPeggyJV.sol";
import "forge-std/Script.sol";
import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.sol";
import { ContractDeploymentNames } from "resources/PeggyJVContractDeploymentNames.sol";

/**
 * @dev Run
 *       source .env && forge script script/Arbitrum/peggyjv_production/QueryTestCellarAddress.s.sol:QueryRYUSDAddress --evm-version london --with-gas-price 100000000 --slow --broadcast --etherscan-api-key $ARBISCAN_KEY --verify  --private-key $PRIVATE_KEY

 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */

contract QueryRYUSDAddress is Script, ArbitrumAddresses, ContractDeploymentNames {
    uint256 public privateKey;

    Deployer public deployer = Deployer(deployerAddress);
    address public ryusd_address = address(0);

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit public RYUSD;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("arbitrum");
        ryusd_address = deployer.getAddress(realYieldUsdName);
    }

    function run() external {
        vm.startBroadcast();
        console.log("RYUSD address: %s", ryusd_address);
        vm.stopBroadcast();
    }
}
