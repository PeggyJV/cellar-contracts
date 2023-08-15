// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import { CollateralFTokenAdaptorV2 } from "src/modules/adaptors/Frax/CollateralFTokenAdaptorV2.sol";

interface V1FToken {
    function updateExchangeRate() external returns (uint256 _exchangeRate);
}

/**
 * @title FraxLend Collateral Adaptor
 * @notice Allows addition and removal of collateralAssets to Fraxlend pairs for a Cellar.
 * @author crispymangoes, 0xEinCodes
 *  * TODO: change CollateralFTokenAdaptorV2 to CollateralFTokenAdaptor in naming
 */
contract CollateralFTokenAdaptorV1 is CollateralFTokenAdaptorV2 {
    //============================================ Notice ===========================================
    // Since there is no way to calculate pending interest for this positions balanceOf,
    // The positions balance is only updated when accounts interact with the
    // Frax Lend pair this position is working with.
    // This can lead to a divergence from the Cellars share price, and its real value.
    // This can be mitigated by calling `callAddInterest` on Frax Lend pairs
    // that are not frequently interacted with.

    constructor(address _frax, uint256 _healthFactor) CollateralFTokenAdaptorV2(_frax, _healthFactor) {}

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
    // whereas the inherited `CollateralFTokenAdaptorV2.sol` is actually associated to `FraxLendPairv2`.
    // The reasoning to name it like this was to set up the base CollateralFTokenAdaptorV2 for the
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
        return keccak256(abi.encode("FraxLend Collateral fTokenV1 Adaptor V 0.1"));
    }

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

    function _updateExchangeRate(IFToken fraxlendPair) internal override returns (uint256 exchangeRate) {
        exchangeRate = V1FToken(address(fraxlendPair)).updateExchangeRate();
    }
}
