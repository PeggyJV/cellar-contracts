// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// ICurvePool interface
interface ICurvePool {
    function coins(uint256) external view returns (address);
    function balances(uint256) external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function calc_withdraw_one_coin(uint256 token_amount, int128 i) external view returns (uint256);

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount, address _receiver) external returns (uint256); 
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function remove_liquidity(uint256 _amount, uint256[3] calldata min_amounts) external;
    function remove_liquidity_imbalance(uint256[2] calldata amounts, uint256 max_burn_amount) external; 
    function remove_liquidity_one_coin(uint256 _burn_amount, int128 i, uint256 _min_received, address _receiver) external returns (uint256);
}