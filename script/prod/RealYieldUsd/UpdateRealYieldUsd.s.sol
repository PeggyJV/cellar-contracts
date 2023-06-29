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

    // Values needed to make positions.
    address private aV2USDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address private aV2DAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address private aV2USDT = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;

    address private morphoAaveV2ATokenAdaptor = 0x1a4cB53eDB8C65C3DF6Aa9D88c1aB4CF35312b73;

    function run() external {
        uint256 numberOfCalls = 4;

        address[] memory targets = new address[](numberOfCalls);
        for (uint256 i; i < numberOfCalls; ++i) targets[i] = address(registry);

        uint256[] memory values = new uint256[](numberOfCalls);

        bytes[] memory payloads = new bytes[](numberOfCalls);
        // Need to trustAdaptors
        payloads[0] = abi.encodeWithSelector(IRegistry.trustAdaptor.selector, morphoAaveV2ATokenAdaptor, 0, 0);
        payloads[1] = abi.encodeWithSelector(
            IRegistry.trustPosition.selector,
            morphoAaveV2ATokenAdaptor,
            abi.encode(aV2DAI),
            0,
            0
        );
        payloads[2] = abi.encodeWithSelector(
            IRegistry.trustPosition.selector,
            morphoAaveV2ATokenAdaptor,
            abi.encode(aV2USDT),
            0,
            0
        );
        payloads[3] = abi.encodeWithSelector(
            IRegistry.trustPosition.selector,
            morphoAaveV2ATokenAdaptor,
            abi.encode(aV2USDC),
            0,
            0
        );

        bytes32 predecessor = hex"";
        bytes32 salt = hex"";

        uint256 delay = 3 days;

        vm.startBroadcast();
        controller.scheduleBatch(targets, values, payloads, predecessor, salt, delay);
        vm.stopBroadcast();
    }
}
