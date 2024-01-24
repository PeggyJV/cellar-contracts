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

    function getWithdrawalStatus(
        uint256[] calldata _requestIds
    ) external view returns (WithdrawalRequestStatus[] memory statuses);

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds);

    function claimWithdrawal(uint256 _requestId) external;
}

/**
 * @title Lido Staking Adaptor
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
        return keccak256(abi.encode("Lido Staking Adaptor V 0.0"));
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

    function _balanceOf(address account) internal view override returns (uint256 amount) {
        bytes32[] memory requests = StakingAdaptor(adaptorAddress).getRequestIds(account);
        // Convert requests to uint256 objects.
        uint256[] memory requestsIds_uint256 = new uint256[](requests.length);
        for (uint256 i; i < requests.length; ++i) {
            requestsIds_uint256[i] = uint256(requests[i]);
        }
        IUNSTETH.WithdrawalRequestStatus[] memory statuses = unstETH.getWithdrawalStatus(requestsIds_uint256);
        for (uint256 i; i < statuses.length; ++i) {
            amount += statuses[i].amountOfStETH;
        }
    }

    // https://etherscan.io/address/0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1#writeProxyContract
    function _requestBurn(uint256 amount) internal override returns (bytes32 id) {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory ids = unstETH.requestWithdrawals(amounts, address(this));
        id = bytes32(ids[0]);
    }

    function _completeBurn(bytes32 id) internal override {
        // TODO call claim withdrawals on unstETH contract. Then wrap it to WETH.
        unstETH.claimWithdrawal(uint256(id));
    }
}
