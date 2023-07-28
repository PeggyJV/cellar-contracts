// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Registry } from "src/Registry.sol";
import { Cellar } from "src/base/Cellar.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";

/**
 * @title VestingSimpleAdaptor
 * @notice Allows cellars to linearly release earned rewards.
 * @author Kevin Kennis
 */
contract VestingSimpleAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    /**
     * @notice Strategist attempted to interact with an unused vesting position.
     */
    error VestingSimpleAdaptor__VestingPositionNotUsed(address unUsedVestingContract);

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("VestingSimpleAdaptor V 1.0"));
    }

    //============================================ Implement Base Functions ===========================================
    //==================== Base Function Specification ====================
    // Base functions are functions designed to help the Cellar interact with
    // an adaptor position, strategists are not intended to use these functions.
    // Base functions MUST be implemented in adaptor contracts, even if that is just
    // adding a revert statement to make them uncallable by normal user operations.
    //
    // All view Base functions will be called used normal staticcall.
    // All mutative Base functions will be called using delegatecall.
    //=====================================================================
    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice Cellar just needs to transfer ERC20 token to `receiver`.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets amount of `token` to send to receiver
     * @param receiver address to send assets to
     * @param adaptorData data needed to withdraw from this position
     * @dev configurationData is NOT used
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory) public override {
        _externalReceiverCheck(receiver);
        VestingSimple vestingContract = abi.decode(adaptorData, (VestingSimple));
        _verifyVestingPositionIsUsed(address(vestingContract));
        vestingContract.withdrawAnyFor(assets, receiver);
    }

    /**
     * @notice Identical to `balanceOf`, if an asset is used with a non ERC20 standard locking logic,
     *         then a NEW adaptor contract is needed.
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        return balanceOf(adaptorData);
    }

    /**
     * @notice Function Cellars use to determine `assetOf` balance of an adaptor position.
     * @param adaptorData data needed to interact with the position
     * @return balance of the position in terms of `assetOf`
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        VestingSimple vestingContract = abi.decode(adaptorData, (VestingSimple));
        return vestingContract.vestedBalanceOf(msg.sender);
    }

    /**
     * @notice Function Cellars use to determine the underlying ERC20 asset of a position.
     * @param adaptorData data needed to withdraw from a position
     * @return the underlying ERC20 asset of a position
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        VestingSimple vestingContract = abi.decode(adaptorData, (VestingSimple));
        return vestingContract.asset();
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================
    //==================== Strategist Function Specification ====================
    // Strategist functions are only callable by strategists through the Cellars
    // `callOnAdaptor` function. A cellar will never call any of these functions,
    // when a normal user interacts with a cellar(depositing/withdrawing)
    //
    // All strategist functions will be called using delegatecall.
    // Strategist functions are intentionally "blind" to what positions the cellar
    // is currently holding. This allows strategists to enter temporary positions
    // while rebalancing.
    // To mitigate strategist from abusing this and moving funds in untracked
    // positions, the cellar will enforce a Total Value Locked check that
    // insures TVL has not deviated too much from `callOnAdaptor`.
    //===========================================================================

    /**
     * @notice Allows strategists to deposit tokens to the vesting contract. By passing
     *         a max uint256 for amountToDeposit, the cellar will deposit its entire
     *         balance (appropriate in most cases).
     *
     * @param vestingContract The vesting contract to interact with.
     * @param amountToDeposit The amount of tokens to deposit.
     */
    function depositToVesting(VestingSimple vestingContract, uint256 amountToDeposit) public {
        _verifyVestingPositionIsUsed(address(vestingContract));
        ERC20 asset = vestingContract.asset();

        amountToDeposit = _maxAvailable(asset, amountToDeposit);
        asset.safeApprove(address(vestingContract), amountToDeposit);

        vestingContract.deposit(amountToDeposit, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(asset, address(vestingContract));
    }

    /**
     * @notice Withdraw a single deposit from vesting. This will not affect the cellar's TVL
     *         because any deposit must already have vested, and will be reported in balanceOf.
     *         Will revert if not enough tokens are available based on amountToWithdraw.
     *
     * @param vestingContract The vesting contract to interact with.
     * @param depositId The ID of the deposit to withdraw from.
     * @param amountToWithdraw The amount of tokens to withdraw.
     */
    function withdrawFromVesting(VestingSimple vestingContract, uint256 depositId, uint256 amountToWithdraw) public {
        _verifyVestingPositionIsUsed(address(vestingContract));
        vestingContract.withdraw(depositId, amountToWithdraw);
    }

    /**
     * @notice Withdraw a certain amount of tokens from vesting, from any deposit. This will
     *         not affect the cellar's TVL because any deposit must already have vested, and
     *         will be reported in balanceOf. Will revert if not enough tokens are available
     *         based on amountToWithdraw.
     *
     * @param vestingContract The vesting contract to interact with.
     * @param amountToWithdraw The amount of tokens to withdraw.
     */
    function withdrawAnyFromVesting(VestingSimple vestingContract, uint256 amountToWithdraw) public {
        _verifyVestingPositionIsUsed(address(vestingContract));
        vestingContract.withdrawAnyFor(amountToWithdraw, address(this));
    }

    /**
     * @notice Withdraw all available tokens from vesting. This will not affect the cellar's TVL
     *         because all withdrawn deposits must already have vested, and will be reported in balanceOf.
     *
     * @param vestingContract The vesting contract to interact with.
     */
    function withdrawAllFromVesting(VestingSimple vestingContract) public {
        _verifyVestingPositionIsUsed(address(vestingContract));
        vestingContract.withdrawAll();
    }

    //============================================ Helper Functions ===========================================

    function _verifyVestingPositionIsUsed(address vestingContract) internal view {
        // Check that vesting position is setup to be used in the cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(vestingContract)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert VestingSimpleAdaptor__VestingPositionNotUsed(vestingContract);
    }
}
