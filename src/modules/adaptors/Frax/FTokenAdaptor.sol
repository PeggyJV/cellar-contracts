// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IFToken } from "src/interfaces/external/Frax/IFToken.sol";

/**
 * @title FraxLend fToken Adaptor
 * @notice Allows Cellars to lend FRAX to FraxLend markets.
 * @author crispymangoes, eincodes
 */
contract FTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address fToken)
    // Where:
    // `fToken` is the fToken address position this adaptor is working with.
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted to interact with an fToken the Cellar is not using.
     */
    error FTokenAdaptor__FTokenPositionsMustBeTracked(address fToken);

    /**
     * @notice Indicates whether or not we should worry about updating interest
     *         when interacting with FraxLend.
     */
    bool constant ACCOUNT_FOR_INTEREST = true;

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("FraxLend fToken Adaptor V 0.0"));
    }

    /**
     * @notice The FRAX contract on Ethereum Mainnet.
     */
    function FRAX() internal pure returns (ERC20) {
        return ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve fToken to spend its assets, then call deposit to lend its assets.
     * @param assets the amount of assets to lend on FraxLend
     * @param adaptorData adaptor data containining the abi encoded fToken
     * @dev configurationData is NOT used
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to Frax Lend.
        IFToken fToken = abi.decode(adaptorData, (IFToken));
        FRAX().safeApprove(address(fToken), assets);
        _deposit(fToken, assets, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(FRAX(), address(fToken));
    }

    /**
     @notice Cellars must withdraw from FraxLend, then transfer assets to receiver.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from FraxLend
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containing the abi encoded fToken
     * @dev configurationData is NOT used
     */
    function withdraw(uint256 assets, address receiver, bytes memory adaptorData, bytes memory) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        // Withdraw assets from Frax.
        IFToken fToken = abi.decode(adaptorData, (IFToken));
        _withdraw(fToken, assets, receiver, address(this));
    }

    /**
     * @notice Returns the amount of FRAX that can be withdrawn.
     * @dev Compares FRAX supplied to FRAX borrowed to check for liquidity.
     *      - If FRAX balance is greater than liquidity available, it returns the amount available.
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory
    ) public view override returns (uint256 withdrawableFrax) {
        IFToken fToken = abi.decode(adaptorData, (IFToken));
        (uint128 totalFraxSupplied, , uint128 totalFraxBorrowed, , ) = _getPairAccounting(fToken);
        if (totalFraxBorrowed >= totalFraxSupplied) return 0;
        uint256 liquidFrax = totalFraxSupplied - totalFraxBorrowed;
        uint256 fraxBalance = _toAssetAmount(fToken, _balanceOf(fToken, msg.sender), false, ACCOUNT_FOR_INTEREST);
        withdrawableFrax = fraxBalance > liquidFrax ? liquidFrax : fraxBalance;
    }

    /**
     * @notice Returns the cellars balance of the positions FRAX.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        IFToken fToken = abi.decode(adaptorData, (IFToken));
        return _toAssetAmount(fToken, _balanceOf(fToken, msg.sender), false, ACCOUNT_FOR_INTEREST);
    }

    /**
     * @notice Returns FRAX.
     */
    function assetOf(bytes memory) public pure override returns (ERC20) {
        return FRAX();
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategists to lend FRAX on FraxLend.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param fToken the market to lend on FraxLend
     * @param amountToDeposit the amount of Frax to lend on FraxLend
     */
    function lendFrax(IFToken fToken, uint256 amountToDeposit) public {
        _validateFToken(fToken);
        amountToDeposit = _maxAvailable(FRAX(), amountToDeposit);
        FRAX().safeApprove(address(fToken), amountToDeposit);
        _deposit(fToken, amountToDeposit, address(this));

        // Zero out approvals if necessary.
        _revokeExternalApproval(FRAX(), address(fToken));
    }

    /**
     * @notice Allows strategists to redeem Frax shares from FraxLend.
     * @param fToken the market to withdraw from on FraxLend
     * @param amountToRedeem the amount of Frax shares to redeem from FraxLend
     */
    function redeemFraxShare(IFToken fToken, uint256 amountToRedeem) public {
        _validateFToken(fToken);
        amountToRedeem = _maxAvailable(ERC20(address(fToken)), amountToRedeem);

        _redeem(fToken, amountToRedeem, address(this), address(this));
    }

    /**
     * @notice Allows strategists to withdraw FRAX from FraxLend.
     * @dev Used to withdraw an exact amount from Frax Lend.
     *      Use `redeemFraxShare` to withdraw all.
     * @param fToken the market to withdraw from on FraxLend
     * @param amountToWithdraw the amount of FRAX to withdraw from FraxLend
     */
    function withdrawFrax(IFToken fToken, uint256 amountToWithdraw) public {
        _validateFToken(fToken);
        _withdraw(fToken, amountToWithdraw, address(this), address(this));
    }

    /**
     * @notice Validates that a given fToken is set up as a position in the Cellar.
     * @dev This function uses `address(this)` as the address of the Cellar.
     */
    function _validateFToken(IFToken fToken) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(address(fToken))));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert FTokenAdaptor__FTokenPositionsMustBeTracked(address(fToken));
    }

    //============================================ Interface Helper Functions ===========================================
    /**
     * @notice The Frax Pair interface can slightly change between versions.
     *         To account for this, FTokenAdaptors will use the below internal functions when
     *         interacting with Frax Pairs, this way new pairs can be added by creating a
     *         new contract that inherits from this one, and overrides any function it needs
     *         so it conforms with the new Frax Pair interface.
     */

    function _deposit(IFToken fToken, uint256 amount, address receiver) internal virtual {
        fToken.deposit(amount, receiver);
    }

    function _withdraw(IFToken fToken, uint256 assets, address receiver, address owner) internal virtual {
        fToken.withdraw(assets, receiver, owner);
    }

    function _redeem(IFToken fToken, uint256 shares, address receiver, address owner) internal virtual {
        fToken.redeem(shares, receiver, owner);
    }

    function _toAssetAmount(
        IFToken fToken,
        uint256 shares,
        bool roundUp,
        bool previewInterest
    ) internal view virtual returns (uint256) {
        return fToken.toAssetAmount(shares, roundUp, previewInterest);
    }

    function _toAssetShares(
        IFToken fToken,
        uint256 amount,
        bool roundUp,
        bool previewInterest
    ) internal view virtual returns (uint256) {
        return fToken.toAssetShares(amount, roundUp, previewInterest);
    }

    function _balanceOf(IFToken fToken, address user) internal view virtual returns (uint256) {
        return fToken.balanceOf(user);
    }

    function _getPairAccounting(
        IFToken fToken
    )
        internal
        view
        virtual
        returns (
            uint128 totalAssetAmount,
            uint128 totalAssetShares,
            uint128 totalBorrowAmount,
            uint128 totalBorrowShares,
            uint256 totalCollateral
        )
    {
        (totalAssetAmount, totalAssetShares, totalBorrowAmount, totalBorrowShares, totalCollateral) = fToken
            .getPairAccounting();
    }
}
