// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, SwapRouter, Registry, PriceRouter } from "src/modules/adaptors/BaseAdaptor.sol";
import { IBalancerQueries } from "src/interfaces/external/Balancer/IBalancerQueries.sol";
import { IVault } from "src/interfaces/external/Balancer/IVault.sol";
import { IBalancerRelayer } from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import { IStakingLiquidityGauge } from "src/interfaces/external/Balancer/IStakingLiquidityGauge.sol";
import { IBalancerRelayer } from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import { ILiquidityGaugeFactory } from "src/interfaces/external/Balancer/ILiquidityGaugeFactory.sol";
import { ILiquidityGaugev3Custom } from "src/interfaces/external/Balancer/ILiquidityGaugev3Custom.sol";
import { IBasePool } from "src/interfaces/external/Balancer/typically-npm/IBasePool.sol";
import { ILiquidityGauge } from "src/interfaces/external/Balancer/ILiquidityGauge.sol";
import { Math } from "src/utils/Math.sol";
import { console } from "@forge-std/Test.sol";

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
    // adaptorData = abi.encode(ERC20 _bpt, address _liquidityGauge)
    // Where:
    // `_bpt` is the Balancer pool token of the Balancer LP market this adaptor is working with
    // `_liquidityGauge` is the balancer gauge corresponding to the specified bpt
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

    error BalancerPoolAdaptor__BptAndGaugeComboMustBeTracked(address bpt, address liquidityGauge);

    error BalancerPoolAdaptor___GaugeUnderlyingBptMismatch(
        address bptInput,
        address liquidityGauge,
        address correctBPT
    );

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
        // The old one actually has `getLiquidityGauge()`
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
    function deposit(
        uint256,
        bytes memory,
        bytes memory
    ) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     * TODO: Cellar will call this if it is trying to give user assets when the cellar doesn't have enough
     * Cellar does a delegate call to this function in the unwind situation.
     *
     */
    function withdraw(
        uint256 _amountBPTToSend,
        address _recipient,
        bytes memory _adaptorData,
        bytes memory _configurationData
    ) public pure override {
        // _externalReceiverCheck(receiver); // TODO: IMPLEMENT THIS!! if we are in the context of callOnAdapter - the receiver needs to be the cellar. That's what this check / block is doing.
        // ge
        // revert BaseAdaptor__UserWithdrawsNotAllowed();
    }

    /**
     * @notice This position is a liquidity provision (credit) position, and user withdraws are not allowed so this position must return 0 for withdrawableFrom.
     */
    function withdrawableFrom(bytes memory, bytes memory) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @notice Calculates the Cellar's balance of the positions creditAsset, a specific bpt.
     * @param _adaptorData encoded data for trusted adaptor position detailing the bpt and liquidityGauge address (if it exists)
     * @return total balance of bpt for Cellar, including liquid bpt and staked bpt
     * NOTE: check that bpt isn't zero address. could also put in checks that it is set to true too...
     */
    function balanceOf(bytes memory _adaptorData) public view override returns (uint256) {
        (ERC20 bpt, address liquidityGauge) = abi.decode(_adaptorData, (ERC20, address));
        // _validateBptAndGauge(address(bpt), liquidityGauge);
        // _validateGaugeUnderlyingBpt(bpt, liquidityGauge); // TODO: Need to have this to ensure underlying bpt of gauge is the same as the cellar.

        if (liquidityGauge == address(0)) return ERC20(bpt).balanceOf(msg.sender);

        //TODO: this is assuming 1:1 swap ratio for staked gauge tokens to bpts themselves. We may need to have checks for that.
        ERC20 liquidityGaugeToken = ERC20(address(liquidityGauge));
        uint256 stakedBPT = liquidityGaugeToken.balanceOf(address(this));
        return ERC20(bpt).balanceOf(msg.sender) + stakedBPT;
    }

    /**
     * @notice Returns the positions underlying assets.
     * @param _adaptorData specified bpt of interest
     * @return bpt for Cellar's respective balancer pool position
     * NOTE: bpts can comprise of nested underlying constituents. Thus proper AssetSettings will be made for each respective bpt (and their various types) that are used in PriceRouter. bpts is as 'low' as `assetOf()` needs to report
     */
    function assetOf(bytes memory _adaptorData) public pure override returns (ERC20) {
        return ERC20(abi.decode(_adaptorData, (address)));
    }

    /**
     * @notice When positions are added to the Registry, this function can be used in order to figure out
     *         what assets this adaptor needs to price, and confirm pricing is properly setup.
     * @param _adaptorData specified bpt of interest
     * @return assets for Cellar's respective balancer pool position
     * @dev all breakdowns of bpt pricing and its underlying assets are done through the PriceRouter extension (in accordance to PriceRouterv2 architecture)
     */
    function assetsUsed(bytes memory _adaptorData) public view override returns (ERC20[] memory assets) {
        assets = new ERC20[](1);
        assets[0] = assetOf(_adaptorData);
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
     * TODO: rename params and possibly include others for `exit()` function. ex.) bptOut needs to be renamed to be agnostic.
     * TODO: see issue for strategist callData
     * TODO: Add a param and conditional logic to sort whether the action with the Relayer is increasing or decreasing BPT
     * TODO: Should we include _liquidityGauge in params here even though it's not used?
     */
    function useRelayer(
        ERC20[] memory tokensIn,
        uint256[] memory amountsIn,
        ERC20 bptOut,
        bytes[] memory callData
    ) public {
        // _validateBptAndGauge(address(bptOut), _liquidityGauge); // liquidityGauge not used in this function but it is part of adaptorData, so leaving it for now.
        // TODO: NOTE: I could check if gauge corresponds to bpt, but I think that the strategist should have done that.

        for (uint256 i; i < tokensIn.length; ++i) {
            tokensIn[i].approve(address(vault()), amountsIn[i]);
        }
        uint256 startingBpt = bptOut.balanceOf(address(this));

        adjustRelayerApproval(true);
        relayer().multicall(callData);
        uint256 endingBpt = bptOut.balanceOf(address(this));
        uint256 amountBptOut = endingBpt - startingBpt;
        PriceRouter priceRouter = PriceRouter(
            Cellar(address(this)).registry().getAddress(PRICE_ROUTER_REGISTRY_SLOT())
        );
        uint256 amountBptIn = priceRouter.getValues(tokensIn, amountsIn, bptOut);

        if (amountBptOut < amountBptIn.mulDivDown(slippage(), 1e4)) revert("Slippage");

        // revoke token in approval
        for (uint256 i; i < tokensIn.length; ++i) {
            _revokeExternalApproval(tokensIn[i], address(vault()));
        }

        // TODO: see if special revocation is required or necessary with bespoke Relayer approval sequences
    }

    /**
     * @notice external function to help adjust whether or not the relayer has been approved by cellar
     * @param _relayerChange proposed approval setting to relayer
     * TODO: I want to have this in the setup() but it is giving me issues weirdly. It only allows tests to pass when the call is made within `useRelayer()` itself, where I think address(this) is the balancerPoolAdaptor itself. It's interesting cause iirc `setRelayerApproval()` allows relayer to act as a relayer for `sender` -->  I'd think that sender is the cellar, not the adaptor.
     * I tried to prank the setup() and have it so the balancerPoolAdaptor was calling `setRelayerApproval()` but then I got a BAL#401 error. I'll come back to this later.
     */
    function adjustRelayerApproval(bool _relayerChange) public virtual {
        // // if relayer is already approved, continue
        // // if it hasn't been approved, set it to set it to approved
        // bool currentStatus = vault().hasApprovedRelayer(address(this), address(relayer()));

        // if (currentStatus != _relayerChange) {
        //     vault().setRelayerApproval(address(this), address(relayer()), _relayerChange);
        //     // event RelayerApprovalChanged will be emitted by Balancer Vault
        // }
        vault().setRelayerApproval(address(this), address(relayer()), true);
        // bool newStatus = vault().hasApprovedRelayer(address(this), address(relayer()));
    }

    /**
     * @notice deposit (stake) BPTs into respective pool gauge
     * @param _bpt address of BPTs to deposit
     * @param _amountIn number of BPTs to deposit
     * @param _claim_rewards whether or not to claim pending rewards too (true == claim)
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     * TODO: Finalize interface details when beginning to do unit testing
     * TODO: See if _claim_rewards is needed in any sequences of actions when interacting with the gauges
     * TODO: fix verification helper checks
     */
    function depositBPT(
        ERC20 _bpt,
        address _liquidityGauge,
        uint256 _amountIn,
        bool _claim_rewards
    ) external {
        // checks
        // _validateBptAndGauge(address(_bpt), _liquidityGauge);
        // _validateGaugeUnderlyingBpt(_bpt, _liquidityGauge); see comment on _validateGaugeUnderlyingBpt()

        uint256 amountIn = _maxAvailable(_bpt, _amountIn);
        ILiquidityGaugev3Custom liquidityGauge = ILiquidityGaugev3Custom(_liquidityGauge); // TODO: double check that we are to use ILiquidityGaugev3Custom vs ILiquidityGauge
        _bpt.approve(address(liquidityGauge), amountIn);
        liquidityGauge.deposit(amountIn, address(this));
        _revokeExternalApproval(_bpt, address(liquidityGauge));
    }

    /**
     * @notice withdraw (unstake) BPT from respective pool gauge
     * @param _bpt address of BPTs to withdraw
     * @param _amountOut number of BPTs to withdraw
     * @param _claim_rewards whether or not to claim pending rewards too (true == claim)
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     * TODO: fix verification helper checks and see other TODOs from depositBPT()
     */
    function withdrawBPT(
        ERC20 _bpt,
        address _liquidityGauge,
        uint256 _amountOut,
        bool _claim_rewards
    ) external {
        // _validateBptAndGauge(address(_bpt), _liquidityGauge);
        // _validateGaugeUnderlyingBpt(_bpt, _liquidityGauge); see comment on _validateGaugeUnderlyingBpt()

        ILiquidityGaugev3Custom liquidityGauge = ILiquidityGaugev3Custom(_liquidityGauge); // TODO: double check that we are to use ILiquidityGaugev3Custom vs ILiquidityGauge
        uint256 amountOut = _maxAvailable(ERC20(address(liquidityGauge)), _amountOut);
        _bpt.approve(address(liquidityGauge), amountOut);
        liquidityGauge.withdraw(amountOut);
        _revokeExternalApproval(_bpt, address(liquidityGauge));
    }

    /**
     * @notice claim rewards ($BAL and/or other tokens) from LP position
     * @dev rewards are only accrue for staked positions
     * @param _bpt associated BPTs for respective reward gauge
     * @param _rewardToken address of reward token, if not $BAL, that strategist is claiming
     * TODO: fix verification helper checks and see other TODOs from depositBPT()
     */
    function claimRewards(
        address _bpt,
        address _liquidityGauge,
        address _rewardToken
    ) public {
        // _validateBptAndGauge(address(_bpt), _liquidityGauge);

        ILiquidityGaugev3Custom liquidityGauge = ILiquidityGaugev3Custom(_liquidityGauge); // TODO: double check that we are to use ILiquidityGaugev3Custom vs ILiquidityGauge

        // TODO: checks - though, I'm not sure we need these. If cellar calls `claim_rewards()` and there's no rewards for them then... there are no explicit reverts in the codebase but I assume it reverts. Need to test it though: https://github.com/balancer/balancer-v2-monorepo/blob/master/pkg/liquidity-mining/contracts/gauges/ethereum/LiquidityGaugeV5.vy#L440-L450:~:text=if%20total_claimable%20%3E%200%3A
        // TODO: include `claimable_rewards` in next BalancerAdaptor (other tokens on mainnet) that will be used for non-mainnet chains.
        if (
            (liquidityGauge.claimable_reward(address(this), _rewardToken) == 0) &&
            (liquidityGauge.claimable_tokens(address(this)) == 0)
        ) {
            revert BalancerPoolAdaptor__ZeroClaimableRewards();
        }

        liquidityGauge.claim_rewards(address(this), address(0));
    }

    //============================================ Helper Functions ===========================================

    /**
     * @notice Validates that a given bpt and liquidityGauge is set up as a position in the Cellar
     * @dev This function uses `address(this)` as the address of the Cellar
     * @param _bpt of interest
     * @param _liquidityGauge corresponding to _bpt
     * NOTE: _liquidityGauge can be zeroAddress in cases where Cellar doesn't want to stake or there are no gauges yet available for respective bpt
     */
    function _validateBptAndGauge(address _bpt, address _liquidityGauge) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(address(_bpt), _liquidityGauge)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert BalancerPoolAdaptor__BptAndGaugeComboMustBeTracked(address(_bpt), _liquidityGauge);
    }

    // /**
    //  * @notice Validates that a liquidityGauge corresponds to a given bpt
    //  * TODO: unsure if this is needed, we may keep this function if the balancer gauges all follow a certain interface.
    //  * @dev This function uses `address(this)` as the address of the Cellar
    //  * @param _bpt of interest
    //  * @param _liquidityGauge being checked if it corresponds to _bpt
    //  * NOTE: _liquidityGauge can be zeroAddress in cases where Cellar doesn't want to stake or there are no gauges yet available for respective bpt
    //  */
    // function _validateGaugeUnderlyingBpt(ERC20 _bpt, address _liquidityGauge) internal view {
    //     address underlyingBPT = _liquidityGauge.staticcall(abi.encodeWithSelector(lp_token.selector));
    //     if (address(_bpt) != underlyingBPT)
    //         revert BalancerPoolAdaptor___GaugeUnderlyingBptMismatch(address(_bpt), _liquidityGauge, underlyingBPT);
    // }
}
