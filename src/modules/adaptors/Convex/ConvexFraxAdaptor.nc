// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IProxyVault } from "src/interfaces/external/Convex/Convex-Frax-Platform/IProxyVault.sol";
import { IPoolRegistry } from "src/interfaces/external/Convex/Convex-Frax-Platform/IPoolRegistry.sol";
import { IBooster } from "src/interfaces/external/Convex/Convex-Frax-Platform/IBooster.sol";
import {IVoterProxy} from "src/interfaces/external/Convex/Convex-Frax-Platform/IVoterProxy.sol";
import {IFraxFarmERC20_V2} from "src/interfaces/external/Convex/IFraxFarmERC20_V2.sol";
/**
 * @title Convex-Frax Platform Adaptor
 * @dev This adaptor is specifically for Convex-Frax Platform Markets.
 * @notice Allows cellars to have positions where they are supplying, staking Frax Yield Bearing Tokens (YBT), and claiming rewards to Convex markets.
 * @author crispymangoes, 0xEinCodes
 * @dev This is a different architecture to the Curve-Frax Platform Markets. The primary difference is that a very different Booster.sol contract is used to create personal staking proxy vaults for users (Cellars in this case). The proxy vaults are what users (cellars) interact with to ultimately interact with the underlying FRAX-related logic. Socialized boosted rewards are turned on for the vault and its respective staked FraxYBT.
 * NOTE: Convex-FRAX platform markets typically require a time-lock. So positions are illiquid for varying time-frames based on specifications from Strategists (see Strategist Functions). Thus positions with this adaptor will be illiquid from User standpoint.
 */
