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

import "hardhat/console.sol";

/**
 * @title Sommelier AaveV2 Stablecoin Cellar contract
 * @notice AaveV2StablecoinCellar contract for Sommelier Network
 * @author Sommelier Finance
 */
contract AaveV2StablecoinCellar is IAaveV2StablecoinCellar, ERC20, ReentrancyGuard, Ownable {
    using SafeTransferLib for ERC20;

    struct UserDeposit {
        uint256 assets;
        uint256 shares;
        uint256 timeDeposited;
    }

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
    address public immutable WETH; // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    address public immutable USDC; // 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48

    // Declare the variables and mappings.
    mapping(address => bool) public inputTokens;
    // The address of the token of the current lending position
    address public currentLendingToken;
    address public currentAToken;
    // Track user user deposits to determine active/inactive shares.
    mapping(address => UserDeposit[]) public userDeposits;
    // Last time inactive funds were entered into a strategy and made active.
    uint256 public lastTimeEnteredStrategy;

    // Restrict liquidity and deposits per wallet until after security audits.
    uint256 public maxDeposit = 50_000e18; // $50k
    uint256 public maxLiquidity = 5_000_000e18; // $5m

    uint24 public constant POOL_FEE = 3000;

    uint256 public constant DENOMINATOR = 10_000;
    uint256 public constant SECS_PER_YEAR = 31_556_952;
    uint256 public constant PLATFORM_FEE = 100;
    uint256 public constant PERFORMANCE_FEE = 500;

    uint256 public lastTimeAccruedPlatformFees;
    // Fees are taken in shares and redeemed for assets at the time they are transferred.
    uint256 public accruedPlatformFees;
    uint256 public accruedPerformanceFees;

    // Emergency states in case of contract malfunction.
    bool public isPaused;
    bool public isShutdown;

    /**
     * @param _uniswapRouter Uniswap V3 swap router address
     * @param _lendingPool Aave V2 lending pool address
     * @param _incentivesController _incentivesController
     * @param _gravityBridge Cosmos Gravity Bridge address
     * @param _stkAAVE stkAAVE address
     * @param _AAVE AAVE address
     * @param _WETH WETH address
     * @param _currentLendingToken token of lending pool where the cellar has its liquidity deposited
     */
    constructor(
        ISwapRouter _uniswapRouter,
        ISushiSwapRouter _sushiSwapRouter,
        ILendingPool _lendingPool,
        IAaveIncentivesController _incentivesController,
        Gravity _gravityBridge,
        IStakedTokenV2 _stkAAVE,
        address _AAVE,
        address _WETH,
        address _USDC,
        address _currentLendingToken
    ) ERC20("Sommelier Aave V2 Stablecoin Cellar LP Token", "sommSAAVE", 18) Ownable() {
        uniswapRouter =  _uniswapRouter;
        sushiSwapRouter = _sushiSwapRouter;
        lendingPool = _lendingPool;
        incentivesController = _incentivesController;
        gravityBridge = _gravityBridge;
        stkAAVE = _stkAAVE;
        AAVE = _AAVE;
        WETH = _WETH;
        USDC = _USDC;

        _updateLendingPosition(_currentLendingToken);

        lastTimeAccruedPlatformFees = block.timestamp;
    }

    /**
     * @notice Deposit supported tokens into the cellar.
     * @param token address of the supported token to deposit
     * @param assets amount of assets to deposit
     * @param minAssetsIn minimum amount of assets cellar should receive after swap (if applicable)
     * @param receiver address that should receive shares
     * @return shares amount of shares minted to receiver
     */
    function deposit(
        address token,
        uint256 assets,
        uint256 minAssetsIn,
        address receiver
    ) public nonReentrant returns (uint256 shares) {
        if (isPaused) revert ContractPaused();
        if (isShutdown) revert ContractShutdown();

        if (!inputTokens[token]) revert UnapprovedToken(token);
        if (maxLiquidity != 0 && assets + totalAssets() > maxLiquidity)
            revert LiquidityRestricted(totalAssets(), maxLiquidity);
        if (maxDeposit != 0 && ERC20(token).balanceOf(msg.sender) + assets > maxDeposit)
            revert DepositRestricted(ERC20(token).balanceOf(msg.sender), maxDeposit);

        uint256 balance = ERC20(token).balanceOf(msg.sender);
        if (assets > balance) assets = balance;

        ERC20(token).safeTransferFrom(msg.sender, address(this), assets);

        if (token != currentLendingToken) {
            assets = _swap(token, currentLendingToken, assets, minAssetsIn);
        }

        // Must calculate shares as if assets were not yet transfered in.
        if ((shares = _convertToShares(assets, assets)) == 0) revert ZeroAssets();

        _mint(receiver, shares);

        UserDeposit[] storage deposits = userDeposits[receiver];
        deposits.push(UserDeposit({
            assets: assets,
            shares: shares,
            timeDeposited: block.timestamp
        }));

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function deposit(uint256 assets) external returns (uint256) {
        return deposit(currentLendingToken, assets, assets, msg.sender);
    }

    /// @dev For ERC4626 compatibility.
    function deposit(uint256 assets, address receiver) external returns (uint256) {
        return deposit(currentLendingToken, assets, assets, receiver);
    }

    /**
     * @notice Withdraw from the cellar.
     * @param assets amount of assets to withdraw
     * @param receiver address that should receive assets
     * @param owner address that should own the shares
     * @return shares amount of shares burned from owner
     */
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();
        if (balanceOf[owner] == 0) revert ZeroShares();

        uint256 withdrawnActiveShares;
        uint256 withdrawnInactiveShares;
        uint256 withdrawnInactiveAssets;
        uint256 originalDepositedAssets; // Used for calculating performance fees.

        // Saves gas by avoiding calling `convertToAssets` on active shares during each loop.
        uint256 exchangeRate = convertToAssets(1e18);

        UserDeposit[] storage deposits = userDeposits[owner];

        uint256 leftToWithdraw = assets;
        for (uint256 i = deposits.length - 1; i + 1 != 0; i--) {
            UserDeposit storage d = deposits[i];

            uint256 dAssets = d.assets;
            if (dAssets != 0) {
                uint256 dShares = d.shares;

                uint256 withdrawnAssets;
                uint256 withdrawnShares;

                // Check if deposit shares are active or inactive.
                if (d.timeDeposited < lastTimeEnteredStrategy) {
                    // Active:
                    dAssets = exchangeRate * dShares / 1e18;
                    withdrawnAssets = MathUtils.min(leftToWithdraw, dAssets);
                    withdrawnShares = MathUtils.mulDivUp(dShares, withdrawnAssets, dAssets);

                    uint256 originalDepositWithdrawn = MathUtils.mulDivUp(d.assets, withdrawnShares, dShares);
                    // Store to calculate performance fees on future withdraws.
                    d.assets -= originalDepositWithdrawn;

                    originalDepositedAssets += originalDepositWithdrawn;
                    withdrawnActiveShares += withdrawnShares;
                } else {
                    // Inactive:
                    withdrawnAssets = MathUtils.min(leftToWithdraw, dAssets);
                    withdrawnShares = MathUtils.mulDivUp(dShares, withdrawnAssets, dAssets);

                    d.assets -= withdrawnAssets;

                    withdrawnInactiveShares += withdrawnShares;
                    withdrawnInactiveAssets += withdrawnAssets;
                }

                d.shares -= withdrawnShares;

                leftToWithdraw -= withdrawnAssets;
            }

            if (i == 0 || leftToWithdraw == 0) break;
        }

        shares = withdrawnActiveShares + withdrawnInactiveShares;

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        uint256 withdrawnActiveAssets = exchangeRate * withdrawnActiveShares / 1e18;

        // Take performance fees.
        if (withdrawnActiveAssets > 0) {
            uint256 gain = withdrawnActiveAssets - originalDepositedAssets;
            uint256 feeInAssets = gain * PERFORMANCE_FEE / DENOMINATOR;
            uint256 fees = convertToShares(feeInAssets);

            if (fees > 0) {
                accruedPerformanceFees += fees;
                withdrawnActiveAssets -= feeInAssets;

                _mint(address(this), fees);
            }
        }

        _burn(owner, shares);

        if (withdrawnActiveAssets > 0) {
            if (!isShutdown) {
                // Withdraw tokens from Aave to receiver.
                lendingPool.withdraw(currentLendingToken, withdrawnActiveAssets, receiver);
            } else {
                ERC20(currentLendingToken).transfer(receiver, withdrawnActiveAssets);
            }
        }

        if (withdrawnInactiveAssets > 0) {
            ERC20(currentLendingToken).transfer(receiver, withdrawnInactiveAssets);
        }

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function withdraw(uint256 assets) external returns (uint256 shares) {
        return withdraw(assets, msg.sender, msg.sender);
    }

    /**
     * @notice Enters Aave stablecoin strategy.
     */
    function enterStrategy() external onlyOwner {
        if (isShutdown) revert ContractShutdown();

        _depositToAave(currentLendingToken, inactiveAssets());

        lastTimeEnteredStrategy = block.timestamp;
    }

    /**
     * @notice Reinvest stkAAVE rewards back into cellar's current position on Aave.
     * @dev Must be called in the 2 day unstake period started 10 days after claimAndUnstake was run.
     * @param amount amount of stkAAVE to redeem and reinvest
     * @param minAssetsOut minimum amount of assets cellar should receive after swap
     */
    // auction model:
    // - send stkaave to the bridge
    // - add functionality to distribute SOMM rewards
    function reinvest(uint256 amount, uint256 minAssetsOut) public onlyOwner {
        stkAAVE.redeem(address(this), amount);

        address[] memory path = new address[](3);
        path[0] = AAVE;
        path[1] = WETH;
        path[2] = currentLendingToken;

        uint256 amountIn = ERC20(AAVE).balanceOf(address(this));

        // Due to the lack of liquidity for AAVE on Uniswap, we use Sushiswap instead here.
        uint256 amountOut = _sushiswap(path, amountIn, minAssetsOut);

        if (!isShutdown) {
            _depositToAave(currentLendingToken, amountOut);
        }
    }

    function reinvest(uint256 minAssetsOut) external onlyOwner {
        reinvest(type(uint256).max, minAssetsOut);
    }

    /**
     * @notice Claim stkAAVE rewards from Aave and begin cooldown period to unstake.
     * @param amount amount of rewards to claim
     * @return claimed amount of rewards claimed from Aave
     */
    function claimAndUnstake(uint256 amount) public onlyOwner returns (uint256 claimed) {
        // Necessary as claimRewards accepts a dynamic array as first param.
        address[] memory aToken = new address[](1);
        aToken[0] = currentAToken;

        claimed = incentivesController.claimRewards(aToken, amount, address(this));

        stkAAVE.cooldown();
    }

    function claimAndUnstake() external onlyOwner returns (uint256) {
        return claimAndUnstake(type(uint256).max);
    }

    /**
     * @notice Deposits cellar holdings into Aave lending pool.
     * @param token the address of the token
     * @param assets the amount of token to be deposited
     */
    function _depositToAave(address token, uint256 assets) internal {
        ERC20(token).safeApprove(address(lendingPool), assets);

        // Deposit token to Aave protocol.
        lendingPool.deposit(token, assets, address(this), 0);

        emit DepositToAave(token, assets);
    }

    /**
     * @notice Redeems a token from Aave protocol.
     * @param token the address of the token
     * @param amount the token amount being redeemed
     * @return withdrawnAmount the withdrawn amount from Aave
     */
    function _redeemFromAave(address token, uint256 amount) internal returns (uint256 withdrawnAmount) {
        // Withdraw token from Aave protocol
        withdrawnAmount = lendingPool.withdraw(token, amount, address(this));

        emit RedeemFromAave(token, withdrawnAmount);
    }

    /**
     * @notice Rebalances of Aave lending position.
     * @param newLendingToken the address of the token of the new lending position
     */
    function rebalance(address newLendingToken, uint256 minNewLendingTokenAmount) external onlyOwner {
        if (!inputTokens[newLendingToken]) revert UnapprovedToken(newLendingToken);
        if (isShutdown) revert ContractShutdown();

        if(newLendingToken == currentLendingToken) revert SameLendingToken(newLendingToken);

        uint256 lendingPositionBalance = _redeemFromAave(currentLendingToken, type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = currentLendingToken;
        path[1] = newLendingToken;

        uint256 newLendingTokenAmount = _multihopSwap(
            path,
            lendingPositionBalance,
            minNewLendingTokenAmount
        );

        _updateLendingPosition(newLendingToken);

        _depositToAave(newLendingToken, newLendingTokenAmount);

        emit Rebalance(newLendingToken, newLendingTokenAmount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        return transferFrom(msg.sender, to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (from != msg.sender) {
            uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        }

        balanceOf[from] -= amount;

        UserDeposit[] storage depositsFrom = userDeposits[from];
        UserDeposit[] storage depositsTo = userDeposits[to];

        // NOTE: Flag this for auditors.
        uint256 leftToTransfer = amount;
        for (uint256 i = depositsFrom.length - 1; i + 1 != 0; i--) {
            UserDeposit storage dFrom = depositsFrom[i];

            uint256 dFromShares = dFrom.shares;
            if (dFromShares != 0) {
                uint256 transferShares = MathUtils.min(leftToTransfer, dFromShares);
                uint256 transferAssets = MathUtils.mulDivUp(dFrom.assets, transferShares, dFromShares);

                dFrom.shares -= transferShares;
                dFrom.assets -= transferAssets;

                depositsTo.push(UserDeposit({
                    assets: transferAssets,
                    shares: transferShares,
                    timeDeposited: dFrom.timeDeposited
                }));

                leftToTransfer -= transferShares;
            }

            if (i == 0 || leftToTransfer == 0) break;
        }

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /// @notice Take platform fees off of cellar's active assets.
    function accruePlatformFees() external {
        uint256 elapsedTime = block.timestamp - lastTimeAccruedPlatformFees;
        uint256 feeInAssets = (activeAssets() * elapsedTime * PLATFORM_FEE) / DENOMINATOR / SECS_PER_YEAR;
        uint256 fees = convertToShares(feeInAssets);

        _mint(address(this), fees);

        accruedPlatformFees += fees;
    }

    /// @notice Transfer accrued fees to Cosmos to distribute.
    function transferFees() external onlyOwner {
        uint256 fees = accruedPerformanceFees + accruedPlatformFees;
        uint256 feeInAssets = convertToAssets(fees);

        // Only withdraw from Aave if holding pool does not contain enough funds.
        uint256 holdingPoolAssets = inactiveAssets();
        if (holdingPoolAssets < feeInAssets) {
            _redeemFromAave(currentLendingToken, feeInAssets - holdingPoolAssets);
        }

        _burn(address(this), fees);

        ERC20(currentLendingToken).approve(address(gravityBridge), feeInAssets);
        gravityBridge.sendToCosmos(currentLendingToken, feesDistributor, feeInAssets);

        accruedPlatformFees = 0;
        accruedPerformanceFees = 0;

        emit TransferFees(fees, feeInAssets);
    }

    /**
     * @notice Set approval for a token to be deposited into the cellar.
     * @param token the address of the supported token
     */
    function setInputToken(address token, bool isApproved) external onlyOwner {
        _validateTokenOnAave(token); // Only allow input tokens supported by Aave.

        inputTokens[token] = isApproved;

        emit SetInputToken(token, isApproved);
    }

    /// @notice Removes initial liquidity restriction.
    function removeLiquidityRestriction() external onlyOwner {
        delete maxDeposit;
        delete maxLiquidity;

        emit LiquidityRestrictionRemoved();
    }

    /**
     * @notice Pause the contract, prevents depositing.
     * @param _isPaused whether the contract should be paused
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

        // Update state and put in irreversible emergency mode.
        isShutdown = true;

        // Ensure contract is not paused.
        isPaused = false;

        if (activeAssets() > 0) {
            // Withdraw everything from Aave.
            _redeemFromAave(currentLendingToken, type(uint256).max);
        }

        emit Shutdown(msg.sender);
    }

    /**
     * @notice Removes tokens from this cellar that are not the type of token managed
     *         by this cellar. This may be used in case of accidentally sending the
     *         wrong kind of token to this contract.
     * @param token address of token to transfer out of this cellar
     */
    function sweep(address token) external onlyOwner {
        if (inputTokens[token] || token == currentAToken || token == address(this))
            revert ProtectedToken(token);

        uint256 amount = ERC20(token).balanceOf(address(this));
        ERC20(token).safeTransfer(msg.sender, amount);

        emit Sweep(token, amount);
    }

    /**
     * @notice Swaps input token by Uniswap V3.
     * @param tokenIn the address of the incoming token
     * @param tokenOut the address of the outgoing token
     * @param amountIn the amount of tokens to be swapped
     * @param amountOutMinimum the minimum amount of tokens returned
     * @return amountOut the amount of tokens received after swap
     */
    function _swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (uint256 amountOut) {
        // Approve the router to spend tokenIn.
        ERC20(tokenIn).safeApprove(address(uniswapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap.
        amountOut = uniswapRouter.exactInputSingle(params);

        emit Swapped(tokenIn, amountIn, tokenOut, amountOut);
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external onlyOwner returns (uint256 amountOut) {
        return _swap(tokenIn, tokenOut, amountIn, amountOutMinimum);
    }

    /**
     * @notice Swaps tokens by multihop swap in Uniswap V3.
     * @param path the token swap path (token addresses)
     * @param amountIn the amount of tokens to be swapped
     * @param amountOutMinimum the minimum amount of tokens returned
     * @return amountOut the amount of tokens received after swap
     */
    function _multihopSwap(
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (uint256 amountOut) {
        // Approve the router to spend first token in path.
        address tokenIn = path[0];
        ERC20(tokenIn).safeApprove(address(uniswapRouter), amountIn);

        bytes memory encodePackedPath = abi.encodePacked(tokenIn);
        for (uint256 i = 1; i < path.length; i++) {
            encodePackedPath = abi.encodePacked(
                encodePackedPath,
                POOL_FEE,
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

        // Executes the swap.
        amountOut = uniswapRouter.exactInput(params);

        emit Swapped(tokenIn, amountIn, path[path.length - 1], amountOut);
    }

    function multihopSwap(
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external onlyOwner returns (uint256) {
        return _multihopSwap(path, amountIn, amountOutMinimum);
    }

    /**
     * @notice Swaps tokens by SushiSwap Router.
     * @param path the token swap path (token addresses)
     * @param amountIn the amount of tokens to be swapped
     * @param amountOutMinimum the minimum amount of tokens returned
     * @return amountOut the amount of tokens received after swap
     */
    function _sushiswap(
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (uint256 amountOut) {
        address tokenIn = path[0];

        // Approve the router to spend first token in path.
        ERC20(tokenIn).safeApprove(address(sushiSwapRouter), amountIn);

        uint256[] memory amounts = sushiSwapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMinimum,
            path,
            address(this),
            block.timestamp + 60
        );

        amountOut = amounts[amounts.length - 1];

        emit Swapped(tokenIn, amountIn, path[path.length - 1], amountOut);
    }

    function sushiswap(
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external onlyOwner returns (uint256) {
        return _sushiswap(path, amountIn, amountOutMinimum);
    }


    /// @notice Total amount of inactive asset waiting in a holding pool to be entered into a strategy.
    function inactiveAssets() public view returns (uint256) {
        return ERC20(currentLendingToken).balanceOf(address(this));
    }

    /// @notice Total amount of active asset entered into a strategy.
    function activeAssets() public view returns (uint256) {
        // The aTokens' value is pegged to the value of the corresponding deposited
        // asset at a 1:1 ratio, so we can find the amount of assets active in a
        // strategy simply by taking balance of aTokens cellar holds.
        return ERC20(currentAToken).balanceOf(address(this));
    }

    /// @notice Total amount of the underlying asset that is managed by cellar.
    function totalAssets() public view returns (uint256) {
        return activeAssets() + inactiveAssets();
    }

    /**
     * @notice The amount of shares that the cellar would exchange for the amount of assets provided.
     * @param assets amount of assets to convert
     * @param offset amount to negatively offset total assets during calculation
     */
    function _convertToShares(uint256 assets, uint256 offset) internal view returns (uint256) {
        return totalSupply == 0 ? assets : MathUtils.mulDivDown(assets, totalSupply, totalAssets() - offset);
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, 0);
    }

    /**
     * @notice The amount of assets that the cellar would exchange for the amount of shares provided.
     * @param shares amount of shares to convert
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        return totalSupply == 0 ? shares : MathUtils.mulDivDown(shares, totalAssets(), totalSupply);
    }

    /**
     * @notice Check if a token is being supported by Aave.
     * @param token address of the token being checked
     * @return aTokenAddress address of the token's aToken version on Aave
     */
    function _validateTokenOnAave(address token) internal view returns (address aTokenAddress) {
        (, , , , , , , aTokenAddress, , , , ) = lendingPool.getReserveData(token);

        if (aTokenAddress == address(0)) revert TokenIsNotSupportedByAave(token);
    }

    /**
     * @notice Update the current lending tokening and current aToken.
     * @param newLendingToken address of the new lending token
     */
    function _updateLendingPosition(address newLendingToken) internal {
        address aTokenAddress = _validateTokenOnAave(newLendingToken);

        currentLendingToken = newLendingToken;
        currentAToken = aTokenAddress;
    }
}
