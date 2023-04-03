// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarAaveTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    AaveATokenAdaptor private aaveATokenAdaptor;
    AaveDebtTokenAdaptor private aaveDebtTokenAdaptor;
    ERC20Adaptor private erc20Adaptor;
    SwapWithUniswapAdaptor private swapWithUniswapAdaptor;
    Cellar private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private aWETH = ERC20(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e);
    ERC20 private aUSDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    ERC20 private dUSDC = ERC20(0x619beb58998eD2278e08620f97007e1116D5D25b);
    ERC20 private dWETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private aWBTC = ERC20(0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656);
    ERC20 private TUSD = ERC20(0x0000000000085d4780B73119b644AE5ecd22b376);
    ERC20 private aTUSD = ERC20(0x101cc05f4A51C0319f570d5E146a8C625198e636);
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    // Note this is the BTC USD data feed, but we assume the risk that WBTC depegs from BTC.
    address private WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address private TUSD_USD_FEED = 0xec746eCF986E2927Abd291a2A1716c940100f8Ba;

    uint32 private usdcPosition;
    uint32 private aUSDCPosition;
    uint32 private debtUSDCPosition;

    function setUp() external {
        aaveATokenAdaptor = new AaveATokenAdaptor();
        aaveDebtTokenAdaptor = new AaveDebtTokenAdaptor();
        erc20Adaptor = new ERC20Adaptor();
        priceRouter = new PriceRouter();
        swapWithUniswapAdaptor = new SwapWithUniswapAdaptor();

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

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        // Setup Cellar:
        // Cellar positions array.
        uint32[] memory positions = new uint32[](2);
        uint32[] memory debtPositions = new uint32[](1);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(aaveATokenAdaptor));
        registry.trustAdaptor(address(aaveDebtTokenAdaptor));
        registry.trustAdaptor(address(swapWithUniswapAdaptor));

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));
        aUSDCPosition = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aUSDC)));
        debtUSDCPosition = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(address(dUSDC)));

        positions[0] = aUSDCPosition;
        positions[1] = usdcPosition;

        debtPositions[0] = debtUSDCPosition;

        bytes[] memory positionConfigs = new bytes[](2);
        bytes[] memory debtConfigs = new bytes[](1);

        uint256 minHealthFactor = 1.1e18;
        positionConfigs[0] = abi.encode(minHealthFactor);

        cellar = new Cellar(
            registry,
            USDC,
            "AAVE Debt Cellar",
            "AAVE-CLR",
            abi.encode(
                positions,
                debtPositions,
                positionConfigs,
                debtConfigs,
                aUSDCPosition,
                address(0),
                type(uint128).max,
                type(uint128).max
            )
        );

        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveDebtTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));

        USDC.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testDeposit() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(aUSDC.balanceOf(address(cellar)), assets, 1, "Assets should have been deposited into Aave.");
    }

    function testWithdraw() external {
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

    function testTotalAssets() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(cellar.totalAssets(), assets, 1, "Total assets should equal assets deposited.");
    }

    function testTakingOutLoans() external {
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
    }

    function testTakingOutLoansInUntrackedPosition() external {
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
                    AaveDebtTokenAdaptor.AaveDebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
                    address(dWETH)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    function testRepayingLoans() external {
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

    function testWithdrawableFromaUSDC() external {
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

    function testWithdrawableFromaWETH() external {
        // First adjust cellar to work primarily with WETH.
        // Make vanilla USDC the holding position.
        cellar.swapPositions(0, 1, false);
        cellar.setHoldingPosition(usdcPosition);

        // Adjust rebalance deviation so we can swap full amount of USDC for WETH.
        cellar.setRebalanceDeviation(0.003e18);

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
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        bytes[] memory adaptorCallsForFirstAdaptor = new bytes[](1);
        adaptorCallsForFirstAdaptor[0] = _createBytesDataForSwap(USDC, WETH, 500, assets);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(swapWithUniswapAdaptor),
            callData: adaptorCallsForFirstAdaptor
        });

        bytes[] memory adaptorCallsForSecondAdaptor = new bytes[](1);
        adaptorCallsForSecondAdaptor[0] = _createBytesDataToLend(WETH, type(uint256).max);
        data[1] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsForSecondAdaptor });

        // Figure out roughly how much WETH the cellar has on Aave.
        uint256 approxWETHCollateral = priceRouter.getValue(USDC, assets, WETH);
        bytes[] memory adaptorCallsForThirdAdaptor = new bytes[](1);
        adaptorCallsForThirdAdaptor[0] = _createBytesDataToBorrow(dWETH, approxWETHCollateral / 2);
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

    function testMultipleATokensAndDebtTokens() external {
        cellar.setRebalanceDeviation(0.004e18);
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
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](4);
        bytes[] memory adaptorCallsFirstAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsSecondAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsThirdAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsFourthAdaptor = new bytes[](2);
        adaptorCallsFirstAdaptor[0] = _createBytesDataToWithdraw(USDC, assets / 2);
        adaptorCallsSecondAdaptor[0] = _createBytesDataForSwap(USDC, WETH, 500, assets / 2);
        adaptorCallsThirdAdaptor[0] = _createBytesDataToLend(WETH, type(uint256).max);
        adaptorCallsFourthAdaptor[0] = _createBytesDataToBorrow(dUSDC, assets / 4);
        uint256 wethAmount = priceRouter.getValue(USDC, assets / 2, WETH) / 2; // To get approx a 50% LTV loan.
        adaptorCallsFourthAdaptor[1] = _createBytesDataToBorrow(dWETH, wethAmount);

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
        adaptorCalls[0] = _createBytesDataToBorrow(dWETH, 1e18);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    AaveDebtTokenAdaptor.AaveDebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
                    address(dWETH)
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
        adaptorCalls[0] = _createBytesDataToRepay(USDC, 1e6);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });

        // Error code 15: No debt of selected type.
        vm.expectRevert(bytes("15"));
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
            AaveATokenAdaptor.withdraw.selector,
            100e6,
            maliciousStrategist,
            abi.encode(address(aUSDC)),
            abi.encode(0)
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });

        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        cellar.callOnAdaptor(data);
    }

    function testAddingPositionWithUnsupportedAssetsReverts() external {
        // trust position fails because TUSD is not set up for pricing.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Registry.Registry__PositionPricingNotSetUp.selector, address(TUSD)))
        );
        registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aTUSD)));

        // Add TUSD.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;
        uint256 price = uint256(IChainlinkAggregator(TUSD_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, TUSD_USD_FEED);
        priceRouter.addAsset(TUSD, settings, abi.encode(stor), price);

        // trust position works now.
        registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aTUSD)));
    }

    // ========================================== INTEGRATION TEST ==========================================

    function testIntegration() external {
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

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](5);
        // Create data to withdraw USDC, swap for WETH and WBTC and lend them on Aave.
        uint256 amountToSwap = assets.mulDivDown(8, 10);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdraw(USDC, assets.mulDivDown(8, 10));

            data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](2);
            adaptorCalls[0] = _createBytesDataForSwap(USDC, WETH, 500, amountToSwap);
            amountToSwap = priceRouter.getValue(USDC, amountToSwap / 2, WETH);
            adaptorCalls[1] = _createBytesDataForSwap(WETH, WBTC, 500, amountToSwap);
            data[1] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        }

        {
            bytes[] memory adaptorCalls = new bytes[](2);

            adaptorCalls[0] = _createBytesDataToLend(WETH, type(uint256).max);
            adaptorCalls[1] = _createBytesDataToLend(WBTC, type(uint256).max);
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
            adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataForSwap(USDC, WETH, 500, USDCtoFlashLoan);
            // Swap USDC for WBTC.
            uint256 amountToSwap = priceRouter.getValue(USDC, USDCtoFlashLoan.mulDivDown(2, 3), WETH);
            adaptorCallsInsideFlashLoanFirstAdaptor[1] = _createBytesDataForSwap(WETH, WBTC, 500, amountToSwap);
            // Lend USDC on Aave specifying to use the max amount available.
            adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToLend(WETH, type(uint256).max);
            adaptorCallsInsideFlashLoanSecondAdaptor[1] = _createBytesDataToLend(WBTC, type(uint256).max);
            adaptorCallsInsideFlashLoanThirdAdaptor[0] = _createBytesDataToBorrow(dUSDC, USDCtoBorrow);
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
            adaptorCallsForFlashLoan[0] = _createBytesDataToFlashLoan(
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
            adaptorCalls[0] = _createBytesDataToLend(USDC, type(uint256).max);

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
            uint256 cellarAWETH = aWETH.balanceOf(address(cellar));
            // By lowering the USDC flash loan amount, we free up more aUSDC for withdraw, but lower the health factor
            uint256 USDCtoFlashLoan = priceRouter.getValue(WETH, cellarAWETH, USDC).mulDivDown(8, 10);

            bytes[] memory adaptorCallsForFlashLoan = new bytes[](1);
            Cellar.AdaptorCall[] memory dataInsideFlashLoan = new Cellar.AdaptorCall[](3);
            bytes[] memory adaptorCallsInsideFlashLoanFirstAdaptor = new bytes[](1);
            bytes[] memory adaptorCallsInsideFlashLoanSecondAdaptor = new bytes[](1);
            bytes[] memory adaptorCallsInsideFlashLoanThirdAdaptor = new bytes[](1);
            // Repay USDC debt.
            adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataToRepay(USDC, USDCtoFlashLoan);
            // Withdraw WETH and swap for USDC.
            adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToWithdraw(WETH, cellarAWETH);
            adaptorCallsInsideFlashLoanThirdAdaptor[0] = _createBytesDataForSwap(WETH, USDC, 500, cellarAWETH);
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
        return abi.encodeWithSelector(AaveATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToWithdraw(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToBorrow(ERC20 debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToRepay(ERC20 tokenToRepay, uint256 amountToRepay) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
    }

    function _createBytesDataToFlashLoan(
        address[] memory loanToken,
        uint256[] memory loanAmount,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.flashLoan.selector, loanToken, loanAmount, params);
    }
}
