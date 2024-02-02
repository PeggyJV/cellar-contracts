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
 *      `source .env && forge script script/Mainnet/production/Gnosis6.s.sol:Gnosis6Script --rpc-url $MAINNET_RPC_URL --sender $MULTI_SIG --with-gas-price 25000000000`
 */
contract Gnosis6Script is Script, MainnetAddresses {
    using Math for uint256;

    address public sommDev = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0xEED68C267E9313a6ED6ee08de08c9F68dee44476);
    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);
    Curve2PoolExtension public curve2PoolExtension = Curve2PoolExtension(0xbF45bCd5058ddcc69add6D53D8f5603AEdD2a5e1);

    address public curveAdaptor = 0x94E28529f73dAD189CD0bf9D83a06572d4bFB26a;
    address public convexCurveAdaptor = 0x98C44FF447c62364E3750C5e2eF8acc38391A8B0;
    address public uniswapV3Adaptor = 0xC74fFa211A8148949a77ec1070Df7013C8D5Ce92;
    address public erc20Adaptor = 0xa5D315eA3D066160651459C4123ead9264130BFd;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;
    uint8 public constant TWAP_DERIVATIVE = 2;
    uint8 public constant EXTENSION_DERIVATIVE = 3;

    // New positions
    // WstethEthXPool
    // WstethEthXToken
    // WstethEthXGauge
    // EthEthXPool
    // EthEthXToken
    // EthEthXGauge

    uint32 public WstethEthXPosition = 6_000_006;
    uint32 public EthEthXPosition = 6_000_007;

    uint32 public WstethEthXConvexPosition = 6_500_005;
    uint32 public EthEthXConvexPosition = 6_500_006;

    uint32 public WstethEthxUniswapV3Position = 1_000_010;
    uint32 public EthXWethUniswapV3Position = 1_000_011;

    uint32 public ethxPosition = 14;

    uint256 public wstethEthxCurveLpPriceWith8Decimals = 4_989e8;
    uint256 public ethEthxCurveLpPriceWith8Decimals = 2_318e8;

    function run() external {
        PriceRouter.AssetSettings memory settings;
        Curve2PoolExtension.ExtensionStorage memory stor;
        vm.startBroadcast();

        // Add pricing.
        stor = Curve2PoolExtension.ExtensionStorage({
            pool: WstethEthXPool,
            underlyingOrConstituent0: address(WSTETH),
            underlyingOrConstituent1: address(ETHX),
            divideRate0: false,
            divideRate1: false,
            isCorrelated: false,
            upperBound: 10300,
            lowerBound: 9900
        });

        settings = PriceRouter.AssetSettings({
            derivative: EXTENSION_DERIVATIVE,
            source: address(curve2PoolExtension)
        });

        priceRouter.addAsset(ERC20(WstethEthXToken), settings, abi.encode(stor), wstethEthxCurveLpPriceWith8Decimals);

        stor = Curve2PoolExtension.ExtensionStorage({
            pool: EthEthXPool,
            underlyingOrConstituent0: address(WETH),
            underlyingOrConstituent1: address(ETHX),
            divideRate0: false,
            divideRate1: true,
            isCorrelated: true,
            upperBound: 10300,
            lowerBound: 9900
        });

        settings = PriceRouter.AssetSettings({
            derivative: EXTENSION_DERIVATIVE,
            source: address(curve2PoolExtension)
        });

        priceRouter.addAsset(ERC20(EthEthXToken), settings, abi.encode(stor), ethEthxCurveLpPriceWith8Decimals);

        // Add Curve Positions.
        registry.trustPosition(
            WstethEthXPosition,
            curveAdaptor,
            abi.encode(WstethEthXPool, WstethEthXToken, WstethEthXGauge, CurvePool.claim_admin_fees.selector)
        );
        registry.trustPosition(
            EthEthXPosition,
            curveAdaptor,
            abi.encode(EthEthXPool, EthEthXToken, EthEthXGauge, CurvePool.get_virtual_price.selector)
        );

        // Add Convex Positions.
        registry.trustPosition(
            WstethEthXConvexPosition,
            convexCurveAdaptor,
            abi.encode(
                265,
                wstethEthxBaseRewardPool,
                WstethEthXToken,
                WstethEthXPool,
                CurvePool.claim_admin_fees.selector
            )
        );
        registry.trustPosition(
            EthEthXConvexPosition,
            convexCurveAdaptor,
            abi.encode(232, ethEthxBaseRewardPool, EthEthXToken, EthEthXPool, CurvePool.get_virtual_price.selector)
        );

        // Add Uniswap V3 Positions.
        registry.trustPosition(WstethEthxUniswapV3Position, uniswapV3Adaptor, abi.encode(WSTETH, ETHX));
        registry.trustPosition(EthXWethUniswapV3Position, uniswapV3Adaptor, abi.encode(ETHX, WETH));

        // Add ERC20 position
        registry.trustPosition(ethxPosition, erc20Adaptor, abi.encode(ETHX));

        vm.stopBroadcast();
    }
}
