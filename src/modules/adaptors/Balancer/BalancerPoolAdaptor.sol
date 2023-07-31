// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, Registry, PriceRouter } from "src/modules/adaptors/BaseAdaptor.sol";
import { IBalancerQueries } from "src/interfaces/external/Balancer/IBalancerQueries.sol";
import { IVault, IERC20, IAsset, IFlashLoanRecipient } from "src/interfaces/external/Balancer/IVault.sol";
import { IStakingLiquidityGauge } from "src/interfaces/external/Balancer/IStakingLiquidityGauge.sol";
import { ILiquidityGaugev3Custom } from "src/interfaces/external/Balancer/ILiquidityGaugev3Custom.sol";
import { IBasePool } from "src/interfaces/external/Balancer/typically-npm/IBasePool.sol";
import { ILiquidityGauge } from "src/interfaces/external/Balancer/ILiquidityGauge.sol";
import { Math } from "src/utils/Math.sol";
import { console } from "@forge-std/Test.sol";
import { IBalancerMinter } from "src/interfaces/external/IBalancerMinter.sol";

/**
 * @title Balancer Pool Adaptor
 * @notice Allows Cellars to interact with Stable and Boosted Stable Balancer Pools (BPs).
 * @author 0xEinCodes and CrispyMangoes
 */
