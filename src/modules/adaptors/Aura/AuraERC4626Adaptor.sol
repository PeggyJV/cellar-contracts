// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IBaseRewardPool } from "src/interfaces/external/Aura/IBaseRewardPool.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC4626Adaptor } from "src/modules/adaptors/Sommelier/ERC4626Adaptor.sol";

/**
 * @title Aura "Extras" Adaptor
 * @dev This adaptor is specifically for AuraV? contracts. TODO: update version with final reformat
 * NOTE: (may remove this comment) To interact with a different version, inherit from this adaptor and override the interface helper functions.
 * @notice Allows Cellars to claim rewards from AURA pools
 * @author crispymangoes, 0xEinCodes
 */
contract AuraERC4626Adaptor is ERC4626Adaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address auraPool)
    // Where:
    // `auraPool` is the AURA pool address position this adaptor is working with.
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted to interact with an auraPool the Cellar is not using.
     */
    error AuraExtrasAdaptor__AuraPoolPositionsMustBeTracked(address auraPool);

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Aura Extras Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice Returns the positions underlying asset.
     * NOTE: setup to not cause any reversions but accounting is really done for rewardsTokens via other adaptors.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        ERC4626 auraPool = ERC4626(abi.decode(adaptorData, (address)));
        return ERC20(auraPool.asset());
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to get rewards for an AuraPool.
     * @param _auraPool the specified AuraPool
     * @param _claimExtras Whether or not to claim extra rewards associated to the AuraPool (outside of rewardToken for AuraPool)
     */
    function getRewards(IBaseRewardPool _auraPool, bool _claimExtras) public {
        _validateAuraPool(address(_auraPool));
        _getRewards(_auraPool, _claimExtras);
    }

    /**
     * @notice Validates that a given auraPool is set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateAuraPool(address _auraPool) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_auraPool)));
        // uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        // if (!Cellar(address(this)).isPositionUsed(positionId))
        //     revert AuraExtrasAdaptor__AuraPoolPositionsMustBeTracked(_auraPool); // TODO: troubleshoot uncommented implementation code here
    }

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // It is unlikely, but AURA pool interfaces can change between versions.
    // To account for this, internal functions will be used in case it is needed to
    // implement new functionality.
    //===============================================================================

    function _getRewards(IBaseRewardPool _auraPool, bool _claimExtras) internal virtual {
        _auraPool.getReward(address(this), _claimExtras); // TODO: confirm that any and all reward tokens associated to this position will be transferred from this external call.
        // emit event so there is a record of the strategist claiming rewards, marking down a clear record.
    }
}
