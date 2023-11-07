// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IBaseRewardPool } from "src/interfaces/external/Convex/IBaseRewardPool.sol";

/**
 * @title Convex Adaptor
 * @dev This adaptor is specifically for Convex contracts.
 * @notice Allows cellars to have positions where they are supplying, staking LPTs, and claiming rewards to Convex markets.
 * @author crispymangoes, 0xEinCodes
 * @dev TODO: this may not work for Convex with other protocols (FRAX, Prisma, etc.).
 */
contract ConvexAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    /**
     * @notice The booster for the respective network
     * @dev For mainnet, use 0xF403C135812408BFbE8713b5A23a04b3D48AAE31
     */
    IBooster public immutable booster;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(uint256 pid, address baseRewardPool)
    // Where:
    // `pid` is the Convex market pool id that corresponds to a respective market within Convex protocol we are working with, and `baseRewardPool` is the isolated base reward pool for the respective convex market
    // NOTE that there can be multiple market addresses associated with the same Curve LPT, thus it is important to focus on the market pid  itself, and not constituent assets / LPTs.

    //================= Configuration Data Specification =================
    // configurationData = abi.encode(bool isLiquid)
    // Where:
    // `isLiquid` dictates whether the position is liquid or not
    // If true:
    //      position can support use withdraws
    // else:
    //      position can not support user withdraws
    //====================================================================

    /**
     * @notice Attempted to interact with a Convex market pid that the Cellar is not using.
     */
    error ConvexAdaptor__ConvexBoosterPositionsMustBeTracked(uint256 pid, address baseRewardsPool);

    constructor(address _booster) {
        booster = IBooster(_booster);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Convex Supply Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice User deposits are allowed into this position.
     */
    function deposit(
        uint256 assets,
        address recipient,
        bytes memory adaptorData,
        bytes memory configurationData
    ) public pure override {
        // TODO: EIN
        (uint256 _pid, address _rewardsPool) = abi.decode(adaptorData, (uint256, address));
        _validatePositionIsUsed(_pid, _rewardsPool);
        ERC20 lpt = ERC20(booster.PoolInfo(pid).lpToken()); // TODO: double check that struct object is coming out of this properly
        lpt.safeApprove(address(booster), assets);
        booster.deposit(_pid, _amount, true);

        // Zero out approvals if necessary.
        _revokeExternalApproval(asset, address(booster));
    }

    /**
     * @notice If a user withdraw needs more LPTs than what is in the Cellar's
     *         wallet, then the Cellar will unstake cvxLPTs from Convex
     */
    function withdraw(
        uint256 amount,
        address receiver,
        bytes memory adaptorData,
        bytes memory configurationData
    ) public override {
        // Check that position is setup to be liquid.
        bool isLiquid = abi.decode(configurationData, (bool));
        if (!isLiquid) revert BaseAdaptor__UserWithdrawsNotAllowed();

        // Run external receiver check.
        _externalReceiverCheck(receiver);

        (uint256 _pid, address _rewardsPool) = abi.decode(adaptorData, (uint256, address));
        _validatePositionIsUsed(_pid, _rewardsPool);

        booster.withdraw(_pid, _amount);
        IBaseRewardsPool rewardsPool = IBaseRewardsPool(_rewardsPool);
        rewardsPool.withdrawAndUnwrap(amount, _claim); // TODO: not sure if we just always set this to true (might be gas intensive), or if we allow this as a param somehow.
    }

    /**
     * @notice Functions Cellars use to determine the withdrawable balance from an adaptor position.
     * @dev Accounts for LPTs in the Cellar's wallet, and staked in Convex Market.
     * @dev See `balanceOf`.
     * TODO: get Crispy's thoughts on when we are considering these positions liquid (does staked LPTs count?)
     * TODO: EIN THIS IS WHERE YOU LEFT OFF.
     */
    function withdrawableFrom(
        bytes memory _adaptorData,
        bytes memory configurationData
    ) public view override returns (uint256) {
        bool isLiquid = abi.decode(configurationData, (bool));
        if (isLiquid) {
            ERC4626 erc4626Vault = abi.decode(adaptorData, (ERC4626));
            return erc4626Vault.maxWithdraw(msg.sender);
        } else return 0;
    }

    /**
     * @notice Calculates the Cellar's balance of the positions creditAsset, a specific underlying LPT.
     * @param _adaptorData encoded data for trusted adaptor position detailing the LPT and poolId for the convex market that holds any of the Cellar's staked LPTs
     * @return total balance of LPT for Cellar, including liquid and staked
     */
    function balanceOf(bytes memory _adaptorData) public view override returns (uint256) {
        // TODO: EIN - use below balancer implementation as reference.
        // (ERC20 bpt, address liquidityGauge) = abi.decode(_adaptorData, (ERC20, address));
        // if (liquidityGauge == address(0)) return ERC20(bpt).balanceOf(msg.sender);
        // ERC20 liquidityGaugeToken = ERC20(liquidityGauge);
        // uint256 stakedBPT = liquidityGaugeToken.balanceOf(msg.sender);
        // return ERC20(bpt).balanceOf(msg.sender) + stakedBPT;
    }

    /**
     * @notice Returns the positions underlying assets.
     * @param _adaptorData encoded data for trusted adaptor position detailing the LPT and poolId for the convex market that holds any of the Cellar's staked LPTs
     * @return Underlying LPT for Cellar's respective Convex market position
     */
    function assetOf(bytes memory _adaptorData) public pure override returns (ERC20) {
        // TODO: EIN
        // return ERC20(abi.decode(_adaptorData, (address)));
    }

    /**
     * @notice When positions are added to the Registry, this function can be used in order to figure out
     *         what assets this adaptor needs to price, and confirm pricing is properly setup.
     * @param _adaptorData specified underlying LPT of interest
     * @return Underlying assets for Cellar's respective Convex market position
     * @dev all breakdowns of LPT pricing and its underlying assets are done through the PriceRouter extension (in accordance to PriceRouterv2 architecture)
     */
    function assetsUsed(bytes memory _adaptorData) public pure override returns (ERC20[] memory assets) {
        // TODO: EIN
        // assets = new ERC20[](1);
        // assets[0] = assetOf(_adaptorData);
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
     * @notice Allows strategists to deposit into Convex markets via the Booster contract
     * NOTE - EIN: Have adaptor function that takes in whether or not to stake. If they do not decide to stake, we'll need another function to stake unstaked cvxLPTs.
     * @param _booster
     * @param _claimExtras
     * TODO: stake bool: not sure if we just always set this to true (might be gas intensive), or if we allow this as a param somehow.
     */
    function deposit(uint256 _pid, uint256 _amount, bool _stake) public {
        _validatePositionIsUsed(_pid); // validate pid representing convex market within respective booster
        booster.deposit(_pid, _amount, _stake);
    }

    /**
     * @notice Allows strategists to withdraw from Convex markets via Booster contract
     * NOTE: this adaptor will always unwrap to CRV LPTs if possible. It will not keep the position in convex wrapped LPT position.
     * // TODO: not sure if we just always set this to true (might be gas intensive), or if we allow this as a param somehow.
     */
    function withdrawFromBoosterNoRewards(uint256 _pid, uint256 _amount, bool _claim) public {
        _validatePositionIsUsed(_pid);
        booster.withdraw(_pid, _amount);
    }

    /**
     * @notice Allows strategists to withdraw from Convex markets via Booster contract
     * NOTE: this adaptor will always unwrap to CRV LPTs if possible. It will not keep the position in convex wrapped LPT position.
     * TODO: this claims all rewards associated to a cellar interacting w/ Convex markets. The BaseRewardsPool contract has the function for withdrawing and unwrapping whilst also claiming all rewards (TODO: check that it claims all rewards). If it doesn't, or we don't have enough time, then we can just make other adaptors that handle that.
     * TODO: decide which to do based on gas consumption for adaptor calls?
     */
    function withdrawFromBaseRewardsAsLPT(address _rewardsPool, uint256 _amount, bool _claim) public {
        IBaseRewardsPool rewardsPool = IBaseRewardsPool(_rewardsPool);
        rewardsPool.withdrawAndUnwrap(_amount, _claim);
    }

    /**
     * @notice Allows strategists to get rewards for an Convex Booster without withdrawing/unwrapping from Convex market
     * @param _booster the specified booster
     * @param _claimExtras Whether or not to claim extra rewards associated to the Convex booster (outside of rewardToken for Convex booster)
     */
    function getRewards(IBaseRewardPool _booster, bool _claimExtras) public {
        _validatePositionIsUsed(address(_booster));
        _getRewards(_booster, _claimExtras);
    }

    /**
     * @notice Validates that a given booster is set up as a position in the calling Cellar.
     * @dev This function uses `address(this)` as the address of the calling Cellar.
     * TODO: possibly add address _rewardsPool to the adaptorData etc.
     */
    function _validatePositionIsUsed(uint256 _pid, address _baseRewardsPool) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_pid, _baseRewardsPool)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert ConvexAdaptor__ConvexBoosterPositionsMustBeTracked(_pid, _baseRewardsPool);
    }

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // It is unlikely, but Convex interfaces can change between versions.
    // To account for this, internal functions will be used in case it is needed to
    // implement new functionality.
    //===============================================================================

    /**
     * @dev Uses baseRewardPool.getReward() to claim rewards for your address or an arbitrary address.  There is an getRewards() function option where there is a bool as an option to also claim extra incentive tokens (ex. snx) which is defaulted to true in the non-parametrized version. More information on extra rewards below.
     */
    function _getRewards(IBaseRewardPool _booster, bool _claimExtras) internal virtual {
        _booster.getReward(address(this), _claimExtras);
    }
}
