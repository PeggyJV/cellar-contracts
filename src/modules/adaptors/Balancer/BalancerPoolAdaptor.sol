// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {BaseAdaptor, ERC20, SafeTransferLib, Cellar, SwapRouter, Registry, PriceRouter} from "src/modules/adaptors/BaseAdaptor.sol";
import {IBalancerQueries} from "src/interfaces/external/Balancer/IBalancerQueries.sol";
import {IVault} from "src/interfaces/external/Balancer/IVault.sol";
import {IBalancerRelayer} from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import {IStakingLiquidityGauge} from "src/interfaces/external/Balancer/IStakingLiquidityGauge.sol";
import {IBalancerRelayer} from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import {ILiquidityGaugeFactory} from "src/interfaces/external/Balancer/ILiquidityGaugeFactory.sol";
import {ILiquidityGaugev3Custom} from "src/interfaces/external/Balancer/ILiquidityGaugev3Custom.sol";
import {IBasePool} from "src/interfaces/external/Balancer/typically-npm/IBasePool.sol";
import {ILiquidityGauge} from "src/interfaces/external/Balancer/ILiquidityGauge.sol";
import { Math } from "src/utils/Math.sol";
import {console} from "@forge-std/Test.sol";




/**
 * @title Balancer Pool Adaptor
 * @notice Allows Cellars to interact with Weighted, Stable, and Linear Balancer Pools (BPs).
 * @author 0xEinCodes and CrispyMangoes
 * TODO: This contract is still a WIP, Still need to go through TODOs and resolve relevant github issues
 * TODO: Add event emissions where necessary
 * VERY IMPORTANT - Major TODO: for core functionality (aside from testing)
 * 1. withdraw() - see PR #112 comment from Crispy
 */
