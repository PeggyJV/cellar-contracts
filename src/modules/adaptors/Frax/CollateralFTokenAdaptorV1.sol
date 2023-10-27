// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import { CollateralFTokenAdaptor } from "src/modules/adaptors/Frax/CollateralFTokenAdaptor.sol";

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
 * @title FraxLend Collateral Adaptor
 * @notice Allows addition and removal of collateralAssets to Fraxlend pairs for a Cellar.
 * @author crispymangoes, 0xEinCodes
 */
contract CollateralFTokenAdaptorV1 is CollateralFTokenAdaptor {
    constructor(address _frax, uint256 _healthFactor) CollateralFTokenAdaptor(_frax, _healthFactor) {}

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

    // IMPORTANT: This `CollateralFTokenAdaptorV1.sol` is associated to the v1 version of `FraxLendPair`
    // whereas the inherited `CollateralFTokenAdaptor.sol` is actually associated to `FraxLendPairv2`.
    // The reasoning to name it like this was to set up the base CollateralFTokenAdaptor for the
    // most current version, v2. This is in anticipation that more FraxLendPairs will
    // be deployed following v2 in the near future. When later versions are deployed,
    // then the described inheritance pattern above will be used.

    // NOTE: FraxlendHealthFactorLogic.sol has helper functions used for both v1 and v2 fraxlend pairs (`_getHealthFactor()`).
    // This function has a helper `_toBorrowAmount()` that corresponds to v2 by default, but is virtual and overwritten for
    // fraxlendV1 pairs as seen in Collateral and Debt adaptors for v1 pairs.
    //===============================================================================

    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("FraxLend Collateral fTokenV1 Adaptor V 0.2"));
    }

    /**
     * @notice Converts a given number of borrow shares to debtToken amount from specified 'v1' FraxLendPair
     * @param _fraxlendPair The specified FraxLendPair
     * @param _shares Shares of debtToken
     * @param _roundUp Whether to round up after division
     * @return amount of debtToken
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
     * @notice Caller calls `updateExchangeRate()` on specified FraxlendV1 Pair
     * @param fraxlendPair The specified FraxLendPair
     * @return exchangeRate needed to calculate the current health factor
     */
    function _getExchangeRateInfo(IFToken fraxlendPair) internal view override returns (uint256 exchangeRate) {
        exchangeRate = V1FToken(address(fraxlendPair)).exchangeRateInfo().exchangeRate;
    }
}
