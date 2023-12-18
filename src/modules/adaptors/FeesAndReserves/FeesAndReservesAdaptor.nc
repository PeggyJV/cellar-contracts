// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC20, SafeTransferLib, Cellar, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { PositionlessAdaptor } from "src/modules/adaptors/PositionlessAdaptor.sol";

/**
 * @title Fees And Reserves Adaptor
 * @notice Allows Cellars to interact with Sommelier FeesAndReserves contract
 *         in order to store/withdraw reserves and take fees.
 * @author crispymangoes
 */
contract FeesAndReservesAdaptor is PositionlessAdaptor {
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

    /**
     * @notice The FeesAndReserves contract on the current network.
     * @notice For mainnet use 0xF4279E93a06F9d4b5d0625b1F471AA99Ef9B686b.
     */
    FeesAndReserves public immutable feesAndReserves;

    constructor(address feesAndReservesContract) {
        feesAndReserves = FeesAndReserves(feesAndReservesContract);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Fees And Reserves Adaptor V 1.1"));
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Strategists are free to update their cellar's performance fee as they see fit.
     *         Ultimately the competition between strategists will keep this in check, since
     *         a strategist could out perform another strategist simply because they take a smaller fee.
     */
    function updatePerformanceFee(uint32 performanceFee) public {
        feesAndReserves.updatePerformanceFee(performanceFee);
    }

    /**
     * @notice Strategists are free to update their cellar's management fee as they see fit.
     *         Ultimately the competition between strategists will keep this in check, since
     *         a strategist could out perform another strategist simply because they take a smaller fee.
     */
    function updateManagementFee(uint32 managementFee) public {
        feesAndReserves.updateManagementFee(managementFee);
    }

    /**
     * @notice Allows strategist to change how frequently they want their cellars fees calculated.
     */
    function changeUpkeepFrequency(uint64 newFrequency) public {
        feesAndReserves.changeUpkeepFrequency(newFrequency);
    }

    /**
     * @notice Allows strategist to change the max gas they are willing to pay for fee calculations..
     */
    function changeUpkeepMaxGas(uint64 newMaxGas) public {
        feesAndReserves.changeUpkeepMaxGas(newMaxGas);
    }

    /**
     * @notice Setup function strategist must call in order to use FeesAndReserves.
     */
    function setupMetaData(uint32 managementFee, uint32 performanceFee) public {
        feesAndReserves.setupMetaData(managementFee, performanceFee);
    }

    /**
     * @notice Strategists are free to add/remove assets to reserves because it allows them to
     *         inject yield into the cellar during time of under performance, and reserve yield
     *         during times of over performance.
     */
    function addAssetsToReserves(uint256 amount) public {
        (ERC20 asset, , , , , , , , , ) = feesAndReserves.metaData(Cellar(address(this)));
        amount = _maxAvailable(asset, amount);
        asset.safeApprove(address(feesAndReserves), amount);
        feesAndReserves.addAssetsToReserves(amount);

        // Make sure that `feesAndReserves` has zero allowance to Cellar assets.
        _revokeExternalApproval(asset, address(feesAndReserves));
    }

    /**
     * @notice Strategists are free to add/remove assets to reserves because it allows them to
     *         inject yield into the cellar during time of under performance, and reserve yield
     *         during times of over performance.
     */
    function withdrawAssetsFromReserves(uint256 amount) public {
        feesAndReserves.withdrawAssetsFromReserves(amount);
    }

    /**
     * @notice Allows strategists to take pending fees owed, and set them up to be distributed using `sendFees` in FeesAndReserves contract.
     */
    function prepareFees(uint256 amount) public {
        feesAndReserves.prepareFees(amount);
    }
}
