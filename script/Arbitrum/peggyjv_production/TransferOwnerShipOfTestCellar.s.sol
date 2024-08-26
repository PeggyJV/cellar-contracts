// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";
import { ArbitrumAddresses } from "test/resources/Arbitrum/ArbitrumAddressesPeggyJV.sol";
import "forge-std/Script.sol";
import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.sol";
import { ContractDeploymentNames } from "resources/PeggyJVContractDeploymentNames.sol";

/**
 * @dev Run
 *       script/Arbitrum/peggyjv_production/TransferOwnerShipOfTestCellar.s.sol:TransferOwnerShipScript--evm-version london --with-gas-price 100000000 --slow --broadcast --etherscan-api-key $ARBISCAN_KEY --verify  --private-key $PRIVATE_KEY

 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */

contract TransferOwnerShipScript is Script, ArbitrumAddresses, ContractDeploymentNames {
    uint256 public privateKey;

    Deployer public deployer = Deployer(deployerAddress);

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit public RYUSD;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("arbitrum");
        RYUSD = CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit(deployer.getAddress(realYieldUsdName));
    }

    function run() external {
        vm.startBroadcast(privateKey);
        RYUSD.transferOwnership(axelarProxyV0_0);
        vm.stopBroadcast();
    }
}
