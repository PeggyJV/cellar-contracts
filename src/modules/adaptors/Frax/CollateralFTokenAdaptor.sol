// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IFToken } from "src/interfaces/external/Frax/IFToken.sol";

// bespoke interface to access collateralBalancer getter.
interface ICollateralFToken {
    function userCollateralBalance(address _user) external;
}

/**
 * @title FraxLend Collateral Adaptor
 * @notice Allows addition and removal of collateralAssets to Fraxlend pairs for a Cellar.
 * @author crispymangoes, 0xEinCodes
 */
contract CollateralFTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address fToken)
    // Where:
    // `collateralToken` is the collateralToken address position this adaptor is working with.
    //================= Configuration Data Specification =================
    // N/A because the DebtFTokenAdaptor handles actual deposits and withdrawals.
    // ==================================================================

    /**
     * @notice Attempted to interact with an fToken the Cellar is not using.
     * TODO: rename it to suit this adaptor
     */
    error CollateralFTokenAdaptor__FTokenPositionsMustBeTracked(address fToken);

    /**
     * @notice Removal of collateral causes Cellar LTV to be unhealthy
     */
    error CollateralFTokenAdaptor__LTVTooLow(address fToken);

    /**
     * @notice The FRAX contract on current network.
     * @notice For mainnet use 0x853d955aCEf822Db058eb8505911ED77F175b99e.
     */
    ERC20 public immutable FRAX;

    constructor(address _frax) {
        FRAX = ERC20(_frax);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("FraxLend Collateral fToken Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice User deposits collateralToken to Fraxlend pair
     * @param assets the amount of assets to lend on FraxLend
     * @param adaptorData adaptor data containing the abi encoded fToken
     * @dev configurationData is NOT used
     * TODO: EIN write implementation code for base function
     */
    function deposit(
        uint256 assets,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        // use addCollateral() from fraxlendCore.sol
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     * TODO: EIN write implementation code for base function
     */
    function withdraw(
        uint256,
        address,
        bytes memory,
        bytes memory
    ) public pure override {}

    /**
     * @notice This position is a debt position, and user withdraws are not allowed so
     *         this position must return 0 for withdrawableFrom.
     * TODO: EIN write implementation code for base function
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0; // TODO: see AaveATokenAdaptor for idea of what to do here. Not sure it applies.
    }

    /**
     * @notice Returns the cellar's balance of the collateralAsset position.
     * @param adaptorData the collateral asset deposited into Fraxlend
     * NOTE: CRISPY QUESTION - TODO: confirm that this works... EIN - FraxlendCore doesn't have an interface to access the getter. So we'll have to have it here.
     * TODO: confirm that there is no need to typeCast on the decoded adaptorData when needing address, ERC20 or vice versa.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        ICollateralFToken fToken = ICollateralFToken(abi.decode(adaptorData, (address))); // TODO: CRISPY QUESTION - could change adaptorData to be collateralToken but then it won't be consistent with rest of fraxlend adaptors.
        return fToken.userCollateralBalance(msg.sender) + fToken.collateralContract().balanceOf(msg.sender); // reports balance of collateral provided to protocol.
    }

    /**
     * @notice Returns collateral asset
     */
    function assetOf(bytes memory) public view override returns (ERC20) {
        IFToken fToken = abi.decode(adaptorData, (IFToken));
        return ERC20(fToken.collateralContract());
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to add collateral to the respective cellar position on FraxLend, enabling borrowing.
     * @dev `borrowTokens()` within DebtFTokenAdaptor can increase cellar collateralPosition too. `borrowTokens()` cannot be used without a trusted CollateralFTokenAdaptor position in the same cellar because CollateralFTokenAdaptors track the collateral within a Fraxlend pair. CRISPY QUESTION - See TODO: within DebtFTokenAdaptor regarding this.
     */
    function addCollateral(
        ERC20 _collateralToken,
        uint256 _collateralToDeposit,
        IFToken _fToken
    ) public {
        // _validateFToken(collateralToken); // TODO: CRISPY QUESTION - we could have a validation helper but Fraxlend checks if there is even a collateral position for whomever is attempting to borrow. So it is not necessary unless we want to save Strategists gas during reversions. I have left this here in case I am wrong.
        // amountToDeposit = _maxAvailable(collateralToken, amountToDeposit); // TODO: CRISPY QUESTION - not sure if we want to deposit the max or not by default... It depends if the strategist wants to do uint256.max or not for these cellars.
        address fraxlendPair = address(_fToken);
        _collateralToken.safeApprove(fraxlendPair, _collateralToDeposit);
        _fraxLendPair.addCollateral(_collateralToDeposit, address(this));

        // TODO: CRISPY QUESTION - should we check that the LTV is in a healthy state? Check that the FraxlendCore doesn't already do that.
        // Zero out approvals if necessary.
        _revokeExternalApproval(address(_collateralToken), fraxlendPair);
    }

    /**
     * @notice Allows strategists to remove collateral from the respective cellar position on FraxLend.
     */
    function removeCollateral(
        ERC20 _collateralToken,
        uint256 _collateralAmount,
        IFToken _fToken
    ) public {
        // TODO: I don't think that Fraxlend pairs check whether or not cellar even has a position to start with. So we need to add a check/revert to disallow Strategists from calling this when they have zero collateral in fraxlend pair position

        // remove collateral
        _fToken.removeCollateral(_collateralAmount, address(this));
        (, uint256 _exchangeRate, ) = _fToken._updateExchangeRate(); // need to calculate LTV
        // Check if borrower is insolvent (AKA they have bad LTV), revert if they are
        if (!_isSolvent(address(this), _exchangeRate)) {
            revert CollateralFTokenAdaptor__LTVTooLow(address(_fToken));
        }
    }

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // The Frax Pair interface can slightly change between versions.
    // To account for this, FTokenAdaptors (including debt and collateral adaptors) will use the below internal functions when
    // interacting with Frax Pairs, this way new pairs can be added by creating a
    // new contract that inherits from this one, and overrides any function it needs
    // so it conforms with the new Frax Pair interface.

    // Current versions in use for `FraxLendPair` include v1 and v2.

    // IMPORTANT: This `DebtFTokenAdaptor.sol` is associated to the v2 version of `FraxLendPair`
    // whereas DebtFTokenAdaptorV1 is actually associated to `FraxLendPairv1`.
    // The reasoning to name it like this was to set up the base DebtFTokenAdaptor for the
    // most current version, v2. This is in anticipation that more FraxLendPairs will
    // be deployed following v2 in the near future. When later versions are deployed,
    // then the described inheritance pattern above will be used.
    //===============================================================================

    /**
     * @notice Converts a given number of borrow shares to debtToken amount from specified 'v2' FraxLendPair
     * @dev This is one of the adjusted functions from v1 to v2. ftoken.toBorrowAmount() calls into the respective version (v2 by default) of FraxLendPair
     * @param fToken The specified FraxLendPair
     * @param shares Shares of debtToken
     * @param roundUp Whether to round up after division
     * @param previewInterest Whether to preview interest accrual before calculation
     */
    function _toBorrowAmount(
        IFToken fToken,
        uint256 _shares,
        bool _roundUp,
        bool _previewInterest
    ) internal view virtual returns (uint256) {
        return fToken.toBorrowAmount(_shares, _roundUp, _previewInterest);
    }

    // /**
    //  * @notice Caller calls `addInterest` on specified 'v2' FraxLendPair
    //  * @dev ftoken.addInterest() calls into the respective version (v2 by default) of FraxLendPair
    //  * @param fToken The specified FraxLendPair
    //  * TODO: EIN - confirm if/how we need this
    //  */
    // function _addInterest(IFToken fToken) internal virtual {
    //     fToken.addInterest(false);
    // }

    /// @notice The ```_isSolvent``` function determines if a given borrower is solvent given an exchange rate
    /// @param _borrower The borrower address to check
    /// @param _exchangeRate The exchange rate, i.e. the amount of collateral to buy 1e18 asset
    /// @return Whether borrower is solvent
    /// @dev NOTE: TODO: EIN - mainly copied from `FraxlendPairCore.sol` so this needs reworking in full.
    /// NOTE:  This is not working yet, convert this in a gas efficient manner to work with this adaptor. Not sure about it though...
    function _isSolvent(address _borrower, uint256 _exchangeRate) internal view returns (bool) {
        if (maxLTV == 0) return true;
        uint256 _borrowerAmount = totalBorrow.toAmount(userBorrowShares[_borrower], true); // TODO: Change to have toBorrowAmount helper from our adaptor instead of what is in the fraxlendpair contract itself.
        if (_borrowerAmount == 0) return true;
        uint256 _collateralAmount = userCollateralBalance[_borrower];
        if (_collateralAmount == 0) return false;

        uint256 _ltv = (((_borrowerAmount * _exchangeRate) / EXCHANGE_PRECISION) * LTV_PRECISION) / _collateralAmount;
        return _ltv <= maxLTV;
    }
}
