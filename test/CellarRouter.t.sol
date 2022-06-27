// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CellarRouter } from "src/CellarRouter.sol";
import { IUniswapV3Router } from "src/interfaces/IUniswapV3Router.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockExchange, MockPriceRouter } from "src/mocks/MockExchange.sol";
import { MockCellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, SwapRouter, IGravity } from "src/Registry.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarRouterTest is Test {
    using Math for uint256;

    MockERC20 private ABC;
    MockERC20 private XYZ;
    MockPriceRouter private priceRouter;
    MockExchange private exchange;
    MockGravity private gravity;
    Registry private registry;
    SwapRouter private swapRouter;

    MockERC4626 private cellar;
    MockCellar private multiCellar; //cellar with multiple assets
    CellarRouter private router;

    MockERC4626 private forkedCellar;
    CellarRouter private forkedRouter;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    uint256 private constant privateKey = 0xBEEF;
    address private owner = vm.addr(privateKey);

    // Mainnet contracts:
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    MockERC4626 private usdcCLR;

    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    MockERC4626 private wethCLR;

    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
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

        router = new CellarRouter(IUniswapV3Router(address(exchange)), IUniswapV2Router(address(exchange)));
        forkedRouter = new CellarRouter(IUniswapV3Router(uniV3Router), IUniswapV2Router(uniV2Router));
        swapRouter = new SwapRouter(IUniswapV2Router(address(exchange)), IUniswapV3Router(address(exchange)));
        gravity = new MockGravity();

        registry = new Registry(
            SwapRouter(address(swapRouter)),
            PriceRouter(address(priceRouter)),
            IGravity(address(gravity))
        );

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

        address[] memory positions = new address[](3);
        positions[0] = address(usdcCLR);
        positions[1] = address(wethCLR);
        positions[2] = address(wbtcCLR);

        multiCellar = new MockCellar(registry, USDC, positions, "Multiposition Cellar LP Token", "multiposition-CLR");
        vm.label(address(cellar), "cellar");

        // Transfer ownership to this contract for testing.
        vm.prank(address(registry.gravityBridge()));
        multiCellar.transferOwnership(address(this));

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

    function testDepositAndSwapIntoCellar(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Mint liquidity for swap.
        ABC.mint(address(exchange), 2 * assets);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(XYZ);
        path[1] = address(ABC);

        // Specify the pool fee tiers to use for each swap (none).
        uint24[] memory poolFees;

        // Test deposit and swap.
        vm.startPrank(owner);
        XYZ.approve(address(router), assets);
        XYZ.mint(owner, assets);
        uint256 shares = router.depositAndSwapIntoCellar(Cellar(address(cellar)), path, poolFees, assets, 0, owner);
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

    function testDepositAndSwapIntoCellarUsingUniswapV2OnMainnet(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);

        // Specify the pool fee tiers to use for each swap (none).
        uint24[] memory poolFees;

        // Test deposit and swap.
        vm.startPrank(owner);
        deal(address(DAI), owner, assets, true);
        DAI.approve(address(forkedRouter), assets);
        uint256 shares = forkedRouter.depositAndSwapIntoCellar(
            Cellar(address(forkedCellar)),
            path,
            poolFees,
            assets,
            0,
            owner
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

    function testDepositAndSwapIntoCellarUsingUniswapV3OnMainnet(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

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
        DAI.approve(address(forkedRouter), assets);
        uint256 shares = forkedRouter.depositAndSwapIntoCellar(
            Cellar(address(forkedCellar)),
            path,
            poolFees,
            assets,
            0,
            owner
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

    function testWithdrawAndSwapFromCellar(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Mint liquidity for swap.
        ABC.mint(address(exchange), 2 * assets);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(XYZ);
        path[1] = address(ABC);

        // Specify the pool fee tiers to use for each swap (none).
        uint24[] memory poolFees;

        // Deposit and swap
        vm.startPrank(owner);
        XYZ.approve(address(router), assets);
        XYZ.mint(owner, assets);
        router.depositAndSwapIntoCellar(Cellar(address(cellar)), path, poolFees, assets, 0, owner);

        // Assets received by the cellar will be different from the amount of assets a user attempted
        // to deposit due to slippage swaps.
        uint256 assetsReceivedAfterDeposit = exchange.quote(assets, path);

        // Reverse the swap path.
        (path[0], path[1]) = (path[1], path[0]);

        // Test withdraw and swap.
        cellar.approve(address(router), assetsReceivedAfterDeposit);
        uint256 sharesRedeemed = router.withdrawAndSwapFromCellar(
            Cellar(address(cellar)),
            path,
            poolFees,
            assetsReceivedAfterDeposit,
            0,
            owner
        );
        vm.stopPrank();

        uint256 assetsReceivedAfterWithdraw = exchange.quote(assetsReceivedAfterDeposit, path);

        // Run test.
        assertEq(sharesRedeemed, assetsReceivedAfterDeposit, "Should have 1:1 exchange rate.");
        assertEq(cellar.totalSupply(), 0, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), 0, "Should have updated total assets into account the withdrawn assets.");
        assertEq(cellar.balanceOf(owner), 0, "Should have updated user's share balance.");
        assertEq(XYZ.balanceOf(owner), assetsReceivedAfterWithdraw, "Should have withdrawn assets to the user.");
    }

    function testWithdrawFromPositionsIntoSingleAssetWTwoSwaps() external {
        multiCellar.depositIntoPosition(address(wethCLR), 1e18);
        multiCellar.depositIntoPosition(address(wbtcCLR), 1e8);

        assertEq(multiCellar.totalAssets(), 32_000e6, "Should have updated total assets with assets deposited.");

        // Mint shares to user to redeem.
        deal(address(multiCellar), address(this), multiCellar.previewWithdraw(32_000e6));

        //create paths
        address[][] memory paths = new address[][](2);
        paths[0] = new address[](2);
        paths[0][0] = address(WETH);
        paths[0][1] = address(USDC);
        paths[1] = new address[](2);
        paths[1][0] = address(WBTC);
        paths[1][1] = address(USDC);
        uint24[][] memory poolFees = new uint24[][](2);
        poolFees[0] = new uint24[](0);
        poolFees[1] = new uint24[](0);
        uint256 assets = 32_000e6;
        uint256[] memory minOuts = new uint256[](2);
        minOuts[0] = 0;
        minOuts[1] = 0;

        uint256[] memory assetsIn = new uint256[](2);
        assetsIn[0] = 1e18;
        assetsIn[1] = 1e8;

        multiCellar.approve(address(router), type(uint256).max);
        router.withdrawFromPositionsIntoSingleAsset(
            multiCellar,
            paths,
            poolFees,
            assets,
            assetsIn,
            minOuts,
            address(this)
        );

        assertEq(USDC.balanceOf(address(this)), 30_400e6, "Did not recieve expected assets");
    }

    /**
     * @notice if the asset wanted is an asset given, then it should just be added to the output with no swaps needed
     */
    function testWithdrawFromPositionsIntoSingleAssetWOneSwap() external {
        multiCellar.depositIntoPosition(address(wethCLR), 1e18);
        multiCellar.depositIntoPosition(address(wbtcCLR), 1e8);

        assertEq(multiCellar.totalAssets(), 32_000e6, "Should have updated total assets with assets deposited.");

        // Mint shares to user to redeem.
        deal(address(multiCellar), address(this), multiCellar.previewWithdraw(32_000e6));

        //create paths
        address[][] memory paths = new address[][](2);
        paths[0] = new address[](1);
        paths[0][0] = address(WETH);
        paths[1] = new address[](2);
        paths[1][0] = address(WBTC);
        paths[1][1] = address(WETH);
        uint24[][] memory poolFees = new uint24[][](2);
        poolFees[0] = new uint24[](0);
        poolFees[1] = new uint24[](0);
        uint256 assets = 32_000e6;
        uint256[] memory minOuts = new uint256[](2);
        minOuts[0] = 0;
        minOuts[1] = 0;

        uint256[] memory assetsIn = new uint256[](2);
        assetsIn[0] = 1e18;
        assetsIn[1] = 1e8;

        multiCellar.approve(address(router), type(uint256).max);
        router.withdrawFromPositionsIntoSingleAsset(
            multiCellar,
            paths,
            poolFees,
            assets,
            assetsIn,
            minOuts,
            address(this)
        );
        assertEq(WETH.balanceOf(address(this)), 15.25e18, "Did not recieve expected assets");
    }

    function testWithdrawFromPositionsIntoSingleAssetWFourSwaps() external {
        multiCellar.depositIntoPosition(address(wethCLR), 1e18);
        multiCellar.depositIntoPosition(address(wbtcCLR), 1e8);

        assertEq(multiCellar.totalAssets(), 32_000e6, "Should have updated total assets with assets deposited.");

        // Mint shares to user to redeem.
        deal(address(multiCellar), address(this), multiCellar.previewWithdraw(32_000e6));

        //create paths
        address[][] memory paths = new address[][](4);
        paths[0] = new address[](2);
        paths[0][0] = address(WETH);
        paths[0][1] = address(USDC);
        paths[1] = new address[](2);
        paths[1][0] = address(WBTC);
        paths[1][1] = address(USDC);
        paths[2] = new address[](2);
        paths[2][0] = address(WETH);
        paths[2][1] = address(USDC);
        paths[3] = new address[](2);
        paths[3][0] = address(WBTC);
        paths[3][1] = address(USDC);
        uint24[][] memory poolFees = new uint24[][](4);
        poolFees[0] = new uint24[](0);
        poolFees[1] = new uint24[](0);
        poolFees[2] = new uint24[](0);
        poolFees[3] = new uint24[](0);
        uint256 assets = 32_000e6;
        uint256[] memory minOuts = new uint256[](4);
        minOuts[0] = 0;
        minOuts[1] = 0;
        minOuts[2] = 0;
        minOuts[3] = 0;

        uint256[] memory assetsIn = new uint256[](4);
        assetsIn[0] = 0.5e18;
        assetsIn[1] = 0.5e8;
        assetsIn[2] = 0.5e18;
        assetsIn[3] = 0.5e8;

        multiCellar.approve(address(router), type(uint256).max);
        router.withdrawFromPositionsIntoSingleAsset(
            multiCellar,
            paths,
            poolFees,
            assets,
            assetsIn,
            minOuts,
            address(this)
        );

        assertEq(USDC.balanceOf(address(this)), 30_400e6, "Did not recieve expected assets");
    }
}
