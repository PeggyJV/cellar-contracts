// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ERC4626 } from "src/base/ERC4626.sol";
import { CellarRouter } from "src/CellarRouter.sol";
import { IUniswapV3Router as UniswapV3Router } from "src/interfaces/IUniswapV3Router.sol";
import { IUniswapV2Router02 as UniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockSwapRouter } from "src/mocks/MockSwapRouter.sol";

import { Test } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarRouterTest is Test {
    using Math for uint256;

    MockERC20 private ABC;
    MockERC20 private XYZ;
    MockSwapRouter private swapRouter;

    MockERC4626 private cellar;
    CellarRouter private router;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    uint256 private constant privateKey = 0xBEEF;
    address private owner = vm.addr(privateKey);

    function setUp() public {
        swapRouter = new MockSwapRouter();

        router = new CellarRouter(UniswapV3Router(address(swapRouter)), UniswapV2Router(address(swapRouter)));

        ABC = new MockERC20("ABC", 18);
        XYZ = new MockERC20("XYZ", 18);

        // Setup exchange rates:
        swapRouter.setExchangeRate(address(ABC), address(XYZ), 1e18);
        swapRouter.setExchangeRate(address(XYZ), address(ABC), 1e18);

        // Set up a cellar:
        cellar = new MockERC4626(ERC20(address(ABC)), "ABC Cellar", "abcCLR", 18);
    }

    // ======================================= DEPOSIT TESTS =======================================

    function testDepositWithPermit(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Retrieve signature for permit.
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ABC.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(router), assets, 0, block.timestamp))
                )
            )
        );

        // Test deposit with permit.
        vm.startPrank(owner);
        ABC.mint(owner, assets);
        uint256 shares = router.depositIntoCellarWithPermit(
            ERC4626(address(cellar)),
            assets,
            owner,
            block.timestamp,
            v,
            r,
            s
        );
        vm.stopPrank();

        // Run test.
        assertEq(shares, assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assets), shares, "Withdrawing assets should burn shares given.");
        assertEq(cellar.previewDeposit(assets), shares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(owner), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(owner)), assets, "Should return all user's assets.");
        assertEq(ABC.balanceOf(owner), 0, "Should have deposited assets from user.");
    }

    function testDepositAndSwapIntoCellar(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Mint liquidity for swap.
        ABC.mint(address(swapRouter), 2 * assets);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(XYZ);
        path[1] = address(ABC);

        // Specify the pool fee tiers to use for each swap (none).
        uint256[] memory poolFees;

        // Test deposit and swap.
        vm.startPrank(owner);
        XYZ.approve(address(router), assets);
        XYZ.mint(owner, assets);
        uint256 shares = router.depositAndSwapIntoCellar(ERC4626(address(cellar)), path, poolFees, assets, 0, owner);
        vm.stopPrank();

        // Assets received by the cellar will be different from the amount of assets a user attempted
        // to deposit due to slippage swaps.
        uint256 assetsReceived = swapRouter.quote(assets, path);

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

    function testDepositAndSwapIntoCellarWithPermit(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    XYZ.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(router), assets, 0, block.timestamp))
                )
            )
        );

        // Mint liquidity for swap.
        ABC.mint(address(swapRouter), assets);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(XYZ);
        path[1] = address(ABC);

        // Specify the pool fee tiers to use for each swap (none).
        uint256[] memory poolFees;

        // Test deposit and swap with permit.
        vm.startPrank(owner);
        XYZ.mint(owner, assets);
        uint256 shares = router.depositAndSwapIntoCellarWithPermit(
            ERC4626(address(cellar)),
            path,
            poolFees,
            assets,
            0,
            owner,
            block.timestamp,
            v,
            r,
            s
        );
        vm.stopPrank();

        // Assets received by the cellar will be different from the amount of assets a user attempted
        // to deposit due to slippage swaps.
        uint256 assetsReceived = swapRouter.quote(assets, path);

        // Run test.
        assertEq(shares, assetsReceived, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assetsReceived), shares, "Withdrawing assets should burn shares given.");
        assertEq(cellar.previewDeposit(assetsReceived), shares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assetsReceived, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(owner), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(owner)), assetsReceived, "Should return all user's assets.");
        assertEq(ABC.balanceOf(owner), 0, "Should have deposited assets from user.");
    }

    function testWithdrawAndSwapFromCellar(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Mint liquidity for swap.
        ABC.mint(address(swapRouter), 2 * assets);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(XYZ);
        path[1] = address(ABC);

        // Specify the pool fee tiers to use for each swap (none).
        uint256[] memory poolFees;

        // Deposit and swap
        vm.startPrank(owner);
        XYZ.approve(address(router), assets);
        XYZ.mint(owner, assets);
        router.depositAndSwapIntoCellar(ERC4626(address(cellar)), path, poolFees, assets, 0, owner);

        // Assets received by the cellar will be different from the amount of assets a user attempted
        // to deposit due to slippage swaps.
        uint256 assetsReceivedAfterDeposit = swapRouter.quote(assets, path);

        // Reverse the swap path.
        (path[0], path[1]) = (path[1], path[0]);

        // Test withdraw and swap.
        cellar.approve(address(router), assetsReceivedAfterDeposit);
        uint256 sharesRedeemed = router.withdrawAndSwapFromCellar(
            ERC4626(address(cellar)),
            path,
            poolFees,
            assetsReceivedAfterDeposit,
            0,
            owner
        );
        vm.stopPrank();

        uint256 assetsReceivedAfterWithdraw = swapRouter.quote(assetsReceivedAfterDeposit, path);

        // Run test.
        assertEq(sharesRedeemed, assetsReceivedAfterDeposit, "Should have 1:1 exchange rate.");
        assertEq(cellar.totalSupply(), 0, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), 0, "Should have updated total assets into account the withdrawn assets.");
        assertEq(cellar.balanceOf(owner), 0, "Should have updated user's share balance.");
        assertEq(XYZ.balanceOf(owner), assetsReceivedAfterWithdraw, "Should have withdrawn assets to the user.");
    }

    // ======================================= WITHDRAW TESTS =======================================

    function testWithdrawAndSwapFromCellarWithPermit(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Mint liquidity for swap.
        ABC.mint(address(swapRouter), 2 * assets);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(XYZ);
        path[1] = address(ABC);

        // Specify the pool fee tiers to use for each swap (none).
        uint256[] memory poolFees;

        // Deposit and swap
        vm.startPrank(owner);
        XYZ.approve(address(router), assets);
        XYZ.mint(owner, assets);
        router.depositAndSwapIntoCellar(ERC4626(address(cellar)), path, poolFees, assets, 0, owner);
        vm.stopPrank();

        // Assets received by the cellar will be different from the amount of assets a user attempted
        // to deposit due to slippage swaps.
        uint256 assetsReceivedAfterDeposit = swapRouter.quote(assets, path);

        // Sign permit to allow router to transfer shares.
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    cellar.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(router),
                            assetsReceivedAfterDeposit,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        // Reverse the swap path.
        (path[0], path[1]) = (path[1], path[0]);

        // Test withdraw and swap.
        vm.prank(owner);
        uint256 sharesRedeemed = router.withdrawAndSwapFromCellarWithPermit(
            ERC4626(address(cellar)),
            path,
            poolFees,
            assetsReceivedAfterDeposit,
            0,
            owner,
            block.timestamp,
            v,
            r,
            s
        );

        uint256 assetsReceivedAfterWithdraw = swapRouter.quote(assetsReceivedAfterDeposit, path);

        // Run test.
        assertEq(sharesRedeemed, assetsReceivedAfterDeposit, "Should have 1:1 exchange rate.");
        assertEq(cellar.totalSupply(), 0, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), 0, "Should have updated total assets into account the withdrawn assets.");
        assertEq(cellar.balanceOf(owner), 0, "Should have updated user's share balance.");
        assertEq(XYZ.balanceOf(owner), assetsReceivedAfterWithdraw, "Should have withdrawn assets to the user.");
    }
}
