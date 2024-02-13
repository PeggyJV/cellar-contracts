// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CTokenAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { ComptrollerG7 as Comptroller, CErc20, PriceOracle } from "src/interfaces/external/ICompound.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";
// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { CompoundV2DebtAdaptor } from "src/modules/adaptors/Compound/CompoundV2DebtAdaptor.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Tests are purposely kept very single-scope in order to do better gas comparisons with gas-snapshots for typical functionalities.
 * TODO - finish off happy path and reversion tests once health factor is figured out
 * TODO - test cTokens that are using native tokens (ETH, etc.)
 * TODO - EIN - OG compoundV2 tests already account for totalAssets, deposit, withdraw w/ basic supplying and withdrawing, and claiming of comp token (see `CTokenAdaptor.sol`). So we'll have to test for each new functionality: enterMarket, exitMarket, borrowFromCompoundV2, repayCompoundV2Debt.
 */
contract CompoundV2AdditionalTests is MainnetStarterTest, AdaptorHelperFunctions {
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

    address private whaleBorrower = vm.addr(777);

    // Collateral Positions are just regular CTokenAdaptor positions but after `enterMarket()` has been called.
    // Debt Positions --> these need to be setup properly. Start with a debt position on a market that is easy.

    uint256 private minHealthFactor = 1.1e18;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19135027;
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

        bool isLiquid = true;

        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(DAI));
        registry.trustPosition(cDAIPosition, address(cTokenAdaptor), abi.encode(cDAI));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(cUSDCPosition, address(cTokenAdaptor), abi.encode(cUSDC));
        registry.trustPosition(daiVestingPosition, address(vestingAdaptor), abi.encode(vesting));

        // trust debtAdaptor positions
        registry.trustPosition(cDAIDebtPosition, address(compoundV2DebtAdaptor), abi.encode(cDAI) );
        registry.trustPosition(cUSDCDebtPosition, address(compoundV2DebtAdaptor), abi.encode(cUSDC));

        string memory cellarName = "Compound Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, DAI, cDAIPosition, abi.encode(isLiquid), initialDeposit, platformCut);

        cellar.setRebalanceDeviation(0.003e18);
        cellar.addAdaptorToCatalogue(address(erc20Adaptor));
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

    //============================================ CTokenAdaptor Extra Tests  ===========================================

    // Supply && EnterMarket
    function testEnterMarket(uint256 assets) external {
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

    // Ensure that default cTokenAdaptor supply position is not "in" the market
    function testDefaultCheckInMarket(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
        // uint256 assets = 100e6;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position is cDAI (w/o entering market)

        // check that we aren't in market
        bool inCTokenMarket = _checkInMarket(cDAI);
        assertEq(inCTokenMarket, false, "Should not be 'IN' the market yet");
    }

    // Same as testTotalAssets in OG CompoundV2 tests but the supplied position is marked as `entered` in the market --> so it checks totalAssets with a position that has: lending, marking that as entered in the market, withdrawing, swaps, and lending more.
    function testTotalAssetsWithJustEnterMarket(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e18, 1_000_000e18);

        _setupSimpleLendAndEnter(assets, initialAssets);   
        _totalAssetsCheck(assets, initialAssets);
    }

    // checks that it reverts if the position is marked as `entered` - aka is collateral
    // NOTE - without the `_checkMarketsEntered` withdrawals are possible with CompoundV2 markets even if the the position is marked as `entered` in the market, until it hits a shortfall scenario (more borrow than collateral * market collateral factor) --> see "Compound Revert Tests" at bottom of this test file.
    // TODO - resolve bug
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
        uint256 amountToWithdraw = 1;
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__AlreadyInMarket.selector, address(cDAI)))
        );
        cellar.withdraw(amountToWithdraw, address(this), address(this));
    }

    // strategist function `withdrawFromCompound` tests but with and without exiting the market. Purposely allowed withdrawals even while 'IN' market for this strategist function.
    // test withdrawing without calling `exitMarket`
    // test withdrawing with calling `exitMarket` first to make sure it all works still either way
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

        // test strategist calling withdrawing without calling `exitMarket` - should work
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

        assertApproxEqAbs(
            DAI.balanceOf(address(cellar)),
            assets,
            1e9,
            "Check 1: All assets should have been withdrawn besides initialAssets."
        );
    }

    function testWithdrawFromCompoundWithTypeUINT256Max(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();

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
        assertApproxEqAbs(
            DAI.balanceOf(address(cellar)),
            assets + initialAssets,
            1e9,
            "Check 1: All assets should have been withdrawn."
        );

        // deposit again
        deal(address(DAI), address(this), assets);
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

        assertApproxEqAbs(
            DAI.balanceOf(address(cellar)),
            (2 * assets) + initialAssets,
            1e18,
            "Check 2: All assets should have been withdrawn."
        );
    }

    // strategist tries withdrawing more than is allowed based on adaptor specified health factor.
    function testStrategistWithdrawTooLowHF(uint256 assets) external {
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
        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 2, USDC);

        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        uint256 lowerThanMinHF = 1.05e18;
        uint256 amountToWithdraw = _generateAmountBasedOnHFOptionA(
            lowerThanMinHF,
            address(cellar),
            DAI.decimals(),
            false
        ); // back calculate the amount to withdraw so: liquidateHF < HF < minHF, otherwise it will revert because of compound internal checks for shortfall scenarios --> TODO - EIN, based on console logs it seems that the amountToWithdraw calculated is not correct. 

        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, amountToWithdraw);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__HealthFactorTooLow.selector, address(cDAI)))
        );
        cellar.callOnAdaptor(data);
    }

    // check that exit market exits position from compoundV2 market collateral position
    function testExitMarket(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
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
        assertEq(inCTokenMarket, false, "Should not be 'IN' the market");
    }

        // same setup as testTotalAssetsWithJustEnterMarket, except after doing everything, do one more adaptor call.
    function testTotalAssetsAfterExitMarket(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e18, 1_000_000e18);

        _setupSimpleLendAndEnter(assets, initialAssets);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToExitMarketWithCompoundV2(cUSDC);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        _totalAssetsCheck(assets, initialAssets);
    }

    // function testErrorCodesFromEnterAndExitMarket() external {
    //     // trust fake market position (as if malicious governance & multisig)
    //     uint32 cFakeMarketPosition = 8;
    //     CErc20 fakeMarket = CErc20(FakeCErc20); // TODO NEW - figure out how to set up CErc20
    //     registry.trustPosition(cFakeMarketPosition, address(compoundV2DebtAdaptor), abi.encode(cUSDC));
    //     // add fake market position to cellar
    //     cellar.addPositionToCatalogue(cFakeMarketPosition);
    //     cellar.addPosition(5, cFakeMarketPosition, abi.encode(0), false);

    //     // enter market
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     {
    //         adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(fakeMarket);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
    //     }

    //     // try entering fake market - should revert
    //     vm.expectRevert(
    //         bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__NonZeroCompoundErrorCode.selector, 9))
    //     );
    //     cellar.callOnAdaptor(data);

    //     // try exiting fake market - should revert
    //     {
    //         adaptorCalls[0] = _createBytesDataToExitMarketWithCompoundV2(fakeMarket);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
    //     }
    //     vm.expectRevert(
    //         bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__NonZeroCompoundErrorCode.selector, 9))
    //     );
    //     cellar.callOnAdaptor(data);
    // }

    function testCellarWithdrawTooMuch(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        deal(address(DAI), address(this), 0);

        vm.expectRevert();
        cellar.withdraw(assets * 2, address(this), address(this));
    }

    // if position is already in market, reverts to save on gas for unecessary call
    function testAlreadyInMarket(uint256 assets) external {
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

    // lend assets
    // prank as whale
    // whale supplies to a different market as collateral, then borrows from this market all of the assets.
    // test address tries to do withdrawableFrom, it doesn't work
    // test address tries to do a cellar.withdraw(), it doesn't work.
    // prank as whale, have them repay half of their loan
    // test address calls withdrawableFrom
    // test address calls cellar.withdraw()
    function testWithdrawableFromAndIlliquidWithdraws(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position is cDAI (w/o entering market)
        deal(address(USDC), address(cellar), 0);

        vm.startPrank(address(whaleBorrower));
        uint256 liquidSupply = cDAI.getCash();
        uint256 amountToBorrow = assets > liquidSupply ? assets : liquidSupply;
        uint256 collateralToProvide = priceRouter.getValue(DAI, 2 * amountToBorrow, USDC);
        deal(address(USDC), whaleBorrower, collateralToProvide);
        USDC.approve(address(cUSDC), collateralToProvide);
        cUSDC.mint(collateralToProvide);

        address[] memory cToken = new address[](1);
        uint256[] memory result = new uint256[](1);
        cToken[0] = address(cUSDC);
        result = comptroller.enterMarkets(cToken); // enter the market

        if (result[0] > 0) revert();

        // now borrow
        cDAI.borrow(amountToBorrow);
        vm.stopPrank();

        uint256 assetsWithdrawable = cellar.totalAssetsWithdrawable();
        liquidSupply = cDAI.getCash();

        assertEq(assetsWithdrawable, 0, "There should be no assets withdrawable.");
        assertEq(assetsWithdrawable, liquidSupply, "There should be no assets withdrawable.");

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        // try doing a strategist withdraw, it should revert because supplied assets are illiquid
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(); // TODO - figure out what specific revert error is coming
        cellar.callOnAdaptor(data);

        // Whale repays half of their debt.
        vm.startPrank(whaleBorrower);
        DAI.approve(address(cDAI), assets);
        cDAI.repayBorrow(assets / 2);
        vm.stopPrank();

        liquidSupply = cDAI.getCash();
        assetsWithdrawable = cellar.totalAssetsWithdrawable();
        console.log("liquidSupply: %s, assetsWithdrawable: %s", liquidSupply, assetsWithdrawable);
        assertEq(assetsWithdrawable, liquidSupply, "Should be able to withdraw liquid loanToken."); 
        // Have user withdraw the loanToken.
        deal(address(DAI), address(this), 0);
        cellar.withdraw(liquidSupply, address(this), address(this));
        assertEq(DAI.balanceOf(address(this)), liquidSupply, "User should have received liquid loanToken.");
    }

    //============================================ CompoundV2DebtAdaptor Tests ===========================================

    // simple borrow using strategist functions
    function testBorrow(uint256 assets) external {
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
    }

    // simple test checking that tx will revert when strategist tries borrowing more than allowed based on adaptor specced health factor.
    function testBorrowHFRevert(uint256 assets) external {
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

        uint256 lowerThanMinHF = 1.05e18;
        uint256 amountToBorrow = _generateAmountToBorrowOptionB(lowerThanMinHF, address(cellar), USDC.decimals()); // back calculate the amount to borrow so: liquidateHF < HF < minHF, otherwise it will revert because of liquidateHF check in compound

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

    // This check stops strategists from taking on any debt in positions they do not set up properly.
    function testTakingOutLoanInUntrackedPositionV2(uint256 assets) external {
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

    function testBorrowWithNoEnteredMarketPositions(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position is cDAI (w/o entering market)

        deal(address(USDC), address(cellar), 0);

        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 2, USDC);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert();
        cellar.callOnAdaptor(data);
    }

    function testCompoundInternalRevertFromBorrowingTooMuch(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 1e18, 1_000_000e18);
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

        deal(address(USDC), address(cellar), 0);

        uint256 amountToBorrow = priceRouter.getValue(DAI, assets + initialAssets, USDC);
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CompoundV2DebtAdaptor.CompoundV2DebtAdaptor__NonZeroCompoundErrorCode.selector,
                    3
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

        assertApproxEqAbs(
            USDC.balanceOf(address(cellar)),
            amountToBorrow / 2,
            2,
            "Cellar should have repaid about half of debt."
        );

        assertApproxEqAbs(
            cUSDC.borrowBalanceStored(address(cellar)),
            amountToBorrow / 2,
            2,
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

    // CompoundV2 doesn't allow repayment over what is owed by user. This is double checking that scenario.
    function testRepayMoreThanIsOwed(uint256 assets) external {
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

        // Try repaying more than what is owed.
        deal(address(USDC), address(cellar), amountToBorrow +1);
        {
            adaptorCalls[0] = _createBytesDataToRepayWithCompoundV2(cUSDC, amountToBorrow + 1 );
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CompoundV2DebtAdaptor.CompoundV2DebtAdaptor__NonZeroCompoundErrorCode.selector, 9))
        );
        cellar.callOnAdaptor(data);

        // now make sure it can be repaid for a sanity check if we specify the right amount or less.
        {
            adaptorCalls[0] = _createBytesDataToRepayWithCompoundV2(cUSDC, amountToBorrow );
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        assertEq(cUSDC.borrowBalanceStored(address(cellar)), 0, "CompoundV2 market reflects debt being repaid fully.");
        assertEq(USDC.balanceOf(address(cellar)),1, "Debt should be paid.");
    }

    // repay for a market that cellar is not tracking as a debt position
    function testRepayingUnregisteredDebtMarket(uint256 assets) external {
        uint256 price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

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

        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 2, WBTC);

        // repay
        {
            adaptorCalls[0] = _createBytesDataToRepayWithCompoundV2(cWBTC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CompoundV2DebtAdaptor.CompoundV2DebtAdaptor__CompoundV2PositionsMustBeTracked.selector,
                    address(cWBTC)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    //============================================ Collateral (CToken) and Debt Tests ===========================================

    // exiting market when that lowers HF past adaptor specced HF
    // NOTE - not sure if this is needed because I thought Compound does a check, AND exiting completely removes the collateral position in the respective market. If anything, we ought to do a test where we have multiple compound positions, and exit one of them that has a small amount of collateral that is JUST big enough to tip the cellar health factor below the minimum.
    // TODO - make another test that does the above so it actually tests the health factor check. This one just test compound internal really.
    function testStrategistExitMarketShortFallInCompoundV2(uint256 assets) external {
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
        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 2, USDC);

        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        {
            adaptorCalls[0] = _createBytesDataToExitMarketWithCompoundV2(cDAI);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__NonZeroCompoundErrorCode.selector, 14))
        );
        cellar.callOnAdaptor(data);
    }

    // test type(uint256).max removal after repays on an open borrow position
    // test withdrawing without calling `exitMarket`
    function testWithdrawCollateralWithTypeUINT256MaxAfterRepayWithoutExitingMarket(uint256 assets) external {
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

        assertApproxEqAbs(
            DAI.balanceOf(address(cellar)),
            assets + initialAssets,
            1e9,
            "All assets should have been withdrawn."
        ); // TODO - tolerances should be lowered but will look at this later.
    }

    //  test type(uint256).max removal after repays on an open borrow position
    //  test withdrawing collateral with calling `exitMarket` first to make sure it all works still either way
    function testRemoveCollateralWithTypeUINT256MaxAfterRepayWITHExitingMarket(uint256 assets) external {
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

        assertApproxEqAbs(
            DAI.balanceOf(address(cellar)),
            assets + initialAssets,
            10e8,
            "All assets should have been withdrawn."
        ); // TODO - tolerances should be lowered but will look at this later.
    }

    // compare health factor calculation method options A and B to see how much accuracy is lost when doing the "less precise" way of option A. See `CompoundV2HelperLogic.sol` that uses option A. Option B's helper logic smart contract was deleted but its methodology can be seen in this test file in the helpers at the bottom.
    function testHFLossyness(uint256 assets) external {
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

        uint256 amountToBorrow = priceRouter.getValue(DAI, assets / 2, USDC);

        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // get HF using method A
        uint256 healthFactorOptionA = _getHFOptionA(address(cellar));
        // get HF using method B
        uint256 healthFactorOptionB = _getHFOptionB(address(cellar));

        // compare method results
        uint256 relativeDiff;
        if (healthFactorOptionA >= healthFactorOptionB) {
            relativeDiff = ((healthFactorOptionA - healthFactorOptionB) * 1e18) / healthFactorOptionA;
        } else {
            relativeDiff = ((healthFactorOptionB - healthFactorOptionA) * 1e18) / healthFactorOptionB;
        }

        assertGt(1e16, relativeDiff, "relativeDiff cannot exceed 1bps."); // ensure that relativeDiff !> 1bps (1e16)
    }

    // add collateral
    // try borrowing from same market
    // a borrow position will open up in the same market; cellar has a cToken position from lending underlying (DAI), and a borrow balance from borrowing DAI.
    // test borrowing going up to the HF, have it revert because of HF. 
    // test redeeming going up to the HF, have it revert because of HF.
    function testBorrowInSameCollateralMarket() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 1e18;
        // assets = bound(assets, 0.1e18, 1_000_000e18);
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
        uint256 initialcDaiBalance = cDAI.balanceOf(address(cellar));
        console.log("initialCDaiBalance: %s", initialcDaiBalance);

        // borrow from same market unlike other tests
        {
            adaptorCalls[0] = _createBytesDataToBorrowWithCompoundV2(cDAI, (assets/2));
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // call should go through, and it records a borrow balance in cToken market.
        assertEq(
            DAI.balanceOf(address(cellar)),
            assets / 2,
            "Borrowing from a market that cellar has lent out to already means they are just withdrawing some of their lent out initial amount."
        );
        assertEq(
            cDAI.borrowBalanceStored(address(cellar)),
            assets / 2,
            "CompoundV2 market should show borrowed, even though cellar is also supplying said underlying asset."
        );
        assertEq(
            cDAI.balanceOf(address(cellar)),
            initialcDaiBalance,
            "CompoundV2 market should show same amount cDai for cellar."
        );

        uint256 lowerThanMinHF = 1.05e18;
        uint256 amountToWithdraw = _generateAmountBasedOnHFOptionA(
            lowerThanMinHF,
            address(cellar),
            DAI.decimals(),
            false
        ); // back calculate the amount to withdraw so: liquidateHF < HF < minHF, otherwise it will revert because of compound internal checks for shortfall scenarios
        console.log("assets: %s, amountToWithdraw: %s ",assets,amountToWithdraw);
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, (amountToWithdraw) );
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }

        // vm.expectRevert(
        //     bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__HealthFactorTooLow.selector, address(cDAI)))
        // );
        cellar.callOnAdaptor(data);

        console.log("HF according to test: %s", _getHFOptionA(address(cellar)));

        // if call goes through, let's check the values
        assertEq(
            DAI.balanceOf(address(cellar)),
            assets / 2 + amountToWithdraw,
            "Stage 2: Borrowing from a market that cellar has lent out to already means they are just withdrawing some of their lent out initial amount."
        );
        assertEq(
            cDAI.borrowBalanceStored(address(cellar)),
            assets / 2,
            "Stage 2: CompoundV2 market should show borrowed, even though cellar is also supplying said underlying asset."
        );
        assertLt(
            cDAI.balanceOf(address(cellar)),
            initialcDaiBalance,
            "Stage 2: CompoundV2 market should show lower amount cDai for cellar."
        );
        revert();
    }

    function testRepayingDebtThatIsNotOwed(uint256 assets) external {
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
            adaptorCalls[0] = _createBytesDataToRepayWithCompoundV2(cUSDC, amountToBorrow + 1);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CompoundV2DebtAdaptor.CompoundV2DebtAdaptor__NonZeroCompoundErrorCode.selector,
                    13
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // externalReceiver triggers when doing Strategist Function calls via adaptorCall.
    function testBlockExternalReceiver(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist tries to withdraw USDC to their own wallet using Adaptor's `withdraw` function.
        address maliciousStrategist = vm.addr(10);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(
            CTokenAdaptor.withdraw.selector,
            assets,
            maliciousStrategist,
            abi.encode(cDAI),
            abi.encode(0)
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        cellar.callOnAdaptor(data);
    }

    //============================================ Compound Revert Tests ===========================================

    // These tests are just to check that compoundV2 reverts as it is supposed to.

    // test that it reverts if trying to redeem too much --> it should revert because of CompoundV2, no need for us to worry about it. We will throw in a test though to be sure.
    function testWithdrawMoreThanSupplied(uint256 assets) external {
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

        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, (assets + 1e18) * 10);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert();
        cellar.callOnAdaptor(data);
    }

    // TODO - error code tests

    // repay for a market that cellar does not have a borrow position in
    function testRepayingLoansWithNoBorrowPosition(uint256 assets) external {
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
            adaptorCalls[0] = _createBytesDataToRepayWithCompoundV2(cUSDC, amountToBorrow);
            data[0] = Cellar.AdaptorCall({ adaptor: address(compoundV2DebtAdaptor), callData: adaptorCalls });
        }
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CompoundV2DebtAdaptor.CompoundV2DebtAdaptor__NonZeroCompoundErrorCode.selector,
                    13
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    //============================================ Helpers ===========================================

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

    
    function _setupSimpleLendAndEnter(uint256 assets, uint256 initialAssets) internal {
        deal(address(DAI), address(this), assets);
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
    }

    function _totalAssetsCheck(uint256 assets, uint256 initialAssets) internal {
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

    // helper to produce the amountToBorrow or amountToWithdraw to get a certain health factor
    // uses precision matching option A
    function _generateAmountBasedOnHFOptionA(
        uint256 _hfRequested,
        address _account,
        uint256 _borrowDecimals,
        bool _borrow
    ) internal view returns (uint256) {
        // get the array of markets currently being used
        CErc20[] memory marketsEntered;
        marketsEntered = comptroller.getAssetsIn(address(_account));
        PriceOracle oracle = comptroller.oracle();
        uint256 sumCollateral;
        uint256 sumBorrow;
        uint256 marketsEnteredLength = marketsEntered.length;
        // Loop to calculate total collateral & total borrow for HF calcs w/ assets we're in.
        for (uint256 i = 0; i < marketsEnteredLength; i++) {
            CErc20 asset = marketsEntered[i];
            (, uint256 cTokenBalance, uint256 borrowBalance, uint256 exchangeRate) = asset.getAccountSnapshot(_account);
            uint256 oraclePrice = oracle.getUnderlyingPrice(asset);
            // get collateral factor from markets
            (, uint256 collateralFactor, ) = comptroller.markets(address(asset)); // always scaled by 18 decimals
            uint256 actualCollateralBacking = cTokenBalance.mulDivDown(exchangeRate, 1e18); // NOTE - this is the 1st key difference usage of a different scaling factor than in OptionB and CompoundV2. This means less precision but it is possibly negligible.
            actualCollateralBacking = actualCollateralBacking.mulDivDown(oraclePrice, 1e18); // NOTE - this is the 2nd key difference usage of a different scaling factor than in OptionB and CompoundV2. This means less precision but it is possibly negligible.
            actualCollateralBacking = actualCollateralBacking.mulDivDown(collateralFactor, 1e18); // scaling factor for collateral factor is always 1e18.
            uint256 additionalBorrowBalance = borrowBalance.mulDivDown(oraclePrice, 1e18); // converts cToken underlying borrow to USD
            sumCollateral = sumCollateral + actualCollateralBacking;
            sumBorrow = additionalBorrowBalance + sumBorrow;
        }

        if (_borrow) {
            uint256 borrowAmountNeeded = (sumCollateral.mulDivDown(1e18, _hfRequested) - sumBorrow) /
                (10 ** (18 - _borrowDecimals)); // recall: sumBorrow = sumCollateral / healthFactor --> because specific market collateral factors are already accounted for within calcs above
            return borrowAmountNeeded;

            // uint256 borrowAmountNeeded = (sumCollateral.mulDivDown(1e18, _hfRequested) - sumBorrow);
            // return borrowAmountNeeded;
        } else {
            uint256 withdrawAmountNeeded = (sumCollateral - (sumBorrow.mulDivDown(_hfRequested, 1e18)) / (10 ** (18 - _borrowDecimals)));
            console.log("sumCollateral: %s, sumBorrow: %s, hfRequested: %s", sumCollateral, sumBorrow, _hfRequested);

                // healthfactor = sumcollateral / sumborrow.
                // we want the amount that needs to be withdrawn from collateral to get a certain hf
                // hf * sumborrow = sumcollateral
                // sumCollateral2 = sumCollateral1 - withdrawnCollateral
                // sumCollateral1 - withdrawnCollateral = hf * sumborrow
                // hf * sumborrow - sumCollateral1 = - withdrawnCollateral
                // withdrawnCollateral = sumCollateral1 - hf*sumborrow
            return withdrawAmountNeeded;
        }
    }

    function _getHFOptionA(address _account) internal view returns (uint256 healthFactor) {
        // get the array of markets currently being used
        CErc20[] memory marketsEntered;

        marketsEntered = comptroller.getAssetsIn(address(_account));
        PriceOracle oracle = comptroller.oracle();
        uint256 sumCollateral;
        uint256 sumBorrow;
        uint256 marketsEnteredLength = marketsEntered.length;
        // Loop to calculate total collateral & total borrow for HF calcs w/ assets we're in.
        for (uint256 i = 0; i < marketsEnteredLength; i++) {
            CErc20 asset = marketsEntered[i];
            (, uint256 cTokenBalance, uint256 borrowBalance, uint256 exchangeRate) = asset.getAccountSnapshot(_account);
            uint256 oraclePrice = oracle.getUnderlyingPrice(asset);
            // get collateral factor from markets
            (, uint256 collateralFactor, ) = comptroller.markets(address(asset)); // always scaled by 18 decimals
            uint256 actualCollateralBacking = cTokenBalance.mulDivDown(exchangeRate, 1e18); // NOTE - this is the 1st key difference usage of a different scaling factor than in OptionB and CompoundV2. This means less precision but it is possibly negligible.
            actualCollateralBacking = actualCollateralBacking.mulDivDown(oraclePrice, 1e18); // NOTE - this is the 2nd key difference usage of a different scaling factor than in OptionB and CompoundV2. This means less precision but it is possibly negligible.
            actualCollateralBacking = actualCollateralBacking.mulDivDown(collateralFactor, 1e18); // scaling factor for collateral factor is always 1e18.
            // scale up actualCollateralBacking to 1e18 if it isn't already for health factor calculations.
            uint256 additionalBorrowBalance = borrowBalance.mulDivDown(oraclePrice, 1e18); // converts cToken underlying borrow to USD
            sumCollateral = sumCollateral + actualCollateralBacking;
            sumBorrow = additionalBorrowBalance + sumBorrow;
        }
        // now we can calculate health factor with sumCollateral and sumBorrow
        healthFactor = sumCollateral.mulDivDown(1e18, sumBorrow); 
    }

    function _getHFOptionB(address _account) internal view returns (uint256 healthFactor) {
        // get the array of markets currently being used
        CErc20[] memory marketsEntered;
        marketsEntered = comptroller.getAssetsIn(address(_account));
        PriceOracle oracle = comptroller.oracle();
        uint256 sumCollateral;
        uint256 sumBorrow;
        // Loop to calculate total collateral & total borrow for HF calcs w/ assets we're in.
        for (uint256 i = 0; i < marketsEntered.length; i++) {
            // Obtain values from markets
            CErc20 asset = marketsEntered[i];
            (, uint256 cTokenBalance, uint256 borrowBalance, uint256 exchangeRate) = asset.getAccountSnapshot(_account);
            uint256 oraclePrice = oracle.getUnderlyingPrice(asset);
            ERC20 underlyingAsset = ERC20(asset.underlying());
            uint256 underlyingDecimals = underlyingAsset.decimals();

            // Actual calculation of collateral and borrows for respective markets.
            // NOTE - below is scoped for stack too deep errors
            {
                (, uint256 collateralFactor, ) = comptroller.markets(address(asset)); // get collateral factor from markets
                uint256 oraclePriceScalingFactor = 10 ** (36 - underlyingDecimals);
                uint256 exchangeRateScalingFactor = 10 ** (18 - 8 + underlyingDecimals); //18 - 8 + underlyingDecimals
                uint256 actualCollateralBacking = cTokenBalance.mulDivDown(exchangeRate, exchangeRateScalingFactor);

                // convert to USD values

                actualCollateralBacking = actualCollateralBacking.mulDivDown(oraclePrice, oraclePriceScalingFactor); // converts it to USD but it is in the decimals of the underlying --> it's still in decimals of 8 (so ctoken decimals)

                // Apply collateral factor to collateral backing
                actualCollateralBacking = actualCollateralBacking.mulDivDown(collateralFactor, 1e18); // scaling factor for collateral factor is always 1e18.

                // refactor as needed for decimals
                actualCollateralBacking = _refactorCollateralBalance(actualCollateralBacking, underlyingDecimals); // scale up additionalBorrowBalance to 1e18 if it isn't already.

                // borrow balances
                // NOTE - below is scoped for stack too deep errors
                {
                    uint256 additionalBorrowBalance = borrowBalance.mulDivDown(oraclePrice, oraclePriceScalingFactor); // converts cToken underlying borrow to USD but it's in decimals of underlyingAsset

                    // refactor as needed for decimals
                    additionalBorrowBalance = _refactorBorrowBalance(additionalBorrowBalance, underlyingDecimals);

                    sumBorrow = sumBorrow + additionalBorrowBalance;
                }

                sumCollateral = sumCollateral + actualCollateralBacking;
            }
        }
        // now we can calculate health factor with sumCollateral and sumBorrow
        healthFactor = sumCollateral.mulDivDown(1e18, sumBorrow);
    }

    /**
     * @notice Option B - The ```_getHealthFactor``` function returns the current health factor
     * @dev This has the same logic as CompoundV2HelperLogicVersionB
     */
    function _generateAmountToBorrowOptionB(
        uint256 _hfRequested,
        address _account,
        uint256 _borrowDecimals
    ) internal view returns (uint256 borrowAmountNeeded) {
        // get the array of markets currently being used
        CErc20[] memory marketsEntered;
        marketsEntered = comptroller.getAssetsIn(address(_account));
        PriceOracle oracle = comptroller.oracle();
        uint256 sumCollateral;
        uint256 sumBorrow;
        // Loop to calculate total collateral & total borrow for HF calcs w/ assets we're in.
        for (uint256 i = 0; i < marketsEntered.length; i++) {
            // Obtain values from markets
            CErc20 asset = marketsEntered[i];
            (, uint256 cTokenBalance, uint256 borrowBalance, uint256 exchangeRate) = asset.getAccountSnapshot(_account);
            uint256 oraclePrice = oracle.getUnderlyingPrice(asset);
            ERC20 underlyingAsset = ERC20(asset.underlying());
            uint256 underlyingDecimals = underlyingAsset.decimals();

            // Actual calculation of collateral and borrows for respective markets.
            // NOTE - below is scoped for stack too deep errors
            {
                (, uint256 collateralFactor, ) = comptroller.markets(address(asset)); // get collateral factor from markets
                uint256 oraclePriceScalingFactor = 10 ** (36 - underlyingDecimals);
                uint256 exchangeRateScalingFactor = 10 ** (18 - 8 + underlyingDecimals); // 18 - 8 + underlyingDecimals
                uint256 actualCollateralBacking = cTokenBalance.mulDivDown(exchangeRate, exchangeRateScalingFactor); // okay, for dai, you'd end up with: 8 + 28 - 28... yeah so it just stays as 8

                // convert to USD values
                actualCollateralBacking = actualCollateralBacking.mulDivDown(oraclePrice, oraclePriceScalingFactor); // converts it to USD but it is in the decimals of the underlying --> it's still in decimals of 8 (so ctoken decimals)

                // Apply collateral factor to collateral backing
                actualCollateralBacking = actualCollateralBacking.mulDivDown(collateralFactor, 1e18); // scaling factor for collateral factor is always 1e18.

                // refactor as needed for decimals
                actualCollateralBacking = _refactorCollateralBalance(actualCollateralBacking, underlyingDecimals); // scale up additionalBorrowBalance to 1e18 if it isn't already.

                // borrow balances
                // NOTE - below is scoped for stack too deep errors
                {
                    uint256 additionalBorrowBalance = borrowBalance.mulDivDown(oraclePrice, oraclePriceScalingFactor); // converts cToken underlying borrow to USD but it's in decimals of underlyingAsset

                    // refactor as needed for decimals
                    additionalBorrowBalance = _refactorBorrowBalance(additionalBorrowBalance, underlyingDecimals);

                    sumBorrow = sumBorrow + additionalBorrowBalance;
                }

                sumCollateral = sumCollateral + actualCollateralBacking;
            }
        }

        borrowAmountNeeded =
            (sumCollateral.mulDivDown(1e18, _hfRequested) - sumBorrow) /
            (10 ** (18 - _borrowDecimals)); // recall: sumBorrow = sumCollateral / healthFactor --> because specific market collateral factors are already accounted for within calcs above
    }

    // helper that scales passed in param _balance to 18 decimals. This is needed to make it easier for health factor calculations
    function _refactorBalance(uint256 _balance, uint256 _decimals) public pure returns (uint256) {
        if (_decimals != 18) {
            _balance = _balance * (10 ** (18 - _decimals));
        }
        return _balance;
    }

    // helper that scales passed in param _balance to 18 decimals. _balance param is always passed in 8 decimals (cToken decimals). This is needed to make it easier for health factor calculations
    function _refactorCollateralBalance(uint256 _balance, uint256 _decimals) public pure returns (uint256 balance) {
        if (_decimals < 8) {
            //convert to _decimals precision first)
            balance = _balance / (10 ** (8 - _decimals));
        } else if (_decimals > 8) {
            balance = _balance * (10 ** (_decimals - 8));
        }
        if (_decimals != 18) {
            balance = balance * (10 ** (18 - _decimals)); // if _balance is 8 decimals, it'll convert balance to 18 decimals. Ah.
        }
        return balance;
    }

    function _refactorBorrowBalance(uint256 _balance, uint256 _decimals) public pure returns (uint256 balance) {
        if (_decimals != 18) {
            balance = _balance * (10 ** (18 - _decimals)); // if _balance is 8 decimals, it'll convert balance to 18 decimals. Ah.
        }
        return balance;
    }
}

// contract FakeCErc20 is CErc20 {}
