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
import { IBalancerStablePoolAdaptor } from "src/modules/adaptors/Balancer/IBalancerStablePoolAdaptor.sol";

/**
 * @title Balancer Stable Pool Adaptor
 * @notice Allows ERC4626 Vaults to interact with Stable and Boosted Stable Balancer Pools (BPs).
 * @author 0xEinCodes and CrispyMangoes
 * NOTE: IMPORTANT - THIS IS A WIP, WHERE MOST OF THE CODE HAS BEEN TAKEN FROM THE ACTUAL `BalancerPoolAdaptor.sol` THAT IS USED WITHIN THE SOMMELIER ARCHITECTURE. THERE ARE ASPECTS OF THE SOMMELIER ARCHITECTURE THAT ARE NOT NEEDED, THOUGH MAY BE INCLUDED TO HELP PROMPT OTHER YIELD AGGREGATORS TO PROPERLY ACCOUNT FOR `assetOf()` AND `totalAssets()`, ETC. FOR THE RESPECTIVE ERC 4626 VAULT'S POSITION USING THIS ADAPTOR. FOR NOW IT IS REMOVED TO SHOWCASE THE MAIN FUNCTIONS THAT INTERACT WITH THE BALANCER STABLE POOL AS PER `IBalancerStablePoolAdaptor.sol`
 * NOTE: Possibly do not need `BaseAdaptor.sol` inheritted but again, this is just a wip and can be assessed if the Balancer Grant is approved.
 * NOTE: Actual implementation mentioned, `BalancerPoolAdaptor.sol` can be found here: https://github.com/PeggyJV/cellar-contracts/blob/main/src/modules/adaptors/Balancer/BalancerPoolAdaptor.sol && tests here: https://github.com/PeggyJV/cellar-contracts/blob/main/test/testAdaptors/BalancerPoolAdaptor.t.sol
 */
contract BalancerStablePoolAdaptor is IBalancerStablePoolAdaptor, BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    /**
     * @notice Constructor param for slippage too high
     */
    error BalancerStablePoolAdaptor___InvalidConstructorSlippage();

    /**
     * @notice Tried using a bpt and/or liquidityGauge that is not setup as a position.
     */
    error BalancerStablePoolAdaptor__BptAndGaugeComboMustBeTracked(address bpt, address liquidityGauge);

    /**
     * @notice Attempted balancer pool joins, exits, staking, unstaking, etc. with bad slippage
     */
    error BalancerStablePoolAdaptor___Slippage();

    /**
     * @notice Provided swap array length differs from expected tokens array length.
     */
    error BalancerStablePoolAdaptor___LengthMismatch();

    /**
     * @notice Provided swap information with wrong swap kind.
     */
    error BalancerStablePoolAdaptor___WrongSwapKind();

    //============================================ Constructor ===========================================

    constructor(address _vault, address _minter, uint32 _balancerSlippage) {
        if (_balancerSlippage < 0.9e4 || _balancerSlippage > 1e4)
            revert BalancerStablePoolAdaptor___InvalidConstructorSlippage();
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
        return keccak256(abi.encode("Balancer Stable Pool Adaptor V 1.0"));
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to join Balancer pools using EXACT_TOKENS_IN_FOR_BPT_OUT joins.
     * @dev `swapsBeforeJoin` MUST match up with expected token array returned from `_getPoolTokensWithNoPremintedBpt`.
     *      IE if the first token in expected token array is DAI, the first swap in `swapsBeforeJoin` MUST be for DAI.
     * @dev Max Available logic IS supported.
     * TODO: Yield Aggregators must specify their own `PriceRouter` or pricing mechanism. More documentation can be provided with the grant on how the `PriceRouter` would function (basic function is accounting for example).
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
        if (swapsBeforeJoin.length != expectedTokensIn.length) revert BalancerStablePoolAdaptor___LengthMismatch();

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
                        revert BalancerStablePoolAdaptor___SwapTokenAndExpectedTokenMismatch();

                    // Make sure swap kind is GIVEN_IN.
                    if (swapsBeforeJoin[i].kind != IVault.SwapKind.GIVEN_IN)
                        revert BalancerStablePoolAdaptor___WrongSwapKind();

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
                        revert BalancerStablePoolAdaptor___SwapTokenAndExpectedTokenMismatch();
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
            revert BalancerStablePoolAdaptor___Slippage();
    }

    /**
     * @notice Allows strategists to exit Balancer pools using any exit.
     * @dev The amounts in `swapsAfterExit` are overwritten by the actual amount out received from the swap.
     * @dev `swapsAfterExit` MUST match up with expected token array returned from `_getPoolTokensWithNoPremintedBpt`.
     *      IE if the first token in expected token array is BB A DAI, the first swap in `swapsBeforeJoin` MUST be to
     *      swap BB A DAI.
     * @dev Max Available logic IS NOT supported.
     * TODO: Yield Aggregators must specify their own `PriceRouter` or pricing mechanism. More documentation can be provided with the grant on how the `PriceRouter` would function (basic function is accounting for example).
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
        if (swapsAfterExit.length != expectedTokensOut.length) revert BalancerStablePoolAdaptor___LengthMismatch();

        // Ensure toInternalBalance is false.
        if (request.toInternalBalance) revert BalancerStablePoolAdaptor___InternalBalancesNotSupported();

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
                revert BalancerStablePoolAdaptor___SwapTokenAndExpectedTokenMismatch();

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
                if (swapsAfterExit[i].kind != IVault.SwapKind.GIVEN_IN)
                    revert BalancerStablePoolAdaptor___WrongSwapKind();

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
                revert BalancerStablePoolAdaptor___UnsupportedTokenNotSwapped();
            }
        }

        // Compare value in vs value out, and revert if slippage is too high.
        uint256 valueOutConvertedToTarget = priceRouter.getValues(expectedTokensOut, tokensOutDelta, targetBpt);
        if (valueOutConvertedToTarget < targetDelta.mulDivDown(balancerSlippage, 1e4))
            revert BalancerStablePoolAdaptor___Slippage();
    }

    /**
     * @notice stake (deposit) BPTs into respective pool gauge
     * @param _bpt address of BPTs to stake
     * @param _amountIn number of BPTs to stake
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     * TODO: Yield Aggregators must specify their own `Registry` or whitelisting mechanism. More documentation can be provided with the grant on how the `Registry` would function (basic function is to gate for approved adaptors and ERC20 && gauge combos to use).
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
     * TODO: Yield Aggregators must specify their own `Registry` or whitelisting mechanism. More documentation can be provided with the grant on how the `Registry` would function (basic function is to gate for approved adaptors and ERC20 && gauge combos to use).
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
            revert BalancerStablePoolAdaptor__BptAndGaugeComboMustBeTracked(_bpt, _liquidityGauge);
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
