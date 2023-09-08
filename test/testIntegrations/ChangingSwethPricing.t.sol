// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Deployer } from "src/Deployer.sol";
import { Cellar } from "src/base/Cellar.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

// Will test the swapping and cellar position management using adaptors
contract ChangingSwethPricingTest is MainnetStarterTest, AdaptorHelperFunctions {
    Cellar public turboSweth = Cellar(0xd33dAd974b938744dAC81fE00ac67cb5AA13958E);

    address public SWETH_ETH_100 = 0xcBDF4d702e7dCda5dfCA05Dacd24f203CFD7Ef84;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18092686;
        _startFork(rpcKey, blockNumber);

        priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);
    }

    function testChangingSwethPricing() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(2, SWETH_ETH_100);
        bytes
            memory stor = hex"0000000000000000000000000000000000000000000000000000000000002a3000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000012000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

        uint256 oldTotalAssets = turboSweth.totalAssets();
        uint256 oldPrice = priceRouter.getPriceInUSD(SWETH);
        // Go back in time 1 week.
        vm.warp(block.timestamp - 7 days);
        vm.startPrank(multisig);
        priceRouter.startEditAsset(SWETH, settings, stor);
        vm.stopPrank();

        // Advance time 1 week.
        vm.warp(block.timestamp + 7 days);
        vm.startPrank(multisig);
        priceRouter.completeEditAsset(SWETH, settings, stor, 1_665e8);
        vm.stopPrank();

        uint256 newPrice = priceRouter.getPriceInUSD(SWETH);
        uint256 newTotalAssets = turboSweth.totalAssets();

        assertApproxEqRel(newPrice, oldPrice, 0.003e18, "Redstone Price and Uniswap TWAP should be about the same.");
        assertApproxEqRel(newTotalAssets, oldTotalAssets, 0.003e18, "totalAssets should be about the same.");
    }
}
