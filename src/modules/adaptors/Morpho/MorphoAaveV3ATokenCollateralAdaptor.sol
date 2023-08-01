// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib } from "src/modules/adaptors/BaseAdaptor.sol";
import { IMorphoV3 } from "src/interfaces/external/Morpho/IMorphoV3.sol";
import { MorphoRewardHandler } from "src/modules/adaptors/Morpho/MorphoRewardHandler.sol";
import { MorphoAaveV3HealthFactorLogic } from "src/modules/adaptors/Morpho/MorphoAaveV3HealthFactorLogic.sol";

/**
 * @title Morpho Aave V3 aToken Adaptor
 * @notice Allows Cellars to interact with Morpho Aave V3 positions.
 * @author crispymangoes
 */
contract MorphoAaveV3ATokenCollateralAdaptor is BaseAdaptor, MorphoRewardHandler, MorphoAaveV3HealthFactorLogic {
    using SafeTransferLib for ERC20;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address underlying)
    // Where:
    // `underlying` is the ERC20 position this adaptor is working with
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     @notice Attempted withdraw would lower Cellar health factor too low.
     */
    error MorphoAaveV3ATokenCollateralAdaptor__HealthFactorTooLow();

    /**
     * @notice The Morpho Aave V3 contract on current network.
     * @notice For mainnet use 0x33333aea097c193e66081E930c33020272b33333.
     */
    IMorphoV3 public immutable morpho;

    /**
     * @notice Minimum Health Factor enforced after every aToken withdraw.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(
        address _morpho,
        uint256 minHealthFactor,
        address rewardDistributor
    ) MorphoRewardHandler(rewardDistributor) {
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
        return keccak256(abi.encode("Morpho Aave V3 aToken Collateral Adaptor V 1.2"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Morpho to spend its assets, then call supplyCollateral to lend its assets.
     * @param assets the amount of assets to lend on Morpho
     * @param adaptorData adaptor data containing the abi encoded ERC20 token
     * @dev configurationData is NOT used
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to Morpho.
        ERC20 underlying = abi.decode(adaptorData, (ERC20));
        underlying.safeApprove(address(morpho), assets);

        morpho.supplyCollateral(address(underlying), assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(underlying, address(morpho));
    }

    /**
     @notice Cellars must withdraw from Morpho, check if collateral is backing any loans
     *       and prevent withdraws if so.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Morpho
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containing the abi encoded aToken
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        // Make sure there are no active borrows.
        address[] memory borrows = morpho.userBorrows(address(this));
        if (borrows.length > 0) revert BaseAdaptor__UserWithdrawsNotAllowed();

        address underlying = abi.decode(adaptorData, (address));

        // Withdraw assets from Morpho.
        morpho.withdrawCollateral(underlying, assets, address(this), receiver);
    }

    /**
     * @notice Checks that cellar has no active borrows, and if so returns 0.
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        address[] memory borrows = morpho.userBorrows(msg.sender);
        if (borrows.length > 0) return 0;
        else {
            address underlying = abi.decode(adaptorData, (address));
            return morpho.collateralBalance(underlying, msg.sender);
        }
    }

    /**
     * @notice Returns the cellars balance of the position in terms of underlying asset.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        address underlying = abi.decode(adaptorData, (address));
        return morpho.collateralBalance(underlying, msg.sender);
    }

    /**
     * @notice Returns the positions underlying asset.
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 underlying = abi.decode(adaptorData, (ERC20));
        return underlying;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategists to lend assets on Morpho.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param tokenToDeposit the token to lend on Morpho
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Morpho.
     */
    function depositToAaveV3Morpho(ERC20 tokenToDeposit, uint256 amountToDeposit) public {
        amountToDeposit = _maxAvailable(tokenToDeposit, amountToDeposit);
        tokenToDeposit.safeApprove(address(morpho), amountToDeposit);
        morpho.supplyCollateral(address(tokenToDeposit), amountToDeposit, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(tokenToDeposit, address(morpho));
    }

    /**
     * @notice Allows strategists to withdraw assets from Morpho.
     * @param tokenToWithdraw the token to withdraw from Morpho.
     * @param amountToWithdraw the amount of `tokenToWithdraw` to withdraw from Morpho
     */
    function withdrawFromAaveV3Morpho(ERC20 tokenToWithdraw, uint256 amountToWithdraw) public {
        morpho.withdrawCollateral(address(tokenToWithdraw), amountToWithdraw, address(this), address(this));

        // Check that health factor is above adaptor minimum.
        uint256 healthFactor = _getUserHealthFactor(morpho, address(this));
        if (healthFactor < minimumHealthFactor) revert MorphoAaveV3ATokenCollateralAdaptor__HealthFactorTooLow();
    }
}
