// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IFToken } from "src/interfaces/external/Frax/IFToken.sol";

/**
 * @title Aave aToken Adaptor
 * @notice Allows Cellars to interact with Aave aToken positions.
 * @author crispymangoes
 */
contract FTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address fToken)
    // Where:
    // `fToken` is the fToken address position this adaptor is working with
    //================= Configuration Data Specification =================
    // configurationData = abi.encode(minimumHealthFactor uint256)
    // Where:
    // `minimumHealthFactor` dictates how much assets can be taken from this position
    // If zero:
    //      position returns ZERO for `withdrawableFrom`
    // else:
    //      position calculates `withdrawableFrom` based off minimum specified
    //      position reverts if a user withdraw lowers health factor below minimum
    //
    // **************************** IMPORTANT ****************************
    // Cellars with multiple aToken positions MUST only specify minimum
    // health factor on ONE of the positions. Failing to do so will result
    // in user withdraws temporarily being blocked.
    //====================================================================

    error FTokenAdaptor__FTokenPositionsMustBeTracked(address fToken);

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Aave fToken Adaptor V 0.0"));
    }

    /**
     * @notice The FRAX contract on Ethereum Mainnet.
     */
    function FRAX() internal pure returns (ERC20) {
        return ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Pool to spend its assets, then call deposit to lend its assets.
     * @param assets the amount of assets to lend on Aave
     * @param adaptorData adaptor data containining the abi encoded aToken
     * @dev configurationData is NOT used because this action will only increase the health factor
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to Frax Lend.
        IFToken fToken = abi.decode(adaptorData, (IFToken));
        FRAX().safeApprove(address(fToken), assets);
        fToken.deposit(assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(FRAX(), address(fToken));
    }

    /**
     @notice Cellars must withdraw from Aave, check if a minimum health factor is specified
     *       then transfer assets to receiver.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Aave
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containining the abi encoded aToken
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        // Withdraw assets from Frax.
        IFToken fToken = abi.decode(adaptorData, (IFToken));
        // Round down to benefit protocol.
        uint256 shares = fToken.toAssetShares(assets, false);
        fToken.redeem(shares, receiver, address(this));
    }

    /**
     * @notice Uses configurartion data minimum health factor to calculate withdrawable assets from Aave.
     * @dev Applies a `cushion` value to the health factor checks and calculation.
     *      The goal of this is to minimize scenarios where users are withdrawing a very small amount of
     *      assets from Aave. This function returns zero if
     *      -minimum health factor is NOT set.
     *      -the current health factor is less than the minimum health factor + 2x `cushion`
     *      Otherwise this function calculates the withdrawable amount using
     *      minimum health factor + `cushion` for its calcualtions.
     * @dev It is possible for the math below to lose a small amount of precision since it is only
     *      maintaining 18 decimals during the calculation, but this is desired since
     *      doing so lowers the withdrawable from amount which in turn raises the health factor.
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory
    ) public view override returns (uint256 withdrawableFrax) {
        IFToken fToken = abi.decode(adaptorData, (IFToken));
        (uint128 totalFraxSupplied, , uint128 totalFraxBorrowed, , ) = fToken.getPairAccounting();
        if (totalFraxBorrowed > totalFraxSupplied) return 0;
        uint256 liquidFrax = totalFraxSupplied - totalFraxBorrowed;
        uint256 fraxBalance = fToken.toAssetAmount(fToken.balanceOf(msg.sender), false);
        withdrawableFrax = fraxBalance > liquidFrax ? liquidFrax : fraxBalance;
    }

    /**
     * @notice Returns the cellars balance of the positions aToken.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        IFToken fToken = abi.decode(adaptorData, (IFToken));
        return fToken.toAssetAmount(fToken.balanceOf(msg.sender), false);
    }

    /**
     * @notice Returns the positions aToken underlying asset.
     */
    function assetOf(bytes memory) public pure override returns (ERC20) {
        return FRAX();
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategists to lend assets on Aave.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param fToken the token to lend on Aave
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Aave.
     */
    function lendFrax(IFToken fToken, uint256 amountToDeposit) public {
        _validateFToken(fToken);
        amountToDeposit = _maxAvailable(FRAX(), amountToDeposit);
        FRAX().safeApprove(address(fToken), amountToDeposit);
        fToken.deposit(amountToDeposit, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(FRAX(), address(fToken));
    }

    /**
     * @notice Allows strategists to withdraw assets from Aave.
     * @param fToken the token to withdraw from Aave.
     * @param amountToRedeem the amount of `tokenToWithdraw` to withdraw from Aave
     */
    function redeemFraxShare(IFToken fToken, uint256 amountToRedeem) public {
        _validateFToken(fToken);
        amountToRedeem = _maxAvailable(ERC20(address(fToken)), amountToRedeem);

        fToken.redeem(amountToRedeem, address(this), address(this));
    }

    function _validateFToken(IFToken fToken) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(address(fToken))));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert FTokenAdaptor__FTokenPositionsMustBeTracked(address(fToken));
    }
}
