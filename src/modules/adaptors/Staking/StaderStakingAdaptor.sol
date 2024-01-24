// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";

interface IStakePoolManager {
    function deposit(address _receiver) external payable returns (uint256);
}

interface IWSTETH {
    function wrap(uint256 amount) external;

    function unwrap(uint256 amount) external;
}

interface IUserWithdrawManager {
    struct WithdrawRequest {
        address owner;
        uint256 ethXAmount;
        uint256 ethExpected;
        uint256 ethFinalized;
        uint256 requestTime;
    }

    function requestWithdraw(uint256 _ethXAmount, address _owner) external returns (uint256);

    function claim(uint256 _requestId) external;

    function userWithdrawRequests(uint256) external view returns (WithdrawRequest memory);
}

/**
 * @title 0x Adaptor
 * @notice Allows Cellars to swap with 0x.
 * @author crispymangoes
 */
contract StaderStakingAdaptor is StakingAdaptor {
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

    IStakePoolManager public immutable stakePoolManager;
    IUserWithdrawManager public immutable userWithdrawManager;

    constructor(
        IWETH9 _wrappedNative,
        IStakePoolManager _stakePoolManager,
        IUserWithdrawManager _userWithdrawManager
    ) StakingAdaptor(_wrappedNative, 8) {
        stakePoolManager = _stakePoolManager;
        userWithdrawManager = _userWithdrawManager;
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
        stakePoolManager.deposit{ value: amount }(address(this));
    }

    function _balanceOf(address account) internal view override returns (uint256 amount) {
        bytes32[] memory requests = StakingAdaptor(adaptorAddress).getRequestIds(account);

        for (uint256 i; i < requests.length; ++i) {
            IUserWithdrawManager.WithdrawRequest memory request = userWithdrawManager.userWithdrawRequests(
                uint256(requests[i])
            );
            amount += request.ethExpected;
        }
    }

    // TODO so an attacker could just send the cellar their NFT, to cause a rebalance to revert, so maybe I should use unstructured storage to store the request id.
    // for this we can do a mapping from address to a uint256.
    // TODO but do I really need unstructured storage? Or can I just make an external call to the adaptor to write to a mapping <----- this
    // could probs jsut store a bytes32 then encode.decode however I need to.
    // https://etherscan.io/address/0x9F0491B32DBce587c50c4C43AB303b06478193A7
    function _requestBurn(uint256 amount) internal override returns (bytes32 id) {
        // TODO Call requestWithdraw
    }

    function _completeBurn(bytes32 id) internal override {
        // TODO call claim
    }
}
