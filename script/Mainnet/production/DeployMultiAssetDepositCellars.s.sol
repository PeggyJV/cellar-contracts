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

    address public sommDev = 0x6d3655EE04820f4385a910FD1898d4Ec6241F520;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit public crvUsdCellar;
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public morphoBlueCellar;
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public stakewiseCellar;
    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport public staderCellar;
    CellarWithOracleWithBalancerFlashLoans public maxiUsdc;
    CellarWithOracleWithBalancerFlashLoans public maxiUsdt;

    // Positions.
    uint32 wethPositionId = 1;
    uint32 usdcPositionId = 3;
    uint32 usdtPositionId = 5;
    uint32 crvUsdPositionId = 13;

    function run() external {
        vm.startBroadcast();

        // Create CRVUSD Cellar.
        crvUsdCellar = _createCellarNoNativeSupport(
            "Turbo CRVUSD",
            "TurboCRVUSD",
            CRVUSD,
            crvUsdPositionId,
            abi.encode(0),
            0.01e18,
            0.8e18
        );

        // 7 day Time weighted average
        ERC4626SharePriceOracle.ConstructorArgs memory args;
        args._target = crvUsdCellar;
        args._heartbeat = 1 days;
        args._deviationTrigger = 0.0050e4;
        args._gracePeriod = 1 days / 2; // If 3 days change to 1 days / 4.
        args._observationsToUse = 8; // If 3 days change to 4.
        args._automationRegistry = automationRegistryV2;
        args._automationRegistrar = automationRegistrarV2;
        args._automationAdmin = devStrategist;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.8e4;
        args._allowedAnswerChangeUpper = 1.2e4;
        args._sequencerUptimeFeed = address(0);
        args._sequencerGracePeriod = 0;
        _createSharePriceOracle("TurboCRVUSD Share Price Oracle V0.0", args);

        crvUsdCellar.transferOwnership(devStrategist);

        // Create Morpho Blue Cellar.
        morphoBlueCellar = _createCellarWithNativeSupport(
            "Morpho ETH Maximizer",
            "MaxMorphoETH",
            WETH,
            wethPositionId,
            abi.encode(0),
            0.0001e18,
            0.8e18
        );

        // 3 day Time weighted average
        args._target = morphoBlueCellar;
        args._heartbeat = 1 days;
        args._deviationTrigger = 0.0050e4;
        args._gracePeriod = 1 days / 4;
        args._observationsToUse = 4;
        args._automationRegistry = automationRegistryV2;
        args._automationRegistrar = automationRegistrarV2;
        args._automationAdmin = devStrategist;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.5e4;
        args._allowedAnswerChangeUpper = 3e4;
        args._sequencerUptimeFeed = address(0);
        args._sequencerGracePeriod = 0;
        _createSharePriceOracle("Morpho ETH Maximizer Share Price Oracle V0.0", args);

        morphoBlueCellar.transferOwnership(devStrategist);

        // Create Stake Wise Cellar.
        stakewiseCellar = _createCellarWithNativeSupport(
            "Turbo OSETH",
            "TurboOSETH",
            WETH,
            wethPositionId,
            abi.encode(0),
            0.0001e18,
            0.8e18
        );

        // 3 day Time weighted average
        args._target = stakewiseCellar;
        args._heartbeat = 1 days;
        args._deviationTrigger = 0.0050e4;
        args._gracePeriod = 1 days / 4;
        args._observationsToUse = 4;
        args._automationRegistry = automationRegistryV2;
        args._automationRegistrar = automationRegistrarV2;
        args._automationAdmin = devStrategist;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.8e4;
        args._allowedAnswerChangeUpper = 1.2e4;
        args._sequencerUptimeFeed = address(0);
        args._sequencerGracePeriod = 0;
        _createSharePriceOracle("TurboOSETH Share Price Oracle V0.0", args);

        stakewiseCellar.transferOwnership(devStrategist);

        // Create Stader Cellar.
        staderCellar = _createCellarWithNativeSupport(
            "Turbo ETHX",
            "TurboETHX",
            WETH,
            wethPositionId,
            abi.encode(0),
            0.0001e18,
            0.8e18
        );

        // 3 day Time weighted average
        args._target = staderCellar;
        args._heartbeat = 1 days;
        args._deviationTrigger = 0.0050e4;
        args._gracePeriod = 1 days / 4;
        args._observationsToUse = 4;
        args._automationRegistry = automationRegistryV2;
        args._automationRegistrar = automationRegistrarV2;
        args._automationAdmin = devStrategist;
        args._link = address(LINK);
        args._startingAnswer = 1e18;
        args._allowedAnswerChangeLower = 0.8e4;
        args._allowedAnswerChangeUpper = 1.2e4;
        args._sequencerUptimeFeed = address(0);
        args._sequencerGracePeriod = 0;
        _createSharePriceOracle("TurboETHX Share Price Oracle V0.0", args);

        staderCellar.transferOwnership(devStrategist);

        // Deploy Staking Contracts.
        _createStakingContract(crvUsdCellar, "TurboCRVUSD Staking Contract V0.0");
        _createStakingContract(morphoBlueCellar, "Morpho ETH Maximizer Staking Contract V0.0");
        _createStakingContract(stakewiseCellar, "TurboOSETH Staking Contract V0.0");
        _createStakingContract(staderCellar, "TurboETHX Staking Contract V0.0");

        // // Create Yield Maxi USDC Cellar.
        // maxiUsdc = _createCellar(
        //     "YieldMAXI USDC",
        //     "YieldMAXIUSDC",
        //     USDC,
        //     usdcPositionId,
        //     abi.encode(0),
        //     0.01e6,
        //     0.8e18
        // );

        // args._target = maxiUsdc;
        // args._heartbeat = 1 days;
        // args._deviationTrigger = 0.0050e4;
        // args._gracePeriod = 1 days / 4;
        // args._observationsToUse = 4;
        // args._automationRegistry = automationRegistryV2;
        // args._automationRegistrar = automationRegistrarV2;
        // args._automationAdmin = devStrategist;
        // args._link = address(LINK);
        // args._startingAnswer = 1e18;
        // args._allowedAnswerChangeLower = 0.8e4;
        // args._allowedAnswerChangeUpper = 1.2e4;
        // args._sequencerUptimeFeed = address(0);
        // args._sequencerGracePeriod = 0;
        // _createSharePriceOracle("YieldMAXIUSDC Share Price Oracle V0.0", args);

        // // Create Yield Maxi USDT Cellar.
        // maxiUsdt = _createCellar(
        //     "YieldMAXI USDT",
        //     "YieldMAXIUSDT",
        //     USDT,
        //     usdtPositionId,
        //     abi.encode(0),
        //     0.01e6,
        //     0.8e18
        // );

        // args._target = maxiUsdt;
        // args._heartbeat = 1 days;
        // args._deviationTrigger = 0.0050e4;
        // args._gracePeriod = 1 days / 4;
        // args._observationsToUse = 4;
        // args._automationRegistry = automationRegistryV2;
        // args._automationRegistrar = automationRegistrarV2;
        // args._automationAdmin = devStrategist;
        // args._link = address(LINK);
        // args._startingAnswer = 1e18;
        // args._allowedAnswerChangeLower = 0.8e4;
        // args._allowedAnswerChangeUpper = 1.2e4;
        // args._sequencerUptimeFeed = address(0);
        // args._sequencerGracePeriod = 0;
        // _createSharePriceOracle("YieldMAXIUSDT Share Price Oracle V0.0", args);

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
        string memory nameToUse = string.concat(cellarName, " V0.0");
        address cellarAddress = deployer.getAddress(nameToUse);
        holdingAsset.approve(cellarAddress, initialDeposit);

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
        string memory nameToUse = string.concat(cellarName, " V0.0");
        address cellarAddress = deployer.getAddress(nameToUse);
        holdingAsset.approve(cellarAddress, initialDeposit);

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
