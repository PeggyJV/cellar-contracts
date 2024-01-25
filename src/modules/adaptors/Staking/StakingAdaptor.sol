// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IWETH9 } from "src/interfaces/external/IWETH9.sol";
import { BaseAdaptor, ERC20, SafeTransferLib } from "src/modules/adaptors/BaseAdaptor.sol";

abstract contract StakingAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has NO underlying position, its only purpose is to
    // interact with staking protocols.
    //====================================================================

    error StakingAdaptor__RequestNotFound(uint256 id);
    error StakingAdaptor__DuplicateRequest(uint256 id);
    error StakingAdaptor__MaximumRequestsExceeded();
    error StakingAdaptor__NotSupported();
    error StakingAdaptor__ZeroAmount();

    // If I find that all protocols use uint256, just make this uint256
    mapping(address => uint256[]) public requestIds;

    IWETH9 public immutable wrappedPrimitive;

    address internal immutable adaptorAddress;

    uint8 internal immutable maximumRequests;

    constructor(address _wrappedPrimitive, uint8 _maximumRequests) {
        wrappedPrimitive = IWETH9(_wrappedPrimitive);
        maximumRequests = _maximumRequests;
        adaptorAddress = address(this);
    }

    // TODO use unstructured storage to prevent cellar directly calling this.
    // Does not check for unique ids.
    function addRequestId(uint256 id) external {
        uint256[] storage ids = requestIds[msg.sender];
        uint256 idsLength = ids.length;
        if (idsLength >= maximumRequests) revert StakingAdaptor__MaximumRequestsExceeded();
        for (uint256 i = 0; i < idsLength; ++i) {
            if (ids[i] == id) revert StakingAdaptor__DuplicateRequest(id);
        }
        ids.push(id);
    }

    function removeRequestId(uint256 id) external {
        uint256[] storage ids = requestIds[msg.sender];
        uint256 idsLength = ids.length;
        for (uint256 i = 0; i < idsLength; ++i) {
            if (ids[i] == id) {
                // Copy last element to current position.
                ids[i] = ids[idsLength - 1];
                ids.pop();
                return;
            }
        }
        revert StakingAdaptor__RequestNotFound(id);
    }

    function getRequestIds(address user) external view returns (uint256[] memory) {
        return requestIds[user];
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar already has possession of users ERC20 assets by the time this function is called,
     *         so there is nothing to do.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice Cellar just needs to transfer ERC20 token to `receiver`.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice Identical to `balanceOf`, if an asset is used with a non ERC20 standard locking logic,
     *         then a NEW adaptor contract is needed.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the balance of `token`.
     */
    function balanceOf(bytes memory) public view override returns (uint256) {
        return _balanceOf(msg.sender);
    }

    /**
     * @notice Returns `token`
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        ERC20 primitive = abi.decode(adaptorData, (ERC20));
        return primitive;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    function mint(uint256 amount) external {
        if (amount == 0) revert StakingAdaptor__ZeroAmount();

        amount = _maxAvailable(ERC20(address(wrappedPrimitive)), amount);
        wrappedPrimitive.withdraw(amount);

        _mint(amount);
    }

    function requestBurn(uint256 amount) external {
        if (amount == 0) revert StakingAdaptor__ZeroAmount();

        uint256 id = _requestBurn(amount);

        // Add request id to staking adaptor.
        StakingAdaptor(adaptorAddress).addRequestId(id);
    }

    function completeBurn(uint256 id) external {
        uint256 primitiveDelta = address(this).balance;
        _completeBurn(id);
        primitiveDelta = address(this).balance - primitiveDelta;
        wrappedPrimitive.deposit{ value: primitiveDelta }();
        StakingAdaptor(adaptorAddress).removeRequestId(id);
    }

    function cancelBurn(uint256 id) external {
        _cancelBurn(id);
        StakingAdaptor(adaptorAddress).removeRequestId(id);
    }

    function wrap(uint256 amount) external {
        if (amount == 0) revert StakingAdaptor__ZeroAmount();

        _wrap(amount);
    }

    function unwrap(uint256 amount) external {
        if (amount == 0) revert StakingAdaptor__ZeroAmount();

        _unwrap(amount);
    }

    function mintERC20(ERC20 depositAsset, uint256 amount, uint256 minAmountOut) external {
        if (amount == 0) revert StakingAdaptor__ZeroAmount();

        _mintERC20(depositAsset, amount, minAmountOut);
    }

    // should return the amount of primitive that is pending and matured that is owed to `account`.
    function _balanceOf(address) internal view virtual returns (uint256) {
        revert StakingAdaptor__NotSupported();
    }

    function _mint(uint256) internal virtual {
        revert StakingAdaptor__NotSupported();
    }

    function _wrap(uint256) internal virtual {
        revert StakingAdaptor__NotSupported();
    }

    function _unwrap(uint256) internal virtual {
        revert StakingAdaptor__NotSupported();
    }

    function _requestBurn(uint256) internal virtual returns (uint256) {
        // revert StakingAdaptor__NotSupported();
    }

    function _completeBurn(uint256) internal virtual {
        // revert StakingAdaptor__NotSupported();
    }

    function _cancelBurn(uint256) internal virtual {
        revert StakingAdaptor__NotSupported();
    }

    function _mintERC20(ERC20 depositAsset, uint256 amount, uint256 minAmountOut) internal virtual {
        revert StakingAdaptor__NotSupported();
    }
}
