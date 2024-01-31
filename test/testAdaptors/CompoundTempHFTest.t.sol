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
 * @dev Tests are purposely kept very single-scope in order to do better gas comparisons with gas-snapshots for typical functionalities.
 * TODO - Use this temporary test file to troubleshoot decimals and health factor tests until we resolve the CUSDC position error in `Compound.t.sol`. Once that is resolved we can copy over the tests from here if they are done.
 * TODO - troubleshoot decimals and health factor calcs
 * TODO - finish off happy path and reversion tests once health factor is figured out
 * TODO - test cTokens that are using native tokens (ETH, etc.)
 * 
 * TODO - EIN - OG compoundV2 tests already account for totalAssets, deposit, withdraw, so we'll have to test for each new functionality: enterMarket, exitMarket, borrowFromCompoundV2, repayCompoundV2Debt.

 */
contract CompoundTempHFTest is MainnetStarterTest, AdaptorHelperFunctions {
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
    uint32 private cUSDCPosition = 2;
    uint32 private usdcPosition = 3;
    uint32 private cDAIPosition = 4;
    uint32 private daiVestingPosition = 5;
    uint32 private cDAIDebtPosition = 6;
    uint32 private cUSDCDebtPosition = 7;
    // TODO: add positions for ETH CTokens

    // Collateral Positions are just regular CTokenAdaptor positions but after `enterMarket()` has been called.
    // Debt Positions --> these need to be setup properly. Start with a debt position on a market that is easy.

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
        registry.trustPosition(cUSDCDebtPosition, address(compoundV2DebtAdaptor), abi.encode(cUSDC));

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
        cellar.addPositionToCatalogue(cUSDCDebtPosition);

        cellar.addPosition(1, daiPosition, abi.encode(0), false);
        cellar.addPosition(2, usdcPosition, abi.encode(0), false);
        cellar.addPosition(3, cUSDCPosition, abi.encode(0), false);
        cellar.addPosition(4, daiVestingPosition, abi.encode(0), false);
        cellar.addPosition(0, cDAIDebtPosition, abi.encode(0), true);
        cellar.addPosition(1, cUSDCDebtPosition, abi.encode(0), true);

        DAI.safeApprove(address(cellar), type(uint256).max);
    }

    // Supply && EnterMarket
    function testEnterMarket(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e18, 1_000_000e18);
        // uint256 assets = 100e6;
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
        bool inCTokenMarket = _checkInMarket(cDAI);
        assertEq(inCTokenMarket, true, "Should be 'IN' the market");
    }

    // Supply && EnterMarket
    function testDefaultCheckInMarket(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e18, 1_000_000e18);
        // uint256 assets = 100e6;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position is cDAI (w/o entering market)

        // check that we aren't in market
        bool inCTokenMarket = _checkInMarket(cDAI);
        assertEq(inCTokenMarket, false, "Should not be 'IN' the market yet");
    }

    // Same as testTotalAssets in OG CompoundV2 tests but the supplied position is marked as `entered` in the market --> so it checks totalAssets with a position that has: lending, marking that as entered in the market, withdrawing, swaps, and lending more.
    // TODO - reverts w/ STF on uniswap v3 swap. I switched the blockNumber to match that of the `Compound.t.sol` file but it still fails.
    function testTotalAssetsWithJustEnterMarket() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 1_000e18;
        deal(address(DAI), address(this), assets);
        // deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqRel(
            cellar.totalAssets(),
            assets + initialAssets,
            0.0002e18,
            "Total assets should equal assets deposited."
        );

        // Swap from USDC to DAI and lend DAI on Compound.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](5);

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cDAI);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, assets / 2);
            data[1] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwapWithUniv3(DAI, USDC, 100, assets / 2);
            data[2] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cUSDC, type(uint256).max);
            data[3] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cUSDC);
            data[4] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
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

    // checks that it reverts if the position is marked as `entered` - aka is collateral
    // NOTE - without the `_checkMarketsEntered` withdrawals are possible with CompoundV2 markets even if the the position is marked as `entered` in the market.
    // TODO - if we design it this way, doublecheck that entering market, as long as position is not in an open borrow, can be withdrawn without having to toggle `exitMarket`
    function testWithdrawEnteredMarketPosition(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        // enter market
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cDAI);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        deal(address(DAI), address(this), 0);
        uint256 amountToWithdraw = cellar.maxWithdraw(address(this));
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__AlreadyInMarket.selector, address(cDAI)))
        );
        cellar.withdraw(amountToWithdraw, address(this), address(this));
    }

    // withdrawFromCompound tests but with and without exiting the market.
    // test redeeming without calling `exitMarket`
    // test redeeming with calling `exitMarket` first to make sure it all works still either way
    // TODO - Question: should we allow withdraws from supply positions from strategists when "in market"? I think we should but we should double check the HF when doing so is all. THIS IS ASSUMING THAT COMPOUND ALLOWS SUPPLIED ASSETS TO BE WITHDRAWN EVEN IF THEY ARE SUPPORTING A BORROW POSITION
    function testWithdrawFromCompound(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position is cDAI (w/o entering market)

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // enter market
        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cUSDC);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // test withdrawing without calling `exitMarket` - should work
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // test withdrawing with calling `exitMarket` first to make sure it all works still either way
        // exit market
        {
            adaptorCalls[0] = _createBytesDataToExitMarketWithCompoundV2(cUSDC);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // withdraw from compoundV2
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);
    }

    // TODO - Go through this if compound answers that we can't withdraw if we have "entered" the market.
    function testWithdrawFromCompoundWithTypeUINT256Max(uint256 assets) external {
        // TODO test type(uint256).max withdraw
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position is cDAI (w/o entering market)

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // enter market
        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cDAI);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // test withdrawing without calling `exitMarket` - should work
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);
        assertEq(DAI.balanceOf(address(cellar)), assets, "Check 1: All assets should have been withdrawn.");

        // deposit again
        cellar.deposit(assets, address(this)); // holding position is cDAI (w/o entering market)
        // test withdrawing with calling `exitMarket` first to make sure it all works still either way
        // exit market
        {
            adaptorCalls[0] = _createBytesDataToExitMarketWithCompoundV2(cDAI);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // withdraw from compoundV2
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertEq(DAI.balanceOf(address(cellar)), assets, "Check 2: All assets should have been withdrawn.");
    }

    // TODO - test to check the following: I believe it won't allow withdrawals if below a certain LTV, but we prevent that anyways with our own HF calculations.

    // check that exit market exits position from compoundV2 market collateral position
    function testExitMarket(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e18, 1_000_000e18);
        // uint256 assets = 100e6;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position is cDAI (w/o entering market)

        // enter market
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cDAI);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        {
            adaptorCalls[0] = _createBytesDataToExitMarketWithCompoundV2(cDAI);
            data[1] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);
        bool inCTokenMarket = _checkInMarket(cDAI);
        assertEq(inCTokenMarket, false, "Should be 'NOT IN' the market");
    }

    // TODO - refactor because it uses repeititve code used elsewhere in tests (see testTotalAssetsWithJustEnterMarket)
    function testTotalAssetsAfterExitMarket() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 1_000e18;
        deal(address(DAI), address(this), assets);
        // deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqRel(
            cellar.totalAssets(),
            assets + initialAssets,
            0.0002e18,
            "Total assets should equal assets deposited."
        );

        // Swap from USDC to DAI and lend DAI on Compound.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](6);
        bytes[] memory adaptorCalls = new bytes[](1);

        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cDAI);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, assets / 2);
            data[1] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        {
            adaptorCalls[0] = _createBytesDataForSwapWithUniv3(DAI, USDC, 100, assets / 2);
            data[2] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        {
            adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cUSDC, type(uint256).max);
            data[3] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cUSDC);
            data[4] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        {
            adaptorCalls[0] = _createBytesDataToExitMarketWithCompoundV2(cDAI);
            data[5] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
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

    // See TODO  below that is in code below
    function testErrorCodesFromEnterAndExitMarket() external {
        // trust fake market position (as if malicious governance & multisig)
        uint32 cFakeMarketPosition = 8;
        CErc20 fakeMarket = CErc20(FakeCErc20); // TODO - figure out how to set up CErc20
        registry.trustPosition(cFakeMarketPosition, address(compoundV2DebtAdaptor), abi.encode(cUSDC));
        // add fake market position to cellar
        cellar.addPositionToCatalogue(cFakeMarketPosition);
        cellar.addPosition(5, cFakeMarketPosition, abi.encode(0), false);

        // enter market
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(fakeMarket);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }

        // try entering fake market - should revert
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__NonZeroCompoundErrorCode.selector, 9))
        );
        cellar.callOnAdaptor(data);

        // try exiting fake market - should revert
        {
            adaptorCalls[0] = _createBytesDataToExitMarketWithCompoundV2(fakeMarket);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__NonZeroCompoundErrorCode.selector, 9))
        );
        cellar.callOnAdaptor(data);
    }

    // TODO - error code tests for checkMarketsEntered --> needs finishing off and confirmation with compound's own code if they are doing their own checks and thus if we need our own in the adaptor design.
    function testAlreadyInMarket() external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
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
        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cDAI);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__AlreadyInMarket.selector, address(cDAI)))
        );
        cellar.callOnAdaptor(data);
    }

    // check that balanceOf reports properly
    function testBalanceOfCTokenCalculationMethods(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
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

        uint256 supplyBalanceDirectFromCompoundV2 = cDAI.balanceOf(address(cellar));

        vm.startPrank(address(cellar));
        bytes memory adaptorData = abi.encode(cDAI);
        uint256 balanceOfAccToCTokenAdaptor = cTokenAdaptor.balanceOf(adaptorData);
        vm.stopPrank();
        assertEq(
            balanceOfAccToCTokenAdaptor,
            supplyBalanceDirectFromCompoundV2,
            "BalanceOf should match what CompoundV2 reports."
        );
    }

    // TODO check that withdrawableFrom reports properly
    // TODO - EIN REMAINING WORK - THE COMMENTED OUT CODE BELOW IS FROM MOREPHOBLUE
    function testWithdrawableFrom() external {
        // cellar.addPositionToCatalogue(morphoBlueSupplyWETHPosition);
        // cellar.addPosition(4, morphoBlueSupplyWETHPosition, abi.encode(true), false);
        // // Strategist rebalances to withdraw USDC, and lend in a different pair.
        // Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        // // Withdraw USDC from Morpho Blue.
        // {
        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataToWithdrawFromMorphoBlue(usdcDaiMarket, type(uint256).max);
        //     data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        // }
        // {
        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataToLendOnMorphoBlue(wethUsdcMarket, type(uint256).max);
        //     data[1] = Cellar.AdaptorCall({ adaptor: address(morphoBlueSupplyAdaptor), callData: adaptorCalls });
        // }
        // cellar.callOnAdaptor(data);
        // // Make cellar deposits lend USDC into WETH Pair by default
        // cellar.setHoldingPosition(morphoBlueSupplyWETHPosition);
        // uint256 assets = 10_000e6;
        // deal(address(USDC), address(this), assets);
        // cellar.deposit(assets, address(this));
        // // Figure out how much the whale must borrow to borrow all the loanToken.
        // uint256 totalLoanTokenSupplied = uint256(morphoBlue.market(wethUsdcMarketId).totalSupplyAssets);
        // uint256 totalLoanTokenBorrowed = uint256(morphoBlue.market(wethUsdcMarketId).totalBorrowAssets);
        // uint256 assetsToBorrow = totalLoanTokenSupplied > totalLoanTokenBorrowed
        //     ? totalLoanTokenSupplied - totalLoanTokenBorrowed
        //     : 0;
        // // Supply 2x the value we are trying to borrow in weth market collateral (WETH)
        // uint256 collateralToProvide = priceRouter.getValue(USDC, 2 * assetsToBorrow, WETH);
        // deal(address(WETH), whaleBorrower, collateralToProvide);
        // vm.startPrank(whaleBorrower);
        // WETH.approve(address(morphoBlue), collateralToProvide);
        // MarketParams memory market = morphoBlue.idToMarketParams(wethUsdcMarketId);
        // morphoBlue.supplyCollateral(market, collateralToProvide, whaleBorrower, hex"");
        // // now borrow
        // morphoBlue.borrow(market, assetsToBorrow, 0, whaleBorrower, whaleBorrower);
        // vm.stopPrank();
        // uint256 assetsWithdrawable = cellar.totalAssetsWithdrawable();
        // assertEq(assetsWithdrawable, 0, "There should be no assets withdrawable.");
        // // Whale repays half of their debt.
        // uint256 sharesToRepay = (morphoBlue.position(wethUsdcMarketId, whaleBorrower).borrowShares) / 2;
        // vm.startPrank(whaleBorrower);
        // USDC.approve(address(morphoBlue), assetsToBorrow);
        // morphoBlue.repay(market, 0, sharesToRepay, whaleBorrower, hex"");
        // vm.stopPrank();
        // uint256 totalLoanTokenSupplied2 = uint256(morphoBlue.market(wethUsdcMarketId).totalSupplyAssets);
        // uint256 totalLoanTokenBorrowed2 = uint256(morphoBlue.market(wethUsdcMarketId).totalBorrowAssets);
        // uint256 liquidLoanToken2 = totalLoanTokenSupplied2 - totalLoanTokenBorrowed2;
        // assetsWithdrawable = cellar.totalAssetsWithdrawable();
        // assertEq(assetsWithdrawable, liquidLoanToken2, "Should be able to withdraw liquid loanToken.");
        // // Have user withdraw the loanToken.
        // deal(address(USDC), address(this), 0);
        // cellar.withdraw(liquidLoanToken2, address(this), address(this));
        // assertEq(USDC.balanceOf(address(this)), liquidLoanToken2, "User should have received liquid loanToken.");
    }

    //============================================ CompoundV2DebtAdaptor Tests ===========================================

    // to assess the gas costs for the simplest function involving HF, I guess we'd just do a borrow.
    function testGAS_Borrow(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
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

        // borrow from a different market, it should be fine because that is how compoundV2 works, it shares collateral amongst a bunch of different lending markets.

        deal(address(USDC), address(cellar), 0);

        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 2, USDC);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertEq(
            USDC.balanceOf(address(cellar)),
            amountToBorrow,
            "Requested amountToBorrow should be met from borrow tx."
        );
        assertEq(
            cUSDC.borrowBalanceStored(address(cellar)),
            amountToBorrow,
            "CompoundV2 market reflects total borrowed."
        );
        // TODO - Question: Does supply amount diminish as more cellar borrows more and thus truly switches more and more lent out supply as collateral? If yes, run a test checking that.
    }

    // This check stops strategists from taking on any debt in positions they do not set up properly.
    function testTakingOutLoanInUntrackedPositionV2(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e18, 1_000_000e18);
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

        // borrow
        deal(address(USDC), address(this), 0);

        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 2, USDC);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cTUSD, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CompoundV2DebtAdaptor.CompoundV2DebtAdaptor__CompoundV2PositionsMustBeTracked.selector,
                    address(cTUSD)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // simply test repaying and that balances make sense
    function testRepayingLoans(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
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

        // borrow
        deal(address(USDC), address(this), 0);

        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 2, USDC);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        {
            adaptorCalls[0] = _createBytesDataToRepayWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertEq(
            USDC.balanceOf(address(cellar)),
            0,
            "Cellar should have repaid USDC debt with all of its USDC balance."
        );
        assertEq(cUSDC.borrowBalanceStored(address(cellar)), 0, "CompoundV2 market reflects debt being repaid fully.");
    }

    //  repay some
    //  repay all
    function testMultipleRepayments(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
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

        // borrow
        deal(address(USDC), address(this), 0);

        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 2, USDC);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        {
            adaptorCalls[0] = _createBytesDataToRepayWithCompoundV2(cUSDC, amountToBorrow / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertEq(USDC.balanceOf(address(cellar)), amountToBorrow / 2, "Cellar should have repaid half of debt.");
        assertEq(
            cUSDC.borrowBalanceStored(address(cellar)),
            amountToBorrow / 2,
            "CompoundV2 market reflects debt being repaid partially."
        );

        // repay rest
        {
            adaptorCalls[0] = _createBytesDataToRepayWithCompoundV2(cUSDC, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);
        assertEq(USDC.balanceOf(address(cellar)), 0, "Cellar should have repaid all of debt.");
        assertEq(cUSDC.borrowBalanceStored(address(cellar)), 0, "CompoundV2 market reflects debt being repaid fully.");
    }

    // TODO - test multiple borrows up to the point that the HF is unhealthy.
    // TODO - test borrowing from multiple markets up to the HF being unhealthy. Then test repaying some of it, and then try the last borrow that shows that the adaptor is working with the "one-big-pot" lending market of compoundV2 design.

    function testMultipleCompoundV2Positions() external {
        // TODO check that adaptor can handle multiple positions for a cellar
        uint32 cWBTCDebtPosition = 8;

        registry.trustPosition(cWBTCDebtPosition, address(compoundV2DebtAdaptor), abi.encode(cWBTC));
        cellar.addPositionToCatalogue(cWBTCDebtPosition);
        cellar.addPosition(2, cWBTCDebtPosition, abi.encode(0), true);

        // lend to market1: cUSDC
        assets = bound(assets, 0.1e18, 1_000_000e18);
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

        // borrow from a different market, it should be fine because that is how compoundV2 works, it shares collateral amongst a bunch of different lending markets.

        deal(address(USDC), address(cellar), 0);

        // borrow from market2: cDAI
        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 4, USDC);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // borrow more from market2: cDAI
        amountToBorrow = priceRouter.getValue(DAI, assets / 4, USDC);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // borrow from market 3: cWBTC
        amountToBorrow = priceRouter.getValue(DAI, assets / 4, WBTC);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cWBTC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // at this point we've borrowed 75% of the collateral value supplied to compoundV2.
        // TODO - could check the HF.

        // try borrowing from market 3: cWBTC again and expect it to revert because it would bring us to 100% LTV
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cWBTC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }

        // TODO expect revert
        cellar.callOnAdaptor(data);

        // TODO - check totalAssets at this point.

        // deal more DAI to cellar and lend to market 2: cDAI so we have (2 * assets)
        deal(address(DAI), address(cellar), assets);
        {
            adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cDAI, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // now we should have 2 * assets in the cellars net worth. Try borrowing from market 3: cWBTC and it should work
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cWBTC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }

        // check all the balances wrt to compound
        assertEq(); // borrowed USDC should be assets / 2
        // borrowed WBTC should be amountToBorrow * 2

        // check totalAssets to make sure we still have 'assets' --> should be 2 * assets
    }

    //============================================ Collateral (CToken) and Debt Tests ===========================================

    // TODO - testHFReverts --> should revert w/: 1. trying to withdraw when that lowers HF, 2. trying to borrow more, 3. exiting market when that lowers HF
    // So this would test --> CTokenAdaptor__HealthFactorTooLow
    // and test --> <debt error>

    // test type(uint256).max removal after repays on an open borrow position
    // test withdrawing without calling `exitMarket`
    // TODO - Go through this if compound answers that we can't withdraw if we have "entered" the market.

    function testRemoveCollateralWithTypeUINT256MaxAfterRepayWithoutExitingMarket(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
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

        // borrow
        deal(address(USDC), address(this), 0);

        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 2, USDC);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        {
            adaptorCalls[0] = _createBytesDataToRepayWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // withdraw from compoundV2
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertEq(DAI.balanceOf(address(cellar)), assets, "All assets should have been withdrawn.");
    }

    //  test type(uint256).max removal after repays on an open borrow position
    //  test redeeming with calling `exitMarket` first to make sure it all works still either way
    function testRemoveCollateralWithTypeUINT256MaxAfterRepayWITHExitingMarket(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
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

        // borrow
        deal(address(USDC), address(this), 0);

        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 2, USDC);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        {
            adaptorCalls[0] = _createBytesDataToRepayWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // exit market
        {
            adaptorCalls[0] = _createBytesDataToExitMarketWithCompoundV2(cUSDC);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }

        // withdraw from compoundV2
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertEq(DAI.balanceOf(address(cellar)), assets, "All assets should have been withdrawn.");
    }

    /// TODO - EIN THIS IS WHERE YOU LEFT OFF

    // TODO test that it reverts if trying to redeem too much
    // TODO test that it reverts if trying to call exitMarket w/ too much borrow position out that one cannot pull the collateral.
    function testFailRemoveCollateralBecauseLTV(uint256 assets) external {}

    // tests the different scenarios that would revert if HFMinimum was not met, and then tests with values that would pass if HF assessments were working correctly.
    function testHF() external {
        // will have cUSDC to start from setup, taking out DAI ultimately. To figure out decimals for HF calc, I'll console log throughout the whole thing when borrowing. I need to have a stable start though.
        uint256 initialAssets = cellar.totalAssets();
        // assets = bound(assets, 0.1e18, 1_000_000e18);
        uint256 assets = 99e6;
        deal(address(USDC), address(cellar), assets); // deal USDC to cellar
        uint256 usdcBalance1 = USDC.balanceOf(address(cellar));
        uint256 cUSDCBalance0 = cUSDC.balanceOf(address(cellar));
        console.log("cUSDCBalance0: %s", cUSDCBalance0);

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
        uint256 borrow1 = 50e18; // should be 50e18 DAI --> do we need to put in the proper decimals?
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

        // Now borrow up to the Max HF, and console.log the HF.

        // Now borrow past the HF and make sure it reverts.

        // Now repay so the HF is another value that makes sense. Maybe HF = 4? So loan is 25% of the collateral.

        revert();

        // TODO check decimals to refine the HF calculations
        // check consoles, ultimately we just want to see HF is calculated properly, actually just console log inside of the CompoundV2HelperLogic.sol file. see what comes up.

        // TODO test borrowing more when it would lower HF
        // TODO test redeeming when it would lower HF
        // TODO increase the collateral position so the HF is higher and then perform the borrow
        // TODO decrease the borrow and then do the redeem successfully
    }

    // TODO - EIN - ASSESSING OPTIONS A AND OPTIONS B to further assess gas costs we can simply test that it reverts when HF is not respected.
    function testGAS_HFRevert(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
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

        // borrow
        deal(address(USDC), address(cellar), 0);

        uint256 amountToBorrow = priceRouter.getValue(DAI, assets, USDC);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CompoundV2DebtAdaptor.CompoundV2DebtAdaptor__HealthFactorTooLow.selector,
                    address(cUSDC)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // TODO - EIN - ASSESSING OPTIONS A AND OPTIONS B --> Lossyness test. If there is any lossyness, we'd be able to see if with large numbers. So do fuzz tests with HUGE bounds. From there, I guess the assert test will make sure that the actual health factor and the reported health factor do not differ by a certain amount of bps.
    // ACTUALLY we can just have helpers within this file that use the two possible implementations to calculate HFs. From there, we just compare against one another to see how far off they are from each other. If it is negligible then we are good.
    // TODO - Consider this... NOTE: arguably, it is better to test against the actual reported HF from CompoundV2 versus doing relative testing with the two methods.
    function testHFLossyness() external {}

    // TODO - is it possible for a position to have a collateral postiion and a borrow position in the same market?

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
            if (marketsEntered[i] == _market) {
                inCTokenMarket = true;
            }
        }
    }
}

contract FakeCErc20 is CErc20 {}