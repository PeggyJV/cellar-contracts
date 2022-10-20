// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Registry } from "src/Registry.sol";
import { Cellar } from "src/base/Cellar.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract DeployedCellarTest is Test {
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private sommMultiSig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private strategist = 0x13FBB7e817e5347ce4ae39c3dff1E6705746DCdC;

    Cellar private cellarTrend;
    Cellar private cellarMomentum;

    function setUp() external {
        cellarTrend = Cellar(0x6E2dAc3b9E9ADc0CbbaE2D0B9Fd81952a8D33872);
        cellarMomentum = Cellar(0xbB9077c49673ac4760E9E6e21f7Ce16aE058029e);
    }

    // function testCellars() external {
    //     _testCellar(cellarTrend);
    //     _testCellar(cellarMomentum);
    // }

    // function _testCellar(Cellar cellar) internal {
    //     assertTrue(gravityBridge == cellar.owner(), "Cellar owner should be Gravity Bridge.");

    //     //  Have user deposit into Cellar
    //     deal(address(USDC), address(this), 100_000e6);
    //     USDC.approve(address(cellar), 100_000e6);
    //     cellar.deposit(100_000e6, address(this));

    //     assertEq(cellar.totalAssets(), 100_000e6, "Total assets should equal 100,000 USDC.");

    //     // Strategist swaps 10,000 USDC for wBTC on UniV3.
    //     vm.startPrank(gravityBridge);
    //     address[] memory path = new address[](2);
    //     path[0] = address(USDC);
    //     path[1] = address(WBTC);
    //     uint24[] memory poolFees = new uint24[](1);
    //     poolFees[0] = 3000; // 0.3% fee
    //     uint256 amount = 10_000e6;
    //     bytes memory params = abi.encode(path, poolFees, amount, 0);
    //     cellar.rebalance(address(USDC), address(WBTC), amount, SwapRouter.Exchange.UNIV3, params);
    //     vm.stopPrank();

    //     // Strategist swaps 10,000 USDC for wBTC on UniV2.
    //     vm.startPrank(gravityBridge);
    //     path = new address[](3);
    //     path[0] = address(USDC);
    //     path[1] = address(WETH);
    //     path[2] = address(WBTC);
    //     amount = 10_000e6;
    //     params = abi.encode(path, amount, 0);
    //     cellar.rebalance(address(USDC), address(WBTC), amount, SwapRouter.Exchange.UNIV2, params);
    //     vm.stopPrank();

    //     assertApproxEqRel(
    //         cellar.totalAssets(),
    //         100_000e6,
    //         0.005e18,
    //         "Total assets should approximately be equal to 100,000 USDC."
    //     );

    //     // Mint cellar some USDC to simulate gains.
    //     deal(address(USDC), address(cellar), 100_000e6);

    //     // Fast forward time by 0.25 days
    //     skip(21600);

    //     // Strategist changes fee share payout address.
    //     vm.startPrank(gravityBridge);
    //     address newPayout = vm.addr(7);
    //     cellar.setStrategistPayoutAddress(newPayout);
    //     vm.stopPrank();

    //     // Call `sendFees` to mint performance/platform fees.
    //     cellar.sendFees();

    //     assertTrue(cellar.balanceOf(newPayout) > 0, "Strategist should have been minted shares for fees.");

    //     vm.roll(block.number + cellar.shareLockPeriod());

    //     // Have user withdraw.
    //     cellar.withdraw(10_000e6, address(this), address(this));
    //     assertGt(USDC.balanceOf(address(this)), 0, "User should have gotten USDC.");
    //     assertEq(WETH.balanceOf(address(this)), 0, "User should have not gotten WETH.");
    //     assertGt(WBTC.balanceOf(address(this)), 0, "User should have gotten WBTC.");

    //     // Zero out users balances.
    //     deal(address(USDC), address(this), 0);
    //     deal(address(WETH), address(this), 0);
    //     deal(address(WBTC), address(this), 0);

    //     vm.prank(gravityBridge);
    //     cellar.setWithdrawType(Cellar.WithdrawType.ORDERLY);

    //     // Have user withdraw.
    //     cellar.withdraw(10_000e6, address(this), address(this));
    //     assertEq(USDC.balanceOf(address(this)), 10_000e6, "User should have gotten 10,000 USDC.");
    //     assertEq(WETH.balanceOf(address(this)), 0, "User should not have gotten any WETH.");
    //     assertEq(WBTC.balanceOf(address(this)), 0, "User should not have gotten any WBTC.");
    // }
}
