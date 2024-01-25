// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";
import { IRestakeManager } from "src/interfaces/external/IStaking.sol";

/**
 * @title Renzo Staking Adaptor
 * @notice Allows Cellars to stake with Renzo.
 * @author crispymangoes
 */
contract RenzoStakingAdaptor is StakingAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    /**
     * @notice The Renzo contract staking calls are made to.
     */
    IRestakeManager public immutable restakeManager;

    constructor(
        address _wrappedNative,
        uint8 _maxRequests,
        address _restakeManager
    ) StakingAdaptor(_wrappedNative, _maxRequests) {
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

    /**
     * @notice Stakes into Renzo using native asset.
     */
    function _mint(uint256 amount) internal override {
        restakeManager.depositETH{ value: amount }();
    }
}
