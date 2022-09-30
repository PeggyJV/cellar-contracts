// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, ERC20 } from "src/base/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


/**
 * @title Cellar Vesting Timelock
 * @notice A contract sed as a position in a Sommelier cellar, with an adapter,
 *         that linearly releases deposited tokens in order to smooth
 *         out sudden TVL increases.
 */
contract VestingSimple {
    using SafeTransferLib for ERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    event Deposit(address indexed token, address indexed user, uint256 amount);
    event Withdraw(address indexed token, address indexed user, uint256 indexed depositId, uint256 amount);

    // ============================================= TYPES =============================================

    struct VestingSchedule {
        address token;
        uint256 amountPerSecond;
        uint128 until;
        uint128 lastClaimed;
        uint256 vested;
    }

    uint256 public constant MAX_VESTING_SCHEDULES = 10;

    // ============================================= STATE =============================================

    /// @notice The vesting period for the contract, in seconds.
    uint256 public immutable vestingPeriod;

   /// @notice All vesting schedules for a user
    mapping(address => mapping(uint256 => VestingSchedule)) public vests;
    /// @notice Enumeration of user deposit ID
    mapping(address => EnumerableSet.UintSet) private allUserDepositIds;
    /// @notice The current user's last deposited vest
    mapping(address => uint256) public currentId;

    uint256 public totalDeposits;
    uint256 public unvestedDeposits;

    // ========================================== CONSTRUCTOR ==========================================

    /**
     * @notice Instantiate the contract with a vesting period.
     *
     * @param _vestingPeriod                The length of time, in seconds, that tokens should vest over.
     */
    constructor(
        uint256 _vestingPeriod
    ) {
        vestingPeriod = _vestingPeriod;
    }

    // ====================================== DEPOSIT/WITHDRAWAL =======================================

    /**
     * @notice Deposit tokens to vest, which will instantly
     *         start emitting linearly over the defined lock period.
     *
     * @param token                         The token to deposit.
     * @param assets                        The amount of tokens to deposit.
     * @param receiver                      The account credited for the deposit.
     */
    function deposit(address token, uint256 assets, address receiver) public returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require(assets > 0, "Deposit amount 0");

        // Used for compatibility
        shares = assets;

        // Add deposit info
        uint256 newDepositId = ++currentId[receiver];
        allUserDepositIds[receiver].add(newDepositId);
        VestingSchedule storage s = vests[receiver][newDepositId];

        s.token = token;
        s.amountPerSecond = assets / vestingPeriod;
        s.until = uint128(block.timestamp + vestingPeriod);
        s.lastClaimed = uint128(block.timestamp);

        // Update global accounting
        totalDeposits += assets;
        unvestedDeposits += assets;

        // Collect tokens
        ERC20(token).safeTransferFrom(msg.sender, address(this), assets);

        emit Deposit(token, receiver, assets);
    }

    function withdraw(uint256 depositId, uint256 assets) public returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require(assets > 0, "Deposit amount 0");

        // Used for compatibility
        shares = assets;

        // Add deposit info
        VestingSchedule storage s = vests[msg.sender][depositId];

        uint256 newlyVested = _vestDeposit(msg.sender, depositId);

        require(s.vested >= assets, "Not enough available");

        // Update accounting
        s.vested -= assets;
        totalDeposits -= assets;
        unvestedDeposits -= newlyVested;

        // Collect tokens
        ERC20(s.token).safeTransfer(msg.sender, assets);

        emit Withdraw(s.token, msg.sender, depositId, assets);
    }

    function _vestDeposit(address user, uint256 depositId) internal returns (uint256 newlyVested) {
        // Add deposit info
        VestingSchedule storage s = vests[user][depositId];

        require(s.token != address(0), "No such deposit");
        require(s.lastClaimed < s.until, "Deposit fully vested");

        uint256 lastTimestamp = block.timestamp <= s.until ? block.timestamp : s.until;
        uint256 timeElapsed = lastTimestamp - s.lastClaimed;
        newlyVested = timeElapsed * s.amountPerSecond;

        s.vested += newlyVested;
        s.lastClaimed = uint128(lastTimestamp);
    }
}
