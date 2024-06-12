// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport} from
    "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport.sol";
import {IChainlinkAggregator} from "src/interfaces/external/IChainlinkAggregator.sol";
import {Cellar, Registry} from "src/base/Cellar.sol";
import {ERC4626Adaptor} from "src/modules/adaptors/ERC4626Adaptor.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import {AdaptorHelperFunctions} from "test/resources/AdaptorHelperFunctions.sol";

contract GearBoxCellarTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport private cellar;
    address dWETHV3 = 0xda0002859B2d05F66a753d8241fCDE8623f26F4f;
    ERC4626Adaptor private erc4626Adaptor;
    uint32 private wethPosition = 1;

    uint256 private initialAssets;
    uint256 private initialShares;

    address registryOwner;
    address cellarOwner;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19520757;
        _startFork(rpcKey, blockNumber);
        // Run Starter setUp code.
        _setUp();

        cellar = CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport(
            payable(0xeA1A6307D9b18F8d1cbf1c3Dd6aad8416C06a221)
        );

        erc4626Adaptor = new ERC4626Adaptor();

        registry = cellar.registry();

        registryOwner = registry.owner();
        cellarOwner = cellar.owner();

        vm.startPrank(registryOwner);
        registry.trustAdaptor(address(erc4626Adaptor));
        registry.trustPosition(77_777_777, address(erc4626Adaptor), abi.encode(dWETHV3));
        vm.stopPrank();

        vm.label(multisig, "multisig");
        vm.label(strategist, "strategist");
        // Approve cellar to spend all assets.
        initialAssets = cellar.totalAssets();
        initialShares = cellar.totalSupply();
    }

    function testIntegration(uint256 assets) external {
        assets = bound(assets, 0.1e18, 10_000e18);
        // Add adaptor and position to catalogue, and to cellar
        vm.startPrank(cellarOwner);
        cellar.addAdaptorToCatalogue(address(erc4626Adaptor));
        cellar.addPositionToCatalogue(77_777_777);
        cellar.addPosition(0, 77_777_777, abi.encode(false), false);
        vm.stopPrank();

        // Deal some WETH to vault, and record totalAssets.
        deal(address(WETH), address(cellar), assets);
        uint256 totalAssetsBefore = cellar.totalAssets();
        uint256 totalAssetsWithdrawableBefore = cellar.totalAssetsWithdrawable();

        // Rebalance into GearBox position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToDepositToERC4626Vault(dWETHV3, assets);

        data[0] = Cellar.AdaptorCall({adaptor: address(erc4626Adaptor), callData: adaptorCalls});
        vm.startPrank(cellarOwner);
        cellar.callOnAdaptor(data);
        vm.stopPrank();

        uint256 totalAssetsAfter = cellar.totalAssets();
        uint256 totalAssetsWithdrawableAfter = cellar.totalAssetsWithdrawable();

        assertApproxEqAbs(totalAssetsBefore, totalAssetsAfter, 2, "totalAssets should be unchanged");
        assertEq(
            totalAssetsWithdrawableBefore, totalAssetsWithdrawableAfter, "totalAssetsWithdrawable should be unchanged"
        );

        // Rebalance out of GearBox position.
        data = new Cellar.AdaptorCall[](1);
        adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToWithdrawFromERC4626Vault(dWETHV3, type(uint256).max);

        data[0] = Cellar.AdaptorCall({adaptor: address(erc4626Adaptor), callData: adaptorCalls});
        vm.startPrank(cellarOwner);
        cellar.callOnAdaptor(data);
        vm.stopPrank();

        totalAssetsAfter = cellar.totalAssets();
        totalAssetsWithdrawableAfter = cellar.totalAssetsWithdrawable();
        assertApproxEqAbs(totalAssetsBefore, totalAssetsAfter, 2, "totalAssets should be unchanged");
        assertEq(
            totalAssetsWithdrawableBefore, totalAssetsWithdrawableAfter, "totalAssetsWithdrawable should be unchanged"
        );
    }
}
