// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, SwapRouter, Registry } from "src/modules/adaptors/BaseAdaptor.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";

/**
 * @title Balancer Pool Adaptor
 * @notice Allows Cellars to interact with Weighted, Stable, and Linear Balancer Pools (BPs).
 * @author 0xEinCodes
 * TODO: Go through TODOs because this was copied from AaveDebtTokenAdaptor.sol so there are some aspects that need to be definitely replaced/edited. Of course replace imports and everything too as necessary.
 * TODO: stub out implementation code whilst going through the Balancer Docs
 */
contract BalancerPoolAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    //==================== TODO: Adaptor Data Specification ====================
    // adaptorData = abi.encode(address debtToken)
    // Where:
    // `debtToken` is the debtToken address position this adaptor is working with
    // SP NOTE: function assetsUsed() is not needed for this implementation as per convo w/ Crispy and how priceRouter works with this adaptor
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    /**
     @notice Attempted borrow would lower Cellar health factor too low.
     */
    error AaveV3DebtTokenAdaptor__HealthFactorTooLow();

    /**
     * @notice Strategist attempted to open an untracked Aave loan.
     * @param untrackedDebtPosition the address of the untracked loan
     */
    error AaveV3DebtTokenAdaptor__DebtPositionsMustBeTracked(address untrackedDebtPosition);

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this identifier is needed during Cellar Delegate Call Operations, so getting the address of the adaptor is more difficult.
     * @return encoded adaptor identifier
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Balancer Pool Adaptor V 1.0"));
    }

    /**
     * @notice The Balancer Vault contract on Ethereum Mainnet.
     * TODO: change this with respective Balancer objects and vault address
     */
    function comptroller() internal pure returns (Comptroller) {
        return Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
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
     * @notice This position is a liquidity provision (credit) position, and user withdraws are not allowed so this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the cellars balance of the positions debtToken.
     * TODO: make sure it is checking balanceOf && staked tokens
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        address token = abi.decode(adaptorData, (address));
        return ERC20(token).balanceOf(msg.sender);
    }

    /**
     * @notice Returns the positions debtToken underlying asset.
     * TODO: I can't recall if it was this or assetsUsed() that would probably not be needed from chat w/ Crispy. I need to double check this. 
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        return ERC20(token.UNDERLYING_ASSET_ADDRESS());
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     * @return whether adaptor returns debt or not
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to join/exit Balancer pools
     */
    function adjustWeightedBP() public {
        // TODO: see asana for strategist function details
    }

    /**
     * @notice Allows strategists to join/exit Balancer pools
     */
    function adjustStableBP() public {
        // TODO: see asana for strategist function details
    }

    /**
     * @notice Allows strategists to stake BPTs into Balancer gauges
     * TODO: should we include logic to check if it is 80/20 BAL/WETH BPT bc that means we are staking it to earn veBAL?
     */
    function stakeBPT() public {
        // TODO: see asana for strategist function details
    }

    /**
     * @notice Allows strategists to claim rewards (incl. from LP positions & staking)
     * TODO: not sure how agnostic I need to make this
     */
    function claimRewards() public {
        // TODO: see asana for strategist function details
    }
    
    /**
     * @notice Allows strategists to allocate boost amounts
     * TODO: not sure if we need this, and vote allocation may be off-chain IIRC
     */
    function allocateVotes() public {
        // TODO: see asana for strategist function details
    }

  //============================================ TODO: Strategist Functions ===========================================

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
            revert AaveV3DebtTokenAdaptor__DebtPositionsMustBeTracked(address(debtTokenToBorrow));

        // Open up new variable debt position on Aave.
        pool().borrow(
            IAaveToken(address(debtTokenToBorrow)).UNDERLYING_ASSET_ADDRESS(),
            amountToBorrow,
            2,
            0,
            address(this)
        ); // 2 is the interest rate mode, either 1 for stable or 2 for variable

        // Check that health factor is above adaptor minimum.
        (, , , , , uint256 healthFactor) = pool().getUserAccountData(address(this));
        if (healthFactor < HFMIN()) revert AaveV3DebtTokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategists to repay loan debt on Aave.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param tokenToRepay the underlying ERC20 token you want to repay, NOT the debtToken.
     * @param amountToRepay the amount of `tokenToRepay` to repay with.
     */
    function repayAaveDebt(ERC20 tokenToRepay, uint256 amountToRepay) public {
        tokenToRepay.safeApprove(address(pool()), amountToRepay);
        pool().repay(address(tokenToRepay), amountToRepay, 2, address(this)); // 2 is the interest rate mode,  either 1 for stable or 2 for variable

        // Zero out approvals if necessary.
        _revokeExternalApproval(tokenToRepay, address(pool()));
    }

    /**
     * @notice Allows strategist to use aTokens to repay debt tokens with the same underlying.
     */
    function repayWithATokens(ERC20 underlying, uint256 amount) public {
        pool().repayWithATokens(address(underlying), amount, 2);
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
        pool().flashLoan(address(this), loanToken, loanAmount, modes, address(this), params, 0);
    }
}
