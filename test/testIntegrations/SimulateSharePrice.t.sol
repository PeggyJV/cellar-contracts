// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import "@uniswapV3C/libraries/FixedPoint128.sol";
import "@uniswapV3C/libraries/FullMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { WstEthExtension } from "./tmp.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

interface OldPriceRouter {
    struct AssetSettings {
        uint8 derivative;
        address source;
    }

    struct ChainlinkDerivativeStorage {
        uint144 max;
        uint80 min;
        uint24 heartbeat;
        bool inETH;
    }

    function addAsset(
        ERC20 _asset,
        AssetSettings memory _settings,
        bytes memory _storage,
        uint256 _expectedAnswer
    ) external;
}

// Will test the swapping and cellar position management using adaptors
contract SimulateSharePriceTest is MainnetStarterTest, AdaptorHelperFunctions, ERC721Holder {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    address[] public cellars;
    MockDataFeed public mockStethFeed;

    OldPriceRouter public oldPriceRouter;

    WstEthExtension public extension;

    Cellar public rye;

    address priceRouterOwner = 0xaDa78a5E01325B91Bc7879a63c309F7D54d42950;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17815194;
        _startFork(rpcKey, blockNumber);

        mockStethFeed = new MockDataFeed(STETH_ETH_FEED);
        extension = new WstEthExtension(address(mockStethFeed));

        rye = Cellar(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);

        registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
        oldPriceRouter = OldPriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);

        OldPriceRouter.AssetSettings memory settings;
        settings.derivative = 1;
        settings.source = address(extension);

        OldPriceRouter.ChainlinkDerivativeStorage memory stor;
        stor.inETH = true;

        vm.prank(priceRouterOwner);
        oldPriceRouter.addAsset(WSTETH, settings, abi.encode(stor), 2_106e8);
    }

    function testUpdatingPriceRouter() external {
        console.log("RYE share price", rye.previewRedeem(1e18));

        mockStethFeed.setMockAnswer(0.9995772525317685e18);
        console.log("RYE share price", rye.previewRedeem(1e18));
    }
}
