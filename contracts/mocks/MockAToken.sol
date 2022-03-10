// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../utils/MathUtils.sol";

contract MockAToken is ERC20 {
    address public underlyingAsset;

    constructor(address _underlyingAsset, string memory _symbol) ERC20(_symbol, _symbol) {
        underlyingAsset = _underlyingAsset;
    }

    /**
     * @dev Mints aTokens to `user`
     * - Only callable by the LendingPool, as extra state updates there need to be managed
     * @param user The address receiving the minted tokens
     * @param amount The amount of tokens getting minted
     * @param index The new liquidity index of the reserve
     * @return `true` if the the previous balance of the user was 0
     */
    function mint(
        address user,
        uint256 amount,
        uint256 index
    ) external returns (bool) {
        uint256 previousBalance = super.balanceOf(user);

        uint256 amountScaled = MathUtils.rayDiv(amount, index);
        require(amountScaled != 0, "CT_INVALID_MINT_AMOUNT");
        _mint(user, amountScaled);

        return previousBalance == 0;
    }

    /**
     * @dev Burns aTokens from `user` and sends the equivalent amount of underlying to `receiverOfUnderlying`
     * - Only callable by the LendingPool, as extra state updates there need to be managed
     * @param user The owner of the aTokens, getting them burned
     * @param receiverOfUnderlying The address that will receive the underlying
     * @param amount The amount being burned
     * @param index The new liquidity index of the reserve
     */
    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 amount,
        uint256 index
    ) external {
        uint256 amountScaled = MathUtils.rayDiv(amount, index);
        require(amountScaled != 0, "CT_INVALID_BURN_AMOUNT");
        _burn(user, amountScaled);

        IERC20(underlyingAsset).transfer(receiverOfUnderlying, amount);
    }
}