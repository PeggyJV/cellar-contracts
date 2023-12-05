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
        mockUsdcUsd.setMockAnswer(1e8);

        // Add adaptors and ERC20 positions to the registry.
        registry.trustAdaptor(address(cellarAdaptor));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));

        // Create Dummy Cellars.
        string memory cellarName = "Dummy Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellarName = "Cellar V0.0";
        initialDeposit = 1e6;
        platformCut = 0.75e18;
        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(0), initialDeposit, platformCut);

        cellar.setStrategistPayoutAddress(strategist);

        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
        initialShares = cellar.totalSupply();
    }

    // ========================================= INITIALIZATION TEST =========================================

    // simpleSlippageRouter should not have any assets, any approvals, etc.
    function testInitialization() external {}

    // ========================================= HAPPY PATH TEST =========================================

    // test depositing using SimpleSlippageRouter
    function testDeposit() external {}

    // test withdrawing using SimpleSlippageRouter
    function testWithdraw() external {}

    // test minting using SimpleSlippageRouter
    function testMint() external {}

    // test redeeming using SimpleSlippageRouter
    function testRedeem() external {}

    // ========================================= REVERSION TEST =========================================

    function testBadDeadline() external {

    }

    function testDepositMinimumSharesUnmet() external {
        
    }

    function testDepositMinimumSharesUnmet() external {
        
    }

    function testDepositMinimumSharesUnmet() external {
        
    }



    //============================================ Helper Functions ===========================================

    function _depositToCellar(Cellar targetFrom, Cellar targetTo, uint256 amountIn) internal {
        ERC20 assetIn = targetFrom.asset();
        ERC20 assetOut = targetTo.asset();

        uint256 amountTo = priceRouter.getValue(assetIn, amountIn, assetOut);

        // Update targetFrom ERC20 balances.
        deal(address(assetIn), address(targetFrom), assetIn.balanceOf(address(targetFrom)) - amountIn);
        deal(address(assetOut), address(targetFrom), assetOut.balanceOf(address(targetFrom)) + amountTo);

        // Rebalance into targetTo.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToCellar(address(targetTo), amountTo);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        targetFrom.callOnAdaptor(data);
    }

    // Used to act like malicious price router under reporting assets.
    function getValuesDelta(
        ERC20[] calldata,
        uint256[] calldata,
        ERC20[] calldata,
        uint256[] calldata,
        ERC20
    ) external pure returns (uint256) {
        return 50e6;
    }
}
