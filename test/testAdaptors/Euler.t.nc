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

// TODO This test is no longer needed, as no future cellars will be using Euelr finance

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
  ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
  ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
  ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

  IEulerMarkets private markets = IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
  address private euler = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
  IEulerExec private exec = IEulerExec(0x59828FdF7ee634AaaD3f58B19fDBa3b03E2D9d80);

  IEulerEToken private eUSDC;
  IEulerEToken private eDAI;
  IEulerEToken private eUSDT;
  IEulerEToken private eWETH;
  IEulerEToken private eWBTC;

  IEulerDToken private dUSDC;
  IEulerDToken private dDAI;
  IEulerDToken private dUSDT;
  IEulerDToken private dWETH;
  IEulerDToken private dWBTC;

  address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

  // Chainlink PriceFeeds
  address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
  address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
  address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
  address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
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
    eDAI = IEulerEToken(markets.underlyingToEToken(address(DAI)));
    eUSDT = IEulerEToken(markets.underlyingToEToken(address(USDT)));
    eWETH = IEulerEToken(markets.underlyingToEToken(address(WETH)));
    eWBTC = IEulerEToken(markets.underlyingToEToken(address(WBTC)));

    dUSDC = IEulerDToken(markets.underlyingToDToken(address(USDC)));
    dDAI = IEulerDToken(markets.underlyingToDToken(address(DAI)));
    dUSDT = IEulerDToken(markets.underlyingToDToken(address(USDT)));
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

    price = uint256(IChainlinkAggregator(DAI_USD_FEED).latestAnswer());
    settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
    priceRouter.addAsset(DAI, settings, abi.encode(stor), price);

    price = uint256(IChainlinkAggregator(USDT_USD_FEED).latestAnswer());
    settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
    priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

    price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
    settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
    priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

    // Setup Cellar:
    // Cellar positions array.
    uint32[] memory positions = new uint32[](2);
    uint32[] memory debtPositions = new uint32[](1);

    // Add adaptors and positions to the registry.
    registry.trustAdaptor(address(erc20Adaptor));
    registry.trustAdaptor(address(eulerETokenAdaptor));
    registry.trustAdaptor(address(eulerDebtTokenAdaptor));

    usdcPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));
    eUSDCPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eUSDC, 0));
    debtUSDCPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dUSDC, 0));

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

    cellar.addAdaptorToCatalogue(address(eulerETokenAdaptor));
    cellar.addAdaptorToCatalogue(address(eulerDebtTokenAdaptor));

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
      adaptorCalls0[0] = _createBytesDataToEnterMarket(USDC, 0);
      bytes[] memory adaptorCalls1 = new bytes[](1);
      adaptorCalls1[0] = _createBytesDataToBorrow(USDC, 0, assets / 2);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls0 });
      data[1] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls1 });
      cellar.callOnAdaptor(data);
    }

    // User Withdraws should now revert.
    uint256 assetsToWithdraw = cellar.maxWithdraw(address(this));
    // Since the USDC loan is just sitting in the cellar, we should only be able to withdraw that.
    uint256 expectedAssetsWithdrawable = assets / 2;
    assertEq(assetsToWithdraw, expectedAssetsWithdrawable, "There should be assets / 2 withdrawable.");

    // Calling exitMarket should revert.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
      bytes[] memory adaptorCalls = new bytes[](1);
      adaptorCalls[0] = _createBytesDataToExitMarket(USDC, 0);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls });
      vm.expectRevert(bytes("e/outstanding-borrow"));
      cellar.callOnAdaptor(data);
    }

    // Have strategist repay debt.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
      bytes[] memory adaptorCalls = new bytes[](1);
      adaptorCalls[0] = _createBytesDataToRepay(USDC, 0, assets / 2);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls });
      cellar.callOnAdaptor(data);
    }

    assertEq(dUSDC.balanceOf(_getSubAccount(address(cellar), 0)), 0, "Sub Account 0 should have zero USDC debt.");
  }

  function testSelfBorrowAndSelfRepay() external {
    // Deposit into Euler.
    uint256 assets = 100e6;
    deal(address(USDC), address(this), assets);
    cellar.deposit(assets, address(this));

    uint256 totalAssetsBefore = cellar.totalAssets();

    // Enter market and self borrow  2x USDC assets.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
      bytes[] memory adaptorCalls0 = new bytes[](1);
      adaptorCalls0[0] = _createBytesDataToEnterMarket(USDC, 0);
      bytes[] memory adaptorCalls1 = new bytes[](1);
      adaptorCalls1[0] = _createBytesDataToSelfBorrow(USDC, 0, 2 * assets);

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

    // Have strategist close out mint position.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
      bytes[] memory adaptorCalls = new bytes[](1);
      adaptorCalls[0] = _createBytesDataToSelfRepay(USDC, 0, 2 * assets);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls });
      cellar.callOnAdaptor(data);
    }

    assertApproxEqAbs(cellar.totalAssets(), totalAssetsBefore, 1, "Cellar Total Assets should be unchanged.");
    assertApproxEqAbs(
      eUSDC.balanceOfUnderlying(address(cellar)),
      assets,
      1,
      "Cellar eUSDC balance should be equal to assets deposited."
    );
    assertEq(dUSDC.balanceOf(address(cellar)), 0, "Cellar dUSDC balance should be zero.");
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
      adaptorCalls0[0] = _createBytesDataToEnterMarket(USDC, 0);
      adaptorCalls0[1] = _createBytesDataToTransferBetweenAccounts(USDC, 1, 0, eUSDCBalance / 2);
      bytes[] memory adaptorCalls1 = new bytes[](1);
      adaptorCalls1[0] = _createBytesDataToSelfBorrow(USDC, 0, assets);

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

  function testDelegate() external {
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
      bytes[] memory adaptorCalls = new bytes[](1);
      adaptorCalls[0] = _createBytesDataToDelegate(address(this));

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls });
      cellar.callOnAdaptor(data);
    }
  }

  function testTakingOutLoansIntoUntrackedPositions() external {
    // Deposit into Euler.
    uint256 assets = 100e6;
    deal(address(USDC), address(this), assets);
    cellar.deposit(assets, address(this));

    // Strategists enters USDC market.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
      bytes[] memory adaptorCalls = new bytes[](1);
      adaptorCalls[0] = _createBytesDataToEnterMarket(USDC, 0);
      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls });

      cellar.callOnAdaptor(data);
    }

    // Strategsit tries to take out a loan in an untracked asset.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
      bytes[] memory adaptorCalls = new bytes[](1);
      adaptorCalls[0] = _createBytesDataToBorrow(USDT, 0, assets / 2);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls });
      vm.expectRevert(
        bytes(
          abi.encodeWithSelector(
            EulerDebtTokenAdaptor.EulerDebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
            address(dUSDT)
          )
        )
      );
      cellar.callOnAdaptor(data);
    }

    // Strategist tries to self borrow into unsupported debt position.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
      bytes[] memory adaptorCalls = new bytes[](1);
      adaptorCalls[0] = _createBytesDataToSelfBorrow(USDT, 0, 2 * assets);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls });
      vm.expectRevert(
        bytes(
          abi.encodeWithSelector(
            EulerDebtTokenAdaptor.EulerDebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
            address(dUSDT)
          )
        )
      );
      cellar.callOnAdaptor(data);
    }

    // Strategist tries to take out a loan in an untracked sub account.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
      bytes[] memory adaptorCalls = new bytes[](1);
      adaptorCalls[0] = _createBytesDataToBorrow(USDC, 1, assets / 2);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls });
      vm.expectRevert(
        bytes(
          abi.encodeWithSelector(
            EulerDebtTokenAdaptor.EulerDebtTokenAdaptor__DebtPositionsMustBeTracked.selector,
            address(dUSDC)
          )
        )
      );
      cellar.callOnAdaptor(data);
    }
  }

  function testMovingAssetsIntoUntrackedSubAccounts() external {
    // Deposit into Euler.
    uint256 assets = 100e6;
    deal(address(USDC), address(this), assets);
    cellar.deposit(assets, address(this));

    uint256 eUSDCBalance = eUSDC.balanceOf(address(cellar));
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
      bytes[] memory adaptorCalls = new bytes[](1);
      adaptorCalls[0] = _createBytesDataToTransferBetweenAccounts(USDC, 0, 1, eUSDCBalance / 2);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls });
      vm.expectRevert(
        bytes(
          abi.encodeWithSelector(
            Cellar.Cellar__TotalAssetDeviatedOutsideRange.selector,
            assets / 2,
            assets.mulDivDown(0.9997e18, 1e18),
            assets.mulDivDown(1.0003e18, 1e18) - 1
          )
        )
      );
      cellar.callOnAdaptor(data);
    }
  }

  function testLeveragedUSDC() external {
    // Remove vanilla USDC position.
    cellar.removePosition(1, false);

    // Add liquid euler position.
    uint32 eUSDCPosition1 = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eUSDC, 1), 0, 0);

    // Reconfigure cellar so it has 1 liquid euler position and an illiquid one.
    cellar.addPosition(1, eUSDCPosition1, abi.encode(0), false);

    // Make the liquid euler position the holding position.
    cellar.setHoldingPosition(eUSDCPosition1);

    // Deposit into Euler.
    uint256 assets = 1_000_000e6;
    deal(address(USDC), address(this), assets);
    cellar.deposit(assets, address(this));

    _checkLeveragedPosition(assets, cellar, USDC, 10);
  }

  function testLeveragedWETH() external {
    uint32 eWETHPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eWETH, 0), 0, 0);
    uint32 eWETHPosition1 = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eWETH, 1), 0, 0);
    uint32 debtWETHPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dWETH, 0), 0, 0);

    uint32[] memory positions = new uint32[](2);
    uint32[] memory debtPositions = new uint32[](1);

    positions[0] = eWETHPosition1;
    positions[1] = eWETHPosition;

    debtPositions[0] = debtWETHPosition;

    bytes[] memory positionConfigs = new bytes[](2);
    bytes[] memory debtConfigs = new bytes[](1);

    Cellar leveragedCellar = new Cellar(
      registry,
      WETH,
      "Euler Cellar",
      "EULER-CLR",
      abi.encode(
        positions,
        debtPositions,
        positionConfigs,
        debtConfigs,
        eWETHPosition1,
        address(0),
        type(uint128).max,
        type(uint128).max
      )
    );

    leveragedCellar.addAdaptorToCatalogue(address(eulerETokenAdaptor));
    leveragedCellar.addAdaptorToCatalogue(address(eulerDebtTokenAdaptor));

    // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
    stdstore.target(address(leveragedCellar)).sig(leveragedCellar.shareLockPeriod.selector).checked_write(uint256(0));

    // Deposit into Euler.
    uint256 assets = 1_000e18;
    WETH.approve(address(leveragedCellar), assets);
    deal(address(WETH), address(this), assets);
    leveragedCellar.deposit(assets, address(this));

    _checkLeveragedPosition(assets, leveragedCellar, WETH, 10);
  }

  function testETokenAndDebtTokenPositions() external {
    // Adjust rebalance deviation so we can make larger positions changes in less TXs.
    cellar.setRebalanceDeviation(0.02e18);
    // Remove dUSDC position.
    cellar.removePosition(0, true);
    uint32 debtWETHPosition = registry.trustPosition(address(eulerDebtTokenAdaptor), abi.encode(dWETH, 0), 0, 0);

    cellar.addPosition(0, debtWETHPosition, abi.encode(0), true);

    // Deposit into Euler.
    uint256 assets = 1_000_000e6;
    deal(address(USDC), address(this), assets);
    cellar.deposit(assets, address(this));

    // Strategist enters USDC market, borrows WETH, and sells it.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
      bytes[] memory adaptorCalls0 = new bytes[](1);
      adaptorCalls0[0] = _createBytesDataToEnterMarket(USDC, 0);

      bytes[] memory adaptorCalls1 = new bytes[](2);
      uint256 amountToBorrow = priceRouter.getValue(USDC, assets / 2, WETH);
      adaptorCalls1[0] = _createBytesDataToBorrow(WETH, 0, amountToBorrow);
      adaptorCalls1[1] = _createBytesDataForSwap(WETH, USDC, 500, amountToBorrow);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls0 });
      data[1] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls1 });
      cellar.callOnAdaptor(data);
    }

    // Strategist repays some of WETH loan using collateral.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
      bytes[] memory adaptorCalls0 = new bytes[](1);
      adaptorCalls0[0] = _createBytesDataToWithdraw(USDC, 0, assets / 10);

      bytes[] memory adaptorCalls1 = new bytes[](1);
      adaptorCalls1[0] = _createBytesDataToSwapAndRepay(USDC, 0, WETH, 500, assets / 10);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls0 });
      data[1] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls1 });
      cellar.callOnAdaptor(data);
    }

    // Setup WETH as a position in the cellar.
    uint32 wethPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(WETH), 0, 0);
    cellar.addPosition(1, wethPosition, abi.encode(0), false);

    // Strategist repays remaining loan.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
      uint256 USDCToSwap = USDC.balanceOf(address(cellar));
      bytes[] memory adaptorCalls = new bytes[](2);
      adaptorCalls[0] = _createBytesDataForSwap(USDC, WETH, 500, USDCToSwap);
      adaptorCalls[1] = _createBytesDataToRepay(WETH, 0, type(uint256).max);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls });
      cellar.callOnAdaptor(data);
    }

    assertEq(dWETH.balanceOf(address(cellar)), 0, "Cellar should have no WETH debt.");
  }

  function testETokenPositionsWithNoDebt() external {
    // Remove vanilla USDC position, and dUSDC position.
    cellar.removePosition(1, false);
    cellar.removePosition(0, true);

    // Add liquid euler positions.
    uint32 eDAIPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eDAI, 0), 0, 0);
    uint32 eUSDTPosition = registry.trustPosition(address(eulerETokenAdaptor), abi.encode(eUSDT, 0), 0, 0);

    // Reconfigure cellar so it has 1 liquid euler position and an illiquid one.
    cellar.addPosition(1, eDAIPosition, abi.encode(0), false);
    cellar.addPosition(2, eUSDTPosition, abi.encode(0), false);

    // Deposit into Euler.
    uint256 assets = 1_000_000e6;
    deal(address(USDC), address(this), assets);
    cellar.deposit(assets, address(this));

    // Strategist moves assets into eDAI and eUSDT positions.
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
      bytes[] memory adaptorCalls = new bytes[](6);
      adaptorCalls[0] = _createBytesDataToWithdraw(USDC, 0, type(uint256).max);
      adaptorCalls[1] = _createBytesDataForSwap(USDC, DAI, 500, assets / 3);
      adaptorCalls[2] = _createBytesDataForSwap(USDC, USDT, 500, assets / 3);
      adaptorCalls[3] = _createBytesDataToDeposit(DAI, 0, type(uint256).max);
      adaptorCalls[4] = _createBytesDataToDeposit(USDT, 0, type(uint256).max);
      adaptorCalls[5] = _createBytesDataToDeposit(USDC, 0, type(uint256).max);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls });
      cellar.callOnAdaptor(data);
    }

    uint256 cellarAssets = cellar.totalAssets();
    assertApproxEqRel(cellarAssets, assets, 0.0001e18, "Total assets should be relatively unchanged.");

    // Pass some time to earn interest.
    vm.warp(block.timestamp + 1 days / 4);
    assertGt(cellar.totalAssets(), cellarAssets, "Assets should have increased.");

    cellarAssets = cellar.totalAssets();

    // Positions should be fully withdrawable.
    uint256 maxWithdraw = cellar.maxWithdraw(address(this));
    assertApproxEqAbs(maxWithdraw, cellarAssets, 1, "All assets should be withdrawable.");

    cellar.withdraw(maxWithdraw, address(this), address(this));

    // Caller should have USDC, DAI, and USDT.
    assertGt(USDC.balanceOf(address(this)), 0, "USDC balance should be greater than zero.");
    assertGt(DAI.balanceOf(address(this)), 0, "DAI balance should be greater than zero.");
    assertGt(USDT.balanceOf(address(this)), 0, "USDT balance should be greater than zero.");
  }

  function _checkLeveragedPosition(
    uint256 assets,
    Cellar leveragedCellar,
    ERC20 leveragedAsset,
    uint256 targetLeverage
  ) internal {
    // Strategist moves half of assets into sub account 0, enter markets for 0, then self borrows.
    IEulerEToken eToken = IEulerEToken(markets.underlyingToEToken(address(leveragedAsset)));
    uint256 eTokensToTransfer = eToken.balanceOf(_getSubAccount(address(leveragedCellar), 1)).mulDivDown(9, 10);
    {
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
      bytes[] memory adaptorCalls0 = new bytes[](2);
      adaptorCalls0[0] = _createBytesDataToEnterMarket(leveragedAsset, 0);
      adaptorCalls0[1] = _createBytesDataToTransferBetweenAccounts(leveragedAsset, 1, 0, eTokensToTransfer);
      bytes[] memory adaptorCalls1 = new bytes[](1);
      adaptorCalls1[0] = _createBytesDataToSelfBorrow(leveragedAsset, 0, targetLeverage * assets);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls0 });
      data[1] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls1 });
      leveragedCellar.callOnAdaptor(data);
    }

    // Cellar Withdrawable assets drops to 10% of assets deposited.
    uint256 expectedWithdrawable = assets / 10;
    assertApproxEqAbs(
      leveragedCellar.maxWithdraw(address(this)),
      expectedWithdrawable,
      1,
      "maxWithdraw should equal 10% of assets."
    );

    // User withdraws as much as they can.
    uint256 userWithdrawAmount = leveragedCellar.maxWithdraw(address(this));
    leveragedCellar.withdraw(userWithdrawAmount, address(this), address(this));

    expectedWithdrawable = 0;
    assertApproxEqAbs(
      leveragedCellar.maxWithdraw(address(this)),
      expectedWithdrawable,
      1,
      "maxWithdraw should be zero."
    );

    // Strategist deleverages and moves funds to liquid eToken position.
    {
      eTokensToTransfer = eTokensToTransfer.mulDivDown(1, 10);
      Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
      bytes[] memory adaptorCalls0 = new bytes[](1);
      adaptorCalls0[0] = _createBytesDataToSelfRepay(leveragedAsset, 0, (targetLeverage * assets) / 2);
      bytes[] memory adaptorCalls1 = new bytes[](1);
      adaptorCalls1[0] = _createBytesDataToTransferBetweenAccounts(leveragedAsset, 0, 1, eTokensToTransfer);

      data[0] = Cellar.AdaptorCall({ adaptor: address(eulerDebtTokenAdaptor), callData: adaptorCalls0 });
      data[1] = Cellar.AdaptorCall({ adaptor: address(eulerETokenAdaptor), callData: adaptorCalls1 });
      leveragedCellar.callOnAdaptor(data);
    }

    // Cellar Withdrawable assets drops to 9% of assets deposited.
    expectedWithdrawable = assets.mulDivDown(9, 100);
    assertApproxEqAbs(
      leveragedCellar.maxWithdraw(address(this)),
      expectedWithdrawable,
      1,
      "maxWithdraw should equal 9% of assets."
    );

    // User withdraws as much as they can.
    userWithdrawAmount = leveragedCellar.maxWithdraw(address(this));
    leveragedCellar.withdraw(userWithdrawAmount, address(this), address(this));

    expectedWithdrawable = 0;
    assertApproxEqAbs(
      leveragedCellar.maxWithdraw(address(this)),
      expectedWithdrawable,
      1,
      "maxWithdraw should be zero."
    );
  }

  function _createBytesDataToSwapAndRepay(
    ERC20 from,
    uint256 subAccountId,
    ERC20 underlying,
    uint24 fee,
    uint256 amount
  ) internal pure returns (bytes memory) {
    address[] memory path = new address[](2);
    path[0] = address(from);
    path[1] = address(underlying);
    uint24[] memory poolFees = new uint24[](1);
    poolFees[0] = fee;
    bytes memory params = abi.encode(path, poolFees, amount, 0);
    return
      abi.encodeWithSelector(
        EulerDebtTokenAdaptor.swapAndRepay.selector,
        from,
        subAccountId,
        underlying,
        amount,
        SwapRouter.Exchange.UNIV3,
        params
      );
  }

  function _createBytesDataForSwap(
    ERC20 from,
    ERC20 to,
    uint24 poolFee,
    uint256 fromAmount
  ) internal pure returns (bytes memory) {
    address[] memory path = new address[](2);
    path[0] = address(from);
    path[1] = address(to);
    uint24[] memory poolFees = new uint24[](1);
    poolFees[0] = poolFee;
    bytes memory params = abi.encode(path, poolFees, fromAmount, 0);
    return abi.encodeWithSelector(BaseAdaptor.swap.selector, from, to, fromAmount, SwapRouter.Exchange.UNIV3, params);
  }

  function _createBytesDataToEnterMarket(ERC20 underlying, uint256 subAccountId) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(EulerETokenAdaptor.enterMarket.selector, underlying, subAccountId);
  }

  function _createBytesDataToExitMarket(ERC20 underlying, uint256 subAccountId) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(EulerETokenAdaptor.exitMarket.selector, underlying, subAccountId);
  }

  function _createBytesDataToDeposit(
    ERC20 underlying,
    uint256 subAccountId,
    uint256 amountToDeposit
  ) internal pure returns (bytes memory) {
    return
      abi.encodeWithSelector(EulerETokenAdaptor.depositToEuler.selector, underlying, subAccountId, amountToDeposit);
  }

  function _createBytesDataToWithdraw(
    ERC20 underlying,
    uint256 subAccountId,
    uint256 amountToWithdraw
  ) internal pure returns (bytes memory) {
    return
      abi.encodeWithSelector(EulerETokenAdaptor.withdrawFromEuler.selector, underlying, subAccountId, amountToWithdraw);
  }

  function _createBytesDataToBorrow(
    ERC20 underlying,
    uint256 subAccountId,
    uint256 amountToBorrow
  ) internal pure returns (bytes memory) {
    return
      abi.encodeWithSelector(EulerDebtTokenAdaptor.borrowFromEuler.selector, underlying, subAccountId, amountToBorrow);
  }

  function _createBytesDataToRepay(
    ERC20 underlying,
    uint256 subAccountId,
    uint256 amountToRepay
  ) internal pure returns (bytes memory) {
    return
      abi.encodeWithSelector(EulerDebtTokenAdaptor.repayEulerDebt.selector, underlying, subAccountId, amountToRepay);
  }

  function _createBytesDataToSelfBorrow(
    ERC20 target,
    uint256 subAccountId,
    uint256 amount
  ) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(EulerDebtTokenAdaptor.selfBorrow.selector, target, subAccountId, amount);
  }

  function _createBytesDataToSelfRepay(
    ERC20 target,
    uint256 subAccountId,
    uint256 amount
  ) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(EulerDebtTokenAdaptor.selfRepay.selector, target, subAccountId, amount);
  }

  function _createBytesDataToTransferBetweenAccounts(
    ERC20 underlying,
    uint256 from,
    uint256 to,
    uint256 amount
  ) internal pure returns (bytes memory) {
    return
      abi.encodeWithSelector(
        EulerETokenAdaptor.transferETokensBetweenSubAccounts.selector,
        underlying,
        from,
        to,
        amount
      );
  }

  function _createBytesDataToDelegate(address delegatee) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(EulerDebtTokenAdaptor.delegate.selector, delegatee);
  }

  function _getSubAccount(address primary, uint256 subAccountId) internal pure returns (address) {
    require(subAccountId < 256, "e/sub-account-id-too-big");
    return address(uint160(primary) ^ uint160(subAccountId));
  }
}
