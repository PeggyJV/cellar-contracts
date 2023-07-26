// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { CellarWithOracle } from "src/base/permutations/CellarWithOracle.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarWithOracleTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    MockDataFeed private usdcMockFeed;
    MockDataFeed private usdtMockFeed;
    MockDataFeed private daiMockFeed;
    MockDataFeed private fraxMockFeed;
    CellarWithOracle private cellar;
    ERC4626SharePriceOracle private sharePriceOracle;

    uint32 public usdcPosition = 1;
    uint32 public wethPosition = 2;
    uint32 public usdtPosition = 3;
    uint32 public daiPosition = 4;
    uint32 public fraxPosition = 5;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        usdcMockFeed = new MockDataFeed(USDC_USD_FEED);
        usdtMockFeed = new MockDataFeed(USDT_USD_FEED);
        daiMockFeed = new MockDataFeed(DAI_USD_FEED);
        fraxMockFeed = new MockDataFeed(FRAX_USD_FEED);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(usdcMockFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(usdcMockFeed));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(usdtMockFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(usdtMockFeed));
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(daiMockFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(daiMockFeed));
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(fraxMockFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(fraxMockFeed));
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(address(USDC)));
        registry.trustPosition(usdtPosition, address(erc20Adaptor), abi.encode(address(USDT)));
        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(address(DAI)));
        registry.trustPosition(fraxPosition, address(erc20Adaptor), abi.encode(address(FRAX)));

        bytes memory creationCode;
        bytes memory constructorArgs;

        string memory cellarName = "Simple Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        creationCode = type(CellarWithOracle).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            USDC,
            cellarName,
            cellarName,
            usdcPosition,
            abi.encode(0),
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(USDC), address(this), initialDeposit);
        USDC.approve(cellarAddress, initialDeposit);

        cellar = CellarWithOracle(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addPositionToCatalogue(usdtPosition);
        cellar.addPositionToCatalogue(daiPosition);
        cellar.addPositionToCatalogue(fraxPosition);

        USDC.safeApprove(address(cellar), type(uint256).max);

        ERC4626 _target = ERC4626(address(cellar));
        uint64 _heartbeat = 1 days;
        uint64 _deviationTrigger = 0.0005e4;
        uint64 _gracePeriod = 60 * 60; // 1 hr
        uint16 _observationsToUse = 4; // TWAA duration is heartbeat * (observationsToUse - 1), so ~3 days.
        address _automationRegistry = address(this);

        // Setup share price oracle.
        sharePriceOracle = new ERC4626SharePriceOracle(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry
        );

        // Call first performUpkeep on Cellar.
        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);

        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);
        (, , bool notSafeToUse) = sharePriceOracle.getLatest();
        assertTrue(!notSafeToUse);

        cellar.setSharePriceOracle(sharePriceOracle);
    }

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));
    }

    function testDepositAndMintUseLargerAnswer() external {
        address user0 = vm.addr(10);
        address user1 = vm.addr(11);

        uint256 snapshotBeforeEntries = vm.snapshot();

        // Double the share price.
        _passTimeAlterSharePriceAndUpkeep(1 days, 2e4);

        vm.warp(block.timestamp + 1 days / 2);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        usdtMockFeed.setMockUpdatedAt(block.timestamp);
        daiMockFeed.setMockUpdatedAt(block.timestamp);
        fraxMockFeed.setMockUpdatedAt(block.timestamp);

        uint256 assets = 100e6;
        uint256 expectedShares = assets / 2;
        {
            vm.startPrank(user0);
            deal(address(USDC), user0, assets);
            USDC.approve(address(cellar), assets);
            cellar.deposit(assets, user0);
            vm.stopPrank();
            assertEq(cellar.balanceOf(user0), expectedShares, "User entry should have used larger answer");
            assertEq(
                cellar.balanceOf(user0),
                cellar.previewDeposit(assets),
                "User entry should have used larger answer"
            );
        }

        {
            vm.startPrank(user1);
            deal(address(USDC), user1, assets);
            USDC.approve(address(cellar), assets);
            cellar.mint(expectedShares, user1);
            vm.stopPrank();
            assertEq(cellar.balanceOf(user1), expectedShares, "User entry should have used larger answer");
            assertEq(assets, cellar.previewMint(expectedShares), "User entry should have used larger answer");
        }

        // Revert to before entries.
        vm.revertTo(snapshotBeforeEntries);

        // Half the share price.
        _passTimeAlterSharePriceAndUpkeep(1 days, 0.5e4);

        vm.warp(block.timestamp + 1 days / 2);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        usdtMockFeed.setMockUpdatedAt(block.timestamp);
        daiMockFeed.setMockUpdatedAt(block.timestamp);
        fraxMockFeed.setMockUpdatedAt(block.timestamp);

        expectedShares = assets.mulDivDown(3.5e18, 3.25e18);
        {
            vm.startPrank(user0);
            deal(address(USDC), user0, assets);
            USDC.approve(address(cellar), assets);
            cellar.deposit(assets, user0);
            vm.stopPrank();
            assertApproxEqAbs(
                cellar.balanceOf(user0),
                expectedShares,
                100,
                "User entry should have used larger time weighted average answer"
            );
            assertApproxEqAbs(
                cellar.balanceOf(user0),
                cellar.previewDeposit(assets),
                100,
                "User entry should have used larger answer"
            );
        }

        {
            vm.startPrank(user1);
            deal(address(USDC), user1, assets);
            USDC.approve(address(cellar), assets);
            cellar.mint(expectedShares, user1);
            vm.stopPrank();
            assertApproxEqAbs(
                cellar.balanceOf(user1),
                expectedShares,
                100,
                "User entry should have used larger time weighted average answer"
            );
            assertApproxEqAbs(
                assets,
                cellar.previewMint(expectedShares),
                100,
                "User entry should have used larger answer"
            );
        }
    }

    function testWithdrawAndRedeemUseSmallerAnswer() external {
        address user0 = vm.addr(10);
        address user1 = vm.addr(11);
        uint256 assets = 100e6;
        uint256 initialShares = 100e6;
        {
            vm.startPrank(user0);
            deal(address(USDC), user0, assets);
            USDC.approve(address(cellar), assets);
            cellar.deposit(assets, user0);
            vm.stopPrank();
        }
        {
            vm.startPrank(user1);
            deal(address(USDC), user1, assets);
            USDC.approve(address(cellar), assets);
            cellar.deposit(assets, user1);
            vm.stopPrank();
        }

        uint256 snapshotBeforeExits = vm.snapshot();

        // Double the share price.
        _passTimeAlterSharePriceAndUpkeep(1 days, 2e4);

        vm.warp(block.timestamp + 1 days / 2);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        usdtMockFeed.setMockUpdatedAt(block.timestamp);
        daiMockFeed.setMockUpdatedAt(block.timestamp);
        fraxMockFeed.setMockUpdatedAt(block.timestamp);

        uint256 expectedAssets = assets.mulDivDown(4e18, 3.5e18);
        {
            vm.startPrank(user0);
            uint256 assetsToWithdraw = cellar.maxWithdraw(user0);
            cellar.withdraw(assetsToWithdraw, user0, user0);
            vm.stopPrank();
            assertApproxEqAbs(
                USDC.balanceOf(user0),
                expectedAssets,
                100,
                "User exit should have used smaller time weighted average answer"
            );
            assertApproxEqAbs(
                initialShares,
                cellar.previewWithdraw(assetsToWithdraw),
                100,
                "User exit should have used smaller time weighted average answer"
            );
        }

        {
            vm.startPrank(user1);
            uint256 sharesToRedeem = cellar.maxRedeem(user1);
            cellar.redeem(sharesToRedeem, user1, user1);
            vm.stopPrank();
            assertApproxEqAbs(
                USDC.balanceOf(user1),
                expectedAssets,
                100,
                "User exit should have used smaller time weighted average answer"
            );
            assertApproxEqAbs(
                USDC.balanceOf(user1),
                cellar.previewRedeem(initialShares),
                100,
                "User exit should have used smaller time weighted average answer"
            );
        }

        // Revert to before exits.
        vm.revertTo(snapshotBeforeExits);

        // Half the share price.
        _passTimeAlterSharePriceAndUpkeep(1 days, 0.5e4);

        vm.warp(block.timestamp + 1 days / 2);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        usdtMockFeed.setMockUpdatedAt(block.timestamp);
        daiMockFeed.setMockUpdatedAt(block.timestamp);
        fraxMockFeed.setMockUpdatedAt(block.timestamp);

        expectedAssets = assets / 2;
        {
            vm.startPrank(user0);
            uint256 assetsToWithdraw = cellar.maxWithdraw(user0);
            cellar.withdraw(assetsToWithdraw, user0, user0);
            vm.stopPrank();
            assertApproxEqAbs(
                USDC.balanceOf(user0),
                expectedAssets,
                100,
                "User exit should have used smaller time weighted average answer"
            );
            assertApproxEqAbs(
                initialShares,
                cellar.previewWithdraw(assetsToWithdraw),
                100,
                "User exit should have used smaller time weighted average answer"
            );
        }

        {
            vm.startPrank(user1);
            uint256 sharesToRedeem = cellar.maxRedeem(user1);
            cellar.redeem(sharesToRedeem, user1, user1);
            vm.stopPrank();
            assertApproxEqAbs(
                USDC.balanceOf(user1),
                expectedAssets,
                100,
                "User exit should have used smaller time weighted average answer"
            );
            assertApproxEqAbs(
                USDC.balanceOf(user1),
                cellar.previewRedeem(initialShares),
                100,
                "User exit should have used smaller time weighted average answer"
            );
        }
    }

    function testDepositGas(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), 3 * assets);
        USDC.approve(address(cellar), type(uint256).max);
        cellar.deposit(assets, address(this));

        uint256 depositGas1Asset = gasleft();
        cellar.deposit(assets, address(this));
        depositGas1Asset -= gasleft();

        // Rebalance Cellar so it has assets in 4 positions.
        cellar.addPosition(1, usdtPosition, abi.encode(0), false);
        cellar.addPosition(2, daiPosition, abi.encode(0), false);
        cellar.addPosition(3, fraxPosition, abi.encode(0), false);

        uint256 usdcAmount = (2 * assets) / 4;
        uint256 usdtAmount = priceRouter.getValue(USDC, usdcAmount, USDT);
        uint256 daiAmount = priceRouter.getValue(USDC, usdcAmount, DAI);
        uint256 fraxAmount = priceRouter.getValue(USDC, usdcAmount, FRAX);

        deal(address(USDC), address(cellar), usdcAmount);
        deal(address(USDT), address(cellar), usdtAmount);
        deal(address(DAI), address(cellar), daiAmount);
        deal(address(FRAX), address(cellar), fraxAmount);

        uint256 depositGas4Assets = gasleft();
        cellar.deposit(assets, address(this));
        depositGas4Assets -= gasleft();

        assertApproxEqRel(depositGas1Asset, depositGas4Assets, 0.001e18, "Deposit gas should be the same");
    }

    function testAttackerManipulatingSharePriceUp() external {
        // In this hypothetical scenario, the attacker has found a way to 2x the share price.
        // And perfectly times it so that oracle updates immediately after.
        // Even though this happens, when the attacker withdraws, they use the
        // Time Weighted Average Share Price which is significantly less than the current share price.
        address attacker = vm.addr(88);
        uint256 attackerAssets = 1_000e6;
        // Attacker joins cellar.
        vm.startPrank(attacker);
        deal(address(USDC), attacker, attackerAssets);
        USDC.approve(address(cellar), attackerAssets);
        cellar.deposit(attackerAssets, attacker);
        vm.stopPrank();

        uint256 attackerPaidSharePrice = cellar.previewMint(1e6);

        (, uint256 twaaBeforeAttack, ) = sharePriceOracle.getLatest();

        // Attacker manipulates Cellar Share Price.
        deal(address(USDC), address(cellar), 2 * USDC.balanceOf(address(cellar)));

        assertEq(
            cellar.previewMint(1e6),
            attackerPaidSharePrice,
            "Share price is only updated once oracle has been updated"
        );

        // Assume upkeep happens right after share price manipulation.
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);

        (uint256 ans, uint256 twaa, bool isSafeToUse) = sharePriceOracle.getLatest();
        // Immediately after attack, twaa is unaffected.
        assertEq(twaa, twaaBeforeAttack, "TWAA should be unaffected.");
        // But as time passes, TWAA will gradually be affected by share price manipulation.
        vm.warp(block.timestamp + 1 days / 2);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        usdtMockFeed.setMockUpdatedAt(block.timestamp);
        daiMockFeed.setMockUpdatedAt(block.timestamp);
        fraxMockFeed.setMockUpdatedAt(block.timestamp);

        (, twaa, isSafeToUse) = sharePriceOracle.getLatest();
        // Math behind this. cumulative is 4, and the elapsed time is 3.5 days.
        uint256 expectedTwaa = twaaBeforeAttack.mulDivDown(4e18, 3.5e18);
        assertApproxEqRel(twaa, expectedTwaa, 0.01e18, "TWAA is now affected.");

        assertTrue(!isSafeToUse, "Oracle should be safe to use");
        assertEq(ans.changeDecimals(18, 6), 2 * attackerPaidSharePrice, "SharePrice should 2.0");

        uint256 attackerRedemptionSharePrice = cellar.previewRedeem(1e6);

        assertEq(
            attackerRedemptionSharePrice,
            expectedTwaa.changeDecimals(18, 6),
            "Share price for redemption should equal twaa"
        );
        uint256 expectedAttackerAssetsOut = attackerAssets.mulDivDown(expectedTwaa, 1e18);
        vm.startPrank(attacker);
        cellar.redeem(1_000e6, attacker, attacker);
        vm.stopPrank();
        assertApproxEqAbs(
            USDC.balanceOf(attacker),
            expectedAttackerAssetsOut,
            1,
            "Attacker assets out should equal expected"
        );
    }

    function testAttackerManipulatingSharePriceDown() external {
        // In this hypothetical scenario, the attacker has found a way to 0.5x the share price.
        // And perfectly times it so that oracle updates immediately after.
        // Even though this happens, when the attacker mints, then withdraws, the
        // cellar uses valeus that benefit the cellar.
        address attacker = vm.addr(88);
        uint256 attackerAssets = 1_000e6;

        // Attacker manipulates Cellar Share Price.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) / 2);

        // Assume upkeep happens right after share price manipulation.
        _passTimeAlterSharePriceAndUpkeep(1 days, 1e4);

        // Attacker joins cellar.
        vm.startPrank(attacker);
        deal(address(USDC), attacker, attackerAssets);
        USDC.approve(address(cellar), attackerAssets);
        cellar.deposit(attackerAssets, attacker);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days / 2);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        usdtMockFeed.setMockUpdatedAt(block.timestamp);
        daiMockFeed.setMockUpdatedAt(block.timestamp);
        fraxMockFeed.setMockUpdatedAt(block.timestamp);

        uint256 attackerPaidSharePrice = cellar.previewMint(1e6);

        uint256 expectedAttackerPaidSharePrice = uint256(1e6).mulDivDown(3.25e18, 3.5e18);

        assertApproxEqAbs(
            attackerPaidSharePrice,
            expectedAttackerPaidSharePrice,
            1,
            "Even though attacker reduced the share price before entering, it should be greater than 0.5e6"
        );
    }

    // ------------------------------------- Revert Tests -------------------------------------------------
    // Implement Decimals so that `setSharePriceOracle` reverts for the right reason.
    uint256 public ORACLE_DECIMALS = 6;

    function testAddingOracleWithWrongDecimalsReverts() external {
        vm.expectRevert(bytes(abi.encodeWithSelector(CellarWithOracle.Cellar__OracleFailure.selector)));
        cellar.setSharePriceOracle(ERC4626SharePriceOracle(address(this)));
    }

    // Make sure if oracle answer is not safe to use deposits revert
    function testOracleNotSetOrUnsafeOracleAnswersRevert() external {
        uint256 assets = 1_000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellar), assets);

        // Alter storage since it is impossible to set share price oracle to zero address normally.
        stdstore.target(address(cellar)).sig(cellar.sharePriceOracle.selector).checked_write(address(0));

        vm.expectRevert(bytes(abi.encodeWithSelector(CellarWithOracle.Cellar__OracleFailure.selector)));
        cellar.deposit(assets, address(this));

        cellar.setSharePriceOracle(sharePriceOracle);

        vm.warp(block.timestamp + 1 days + 3_601);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);

        vm.expectRevert(bytes(abi.encodeWithSelector(CellarWithOracle.Cellar__OracleFailure.selector)));
        cellar.deposit(assets, address(this));
    }

    function testSettingSharePriceOracleToZeroAddressReverts() external {
        vm.expectRevert();
        cellar.setSharePriceOracle(ERC4626SharePriceOracle(address(0)));
    }

    function _passTimeAlterSharePriceAndUpkeep(uint256 timeToPass, uint256 sharePriceMultiplier) internal {
        vm.warp(block.timestamp + timeToPass);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        usdtMockFeed.setMockUpdatedAt(block.timestamp);
        daiMockFeed.setMockUpdatedAt(block.timestamp);
        fraxMockFeed.setMockUpdatedAt(block.timestamp);
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)).mulDivDown(sharePriceMultiplier, 1e4));

        bool upkeepNeeded;
        bytes memory performData;
        (upkeepNeeded, performData) = sharePriceOracle.checkUpkeep(abi.encode(0));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        sharePriceOracle.performUpkeep(performData);
    }
}
