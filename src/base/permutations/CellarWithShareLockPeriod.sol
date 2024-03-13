// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, Registry, ERC20, Math } from "src/base/Cellar.sol";

contract CellarWithShareLockPeriod is Cellar {
    using Math for uint256;

    constructor(
        address _owner,
        Registry _registry,
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint32 _holdingPosition,
        bytes memory _holdingPositionConfig,
        uint256 _initialDeposit,
        uint64 _strategistPlatformCut,
        uint192 _shareSupplyCap
    )
        Cellar(
            _owner,
            _registry,
            _asset,
            _name,
            _symbol,
            _holdingPosition,
            _holdingPositionConfig,
            _initialDeposit,
            _strategistPlatformCut,
            _shareSupplyCap
        )
    {}

    /**
     * @notice Emitted when share locking period is changed.
     * @param oldPeriod the old locking period
     * @param newPeriod the new locking period
     */
    event ShareLockingPeriodChanged(uint256 oldPeriod, uint256 newPeriod);

    /**
     * @notice Attempted to set `shareLockPeriod` to an invalid number.
     */
    error Cellar__InvalidShareLockPeriod();

    /**
     * @notice Attempted to burn shares when they are locked.
     * @param timeSharesAreUnlocked time when caller can transfer/redeem shares
     * @param currentBlock the current block number.
     */
    error Cellar__SharesAreLocked(uint256 timeSharesAreUnlocked, uint256 currentBlock);

    /**
     * @notice Attempted deposit on behalf of a user without being approved.
     */
    error Cellar__NotApprovedToDepositOnBehalf(address depositor);

    /**
     * @notice Shares must be locked for at least 5 minutes after minting.
     */
    uint256 public constant MINIMUM_SHARE_LOCK_PERIOD = 5 * 60;

    /**
     * @notice Shares can be locked for at most 2 days after minting.
     */
    uint256 public constant MAXIMUM_SHARE_LOCK_PERIOD = 2 days;

    /**
     * @notice After deposits users must wait `shareLockPeriod` time before being able to transfer or withdraw their shares.
     */
    uint256 public shareLockPeriod = MAXIMUM_SHARE_LOCK_PERIOD;

    /**
     * @notice mapping that stores every users last time stamp they minted shares.
     */
    mapping(address => uint256) public userShareLockStartTime;

    /**
     * @notice Allows share lock period to be updated.
     * @param newLock the new lock period
     * @dev Callable by Sommelier Strategist.
     */
    function setShareLockPeriod(uint256 newLock) external requiresAuth {
        if (newLock < MINIMUM_SHARE_LOCK_PERIOD || newLock > MAXIMUM_SHARE_LOCK_PERIOD)
            revert Cellar__InvalidShareLockPeriod();
        uint256 oldLockingPeriod = shareLockPeriod;
        shareLockPeriod = newLock;
        emit ShareLockingPeriodChanged(oldLockingPeriod, newLock);
    }

    /**
     * @notice helper function that checks enough time has passed to unlock shares.
     * @param owner the address of the user to check
     */
    function _checkIfSharesLocked(address owner) internal view {
        uint256 lockTime = userShareLockStartTime[owner];
        if (lockTime != 0) {
            uint256 timeSharesAreUnlocked = lockTime + shareLockPeriod;
            if (timeSharesAreUnlocked > block.timestamp)
                revert Cellar__SharesAreLocked(timeSharesAreUnlocked, block.timestamp);
        }
    }

    /**
     * @notice Override `transfer` to add share lock check.
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        _checkIfSharesLocked(msg.sender);
        return super.transfer(to, amount);
    }

    /**
     * @notice Override `transferFrom` to add share lock check.
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _checkIfSharesLocked(from);
        return super.transferFrom(from, to, amount);
    }

    /**
     * @notice called at the beginning of deposit.
     * @param assets amount of assets deposited by user.
     * @param receiver address receiving the shares.
     */
    function beforeDeposit(
        ERC20 depositAsset,
        uint256 assets,
        uint256 shares,
        address receiver
    ) internal view override {
        super.beforeDeposit(depositAsset, assets, shares, receiver);
        if (msg.sender != receiver) {
            if (!registry.approvedForDepositOnBehalf(msg.sender))
                revert Cellar__NotApprovedToDepositOnBehalf(msg.sender);
        }
    }

    /**
     * @notice called at the end of deposit.
     * @param position the position to deposit to.
     * @param assets amount of assets deposited by user.
     */
    function afterDeposit(uint32 position, uint256 assets, uint256 shares, address receiver) internal override {
        userShareLockStartTime[receiver] = block.timestamp;
        super.afterDeposit(position, assets, shares, receiver);
    }

    /**
     * @notice called at the beginning of withdraw.
     */
    function beforeWithdraw(uint256 assets, uint256 shares, address receiver, address owner) internal view override {
        _checkIfSharesLocked(owner);
        super.beforeWithdraw(assets, shares, receiver, owner);
    }

    /**
     * @notice Finds the max amount of value an `owner` can remove from the cellar.
     * @param owner address of the user to find max value.
     * @param inShares if false, then returns value in terms of assets
     *                 if true then returns value in terms of shares
     */
    function _findMax(address owner, bool inShares) internal view override returns (uint256 maxOut) {
        maxOut = super._findMax(owner, inShares);
        uint256 lockTime = userShareLockStartTime[owner];
        if (lockTime != 0) {
            uint256 timeSharesAreUnlocked = lockTime + shareLockPeriod;
            if (timeSharesAreUnlocked > block.timestamp) return 0;
        }
    }
}
