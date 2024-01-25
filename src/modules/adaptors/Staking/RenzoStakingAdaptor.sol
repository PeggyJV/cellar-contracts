// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";

interface IRestakeManager {
    function depositETH() external payable;
}

/**
 * @title Renzo Staking Adaptor
 * @notice Allows Cellars to swap with 0x.
 * @author crispymangoes
 */
contract RenzoStakingAdaptor is StakingAdaptor {
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

    IRestakeManager public immutable restakeManager;

    constructor(address _wrappedNative, address _restakeManager) StakingAdaptor(_wrappedNative, 8) {
        restakeManager = IRestakeManager(_restakeManager);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Renzo Staking Adaptor V 1.1"));
    }

    //============================================ Override Functions ===========================================
    // 0x74a09653A083691711cF8215a6ab074BB4e99ef5
    function _mint(uint256 amount) internal override {
        restakeManager.depositETH{ value: amount }();
    }
}
