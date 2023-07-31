// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CTokenAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";

import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarCompoundTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    CTokenAdaptor private cTokenAdaptor;
    VestingSimpleAdaptor private vestingAdaptor;
    VestingSimple private vesting;
    Cellar private cellar;

    Comptroller private comptroller = Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    uint32 private daiPosition = 1;
    uint32 private cDAIPosition = 2;
    uint32 private usdcPosition = 3;
    uint32 private cUSDCPosition = 4;
    uint32 private daiVestingPosition = 5;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        vesting = new VestingSimple(USDC, 1 days / 4, 1e6);
        cTokenAdaptor = new CTokenAdaptor(address(comptroller), address(COMP));
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

        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(DAI));
        registry.trustPosition(cDAIPosition, address(cTokenAdaptor), abi.encode(cDAI));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(cUSDCPosition, address(cTokenAdaptor), abi.encode(cUSDC));
        registry.trustPosition(daiVestingPosition, address(vestingAdaptor), abi.encode(vesting));

        string memory cellarName = "Compound Cellar V0.0";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, DAI, cDAIPosition, abi.encode(0), initialDeposit, platformCut);

        cellar.setRebalanceDeviation(0.003e18);
        cellar.addAdaptorToCatalogue(address(cTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(vestingAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        cellar.addPositionToCatalogue(daiPosition);
        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPositionToCatalogue(cUSDCPosition);
        cellar.addPositionToCatalogue(daiVestingPosition);

        cellar.addPosition(1, daiPosition, abi.encode(0), false);
        cellar.addPosition(1, usdcPosition, abi.encode(0), false);
        cellar.addPosition(1, cUSDCPosition, abi.encode(0), false);
        cellar.addPosition(1, daiVestingPosition, abi.encode(0), false);

        DAI.safeApprove(address(cellar), type(uint256).max);
    }

    function testDeposit(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqRel(
            cDAI.balanceOf(address(cellar)).mulDivDown(cDAI.exchangeRateStored(), 1e18),
            assets + initialAssets,
            0.001e18,
            "Assets should have been deposited into Compound."
        );
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e18, 1_000_000e18);
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        deal(address(DAI), address(this), 0);
        uint256 amountToWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        assertEq(DAI.balanceOf(address(this)), amountToWithdraw, "Amount withdrawn should equal callers DAI balance.");
    }

    function testTotalAssets() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 1_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqRel(
            cellar.totalAssets(),
            assets + initialAssets,
            0.0002e18,
            "Total assets should equal assets deposited."
        );

        // Swap from DAI to USDC and lend USDC on Compound.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataForSwapWithUniv3(DAI, USDC, 100, assets / 2);
            data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cUSDC, type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
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

    function testClaimCompAndVest() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 10_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        // Manipulate Comptroller storage to give Cellar some pending COMP.
        uint256 compReward = 10e18;
        stdstore
            .target(address(comptroller))
            .sig(comptroller.compAccrued.selector)
            .with_key(address(cellar))
            .checked_write(compReward);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Create data to claim COMP and swap it for USDC.
        address[] memory path = new address[](3);
        path[0] = address(COMP);
        path[1] = address(WETH);
        path[2] = address(USDC);
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 500;
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(CTokenAdaptor.claimComp.selector);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                SwapWithUniswapAdaptor.swapWithUniV3.selector,
                path,
                poolFees,
                type(uint256).max,
                0
            );
            data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            // Create data to vest USDC.
            adaptorCalls[0] = abi.encodeWithSelector(
                VestingSimpleAdaptor.depositToVesting.selector,
                vesting,
                type(uint256).max
            );
            data[2] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        uint256 totalAssets = cellar.totalAssets();

        // Pass time to fully vest the USDC.
        vm.warp(block.timestamp + 1 days / 4);

        assertApproxEqRel(
            cellar.totalAssets(),
            totalAssets + priceRouter.getValue(COMP, compReward, USDC) + initialAssets,
            0.05e18,
            "New totalAssets should equal previous plus vested USDC."
        );
    }

    function testMaliciousStrategistMovingFundsIntoUntrackedCompoundPosition() external {
        uint256 initialAssets = cellar.totalAssets();
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);

        // Remove cDAI as a position from Cellar.
        cellar.setHoldingPosition(daiPosition);
        cellar.removePosition(0, false);

        // Add DAI to the Cellar.
        uint256 assets = 100_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 assetsBeforeAttack = cellar.totalAssets();

        // Strategist malicously makes several `callOnAdaptor` calls to lower the Cellars Share Price.
        data = new Cellar.AdaptorCall[](1);
        adaptorCalls = new bytes[](1);
        uint256 amountToLend = assets;
        for (uint8 i; i < 10; i++) {
            // Choose a value close to the Cellars rebalance deviation limit.
            amountToLend = cellar.totalAssets().mulDivDown(0.003e18, 1e18);
            adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cDAI, amountToLend);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }
        uint256 assetsLost = assetsBeforeAttack - cellar.totalAssets();
        assertApproxEqRel(
            assetsLost,
            assets.mulDivDown(0.03e18, 1e18),
            0.02e18,
            "Assets Lost should be about 3% of original TVL."
        );

        // Somm Governance sees suspicious rebalances, and temporarily shuts down the cellar.
        cellar.initiateShutdown();

        // Somm Governance revokes old strategists privilages and puts in new strategist.

        // Shut down is lifted, and strategist rebalances cellar back to original value.
        cellar.liftShutdown();
        uint256 amountToWithdraw = assetsLost / 12;
        for (uint8 i; i < 12; i++) {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, amountToWithdraw);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        assertApproxEqRel(
            cellar.totalAssets(),
            assets + initialAssets,
            0.001e18,
            "totalAssets should be equal to original assets."
        );
    }

    function testAddingPositionWithUnsupportedAssetsReverts() external {
        // trust position fails because TUSD is not set up for pricing.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Registry.Registry__PositionPricingNotSetUp.selector, address(TUSD)))
        );
        registry.trustPosition(300, address(cTokenAdaptor), abi.encode(address(cTUSD)));

        // Add TUSD.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(TUSD_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, TUSD_USD_FEED);
        priceRouter.addAsset(TUSD, settings, abi.encode(stor), price);

        // trust position works now.
        registry.trustPosition(300, address(cTokenAdaptor), abi.encode(address(cTUSD)));
    }

    function testErrorCodeCheck() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        {
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompoundV2(cDAI, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        }
        cellar.callOnAdaptor(data);
        // Remove cDAI as a position from Cellar.
        cellar.setHoldingPosition(daiPosition);
        cellar.removePosition(0, false);

        // Add DAI to the Cellar.
        uint256 assets = 100_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        // Convert cellar assets to USDC.
        assets = assets.changeDecimals(18, 6);
        deal(address(DAI), address(cellar), 0);
        deal(address(USDC), address(cellar), assets);

        // Strategist tries to lend more USDC then they have,
        data = new Cellar.AdaptorCall[](1);
        adaptorCalls = new bytes[](1);

        // Choose an amount too large so deposit fails.
        uint256 amountToLend = assets + 1;

        adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cUSDC, amountToLend);
        data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__NonZeroCompoundErrorCode.selector, 13))
        );
        cellar.callOnAdaptor(data);

        // Strategist tries to withdraw more assets then they have.
        adaptorCalls = new bytes[](2);
        amountToLend = assets;
        uint256 amountToWithdraw = assets + 1e6;

        adaptorCalls[0] = _createBytesDataToLendOnComnpoundV2(cUSDC, amountToLend);
        adaptorCalls[1] = _createBytesDataToWithdrawFromCompoundV2(cUSDC, amountToWithdraw);
        data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CTokenAdaptor.CTokenAdaptor__NonZeroCompoundErrorCode.selector, 9))
        );
        cellar.callOnAdaptor(data);
    }
}
