// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math, Registry } from "src/modules/adaptors/BaseAdaptor.sol";
import { IWETH9 } from "src/interfaces/external/IWETH9.sol";
import { CurvePool } from "src/interfaces/external/Curve/CurvePool.sol";
import { CurveGauge } from "src/interfaces/external/Curve/CurveGauge.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Cellar } from "src/base/Cellar.sol";
import { CurveHelper } from "src/modules/adaptors/Curve/CurveHelper.sol";

/**
 * @title Curve Adaptor
 * @notice Allows Cellars to interact with Curve LP positions.
 * @author crispymangoes
 */
contract CurveAdaptor is BaseAdaptor, CurveHelper {
    using SafeTransferLib for ERC20;
    using Address for address;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address pool, address token, address gauge, bytes4 selector)
    // Where:
    // pool is the Curve Pool address
    // token is the Curve LP token address(can be the same as pool)
    // gauge is the Curve Gauge(can be zero address)
    // selector is the pool function to call when checking for re-entrancy during user deposit/withdraws(can be bytes4(0), but then withdraws and deposits are not supported).
    //================= Configuration Data Specification =================
    // isLiquid bool
    // Indicates whether the position is liquid or not.
    //====================================================================

    /**
     * @notice Attempted add/remove liquidity from Curve resulted in excess slippage.
     */
    error CurveAdaptor___Slippage();

    /**
     * @notice Much of the adaptor, and pricing logic relies on Curve sticking to using 18 decimals, but since that
     *         is not guaranteed when position is being trusted in registry, we verify 18 decimals is used.
     */
    error CurveAdaptor___NonStandardDecimals();

    /**
     * @notice Attempted to interact with a curve position that is not being used by the Cellar.
     * @param positionId the uint32 position id the Cellar needs to use
     */
    error CurveAdaptor__CurvePositionNotUsed(uint32 positionId);

    /**
     * @notice Attempted to use an invalid slippage in the structure.
     */
    error CurveAdaptor___InvalidConstructorSlippage();

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Curve Adaptor V 0.0"));
    }

    /**
     * @notice Store the adaptor address in bytecode, so that Cellars can use it during delegate call operations.
     */
    address payable public immutable adaptorAddress;

    /**
     * @notice Number between 0.9e4, and 1e4 representing the amount of slippage that can be
     *         tolerated when entering/exiting a pool.
     *         - 0.90e4: 10% slippage
     *         - 0.95e4: 5% slippage
     */
    uint32 public immutable curveSlippage;

    constructor(address _nativeWrapper, uint32 _curveSlippage) CurveHelper(_nativeWrapper) {
        if (_curveSlippage < 0.9e4 || _curveSlippage > 1e4) revert CurveAdaptor___InvalidConstructorSlippage();
        adaptorAddress = payable(address(this));
        curveSlippage = _curveSlippage;
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar already has possession of users Curve LP tokens by the time this function is called,
     *         so if gauge is zero address, do nothing.
     * @dev Check for reentrancy by calling a pool function that checks for reentrancy.
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        (CurvePool pool, ERC20 token, CurveGauge gauge, bytes4 selector) = abi.decode(
            adaptorData,
            (CurvePool, ERC20, CurveGauge, bytes4)
        );

        _verifyCurvePositionIsUsed(pool, token, gauge, selector);

        if (selector != bytes4(0)) _callReentrancyFunction(pool, selector);
        else revert BaseAdaptor__UserDepositsNotAllowed();

        if (address(gauge) != address(0)) {
            // Deposit into gauge.
            token.safeApprove(address(gauge), assets);
            gauge.deposit(assets, address(this));
            _revokeExternalApproval(token, address(gauge));
        }
    }

    /**
     * @notice Withdraws from Curve Gauge if tokens in Cellar are not enough to handle withdraw.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets amount of `token` to send to receiver
     * @param receiver address to send assets to
     * @param adaptorData data needed to withdraw from this position
     * @dev configurationData used to check if position is liquid
     * @dev Does not check that gauge address is non-zero, but if gauge is zero, then `withdrawableFrom` only reports
     *      the lpToken balance in the cellar, so assets will never be greater than `tokenBalance`.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory configurationData
    ) public override {
        _externalReceiverCheck(receiver);
        (CurvePool pool, ERC20 lpToken, CurveGauge gauge, bytes4 selector) = abi.decode(
            adaptorData,
            (CurvePool, ERC20, CurveGauge, bytes4)
        );

        _verifyCurvePositionIsUsed(pool, lpToken, gauge, selector);

        bool isLiquid = abi.decode(configurationData, (bool));

        if (isLiquid && selector != bytes4(0)) _callReentrancyFunction(pool, selector);
        else revert BaseAdaptor__UserWithdrawsNotAllowed();

        uint256 tokenBalance = lpToken.balanceOf(address(this));
        if (tokenBalance < assets) {
            // Pull from gauge.
            gauge.withdraw(assets - tokenBalance, false);
        }

        lpToken.safeTransfer(receiver, assets);
    }

    /**
     * @notice Identical to `balanceOf`
     * @dev Strategists can make the position illiquid using configuration data.
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory configurationData
    ) public view override returns (uint256) {
        (, ERC20 lpToken, CurveGauge gauge, bytes4 selector) = abi.decode(
            adaptorData,
            (CurvePool, ERC20, CurveGauge, bytes4)
        );
        bool isLiquid = abi.decode(configurationData, (bool));
        if (isLiquid && selector != bytes4(0)) {
            uint256 gaugeBalance = address(gauge) != address(0) ? gauge.balanceOf(msg.sender) : 0;
            return lpToken.balanceOf(msg.sender) + gaugeBalance;
        } else return 0;
    }

    /**
     * @notice Returns the balance of Curve LP token.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256 balance) {
        (, ERC20 lpToken, CurveGauge gauge) = abi.decode(adaptorData, (CurvePool, ERC20, CurveGauge));
        uint256 gaugeBalance = address(gauge) != address(0) ? gauge.balanceOf(msg.sender) : 0;
        balance = lpToken.balanceOf(msg.sender) + gaugeBalance;

        if (balance > 0) {
            // Run check to make sure Cellar uses an oracle.
            _ensureCallerUsesOracle(msg.sender);
        }
    }

    /**
     * @notice Returns Curve LP token
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        (, ERC20 lpToken) = abi.decode(adaptorData, (CurvePool, ERC20));
        return lpToken;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    /**
     * @notice This function is called when the position is being set up in the registry, functionally `assetsUsed` is the same as in the `BaseAdaptor`,
     *         but since this is called while trusting the position, we also validate decimals are 18.
     */
    function assetsUsed(bytes memory adaptorData) public view override returns (ERC20[] memory assets) {
        // Make sure token, and gauge have 18 decimals.
        (, ERC20 lpToken, CurveGauge gauge) = abi.decode(adaptorData, (CurvePool, ERC20, CurveGauge));
        if (lpToken.decimals() != 18 || (address(gauge) != address(0) && gauge.decimals() != 18))
            revert CurveAdaptor___NonStandardDecimals();
        return super.assetsUsed(adaptorData);
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategist to add liquidity to Curve pairs that do NOT use the native asset.
     * @param pool the curve pool address
     * @param lpToken the curve pool token
     * @param orderedUnderlyingTokenAmounts array of token amounts, in order of `pool.coins`
     * @param minLPAmount the minimum amount of LP out
     */
    function addLiquidity(
        address pool,
        ERC20 lpToken,
        uint256[] memory orderedUnderlyingTokenAmounts,
        uint256 minLPAmount,
        CurveGauge gauge,
        bytes4 selector
    ) external {
        _verifyCurvePositionIsUsed(CurvePool(pool), lpToken, gauge, selector);

        // Internal function also validates array lengths are the same.
        ERC20[] memory underlyingTokens = _getPoolUnderlyingTokens(
            CurvePool(pool),
            orderedUnderlyingTokenAmounts.length
        );

        // Approve pool to spend amounts, and check for max available.
        for (uint256 i; i < underlyingTokens.length; ++i) {
            if (orderedUnderlyingTokenAmounts[i] > 0) {
                orderedUnderlyingTokenAmounts[i] = _maxAvailable(underlyingTokens[i], orderedUnderlyingTokenAmounts[i]);
                underlyingTokens[i].safeApprove(pool, orderedUnderlyingTokenAmounts[i]);
            }
        }

        // Generate `add_liquidity` function call data.
        bytes memory data = _curveAddLiquidityEncodedCallData(orderedUnderlyingTokenAmounts, minLPAmount, false);

        // Track the change in lpToken balance.
        uint256 balanceDelta = lpToken.balanceOf(address(this));

        pool.functionCall(data);

        balanceDelta = lpToken.balanceOf(address(this)) - balanceDelta;

        // Compare value out vs value in, and check for slippage.
        uint256 lpValueIn = Cellar(address(this)).priceRouter().getValues(
            underlyingTokens,
            orderedUnderlyingTokenAmounts,
            lpToken
        );
        uint256 minValueOut = lpValueIn.mulDivDown(curveSlippage, 1e4);
        if (balanceDelta < minValueOut) revert CurveAdaptor___Slippage();

        // Revoke any unused approvals.
        for (uint256 i; i < underlyingTokens.length; ++i)
            if (orderedUnderlyingTokenAmounts[i] > 0) _revokeExternalApproval(underlyingTokens[i], pool);
    }

    /**
     * @notice Allows strategist to add liquidity to Curve pairs that use the native asset.
     * @param pool the curve pool address
     * @param lpToken the curve pool token
     * @param orderedUnderlyingTokenAmounts array of token amounts, in order of `pool.coins`
     * @param minLPAmount the minimum amount of LP out
     * @param useUnderlying bool indicating whether or not to add a true bool to the end of abi.encoded `addLiquidity` call
     */
    function addLiquidityETH(
        address pool,
        ERC20 lpToken,
        uint256[] memory orderedUnderlyingTokenAmounts,
        uint256 minLPAmount,
        bool useUnderlying,
        CurveGauge gauge,
        bytes4 selector
    ) external {
        _verifyCurvePositionIsUsed(CurvePool(pool), lpToken, gauge, selector);

        // Internal function also validates array lengths are the same.
        ERC20[] memory underlyingTokens = _getPoolUnderlyingTokens(
            CurvePool(pool),
            orderedUnderlyingTokenAmounts.length
        );

        // Approve adaptor to spend amounts
        for (uint256 i; i < underlyingTokens.length; ++i) {
            if (address(underlyingTokens[i]) == CURVE_ETH) {
                // If token is CURVE_ETH, then approve adaptor to spend native wrapper.
                orderedUnderlyingTokenAmounts[i] = _maxAvailable(
                    ERC20(nativeWrapper),
                    orderedUnderlyingTokenAmounts[i]
                );
                ERC20(nativeWrapper).safeApprove(adaptorAddress, orderedUnderlyingTokenAmounts[i]);
            } else {
                orderedUnderlyingTokenAmounts[i] = _maxAvailable(underlyingTokens[i], orderedUnderlyingTokenAmounts[i]);
                underlyingTokens[i].safeApprove(adaptorAddress, orderedUnderlyingTokenAmounts[i]);
            }
        }

        // Make normal function call to this adaptor to handle native ETH interactions.
        uint256 lpOut = CurveHelper(adaptorAddress).addLiquidityETHViaProxy(
            pool,
            lpToken,
            underlyingTokens,
            orderedUnderlyingTokenAmounts,
            minLPAmount,
            useUnderlying
        );

        // Compare value out vs value in, and check for slippage.
        for (uint256 i; i < underlyingTokens.length; ++i) {
            if (address(underlyingTokens[i]) == CURVE_ETH) underlyingTokens[i] = ERC20(nativeWrapper);
        }
        uint256 lpValueIn = Cellar(address(this)).priceRouter().getValues(
            underlyingTokens,
            orderedUnderlyingTokenAmounts,
            lpToken
        );
        uint256 minValueOut = lpValueIn.mulDivDown(curveSlippage, 1e4);
        if (lpOut < minValueOut) revert CurveAdaptor___Slippage();

        // Revoke any unused approvals.
        for (uint256 i; i < underlyingTokens.length; ++i) {
            if (address(underlyingTokens[i]) == CURVE_ETH)
                _revokeExternalApproval(ERC20(nativeWrapper), adaptorAddress);
            else _revokeExternalApproval(underlyingTokens[i], adaptorAddress);
        }
    }

    /**
     * @notice Allows strategist to remove liquidity from Curve pairs that do NOT use the native asset.
     * @param pool the curve pool address
     * @param lpToken the curve pool token
     * @param lpTokenAmount the amount of LP token
     * @param orderedMinimumUnderlyingTokenAmountsOut array of minimum token amounts out, in order of `pool.coins`
     */
    function removeLiquidity(
        address pool,
        ERC20 lpToken,
        uint256 lpTokenAmount,
        uint256[] memory orderedMinimumUnderlyingTokenAmountsOut,
        CurveGauge gauge,
        bytes4 selector
    ) external {
        _verifyCurvePositionIsUsed(CurvePool(pool), lpToken, gauge, selector);

        // Internal function also validates array lengths are the same.
        ERC20[] memory underlyingTokens = _getPoolUnderlyingTokens(
            CurvePool(pool),
            orderedMinimumUnderlyingTokenAmountsOut.length
        );

        lpTokenAmount = _maxAvailable(lpToken, lpTokenAmount);

        // Generate `remove_liquidity` function call data.
        bytes memory data = _curveRemoveLiquidityEncodedCalldata(
            lpTokenAmount,
            orderedMinimumUnderlyingTokenAmountsOut,
            false
        );

        // Track the changes in token balances.
        uint256[] memory balanceDelta = new uint256[](underlyingTokens.length);
        for (uint256 i; i < underlyingTokens.length; ++i)
            balanceDelta[i] = ERC20(underlyingTokens[i]).balanceOf(address(this));

        pool.functionCall(data);

        for (uint256 i; i < underlyingTokens.length; ++i) {
            balanceDelta[i] = ERC20(underlyingTokens[i]).balanceOf(address(this)) - balanceDelta[i];
        }

        // Compare value out vs value in, and check for slippage.
        uint256 lpValueOut = Cellar(address(this)).priceRouter().getValues(underlyingTokens, balanceDelta, lpToken);
        uint256 minValueOut = lpTokenAmount.mulDivDown(curveSlippage, 1e4);
        if (lpValueOut < minValueOut) revert CurveAdaptor___Slippage();
    }

    /**
     * @notice Allows strategist to remove liquidity from Curve pairs that use the native asset.
     * @param pool the curve pool address
     * @param lpToken the curve pool token
     * @param lpTokenAmount the amount of LP token
     * @param orderedMinimumUnderlyingTokenAmountsOut array of minimum token amounts out, in order of `pool.coins`
     * @param useUnderlying bool indicating whether or not to add a true bool to the end of abi.encoded `removeLiquidity` call
     */
    function removeLiquidityETH(
        address pool,
        ERC20 lpToken,
        uint256 lpTokenAmount,
        uint256[] memory orderedMinimumUnderlyingTokenAmountsOut,
        bool useUnderlying,
        CurveGauge gauge,
        bytes4 selector
    ) external {
        _verifyCurvePositionIsUsed(CurvePool(pool), lpToken, gauge, selector);

        // Internal function also validates array lengths are the same.
        ERC20[] memory underlyingTokens = _getPoolUnderlyingTokens(
            CurvePool(pool),
            orderedMinimumUnderlyingTokenAmountsOut.length
        );

        lpTokenAmount = _maxAvailable(lpToken, lpTokenAmount);

        lpToken.safeApprove(adaptorAddress, lpTokenAmount);

        // Make normal function call to this adaptor to handle native ETH interactions.
        uint256[] memory underlyingTokensOut = CurveHelper(adaptorAddress).removeLiquidityETHViaProxy(
            pool,
            lpToken,
            lpTokenAmount,
            underlyingTokens,
            orderedMinimumUnderlyingTokenAmountsOut,
            useUnderlying
        );

        // Compare value out vs value in, and check for slippage.
        for (uint256 i; i < underlyingTokens.length; ++i)
            if (address(underlyingTokens[i]) == CURVE_ETH) underlyingTokens[i] = ERC20(nativeWrapper);
        uint256 lpValueOut = Cellar(address(this)).priceRouter().getValues(
            underlyingTokens,
            underlyingTokensOut,
            lpToken
        );
        uint256 minValueOut = lpTokenAmount.mulDivDown(curveSlippage, 1e4);
        if (lpValueOut < minValueOut) revert CurveAdaptor___Slippage();

        // Revoke any unused approval.
        _revokeExternalApproval(lpToken, adaptorAddress);
    }

    /**
     * @notice Allows strategist to stake Curve LP tokens in their gauge.
     * @param lpToken the curve pool token
     * @param gauge the gauge for `lpToken`
     * @param amount the amount of `lpToken` to stake
     */
    function stakeInGauge(ERC20 lpToken, CurveGauge gauge, uint256 amount, CurvePool pool, bytes4 selector) external {
        _verifyCurvePositionIsUsed(pool, lpToken, gauge, selector);
        amount = _maxAvailable(lpToken, amount);
        lpToken.safeApprove(address(gauge), amount);
        gauge.deposit(amount, address(this));
        _revokeExternalApproval(lpToken, address(gauge));
    }

    /**
     * @notice Allows strategist to unstake Curve LP tokens from their gauge.
     * @param gauge the gauge for `lpToken`
     * @param amount the amount of `lpToken` to unstake
     */
    function unStakeFromGauge(CurveGauge gauge, uint256 amount) external {
        if (amount == type(uint256).max) amount = gauge.balanceOf(address(this));
        gauge.withdraw(amount);
    }

    /**
     * @notice Allows strategist to claim rewards from a gauge.
     * @param gauge the gauge for `lpToken`
     */
    function claimRewards(CurveGauge gauge) external {
        gauge.claim_rewards();
    }

    /**
     * @notice Reverts if a given curve position data is not set up as a position in the calling Cellar.
     * @dev This function is only used in a delegate call context, hence why address(this) is used
     *      to get the calling Cellar.
     */
    function _verifyCurvePositionIsUsed(CurvePool pool, ERC20 token, CurveGauge gauge, bytes4 selector) internal view {
        uint256 cellarCodeSize;
        address cellarAddress = address(this);
        assembly {
            cellarCodeSize := extcodesize(cellarAddress)
        }
        if (cellarCodeSize > 0) {
            bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(pool, token, gauge, selector)));
            Cellar cellar = Cellar(cellarAddress);
            Registry registry = cellar.registry();
            uint32 positionId = registry.getPositionHashToPositionId(positionHash);
            if (!cellar.isPositionUsed(positionId)) revert CurveAdaptor__CurvePositionNotUsed(positionId);
        }
        // else do nothing. The cellar is currently being deployed so it has no bytecode, and trying to call `cellar.registry()` will revert.
    }
}
