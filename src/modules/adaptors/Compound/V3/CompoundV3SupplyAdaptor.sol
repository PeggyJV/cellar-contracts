// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math, Cellar, Registry } from "src/modules/adaptors/BaseAdaptor.sol";
import { IComet } from "src/interfaces/external/Compound/IComet.sol";

/**
 * @title Compound V3 Supply Adaptor
 * @notice Allows Cellars to supply base token to Compound V3.
 * @author crispymangoes
 */
contract CompoundV3SupplyAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(Comet comet)
    // Where:
    // `comet` is the underling Compound V3 Comet this adaptor is working with
    //================= Configuration Data Specification =================
    // isLiquid bool
    // Indicates whether the position is liquid or not.
    //====================================================================

    /**
     * @notice Strategist attempted to use an invalid Comet address.
     */
    error SupplyAdaptor___InvalidComet(address comet);

    /**
     * @notice User withdraw would result in the Cellar taking on a debt position.
     */
    error SupplyAdaptor___WithdrawWouldResultInDebt();

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Compound V3 Supply Adaptor V 0.0"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Deposit base token into Compound V3.
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        IComet comet = abi.decode(adaptorData, (IComet));

        _verifyComet(comet);

        ERC20 base = comet.baseToken();
        base.safeApprove(address(comet), assets);

        comet.supply(address(base), assets);

        _revokeExternalApproval(base, address(comet));
    }

    /**
     * @notice Withdraw base token from Compound V3 and send to receiver.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory configurationData
    ) public override {
        _externalReceiverCheck(receiver);

        bool isLiquid = abi.decode(configurationData, (bool));
        if (!isLiquid) revert BaseAdaptor__UserWithdrawsNotAllowed();

        IComet comet = abi.decode(adaptorData, (IComet));

        // Check if the withdrawal would result in debt being taken out.
        // This should not be possible in the Cellar architecture as balanceOf returns
        // the supplied base token balance, so at most withdraws would pull all supplied
        // base token.
        uint256 baseSupplied = comet.balanceOf(address(this));
        if (assets > baseSupplied) revert SupplyAdaptor___WithdrawWouldResultInDebt();

        _verifyComet(comet);

        ERC20 base = comet.baseToken();

        comet.withdrawTo(receiver, address(base), assets);
    }

    /**
     * @notice If isLiquid is true, reports the minimum between baseSupplied and baseLiquid.
     *         else reports 0.
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory configurationData
    ) public view override returns (uint256) {
        bool isLiquid = abi.decode(configurationData, (bool));
        if (isLiquid) {
            IComet comet = abi.decode(adaptorData, (IComet));
            uint256 baseSupplied = comet.balanceOf(msg.sender);
            uint256 baseLiquid = comet.baseToken().balanceOf(address(comet));
            return baseSupplied > baseLiquid ? baseLiquid : baseSupplied;
        } else return 0;
    }

    /**
     * @notice Returns the balance of comet base token.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        IComet comet = abi.decode(adaptorData, (IComet));
        return comet.balanceOf(msg.sender);
    }

    /**
     * @notice Returns `comet.baseToken()`
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IComet comet = abi.decode(adaptorData, (IComet));
        return comet.baseToken();
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategist to supply base token to Compound V3.
     */
    function supplyBase(IComet comet, uint256 assets) external {
        _verifyComet(comet);

        ERC20 base = comet.baseToken();
        assets = _maxAvailable(base, assets);
        base.safeApprove(address(comet), assets);

        comet.supply(address(base), assets);

        _revokeExternalApproval(base, address(comet));
    }

    /**
     * @notice Allows strategist to withdraw base token from Compound V3.
     */
    function withdrawBase(IComet comet, uint256 assets) external {
        _verifyComet(comet);

        ERC20 base = comet.baseToken();
        uint256 baseSupplied = comet.balanceOf(address(this));
        uint256 baseLiquid = base.balanceOf(address(comet));

        // Cap withdraw amount to be baseSupplied so that a strategist can not accidentally open a borrow using this function.
        if (assets > baseSupplied) assets = baseSupplied;

        // Cap withdraw amount to what is liquid in comet.
        if (assets > baseLiquid) assets = baseLiquid;

        comet.withdraw(address(base), assets);
    }

    /**
     * @notice Reverts if a Cellar is not setup to interact with a given Comet.
     * @dev This function is only used in a delegate call context, hence why address(this) is used
     *      to get the calling Cellar.
     */
    function _verifyComet(IComet comet) internal view {
        uint256 cellarCodeSize;
        address cellarAddress = address(this);
        assembly {
            cellarCodeSize := extcodesize(cellarAddress)
        }
        if (cellarCodeSize > 0) {
            bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(comet)));
            Cellar cellar = Cellar(cellarAddress);
            Registry registry = cellar.registry();
            uint32 positionId = registry.getPositionHashToPositionId(positionHash);
            if (!cellar.isPositionUsed(positionId)) revert SupplyAdaptor___InvalidComet(address(comet));
        }
        // else do nothing. The cellar is currently being deployed so it has no bytecode, and trying to call `cellar.registry()` will revert.
    }
}
