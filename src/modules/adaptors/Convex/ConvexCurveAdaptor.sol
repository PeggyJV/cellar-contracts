// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IBaseRewardPool } from "src/interfaces/external/Convex/IBaseRewardPool.sol";
import { IBooster } from "src/interfaces/external/Convex/IBooster.sol";
import { CurvePool } from "src/interfaces/external/Curve/CurvePool.sol";
import { CurveHelper } from "src/modules/adaptors/Curve/CurveHelper.sol";

/**
 * @title Convex-Curve Platform Adaptor
 * @dev This adaptor is specifically for Convex-Curve Platform contracts.
 * @notice Allows cellars to have positions where they are supplying, staking LPTs, and claiming rewards to Convex-Curve pools/markets.
 * @author crispymangoes, 0xEinCodes
 * @dev this may not work for Convex with other protocols / platforms / networks. It is important to keep these associated to Curve-Convex Platform on Mainnet
 */
contract ConvexCurveAdaptor is BaseAdaptor, CurveHelper {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    /**
     * @notice The booster for the respective network
     * @dev For mainnet, use 0xF403C135812408BFbE8713b5A23a04b3D48AAE31
     */
    IBooster public immutable booster;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(uint256 pid, address baseRewardPool, ERC20 lpt, CurvePool pool, bytes4 selector)
    // Where:
    // `pid` is the Convex market pool id that corresponds to a respective market within Convex protocol we are working with
    // `baseRewardPool` is the main base reward pool for the respective convex market --> baseRewardPool has extraReward Child Contracts associated to it (that likely follow the same `BaseRewardPool` smart contract schematic). So cellar puts CRVLPT into Convex Booster, which then stakes it into Curve.
    // `lpt` is the Curve LPT that is deposited into the respective Convex-Curve Platform market.
    // `pool` is the Curve liquidity pool adhering to the CurvePool interface
    // `selector` is the function signature specified within adaptorData to be triggered within the callee contract
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
    error ConvexAdaptor__ConvexBoosterPositionsMustBeTracked(
        uint256 pid,
        address baseRewardPool,
        ERC20 lpt,
        CurvePool _curvePool,
        bytes4 _selector
    );

    /**
     * @notice Attempted to pass adaptorData that does not comply with the stored information within Convex Booster records.
     */
    error ConvexAdaptor__ConvexBoosterPositionsDoesNotMatchAdaptorData(
        uint256 pid,
        address baseRewardPool,
        ERC20 lpt,
        CurvePool pool,
        bytes4 selector
    );

    /**
     * @param _booster the Convex booster contract for the network/market (different booster for Curve, FRAX, Prisma, etc.)
     * @dev Booster.sol serves as the primary contract that accounts for markets via poolIds. PoolInfo structs can be queried w/ poolIds, where baseRewardPool contracts, and other info can be obtained.
     */
    constructor(address _booster, address _nativeWrapper) CurveHelper(_nativeWrapper) {
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
        return keccak256(abi.encode("Convex Curve Adaptor V 0.0"));
    }

    //============================================ Implement Base Functions ===========================================

    /**
     * @notice Deposit & Stakes LPT from the cellar into Convex Market at the end of the user deposit sequence.
     * @param assets amount of LPT to deposit and stake
     * @param adaptorData see adaptorData info at top of this smart contract
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        (uint256 pid, address rewardsPool, ERC20 lpt, CurvePool pool, bytes4 selector) = abi.decode(
            adaptorData,
            (uint256, address, ERC20, CurvePool, bytes4)
        );
        _validatePositionIsUsed(pid, rewardsPool, lpt, pool, selector);
        if (selector != bytes4(0)) _callReentrancyFunction(pool, selector);
        else revert BaseAdaptor__UserDepositsNotAllowed();
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

        // Run external receiver check.
        _externalReceiverCheck(receiver);

        (uint256 pid, address rewardPool, ERC20 lpt, CurvePool pool, bytes4 selector) = abi.decode(
            adaptorData,
            (uint256, address, ERC20, CurvePool, bytes4)
        );
        _validatePositionIsUsed(pid, rewardPool, lpt, pool, selector);
        if (isLiquid && selector != bytes4(0)) {
            _callReentrancyFunction(pool, selector);
        } else revert BaseAdaptor__UserWithdrawsNotAllowed();
        IBaseRewardPool baseRewardPool = IBaseRewardPool(rewardPool);
        baseRewardPool.withdrawAndUnwrap(amount, false);
        lpt.safeTransfer(receiver, amount);
    }

    /**
     * @notice Functions Cellars use to determine the withdrawable balance from an adaptor position.
     * @dev Accounts for LPTs staked in Convex Market from calling Cellar.
     * @param adaptorData see adaptorData info at top of this smart contract
     * @param configurationData see configurationData at top of this smart contract
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory configurationData
    ) public view override returns (uint256) {
        bool isLiquid = abi.decode(configurationData, (bool));
        (, address rewardPool, , , bytes4 selector) = abi.decode(
            adaptorData,
            (uint256, address, ERC20, CurvePool, bytes4)
        );

        if (isLiquid && selector != bytes4(0)) {
            IBaseRewardPool baseRewardPool = IBaseRewardPool(rewardPool);
            return (baseRewardPool.balanceOf(msg.sender));
        } else return 0;
    }

    /**
     * @notice Calculates the Cellar's balance of the positions creditAsset, a specific underlying LPT.
     * @param adaptorData see adaptorData info at top of this smart contract
     * @return total balance of LPT staked in Convex-Curve Platform for Cellar
     * NOTE: This assumes that no rewards are given back as accrual of more curveLPT. I believe that to be the case because BaseRewardPool has its own rewardsToken, and extraRewards has specific reward contracts specific to respective convex markets.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        (, address rewardPool) = abi.decode(adaptorData, (uint256, address));
        IBaseRewardPool baseRewardPool = IBaseRewardPool(rewardPool);
        uint256 balance = baseRewardPool.balanceOf(msg.sender);
        if (balance > 0) {
            // Run check to make sure Cellar uses an oracle.
            _ensureCallerUsesOracle(msg.sender);
        }
        return balance;
    }

    /**
     * @notice Returns the positions underlying assets.
     * @param adaptorData see adaptorData info at top of this smart contract
     * @return Underlying LPT for Cellar's respective Convex market position
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        (uint256 pid, address rewardsPool, ERC20 lpt, CurvePool pool, bytes4 selector) = abi.decode(
            adaptorData,
            (uint256, address, ERC20, CurvePool, bytes4)
        );

        // compare against booster (queried lpt (qlpt) & queried RewardsPool (qRewardsPool))
        (address qlpt, , , address qRewardsPool, , ) = booster.poolInfo(pid);
        if ((address(lpt) != qlpt) || (rewardsPool != qRewardsPool)) {
            revert ConvexAdaptor__ConvexBoosterPositionsDoesNotMatchAdaptorData(pid, rewardsPool, lpt, pool, selector);
        }
        return lpt;
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
     * NOTE: stake bool in `boosted.deposit()` function to stake assets is set to always true for strategist calls
     */
    function depositLPTInConvexAndStake(
        uint256 _pid,
        address _baseRewardPool,
        ERC20 _lpt,
        CurvePool _pool,
        bytes4 _selector,
        uint256 _amount
    ) public {
        _validatePositionIsUsed(_pid, _baseRewardPool, _lpt, _pool, _selector); // validate pid representing convex market within respective booster
        _amount = _maxAvailable(_lpt, _amount);

        _lpt.approve(address(booster), _amount);
        booster.deposit(_pid, _amount, true);
        _revokeExternalApproval(_lpt, address(booster));
    }

    /**
     * @notice Allows strategists to withdraw from Convex markets via Booster contract w/ or w/o claiming rewards
     * NOTE: this adaptor will always unwrap to CRV LPTs if possible. It will not keep the position in convex wrapped LPT position.
     * NOTE: If _claim is true, this claims all rewards associated to a cellar interacting w/ Convex markets. The BaseRewardPool contract has the function for withdrawing and unwrapping whilst also claiming all rewards. NOTE: if it does not claim all extra rewards (say another reward contract is linked to it somehow), then we can just make other adaptors that handle that.
     * @param _baseRewardPool for respective convex market (w/ trusted poolId)
     * @param _amount of LPTs to unstake, unwrap, and withdraw from convex market to calling cellar
     * @param _claim whether or not to claim all rewards from BaseRewardPool
     */
    function withdrawFromBaseRewardPoolAsLPT(address _baseRewardPool, uint256 _amount, bool _claim) public {
        IBaseRewardPool baseRewardPool = IBaseRewardPool(_baseRewardPool);
        _amount = _maxAvailable(ERC20(_baseRewardPool), _amount);
        baseRewardPool.withdrawAndUnwrap(_amount, _claim);
    }

    /**
     * @notice Allows strategists to get rewards for an Convex Booster without withdrawing/unwrapping from Convex market
     * @param _baseRewardPool for respective convex market (w/ trusted poolId)
     * @param _claimExtras Whether or not to claim extra rewards associated to the Convex booster (outside of rewardToken for Convex booster)
     */
    function getRewards(address _baseRewardPool, bool _claimExtras) public {
        _getRewards(_baseRewardPool, _claimExtras);
    }

    /**
     * @notice Validates that a given pid (poolId), and baseRewardPool are set up as a position with this adaptor in the calling Cellar.
     * @dev This function uses `address(this)` as the address of the calling Cellar.
     */
    function _validatePositionIsUsed(
        uint256 _pid,
        address _baseRewardPool,
        ERC20 _lpt,
        CurvePool _curvePool,
        bytes4 _selector
    ) internal view {
        uint256 cellarCodeSize;
        address cellarAddress = address(this);
        assembly {
            cellarCodeSize := extcodesize(cellarAddress)
        }

        if (cellarCodeSize > 0) {
            bytes32 positionHash = keccak256(
                abi.encode(identifier(), false, abi.encode(_pid, _baseRewardPool, _lpt, _curvePool, _selector))
            );
            uint32 positionId = Cellar(address(this)).registry().getPositionHashToPositionId(positionHash);
            if (!Cellar(address(this)).isPositionUsed(positionId)) {
                revert ConvexAdaptor__ConvexBoosterPositionsMustBeTracked(
                    _pid,
                    _baseRewardPool,
                    _lpt,
                    _curvePool,
                    _selector
                );
            }
        } // else do nothing. The cellar is currently being deployed so it has no bytecode, and trying to call `cellar.registry()` will revert.
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
