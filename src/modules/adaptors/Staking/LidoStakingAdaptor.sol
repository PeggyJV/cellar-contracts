// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";
import { IUNSTETH, IWSTETH, ISTETH } from "src/interfaces/external/IStaking.sol";

/**
 * @title Lido Staking Adaptor
 * @notice Allows Cellars to stake with Lido.
 * @dev Lido supports minting, burning, and wrapping.
 * @author crispymangoes
 */
contract LidoStakingAdaptor is StakingAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    /**
     * @notice stETH contract deposits are made to.
     */
    ISTETH public immutable stETH;

    /**
     * @notice Wrapper contract for stETH.
     */
    IWSTETH public immutable wstETH;

    /**
     * @notice Contract to handle stETH withdraws.
     */
    IUNSTETH public immutable unstETH;

    /**
     * @notice On deployment, save the `getLastCheckpointIndex` so it can be used
     *         as the starting index when calling `findCheckPointHints`
     */
    uint256 public immutable startingCheckPointIndex;

    constructor(
        address _wrappedNative,
        uint8 _maxRequests,
        address _stETH,
        address _wstETH,
        address _unstETH
    ) StakingAdaptor(_wrappedNative, _maxRequests) {
        stETH = ISTETH(_stETH);
        wstETH = IWSTETH(_wstETH);
        unstETH = IUNSTETH(_unstETH);
        startingCheckPointIndex = unstETH.getLastCheckpointIndex();
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Lido Staking Adaptor V 0.0"));
    }

    //============================================ Override Functions ===========================================

    /**
     * @notice Stakes into Lido using native asset.
     */
    function _mint(uint256 amount, bytes calldata) internal override returns (uint256 amountOut) {
        ERC20 derivative = ERC20(address(stETH));
        amountOut = derivative.balanceOf(address(this));
        stETH.submit{ value: amount }(address(0));
        amountOut = derivative.balanceOf(address(this)) - amountOut;
    }

    /**
     * @notice Wrap stETH.
     */
    function _wrap(uint256 amount, bytes calldata) internal override returns (uint256 amountOut) {
        ERC20 derivative = ERC20(address(stETH));
        amount = _maxAvailable(derivative, amount);
        derivative.safeApprove(address(wstETH), amount);
        amountOut = wstETH.wrap(amount);
        _revokeExternalApproval(derivative, address(wstETH));
    }

    /**
     * @notice Unwrap wstETH.
     */
    function _unwrap(uint256 amount, bytes calldata) internal override returns (uint256 amountOut) {
        amount = _maxAvailable(ERC20(address(wstETH)), amount);
        amountOut = wstETH.unwrap(amount);
    }

    /**
     * @notice Returns balance in pending and finalized withdraw requests.
     * @dev This function assumes that the primitive and derivative asset are 1:1.
     */
    function _balanceOf(address account) internal view override returns (uint256 amount) {
        uint256[] memory requests = StakingAdaptor(adaptorAddress).getRequestIds(account);
        IUNSTETH.WithdrawalRequestStatus[] memory statuses = unstETH.getWithdrawalStatus(requests);
        uint256 lastCheckpointIndex = type(uint256).max;
        for (uint256 i; i < statuses.length; ++i) {
            uint256 requestId = requests[i];
            // If request was already claimed continue.
            if (statuses[i].isClaimed) continue;
            if (statuses[i].isFinalized) {
                // Request has been finalized, and we need to call `getClaimableEther` to determine
                // the amount of ETH request is worth.
                // Save last checkpoint index if it has not been set.
                if (lastCheckpointIndex == type(uint256).max) lastCheckpointIndex = unstETH.getLastCheckpointIndex();
                // Start by determining what hint to use.
                uint256[] memory rIds = new uint256[](1);
                rIds[0] = requestId;
                uint256[] memory hints = unstETH.findCheckpointHints(
                    rIds,
                    startingCheckPointIndex,
                    lastCheckpointIndex
                );
                // Now call getClaimableEther to determine requests value.
                uint256[] memory finalizedAmounts = unstETH.getClaimableEther(rIds, hints);
                amount += finalizedAmounts[0];
            } else {
                // Request has not been finalized, so report amount as `amountOfStETH`.
                amount += statuses[i].amountOfStETH;
            }
        }
    }

    /**
     * @notice Request to withdraw.
     */
    function _requestBurn(uint256 amount, bytes calldata) internal override returns (uint256 id) {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        ERC20 derivative = ERC20(address(stETH));
        amount = _maxAvailable(derivative, amount);
        derivative.safeApprove(address(unstETH), amount);
        uint256[] memory ids = unstETH.requestWithdrawals(amounts, address(this));
        _revokeExternalApproval(derivative, address(unstETH));
        id = ids[0];
    }

    /**
     * @notice Complete a withdraw.
     * @param wildcard the uint256 hint for the given id
     *        Optionally leave this blank if not known, but call is more gas intensive.
     */
    function _completeBurn(uint256 id, bytes calldata wildcard) internal override {
        uint256 hint;
        if (wildcard.length > 0) hint = abi.decode(wildcard, (uint256));

        if (hint == 0) unstETH.claimWithdrawal(id);
        else {
            uint256[] memory ids = new uint256[](1);
            ids[0] = id;
            uint256[] memory hints = new uint256[](1);
            hints[0] = hint;
            unstETH.claimWithdrawals(ids, hints);
        }
    }

    /**
     * @notice Remove a request from requestIds if it is already claimed.
     */
    function removeClaimedRequest(uint256 id, bytes calldata) external override {
        uint256[] memory requests = new uint256[](1);
        requests[0] = id;
        IUNSTETH.WithdrawalRequestStatus[] memory statuses = unstETH.getWithdrawalStatus(requests);
        if (statuses[0].isClaimed) StakingAdaptor(adaptorAddress).removeRequestId(id);
        else revert StakingAdaptor__RequestNotClaimed(id);
    }
}
