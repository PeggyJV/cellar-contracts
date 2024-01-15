// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { SequencerPriceRouter, PriceRouter, Registry, ERC20, IChainlinkAggregator } from "src/modules/price-router/permutations/SequencerPriceRouter.sol";
import { Math } from "src/utils/Math.sol";

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

// TODO refactor to a multichain test once deploy is merged into branch.
contract SequencerPriceRouterTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;

    SequencerPriceRouter public sequencerPriceRouter;

    address arbitrumSequencerUptimeFeed = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;
    ERC20 public WETH = ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ERC20 public USDC = ERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address public USDC_USD_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    Registry public registry;

    // Variables so this contract can act as a mock sequencer uptime fee.
    int256 mockAnswer = type(int256).max;
    uint256 mockStartedAt = 0;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "ARBITRUM_RPC_URL";
        uint256 blockNumber = 161730035;

        uint256 forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);

        sequencerPriceRouter = new SequencerPriceRouter(address(this), 3_600, address(this), registry, WETH);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        settings = PriceRouter.AssetSettings(1, USDC_USD_FEED);
        sequencerPriceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    function testSequencerUptimeFeedLogic() external {
        // Sequencer is currently up so pricing succeeds.
        sequencerPriceRouter.getPriceInUSD(USDC);

        // But if sequencer goes down.
        mockAnswer = 1;
        mockStartedAt = block.timestamp - 1;

        // Pricing calls revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(SequencerPriceRouter.SequencerPriceRouter__SequencerDown.selector))
        );
        sequencerPriceRouter.getPriceInUSD(USDC);

        // And if sequencer comes back up.
        mockAnswer = type(int256).max;

        // Grace period must pass before pricing calls succeed.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(SequencerPriceRouter.SequencerPriceRouter__GracePeriodNotOver.selector))
        );
        sequencerPriceRouter.getPriceInUSD(USDC);

        mockStartedAt = block.timestamp - 3_601;

        // Pricing calls now succeed.
        sequencerPriceRouter.getPriceInUSD(USDC);
    }

    function latestRoundData()
        public
        view
        returns (uint80 roundID, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundID, answer, startedAt, updatedAt, answeredInRound) = IChainlinkAggregator(arbitrumSequencerUptimeFeed)
            .latestRoundData();
        if (mockAnswer != type(int256).max) answer = mockAnswer;
        if (mockStartedAt != 0) startedAt = mockStartedAt;
    }
}
