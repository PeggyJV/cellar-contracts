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

    CellarWithOracleWithBalancerFlashLoans public okxCellar;

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    // Positions.
    uint32 stethPositionId = 10;

    function run() external {
        vm.startBroadcast();

        // Create Cellars and Share Price Oracles.
        okxCellar = _createCellar(
            "Turbo stETH (stETH Deposit)",
            "TurboSTETH2",
            STETH,
            stethPositionId,
            abi.encode(0),
            0.001e18,
            0.85e18
        );

        uint64 heartbeat = 1 days;
        uint64 deviationTrigger = 0.0050e4;
        uint64 gracePeriod = 1 days / 6;
        uint16 observationsToUse = 4;
        address automationAdmin = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
        uint216 startingAnswer = 1e18;
        uint256 allowedAnswerChangeLower = 0.8e4;
        uint256 allowedAnswerChangeUpper = 10e4;
        _createSharePriceOracle(
            "TurboSTETH2 Share Price Oracle V0.0",
            address(okxCellar),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            automationAdmin,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

        okxCellar.transferOwnership(automationAdmin);

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
        require(false, "is this needed anymore");
        // holdingAsset.approve(cellarAddress, initialDeposit);

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
        address _automationAdmin,
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
            automationRegistryV2,
            automationRegistrarV2,
            _automationAdmin,
            LINK,
            _startingAnswer,
            _allowedAnswerChangeLower,
            _allowedAnswerChangeUpper
        );

        return ERC4626SharePriceOracle(deployer.deployContract(_name, creationCode, constructorArgs, 0));
    }
}
