// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IMorphoV2 } from "src/interfaces/external/Morpho/IMorphoV2.sol";
import { IMorphoLensV2 } from "src/interfaces/external/Morpho/IMorphoLensV2.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";

/**
 * @title Morpho Aave V2 debtToken Adaptor
 * @notice Allows Cellars to interact with Morpho Aave V2 debtToken positions.
 * @author crispymangoes
 */
contract MorphoAaveV2DebtTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address aToken)
    // Where:
    // `aToken` is the Aave V2 pool token address this adaptor is borrowing.
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    /**
     * @notice Strategist attempted to open an untracked Morpho loan.
     * @param untrackedDebtPosition the address of the untracked loan
     */
    error MorphoAaveV2DebtTokenAdaptor__DebtPositionsMustBeTracked(address untrackedDebtPosition);

    /**
     @notice Attempted borrow would lower Cellar health factor too low.
     */
    error MorphoAaveV2DebtTokenAdaptor__HealthFactorTooLow();

    /**
     * @notice The Morpho Aave V2 contract on current network.
     * @notice For mainnet use 0x777777c9898D384F785Ee44Acfe945efDFf5f3E0.
     */
    IMorphoV2 public immutable morpho;

    /**
     * @notice The Morpho Aave V2 Lens contract on current network.
     * @notice For mainnet use 0x507fA343d0A90786d86C7cd885f5C49263A91FF4.
     */
    IMorphoLensV2 public immutable morphoLens;

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(address _morpho, address _morphoLens, uint256 minHealthFactor) {
        _verifyConstructorMinimumHealthFactor(minHealthFactor);
        morpho = IMorphoV2(_morpho);
        morphoLens = IMorphoLensV2(_morphoLens);
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
        return keccak256(abi.encode("Morpho Aave V2 debtToken Adaptor V 1.1"));
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
        address aToken = abi.decode(adaptorData, (address));
        return _balanceOfInUnderlying(aToken, msg.sender);
    }

    /**
     * @notice Returns the positions aToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IAaveToken aToken = abi.decode(adaptorData, (IAaveToken));
        return ERC20(aToken.UNDERLYING_ASSET_ADDRESS());
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
     * @notice `aToken` must be the aToken not the debtToken.
     * @param aToken the aToken to borrow on Aave
     * @param amountToBorrow the amount of `aTokenToBorrow` to borrow on Morpho.
     */
    function borrowFromAaveV2Morpho(address aToken, uint256 amountToBorrow) public {
        // Check that debt position is properly set up to be tracked in the Cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(aToken)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert MorphoAaveV2DebtTokenAdaptor__DebtPositionsMustBeTracked(aToken);

        // Borrow from morpho.
        morpho.borrow(aToken, amountToBorrow);

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = morphoLens.getUserHealthFactor(address(this));
        if (healthFactor < minimumHealthFactor) revert MorphoAaveV2DebtTokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategists to repay loan debt on Aave.
     * @param aToken the aToken you want to repay.
     * @param amountToRepay the amount of `tokenToRepay` to repay with.
     */
    function repayAaveV2MorphoDebt(IAaveToken aToken, uint256 amountToRepay) public {
        ERC20 underlying = ERC20(aToken.UNDERLYING_ASSET_ADDRESS());
        underlying.safeApprove(address(morpho), amountToRepay);
        morpho.repay(address(aToken), amountToRepay);

        // Zero out approvals if necessary.
        _revokeExternalApproval(underlying, address(morpho));
    }

    /**
     * @notice Returns the balance in underlying of debt owed.
     * @param poolToken the Aave V2 a Token user has debt in
     * @param user the address of the user to query their debt balance of.
     */
    function _balanceOfInUnderlying(address poolToken, address user) internal view returns (uint256) {
        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(poolToken, user);

        uint256 balanceInUnderlying;
        if (inP2P > 0) balanceInUnderlying = inP2P.mulDivDown(morpho.p2pBorrowIndex(poolToken), 1e27);
        if (onPool > 0) balanceInUnderlying += onPool.mulDivDown(morpho.poolIndexes(poolToken).poolBorrowIndex, 1e27);
        return balanceInUnderlying;
    }
}
