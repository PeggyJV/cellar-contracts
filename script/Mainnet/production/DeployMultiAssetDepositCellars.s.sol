// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { CellarStaking } from "src/modules/staking/CellarStaking.sol";

import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.sol";
import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport.sol";
import { CellarWithOracleWithBalancerFlashLoans } from "src/base/permutations/CellarWithOracleWithBalancerFlashLoans.sol";
import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Mainnet/production/DeployMultiAssetDepositCellars.s.sol:DeployMultiAssetDepositCellarsScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployMultiAssetDepositCellarsScript is Script, MainnetAddresses {
    using Math for uint256;
    using SafeTransferLib for ERC20;

    address public sommDev = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public turboEETH;
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public turboSWETH;
    CellarWithOracleWithBalancerFlashLoans public yieldMaxiUSDT;
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit public RYUSD_2;

    // Positions.
    uint32 wethPositionId = 1;
    uint32 usdcPositionId = 3;
    uint32 usdtPositionId = 5;

    function run() external {
        ERC4626SharePriceOracle.ConstructorArgs memory args;
        // Set all oracles to use 50 bps deviation, 5 day TWAAs with 8 hour grace period.
        // Allowed answer change upper and lower of 1.25x and 0.75x
        args._heartbeat = 1 days;
        args._deviationTrigger = 0.0050e4;
        args._gracePeriod = 1 days / 3;
        args._observationsToUse = 6;
        args._automationRegistry = automationRegistryV2;
        args._automationRegistrar = automationRegistrarV2;
        args._automationAdmin = devStrategist;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.75e4;
        args._allowedAnswerChangeUpper = 1.25e4;
        args._sequencerUptimeFeed = address(0);
        args._sequencerGracePeriod = 0;
        vm.startBroadcast();

        // Create Turbo EETH Cellar.
        turboEETH = _createCellarWithNativeSupport(
            "Turbo EETH", // Name
            "TurboEETH", // Symbol
            WETH,
            wethPositionId,
            abi.encode(0),
            0.0001e18,
            0.8e18
        );

        args._target = turboEETH;
        _createSharePriceOracle("TurboEETH Share Price Oracle V0.0", args);

        // turboEETH.transferOwnership(devStrategist);

        // Create Turbo SWETH Cellar.
        turboSWETH = _createCellarWithNativeSupport(
            "Turbo SWETH",
            "TurboSWETH",
            WETH,
            wethPositionId,
            abi.encode(0),
            0.0001e18,
            0.8e18
        );

        args._target = turboSWETH;
        _createSharePriceOracle("TurboSWETH Share Price Oracle V0.0", args);

        // turboSWETH.transferOwnership(devStrategist);

        // Create Yield Maxi USDT Cellar.
        yieldMaxiUSDT = _createCellar(
            "Yield Maxi USDT",
            "YieldMaxiUSDT",
            USDT,
            usdtPositionId,
            abi.encode(0),
            0.1e6,
            0.8e18
        );

        args._target = yieldMaxiUSDT;
        _createSharePriceOracle("YieldMaxiUSDT Share Price Oracle V0.0", args);

        // yieldMaxiUSDT.transferOwnership(devStrategist);

        // Create RYUSD 2
        RYUSD_2 = _createCellarNoNativeSupport(
            "Real Yield USD 2",
            "RYUSD 2",
            USDC,
            usdcPositionId,
            abi.encode(0),
            0.1e6,
            0.8e18
        );

        args._target = RYUSD_2;
        _createSharePriceOracle("RYUSD_2 Share Price Oracle V0.0", args);

        // RYUSD_2.transferOwnership(devStrategist);

        // Deploy Staking Contracts.
        _createStakingContract(turboEETH, "TurboEETH Staking Contract V0.0");
        _createStakingContract(turboSWETH, "TurboSWETH Staking Contract V0.0");
        _createStakingContract(yieldMaxiUSDT, "YieldMaxiUSDT Staking Contract V0.0");
        _createStakingContract(RYUSD_2, "Real Yield USD Staking Contract V0.0");

        vm.stopBroadcast();
    }

    function _createCellarNoNativeSupport(
        string memory cellarName,
        string memory cellarSymbol,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit) {
        // Approve new cellar to spend assets.
        string memory nameToUse = string.concat(cellarName, " Multi Asset Deposit V0.0");
        address cellarAddress = deployer.getAddress(nameToUse);
        holdingAsset.safeApprove(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit).creationCode;
        constructorArgs = abi.encode(
            sommDev,
            registry,
            holdingAsset,
            cellarName,
            cellarSymbol,
            holdingPosition,
            holdingPositionConfig,
            initialDeposit,
            platformCut,
            type(uint192).max,
            address(vault)
        );

        return
            CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit(
                deployer.deployContract(nameToUse, creationCode, constructorArgs, 0)
            );
    }

    function _createCellarWithNativeSupport(
        string memory cellarName,
        string memory cellarSymbol,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport) {
        // Approve new cellar to spend assets.
        string memory nameToUse = string.concat(cellarName, " Multi Asset Deposit V0.0");
        address cellarAddress = deployer.getAddress(nameToUse);
        holdingAsset.safeApprove(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport).creationCode;
        constructorArgs = abi.encode(
            sommDev,
            registry,
            holdingAsset,
            cellarName,
            cellarSymbol,
            holdingPosition,
            holdingPositionConfig,
            initialDeposit,
            platformCut,
            type(uint192).max,
            address(vault)
        );

        return
            CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport(
                payable(deployer.deployContract(nameToUse, creationCode, constructorArgs, 0))
            );
    }

    function _createSharePriceOracle(
        string memory _name,
        ERC4626SharePriceOracle.ConstructorArgs memory args
    ) internal returns (ERC4626SharePriceOracle) {
        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(ERC4626SharePriceOracle).creationCode;
        constructorArgs = abi.encode(args);

        return ERC4626SharePriceOracle(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }

    function _createCellar(
        string memory cellarName,
        string memory cellarSymbol,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithOracleWithBalancerFlashLoans) {
        // Approve new cellar to spend assets.
        string memory nameToUse = string.concat(cellarName, " V0.0");
        address cellarAddress = deployer.getAddress(nameToUse);
        holdingAsset.safeApprove(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithOracleWithBalancerFlashLoans).creationCode;
        constructorArgs = abi.encode(
            sommDev,
            registry,
            holdingAsset,
            cellarName,
            cellarSymbol,
            holdingPosition,
            holdingPositionConfig,
            initialDeposit,
            platformCut,
            type(uint192).max,
            address(vault)
        );

        return
            CellarWithOracleWithBalancerFlashLoans(
                deployer.deployContract(nameToUse, creationCode, constructorArgs, 0)
            );
    }

    function _createStakingContract(ERC20 _stakingToken, string memory _name) internal returns (CellarStaking) {
        bytes memory creationCode;
        bytes memory constructorArgs;

        address _owner = devStrategist;
        ERC20 _distributionToken = ERC20(0xa670d7237398238DE01267472C6f13e5B8010FD1); // somm
        uint256 _epochDuration = 3 days;
        uint256 shortBoost = 0.10e18;
        uint256 mediumBoost = 0.30e18;
        uint256 longBoost = 0.50e18;
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
