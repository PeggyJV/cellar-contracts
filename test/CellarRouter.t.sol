// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CellarRouter } from "src/CellarRouter.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IGravity } from "src/interfaces/external/IGravity.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockCellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, SwapRouter, IGravity } from "src/base/Cellar.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";

import { Test } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

/**
 * Security wise since this contract stores no user funds, and keeps track of no state, we aren't really concerned with re-entrancy attacks,
 * or any attacks that try to extract value from this contract(since there is no value in it). This being said the biggest security concern
 * is attackers being able to exploit users ERC20 approvals, and attackers  exploiting users shares, either by minting them to their address,
 * or redeeming them for themselves.
 *
 * To mitigate attackers exploiting users ERC20 approvals, this contract always calls `safeTransferFrom` with the `from` address as `msg.sender`
 *
 * As for attackers exploiting users shares by minting them to themselves, `receiver` is an input to the deposit functions, which isolates the risk to a malicious front-end
 * which is already a risk in the existing cellar architecture so we can accept it and not mitigate it.
 *
 * As for attackers exploiting users by redeeming users shares, the `owner` address(which is the address the cellar will burn shares from) is always `msg.sender`
 *
 * @notice if a user sent funds to this contract by accident, anyone would be able to "steal" them either on purpose or by accident. We will accept this risk
 * because users have to make a big and unlikely mistake in order for attackers to exploit this.
 */
