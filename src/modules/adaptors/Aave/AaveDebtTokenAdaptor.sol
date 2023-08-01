// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, Registry } from "src/modules/adaptors/BaseAdaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";

/**
 * @title Aave debtToken Adaptor
 * @notice Allows Cellars to interact with Aave debtToken positions.
 * @author crispymangoes
 */
contract AaveDebtTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address debtToken)
    // Where:
    // `debtToken` is the debtToken address position this adaptor is working with
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    /**
     @notice Attempted borrow would lower Cellar health factor too low.
     */
    error AaveDebtTokenAdaptor__HealthFactorTooLow();

    /**
     * @notice The Aave V3 Pool contract on current network.
     * @dev For mainnet use 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2.
     */
    IPool public immutable pool;

    /**
     * @notice Minimum Health Factor enforced after every borrow.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(address v2Pool, uint256 minHealthFactor) {
        _verifyConstructorMinimumHealthFactor(minHealthFactor);
        pool = IPool(v2Pool);
        minimumHealthFactor = minHealthFactor;
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Aave debtToken Adaptor V 1.2"));
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
     * @notice Returns the cellars balance of the positions debtToken.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        address token = abi.decode(adaptorData, (address));
        return ERC20(token).balanceOf(msg.sender);
    }

    /**
     * @notice Returns the positions debtToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        return ERC20(token.UNDERLYING_ASSET_ADDRESS());
    }

    /**
     * @notice This adaptor reports values in terms of debt.
     */
    function isDebt() public pure override returns (bool) {
        return true;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Strategist attempted to open an untracked Aave loan.
     * @param untrackedDebtPosition the address of the untracked loan
     */
    error AaveDebtTokenAdaptor__DebtPositionsMustBeTracked(address untrackedDebtPosition);

    /**
     * @notice Allows strategists to borrow assets from Aave.
     * @notice `debtTokenToBorrow` must be the debtToken, NOT the underlying ERC20.
     * @param debtTokenToBorrow the debtToken to borrow on Aave
     * @param amountToBorrow the amount of `debtTokenToBorrow` to borrow on Aave.
     */
    function borrowFromAave(ERC20 debtTokenToBorrow, uint256 amountToBorrow) public {
        // Check that debt position is properly set up to be tracked in the Cellar.
        bytes32 positionHash = keccak256(abi.encode(identifier(), true, abi.encode(address(debtTokenToBorrow))));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert AaveDebtTokenAdaptor__DebtPositionsMustBeTracked(address(debtTokenToBorrow));

        // Open up new variable debt position on Aave.
        pool.borrow(
            IAaveToken(address(debtTokenToBorrow)).UNDERLYING_ASSET_ADDRESS(),
            amountToBorrow,
            2,
            0,
            address(this)
        ); // 2 is the interest rate mode, either 1 for stable or 2 for variable

        // Check that health factor is above adaptor minimum.
        (, , , , , uint256 healthFactor) = pool.getUserAccountData(address(this));
        if (healthFactor < minimumHealthFactor) revert AaveDebtTokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategists to repay loan debt on Aave.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param tokenToRepay the underlying ERC20 token you want to repay, NOT the debtToken.
     * @param amountToRepay the amount of `tokenToRepay` to repay with.
     */
    function repayAaveDebt(ERC20 tokenToRepay, uint256 amountToRepay) public {
        tokenToRepay.safeApprove(address(pool), amountToRepay);
        pool.repay(address(tokenToRepay), amountToRepay, 2, address(this)); // 2 is the interest rate mode,  either 1 for stable or 2 for variable

        // Zero out approvals if necessary.
        _revokeExternalApproval(tokenToRepay, address(pool));
    }

    /**
     * @notice allows strategist to have Cellars take out flash loans.
     * @param loanToken address array of tokens to take out loans
     * @param loanAmount uint256 array of loan amounts for each `loanToken`
     * @dev `modes` is always a zero array meaning that this flash loan can NOT take on new debt positions, it must be paid in full.
     */
    function flashLoan(address[] memory loanToken, uint256[] memory loanAmount, bytes memory params) public {
        require(loanToken.length == loanAmount.length, "Input length mismatch.");
        uint256[] memory modes = new uint256[](loanToken.length);
        pool.flashLoan(address(this), loanToken, loanAmount, modes, address(this), params, 0);
    }
}
