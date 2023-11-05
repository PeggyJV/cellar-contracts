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
    // adaptorData = abi.encode(uint256 pid)
    // Where:
    // `pid` is the Convex market pool id that corresponds to a respective market within Convex protocol we are working with.
    // NOTE that there can be multiple market addresses associated with the same Curve LPT, thus it is important to focus on the market pid  itself, and not constituent assets / LPTs.
    //================= Configuration Data Specification =================
    // NA
    //====================================================================

    /**
     * @notice Attempted to interact with a Convex market pid that the Cellar is not using.
     */
    error ConvexAdaptor__ConvexBoosterPositionsMustBeTracked(uint256 pid);

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

    //============================================ Implement Base Functions =========================================== TODO: EIN THIS IS WHERE YOU LEFT OFF - GOTTA DO BASE FUNCTIONS

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows strategists to deposit into Convex markets via the Booster contract
     * NOTE - EIN: Have adaptor function that takes in whether or not to stake. If they do not decide to stake, we'll need another function to stake unstaked cvxLPTs.
     * @param _booster
     * @param _claimExtras
     */
    function deposit(uint256 _pid, uint256 _amount, bool _stake) public {
        _validateBooster(_pid); // validate pid representing convex market within respective booster
        booster.deposit(_pid, _amount, _stake);

        // TODO: check that the correct amount was deposited and the correct "share" allocation was given within Convex market (not sure if we get ERC20 back of if it is internal measurements)
    }

    /**
     * @notice Allows strategists to withdraw from Convex markets via Booster contract
     * NOTE: this adaptor will always unwrap to CRV LPTs if possible. It will not keep the position in convex wrapped LPT position.
     */
    function withdrawFromBoosterNoRewards(uint256 _pid, uint256 _amount, bool _claim) public {
        _validateBooster(_pid);
        booster.withdraw(_pid, _amount);
    }

    /**
     * @notice Allows strategists to withdraw from Convex markets via Booster contract
     * NOTE: this adaptor will always unwrap to CRV LPTs if possible. It will not keep the position in convex wrapped LPT position.
     * TODO: this claims all rewards associated to a cellar interacting w/ Convex markets. The BaseRewardsPool contract has the function for withdrawing and unwrapping whilst also claiming all rewards (TODO: check that it claims all rewards). If it doesn't, or we don't have enough time, then we can just make other adaptors that handle that.
     */
    function withdrawFromBaseRewardsAsCRV(address _rewardsPool, uint256 _amount, bool _claim) public {
        //TODO: possibly add address _rewardsPool to the adaptorData etc.
        IBaseRewardsPool rewardsPool = IBaseRewardsPool(_rewardsPool);
        rewardsPool.withdrawAndUnwrap(_amount, _claim);
    }

    /**
     * @notice Allows strategists to get rewards for an Convex Booster without withdrawing/unwrapping from Convex market
     * @param _booster the specified booster
     * @param _claimExtras Whether or not to claim extra rewards associated to the Convex booster (outside of rewardToken for Convex booster)
     */
    function getRewards(IBaseRewardPool _booster, bool _claimExtras) public {
        _validateBooster(address(_booster));
        _getRewards(_booster, _claimExtras);
    }

    /**
     * @notice Validates that a given booster is set up as a position in the calling Cellar.
     * @dev This function uses `address(this)` as the address of the calling Cellar.
     * TODO: possibly add address _rewardsPool to the adaptorData etc.
     */
    function _validateBooster(uint256 _pid) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_pid)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert ConvexAdaptor__ConvexBoosterPositionsMustBeTracked(_pid);
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
