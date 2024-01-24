// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";

interface IStakePoolManager {
    function deposit(address _receiver) external payable returns (uint256);
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
    ERC20 public immutable ETHx;

    constructor(
        address _wrappedNative,
        uint8 _maxRequests,
        address _stakePoolManager,
        address _userWithdrawManager,
        address _ethx
    ) StakingAdaptor(_wrappedNative, _maxRequests) {
        stakePoolManager = IStakePoolManager(_stakePoolManager);
        userWithdrawManager = IUserWithdrawManager(_userWithdrawManager);
        ETHx = ERC20(_ethx);
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
        uint256[] memory requests = StakingAdaptor(adaptorAddress).getRequestIds(account);

        for (uint256 i; i < requests.length; ++i) {
            IUserWithdrawManager.WithdrawRequest memory request = userWithdrawManager.userWithdrawRequests(
                uint256(requests[i])
            );
            amount += request.ethExpected;
        }
    }

    // https://etherscan.io/address/0x9F0491B32DBce587c50c4C43AB303b06478193A7
    function _requestBurn(uint256 amount) internal override returns (uint256 id) {
        ETHx.safeApprove(address(userWithdrawManager), amount);
        id = userWithdrawManager.requestWithdraw(amount, address(this));
        _revokeExternalApproval(ETHx, address(userWithdrawManager));
    }

    function _completeBurn(uint256 id) internal override {
        userWithdrawManager.claim(id);
    }
}
