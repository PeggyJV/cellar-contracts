// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, SwapRouter, Registry, PriceRouter } from "src/modules/adaptors/BaseAdaptor.sol";
import { IBalancerQueries } from "src/interfaces/external/Balancer/IBalancerQueries.sol";
import { IVault } from "src/interfaces/external/Balancer/IVault.sol";
import { IBalancerRelayer } from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
import { IStakingLiquidityGauge } from "src/interfaces/external/Balancer/IStakingLiquidityGauge.sol";
import { IBalancerRelayer } from "src/interfaces/external/Balancer/IBalancerRelayer.sol";
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
 * TODO: CONSOLIDATE THIS TO AN ISSUE THAT WE NEED TO DISCUSS FURTHER - FOR NOW WE CAN JUST PAUSE THE CELLAR... bpts rates are integrated in price router checks so if there is a shortfall of collateral (hack) in bpts or something, then there wouldn't be a discprancy on prices between the assets that the cellar has vs what the bpts are worth in the bpt pool. CRISPY QUESTION - maybe we'll need a bool in case the pools are broken and we get a bad deal no matter what, so slippage checks are overridden in that case?
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
    error BalancerPoolAdaptor__NotEnoughToUnstake();

    /**
     * @notice bpt amount to unstake/withdraw requested exceeds amount actually staked/deposited in liquidity gauge
     */
    error BalancerPoolAdaptor__NotEnoughToStake();

    error BalancerPoolAdaptor__BptAndGaugeComboMustBeTracked(address bpt, address liquidityGauge);

    error BalancerPoolAdaptor___GaugeUnderlyingBptMismatch(
        address bptInput,
        address liquidityGauge,
        address correctBPT
    );

    //============================================ Global Vars && Specific Adaptor Constants ===========================================

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
     * NOTE:
     */
    function deposit(uint256, bytes memory, bytes memory) public pure override {
        revert BaseAdaptor__UserDepositsNotAllowed();
    }

    /**
     * @notice User withdraws are NOT allowed from this position.
     * Cellar does a delegate call to this function in the unwind situation.
     * NOTE: accessed via delegateCall from Cellar
     */
    function withdraw(
        uint256 _amountBPTToSend,
        address _recipient,
        bytes memory _adaptorData,
        bytes memory _configurationData
    ) public pure override {
        // Run external receiver check.
        _externalReceiverCheck(_recipient);
        (ERC20 bpt, address liquidityGauge) = abi.decode(_adaptorData, (ERC20, address));
        uint256 liquidBptBeforeWithdraw = bpt.balanceOf(address(this));
        if (_amountBPTToSend > liquidBptBeforeWithdraw) {
            uint256 amountToUnstake = _amountBPTToSend - liquidBptBeforeWithdraw;
            unstakeBPT(bpt, liquidityGauge, amountToUnstake, false);
        }
        bpt.safeTransfer(_recipient, _amountBPTToSend);
    }

    /**
     * @notice Staked positions can be unstaked, and bpts can be sent to a respective user if Cellar cannot meet withdrawal quota.
     */
    function withdrawableFrom(
        bytes memory _adaptorData,
        bytes memory _configData
    ) public pure override returns (uint256) {
        (ERC20 bpt, address liquidityGauge) = abi.decode(_adaptorData, (ERC20, address));
        return balanceOf(_adaptorData);
    }

    /**
     * @notice Calculates the Cellar's balance of the positions creditAsset, a specific bpt.
     * @param _adaptorData encoded data for trusted adaptor position detailing the bpt and liquidityGauge address (if it exists)
     * @return total balance of bpt for Cellar, including liquid bpt and staked bpt
     * NOTE: to be called via staticcall, also be wary that adaptorData ought to have paired gauge to bpts, otherwise it would be wrong.
     */
    function balanceOf(bytes memory _adaptorData) public view override returns (uint256) {
        (ERC20 bpt, address liquidityGauge) = abi.decode(_adaptorData, (ERC20, address));
        if (liquidityGauge == address(0)) return ERC20(bpt).balanceOf(msg.sender);
        //TODO: this is assuming 1:1 swap ratio for staked gauge tokens to bpts themselves. We may need to have checks for that.
        ERC20 liquidityGaugeToken = ERC20(address(liquidityGauge));
        uint256 stakedBPT = liquidityGaugeToken.balanceOf(msg.sender);
        return ERC20(bpt).balanceOf(msg.sender) + stakedBPT;
    }

    /**
     * @notice Returns the positions underlying assets.
     * @param _adaptorData specified bpt of interest
     * @return bpt for Cellar's respective balancer pool position
     * NOTE: bpts can comprise of nested underlying constituents. Thus proper AssetSettings will be made for each respective bpt (and their various types) that are used in PriceRouter. bpts is as 'low' of a level that the BalancerPoolAdaptor will report via `assetOf()` because PriceRouter takes care of the constituents.
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

    /// STRATEGIST NOTE: for `relayerJoinPool()` and `relayerExitPool()` strategist functions callData param are encoded specific txs to be used in `relayer.multicall()`. It is an array of bytes. This is different than other adaptors where singular txs are carried out via the `cellar.callOnAdaptor()` with its own array of `data`. Here we take a series of actions, encode all those into one bytes data var, pass that singular one along to `cellar.callOnAdaptor()` and then `cellar.callOnAdaptor()` will ultimately feed individual decoded actions into `relayerJoinPool()` as `bytes[] memory callData`.

    /**
     * @notice call `BalancerRelayer` on mainnet to carry out txs that can incl. joins, exits, and swaps
     * @param tokensIn specific tokens being input for tx
     * @param amountsIn amount of assets input for tx
     * @param bptOut acceptable amount of assets resulting from tx (due to slippage, etc.)
     * @param callData encoded specific txs to be used in `relayer.multicall()`. See general note at start of `Strategist Functions` section.
     * @dev multicall() handles the actual mutation code whereas everything else mostly is there for checks preventing manipulation, etc.
     * TODO: see issue for strategist general callData
     * NOTE: possible that bpts can be moved into AURA positions so we don't validate that the bptOut is a valid position in the cellar because it could be moved to Aura during the same rebalance. Thus _liquidityGauge in params is not checked here
     */
    function relayerJoinPool(
        ERC20[] memory tokensIn,
        uint256[] memory amountsIn,
        ERC20 bptOut,
        bytes[] memory callData
    ) public {
        for (uint256 i; i < tokensIn.length; ++i) {
            tokensIn[i].approve(address(vault()), amountsIn[i]);
        }
        uint256 startingBpt = bptOut.balanceOf(address(this));
        adjustRelayerApproval(true); // TODO: get rid of this once `adjustRelayerApproval()` helper is made and working
        relayer().multicall(callData);

        uint256 endingBpt = bptOut.balanceOf(address(this));
        uint256 amountBptOut = endingBpt - startingBpt;
        PriceRouter priceRouter = Cellar(address(this)).priceRouter();
        uint256 amountBptIn = priceRouter.getValues(tokensIn, amountsIn, bptOut);

        if (amountBptOut < amountBptIn.mulDivDown(slippage(), 1e4)) revert("Slippage"); // TODO: replace quote message with actual error message. Also check baseAdaptor slippage error that may suffice.

        // revoke token in approval
        for (uint256 i; i < tokensIn.length; ++i) {
            _revokeExternalApproval(tokensIn[i], address(vault()));
        }

        // TODO: BALANCER QUESTION - see if special revocation is required or necessary with bespoke Relayer approval sequences
    }

    /**
     * @notice call `BalancerRelayer` on mainnet to carry out txs that can incl. joins, exits, and swaps
     * @param bptIn specific tokens being input for tx
     * @param amountIn amount of bpts input for tx
     * @param tokensOut acceptable amounts of assets out resulting from tx (due to slippage, etc.)
     * @param callData encoded specific txs to be used in `relayer.multicall()`. See general note at start of `Strategist Functions` section.
     * @dev multicall() handles the actual mutation code whereas everything else mostly is there for checks preventing manipulation, etc.
     * TODO: see issue for strategist general callData
     * NOTE: when exiting pool, a number of different ERC20 constituent assets will be in the Cellar for distribution to depositors. Strategists must have ERC20Adaptor Positions trusted for these respectively. Swaps with them are to be done with external protocols for now (ZeroX, OneInch, etc.). Future swaps can be made internally using Balancer DEX upon a later Adaptor version.
     * NOTE: possible that bpts can be in transit between AURA positions so we don't validate that the bptIn is a valid position in the cellar during the same rebalance. Thus _liquidityGauge in params is not checked here
     */
    function relayerExitPool(
        ERC20 memory bptIn,
        uint256 memory amountIn,
        ERC20[] tokensOut,
        bytes[] memory callData
    ) public {
        bptIn.approve(address(vault()), amountIn); // TODO: check if this is needed cause vault could have approval already.
        PriceRouter priceRouter = Cellar(address(this)).priceRouter();
        adjustRelayerApproval(true); // TODO: get rid of this once `adjustRelayerApproval()` helper is made and working
        uint256[] memory tokenAmount = new uint256[](tokensOut.length);

        for (uint256 i; i < tokensOut.length; ++i) {
            tokenAmount[i] = tokensOut[i].balanceOf(address(this));
        }

        relayer().multicall(callData);

        for (uint256 i; i < tokensOut.length; ++i) {
            tokenAmount[i] = tokensOut[i].balanceOf(address(this)) - tokenAmount[i];
        }
        uint256 bptEquivalent = priceRouter.getValues(tokensOut, tokenAmount, bptIn);
        if (bptEquivalent < amountIn.mulDivDown(slippage(), 1e4)) revert("Slippage"); // TODO: replace quote message with actual error message. Also check baseAdaptor slippage error that may suffice.

        // revoke token in approval
        _revokeExternalApproval(bptIn, address(vault())); // TODO: check if this is needed cause vault could have approval already.
    }

    /**
     * @notice stake (deposit) BPTs into respective pool gauge
     * @param _bpt address of BPTs to stake
     * @param _amountIn number of BPTs to stake
     * @param _claim_rewards whether or not to claim pending rewards too (true == claim)
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     * TODO: Finalize interface details when beginning to do unit testing
     * TODO: See if _claim_rewards is needed in any sequences of actions when interacting with the gauges
     * TODO: fix verification helper checks
     */
    function stakeBPT(ERC20 _bpt, address _liquidityGauge, uint256 _amountIn, bool _claim_rewards) external {
        // checks
        _validateBptAndGauge(address(_bpt), _liquidityGauge);
        uint256 amountIn = _maxAvailable(_bpt, _amountIn);
        ILiquidityGaugev3Custom liquidityGauge = ILiquidityGaugev3Custom(_liquidityGauge); // TODO: BALANCER QUESTION - double check that we are to use ILiquidityGaugev3Custom vs ILiquidityGauge
        _bpt.approve(address(liquidityGauge), amountIn);
        liquidityGauge.stake(amountIn, address(this));
        _revokeExternalApproval(_bpt, address(liquidityGauge));
    }

    /**
     * @notice unstake (withdraw) BPT from respective pool gauge
     * @param _bpt address of BPTs to unstake
     * @param _amountOut number of BPTs to unstake
     * @param _claim_rewards whether or not to claim pending rewards too (true == claim)
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     */
    function unstakeBPT(ERC20 _bpt, address _liquidityGauge, uint256 _amountOut, bool _claim_rewards) public {
        _validateBptAndGauge(address(_bpt), _liquidityGauge);
        ILiquidityGaugev3Custom liquidityGauge = ILiquidityGaugev3Custom(_liquidityGauge); // TODO: double check that we are to use ILiquidityGaugev3Custom vs ILiquidityGauge
        _amountOut = _maxAvailable(ERC20(address(liquidityGauge)), _amountOut);
        liquidityGauge.withdraw(_amountOut);

        if (_claim_rewards) {
            // claimRewards(_bpt, _liquidityGauge, _rewardToken);
        }
    }

    /**
     * @notice claim rewards ($BAL and/or other tokens) from LP position
     * @dev rewards are only accrue for staked positions
     * @param _bpt associated BPTs for respective reward gauge
     * @param _rewardToken address of reward token, if not $BAL, that strategist is claiming
     * TODO: fix verification helper checks and see other TODOs from stakeBPT()
     * TODO: include `claimable_rewards` in next BalancerAdaptor (other tokens on mainnet) that will be used for non-mainnet chains.
     * TODO: BALANCER QUESTION - check if claimRewards() sends tokens to us, or do we need to actually specify the rewards to come back to us.
     */
    function claimRewards(address _bpt, address _liquidityGauge, address _rewardToken) public {
        _validateBptAndGauge(address(_bpt), _liquidityGauge);

        ILiquidityGaugev3Custom liquidityGauge = ILiquidityGaugev3Custom(_liquidityGauge); // TODO: double check that we are to use ILiquidityGaugev3Custom vs ILiquidityGauge

        // TODO: checks - though, I'm not sure we need these. If cellar calls `claim_rewards()` and there's no rewards for them then... there are no explicit reverts in the codebase but I assume it reverts. Need to test it though: https://github.com/balancer/balancer-v2-monorepo/blob/master/pkg/liquidity-mining/contracts/gauges/ethereum/LiquidityGaugeV5.vy#L440-L450:~:text=if%20total_claimable%20%3E%200%3A

        if (
            (liquidityGauge.claimable_reward(address(this), _rewardToken) > 0) ||
            (liquidityGauge.claimable_tokens(address(this)) > 0)
        ) {
            liquidityGauge.claim_rewards(address(this), address(0)); // TODO: do we need to have different claim_rewards and claim_tokens function calls to get all rewards or does this one call get us everything?
        }
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
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_bpt, _liquidityGauge)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert BalancerPoolAdaptor__BptAndGaugeComboMustBeTracked(_bpt, _liquidityGauge);
    }

    /**
     * @notice external function to help adjust whether or not the relayer has been approved by cellar
     * @param _relayerChange proposed approval setting to relayer
     * TODO: I want to have this in the setup() but it is giving me issues weirdly. It only allows tests to pass when the call is made within `relayerJoinPool()` itself, where I think address(this) is the balancerPoolAdaptor itself. It's interesting cause iirc `setRelayerApproval()` allows relayer to act as a relayer for `sender` -->  I'd think that sender is the cellar, not the adaptor.
     * I tried to prank the setup() and have it so the balancerPoolAdaptor was calling `setRelayerApproval()` but then I got a BAL#401 error. I'll come back to this later.
     */
    function adjustRelayerApproval(bool _relayerChange) public virtual {
        // // if relayer is already approved, continue
        // // if it hasn't been approved, set it to set it to approved
        // bool currentStatus = vault().hasApprovedRelayer(address(this), address(relayer()));
        // if (currentStatus != _relayerChange) {
        //     vault().setRelayerApproval(address(this), address(relayer()), _relayerChange);
        //     // event RelayerApprovalChanged will be emitted by Balancer Vault
        // // }
        // vault().setRelayerApproval(address(this), address(relayer()), true);
        // bool newStatus = vault().hasApprovedRelayer(address(this), address(relayer()));
    }
}
