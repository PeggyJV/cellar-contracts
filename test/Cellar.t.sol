// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { MockCellar, ERC20 } from "src/mocks/MockCellar.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";

import { Test } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarTest is Test {
    using Math for uint256;

    MockCellar private cellar;
    MockERC20 private XYZ;

    function setUp() external {
        vm.label(address(this), "user");

        XYZ = new MockERC20("XYZ", 18);

        cellar = new MockCellar(ERC20(address(XYZ)), "XYZ Cellar", "XYZ-CLR");
        vm.label(address(cellar), "cellar");

        // Transfer ownership to this contract for testing.
        vm.prank(address(cellar.gravityBridge()));
        cellar.transferOwnership(address(this));
    }

    function testInitialization() external {
        assertEq(cellar.name(), "XYZ Cellar", "Should initialize with correct name.");
        assertEq(cellar.symbol(), "XYZ-CLR", "Should initialize with correct symbol.");

        assertEq(address(cellar.asset()), address(XYZ), "Should initialize asset to be XYZ.");
        assertEq(cellar.decimals(), 18, "Should initialize decimals to be 18.");

        assertEq(cellar.liquidityLimit(), type(uint256).max, "Should initialize liquidity limit to be max.");
        assertEq(cellar.depositLimit(), type(uint256).max, "Should initialize deposit limit to be max.");
    }

    // ======================================= DEPOSIT/WITHDRAW TESTS =======================================

    function testDepositAndWithdraw(uint256 assets) external {
        assets = bound(assets, 1, type(uint112).max);

        XYZ.mint(address(this), assets);
        XYZ.approve(address(cellar), assets);

        // Test single deposit.
        uint256 shares = cellar.deposit(assets, address(this));

        assertEq(shares, assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assets), shares, "Withdrawing assets should burn shares given.");
        assertEq(cellar.previewDeposit(assets), shares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(XYZ.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

        assertEq(cellar.totalAssets(), 0, "Should have updated total assets with assets withdrawn.");
        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(XYZ.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    function testMintAndRedeem(uint256 shares) external {
        shares = bound(shares, 1, type(uint112).max);

        XYZ.mint(address(this), shares);
        XYZ.approve(address(cellar), shares);

        // Test single mint.
        uint256 assets = cellar.mint(shares, address(this));

        assertEq(shares, assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewRedeem(shares), assets, "Redeeming shares should withdraw assets owed.");
        assertEq(cellar.previewMint(shares), assets, "Minting shares should deposit assets owed.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(XYZ.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // Test single redeem.
        cellar.redeem(shares, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(XYZ.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }
}
