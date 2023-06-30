// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import { FTokenAdaptorV1 } from "src/modules/adaptors/Frax/FTokenAdaptorV1.sol";
import { MockFTokenAdaptor } from "src/mocks/adaptors/MockFTokenAdaptor.sol";
import { MockFTokenAdaptorV1 } from "src/mocks/adaptors/MockFTokenAdaptorV1.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev A lot of FraxLend operations round down, so many tests use `assertApproxEqAbs` with a
 *      2 wei bound to account for this.
 */
contract FraximalTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    FTokenAdaptor private fTokenAdaptorV2 = FTokenAdaptor(0x13C7DA01977E6de1dFa8B135DA34BD569650Acb9);
    FTokenAdaptorV1 private fTokenAdaptorV1 = FTokenAdaptorV1(0x4e4E5610885c6c2c8D9ad92e36945FB7092aADae);
    CellarInitializableV2_2 private fraximal = CellarInitializableV2_2(0xDBe19d1c3F21b1bB250ca7BDaE0687A97B5f77e6);
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 public FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // FraxLend Pairs
    address private FPI_PAIR_v1 = 0x74F82Bd9D0390A4180DaaEc92D64cf0708751759;
    address private FXS_PAIR_v1 = 0xDbe88DBAc39263c47629ebbA02b3eF4cf0752A72;
    address private wBTC_PAIR_v1 = 0x32467a5fc2d72D21E8DCe990906547A2b012f382;
    address private wETH_PAIR_v1 = 0x794F6B13FBd7EB7ef10d1ED205c9a416910207Ff;
    address private gOHM_PAIR_v1 = 0x66bf36dBa79d4606039f04b32946A260BCd3FF52;
    address private Curve_PAIR_v1 = 0x3835a58CA93Cdb5f912519ad366826aC9a752510;
    address private Convex_PAIR_v1 = 0xa1D100a5bf6BFd2736837c97248853D989a9ED84;
    address private AAVE_PAIR_v2 = 0xc779fEE076EB04b9F8EA424ec19DE27Efd17A68d;
    address private Uni_PAIR_v2 = 0xc6CadA314389430d396C7b0C70c6281e99ca7fe8;
    address private MKR_PAIR_v2 = 0x82Ec28636B77661a95f021090F6bE0C8d379DD5D;
    address private APE_PAIR_v2 = 0x3a25B9aB8c07FfEFEe614531C75905E810d8A239;
    address private FRAX_USDC_Curve_LP_PAIR_v2 = 0x1Fff4a418471a7b44EFa023320e02DCDB486ED77;
    address private frxETH_ETH_Curve_LP_PAIR_v2 = 0x281E6CB341a552E4faCCc6b4eEF1A6fCC523682d;
    address private sfrxETH_PAIR_v2 = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15;

    // Chainlink PriceFeeds
    MockDataFeed private mockFraxUsd;
    MockDataFeed private mockWethUsd;
    address private FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    uint32 private fraxPosition;
    uint32 private fxsFraxPairPosition;
    uint32 private fpiFraxPairPosition;
    uint32 private sfrxEthFraxPairPosition;
    uint32 private wEthFraxPairPosition;

    // Positions
    uint32[] private positions = new uint32[](15);
    address[] private fraxLendPairs = new address[](14);

    modifier checkBlockNumber() {
        if (block.number < 17593172) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 17593172.");
            return;
        }
        _;
    }

    function setUp() external {
        positions[0] = 181; // FRAX position
        positions[1] = 167; // FPI_PAIR_v1 position
        positions[2] = 168; // FXS_PAIR_v1 position
        positions[3] = 169; // wBTC_PAIR_v1 position
        positions[4] = 170; // wETH_PAIR_v1 position
        positions[5] = 171; // gOHM_PAIR_v1 position
        positions[6] = 172; // Curve_PAIR_v1 position
        positions[7] = 173; // Convex_PAIR_v1 position
        positions[8] = 174; // AAVE_PAIR_v2 position
        positions[9] = 175; // Uni_PAIR_v2 position
        positions[10] = 176; // MKR_PAIR_v2 position
        positions[11] = 177; // APE_PAIR_v2 position
        positions[12] = 178; // FRAX_USDC_Curve_LP_PAIR_v2 position
        positions[13] = 179; // frxETH_ETH_Curve_LP_PAIR_v2 position
        positions[14] = 180; // sfrxETH_PAIR_v2 position

        fraxLendPairs[0] = 0x74F82Bd9D0390A4180DaaEc92D64cf0708751759;
        fraxLendPairs[1] = 0xDbe88DBAc39263c47629ebbA02b3eF4cf0752A72;
        fraxLendPairs[2] = 0x32467a5fc2d72D21E8DCe990906547A2b012f382;
        fraxLendPairs[3] = 0x794F6B13FBd7EB7ef10d1ED205c9a416910207Ff;
        fraxLendPairs[4] = 0x66bf36dBa79d4606039f04b32946A260BCd3FF52;
        fraxLendPairs[5] = 0x3835a58CA93Cdb5f912519ad366826aC9a752510;
        fraxLendPairs[6] = 0xa1D100a5bf6BFd2736837c97248853D989a9ED84;
        fraxLendPairs[7] = 0xc779fEE076EB04b9F8EA424ec19DE27Efd17A68d;
        fraxLendPairs[8] = 0xc6CadA314389430d396C7b0C70c6281e99ca7fe8;
        fraxLendPairs[9] = 0x82Ec28636B77661a95f021090F6bE0C8d379DD5D;
        fraxLendPairs[10] = 0x3a25B9aB8c07FfEFEe614531C75905E810d8A239;
        fraxLendPairs[11] = 0x1Fff4a418471a7b44EFa023320e02DCDB486ED77;
        fraxLendPairs[12] = 0x281E6CB341a552E4faCCc6b4eEF1A6fCC523682d;
        fraxLendPairs[13] = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15;

        FRAX.approve(address(fraximal), type(uint256).max);
    }

    function testFraximal(uint256 assets) external checkBlockNumber {
        // Add all the FraxLend posiitons.
        vm.startPrank(gravityBridge);
        for (uint256 i = 1; i < positions.length; ++i) fraximal.addPosition(0, positions[i], abi.encode(0), false);
        vm.stopPrank();

        // Account for starting FRASX sitting in the cellar.
        uint256 startingFrax = FRAX.balanceOf(address(fraximal));

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        fraximal.deposit(assets, address(this));

        assets += startingFrax;

        // Strategist rebalances to lend FRAX in all markets.
        uint256 amountToLend = assets / fraxLendPairs.length;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        // Lend FRAX on FraxLend.
        bytes[] memory adaptorCalls0 = new bytes[](7);
        for (uint256 i; i < 7; ++i) adaptorCalls0[i] = _createBytesDataToLend(fraxLendPairs[i], amountToLend);
        data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV1), callData: adaptorCalls0 });
        bytes[] memory adaptorCalls1 = new bytes[](7);
        for (uint256 i = 7; i < 14; ++i) adaptorCalls1[i - 7] = _createBytesDataToLend(fraxLendPairs[i], amountToLend);
        data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls1 });

        // Perform callOnAdaptor.
        vm.prank(gravityBridge);
        fraximal.callOnAdaptor(data);

        assertApproxEqAbs(fraximal.totalAssets(), assets, 30, "Fraximal totalAssets should equal assets in.");
        assertApproxEqAbs(FRAX.balanceOf(address(fraximal)), 0, 30, "Fraximal should have no vanilla FRAX.");

        // Strategist withdraws from ALL FraxLend positions.
        adaptorCalls0 = new bytes[](7);
        for (uint256 i; i < 7; ++i) adaptorCalls0[i] = _createBytesDataToRedeem(fraxLendPairs[i], type(uint256).max);
        data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV1), callData: adaptorCalls0 });
        adaptorCalls1 = new bytes[](7);
        for (uint256 i = 7; i < 14; ++i)
            adaptorCalls1[i - 7] = _createBytesDataToRedeem(fraxLendPairs[i], type(uint256).max);
        data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls1 });

        // Perform callOnAdaptor.
        vm.prank(gravityBridge);
        fraximal.callOnAdaptor(data);

        assertApproxEqAbs(
            fraximal.totalAssets(),
            FRAX.balanceOf(address(fraximal)),
            30,
            "Cellar should have all if its assets in vanilla FRAX."
        );

        assertApproxEqAbs(fraximal.totalAssets(), assets, 30, "Fraximal totalAssets should equal assets in.");

        // Strategist now removes all unused FraxLend positions.
        vm.startPrank(gravityBridge);
        for (uint256 i = 1; i < positions.length; ++i) fraximal.removePosition(0, false);
        vm.stopPrank();
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _createBytesDataToLend(address fToken, uint256 amountToDeposit) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.lendFrax.selector, fToken, amountToDeposit);
    }

    function _createBytesDataToRedeem(address fToken, uint256 amountToRedeem) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.redeemFraxShare.selector, fToken, amountToRedeem);
    }

    function _createBytesDataToWithdraw(address fToken, uint256 amountToWithdraw) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.withdrawFrax.selector, fToken, amountToWithdraw);
    }

    function _createBytesDataToCallAddInterest(address fToken) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.callAddInterest.selector, fToken);
    }
}
