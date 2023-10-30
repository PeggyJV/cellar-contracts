// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IBaseRewardPool } from "src/interfaces/external/Aura/IBaseRewardPool.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC4626Adaptor } from "src/modules/adaptors/ERC4626Adaptor.sol";

/**
 * @title Aura ERC4626 Adaptor
 * @dev This adaptor is specifically for Aura contracts.
 * @notice Carries out typical ERC4626Adaptor functionality and allows Cellars to claim rewards from AURA pools
 * @author crispymangoes, 0xEinCodes
 * NOTE: Transferrance of aura-wrapped BPT is not alowed as per their contracts: ref - https://etherscan.io/address/0xdd1fe5ad401d4777ce89959b7fa587e569bf125d#code#F1#L254
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
        return keccak256(abi.encode("Aura ERC4626 Adaptor V 0.1"));
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
     * @notice Validates that a given auraPool is set up as a position in the calling Cellar.
     * @dev This function uses `address(this)` as the address of the calling Cellar.
     */
    function _validateAuraPool(address _auraPool) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_auraPool)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert AuraExtrasAdaptor__AuraPoolPositionsMustBeTracked(_auraPool);
    }

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // It is unlikely, but AURA pool interfaces can change between versions.
    // To account for this, internal functions will be used in case it is needed to
    // implement new functionality.
    //===============================================================================

    function _getRewards(IBaseRewardPool _auraPool, bool _claimExtras) internal virtual {
        _auraPool.getReward(address(this), _claimExtras);
    }
}
