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

        // TODO use max available to deposit all assets.

        // Confirm all were deposited.

        // Have user withdraw and make sure they get weETH.

        // Use withdraw to withdraw 100 of each

        // confirm 100 was withdrawn

        // Use max available to withdraw all assets

        // confirm all assets were withdrawn

        // Add part where we stake everything with type uint256 max, then unstaking everyhting
    }
}
