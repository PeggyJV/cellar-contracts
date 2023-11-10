// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { ConvexAdaptor } from "src/modules/adaptors/Convex/ConvexAdaptor.sol";
import { IBaseRewardPool } from "src/interfaces/external/Convex/IBaseRewardPool.sol";

import { IBooster } from "src/interfaces/external/Convex/IBooster.sol";

/**
 * @title ConvexAdaptorTest
 * @author crispymangoes, 0xEinCodes
 * @notice Cellar Adaptor tests with Convex markets
 * @dev Mock datafeeds to be used for underlying LPTs. Actual testing of the LPT pricing is carried out TODO: hash out which LPT pair to go with, and what mock datafeeds to use for constituent assets of the pair so we can warp forward to simulat reward accrual.
 */
contract ConvexAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    // from convex (for curve markets)
    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    ConvexAdaptor private convexAdaptor;

    IBooster public immutable booster = IBooster(convexCurveMainnetBooster);
    IBaseRewardPool public rewardsPool; // varies per convex market

    // Chainlink PriceFeeds
    MockDataFeed private mockMkUSDFraxBP_CRVLPT_USDFeed;
    MockDataFeed private mockEth_STETH_CRVLPT_USDFeed;
    
    // TODO: add curve lpt pricing extension when it is ready
    
    // base asset within cellars are the lpts, so we'll just deal lpts to the users to deposit into the cellar. So we need a position for that, and a position for the adaptors w/ pids & baseRewardPool specs.
    uint32 private mkUSDFraxBP_CRVLPT_Position = 1;
    uint32 private eth_STETH_CRVLPT_Position = 2;
    uint32 private cvxPool_mkUSDFraxBP_Position = 3;
    uint32 private cvxPool_STETH_CRVLPT_Position = 4;

    uint256 publit initialAssets;
    
    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18538479;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        deal(address(mkUSDFraxBP_CRVLPT), address(this), 10e18);

        convexAdaptor = new ConvexAdaptor(convexCurveMainnetBooster);

        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        mockMkUSDFraxBP_CRVLPT_USDFeed = new MockDataFeed(WETH_USD_FEED); // TODO: sort out what to use as the mockDataFeed
        mockEth_STETH_CRVLPT_USDFeed = new MockDataFeed(RETH_ETH_FEED);

        uint256 price = uint256(IChainlinkAggregator(address(mockMkUSDFraxBP_CRVLPT_USDFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockMkUSDFraxBP_CRVLPT_USDFeed));
        priceRouter.addAsset(mkUSDFraxBP_CRVLPT, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(mockEth_STETH_CRVLPT_USDFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockEth_STETH_CRVLPT_USDFeed));
        priceRouter.addAsset(eth_STETH_CRVLPT, settings, abi.encode(stor), price);

        mockMkUSDFraxBP_CRVLPT_USDFeed.setMockUpdatedAt(block.timestamp);
        mockEth_STETH_CRVLPT_USDFeed.setMockUpdatedAt(block.timestamp);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(convexAdaptor));

        registry.trustPosition();
        registry.trustPosition(mkUSDFraxBP_CRVLPT_Position, address(erc20Adaptor), abi.encode(mkUSDFraxBP_CRVLPT));
        registry.trustPosition(eth_STETH_CRVLPT_Position, address(erc20Adaptor), abi.encode(eth_STETH_CRVLPT));
        registry.trustPosition(
            cvxPool_mkUSDFraxBP_Position,
            address(convexAdaptor),
            abi.encode(mkUSDFraxBPT_ConvexPID, mkUSDFraxBP_cvxBaseRewardContract)
        );
        registry.trustPosition(
            cvxPool_STETH_CRVLPT_Position,
            address(convexAdaptor),
            abi.encode(eth_STETH_ConvexPID, eth_STETH_cvxBaseRewardContract)
        );

        // Set up Cellar

        string memory cellarName = "mkUSDFraxBP CRVLPT Cellar V0.1";
        uint256 initialDeposit = 1e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(
            cellarName,
            mkUSDFraxBP_CRVLPT,
            mkUSDFraxBP_CRVLPT_Position,
            abi.encode(0),
            initialDeposit,
            platformCut
        );
        
        cellar.setRebalanceDeviation(0.01e18);

        cellar.addAdaptorToCatalogue(address(convexAdaptor));
        cellar.addPositionToCatalogue(cvxPool_mkUSDFraxBP_Position); // cvxPool for mkUSDFraxBP

        cellar.addPosition(0, cvxPool_mkUSDFraxBP_Position, abi.encode(mkUSDFraxBPT_ConvexPID, mkUSDFraxBP_cvxBaseRewardContract), false);

        cellar.setHoldingPosition(cvxPool_mkUSDFraxBP_Position);

        mkUSDFraxBP_CRVLPT.safeApprove(address(cellar), type(uint256).max);

        // TODO: possibly add eth_STETH_CRVLPT details to the cellar as well
        initialAssets = cellar.totalAssets();
    }

    /**
     * THINGS TO TEST (not exhaustive):
     * Deposit Tests

- check that correct amount was deposited without staking (Cellar has cvxCRVLPT) (bool set to false)

- " and that it was all staked (bool set to true)

- check that it reverts properly if attempting to deposit when not having any curve LPT

- check that depositing atop of pre-existing convex position for the cellar works

- check that staking "

- check type(uint256).max works for deposit

---

Withdraw Tests - NOTE: we are not worrying about withdrawing and NOT unwrapping. We always unwrap.

- check correct amount is withdrawn (1:1 as rewards should not be in curve LPT I think) (bool set to false)

  - Also check that, when time is rolled forward, that the CurveLPTs obtained have not changed from when cellar entered the position. Otherwise the assumption that 1 CurveLPT == 1cvxCurveLPT == 1StakedcvxCurveLPT is invalid and `withdrawableFrom()` and `balanceOf()` likely needs to be updated

- check correct amount is withdrawn and rewards are claimed (bool set to true)

- check type(uint256).max works for withdraw

- check that withdrawing partial amount works (bool set to false)

- " (bool set to true with rewards)

---

balanceOf() tests

- Check that the right amount of curve LPTs are being accounted for (during phases where cellar has deposit and stake positions, and phases where it does not, and phases where it has a mix)

---

claimRewards() tests

- Check that we get all the CRV, CVX, 3CRV rewards we're supposed to get --> this will require testing a couple convex markets that are currently giving said rewards. **Will need to specify the block number we're starting at**

From looking over Cellar.sol, withdrawableFrom() can include staked cvxCurveLPTs. For now I am assuming that they are 1:1 w/ curveLPTs but the tests will show that or not. \* withdrawInOrder() goes through positions and ultimately calls `withdraw()` for the respective position. \_calculateTotalAssetsOrTotalAssetsWithdrawable() uses withdrawableFrom() to calculate the amount of assets there are available to withdraw from the cellar.

     */
}
