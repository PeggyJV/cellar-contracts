// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { NativeAdaptor } from "src/modules/adaptors/NativeAdaptor.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract NativeAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    Cellar private cellar;

    NativeAdaptor private nativeAdaptor;

    uint32 private wethPosition = 1;

    uint256 initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16921343;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        nativeAdaptor = NativeAdaptor(address(WETH));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Setup Cellar:

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));

        string memory cellarName = "Native Cellar V0.0";
        uint256 initialDeposit = 0.01e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, WETH, wethPosition, abi.encode(true), initialDeposit, platformCut);

        cellar.addPositionToCatalogue(wethPosition);

        cellar.setRebalanceDeviation(0.01e18);

        WETH.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
    }

    function testLogic(uint256 assets) external {
        assets = bound(assets, 1e6, 1_000_000e6);

        // Have user deposit into cellar.
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 totalAssets = cellar.totalAssets();
        assertEq(totalAssets, assets + initialAssets, "All assets should be accounted for.");

        // Strategist unwraps WETH for ETH.
    }
}
