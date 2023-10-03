// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// ========================================== USER ERRORS ===========================================

/**
 * @dev These errors represent invalid user input to functions. Where appropriate, the invalid value
 *      is specified along with constraints. These errors can be resolved by callers updating their
 *      arguments.
 */

/**
 * @notice Attempted an action with zero assets.
 */
error USR_ZeroAssets();

/**
 * @notice Attempted an action with zero shares.
 */
error USR_ZeroShares();

/**
 * @notice Attempted deposit more than the max deposit.
 * @param assets the assets user attempted to deposit
 * @param maxDeposit the max assets that can be deposited
 */
error USR_DepositRestricted(uint256 assets, uint256 maxDeposit);

/**
 * @notice Attempted to transfer more active shares than the user has.
 * @param activeShares amount of shares user has
 * @param attemptedActiveShares amount of shares user tried to transfer
 */
error USR_NotEnoughActiveShares(uint256 activeShares, uint256 attemptedActiveShares);

/**
 * @notice Attempted swap into an asset that is not the current asset of the position.
 * @param assetOut address of the asset attempted to swap to
 * @param currentAsset address of the current asset of position
 */
error USR_InvalidSwap(address assetOut, address currentAsset);

/**
 * @notice Attempted to sweep an asset that is managed by the cellar.
 * @param token address of the token that can't be sweeped
 */
error USR_ProtectedAsset(address token);

/**
 * @notice Attempted rebalance into the same position.
 * @param position address of the position
 */
error USR_SamePosition(address position);

/**
 * @notice Attempted to update the position to one that is not supported by the platform.
 * @param unsupportedPosition address of the unsupported position
 */
error USR_UnsupportedPosition(address unsupportedPosition);

/**
 * @notice Attempted an operation on an untrusted position.
 * @param position address of the position
 */
error USR_UntrustedPosition(address position);

/**
 * @notice Attempted to update a position to an asset that uses an incompatible amount of decimals.
 * @param newDecimals decimals of precision that the new position uses
 * @param maxDecimals maximum decimals of precision for a position to be compatible with the cellar
 */
error USR_TooManyDecimals(uint8 newDecimals, uint8 maxDecimals);

/**
 * @notice User attempted to stake zero amout.
 */
error USR_ZeroDeposit();

/**
 * @notice User attempted to stake an amount smaller than the minimum deposit.
 *
 * @param amount                Amount user attmpted to stake.
 * @param minimumDeposit        The minimum deopsit amount accepted.
 */
error USR_MinimumDeposit(uint256 amount, uint256 minimumDeposit);

/**
 * @notice The specified deposit ID does not exist for the caller.
 *
 * @param depositId             The deposit ID provided for lookup.
 */
error USR_NoDeposit(uint256 depositId);

/**
 * @notice The user is attempting to cancel unbonding for a deposit which is not unbonding.
 *
 * @param depositId             The deposit ID the user attempted to cancel.
 */
error USR_NotUnbonding(uint256 depositId);

/**
 * @notice The user is attempting to unbond a deposit which has already been unbonded.
 *
 * @param depositId             The deposit ID the user attempted to unbond.
 */
error USR_AlreadyUnbonding(uint256 depositId);

/**
 * @notice The user is attempting to unstake a deposit which is still timelocked.
 *
 * @param depositId             The deposit ID the user attempted to unstake.
 */
error USR_StakeLocked(uint256 depositId);

/**
 * @notice The contract owner attempted to update rewards but the new reward rate would cause overflow.
 */
error USR_RewardTooLarge();

/**
 * @notice The reward distributor attempted to update rewards but 0 rewards per epoch.
 *         This can also happen if there is less than 1 wei of rewards per second of the
 *         epoch - due to integer division this will also lead to 0 rewards.
 */
error USR_ZeroRewardsPerEpoch();

/**
 * @notice The caller attempted to stake with a lock value that did not
 *         correspond to a valid staking time.
 *
 * @param lock                  The provided lock value.
 */
error USR_InvalidLockValue(uint256 lock);

/**
 * @notice The caller attempted an signed action with an invalid signature.
 * @param signatureLength length of the signature passed in
 * @param expectedSignatureLength expected length of the signature passed in
 */
error USR_InvalidSignature(uint256 signatureLength, uint256 expectedSignatureLength);

/**
 * @notice Attempted an action by a non-custodian
 */
error USR_NotCustodian();

// ========================================== STATE ERRORS ===========================================

/**
 * @dev These errors represent actions that are being prevented due to current contract state.
 *      These errors do not relate to user input, and may or may not be resolved by other actions
 *      or the progression of time.
 */

/**
 * @notice Attempted an action when cellar is using an asset that has a fee on transfer.
 * @param assetWithFeeOnTransfer address of the asset with fee on transfer
 */
error STATE_AssetUsesFeeOnTransfer(address assetWithFeeOnTransfer);

/**
 * @notice Attempted action was prevented due to contract being shutdown.
 */
error STATE_ContractShutdown();

/**
 * @notice Attempted to shutdown the contract when it was already shutdown.
 */
error STATE_AlreadyShutdown();

/**
 * @notice The caller attempted to start a reward period, but the contract did not have enough tokens
 *         for the specified amount of rewards.
 *
 * @param rewardBalance         The amount of distributionToken held by the contract.
 * @param reward                The amount of rewards the caller attempted to distribute.
 */
error STATE_RewardsNotFunded(uint256 rewardBalance, uint256 reward);

/**
 * @notice Attempted an operation that is prohibited while yield is still being distributed from the last accrual.
 */
error STATE_AccrualOngoing();

/**
 * @notice The caller attempted to change the epoch length, but current reward epochs were active.
 */
error STATE_RewardsOngoing();

/**
 * @notice The caller attempted to change the next epoch duration, but there are rewards ready.
 */
error STATE_RewardsReady();

/**
 * @notice The caller attempted to deposit stake, but there are no remaining rewards to pay out.
 */
error STATE_NoRewardsLeft();

/**
 * @notice The caller attempted to perform an an emergency unstake, but the contract
 *         is not in emergency mode.
 */
error STATE_NoEmergencyUnstake();

/**
 * @notice The caller attempted to perform an an emergency unstake, but the contract
 *         is not in emergency mode, or the emergency mode does not allow claiming rewards.
 */
error STATE_NoEmergencyClaim();

/**
 * @notice The caller attempted to perform a state-mutating action (e.g. staking or unstaking)
 *         while the contract was paused.
 */
error STATE_ContractPaused();

/**
 * @notice The caller attempted to perform a state-mutating action (e.g. staking or unstaking)
 *         while the contract was killed (placed in emergency mode).
 * @dev    Emergency mode is irreversible.
 */
error STATE_ContractKilled();
