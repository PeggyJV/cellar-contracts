// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CollateralFTokenAdaptorV1 } from "src/modules/adaptors/Frax/CollateralFTokenAdaptorV1.sol";
import { DebtFTokenAdaptorV1 } from "src/modules/adaptors/Frax/DebtFTokenAdaptorV1.sol";
import { CollateralFTokenAdaptor } from "src/modules/adaptors/Frax/CollateralFTokenAdaptor.sol";
import { DebtFTokenAdaptor } from "src/modules/adaptors/Frax/DebtFTokenAdaptor.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import "test/resources/MainnetStarter.t.sol";

/**
 * @notice Test provision of collateral and borrowing on Fraxlend v1 pairs
 * @author 0xEinCodes, crispymangoes
 * @dev These are applied to FraxlendV1 Pair types and are the same tests carried out for FraxlendV1 pairs and the respective debt and collateral adaptors.
 * @dev test with blocknumber = 18414005 bc of fraxlend pair conditions at this block otherwise modify fuzz test limits
 */
contract CellarFraxLendCollateralAndDebtTestV1 is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    CollateralFTokenAdaptorV1 public collateralFTokenAdaptorV1;
    DebtFTokenAdaptorV1 public debtFTokenAdaptorV1;
    Cellar public cellar;
    IFToken crvFraxLendPair = IFToken(CRV_FRAX_PAIR);

    uint32 public fraxlendCollateralCRVPosition = 1_000_001; // fraxlendV1
    uint32 public fraxlendDebtCRVPosition = 1_000_002; // fraxlendV1

    uint32 public fraxlendCollateralWBTCPosition = 1_000_003; // fraxlendV1
    uint32 public fraxlendDebtWBTCPosition = 1_000_004; // fraxlendV1
    uint32 public fraxlendDebtWETHPosition = 1_000_005; // fraxlendV1

    // Chainlink PriceFeeds
    MockDataFeed private mockFraxUsd;
    MockDataFeed private mockWethUsd;
    MockDataFeed private mockCRVUsd;
    MockDataFeed private mockWbtcUsd;
    MockDataFeed private mockCvxEth;

    uint32 private fraxPosition = 1;
    uint32 private crvPosition = 2;
    uint32 private wethPosition = 3;
    uint32 private wbtcPosition = 4;
    uint32 private cvxPosition = 5;

    // Mock Positions
    uint32 private mockFxsFraxPairPosition = 6;
    uint32 private mockSfrxEthFraxPairPosition = 7;

    uint256 initialAssets;
    uint256 minHealthFactor = 1.05e18;

    IFToken crvFToken = IFToken(address(CRV_FRAX_PAIR));
    bool ACCOUNT_FOR_INTEREST = true;

    function setUp() public {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17843162;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockFraxUsd = new MockDataFeed(FRAX_USD_FEED);
        mockCRVUsd = new MockDataFeed(CRV_USD_FEED);
        mockWethUsd = new MockDataFeed(WETH_USD_FEED);
        mockWbtcUsd = new MockDataFeed(WBTC_USD_FEED);
        mockCvxEth = new MockDataFeed(CVX_ETH_FEED);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CollateralFTokenAdaptorV1).creationCode;
        constructorArgs = abi.encode(address(FRAX), minHealthFactor);
        collateralFTokenAdaptorV1 = CollateralFTokenAdaptorV1(
            deployer.deployContract("FraxLend Collateral fToken Adaptor V 0.1", creationCode, constructorArgs, 0)
        );

        creationCode = type(DebtFTokenAdaptorV1).creationCode;
        constructorArgs = abi.encode(ACCOUNT_FOR_INTEREST, address(FRAX), minHealthFactor);
        debtFTokenAdaptorV1 = DebtFTokenAdaptorV1(
            deployer.deployContract("FraxLend debtToken Adaptor V 1.0", creationCode, constructorArgs, 0)
        );

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(mockFraxUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockFraxUsd));
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        price = uint256(mockCRVUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockCRVUsd));
        priceRouter.addAsset(CRV, settings, abi.encode(stor), price);

        price = uint256(mockWethUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWethUsd));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(mockWbtcUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWbtcUsd));
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        price = uint256(mockCvxEth.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockCvxEth));
        priceRouter.addAsset(CVX, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(collateralFTokenAdaptorV1));
        registry.trustAdaptor(address(debtFTokenAdaptorV1));

        registry.trustPosition(fraxPosition, address(erc20Adaptor), abi.encode(FRAX));
        registry.trustPosition(crvPosition, address(erc20Adaptor), abi.encode(CRV));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));
        registry.trustPosition(cvxPosition, address(erc20Adaptor), abi.encode(CVX));

        registry.trustPosition(
            fraxlendCollateralCRVPosition,
            address(collateralFTokenAdaptorV1),
            abi.encode(CRV_FRAX_PAIR)
        );
        registry.trustPosition(fraxlendDebtCRVPosition, address(debtFTokenAdaptorV1), abi.encode(CRV_FRAX_PAIR));
        registry.trustPosition(
            fraxlendCollateralWBTCPosition,
            address(collateralFTokenAdaptorV1),
            abi.encode(WBTC_FRAX_PAIR)
        );
        registry.trustPosition(fraxlendDebtWBTCPosition, address(debtFTokenAdaptorV1), abi.encode(WBTC_FRAX_PAIR));

        string memory cellarName = "Fraxlend Collateral & Debt Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(CRV), address(this), initialDeposit);
        CRV.approve(cellarAddress, initialDeposit);

        creationCode = type(Cellar).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            CRV,
            cellarName,
            cellarName,
            crvPosition,
            abi.encode(true),
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(collateralFTokenAdaptorV1));
        cellar.addAdaptorToCatalogue(address(debtFTokenAdaptorV1));

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(fraxlendCollateralCRVPosition);
        cellar.addPositionToCatalogue(fraxlendDebtCRVPosition);
        cellar.addPositionToCatalogue(fraxPosition);
        cellar.addPositionToCatalogue(wbtcPosition);

        cellar.addPosition(1, wethPosition, abi.encode(true), false);
        cellar.addPosition(2, fraxlendCollateralCRVPosition, abi.encode(0), false);
        cellar.addPosition(3, fraxPosition, abi.encode(true), false);
        cellar.addPosition(4, wbtcPosition, abi.encode(true), false);

        cellar.addPosition(0, fraxlendDebtCRVPosition, abi.encode(0), true);

        CRV.safeApprove(address(cellar), type(uint256).max);
        FRAX.safeApprove(address(cellar), type(uint256).max);
        WETH.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        // stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    // test that holding position for adding collateral is being tracked properly and works upon user deposits
    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        console.log("Cellar CRV balance: %s, initialAssets: %s", CRV.balanceOf(address(cellar)), initialAssets);
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            CRV.balanceOf(address(cellar)),
            assets + initialAssets,
            1,
            "Cellar should have all deposited CRV assets"
        );

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        assertApproxEqAbs(
            CRV.balanceOf(address(cellar)),
            initialAssets,
            1,
            "Only initialAssets should be within Cellar."
        );

        uint256 newCellarCollateralBalance = crvFToken.userCollateralBalance(address(cellar));
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
        console.log("Cellar CRV balance: %s, initialAssets: %s", CRV.balanceOf(address(cellar)), initialAssets);
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));

        // addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            cellar.totalAssets(),
            (assets + initialAssets),
            1,
            "Cellar.totalAssets() && CollateralFTokenAdaptorV1.balanceOf() check: Total assets should not have changed."
        );
    }

    // test taking loans w/ v1 fraxlend pairs
    function testTakingOutLoansV1(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        console.log("Cellar CRV balance: %s, initialAssets: %s", CRV.balanceOf(address(cellar)), initialAssets);
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));

        // addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(CRV, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV1(CRV_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        bytes memory adaptorData = abi.encode(CRV_FRAX_PAIR);

        vm.prank(address(cellar));
        uint256 newBalance = debtFTokenAdaptorV1.balanceOf(adaptorData);
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
    function testTakingOutLoanInUntrackedPositionV1(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV1(WBTC_FRAX_PAIR, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    DebtFTokenAdaptor.DebtFTokenAdaptor__FraxlendPairPositionsMustBeTracked.selector,
                    WBTC_FRAX_PAIR
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingLoans(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));

        // addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(CRV, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV1(CRV_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // start repayment sequence
        crvFraxLendPair.addInterest();
        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
        deal(address(FRAX), address(cellar), fraxToBorrow * 2);

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV1(crvFToken, maxAmountToRepay);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            getFraxlendDebtBalance(CRV_FRAX_PAIR, address(cellar)),
            0,
            1,
            "Cellar should have zero debt recorded within Fraxlend Pair"
        );
        assertLt(FRAX.balanceOf(address(cellar)), fraxToBorrow * 2, "Cellar should have zero debtAsset");
    }

    // okay just seeing if we can handle multiple fraxlend positions
    // TODO: EIN - Reformat adaptorCall var names and troubleshoot why cvxFraxToBorrow has to be 1e18 right now --> Theory: it has to do with the CVX pricing in the cellars?
    function testMultipleFraxlendPositions() external {
        uint256 assets = 1e18;

        // Add new assets related to new fraxlendMarket; CVX_FRAX
        uint32 fraxlendCollateralCVXPosition = 1_000_007; // fralendV1
        uint32 fraxlendDebtCVXPosition = 1_000_008; // fralendV1
        registry.trustPosition(
            fraxlendCollateralCVXPosition,
            address(collateralFTokenAdaptorV1),
            abi.encode(CVX_FRAX_PAIR)
        );
        registry.trustPosition(fraxlendDebtCVXPosition, address(debtFTokenAdaptorV1), abi.encode(CVX_FRAX_PAIR));
        cellar.addPositionToCatalogue(cvxPosition);
        cellar.addPositionToCatalogue(fraxlendCollateralCVXPosition);
        cellar.addPositionToCatalogue(fraxlendDebtCVXPosition);
        cellar.addPosition(5, fraxlendCollateralCVXPosition, abi.encode(0), false);
        cellar.addPosition(6, cvxPosition, abi.encode(true), false);
        cellar.addPosition(1, fraxlendDebtCVXPosition, abi.encode(0), true);

        // multiple adaptor calls
        // deposit CRV
        // borrow FRAX
        // deposit CVX
        // borrow FRAX
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ CRV FraxlendPair
        deal(address(CVX), address(cellar), assets);
        uint256 crvFraxToBorrow = priceRouter.getValue(CRV, assets / 2, FRAX);
        // uint256 cvxFraxToBorrow = priceRouter.getValue(CVX, assets / 2, FRAX);
        // console.log("cvxFraxToBorrow: %s && assets/2: %s", cvxFraxToBorrow, assets / 2);
        uint256 cvxFraxToBorrow = 1e18;

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](2); // collateralAdaptor, CRV already deposited due to cellar holding position
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](2); // debtAdaptor
        adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        adaptorCallsFirstAdaptor[1] = _createBytesDataToAddCollateralWithFraxlendV1(CVX_FRAX_PAIR, assets);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowWithFraxlendV1(CRV_FRAX_PAIR, crvFraxToBorrow);
        adaptorCallsSecondAdaptor[1] = _createBytesDataToBorrowWithFraxlendV1(CVX_FRAX_PAIR, cvxFraxToBorrow);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(collateralFTokenAdaptorV1),
            callData: adaptorCallsFirstAdaptor
        });
        data[1] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCallsSecondAdaptor });
        cellar.callOnAdaptor(data);

        // Check that we have the right amount of FRAX borrowed
        assertApproxEqAbs(
            (getFraxlendDebtBalance(CRV_FRAX_PAIR, address(cellar))) +
                getFraxlendDebtBalance(CVX_FRAX_PAIR, address(cellar)),
            crvFraxToBorrow + cvxFraxToBorrow,
            1
        );

        assertApproxEqAbs(FRAX.balanceOf(address(cellar)), crvFraxToBorrow + cvxFraxToBorrow, 1);

        crvFraxLendPair.addInterest();
        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
        deal(address(FRAX), address(cellar), (crvFraxToBorrow + cvxFraxToBorrow) * 2);

        // Repay the loan in one of the fraxlend pairs
        Cellar.AdaptorCall[] memory newData2 = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls2 = new bytes[](1);
        adaptorCalls2[0] = _createBytesDataToRepayWithFraxlendV1(crvFToken, maxAmountToRepay);
        newData2[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls2 });
        cellar.callOnAdaptor(newData2);

        assertApproxEqAbs(
            getFraxlendDebtBalance(CRV_FRAX_PAIR, address(cellar)),
            0,
            1,
            "Cellar should have zero debt recorded within Fraxlend Pair"
        );

        assertApproxEqAbs(
            getFraxlendDebtBalance(CVX_FRAX_PAIR, address(cellar)),
            cvxFraxToBorrow,
            1,
            "Cellar should still have debt for CVX Fraxlend Pair"
        );

        deal(address(CRV), address(cellar), 0);

        adaptorCalls2[0] = _createBytesDataToRemoveCollateralWithFraxlendV1(assets, crvFToken);
        newData2[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls2 });
        cellar.callOnAdaptor(newData2);

        // Check that we no longer have any CRV in the collateralPosition
        assertEq(CRV.balanceOf(address(cellar)), assets);

        // have user withdraw from cellar
        cellar.withdraw(assets, address(this), address(this));
        assertEq(CRV.balanceOf(address(this)), assets);
    }

    function testRemoveCollateral(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(CRV.balanceOf(address(cellar)), initialAssets);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV1(assets, crvFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(CRV.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(crvFToken.userCollateralBalance(address(cellar)), 0);
    }

    function testRemoveSomeCollateral(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(CRV.balanceOf(address(cellar)), initialAssets);

        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV1(assets / 2, crvFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(CRV.balanceOf(address(cellar)), (assets / 2) + initialAssets);
        assertApproxEqAbs(crvFToken.userCollateralBalance(address(cellar)), assets / 2, 1);
    }

    // test strategist input param for _collateralAmount to be type(uint256).max
    function testRemoveAllCollateralWithTypeUINT256Max(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(CRV.balanceOf(address(cellar)), initialAssets);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV1(type(uint256).max, crvFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(CRV.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(crvFToken.userCollateralBalance(address(cellar)), 0);
    }

    // Test removal of collateral but with taking a loan out and repaying it in full first. Also tests type(uint256).max with removeCollateral.
    function testRemoveCollateralWithTypeUINT256MaxAfterRepay(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));

        // addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(CRV, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV1(CRV_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // start repayment sequence
        crvFraxLendPair.addInterest();
        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
        deal(address(FRAX), address(cellar), fraxToBorrow * 2);

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV1(crvFToken, maxAmountToRepay);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            getFraxlendDebtBalance(CRV_FRAX_PAIR, address(cellar)),
            0,
            1,
            "Cellar should have zero debt recorded within Fraxlend Pair"
        );
        assertLt(FRAX.balanceOf(address(cellar)), fraxToBorrow * 2, "Cellar should have zero debtAsset");

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV1(type(uint256).max, crvFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(CRV.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(crvFToken.userCollateralBalance(address(cellar)), 0);
    }

    // test attempting to removeCollateral() when the LTV would be too high as a result
    function testFailRemoveCollateralBecauseLTV(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(CRV.balanceOf(address(cellar)), 0);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(CRV, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV1(CRV_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        crvFraxLendPair.addInterest();
        // try to removeCollateral but more than should be allowed
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV1(assets, crvFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CollateralFTokenAdaptor.CollateralFTokenAdaptor__HealthFactorTooLow.selector,
                    CRV_FRAX_PAIR
                )
            )
        );
        cellar.callOnAdaptor(data);

        // try again with type(uint256).max as specified amount
        adaptorCalls[0] = _createBytesDataToRemoveCollateralWithFraxlendV1(type(uint256).max, crvFToken);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CollateralFTokenAdaptor.CollateralFTokenAdaptor__HealthFactorTooLow.selector,
                    CRV_FRAX_PAIR
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testLTV(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = crvFToken.userCollateralBalance(address(cellar));

        assertEq(CRV.balanceOf(address(cellar)), initialAssets);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(CRV, assets.mulDivDown(1e4, 1.35e4), FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV1(CRV_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(DebtFTokenAdaptor.DebtFTokenAdaptor__HealthFactorTooLow.selector, CRV_FRAX_PAIR)
            )
        );
        cellar.callOnAdaptor(data);

        // add collateral to be able to borrow amount desired
        deal(address(CRV), address(cellar), 3 * assets);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertEq(CRV.balanceOf(address(cellar)), assets * 2);

        newCellarCollateralBalance = crvFToken.userCollateralBalance(address(cellar));
        assertEq(newCellarCollateralBalance, 2 * assets);

        // Try taking out more FRAX now
        uint256 moreFraxToBorrow = priceRouter.getValue(CRV, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV1(CRV_FRAX_PAIR, moreFraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data); // should transact now
    }

    // TODO: CRISPY - please take a look at the fuzzing, was having issues with this.
    function testRepayPartialDebt(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralWithFraxlendV1(CRV_FRAX_PAIR, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a FRAX loan.
        uint256 fraxToBorrow = priceRouter.getValue(CRV, assets / 2, FRAX);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV1(CRV_FRAX_PAIR, fraxToBorrow);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // start repayment sequence
        crvFraxLendPair.addInterest();

        uint256 debtBefore = getFraxlendDebtBalance(CRV_FRAX_PAIR, address(cellar));
        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV1(crvFToken, fraxToBorrow / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 debtNow = getFraxlendDebtBalance(CRV_FRAX_PAIR, address(cellar));
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
        assets = bound(assets, 0.1e18, 100_000e18);

        uint32 fraxlendCollateralCVXPosition = 1_000_007; // fralendV1
        registry.trustPosition(
            fraxlendCollateralCVXPosition,
            address(collateralFTokenAdaptorV1),
            abi.encode(CVX_FRAX_PAIR)
        );
        // purposely do not trust a fraxlendDebtCVXPosition
        cellar.addPositionToCatalogue(fraxlendCollateralCVXPosition);
        cellar.addPosition(5, fraxlendCollateralCVXPosition, abi.encode(0), false);
        uint256 cvxFraxToBorrow = priceRouter.getValue(CVX, assets / 2, FRAX);

        deal(address(CVX), address(cellar), assets);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1); // collateralAdaptor
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](1); // debtAdaptor
        adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralWithFraxlendV1(CVX_FRAX_PAIR, assets);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowWithFraxlendV1(CVX_FRAX_PAIR, cvxFraxToBorrow);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(collateralFTokenAdaptorV1),
            callData: adaptorCallsFirstAdaptor
        });
        data[1] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCallsSecondAdaptor });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    DebtFTokenAdaptor.DebtFTokenAdaptor__FraxlendPairPositionsMustBeTracked.selector,
                    address(CVX_FRAX_PAIR)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // have strategist call repay function when no debt owed. Expect revert.
    function testRepayingDebtThatIsNotOwed(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);

        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this));
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV1(crvFraxLendPair, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV1), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(DebtFTokenAdaptor.DebtFTokenAdaptor__CannotRepayNoDebt.selector, CRV_FRAX_PAIR)
            )
        );
        cellar.callOnAdaptor(data);
    }

    // externalReceiver triggers when doing Strategist Function calls via adaptorCall.
    function testBlockExternalReceiver(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        deal(address(CRV), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ CRV FraxlendPair
        // Strategist tries to withdraw USDC to their own wallet using Adaptor's `withdraw` function.
        address maliciousStrategist = vm.addr(10);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(
            CollateralFTokenAdaptor.withdraw.selector,
            100_000e18,
            maliciousStrategist,
            abi.encode(CRV_FRAX_PAIR, CRV),
            abi.encode(0)
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptorV1), callData: adaptorCalls });
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
        bool
    ) internal view virtual returns (uint256) {
        return _fraxlendPair.toBorrowAmount(_shares, _roundUp);
    }
}
