// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";
import { CompoundV2HelperLogic } from "src/modules/adaptors/Compound/CompoundV2HelperLogic.sol";

/**
 * @title CompoundV2 Debt Token Adaptor
 * @notice Allows Cellars to borrow assets from Compound V2 markets.
 * @author crispymangoes, 0xEinCodes
 * NOTE: CTokenAdaptorV2.sol is used to "enter" CompoundV2 Markets as Collateral Providers. Collateral Provision from a cellar is needed before they can borrow from CompoundV2 using this adaptor.
 */
contract CompoundV2DebtAdaptor is BaseAdaptor, CompoundV2HelperLogic {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //============================================ Notice ===========================================
    // NOTE - `accrueInterest()` seems to be very expensive, public tx. That said it is similar to other lending protocols where it is called for every mutative function call that the CompoundV2 adaptors are implementing. Thus we are leaving it up to the strategist to coordinate as needed in calling it similar to MorphoBlue adaptors and how they can diverge if the contract is not kicked.

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(CERC20 cToken)
    // Where:
    // `cToken` is the cToken position this adaptor is working with
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    /**
     * @notice Strategist attempted to interact with a market that is not listed.
     */
    error CTokenAdaptorV2__MarketNotListed(address market);

    /**
     * @notice Attempted to interact with an market the Cellar is not using.
     */
    error CompoundV2DebtAdaptor__CompoundV2PositionsMustBeTracked(address market);

    /**
     * @notice Attempted tx that results in unhealthy cellar
     */
    error CompoundV2DebtAdaptor__HealthFactorTooLow(address market);

    /**
     * @notice Attempted repayment when no debt position in market for cellar
     */
    error CompoundV2DebtAdaptor__CannotRepayNoDebt(address market);

    /**
     @notice Compound action returned a non zero error code.
     */
    error CompoundV2DebtAdaptor__NonZeroCompoundErrorCode(uint256 errorCode);

    /**
     * @notice The Compound V2 Comptroller contract on current network.
     * @dev For mainnet use 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B.
     */
    Comptroller public immutable comptroller;

    /**
     * @notice Address of the COMP token.
     * @notice For mainnet use 0xc00e94Cb662C3520282E6f5717214004A7f26888.
     */
    ERC20 public immutable COMP;

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

    // NOTE: comptroller is a proxy so there may be times that the implementation is updated, although it is rare and would come up for governance vote.
    constructor(bool _accountForInterest, address _v2Comptroller, address _comp, uint256 _healthFactor) {
        _verifyConstructorMinimumHealthFactor(_healthFactor);
        ACCOUNT_FOR_INTEREST = _accountForInterest;
        comptroller = Comptroller(_v2Comptroller);
        COMP = ERC20(_comp);
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
        return keccak256(abi.encode("CompoundV2 Debt Adaptor V 0.0"));
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
     * @notice Returns the cellar's amount owing (debt) to CompoundV2 market
     * @param adaptorData encoded CompoundV2 market (cToken) for this position
     * NOTE: this queries `borrowBalanceCurrent(address account)` to get current borrow amount per compoundV2 market WITHOUT interest. `borrowBalanceCurrent` calls accrueInterest, so it changes state and thus won't work for this view function. Thus we are using `borrowBalanceStored`. See NOTE at beginning about `accrueInterest()`
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        CErc20 cToken = abi.decode(adaptorData, (CErc20));
        return cToken.borrowBalanceStored(msg.sender);
    }

    /**
     * @notice Returns the underlying asset for respective CompoundV2 market (cToken)
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        CErc20 cToken = abi.decode(adaptorData, (CErc20));
        return ERC20(cToken.underlying());
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
     * @notice Allows strategists to borrow assets from CompoundV2 markets.
     * @param market the CompoundV2 market to borrow from underlying assets from
     * @param amountToBorrow the amount of `debtTokenToBorrow` to borrow on this CompoundV2 market. This is in the decimals of the underlying asset being borrowed.
     */
    function borrowFromCompoundV2(CErc20 market, uint256 amountToBorrow) public {
        _validateMarketInput(address(market));

        // borrow underlying asset from compoundV2
        uint256 errorCode = market.borrow(amountToBorrow);
        if (errorCode != 0) revert CompoundV2DebtAdaptor__NonZeroCompoundErrorCode(errorCode);

        if (minimumHealthFactor > (_getHealthFactor(address(this), comptroller))) {
            revert CompoundV2DebtAdaptor__HealthFactorTooLow(address(market));
        }
    }

    // `repayDebt`

    /**
     * @notice Allows strategists to repay loan debt on CompoundV2 market.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param _market the CompoundV2 market to borrow from underlying assets from
     * @param _debtTokenRepayAmount the amount of `debtToken` to repay with.
     * NOTE: Events should be emitted to show how much debt is remaining
     */
    function repayCompoundV2Debt(CErc20 _market, uint256 _debtTokenRepayAmount) public {
        _validateMarketInput(address(_market));
        ERC20 tokenToRepay = ERC20(_market.underlying());
        uint256 debtTokenToRepay = _maxAvailable(tokenToRepay, _debtTokenRepayAmount);
        tokenToRepay.safeApprove(address(_market), type(uint256).max);

        uint256 errorCode = _market.repayBorrow(debtTokenToRepay);
        if (errorCode != 0) revert CompoundV2DebtAdaptor__NonZeroCompoundErrorCode(errorCode);

        _revokeExternalApproval(tokenToRepay, address(_market));
    }

    /**
     * @notice Helper function that reverts if market is not listed in Comptroller AND checks that it is setup in the Cellar.
     */
    function _validateMarketInput(address _market) internal view {
        (bool isListed, , ) = comptroller.markets(_market);
        if (!isListed) revert CTokenAdaptorV2__MarketNotListed(_market);
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(_market)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert CompoundV2DebtAdaptor__CompoundV2PositionsMustBeTracked(address(_market));
    }
}
