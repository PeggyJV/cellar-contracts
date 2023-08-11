// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// Import Adaptors
import { CollateralFTokenAdaptorV2 } from "src/modules/adaptors/Frax/CollateralFTokenAdaptorV2.sol";
import { DebtFTokenAdaptorV2 } from "src/modules/adaptors/Frax/DebtFTokenAdaptorV2.sol";
// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";

/**
 * @notice test provision of collateral and borrowing on Fraxlend
 * @author 0xEinCodes, crispymangoes
 * NOTE: Initial tests revolve around providing MKR as collateral and borrowing FRAX. This fraxlend pair was used because it is a Fraxlend v2 pair.
 * TODO: write v1 tests w/ WETH.
 * NOTE: repayAssetWithCollateral() is not allowed from strategist to call in FraxlendCore for cellar.
 */
contract CellarFraxLendCollateralAndDebtTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    CollateralFTokenAdaptorV2 public collateralFTokenAdaptorV2;
    DebtFTokenAdaptorV2 public debtFTokenAdaptorV2;
    Cellar public cellar;
    IFToken mkrFraxLendPair = IFToken(MKR_FRAX_PAIR);

    uint32 public fraxlendCollateralMKRPosition = 1_000_001; // fraxlendV2
    uint32 public fraxlendDebtMKRPosition = 1_000_002; // fraxlendV2
    uint32 public fraxlendCollateralAPEPosition = 1_000_003; // fralendV2
    uint32 public fraxlendDebtAPEPosition = 1_000_004; // fralendV2
    uint32 public fraxlendDebtWETHPosition = 1_000_005; // fralendV1

    // Chainlink PriceFeeds
    MockDataFeed private mockFraxUsd;
    MockDataFeed private mockWethUsd;
    MockDataFeed private mockMkrUsd;
    MockDataFeed private mockApeUsd;
    MockDataFeed private mockUniEth;

    uint32 private fraxPosition = 1;
    uint32 private mkrPosition = 2;
    uint32 private wethPosition = 3;
    uint32 private apePosition = 4;
    uint32 private uniPosition = 5;

    // Mock Positions
    uint32 private mockFxsFraxPairPosition = 6;
    uint32 private mockSfrxEthFraxPairPosition = 7;

    uint256 initialAssets;
    uint256 maxLTV = 0.5e18;

    IFToken mkrFToken = IFToken(address(MKR_FRAX_PAIR));
    bool ACCOUNT_FOR_INTEREST = true;

    function setUp() public {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17843162;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockFraxUsd = new MockDataFeed(FRAX_USD_FEED);
        mockMkrUsd = new MockDataFeed(MKR_USD_FEED);
        mockWethUsd = new MockDataFeed(WETH_USD_FEED);
        mockApeUsd = new MockDataFeed(APE_USD_FEED);
        mockUniEth = new MockDataFeed(UNI_ETH_FEED);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CollateralFTokenAdaptorV2).creationCode;
        constructorArgs = abi.encode(address(FRAX), maxLTV);
        collateralFTokenAdaptorV2 = CollateralFTokenAdaptorV2(
            deployer.deployContract("FraxLend Collateral fToken Adaptor V 0.1", creationCode, constructorArgs, 0)
        );

        creationCode = type(DebtFTokenAdaptorV2).creationCode;
        constructorArgs = abi.encode(ACCOUNT_FOR_INTEREST, address(FRAX), maxLTV);
        debtFTokenAdaptorV2 = DebtFTokenAdaptorV2(
            deployer.deployContract("FraxLend debtToken Adaptor V 1.0", creationCode, constructorArgs, 0)
        );

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(mockFraxUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockFraxUsd));
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        price = uint256(mockMkrUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockMkrUsd));
        priceRouter.addAsset(MKR, settings, abi.encode(stor), price);

        price = uint256(mockWethUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWethUsd));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(mockApeUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockApeUsd));
        priceRouter.addAsset(APE, settings, abi.encode(stor), price);

        price = uint256(mockUniEth.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUniEth));
        priceRouter.addAsset(UNI, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(collateralFTokenAdaptorV2));
        registry.trustAdaptor(address(debtFTokenAdaptorV2));

        registry.trustPosition(fraxPosition, address(erc20Adaptor), abi.encode(FRAX));
        registry.trustPosition(mkrPosition, address(erc20Adaptor), abi.encode(MKR));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(apePosition, address(erc20Adaptor), abi.encode(APE));
        registry.trustPosition(uniPosition, address(erc20Adaptor), abi.encode(UNI));

        registry.trustPosition(
            fraxlendCollateralMKRPosition,
            address(collateralFTokenAdaptorV2),
            abi.encode(MKR_FRAX_PAIR, address(MKR))
        );
        registry.trustPosition(
            fraxlendDebtMKRPosition,
            address(debtFTokenAdaptorV2),
            abi.encode(address(MKR_FRAX_PAIR))
        );
        registry.trustPosition(
            fraxlendCollateralAPEPosition,
            address(collateralFTokenAdaptorV2),
            abi.encode(APE_FRAX_PAIR, address(APE))
        );
        registry.trustPosition(
            fraxlendDebtAPEPosition,
            address(debtFTokenAdaptorV2),
            abi.encode(address(APE_FRAX_PAIR))
        );

        string memory cellarName = "Fraxlend Collateral & Debt Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(MKR), address(this), initialDeposit);
        MKR.approve(cellarAddress, initialDeposit);

        creationCode = type(Cellar).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            MKR,
            cellarName,
            cellarName,
            mkrPosition,
            abi.encode(MKR),
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(collateralFTokenAdaptorV2));
        cellar.addAdaptorToCatalogue(address(debtFTokenAdaptorV2));
        // TODO: add V1 adaptors

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(fraxlendCollateralMKRPosition);
        cellar.addPositionToCatalogue(fraxlendDebtMKRPosition);
        cellar.addPositionToCatalogue(fraxPosition);
        cellar.addPositionToCatalogue(apePosition);

        cellar.addPosition(1, wethPosition, abi.encode(0), false);
        cellar.addPosition(2, fraxlendCollateralMKRPosition, abi.encode(0), false);
        cellar.addPosition(3, fraxPosition, abi.encode(0), false);
        cellar.addPosition(4, apePosition, abi.encode(0), false);

        cellar.addPosition(0, fraxlendDebtMKRPosition, abi.encode(0), true);

        MKR.safeApprove(address(cellar), type(uint256).max);
        FRAX.safeApprove(address(cellar), type(uint256).max);
        WETH.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        // stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    // test that holding position for adding collateral is being tracked properly and works upon user deposits
    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        console.log("Cellar MKR balance: %s, initialAssets: %s", MKR.balanceOf(address(cellar)), initialAssets);
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            MKR.balanceOf(address(cellar)),
            assets + initialAssets,
            1,
            "Cellar should have all deposited MKR assets"
        );

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        assertApproxEqAbs(
            MKR.balanceOf(address(cellar)),
            initialAssets,
            1,
            "Only initialAssets should be within Cellar."
        );

        uint256 newCellarCollateralBalance = mkrFToken.userCollateralBalance(address(cellar));
        assertEq(
            newCellarCollateralBalance,
            assets,
            "`fraxlendPairCore.userCollateralBalance()` check: Assets should be collateral provided to Fraxlend Pair."
        );
    }

    // carry out a total assets test checking that balanceOf works for adaptors.
    function testTotalAssets(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        console.log("Cellar MKR balance: %s, initialAssets: %s", MKR.balanceOf(address(cellar)), initialAssets);
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            cellar.totalAssets(),
            (assets + initialAssets),
            1,
            "Cellar.totalAssets() && CollateralFTokenAdaptorV2.balanceOf() check: Total assets should not have changed."
        );
    }

    // test taking loans w/ v2 fraxlend pairs
    function testTakingOutLoansV2(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        console.log("Cellar MKR balance: %s, initialAssets: %s", MKR.balanceOf(address(cellar)), initialAssets);
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = mkrFToken.userCollateralBalance(address(cellar));

        console.log("Cellar Fraxlend Collateral balance: %s", newCellarCollateralBalance);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        bytes memory adaptorData = abi.encode(MKR_FRAX_PAIR);

        vm.prank(address(cellar));
        uint256 newBalance = debtFTokenAdaptorV2.balanceOf(adaptorData);
        assertApproxEqAbs(
            newBalance,
            fraxToBorrow,
            1,
            "Cellar should have debt recorded within Fraxlend Pair of assets / 2"
        );
        assertApproxEqAbs(
            FRAX.balanceOf(address(cellar)),
            fraxToBorrow,
            1,
            "Cellar should have FRAX equal to assets / 2"
        );
    }

    // test taking loan w/ providing collateral to the wrong pair
    // TODO: troubleshoot bugs
    function testTakingOutLoanInUntrackedPositionV2() external {
        // assets = bound(assets, 0.1e18, 100_000e18);
        uint256 assets = 1e18;
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair

        cellar.addPositionToCatalogue(fraxlendCollateralAPEPosition);
        cellar.addPosition(0, fraxlendCollateralAPEPosition, abi.encode(0), false);
        cellar.addPositionToCatalogue(fraxlendDebtAPEPosition);
        cellar.addPosition(0, fraxlendDebtAPEPosition, abi.encode(0), true);

        // Try taking out a loan incorrectly where we have provided MKR, but are trying to access the APE_FRAX pair (which we shouldn't be able to).
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(APE_FRAX_PAIR, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        // TODO: EIN - I anticipate a reversion from the fraxlend side since the position is trusted but we do not have any collateral in that pair specifically.
        cellar.callOnAdaptor(data);
    }

    // TODO: see TODO below about evm error w/ addInterest() below
    function testRepayingLoans() external {
        // assets = bound(assets, 0.1e18, 100_000e18);
        uint256 assets = 1e18;
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow); //TODO: this will be interesting cause LTV maximums, etc.
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // start repayment sequence
        adaptorCalls[0] = _createBytesDataToAddInterestWithFraxlendV2(mkrFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // debtFTokenAdaptorV2.callAddInterest(mkrFraxLendPair); // TODO: EIN - getting an error here for some reason.
        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
        deal(address(FRAX), address(cellar), fraxToBorrow * 2);

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(mkrFToken, maxAmountToRepay);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar)),
            0,
            1,
            "Cellar should have zero debt recorded within Fraxlend Pair"
        );
        assertLt(FRAX.balanceOf(address(cellar)), fraxToBorrow * 2, "Cellar should have zero debtAsset");
    }

    // okay just seeing if we can handle multiple fraxlend positions
    // tests adding new positions too for new markets I guess
    // TODO: EIN - Reformat adaptorCall var names and troubleshoot why uniFraxToBorrow has to be 1e18 right now
    function testMultipleFraxlendPositions() external {
        // assets = bound(assets, 0.1e18, 100_000e18);
        uint256 assets = 1e18;
        // cellar.setRebalanceDeviation(0.004e18); // TODO: double check why setting rebalanceDeviation is needed

        // Add new assets related to new fraxlendMarket; UNI_FRAX
        uint32 fraxlendCollateralUNIPosition = 1_000_007; // fralendV2
        uint32 fraxlendDebtUNIPosition = 1_000_008; // fralendV2
        registry.trustPosition(
            fraxlendCollateralUNIPosition,
            address(collateralFTokenAdaptorV2),
            abi.encode(UNI_FRAX_PAIR, address(UNI))
        );
        registry.trustPosition(
            fraxlendDebtUNIPosition,
            address(debtFTokenAdaptorV2),
            abi.encode(address(UNI_FRAX_PAIR))
        );
        cellar.addPositionToCatalogue(uniPosition);
        cellar.addPositionToCatalogue(fraxlendCollateralUNIPosition);
        cellar.addPositionToCatalogue(fraxlendDebtUNIPosition);
        cellar.addPosition(5, fraxlendCollateralUNIPosition, abi.encode(0), false);
        cellar.addPosition(6, uniPosition, abi.encode(0), false);
        cellar.addPosition(1, fraxlendDebtUNIPosition, abi.encode(0), true);

        // multiple adaptor calls
        // deposit MKR
        // borrow FRAX
        // deposit UNI
        // borrow FRAX
        // uint256 initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair
        deal(address(UNI), address(cellar), assets);
        uint256 mkrFraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        // uint256 uniFraxToBorrow = priceRouter.getValue(UNI, assets / 2, FRAX);
        // console.log("uniFraxToBorrow: %s && assets/2: %s", uniFraxToBorrow, assets / 2);
        uint256 uniFraxToBorrow = 1e18;

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](2); // collateralAdaptor, MKR already deposited due to cellar holding position
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](2); // debtAdaptor
        adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        adaptorCallsFirstAdaptor[1] = _createBytesDataToAddCollateralWithFraxlendV2(UNI_FRAX_PAIR, assets);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, mkrFraxToBorrow);
        adaptorCallsSecondAdaptor[1] = _createBytesDataToBorrowWithFraxlendV2(UNI_FRAX_PAIR, uniFraxToBorrow);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(collateralFTokenAdaptorV2),
            callData: adaptorCallsFirstAdaptor
        });
        data[1] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCallsSecondAdaptor });
        cellar.callOnAdaptor(data);

        // Check that we have the right amount of FRAX borrowed
        assertApproxEqAbs(
            (getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar))) +
                getFraxlendDebtBalance(UNI_FRAX_PAIR, address(cellar)),
            mkrFraxToBorrow + uniFraxToBorrow,
            1
        );

        assertApproxEqAbs(FRAX.balanceOf(address(cellar)), mkrFraxToBorrow + uniFraxToBorrow, 1);

        Cellar.AdaptorCall[] memory newData = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        adaptorCalls[0] = _createBytesDataToAddInterestWithFraxlendV2(mkrFToken);
        newData[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(newData);
        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
        deal(address(FRAX), address(cellar), (mkrFraxToBorrow + uniFraxToBorrow) * 2);

        // Repay the loan in one of the fraxlend pairs
        Cellar.AdaptorCall[] memory newData2 = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls2 = new bytes[](1);
        adaptorCalls2[0] = _createBytesDataToRepayWithFraxlendV2(mkrFToken, maxAmountToRepay);
        newData2[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls2 });
        cellar.callOnAdaptor(newData2);

        // TODO: check that the repayment resulted in only one of the pairs LTV being improved. TODO: do we want to have a getter that provides the LTV or current healthFactor?
        assertApproxEqAbs(
            getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar)),
            0,
            1,
            "Cellar should have zero debt recorded within Fraxlend Pair"
        );

        assertApproxEqAbs(
            getFraxlendDebtBalance(UNI_FRAX_PAIR, address(cellar)),
            uniFraxToBorrow,
            1,
            "Cellar should still have debt for UNI Fraxlend Pair"
        );

        deal(address(MKR), address(cellar), 0);

        adaptorCalls2[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(assets, mkrFToken);
        newData2[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls2 });
        cellar.callOnAdaptor(newData2);

        // Check that we no longer have any MKR in the collateralPosition
        assertEq(MKR.balanceOf(address(cellar)), assets);

        // have user withdraw from cellar
        cellar.withdraw(assets, address(this), address(this));
        assertEq(MKR.balanceOf(address(this)), assets);
    }

    function testRemoveCollateral(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), initialAssets);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(assets, mkrFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(mkrFToken.userCollateralBalance(address(cellar)), 0);
    }

    function testRemoveSomeCollateral(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), initialAssets);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(assets / 2, mkrFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), (assets / 2) + initialAssets);
        assertApproxEqAbs(mkrFToken.userCollateralBalance(address(cellar)), assets / 2, 1);
    }

    // test attempting to removeCollateral() when the LTV would be too high as a result
    function testFailRemoveCollateralBecauseLTV(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), 0);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow); //TODO: this will be interesting cause LTV maximums, etc.
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        debtFTokenAdaptorV2.callAddInterest(mkrFraxLendPair); // TODO: EIN - getting an error here for some reason.

        // try to removeCollateral but more than should be allowed
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(assets, mkrFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CollateralFTokenAdaptorV2.CollateralFTokenAdaptor__HealthFactorTooLow.selector,
                    MKR_FRAX_PAIR
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // no getter for LTV, so I guess it's just testing that adding collateral to a almost maxed out LTV position increases debt allowance.
    function testLTV() external {
        // assets = bound(assets, 0.1e18, 100_000e18);
        uint256 assets = 1e18;
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = mkrFToken.userCollateralBalance(address(cellar));

        assertEq(MKR.balanceOf(address(cellar)), initialAssets);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(MKR, assets * 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(DebtFTokenAdaptorV2.DebtFTokenAdaptor__LTVTooHigh.selector, MKR_FRAX_PAIR))
        );
        cellar.callOnAdaptor(data); // TODO: CRISPY - it is reverting in a different way which I'm not sure about.

        // add collateral to be able to borrow amount desired
        deal(address(MKR), address(cellar), 3 * assets);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data); // TODO: CRISPY - please take a look at non-expected error generated.

        assertEq(MKR.balanceOf(address(cellar)), assets * 2);

        newCellarCollateralBalance = mkrFToken.userCollateralBalance(address(cellar));
        assertEq(newCellarCollateralBalance, 2 * assets);

        // Try taking out more FRAX now
        uint256 moreFraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, moreFraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data); // should transact now
    }

    // TODO: CRISPY - please take a look at the fuzzing, was having issues with this.
    function testRepayPartialDebt() external {
        // assets = bound(assets, 0.1e18, 100_000e18);
        uint256 assets = 1e18;
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // start repayment sequence
        // debtFTokenAdaptorV2.callAddInterest(mkrFraxLendPair); // TODO: CRISPY - getting an error here for some reason.

        uint256 debtBefore = getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar));
        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(mkrFToken, fraxToBorrow / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 debtNow = getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar));
        assertLt(debtNow, debtBefore);
        assertApproxEqAbs(
            FRAX.balanceOf(address(cellar)),
            fraxToBorrow / 2,
            1e18,
            "Cellar should have approximately half debtAsset"
        );
    }

    // This check stops strategists from taking on any debt in positions they do not set up properly.
    // TODO: CRISPY - getting an Index out of bounds error, and not sure why. Checked on foundry support TG, but no real answer there
    function testLoanInUntrackedPosition() external {
        cellar.setRebalanceDeviation(0.004e18); // TODO: double check why setting rebalanceDeviation is needed
        uint32 fraxlendCollateralUNIPosition = 1_000_007; // fralendV2
        registry.trustPosition(
            fraxlendCollateralUNIPosition,
            address(collateralFTokenAdaptorV2),
            abi.encode(UNI_FRAX_PAIR, address(UNI))
        );
        // purposely do not trust a fraxlendDebtUNIPosition
        cellar.addPositionToCatalogue(fraxlendCollateralUNIPosition);
        cellar.addPosition(5, fraxlendCollateralUNIPosition, abi.encode(0), false);
        uint256 assets = 100_000e18;
        uint256 uniFraxToBorrow = priceRouter.getValue(UNI, assets / 2, FRAX);

        deal(address(UNI), address(cellar), assets);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1); // collateralAdaptor
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](1); // debtAdaptor
        adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralWithFraxlendV2(UNI_FRAX_PAIR, assets);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowWithFraxlendV2(UNI_FRAX_PAIR, uniFraxToBorrow);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(collateralFTokenAdaptorV2),
            callData: adaptorCallsFirstAdaptor
        });
        data[1] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCallsSecondAdaptor });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    DebtFTokenAdaptorV2.DebtFTokenAdaptor__FraxlendPairPositionsMustBeTracked.selector,
                    address(UNI_FRAX_PAIR)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // have strategist call repay function when no debt owed. Expect revert.
    function testRepayingDebtThatIsNotOwed() external {
        uint256 assets = 100_000e18;
        // uint256 initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair
        // uint256 cellarBorrowShares = mkrFraxLendPair.userBorrowShares(address(cellar)); // TODO: double check this works
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(mkrFraxLendPair, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(DebtFTokenAdaptorV2.DebtFTokenAdaptor__CannotRepayNoDebt.selector, MKR_FRAX_PAIR)
            )
        );
        cellar.callOnAdaptor(data);
    }

    // externalReceiver triggers when doing Strategist Function calls via adaptorCall.
    function testBlockExternalReceiver() external {
        uint256 assets = 100_000e18;
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair
        // Strategist tries to withdraw USDC to their own wallet using Adaptor's `withdraw` function.
        address maliciousStrategist = vm.addr(10);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(
            CollateralFTokenAdaptorV2.withdraw.selector,
            100_000e18,
            maliciousStrategist,
            abi.encode(MKR_FRAX_PAIR, MKR),
            abi.encode(0)
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV2), callData: adaptorCalls });
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        cellar.callOnAdaptor(data);
    }

    // // ========================================== UNCERTAIN TESTS ==========================================

    // TODO: test isSolvent check
    function testIsSolventHelper() external {
        // (, uint256 _exchangeRate, ) = fraxlendPair.updateExchangeRate(); // needed to calculate LTV in next line
        //     // Check if borrower is insolvent after this borrow tx, revert if they are
        //     if (!_isSolvent(fraxlendPair, _exchangeRate)) {
        //         revert DebtFTokenAdaptor__LTVTooLow(address(fraxlendPair));
        //     }
    }

    // TODO: delete this test probably cause it just reverts
    function testWithdrawableFrom() external {
        // uint256 withdrawableFrom = debtFTokenAdaptorV2.withdrawableFrom();
        // assertEq(withdrawableFrom, 0);
    }

    // // ========================================== INTEGRATION TEST ==========================================

    // // TODO: Write integration test following similar pattern below except for flash loans.
    // // Test implementation below is still from AAVE.t.sol
    // function testIntegration() external {
    //     // // Manage positions to reflect the following
    //     // // 0) aV2USDC (holding)
    //     // // 1) aV2WETH
    //     // // 2) aV2WBTC
    //     // // Debt Position
    //     // // 0) dV2USDC
    //     // uint32 aV2WETHPosition = 1_000_003;
    //     // registry.trustPosition(aV2WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV2WETH)));
    //     // uint32 aV2WBTCPosition = 1_000_004;
    //     // registry.trustPosition(aV2WBTCPosition, address(aaveATokenAdaptor), abi.encode(address(aV2WBTC)));
    //     // cellar.addPositionToCatalogue(aV2WETHPosition);
    //     // cellar.addPositionToCatalogue(aV2WBTCPosition);
    //     // cellar.addPosition(1, aV2WETHPosition, abi.encode(0), false);
    //     // cellar.addPosition(2, aV2WBTCPosition, abi.encode(0), false);
    //     // cellar.removePosition(3, false);
    //     // // Have whale join the cellar with 1M USDC.
    //     // uint256 assets = 1_000_000e6;
    //     // address whale = vm.addr(777);
    //     // deal(address(USDC), whale, assets);
    //     // vm.startPrank(whale);
    //     // USDC.approve(address(cellar), assets);
    //     // cellar.deposit(assets, whale);
    //     // vm.stopPrank();
    //     // // Strategist manages cellar in order to achieve the following portfolio.
    //     // // ~20% in aV2USDC.
    //     // // ~40% Aave aV2WETH/dV2USDC with 2x LONG on WETH.
    //     // // ~40% Aave aV2WBTC/dV2USDC with 3x LONG on WBTC.
    //     // Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](5);
    //     // // Create data to withdraw USDC, swap for WETH and WBTC and lend them on Aave.
    //     // uint256 amountToSwap = assets.mulDivDown(8, 10);
    //     // {
    //     //     bytes[] memory adaptorCalls = new bytes[](1);
    //     //     adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV2(USDC, assets.mulDivDown(8, 10));
    //     //     data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
    //     // }
    //     // {
    //     //     bytes[] memory adaptorCalls = new bytes[](2);
    //     //     adaptorCalls[0] = _createBytesDataForSwapWithUniv3(USDC, WETH, 500, amountToSwap);
    //     //     amountToSwap = priceRouter.getValue(USDC, amountToSwap / 2, WETH);
    //     //     adaptorCalls[1] = _createBytesDataForSwapWithUniv3(WETH, WBTC, 500, amountToSwap);
    //     //     data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
    //     // }
    //     // {
    //     //     bytes[] memory adaptorCalls = new bytes[](2);
    //     //     adaptorCalls[0] = _createBytesDataToLendOnAaveV2(WETH, type(uint256).max);
    //     //     adaptorCalls[1] = _createBytesDataToLendOnAaveV2(WBTC, type(uint256).max);
    //     //     data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
    //     // }
    //     // // Create data to flash loan USDC, sell it, and lend more WETH and WBTC on Aave.
    //     // {
    //     //     // Want to borrow 3x 40% of assets
    //     //     uint256 USDCtoFlashLoan = assets.mulDivDown(12, 10);
    //     //     // Borrow the flash loan amount + premium.
    //     //     uint256 USDCtoBorrow = USDCtoFlashLoan.mulDivDown(1e3 + pool.FLASHLOAN_PREMIUM_TOTAL(), 1e3);
    //     //     bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
    //     //     Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](3);
    //     //     bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](2);
    //     //     bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](2);
    //     //     bytes[] memory adaptorCallsInsideFlashLoanThirdAdaptor = new bytes[](1);
    //     //     // Swap USDC for WETH.
    //     //     adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataForSwapWithUniv3(
    //     //         USDC,
    //     //         WETH,
    //     //         500,
    //     //         USDCtoFlashLoan
    //     //     );
    //     //     // Swap USDC for WBTC.
    //     //     amountToSwap = priceRouter.getValue(USDC, USDCtoFlashLoan.mulDivDown(2, 3), WETH);
    //     //     adaptorCallsInsideFlashLoanFirstAdaptor[1] = _createBytesDataForSwapWithUniv3(
    //     //         WETH,
    //     //         WBTC,
    //     //         500,
    //     //         amountToSwap
    //     //     );
    //     //     // Lend USDC on Aave specifying to use the max amount available.
    //     //     adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToLendOnAaveV2(WETH, type(uint256).max);
    //     //     adaptorCallsInsideFlashLoanSecondAdaptor[1] = _createBytesDataToLendOnAaveV2(WBTC, type(uint256).max);
    //     //     adaptorCallsInsideFlashLoanThirdAdaptor[0] = _createBytesDataToBorrowFromAaveV2(dV2USDC, USDCtoBorrow);
    //     //     dataInsideFlashLoan[0] = Cellar.AdaptorCall({
    //     //         adaptor: address(swapWithUniswapAdaptor),
    //     //         callData: adaptorCallsInsideFlashLoanFirstAdaptor
    //     //     });
    //     //     dataInsideFlashLoan[1] = Cellar.AdaptorCall({
    //     //         adaptor: address(aaveATokenAdaptor),
    //     //         callData: adaptorCallsInsideFlashLoanSecondAdaptor
    //     //     });
    //     //     dataInsideFlashLoan[2] = Cellar.AdaptorCall({
    //     //         adaptor: address(aaveDebtTokenAdaptor),
    //     //         callData: adaptorCallsInsideFlashLoanThirdAdaptor
    //     //     });
    //     //     address[] memory loanToken = new address[](1);
    //     //     loanToken[0] = address(USDC);
    //     //     uint256[] memory loanAmount = new uint256[](1);
    //     //     loanAmount[0] = USDCtoFlashLoan;
    //     //     adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoanFromAaveV2(
    //     //         loanToken,
    //     //         loanAmount,
    //     //         abi.encode(dataInsideFlashLoan)
    //     //     );
    //     //     data[3] = Cellar.AdaptorCall({
    //     //         adaptor: address(aaveDebtTokenAdaptor),
    //     //         callData: adaptorCallsForFlashLoan
    //     //     });
    //     // }
    //     // // Create data to lend remaining USDC on Aave.
    //     // {
    //     //     bytes[] memory adaptorCalls = new bytes[](1);
    //     //     adaptorCalls[0] = _createBytesDataToLendOnAaveV2(USDC, type(uint256).max);
    //     //     data[4] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
    //     // }
    //     // // Adjust rebalance deviation to account for slippage and fees(swap and flash loan).
    //     // cellar.setRebalanceDeviation(0.03e18);
    //     // cellar.callOnAdaptor(data);
    //     // assertLt(cellar.totalAssetsWithdrawable(), assets, "Assets withdrawable should be less than assets.");
    //     // // Whale withdraws as much as they can.
    //     // vm.startPrank(whale);
    //     // uint256 assetsToWithdraw = cellar.maxWithdraw(whale);
    //     // cellar.withdraw(assetsToWithdraw, whale, whale);
    //     // vm.stopPrank();
    //     // assertEq(USDC.balanceOf(whale), assetsToWithdraw, "Amount withdrawn should equal maxWithdraw for Whale.");
    //     // // Other user joins.
    //     // assets = 100_000e6;
    //     // address user = vm.addr(777);
    //     // deal(address(USDC), user, assets);
    //     // vm.startPrank(user);
    //     // USDC.approve(address(cellar), assets);
    //     // cellar.deposit(assets, user);
    //     // vm.stopPrank();
    //     // assertApproxEqAbs(
    //     //     cellar.totalAssetsWithdrawable(),
    //     //     assets,
    //     //     1,
    //     //     "Total assets withdrawable should equal user deposit."
    //     // );
    //     // // Whale withdraws as much as they can.
    //     // vm.startPrank(whale);
    //     // assetsToWithdraw = cellar.maxWithdraw(whale);
    //     // cellar.withdraw(assetsToWithdraw, whale, whale);
    //     // vm.stopPrank();
    //     // // Strategist must unwind strategy before any more withdraws can be made.
    //     // assertEq(cellar.totalAssetsWithdrawable(), 0, "There should be no more assets withdrawable.");
    //     // // Strategist is more Bullish on WBTC than WETH, so they unwind the WETH position and keep the WBTC position.
    //     // data = new Cellar.AdaptorCall[](2);
    //     // {
    //     //     uint256 cellarAV2WETH = aV2WETH.balanceOf(address(cellar));
    //     //     // By lowering the USDC flash loan amount, we free up more aV2USDC for withdraw, but lower the health factor
    //     //     uint256 USDCtoFlashLoan = priceRouter.getValue(WETH, cellarAV2WETH, USDC).mulDivDown(8, 10);
    //     //     bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
    //     //     Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](3);
    //     //     bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](1);
    //     //     bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](1);
    //     //     bytes[] memory adaptorCallsInsideFlashLoanThirdAdaptor = new bytes[](1);
    //     //     // Repay USDC debt.
    //     //     adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataToRepayToAaveV2(USDC, USDCtoFlashLoan);
    //     //     // Withdraw WETH and swap for USDC.
    //     //     adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToWithdrawFromAaveV2(WETH, cellarAV2WETH);
    //     //     adaptorCallsInsideFlashLoanThirdAdaptor[0] = _createBytesDataForSwapWithUniv3(
    //     //         WETH,
    //     //         USDC,
    //     //         500,
    //     //         cellarAV2WETH
    //     //     );
    //     //     dataInsideFlashLoan[0] = Cellar.AdaptorCall({
    //     //         adaptor: address(aaveDebtTokenAdaptor),
    //     //         callData: adaptorCallsInsideFlashLoanFirstAdaptor
    //     //     });
    //     //     dataInsideFlashLoan[1] = Cellar.AdaptorCall({
    //     //         adaptor: address(aaveATokenAdaptor),
    //     //         callData: adaptorCallsInsideFlashLoanSecondAdaptor
    //     //     });
    //     //     dataInsideFlashLoan[2] = Cellar.AdaptorCall({
    //     //         adaptor: address(swapWithUniswapAdaptor),
    //     //         callData: adaptorCallsInsideFlashLoanThirdAdaptor
    //     //     });
    //     //     address[] memory loanToken = new address[](1);
    //     //     loanToken[0] = address(USDC);
    //     //     uint256[] memory loanAmount = new uint256[](1);
    //     //     loanAmount[0] = USDCtoFlashLoan;
    //     //     adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoanFromAaveV2(
    //     //         loanToken,
    //     //         loanAmount,
    //     //         abi.encode(dataInsideFlashLoan)
    //     //     );
    //     //     data[0] = Cellar.AdaptorCall({
    //     //         adaptor: address(aaveDebtTokenAdaptor),
    //     //         callData: adaptorCallsForFlashLoan
    //     //     });
    //     // }
    //     // // Create data to lend remaining USDC on Aave.
    //     // {
    //     //     bytes[] memory adaptorCalls = new bytes[](1);
    //     //     adaptorCalls[0] = _createBytesDataToLendOnAaveV2(USDC, type(uint256).max);
    //     //     data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
    //     // }
    //     // cellar.callOnAdaptor(data);
    //     // assertGt(
    //     //     cellar.totalAssetsWithdrawable(),
    //     //     100_000e6,
    //     //     "There should a significant amount of assets withdrawable."
    //     // );
    // }

    /// Fraxlend Collateral and Debt Specific Helpers

    // function getFraxlendCollateralBalance(address _fraxlendPair, address _user) internal view returns (uint256) {

    // }

    function getFraxlendDebtBalance(address _fraxlendPair, address _user) internal view returns (uint256) {
        IFToken fraxlendPair = IFToken(_fraxlendPair);
        return _toBorrowAmount(fraxlendPair, fraxlendPair.userBorrowShares(_user), false, ACCOUNT_FOR_INTEREST);
    }

    function _toBorrowAmount(
        IFToken _fraxlendPair,
        uint256 _shares,
        bool _roundUp,
        bool _previewInterest
    ) internal view virtual returns (uint256) {
        return _fraxlendPair.toBorrowAmount(_shares, _roundUp, _previewInterest);
    }
}
