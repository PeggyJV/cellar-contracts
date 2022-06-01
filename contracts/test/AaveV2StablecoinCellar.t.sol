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
import { MockSwapRouter } from "./mocks/MockSwapRouter.sol";
import { MockLendingPool } from "./mocks/MockLendingPool.sol";
import { MockIncentivesController } from "./mocks/MockIncentivesController.sol";
import { MockGravity } from "./mocks/MockGravity.sol";
import { MockStkAAVE } from "./mocks/MockStkAAVE.sol";

import { AaveV2StablecoinCellar } from "../AaveV2StablecoinCellar.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";
import { Math } from "../utils/Math.sol";

contract AaveV2StablecoinCellarTest is DSTestPlus {
    using Math for uint256;

    // Initialization Variables:
    MockERC20 private USDC;
    MockERC20 private DAI;
    MockERC20 private AAVE;
    MockERC20 private WETH;
    MockStkAAVE private stkAAVE;
    MockAToken private aUSDC;
    MockAToken private aDAI;
    MockLendingPool private lendingPool;
    MockSwapRouter private swapRouter;
    MockIncentivesController private incentivesController;
    MockGravity private gravity;

    AaveV2StablecoinCellar private cellar;

    function setUp() external {
        USDC = new MockERC20("USDC", 6);
        hevm.label(address(USDC), "USDC");
        DAI = new MockERC20("DAI", 18);
        hevm.label(address(DAI), "DAI");
        WETH = new MockERC20("WETH", 18);
        hevm.label(address(WETH), "WETH");

        lendingPool = new MockLendingPool();
        hevm.label(address(lendingPool), "lendingPool");

        aUSDC = new MockAToken(address(lendingPool), address(USDC), "aUSDC");
        hevm.label(address(aUSDC), "aUSDC");
        aDAI = new MockAToken(address(lendingPool), address(DAI), "aDAI");
        hevm.label(address(aDAI), "aDAI");

        lendingPool.initReserve(address(USDC), address(aUSDC));
        lendingPool.initReserve(address(DAI), address(aDAI));

        ERC20[] memory approvedPositions = new ERC20[](1);
        approvedPositions[0] = ERC20(DAI);

        swapRouter = new MockSwapRouter();
        hevm.label(address(swapRouter), "swapRouter");

        AAVE = new MockERC20("AAVE", 18);
        hevm.label(address(AAVE), "AAVE");
        stkAAVE = new MockStkAAVE(AAVE);
        hevm.label(address(stkAAVE), "stkAAVE");
        incentivesController = new MockIncentivesController(stkAAVE);
        hevm.label(address(incentivesController), "incentivesController");

        gravity = new MockGravity();
        hevm.label(address(gravity), "gravity");

        // Setup exchange rates:
        swapRouter.setExchangeRate(address(USDC), address(DAI), 1e18);
        swapRouter.setExchangeRate(address(DAI), address(USDC), 1e6);
        swapRouter.setExchangeRate(address(AAVE), address(USDC), 100e6);
        swapRouter.setExchangeRate(address(AAVE), address(DAI), 100e18);

        // Declare unnecessary variables with address 0.
        cellar = new AaveV2StablecoinCellar(
            ERC20(address(USDC)),
            approvedPositions,
            ICurveSwaps(address(swapRouter)),
            ISushiSwapRouter(address(swapRouter)),
            ILendingPool(address(lendingPool)),
            IAaveIncentivesController(address(incentivesController)),
            IGravity(address(gravity)), // Set to this address to give contract admin privileges.
            IStakedTokenV2(address(stkAAVE)),
            ERC20(address(AAVE)),
            ERC20(address(WETH))
        );

        assertEq(cellar.liquidityLimit(), 5_000_000e6);
        assertEq(cellar.depositLimit(), 50_000e6);

        // Transfer ownership to this contract for testing.
        hevm.prank(address(cellar.gravityBridge()));
        cellar.transferOwnership(address(this));

        // Ensure restrictions aren't a factor.
        cellar.setLiquidityLimit(type(uint128).max);
        cellar.setDepositLimit(type(uint128).max);

        // Mint enough liquidity to the Aave lending pool.
        USDC.mint(address(aUSDC), type(uint224).max);
        DAI.mint(address(aDAI), type(uint224).max);

        // Mint enough liquidity to swap router for swaps.
        USDC.mint(address(swapRouter), type(uint224).max);
        DAI.mint(address(swapRouter), type(uint224).max);

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
    }

    function testInitialization() external {
        assertEq(address(cellar.asset()), address(USDC), "Should initialize asset to be USDC.");
        assertEq(address(cellar.assetAToken()), address(aUSDC), "Should initialize asset's aToken to be aUSDC.");
        assertEq(cellar.decimals(), 18, "Should initialize decimals to be 18.");
        assertEq(cellar.assetDecimals(), 6, "Should initialize asset decimals to be 6.");

        assertEq(cellar.liquidityLimit(), type(uint128).max, "Should initialize liquidity limit to be max.");
        assertEq(cellar.depositLimit(), type(uint128).max, "Should initialize deposit limit to be max.");

        assertTrue(cellar.isTrusted(ERC20(USDC)), "Should initialize USDC to be trusted.");
        assertTrue(cellar.isTrusted(ERC20(DAI)), "Should initialize DAI to be trusted.");
    }

    // ======================================= DEPOSIT/WITHDRAW TESTS =======================================

    function testDepositAndWithdraw(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        USDC.mint(address(this), assets);

        // Test single deposit.
        uint256 shares = cellar.deposit(assets, address(this));

        assertEq(shares, assets.changeDecimals(6, 18), "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assets), shares, "Withdrawing assets should burn shares given.");
        assertEq(cellar.previewDeposit(assets), shares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

        assertEq(cellar.totalAssets(), 0, "Should have updated total assets with assets withdrawn.");
        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(USDC.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    function testMintAndRedeem(uint256 shares) external {
        shares = bound(shares, 1e18, type(uint112).max);

        USDC.mint(address(this), shares.changeDecimals(18, 6));

        // Test single mint.
        uint256 assets = cellar.mint(shares, address(this));

        assertEq(shares.changeDecimals(18, 6), assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewRedeem(shares), assets, "Redeeming shares should withdraw assets owed.");
        assertEq(cellar.previewMint(shares), assets, "Minting shares should deposit assets owed.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // Test single redeem.
        cellar.redeem(shares, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(USDC.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    function testMultipleMintDepositRedeemWithdraw() external {
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

        address alice = hevm.addr(1);
        address bob = hevm.addr(2);

        uint256 mutationAssets = 3000e6;

        // Mint each user an extra asset to account for rounding up of assets deposited when minting shares.
        USDC.mint(alice, 4000e6 + 1);
        hevm.prank(alice);
        USDC.approve(address(cellar), type(uint256).max);

        USDC.mint(bob, 7000e6 + 1);
        hevm.prank(bob);
        USDC.approve(address(cellar), type(uint256).max);

        // 1. Alice mints 2000 shares (costs $2000).
        hevm.prank(alice);
        uint256 aliceAssets = cellar.mint(2000e18, alice);
        uint256 aliceShares = cellar.previewDeposit(aliceAssets);

        // Expect to have received the requested mint amount.
        assertEq(aliceShares, 2000e18, "1. Alice should have been minted 2000 shares.");
        assertEq(cellar.balanceOf(alice), aliceShares, "1. Alice's share balance be 2000 shares.");
        assertEq(
            cellar.convertToAssets(cellar.balanceOf(alice)),
            aliceAssets,
            "1. Alice shares should be worth the assets deposited."
        );
        assertEq(
            cellar.convertToShares(aliceAssets),
            cellar.balanceOf(alice),
            "1. Alice's assets should be worth the shares minted."
        );

        // Sanity check.
        assertEq(cellar.totalSupply(), aliceShares, "1. Total supply should be 2000 shares.");
        assertEq(cellar.totalAssets(), aliceAssets, "1. Total assets should be $2000.");

        // 2. Bob deposits $4000 (mints 4000 shares).
        hevm.prank(bob);
        uint256 bobShares = cellar.deposit(4000e6, bob);
        uint256 bobAssets = cellar.previewRedeem(bobShares);

        // Expect to have received the requested asset amount.
        assertEq(bobAssets, 4000e6, "2. Bob should have deposited $4000.");
        assertEq(cellar.balanceOf(bob), bobShares, "2. Bob's share balance be 4000 shares.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(bob)), bobAssets, "2. Bob's shares should be worth $4000.");
        assertEq(
            cellar.convertToShares(bobAssets),
            cellar.balanceOf(bob),
            "2. Bob's assets should be worth the shares deposited."
        );

        // Sanity check.
        uint256 preMutationShares = aliceShares + bobShares;
        uint256 preMutationAssets = aliceAssets + bobAssets;
        assertEq(cellar.totalSupply(), preMutationShares, "2. Total supply should be total of Alice and Bob's shares.");
        assertEq(cellar.totalAssets(), preMutationAssets, "2. Total assets should be total of Alice and Bob's assets.");
        assertEq(cellar.totalSupply(), 6000e18, "2. Total supply should be 6000 shares.");
        assertEq(cellar.totalAssets(), 6000e6, "2. Total assets should be $6000.");

        // 3. Cellar mutates by +$3000.
        // The cellar now contains more assets than deposited which causes the exchange rate to change.
        // Alice share is 33.33% of the cellar, Bob 66.66% of the cellar.
        // Alice's share count stays the same but the asset amount changes from $2000 to $3000.
        // Bob's share count stays the same but the asset amount changes from $4000 to $6000.
        USDC.mint(address(cellar), mutationAssets);

        assertEq(cellar.totalAssets(), preMutationAssets + mutationAssets, "3. Total assets should have mutated.");
        assertEq(cellar.totalSupply(), preMutationShares, "3. Total supply should not have mutated.");
        assertEq(cellar.balanceOf(alice), aliceShares, "3. Alice's share balance should not have mutated.");
        assertEq(
            cellar.convertToAssets(cellar.balanceOf(alice)),
            aliceAssets + (mutationAssets / 3) * 1,
            "3. Alice's asset balance should have mutated."
        );
        assertEq(cellar.balanceOf(bob), bobShares, "3. Bob's share balance should not have mutated.");
        assertEq(
            cellar.convertToAssets(cellar.balanceOf(bob)),
            bobAssets + (mutationAssets / 3) * 2,
            "3. Bob's asset balance should have mutated."
        );

        // 4. Alice deposits $2000 (mints 1333 shares).
        hevm.prank(alice);
        assertApproxEq(
            cellar.deposit(2000e6, alice),
            1333e18,
            1e18,
            "4. Alice should have been minted approximately 1333 shares."
        );
        assertApproxEq(cellar.totalSupply(), 7333e18, 1e18, "4. Total supply should be approximately 7333 shares.");
        assertApproxEq(
            cellar.balanceOf(alice),
            3333e18,
            1e18,
            "4. Alice's share balance should be approximately 3333 shares."
        );
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(alice)),
            5000e6,
            1e6,
            "4. Alice's shares should be worth approximately $5000."
        );
        assertEq(cellar.balanceOf(bob), 4000e18, "4. Bob's share balance should be worth $4000.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(bob)), 6000e6, "4. Bob's shares should be worth $6000.");

        // 5. Bob mints 2000 shares (costs $3000).
        hevm.prank(bob);
        assertApproxEq(cellar.mint(2000e18, bob), 3000e6, 1e6, "5. Bob should have deposited approximately $3000.");
        assertApproxEq(cellar.balanceOf(bob), 6000e18, 1e18, "5. Bob's share balance should be approximately 6000.");
        assertApproxEq(cellar.totalSupply(), 9333e18, 1e18, "5. Total supply should be approximately 9333 shares.");
        assertApproxEq(
            cellar.balanceOf(alice),
            3333e18,
            1e18,
            "5. Alice's share balance should be approximately 3333 shares."
        );
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(alice)),
            5000e6,
            1e6,
            "5. Alice's shares should be worth approximately $5000"
        );
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(bob)),
            9000e6,
            1e6,
            "5. Bob's shares should be worth approximately $9000."
        );

        // Sanity checks:

        assertApproxEq(USDC.balanceOf(alice), 0, 1e6, "5. Alice should have spent practically all her assets now.");
        assertApproxEq(USDC.balanceOf(bob), 0, 1e6, "5. Bob should have spent practically all his assets now.");
        assertApproxEq(cellar.totalAssets(), 14000e6, 1e6, "5. Total asset should be approximately $14000.");

        // 6. Cellar mutates by +$3000.
        USDC.mint(address(cellar), mutationAssets);

        assertApproxEq(cellar.totalAssets(), 17000e6, 1e6, "6. Total assets should have updated.");
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(alice)),
            6071e6,
            1e6,
            "6. Alice's asset balance should have mutated."
        );
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(bob)),
            10929e6,
            1e6,
            "6. Bob's asset balance should have mutated."
        );

        // 7. Alice redeem 1333 shares ($2428).
        hevm.prank(alice);
        assertApproxEq(
            cellar.redeem(1333e18, alice, alice),
            2428e6,
            1e6,
            "7. Alice should have withdrawn approximately $2428 assets."
        );
        assertApproxEq(USDC.balanceOf(alice), 2428e6, 1e6, "7. Alice's balance should be $2428.");
        assertApproxEq(cellar.totalSupply(), 8000e18, 1e18, "7. Total supply should be approximately 8000 shares.");
        assertApproxEq(cellar.totalAssets(), 14572e6, 1e6, "7. Total assets should be approximately $14572.");
        assertApproxEq(
            cellar.balanceOf(alice),
            2000e18,
            1e18,
            "7. Alice's share balance should be approximately 2000."
        );
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(alice)),
            3643e6,
            1e6,
            "7. Alice's shares should be worth approximately $3643."
        );
        assertApproxEq(cellar.balanceOf(bob), 6000e18, 1e18, "7. Bob's share balance should be approximately 6000.");
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(bob)),
            10929e6,
            1e6,
            "7. Bob's shares should be worth approximately $10929."
        );

        // 8. Bob withdraws $2929 (1608 shares)
        hevm.prank(bob);
        assertApproxEq(cellar.withdraw(2929e6, bob, bob), 1608e18, 1e18, "8. Bob should have redeemed 1608.");
        assertApproxEq(USDC.balanceOf(bob), 2929e6, 1e6, "8. Bob's balance should be approximately $2929.");
        assertApproxEq(cellar.totalSupply(), 6392e18, 1e18, "8. Total supply should be approximately 6392 shares.");
        assertApproxEq(cellar.totalAssets(), 11643e6, 1e6, "8. Total assets should be approximately $11643.");
        assertApproxEq(cellar.balanceOf(alice), 2000e18, 1e18, "8. Alice's share balance should be 2000.");
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(alice)),
            3643e6,
            1e6,
            "8. Alice's shares should be worth approximately $3643."
        );
        assertApproxEq(cellar.balanceOf(bob), 4392e18, 1e18, "8. Bob's share balance should be approximately 4392.");
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(bob)),
            8000e6,
            1e6,
            "8. Bob's shares should be worth approximately $8000."
        );

        // 9. Alice withdraws $3643 (2000 shares)
        hevm.prank(alice);
        assertApproxEq(
            cellar.withdraw(3643e6, alice, alice),
            2000e18,
            1e18,
            "9. Alice should have withdrawn approximately 2000."
        );
        assertApproxEq(USDC.balanceOf(alice), 6071e6, 1e6, "9. Alice's balance should be approximately $6071.");
        assertApproxEq(cellar.totalSupply(), 4392e18, 1e18, "9. Total supply should be approximately 4392.");
        assertApproxEq(cellar.totalAssets(), 8000e6, 1e6, "9. Total assets should be approximately $8000.");
        assertApproxEq(cellar.balanceOf(alice), 0, 1e18, "9. Alice's share balance should be approximately 0.");
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(alice)),
            0,
            1e6,
            "9. Alice's shares should be worth approximately 0."
        );
        assertApproxEq(cellar.balanceOf(bob), 4392e18, 1e18, "9. Bob's share balance should be 4392.");
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(bob)),
            8000e6,
            1e6,
            "9. Bob's shares should be worth approximately $8000."
        );

        // 10. Bob redeem 4392 shares ($8000)
        hevm.startPrank(bob);
        assertApproxEq(
            cellar.redeem(cellar.balanceOf(bob), bob, bob),
            8000e6,
            1e6,
            "10. Bob should have redeemed approximately $8000."
        );
        hevm.stopPrank();
        assertApproxEq(USDC.balanceOf(bob), 10928e6, 1e6, "10. Bob's balance should be $10928.");
        assertApproxEq(cellar.totalSupply(), 0, 1e18, "10. Total supply should be approximately 0.");
        assertApproxEq(cellar.totalAssets(), 0, 1e6, "10. Total assets should be approximately $0.");
        assertApproxEq(cellar.balanceOf(alice), 0, 1e18, "10. Alice's share balance should be approximately 0.");
        assertApproxEq(
            cellar.convertToAssets(cellar.balanceOf(alice)),
            0,
            1e6,
            "10. Alice's shares should be worth approximately 0."
        );
        assertEq(cellar.balanceOf(bob), 0, "10. Bob's share balance should be 0.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(bob)), 0, "10. Bob's shares should be worth 0.");
    }

    // ========================================= LIMITS TESTS =========================================

    function testLimits(uint256 amount) external {
        amount = bound(amount, 1, type(uint72).max);

        USDC.mint(address(this), amount);
        USDC.approve(address(cellar), amount);
        cellar.deposit(amount, address(this));

        assertEq(cellar.maxDeposit(address(this)), type(uint256).max, "Should have no max deposit.");
        assertEq(cellar.maxMint(address(this)), type(uint256).max, "Should have no max mint.");

        cellar.setDepositLimit(uint128(amount * 2));
        cellar.setLiquidityLimit(uint128(amount / 2));

        assertEq(cellar.depositLimit(), amount * 2, "Should have changed the deposit limit.");
        assertEq(cellar.liquidityLimit(), amount / 2, "Should have changed the liquidity limit.");
        assertEq(cellar.maxDeposit(address(this)), 0, "Should have reached new max deposit.");
        assertEq(cellar.maxMint(address(this)), 0, "Should have reached new max mint.");

        cellar.setLiquidityLimit(uint128(amount * 3));

        assertEq(cellar.maxDeposit(address(this)), amount, "Should not have reached new max deposit.");
        assertEq(cellar.maxMint(address(this)), amount.changeDecimals(6, 18), "Should not have reached new max mint.");

        address otherUser = hevm.addr(1);

        assertEq(cellar.maxDeposit(otherUser), amount * 2, "Should have different max deposits for other user.");
        assertEq(
            cellar.maxMint(otherUser),
            (amount * 2).changeDecimals(6, 18),
            "Should have different max mint for other user."
        );

        // Hit global liquidity limit and deposit limit for other user.
        hevm.startPrank(otherUser);
        USDC.mint(otherUser, amount * 2);
        USDC.approve(address(cellar), amount * 2);
        cellar.deposit(amount * 2, otherUser);
        hevm.stopPrank();

        assertEq(cellar.maxDeposit(address(this)), 0, "Should have hit liquidity limit for max deposit.");
        assertEq(cellar.maxMint(address(this)), 0, "Should have hit liquidity limit for max mint.");

        // Reduce liquidity limit by withdrawing.
        cellar.withdraw(amount, address(this), address(this));

        assertEq(cellar.maxDeposit(address(this)), amount, "Should have reduced liquidity limit for max deposit.");
        assertEq(
            cellar.maxMint(address(this)),
            amount.changeDecimals(6, 18),
            "Should have reduced liquidity limit for max mint."
        );
        assertEq(
            cellar.maxDeposit(otherUser),
            0,
            "Should have not changed max deposit for other user because they are still at the deposit limit."
        );
        assertEq(
            cellar.maxMint(otherUser),
            0,
            "Should have not changed max mint for other user because they are still at the deposit limit."
        );

        cellar.initiateShutdown(false);

        assertEq(cellar.maxDeposit(address(this)), 0, "Should show no assets can be deposited when shutdown.");
        assertEq(cellar.maxMint(address(this)), 0, "Should show no shares can be minted when shutdown.");
    }

    function testFailDepositAboveDepositLimit(uint256 amount) external {
        amount = bound(amount, 101e6, type(uint112).max);

        cellar.setDepositLimit(100e6);

        USDC.mint(address(this), amount);
        cellar.deposit(amount, address(this));
    }

    function testFailMintAboveDepositLimit(uint256 amount) external {
        amount = bound(amount, 101, type(uint112).max);

        cellar.setDepositLimit(100e6);

        USDC.mint(address(this), amount * 10**6);
        cellar.mint(amount * 10**18, address(this));
    }

    function testFailDepositAboveLiquidityLimit(uint256 amount) external {
        amount = bound(amount, 101e6, type(uint112).max);

        cellar.setLiquidityLimit(100e6);

        USDC.mint(address(this), amount);
        cellar.deposit(amount, address(this));
    }

    function testFailMintAboveLiquidityLimit(uint256 amount) external {
        amount = bound(amount, 101, type(uint112).max);

        cellar.setLiquidityLimit(100e6);

        USDC.mint(address(this), amount * 10**6);
        cellar.mint(amount * 10**18, address(this));
    }

    // ========================================= ACCRUAL TESTS =========================================

    function testAccrue() external {
        // Scenerio:
        // - Platform fee percentage is set to 0.25%
        // - Performance fee percentage is set to 10%
        //
        // Testcases Covered:
        // - Test accrual with positive performance.
        // - Test accrual with negative performance.
        // - Test accrual with no performance (nothing changes).
        // - Test accrual reverting previous accrual period is still ongoing.
        // - Test accrual not starting an accrual period if negative performance or no performance.
        // - Test accrual for single position.
        // - Test accrual for multiple positions.
        // - Test accrued yield is distributed linearly as expected.
        // - Test deposits / withdraws do not effect accrual and yield distribution.
        //
        // +==============+==============+==================+================+===================+==============+
        // | Total Assets | Total Locked | Performance Fees | Platform Fees  | Last Accrual Time | Current Time |
        // |   (in USD)   |   (in USD)   |    (in shares)   |  (in shares)   |   (in seconds)    | (in seconds) |
        // +==============+==============+==================+================+===================+==============+
        // | 1. Deposit $300 worth of assets.                                                                   |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $300 |           $0 |                0 |              0 |                 0 |            0 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 2. An entire year passes.                                                                          |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $300 |           $0 |                0 |              0 |                 0 |     31536000 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 3. Test accrual of platform fees.                                                                  |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $300 |           $0 |                0 |           0.75 |          31536000 |     31536000 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 4. Gains $150 worth of assets of yield.                                                            |
        // |    NOTE: Nothing should change because yield has not been accrued.                                 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $300 |           $0 |                0 |           0.75 |          31536000 |     31536000 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 5. Accrue with positive performance.                                                               |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $315 |         $135 |               15 |           0.75 |          31536000 |     31536000 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 6. Half of accrual period passes.                                                                  |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |       $382.5 |        $67.5 |               15 |           0.75 |          31536000 |     31838400 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 7. Deposit $200 worth of assets.                                                                   |
        // |    NOTE: For testing that deposit does not effect yield and is not factored in to later accrual.   |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |       $582.5 |        $67.5 |               15 |           0.75 |          31536000 |     31838400 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 8. Entire accrual period passes.                                                                   |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $650 |           $0 |               15 |           0.75 |          31536000 |     32140800 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 9. Withdraw $100 worth of assets.                                                                  |
        // |    NOTE: For testing that withdraw does not effect yield and is not factored in to later accrual.  |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $550 |           $0 |               15 |           0.75 |          31536000 |     32140800 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 10. Accrue with no performance.                                                                    |
        // |    NOTE: Ignore platform fees from now on because we've already tested they work and amounts at    |
        // |          this timescale are very small.                                                            |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $550 |           $0 |               15 |           0.75 |          32140800 |     32140800 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 11. Lose $150 worth of assets of yield.                                                            |
        // |    NOTE: Nothing should change because losses have not been accrued.                               |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $550 |           $0 |               15 |           0.75 |          32140800 |     32140800 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // | 12. Accrue with negative performance.                                                              |
        // |    NOTE: Losses are realized immediately.                                                          |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+
        // |         $400 |           $0 |               15 |           0.75 |          32745600 |     32745600 |
        // +--------------+--------------+------------------+----------------+-------------------+--------------+

        // 1. Deposit $300 worth of assets.
        USDC.mint(address(this), type(uint112).max);
        USDC.approve(address(cellar), type(uint112).max);
        cellar.deposit(300e6, address(this));
        cellar.enterPosition();

        assertEq(cellar.totalAssets(), 300e6, "1. Total assets should be $300.");

        // 2. An entire year passes.
        hevm.warp(block.timestamp + 365 days);
        uint256 lastAccrualTimestamp = block.timestamp;

        // 3. Accrue platform fees.
        cellar.accrue();

        assertEq(cellar.totalLocked(), 0, "3. Total locked should be $0.");
        assertApproxEq(cellar.totalAssets(), 300e6, 1e6, "3. Total assets should be $300.");
        assertApproxEq(cellar.totalBalance(), 300e6, 1e6, "3. Total balance should be $300.");
        assertEq(cellar.balanceOf(address(cellar)), 0.75e18, "3. Should have 0.75 shares of platform fees.");
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp, "3. Should have updated timestamp of last accrual.");

        // 4. Gains $150 worth of assets of yield.
        aUSDC.mint(address(cellar), 150e6, lendingPool.index());

        assertEq(cellar.totalLocked(), 0, "4. Total locked should be $0.");
        assertApproxEq(cellar.totalAssets(), 300e6, 1e6, "4. Total assets should be approximately $300.");
        assertApproxEq(cellar.totalBalance(), 300e6, 1e6, "4. Total balance should be approximately $300.");
        assertEq(cellar.balanceOf(address(cellar)), 0.75e18, "4. Should have 0.75 shares of platform fees.");
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp, "4. Should not have changed timestamp of last accrual.");

        // 5. Accrue with positive performance.
        uint256 priceOfShareBefore = cellar.convertToShares(1e6);
        cellar.accrue();
        uint256 priceOfShareAfter = cellar.convertToShares(1e6);

        assertEq(priceOfShareAfter, priceOfShareBefore, "5. Should not have changed worth of share immediately.");
        assertApproxEq(cellar.totalLocked(), 135e6, 1e6, "5. Total locked should be $135.");
        assertApproxEq(cellar.totalAssets(), 315e6, 2e6, "5. Total assets should be approximately $315.");
        assertApproxEq(cellar.totalBalance(), 450e6, 2e6, "5. Total balance should be approximately $450.");
        assertApproxEq(cellar.balanceOf(address(cellar)), 15e18, 1e18, "5. Should have 15 shares of performance fees.");
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp, "5. Should have changed timestamp of last accrual.");

        // 6. Half of accrual period passes.
        uint256 accrualPeriod = cellar.accrualPeriod();
        hevm.warp(block.timestamp + accrualPeriod / 2);

        assertApproxEq(cellar.totalLocked(), 67.5e6, 1e6, "6. Total locked should be $67.5.");
        assertApproxEq(cellar.totalAssets(), 382.5e6, 2e6, "6. Total assets should be approximately $382.5.");
        assertApproxEq(cellar.totalBalance(), 450e6, 2e6, "6. Total balance should be approximately $450.");
        assertApproxEq(cellar.balanceOf(address(cellar)), 15e18, 1e18, "6. Should have 15 shares of performance fees.");
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp, "6. Should not have changed timestamp of last accrual.");

        // 7. Deposit $200 worth of assets.
        cellar.deposit(200e6, address(this));
        cellar.enterPosition();

        assertApproxEq(cellar.totalLocked(), 67.5e6, 1e6, "7. Total locked should be $67.5.");
        assertApproxEq(cellar.totalAssets(), 582.5e6, 2e6, "7. Total assets should be approximately $582.5.");
        assertApproxEq(cellar.totalBalance(), 650e6, 2e6, "7. Total balance should be approximately $650.");
        assertApproxEq(cellar.balanceOf(address(cellar)), 15e18, 1e18, "7. Should have 15 shares of performance fees.");
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp, "7. Should not have changed timestamp of last accrual.");

        // 8. Entire accrual period passes.
        hevm.warp(block.timestamp + accrualPeriod / 2);

        assertEq(cellar.totalLocked(), 0, "8. Total locked should be $0.");
        assertApproxEq(cellar.totalAssets(), 650e6, 2e6, "8. Total assets should be approximately $650.");
        assertApproxEq(cellar.totalBalance(), 650e6, 2e6, "8. Total balance should be approximately $650.");
        assertApproxEq(cellar.balanceOf(address(cellar)), 15e18, 1e18, "8. Should have 15 shares of performance fees.");
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp, "8. Should not have changed timestamp of last accrual.");

        // 9. Withdraw $100 worth of assets.
        cellar.withdraw(100e6, address(this), address(this));

        assertEq(cellar.totalLocked(), 0, "9. Total locked should be $0.");
        assertApproxEq(cellar.totalAssets(), 550e6, 2e6, "9. Total assets should be approximately $550.");
        assertApproxEq(cellar.totalBalance(), 550e6, 2e6, "9. Total balance should be approximately $550.");
        assertApproxEq(cellar.balanceOf(address(cellar)), 15e18, 1e18, "9. Should have 15 shares of performance fees.");
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp, "9. Should not have changed timestamp of last accrual.");

        // 10. Accrue with no performance.
        cellar.accrue();
        lastAccrualTimestamp = block.timestamp;

        assertEq(cellar.totalLocked(), 0, "10. Total locked should be $0.");
        assertApproxEq(cellar.totalAssets(), 550e6, 2e6, "10. Total assets should be approximately $550.");
        assertApproxEq(cellar.totalBalance(), 550e6, 2e6, "10. Total balance should be approximately $550.");
        assertApproxEq(
            cellar.balanceOf(address(cellar)),
            15e18,
            1e18,
            "10. Should have 15 shares of performance fees."
        );
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp, "10. Should have changed timestamp of last accrual.");

        // 11. Lose $150 worth of assets of yield.
        aUSDC.burn(address(cellar), 150e6);

        assertEq(cellar.totalLocked(), 0, "11. Total locked should be $0.");
        assertApproxEq(cellar.totalAssets(), 550e6, 2e6, "11. Total assets should be approximately $550.");
        assertApproxEq(cellar.totalBalance(), 550e6, 2e6, "11. Total balance should be approximately $550.");
        assertApproxEq(
            cellar.balanceOf(address(cellar)),
            15e18,
            1e18,
            "11. Should have 15 shares of performance fees."
        );
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp, "11. Should not have changed timestamp of last accrual.");

        // 12. Accrue with negative performance.
        cellar.accrue();

        assertEq(cellar.totalLocked(), 0, "12. Total locked should be $0.");
        assertApproxEq(cellar.totalAssets(), 400e6, 2e6, "12. Total assets should be approximately $400.");
        assertApproxEq(cellar.totalBalance(), 400e6, 2e6, "12. Total balance should be approximately $400.");
        assertApproxEq(
            cellar.balanceOf(address(cellar)),
            15e18,
            1e18,
            "12. Should have 15 shares of performance fees."
        );
        assertEq(cellar.lastAccrual(), lastAccrualTimestamp, "12. Should have changed timestamp of last accrual.");
    }

    // ========================================== POSITION TESTS ==========================================

    function testEnterPosition(uint256 assets) external {
        assets = bound(assets, 1e6, type(uint72).max);

        USDC.mint(address(this), assets);
        cellar.deposit(assets, address(this));

        cellar.enterPosition(assets / 2);

        assertEq(aUSDC.balanceOf(address(cellar)), assets / 2, "Should have deposited half of assets.");
        assertEq(cellar.totalAssets(), assets, "Total asset should be the assets in holding and in position.");
        assertEq(cellar.totalBalance(), assets / 2, "Total balance should be the assets in position.");
        assertEq(cellar.totalHoldings(), assets - assets / 2, "Total holdings should be the assets not in position.");

        cellar.enterPosition();

        assertEq(aUSDC.balanceOf(address(cellar)), assets, "Should have deposited all of assets.");
        assertEq(cellar.totalAssets(), assets, "Total asset should not have changed.");
        assertEq(cellar.totalBalance(), assets, "Total balance should be all of assets.");
        assertEq(cellar.totalHoldings(), 0, "Total holdings should be empty.");
    }

    function testFailEnterPositionWithoutEnoughHoldings() external {
        USDC.mint(address(this), 100e6);
        cellar.deposit(100e6, address(this));

        cellar.enterPosition(101e6);
    }

    function testExitPosition(uint256 assets) external {
        assets = bound(assets, 1e6, type(uint72).max);

        USDC.mint(address(this), type(uint72).max);
        cellar.deposit(type(uint72).max, address(this));
        cellar.enterPosition();

        // Simulate gains.
        aUSDC.mint(address(cellar), assets);

        cellar.exitPosition(assets);

        assertEq(aUSDC.balanceOf(address(cellar)), type(uint72).max, "Should not have withdrawn unrealized gains.");
        assertEq(USDC.balanceOf(address(cellar)), assets, "Should have withdrawn assets.");
        assertEq(cellar.totalBalance(), type(uint72).max - assets, "Total balance should be remaining assets.");
        assertEq(cellar.totalHoldings(), assets, "Total holdings should be assets withdrawn assets.");
    }

    function testFailExitPositionWithoutEnoughBalance() external {
        USDC.mint(address(this), 100e6);
        cellar.deposit(100e6, address(this));
        cellar.enterPosition();

        cellar.exitPosition(101e6);
    }

    // ========================================= REBALANCE TESTS =========================================

    function testRebalance(uint256 assets) external {
        // assets = bound(assets, 1e6, type(uint72).max);
        assets = 100e6;

        emit log_named_uint("assets", assets);

        USDC.mint(address(this), assets);

        cellar.deposit(assets, address(this));
        cellar.enterPosition(assets / 2);

        address[9] memory route;
        route[0] = address(USDC);
        route[1] = address(1);
        route[2] = address(DAI);

        uint256[3][4] memory swapParams;

        uint256 maxLockedBefore = cellar.maxLocked();

        uint256 totalAssetsBeforeRebalance = cellar.totalAssets();
        uint256 priceOfShareBeforeRebalance = cellar.convertToAssets(1e18);
        cellar.rebalance(route, swapParams, 0);
        uint256 priceOfShareAfterRebalance = cellar.convertToAssets(1e18).changeDecimals(18, 6);
        uint256 totalAssetsAfterRebalance = cellar.totalAssets().changeDecimals(18, 6);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(DAI);

        uint256 assetsAfterRebalance = swapRouter.quote(assets, path);

        assertEq(address(cellar.asset()), address(DAI), "Should have updated asset to DAI.");
        assertEq(address(cellar.assetAToken()), address(aDAI), "Should have updated asset's aToken to aDAI.");
        assertEq(cellar.assetDecimals(), 18, "Should have updated asset's decimals to 18.");
        assertEq(cellar.maxLocked(), maxLockedBefore.changeDecimals(6, 18), "Should have updated max locked.");

        assertEq(USDC.balanceOf(address(cellar)), 0, "Should have withdrawn all holdings.");
        assertEq(aUSDC.balanceOf(address(cellar)), 0, "Should have withdrawn all position balance.");
        assertEq(
            aDAI.balanceOf(address(cellar)),
            assetsAfterRebalance, // Simulating 5% price impact on swap.
            "Should have deposited all assets into new position."
        );
        assertEq(cellar.totalBalance(), assetsAfterRebalance, "Should have updated total balance.");
        assertLt(priceOfShareAfterRebalance, priceOfShareBeforeRebalance, "Expect price of shares to have decreased.");
        assertLt(totalAssetsAfterRebalance, totalAssetsBeforeRebalance, "Expect total assets to have decreased.");

        // Accrue performance fees on swap losses.
        cellar.accrue();

        assertEq(cellar.balanceOf(address(cellar)), 0, "Should accrue no fees for swap losses.");
    }

    function testRebalanceWithUnrealizedGains(uint256 assets) external {
        assets = bound(assets, 1e6, type(uint72).max);

        USDC.mint(address(this), assets);

        cellar.deposit(assets, address(this));
        cellar.enterPosition(assets / 2);

        // Simulate gains.
        aUSDC.mint(address(cellar), assets / 2);

        address[9] memory route;
        route[0] = address(USDC);
        route[1] = address(1);
        route[2] = address(DAI);

        uint256[3][4] memory swapParams;

        uint256 totalBalanceAndHoldingsBeforeRebalance = cellar.totalBalance() + cellar.totalHoldings();

        uint256 totalAssetsBeforeRebalance = cellar.totalAssets();
        uint256 priceOfShareBeforeRebalance = cellar.convertToAssets(1e18);
        cellar.rebalance(route, swapParams, 0);
        uint256 priceOfShareAfterRebalance = cellar.convertToAssets(1e18).changeDecimals(18, 6);
        uint256 totalAssetsAfterRebalance = cellar.totalAssets().changeDecimals(18, 6);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(DAI);

        uint256 assetsAfterRebalance = swapRouter.quote(assets + assets / 2, path);

        assertEq(USDC.balanceOf(address(cellar)), 0, "Should have withdrawn all holdings.");
        assertEq(aUSDC.balanceOf(address(cellar)), 0, "Should have withdrawn all position balance.");
        assertEq(
            aDAI.balanceOf(address(cellar)),
            assetsAfterRebalance, // Simulating 5% price impact on swap.
            "Should have deposited all assets into new position."
        );
        assertEq(
            cellar.totalBalance(),
            totalBalanceAndHoldingsBeforeRebalance.changeDecimals(6, 18),
            "Should have updated total balance."
        );
        assertEq(
            priceOfShareAfterRebalance,
            priceOfShareBeforeRebalance,
            "Expect price of shares to have not changed."
        );
        assertEq(totalAssetsAfterRebalance, totalAssetsBeforeRebalance, "Expect total assets to have not changed.");

        // Accrue performance fees on net gains.
        cellar.accrue();

        assertGt(cellar.maxWithdraw(address(cellar)), 0, "Should accrue fees for net gains.");
    }

    function testRebalanceWithRealizedGains(uint256 assets) external {
        assets = bound(assets, 1e6, type(uint72).max);

        USDC.mint(address(this), assets);

        cellar.deposit(assets, address(this));
        cellar.enterPosition(assets / 2);

        // Simulate gains.
        aUSDC.mint(address(cellar), assets / 2);

        // Accrue performancefees on gains.
        cellar.accrue();

        assertGt(cellar.maxLocked(), 0, "Should realized gains.");
        assertGt(cellar.maxWithdraw(address(cellar)), 0, "Should accrue fees for gains.");

        address[9] memory route;
        route[0] = address(USDC);
        route[1] = address(1);
        route[2] = address(DAI);

        uint256[3][4] memory swapParams;

        uint256 totalAssetsBeforeRebalance = cellar.totalAssets();
        uint256 priceOfShareBeforeRebalance = cellar.convertToAssets(1e18);
        cellar.rebalance(route, swapParams, 0);
        uint256 priceOfShareAfterRebalance = cellar.convertToAssets(1e18).changeDecimals(18, 6);
        uint256 totalAssetsAfterRebalance = cellar.totalAssets().changeDecimals(18, 6);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(DAI);

        uint256 assetsAfterRebalance = swapRouter.quote(assets + assets / 2, path);

        assertEq(USDC.balanceOf(address(cellar)), 0, "Should have withdrawn all holdings.");
        assertEq(aUSDC.balanceOf(address(cellar)), 0, "Should have withdrawn all position balance.");
        assertEq(
            aDAI.balanceOf(address(cellar)),
            assetsAfterRebalance, // Simulating 5% price impact on swap.
            "Should have deposited all assets into new position."
        );
        assertEq(cellar.totalBalance(), assetsAfterRebalance, "Should have updated total balance.");
        assertLt(priceOfShareAfterRebalance, priceOfShareBeforeRebalance, "Expect price of shares to have decreased.");
        assertLt(totalAssetsAfterRebalance, totalAssetsBeforeRebalance, "Expect total assets to have decreased.");
    }

    function testRebalanceWithEmptyPosition(uint256 assets) external {
        assets = bound(assets, 1e6, type(uint72).max);

        USDC.mint(address(this), assets);

        cellar.deposit(assets, address(this));

        address[9] memory route;
        route[0] = address(USDC);
        route[1] = address(1);
        route[2] = address(DAI);

        uint256[3][4] memory swapParams;

        cellar.rebalance(route, swapParams, 0);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(DAI);

        uint256 assetsAfterRebalance = swapRouter.quote(assets, path);

        assertEq(USDC.balanceOf(address(cellar)), 0, "Should have withdrawn all holdings.");
        assertEq(
            aDAI.balanceOf(address(cellar)),
            assetsAfterRebalance, // Simulating 5% price impact on swap.
            "Should have deposited all assets into new position."
        );
    }

    function testFailRebalanceIntoSamePosition() external {
        USDC.mint(address(this), 1000e6);

        cellar.deposit(1000e6, address(this));
        cellar.enterPosition(500e6);

        address[9] memory route;
        route[0] = address(USDC);
        route[1] = address(1);
        route[2] = address(USDC);

        uint256[3][4] memory swapParams;

        cellar.rebalance(route, swapParams, 0);
    }

    function testFailRebalanceIntoUntrustedPosition() external {
        USDC.mint(address(this), 1000e6);

        cellar.deposit(1000e6, address(this));
        cellar.enterPosition(500e6);

        cellar.setTrust(ERC20(DAI), false);

        address[9] memory route;
        route[0] = address(USDC);
        route[1] = address(1);
        route[2] = address(DAI);

        uint256[3][4] memory swapParams;

        cellar.rebalance(route, swapParams, 0);
    }

    // ========================================= REINVEST TESTS =========================================

    function testReinvest() external {
        incentivesController.addRewards(address(cellar), 10e18);
        cellar.claimAndUnstake();

        assertEq(stkAAVE.balanceOf(address(cellar)), 10e18, "Should have gained stkAAVE rewards.");

        hevm.warp(block.timestamp + 10 days + 1);

        cellar.reinvest(0);

        assertEq(stkAAVE.balanceOf(address(cellar)), 0, "Should have reinvested all stkAAVE.");
        assertEq(aUSDC.balanceOf(address(cellar)), 950e6, "Should have reinvested into current position.");
        assertEq(cellar.totalAssets(), 0, "Should have not updated total assets because its unrealized gains.");

        // Test that reinvested rewards are counted as yield.
        cellar.accrue();

        assertApproxEq(cellar.totalAssets(), 9.5e6, 0.1e6, "Should have updated total assets after accrual.");
        assertApproxEq(cellar.totalLocked(), 85.5e6, 0.1e6, "Should have realized gains.");
        assertApproxEq(cellar.totalBalance(), 95e6, 0.1e6, "Should have updated total balance after accrual.");
    }

    // =========================================== FEES TESTS ===========================================

    function testSendFees() external {
        aUSDC.mint(address(cellar), 100e6);

        cellar.accrue();

        assertEq(cellar.totalAssets(), 10e6, "Should have updated total assets after accrual.");
        assertEq(cellar.totalSupply(), 10e18, "Should have updated total supply after accrual.");
        assertEq(cellar.balanceOf(address(cellar)), 10e18, "Should minted performance fees.");

        cellar.sendFees();

        assertEq(cellar.totalAssets(), 0, "Should have sent assets.");
        assertEq(cellar.totalSupply(), 0, "Should have redeemed fees.");
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should have burned performance fees.");
    }

    // ========================================== TRUST TESTS ==========================================

    function testDistrustingCurrentPosition() external {
        USDC.mint(address(this), 900e6);
        cellar.deposit(900e6, address(this));
        cellar.enterPosition(500e6);

        // Simulate gaining $100 of yield.
        aUSDC.mint(address(cellar), 100e6);

        assertEq(aUSDC.balanceOf(address(cellar)), 600e6, "Should have $100 of unrealized yield.");
        assertEq(cellar.totalAssets(), 900e6, "Should have $900 total assets.");

        uint256 priceOfShareBeforeDistrust = cellar.convertToAssets(1e6);
        cellar.setTrust(ERC20(USDC), false);
        uint256 priceOfShareAfterDistrust = cellar.convertToAssets(1e6);

        assertFalse(cellar.isTrusted(ERC20(USDC)), "Should have distrusted USDC.");
        assertEq(cellar.totalAssets(), 910e6, "Should have updated total assets after accrual.");
        assertEq(cellar.totalLocked(), 90e6, "Should have realized gains after accrual.");
        assertEq(
            priceOfShareBeforeDistrust,
            priceOfShareAfterDistrust,
            "Should have not changed price of share immediately."
        );
    }

    function testDistrustingCurrentPositionWhenEmpty() external {
        cellar.setTrust(ERC20(USDC), false);

        assertEq(aUSDC.balanceOf(address(cellar)), 0, "Should have empty position.");
        assertFalse(cellar.isTrusted(ERC20(USDC)), "Should have distrusted USDC.");
    }

    // ======================================== EMERGENCY TESTS ========================================

    function testShutdown() external {
        cellar.initiateShutdown(false);

        assertTrue(cellar.isShutdown(), "Should have initiated shutdown.");

        cellar.liftShutdown();

        assertFalse(cellar.isShutdown(), "Should have lifted shutdown.");
    }

    function testShutdownAndExit() external {
        USDC.mint(address(this), 900e6);
        cellar.deposit(900e6, address(this));
        cellar.enterPosition(500e6);

        // Simulate gaining $100 of yield.
        aUSDC.mint(address(cellar), 100e6);

        assertEq(aUSDC.balanceOf(address(cellar)), 600e6, "Should have $100 of unrealized yield.");
        assertEq(cellar.totalAssets(), 900e6, "Should have $900 total assets.");

        uint256 priceOfShareBeforeShutdown = cellar.convertToAssets(1e6);
        cellar.initiateShutdown(true);
        uint256 priceOfShareAfterShutdown = cellar.convertToAssets(1e6);

        assertTrue(cellar.isShutdown());
        assertEq(cellar.totalAssets(), 910e6);
        assertEq(cellar.totalLocked(), 90e6);
        assertEq(
            priceOfShareBeforeShutdown,
            priceOfShareAfterShutdown,
            "Should have not changed price of share immediately."
        );
    }

    function testShutdownAndExitWithEmptyPosition() external {
        cellar.initiateShutdown(true);

        assertTrue(cellar.isShutdown(), "Should have initiated shutdown.");
    }

    function testWithdrawingWhileShutdown() external {
        USDC.mint(address(this), 1);
        cellar.deposit(1, address(this));

        cellar.initiateShutdown(false);

        cellar.withdraw(1, address(this), address(this));

        assertEq(USDC.balanceOf(address(this)), 1, "Should withdraw while shutdown.");
    }

    function testFailDepositingWhileShutdown() external {
        cellar.initiateShutdown(false);

        USDC.mint(address(this), 1);
        cellar.deposit(1, address(this));
    }

    function testFailEnteringPositionWhileShutdown() external {
        USDC.mint(address(this), 1);
        cellar.deposit(1, address(this));

        cellar.initiateShutdown(false);

        cellar.enterPosition();
    }

    function testFailRebalancingWhileShutdown() external {
        USDC.mint(address(this), 1);
        cellar.deposit(1, address(this));

        cellar.initiateShutdown(false);

        address[9] memory route;
        route[0] = address(USDC);
        route[1] = address(1);
        route[2] = address(DAI);

        uint256[3][4] memory swapParams;

        cellar.rebalance(route, swapParams, 0);
    }

    function testFailInitiatingShutdownWhileShutdown() external {
        cellar.initiateShutdown(false);
        cellar.initiateShutdown(false);
    }

    // ======================================== INTEGRATION TESTS ========================================

    function mutate(uint256 salt) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(salt))) % 1e26;
    }

    function testIntegration(uint8 salt) external {
        // Initialize users.
        address alice = hevm.addr(1);
        address bob = hevm.addr(2);
        address charlie = hevm.addr(3);

        // Mint initial balance to users.
        USDC.mint(alice, type(uint112).max);
        USDC.mint(bob, type(uint112).max);
        USDC.mint(charlie, type(uint112).max);
        DAI.mint(alice, type(uint112).max);
        DAI.mint(bob, type(uint112).max);
        DAI.mint(charlie, type(uint112).max);

        // Approve cellar to send user assets.
        hevm.startPrank(alice);
        USDC.approve(address(cellar), type(uint256).max);
        DAI.approve(address(cellar), type(uint256).max);
        hevm.stopPrank();
        hevm.startPrank(bob);
        USDC.approve(address(cellar), type(uint256).max);
        DAI.approve(address(cellar), type(uint256).max);
        hevm.stopPrank();
        hevm.startPrank(charlie);
        USDC.approve(address(cellar), type(uint256).max);
        DAI.approve(address(cellar), type(uint256).max);
        hevm.stopPrank();

        // ====================== BEGIN SCENERIO ======================

        // 1. Alice deposits.
        uint256 amount = mutate(salt);
        hevm.prank(alice);
        cellar.deposit(amount, alice);

        // 2. Cellar enters position.
        cellar.enterPosition(cellar.totalHoldings() / 2);

        // 3. Cellar gains yield.
        amount = mutate(amount);
        MockERC20(address(cellar.assetAToken())).mint(address(cellar), amount);

        // 4. Cellar accrues.
        cellar.accrue();
        hevm.warp(block.timestamp + cellar.accrualPeriod());

        // 5. Distrust current position.
        cellar.setTrust(cellar.asset(), false);

        // 6. Cellar rebalances into DAI.
        address[9] memory route;
        route[0] = address(USDC);
        route[1] = address(1);
        route[2] = address(DAI);

        uint256[3][4] memory swapParams;

        cellar.rebalance(route, swapParams, 0);

        // 7. Bob mints.
        amount = mutate(amount);
        hevm.prank(bob);
        cellar.mint(amount, bob);

        // 8. Cellar gains yield.
        amount = mutate(amount);
        MockERC20(address(cellar.assetAToken())).mint(address(cellar), amount);

        // 9. Cellar claims rewards.
        amount = mutate(amount);
        incentivesController.addRewards(address(cellar), amount);
        cellar.claimAndUnstake();
        hevm.warp(block.timestamp + 10 days + 1);

        // 10. Cellar rebalance into USDC.
        cellar.setTrust(ERC20(address(USDC)), true);

        route[0] = address(DAI);
        route[2] = address(USDC);

        cellar.rebalance(route, swapParams, 0);

        // 11. Charlie deposits.
        amount = mutate(amount);
        hevm.prank(charlie);
        cellar.deposit(amount, charlie);

        // 12. Cellar exits position.
        cellar.exitPosition(cellar.totalBalance() / 4);

        // 13. Cellar reinvest rewards.
        cellar.reinvest(0);

        // 14. Bob withdraws.
        hevm.startPrank(bob);
        cellar.withdraw(cellar.maxWithdraw(bob) / 3, bob, bob);
        hevm.stopPrank();

        // 15. Cellar enters position.
        cellar.enterPosition(cellar.totalHoldings() / 5);

        // 16. Cellar shuts down.
        cellar.initiateShutdown(true);

        // 17. Alice redeems all.
        hevm.startPrank(alice);
        cellar.redeem(cellar.maxRedeem(alice), alice, alice);
        hevm.stopPrank();

        // 18. Bob withdraws all.
        hevm.startPrank(bob);
        cellar.withdraw(cellar.maxWithdraw(bob), bob, bob);
        hevm.stopPrank();

        // 19. Charlie withdraws all.
        hevm.startPrank(charlie);
        cellar.withdraw(cellar.maxWithdraw(charlie), charlie, charlie);
        hevm.stopPrank();

        // 20. Sends fees.
        cellar.sendFees();

        // ====================== FINAL CHECKS ======================

        assertApproxEq(cellar.totalSupply(), 0, 0.0001e18, "Check total supply is what is expected.");
        assertApproxEq(cellar.totalAssets(), 0, 0.0001e6, "Check total assets is what is expected.");
        assertApproxEq(cellar.totalBalance(), 0, 0.0001e6, "Check total balance is what is expected.");
        assertApproxEq(cellar.totalHoldings(), 0, 0.0001e6, "Check total holdings is what is expected.");
    }
}
