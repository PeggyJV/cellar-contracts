// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import "test/resources/MainnetStarter.t.sol";

import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { CometInterface } from "src/interfaces/external/Compound/CometInterface.sol";

/**
 * @notice Test provision of collateral and borrowing on CompoundV3 lending markets
 * @author 0xEinCodes, crispymangoes
 * NOTE: for WETH markets, use: cbETH, wstETH as collateral. Though, ETH is the borrow asset, so we'll test supplying that too in the other adaptor test.
 * For USDC markets, use: Ether, and WBTC as collateral.
 */
contract CellarCompoundV3CollateralAndDebtAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    CollateralFTokenAdaptor public collateralFTokenAdaptor;
    DebtFTokenAdaptor public debtFTokenAdaptor;
    Cellar public cellar;
    IFToken mkrFraxLendPair = IFToken(MKR_FRAX_PAIR);

    WstEthExtension private wstethExtension;

    // positions that cellar will hold: collateral as erc20s, then collateral positions for specific markets

    uint32 public compoundV3CollateralWstETHPosition = 1_000_001;
    uint32 public compoundV3CollateralCbETHPosition = 1_000_002;
    uint32 public compoundV3CollateralWBTCPosition = 1_000_003;
    uint32 public compoundV3CollateralETHPosition = 1_000_004;

    WstEthExtension private wstEthOracle;

    address private aWstEthWhale = 0xAF06acFD1BD492B913d5807d562e4FC3A6343C4E; // TODO: check on this. I believe we need this because we can't use foundry to `deal` WstETH

    uint32 private wstethPosition = 1;
    uint32 private cbethPosition = 2;
    uint32 private wethPosition = 3;
    uint32 private wbtcPosition = 4;
    uint32 private ethPosition = 5;

    uint256 initialAssets;
    uint256 minHealthFactor = 1.05e18;

    CometInterface cUSDCv3 = CometInterface(cUSDCv3Address);
    CometInterface cWETHv3 = CometInterface(cWETHv3Address);

    bool ACCOUNT_FOR_INTEREST = true;

    function setUp() public {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18334739;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        wstethExtension = new WstEthExtension(priceRouter);

        // Bring feeds in for USD.

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CompoundV3CollateralAdaptor).creationCode;
        constructorArgs = abi.encode(ACCOUNT_FOR_INTEREST, minHealthFactor);
        compoundV3CollateralAdaptor = CompoundV3CollateralAdaptor(
            deployer.deployContract("CompoundV3 Collateral Adaptor V 0.1", creationCode, constructorArgs, 0)
        );

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        // Add wstEth.
        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        uint256 price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);

        // cbeth
        price = uint256(IChainlinkAggregator(CBETH_ETH_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, CBETH_ETH_FEED);
        priceRouter.addAsset(CBETH, settings, abi.encode(stor), price);

        // weth
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // wbtc
        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        // eth - TODO: not sure about this setup
        price = uint256(IChainlinkAggregator(ETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, ETH_USD_FEED);
        priceRouter.addAsset(ETH, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.

        registry.trustAdaptor(address(compoundV3CollateralAdaptor));

        registry.trustPosition(wstethPosition, address(erc20Adaptor), abi.encode(WSTETH));
        registry.trustPosition(cbethPosition, address(erc20Adaptor), abi.encode(CBETH));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));
        registry.trustPosition(ethPosition, address(erc20Adaptor), abi.encode(ETH)); // TODO: not sure about this

        registry.trustPosition(
            compoundV3CollateralWstETHPosition,
            address(compoundV3CollateralAdaptor),
            abi.encode(cWETHv3, WSTETH)
        );

        registry.trustPosition(
            compoundV3CollateralCbETHPosition,
            address(compoundV3CollateralAdaptor),
            abi.encode(cWETHv3, CBETH)
        );

        registry.trustPosition(
            compoundV3CollateralWBTCPosition,
            address(compoundV3CollateralAdaptor),
            abi.encode(cUSDCv3, WBTC)
        );

        string memory cellarName = "CompoundV3 Collateral & Debt Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);

        // TODO: deal out wsteth, cbeth, weth, wbtc, and eth to address(this) and then to cellar.
        // deal(address(MKR), address(this), initialDeposit);
        // MKR.approve(cellarAddress, initialDeposit);

        // TODO: not sure about the base asset for the cellar in these tests right now
        creationCode = type(Cellar).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            WETH,
            cellarName,
            cellarName,
            wethPosition,
            abi.encode(WETH),
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(compoundV3CollateralAdaptor));

        cellar.addPositionToCatalogue(wstethPosition);
        cellar.addPositionToCatalogue(cbethPosition);
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(wbtcPosition);
        cellar.addPositionToCatalogue(ethPosition);
        cellar.addPositionToCatalogue(compoundV3CollateralWstETHPosition);
        cellar.addPositionToCatalogue(compoundV3CollateralCbETHPosition);
        cellar.addPositionToCatalogue(compoundV3CollateralWBTCPosition);

        cellar.addPosition(1, wstethPosition, abi.encode(0), false);
        cellar.addPosition(2, cbethPosition, abi.encode(0), false);
        cellar.addPosition(3, wethPosition, abi.encode(0), false);
        cellar.addPosition(4, wbtcPosition, abi.encode(0), false);
        cellar.addPosition(5, ethPosition, abi.encode(0), false);
        cellar.addPosition(6, compoundV3CollateralWstETHPosition, abi.encode(0), false);
        cellar.addPosition(7, compoundV3CollateralCbETHPosition, abi.encode(0), false);
        cellar.addPosition(8, compoundV3CollateralWBTCPosition, abi.encode(0), false);

        // TODO: add debt positions when those are ready to be tested

        // TODO: max approvals for test setup
        // WETH.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        // stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));

        // Force whale out of their WSTETH position.
        vm.prank(aWstEthWhale);
        pool.withdraw(address(WSTETH), 1_000e18, aWstEthWhale);
    }

    /// SUPPLYADAPTOR TESTS

    // TODO: If the calling cellar already has an open borrow position or collateral position, we need to revert because Strategist must use other adaptors when dealing with collateral and borrow positions. CHECK to see if it reverts on its own within Compound via testing.

    /// DEBTADAPTOR TESTS

    //============================================ TODO: BELOW TESTS ARE COPIED FROM FRAXLEND DEBT AND COLLATERAL TESTS AND WILL BE OVERWRITTEN. THEY ARE JUST PLACEHOLDERS. ===========================================

    // Tests will consist of entering and exiting CompoundV3 lending markets on mainnet. So that means: USDC and ETH lending markets. Will test sending a couple of different collaterals to each lending market to make sure that it is working as planned. We'll test to see that they have different CRs, that they are responding as we thought they would, etc.

    // test adding collateral to each market (test 2 kinds of collateral per market, and test adding baseAsset --> do we want to allow adding in baseAsset or no? I don't think we should. That should be explicitly be a supply adaptor for ERC4626 vaults)
    // test removing collateral from each market
    // priceFeeds needed for pricing the collateral asset used? Yes, because we will get balanceOf from Compound for the amount of collateral in a position.

    // // test that holding position for adding collateral is being tracked properly and works upon user deposits
    // function testDeposit(uint256 assets) external {
    //     assets = bound(assets, 0.1e18, 100_000e18);
    //     initialAssets = cellar.totalAssets();
    //     console.log("Cellar MKR balance: %s, initialAssets: %s", MKR.balanceOf(address(cellar)), initialAssets);
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this));
    //     assertApproxEqAbs(
    //         MKR.balanceOf(address(cellar)),
    //         assets + initialAssets,
    //         1,
    //         "Cellar should have all deposited MKR assets"
    //     );

    //     // carry out a proper addCollateral() call
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);
    //     assertApproxEqAbs(
    //         MKR.balanceOf(address(cellar)),
    //         initialAssets,
    //         1,
    //         "Only initialAssets should be within Cellar."
    //     );

    //     uint256 newCellarCollateralBalance = mkrFToken.userCollateralBalance(address(cellar));
    //     assertEq(
    //         newCellarCollateralBalance,
    //         assets,
    //         "`fraxlendPairCore.userCollateralBalance()` check: Assets should be collateral provided to Fraxlend Pair."
    //     );
    // }

    // // carry out a total assets test checking that balanceOf works for adaptors.
    // function testTotalAssets(uint256 assets) external {
    //     assets = bound(assets, 0.1e18, 100_000e18);
    //     initialAssets = cellar.totalAssets();
    //     console.log("Cellar MKR balance: %s, initialAssets: %s", MKR.balanceOf(address(cellar)), initialAssets);
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // addCollateral() call
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     assertApproxEqAbs(
    //         cellar.totalAssets(),
    //         (assets + initialAssets),
    //         1,
    //         "Cellar.totalAssets() && CollateralFTokenAdaptor.balanceOf() check: Total assets should not have changed."
    //     );
    // }

    // function testFailTakingOutLoansWithNoCollateral() external {}

    // // test taking loans w/ v2 fraxlend pairs
    // function testTakingOutLoansV2(uint256 assets) external {
    //     assets = bound(assets, 1e18, 100e18);
    //     initialAssets = cellar.totalAssets();
    //     console.log("Cellar MKR balance: %s, initialAssets: %s", MKR.balanceOf(address(cellar)), initialAssets);
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // addCollateral() call
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     // Take out a FRAX loan.
    //     uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
    //     adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);
    //     bytes memory adaptorData = abi.encode(MKR_FRAX_PAIR);

    //     vm.prank(address(cellar));
    //     uint256 newBalance = debtFTokenAdaptor.balanceOf(adaptorData);
    //     assertApproxEqAbs(
    //         newBalance,
    //         fraxToBorrow,
    //         1,
    //         "Cellar should have debt recorded within Fraxlend Pair of assets / 2"
    //     );
    //     assertApproxEqAbs(
    //         FRAX.balanceOf(address(cellar)),
    //         fraxToBorrow,
    //         1,
    //         "Cellar should have FRAX equal to assets / 2"
    //     );
    // }

    // // test taking loan w/ providing collateral to the wrong pair
    // function testTakingOutLoanInUntrackedPositionV2() external {
    //     // assets = bound(assets, 0.1e18, 100_000e18);
    //     uint256 assets = 1e18;
    //     initialAssets = cellar.totalAssets();
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(APE_FRAX_PAIR, assets / 2);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 DebtFTokenAdaptor.DebtFTokenAdaptor__FraxlendPairPositionsMustBeTracked.selector,
    //                 APE_FRAX_PAIR
    //             )
    //         )
    //     );
    //     cellar.callOnAdaptor(data);
    // }

    // function testRepayingLoans() external {
    //     // assets = bound(assets, 0.1e18, 100_000e18);
    //     uint256 assets = 1e18;
    //     initialAssets = cellar.totalAssets();
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // addCollateral() call
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     // Take out a FRAX loan.
    //     uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
    //     adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     // start repayment sequence
    //     mkrFraxLendPair.addInterest(false);
    //     uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
    //     deal(address(FRAX), address(cellar), fraxToBorrow * 2);

    //     // Repay the loan.
    //     adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(mkrFToken, maxAmountToRepay);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     assertApproxEqAbs(
    //         getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar)),
    //         0,
    //         1,
    //         "Cellar should have zero debt recorded within Fraxlend Pair"
    //     );
    //     assertLt(FRAX.balanceOf(address(cellar)), fraxToBorrow * 2, "Cellar should have zero debtAsset");
    // }

    // // okay just seeing if we can handle multiple fraxlend positions
    // // TODO: EIN - Reformat adaptorCall var names and troubleshoot why uniFraxToBorrow has to be 1e18 right now
    // function testMultipleFraxlendPositions() external {
    //     uint256 assets = 1e18;

    //     // Add new assets related to new fraxlendMarket; UNI_FRAX
    //     uint32 fraxlendCollateralUNIPosition = 1_000_007; // fralendV2
    //     uint32 fraxlendDebtUNIPosition = 1_000_008; // fralendV2
    //     registry.trustPosition(
    //         fraxlendCollateralUNIPosition,
    //         address(collateralFTokenAdaptor),
    //         abi.encode(UNI_FRAX_PAIR)
    //     );
    //     registry.trustPosition(fraxlendDebtUNIPosition, address(debtFTokenAdaptor), abi.encode(UNI_FRAX_PAIR));
    //     cellar.addPositionToCatalogue(uniPosition);
    //     cellar.addPositionToCatalogue(fraxlendCollateralUNIPosition);
    //     cellar.addPositionToCatalogue(fraxlendDebtUNIPosition);
    //     cellar.addPosition(5, fraxlendCollateralUNIPosition, abi.encode(0), false);
    //     cellar.addPosition(6, uniPosition, abi.encode(0), false);
    //     cellar.addPosition(1, fraxlendDebtUNIPosition, abi.encode(0), true);

    //     // multiple adaptor calls
    //     // deposit MKR
    //     // borrow FRAX
    //     // deposit UNI
    //     // borrow FRAX
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair
    //     deal(address(UNI), address(cellar), assets);
    //     uint256 mkrFraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
    //     // uint256 uniFraxToBorrow = priceRouter.getValue(UNI, assets / 2, FRAX);
    //     // console.log("uniFraxToBorrow: %s && assets/2: %s", uniFraxToBorrow, assets / 2);
    //     uint256 uniFraxToBorrow = 1e18;

    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
    //     bytes[] memory adaptorCallsFirstAdaptor = new bytes[](2); // collateralAdaptor, MKR already deposited due to cellar holding position
    //     bytes[] memory adaptorCallsSecondAdaptor = new bytes[](2); // debtAdaptor
    //     adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
    //     adaptorCallsFirstAdaptor[1] = _createBytesDataToAddCollateralWithFraxlendV2(UNI_FRAX_PAIR, assets);
    //     adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, mkrFraxToBorrow);
    //     adaptorCallsSecondAdaptor[1] = _createBytesDataToBorrowWithFraxlendV2(UNI_FRAX_PAIR, uniFraxToBorrow);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCallsFirstAdaptor });
    //     data[1] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCallsSecondAdaptor });
    //     cellar.callOnAdaptor(data);

    //     // Check that we have the right amount of FRAX borrowed
    //     assertApproxEqAbs(
    //         (getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar))) +
    //             getFraxlendDebtBalance(UNI_FRAX_PAIR, address(cellar)),
    //         mkrFraxToBorrow + uniFraxToBorrow,
    //         1
    //     );

    //     assertApproxEqAbs(FRAX.balanceOf(address(cellar)), mkrFraxToBorrow + uniFraxToBorrow, 1);

    //     mkrFraxLendPair.addInterest(false);
    //     uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
    //     deal(address(FRAX), address(cellar), (mkrFraxToBorrow + uniFraxToBorrow) * 2);

    //     // Repay the loan in one of the fraxlend pairs
    //     Cellar.AdaptorCall[] memory newData2 = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls2 = new bytes[](1);
    //     adaptorCalls2[0] = _createBytesDataToRepayWithFraxlendV2(mkrFToken, maxAmountToRepay);
    //     newData2[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls2 });
    //     cellar.callOnAdaptor(newData2);

    //     assertApproxEqAbs(
    //         getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar)),
    //         0,
    //         1,
    //         "Cellar should have zero debt recorded within Fraxlend Pair"
    //     );

    //     assertApproxEqAbs(
    //         getFraxlendDebtBalance(UNI_FRAX_PAIR, address(cellar)),
    //         uniFraxToBorrow,
    //         1,
    //         "Cellar should still have debt for UNI Fraxlend Pair"
    //     );

    //     deal(address(MKR), address(cellar), 0);

    //     adaptorCalls2[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(assets, mkrFToken);
    //     newData2[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls2 });
    //     cellar.callOnAdaptor(newData2);

    //     // Check that we no longer have any MKR in the collateralPosition
    //     assertEq(MKR.balanceOf(address(cellar)), assets);

    //     // have user withdraw from cellar
    //     cellar.withdraw(assets, address(this), address(this));
    //     assertEq(MKR.balanceOf(address(this)), assets);
    // }

    // function testRemoveCollateral(uint256 assets) external {
    //     assets = bound(assets, 0.1e18, 100_000e18);
    //     initialAssets = cellar.totalAssets();
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // carry out a proper addCollateral() call
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     assertEq(MKR.balanceOf(address(cellar)), initialAssets);

    //     // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
    //     adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(assets, mkrFToken);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     assertEq(MKR.balanceOf(address(cellar)), assets + initialAssets);
    //     assertEq(mkrFToken.userCollateralBalance(address(cellar)), 0);
    // }

    // function testRemoveSomeCollateral(uint256 assets) external {
    //     assets = bound(assets, 0.1e18, 100_000e18);
    //     initialAssets = cellar.totalAssets();
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // carry out a proper addCollateral() call
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     assertEq(MKR.balanceOf(address(cellar)), initialAssets);

    //     adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(assets / 2, mkrFToken);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     assertEq(MKR.balanceOf(address(cellar)), (assets / 2) + initialAssets);
    //     assertApproxEqAbs(mkrFToken.userCollateralBalance(address(cellar)), assets / 2, 1);
    // }

    // // test attempting to removeCollateral() when the LTV would be too high as a result
    // function testFailRemoveCollateralBecauseLTV(uint256 assets) external {
    //     assets = bound(assets, 0.1e18, 100_000e18);
    //     initialAssets = cellar.totalAssets();
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // carry out a proper addCollateral() call
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     assertEq(MKR.balanceOf(address(cellar)), 0);

    //     // Take out a FRAX loan.
    //     uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
    //     adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     mkrFraxLendPair.addInterest(false);
    //     // try to removeCollateral but more than should be allowed
    //     adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(assets, mkrFToken);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });

    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 CollateralFTokenAdaptor.CollateralFTokenAdaptor__HealthFactorTooLow.selector,
    //                 MKR_FRAX_PAIR
    //             )
    //         )
    //     );
    //     cellar.callOnAdaptor(data);
    // }

    // function testLTV() external {
    //     // assets = bound(assets, 0.1e18, 100_000e18);
    //     uint256 assets = 1e18;
    //     initialAssets = cellar.totalAssets();
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // carry out a proper addCollateral() call
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);
    //     uint256 newCellarCollateralBalance = mkrFToken.userCollateralBalance(address(cellar));

    //     assertEq(MKR.balanceOf(address(cellar)), initialAssets);

    //     // Take out a FRAX loan.
    //     uint256 fraxToBorrow = priceRouter.getValue(MKR, assets.mulDivDown(1e4, 1.35e4), FRAX);
    //     adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });

    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(DebtFTokenAdaptor.DebtFTokenAdaptor__HealthFactorTooLow.selector, MKR_FRAX_PAIR)
    //         )
    //     );
    //     cellar.callOnAdaptor(data);

    //     // add collateral to be able to borrow amount desired
    //     deal(address(MKR), address(cellar), 3 * assets);
    //     adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     assertEq(MKR.balanceOf(address(cellar)), assets * 2);

    //     newCellarCollateralBalance = mkrFToken.userCollateralBalance(address(cellar));
    //     assertEq(newCellarCollateralBalance, 2 * assets);

    //     // Try taking out more FRAX now
    //     uint256 moreFraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
    //     adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, moreFraxToBorrow);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data); // should transact now
    // }

    // // TODO: CRISPY - please take a look at the fuzzing, was having issues with this.
    // function testRepayPartialDebt() external {
    //     // assets = bound(assets, 0.1e18, 100_000e18);
    //     uint256 assets = 1e18;
    //     initialAssets = cellar.totalAssets();
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     // carry out a proper addCollateral() call
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     // Take out a FRAX loan.
    //     uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
    //     adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);

    //     // start repayment sequence
    //     mkrFraxLendPair.addInterest(false);

    //     uint256 debtBefore = getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar));
    //     // Repay the loan.
    //     adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(mkrFToken, fraxToBorrow / 2);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
    //     cellar.callOnAdaptor(data);
    //     uint256 debtNow = getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar));
    //     assertLt(debtNow, debtBefore);
    //     assertApproxEqAbs(
    //         FRAX.balanceOf(address(cellar)),
    //         fraxToBorrow / 2,
    //         1e18,
    //         "Cellar should have approximately half debtAsset"
    //     );
    // }

    // // This check stops strategists from taking on any debt in positions they do not set up properly.
    // function testLoanInUntrackedPosition() external {
    //     uint32 fraxlendCollateralUNIPosition = 1_000_007; // fralendV2
    //     registry.trustPosition(
    //         fraxlendCollateralUNIPosition,
    //         address(collateralFTokenAdaptor),
    //         abi.encode(UNI_FRAX_PAIR)
    //     );
    //     // purposely do not trust a fraxlendDebtUNIPosition
    //     cellar.addPositionToCatalogue(fraxlendCollateralUNIPosition);
    //     cellar.addPosition(5, fraxlendCollateralUNIPosition, abi.encode(0), false);
    //     uint256 assets = 100_000e18;
    //     uint256 uniFraxToBorrow = priceRouter.getValue(UNI, assets / 2, FRAX);

    //     deal(address(UNI), address(cellar), assets);
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
    //     bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1); // collateralAdaptor
    //     bytes[] memory adaptorCallsSecondAdaptor = new bytes[](1); // debtAdaptor
    //     adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralWithFraxlendV2(UNI_FRAX_PAIR, assets);
    //     adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowWithFraxlendV2(UNI_FRAX_PAIR, uniFraxToBorrow);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCallsFirstAdaptor });
    //     data[1] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCallsSecondAdaptor });
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 DebtFTokenAdaptor.DebtFTokenAdaptor__FraxlendPairPositionsMustBeTracked.selector,
    //                 address(UNI_FRAX_PAIR)
    //             )
    //         )
    //     );
    //     cellar.callOnAdaptor(data);
    // }

    // // have strategist call repay function when no debt owed. Expect revert.
    // function testRepayingDebtThatIsNotOwed() external {
    //     uint256 assets = 100_000e18;
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this));
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);

    //     adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(mkrFraxLendPair, assets / 2);
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(DebtFTokenAdaptor.DebtFTokenAdaptor__CannotRepayNoDebt.selector, MKR_FRAX_PAIR)
    //         )
    //     );
    //     cellar.callOnAdaptor(data);
    // }

    // // externalReceiver triggers when doing Strategist Function calls via adaptorCall.
    // function testBlockExternalReceiver() external {
    //     uint256 assets = 100_000e18;
    //     deal(address(MKR), address(this), assets);
    //     cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair
    //     // Strategist tries to withdraw USDC to their own wallet using Adaptor's `withdraw` function.
    //     address maliciousStrategist = vm.addr(10);
    //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //     bytes[] memory adaptorCalls = new bytes[](1);
    //     adaptorCalls[0] = abi.encodeWithSelector(
    //         CollateralFTokenAdaptor.withdraw.selector,
    //         100_000e18,
    //         maliciousStrategist,
    //         abi.encode(MKR_FRAX_PAIR, MKR),
    //         abi.encode(0)
    //     );
    //     data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
    //     vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
    //     cellar.callOnAdaptor(data);
    // }

    // /// Fraxlend Collateral and Debt Specific Helpers

    // function getFraxlendDebtBalance(address _fraxlendPair, address _user) internal view returns (uint256) {
    //     IFToken fraxlendPair = IFToken(_fraxlendPair);
    //     return _toBorrowAmount(fraxlendPair, fraxlendPair.userBorrowShares(_user), false, ACCOUNT_FOR_INTEREST);
    // }

    // function _toBorrowAmount(
    //     IFToken _fraxlendPair,
    //     uint256 _shares,
    //     bool _roundUp,
    //     bool _previewInterest
    // ) internal view virtual returns (uint256) {
    //     return _fraxlendPair.toBorrowAmount(_shares, _roundUp, _previewInterest);
    // }
}
