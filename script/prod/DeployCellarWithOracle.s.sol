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

import { CellarWithOracleWithBalancerFlashLoans } from "src/base/permutations/CellarWithOracleWithBalancerFlashLoans.sol";

import { StEthExtension } from "src/modules/price-router/Extensions/Lido/StEthExtension.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { RedstonePriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";
import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";

import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

import { BalancerPoolAdaptor } from "src/modules/adaptors/Balancer/BalancerPoolAdaptor.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployCellarWithOracle.s.sol:DeployCellarWithOracleScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployCellarWithOracleScript is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    address public erc20Adaptor = 0xa5D315eA3D066160651459C4123ead9264130BFd; // already trusted
    address public uniswapAdaptor = 0xC74fFa211A8148949a77ec1070Df7013C8D5Ce92; // already trusted
    address public vestingSimpleAdaptor = 0x3b98BA00f981342664969e609Fb88280704ac479; // already trusted
    address public aaveV3ATokenAdaptor = 0x76Cef5606C8b6bA38FE2e3c639E1659afA530b47; // already trusted
    address public aaveV3DebtTokenAdaptor = 0x6DEd49176a69bEBf8dC1a4Ea357faa555df188f7; // already trusted
    address public MORPHO_AAVEV3_P2P_ADAPTOR_NAME = 0x0Dd5d6bA17f223b51f46D4Ed5231cFBf929cFdEe; // already trusted
    address public MORPHO_AAVEV3_ATOKEN_ADAPTOR_NAME = 0xB46E8a03b1AaFFFb50f281397C57b5B87080363E;
    address public MORPHO_AAVEV3_DEBTTOKEN_ADAPTOR_NAME = 0x25a61f771aF9a38C10dDd93c2bBAb39a88926fa9;
    address public MORPHO_AAVEV2_ATOKEN_ADAPTOR_NAME = 0xD11142d10f4E5f12A97E6702cc43E598dC77B2D6; // already trusted
    address public MORPHO_AAVEV2_DEBTTOKEN_ADAPTOR_NAME = 0x407D5489F201013EE6A6ca20fCcb05047C548138; // already trusted
    address public AAVE_ENABLE_ASSET_AS_COLLATERAL_ADAPTOR_NAME = 0x724FEb5819D1717Aec5ADBc0974a655a498b2614;
    address public AAVE_ATOKEN_ADAPTOR_NAME = 0xe3A3b8AbbF3276AD99366811eDf64A0a4b30fDa2;
    address public AAVE_DEBTTOKEN_ADAPTOR_NAME = 0xeC86ac06767e911f5FdE7cba5D97f082C0139C01;
    address public ONE_INCH_ADAPTOR_NAME = 0xB8952ce4010CFF3C74586d712a4402285A3a3AFb; // already trusted
    address public ZEROX_ADAPTOR_NAME = 0x1039a9b61DFF6A3fb8dbF4e924AA749E5cFE35ef; // already trusted
    address public feesAndReservesAdaptor = 0x647d264d800A2461E594796af61a39b7735d8933;

    CellarWithOracleWithBalancerFlashLoans public stethCellar;

    // Positions.
    uint32 wethPositionId = 1; // in there already
    uint32 wstethPositionId = 9; // in there already
    uint32 stethPositionId = 10; // in there already
    uint32 WSTETH_WETH_PositionId = 1_000_007;
    uint32 aV3WETHPosition = 2000005; // in there already
    uint32 aV3WstEthPosition = 2000006; // in there already
    uint32 dV3WethPosition = 2500006; // in there already
    uint32 dV3WstEthPosition = 2500007; // in there already
    uint32 aV2WethPosition = 2000007; // in there already
    uint32 aV2StethPosition = 2000008; // in there already
    uint32 dV2WethPosition = 2500008; // in there already
    uint32 morphoV2AWeth = 5000001; // in there already
    uint32 morphoV3P2PWeth = 5000002; // in there already
    uint32 morphoV2ASteth = 5000006; // in there already
    uint32 morphoV3AWsteth = 5000007; // in there already
    uint32 morphoV2DebtWeth = 5500004; // in there already
    uint32 morphoV3DebtWeth = 5500005; // in there already

    uint32 wstEthVestor = 100000003;

    function run() external {
        vm.startBroadcast();

        // Create Cellars and Share Price Oracles.
        address newCellar = deployer.getAddress("Turbo STETH V0.0");
        WETH.approve(newCellar, 0.0001e18);
        stethCellar = _createCellar(
            "Turbo STETH",
            "TurboSTETH",
            WETH,
            wethPositionId,
            abi.encode(0),
            0.0001e18,
            0.75e18
        );

        uint64 heartbeat = 1 days;
        uint64 deviationTrigger = 0.0030e4;
        uint64 gracePeriod = 1 days / 6;
        uint16 observationsToUse = 4;
        address automationRegistry = 0x6593c7De001fC8542bB1703532EE1E5aA0D458fD;
        uint216 startingAnswer = 1e18;
        uint256 allowedAnswerChangeLower = 0.8e4;
        uint256 allowedAnswerChangeUpper = 10e4;
        _createSharePriceOracle(
            "Turbo STETH Share Price Oracle V0.0",
            address(stethCellar),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            automationRegistry,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

        heartbeat = 1 days;
        deviationTrigger = 0.0030e4;
        gracePeriod = 1 days / 4;
        observationsToUse = 6;
        automationRegistry = 0x6593c7De001fC8542bB1703532EE1E5aA0D458fD;
        startingAnswer = 1e18;
        allowedAnswerChangeLower = 0.8e4;
        allowedAnswerChangeUpper = 10e4;
        _createSharePriceOracle(
            "Turbo STETH Share Price Oracle V0.1",
            address(stethCellar),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            automationRegistry,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

        stethCellar.addAdaptorToCatalogue(uniswapAdaptor);
        stethCellar.addAdaptorToCatalogue(vestingSimpleAdaptor);
        stethCellar.addAdaptorToCatalogue(aaveV3ATokenAdaptor);
        stethCellar.addAdaptorToCatalogue(aaveV3DebtTokenAdaptor);
        stethCellar.addAdaptorToCatalogue(MORPHO_AAVEV3_P2P_ADAPTOR_NAME);
        // stethCellar.addAdaptorToCatalogue(MORPHO_AAVEV3_ATOKEN_ADAPTOR_NAME);
        // stethCellar.addAdaptorToCatalogue(MORPHO_AAVEV3_DEBTTOKEN_ADAPTOR_NAME);
        // stethCellar.addAdaptorToCatalogue(MORPHO_AAVEV2_ATOKEN_ADAPTOR_NAME);
        // stethCellar.addAdaptorToCatalogue(MORPHO_AAVEV2_DEBTTOKEN_ADAPTOR_NAME);
        // stethCellar.addAdaptorToCatalogue(AAVE_ENABLE_ASSET_AS_COLLATERAL_ADAPTOR_NAME);
        // stethCellar.addAdaptorToCatalogue(AAVE_ATOKEN_ADAPTOR_NAME);
        // stethCellar.addAdaptorToCatalogue(AAVE_DEBTTOKEN_ADAPTOR_NAME);
        // stethCellar.addAdaptorToCatalogue(ONE_INCH_ADAPTOR_NAME);
        // stethCellar.addAdaptorToCatalogue(ZEROX_ADAPTOR_NAME);
        // stethCellar.addAdaptorToCatalogue(feesAndReservesAdaptor);

        // stethCellar.addPositionToCatalogue(wstethPositionId);
        // stethCellar.addPositionToCatalogue(stethPositionId);
        // stethCellar.addPositionToCatalogue(WSTETH_WETH_PositionId);
        // stethCellar.addPositionToCatalogue(aV3WETHPosition);
        // stethCellar.addPositionToCatalogue(aV3WstEthPosition);
        // stethCellar.addPositionToCatalogue(dV3WethPosition);
        // stethCellar.addPositionToCatalogue(dV3WstEthPosition);
        // stethCellar.addPositionToCatalogue(aV2WethPosition);
        // stethCellar.addPositionToCatalogue(aV2StethPosition);
        // stethCellar.addPositionToCatalogue(dV2WethPosition);
        // stethCellar.addPositionToCatalogue(morphoV2AWeth);
        // stethCellar.addPositionToCatalogue(morphoV3P2PWeth);
        // stethCellar.addPositionToCatalogue(morphoV2ASteth);
        // stethCellar.addPositionToCatalogue(morphoV3AWsteth);
        // stethCellar.addPositionToCatalogue(morphoV2DebtWeth);
        // stethCellar.addPositionToCatalogue(morphoV3DebtWeth);

        vm.stopBroadcast();
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
        holdingAsset.approve(cellarAddress, initialDeposit);

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

    function _createSharePriceOracle(
        string memory _name,
        address _target,
        uint64 _heartbeat,
        uint64 _deviationTrigger,
        uint64 _gracePeriod,
        uint16 _observationsToUse,
        address _automationRegistry,
        uint216 _startingAnswer,
        uint256 _allowedAnswerChangeLower,
        uint256 _allowedAnswerChangeUpper
    ) internal returns (ERC4626SharePriceOracle) {
        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(ERC4626SharePriceOracle).creationCode;
        constructorArgs = abi.encode(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry,
            _startingAnswer,
            _allowedAnswerChangeLower,
            _allowedAnswerChangeUpper
        );

        return ERC4626SharePriceOracle(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }
}
