// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20 } from "src/modules/adaptors/BaseAdaptor.sol";

/**
 * @title Positionless Adaptor
 * @notice Implements Base Functions for positionless adaptors.
 * @author crispymangoes
 */
abstract contract PositionlessAdaptor is BaseAdaptor {
    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice There is no underlying position so return zero.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice There is no underlying position so return zero.
     */
    function balanceOf(bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice There is no underlying position so return zero address.
     */
    function assetOf(bytes memory) public pure override returns (ERC20) {
        return ERC20(address(0));
    }

    /**
     * @notice There is no underlying position so return false.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }
}
