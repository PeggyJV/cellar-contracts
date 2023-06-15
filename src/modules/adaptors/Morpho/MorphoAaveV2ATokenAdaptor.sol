// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IMorphoV2 } from "src/interfaces/external/Morpho/IMorphoV2.sol";
import { MorphoRewardHandler } from "src/modules/adaptors/Morpho/MorphoRewardHandler.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";

/**
 * @title Morpho Aave V2 aToken Adaptor
 * @notice Allows Cellars to interact with Morpho Aave V2 positions.
 * @author crispymangoes
 */
contract MorphoAaveV2ATokenAdaptor is BaseAdaptor, MorphoRewardHandler {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address aToken)
    // Where:
    // `aToken` is the AaveV2 A Token position this adaptor is working with
    //================= Configuration Data Specification =================
    // isLiquid bool indicating whether user withdraws are allowed from this position.
    // IMPORTANT: It is possible for a strategist to misconfigure their positions,
    // and allow user withdraws from aToken positions that are backing loans.
    // This will be mitigated by only allowing trusted strategists to use this adaptor,
    // and educating them the dangers of misconfiguring their position.
    // EX: If a cellar is using their aTokens to back a borrow, then strategists
    // should make their aToken positions illiquid, so that user withdraws do not
    // negatively affect the cellars health factor.
    //====================================================================

    /**
     * @notice Bit mask used to determine if a cellar has any open borrow positions
     *         by getting the cellar's userMarkets, and performing an AND operation
     *         with the borrow mask.
     */
    bytes32 public constant BORROWING_MASK = 0x5555555555555555555555555555555555555555555555555555555555555555;

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Morpho Aave V2 aToken Adaptor V 1.1"));
    }

    /**
     * @notice The Morpho Aave V2 contract on Ethereum Mainnet.
     */
    function morpho() internal pure returns (IMorphoV2) {
        return IMorphoV2(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Morpho to spend its assets, then call supply to lend its assets.
     * @param assets the amount of assets to lend on Morpho
     * @param adaptorData adaptor data containing the abi encoded aToken
     * @dev configurationData is not used for deposits bc it only influences user withdraws
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to Morpho.
        IAaveToken aToken = abi.decode(adaptorData, (IAaveToken));
        ERC20 underlying = ERC20(aToken.UNDERLYING_ASSET_ADDRESS());
        underlying.safeApprove(address(morpho()), assets);

        morpho().supply(address(aToken), assets);

        // Zero out approvals if necessary.
        _revokeExternalApproval(underlying, address(morpho()));
    }

    /**
     * @notice Cellars must withdraw from Morpho
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Morpho
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containing the abi encoded aToken
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        // Make sure position is not backing a borrow.
        if (isBorrowingAny(address(this))) revert BaseAdaptor__UserWithdrawsNotAllowed();

        IAaveToken aToken = abi.decode(adaptorData, (IAaveToken));

        // Withdraw assets from Morpho.
        morpho().withdraw(address(aToken), assets, receiver);
    }

    /**
     * @notice Uses configuration data to determine if the position is liquid or not.
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        // If position is backing a borrow, then return 0.
        // else return the balance of in underlying.
        if (isBorrowingAny(msg.sender)) return 0;
        else {
            address aToken = abi.decode(adaptorData, (address));
            return _balanceOfInUnderlying(aToken, msg.sender);
        }
    }

    /**
     * @notice Returns the cellars balance of the positions aToken.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        address aToken = abi.decode(adaptorData, (address));
        return _balanceOfInUnderlying(aToken, msg.sender);
    }

    /**
     * @notice Returns the positions aToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        return ERC20(token.UNDERLYING_ASSET_ADDRESS());
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
     * @param aToken the aToken to lend on Morpho
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Morpho.
     */
    function depositToAaveV2Morpho(IAaveToken aToken, uint256 amountToDeposit) public {
        ERC20 underlying = ERC20(aToken.UNDERLYING_ASSET_ADDRESS());
        amountToDeposit = _maxAvailable(underlying, amountToDeposit);
        underlying.safeApprove(address(morpho()), amountToDeposit);
        morpho().supply(address(aToken), amountToDeposit);

        // Zero out approvals if necessary.
        _revokeExternalApproval(underlying, address(morpho()));
    }

    /**
     * @notice Allows strategists to withdraw assets from Morpho.
     * @param aToken the atoken to withdraw from Morpho.
     * @param amountToWithdraw the amount of `tokenToWithdraw` to withdraw from Morpho
     */
    function withdrawFromAaveV2Morpho(IAaveToken aToken, uint256 amountToWithdraw) public {
        morpho().withdraw(address(aToken), amountToWithdraw, address(this));
    }

    /**
     * @notice Returns the balance in underlying of collateral.
     * @param poolToken the Aave V2 a Token user has supplied as collateral
     * @param user the address of the user to query their balance of
     */
    function _balanceOfInUnderlying(address poolToken, address user) internal view returns (uint256) {
        (uint256 inP2P, uint256 onPool) = morpho().supplyBalanceInOf(poolToken, user);

        uint256 balanceInUnderlying;
        // Morpho indexes are scaled by 27 decimals, so divide by 1e27.
        if (inP2P > 0) balanceInUnderlying = inP2P.mulDivDown(morpho().p2pSupplyIndex(poolToken), 1e27);
        if (onPool > 0) balanceInUnderlying += onPool.mulDivDown(morpho().poolIndexes(poolToken).poolSupplyIndex, 1e27);
        return balanceInUnderlying;
    }

    /**
     * @dev Returns if a user has been borrowing from any market.
     * @param user The address to check if it is borrowing or not.
     * @return True if the user has been borrowing on any market, false otherwise.
     */
    function isBorrowingAny(address user) public view returns (bool) {
        bytes32 userMarkets = morpho().userMarkets(user);
        return userMarkets & BORROWING_MASK != 0;
    }
}
