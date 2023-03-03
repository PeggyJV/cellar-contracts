// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, SwapRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";

/**
 * @title Fees And Reserves Adaptor
 * @notice Allows Cellars to interact with Sommelier FeesAndReserves contract
 *         in order to store/withdraw reserves and take fees.
 * @author crispymangoes
 */
contract FeesAndReservesAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // NOT USED
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has NO underlying position, its only purpose is to
    // expose the expose Fees And Reserves to strategists during rebalances.
    //====================================================================

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Fees And Reserves Adaptor V 0.0"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed.
     */
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed.
     */
    function withdraw(
        uint256,
        address,
        bytes memory,
        bytes memory
    ) public pure override {
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

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Strategists are free to update their cellar's performance fee as they see fit.
     *         Ultimately the competition between strategists will keep this in check, since
     *         a strategist could out perform another strategist simply because they take a smaller fee.
     */
    function updatePerformanceFee(FeesAndReserves feesAndReserves, uint32 performanceFee) public {
        feesAndReserves.updatePerformanceFee(performanceFee);
    }

    /**
     * @notice Strategists are free to update their cellar's management fee as they see fit.
     *         Ultimately the competition between strategists will keep this in check, since
     *         a strategist could out perform another strategist simply because they take a smaller fee.
     */
    function updateManagementFee(FeesAndReserves feesAndReserves, uint32 managementFee) public {
        feesAndReserves.updateManagementFee(managementFee);
    }

    /**
     * @notice Allows strategist to change how frequently they want their cellars fees calculated.
     */
    function changeUpkeepFrequency(FeesAndReserves feesAndReserves, uint64 newFrequency) public {
        feesAndReserves.changeUpkeepFrequency(newFrequency);
    }

    /**
     * @notice Allows strategist to change the max gas they are willing to pay for fee calculations..
     */
    function changeUpkeepMaxGas(FeesAndReserves feesAndReserves, uint64 newMaxGas) public {
        feesAndReserves.changeUpkeepMaxGas(newMaxGas);
    }

    /**
     * @notice Setup function strategist must call in order to use FeesAndReserves.
     */
    function setupMetaData(
        FeesAndReserves feesAndReserves,
        uint32 managementFee,
        uint32 performanceFee
    ) public {
        feesAndReserves.setupMetaData(managementFee, performanceFee);
    }

    /**
     * @notice Strategists are free to add/remove assets to reserves because it allows them to
     *         inject yield into the cellar during time of under performance, and reserve yield
     *         during times of over performance.
     */
    function addAssetsToReserves(FeesAndReserves feesAndReserves, uint256 amount) public {
        (ERC20 asset, , , , , , , , , ) = feesAndReserves.metaData(Cellar(address(this)));
        asset.safeApprove(address(feesAndReserves), amount);
        feesAndReserves.addAssetsToReserves(amount);
    }

    /**
     * @notice Strategists are free to add/remove assets to reserves because it allows them to
     *         inject yield into the cellar during time of under performance, and reserve yield
     *         during times of over performance.
     */
    function withdrawAssetsFromReserves(FeesAndReserves feesAndReserves, uint256 amount) public {
        feesAndReserves.withdrawAssetsFromReserves(amount);
    }

    /**
     * @notice Allows strategists to take pending fees owed, and set them up to be distributed using `sendFees` in FeesAndReserves contract.
     */
    function prepareFees(FeesAndReserves feesAndReserves, uint256 amount) public {
        feesAndReserves.prepareFees(amount);
    }
}
