// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";
import { IStakePoolManager, IUserWithdrawManager } from "src/interfaces/external/IStaking.sol";

/**
 * @title Stader Staking Adaptor
 * @notice Allows Cellars to stake with Stader.
 * @author crispymangoes
 */
contract StaderStakingAdaptor is StakingAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    /**
     * @notice The Stader contract staking calls are made to.
     */
    IStakePoolManager public immutable stakePoolManager;

    /**
     * @notice The Stader contract withdraw requests are made to.
     */
    IUserWithdrawManager public immutable userWithdrawManager;

    /**
     * @notice The asset returned from staking.
     */
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
        return keccak256(abi.encode("Stader Staking Adaptor V 0.0"));
    }

    //============================================ Override Functions ===========================================

    /**
     * @notice Stakes into Stader using native asset.
     */
    function _mint(uint256 amount) internal override {
        stakePoolManager.deposit{ value: amount }(address(this));
    }

    /**
     * @notice Returns balance in pending and finalized withdraw requests.
     */
    function _balanceOf(address account) internal view override returns (uint256 amount) {
        uint256[] memory requests = StakingAdaptor(adaptorAddress).getRequestIds(account);

        for (uint256 i; i < requests.length; ++i) {
            IUserWithdrawManager.WithdrawRequest memory request = userWithdrawManager.userWithdrawRequests(
                uint256(requests[i])
            );
            amount += request.ethExpected;
        }
    }

    /**
     * @notice Request to withdraw.
     */
    function _requestBurn(uint256 amount) internal override returns (uint256 id) {
        ETHx.safeApprove(address(userWithdrawManager), amount);
        id = userWithdrawManager.requestWithdraw(amount, address(this));
        _revokeExternalApproval(ETHx, address(userWithdrawManager));
    }

    /**
     * @notice Complete a withdraw.
     */
    function _completeBurn(uint256 id) internal override {
        userWithdrawManager.claim(id);
    }
}
