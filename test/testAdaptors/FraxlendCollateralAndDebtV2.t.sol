// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CollateralFTokenAdaptor } from "src/modules/adaptors/Frax/CollateralFTokenAdaptor.sol";
import { DebtFTokenAdaptor } from "src/modules/adaptors/Frax/DebtFTokenAdaptor.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import "test/resources/MainnetStarter.t.sol";

/**
 * @notice Test provision of collateral and borrowing on Fraxlend v2 pairs
 * @author 0xEinCodes, crispymangoes
 * @dev test with blocknumber = 18414005 bc of fraxlend pair conditions at this block otherwise modify fuzz test limits
 */
contract CellarFraxLendCollateralAndDebtTestV2 is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    CollateralFTokenAdaptor public collateralFTokenAdaptor;
    DebtFTokenAdaptor public debtFTokenAdaptor;
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
    uint256 minHealthFactor = 1.05e18;

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
        creationCode = type(CollateralFTokenAdaptor).creationCode;
        constructorArgs = abi.encode(address(FRAX), minHealthFactor);
        collateralFTokenAdaptor = CollateralFTokenAdaptor(
            deployer.deployContract("FraxLend Collateral fToken Adaptor V 0.1", creationCode, constructorArgs, 0)
        );

        creationCode = type(DebtFTokenAdaptor).creationCode;
        constructorArgs = abi.encode(ACCOUNT_FOR_INTEREST, address(FRAX), minHealthFactor);
        debtFTokenAdaptor = DebtFTokenAdaptor(
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
        registry.trustAdaptor(address(collateralFTokenAdaptor));
        registry.trustAdaptor(address(debtFTokenAdaptor));

        registry.trustPosition(fraxPosition, address(erc20Adaptor), abi.encode(FRAX));
        registry.trustPosition(mkrPosition, address(erc20Adaptor), abi.encode(MKR));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(apePosition, address(erc20Adaptor), abi.encode(APE));
        registry.trustPosition(uniPosition, address(erc20Adaptor), abi.encode(UNI));

        registry.trustPosition(
            fraxlendCollateralMKRPosition,
            address(collateralFTokenAdaptor),
            abi.encode(MKR_FRAX_PAIR)
        );
        registry.trustPosition(fraxlendDebtMKRPosition, address(debtFTokenAdaptor), abi.encode(MKR_FRAX_PAIR));
        registry.trustPosition(
            fraxlendCollateralAPEPosition,
            address(collateralFTokenAdaptor),
            abi.encode(APE_FRAX_PAIR)
        );
        registry.trustPosition(fraxlendDebtAPEPosition, address(debtFTokenAdaptor), abi.encode(APE_FRAX_PAIR));

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
            abi.encode(true),
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(collateralFTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(debtFTokenAdaptor));

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(fraxlendCollateralMKRPosition);
        cellar.addPositionToCatalogue(fraxlendDebtMKRPosition);
        cellar.addPositionToCatalogue(fraxPosition);
        cellar.addPositionToCatalogue(apePosition);

        cellar.addPosition(1, wethPosition, abi.encode(true), false);
        cellar.addPosition(2, fraxlendCollateralMKRPosition, abi.encode(0), false);
        cellar.addPosition(3, fraxPosition, abi.encode(true), false);
        cellar.addPosition(4, apePosition, abi.encode(true), false);

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
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
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

        // addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            cellar.totalAssets(),
            (assets + initialAssets),
            1,
            "Cellar.totalAssets() && CollateralFTokenAdaptor.balanceOf() check: Total assets should not have changed."
        );
    }

    // test taking loans w/ v2 fraxlend pairs
    function testTakingOutLoansV2(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        console.log("Cellar MKR balance: %s, initialAssets: %s", MKR.balanceOf(address(cellar)), initialAssets);
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        bytes memory adaptorData = abi.encode(MKR_FRAX_PAIR);

        vm.prank(address(cellar));
        uint256 newBalance = debtFTokenAdaptor.balanceOf(adaptorData);
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
    function testTakingOutLoanInUntrackedPositionV2(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(APE_FRAX_PAIR, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    DebtFTokenAdaptor.DebtFTokenAdaptor__FraxlendPairPositionsMustBeTracked.selector,
                    APE_FRAX_PAIR
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingLoans(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // start repayment sequence
        mkrFraxLendPair.addInterest(false);
        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
        deal(address(FRAX), address(cellar), fraxToBorrow * 2);

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(mkrFToken, maxAmountToRepay);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
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
    // TODO: EIN - Reformat adaptorCall var names and troubleshoot why uniFraxToBorrow has to be 1e18 right now
    function testMultipleFraxlendPositions() external {
        uint256 assets = 1e18;

        // Add new assets related to new fraxlendMarket; UNI_FRAX
        uint32 fraxlendCollateralUNIPosition = 1_000_007; // fralendV2
        uint32 fraxlendDebtUNIPosition = 1_000_008; // fralendV2
        registry.trustPosition(
            fraxlendCollateralUNIPosition,
            address(collateralFTokenAdaptor),
            abi.encode(UNI_FRAX_PAIR)
        );
        registry.trustPosition(fraxlendDebtUNIPosition, address(debtFTokenAdaptor), abi.encode(UNI_FRAX_PAIR));
        cellar.addPositionToCatalogue(uniPosition);
        cellar.addPositionToCatalogue(fraxlendCollateralUNIPosition);
        cellar.addPositionToCatalogue(fraxlendDebtUNIPosition);
        cellar.addPosition(5, fraxlendCollateralUNIPosition, abi.encode(0), false);
        cellar.addPosition(6, uniPosition, abi.encode(true), false);
        cellar.addPosition(1, fraxlendDebtUNIPosition, abi.encode(0), true);

        // multiple adaptor calls
        // deposit MKR
        // borrow FRAX
        // deposit UNI
        // borrow FRAX
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
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCallsFirstAdaptor });
        data[1] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCallsSecondAdaptor });
        cellar.callOnAdaptor(data);

        // Check that we have the right amount of FRAX borrowed
        assertApproxEqAbs(
            (getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar))) +
                getFraxlendDebtBalance(UNI_FRAX_PAIR, address(cellar)),
            mkrFraxToBorrow + uniFraxToBorrow,
            1
        );

        assertApproxEqAbs(FRAX.balanceOf(address(cellar)), mkrFraxToBorrow + uniFraxToBorrow, 1);

        mkrFraxLendPair.addInterest(false);
        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
        deal(address(FRAX), address(cellar), (mkrFraxToBorrow + uniFraxToBorrow) * 2);

        // Repay the loan in one of the fraxlend pairs
        Cellar.AdaptorCall[] memory newData2 = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls2 = new bytes[](1);
        adaptorCalls2[0] = _createBytesDataToRepayWithFraxlendV2(mkrFToken, maxAmountToRepay);
        newData2[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls2 });
        cellar.callOnAdaptor(newData2);

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
        newData2[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls2 });
        cellar.callOnAdaptor(newData2);

        // Check that we no longer have any MKR in the collateralPosition
        assertEq(MKR.balanceOf(address(cellar)), assets);

        // have user withdraw from cellar
        cellar.withdraw(assets, address(this), address(this));
        assertEq(MKR.balanceOf(address(this)), assets);
    }

    function testRemoveCollateral(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), initialAssets);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(assets, mkrFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
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
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), initialAssets);

        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(assets / 2, mkrFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), (assets / 2) + initialAssets);
        assertApproxEqAbs(mkrFToken.userCollateralBalance(address(cellar)), assets / 2, 1);
    }

    // test strategist input param for _collateralAmount to be type(uint256).max
    function testRemoveAllCollateralWithTypeUINT256Max(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), initialAssets);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(type(uint256).max, mkrFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(mkrFToken.userCollateralBalance(address(cellar)), 0);
    }

    // Test removal of collateral but with taking a loan out and repaying it in full first. Also tests type(uint256).max with removeCollateral.
    function testRemoveCollateralWithTypeUINT256MaxAfterRepay(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // start repayment sequence
        mkrFraxLendPair.addInterest(false);
        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
        deal(address(FRAX), address(cellar), fraxToBorrow * 2);

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(mkrFToken, maxAmountToRepay);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar)),
            0,
            1,
            "Cellar should have zero debt recorded within Fraxlend Pair"
        );
        assertLt(FRAX.balanceOf(address(cellar)), fraxToBorrow * 2, "Cellar should have zero debtAsset");

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(type(uint256).max, mkrFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(mkrFToken.userCollateralBalance(address(cellar)), 0);
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
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), 0);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        mkrFraxLendPair.addInterest(false);
        // try to removeCollateral but more than should be allowed
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(assets, mkrFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CollateralFTokenAdaptor.CollateralFTokenAdaptor__HealthFactorTooLow.selector,
                    MKR_FRAX_PAIR
                )
            )
        );
        cellar.callOnAdaptor(data);

        // try again with type(uint256).max as specified amount
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV2(type(uint256).max, mkrFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CollateralFTokenAdaptor.CollateralFTokenAdaptor__HealthFactorTooLow.selector,
                    MKR_FRAX_PAIR
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testLTV(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = mkrFToken.userCollateralBalance(address(cellar));

        assertEq(MKR.balanceOf(address(cellar)), initialAssets);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(MKR, assets.mulDivDown(1e4, 1.35e4), FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(DebtFTokenAdaptor.DebtFTokenAdaptor__HealthFactorTooLow.selector, MKR_FRAX_PAIR)
            )
        );
        cellar.callOnAdaptor(data);

        // add collateral to be able to borrow amount desired
        deal(address(MKR), address(cellar), 3 * assets);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(MKR.balanceOf(address(cellar)), assets * 2);

        newCellarCollateralBalance = mkrFToken.userCollateralBalance(address(cellar));
        assertEq(newCellarCollateralBalance, 2 * assets);

        // Try taking out more FRAX now
        uint256 moreFraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, moreFraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data); // should transact now
    }

    function testRepayPartialDebt(uint256 assets) external {
        assets = bound(assets, 0.1e18, 195e18);
        initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV2(MKR_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(MKR, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // start repayment sequence
        mkrFraxLendPair.addInterest(false);

        uint256 debtBefore = getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar));
        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(mkrFToken, fraxToBorrow / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
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
    function testLoanInUntrackedPosition(uint256 assets) external {
        uint32 fraxlendCollateralUNIPosition = 1_000_007; // fralendV2
        registry.trustPosition(
            fraxlendCollateralUNIPosition,
            address(collateralFTokenAdaptor),
            abi.encode(UNI_FRAX_PAIR)
        );
        // purposely do not trust a fraxlendDebtUNIPosition
        cellar.addPositionToCatalogue(fraxlendCollateralUNIPosition);
        cellar.addPosition(5, fraxlendCollateralUNIPosition, abi.encode(0), false);
        assets = bound(assets, 0.1e18, 100e18);
        uint256 uniFraxToBorrow = priceRouter.getValue(UNI, assets / 2, FRAX);

        deal(address(UNI), address(cellar), assets);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1); // collateralAdaptor
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](1); // debtAdaptor
        adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralWithFraxlendV2(UNI_FRAX_PAIR, assets);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowWithFraxlendV2(UNI_FRAX_PAIR, uniFraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCallsFirstAdaptor });
        data[1] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCallsSecondAdaptor });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    DebtFTokenAdaptor.DebtFTokenAdaptor__FraxlendPairPositionsMustBeTracked.selector,
                    address(UNI_FRAX_PAIR)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // have strategist call repay function when no debt owed. Expect revert.
    function testRepayingDebtThatIsNotOwed(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(mkrFraxLendPair, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(DebtFTokenAdaptor.DebtFTokenAdaptor__CannotRepayNoDebt.selector, MKR_FRAX_PAIR)
            )
        );
        cellar.callOnAdaptor(data);
    }

    // externalReceiver triggers when doing Strategist Function calls via adaptorCall.
    function testBlockExternalReceiver(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair
        // Strategist tries to withdraw USDC to their own wallet using Adaptor's `withdraw` function.
        address maliciousStrategist = vm.addr(10);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(
            CollateralFTokenAdaptor.withdraw.selector,
            100_000e18,
            maliciousStrategist,
            abi.encode(MKR_FRAX_PAIR, MKR),
            abi.encode(0)
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls });
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        cellar.callOnAdaptor(data);
    }

    /// Fraxlend Collateral and Debt Specific Helpers

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
