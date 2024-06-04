// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SwellSimpleStakingAdaptor} from "src/modules/adaptors/Staking/SwellSimpleStakingAdaptor.sol";
import {SimpleStakingERC20 as SwellSimpleStaking} from "src/interfaces/external/SwellSimpleStaking.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import {AdaptorHelperFunctions} from "test/resources/AdaptorHelperFunctions.sol";

contract SwellSimpleStakingAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    // LiquidV1
    Cellar private cellar = Cellar(0xeA1A6307D9b18F8d1cbf1c3Dd6aad8416C06a221);

    SwellSimpleStakingAdaptor private swellSimpleStakingAdaptor;

    address private cellarOwner;
    address private registryOwner;

    uint32 private ptEEthSwellPosition = 1_000_001;
    uint32 private weEthSwellPosition = 1_000_002;

    uint256 initialAssets;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19969336;
        _startFork(rpcKey, blockNumber);

        swellSimpleStakingAdaptor = new SwellSimpleStakingAdaptor(swellSimpleStaking);

        registry = Registry(0x37912f4c0F0d916890eBD755BF6d1f0A0e059BbD);
        priceRouter = PriceRouter(cellar.priceRouter());
        cellarOwner = cellar.owner();
        registryOwner = registry.owner();

        vm.startPrank(registryOwner);
        registry.trustAdaptor(address(swellSimpleStakingAdaptor));
        registry.trustPosition(ptEEthSwellPosition, address(swellSimpleStakingAdaptor), abi.encode(pendleEethPt));
        registry.trustPosition(weEthSwellPosition, address(swellSimpleStakingAdaptor), abi.encode(WEETH));
        vm.stopPrank();

        vm.startPrank(cellarOwner);
        cellar.addAdaptorToCatalogue(address(swellSimpleStakingAdaptor));
        cellar.addPositionToCatalogue(ptEEthSwellPosition);
        cellar.addPositionToCatalogue(weEthSwellPosition);
        vm.stopPrank();

        initialAssets = cellar.totalAssets();
    }

    function testLogic() external {
        // Add both positions to the cellar, making the pt eETH one illiquid, but the weETH one liquid.
        vm.startPrank(cellarOwner);
        cellar.addPosition(0, ptEEthSwellPosition, abi.encode(false), false);
        cellar.addPosition(0, weEthSwellPosition, abi.encode(true), false);
        vm.stopPrank();

        uint256 ptEthInCellar = ERC20(pendleEethPt).balanceOf(address(cellar));
        uint256 weETHInCellar = WEETH.balanceOf(address(cellar));

        // Move 100 eETH and 100 weETH into Swell Simple Staking.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] =
            abi.encodeWithSelector(SwellSimpleStakingAdaptor.depositIntoSimpleStaking.selector, pendleEethPt, 100e18);
        adaptorCalls[1] =
            abi.encodeWithSelector(SwellSimpleStakingAdaptor.depositIntoSimpleStaking.selector, WEETH, 100e18);

        data[0] = Cellar.AdaptorCall({adaptor: address(swellSimpleStakingAdaptor), callData: adaptorCalls});
        vm.startPrank(cellarOwner);
        cellar.callOnAdaptor(data);
        vm.stopPrank();

        uint256 expectedWithdrawableAssets = priceRouter.getValue(WEETH, 100e18, WETH);

        assertEq(
            cellar.totalAssetsWithdrawable(),
            expectedWithdrawableAssets,
            "Only assets in the weETH Simple Staking position should be withdrawable"
        );

        assertApproxEqAbs(cellar.totalAssets(), initialAssets, 1, "The total assets in the cellar should be unchanged");

        // Use max available to deposit all assets.
        data = new Cellar.AdaptorCall[](1);
        adaptorCalls = new bytes[](2);
        adaptorCalls[0] = abi.encodeWithSelector(
            SwellSimpleStakingAdaptor.depositIntoSimpleStaking.selector, pendleEethPt, type(uint256).max
        );
        adaptorCalls[1] = abi.encodeWithSelector(
            SwellSimpleStakingAdaptor.depositIntoSimpleStaking.selector, WEETH, type(uint256).max
        );

        data[0] = Cellar.AdaptorCall({adaptor: address(swellSimpleStakingAdaptor), callData: adaptorCalls});
        vm.startPrank(cellarOwner);
        cellar.callOnAdaptor(data);
        vm.stopPrank();

        expectedWithdrawableAssets = priceRouter.getValue(WEETH, weETHInCellar, WETH);

        assertEq(
            cellar.totalAssetsWithdrawable(),
            expectedWithdrawableAssets,
            "Only assets in the weETH Simple Staking position should be withdrawable"
        );

        assertApproxEqAbs(cellar.totalAssets(), initialAssets, 1, "The total assets in the cellar should be unchanged");

        // Confirm all were deposited.
        assertEq(ERC20(pendleEethPt).balanceOf(address(cellar)), 0, "Cellar should have no pt eETH.");
        assertEq(WEETH.balanceOf(address(cellar)), 0, "Cellar should have no weETH.");

        address user = vm.addr(1);

        // Have user withdraw and make sure they get weETH.
        deal(address(cellar), user, 100e18, true);

        vm.startPrank(user);
        cellar.redeem(100e18, user, user);
        vm.stopPrank();

        uint256 expectedWeEthToUser = priceRouter.getValue(WETH, cellar.previewRedeem(100e18), WEETH);

        assertApproxEqAbs(WEETH.balanceOf(user), expectedWeEthToUser, 1, "User should have received weETH");

        // Use withdraw to withdraw 100 of each
        data = new Cellar.AdaptorCall[](1);
        adaptorCalls = new bytes[](2);
        adaptorCalls[0] =
            abi.encodeWithSelector(SwellSimpleStakingAdaptor.withdrawFromSimpleStaking.selector, pendleEethPt, 100e18);
        adaptorCalls[1] =
            abi.encodeWithSelector(SwellSimpleStakingAdaptor.withdrawFromSimpleStaking.selector, WEETH, 100e18);

        data[0] = Cellar.AdaptorCall({adaptor: address(swellSimpleStakingAdaptor), callData: adaptorCalls});
        vm.startPrank(cellarOwner);
        cellar.callOnAdaptor(data);
        vm.stopPrank();

        // Confirm 100 was withdrawn
        assertEq(ERC20(pendleEethPt).balanceOf(address(cellar)), 100e18, "Cellar should have 100e18 pt eETH.");
        assertEq(WEETH.balanceOf(address(cellar)), 100e18, "Cellar should have 100e18 weETH.");

        // Use max available to withdraw all assets
        data = new Cellar.AdaptorCall[](1);
        adaptorCalls = new bytes[](2);
        adaptorCalls[0] = abi.encodeWithSelector(
            SwellSimpleStakingAdaptor.withdrawFromSimpleStaking.selector, pendleEethPt, type(uint256).max
        );
        adaptorCalls[1] = abi.encodeWithSelector(
            SwellSimpleStakingAdaptor.withdrawFromSimpleStaking.selector, WEETH, type(uint256).max
        );

        data[0] = Cellar.AdaptorCall({adaptor: address(swellSimpleStakingAdaptor), callData: adaptorCalls});
        vm.startPrank(cellarOwner);
        cellar.callOnAdaptor(data);
        vm.stopPrank();

        // Confirm all assets were withdrawn
        assertEq(ERC20(pendleEethPt).balanceOf(address(cellar)), ptEthInCellar, "Cellar should have starting pt eETH.");
        assertEq(
            WEETH.balanceOf(address(cellar)),
            weETHInCellar - expectedWeEthToUser,
            "Cellar should have starting weETH, minus withdrawn amount"
        );
    }
}
