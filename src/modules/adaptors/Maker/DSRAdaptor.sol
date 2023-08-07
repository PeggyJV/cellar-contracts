// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";

interface DSRManager {
    function join(address dst, uint256 amount) external;

    function exit(address dst, uint256 amount) external;

    function exitAll(address dst) external;

    function pieOf(address user) external view returns (uint256);

    function pot() external view returns (address);

    function dai() external view returns (address);

    function daiBalance(address user) external returns (uint256);
}

interface Pot {
    function chi() external view returns (uint256);
}

/**
 * @title ERC20 Adaptor
 * @notice Allows Cellars to interact with ERC20 positions.
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

    DSRManager public immutable dsrManager;
    Pot public immutable pot;
    ERC20 public immutable dai;

    constructor(address _dsrManager) {
        dsrManager = DSRManager(_dsrManager);
        pot = Pot(dsrManager.pot());
        dai = ERC20(dsrManager.dai());
    }

    //============================================ Implement Base Functions ===========================================

    function deposit(uint256 assets, bytes memory, bytes memory) public override {
        _join(assets);
    }

    function withdraw(uint256 assets, address receiver, bytes memory, bytes memory) public override {
        _externalReceiverCheck(receiver);

        dsrManager.exit(receiver, assets);
    }

    /**
     * @notice Identical to `balanceOf`, if an asset is used with a non ERC20 standard locking logic,
     *         then a NEW adaptor contract is needed.
     */
    function withdrawableFrom(bytes memory, bytes memory) public view override returns (uint256) {
        uint256 pieOf = dsrManager.pieOf(msg.sender);
        return pieOf.mulDivDown(pot.chi(), 1e27);
    }

    /**
     * @notice Returns the balance of `token`.
     */
    function balanceOf(bytes memory) public view override returns (uint256) {
        uint256 pieOf = dsrManager.pieOf(msg.sender);
        return pieOf.mulDivDown(pot.chi(), 1e27);
    }

    /**
     * @notice Returns `token`
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

    function join(uint256 assets) external {
        assets = _maxAvailable(dai, assets);
        _join(assets);
    }

    function exit(uint256 assets) external {
        if (assets == type(uint256).max) dsrManager.exitAll(address(this));
        else dsrManager.exit(address(this), assets);
    }

    //============================================ Helper Functions ===========================================

    function _join(uint256 assets) internal {
        dai.safeApprove(address(dsrManager), assets);
        dsrManager.join(address(this), assets);
        _revokeExternalApproval(dai, address(dsrManager));
    }
}
