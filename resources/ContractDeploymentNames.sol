// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

contract ContractDeploymentNames {
    // Infrastructure
    string public registryName = "Registry V0.0";
    string public priceRouterName = "PriceRouter V0.1";
    string public timelockOwnerName = "Timelock Owner V0.0";
    string public protocolFeeCollectorName = "Protocol Fee Collector V0.0";
    string public feesAndReservesName = "Fees And Reserves V0.0";
    string public withdrawQueueName = "Withdraw Queue V0.0";
    string public simpleSolverName = "Simple Solver V0.0";
    string public atomicQueueName = "Atomic Queue V0.0";
    string public incentiveDistributorName = "Incentive Distributor V0.1";
    // Adaptors
    string public erc20AdaptorName = "ERC20 Adaptor V0.0";
    string public erc4626AdaptorName = "ERC4626 Adaptor V0.0";
    string public oneInchAdaptorName = "1Inch Adaptor V0.0";
    string public zeroXAdaptorName = "0x Adaptor V0.0";
    string public uniswapV3AdaptorName = "Uniswap V3 Adaptor V0.0";
    string public uniswapV3PositionTrackerName = "Uniswap V3 Position Tracker V0.0";
    string public swapWithUniswapAdaptorName = "Swap With Uniswap Adaptor V0.0";
    string public aaveV3ATokenAdaptorName = "Aave V3 AToken Adaptor V0.0";
    string public aaveV3DebtTokenAdaptorName = "Aave V3 Debt Token Adaptor V0.0";
    string public compoundV3SupplyAdaptorName = "Compound V3 Supply Adaptor V 0.0";
    string public compoundV3RewardsAdaptorName = "Compound V3 Rewards Adaptor V 0.0";
    string public feesAndReservesAdaptorName = "Fees And Reserves Adaptor V 0.0";
    string public balancerPoolAdaptorName = "Balancer Pool Adaptor V 0.0";
    // Deploy below only after it has been confirmed that they will work on L2
    string public balancerV2PoolAdaptorName = "Balancer Pool Adaptor V 0.0";
    string public auraAdaptorName = "Aura ERC4626 Adaptor V 0.0";
    string public curveAdaptorName = "Curve Adaptor V 0.0";
    string public convexCurveAdaptorName = "Convex Curve Adaptor V 0.0";

    // Vault Names
    string public realYieldUsdName = "Real Yield USD V0.0";
    string public realYieldEthName = "Real Yield ETH V0.1";
    string public realYieldMaticName = "Real Yield MATIC V0.0";
    string public realYieldAvaxName = "Real Yield AVAX V0.0";
    string public turboRSETHName = "Turbo RSETH V0.0";
    string public turboEZETHName = "Turbo EZETH V0.0";

    // Share Price Oracle Names
    string public realYieldUsdSharePriceOracleName = "Real Yield USD Share Price Oracle V0.0";
    string public realYieldEthSharePriceOracleName = "Real Yield ETH Share Price Oracle V0.1";
    string public realYieldMaticSharePriceOracleName = "Real Yield MATIC Share Price Oracle V0.0";
    string public realYieldAvaxSharePriceOracleName = "Real Yield AVAX Share Price Oracle V0.0";

    // Cellar Staking Contracts
    string public realYieldUsdStakingName = "Real Yield USD Staking V0.0";
    string public realYieldEthStakingName = "Real Yield ETH Staking V0.1";
    // Mainnet
    // TODO morpho adaptors
    // aave v2 adaptors

    // PRODUCTION_REGISTRY_V3 = {
    // ERC20_ADAPTOR_NAME: "0xa5D315eA3D066160651459C4123ead9264130BFd",
    // UNIV3_ADAPTOR_NAME: "0xC74fFa211A8148949a77ec1070Df7013C8D5Ce92",
    // ONE_INCH_ADAPTOR_NAME: "0xB8952ce4010CFF3C74586d712a4402285A3a3AFb",
    // ZEROX_ADAPTOR_NAME: "0x1039a9b61DFF6A3fb8dbF4e924AA749E5cFE35ef",
    // SWAP_WITH_UNISWAP_ADAPTOR_NAME: "0xd6BC6Df1ed43e3101bC27a4254593a06598a3fDD",
    // f"{BALANCER_POOL_ADAPTOR_NAME} (Deprecated)": "0xa05322534381D371Bf095E031D939f54faA33823",
    // FEES_AND_RESERVES_ADAPTOR_NAME: "0x647d264d800A2461E594796af61a39b7735d8933",
    // MORPHO_AAVEV2_ATOKEN_ADAPTOR_NAME: "0xD11142d10f4E5f12A97E6702cc43E598dC77B2D6",
    // MORPHO_AAVEV3_P2P_ADAPTOR_NAME: "0x0Dd5d6bA17f223b51f46D4Ed5231cFBf929cFdEe",
    // AAVEV3_ATOKEN_ADAPTOR_NAME: "0x76Cef5606C8b6bA38FE2e3c639E1659afA530b47",
    // AAVEV3_DEBTTOKEN_ADAPTOR_NAME: "0x6DEd49176a69bEBf8dC1a4Ea357faa555df188f7",
    // MORPHO_AAVEV2_DEBTTOKEN_ADAPTOR_NAME: "0x407D5489F201013EE6A6ca20fCcb05047C548138",
    // LEGACY_CELLAR_ADAPTOR_NAME: "0x1e22aDf9E63eF8F2A3626841DDdDD19683E31068",
    // VESTING_SIMPLE_ADAPTOR_NAME: "0x3b98BA00f981342664969e609Fb88280704ac479",
    // AAVE_ATOKEN_ADAPTOR_NAME: "0xe3A3b8AbbF3276AD99366811eDf64A0a4b30fDa2",
    // AAVE_DEBTTOKEN_ADAPTOR_NAME: "0xeC86ac06767e911f5FdE7cba5D97f082C0139C01",
    // MORPHO_AAVEV3_ATOKEN_ADAPTOR_NAME: "0xB46E8a03b1AaFFFb50f281397C57b5B87080363E",
    // MORPHO_AAVEV3_DEBTTOKEN_ADAPTOR_NAME: "0x25a61f771aF9a38C10dDd93c2bBAb39a88926fa9",
    // f"{AAVE_ATOKEN_ADAPTOR_NAME} 1.02HF": "0x76282f60d541Ec41b26ac8fC0F6922337ADE0a86",
    // f"{AAVE_DEBTTOKEN_ADAPTOR_NAME} 1.02HF": "0x1de3C2790E958BeDe9cA26e93169dBDfEF5A94B2",
    // f"{AAVEV3_ATOKEN_ADAPTOR_NAME} 1.02HF": "0x96916a05c09f78B831c7bfC6e10e991A6fbeE1B3",
    // f"{AAVEV3_DEBTTOKEN_ADAPTOR_NAME} 1.02HF": "0x0C74c849cC9aaACDe78d8657aBD6812C675726Fb",
    // f"{MORPHO_AAVEV2_ATOKEN_ADAPTOR_NAME} 1.02HF": "0xD8224b856DdB3227CC0dCCb59BCBB5236651E25F",
    // f"{MORPHO_AAVEV2_DEBTTOKEN_ADAPTOR_NAME} 1.02HF": "0xc852e0835eFaFeEF3B4d5bfEF41AA52D0E4eeD98",
    // f"{MORPHO_AAVEV3_ATOKEN_ADAPTOR_NAME} 1.02HF": "0x84E7ea073bFd8c409678dBd17EC481dC9AD7Dcd9",
    // f"{MORPHO_AAVEV3_DEBTTOKEN_ADAPTOR_NAME} 1.02HF": "0xf7C64ED003C997BD88DC5f1081eFBBE607400Df0",
    // BALANCER_POOL_ADAPTOR_NAME: "0x2750348A897059C45683d33A1742a3989454F7d6",
    // f"{VESTING_SIMPLE_ADAPTOR_NAME} SOMM": "0x8a95BBAbb0039480F6DD90fe856c1E0c3D575aA1",
    // CELLAR_ADAPTOR_NAME: "0x3B5CA5de4d808Cd793d3a7b3a731D3E67E707B27",
    // AAVE_ENABLE_ASSET_AS_COLLATERAL_ADAPTOR_NAME: "0x724FEb5819D1717Aec5ADBc0974a655a498b2614",
    // }
}
