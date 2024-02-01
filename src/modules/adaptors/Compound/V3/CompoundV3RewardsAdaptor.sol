// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ICometRewards } from "src/interfaces/external/Compound/ICometRewards.sol";
import { PositionlessAdaptor } from "src/modules/adaptors/PositionlessAdaptor.sol";

contract CompoundV3RewardsAdaptor is PositionlessAdaptor {
    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has NO underlying position, its only purpose is to
    // expose the claim logic from Compound V3, so Cellars can claim rewards.
    //====================================================================

    /**
     * @notice The Compound V3 CometRewards contract for the given network.
     */
    ICometRewards public immutable cometRewards;

    constructor(address _cometRewards) {
        cometRewards = ICometRewards(_cometRewards);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Compound V3 Rewards Adaptor V 0.0"));
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Claim rewards from the comet.
     * @dev src, and shouldAccrue are hardcoded to the cellar address, and true.
     */
    function claim(address comet) external {
        cometRewards.claim(comet, address(this), true);
    }
}
