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
contract LidoStakingAdaptor is StakingAdaptor {
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
        IWETH9 _wrappedNative,
        ISTETH _stETH,
        IWSTETH _wstETH,
        IUNSTETH _unstETH
    ) StakingAdaptor(_wrappedNative) {
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
        stETH.submit{ value: amount }(address(0));
    }

    function _wrap(uint256 amount) internal override {
        wstETH.wrap(amount);
    }

    function _unwrap(uint256 amount) internal override {
        wstETH.unwrap(amount);
    }

    function _getPendingWithdraw(
        address account
    ) internal view override returns (bool isRequestActive, bool isRequestPending, uint256 amount) {
        uint256[] memory requests = unstETH.getWithdrawalRequests(account);
        isRequestActive = requests.length > 0;
        uint256 lastFinalizedRequestId = unstETH.getLastFinalizedRequestId();
        if (requests[0] > lastFinalizedRequestId) {
            isRequestPending = true;
        } // else request has matured.
        WithdrawalRequestStatus[] memory statuses = unstETH.getWithdrawalStatus(requests);
        amount = statuses[0].cumulativeStETH;
    }

    // TODO so an attacker could just send the cellar their NFT, to cause a rebalance to revert, so maybe I should use unstructured storage to store the request id.
    // https://etherscan.io/address/0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1#writeProxyContract
    function _requestBurn(uint256 amount) internal override {
        // TODO Call requestWithdrawals on unstETH contract.
    }

    function _completeBurn(uint256 amount) internal override {
        // TODO call claim withdrawals on unstETH contract. Then wrap it to WETH.
    }
}
