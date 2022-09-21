// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { IUniswapV3Router as UniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { IUniswapV2Router02 as UniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

abstract contract SwapRouterTest is Test {
    using Math for uint256;

    SwapRouter internal swapRouter;
    PriceRouter internal priceRouter;

    uint256 internal constant privateKey0 = 0xABCD;
    uint256 internal constant privateKey1 = 0xBEEF;
    address internal sender = vm.addr(privateKey0);
    address internal receiver = vm.addr(privateKey1);

    address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    ERC20 internal WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 internal DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 internal USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        /// @dev When adding a new exchange for the swap router to support, make
        ///      sure to update this.
        swapRouter = new SwapRouter(UniswapV2Router(uniV2Router), UniswapV3Router(uniV3Router));

        // Used to estimate the amount that should be received from swaps.
        priceRouter = new PriceRouter();

        priceRouter.addAsset(WETH, 0, 0, false, 0);
        priceRouter.addAsset(USDC, 0, 0, false, 0);
        priceRouter.addAsset(DAI, 0, 0, false, 0);

        vm.startPrank(sender);
    }

    // ================================= SWAP FUNCTIONS =================================

    /// @dev When implementing the functions below to perform a 1) single swap
    ///      and 2) multi-swap using one of the swap router's supported exchanges,
    ///      you do not need to mint DAI to `sender` or set approval for the
    ///      swap. This will be handled in test.

    /// @dev Define the logic for `sender` to swap from from DAI -> WETH to be
    ///      received by `receiver using the swap router.
    function _doSwap(uint256 assets) internal virtual returns (uint256 received);

    /// @dev Define the logic for `sender` to swap from from DAI -> WETH -> USDC
    ///      to be received by `receiver using the swap router.
    function _doMultiSwap(uint256 assets) internal virtual returns (uint256 received);

    // ==================================== SWAP TEST ====================================

    function _testSwap(uint256 assets, function(uint256) internal returns (uint256) _swap) internal {
        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets);
        uint256 received = _swap(assets);

        // Estimate approximate amount that should of been received.
        uint256 expectedReceived = priceRouter.getValue(DAI, assets, WETH);

        assertEq(DAI.balanceOf(sender), 0, "Should have swapped all DAI");
        assertEq(DAI.balanceOf(address(swapRouter)), 0, "Router should not have a DAI balance.");
        assertEq(USDC.balanceOf(address(swapRouter)), 0, "Router should not have a USDC balance.");
        assertApproxEqRel(WETH.balanceOf(receiver), expectedReceived, 0.05e18, "Should have received USDC");
        assertEq(received, WETH.balanceOf(receiver), "Should return correct amount received");
    }

    function testSingleSwap(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        _testSwap(assets, _doSwap);
    }

    function testMultiSwap(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        _testSwap(assets, _doMultiSwap);
    }

    function testSwapWithoutEnoughAssets() external {
        uint256 assets = 100e18;

        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        _doSwap(assets * 2);
    }

    function testSwapWithoutEnoughApproved() external {
        uint256 assets = 100e18;

        deal(address(DAI), sender, assets, true);
        DAI.approve(address(swapRouter), assets / 2);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        _doSwap(assets);
    }

    function testInvalidSwapData() external {
        vm.expectRevert(SwapRouter.SwapRouter__SwapReverted.selector);
        swapRouter.swap(SwapRouter.Exchange.UNIV2, abi.encode(0), receiver, ERC20(address(0)), ERC20(address(0)));
    }
}

contract UniswapV2SwapRouterTest is SwapRouterTest {
    function _doSwap(uint256 assets) internal override returns (uint256 received) {
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);

        bytes memory swapData = abi.encode(path, assets, 0);
        received = swapRouter.swap(SwapRouter.Exchange.UNIV2, swapData, receiver, DAI, WETH);
    }

    function _doMultiSwap(uint256 assets) internal override returns (uint256 received) {
        address[] memory path = new address[](3);
        path[0] = address(DAI);
        path[1] = address(USDC);
        path[2] = address(WETH);

        bytes memory swapData = abi.encode(path, assets, 0);
        received = swapRouter.swap(SwapRouter.Exchange.UNIV2, swapData, receiver, DAI, WETH);
    }
}

contract UniswapV3SwapRouterTest is SwapRouterTest {
    function _doSwap(uint256 assets) internal override returns (uint256 received) {
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);

        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3%

        bytes memory swapData = abi.encode(path, poolFees, assets, 0);
        received = swapRouter.swap(SwapRouter.Exchange.UNIV3, swapData, receiver, DAI, WETH);
    }

    function _doMultiSwap(uint256 assets) internal override returns (uint256 received) {
        address[] memory path = new address[](3);
        path[0] = address(DAI);
        path[1] = address(USDC);
        path[2] = address(WETH);

        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 100; // 0.01%
        poolFees[1] = 3000; // 0.3%

        bytes memory swapData = abi.encode(path, poolFees, assets, 0);
        received = swapRouter.swap(SwapRouter.Exchange.UNIV3, swapData, receiver, DAI, WETH);
    }
}
