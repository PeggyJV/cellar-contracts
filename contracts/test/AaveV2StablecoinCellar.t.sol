// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { IAaveIncentivesController } from "../interfaces/IAaveIncentivesController.sol";
import { IStakedTokenV2 } from "../interfaces/IStakedTokenV2.sol";
import { ICurveSwaps } from "../interfaces/ICurveSwaps.sol";
import { ISushiSwapRouter } from "../interfaces/ISushiSwapRouter.sol";
import { IGravity } from "../interfaces/IGravity.sol";
import { ILendingPool } from "../interfaces/ILendingPool.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockAToken } from "./mocks/MockAToken.sol";
import { MockCurveSwaps } from "./mocks/MockCurveSwaps.sol";
import { MockSwapRouter } from "./mocks/MockSwapRouter.sol";
import { MockLendingPool } from "./mocks/MockLendingPool.sol";
import { MockIncentivesController } from "./mocks/MockIncentivesController.sol";
import { MockGravity } from "./mocks/MockGravity.sol";
import { MockStkAAVE } from "./mocks/MockStkAAVE.sol";

import { MockAaveCellar } from "./mocks/MockAaveCellar.sol";
import { CellarUser } from "./users/CellarUser.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";
import { MathUtils } from "../utils/MathUtils.sol";

