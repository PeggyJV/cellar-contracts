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
 *      `source .env && forge script script/prod/DeployCellars.s.sol:DeployCellarsScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployCellarsScript is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    StEthExtension public stEthExtension;
    WstEthExtension public wstEthExtension;
    RedstonePriceFeedExtension public redstonePriceFeedExtension;
    BalancerStablePoolExtension public balancerStablePoolExtension;

    ERC20Adaptor public erc20Adaptor;
    UniswapV3Adaptor public uniswapV3Adaptor;
    UniswapV3PositionTracker public tracker;
    BalancerPoolAdaptor public balancerPoolAdaptor;

    CellarWithOracleWithBalancerFlashLoans public ghoCellar;
    CellarWithOracleWithBalancerFlashLoans public swethCellar;

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    // ERC20 Positions.
    uint32 wethPositionId = 1;
    uint32 wbtcPositionId = 2;
    uint32 usdcPositionId = 3;
    uint32 daiPositionId = 4;
    uint32 usdtPositionId = 5;
    uint32 ghoPositionId = 6;
    uint32 swethPositionId = 7;

    // Uniswap Positions.
    uint32 wETH_swETH_PositionId = 1_000_001;
    uint32 GHO_USDC_PositionId = 1_000_002;
    uint32 GHO_USDT_PositionId = 1_000_003;

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;

        vm.startBroadcast();

        // Deploy ERC20 Adaptor.
        creationCode = type(ERC20Adaptor).creationCode;
        constructorArgs = hex"";
        erc20Adaptor = ERC20Adaptor(deployer.deployContract("ERC20 Adaptor V0.0", creationCode, constructorArgs, 0));

        // Deploy Uniswap Adaptor
        creationCode = type(UniswapV3PositionTracker).creationCode;
        constructorArgs = abi.encode(positionManager);
        tracker = UniswapV3PositionTracker(
            deployer.deployContract("Uniswap V3 Position Tracker V0.0", creationCode, constructorArgs, 0)
        );

        creationCode = type(UniswapV3Adaptor).creationCode;
        constructorArgs = abi.encode(address(positionManager), address(tracker));
        uniswapV3Adaptor = UniswapV3Adaptor(
            deployer.deployContract("Uniswap V3 Adaptor V1.4", creationCode, constructorArgs, 0)
        );

        // Deploy Balancer Adaptor.
        creationCode = type(BalancerPoolAdaptor).creationCode;
        constructorArgs = abi.encode(vault, minter, 0.9e4);
        balancerPoolAdaptor = BalancerPoolAdaptor(
            deployer.deployContract("Balancer Pool Adaptor V1.0", creationCode, constructorArgs, 0)
        );

        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(uniswapV3Adaptor));
        registry.trustAdaptor(address(balancerPoolAdaptor));

        // Add ERC20 positions to Registry.
        registry.trustPosition(wethPositionId, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(wbtcPositionId, address(erc20Adaptor), abi.encode(WBTC));
        registry.trustPosition(usdcPositionId, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(daiPositionId, address(erc20Adaptor), abi.encode(DAI));
        registry.trustPosition(usdtPositionId, address(erc20Adaptor), abi.encode(USDT));
        registry.trustPosition(ghoPositionId, address(erc20Adaptor), abi.encode(GHO));
        registry.trustPosition(swethPositionId, address(erc20Adaptor), abi.encode(SWETH));

        // Add Uniswap positions to Registry.
        registry.trustPosition(wETH_swETH_PositionId, address(uniswapV3Adaptor), abi.encode(WETH, SWETH));
        registry.trustPosition(GHO_USDC_PositionId, address(uniswapV3Adaptor), abi.encode(GHO, USDC));
        registry.trustPosition(GHO_USDT_PositionId, address(uniswapV3Adaptor), abi.encode(GHO, USDT));

        // Create Cellars and Share Price Oracles.
        ghoCellar = _createCellar("Turbo GHO", "TurboGHO", GHO, ghoPositionId, abi.encode(0), 1e18, 0.8e18);
        swethCellar = _createCellar("Turbo SWETH", "TurboSWETH", WETH, wethPositionId, abi.encode(0), 0.001e18, 0.8e18);

        uint64 heartbeat = 1 days;
        uint64 deviationTrigger = 0.0010e4;
        uint64 gracePeriod = 1 days / 6;
        uint16 observationsToUse = 4;
        address automationRegistry = 0xd746F3601eA520Baf3498D61e1B7d976DbB33310;
        uint216 startingAnswer = 1e18;
        uint256 allowedAnswerChangeLower = 0.8e4;
        uint256 allowedAnswerChangeUpper = 10e4;
        _createSharePriceOracle(
            "Turbo GHO Share Price Oracle V0.0",
            address(ghoCellar),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            automationRegistry,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

        _createSharePriceOracle(
            "Turbo SWETH Share Price Oracle V0.0",
            address(swethCellar),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            automationRegistry,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

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
        address cellarAddress = deployer.getAddress(cellarName);
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
                deployer.deployContract(string.concat(cellarName, " V0.0"), creationCode, constructorArgs, 0)
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
