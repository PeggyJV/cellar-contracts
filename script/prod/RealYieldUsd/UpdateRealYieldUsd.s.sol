// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib, PriceRouter } from "src/base/Cellar.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";

// Import adaptors.
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

interface IRegistry {
    function trustAdaptor(address adaptor, uint128 assetRisk, uint128 protocolRisk) external;

    function trustPosition(address adaptor, bytes memory adaptorData, uint128 assetRisk, uint128 protocolRisk) external;
}

interface IRealYieldUsd {
    function addPosition(uint32 index, uint32 positionId, bytes memory congigData, bool inDebtArray) external;
}

interface ICellar {
    function setupAdaptor(address adaptor) external;
}

/**
 * @dev Run
 *      `source .env && forge script script/prod/RealYieldUsd/UpdateRealYieldUsd.s.sol:UpdateRealYieldUsdScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract UpdateRealYieldUsdScript is Script {
    TimelockController private controller = TimelockController(payable(0xaDa78a5E01325B91Bc7879a63c309F7D54d42950));

    IRegistry private registry = IRegistry(0x2Cbd27E034FEE53f79b607430dA7771B22050741);

    address public vestingSimpleAdaptor = 0x508E6aE090eA92Cb90571e4269B799257CD78CA1;
    address public oneInchAdaptor = 0xB8952ce4010CFF3C74586d712a4402285A3a3AFb;
    address public swapWithUniswapAdaptor = 0xd6BC6Df1ed43e3101bC27a4254593a06598a3fDD;
    address public zeroXAdaptor = 0x1039a9b61DFF6A3fb8dbF4e924AA749E5cFE35ef;
    address public aaveV3DebtTokenAdaptor = 0x6DEd49176a69bEBf8dC1a4Ea357faa555df188f7;
    address public aaveV3AtokenAdaptor = 0x3184CBEa47eD519FA04A23c4207cD15b7545F1A6;
    address public aaveDebtTokenAdaptor = 0x5F4e81E1BC9D7074Fc30aa697855bE4e1AA16F0b;
    address public aaveATokenAdaptor = 0x25570a77dCA06fda89C1ef41FAb6eE48a2377E81;
    address public feesAndReservesAdaptor = 0x647d264d800A2461E594796af61a39b7735d8933;
    address public cTokenAdaptor = 0x9a384Df333588428843D128120Becd72434ec078;

    // Values needed to make positions.
    address public usdcVestor = 0xd944D0e62de2ae742C4CA085e80222f58B69b231;
    address private aV2USDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address private aV2DAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address private aV2USDT = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address private aV3USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address private aV3DAI = 0x018008bfb33d285247A21d44E50697654f754e63;
    address private aV3USDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;

    // address private cUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    // address private cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    // address private cUSDT = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;

    function run() external {
        uint256 numberOfCalls = 15;

        address[] memory targets = new address[](numberOfCalls);
        for (uint256 i; i < numberOfCalls; ++i) targets[i] = address(registry);

        uint256[] memory values = new uint256[](numberOfCalls);

        bytes[] memory payloads = new bytes[](numberOfCalls);
        // Need to trustAdaptors
        payloads[0] = abi.encodeWithSelector(IRegistry.trustAdaptor.selector, vestingSimpleAdaptor, 0, 0);
        payloads[1] = abi.encodeWithSelector(IRegistry.trustAdaptor.selector, oneInchAdaptor, 0, 0);
        payloads[2] = abi.encodeWithSelector(IRegistry.trustAdaptor.selector, swapWithUniswapAdaptor, 0, 0);
        payloads[3] = abi.encodeWithSelector(IRegistry.trustAdaptor.selector, zeroXAdaptor, 0, 0);
        payloads[4] = abi.encodeWithSelector(IRegistry.trustAdaptor.selector, aaveV3AtokenAdaptor, 0, 0);
        payloads[5] = abi.encodeWithSelector(IRegistry.trustAdaptor.selector, aaveATokenAdaptor, 0, 0);
        payloads[6] = abi.encodeWithSelector(IRegistry.trustAdaptor.selector, feesAndReservesAdaptor, 0, 0);
        payloads[7] = abi.encodeWithSelector(IRegistry.trustAdaptor.selector, cTokenAdaptor, 0, 0);
        payloads[8] = abi.encodeWithSelector(
            IRegistry.trustPosition.selector,
            aaveATokenAdaptor,
            abi.encode(aV2USDC),
            0,
            0
        );
        payloads[9] = abi.encodeWithSelector(
            IRegistry.trustPosition.selector,
            aaveATokenAdaptor,
            abi.encode(aV2DAI),
            0,
            0
        );
        payloads[10] = abi.encodeWithSelector(
            IRegistry.trustPosition.selector,
            aaveATokenAdaptor,
            abi.encode(aV2USDT),
            0,
            0
        );
        payloads[11] = abi.encodeWithSelector(
            IRegistry.trustPosition.selector,
            aaveV3AtokenAdaptor,
            abi.encode(aV3USDC),
            0,
            0
        );
        payloads[12] = abi.encodeWithSelector(
            IRegistry.trustPosition.selector,
            aaveV3AtokenAdaptor,
            abi.encode(aV3DAI),
            0,
            0
        );
        payloads[13] = abi.encodeWithSelector(
            IRegistry.trustPosition.selector,
            aaveV3AtokenAdaptor,
            abi.encode(aV3USDT),
            0,
            0
        );
        payloads[14] = abi.encodeWithSelector(
            IRegistry.trustPosition.selector,
            vestingSimpleAdaptor,
            abi.encode(usdcVestor),
            0,
            0
        );

        bytes32 predecessor = hex"";
        bytes32 salt = hex"";

        uint256 delay = 3 days;

        vm.startBroadcast();
        controller.scheduleBatch(targets, values, payloads, predecessor, salt, delay);
        vm.stopBroadcast();

        // Wait to trust Compound positions cuz RYUSD needs the new compound adaptor in order to fully exit the compound positions.
        // registry.trustPosition(cTokenAdaptor, abi.encode(cUSDC), 0, 0);
        // registry.trustPosition(cTokenAdaptor, abi.encode(cDAI), 0, 0);
        // registry.trustPosition(cTokenAdaptor, abi.encode(cUSDT), 0, 0);
    }
}
