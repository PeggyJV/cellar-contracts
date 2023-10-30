// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import { DebtFTokenAdaptor } from "src/modules/adaptors/Frax/DebtFTokenAdaptor.sol";

/**
 * @notice Extra interface for FraxlendV1 pairs for `updateExchangeRate()` access. Originally was thought to be all included into the `updateExchangeRate()` defined within interface IFToken.sol, but solidity requires that there are separate interfaces because `updateExchangeRate()` differs between Fraxlend v1 and v2 Pairs in the return values.
 */
interface V1FToken {
    function exchangeRateInfo() external view returns (ExchangeRateInfo memory exchangeRateInfo);

    struct ExchangeRateInfo {
        uint32 lastTimestamp;
        uint224 exchangeRate; // collateral:asset ratio. i.e. how much collateral to buy 1e18 asset
    }
}

/**
 * @title FraxLend Debt Token Adaptor for FraxlendV1 pairs
 * @notice Allows Cellars to borrow assets from FraxLendV1 Pairs
 * @author crispymangoes, 0xEinCodes
 */
contract DebtFTokenAdaptorV1 is DebtFTokenAdaptor {
    //============================================ Notice ===========================================
    // Since there is no way to calculate pending interest for this positions balanceOf,
    // The positions balance is only updated when accounts interact with the
    // Frax Lend pair this position is working with.
    // This can lead to a divergence from the Cellars share price, and its real value.
    // This can be mitigated by calling `callAddInterest` on Frax Lend pairs
    // that are not frequently interacted with.

    constructor(
        bool _accountForInterest,
        address _frax,
        uint256 _healthFactor
    ) DebtFTokenAdaptor(_accountForInterest, _frax, _healthFactor) {}

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
    // whereas the inherited `DebtFTokenAdaptor.sol` is actually associated to `FraxLendPairv2`.
    // The reasoning to name it like this was to set up the base DebtFTokenAdaptor for the
    // most current version, v2. This is in anticipation that more FraxLendPairs will
    // be deployed following v2 in the near future. When later versions are deployed,
    // then the described inheritance pattern above will be used.

    // NOTE: FraxlendHealthFactorLogic.sol has helper functions used for both v1 and v2 fraxlend pairs (`_getHealthFactor()`).
    // This function has a helper `_toBorrow()` that corresponds to v2 by default, but is virtual and overwritten for
    // fraxlendV1 pairs as seen in Collateral and Debt adaptors for v1 pairs.
    //===============================================================================

    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("FraxLend debtTokenV1 Adaptor V 1.1"));
    }

    /**
     * @notice Converts a given number of borrow shares to debtToken amount from specified FraxlendV1 Pair
     * @param _fraxlendPair The specified FraxLendPair
     * @param _shares Shares of debtToken
     * @param _roundUp Whether to round up after division
     * @return amount of debtToken to receive
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
     * @notice Converts a given asset amount to a number of borrow shares from specified FraxlendV1 Pair
     * @dev versions of FraxLendPair do not have a fourth param whereas v2 does
     * @param fToken The specified FraxLendPair
     * @param amount The amount of asset
     * @param roundUp Whether to round up after division
     * @return number of borrow shares
     */
    function _toBorrowShares(
        IFToken fToken,
        uint256 amount,
        bool roundUp,
        bool
    ) internal view override returns (uint256) {
        return fToken.toBorrowShares(amount, roundUp);
    }

    /**
     * @notice Caller calls `addInterest` on specified FraxlendV1 Pair
     * @param fToken The specified FraxlendPair
     */
    function _addInterest(IFToken fToken) internal override {
        fToken.addInterest();
    }

    /**
     * @notice Caller calls `updateExchangeRate()` on specified FraxlendV1 Pair
     * @param fraxlendPair The specified FraxLendPair
     * @return exchangeRate needed to calculate the current health factor
     */
    function _getExchangeRateInfo(IFToken fraxlendPair) internal view override returns (uint256 exchangeRate) {
        exchangeRate = V1FToken(address(fraxlendPair)).exchangeRateInfo().exchangeRate;
    }
}
