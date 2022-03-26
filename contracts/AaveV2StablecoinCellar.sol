// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.11;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./utils/MathUtils.sol";
import "./interfaces/IAaveV2StablecoinCellar.sol";
import "./interfaces/IAaveIncentivesController.sol";
import "./interfaces/IStakedTokenV2.sol";
import "./interfaces/ISushiSwapRouter.sol";
import "./interfaces/IGravity.sol";
import "./interfaces/ILendingPool.sol";

/**
 * @title Sommelier Aave V2 Stablecoin Cellar
 * @notice AaveV2StablecoinCellar contract for Sommelier Network
 * @author Sommelier Finance
 */
contract AaveV2StablecoinCellar is IAaveV2StablecoinCellar, ERC20, Ownable {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    /**
     * @notice The asset that makes up the cellar's holding pool. Will change when the cellar
     *         rebalances into a new strategy.
     * @dev The cellar denotes its inactive assets in this token. While it waits in the holding pool
     *      to be entered into a strategy, it is used to pay for withdraws from those redeeming their
     *      shares.
     */
    ERC20 public asset;

    /**
     * @notice An interest-bearing derivative of the current asset returned by Aave for lending
     *         assets. Represents cellar's portion of active assets earning yield in a lending
     *         strategy.
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
     * @dev Used in determining which of a user's shares are active (entered into a strategy earning
     *      yield vs inactve (waiting in the holding pool to be entered into a strategy and not
     *      earning yield).
     */
    mapping(address => UserDeposit[]) public userDeposits;

    /**
     * @notice Mapping from user's address to the index of first non-zero deposit in `userDeposits`.
     * @dev Saves gas when looping through all user's deposits.
     */
    mapping(address => uint256) public currentDepositIndex;

    /**
     * @notice Last time all inactive assets were entered into a strategy and made active.
     */
    uint256 public lastTimeEnteredStrategy;

    /**
     * @notice Maximum amount of assets that can be managed by the cellar. Denominated in the same
     *         units as the current asset.
     * @dev Limited to $5m until after security audits.
     */
    uint256 public maxLiquidity;

    /**
     * @notice The value fees are divided by to get a percentage. Represents maximum percent (100%).
     */
    uint256 public constant DENOMINATOR = 100_00;

    /**
     * @notice The percentage of platform fees (1%) taken off of active assets over a year.
     */
    uint256 public constant PLATFORM_FEE = 1_00;

    /**
     * @notice The percentage of performance fees (5%) taken off of cellar gains.
     */
    uint256 public constant PERFORMANCE_FEE = 5_00;

    /**
     * @notice Struct where fee data gets updated and stored.
     * @dev This is stored in a struct purely to avoid stack too deep errors.
     */
    FeesData public feesData;

    /**
     * @notice Whether or not the contract is paused in case of an emergency.
     */
    bool public isPaused;

    /**
     * @notice Whether or not the contract is permanently shutdown in case of an emergency.
     */
    bool public isShutdown;

    // ======================================== IMMUTABLES ========================================

    // Uniswap Router V3 contract
    ISwapRouter public immutable uniswapRouter; // 0xE592427A0AEce92De3Edee1F18E0157C05861564
    // SushiSwap Router V2 contract
    ISushiSwapRouter public immutable sushiswapRouter; // 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
    // Aave Lending Pool V2 contract
    ILendingPool public immutable lendingPool; // 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9
    // Aave Incentives Controller V2 contract
    IAaveIncentivesController public immutable incentivesController; // 0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5
    // Cosmos Gravity Bridge contract
    Gravity public immutable gravityBridge; // 0x69592e6f9d21989a043646fE8225da2600e5A0f7
    // Cosmos address of fee distributor
    bytes32 public feesDistributor; // TBD, then make immutable

    IStakedTokenV2 public immutable stkAAVE; // 0x4da27a545c0c5B758a6BA100e3a049001de870f5
    ERC20 public immutable AAVE; // 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9

    /**
     * @param _asset current asset managed by the cellar
     * @param _uniswapRouter Uniswap V3 swap router address
     * @param _sushiswapRouter Sushiswap V2 router address
     * @param _lendingPool Aave V2 lending pool address
     * @param _incentivesController _incentivesController
     * @param _gravityBridge Cosmos Gravity Bridge address
     * @param _stkAAVE stkAAVE address
     * @param _AAVE AAVE address
     */
    constructor(
        ERC20 _asset,
        ISwapRouter _uniswapRouter,
        ISushiSwapRouter _sushiswapRouter,
        ILendingPool _lendingPool,
        IAaveIncentivesController _incentivesController,
        Gravity _gravityBridge,
        IStakedTokenV2 _stkAAVE,
        ERC20 _AAVE
    ) ERC20("Sommelier Aave V2 Stablecoin Cellar LP Token", "aave2-CLR-S", 18) Ownable() {
        uniswapRouter =  _uniswapRouter;
        sushiswapRouter = _sushiswapRouter;
        lendingPool = _lendingPool;
        incentivesController = _incentivesController;
        gravityBridge = _gravityBridge;
        stkAAVE = _stkAAVE;
        AAVE = _AAVE;

        // Initialize asset.
        _updateStategy(address(_asset));

        // Initialize starting point for platform fee accrual to time when cellar was created.
        // Otherwise it would incorrectly calculate how much platform fees to take when accrueFees
        // is called for the first time.
        feesData.lastTimeAccruedPlatformFees = block.timestamp;
    }

    // ================================= DEPOSIT/WITHDRAWAL OPERATIONS =================================

    /**
     * @notice Deposits assets and mints the shares to receiver.
     * @param assets amount of assets to deposit
     * @param receiver address receiving the shares
     * @return shares amount of shares minted
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public returns (uint256 shares) {
        // In case of an emergency or contract vulernability, we don't want users to be able to
        // deposit more assets into a compromised contract.
        if (isPaused) revert ContractPaused();
        if (isShutdown) revert ContractShutdown();

        // In the case where a user tries to deposit more than their balance, the desired behavior
        // is to deposit what they have instead of reverting.
        uint256 balance = ERC20(asset).balanceOf(msg.sender);
        if (assets > balance) assets = balance;

        // Check if security restrictions still apply. Enforce them if they do.
        if (maxLiquidity != type(uint256).max) {
            if (assets + totalAssets() > maxLiquidity) revert LiquidityRestricted(maxLiquidity);
            if (assets > maxDeposit(receiver)) revert DepositRestricted(50_000 * 10**assetDecimals);
        }

        // Must calculate shares before assets are transfered in. Reverts if no assets were deposited.
        if ((shares = previewDeposit(assets)) == 0) revert ZeroAssets();

        // Transfers assets into the cellar.
        ERC20(asset).safeTransferFrom(msg.sender, address(this), assets);

        // Mint user a token that represents their share of the cellar's assets.
        _mint(receiver, shares);

        // Store the user's deposit data. This will be used later on when the user wants to withdraw
        // their assets or transfer their shares.
        UserDeposit[] storage deposits = userDeposits[receiver];
        deposits.push(UserDeposit({
            // Always store asset amounts with 18 decimals of precision regardless of the asset's
            // decimals. This is so we can still use this data even after rebalancing to different
            // asset.
            assets: assets.changeDecimals(assetDecimals, decimals),
            shares: shares,
            timeDeposited: block.timestamp
        }));

        emit Deposit(
            msg.sender,
            receiver,
            address(asset),
            assets,
            shares
        );
    }

    /**
     * @notice Mints shares to receiver by depositing assets.
     * @param shares amount of shares to mint
     * @param receiver address receiving the shares
     * @return assets amount of assets deposited
     */
    function mint(uint256 shares, address receiver) external returns (uint256) {
        shares = deposit(previewMint(shares), receiver);

        return convertToAssets(shares);
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
        uint256 maxWithdrableAssets = previewRedeem(balanceOf[owner]);
        if (assets > maxWithdrableAssets) assets = maxWithdrableAssets;

        (shares, ) = _withdraw(assets, receiver, owner);
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
        uint256 maxRedeemableShares = maxRedeem(owner);
        if (shares > maxRedeemableShares) shares = maxRedeemableShares;

        (, assets) = _withdraw(previewRedeem(shares), receiver, owner);
    }

    function _withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) internal returns (uint256, uint256) {
        if (balanceOf[owner] == 0) revert ZeroShares();
        if (assets == 0) revert ZeroAssets();

        // Ensures proceeding calculations are done with a standard 18 decimals of precision. Will
        // change back to the using the asset's usual decimals of precision when transferring assets
        // after all calculations are done.
        assets = assets.changeDecimals(assetDecimals, decimals);

        // Tracks the total amount of shares being redeemed for the amount of assets withdrawn.
        uint256 shares;

        // Retrieve the user's deposits to begin looping through them, generally from oldest to
        // newest deposits. This is not be the case though if shares have been transferred to the
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
            bool isActive = d.timeDeposited < lastTimeEnteredStrategy;

            // If shares are active, convert them to the amount of assets they're worth to see the
            // maximum amount of assets we can take from this deposit.
            uint256 dAssets = isActive ? d.shares.mulWadDown(exchangeRate) : d.assets;

            // Determine the amount of assets we need from this deposit.
            uint256 withdrawnAssets = MathUtils.min(leftToWithdraw, dAssets);

            // Determine the amount of shares we'd have to redeem to get the amount of assets we
            // need.
            uint256 withdrawnShares = d.shares.mulDivUp(withdrawnAssets, dAssets);

            // Either deletes the assets data for a gas refund since we won't need it anymore or
            // updates it with the amount of assets we've withrdawn.
            d.assets = isActive ? 0 : d.assets - withdrawnAssets;

            // Take the shares we need from this deposit and add them to our total.
            d.shares -= withdrawnShares;
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

        // Only withdraw from strategy if holding pool does not contain enough funds.
        _allocateAssets(assets);

        // Transfer assets to receiver from the cellar's holding pool.
        ERC20(asset).safeTransfer(receiver, assets);

        emit Withdraw(receiver, owner, address(asset), assets, shares);

        // Returns the amount of shares redeemed and amount of assets withdrawn. The amount of
        // assets withdrawn may differ from the amount of assets specified when calling the function
        // if the user has less assets then they tried withdrawing.
        return (shares, assets);
    }

    // ==================================== ACCOUNTING OPERATIONS ====================================

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
     * @notice Total amount of active asset entered into a strategy.
     */
    function activeAssets() public view returns (uint256) {
        // The aTokens' value is pegged to the value of the corresponding asset at a 1:1 ratio. We
        // can find the amount of assets active in a strategy simply by taking balance of aTokens
        // cellar holds.
        return ERC20(assetAToken).balanceOf(address(this));
    }

    function _activeAssets() internal view returns (uint256) {
        uint256 assets = ERC20(assetAToken).balanceOf(address(this));
        return assets.changeDecimals(assetDecimals, decimals);
    }

    /**
     * @notice Total amount of inactive asset waiting in a holding pool to be entered into a strategy.
     */
    function inactiveAssets() public view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function _inactiveAssets() internal view returns (uint256) {
        uint256 assets = ERC20(asset).balanceOf(address(this));
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
     * @notice The amount of shares that the cellar would exchange for the amount of assets provided.
     * @dev Must be careful not be specify an offset greater than the cellar's total assets otherwise it
     *      will revert.
     * @param assets amount of assets to convert
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        assets = assets.changeDecimals(assetDecimals, decimals);
        return _convertToShares(assets);
    }

    function _convertToShares(uint256 assets) internal view returns (uint256) {
        return totalSupply == 0 ? assets : assets.mulDivDown(totalSupply, _totalAssets());
    }

    /**
     * @notice The amount of assets that the cellar would exchange for the amount of shares provided.
     * @param shares amount of shares to convert
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
     */
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    /**
    * @notice Simulate the effects of minting shares at the current block, given current on-chain
    *         conditions.
     * @param shares amount of shares to mint
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
     */
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    /**
    * @notice Simulate the effects of redeeming shares at the current block, given current on-chain
    *         conditions. Assumes the shares being redeemed are all active.
     * @param shares amount of shareas to withdraw
     */
    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    // ============================ DEPOSIT/WITHDRAWAL LIMIT OPERATIONS ============================

    /**
     * @notice Total number of assets that can be deposited by owner into the cellar.
     * @dev Until after security audits, limits deposits to $50k per wallet.
     * @param owner address of account that would receive the shares
     */
    function maxDeposit(address owner) public view returns (uint256) {
        if (isShutdown || isPaused) return 0;

        if (maxLiquidity == type(uint256).max) return type(uint256).max;

        uint256 depositLimit = 50_000 * 10**assetDecimals;
        uint256 assets = previewRedeem(balanceOf[owner]);

        return depositLimit > assets ? depositLimit - assets : 0;
    }

    /**
     * @notice Total number of shares that can be minted for owner from the cellar.
     * @dev Until after security audits, limits mints to $50k of shares per wallet.
     * @param owner address of account that would receive the shares
     */
    function maxMint(address owner) public view returns (uint256) {
        if (isShutdown || isPaused) return 0;

        if (maxLiquidity == type(uint256).max) return type(uint256).max;

        uint256 mintLimit = previewDeposit(50_000 * 10**assetDecimals);
        uint256 shares = balanceOf[owner];

        return mintLimit > shares ? mintLimit - shares : 0;
    }

    /**
     * @notice Total number of assets that can be withdrawn from the cellar.
     * @param owner address of account that would holds the shares
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
            // assets, otherwise just withdrawn the orignal amount of assets that were deposited.
            assets += d.timeDeposited < lastTimeEnteredStrategy ?
                d.shares.mulWadDown(exchangeRate) :
                d.assets;
        }

        // Return the maximum amount of assets that can be withdrawn in the assets original units.
        return assets.changeDecimals(decimals, assetDecimals);
    }

    /**
     * @notice Total number of shares that can be redeemed from the cellar.
     * @param owner address of account that would holds the shares
     */
    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf[owner];
    }

    // ======================================= FEE OPERATIONS =======================================

    /**
     * @notice Take platform fees and performance fees off of cellar's active assets.
     */
    function accrueFees() external {
        // When the contract is shutdown, there should be no reason to accrue fees because there
        // will be no active assets to accrue fees on.
        if (isShutdown) revert ContractShutdown();

        // Platform fees taken each accrual = activeAssets * (elapsedTime * (2% / SECS_PER_YEAR)).
        uint256 elapsedTime = block.timestamp - feesData.lastTimeAccruedPlatformFees;
        uint256 platformFeeInAssets =
            (_activeAssets() * elapsedTime * PLATFORM_FEE) / DENOMINATOR / 365 days;

        // The cellar accrues fees as shares instead of assets.
        uint256 platformFees = _convertToShares(platformFeeInAssets);
        _mint(address(this), platformFees);

        // Update the tracker for total platform fees accrued that are still waiting to be
        // transferred.
        feesData.accruedPlatformFees += platformFees;

        emit AccruedPlatformFees(platformFees);

        // Begin accrual of performance fees.
        _accruePerformanceFees(true);
    }

    /**
     * @notice Accrue performance fees.
     */
    function _accruePerformanceFees(bool updateFeeData) internal {
        // Retrieve the current normalized income per unit of asset for the current stategy on Aave.
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(address(asset));

        // If this is the first time the cellar is accuring performance fees, it will skip the part
        // were we take fees and should just update the fee data to set a baseline for assessing the
        // current strategy's performance.
        if (feesData.lastActiveAssets != 0) {
            // An index value greater than 1e27 indicates positive performance for the strategy's
            // lending position, while a value less than that indicates negative performance.
            uint256 performanceIndex = normalizedIncome.mulDivDown(1e27, feesData.lastNormalizedIncome);

            // This is the amount the cellar's active assets have grown to solely from performance
            // on Aave since the last time performance fees were accrued.  It does not include
            // changes from deposits and withdraws.
            uint256 updatedActiveAssets = feesData.lastActiveAssets.mulDivUp(performanceIndex, 1e27);

            // Determines whether performance has been positive or negative.
            if (performanceIndex >= 1e27) {
                // Fees taken each accrual = (updatedActiveAssets - lastActiveAssets) * 5%
                uint256 gain = updatedActiveAssets - feesData.lastActiveAssets;
                uint256 performanceFeeInAssets = gain.mulDivDown(PERFORMANCE_FEE, DENOMINATOR);

                // The cellar accrues fees as shares instead of assets.
                uint256 performanceFees = _convertToShares(performanceFeeInAssets);
                _mint(address(this), performanceFees);

                feesData.accruedPerformanceFees += performanceFees;

                emit AccruedPerformanceFees(performanceFees);
            } else {
                // This would only happen if the current stablecoin strategy on Aave performed
                // negatively.  This should rarely happen, if ever, for this particular cellar. But
                // in case it does, this mechanism will burn performance fees to help offset losses
                // in proportion to those minted for previous gains.

                uint256 loss = feesData.lastActiveAssets - updatedActiveAssets;
                uint256 insuranceInAssets = loss.mulDivDown(PERFORMANCE_FEE, DENOMINATOR);

                // Cannot burn more performance fees than the cellar has accrued.
                uint256 insurance = MathUtils.min(
                    _convertToShares(insuranceInAssets),
                    feesData.accruedPerformanceFees
                );

                _burn(address(this), insurance);

                feesData.accruedPerformanceFees -= insurance;

                emit BurntPerformanceFees(insurance);
            }
        }

        // There may be cases were we don't want to update fee data in this function, for example
        // when we accrue performance fees before rebalancing into a new strategy since the data
        // will be outdated after the rebalance to a new strategy.
        if (updateFeeData) {
            feesData.lastActiveAssets = _activeAssets();
            feesData.lastNormalizedIncome = normalizedIncome;
        }
    }

    /**
     * @notice Transfer accrued fees to Cosmos to distribute.
     */
    function transferFees() external onlyOwner {
        // Total up all the fees this cellar has accrued and determine how much they can be redeemed
        // for in assets.
        uint256 fees = feesData.accruedPerformanceFees + feesData.accruedPlatformFees;
        uint256 feeInAssets = previewRedeem(fees);

        // Redeem our fee shares for assets to transfer to Cosmos.
        _burn(address(this), fees);

        // Only withdraw assets from strategy if the holding pool does not contain enough funds.
        // Otherwise, all assets will come from the holding pool.
        _allocateAssets(feeInAssets);

        // Transfer assets to a fee distributor on Cosmos.
        ERC20(asset).approve(address(gravityBridge), feeInAssets);
        gravityBridge.sendToCosmos(address(asset), feesDistributor, feeInAssets);

        emit TransferFees(feesData.accruedPlatformFees, feesData.accruedPerformanceFees);

        // Reset the tracker for fees accrued that are still waiting to be transferred.
        feesData.accruedPlatformFees = 0;
        feesData.accruedPerformanceFees = 0;
    }

    // ========================================= ADMIN OPERATIONS =========================================

    /**
     * @notice Enters into the current Aave stablecoin strategy.
     */
    function enterStrategy() external onlyOwner {
        // When the contract is shutdown, it shouldn't be allowed to enter back into a strategy with the
        // assets it just withdrew from Aave.
        if (isShutdown) revert ContractShutdown();

        // Deposits all inactive assets in the holding pool into the current strategy.
        _depositToAave(address(asset), inactiveAssets());

        // The cellar will use this when determining which of a user's shares are active vs inactive.
        lastTimeEnteredStrategy = block.timestamp;
    }

    /**
     * @notice Rebalances current assets into a new asset strategy.
     * @param path path to swap from the current asset to new asset using Uniswap
     * @param amountOutMinimum minimum amount of assets returned after swap
     */
    function rebalance(address[] memory path, uint256 amountOutMinimum) external onlyOwner {
        // If the contract is shutdown, cellar shouldn't be able to rebalance assets it recently
        // pulled out back into a new strategy.
        if (isShutdown) revert ContractShutdown();

        if (path[0] != address(asset)) revert InvalidSwapPath(path);

        address newAsset = path[path.length - 1];

        // Doesn't make sense to rebalance into the same asset.
        if (newAsset == address(asset)) revert SameAsset(newAsset);

        // Accrue any final performance fees from the current strategy before rebalancing. Otherwise
        // those fees would be lost when we proceed to update fee data for the new strategy. Also
        // we don't want to update the fee data here because we will do that later on after we've
        // rebalanced into a new strategy.
        _accruePerformanceFees(false);

        // Pull all active assets entered into Aave back into the cellar so we can swap everything into
        // the new asset.
        _withdrawFromAave(address(asset), type(uint256).max);
        uint256 amountOut = _swap(path, inactiveAssets(), amountOutMinimum, true);

        // Store this later for the event we will emit.
        address oldAsset = address(asset);

        // Updates state for our new strategy and check to make sure Aave supports it before
        // rebalancing.
        _updateStategy(newAsset);

        // Rebalance our assets into a new strategy.
        _depositToAave(newAsset, amountOut);

        // Update fee data for next fee accrual with new strategy.
        feesData.lastActiveAssets = _activeAssets();
        feesData.lastNormalizedIncome = lendingPool.getReserveNormalizedIncome(address(asset));

        emit Rebalance(oldAsset, newAsset, amountOut);
    }

    /**
     * @notice Reinvest rewards back into cellar's current strategy.
     * @dev Must be called within 2 day unstake period 10 days after `claimAndUnstake` was run.
     * @param path path to swap from AAVE to the current asset on Sushiswap
     * @param minAssetsOut minimum amount of assets cellar should receive after swap
     */
    function reinvest(address[] memory path, uint256 minAssetsOut) public onlyOwner {
        if (path[0] != address(AAVE) || path[path.length - 1] != address(asset))
            revert InvalidSwapPath(path);

        // Redeems the cellar's stkAAVe rewards for AAVE.
        stkAAVE.redeem(address(this), type(uint256).max);

        // Due to the lack of liquidity for AAVE on Uniswap, we use Sushiswap instead here.
        uint256 amountOut = _swap(path, AAVE.balanceOf(address(this)), minAssetsOut, false);

        // In the case of a shutdown, we just may want to redeem any leftover rewards for
        // shareholders to claim but without entering them back into a strategy.
        if (!isShutdown) {
            // Take performance fee off of rewards.
            uint256 performanceFeeInAssets = amountOut.mulDivDown(PERFORMANCE_FEE, DENOMINATOR);
            uint256 performanceFees = convertToShares(performanceFeeInAssets);

            // Mint performance fees to cellar as shares.
            _mint(address(this), performanceFees);

            feesData.accruedPerformanceFees += performanceFees;

            // Reinvest rewards back into the current strategy.
            _depositToAave(address(asset), amountOut);
        }
    }

    /**
     * @notice Claim rewards from Aave and begin cooldown period to unstake them.
     * @return claimed amount of rewards claimed from Aave
     */
    function claimAndUnstake() public onlyOwner returns (uint256 claimed) {
        // Necessary to do as `claimRewards` accepts a dynamic array as first param.
        address[] memory aToken = new address[](1);
        aToken[0] = address(assetAToken);

        // Claim all stkAAVE rewards.
        claimed = incentivesController.claimRewards(aToken, type(uint256).max, address(this));

        // Begin the cooldown period for unstaking stkAAVE to later redeem for AAVE.
        stkAAVE.cooldown();
    }

    /**
     * @notice Sweep tokens sent here that are not managed by the cellar.
     * @dev This may be used in case the wrong tokens are accidently sent to this contract.
     * @param token address of token to transfer out of this cellar
     */
    function sweep(address token) external onlyOwner {
        // Prevent sweeping of assets managed by the cellar and shares minted to the cellar as fees.
        if (token == address(asset) || token == address(assetAToken) || token == address(this))
            revert ProtectedAsset(token);

        // Transfer out tokens in this cellar that shouldn't be here.
        uint256 amount = ERC20(token).balanceOf(address(this));
        ERC20(token).safeTransfer(msg.sender, amount);

        emit Sweep(token, amount);
    }

    /**
     * @notice Removes initial liquidity restriction.
     */
    function removeLiquidityRestriction() external onlyOwner {
        maxLiquidity = type(uint256).max;

        emit LiquidityRestrictionRemoved();
    }

    /**
     * @notice Pause the contract to prevent deposits.
     * @param _isPaused whether the contract should be paused or unpaused
     */
    function setPause(bool _isPaused) external onlyOwner {
        if (isShutdown) revert ContractShutdown();

        isPaused = _isPaused;

        emit Pause(_isPaused);
    }

    /**
     * @notice Stops the contract - this is irreversible. Should only be used in an emergency,
     *         for example an irreversible accounting bug or an exploit.
     */
    function shutdown() external onlyOwner {
        if (isShutdown) revert AlreadyShutdown();

        isShutdown = true;

        // Ensure contract is not paused.
        isPaused = false;

        // Withdraw everything from Aave. The check is necessary to prevent a revert happening if we
        // try to withdraw from Aave without any assets entered into a strategy which would prevent
        // the contract from being able to be shutdown in this case.
        if (activeAssets() > 0) _withdrawFromAave(address(asset), type(uint256).max);

        emit Shutdown();
    }

    // ============================================ HELPERS ============================================

    /**
     * @notice Update state variables related to the current strategy.
     * @param newAsset address of the new asset being managed by the cellar
     */
    function _updateStategy(address newAsset) internal {
        // Retrieve the aToken that will represent the cellar's new strategy on Aave.
        (, , , , , , , address aTokenAddress, , , , ) = lendingPool.getReserveData(newAsset);

        // If the address is not null, it is supported by Aave.
        if (aTokenAddress == address(0)) revert TokenIsNotSupportedByAave(newAsset);

        // Update state related to the current strategy.
        asset = ERC20(newAsset);
        assetDecimals = ERC20(newAsset).decimals();
        assetAToken = ERC20(aTokenAddress);

        // Update the decimals max liquidity is denoted in if restrictions are still in place.
        if (maxLiquidity != type(uint256).max) maxLiquidity = 5_000_000 * 10**assetDecimals;
    }

    /**
     * @notice Ensures there is a specific amount of assets in the contract available to be transferred.
     * @dev Only withdraws from strategy if needed.
     * @param assets The amount of assets to allocate
     */
    function _allocateAssets(uint256 assets) internal {
        uint256 holdingPoolAssets = inactiveAssets();

        if (assets > holdingPoolAssets) {
            _withdrawFromAave(address(asset), assets - holdingPoolAssets);
        }
    }


    /**
     * @notice Deposits cellar holdings into an Aave lending pool.
     * @param token the address of the token
     * @param amount the amount of tokens to deposit
     */
    function _depositToAave(address token, uint256 amount) internal {
        ERC20(token).safeApprove(address(lendingPool), amount);

        // Deposit tokens to Aave protocol.
        lendingPool.deposit(token, amount, address(this), 0);

        emit DepositToAave(token, amount);
    }

    /**
     * @notice Withdraws assets from Aave.
     * @param token the address of the token
     * @param amount the amount of tokens to withdraw
     * @return withdrawnAmount the withdrawn amount from Aave
     */
    function _withdrawFromAave(address token, uint256 amount) internal returns (uint256 withdrawnAmount) {
        // Withdraw tokens from Aave protocol
        withdrawnAmount = lendingPool.withdraw(token, amount, address(this));

        emit WithdrawFromAave(token, withdrawnAmount);
    }

    /**
     * @notice Swaps assets using Uniswap V3 or Sushiswap V2.
     * @param path swap path (ie. token addresses) from one asset to another
     * @param amountIn amount of asstes to be swapped
     * @param amountOutMinimum minimum amount of assets returned
     * @param useUniswap whether to use Uniswap or Sushiswap
     * @return amountOut amount of assets received after swap
     */
    function _swap(
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bool useUniswap
    ) internal returns (uint256 amountOut) {
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        // Specifies that the cellar will use the 0.30% fee pools when performing swaps on Uniswap.
        uint24 SWAP_FEE = 3000;

        // Approve the router to spend first token in path.
        ERC20(tokenIn).safeApprove(address(uniswapRouter), amountIn);

        // Determine whether to use a single swap or multihop swap.
        if (path.length > 2){
            // Multihop:

            if (useUniswap) {
                bytes memory encodePackedPath = abi.encodePacked(tokenIn);
                for (uint256 i = 1; i < path.length; i++) {
                    encodePackedPath = abi.encodePacked(
                        encodePackedPath,
                        SWAP_FEE,
                        path[i]
                    );
                }

                // Multiple pool swaps are encoded through bytes called a `path`. A path is a
                // sequence of token addresses and poolFees that define the pools used in the swaps.
                // The format for pool encoding is (tokenIn, fee, tokenOut/tokenIn, fee, tokenOut)
                // where tokenIn/tokenOut parameter is the shared token across the pools.
                ISwapRouter.ExactInputParams memory params = ISwapRouter
                    .ExactInputParams({
                        path: encodePackedPath,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: amountIn,
                        amountOutMinimum: amountOutMinimum
                    });

                // Executes a multihop swap on Uniswap.
                amountOut = uniswapRouter.exactInput(params);
            } else {
                uint256[] memory amounts = sushiswapRouter.swapExactTokensForTokens(
                    amountIn,
                    amountOutMinimum,
                    path,
                    address(this),
                    block.timestamp + 60
                );

                // Executes a multihop swap on Sushiswap.
                amountOut = amounts[amounts.length - 1];
            }
        } else {
            // Single:

            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                .ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: SWAP_FEE,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: amountOutMinimum,
                    sqrtPriceLimitX96: 0
                });

            // Executes a single swap on Uniswap.
            amountOut = uniswapRouter.exactInputSingle(params);
        }

        emit Swap(tokenIn, amountIn, tokenOut, amountOut);
    }

    // ==================================== SHARE TRANSFER OPERATIONS ====================================

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

        // Retrieve the deposits from both sender and receiver then begin looping through the
        // sender's deposits, generally from oldest to newest deposits. This is not always the case
        // though if shares have been transferred to the sender, as they will be added to the end of
        // the sender's deposits regardless of time deposited.
        UserDeposit[] storage depositsFrom = userDeposits[from];
        UserDeposit[] storage depositsTo = userDeposits[to];

        // Tracks the amount of shares left to transfer; updated at the end of each loop.
        uint256 leftToTransfer = amount;

        for (uint256 i = currentDepositIndex[from]; i < depositsFrom.length; i++) {
            UserDeposit storage dFrom = depositsFrom[i];

            // If we only want to transfer active shares, skips this deposit if it is inactive.
            bool isActive = dFrom.timeDeposited < lastTimeEnteredStrategy;
            if (onlyActive && !isActive) continue;

            // Track the amount of assets and shares transfered from the sender's deposit.
            uint256 transferredShares = MathUtils.min(leftToTransfer, dFrom.shares);
            uint256 transferredAssets = dFrom.assets.mulDivUp(transferredShares, dFrom.shares);

            // Update this deposit with the amount of assets taken.
            dFrom.shares -= transferredShares;
            dFrom.assets -= transferredAssets;

            // Add a deposit to the end of receiver's list of deposits.
            depositsTo.push(UserDeposit({
                assets: isActive ? 0 : transferredAssets, // Saves gas on storage if active.
                shares: transferredShares,
                timeDeposited: isActive ? 0 : dFrom.timeDeposited // Same here.
            }));

            // Update the counter of assets left to transfer.
            leftToTransfer -= transferredShares;

            // Finish if this is the last deposit or there is nothing left to transfer.
            if (i == depositsFrom.length - 1 || leftToTransfer == 0) {
                // Store the index for the next non-zero deposit to save gas on looping.
                currentDepositIndex[from] = dFrom.shares != 0 ? i : i+1;
                break;
            }
        }

        // Determine the total amount of shares transferred.
        amount -= leftToTransfer;

        // Will revert here if sender is trying to transfer more shares then they have, so no need
        // for an explict check.
        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /// @dev For compatibility with ERC20 standard.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        // Defaults to not caring whether the shares transferred are active or not.
        return transferFrom(from, to, amount, false);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        return transferFrom(msg.sender, to, amount, false);
    }

}
