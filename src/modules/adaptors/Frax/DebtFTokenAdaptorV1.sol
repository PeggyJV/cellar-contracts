// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import { DebtFTokenAdaptorV2 } from "src/modules/adaptors/Frax/DebtFTokenAdaptorV2.sol";

/**
 * @title FraxLend Debt Token Adaptor for FraxlendV1 pairs
 * @notice Allows Cellars to borrow assets from FraxLendV1 Pairs
 * @author crispymangoes, 0xEinCodes
 * TODO: change DebtFTokenAdaptorV2 to DebtFTokenAdaptor in naming
 */
contract DebtFTokenAdaptorV1 is DebtFTokenAdaptorV2 {
    //============================================ Notice ===========================================
    // Since there is no way to calculate pending interest for this positions balanceOf,
    // The positions balance is only updated when accounts interact with the
    // Frax Lend pair this position is working with.
    // This can lead to a divergence from the Cellars share price, and its real value.
    // This can be mitigated by calling `callAddInterest` on Frax Lend pairs
    // that are not frequently interacted with.

    constructor(bool _accountForInterest, address _frax, uint256 _healthFactor) DebtFTokenAdaptorV2(_accountForInterest, _frax, _healthFactor) {}

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // The Frax Pair interface can slightly change between versions.
    // To account for this, FTokenAdaptors will use the below internal functions when
    // interacting with Frax Pairs, this way new pairs can be added by creating a
    // new contract that inherits from this one, and overrides any function it needs
    // so it conforms with the new Frax Pair interface. This adaptor exemplifies how
    // the v1 version of `FraxLendPair` needs to be accomodated due to the slight
    // difference compared to the v2 `FraxLendPair` version.

    // Current versions in use for `FraxLendPair` include v1 and v2.

    // IMPORTANT: This `DebtFTokenAdaptorV1.sol` is associated to the v1 version of `FraxLendPair`
    // whereas the inherited `DebtFTokenAdaptorV2.sol` is actually associated to `FraxLendPairv2`.
    // The reasoning to name it like this was to set up the base DebtFTokenAdaptorV2 for the
    // most current version, v2. This is in anticipation that more FraxLendPairs will
    // be deployed following v2 in the near future. When later versions are deployed,
    // then the described inheritance pattern above will be used.
    //===============================================================================

    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("FraxLend debtTokenV1 Adaptor V 1.0"));
    }

    // /**
    //  * @notice Returns the cellar's balance of the respective Fraxlend debtToken calculated from cellar borrow shares
    //  * @param adaptorData encoded fraxlendPair (fToken) for this position
    //  * TODO: EIN
    //  */
    // function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
    //     IFToken fraxlendPair = abi.decode(adaptorData, (IFToken));
    //     return _toBorrowAmount(fraxlendPair, fraxlendPair.userBorrowShares(msg.sender), false, ACCOUNT_FOR_INTEREST);
    // }

    /**
     * @notice Converts a given number of borrow shares to debtToken amount from specified 'v1' FraxLendPair
     * @param _fraxlendPair The specified FraxLendPair
     * @param _shares Shares of debtToken
     * @param _roundUp Whether to round up after division
     */
    function _toBorrowAmount(
        IFToken _fraxlendPair,
        uint256 _shares,
        bool _roundUp,
        bool
    ) internal view override returns (uint256) {
        return _fraxlendPair.toBorrowAmount(_shares, _roundUp);
    }

    /**
     * @notice Converts a given asset amount to a number of asset shares (fTokens) from specified 'v1' FraxLendPair
     * @dev versions of FraxLendPair do not have a fourth param whereas v2 does
     * @param fToken The specified FraxLendPair
     * @param amount The amount of asset
     * @param roundUp Whether to round up after division
     */
    function _toAssetShares(
        IFToken fToken,
        uint256 amount,
        bool roundUp,
        bool
    ) internal view override returns (uint256) {
        return fToken.toAssetShares(amount, roundUp);
    }

    /**
     * @notice Caller calls `addInterest` on specified 'v1' FraxLendPair
     */
    function _addInterest(IFToken fToken) internal override {
        fToken.addInterest();
    }
}
