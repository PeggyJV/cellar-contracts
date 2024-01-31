// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { NativeAdaptor } from "src/modules/adaptors/NativeAdaptor.sol";
import { CellarWithNativeSupport } from "src/base/permutations/CellarWithNativeSupport.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract NativeAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    CellarWithNativeSupport private cellar;

    NativeAdaptor private nativeAdaptor;

    uint32 private wethPosition = 1;
    uint32 private nativePosition = 2;

    uint256 initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16921343;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        nativeAdaptor = new NativeAdaptor(address(WETH));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Setup Cellar:
        registry.trustAdaptor(address(nativeAdaptor));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(nativePosition, address(nativeAdaptor), hex"");

        string memory cellarName = "Native Cellar V0.0";
        uint256 initialDeposit = 0.01e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellarWithNativeSupport(
            cellarName,
            WETH,
            wethPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );

        cellar.addPositionToCatalogue(nativePosition);
        cellar.addAdaptorToCatalogue(address(nativeAdaptor));

        cellar.addPosition(1, nativePosition, abi.encode(0), false);

        cellar.setRebalanceDeviation(0.01e18);

        WETH.safeApprove(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
    }

    function testLogic(uint256 assets) external {
        assets = bound(assets, 0.0001e18, 1_000_000e18);

        // Have user deposit into cellar.
        deal(address(WETH), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 startingAssets = assets + initialAssets;

        uint256 totalAssets = cellar.totalAssets();
        assertEq(totalAssets, startingAssets, "All assets should be accounted for.");

        // Strategist unwraps WETH for ETH.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToUnwrapNative(type(uint256).max);

        data[0] = Cellar.AdaptorCall({ adaptor: address(nativeAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        totalAssets = cellar.totalAssets();
        assertEq(totalAssets, startingAssets, "All assets should be accounted for.");

        assertEq(address(cellar).balance, startingAssets, "Cellar should have unwrapped all assets into Native.");

        // Strategist wraps ETH for WETH.
        adaptorCalls[0] = _createBytesDataToWrapNative(type(uint256).max);

        data[0] = Cellar.AdaptorCall({ adaptor: address(nativeAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        totalAssets = cellar.totalAssets();
        assertEq(totalAssets, startingAssets, "All assets should be accounted for.");

        assertEq(address(cellar).balance, 0, "Cellar should have wrapped all assets.");
    }

    function _createCellarWithNativeSupport(
        string memory cellarName,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithNativeSupport) {
        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(holdingAsset), address(this), initialDeposit);
        holdingAsset.approve(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithNativeSupport).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            holdingAsset,
            cellarName,
            cellarName,
            holdingPosition,
            holdingPositionConfig,
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        return CellarWithNativeSupport(payable(deployer.deployContract(cellarName, creationCode, constructorArgs, 0)));
    }
}
