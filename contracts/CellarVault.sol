// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStrategiesCellar} from "./interfaces/IStrategiesCellar.sol";
import {ICellarVault} from "./interfaces/ICellarVault.sol";
import {IAaveIncentivesController} from "./interfaces/IAaveIncentivesController.sol";
import {IStakedTokenV2} from "./interfaces/IStakedTokenV2.sol";
import {ICurveSwaps} from "./interfaces/ICurveSwaps.sol";
import {ISushiSwapRouter} from "./interfaces/ISushiSwapRouter.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IGravity} from "./interfaces/IGravity.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {MathUtils} from "./utils/MathUtils.sol";

/**
 * @title Sommelier Cellar Vault
 * @notice Dynamic ERC4626 that adapts strategies to always get the best yield for stablecoins on Aave.
 */
contract CellarVault is ICellarVault, Ownable {
    using SafeTransferLib for ERC20;
    using MathUtils for uint256;

    /**
     * @notice The asset that makes up the cellar's holding pool. Will change whenever the cellar
     *         rebalances into a new strategy.
     * @dev The cellar denotes its inactive assets in this token. While it waits in the holding pool
     *      to be entered into a strategy, it is used to pay for withdraws from those redeeming their
     *      shares.
     */
    ERC20 public asset;

    /**
     * @notice The value fees are divided by to get a percentage. Represents maximum percent (100%).
     */
    uint256 public constant DENOMINATOR = 100_00;

    /**
     * @notice The percentage of platform fees (1%) taken off of active assets over a year.
     */
    uint256 public constant PLATFORM_FEE = 1_00;

    /**
     * @notice The percentage of performance fees (10%) taken off of cellar gains.
     */
    uint256 public constant PERFORMANCE_FEE = 10_00;
    
    /**
     * @notice Maximum amount of all deposits in dollars (with zero decimals).
     */
    uint256 public depositLimitUsd;
    
    /**
     * @notice Timestamp of last time platform fees were accrued.
     */
    uint256 public lastTimeAccruedPlatformFees;

    /**
     * @notice Maximum amount of assets that can be managed by the cellar. Denominated in the same
     *         units as the current asset.
     * @dev Limited to $5m until after security audits.
     */
    uint256 public maxLiquidity;

    /**
     * @notice Whether or not the contract is paused in case of an emergency.
     */
    bool public isPaused;

    /**
     * @notice Whether or not the contract is permanently shutdown in case of an emergency.
     */
    bool public isShutdown;

    // ======================================== IMMUTABLES ========================================

    // Curve Registry Exchange contract
    ICurveSwaps public immutable curveRegistryExchange; // 0x8e764bE4288B842791989DB5b8ec067279829809
    // SushiSwap Router V2 contract
    ISushiSwapRouter public immutable sushiswapRouter; // 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
    ISwapRouter public uniswapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    // Aave Lending Pool V2 contract
    ILendingPool public immutable lendingPool; // 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9
    // Aave Incentives Controller V2 contract
    IAaveIncentivesController public immutable incentivesController; // 0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5
    // Cosmos Gravity Bridge contract
    IGravity public immutable gravityBridge; // 0x69592e6f9d21989a043646fE8225da2600e5A0f7

    IStakedTokenV2 public immutable stkAAVE; // 0x4da27a545c0c5B758a6BA100e3a049001de870f5
    ERC20 public immutable AAVE; // 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9
    ERC20 public immutable WETH; // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

    address public strategiesCellar;
    address public cellarAsset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

    /**
    * @dev only Strategies Cellar contract can use functions affected by this modifier
    **/
    modifier onlyStrategiesCellar {
        if (msg.sender != strategiesCellar) revert CallerNoStrategiesCellar();
        _;
    }

    /**
     * @dev Owner of the cellar will be the Gravity contract controlled by Steward:
     *      https://github.com/cosmos/gravity-bridge/blob/main/solidity/contracts/Gravity.sol
     *      https://github.com/PeggyJV/steward
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
        ICurveSwaps _curveRegistryExchange,
        ISushiSwapRouter _sushiswapRouter,
        ILendingPool _lendingPool,
        IAaveIncentivesController _incentivesController,
        IGravity _gravityBridge,
        IStakedTokenV2 _stkAAVE,
        ERC20 _AAVE,
        ERC20 _WETH
    ) Ownable() {
        curveRegistryExchange =  _curveRegistryExchange;
        sushiswapRouter = _sushiswapRouter;
        lendingPool = _lendingPool;
        incentivesController = _incentivesController;
        gravityBridge = _gravityBridge;
        stkAAVE = _stkAAVE;
        AAVE = _AAVE;
        WETH = _WETH;

        depositLimitUsd = 50_000; // default value

        // Initialize starting point for platform fee accrual to time when cellar was created.
        // Otherwise it would incorrectly calculate how much platform fees to take when accrueFees
        // is called for the first time.
        lastTimeAccruedPlatformFees = block.timestamp;
    }

    function setStrategiesCellar(address _strategiesCellar) external onlyOwner {
        strategiesCellar = _strategiesCellar;
    }

    /**
     * @notice Withdraws assets to receiver.
     * @param outputToken outputToken
     * @param cellarAssetAmount amount of cellarAsset
     * @param outputAmount outputAmount
     * @param receiver address of account receiving the assets
     */
    function withdraw(
        address outputToken,
        uint256 cellarAssetAmount,
        uint256 outputAmount,
        address receiver
    ) onlyStrategiesCellar external {
        if (outputToken != cellarAsset) {
            _sushiswap(
                cellarAsset,
                outputToken,
                cellarAssetAmount,
                outputAmount
            );
        }

        // Transfer outputToken to receiver from the cellarVault.
        ERC20(outputToken).safeTransfer(receiver, outputAmount);
    }
    
    // TODO: needs to be changed to uniswap v3, since you need a swap with a fixed amountOut
    function _sushiswap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256) {
        // Approve the Sushiswap to swap cellarAsset.
        ERC20(tokenIn).safeApprove(address(sushiswapRouter), amountIn);

        // Specify the swap path from tokenIn -> tokenOut.
        address[] memory path = new address[](3);
        path[0] = tokenIn;
        path[1] = address(WETH);
        path[2] = tokenOut;

        // Perform a multihop swap using Sushiswap.
        uint256[] memory amounts = sushiswapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 60
        );
        
        return amounts[amounts.length - 1];
    }

    // convert active asset to inactive asset by withdraw inactive asset from lending pool
    function convertActiveToInactiveAsset(
        // we pass _baseStrategyId instead of inactive asset because in the general case the landing protocol may differ for the same inactive asset
        uint256 _baseStrategyId,
        uint256 inactiveAssets
    ) onlyStrategiesCellar external returns (uint256) {
        return _withdrawFromAave(
            IStrategiesCellar(strategiesCellar).getBaseInactiveAsset(_baseStrategyId),
            inactiveAssets
        );
    }

    // Swap token to cellarAsset (USDC) by sushiswap
    function swapToAsset(
        address token,
        uint256 amountIn,
        uint256 amountOutMin
    ) onlyStrategiesCellar external returns (uint256) {
        return _sushiswap(
            token,
            cellarAsset,
            amountIn,
            amountOutMin
        );
    }

    function toAsset(address token, uint256 tokenAmount, bool useReverseDirection) external view returns (uint256) {
        if (token == cellarAsset) {
            return tokenAmount;
        } else {
            address[] memory path = new address[](3);
            uint256[] memory amounts;

            if (useReverseDirection) {
                path[0] = cellarAsset;
                path[1] = address(WETH);
                path[2] = token;

                amounts = sushiswapRouter.getAmountsIn(tokenAmount, path);

                return amounts[0];
            } else {
                path[0] = token;
                path[1] = address(WETH);
                path[2] = cellarAsset;

                amounts = sushiswapRouter.getAmountsOut(tokenAmount, path);

                return amounts[amounts.length - 1];
            }
        }
    }

    function toToken(address token, uint256 assetAmount, bool useReverseDirection) external view returns (uint256) {
        if (token == cellarAsset) {
            return assetAmount;
        } else {
            address[] memory path = new address[](3);
            uint256[] memory amounts;

            if (useReverseDirection) {
                path[0] = token;
                path[1] = address(WETH);
                path[2] = cellarAsset;

                amounts = sushiswapRouter.getAmountsIn(assetAmount, path);

                return amounts[0];
            } else {
                path[0] = cellarAsset;
                path[1] = address(WETH);
                path[2] = token;

                amounts = sushiswapRouter.getAmountsOut(assetAmount, path);

                return amounts[amounts.length - 1];
            }
        }
    }

    // ===================================== ADMIN OPERATIONS =====================================

    /**
     * @notice Enters into the lending pool of base strategy.
     */
    function enterBaseStrategy(uint256 _baseStrategyId) external onlyOwner {
        // When the contract is shutdown, it shouldn't be allowed to enter back into a strategy with
        // the assets it just withdrew from Aave.
        if (isShutdown) revert ContractShutdown();
        
        IStrategiesCellar strategies = IStrategiesCellar(strategiesCellar);
        address inactiveAsset = strategies.getBaseInactiveAsset(_baseStrategyId);

        uint256 inactiveBaseAssets = strategies.inactiveBaseAssets(_baseStrategyId);
        if (inactiveAsset != cellarAsset) {
            inactiveBaseAssets = _sushiswap(
                cellarAsset,
                inactiveAsset,
                strategies.inactiveBaseAssetsUSDC(_baseStrategyId),
                inactiveBaseAssets
            );
        }

        // Deposits all inactive assets in the holding pool into the current strategy.
        _depositToAave(inactiveAsset, inactiveBaseAssets);

        strategies.afterEnterBaseStrategy(_baseStrategyId);
    }

    /**
     * @notice Sweep tokens sent here that are not managed by the cellar.
     * @dev This may be used in case the wrong tokens are accidentally sent to this contract.
     * @param token address of token to transfer out of this cellar
     */
    function sweep(address token) external onlyOwner {
        // Prevent sweeping of assets managed by the cellar and shares minted to the cellar as fees.
        if (token == cellarAsset || token == address(this))
            revert ProtectedAsset(token);
        
        IStrategiesCellar strategies = IStrategiesCellar(strategiesCellar);
        for (uint256 i = 0; i < strategies.strategyCount(); i++) {
            if (strategies.getIsBase(i) &&
                (token == strategies.getBaseInactiveAsset(i) || 
                 token == strategies.getBaseActiveAsset(i)))
                revert ProtectedAsset(token);
        }

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
        // TODO: need to withdraw funds from all basic strategies
//         if (activeAssets() > 0) _withdrawFromAave(address(asset), type(uint256).max);

        emit Shutdown();
    }

    // ========================================== HELPERS ==========================================
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
    function _withdrawFromAave(address token, uint256 amount) internal returns (uint256) {
        // Withdraw tokens from Aave protocol
        uint256 withdrawnAmount = lendingPool.withdraw(token, amount, address(this));

        emit WithdrawFromAave(token, withdrawnAmount);

        return withdrawnAmount;
    }

}
