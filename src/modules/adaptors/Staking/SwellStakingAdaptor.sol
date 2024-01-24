// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";

interface ISTETH {
    function submit(address referral) external payable;
}

interface IWSTETH {
    function wrap(uint256 amount) external;

    function unwrap(uint256 amount) external;
}

interface IUNSTETH {
    struct WithdrawalRequest {
        /// @notice sum of the all stETH submitted for withdrawals including this request
        uint128 cumulativeStETH;
        /// @notice sum of the all shares locked for withdrawal including this request
        uint128 cumulativeShares;
        /// @notice address that can claim or transfer the request
        address owner;
        /// @notice block.timestamp when the request was created
        uint40 timestamp;
        /// @notice flag if the request was claimed
        bool claimed;
        /// @notice timestamp of last oracle report for this request
        uint40 reportTimestamp;
    }

    struct WithdrawalRequestStatus {
        /// @notice stETH token amount that was locked on withdrawal queue for this request
        uint256 amountOfStETH;
        /// @notice amount of stETH shares locked on withdrawal queue for this request
        uint256 amountOfShares;
        /// @notice address that can claim or transfer this request
        address owner;
        /// @notice timestamp of when the request was created, in seconds
        uint256 timestamp;
        /// @notice true, if request is finalized
        bool isFinalized;
        /// @notice true, if request is claimed. Request is claimable if (isFinalized && !isClaimed)
        bool isClaimed;
    }

    function getWithdrawalRequests(address user) external view returns (uint256[] memory);

    function getWithdrawalStatus(
        uint256[] calldata _requestIds
    ) external view returns (WithdrawalRequestStatus[] memory statuses);

    function getLastFinalizedRequestId() external view returns (uint256);
}

/**
 * @title 0x Adaptor
 * @notice Allows Cellars to swap with 0x.
 * @author crispymangoes
 */
contract SwellStakingAdaptor is StakingAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has NO underlying position, its only purpose is to
    // expose the swap function to strategists during rebalances.
    //====================================================================

    ISTETH public immutable stETH;
    IWSTETH public immutable wstETH;
    IUNSTETH public immutable unstETH;

    constructor(
        address _wrappedNative,
        ISTETH _stETH,
        IWSTETH _wstETH,
        IUNSTETH _unstETH
    ) StakingAdaptor(_wrappedNative, 8) {
        stETH = _stETH;
        wstETH = _wstETH;
        unstETH = _unstETH;
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("0x Adaptor V 1.1"));
    }

    //============================================ Override Functions ===========================================
    function _mint(uint256 amount) internal override {
        // https://etherscan.io/address/0xf951E335afb289353dc249e82926178EaC7DEd78#writeProxyContract
        // call deposit
    }

    function _wrap(uint256 amount) internal override {
        wstETH.wrap(amount);
    }

    function _unwrap(uint256 amount) internal override {
        wstETH.unwrap(amount);
    }

    function _balanceOf(address account) internal view override returns (uint256 amount) {
        // Call getRewuestIdsByUser
        // Call userWithdrawRequests(uint256 id)
        // call nextRequestIdToFinalize to see if request is finalized.
    }

    // TODO so an attacker could just send the cellar their NFT, to cause a rebalance to revert, so maybe I should use unstructured storage to store the request id.
    // for this we can do a mapping from address to a uint256.
    // TODO but do I really need unstructured storage? Or can I just make an external call to the adaptor to write to a mapping <----- this
    // could probs jsut store a bytes32 then encode.decode however I need to.
    // https://etherscan.io/address/0x9F0491B32DBce587c50c4C43AB303b06478193A7
}
