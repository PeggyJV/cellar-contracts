// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";
import { ArbitrumAddresses } from "test/resources/Arbitrum/ArbitrumAddressesPeggyJV.sol";
import "forge-std/Script.sol";
import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.sol";
import { ContractDeploymentNames } from "resources/PeggyJVContractDeploymentNames.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

/**
 * @dev Run
 *       source .env && forge script script/Arbitrum/peggyjv_production/DepositIntoTestCellar.s.sol:DepositIntoTestCellar --evm-version london --with-gas-price 100000000 --slow --broadcast --etherscan-api-key $ARBISCAN_KEY --verify  --private-key $PRIVATE_KEY

 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */

contract DepositIntoTestCellar is Script, ArbitrumAddresses, ContractDeploymentNames {
    uint256 public privateKey;

    Deployer public deployer = Deployer(deployerAddress);
    address public ryusd_address;

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit public RYUSD;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork("arbitrum");
        ryusd_address = deployer.getAddress(realYieldUsdName);
        RYUSD = CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit(ryusd_address);
    }

    function run() external {
        vm.startBroadcast(privateKey);

        USDC.approve(ryusd_address, 100e6);

        address my_address = vm.addr(vm.envUint("PRIVATE_KEY"));

        RYUSD.deposit(100e6, my_address);

        vm.stopBroadcast();
    }
}
