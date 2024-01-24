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

    // If I find that all protocols use uint256, just make this uint256
    mapping(address => bytes32[]) public requestIds;

    IWETH9 public immutable wrappedNative;

    address internal immutable adaptorAddress;

    uint8 internal immutable maximumRequests;

    constructor(IWETH9 _wrappedNative, uint8 _maximumRequests) {
        wrappedNative = _wrappedNative;
        maximumRequests = _maximumRequests;
    }

    // TODO use unstructured storage to prevent cellar directly calling this.
    // Does not check for unique ids.
    function addRequestId(bytes32 id) external {
        bytes32[] storage ids = requestIds[msg.sender];
        uint256 idsLength = ids.length;
        if (idsLength >= maximumRequests) revert("Max exceeded");
        for (uint256 i = 0; i < idsLength; ++i) {
            if (ids[i] == id) revert("Duplicate id");
        }
        ids.push(id);
    }

    function removeRequestId(bytes32 id) external {
        bytes32[] storage ids = requestIds[msg.sender];
        uint256 idsLength = ids.length;
        for (uint256 i = 0; i < idsLength; ++i) {
            if (ids[i] == id) {
                // Copy last element to current position.
                ids[i] = ids[idsLength - 1];
                ids.pop();
                return;
            }
        }
        revert("Id not found");
    }

    function getRequestIds(address user) external view returns (bytes32[] memory) {
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
        ERC20 native = abi.decode(adaptorData, (ERC20));
        return native;
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    function mint(uint256 amount) external {
        amount = _maxAvailable(ERC20(address(wrappedNative)), amount);
        wrappedNative.withdraw(amount);

        _mint(amount);
    }

    function requestBurn(uint256 amount) external {
        bytes32 id = _requestBurn(amount);

        // Add request id to staking adaptor.
        StakingAdaptor(adaptorAddress).addRequestId(id);
    }

    function completeBurn(bytes32 id) external {
        _completeBurn(id);
        StakingAdaptor(adaptorAddress).removeRequestId(id);
    }

    function wrap(uint256 amount) external {
        _wrap(amount);
    }

    function unwrap(uint256 amount) external {
        _unwrap(amount);
    }

    // should return the amount of native that is pending and matured that is owed to `account`.
    function _balanceOf(address account) internal view virtual returns (uint256 amount);

    function _mint(uint256 amount) internal virtual;

    function _wrap(uint256) internal virtual {
        revert("Not supported");
    }

    function _unwrap(uint256) internal virtual {
        revert("Not supported");
    }

    function _requestBurn(uint256 amount) internal virtual returns (bytes32 id);

    function _completeBurn(bytes32 id) internal virtual;
}
