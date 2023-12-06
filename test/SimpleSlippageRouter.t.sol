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
        mockUsdcUsd.setMockAnswer(1e6);

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
    function testDeposit(uint256 assets) external {
        assets = bound(assets, 1e6, 100_000e6);

        // deal USDC to test contract

        // deposit half using the SSR

        // check that cellar balances are proper (new balance = deposit + initialAssets)

        // the other half using the SSR

        // check that cellar balances are proper (new balance = totalDeposit + initialAssets)
    }

    // test withdrawing using SimpleSlippageRouter
    function testWithdraw() external {
        // deal USDC to test contract
        // deposit half using the SSR
        // withdraw a quarter using the SSR
        // check that cellar balances are proper (new balance = (deposit + initialAssets) - withdraw)
        // withdraw the rest using the SSR
        // check that cellar balances are proper (assets + initialAssets)
    }

    // test minting using SimpleSlippageRouter
    function testMint() external {
        // deal USDC to test contract
        // mint with half of the assets using the SSR
        // check that cellar balances are proper (new balance = assetsUsedInMint + initialAssets)
        // mint using the other half using the SSR
        // check that cellar balances are proper (new balance = totalAssetsUsedInMint + initialAssets)
    }

    // test redeeming using SimpleSlippageRouter
    function testRedeem() external {
        // deal USDC to test contract
        // deposit half using the SSR
        // redeem half of the shares test contract has using the SSR
        // check that cellar balances are proper
        // redeem the rest using the SSR
        // check that cellar balances are proper
    }

    // ========================================= REVERSION TEST =========================================

    function testBadDeadline() external {}

    function testDepositMinimumSharesUnmet() external {}

    function testWithdrawMaxSharesSurpassed() external {}

    function testMintMinimumSharesSurpassed() external {}

    //============================================ Helper Functions ===========================================
}
