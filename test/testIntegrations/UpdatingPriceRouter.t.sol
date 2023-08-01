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

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

// Will test the swapping and cellar position management using adaptors
contract UpdatingPriceRouterTest is MainnetStarterTest, AdaptorHelperFunctions, ERC721Holder {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    address[] public cellars;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 17737188;
        _startFork(rpcKey, blockNumber);

        registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
        priceRouter = new PriceRouter(address(this), registry, WETH);

        cellars = new address[](7);
        cellars[0] = 0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec; // RYE
        cellars[1] = 0xDBe19d1c3F21b1bB250ca7BDaE0687A97B5f77e6; // FRAX
        cellars[2] = 0x0274a704a6D9129F90A62dDC6f6024b33EcDad36; // RYBTC
        cellars[3] = 0x4068BDD217a45F8F668EF19F1E3A1f043e4c4934; // RYLINK
        cellars[4] = 0x03df2A53Cbed19B824347D6a45d09016C2D1676a; // DeFi Stars
        cellars[5] = 0x18ea937aba6053bC232d9Ae2C42abE7a8a2Be440; // RYENS
        cellars[6] = 0x6A6AF5393DC23D7e3dB28D28Ef422DB7c40932B6; // RYUNI
    }

    function testUpdatingPriceRouter() external {
        vm.prank(multisig);
        registry.setAddress(2, address(priceRouter));

        for (uint256 i; i < cellars.length; ++i) {
            Cellar cellar = Cellar(cellars[i]);
            ERC20 asset = cellar.asset();
            uint256 amount = 10 ** asset.decimals();
            deal(address(asset), address(this), amount);
            asset.safeApprove(address(cellar), amount);
            cellar.deposit(amount, address(this));
            assertTrue(address(cellar.priceRouter()) != address(priceRouter), "PriceRouters should be different");
        }
    }
}
