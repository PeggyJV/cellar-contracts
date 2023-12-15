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

        // Add adaptors and ERC20 positions to the registry.
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));

        // Create Dummy Cellars.
        string memory cellarName = "Dummy Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellarName = "Cellar V0.0";
        initialDeposit = 1e6;
        platformCut = 0.75e18;
        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(true), initialDeposit, platformCut);

        vm.label(address(cellar), "cellar");

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        USDC.approve(address(simpleSlippageRouter), type(uint256).max);

        initialAssets = cellar.totalAssets();
        initialShares = cellar.totalSupply();
    }

    // ========================================= HAPPY PATH TEST =========================================

    // deposit() using SSR, deposit again using SSR. See that appropriate amount of funds were deposited.
    function testDeposit(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);

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

        assertEq(shareBalance1, minShares1);
        assertEq(USDC.balanceOf(address(this)), assets - deposit1);

        // deposit the other half using the SSR
        simpleSlippageRouter.deposit(cellar, deposit1, minShares1, deadline1);

        shareBalance2 = cellar.balanceOf(address(this));

        assertApproxEqAbs(shareBalance2, assets, 2, "deposit(): Test contract USDC should be all shares");
        assertApproxEqAbs(USDC.balanceOf(address(this)), 0, 2, "deposit(): All USDC deposited to Cellar");

        // check allowance SSR given to cellar is zeroed out
        ERC20 cellarERC20 = ERC20(address(cellar));
        assertEq(
            cellarERC20.allowance(address(simpleSlippageRouter), address(cellar)),
            0,
            "cellar's approval to spend SSR cellarToken should be zeroed out."
        );
    }

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
        uint256 withdraw1 = assets / 4;
        uint256 maxShares1 = withdraw1; // assume 1:1 USDC:Shares shareprice
        cellar.approve(address(simpleSlippageRouter), withdraw1);
        simpleSlippageRouter.withdraw(cellar, withdraw1, maxShares1, deadline1);

        shareBalance1 = cellar.balanceOf(address(this));

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
        );

        // withdraw the rest using the SSR
        uint256 withdraw2 = cellar.balanceOf(address(this));
        cellar.approve(address(simpleSlippageRouter), withdraw2);

        simpleSlippageRouter.withdraw(cellar, withdraw2, withdraw2, deadline1);

        shareBalance2 = cellar.balanceOf(address(this));

        assertApproxEqAbs(shareBalance2, 0, 2, "withdraw(): Test contract should have redeemed all of its shares");
        assertApproxEqAbs(
            USDC.balanceOf(address(this)),
            assets,
            2,
            "withdraw(): Should have withdrawn expected entire USDC amount"
        );
    }

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
        simpleSlippageRouter.mint(cellar, minShares1, deposit1, deadline1);
        console.log("AFTER: Cellar Shares Belonging to Test Contract: %s", cellar.balanceOf(address(this)));
        console.log("AFTER: Total Cellar Shares: %s", cellar.totalSupply());

        shareBalance1 = cellar.balanceOf(address(this));

        assertEq(shareBalance1, minShares1);
        assertEq(USDC.balanceOf(address(this)), assets - deposit1);

        // mint using the other half using the SSR
        simpleSlippageRouter.mint(cellar, minShares1, deposit1, deadline1);

        shareBalance2 = cellar.balanceOf(address(this));

        assertApproxEqAbs(shareBalance2, assets, 2, "mint(): Test contract USDC should be all shares");
        assertApproxEqAbs(USDC.balanceOf(address(this)), 0, 2, "mint(): All USDC deposited to Cellar");

        // check allowance SSR given to cellar is zeroed out
        ERC20 cellarERC20 = ERC20(address(cellar));
        assertEq(
            cellarERC20.allowance(address(simpleSlippageRouter), address(cellar)),
            0,
            "cellar's approval to spend SSR cellarToken should be zeroed out."
        );
    }

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
        cellar.approve(address(simpleSlippageRouter), withdraw1);

        simpleSlippageRouter.redeem(cellar, maxShares1, withdraw1, deadline1);

        shareBalance1 = cellar.balanceOf(address(this));

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
        );

        // redeem the rest using the SSR
        uint256 withdraw2 = cellar.balanceOf(address(this));
        cellar.approve(address(simpleSlippageRouter), withdraw2);

        simpleSlippageRouter.redeem(cellar, withdraw2, withdraw2, deadline1);

        shareBalance2 = cellar.balanceOf(address(this));

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

    function testBadDeadline(uint256 assets) external {
        // test revert in all functions
        assets = bound(assets, 1e6, 100_000e6);

        // deal USDC assets to test contract
        deal(address(USDC), address(this), assets);
        deposit1 = assets / 2;
        minShares1 = deposit1;
        deadline1 = uint64(block.timestamp + 1 days);
        skip(2 days);
        mockUsdcUsd.setMockUpdatedAt(block.timestamp);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(SimpleSlippageRouter.SimpleSlippageRouter__ExpiredDeadline.selector, deadline1)
            )
        );
        simpleSlippageRouter.deposit(cellar, deposit1, minShares1, deadline1);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(SimpleSlippageRouter.SimpleSlippageRouter__ExpiredDeadline.selector, deadline1)
            )
        );
        simpleSlippageRouter.withdraw(cellar, deposit1, minShares1, deadline1);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(SimpleSlippageRouter.SimpleSlippageRouter__ExpiredDeadline.selector, deadline1)
            )
        );
        simpleSlippageRouter.mint(cellar, minShares1, deposit1, deadline1);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(SimpleSlippageRouter.SimpleSlippageRouter__ExpiredDeadline.selector, deadline1)
            )
        );
        simpleSlippageRouter.redeem(cellar, minShares1, deposit1, deadline1);
    }

    function testDepositMinimumSharesUnmet(uint256 assets) external {
        // test revert in deposit()
        assets = bound(assets, 1e6, 100_000e6);

        // deal USDC assets to test contract
        deal(address(USDC), address(this), assets);
        deposit1 = assets;
        minShares1 = assets + 1; // input param so it will revert
        deadline1 = uint64(block.timestamp + 1 days);

        uint256 quoteShares = cellar.previewDeposit(assets);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    SimpleSlippageRouter.SimpleSlippageRouter__DepositMinimumSharesUnmet.selector,
                    minShares1,
                    quoteShares
                )
            )
        );
        simpleSlippageRouter.deposit(cellar, deposit1, minShares1, deadline1);

        // manipulate back so the deposit should resolve.
        minShares1 = assets;
        simpleSlippageRouter.deposit(cellar, deposit1, minShares1, deadline1);
    }

    function testWithdrawMaxSharesSurpassed(uint256 assets) external {
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
        cellar.approve(address(simpleSlippageRouter), withdraw1);

        uint256 quoteShares = cellar.previewWithdraw(withdraw1);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    SimpleSlippageRouter.SimpleSlippageRouter__WithdrawMaxSharesSurpassed.selector,
                    maxShares1 - 1,
                    quoteShares
                )
            )
        );
        simpleSlippageRouter.withdraw(cellar, withdraw1, maxShares1 - 1, deadline1);

        // Use a value for maxShare that will pass the conditional logic
        simpleSlippageRouter.withdraw(cellar, withdraw1, maxShares1, deadline1);
    }

    function testMintMaxAssetsRqdSurpassed(uint256 assets) external {
        // test revert in mint()
        assets = bound(assets, 1e6, 100_000e6);

        // deal USDC assets to test contract
        deal(address(USDC), address(this), assets);
        deposit1 = assets / 2;
        minShares1 = deposit1;
        deadline1 = uint64(block.timestamp + 1 days);

        // manipulate cellar to have lots of USDC and thus not a 1:1 ratio anymore for shares
        uint256 originalBalance = USDC.balanceOf(address(cellar));
        deal(address(USDC), address(cellar), assets * 10);
        uint256 quotedAssetAmount = cellar.previewMint(minShares1);

        // mint with half of the assets using the SSR
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    SimpleSlippageRouter.SimpleSlippageRouter__MintMaxAssetsRqdSurpassed.selector,
                    minShares1,
                    deposit1,
                    quotedAssetAmount
                )
            )
        );
        simpleSlippageRouter.mint(cellar, minShares1, deposit1, deadline1);

        // manipulate back so the mint should resolve.
        deal(address(USDC), address(cellar), originalBalance);
        simpleSlippageRouter.mint(cellar, minShares1, deposit1, deadline1);
    }

    function testRedeemMinAssetsUnmet(uint256 assets) external {
        // test revert in redeem()
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

        cellar.approve(address(simpleSlippageRouter), withdraw1);
        uint256 quotedAssetAmount = cellar.previewRedeem(maxShares1);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    SimpleSlippageRouter.SimpleSlippageRouter__RedeemMinAssetsUnmet.selector,
                    maxShares1,
                    withdraw1 + 1,
                    quotedAssetAmount
                )
            )
        );
        simpleSlippageRouter.redeem(cellar, maxShares1, withdraw1 + 1, deadline1);

        // Use a value for withdraw1 that will pass the conditional logic.
        simpleSlippageRouter.redeem(cellar, maxShares1, withdraw1, deadline1);
    }
}
