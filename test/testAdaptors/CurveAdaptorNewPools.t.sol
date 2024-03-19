// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { CellarWithOracle } from "src/base/permutations/CellarWithOracle.sol";
import { MockCellarWithOracle } from "src/mocks/MockCellarWithOracle.sol";
import { CurveEMAExtension } from "src/modules/price-router/Extensions/Curve/CurveEMAExtension.sol";
import { CurveAdaptor, CurvePool, CurveGauge, CurveHelper } from "src/modules/adaptors/Curve/CurveAdaptor.sol";
import { Curve2PoolExtension } from "src/modules/price-router/Extensions/Curve/Curve2PoolExtension.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { RedstonePriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

// TODO remove the pools from crispy's tests
contract CurveAdaptorNewPoolsTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;
    using SafeTransferLib for address;

    CurveAdaptor private curveAdaptor;
    WstEthExtension private wstethExtension;
    CurveEMAExtension private curveEMAExtension;
    Curve2PoolExtension private curve2PoolExtension;
    RedstonePriceFeedExtension private redstonePriceFeedExtension;

    Cellar private cellar;

    MockDataFeed public mockWETHdataFeed;
    MockDataFeed public mockUSDCdataFeed;
    MockDataFeed public mockDAI_dataFeed;
    MockDataFeed public mockUSDTdataFeed;
    MockDataFeed public mockFRAXdataFeed;
    MockDataFeed public mockSTETdataFeed;
    MockDataFeed public mockRETHdataFeed;

    uint32 private usdcPosition = 1;
    uint32 private wethPosition = 2;

    // newer curve pool related positions
    uint32 private WeethPosition = 3;
    uint32 private RswethPosition = 4;
    uint32 private EzEthPosition = 5;
    uint32 private EethPosition = 6;
    uint32 private WeEthWethPoolPosition = 7;
    uint32 private WeethRswEthPoolPosition = 8;
    uint32 private EzEthWethPoolPosition = 9;
    uint32 private EethEthPoolPoolPosition = 10;

    uint32 private slippage = 0.9e4;
    uint256 public initialAssets;

    bool public attackCellar;
    bool public blockExternalReceiver;
    uint256 public slippageToCharge;
    address public slippageToken;

    uint8 public decimals;

    mapping(uint256 => bool) public isPositionUsed;

    // Variables were originally memory but changed to state, to prevent stack too deep errors.
    ERC20[] public coins = new ERC20[](2);
    ERC20[] tokens = new ERC20[](2);
    uint256[] balanceDelta = new uint256[](2);
    uint256[] orderedTokenAmounts = new uint256[](2);
    uint256 expectedValueOut;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19435907;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockWETHdataFeed = new MockDataFeed(WETH_USD_FEED);
        mockUSDCdataFeed = new MockDataFeed(USDC_USD_FEED);

        curveAdaptor = new CurveAdaptor(address(WETH), slippage);
        curveEMAExtension = new CurveEMAExtension(priceRouter, address(WETH), 18);
        curve2PoolExtension = new Curve2PoolExtension(priceRouter, address(WETH), 18);

        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        // Add WETH pricing.
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWETHdataFeed));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Set eETH to be 1:1 with wETH.
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(EETH, settings, abi.encode(stor), price);

        // Add USDC pricing.
        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUSDCdataFeed));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // NOTE - for rsweth && ezeth: below is mimicking workaround for these new assets that was done in RenzoStakingAdaptor.t.sol. We will need to find proper pricing resources for these.

        //  Set rsweth to be 1:1 with ETH.
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(RSWETH, settings, abi.encode(stor), price);

        // Set EZETH to be 1:1 with ETH.
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(EZETH, settings, abi.encode(stor), price);

        // add WEETH
        redstonePriceFeedExtension = new RedstonePriceFeedExtension(priceRouter);

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));
        RedstonePriceFeedExtension.ExtensionStorage memory rstor;
        rstor.dataFeedId = weethUsdDataFeedId;
        rstor.heartbeat = 1 days;
        rstor.redstoneAdapter = IRedstoneAdapter(weethAdapter);
        price = IRedstoneAdapter(weethAdapter).getValueForDataFeed(rstor.dataFeedId);
        priceRouter.addAsset(WEETH, settings, abi.encode(rstor), price);

        // WeEthWethPool
        // WeEthWethToken
        // WeEthWethGauge
        _add2PoolAssetToPriceRouter(WeEthWethPool, WeEthWethToken, true, 3_854e8, WETH, WEETH, false, true, 0, 10e4);

        // WeethRswEthPool
        // WeethRswEthToken
        // WeethRswEthGauge
        _add2PoolAssetToPriceRouter(
            WeethRswEthPool,
            WeethRswEthToken,
            true,
            3_965e8,
            WEETH,
            RSWETH,
            false,
            true,
            0,
            10e4
        );

        // EzEthWethPool
        // EzEthWethToken
        // EzEthWethGauge
        _add2PoolAssetToPriceRouter(EzEthWethPool, EzEthWethToken, true, 3_854e8, WETH, EZETH, false, true, 0, 10e4);

        // EethEthPool
        // EethEthToken
        _add2PoolAssetToPriceRouter(EethEthPool, EethEthToken, true, 3_854e8, WETH, EETH, false, true, 0, 10e4);

        // Add positions to registry.
        registry.trustAdaptor(address(curveAdaptor));

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(WeethPosition, address(erc20Adaptor), abi.encode(WEETH));
        registry.trustPosition(RswethPosition, address(erc20Adaptor), abi.encode(RSWETH));
        registry.trustPosition(EzEthPosition, address(erc20Adaptor), abi.encode(EZETH));
        registry.trustPosition(EethPosition, address(erc20Adaptor), abi.encode(EETH));

        // Below position should technically be illiquid bc the re-entrancy function doesnt actually check for
        // re-entrancy, but for the sake of not refactoring a large test, it has been left alone.
        // Does not check for re-entrancy.

        /// TODO - EIN double check this set up with Crispy --> trust new pools
        registry.trustPosition(
            WeEthWethPoolPosition,
            address(curveAdaptor),
            abi.encode(WeEthWethPool, WeEthWethToken, WeEthWethGauge, bytes4(keccak256(abi.encodePacked("D_oracle()"))))
        );
        registry.trustPosition(
            WeethRswEthPoolPosition,
            address(curveAdaptor),
            abi.encode(WeethRswEthPool, WeethRswEthToken, WeethRswEthGauge, CurvePool.withdraw_admin_fees.selector)
        );
        registry.trustPosition(
            EzEthWethPoolPosition,
            address(curveAdaptor),
            abi.encode(EzEthWethPool, EzEthWethToken, EzEthWethGauge, CurvePool.withdraw_admin_fees.selector)
        );

        // TODO - EIN - no gauge
        registry.trustPosition(
            EethEthPoolPoolPosition,
            address(curveAdaptor),
            abi.encode(EethEthPool, EethEthToken, address(0), CurvePool.withdraw_admin_fees.selector)
        );

        string memory cellarName = "Curve Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(USDC), address(this), initialDeposit);
        USDC.approve(cellarAddress, initialDeposit);

        bytes memory creationCode = type(MockCellarWithOracle).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(this),
            registry,
            USDC,
            cellarName,
            cellarName,
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut,
            type(uint192).max
        );
        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(curveAdaptor));

        USDC.safeApprove(address(cellar), type(uint256).max);

        for (uint32 i = 2; i < 11; ++i) cellar.addPositionToCatalogue(i);
        for (uint32 i = 2; i < 11; ++i) cellar.addPosition(0, i, abi.encode(true), false);

        cellar.setRebalanceDeviation(0.030e18);

        initialAssets = cellar.totalAssets();

        // Used so that this address can be used as a "cellar" and spoof the validation check in adaptor.
        isPositionUsed[0] = true;
    }

    // ========================================= HAPPY PATH TESTS =========================================

    // TODO - assess if we need to do this test too
    function testWithdrawLogic(uint256 assets) external {}

    /// TODO - EIN happy path dynamic array pool tests - unsure why

    // weethWeth
    function testManagingLiquidityInDynamicArrayPool0() external {
        // assets = bound(assets, 1e6, 1_000_000e6);
        uint256 assets = 1_000_000e6;
        _manageLiquidityIn2PoolDynamicArraysNoETH(
            assets,
            WeEthWethPool,
            WeEthWethToken,
            WeEthWethGauge,
            0.01e18,
            bytes4(keccak256(abi.encodePacked("D_oracle()")))
        );
    }

    // weethRsweth
    function testManagingLiquidityInDynamicArrayPool1() external {
        // assets = bound(assets, 1e6, 1_000_000e6);
        uint256 assets = 1e6;
        _manageLiquidityIn2PoolDynamicArraysNoETH(
            assets,
            WeethRswEthPool,
            WeethRswEthToken,
            WeethRswEthGauge,
            0.0005e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    // ezethWeth
    function testManagingLiquidityInDynamicArrayPool2() external {
        // assets = bound(assets, 1e6, 1_000_000e6);
        uint256 assets = 1e6;
        _manageLiquidityIn2PoolDynamicArraysNoETH(
            assets,
            EzEthWethPool,
            EzEthWethToken,
            EzEthWethGauge,
            0.0005e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    // eethEth
    function testManagingLiquidityInDynamicArrayPool3() external {
        // assets = bound(assets, 1e6, 1_000_000e6);
        uint256 assets = 1e6;

        // // NOTE: even though pool is named with eth, it is weth based!
        _manageLiquidityIn2PoolDynamicArraysNoETH(
            assets,
            EethEthPool,
            EethEthToken,
            address(0),
            0.0010e18,
            CurvePool.withdraw_admin_fees.selector
        );
    }

    // ========================================= Reverts =========================================

    // TODO - do we want to test this too?
    function testSlippageRevertsNoETH() external {}

    // TODO - do we want to test this too?
    function testSlippageRevertsWithETH() external {}

    // TODO - do we want to test this too?
    function testReentrancyProtection3() external {}
    // ========================================= Reverts =========================================

    // TODO - do we want to test this too?
    function testInteractingWithPositionThatIsNotUsed() external {}

    // TODO - assess if we need to do this test too
    function testMismatchedArrayLengths() external {}

    // TODO - assess if we need to do this test too
    function testUsingNormalFunctionsToInteractWithETHCurvePool() external {}

    // TODO - assess if we need to do this test too
    function testCellarMakingCallsToProxyFunctions() external {}

    // TODO - assess if we need to do this test too
    function testAddingCurvePositionsWithWeirdDecimals() external {}

    // TODO - assess if we need to do this test too
    function testRepeatingNativeEthTwiceInInputArray() external {}

    // TODO - assess if we need to do this test too
    function testHelperReentrancyLock() external {}

    // TODO - assess if we need to do this test too
    function testCellarWithoutOracleTryingToUseCurvePosition() external {}

    /// TODO - EIN non-happy path dynamic array pool tests

    function testNoSpecifiedEnum() external {
        // try calling strategist functions without specifying enum
    }

    // ========================================= Attacker Tests =========================================

    // TODO - assess if we need to do this test too
    function testMaliciousStrategistUsingWrongCoinsArray() external {}

    // ========================================= Helpers =========================================

    // // NOTE Some curve pools use 2 to indicate locked, and 3 to indicate unlocked, others use 1, and 0 respectively
    // // But ones that use 1 or 0, are just checking if the slot is truthy or not, so setting it to 2 should still trigger re-entrancy reverts.
    // function _verifyReentrancyProtectionWorks(
    //     address poolAddress,
    //     address lpToken,
    //     uint32 position,
    //     uint256 assets,
    //     bytes memory expectedRevert
    // ) internal {
    //     // Create a cellar that uses the curve token as the asset.
    //     cellar = _createCellarWithCurveLPAsAsset(position, lpToken);

    //     deal(lpToken, address(this), assets);
    //     ERC20(lpToken).safeApprove(address(cellar), assets);

    //     CurvePool pool = CurvePool(poolAddress);
    //     bytes32 slot0 = bytes32(uint256(0));

    //     // Get the original slot value;
    //     bytes32 originalValue = vm.load(address(pool), slot0);

    //     // Set lock slot to 2 to lock it. Then try to deposit while pool is "re-entered".
    //     vm.store(address(pool), slot0, bytes32(uint256(2)));

    //     if (expectedRevert.length > 0) {
    //         vm.expectRevert(expectedRevert);
    //     } else {
    //         vm.expectRevert();
    //     }
    //     cellar.deposit(assets, address(this));

    //     // Change lock back to unlocked state
    //     vm.store(address(pool), slot0, originalValue);

    //     // Deposit should work now.
    //     cellar.deposit(assets, address(this));

    //     // Set lock slot to 2 to lock it. Then try to withdraw while pool is "re-entered".
    //     vm.store(address(pool), slot0, bytes32(uint256(2)));
    //     if (expectedRevert.length > 0) {
    //         vm.expectRevert(expectedRevert);
    //     } else {
    //         vm.expectRevert();
    //     }
    //     cellar.withdraw(assets / 2, address(this), address(this));

    //     // Change lock back to unlocked state
    //     vm.store(address(pool), slot0, originalValue);

    //     // Withdraw should work now.
    //     cellar.withdraw(assets / 2, address(this), address(this));
    // }

    // function _createCellarWithCurveLPAsAsset(uint32 position, address lpToken) internal returns (Cellar newCellar) {
    //     string memory cellarName = "Test Curve Cellar V0.0";
    //     uint256 initialDeposit = 1e6;
    //     uint64 platformCut = 0.75e18;

    //     ERC20 erc20LpToken = ERC20(lpToken);

    //     // Approve new cellar to spend assets.
    //     address cellarAddress = deployer.getAddress(cellarName);
    //     deal(lpToken, address(this), initialDeposit);
    //     erc20LpToken.approve(cellarAddress, initialDeposit);

    //     bytes memory creationCode = type(MockCellarWithOracle).creationCode;
    //     bytes memory constructorArgs = abi.encode(
    //         address(this),
    //         registry,
    //         erc20LpToken,
    //         cellarName,
    //         cellarName,
    //         position,
    //         abi.encode(true),
    //         initialDeposit,
    //         platformCut,
    //         type(uint192).max
    //     );
    //     newCellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

    //     newCellar.addAdaptorToCatalogue(address(curveAdaptor));
    // }

    // function _curveLPAsAccountingAsset(uint256 assets, ERC20 token, uint32 positionId, address gauge) internal {
    //     string memory cellarName = "Curve LP Cellar V0.0";
    //     // Approve new cellar to spend assets.
    //     initialAssets = 1e18;
    //     address cellarAddress = deployer.getAddress(cellarName);
    //     deal(address(token), address(this), initialAssets);
    //     token.approve(cellarAddress, initialAssets);

    //     bytes memory creationCode = type(MockCellarWithOracle).creationCode;
    //     bytes memory constructorArgs = abi.encode(
    //         address(this),
    //         registry,
    //         token,
    //         cellarName,
    //         cellarName,
    //         positionId,
    //         abi.encode(true),
    //         initialAssets,
    //         0.75e18,
    //         type(uint192).max
    //     );
    //     cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));
    //     cellar.addAdaptorToCatalogue(address(curveAdaptor));
    //     cellar.setRebalanceDeviation(0.030e18);

    //     token.safeApprove(address(cellar), assets);
    //     deal(address(token), address(this), assets);
    //     cellar.deposit(assets, address(this));

    //     uint256 balanceInGauge = CurveGauge(gauge).balanceOf(address(cellar));
    //     assertEq(assets + initialAssets, balanceInGauge, "Should have deposited assets into gauge.");

    //     // Strategist rebalances to pull half of assets from gauge.
    //     {
    //         Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = _createBytesDataToUnStakeCurveLP(gauge, balanceInGauge / 2);
    //         data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
    //         cellar.callOnAdaptor(data);
    //     }

    //     // Make sure when we redeem we pull from gauge and cellar wallet.
    //     uint256 sharesToRedeem = cellar.balanceOf(address(this));
    //     cellar.redeem(sharesToRedeem, address(this), address(this));

    //     assertEq(token.balanceOf(address(this)), assets);
    // }

    /// TODO - New Curve Dynamic Array Related Tests

    /**
     * @notice tests with passed in curve pool use of dynamic array enum in strategist functions, respectively.
     * @dev this covers addLiquidity, addLiquidityETH, removeLiquidity, removeLiquidityETH
     */
    function _manageLiquidityIn2PoolDynamicArraysNoETH(
        uint256 assets,
        address pool,
        address token,
        address gauge,
        uint256 tolerance,
        bytes4 selector
    ) internal {
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        ERC20 coins0 = ERC20(CurvePool(pool).coins(0));
        ERC20 coins1 = ERC20(CurvePool(pool).coins(1));

        // Convert cellars USDC balance into coins0.
        if (coins0 != USDC) {
            if (address(coins0) == curveAdaptor.CURVE_ETH()) {
                assets = priceRouter.getValue(USDC, assets, WETH);
                deal(address(WETH), address(cellar), assets);
            } else {
                assets = priceRouter.getValue(USDC, assets, coins0);
                if (coins0 == STETH) _takeSteth(assets, address(cellar));
                else if (coins0 == OETH) _takeOeth(assets, address(cellar));
                else if (coins0 == EETH) _takeEETH(assets, address(cellar));
                else deal(address(coins0), address(cellar), assets);
            }
            deal(address(USDC), address(cellar), 0);
        }

        // ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = coins0;
        tokens[1] = coins1;

        // uint256[] memory orderedTokenAmounts = new uint256[](2);
        orderedTokenAmounts[0] = assets / 2;
        orderedTokenAmounts[1] = 0;

        // Strategist rebalances into LP , single asset.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddLiquidityToCurve(
                pool,
                ERC20(token),
                orderedTokenAmounts,
                0,
                gauge,
                selector,
                CurveHelper.FixedOrDynamic.Dynamic
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        // uint256 cellarCurveLPBalance = ERC20(token).balanceOf(address(cellar));

        // expectedValueOut = priceRouter.getValue(coins0, assets / 2, ERC20(token));
        // assertApproxEqRel(
        //     cellarCurveLPBalance,
        //     expectedValueOut,
        //     tolerance,
        //     "Cellar should have received expected value out."
        // );

        // // Strategist rebalances into LP , dual asset.
        // // Simulate a swap by minting Cellar CRVUSD in exchange for USDC.
        // {
        //     uint256 coins1Amount = priceRouter.getValue(coins0, assets / 4, coins1);
        //     orderedTokenAmounts[0] = assets / 4;
        //     orderedTokenAmounts[1] = coins1Amount;
        //     if (coins0 == STETH) _takeSteth(assets / 4, address(cellar));
        //     else if (coins0 == OETH) _takeOeth(assets / 4, address(cellar));
        //     else if (coins0 == EETH) _takeEETH(assets / 4, address(cellar));
        //     else deal(address(coins0), address(cellar), assets / 4);
        //     if (coins1 == STETH) _takeSteth(coins1Amount, address(cellar));
        //     else if (coins1 == OETH) _takeOeth(coins1Amount, address(cellar));
        //     else if (coins1 == EETH) _takeEETH(coins1Amount, address(cellar));

        //     else deal(address(coins1), address(cellar), coins1Amount);
        // }
        // {
        //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataToAddLiquidityToCurve(
        //         pool,
        //         ERC20(token),
        //         orderedTokenAmounts,
        //         0,
        //         gauge,
        //         selector,
        //         CurveHelper.FixedOrDynamic.Dynamic
        //     );
        //     data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
        //     cellar.callOnAdaptor(data);
        // }

        // assertGt(ERC20(token).balanceOf(address(cellar)), 0, "Should have added liquidity");

        // expectedValueOut = priceRouter.getValues(tokens, orderedTokenAmounts, ERC20(token));
        // uint256 actualValueOut = ERC20(token).balanceOf(address(cellar)) - cellarCurveLPBalance;

        // assertApproxEqRel(
        //     actualValueOut,
        //     expectedValueOut,
        //     tolerance,
        //     "Cellar should have received expected value out."
        // );

        // // uint256[] memory balanceDelta = new uint256[](2);
        // balanceDelta[0] = coins0.balanceOf(address(cellar));
        // balanceDelta[1] = coins1.balanceOf(address(cellar));

        // // Strategist stakes LP.
        // {
        //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        //     uint256 expectedLPStaked = ERC20(token).balanceOf(address(cellar));

        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataToStakeCurveLP(token, gauge, type(uint256).max, pool, selector);
        //     data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
        //     cellar.callOnAdaptor(data);

        //     assertEq(CurveGauge(gauge).balanceOf(address(cellar)), expectedLPStaked, "Should have staked LP in gauge.");
        // }
        // // Pass time.
        // _skip(1 days);

        // // Strategist unstakes half the LP.
        // {
        //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        //     uint256 lpStaked = CurveGauge(gauge).balanceOf(address(cellar));

        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataToUnStakeCurveLP(gauge, lpStaked / 2);
        //     data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
        //     cellar.callOnAdaptor(data);

        //     assertApproxEqAbs(
        //         CurveGauge(gauge).balanceOf(address(cellar)),
        //         lpStaked / 2,
        //         1,
        //         "Should have staked LP in gauge."
        //     );
        // }

        // // Zero out cellars LP balance.
        // deal(address(CRV), address(cellar), 0);

        // // Pass time.
        // _skip(1 days);

        // // Unstake remaining LP, and call getRewards.
        // {
        //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        //     bytes[] memory adaptorCalls = new bytes[](2);
        //     adaptorCalls[0] = _createBytesDataToUnStakeCurveLP(gauge, type(uint256).max);
        //     adaptorCalls[1] = _createBytesDataToClaimRewardsForCurveLP(gauge);
        //     data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
        //     cellar.callOnAdaptor(data);
        // }

        // // TODO assertGt(CRV.balanceOf(address(cellar)), 0, "Cellar should have recieved CRV rewards.");

        // // Strategist pulls liquidity dual asset.
        // // orderedTokenAmounts = new uint256[](2); // Specify zero for min amounts out.
        // uint256 amountToPull = ERC20(token).balanceOf(address(cellar));
        // {
        //     Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataToRemoveLiquidityFromCurve(
        //         pool,
        //         ERC20(token),
        //         amountToPull,
        //         new uint256[](2),
        //         gauge,
        //         selector,
        //         CurveHelper.FixedOrDynamic.Dynamic
        //     );
        //     data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
        //     cellar.callOnAdaptor(data);
        // }

        // balanceDelta[0] = coins0.balanceOf(address(cellar)) - balanceDelta[0];
        // balanceDelta[1] = coins1.balanceOf(address(cellar)) - balanceDelta[1];

        // actualValueOut = priceRouter.getValues(tokens, balanceDelta, ERC20(token));
        // assertApproxEqRel(actualValueOut, amountToPull, tolerance, "Cellar should have received expected value out.");

        // assertTrue(ERC20(token).balanceOf(address(cellar)) == 0, "Should have redeemed all of cellars Curve LP Token.");
    }

    function _manageLiquidityIn2PoolDynamicArrayWithETH(
        uint256 assets,
        address pool,
        address token,
        address gauge,
        uint256 tolerance,
        bytes4 selector
    ) internal {
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // ERC20[] memory coins = new ERC20[](2);
        coins[0] = ERC20(CurvePool(pool).coins(0));
        coins[1] = ERC20(CurvePool(pool).coins(1));

        // Convert cellars USDC balance into coins0.
        if (coins[0] != USDC) {
            if (address(coins[0]) == curveAdaptor.CURVE_ETH()) {
                assets = priceRouter.getValue(USDC, assets, WETH);
                deal(address(WETH), address(cellar), assets);
            } else {
                assets = priceRouter.getValue(USDC, assets, coins[0]);
                if (coins[0] == STETH) _takeSteth(assets, address(cellar));
                else if (coins[0] == OETH) _takeOeth(assets, address(cellar));
                else if (coins[0] == EETH) _takeEETH(assets, address(cellar));
                else deal(address(coins[0]), address(cellar), assets);
            }
            deal(address(USDC), address(cellar), 0);
        }

        // ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = coins[0];
        tokens[1] = coins[1];

        if (address(coins[0]) == curveAdaptor.CURVE_ETH()) coins[0] = WETH;
        if (address(coins[1]) == curveAdaptor.CURVE_ETH()) coins[1] = WETH;

        // uint256[] memory orderedTokenAmounts = new uint256[](2);
        orderedTokenAmounts[0] = assets / 2;
        orderedTokenAmounts[1] = 0;

        // Strategist rebalances into LP , single asset.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddETHLiquidityToCurve(
                pool,
                ERC20(token),
                orderedTokenAmounts,
                0,
                false,
                gauge,
                selector,
                CurveHelper.FixedOrDynamic.Dynamic
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        uint256 cellarCurveLPBalance = ERC20(token).balanceOf(address(cellar));

        expectedValueOut = priceRouter.getValue(coins[0], assets / 2, ERC20(token));
        assertApproxEqRel(
            cellarCurveLPBalance,
            expectedValueOut,
            tolerance,
            "Cellar should have received expected value out."
        );

        // Strategist rebalances into LP , dual asset.
        // Simulate a swap by minting Cellar CRVUSD in exchange for USDC.
        {
            uint256 coins1Amount = priceRouter.getValue(coins[0], assets / 4, coins[1]);
            orderedTokenAmounts[0] = assets / 4;
            orderedTokenAmounts[1] = coins1Amount;
            if (coins[0] == STETH) _takeSteth(assets / 4, address(cellar));
            else if (coins[0] == OETH) _takeOeth(assets / 4, address(cellar));
            else if (coins[0] == EETH) _takeEETH(assets / 4, address(cellar));
            else deal(address(coins[0]), address(cellar), assets / 4);
            if (coins[1] == STETH) _takeSteth(coins1Amount, address(cellar));
            else if (coins[1] == OETH) _takeOeth(coins1Amount, address(cellar));
            else if (coins[1] == EETH) _takeEETH(assets / 4, address(cellar));
            else deal(address(coins[1]), address(cellar), coins1Amount);
        }
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddETHLiquidityToCurve(
                pool,
                ERC20(token),
                orderedTokenAmounts,
                0,
                false,
                gauge,
                selector,
                CurveHelper.FixedOrDynamic.Dynamic
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        assertGt(ERC20(token).balanceOf(address(cellar)), 0, "Should have added liquidity");

        {
            uint256 actualValueOut = ERC20(token).balanceOf(address(cellar)) - cellarCurveLPBalance;
            expectedValueOut = priceRouter.getValues(coins, orderedTokenAmounts, ERC20(token));

            assertApproxEqRel(
                actualValueOut,
                expectedValueOut,
                tolerance,
                "Cellar should have received expected value out."
            );
        }

        // uint256[] memory balanceDelta = new uint256[](2);
        balanceDelta[0] = coins[0].balanceOf(address(cellar));
        balanceDelta[1] = coins[1].balanceOf(address(cellar));

        // Strategist stakes LP.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            uint256 expectedLPStaked = ERC20(token).balanceOf(address(cellar));

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToStakeCurveLP(token, gauge, type(uint256).max, pool, selector);
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);

            assertEq(CurveGauge(gauge).balanceOf(address(cellar)), expectedLPStaked, "Should have staked LP in gauge.");
        }
        // Pass time.
        _skip(1 days);

        // Strategist unstakes half the LP, claiming rewards.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            uint256 lpStaked = CurveGauge(gauge).balanceOf(address(cellar));

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToUnStakeCurveLP(gauge, lpStaked / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);

            assertApproxEqAbs(
                CurveGauge(gauge).balanceOf(address(cellar)),
                lpStaked / 2,
                1,
                "Should have staked LP in gauge."
            );
        }

        // Zero out cellars LP balance.
        deal(address(CRV), address(cellar), 0);

        // Pass time.
        _skip(1 days);

        // Unstake remaining LP, and call getRewards.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](2);
            adaptorCalls[0] = _createBytesDataToUnStakeCurveLP(gauge, type(uint256).max);
            adaptorCalls[1] = _createBytesDataToClaimRewardsForCurveLP(gauge);
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        // TODO assertGt(CRV.balanceOf(address(cellar)), 0, "Cellar should have recieved CRV rewards.");

        // Strategist pulls liquidity dual asset.
        orderedTokenAmounts = new uint256[](2); // Specify zero for min amounts out.
        uint256 amountToPull = ERC20(token).balanceOf(address(cellar));
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRemoveETHLiquidityFromCurve(
                pool,
                ERC20(token),
                amountToPull,
                orderedTokenAmounts,
                false,
                gauge,
                selector,
                CurveHelper.FixedOrDynamic.Dynamic
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        balanceDelta[0] = coins[0].balanceOf(address(cellar)) - balanceDelta[0];
        balanceDelta[1] = coins[1].balanceOf(address(cellar)) - balanceDelta[1];

        {
            uint256 actualValueOut = priceRouter.getValues(coins, balanceDelta, ERC20(token));
            assertApproxEqRel(
                actualValueOut,
                amountToPull,
                tolerance,
                "Cellar should have received expected value out."
            );
        }

        assertTrue(ERC20(token).balanceOf(address(cellar)) == 0, "Should have redeemed all of cellars Curve LP Token.");
    }

    /**
     * @notice tests non-happy path for scenarios where dynamic array enum is used.
     * @dev this covers addLiquidity, addLiquidityETH, removeLiquidity, removeLiquidityETH
     * NOTE: Try passing in dynamic enum when the curvePool it is working with is fixed array. Try passing in dynamic enum but incorrect other params.
     * TODO - see if Crispy's manageLiquidity test have these things in it.
     */

    function _checkForReentrancyOnWithdraw(
        uint256 assets,
        address pool,
        address token,
        address gauge,
        bytes4 selector
    ) internal {
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // ERC20[] memory coins = new ERC20[](2);
        coins[0] = ERC20(CurvePool(pool).coins(0));
        coins[1] = ERC20(CurvePool(pool).coins(1));

        // Convert cellars USDC balance into coins0.
        if (coins[0] != USDC) {
            if (address(coins[0]) == curveAdaptor.CURVE_ETH()) {
                assets = priceRouter.getValue(USDC, assets, WETH);
                deal(address(WETH), address(cellar), assets);
            } else {
                assets = priceRouter.getValue(USDC, assets, coins[0]);
                if (coins[0] == STETH) _takeSteth(assets, address(cellar));
                else if (coins[0] == OETH) _takeOeth(assets, address(cellar));
                else if (coins[0] == EETH) _takeEETH(assets, address(cellar));
                else deal(address(coins[0]), address(cellar), assets);
            }
            deal(address(USDC), address(cellar), 0);
        }

        // ERC20[] memory tokens = new ERC20[](2);
        tokens[0] = coins[0];
        tokens[1] = coins[1];

        if (address(coins[0]) == curveAdaptor.CURVE_ETH()) coins[0] = WETH;
        if (address(coins[1]) == curveAdaptor.CURVE_ETH()) coins[1] = WETH;

        // uint256[] memory orderedTokenAmounts = new uint256[](2);
        orderedTokenAmounts[0] = assets;
        orderedTokenAmounts[1] = 0;

        // Strategist rebalances into LP , single asset.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToAddETHLiquidityToCurve(
                pool,
                ERC20(token),
                orderedTokenAmounts,
                0,
                false,
                gauge,
                selector,
                CurveHelper.FixedOrDynamic.Dynamic
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(curveAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        // Mint attacker Curve LP so they can withdraw liquidity and re-enter.
        deal(token, address(this), 1e18);

        CurvePool curvePool = CurvePool(pool);

        // Attacker tries en-entering into Cellar on ETH recieve but redeem reverts.
        attackCellar = true;
        vm.expectRevert();
        curvePool.remove_liquidity(1e18, [uint256(0), 0]);

        // But if there is no re-entrancy attackers remove_liquidity calls is successful, and they can redeem.
        attackCellar = false;
        curvePool.remove_liquidity(1e18, [uint256(0), 0]);

        uint256 maxRedeem = cellar.maxRedeem(address(this));
        cellar.redeem(maxRedeem, address(this), address(this));
    }

    receive() external payable {
        if (attackCellar) {
            uint256 maxRedeem = cellar.maxRedeem(address(this));
            cellar.redeem(maxRedeem, address(this), address(this));
        }
    }

    function _add2PoolAssetToPriceRouter(
        address pool,
        address token,
        bool isCorrelated,
        uint256 expectedPrice,
        ERC20 underlyingOrConstituent0,
        ERC20 underlyingOrConstituent1,
        bool divideRate0,
        bool divideRate1,
        uint32 lowerBound,
        uint32 upperBound
    ) internal {
        Curve2PoolExtension.ExtensionStorage memory stor;
        stor.pool = pool;
        stor.isCorrelated = isCorrelated;
        stor.underlyingOrConstituent0 = address(underlyingOrConstituent0);
        stor.underlyingOrConstituent1 = address(underlyingOrConstituent1);
        stor.divideRate0 = divideRate0;
        stor.divideRate1 = divideRate1;
        stor.lowerBound = lowerBound;
        stor.upperBound = upperBound;
        PriceRouter.AssetSettings memory settings;
        settings.derivative = EXTENSION_DERIVATIVE;
        settings.source = address(curve2PoolExtension);

        priceRouter.addAsset(ERC20(token), settings, abi.encode(stor), expectedPrice);
    }

    function _takeSteth(uint256 amount, address to) internal {
        // STETH does not work with DEAL, so steal STETH from a whale.
        address stethWhale = 0x18709E89BD403F470088aBDAcEbE86CC60dda12e;
        vm.prank(stethWhale);
        STETH.safeTransfer(to, amount);
    }

    function _takeOeth(uint256 amount, address to) internal {
        // STETH does not work with DEAL, so steal STETH from a whale.
        address oethWhale = 0xEADB3840596cabF312F2bC88A4Bb0b93A4E1FF5F;
        vm.prank(oethWhale);
        OETH.safeTransfer(to, amount);
    }

    function _takeEETH(uint256 amount, address to) internal {
        // EETH does not work with DEAL, so steal EETH from a whale.
        address eethWhale = 0x22162DbBa43fE0477cdC5234E248264eC7C6EA7c;
        vm.prank(eethWhale);
        EETH.safeTransfer(to, amount);
    }

    function _skip(uint256 time) internal {
        uint256 blocksToRoll = time / 12; // Assumes an avg 12 second block time.
        skip(time);
        vm.roll(block.number + blocksToRoll);
        mockWETHdataFeed.setMockUpdatedAt(block.timestamp);
        mockUSDCdataFeed.setMockUpdatedAt(block.timestamp);
        mockDAI_dataFeed.setMockUpdatedAt(block.timestamp);
        mockUSDTdataFeed.setMockUpdatedAt(block.timestamp);
        mockFRAXdataFeed.setMockUpdatedAt(block.timestamp);
        mockSTETdataFeed.setMockUpdatedAt(block.timestamp);
        mockRETHdataFeed.setMockUpdatedAt(block.timestamp);
    }
}
