// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar } from "src/modules/adaptors/BaseAdaptor.sol";

/**
 * @title Generic ERC4626 Vault Adaptor (basically a copy of Cellar Adaptor w/ virtual function sigs to enable inheritance and overriding).
 * @notice Allows Cellars to interact with other ERC4626 contracts.
 * @author crispymangoes, 0xEinCodes
 * @dev this is a WIP and not audited yet.
 * NOTE: `CellarAdaptor.sol` was used, and is still used for nested Cellar positions for Sommelier Cellars (ERC4626 Vaults). Integrations into Aura, among other ERC4626 contracts outside of Sommelier have led to using a separate ERC4626Vault.sol file that allows more flexibility via inheritance.
 * NOTE: `Cellar` is still used throughout this contract at times because it is a contract made for the Sommelier protocol (has extra pricing and accounting mechanics, etc.)
 */
contract ERC4626Adaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(Cellar erc4626Vault)
    // Where:
    // `erc4626Vault` is the underling Cellar this adaptor is working with
    //================= Configuration Data Specification =================
    // configurationData = abi.encode(bool isLiquid)
    // Where:
    // `isLiquid` dictates whether the position is liquid or not
    // If true:
    //      position can support use withdraws
    // else:
    //      position can not support user withdraws
    //
    //====================================================================

    /**
     * @notice Strategist attempted to interact with a erc4626Vault with no position setup for it.
     */
    error ERC4626Adaptor__CellarPositionNotUsed(address erc4626Vault);

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Sommelier General ERC4626 Adaptor V 0.0"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Cellar position to spend its assets, then deposit into the Cellar position.
     * @param assets the amount of assets to deposit into the Cellar position
     * @param adaptorData adaptor data containining the abi encoded Cellar
     * @dev configurationData is NOT used
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to `cellar`.
        Cellar erc4626Vault = abi.decode(adaptorData, (Cellar));
        _verifyCellarPositionIsUsed(address(erc4626Vault));
        ERC20 asset = erc4626Vault.asset();
        asset.safeApprove(address(erc4626Vault), assets);
        erc4626Vault.deposit(assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(asset, address(erc4626Vault));
    }

    /**
     * @notice Cellar needs to call withdraw on Cellar position.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from the Cellar position
     * @param receiver address to send assets to'
     * @param adaptorData data needed to withdraw from the Cellar position
     * @param configurationData abi encoded bool indicating whether the position is liquid or not
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory configurationData
    ) public override {
        // Check that position is setup to be liquid.
        bool isLiquid = abi.decode(configurationData, (bool));
        if (!isLiquid) revert BaseAdaptor__UserWithdrawsNotAllowed();

        // Run external receiver check.
        _externalReceiverCheck(receiver);

        // Withdraw assets from `cellar`.
        Cellar erc4626Vault = abi.decode(adaptorData, (Cellar));
        _verifyCellarPositionIsUsed(address(erc4626Vault));
        erc4626Vault.withdraw(assets, receiver, address(this));
    }

    /**
     * @notice Cellar needs to call `maxWithdraw` to see if its assets are locked.
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory configurationData
    ) public view override returns (uint256) {
        bool isLiquid = abi.decode(configurationData, (bool));
        if (isLiquid) {
            Cellar erc4626Vault = abi.decode(adaptorData, (Cellar));
            return erc4626Vault.maxWithdraw(msg.sender);
        } else return 0;
    }

    /**
     * @notice Uses ERC4626 `previewRedeem` to determine Cellars balance in Cellar position.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        Cellar erc4626Vault = abi.decode(adaptorData, (Cellar));
        return erc4626Vault.previewRedeem(erc4626Vault.balanceOf(msg.sender));
    }

    /**
     * @notice Returns the asset the Cellar position uses.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        Cellar erc4626Vault = abi.decode(adaptorData, (Cellar));
        return erc4626Vault.asset();
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategists to deposit into Cellar positions.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param cellar the Cellar to deposit `assets` into
     * @param assets the amount of assets to deposit into `cellar`
     */
    function depositToCellar(Cellar erc4626Vault, uint256 assets) public {
        _verifyCellarPositionIsUsed(address(erc4626Vault));
        ERC20 asset = erc4626Vault.asset();
        assets = _maxAvailable(asset, assets);
        asset.safeApprove(address(erc4626Vault), assets);
        erc4626Vault.deposit(assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(asset, address(erc4626Vault));
    }

    /**
     * @notice Allows strategists to withdraw from Cellar positions.
     * @param cellar the Cellar to withdraw `assets` from
     * @param assets the amount of assets to withdraw from `cellar`
     */
    function withdrawFromCellar(Cellar erc4626Vault, uint256 assets) public {
        _verifyCellarPositionIsUsed(address(erc4626Vault));
        if (assets == type(uint256).max) assets = erc4626Vault.maxWithdraw(address(this));
        erc4626Vault.withdraw(assets, address(this), address(this));
    }

    //============================================ Helper Functions ===========================================

    /**
     * @notice Reverts if a given `erc4626Vault` is not set up as a position in the calling Cellar.
     * @dev This function is only used in a delegate call context, hence why address(this) is used
     *      to get the calling Cellar.
     */
    function _verifyCellarPositionIsUsed(address erc4626Vault) internal view {
        // Check that erc4626Vault position is setup to be used in the calling cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(erc4626Vault)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert ERC4626Adaptor__CellarPositionNotUsed(erc4626Vault);
    }
}
