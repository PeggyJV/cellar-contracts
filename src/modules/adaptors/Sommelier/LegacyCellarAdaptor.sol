// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

/**
 * @title Legacy Cellar Adaptor
 * @notice Allows Cellars to interact with other Cellar positions.
 * @dev Uses Share Price Oracle if available.
 * @author crispymangoes
 */
contract LegacyCellarAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(Cellar cellar, ERC4626SharePriceOracle oracle)
    // Where:
    // `cellar` is the underling Cellar this adaptor is working with
    // `oracle` is the underling Cellar oracle this adaptor is working with
    //================= Configuration Data Specification =================
    // NA
    //============================= NOTE =================================
    // Contract is illiquid because using a share price oracle to estimate
    // the balance of the position will be very accurate, but not
    // perfect. By making it illiquid, the Cellar share price will only
    // feel the difference of oracle share price compared to actual
    // when the strategist enters or exists the position.
    // Otherwise user deposits/withdraws would alter this Cellars share price.
    //====================================================================

    /**
     * @notice Strategist attempted to interact with a Cellar with no position setup for it.
     */
    error LegacyCellarAdaptor__CellarPositionNotUsed(address cellar);

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Sommelier Legacy Cellar Use Oracle Adaptor V 0.0"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice User deposits are not allowed.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are not allowed.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice Position is not liquid
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Uses ERC4626 Share Price Oracle or `previewRedeem` to determine Cellars balance in Cellar position.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (Cellar cellar, ERC4626SharePriceOracle oracle) = abi.decode(adaptorData, (Cellar, ERC4626SharePriceOracle));

        uint256 balance = cellar.balanceOf(msg.sender);

        (uint256 latest, bool isNotSafeToUse) = oracle.getLatestAnswer();
        // If oracle is not safe to use, default to calculating share price on chain.
        if (!isNotSafeToUse) {
            balance = balance.mulDivDown(latest, 10 ** oracle.decimals());
            // Convert balance from share decimals to asset decimals.
            return balance.changeDecimals(cellar.decimals(), cellar.asset().decimals());
        } else return cellar.previewRedeem(balance);
    }

    /**
     * @notice Returns the asset the Cellar position uses.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        Cellar cellar = abi.decode(adaptorData, (Cellar));
        return cellar.asset();
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategists to deposit into Cellar positions.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param cellar the Cellar to deposit `assets` into
     * @param assets the amount of assets to deposit into `cellar`
     */
    function depositToCellar(Cellar cellar, uint256 assets, address oracle) public {
        _verifyCellarPositionIsUsed(address(cellar), oracle);
        ERC20 asset = cellar.asset();
        assets = _maxAvailable(asset, assets);
        asset.safeApprove(address(cellar), assets);
        cellar.deposit(assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(asset, address(cellar));
    }

    /**
     * @notice Allows strategists to withdraw from Cellar positions.
     * @param cellar the Cellar to withdraw `assets` from
     * @param assets the amount of assets to withdraw from `cellar`
     */
    function withdrawFromCellar(Cellar cellar, uint256 assets, address oracle) public {
        _verifyCellarPositionIsUsed(address(cellar), oracle);
        if (assets == type(uint256).max) assets = cellar.maxWithdraw(address(this));
        cellar.withdraw(assets, address(this), address(this));
    }

    //============================================ Helper Functions ===========================================

    /**
     * @notice Reverts if a given `cellar` is not set up as a position in the calling Cellar.
     * @dev This function is only used in a delegate call context, hence why address(this) is used
     *      to get the calling Cellar.
     */
    function _verifyCellarPositionIsUsed(address cellar, address oracle) internal view {
        // Check that cellar position is setup to be used in the cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(cellar, oracle)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert LegacyCellarAdaptor__CellarPositionNotUsed(cellar);
    }
}
