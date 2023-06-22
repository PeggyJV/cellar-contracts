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
import { IBalancerMinter } from "src/interfaces/external/IBalancerMinter.sol";
import { BalancerRelayerFirewall } from "src/modules/adaptors/Balancer/BalancerRelayerFirewall.sol";

/**
 * @title Balancer Pool Adaptor
 * @notice Allows Cellars to interact with Weighted, Stable, and Linear Balancer Pools (BPs).
 * @author 0xEinCodes and CrispyMangoes
 */
contract BalancerPoolAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(ERC20 _bpt, address _liquidityGauge)
    // Where:
    // `_bpt` is the Balancer pool token of the Balancer LP market this adaptor is working with
    // `_liquidityGauge` is the balancer gauge corresponding to the specified bpt
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // This adaptor has the `assetOf` as a bpt, and thus relies on the `PriceRouterv2` Balancer
    // Extensions corresponding with the type of bpt the Cellar is working with.
    //==================== Adaptor Data Specification ====================
    // See Related Open Issues on this for BalancerPoolAdaptor.sol
    //================= Configuration Data Specification =================
    // NOT USED
    //====================================================================

    //============================================ Error Statements ===========================================

    /**
     * @notice Tried using a bpt and/or liquidityGauge that is not setup as a position.
     */
    error BalancerPoolAdaptor__BptAndGaugeComboMustBeTracked(address bpt, address liquidityGauge);

    /**
     * @notice Attempted balancer pool joins, exits, staking, unstaking, etc. with bad slippage
     */
    error BalancerPoolAdaptor___Slippage();

    /**
     * @notice Constructor param for slippage too high
     */
    error BalancerPoolAdaptor___InvalidConstructorSlippage();

    //============================================ Global Vars && Specific Adaptor Constants ===========================================

    /**
     * @notice The Balancer Vault contract
     * @notice For mainnet use 0xBA12222222228d8Ba445958a75a0704d566BF2C8
     */
    IVault public immutable vault;

    /**
     * @notice The Balancer Relayer contract adhering to `IBalancerRelayer
     * @notice For mainnet use 0xfeA793Aa415061C483D2390414275AD314B3F621
     */
    IBalancerRelayer public immutable relayer;

    /**
     * @notice The BalancerMinter contract adhering to IBalancerMinter (custom interface) to access `mint()` to collect $BAL rewards for Cellar
     * @notice For mainnet use 0x239e55F427D44C3cc793f49bFB507ebe76638a2b
     */
    IBalancerMinter public immutable minter;

    /**
     * @notice Number between 0.9e4, and 1e4 representing the amount of slippage that can be
     *         tolerated when entering/exiting a pool.
     *         - 0.90e4: 10% slippage
     *         - 0.95e4: 5% slippage
     */
    uint32 public immutable balancerSlippage;

    BalancerRelayerFirewall public immutable firewall;

    //============================================ Constructor ===========================================

    constructor(
        address _vault,
        address _relayer,
        address _minter,
        uint32 _balancerSlippage,
        BalancerRelayerFirewall _firewall
    ) {
        if (_balancerSlippage < 0.9e4 || _balancerSlippage > 1e4)
            revert BalancerPoolAdaptor___InvalidConstructorSlippage();
        vault = IVault(_vault);
        relayer = IBalancerRelayer(_relayer);
        minter = IBalancerMinter(_minter);
        balancerSlippage = _balancerSlippage;
        firewall = _firewall;
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
     * @notice If a user withdraw needs more BPTs than what is in the Cellar's
     *         wallet, then the Cellar will unstake BPTs from the gauge.
     */
    function withdraw(
        uint256 _amountBPTToSend,
        address _recipient,
        bytes memory _adaptorData,
        bytes memory
    ) public override {
        // Run external receiver check.
        _externalReceiverCheck(_recipient);
        (ERC20 bpt, address liquidityGauge) = abi.decode(_adaptorData, (ERC20, address));
        uint256 liquidBptBeforeWithdraw = bpt.balanceOf(address(this));
        if (_amountBPTToSend > liquidBptBeforeWithdraw) {
            uint256 amountToUnstake = _amountBPTToSend - liquidBptBeforeWithdraw;
            unstakeBPT(bpt, liquidityGauge, amountToUnstake);
        }
        bpt.safeTransfer(_recipient, _amountBPTToSend);
    }

    /**
     * @notice Accounts for BPTs in the Cellar's wallet, and staked in gauge.
     * @dev See `balanceOf`.
     */
    function withdrawableFrom(bytes memory _adaptorData, bytes memory) public view override returns (uint256) {
        return balanceOf(_adaptorData);
    }

    /**
     * @notice Calculates the Cellar's balance of the positions creditAsset, a specific bpt.
     * @param _adaptorData encoded data for trusted adaptor position detailing the bpt and liquidityGauge address (if it exists)
     * @return total balance of bpt for Cellar, including liquid bpt and staked bpt
     */
    function balanceOf(bytes memory _adaptorData) public view override returns (uint256) {
        (ERC20 bpt, address liquidityGauge) = abi.decode(_adaptorData, (ERC20, address));
        if (liquidityGauge == address(0)) return ERC20(bpt).balanceOf(msg.sender);
        ERC20 liquidityGaugeToken = ERC20(address(liquidityGauge));
        uint256 stakedBPT = liquidityGaugeToken.balanceOf(msg.sender);
        return ERC20(bpt).balanceOf(msg.sender) + stakedBPT;
    }

    /**
     * @notice Returns the positions underlying assets.
     * @param _adaptorData encoded data for trusted adaptor position detailing the bpt and liquidityGauge address (if it exists)
     * @return bpt for Cellar's respective balancer pool position
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
    function assetsUsed(bytes memory _adaptorData) public pure override returns (ERC20[] memory assets) {
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

    /// STRATEGIST NOTE: for `relayerJoinPool()` and `relayerExitPool()` strategist functions callData param are encoded
    /// specific txs to be used in `relayer.multicall()`. It is an array of bytes. This is different than other adaptors
    /// where singular txs are carried out via the `cellar.callOnAdaptor()` with its own array of `data`. Here we take a
    /// series of actions, encode all those into one bytes data var, pass that singular one along to `cellar.callOnAdaptor()`
    /// and then `cellar.callOnAdaptor()` will ultimately feed individual decoded actions into `relayerJoinPool()` as `bytes[]
    /// memory callData`.

    /**
     * @notice Call `BalancerRelayer` on mainnet to carry out join txs.
     * @param tokensIn specific tokens being input for tx
     * @param amountsIn amount of assets input for tx
     * @param bptOut acceptable amount of assets resulting from tx (due to slippage, etc.)
     * @param callData encoded specific txs to be used in `relayer.multicall()`. See general note at start of `Strategist Functions` section.
     * @dev multicall() handles the actual mutation code whereas everything else mostly is there for checks preventing manipulation, etc.
     * NOTE: possible that bpts can be moved into AURA positions so we don't validate that the bptOut is a valid position in the
     *      cellar because it could be moved to Aura during the same rebalance. Thus _liquidityGauge in params is not checked here
     */
    function relayerJoinPool(
        ERC20[] memory tokensIn,
        uint256[] memory amountsIn,
        ERC20 bptOut,
        bytes[] memory callData
    ) public {
        for (uint256 i; i < tokensIn.length; ++i) {
            tokensIn[i].approve(address(firewall), amountsIn[i]);
        }
        uint256 startingBpt = bptOut.balanceOf(address(this));
        firewall.joinPool(tokensIn, amountsIn, bptOut, callData);
        // relayer.multicall(callData);

        uint256 endingBpt = bptOut.balanceOf(address(this));
        uint256 amountBptOut = endingBpt - startingBpt;
        PriceRouter priceRouter = Cellar(address(this)).priceRouter();
        uint256 amountBptIn = priceRouter.getValues(tokensIn, amountsIn, bptOut);

        if (amountBptOut < amountBptIn.mulDivDown(slippage(), 1e4)) revert BalancerPoolAdaptor___Slippage();

        // revoke token in approval
        for (uint256 i; i < tokensIn.length; ++i) {
            _revokeExternalApproval(tokensIn[i], address(firewall));
        }
    }

    /**
     * @notice Call `BalancerRelayer` on mainnet to carry out exit txs.
     * @param bptIn specific tokens being input for tx
     * @param amountIn amount of bpts input for tx
     * @param tokensOut acceptable amounts of assets out resulting from tx (due to slippage, etc.)
     * @param callData encoded specific txs to be used in `relayer.multicall()`. See general note at start of `Strategist Functions` section.
     * @dev multicall() handles the actual mutation code whereas everything else mostly is there for checks preventing manipulation, etc.
     * NOTE: possible that bpts can be in transit between AURA positions so we don't validate that the bptIn is a valid
     *       position in the cellar during the same rebalance. Thus _liquidityGauge in params is not checked here
     */
    function relayerExitPool(ERC20 bptIn, uint256 amountIn, ERC20[] memory tokensOut, bytes[] memory callData) public {
        PriceRouter priceRouter = Cellar(address(this)).priceRouter();
        uint256[] memory tokenAmount = new uint256[](tokensOut.length);

        for (uint256 i; i < tokensOut.length; ++i) {
            tokenAmount[i] = tokensOut[i].balanceOf(address(this));
        }

        bptIn.safeApprove(address(firewall), amountIn);

        firewall.exitPool(bptIn, amountIn, tokensOut, callData);
        // relayer.multicall(callData);

        for (uint256 i; i < tokensOut.length; ++i) {
            tokenAmount[i] = tokensOut[i].balanceOf(address(this)) - tokenAmount[i];
        }
        uint256 bptEquivalent = priceRouter.getValues(tokensOut, tokenAmount, bptIn);
        if (bptEquivalent < amountIn.mulDivDown(slippage(), 1e4)) revert BalancerPoolAdaptor___Slippage();

        _revokeExternalApproval(bptIn, address(firewall));
    }

    /**
     * @notice stake (deposit) BPTs into respective pool gauge
     * @param _bpt address of BPTs to stake
     * @param _amountIn number of BPTs to stake
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     */
    function stakeBPT(ERC20 _bpt, address _liquidityGauge, uint256 _amountIn) external {
        _validateBptAndGauge(address(_bpt), _liquidityGauge);
        uint256 amountIn = _maxAvailable(_bpt, _amountIn);
        ILiquidityGaugev3Custom liquidityGauge = ILiquidityGaugev3Custom(_liquidityGauge);
        _bpt.approve(address(liquidityGauge), amountIn);
        liquidityGauge.deposit(amountIn, address(this));
        _revokeExternalApproval(_bpt, address(liquidityGauge));
    }

    /**
     * @notice unstake (withdraw) BPT from respective pool gauge
     * @param _bpt address of BPTs to unstake
     * @param _amountOut number of BPTs to unstake
     * @dev Interface custom as Balancer/Curve do not provide for liquidityGauges.
     */
    function unstakeBPT(ERC20 _bpt, address _liquidityGauge, uint256 _amountOut) public {
        _validateBptAndGauge(address(_bpt), _liquidityGauge);
        ILiquidityGaugev3Custom liquidityGauge = ILiquidityGaugev3Custom(_liquidityGauge);
        _amountOut = _maxAvailable(ERC20(address(liquidityGauge)), _amountOut);
        liquidityGauge.withdraw(_amountOut);
    }

    /**
     * @notice claim rewards ($BAL) from LP position
     * @dev rewards are only accrued for staked positions
     */
    function claimRewards(address gauge) public {
        minter.mint(gauge);
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
     */
    function adjustRelayerApproval(bool _relayerChange) public virtual {
        vault.setRelayerApproval(address(this), address(relayer), _relayerChange);
    }
}
