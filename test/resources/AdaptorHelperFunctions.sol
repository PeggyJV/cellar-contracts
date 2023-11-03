// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

// Aave V2
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";

// Morpho Aave V2
import { MorphoAaveV2ATokenAdaptor, IMorphoV2 } from "src/modules/adaptors/Morpho/MorphoAaveV2ATokenAdaptor.sol";
import { MorphoAaveV2DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV2DebtTokenAdaptor.sol";

// Aave V3
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";

// Morpho Aave V3
import { MorphoAaveV3ATokenP2PAdaptor, IMorphoV3, BaseAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenP2PAdaptor.sol";
import { MorphoAaveV3ATokenCollateralAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenCollateralAdaptor.sol";
import { MorphoAaveV3DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3DebtTokenAdaptor.sol";

// Balancer
import { IVault, IAsset, IERC20 } from "@balancer/interfaces/contracts/vault/IVault.sol";
import { BalancerPoolAdaptor } from "src/modules/adaptors/Balancer/BalancerPoolAdaptor.sol";

// Compound
import { CTokenAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";

// FeesAndReserves
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";

// FraxLend
import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";

// Sommelier
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { LegacyCellarAdaptor } from "src/modules/adaptors/Sommelier/LegacyCellarAdaptor.sol";

// Maker
import { DSRAdaptor } from "src/modules/adaptors/Maker/DSRAdaptor.sol";

// Curve
import { CurveAdaptor, CurvePool } from "src/modules/Adaptors/Curve/CurveAdaptor.sol";

import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";

import { AuraERC4626Adaptor } from "src/modules/adaptors/Aura/AuraERC4626Adaptor.sol";

import { ERC4626Adaptor } from "src/modules/adaptors/ERC4626Adaptor.sol";
import { CollateralFTokenAdaptor } from "src/modules/adaptors/Frax/CollateralFTokenAdaptor.sol";

import { DebtFTokenAdaptor } from "src/modules/adaptors/Frax/DebtFTokenAdaptor.sol";

import { CollateralFTokenAdaptorV1 } from "src/modules/adaptors/Frax/CollateralFTokenAdaptorV1.sol";

import { DebtFTokenAdaptorV1 } from "src/modules/adaptors/Frax/DebtFTokenAdaptorV1.sol";

contract AdaptorHelperFunctions {
    // ========================================= General FUNCTIONS =========================================

    function _createBytesDataForSwapWithUniv3(
        ERC20 from,
        ERC20 to,
        uint24 poolFee,
        uint256 fromAmount
    ) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = poolFee;
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV3.selector, path, poolFees, fromAmount, 0);
    }

    function _createBytesDataForSwapWithUniv2(
        ERC20 from,
        ERC20 to,
        uint256 fromAmount
    ) internal pure returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = address(from);
        path[1] = address(to);
        return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV2.selector, path, fromAmount, 0);
    }

    // ========================================= Aave V2 FUNCTIONS =========================================

    function _createBytesDataToLendOnAaveV2(
        ERC20 tokenToLend,
        uint256 amountToLend
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToWithdrawFromAaveV2(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToBorrowFromAaveV2(
        ERC20 debtToken,
        uint256 amountToBorrow
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToRepayToAaveV2(
        ERC20 tokenToRepay,
        uint256 amountToRepay
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
    }

    function _createBytesDataToFlashLoanFromAaveV2(
        address[] memory loanToken,
        uint256[] memory loanAmount,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveDebtTokenAdaptor.flashLoan.selector, loanToken, loanAmount, params);
    }

    // ========================================= Morpho Aave V2 FUNCTIONS =========================================

    function _createBytesDataToLendToMorphoAaveV2(
        address aToken,
        uint256 amountToLend
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(MorphoAaveV2ATokenAdaptor.depositToAaveV2Morpho.selector, aToken, amountToLend);
    }

    function _createBytesDataToWithdrawFromMorphoAaveV2(
        address aToken,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2ATokenAdaptor.withdrawFromAaveV2Morpho.selector,
                aToken,
                amountToWithdraw
            );
    }

    function _createBytesDataToBorrowFromMorphoAaveV2(
        address debtToken,
        uint256 amountToBorrow
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2DebtTokenAdaptor.borrowFromAaveV2Morpho.selector,
                debtToken,
                amountToBorrow
            );
    }

    function _createBytesDataToRepayToMorphoAaveV2(
        address debtToken,
        uint256 amountToRepay
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2DebtTokenAdaptor.repayAaveV2MorphoDebt.selector,
                debtToken,
                amountToRepay
            );
    }

    // ========================================= Aave V3 FUNCTIONS =========================================

    function _createBytesDataToLendOnAaveV3(
        ERC20 tokenToLend,
        uint256 amountToLend
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.depositToAave.selector, tokenToLend, amountToLend);
    }

    function _createBytesDataToChangeEModeOnAaveV3(uint8 category) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.changeEMode.selector, category);
    }

    function _createBytesDataToWithdrawFromAaveV3(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3ATokenAdaptor.withdrawFromAave.selector, tokenToWithdraw, amountToWithdraw);
    }

    function _createBytesDataToBorrowFromAaveV3(
        ERC20 debtToken,
        uint256 amountToBorrow
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.borrowFromAave.selector, debtToken, amountToBorrow);
    }

    function _createBytesDataToRepayToAaveV3(
        ERC20 tokenToRepay,
        uint256 amountToRepay
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.repayAaveDebt.selector, tokenToRepay, amountToRepay);
    }

    function _createBytesDataToFlashLoanFromAaveV3(
        address[] memory loanToken,
        uint256[] memory loanAmount,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AaveV3DebtTokenAdaptor.flashLoan.selector, loanToken, loanAmount, params);
    }

    // ========================================= Morpho Aave V2 FUNCTIONS =========================================

    function _createBytesDataToLendP2POnMorpoAaveV3(
        ERC20 tokenToLend,
        uint256 amountToLend,
        uint256 maxIterations
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3ATokenP2PAdaptor.depositToAaveV3Morpho.selector,
                tokenToLend,
                amountToLend,
                maxIterations
            );
    }

    function _createBytesDataToLendCollateralOnMorphoAaveV3(
        ERC20 tokenToLend,
        uint256 amountToLend
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3ATokenCollateralAdaptor.depositToAaveV3Morpho.selector,
                tokenToLend,
                amountToLend
            );
    }

    function _createBytesDataToWithdrawP2PFromMorphoAaveV3(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw,
        uint256 maxIterations
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3ATokenP2PAdaptor.withdrawFromAaveV3Morpho.selector,
                tokenToWithdraw,
                amountToWithdraw,
                maxIterations
            );
    }

    function _createBytesDataToWithdrawCollateralFromMorphoAaveV3(
        ERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3ATokenCollateralAdaptor.withdrawFromAaveV3Morpho.selector,
                tokenToWithdraw,
                amountToWithdraw
            );
    }

    function _createBytesDataToBorrowFromMorphoAaveV3(
        ERC20 debtToken,
        uint256 amountToBorrow,
        uint256 maxIterations
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3DebtTokenAdaptor.borrowFromAaveV3Morpho.selector,
                debtToken,
                amountToBorrow,
                maxIterations
            );
    }

    function _createBytesDataToRepayToMorphoAaveV3(
        ERC20 tokenToRepay,
        uint256 amountToRepay
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3DebtTokenAdaptor.repayAaveV3MorphoDebt.selector,
                tokenToRepay,
                amountToRepay
            );
    }

    // ========================================= Balancer FUNCTIONS =========================================

    /**
     * @notice create data for staking using BalancerPoolAdaptor
     */
    function _createBytesDataToStakeBpts(
        address _bpt,
        address _liquidityGauge,
        uint256 _amountIn
    ) public pure returns (bytes memory) {
        return abi.encodeWithSelector(BalancerPoolAdaptor.stakeBPT.selector, _bpt, _liquidityGauge, _amountIn);
    }

    /**
     * @notice create data for staking using BalancerPoolAdaptor
     */
    function _createBytesDataToMakeFlashLoanFromBalancer(
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory data
    ) public pure returns (bytes memory) {
        return abi.encodeWithSelector(BalancerPoolAdaptor.makeFlashLoan.selector, tokens, amounts, data);
    }

    /**
     * @notice create data for unstaking using BalancerPoolAdaptor
     */
    function _createBytesDataToUnstakeBpts(
        address _bpt,
        address _liquidityGauge,
        uint256 _amountOut
    ) public pure returns (bytes memory) {
        return abi.encodeWithSelector(BalancerPoolAdaptor.unstakeBPT.selector, _bpt, _liquidityGauge, _amountOut);
    }

    function _createBytesDataToClaimBalancerRewards(address _liquidityGauge) public pure returns (bytes memory) {
        return abi.encodeWithSelector(BalancerPoolAdaptor.claimRewards.selector, _liquidityGauge);
    }

    function _createBytesDataToJoinBalancerPool(
        ERC20 targetBpt,
        IVault.SingleSwap[] memory swapsBeforeJoin,
        BalancerPoolAdaptor.SwapData memory swapData,
        uint256 minimumBpt
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                BalancerPoolAdaptor.joinPool.selector,
                targetBpt,
                swapsBeforeJoin,
                swapData,
                minimumBpt
            );
    }

    function _createBytesDataToExitBalancerPool(
        ERC20 targetBpt,
        IVault.SingleSwap[] memory swapsAfterExit,
        BalancerPoolAdaptor.SwapData memory swapData,
        IVault.ExitPoolRequest memory request
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSelector(BalancerPoolAdaptor.exitPool.selector, targetBpt, swapsAfterExit, swapData, request);
    }

    // ========================================= Compound V2 FUNCTIONS =========================================

    function _createBytesDataToLendOnComnpoundV2(
        CErc20 market,
        uint256 amountToLend
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.depositToCompound.selector, market, amountToLend);
    }

    function _createBytesDataToWithdrawFromCompoundV2(
        CErc20 market,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.withdrawFromCompound.selector, market, amountToWithdraw);
    }

    // ========================================= Fees And Reserves FUNCTIONS =========================================

    // Make sure that if a strategists makes a huge deposit before calling log fees, it doesn't affect fee pay out
    function _createBytesDataToSetupFeesAndReserves(
        uint32 targetAPR,
        uint32 performanceFee
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.setupMetaData.selector, targetAPR, performanceFee);
    }

    function _createBytesDataToChangeUpkeepFrequency(uint64 newFrequency) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.changeUpkeepFrequency.selector, newFrequency);
    }

    function _createBytesDataToChangeUpkeepMaxGas(uint64 newMaxGas) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.changeUpkeepMaxGas.selector, newMaxGas);
    }

    function _createBytesDataToAddToReserves(uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.addAssetsToReserves.selector, amount);
    }

    function _createBytesDataToWithdrawFromReserves(uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.withdrawAssetsFromReserves.selector, amount);
    }

    function _createBytesDataToPrepareFees(uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.prepareFees.selector, amount);
    }

    function _createBytesDataToUpdateManagementFee(uint32 newFee) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FeesAndReservesAdaptor.updateManagementFee.selector, newFee);
    }

    // ========================================= FraxLend FUNCTIONS =========================================

    function _createBytesDataToLendOnFraxLend(
        address fToken,
        uint256 amountToDeposit
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.lendFrax.selector, fToken, amountToDeposit);
    }

    function _createBytesDataToRedeemFromFraxLend(
        address fToken,
        uint256 amountToRedeem
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.redeemFraxShare.selector, fToken, amountToRedeem);
    }

    function _createBytesDataToWithdrawFromFraxLend(
        address fToken,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.withdrawFrax.selector, fToken, amountToWithdraw);
    }

    function _createBytesDataToCallAddInterestOnFraxLend(address fToken) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.callAddInterest.selector, fToken);
    }

    // ========================================= AURA FUNCTIONS =========================================

    function _createBytesDataGetRewardsFromAuraPoolERC4626(
        address _auraPool,
        bool _claimExtras
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(AuraERC4626Adaptor.getRewards.selector, _auraPool, _claimExtras);
    }

    // ========================================= Sommelier FUNCTIONS =========================================

    function _createBytesDataToDepositToCellar(address cellar, uint256 assets) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CellarAdaptor.depositToCellar.selector, cellar, assets);
    }

    function _createBytesDataToWithdrawFromCellar(address cellar, uint256 assets) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CellarAdaptor.withdrawFromCellar.selector, cellar, assets);
    }

    function _createBytesDataToDepositToLegacyCellar(
        address cellar,
        uint256 assets,
        address oracle
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(LegacyCellarAdaptor.depositToCellar.selector, cellar, assets, oracle);
    }

    function _createBytesDataToWithdrawFromLegacyCellar(
        address cellar,
        uint256 assets,
        address oracle
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(LegacyCellarAdaptor.withdrawFromCellar.selector, cellar, assets, oracle);
    }

    function _createBytesDataToDepositToERC4626Vault(
        address vault,
        uint256 assets
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(ERC4626Adaptor.depositToVault.selector, vault, assets);
    }

    // ========================================= FraxLendV2 COLLATERAL FUNCTIONS =========================================

    function _createBytesDataToAddCollateralWithFraxlendV2(
        address _fraxlendPair,
        uint256 _collateralToDeposit
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(CollateralFTokenAdaptor.addCollateral.selector, _fraxlendPair, _collateralToDeposit);
    }

    function _createBytesDataToRemoveCollateralWithFraxlendV2(
        uint256 _collateralAmount,
        IFToken _fraxlendPair
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(CollateralFTokenAdaptor.removeCollateral.selector, _collateralAmount, _fraxlendPair);
    }

    // ========================================= FraxLendV2 DEBT FUNCTIONS =========================================

    function _createBytesDataToBorrowWithFraxlendV2(
        address _fraxlendPair,
        uint256 _amountToBorrow
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(DebtFTokenAdaptor.borrowFromFraxlend.selector, _fraxlendPair, _amountToBorrow);
    }

    function _createBytesDataToRepayWithFraxlendV2(
        IFToken _fraxlendPair,
        uint256 _debtTokenRepayAmount
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(DebtFTokenAdaptor.repayFraxlendDebt.selector, _fraxlendPair, _debtTokenRepayAmount);
    }

    function _createBytesDataToAddInterestWithFraxlendV2(IFToken fraxlendPair) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(DebtFTokenAdaptor.callAddInterest.selector, fraxlendPair);
    }

    // ========================================= FraxLendV1 COLLATERAL FUNCTIONS =========================================

    function _createBytesDataToAddCollateralWithFraxlendV1(
        address _fraxlendPair,
        uint256 _collateralToDeposit
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(CollateralFTokenAdaptor.addCollateral.selector, _fraxlendPair, _collateralToDeposit);
    }

    function _createBytesDataToRemoveCollateralWithFraxlendV1(
        uint256 _collateralAmount,
        IFToken _fraxlendPair
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(CollateralFTokenAdaptor.removeCollateral.selector, _collateralAmount, _fraxlendPair);
    }

    // ========================================= FraxLendV1 DEBT FUNCTIONS =========================================

    function _createBytesDataToBorrowWithFraxlendV1(
        address _fraxlendPair,
        uint256 _amountToBorrow
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(DebtFTokenAdaptor.borrowFromFraxlend.selector, _fraxlendPair, _amountToBorrow);
    }

    function _createBytesDataToRepayWithFraxlendV1(
        IFToken _fraxlendPair,
        uint256 _debtTokenRepayAmount
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(DebtFTokenAdaptor.repayFraxlendDebt.selector, _fraxlendPair, _debtTokenRepayAmount);
    }

    function _createBytesDataToAddInterestWithFraxlendV1(IFToken fraxlendPair) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(DebtFTokenAdaptor.callAddInterest.selector, fraxlendPair);
    }

    // ========================================= Maker FUNCTIONS =========================================

    function _createBytesDataToJoinDsr(uint256 assets) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(DSRAdaptor.join.selector, assets);
    }

    function _createBytesDataToExitDsr(uint256 assets) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(DSRAdaptor.exit.selector, assets);
    }

    function _createBytesDataToDrip() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(DSRAdaptor.drip.selector);
    }

    // ========================================= Curve FUNCTIONS =========================================

    function _createBytesDataToAddLiquidityToCurve(
        address pool,
        ERC20 token,
        ERC20[] memory tokens,
        uint256[] memory orderedTokenAmounts,
        uint256 minLPAmount
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                CurveAdaptor.addLiquidity.selector,
                pool,
                token,
                tokens,
                orderedTokenAmounts,
                minLPAmount
            );
    }

    function _createBytesDataToRemoveLiquidityFromCurve(
        address pool,
        ERC20 token,
        uint256 lpTokenAmount,
        ERC20[] memory tokens,
        uint256[] memory orderedTokenAmountsOut
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                CurveAdaptor.removeLiquidity.selector,
                pool,
                token,
                lpTokenAmount,
                tokens,
                orderedTokenAmountsOut
            );
    }

    function _createBytesDataToRemoveLiquidityFromCurveSingleCoin(
        address pool,
        ERC20 token,
        uint256 lpTokenAmount,
        uint256 i,
        uint256 minOut
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(CurveAdaptor.removeLiquidityOneCoin.selector, pool, token, lpTokenAmount, i, minOut);
    }
}
