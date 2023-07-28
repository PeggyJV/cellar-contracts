// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import {  IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken, IEulerDToken } from "src/interfaces/external/IEuler.sol";

// Import adaptors.
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/CleanUpCellar/AddLiquidityToAllPositions.s.sol:AddLiquidityToAllPositionsScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract AddLiquidityToAllPositionsScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    struct Position {
        uint256 id;
        uint128 liquidity;
        ERC20 t0;
        ERC20 t1;
    }

    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;

    CellarFactory private factory = CellarFactory(0xFCed747657ACfFc6FAfacD606E17D0988EDf3Fd9);
    Registry private registry = Registry(0xd1c18363F81d8E6260511b38FcF1e8b710E7e31D);

    CellarInitializableV2_1 private cellar = CellarInitializableV2_1(0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E);

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    function run() external {
        uint256 nftCount = positionManager.balanceOf(address(cellar));
        Position[] memory positions = new Position[](nftCount);

        for (uint256 i; i < nftCount; ++i) {
            uint256 id = positionManager.tokenOfOwnerByIndex(address(cellar), i);
            (, , address t0, address t1, , , , uint128 liquidity, , , , ) = positionManager.positions(id);
            positions[i] = Position({ id: id, liquidity: liquidity, t0: ERC20(t0), t1: ERC20(t1) });
        }

        vm.startBroadcast();

        USDC.safeApprove(address(positionManager), 5e6);
        USDT.safeApprove(address(positionManager), 5e6);
        DAI.safeApprove(address(positionManager), 5e18);

        uint256 amount0;
        uint256 amount1;

        for (uint256 i; i < nftCount; ++i) {
            if (positions[i].liquidity > 0) continue;

            if (positions[i].t0 == USDC || positions[i].t0 == USDT) amount0 = 0.01e6;
            else amount0 = 0.01e18;

            if (positions[i].t1 == USDC || positions[i].t1 == USDT) amount1 = 0.01e6;
            else amount1 = 0.01e18;
            // Create increase liquidity params.
            INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: positions[i].id,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 1 days
                });

            // Increase liquidity in pool.
            (uint128 liquidity, , ) = positionManager.increaseLiquidity(params);
            require(liquidity > 0, "No liquidity added");
        }

        vm.stopBroadcast();
    }
}
