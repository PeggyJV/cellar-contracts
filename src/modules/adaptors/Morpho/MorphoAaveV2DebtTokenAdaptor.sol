// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, SwapRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IMorpho } from "src/interfaces/external/Morpho/IMorpho.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";

import { console } from "@forge-std/Test.sol"; //TODO remove

/**
 * @title Aave debtToken Adaptor
 * @notice Allows Cellars to interact with Aave debtToken positions.
 * @author crispymangoes
 */
contract MorphoAaveV2DebtTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address debtToken)
    // Where:
    // `debtToken` is the debt token address this adaptor is working with
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    /**
     @notice Attempted borrow would lower Cellar health factor too low.
     */
    error MorphoAaveV3DebtTokenAdaptor__HealthFactorTooLow();

    /**
     * @notice Strategist attempted to open an untracked Aave loan.
     * @param untrackedDebtPosition the address of the untracked loan
     */
    error MorphoAaveV3DebtTokenAdaptor__DebtPositionsMustBeTracked(address untrackedDebtPosition);

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Morpho Aave V2 debtToken Adaptor V 1.0"));
    }

    /**
     * @notice The Morpho Aave V3 contract on Ethereum Mainnet.
     */
    function morpho() internal pure returns (IMorpho) {
        return IMorpho(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);
    }

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    function HFMIN() internal pure returns (uint256) {
        return 1.05e18;
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This position is a debt position, and user withdraws are not allowed so
     *         this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellars balance of the positions debtToken.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        address debtToken = abi.decode(adaptorData, (address));
        return _balanceOfInUnderlying(debtToken, msg.sender);
    }

    /**
     * @notice Returns the positions debtToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IAaveToken debtToken = abi.decode(adaptorData, (IAaveToken));
        return ERC20(debtToken.UNDERLYING_ASSET_ADDRESS());
    }

    /**
     * @notice This adaptor reports values in terms of debt.
     */
    function isDebt() public pure override returns (bool) {
        return true;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to borrow assets from Aave.
     * @notice `debtTokenToBorrow` must be the debtToken, NOT the underlying ERC20.
     * @param debtToken the debtToken to borrow on Aave
     * @param amountToBorrow the amount of `debtTokenToBorrow` to borrow on Aave.
     */
    function borrowFromAaveV2Morpho(address debtToken, uint256 amountToBorrow) public {
        // Check that debt position is properly set up to be tracked in the Cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(debtToken)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert MorphoAaveV3DebtTokenAdaptor__DebtPositionsMustBeTracked(debtToken);

        // Borrow from morpho.
        morpho().borrow(debtToken, amountToBorrow);

        // TODO so morpho does not provide a liquidity data method so how do we do a HF check?
        // Check that health factor is above adaptor minimum.
        // uint256 healthFactor = _getUserHealthFactor(address(this));
        // console.log("Health Factor", healthFactor);
        // if (healthFactor < HFMIN()) revert MorphoAaveV3DebtTokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategists to repay loan debt on Aave.
     * @param debtToken the debtToken you want to repay.
     * @param amountToRepay the amount of `tokenToRepay` to repay with.
     */
    function repayAaveV2MorphoDebt(IAaveToken debtToken, uint256 amountToRepay) public {
        ERC20 underlying = ERC20(debtToken.UNDERLYING_ASSET_ADDRESS());
        if (amountToRepay == type(uint256).max) {
            uint256 availableUnderlying = underlying.balanceOf(address(this));
            uint256 debt = _balanceOfInUnderlying(address(debtToken), address(this));
            amountToRepay = availableUnderlying > debt ? debt : availableUnderlying;
        }
        underlying.safeApprove(address(morpho()), amountToRepay);
        morpho().repay(address(debtToken), amountToRepay);

        // Zero out approvals if necessary.
        _revokeExternalApproval(underlying, address(morpho()));
    }

    /**
     * @notice Code pulled directly from Morpho Position Manager.
     * https://etherscan.io/address/0x4592e45e0c5DbEe94a135720cCfF2e4353dAc6De#code
     */
    function _getUserHealthFactor(address user) internal view returns (uint256) {
        IMorpho.LiquidityData memory liquidityData = morpho().liquidityData(user);

        return
            liquidityData.debt > 0
                ? uint256(1e18).mulDivDown(liquidityData.maxDebt, liquidityData.debt)
                : type(uint256).max;
    }

    function _balanceOfInUnderlying(address poolToken, address user) internal view returns (uint256) {
        (uint256 inP2P, uint256 onPool) = morpho().borrowBalanceInOf(poolToken, user);

        uint256 balanceInUnderlying;
        if (inP2P > 0) balanceInUnderlying = inP2P.mulDivDown(morpho().p2pBorrowIndex(poolToken), 1e27);
        if (onPool > 0) balanceInUnderlying += onPool.mulDivDown(morpho().poolIndexes(poolToken).poolBorrowIndex, 1e27);
        return balanceInUnderlying;
    }
}