contract AaveV2StablecoinCellarTest is DSTestPlus {
    using MathUtils for uint256;

    // Initialization Variables:
    MockERC20 private USDC;
    MockERC20 private DAI;
    MockAToken private aUSDC;
    MockAToken private aDAI;
    MockLendingPool private lendingPool;

    MockAaveCellar private cellar;

    // `lastTimeEnteredPosition` must be greater than `timeDeposited` to active shares, however in
    // a testing environment `block.timestamp` is always 0. This ensures `enterPosition` actives a
    // users shares as expected.
    function enterPosition() private {
        hevm.warp(block.timestamp + 1);
        cellar.enterPosition();
    }

    function setUp() public {
        USDC = new MockERC20("USDC", 6);
        DAI = new MockERC20("DAI", 6);

        lendingPool = new MockLendingPool();

        aUSDC = new MockAToken(address(lendingPool), address(USDC), "aUSDC");
        aDAI = new MockAToken(address(lendingPool), address(DAI), "aDAI");

        lendingPool.initReserve(address(USDC), address(aUSDC));
        lendingPool.initReserve(address(DAI), address(aDAI));

        address[] memory approvedPositions = new address[](1);
        approvedPositions[0] = address(DAI);

        // Declare unnecessary variables with address 0.
        cellar = new MockAaveCellar(
            ERC20(address(USDC)),
            approvedPositions,
            ICurveSwaps(address(0)),
            ISushiSwapRouter(address(0)),
            ILendingPool(address(lendingPool)),
            IAaveIncentivesController(address(0)),
            IGravity(address(this)), // Set to this address to give contract admin privileges.
            IStakedTokenV2(address(0)),
            ERC20(address(0)),
            ERC20(address(0))
        );

        assertEq(cellar.liquidityLimit(), 5_000_000e6);
        assertEq(cellar.depositLimit(), 50_000e6);

        // Ensure restrictions aren't a factor.
        cellar.setLiquidityLimit(type(uint256).max);
        cellar.setDepositLimit(type(uint256).max);

        // Mint enough liquidity to the Aave lending pool.
        USDC.mint(address(aUSDC), type(uint112).max);

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
    }

    function testInitialization() external {
        assertEq(address(cellar.asset()), address(USDC));
        assertEq(address(cellar.assetAToken()), address(aUSDC));
        assertEq(cellar.decimals(), 18);
        assertEq(cellar.assetDecimals(), USDC.decimals());

        assertEq(cellar.liquidityLimit(), type(uint256).max);
        assertEq(cellar.depositLimit(), type(uint256).max);

        assertTrue(cellar.isTrusted(address(USDC)));
        assertTrue(cellar.isTrusted(address(DAI)));

        assertEq(cellar.owner(), address(this));
    }

    function testDepositAndWithdraw(uint256 assets) public {
        assets = bound(assets, 1, cellar.maxDeposit(address(this)));

        USDC.mint(address(this), assets);

        // Test single deposit.
        uint256 shares = cellar.deposit(assets, address(this));

        assertEq(shares, assets.changeDecimals(6, 18)); // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(cellar.previewWithdraw(assets), shares);
        assertEq(cellar.previewDeposit(assets), shares);
        assertEq(cellar.totalSupply(), shares);
        assertEq(cellar.totalAssets(), assets);
        assertEq(cellar.balanceOf(address(this)), shares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets);
        assertEq(USDC.balanceOf(address(this)), 0);

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

        assertEq(cellar.totalAssets(), 0);
        assertEq(cellar.balanceOf(address(this)), 0);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0);
        assertEq(USDC.balanceOf(address(this)), assets);
    }

    // Test using with 18 decimals instead of 6.
    function testDepositAndWithdrawWithDifferentDecimals(uint256 assets) public {
        cellar.updatePosition(address(DAI));

        assets = bound(assets, 1, cellar.maxDeposit(address(this)));

        DAI.mint(address(this), assets);
        DAI.approve(address(cellar), assets);

        // Test single deposit.
        uint256 shares = cellar.deposit(assets, address(this));

        assertEq(shares, assets.changeDecimals(6, 18)); // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(cellar.previewWithdraw(assets), shares);
        assertEq(cellar.previewDeposit(assets), shares);
        assertEq(cellar.totalSupply(), shares);
        assertEq(cellar.totalAssets(), assets);
        assertEq(cellar.balanceOf(address(this)), shares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets);
        assertEq(DAI.balanceOf(address(this)), 0);

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

        assertEq(cellar.totalAssets(), 0);
        assertEq(cellar.balanceOf(address(this)), 0);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0);
        assertEq(DAI.balanceOf(address(this)), assets);
    }

    function testMintAndRedeem(uint256 shares) public {
        shares = bound(shares, 1, cellar.maxMint(address(this)));

        USDC.mint(address(this), shares.changeDecimals(18, 6));

        // Test single mint.
        uint256 assets = cellar.mint(shares, address(this));

        assertEq(shares.changeDecimals(18, 6), assets); // Expect exchange rate to be 1:1 on initial mint.
        assertEq(cellar.previewRedeem(shares), assets);
        assertEq(cellar.previewMint(shares), assets);
        assertEq(cellar.totalSupply(), shares);
        assertEq(cellar.totalAssets(), assets);
        assertEq(cellar.balanceOf(address(this)), shares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets);
        assertEq(USDC.balanceOf(address(this)), 0);

        // Test single redeem.
        cellar.redeem(shares, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0);
        assertEq(USDC.balanceOf(address(this)), assets);
    }

    // Test using with 18 decimals instead of 6.
    function testMintAndRedeemWithDifferentDecimals(uint256 shares) public {
        cellar.updatePosition(address(DAI));

        shares = bound(shares, 1, cellar.maxMint(address(this)));

        DAI.mint(address(this), shares.changeDecimals(18, 6));
        DAI.approve(address(cellar), shares);

        // Test single mint.
        uint256 assets = cellar.mint(shares, address(this));

        assertEq(shares.changeDecimals(18, 6), assets); // Expect exchange rate to be 1:1 on initial mint.
        assertEq(cellar.previewRedeem(shares), assets);
        assertEq(cellar.previewMint(shares), assets);
        assertEq(cellar.totalSupply(), shares);
        assertEq(cellar.totalAssets(), assets);
        assertEq(cellar.balanceOf(address(this)), shares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets);
        assertEq(DAI.balanceOf(address(this)), 0);

        // Test single redeem.
        cellar.redeem(shares, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0);
        assertEq(DAI.balanceOf(address(this)), assets);
    }

    function testMultipleMintDepositRedeemWithdraw() public {
        // Scenario:
        // A = Alice, B = Bob
        //  ________________________________________________________
        // | Cellar shares | A share | A assets | B share | B assets|
        // |========================================================|
        // | 1. Alice mints 2000 shares (costs $2000).              |
        // |--------------|---------|----------|---------|----------|
        // |         2000 |    2000 |    $2000 |       0 |       $0 |
        // |--------------|---------|----------|---------|----------|
        // | 2. Bob deposits $4000 (mints 4000 shares).             |
        // |--------------|---------|----------|---------|----------|
        // |         6000 |    2000 |    $2000 |    4000 |    $4000 |
        // |--------------|---------|----------|---------|----------|
        // | 3. Cellar mutates by +$3000 simulated yield            |
        // |    returned from position.                             |
        // |--------------|---------|----------|---------|----------|
        // |         6000 |    2000 |    $3000 |    4000 |    $6000 |
        // |--------------|---------|----------|---------|----------|
        // | 4. Alice deposits $2000 (mints 1333 shares).           |
        // |--------------|---------|----------|---------|----------|
        // |         7333 |    3333 |    $5000 |    4000 |    $6000 |
        // |--------------|---------|----------|---------|----------|
        // | 5. Bob mints 2000 shares (costs $3000).                |
        // |--------------|---------|----------|---------|----------|
        // |         9333 |    3333 |    $5000 |    6000 |    $9000 |
        // |--------------|---------|----------|---------|----------|
        // | 6. Cellar mutates by +$3000 simulated yield            |
        // |    returned from position.                             |
        // |--------------|---------|----------|---------|----------|
        // |         9333 |    3333 |    $6071 |    6000 |   $10929 |
        // |--------------|---------|----------|---------|----------|
        // | 7. Alice redeem 1333 shares ($2428).                   |
        // |--------------|---------|----------|---------|----------|
        // |         8000 |    2000 |    $3643 |    6000 |   $10929 |
        // |--------------|---------|----------|---------|----------|
        // | 8. Bob withdraws $2929 (1608 shares).                  |
        // |--------------|---------|----------|---------|----------|
        // |         6392 |    2000 |    $3643 |    4392 |    $8000 |
        // |--------------|---------|----------|---------|----------|
        // | 9. Alice withdraws $3643 (2000 shares).                |
        // |--------------|---------|----------|---------|----------|
        // |         4392 |       0 |       $0 |    4392 |    $8000 |
        // |--------------|---------|----------|---------|----------|
        // | 10. Bob redeem 4392 shares ($8000).                    |
        // |--------------|---------|----------|---------|----------|
        // |            0 |       0 |       $0 |       0 |       $0 |
        // |______________|_________|__________|_________|__________|

        CellarUser alice = new CellarUser(cellar, USDC);
        CellarUser bob = new CellarUser(cellar, USDC);

        uint256 mutationAssets = 3000e6;

        USDC.mint(address(alice), 4000e6);
        alice.approve(address(cellar), 4000e6);

        USDC.mint(address(bob), 7000e6);
        bob.approve(address(cellar), 7000e6);

        // 1. Alice mints 2000 shares (costs $2000).
        uint256 aliceAssets = alice.mint(2000e18, address(alice));
        uint256 aliceShares = cellar.previewDeposit(aliceAssets);

        // Expect to have received the requested mint amount.
        assertEq(aliceShares, 2000e18);
        assertEq(cellar.balanceOf(address(alice)), aliceShares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(alice))), aliceAssets);
        assertEq(cellar.convertToShares(aliceAssets), cellar.balanceOf(address(alice)));

        // Expect a 1:1 ratio before mutation.
        assertEq(aliceAssets, 2000e6);

        // Sanity check.
        assertEq(cellar.totalSupply(), aliceShares);
        assertEq(cellar.totalAssets(), aliceAssets);

        // 2. Bob deposits $4000 (mints 4000 shares).
        uint256 bobShares = bob.deposit(4000e6, address(bob));
        uint256 bobAssets = cellar.previewRedeem(bobShares);

        // Expect to have received the requested asset amount.
        assertEq(bobAssets, 4000e6);
        assertEq(cellar.balanceOf(address(bob)), bobShares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(bob))), bobAssets);
        assertEq(cellar.convertToShares(bobAssets), cellar.balanceOf(address(bob)));

        // Expect a 1:1 ratio before mutation.
        assertEq(bobShares.changeDecimals(18, 6), bobAssets);

        // Sanity check.
        uint256 preMutationShares = aliceShares + bobShares;
        uint256 preMutationAssets = aliceAssets + bobAssets;
        assertEq(cellar.totalSupply(), preMutationShares);
        assertEq(cellar.totalAssets(), preMutationAssets);
        assertEq(cellar.totalSupply(), 6000e18);
        assertEq(cellar.totalAssets(), 6000e6);

        // 3. Cellar mutates by +$3000 to simulate yield returned from position.
        // The cellar now contains more assets than deposited which causes the exchange rate to change.
        // Alice share is 33.33% of the cellar, Bob 66.66% of the cellar.
        // Alice's share count stays the same but the asset amount changes from $2000 to $3000.
        // Bob's share count stays the same but the asset amount changes from $4000 to $6000.
        USDC.mint(address(cellar), mutationAssets);
        enterPosition();
        assertEq(cellar.activeAssets(), preMutationAssets + mutationAssets);
        assertEq(cellar.totalSupply(), preMutationShares);
        assertEq(cellar.balanceOf(address(alice)), aliceShares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(alice))), aliceAssets + (mutationAssets / 3) * 1);
        assertEq(cellar.balanceOf(address(bob)), bobShares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(bob))), bobAssets + (mutationAssets / 3) * 2);

        // 4. Alice deposits $2000 (mints 1333 shares).
        assertApproxEq(alice.deposit(2000e6, address(alice)), 1333e18, 1e18); // 1333.333...
        assertApproxEq(cellar.totalSupply(), 7333e18, 1e18); // 7333.333...
        assertApproxEq(cellar.balanceOf(address(alice)), 3333e18, 1e18); // 3333.333...
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(alice))), 5000e6);
        assertEq(cellar.balanceOf(address(bob)), 4000e18);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(bob))), 6000e6);

        // 5. Bob mints 2000 shares (costs $3000).
        assertEq(bob.mint(2000e18, address(bob)), 3000e6);
        assertApproxEq(cellar.balanceOf(address(bob)), 6000e18, 1e18); // 5999.999...
        assertApproxEq(cellar.totalSupply(), 9333e18, 1e18); // 9333.333...
        assertApproxEq(cellar.balanceOf(address(alice)), 3333e18, 1e18); // 3333.333...
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(alice))), 5000e6);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(bob))), 9000e6);

        // Sanity checks:
        // Alice should have spent all her assets now.
        assertEq(USDC.balanceOf(address(alice)), 0);
        // Bob should have spent all his assets now.
        assertEq(USDC.balanceOf(address(bob)), 0);
        // Assets in cellar: 4k (alice) + 7k (bob) + 3k (yield).
        assertEq(cellar.totalAssets(), 14000e6);

        // 6. Cellar mutates by +$3000.
        USDC.mint(address(cellar), mutationAssets);
        enterPosition();
        assertEq(cellar.activeAssets(), 17000e6);
        assertApproxEq(cellar.convertToAssets(cellar.balanceOf(address(alice))), 6071e6, 1e6); // 6071.429
        assertApproxEq(cellar.convertToAssets(cellar.balanceOf(address(bob))), 10929e6, 1e6); // 10928.571

        // 7. Alice redeem 1333 shares ($2428).
        assertApproxEq(alice.redeem(1333e18, address(alice), address(alice)), 2428e6, 1e6); // 2427.964
        assertApproxEq(USDC.balanceOf(address(alice)), 2428e6, 1e6); // 2427.964
        assertApproxEq(cellar.totalSupply(), 8000e18, 1e18); // 8000.333
        assertApproxEq(cellar.totalAssets(), 14572e6, 1e6); // 14572.0357
        assertApproxEq(cellar.balanceOf(address(alice)), 2000e18, 1e18); // 2000.333
        assertApproxEq(cellar.convertToAssets(cellar.balanceOf(address(alice))), 3643e6, 1e6); // 3643.464
        assertApproxEq(cellar.balanceOf(address(bob)), 6000e18, 1e18); // 5999.999
        assertApproxEq(cellar.convertToAssets(cellar.balanceOf(address(bob))), 10929e6, 1e6); // 10928.571

        // 8. Bob withdraws $2929 (1608 shares)
        assertApproxEq(bob.withdraw(2929e6, address(bob), address(bob)), 1608e18, 1e18); // 1608.078
        assertEq(USDC.balanceOf(address(bob)), 2929e6);
        assertApproxEq(cellar.totalSupply(), 6392e18, 1e18); // 6392.255
        assertApproxEq(cellar.totalAssets(), 11643e6, 1e6); // 1164.304
        assertApproxEq(cellar.balanceOf(address(alice)), 2000e18, 1e18); // 2000.333
        assertApproxEq(cellar.convertToAssets(cellar.balanceOf(address(alice))), 3643e6, 1e6); // 3643.464
        assertApproxEq(cellar.balanceOf(address(bob)), 4392e18, 1e18); // 4391.922
        assertApproxEq(cellar.convertToAssets(cellar.balanceOf(address(bob))), 8000e6, 1e6); // 7999.571

        // 9. Alice withdraws $3643 (2000 shares)
        assertApproxEq(alice.withdraw(3643e6, address(alice), address(alice)), 2000e18, 1e18); // 2000.078
        assertApproxEq(USDC.balanceOf(address(alice)), 6071e6, 1e6); // 6070.964
        assertApproxEq(cellar.totalSupply(), 4392e18, 1e18); // 4392.176
        assertApproxEq(cellar.totalAssets(), 8000e6, 1e6); // 8000.036
        assertApproxEq(cellar.balanceOf(address(alice)), 0, 1e18); // 0.255
        assertApproxEq(cellar.convertToAssets(cellar.balanceOf(address(alice))), 0, 1e6); // 0.464
        assertApproxEq(cellar.balanceOf(address(bob)), 4392e18, 1e18); // 4391.922
        assertApproxEq(cellar.convertToAssets(cellar.balanceOf(address(bob))), 8000e6, 1e6); // 7999.571

        // 10. Bob redeem 4392 shares ($8000)
        assertApproxEq(bob.redeem(4392e18, address(bob), address(bob)), 8000e6, 1e6); // 7999.571
        assertApproxEq(USDC.balanceOf(address(bob)), 10928e6, 1e6); // 10928.571
        assertApproxEq(cellar.totalSupply(), 0, 1e18); // 0.255
        assertApproxEq(cellar.totalAssets(), 0, 1e6); // 0.464
        assertApproxEq(cellar.balanceOf(address(alice)), 0, 1e18); // 0.255
        assertApproxEq(cellar.convertToAssets(cellar.balanceOf(address(alice))), 0, 1e6); // 0.464
        assertEq(cellar.balanceOf(address(bob)), 0);
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(bob))), 0);
    }

    function testCellarInteractionsFromThirdParties() public {
        CellarUser alice = new CellarUser(cellar, USDC);
        CellarUser bob = new CellarUser(cellar, USDC);

        USDC.mint(address(alice), 1e6);
        USDC.mint(address(bob), 1e6);
        alice.approve(address(cellar), 1e6);
        bob.approve(address(cellar), 1e6);

        // Alice deposits $1 for Bob.
        alice.deposit(1e6, address(bob));
        assertEq(cellar.balanceOf(address(alice)), 0);
        assertEq(cellar.balanceOf(address(bob)), 1e18);
        assertEq(USDC.balanceOf(address(alice)), 0);

        // Bob mint 1 share for Alice.
        bob.mint(1e18, address(alice));
        assertEq(cellar.balanceOf(address(alice)), 1e18);
        assertEq(cellar.balanceOf(address(bob)), 1e18);
        assertEq(USDC.balanceOf(address(bob)), 0);

        // Alice redeem 1 share for Bob.
        alice.redeem(1e18, address(bob), address(alice));
        assertEq(cellar.balanceOf(address(alice)), 0);
        assertEq(cellar.balanceOf(address(bob)), 1e18);
        assertEq(USDC.balanceOf(address(bob)), 1e6);

        // Bob withdraw 1e18 for Alice.
        bob.withdraw(1e6, address(alice), address(bob));
        assertEq(cellar.balanceOf(address(alice)), 0);
        assertEq(cellar.balanceOf(address(bob)), 0);
        assertEq(USDC.balanceOf(address(alice)), 1e6);
    }

    function testDepositWithdrawWithNotEnoughAssets() public {
        USDC.mint(address(this), 1e6);

        // Should deposit as much as possible without reverting.
        cellar.deposit(2e6, address(this));
        assertEq(USDC.balanceOf(address(this)), 0);

        // Should withdraw as much as possible without reverting.
        cellar.withdraw(2e6, address(this), address(this));
        assertEq(USDC.balanceOf(address(this)), 1e6);
    }

    function testRedeemWithNotEnoughShares() public {
        USDC.mint(address(this), 1e6);

        // Should mint as much as possible without reverting.
        cellar.mint(2e18, address(this));
        assertEq(cellar.balanceOf(address(this)), 1e18);

        // Should redeem as much as possible without reverting.
        cellar.redeem(2e18, address(this), address(this));
        assertEq(cellar.balanceOf(address(this)), 0);
    }

    function testFailTransferSharesWithNotEnoughShares() external {
        cellar.transfer(hevm.addr(1), 1e18);
    }

    function testFailOnlyTransferActiveSharesWithNotEnoughActiveShares() external {
        USDC.mint(address(this), 1e6);
        cellar.mint(1e18, address(this));

        (uint256 activeShares, uint256 inactiveShares, , ) = cellar.getUserBalances(address(this));
        assertEq(activeShares, 0);
        assertEq(inactiveShares, 1e18);

        cellar.transferFrom(address(this), hevm.addr(1), 1e18, true);
    }

    function testFailDepositZero() public {
        USDC.mint(address(this), 1);

        cellar.deposit(0, address(this));
    }

    function testFailMintZero() public {
        USDC.mint(address(this), 1);

        cellar.mint(0, address(this));
    }

    function testFailWithdrawZero() public {
        USDC.mint(address(this), 1);

        cellar.deposit(1, address(this));

        cellar.withdraw(0, address(this), address(this));
    }

    function testFailRedeemZero() public {
        USDC.mint(address(this), 1);

        cellar.deposit(1, address(this));

        cellar.redeem(0, address(this), address(this));
    }

    function testTransferSharesZero() external {
        cellar.transfer(hevm.addr(1), 0);

        assertEq(cellar.balanceOf(hevm.addr(1)), 0);
    }

    // Test an edgecase where `totalSupply` can be non-zero when `totalAssets` is zero.
    function testEdgecaseDepositWithNonZeroTotalSupply() public {
        USDC.mint(address(this), 1000e6);

        // Deposit all assets.
        cellar.deposit(USDC.balanceOf(address(this)), address(this));

        assertEq(cellar.balanceOf(address(this)), 1000e18);

        // Simulate gaining $100 yield.
        enterPosition();
        aUSDC.mint(address(cellar), 100e6, lendingPool.index());

        assertEq(cellar.activeAssets(), 1100e6);
        assertEq(cellar.totalAssets(), 1100e6);

        // Redeem all shares.
        cellar.redeem(cellar.balanceOf(address(this)), address(this), address(this));

        assertEq(USDC.balanceOf(address(this)), 1100e6);
        assertEq(cellar.totalSupply(), 0);

        // Accrue $10 of fees as shares (will be redeemable for $0, however, since there are no
        // assets left in cellar).
        cellar.accrueFees();

        (, , , , uint256 accruedPerformanceFees) = cellar.fees();

        assertEq(accruedPerformanceFees, 10e18);
        assertEq(cellar.totalSupply(), 10e18);
        assertEq(cellar.previewRedeem(accruedPerformanceFees), 0);

        // Test depositing when `totalSupply` is non-zero but `totalAssets` is zero.
        cellar.deposit(1e6, address(this));
        cellar.mint(1e18, address(this));
    }
}
