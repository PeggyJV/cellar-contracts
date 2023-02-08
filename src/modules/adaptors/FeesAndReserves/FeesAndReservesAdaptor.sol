// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, SwapRouter, Registry, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";

/**
 * @title Euler debtToken Adaptor
 * @notice Allows Cellars to interact with Euler debtToken positions.
 * @author crispymangoes
 */
contract FeesAndReservesAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(IEulerDToken dToken, uint256 subAccountId)
    // Where:
    // `dToken` is the Euler debt token address position this adaptor is working with
    // `subAccountId` is the sub account id the position uses
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    /**
     @notice Attempted borrow would lower Cellar health factor too low.
     */
    error EulerDebtTokenAdaptor__HealthFactorTooLow();

    /**
     * @notice Attempted to use an invalid subAccountId.
     */
    error EulerDebtTokenAdaptor__InvalidSubAccountId();

    /**
     * @notice Strategist attempted to open an untracked Euler loan.
     * @param untrackedDebtPosition the address of the untracked loan
     */
    error EulerDebtTokenAdaptor__DebtPositionsMustBeTracked(address untrackedDebtPosition);

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

    /**
     * @notice Minimum HF enforced after every eToken borrows/self borrows.
     * @dev A low `HFMIN` is required for strategist to run leveraged strategies,
     *      where the collateral and borrow token are the same.
     *      This does pose a risk of strategists intentionally making their Cellar vulnerable to liquidation
     *      but this is mitigated because of the following
     *      - Euler liquidations are gradual, and increase in size as the position becomes worse, so even if
     *        a Cellar's health factor is slightly below 1, the value lost from liquidation is much less
     *        compared to an Aave or Compound liquidiation
     *      - Given that the MEV liquidation space is so competitive it is extremely unlikely that a strategist
     *        would be able to consistently be the one liquidating the Cellar.
     *      - If a Cellar is constantly being liquidated because of a malicious strategist intentionally lowering the HF,
     *        users will leave the Cellar, and the strategist will lose future recurring income.
     */
    function HFMIN() internal pure returns (uint256) {
        return 1.01e18;
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
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the positions debtToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
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

    /**
     * @notice Strategists are free to update their cellar's target APR as they see fit.
     *         By accurately and regularly updating this value to refect the cellars actual APR,
     *         strategists maximize their fees.
     */
    function updateTargetAPR(FeesAndReserves feesAndReserves, uint32 targetAPR) public {
        feesAndReserves.updateTargetAPR(targetAPR);
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
        feesAndReserves.addAssetsToReserves(amount);
    }

    function withdrawAssetsFromReserves(FeesAndReserves feesAndReserves, uint256 amount) public {
        feesAndReserves.withdrawAssetsFromReserves(amount);
    }

    function prepareFees(FeesAndReserves feesAndReserves, uint256 amount) public {
        feesAndReserves.prepareFees(amount);
    }

    function logFees(FeesAndReserves feesAndReserves) public {
        feesAndReserves.logFees();
    }
}
