// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

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
 *      `source .env && forge script script/prod/DeployStaking.s.sol:DeployStakingScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployStakingScript is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    // Turbo GHO.
    ERC20 public stakingToken = ERC20(0x0C190DEd9Be5f512Bd72827bdaD4003e9Cc7975C);

    CellarStaking public staker;

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;

        address _owner = devStrategist;
        ERC20 _stakingToken = stakingToken;
        ERC20 _distributionToken = ERC20(0xa670d7237398238DE01267472C6f13e5B8010FD1); // somm
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
        priceRouter = PriceRouter(
            deployer.deployContract("Turbo GHO Staking Contract V0.0", creationCode, constructorArgs, 0)
        );
        vm.stopBroadcast();
    }
}
