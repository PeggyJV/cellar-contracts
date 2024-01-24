// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";

interface LiquidityPool {
    function deposit() external payable;

    function requestWithdraw(address recipient, uint256 amount) external returns (uint256);
}

/**
 * @title 0x Adaptor
 * @notice Allows Cellars to swap with 0x.
 * @author crispymangoes
 */
contract EtherFiStakingAdaptor is StakingAdaptor {
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
        // https://etherscan.io/address/0x308861a430be4cce5502d0a12724771fc6daf216
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
    function _requestBurn(uint256 amount) internal override returns (uint256 id) {
        // TODO Call requestWithdraw
        // https://etherscan.io/address/0x308861a430be4cce5502d0a12724771fc6daf216
    }

    function _completeBurn(uint256 id) internal override {
        // TODO call claim
    }
}
