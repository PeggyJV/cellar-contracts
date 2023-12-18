// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CTokenAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";
// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { CompoundV2DebtAdaptor } from "src/modules/adaptors/Compound/CompoundV2DebtAdaptor.sol";
import { Math } from "src/utils/Math.sol";

/**
 * TODO - troubleshoot decimals and health factor calcs via console logs
 * TODO - test basic cTokens
 * TODO - test cTokens that are using native ETH
 */
contract CellarCompoundTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    CTokenAdaptor private cTokenAdaptor;
    CompoundV2DebtAdaptor private compoundV2DebtAdaptor;
    VestingSimpleAdaptor private vestingAdaptor;
    VestingSimple private vesting;
    Cellar private cellar;

    Comptroller private comptroller = Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    uint32 private daiPosition = 1;
    uint32 private cDAIPosition = 2;
    uint32 private usdcPosition = 3;
    uint32 private cUSDCPosition = 4;
    uint32 private daiVestingPosition = 5;
    uint32 private cDAIDebtPosition = 6;
    // uint32 private cUSDCDebtPosition = 7;
    // TODO: add positions for ETH CTokens

    uint256 private minHealthFactor = 1.1e18;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        vesting = new VestingSimple(USDC, 1 days / 4, 1e6);
        cTokenAdaptor = new CTokenAdaptor(address(comptroller), address(COMP), minHealthFactor);
        compoundV2DebtAdaptor = new CompoundV2DebtAdaptor(false, address(comptroller), address(COMP), minHealthFactor);

        vestingAdaptor = new VestingSimpleAdaptor();

        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(COMP_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, COMP_USD_FEED);
        priceRouter.addAsset(COMP, settings, abi.encode(stor), price);

        // Setup Cellar:
        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(cTokenAdaptor));
        registry.trustAdaptor(address(vestingAdaptor));
        registry.trustAdaptor(address(compoundV2DebtAdaptor));

        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(DAI));
        registry.trustPosition(cDAIPosition, address(cTokenAdaptor), abi.encode(cDAI));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(cUSDCPosition, address(cTokenAdaptor), abi.encode(cUSDC));
        registry.trustPosition(daiVestingPosition, address(vestingAdaptor), abi.encode(vesting));

        // trust debtAdaptor positions
        registry.trustPosition(cDAIDebtPosition, address(compoundV2DebtAdaptor), abi.encode(cDAI));
        // registry.trustPosition(cUSDCDebtPosition, address(compoundV2DebtAdaptor), abi.encode(cUSDC));

        string memory cellarName = "Compound Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, DAI, cDAIPosition, abi.encode(0), initialDeposit, platformCut);

        cellar.setRebalanceDeviation(0.003e18);
        cellar.addAdaptorToCatalogue(address(cTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(vestingAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));
        cellar.addAdaptorToCatalogue(address(compoundV2DebtAdaptor));

        cellar.addPositionToCatalogue(daiPosition);
        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPositionToCatalogue(cUSDCPosition);
        cellar.addPositionToCatalogue(daiVestingPosition);
        cellar.addPositionToCatalogue(cDAIDebtPosition);
        // cellar.addPositionToCatalogue(cUSDCDebtPosition);

        cellar.addPosition(1, daiPosition, abi.encode(0), false);
        cellar.addPosition(2, usdcPosition, abi.encode(0), false);
        cellar.addPosition(3, cUSDCPosition, abi.encode(0), false);
        cellar.addPosition(4, daiVestingPosition, abi.encode(0), false);
        cellar.addPosition(5, cDAIDebtPosition, abi.encode(0), true);
        // cellar.addPosition(6, cUSDCDebtPosition, abi.encode(0), true);

        DAI.safeApprove(address(cellar), type(uint256).max);
    }

    function testDeposit(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqRel(
            cDAI.balanceOf(address(cellar)).mulDivDown(cDAI.exchangeRateStored(), 1e18),
            assets + initialAssets,
            0.001e18,
            "Assets should have been deposited into Compound."
        );
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        deal(address(DAI), address(this), 0);
        uint256 amountToWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        assertEq(DAI.balanceOf(address(this)), amountToWithdraw, "Amount withdrawn should equal callers DAI balance.");
    }

    function testTotalAssets() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 1_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqRel(
            cellar.totalAssets(),
            assets + initialAssets,
            0.0002e18,
            "Total assets should equal assets deposited."
        );

        // Swap from DAI to USDC and lend USDC on Compound.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwapWithUniv3(DAI, USDC, 100, assets / 2);
            data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cUSDC, type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        // Account for 0.1% Swap Fee.
        assets = assets - assets.mulDivDown(0.001e18, 2e18);
        // Make sure Total Assets is reasonable.
        assertApproxEqRel(
            cellar.totalAssets(),
            assets + initialAssets,
            0.001e18,
            "Total assets should equal assets deposited minus swap fees."
        );
    }

    function testClaimCompAndVest() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 10_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        // Manipulate Comptroller storage to give Cellar some pending COMP.
        uint256 compReward = 10e18;
        stdstore
            .target(address(comptroller))
            .sig(comptroller.compAccrued.selector)
            .with_key(address(cellar))
            .checked_write(compReward);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Create data to claim COMP and swap it for USDC.
        address[] memory path = new address[](3);
        path[0] = address(COMP);
        path[1] = address(WETH);
        path[2] = address(USDC);
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 500;
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(CTokenAdaptor.claimComp.selector);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                SwapWithUniswapAdaptor.swapWithUniV3.selector,
                path,
                poolFees,
                type(uint256).max,
                0
            );
            data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            // Create data to vest USDC.
            adaptorCalls[0] = abi.encodeWithSelector(
                VestingSimpleAdaptor.depositToVesting.selector,
                vesting,
                type(uint256).max
            );
            data[2] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        uint256 totalAssets = cellar.totalAssets();

        // Pass time to fully vest the USDC.
        vm.warp(block.timestamp + 1 days / 4);

        assertApproxEqRel(
            cellar.totalAssets(),
            totalAssets + priceRouter.getValue(COMP, compReward, USDC) + initialAssets,
            0.05e18,
            "New totalAssets should equal previous plus vested USDC."
        );
    }

    function testMaliciousStrategistMovingFundsIntoUntrackedCompoundPosition() external {
        uint256 initialAssets = cellar.totalAssets();
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // Remove cDAI as a position from Cellar.
        cellar.setHoldingPosition(daiPosition);
        cellar.removePosition(0, false);

        // Add DAI to the Cellar.
        uint256 assets = 100_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 assetsBeforeAttack = cellar.totalAssets();

        // Strategist malicously makes several `callOnAdaptor` calls to lower the Cellars Share Price.
        data = new Cellar.AdaptorCall[](1);
        adaptorCalls = new bytes[](1);
        uint256 amountToLend = assets;
        for (uint8 i; i < 10; i++) {
            // Choose a value close to the Cellars rebalance deviation limit.
            amountToLend = cellar.totalAssets().mulDivDown(0.003e18, 1e18);
            adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cDAI, amountToLend);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }
        uint256 assetsLost = assetsBeforeAttack - cellar.totalAssets();
        assertApproxEqRel(
            assetsLost,
            assets.mulDivDown(0.03e18, 1e18),
            0.02e18,
            "Assets Lost should be about 3% of original TVL."
        );

        // Somm Governance sees suspicious rebalances, and temporarily shuts down the cellar.
        cellar.initiateShutdown();

        // Somm Governance revokes old strategists privilages and puts in new strategist.

        // Shut down is lifted, and strategist rebalances cellar back to original value.
        cellar.liftShutdown();
        uint256 amountToWithdraw = assetsLost / 12;
        for (uint8 i; i < 12; i++) {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, amountToWithdraw);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        assertApproxEqRel(
            cellar.totalAssets(),
            assets + initialAssets,
            0.001e18,
            "totalAssets should be equal to original assets."
        );
    }

    function testAddingPositionWithUnsupportedAssetsReverts() external {
        // trust position fails because TUSD is not set up for pricing.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Registry.Registry__PositionPricingNotSetUp.selector, address(TUSD)))
        );
        registry.trustPosition(300, address(cTokenAdaptor), abi.encode(address(cTUSD)));

        // Add TUSD.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(TUSD_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, TUSD_USD_FEED);
        priceRouter.addAsset(TUSD, settings, abi.encode(stor), price);

        // trust position works now.
        registry.trustPosition(300, address(cTokenAdaptor), abi.encode(address(cTUSD)));
    }

    function testErrorCodeCheck() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);
        // Remove cDAI as a position from Cellar.
        cellar.setHoldingPosition(daiPosition);
        cellar.removePosition(0, false);

        // Add DAI to the Cellar.
        uint256 assets = 100_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        // Convert cellar assets to USDC.
        assets = assets.changeDecimals(18, 6);
        deal(address(DAI), address(cellar), 0);
        deal(address(USDC), address(cellar), assets);

        // Strategist tries to lend more USDC then they have,
        data = new Cellar.AdaptorCall[](1);
        adaptorCalls = new bytes[](1);

        // Choose an amount too large so deposit fails.
        uint256 amountToLend = assets + 1;

        adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cUSDC, amountToLend);
        data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__NonZeroCompoundErrorCode.selector, 13))
        );
        cellar.callOnAdaptor(data);

        // Strategist tries to withdraw more assets then they have.
        adaptorCalls = new bytes[](2);
        amountToLend = assets;
        uint256 amountToWithdraw = assets + 1e6;

        adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cUSDC, amountToLend);
        adaptorCalls[1] = _createBytesDataToWithdrawFromCompoundV2(cUSDC, amountToWithdraw);
        data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__NonZeroCompoundErrorCode.selector, 9))
        );
        cellar.callOnAdaptor(data);
    }

    /// Extra test for supporting providing collateral && open borrow positions

    // TODO repeat above tests but for positions that have marked their cToken positions as collateral provision

    function testEnterMarket(uint256 assets) external {
        // TODO below checks AFTER entering the market
        // TODO check that totalAssets reports properly
        // TODO check that balanceOf reports properly
        // TODO check that withdrawableFrom reports properly
        // TODO check that user deposits add to collateral position
        // TODO check that user withdraws work when no debt-position is open
        // TODO check that strategist function to enterMarket reverts if you're already in the market
        // TODO check that you can exit the market, then enter again

        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position is cDAI (w/o entering market)

        // TODO - MOVE BELOW BLOB ABOUT CHECKING IN MARKET TO ENTER MARKET TEST
        // check that we aren't in market
        bool inCTokenMarket = _checkInMarket(cDAI);
        assertEq(inCTokenMarket, false, "Should not be 'IN' the market yet");

        // enter market
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cDAI);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);
        inCTokenMarket = _checkInMarket(cDAI);
        assertEq(inCTokenMarket, true, "Should be 'IN' the market yet");
    }

    function testTotalAssets(uint256 assets) external {
        // TODO focused test on totalAssets as cellar takes on lending, collateral provision, borrows, repayments, full withdrawals
    }

    function testExitMarket(uint256 assets) external {
        // TODO below checks AFTER entering the market
        // TODO check that totalAssets reports properly
        // TODO check that balanceOf reports properly
        // TODO check that withdrawableFrom reports properly
        // TODO check that user deposits add to collateral position
        // TODO check that user withdraws work when no debt-position is open
        // TODO check that strategist function to enterMarket reverts if you're already in the market
        // TODO check that you can exit the market, then enter again
    }

    function testTakingOutLoans(uint256 assets) external {
        // TODO Simply carry out borrows
        // TODO assert that amount borrowed equates to how much compound has on record, and is in agreement with how much cellar wanted
    }

    function testTakingOutLoanInUntrackedPositionV2(uint256 assets) external {
        // TODO simply test taking out loans in untracked position
    }

    function testRepayingLoans(uint256 assets) external {
        // TODO simply test repaying and that balances make sense
        // TODO repay some
        // TODO repay all
    }

    function testMultipleCompoundV2Positions() external {
        // TODO check that adaptor can handle multiple positions for a cellar
        // TODO
    }

    function testRemoveCollateral(uint256 assets) external {
        // TODO test redeeming without calling `exitMarket`
        // TODO test redeeming with calling `exitMarket` first to make sure it all works still either way
    }

    function testRemoveSomeCollateral(uint256 assets) external {
        // TODO test partial removal
        // TODO test redeeming without calling `exitMarket`
        // TODO test redeeming with calling `exitMarket` first to make sure it all works still either way
    }

    function testRemoveAllCollateralWithTypeUINT256Max(uint256 assets) external {
        // TODO test type(uint256).max removal
        // TODO test redeeming without calling `exitMarket`
        // TODO test redeeming with calling `exitMarket` first to make sure it all works still either way
    }

    function testRemoveCollateralWithTypeUINT256MaxAfterRepay(uint256 assets) external {
        // TODO test type(uint256).max removal after repays on an open borrow position
        // TODO test redeeming without calling `exitMarket`
        // TODO test redeeming with calling `exitMarket` first to make sure it all works still either way
    }

    function testFailRemoveCollateralBecauseLTV(uint256 assets) external {
        // TODO test that it reverts if trying to redeem too much
        // TODO test that it reverts if trying to call exitMarket w/ too much borrow position out that one cannot pull the collateral.
    }

    // TODO - supply collateral in one asset, and then borrow another. So for these tests, supply DAI, borrow USDC.
    function testHF() external {
        uint256 initialAssets = cellar.totalAssets();
        // assets = bound(assets, 0.1e18, 1_000_000e18);
        uint256 assets = 100e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position is cDAI (w/o entering market)

        // enter market
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cDAI);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // now we're in the market, so start borrowing.
        uint256 borrow1 = assets / 2;
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cDAI, borrow1);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // TODO - EIN THIS IS WHERE YOU LEFT OFF, CURRENTLY IT IS HAVING UNDERFLOW/OVERFLOW ERRORS IN THE HEALTHFACTOR LOGIC HELPER CONTRACT

        // TODO check decimals to refine the HF calculations
        // check consoles, ultimately we just want to see HF is calculated properly, actually just console log inside of the CompoundV2HelperLogic.sol file. see what comes up.

        // TODO test borrowing more when it would lower HF
        // TODO test redeeming when it would lower HF
        // TODO increase the collateral position so the HF is higher and then perform the borrow
        // TODO decrease the borrow and then do the redeem successfully
    }

    // TODO - supply collateral in one asset, and then borrow another. So for these tests, supply USDC, borrow DAI. DOING THIS INSTEAD OF HF TEST ABOVE BECAUSE SHOULD BE BORROWING A DIFFERENT ASSET BUT CELLAR ERRORS OUT WHEN TRYING TO ADD IN CUSDC
    function testHF2() external {
        uint256 initialAssets = cellar.totalAssets();
        // assets = bound(assets, 0.1e18, 1_000_000e18);
        uint256 assets = 100e6;
        deal(address(USDC), address(cellar), assets); // deal USDC to cellar
        uint256 usdcBalance1 = USDC.balanceOf(address(cellar));

        // mint cUSDC / lend USDC via strategist call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cUSDC, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 cUSDCBalance1 = cUSDC.balanceOf(address(cellar));
        uint256 daiBalance1 = DAI.balanceOf(address(cellar));

        // enter market
        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cUSDC);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // now we're in the market, so start borrowing from a different market, cDAI
        uint256 borrow1 = (assets / 2).changeDecimals(6, 18); // should be 50e18 DAI --> do we need to put in the proper decimals?
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cDAI, borrow1);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 cUSDCBalance2 = cUSDC.balanceOf(address(cellar));
        uint256 usdcBalance2 = USDC.balanceOf(address(cellar));
        uint256 daiBalance2 = DAI.balanceOf(address(cellar));

        assertGt(daiBalance2, daiBalance1, "Cellar should have borrowed some DAI.");
        assertApproxEqRel(borrow1, daiBalance2, 10, "Cellar should have gotten the correct amount of borrowed DAI");

        console.log("cUSDCBalance1: %s, usdcBalance1: %s, daiBalance1: %s", cUSDCBalance1, usdcBalance1, daiBalance1);
        console.log("cUSDCBalance2: %s, usdcBalance2: %s, daiBalance2: %s", cUSDCBalance2, usdcBalance2, daiBalance2);

        revert();

        // TODO - EIN THIS IS WHERE YOU LEFT OFF, CURRENTLY IT IS HAVING UNDERFLOW/OVERFLOW ERRORS IN THE HEALTHFACTOR LOGIC HELPER CONTRACT

        // TODO check decimals to refine the HF calculations
        // check consoles, ultimately we just want to see HF is calculated properly, actually just console log inside of the CompoundV2HelperLogic.sol file. see what comes up.

        // TODO test borrowing more when it would lower HF
        // TODO test redeeming when it would lower HF
        // TODO increase the collateral position so the HF is higher and then perform the borrow
        // TODO decrease the borrow and then do the redeem successfully
    }

    // Crispy's test that has the decimals that he thinks we should use.
    //     The only thing with this calculation is that the first part is in terms of the underlying asset decimals, which for DAI is 18 decimals, but USDC, USDT use 6 decimals, so you could lose a lot of precision there. Something we would need to look at.
    // To increase precision, the line where we declare actualCollateralBacking we could do 1 of 2 things
    // 1) Divide by the asset decimals instead of 1e18, so we use 18 decimals by default(which later on we would need to adjust for)
    // 2) Or we could multiply by some scalar to make sure we have more precision(which later on we would need to adjust for again)

    // Both of these methods use more logic and read more state, so if we can get away with using the method I outlined in the screen shot that would be best, even if it resulted in HFs being 0.1% off from the compound 1. If we set our minimum health factor in the adaptor to 1.03, then worse case scenario is the adaptor thinks the cellars health factor is 1.03, but in reality it is 1.02897.

    // I mean hell even if it was 1% the worst case scenario for the health factor would bbe 1.0197, which is still comfortably above 1

    // function testCrispyDeposit(uint256 assets) external {
    //     uint256 initialAssets = cellar.totalAssets();
    //     assets = bound(assets, 0.1e18, 1_000_000e18);
    //     deal(address(DAI), address(this), assets); //18
    //     cellar.deposit(assets, address(this));
    //     assertApproxEqRel(
    //         cDAI.balanceOf(address(cellar)).mulDivDown(cDAI.exchangeRateStored(), 1e18),
    //         assets + initialAssets,
    //         0.001e18,
    //         "Assets should have been deposited into Compound."
    //     );

    //     // Calculate collateral value for HF equation.
    //     cDAI.accrueInterest(); // Update ExchangeRate stored.
    //     uint256 cTokenBalance = cDAI.balanceOf(address(cellar));
    //     uint256 currentExchangeRate = cDAI.exchangeRateStored();
    //     Oracle compoundOracle = Oracle(comptroller.oracle());
    //     uint256 underlyingPriceInUsd = compoundOracle.getUnderlyingPrice(address(cDAI));
    //     (, uint256 collateralFactor, ) = comptroller.markets(address(cDAI));

    //     uint256 actualCollateralBacking = cTokenBalance.mulDivDown(currentExchangeRate, 1e18); // Now in terms of underlying asset decimals.
    //     actualCollateralBacking = actualCollateralBacking.mulDivDown(underlyingPriceInUsd, 1e18); // Now in terms of 18 decimals.
    //     /// NOTE to perform calc for a debt balance, call `cDAI.borrowBalanceStored` and use that value instead of `cDAI.balanceOf`, then stop here and do not muldiv the collateral factor
    //     actualCollateralBacking = actualCollateralBacking.mulDivDown(collateralFactor, 1e18); // Still in terms of 18 decimals.

    //     uint256 assetsInvested = assets + initialDeposit;
    //     uint256 expectedCollateralBacking = assetsInvested.mulDivDown(priceRouter.getPriceInUSD(DAI), 1e8); // Now in terms of underlying decimals.
    //     expectedCollateralBacking = expectedCollateralBacking.mulDivDown(collateralFactor, 10 ** DAI.decimals()); // Now in terms of 18 decimals.

    //     assertApproxEqRel(
    //         actualCollateralBacking,
    //         expectedCollateralBacking,
    //         0.000001e18,
    //         "Collateral backing does not equal expected."
    //     );
    // }

    function testRepayPartialDebt(uint256 assets) external {
        // TODO test partial repayment and check that balances make sense within compound and outside of it (actual token balances)
    }

    // This check stops strategists from taking on any debt in positions they do not set up properly.
    function testLoanInUntrackedPosition(uint256 assets) external {
        // TODO purposely do not trust a fraxlendDebtUNIPosition
        // TODO then test borrowing from it
    }

    function testRepayingDebtThatIsNotOwed(uint256 assets) external {
        // TODO
    }

    // externalReceiver triggers when doing Strategist Function calls via adaptorCall.
    function testBlockExternalReceiver(uint256 assets) external {
        // TODO         vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
    }

    /// helpers

    function _checkInMarket(CErc20 _market) internal view returns (bool inCTokenMarket) {
        // check that we aren't in market
        CErc20[] memory marketsEntered = comptroller.getAssetsIn(address(cellar));
        for (uint256 i = 0; i < marketsEntered.length; i++) {
            // check if cToken is one of the markets cellar position is in.
            if (marketsEntered[i] == cDAI) {
                inCTokenMarket = true;
            }
        }
    }
}
