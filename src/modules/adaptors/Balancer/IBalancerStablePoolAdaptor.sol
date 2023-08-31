// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SingleSwap, JoinPoolRequest, SwapKind, FundManagement, ExitPoolRequest } from "src/interfaces/external/Balancer/IVault.sol";

/**
 * @title IBalancerPoolAdaptor
 * @author crispymangoes, 0xEinCodes
 * @notice An interface outlining the functions needed for a stable pool adaptor between an ERC4626 vault and Balancer Stable Pools. The general architecture is to be used for other types of Balancer Pools in separate adaptors (ex. WeightedPoolAdaptor, etc.)
 * @dev Example of implementation used in Sommelier protocol found here: https://github.com/PeggyJV/cellar-contracts/blob/main/src/modules/adaptors/Balancer/BalancerPoolAdaptor.sol && tests here: https://github.com/PeggyJV/cellar-contracts/blob/main/test/testAdaptors/BalancerPoolAdaptor.t.sol
 * NOTE: A full yield aggregator protocol or any others using ERC 4626 vaults will likely need to keep track of pricing of BPTs wrt a base asset. This aspect is left up to the respective protocol to design and implement. Pricing examples using the Sommelier protocol pricing architecture are outlined to illustrate pricing the various types of BPTs.
 * NOTE: This adaptor and pricing derivatives focus on stablepool BPTs
 */
interface IBalancerStablePoolAdaptor {

    /**
     * @notice Allows strategists to join Balancer pools using EXACT_TOKENS_IN_FOR_BPT_OUT joins.
     * @dev `swapsBeforeJoin` MUST match up with expected token array returned from `_getPoolTokensWithNoPremintedBpt`.
     *      IE if the first token in expected token array is DAI, the first swap in `swapsBeforeJoin` MUST be for DAI.
     * @dev Implementation logic to likely include pricing mechanic that checks for slippage and is often custom to the respective yield protocol or project.
     * @param targetBpt The specified Balancer Pool to join
     * @param swapsBeforeJoin Data for a single swap executed by `swap` as specified by struct SingleSwap (see IVault.sol)
     * @param swapData Information pertaining to aspects including minAmountsForSwaps, and swapDeadlines
     * @param minimumBpt Minimum BPT to be included in request encoded data.
     * NOTE: Max Available logic IS supported.
     */
    function joinPool(
        ERC20 targetBpt,
        IVault.SingleSwap[] memory swapsBeforeJoin,
        SwapData memory swapData,
        uint256 minimumBpt
    ) external
    
    /**
     * @notice Allows strategists to exit Balancer pools using any exit.
    //  * @dev The amounts in `swapsAfterExit` are overwritten by the actual amount out received from the swap.
     * @dev `swapsAfterExit` MUST match up with expected token array returned from `_getPoolTokensWithNoPremintedBpt`.
     *      IE if the first token in expected token array is BB A DAI, the first swap in `swapsBeforeJoin` MUST be to
     *      swap BB A DAI.
     * @dev Implementation logic to likely include pricing mechanic that checks for slippage and is often custom to the respective yield protocol or project.
     * @param targetBpt The specified Balancer Pool to exit
     * @param swapsAfterExit Data for a single swap executed by `swap` as specified by struct SingleSwap
     * @param swapData Information pertaining to aspects including minAmountsForSwaps, and swapDeadlines
     * @param request ExitPoolRequest Struct containing assets involved, minAmountsOut, userData, and whether internalBalances are used (see IVault.sol)
     * NOTE: Max Available logic IS NOT supported.
     */
    function exitPool(
        ERC20 targetBpt,
        IVault.SingleSwap[] memory swapsAfterExit,
        SwapData memory swapData,
        IVault.ExitPoolRequest memory request
    ) external;

    /**
     * @notice stake (deposit) BPTs into respective pool gauge
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     * @dev Will likely validate that the `_bpt` and `_liquidityGauge` are trusted and in use with the respective yield protocol/project. Revocation of approvals needed too at end of transaction to protect respective ERC4626 vault.
     * @param _bpt address of BPTs to stake
     * @param _liquidityGauge Balancer gauge to deposit (stake) BPTs into.
     * @param _amountIn number of BPTs to stake.
     */
    function stakeBPT(ERC20 _bpt, address _liquidityGauge, uint256 _amountIn) external;

    /**
     * @notice unstake (withdraw) BPT from respective pool gauge
     * @dev Will likely validate that the `_bpt` and `_liquidityGauge` are trusted and in use with the respective yield protocol/project. Revocation of approvals needed too at end of transaction to protect respective ERC4626 vault.
     * @param _bpt address of BPTs to unstake.
     * @param _liquidityGauge Balancer gauge to withdraw (unstake) BPTs into.
     * @param _amountOut number of BPTs to unstake
     * @dev Custom interface required as Balancer/Curve do not provide an interface for liquidityGauges.
     */
    function unstakeBPT(ERC20 _bpt, address _liquidityGauge, uint256 _amountOut) external;

    /**
     * @notice claim rewards ($BAL) from LP position
     * @dev rewards are only accrued for staked positions
     * @param gauge Balancer gauge to claim rewards from.
     */
    function claimRewards(address gauge) external;

    /**
     * @notice Start a flash loan using Balancer.
     * @param tokens specified IERC20 tokens to loan
     * @param amounts number of respective ERC20s to flash loan
     * @param data TODO: check w/ Crispy what this data is --> see https://etherscan.deth.net/address/0xBA12222222228d8Ba445958a75a0704d566BF2C8
     */
    function makeFlashLoan(IERC20[] memory tokens, uint256[] memory amounts, bytes memory data) external;
}
