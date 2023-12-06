// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { ERC20DebtAdaptor } from "src/mocks/ERC20DebtAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { SimpleSlippageRouter } from "src/modules/SimpleSlippageRouter.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

/**
 * NOTE: test setup involves trying to carry out all functions to a cellar. Need to replicate scenarios that do not return the correct amount to the user via the router. Can do that by manipulating the cellar totalAssets and share amounts per test.
 * TODO: initialShares belongs to  this test contract since it created the cellar no? --> this comment is outlined multiple times because I just want to double check. If it does apply and there is a fix then the asserts marked with this comment need to be adjusted.
 */
contract SimpleSlippageRouterTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    Cellar private cellar;

    SimpleSlippageRouter private simpleSlippageRouter;

    MockDataFeed private mockUsdcUsd;

    uint32 private usdcPosition = 1;

    uint256 private initialAssets;
    uint256 private initialShares;

    // vars used to check within tests
    uint256 deposit1;
    uint256 minShares1;
    uint64 deadline1;
    uint256 shareBalance1;
    uint256 deposit2;
    uint256 minShares2;
    uint64 deadline2;
    uint256 shareBalance2;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        // Get a cellar w/ usdc holding position, deploy a SlippageRouter to work with it.
        _setUp();

        mockUsdcUsd = new MockDataFeed(USDC_USD_FEED);
        simpleSlippageRouter = new SimpleSlippageRouter();

        // Setup pricing
        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(mockUsdcUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUsdcUsd));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Setup exchange rates:
        // USDC Simulated Price: $1
        // mockUsdcUsd.setMockAnswer(1e6);

        // Add adaptors and ERC20 positions to the registry.
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));

        // Create Dummy Cellars.
        string memory cellarName = "Dummy Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellarName = "Cellar V0.0";
        initialDeposit = 1e6;
        platformCut = 0.75e18;
        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(0), initialDeposit, platformCut);

        vm.label(address(cellar), "cellar");

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        USDC.approve(address(simpleSlippageRouter), type(uint256).max);

        initialAssets = cellar.totalAssets();
        initialShares = cellar.totalSupply();
    }

    // ========================================= INITIALIZATION TEST =========================================

    // simpleSlippageRouter should not have any assets, any approvals, etc.
    function testInitialization() external {}

    // ========================================= HAPPY PATH TEST =========================================

    // test depositing using SimpleSlippageRouter
    // deposit() using SSR, deposit again using SSR. See that appropriate amount of funds were deposited.
    function testDeposit(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);

        // deal USDC assets to test contract
        deal(address(USDC), address(this), assets);
        deposit1 = assets / 2;
        minShares1 = deposit1;
        deadline1 = uint64(block.timestamp + 1 days);

        console.log("BEFORE: Total Cellar Shares: %s", cellar.totalSupply());

        console.log("BEFORE: Cellar Shares Belonging to Test Contract: %s", cellar.balanceOf(address(this)));

        // deposit half using the SSR
        simpleSlippageRouter.deposit(cellar, deposit1, minShares1, deadline1);
        console.log("AFTER: Cellar Shares Belonging to Test Contract: %s", cellar.balanceOf(address(this)));
        console.log("AFTER: Total Cellar Shares: %s", cellar.totalSupply());

        shareBalance1 = cellar.balanceOf(address(this));

        assertEq(shareBalance1, minShares1); // shares and assets are 1:1 right now because it's just USDC in a holding position - TODO: initialShares belongs to  this test contract since it created the cellar no?
        assertEq(USDC.balanceOf(address(this)), assets - deposit1); // check that cellar balances are proper (new balance = deposit + initialAssets)

        // the other half using the SSR
        simpleSlippageRouter.deposit(cellar, deposit1, minShares1, deadline1);

        // check that cellar balances are proper (new balance = totalDeposit + initialAssets)
        shareBalance2 = cellar.balanceOf(address(this));

        assertApproxEqAbs(shareBalance2, assets, 2, "deposit(): Test contract USDC should be all shares"); // shares and assets are 1:1 right now because it's just USDC in a holding position - TODO: initialShares belongs to  this test contract since it created the cellar no?
        assertApproxEqAbs(USDC.balanceOf(address(this)), 0, 2, "deposit(): All USDC deposited to Cellar");
    }

    // test withdrawing using SimpleSlippageRouter
    // TODO: debug
    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);

        // deal USDC assets to test contract
        deal(address(USDC), address(this), assets);
        deposit1 = assets / 2;
        minShares1 = deposit1;
        deadline1 = uint64(block.timestamp + 1 days);
        // deposit half using the SSR
        simpleSlippageRouter.deposit(cellar, deposit1, minShares1, deadline1);

        // withdraw a quarter using the SSR
        uint256 withdraw1 = deposit1 / 2;
        uint256 maxShares1 = withdraw1; // assume 1:1 USDC:Shares shareprice
        simpleSlippageRouter.withdraw(cellar, withdraw1, maxShares1, deadline1); // TODO: debug underflow/overflow error

        shareBalance1 = cellar.balanceOf(address(this));

        // check that cellar balances are proper (new balance = (deposit) - withdraw)
        assertApproxEqAbs(
            shareBalance1,
            (assets / 2) - withdraw1,
            2,
            "withdraw(): Test contract should have redeemed half of its shares"
        );
        assertApproxEqAbs(
            USDC.balanceOf(address(this)),
            (assets / 2) + withdraw1,
            2,
            "withdraw(): Should have withdrawn expected partial amount"
        ); // check that cellar balances are proper (new balance = deposit + initialAssets)

        // withdraw the rest using the SSR
        uint256 withdraw2 = cellar.balanceOf(address(this));
        simpleSlippageRouter.withdraw(cellar, withdraw2, withdraw2, deadline1); // TODO: debug underflow/overflow error

        shareBalance2 = cellar.balanceOf(address(this));

        // check that cellar balances are proper (new balance = (deposit) - withdraw)
        assertApproxEqAbs(shareBalance2, 0, 2, "withdraw(): Test contract should have redeemed all of its shares");
        assertApproxEqAbs(
            USDC.balanceOf(address(this)),
            assets,
            2,
            "withdraw(): Should have withdrawn expected entire USDC amount"
        );
    }

    // test minting using SimpleSlippageRouter
    function testMint(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);

        // deal USDC assets to test contract
        deal(address(USDC), address(this), assets);
        deposit1 = assets / 2;
        minShares1 = deposit1;
        deadline1 = uint64(block.timestamp + 1 days);

        console.log("BEFORE: Total Cellar Shares: %s", cellar.totalSupply());

        console.log("BEFORE: Cellar Shares Belonging to Test Contract: %s", cellar.balanceOf(address(this)));

        // mint with half of the assets using the SSR
        simpleSlippageRouter.mint(cellar, deposit1, minShares1, deadline1);
        console.log("AFTER: Cellar Shares Belonging to Test Contract: %s", cellar.balanceOf(address(this)));
        console.log("AFTER: Total Cellar Shares: %s", cellar.totalSupply());

        shareBalance1 = cellar.balanceOf(address(this));

        assertEq(shareBalance1, minShares1); // shares and assets are 1:1 right now because it's just USDC in a holding position - TODO: initialShares belongs to  this test contract since it created the cellar no?
        assertEq(USDC.balanceOf(address(this)), assets - deposit1); // check that cellar balances are proper (new balance = deposit + initialAssets)

        // mint using the other half using the SSR
        simpleSlippageRouter.mint(cellar, deposit1, minShares1, deadline1);

        // check that cellar balances are proper (new balance = totalDeposit + initialAssets)
        shareBalance2 = cellar.balanceOf(address(this));

        assertApproxEqAbs(shareBalance2, assets, 2, "mint(): Test contract USDC should be all shares"); // shares and assets are 1:1 right now because it's just USDC in a holding position - TODO: initialShares belongs to  this test contract since it created the cellar no?
        assertApproxEqAbs(USDC.balanceOf(address(this)), 0, 2, "mint(): All USDC deposited to Cellar");
    }

    // test redeeming using SimpleSlippageRouter
    // TODO: debug
    function testRedeem(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);

        // deal USDC assets to test contract
        deal(address(USDC), address(this), assets);
        deposit1 = assets / 2;
        minShares1 = deposit1;
        deadline1 = uint64(block.timestamp + 1 days);
        // deposit half using the SSR
        simpleSlippageRouter.deposit(cellar, deposit1, minShares1, deadline1);

        // redeem half of the shares test contract has using the SSR
        uint256 withdraw1 = deposit1 / 2;
        uint256 maxShares1 = withdraw1; // assume 1:1 USDC:Shares shareprice
        simpleSlippageRouter.redeem(cellar, withdraw1, maxShares1, deadline1); // TODO: debug underflow/overflow error

        shareBalance1 = cellar.balanceOf(address(this));

        // check that cellar balances are proper (new balance = (deposit) - withdraw)
        assertApproxEqAbs(
            shareBalance1,
            (assets / 2) - withdraw1,
            2,
            "redeem(): Test contract should have redeemed half of its shares"
        );
        assertApproxEqAbs(
            USDC.balanceOf(address(this)),
            (assets / 2) + withdraw1,
            2,
            "redeem(): Should have withdrawn expected partial amount"
        ); // check that cellar balances are proper (new balance = deposit + initialAssets)

        // redeem the rest using the SSR
        uint256 withdraw2 = cellar.balanceOf(address(this));
        simpleSlippageRouter.redeem(cellar, withdraw2, withdraw2, deadline1); // TODO: debug underflow/overflow error

        shareBalance2 = cellar.balanceOf(address(this));

        // check that cellar balances are proper (new balance = (deposit) - withdraw)
        assertApproxEqAbs(shareBalance2, 0, 2, "redeem(): Test contract should have redeemed all of its shares");
        assertApproxEqAbs(
            USDC.balanceOf(address(this)),
            assets,
            2,
            "redeem(): Should have withdrawn expected entire USDC amount"
        );
    }

    // ========================================= REVERSION TEST =========================================

    // For revert tests, check that reversion occurs and then resolve it showing a passing tx.

    function testBadDeadline() external {
        // test revert in all functions
    }

    function testDepositMinimumSharesUnmet() external {
        // test revert in deposit()
    }

    function testWithdrawMaxSharesSurpassed() external {
        // test revert in withdraw()
    }

    function testMintMinimumSharesSurpassed() external {
        // test revert in mint()
    }

    function testRedeemMaxSharesSurpassed() external {
        // test revert in redeem()
    }

    // ========================================= INTEGRATION TEST =========================================

    // Test the deposit function combined with the withdraw, mint, and redeem functions. This would have multiple users in it. It's a more full integration test.

    //============================================ Helper Functions ===========================================
}
