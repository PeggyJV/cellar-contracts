// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC4626, ERC20, SafeTransferLib } from "./base/ERC4626.sol";
import { Multicall } from "./base/Multicall.sol";
import { Ownable } from "@openzeppelin/access/Ownable.sol";
import { IAaveV2StablecoinCellar } from "./interfaces/IAaveV2StablecoinCellar.sol";
import { IAaveIncentivesController } from "./interfaces/IAaveIncentivesController.sol";
import { IStakedTokenV2 } from "./interfaces/IStakedTokenV2.sol";
import { ICurveSwaps } from "./interfaces/ICurveSwaps.sol";
import { ISushiSwapRouter } from "./interfaces/ISushiSwapRouter.sol";
import { IGravity } from "./interfaces/IGravity.sol";
import { ILendingPool } from "./interfaces/ILendingPool.sol";
import { Math } from "./utils/Math.sol";

import "./Errors.sol";

/**
 * @title Sommelier Aave V2 Stablecoin Cellar
 * @notice Dynamic ERC4626 that changes positions to always get the best yield for stablecoins on Aave.
 * @author Brian Le
 */
contract AaveV2StablecoinCellar is IAaveV2StablecoinCellar, ERC4626, Multicall, Ownable {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    // ======================================== POSITION STORAGE ========================================

    /**
     * @notice An interest-bearing derivative of the current asset returned by Aave for lending
     *         the current asset. Represents cellar's portion of assets earning yield in a lending
     *         position.
     */
    ERC20 public assetAToken;

    /**
     * @notice The decimals of precision used by the current position's asset.
     * @dev Since some stablecoins don't use the standard 18 decimals of precision (eg. USDC and USDT),
     *      we cache this to use for more efficient decimal conversions.
     */
    uint8 public assetDecimals;

    /**
     * @notice The total amount of assets held in the current position since the time of last accrual.
     * @dev Unlike `totalAssets`, this includes locked yield that hasn't been distributed.
     */
    uint256 public totalBalance;

    // ======================================== ACCRUAL CONFIG ========================================

    /**
     * @notice Period of time over which yield since the last accrual is linearly distributed to the cellar.
     * @dev Net gains are distributed gradually over a period to prevent frontrunning and sandwich attacks.
     *      Net losses are realized immediately otherwise users could time exits to sidestep losses.
     */
    uint32 public accrualPeriod = 7 days;

    /**
     * @notice Timestamp of when the last accrual occurred.
     */
    uint64 public lastAccrual;

    /**
     * @notice The amount of yield to be distributed to the cellar from the last accrual.
     */
    uint160 public maxLocked;

    /**
     * @notice The minimum level of total balance a strategy provider needs to achieve to receive
     *         performance fees for the next accrual.
     */
    uint256 public highWatermarkBalance;

    /**
     * @notice Set the accrual period over which yield is distributed.
     * @param newAccrualPeriod period of time in seconds of the new accrual period
     */
    function setAccrualPeriod(uint32 newAccrualPeriod) external onlyOwner {
        // Ensure that the change is not disrupting a currently ongoing distribution of accrued yield.
        if (totalLocked() > 0) revert STATE_AccrualOngoing();

        emit AccrualPeriodChanged(accrualPeriod, newAccrualPeriod);

        accrualPeriod = newAccrualPeriod;
    }

    // ========================================= FEES CONFIG =========================================

    /**
     *  @notice The percentage of yield accrued as performance fees.
     *  @dev This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     */
    uint64 public constant platformFee = 0.0025e18; // 0.25%

    /**
     * @notice The percentage of total assets accrued as platform fees over a year.
     * @dev This should be a value out of 1e18 (ie. 1e18 represents 100%, 0 represents 0%).
     */
    uint64 public constant performanceFee = 0.1e18; // 10%

    /**
     * @notice Cosmos address of module that distributes fees, specified as a hex value.
     * @dev The Gravity contract expects a 32-byte value formatted in a specific way.
     */
    bytes32 public feesDistributor = hex"000000000000000000000000b813554b423266bbd4c16c32fa383394868c1f55";

    /**
     * @notice Set the address of the fee distributor on the Sommelier chain.
     * @dev IMPORTANT: Ensure that the address is formatted in the specific way that the Gravity contract
     *      expects it to be.
     * @param newFeesDistributor formatted address of the new fee distributor module
     */
    function setFeesDistributor(bytes32 newFeesDistributor) external onlyOwner {
        emit FeesDistributorChanged(feesDistributor, newFeesDistributor);

        feesDistributor = newFeesDistributor;
    }

    // ======================================== TRUST CONFIG ========================================

    /**
     * @notice Whether an asset position is trusted or not. Prevents cellar from rebalancing into an
     *         asset that has not been trusted by the users. Trusting / distrusting of an asset is done
     *         through governance.
     */
    mapping(ERC20 => bool) public isTrusted;

    /**
     * @notice Set the trust for a position.
     * @param position address of an asset position on Aave (eg. FRAX, UST, FEI).
     * @param trust whether to trust or distrust
     */
    function setTrust(ERC20 position, bool trust) external onlyOwner {
        isTrusted[position] = trust;

        // In the case that validators no longer trust the current position, pull all assets back
        // into the cellar.
        ERC20 currentPosition = asset;
        if (trust == false && position == currentPosition) _emptyPosition(currentPosition);

        emit TrustChanged(address(position), trust);
    }

    // ======================================== LIMITS CONFIG ========================================

    /**
     * @notice Maximum amount of assets that can be managed by the cellar. Denominated in the same decimals
     *         as the current asset.
     * @dev Set to `type(uint256).max` to have no limit.
     */
    uint256 public liquidityLimit;

    /**
     * @notice Maximum amount of assets per wallet. Denominated in the same decimals as the current asset.
     * @dev Set to `type(uint256).max` to have no limit.
     */
    uint256 public depositLimit;

    /**
     * @notice Set the maximum liquidity that cellar can manage. Uses the same decimals as the current asset.
     * @param newLimit amount of assets to set as the new limit
     */
    function setLiquidityLimit(uint256 newLimit) external onlyOwner {
        emit LiquidityLimitChanged(liquidityLimit, newLimit);

        liquidityLimit = newLimit;
    }

    /**
     * @notice Set the per-wallet deposit limit. Uses the same decimals as the current asset.
     * @param newLimit amount of assets to set as the new limit
     */
    function setDepositLimit(uint256 newLimit) external onlyOwner {
        emit DepositLimitChanged(depositLimit, newLimit);

        depositLimit = newLimit;
    }

    // ======================================== EMERGENCY LOGIC ========================================

    /**
     * @notice Whether or not the contract is shutdown in case of an emergency.
     */
    bool public isShutdown;

    /**
     * @notice Prevent a function from being called during a shutdown.
     */
    modifier whenNotShutdown() {
        if (isShutdown) revert STATE_ContractShutdown();

        _;
    }

    /**
     * @notice Shutdown the cellar. Used in an emergency or if the cellar has been deprecated.
     * @param emptyPosition whether to pull all assets back into the cellar from the current position
     */
    function initiateShutdown(bool emptyPosition) external whenNotShutdown onlyOwner {
        // Pull all assets from a position.
        if (emptyPosition) _emptyPosition(asset);

        isShutdown = true;

        emit ShutdownInitiated(emptyPosition);
    }

    /**
     * @notice Restart the cellar.
     */
    function liftShutdown() external onlyOwner {
        isShutdown = false;

        emit ShutdownLifted();
    }

    // ======================================== INITIALIZATION ========================================

    /**
     * @notice Curve Registry Exchange contract. Used for rebalancing positions.
     */
    ICurveSwaps public immutable curveRegistryExchange; // 0x81C46fECa27B31F3ADC2b91eE4be9717d1cd3DD7

    /**
     * @notice SushiSwap Router V2 contract. Used for reinvesting rewards back into the current position.
     */
    ISushiSwapRouter public immutable sushiswapRouter; // 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F

    /**
     * @notice Aave Lending Pool V2 contract. Used to deposit and withdraw from the current position.
     */
    ILendingPool public immutable lendingPool; // 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9

    /**
     * @notice Aave Incentives Controller V2 contract. Used to claim and unstake rewards to reinvest.
     */
    IAaveIncentivesController public immutable incentivesController; // 0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5

    /**
     * @notice Cosmos Gravity Bridge contract. Used to transfer fees to `feeDistributor` on the Sommelier chain.
     */
    IGravity public immutable gravityBridge; // 0x69592e6f9d21989a043646fE8225da2600e5A0f7

    /**
     * @notice stkAAVE address. Used to swap rewards to the current asset to reinvest.
     */
    IStakedTokenV2 public immutable stkAAVE; // 0x4da27a545c0c5B758a6BA100e3a049001de870f5

    /**
     * @notice AAVE address. Used to swap rewards to the current asset to reinvest.
     */
    ERC20 public immutable AAVE; // 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9

    /**
     * @notice WETH address. Used to swap rewards to the current asset to reinvest.
     */
    ERC20 public immutable WETH; // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

    /**
     * @dev Owner will be set to the Gravity Bridge, which relays instructions from the Steward
     *      module to the cellars.
     *      https://github.com/PeggyJV/steward
     *      https://github.com/cosmos/gravity-bridge/blob/main/solidity/contracts/Gravity.sol
     * @param _asset current asset managed by the cellar
     * @param _approvedPositions list of approved positions to start with
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
        ERC20[] memory _approvedPositions,
        ICurveSwaps _curveRegistryExchange,
        ISushiSwapRouter _sushiswapRouter,
        ILendingPool _lendingPool,
        IAaveIncentivesController _incentivesController,
        IGravity _gravityBridge,
        IStakedTokenV2 _stkAAVE,
        ERC20 _AAVE,
        ERC20 _WETH
    ) ERC4626(_asset, "Sommelier Aave V2 Stablecoin Cellar LP Token", "aave2-CLR-S", 18) {
        // Initialize immutables.
        curveRegistryExchange = _curveRegistryExchange;
        sushiswapRouter = _sushiswapRouter;
        lendingPool = _lendingPool;
        incentivesController = _incentivesController;
        gravityBridge = _gravityBridge;
        stkAAVE = _stkAAVE;
        AAVE = _AAVE;
        WETH = _WETH;

        // Initialize asset.
        isTrusted[_asset] = true;
        uint8 _assetDecimals = _updatePosition(_asset);

        // Initialize limits.
        uint256 powOfAssetDecimals = 10**_assetDecimals;
        liquidityLimit = 5_000_000 * powOfAssetDecimals;
        depositLimit = 50_000 * powOfAssetDecimals;

        // Initialize approved positions.
        for (uint256 i; i < _approvedPositions.length; i++) isTrusted[_approvedPositions[i]] = true;

        // Initialize starting timestamp for first accrual.
        lastAccrual = uint32(block.timestamp);

        // Transfer ownership to the Gravity Bridge.
        transferOwnership(address(_gravityBridge));
    }

    // ============================================ CORE LOGIC ============================================

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        // Check that the deposit is not restricted by a deposit limit or liquidity limit and
        // prevent deposits during a shutdown.
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) revert USR_DepositRestricted(assets, maxAssets);

        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        ERC20 cellarAsset = asset;
        uint256 assetsBeforeDeposit = cellarAsset.balanceOf(address(this));

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        // Check that the balance transferred is what was expected.
        uint256 assetsReceived = cellarAsset.balanceOf(address(this)) - assetsBeforeDeposit;
        if (assetsReceived != assets) revert STATE_AssetUsesFeeOnTransfer(address(cellarAsset));

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Check that the deposit is not restricted by a deposit limit or liquidity limit and
        // prevent deposits during a shutdown.
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) revert USR_DepositRestricted(assets, maxAssets);

        ERC20 cellarAsset = asset;
        uint256 assetsBeforeDeposit = cellarAsset.balanceOf(address(this));

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        // Check that the balance transferred is what was expected.
        uint256 assetsReceived = cellarAsset.balanceOf(address(this)) - assetsBeforeDeposit;
        if (assetsReceived != assets) revert STATE_AssetUsesFeeOnTransfer(address(cellarAsset));

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @dev Check if holding position has enough funds to cover the withdraw and only pull from the
     *      current lending position if needed.
     * @param assets amount of assets to withdraw
     */
    function beforeWithdraw(
        uint256 assets,
        uint256,
        address,
        address
    ) internal override {
        ERC20 currentPosition = asset;
        uint256 holdings = totalHoldings();

        // Only withdraw if not enough assets in the holding pool.
        if (assets > holdings) {
            uint256 withdrawnAssets = _withdrawFromPosition(currentPosition, assets - holdings);

            totalBalance -= withdrawnAssets;
            highWatermarkBalance -= withdrawnAssets;
        }
    }

    // ======================================= ACCOUNTING LOGIC =======================================

    /**
     * @notice The total amount of assets in the cellar.
     * @dev Excludes locked yield that hasn't been distributed.
     */
    function totalAssets() public view override returns (uint256) {
        return totalBalance + totalHoldings() - totalLocked();
    }

    /**
     * @notice The total amount of assets in holding position.
     */
    function totalHoldings() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @notice The total amount of locked yield still being distributed.
     */
    function totalLocked() public view returns (uint256) {
        // Get the last accrual and accrual period.
        uint256 previousAccrual = lastAccrual;
        uint256 accrualInterval = accrualPeriod;

        // If the accrual period has passed, there is no locked yield.
        if (block.timestamp >= previousAccrual + accrualInterval) return 0;

        // Get the maximum amount we could return.
        uint256 maxLockedYield = maxLocked;

        // Get how much yield remains locked.
        return maxLockedYield - (maxLockedYield * (block.timestamp - previousAccrual)) / accrualInterval;
    }

    /**
     * @notice The amount of assets that the cellar would exchange for the amount of shares provided.
     * @param shares amount of shares to convert
     * @return assets the shares can be exchanged for
     */
    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 positionDecimals = assetDecimals;
        uint256 totalAssetsNormalized = totalAssets().changeDecimals(positionDecimals, 18);

        assets = totalShares == 0 ? shares : shares.mulDivDown(totalAssetsNormalized, totalShares);
        assets = assets.changeDecimals(18, positionDecimals);
    }

    /**
     * @notice The amount of shares that the cellar would exchange for the amount of assets provided.
     * @param assets amount of assets to convert
     * @return shares the assets can be exchanged for
     */
    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 positionDecimals = assetDecimals;
        uint256 assetsNormalized = assets.changeDecimals(positionDecimals, 18);
        uint256 totalAssetsNormalized = totalAssets().changeDecimals(positionDecimals, 18);

        shares = totalShares == 0 ? assetsNormalized : assetsNormalized.mulDivDown(totalShares, totalAssetsNormalized);
    }

    /**
     * @notice Simulate the effects of minting shares at the current block, given current on-chain conditions.
     * @param shares amount of shares to mint
     * @return assets that will be deposited
     */
    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 positionDecimals = assetDecimals;
        uint256 totalAssetsNormalized = totalAssets().changeDecimals(positionDecimals, 18);

        assets = totalShares == 0 ? shares : shares.mulDivUp(totalAssetsNormalized, totalShares);
        assets = assets.changeDecimals(18, positionDecimals);
    }

    /**
     * @notice Simulate the effects of withdrawing assets at the current block, given current on-chain conditions.
     * @param assets amount of assets to withdraw
     * @return shares that will be redeemed
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        uint256 totalShares = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint8 positionDecimals = assetDecimals;
        uint256 assetsNormalized = assets.changeDecimals(positionDecimals, 18);
        uint256 totalAssetsNormalized = totalAssets().changeDecimals(positionDecimals, 18);

        shares = totalShares == 0 ? assetsNormalized : assetsNormalized.mulDivUp(totalShares, totalAssetsNormalized);
    }

    // ========================================= LIMITS LOGIC =========================================

    /**
     * @notice Total amount of assets that can be deposited for a user.
     * @param receiver address of account that would receive the shares
     * @return assets maximum amount of assets that can be deposited
     */
    function maxDeposit(address receiver) public view override returns (uint256 assets) {
        if (isShutdown) return 0;

        uint256 asssetDepositLimit = depositLimit;
        uint256 asssetLiquidityLimit = liquidityLimit;
        if (asssetDepositLimit == type(uint256).max && asssetLiquidityLimit == type(uint256).max)
            return type(uint256).max;

        (uint256 leftUntilDepositLimit, uint256 leftUntilLiquidityLimit) = _getAssetsLeftUntilLimits(
            asssetDepositLimit,
            asssetLiquidityLimit,
            receiver
        );

        // Only return the more relevant of the two.
        assets = Math.min(leftUntilDepositLimit, leftUntilLiquidityLimit);
    }

    /**
     * @notice Total amount of shares that can be minted for a user.
     * @param receiver address of account that would receive the shares
     * @return shares maximum amount of shares that can be minted
     */
    function maxMint(address receiver) public view override returns (uint256 shares) {
        if (isShutdown) return 0;

        uint256 asssetDepositLimit = depositLimit;
        uint256 asssetLiquidityLimit = liquidityLimit;
        if (asssetDepositLimit == type(uint256).max && asssetLiquidityLimit == type(uint256).max)
            return type(uint256).max;

        (uint256 leftUntilDepositLimit, uint256 leftUntilLiquidityLimit) = _getAssetsLeftUntilLimits(
            asssetDepositLimit,
            asssetLiquidityLimit,
            receiver
        );

        // Only return the more relevant of the two.
        shares = convertToShares(Math.min(leftUntilDepositLimit, leftUntilLiquidityLimit));
    }

    function _getAssetsLeftUntilLimits(
        uint256 asssetDepositLimit,
        uint256 asssetLiquidityLimit,
        address receiver
    ) internal view returns (uint256 leftUntilDepositLimit, uint256 leftUntilLiquidityLimit) {
        uint256 totalAssetsIncludingUnrealizedGains = assetAToken.balanceOf(address(this)) + totalHoldings();

        // Convert receiver's shares to assets using total assets including locked yield.
        uint256 receiverShares = balanceOf[receiver];
        uint256 totalShares = totalSupply;
        uint256 maxWithdrawableByReceiver = totalShares == 0
            ? receiverShares
            : receiverShares.mulDivDown(totalAssetsIncludingUnrealizedGains, totalShares);

        // Get the maximum amount of assets that can be deposited until limits are reached.
        leftUntilDepositLimit = asssetDepositLimit.subMinZero(maxWithdrawableByReceiver);
        leftUntilLiquidityLimit = asssetLiquidityLimit.subMinZero(totalAssetsIncludingUnrealizedGains);
    }

    // ========================================== ACCRUAL LOGIC ==========================================

    /**
     * @notice Accrue yield, platform fees, and performance fees.
     * @dev Since this is the function responsible for distributing yield to shareholders and
     *      updating the cellar's balance, it is important to make sure it gets called regularly.
     */
    function accrue() public {
        uint256 totalLockedYield = totalLocked();

        // Without this check, malicious actors could do a slowdown attack on the distribution of
        // yield by continuously resetting the accrual period.
        if (msg.sender != owner() && totalLockedYield > 0) revert STATE_AccrualOngoing();

        // Compute and store current exchange rate between assets and shares for gas efficiency.
        uint256 oneAsset = 10**assetDecimals;
        uint256 exchangeRate = convertToShares(oneAsset);

        // Get balance since last accrual and updated balance for this accrual.
        uint256 balanceThisAccrual = assetAToken.balanceOf(address(this));

        // Calculate platform fees accrued.
        uint256 elapsedTime = block.timestamp - lastAccrual;
        uint256 platformFeeInAssets = (balanceThisAccrual * elapsedTime * platformFee) / 1e18 / 365 days;
        uint256 platformFees = platformFeeInAssets.mulDivDown(exchangeRate, oneAsset); // Convert to shares.

        // Calculate performance fees accrued.
        uint256 yield = balanceThisAccrual.subMinZero(highWatermarkBalance);
        uint256 performanceFeeInAssets = yield.mulWadDown(performanceFee);
        uint256 performanceFees = performanceFeeInAssets.mulDivDown(exchangeRate, oneAsset); // Convert to shares.

        // Mint accrued fees as shares.
        _mint(address(this), platformFees + performanceFees);

        // Do not count assets set aside for fees as yield. Allows fees to be immediately withdrawable.
        maxLocked = uint160(totalLockedYield + yield.subMinZero(platformFeeInAssets + performanceFeeInAssets));

        lastAccrual = uint32(block.timestamp);

        totalBalance = balanceThisAccrual;

        // Only update high watermark if balance greater than last high watermark.
        if (balanceThisAccrual > highWatermarkBalance) highWatermarkBalance = balanceThisAccrual;

        emit Accrual(platformFees, performanceFees, yield);
    }

    // ========================================= POSITION LOGIC =========================================

    /**
     * @notice Pushes assets into the current Aave lending position.
     * @param assets amount of assets to enter into the current position
     */
    function enterPosition(uint256 assets) public whenNotShutdown onlyOwner {
        ERC20 currentPosition = asset;

        totalBalance += assets;

        // Without this line, assets entered into Aave would be counted as gains during the next
        // accrual.
        highWatermarkBalance += assets;

        _depositIntoPosition(currentPosition, assets);

        emit EnterPosition(address(currentPosition), assets);
    }

    /**
     * @notice Pushes all assets in holding into the current Aave lending position.
     */
    function enterPosition() external {
        enterPosition(totalHoldings());
    }

    /**
     * @notice Pulls assets from the current Aave lending position.
     * @param assets amount of assets to exit from the current position
     */
    function exitPosition(uint256 assets) public whenNotShutdown onlyOwner {
        ERC20 currentPosition = asset;

        uint256 withdrawnAssets = _withdrawFromPosition(currentPosition, assets);

        totalBalance -= withdrawnAssets;

        // Without this line, assets exited from Aave would be counted as losses during the next
        // accrual.
        highWatermarkBalance -= withdrawnAssets;

        emit ExitPosition(address(currentPosition), assets);
    }

    /**
     * @notice Pulls all assets from the current Aave lending position.
     * @dev Strategy providers should not assume the position is empty after this call. If there is
     *      unrealized yield, that will still remain in the position. To completely empty the cellar,
     *      multicall accrue and this.
     */
    function exitPosition() external {
        exitPosition(totalBalance);
    }

    /**
     * @notice Rebalances current assets into a new position.
     * @param route array of [initial token, pool, token, pool, token, ...] that specifies the swap route on Curve.
     * @param swapParams multidimensional array of [i, j, swap type] where i and j are the correct
                         values for the n'th pool in `_route` and swap type should be 1 for a
                         stableswap `exchange`, 2 for stableswap `exchange_underlying`, 3 for a
                         cryptoswap `exchange`, 4 for a cryptoswap `exchange_underlying` and 5 for
                         Polygon factory metapools `exchange_underlying`
     * @param minAssetsOut minimum amount of assets received after swap
     */
    function rebalance(
        address[9] memory route,
        uint256[3][4] memory swapParams,
        uint256 minAssetsOut
    ) external whenNotShutdown onlyOwner {
        // Retrieve the last token in the route and store it as the new asset position.
        ERC20 newPosition;
        for (uint256 i; ; i += 2) {
            if (i == 8 || route[i + 1] == address(0)) {
                newPosition = ERC20(route[i]);
                break;
            }
        }

        // Ensure the asset position is trusted.
        if (!isTrusted[newPosition]) revert USR_UntrustedPosition(address(newPosition));

        ERC20 oldPosition = asset;

        // Doesn't make sense to rebalance into the same position.
        if (newPosition == oldPosition) revert USR_SamePosition(address(oldPosition));

        // Store this for later when updating total balance.
        uint256 totalAssetsInHolding = totalHoldings();
        uint256 totalBalanceIncludingHoldings = totalBalance + totalAssetsInHolding;

        // Pull any assets in the lending position back in to swap everything into the new position.
        uint256 assetsBeforeSwap = assetAToken.balanceOf(address(this)) > 0
            ? _withdrawFromPosition(oldPosition, type(uint256).max) + totalAssetsInHolding
            : totalAssetsInHolding;

        // Perform stablecoin swap using Curve.
        oldPosition.safeApprove(address(curveRegistryExchange), assetsBeforeSwap);
        uint256 assetsAfterSwap = curveRegistryExchange.exchange_multiple(
            route,
            swapParams,
            assetsBeforeSwap,
            minAssetsOut
        );

        uint8 oldPositionDecimals = assetDecimals;

        // Updates state for new position and check that Aave supports it.
        uint8 newPositionDecimals = _updatePosition(newPosition);

        // Deposit all newly swapped assets into Aave.
        _depositIntoPosition(newPosition, assetsAfterSwap);

        // Update maximum locked yield to scale accordingly to the decimals of the new asset.
        maxLocked = uint160(uint256(maxLocked).changeDecimals(oldPositionDecimals, newPositionDecimals));

        // Update the cellar's balance. If the unrealized gains before rebalancing exceed the losses
        // from the swap, then losses will be taken from the unrealized gains during next accrual
        // and this rebalance will not effect the exchange rate of shares to assets. Otherwise, the
        // losses from this rebalance will be realized and factored into the new balance.
        uint256 newTotalBalance = Math.min(
            totalBalanceIncludingHoldings.changeDecimals(oldPositionDecimals, newPositionDecimals),
            assetsAfterSwap
        );

        totalBalance = newTotalBalance;

        // Keep high watermark at level it should be at before rebalance because otherwise swap
        // losses from this rebalance would not be counted in the next accrual. Include holdings
        // into new high watermark balance as those have all been deposited into Aave now.
        highWatermarkBalance = (highWatermarkBalance + totalAssetsInHolding).changeDecimals(
            oldPositionDecimals,
            newPositionDecimals
        );

        emit Rebalance(address(oldPosition), address(newPosition), newTotalBalance);
    }

    // ======================================= REINVEST LOGIC =======================================

    /**
     * @notice Claim rewards from Aave and begin cooldown period to unstake them.
     * @return rewards amount of stkAAVE rewards claimed from Aave
     */
    function claimAndUnstake() external onlyOwner returns (uint256 rewards) {
        // Necessary to do as `claimRewards` accepts a dynamic array as first param.
        address[] memory aToken = new address[](1);
        aToken[0] = address(assetAToken);

        // Claim all stkAAVE rewards.
        rewards = incentivesController.claimRewards(aToken, type(uint256).max, address(this));

        // Begin the 10 day cooldown period for unstaking stkAAVE for AAVE.
        stkAAVE.cooldown();

        emit ClaimAndUnstake(rewards);
    }

    /**
     * @notice Reinvest rewards back into cellar's current position.
     * @dev Must be called within 2 day unstake period 10 days after `claimAndUnstake` was run.
     * @param minAssetsOut minimum amount of assets to receive after swapping AAVE to the current asset
     */
    function reinvest(uint256 minAssetsOut) external onlyOwner {
        // Redeems the cellar's stkAAVE rewards for AAVE.
        stkAAVE.redeem(address(this), type(uint256).max);

        // Get the amount of AAVE rewards going in to be swap for the current asset.
        uint256 rewardsIn = AAVE.balanceOf(address(this));

        ERC20 currentAsset = asset;

        // Specify the swap path from AAVE -> WETH -> current asset.
        address[] memory path = new address[](3);
        path[0] = address(AAVE);
        path[1] = address(WETH);
        path[2] = address(currentAsset);

        // Perform a multihop swap using Sushiswap.
        AAVE.safeApprove(address(sushiswapRouter), rewardsIn);
        uint256[] memory amounts = sushiswapRouter.swapExactTokensForTokens(
            rewardsIn,
            minAssetsOut,
            path,
            address(this),
            block.timestamp + 60
        );

        uint256 assetsOut = amounts[amounts.length - 1];

        // In the case of a shutdown, we just may want to redeem any leftover rewards for users to
        // claim but without entering them back into a position in case the position has been
        // exited. Also, for the purposes of performance fee calculation, we count reinvested
        // rewards as yield so do not update balance.
        if (!isShutdown) _depositIntoPosition(currentAsset, assetsOut);

        emit Reinvest(address(currentAsset), rewardsIn, assetsOut);
    }

    // ========================================= FEES LOGIC =========================================

    /**
     * @notice Transfer accrued fees to the Sommelier chain to distribute.
     * @dev Fees are accrued as shares and redeemed upon transfer.
     */
    function sendFees() external onlyOwner {
        // Redeem our fee shares for assets to send to the fee distributor module.
        uint256 totalFees = balanceOf[address(this)];
        uint256 assets = previewRedeem(totalFees);
        require(assets != 0, "ZERO_ASSETS");

        // Only withdraw assets from position if the holding position does not contain enough funds.
        // Pass in only the amount of assets withdrawn, the rest doesn't matter.
        beforeWithdraw(assets, 0, address(0), address(0));

        _burn(address(this), totalFees);

        // Transfer assets to a fee distributor on the Sommelier chain.
        ERC20 positionAsset = asset;
        positionAsset.safeApprove(address(gravityBridge), assets);
        gravityBridge.sendToCosmos(address(positionAsset), feesDistributor, assets);

        emit SendFees(totalFees, assets);
    }

    // ====================================== RECOVERY LOGIC ======================================

    /**
     * @notice Sweep tokens that are not suppose to be in the cellar.
     * @dev This may be used in case the wrong tokens are accidentally sent.
     * @param token address of token to transfer out of this cellar
     * @param to address to transfer sweeped tokens to
     */
    function sweep(ERC20 token, address to) external onlyOwner {
        // Prevent sweeping of assets managed by the cellar and shares minted to the cellar as fees.
        if (token == asset || token == assetAToken || token == this || address(token) == address(stkAAVE))
            revert USR_ProtectedAsset(address(token));

        // Transfer out tokens in this cellar that shouldn't be here.
        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(to, amount);

        emit Sweep(address(token), to, amount);
    }

    // ===================================== HELPER FUNCTIONS =====================================

    /**
     * @notice Deposits cellar holdings into an Aave lending position.
     * @param position the address of the asset position
     * @param assets the amount of assets to deposit
     */
    function _depositIntoPosition(ERC20 position, uint256 assets) internal {
        // Deposit assets into Aave position.
        position.safeApprove(address(lendingPool), assets);
        lendingPool.deposit(address(position), assets, address(this), 0);

        emit DepositIntoPosition(address(position), assets);
    }

    /**
     * @notice Withdraws assets from an Aave lending position.
     * @dev The assets withdrawn differs from the assets specified if withdrawing `type(uint256).max`.
     * @param position the address of the asset position
     * @param assets amount of assets to withdraw
     * @return withdrawnAssets amount of assets actually withdrawn
     */
    function _withdrawFromPosition(ERC20 position, uint256 assets) internal returns (uint256 withdrawnAssets) {
        // Withdraw assets from Aave position.
        withdrawnAssets = lendingPool.withdraw(address(position), assets, address(this));

        emit WithdrawFromPosition(address(position), withdrawnAssets);
    }

    /**
     * @notice Pull all assets from the current lending position on Aave back into holding.
     * @param position the address of the asset position to pull from
     */
    function _emptyPosition(ERC20 position) internal {
        uint256 totalPositionBalance = totalBalance;

        if (totalPositionBalance > 0) {
            accrue();

            _withdrawFromPosition(position, type(uint256).max);

            delete totalBalance;
            delete highWatermarkBalance;
        }
    }

    /**
     * @notice Update state variables related to the current position.
     * @dev Be aware that when updating to an asset that uses less decimals than the previous
     *      asset (eg. DAI -> USDC), `depositLimit` and `liquidityLimit` will lose some precision
     *      due to truncation.
     * @param newPosition address of the new asset being managed by the cellar
     */
    function _updatePosition(ERC20 newPosition) internal returns (uint8 newAssetDecimals) {
        // Retrieve the aToken that will represent the cellar's new position on Aave.
        (, , , , , , , address aTokenAddress, , , , ) = lendingPool.getReserveData(address(newPosition));

        // If the address is not null, it is supported by Aave.
        if (aTokenAddress == address(0)) revert USR_UnsupportedPosition(address(newPosition));

        // Update the decimals used by limits if necessary.
        uint8 oldAssetDecimals = assetDecimals;
        newAssetDecimals = newPosition.decimals();

        // Ensure the decimals of precision of the new position uses will not break the cellar.
        if (newAssetDecimals > 18) revert USR_TooManyDecimals(newAssetDecimals, 18);

        // Ignore if decimals are the same or if it is the first time initializing a position.
        if (oldAssetDecimals != 0 && oldAssetDecimals != newAssetDecimals) {
            uint256 asssetDepositLimit = depositLimit;
            uint256 asssetLiquidityLimit = liquidityLimit;
            if (asssetDepositLimit != type(uint256).max)
                depositLimit = asssetDepositLimit.changeDecimals(oldAssetDecimals, newAssetDecimals);

            if (asssetLiquidityLimit != type(uint256).max)
                liquidityLimit = asssetLiquidityLimit.changeDecimals(oldAssetDecimals, newAssetDecimals);
        }

        // Update state related to the current position.
        asset = newPosition;
        assetDecimals = newAssetDecimals;
        assetAToken = ERC20(aTokenAddress);
    }
}
