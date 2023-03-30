// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, ERC4626, ERC20, SafeTransferLib } from "src/mocks/MockCellar.sol";
import { Cellar } from "src/base/Cellar.sol";
import { EulerETokenAdaptor } from "src/modules/adaptors/Euler/EulerETokenAdaptor.sol";
import { IEuler, IEulerMarkets, IEulerExec, IEulerEToken, IEulerDToken } from "src/interfaces/external/IEuler.sol";
import { EulerDebtTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Euler/EulerDebtTokenAdaptor.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { OneInchAdaptor } from "src/modules/adaptors/OneInch/OneInchAdaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";
import { MockOneInchAdaptor } from "src/mocks/adaptors/MockOneInchAdaptor.sol";

contract CellarOneInchTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    ERC20Adaptor private erc20Adaptor;
    OneInchAdaptor private oneInchAdaptor;
    MockOneInchAdaptor private mockOneInchAdaptor;
    Cellar private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    uint32 private usdcPosition;
    uint32 private wethPosition;

    // Swap Details
    address private spender = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address private swapTarget = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    bytes private swapCallData =
        hex"0502b1c5000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000000989680000000000000000000000000000000000000000000000000001483d59a9bcf1b0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000003b5dc1003926a168c11a816e10c13977f75f488bfffe88e4cfee7c08";

    function setUp() external {
        erc20Adaptor = new ERC20Adaptor();
        oneInchAdaptor = new OneInchAdaptor();
        mockOneInchAdaptor = new MockOneInchAdaptor();
        priceRouter = new PriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(address(this), address(swapRouter), address(priceRouter));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Setup Cellar:
        // Cellar positions array.
        uint32[] memory positions = new uint32[](2);
        uint32[] memory debtPositions;

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(oneInchAdaptor));
        registry.trustAdaptor(address(mockOneInchAdaptor));

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));
        wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH));

        positions[0] = usdcPosition;
        positions[1] = wethPosition;

        bytes[] memory positionConfigs = new bytes[](2);
        bytes[] memory debtConfigs;

        cellar = new Cellar(
            registry,
            USDC,
            "OneInch Cellar",
            "OneInch-CLR",
            abi.encode(
                positions,
                debtPositions,
                positionConfigs,
                debtConfigs,
                usdcPosition,
                address(0),
                type(uint128).max,
                type(uint128).max
            )
        );

        cellar.addAdaptorToCatalogue(address(oneInchAdaptor));
        cellar.addAdaptorToCatalogue(address(mockOneInchAdaptor));

        cellar.setRebalanceDeviation(0.01e18);

        USDC.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testOneInchSwap() external {
        if (block.number < 16921343) {
            console.log("Invalid block number. use 16921343");
            return;
        }
        // Deposit into Cellar.
        uint256 assets = 10_000_000;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToSwap(USDC, WETH, assets, swapCallData);

            data[0] = Cellar.AdaptorCall({ adaptor: address(oneInchAdaptor), callData: adaptorCalls });
            cellar.callOnAdaptor(data);
        }

        assertEq(USDC.balanceOf(address(cellar)), 0, "Cellar USDC should have been converted into WETH.");
        uint256 expectedWETH = priceRouter.getValue(USDC, assets, WETH);
        assertApproxEqRel(
            WETH.balanceOf(address(cellar)),
            expectedWETH,
            0.01e18,
            "Cellar WETH should be approximately equal to expected."
        );
    }

    function testSlippageChecks() external {
        // Deposit into Cellar.
        uint256 assets = 1_000_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        ERC20 from;
        ERC20 to;
        uint256 fromAmount;
        bytes memory slippageSwapData;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Make a swap where both assets are supported by the price router, and slippage is good.
        from = USDC;
        to = WETH;
        fromAmount = 1_000e6;
        slippageSwapData = abi.encodeWithSignature(
            "slippageSwap(address,address,uint256,uint32)",
            from,
            to,
            fromAmount,
            0.99e4
        );

        // Make the swap.
        adaptorCalls[0] = _createBytesDataToSwap(from, to, fromAmount, slippageSwapData);
        data[0] = Cellar.AdaptorCall({ adaptor: address(mockOneInchAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // This test does not spend cellars approval, but check it is still zero.
        assertEq(USDC.allowance(address(cellar), address(this)), 0, "Approval should have been revoked.");

        // Make the same swap, but have the slippage check fail.
        slippageSwapData = abi.encodeWithSignature(
            "slippageSwap(address,address,uint256,uint32)",
            from,
            to,
            fromAmount,
            0.89e4
        );

        // Make the swap.
        adaptorCalls[0] = _createBytesDataToSwap(from, to, fromAmount, slippageSwapData);
        data[0] = Cellar.AdaptorCall({ adaptor: address(mockOneInchAdaptor), callData: adaptorCalls });
        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__Slippage.selector)));
        cellar.callOnAdaptor(data);

        // Try making a swap where the from `asset` is supported, but the `to` asset is not.
        from = USDC;
        to = ERC20(address(1));
        fromAmount = 1_000e6;
        slippageSwapData = abi.encodeWithSignature(
            "slippageSwap(address,address,uint256,uint32)",
            from,
            to,
            fromAmount,
            0.99e4
        );
        adaptorCalls[0] = _createBytesDataToSwap(from, to, fromAmount, slippageSwapData);
        data[0] = Cellar.AdaptorCall({ adaptor: address(mockOneInchAdaptor), callData: adaptorCalls });
        vm.expectRevert(
            bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__PricingNotSupported.selector, address(1)))
        );
        cellar.callOnAdaptor(data);

        // Make a swap where the `from` asset is not supported.
        from = DAI;
        to = USDC;
        fromAmount = 1_000e18;
        deal(address(DAI), address(cellar), fromAmount);
        slippageSwapData = abi.encodeWithSignature(
            "slippageSwap(address,address,uint256,uint32)",
            from,
            to,
            fromAmount,
            0.99e4
        );
        adaptorCalls[0] = _createBytesDataToSwap(from, to, fromAmount, slippageSwapData);
        data[0] = Cellar.AdaptorCall({ adaptor: address(mockOneInchAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Demonstrate that multiple swaps back to back can max out slippage and still work.
        from = USDC;
        to = WETH;
        fromAmount = 1_000e6;
        slippageSwapData = abi.encodeWithSignature(
            "slippageSwap(address,address,uint256,uint32)",
            from,
            to,
            fromAmount,
            0.9001e4
        );

        adaptorCalls = new bytes[](10);
        for (uint256 i; i < 10; ++i) adaptorCalls[i] = _createBytesDataToSwap(from, to, fromAmount, slippageSwapData);
        data[0] = Cellar.AdaptorCall({ adaptor: address(mockOneInchAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Above rebalance works, but this attack vector will be mitigated on the steward side, by flagging suspicious rebalances,
        // such as the one above.
    }

    function slippageSwap(ERC20 from, ERC20 to, uint256 inAmount, uint32 slippage) public {
        if (priceRouter.isSupported(from) && priceRouter.isSupported(to)) {
            // Figure out value in, quoted in `to`.
            uint256 fullValueOut = priceRouter.getValue(from, inAmount, to);
            uint256 valueOutWithSlippage = fullValueOut.mulDivDown(slippage, 1e4);
            // Deal caller new balances.
            deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
            deal(address(to), msg.sender, to.balanceOf(msg.sender) + valueOutWithSlippage);
        } else {
            // Pricing is not supported, so just assume exchange rate is 1:1.
            deal(address(from), msg.sender, from.balanceOf(msg.sender) - inAmount);
            deal(
                address(to),
                msg.sender,
                to.balanceOf(msg.sender) + inAmount.changeDecimals(from.decimals(), to.decimals())
            );
        }
    }

    function _createBytesDataToSwap(
        ERC20 tokenIn,
        ERC20 tokenOut,
        uint256 amount,
        bytes memory _swapCallData
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(OneInchAdaptor.swapWithOneInch.selector, tokenIn, tokenOut, amount, _swapCallData);
    }
}

// OneInch swap calldata at block 16921343

// {
//   "fromToken": {
//     "symbol": "ETH",
//     "name": "Ethereum",
//     "decimals": 18,
//     "address": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
//     "logoURI": "https://tokens.1inch.io/0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.png",
//     "tags": [
//       "native",
//       "PEG:ETH"
//     ]
//   },
//   "toToken": {
//     "symbol": "MATIC",
//     "name": "Matic Token",
//     "decimals": 18,
//     "address": "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0",
//     "logoURI": "https://tokens.1inch.io/0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0.png",
//     "tags": [
//       "tokens"
//     ]
//   },
//   "toTokenAmount": "163963423852",
//   "fromTokenAmount": "100000000",
//   "protocols": [
//     [
//       [
//         {
//           "name": "UNISWAP_V2",
//           "part": 100,
//           "fromTokenAddress": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
//           "toTokenAddress": "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0"
//         }
//       ]
//     ]
//   ],
//   "tx": {
//     "from": "0xB6631E52E513eEE0b8c932d7c76F8ccfA607a28e",
//     "to": "0x1111111254eeb25477b68fb85ed929f73a960582",
//     "data": "0x0502b1c500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005f5e10000000000000000000000000000000000000000000000000000000025cb40772d0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000180000000000000003b6d0340819f3450da6f110ba6ea52195b3beafa246062decfee7c08",
//     "value": "100000000",
//     "gas": 133099,
//     "gasPrice": "29584025240"
//   }
// }

// {
//   "fromToken": {
//     "symbol": "USDC",
//     "name": "USD Coin",
//     "address": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
//     "decimals": 6,
//     "logoURI": "https://tokens.1inch.io/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48.png",
//     "eip2612": true,
//     "domainVersion": "2",
//     "tags": [
//       "tokens",
//       "PEG:USD"
//     ]
//   },
//   "toToken": {
//     "symbol": "WETH",
//     "name": "Wrapped Ether",
//     "address": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
//     "decimals": 18,
//     "logoURI": "https://tokens.1inch.io/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2.png",
//     "wrappedNative": "true",
//     "tags": [
//       "tokens",
//       "PEG:ETH"
//     ]
//   },
//   "toTokenAmount": "5832780787260795",
//   "fromTokenAmount": "10000000",
//   "protocols": [
//     [
//       [
//         {
//           "name": "LUASWAP",
//           "part": 100,
//           "fromTokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
//           "toTokenAddress": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
//         }
//       ]
//     ]
//   ],
//   "tx": {
//     "from": "0xB6631E52E513eEE0b8c932d7c76F8ccfA607a28e",
//     "to": "0x1111111254eeb25477b68fb85ed929f73a960582",
//     "data": "0x0502b1c5000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000000989680000000000000000000000000000000000000000000000000001483d59a9bcf1b0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000003b5dc1003926a168c11a816e10c13977f75f488bfffe88e4cfee7c08",
//     "value": "0",
//     "gas": 157684,
//     "gasPrice": "30694393265"
//   }
// }
