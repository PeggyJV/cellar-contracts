// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";

import { CellarWithShareLockPeriod } from "src/base/permutations/CellarWithShareLockPeriod.sol";
import { Registry } from "src/Registry.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployCellarWithShareLockPeriod.s.sol:DeployCellarWithShareLockPeriodScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployCellarWithShareLockPeriodScript is Script, MainnetAddresses {
    Deployer public deployer = Deployer(deployerAddress);

    function run() external {
        vm.startBroadcast();

        address owner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
        Registry registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
        ERC20 asset = USDC;
        string memory name = "ETH Trend Growth";
        string memory symbol = "ETHGROWTH";
        uint32 holdingPosition = 3; // Vanilla USDC
        bytes memory holdingPositionConfig = abi.encode(0);
        uint256 initialDeposit = 1e6;
        uint64 strategistPlatformCut = 0.75e18;
        uint192 shareSupplyCap = type(uint192).max;

        // USDC.approve(deployer.getAddress(string.concat(name, " V0.0")), initialDeposit);

        CellarWithShareLockPeriod cellar = _createCellarWithShareLockPeriod(
            owner,
            registry,
            asset,
            name,
            symbol,
            holdingPosition,
            holdingPositionConfig,
            initialDeposit,
            strategistPlatformCut,
            shareSupplyCap
        );

        cellar.transferOwnership(devStrategist);

        vm.stopBroadcast();
    }

    function _createCellarWithShareLockPeriod(
        address _owner,
        Registry _registry,
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint32 _holdingPosition,
        bytes memory _holdingPositionConfig,
        uint256 _initialDeposit,
        uint64 _strategistPlatformCut,
        uint192 _shareSupplyCap
    ) internal returns (CellarWithShareLockPeriod) {
        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithShareLockPeriod).creationCode;
        constructorArgs = abi.encode(
            _owner,
            _registry,
            _asset,
            _name,
            _symbol,
            _holdingPosition,
            _holdingPositionConfig,
            _initialDeposit,
            _strategistPlatformCut,
            _shareSupplyCap
        );

        return
            CellarWithShareLockPeriod(
                deployer.deployContract(string.concat(_name, " V0.0"), creationCode, constructorArgs, 0)
            );
    }
}
