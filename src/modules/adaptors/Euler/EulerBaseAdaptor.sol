// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;
import { Math } from "src/utils/Math.sol";
import { IEulerMarkets, IEulerExec } from "src/interfaces/external/IEuler.sol";

/**
 * @title Euler Base Adaptor
 * @notice Implements shared logic/constants between EulerETokenAdaptor and EulerDebtTokenAdaptor.
 * @author crispymangoes
 */
contract EulerBaseAdaptor {
    using Math for uint256;

    /**
     * @notice Attempted to use an invalid subAccountId.
     */
    error EulerETokenAdaptor__InvalidSubAccountId();

    //============================================ Global Functions ===========================================

    /**
     * @notice The Euler Markets contract on Ethereum Mainnet.
     */
    function markets() internal pure returns (IEulerMarkets) {
        return IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    }

    /**
     * @notice The Euler Exec contract on Ethereum Mainnet.
     */
    function exec() internal pure returns (IEulerExec) {
        return IEulerExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);
    }

    /**
     * @notice The Euler contract on Ethereum Mainnet.
     */
    function euler() internal pure returns (address) {
        return 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    }

    /**
     * @notice Minimum HF enforced after every eToken withdraw/market exit.
     *         Also enforced when borrowing assets.
     */
    function HFMIN() internal pure returns (uint256) {
        return 1.1e18;
    }

    /**
     * @notice Calculate the `target`s health factor.
     * @dev Returns type(uint256).max if there is no outstanding debt.
     */
    function _calculateHF(address target) internal view returns (uint256) {
        IEulerExec.LiquidityStatus memory status = exec().liquidity(target);

        // If target has no debt, report type(uint256).max.
        if (status.liabilityValue == 0) return type(uint256).max;

        // Else calculate actual health factor.
        return status.collateralValue.mulDivDown(1e18, status.liabilityValue);
    }

    /**
     * @notice Helper function to compute the sub account address given the primary account, and sub account Id.
     */
    function _getSubAccount(address primary, uint256 subAccountId) internal pure returns (address) {
        if (subAccountId >= 256) revert EulerETokenAdaptor__InvalidSubAccountId();
        return address(uint160(primary) ^ uint160(subAccountId));
    }
}
