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
 * TODO - Use this temporary test file to troubleshoot decimals and health factor tests until we resolve the CUSDC position error in `Compound.t.sol`. Once that is resolved we can copy over the tests from here if they are done.
 * TODO - troubleshoot decimals and health factor calcs
 * TODO - finish off happy path and reversion tests once health factor is figured out
 * TODO - test cTokens that are using native tokens (ETH, etc.)
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
    uint32 private cDAIPosition = 4;
    uint32 private usdcPosition = 3;
    uint32 private cUSDCPosition = 2;
    uint32 private daiVestingPosition = 5;
    uint32 private cDAIDebtPosition = 6;
    // uint32 private cUSDCDebtPosition = 7;
    // TODO: add positions for ETH CTokens

    uint256 private minHealthFactor = 1.1e18;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18814032;
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
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, USDC, cUSDCPosition, abi.encode(0), initialDeposit, platformCut);

        cellar.setRebalanceDeviation(0.003e18);
        cellar.addAdaptorToCatalogue(address(cTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(vestingAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));
        cellar.addAdaptorToCatalogue(address(compoundV2DebtAdaptor));

        cellar.addPositionToCatalogue(daiPosition);
        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPositionToCatalogue(cDAIPosition);
        cellar.addPositionToCatalogue(daiVestingPosition);
        cellar.addPositionToCatalogue(cDAIDebtPosition);
        // cellar.addPositionToCatalogue(cUSDCDebtPosition);

        cellar.addPosition(1, daiPosition, abi.encode(0), false);
        cellar.addPosition(2, usdcPosition, abi.encode(0), false);
        cellar.addPosition(3, cDAIPosition, abi.encode(0), false);
        cellar.addPosition(4, daiVestingPosition, abi.encode(0), false);
        cellar.addPosition(5, cDAIDebtPosition, abi.encode(0), true);
        // cellar.addPosition(6, cUSDCDebtPosition, abi.encode(0), true);

        USDC.safeApprove(address(cellar), type(uint256).max);
    }

    /// Extra test for supporting providing collateral && open borrow positions

    // TODO repeat above tests but for positions that have marked their cToken positions as collateral provision

    function testEnterMarket() external {
        // TODO below checks AFTER entering the market
        // TODO check that totalAssets reports properly
        // TODO check that balanceOf reports properly
        // TODO check that withdrawableFrom reports properly
        // TODO check that user deposits add to collateral position
        // TODO check that user withdraws work when no debt-position is open
        // TODO check that strategist function to enterMarket reverts if you're already in the market
        // TODO check that you can exit the market, then enter again

        // uint256 initialAssets = cellar.totalAssets();
        // assets = bound(assets, 0.1e6, 1_000_000e6);
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position is cDAI (w/o entering market)

        // TODO - MOVE BELOW BLOB ABOUT CHECKING IN MARKET TO ENTER MARKET TEST
        // check that we aren't in market
        bool inCTokenMarket = _checkInMarket(cUSDC);
        assertEq(inCTokenMarket, false, "Should not be 'IN' the market yet");

        // enter market
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToEnterMarketWithCompoundV2(cUSDC);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);
        inCTokenMarket = _checkInMarket(cUSDC);
        assertEq(inCTokenMarket, true, "Should be 'IN' the market");
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

    // TODO - supply collateral in one asset, and then borrow another. So for these tests, supply USDC, borrow DAI.
    // TODO - add testing within this to see if lossy-ness is a big deal. We will need to use CompoundV2HelperLogicVersionA, then CompoundV2HelperLogicVersionB to compare.
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

    // TODO - is it possible for a position to have a collateral postiion and a borrow position in the same market?

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
            if (marketsEntered[i] == _market) {
                inCTokenMarket = true;
            }
        }
    }
}
