// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface CurvePool {
    function price_oracle() external view returns (uint256);

    function price_oracle(uint256 k) external view returns (uint256);

    function coins(uint256 i) external view returns (address);

    function remove_liquidity_one_coin(uint256 token_amount, uint256 i, uint256 min_amount) external;

    function lp_price() external view returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function claim_admin_fees() external;

    function withdraw_admin_fees() external;
}
