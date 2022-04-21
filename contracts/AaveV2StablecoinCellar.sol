// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IAaveV2StablecoinCellar } from "./interfaces/IAaveV2StablecoinCellar.sol";
import { IAaveIncentivesController } from "./interfaces/IAaveIncentivesController.sol";
import { IStakedTokenV2 } from "./interfaces/IStakedTokenV2.sol";
import { ICurveSwaps } from "./interfaces/ICurveSwaps.sol";
import { ISushiSwapRouter } from "./interfaces/ISushiSwapRouter.sol";
import { IGravity } from "./interfaces/IGravity.sol";
import { ILendingPool } from "./interfaces/ILendingPool.sol";
import { MathUtils } from "./utils/MathUtils.sol";

/**
 * @title Sommelier Aave V2 Stablecoin Cellar
 * @notice Dynamic ERC4626 that changes positions to always get the best yield for stablecoins on Aave.
 * @author Brian Le
 */
contract AaveV2StablecoinCellar is IAaveV2StablecoinCellar, ERC20, Ownable {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    /**
     * @notice The asset that makes up the cellar's holding pool. Will change whenever the cellar
     *         rebalances into a new position.
     * @dev The cellar denotes its inactive assets in this token. While it waits in the holding pool
     *      to be entered into a position, it is used to pay for withdraws from those redeeming their
     *      shares.
     */
    ERC20 public asset;

    /**
     * @notice An interest-bearing derivative of the current asset returned by Aave for lending
     *         assets. Represents cellar's portion of active assets earning yield in a lending
     *         position.
     */
    ERC20 public assetAToken;

    /**
     * @notice The decimals of precision used by the current asset.
     * @dev Some stablecoins (eg. USDC and USDT) don't use the standard 18 decimals of precision.
     *      This is used for converting between decimals when performing calculations in the cellar.
     */
    uint8 public assetDecimals;

    /**
     * @notice Mapping from a user's address to all their deposits and balances.
     * @dev Used in determining which of a user's shares are active (entered into a position earning
     *      yield vs inactive (waiting in the holding pool to be entered into a position and not
     *      earning yield).
     */
    mapping(address => UserDeposit[]) public userDeposits;

    /**
     * @notice Mapping from user's address to the index of first non-zero deposit in `userDeposits`.
     * @dev Saves gas when looping through all user's deposits.
     */
    mapping(address => uint256) public currentDepositIndex;

    /**
     * @notice Whether an asset position is trusted or not. Prevents cellar from rebalancing into an
     *         asset that has not been trusted by the users. Trusting / distrusting of an asset is done
     *         through governance.
     */
    mapping(address => bool) public isTrusted;

    /**
     * @notice Last time all inactive assets were entered into a strategy and made active.
     */
    uint256 public lastTimeEnteredPosition;

    /**
     * @notice The value fees are divided by to get a percentage. Represents maximum percent (100%).
     */
    uint256 private constant DENOMINATOR = 100_00;

    /**
     * @notice The percentage of platform fees (1%) taken off of active assets over a year.
     */
    uint256 private constant PLATFORM_FEE = 1_00;

    /**
     * @notice The percentage of performance fees (10%) taken off of cellar gains.
     */
    uint256 private constant PERFORMANCE_FEE = 10_00;

    /**
     * @notice Stores fee-related data.
     */
    IAaveV2StablecoinCellar.Fees public fees;

    /**
     * @notice Cosmos address of the fee distributor as a hex value.
     * @dev The Gravity contract expects a 32-byte value formatted in a specific way.
     */
    bytes32 public constant feesDistributor = hex"000000000000000000000000b813554b423266bbd4c16c32fa383394868c1f55";

    /**
     * @notice Maximum amount of assets that can be managed by the cellar. Denominated in the same decimals
     *         as the current asset.
     * @dev Set to `type(uint256).max` to have no limit.
     */
    uint256 public liquidityLimit;

    /**
     * @notice Maximum amount of deposits per wallet. Denominated in the same decimals as the current assets.
     * @dev Set to `type(uint256).max` to have no limit.
     */
    uint256 public depositLimit;

    /**
    /**
     * @notice Whether or not the contract is shutdown in case of an emergency.
     */
    bool public isShutdown;

    // ======================================== INITIALIZATION ========================================

    // Curve Registry Exchange contract
    ICurveSwaps public immutable curveRegistryExchange; // 0x8e764bE4288B842791989DB5b8ec067279829809
    // SushiSwap Router V2 contract
    ISushiSwapRouter public immutable sushiswapRouter; // 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
    // Aave Lending Pool V2 contract
    ILendingPool public immutable lendingPool; // 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9
    // Aave Incentives Controller V2 contract
    IAaveIncentivesController public immutable incentivesController; // 0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5
    // Cosmos Gravity Bridge contract
    IGravity public immutable gravityBridge; // 0x69592e6f9d21989a043646fE8225da2600e5A0f7

    IStakedTokenV2 public immutable stkAAVE; // 0x4da27a545c0c5B758a6BA100e3a049001de870f5
    ERC20 public immutable AAVE; // 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9
    ERC20 public immutable WETH; // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

    /**
    /**
     * @dev Owner will be set to the Gravity Bridge, which relays instructions from the Steward
     *      module to the cellars.
     *      https://github.com/PeggyJV/steward
     *      https://github.com/cosmos/gravity-bridge/blob/main/solidity/contracts/Gravity.sol
     * @param _asset current asset managed by the cellar
     * @param _liquidityLimit amount liquidity limit should be initialized to
     * @param _depositLimit amount deposit limit should be initialized to
     * @param _curveRegistryExchange Curve registry exchange
     * @param _sushiswapRouter Sushiswap V2 router address
     * @param _lendingPool Aave V2 lending pool address
     * @param _incentivesController _incentivesController
     * @param _gravityBridge Cosmos Gravity Bridge address
     * @param _stkAAVE stkAAVE address
     * @param _AAVE AAVE address
     * @param _WETH WETH address
     */
    constructor(
        ERC20 _asset,
        uint256 _liquidityLimit,
        uint256 _depositLimit,
        ICurveSwaps _curveRegistryExchange,
        ISushiSwapRouter _sushiswapRouter,
        ILendingPool _lendingPool,
        IAaveIncentivesController _incentivesController,
        IGravity _gravityBridge,
        IStakedTokenV2 _stkAAVE,
        ERC20 _AAVE,
        ERC20 _WETH
    ) ERC20("Sommelier Aave V2 Stablecoin Cellar LP Token", "aave2-CLR-S", 18) {
        // Initialize immutables.
        curveRegistryExchange =  _curveRegistryExchange;
        sushiswapRouter = _sushiswapRouter;
        lendingPool = _lendingPool;
        incentivesController = _incentivesController;
        gravityBridge = _gravityBridge;
        stkAAVE = _stkAAVE;
        AAVE = _AAVE;
        WETH = _WETH;

        // Initialize limits.
        liquidityLimit = _liquidityLimit;
        depositLimit = _depositLimit;

        // Initialize asset.
        isTrusted[address(_asset)] = true;
        _updatePosition(address(_asset));

        // Transfer ownership to the Gravity Bridge
        transferOwnership(address(_gravityBridge));
    }

    // =============================== DEPOSIT/WITHDRAWAL OPERATIONS ===============================

    /**
     * @notice Deposits assets and mints the shares to receiver.
     * @param assets amount of assets to deposit
     * @param receiver address receiving the shares
     * @return shares amount of shares minted
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        // In the case where a user tries to deposit more than their balance, the desired behavior
        // is to deposit what they have instead of reverting.
        uint256 depositableAssets = asset.balanceOf(msg.sender);
        if (assets > depositableAssets) assets = depositableAssets;

        (, shares) = _deposit(assets, 0, receiver);
    }

    /**
     * @notice Mints shares to receiver by depositing assets.
     * @param shares amount of shares to mint
     * @param receiver address receiving the shares
     * @return assets amount of assets deposited
     */
    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        // In the case where a user tries to mint more shares than possible, the desired behavior
        // is to mint as many shares as their balance allows instead of reverting.
        uint256 mintableShares = previewDeposit(asset.balanceOf(msg.sender));
        if (shares > mintableShares) shares = mintableShares;

        (assets, ) = _deposit(0, shares, receiver);
    }


    function _deposit(uint256 assets, uint256 shares, address receiver) internal returns (uint256, uint256) {
        // In case of an emergency or contract vulnerability, we don't want users to be able to
        // deposit more assets into a compromised contract.
        if (isShutdown) revert STATE_ContractShutdown();

        // Must calculate before assets are transferred in.
        shares > 0 ? assets = previewMint(shares) : shares = previewDeposit(assets);

        // Check for rounding error on `deposit` since we round down in previewDeposit. No need to
        // check for rounding error if `mint`, previewMint rounds up.
        if (shares == 0) revert USR_ZeroShares();

        // Enforce deposit restrictions per wallet.
        if (depositLimit != type(uint256).max && assets > maxDeposit(receiver))
            revert USR_DepositRestricted(depositLimit);

        // Check if security restrictions still apply. Enforce them if they do.
        if (liquidityLimit != type(uint256).max && assets + totalAssets() > liquidityLimit)
            revert STATE_LiquidityRestricted(liquidityLimit);

        // Transfers assets into the cellar.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        // Mint user tokens that represents their share of the cellar's assets.
        _mint(receiver, shares);

        // Store the user's deposit data. This will be used later on when the user wants to withdraw
        // their assets or transfer their shares.
        UserDeposit[] storage deposits = userDeposits[receiver];
        deposits.push(UserDeposit({
            // Always store asset amounts with 18 decimals of precision regardless of the asset's
            // decimals. This is so we can still use this data even after rebalancing to different
            // asset.
            assets: uint112(assets.changeDecimals(assetDecimals, decimals)),
            shares: uint112(shares),
            timeDeposited: uint32(block.timestamp)
        }));

        emit Deposit(
            msg.sender,
            receiver,
            address(asset),
            assets,
            shares
        );

        return (assets, shares);
    }

    /**
     * @notice Withdraws assets to receiver by redeeming shares from owner.
     * @param assets amount of assets being withdrawn
     * @param receiver address of account receiving the assets
     * @param owner address of the owner of the shares being redeemed
     * @return shares amount of shares redeemed
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares) {
        // This is done to avoid the possibility of an overflow if `assets` was set to a very high
        // number (like 2**256 – 1)  when trying to change decimals. If a user tries to withdraw
        // more than their balance, the desired behavior is to withdraw as much as possible.
        uint256 withdrawableAssets = previewRedeem(balanceOf[owner]);
        if (assets > withdrawableAssets) assets = withdrawableAssets;

        // Ensures proceeding calculations are done with a standard 18 decimals of precision. Will
        // change back to the using the asset's usual decimals of precision when transferring assets
        // after all calculations are done.
        assets = assets.changeDecimals(assetDecimals, decimals);

        (, shares) = _withdraw(assets, receiver, owner);
    }

    /**
     * @notice Redeems shares from owner to withdraw assets to receiver.
     * @param shares amount of shares redeemed
     * @param receiver address of account receiving the assets
     * @param owner address of the owner of the shares being redeemed
     * @return assets amount of assets sent to receiver
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets) {
        // This is done to avoid the possibility of an overflow if `shares` was set to a very high
        // number (like 2**256 – 1) when trying to change decimals. If a user tries to redeem more
        // than their balance, the desired behavior is to redeem as much as possible.
        uint256 redeemableShares = maxRedeem(owner);
        if (shares > redeemableShares) shares = redeemableShares;

        (assets, ) = _withdraw(_convertToAssets(shares), receiver, owner);
    }

    /**
     * @dev `assets` must be passed in with 18 decimals of precision. Must extend/truncate decimals of
     *       the amount passed in if necessary to ensure this is true.
     */
    function _withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) internal returns (uint256, uint256) {
        if (balanceOf[owner] == 0) revert USR_ZeroShares();
        if (assets == 0) revert USR_ZeroAssets();

        // Tracks the total amount of shares being redeemed for the amount of assets withdrawn.
        uint256 shares;

        // Retrieve the user's deposits to begin looping through them, generally from oldest to
        // newest deposits. This may not be the case though if shares have been transferred to the
        // owner, which will be added to the end of the owner's deposits regardless of time
        // deposited.
        UserDeposit[] storage deposits = userDeposits[owner];

        // Tracks the amount of assets left to withdraw. Updated at the end of each loop.
        uint256 leftToWithdraw = assets;

        // Saves gas by avoiding calling `_convertToAssets` on active shares during each loop.
        uint256 exchangeRate = _convertToAssets(1e18);

        for (uint256 i = currentDepositIndex[owner]; i < deposits.length; i++) {
            UserDeposit storage d = deposits[i];

            // Whether or not deposited shares are active or inactive.
            bool isActive = d.timeDeposited <= lastTimeEnteredPosition;

            // If shares are active, convert them to the amount of assets they're worth to see the
            // maximum amount of assets we can take from this deposit.
            uint256 dAssets = isActive ? uint256(d.shares).mulWadDown(exchangeRate) : d.assets;

            // Determine the amount of assets and shares to withdraw from this deposit.
            uint256 withdrawnAssets = MathUtils.min(leftToWithdraw, dAssets);
            uint256 withdrawnShares = uint256(d.shares).mulDivUp(withdrawnAssets, dAssets);

            // For active shares, deletes the deposit data we don't need anymore for a gas refund.
            if (isActive) {
                delete d.assets;
                delete d.timeDeposited;
            } else {
                d.assets -= uint112(withdrawnAssets);
            }

            // Take the shares we need from this deposit and add them to our total.
            d.shares -= uint112(withdrawnShares);
            shares += withdrawnShares;

            // Update the counter of assets we have left to withdraw.
            leftToWithdraw -= withdrawnAssets;

            // Finish if this is the last deposit or there is nothing left to withdraw.
            if (i == deposits.length - 1 || leftToWithdraw == 0) {
                // Store the user's next non-zero deposit to save gas on future looping.
                currentDepositIndex[owner] = d.shares != 0 ? i : i+1;
                break;
            }
        }

        // If the caller is not the owner of the shares, check to see if the owner has approved them
        // to spend their shares.
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Redeem shares for assets.
        _burn(owner, shares);

        // Determine the total amount of assets withdrawn.
        assets -= leftToWithdraw;

        // Convert assets decimals back to get ready for transfers.
        assets = assets.changeDecimals(decimals, assetDecimals);

        // Only withdraw from position if holding pool does not contain enough funds.
        _allocateAssets(assets);

        // Transfer assets to receiver from the cellar's holding pool.
        asset.safeTransfer(receiver, assets);

        emit Withdraw(receiver, owner, address(asset), assets, shares);

        // Returns the amount of assets withdrawn and amount of shares redeemed. The amount of
        // assets withdrawn may differ from the amount of assets specified when calling the function
        // if the user has less assets then they tried withdrawing.
        return (assets, shares);
    }

    // ================================== ACCOUNTING OPERATIONS ==================================

    /**
     * @dev The internal functions always use 18 decimals of precision while the public functions use
     *      as many decimals as the current asset (aka they don't change the decimals). This is
     *      because we want the user deposit data the cellar stores to be usable across different
     *      assets regardless of the decimals used. This means the cellar will always perform
     *      calculations and store data with a standard of 18 decimals of precision but will change
     *      the decimals back when transferring assets outside the contract or returning data
     *      through public view functions.
     */

    /**
     * @notice Total amount of active asset entered into a position.
     * @dev The aTokens' value is pegged to the value of the corresponding asset at a 1:1 ratio. We
     *      can find the amount of assets active in a position simply by taking balance of aTokens
     *      cellar holds.
     */
    function activeAssets() public view returns (uint256) {
        return assetAToken.balanceOf(address(this));
    }

    function _activeAssets() internal view returns (uint256) {
        uint256 assets = assetAToken.balanceOf(address(this));
        return assets.changeDecimals(assetDecimals, decimals);
    }

    /**
     * @notice Total amount of inactive asset waiting in a holding pool to be entered into a position.
     */
    function inactiveAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _inactiveAssets() internal view returns (uint256) {
        uint256 assets = asset.balanceOf(address(this));
        return assets.changeDecimals(assetDecimals, decimals);
    }

    /**
     * @notice Total amount of the asset that is managed by cellar.
     */
    function totalAssets() public view returns (uint256) {
        return activeAssets() + inactiveAssets();
    }

    function _totalAssets() internal view returns (uint256) {
        return _activeAssets() + _inactiveAssets();
    }

    /**
     * @notice The amount of shares that the cellar would exchange for the amount of assets provided
     *         ONLY if they are active.
     * @param assets amount of assets to convert
     * @return shares the assets can be exchanged for
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        assets = assets.changeDecimals(assetDecimals, decimals);
        return _convertToShares(assets);
    }

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        return totalSupply == 0 ? assets : assets.mulDivDown(totalSupply, _totalAssets());
    }

    /**
     * @notice The amount of assets that the cellar would exchange for the amount of shares provided
     *         ONLY if they are active.
     * @param shares amount of shares to convert
     * @return assets the shares can be exchanged for
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 assets = _convertToAssets(shares);
        return assets.changeDecimals(decimals, assetDecimals);
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        return totalSupply == 0 ? shares : shares.mulDivDown(_totalAssets(), totalSupply);
    }

    /**
    * @notice Simulate the effects of depositing assets at the current block, given current on-chain
    *         conditions.
     * @param assets amount of assets to deposit
     * @return shares that will be minted
     */
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    /**
    * @notice Simulate the effects of minting shares at the current block, given current on-chain
    *         conditions.
     * @param shares amount of shares to mint
     * @return assets that will be deposited
     */
    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        uint256 assets = supply == 0 ? shares : shares.mulDivUp(_totalAssets(), supply);
        return assets.changeDecimals(decimals, assetDecimals);
    }

    /**
    * @notice Simulate the effects of withdrawing assets at the current block, given current
    *         on-chain conditions. Assumes the shares being redeemed are all active.
     * @param assets amount of assets to withdraw
     * @return shares that will be redeemed
     */
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    /**
    * @notice Simulate the effects of redeeming shares at the current block, given current on-chain
    *         conditions. Assumes the shares being redeemed are all active.
     * @param shares amount of sharers to redeem
     * @return assets that can be withdrawn
     */
    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    // ======================================= STATE INFORMATION =====================================

    /**
     * @notice Retrieve information on a user's deposit balances.
     * @param user address of the user
     * @return userActiveShares amount of active shares the user has
     * @return userInactiveShares amount of inactive shares the user has
     * @return userActiveAssets amount of active assets the user has
     * @return userInactiveAssets amount of inactive assets the user has
     */
    function getUserBalances(address user) external view returns (
        uint256 userActiveShares,
        uint256 userInactiveShares,
        uint256 userActiveAssets,
        uint256 userInactiveAssets
    ) {
        // Retrieve the user's deposits to begin looping through them, generally from oldest to
        // newest deposits. This may not be the case though if shares have been transferred to the
        // user, which will be added to the end of the user's deposits regardless of time
        // deposited.
        UserDeposit[] storage deposits = userDeposits[user];

        // Saves gas by avoiding calling `_convertToAssets` on active shares during each loop.
        uint256 exchangeRate = _convertToAssets(1e18);

        for (uint256 i = currentDepositIndex[user]; i < deposits.length; i++) {
            UserDeposit storage d = deposits[i];

            // Determine whether or not deposit is active or inactive.
            if (d.timeDeposited <= lastTimeEnteredPosition) {
                // Saves an extra SLOAD if active and cast type to uint256.
                uint256 dShares = d.shares;

                userActiveShares += dShares;
                userActiveAssets += dShares.mulWadDown(exchangeRate); // Convert shares to assets.
            } else {
                userInactiveShares += d.shares;
                userInactiveAssets += d.assets;
            }
        }

        // Return assets in their original units.
        userActiveAssets = userActiveAssets.changeDecimals(decimals, assetDecimals);
        userInactiveAssets = userInactiveAssets.changeDecimals(decimals, assetDecimals);
    }

    /**
     * @notice Gets all of a user's deposits.
     * @dev This is provided because Solidity converts public arrays into index getters,
     *      but we need a way to allow external contracts and users to access the whole array.
     * @param user address of the user
     * @return array of all the users deposits
     */
    function getUserDeposits(address user) external view returns (UserDeposit[] memory) {
        return userDeposits[user];
    }

    // =========================== DEPOSIT/WITHDRAWAL LIMIT OPERATIONS ===========================

    /**
     * @notice Total number of assets that can be deposited by owner into the cellar.
     * @param owner address of account that would receive the shares
     * @return maximum amount of assets that can be deposited
     */
    function maxDeposit(address owner) public view returns (uint256) {
        if (isShutdown) return 0;

        if (depositLimit == type(uint256).max) return type(uint256).max;

        uint256 assets = previewRedeem(balanceOf[owner]);

        return depositLimit > assets ? depositLimit - assets : 0;
    }

    /**
     * @notice Total number of shares that can be minted for owner from the cellar.
     * @dev Limits mints to $50k of shares per wallet.
     * @param owner address of account that would receive the shares
     * @return maximum amount of shares that can be minted
     */
    function maxMint(address owner) public view returns (uint256) {
        if (isShutdown) return 0;

        if (liquidityLimit == type(uint256).max) return type(uint256).max;

        uint256 mintLimit = previewDeposit(50_000 * 10**assetDecimals);
        uint256 shares = balanceOf[owner];

        return mintLimit > shares ? mintLimit - shares : 0;
    }

    /**
     * @notice Total number of assets that can be withdrawn from the cellar.
     * @param owner address of account that would holds the shares
     * @return maximum amount of assets that can be withdrawn
     */
    function maxWithdraw(address owner) public view returns (uint256) {
        UserDeposit[] storage deposits = userDeposits[owner];

        // Track max assets that can be withdrawn.
        uint256 assets;

        // Saves gas by avoiding calling `_convertToAssets` on active shares during each loop.
        uint256 exchangeRate = _convertToAssets(1e18);

        for (uint256 i = currentDepositIndex[owner]; i < deposits.length; i++) {
            UserDeposit storage d = deposits[i];

            // Determine the amount of assets that can be withdrawn. Only redeem active shares for
            // assets, otherwise just withdrawn the original amount of assets that were deposited.
            assets += d.timeDeposited <= lastTimeEnteredPosition ?
                uint256(d.shares).mulWadDown(exchangeRate) :
                d.assets;
        }

        // Return the maximum amount of assets that can be withdrawn in the assets original units.
        return assets.changeDecimals(decimals, assetDecimals);
    }

    /**
     * @notice Total number of shares that can be redeemed from the cellar.
     * @param owner address of account that would holds the shares
     * @return maximum amount of shares that can be redeemed
     */
    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf[owner];
    }

    // ====================================== FEE OPERATIONS ======================================

    /**
     * @notice Take platform fees and performance fees off of cellar's active assets.
     */
    function accrueFees() external updateYield {
        // Platform fees taken each accrual = activeAssets * (elapsedTime * (2% / SECS_PER_YEAR)).
        uint256 elapsedTime = block.timestamp - fees.lastTimeAccruedPlatformFees;
        uint256 platformFeeInAssets = (_activeAssets() * elapsedTime * PLATFORM_FEE) / DENOMINATOR / 365 days;
        uint256 platformFees = _convertToShares(platformFeeInAssets);

        // Update tracking of last time platform fees were accrued.
        fees.lastTimeAccruedPlatformFees = uint32(block.timestamp);

        // Mint the cellar accrued platform fees as shares.
        _mint(address(this), platformFees);

        // Performance fees taken each accrual = yield * 10%
        uint256 yield = fees.yield;
        uint256 performanceFeeInAssets = yield.mulDivDown(PERFORMANCE_FEE, DENOMINATOR);
        uint256 performanceFees = _convertToShares(performanceFeeInAssets);

        // Reset tracking of yield since last accrual.
        fees.yield = 0;

        // Mint the cellar accrued performance fees as shares.
        _mint(address(this), performanceFees);

        // Update fees that have been accrued.
        fees.accruedPlatformFees += uint112(platformFees);
        fees.accruedPerformanceFees += uint112(performanceFees);

        emit AccruedPlatformFees(platformFees);
        emit AccruedPerformanceFees(performanceFees);
    }

    /**
     * @notice Update information tracking yield the cellar has earned.
     * @dev Must be called every time a function is called that changes `activeAssets`.
     */
    modifier updateYield() {
        uint256 currentActiveAssets = _activeAssets();
        uint256 lastActiveAssets = fees.lastActiveAssets;

        if (currentActiveAssets > lastActiveAssets) {
            fees.yield += uint112(currentActiveAssets - lastActiveAssets);
        }

        _;

        // Update this for next performance fee accrual.
        fees.lastActiveAssets = uint112(_activeAssets());
    }

    /**
     * @notice Transfer accrued fees to Cosmos to distribute.
     */
    function transferFees() external onlyOwner {
        // Cellar fees are accrued in shares and redeemed upon transfer.
        uint256 totalFees = ERC20(this).balanceOf(address(this));
        uint256 feeInAssets = previewRedeem(totalFees);

        // Redeem our fee shares for assets to transfer to Cosmos.
        _burn(address(this), totalFees);

        // Only withdraw assets from position if the holding pool does not contain enough funds.
        // Otherwise, all assets will come from the holding pool.
        _allocateAssets(feeInAssets);

        // Transfer assets to a fee distributor on Cosmos.
        asset.safeApprove(address(gravityBridge), feeInAssets);
        gravityBridge.sendToCosmos(address(asset), feesDistributor, feeInAssets);

        emit TransferFees(fees.accruedPlatformFees, fees.accruedPerformanceFees);

        // Reset the tracker for fees accrued that are still waiting to be transferred.
        fees.accruedPlatformFees = 0;
        fees.accruedPerformanceFees = 0;
    }

    // =================================== GOVERNANCE OPERATIONS ===================================

    /**
     * @notice Trust or distrust an asset position on Aave (eg. FRAX, UST, FEI).
     */
    function setTrust(address position, bool trust) external onlyOwner {
        isTrusted[position] = trust;

        // In the case that governance no longer trust the current position, pull all assets back into
        // the cellar.
        if (trust == false && position == address(asset)) {
            _withdrawFromAave(address(asset), type(uint256).max);
        }
    }

    /**
     * @notice Stop or start the contract. Should only be used in an emergency,
     */
    function setShutdown(bool shutdown, bool exitPosition) external onlyOwner {
        isShutdown = shutdown;

        // Withdraw everything from the current position on Aave if specified when shutting down.
        if (shutdown && exitPosition) _withdrawFromAave(address(asset), type(uint256).max);

        emit Shutdown(shutdown, exitPosition);
    }

    // ===================================== ADMIN OPERATIONS =====================================

    /**
     * @notice Enters into the current Aave stablecoin position.
     */
    function enterPosition() external onlyOwner {
        if (isShutdown) revert STATE_ContractShutdown();

        uint256 currentInactiveAssets = inactiveAssets();

        // Deposits all inactive assets in the holding pool into the current position.
        _depositToAave(address(asset), currentInactiveAssets);

        // The cellar will use this when determining which of a user's shares are active vs inactive.
        lastTimeEnteredPosition = block.timestamp;

        emit EnterPosition(address(asset), currentInactiveAssets);
    }

    /**
     * @notice Rebalances current assets into a new asset position.
     * @param route array of [initial token, pool, token, pool, token, ...] that specifies the swap route
     * @param swapParams multidimensional array of [i, j, swap type] where i and j are the correct
                         values for the n'th pool in `_route` and swap type should be 1 for a
                         stableswap `exchange`, 2 for stableswap `exchange_underlying`, 3 for a
                         cryptoswap `exchange`, 4 for a cryptoswap `exchange_underlying` and 5 for
                         Polygon factory metapools `exchange_underlying`
     * @param minAmountOut minimum amount received after the final swap
     */
    function rebalance(
        address[9] memory route,
        uint256[3][4] memory swapParams,
        uint256 minAmountOut
    ) external onlyOwner {
        if (isShutdown) revert STATE_ContractShutdown();

        // Retrieve the last token in the route and store it as the new asset.
        address newAsset;
        for (uint256 i; ; i += 2) {
            if (i == 8 || route[i+1] == address(0)) {
                newAsset = route[i];
                break;
            }
        }

        // Doesn't make sense to rebalance into the same asset.
        if (newAsset == address(asset)) revert STATE_SameAsset(newAsset);

        // Pull all active assets entered into Aave back into the cellar so we can swap everything
        // into the new asset.
        _withdrawFromAave(address(asset), type(uint256).max);

        uint256 currentInactiveAssets = inactiveAssets();

        // Approve Curve to swap the cellar's assets.
        asset.safeApprove(address(curveRegistryExchange), currentInactiveAssets);

        // Perform stablecoin swap using Curve.
        uint256 amountOut = curveRegistryExchange.exchange_multiple(
            route,
            swapParams,
            currentInactiveAssets,
            minAmountOut
        );

        // Store this later for the event we will emit.
        address oldAsset = address(asset);

        // Updates state for our new position and check to make sure Aave supports it before
        // rebalancing.
        _updatePosition(newAsset);

        // Deposit all newly swapped assets into Aave.
        _depositToAave(address(asset), amountOut);

        // Update the last time all inactive assets were entered into a position.
        lastTimeEnteredPosition = block.timestamp;

        emit Rebalance(oldAsset, newAsset, amountOut);
    }

    /**
     * @notice Reinvest rewards back into cellar's current position.
     * @dev Must be called within 2 day unstake period 10 days after `claimAndUnstake` was run.
     * @param minAmountOut minimum amount of assets cellar should receive after swap
     */
    function reinvest(uint256 minAmountOut) external onlyOwner {
        // Redeems the cellar's stkAAVE rewards for AAVE.
        stkAAVE.redeem(address(this), type(uint256).max);

        uint256 amountIn = AAVE.balanceOf(address(this));

        // Approve the Sushiswap to swap AAVE.
        AAVE.safeApprove(address(sushiswapRouter), amountIn);

        // Specify the swap path from AAVE -> WETH -> current asset.
        address[] memory path = new address[](3);
        path[0] = address(AAVE);
        path[1] = address(WETH);
        path[2] = address(asset);

        // Perform a multihop swap using Sushiswap.
        uint256[] memory amounts = sushiswapRouter.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 60
        );

        uint256 amountOut = amounts[amounts.length - 1];

        // Consider reinvested rewards yield.
        fees.yield += uint112(amountOut.changeDecimals(assetDecimals, decimals));

        // In the case of a shutdown, we just may want to redeem any leftover rewards for users to
        // claim but without entering them back into a position in case the position has been exited.
        if (!isShutdown) {
            // Reinvest rewards back into the current position.
            _depositToAave(address(asset), amountOut);

            emit Reinvest(address(asset), amountIn, amountOut);
        }
    }

    /**
     * @notice Claim rewards from Aave and begin cooldown period to unstake them.
     * @return claimed amount of rewards claimed from Aave
     */
    function claimAndUnstake() external onlyOwner returns (uint256 claimed) {
        // Necessary to do as `claimRewards` accepts a dynamic array as first param.
        address[] memory aToken = new address[](1);
        aToken[0] = address(assetAToken);

        // Claim all stkAAVE rewards.
        claimed = incentivesController.claimRewards(aToken, type(uint256).max, address(this));

        // Begin the cooldown period for unstaking stkAAVE to later redeem for AAVE.
        stkAAVE.cooldown();

        emit ClaimAndUnstake(claimed);
    }

    /**
     * @notice Sweep tokens sent here that are not managed by the cellar.
     * @dev This may be used in case the wrong tokens are accidentally sent to this contract.
     * @param token address of token to transfer out of this cellar
     */
    function sweep(address token) external onlyOwner {
        // Prevent sweeping of assets managed by the cellar and shares minted to the cellar as fees.
        if (token == address(asset) || token == address(assetAToken) || token == address(this))
            revert STATE_ProtectedAsset(token);

        // Transfer out tokens in this cellar that shouldn't be here.
        uint256 amount = ERC20(token).balanceOf(address(this));
        ERC20(token).safeTransfer(msg.sender, amount);

        emit Sweep(token, amount);
    }

    /**
     * @notice Sets the maximum liquidity that cellar can manage. Careful to use the same decimals as the
     *         current asset.
     */
    function setLiquidityLimit(uint256 limit) external onlyOwner {
        // Store for emitted event.
        uint256 oldLimit = liquidityLimit;

        liquidityLimit = limit;

        emit LiquidityLimitChanged(oldLimit, limit);
    }

    /**
     * @notice Sets per-wallet deposit limit. Careful to use the same decimals as the current asset.
     */
    function setDepositLimit(uint256 limit) external onlyOwner {
        // Store for emitted event.
        uint256 oldLimit = depositLimit;

        depositLimit = limit;

        emit DepositLimitChanged(oldLimit, limit);
    }

    // ========================================== HELPERS ==========================================

    /**
     * @notice Update state variables related to the current position.
     * @dev Be aware that when updating to an asset that uses less decimals of precision than the
     *      previous (eg. DAI -> USDC), `depositLimit` and `liquidityLimit` will lose some data in
     *      the conversion.
     * @param newAsset address of the new asset being managed by the cellar
     */
    function _updatePosition(address newAsset) internal {
        // Retrieve the aToken that will represent the cellar's new position on Aave.
        (, , , , , , , address aTokenAddress, , , , ) = lendingPool.getReserveData(newAsset);

        // If the address is not null, it is supported by Aave.
        if (aTokenAddress == address(0)) revert STATE_TokenIsNotSupportedByAave(newAsset);

        // Update the decimals for limits if necessary.
        uint8 oldAssetDecimals = assetDecimals;
        uint8 newAssetDecimals = ERC20(newAsset).decimals();

        // Ignore if decimals are the same or first time initializing position.
        if (oldAssetDecimals != 0 && oldAssetDecimals != newAssetDecimals) {
            if (depositLimit != type(uint256).max) {
                depositLimit = depositLimit.changeDecimals(oldAssetDecimals, newAssetDecimals);
            }

            if (liquidityLimit != type(uint256).max) {
                liquidityLimit = liquidityLimit.changeDecimals(oldAssetDecimals, newAssetDecimals);
            }
        }

        // Update state related to the current position.
        asset = ERC20(newAsset);
        assetDecimals = newAssetDecimals;
        assetAToken = ERC20(aTokenAddress);
    }

    /**
     * @notice Ensures there is enough assets in the contract available for a transfer.
     * @dev Only withdraws from position if needed.
     * @param assets The amount of assets to allocate
     */
    function _allocateAssets(uint256 assets) internal {
        uint256 currentInactiveAssets = inactiveAssets();

        if (assets > currentInactiveAssets) {
            _withdrawFromAave(address(asset), assets - currentInactiveAssets);
        }
    }

    /**
     * @notice Deposits cellar holdings into an Aave lending pool.
     * @param token the address of the token
     * @param amount the amount of tokens to deposit
     */
    function _depositToAave(address token, uint256 amount) internal updateYield {
        // Ensure the position has been trusted by governance.
        if (!isTrusted[token]) revert STATE_UntrustedPosition(token);

        // Initialize starting point for first platform fee accrual to time when cellar first deposits
        // assets into a position on Aave.
        if (fees.lastTimeAccruedPlatformFees == 0) {
            fees.lastTimeAccruedPlatformFees = uint32(block.timestamp);
        }

        ERC20(token).safeApprove(address(lendingPool), amount);

        // Deposit tokens to Aave protocol.
        lendingPool.deposit(token, amount, address(this), 0);

        emit DepositToAave(token, amount);
    }

    /**
     * @notice Withdraws assets from Aave.
     * @param token the address of the token
     * @param amount the amount of tokens to withdraw
     */
    function _withdrawFromAave(address token, uint256 amount) internal updateYield {
        // Skip withdrawal instead of reverting if there are no active assets to withdraw. Reverting
        // could potentially prevent important function calls from executing, such as `shutdown`,
        // in the case where there were no active assets because Aave would throw an error.
        if (activeAssets() > 0) {
            // Withdraw tokens from Aave protocol
            uint256 withdrawnAmount = lendingPool.withdraw(token, amount, address(this));

            emit WithdrawFromAave(token, withdrawnAmount);
        }
    }

    // ================================= SHARE TRANSFER OPERATIONS =================================

    /**
     * @dev Modified versions of Solmate's ERC20 transfer and transferFrom functions to work with the
     *      cellar's active vs inactive shares mechanic.
     */

    /**
     * @notice Transfers shares from one account to another.
     * @dev If the sender specifies to only transfer active shares and does not have enough active
     *      shares to transfer to meet the amount specified, the default behavior is to not to
     *      revert but transfer as many active shares as the sender has to the receiver.
     * @param from address that is sending shares
     * @param to address that is receiving shares
     * @param amount amount of shares to transfer
     * @param onlyActive whether to only transfer active shares
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount,
        bool onlyActive
    ) public returns (bool) {
        // If the sender is not the owner of the shares, check to see if the owner has approved them
        // to spend their shares.
        if (from != msg.sender) {
            uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        }

        // Retrieve the deposits from sender then begin looping through deposits, generally from
        // oldest to newest deposits. This may not be the case though if shares have been
        // transferred to the sender, as they will be added to the end of the sender's deposits
        // regardless of time deposited.
        UserDeposit[] storage depositsFrom = userDeposits[from];

        // Tracks the amount of shares left to transfer; updated at the end of each loop.
        uint256 leftToTransfer = amount;

        for (uint256 i = currentDepositIndex[from]; i < depositsFrom.length; i++) {
            UserDeposit storage dFrom = depositsFrom[i];

            // If we only want to transfer active shares, skips this deposit if it is inactive.
            bool isActive = dFrom.timeDeposited <= lastTimeEnteredPosition;
            if (onlyActive && !isActive) continue;

            // Saves an extra SLOAD if active and cast type to uint256.
            uint256 dFromShares = dFrom.shares;

            // Determine the amount of assets and shares to transfer from this deposit.
            uint256 transferredShares = MathUtils.min(leftToTransfer, dFromShares);
            uint256 transferredAssets = uint256(dFrom.assets).mulDivUp(transferredShares, dFromShares);

            // For active shares, deletes the deposit data we don't need anymore for a gas refund.
            if (isActive) {
                delete dFrom.assets;
                delete dFrom.timeDeposited;
            } else {
                dFrom.assets -= uint112(transferredAssets);
            }

            // Taken shares from this deposit to transfer.
            dFrom.shares -= uint112(transferredShares);

            // Transfer a new deposit to the end of receiver's list of deposits.
            userDeposits[to].push(UserDeposit({
                assets: isActive ? 0 : uint112(transferredAssets),
                shares: uint112(transferredShares),
                timeDeposited: isActive ? 0 : dFrom.timeDeposited
            }));

            // Update the counter of assets left to transfer.
            leftToTransfer -= transferredShares;

            if (i == depositsFrom.length - 1 || leftToTransfer == 0) {
                // Only store the index for the next non-zero deposit to save gas on looping if
                // inactive deposits weren't skipped.
                if (!onlyActive) currentDepositIndex[from] = dFrom.shares != 0 ? i : i+1;
                break;
            }
        }

        // Determine the total amount of shares transferred.
        amount -= leftToTransfer;

        // Will revert here if sender is trying to transfer more shares then they have, so no need
        // for an explicit check.
        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /// @dev For compatibility with ERC20 standard.
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Defaults to allowing both active and inactive shares to be transferred.
        return transferFrom(from, to, amount, false);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        // Defaults to allowing both active and inactive shares to be transferred.
        return transferFrom(msg.sender, to, amount, false);
    }
}
