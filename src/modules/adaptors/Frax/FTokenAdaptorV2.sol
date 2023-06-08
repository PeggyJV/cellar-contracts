// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";

/**
 * @title FraxLend fToken Adaptor
 * @notice Allows Cellars to lend FRAX to FraxLend markets.
 * @author crispymangoes, eincodes
 */
contract FTokenAdaptorV2 is FTokenAdaptor {
    //============================================ Interface Helper Functions ===========================================
    /**
     * @notice The Frax Pair interface can slightly change between versions.
     *         To account for this, FTokenAdaptors will use the below internal functions when
     *         interacting with Frax Pairs, this way new pairs can be added by creating a
     *         new contract that inherits from this one, and overrides any function it needs
     *         so it conforms with the new Frax Pair interface.
     */

    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("FraxLend fTokenV2 Adaptor V 0.0"));
    }

    function _toAssetAmount(IFToken fToken, uint256 shares, bool roundUp) internal view override returns (uint256) {
        // Note set `previewInterest` to false.
        // With such low interest rates on FRAX lending, the delta between the stored value,
        // and the true value will be negligible, and it not worth the extra gas cost.
        return fToken.toAssetAmount(shares, roundUp, false);
    }

    function _toAssetShares(IFToken fToken, uint256 amount, bool roundUp) internal view override returns (uint256) {
        // Note set `previewInterest` to false.
        // With such low interest rates on FRAX lending, the delta between the stored value,
        // and the true value will be negligible, and it not worth the extra gas cost.
        return fToken.toAssetShares(amount, roundUp, false);
    }
}
