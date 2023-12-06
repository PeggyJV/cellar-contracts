// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { ERC4626SharePriceOracle, IRegistry, IRegistrar } from "src/base/ERC4626SharePriceOracle.sol";
import { MultiChainERC4626SharePriceOracleSource } from "src/modules/multi-chain-share/MultichainERC4626SharePriceOracleSource.sol";
import { MultiChainERC4626SharePriceOracleDestination } from "src/modules/multi-chain-share/MultichainERC4626SharePriceOracleDestination.sol";
import { MockCCIPRouter } from "src/mocks/MockCCIPRouter.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import { DestinationMinter } from "src/modules/multi-chain-share/DestinationMinter.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract ERC4626SharePriceOracleXChainTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    MockCCIPRouter public router;
    AaveATokenAdaptor private aaveATokenAdaptor;
    MockDataFeed private usdcMockFeed;
    MockDataFeed private wethMockFeed;
    Cellar private cellar;
    MultiChainERC4626SharePriceOracleSource private sourceOracle;
    MultiChainERC4626SharePriceOracleDestination private destinationOracle;
    DestinationMinter private destinationMinter;

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    uint32 private usdcPosition = 1;
    uint32 private aV2USDCPosition = 2;
    uint32 private debtUSDCPosition = 3;
    uint32 private wethPosition = 4;

    uint256 private initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18364794;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        router = new MockCCIPRouter(address(LINK));

        usdcMockFeed = new MockDataFeed(USDC_USD_FEED);
        wethMockFeed = new MockDataFeed(WETH_USD_FEED);
        aaveATokenAdaptor = new AaveATokenAdaptor(address(pool), address(WETH), 1.05e18);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(address(wethMockFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(wethMockFeed));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(usdcMockFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(usdcMockFeed));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(aaveATokenAdaptor));

        registry.trustPosition(aV2USDCPosition, address(aaveATokenAdaptor), abi.encode(address(aV2USDC)));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(address(USDC)));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(address(WETH)));

        uint256 minHealthFactor = 1.1e18;

        string memory cellarName = "Simple Aave Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(
            cellarName,
            USDC,
            aV2USDCPosition,
            abi.encode(minHealthFactor),
            initialDeposit,
            platformCut
        );

        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));

        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPosition(1, usdcPosition, abi.encode(0), false);

        USDC.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();

        ERC4626 _target = ERC4626(address(cellar));
        uint64 _heartbeat = 1 days;
        uint64 _deviationTrigger = 0.0005e4;
        uint64 _gracePeriod = 1 days / 6; // 4 hr
        uint16 _observationsToUse = 4; // TWAA duration is heartbeat * (observationsToUse - 1), so ~3 days.
        address _automationRegistry = automationRegistryV2;
        address _automationRegistrar = automationRegistrarV2;
        address _automationAdmin = address(this);

        // Setup source share price oracle.
        sourceOracle = new MultiChainERC4626SharePriceOracleSource(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry,
            _automationRegistrar,
            _automationAdmin,
            address(LINK),
            1e18,
            0.01e4,
            10e4
        );

        // Deploy DestinationMinter.
        destinationMinter = new DestinationMinter(
            address(router),
            address(0),
            cellar.name(),
            cellar.symbol(),
            cellar.decimals(),
            router.SOURCE_SELECTOR(),
            router.DESTINATION_SELECTOR(),
            address(LINK),
            200_000
        );
        // Setup destination share price oracle.
        destinationOracle = new MultiChainERC4626SharePriceOracleDestination(
            ERC4626(address(destinationMinter)),
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            address(LINK),
            1e18,
            0.01e4,
            10e4,
            address(router),
            address(sourceOracle),
            router.SOURCE_SELECTOR()
        );

        uint96 initialUpkeepFunds = 10e18;
        deal(address(LINK), address(this), initialUpkeepFunds);
        LINK.safeApprove(address(sourceOracle), initialUpkeepFunds);
        sourceOracle.initializeWithCcipArgs(
            initialUpkeepFunds,
            address(router),
            address(destinationOracle),
            router.DESTINATION_SELECTOR()
        );

        // Give source LINK so it can send messages to destination.
        deal(address(LINK), address(sourceOracle), 1_000e18);

        // Write storage to change forwarder to address this.
        stdstore.target(address(sourceOracle)).sig(sourceOracle.automationForwarder.selector).checked_write(
            address(this)
        );
    }

    // TODO test where we try to call performUpkeep on source oracle from an address that is not forwarder.
    function testHappyPath() external {
        _makeOraclesSafeToUse();

        // Have whale deposit into Cellar.
        deal(address(USDC), address(this), 1_000_000e6);
        cellar.deposit(1_000_000e6, address(this));

        _runOraclesForNDays(7);

        // Get answers from both oracles.
        (uint256 sourceAnswer, uint256 sourceTWAA, ) = sourceOracle.getLatest();
        (uint256 destinationAnswer, uint256 destinationTWAA, ) = destinationOracle.getLatest();

        assertEq(sourceAnswer, destinationAnswer, "Answers should be the same.");
        assertEq(sourceTWAA, destinationTWAA, "TWAAs should be the same.");
    }

    function testHandlingKillSwitchTriggered() external {
        _makeOraclesSafeToUse();

        // Have whale deposit into Cellar.
        deal(address(USDC), address(this), 1_000_000e6);
        cellar.deposit(1_000_000e6, address(this));

        _runOraclesForNDays(7);

        // Source oracle is updated because share price is exploited.
        bool upkeepNeeded;
        bytes memory performData;

        deal(address(USDC), address(cellar), 10_000_000_000e6);

        (upkeepNeeded, performData) = sourceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sourceOracle.performUpkeep(performData);

        assertTrue(sourceOracle.killSwitch(), "KillSwitch should have been triggered.");

        Client.Any2EVMMessage memory message = router.getLastMessage();

        // For some reason CCIP sends message1 before message0.
        vm.prank(address(router));
        destinationOracle.ccipReceive(message);

        assertTrue(destinationOracle.killSwitch(), "KillSwitch should have been triggered.");
    }

    function testHandlingKillSwitchTriggeredButNotEnoughLinkToSendMessage() external {
        _makeOraclesSafeToUse();

        // Have whale deposit into Cellar.
        deal(address(USDC), address(this), 1_000_000e6);
        cellar.deposit(1_000_000e6, address(this));

        _runOraclesForNDays(7);

        // Make sure users can not call `forwardKillSwitchStateToDestination`.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MultiChainERC4626SharePriceOracleSource
                        .MultiChainERC4626SharePriceOracleSource___KillSwitchNotActivated
                        .selector
                )
            )
        );
        sourceOracle.forwardKillSwitchStateToDestination();

        // Remove Source Oracles LINK balance.
        deal(address(LINK), address(sourceOracle), 0);

        // Source oracle is updated because share price is exploited.
        bool upkeepNeeded;
        bytes memory performData;

        deal(address(USDC), address(cellar), 10_000_000_000e6);

        (upkeepNeeded, performData) = sourceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sourceOracle.performUpkeep(performData);

        assertTrue(sourceOracle.killSwitch(), "KillSwitch should have been triggered.");

        deal(address(LINK), address(this), 1e18);
        LINK.safeApprove(address(sourceOracle), 1e18);
        sourceOracle.forwardKillSwitchStateToDestination();

        Client.Any2EVMMessage memory message = router.getLastMessage();

        // For some reason CCIP sends message1 before message0.
        vm.prank(address(router));
        destinationOracle.ccipReceive(message);

        assertTrue(destinationOracle.killSwitch(), "KillSwitch should have been triggered.");
    }

    function testMessagesComingInOutOfOrder() external {
        _makeOraclesSafeToUse();

        // Have whale deposit into Cellar.
        deal(address(USDC), address(this), 1_000_000e6);
        cellar.deposit(1_000_000e6, address(this));

        _runOraclesForNDays(7);

        // Source oracle is updated.
        bool upkeepNeeded;
        bytes memory performData;

        (upkeepNeeded, performData) = sourceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sourceOracle.performUpkeep(performData);

        Client.Any2EVMMessage memory message0 = router.getLastMessage();

        // Immediately after update, oracle is updated again.
        skip(10);

        // Change share price by minting cellar USDC.
        deal(address(USDC), address(cellar), 100_000e6);

        (upkeepNeeded, performData) = sourceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sourceOracle.performUpkeep(performData);

        Client.Any2EVMMessage memory message1 = router.getLastMessage();

        // For some reason CCIP sends message1 before message0.
        vm.prank(address(router));
        destinationOracle.ccipReceive(message1);

        // message0 fails from staleness.
        vm.startPrank(address(router));
        vm.expectRevert(
            bytes(abi.encodeWithSelector(ERC4626SharePriceOracle.ERC4626SharePriceOracle__StalePerformData.selector))
        );
        destinationOracle.ccipReceive(message0);
        vm.stopPrank();

        // Advance time by 15 min.
        skip(15 * 60);

        // Answers are the same, but TWAA
        (uint256 sourceAnswer, uint256 sourceTWAA, bool isSourceNotSafeToUse) = sourceOracle.getLatest();
        (uint256 destinationAnswer, uint256 destinationTWAA, bool isDestinationNotSafeToUse) = destinationOracle
            .getLatest();

        assertEq(sourceAnswer, destinationAnswer, "Answers should be the same.");
        assertApproxEqRel(sourceTWAA, destinationTWAA, 0.00000001e18, "TWAAs should be slightly different.");

        // But once the volatile data is removed from the TWAA over time.
        skip(1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        wethMockFeed.setMockUpdatedAt(block.timestamp);

        _runOraclesForNDays(4);

        (sourceAnswer, sourceTWAA, isSourceNotSafeToUse) = sourceOracle.getLatest();
        (destinationAnswer, destinationTWAA, isDestinationNotSafeToUse) = destinationOracle.getLatest();

        assertEq(sourceAnswer, destinationAnswer, "Answers should be the same.");
        assertEq(sourceTWAA, destinationTWAA, "TWAAs should be the same.");
    }

    function testCCIPReplayingMessage() external {
        _makeOraclesSafeToUse();

        // Have whale deposit into Cellar.
        deal(address(USDC), address(this), 1_000_000e6);
        cellar.deposit(1_000_000e6, address(this));

        _runOraclesForNDays(7);

        // Source oracle is updated.
        bool upkeepNeeded;
        bytes memory performData;

        (upkeepNeeded, performData) = sourceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sourceOracle.performUpkeep(performData);

        // Immediately after update, oracle is updated again.
        skip(10);

        // Change share price by minting cellar USDC.
        deal(address(USDC), address(cellar), 100_000e6);

        (upkeepNeeded, performData) = sourceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sourceOracle.performUpkeep(performData);

        Client.Any2EVMMessage memory message1 = router.getLastMessage();

        // For some reason CCIP sends message1 before message0.
        vm.prank(address(router));
        destinationOracle.ccipReceive(message1);

        // message1 is replayed.
        vm.startPrank(address(router));
        vm.expectRevert(
            bytes(abi.encodeWithSelector(ERC4626SharePriceOracle.ERC4626SharePriceOracle__StalePerformData.selector))
        );
        destinationOracle.ccipReceive(message1);
        vm.stopPrank();
    }

    // TODO remaining reverts in source
    // TODO remaining reverts in destination\, like try calling ccipRecevie from a non router address

    function _makeOraclesSafeToUse() internal {
        bool upkeepNeeded;
        bytes memory performData;

        (, , bool isSourceNotSafeToUse) = sourceOracle.getLatest();
        (, , bool isDestinationNotSafeToUse) = destinationOracle.getLatest();
        while (!isSourceNotSafeToUse && !isDestinationNotSafeToUse) {
            (upkeepNeeded, performData) = sourceOracle.checkUpkeep(abi.encode(0));
            assertTrue(upkeepNeeded, "Upkeep should be needed.");
            sourceOracle.performUpkeep(performData);

            // simulate a 20 min message time.
            skip(20 * 60);

            // Simulate CCIP Message to destination oracle.
            Client.Any2EVMMessage memory message = router.getLastMessage();
            vm.prank(address(router));
            destinationOracle.ccipReceive(message);

            (, , isSourceNotSafeToUse) = sourceOracle.getLatest();
            (, , isDestinationNotSafeToUse) = destinationOracle.getLatest();

            skip(1 days);
            usdcMockFeed.setMockUpdatedAt(block.timestamp);
            wethMockFeed.setMockUpdatedAt(block.timestamp);
        }
    }

    function _runOraclesForNDays(uint256 n) internal {
        bool upkeepNeeded;
        bytes memory performData;
        for (uint256 i; i < n; ++i) {
            (upkeepNeeded, performData) = sourceOracle.checkUpkeep(abi.encode(0));
            assertTrue(upkeepNeeded, "Upkeep should be needed.");
            sourceOracle.performUpkeep(performData);

            // simulate a 20 min message time.
            skip(20 * 60);

            // Simulate CCIP Message to destination oracle.
            Client.Any2EVMMessage memory message = router.getLastMessage();
            vm.prank(address(router));
            destinationOracle.ccipReceive(message);

            skip(1 days);
            usdcMockFeed.setMockUpdatedAt(block.timestamp);
            wethMockFeed.setMockUpdatedAt(block.timestamp);
        }
    }
}
