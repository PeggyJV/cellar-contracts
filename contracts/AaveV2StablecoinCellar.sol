// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.11;

import "./interfaces/IAaveV2StablecoinCellar.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/ILendingPool.sol";
import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./utils/MathUtils.sol";
import "./interfaces/IAaveIncentivesController.sol";
import "./interfaces/IStakedTokenV2.sol";
import "./interfaces/ISushiSwapRouter.sol";
import "./interfaces/IGravity.sol";

/**
 * @title Sommelier AaveV2 Stablecoin Cellar contract
 * @notice AaveV2StablecoinCellar contract for Sommelier Network
 * @author Sommelier Finance
 */
contract AaveV2StablecoinCellar is IAaveV2StablecoinCellar, ERC20, ReentrancyGuard, Ownable {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    /**
     * @notice Mapping from a token to a boolean representing whether it is approved for deposit.
     * @dev Being approved for deposit does not mean it is ultimately received by the cellar, as all input
     *      tokens are swapped to the current lending token if not already.
     */
    mapping(address => bool) public inputTokens;

    /**
     * @notice The token that makes up the cellar's holding pool.
     * @dev The cellar denotes its inactive assets in this token. While it waits in the holding pool to be
     *      entered into a strategy, it is used to pay for withdraws from those redeeming their shares.
     */
    address public currentLendingToken;

    /**
     * @notice The decimals of precision used by the current lending token.
     * @dev Some stablecoins (eg. USDC and USDT) don't use the standard 18 decimals of precision of most
     *      ERC20s. This is used for converting between decimals for different operations.
     */
    uint8 public assetDecimals;

    /**
     * @notice The token returned by Aave representing the cellar's active assets earning yield.
     */
    address public currentAToken;

    /**
     * @notice Mapping from a user's address to all their deposits and balances.
     * @dev Used in determining which of a user's shares are active (entered into a strategy earning yield
     *      vs inactve (waiting to be entered into a strategy and not earning yield).
     */
    mapping(address => UserDeposit[]) public userDeposits;

    /**
     * @notice Mapping from a user's address to the index of the first non-zero deposit in userDeposits.
     * @dev Saves gas when looping through all a user's deposits.
     */
    mapping(address => uint256) public currentDepositIndex;

    /**
     * @notice Last time all inactive assets were entered into a strategy and made active.
     */
    uint256 public lastTimeEnteredStrategy;

    /**
     * @notice Limits deposits per wallet to $50k until after security audits. A value of 0 means the
     *         restriction has been lifted.
     */
    uint256 public maxDeposit;

    /**
     * @notice Limits the total assets that can be managed by the cellar to $5m until after security
     *         audits. A value of 0 means the restriction has been lifted.
     */
    uint256 public maxLiquidity;

    /**
     * @notice The value we divide fees by to get a percentage. Represents the maximum, or 100%.
     */
    uint256 public constant DENOMINATOR = 10_000;

    /**
     * @notice The percentage of platform fees (1%) taken off of active assets over a year.
     */
    uint256 public constant PLATFORM_FEE = 100;

    /**
     * @notice The percentage of performance fees (5%) taken off of cellar gains.
     */
    uint256 public constant PERFORMANCE_FEE = 500;

    /**
     * @notice Struct where fee data gets updated and stored.
     * @dev This is stored in a struct purely to avoid stack too deep errors represents everything about a
     *      given validator set.
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

    // ====================================== INITIALIZATION =====================================

    // Uniswap Router V3 contract
    ISwapRouter public immutable uniswapRouter; // 0xE592427A0AEce92De3Edee1F18E0157C05861564
    // SushiSwap Router V2 contract
    ISushiSwapRouter public immutable sushiSwapRouter; // 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
    // Aave Lending Pool V2 contract
    ILendingPool public immutable lendingPool; // 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9
    // Aave Incentives Controller V2 contract
    IAaveIncentivesController public immutable incentivesController; // 0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5
    // Cosmos Gravity Bridge contract
    Gravity public immutable gravityBridge; // 0x69592e6f9d21989a043646fE8225da2600e5A0f7
    // Cosmos address of fee distributor
    bytes32 public feesDistributor; // TBD
    IStakedTokenV2 public immutable stkAAVE; // 0x4da27a545c0c5B758a6BA100e3a049001de870f5

    address public immutable AAVE; // 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9
    address public immutable USDC; // 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48

    /**
     * @dev The owner of this cellar should be
     * @param _uniswapRouter Uniswap V3 swap router address
     * @param _lendingPool Aave V2 lending pool address
     * @param _incentivesController _incentivesController
     * @param _gravityBridge Cosmos Gravity Bridge address
     * @param _stkAAVE stkAAVE address
     * @param _AAVE AAVE address
     * @param _USDC USDC address
     */
    constructor(
        ISwapRouter _uniswapRouter,
        ISushiSwapRouter _sushiSwapRouter,
        ILendingPool _lendingPool,
        IAaveIncentivesController _incentivesController,
        Gravity _gravityBridge,
        IStakedTokenV2 _stkAAVE,
        address _AAVE,
        address _USDC
    ) ERC20("Sommelier Aave V2 Stablecoin Cellar LP Token", "aave2CLR-S", 18) Ownable() {
        uniswapRouter =  _uniswapRouter;
        sushiSwapRouter = _sushiSwapRouter;
        lendingPool = _lendingPool;
        incentivesController = _incentivesController;
        gravityBridge = _gravityBridge;
        stkAAVE = _stkAAVE;
        AAVE = _AAVE;
        USDC = _USDC;

        // Initialize current lending token to USDC and approve it for deposits.
        _updateLendingPosition(_USDC);
        setInputToken(_USDC, true);

        // Initialize max deposits to $50k and max liquidity to $5m.
        maxDeposit = 50_000 * 10**assetDecimals;
        maxLiquidity = 5_000_000 * 10**assetDecimals;

        // Initialize starting point for platform fee accrual to time when cellar was created. Otherwise
        // it would incorrectly calculate how much platform fees to take when accrueFees is called for the
        // first time.
        feesData.lastTimeAccruedPlatformFees = block.timestamp;
    }

    // ======================================= CORE FUNCTIONS =======================================

    /**
     * @notice Deposit assets into the cellar.
     * @param assets amount of assets to deposit
     * @param receiver address that should receive shares
     * @param path path to swap from the input token to current lending token on Uniswap
     * @param minAssetsOut minimum amount of assets cellar should receive after swap (if applicable)
     * @return shares amount of shares minted to receiver
     */
    function deposit(
        uint256 assets,
        address receiver,
        address[] memory path,
        uint256 minAssetsOut
    ) public nonReentrant returns (uint256 shares) {
        // In case of an emergency or contract vulernability, we don't want users to be able to deposit
        // more assets into a compromised contract.
        if (isPaused) revert ContractPaused();
        if (isShutdown) revert ContractShutdown();

        address inputToken = path[0];

        // Will revert if depositing tokens that have not been approved.
        if (!inputTokens[inputToken]) revert UnapprovedToken(inputToken);

        // The token ultimately being swapped to should always be the current lending token.
        if (path[path.length - 1] != currentLendingToken) revert InvalidSwapPath(path);

        // In the case where a user tries to deposit more than their balance, the desired behavior is to
        // deposit what they have instead of reverting.
        uint256 balance = ERC20(inputToken).balanceOf(msg.sender);
        if (assets > balance) assets = balance;

        // Transfer their tokens into the cellar and swaps them into the current lending token if it isn't
        // already.
        ERC20(inputToken).safeTransferFrom(msg.sender, address(this), assets);
        if (inputToken != currentLendingToken) assets = _swap(path, assets, minAssetsOut, true);

        // If security restrictions still apply, ensure that the amount going into the cellar isn't more
        // than the caps specified.
        if (maxLiquidity != 0 && assets + totalAssets() > maxLiquidity)
            revert LiquidityRestricted(maxLiquidity);
        if (maxDeposit != 0 && convertToAssets(balanceOf[msg.sender]) + assets > maxDeposit)
            revert DepositRestricted(maxDeposit);

        // From here on out, we want to ensure the cellar is storing data with the standard 18 decimals of
        // precision.
        assets = assets.changeDecimals(assetDecimals, decimals);

        // Must calculate shares as if assets were not yet transfered in. Will only revert if no shares
        // were minted, which would only happen if no assets were deposited.
        if ((shares = _convertToShares(assets, assets)) == 0) revert ZeroAssets();

        // Mint user a token that represents their share of the cellar's assets.
        _mint(receiver, shares);

        // Store the user's deposit data. This will be used later on when the user wants to withdraw their
        // assets or transfer their shares.
        UserDeposit[] storage deposits = userDeposits[receiver];
        deposits.push(UserDeposit({
            assets: assets,
            shares: shares,
            timeDeposited: block.timestamp
        }));

        emit Deposit(
            msg.sender,
            receiver,
            currentLendingToken,
            assets.changeDecimals(decimals, assetDecimals),
            shares
        );
    }

    function deposit(uint256 assets) external returns (uint256) {
        address [] memory path = new address [](1);
        path[0] = currentLendingToken;

        // Defaults to the current lending token being the token that gets deposited and having the user
        // who deposited them receiving the shares.
        return deposit(assets, msg.sender, path, 0);
    }

    /// @dev For ERC4626 compatibility.
    function deposit(uint256 assets, address receiver) external returns (uint256) {
        address [] memory path = new address [](1);
        path[0] = currentLendingToken;

        // Defaults to the current lending token being the token that gets deposited but allows the
        // depositer to specify a different wallet that will receive the shares.
        return deposit(assets, receiver, path, 0);
    }

    /**
     * @notice Withdraw assets from the cellar.
     * @param assets amount of assets to withdraw
     * @param receiver address that should receive assets
     * @param owner address that should own the shares
     * @return shares amount of shares burned from owner
     */
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();
        if (balanceOf[owner] == 0) revert ZeroShares();

        // Ensures proceeding calculations are done with a standard 18 decimals of precision. Will change
        // back to the using the token's usual decimals of precision when transferring assets after all
        // calculations are done.
        assets = assets.changeDecimals(assetDecimals, decimals);

        // Tracks the amount of active shares we need to redeem to withdraw the amount of assets we want.
        uint256 withdrawnActiveShares;
        // Also the amount of inactive shares.
        uint256 withdrawnInactiveShares;
        // Inactive shares don't earn yield so we can't redeem them like we do active shares. If a user
        // tries to redeem inactive shares, they should get back what they orignally deposited. So this
        // keeps track of how many assets their withdrawn inactive shares can be redeemed for.
        uint256 withdrawnInactiveAssets;

        // Saves gas by avoiding calling `_convertToAssets` on active shares during each loop.
        uint256 exchangeRate = _convertToAssets(1e18);

        // Tracks the amount of assets left to withdraw.
        uint256 leftToWithdraw = assets;

        UserDeposit[] storage deposits = userDeposits[owner];
        for (uint256 i = currentDepositIndex[owner]; i < deposits.length; i++) {
            UserDeposit storage d = deposits[i];

            // Track the amount of assets and shares we will withdraw from this deposit.
            uint256 withdrawnAssets;
            uint256 withdrawnShares;

            // Check if deposit shares are active or inactive.
            if (d.timeDeposited < lastTimeEnteredStrategy) {
                // Active:

                // Since these shares are active, convert them to the amount of assets they're worth to see
                // the maximum amount of assets we can take from this deposit.
                uint256 dAssets = d.shares.mulDivDown(exchangeRate, 1e18);

                // Get the amount of assets we need from this deposit.
                withdrawnAssets = MathUtils.min(leftToWithdraw, dAssets);

                // Get the amount of shares we'd have to redeem to get the amount of assets we need.
                withdrawnShares = d.shares.mulDivUp(withdrawnAssets, dAssets);

                delete d.assets; // Don't need this anymore; delete for a gas refund.

                // Add the shares taken from this deposit to our total.
                withdrawnActiveShares += withdrawnShares;
            } else {
                // Inactive:

                // Get the amount of assets we need from this deposit.
                withdrawnAssets = MathUtils.min(leftToWithdraw, d.assets);

                // Get the amount of shares we'd have to redeem to get the amount of assets we need.
                withdrawnShares = d.shares.mulDivUp(withdrawnAssets, d.assets);

                // Add the shares taken from this deposit to our total.
                withdrawnInactiveShares += withdrawnShares;

                // Store the amount of assets these inactive shares were originally worth.
                withdrawnInactiveAssets += withdrawnAssets;

                // Update this deposit with the amount of assets we've taken.
                d.assets -= withdrawnAssets;
            }

            // Update this deposit with the amount of shares we've taken.
            d.shares -= withdrawnShares;

            // Update the counter of assets we have left to withdraw.
            leftToWithdraw -= withdrawnAssets;

            // If there are no more assets left to withdraw, we're done here. Otherwise continue. In the
            // case where the user tried to withdraw more assets than the owner has, the desired behavior
            // is to withdraw everything the owner can instead of reverting so we'd exhaust this loop and
            // empty all a user's deposits.
            if (i == deposits.length - 1 || leftToWithdraw == 0) {
                // Before we go, store the user's next non-zero deposit to save gas on future looping.
                currentDepositIndex[owner] = d.shares != 0 ? i : i+1;
                break;
            }
        }

        // Total up the shares we will be redeeming.
        shares = withdrawnActiveShares + withdrawnInactiveShares;

        // If the caller is not the owner of the shares, check to see if the owner has approved them to
        // spend their shares.
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Convert the active shares to their worth in assets.
        uint256 withdrawnActiveAssets = withdrawnActiveShares.mulDivDown(exchangeRate, 1e18);

        // Redeem the shares.
        _burn(owner, shares);

        uint256 toWithdaw = withdrawnActiveAssets + withdrawnInactiveAssets;

        // Convert decimals back to get ready for transfers.
        toWithdaw = toWithdaw.changeDecimals(decimals, assetDecimals);

        // Only withdraw from strategy if holding pool does not contain enough funds.
        _allocateAssets(toWithdaw);

        // Transfer assets to receiver from the cellar's holding pool.
        ERC20(currentLendingToken).safeTransfer(receiver, toWithdaw);

        emit Withdraw(
            receiver,
            owner,
            currentLendingToken,
            toWithdaw,
            shares
        );
    }

    function withdraw(uint256 assets) external returns (uint256 shares) {
        // Default to the receiver and owner being the caller.
        return withdraw(assets, msg.sender, msg.sender);
    }

    // ======================================== ADMIN FUNCTIONS ========================================

    /**
     * @notice Enters into the current Aave stablecoin strategy.
     */
    function enterStrategy() external onlyOwner {
        // When the contract is shutdown, it shouldn't be allowed to enter back into a strategy with the
        // assets it just withdrew from Aave.
        if (isShutdown) revert ContractShutdown();

        // Deposits all inactive assets in the holding pool into the current strategy.
        _depositToAave(currentLendingToken, inactiveAssets());

        // The cellar will use this when determining which of a user's shares are active vs inactive.
        lastTimeEnteredStrategy = block.timestamp;
    }

    /**
     * @notice Claim rewards from Aave and begin cooldown period to unstake them.
     * @return claimed amount of rewards claimed from Aave
     */
    function claimAndUnstake() public onlyOwner returns (uint256 claimed) {
        // Necessary to do as claimRewards accepts a dynamic array as first param.
        address[] memory aToken = new address[](1);
        aToken[0] = currentAToken;

        // Claim all stkAAVE rewards.
        claimed = incentivesController.claimRewards(aToken, type(uint256).max, address(this));

        // Begin the cooldown period for unstaking stkAAVE to later redeem for AAVE.
        stkAAVE.cooldown();
    }

    /**
     * @notice Reinvest rewards back into cellar's current strategy.
     * @dev Must be called in the 2 day unstake period started 10 days after claimAndUnstake was run.
     * @param path path to swap from AAVE to the current lending token on Sushiswap
     * @param minAssetsOut minimum amount of assets cellar should receive after swap
     */
    function reinvest(address[] memory path, uint256 minAssetsOut) public onlyOwner {
        if (path[0] != AAVE || path[path.length - 1] != currentLendingToken) revert InvalidSwapPath(path);

        // Redeems the cellar's stkAAVe rewards for AAVE.
        stkAAVE.redeem(address(this), type(uint256).max);

        // Due to the lack of liquidity for AAVE on Uniswap, we use Sushiswap instead here.
        uint256 amountOut = _swap(path, ERC20(AAVE).balanceOf(address(this)), minAssetsOut, false);

        // In the case of a shutdown, we just may want to redeem any leftover rewards for shareholders to
        // claim but without entering them back into a strategy.
        if (!isShutdown) {
            // Take performance fee off of rewards.
            uint256 performanceFeeInAssets = amountOut.mulDivDown(PERFORMANCE_FEE, DENOMINATOR);
            uint256 performanceFees = convertToShares(performanceFeeInAssets);

            // Mint performance fees to cellar as shares.
            _mint(address(this), performanceFees);

            feesData.accruedPerformanceFees += performanceFees;

            // Reinvest rewards back into the current strategy.
            _depositToAave(currentLendingToken, amountOut);
        }
    }

    /**
     * @notice Rebalances the current lending token into a new one, effectively changing strategies.
     * @param path path to swap from the current lending token to new lending token on Uniswap
     * @param minNewLendingTokenAmount minimum amount of tokens received by cellar after swap
     */
    function rebalance(address[] memory path, uint256 minNewLendingTokenAmount) external onlyOwner {
        // If the contract is shutdown, cellar shouldn't be able to rebalance assets it recently pulled out
        // back into a new strategy.
        if (isShutdown) revert ContractShutdown();

        if (path[0] != currentLendingToken) revert InvalidSwapPath(path);

        address newLendingToken = path[path.length - 1];

        // It would be awkward if the new lending token wasn't approved because users wouldn't be able to
        // directly deposit it into the cellar.
        if (!inputTokens[newLendingToken]) revert UnapprovedToken(newLendingToken);

        // Without this check there could be an attack were
        if (newLendingToken == currentLendingToken) revert SameLendingToken(currentLendingToken);

        // Accrue any final performance fees from the current strategy before rebalancing. Otherwise
        // those fees would be lost when we proceed to update fee data for the new lending position. Also
        // we don't want to update the fee data here because we will do that later on after we've
        // rebalanced into a new strategy.
        _accruePerformanceFees(false);

        // Pull all active assets entered into Aave back into the cellar so we can swap everything into
        // the new lending token.
        _redeemFromAave(currentLendingToken, type(uint256).max);
        uint256 newLendingTokenAmount = _swap(path, inactiveAssets(), minNewLendingTokenAmount, true);

        // Store this later for the event we will emit.
        address oldLendingToken = currentLendingToken;

        // Updates state for our new lending position and check to make sure Aave supports it before
        // rebalancing.
        _updateLendingPosition(newLendingToken);

        // Rebalance our assets into a new strategy.
        _depositToAave(newLendingToken, newLendingTokenAmount);

        // Update fee data for next fee accrual with new lending position.
        feesData.lastActiveAssets = _activeAssets();
        feesData.lastNormalizedIncome = lendingPool.getReserveNormalizedIncome(currentLendingToken);

        emit Rebalance(oldLendingToken, newLendingToken, newLendingTokenAmount);
    }

    /**
     * @notice Set approval for a token to be deposited into the cellar.
     * @param token the address of the supported token
     */
    function setInputToken(address token, bool isApproved) public onlyOwner {
        _validateTokenOnAave(token); // Only allow input tokens supported by Aave.

        inputTokens[token] = isApproved;

        emit SetInputToken(token, isApproved);
    }

    /**
     * @notice Sweep tokens sent here that are not managed by the cellar.
     * @dev This may be used in case the wrong tokens are accidently sent to this contract.
     * @param token address of token to transfer out of this cellar
     */
    function sweep(address token) external onlyOwner {
        // Prevent sweeping of tokens managed by the cellar and shares minted to the cellar as fees.
        if (token == currentLendingToken || token == currentAToken || token == address(this))
            revert ProtectedAsset(token);

        // Transfer out tokens in this cellar that shouldn't be here.
        uint256 amount = ERC20(token).balanceOf(address(this));
        ERC20(token).safeTransfer(msg.sender, amount);

        emit Sweep(token, amount);
    }

    /**
     * @notice Take platform fees and performance fees off of cellar's active assets.
     */
    function accrueFees() external {
        // When the contract is shutdown, there should be no reason to accrue fees because there will be no
        // active assets to accrue fees on.
        if (isShutdown) revert ContractShutdown();

        // Platform fees taken each accrual = activeAssets * (elapsedTime * (2% / SECS_PER_YEAR)).
        uint256 elapsedTime = block.timestamp - feesData.lastTimeAccruedPlatformFees;
        uint256 platformFeeInAssets =
            (_activeAssets() * elapsedTime * PLATFORM_FEE) / DENOMINATOR / 365 days;

        // The cellar accrues fees as shares instead of assets.
        uint256 platformFees = _convertToShares(platformFeeInAssets, 0);
        _mint(address(this), platformFees);

        // Update the tracker for total platform fees accrued that are still waiting to be transferred.
        feesData.accruedPlatformFees += platformFees;

        emit AccruedPlatformFees(platformFees);

        // Begin accrual of performance fees.
        _accruePerformanceFees(true);
    }

    /**
     * @notice Accrue performance fees.
     */
    function _accruePerformanceFees(bool updateFeeData) internal {
        // Retrieve the current normalized income per unit of asset for the current lending position on Aave.
        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(currentLendingToken);

        // If this is the first time the cellar is accuring performance fees, it will skip the part were we
        // take fees and should just update the fee data to set a baseline for assessing the current
        // strategy's performance.
        if (feesData.lastActiveAssets != 0) {
            // An index value greater than 1e27 indicates positive performance for the strategy's lending
            // position, while a value less than that indicates negative performance.
            uint256 performanceIndex = normalizedIncome.mulDivDown(1e27, feesData.lastNormalizedIncome);

            // This is the amount the cellar's active assets have grown to solely from performance on Aave
            // since the last time performance fees were accrued.  It does not include changes from
            // deposits and withdraws.
            uint256 updatedActiveAssets = feesData.lastActiveAssets.mulDivUp(performanceIndex, 1e27);

            // Determines whether performance has been positive or negative.
            if (performanceIndex >= 1e27) {
                // Fees taken each accrual = (updatedActiveAssets - lastActiveAssets) * 5%
                uint256 gain = updatedActiveAssets - feesData.lastActiveAssets;
                uint256 performanceFeeInAssets = gain.mulDivDown(PERFORMANCE_FEE, DENOMINATOR);

                // The cellar accrues fees as shares instead of assets.
                uint256 performanceFees = _convertToShares(performanceFeeInAssets, 0);
                _mint(address(this), performanceFees);

                feesData.accruedPerformanceFees += performanceFees;

                emit AccruedPerformanceFees(performanceFees);
            } else {
                // This would only happen if the current stablecoin strategy on Aave performed negatively.
                // This should rarely happen, if ever, for this particular cellar. But in case it does,
                // this mechanism will burn performance fees to help offset losses in proportion to those
                // minted for previous gains.

                uint256 loss = feesData.lastActiveAssets - updatedActiveAssets;
                uint256 insuranceInAssets = loss.mulDivDown(PERFORMANCE_FEE, DENOMINATOR);

                // Cannot burn more performance fees than the cellar has accrued.
                uint256 insurance = MathUtils.min(
                    _convertToShares(insuranceInAssets, 0),
                    feesData.accruedPerformanceFees
                );

                _burn(address(this), insurance);

                feesData.accruedPerformanceFees -= insurance;

                emit BurntPerformanceFees(insurance);
            }
        }

        // There may be cases were we don't want to update fee data in this function, for example when we
        // accrue performance fees before rebalancing into a new strategy since the data will be outdated
        // after the rebalance to a new lending position.
        if (updateFeeData) {
            feesData.lastActiveAssets = _activeAssets();
            feesData.lastNormalizedIncome = normalizedIncome;
        }

    }

    /**
     * @notice Transfer accrued fees to Cosmos to distribute.
     */
    function transferFees() external onlyOwner {
        // Total up all the fees this cellar has accrued and see how much they can be redeemed for in assets.
        uint256 fees = feesData.accruedPerformanceFees + feesData.accruedPlatformFees;
        uint256 feeInAssets = convertToAssets(fees);

        // Redeem our fee shares for assets to transfer to Cosmos.
        _burn(address(this), fees);

        // Only withdraw assets from strategy if the holding pool does not contain enough funds. Otherwise,
        // all assets will come from the holding pool.
        _allocateAssets(feeInAssets);

        // Transfer assets to a fee distributor on Cosmos.
        ERC20(currentLendingToken).approve(address(gravityBridge), feeInAssets);
        gravityBridge.sendToCosmos(currentLendingToken, feesDistributor, feeInAssets);

        emit TransferFees(feesData.accruedPlatformFees, feesData.accruedPerformanceFees);

        // Reset the tracker for fees accrued that are still waiting to be transferred.
        feesData.accruedPlatformFees = 0;
        feesData.accruedPerformanceFees = 0;
    }

    /**
     * @notice Removes initial liquidity restriction.
     */
    function removeLiquidityRestriction() external onlyOwner {
        delete maxDeposit;
        delete maxLiquidity;

        emit LiquidityRestrictionRemoved();
    }

    /**
     * @notice Pause the contract to prevent deposits.
     * @param _isPaused whether the contract should be paused or unpaused
     */
    function setPause(bool _isPaused) external onlyOwner {
        if (isShutdown) revert ContractShutdown();

        isPaused = _isPaused;

        emit Pause(msg.sender, _isPaused);
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

        // Withdraw everything from Aave. The check is necessary to prevent a revert happening if we try to
        // withdraw from Aave without any assets entered into a strategy which would prevent the contract
        // from being able to be shutdown in this case.
        if (activeAssets() > 0) _redeemFromAave(currentLendingToken, type(uint256).max);

        emit Shutdown(msg.sender);
    }

    // ======================================= STATE INFORMATION =======================================
    /**
     * @dev The internal functions always use 18 decimals of precision while the public functions use as
     *      many decimals as the current lending token (aka they don't change the decimals). This is
     *      because we want the user deposit data the cellar stores to be usable across different tokens,
     *      even if they used different decimals. This means the cellar will always perform calculations
     *      and store data with a standard of 18 decimals of precision but will change the decimals back
     *      when it transfers assets outside the contract or returns data through public view functions.
     */

    /**
     * @notice Total amount of active asset entered into a strategy.
     */
    function activeAssets() public view returns (uint256) {
        // The aTokens' value is pegged to the value of the corresponding deposited
        // asset at a 1:1 ratio, so we can find the amount of assets active in a
        // strategy simply by taking balance of aTokens cellar holds.
        return ERC20(currentAToken).balanceOf(address(this));
    }

    function _activeAssets() internal view returns (uint256) {
        uint256 assets = ERC20(currentAToken).balanceOf(address(this));
        return assets.changeDecimals(assetDecimals, decimals);
    }

    /**
     * @notice Total amount of inactive asset waiting in a holding pool to be entered into a strategy.
     */
    function inactiveAssets() public view returns (uint256) {
        return ERC20(currentLendingToken).balanceOf(address(this));
    }

    function _inactiveAssets() internal view returns (uint256) {
        uint256 assets = ERC20(currentLendingToken).balanceOf(address(this));
        return assets.changeDecimals(assetDecimals, decimals);
    }

    /**
     * @notice Total amount of the underlying asset that is managed by cellar.
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
     * @param offset amount to negatively offset total assets during calculation
     */
    function _convertToShares(uint256 assets, uint256 offset) internal view returns (uint256) {
        return totalSupply == 0 ? assets : assets.mulDivDown(totalSupply, _totalAssets() - offset);
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        assets = assets.changeDecimals(assetDecimals, decimals);
        return _convertToShares(assets, 0);
    }

    /**
     * @notice The amount of assets that the cellar would exchange for the amount of shares provided.
     * @param shares amount of shares to convert
     */
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        return totalSupply == 0 ? shares : shares.mulDivDown(_totalAssets(), totalSupply);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 assets = _convertToAssets(shares);
        return assets.changeDecimals(decimals, assetDecimals);
    }


    // ============================================ HELPERS ============================================

    /**
     * @notice Swaps token using Uniswap V3 or Sushiswap V2.
     * @param path swap path (ie. token addresses) from the token you have to the one you want
     * @param amountIn amount of tokens to be swapped
     * @param amountOutMinimum minimum amount of tokens returned
     * @param useUniswap whether to use Uniswap or Sushiswap
     * @return amountOut amount of tokens received after swap
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
            // Multihop swap:

            if (useUniswap) {
                bytes memory encodePackedPath = abi.encodePacked(tokenIn);
                for (uint256 i = 1; i < path.length; i++) {
                    encodePackedPath = abi.encodePacked(
                        encodePackedPath,
                        SWAP_FEE,
                        path[i]
                    );
                }

                // Multiple pool swaps are encoded through bytes called a `path`. A path
                // is a sequence of token addresses and poolFees that define the pools
                // used in the swaps. The format for pool encoding is (tokenIn, fee,
                // tokenOut/tokenIn, fee, tokenOut) where tokenIn/tokenOut parameter is
                // the shared token across the pools.
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
                uint256[] memory amounts = sushiSwapRouter.swapExactTokensForTokens(
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
            // Single swap:

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

        emit Swapped(tokenIn, amountIn, tokenOut, amountOut);
    }

    /**
     * @notice Deposits cellar holdings into an Aave lending pool.
     * @param token the address of the token
     * @param assets the amount of token to be deposited
     */
    function _depositToAave(address token, uint256 assets) internal {
        ERC20(token).safeApprove(address(lendingPool), assets);

        // Deposit assets to Aave protocol.
        lendingPool.deposit(token, assets, address(this), 0);

        emit DepositToAave(token, assets);
    }

    /**
     * @notice Redeems assets from Aave.
     * @param token the address of the token
     * @param assets amount of assets being redeemed for
     * @return withdrawnAmount the withdrawn amount from Aave
     */
    function _redeemFromAave(address token, uint256 assets) internal returns (uint256 withdrawnAmount) {
        // Withdraw token from Aave protocol
        withdrawnAmount = lendingPool.withdraw(token, assets, address(this));

        emit RedeemFromAave(token, withdrawnAmount);
    }

    /**
     * @notice Ensures there is a specific amount of assets in the contract available to be transferred.
     * @dev Only withdraws from strategies if needed.
     * @param assets The amount of underlying tokens to allocate
     */
    function _allocateAssets(uint256 assets) internal {
        uint256 holdingPoolAssets = inactiveAssets();

        if (assets > holdingPoolAssets) {
            _redeemFromAave(currentLendingToken, assets - holdingPoolAssets);
        }
    }

    /**
     * @notice Update state variables related to the current lending position.
     * @param newLendingToken address of the new lending token
     */
    function _updateLendingPosition(address newLendingToken) internal {
        // Retrieve the aToken that will represent the cellar's new lending position on Aave.
        address aTokenAddress = _validateTokenOnAave(newLendingToken);

        // Update state related to the current lending position.
        currentLendingToken = newLendingToken;
        assetDecimals = ERC20(currentLendingToken).decimals();
        currentAToken = aTokenAddress;

        // Update the decimals max deposits and max liquidity is denoted in if restrictions are still in
        // place. Only need to check if one of them isn't zero to see if restrictions have been removed
        // since if one them has been removed they both will be.
        if (maxLiquidity != 0) {
            maxLiquidity = 5_000_000 * 10**assetDecimals;
            maxDeposit = 50_000 * 10**assetDecimals;
        }
    }

    /**
     * @notice Check if a token is supported by Aave.
     * @param token address of the token being checked
     * @return aTokenAddress address of the token's aToken version on Aave
     */
    function _validateTokenOnAave(address token) internal view returns (address aTokenAddress) {
        (, , , , , , , aTokenAddress, , , , ) = lendingPool.getReserveData(token);

        // If the address is not null, it is supported by Aave.
        if (aTokenAddress == address(0)) revert TokenIsNotSupportedByAave(token);
    }

    // ============================================ TRANSFERS ============================================
    /**
     * @dev Modified versions of Solmate's ERC20 transfer and transferFrom functions to work with the
     *      cellar's active vs inactive shares mechanic.
     */

    function transfer(address to, uint256 amount) public override returns (bool) {
        return transferFrom(msg.sender, to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        // If the sender is not the owner of the shares, check to see if the owner has approved them to
        // spend their shares.
        if (from != msg.sender) {
            uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        }

        // Will revert here if sender is trying to transfer more shares then they have, so no need for an
        // explict check.
        balanceOf[from] -= amount;

        // Retrieve deposits of both the sender and receiver of shares.
        UserDeposit[] storage depositsFrom = userDeposits[from];
        UserDeposit[] storage depositsTo = userDeposits[to];

        // Tracks the amount of shares left to transfer.
        uint256 leftToTransfer = amount;
        for (uint256 i = currentDepositIndex[from]; i < depositsFrom.length; i++) {
            UserDeposit storage dFrom = depositsFrom[i];

            uint256 dFromShares = dFrom.shares; // Saves an extra SLOAD.

            // Track the amount of assets and shares transfered from the sender's deposit.
            uint256 transferShares = MathUtils.min(leftToTransfer, dFromShares);
            uint256 transferAssets = dFrom.assets.mulDivUp(transferShares, dFromShares);

            // Update this deposit with the amount of assets taken.
            dFrom.shares -= transferShares;
            dFrom.assets -= transferAssets;

            // Update the receiver's deposits with the amount of assets being transferred to them from the
            // sender's deposit.
            depositsTo.push(UserDeposit({
                assets: transferAssets,
                shares: transferShares,
                timeDeposited: dFrom.timeDeposited
            }));

            // Update the counter of assets left to withdraw.
            leftToTransfer -= transferShares;

            // If there are no more assets left to tranfer, we're done here. Otherwise continue.
            if (i == depositsFrom.length - 1 || leftToTransfer == 0) {
                // Store the index for the next non-zero deposit to save gas on looping.
                currentDepositIndex[from] = dFrom.shares != 0 ? i : i+1;
                break;
            }
        }

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }
}
