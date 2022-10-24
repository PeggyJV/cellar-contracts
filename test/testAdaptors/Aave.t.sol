// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/aave/AaveDebtTokenAdaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";

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

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private aUSDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    ERC20 private dUSDC = ERC20(0x619beb58998eD2278e08620f97007e1116D5D25b);
    ERC20 private dWETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);
    ERC20 private CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    ERC20 private dCVX = ERC20(0x4Ae5E4409C6Dbc84A00f9f89e4ba096603fb7d50);
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

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

        priceRouter.addAsset(USDC, 0, 0, false, 0);
        priceRouter.addAsset(WETH, 0, 0, false, 0);

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

        USDC.approve(address(cellar), type(uint256).max);

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

    //TODO add test seeing if strategists can take on debt in untracked positions.
    // //TODO test balanceOf adaptor position
    // //TODO test assetOf adaptor position
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

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToBorrow(dUSDC, assets / 2);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveDebtTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
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

    //TODO add test using a flash loan.

    // ========================================= HELPER FUNCTIONS =========================================
    function _createBytesDataToBorrow(ERC20 tokenToBorrow, uint256 amountToBorrow) internal returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, tokenToBorrow, amountToBorrow);
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
