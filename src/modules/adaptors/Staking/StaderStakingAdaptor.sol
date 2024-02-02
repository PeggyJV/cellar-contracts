// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";
import { IStakePoolManager, IUserWithdrawManager, IStaderConfig } from "src/interfaces/external/IStaking.sol";

/**
 * @title Stader Staking Adaptor
 * @notice Allows Cellars to stake with Stader.
 * @dev Stader supports minting, and burning.
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

    IStaderConfig public immutable staderConfig;

    /**
     * @notice The asset returned from staking.
     */
    ERC20 public immutable ETHx;

    constructor(
        address _wrappedNative,
        uint8 _maxRequests,
        address _stakePoolManager,
        address _userWithdrawManager,
        address _ethx,
        address _staderConfig
    ) StakingAdaptor(_wrappedNative, _maxRequests) {
        stakePoolManager = IStakePoolManager(_stakePoolManager);
        userWithdrawManager = IUserWithdrawManager(_userWithdrawManager);
        ETHx = ERC20(_ethx);
        staderConfig = IStaderConfig(_staderConfig);
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
    function _mint(uint256 amount, bytes calldata) internal override returns (uint256 amountOut) {
        amountOut = ETHx.balanceOf(address(this));
        stakePoolManager.deposit{ value: amount }(address(this));
        amountOut = ETHx.balanceOf(address(this)) - amountOut;
    }

    /**
     * @notice Returns balance in pending and finalized withdraw requests.
     * @dev Calculation uses logic from Line 154 here
     *      https://etherscan.deth.net/address/0x9F0491B32DBce587c50c4C43AB303b06478193A7
     */
    function _balanceOf(address account) internal view override returns (uint256 amount) {
        uint256[] memory requests = StakingAdaptor(adaptorAddress).getRequestIds(account);

        uint256 exchangeRate = stakePoolManager.getExchangeRate();
        uint256 DECIMALS = staderConfig.getDecimals();
        uint256 requestsLength = requests.length;
        for (uint256 i; i < requestsLength; ++i) {
            IUserWithdrawManager.WithdrawRequest memory request = userWithdrawManager.userWithdrawRequests(
                uint256(requests[i])
            );
            if (request.owner != account) continue;
            // If ethFinalized is set, use that value.
            if (request.ethFinalized > 0) amount += request.ethFinalized;
            else {
                // Else calculate request value using current and past rates.
                uint256 ethXValueUsingCurrentExchangeRate = request.ethXAmount.mulDivDown(exchangeRate, DECIMALS);
                amount += request.ethExpected.min(ethXValueUsingCurrentExchangeRate);
            }
        }
    }

    /**
     * @notice Request to withdraw.
     */
    function _requestBurn(uint256 amount, bytes calldata) internal override returns (uint256 id) {
        amount = _maxAvailable(ETHx, amount);
        ETHx.safeApprove(address(userWithdrawManager), amount);
        id = userWithdrawManager.requestWithdraw(amount, address(this));
        _revokeExternalApproval(ETHx, address(userWithdrawManager));
    }

    /**
     * @notice Complete a withdraw.
     */
    function _completeBurn(uint256 id, bytes calldata) internal override {
        userWithdrawManager.claim(id);
    }

    /**
     * @notice Remove a request from requestIds if it is already claimed.
     */
    function removeClaimedRequest(uint256 id, bytes calldata) external override {
        IUserWithdrawManager.WithdrawRequest memory request = userWithdrawManager.userWithdrawRequests(uint256(id));
        if (request.owner != address(this)) StakingAdaptor(adaptorAddress).removeRequestId(id);
        else revert StakingAdaptor__RequestNotClaimed(id);
    }
}
