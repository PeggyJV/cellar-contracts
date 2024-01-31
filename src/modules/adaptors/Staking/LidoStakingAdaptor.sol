// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";
import { IUNSTETH, IWSTETH, ISTETH } from "src/interfaces/external/IStaking.sol";

/**
 * @title Lido Staking Adaptor
 * @notice Allows Cellars to stake with Lido.
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

    /**
     * @notice Stakes into Lido using native asset.
     */
    function _mint(uint256 amount) internal override returns (uint256 amountOut) {
        ERC20 derivative = ERC20(address(stETH));
        amountOut = derivative.balanceOf(address(this));
        stETH.submit{ value: amount }(address(0));
        amountOut = derivative.balanceOf(address(this)) - amountOut;
    }

    /**
     * @notice Wrap stETH.
     */
    function _wrap(uint256 amount) internal override returns (uint256 amountOut) {
        ERC20 derivative = ERC20(address(stETH));
        amount = _maxAvailable(derivative, amount);
        derivative.safeApprove(address(wstETH), amount);
        amountOut = wstETH.wrap(amount);
        _revokeExternalApproval(derivative, address(wstETH));
    }

    /**
     * @notice Unwrap wstETH.
     */
    function _unwrap(uint256 amount) internal override returns (uint256 amountOut) {
        amount = _maxAvailable(ERC20(address(wstETH)), amount);
        amountOut = wstETH.unwrap(amount);
    }

    // TODO so I dont really get the math in WithdrawQueueBase.sol Line 484
    // https://etherscan.deth.net/address/0xe42c659dc09109566720ea8b2de186c2be7d94d9
    // It seems like a safe estimation to say 1 stETH is 1 ETH, but this logic is doing
    // a whole bunch of stuff with check points and hints, which we really wouldn't be able to
    // provide hints since this needs to be called in balance of.
    /**
     * @notice Returns balance in pending and finalized withdraw requests.
     * @dev This function assumes that the primitive and derivative asset are 1:1.
     */
    function _balanceOf(address account) internal view override returns (uint256 amount) {
        uint256[] memory requests = StakingAdaptor(adaptorAddress).getRequestIds(account);
        IUNSTETH.WithdrawalRequestStatus[] memory statuses = unstETH.getWithdrawalStatus(requests);
        for (uint256 i; i < statuses.length; ++i) {
            // If request was already claimed continue.
            if (statuses[i].isClaimed) continue;
            amount += statuses[i].amountOfStETH;
        }
    }

    /**
     * @notice Request to withdraw.
     */
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

    /**
     * @notice Complete a withdraw.
     */
    function _completeBurn(uint256 id) internal override {
        unstETH.claimWithdrawal(id);
    }

    /**
     * @notice Remove a request from requestIds if it is already claimed.
     */
    function removeClaimedRequest(uint256 id) external override {
        uint256[] memory requests = new uint256[](1);
        requests[0] = id;
        IUNSTETH.WithdrawalRequestStatus[] memory statuses = unstETH.getWithdrawalStatus(requests);
        if (statuses[0].isClaimed) StakingAdaptor(adaptorAddress).removeRequestId(id);
        else revert StakingAdaptor__RequestNotClaimed(id);
    }
}
