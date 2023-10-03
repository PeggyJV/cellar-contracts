// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ICellarStaking } from "src/interfaces/ICellarStaking.sol";

import "./Errors.sol";

/**
 * @title Sommelier Staking
 * @author Kevin Kennis
 *
 * Staking for Sommelier Cellars.
 *
 * This contract is inspired by the Synthetix staking rewards contract, Ampleforth's
 * token geyser, and Treasure DAO's MAGIC mine. However, there are unique improvements
 * and new features, specifically unbonding, as inspired by LP bonding on Osmosis.
 * Unbonding allows the contract to guarantee deposits for a certain amount of time,
 * increasing predictability and stickiness of TVL for Cellars.
 *
 * *********************************** Funding Flow ***********************************
 *
 * 1) The contract owner calls 'notifyRewardAmount' to specify an initial schedule of rewards
 *    The contract should hold enough the distribution token to fund the
 *    specified reward schedule, where the length of the reward schedule is defined by
 *    epochDuration. This duration can also be changed by the owner, and any change will apply
 *    to future calls to 'notifyRewardAmount' (but will not affect active schedules).
 * 2) At a future time, the contract owner may call 'notifyRewardAmount' again to extend the
 *    staking program with new rewards. These new schedules may distribute more or less
 *    rewards than previous epochs. If a previous epoch is not finished, any leftover rewards
 *    get rolled into the new schedule, increasing the reward rate. Reward schedules always
 *    end exactly 'epochDuration' seconds from the most recent time 'notifyRewardAmount' has been
 *    called.
 *
 * ********************************* Staking Lifecycle ********************************
 *
 * 1) A user may deposit a certain amount of tokens to stake, and is required to lock
 *    those tokens for a specified amount of time. There are three locking options:
 *    one day, one week, or one month. Longer locking times receive larger 'boosts',
 *    that the deposit will receive a larger proportional amount of shares. A user
 *    may not unstake until they choose to unbond, and time defined by the lock has
 *    elapsed during unbonding.
 * 2) When a user wishes to withdraw, they must first "unbond" their stake, which starts
 *    a timer equivalent to the lock time. They still receive their rewards during this
 *    time, but forfeit any locktime boosts. A user may cancel the unbonding period at any
 *    time to regain their boosts, which will set the unbonding timer back to 0.
 * 2) Once the lock has elapsed, a user may unstake their deposit, either partially
 *    or in full. The user will continue to receive the same 'boosted' amount of rewards
 *    until they unstake. The user may unstake all of their deposits at once, as long
 *    as all of the lock times have elapsed. When unstaking, the user will also receive
 *    all eligible rewards for all deposited stakes, which accumulate linearly.
 * 3) At any time, a user may claim their available rewards for their deposits. Rewards
 *    accumulate linearly and can be claimed at any time, whether or not the lock has
 *    for a given deposit has expired. The user can claim rewards for a specific deposit,
 *    or may choose to collect all eligible rewards at once.
 *
 * ************************************ Accounting ************************************
 *
 * The contract uses an accounting mechanism based on the 'rewardPerToken' model,
 * originated by the Synthetix staking rewards contract. First, token deposits are accounted
 * for, with synthetic "boosted" amounts used for reward calculations. As time passes,
 * rewardPerToken continues to accumulate, whereas the value of 'rewardPerToken' will match
 * the reward due to a single token deposited before the first ever rewards were scheduled.
 *
 * At each accounting checkpoint, rewardPerToken will be recalculated, and every time an
 * existing stake is 'touched', this value is used to calculate earned rewards for that
 * stake. Each stake tracks a 'rewardPerTokenPaid' value, which represents the 'rewardPerToken'
 * value the last time the stake calculated "earned" rewards. Every recalculation pays the difference.
 * This ensures no earning is double-counted. When a new stake is deposited, its
 * initial 'rewardPerTokenPaid' is set to the current 'rewardPerToken' in the contract,
 * ensuring it will not receive any rewards emitted during the period before deposit.
 *
 * The following example applies to a given epoch of 100 seconds, with a reward rate
 * of 100 tokens per second:
 *
 * a) User 1 deposits a stake of 50 before the epoch begins
 * b) User 2 deposits a stake of 20 at second 20 of the epoch
 * c) User 3 deposits a stake of 100 at second 50 of the epoch
 *
 * In this case,
 *
 * a) At second 20, before User 2's deposit, rewardPerToken will be 40
 *     (2000 total tokens emitted over 20 seconds / 50 staked).
 * b) At second 50, before User 3's deposit, rewardPerToken will be 82.857
 *     (previous 40 + 3000 tokens emitted over 30 seconds / 70 staked == 42.857)
 * c) At second 100, when the period is over, rewardPerToken will be 112.267
 *     (previous 82.857 + 5000 tokens emitted over 50 seconds / 170 staked == 29.41)
 *
 *
 * Then, each user will receive rewards proportional to the their number of tokens. At second 100:
 * a) User 1 will receive 50 * 112.267 = 5613.35 rewards
 * b) User 2 will receive 20 * (112.267 - 40) = 1445.34
 *       (40 is deducted because it was the current rewardPerToken value on deposit)
 * c) User 3 will receive 100 * (112.267 - 82.857) = 2941
 *       (82.857 is deducted because it was the current rewardPerToken value on deposit)
 *
 * Depending on deposit times, this accumulation may take place over multiple
 * reward periods, and the total rewards earned is simply the sum of rewards earned for
 * each period. A user may also have multiple discrete deposits, which are all
 * accounted for separately due to timelocks and locking boosts. Therefore,
 * a user's total earned rewards are a function of their rewards across
 * the proportional tokens deposited, across different ranges of rewardPerToken.
 *
 * Reward accounting takes place before every operation which may change
 * accounting calculations (minting of new shares on staking, burning of
 * shares on unstaking, or claiming, which decrements eligible rewards).
 * This is gas-intensive but unavoidable, since retroactive accounting
 * based on previous proportionate shares would require a prohibitive
 * amount of storage of historical state. On every accounting run, there
 * are a number of safety checks to ensure that all reward tokens are
 * accounted for and that no accounting time periods have been missed.
 *
 */
