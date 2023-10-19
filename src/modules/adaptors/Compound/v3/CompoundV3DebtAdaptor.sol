// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IFToken } from "src/interfaces/external/Frax/IFToken.sol";
import { FraxlendHealthFactorLogic } from "src/modules/adaptors/Frax/FraxlendHealthFactorLogic.sol";
import { CometInterface } from "src/interfaces/external/Compound/CometInterface.sol";
import { CompoundV3ExtraLogic } from "src/modules/adaptors/Compound/v3/CompoundV3ExtraLogic.sol";

/**
 * @title CompoundV3 Debt Token Adaptor
 * @notice Allows Cellars to borrow assets from CompoundV3 Lending Markets.
 * @author crispymangoes, 0xEinCodes
 * NOTE: In efforts to keep the smart contracts simple, the three main services for accounts with CompoundV3; supplying `BaseAssets`, supplying `Collateral`, and `Borrowing` against `Collateral` are isolated to three separate adaptor contracts. Therefore, repayment of open `borrow` positions are done within this adaptor, and cannot be carried out through the use of `CompoundV3SupplyAdaptor`.
 */
contract CompoundV3DebtAdaptor is BaseAdaptor, CompoundV3ExtraLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address compMarket)
    // Where:
    // `compMarket` is the CompoundV3 Lending Market address that this adaptor is working with
    //================= Configuration Data Specification =================
    // NA
    //
    //====================================================================

    /**
     * @notice Attempted tx that results in unhealthy cellar
     */
    error CompoundV3DebtAdaptor_HealthFactorTooLow(address compMarket);

    /**
     * @notice Attempted repayment when no debt position in compMarket for cellar
     */
    error CompoundV3DebtAdaptor_CannotRepayNoDebt(address compMarket);

    /**
     * @notice
     */
    error CompoundV3DebtAdaptor_NotEnoughCollateralToBorrow(address compMarket);

    /**
     * @notice This bool determines how this adaptor accounts for interest.
     *         True: Account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     *         False: Do not account for pending interest to be paid when calling `balanceOf` or `withdrawableFrom`.
     */
    bool public immutable ACCOUNT_FOR_INTEREST;

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(bool _accountForInterest, uint256 _healthFactor) CompoundV3ExtraLogic(_healthFactor) {
        _verifyConstructorMinimumHealthFactor(_healthFactor);
        ACCOUNT_FOR_INTEREST = _accountForInterest;
        minimumHealthFactor = _healthFactor;
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("CompoundV3 DebtToken Adaptor V 1.0"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are NOT allowed into this position.
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     */
    function withdraw(uint256, address, bytes memory, bytes memory) public pure override {
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
     * @notice Returns the cellar's balance of the respective CompoundV3 Lending Market debtToken (`baseAsset`)
     * @param adaptorData the CompMarket and Asset combo the Cellar position corresponds to
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        CometInterface compMarket = abi.decode(adaptorData, (CometInterface));

        _validateCompMarket(compMarket);

        return compMarket.borrowBalanceOf(address(this)); // RETURNS: The balance of the base asset, including interest, borrowed by the specified account as an unsigned integer scaled up by 10 to the “decimals” integer in the asset’s contract. TODO: assess how we need to work with this return value, decimals-wise.
    }

    /**
     * @notice Returns `assetContract` from respective fraxlend pair, but this is most likely going to be FRAX.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        CometInterface compMarket = abi.decode(adaptorData, CometInterface);
        return ERC20(compMarket.baseToken());
    }

    /**
     * @notice This adaptor reports values in terms of debt.
     */
    function isDebt() public pure override returns (bool) {
        return true;
    }

    //============================================ Strategist Functions ===========================================

    // `borrowAsset`
    /**
     * @notice Allows strategists to borrow assets from CompoundV3 Lending Market.
     * @param _compMarket The specified CompoundV3 Lending Market
     * @param amountToBorrow the amount of `baseAsset` to borrow on respective compMarket
     * NOTE: need to take the higher value btw minBorrowAmount and amountToBorrow or else will revert
     */
    function borrowFromCompoundV3(CometInterface _compMarket, uint256 amountToBorrow) public {
        _validateCompMarket(_compMarket);
        int liquidity = _checkLiquidity(_compMarket);
        if (liquidity < 0) revert CompoundV3DebtAdaptor_NotEnoughCollateralToBorrow(address(_compMarket));
        ERC20 baseToken = ERC20(_compMarket.baseToken());

        if (amountToBorrow == type(uint256).max) {
            amountToBorrow = uint256(liquidity); // liquidity, if a positive int, is the total amount of baseAsset borrowable from lending market for this respective account (cellar) atm
        }
        // query compMarket to assess minBorrowAmount
        uint256 minBorrowAmount = uint256((_compMarket.getConfiguration(_compMarket)).baseBorrowMin); // see `CometConfiguration.sol` for `struct Configuration`

        amountToBorrow = minBorrowAmount > amountToBorrow ? minBorrowAmount : amountToBorrow;

        // TODO: see how Compound handles a request for withdrawal but all of the baseAsset is being supplied. IIRC they give you what they have or revert... and they increase the supply APY exponentially to get enough to meet withdrawals. 
        _compMarket.withdraw(address(baseToken), amountToBorrow);

        // Check if borrower is insolvent after this borrow tx, revert if they are
        if (_checkLiquidity(_compMarket) < 0) revert CompoundV3DebtAdaptor_HealthFactorTooLow(address(_compMarket));
    }

    // `repayDebt`

    /**
     * @notice Allows strategists to repay loan debt on CompoundV3 Lending Market.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param _compMarket the Fraxlend Pair to repay debt from.
     * @param _debtTokenRepayAmount the amount of `debtToken` (`baseAsset`) to repay with.
     */
    function repayCompoundV3Debt(CometInterface _compMarket, uint256 _debtTokenRepayAmount) public {
        _validateCompMarket(_compMarket);

        uint256 debtToRepayAccCompoundV3 = _compMarket.borrowBalanceOf(address(this));
        if (debtToRepayAccCompoundV3 == 0) revert CompoundV3DebtAdaptor_CannotRepayNoDebt(address(_compMarket));

        ERC20 baseToken = ERC20(compMarket.baseToken());
        _debtTokenRepayAmount = _maxAvailable(baseToken, _debtTokenRepayAmount); // TODO: check what happens when one tries to repay more than what they owe in CompoundV3, and what happens if they try to repay on an account that shows zero for their collateral, or for their loan?

        _debtTokenRepayAmount = debtToRepayAccCompoundV3 < _debtTokenRepayAmount
            ? debtToRepayAccCompoundV3
            : _debtTokenRepayAmount;

        baseToken.safeApprove(address(_compMarket), type(uint256).max);

        // finally repay debt
        _compMarket.supply(address(baseToken), _debtTokenRepayAmount);

        _revokeExternalApproval(tokenToRepay, address(_compMarket));
    }
}
