// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { ConvexAdaptor } from "src/modules/adaptors/Convex/ConvexAdaptor.sol";

/**
 * @title ConvexAdaptorTest
 * @author crispymangoes, 0xEinCodes
 * @notice Cellar Adaptor tests with Convex markets
 * @dev Mock datafeeds to be used for underlying LPTs. TODO: hash out which LPT pair to go with, and what mock datafeeds to use for constituent assets of the pair so we can warp forward to simulat reward accrual.
 */
contract ConvexAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

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
