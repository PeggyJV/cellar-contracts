// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface ICurveFi {
    function get_virtual_price() external view returns (uint256);

    function add_liquidity(
        // EURt
        uint256[2] calldata amounts,
        uint256 min_mint_amount
    ) external payable;

    function add_liquidity(
        // Compound, sAave
        uint256[2] calldata amounts,
        uint256 min_mint_amount,
        bool _use_underlying
    ) external payable returns (uint256);

    function add_liquidity(
        // Iron Bank, Aave
        uint256[3] calldata amounts,
        uint256 min_mint_amount,
        bool _use_underlying
    ) external payable returns (uint256);

    function add_liquidity(
        // 3Crv Metapools
        address pool,
        uint256[4] calldata amounts,
        uint256 min_mint_amount
    ) external;

    function add_liquidity(
        // Y and yBUSD
        uint256[4] calldata amounts,
        uint256 min_mint_amount,
        bool _use_underlying
    ) external payable returns (uint256);

    function add_liquidity(
        // 3pool
        uint256[3] calldata amounts,
        uint256 min_mint_amount
    ) external payable;

    function add_liquidity(
        // sUSD
        uint256[4] calldata amounts,
        uint256 min_mint_amount
    ) external payable;

    function remove_liquidity_imbalance(uint256[2] calldata amounts, uint256 max_burn_amount) external;

    function remove_liquidity(uint256 _amount, uint256[2] calldata amounts) external;

    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_amount) external;

    function exchange(
        // CRV-ETH and CVX-ETH
        uint256 from,
        uint256 to,
        uint256 _from_amount,
        uint256 _min_to_amount,
        bool use_eth
    ) external;

    function exchange(
        // sETH
        int128 from,
        int128 to,
        uint256 _from_amount,
        uint256 _min_to_amount
    ) external payable returns (uint256);

    function balances(uint256) external view returns (uint256);

    function price_oracle() external view returns (uint256);

    function get_dy(int128 from, int128 to, uint256 _from_amount) external view returns (uint256);

    // EURt
    function calc_token_amount(uint256[2] calldata _amounts, bool _is_deposit) external view returns (uint256);

    // 3Crv Metapools
    function calc_token_amount(
        address _pool,
        uint256[4] calldata _amounts,
        bool _is_deposit
    ) external view returns (uint256);

    // sUSD, Y pool, etc
    function calc_token_amount(uint256[4] calldata _amounts, bool _is_deposit) external view returns (uint256);

    // 3pool, Iron Bank, etc
    function calc_token_amount(uint256[3] calldata _amounts, bool _is_deposit) external view returns (uint256);

    function calc_withdraw_one_coin(uint256 amount, int128 i) external view returns (uint256);
}
