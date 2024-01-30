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
import { Curve2PoolExtension, CurvePool } from "src/modules/price-router/Extensions/Curve/Curve2PoolExtension.sol";

import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDeposit.sol";
import { CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport } from "src/base/permutations/advanced/CellarWithOracleWithBalancerFlashLoansWithMultiAssetDepositWithNativeSupport.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Mainnet/production/Gnosis1.s.sol:Gnosis1Script --rpc-url $MAINNET_RPC_URL --sender $MULTI_SIG --with-gas-price 25000000000`
 */
contract Gnosis1Script is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);
    Curve2PoolExtension public curve2PoolExtension = Curve2PoolExtension(0xbF45bCd5058ddcc69add6D53D8f5603AEdD2a5e1);

    address public aaveV3ATokenAdaptor = 0x96916a05c09f78B831c7bfC6e10e991A6fbeE1B3;
    address public aaveV3DebtTokenAdaptor = 0x0C74c849cC9aaACDe78d8657aBD6812C675726Fb;
    address public curveAdaptor = 0x94E28529f73dAD189CD0bf9D83a06572d4bFB26a;
    address public convexCurveAdaptor = 0x98C44FF447c62364E3750C5e2eF8acc38391A8B0;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    // New positions
    uint32 public aCRVUSDPosition = 2_000_014;
    uint32 public dCRVUSDPosition = 2_500_011;

    uint32 public usdtCrvUsdPosition = 6_000_003;
    uint32 public fraxCrvUsdPosition = 6_000_004;
    uint32 public lusdCrvUsdPosition = 6_000_005;

    uint32 public usdtCrvUsdConvexPosition = 6_500_002;
    uint32 public fraxCrvUsdConvexPosition = 6_500_003;
    uint32 public lusdCrvUsdConvexPosition = 6_500_004;

    function run() external {
        PriceRouter.AssetSettings memory settings;
        Curve2PoolExtension.ExtensionStorage memory stor;
        vm.startBroadcast();

        // Add pricing.
        stor = Curve2PoolExtension.ExtensionStorage({
            pool: UsdtCrvUsdPool,
            underlyingOrConstituent0: address(USDT),
            underlyingOrConstituent1: address(CRVUSD),
            divideRate0: false,
            divideRate1: false,
            isCorrelated: true,
            upperBound: 10200,
            lowerBound: 9800
        });

        settings = PriceRouter.AssetSettings({
            derivative: EXTENSION_DERIVATIVE,
            source: address(curve2PoolExtension)
        });

        priceRouter.addAsset(ERC20(UsdtCrvUsdToken), settings, abi.encode(stor), 1e8);

        stor = Curve2PoolExtension.ExtensionStorage({
            pool: FraxCrvUsdPool,
            underlyingOrConstituent0: address(FRAX),
            underlyingOrConstituent1: address(CRVUSD),
            divideRate0: false,
            divideRate1: false,
            isCorrelated: true,
            upperBound: 10200,
            lowerBound: 9800
        });

        settings = PriceRouter.AssetSettings({
            derivative: EXTENSION_DERIVATIVE,
            source: address(curve2PoolExtension)
        });

        priceRouter.addAsset(ERC20(FraxCrvUsdToken), settings, abi.encode(stor), 1e8);

        stor = Curve2PoolExtension.ExtensionStorage({
            pool: LusdCrvUsdPool,
            underlyingOrConstituent0: address(LUSD),
            underlyingOrConstituent1: address(CRVUSD),
            divideRate0: false,
            divideRate1: false,
            isCorrelated: true,
            upperBound: 10200,
            lowerBound: 9800
        });

        settings = PriceRouter.AssetSettings({
            derivative: EXTENSION_DERIVATIVE,
            source: address(curve2PoolExtension)
        });

        priceRouter.addAsset(ERC20(LusdCrvUsdToken), settings, abi.encode(stor), 1e8);

        // Add aave V3 positions.
        registry.trustPosition(aCRVUSDPosition, aaveV3ATokenAdaptor, abi.encode(aV3CrvUsd));
        registry.trustPosition(dCRVUSDPosition, aaveV3DebtTokenAdaptor, abi.encode(dV3CrvUsd));

        // Add Curve Positions.
        registry.trustPosition(
            usdtCrvUsdPosition,
            curveAdaptor,
            abi.encode(UsdtCrvUsdPool, UsdtCrvUsdToken, UsdtCrvUsdGauge, bytes4(0))
        );
        registry.trustPosition(
            fraxCrvUsdPosition,
            curveAdaptor,
            abi.encode(FraxCrvUsdPool, FraxCrvUsdToken, FraxCrvUsdGauge, bytes4(0))
        );
        registry.trustPosition(
            lusdCrvUsdPosition,
            curveAdaptor,
            abi.encode(LusdCrvUsdPool, LusdCrvUsdToken, LusdCrvUsdGauge, CurvePool.get_virtual_price.selector)
        );

        // Add Convex Positions.
        registry.trustPosition(
            usdtCrvUsdConvexPosition,
            convexCurveAdaptor,
            abi.encode(179, usdtCrvUsdBaseRewardPool, UsdtCrvUsdToken, UsdtCrvUsdPool, bytes4(0))
        );
        registry.trustPosition(
            fraxCrvUsdConvexPosition,
            convexCurveAdaptor,
            abi.encode(187, fraxCrvUsdBaseRewardPool, FraxCrvUsdToken, FraxCrvUsdPool, bytes4(0))
        );
        registry.trustPosition(
            lusdCrvUsdConvexPosition,
            convexCurveAdaptor,
            abi.encode(
                229,
                lusdCrvUsdBaseRewardPool,
                LusdCrvUsdToken,
                LusdCrvUsdPool,
                CurvePool.get_virtual_price.selector
            )
        );

        vm.stopBroadcast();
    }
}
