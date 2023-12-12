// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib } from "src/modules/adaptors/BaseAdaptor.sol";

/**
 * @title ERC20 Adaptor
 * @notice Allows Cellars to interact with ERC20 positions.
 * @author crispymangoes
 */
contract ERC20Adaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(ERC20 token)
    // Where:
    // `token` is the underling ERC20 token this adaptor is working with
    //================= Configuration Data Specification =================
    // isLiquid bool
    // Indicates whether the position is liquid or not.
    //====================================================================

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("ERC20 Adaptor V 1.0"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar already has possession of users ERC20 assets by the time this function is called,
     *         so there is nothing to do.
     */
    function deposit(uint256, bytes memory, bytes memory) public override {}

    /**
     * @notice Cellar just needs to transfer ERC20 token to `receiver`.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets amount of `token` to send to receiver
     * @param receiver address to send assets to
     * @param adaptorData data needed to withdraw from this position
     * @param configurationData data needed to determine if this position is liquid or not
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

        ERC20 token = abi.decode(adaptorData, (ERC20));
        token.safeTransfer(receiver, assets);
    }

    /**
     * @notice Identical to `balanceOf`, if an asset is used with a non ERC20 standard locking logic,
     *         then a NEW adaptor contract is needed.
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory configurationData
    ) public view override returns (uint256) {
        bool isLiquid = abi.decode(configurationData, (bool));
        if (isLiquid) {
            ERC20 token = abi.decode(adaptorData, (ERC20));
            return token.balanceOf(msg.sender);
        } else return 0;
    }

    /**
     * @notice Returns the balance of `token`.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token.balanceOf(msg.sender);
    }

    /**
     * @notice Returns `token`
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 token = abi.decode(adaptorData, (ERC20));
        return token;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================
}
