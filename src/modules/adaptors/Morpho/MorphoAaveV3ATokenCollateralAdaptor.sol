// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IMorpho } from "src/interfaces/external/Morpho/IMorpho.sol";

/**
 * @title Morpho Aave V3 aToken Adaptor
 * @notice Allows Cellars to interact with Morpho Aave V3 positions.
 * @author crispymangoes
 */
contract MorphoAaveV3ATokenCollateralAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address underlying)
    // Where:
    // `underlying` is the ERC20 position this adaptor is working with
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Morpho Aave V3 aToken Adaptor V 1.1"));
    }

    /**
     * @notice The Morpho Aave V2 contract on Ethereum Mainnet.
     */
    function morpho() internal pure returns (IMorpho) {
        return IMorpho(0x33333aea097c193e66081E930c33020272b33333);
    }

    /**
     * @notice The WETH contract on Ethereum Mainnet.
     */
    function WETH() internal pure returns (ERC20) {
        return ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Pool to spend its assets, then call deposit to lend its assets.
     * @param assets the amount of assets to lend on Aave
     * @param adaptorData adaptor data containining the abi encoded aToken
     * @dev configurationData is NOT used because this action will only increase the health factor
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory configurationData) public override {
        // Deposit assets to Morpho.
        ERC20 underlying = abi.decode(adaptorData, (ERC20));
        underlying.safeApprove(address(morpho()), assets);

        morpho().supplyCollateral(address(underlying), assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(underlying, address(morpho()));
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

        // Make sure there are no active borrows.
        address[] memory borrows = morpho().userBorrows(address(this));
        if (borrows.length > 0) revert BaseAdaptor__UserWithdrawsNotAllowed();

        ERC20 underlying = abi.decode(adaptorData, (ERC20));

        // Withdraw assets from Morpho.
        morpho().withdrawCollateral(address(underlying), assets, address(this), receiver);
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
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        address[] memory borrows = morpho().userBorrows(address(this));
        if (borrows.length > 0) return 0;
        else {
            ERC20 underlying = abi.decode(adaptorData, (ERC20));
            return morpho().collateralBalance(address(underlying), msg.sender);
        }
    }

    /**
     * @notice Returns the cellars balance of the positions aToken.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        ERC20 underlying = abi.decode(adaptorData, (ERC20));
        return morpho().collateralBalance(address(underlying), msg.sender);
    }

    /**
     * @notice Returns the positions aToken underlying asset.
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
     * @notice Allows strategists to lend assets on Aave.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param tokenToDeposit the token to lend on Aave
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Aave.
     */
    function depositToAaveV3Morpho(ERC20 tokenToDeposit, uint256 amountToDeposit) public {
        amountToDeposit = _maxAvailable(tokenToDeposit, amountToDeposit);
        tokenToDeposit.safeApprove(address(morpho()), amountToDeposit);
        morpho().supplyCollateral(address(tokenToDeposit), amountToDeposit, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(tokenToDeposit, address(morpho()));
    }

    /**
     * @notice Allows strategists to withdraw assets from Aave.
     * @param tokenToWithdraw the token to withdraw from Aave.
     * @param amountToWithdraw the amount of `tokenToWithdraw` to withdraw from Aave
     */
    function withdrawFromAaveV3Morpho(ERC20 tokenToWithdraw, uint256 amountToWithdraw) public {
        morpho().withdrawCollateral(address(tokenToWithdraw), amountToWithdraw, address(this), address(this));
    }
}
