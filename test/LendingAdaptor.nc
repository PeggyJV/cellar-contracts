// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { LendingAdaptor } from "src/modules/lending/LendingAdaptor.sol";
import { IPool } from "@aave/interfaces/IPool.sol";
import { IMasterChef } from "src/interfaces/IMasterChef.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract LendingAdaptorTest is Test {
  using SafeTransferLib for ERC20;
  using Math for uint256;

  LendingAdaptor private adaptor;
  ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
  ERC20 private aUSDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
  ERC20 private dWETH = ERC20(0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf);
  ERC20 private CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
  ERC20 private SUSHI = ERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2);

  IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

  IMasterChef chef = IMasterChef(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d); //mainnet sushi chef

  function setUp() external {
    adaptor = new LendingAdaptor();

    // Mint enough liquidity to swap router for swaps.
    deal(address(USDC), address(adaptor), type(uint224).max);
  }

  //============================================ AAVE ============================================
  function testAaveDeposit() external {
    uint8[] memory functionsToCall = new uint8[](1);
    bytes[] memory callData = new bytes[](1);

    functionsToCall[0] = 1;
    ERC20 tokenToDeposit = USDC;
    uint256 amountToDeposit = 100e6;
    callData[0] = abi.encode(tokenToDeposit, amountToDeposit);

    adaptor.routeCalls(functionsToCall, callData);
    assertEq(amountToDeposit, aUSDC.balanceOf(address(adaptor)));
  }

  function testAaveBorrow() external {
    uint8[] memory functionsToCall = new uint8[](2);
    bytes[] memory callData = new bytes[](2);

    functionsToCall[0] = 1;
    ERC20 tokenToDeposit = USDC;
    uint256 amountToDeposit = 10000e6;
    callData[0] = abi.encode(tokenToDeposit, amountToDeposit);

    functionsToCall[1] = 2;
    ERC20 tokenToBorrow = WETH;
    uint256 amountToBorrow = 1e18;
    callData[1] = abi.encode(tokenToBorrow, amountToBorrow);

    adaptor.routeCalls(functionsToCall, callData);
    assertEq(amountToBorrow, dWETH.balanceOf(address(adaptor)));
  }

  function testAaveRepay() external {
    uint8[] memory functionsToCall = new uint8[](3);
    bytes[] memory callData = new bytes[](3);

    functionsToCall[0] = 1;
    ERC20 tokenToDeposit = USDC;
    uint256 amountToDeposit = 10000e6;
    callData[0] = abi.encode(tokenToDeposit, amountToDeposit);

    functionsToCall[1] = 2;
    ERC20 tokenToBorrow = WETH;
    uint256 amountToBorrow = 1e18;
    callData[1] = abi.encode(tokenToBorrow, amountToBorrow);

    functionsToCall[2] = 3;
    ERC20 tokenToRepay = WETH;
    uint256 amountToRepay = 1e18;
    callData[2] = abi.encode(tokenToRepay, amountToRepay);

    adaptor.routeCalls(functionsToCall, callData);
    assertEq(0, dWETH.balanceOf(address(adaptor)));
  }

  function testAaveWithdraw() external {
    uint8[] memory functionsToCall = new uint8[](2);
    bytes[] memory callData = new bytes[](2);

    functionsToCall[0] = 1;
    ERC20 tokenToDeposit = USDC;
    uint256 amountToDeposit = 100e6;
    callData[0] = abi.encode(tokenToDeposit, amountToDeposit);

    functionsToCall[1] = 4;
    ERC20 tokenToWithdraw = USDC;
    uint256 amountToWithdraw = 99999999;
    callData[1] = abi.encode(tokenToWithdraw, amountToWithdraw);

    uint256 adaptorBal = USDC.balanceOf(address(adaptor));
    adaptor.routeCalls(functionsToCall, callData);
    adaptorBal = adaptorBal - USDC.balanceOf(address(adaptor));
    assertEq(1, adaptorBal, "adaptorBal difference should be 1 because Aave rounds down when depositing");
  }

  //============================================ SUSHI ============================================
  function testAddLiquidityAndFarmSushi() external {
    deal(address(WETH), address(adaptor), type(uint224).max);
    deal(address(CVX), address(adaptor), type(uint224).max);

    uint8[] memory functionsToCall = new uint8[](1);
    bytes[] memory callData = new bytes[](1);

    functionsToCall[0] = 5;
    ERC20 tokenA = WETH;
    ERC20 tokenB = CVX;
    uint256 amountA = 1e18;
    uint256 amountB = 200e18;
    uint256 minimumA = 0;
    uint256 minimumB = 0;
    uint256 pid = 1;

    callData[0] = abi.encode(tokenA, tokenB, amountA, amountB, minimumA, minimumB, pid);
    adaptor.routeCalls(functionsToCall, callData);
    IMasterChef.UserInfo memory info = chef.userInfo(1, address(adaptor));
    console.log(info.amount);
  }

  function testHarvestSushiFarms() external {
    deal(address(WETH), address(adaptor), type(uint224).max);
    deal(address(CVX), address(adaptor), type(uint224).max);

    uint8[] memory functionsToCall = new uint8[](1);
    bytes[] memory callData = new bytes[](1);

    functionsToCall[0] = 5;
    ERC20 tokenA = WETH;
    ERC20 tokenB = CVX;
    uint256 amountA = 1e18;
    uint256 amountB = 200e18;
    uint256 minimumA = 0;
    uint256 minimumB = 0;
    uint256 pid = 1;

    callData[0] = abi.encode(tokenA, tokenB, amountA, amountB, minimumA, minimumB, pid);
    adaptor.routeCalls(functionsToCall, callData);

    console.log("Pending Sushi Before Roll: ", chef.pendingSushi(1, address(adaptor)));

    vm.roll(16000000);

    console.log("Pending Sushi After Roll: ", chef.pendingSushi(1, address(adaptor)));

    functionsToCall[0] = 6;

    //reward tokens
    ERC20[] memory rewardTokens = new ERC20[](2);
    bytes memory swapData;
    rewardTokens[0] = SUSHI;
    rewardTokens[1] = ERC20(address(0));

    callData[0] = abi.encode(pid, rewardTokens, swapData);
    adaptor.routeCalls(functionsToCall, callData);

    console.log("Pending Sushi After Harvest: ", chef.pendingSushi(1, address(adaptor)));
    console.log("Adaptor Sushi Balance:", SUSHI.balanceOf(address(adaptor)));
  }

  function testWithdrawFromFarmAndLPSushi() external {
    deal(address(WETH), address(adaptor), type(uint224).max);
    deal(address(CVX), address(adaptor), type(uint224).max);

    uint8[] memory functionsToCall = new uint8[](1);
    bytes[] memory callData = new bytes[](1);

    functionsToCall[0] = 5;
    ERC20 tokenA = WETH;
    ERC20 tokenB = CVX;
    uint256 amountA = 1e18;
    uint256 amountB = 200e18;
    uint256 minimumA = 0;
    uint256 minimumB = 0;
    uint256 pid = 1;

    callData[0] = abi.encode(tokenA, tokenB, amountA, amountB, minimumA, minimumB, pid);
    adaptor.routeCalls(functionsToCall, callData);
    IMasterChef.UserInfo memory info = chef.userInfo(1, address(adaptor));

    functionsToCall[0] = 7;
    tokenA = WETH;
    tokenB = CVX;
    uint256 liquidity = info.amount;
    minimumA = 0;
    minimumB = 0;
    callData[0] = abi.encode(tokenA, tokenB, liquidity, minimumA, minimumB, pid);
    adaptor.routeCalls(functionsToCall, callData);
    info = chef.userInfo(1, address(adaptor));
    assertEq(info.amount, 0, "LP balance should be zero");
  }
}