contract CellarStaking is ICellarStaking, Ownable {
    using SafeTransferLib for ERC20;

    // ============================================ STATE ==============================================

    // ============== Constants ==============

    uint256 public constant ONE = 1e18;
    uint256 public constant ONE_DAY = 60 * 60 * 24;
    uint256 public constant ONE_WEEK = ONE_DAY * 7;
    uint256 public constant TWO_WEEKS = ONE_WEEK * 2;

    uint256 public immutable SHORT_BOOST;
    uint256 public immutable MEDIUM_BOOST;
    uint256 public immutable LONG_BOOST;

    uint256 public immutable SHORT_BOOST_TIME;
    uint256 public immutable MEDIUM_BOOST_TIME;
    uint256 public immutable LONG_BOOST_TIME;

    // ============ Global State =============

    ERC20 public immutable override stakingToken;
    ERC20 public immutable override distributionToken;
    uint256 public override currentEpochDuration;
    uint256 public override nextEpochDuration;
    uint256 public override rewardsReady;

    uint256 public override minimumDeposit;
    uint256 public override endTimestamp;
    uint256 public override totalDeposits;
    uint256 public override totalDepositsWithBoost;
    uint256 public override rewardRate;
    uint256 public override rewardPerTokenStored;

    uint256 private lastAccountingTimestamp = block.timestamp;

    /// @notice Emergency states in case of contract malfunction.
    bool public override paused;
    bool public override ended;
    bool public override claimable;

    // ============= User State ==============

    /// @notice user => all user's staking positions
    mapping(address => UserStake[]) public stakes;

    // ========================================== CONSTRUCTOR ===========================================

    /**
     * @param _owner                The owner of the staking contract - will immediately receive ownership.
     * @param _stakingToken         The token users will deposit in order to stake.
     * @param _distributionToken    The token the staking contract will distribute as rewards.
     * @param _epochDuration        The length of a reward schedule.
     * @param shortBoost            The boost multiplier for the short unbonding time.
     * @param mediumBoost           The boost multiplier for the medium unbonding time.
     * @param longBoost             The boost multiplier for the long unbonding time.
     * @param shortBoostTime        The short unbonding time.
     * @param mediumBoostTime       The medium unbonding time.
     * @param longBoostTime         The long unbonding time.
     */
    constructor(
        address _owner,
        ERC20 _stakingToken,
        ERC20 _distributionToken,
        uint256 _epochDuration,
        uint256 shortBoost,
        uint256 mediumBoost,
        uint256 longBoost,
        uint256 shortBoostTime,
        uint256 mediumBoostTime,
        uint256 longBoostTime
    ) {
        stakingToken = _stakingToken;
        distributionToken = _distributionToken;
        nextEpochDuration = _epochDuration;

        SHORT_BOOST = shortBoost;
        MEDIUM_BOOST = mediumBoost;
        LONG_BOOST = longBoost;

        SHORT_BOOST_TIME = shortBoostTime;
        MEDIUM_BOOST_TIME = mediumBoostTime;
        LONG_BOOST_TIME = longBoostTime;

        transferOwnership(_owner);
    }

    // ======================================= STAKING OPERATIONS =======================================

    /**
     * @notice  Make a new deposit into the staking contract. Longer locks receive reward boosts.
     * @dev     Specified amount of stakingToken must be approved for withdrawal by the caller.
     * @dev     Valid lock values are 0 (one day), 1 (one week), and 2 (two weeks).
     *
     * @param amount                The amount of the stakingToken to stake.
     * @param lock                  The amount of time to lock stake for.
     */
    function stake(uint256 amount, Lock lock) external override whenNotPaused updateRewards {
        if (amount == 0) revert USR_ZeroDeposit();
        if (amount < minimumDeposit) revert USR_MinimumDeposit(amount, minimumDeposit);

        if (totalDeposits == 0 && rewardsReady > 0) {
            _startProgram(rewardsReady);
            rewardsReady = 0;

            // Need to run updateRewards again
            _updateRewards();
        } else if (block.timestamp > endTimestamp) {
            revert STATE_NoRewardsLeft();
        }

        // Do share accounting and populate user stake information
        (uint256 boost, ) = _getBoost(lock);
        uint256 amountWithBoost = amount + ((amount * boost) / ONE);

        stakes[msg.sender].push(
            UserStake({
                amount: uint112(amount),
                amountWithBoost: uint112(amountWithBoost),
                unbondTimestamp: 0,
                rewardPerTokenPaid: uint112(rewardPerTokenStored),
                rewards: 0,
                lock: lock
            })
        );

        // Update global state
        totalDeposits += amount;
        totalDepositsWithBoost += amountWithBoost;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Stake(msg.sender, stakes[msg.sender].length - 1, amount);
    }

    /**
     * @notice  Unbond a specified amount from a certain deposited stake.
     * @dev     After the unbond time elapses, the deposit can be unstaked.
     *
     * @param depositId             The specified deposit to unstake from.
     *
     */
    function unbond(uint256 depositId) external override whenNotPaused updateRewards {
        _unbond(depositId);
    }

    /**
     * @notice  Unbond all user deposits.
     * @dev     Different deposits may have different timelocks.
     *
     */
    function unbondAll() external override whenNotPaused updateRewards {
        // Individually unbond each deposit
        UserStake[] storage userStakes = stakes[msg.sender];
        for (uint256 i = 0; i < userStakes.length; i++) {
            UserStake storage s = userStakes[i];

            if (s.amount != 0 && s.unbondTimestamp == 0) {
                _unbond(i);
            }
        }
    }

    /**
     * @dev     Contains all logic for processing an unbond operation.
     *          For the given deposit, sets an unlock time, and
     *          reverts boosts to 0.
     *
     * @param depositId             The specified deposit to unbond from.
     */
    function _unbond(uint256 depositId) internal {
        // Fetch stake and make sure it is withdrawable
        UserStake storage s = stakes[msg.sender][depositId];

        uint256 depositAmount = s.amount;
        if (depositAmount == 0) revert USR_NoDeposit(depositId);
        if (s.unbondTimestamp > 0) revert USR_AlreadyUnbonding(depositId);

        _updateRewardForStake(msg.sender, depositId);

        // Remove any lock boosts
        uint256 depositAmountReduced = s.amountWithBoost - depositAmount;
        (, uint256 lockDuration) = _getBoost(s.lock);

        s.amountWithBoost = uint112(depositAmount);
        s.unbondTimestamp = uint32(block.timestamp + lockDuration);

        totalDepositsWithBoost -= uint112(depositAmountReduced);

        emit Unbond(msg.sender, depositId, depositAmount);
    }

    /**
     * @notice  Cancel an unbonding period for a stake that is currently unbonding.
     * @dev     Resets the unbonding timer and reinstates any lock boosts.
     *
     * @param depositId             The specified deposit to unstake from.
     *
     */
    function cancelUnbonding(uint256 depositId) external override whenNotPaused updateRewards {
        _cancelUnbonding(depositId);
    }

    /**
     * @notice  Cancel an unbonding period for all stakes.
     * @dev     Only cancels stakes that are unbonding.
     *
     */
    function cancelUnbondingAll() external override whenNotPaused updateRewards {
        // Individually unbond each deposit
        UserStake[] storage userStakes = stakes[msg.sender];
        for (uint256 i = 0; i < userStakes.length; i++) {
            UserStake storage s = userStakes[i];

            if (s.amount != 0 && s.unbondTimestamp != 0) {
                _cancelUnbonding(i);
            }
        }
    }

    /**
     * @dev     Contains all logic for cancelling an unbond operation.
     *          For the given deposit, resets the unbonding timer, and
     *          reverts boosts to amount determined by lock.
     *
     * @param depositId             The specified deposit to unbond from.
     */
    function _cancelUnbonding(uint256 depositId) internal {
        // Fetch stake and make sure it is withdrawable
        UserStake storage s = stakes[msg.sender][depositId];

        uint256 depositAmount = s.amount;
        if (depositAmount == 0) revert USR_NoDeposit(depositId);
        if (s.unbondTimestamp == 0) revert USR_NotUnbonding(depositId);

        _updateRewardForStake(msg.sender, depositId);

        // Reinstate
        (uint256 boost, ) = _getBoost(s.lock);
        uint256 depositAmountIncreased = (s.amount * boost) / ONE;
        uint256 amountWithBoost = s.amount + depositAmountIncreased;

        s.amountWithBoost = uint112(amountWithBoost);
        s.unbondTimestamp = 0;

        totalDepositsWithBoost += depositAmountIncreased;

        emit CancelUnbond(msg.sender, depositId);
    }

    /**
     * @notice  Unstake a specific deposited stake.
     * @dev     The unbonding time for the specified deposit must have elapsed.
     * @dev     Unstaking automatically claims available rewards for the deposit.
     *
     * @param depositId             The specified deposit to unstake from.
     *
     * @return reward               The amount of accumulated rewards since the last reward claim.
     */
    function unstake(uint256 depositId) external override whenNotPaused updateRewards returns (uint256 reward) {
        return _unstake(depositId);
    }

    /**
     * @notice  Unstake all user deposits.
     * @dev     Only unstakes rewards that are unbonded.
     * @dev     Unstaking automatically claims all available rewards.
     *
     * @return rewards              The amount of accumulated rewards since the last reward claim.
     */
    function unstakeAll() external override whenNotPaused updateRewards returns (uint256[] memory) {
        // Individually unstake each deposit
        UserStake[] storage userStakes = stakes[msg.sender];
        uint256[] memory rewards = new uint256[](userStakes.length);

        for (uint256 i = 0; i < userStakes.length; i++) {
            UserStake storage s = userStakes[i];

            if (s.amount != 0 && s.unbondTimestamp != 0 && block.timestamp >= s.unbondTimestamp) {
                rewards[i] = _unstake(i);
            }
        }

        return rewards;
    }

    /**
     * @dev     Contains all logic for processing an unstake operation.
     *          For the given deposit, does share accounting and burns
     *          shares, returns staking tokens to the original owner,
     *          updates global deposit and share trackers, and claims
     *          rewards for the given deposit.
     *
     * @param depositId             The specified deposit to unstake from.
     */
    function _unstake(uint256 depositId) internal returns (uint256 reward) {
        // Fetch stake and make sure it is withdrawable
        UserStake storage s = stakes[msg.sender][depositId];

        uint256 depositAmount = s.amount;

        if (depositAmount == 0) revert USR_NoDeposit(depositId);
        if (s.unbondTimestamp == 0 || block.timestamp < s.unbondTimestamp) revert USR_StakeLocked(depositId);

        _updateRewardForStake(msg.sender, depositId);

        // Start unstaking
        reward = s.rewards;

        s.amount = 0;
        s.amountWithBoost = 0;
        s.rewards = 0;

        // Update global state
        // Boosted amount same as deposit amount, since we have unbonded
        totalDeposits -= depositAmount;
        totalDepositsWithBoost -= depositAmount;

        // Distribute stake
        stakingToken.safeTransfer(msg.sender, depositAmount);

        // Distribute reward
        distributionToken.safeTransfer(msg.sender, reward);

        emit Unstake(msg.sender, depositId, depositAmount, reward);
    }

    /**
     * @notice  Claim rewards for a given deposit.
     * @dev     Rewards accumulate linearly since deposit.
     *
     * @param depositId             The specified deposit for which to claim rewards.
     *
     * @return reward               The amount of accumulated rewards since the last reward claim.
     */
    function claim(uint256 depositId) external override whenNotPaused updateRewards returns (uint256 reward) {
        return _claim(depositId);
    }

    /**
     * @notice  Claim all available rewards.
     * @dev     Rewards accumulate linearly.
     *
     *
     * @return rewards               The amount of accumulated rewards since the last reward claim.
     *                               Each element of the array specified rewards for the corresponding
     *                               indexed deposit.
     */
    function claimAll() external override whenNotPaused updateRewards returns (uint256[] memory rewards) {
        // Individually claim for each stake
        UserStake[] storage userStakes = stakes[msg.sender];
        rewards = new uint256[](userStakes.length);

        for (uint256 i = 0; i < userStakes.length; i++) {
            rewards[i] = _claim(i);
        }
    }

    /**
     * @dev Contains all logic for processing a claim operation.
     *      Relies on previous reward accounting done before
     *      processing external functions. Updates the amount
     *      of rewards claimed so rewards cannot be claimed twice.
     *
     *
     * @param depositId             The specified deposit to claim rewards for.
     *
     * @return reward               The amount of accumulated rewards since the last reward claim.
     */
    function _claim(uint256 depositId) internal returns (uint256 reward) {
        // Fetch stake and make sure it is valid
        UserStake storage s = stakes[msg.sender][depositId];

        _updateRewardForStake(msg.sender, depositId);

        reward = s.rewards;

        // Distribute reward
        if (reward > 0) {
            s.rewards = 0;

            distributionToken.safeTransfer(msg.sender, reward);

            emit Claim(msg.sender, depositId, reward);
        }
    }

    /**
     * @notice  Unstake and return all staked tokens to the caller.
     * @dev     In emergency mode, staking time locks do not apply.
     */
    function emergencyUnstake() external override {
        if (!ended) revert STATE_NoEmergencyUnstake();

        UserStake[] storage userStakes = stakes[msg.sender];
        for (uint256 i = 0; i < userStakes.length; i++) {
            if (claimable) _updateRewardForStake(msg.sender, i);

            UserStake storage s = userStakes[i];
            uint256 amount = s.amount;

            if (amount > 0) {
                // Update global state
                totalDeposits -= amount;
                totalDepositsWithBoost -= s.amountWithBoost;

                s.amount = 0;
                s.amountWithBoost = 0;

                stakingToken.transfer(msg.sender, amount);

                emit EmergencyUnstake(msg.sender, i, amount);
            }
        }
    }

    /**
     * @notice  Claim any accumulated rewards in emergency mode.
     * @dev     In emergency node, no additional reward accounting is done.
     *          Rewards do not accumulate after emergency mode begins,
     *          so any earned amount is only retroactive to when the contract
     *          was active.
     */
    function emergencyClaim() external override {
        if (!ended) revert STATE_NoEmergencyUnstake();
        if (!claimable) revert STATE_NoEmergencyClaim();

        uint256 reward;

        UserStake[] storage userStakes = stakes[msg.sender];
        for (uint256 i = 0; i < userStakes.length; i++) {
            _updateRewardForStake(msg.sender, i);

            UserStake storage s = userStakes[i];

            reward += s.rewards;
            s.rewards = 0;
        }

        if (reward > 0) {
            distributionToken.safeTransfer(msg.sender, reward);

            // No need for per-stake events like emergencyUnstake:
            // don't need to make sure positions were unwound
            emit EmergencyClaim(msg.sender, reward);
        }
    }

    // ======================================== ADMIN OPERATIONS ========================================

    /**
     * @notice Specify a new schedule for staking rewards. Contract must already hold enough tokens.
     * @dev    Can only be called by reward distributor. Owner must approve distributionToken for withdrawal.
     * @dev    epochDuration must divide reward evenly, otherwise any remainder will be lost.
     *
     * @param reward                The amount of rewards to distribute per second.
     */
    function notifyRewardAmount(uint256 reward) external override onlyOwner updateRewards {
        if (block.timestamp < endTimestamp) {
            uint256 remaining = endTimestamp - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            reward += leftover;
        }

        if (reward < nextEpochDuration) revert USR_ZeroRewardsPerEpoch();

        uint256 rewardBalance = distributionToken.balanceOf(address(this));
        uint256 pendingRewards = reward + rewardsReady;
        if (rewardBalance < pendingRewards) revert STATE_RewardsNotFunded(rewardBalance, pendingRewards);

        // prevent overflow when computing rewardPerToken
        uint256 proposedRewardRate = reward / nextEpochDuration;
        if (proposedRewardRate >= ((type(uint256).max / ONE) / nextEpochDuration)) {
            revert USR_RewardTooLarge();
        }

        if (totalDeposits == 0) {
            // No deposits yet, so keep rewards pending until first deposit
            // Incrementing in case it is called twice
            rewardsReady += reward;
        } else {
            // Ready to start
            _startProgram(reward);
        }

        lastAccountingTimestamp = block.timestamp;
    }

    /**
     * @notice Change the length of a reward epoch for future reward schedules.
     *
     * @param _epochDuration        The new duration for reward schedules.
     */
    function setRewardsDuration(uint256 _epochDuration) external override onlyOwner {
        if (rewardsReady > 0) revert STATE_RewardsReady();

        nextEpochDuration = _epochDuration;
        emit EpochDurationChange(nextEpochDuration);
    }

    /**
     * @notice Specify a minimum deposit for staking.
     * @dev    Can only be called by owner.
     *
     * @param _minimum              The minimum deposit for each new stake.
     */
    function setMinimumDeposit(uint256 _minimum) external override onlyOwner {
        minimumDeposit = _minimum;
    }

    /**
     * @notice Pause the contract. Pausing prevents staking, unstaking, claiming
     *         rewards, and scheduling new rewards. Should only be used
     *         in an emergency.
     *
     * @param _paused               Whether the contract should be paused.
     */
    function setPaused(bool _paused) external override onlyOwner {
        paused = _paused;
    }

    /**
     * @notice Stops the contract - this is irreversible. Should only be used
     *         in an emergency, for example an irreversible accounting bug
     *         or an exploit. Enables all depositors to withdraw their stake
     *         instantly. Also stops new rewards accounting.
     *
     * @param makeRewardsClaimable  Whether any previously accumulated rewards should be claimable.
     */
    function emergencyStop(bool makeRewardsClaimable) external override onlyOwner {
        if (ended) revert STATE_AlreadyShutdown();

        // Update state and put in irreversible emergency mode
        ended = true;
        claimable = makeRewardsClaimable;
        uint256 amountToReturn = distributionToken.balanceOf(address(this));

        if (makeRewardsClaimable) {
            // Update rewards one more time
            _updateRewards();

            // Return any remaining, since new calculation is stopped
            uint256 remaining = endTimestamp > block.timestamp ? (endTimestamp - block.timestamp) * rewardRate : 0;

            // Make sure any rewards except for remaining are kept for claims
            uint256 amountToKeep = rewardRate * currentEpochDuration - remaining;

            amountToReturn -= amountToKeep;
        }

        // Send distribution token back to owner
        distributionToken.transfer(msg.sender, amountToReturn);

        emit EmergencyStop(msg.sender, makeRewardsClaimable);
    }

    // ======================================= STATE INFORMATION =======================================

    /**
     * @notice Returns the latest time to account for in the reward program.
     *
     * @return timestamp           The latest time to calculate.
     */
    function latestRewardsTimestamp() public view override returns (uint256) {
        return block.timestamp < endTimestamp ? block.timestamp : endTimestamp;
    }

    /**
     * @notice Returns the amount of reward to distribute per currently-depostied token.
     *         Will update on changes to total deposit balance or reward rate.
     * @dev    Sets rewardPerTokenStored.
     *
     *
     * @return newRewardPerTokenStored  The new rewards to distribute per token.
     * @return latestTimestamp          The latest time to calculate.
     */
    function rewardPerToken() public view override returns (uint256 newRewardPerTokenStored, uint256 latestTimestamp) {
        latestTimestamp = latestRewardsTimestamp();

        if (totalDeposits == 0) return (rewardPerTokenStored, latestTimestamp);

        uint256 timeElapsed = latestTimestamp - lastAccountingTimestamp;
        uint256 rewardsForTime = timeElapsed * rewardRate;
        uint256 newRewardsPerToken = (rewardsForTime * ONE) / totalDepositsWithBoost;

        newRewardPerTokenStored = rewardPerTokenStored + newRewardsPerToken;
    }

    /**
     * @notice Gets all of a user's stakes.
     * @dev This is provided because Solidity converts public arrays into index getters,
     *      but we need a way to allow external contracts and users to access the whole array.

     * @param user                      The user whose stakes to get.
     *
     * @return stakes                   Array of all user's stakes
     */
    function getUserStakes(address user) public view override returns (UserStake[] memory) {
        return stakes[user];
    }

    // ============================================ HELPERS ============================================

    /**
     * @dev Modifier to apply reward updates before functions that change accounts.
     */
    modifier updateRewards() {
        _updateRewards();
        _;
    }

    /**
     * @dev Blocks calls if contract is paused or killed.
     */
    modifier whenNotPaused() {
        if (paused) revert STATE_ContractPaused();
        if (ended) revert STATE_ContractKilled();
        _;
    }

    /**
     * @dev Update reward accounting for the global state totals.
     */
    function _updateRewards() internal {
        (rewardPerTokenStored, lastAccountingTimestamp) = rewardPerToken();
    }

    /**
     * @dev On initial deposit, start the rewards program.
     *
     * @param reward                    The pending rewards to start distributing.
     */
    function _startProgram(uint256 reward) internal {
        // Assumptions
        // Total deposits are now (mod current tx), no ongoing program
        // Rewards are already funded (since checked in notifyRewardAmount)

        rewardRate = reward / nextEpochDuration;
        endTimestamp = block.timestamp + nextEpochDuration;
        currentEpochDuration = nextEpochDuration;

        emit Funding(reward, endTimestamp);
    }

    /**
     * @dev Update reward for a specific user stake.
     */
    function _updateRewardForStake(address user, uint256 depositId) internal {
        UserStake storage s = stakes[user][depositId];
        if (s.amount == 0) return;

        uint256 earned = _earned(s);
        s.rewards += uint112(earned);

        s.rewardPerTokenPaid = uint112(rewardPerTokenStored);
    }

    /**
     * @dev Return how many rewards a stake has earned and has claimable.
     */
    function _earned(UserStake memory s) internal view returns (uint256) {
        uint256 rewardPerTokenAcc = rewardPerTokenStored - s.rewardPerTokenPaid;
        uint256 newRewards = (s.amountWithBoost * rewardPerTokenAcc) / ONE;

        return newRewards;
    }

    /**
     * @dev Maps Lock enum values to corresponding lengths of time and reward boosts.
     */
    function _getBoost(Lock _lock) internal view returns (uint256 boost, uint256 timelock) {
        if (_lock == Lock.short) {
            return (SHORT_BOOST, SHORT_BOOST_TIME);
        } else if (_lock == Lock.medium) {
            return (MEDIUM_BOOST, MEDIUM_BOOST_TIME);
        } else if (_lock == Lock.long) {
            return (LONG_BOOST, LONG_BOOST_TIME);
        } else {
            revert USR_InvalidLockValue(uint256(_lock));
        }
    }
}
