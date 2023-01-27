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
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarEulerTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    EulerETokenAdaptor private eulerETokenAdaptor;
    EulerDebtTokenAdaptor private eulerDebtTokenAdaptor;
    ERC20Adaptor private erc20Adaptor;
    Cellar private cellar;
    PriceRouter private priceRouter;
    Registry private registry;
    SwapRouter private swapRouter;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    IEulerMarkets private markets = IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    address private euler = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    IEulerExec private exec = IEulerExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);

    IEulerEToken private eUSDC;
    IEulerEToken private eWETH;
    IEulerEToken private eWBTC;

    IEulerDToken private dUSDC;
    IEulerDToken private dWETH;
    IEulerDToken private dWBTC;

    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    // Note this is the BTC USD data feed, but we assume the risk that WBTC depegs from BTC.
    address private WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

    uint32 private usdcPosition;
    uint32 private eUSDCPosition;
    uint32 private debtUSDCPosition;

    function setUp() external {
        eulerETokenAdaptor = new EulerETokenAdaptor();
        eulerDebtTokenAdaptor = new EulerDebtTokenAdaptor();
        erc20Adaptor = new ERC20Adaptor();
        priceRouter = new PriceRouter();

        eUSDC = IEulerEToken(markets.underlyingToEToken(address(USDC)));
        // console.log("eUSDC", address(eUSDC));
        eWETH = IEulerEToken(markets.underlyingToEToken(address(WETH)));
        eWBTC = IEulerEToken(markets.underlyingToEToken(address(WBTC)));

        dUSDC = IEulerDToken(markets.underlyingToDToken(address(USDC)));
        dWETH = IEulerDToken(markets.underlyingToDToken(address(WETH)));
        dWBTC = IEulerDToken(markets.underlyingToDToken(address(WBTC)));

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

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        // Setup Cellar:
        // Cellar positions array.
        uint32[] memory positions = new uint32[](2);
        uint32[] memory debtPositions = new uint32[](1);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);
        registry.trustAdaptor(address(eulerETokenAdaptor), 0, 0);
        registry.trustAdaptor(address(eulerDebtTokenAdaptor), 0, 0);

        usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC), 0, 0);
        eUSDCPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eUSDC, 0), 0, 0);
        debtUSDCPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dUSDC, 0), 0, 0);

        positions[0] = eUSDCPosition;
        positions[1] = usdcPosition;

        debtPositions[0] = debtUSDCPosition;

        bytes[] memory positionConfigs = new bytes[](2);
        bytes[] memory debtConfigs = new bytes[](1);

        cellar = new Cellar(
            registry,
            USDC,
            "Euler Cellar",
            "EULER-CLR",
            abi.encode(
                positions,
                debtPositions,
                positionConfigs,
                debtConfigs,
                eUSDCPosition,
                address(0),
                type(uint128).max,
                type(uint128).max
            )
        );

        cellar.setupAdaptor(address(eulerETokenAdaptor));
        cellar.setupAdaptor(address(eulerDebtTokenAdaptor));

        USDC.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testEulerDeposit() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            eUSDC.balanceOfUnderlying(address(cellar)),
            assets,
            1,
            "Assets should have been deposited into Euler."
        );
    }

    function testEulerWithdraw() external {
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(
            eUSDC.balanceOfUnderlying(address(cellar)),
            assets,
            1,
            "Assets should have been deposited into Euler."
        );

        uint256 assetsToWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(assetsToWithdraw, address(this), address(this));
        assertApproxEqAbs(USDC.balanceOf(address(this)), assets, 1, "Assets should have been withdrawn from Euler.");
    }

    function testEnterMarketAndLoan() external {
        // Deposit into Euler.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        // Enter market and Take out a USDC loan.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
            bytes[] memory adaptorCalls0 = new bytes[](1);
            adaptorCalls0[0] = _createBytesDataToEnterMarket(eUSDC, 0);
            bytes[] memory adaptorCalls1 = new bytes[](1);
            adaptorCalls1[0] = _createBytesDataToBorrow(dUSDC, assets / 2);

            data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls0 });
            data[1] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls1 });
            cellar.callOnAdaptor(data);
        }

        // User Withdraws should now revert.
        uint256 assetsToWithdraw = cellar.maxWithdraw(address(this));
        // Since the USDC loan is just sitting in the cellar, we should only be able to withdraw that.
        uint256 expectedAssetsWithdrawable = assets / 2;
        assertEq(assetsToWithdraw, expectedAssetsWithdrawable, "There should assets / 2 withdrawable.");

        // Calling exitMarket should revert.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToExitMarket(eUSDC, 0);

            data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls });
            vm.expectRevert(bytes("e/outstanding-borrow"));
            cellar.callOnAdaptor(data);
        }
    }

    function testSelfBorrow() external {
        // Deposit into Euler.
        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        uint256 totalAssetsBefore = cellar.totalAssets();

        // Enter market and self borrow  2x USDC assets.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
            bytes[] memory adaptorCalls0 = new bytes[](1);
            adaptorCalls0[0] = _createBytesDataToEnterMarket(eUSDC, 0);
            bytes[] memory adaptorCalls1 = new bytes[](1);
            adaptorCalls1[0] = _createBytesDataToSelfBorrow(address(USDC), 0, 2 * assets);

            data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls0 });
            data[1] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls1 });
            cellar.callOnAdaptor(data);
        }

        assertApproxEqAbs(cellar.totalAssets(), totalAssetsBefore, 1, "Cellar Total Assets should be unchanged.");
        assertApproxEqAbs(
            eUSDC.balanceOfUnderlying(address(cellar)),
            3 * assets,
            1,
            "Cellar eUSDC balance should be 3x assets deposited."
        );
        assertApproxEqAbs(
            dUSDC.balanceOf(address(cellar)),
            2 * assets,
            1,
            "Cellar dUSDC balance should be 2x assets deposited."
        );
    }

    function testSubAccounts() external {
        // Remove vanilla USDC position.
        cellar.removePosition(1, false);

        // Add liquid euler position.
        uint32 eUSDCPosition1 = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eUSDC, 1), 0, 0);

        // Reconfigure cellar so it has 1 liquid euler position and an illiquid one.
        cellar.addPosition(1, eUSDCPosition1, abi.encode(0), false);

        // Make the liquid euler position the holding position.
        cellar.setHoldingPosition(eUSDCPosition1);

        // Deposit into Euler.
        uint256 assets = 200e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        assertApproxEqAbs(
            eUSDC.balanceOfUnderlying(_getSubAccount(address(cellar), 1)),
            assets,
            1,
            "USDC should have been deposited into sub account 1."
        );

        assertEq(
            eUSDC.balanceOfUnderlying(_getSubAccount(address(cellar), 0)),
            0,
            "USDC should not have been deposited into sub account 0."
        );

        uint256 eUSDCBalance = eUSDC.balanceOf(_getSubAccount(address(cellar), 1));

        // Strategist moves half of assets into sub account 0, enter markets for 0, then self borrows.
        {
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
            bytes[] memory adaptorCalls0 = new bytes[](2);
            adaptorCalls0[0] = _createBytesDataToEnterMarket(eUSDC, 0);
            adaptorCalls0[1] = _createBytesDataToTransferBetweenAccounts(eUSDC, 1, 0, eUSDCBalance / 2);
            bytes[] memory adaptorCalls1 = new bytes[](1);
            adaptorCalls1[0] = _createBytesDataToSelfBorrow(address(USDC), 0, assets);

            data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls0 });
            data[1] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls1 });
            cellar.callOnAdaptor(data);
        }

        // Users can still withdraw.
        uint256 withdrawable = cellar.maxWithdraw(address(this));
        assertApproxEqAbs(withdrawable, assets / 2, 1, "Withdrawable should equal half of assets.");

        assertApproxEqAbs(
            eUSDC.balanceOfUnderlying(_getSubAccount(address(cellar), 1)),
            assets / 2,
            1,
            "USDC should have been moved from sub account 1."
        );

        assertApproxEqAbs(
            eUSDC.balanceOfUnderlying(_getSubAccount(address(cellar), 0)),
            assets.mulDivDown(1.5e18, 1e18),
            1,
            "USDC should be set as collateral in sub account 0."
        );

        assertApproxEqAbs(
            dUSDC.balanceOf(_getSubAccount(address(cellar), 0)),
            assets,
            1,
            "Sub Account 0 should have assets worth of USDC debt."
        );

        assertEq(dUSDC.balanceOf(_getSubAccount(address(cellar), 1)), 0, "Sub Account 1 should have zero USDC debt.");
    }

    function _createBytesDataToEnterMarket(IEulerEToken eToken, uint256 subAccountId)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(EulerETokenAdaptor.enterMarket.selector, eToken, subAccountId);
    }

    function _createBytesDataToExitMarket(IEulerEToken eToken, uint256 subAccountId)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(EulerETokenAdaptor.exitMarket.selector, eToken, subAccountId);
    }

    function _createBytesDataToBorrow(IEulerDToken debtTokenToBorrow, uint256 amountToBorrow)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodeWithSelector(EulerDebtTokenAdaptor.borrowFromEuler.selector, debtTokenToBorrow, amountToBorrow);
    }

    function _createBytesDataToSelfBorrow(
        address target,
        uint256 subAccountId,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(EulerDebtTokenAdaptor.selfBorrow.selector, target, subAccountId, amount);
    }

    function _createBytesDataToTransferBetweenAccounts(
        IEulerEToken eToken,
        uint256 from,
        uint256 to,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                EulerETokenAdaptor.transferETokensBetweenSubAccounts.selector,
                eToken,
                from,
                to,
                amount
            );
    }

    function _getSubAccount(address primary, uint256 subAccountId) internal pure returns (address) {
        require(subAccountId < 256, "e/sub-account-id-too-big");
        return address(uint160(primary) ^ uint160(subAccountId));
    }
}
