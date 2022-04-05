// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {MathUtils} from "contracts/utils/MathUtils.sol";

contract MockCurveSwaps {
    using MathUtils for uint256;

    function exchange_multiple(
        address[9] memory _route,
        uint256[3][4] memory,
        uint256 _amount,
        uint256 _expected
    ) external returns (uint256) {
        address tokenIn = _route[0];

        address tokenOut;
        for (uint256 i; ; i += 2) {
            if (i == 8 || _route[i+1] == address(0)) {
                tokenOut = _route[i];
                break;
            }
        }

        uint256 exchangeRate = 9500;

        ERC20(tokenIn).transferFrom(msg.sender, address(this), _amount);

        uint256 amountOut = _amount * exchangeRate / 10000;

        uint8 fromDecimals = ERC20(tokenIn).decimals();
        uint8 toDecimals = ERC20(tokenOut).decimals();
        amountOut = amountOut.changeDecimals(fromDecimals, toDecimals);

        require(amountOut > _expected, "received less than expected");

        ERC20(tokenOut).transfer(msg.sender, amountOut);

        return amountOut;
    }
}