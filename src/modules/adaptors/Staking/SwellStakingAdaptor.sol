// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, PriceRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { StakingAdaptor, IWETH9 } from "./StakingAdaptor.sol";
import { ISWETH } from "src/interfaces/external/IStaking.sol";

/**
 * @title Swell Staking Adaptor
 * @notice Allows Cellars to stake with Swell.
 * @dev Swell supports minting.
 * @author crispymangoes
 */
contract SwellStakingAdaptor is StakingAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using Address for address;

    /**
     * @notice The swETH contract staking calls are made to.
     */
    ISWETH public immutable swETH;

    constructor(
        address _wrappedNative,
        uint8 _maxRequests,
        address _swETH
    ) StakingAdaptor(_wrappedNative, _maxRequests) {
        swETH = ISWETH(_swETH);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Swell Staking Adaptor V 0.0"));
    }

    //============================================ Override Functions ===========================================

    /**
     * @notice Stakes into Swell using native asset.
     */
    function _mint(uint256 amount, bytes calldata) internal override returns (uint256 amountOut) {
        ERC20 derivative = ERC20(address(swETH));
        amountOut = derivative.balanceOf(address(this));
        swETH.deposit{ value: amount }();
        amountOut = derivative.balanceOf(address(this)) - amountOut;
    }
}
