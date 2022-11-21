// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

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
    // NOT USED
    //====================================================================

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Sommelier Cellar Adaptor V 0.0"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Cellar position to spend its assets, then deposit into the Cellar position.
     * @param assets the amount of assets to deposit into the Cellar position
     * @param adaptorData adaptor data containining the abi encoded Cellar
     * @dev configurationData is NOT used
     */
    function deposit(
        uint256 assets,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        // Deposit assets to `cellar`.
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        cellar.asset().safeApprove(address(cellar), assets);
        cellar.deposit(assets, address(this));
    }

    /**
     * @notice Cellar needs to call withdraw on Cellar position.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from the Cellar position
     * @param receiver address to send assets to'
     * @param adaptorData data needed to withdraw from the Cellar position
     * @dev configurationData is NOT used
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        // Withdraw assets from `cellar`.
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        cellar.withdraw(assets, receiver, address(this));
    }

    /**
     * @notice Cellar needs to call `maxWithdraw` to see if its assets are locked.
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        return cellar.maxWithdraw(msg.sender);
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
        assets = _maxAvailable(cellar.asset(), assets);
        cellar.asset().safeApprove(address(cellar), assets);
        cellar.deposit(assets, address(this));
    }

    /**
     * @notice Allows strategists to withdraw from Cellar positions.
     * @param cellar the Cellar to withdraw `assets` from
     * @param assets the amount of assets to withdraw from `cellar`
     */
    function withdrawFromCellar(Cellar cellar, uint256 assets) public {
        cellar.withdraw(assets, address(this), address(this));
    }
}
