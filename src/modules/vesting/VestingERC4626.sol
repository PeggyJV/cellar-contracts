// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, ERC20 } from "src/base/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

/**
 * @title Cellar Vesting Timelock
 * @notice An ERC4626 contract, used as a position in a Sommelier cellar,
 *         that linearly releases deposited tokens in order to smooth
 *         out sudden TVL increases. Each contract can hold a single asset type,
 *         following ERC4626.
 */
contract Vesting4626 is ERC4626 {
    using SafeTransferLib for ERC20;

    // ============================================= TYPES =============================================

    struct VestingSchedule {
        uint256 amountPerSecond;
        uint128 until;
        uint128 lastClaimed;
    }

    uint256 public constant MAX_VESTING_SCHEDULES = 10;

    // ============================================= STATE =============================================

    /// @notice The vesting period for the contract, in seconds.
    uint256 public immutable vestingPeriod;

    /// @notice Total amount of deposited, unvested tokens.
    uint256 public totalUnvestedSupply;

    /// @notice Total amount of deposited, unvested tokens.
    mapping(address => uint256) public unvestedBalanceOf;

    /// @notice The scheduled vesting for each depositor.
    mapping(address => VestingSchedule[]) public vests;

    // ========================================== CONSTRUCTOR ==========================================

    /**
     * @notice Instantiate the contract with a vesting period.
     *
     * @param _vestingPeriod                The length of time, in seconds, that tokens should vest over.
     */
    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _vestingPeriod
    ) ERC4626(_asset, _name, _symbol, _decimals) {
        vestingPeriod = _vestingPeriod;
    }

    // ====================================== DEPOSIT/WITHDRAWAL =======================================

    // Re-implement deposit and mint to not accrue balances

    /**
     * @notice Deposit tokens to vest, which will instantly
     *         start emitting linearly over the defined lock period.
     *
     * @param assets                        The amount of tokens to deposit.
     * @param receiver                      The account credited for the deposit.
     */
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = (assets)) != 0, "ZERO_SHARES");

        beforeDeposit(assets, shares, receiver);

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mintUnvested(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares, receiver);
    }

    // Implement beforeWithdraw to add to user's balance based on vesting time

    /**
     * @notice After deposit, initialize a vesting schedule to define
     *         when the deposited tokens can be withdrawn.
     */
    function afterDeposit(
        uint256 assets,
        uint256,
        address receiver
    ) internal override {
        // Add a new vesting schedule for the user.
        vests[receiver].push(VestingSchedule({
            amountPerSecond: assets / vestingPeriod,
            until: block.timestamp + vestingPeriod
        });
    }

    // ======================================== VIEW FUNCTIONS =========================================

    /**
     * @notice Return the total assets held by the contract. Note that this does
     *         _not_ include unvested tokens, so that they are not counted for in
     *         a cellar's TVL.
     *
     * @return assets                       The total vested tokens held by the contract.
     */
    function totalAssets() public view override returns (uint256) {
        return totalSupply;
    }

    /**
     * @notice Convert vesting contract shares to vested tokens, which
     *         should always be 1-1.
     *
     * @param assets                        The amount of tokens.
     */
    function convertToShares(uint256 assets) public pure override returns (uint256) {
        return assets;
    }

    /**
     * @notice Convert vested tokens to vesting contract shares, which
     *         should always be 1-1.
     *
     * @param shares                        The amount of tokens.
     */
    function convertToAssets(uint256 shares) public pure override returns (uint256) {
        return shares;
    }

    // ===================================== INTERNAL FUNCTIONS =======================================

    /**
     * @dev Mint unvested tokens, such that a user's balance is not credited, but their
     *      unvested balance is.
     *
     * @param to                            The user receiving the minted tokens.
     * @param amount                        The amount of tokens to mint.
     */
    function _mintUnvested(address to, uint256 amount) internal {
        totalUnvestedSupply += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            unvestedBalanceOf[to] += amount;
        }

        // Do NOT emit an event because no free tokens were created.
    }

    /**
     * @dev Burn unvested tokens, such that they can be added to their vested amount.
     *
     * @param from                          The user burning the unvested tokens.
     * @param amount                        The amount of tokens to burn.
     */
    function _burnUnvested(address from, uint256 amount) internal {
        unvestedBalanceOf[from] -= amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalUnvestedSupply -= amount;
        }

        // Do NOT emit an event because no free tokens were burned.
    }

    /**
     * @dev Vest tokens by burning the unvested ones and minting free ones.
     *
     * @param to                            The user receiving the vest tokens.
     * @param amount                        The amount of tokens to vest.
     */
    function _vest(address to, uint256 amount) internal {
        _burnUnvested(to, amount);
        _mint(to, amount);
    }
}
