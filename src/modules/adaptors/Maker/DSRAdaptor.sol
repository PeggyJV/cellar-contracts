// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { DSRManager } from "src/interfaces/external/Maker/DSRManager.sol";
import { Pot } from "src/interfaces/external/Maker/Pot.sol";

/**
 * @title DSR Adaptor
 * @notice Allows Cellars to deposit/withdraw DAI from the DSR.
 * @author crispymangoes
 */
contract DSRAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // NOT USED
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
        return keccak256(abi.encode("DSR Adaptor V 0.0"));
    }

    /**
     * @notice Current networks DSR Manager address.
     */
    DSRManager public immutable dsrManager;

    /**
     * @notice Current networks Pot address.
     */
    Pot public immutable pot;

    /**
     * @notice Current networks DAI address.
     */
    ERC20 public immutable dai;

    constructor(address _dsrManager) {
        DSRManager manager = DSRManager(_dsrManager);
        dsrManager = manager;
        pot = Pot(manager.pot());
        dai = ERC20(manager.dai());
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice Deposit assets directly into DSR.
     */
    function deposit(uint256 assets, bytes memory, bytes memory) public override {
        _join(assets);
    }

    /**
     * @notice Withdraw assets from DSR.
     */
    function withdraw(uint256 assets, address receiver, bytes memory, bytes memory) public override {
        _externalReceiverCheck(receiver);

        dsrManager.exit(receiver, assets);
    }

    /**
     * @notice Identical to `balanceOf`.
     * @dev Does not account for pending interest.
     */
    function withdrawableFrom(bytes memory, bytes memory) public view override returns (uint256) {
        uint256 pieOf = dsrManager.pieOf(msg.sender);
        return pieOf.mulDivDown(pot.chi(), 1e27);
    }

    /**
     * @notice Returns the balance of DAI in the DSR.
     * @dev Does not account for pending interest.
     */
    function balanceOf(bytes memory) public view override returns (uint256) {
        uint256 pieOf = dsrManager.pieOf(msg.sender);
        return pieOf.mulDivDown(pot.chi(), 1e27);
    }

    /**
     * @notice Returns DAI
     */
    function assetOf(bytes memory) public view override returns (ERC20) {
        return dai;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategist to join the DSR.
     */
    function join(uint256 assets) external {
        assets = _maxAvailable(dai, assets);
        _join(assets);
    }

    /**
     * @notice Allows strategist to exit the DSR.
     */
    function exit(uint256 assets) external {
        if (assets == type(uint256).max) dsrManager.exitAll(address(this));
        else dsrManager.exit(address(this), assets);
    }

    /**
     * @notice Allows strategist to update `chi`.
     */
    function drip() external {
        pot.drip();
    }

    //============================================ Helper Functions ===========================================

    /**
     * @notice Internal helper function to join the DSR.
     */
    function _join(uint256 assets) internal {
        dai.safeApprove(address(dsrManager), assets);
        dsrManager.join(address(this), assets);
        _revokeExternalApproval(dai, address(dsrManager));
    }
}
