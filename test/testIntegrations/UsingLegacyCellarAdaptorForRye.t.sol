// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { LegacyCellarAdaptor } from "src/modules/adaptors/Sommelier/LegacyCellarAdaptor.sol";
import { LegacyRegistry } from "src/interfaces/LegacyRegistry.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract UsingLegacyCellarAdaptorForRyeTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    LegacyCellarAdaptor private cellarAdaptor;
    ERC4626SharePriceOracle private sharePriceOracle;
    Cellar private rye = Cellar(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);
    Cellar private ryb = Cellar(0x0274a704a6D9129F90A62dDC6f6024b33EcDad36);
    address private uniswapAdaptor = 0x92611574EC9BC13C6137917481dab7BB7b173c9b;

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    LegacyRegistry private legacyRegistry = LegacyRegistry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);

    uint32 private legacyCellarRyePosition;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18200000;
        _startFork(rpcKey, blockNumber);

        // Setup RYE Share Price Oracle.
        ERC4626 _target = ERC4626(address(rye));
        uint64 _heartbeat = 1 days;
        uint64 _deviationTrigger = 0.0005e4;
        uint64 _gracePeriod = 60 * 60; // 1 hr
        uint16 _observationsToUse = 4; // TWAA duration is heartbeat * (observationsToUse - 1), so ~3 days.
        address _automationRegistry = automationRegistryV2;
        address _automationRegistrar = automationRegistrarV2;
        address _automationAdmin = address(this);

        // Setup share price oracle.
        ERC4626SharePriceOracle.ConstructorArgs memory args = ERC4626SharePriceOracle.ConstructorArgs(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry,
            _automationRegistrar,
            _automationAdmin,
            address(LINK),
            1.02e18,
            0.1e4,
            10e4,
            address(0),
            0
        );
        sharePriceOracle = new ERC4626SharePriceOracle(args);

        uint96 initialUpkeepFunds = 10e18;
        deal(address(LINK), address(this), initialUpkeepFunds);
        LINK.safeApprove(address(sharePriceOracle), initialUpkeepFunds);
        sharePriceOracle.initialize(initialUpkeepFunds);

        // Write storage to change forwarder to address this.
        stdstore.target(address(sharePriceOracle)).sig(sharePriceOracle.automationForwarder.selector).checked_write(
            address(this)
        );

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        cellarAdaptor = LegacyCellarAdaptor(0x1e22aDf9E63eF8F2A3626841DDdDD19683E31068);

        // vm.startPrank(multisig);
        // legacyRegistry.trustAdaptor(address(cellarAdaptor));
        // vm.stopPrank();

        deal(address(WBTC), address(this), type(uint256).max);
        WBTC.safeApprove(address(ryb), type(uint256).max);
    }

    function testNormalTotalAssetsCosts() external {
        ryb.deposit(1e8, address(this));
        uint256 gas = gasleft();
        ryb.totalAssets();
        console.log("Gas Used Base", gas - gasleft());
    }

    function testUsingRyeWithOracle() external {
        // vm.startPrank(multisig);
        // legacyCellarRyePosition = legacyRegistry.trustPosition(
        //     address(cellarAdaptor),
        //     abi.encode(rye, sharePriceOracle)
        // );
        // vm.stopPrank();
        // vm.startPrank(gravityBridgeAddress);
        // ryb.addAdaptorToCatalogue(address(cellarAdaptor));
        // ryb.addPositionToCatalogue(legacyCellarRyePosition);
        // ryb.addPosition(1, legacyCellarRyePosition, abi.encode(false), false);
        // _withdrawFromUniswapAndDepositToRye(address(sharePriceOracle));
        // vm.stopPrank();
        // uint256 gas = gasleft();
        // ryb.totalAssets();
        // console.log("Gas Used With Oracle", gas - gasleft());
    }

    function _withdrawFromUniswapAndDepositToRye(address oracle) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        // Remove Liquidity from Uniswap.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToCloseLP(address(ryb), 0);
            data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapAdaptor), callData: adaptorCalls });
        }
        ryb.callOnAdaptor(data);

        // Remove Uniswap position.
        ryb.removePosition(6, false);

        // Simulate a swap by converting WSTETH into WETH.
        uint256 wethAmount = WETH.balanceOf(address(ryb)) +
            ryb.priceRouter().getValue(WSTETH, WSTETH.balanceOf(address(ryb)), WETH);
        deal(address(WSTETH), address(ryb), 0);
        deal(address(WETH), address(ryb), wethAmount);

        // Deposit WETH into RYE.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToLegacyCellar(address(rye), wethAmount, oracle);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }
        ryb.callOnAdaptor(data);
    }

    function _createBytesDataToCloseLP(address owner, uint256 index) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.closePosition.selector, tokenId, 0, 0);
    }
}