contract BalancerPoolAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(ERC20 _bpt, address _liquidityGauge)
    // Where:
    // `_bpt` is the Balancer pool token of the Balancer LP market this adaptor is working with
    // `_liquidityGauge` is the balancer gauge corresponding to the specified bpt
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has the `assetOf` as a bpt, and thus relies on the `PriceRouterv2` Balancer
    // Extensions corresponding with the type of bpt the Cellar is working with.
    //====================================================================

    //============================================ Error Statements ===========================================

    /**
     * @notice Tried using a bpt and/or liquidityGauge that is not setup as a position.
     */
    error BalancerPoolAdaptor__BptAndGaugeComboMustBeTracked(address bpt, address liquidityGauge);

    /**
     * @notice Attempted balancer pool joins, exits, staking, unstaking, etc. with bad slippage
     */
    error BalancerPoolAdaptor___Slippage();

    /**
     * @notice Constructor param for slippage too high
     */
    error BalancerPoolAdaptor___InvalidConstructorSlippage();

    /**
     * @notice Provided swap array length differs from expected tokens array length.
     */
    error BalancerPoolAdaptor___LengthMismatch();

    /**
     * @notice Provided swap information with wrong swap kind.
     */
    error BalancerPoolAdaptor___WrongSwapKind();

    /**
     * @notice Provided swap information does not match expected tokens array.
     * @dev Swap information passed to `joinPool` and `exitPool` MUST line up with
     *      the expected tokens array.
     *      Example: BB A USD has 4 constituents BB A DAI, BB A USDT, BB A USDC, BB A USD
     *               but the pool has pre-minted BPTs in its tokens array.
     *               So the expected tokens array will only contain the first 3 constituents.
     *               The swap data must be in the following order.
     *               0 - Swap data to swap DAI for BB A DAI.
     *               1 - Swap data to swap USDT for BB A USDT.
     *               2 - Swap data to swap USDC for BB A USDC.
     *               If the swap data is not in the order above, or tries swapping using tokens
     *               that are NOT in the BPT, the call will revert with the below error.
     */
    error BalancerPoolAdaptor___SwapTokenAndExpectedTokenMismatch();

    /**
     * @notice Provided swap information tried to work with internal balances.
     */
    error BalancerPoolAdaptor___InternalBalancesNotSupported();

    /**
     * @notice Provided swap information chose to keep an asset that is not supported
     *         for pricing.
     */
    error BalancerPoolAdaptor___UnsupportedTokenNotSwapped();

    /**
     * @notice Stores each swaps min amount, and deadline.
     * @dev Needed to overcome stack too deep errors.
     */
    struct SwapData {
        uint256[] minAmountsForSwaps;
        uint256[] swapDeadlines;
    }

    //============================================ Global Vars && Specific Adaptor Constants ===========================================

    /**
     * @notice The Balancer Vault contract
     * @notice For mainnet use 0xBA12222222228d8Ba445958a75a0704d566BF2C8
     */
    IVault public immutable vault;

    /**
     * @notice The BalancerMinter contract adhering to IBalancerMinter (custom interface) to access `mint()` to collect $BAL rewards for Cellar
     * @notice For mainnet use 0x239e55F427D44C3cc793f49bFB507ebe76638a2b
     */
    IBalancerMinter public immutable minter;

    /**
     * @notice Number between 0.9e4, and 1e4 representing the amount of slippage that can be
     *         tolerated when entering/exiting a pool.
     *         - 0.90e4: 10% slippage
     *         - 0.95e4: 5% slippage
     */
    uint32 public immutable balancerSlippage;

    /**
     * @notice The enum value needed to specify an Exact Tokens in for BPT out join.
     */
    uint256 public constant EXACT_TOKENS_IN_FOR_BPT_OUT = 1;

    //============================================ Constructor ===========================================

    constructor(address _vault, address _minter, uint32 _balancerSlippage) {
        if (_balancerSlippage < 0.9e4 || _balancerSlippage > 1e4)
            revert BalancerPoolAdaptor___InvalidConstructorSlippage();
        vault = IVault(_vault);
        minter = IBalancerMinter(_minter);
        balancerSlippage = _balancerSlippage;
    }

    //============================================ Global Functions ===========================================

    /**
     * @notice Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this identifier is needed during Cellar Delegate Call Operations, so getting the address of the adaptor is more difficult.
     * @return encoded adaptor identifier
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Balancer Pool Adaptor V 1.0"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are allowed into this position.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {}

    /**
     * @notice If a user withdraw needs more BPTs than what is in the Cellar's
     *         wallet, then the Cellar will unstake BPTs from the gauge.
     */
    function withdraw(
        uint256 _amountBPTToSend,
        address _recipient,
        bytes memory _adaptorData,
        bytes memory
    ) public override {
        // Run external receiver check.
        _externalReceiverCheck(_recipient);
        (ERC20 bpt, address liquidityGauge) = abi.decode(_adaptorData, (ERC20, address));
        uint256 liquidBptBeforeWithdraw = bpt.balanceOf(address(this));
        if (_amountBPTToSend > liquidBptBeforeWithdraw) {
            uint256 amountToUnstake = _amountBPTToSend - liquidBptBeforeWithdraw;
            unstakeBPT(bpt, liquidityGauge, amountToUnstake);
        }
        bpt.safeTransfer(_recipient, _amountBPTToSend);
    }

    /**
     * @notice Accounts for BPTs in the Cellar's wallet, and staked in gauge.
     * @dev See `balanceOf`.
     */
    function withdrawableFrom(bytes memory _adaptorData, bytes memory) public view override returns (uint256) {
        return balanceOf(_adaptorData);
    }

    /**
     * @notice Calculates the Cellar's balance of the positions creditAsset, a specific bpt.
     * @param _adaptorData encoded data for trusted adaptor position detailing the bpt and liquidityGauge address (if it exists)
     * @return total balance of bpt for Cellar, including liquid bpt and staked bpt
     */
    function balanceOf(bytes memory _adaptorData) public view override returns (uint256) {
        (ERC20 bpt, address liquidityGauge) = abi.decode(_adaptorData, (ERC20, address));
        if (liquidityGauge == address(0)) return ERC20(bpt).balanceOf(msg.sender);
        ERC20 liquidityGaugeToken = ERC20(liquidityGauge);
        uint256 stakedBPT = liquidityGaugeToken.balanceOf(msg.sender);
        return ERC20(bpt).balanceOf(msg.sender) + stakedBPT;
    }

    /**
     * @notice Returns the positions underlying assets.
     * @param _adaptorData encoded data for trusted adaptor position detailing the bpt and liquidityGauge address (if it exists)
     * @return bpt for Cellar's respective balancer pool position
     */
    function assetOf(bytes memory _adaptorData) public pure override returns (ERC20) {
        return ERC20(abi.decode(_adaptorData, (address)));
    }

    /**
     * @notice When positions are added to the Registry, this function can be used in order to figure out
     *         what assets this adaptor needs to price, and confirm pricing is properly setup.
     * @param _adaptorData specified bpt of interest
     * @return assets for Cellar's respective balancer pool position
     * @dev all breakdowns of bpt pricing and its underlying assets are done through the PriceRouter extension (in accordance to PriceRouterv2 architecture)
     */
    function assetsUsed(bytes memory _adaptorData) public pure override returns (ERC20[] memory assets) {
        assets = new ERC20[](1);
        assets[0] = assetOf(_adaptorData);
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     * @return whether adaptor returns debt or not
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to join Balancer pools using EXACT_TOKENS_IN_FOR_BPT_OUT joins.
     * @dev `swapsBeforeJoin` MUST match up with expected token array returned from `_getPoolTokensWithNoPremintedBpt`.
     *      IE if the first token in expected token array is DAI, the first swap in `swapsBeforeJoin` MUST be for DAI.
     * @dev Max Available logic IS supported.
     */
    function joinPool(
        ERC20 targetBpt,
        IVault.SingleSwap[] memory swapsBeforeJoin,
        SwapData memory swapData,
        uint256 minimumBpt
    ) external {
        bytes32 poolId = IBasePool(address(targetBpt)).getPoolId();
        PriceRouter priceRouter = Cellar(address(this)).priceRouter();

        // Start formulating request.
        IVault.JoinPoolRequest memory request;
        request.fromInternalBalance = false;
        ERC20[] memory expectedTokensIn;
        {
            (IERC20[] memory poolTokens, , ) = vault.getPoolTokens(poolId);
            expectedTokensIn = _getPoolTokensWithNoPremintedBpt(address(targetBpt), poolTokens);
            request.assets = new IAsset[](poolTokens.length);
            for (uint256 i; i < poolTokens.length; ++i) request.assets[i] = IAsset(address(poolTokens[i]));
            request.maxAmountsIn = new uint256[](poolTokens.length);
            // NOTE maxAmountsIn is always set to be type(uint256).max.
            // The approvals given to the vault will limit the max amount that can actually go into the pool.
            for (uint256 i; i < poolTokens.length; ++i) request.maxAmountsIn[i] = type(uint256).max;
        }

        // Insure swapsBeforeJoin has the same length as expectedTokensIn.
        if (swapsBeforeJoin.length != expectedTokensIn.length) revert BalancerPoolAdaptor___LengthMismatch();

        // Iterate through swapsBeforeJoin and swap if required. Then set approvals for join.
        {
            uint256[] memory joinAmounts = new uint256[](expectedTokensIn.length);
            for (uint256 i; i < swapsBeforeJoin.length; ++i) {
                // If this amount is zero, we are not swapping, nor using it to join the pool, so continue.
                if (swapsBeforeJoin[i].amount == 0) continue;

                // Approve the vault to spend assetIn, which will be used either in a swap, or pool join.
                ERC20 inputToken = ERC20(address(swapsBeforeJoin[i].assetIn));
                swapsBeforeJoin[i].amount = _maxAvailable(inputToken, swapsBeforeJoin[i].amount);
                inputToken.safeApprove(address(vault), swapsBeforeJoin[i].amount);

                // if assetOut is not the zero address, we are trying to swap for it.
                if (address(swapsBeforeJoin[i].assetOut) != address(0)) {
                    // If we are swapping for an asset, make sure that asset is in the targetBpt pool.
                    if (address(swapsBeforeJoin[i].assetOut) != address(expectedTokensIn[i]))
                        revert BalancerPoolAdaptor___SwapTokenAndExpectedTokenMismatch();

                    // Make sure swap kind is GIVEN_IN.
                    if (swapsBeforeJoin[i].kind != IVault.SwapKind.GIVEN_IN)
                        revert BalancerPoolAdaptor___WrongSwapKind();

                    // Formulate FundManagement struct.
                    IVault.FundManagement memory fundManagement = IVault.FundManagement({
                        sender: address(this),
                        fromInternalBalance: false,
                        recipient: payable(address(this)),
                        toInternalBalance: false
                    });

                    // Perform the swap.
                    // NOTE this output will ALWAYS be the amount out from the swap because we insure the swap kind is GIVEN_IN.
                    uint256 swapAmountOut = vault.swap(
                        swapsBeforeJoin[i],
                        fundManagement,
                        swapData.minAmountsForSwaps[i],
                        swapData.swapDeadlines[i]
                    );

                    // Approve vault to spend bought asset.
                    ERC20(address(swapsBeforeJoin[i].assetOut)).safeApprove(address(vault), swapAmountOut);

                    joinAmounts[i] = swapAmountOut;
                } else {
                    // We are not swapping, and have a non zero amount so insure that assetIn is apart of targetBpt.
                    if (address(swapsBeforeJoin[i].assetIn) != address(expectedTokensIn[i]))
                        revert BalancerPoolAdaptor___SwapTokenAndExpectedTokenMismatch();
                    joinAmounts[i] = swapsBeforeJoin[i].amount;
                }
            }
            request.userData = abi.encode(EXACT_TOKENS_IN_FOR_BPT_OUT, joinAmounts, minimumBpt);
        }

        uint256 targetDelta = targetBpt.balanceOf(address(this));
        vault.joinPool(poolId, address(this), address(this), request);
        targetDelta = targetBpt.balanceOf(address(this)) - targetDelta;

        // Revoke any lingering approvals, and build arrays to be used in `getValues` below.
        uint256[] memory inputAmounts = new uint256[](swapsBeforeJoin.length);
        ERC20[] memory inputTokens = new ERC20[](swapsBeforeJoin.length);
        // If we had to swap for an asset, revoke any unused approval from join.
        for (uint256 i; i < swapsBeforeJoin.length; ++i) {
            address assetIn = address(swapsBeforeJoin[i].assetIn);
            inputTokens[i] = ERC20(address(assetIn));
            inputAmounts[i] = swapsBeforeJoin[i].amount;
            // Revoke input asset approval.
            _revokeExternalApproval(inputTokens[i], address(vault));

            // Revoke approval if we swapped for an asset.
            address assetOut = address(swapsBeforeJoin[i].assetOut);
            if (assetOut != address(0)) _revokeExternalApproval(ERC20(assetOut), address(vault));
        }

        // Compare value in vs value out, and revert if slippage is too high.
        uint256 valueInConvertedToTarget = priceRouter.getValues(inputTokens, inputAmounts, targetBpt);
        if (targetDelta < valueInConvertedToTarget.mulDivDown(balancerSlippage, 1e4))
            revert BalancerPoolAdaptor___Slippage();
    }

    /**
     * @notice Allows strategists to exit Balancer pools using any exit.
     * @dev The amounts in `swapsAfterExit` are overwritten by the actual amount out received from the swap.
     * @dev `swapsAfterExit` MUST match up with expected token array returned from `_getPoolTokensWithNoPremintedBpt`.
     *      IE if the first token in expected token array is BB A DAI, the first swap in `swapsBeforeJoin` MUST be to
     *      swap BB A DAI.
     * @dev Max Available logic IS NOT supported.
     */
    function exitPool(
        ERC20 targetBpt,
        IVault.SingleSwap[] memory swapsAfterExit,
        SwapData memory swapData,
        IVault.ExitPoolRequest memory request
    ) external {
        bytes32 poolId = IBasePool(address(targetBpt)).getPoolId();

        // Figure out expected tokens out.
        (IERC20[] memory poolTokens, , ) = vault.getPoolTokens(poolId);
        ERC20[] memory expectedTokensOut = _getPoolTokensWithNoPremintedBpt(address(targetBpt), poolTokens);
        if (swapsAfterExit.length != expectedTokensOut.length) revert BalancerPoolAdaptor___LengthMismatch();

        // Ensure toInternalBalance is false.
        if (request.toInternalBalance) revert BalancerPoolAdaptor___InternalBalancesNotSupported();

        // Figure out the ERC20 balance changes, and the BPT balance change from calling `exitPool`.
        uint256[] memory tokensOutDelta = new uint256[](expectedTokensOut.length);
        for (uint256 i; i < expectedTokensOut.length; ++i)
            tokensOutDelta[i] = expectedTokensOut[i].balanceOf(address(this));

        uint256 targetDelta = targetBpt.balanceOf(address(this));
        vault.exitPool(poolId, address(this), payable(address(this)), request);
        targetDelta = targetDelta - targetBpt.balanceOf(address(this));
        for (uint256 i; i < expectedTokensOut.length; ++i)
            tokensOutDelta[i] = expectedTokensOut[i].balanceOf(address(this)) - tokensOutDelta[i];

        PriceRouter priceRouter = Cellar(address(this)).priceRouter();
        for (uint256 i; i < expectedTokensOut.length; ++i) {
            // If we didn't receive any of this token, continue.
            if (tokensOutDelta[i] == 0) continue;

            // Make sure swap assetIn is the expectedTokensOut.
            if (address(swapsAfterExit[i].assetIn) != address(expectedTokensOut[i]))
                revert BalancerPoolAdaptor___SwapTokenAndExpectedTokenMismatch();

            if (address(swapsAfterExit[i].assetOut) != address(0)) {
                expectedTokensOut[i].safeApprove(address(vault), tokensOutDelta[i]);

                // Perform a swap then update expected token, and tokensOutDelta.
                IVault.FundManagement memory fundManagement = IVault.FundManagement({
                    sender: address(this),
                    fromInternalBalance: false,
                    recipient: payable(address(this)),
                    toInternalBalance: false
                });

                // Update swap amount to be what we got out from exit.
                swapsAfterExit[i].amount = tokensOutDelta[i];

                // Make sure swap kind is GIVEN_IN.
                if (swapsAfterExit[i].kind != IVault.SwapKind.GIVEN_IN) revert BalancerPoolAdaptor___WrongSwapKind();

                // Perform the swap. Save amount out as the new tokensOutDelta[i].
                tokensOutDelta[i] = vault.swap(
                    swapsAfterExit[i],
                    fundManagement,
                    swapData.minAmountsForSwaps[i],
                    swapData.swapDeadlines[i]
                );

                // Then revoke approval
                _revokeExternalApproval(expectedTokensOut[i], address(vault));

                // Update expected token out to be the assetOut of the swap.
                expectedTokensOut[i] = ERC20(address(swapsAfterExit[i].assetOut));
            } else if (!priceRouter.isSupported(expectedTokensOut[i])) {
                // We received some of expectedTokensOut, but no swap was provided for it, and we can not price
                // this asset so revert.
                revert BalancerPoolAdaptor___UnsupportedTokenNotSwapped();
            }
        }

        // Compare value in vs value out, and revert if slippage is too high.
        uint256 valueOutConvertedToTarget = priceRouter.getValues(expectedTokensOut, tokensOutDelta, targetBpt);
        if (valueOutConvertedToTarget < targetDelta.mulDivDown(balancerSlippage, 1e4))
            revert BalancerPoolAdaptor___Slippage();
    }

    /**
     * @notice stake (deposit) BPTs into respective pool gauge
     * @param _bpt address of BPTs to stake
     * @param _amountIn number of BPTs to stake
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     */
    function stakeBPT(ERC20 _bpt, address _liquidityGauge, uint256 _amountIn) external {
        _validateBptAndGauge(address(_bpt), _liquidityGauge);
        uint256 amountIn = _maxAvailable(_bpt, _amountIn);
        ILiquidityGaugev3Custom liquidityGauge = ILiquidityGaugev3Custom(_liquidityGauge);
        _bpt.approve(_liquidityGauge, amountIn);
        liquidityGauge.deposit(amountIn, address(this));
        _revokeExternalApproval(_bpt, _liquidityGauge);
    }

    /**
     * @notice unstake (withdraw) BPT from respective pool gauge
     * @param _bpt address of BPTs to unstake
     * @param _amountOut number of BPTs to unstake
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     */
    function unstakeBPT(ERC20 _bpt, address _liquidityGauge, uint256 _amountOut) public {
        _validateBptAndGauge(address(_bpt), _liquidityGauge);
        ILiquidityGaugev3Custom liquidityGauge = ILiquidityGaugev3Custom(_liquidityGauge);
        _amountOut = _maxAvailable(ERC20(_liquidityGauge), _amountOut);
        liquidityGauge.withdraw(_amountOut);
    }

    /**
     * @notice claim rewards ($BAL) from LP position
     * @dev rewards are only accrued for staked positions
     */
    function claimRewards(address gauge) public {
        minter.mint(gauge);
    }

    /**
     * @notice Start a flash loan using Balancer.
     */
    function makeFlashLoan(IERC20[] memory tokens, uint256[] memory amounts, bytes memory data) public {
        vault.flashLoan(IFlashLoanRecipient(address(this)), tokens, amounts, data);
    }

    //============================================ Helper Functions ===========================================

    /**
     * @notice Validates that a given bpt and liquidityGauge is set up as a position in the Cellar
     * @dev This function uses `address(this)` as the address of the Cellar
     * @param _bpt of interest
     * @param _liquidityGauge corresponding to _bpt
     * NOTE: _liquidityGauge can be zeroAddress in cases where Cellar doesn't want to stake or there are no gauges yet available for respective bpt
     */
    function _validateBptAndGauge(address _bpt, address _liquidityGauge) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_bpt, _liquidityGauge)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert BalancerPoolAdaptor__BptAndGaugeComboMustBeTracked(_bpt, _liquidityGauge);
    }

    /**
     * @notice Returns a BPT's token array with any pre-minted BPT removed, but the order preserved.
     */
    function _getPoolTokensWithNoPremintedBpt(
        address bpt,
        IERC20[] memory poolTokens
    ) internal pure returns (ERC20[] memory tokens) {
        uint256 poolTokensLength = poolTokens.length;
        bool removePremintedBpts;
        // Iterate through, and check if we need to remove pre-minted bpts.
        for (uint256 i; i < poolTokensLength; ++i) {
            if (address(poolTokens[i]) == bpt) {
                removePremintedBpts = true;
                break;
            }
        }
        if (removePremintedBpts) {
            tokens = new ERC20[](poolTokensLength - 1);
            uint256 tokensIndex;
            for (uint256 i; i < poolTokensLength; ++i) {
                if (address(poolTokens[i]) != bpt) {
                    tokens[tokensIndex] = ERC20(address(poolTokens[i]));
                    tokensIndex++;
                }
            }
        } else {
            tokens = new ERC20[](poolTokensLength);
            for (uint256 i; i < poolTokensLength; ++i) tokens[i] = ERC20(address(poolTokens[i]));
        }
    }

    /**
     * @notice Returns the expected tokens array for a given `targetBpt`.
     * @dev This function is NOT used by the adaptor, but could be used by strategists
     *      when formulating Balancer rebalances.
     */
    function getExpectedTokens(address targetBpt) external view returns (ERC20[] memory expectedTokens) {
        bytes32 poolId = IBasePool(address(targetBpt)).getPoolId();
        (IERC20[] memory poolTokens, , ) = vault.getPoolTokens(poolId);
        return _getPoolTokensWithNoPremintedBpt(address(targetBpt), poolTokens);
    }
}
