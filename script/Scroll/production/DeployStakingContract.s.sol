// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Deployer} from "src/Deployer.sol";
import {ScrollAddresses} from "test/resources/Scroll/ScrollAddresses.sol";
import {ContractDeploymentNames} from "resources/ContractDeploymentNames.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {CellarStaking} from "src/modules/staking/CellarStaking.sol";

import {PositionIds} from "resources/PositionIds.sol";
import {Math} from "src/utils/Math.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

/**
 *  source .env && forge script script/Scroll/production/DeployStakingContract.s.sol:DeployStakingContractScript --evm-version london --with-gas-price 100000000 --slow --broadcast --etherscan-api-key $ARBISCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployStakingContractScript is Script, ScrollAddresses, ContractDeploymentNames, PositionIds {
    using Math for uint256;
    using stdJson for string;

    uint256 public privateKey;
    Deployer public deployer = Deployer(deployerAddress);
    ERC20 public ScrollRye = ERC20(0xd3BB04423b0c98aBc9d62f201212f44dC2611200);

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
    }

    function run() external {
        vm.createSelectFork("scroll");
        vm.startBroadcast(privateKey);

        _createStakingContract(ScrollRye, "Scroll RYE Staking V 0.0");

        vm.stopBroadcast();
    }

    function _createStakingContract(ERC20 _stakingToken, string memory _name) internal returns (CellarStaking) {
        bytes memory creationCode;
        bytes memory constructorArgs;

        address _owner = devStrategist;
        ERC20 _distributionToken = AXL_SOMM;
        uint256 _epochDuration = 3 days;
        uint256 shortBoost = 0.1e18;
        uint256 mediumBoost = 0.3e18;
        uint256 longBoost = 0.5e18;
        uint256 shortBoostTime = 7 days;
        uint256 mediumBoostTime = 14 days;
        uint256 longBoostTime = 21 days;

        // Deploy the staking contract.
        creationCode = type(CellarStaking).creationCode;
        constructorArgs = abi.encode(
            _owner,
            _stakingToken,
            _distributionToken,
            _epochDuration,
            shortBoost,
            mediumBoost,
            longBoost,
            shortBoostTime,
            mediumBoostTime,
            longBoostTime
        );
        return CellarStaking(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }
}
