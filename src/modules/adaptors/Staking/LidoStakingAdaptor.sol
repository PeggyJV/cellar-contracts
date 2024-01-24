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

    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;

    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    function FINALIZE_ROLE() external view returns (bytes32);
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
        address _wrappedNative,
        uint8 _maxRequests,
        address _stETH,
        address _wstETH,
        address _unstETH
    ) StakingAdaptor(_wrappedNative, _maxRequests) {
        stETH = ISTETH(_stETH);
        wstETH = IWSTETH(_wstETH);
        unstETH = IUNSTETH(_unstETH);
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
        ERC20 derivative = ERC20(address(stETH));
        amount = _maxAvailable(derivative, amount);
        derivative.safeApprove(address(wstETH), amount);
        wstETH.wrap(amount);
        _revokeExternalApproval(derivative, address(wstETH));
    }

    function _unwrap(uint256 amount) internal override {
        amount = _maxAvailable(ERC20(address(wstETH)), amount);
        wstETH.unwrap(amount);
    }

    function _balanceOf(address account) internal view override returns (uint256 amount) {
        uint256[] memory requests = StakingAdaptor(adaptorAddress).getRequestIds(account);
        IUNSTETH.WithdrawalRequestStatus[] memory statuses = unstETH.getWithdrawalStatus(requests);
        for (uint256 i; i < statuses.length; ++i) {
            amount += statuses[i].amountOfStETH;
        }
    }

    // https://etherscan.io/address/0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1#writeProxyContract
    function _requestBurn(uint256 amount) internal override returns (uint256 id) {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        ERC20 derivative = ERC20(address(stETH));
        amount = _maxAvailable(derivative, amount);
        derivative.safeApprove(address(unstETH), amount);
        uint256[] memory ids = unstETH.requestWithdrawals(amounts, address(this));
        _revokeExternalApproval(derivative, address(unstETH));
        id = ids[0];
    }

    function _completeBurn(uint256 id) internal override {
        unstETH.claimWithdrawal(id);
    }
}
