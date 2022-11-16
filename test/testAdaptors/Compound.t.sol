// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { CTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { CErc20 } from "@compound/CErc20.sol";
import { ComptrollerG7 as Comptroller } from "@compound/ComptrollerG7.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarAaveTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    CTokenAdaptor private cTokenAdaptor;
    ERC20Adaptor private erc20Adaptor;
    MockCellar private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;

    address private immutable strategist = vm.addr(0xBEEF);

    ERC20 private COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    CErc20 private cDAI = CErc20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    CErc20 private cUSDC = CErc20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);

    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    Comptroller private comptroller = Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    uint32 private daiPosition;
    uint32 private cDAIPosition;
    uint32 private usdcPosition;
    uint32 private cUSDCPosition;

    function setUp() external {
        cTokenAdaptor = new CTokenAdaptor();
        erc20Adaptor = new ERC20Adaptor();
        priceRouter = new PriceRouter();

        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(address(this), address(swapRouter), address(priceRouter));

        priceRouter.addAsset(DAI, 0, 0, false, 0);
        priceRouter.addAsset(USDC, 0, 0, false, 0);

        // Setup Cellar:
        // Cellar positions array.
        uint32[] memory positions = new uint32[](4);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);
        registry.trustAdaptor(address(cTokenAdaptor), 0, 0);

        daiPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(DAI), 0, 0);
        cDAIPosition = registry.trustPosition(address(cTokenAdaptor), false, abi.encode(address(cDAI)), 0, 0);
        usdcPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(USDC), 0, 0);
        cUSDCPosition = registry.trustPosition(address(cTokenAdaptor), false, abi.encode(address(cUSDC)), 0, 0);

        // address[] memory positions = new address[](5);
        // positions[0] = address(aUSDC);
        // positions[1] = address(dWETH);
        // positions[2] = address(WETH);
        // positions[3] = address(dCVX);
        // positions[4] = address(CVX);

        positions[0] = cDAIPosition;
        positions[1] = daiPosition;
        positions[2] = cUSDCPosition;
        positions[3] = usdcPosition;

        bytes[] memory positionConfigs = new bytes[](4);

        cellar = new MockCellar(
            registry,
            DAI,
            positions,
            positionConfigs,
            "Compound Lending Cellar",
            "COMP-CLR",
            address(0)
        );

        cellar.setupAdaptor(address(cTokenAdaptor));

        DAI.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testDeposit() external {
        uint256 assets = 100e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqRel(
            cDAI.balanceOf(address(cellar)).mulDivDown(cDAI.exchangeRateStored(), 1e18),
            assets,
            0.001e18,
            "Assets should have been deposited into Compound."
        );
    }

    function testWithdraw() external {
        uint256 assets = 100e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        deal(address(DAI), address(this), 0);
        uint256 amountToWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(amountToWithdraw, address(this), address(this));

        assertEq(DAI.balanceOf(address(this)), amountToWithdraw, "Amount withdrawn should equal callers DAI balance.");
    }

    function testTotalAssets() external {
        uint256 assets = 1_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqRel(cellar.totalAssets(), assets, 0.0002e18, "Total assets should equal assets deposited.");

        // Swap from DAI to USDC and lend USDC on Compound.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](3);
        adaptorCalls[0] = _createBytesDataToWithdraw(cDAI, assets / 2);
        adaptorCalls[1] = _createBytesDataForSwap(DAI, USDC, 100, assets / 2);
        adaptorCalls[2] = _createBytesDataToLend(cUSDC, type(uint256).max);

        data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Account for 0.1% Swap Fee.
        assets = assets - assets.mulDivDown(0.001e18, 2e18);
        // Make sure Total Assets is reasonable.
        assertApproxEqRel(
            cellar.totalAssets(),
            assets,
            0.0002e18,
            "Total assets should equal assets deposited minus swap fees."
        );
    }

    function testClaimComp() external {
        uint256 assets = 10_000e18;
        deal(address(DAI), address(this), assets);
        cellar.deposit(assets, address(this));

        // Have this test contract mint cDAI to accrue COMP rewards.
        deal(address(DAI), address(this), assets);
        DAI.approve(address(cDAI), assets);
        cDAI.mint(assets);

        vm.roll(block.number + 1_000);

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](3);
        adaptorCalls[0] = _createBytesDataToClaimComp();
        adaptorCalls[1] = _createBytesDataForSwap(COMP, WETH, 3000, 0.00005e18);
        adaptorCalls[2] = _createBytesDataForSwap(WETH, DAI, 3000, 0.000001e18);

        data[0] = Cellar.AdaptorCall({ adaptor: address(cTokenAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
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
        bytes memory params = abi.encode(path, poolFees, fromAmount, 0);
        return
            abi.encodeWithSelector(BaseAdaptor.swap.selector, from, to, fromAmount, SwapRouter.Exchange.UNIV3, params);
    }

    function _createBytesDataToLend(CErc20 market, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.depositToCompound.selector, market, amountToLend);
    }

    function _createBytesDataToWithdraw(CErc20 market, uint256 amountToWithdraw) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.withdrawFromCompound.selector, market, amountToWithdraw);
    }

    function _createBytesDataToClaimComp() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.claimComp.selector);
    }

    function _createBytesDataForClaimCompAndSwap(
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
        return abi.encodeWithSelector(CTokenAdaptor.claimCompAndSwap.selector, to, SwapRouter.Exchange.UNIV3, params);
    }

    // function _createBytesDataToBorrow(ERC20 debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
    //     return abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    // }

    // function _createBytesDataToRepay(ERC20 tokenToRepay, uint256 amountToRepay) internal pure returns (bytes memory) {
    //     return abi.encodeWithSelector(AaveDebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
    // }

    // function _createBytesDataToSwapAndRepay(
    //     ERC20 from,
    //     ERC20 to,
    //     uint24 fee,
    //     uint256 amount
    // ) internal pure returns (bytes memory) {
    //     address[] memory path = new address[](2);
    //     path[0] = address(from);
    //     path[1] = address(to);
    //     uint24[] memory poolFees = new uint24[](1);
    //     poolFees[0] = fee;
    //     bytes memory params = abi.encode(path, poolFees, amount, 0);
    //     return
    //         abi.encodeWithSelector(
    //             AaveDebtTokenAdaptor.swapAndRepay.selector,
    //             from,
    //             to,
    //             amount,
    //             SwapRouter.Exchange.UNIV3,
    //             params
    //         );
    // }

    // function _createBytesDataToFlashLoan(
    //     address[] memory loanToken,
    //     uint256[] memory loanAmount,
    //     bytes memory params
    // ) internal pure returns (bytes memory) {
    //     return abi.encodeWithSelector(AaveDebtTokenAdaptor.flashLoan.selector, loanToken, loanAmount, params);
    // }
}
