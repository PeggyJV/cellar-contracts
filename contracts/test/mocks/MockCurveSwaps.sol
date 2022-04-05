// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {MathUtils} from "contracts/utils/MathUtils.sol";

contract MockCurveSwaps {
    using MathUtils for uint256;

    function exchange(
        address,
        address _from,
        address _to,
        uint256 _amount,
        uint256 _expected,
        address _receiver
    ) external returns (uint256) {
        uint256 exchangeRate = 9500;

        ERC20(_from).transferFrom(msg.sender, address(this), _amount);

        uint256 amountOut = _amount * exchangeRate / 10000;

        uint8 fromDecimals = ERC20(_from).decimals();
        uint8 toDecimals = ERC20(_to).decimals();
        amountOut = amountOut.changeDecimals(fromDecimals, toDecimals);

        require(amountOut > _expected, "received less than expected");

        ERC20(_to).transfer(_receiver, amountOut);

        return amountOut;
    }
}