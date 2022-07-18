// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { LendingAdaptor } from "src/modules/lending/LendingAdaptor.sol";
import { IPool } from "@aave/interfaces/IPool.sol";

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

    IPool private pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    function setUp() external {
        adaptor = new LendingAdaptor();

        // Mint enough liquidity to swap router for swaps.
        deal(address(USDC), address(adaptor), type(uint224).max);
    }

    function testAaveDeposit() external {
        uint8[] memory functionsToCall;
        bytes[] memory callData;
        ERC20[] memory tokens;
        uint256[] memory amounts;
        functionsToCall = new uint8[](1);
        callData = new bytes[](1);
        tokens = new ERC20[](1);
        amounts = new uint256[](1);

        functionsToCall[0] = 1;
        tokens[0] = USDC;
        amounts[0] = 100e6;
        callData[0] = abi.encode(tokens, amounts);

        adaptor.routeCalls(functionsToCall, callData);
        assertEq(amounts[0] - 1, aUSDC.balanceOf(address(adaptor)));
    }

    function testAaveBorrow() external {
        uint8[] memory functionsToCall;
        bytes[] memory callData;
        ERC20[] memory tokens;
        uint256[] memory amounts;
        functionsToCall = new uint8[](2);
        callData = new bytes[](2);
        tokens = new ERC20[](1);
        amounts = new uint256[](1);

        functionsToCall[0] = 1;
        tokens[0] = USDC;
        amounts[0] = 10000e6;
        callData[0] = abi.encode(tokens, amounts);

        functionsToCall[1] = 2;
        tokens[0] = WETH;
        amounts[0] = 1e18;
        callData[1] = abi.encode(tokens, amounts);

        adaptor.routeCalls(functionsToCall, callData);
        assertEq(amounts[0], dWETH.balanceOf(address(adaptor)));
    }

    function testAaveRepay() external {
        uint8[] memory functionsToCall;
        bytes[] memory callData;
        ERC20[] memory tokens;
        uint256[] memory amounts;
        functionsToCall = new uint8[](3);
        callData = new bytes[](3);
        tokens = new ERC20[](1);
        amounts = new uint256[](1);

        functionsToCall[0] = 1;
        tokens[0] = USDC;
        amounts[0] = 10000e6;
        callData[0] = abi.encode(tokens, amounts);

        functionsToCall[1] = 2;
        tokens[0] = WETH;
        amounts[0] = 1e18;
        callData[1] = abi.encode(tokens, amounts);

        functionsToCall[1] = 3;
        tokens[0] = WETH;
        amounts[0] = 1e18;
        callData[1] = abi.encode(tokens, amounts);

        adaptor.routeCalls(functionsToCall, callData);
        assertEq(0, dWETH.balanceOf(address(adaptor)));
    }
}
