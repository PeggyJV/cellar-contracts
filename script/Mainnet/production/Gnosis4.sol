// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { BalancerStablePoolExtension } from "src/modules/price-router/Extensions/Balancer/BalancerStablePoolExtension.sol";

import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.sol";
import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

// import { IMorpho, MarketParams, Id, Market } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";
import { IMorpho, MarketParams, Id, Market } from "src/interfaces/external/Morpho/MorphoBlue/interfaces/IMorpho.sol";

/**
 * @dev For MorphoBlue specific details: go to `MorphoBlue` contract on mainnet, and query for marketParams using the marketId that you can get from their docs, respectively, or their UI for each market.
 * @dev Run
 *      `source .env && forge script script/Mainnet/production/Gnosis4.s.sol:Gnosis4Script --rpc-url $MAINNET_RPC_URL --sender $MULTI_SIG --with-gas-price 25000000000`
 * NOTE:
 * osETHWethMarketId = 0xd5211d0e3f4a30d5c98653d988585792bb7812221f04801be73a44ceecb11e89;
 * weethWethMarketId = 0x698fe98247a40c5771537b5786b2f3f9d78eb487b4ce4d75533cd0e94d88a115;
 *
 * Extra NOTE: UniswapV3 - https://etherscan.io/address/0x96C3Acb0F3F523d7bec7dF43bdf8CCD8c05D0D3E#readContract
 * Balancer/Gauge details - https://app.aura.finance/#/1/pool/179
 */
contract Gnosis4Script is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    Deployer public deployer = Deployer(deployerAddress);
    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);

    address public morphoBlueSupplyAdaptor = 0xCE1d8694e8fcDD350B1d6EC23e61185660174882;
    address public morphoBlueCollateralAdaptor = 0x8a0eB443F1E9Baa4DfB62E6516E140950236c57A;
    address public morphoBlueDebtAdaptor = 0x7A8F53E15BCe9b546D38C28Ed4Fe4D131E0B73Ec;
    // address public uniswapV3Adaptor = ;
    // address public curveAdaptor = ;
    // address public convexCurveAdaptor = ;
    // address public balancerAdaptor = ;

    /// New positions

    /// MorphoBlue Positions
    // supply positions
    uint32 public osETH_WETH_MorphoBlueSupplyPosition = 11_000_0007; // supplies WETH to osETHWethMarket
    uint32 public WEETH_WETH_MorphoBlueSupplyPosition = 11_000_0008; // supplies WETH to weEthWethMarket

    // collateral positions
    uint32 public osETH_WETH_MorphoBlueCollateralPosition = 11_000_0009; // provides collateral (osETH) to osETHWethMarket
    uint32 public WEETH_WETH_MorphoBlueCollateralPosition = 11_000_0010; // provides collateral (weETH) to weEthWethMarket

    // borrow positions
    uint32 public osETH_WETH_MorphoBlueBorrowPosition = 11_500_004; // borrows WETH from osETHWethMarket
    uint32 public WEETH_WETH_MorphoBlueBorrowPosition = 11_500_005; // borrows WETH from weEthWethMarket

    /// UniswapV3Position details w/ weth/oseth: 0x96C3Acb0F3F523d7bec7dF43bdf8CCD8c05D0D3E
    uint32 public WETH_OSETH_UniswapV3Position = 11_000_0011;

    /// Curve Position Details
    uint32 public OSETH_RETH_CurvePosition = 11_000_0012;

    /// Convex Position Details
    uint32 public OSETH_RETH_CurveConvexPosition = 11_000_0013;

    /// Balancer Position Details
    uint32 public OSETH_WETH_BalancerPosition = 11_000_0014;

    IMorpho morphoBlue = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    function run() external {
        vm.startBroadcast();

        MarketParams memory osEthWethMarket = MarketParams(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38,
            0x224F2F1333b45E34fFCfC3bD01cE43C73A914498,
            0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
            860000000000000000
        );

        MarketParams memory weEthWethMarket = MarketParams(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee,
            0x3fa58b74e9a8eA8768eb33c8453e9C2Ed089A40a,
            0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
            860000000000000000
        );

        /// Add MorphoBlue Positions.

        // supply positions
        registry.trustPosition(
            osETH_WETH_MorphoBlueSupplyPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(osEthWethMarket)
        );
        registry.trustPosition(
            WEETH_WETH_MorphoBlueSupplyPosition,
            address(morphoBlueSupplyAdaptor),
            abi.encode(weEthWethMarket)
        );

        // collateral positions
        registry.trustPosition(
            osETH_WETH_MorphoBlueCollateralPosition,
            address(morphoBlueCollateralAdaptor),
            abi.encode(osEthWethMarket)
        );
        registry.trustPosition(
            WEETH_WETH_MorphoBlueCollateralPosition,
            address(morphoBlueCollateralAdaptor),
            abi.encode(weEthWethMarket)
        );

        // borrow positions
        registry.trustPosition(
            osETH_WETH_MorphoBlueBorrowPosition,
            address(morphoBlueDebtAdaptor),
            abi.encode(osEthWethMarket)
        );
        registry.trustPosition(
            WEETH_WETH_MorphoBlueBorrowPosition,
            address(morphoBlueDebtAdaptor),
            abi.encode(weEthWethMarket)
        );

        /// Add new uniswap position
        // token0 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        // ERC20 public OSETH = ERC20(0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38);
        // registry.trustPosition(WETH_OSETH_UniswapV3Position, address(uniswapV3Adaptor), abi.encode(WETH, OSETH)); // token 1

        /// Add add balancer/aura oseth/weth position
        // adaptorData = abi.encode(ERC20 _bpt, address _liquidityGauge)
        // address public osETH_wETH_GAUGE_ADDRESS = 0xc592c33e51a764b94db0702d8baf4035ed577aed;
        // ERC20 public osETH_wETH = ERC20(0xDACf5Fa19b1f720111609043ac67A9818262850c);

        // registry.trustPosition(OSETH_WETH_BalancerPosition, address(balancerAdaptor), abi.encode(osETH_wETH, osETH_wETH_GAUGE_ADDRESS));

        vm.stopBroadcast();
    }
}
