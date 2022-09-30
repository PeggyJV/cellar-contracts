// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, ERC20 } from "src/base/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// TODO:
// - Tests

/**
 * @title Cellar Vesting Timelock
 * @notice A contract sed as a position in a Sommelier cellar, with an adapter,
 *         that linearly releases deposited tokens in order to smooth
 *         out sudden TVL increases.
 */
contract VestingSimple {
    using SafeTransferLib for ERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed depositId, uint256 amount);

    // ============================================= TYPES =============================================

    struct VestingSchedule {
        uint256 amountPerSecond;
        uint128 until;
        uint128 lastClaimed;
        uint256 vested;
    }

    uint256 public constant MAX_VESTING_SCHEDULES = 10;

    // ============================================= STATE =============================================

    /// @notice The deposit token for the vesting contract.
    ERC20 public immutable asset;
    /// @notice The vesting period for the contract, in seconds.
    uint256 public immutable vestingPeriod;

   /// @notice All vesting schedules for a user
    mapping(address => mapping(uint256 => VestingSchedule)) public vests;
    /// @notice Enumeration of user deposit ID
    mapping(address => EnumerableSet.UintSet) private allUserDepositIds;
    /// @notice The current user's last deposited vest
    mapping(address => uint256) public currentId;

    /// @notice The total amount of deposits to the contract.
    uint256 public totalDeposits;
    /// @notice The total amount of deposits to the contract that haven't vested
    ///         through withdrawals. Note that based on point-of-time calculatinos,
    ///         some of these tokens may be available for withdrawal.
    uint256 public unvestedDeposits;

    // ========================================== CONSTRUCTOR ==========================================

    /**
     * @notice Instantiate the contract with a vesting period.
     *
     * @param _vestingPeriod                The length of time, in seconds, that tokens should vest over.
     */
    constructor(
        ERC20 _asset,
        uint256 _vestingPeriod
    ) {
        asset = _asset;
        vestingPeriod = _vestingPeriod;
    }

    // ====================================== DEPOSIT/WITHDRAWAL =======================================

    /**
     * @notice Deposit tokens to vest, which will instantly
     *         start emitting linearly over the defined lock period. Each deposit
     *         tracked separately such that new deposits don't reset the vesting
     *         clocks of the old deposits.
     *
     * @param assets                        The amount of tokens to deposit.
     * @param receiver                      The account credited for the deposit.
     *
     * @return shares                       The amount of tokens deposited (for compatibility).
     */
    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require(assets > 0, "Deposit amount 0");
        require(assets / vestingPeriod > 0, "Reward rate 0");

        // Used for compatibility
        shares = assets;

        // Add deposit info
        uint256 newDepositId = ++currentId[receiver];
        allUserDepositIds[receiver].add(newDepositId);
        VestingSchedule storage s = vests[receiver][newDepositId];

        s.amountPerSecond = assets / vestingPeriod;
        s.until = uint128(block.timestamp + vestingPeriod);
        s.lastClaimed = uint128(block.timestamp);

        // Update global accounting
        totalDeposits += assets;
        unvestedDeposits += assets;

        // Collect tokens
        ERC20(asset).safeTransferFrom(msg.sender, address(this), assets);

        emit Deposit(receiver, assets);
    }

    /**
     * @notice Withdraw vesting tokens, winding the vesting clock
     *         and releasing newly earned tokens since the last claim.
     *         Reverts if there are not enough assets available.
     *
     * @param depositId                     The deposit ID to withdraw from.
     * @param assets                        The amount of assets to withdraw.
     *
     * @return shares                       The amount of tokens withdraw (for compatibility).
     */
    function withdraw(uint256 depositId, uint256 assets) public returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require(assets > 0, "Deposit amount 0");

        // Used for compatibility
        shares = assets;

        VestingSchedule storage s = vests[msg.sender][depositId];
        uint256 newlyVested = _vestDeposit(msg.sender, depositId);

        require(s.vested >= assets, "Not enough available");

        // Update accounting
        s.vested -= assets;
        totalDeposits -= assets;
        unvestedDeposits -= newlyVested;

        // Remove deposit if needed
        if (s.vested == 0 && block.timestamp >= s.until) {
            allUserDepositIds[msg.sender].remove(depositId);
        }

        emit Withdraw(msg.sender, depositId, assets);

        asset.safeTransfer(msg.sender, assets);
    }

    /**
     * @notice Withdraw all tokens across all deposits that have vested.
     *         Winds the vesting clock to release newly earned tokens since the last claim.
     *
     * @return shares                       The amount of tokens withdraw (for compatibility).
     */
    function withdrawAll() public returns (uint256 shares) {
        uint256[] memory depositIds = allUserDepositIds[msg.sender].values();
        uint256 numDeposits = depositIds.length;

        for (uint256 i = 0; i < numDeposits; i++) {
            VestingSchedule storage s = vests[msg.sender][depositIds[i]];

            if (s.amountPerSecond > 0 && (s.vested > 0 || s.lastClaimed < s.until)) {
                uint256 newlyVested = _vestDeposit(msg.sender, depositIds[i]);

                shares += s.vested;
                s.vested = 0;

                totalDeposits -= s.vested;
                unvestedDeposits -= newlyVested;

                // Remove deposit if needed
                // Will not affect loop logic because values are pre-defined
                if (s.vested == 0 && block.timestamp >= s.until) {
                    allUserDepositIds[msg.sender].remove(depositIds[i]);
                }

                emit Withdraw(msg.sender, depositIds[i], s.vested);
            }
        }

        asset.safeTransfer(msg.sender, shares);
    }

    // ======================================= VIEW FUNCTIONS =========================================

    /**
     * @notice Reports all tokens which are vested and can be withdrawn for a user.
     *
     * @param user                          The user whose balance should be reported.
     *
     * @return balance                      The user's vested total balance.
     */
    function vestedBalanceOf(address user) public view returns (uint256 balance) {
        uint256[] memory depositIds = allUserDepositIds[user].values();
        uint256 numDeposits = depositIds.length;

        for (uint256 i = 0; i < numDeposits; i++) {
            VestingSchedule storage s = vests[user][depositIds[i]];

            if (s.amountPerSecond > 0 && (s.vested > 0 || s.lastClaimed < s.until)) {
                uint256 lastTimestamp = block.timestamp <= s.until ? block.timestamp : s.until;
                uint256 timeElapsed = lastTimestamp - s.lastClaimed;
                uint256 newlyVested = timeElapsed * s.amountPerSecond;

                balance += (s.vested + newlyVested);
            }
        }
    }

    /**
     * @notice Reports all tokens which are vested and can be withdrawn for a user.
     *
     * @param user                          The user whose balance should be reported.
     * @param depositId                     The depositId to report.
     *
     * @return balance                      The user's vested total balance.
     */
    function vestedBalanceOfDeposit(address user, uint256 depositId) public view returns (uint256 balance) {
        VestingSchedule storage s = vests[user][depositId];

        require(s.amountPerSecond > 0, "No such deposit");

        uint256 lastTimestamp = block.timestamp <= s.until ? block.timestamp : s.until;
        uint256 timeElapsed = lastTimestamp - s.lastClaimed;
        uint256 newlyVested = timeElapsed * s.amountPerSecond;

        balance = (s.vested + newlyVested);
    }

    /**
     * @notice Reports all tokens deposited by a user which have not been withdrawn yet.
     *         Includes unvested tokens.
     *
     * @param user                          The user whose balance should be reported.
     *
     * @return balance                      The user's total balance, both vested and unvested.
     */
    function totalBalanceOf(address user) public view returns (uint256 balance) {
        uint256[] memory depositIds = allUserDepositIds[user].values();
        uint256 numDeposits = depositIds.length;

        for (uint256 i = 0; i < numDeposits; i++) {
            VestingSchedule storage s = vests[user][depositIds[i]];

            if (s.amountPerSecond > 0 && (s.vested > 0 || s.lastClaimed < s.until)) {
                // Get total amount for the schedule
                uint256 totalAmount = s.amountPerSecond * vestingPeriod;
                uint256 startTime = s.until - vestingPeriod;

                uint256 lastTimestamp = block.timestamp <= s.until ? block.timestamp : s.until;
                uint256 timeElapsed = lastTimestamp - startTime;
                uint256 earned = timeElapsed * s.amountPerSecond;
                uint256 claimed = earned - s.vested;

                balance += (totalAmount - claimed);
            }
        }
    }

    // ===================================== INTERNAL FUNCTIONS =======================================

    /**
     * @dev Wind the vesting clock for a given deposit, based on how many seconds have
     *      elapsed in the vesting schedule since the last claim.
     *
     * @param user                          The user whose deposit will be vested.
     * @param depositId                     The deposit ID to vest for.
     *
     * @return newlyVested                  The newly vested tokens since the last vest.
     */
    function _vestDeposit(address user, uint256 depositId) internal returns (uint256 newlyVested) {
        // Add deposit info
        VestingSchedule storage s = vests[user][depositId];

        require(s.amountPerSecond > 0, "No such deposit");
        require(s.lastClaimed < s.until, "Deposit fully vested");

        uint256 lastTimestamp = block.timestamp <= s.until ? block.timestamp : s.until;
        uint256 timeElapsed = lastTimestamp - s.lastClaimed;
        newlyVested = timeElapsed * s.amountPerSecond;

        s.vested += newlyVested;
        s.lastClaimed = uint128(lastTimestamp);
    }
}