contract BalancerPoolAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;


    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(ERC20 _bpt)
    // Where:
    // `_bpt` is the Balancer pool token of the Balancer LP market this adaptor is working with
    // See 1-pager made to assist constructing queries: TODO: layout 1 pager example in the docs as a ChangeRequest. 
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has the `assetof` as a bpt, and thus relies on the `PriceRouterv2` Balancer Extensions corresponding with the type of bpt the Cellar is working with.

    //==================== TODO: Adaptor Data Specification ====================
    // See Related Open Issues on this for BalancerPoolAdaptor.sol
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    //============================================ Error Statements ===========================================
    
    /**
     * @notice bptOut lower than desired
     */
    error BalancerPoolAdaptor__BPTOutTooLow();

    /**
     * @notice no claimable reward tokens
     */
    error BalancerPoolAdaptor__ZeroClaimableRewards();

    /**
     * @notice max slippage exceeded
     */
    error BalancerPoolAdaptor__MaxSlippageExceeded();

    /**
     * @notice bpt amount to unstake/withdraw requested exceeds amount actuall staked/deposited in liquidity gauge
     */
    error BalancerPoolAdaptor__NotEnoughToWithdraw();

    /**
     * @notice bpt amount to unstake/withdraw requested exceeds amount actuall staked/deposited in liquidity gauge
     */
    error BalancerPoolAdaptor__NotEnoughToDeposit();


    //============================================ Global Vars && Specific Adaptor Constants ===========================================

    // TODO: not sure if I actually need this.
    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    /**
     * @notice The Balancer Vault contract on Ethereum Mainnet
     * @return address adhering to `IVault`
     */
    function vault() internal pure virtual returns (IVault) {
        return IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    }

    /**
     * @notice The Balancer Relayer contract on Ethereum Mainnet
     * @return relayer address adhering to `IBalancerRelayer`
     */
    function relayer() internal pure virtual returns (IBalancerRelayer) {
        return IBalancerRelayer(0xfeA793Aa415061C483D2390414275AD314B3F621);
    }

    /**
     * @notice The Liquidity Gauge Factory contract on Ethereum Mainnet
     * @return address adhering to ILiquidityGaugeFactory
     */
    function gaugeFactory() internal pure returns (ILiquidityGaugeFactory) {
        return ILiquidityGaugeFactory(0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC); // TODO: according to the docs, this is the newest version that should be used but the docs also point people to use the old one. Which one are supposed to use? "Newer one: 0xf1665E19bc105BE4EDD3739F88315cC699cc5b65"
        // The old one actually has `getPoolGauge()`
    }

    //============================================ Global Functions ===========================================

    /**
     * @notice Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this identifier is needed during Cellar Delegate Call Operations, so getting the address of the adaptor is more difficult.
     * @return encoded adaptor identifier
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Balancer Pool Adaptor V 1.0"));
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
     * @notice Calculates the Cellar's balance of the positions creditAsset, a specific bpt.
     * @return total balance of bpt for Cellar, including liquid bpt and staked bpt
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        // TODO: decode adaptorData for poolGauge address
        address bpt = abi.decode(adaptorData, (address));

        // TODO: commented out for now, see comments below for gaugeFactory setup
        // ILiquidityGaugev3Custom poolGauge = gaugeFactory().getPoolGauge(bpt); // TODO: there are no getters to access in the latest gauge factory to check what the poolGauge address is associated to a respective BPT.
        // TODO: might have to put conditional logic here that:
        // 1. First checks that the returned poolgauge isn't zeroAddress
        // 2. If it is, it exits the if statement conditions and skips checking for stakedBPT. If it isn't it goes through and calculates total BPT. 
        // ** the challenge is that the most recent pool gauge factories do not have getters exposing poolGauge addresses for specific BPTs. 

        // ERC20 poolGaugeToken = ERC20(address(poolGauge));
        // uint256 stakedBPT = poolGaugeToken.balanceOf(address(this));
        // return ERC20(bpt).balanceOf(msg.sender) + stakedBPT;
        return ERC20(bpt).balanceOf(msg.sender);
    }

    /**
     * @notice Returns the positions underlying assets.
     * @param adaptorData specified bpt of interest
     * @return bpt for Cellar's respective balancer pool position
     */
    function assetOf(bytes memory adaptorData) public pure override returns (ERC20) {
        return ERC20(abi.decode(adaptorData, (address)));
    }

    /**
     * @notice When positions are added to the Registry, this function can be used in order to figure out
     *         what assets this adaptor needs to price, and confirm pricing is properly setup.
     * @param adaptorData specified bpt of interest
     * @return assets for Cellar's respective balancer pool position
     * @dev all breakdowns of bpt pricing and its underlying assets are done through the PriceRouter extension (in accordance to PriceRouterv2 architecture)
     */
    function assetsUsed(bytes memory adaptorData) public view override returns (ERC20[] memory assets) {
        assets = new ERC20[](1);
        assets[0] = assetOf(adaptorData);
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
     * @notice call `BalancerRelayer` on mainnet to carry out txs that can incl. joins, exits, and swaps
     * @param tokensIn specific tokens being input for tx
     * @param amountsIn amount of assets input for tx
     * @param bptOut acceptable amount of assets resulting from tx (due to slippage, etc.)
     * @param callData encoded specific txs to be used in `relayer.multicall()`. It is an array of bytes. This is different than other adaptors where singular txs are carried out via the `cellar.callOnAdaptor()` with its own array of `data`. Here we take a series of actions, encode all those into one bytes data var, pass that singular one along to `cellar.callOnAdaptor()` and then `cellar.callOnAdaptor()` will ultimately feed individual decoded actions into `useRelayer()` as `bytes[] memory callData`.
     * @dev multicall() handles the actual mutation code whereas everything else mostly is there for checks preventing manipulation, etc.
     * NOTE: The difference btw what Balancer outlines to do and what we want to do is that we want the txs to be carried out by the vault. Whereas we could just end up connecting to the relayer and have it carry out multi-txs which would be bad cause we need to confirm each step of the multi-call.
     * TODO: rename params and possibly include others for `exit()` function. ex.) bptOut needs to be renamed to be agnostic.
     * TODO: see issue for strategist callData
     * TODO: see discussion in draft PR #112 about `approve()` details
     */
    function useRelayer(ERC20[] memory tokensIn, uint256[] memory amountsIn, ERC20 bptOut, bytes[] memory callData)
        public
    {
        for (uint256 i; i < tokensIn.length; ++i) {
            tokensIn[i].approve(address(vault()), amountsIn[i]);
        } // TODO: this may be obsolete based on approval steps necessary for relayer functionality (see TODO below)

        uint256 startingBpt = bptOut.balanceOf(address(this));

        // TODO: implement proper way of giving Relayer approval; Relayer.setRelayerApproval() or Relayer.approveVault().

        relayer().multicall(callData);

        // uint256 endingBpt = bptOut.balanceOf(address(this));

        // uint256 amountBptOut = endingBpt - startingBpt;
        
        // PriceRouter priceRouter = PriceRouter(Cellar(msg.sender).registry().getAddress(PRICE_ROUTER_REGISTRY_SLOT())); // TODO: I don't think this is set up right.

        // uint256 amountBptIn = priceRouter.getValues(tokensIn, amountsIn, bptOut);

        // // check value in vs value out
        // if (amountBptOut < amountBptIn.mulDivDown(slippage(), 1e4)) revert("Slippage");

        // // revoke token in approval
        // for (uint256 i; i < tokensIn.length; ++i) {
        //     _revokeExternalApproval(tokensIn[i],address(relayer()));
        // }

        // TODO: see if special revocation is required or necessary with bespoke Relayer approval sequences
    }

    /**
     * @notice TEMPORARY function to help with troubleshooting tests.
     * TODO: Delete this function and replace any use of it with `useRelayer()` in tests
     */
    function useRelayer2(bytes[] memory callData)
        public
    {
        relayer().multicall(callData);
    }

    /// INDIVIDUAL BALANCER ECOSYSTEM FUNCTION CALLS (LIKELY UNUSED / TO BE REMOVED SINCE RELAYER CAN DO MOST ACTIONS)

    /**
     * @notice deposit (stake) BPTs into respective pool gauge
     * @param _bpt address of BPTs to deposit
     * @param _amountIn number of BPTs to deposit
     * @param _claim_rewards whether or not to claim pending rewards too (true == claim)
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     * TODO: Finalize interface details when beginning to do unit testing
     * TODO: See if _claim_rewards is needed in any sequences of actions when interacting with the gauges
     * TODO: Assess if `depositBPT()`, `withdrawBPT()`, `claimRewards()`
     */
    function depositBPT(address _bpt, uint256 _amountIn, bool _claim_rewards) external {
        ERC20 bpt = ERC20(_bpt);
        uint256 amountIn = _maxAvailable(bpt, _amountIn);

        ILiquidityGaugev3Custom poolGauge = gaugeFactory().getPoolGauge(_bpt);
        // uint256 amountStakedBefore = ERC20(address(poolGauge)).balanceOf(address(this));

        bpt.approve(address(poolGauge), amountIn);
        poolGauge.deposit(amountIn, address(this)); // address(this) is cellar address bc delegateCall --> TODO: double check that we are to use ILiquidityGaugev3Custom vs ILiquidityGauge
        // ERC20 poolGaugeToken = ERC20(address(poolGauge));

        // uint256 actualAmountStaked = poolGaugeToken.balanceOf(address(this)) - amountStakedBefore;

        _revokeExternalApproval(bpt, address(poolGauge));
    }

    /**
     * @notice withdraw (unstake) BPT from respective pool gauge
     * @param _bpt address of BPTs to withdraw
     * @param _amountOut number of BPTs to withdraw
     * @param _claim_rewards whether or not to claim pending rewards too (true == claim)
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     */
    function withdrawBPT(address _bpt, uint256 _amountOut, bool _claim_rewards) external {

        ILiquidityGaugev3Custom poolGauge = gaugeFactory().getPoolGauge(_bpt);
        uint256 amountOut = _maxAvailable(ERC20(address(poolGauge)), _amountOut); // get the total amount of bpt staked by the cellar essentially (bc it's represented by the amount of gauge tokens the Cellar has)

        ERC20 bpt = ERC20(_bpt);
        // uint256 unstakedBPTBefore = bpt.balanceOf(address(this));

        bpt.approve(address(poolGauge), amountOut);
        poolGauge.withdraw(amountOut); // msg.sender should be cellar address bc delegateCall. TODO: see issue # <> and confirm address.

        // uint256 actualWithdrawn = bpt.balanceOf(address(this)) - unstakedBPTBefore;

        _revokeExternalApproval(bpt, address(poolGauge));
    }

    /**
     * @notice claim rewards ($BAL and/or other tokens) from LP position
     * @notice Have the strategist provide the address for the pool gauge
     * @dev rewards are only accrue for staked positions
     * @param _bpt associated BPTs for respective reward gauge
     * @param _rewardToken address of reward token, if not $BAL, that strategist is claiming
     * TODO: make all verbose text here into github issues or remove them after discussion w/ Crispy
     * TODO: add checks throughout function
     */
    function claimRewards(address _bpt, address _rewardToken) public {
        ILiquidityGaugev3Custom poolGauge = gaugeFactory().getPoolGauge(_bpt);

        // TODO: checks - though, I'm not sure we need these. If cellar calls `claim_rewards()` and there's no rewards for them then... there are no explicit reverts in the codebase but I assume it reverts. Need to test it though: https://github.com/balancer/balancer-v2-monorepo/blob/master/pkg/liquidity-mining/contracts/gauges/ethereum/LiquidityGaugeV5.vy#L440-L450:~:text=if%20total_claimable%20%3E%200%3A

        // TODO: include `claimable_rewards` in next BalancerAdaptor (other tokens on mainnet) that will be used for non-mainnet chains.
        if ((poolGauge.claimable_reward(address(this), _rewardToken) == 0) && (poolGauge.claimable_tokens(address(this)) == 0)) {
            revert BalancerPoolAdaptor__ZeroClaimableRewards();
        }

        poolGauge.claim_rewards(address(this), address(0));
    }

    /// Functions && Notes that may not be needed

    // /**
    //  * @notice the BalancerQueries address on all networks
    //  * @return address adhering to IBalancerQueries
    //  */
    // function balancerQueries() internal pure returns (IBalancerQueries) {
    //     return 0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5;
    // }

     // NOTE from balancer docs: JoinPoolRequest is what strategists will need to provide
    // When providing your assets, you must ensure that the tokens are sorted numerically by token address. It's also important to note that the values in maxAmountsIn correspond to the same index value in assets, so these arrays must be made in parallel after sorting.
    // NOTE: different JoinKinds for different pool types: to start, we'll focus on WeightedPools & StablePools. The idea: Strategists pass in the JoinKinds within their calls, so they need to know what type of pool they are joining. Alt: we could query to see what kind of pool it is, but strategist still needs to specify the type of tx this is.

    /**
     * NOTE: it would take multiple tokens and amounts in and a single bpt out
     */
    function slippageSwap(ERC20 from, ERC20 to, uint256 inAmount, uint32 slippage) public virtual {
        // if (priceRouter.isSupported(from) && priceRouter.isSupported(to)) {
        //     // Figure out value in, quoted in `to`.
        //     uint256 fullValueOut = priceRouter.getValue(from, inAmount, to);
        //     uint256 valueOutWithSlippage = fullValueOut.mulDivDown(slippage, 1e4);
        //     // Deal caller new balances.
        //     deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
        //     deal(address(to), msg.sender, to.balanceOf(msg.sender) + valueOutWithSlippage);
        // } else {
        //     // Pricing is not supported, so just assume exchange rate is 1:1.
        //     deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
        //     deal(
        //         address(to),
        //         msg.sender,
        //         to.balanceOf(msg.sender) + inAmount.changeDecimals(from.decimals(), to.decimals())
        //     );
        // }

        console.log("howdy");
    }
}
