// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";
import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { IRYUSDRegistry } from "src/interfaces/IRYUSDRegistry.sol";

interface IRYUSDCellar {
    function totalAssets() external view returns (uint256 assets);
}

/**
 * Intent: Will test migration of RYUSD PriceRouter to PriceRouterV2
 * Steps:
 * 0. Get the totalAssets for the current PriceRouterV1
 * 1. Get the Registry for RYUSD
 * 2. Prank being the Registry owner (timelock)
 * 3. Change the PriceRouter to PriceRouterV2
 * 4. Test totalAssets with new PriceRouterV2
 * 5. Compare against V1 totalAssets. Should be the same.
 * PriceRouterV1: 0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E
 * PriceRouterV1Registry: 0x2Cbd27E034FEE53f79b607430dA7771B22050741
 * PriceRouterV2: 0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92
 */
contract PriceRouterV2WithRYUSDTest is MainnetStarterTest, AdaptorHelperFunctions {
    IRYUSDRegistry RYUSD_REGISTRY = IRYUSDRegistry(ryusdRegistry);
    IRYUSDCellar RYUSD_CELLAR = IRYUSDCellar(ryusdCellar);
    uint256 public constant priceRouterID = 2;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18092686;
        _startFork(rpcKey, blockNumber);
    }

    function testMigrationAndTotalAssets() external {
        uint256 prV1TotalAssets = RYUSD_CELLAR.totalAssets();
        address prV1Check = RYUSD_REGISTRY.getAddress(priceRouterID);
        assertEq(prV1Check, priceRouterV1);

        vm.startPrank(ryusdRegistryOwner);
        RYUSD_REGISTRY.setAddress(2, priceRouterV2);
        address prV2Check = RYUSD_REGISTRY.getAddress(priceRouterID);
        assertEq(prV2Check, priceRouterV2);
        vm.stopPrank();

        uint256 prV2TotalAssets = RYUSD_CELLAR.totalAssets();
        assertEq(prV2TotalAssets, prV1TotalAssets);
    }
}
