// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Registry } from "src/Registry.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { CellarWithOracleWithBalancerFlashLoans } from "src/base/permutations/CellarWithOracleWithBalancerFlashLoans.sol";
import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployTurboSOMMCellar.s.sol:DeployTurboSOMMCellarScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployTurboSOMMCellarScript is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    address uniswapV3Adaptor = 0xC74fFa211A8148949a77ec1070Df7013C8D5Ce92; // v1.4
    address balancerPoolAdaptor = 0x2750348A897059C45683d33A1742a3989454F7d6; // v1.1
    address oneInchAdaptor = 0xB8952ce4010CFF3C74586d712a4402285A3a3AFb; // already trusted
    address zeroXAdaptor = 0x1039a9b61DFF6A3fb8dbF4e924AA749E5cFE35ef; // already trusted
    address feesAndReservesAdaptor = 0x647d264d800A2461E594796af61a39b7735d8933;
    address vestingSimpleAdaptor = 0x3b98BA00f981342664969e609Fb88280704ac479; // already trusted

    CellarWithOracleWithBalancerFlashLoans public sommCellar;

    // ERC20 Positions.
    uint32 wethPositionId = 1;
    uint32 sommPositionId = 11;

    // Uniswap Positions.
    uint32 SOMM_wETH_PositionId = 1_000_008;

    function run() external {
        bytes memory creationCode;
        bytes memory constructorArgs;

        vm.startBroadcast();

        // Create Cellars and Share Price Oracles.
        sommCellar = _createCellar("Turbo SOMM", "TurboSOMM", SOMM, sommPositionId, abi.encode(0), 1e18, 0.8e18);

        uint64 heartbeat = 1 days;
        uint64 deviationTrigger = 0.0010e4;
        uint64 gracePeriod = 1 days / 6;
        uint16 observationsToUse = 4;
        address automationRegistry = 0xd746F3601eA520Baf3498D61e1B7d976DbB33310;
        uint216 startingAnswer = 1e18;
        uint256 allowedAnswerChangeLower = 0.8e4;
        uint256 allowedAnswerChangeUpper = 10e4;

        _createSharePriceOracle(
            "Turbo SOMM Share Price Oracle V0.0",
            address(sommCellar),
            heartbeat,
            deviationTrigger,
            gracePeriod,
            observationsToUse,
            automationRegistry,
            startingAnswer,
            allowedAnswerChangeLower,
            allowedAnswerChangeUpper
        );

        registry.trustAdaptor(address(uniswapV3Adaptor));
        registry.trustAdaptor(address(balancerPoolAdaptor));
        registry.trustAdaptor(address(feesAndReservesAdaptor));

        sommCellar.addAdaptorToCatalogue(uniswapV3Adaptor);
        sommCellar.addAdaptorToCatalogue(balancerPoolAdaptor);
        sommCellar.addAdaptorToCatalogue(oneInchAdaptor); 
        sommCellar.addAdaptorToCatalogue(zeroXAdaptor); 
        sommCellar.addAdaptorToCatalogue(feesAndReservesAdaptor);
        sommCellar.addAdaptorToCatalogue(vestingSimpleAdaptor);

        sommCellar.addPositionToCatalogue(wethPositionId);
        sommCellar.addPositionToCatalogue(sommPositionId);
        sommCellar.addPositionToCatalogue(SOMM_wETH_PositionId);

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
