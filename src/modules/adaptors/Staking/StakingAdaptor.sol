// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IWETH9 } from "src/interfaces/external/IWETH9.sol";
import { BaseAdaptor, ERC20, SafeTransferLib } from "src/modules/adaptors/BaseAdaptor.sol";

/**
 * @title Staking Adaptor
 * @notice Serves as a universal template for a variety of staking adaptors.
 * @notice A staking adaptor position will only check for value that is locked in unstaking
 *         requests, other value must be accounted for using other adaptors.
 * @dev Allows inheriting adaptors to implement staking, unstaking, wrapping, unwrapping.
 * @author crispymangoes
 */
contract StakingAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(ERC20 primitive)
    // Where:
    // primitive is the primitive asset that is returned from unstaking/burning a derivative.
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    // ========================================= GLOBAL STATE =========================================

    /**
     * @notice Stores burn/withdraw request ids for callers.
     */
    mapping(address => uint256[]) public requestIds;

    //========================================= ERRORS =========================================

    error StakingAdaptor__RequestNotFound(uint256 id);
    error StakingAdaptor__DuplicateRequest(uint256 id);
    error StakingAdaptor__MaximumRequestsExceeded();
    error StakingAdaptor__NotSupported();
    error StakingAdaptor__ZeroAmount();
    error StakingAdaptor__MinimumAmountNotMet(uint256 actual, uint256 minimum);
    error StakingAdaptor__RequestNotClaimed(uint256 id);

    /**
     * @notice Attempted to read `locked` from unstructured storage, but found uninitialized value.
     * @dev Most likely an external contract made a delegate call to this contract.
     */
    error StakingAdaptor___StorageSlotNotInitialized();

    /**
     * @notice Attempted to reenter into this contract.
     */
    error StakingAdaptor___Reentrancy();

    //========================================= IMMUTABLES ==========================================

    /**
     * @notice The wrapper contract for the primitive/native asset.
     */
    IWETH9 public immutable wrappedPrimitive;

    /**
     * @notice The address of this adaptor.
     */
    address internal immutable adaptorAddress;

    /**
     * @notice The maximum requests a caller can store in `requestIds`.
     * @dev This cap is here because `requestIds` must be iterated through in `_balanceOf`
     *      and it is unsafe to have an unbounded for loop.
     */
    uint8 internal immutable maximumRequests;

    /**
     * @notice The slot to store value needed to check for re-entrancy.
     */
    bytes32 public immutable lockedStoragePosition;

    constructor(address _wrappedPrimitive, uint8 _maximumRequests) {
        wrappedPrimitive = IWETH9(_wrappedPrimitive);
        maximumRequests = _maximumRequests;
        adaptorAddress = address(this);

        lockedStoragePosition =
            keccak256(abi.encode(uint256(keccak256("staking.adaptor.storage")) - 1)) &
            ~bytes32(uint256(0xff));

        // Initialize locked storage to 1;
        setLockedStorage(1);
    }

    //========================================= Unstructured Reentrancy =========================================

    /**
     * @notice Helper function to read `locked` from unstructured storage.
     */
    function readLockedStorage() internal view returns (uint256 locked) {
        bytes32 position = lockedStoragePosition;
        assembly {
            locked := sload(position)
        }
    }

    /**
     * @notice Helper function to set `locked` to unstructured storage.
     */
    function setLockedStorage(uint256 state) internal {
        bytes32 position = lockedStoragePosition;
        assembly {
            sstore(position, state)
        }
    }

    /**
     * @notice nonReentrant modifier that uses unstructured storage.
     */
    modifier nonReentrant() virtual {
        uint256 locked = readLockedStorage();
        if (locked == 0) revert StakingAdaptor___StorageSlotNotInitialized();
        if (locked != 1) revert StakingAdaptor___Reentrancy();

        setLockedStorage(2);

        _;

        setLockedStorage(1);
    }

    //========================================= Request Id Storage =========================================

    /**
     * @notice Add a request id to callers `requestIds` array.
     * @dev Reverts if maximum requests are stored, or if request id is duplicated.
     */
    function addRequestId(uint256 id) external nonReentrant {
        uint256[] storage ids = requestIds[msg.sender];
        uint256 idsLength = ids.length;
        if (idsLength >= maximumRequests) revert StakingAdaptor__MaximumRequestsExceeded();
        for (uint256 i = 0; i < idsLength; ++i) {
            if (ids[i] == id) revert StakingAdaptor__DuplicateRequest(id);
        }
        ids.push(id);
    }

    /**
     * @notice Remove a request id from callers `requestIds` array.
     * @dev Reverts if request id is not found.
     */
    function removeRequestId(uint256 id) external nonReentrant {
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

    /**
     * @notice Get a callers `requestIds` array.
     */
    function getRequestIds(address user) external view returns (uint256[] memory) {
        return requestIds[user];
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice This adaptor does not support user deposits.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice This adaptor does not support user withdraws.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This adaptor is not user withdrawable.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the balance of `primitive` that is unstaking.
     */
    function balanceOf(bytes memory) public view override returns (uint256) {
        return _balanceOf(msg.sender);
    }

    /**
     * @notice Returns `primitive`
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

    /**
     * @notice Allows a strategist to `mint` a derivative asset using the chains native asset.
     * @dev Will automatically unwrap the native asset.
     * @param amount the amount of native asset to use for minting
     * @param wildcard arbitrary abi encoded data that can be used by inheriting adaptors
     */
    function mint(uint256 amount, uint256 minAmountOut, bytes calldata wildcard) external virtual {
        if (amount == 0) revert StakingAdaptor__ZeroAmount();

        amount = _maxAvailable(ERC20(address(wrappedPrimitive)), amount);
        wrappedPrimitive.withdraw(amount);

        uint256 amountMinted = _mint(amount, wildcard);
        if (amountMinted < minAmountOut) revert StakingAdaptor__MinimumAmountNotMet(amountMinted, minAmountOut);
    }

    /**
     * @notice Allows a strategist to request to burn/withdraw a derivative for a chains native asset.
     * @param amount the amount of derivative to burn/withdraw
     * @param wildcard arbitrary abi encoded data that can be used by inheriting adaptors
     */
    function requestBurn(uint256 amount, bytes calldata wildcard) external virtual {
        if (amount == 0) revert StakingAdaptor__ZeroAmount();

        uint256 id = _requestBurn(amount, wildcard);

        // Add request id to staking adaptor.
        StakingAdaptor(adaptorAddress).addRequestId(id);
    }

    /**
     * @notice Allows a strategist to complete a burn/withdraw of a derivative asset for a native asset.
     * @dev Will automatically wrap the native asset received from burn/withdraw.
     * @param id the request id
     * @param wildcard arbitrary abi encoded data that can be used by inheriting adaptors
     */
    function completeBurn(uint256 id, uint256 minAmountOut, bytes calldata wildcard) external virtual {
        uint256 primitiveDelta = address(this).balance;
        _completeBurn(id, wildcard);
        primitiveDelta = address(this).balance - primitiveDelta;
        if (primitiveDelta < minAmountOut) revert StakingAdaptor__MinimumAmountNotMet(primitiveDelta, minAmountOut);
        wrappedPrimitive.deposit{ value: primitiveDelta }();
        StakingAdaptor(adaptorAddress).removeRequestId(id);
    }

    /**
     * @notice Allows a strategist to cancel an active burn/withdraw request.
     * @param id the request id
     * @param wildcard arbitrary abi encoded data that can be used by inheriting adaptors
     */
    function cancelBurn(uint256 id, bytes calldata wildcard) external virtual {
        _cancelBurn(id, wildcard);
        StakingAdaptor(adaptorAddress).removeRequestId(id);
    }

    /**
     * @notice Allows a strategist to wrap a derivative asset.
     * @param amount the amount of derivative to wrap
     * @param wildcard arbitrary abi encoded data that can be used by inheriting adaptors
     */
    function wrap(uint256 amount, uint256 minAmountOut, bytes calldata wildcard) external virtual {
        if (amount == 0) revert StakingAdaptor__ZeroAmount();

        uint256 amountOut = _wrap(amount, wildcard);
        if (amountOut < minAmountOut) revert StakingAdaptor__MinimumAmountNotMet(amountOut, minAmountOut);
    }

    /**
     * @notice Allows a strategist to unwrap a wrapped derivative asset.
     * @param amount the amount of wrapped derivative to unwrap
     * @param wildcard arbitrary abi encoded data that can be used by inheriting adaptors
     */
    function unwrap(uint256 amount, uint256 minAmountOut, bytes calldata wildcard) external virtual {
        if (amount == 0) revert StakingAdaptor__ZeroAmount();

        uint256 amountOut = _unwrap(amount, wildcard);
        if (amountOut < minAmountOut) revert StakingAdaptor__MinimumAmountNotMet(amountOut, minAmountOut);
    }

    /**
     * @notice Allows a strategist to mint a derivative asset using an ERC20.
     * @param depositAsset the ERC20 asset to mint with
     * @param amount the amount of `depositAsset` to mint with
     * @param minAmountOut the minimum amount of derivative out
     * @param wildcard arbitrary abi encoded data that can be used by inheriting adaptors
     */
    function mintERC20(
        ERC20 depositAsset,
        uint256 amount,
        uint256 minAmountOut,
        bytes calldata wildcard
    ) external virtual {
        if (amount == 0) revert StakingAdaptor__ZeroAmount();

        uint256 amountOut = _mintERC20(depositAsset, amount, minAmountOut, wildcard);
        if (amountOut < minAmountOut) revert StakingAdaptor__MinimumAmountNotMet(amountOut, minAmountOut);
    }

    /**
     * @notice Allows strategist to remove a request from `requestIds` if it has already been claimed.
     * @dev id the request id to remove
     * @dev wildcard arbitrary abi encoded data that can be used by inheriting adaptors
     */
    function removeClaimedRequest(uint256, bytes calldata) external virtual {
        if (true) revert StakingAdaptor__NotSupported();
    }

    //============================================ Interface Helper Functions ===========================================
    //============================== Interface Details =========================================
    // Staking protocols have very similar patterns when staking/unstaking, and wrapping/unwrapping.
    // This pattern has been generalized to the below interface helper functions.
    // Note inheriting adaptors do NOT need to implement all helper functions, rather they
    // should only implement the functions that they actually logically support.
    // ie A lot of protocols do not support unstaking, so the burn related functions should not be
    // implemented. Some protocols do not have a wrapped asset, so the wrapping functions
    // should not be implemented.

    // Note the below base implementations use this weird `if (true) revert` pattern so that
    // if a helper interface is not implemented, calls to the associated strategist function will
    // revert.
    // Also this was the only way I could get it so that the compiler would not complain about
    // unreachable code :)
    //==========================================================================================

    /**
     * @notice An inheriting adaptor should implement `_balanceOf` if they support unstaking.
     * @dev Should report both balances in both pending and finalized unstaking requests.
     * @dev Address input is the address to get balances for.
     */
    function _balanceOf(address) internal view virtual returns (uint256) {
        if (true) revert StakingAdaptor__NotSupported();
        return 0;
    }

    /**
     * @notice An inheriting adaptor should implement `_mint` if they support staking with native.
     * @dev Uint256 is the amount of native to mint with.
     * @dev bytes arbitrary abi encoded data that can be used by inheriting adaptors.
     */
    function _mint(uint256, bytes calldata) internal virtual returns (uint256) {
        if (true) revert StakingAdaptor__NotSupported();
        return 0;
    }

    /**
     * @notice An inheriting adaptor should implement `_wrap` if they support wrapping a derivative.
     * @dev Uint256 is the amount of derivative to wrap.
     * @dev bytes arbitrary abi encoded data that can be used by inheriting adaptors.
     */
    function _wrap(uint256, bytes calldata) internal virtual returns (uint256) {
        if (true) revert StakingAdaptor__NotSupported();
        return 0;
    }

    /**
     * @notice An inheriting adaptor should implement `_unwrap` if they support unwrapping a derivative.
     * @dev Uint256 is the amount of wrapped derivative to unwrap.
     * @dev bytes arbitrary abi encoded data that can be used by inheriting adaptors.
     */
    function _unwrap(uint256, bytes calldata) internal virtual returns (uint256) {
        if (true) revert StakingAdaptor__NotSupported();
        return 0;
    }

    /**
     * @notice An inheriting adaptor should implement `_requestBurn` if they support unstaking.
     * @dev Uint256 is the amount of derivative to unstake.
     * @dev bytes arbitrary abi encoded data that can be used by inheriting adaptors.
     * @dev Returns the request id.
     */
    function _requestBurn(uint256, bytes calldata) internal virtual returns (uint256) {
        if (true) revert StakingAdaptor__NotSupported();
        return 0;
    }

    /**
     * @notice An inheriting adaptor should implement `_completeBurn` if they support unstaking.
     * @dev Uint256 is the request id.
     * @dev bytes arbitrary abi encoded data that can be used by inheriting adaptors.
     */
    function _completeBurn(uint256, bytes calldata) internal virtual {
        if (true) revert StakingAdaptor__NotSupported();
    }

    /**
     * @notice An inheriting adaptor should implement `_cancelBurn` if they support canceling unstaking.
     * @dev Uint256 is the request id.
     * @dev bytes arbitrary abi encoded data that can be used by inheriting adaptors.
     */
    function _cancelBurn(uint256, bytes calldata) internal virtual {
        if (true) revert StakingAdaptor__NotSupported();
    }

    /**
     * @notice An inheriting adaptor should implement `_mintERC20` if they support minting using ERC20 assets.
     * @dev It is a good idea for inheriting adaptors to implement a value in vs value out check.
     * @dev First arg is the ERC20 to mint with.
     * @dev Second arg is the amount of ERC20.
     * @dev Third arg is the minimum amount of derivative out from mint.
     * @dev bytes arbitrary abi encoded data that can be used by inheriting adaptors.
     */
    function _mintERC20(ERC20, uint256, uint256, bytes calldata) internal virtual returns (uint256) {
        if (true) revert StakingAdaptor__NotSupported();
        return 0;
    }
}
