// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Deployer } from "src/Deployer.sol";
import { CellarWithOracle } from "src/base/permutations/CellarWithOracle.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

// Will test the swapping and cellar position management using adaptors
contract UsingVestingForGhoTest is MainnetStarterTest, AdaptorHelperFunctions {
    CellarWithOracle public turboGHO = CellarWithOracle(0x0C190DEd9Be5f512Bd72827bdaD4003e9Cc7975C);
    VestingSimple public ghoVestor;
    VestingSimpleAdaptor public vestingAdaptor;
    MockDataFeed private usdcMockFeed;
    MockDataFeed private ghoMockFeed;

    uint32 vestingPositionId = 1_000_000_000;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 18215771;
        _startFork(rpcKey, blockNumber);

        usdcMockFeed = new MockDataFeed(USDC_USD_FEED);
        ghoMockFeed = new MockDataFeed(GHO_USD_FEED);

        // Have this contract deposit into Cellar.
        uint256 usdcAssets = 1_000e6;
        deal(address(USDC), address(this), usdcAssets);
        USDC.approve(address(turboGHO), usdcAssets);
        turboGHO.deposit(usdcAssets, address(this));

        priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

        vm.startPrank(multisig);
        // Update the pricefeeds in the price router.
        PriceRouter.AssetSettings memory settingsUsdc = PriceRouter.AssetSettings(
            CHAINLINK_DERIVATIVE,
            address(address(usdcMockFeed))
        );
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        priceRouter.startEditAsset(USDC, settingsUsdc, abi.encode(stor));

        PriceRouter.AssetSettings memory settingsGho = PriceRouter.AssetSettings(
            CHAINLINK_DERIVATIVE,
            address(address(ghoMockFeed))
        );
        priceRouter.startEditAsset(GHO, settingsGho, abi.encode(stor));

        skip(7 days);

        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        ghoMockFeed.setMockUpdatedAt(block.timestamp);

        priceRouter.completeEditAsset(USDC, settingsUsdc, abi.encode(stor), 1e8);
        priceRouter.completeEditAsset(GHO, settingsGho, abi.encode(stor), 0.98e8);

        vm.stopPrank();

        registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);

        ghoVestor = new VestingSimple(GHO, 7 days, 1e18);

        vestingAdaptor = new VestingSimpleAdaptor();
    }

    function testUsingVestingPosition() external {
        // Add vesting position to registry first.
        vm.startPrank(multisig);
        registry.trustAdaptor(address(vestingAdaptor));
        registry.trustPosition(vestingPositionId, address(vestingAdaptor), abi.encode(ghoVestor));
        vm.stopPrank();

        // Add vesting position to cellar.
        vm.startPrank(gravityBridgeAddress);
        turboGHO.addAdaptorToCatalogue(address(vestingAdaptor));
        turboGHO.addPositionToCatalogue(vestingPositionId);
        turboGHO.addPosition(0, vestingPositionId, abi.encode(0), false);
        vm.stopPrank();

        address ghoMultisig = vm.addr(555);
        uint256 ghoAssets = 1_000e18;
        deal(address(GHO), ghoMultisig, ghoAssets);

        // GHO multisig gives the cellar a GHO vest.
        vm.startPrank(ghoMultisig);
        GHO.approve(address(ghoVestor), ghoAssets);
        ghoVestor.deposit(ghoAssets, address(turboGHO));
        vm.stopPrank();

        skip(1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        ghoMockFeed.setMockUpdatedAt(block.timestamp);

        deal(address(GHO), address(turboGHO), 0);

        // Make sure strategist can claim GHO.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                VestingSimpleAdaptor.withdrawAllFromVesting.selector,
                address(ghoVestor)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        }
        vm.startPrank(gravityBridgeAddress);
        turboGHO.callOnAdaptor(data);
        vm.stopPrank();

        assertGt(GHO.balanceOf(address(turboGHO)), 0, "Cellar should have GHO in it.");

        skip(1 days);
        usdcMockFeed.setMockUpdatedAt(block.timestamp);
        ghoMockFeed.setMockUpdatedAt(block.timestamp);

        deal(address(GHO), address(turboGHO), 0);

        // Make sure strategist can claim GHO.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                VestingSimpleAdaptor.withdrawAllFromVesting.selector,
                address(ghoVestor)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        }
        vm.startPrank(gravityBridgeAddress);
        turboGHO.callOnAdaptor(data);
        vm.stopPrank();

        assertGt(GHO.balanceOf(address(turboGHO)), 0, "Cellar should have GHO in it.");

        // Make multiple vests.
        deal(address(GHO), ghoMultisig, ghoAssets);

        // GHO multisig gives the cellar a GHO vest.
        vm.startPrank(ghoMultisig);
        GHO.approve(address(ghoVestor), ghoAssets);
        ghoVestor.deposit(ghoAssets, address(turboGHO));
        vm.stopPrank();

        skip(1 days);

        deal(address(GHO), ghoMultisig, ghoAssets);

        // GHO multisig gives the cellar a GHO vest.
        vm.startPrank(ghoMultisig);
        GHO.approve(address(ghoVestor), ghoAssets);
        ghoVestor.deposit(ghoAssets, address(turboGHO));
        vm.stopPrank();

        skip(1 days);

        deal(address(GHO), ghoMultisig, ghoAssets);

        // GHO multisig gives the cellar a GHO vest.
        vm.startPrank(ghoMultisig);
        GHO.approve(address(ghoVestor), ghoAssets);
        ghoVestor.deposit(ghoAssets, address(turboGHO));
        vm.stopPrank();

        skip(7 days);

        // Need to make the oracle safe to use.
        ERC4626SharePriceOracle oracle = turboGHO.sharePriceOracle();
        for (uint256 i; i < 4; ++i) {
            skip(1 days);
            usdcMockFeed.setMockUpdatedAt(block.timestamp);
            ghoMockFeed.setMockUpdatedAt(block.timestamp);
            (, bytes memory performData) = oracle.checkUpkeep(abi.encode(0));
            vm.prank(oracle.automationRegistry());
            oracle.performUpkeep(performData);
        }
        (, , bool isNotSafeToUse) = oracle.getLatest();
        assertTrue(!isNotSafeToUse, "Oracle should be safe to use.");

        // Make sure user withdraws work.
        uint256 sharesToRedeem = turboGHO.maxRedeem(address(this));
        turboGHO.redeem(sharesToRedeem, address(this), address(this));

        assertGt(GHO.balanceOf(address(this)), 1_000e18, "User should have received more than 1,000 GHO.");

        deal(address(GHO), address(turboGHO), 0);

        // Make sure strategist can claim GHO.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = abi.encodeWithSelector(
                VestingSimpleAdaptor.withdrawAllFromVesting.selector,
                address(ghoVestor)
            );
            data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        }
        vm.startPrank(gravityBridgeAddress);
        turboGHO.callOnAdaptor(data);
        vm.stopPrank();

        assertGt(GHO.balanceOf(address(turboGHO)), 0, "Cellar should have GHO in it.");
    }
}
