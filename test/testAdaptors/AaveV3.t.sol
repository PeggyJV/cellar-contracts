// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { IPoolV3 } from "src/interfaces/external/IPoolV3.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarAaveV3Test is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    AaveV3ATokenAdaptor private aaveATokenAdaptor;
    AaveV3DebtTokenAdaptor private aaveDebtTokenAdaptor;
    ERC20Adaptor private erc20Adaptor;
    SwapWithUniswapAdaptor private swapWithUniswapAdaptor;
    CellarInitializableV2_2 private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private aWETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 private aUSDC = ERC20(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
    ERC20 private dUSDC = ERC20(0x72E95b8931767C79bA4EeE721354d6E99a61D004);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private aDAI = ERC20(0x018008bfb33d285247A21d44E50697654f754e63);
    ERC20 private dWETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private aWBTC = ERC20(0x5Ee5bf7ae06D1Be5997A1A72006FE6C607eC6DE8);
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IPoolV3 private pool = IPoolV3(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    // Note this is the BTC USD data feed, but we assume the risk that WBTC depegs from BTC.
    address private WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

    uint32 private usdcPosition;
    uint32 private aUSDCPosition;
    uint32 private debtUSDCPosition;

    modifier checkBlockNumber() {
        if (block.number < 16700000) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16700000.");
            return;
        }
        _;
    }

    function setUp() external checkBlockNumber {
        aaveATokenAdaptor = new AaveV3ATokenAdaptor();
        aaveDebtTokenAdaptor = new AaveV3DebtTokenAdaptor();
        erc20Adaptor = new ERC20Adaptor();
        swapWithUniswapAdaptor = new SwapWithUniswapAdaptor();
        priceRouter = new PriceRouter();

        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(address(this), address(swapRouter), address(priceRouter));

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
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(aaveATokenAdaptor));
        registry.trustAdaptor(address(aaveDebtTokenAdaptor));
        registry.trustAdaptor(address(swapWithUniswapAdaptor));

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));
        aUSDCPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aUSDC)));
        debtUSDCPosition = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dUSDC)));

        cellar = new CellarInitializableV2_2(registry);
        cellar.initialize(
            abi.encode(
                address(this),
                registry,
                USDC,
                "AAVE Debt Cellar",
                "AAVE-CLR",
                aUSDCPosition,
                abi.encode(1.1e18),
                strategist
            )
        );

        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPositionToCatalogue(debtUSDCPosition);

        cellar.addPosition(1, usdcPosition, abi.encode(0), false);
        cellar.addPosition(0, debtUSDCPosition, abi.encode(0), true);

        USDC.safeApprove(address(cellar), type(uint256).max);

        cellar.setRebalanceDeviation(0.005e18);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));

        // Currently tries to write a packed slot, so below call reverts.
        // stdstore.target(address(cellar)).sig(cellar.aavePool.selector).checked_write(address(pool));
    }

    function testDeposit() external checkBlockNumber {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(aUSDC.balanceOf(address(cellar)), assets, 1, "Assets should have been deposited into Aave.");
    }

    function testWithdraw() external checkBlockNumber {
        uint256 assets = 100e6;
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

    function testWithdrawalLogicNoDebt() external checkBlockNumber {
        // Add aWETH as a trusted position to the registry, then to the cellar.
        uint32 aWETHPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aWETH)));
        cellar.addPositionToCatalogue(aWETHPosition);
        cellar.addPosition(2, aWETHPosition, abi.encode(0), false);

        uint32 wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(3, wethPosition, abi.encode(0), false);

        // Change holding position to just be USDC.
        cellar.setHoldingPosition(usdcPosition);

        // Have user join the cellar.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance cellar so that it has aUSDC and aWETH positions.
        // Simulate swapping hald the assets by dealing appropriate amounts of WETH.
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH);
        deal(address(USDC), address(cellar), assets / 2);
        deal(address(WETH), address(cellar), wethAmount);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataToLend(USDC, type(uint256).max);
        adaptorCalls[1] = _createBytesDataToLend(WETH, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // If cellar has no debt, then all aTokens are fully withdrawable.
        uint256 withdrawable = cellar.maxWithdraw(address(this));
        assertApproxEqAbs(withdrawable, assets, 1, "Withdrawable should approx equal original assets deposited.");

        // Even if EMode is set, all assets are still withdrawable.
        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToChangeEMode(1);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
        withdrawable = cellar.maxWithdraw(address(this));
        assertApproxEqAbs(withdrawable, assets, 1, "Withdrawable should approx equal original assets deposited.");

        uint256 assetsOut = cellar.redeem(cellar.balanceOf(address(this)), address(this), address(this));
        assertApproxEqAbs(assetsOut, assets, 1, "Assets Out should approx equal original assets deposited.");
    }

    function testWithdrawalLogicEModeWithDebt() external checkBlockNumber {
        // Add aWETH as a trusted position to the registry, then to the cellar.
        uint32 aWETHPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aWETH)));
        cellar.addPositionToCatalogue(aWETHPosition);
        cellar.addPosition(2, aWETHPosition, abi.encode(0), false);

        uint32 debtWETHPosition = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dWETH)));
        cellar.addPositionToCatalogue(debtWETHPosition);
        cellar.addPosition(1, debtWETHPosition, abi.encode(0), true);

        uint32 wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(3, wethPosition, abi.encode(0), false);

        // Change holding position to just be USDC.
        cellar.setHoldingPosition(usdcPosition);

        // Have user join the cellar.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance cellar so that it has aUSDC and aWETH positions.
        // Simulate swapping hald the assets by dealing appropriate amounts of WETH.
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH);
        deal(address(USDC), address(cellar), assets / 2);
        deal(address(WETH), address(cellar), wethAmount);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        bytes[] memory adaptorCalls0 = new bytes[](3);
        adaptorCalls0[0] = _createBytesDataToLend(USDC, type(uint256).max);
        adaptorCalls0[1] = _createBytesDataToLend(WETH, type(uint256).max);
        adaptorCalls0[2] = _createBytesDataToChangeEMode(1);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls0 });

        bytes[] memory adaptorCalls1 = new bytes[](1);
        adaptorCalls1[0] = _createBytesDataToBorrow(dWETH, wethAmount / 10);
        data[1] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls1 });

        bytes[] memory adaptorCalls2 = new bytes[](1);
        adaptorCalls2[0] = _createBytesDataToLend(WETH, type(uint256).max);
        data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls2 });
        cellar.callOnAdaptor(data);

        // If cellar has no debt, but EMode is turned on so withdrawable should be zero.
        uint256 withdrawable = cellar.maxWithdraw(address(this));
        assertEq(withdrawable, 0, "Withdrawable should be 0.");

        // If cellar has debt, but is not in e-mode, only the position with its config data HF greater than zero is withdrawable.
    }

    function testWithdrawalLogicNoEModeWithDebt() external checkBlockNumber {
        // Add aWETH as a trusted position to the registry, then to the cellar.
        uint32 aWETHPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aWETH)));
        cellar.addPositionToCatalogue(aWETHPosition);
        cellar.addPosition(2, aWETHPosition, abi.encode(0), false);

        uint32 debtWETHPosition = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dWETH)));
        cellar.addPositionToCatalogue(debtWETHPosition);
        cellar.addPosition(1, debtWETHPosition, abi.encode(0), true);

        uint32 wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(3, wethPosition, abi.encode(0), false);

        // Change holding position to just be USDC.
        cellar.setHoldingPosition(usdcPosition);

        // Have user join the cellar.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Rebalance cellar so that it has aUSDC and aWETH positions.
        // Simulate swapping hald the assets by dealing appropriate amounts of WETH.
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH);
        deal(address(USDC), address(cellar), assets / 2);
        deal(address(WETH), address(cellar), wethAmount);
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        bytes[] memory adaptorCalls0 = new bytes[](2);
        adaptorCalls0[0] = _createBytesDataToLend(USDC, type(uint256).max);
        adaptorCalls0[1] = _createBytesDataToLend(WETH, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls0 });

        bytes[] memory adaptorCalls1 = new bytes[](1);
        adaptorCalls1[0] = _createBytesDataToBorrow(dWETH, wethAmount / 10);
        data[1] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls1 });

        bytes[] memory adaptorCalls2 = new bytes[](1);
        adaptorCalls2[0] = _createBytesDataToLend(WETH, type(uint256).max);
        data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls2 });
        cellar.callOnAdaptor(data);

        // If cellar has no debt, but EMode is turned on so withdrawable should be zero.
        uint256 withdrawable = cellar.maxWithdraw(address(this));
        assertEq(withdrawable, assets / 2, "Withdrawable should equal half the assets deposited.");

        // Withdraw should work.
        cellar.withdraw(assets / 2, address(this), address(this));
    }

    function testTotalAssets() external checkBlockNumber {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(cellar.totalAssets(), assets, 1, "Total assets should equal assets deposited.");
    }

    function testTakingOutLoans() external checkBlockNumber {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(aUSDC.balanceOf(address(cellar)), assets, 1, "Cellar should have aUSDC worth of assets.");

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrow(dUSDC, assets / 2);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            dUSDC.balanceOf(address(cellar)),
            assets / 2,
            1,
            "Cellar should have dUSDC worth of assets/2."
        );

        (ERC20[] memory tokens, uint256[] memory balances, bool[] memory isDebt) = cellar.viewPositionBalances();
        assertEq(tokens.length, 3, "Should have length of 3.");
        assertEq(balances.length, 3, "Should have length of 3.");
        assertEq(isDebt.length, 3, "Should have length of 3.");

        assertEq(address(tokens[0]), address(USDC), "Should be USDC.");
        assertEq(address(tokens[1]), address(USDC), "Should be USDC.");
        assertEq(address(tokens[2]), address(USDC), "Should be USDC.");

        assertEq(balances[0], assets, "Should equal assets.");
        assertEq(balances[1], assets / 2, "Should equal assets/2.");
        assertEq(balances[2], assets / 2, "Should equal assets/2.");

        assertEq(isDebt[0], false, "Should not be debt.");
        assertEq(isDebt[1], false, "Should not be debt.");
        assertEq(isDebt[2], true, "Should be debt.");
    }

    function testTakingOutLoansInUntrackedPosition() external checkBlockNumber {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(aUSDC.balanceOf(address(cellar)), assets, 1, "Cellar should have aUSDC worth of assets.");

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        uint256 usdcPrice = priceRouter.getExchangeRate(USDC, WETH);
        uint256 wethLoanAmount = assets.mulDivDown(10 ** WETH.decimals(), usdcPrice) / 2;
        adaptorCalls[0] = _createBytesDataToBorrow(dWETH, wethLoanAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    AaveV3DebtTokenAdaptor.AaveV3DebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
                    address(dWETH)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingLoans() external checkBlockNumber {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(aUSDC.balanceOf(address(cellar)), assets, 1, "Cellar should have aUSDC worth of assets.");

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrow(dUSDC, assets / 2);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            dUSDC.balanceOf(address(cellar)),
            assets / 2,
            1,
            "Cellar should have dUSDC worth of assets/2."
        );

        // Repay the loan.
        adaptorCalls[0] = _createBytesDataToRepay(USDC, assets / 2);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(dUSDC.balanceOf(address(cellar)), 0, 1, "Cellar should have no dUSDC left.");
    }

    function testWithdrawableFromaUSDC() external checkBlockNumber {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Take out a USDC loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrow(dUSDC, assets / 2);

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

    function testWithdrawableFromaWETH() external checkBlockNumber {
        // First adjust cellar to work primarily with WETH.
        // Make vanilla USDC the holding position.
        cellar.swapPositions(0, 1, false);
        cellar.setHoldingPosition(usdcPosition);

        // Adjust rebalance deviation so we can swap full amount of USDC for WETH.
        cellar.setRebalanceDeviation(0.005e18);

        // Add WETH, aWETH, and dWETH as trusted positions to the registry.
        uint32 wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));
        uint32 aWETHPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aWETH)));
        uint32 debtWETHPosition = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dWETH)));
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(aWETHPosition);
        cellar.addPositionToCatalogue(debtWETHPosition);

        // Remove dUSDC and aUSDC positions.
        cellar.removePosition(1, false);
        cellar.removePosition(0, true);

        cellar.addPosition(1, aWETHPosition, abi.encode(1.1e18), false);
        cellar.addPosition(0, debtWETHPosition, abi.encode(0), true);
        cellar.addPosition(2, wethPosition, abi.encode(0), false);

        // Deposit into the cellar.
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Perform several adaptor calls.
        // - Swap all USDC for WETH.
        // - Deposit all WETH into Aave.
        // - Take out a WETH loan on Aave.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsForFirstAdaptor = new bytes[](2);
        adaptorCallsForFirstAdaptor[0] = _createBytesDataForSwap(USDC, WETH, 500, assets);
        adaptorCallsForFirstAdaptor[1] = _createBytesDataToLend(WETH, type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsForFirstAdaptor });

        // Figure out roughly how much WETH the cellar has on Aave.
        uint256 approxWETHCollateral = priceRouter.getValue(USDC, assets, WETH);
        bytes[] memory adaptorCallsForSecondAdaptor = new bytes[](1);
        adaptorCallsForSecondAdaptor[0] = _createBytesDataToBorrow(dWETH, approxWETHCollateral / 2);
        data[1] = Cellar.AdaptorCall({
            adaptor: address(aaveDebtTokenAdaptor),
            callData: adaptorCallsForSecondAdaptor
        });
        cellar.callOnAdaptor(data);

        uint256 maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));

        assertEq(
            cellar.totalAssetsWithdrawable(),
            0,
            "Cellar should have remaining assets locked until strategist rebalances."
        );
    }

    function testTakingOutAFlashLoan() external checkBlockNumber {
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
        adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataToLend(USDC, 2 * assets);
        adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToBorrow(dUSDC, 2 * assets.mulWadDown(1.009e18));
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
        adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoan(
            loanToken,
            loanAmount,
            abi.encode(dataInsideFlashLoan)
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCallsForFlashLoan });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            aUSDC.balanceOf(address(cellar)),
            3 * assets,
            1,
            "Cellar should have 3x its aave assets using a flash loan."
        );
    }

    function testMulitipleATokensAndDebtTokens() external checkBlockNumber {
        // Add WETH, aWETH, and dWETH as trusted positions to the registry.
        uint32 wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));
        uint32 aWETHPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aWETH)));
        uint32 debtWETHPosition = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dWETH)));

        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPositionToCatalogue(aWETHPosition);
        cellar.addPositionToCatalogue(debtWETHPosition);

        // Purposely do not set aWETH positions min health factor to signal the adaptor the position should return 0 for withdrawableFrom.
        cellar.addPosition(2, aWETHPosition, abi.encode(0), false);
        cellar.addPosition(1, debtWETHPosition, abi.encode(0), true);
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
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](3);
        adaptorCallsFirstAdaptor[0] = _createBytesDataToWithdraw(USDC, assets / 2);
        adaptorCallsFirstAdaptor[1] = _createBytesDataForSwap(USDC, WETH, 500, assets / 2);
        adaptorCallsFirstAdaptor[2] = _createBytesDataToLend(WETH, type(uint256).max);
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](2);
        adaptorCallsSecondAdaptor[0] = _createBytesDataToBorrow(dUSDC, assets / 4);
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH) / 2; // To get approx a 50% LTV loan.
        adaptorCallsSecondAdaptor[1] = _createBytesDataToBorrow(dWETH, wethAmount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsFirstAdaptor });
        data[1] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCallsSecondAdaptor });
        cellar.callOnAdaptor(data);

        uint256 maxAssets = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxAssets, address(this), address(this));
    }

    // This check stops strategists from taking on any debt in positions they do not set up properly.
    // This stops the attack vector or strategists opening up an untracked debt position then depositing the funds into a vesting contract.
    function testTakingOutLoanInUntrackedPosition() external checkBlockNumber {
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrow(dWETH, 1e18);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    AaveV3DebtTokenAdaptor.AaveV3DebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
                    address(dWETH)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingDebtThatIsNotOwed() external checkBlockNumber {
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRepay(USDC, 1e6);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });

        // Error code 15: No debt of selected type.
        vm.expectRevert(bytes("39"));
        cellar.callOnAdaptor(data);
    }

    function testBlockExternalReceiver() external checkBlockNumber {
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
            abi.encode(address(aUSDC)),
            abi.encode(0)
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        cellar.callOnAdaptor(data);
    }

    // ========================================== INTEGRATION TEST ==========================================

    function testIntegration() external checkBlockNumber {
        // Manage positions to reflect the following
        // 0) aUSDC (holding)
        // 1) aWETH
        // 2) aWBTC

        // Debt Position
        // 0) dUSDC
        uint32 aWETHPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aWETH)));
        uint32 aWBTCPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aWBTC)));
        cellar.addPositionToCatalogue(aWETHPosition);
        cellar.addPositionToCatalogue(aWBTCPosition);
        cellar.addPosition(1, aWETHPosition, abi.encode(0), false);
        cellar.addPosition(2, aWBTCPosition, abi.encode(0), false);
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
        // ~20% in aUSDC.
        // ~40% Aave aWETH/dUSDC with 2x LONG on WETH.
        // ~40% Aave aWBTC/dUSDC with 3x LONG on WBTC.

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Create data to withdraw USDC, swap for WETH and WBTC and lend them on Aave.
        {
            uint256 amountToSwap = assets.mulDivDown(8, 10);
            bytes[] memory adaptorCalls = new bytes[](5);
            adaptorCalls[0] = _createBytesDataToWithdraw(USDC, assets.mulDivDown(8, 10));
            adaptorCalls[1] = _createBytesDataForSwap(USDC, WETH, 500, amountToSwap);
            amountToSwap = priceRouter.getValue(USDC, amountToSwap / 2, WETH);
            adaptorCalls[2] = _createBytesDataForSwap(WETH, WBTC, 500, amountToSwap);

            adaptorCalls[3] = _createBytesDataToLend(WETH, type(uint256).max);
            adaptorCalls[4] = _createBytesDataToLend(WBTC, type(uint256).max);

            data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }

        // Create data to flash loan USDC, sell it, and lend more WETH and WBTC on Aave.
        {
            // Want to borrow 3x 40% of assets
            uint256 USDCtoFlashLoan = assets.mulDivDown(12, 10);
            // Borrow the flash loan amount + premium.
            uint256 USDCtoBorrow = USDCtoFlashLoan.mulDivDown(1e3 + pool.FLASHLOAN_PREMIUM_TOTAL(), 1e3);

            bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
            Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](2);
            bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](4);
            bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](1);
            // Swap USDC for WETH.
            adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataForSwap(USDC, WETH, 500, USDCtoFlashLoan);
            // Swap USDC for WBTC.
            uint256 amountToSwap = priceRouter.getValue(USDC, USDCtoFlashLoan.mulDivDown(2, 3), WETH);
            adaptorCallsInsideFlashLoanFirstAdaptor[1] = _createBytesDataForSwap(WETH, WBTC, 500, amountToSwap);
            // Lend USDC on Aave specifying to use the max amount available.
            adaptorCallsInsideFlashLoanFirstAdaptor[2] = _createBytesDataToLend(WETH, type(uint256).max);
            adaptorCallsInsideFlashLoanFirstAdaptor[3] = _createBytesDataToLend(WBTC, type(uint256).max);
            adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToBorrow(dUSDC, USDCtoBorrow);
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
            loanAmount[0] = USDCtoFlashLoan;
            adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoan(
                loanToken,
                loanAmount,
                abi.encode(dataInsideFlashLoan)
            );
            data[1] = Cellar.AdaptorCall({
                adaptor: address(aaveDebtTokenAdaptor),
                callData: adaptorCallsForFlashLoan
            });
        }

        // Create data to lend remaining USDC on Aave.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(USDC, type(uint256).max);

            data[2] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
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
            uint256 cellarAWETH = aWETH.balanceOf(address(cellar));
            // By lowering the USDC flash loan amount, we free up more aUSDC for withdraw, but lower the health factor
            uint256 USDCtoFlashLoan = priceRouter.getValue(WETH, cellarAWETH, USDC).mulDivDown(8, 10);

            bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
            Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](2);
            bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](1);
            bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](2);
            // Repay USDC debt.
            adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataToRepay(USDC, USDCtoFlashLoan);
            // Withdraw WETH and swap for USDC.
            adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToWithdraw(WETH, cellarAWETH);
            adaptorCallsInsideFlashLoanSecondAdaptor[1] = _createBytesDataForSwap(WETH, USDC, 500, cellarAWETH);
            dataInsideFlashLoan[0] = Cellar.AdaptorCall({
                adaptor: address(aaveDebtTokenAdaptor),
                callData: adaptorCallsInsideFlashLoanFirstAdaptor
            });
            dataInsideFlashLoan[1] = Cellar.AdaptorCall({
                adaptor: address(aaveATokenAdaptor),
                callData: adaptorCallsInsideFlashLoanSecondAdaptor
            });
            address[] memory loanToken = new address[](1);
            loanToken[0] = address(USDC);
            uint256[] memory loanAmount = new uint256[](1);
            loanAmount[0] = USDCtoFlashLoan;
            adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoan(
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
            adaptorCalls[0] = _createBytesDataToLend(USDC, type(uint256).max);

            data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        assertGt(
            cellar.totalAssetsWithdrawable(),
            100_000e6,
            "There should a significant amount of assets withdrawable."
        );
    }

    // ========================================= HELPER FUNCTIONS =========================================
    function _createBytesDataForSwap(
        ERC20 from,
        ERC20 to,
        uint24 poolFee,
        uint256 fromAmount
    ) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = poolFee;
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV3.selector, path, poolFees, fromAmount, 0);
    }

    function _createBytesDataToLend(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToChangeEMode(uint8 category) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.changeEMode.selector, category);
    }

    function _createBytesDataToWithdraw(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToBorrow(ERC20 debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToRepay(ERC20 tokenToRepay, uint256 amountToRepay) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
    }

    function _createBytesDataToFlashLoan(
        address[] memory loanToken,
        uint256[] memory loanAmount,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.flashLoan.selector, loanToken, loanAmount, params);
    }
}
