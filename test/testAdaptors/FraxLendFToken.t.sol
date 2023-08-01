// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import { FTokenAdaptorV1 } from "src/modules/adaptors/Frax/FTokenAdaptorV1.sol";
import { MockFTokenAdaptor } from "src/mocks/adaptors/MockFTokenAdaptor.sol";
import { MockFTokenAdaptorV1 } from "src/mocks/adaptors/MockFTokenAdaptorV1.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

/**
 * @dev A lot of FraxLend operations round down, so many tests use `assertApproxEqAbs` with a
 *      2 wei bound to account for this.
 */
contract FraxLendFTokenAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    FTokenAdaptor private fTokenAdaptorV2;
    FTokenAdaptorV1 private fTokenAdaptor;
    MockFTokenAdaptor private mockFTokenAdaptorV2;
    MockFTokenAdaptorV1 private mockFTokenAdaptor;
    Cellar private cellar;

    address private UNTRUSTED_sfrxETH = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15;

    // Chainlink PriceFeeds
    MockDataFeed private mockFraxUsd;
    MockDataFeed private mockWethUsd;

    uint32 private fraxPosition = 1;
    uint32 private fxsFraxPairPosition = 2;
    uint32 private fpiFraxPairPosition = 3;
    uint32 private sfrxEthFraxPairPosition = 4;
    uint32 private wEthFraxPairPosition = 5;

    // Mock Positions
    uint32 private mockFxsFraxPairPosition = 6;
    uint32 private mockSfrxEthFraxPairPosition = 7;

    uint256 initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockFraxUsd = new MockDataFeed(FRAX_USD_FEED);
        mockWethUsd = new MockDataFeed(WETH_USD_FEED);
        fTokenAdaptorV2 = new FTokenAdaptor(true, address(FRAX));
        fTokenAdaptor = new FTokenAdaptorV1(true, address(FRAX));
        mockFTokenAdaptorV2 = new MockFTokenAdaptor(false, address(FRAX));
        mockFTokenAdaptor = new MockFTokenAdaptorV1(false, address(FRAX));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(mockFraxUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockFraxUsd));
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        price = uint256(mockWethUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWethUsd));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(fTokenAdaptor));
        registry.trustAdaptor(address(fTokenAdaptorV2));
        registry.trustAdaptor(address(mockFTokenAdaptorV2));
        registry.trustAdaptor(address(mockFTokenAdaptor));

        registry.trustPosition(fraxPosition, address(erc20Adaptor), abi.encode(FRAX));
        registry.trustPosition(fxsFraxPairPosition, address(fTokenAdaptor), abi.encode(FXS_FRAX_PAIR));
        registry.trustPosition(fpiFraxPairPosition, address(fTokenAdaptor), abi.encode(FPI_FRAX_PAIR));
        registry.trustPosition(sfrxEthFraxPairPosition, address(fTokenAdaptorV2), abi.encode(SFRXETH_FRAX_PAIR));
        registry.trustPosition(wEthFraxPairPosition, address(fTokenAdaptor), abi.encode(WETH_FRAX_PAIR));
        registry.trustPosition(mockFxsFraxPairPosition, address(mockFTokenAdaptor), abi.encode(FXS_FRAX_PAIR));
        registry.trustPosition(
            mockSfrxEthFraxPairPosition,
            address(mockFTokenAdaptorV2),
            abi.encode(SFRXETH_FRAX_PAIR)
        );

        string memory cellarName = "FraxLend Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, FRAX, fraxPosition, abi.encode(0), initialDeposit, platformCut);

        cellar.addAdaptorToCatalogue(address(fTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(fTokenAdaptorV2));

        cellar.addPositionToCatalogue(fxsFraxPairPosition);
        cellar.addPositionToCatalogue(fpiFraxPairPosition);
        cellar.addPositionToCatalogue(sfrxEthFraxPairPosition);
        cellar.addPositionToCatalogue(wEthFraxPairPosition);

        cellar.addPositionToCatalogue(fxsFraxPairPosition);
        cellar.addPosition(0, fxsFraxPairPosition, abi.encode(0), false);
        cellar.setHoldingPosition(fxsFraxPairPosition);

        FRAX.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend FRAX on FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnFraxLend(FXS_FRAX_PAIR, initialDeposit);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);
    }

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        cellar.withdraw(assets - 2, address(this), address(this));
    }

    function testDepositV2(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        // Adjust Cellar holding position to deposit into a Frax Pair V2.
        cellar.addPosition(0, sfrxEthFraxPairPosition, abi.encode(0), false);
        cellar.setHoldingPosition(sfrxEthFraxPairPosition);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));
    }

    function testWithdrawV2(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        // Adjust Cellar holding position to withdraw from a Frax Pair V2.
        cellar.addPosition(0, sfrxEthFraxPairPosition, abi.encode(0), false);
        cellar.setHoldingPosition(sfrxEthFraxPairPosition);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        cellar.withdraw(assets - 2, address(this), address(this));
    }

    function testTotalAssets(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            cellar.totalAssets(),
            assets + initialAssets,
            2,
            "Total assets should equal assets deposited."
        );
    }

    function testLendingFrax(uint256 assets) external {
        // Add FRAX position and change holding position to vanilla FRAX.
        cellar.setHoldingPosition(fraxPosition);

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to lend FRAX.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend FRAX on FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnFraxLend(FXS_FRAX_PAIR, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        IFToken pair = IFToken(FXS_FRAX_PAIR);
        uint256 shareBalance = pair.balanceOf(address(cellar));
        assertTrue(shareBalance > 0, "Cellar should own shares.");
        assertApproxEqAbs(
            pair.toAssetAmount(shareBalance, false),
            assets + initialAssets,
            2,
            "Rebalance should have lent all FRAX on FraxLend."
        );
    }

    function testWithdrawingFrax(uint256 assets) external {
        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to withdraw FRAX.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Withdraw FRAX from FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeemFromFraxLend(FXS_FRAX_PAIR, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            FRAX.balanceOf(address(cellar)),
            assets + initialAssets,
            2,
            "Cellar FRAX should have been withdraw from FraxLend."
        );
    }

    function testRebalancingBetweenPairs(uint256 assets) external {
        // Add another Frax Lend pair, and vanilla FRAX.
        cellar.addPosition(0, sfrxEthFraxPairPosition, abi.encode(0), false);

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to withdraw FRAX, and lend in a different pair.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        // Withdraw FRAX from FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeemFromFraxLend(FXS_FRAX_PAIR, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnFraxLend(SFRXETH_FRAX_PAIR, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        IFToken pair = IFToken(SFRXETH_FRAX_PAIR);
        uint256 shareBalance = pair.balanceOf(address(cellar));
        assertTrue(shareBalance > 0, "Cellar should own shares.");
        assertApproxEqAbs(
            pair.toAssetAmount(shareBalance, false, false),
            assets + initialAssets,
            10,
            "Rebalance should have lent in other pair."
        );

        // Withdraw half the assets from Frax Pair V2.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromFraxLend(SFRXETH_FRAX_PAIR, assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        assertEq(FRAX.balanceOf(address(cellar)), assets / 2, "Should have withdrawn half the assets from FraxLend.");
    }

    function testUsingPairNotSetupAsPosition(uint256 assets) external {
        // Add FRAX position and change holding position to vanilla FRAX.
        cellar.setHoldingPosition(fraxPosition);

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to lend FRAX.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend FRAX on FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnFraxLend(UNTRUSTED_sfrxETH, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    FTokenAdaptor.FTokenAdaptor__FTokenPositionsMustBeTracked.selector,
                    (UNTRUSTED_sfrxETH)
                )
            )
        );
        cellar.callOnAdaptor(data);

        address maliciousContract = vm.addr(87345834);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeemFromFraxLend(maliciousContract, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    FTokenAdaptor.FTokenAdaptor__FTokenPositionsMustBeTracked.selector,
                    (maliciousContract)
                )
            )
        );
        cellar.callOnAdaptor(data);

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromFraxLend(maliciousContract, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    FTokenAdaptor.FTokenAdaptor__FTokenPositionsMustBeTracked.selector,
                    (maliciousContract)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // Check that FRAX in multiple different pairs is correctly accounted for in totalAssets().
    function testMultiplePositionsTotalAssets(uint256 assets) external {
        // Have user deposit into cellar
        assets = bound(assets, 0.01e18, 100_000_000e18);
        uint256 expectedAssets = assets;
        uint256 dividedAssetPerMultiPair = assets / 3; // amount of FRAX to distribute between different fraxLendPairs
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Test that users can withdraw from multiple pairs at once.
        _setupMultiplePositions(dividedAssetPerMultiPair);

        assertApproxEqAbs(
            expectedAssets + initialAssets,
            cellar.totalAssets(),
            10,
            "Total assets should have been lent out"
        );
    }

    // Check that user able to withdraw from multiple lending positions outright
    function testMultiplePositionsUserWithdraw(uint256 assets) external {
        // Have user deposit into cellar
        assets = bound(assets, 0.01e18, 100_000_000e18);
        uint256 dividedAssetPerMultiPair = assets / 3; // amount of FRAX to distribute between different fraxLendPairs
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Test that users can withdraw from multiple pairs at once.
        _setupMultiplePositions(dividedAssetPerMultiPair);

        deal(address(FRAX), address(this), 0);
        uint256 toWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(toWithdraw, address(this), address(this));

        assertApproxEqAbs(
            FRAX.balanceOf(address(this)),
            toWithdraw,
            10,
            "User should have gotten all their FRAX (minus some dust)"
        );
    }

    function testWithdrawableFrom() external {
        cellar.addPosition(0, wEthFraxPairPosition, abi.encode(0), false);

        // Strategist rebalances to withdraw FRAX, and lend in a different pair.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        // Withdraw FRAX from FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeemFromFraxLend(FXS_FRAX_PAIR, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnFraxLend(WETH_FRAX_PAIR, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }
        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        // Make cellar deposits lend FRAX into WETH Pair.
        cellar.setHoldingPosition(wEthFraxPairPosition);

        uint256 assets = 10_000e18;
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        address whaleBorrower = vm.addr(777);

        // Figure out how much the whale must borrow to borrow all the Frax.
        IFToken fToken = IFToken(WETH_FRAX_PAIR);
        (uint128 totalFraxSupplied, , uint128 totalFraxBorrowed, , ) = fToken.getPairAccounting();
        uint256 assetsToBorrow = totalFraxSupplied > totalFraxBorrowed ? totalFraxSupplied - totalFraxBorrowed : 0;
        // Supply 2x the value we are trying to borrow.
        uint256 assetsToSupply = priceRouter.getValue(FRAX, 2 * assetsToBorrow, WETH);

        deal(address(WETH), whaleBorrower, assetsToSupply);
        vm.startPrank(whaleBorrower);
        WETH.approve(WETH_FRAX_PAIR, assetsToSupply);
        fToken.borrowAsset(assetsToBorrow, assetsToSupply, whaleBorrower);
        vm.stopPrank();

        uint256 assetsWithdrawable = cellar.totalAssetsWithdrawable();

        assertEq(assetsWithdrawable, 0, "There should be no assets withdrawable.");

        // Whale repays half of their debt.
        uint256 sharesToRepay = fToken.balanceOf(whaleBorrower) / 2;
        vm.startPrank(whaleBorrower);
        FRAX.approve(WETH_FRAX_PAIR, assetsToBorrow);
        fToken.repayAsset(sharesToRepay, whaleBorrower);
        vm.stopPrank();

        (totalFraxSupplied, , totalFraxBorrowed, , ) = fToken.getPairAccounting();
        uint256 liquidFrax = totalFraxSupplied - totalFraxBorrowed;

        assetsWithdrawable = cellar.totalAssetsWithdrawable();

        assertEq(assetsWithdrawable, liquidFrax, "Should be able to withdraw liquid FRAX.");

        // Have user withdraw the FRAX.
        deal(address(FRAX), address(this), 0);
        cellar.withdraw(liquidFrax, address(this), address(this));
        assertEq(FRAX.balanceOf(address(this)), liquidFrax, "User should have received liquid FRAX.");
    }

    function testDifferencesWhenAccountingForInterestV1() external {
        IFToken fToken = IFToken(FXS_FRAX_PAIR);
        uint256 assets = 1_000_000e18;
        address userA = vm.addr(111);
        address userB = vm.addr(222);
        uint256 expectedInterestEarnedAfter7Days;

        Cellar v1PositionAccountingForInterest = _createSimpleCellar(
            "1",
            fxsFraxPairPosition,
            FXS_FRAX_PAIR,
            address(fTokenAdaptor)
        );
        Cellar v1PositionNotAccountingForInterest = _createSimpleCellar(
            "2",
            mockFxsFraxPairPosition,
            FXS_FRAX_PAIR,
            address(mockFTokenAdaptor)
        );

        GasReadings memory gasWithAccountingForInterest;
        GasReadings memory gasWithoutAccountingForInterest;
        uint256 totalAssets;
        uint256 maxWithdraw;

        uint256 snapshot = vm.snapshot();

        // Start by depositing into first cellar and saving gas values.
        vm.startPrank(userA);
        deal(address(FRAX), userA, assets);
        FRAX.approve(address(v1PositionAccountingForInterest), assets);
        gasWithAccountingForInterest.depositGas = gasleft();
        v1PositionAccountingForInterest.deposit(assets, userA);
        gasWithAccountingForInterest.depositGas = gasWithAccountingForInterest.depositGas - gasleft();
        vm.stopPrank();

        // Save totalAssets.
        gasWithAccountingForInterest.totalAssetsGas = gasleft();
        totalAssets = v1PositionAccountingForInterest.totalAssets();
        gasWithAccountingForInterest.totalAssetsGas = gasWithAccountingForInterest.totalAssetsGas - gasleft();

        // Advance time to earn interest on lent FRAX.
        vm.warp(block.timestamp + 7 days);
        mockFraxUsd.setMockUpdatedAt(block.timestamp);

        assertEq(
            v1PositionAccountingForInterest.totalAssets(),
            totalAssets,
            "No users have interacted with FraxLend so totalAssets remains the same."
        );

        // But if some other user interacts with the FraxLend Pair, totalAssets increases.
        {
            uint256 snapshotBeforeAddInterest = vm.snapshot();
            uint256 totalAssetsBefore = v1PositionAccountingForInterest.totalAssets();
            fToken.addInterest();
            expectedInterestEarnedAfter7Days = v1PositionAccountingForInterest.totalAssets() - totalAssetsBefore;
            assertGt(v1PositionAccountingForInterest.totalAssets(), totalAssets, "Total Assets should have increased.");
            vm.revertTo(snapshotBeforeAddInterest);
        }

        // User Withdraws.
        vm.startPrank(userA);
        maxWithdraw = v1PositionAccountingForInterest.maxWithdraw(userA);
        gasWithAccountingForInterest.withdrawGas = gasleft();
        v1PositionAccountingForInterest.withdraw(maxWithdraw, userA, userA);
        gasWithAccountingForInterest.withdrawGas = gasWithAccountingForInterest.withdrawGas - gasleft();
        vm.stopPrank();

        // Since no one interacted with FraxLend between the users deposit and their withdraw,
        // the interest was NOT accounted for in cellar share price.
        assertApproxEqAbs(
            FRAX.balanceOf(userA),
            assets,
            2,
            "Since no one interacted with FraxLend between the users deposit and their withdraw, the interest was"
        );

        // When the user withdraws, the cellar share price is still 1:1 bc
        // no one has interacted with FraxLend, so the positions balanceOf does not change
        // but during position withdraw, this cellar calls `addInterest`
        // BEFORE calculating the shares needed to redeem to get the assets out the cellar requested.
        // Because of this, the unaccounted for interest is left in the cellar.
        totalAssets = v1PositionAccountingForInterest.totalAssets();
        assertApproxEqAbs(
            totalAssets,
            expectedInterestEarnedAfter7Days + initialAssets,
            1,
            "Yield should be left behind."
        );

        // --------------------- Revert to state before interacting with FraxLend Pair ---------------------
        vm.revertTo(snapshot);

        // Now deposit into other cellar, saving gas values.
        vm.startPrank(userB);
        deal(address(FRAX), userB, assets);
        FRAX.approve(address(v1PositionNotAccountingForInterest), assets);
        gasWithoutAccountingForInterest.depositGas = gasleft();
        v1PositionNotAccountingForInterest.deposit(assets, userB);
        gasWithoutAccountingForInterest.depositGas = gasWithoutAccountingForInterest.depositGas - gasleft();
        vm.stopPrank();

        // Save totalAssets.
        gasWithoutAccountingForInterest.totalAssetsGas = gasleft();
        totalAssets = v1PositionNotAccountingForInterest.totalAssets();
        gasWithoutAccountingForInterest.totalAssetsGas = gasWithoutAccountingForInterest.totalAssetsGas - gasleft();

        // Save snapshot after userB deposit.
        uint256 snapshotAfterUserBDeposit = vm.snapshot();

        // Advance time to earn interest on lent FRAX.
        vm.warp(block.timestamp + 7 days);
        mockFraxUsd.setMockUpdatedAt(block.timestamp);

        assertEq(
            v1PositionNotAccountingForInterest.totalAssets(),
            totalAssets,
            "No users have interacted with FraxLend so totalAssets remains the same."
        );

        // User Withdraws.
        vm.startPrank(userB);
        maxWithdraw = v1PositionNotAccountingForInterest.maxWithdraw(userB);
        gasWithoutAccountingForInterest.withdrawGas = gasleft();
        v1PositionNotAccountingForInterest.withdraw(maxWithdraw, userB, userB);
        gasWithoutAccountingForInterest.withdrawGas = gasWithoutAccountingForInterest.withdrawGas - gasleft();
        vm.stopPrank();

        // Remove the interest that the initial deposit earned.
        expectedInterestEarnedAfter7Days = expectedInterestEarnedAfter7Days.mulDivDown(
            assets,
            (assets + initialAssets)
        );

        // Since no one interacted with FraxLend between the users deposit and their withdraw,
        // the interest was NOT accounted for in cellar share price.
        // But on withdraw we do NOT call `addInterest` before calculating shares to redeem to get the
        // assets out the cellar requested, so we underestimate frax share price, and redeem more shares than are needed.
        assertApproxEqAbs(
            FRAX.balanceOf(userB),
            assets + expectedInterestEarnedAfter7Days,
            2,
            "User FRAX balance should equal assets + interest earned."
        );

        // Revert back to right after userB deposit, and have userA join.
        vm.revertTo(snapshotAfterUserBDeposit);

        vm.startPrank(userA);
        deal(address(FRAX), userA, assets);
        FRAX.approve(address(v1PositionNotAccountingForInterest), assets);
        v1PositionNotAccountingForInterest.deposit(assets, userA);
        vm.stopPrank();

        // Advance time to earn interest on lent FRAX.
        vm.warp(block.timestamp + 365 days);
        mockFraxUsd.setMockUpdatedAt(block.timestamp);

        // Figure out how much interest was earned.
        {
            uint256 snapshotBeforeAddInterest = vm.snapshot();
            uint256 totalAssetsBefore = v1PositionNotAccountingForInterest.totalAssets();
            fToken.addInterest();
            expectedInterestEarnedAfter7Days = v1PositionNotAccountingForInterest.totalAssets() - totalAssetsBefore;
            vm.revertTo(snapshotBeforeAddInterest);
        }

        // Users Withdraw.
        vm.startPrank(userB);
        maxWithdraw = v1PositionNotAccountingForInterest.maxWithdraw(userB);
        v1PositionNotAccountingForInterest.withdraw(maxWithdraw, userB, userB);
        vm.stopPrank();

        vm.startPrank(userA);
        maxWithdraw = v1PositionNotAccountingForInterest.maxWithdraw(userA);
        v1PositionNotAccountingForInterest.withdraw(maxWithdraw, userA, userA);
        vm.stopPrank();

        // Since no one interacted with FraxLend between the users deposit and their withdraw,
        // the interest was NOT accounted for in cellar share price.
        // But on withdraw we do NOT call `addInterest` before calculating shares to redeem to get the
        // assets out the cellar requested, so we underestimate frax share price, and redeem more shares than are needed.
        uint256 userBFraxBalance = FRAX.balanceOf(userB);
        uint256 userAFraxBalance = FRAX.balanceOf(userA);

        // But at the end of it all each user earned their expected yield.
        assertApproxEqAbs(userBFraxBalance, userAFraxBalance, 2, "User Balances should be approximately equal.");

        // --------------------- Compare gas values ---------------------
        // assertEq(
        //     gasWithoutAccountingForInterest.depositGas,
        //     gasWithAccountingForInterest.depositGas,
        //     "depositGas should be the same."
        // );

        assertEq(
            gasWithoutAccountingForInterest.totalAssetsGas,
            gasWithAccountingForInterest.totalAssetsGas,
            "totalAssetsGas should be the same."
        );

        assertGt(
            gasWithAccountingForInterest.withdrawGas,
            gasWithoutAccountingForInterest.withdrawGas,
            "withdrawGas should higher when we account for interest."
        );

        uint256 withdrawGasDelta = gasWithAccountingForInterest.withdrawGas -
            gasWithoutAccountingForInterest.withdrawGas;

        assertApproxEqAbs(withdrawGasDelta, 4_500, 100, "Delta should be around 4.5k");

        // --------------------- TLDR ---------------------
        // If you account for interest, gas cost is increased by 4.5k for withdrawals, and in the edge case where
        // there are no contract interactions with the FraxLend pair between when the user deposits
        // into the cellar, and when the user withdraws, that user will not get their share of the yield.

        // For the v1 fTokenAdaptor it is best to NOT ACCOUNT FOR INTEREST, since the
        // cellar share price does not update, and the FraxLend share price does not update,
        // they cancel out, and we actually withdraw the appropriate amount from FraxLend.
    }

    function testDifferencesWhenAccountingForInterestV2() external {
        uint256 assets = 1_000_000e18;
        address userA = vm.addr(111);
        address userB = vm.addr(222);
        uint256 expectedInterestEarnedAfter7Days;

        Cellar v2PositionAccountingForInterest = _createSimpleCellar(
            "1",
            sfrxEthFraxPairPosition,
            SFRXETH_FRAX_PAIR,
            address(fTokenAdaptorV2)
        );
        Cellar v2PositionNotAccountingForInterest = _createSimpleCellar(
            "2",
            mockSfrxEthFraxPairPosition,
            SFRXETH_FRAX_PAIR,
            address(mockFTokenAdaptorV2)
        );

        GasReadings memory gasWithAccountingForInterest;
        GasReadings memory gasWithoutAccountingForInterest;
        uint256 totalAssets;
        uint256 maxWithdraw;

        uint256 snapshot = vm.snapshot();

        // Start by depositing into first cellar and saving gas values.
        vm.startPrank(userA);
        deal(address(FRAX), userA, assets);
        FRAX.approve(address(v2PositionAccountingForInterest), assets);
        gasWithAccountingForInterest.depositGas = gasleft();
        v2PositionAccountingForInterest.deposit(assets, userA);
        gasWithAccountingForInterest.depositGas = gasWithAccountingForInterest.depositGas - gasleft();
        vm.stopPrank();

        // Save totalAssets.
        gasWithAccountingForInterest.totalAssetsGas = gasleft();
        totalAssets = v2PositionAccountingForInterest.totalAssets();
        gasWithAccountingForInterest.totalAssetsGas = gasWithAccountingForInterest.totalAssetsGas - gasleft();

        {
            // Advance time to earn interest on lent FRAX.
            vm.warp(block.timestamp + 7 days);
            mockFraxUsd.setMockUpdatedAt(block.timestamp);
            expectedInterestEarnedAfter7Days = v2PositionAccountingForInterest.totalAssets() - totalAssets;
            assertGt(
                v2PositionAccountingForInterest.totalAssets(),
                totalAssets,
                "Cellar totalAssets should increase over time since we are accounting for interest."
            );
        }

        // User Withdraws.
        vm.startPrank(userA);
        maxWithdraw = v2PositionAccountingForInterest.maxWithdraw(userA);
        gasWithAccountingForInterest.withdrawGas = gasleft();
        v2PositionAccountingForInterest.withdraw(maxWithdraw, userA, userA);
        gasWithAccountingForInterest.withdrawGas = gasWithAccountingForInterest.withdrawGas - gasleft();
        vm.stopPrank();

        expectedInterestEarnedAfter7Days = expectedInterestEarnedAfter7Days.mulDivDown(
            assets,
            (assets + initialAssets)
        );

        // User should get all the yield they are owed.
        assertApproxEqAbs(
            FRAX.balanceOf(userA),
            assets + expectedInterestEarnedAfter7Days,
            2,
            "Since we are accounting for interest, the user should get their assets + interest."
        );

        // --------------------- Revert to state before interacting with FraxLend Pair ---------------------
        vm.revertTo(snapshot);

        // Now deposit into other cellar, saving gas values.
        vm.startPrank(userB);
        deal(address(FRAX), userB, assets);
        FRAX.approve(address(v2PositionNotAccountingForInterest), assets);
        gasWithoutAccountingForInterest.depositGas = gasleft();
        v2PositionNotAccountingForInterest.deposit(assets, userB);
        gasWithoutAccountingForInterest.depositGas = gasWithoutAccountingForInterest.depositGas - gasleft();
        vm.stopPrank();

        // Save totalAssets.
        gasWithoutAccountingForInterest.totalAssetsGas = gasleft();
        totalAssets = v2PositionNotAccountingForInterest.totalAssets();
        gasWithoutAccountingForInterest.totalAssetsGas = gasWithoutAccountingForInterest.totalAssetsGas - gasleft();

        // Advance time to earn interest on lent FRAX.
        vm.warp(block.timestamp + 7 days);
        mockFraxUsd.setMockUpdatedAt(block.timestamp);

        assertEq(
            v2PositionNotAccountingForInterest.totalAssets(),
            totalAssets,
            "No users have interacted with FraxLend so totalAssets remains the same."
        );

        // User Withdraws.
        vm.startPrank(userB);
        maxWithdraw = v2PositionNotAccountingForInterest.maxWithdraw(userB);
        gasWithoutAccountingForInterest.withdrawGas = gasleft();
        v2PositionNotAccountingForInterest.withdraw(maxWithdraw, userB, userB);
        gasWithoutAccountingForInterest.withdrawGas = gasWithoutAccountingForInterest.withdrawGas - gasleft();
        vm.stopPrank();

        // Since the cellar share price is not updated until after the cellar interacts with FraxLend,
        // the users Cellar shares are undervalued, and they only get their initial capital out, but no yield.
        assertApproxEqAbs(FRAX.balanceOf(userB), assets, 2, "User FRAX balance should equal assets.");

        // The yield is left in the cellar.
        assertGt(v2PositionNotAccountingForInterest.totalAssets(), initialAssets, "There should be assets left.");

        // --------------------- Compare gas values ---------------------
        // assertGt(
        //     gasWithAccountingForInterest.depositGas,
        //     gasWithoutAccountingForInterest.depositGas,
        //     "depositGas should be higher when accounting for interest."
        // );

        // uint256 depositGasDelta = gasWithAccountingForInterest.depositGas - gasWithoutAccountingForInterest.depositGas;
        // assertApproxEqAbs(depositGasDelta, 5_800, 100, "Delta should be around 5.8k");

        // assertGt(
        //     gasWithAccountingForInterest.totalAssetsGas,
        //     gasWithoutAccountingForInterest.totalAssetsGas,
        //     "totalAssetsGas should be higher when accounting for interest."
        // );

        // uint256 totalAssetsGasDelta = gasWithAccountingForInterest.totalAssetsGas -
        //     gasWithoutAccountingForInterest.totalAssetsGas;
        // assertApproxEqAbs(totalAssetsGasDelta, 1_700, 100, "Delta should be around 1.7k");

        // assertGt(
        //     gasWithAccountingForInterest.withdrawGas,
        //     gasWithoutAccountingForInterest.withdrawGas,
        //     "withdrawGas should higher when we account for interest."
        // );

        // uint256 withdrawGasDelta = gasWithAccountingForInterest.withdrawGas -
        //     gasWithoutAccountingForInterest.withdrawGas;

        // assertApproxEqAbs(withdrawGasDelta, 11_400, 100, "Delta should be around 11.4k");

        // --------------------- TLDR ---------------------
        // When accounting for interest the following operations become X% more gas intensive.
        // Deposits: 2%
        // TotalAssets: 5.6%
        // Withdraws: 8.9%
        //
        // The gas increase is fairly minimal in exchange for more accurate share price calculations.
        // It is generally better to account for interest earned, so that users do not run the
        // possibility of either getting the share price arbed(in the case of divergence between
        // cellar share price and FraxLend pair share price, which happens when the pair is not
        // interacted with for a long time.), or the user leaves the cellar without getting the yield
        // their capital generated.
        //
        // This being said if the Cellar is rebalancing its FraxLend positions regularly (3-7 days) the
        // divergence between the two share prices will be minimal, and cellar interactions will be cheaper.
        // Also the strategist would be able to move assets into reserves without lowering share price.
    }

    function testAddInterest() external {
        // Add v2 FraxLend Pair position to Cellar.
        cellar.addPosition(0, sfrxEthFraxPairPosition, abi.encode(0), false);

        // Strategist rebalances to withdraw FRAX, and lend in a different pair.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        // Withdraw FRAX from FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToCallAddInterestOnFraxLend(FXS_FRAX_PAIR);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToCallAddInterestOnFraxLend(SFRXETH_FRAX_PAIR);
            data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);
    }

    // ========================================= HELPER FUNCTIONS =========================================

    struct GasReadings {
        uint256 depositGas;
        uint256 totalAssetsGas;
        uint256 withdrawGas;
    }

    // setup multiple lending positions
    function _setupMultiplePositions(uint256 dividedAssetPerMultiPair) internal {
        // add numerous frax pairs atop of holdingPosition (fxs)
        cellar.addPosition(0, sfrxEthFraxPairPosition, abi.encode(0), false);
        cellar.addPosition(0, fpiFraxPairPosition, abi.encode(0), false);

        // Strategist rebalances to withdraw set amount of FRAX, and lend in a different pair.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Withdraw 2/3 of cellar FRAX from FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeemFromFraxLend(FXS_FRAX_PAIR, dividedAssetPerMultiPair * 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnFraxLend(SFRXETH_FRAX_PAIR, dividedAssetPerMultiPair);
            data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnFraxLend(FPI_FRAX_PAIR, type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);
    }

    function _createSimpleCellar(
        string memory cellarName,
        uint32 holdingPosition,
        address pair,
        address adaptorToUse
    ) internal returns (Cellar simpleCellar) {
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        simpleCellar = _createCellar(cellarName, FRAX, fraxPosition, abi.encode(0), initialDeposit, platformCut);

        simpleCellar.addAdaptorToCatalogue(address(adaptorToUse));
        simpleCellar.addPositionToCatalogue(holdingPosition);

        simpleCellar.addPosition(0, holdingPosition, abi.encode(0), false);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend FRAX on FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnFraxLend(pair, initialDeposit);
            data[0] = Cellar.AdaptorCall({ adaptor: address(adaptorToUse), callData: adaptorCalls });
        }

        simpleCellar.callOnAdaptor(data);

        simpleCellar.setHoldingPosition(holdingPosition);
    }
}
