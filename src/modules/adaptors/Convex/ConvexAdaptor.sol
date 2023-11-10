// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IBaseRewardPool } from "src/interfaces/external/Convex/IBaseRewardPool.sol";
import { IBooster } from "src/interfaces/external/Convex/IBooster.sol";

/**
 * @title Convex Adaptor
 * @dev This adaptor is specifically for Convex contracts.
 * @notice Allows cellars to have positions where they are supplying, staking LPTs, and claiming rewards to Convex markets.
 * @author crispymangoes, 0xEinCodes
 * @dev TODO: this may not work for Convex with other protocols (FRAX, Prisma, etc.). FRAX contract architecture shows some discrepancies (need to confirm). Side-Chain implementations for convex markets showcase other discrepancies too in external function signatures, etc.
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
    //      position can support user withdraws
    // else:
    //      position can not support user withdraws
    //====================================================================

    /**
     * @notice Attempted to interact with a Convex market pid & baseRewardPool that the Cellar is not using.
     */
    error ConvexAdaptor__ConvexBoosterPositionsMustBeTracked(uint256 pid, address baseRewardPool);

    /**
     * @param _booster the Convex booster contract for the network/market (different booster for Curve, FRAX, Prisma, etc.)
     * @dev Booster.sol serves as the primary contract that accounts for markets via poolIds. PoolInfo structs can be queried w/ poolIds, where baseRewardPool contracts, and other info can be obtained.
     */
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
        return keccak256(abi.encode("Convex Curve Adaptor V 0.1"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice Deposit & Stakes LPT from the cellar into Convex Market at the end of the user deposit sequence.
     * @param assets amount of LPT to deposit and stake
     * @param adaptorData see adaptorData info at top of this smart contract
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        (uint256 pid, address rewardsPool) = abi.decode(adaptorData, (uint256, address));
        _validatePositionIsUsed(pid, rewardsPool);
        (address lpToken, , , , , ) = booster.poolInfo(pid);
        ERC20 lpt = ERC20(lpToken); // TODO: double check that struct object is coming out of this properly
        lpt.safeApprove(address(booster), assets);
        booster.deposit(pid, assets, true);

        // Zero out approvals if necessary.
        _revokeExternalApproval(lpt, address(booster));
    }

    /**
     * @notice If a user withdraw needs more LPTs than what is in the Cellar's wallet, then the Cellar will unstake, unwrap cvxLPTs, and withdraw LPTs from Convex
     * @param amount of LPT to unstake, unwrap, and withdraw from Convex market
     * @param receiver see baseAdaptor.sol
     * @param adaptorData see adaptorData info at top of this smart contract
     * @param configurationData see configurationData at top of this smart contract
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

        (uint256 pid, address rewardPool) = abi.decode(adaptorData, (uint256, address));
        _validatePositionIsUsed(pid, rewardPool);

        //TODO: logic that checks if there is enough liquid curveLPT,and if not it does withdrawAndUnwrap(). If this logic is in place, withdrawableFrom() can report staked amount too.

        // booster.withdraw(pid, amount);

        IBaseRewardPool baseRewardPool = IBaseRewardPool(rewardPool);
        baseRewardPool.withdrawAndUnwrap(amount, true); // TODO: not sure if we just always set this to true (might be gas intensive), or if we allow this as a param somehow.
    }

    /**
     * @notice Functions Cellars use to determine the withdrawable balance from an adaptor position.
     * @dev Accounts for LPTs in the Cellar's wallet, and staked in Convex Market.
     * @param adaptorData see adaptorData info at top of this smart contract
     * @param configurationData see configurationData at top of this smart contract
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory configurationData
    ) public view override returns (uint256) {
        bool isLiquid = abi.decode(configurationData, (bool));
        if (isLiquid) {
            (, address rewardPool) = abi.decode(adaptorData, (uint256, address));
            IBaseRewardPool baseRewardPool = IBaseRewardPool(rewardPool);
            ERC20 stakingToken = ERC20(baseRewardPool.stakingToken());
            return (stakingToken.balanceOf(msg.sender) + baseRewardPool.balanceOf(msg.sender));
        } else return 0;
    }

    /**
     * @notice Calculates the Cellar's balance of the positions creditAsset, a specific underlying LPT.
     * @param adaptorData see adaptorData info at top of this smart contract
     * @return total balance of LPT for Cellar, including liquid and staked
     * TODO: This assumes that no rewards are given back as accrual of more curveLPT. I believe that to be the case because BaseRewardPool has its own rewardsToken, and extraRewards has specific reward contracts specific to respective convex markets.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (, address rewardPool) = abi.decode(adaptorData, (uint256, address));
        IBaseRewardPool baseRewardPool = IBaseRewardPool(rewardPool);
        ERC20 stakingToken = ERC20(baseRewardPool.stakingToken());
        return (stakingToken.balanceOf(msg.sender) + baseRewardPool.balanceOf(msg.sender));
    }

    /**
     * @notice Returns the positions underlying assets.
     * @param adaptorData see adaptorData info at top of this smart contract
     * @return Underlying LPT for Cellar's respective Convex market position
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        (uint256 pid, ) = abi.decode(adaptorData, (uint256, address));
        (address lpToken, , , , , ) = booster.poolInfo(pid);
        ERC20 lpt = ERC20(lpToken);
        return lpt;
        // TODO: decide to use above or alternative way to get lpt below
        // IBaseRewardPool rewardsPool = IBaseRewardPool(rewardsPool);
        // return ERC(rewardsPool.stakingToken());
    }

    /**
     * @notice When positions are added to the Registry, this function can be used in order to figure out
     *         what assets this adaptor needs to price, and confirm pricing is properly setup.
     * @param adaptorData see adaptorData info at top of this smart contract
     * @return assets Underlying assets for Cellar's respective Convex market position
     * @dev all breakdowns of LPT pricing and its underlying assets are done through the PriceRouter extension (in accordance to PriceRouterv2 architecture)
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
     * @notice Allows strategists to deposit and stake LPTs into Convex markets via the respective Convex market Booster contract
     * @param _pid specified pool ID corresponding to LPT convex market
     * @param _amount amount of LPT to deposit and stake
     * @param _stake whether or not to stake Convex wrapped LPTs (into respective BaseRewardPool) after depositing LPTs into Convex Market
     * TODO: stake bool: not sure if we just always set this to true (might be gas intensive), or if we allow this as a param somehow.
     */
    function deposit(uint256 _pid, address _baseRewardPool, uint256 _amount, bool _stake) public {
        _validatePositionIsUsed(_pid, _baseRewardPool); // validate pid representing convex market within respective booster
        booster.deposit(_pid, _amount, _stake);
    }

    /**
     * @notice Allows strategists to withdraw from Convex markets via Booster contract without claiming rewards
     * NOTE: this adaptor will always unwrap to CRV LPTs if possible. It will not keep the position in convex wrapped LPT position.
     * TODO: likely removing this functionality since unless gas is so expensive to withdrawFromBaseRewardPoolAsLPT() where we can specify to get w/ rewards or w/o
     * @param _pid specified pool ID corresponding to LPT convex market
     * @param _amount amount of cvxLPT to unstake, and withdraw (TODO: can't recall if this unwraps to LPT)
     */
    function withdrawFromBoosterNoRewards(uint256 _pid, address _baseRewardPool, uint256 _amount) public {
        _validatePositionIsUsed(_pid, _baseRewardPool);
        booster.withdraw(_pid, _amount);
    }

    /**
     * @notice Allows strategists to withdraw from Convex markets via Booster contract w/ or w/o claiming rewards
     * NOTE: this adaptor will always unwrap to CRV LPTs if possible. It will not keep the position in convex wrapped LPT position.
     * TODO: if _claim is true, this claims all rewards associated to a cellar interacting w/ Convex markets. The BaseRewardPool contract has the function for withdrawing and unwrapping whilst also claiming all rewards. NOTE: if it does not claim all extra rewards (say another reward contract is linked to it somehow), then we can just make other adaptors that handle that.
     * TODO: decide which function to use for withdrawing based on gas consumption for adaptor calls? Either: withdrawFromBoosterNoRewards() && getRewards() OR withdrawFromBaseRewardPoolAsLPT() && getRewards()
     * @param _baseRewardPool for respective convex market (w/ trusted poolId)
     * @param _amount of LPTs to unstake, unwrap, and withdraw from convex market to calling cellar
     * @param _claim whether or not to claim all rewards from BaseRewardPool
     */
    function withdrawFromBaseRewardPoolAsLPT(address _baseRewardPool, uint256 _amount, bool _claim) public {
        IBaseRewardPool baseRewardPool = IBaseRewardPool(_baseRewardPool);
        baseRewardPool.withdrawAndUnwrap(_amount, _claim);
    }

    /**
     * @notice Allows strategists to get rewards for an Convex Booster without withdrawing/unwrapping from Convex market
     * @param _pid specified pool ID corresponding to LPT convex market
     * @param _baseRewardPool for respective convex market (w/ trusted poolId)
     * @param _claimExtras Whether or not to claim extra rewards associated to the Convex booster (outside of rewardToken for Convex booster)
     */
    function getRewards(uint256 _pid, address _baseRewardPool, bool _claimExtras) public {
        _validatePositionIsUsed(_pid, _baseRewardPool);
        _getRewards(_baseRewardPool, _claimExtras);
    }

    /**
     * @notice Validates that a given pid (poolId), and baseRewardPool are set up as a position with this adaptor in the calling Cellar.
     * @dev This function uses `address(this)` as the address of the calling Cellar.
     */
    function _validatePositionIsUsed(uint256 _pid, address _baseRewardPool) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_pid, _baseRewardPool)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert ConvexAdaptor__ConvexBoosterPositionsMustBeTracked(_pid, _baseRewardPool);
    }

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // It is unlikely, but Convex interfaces can change between versions.
    // To account for this, internal functions will be used in case it is needed to
    // implement new functionality.
    //===============================================================================

    /**
     * @dev Uses baseRewardPool.getReward() to claim rewards for your address or an arbitrary address.  There is a getRewards() function option where there is a bool as an option to also claim extra incentive tokens (ex. snx) which is defaulted to true in the non-parametrized version.
     */
    function _getRewards(address _baseRewardPool, bool _claimExtras) internal virtual {
        IBaseRewardPool baseRewardPool = IBaseRewardPool(_baseRewardPool);
        baseRewardPool.getReward(address(this), _claimExtras);
    }
}
