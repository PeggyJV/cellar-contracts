// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/UniSwap/UniswapV3Adaptor.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";

// Import adaptors.
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract AddLiqquidityToAllPositionsTest is Test {
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    CellarInitializableV2_1 private cellar = CellarInitializableV2_1(0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E);

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    UniswapV3Adaptor private uniswapV3Adaptor = UniswapV3Adaptor(0x7C4262f83e6775D6ff6fE8d9ab268611Ed9d13Ee);

    function setUp() external {}

    function testCleanUp() external {
        deal(address(USDC), address(this), 3_000e6);
        USDC.approve(address(cellar), 3_000e6);

        // Deposit to make addresses warm
        uint256 gas = gasleft();
        cellar.deposit(1_000e6, address(this));
        console.log("Gas Used", gas - gasleft());

        gas = gasleft();
        cellar.deposit(1_000e6, address(this));
        console.log("Gas Used", gas - gasleft());

        uint256 nftCount = positionManager.balanceOf(address(cellar));

        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](nftCount);

        uint256 i;
        while (i < nftCount) {
            uint256 id = positionManager.tokenOfOwnerByIndex(address(cellar), i);
            // We wanna keep this liquidity
            adaptorCalls[i] = _createBytesDataToCloseLP(id);
            i++;
        }

        data[0] = Cellar.AdaptorCall({ adaptor: address(uniswapV3Adaptor), callData: adaptorCalls });

        // Strategist rebalances cellar to remove unused positions.
        vm.startPrank(cellar.owner());
        gas = gasleft();
        cellar.callOnAdaptor(data);
        console.log("Gas Used to rebalance", gas - gasleft());
        vm.stopPrank();

        gas = gasleft();
        cellar.deposit(1_000e6, address(this));
        console.log("Gas Used", gas - gasleft());
    }

    function _createBytesDataToCloseLP(uint256 id) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(UniswapV3Adaptor.closePosition.selector, id, 0, 0);
    }
}
