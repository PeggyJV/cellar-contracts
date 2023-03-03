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
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
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
     * @notice This position is a debt position, and user withdraws are not allowed so
     *         this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellars balance of the positions debtToken.
     */
    function balanceOf(bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the positions debtToken underlying asset.
     */
    function assetOf(bytes memory) public pure override returns (ERC20) {
        return ERC20(address(0));
    }

    /**
     * @notice This adaptor reports values in terms of debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Strategists are free to update their cellar's performance fee as they see fit.
     *         Ultimately the compeition between strategists will keep this in check, since
     *         a strategist could out perform another strategist simply because they take a smaller fee.
     */
    function updatePerformanceFee(FeesAndReserves feesAndReserves, uint32 performanceFee) public {
        feesAndReserves.updatePerformanceFee(performanceFee);
    }

    function updateManagementFee(FeesAndReserves feesAndReserves, uint32 managementFee) public {
        feesAndReserves.updateManagementFee(managementFee);
    }

    function changeUpkeepFrequency(FeesAndReserves feesAndReserves, uint64 newFrequency) public {
        feesAndReserves.changeUpkeepFrequency(newFrequency);
    }

    function changeUpkeepMaxGas(FeesAndReserves feesAndReserves, uint64 newMaxGas) public {
        feesAndReserves.changeUpkeepMaxGas(newMaxGas);
    }

    function setupMetaData(
        FeesAndReserves feesAndReserves,
        uint32 targetAPR,
        uint32 performanceFee
    ) public {
        feesAndReserves.setupMetaData(targetAPR, performanceFee);
    }

    /**
     * @notice Strategists are free to add/remove assets to reserves because it allows them to
     *         inject yield into the cellar during time of under performance, and reserve yield
     *         during times of over performance.
     *         This allows strategists to push actual APR towards the target, and also facilitates
     *         taking performance fees without dilluting share price
     */
    function addAssetsToReserves(FeesAndReserves feesAndReserves, uint256 amount) public {
        (ERC20 asset, , , , , , , , , ) = feesAndReserves.metaData(Cellar(address(this)));
        asset.safeApprove(address(feesAndReserves), amount);
        feesAndReserves.addAssetsToReserves(amount);
    }

    function withdrawAssetsFromReserves(FeesAndReserves feesAndReserves, uint256 amount) public {
        feesAndReserves.withdrawAssetsFromReserves(amount);
    }

    function prepareFees(FeesAndReserves feesAndReserves, uint256 amount) public {
        feesAndReserves.prepareFees(amount);
    }
}
