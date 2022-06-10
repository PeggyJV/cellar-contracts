// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { MultipositionETHCellar, ERC4626, ERC20 } from "src/base/MultipositionETHCellar.sol";
import { MockWETH } from "src/mocks/MockWETH.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";

import { Test } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract MultipositionETHCellarTest is Test {
    using Math for uint256;

    MultipositionETHCellar private cellar;
    MockERC4626 private position1;
    MockERC4626 private position2;
    MockERC4626 private position3;
    MockWETH private WETH;

    function setUp() external {
        vm.label(address(this), "user");

        WETH = new MockWETH();
        vm.label(address(WETH), "WETH");

        position1 = new MockERC4626(ERC20(address(WETH)), "Position 1", "p1", 18);
        position2 = new MockERC4626(ERC20(address(WETH)), "Position 2", "p2", 18);
        position3 = new MockERC4626(ERC20(address(WETH)), "Position 3", "p3", 18);
        vm.label(address(position1), "position 1");
        vm.label(address(position2), "position 2");
        vm.label(address(position3), "position 3");

        address[] memory positions = new address[](3);
        positions[0] = address(position1);
        positions[1] = address(position2);
        positions[2] = address(position3);

        cellar = new MultipositionETHCellar(ERC20(address(WETH)), positions, "ETH Cellar LP Token", "ETH-CLR");
        vm.label(address(cellar), "cellar");

        // Transfer ownership to this contract for testing.
        vm.prank(address(cellar.gravityBridge()));
        cellar.transferOwnership(address(this));
    }

    function testInitialization() external {
        assertEq(cellar.name(), "ETH Cellar LP Token", "Should initialize with correct name.");
        assertEq(cellar.symbol(), "ETH-CLR", "Should initialize with correct symbol.");

        assertEq(address(cellar.asset()), address(WETH), "Should initialize asset to be WETH.");
        assertEq(cellar.decimals(), 18, "Should initialize decimals to be 18.");

        address[] memory positions = new address[](3);
        positions[0] = address(position1);
        positions[1] = address(position2);
        positions[2] = address(position3);

        for (uint256 i; i < positions.length; i++)
            assertEq(address(cellar.positions(i)), address(positions[i]), "Should initialize positions.");

        assertTrue(cellar.isTrusted(address(position1)), "Should initialize position 1 to be trusted.");
        assertTrue(cellar.isTrusted(address(position2)), "Should initialize position 2 to be trusted.");
        assertTrue(cellar.isTrusted(address(position3)), "Should initialize position 3 to be trusted.");

        assertEq(cellar.liquidityLimit(), type(uint256).max, "Should initialize liquidity limit to be max.");
        assertEq(cellar.depositLimit(), type(uint256).max, "Should initialize deposit limit to be max.");
    }

    // ======================================= DEPOSIT/WITHDRAW TESTS =======================================

    function testDepositAndWithdraw(uint256 assets) external {
        assets = bound(assets, 1, type(uint112).max);

        WETH.mint(address(this), assets);
        WETH.approve(address(cellar), assets);

        // Test single deposit.
        uint256 shares = cellar.deposit(assets, address(this));

        assertEq(shares, assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assets), shares, "Withdrawing assets should burn shares given.");
        assertEq(cellar.previewDeposit(assets), shares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(WETH.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

        assertEq(cellar.totalAssets(), 0, "Should have updated total assets with assets withdrawn.");
        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(WETH.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    function testMintAndRedeem(uint256 shares) external {
        shares = bound(shares, 1, type(uint112).max);

        WETH.mint(address(this), shares);
        WETH.approve(address(cellar), shares);

        // Test single mint.
        uint256 assets = cellar.mint(shares, address(this));

        assertEq(shares, assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewRedeem(shares), assets, "Redeeming shares should withdraw assets owed.");
        assertEq(cellar.previewMint(shares), assets, "Minting shares should deposit assets owed.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(WETH.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // Test single redeem.
        cellar.redeem(shares, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(WETH.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    // TODO: test deposit and mint with ETH (maybe in router instead of this contract)
}
