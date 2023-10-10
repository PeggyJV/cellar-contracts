// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IAllocatorConduit } from "src/interfaces/external/Maker/IAllocatorConduit.sol";
import {IERC4626} from "";

import { UpgradeableProxied, UpgradeableProxy, ArrangerConduit, IUpgradeableProxied, IUpgradeableProxy, IArrangerConduit } from  "src/interfaces/external/Maker/Conduits";


/// From Spark Protocol Conduits Repo
interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

interface RolesLike {
    function canCall(bytes32, address, address, bytes4) external view returns (bool);
}

interface RegistryLike {
    function buffers(bytes32 ilk) external view returns (address buffer);
}



/**
 * @title ERC4626 Conduit
 * @notice Allows any SubDAO to allocate assets to generic ERC4626 vaults.
 * @author crispymangoes, 0xEinCodes
 * @dev Internal Virtual hooks to be used for bespoke implementation to be carried out in scenarios where there are extra calls that the SubDAO may want to carry out (ex. claim rewards, etc.).
 * NOTE: General concept: SubDAOs to use ERC4626Conduit to interact with ERC4626 Vaults and keep track of their respective ERC4626 share receipt tokens.
 * TODO: if total assets delta not checked via other means within makerDAO > SubDAO (allocator) > Conduits then it's best to have some sort of check here to protect against any edge cases where interaction w/ ERC4626 Vault would be negatively impactful to subDAO.
 * See notion doc for TODOs and further details / questions for Maker / Spark ecosystems. TODO: remove params from deposit() and other functions as per IAllocatorConduit
 * Ref: `SparkConduit.sol` for other design needs. These need to be flushed out of course with Maker system as Conduits are new and still `early`
 * TODO: amongst other design concepts, we need to choose whether single ERC4626 conduit will be created for single ERC4626 vault, but this code can be used for any ERC4626 Vault (just needs new deployment per ERC4626 Vault), or it will hold all accounting for generic ERC4626 Vault. FOR NOW, THIS SERVES ONLY ONE ERC4626 VAULT.
 * Recall: ArrangerConduit extends  UpgradeableProxied, IUpgradeableProxied, IArrangerConduit
 * TODO: It looks like the design of the ERC4626Conduit could just be extending the ArrangerConduit. The ArrangerConduit has permissions within it that work with yield bearing, whitelisted contracts. So there may be a revamp here, it looks like the only thing else that is needed is the addition of `hooks`, but that is only for exceptional scenarios. Typically the ArrangerConduit should be able to handle custom implementation (claiming rewards, etc.) per erc4626Vault.
 */
