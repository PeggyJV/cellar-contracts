// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { CellarRouter } from "src/CellarRouter.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IGravity } from "src/interfaces/external/IGravity.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockCellar, ERC4626 } from "src/mocks/MockCellar.sol";
import { Cellar, Registry, PriceRouter, IGravity } from "src/base/Cellar.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { SigUtils } from "src/utils/SigUtils.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

// solhint-disable-next-line max-states-count
contract CellarRouterTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;

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

    ERC20Adaptor private erc20Adaptor;

    uint32 private usdcPosition;
    uint32 private daiPosition;
    uint32 private wethPosition;
    uint32 private wbtcPosition;

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

        registry.setApprovedForDepositOnBehalf(address(router), true);

        erc20Adaptor = new ERC20Adaptor();

        // Set up exchange rates:
        priceRouter.addAsset(USDC, 0, 0, false, 0);
        priceRouter.addAsset(DAI, 0, 0, false, 0);
        priceRouter.addAsset(WETH, 0, 0, false, 0);
        priceRouter.addAsset(WBTC, 0, 0, false, 0);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);

        usdcPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(USDC), 0, 0);
        daiPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(DAI), 0, 0);
        wethPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(WETH), 0, 0);
        wbtcPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(WBTC), 0, 0);

        uint32[] memory positions = new uint32[](4);
        positions[0] = usdcPosition;
        positions[1] = daiPosition;
        positions[2] = wethPosition;
        positions[3] = wbtcPosition;

        bytes[] memory positionConfigs = new bytes[](4);

        cellar = new MockCellar(
            registry,
            USDC,
            positions,
            positionConfigs,
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            address(0)
        );
        vm.label(address(cellar), "cellar");

        // Manipulate  test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        WETH.approve(address(cellar), type(uint256).max);
        WBTC.approve(address(cellar), type(uint256).max);
    }

    // ======================================= DEPOSIT TESTS =======================================

    function testDepositAndSwapWithPermit(uint256 assets) external {
        assets = bound(assets, 1e6, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        // Create a WETH Cellar.
        uint32[] memory positions = new uint32[](1);
        positions[0] = wethPosition;

        bytes[] memory positionConfigs = new bytes[](1);

        MockCellar wethCellar = new MockCellar(
            registry,
            WETH,
            positions,
            positionConfigs,
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            address(0)
        );

        // Generate permit sig
        uint256 ownerPrivateKey = 0xA11CE;
        address pOwner = vm.addr(ownerPrivateKey);
        bytes memory sig;
        {
            MockERC20 usdcPermit = MockERC20(address(USDC));
            SigUtils sigUtils = new SigUtils(usdcPermit.DOMAIN_SEPARATOR());
            SigUtils.Permit memory permit = SigUtils.Permit({
                owner: pOwner,
                spender: address(router),
                value: assets,
                nonce: 0,
                deadline: 1000000 days
            });

            bytes32 digest = sigUtils.getTypedDataHash(permit);

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
            sig = abi.encodePacked(r, s, v);
        }

        // Test deposit and swap.
        deal(address(USDC), pOwner, assets);

        bytes memory swapData = abi.encode(path, assets, 0);
        vm.prank(pOwner);
        uint256 shares = router.depositAndSwapWithPermit(
            wethCellar,
            SwapRouter.Exchange.UNIV2,
            swapData,
            assets,
            USDC,
            1000000 days,
            sig
        );

        // Assets received by the cellar will be equal to WETH currently in forked cellar because no
        // other deposits have been made.
        uint256 assetsReceived = WETH.balanceOf(address(wethCellar));

        // Run test.
        assertEq(shares, assetsReceived, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(wethCellar.previewWithdraw(assetsReceived), shares, "Withdrawing assets should burn shares given.");
        assertEq(wethCellar.previewDeposit(assetsReceived), shares, "Depositing assets should mint shares given.");
        assertEq(wethCellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(wethCellar.totalAssets(), assetsReceived, "Should have updated total assets with assets deposited.");
        assertEq(wethCellar.balanceOf(pOwner), shares, "Should have updated user's share balance.");
        assertEq(
            wethCellar.convertToAssets(wethCellar.balanceOf(pOwner)),
            assetsReceived,
            "Should return all user's assets."
        );
        assertEq(USDC.balanceOf(pOwner), 0, "Should have deposited assets from user.");
    }

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
        uint256 shares = router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV2, swapData, assets, DAI);

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
        uint256 shares = router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV3, swapData, assets, DAI);

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

    function testDepositAndSwapWithWrongSwapAmount(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);

        // Test deposit and swap.
        deal(address(DAI), address(this), assets);
        DAI.approve(address(router), assets);
        // Encode swap data to only use half the assets.
        bytes memory swapData = abi.encode(path, assets / 2, 0);
        uint256 shares = router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV2, swapData, assets, DAI);

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
        assertApproxEqAbs(DAI.balanceOf(address(this)), assets / 2, 1, "Should have received extra DAI from router.");
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
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        // Specify USDC as assetIn when it should be DAI.
        router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV2, swapData, assets, USDC);
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
        vm.expectRevert("Dai/insufficient-allowance");
        // Specify 0 for assets. Should revert since swap router is approved to spend 0 tokens from router.
        router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV2, swapData, 0, DAI);

        // Reset routers DAI balance.
        deal(address(DAI), address(router), 0);

        // Give user some DAI.
        deal(address(DAI), address(this), assets);
        DAI.approve(address(router), assets);

        // User calls deposit and swap but specifies a lower amount in swapData then actual.
        swapData = abi.encode(path, assets / 2, 0);
        router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV2, swapData, assets, DAI);

        assertEq(DAI.balanceOf(address(this)), assets / 2, "Caller should have been sent back their remaining assets.");
    }

    // ======================================= WITHDRAW TESTS =======================================

    function testWithdrawAndSwap() external {
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

    function testWithdrawAndSwapWithPermit() external {
        uint256 ownerPrivateKey = 0xA11CE;
        address pOwner = vm.addr(ownerPrivateKey);

        // Deposit initial funds into cellar.
        {
            vm.startPrank(pOwner);
            uint256 assets = 10_000e6;
            deal(address(USDC), pOwner, assets);
            USDC.approve(address(cellar), assets);
            cellar.deposit(assets, pOwner);
            vm.stopPrank();
        }

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

        // Create permit sig.
        bytes memory sig;
        uint256 shares = cellar.balanceOf(pOwner);
        {
            SigUtils sigUtils = new SigUtils(cellar.DOMAIN_SEPARATOR());
            SigUtils.Permit memory permit = SigUtils.Permit({
                owner: pOwner,
                spender: address(router),
                value: shares,
                nonce: 0,
                deadline: 1000000 days
            });

            bytes32 digest = sigUtils.getTypedDataHash(permit);

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
            sig = abi.encodePacked(r, s, v);
        }
        vm.prank(pOwner);
        shares = router.withdrawAndSwapWithPermit(cellar, exchanges, swapData, shares, 1000000 days, sig, pOwner);

        assertEq(WETH.balanceOf(pOwner), 0, "Should receive no WETH.");
        assertGt(WBTC.balanceOf(pOwner), 0, "Should receive WBTC");
        assertGt(USDC.balanceOf(pOwner), 0, "Should receive USDC");
        assertEq(WETH.balanceOf(address(router)), 0, "Router Should receive no WETH.");
        assertEq(WBTC.balanceOf(address(router)), 0, "Router Should receive no WBTC");
        assertEq(USDC.balanceOf(address(router)), 0, "Router Should receive no USDC");
        assertEq(WETH.allowance(address(router), address(swapRouter)), 0, "Should have no WETH allowances.");
        assertEq(WBTC.allowance(address(router), address(swapRouter)), 0, "Should have no WBTC allowances.");
    }

    function testWithdrawWithNoSwaps() external {
        // Deposit initial funds into cellar.
        uint256 assets = 10_000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));

        // Distribute funds into WETH and WBTC.
        deal(address(WETH), address(cellar), 3e18);
        deal(address(WBTC), address(cellar), 0.3e8);
        deal(address(USDC), address(cellar), 0);

        SwapRouter.Exchange[] memory exchanges;

        bytes[] memory swapData;

        cellar.approve(address(router), type(uint256).max);
        router.withdrawAndSwap(cellar, exchanges, swapData, cellar.totalAssets(), address(this));

        assertGt(WETH.balanceOf(address(this)), 0, "Should receive WETH.");
        assertGt(WBTC.balanceOf(address(this)), 0, "Should receive WBTC");
        assertEq(USDC.balanceOf(address(this)), 0, "Should receive no USDC");
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

    function testDepositOnBehalf(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint112).max);

        // Revoke depositor privilege.
        registry.setApprovedForDepositOnBehalf(address(router), false);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);

        // Test deposit and swap.
        deal(address(DAI), address(this), assets);
        DAI.approve(address(router), assets);
        bytes memory swapData = abi.encode(path, assets, 0);
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Cellar.Cellar__NotApprovedToDepositOnBehalf.selector, address(router)))
        );
        router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV2, swapData, assets, DAI);

        // Grant depositor privilege.
        registry.setApprovedForDepositOnBehalf(address(router), true);

        // Require shares are held for 8 blocks.
        cellar.setShareLockPeriod(8);

        router.depositAndSwap(cellar, SwapRouter.Exchange.UNIV2, swapData, assets, DAI);
        // Receiver should not be able to redeem, withdraw, or transfer shares for locking period.
        uint256 shares = cellar.balanceOf(address(this));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__SharesAreLocked.selector,
                    block.number + cellar.shareLockPeriod(),
                    block.number
                )
            )
        );
        cellar.transfer(vm.addr(111), shares);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__SharesAreLocked.selector,
                    block.number + cellar.shareLockPeriod(),
                    block.number
                )
            )
        );
        cellar.redeem(shares, address(this), address(this));

        // Try to withdraw something from the cellar
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__SharesAreLocked.selector,
                    block.number + cellar.shareLockPeriod(),
                    block.number
                )
            )
        );
        cellar.withdraw(1e6, address(this), address(this));
    }
}
