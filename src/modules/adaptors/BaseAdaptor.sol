// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC4626, ERC20 } from "src/base/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Registry } from "src/Registry.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { Cellar } from "src/base/Cellar.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @title Base Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 * @dev while testing on forked mainnet, aave deposits would sometimes return 1 less aUSDC, and sometimes return the exact amount of USDC you put in
 * Block where USDC in == aUSDC out 15174148
 * Block where USDC-1 in == aUSDC out 15000000
 */

contract BaseAdaptor {
    Registry public registry;
    using SafeERC20 for ERC20;
    using Math for uint256;

    function deposit(uint256 assets, bytes memory adaptorData) public virtual {}

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData
    ) public virtual {}

    function balanceOf(bytes memory adaptorData) public view virtual returns (uint256) {}

    function withdrawableFrom(bytes memory) public view virtual returns (uint256) {
        return 0;
    }

    function assetOf(bytes memory adaptorData) public view virtual returns (ERC20) {}

    function beforeHook(bytes memory) public view virtual returns (bool) {
        return true;
    }

    function afterHook(bytes memory) public view virtual returns (bool) {
        return true;
    }

    function _maxAvailable(ERC20 token, uint256 amount) internal view virtual returns (uint256) {
        if (amount == type(uint256).max) return token.balanceOf(address(this));
        else return amount;
    }

    function swap(
        ERC20 assetIn,
        ERC20 assetOut,
        uint256 amountIn,
        SwapRouter.Exchange exchange,
        bytes memory params
    ) public returns (uint256 amountOut) {
        // Store the expected amount of the asset in that we expect to have after the swap.
        uint256 expectedAssetsInAfter = assetIn.balanceOf(address(this)) - amountIn;

        // Get the address of the latest swap router.
        SwapRouter swapRouter = SwapRouter(Cellar(address(this)).registry().getAddress(1));

        // Approve swap router to swap assets.
        assetIn.safeApprove(address(swapRouter), amountIn);

        // Perform swap.
        amountOut = swapRouter.swap(exchange, params, address(this), assetIn, assetOut);

        // Check that the amount of assets swapped is what is expected. Will revert if the `params`
        // specified a different amount of assets to swap then `amountIn`.
        require(assetIn.balanceOf(address(this)) == expectedAssetsInAfter, "INCORRECT_PARAMS_AMOUNT");
    }
}
