// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { ERC20, MockERC20 } from "src/mocks/MockERC20.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract VestingTest is Test {
    using Math for uint256;

    VestingSimple internal vesting;
    ERC20 internal token;

    uint256 internal constant pk1 = 0xABCD;
    uint256 internal constant pk2 = 0xBEEF;
    address internal user = vm.addr(pk1);
    address internal user2 = vm.addr(pk2);
    uint256 internal constant balance = 1000 ether;
    uint256 internal constant ONE = 1e18;

    /// @dev Divides deposited amounts evenly - if a deposit divided
    ///      by the vesting period does not divide evenly, dust remainders
    ///      may be lost.
    uint256 internal constant vestingPeriod = 10000;
    uint256 internal constant minimumDeposit = vestingPeriod * 1000;

    function setUp() external {
        // Deploy token
        token = new MockERC20("TT", 18);

        // Deploy vesting contract
        vesting = new VestingSimple(token, vestingPeriod, minimumDeposit);

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

    function testFailDepositLessThanMinimum() external {
        vesting.deposit(vestingPeriod * 500, user);
    }

    function testPartialVest(uint256 amount, uint256 time) public {
        vm.assume(amount >= minimumDeposit && amount <= balance);
        vm.assume(time > 0 && time < vestingPeriod);

        // Deposit, then move forward in time, then withdraw
        vesting.deposit(amount, user);

        _checkState(amount, 0);

        skip(time);

        // Check state of vesting
        uint256 pctElapsed = time.mulDivDown(ONE, vestingPeriod);
        uint256 amountVested = pctElapsed.mulDivDown(amount, ONE);
        _checkState(amount, amountVested);

        _checkWithdrawReverts(1, amountVested);

        // Withdraw
        _doWithdrawal(1, amountVested);

        // Also make sure user still has a deposit
        assertEq(vesting.userDepositIds(user).length, 1, "User deposit should still be active");

        // Check global state
        assertEq(vesting.totalDeposits(), amount - amountVested, "Total deposits should be reduced");
        assertEq(vesting.unvestedDeposits(), amount - amountVested, "Unvested deposits should be reduced");
    }

    function testFullVest(uint256 amount) external {
        vm.assume(amount >= minimumDeposit && amount <= balance);

        // Deposit, then move forward in time, then withdraw
        vesting.deposit(amount, user);

        _checkState(amount, 0);

        skip(vestingPeriod);

        // Check state of vesting - full amount should have vested
        _checkState(amount, amount);

        _checkWithdrawReverts(1, amount);

        // Withdraw
        _doWithdrawal(1, amount);

        // Try to withdraw again, should get error that deposit is fully vested
        vm.expectRevert(bytes("Deposit fully vested"));
        vesting.withdraw(1, 1);

        // Also make sure user has no deposits
        assertEq(vesting.userDepositIds(user).length, 0, "User should have no more deposits");

        // Check global state
        assertEq(vesting.totalDeposits(), 0, "Total deposits should be 0");
        assertEq(vesting.unvestedDeposits(), 0, "Unvested deposits should be 0");
    }

    function testFullVestWithPartialClaim(uint256 amount, uint256 amountToClaim) external {
        vm.assume(amount >= minimumDeposit && amount <= balance);
        vm.assume(amountToClaim > 0 && amountToClaim < amount);

        // Deposit, then move forward in time, then withdraw
        vesting.deposit(amount, user);
        uint256 depositTimestamp = block.timestamp;

        _checkState(amount, 0);

        skip(vestingPeriod);

        // Check state of vesting - full amount should have vested
        _checkState(amount, amount);

        _checkWithdrawReverts(1, amount);

        // Withdraw
        _doWithdrawal(1, amountToClaim);
        uint256 claimTimestamp = block.timestamp;

        // Make sure user still has a deposit
        assertEq(vesting.userDepositIds(user).length, 1, "User deposit should still be active");

        // Check state, with deposit info's vesting value now nonzero
        assertEq(vesting.vestedBalanceOf(user), amount - amountToClaim, "User vested balance should be 0");
        assertEq(vesting.vestedBalanceOfDeposit(user, 1), amount - amountToClaim, "User vested balance of deposit should be 0");

        (
            uint256 amountPerSecond,
            uint128 until,
            uint128 lastClaimed,
            uint256 vested
        ) = vesting.userVestingInfo(user, 1);

        assertEq(amountPerSecond, amount.mulDivDown(ONE, vestingPeriod), "Amount per second should be accurate");
        assertEq(until, depositTimestamp + vestingPeriod, "Release time should be accurate");
        assertEq(lastClaimed, claimTimestamp, "Last claim timestamp should be accurate");
        assertEq(vested, amount - amountToClaim, "Vested tokens should be accounted for");

        // Check global state
        assertEq(vesting.totalDeposits(), amount - amountToClaim, "Total deposits should be nonzero");
        assertEq(vesting.unvestedDeposits(), 0, "Unvested deposits should be 0");

        // Try to withdraw the remainder - should work
        // Check all again
        _doWithdrawal(1, amount - amountToClaim);

        assertEq(vesting.currentId(user), 1, "User currentId should be 1");
        assertEq(vesting.vestedBalanceOf(user), 0, "User vested balance should be 0");
        assertEq(vesting.vestedBalanceOfDeposit(user, 1), 0, "User vested balance of deposit should be 0");
        assertEq(vesting.totalBalanceOf(user), 0, "User total balance should be 0");

        (,, lastClaimed, vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + vestingPeriod, "Last claim timestamp should be accurate after final withdrawal");
        assertEq(vested, 0, "Vested tokens should be accounted for after final withdrawal");

        // Also make sure user has no deposits
        assertEq(vesting.userDepositIds(user).length, 0, "User should have no more deposits");

        // Check global state
        assertEq(vesting.totalDeposits(), 0, "Total deposits should be 0");
        assertEq(vesting.unvestedDeposits(), 0, "Unvested deposits should be 0");
    }

    function testPartialVestWithPartialClaim(uint256 amount, uint256 amountToClaim, uint256 time) external {
        vm.assume(amount >= minimumDeposit && amount <= balance);
        vm.assume(time > 0 && time < vestingPeriod);

        uint256 pctElapsed = time.mulDivDown(ONE, vestingPeriod);
        uint256 amountVested = pctElapsed.mulDivDown(amount, ONE);

        vm.assume(amountToClaim > 0 && amountToClaim < amountVested);

        // Deposit, then move forward in time, then withdraw
        vesting.deposit(amount, user);
        uint256 depositTimestamp = block.timestamp;

        _checkState(amount, 0);

        skip(time);

        // Check state of vesting - full amount should have vested
        _checkState(amount, amountVested);

        _checkWithdrawReverts(1, amountVested);

        // Withdraw
        _doWithdrawal(1, amountToClaim);
        uint256 claimTimestamp = block.timestamp;

        // Make sure user still has a deposit
        assertEq(vesting.userDepositIds(user).length, 1, "User deposit should still be active");

        // Check state, with deposit info's vesting value now nonzero
        assertEq(vesting.vestedBalanceOf(user), amountVested - amountToClaim, "User vested balance should be 0");
        assertEq(vesting.vestedBalanceOfDeposit(user, 1), amountVested - amountToClaim, "User vested balance of deposit should be 0");

        (
            uint256 amountPerSecond,
            uint128 until,
            uint128 lastClaimed,
            uint256 vested
        ) = vesting.userVestingInfo(user, 1);

        assertEq(amountPerSecond, amount.mulDivDown(ONE, vestingPeriod), "Amount per second should be accurate");
        assertEq(until, depositTimestamp + vestingPeriod, "Release time should be accurate");
        assertEq(lastClaimed, claimTimestamp, "Last claim timestamp should be accurate");
        assertEq(vested, amountVested - amountToClaim, "Vested tokens should be accounted for");

        // Check global state
        assertEq(vesting.totalDeposits(), amount - amountToClaim, "Total deposits should be nonzero");
        assertEq(vesting.unvestedDeposits(), amount - amountVested, "Unvested deposits should be 0");

        // Try to withdraw the remainder - should work
        // Check all again
        _doWithdrawal(1, amountVested - amountToClaim);

        assertEq(vesting.currentId(user), 1, "User currentId should be 1");
        assertEq(vesting.vestedBalanceOf(user), 0, "User vested balance should be 0");
        assertEq(vesting.vestedBalanceOfDeposit(user, 1), 0, "User vested balance of deposit should be 0");
        assertEq(vesting.totalBalanceOf(user), amount - amountVested, "User total balance should be 0");

        (,, lastClaimed, vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + time, "Last claim timestamp should be accurate after final withdrawal");
        assertEq(vested, 0, "Vested tokens should be accounted for after final withdrawal");

        // Deposit still active, since only partially vested
        assertEq(vesting.userDepositIds(user).length, 1, "User deposit should still be active");

        // Check global state
        assertEq(vesting.totalDeposits(), amount - amountVested, "Total deposits should be 0");
        assertEq(vesting.unvestedDeposits(), amount - amountVested, "Unvested deposits should be 0");
    }

    function testMultipleClaims(uint256 amount, uint256 time) external {
        vm.assume(amount >= minimumDeposit && amount <= balance);
        vm.assume(time > 0 && time < vestingPeriod);

        uint256 pctElapsed = time.mulDivDown(ONE, vestingPeriod);
        uint256 amountVested = pctElapsed.mulDivDown(amount, ONE);
        // Aso subtract by one to round down
        uint256 amountToClaim = amount - amountVested;

        // Deposit, then move forward in time, then withdraw
        vesting.deposit(amount, user);
        uint256 depositTimestamp = block.timestamp;

        _checkState(amount, 0);

        skip(time);

        // Check state of vesting
        _checkState(amount, amountVested);

        _checkWithdrawReverts(1, amountVested);

        // Withdraw
        _doWithdrawal(1, amountVested);

        // Also make sure user still has a deposit
        assertEq(vesting.userDepositIds(user).length, 1, "User deposit should still be active");

        (,, uint128 lastClaimed, uint256 vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + time, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        // Check global state
        assertEq(vesting.totalDeposits(), amountToClaim, "Total deposits should be reduced");
        assertEq(vesting.unvestedDeposits(), amountToClaim, "Unvested deposits should be reduced");

        // Move to the end of the period and claim again
        skip(depositTimestamp + vestingPeriod + 100);

        assertEq(vesting.currentId(user), 1, "User currentId should be 1");
        assertApproxEqAbs(vesting.vestedBalanceOf(user), amountToClaim, 1, "User vested balance should be accurate");
        assertApproxEqAbs(vesting.vestedBalanceOfDeposit(user, 1), amountToClaim, 1, "User vested balance of deposit should be accurate");

        // TODO: Fix totalBalanceOf
        // assertApproxEqRel(vesting.totalBalanceOf(user), totalDeposited, 1e15, "User total balance should be nonzero");

        _checkWithdrawReverts(1, amountToClaim);

        _doWithdrawal(1, amountToClaim);

        // Also make sure user has no deposits
        assertEq(vesting.userDepositIds(user).length, 0, "User should have no more deposits");

        (,, lastClaimed, vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + vestingPeriod, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        // Check global state
        assertEq(vesting.totalDeposits(), 0, "Total deposits should be 0");
        assertEq(vesting.unvestedDeposits(), 0, "Unvested deposits should be 0");
    }

    // function testMultipleDeposits() external {
//
    // }

    // function testMultipleUsers() external {

    // }

    // function testDepositOnBehalf() external {

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
        vesting.withdraw(depositId, available + 100);

        // Make sure we cannot withdraw 0
        vm.expectRevert(bytes("Withdraw amount 0"));
        vesting.withdraw(depositId, 0);

        // Make sure we cannot withdraw invalid deposit
        vm.expectRevert(bytes("No such deposit"));
        vesting.withdraw(100, available);
    }

    function _doWithdrawal(uint256 depositId, uint256 amountToClaim) internal {
        uint256 amtBefore = token.balanceOf(user);
        vesting.withdraw(depositId, amountToClaim);
        uint256 amtAfter = token.balanceOf(user);

        assertEq(amtAfter - amtBefore, amountToClaim, "User should have received vested tokens");
    }
}
