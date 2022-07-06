// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CellarRouter } from "src/CellarRouter.sol";
import { IUniswapV3Router } from "src/interfaces/IUniswapV3Router.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";
import { IGravity } from "src/interfaces/IGravity.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockExchange, MockPriceRouter } from "src/mocks/MockExchange.sol";
import { MockCellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, SwapRouter, IGravity } from "src/base/Cellar.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

// solhint-disable-next-line max-states-count
contract CellarRouterTest is Test {
    using Math for uint256;

    MockERC20 private ABC;
    MockERC20 private XYZ;
    MockPriceRouter private priceRouter;
    MockExchange private exchange;
    MockGravity private gravity;
    Registry private registry;
    SwapRouter private swapRouter;
    SwapRouter private realSwapRouter;

    MockERC4626 private cellar;
    MockCellar private multiCellar; //cellar with multiple assets
    CellarRouter private router;

    MockERC4626 private forkedCellar;

    address private immutable owner = vm.addr(0xBEEF);

    // Mainnet contracts:
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    ERC20 private constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    ERC20 private constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    MockERC4626 private usdcCLR;

    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    MockERC4626 private wethCLR;

    ERC20 private constant WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    MockERC4626 private wbtcCLR;

    function setUp() public {
        usdcCLR = new MockERC4626(USDC, "USDC Cellar LP Token", "USDC-CLR", 6);
        vm.label(address(usdcCLR), "usdcCLR");

        wethCLR = new MockERC4626(WETH, "WETH Cellar LP Token", "WETH-CLR", 18);
        vm.label(address(wethCLR), "wethCLR");

        wbtcCLR = new MockERC4626(WBTC, "WBTC Cellar LP Token", "WBTC-CLR", 8);
        vm.label(address(wbtcCLR), "wbtcCLR");

        priceRouter = new MockPriceRouter();
        exchange = new MockExchange(priceRouter);

        swapRouter = new SwapRouter(IUniswapV2Router(address(exchange)), IUniswapV3Router(address(exchange)));
        realSwapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(
            // Set this contract to the Gravity Bridge for testing to give the permissions usually
            // given to the Gravity Bridge to this contract.
            address(this),
            address(swapRouter),
            address(priceRouter)
        );

        router = new CellarRouter(IUniswapV3Router(address(exchange)), IUniswapV2Router(address(exchange)), registry);
        //forkedRouter = new CellarRouter(IUniswapV3Router(uniV3Router), IUniswapV2Router(uniV2Router), registry);

        ABC = new MockERC20("ABC", 18);
        XYZ = new MockERC20("XYZ", 18);

        // Set up exchange rates:
        priceRouter.setExchangeRate(ERC20(address(ABC)), ERC20(address(XYZ)), 1e18);
        priceRouter.setExchangeRate(ERC20(address(XYZ)), ERC20(address(ABC)), 1e18);
        priceRouter.setExchangeRate(USDC, USDC, 1e6);
        priceRouter.setExchangeRate(WETH, WETH, 1e18);
        priceRouter.setExchangeRate(WBTC, WBTC, 1e8);
        priceRouter.setExchangeRate(USDC, WETH, 0.0005e18);
        priceRouter.setExchangeRate(WETH, USDC, 2000e6);
        priceRouter.setExchangeRate(USDC, WBTC, 0.000033e8);
        priceRouter.setExchangeRate(WBTC, USDC, 30_000e6);
        priceRouter.setExchangeRate(WETH, WBTC, 0.06666666e8);
        priceRouter.setExchangeRate(WBTC, WETH, 15e18);

        // Set up two cellars:
        cellar = new MockERC4626(ERC20(address(ABC)), "ABC Cellar", "abcCLR", 18);
        forkedCellar = new MockERC4626(ERC20(address(WETH)), "WETH Cellar", "WETHCLR", 18); // For mainnet fork test.

        address[] memory positions = new address[](4);
        positions[0] = address(USDC);
        positions[1] = address(usdcCLR);
        positions[2] = address(wethCLR);
        positions[3] = address(wbtcCLR);

        Cellar.PositionType[] memory positionTypes = new Cellar.PositionType[](4);
        positionTypes[0] = Cellar.PositionType.ERC20;
        positionTypes[1] = Cellar.PositionType.ERC4626;
        positionTypes[2] = Cellar.PositionType.ERC4626;
        positionTypes[3] = Cellar.PositionType.ERC4626;

        multiCellar = new MockCellar(
            registry,
            USDC,
            positions,
            positionTypes,
            address(USDC),
            Cellar.WithdrawType.ORDERLY,
            "Multiposition Cellar LP Token",
            "multiposition-CLR"
        );
        vm.label(address(cellar), "cellar");

        // Mint enough liquidity to swap router for swaps.
        deal(address(USDC), address(exchange), type(uint224).max);
        deal(address(WETH), address(exchange), type(uint224).max);
        deal(address(WBTC), address(exchange), type(uint224).max);

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        WETH.approve(address(cellar), type(uint256).max);
        WBTC.approve(address(cellar), type(uint256).max);
    }

    // ======================================= DEPOSIT TESTS =======================================

    function testDepositAndSwap(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Mint liquidity for swap.
        ABC.mint(address(exchange), 2 * assets);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(XYZ);
        path[1] = address(ABC);

        // Test deposit and swap.
        vm.startPrank(owner);
        XYZ.approve(address(router), assets);
        XYZ.mint(owner, assets);
        bytes memory swapData = abi.encode(path, assets, 0);
        uint256 shares = router.depositAndSwap(
            Cellar(address(cellar)),
            SwapRouter.Exchange.UNIV2,
            swapData,
            assets,
            owner,
            XYZ
        );
        vm.stopPrank();

        // Assets received by the cellar will be different from the amount of assets a user attempted
        // to deposit due to slippage swaps.
        uint256 assetsReceived = exchange.quote(assets, path);

        // Run test.
        assertEq(shares, assetsReceived, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assetsReceived), shares, "Withdrawing assets should burn shares given.");
        assertEq(cellar.previewDeposit(assetsReceived), shares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assetsReceived, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(owner), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(owner)), assetsReceived, "Should return all user's assets.");
        assertEq(XYZ.balanceOf(owner), 0, "Should have deposited assets from user.");
    }

    function testDepositAndSwapUsingUniswapV2OnMainnet(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        registry.setAddress(1, address(realSwapRouter)); // use the real swap router for this test

        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);

        // Test deposit and swap.
        vm.startPrank(owner);
        deal(address(DAI), owner, assets, true);
        DAI.approve(address(router), assets);
        bytes memory swapData = abi.encode(path, assets, 0);
        uint256 shares = router.depositAndSwap(
            Cellar(address(forkedCellar)),
            SwapRouter.Exchange.UNIV2,
            swapData,
            assets,
            owner,
            DAI
        );
        vm.stopPrank();

        // Assets received by the cellar will be equal to WETH currently in forked cellar because no
        // other deposits have been made.
        uint256 assetsReceived = WETH.balanceOf(address(forkedCellar));

        // Run test.
        assertEq(shares, assetsReceived, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(forkedCellar.previewWithdraw(assetsReceived), shares, "Withdrawing assets should burn shares given.");
        assertEq(forkedCellar.previewDeposit(assetsReceived), shares, "Depositing assets should mint shares given.");
        assertEq(forkedCellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(forkedCellar.totalAssets(), assetsReceived, "Should have updated total assets with assets deposited.");
        assertEq(forkedCellar.balanceOf(owner), shares, "Should have updated user's share balance.");
        assertEq(
            forkedCellar.convertToAssets(forkedCellar.balanceOf(owner)),
            assetsReceived,
            "Should return all user's assets."
        );
        assertEq(DAI.balanceOf(owner), 0, "Should have deposited assets from user.");
    }

    function testDepositAndSwapUsingUniswapV3OnMainnet(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        registry.setAddress(1, address(realSwapRouter)); // use the real swap router for this test

        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);

        // Specify the pool fee tiers to use for each swap, 0.3% for DAI <-> WETH.
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        // Test deposit and swap.
        vm.startPrank(owner);
        deal(address(DAI), owner, assets, true);
        DAI.approve(address(router), assets);
        bytes memory swapData = abi.encode(path, poolFees, assets, 0);
        uint256 shares = router.depositAndSwap(
            Cellar(address(forkedCellar)),
            SwapRouter.Exchange.UNIV3,
            swapData,
            assets,
            owner,
            DAI
        );
        vm.stopPrank();

        // Assets received by the cellar will be equal to WETH currently in forked cellar because no
        // other deposits have been made.
        uint256 assetsReceived = WETH.balanceOf(address(forkedCellar));

        // Run test.
        assertEq(shares, assetsReceived, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(forkedCellar.previewWithdraw(assetsReceived), shares, "Withdrawing assets should burn shares given.");
        assertEq(forkedCellar.previewDeposit(assetsReceived), shares, "Depositing assets should mint shares given.");
        assertEq(forkedCellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(forkedCellar.totalAssets(), assetsReceived, "Should have updated total assets with assets deposited.");
        assertEq(forkedCellar.balanceOf(owner), shares, "Should have updated user's share balance.");
        assertEq(
            forkedCellar.convertToAssets(forkedCellar.balanceOf(owner)),
            assetsReceived,
            "Should return all user's assets."
        );
        assertEq(DAI.balanceOf(owner), 0, "Should have deposited assets from user.");
    }

    // ======================================= WITHDRAW TESTS =======================================

    function testWithdrawAndSwap() external {
        multiCellar.depositIntoPosition(address(wethCLR), 1e18);
        multiCellar.depositIntoPosition(address(wbtcCLR), 1e8);

        assertEq(multiCellar.totalAssets(), 32_000e6, "Should have updated total assets with assets deposited.");

        // Mint shares to user to redeem.
        deal(address(multiCellar), address(this), multiCellar.previewWithdraw(32_000e6));

        // Encode swaps.
        // Swap 1: 0.2 WETH -> WBTC.
        // Swap 2: 0.8 WETH -> USDC.
        SwapRouter.Exchange[] memory exchanges = new SwapRouter.Exchange[](2);
        exchanges[0] = SwapRouter.Exchange.UNIV2;
        exchanges[1] = SwapRouter.Exchange.UNIV2;

        address[][] memory paths = new address[][](2);
        paths[0] = new address[](2);
        paths[0][0] = address(WETH);
        paths[0][1] = address(WBTC);

        paths[1] = new address[](2);
        paths[1][0] = address(WETH);
        paths[1][1] = address(USDC);

        bytes[] memory swapData = new bytes[](2);
        swapData[0] = abi.encode(paths[0], 0.2e18, 0);
        swapData[1] = abi.encode(paths[1], 0.8e18, 0);

        multiCellar.approve(address(router), type(uint256).max);
        router.withdrawAndSwap(multiCellar, exchanges, swapData, 32_000e6, address(this));

        assertEq(WETH.balanceOf(address(this)), 0, "Should receive no WETH.");
        assertGt(WBTC.balanceOf(address(this)), 0, "Should receive WBTC");
        assertGt(USDC.balanceOf(address(this)), 0, "Should receive USDC");
        assertEq(WETH.allowance(address(router), address(swapRouter)), 0, "Should have no WETH allowances.");
        assertEq(WBTC.allowance(address(router), address(swapRouter)), 0, "Should have no WBTC allowances.");
        assertEq(USDC.allowance(address(router), address(swapRouter)), 0, "Should have no USDC allowances.");
    }
}
