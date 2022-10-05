// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { ERC20, MockERC20 } from "src/mocks/MockERC20.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract VestingTest is Test {
    VestingSimple internal vesting;
    ERC20 internal token;

    uint256 internal constant pk = 0xABCD;
    address internal user = vm.addr(pk);
    uint256 internal constant balance = 1000 ether;
    uint256 internal constant ONE = 1e18;

    /// @dev Divides deposited amounts evenly - if a deposit divided
    ///      by the vesting period does not divide evenly, dust remainders
    ///      may be lost.
    uint256 internal constant vestingPeriod = 10000;

    function setUp() external {
        // Deploy token
        token = new MockERC20("TT", 18);

        // Deploy vesting contract
        vesting = new VestingSimple(token, vestingPeriod);

        // Set up user with funds
        vm.startPrank(user);
        deal(address(token), user, balance);
        token.approve(address(vesting), balance);
    }

    // =========================================== INITIALIZATION TEST =========================================

    function testInitialization() external {
        assertEq(address(vesting.asset()), address(token), "Should initialize an immutable asset");
        assertEq(vesting.vestingPeriod(), vestingPeriod, "Should initialize an immutable vesting period");
    }

    // ========================================== DEPOSIT/WITHDRAW TEST ========================================

    function testFailDepositZero() external {
        vesting.deposit(0, user);
    }

    function testFailDepositLessThanVestingPeriod() external {
        vesting.deposit(vestingPeriod / 2, user);
    }

    function testPartialVest(uint256 amount, uint256 time) external {
        vm.assume(amount >= vestingPeriod && amount <= balance);
        vm.assume(time > 0 && time <= vestingPeriod);

        // Deposit, then move forward in time, then withdraw
        vesting.deposit(amount, user);

        _checkState(amount, 0);

        skip(time);

        // Check state of vesting
        uint256 pctElapsed = time * ONE / vestingPeriod;
        uint256 amountVested = pctElapsed * amount / ONE;
        _checkState(amount, amountVested);

        _checkWithdrawReverts(1, amountVested);

        // Withdraw
        uint256 amtBefore = token.balanceOf(user);
        vesting.withdraw(1, amountVested);
        uint256 amtAfter = token.balanceOf(user);

        assertEq(amtAfter - amtBefore, amountVested, "User should have received vested tokens");

        // Also make sure user still has a deposit
        assertEq(vesting.userDepositIds(user).length, 1, "User deposit should still be active");

        // Check global state
        assertEq(vesting.totalDeposits(), amount - amountVested, "Total deposits should be 0");
        assertEq(vesting.unvestedDeposits(), amount - amountVested, "Unvested deposits should be 0");
    }

    function testFullVest(uint256 amount) external {
        vm.assume(amount >= vestingPeriod && amount <= balance);

        // Deposit, then move forward in time, then withdraw
        vesting.deposit(amount, user);

        _checkState(amount, 0);

        skip(vestingPeriod);

        // Check state of vesting - full amount should have vested
        _checkState(amount, amount);

        _checkWithdrawReverts(1, amount);

        // Withdraw
        uint256 amtBefore = token.balanceOf(user);
        vesting.withdraw(1, amount);
        uint256 amtAfter = token.balanceOf(user);

        assertEq(amtAfter - amtBefore, amount, "User should have received vested tokens");

        // Try to withdraw again, should get error that deposit is fully vested
        vm.expectRevert(bytes("Deposit fully vested"));
        vesting.withdraw(1, 1);

        // Also make sure user has no deposits
        assertEq(vesting.userDepositIds(user).length, 0, "User should have no more deposits");

        // Check global state
        assertEq(vesting.totalDeposits(), 0, "Total deposits should be 0");
        assertEq(vesting.unvestedDeposits(), 0, "Unvested deposits should be 0");
    }

    // function testFullVestWithPartialClaim(uint256 amount, uint256 time) external {
    //     vm.assume(amount <= balance);
    //     vm.assume(time <= vestingPeriod);

    //     // Deposit, then move forward in time, then withdraw
    // }

    // function testMultipleDeposits() external {

    // }

    // function testDepositOnBehalf() external {

    // }

    // function testPartialWithdrawal() external {

    // }

    // ================================================= HELPERS ===============================================

    function _checkState(uint256 totalDeposited, uint256 vested) internal {
        assertEq(vesting.totalDeposits(), totalDeposited, "Total deposits should be nonzero");
        assertEq(vesting.unvestedDeposits(), totalDeposited, "Unvested deposits should be nonzero");

        assertEq(vesting.currentId(user), 1, "User currentId should be 1");
        assertEq(vesting.vestedBalanceOf(user), vested, "User vested balance should be 0");
        assertEq(vesting.vestedBalanceOfDeposit(user, 1), vested, "User vested balance of deposit should be 0");

        // TODO: Fix totalBalanceOf
        // assertApproxEqRel(vesting.totalBalanceOf(user), totalDeposited, 1e15, "User total balance should be nonzero");
    }

    function _checkWithdrawReverts(uint256 depositId, uint256 available) internal {
        // Make sure we cannot withdraw more than vested
        vm.expectRevert(bytes("Not enough available"));
        vesting.withdraw(depositId, available + 1);

        // Make sure we cannot withdraw 0
        vm.expectRevert(bytes("Withdraw amount 0"));
        vesting.withdraw(depositId, 0);

        // Make sure we cannot withdraw invalid deposit
        vm.expectRevert(bytes("No such deposit"));
        vesting.withdraw(100, available);
    }
}