// solhint-disable-next-line max-states-count
contract CellarRouterTest is Test {
    using Math for uint256;

    MockGravity private gravity;
    Registry private registry;
    SwapRouter private swapRouter;
    PriceRouter private priceRouter;

    MockCellar private cellar; //cellar with multiple assets
    CellarRouter private router;

    address private immutable owner = vm.addr(0xBEEF);

    // Mainnet contracts:
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ERC20 private constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    function setUp() public {
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(
            // Set this contract to the Gravity Bridge for testing to give the permissions usually
            // given to the Gravity Bridge to this contract.
            address(this),
            address(swapRouter),
            address(priceRouter)
        );

        router = new CellarRouter(registry);

        // Set up exchange rates:
        priceRouter.addAsset(USDC, ERC20(address(0)), 0, 0, 0);
        priceRouter.addAsset(DAI, ERC20(address(0)), 0, 0, 0);
        priceRouter.addAsset(WETH, ERC20(address(Denominations.ETH)), 0, 0, 0);
        priceRouter.addAsset(WBTC, ERC20(address(Denominations.BTC)), 0, 0, 0);

        address[] memory positions = new address[](4);
        positions[0] = address(USDC);
        positions[1] = address(DAI);
        positions[2] = address(WETH);
        positions[3] = address(WBTC);

        Cellar.PositionType[] memory positionTypes = new Cellar.PositionType[](4);
        positionTypes[0] = Cellar.PositionType.ERC20;
        positionTypes[1] = Cellar.PositionType.ERC20;
        positionTypes[2] = Cellar.PositionType.ERC20;
        positionTypes[3] = Cellar.PositionType.ERC20;

        cellar = new MockCellar(
            registry,
            USDC,
            positions,
            positionTypes,
            address(USDC),
            Cellar.WithdrawType.ORDERLY,
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            address(0)
        );
        vm.label(address(cellar), "cellar");

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        WETH.approve(address(cellar), type(uint256).max);
        WBTC.approve(address(cellar), type(uint256).max);
    }

    // ======================================= DEPOSIT TESTS =======================================

    function testDepositAndSwapUsingUniswapV2(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);

        // Test deposit and swap.
        deal(address(DAI), address(this), assets);
        DAI.approve(address(router), assets);
        bytes memory swapData = abi.encode(path, assets, 0);
        uint256 shares = router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV2, swapData, assets, address(this), DAI);

        // Assets received by the cellar will be equal to WETH currently in forked cellar because no
        // other deposits have been made.
        uint256 assetsReceived = USDC.balanceOf(address(cellar));

        // Run test.
        assertEq(shares, assetsReceived.changeDecimals(6, 18), "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assetsReceived), shares, "Withdrawing assets should burn shares given.");
        assertEq(cellar.previewDeposit(assetsReceived), shares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assetsReceived, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(
            cellar.convertToAssets(cellar.balanceOf(address(this))),
            assetsReceived,
            "Should return all user's assets."
        );
        assertEq(DAI.balanceOf(address(this)), 0, "Should have deposited assets from user.");
    }

    function testDepositAndSwapUsingUniswapV3(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](3);
        path[0] = address(DAI);
        path[1] = address(WETH);
        path[2] = address(USDC);

        // Specify the pool fee tiers to use for each swap, 0.3% for DAI <-> WETH.
        uint24[] memory poolFees = new uint24[](2);
        poolFees[0] = 3000;
        poolFees[1] = 3000;

        // Test deposit and swap.
        deal(address(DAI), address(this), assets);
        DAI.approve(address(router), assets);
        bytes memory swapData = abi.encode(path, poolFees, assets, 0);
        uint256 shares = router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV3, swapData, assets, address(this), DAI);

        // Assets received by the cellar will be equal to WETH currently in forked cellar because no
        // other deposits have been made.
        uint256 assetsReceived = USDC.balanceOf(address(cellar));

        // Run test.
        assertEq(shares, assetsReceived.changeDecimals(6, 18), "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assetsReceived), shares, "Withdrawing assets should burn shares given.");
        assertEq(cellar.previewDeposit(assetsReceived), shares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assetsReceived, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(
            cellar.convertToAssets(cellar.balanceOf(address(this))),
            assetsReceived,
            "Should return all user's assets."
        );
        assertEq(DAI.balanceOf(address(this)), 0, "Should have deposited assets from user.");
    }

    function testDepositWithAssetInDifferentFromPath() external {
        uint256 assets = 100e18;

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);

        // Give user USDC.
        deal(address(USDC), address(this), assets);

        // Test deposit and swap.
        deal(address(DAI), address(this), assets);
        DAI.approve(address(router), assets);
        bytes memory swapData = abi.encode(path, assets, 0);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        // Specify USDC as assetIn when it should be DAI.
        router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV2, swapData, assets, address(this), USDC);
    }

    function testDepositWithAssetAmountMisMatch() external {
        uint256 assets = 100e18;

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);

        // Previously a user sent DAI to the router on accident.
        deal(address(DAI), address(router), assets);
        bytes memory swapData = abi.encode(path, assets, 0);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        // Specify 0 for assets. Should revert since swap router is approved to spend 0 tokens from router.
        router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV2, swapData, 0, address(this), DAI);

        // Reset routers DAI balance.
        deal(address(DAI), address(router), 0);

        // Give user some DAI.
        deal(address(DAI), address(this), assets);
        DAI.approve(address(router), assets);

        // User calls deposit and swap but specifies a lower amount in swapData then actual.
        swapData = abi.encode(path, assets / 2, 0);
        router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV2, swapData, assets, address(this), DAI);

        assertEq(DAI.balanceOf(address(this)), assets / 2, "Caller should have been sent back their remaining assets.");
    }

    // ======================================= WITHDRAW TESTS =======================================

    function testWithdrawAndSwap() external {
        // Set performance fees to zero, so test is not dependent to price movements.
        cellar.setPerformanceFee(0);

        // Deposit initial funds into cellar.
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));

        // Distribute funds into WETH and WBTC.
        deal(address(WETH), address(cellar), 3e18);
        deal(address(WBTC), address(cellar), 0.3e8);
        deal(address(USDC), address(cellar), 0);

        // Encode swaps.
        // Swap 1: 1.5 WETH -> USDC on V2.
        // Swap 1: 1.5 WETH -> WBTC on V3.
        // Swap 2: 0.3 WBTC -> USDC on V2.
        SwapRouter.Exchange[] memory exchanges = new SwapRouter.Exchange[](3);
        exchanges[0] = SwapRouter.Exchange.UNIV2;
        exchanges[1] = SwapRouter.Exchange.UNIV3;
        exchanges[2] = SwapRouter.Exchange.UNIV2;

        address[][] memory paths = new address[][](3);
        paths[0] = new address[](2);
        paths[0][0] = address(WETH);
        paths[0][1] = address(USDC);

        paths[1] = new address[](2);
        paths[1][0] = address(WETH);
        paths[1][1] = address(WBTC);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3% fee.

        paths[2] = new address[](2);
        paths[2][0] = address(WBTC);
        paths[2][1] = address(USDC);

        bytes[] memory swapData = new bytes[](3);
        swapData[0] = abi.encode(paths[0], 1.5e18, 0);
        swapData[1] = abi.encode(paths[1], poolFees, 1.5e18, 0);
        swapData[2] = abi.encode(paths[2], 0.3e8, 0);

        cellar.approve(address(router), type(uint256).max);
        router.withdrawAndSwap(cellar, exchanges, swapData, cellar.totalAssets(), address(this));

        assertEq(WETH.balanceOf(address(this)), 0, "Should receive no WETH.");
        assertGt(WBTC.balanceOf(address(this)), 0, "Should receive WBTC");
        assertGt(USDC.balanceOf(address(this)), 0, "Should receive USDC");
        assertEq(WETH.balanceOf(address(router)), 0, "Router Should receive no WETH.");
        assertEq(WBTC.balanceOf(address(router)), 0, "Router Should receive no WBTC");
        assertEq(USDC.balanceOf(address(router)), 0, "Router Should receive no USDC");
        assertEq(WETH.allowance(address(router), address(swapRouter)), 0, "Should have no WETH allowances.");
        assertEq(WBTC.allowance(address(router), address(swapRouter)), 0, "Should have no WBTC allowances.");
    }

    function testFailWithdrawWithInvalidSwapPath() external {
        // Deposit initial funds into cellar.
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));

        // Distribute funds into WETH and WBTC.
        deal(address(WETH), address(cellar), 3e18);
        deal(address(WBTC), address(cellar), 0.3e8);
        deal(address(USDC), address(cellar), 0);

        // Encode swaps with an invalid swap path
        SwapRouter.Exchange[] memory exchanges = new SwapRouter.Exchange[](3);
        exchanges[0] = SwapRouter.Exchange.UNIV2;
        exchanges[1] = SwapRouter.Exchange.UNIV3;
        exchanges[2] = SwapRouter.Exchange.UNIV2;

        address[][] memory paths = new address[][](3);
        paths[0] = new address[](2);
        paths[0][0] = address(WETH);
        paths[0][1] = address(USDC);

        paths[1] = new address[](2);
        paths[1][0] = address(WETH);
        paths[1][1] = address(0);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3% fee.

        paths[2] = new address[](2);
        paths[2][0] = address(WBTC);
        paths[2][1] = address(USDC);

        bytes[] memory swapData = new bytes[](3);
        swapData[0] = abi.encode(paths[0], 1.5e18, 0);
        swapData[1] = abi.encode(paths[1], poolFees, 1.5e18, 0);
        swapData[2] = abi.encode(paths[2], 0.3e8, 0);

        cellar.approve(address(router), type(uint256).max);
        router.withdrawAndSwap(cellar, exchanges, swapData, cellar.totalAssets(), address(this));
    }

    function testFailWithdrawWithInvalidSwapData() external {
        // Deposit initial funds into cellar.
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));

        // Distribute funds into WETH and WBTC.
        deal(address(WETH), address(cellar), 3e18);
        deal(address(WBTC), address(cellar), 0.3e8);
        deal(address(USDC), address(cellar), 0);

        // Encode swaps with an invalid swap path
        SwapRouter.Exchange[] memory exchanges = new SwapRouter.Exchange[](3);
        exchanges[0] = SwapRouter.Exchange.UNIV2;
        exchanges[1] = SwapRouter.Exchange.UNIV3;
        exchanges[2] = SwapRouter.Exchange.UNIV2;

        address[][] memory paths = new address[][](3);
        paths[0] = new address[](2);
        paths[0][0] = address(WETH);
        paths[0][1] = address(USDC);

        paths[1] = new address[](2);
        paths[1][0] = address(WETH);
        paths[1][1] = address(0);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3% fee.

        paths[2] = new address[](2);
        paths[2][0] = address(WBTC);
        paths[2][1] = address(USDC);

        bytes[] memory swapData = new bytes[](3);
        swapData[0] = abi.encode(paths[0], 1.5e18, 0);
        // Do not encode the poolFees argument.
        swapData[1] = abi.encode(paths[1], 1.5e18, 0);
        swapData[2] = abi.encode(paths[2], 0.3e8, 0);

        cellar.approve(address(router), type(uint256).max);
        router.withdrawAndSwap(cellar, exchanges, swapData, cellar.totalAssets(), address(this));
    }

    function testFailWithdrawWithInvalidMinAmountOut() external {
        // Deposit initial funds into cellar.
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));

        // Distribute funds into WETH and WBTC.
        deal(address(WETH), address(cellar), 3e18);
        deal(address(WBTC), address(cellar), 0.3e8);
        deal(address(USDC), address(cellar), 0);

        // Encode swaps with an invalid swap path
        SwapRouter.Exchange[] memory exchanges = new SwapRouter.Exchange[](3);
        exchanges[0] = SwapRouter.Exchange.UNIV2;
        exchanges[1] = SwapRouter.Exchange.UNIV3;
        exchanges[2] = SwapRouter.Exchange.UNIV2;

        address[][] memory paths = new address[][](3);
        paths[0] = new address[](2);
        paths[0][0] = address(WETH);
        paths[0][1] = address(USDC);

        paths[1] = new address[](2);
        paths[1][0] = address(WETH);
        paths[1][1] = address(0);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3% fee.

        paths[2] = new address[](2);
        paths[2][0] = address(WBTC);
        paths[2][1] = address(USDC);

        bytes[] memory swapData = new bytes[](3);
        // Encode an invalid min amount out.
        swapData[0] = abi.encode(paths[0], 1.5e18, type(uint256).max);
        swapData[1] = abi.encode(paths[1], poolFees, 1.5e18, 0);
        swapData[2] = abi.encode(paths[2], 0.3e8, 0);

        cellar.approve(address(router), type(uint256).max);
        router.withdrawAndSwap(cellar, exchanges, swapData, cellar.totalAssets(), address(this));
    }

    function testFailWithdrawWithInvalidReceiver() external {
        // Deposit initial funds into cellar.
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));

        // Distribute funds into WETH and WBTC.
        deal(address(WETH), address(cellar), 3e18);
        deal(address(WBTC), address(cellar), 0.3e8);
        deal(address(USDC), address(cellar), 0);

        // Encode swaps with an invalid swap path
        SwapRouter.Exchange[] memory exchanges = new SwapRouter.Exchange[](3);
        exchanges[0] = SwapRouter.Exchange.UNIV2;
        exchanges[1] = SwapRouter.Exchange.UNIV3;
        exchanges[2] = SwapRouter.Exchange.UNIV2;

        address[][] memory paths = new address[][](3);
        paths[0] = new address[](2);
        paths[0][0] = address(WETH);
        paths[0][1] = address(USDC);

        paths[1] = new address[](2);
        paths[1][0] = address(WETH);
        paths[1][1] = address(0);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3% fee.

        paths[2] = new address[](2);
        paths[2][0] = address(WBTC);
        paths[2][1] = address(USDC);

        bytes[] memory swapData = new bytes[](3);
        // Encode an invalid min amount out.
        swapData[0] = abi.encode(paths[0], 1.5e18, 0);
        swapData[1] = abi.encode(paths[1], poolFees, 1.5e18, 0);
        swapData[2] = abi.encode(paths[2], 0.3e8, 0);

        cellar.approve(address(router), type(uint256).max);
        router.withdrawAndSwap(cellar, exchanges, swapData, cellar.totalAssets(), address(0));
    }
}
