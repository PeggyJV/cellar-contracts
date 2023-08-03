// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// Import Adaptors
import { CollateralFTokenAdaptorV2 } from "src/modules/adaptors/Frax/CollateralFTokenAdaptorV2.sol";
import { DebtFTokenAdaptorV2 } from "src/modules/adaptors/Frax/DebtFTokenAdaptorV2.sol";
// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// bespoke interface to access collateralBalancer getter.
interface ICollateralFToken {
    function userCollateralBalance(address _user) external;
}

/**
 * @notice test provision of collateral and borrowing on Fraxlend
 * @author 0xEinCodes, crispymangoes
 * NOTE: Initial tests revolve around providing MKR as collateral and borrowing FRAX. This fraxlend pair was used because it is a Fraxlend v2 pair.
 * TODO: write v1 tests w/ WETH.
 */
contract CellarFraxLendCollateralAndDebtTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    CollateralFTokenAdaptorV2 public fraxlendCollateralTokenAdaptor;
    DebtFTokenAdaptorV2 public fraxlendDebtTokenAdaptor;
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

    uint32 private fraxPosition = 1;
    uint32 private mkrPosition = 2;
    uint32 private wethPosition = 3;
    // uint32 private sfrxETHPosition = 4;

    // uint32 private fxsFraxPairPosition = 2;
    // uint32 private fpiFraxPairPosition = 3;
    // uint32 private sfrxEthFraxPairPosition = 4;
    // uint32 private wEthFraxPairPosition = 5;

    // Mock Positions
    uint32 private mockFxsFraxPairPosition = 6;
    uint32 private mockSfrxEthFraxPairPosition = 7;

    uint256 initialAssets;
    uint256 maxLTV = 0.5e18;

    ICollateralFToken mkrCollateralFToken = ICollateralFToken(address(MKR_FRAX_PAIR));

    function setUp() public {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockFraxUsd = new MockDataFeed(FRAX_USD_FEED);
        mockMkrUsd = new MockDataFeed(MKR_USD_FEED);
        mockWethUsd = new MockDataFeed(WETH_USD_FEED);

        // mockFTokenAdaptorV2 = new MockFTokenAdaptor(false, address(FRAX));
        // mockFTokenAdaptor = new MockFTokenAdaptorV1(false, address(FRAX));

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CollateralFTokenAdaptorV2).creationCode;
        constructorArgs = abi.encode(address(FRAX), maxLTV);
        collateralFTokenAdaptorV2 = CollateralFTokenAdaptorV2(
            deployer.deployContract("FraxLend Collateral fToken Adaptor V 0.1", creationCode, constructorArgs, 0)
        );

        creationCode = type(DebtFTokenAdaptorV2).creationCode;
        constructorArgs = abi.encode(true, address(FRAX), maxLTV);
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

        // uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        // settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        // priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(collateralFTokenAdaptorV2));
        registry.trustAdaptor(address(debtFTokenAdaptorV2));

        registry.trustPosition(fraxPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(mkrPosition, address(erc20Adaptor), abi.encode(MKR));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        // registry.trustPosition(sfrxETHPosition, address(erc20Adaptor), abi.encode());
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
            fraxlendDebtAPEPosition,
            address(collateralFTokenAdaptorV2),
            abi.encode(APE_FRAX_PAIR, address(APE))
        );
        registry.trustPosition(
            fraxlendDebtAPEPosition,
            address(debtFTokenAdaptorV2),
            abi.encode(address(MKR_FRAX_PAIR))
        );

        uint256 maxLTV = e18;

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
            fraxlendCollateralMKRPosition,
            abi.encode(MKR_FRAX_PAIR, MKR),
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(collateralFTokenAdaptorV2));
        cellar.addAdaptorToCatalogue(address(debtFTokenAdaptorV2));
        // TODO: add V1 adaptors

        cellar.addPositionToCatalogue(mkrPosition);
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(fraxlendCollateralMKRPosition);
        cellar.addPositionTocatalogue(fraxlendDebtMKRPosition);

        cellar.addPosition(1, mkrPosition, abi.encode(0), false);
        cellar.addPosition(2, wethPosition, abi.encode(0), false);
        cellar.addPosition(3, fraxlendCollateralMKRPosition, abi.encode(0), false);
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
        uint256 initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair
        assertApproxEqAbs(MKR.balanceOf(), 0, 1, "Assets should not be within Cellar.");

        bytes memory adaptorData = abi.encode(MKR_FRAX_PAIR, MKR);
        assertApproxEqAbs(
            collateralFTokenAdaptorV2.balanceOf(adaptorData),
            assets + initialAssets,
            1,
            "Assets should be collateral provided to Fraxlend Pair."
        );

        // TODO: decide to use this assert or the above one. This one reads directly from the fraxlendpair in the test, the other goes off the Adaptor balanceOf(). There should be specific tests for balanceOf() elsewhere, so we can use it in our tests.
        assertApproxEqAbs(
            mkrCollateralFToken.userCollateralBalance(address(cellar)),
            assets + initialAssets,
            1,
            "Assets should be collateral provided to Fraxlend Pair."
        );
    }

    // deposit into cellar - provide collateral, withdraw collateral --> should get all back.
    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this));

        deal(address(MKR), address(this), 0);
        uint256 amountToWithdraw = cellar.maxWithdraw(address(this)) - 1; // -1 accounts for rounding errors when supplying liquidity to aTokens.
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        assertEq(MKR.balanceOf(address(this)), amountToWithdraw, "Amount withdrawn should equal callers MKR balance.");
    }

    function testTotalAssets(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        uint256 initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair

        assertApproxEqAbs(
            cellar.totalAssets(),
            (assets + initialAssets),
            1,
            "Total assets should equal assets deposited."
        );
    }

    // test taking loans w/ v2 fraxlend pairs
    function testTakingOutLoansV2(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        uint256 initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair

        // Take out a FRAX loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, assets / 2); //TODO: this will be interesting cause LTV maximums, etc.

        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        bytes memory adaptorData = abi.encode(MKR_FRAX_PAIR);
        assertApproxEqAbs(
            debtFTokenAdaptorV2.balanceOf(adaptorData),
            assets / 2,
            1,
            "Cellar should have debt recorded within Fraxlend Pair of assets / 2"
        );
        assertApproxEqAbs(
            FRAX.balanceOf(address(cellar)),
            assets / 2,
            1,
            "Cellar should have FRAX equal to assets / 2"
        );
    }

    // test taking loan w/ providing collateral to the wrong pair
    function testTakingOutLoanInUntrackedPositionV2() external {
        assets = bound(assets, 0.1e18, 100_000e18);
        uint256 initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair

        // Take out a FRAX loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(APE_FRAX_PAIR, assets / 2); //TODO: this will be interesting cause LTV maximums, etc.

        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });

        // TODO: EIN - I anticipate a reversion from the fraxlend side since the position is trusted but we do not have any collateral in that pair specifically.

        cellar.callOnAdaptor(data);
    }

    // TODO: not sure how this one would apply with Fraxlend Pairs
    function testTakingOutLoansInUntrackedPositionV2() external {}

    function testRepayingLoans(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        uint256 initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair

        // Take out a FRAX loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, assets / 2); //TODO: this will be interesting cause LTV maximums, etc.

        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        bytes memory adaptorData = abi.encode(MKR_FRAX_PAIR);
        assertApproxEqAbs(
            debtFTokenAdaptorV2.balanceOf(adaptorData),
            assets / 2,
            1,
            "Cellar should have debt recorded within Fraxlend Pair of assets / 2"
        );
        assertApproxEqAbs(
            FRAX.balanceOf(address(cellar)),
            assets / 2,
            1,
            "Cellar should have FRAX equal to assets / 2"
        );

        uint256 cellarBorrowShares = mkrFraxLendPair.userBorrowShares(address(cellar)); // TODO: double check this works

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(MKR_FRAX_PAIR, FRAX, assets / 2, cellarBorrowShares);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        bytes memory adaptorData = abi.encode(MKR_FRAX_PAIR);

        // TODO: there may be interest if a block moved forward I guess which would need to be accounted for below
        assertApproxEqAbs(
            debtFTokenAdaptorV2.balanceOf(adaptorData),
            0,
            1,
            "Cellar should have zero debt recorded within Fraxlend Pair"
        );
        assertApproxEqAbs(FRAX.balanceOf(address(cellar)), 0, 1, "Cellar should have zero debtAsset");
    }

    // TODO: is this testing the withdrawableFrom() associated to the creditPosition? Cause the debtPosition should just revert.
    // Test implementation below is still from AAVE.t.sol
    function testWithdrawableFromaV2USDC() external {
        // uint256 assets = 100e6;
        // deal(address(USDC), address(this), assets);
        // cellar.deposit(assets, address(this));
        // // Take out a USDC loan.
        // Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // bytes[] memory adaptorCalls = new bytes[](1);
        // adaptorCalls[0] = _createBytesDataToBorrowFromAaveV2(dV2USDC, assets / 2);
        // data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        // cellar.callOnAdaptor(data);
        // uint256 maxAssets = cellar.maxWithdraw(address(this));
        // cellar.withdraw(maxAssets, address(this), address(this));
        // assertEq(USDC.balanceOf(address(this)), maxAssets, "Should have withdraw max assets possible.");
        // maxAssets = cellar.maxWithdraw(address(this));
        // cellar.withdraw(maxAssets, address(this), address(this));
        // assertEq(
        //     cellar.totalAssetsWithdrawable(),
        //     0,
        //     "Cellar should have remaining assets locked until strategist rebalances."
        // );
    }

    // TODO: EIN - review with Crispy relevance for Fraxlend tests
    // Test implementation below is still from AAVE.t.sol
    function testWithdrawableFromaV2WETH() external {
        // // First adjust cellar to work primarily with WETH.
        // // Make vanilla USDC the holding position.
        // cellar.swapPositions(0, 1, false);
        // cellar.setHoldingPosition(usdcPosition);
        // // Adjust rebalance deviation so we can swap full amount of USDC for WETH.
        // cellar.setRebalanceDeviation(0.003e18);
        // // Add WETH, aV2WETH, and dV2WETH as trusted positions to the registry.
        // uint32 wethPosition = 2;
        // registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        // uint32 aV2WETHPosition = 1_000_003;
        // registry.trustPosition(aV2WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV2WETH)));
        // uint32 debtWETHPosition = 1_000_004;
        // registry.trustPosition(debtWETHPosition, address(aaveDebtTokenAdaptor), abi.encode(address(dV2WETH)));
        // cellar.addPositionToCatalogue(wethPosition);
        // cellar.addPositionToCatalogue(aV2WETHPosition);
        // cellar.addPositionToCatalogue(debtWETHPosition);
        // // Pull USDC out of Aave.
        // Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // {
        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV2(USDC, type(uint256).max);
        //     data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        // }
        // cellar.callOnAdaptor(data);
        // // Remove dV2USDC and aV2USDC positions.
        // cellar.removePosition(1, false);
        // cellar.removePosition(0, true);
        // cellar.addPosition(1, aV2WETHPosition, abi.encode(1.1e18), false);
        // cellar.addPosition(0, debtWETHPosition, abi.encode(0), true);
        // cellar.addPosition(2, wethPosition, abi.encode(0), false);
        // // Deposit into the cellar.
        // uint256 assets = 10_000e6 + cellar.totalAssets();
        // deal(address(USDC), address(this), assets);
        // cellar.deposit(assets, address(this));
        // // Perform several adaptor calls.
        // // - Swap all USDC for WETH.
        // // - Deposit all WETH into Aave.
        // // - Take out a WETH loan on Aave.
        // data = new Cellar.AdaptorCall[](3);
        // bytes[] memory adaptorCallsForFirstAdaptor = new bytes[](1);
        // adaptorCallsForFirstAdaptor[0] = _createBytesDataForSwapWithUniv3(USDC, WETH, 500, assets);
        // data[0] = Cellar.AdaptorCall({
        //     adaptor: address(swapWithUniswapAdaptor),
        //     callData: adaptorCallsForFirstAdaptor
        // });
        // bytes[] memory adaptorCallsForSecondAdaptor = new bytes[](1);
        // adaptorCallsForSecondAdaptor[0] = _createBytesDataToLendOnAaveV2(WETH, type(uint256).max);
        // data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsForSecondAdaptor });
        // // Figure out roughly how much WETH the cellar has on Aave.
        // uint256 approxWETHCollateral = priceRouter.getValue(USDC, assets, WETH);
        // bytes[] memory adaptorCallsForThirdAdaptor = new bytes[](1);
        // adaptorCallsForThirdAdaptor[0] = _createBytesDataToBorrowFromAaveV2(dV2WETH, approxWETHCollateral / 2);
        // data[2] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCallsForThirdAdaptor });
        // cellar.callOnAdaptor(data);
        // uint256 maxAssets = cellar.maxWithdraw(address(this));
        // cellar.withdraw(maxAssets, address(this), address(this));
        // assertEq(
        //     cellar.totalAssetsWithdrawable(),
        //     0,
        //     "Cellar should have remaining assets locked until strategist rebalances."
        // );
    }

    // okay just seeing if we can handle multiple fraxlend positions
    // tests adding new positions too for new markets I guess
    function testMultipleATokensAndDebtTokens() external {
        cellar.setRebalanceDeviation(0.004e18); // TODO: double check why setting rebalanceDeviation is needed

        // Add new assets related to new fraxlendMarket; UNI_FRAX
        uint32 uniPosition = 1_000_006;
        registry.trustPosition(uniPosition, address(erc20Adaptor), abi.encode(UNI));

        mockUniEth = new MockDataFeed(UNI_ETH_FEED);
        price = uint256(mockUniEth.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUniEth));
        priceRouter.addAsset(UNI, settings, abi.encode(stor), price);

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
        cellar.addPositionToCatalogue(fraxlendCollateralUNIPosition);
        cellar.addPositionToCatalogue(fraxlendDebtUNIPosition);
        cellar.addPosition(4, fraxlendCollateralUNIPosition, abi.encode(0), false);
        cellar.addPosition(1, fraxlendDebtUNIPosition, abi.encode(0), true);

        // multiple adaptor calls
        // deposit MKR
        // borrow FRAX
        // deposit UNI
        // borrow FRAX
        assets = 100_000e18;
        // uint256 initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        deal(address(UNI), address(cellar), assets);

        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1); // collateralAdaptor, MKR already deposited due to cellar holding position
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](2); // debtAdaptor
        adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralWithFraxlendV2(UNI_FRAX_PAIR, assets);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowWithFraxlendV2(MKR_FRAX_PAIR, assets / 2);
        adaptorCallsSecondAdaptor[1] = _createBytesDataToBorrowWithFraxlendV2(UNI_FRAX_PAIR, assets / 2);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(collateralFTokenAdaptorV2),
            callData: adaptorCallsFirstAdaptor
        });
        data[1] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCallsSecondAdaptor });
        cellar.callOnAdaptor(data);

        // TODO: checks showing that we have:
        // 1. Check that we have the right amount of FRAX borrowed, the right amount of Collateral provided, the right LTV per position.

        // TODO: carry out a repayment for one of the positions
        // TODO: check that the repayment resulted in only one of the pairs LTV being improved.
        // TODO: check cellar generic checks (totalAssets, withdrawableFrom, etc.)

        uint256 maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));
    }

    // This check stops strategists from taking on any debt in positions they do not set up properly.
    // This stops the attack vector or strategists opening up an untracked debt position then depositing the funds into a vesting contract.
    function testTakingOutLoanInUntrackedPosition() external {
        cellar.setRebalanceDeviation(0.004e18); // TODO: double check why setting rebalanceDeviation is needed

        // Add new assets related to new fraxlendMarket; UNI_FRAX
        uint32 uniPosition = 1_000_006;
        registry.trustPosition(uniPosition, address(erc20Adaptor), abi.encode(UNI));

        mockUniEth = new MockDataFeed(UNI_ETH_FEED);
        price = uint256(mockUniEth.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUniEth));
        priceRouter.addAsset(UNI, settings, abi.encode(stor), price);

        uint32 fraxlendCollateralUNIPosition = 1_000_007; // fralendV2
        registry.trustPosition(
            fraxlendCollateralUNIPosition,
            address(collateralFTokenAdaptorV2),
            abi.encode(UNI_FRAX_PAIR, address(UNI))
        );
        // purposely do not trust a fraxlendDebtUNIPosition
        cellar.addPositionToCatalogue(fraxlendCollateralUNIPosition);
        cellar.addPosition(4, fraxlendCollateralUNIPosition, abi.encode(0), false);

        assets = 100_000e18;
        deal(address(UNI), address(cellar), assets);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1); // collateralAdaptor
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](1); // debtAdaptor
        adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralWithFraxlendV2(UNI_FRAX_PAIR, assets);
        adaptorCallsSecondAdaptor[1] = _createBytesDataToBorrowWithFraxlendV2(UNI_FRAX_PAIR, assets / 2);
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

    function testRepayingDebtThatIsNotOwed() external {
        assets = 100_000e18;
        // uint256 initialAssets = cellar.totalAssets();
        deal(address(MKR), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRepayWithFraxlendV2(MKR_FRAX_PAIR, FRAX, assets / 2, cellarBorrowShares);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptorV2), callData: adaptorCalls });
        // TODO: not sure what error to expect here, this was from AAVE tests: Error code 15: No debt of selected type.
        vm.expectRevert(bytes("15"));
        cellar.callOnAdaptor(data);
    }

    // externalReceiver triggers when doing Strategist Function calls via adaptorCall.
    // TODO: withdraw functionality requires implementation logic that respects a set max LTV.
    // Test logic has been written basically though.
    function testBlockExternalReceiver() external {
        // uint256 assets = 100_000e18;
        // deal(address(MKR), address(this), assets);
        // cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair
        // // Strategist tries to withdraw USDC to their own wallet using Adaptor's `withdraw` function.
        // address maliciousStrategist = vm.addr(10);
        // Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // bytes[] memory adaptorCalls = new bytes[](1);
        // adaptorCalls[0] = abi.encodeWithSelector(
        //     CollateralFTokenAdaptorV2.withdraw.selector,
        //     100_000e18,
        //     maliciousStrategist,
        //     abi.encode(MKR_FRAX_PAIR, MKR),
        //     abi.encode(0)
        // );
        // data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        // vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        // cellar.callOnAdaptor(data);
    }

    function testAddingPositionWithUnsupportedAssetsReverts() external {
        uint32 fraxlendCollateralUNIPosition = 1_000_006; // fralendV2
        // trust position fails because TUSD is not set up for pricing.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Registry.Registry__PositionPricingNotSetUp.selector, address(UNI)))
        );
        registry.trustPosition(
            fraxlendCollateralUNIPosition,
            address(collateralFTokenAdaptorV2),
            abi.encode(UNI_FRAX_PAIR, address(UNI))
        );
        // Add new assets related to new fraxlendMarket; UNI_FRAX
        uint32 uniPosition = 1_000_007;
        registry.trustPosition(uniPosition, address(erc20Adaptor), abi.encode(UNI));

        mockUniEth = new MockDataFeed(UNI_ETH_FEED);
        price = uint256(mockUniEth.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUniEth));
        priceRouter.addAsset(UNI, settings, abi.encode(stor), price);

        // trust position works now.
        registry.trustPosition(
            fraxlendCollateralUNIPosition,
            address(collateralFTokenAdaptorV2),
            abi.encode(UNI_FRAX_PAIR, address(UNI))
        );
    }

    // ========================================== INTEGRATION TEST ==========================================

    // TODO: Write integration test following similar pattern below except for flash loans.
    // Test implementation below is still from AAVE.t.sol
    function testIntegration() external {
        // // Manage positions to reflect the following
        // // 0) aV2USDC (holding)
        // // 1) aV2WETH
        // // 2) aV2WBTC
        // // Debt Position
        // // 0) dV2USDC
        // uint32 aV2WETHPosition = 1_000_003;
        // registry.trustPosition(aV2WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV2WETH)));
        // uint32 aV2WBTCPosition = 1_000_004;
        // registry.trustPosition(aV2WBTCPosition, address(aaveATokenAdaptor), abi.encode(address(aV2WBTC)));
        // cellar.addPositionToCatalogue(aV2WETHPosition);
        // cellar.addPositionToCatalogue(aV2WBTCPosition);
        // cellar.addPosition(1, aV2WETHPosition, abi.encode(0), false);
        // cellar.addPosition(2, aV2WBTCPosition, abi.encode(0), false);
        // cellar.removePosition(3, false);
        // // Have whale join the cellar with 1M USDC.
        // uint256 assets = 1_000_000e6;
        // address whale = vm.addr(777);
        // deal(address(USDC), whale, assets);
        // vm.startPrank(whale);
        // USDC.approve(address(cellar), assets);
        // cellar.deposit(assets, whale);
        // vm.stopPrank();
        // // Strategist manages cellar in order to achieve the following portfolio.
        // // ~20% in aV2USDC.
        // // ~40% Aave aV2WETH/dV2USDC with 2x LONG on WETH.
        // // ~40% Aave aV2WBTC/dV2USDC with 3x LONG on WBTC.
        // Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](5);
        // // Create data to withdraw USDC, swap for WETH and WBTC and lend them on Aave.
        // uint256 amountToSwap = assets.mulDivDown(8, 10);
        // {
        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV2(USDC, assets.mulDivDown(8, 10));
        //     data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        // }
        // {
        //     bytes[] memory adaptorCalls = new bytes[](2);
        //     adaptorCalls[0] = _createBytesDataForSwapWithUniv3(USDC, WETH, 500, amountToSwap);
        //     amountToSwap = priceRouter.getValue(USDC, amountToSwap / 2, WETH);
        //     adaptorCalls[1] = _createBytesDataForSwapWithUniv3(WETH, WBTC, 500, amountToSwap);
        //     data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        // }
        // {
        //     bytes[] memory adaptorCalls = new bytes[](2);
        //     adaptorCalls[0] = _createBytesDataToLendOnAaveV2(WETH, type(uint256).max);
        //     adaptorCalls[1] = _createBytesDataToLendOnAaveV2(WBTC, type(uint256).max);
        //     data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        // }
        // // Create data to flash loan USDC, sell it, and lend more WETH and WBTC on Aave.
        // {
        //     // Want to borrow 3x 40% of assets
        //     uint256 USDCtoFlashLoan = assets.mulDivDown(12, 10);
        //     // Borrow the flash loan amount + premium.
        //     uint256 USDCtoBorrow = USDCtoFlashLoan.mulDivDown(1e3 + pool.FLASHLOAN_PREMIUM_TOTAL(), 1e3);
        //     bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
        //     Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](3);
        //     bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](2);
        //     bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](2);
        //     bytes[] memory adaptorCallsInsideFlashLoanThirdAdaptor = new bytes[](1);
        //     // Swap USDC for WETH.
        //     adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataForSwapWithUniv3(
        //         USDC,
        //         WETH,
        //         500,
        //         USDCtoFlashLoan
        //     );
        //     // Swap USDC for WBTC.
        //     amountToSwap = priceRouter.getValue(USDC, USDCtoFlashLoan.mulDivDown(2, 3), WETH);
        //     adaptorCallsInsideFlashLoanFirstAdaptor[1] = _createBytesDataForSwapWithUniv3(
        //         WETH,
        //         WBTC,
        //         500,
        //         amountToSwap
        //     );
        //     // Lend USDC on Aave specifying to use the max amount available.
        //     adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToLendOnAaveV2(WETH, type(uint256).max);
        //     adaptorCallsInsideFlashLoanSecondAdaptor[1] = _createBytesDataToLendOnAaveV2(WBTC, type(uint256).max);
        //     adaptorCallsInsideFlashLoanThirdAdaptor[0] = _createBytesDataToBorrowFromAaveV2(dV2USDC, USDCtoBorrow);
        //     dataInsideFlashLoan[0] = Cellar.AdaptorCall({
        //         adaptor: address(swapWithUniswapAdaptor),
        //         callData: adaptorCallsInsideFlashLoanFirstAdaptor
        //     });
        //     dataInsideFlashLoan[1] = Cellar.AdaptorCall({
        //         adaptor: address(aaveATokenAdaptor),
        //         callData: adaptorCallsInsideFlashLoanSecondAdaptor
        //     });
        //     dataInsideFlashLoan[2] = Cellar.AdaptorCall({
        //         adaptor: address(aaveDebtTokenAdaptor),
        //         callData: adaptorCallsInsideFlashLoanThirdAdaptor
        //     });
        //     address[] memory loanToken = new address[](1);
        //     loanToken[0] = address(USDC);
        //     uint256[] memory loanAmount = new uint256[](1);
        //     loanAmount[0] = USDCtoFlashLoan;
        //     adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoanFromAaveV2(
        //         loanToken,
        //         loanAmount,
        //         abi.encode(dataInsideFlashLoan)
        //     );
        //     data[3] = Cellar.AdaptorCall({
        //         adaptor: address(aaveDebtTokenAdaptor),
        //         callData: adaptorCallsForFlashLoan
        //     });
        // }
        // // Create data to lend remaining USDC on Aave.
        // {
        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataToLendOnAaveV2(USDC, type(uint256).max);
        //     data[4] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        // }
        // // Adjust rebalance deviation to account for slippage and fees(swap and flash loan).
        // cellar.setRebalanceDeviation(0.03e18);
        // cellar.callOnAdaptor(data);
        // assertLt(cellar.totalAssetsWithdrawable(), assets, "Assets withdrawable should be less than assets.");
        // // Whale withdraws as much as they can.
        // vm.startPrank(whale);
        // uint256 assetsToWithdraw = cellar.maxWithdraw(whale);
        // cellar.withdraw(assetsToWithdraw, whale, whale);
        // vm.stopPrank();
        // assertEq(USDC.balanceOf(whale), assetsToWithdraw, "Amount withdrawn should equal maxWithdraw for Whale.");
        // // Other user joins.
        // assets = 100_000e6;
        // address user = vm.addr(777);
        // deal(address(USDC), user, assets);
        // vm.startPrank(user);
        // USDC.approve(address(cellar), assets);
        // cellar.deposit(assets, user);
        // vm.stopPrank();
        // assertApproxEqAbs(
        //     cellar.totalAssetsWithdrawable(),
        //     assets,
        //     1,
        //     "Total assets withdrawable should equal user deposit."
        // );
        // // Whale withdraws as much as they can.
        // vm.startPrank(whale);
        // assetsToWithdraw = cellar.maxWithdraw(whale);
        // cellar.withdraw(assetsToWithdraw, whale, whale);
        // vm.stopPrank();
        // // Strategist must unwind strategy before any more withdraws can be made.
        // assertEq(cellar.totalAssetsWithdrawable(), 0, "There should be no more assets withdrawable.");
        // // Strategist is more Bullish on WBTC than WETH, so they unwind the WETH position and keep the WBTC position.
        // data = new Cellar.AdaptorCall[](2);
        // {
        //     uint256 cellarAV2WETH = aV2WETH.balanceOf(address(cellar));
        //     // By lowering the USDC flash loan amount, we free up more aV2USDC for withdraw, but lower the health factor
        //     uint256 USDCtoFlashLoan = priceRouter.getValue(WETH, cellarAV2WETH, USDC).mulDivDown(8, 10);
        //     bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
        //     Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](3);
        //     bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](1);
        //     bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](1);
        //     bytes[] memory adaptorCallsInsideFlashLoanThirdAdaptor = new bytes[](1);
        //     // Repay USDC debt.
        //     adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataToRepayToAaveV2(USDC, USDCtoFlashLoan);
        //     // Withdraw WETH and swap for USDC.
        //     adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToWithdrawFromAaveV2(WETH, cellarAV2WETH);
        //     adaptorCallsInsideFlashLoanThirdAdaptor[0] = _createBytesDataForSwapWithUniv3(
        //         WETH,
        //         USDC,
        //         500,
        //         cellarAV2WETH
        //     );
        //     dataInsideFlashLoan[0] = Cellar.AdaptorCall({
        //         adaptor: address(aaveDebtTokenAdaptor),
        //         callData: adaptorCallsInsideFlashLoanFirstAdaptor
        //     });
        //     dataInsideFlashLoan[1] = Cellar.AdaptorCall({
        //         adaptor: address(aaveATokenAdaptor),
        //         callData: adaptorCallsInsideFlashLoanSecondAdaptor
        //     });
        //     dataInsideFlashLoan[2] = Cellar.AdaptorCall({
        //         adaptor: address(swapWithUniswapAdaptor),
        //         callData: adaptorCallsInsideFlashLoanThirdAdaptor
        //     });
        //     address[] memory loanToken = new address[](1);
        //     loanToken[0] = address(USDC);
        //     uint256[] memory loanAmount = new uint256[](1);
        //     loanAmount[0] = USDCtoFlashLoan;
        //     adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoanFromAaveV2(
        //         loanToken,
        //         loanAmount,
        //         abi.encode(dataInsideFlashLoan)
        //     );
        //     data[0] = Cellar.AdaptorCall({
        //         adaptor: address(aaveDebtTokenAdaptor),
        //         callData: adaptorCallsForFlashLoan
        //     });
        // }
        // // Create data to lend remaining USDC on Aave.
        // {
        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataToLendOnAaveV2(USDC, type(uint256).max);
        //     data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        // }
        // cellar.callOnAdaptor(data);
        // assertGt(
        //     cellar.totalAssetsWithdrawable(),
        //     100_000e6,
        //     "There should a significant amount of assets withdrawable."
        // );
    }
}
