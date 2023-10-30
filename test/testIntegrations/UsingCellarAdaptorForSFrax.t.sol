// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC4626 } from "src/base/Cellar.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

// Will test the swapping and cellar position management using adaptors
contract UsingCellarAdaptorForSFraxTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;

    MockDataFeed private fraxMockFeed;

    Cellar public cellar;
    CellarAdaptor public cellarAdaptor;

    uint32 fraxPosition = 1;
    uint32 sFraxPosition = 2;

    uint256 originalTotalAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18406923;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        fraxMockFeed = new MockDataFeed(FRAX_USD_FEED);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(address(fraxMockFeed)).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(fraxMockFeed));
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        cellarAdaptor = new CellarAdaptor();

        registry.trustAdaptor(address(cellarAdaptor));

        registry.trustPosition(fraxPosition, address(erc20Adaptor), abi.encode(FRAX));
        registry.trustPosition(sFraxPosition, address(cellarAdaptor), abi.encode(sFRAX));

        bytes memory creationCode = type(Cellar).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(this),
            registry,
            FRAX,
            "Test sFRAX Cellar",
            "TSFC",
            fraxPosition,
            abi.encode(0),
            1e18,
            0.8e18,
            type(uint192).max
        );
        cellar = Cellar(deployer.getAddress("Test Cellar"));
        FRAX.safeApprove(address(cellar), 1e18);
        deal(address(FRAX), address(this), 1e18);
        deployer.deployContract("Test Cellar", creationCode, constructorArgs, 0);

        cellar.addAdaptorToCatalogue(address(cellarAdaptor));
        cellar.addPositionToCatalogue(sFraxPosition);
        cellar.addPosition(0, sFraxPosition, abi.encode(true), false);

        originalTotalAssets = cellar.totalAssets();
    }

    function testSFraxUse(uint256 assets) external {
        assets = bound(assets, 1e18, 1_000_000_000e18);

        // User deposits.
        deal(address(FRAX), address(this), assets);
        FRAX.safeApprove(address(cellar), assets);
        cellar.deposit(assets, address(this));

        // Strategist moves assets into sFrax, and makes sFrax the holding position.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToCellar(address(sFRAX), assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }
        cellar.setHoldingPosition(sFraxPosition);

        // Check that we deposited into sFRAX.
        uint256 cellarsFraxWorth = ERC4626(sFRAX).maxWithdraw(address(cellar));
        assertApproxEqAbs(cellarsFraxWorth, assets, 1, "Should have deposited assets into sFRAX.");

        skip(100 days);
        fraxMockFeed.setMockUpdatedAt(block.timestamp);

        assertGt(
            cellar.totalAssets(),
            originalTotalAssets + assets,
            "Cellar totalAssets should have increased from sFRAX yield."
        );

        // Have user withdraw to make sure we can withdraw from sFRAX.
        uint256 maxWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(maxWithdraw, address(this), address(this));

        assertEq(FRAX.balanceOf(address(this)), maxWithdraw, "Assets withdrawn should equal expected.");

        // Make sure we pulled from sFRAX.
        uint256 newCellarsFraxWorth = ERC4626(sFRAX).maxWithdraw(address(cellar));
        assertLt(newCellarsFraxWorth, cellarsFraxWorth, "Should have pulled assets from sFRAX.");

        // Make sure users deposit go into sFRAX.
        FRAX.safeApprove(address(cellar), assets);
        cellar.deposit(assets, address(this));

        uint256 expectedAssets = newCellarsFraxWorth + assets;
        cellarsFraxWorth = ERC4626(sFRAX).maxWithdraw(address(cellar));
        assertApproxEqAbs(cellarsFraxWorth, expectedAssets, 1, "Should have deposited assets into sFRAX.");

        // Make sure strategist can rebalance assets out of sFRAX.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromCellar(sFRAX, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        assertEq(0, ERC20(sFRAX).balanceOf(address(cellar)), "Should have withdrawn all assets from sFRAX.");
    }
}
