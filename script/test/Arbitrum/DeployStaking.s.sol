// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { CellarStaking } from "src/modules/staking/CellarStaking.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/test/Arbitrum/DeployStaking.s.sol:DeployStakingScript --rpc-url $ARBITRUM_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 100000000 --verify --etherscan-api-key $ARBISCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployStakingScript is Script, MainnetAddresses {
    using Math for uint256;

    Deployer public deployer = Deployer(deployerAddress);

    // Test RYUSD.
    ERC20 public stakingToken = ERC20(0xA73B0B48E26E4B8B24CeaD149252cc275deE99A6);

    CellarStaking public staker;

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;

        address _owner = 0xe8aF5E8A7DC2B6B88805cfF1bb3D63b8Ba5D6d30;
        ERC20 _stakingToken = stakingToken;
        ERC20 _distributionToken = ERC20(0x4e914bbDCDE0f455A8aC9d59d3bF739c46287Ed2); // axlSOMM
        uint256 _epochDuration = 3 days;
        uint256 shortBoost = 0.10e18;
        uint256 mediumBoost = 0.30e18;
        uint256 longBoost = 0.50e18;
        uint256 shortBoostTime = 7 days;
        uint256 mediumBoostTime = 14 days;
        uint256 longBoostTime = 21 days;

        vm.startBroadcast();

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
        staker = CellarStaking(
            deployer.deployContract("Test RYUSD Staking Contract V0.0", creationCode, constructorArgs, 0)
        );

        vm.stopBroadcast();
    }
}
