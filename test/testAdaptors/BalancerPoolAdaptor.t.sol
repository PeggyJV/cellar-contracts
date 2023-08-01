// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BalancerPoolAdaptor } from "src/modules/adaptors/Balancer/BalancerPoolAdaptor.sol";
import { ILiquidityGaugev3Custom } from "src/interfaces/external/Balancer/ILiquidityGaugev3Custom.sol";
import { IBasePool } from "src/interfaces/external/Balancer/typically-npm/IBasePool.sol";
import { IVault, IAsset, IERC20, IFlashLoanRecipient } from "@balancer/interfaces/contracts/vault/IVault.sol";
import { IBalancerRelayer } from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import { MockBalancerPoolAdaptor } from "src/mocks/adaptors/MockBalancerPoolAdaptor.sol";
import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { CellarWithBalancerFlashLoans } from "src/base/permutations/CellarWithBalancerFlashLoans.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract BalancerPoolAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;
    using SafeTransferLib for address;

    BalancerPoolAdaptor private balancerPoolAdaptor;
    MockBalancerPoolAdaptor private mockBalancerPoolAdaptor;
    BalancerStablePoolExtension private balancerStablePoolExtension;
    WstEthExtension private wstethExtension;

    CellarWithBalancerFlashLoans private cellar;
    CellarWithBalancerFlashLoans private wethCellar;

    uint32 private usdcPosition = 1;
    uint32 private daiPosition = 2;
    uint32 private usdtPosition = 3;
    uint32 private bbaUSDPosition = 4;
    uint32 private vanillaBbaUSDPosition = 5;
    uint32 private bbaUSDGaugePosition = 6;
    uint32 private bbaWETHPosition = 7;
    uint32 private wstETHPosition = 8;
    uint32 private wethPosition = 9;
    uint32 private wstETH_bbaWETHPosition = 10;

    uint32 private slippage = 0.9e4;
    uint256 public initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17523303;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        balancerPoolAdaptor = new BalancerPoolAdaptor(vault, minter, slippage);
        wstethExtension = new WstEthExtension(priceRouter);
        balancerStablePoolExtension = new BalancerStablePoolExtension(priceRouter, IVault(vault));
        mockBalancerPoolAdaptor = new MockBalancerPoolAdaptor(address(this), minter, slippage);

        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        // Add WETH pricing.
        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Add USDC pricing.
        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Add DAI pricing.
        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        // Add USDT pricing.
        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_USD_FEED);
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        // Add wstETH pricing.
        price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        // Add wstEth pricing.
        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);

        // Add bb_a_USD pricing.
        uint8[8] memory rateProviderDecimals;
        address[8] memory rateProviders;
        ERC20[8] memory underlyings;
        underlyings[0] = USDC;
        underlyings[1] = DAI;
        underlyings[2] = USDT;
        BalancerStablePoolExtension.ExtensionStorage memory extensionStor = BalancerStablePoolExtension
            .ExtensionStorage({
                poolId: bytes32(0),
                poolDecimals: 18,
                rateProviderDecimals: rateProviderDecimals,
                rateProviders: rateProviders,
                underlyingOrConstituent: underlyings
            });

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));
        priceRouter.addAsset(BB_A_USD, settings, abi.encode(extensionStor), 1e8);

        // Add vanilla USDC DAI USDT Bpt pricing.
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));
        priceRouter.addAsset(vanillaUsdcDaiUsdt, settings, abi.encode(extensionStor), 1e8);

        // Add wstETH_bbaWETH pricing.
        underlyings[0] = WETH;
        underlyings[1] = STETH;
        underlyings[2] = ERC20(address(0));
        extensionStor = BalancerStablePoolExtension.ExtensionStorage({
            poolId: bytes32(0),
            poolDecimals: 18,
            rateProviderDecimals: rateProviderDecimals,
            rateProviders: rateProviders,
            underlyingOrConstituent: underlyings
        });

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(balancerStablePoolExtension));
        priceRouter.addAsset(wstETH_bbaWETH, settings, abi.encode(extensionStor), 1.787e11);

        // Setup Cellar:
        registry.trustAdaptor(address(balancerPoolAdaptor));
        registry.trustAdaptor(address(mockBalancerPoolAdaptor));

        registry.trustPosition(
            bbaUSDPosition,
            address(balancerPoolAdaptor),
            abi.encode(address(BB_A_USD), BB_A_USD_GAUGE_ADDRESS)
        );
        registry.trustPosition(
            vanillaBbaUSDPosition,
            address(balancerPoolAdaptor),
            abi.encode(address(vanillaUsdcDaiUsdt), address(0))
        );
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(address(USDC))); // holdingPosition for tests
        registry.trustPosition(daiPosition, address(erc20Adaptor), abi.encode(address(DAI))); // holdingPosition for tests
        registry.trustPosition(usdtPosition, address(erc20Adaptor), abi.encode(address(USDT))); // holdingPosition for tests
        registry.trustPosition(wstETHPosition, address(erc20Adaptor), abi.encode(address(WSTETH))); // holdingPosition for tests
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(address(WETH))); // holdingPosition for tests
        registry.trustPosition(
            wstETH_bbaWETHPosition,
            address(balancerPoolAdaptor),
            abi.encode(address(wstETH_bbaWETH), wstETH_bbaWETH_GAUGE_ADDRESS)
        );

        string memory cellarName = "Balancer Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(USDC), address(this), initialDeposit);
        USDC.approve(cellarAddress, initialDeposit);

        bytes memory creationCode = type(CellarWithBalancerFlashLoans).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(this),
            registry,
            USDC,
            cellarName,
            cellarName,
            usdcPosition,
            abi.encode(0),
            initialDeposit,
            platformCut,
            type(uint192).max,
            vault
        );
        cellar = CellarWithBalancerFlashLoans(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(balancerPoolAdaptor));
        cellar.addAdaptorToCatalogue(address(erc20Adaptor));
        cellar.addAdaptorToCatalogue(address(mockBalancerPoolAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        USDC.safeApprove(address(cellar), type(uint256).max);

        cellar.setRebalanceDeviation(0.005e18);
        cellar.addPositionToCatalogue(daiPosition);
        cellar.addPositionToCatalogue(usdtPosition);
        cellar.addPositionToCatalogue(bbaUSDPosition);
        cellar.addPositionToCatalogue(vanillaBbaUSDPosition);

        cellar.addPosition(0, bbaUSDPosition, abi.encode(0), false);
        cellar.addPosition(0, vanillaBbaUSDPosition, abi.encode(0), false);
        cellar.addPosition(0, daiPosition, abi.encode(0), false);
        cellar.addPosition(0, usdtPosition, abi.encode(0), false);

        // Deploy WETH cellar.
        cellarName = "WETH Balancer Cellar V0.0";
        initialDeposit = 1e6;
        platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        cellarAddress = deployer.getAddress(cellarName);
        deal(address(WETH), address(this), initialDeposit);
        WETH.approve(cellarAddress, initialDeposit);

        creationCode = type(CellarWithBalancerFlashLoans).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            WETH,
            cellarName,
            cellarName,
            wethPosition,
            abi.encode(0),
            initialDeposit,
            platformCut,
            type(uint192).max,
            vault
        );
        wethCellar = CellarWithBalancerFlashLoans(
            deployer.deployContract(cellarName, creationCode, constructorArgs, 0)
        );

        wethCellar.addAdaptorToCatalogue(address(balancerPoolAdaptor));
        wethCellar.addAdaptorToCatalogue(address(erc20Adaptor));
        wethCellar.addAdaptorToCatalogue(address(mockBalancerPoolAdaptor));

        WETH.safeApprove(address(wethCellar), type(uint256).max);

        wethCellar.setRebalanceDeviation(0.005e18);
        wethCellar.addPositionToCatalogue(wstETHPosition);
        wethCellar.addPositionToCatalogue(wstETH_bbaWETHPosition);

        wethCellar.addPosition(0, wstETHPosition, abi.encode(0), false);
        wethCellar.addPosition(0, wstETH_bbaWETHPosition, abi.encode(0), false);

        initialAssets = cellar.totalAssets();
    }

    // ========================================= HAPPY PATH TESTS =========================================

    function testTotalAssets(uint256 assets) external {
        // User Joins Cellar.
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate strategist pool join.
        _simulatePoolJoin(address(cellar), USDC, assets, BB_A_USD);
        assertApproxEqAbs(
            cellar.totalAssets(),
            assets + initialAssets,
            10,
            "Cellar totalAssets should approximately equal assets."
        );

        // Simulate strategist stakes all their BPTs.
        uint256 bbAUsdBalance = BB_A_USD.balanceOf(address(cellar));
        _simulateBptStake(address(cellar), BB_A_USD, bbAUsdBalance, BB_A_USD_GAUGE);
        assertApproxEqAbs(
            cellar.totalAssets(),
            assets + initialAssets,
            10,
            "Cellar totalAssets should approximately equal assets."
        );

        // Simulate strategist unstaking half their BPTs.
        _simulateBptUnStake(address(cellar), BB_A_USD, bbAUsdBalance / 2, BB_A_USD_GAUGE);
        assertApproxEqAbs(
            cellar.totalAssets(),
            assets + initialAssets,
            10,
            "Cellar totalAssets should approximately equal assets."
        );

        // Simulate strategist full unstake, and exit.
        bbAUsdBalance = BB_A_USD_GAUGE.balanceOf(address(cellar));
        _simulateBptUnStake(address(cellar), BB_A_USD, bbAUsdBalance, BB_A_USD_GAUGE);
        bbAUsdBalance = BB_A_USD.balanceOf(address(cellar));
        _simulatePoolExit(address(cellar), BB_A_USD, bbAUsdBalance, USDC);
        assertApproxEqAbs(
            cellar.totalAssets(),
            assets + initialAssets,
            10,
            "Cellar totalAssets should approximately equal assets."
        );

        // At this point Cellar should hold approximately assets of USDC, and no bpts or guage bpts.
        assertApproxEqAbs(
            USDC.balanceOf(address(cellar)),
            assets + initialAssets,
            10,
            "Cellar should be holding assets amount of USDC."
        );
        assertEq(BB_A_USD.balanceOf(address(cellar)), 0, "Cellar should have no BB_A_USD.");
        assertEq(BB_A_USD_GAUGE.balanceOf(address(cellar)), 0, "Cellar should have no BB_A_USD_GAUGE.");
    }

    function testStakeBpt(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToStakeBpts(address(BB_A_USD), address(BB_A_USD_GAUGE), bptAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqRel(cellar.totalAssets(), assets, 0.01e18, "Cellar totalAssets should equal assets.");

        // Make sure cellar actually staked into gauge.
        assertEq(BB_A_USD_GAUGE.balanceOf(address(cellar)), bptAmount, "Cellar should have staked into guage.");
    }

    function testStakeUint256Max(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToStakeBpts(address(BB_A_USD), address(BB_A_USD_GAUGE), type(uint256).max);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqRel(cellar.totalAssets(), assets, 0.01e18, "Cellar totalAssets should equal assets.");

        // Make sure cellar actually staked into gauge.
        assertEq(BB_A_USD_GAUGE.balanceOf(address(cellar)), bptAmount, "Cellar should have staked into guage.");
    }

    function testUnstakeBpt(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Gauge Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD_GAUGE), address(cellar), bptAmount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToUnstakeBpts(address(BB_A_USD), address(BB_A_USD_GAUGE), bptAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqRel(cellar.totalAssets(), assets, 0.01e18, "Cellar totalAssets should equal assets.");

        // Make sure cellar actually staked into gauge.
        assertEq(BB_A_USD.balanceOf(address(cellar)), bptAmount, "Cellar should have unstaked from guage.");
    }

    function testUnstakeUint256Max(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Gauge Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD_GAUGE), address(cellar), bptAmount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToUnstakeBpts(address(BB_A_USD), address(BB_A_USD_GAUGE), type(uint256).max);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqRel(cellar.totalAssets(), assets, 0.01e18, "Cellar totalAssets should equal assets.");

        // Make sure cellar actually staked into gauge.
        assertEq(BB_A_USD.balanceOf(address(cellar)), bptAmount, "Cellar should have unstaked from guage.");
    }

    function testClaimRewards() external {
        uint256 assets = 1_000_000e6;
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToStakeBpts(address(BB_A_USD), address(BB_A_USD_GAUGE), bptAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Now that cellar is in gauge, wait for awards to accrue.
        vm.warp(block.timestamp + (1 days / 4));

        // Strategist claims rewards.
        adaptorCalls[0] = _createBytesDataToClaimBalancerRewards(address(BB_A_USD_GAUGE));

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 cellarBALBalance = BAL.balanceOf(address(cellar));

        assertGt(cellarBALBalance, 0, "Cellar should have earned BAL rewards.");
    }

    function testUserWithdrawPullFromGauge(uint256 assets, uint256 percentInGauge) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        percentInGauge = bound(percentInGauge, 0, 1e18);
        uint256 bptAmount = priceRouter.getValue(USDC, assets + initialAssets, BB_A_USD);
        // User Joins Cellar.
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Use deal to mint cellar Bpts.
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        uint256 amountToStakeInGauge = bptAmount.mulDivDown(percentInGauge, 1e18);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToStakeBpts(address(BB_A_USD), address(BB_A_USD_GAUGE), amountToStakeInGauge);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 amountToWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        uint256 expectedBptOut = priceRouter.getValue(USDC, assets, BB_A_USD);

        assertApproxEqRel(
            BB_A_USD.balanceOf(address(this)),
            expectedBptOut,
            0.0001e18,
            "User should have received assets out."
        );
    }

    function testBalancerFlashLoans() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        USDC.safeApprove(address(cellar), assets);
        cellar.deposit(assets, address(this));

        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000e6;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCallsInFlashLoan = new bytes[](2);
        adaptorCallsInFlashLoan[0] = _createBytesDataForSwapWithUniv3(USDC, DAI, 100, 1_000e6);
        adaptorCallsInFlashLoan[1] = _createBytesDataForSwapWithUniv3(DAI, USDC, 100, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCallsInFlashLoan });
        bytes memory flashLoanData = abi.encode(data);

        data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMakeFlashLoanFromBalancer(tokens, amounts, flashLoanData);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqRel(
            cellar.totalAssets(),
            initialAssets + assets,
            0.002e18,
            "Cellar totalAssets should be relatively unchanged."
        );
    }

    function testBalancerFlashLoanChecks() external {
        // Try calling `receiveFlashLoan` directly on the Cellar.
        IERC20[] memory tokens;
        uint256[] memory amounts;
        uint256[] memory feeAmounts;
        bytes memory userData;

        vm.expectRevert(
            bytes(abi.encodeWithSelector(CellarWithBalancerFlashLoans.Cellar__CallerNotBalancerVault.selector))
        );
        cellar.receiveFlashLoan(tokens, amounts, feeAmounts, userData);

        // Attacker tries to initiate a flashloan to control the Cellar.
        vm.expectRevert(bytes(abi.encodeWithSelector(CellarWithBalancerFlashLoans.Cellar__ExternalInitiator.selector)));
        IVault(vault).flashLoan(IFlashLoanRecipient(address(cellar)), tokens, amounts, userData);
    }

    /**
     * @notice check that assetsUsed() works which also checks assetOf() works
     */
    function testAssetsUsed() external {
        bytes memory adaptorData = abi.encode(address(BB_A_USD), BB_A_USD_GAUGE_ADDRESS);
        ERC20[] memory actualAsset = balancerPoolAdaptor.assetsUsed(adaptorData);
        address actualAssetAddress = address(actualAsset[0]);
        assertEq(actualAssetAddress, address(BB_A_USD));
    }

    function testIsDebt() external {
        bool result = balancerPoolAdaptor.isDebt();
        assertEq(result, false);
    }

    function testDepositToHoldingPosition() external {
        string memory cellarName = "Balancer LP Cellar V0.0";
        uint256 initialDeposit = 1e12;
        uint64 platformCut = 0.75e18;

        Cellar balancerCellar = _createCellar(
            cellarName,
            BB_A_USD,
            bbaUSDPosition,
            abi.encode(0),
            initialDeposit,
            platformCut
        );

        uint256 totalAssetsBefore = balancerCellar.totalAssets();

        uint256 assetsToDeposit = 100e18;
        deal(address(BB_A_USD), address(this), assetsToDeposit);
        BB_A_USD.safeApprove(address(balancerCellar), assetsToDeposit);
        balancerCellar.deposit(assetsToDeposit, address(this));

        uint256 totalAssetsAfter = balancerCellar.totalAssets();

        assertEq(
            totalAssetsAfter,
            totalAssetsBefore + assetsToDeposit,
            "TotalAssets should have increased by assetsToDeposit"
        );
    }

    // ========================================= Join Happy Paths =========================================

    function testJoinVanillaPool(uint256 assets) external {
        // Deposit into Cellar.
        assets = bound(assets, 0.1e6, 10_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Have strategist rebalance into vanilla USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Create Swap Data.
        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](3);
        swapsBeforeJoin[0].assetIn = IAsset(address(DAI));
        swapsBeforeJoin[1].assetIn = IAsset(address(USDC));
        swapsBeforeJoin[1].amount = type(uint256).max;
        swapsBeforeJoin[2].assetIn = IAsset(address(USDT));

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;
        swapData.swapDeadlines[2] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinBalancerPool(vanillaUsdcDaiUsdt, swapsBeforeJoin, swapData, 0);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 expectedBpt = priceRouter.getValue(USDC, assets + initialAssets, vanillaUsdcDaiUsdt);

        assertApproxEqRel(
            vanillaUsdcDaiUsdt.balanceOf(address(cellar)),
            expectedBpt,
            0.002e18,
            "Cellar should have received expected BPT."
        );
    }

    function testJoinBoostedPool(uint256 assets) external {
        // Deposit into Cellar.
        assets = bound(assets, 0.1e6, 10_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Have strategist rebalance into boosted USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Create Swap Data.
        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](3);
        swapsBeforeJoin[0].assetIn = IAsset(address(DAI));
        swapsBeforeJoin[1].assetIn = IAsset(address(USDT));

        // Create Swap Data.
        swapsBeforeJoin[2] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_usdc)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(USDC)),
            assetOut: IAsset(address(bb_a_usdc)),
            amount: assets,
            userData: bytes(abi.encode(0))
        });

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[2] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinBalancerPool(BB_A_USD, swapsBeforeJoin, swapData, 0);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 expectedBpt = priceRouter.getValue(USDC, assets, BB_A_USD);

        assertApproxEqRel(
            BB_A_USD.balanceOf(address(cellar)),
            expectedBpt,
            0.001e18,
            "Cellar should have received expected BPT."
        );
    }

    function testJoinVanillaPoolWithMultiTokens(uint256 assets) external {
        // Deposit into Cellar.
        assets = bound(assets, 0.1e6, 10_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate strategist rebalance into pools underlying assets.
        uint256 daiAmount = priceRouter.getValue(USDC, assets / 3, DAI);
        uint256 usdtAmount = priceRouter.getValue(USDC, assets / 3, USDT);
        uint256 usdcAmount = assets / 3;

        deal(address(USDT), address(cellar), usdtAmount);
        deal(address(DAI), address(cellar), daiAmount);
        deal(address(USDC), address(cellar), usdcAmount);

        // Have strategist rebalance into vanilla USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Create Swap Data.
        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](3);
        swapsBeforeJoin[0].assetIn = IAsset(address(DAI));
        swapsBeforeJoin[0].amount = daiAmount;
        swapsBeforeJoin[1].assetIn = IAsset(address(USDC));
        swapsBeforeJoin[1].amount = type(uint256).max;
        swapsBeforeJoin[2].assetIn = IAsset(address(USDT));
        swapsBeforeJoin[2].amount = type(uint256).max;
        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;
        swapData.swapDeadlines[2] = block.timestamp;
        adaptorCalls[0] = _createBytesDataToJoinBalancerPool(vanillaUsdcDaiUsdt, swapsBeforeJoin, swapData, 0);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = DAI;
        baseAssets[1] = USDC;
        baseAssets[2] = USDT;

        uint256[] memory baseAmounts = new uint256[](3);
        baseAmounts[0] = daiAmount;
        baseAmounts[1] = usdcAmount;
        baseAmounts[2] = usdtAmount;

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        // carry out tx
        cellar.callOnAdaptor(data);

        uint256 expectedBpt = priceRouter.getValues(baseAssets, baseAmounts, vanillaUsdcDaiUsdt);

        assertApproxEqRel(
            vanillaUsdcDaiUsdt.balanceOf(address(cellar)),
            expectedBpt,
            0.001e18,
            "Cellar should have received expected BPT."
        );
    }

    function testJoinBoostedPoolWithMultipleTokens(uint256 assets) external {
        // Deposit into Cellar.
        assets = bound(assets, 0.1e6, 10_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate strategist rebalance into pools underlying assets.
        uint256 daiAmount = priceRouter.getValue(USDC, assets / 3, DAI);
        uint256 usdtAmount = priceRouter.getValue(USDC, assets / 3, USDT);
        uint256 usdcAmount = assets / 3;

        deal(address(USDT), address(cellar), usdtAmount);
        deal(address(DAI), address(cellar), daiAmount);
        deal(address(USDC), address(cellar), usdcAmount);

        // Have strategist rebalance into boosted USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Create Swap Data.
        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](3);

        swapsBeforeJoin[0] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_dai)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(DAI)),
            assetOut: IAsset(address(bb_a_dai)),
            amount: daiAmount,
            userData: bytes(abi.encode(0))
        });

        swapsBeforeJoin[1] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_usdt)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(USDT)),
            assetOut: IAsset(address(bb_a_usdt)),
            amount: type(uint256).max,
            userData: bytes(abi.encode(0))
        });

        // Create Swap Data.
        swapsBeforeJoin[2] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_usdc)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(USDC)),
            assetOut: IAsset(address(bb_a_usdc)),
            amount: usdcAmount,
            userData: bytes(abi.encode(0))
        });

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;
        swapData.swapDeadlines[2] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinBalancerPool(BB_A_USD, swapsBeforeJoin, swapData, 0);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = DAI;
        baseAssets[1] = USDC;
        baseAssets[2] = USDT;

        uint256[] memory baseAmounts = new uint256[](3);
        baseAmounts[0] = daiAmount;
        baseAmounts[1] = usdcAmount;
        baseAmounts[2] = usdtAmount;

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 expectedBpt = priceRouter.getValues(baseAssets, baseAmounts, BB_A_USD);

        assertApproxEqRel(
            BB_A_USD.balanceOf(address(cellar)),
            expectedBpt,
            0.001e18,
            "Cellar should have received expected BPT."
        );
    }

    /**
     * More complex join: deal wstETH to user and they deposit to cellar.
     * Cellar should be dealt equal amounts of other constituent (WETH). Prepare swaps for bb-a-WETH.
     */
    function testNonStableCoinJoinMultiTokens(uint256 assets) external {
        // Deposit into Cellar.
        assets = bound(assets, 0.1e18, 100_000e18);
        deal(address(WETH), address(this), assets);
        wethCellar.deposit(assets, address(this));

        // pricing set up for BB_A_WETH. Now, we set up the adaptorCall to actually join the pool

        uint256 wethAmount = assets / 2;
        uint256 wstethAmount = priceRouter.getValue(WETH, assets / 2, WSTETH);

        deal(address(WETH), address(wethCellar), wethAmount);
        deal(address(WSTETH), address(wethCellar), wstethAmount);

        // Have strategist rebalance into Boosted.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](2);

        // NOTE: `vault.getPoolTokens(wstETH_bbaWETH)` to be - [0]: BB_A_WETH, [1]: wstETH, [2]: wstETH_bbaWETH
        swapsBeforeJoin[0] = IVault.SingleSwap({
            poolId: IBasePool(address(BB_A_WETH)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(WETH)),
            assetOut: IAsset(address(BB_A_WETH)),
            amount: wethAmount,
            userData: bytes(abi.encode(0))
        });

        swapsBeforeJoin[1].assetIn = IAsset(address(WSTETH));
        swapsBeforeJoin[1].amount = wstethAmount;

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](2);
        swapData.swapDeadlines = new uint256[](2);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinBalancerPool(wstETH_bbaWETH, swapsBeforeJoin, swapData, 0);

        ERC20[] memory baseAssets = new ERC20[](2);
        baseAssets[0] = WETH;
        baseAssets[1] = WSTETH;

        uint256[] memory baseAmounts = new uint256[](2);
        baseAmounts[0] = wethAmount;
        baseAmounts[1] = wstethAmount;

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });
        wethCellar.callOnAdaptor(data);

        uint256 expectedBpt = priceRouter.getValues(baseAssets, baseAmounts, wstETH_bbaWETH);

        assertApproxEqRel(
            wstETH_bbaWETH.balanceOf(address(wethCellar)),
            expectedBpt,
            0.001e18,
            "Cellar should have received expected BPT."
        );
    }

    // ========================================= Exit Happy Paths =========================================

    function testExitVanillaPool(uint256 assets) external {
        // Deposit into Cellar.
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a vanilla pool deposit by minting cellar bpts.
        uint256 bptAmount = priceRouter.getValue(USDC, assets, vanillaUsdcDaiUsdt);
        deal(address(USDC), address(cellar), 0);
        deal(address(vanillaUsdcDaiUsdt), address(cellar), bptAmount);

        // Have strategist exit pool in 1 token.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // There are no swaps to be made, so just create empty arrays.
        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);

        // There are no swaps needed because we support all the assets we get from the pool.
        IVault.SingleSwap[] memory swapsAfterExit = new IVault.SingleSwap[](3);
        swapsAfterExit[0].assetIn = IAsset(address(DAI));
        swapsAfterExit[1].assetIn = IAsset(address(USDC));
        swapsAfterExit[2].assetIn = IAsset(address(USDT));

        // Formulate request.
        IAsset[] memory poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(DAI));
        poolAssets[1] = IAsset(address(vanillaUsdcDaiUsdt));
        poolAssets[2] = IAsset(address(USDC));
        poolAssets[3] = IAsset(address(USDT));
        uint256[] memory minAmountsOut = new uint256[](4);
        bytes memory userData = abi.encode(0, bptAmount, 1);
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        adaptorCalls[0] = _createBytesDataToExitBalancerPool(vanillaUsdcDaiUsdt, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        cellar.callOnAdaptor(data);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = USDC;
        baseAssets[1] = DAI;
        baseAssets[2] = USDT;

        uint256[] memory baseAmounts = new uint256[](3);
        baseAmounts[0] = USDC.balanceOf(address(cellar));
        baseAmounts[1] = DAI.balanceOf(address(cellar));
        baseAmounts[2] = USDT.balanceOf(address(cellar));

        uint256 expectedValueOut = priceRouter.getValues(baseAssets, baseAmounts, USDC);

        assertApproxEqRel(
            cellar.totalAssets(),
            expectedValueOut,
            0.001e18,
            "Cellar should have received expected value out."
        );
    }

    function testExitBoostedPool(uint256 assets) external {
        // Deposit into Cellar.
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a vanilla pool deposit by minting cellar bpts.
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        // Have strategist exit pool in 1 token.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // There are no swaps to be made, so just create empty arrays.
        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[1] = block.timestamp;

        // We need to swap any linear pool tokens for ERC20s.
        // We don't set amounts because adaptor will automatically use all the tokens we receive as the amount.
        IVault.SingleSwap[] memory swapsAfterExit = new IVault.SingleSwap[](3);
        swapsAfterExit[0].assetIn = IAsset(address(bb_a_dai));
        swapsAfterExit[1].assetIn = IAsset(address(bb_a_usdt));
        swapsAfterExit[1].poolId = IBasePool(address(bb_a_usdt)).getPoolId();
        swapsAfterExit[2].assetIn = IAsset(address(bb_a_usdc));
        swapsAfterExit[0].assetOut = IAsset(address(DAI));
        swapsAfterExit[1].assetOut = IAsset(address(USDT));
        swapsAfterExit[2].assetOut = IAsset(address(USDC));

        // Formulate request.
        IAsset[] memory poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(bb_a_dai));
        poolAssets[1] = IAsset(address(bb_a_usdt));
        poolAssets[2] = IAsset(address(bb_a_usdc));
        poolAssets[3] = IAsset(address(BB_A_USD));
        uint256[] memory minAmountsOut = new uint256[](4);
        bytes memory userData = abi.encode(0, bptAmount, 1);
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        adaptorCalls[0] = _createBytesDataToExitBalancerPool(BB_A_USD, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        cellar.callOnAdaptor(data);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = USDC;
        baseAssets[1] = DAI;
        baseAssets[2] = USDT;

        uint256[] memory baseAmounts = new uint256[](3);
        baseAmounts[0] = USDC.balanceOf(address(cellar));
        baseAmounts[1] = DAI.balanceOf(address(cellar));
        baseAmounts[2] = USDT.balanceOf(address(cellar));

        uint256 expectedValueOut = priceRouter.getValues(baseAssets, baseAmounts, USDC);

        assertApproxEqRel(
            cellar.totalAssets(),
            expectedValueOut,
            0.001e18,
            "Cellar should have received expected value out."
        );
    }

    function testExitBoostedPoolProportional(uint256 assets) external {
        // Deposit into Cellar.
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a vanilla pool deposit by minting cellar bpts.
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        // Have strategist exit pool in 1 token.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // There are no swaps to be made, so just create empty arrays.
        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;
        swapData.swapDeadlines[2] = block.timestamp;

        // We need to swap any linear pool tokens for ERC20s.
        // We don't set amounts because adaptor will automatically use all the tokens we receive as the amount.
        IVault.SingleSwap[] memory swapsAfterExit = new IVault.SingleSwap[](3);
        swapsAfterExit[0].assetIn = IAsset(address(bb_a_dai));
        swapsAfterExit[0].poolId = IBasePool(address(bb_a_dai)).getPoolId();
        swapsAfterExit[1].assetIn = IAsset(address(bb_a_usdt));
        swapsAfterExit[1].poolId = IBasePool(address(bb_a_usdt)).getPoolId();
        swapsAfterExit[2].assetIn = IAsset(address(bb_a_usdc));
        swapsAfterExit[2].poolId = IBasePool(address(bb_a_usdc)).getPoolId();
        swapsAfterExit[0].assetOut = IAsset(address(DAI));
        swapsAfterExit[1].assetOut = IAsset(address(USDT));
        swapsAfterExit[2].assetOut = IAsset(address(USDC));

        // Formulate request.
        IAsset[] memory poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(bb_a_dai));
        poolAssets[1] = IAsset(address(bb_a_usdt));
        poolAssets[2] = IAsset(address(bb_a_usdc));
        poolAssets[3] = IAsset(address(BB_A_USD));
        uint256[] memory minAmountsOut = new uint256[](4);
        bytes memory userData = abi.encode(2, bptAmount);
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        adaptorCalls[0] = _createBytesDataToExitBalancerPool(BB_A_USD, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        cellar.callOnAdaptor(data);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = USDC;
        baseAssets[1] = DAI;
        baseAssets[2] = USDT;

        uint256[] memory baseAmounts = new uint256[](3);
        baseAmounts[0] = USDC.balanceOf(address(cellar));
        baseAmounts[1] = DAI.balanceOf(address(cellar));
        baseAmounts[2] = USDT.balanceOf(address(cellar));

        assertGt(baseAmounts[0], 0, "Cellar should have got USDC.");
        assertGt(baseAmounts[1], 0, "Cellar should have got DAI.");
        assertGt(baseAmounts[2], 0, "Cellar should have got USDT.");

        uint256 expectedValueOut = priceRouter.getValues(baseAssets, baseAmounts, USDC);

        assertApproxEqRel(
            cellar.totalAssets(),
            expectedValueOut,
            0.001e18,
            "Cellar should have received expected value out."
        );

        assertEq(BB_A_USD.balanceOf(address(cellar)), 0, "Cellar should have redeemed all BPTs.");
    }

    function testExitVanillaPoolProportional(uint256 assets) external {
        // Deposit into Cellar.
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a vanilla pool deposit by minting cellar bpts.
        uint256 bptAmount = priceRouter.getValue(USDC, assets, vanillaUsdcDaiUsdt);
        deal(address(USDC), address(cellar), 0);
        deal(address(vanillaUsdcDaiUsdt), address(cellar), bptAmount);

        // Have strategist exit pool in underlying tokens.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // There are no swaps to be made, so just create empty arrays.
        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);

        // There are no swaps needed because we support all the assets we get from the pool.
        IVault.SingleSwap[] memory swapsAfterExit = new IVault.SingleSwap[](3);
        swapsAfterExit[0].assetIn = IAsset(address(DAI));
        swapsAfterExit[1].assetIn = IAsset(address(USDC));
        swapsAfterExit[2].assetIn = IAsset(address(USDT));

        // Formulate request.
        IAsset[] memory poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(DAI));
        poolAssets[1] = IAsset(address(vanillaUsdcDaiUsdt));
        poolAssets[2] = IAsset(address(USDC));
        poolAssets[3] = IAsset(address(USDT));
        uint256[] memory minAmountsOut = new uint256[](4);
        bytes memory userData = abi.encode(2, bptAmount);
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        adaptorCalls[0] = _createBytesDataToExitBalancerPool(vanillaUsdcDaiUsdt, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        cellar.callOnAdaptor(data);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = USDC;
        baseAssets[1] = DAI;
        baseAssets[2] = USDT;

        uint256[] memory baseAmounts = new uint256[](3);
        baseAmounts[0] = USDC.balanceOf(address(cellar));
        baseAmounts[1] = DAI.balanceOf(address(cellar));
        baseAmounts[2] = USDT.balanceOf(address(cellar));

        uint256 expectedValueOut = priceRouter.getValues(baseAssets, baseAmounts, USDC);

        assertApproxEqRel(
            cellar.totalAssets(),
            expectedValueOut,
            0.002e18,
            "Cellar should have received expected value out."
        );

        assertGt(baseAmounts[0], 0, "Cellar should have got USDC.");
        assertGt(baseAmounts[1], 0, "Cellar should have got DAI.");
        assertGt(baseAmounts[2], 0, "Cellar should have got USDT.");

        assertEq(vanillaUsdcDaiUsdt.balanceOf(address(cellar)), 0, "Cellar shouyld have redeemed all BPTs.");
    }

    // ========================================= Reverts =========================================

    function testConstructorReverts() external {
        vm.expectRevert(
            bytes(abi.encodeWithSelector(BalancerPoolAdaptor.BalancerPoolAdaptor___InvalidConstructorSlippage.selector))
        );
        new BalancerPoolAdaptor(vault, minter, 0.89e4);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(BalancerPoolAdaptor.BalancerPoolAdaptor___InvalidConstructorSlippage.selector))
        );
        new BalancerPoolAdaptor(vault, minter, 1.01e4);
    }

    function testJoinPoolNoSwapsReverts() external {
        // Deposit into Cellar.
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Have strategist rebalance into vanilla USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Create Swap Data with 1 less index than required.
        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](2);
        swapsBeforeJoin[0].assetIn = IAsset(address(DAI));
        swapsBeforeJoin[1].assetIn = IAsset(address(USDC));
        swapsBeforeJoin[1].amount = type(uint256).max;

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](2);
        swapData.swapDeadlines = new uint256[](2);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinBalancerPool(vanillaUsdcDaiUsdt, swapsBeforeJoin, swapData, 0);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(BalancerPoolAdaptor.BalancerPoolAdaptor___LengthMismatch.selector))
        );
        cellar.callOnAdaptor(data);

        // Simulate strategist rebalance into pools underlying assets.
        uint256 daiAmount = priceRouter.getValue(USDC, assets / 3, DAI);
        uint256 usdtAmount = priceRouter.getValue(USDC, assets / 3, USDT);
        uint256 usdcAmount = assets / 3;

        deal(address(USDT), address(cellar), usdtAmount);
        deal(address(DAI), address(cellar), daiAmount);
        deal(address(USDC), address(cellar), usdcAmount);

        // Now make the lengths right, but mix up USDC and USDT inputs.
        swapsBeforeJoin = new IVault.SingleSwap[](3);
        swapsBeforeJoin[0].assetIn = IAsset(address(DAI));
        swapsBeforeJoin[0].amount = daiAmount;
        swapsBeforeJoin[1].assetIn = IAsset(address(USDT));
        swapsBeforeJoin[1].amount = type(uint256).max;
        swapsBeforeJoin[2].assetIn = IAsset(address(USDC));
        swapsBeforeJoin[2].amount = type(uint256).max;

        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;
        swapData.swapDeadlines[2] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinBalancerPool(vanillaUsdcDaiUsdt, swapsBeforeJoin, swapData, 0);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    BalancerPoolAdaptor.BalancerPoolAdaptor___SwapTokenAndExpectedTokenMismatch.selector
                )
            )
        );
        cellar.callOnAdaptor(data);

        // Now fix USDT USDC order, but replace DAI with FRAX.
        swapsBeforeJoin = new IVault.SingleSwap[](3);
        swapsBeforeJoin[0].assetIn = IAsset(address(FRAX));
        swapsBeforeJoin[0].amount = daiAmount;
        swapsBeforeJoin[1].assetIn = IAsset(address(USDC));
        swapsBeforeJoin[1].amount = type(uint256).max;
        swapsBeforeJoin[2].assetIn = IAsset(address(USDT));
        swapsBeforeJoin[2].amount = type(uint256).max;

        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;
        swapData.swapDeadlines[2] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinBalancerPool(vanillaUsdcDaiUsdt, swapsBeforeJoin, swapData, 0);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    BalancerPoolAdaptor.BalancerPoolAdaptor___SwapTokenAndExpectedTokenMismatch.selector
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testJoinPoolWithSwapsReverts() external {
        // Deposit into Cellar.
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate strategist rebalance into pools underlying assets.
        uint256 daiAmount = priceRouter.getValue(USDC, assets / 3, DAI);
        uint256 usdtAmount = priceRouter.getValue(USDC, assets / 3, USDT);
        uint256 usdcAmount = assets / 3;

        deal(address(USDT), address(cellar), usdtAmount);
        deal(address(DAI), address(cellar), daiAmount);
        deal(address(USDC), address(cellar), usdcAmount);

        // Have strategist rebalance into boosted USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // First replace BB A DAI with Frax.
        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](3);

        swapsBeforeJoin[0] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_dai)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(DAI)),
            assetOut: IAsset(address(FRAX)),
            amount: daiAmount,
            userData: bytes(abi.encode(0))
        });

        swapsBeforeJoin[1] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_usdt)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(USDT)),
            assetOut: IAsset(address(bb_a_usdt)),
            amount: type(uint256).max,
            userData: bytes(abi.encode(0))
        });

        // Create Swap Data.
        swapsBeforeJoin[2] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_usdc)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(address(USDC)),
            assetOut: IAsset(address(bb_a_usdc)),
            amount: usdcAmount,
            userData: bytes(abi.encode(0))
        });

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[0] = block.timestamp;
        swapData.swapDeadlines[1] = block.timestamp;
        swapData.swapDeadlines[2] = block.timestamp;

        adaptorCalls[0] = _createBytesDataToJoinBalancerPool(BB_A_USD, swapsBeforeJoin, swapData, 0);

        ERC20[] memory baseAssets = new ERC20[](3);
        baseAssets[0] = DAI;
        baseAssets[1] = USDC;
        baseAssets[2] = USDT;

        uint256[] memory baseAmounts = new uint256[](3);
        baseAmounts[0] = daiAmount;
        baseAmounts[1] = usdcAmount;
        baseAmounts[2] = usdtAmount;

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    BalancerPoolAdaptor.BalancerPoolAdaptor___SwapTokenAndExpectedTokenMismatch.selector
                )
            )
        );
        cellar.callOnAdaptor(data);

        // Fix it by setting it back to bb_a_dai, but change swap kind.
        swapsBeforeJoin[0] = IVault.SingleSwap({
            poolId: IBasePool(address(bb_a_dai)).getPoolId(),
            kind: IVault.SwapKind.GIVEN_OUT,
            assetIn: IAsset(address(DAI)),
            assetOut: IAsset(address(bb_a_dai)),
            amount: daiAmount,
            userData: bytes(abi.encode(0))
        });

        adaptorCalls[0] = _createBytesDataToJoinBalancerPool(BB_A_USD, swapsBeforeJoin, swapData, 0);

        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(BalancerPoolAdaptor.BalancerPoolAdaptor___WrongSwapKind.selector))
        );
        cellar.callOnAdaptor(data);
    }

    function testExitPoolReverts() external {
        // Deposit into Cellar.
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a vanilla pool deposit by minting cellar bpts.
        uint256 bptAmount = priceRouter.getValue(USDC, assets, BB_A_USD);
        deal(address(USDC), address(cellar), 0);
        deal(address(BB_A_USD), address(cellar), bptAmount);

        // Have strategist exit pool but try to send funds to an internal balance.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[1] = block.timestamp;

        // We need to swap any linear pool tokens for ERC20s.
        // We don't set amounts because adaptor will automatically use all the tokens we receive as the amount.
        IVault.SingleSwap[] memory swapsAfterExit = new IVault.SingleSwap[](3);
        swapsAfterExit[0].assetIn = IAsset(address(bb_a_dai));
        swapsAfterExit[1].assetIn = IAsset(address(bb_a_usdt));
        swapsAfterExit[1].poolId = IBasePool(address(bb_a_usdt)).getPoolId();
        swapsAfterExit[2].assetIn = IAsset(address(bb_a_usdc));
        swapsAfterExit[0].assetOut = IAsset(address(DAI));
        swapsAfterExit[1].assetOut = IAsset(address(USDT));
        swapsAfterExit[2].assetOut = IAsset(address(USDC));

        // Formulate request.
        IAsset[] memory poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(bb_a_dai));
        poolAssets[1] = IAsset(address(bb_a_usdt));
        poolAssets[2] = IAsset(address(bb_a_usdc));
        poolAssets[3] = IAsset(address(BB_A_USD));
        uint256[] memory minAmountsOut = new uint256[](4);
        bytes memory userData = abi.encode(0, bptAmount, 1);
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: true
        });

        adaptorCalls[0] = _createBytesDataToExitBalancerPool(BB_A_USD, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(BalancerPoolAdaptor.BalancerPoolAdaptor___InternalBalancesNotSupported.selector)
            )
        );
        cellar.callOnAdaptor(data);

        // Change toInternalBalance to false, but mistmatch the array lengths.
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[1] = block.timestamp;

        // We need to swap any linear pool tokens for ERC20s.
        // We don't set amounts because adaptor will automatically use all the tokens we receive as the amount.
        swapsAfterExit = new IVault.SingleSwap[](2);
        swapsAfterExit[0].assetIn = IAsset(address(bb_a_dai));
        swapsAfterExit[1].assetIn = IAsset(address(bb_a_usdt));
        swapsAfterExit[1].poolId = IBasePool(address(bb_a_usdt)).getPoolId();
        swapsAfterExit[0].assetOut = IAsset(address(DAI));
        swapsAfterExit[1].assetOut = IAsset(address(USDT));

        // Formulate request.
        poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(bb_a_dai));
        poolAssets[1] = IAsset(address(bb_a_usdt));
        poolAssets[2] = IAsset(address(bb_a_usdc));
        poolAssets[3] = IAsset(address(BB_A_USD));
        minAmountsOut = new uint256[](4);
        userData = abi.encode(0, bptAmount, 1);
        request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        adaptorCalls[0] = _createBytesDataToExitBalancerPool(BB_A_USD, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(BalancerPoolAdaptor.BalancerPoolAdaptor___LengthMismatch.selector))
        );
        cellar.callOnAdaptor(data);

        // Now have strategist try to swap an asset not in the BPT.
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[1] = block.timestamp;

        // We need to swap any linear pool tokens for ERC20s.
        // We don't set amounts because adaptor will automatically use all the tokens we receive as the amount.
        swapsAfterExit = new IVault.SingleSwap[](3);
        swapsAfterExit[0].assetIn = IAsset(address(bb_a_dai));
        swapsAfterExit[1].assetIn = IAsset(address(FRAX));
        swapsAfterExit[1].poolId = IBasePool(address(bb_a_usdt)).getPoolId();
        swapsAfterExit[2].assetIn = IAsset(address(bb_a_usdc));
        swapsAfterExit[0].assetOut = IAsset(address(DAI));
        swapsAfterExit[1].assetOut = IAsset(address(USDT));
        swapsAfterExit[2].assetOut = IAsset(address(USDC));

        // Formulate request.
        poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(bb_a_dai));
        poolAssets[1] = IAsset(address(bb_a_usdt));
        poolAssets[2] = IAsset(address(bb_a_usdc));
        poolAssets[3] = IAsset(address(BB_A_USD));
        minAmountsOut = new uint256[](4);
        userData = abi.encode(0, bptAmount, 1);
        request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        adaptorCalls[0] = _createBytesDataToExitBalancerPool(BB_A_USD, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    BalancerPoolAdaptor.BalancerPoolAdaptor___SwapTokenAndExpectedTokenMismatch.selector
                )
            )
        );
        cellar.callOnAdaptor(data);

        // Now have strategist try to swap with wrong swap kind.
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[1] = block.timestamp;

        // We need to swap any linear pool tokens for ERC20s.
        // We don't set amounts because adaptor will automatically use all the tokens we receive as the amount.
        swapsAfterExit = new IVault.SingleSwap[](3);
        swapsAfterExit[0].assetIn = IAsset(address(bb_a_dai));
        swapsAfterExit[1].assetIn = IAsset(address(bb_a_usdt));
        swapsAfterExit[1].poolId = IBasePool(address(bb_a_usdt)).getPoolId();
        swapsAfterExit[1].kind = IVault.SwapKind.GIVEN_OUT;
        swapsAfterExit[2].assetIn = IAsset(address(bb_a_usdc));
        swapsAfterExit[0].assetOut = IAsset(address(DAI));
        swapsAfterExit[1].assetOut = IAsset(address(USDT));
        swapsAfterExit[2].assetOut = IAsset(address(USDC));

        // Formulate request.
        poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(bb_a_dai));
        poolAssets[1] = IAsset(address(bb_a_usdt));
        poolAssets[2] = IAsset(address(bb_a_usdc));
        poolAssets[3] = IAsset(address(BB_A_USD));
        minAmountsOut = new uint256[](4);
        userData = abi.encode(0, bptAmount, 1);
        request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        adaptorCalls[0] = _createBytesDataToExitBalancerPool(BB_A_USD, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(BalancerPoolAdaptor.BalancerPoolAdaptor___WrongSwapKind.selector))
        );
        cellar.callOnAdaptor(data);

        // Now have strategist try to not swap their linear pool tokens.
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);
        swapData.swapDeadlines[1] = block.timestamp;

        // We need to swap any linear pool tokens for ERC20s.
        // We don't set amounts because adaptor will automatically use all the tokens we receive as the amount.
        swapsAfterExit = new IVault.SingleSwap[](3);
        swapsAfterExit[0].assetIn = IAsset(address(bb_a_dai));
        swapsAfterExit[1].assetIn = IAsset(address(bb_a_usdt));
        swapsAfterExit[1].poolId = IBasePool(address(bb_a_usdt)).getPoolId();
        swapsAfterExit[1].kind = IVault.SwapKind.GIVEN_IN;
        swapsAfterExit[2].assetIn = IAsset(address(bb_a_usdc));
        swapsAfterExit[0].assetOut = IAsset(address(DAI));
        swapsAfterExit[1].assetOut = IAsset(address(0));
        swapsAfterExit[2].assetOut = IAsset(address(USDC));

        // Formulate request.
        poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(bb_a_dai));
        poolAssets[1] = IAsset(address(bb_a_usdt));
        poolAssets[2] = IAsset(address(bb_a_usdc));
        poolAssets[3] = IAsset(address(BB_A_USD));
        minAmountsOut = new uint256[](4);
        userData = abi.encode(0, bptAmount, 1);
        request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        adaptorCalls[0] = _createBytesDataToExitBalancerPool(BB_A_USD, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(balancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(BalancerPoolAdaptor.BalancerPoolAdaptor___UnsupportedTokenNotSwapped.selector))
        );
        cellar.callOnAdaptor(data);
    }

    function testFailTransferEthToCellar() external {
        // This test verifies that native eth transfers to the cellar will revert.
        // So even if the strategist somehow manages to make a swap send native eth
        // to the cellar it will revert.

        deal(address(this), 1 ether);
        address(cellar).safeTransferETH(1 ether);
    }

    function testJoinPoolSlippageCheck(uint256 assets) external {
        // Deposit into Cellar.
        assets = bound(assets, 0.1e6, 10_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Have strategist rebalance into vanilla USDC DAI USDT Bpt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Create Swap Data.
        IVault.SingleSwap[] memory swapsBeforeJoin = new IVault.SingleSwap[](3);
        swapsBeforeJoin[0].assetIn = IAsset(address(DAI));
        swapsBeforeJoin[1].assetIn = IAsset(address(USDC));
        swapsBeforeJoin[1].amount = type(uint256).max;
        swapsBeforeJoin[2].assetIn = IAsset(address(USDT));

        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);

        adaptorCalls[0] = _createBytesDataToJoinBalancerPool(vanillaUsdcDaiUsdt, swapsBeforeJoin, swapData, 0);

        data[0] = Cellar.AdaptorCall({ adaptor: address(mockBalancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(bytes(abi.encodeWithSelector(BalancerPoolAdaptor.BalancerPoolAdaptor___Slippage.selector)));
        cellar.callOnAdaptor(data);
    }

    function testExitPoolSlippageCheck(uint256 assets) external {
        // Deposit into Cellar.
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Simulate a vanilla pool deposit by minting cellar bpts.
        uint256 bptAmount = priceRouter.getValue(USDC, assets, vanillaUsdcDaiUsdt);
        deal(address(USDC), address(cellar), 0);
        deal(address(vanillaUsdcDaiUsdt), address(cellar), bptAmount);

        // Have strategist exit pool in 1 token.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // There are no swaps to be made, so just create empty arrays.
        BalancerPoolAdaptor.SwapData memory swapData;
        swapData.minAmountsForSwaps = new uint256[](3);
        swapData.swapDeadlines = new uint256[](3);

        // There are no swaps needed because we support all the assets we get from the pool.
        IVault.SingleSwap[] memory swapsAfterExit = new IVault.SingleSwap[](3);
        swapsAfterExit[0].assetIn = IAsset(address(DAI));
        swapsAfterExit[1].assetIn = IAsset(address(USDC));
        swapsAfterExit[2].assetIn = IAsset(address(USDT));

        // Formulate request.
        IAsset[] memory poolAssets = new IAsset[](4);
        poolAssets[0] = IAsset(address(DAI));
        poolAssets[1] = IAsset(address(vanillaUsdcDaiUsdt));
        poolAssets[2] = IAsset(address(USDC));
        poolAssets[3] = IAsset(address(USDT));
        uint256[] memory minAmountsOut = new uint256[](4);
        bytes memory userData = abi.encode(0, bptAmount, 1);
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            assets: poolAssets,
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        adaptorCalls[0] = _createBytesDataToExitBalancerPool(vanillaUsdcDaiUsdt, swapsAfterExit, swapData, request);
        data[0] = Cellar.AdaptorCall({ adaptor: address(mockBalancerPoolAdaptor), callData: adaptorCalls });

        vm.expectRevert(bytes(abi.encodeWithSelector(BalancerPoolAdaptor.BalancerPoolAdaptor___Slippage.selector)));
        cellar.callOnAdaptor(data);
    }

    // ========================================= HELPERS =========================================

    // This function is used for exit pool slippage checks.
    // Specifically this function will only work to mock exit pools for vanilla stablecoin pool where the cellar
    // is exiting into USDC at index 1.
    function exitPool(bytes32, address sender, address payable, IVault.ExitPoolRequest memory request) external {
        (, uint256 amountOfBptsToRedeem) = abi.decode(request.userData, (uint256, uint256));
        uint256 exitPoolSlippage = 0.89e4;

        uint256 amountOfUsdcToMint = priceRouter.getValue(vanillaUsdcDaiUsdt, amountOfBptsToRedeem, USDC);
        amountOfUsdcToMint = amountOfUsdcToMint.mulDivDown(exitPoolSlippage, 1e4);

        deal(address(USDC), sender, USDC.balanceOf(sender) + amountOfUsdcToMint);
        deal(address(vanillaUsdcDaiUsdt), sender, vanillaUsdcDaiUsdt.balanceOf(address(cellar)) - amountOfBptsToRedeem);
    }

    // This function is used for join pool slippage checks.
    // Specifically this function will only work to mock join pools for vanilla stablecoin pool where the cellar
    // is joining with USDC at index 1.
    function joinPool(bytes32, address sender, address, IVault.JoinPoolRequest memory request) public {
        (, uint256[] memory amounts) = abi.decode(request.userData, (uint256, uint256[]));
        uint256 amountOfUsdcJoinedWith = amounts[1];
        uint256 joinPoolSlippage = 0.89e4;
        uint256 amountOfBptsToMint = priceRouter.getValue(USDC, amountOfUsdcJoinedWith, vanillaUsdcDaiUsdt);
        amountOfBptsToMint = amountOfBptsToMint.mulDivDown(joinPoolSlippage, 1e4);

        deal(address(USDC), sender, USDC.balanceOf(sender) - amountOfUsdcJoinedWith);
        deal(address(vanillaUsdcDaiUsdt), sender, amountOfBptsToMint);
    }

    function getPoolTokens(
        bytes32 poolId
    ) external view returns (IERC20[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock) {
        return IVault(vault).getPoolTokens(poolId);
    }

    /**
     * NOTE: it would take multiple tokens and amounts in and a single bpt out
     */
    function slippageSwap(ERC20 from, ERC20 to, uint256 inAmount, uint32 _slippage) public {
        if (priceRouter.isSupported(from) && priceRouter.isSupported(to)) {
            // Figure out value in, quoted in `to`.
            uint256 fullValueOut = priceRouter.getValue(from, inAmount, to);
            uint256 valueOutWithSlippage = fullValueOut.mulDivDown(_slippage, 1e4);
            // Deal caller new balances.
            deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
            deal(address(to), msg.sender, to.balanceOf(msg.sender) + valueOutWithSlippage);
        } else {
            // Pricing is not supported, so just assume exchange rate is 1:1.
            deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
            deal(
                address(to),
                msg.sender,
                to.balanceOf(msg.sender) + inAmount.changeDecimals(from.decimals(), to.decimals())
            );
        }
    }

    /**
     * @notice mock multicall used in `testSlippageChecks()` since it is treating this test contract as the `BalancerRelayer` through the `MockBalancerPoolAdaptor`
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        for (uint256 i = 0; i < data.length; i++) address(this).functionDelegateCall(data[i]);
        return results;
    }

    function _simulatePoolJoin(address target, ERC20 tokenIn, uint256 amountIn, ERC20 bpt) internal {
        // Convert Value in to terms of bpt.
        uint256 valueInBpt = priceRouter.getValue(tokenIn, amountIn, bpt);

        // Use deal to mutate targets balances.
        uint256 tokenInBalance = tokenIn.balanceOf(target);
        deal(address(tokenIn), target, tokenInBalance - amountIn);
        uint256 bptBalance = bpt.balanceOf(target);
        deal(address(bpt), target, bptBalance + valueInBpt);
    }

    function _simulatePoolExit(address target, ERC20 bptIn, uint256 amountIn, ERC20 tokenOut) internal {
        // Convert Value in to terms of bpt.
        uint256 valueInTokenOut = priceRouter.getValue(bptIn, amountIn, tokenOut);

        // Use deal to mutate targets balances.
        uint256 bptBalance = bptIn.balanceOf(target);
        deal(address(bptIn), target, bptBalance - amountIn);
        uint256 tokenOutBalance = tokenOut.balanceOf(target);
        deal(address(tokenOut), target, tokenOutBalance + valueInTokenOut);
    }

    function _simulateBptStake(address target, ERC20 bpt, uint256 amountIn, ERC20 gauge) internal {
        // Use deal to mutate targets balances.
        uint256 tokenInBalance = bpt.balanceOf(target);
        deal(address(bpt), target, tokenInBalance - amountIn);
        uint256 gaugeBalance = gauge.balanceOf(target);
        deal(address(gauge), target, gaugeBalance + amountIn);
    }

    function _simulateBptUnStake(address target, ERC20 bpt, uint256 amountOut, ERC20 gauge) internal {
        // Use deal to mutate targets balances.
        uint256 bptBalance = bpt.balanceOf(target);
        deal(address(bpt), target, bptBalance + amountOut);
        uint256 gaugeBalance = gauge.balanceOf(target);
        deal(address(gauge), target, gaugeBalance - amountOut);
    }
}
