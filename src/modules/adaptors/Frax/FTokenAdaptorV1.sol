// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";

/**
 * @title FraxLend fToken Adaptor
 * @notice Allows Cellars to lend FRAX to FraxLend pairs.
 * @author crispymangoes, 0xEinCodes
 */
contract FTokenAdaptorV1 is FTokenAdaptor {
    //============================================ Notice ===========================================
    // Since there is no way to calculate pending interest for this positions balanceOf,
    // The positions balance is only updated when accounts interact with the
    // Frax Lend pair this position is working with.
    // This can lead to a divergence from the Cellars share price, and its real value.
    // This can be mitigated by calling `callAddInterest` on Frax Lend pairs
    // that are not frequently interacted with.

    constructor(bool _accountForInterest, address frax) FTokenAdaptor(_accountForInterest, frax) {}

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

    // IMPORTANT: This `FTokenAdaptorV1.sol` is associated to the v1 version of `FraxLendPair`
    // whereas the inherited `FTokenAdaptor.sol` is actually associated to `FraxLendPairv2`.
    // The reasoning to name it like this was to set up the base FTokenAdaptor for the
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
        return keccak256(abi.encode("FraxLend fTokenV1 Adaptor V 0.1"));
    }

    /**
     * @notice Withdraw $FRAX from specified 'v1' FraxLendPair.
     * @dev Since `withdrawableFrom` does NOT account for pending interest,
     *      user withdraws from V1 positions can result in dust being left in the position.
     * @dev If `ACCOUNT_FOR_INTEREST` is false, then _toAssetShares will use a FraxLend share price that
     *      is slightly lower than what is used in redeem, so users can receive more assets than expected.
     *      The extra assets are influenced by the FraxLend APR, and the time since the interest was last
     *      added to the pair, so in practice this extra amount should be negligible.
     * @param fToken The specified FraxLendPair
     * @param assets The amount to withdraw
     * @param receiver The address to which the Asset Tokens will be transferred
     * @param owner The owner of the Asset Shares (fTokens)
     */
    function _withdraw(IFToken fToken, uint256 assets, address receiver, address owner) internal override {
        // If accounting for interest, call `addInterest` before calculating shares to redeem.
        if (ACCOUNT_FOR_INTEREST) fToken.addInterest();
        uint256 shares = _toAssetShares(fToken, assets, false, ACCOUNT_FOR_INTEREST);
        fToken.redeem(shares, receiver, owner);
    }

    /**
     * @notice Converts a given number of shares to $FRAX amount from specified 'v1' FraxLendPair
     * @dev versions of FraxLendPair do not have a fourth param whereas v2 does
     * @param fToken The specified FraxLendPair
     * @param shares Shares of asset (fToken)
     * @param roundUp Whether to round up after division
     */
    function _toAssetAmount(
        IFToken fToken,
        uint256 shares,
        bool roundUp,
        bool
    ) internal view override returns (uint256) {
        return fToken.toAssetAmount(shares, roundUp);
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
     * @dev ftoken.addInterest() calls into the v1 FraxLendPair
     * @param fToken The specified FraxLendPair
     */
    function _addInterest(IFToken fToken) internal override {
        fToken.addInterest();
    }
}
