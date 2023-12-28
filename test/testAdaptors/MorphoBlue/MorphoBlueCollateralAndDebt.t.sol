// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import "test/resources/MainnetStarter.t.sol";
import { MorphoBlueDebtAdaptor } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueDebtAdaptor.sol";
import { MorphoBlueHealthFactorLogic } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueHealthFactorLogic.sol";
import { MorphoBlueCollateralAdaptor } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueCollateralAdaptor.sol";
import { MorphoBlueSupplyAdaptor } from "src/modules/adaptors/Morpho/MorphoBlue/MorphoBlueSupplyAdaptor.sol";
import { IMorpho, MarketParams, Id } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { Morpho } from "test/testAdaptors/MorphoBlue/Morpho.sol";

/**
 * @notice Test provision of collateral and borrowing on MorphoBlue Markets
 * @author 0xEinCodes, crispymangoes
 * TODO setup test for supplyAdaptor in its own test file
 */
contract MorphoBlueCollateralAndDebtTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    type Id is bytes32;

    MorphoBlueCollateralAdaptor public morphoBlueCollateralAdaptor;
    MorphoBlueDebtAdaptor public morphoBlueDebtAdaptor;
    MorphoBlueSupplyAdaptor public morphoBlueSupplyAdaptor;

    Cellar public cellar;

    uint32 public morphoBlueSupplyWETHPosition = 1_000_001;
    uint32 public morphoBlueCollateralWETHPosition = 1_000_002;
    uint32 public morphoBlueDebtWETHPosition = 1_000_003;
    uint32 public morphoBlueSupplyUSDCPosition = 1_000_004;
    uint32 public morphoBlueCollateralUSDCPosition = 1_000_005;
    uint32 public morphoBlueDebtUSDCPosition = 1_000_006;
    uint32 public morphoBlueSupplyWBTCPosition = 1_000_007;
    uint32 public morphoBlueCollateralWBTCPosition = 1_000_008;
    uint32 public morphoBlueDebtWBTCPosition = 1_000_009;

    // adaptorData for above positions
    Id wethMarketId = bytes(1); // TODO - placeholder, need actual id for morpho blue market we are working with.
    Id usdcMarketId = bytes(2); // TODO - placeholder, need actual id for morpho blue market we are working with.
    Id wbtcMarketId = bytes(3); // TODO - placeholder, need actual id for morpho blue market we are working with.

    // Chainlink PriceFeeds
    MockDataFeed private mockWethUsd;
    MockDataFeed private mockUsdcUsd;
    MockDataFeed private mockWbtcUsd;

    uint32 private wethPosition = 1;
    uint32 private usdcPosition = 2;
    uint32 private wbtcPosition = 3;

    uint256 initialAssets;
    uint256 minHealthFactor = 1.05e18;

    IMorpho public morphoBlue;

    bool ACCOUNT_FOR_INTEREST = true;

    function setUp() public {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18877807; //  TODO - might have to test with specific blocknumber

        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockUsdcUsd = new MockDataFeed(USDC_USD_FEED);
        mockWbtcUsd = new MockDataFeed(WBTC_USD_FEED);
        mockWethUsd = new MockDataFeed(WETH_USD_FEED);

        bytes memory creationCode;
        bytes memory constructorArgs;

        // deploy test morpho blue since it is not live in prod yet. TODO - confirm that this works or if there is some other test deployment elsewhere
        creationCode = type(Morpho).creationCode;
        constructorArgs = abi.encode(address(this));
        morphoBlue = Morpho(deployer.deployContract("Morpho Blue TEST V 0.0", creationCode, constructorArgs, 0)); // TODO - testMorphoBlue is set to be not payable for now.

        creationCode = type(MorphoBlueCollateralAdaptor).creationCode;
        constructorArgs = abi.encode(address(morphoBlue), minHealthFactor);
        morphoBlueCollateralAdaptor = MorphoBlueCollateralAdaptor(
            deployer.deployContract("Morpho Blue Collateral Adaptor V 0.0", creationCode, constructorArgs, 0)
        );

        creationCode = type(MorphoBlueDebtAdaptor).creationCode;
        constructorArgs = abi.encode(ACCOUNT_FOR_INTEREST, address(morphoBlue), minHealthFactor);
        morphoBlueDebtAdaptor = MorphoBlueDebtAdaptor(
            deployer.deployContract("Morpho Blue Debt Adaptor V 0.0", creationCode, constructorArgs, 0)
        );

        creationCode = type(MorphoBlueSupplyAdaptor).creationCode;
        constructorArgs = abi.encode(ACCOUNT_FOR_INTEREST, address(morphoBlue));
        morphoBlueSupplyAdaptor = MorphoBlueSupplyAdaptor(
            deployer.deployContract("Morpho Blue Supply Adaptor V 0.0", creationCode, constructorArgs, 0)
        );

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        price = uint256(mockWethUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWethUsd));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        uint256 price = uint256(mockUsdcUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUsdcUsd));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(mockWbtcUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWbtcUsd));
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(morphoBlueCollateralAdaptor));
        registry.trustAdaptor(address(morphoBlueDebtAdaptor));
        registry.trustAdaptor(address(morphoBlueSupplyAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));

        registry.trustPosition(
            morphoBlueSupplyWETHPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(wethMarketId)
        );
        registry.trustPosition(
            morphoBlueCollateralWETHPosition,
            address(morphoBlueCollateralAdaptor),
            abi.encode(wethMarketId)
        );
        registry.trustPosition(morphoBlueDebtWETHPosition, address(morphoBlueDebtAdaptor), abi.encode(wethMarketId));
        registry.trustPosition(
            morphoBlueSupplyUSDCPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(usdcMarketId)
        );
        registry.trustPosition(
            morphoBlueCollateralUSDCPosition,
            address(morphoBlueCollateralAdaptor),
            abi.encode(usdcMarketId)
        );
        registry.trustPosition(morphoBlueDebtUSDCPosition, address(morphoBlueDebtAdaptor), abi.encode(usdcMarketId));
        registry.trustPosition(
            morphoBlueSupplyWBTCPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(wbtcMarketId)
        );
        registry.trustPosition(
            morphoBlueCollateralWBTCPosition,
            address(morphoBlueCollateralAdaptor),
            abi.encode(wbtcMarketId)
        );
        registry.trustPosition(morphoBlueDebtWBTCPosition, address(morphoBlueDebtAdaptor), abi.encode(wbtcMarketId));

        string memory cellarName = "Morpho Blue Collateral & Debt Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(WETH), address(this), initialDeposit);
        WETH.approve(cellarAddress, initialDeposit);

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

        cellar.addAdaptorToCatalogue(address(morphoBlueSupplyAdaptor));
        cellar.addAdaptorToCatalogue(address(morphoBlueCollateralAdaptor));
        cellar.addAdaptorToCatalogue(address(morphoBlueDebtAdaptor));

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPositionToCatalogue(wbtcPosition);

        // only add weth positions for now.
        cellar.addPositionToCatalogue(morphoBlueSupplyWETHPosition);
        cellar.addPositionToCatalogue(morphoBlueCollateralWETHPosition);
        cellar.addPositionToCatalogue(morphoBlueDebtWETHPosition);

        cellar.addPosition(1, usdcPosition, abi.encode(0), false);
        cellar.addPosition(2, wbtcPosition, abi.encode(0), false);
        cellar.addPosition(3, morphoBlueSupplyWETHPosition, abi.encode(0), false);
        cellar.addPosition(4, morphoBlueCollateralWETHPosition, abi.encode(0), false);

        cellar.addPosition(0, morphoBlueDebtWETHPosition, abi.encode(0), true);

        WETH.safeApprove(address(cellar), type(uint256).max);
        USDC.safeApprove(address(cellar), type(uint256).max);
        WBTC.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        // stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    // set up has a cellar w/ WETH erc20Position as holding position, and cellar positions (empty) for supply, and debt for morpho blue weth market.
    // cellar current initial assets = initial deposit using the deployer.
    // cellar balance for this test address is zero though.

    /// MorphoBlueCollateralAdaptor tests

    // test that holding position for adding collateral is being tracked properly and works upon user deposits
    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        console.log("Cellar WETH balance: %s, initialAssets: %s", WETH.balanceOf(address(cellar)), initialAssets);
        deal(address(WETH), address(this), assets);
        cellar.setHoldingPosition(morphoBlueCollateralWETHPosition);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            WETH.balanceOf(address(cellar)),
            initialAssets,
            1,
            "Cellar should have only initial assets, and have supplied the new asset amount as collateral"
        );
        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethMarketId, address(cellar)).collateral);

        assertEq(newCellarCollateralBalance, assets, "Assets should be collateral provided to Morpho Blue Market.");
    }

    // test adding collateral where holdingPosition is WETH erc20Position
    function testAddCollateral(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            WETH.balanceOf(address(cellar)),
            assets + initialAssets,
            1,
            "Cellar should have all deposited WETH assets"
        );

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        assertApproxEqAbs(
            WETH.balanceOf(address(cellar)),
            initialAssets,
            1,
            "Only initialAssets should be within Cellar."
        );

        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethMarketId, address(cellar)).collateral);
        assertEq(
            newCellarCollateralBalance,
            assets,
            "Assets (except initialAssets) should be collateral provided to Morpho Blue Market."
        );
    }

    // carry out a total assets test checking that balanceOf works for adaptors.
    function testTotalAssets(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(
            cellar.totalAssets(),
            (assets + initialAssets),
            1,
            "Adaptor totalAssets(): Total assets should equal initialAssets + assets."
        );

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            cellar.totalAssets(),
            (assets + initialAssets),
            1,
            "Adaptor totalAssets(): Total assets should not have changed."
        );
    }

    function testRemoveCollateral(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethMarketId, address(cellar)).collateral);

        assertEq(WETH.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(newCellarCollateralBalance, 0);
    }

    function testRemoveSomeCollateral(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethMarketId, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethMarketId, address(cellar)).collateral);

        assertEq(WETH.balanceOf(address(cellar)), (assets / 2) + initialAssets);
        assertApproxEqAbs(newCellarCollateralBalance, assets / 2, 1);
    }

    // test strategist input param for _collateralAmount to be type(uint256).max
    function testRemoveAllCollateralWithTypeUINT256Max(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethMarketId, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethMarketId, address(cellar)).collateral);

        assertEq(WETH.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(mkrFToken.userCollateralBalance(address(cellar)), 0);
    }

    // externalReceiver triggers when doing Strategist Function calls via adaptorCall within collateral adaptor.
    function testBlockExternalReceiver(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);
        deal(address(WETH), address(this), assets);
        cellar.setHoldingPosition(morphoBlueCollateralWETHPosition);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ WETH MorphoBlue weth:usdc market
        // Strategist tries to withdraw USDC to their own wallet using Adaptor's `withdraw` function.
        address maliciousStrategist = vm.addr(10);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(
            MorphoBlueCollateralAdaptor.withdraw.selector,
            100_000e18,
            maliciousStrategist,
            abi.encode(wethMarketId),
            abi.encode(0)
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        cellar.callOnAdaptor(data);
    }

    // TODO - test that it reverts with untracked positions
    // TODO - write test checking balanceOf() within morphoBlueCollateralAdaptor

    /// MorphoBlueDebtAdaptor tests

    // test taking loans w/ a morpho blue market
    function testTakingOutLoans(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        console.log("Cellar WETH balance: %s, initialAssets: %s", WETH.balanceOf(address(cellar)), initialAssets);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a loan
        uint256 borrowAmount = priceRouter.getValue(WETH, assets / 2, USDC); // TODO assumes that wethMarketId is a WETH:USDC market. Correct this if otherwise.
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethMarketId, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        bytes memory adaptorData = abi.encode(wethMarketId);

        vm.prank(address(cellar));
        uint256 newBalance = morphoBlueDebtAdaptor.balanceOf(adaptorData);
        assertApproxEqAbs(
            newBalance,
            borrowAmount,
            1,
            "Cellar should have debt recorded within Morpho Blue market equal to assets / 2"
        );
        assertApproxEqAbs(
            USDC.balanceOf(address(cellar)),
            borrowAmount,
            1,
            "Cellar should have borrow amount equal to assets / 2"
        );
    }

    // test taking loan w/ the wrong pair that we provided collateral to
    function testTakingOutLoanInUntrackedPositionV2(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100_000e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // try borrowing from the wrong market that is untracked by cellar
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(usdcMarketId, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoBlueDebtAdaptor.MorphoBlueDebtAdaptor__MarketPositionsMustBeTracked.selector,
                    usdcMarketId
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingLoans(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a loan
        uint256 borrowAmount = priceRouter.getValue(WETH, assets / 2, USDC); // TODO assumes that wethMarketId is a WETH:USDC market. Correct this if otherwise.
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethMarketId, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        bytes memory adaptorData = abi.encode(wethMarketId);

        vm.prank(address(cellar));

        // start repayment sequence - NOTE that the repay function in Morpho Blue calls accrue interest within it.
        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
        deal(address(USDC), address(cellar), borrowAmount * 2);

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayDebtToMorphoBlue(wethMarketId, maxAmountToRepay);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 newBalance = morphoBlueDebtAdaptor.balanceOf(adaptorData);

        assertApproxEqAbs(newBalance, 0, 1, "Cellar should have zero debt recorded within Morpho Blue Market");
        assertLt(USDC.balanceOf(address(cellar)), borrowAmount * 2, "Cellar should have zero debtAsset"); // TODO make this assert expect 0 USDC
    }

    // TODO - write test checking balanceOf() within morphoBlueDebtAdaptor

    function testRepayPartialDebt(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a loan
        uint256 borrowAmount = priceRouter.getValue(WETH, assets / 2, USDC); // TODO assumes that wethMarketId is a WETH:USDC market. Correct this if otherwise.
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethMarketId, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        bytes memory adaptorData = abi.encode(wethMarketId);

        vm.prank(address(cellar));

        uint256 debtBefore = morphoBlueDebtAdaptor.balanceOf(adaptorData);

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayDebtToMorphoBlue(wethMarketId, borrowAmount / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // start repayment sequence
        uint256 debtNow = morphoBlueDebtAdaptor.balanceOf(adaptorData);
        assertLt(debtNow, debtBefore);
        assertApproxEqAbs(
            USDC.balanceOf(address(cellar)),
            borrowAmount / 2,
            1e18,
            "Cellar should have approximately half debtAsset"
        );
    }

    // This check stops strategists from taking on any debt in positions they do not set up properly.
    // Try sending out adaptorCalls that has a call with an position that is unregistered within the cellar, should lead to a revert from the adaptor that is trusted.
    function testLoanInUntrackedPosition(uint256 assets) external {
        // purposely do not trust a debt position with WBTC with the cellar
        cellar.addPositionToCatalogue(morphoBlueCollateralWBTCPosition); // decimals is 8 for wbtc
        cellar.addPosition(5, morphoBlueCollateralWBTCPosition, abi.encode(0), false);
        assets = bound(assets, 0.1e8, 100e8);
        uint256 MBWbtcUsdcBorrowAmount = priceRouter.getValue(WBTC, assets / 2, USDC); // assume wbtcMarketId corresponds to a wbtc-usdc market on morpho blue

        deal(address(WBTC), address(cellar), assets);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1); // collateralAdaptor
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](1); // debtAdaptor
        adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralToMorphoBlue(wbtcMarketId, assets);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowFromMorphoBlue(wbtcMarketId, MBWbtcUsdcBorrowAmount);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(morphoBlueCollateralAdaptor),
            callData: adaptorCallsFirstAdaptor
        });
        data[1] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCallsSecondAdaptor });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoBlueDebtAdaptor.MorphoBlueDebtAdaptor__MarketPositionsMustBeTracked.selector,
                    wbtcMarketId
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // have strategist call repay function when no debt owed. Expect revert.
    // TODO - refine this as we see how morpho blue responds to attempts to repay debt positions that do not exist
    function testRepayingDebtThatIsNotOwed(uint256 assets) external {
        assets = bound(assets, 0.1e18, 100e18);
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        adaptorCalls[0] = _createBytesDataToRepayDebtToMorphoBlue(wethMarketId, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoBlueDebtAdaptor.MorphoBlueDebtAdaptor__CannotRepayNoDebt.selector,
                    wethMarketId
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    /// MorphoBlueDebtAdaptor AND MorphoBlueCollateralAdaptor tests

    // okay just seeing if we can handle multiple morpho blue positions
    // TODO: EIN - May hve to deal with similar error that was experienced with fraxlend adaptors: troubleshoot why wbtcUSDCToBorrow might have to be 1e18 right now
    function testMultipleMorphoBluePositions() external {
        uint256 assets = 1e18;

        // Add new assets positions to cellar
        cellar.addPositionToCatalogue(wbtcPosition);
        cellar.addPositionToCatalogue(morphoBlueCollateralWBTCPosition);
        cellar.addPositionToCatalogue(morphoBlueDebtWBTCPosition);
        cellar.addPosition(5, wbtcPosition, abi.encode(0), false);
        cellar.addPosition(6, morphoBlueCollateralWBTCPosition, abi.encode(0), false);
        cellar.addPosition(1, morphoBlueDebtWBTCPosition, abi.encode(0), true);

        cellar.setHoldingPosition(morphoBlueCollateralWETHPosition);

        // multiple adaptor calls
        // deposit WETH
        // borrow USDC from weth:usdc morpho blue market
        // deposit WBTC
        // borrow USDC from wbtc:usdc morpho blue market
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this)); // holding position == collateralPosition w/ MKR FraxlendPair

        uint256 wbtcAssets = assets.changeDecimals(18, 8);
        deal(address(WBTC), address(cellar), wbtcAssets);
        uint256 wethUSDCToBorrow = priceRouter.getValue(WETH, assets / 2, USDC);
        uint256 wbtcUSDCToBorrow = priceRouter.getValue(WBTC, wbtcAssets / 2, USDC);
        // uint256 wbtcUSDCToBorrow = 1e8; // NOTE - this test failed in fraxlend tests before and we had to resort to having the above line commented out and this line used instead.

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](2); // collateralAdaptor, MKR already deposited due to cellar holding position
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](2); // debtAdaptor
        adaptorCallsFirstAdaptor[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        adaptorCallsFirstAdaptor[1] = _createBytesDataToAddCollateralToMorphoBlue(wbtcMarketId, wbtcAssets);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrowFromMorphoBlue(wethMarketId, wethUSDCToBorrow);
        adaptorCallsSecondAdaptor[1] = _createBytesDataToBorrowFromMorphoBlue(wbtcMarketId, wbtcUSDCToBorrow);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(morphoBlueCollateralAdaptor),
            callData: adaptorCallsFirstAdaptor
        });
        data[1] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCallsSecondAdaptor });
        cellar.callOnAdaptor(data);

        // TODO - Check that we have the right amount of USDC borrowed (commented out stuff from fraxlend using fraxlend helpers)
        // assertApproxEqAbs(
        //     (getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar))) +
        //         getFraxlendDebtBalance(UNI_FRAX_PAIR, address(cellar)),
        //     mkrFraxToBorrow + uniFraxToBorrow,
        //     1
        // );

        // assertApproxEqAbs(FRAX.balanceOf(address(cellar)), mkrFraxToBorrow + uniFraxToBorrow, 1);

        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total USDC.
        deal(address(USDC), address(cellar), (wethUSDCToBorrow + wbtcUSDCToBorrow) * 2);

        // Repay the loan in one of the morpho blue markets
        Cellar.AdaptorCall[] memory newData2 = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls2 = new bytes[](1);
        adaptorCalls2[0] = _createBytesDataToRepayDebtToMorphoBlue(wethMarketId, maxAmountToRepay);
        newData2[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls2 });
        cellar.callOnAdaptor(newData2);

        // TODO - asserts (commented out stuff from fraxlend using fraxlend helpers)
        // assertApproxEqAbs(
        //     getFraxlendDebtBalance(MKR_FRAX_PAIR, address(cellar)),
        //     0,
        //     1,
        //     "Cellar should have zero debt recorded within Fraxlend Pair"
        // );

        // assertApproxEqAbs(
        //     getFraxlendDebtBalance(UNI_FRAX_PAIR, address(cellar)),
        //     uniFraxToBorrow,
        //     1,
        //     "Cellar should still have debt for UNI Fraxlend Pair"
        // );

        deal(address(WETH), address(cellar), 0);

        adaptorCalls2[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethMarketId, assets);
        newData2[0] = Cellar.AdaptorCall({ adaptor: address(collateralFTokenAdaptor), callData: adaptorCalls2 });
        cellar.callOnAdaptor(newData2);

        // Check that we no longer have any MKR in the collateralPosition
        assertEq(WETH.balanceOf(address(cellar)), assets);

        // have user withdraw from cellar
        cellar.withdraw(assets, address(this), address(this));
        assertEq(WETH.balanceOf(address(this)), assets);
    }

    // Test removal of collateral but with taking a loan out and repaying it in full first.
    function testRemoveCollateralWithTypeUINT256MaxAfterRepay(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a loan
        uint256 borrowAmount = priceRouter.getValue(WETH, assets / 2, USDC); // TODO assumes that wethMarketId is a WETH:USDC market. Correct this if otherwise.
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethMarketId, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        bytes memory adaptorData = abi.encode(wethMarketId);

        vm.prank(address(cellar));

        // start repayment sequence - NOTE that the repay function in Morpho Blue calls accrue interest within it.
        uint256 maxAmountToRepay = type(uint256).max; // set up repayment amount to be cellar's total FRAX.
        deal(address(USDC), address(cellar), borrowAmount * 2);

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayDebtToMorphoBlue(wethMarketId, maxAmountToRepay);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueDebtAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 newBalance = morphoBlueDebtAdaptor.balanceOf(adaptorData);

        assertApproxEqAbs(newBalance, 0, 1, "Cellar should have zero debt recorded within Morpho Blue Market");
        assertLt(USDC.balanceOf(address(cellar)), borrowAmount * 2, "Cellar should have zero debtAsset"); // TODO make this assert expect 0 USDC

        // no collateral interest or anything has accrued, should be able to withdraw everything and have nothing left in it.
        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethMarketId, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        uint256 newCellarCollateralBalance = uint256(morphoBlue.position(wethMarketId, address(cellar)).collateral);

        assertEq(WETH.balanceOf(address(cellar)), assets + initialAssets);
        assertEq(mkrFToken.userCollateralBalance(address(cellar)), 0);
    }

    // test attempting to removeCollateral() when the LTV would be too high as a result
    function testFailRemoveCollateralBecauseLTV(uint256 assets) external {
        assets = bound(assets, 1e18, 100e18);
        initialAssets = cellar.totalAssets();
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        // carry out a proper addCollateral() call
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToAddCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Take out a loan
        uint256 borrowAmount = priceRouter.getValue(WETH, assets / 2, USDC); // TODO assumes that wethMarketId is a WETH:USDC market. Correct this if otherwise.
        adaptorCalls[0] = _createBytesDataToBorrowFromMorphoBlue(wethMarketId, borrowAmount);
        data[0] = Cellar.AdaptorCall({ adaptor: address(debtFTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // try to removeCollateral but more than should be allowed
        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethMarketId, assets);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoBlueCollateralAdaptor.MorphoBlueCollateralAdaptor__HealthFactorTooLow.selector,
                    wethMarketId
                )
            )
        );
        cellar.callOnAdaptor(data);

        adaptorCalls[0] = _createBytesDataToRemoveCollateralToMorphoBlue(wethMarketId, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(morphoBlueCollateralAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    MorphoBlueCollateralAdaptor.MorphoBlueCollateralAdaptor__HealthFactorTooLow.selector,
                    wethMarketId
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // TODO - EIN THIS IS WHERE YOU LEFT OFF
    // function testLTV(uint256 assets) external {
    //     assets = bound(assets, 0.1e18, 100e18);
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
