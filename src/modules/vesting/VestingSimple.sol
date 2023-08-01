// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @title Cellar Vesting Timelock
 * @author Kevin Kennis
 * @notice A contract set as a position in a Sommelier cellar, with an adapter,
 *         that linearly releases deposited tokens in order to smooth
 *         out sudden TVL increases.
 */
contract VestingSimple {
    using SafeTransferLib for ERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using Math for uint256;

    /// @notice Emitted when tokens are deposited for vesting.
    ///
    /// @param user The user making the deposit.
    /// @param receiver The user receiving the shares.
    /// @param amount The amount of tokens deposited.
    event VestingDeposit(address indexed user, address indexed receiver, uint256 amount);

    /// @notice Emitted when vested tokens are withdrawn.
    ///
    /// @param user The owner of the deposit.
    /// @param receiver The user receiving the deposit.
    /// @param depositId The ID of the deposit specified.
    /// @param amount The amount of tokens deposited.
    event VestingWithdraw(address indexed user, address indexed receiver, uint256 depositId, uint256 amount);

    // ============================================= ERRORS =============================================

    /// @notice Contract was deployed with no asset.
    error Vesting_ZeroAsset();

    /// @notice Contract was deployed with no vesting period.
    error Vesting_ZeroVestingPeriod();

    /// @notice Contract was deployed with a minimum deposit lower
    ///         then the vesting period.
    ///
    /// @param lowestMinimum The lowest minimum deposit possible,
    ///                      based on the vesting period.
    error Vesting_MinimumTooSmall(uint256 lowestMinimum);

    /// @notice User attempted to deposit 0 tokens.
    error Vesting_ZeroDeposit();

    /// @notice User attempted to deposit an amount of tokens
    ///         under the minimum.
    ///
    /// @param minimumDeposit The minimum deposit amount.
    error Vesting_DepositTooSmall(uint256 minimumDeposit);

    /// @notice User attempted to withdraw 0 tokens.
    error Vesting_ZeroWithdraw();

    /// @notice User attempted to withdraw from a fully-vested deposit.
    ///
    /// @param depositId The deposit ID specified.
    error Vesting_DepositFullyVested(uint256 depositId);

    /// @notice User attempted to withdraw more than the amount vested,
    ///         from any deposit.
    ///
    /// @param available The amount of token available for withdrawal.
    error Vesting_NotEnoughAvailable(uint256 available);

    /// @notice User attempted to withdraw more than the amount vested.
    ///
    /// @param depositId The deposit ID specified.
    /// @param available The amount of token available for withdrawal.
    error Vesting_DepositNotEnoughAvailable(uint256 depositId, uint256 available);

    /// @notice User specified a deposit that does not exist.
    ///
    /// @param depositId The deposit ID specified.
    error Vesting_NoDeposit(uint256 depositId);

    // ============================================= TYPES =============================================

    /// @notice Contains all information needed to vest
    ///         tokens for each deposited.
    struct VestingSchedule {
        uint256 amountPerSecond; // The amount of tokens vested per second.
        uint128 until; // The time vesting will finish.
        uint128 lastClaimed; // The last time vesting accrued.
        uint256 vested; // The amount of vested tokens still not withdrawn.
    }

    // ============================================= STATE =============================================

    /// @notice Used for retaining maximum precision in amountPerSecond.
    uint256 internal constant ONE = 1e18;

    /// @notice The deposit token for the vesting contract.
    ERC20 public immutable asset;
    /// @notice The vesting period for the contract, in seconds.
    uint256 public immutable vestingPeriod;
    /// @notice Used to preclude rounding errors. Should be equal to 0.0001 tokens of asset.
    uint256 public immutable minimumDeposit;

    /// @notice All vesting schedules for a user
    mapping(address => mapping(uint256 => VestingSchedule)) public vests;
    /// @notice Enumeration of user deposit ID
    mapping(address => EnumerableSet.UintSet) private allUserDepositIds;
    /// @notice The current user's last deposited vest
    mapping(address => uint256) public currentId;

    /// @notice The total amount of deposits to the contract.
    uint256 public totalDeposits;
    /// @notice The total amount of deposits to the contract that haven't vested
    ///         through withdrawals. Note that based on point-of-time calculations,
    ///         some of these tokens may be available for withdrawal.
    uint256 public unvestedDeposits;

    // ========================================== CONSTRUCTOR ==========================================

    /**
     * @notice Instantiate the contract with a vesting period.
     *
     * @param _asset                        The token the vesting contract will hold.
     * @param _vestingPeriod                The length of time, in seconds, that tokens should vest over.
     * @param _minimumDeposit               The minimum amount of tokens that can be deposited for vesting.
     */
    constructor(ERC20 _asset, uint256 _vestingPeriod, uint256 _minimumDeposit) {
        if (address(_asset) == address(0)) revert Vesting_ZeroDeposit();
        if (_vestingPeriod == 0) revert Vesting_ZeroVestingPeriod();
        if (_minimumDeposit < _vestingPeriod) revert Vesting_MinimumTooSmall(_vestingPeriod);

        asset = _asset;
        vestingPeriod = _vestingPeriod;
        minimumDeposit = _minimumDeposit;
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
        if (assets == 0) revert Vesting_ZeroDeposit();
        if (assets < minimumDeposit) revert Vesting_DepositTooSmall(minimumDeposit);

        // Used for compatibility
        shares = assets;

        // Add deposit info
        uint256 newDepositId = ++currentId[receiver];
        allUserDepositIds[receiver].add(newDepositId);
        VestingSchedule storage s = vests[receiver][newDepositId];

        s.amountPerSecond = assets.mulDivDown(ONE, vestingPeriod);
        s.until = uint128(block.timestamp + vestingPeriod);
        s.lastClaimed = uint128(block.timestamp);

        // Update global accounting
        totalDeposits += assets;
        unvestedDeposits += assets;

        // Collect tokens
        ERC20(asset).safeTransferFrom(msg.sender, address(this), assets);

        emit VestingDeposit(msg.sender, receiver, assets);
    }

    /**
     * @notice Withdraw vesting tokens, winding the vesting clock
     *         and releasing newly earned tokens since the last claim.
     *         Reverts if there are not enough assets available.
     *
     * @param depositId                     The deposit ID to withdraw from.
     * @param assets                        The amount of assets to withdraw.
     *
     * @return shares                       The amount of tokens withdrawn (for compatibility).
     */
    function withdraw(uint256 depositId, uint256 assets) public returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        if (assets == 0) revert Vesting_ZeroWithdraw();

        // Used for compatibility
        shares = assets;

        VestingSchedule storage s = vests[msg.sender][depositId];
        uint256 newlyVested = _vestDeposit(msg.sender, depositId);

        if (newlyVested == 0 && s.vested == 0) revert Vesting_DepositFullyVested(depositId);
        if (assets > s.vested) revert Vesting_DepositNotEnoughAvailable(depositId, s.vested);

        // Update accounting
        s.vested -= assets;
        totalDeposits -= assets;

        // Remove deposit if needed, including 1-wei deposits (rounding)
        if (s.vested <= 1 && block.timestamp >= s.until) {
            allUserDepositIds[msg.sender].remove(depositId);
        }

        emit VestingWithdraw(msg.sender, msg.sender, depositId, assets);

        asset.safeTransfer(msg.sender, assets);
    }

    /**
     * @notice Withdraw all tokens across all deposits that have vested.
     *         Winds the vesting clock to release newly earned tokens since the last claim.
     *
     * @return shares                       The amount of tokens withdrawn (for compatibility).
     */
    function withdrawAll() public returns (uint256 shares) {
        uint256[] memory depositIds = allUserDepositIds[msg.sender].values();
        uint256 numDeposits = depositIds.length;

        for (uint256 i = 0; i < numDeposits; i++) {
            VestingSchedule storage s = vests[msg.sender][depositIds[i]];

            if (s.amountPerSecond > 0 && (s.vested > 0 || s.lastClaimed < s.until)) {
                _vestDeposit(msg.sender, depositIds[i]);

                uint256 vested = s.vested;
                shares += vested;
                s.vested = 0;

                // Remove deposit if needed
                // Will not affect loop logic because values are pre-defined
                if (s.vested == 0 && block.timestamp >= s.until) {
                    allUserDepositIds[msg.sender].remove(depositIds[i]);
                }

                emit VestingWithdraw(msg.sender, msg.sender, depositIds[i], vested);
            }
        }

        totalDeposits -= shares;
        asset.safeTransfer(msg.sender, shares);
    }

    /**
     * @notice Withdraw a specified amount of tokens, sending them to the specified
     *         receiver. Withdraws from all deposits in order until the current amount
     *         is met.
     *
     * @param assets                        The amount of assets to withdraw.
     * @param receiver                      The address that will receive the assets.
     *
     * @return shares                       The amount of tokens withdrawn (for compatibility).
     */
    function withdrawAnyFor(uint256 assets, address receiver) public returns (uint256 shares) {
        uint256[] memory depositIds = allUserDepositIds[msg.sender].values();
        uint256 numDeposits = depositIds.length;

        shares = assets;

        for (uint256 i = 0; assets > 0 && i < numDeposits; i++) {
            VestingSchedule storage s = vests[msg.sender][depositIds[i]];

            if (s.amountPerSecond > 0 && (s.vested > 0 || s.lastClaimed < s.until)) {
                _vestDeposit(msg.sender, depositIds[i]);

                uint256 payout = s.vested >= assets ? assets : s.vested;

                if (payout == assets) {
                    // Can end here - only withdraw the amount we need
                    s.vested -= payout;
                    assets = 0;
                } else {
                    // Withdraw full deposit and go to next one
                    assets -= payout;
                    s.vested = 0;
                }

                emit VestingWithdraw(msg.sender, receiver, depositIds[i], payout);

                // Remove deposit if needed
                // Will not affect loop logic because values are pre-defined
                if (s.vested == 0 && block.timestamp >= s.until) {
                    allUserDepositIds[msg.sender].remove(depositIds[i]);
                }
            }
        }

        // Could not collect enough
        if (assets > 0) revert Vesting_NotEnoughAvailable(shares - assets);

        totalDeposits -= shares;
        asset.safeTransfer(receiver, shares);
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
                uint256 newlyVested = timeElapsed.mulDivDown(s.amountPerSecond, ONE);

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
     * @return balance                      The user's vested balance for the specified deposit.
     */
    function vestedBalanceOfDeposit(address user, uint256 depositId) public view returns (uint256) {
        VestingSchedule storage s = vests[user][depositId];

        if (s.amountPerSecond == 0) revert Vesting_NoDeposit(depositId);

        uint256 lastTimestamp = block.timestamp <= s.until ? block.timestamp : s.until;
        uint256 timeElapsed = lastTimestamp - s.lastClaimed;
        uint256 newlyVested = timeElapsed.mulDivDown(s.amountPerSecond, ONE);

        return s.vested + newlyVested;
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
                uint256 startTime = s.until - vestingPeriod;
                uint256 timeElapsedBeforeClaim = s.lastClaimed - startTime;

                uint256 totalAmount = (s.amountPerSecond * vestingPeriod) / ONE;
                uint256 previouslyVested = timeElapsedBeforeClaim.mulDivDown(s.amountPerSecond, ONE);
                uint256 claimed = previouslyVested - s.vested;

                balance += (totalAmount - claimed);
            }
        }
    }

    /**
     * @notice Returns all deposit IDs in an array. Only contains active deposits.
     *
     * @param user                          The user whose IDs should be reported.
     *
     * @return ids                          An array of the user's active deposit IDs.
     */
    function userDepositIds(address user) public view returns (uint256[] memory) {
        return allUserDepositIds[user].values();
    }

    /**
     * @notice Returns the vesting info for a given sdeposit.
     *
     * @param user                          The user whose vesting info should be reported.
     * @param depositId                     The deposit to report.
     *
     * @return amountPerSecond              The amount of tokens released per second.
     * @return until                        The timestamp at which all coins will be released.
     * @return lastClaimed                  The last time vesting occurred.
     * @return amountPerSecond              The amount of tokens released per second.
     */
    function userVestingInfo(address user, uint256 depositId) public view returns (uint256, uint128, uint128, uint256) {
        VestingSchedule memory s = vests[user][depositId];

        return (s.amountPerSecond, s.until, s.lastClaimed, s.vested);
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

        if (s.amountPerSecond == 0) revert Vesting_NoDeposit(depositId);

        // No new vesting
        if (s.lastClaimed >= s.until) return 0;

        uint256 lastTimestamp = block.timestamp <= s.until ? block.timestamp : s.until;
        uint256 timeElapsed = lastTimestamp - s.lastClaimed;

        // In case there were rounding errors due to accrual times,
        // round up on the last vest to collect anything lost.
        if (lastTimestamp == s.until) {
            newlyVested = timeElapsed.mulDivUp(s.amountPerSecond, ONE);
        } else {
            newlyVested = timeElapsed.mulDivDown(s.amountPerSecond, ONE);
        }

        s.vested += newlyVested;
        s.lastClaimed = uint128(lastTimestamp);

        unvestedDeposits -= newlyVested;
    }
}
