// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";

import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

import { ERC4626SharePriceOracle, ERC20 } from "src/base/ERC4626SharePriceOracle.sol";
import { CellarWithOracleWithBalancerFlashLoans } from "src/base/permutations/CellarWithOracleWithBalancerFlashLoans.sol";

import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";

import { ArbitrumAddresses } from "test/resources/Arbitrum/ArbitrumAddresses.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Arbitrum/test/DeployTestRealYield.s.sol:DeployTestRealYieldScript --rpc-url $ARBITRUM_RPC_URL --evm-version london  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 100000000 --verify --etherscan-api-key $ARBISCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployTestRealYieldScript is Script, ArbitrumAddresses {
    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0x43BD96931A47FBABd50727F6982c796B3C9A974C);
    PriceRouter public priceRouter = PriceRouter(0x6aC423c11bb65B1bc7C5Cf292b22e0CBa125f98A);

    address public erc20Adaptor = 0xcaDe581bD66104B278A2F47a43B05a2db64E871f;
    address public uniswapV3Adaptor = 0x4804534106AE70718aaCBe35710D8d4F553F5bcD;
    address public aaveV3ATokenAdaptor = 0x88fe7C31D26c43B8b0d313e45c3d9d1c300F7e18;
    address public aaveV3DebtTokenAdaptor = 0x76Baff5B49Aa06a1c226Db42cDc6210f3b6658C2;
    address public zeroXAdaptor = 0x48B11b282964AF32AA26A5f83323271e02E7fAF0;
    address public oneInchAdaptor = 0xc64A77Aad4c9e1d78EaDe6Ad204Df751eCD30173;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;

    uint32 public wethPosition = 1;
    uint32 public wstethPosition = 6;
    uint32 public rethPosition = 7;
    uint32 public aV3WethPosition = 2000001;
    uint32 public dV3WethPosition = 2500001;

    // To be added
    uint32 public aV3WstethPosition = 2000006;
    uint32 public aV3RethPosition = 2000007;
    uint32 public wstethWethUniPosition = 1000006;
    uint32 public wethRethUniPosition = 1000007;

    function run() external {
        vm.startBroadcast();

        // Deploy Cellar
        CellarWithOracleWithBalancerFlashLoans cellar = _createCellar(
            "Test Real Yield ETH",
            "TRYE",
            WETH,
            wethPosition,
            abi.encode(true),
            0.0001e18,
            0.8e18
        );

        // Deploy Oracle
        _createSharePriceOracle(
            "Test Real Yield ETH Share Price Oracle V0.0",
            address(cellar),
            2 days,
            0.0050e4,
            1 days / 4,
            3,
            1e18,
            0.8e4,
            1.2e4
        );

        // Add WSTETH pricing
        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        stor.inETH = true;
        uint256 price = uint256(IChainlinkAggregator(WSTETH_ETH_FEED).latestAnswer());
        price = (price * priceRouter.getPriceInUSD(WETH)) / 1e18;
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WSTETH_ETH_FEED);
        priceRouter.addAsset(WSTETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(RETH_ETH_FEED).latestAnswer());
        price = (price * priceRouter.getPriceInUSD(WETH)) / 1e18;
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, RETH_ETH_FEED);
        priceRouter.addAsset(rETH, settings, abi.encode(stor), price);

        // Create RYE positions.
        registry.trustPosition(wstethPosition, erc20Adaptor, abi.encode(WSTETH));
        registry.trustPosition(rethPosition, erc20Adaptor, abi.encode(rETH));
        registry.trustPosition(aV3WstethPosition, aaveV3ATokenAdaptor, abi.encode(aV3WSTETH));
        registry.trustPosition(aV3RethPosition, aaveV3ATokenAdaptor, abi.encode(aV3rETH));
        registry.trustPosition(wstethWethUniPosition, uniswapV3Adaptor, abi.encode(WSTETH, WETH));
        registry.trustPosition(wethRethUniPosition, uniswapV3Adaptor, abi.encode(WETH, rETH));

        cellar.addAdaptorToCatalogue(aaveV3ATokenAdaptor);
        cellar.addAdaptorToCatalogue(aaveV3DebtTokenAdaptor);
        cellar.addAdaptorToCatalogue(uniswapV3Adaptor);

        cellar.addPositionToCatalogue(aV3WstethPosition);
        cellar.addPositionToCatalogue(aV3RethPosition);
        cellar.addPositionToCatalogue(wstethWethUniPosition);
        cellar.addPositionToCatalogue(wethRethUniPosition);
        cellar.addPositionToCatalogue(aV3WethPosition);
        cellar.addPositionToCatalogue(dV3WethPosition);
        cellar.addPositionToCatalogue(wstethPosition);
        cellar.addPositionToCatalogue(rethPosition);

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
            dev0Address,
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
            automationRegistry,
            automationRegistrar,
            devStrategist,
            LINK,
            _startingAnswer,
            _allowedAnswerChangeLower,
            _allowedAnswerChangeUpper
        );

        return ERC4626SharePriceOracle(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }
}
