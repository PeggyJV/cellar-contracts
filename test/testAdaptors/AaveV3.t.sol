// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";

import { IPoolV3 } from "src/interfaces/external/IPoolV3.sol";

import { CellarWithAaveFlashLoans } from "src/base/permutations/CellarWithAaveFlashLoans.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarAaveV3Test is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    AaveV3ATokenAdaptor private aaveATokenAdaptor;
    AaveV3DebtTokenAdaptor private aaveDebtTokenAdaptor;
    CellarWithAaveFlashLoans private cellar;

    IPoolV3 private pool = IPoolV3(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    address private aaveOracle = 0x54586bE62E3c3580375aE3723C145253060Ca0C2;

    uint32 private usdcPosition = 1;
    uint32 private aV3USDCPosition = 1_000_001;
    uint32 private debtUSDCPosition = 1_000_002;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16700000;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        aaveATokenAdaptor = new AaveV3ATokenAdaptor(address(pool), aaveOracle, 1.05e18);
        aaveDebtTokenAdaptor = new AaveV3DebtTokenAdaptor(address(pool), 1.05e18);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(aaveATokenAdaptor));
        registry.trustAdaptor(address(aaveDebtTokenAdaptor));

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(aV3USDCPosition, address(aaveATokenAdaptor), abi.encode(address(aV3USDC)));
        registry.trustPosition(debtUSDCPosition, address(aaveDebtTokenAdaptor), abi.encode(address(dV3USDC)));

        uint256 minHealthFactor = 1.1e18;

        string memory cellarName = "AAVE Debt Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(USDC), address(this), initialDeposit);
        USDC.approve(cellarAddress, initialDeposit);

        bytes memory creationCode = type(CellarWithAaveFlashLoans).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(this),
            registry,
            USDC,
            cellarName,
            cellarName,
            aV3USDCPosition,
            abi.encode(minHealthFactor),
            initialDeposit,
            platformCut,
            type(uint192).max,
            address(pool)
        );

        cellar = CellarWithAaveFlashLoans(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));

        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPositionToCatalogue(debtUSDCPosition);

        cellar.addPosition(1, usdcPosition, abi.encode(0), false);
        cellar.addPosition(0, debtUSDCPosition, abi.encode(0), true);

        USDC.safeApprove(address(cellar), type(uint256).max);

        cellar.setRebalanceDeviation(0.005e18);
    }

    function testDeposit(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            aV3USDC.balanceOf(address(cellar)),
            assets + initialAssets,
            1,
            "Assets should have been deposited into Aave."
        );
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        deal(address(USDC), address(this), 0);
        uint256 amountToWithdraw = cellar.maxWithdraw(address(this)) - 1; // -1 accounts for rounding errors when supplying liquidity to aTokens.
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        assertEq(
            USDC.balanceOf(address(this)),
            amountToWithdraw,
            "Amount withdrawn should equal callers USDC balance."
        );
    }

    function testWithdrawalLogicNoDebt() external {
        // Add aV3WETH as a trusted position to the registry, then to the cellar.
        uint32 aV3WETHPosition = 1_000_003;
        registry.trustPosition(aV3WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV3WETH)));
        cellar.addPositionToCatalogue(aV3WETHPosition);
        cellar.addPosition(2, aV3WETHPosition, abi.encode(0), false);

        uint32 wethPosition = 2;
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(3, wethPosition, abi.encode(0), false);

        // Change holding position to just be USDC.
        cellar.setHoldingPosition(usdcPosition);

        // Have user join the cellar.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance cellar so that it has aV3USDC and aV3WETH positions.
        // Simulate swapping hald the assets by dealing appropriate amounts of WETH.
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH);
        deal(address(USDC), address(cellar), assets / 2);
        deal(address(WETH), address(cellar), wethAmount);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataToLendOnAaveV3(USDC, type(uint256).max);
        adaptorCalls[1] = _createBytesDataToLendOnAaveV3(WETH, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // If cellar has no debt, then all aTokens are fully withdrawable.
        uint256 withdrawable = cellar.maxWithdraw(address(this));
        assertApproxEqAbs(withdrawable, assets, 1, "Withdrawable should approx equal original assets deposited.");

        // Even if EMode is set, all assets are still withdrawable.
        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToChangeEModeOnAaveV3(1);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        withdrawable = cellar.maxWithdraw(address(this));
        assertApproxEqAbs(withdrawable, assets, 1, "Withdrawable should approx equal original assets deposited.");

        uint256 assetsOut = cellar.redeem(cellar.balanceOf(address(this)), address(this), address(this));
        assertApproxEqAbs(assetsOut, assets, 1, "Assets Out should approx equal original assets deposited.");
    }

    function testWithdrawalLogicEModeWithDebt() external {
        // Add aV3WETH as a trusted position to the registry, then to the cellar.
        uint32 aV3WETHPosition = 1_000_003;
        registry.trustPosition(aV3WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV3WETH)));
        cellar.addPositionToCatalogue(aV3WETHPosition);
        cellar.addPosition(2, aV3WETHPosition, abi.encode(0), false);

        uint32 debtWETHPosition = 1_000_004;
        registry.trustPosition(debtWETHPosition, address(aaveDebtTokenAdaptor), abi.encode(address(dV3WETH)));
        cellar.addPositionToCatalogue(debtWETHPosition);
        cellar.addPosition(1, debtWETHPosition, abi.encode(0), true);

        uint32 wethPosition = 2;
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(3, wethPosition, abi.encode(0), false);

        // Change holding position to just be USDC.
        cellar.setHoldingPosition(usdcPosition);

        // Have user join the cellar.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance cellar so that it has aV3USDC and aV3WETH positions.
        // Simulate swapping hald the assets by dealing appropriate amounts of WETH.
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH);
        deal(address(USDC), address(cellar), assets / 2);
        deal(address(WETH), address(cellar), wethAmount);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        bytes[] memory adaptorCalls0 = new bytes[](3);
        adaptorCalls0[0] = _createBytesDataToLendOnAaveV3(USDC, type(uint256).max);
        adaptorCalls0[1] = _createBytesDataToLendOnAaveV3(WETH, type(uint256).max);
        adaptorCalls0[2] = _createBytesDataToChangeEModeOnAaveV3(1);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls0 });

        bytes[] memory adaptorCalls1 = new bytes[](1);
        adaptorCalls1[0] = _createBytesDataToBorrowFromAaveV3(dV3WETH, wethAmount / 10);
        data[1] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls1 });

        bytes[] memory adaptorCalls2 = new bytes[](1);
        adaptorCalls2[0] = _createBytesDataToLendOnAaveV3(WETH, type(uint256).max);
        data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls2 });
        cellar.callOnAdaptor(data);

        // If cellar has no debt, but EMode is turned on so withdrawable should be zero.
        uint256 withdrawable = cellar.maxWithdraw(address(this));
        assertEq(withdrawable, 0, "Withdrawable should be 0.");

        // If cellar has debt, but is not in e-mode, only the position with its config data HF greater than zero is withdrawable.
    }

    function testWithdrawalLogicNoEModeWithDebt() external {
        uint256 initialAssets = cellar.totalAssets();
        // Add aV3WETH as a trusted position to the registry, then to the cellar.
        uint32 aV3WETHPosition = 1_000_003;
        registry.trustPosition(aV3WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV3WETH)));
        cellar.addPositionToCatalogue(aV3WETHPosition);
        cellar.addPosition(2, aV3WETHPosition, abi.encode(0), false);

        uint32 debtWETHPosition = 1_000_004;
        registry.trustPosition(debtWETHPosition, address(aaveDebtTokenAdaptor), abi.encode(address(dV3WETH)));
        cellar.addPositionToCatalogue(debtWETHPosition);
        cellar.addPosition(1, debtWETHPosition, abi.encode(0), true);

        uint32 wethPosition = 2;
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(3, wethPosition, abi.encode(0), false);

        // Change holding position to just be USDC.
        cellar.setHoldingPosition(usdcPosition);

        // Have user join the cellar.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance cellar so that it has aV3USDC and aV3WETH positions.
        // Simulate swapping hald the assets by dealing appropriate amounts of WETH.
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH);
        deal(address(USDC), address(cellar), assets / 2);
        deal(address(WETH), address(cellar), wethAmount);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        bytes[] memory adaptorCalls0 = new bytes[](2);
        adaptorCalls0[0] = _createBytesDataToLendOnAaveV3(USDC, type(uint256).max);
        adaptorCalls0[1] = _createBytesDataToLendOnAaveV3(WETH, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls0 });

        bytes[] memory adaptorCalls1 = new bytes[](1);
        adaptorCalls1[0] = _createBytesDataToBorrowFromAaveV3(dV3WETH, wethAmount / 10);
        data[1] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls1 });

        bytes[] memory adaptorCalls2 = new bytes[](1);
        adaptorCalls2[0] = _createBytesDataToLendOnAaveV3(WETH, type(uint256).max);
        data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls2 });
        cellar.callOnAdaptor(data);

        // If cellar has no debt, but EMode is turned on so withdrawable should be zero.
        uint256 withdrawable = cellar.maxWithdraw(address(this));
        assertEq(withdrawable, (assets / 2) + initialAssets, "Withdrawable should equal half the assets deposited.");

        // Withdraw should work.
        cellar.withdraw((assets / 2) + initialAssets, address(this), address(this));
    }

    function testTotalAssets(uint256 assets) external {
        uint256 initialAssets = cellar.totalAssets();
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            cellar.totalAssets(),
            assets + initialAssets,
            1,
            "Total assets should equal assets deposited."
        );
    }

    function testTakingOutLoans() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(
            aV3USDC.balanceOf(address(cellar)),
            assets + initialAssets,
            1,
            "Cellar should have aV3USDC worth of assets."
        );

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowFromAaveV3(dV3USDC, assets / 2);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            dV3USDC.balanceOf(address(cellar)),
            assets / 2,
            1,
            "Cellar should have dV3USDC worth of assets/2."
        );

        // (ERC20[] memory tokens, uint256[] memory balances, bool[] memory isDebt) = cellar.viewPositionBalances();
        // assertEq(tokens.length, 3, "Should have length of 3.");
        // assertEq(balances.length, 3, "Should have length of 3.");
        // assertEq(isDebt.length, 3, "Should have length of 3.");

        // assertEq(address(tokens[0]), address(USDC), "Should be USDC.");
        // assertEq(address(tokens[1]), address(USDC), "Should be USDC.");
        // assertEq(address(tokens[2]), address(USDC), "Should be USDC.");

        // assertApproxEqAbs(balances[0], assets + initialAssets, 1, "Should equal assets.");
        // assertEq(balances[1], assets / 2, "Should equal assets/2.");
        // assertEq(balances[2], assets / 2, "Should equal assets/2.");

        // assertEq(isDebt[0], false, "Should not be debt.");
        // assertEq(isDebt[1], false, "Should not be debt.");
        // assertEq(isDebt[2], true, "Should be debt.");
    }

    function testTakingOutLoansInUntrackedPosition() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(
            aV3USDC.balanceOf(address(cellar)),
            assets + initialAssets,
            1,
            "Cellar should have aV3USDC worth of assets."
        );

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        uint256 usdcPrice = priceRouter.getExchangeRate(USDC, WETH);
        uint256 wethLoanAmount = assets.mulDivDown(10 ** WETH.decimals(), usdcPrice) / 2;
        adaptorCalls[0] = _createBytesDataToBorrowFromAaveV3(dV3WETH, wethLoanAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    AaveV3DebtTokenAdaptor.AaveV3DebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
                    address(dV3WETH)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingLoans() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(
            aV3USDC.balanceOf(address(cellar)),
            assets + initialAssets,
            1,
            "Cellar should have aV3USDC worth of assets."
        );

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowFromAaveV3(dV3USDC, assets / 2);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            dV3USDC.balanceOf(address(cellar)),
            assets / 2,
            1,
            "Cellar should have dV3USDC worth of assets/2."
        );

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepayToAaveV3(USDC, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(dV3USDC.balanceOf(address(cellar)), 0, 1, "Cellar should have no dV3USDC left.");
    }

    function testWithdrawableFromaV3USDC() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowFromAaveV3(dV3USDC, assets / 2);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        uint256 maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));

        assertEq(USDC.balanceOf(address(this)), maxAssets, "Should have withdraw max assets possible.");

        maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));

        assertEq(
            cellar.totalAssetsWithdrawable(),
            0,
            "Cellar should have remaining assets locked until strategist rebalances."
        );
    }

    function testWithdrawableFromaV3WETH() external {
        // First adjust cellar to work primarily with WETH.
        // Make vanilla USDC the holding position.
        cellar.swapPositions(0, 1, false);
        cellar.setHoldingPosition(usdcPosition);

        // Adjust rebalance deviation so we can swap full amount of USDC for WETH.
        cellar.setRebalanceDeviation(0.005e18);

        // Add WETH, aV3WETH, and dV3WETH as trusted positions to the registry.
        uint32 aV3WETHPosition = 1_000_003;
        registry.trustPosition(aV3WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV3WETH)));
        cellar.addPositionToCatalogue(aV3WETHPosition);
        cellar.addPosition(2, aV3WETHPosition, abi.encode(0), false);

        uint32 debtWETHPosition = 1_000_004;
        registry.trustPosition(debtWETHPosition, address(aaveDebtTokenAdaptor), abi.encode(address(dV3WETH)));
        cellar.addPositionToCatalogue(debtWETHPosition);
        cellar.addPosition(1, debtWETHPosition, abi.encode(0), true);

        uint32 wethPosition = 2;
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(3, wethPosition, abi.encode(0), false);
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(aV3WETHPosition);
        cellar.addPositionToCatalogue(debtWETHPosition);

        // Withdraw from Aave V3 USDC.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV3(USDC, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });

        cellar.callOnAdaptor(data);

        // Remove dV3USDC and aV3USDC positions.
        cellar.removePosition(1, false);
        cellar.removePosition(0, true);

        // Deposit into the cellar.
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Perform several adaptor calls.
        // - Swap all USDC for WETH.
        // - Deposit all WETH into Aave.
        // - Take out a WETH loan on Aave.
        data = new Cellar.AdaptorCall[](3);
        bytes[] memory adaptorCallsForFirstAdaptor = new bytes[](1);
        adaptorCallsForFirstAdaptor[0] = _createBytesDataForSwapWithUniv3(USDC, WETH, 500, assets);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(swapWithUniswapAdaptor),
            callData: adaptorCallsForFirstAdaptor
        });

        bytes[] memory adaptorCallsForSecondAdaptor = new bytes[](1);
        adaptorCallsForSecondAdaptor[0] = _createBytesDataToLendOnAaveV3(WETH, type(uint256).max);
        data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsForSecondAdaptor });

        // Figure out roughly how much WETH the cellar has on Aave.
        uint256 approxWETHCollateral = priceRouter.getValue(USDC, assets, WETH);
        bytes[] memory adaptorCallsForThirdAdaptor = new bytes[](1);
        adaptorCallsForThirdAdaptor[0] = _createBytesDataToBorrowFromAaveV3(dV3WETH, approxWETHCollateral / 2);
        data[2] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCallsForThirdAdaptor });
        cellar.callOnAdaptor(data);

        uint256 maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));

        assertEq(
            cellar.totalAssetsWithdrawable(),
            0,
            "Cellar should have remaining assets locked until strategist rebalances."
        );
    }

    function testTakingOutAFlashLoan() external {
        uint256 initialAssets = cellar.totalAssets();
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Increase rebalance deviation so we can enter a larger position.
        // Flash loan fee is 0.09%, since we are taking a loan of 4x our assets, the total fee is 4x0.09% or 0.036%
        cellar.setRebalanceDeviation(0.004e18);

        // Perform several adaptor calls.
        // - Use Flash loan to borrow `assets` USDC.
        //      - Deposit extra USDC into AAVE.
        //      - Take out USDC loan of (assets * 1.0009) against new collateral
        //      - Repay flash loan with new USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
        Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](1);
        adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataToLendOnAaveV3(USDC, 2 * assets);
        adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToBorrowFromAaveV3(
            dV3USDC,
            2 * assets.mulWadDown(1.009e18)
        );
        dataInsideFlashLoan[0] = Cellar.AdaptorCall({
            adaptor: address(aaveATokenAdaptor),
            callData: adaptorCallsInsideFlashLoanFirstAdaptor
        });
        dataInsideFlashLoan[1] = Cellar.AdaptorCall({
            adaptor: address(aaveDebtTokenAdaptor),
            callData: adaptorCallsInsideFlashLoanSecondAdaptor
        });
        address[] memory loanToken = new address[](1);
        loanToken[0] = address(USDC);
        uint256[] memory loanAmount = new uint256[](1);
        loanAmount[0] = 4 * assets;
        adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoanFromAaveV3(
            loanToken,
            loanAmount,
            abi.encode(dataInsideFlashLoan)
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCallsForFlashLoan });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            aV3USDC.balanceOf(address(cellar)),
            (3 * assets) + initialAssets,
            10,
            "Cellar should have 3x its aave assets using a flash loan."
        );
    }

    function testMultipleATokensAndDebtTokens() external {
        // Add WETH, aV3WETH, and dV3WETH as trusted positions to the registry.
        uint32 aV3WETHPosition = 1_000_003;
        registry.trustPosition(aV3WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV3WETH)));
        cellar.addPositionToCatalogue(aV3WETHPosition);
        cellar.addPosition(2, aV3WETHPosition, abi.encode(0), false);

        uint32 debtWETHPosition = 1_000_004;
        registry.trustPosition(debtWETHPosition, address(aaveDebtTokenAdaptor), abi.encode(address(dV3WETH)));
        cellar.addPositionToCatalogue(debtWETHPosition);
        cellar.addPosition(1, debtWETHPosition, abi.encode(0), true);

        uint32 wethPosition = 2;
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(3, wethPosition, abi.encode(0), false);

        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Perform several adaptor calls.
        // - Withdraw USDC from Aave.
        // - Swap USDC for WETH.
        // - Deposit WETH into Aave.
        // - Take out USDC loan.
        // - Take out WETH loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](4);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsThirdAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsFourthAdaptor = new bytes[](2);
        adaptorCallsFirstAdaptor[0] = _createBytesDataToWithdrawFromAaveV3(USDC, assets / 2);
        adaptorCallsSecondAdaptor[0] = _createBytesDataForSwapWithUniv3(USDC, WETH, 500, assets / 2);
        adaptorCallsThirdAdaptor[0] = _createBytesDataToLendOnAaveV3(WETH, type(uint256).max);
        adaptorCallsFourthAdaptor[0] = _createBytesDataToBorrowFromAaveV3(dV3USDC, assets / 4);
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH) / 2; // To get approx a 50% LTV loan.
        adaptorCallsFourthAdaptor[1] = _createBytesDataToBorrowFromAaveV3(dV3WETH, wethAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsFirstAdaptor });
        data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCallsSecondAdaptor });
        data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsThirdAdaptor });
        data[3] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCallsFourthAdaptor });
        cellar.callOnAdaptor(data);

        uint256 maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));
    }

    // This check stops strategists from taking on any debt in positions they do not set up properly.
    // This stops the attack vector or strategists opening up an untracked debt position then depositing the funds into a vesting contract.
    function testTakingOutLoanInUntrackedPosition() external {
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrowFromAaveV3(dV3WETH, 1e18);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    AaveV3DebtTokenAdaptor.AaveV3DebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
                    address(dV3WETH)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingDebtThatIsNotOwed() external {
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRepayToAaveV3(USDC, 1e6);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });

        // Error code 15: No debt of selected type.
        vm.expectRevert(bytes("39"));
        cellar.callOnAdaptor(data);
    }

    function testBlockExternalReceiver() external {
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist tries to withdraw USDC to their own wallet using Adaptor's `withdraw` function.
        address maliciousStrategist = vm.addr(10);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(
            AaveV3ATokenAdaptor.withdraw.selector,
            100e6,
            maliciousStrategist,
            abi.encode(address(aV3USDC)),
            abi.encode(0)
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        cellar.callOnAdaptor(data);
    }

    // ========================================== INTEGRATION TEST ==========================================

    function testIntegration() external {
        // Manage positions to reflect the following
        // 0) aV3USDC (holding)
        // 1) aV3WETH
        // 2) aV3WBTC

        // Debt Position
        // 0) dV3USDC
        uint32 aV3WETHPosition = 1_000_003;
        registry.trustPosition(aV3WETHPosition, address(aaveATokenAdaptor), abi.encode(address(aV3WETH)));
        uint32 aV3WBTCPosition = 1_000_004;
        registry.trustPosition(aV3WBTCPosition, address(aaveATokenAdaptor), abi.encode(address(aV3WBTC)));
        cellar.addPositionToCatalogue(aV3WETHPosition);
        cellar.addPositionToCatalogue(aV3WBTCPosition);
        cellar.addPosition(1, aV3WETHPosition, abi.encode(0), false);
        cellar.addPosition(2, aV3WBTCPosition, abi.encode(0), false);
        cellar.removePosition(3, false);

        // Have whale join the cellar with 1M USDC.
        uint256 assets = 1_000_000e6;
        address whale = vm.addr(777);
        deal(address(USDC), whale, assets);
        vm.startPrank(whale);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, whale);
        vm.stopPrank();

        // Strategist manages cellar in order to achieve the following portfolio.
        // ~20% in aV3USDC.
        // ~40% Aave aV3WETH/dV3USDC with 2x LONG on WETH.
        // ~40% Aave aV3WBTC/dV3USDC with 3x LONG on WBTC.

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](5);
        // Create data to withdraw USDC, swap for WETH and WBTC and lend them on Aave.
        uint256 amountToSwap = assets.mulDivDown(8, 10);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV3(USDC, assets.mulDivDown(8, 10));

            data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](2);
            adaptorCalls[0] = _createBytesDataForSwapWithUniv3(USDC, WETH, 500, amountToSwap);
            amountToSwap = priceRouter.getValue(USDC, amountToSwap / 2, WETH);
            adaptorCalls[1] = _createBytesDataForSwapWithUniv3(WETH, WBTC, 500, amountToSwap);
            data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }

        {
            bytes[] memory adaptorCalls = new bytes[](2);

            adaptorCalls[0] = _createBytesDataToLendOnAaveV3(WETH, type(uint256).max);
            adaptorCalls[1] = _createBytesDataToLendOnAaveV3(WBTC, type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }

        // Create data to flash loan USDC, sell it, and lend more WETH and WBTC on Aave.
        {
            // Want to borrow 3x 40% of assets
            uint256 USDCtoFlashLoan = assets.mulDivDown(12, 10);
            // Borrow the flash loan amount + premium.
            uint256 USDCtoBorrow = USDCtoFlashLoan.mulDivDown(1e3 + pool.FLASHLOAN_PREMIUM_TOTAL(), 1e3);

            bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
            Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](3);
            bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](2);
            bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](2);
            bytes[] memory adaptorCallsInsideFlashLoanThirdAdaptor = new bytes[](1);
            // Swap USDC for WETH.
            adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataForSwapWithUniv3(
                USDC,
                WETH,
                500,
                USDCtoFlashLoan
            );
            // Swap USDC for WBTC.
            uint256 amountToSwap0 = priceRouter.getValue(USDC, USDCtoFlashLoan.mulDivDown(2, 3), WETH);
            adaptorCallsInsideFlashLoanFirstAdaptor[1] = _createBytesDataForSwapWithUniv3(
                WETH,
                WBTC,
                500,
                amountToSwap0
            );
            // Lend USDC on Aave specifying to use the max amount available.
            adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToLendOnAaveV3(WETH, type(uint256).max);
            adaptorCallsInsideFlashLoanSecondAdaptor[1] = _createBytesDataToLendOnAaveV3(WBTC, type(uint256).max);
            adaptorCallsInsideFlashLoanThirdAdaptor[0] = _createBytesDataToBorrowFromAaveV3(dV3USDC, USDCtoBorrow);
            dataInsideFlashLoan[0] = Cellar.AdaptorCall({
                adaptor: address(swapWithUniswapAdaptor),
                callData: adaptorCallsInsideFlashLoanFirstAdaptor
            });
            dataInsideFlashLoan[1] = Cellar.AdaptorCall({
                adaptor: address(aaveATokenAdaptor),
                callData: adaptorCallsInsideFlashLoanSecondAdaptor
            });
            dataInsideFlashLoan[2] = Cellar.AdaptorCall({
                adaptor: address(aaveDebtTokenAdaptor),
                callData: adaptorCallsInsideFlashLoanThirdAdaptor
            });
            address[] memory loanToken = new address[](1);
            loanToken[0] = address(USDC);
            uint256[] memory loanAmount = new uint256[](1);
            loanAmount[0] = USDCtoFlashLoan;
            adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoanFromAaveV3(
                loanToken,
                loanAmount,
                abi.encode(dataInsideFlashLoan)
            );
            data[3] = Cellar.AdaptorCall({
                adaptor: address(aaveDebtTokenAdaptor),
                callData: adaptorCallsForFlashLoan
            });
        }

        // Create data to lend remaining USDC on Aave.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnAaveV3(USDC, type(uint256).max);

            data[4] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }
        // Adjust rebalance deviation to account for slippage and fees(swap and flash loan).
        cellar.setRebalanceDeviation(0.03e18);
        cellar.callOnAdaptor(data);

        assertLt(cellar.totalAssetsWithdrawable(), assets, "Assets withdrawable should be less than assets.");

        // Whale withdraws as much as they can.
        vm.startPrank(whale);
        uint256 assetsToWithdraw = cellar.maxWithdraw(whale);
        cellar.withdraw(assetsToWithdraw, whale, whale);
        vm.stopPrank();

        assertEq(USDC.balanceOf(whale), assetsToWithdraw, "Amount withdrawn should equal maxWithdraw for Whale.");

        // Other user joins.
        assets = 100_000e6;
        address user = vm.addr(777);
        deal(address(USDC), user, assets);
        vm.startPrank(user);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, user);
        vm.stopPrank();

        assertApproxEqAbs(
            cellar.totalAssetsWithdrawable(),
            assets,
            1,
            "Total assets withdrawable should equal user deposit."
        );

        // Whale withdraws as much as they can.
        vm.startPrank(whale);
        assetsToWithdraw = cellar.maxWithdraw(whale);
        cellar.withdraw(assetsToWithdraw, whale, whale);
        vm.stopPrank();

        // Strategist must unwind strategy before any more withdraws can be made.
        assertEq(cellar.totalAssetsWithdrawable(), 0, "There should be no more assets withdrawable.");

        // Strategist is more Bullish on WBTC than WETH, so they unwind the WETH position and keep the WBTC position.
        data = new Cellar.AdaptorCall[](2);
        {
            uint256 cellarAV3WETH = aV3WETH.balanceOf(address(cellar));
            // By lowering the USDC flash loan amount, we free up more aV3USDC for withdraw, but lower the health factor
            uint256 USDCtoFlashLoan = priceRouter.getValue(WETH, cellarAV3WETH, USDC).mulDivDown(8, 10);

            bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
            Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](3);
            bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](1);
            bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](1);
            bytes[] memory adaptorCallsInsideFlashLoanThirdAdaptor = new bytes[](1);
            // Repay USDC debt.
            adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataToRepayToAaveV3(USDC, USDCtoFlashLoan);
            // Withdraw WETH and swap for USDC.
            adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToWithdrawFromAaveV3(WETH, cellarAV3WETH);
            adaptorCallsInsideFlashLoanThirdAdaptor[0] = _createBytesDataForSwapWithUniv3(
                WETH,
                USDC,
                500,
                cellarAV3WETH
            );
            dataInsideFlashLoan[0] = Cellar.AdaptorCall({
                adaptor: address(aaveDebtTokenAdaptor),
                callData: adaptorCallsInsideFlashLoanFirstAdaptor
            });
            dataInsideFlashLoan[1] = Cellar.AdaptorCall({
                adaptor: address(aaveATokenAdaptor),
                callData: adaptorCallsInsideFlashLoanSecondAdaptor
            });
            dataInsideFlashLoan[2] = Cellar.AdaptorCall({
                adaptor: address(swapWithUniswapAdaptor),
                callData: adaptorCallsInsideFlashLoanThirdAdaptor
            });
            address[] memory loanToken = new address[](1);
            loanToken[0] = address(USDC);
            uint256[] memory loanAmount = new uint256[](1);
            loanAmount[0] = USDCtoFlashLoan;
            adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoanFromAaveV3(
                loanToken,
                loanAmount,
                abi.encode(dataInsideFlashLoan)
            );
            data[0] = Cellar.AdaptorCall({
                adaptor: address(aaveDebtTokenAdaptor),
                callData: adaptorCallsForFlashLoan
            });
        }

        // Create data to lend remaining USDC on Aave.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendOnAaveV3(USDC, type(uint256).max);

            data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        assertGt(
            cellar.totalAssetsWithdrawable(),
            100_000e6,
            "There should a significant amount of assets withdrawable."
        );
    }
}
