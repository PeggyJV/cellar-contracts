// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface CurvePool {
    function price_oracle() external view returns (uint256);

    function price_oracle(uint256 k) external view returns (uint256);

    function stored_rates() external view returns (uint256[2] memory);

    function coins(uint256 i) external view returns (address);

    function remove_liquidity_one_coin(uint256 token_amount, int128 i, uint256 min_amount) external;

    function remove_liquidity(uint256 token_amount, uint256[2] memory min_amounts) external;

    function lp_price() external view returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function claim_admin_fees() external;

    function withdraw_admin_fees() external;

    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
}