contract ERC4626Conduit is ArrangerConduit {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    ERC4626 erc4626Vault;

    //============================================ Errors and Events ===========================================

    /**
     * @notice
     */
    error ERC4626Conduit_IncorrectBaseAssetForERC4626Vault(address);

    /**
     * @notice constructor args for each ERC4626Conduit
     * @param _vault set immutable vault var
     */
    constructor(address _erc4626Vault) {
        erc4626Vault = ERC4626(_erc4626Vault);
    }

    //============================================ Global Functions ===========================================

    /**
     * @dev Identifier unique to this conduit for a shared registry. 
     * NOTE: Current contract design requires that a conduit be deployed per ERC4626 vault.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("ERC4626 Vault Conduit V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================
    
    /**
     *  @dev   Function for depositing tokens into a Fund Manager.
     *  @param ilk    The unique identifier of the ilk.
     *  @param asset  The asset to deposit.
     *  @param amount The amount of tokens to deposit.
     */
    function deposit(bytes32 ilk, address asset, uint256 amount) external override {
        // deposit assets to `erc4626Vault`
        // _verifyERC4626PositionIsUsed(address(erc4626Vault)); // TODO: verify that erc4626Vault is deemed safe to interact within Maker ecosystem
        // TODO: decode ilk

        if (asset != erc4626Vault.asset()) revert ERC4626Conduit_IncorrectBaseAssetForERC4626Vault(asset); 
        ERC20 asset = ERC20(asset);
        asset.safeApprove(address(erc4626Vault), amount);
        erc4626Vault.deposit(assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(asset, address(erc4626Vault)); // TODO: not sure if this is needed anymore
    };

    /**
     *  @dev   Function for withdrawing tokens from a Fund Manager.
     *  @param  ilk         The unique identifier of the ilk.
     *  @param  asset       The asset to withdraw.
     *  @param  maxAmount   The max amount of tokens to withdraw. Setting to "type(uint256).max" will ensure to withdraw all available liquidity.
     *  @return amount      The amount of tokens withdrawn.
     * TODO: do we want to implement functionality where the Conduit goes through a catalogue of ERC4626 positions similar to Cellars and withdraws in a certain order? Same question applies for whether the design ought to include a bool indicating to only target fully liquid positions or not. Ex of semi-illiquid erc4626 vault positions include: creating a CDP and using the loan in further yield strategies.)
     */
    function withdraw(bytes32 ilk, address asset, uint256 maxAmount) external override returns (uint256 amount){
        // Withdraw assets from `erc4626Vault`.
        // TODO: decode ilk
        erc4626Vault.withdraw(maxAmount, receiver, address(this));
    }

    /**
     *  @dev    Function to get the maximum deposit possible for a specific asset and ilk.
     *  @param  ilk         The unique identifier of the ilk.
     *  @param  asset       The asset to check.
     *  @return maxDeposit_ The maximum possible deposit for the asset.
     *  @param erc4626Vault the ERC4626 to query from
     */
    function maxDeposit(bytes32 ilk, address asset, ERC4626 erc4626Vault) external override view returns (uint256 maxDeposit_) {

        return erc4626Vault.maxDeposit(msg.sender);
    }

     /**
     *  @dev    Function to get the maximum withdrawal possible for a specific asset and ilk.
     *  @param  ilk          The unique identifier of the ilk.
     *  @param  asset        The asset to check.     
     *  @param erc4626Vault the ERC4626 to query from
     *  @return maxWithdraw_ The maximum possible withdrawal for the asset.
     */
    function maxWithdraw(bytes32 ilk, address asset, ERC4626 erc4626Vault) external override view returns (uint256 maxWithdraw_) {
        return erc4626Vault.maxDeposit(msg.sender);

    }

    //============================================ Helper Functions ===========================================

    /**
     * @notice Reverts if a given `erc4626Vault` is not set up as a position in the calling Cellar.
     * @dev This function is only used in a delegate call context, hence why address(this) is used
     *      to get the calling Cellar.
     */
    function _verifyERC4626PositionIsUsed(address erc4626Vault) internal view {
        // Check that erc4626Vault position is setup to be used in the calling cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(erc4626Vault)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert ERC4626Adaptor__CellarPositionNotUsed(erc4626Vault);
    }

    /**
     * @notice Helper function that checks if `spender` has any more approval for `asset`, and if so revokes it.
     */
    function _revokeExternalApproval(ERC20 asset, address spender) internal {
        if (asset.allowance(address(this), spender) > 0) asset.safeApprove(spender, 0);
    }
    //============================================ Helper Functions ===========================================

    //============================== Interface Details ==============================
    // Each scenario that the SubDAO interacts with a different ERC4626 Vault may have specific conditions that require additional external calls within the same transaction. Ex.) Claiming rewards from AuraPool that abide by ERC4626.
    // To account for this, conduit designers can use the below internal functions when working with
    // these different bespoke scenarios.
    // This setup allows new conduits to build upon this smart contract while overriding any function
    // it needs so it conforms with the bespoke scenario.

    // IMPORTANT: This `ERC4626Conduit.sol` is associated to the standard version of `ERC4626`

    //===============================================================================

    /**
     * @notice
     */
    function _beforeDepositHook() internal {}
}
