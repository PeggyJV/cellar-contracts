// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IMorphoV3 } from "src/interfaces/external/Morpho/IMorphoV3.sol";
import { MorphoAaveV3HealthFactorLogic } from "src/modules/adaptors/Morpho/MorphoAaveV3HealthFactorLogic.sol";

/**
 * @title Morpho Aave V3 debtToken Adaptor
 * @notice Allows Cellars to interact with Morpho Aave V3 debtToken positions.
 * @author crispymangoes
 */
contract MorphoAaveV3DebtTokenAdaptor is BaseAdaptor, MorphoAaveV3HealthFactorLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address underlying)
    // Where:
    // `underlying` is the underlying token address this adaptor is working with
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    /**
     @notice Attempted borrow would lower Cellar health factor too low.
     */
    error MorphoAaveV3DebtTokenAdaptor__HealthFactorTooLow();

    /**
     * @notice Strategist attempted to open an untracked Morpho loan.
     * @param untrackedDebtPosition the address of the untracked loan
     */
    error MorphoAaveV3DebtTokenAdaptor__DebtPositionsMustBeTracked(address untrackedDebtPosition);

    /**
     * @notice The Morpho Aave V3 contract on current network.
     * @notice For mainnet use 0x33333aea097c193e66081E930c33020272b33333.
     */
    IMorphoV3 public immutable morpho;

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(address _morpho, uint256 minHealthFactor) {
        _verifyConstructorMinimumHealthFactor(minHealthFactor);
        morpho = IMorphoV3(_morpho);
        minimumHealthFactor = minHealthFactor;
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Morpho Aave V3 debtToken Adaptor V 1.1"));
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
     * @notice Returns the cellars balance of the positions debt.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        address underlying = abi.decode(adaptorData, (address));
        return morpho.borrowBalance(underlying, msg.sender);
    }

    /**
     * @notice Returns the positions underlying asset.
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 underlying = abi.decode(adaptorData, (ERC20));
        return underlying;
    }

    /**
     * @notice This adaptor reports values in terms of debt.
     */
    function isDebt() public pure override returns (bool) {
        return true;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to borrow assets from Morpho.
     * @notice `debtTokenToBorrow` must be the debtToken, NOT the underlying ERC20.
     * @param underlying the debtToken to borrow on Morpho
     * @param amountToBorrow the amount of `debtTokenToBorrow` to borrow on Morpho.
     */
    function borrowFromAaveV3Morpho(address underlying, uint256 amountToBorrow, uint256 maxIterations) public {
        // Check that debt position is properly set up to be tracked in the Cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(underlying)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert MorphoAaveV3DebtTokenAdaptor__DebtPositionsMustBeTracked(underlying);

        // Borrow from morpho.
        morpho.borrow(underlying, amountToBorrow, address(this), address(this), maxIterations);

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = _getUserHealthFactor(morpho, address(this));
        if (healthFactor < minimumHealthFactor) revert MorphoAaveV3DebtTokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategists to repay loan debt on Morpho.
     * @param tokenToRepay the underlying ERC20 token you want to repay, NOT the debtToken.
     * @param amountToRepay the amount of `tokenToRepay` to repay with.
     */
    function repayAaveV3MorphoDebt(ERC20 tokenToRepay, uint256 amountToRepay) public {
        tokenToRepay.safeApprove(address(morpho), amountToRepay);
        morpho.repay(address(tokenToRepay), amountToRepay, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(tokenToRepay, address(morpho));
    }
}
