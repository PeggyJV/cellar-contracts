// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
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

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarAaveTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    AaveATokenAdaptor private aaveATokenAdaptor;
    AaveDebtTokenAdaptor private aaveDebtTokenAdaptor;
    ERC20Adaptor private erc20Adaptor;
    MockCellar private cellar;
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
    ERC20 private CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 private dCVX = ERC20(0x4Ae5E4409C6Dbc84A00f9f89e4ba096603fb7d50);
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    uint32 private usdcPosition;
    uint32 private aUSDCPosition;
    uint32 private debtUSDCPosition;

    function setUp() external {
        aaveATokenAdaptor = new AaveATokenAdaptor();
        aaveDebtTokenAdaptor = new AaveDebtTokenAdaptor();
        erc20Adaptor = new ERC20Adaptor();
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

        // Setup Cellar:
        // Cellar positions array.
        uint32[] memory positions = new uint32[](3);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);
        registry.trustAdaptor(address(aaveATokenAdaptor), 0, 0);
        registry.trustAdaptor(address(aaveDebtTokenAdaptor), 0, 0);

        usdcPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(USDC), 0, 0);
        aUSDCPosition = registry.trustPosition(address(aaveATokenAdaptor), false, abi.encode(address(aUSDC)), 0, 0);
        debtUSDCPosition = registry.trustPosition(
            address(aaveDebtTokenAdaptor),
            true,
            abi.encode(address(dUSDC)),
            0,
            0
        );

        // address[] memory positions = new address[](5);
        // positions[0] = address(aUSDC);
        // positions[1] = address(dWETH);
        // positions[2] = address(WETH);
        // positions[3] = address(dCVX);
        // positions[4] = address(CVX);

        positions[0] = aUSDCPosition;
        positions[1] = debtUSDCPosition;
        positions[2] = usdcPosition;

        bytes[] memory positionConfigs = new bytes[](3);

        uint256 minHealthFactor = 1.1e18;
        positionConfigs[0] = abi.encode(minHealthFactor);

        cellar = new MockCellar(registry, USDC, positions, positionConfigs, "AAVE Debt Cellar", "AAVE-CLR", address(0));

        cellar.setupAdaptor(address(aaveATokenAdaptor));
        cellar.setupAdaptor(address(aaveDebtTokenAdaptor));

        USDC.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testDeposit() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(aUSDC.balanceOf(address(cellar)), assets, 2, "Assets should have been deposited into Aave.");
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

    //TODO add test seeing if strategists can take on debt in untracked positions.
    // //TODO test balanceOf adaptor position
    // //TODO test assetOf adaptor position
    function testTotalAssets() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(cellar.totalAssets(), assets, 2, "Total assets should equal assets deposited.");
    }

    function testTakingOutLoans() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(aUSDC.balanceOf(address(cellar)), assets, 2, "Cellar should have aUSDC worth of assets.");

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

    function testSwapAndRepay() external {
        // Deposit into the cellar(which deposits into Aave).
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Trust WETH as a position in the registry, then add it to the Cellar.
        uint32 wethPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(WETH), 0, 0);
        cellar.addPosition(3, wethPosition, abi.encode(0));

        // Trust dWETH as a position in the registry, then add it to the Cellar.
        uint32 debtWETHPosition = registry.trustPosition(
            address(aaveDebtTokenAdaptor),
            true,
            abi.encode(address(dWETH)),
            0,
            0
        );
        cellar.addPosition(4, debtWETHPosition, abi.encode(0));

        // Take out a WETH loan.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        uint256 amount = priceRouter.getValue(USDC, assets / 4, WETH);
        adaptorCalls[0] = _createBytesDataToBorrow(dWETH, amount);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(dWETH.balanceOf(address(cellar)), amount, 1, "Cellar should have `amount` WETH debt.");

        // Repay loan using collateral.
        data = new Cellar.AdaptorCall[](2);
        bytes[] memory adaptorCallsForFirstAdaptor = new bytes[](1);
        bytes[] memory adaptorCallsForSecondAdaptor = new bytes[](1);
        adaptorCallsForFirstAdaptor[0] = _createBytesDataToWithdraw(USDC, assets / 4);
        adaptorCallsForSecondAdaptor[0] = _createBytesDataToSwapAndRepay(USDC, WETH, 500, assets / 4);
        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCallsForFirstAdaptor });
        data[1] = Cellar.AdaptorCall({
            adaptor: address(aaveDebtTokenAdaptor),
            callData: adaptorCallsForSecondAdaptor
        });
        cellar.callOnAdaptor(data);

        // Relative accounts for swap fees.
        assertApproxEqRel(dWETH.balanceOf(address(cellar)), 0, 0.0005e18, "Cellar should have `amount/2` WETH debt.");
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
        cellar.swapPositions(0, 2);

        // Add WETH, aWETH, and dWETH as trusted positions to the registry.
        uint32 wethPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(WETH), 0, 0);
        uint32 aWETHPosition = registry.trustPosition(
            address(aaveATokenAdaptor),
            false,
            abi.encode(address(aWETH)),
            0,
            0
        );
        uint32 debtWETHPosition = registry.trustPosition(
            address(aaveDebtTokenAdaptor),
            true,
            abi.encode(address(dWETH)),
            0,
            0
        );

        // Remove dUSDC and aUSDC positions.
        cellar.removePosition(2);
        cellar.removePosition(1);

        cellar.addPosition(1, aWETHPosition, abi.encode(1.1e18));
        cellar.addPosition(2, debtWETHPosition, abi.encode(0));
        cellar.addPosition(3, wethPosition, abi.encode(0));

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

        uint256 maxAssets = cellar.maxWithdraw(address(this)) - 1;
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
        adaptorCallsInsideFlashLoanFirstAdaptor[0] = _createBytesDataToLend(USDC, 4 * assets);
        adaptorCallsInsideFlashLoanSecondAdaptor[0] = _createBytesDataToBorrow(dUSDC, 4 * assets.mulWadDown(1.009e18));
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
            5 * assets,
            1,
            "Cellar should have 5x its aave assets using a flash loan."
        );

        uint256 maxWithdraw = cellar.maxWithdraw(address(this));
        assertApproxEqAbs(
            maxWithdraw,
            USDC.balanceOf(address(cellar)),
            1,
            "Only assets withdrawable should be USDC sitting in the cellar."
        );

        // (, , , uint256 currentLiquidationThreshold, , uint256 healthFactor) = IPool(
        //     0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9
        // ).getUserAccountData(address(cellar));
        // console.log("Health Factor after flash loan", healthFactor);
        // console.log("CLT", currentLiquidationThreshold);
    }

    function testMulitipleATokensAndDebtTokens() external {
        // Add WETH, aWETH, and dWETH as trusted positions to the registry.
        uint32 wethPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(WETH), 0, 0);
        uint32 aWETHPosition = registry.trustPosition(
            address(aaveATokenAdaptor),
            false,
            abi.encode(address(aWETH)),
            0,
            0
        );
        uint32 debtWETHPosition = registry.trustPosition(
            address(aaveDebtTokenAdaptor),
            true,
            abi.encode(address(dWETH)),
            0,
            0
        );

        // Purposely do not set aWETH positions min health factor to signal the adaptor the position should return 0 for withdrawableFrom.
        cellar.addPosition(3, aWETHPosition, abi.encode(0));
        cellar.addPosition(4, debtWETHPosition, abi.encode(0));
        cellar.addPosition(5, wethPosition, abi.encode(0));

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

    //TODO is it possible to repay a debt position the cellar does not have?

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
        bytes memory params = abi.encode(path, poolFees, fromAmount, 0);
        return
            abi.encodeWithSelector(BaseAdaptor.swap.selector, from, to, fromAmount, SwapRouter.Exchange.UNIV3, params);
    }

    function _createBytesDataToLend(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToWithdraw(ERC20 tokenToWithdraw, uint256 amountToWithdraw)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(AaveATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToBorrow(ERC20 debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToRepay(ERC20 tokenToRepay, uint256 amountToRepay) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
    }

    function _createBytesDataToSwapAndRepay(
        ERC20 from,
        ERC20 to,
        uint24 fee,
        uint256 amount
    ) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = fee;
        bytes memory params = abi.encode(path, poolFees, amount, 0);
        return
            abi.encodeWithSelector(
                AaveDebtTokenAdaptor.swapAndRepay.selector,
                from,
                to,
                amount,
                SwapRouter.Exchange.UNIV3,
                params
            );
    }

    function _createBytesDataToFlashLoan(
        address[] memory loanToken,
        uint256[] memory loanAmount,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.flashLoan.selector, loanToken, loanAmount, params);
    }
    // //TODO test malicous strategist trying to move funds out of the cellar.
    // //TODO integration tests maybe looping assets on Aave?
    // //TODO test blockExternalReceiver

    // function testAavePositions() external {
    //     cellar.deposit(10000e6, address(this));
    //     Cellar.AdaptorCall[] memory callInfo = new Cellar.AdaptorCall[](1);
    //     bytes[] memory callData = new bytes[](2);
    //     bool[] memory isRevertOkay = new bool[](2);

    //     //borrow data
    //     callData[0] = abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, address(WETH), 1e18);
    //     isRevertOkay[0] = false;

    //     callData[1] = abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, address(CVX), 200e18);
    //     isRevertOkay[1] = false;

    //     callInfo[0] = Cellar.AdaptorCall({
    //         adaptor: address(aaveDebtTokenAdaptor),
    //         callData: callData,
    //         isRevertOkay: isRevertOkay
    //     });

    //     //SP Calls on Adaptor
    //     cellar.callOnAdaptor(callInfo);
    // }

    // //TODO use swapAndRepay
    // function testRepayLoanWithCollateral() external {
    //     cellar.deposit(10_000e6, address(this));
    //     Cellar.AdaptorCall[] memory callInfo = new Cellar.AdaptorCall[](1);
    //     bytes[] memory callData = new bytes[](2);
    //     bool[] memory isRevertOkay = new bool[](2);

    //     //borrow data
    //     callData[0] = abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, address(WETH), 1e18);
    //     isRevertOkay[0] = false;

    //     callData[1] = abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, address(CVX), 200e18);
    //     isRevertOkay[1] = false;

    //     callInfo[0] = Cellar.AdaptorCall({
    //         adaptor: address(aaveDebtTokenAdaptor),
    //         callData: callData,
    //         isRevertOkay: isRevertOkay
    //     });

    //     //SP Calls on Adaptor
    //     cellar.callOnAdaptor(callInfo);

    //     callInfo = new Cellar.AdaptorCall[](2);
    //     callData = new bytes[](1);
    //     isRevertOkay = new bool[](1);

    //     // Withdraw 100 USDC from Aave.
    //     callData[0] = abi.encodeWithSelector(AaveATokenAdaptor.withdrawFromAave.selector, USDC, 99e6);
    //     isRevertOkay[0] = false;
    //     callInfo[0] = Cellar.AdaptorCall({
    //         adaptor: address(aaveATokenAdaptor),
    //         callData: callData,
    //         isRevertOkay: isRevertOkay
    //     });

    //     // Swap USDC for WETH to repay loan
    //     address[] memory path = new address[](2);
    //     path[0] = address(USDC);
    //     path[1] = address(WETH);
    //     bytes memory swapParams = abi.encode(path, 99e6, 0);
    //     bytes[] memory callData0 = new bytes[](1);
    //     callData0[0] = abi.encodeWithSelector(
    //         AaveDebtTokenAdaptor.swapAndRepay.selector,
    //         USDC,
    //         WETH,
    //         99e6,
    //         SwapRouter.Exchange.UNIV2,
    //         swapParams
    //     );
    //     isRevertOkay[0] = false;
    //     callInfo[1] = Cellar.AdaptorCall({
    //         adaptor: address(aaveDebtTokenAdaptor),
    //         callData: callData0,
    //         isRevertOkay: isRevertOkay
    //     });

    //     uint256 dWETHBalBefore = dWETH.balanceOf(address(cellar));

    //     cellar.callOnAdaptor(callInfo);

    //     assertTrue(dWETHBalBefore > dWETH.balanceOf(address(cellar)), "Some debt should have been repaid.");
    // }
}
