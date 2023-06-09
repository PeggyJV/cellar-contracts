// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import { FTokenAdaptorV1 } from "src/modules/adaptors/Frax/FTokenAdaptorV1.sol";
import { MockFTokenAdaptor } from "src/mocks/adaptors/MockFTokenAdaptor.sol";
import { MockFTokenAdaptorV1 } from "src/mocks/adaptors/MockFTokenAdaptorV1.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract FraxLendFTokenAdaptorTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    ERC20Adaptor private erc20Adaptor;
    FTokenAdaptor private fTokenAdaptorV2;
    FTokenAdaptorV1 private fTokenAdaptor;
    MockFTokenAdaptor private mockFTokenAdaptorV2;
    MockFTokenAdaptorV1 private mockFTokenAdaptor;
    CellarInitializableV2_2 private cellar;
    PriceRouter private priceRouter;
    Registry private registry;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    address private UNTRUSTED_sfrxETH = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15;

    ERC20 public FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // FraxLend fToken pairs.
    address private FXS_FRAX_PAIR = 0xDbe88DBAc39263c47629ebbA02b3eF4cf0752A72;
    address private FPI_FRAX_PAIR = 0x74F82Bd9D0390A4180DaaEc92D64cf0708751759;
    address private SFRXETH_FRAX_PAIR = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15;
    address private WETH_FRAX_PAIR = 0x794F6B13FBd7EB7ef10d1ED205c9a416910207Ff;

    // Chainlink PriceFeeds
    MockDataFeed private mockFraxUsd;
    MockDataFeed private mockWethUsd;
    address private FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    uint32 private fraxPosition;
    uint32 private fxsFraxPairPosition;
    uint32 private fpiFraxPairPosition;
    uint32 private sfrxEthFraxPairPosition;
    uint32 private wEthFraxPairPosition;

    // Mock Positions
    uint32 private mockFxsFraxPairPosition;
    uint32 private mockSfrxEthFraxPairPosition;

    modifier checkBlockNumber() {
        if (block.number < 16869780) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16869780.");
            return;
        }
        _;
    }

    function setUp() external {
        mockFraxUsd = new MockDataFeed(FRAX_USD_FEED);
        mockWethUsd = new MockDataFeed(WETH_USD_FEED);
        fTokenAdaptorV2 = new FTokenAdaptor();
        fTokenAdaptor = new FTokenAdaptorV1();
        mockFTokenAdaptorV2 = new MockFTokenAdaptor();
        mockFTokenAdaptor = new MockFTokenAdaptorV1();
        erc20Adaptor = new ERC20Adaptor();

        registry = new Registry(address(this), address(this), address(priceRouter));
        priceRouter = new PriceRouter(registry);
        registry.setAddress(2, address(priceRouter));

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
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(fTokenAdaptor));
        registry.trustAdaptor(address(fTokenAdaptorV2));
        registry.trustAdaptor(address(mockFTokenAdaptorV2));
        registry.trustAdaptor(address(mockFTokenAdaptor));

        fraxPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(FRAX));
        fxsFraxPairPosition = registry.trustPosition(address(fTokenAdaptor), abi.encode(FXS_FRAX_PAIR));
        fpiFraxPairPosition = registry.trustPosition(address(fTokenAdaptor), abi.encode(FPI_FRAX_PAIR));
        sfrxEthFraxPairPosition = registry.trustPosition(address(fTokenAdaptorV2), abi.encode(SFRXETH_FRAX_PAIR));
        wEthFraxPairPosition = registry.trustPosition(address(fTokenAdaptor), abi.encode(WETH_FRAX_PAIR));
        mockFxsFraxPairPosition = registry.trustPosition(address(mockFTokenAdaptor), abi.encode(FXS_FRAX_PAIR));
        mockSfrxEthFraxPairPosition = registry.trustPosition(
            address(mockFTokenAdaptorV2),
            abi.encode(SFRXETH_FRAX_PAIR)
        );

        cellar = new CellarInitializableV2_2(registry);
        cellar.initialize(
            abi.encode(
                address(this),
                registry,
                FRAX,
                "Fraximal Cellar",
                "oWo",
                fxsFraxPairPosition,
                abi.encode(0),
                strategist
            )
        );

        cellar.addAdaptorToCatalogue(address(fTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(fTokenAdaptorV2));

        cellar.addPositionToCatalogue(fraxPosition);
        cellar.addPositionToCatalogue(fpiFraxPairPosition);
        cellar.addPositionToCatalogue(sfrxEthFraxPairPosition);
        cellar.addPositionToCatalogue(wEthFraxPairPosition);

        FRAX.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
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
        assertApproxEqAbs(cellar.totalAssets(), assets, 2, "Total assets should equal assets deposited.");
    }

    function testLendingFrax(uint256 assets) external {
        // Add FRAX position and change holding position to vanilla FRAX.
        cellar.addPosition(0, fraxPosition, abi.encode(0), false);
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
            adaptorCalls[0] = _createBytesDataToLend(FXS_FRAX_PAIR, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        IFToken pair = IFToken(FXS_FRAX_PAIR);
        uint256 shareBalance = pair.balanceOf(address(cellar));
        assertTrue(shareBalance > 0, "Cellar should own shares.");
        assertApproxEqAbs(
            pair.toAssetAmount(shareBalance, false),
            assets,
            2,
            "Rebalance should have lent all FRAX on FraxLend."
        );
    }

    function testWithdrawingFrax(uint256 assets) external {
        // Add vanilla FRAX as a position in the cellar.
        cellar.addPosition(0, fraxPosition, abi.encode(0), false);

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to withdraw FRAX.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Withdraw FRAX from FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeem(FXS_FRAX_PAIR, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            FRAX.balanceOf(address(cellar)),
            assets,
            2,
            "Cellar FRAX should have been withdraw from FraxLend."
        );
    }

    function testRebalancingBetweenPairs(uint256 assets) external {
        // Add another Frax Lend pair, and vanilla FRAX.
        cellar.addPosition(0, sfrxEthFraxPairPosition, abi.encode(0), false);
        cellar.addPosition(0, fraxPosition, abi.encode(0), false);

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to withdraw FRAX, and lend in a different pair.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        // Withdraw FRAX from FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeem(FXS_FRAX_PAIR, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(SFRXETH_FRAX_PAIR, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        IFToken pair = IFToken(SFRXETH_FRAX_PAIR);
        uint256 shareBalance = pair.balanceOf(address(cellar));
        assertTrue(shareBalance > 0, "Cellar should own shares.");
        assertApproxEqAbs(
            pair.toAssetAmount(shareBalance, false, false),
            assets,
            10,
            "Rebalance should have lent in other pair."
        );

        // Withdraw half the assets from Frax Pair V2.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdraw(SFRXETH_FRAX_PAIR, assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        assertEq(FRAX.balanceOf(address(cellar)), assets / 2, "Should have withdrawn half the assets from FraxLend.");
    }

    // try lending and redeemin with fTokens that are not positions in the cellar and check for revert.
    function testUsingPairNotSetupAsPosition(uint256 assets) external {
        // Add FRAX position and change holding position to vanilla FRAX.
        cellar.addPosition(0, fraxPosition, abi.encode(0), false);
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
            adaptorCalls[0] = _createBytesDataToLend(UNTRUSTED_sfrxETH, assets);
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
            adaptorCalls[0] = _createBytesDataToRedeem(maliciousContract, assets);
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
            adaptorCalls[0] = _createBytesDataToWithdraw(maliciousContract, assets);
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

    // Check that FRAX in multiple different pairs is correctly accounted for in total assets.
    function testMultiplePositionsTotalAssets(uint256 assets) external {
        // Have user deposit into cellar
        assets = bound(assets, 0.01e18, 100_000_000e18);
        uint256 expectedAssets = assets;
        uint256 dividedAssetPerMultiPair = assets / 3; // amount of FRAX to distribute between different fraxLendPairs
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Test that users can withdraw from multiple pairs at once.
        _setupMultiplePositions(dividedAssetPerMultiPair);

        assertApproxEqAbs(expectedAssets, cellar.totalAssets(), 10, "Total assets should have been lent out");
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
        // Make cellar deposits lend FRAX into WETH Pair.
        cellar.addPosition(0, wEthFraxPairPosition, abi.encode(0), false);
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

        CellarInitializableV2_2 v1PositionAccountingForInterest = _createSimpleCellar(
            fxsFraxPairPosition,
            address(fTokenAdaptor)
        );
        CellarInitializableV2_2 v1PositionNotAccountingForInterest = _createSimpleCellar(
            mockFxsFraxPairPosition,
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
        assertApproxEqAbs(totalAssets, expectedInterestEarnedAfter7Days, 1, "Yield should be left behind.");

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

        totalAssets = v1PositionAccountingForInterest.totalAssets();
        assertEq(totalAssets, 0, "No Assets should be left behind.");

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
        assertEq(
            gasWithoutAccountingForInterest.depositGas,
            gasWithAccountingForInterest.depositGas,
            "depositGas should be the same."
        );

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

        CellarInitializableV2_2 v1PositionAccountingForInterest = _createSimpleCellar(
            sfrxEthFraxPairPosition,
            address(fTokenAdaptorV2)
        );
        CellarInitializableV2_2 v1PositionNotAccountingForInterest = _createSimpleCellar(
            mockSfrxEthFraxPairPosition,
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
        FRAX.approve(address(v1PositionAccountingForInterest), assets);
        gasWithAccountingForInterest.depositGas = gasleft();
        v1PositionAccountingForInterest.deposit(assets, userA);
        gasWithAccountingForInterest.depositGas = gasWithAccountingForInterest.depositGas - gasleft();
        vm.stopPrank();

        // Save totalAssets.
        gasWithAccountingForInterest.totalAssetsGas = gasleft();
        totalAssets = v1PositionAccountingForInterest.totalAssets();
        gasWithAccountingForInterest.totalAssetsGas = gasWithAccountingForInterest.totalAssetsGas - gasleft();

        {
            // Advance time to earn interest on lent FRAX.
            vm.warp(block.timestamp + 7 days);
            mockFraxUsd.setMockUpdatedAt(block.timestamp);
            expectedInterestEarnedAfter7Days = v1PositionAccountingForInterest.totalAssets() - totalAssets;
            assertGt(
                v1PositionAccountingForInterest.totalAssets(),
                totalAssets,
                "Cellar totalAssets should increase over time since we are accounting for interest."
            );
        }

        // User Withdraws.
        vm.startPrank(userA);
        maxWithdraw = v1PositionAccountingForInterest.maxWithdraw(userA);
        gasWithAccountingForInterest.withdrawGas = gasleft();
        v1PositionAccountingForInterest.withdraw(maxWithdraw, userA, userA);
        gasWithAccountingForInterest.withdrawGas = gasWithAccountingForInterest.withdrawGas - gasleft();
        vm.stopPrank();

        // User should get all the yield they are owed.
        assertApproxEqAbs(
            FRAX.balanceOf(userA),
            assets + expectedInterestEarnedAfter7Days,
            2,
            "Since we are accounting for interest, the user should get their assets + interest."
        );

        totalAssets = v1PositionAccountingForInterest.totalAssets();
        assertEq(totalAssets, 0, "No Assets should be left behind.");

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

        // Since the cellar share price is not updated until after the cellar interacts with FraxLend,
        // the users Cellar shares are undervalued, and they only get their initial capital out, but no yield.
        assertApproxEqAbs(FRAX.balanceOf(userB), assets, 2, "User FRAX balance should equal assets.");

        // The yield is left in the cellar.
        assertGt(v1PositionNotAccountingForInterest.totalAssets(), 0, "There should be assets left.");

        // --------------------- Compare gas values ---------------------
        assertGt(
            gasWithAccountingForInterest.depositGas,
            gasWithoutAccountingForInterest.depositGas,
            "depositGas should be higher when accounting for interest."
        );

        uint256 depositGasDelta = gasWithAccountingForInterest.depositGas - gasWithoutAccountingForInterest.depositGas;
        assertApproxEqAbs(depositGasDelta, 5_800, 100, "Delta should be around 5.8k");

        assertGt(
            gasWithAccountingForInterest.totalAssetsGas,
            gasWithoutAccountingForInterest.totalAssetsGas,
            "totalAssetsGas should be higher when accounting for interest."
        );

        uint256 totalAssetsGasDelta = gasWithAccountingForInterest.totalAssetsGas -
            gasWithoutAccountingForInterest.totalAssetsGas;
        assertApproxEqAbs(totalAssetsGasDelta, 1_700, 100, "Delta should be around 1.7k");

        assertGt(
            gasWithAccountingForInterest.withdrawGas,
            gasWithoutAccountingForInterest.withdrawGas,
            "withdrawGas should higher when we account for interest."
        );

        uint256 withdrawGasDelta = gasWithAccountingForInterest.withdrawGas -
            gasWithoutAccountingForInterest.withdrawGas;

        assertApproxEqAbs(withdrawGasDelta, 11_400, 100, "Delta should be around 11.4k");

        console.log("depositGas", gasWithoutAccountingForInterest.depositGas);
        console.log("depositGasDelta", depositGasDelta);
        console.log("totalAssetsGas", gasWithoutAccountingForInterest.totalAssetsGas);
        console.log("totalAssetsGasDelta", totalAssetsGasDelta);
        console.log("withdrawGas", gasWithoutAccountingForInterest.withdrawGas);
        console.log("withdrawGasDelta", withdrawGasDelta);

        // --------------------- TLDR ---------------------
    }

    // ========================================= HELPER FUNCTIONS =========================================

    struct GasReadings {
        uint256 depositGas;
        uint256 totalAssetsGas;
        uint256 withdrawGas;
    }

    function _createBytesDataToLend(address fToken, uint256 amountToDeposit) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.lendFrax.selector, fToken, amountToDeposit);
    }

    function _createBytesDataToRedeem(address fToken, uint256 amountToRedeem) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.redeemFraxShare.selector, fToken, amountToRedeem);
    }

    function _createBytesDataToWithdraw(address fToken, uint256 amountToWithdraw) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.withdrawFrax.selector, fToken, amountToWithdraw);
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
            adaptorCalls[0] = _createBytesDataToRedeem(FXS_FRAX_PAIR, dividedAssetPerMultiPair * 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(SFRXETH_FRAX_PAIR, dividedAssetPerMultiPair);
            data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(FPI_FRAX_PAIR, type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);
    }

    function _createSimpleCellar(
        uint32 holdingPosition,
        address adaptorToUse
    ) internal returns (CellarInitializableV2_2 simpleCellar) {
        simpleCellar = new CellarInitializableV2_2(registry);
        simpleCellar.initialize(
            abi.encode(
                address(this),
                registry,
                FRAX,
                "Simple Cellar",
                "oWo",
                holdingPosition,
                abi.encode(0),
                strategist
            )
        );

        simpleCellar.addAdaptorToCatalogue(address(adaptorToUse));

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(simpleCellar)).sig(simpleCellar.shareLockPeriod.selector).checked_write(uint256(0));
    }
}
