// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

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
 * @param positon address of the unsupported position
 */
error USR_UnsupportedPosition(address positon);

/**
 * @notice Attempted to update the asset to one that is not supported by the platform.
 * @param asset address of the unsupported asset
 */
error USR_UnsupportedAsset(address asset);

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
 * @notice Attempted set the cellar's asset to WETH with an asset that is not WETH compatible.
 * @param asset address of the asset that is not WETH compatible
 */
error USR_AssetNotWETH(address asset);

/**
 * @notice User attempted to stake zero amount.
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
 * @notice Attempted to add a position that is already being used.
 * @param position address of the position
 */
error USR_PositionAlreadyUsed(address position);

/**
 * @notice Attempted an action on a position that is not being used by the cellar but must be for
 *         the operation to succeed.
 * @param position address of the invalid position
 */
error USR_InvalidPosition(address position);

/**
 * @notice Attempted an action on a position that is required to be empty before the action can be performed.
 * @param position address of the non-empty position
 * @param sharesRemaining amount of shares remaining in the position
 */
error USR_PositionNotEmpty(address position, uint256 sharesRemaining);

/**
 * @notice Attempted an operation with arrays of unequal lengths that were expected to be equal length.
 */
error USR_LengthMismatch();

/**
 * @notice Attempted an operation with an invalid signature.
 * @param signatureLength length of the signature
 * @param expectedSignatureLength expected length of the signature
 */
error USR_InvalidSignature(uint256 signatureLength, uint256 expectedSignatureLength);

/**
 * @notice Attempted an operation with an asset that was different then the one expected.
 * @param asset address of the asset
 * @param expectedAsset address of the expected asset
 */
error USR_AssetMismatch(address asset, address expectedAsset);

// ========================================== STATE ERRORS ===========================================

/**
 * @dev These errors represent actions that are being prevented due to current contract state.
 *      These errors do not relate to user input, and may or may not be resolved by other actions
 *      or the progression of time.
 */

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

/**
 * @notice Attempted an operation to price an asset that under its minimum valid price.
 * @param asset address of the asset that is under its minimum valid price
 * @param price price of the asset
 * @param minPrice minimum valid price of the asset
 */
error STATE_AssetBelowMinPrice(address asset, uint256 price, uint256 minPrice);

/**
 * @notice Attempted an operation to price an asset that under its maximum valid price.
 * @param asset address of the asset that is under its maximum valid price
 * @param price price of the asset
 * @param maxPrice maximum valid price of the asset
 */
error STATE_AssetAboveMaxPrice(address asset, uint256 price, uint256 maxPrice);

/**
 * @notice Attempted to fetch a price for an asset that has not been updated in too long.
 * @param asset address of the asset thats price is stale
 * @param timeSinceLastUpdate seconds since the last price update
 * @param heartbeat maximum allowed time between price updates
 */
error STATE_StalePrice(address asset, uint256 timeSinceLastUpdate, uint256 heartbeat);
