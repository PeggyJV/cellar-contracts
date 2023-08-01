// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract VestingTest is MainnetStarterTest, AdaptorHelperFunctions {
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
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Deploy token
        token = WETH;

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
        vm.expectRevert(bytes(abi.encodeWithSelector(VestingSimple.Vesting_DepositFullyVested.selector, 1)));
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
        assertEq(
            vesting.vestedBalanceOfDeposit(user, 1),
            amount - amountToClaim,
            "User vested balance of deposit should be 0"
        );

        (uint256 amountPerSecond, uint128 until, uint128 lastClaimed, uint256 vested) = vesting.userVestingInfo(
            user,
            1
        );

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

        (, , lastClaimed, vested) = vesting.userVestingInfo(user, 1);

        assertEq(
            lastClaimed,
            depositTimestamp + vestingPeriod,
            "Last claim timestamp should be accurate after final withdrawal"
        );
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
        assertEq(
            vesting.vestedBalanceOfDeposit(user, 1),
            amountVested - amountToClaim,
            "User vested balance of deposit should be 0"
        );

        (uint256 amountPerSecond, uint128 until, uint128 lastClaimed, uint256 vested) = vesting.userVestingInfo(
            user,
            1
        );

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

        (, , lastClaimed, vested) = vesting.userVestingInfo(user, 1);

        assertEq(
            lastClaimed,
            depositTimestamp + time,
            "Last claim timestamp should be accurate after final withdrawal"
        );
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

        (, , uint128 lastClaimed, uint256 vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + time, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        // Check global state
        assertEq(vesting.totalDeposits(), amountToClaim, "Total deposits should be reduced");
        assertEq(vesting.unvestedDeposits(), amountToClaim, "Unvested deposits should be reduced");

        // Move to the end of the period and claim again
        skip(depositTimestamp + vestingPeriod + 100);

        assertEq(vesting.currentId(user), 1, "User currentId should be 1");
        assertApproxEqAbs(vesting.vestedBalanceOf(user), amountToClaim, 1, "User vested balance should be accurate");
        assertApproxEqAbs(
            vesting.vestedBalanceOfDeposit(user, 1),
            amountToClaim,
            1,
            "User vested balance of deposit should be accurate"
        );
        assertApproxEqAbs(
            vesting.totalBalanceOf(user),
            amount - amountVested,
            1,
            "User total balance should be accrate"
        );

        _checkWithdrawReverts(1, amountToClaim);

        _doWithdrawal(1, amountToClaim);

        // Also make sure user has no deposits
        assertEq(vesting.userDepositIds(user).length, 0, "User should have no more deposits");

        (, , lastClaimed, vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + vestingPeriod, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        // Check global state
        assertEq(vesting.totalDeposits(), 0, "Total deposits should be 0");
        assertEq(vesting.unvestedDeposits(), 0, "Unvested deposits should be 0");
    }

    function testMultipleDeposits(uint256 amount, uint256 time) external {
        vm.assume(amount >= minimumDeposit && amount <= balance / 10);
        vm.assume(time > 0 && time < vestingPeriod);

        uint256 amount2 = amount * 2;

        uint256 pctElapsed = time.mulDivDown(ONE, vestingPeriod);
        uint256 amountVested = pctElapsed.mulDivDown(amount, ONE);
        uint256 amountSecondVest = amount - amountVested;

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
        vesting.deposit(amount2, user);
        uint256 deposit2Timestamp = block.timestamp;

        // Deposit again

        // Also make sure user still has a deposit
        assertEq(vesting.userDepositIds(user).length, 2, "User deposits should both be active");

        (, , uint128 lastClaimed, uint256 vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + time, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        (, , lastClaimed, vested) = vesting.userVestingInfo(user, 2);

        assertEq(lastClaimed, depositTimestamp + time, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        // Check global state
        assertEq(vesting.totalDeposits(), amountSecondVest + amount2, "Total deposits should be reduced");
        assertEq(vesting.unvestedDeposits(), amountSecondVest + amount2, "Unvested deposits should be reduced");

        uint256 endTimestamp = depositTimestamp + vestingPeriod;
        vm.warp(endTimestamp);

        uint256 pctElapsed2 = (block.timestamp - deposit2Timestamp).mulDivDown(ONE, vestingPeriod);
        uint256 amountVested2 = pctElapsed2.mulDivDown(amount2, ONE);

        // Move to the end of the period and claim again
        {
            assertEq(vesting.currentId(user), 2, "User currentId should be 2");
            assertApproxEqAbs(
                vesting.vestedBalanceOf(user),
                amountSecondVest + amountVested2,
                1,
                "User vested balance should be accurate"
            );
            assertApproxEqAbs(
                vesting.vestedBalanceOfDeposit(user, 1),
                amountSecondVest,
                1,
                "User vested balance of deposit should be accurate"
            );
            assertApproxEqAbs(
                vesting.vestedBalanceOfDeposit(user, 2),
                amountVested2,
                1,
                "User vested balance of deposit should be accurate"
            );
            assertApproxEqAbs(
                vesting.totalBalanceOf(user),
                amount2 + amount - amountVested,
                1,
                "User total balance should be accurate"
            );

            _checkWithdrawReverts(1, amountSecondVest);
            _checkWithdrawReverts(2, amountVested2);

            uint256 amtBefore = token.balanceOf(user);
            vesting.withdrawAll();

            assertEq(
                token.balanceOf(user) - amtBefore,
                amountSecondVest + amountVested2,
                "User should have received vested tokens"
            );
        }

        // Also make sure user has 1 deposit removed, 1 remaining
        assertEq(vesting.userDepositIds(user).length, 1, "User should have 1 deposit left");
        assertApproxEqAbs(
            vesting.vestedBalanceOfDeposit(user, 1),
            0,
            1,
            "User vested balance of deposit should be accurate"
        );
        assertApproxEqAbs(
            vesting.vestedBalanceOfDeposit(user, 2),
            0,
            1,
            "User vested balance of deposit should be accurate"
        );

        (, , lastClaimed, vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + vestingPeriod, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        (, , lastClaimed, vested) = vesting.userVestingInfo(user, 2);

        assertEq(lastClaimed, depositTimestamp + vestingPeriod, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        // // Check global state
        assertEq(vesting.totalDeposits(), amount2 - amountVested2, "Total deposits should be leftover");
        assertEq(vesting.unvestedDeposits(), amount2 - amountVested2, "Unvested deposits should be leftover");
    }

    function testMultipleUsers(uint256 amount, uint256 time) external {
        vm.assume(amount >= minimumDeposit && amount <= balance / 10);
        vm.assume(time > 0 && time < vestingPeriod);

        deal(address(token), user2, balance);
        changePrank(user2);
        token.approve(address(vesting), balance);
        changePrank(user);

        uint256 amount2 = amount * 2;

        uint256 pctElapsed = time.mulDivDown(ONE, vestingPeriod);
        uint256 amountVested = pctElapsed.mulDivDown(amount, ONE);
        uint256 amountSecondVest = amount - amountVested;

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

        // Deposit as a second user
        changePrank(user2);
        vesting.deposit(amount2, user2);
        uint256 deposit2Timestamp = block.timestamp;
        changePrank(user);

        // Also make sure user still has a deposit
        assertEq(vesting.userDepositIds(user).length, 1, "User 1 should only have 1 deposit");
        assertEq(vesting.userDepositIds(user2).length, 1, "User 2 should only have 1 deposit");

        (, , uint128 lastClaimed, uint256 vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + time, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        (, , lastClaimed, vested) = vesting.userVestingInfo(user2, 1);

        assertEq(lastClaimed, depositTimestamp + time, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        // Check global state
        assertEq(vesting.totalDeposits(), amountSecondVest + amount2, "Total deposits should be reduced");
        assertEq(vesting.unvestedDeposits(), amountSecondVest + amount2, "Unvested deposits should be reduced");

        uint256 endTimestamp = depositTimestamp + vestingPeriod;
        vm.warp(endTimestamp);

        uint256 pctElapsed2 = (block.timestamp - deposit2Timestamp).mulDivDown(ONE, vestingPeriod);
        uint256 amountVested2 = pctElapsed2.mulDivDown(amount2, ONE);

        // Move to the end of the period and claim again
        {
            assertEq(vesting.currentId(user), 1, "User currentId should be 1");
            assertEq(vesting.currentId(user2), 1, "User 2 currentId should be 1");
            assertApproxEqAbs(
                vesting.vestedBalanceOf(user),
                amountSecondVest,
                1,
                "User vested balance should be accurate"
            );
            assertApproxEqAbs(
                vesting.vestedBalanceOf(user2),
                amountVested2,
                1,
                "User vested balance should be accurate"
            );
            assertApproxEqAbs(
                vesting.vestedBalanceOfDeposit(user, 1),
                amountSecondVest,
                1,
                "User vested balance of deposit should be accurate"
            );
            assertApproxEqAbs(
                vesting.vestedBalanceOfDeposit(user2, 1),
                amountVested2,
                1,
                "User vested balance of deposit should be accurate"
            );
            assertApproxEqAbs(vesting.totalBalanceOf(user2), amount2, 1, "User total balance should be nonzero");

            _checkWithdrawReverts(1, amountSecondVest);

            changePrank(user2);
            _checkWithdrawReverts(1, amountVested2);
            changePrank(user);

            uint256 amtBefore = token.balanceOf(user);
            uint256 amtBefore2 = token.balanceOf(user2);
            vesting.withdrawAll();

            changePrank(user2);
            vesting.withdrawAll();
            changePrank(user);

            assertEq(token.balanceOf(user) - amtBefore, amountSecondVest, "User should have received vested tokens");
            assertEq(token.balanceOf(user2) - amtBefore2, amountVested2, "User 2 should have received vested tokens");
        }

        // Also make sure user has 1 deposit removed, 1 remaining
        assertEq(vesting.userDepositIds(user).length, 0, "User should have no deposit left");
        assertEq(vesting.userDepositIds(user2).length, 1, "User should have 1 deposit left");

        assertApproxEqAbs(
            vesting.vestedBalanceOfDeposit(user, 1),
            0,
            1,
            "User vested balance of deposit should be accurate"
        );
        assertApproxEqAbs(
            vesting.vestedBalanceOfDeposit(user2, 1),
            0,
            1,
            "User vested balance of deposit should be accurate"
        );

        (, , lastClaimed, vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + vestingPeriod, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        (, , lastClaimed, vested) = vesting.userVestingInfo(user2, 1);

        assertEq(lastClaimed, depositTimestamp + vestingPeriod, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        // // Check global state
        assertEq(vesting.totalDeposits(), amount2 - amountVested2, "Total deposits should be leftover");
        assertEq(vesting.unvestedDeposits(), amount2 - amountVested2, "Unvested deposits should be leftover");
    }

    function testDepositOnBehalf(uint256 amount, uint256 time) external {
        vm.assume(amount >= minimumDeposit && amount <= balance);
        vm.assume(time > 0 && time < vestingPeriod);

        // Deposit, then move forward in time, then withdraw
        vesting.deposit(amount, user2);

        assertEq(vesting.totalDeposits(), amount, "Total deposits should be nonzero");
        assertEq(vesting.unvestedDeposits(), amount, "Unvested deposits should be nonzero");

        assertEq(vesting.currentId(user2), 1, "User currentId should be 1");
        assertEq(vesting.vestedBalanceOf(user2), 0, "User vested balance should be 0");
        assertEq(vesting.vestedBalanceOfDeposit(user2, 1), 0, "User vested balance of deposit should be 0");

        skip(time);

        // Check state of vesting
        uint256 pctElapsed = time.mulDivDown(ONE, vestingPeriod);
        uint256 amountVested = pctElapsed.mulDivDown(amount, ONE);

        assertEq(vesting.totalDeposits(), amount, "Total deposits should be nonzero");
        assertEq(vesting.unvestedDeposits(), amount, "Unvested deposits should be nonzero");

        assertEq(vesting.currentId(user2), 1, "User currentId should be 1");
        assertEq(vesting.vestedBalanceOf(user2), amountVested, "User vested balance should be 0");
        assertEq(vesting.vestedBalanceOfDeposit(user2, 1), amountVested, "User vested balance of deposit should be 0");

        // Withdraw
        uint256 amtBefore = token.balanceOf(user2);

        changePrank(user2);
        _checkWithdrawReverts(1, amountVested);
        vesting.withdraw(1, amountVested);
        changePrank(user);

        assertEq(token.balanceOf(user2) - amtBefore, amountVested, "User 2 should have received vested tokens");

        // Also make sure user still has a deposit
        assertEq(vesting.userDepositIds(user2).length, 1, "User deposit should still be active");

        // Check global state
        assertEq(vesting.totalDeposits(), amount - amountVested, "Total deposits should be reduced");
        assertEq(vesting.unvestedDeposits(), amount - amountVested, "Unvested deposits should be reduced");
    }

    function testWithdrawAnyFor(uint256 amount, uint256 time) external {
        vm.assume(amount >= minimumDeposit && amount <= balance / 10);
        vm.assume(time > 0 && time < vestingPeriod);

        uint256 amount2 = amount * 2;

        uint256 pctElapsed = time.mulDivDown(ONE, vestingPeriod);
        uint256 amountVested = pctElapsed.mulDivDown(amount, ONE);
        uint256 amountSecondVest = amount - amountVested;

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
        vesting.deposit(amount2, user);
        uint256 deposit2Timestamp = block.timestamp;

        // Deposit again

        // Also make sure user still has a deposit
        assertEq(vesting.userDepositIds(user).length, 2, "User deposits should both be active");

        (, , uint128 lastClaimed, uint256 vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + time, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        (, , lastClaimed, vested) = vesting.userVestingInfo(user, 2);

        assertEq(lastClaimed, depositTimestamp + time, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        // Check global state
        assertEq(vesting.totalDeposits(), amountSecondVest + amount2, "Total deposits should be reduced");
        assertEq(vesting.unvestedDeposits(), amountSecondVest + amount2, "Unvested deposits should be reduced");

        uint256 endTimestamp = depositTimestamp + vestingPeriod;
        vm.warp(endTimestamp);

        uint256 pctElapsed2 = (block.timestamp - deposit2Timestamp).mulDivDown(ONE, vestingPeriod);
        uint256 amountVested2 = pctElapsed2.mulDivDown(amount2, ONE);

        // Move to the end of the period and claim again,
        // but use a withdrawAnyFor
        {
            assertEq(vesting.currentId(user), 2, "User currentId should be 2");
            assertApproxEqAbs(
                vesting.vestedBalanceOf(user),
                amountSecondVest + amountVested2,
                1,
                "User vested balance should be accurate"
            );
            assertApproxEqAbs(
                vesting.vestedBalanceOfDeposit(user, 1),
                amountSecondVest,
                1,
                "User vested balance of deposit should be accurate"
            );
            assertApproxEqAbs(
                vesting.vestedBalanceOfDeposit(user, 2),
                amountVested2,
                1,
                "User vested balance of deposit should be accurate"
            );
            assertApproxEqAbs(
                vesting.totalBalanceOf(user),
                amount2 + amount - amountVested,
                1,
                "User total balance should be accurate"
            );

            _checkWithdrawReverts(1, amountSecondVest);
            _checkWithdrawReverts(2, amountVested2);

            // Check user2 balance since they will receive withdrawal
            uint256 amtBefore = token.balanceOf(user2);
            // Withdraw an amount that will require some from both deposits
            uint256 amountToWithdraw = amountSecondVest + amountVested2 / 10;
            vesting.withdrawAnyFor(amountToWithdraw, user2);

            assertEq(token.balanceOf(user2) - amtBefore, amountToWithdraw, "User should have received vested tokens");
        }

        // Also make sure user has 1 deposit removed, 1 remaining
        assertEq(vesting.userDepositIds(user).length, 1, "User should have 1 deposit left");
        assertApproxEqAbs(
            vesting.vestedBalanceOfDeposit(user, 1),
            0,
            1,
            "User vested balance of deposit should be accurate"
        );
        assertApproxEqAbs(
            vesting.vestedBalanceOfDeposit(user, 2),
            amountVested2.mulDivDown(9, 10),
            1,
            "User vested balance of deposit should be accurate"
        );

        (, , lastClaimed, vested) = vesting.userVestingInfo(user, 1);

        assertEq(lastClaimed, depositTimestamp + vestingPeriod, "Last claim timestamp should be accurate");
        assertEq(vested, 0, "Vested tokens should be accounted for");

        (, , lastClaimed, vested) = vesting.userVestingInfo(user, 2);

        assertEq(lastClaimed, depositTimestamp + vestingPeriod, "Last claim timestamp should be accurate");
        assertApproxEqAbs(vested, amountVested2.mulDivDown(9, 10), 1, "Vested tokens should be accounted for");

        // // Check global state
        assertEq(vesting.totalDeposits(), amount2 - amountVested2 / 10, "Total deposits should be leftover");
        assertEq(vesting.unvestedDeposits(), amount2 - amountVested2, "Unvested deposits should be leftover");
    }

    // ================================================= HELPERS ===============================================

    function _checkState(uint256 totalDeposited, uint256 vested) internal {
        assertEq(vesting.totalDeposits(), totalDeposited, "Total deposits should be nonzero");
        assertEq(vesting.unvestedDeposits(), totalDeposited, "Unvested deposits should be nonzero");

        assertEq(vesting.currentId(user), 1, "User currentId should be 1");
        assertEq(vesting.vestedBalanceOf(user), vested, "User vested balance should be 0");
        assertEq(vesting.vestedBalanceOfDeposit(user, 1), vested, "User vested balance of deposit should be 0");
        assertApproxEqAbs(vesting.totalBalanceOf(user), totalDeposited, 1, "User total balance should be accurate");
    }

    function _checkWithdrawReverts(uint256 depositId, uint256 available) internal {
        // Make sure we cannot withdraw more than vested
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(VestingSimple.Vesting_DepositNotEnoughAvailable.selector, depositId, available)
            )
        );
        vesting.withdraw(depositId, available + 100);

        // Make sure we cannot withdraw 0
        vm.expectRevert(bytes(abi.encodeWithSelector(VestingSimple.Vesting_ZeroWithdraw.selector)));
        vesting.withdraw(depositId, 0);

        // Make sure we cannot withdraw invalid deposit
        vm.expectRevert(bytes(abi.encodeWithSelector(VestingSimple.Vesting_NoDeposit.selector, 100)));
        vesting.withdraw(100, available);
    }

    function _doWithdrawal(uint256 depositId, uint256 amountToClaim) internal {
        uint256 amtBefore = token.balanceOf(user);
        vesting.withdraw(depositId, amountToClaim);
        uint256 amtAfter = token.balanceOf(user);

        assertEq(amtAfter - amtBefore, amountToClaim, "User should have received vested tokens");
    }
}
