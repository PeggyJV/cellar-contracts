// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar } from "src/modules/adaptors/BaseAdaptor.sol";

/**
 * @title Cellar Adaptor
 * @notice Allows Cellars to interact with other Cellar positions.
 * @author crispymangoes
 */
contract CellarAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(Cellar cellar)
    // Where:
    // `cellar` is the underling Cellar this adaptor is working with
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
     * @notice Strategist attempted to interact with a Cellar with no position setup for it.
     */
    error CellarAdaptor__CellarPositionNotUsed(address cellar);

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Sommelier Cellar Adaptor V 1.1"));
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
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        _verifyCellarPositionIsUsed(address(cellar));
        ERC20 asset = cellar.asset();
        asset.safeApprove(address(cellar), assets);
        cellar.deposit(assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(asset, address(cellar));
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
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        _verifyCellarPositionIsUsed(address(cellar));
        cellar.withdraw(assets, receiver, address(this));
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
            Cellar cellar = abi.decode(adaptorData, (Cellar));
            return cellar.maxWithdraw(msg.sender);
        } else return 0;
    }

    /**
     * @notice Uses ERC4626 `previewRedeem` to determine Cellars balance in Cellar position.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        return cellar.previewRedeem(cellar.balanceOf(msg.sender));
    }

    /**
     * @notice Returns the asset the Cellar position uses.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        return cellar.asset();
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
    function depositToCellar(Cellar cellar, uint256 assets) public {
        _verifyCellarPositionIsUsed(address(cellar));
        ERC20 asset = cellar.asset();
        assets = _maxAvailable(asset, assets);
        asset.safeApprove(address(cellar), assets);
        cellar.deposit(assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(asset, address(cellar));
    }

    /**
     * @notice Allows strategists to withdraw from Cellar positions.
     * @param cellar the Cellar to withdraw `assets` from
     * @param assets the amount of assets to withdraw from `cellar`
     */
    function withdrawFromCellar(Cellar cellar, uint256 assets) public {
        _verifyCellarPositionIsUsed(address(cellar));
        if (assets == type(uint256).max) assets = cellar.maxWithdraw(address(this));
        cellar.withdraw(assets, address(this), address(this));
    }

    //============================================ Helper Functions ===========================================

    /**
     * @notice Reverts if a given `cellar` is not set up as a position in the calling Cellar.
     * @dev This function is only used in a delegate call context, hence why address(this) is used
     *      to get the calling Cellar.
     */
    function _verifyCellarPositionIsUsed(address cellar) internal view {
        // Check that cellar position is setup to be used in the cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(cellar)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId)) revert CellarAdaptor__CellarPositionNotUsed(cellar);
    }
}