contract ConvexFraxAdaptor is BaseAdaptor {
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
     * @notice The VoteProxy where all the vefxs is locked and thus immutable
     * @dev For mainnet, use 0x59CFCD384746ec3035299D90782Be065e466800B
     */
    IVoterProxy public immutable voterProxy;

    /**
     * @notice The poolRegistry for the Convex-Frax Platform on this respective network
     */
    IPoolRegistry public immutable poolRegistry;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(uint256 pid)
    // Where:
    // `pid` is the Convex market pool id that corresponds to a respective market within Convex protocol we are working with. `pid` is used w/ `booster` and `poolRegistry` to obtain the cellar's `vault` where all mutative functionality is done through.
    // NOTE We are currently assuming that the `Booster.sol` and `PoolRegistry.sol` are the same across all Convex-Frax Platform markets.
    // NOTE: `voteProxy` is to be used to find out which `Booster` is the current one. getter `operator()` is used to find the current `Booster` within `voteProxy`

    //================= Configuration Data Specification =================
    // N/A
    //====================================================================

    /**
     * @notice Attempted to interact with a Convex-Frax Platform market pid that the Cellar is not using.
     */
    error ConvexFraxAdaptor__ConvexPIDPositionsMustBeTracked(uint256 pid);

    /**
     * @param _voteProxy the Convex-Frax voteProxy for the network.
     * @param _poolRegistry the Convex-Frax Platform poolRegistry contract for the network.
     * @dev Booster.sol serves as the primary contract that creates staking proxy vaults that are registered within the `PoolRegistry`. Vault addresses can be queried w/ poolIds, and user address (in this case the Cellar itself).
     * TODO: decided to keep `address poolRegistry` to the adaptor storage if it is used a lot throughout adaptor implementation or not.
     * TODO: maybe make poolRegistry a permissioned setter so we can change it if they decide to upgrade poolRegistry. Otherwise, need new adaptor deployment for new poolRegistries.
     */
    constructor(address _voteProxy, address _poolRegistry) {
        voterProxy = IVoterProxy(_voteProxy);
        poolRegistry = IPoolRegistry(_poolRegistry);
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("Convex Frax Adaptor V 0.0"));
    }

    //============================================ Implement Base Functions =========================================== TODO: EIN still gotta do base functions

    /**
     * TODO: EIN
     * @notice Deposit & Stakes Frax YBT from the cellar into Convex-Frax Platform Market at the end of the user deposit sequence.
     * @param assets amount of YBT to deposit and stake
     * @param adaptorData see adaptorData info at top of this smart contract
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        uint256 pid = abi.decode(adaptorData, (uint256, address));
        _validatePositionIsUsed(pid);

        // TODO:

        (address lpToken, , , , , ) = booster.poolInfo(pid);
        ERC20 lpt = ERC20(lpToken); // TODO: double check that struct object is coming out of this properly
        lpt.safeApprove(address(booster), assets);
        booster.deposit(pid, assets, true);

        // Zero out approvals if necessary.
        _revokeExternalApproval(lpt, address(booster));
    }

    /**
     * TODO: EIN
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
     * TODO: EIN
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
     * TODO: EIN
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
     * TODO: EIN
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
     * @notice Allows strategists to create a personal staking proxy vault for the cellar, and then deposit and stake LPTs into Convex-Frax markets via the respective Convex market Booster contract.
     * @param _pid specified pool ID corresponding to Frax YBT convex market
     * @param _liquidity amount of Frax YBT to deposit and stake
     * @param _secs amount of seconds to lock cvxFrax YBT for cellar to recei ve max rewards.
     * NOTE: PoolRegistry can be upgraded / changed so Convex protocol must be monitored in the case that this happens. This would be a more convoluted upgrade though so it would go through governance first presumably. TODO: confirm this.
     */
    function deposit(uint256 _pid, uint256 _liquidity, uint256 _secs) public {
        _validatePositionIsUsed(_pid); // TODO: validate pid representing convex market within respective booster
        address vault;
        // check if vault has been created
        if (poolRegistry.vaultMap(_pid, msg.sender) == address(0)) {
            vault = IBooster(voterProxy.operator()).createVault(_pid); // even if createVault(pid) was called somehow by calling cellar, and it already had one, it would revert within `Booster.sol`
        } else {
            vault = poolRegistry.vaultMap(_pid, msg.sender);
        }
        IProxyVault proxyVault = IProxyVault(vault);
        proxyVault.stakeLockedCurveLp(_liquidity, _secs); // deposits LPT and stakes it, generating a bytes _kek_id within a mapping of struct arrays associated to msg.sender (this cellar)
    }

    /// TODO: EIN THIS IS WHERE YOU LEFT OFF

    /**
     * @notice Allows strategists to withdraw from Convex-Frax markets via vault contract without claiming rewards to cellar.
     * NOTE: this adaptor will always unwrap to underlying Yield Bearing Tokens (YBTs) if possible. It will not keep the position in convex wrapped LPT position.
     * @param _pid specified pool ID corresponding to LPT convex market
     * @param _amount amount of cvxLPT to unstake, unwrap and withdraw
     * NOTE: _kek_id is a bytes ID stored within a struct array:         lockedStakes[staker_address].LockedStake[i].kek_id
     * where:
     *      struct LockedStake {
     *          bytes32 kek_id;
     *          uint256 start_timestamp;
     *          uint256 liquidity;
     *          uint256 ending_timestamp;
     *          uint256 lock_multiplier; // 6 decimals of precision. 1x = 1000000
     * }
     */
    function withdrawLockedAndUnwrap(uint256 _pid, uint256 _amount) public {
        _validatePositionIsUsed(_pid);
        if (poolRegistry.vaultMap(_pid, msg.sender) == address(0)) {
            revert; // TODO: error statement
        }

        IProxyVault proxyVault = IProxyVault(vault);
        address _stakingAddress = proxyVault.stakingAddress(); // get stakingAddress from proxyVault. Import an appropriate interface to interact with the stakingAddress, to specifically access:     mapping(address => LockedStake[]) public lockedStakes;

        IFraxFarmERC20_V2 stakingAddress = IFraxFarmERC20_V2(_stakingAddress);
        if(stakingAddress.lockedStakesOfLength(msg.sender) > 1) revert; // TODO: unsure if we want to allow more than one time-locked position per Frax YBT. For now, we keep things simple and just allow one-element-sized LockedStake array for a cellar per staking address. Otherwise we have multiple LockedStake positions to keep track of.
        bytes kek_id = stakingAddress.lockedStakes(address(this),0).kek_id; // Now, we access the lockedStakes[address(this)] for this vault proxy.
        proxyVault.withdrawLockedAndUnwrap(bytes32 _kek_id); // NOTE: this does not claim rewards to owner, it does claim rewards to this vault though. So Strategist will need to claim rewards via separate strategist function. 
    }

    /**
     * TODO: EIN WHERE YOU LEFT OFF
     * @notice Allows strategists to get rewards for Convex-Frax platform from their own staking proxy vault without withdrawing/unwrapping from Convex market
     * @param _pid specified pool ID corresponding to LPT convex market
     * @param _claimExtras TODO: not sure if there are bools for claiming ExtraRewards or not. 
     * NOTE: according to C2tP, it's best to use this helper bc `earned()` does not incl. fees and some pools might be slightly off: https://etherscan.io/address/0x9Ce7c648244F111CCd338Cc5e269C5961ad9B308#code
     */
    function getRewards(uint256 _pid, address _baseRewardPool, bool _claimExtras) public {
        // TODO: EIN - see helper contract as per comment above, current understanding is that rewards are distributed to the vault whenever deposits or withdraws happen from the Cellar to the proxy vault. This needs to be confirmed though.

        _validatePositionIsUsed(_pid, _baseRewardPool);
        _getRewards(_baseRewardPool, _claimExtras);
    }

    /**
     * TODO: EIN
     * @notice Validates that a given pid (poolId) are set up as a position with this adaptor in the calling Cellar.
     * @dev This function uses `address(this)` as the address of the calling Cellar.
     */
    function _validatePositionIsUsed(uint256 _pid) internal view {
        bytes32 positionHash = keccak256(abi.encode(identifier(), false, abi.encode(_pid)));
        uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
        if (!Cellar(address(this)).isPositionUsed(positionId))
            revert ConvexFraxAdaptor__ConvexPIDPositionsMustBeTracked(_pid);
    }

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // It is unlikely, but Convex interfaces can change between versions.
    // To account for this, internal functions will be used in case it is needed to
    // implement new functionality.
    //===============================================================================

    /**
     * TODO: EIN
     * @dev Uses baseRewardPool.getReward() to claim rewards for your address or an arbitrary address.  There is a getRewards() function option where there is a bool as an option to also claim extra incentive tokens (ex. snx) which is defaulted to true in the non-parametrized version.
     */
    function _getRewards(address _baseRewardPool, bool _claimExtras) internal virtual {
        IBaseRewardPool baseRewardPool = IBaseRewardPool(_baseRewardPool);
        baseRewardPool.getReward(address(this), _claimExtras);
    }
}
