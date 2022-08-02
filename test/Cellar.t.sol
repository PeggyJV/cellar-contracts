// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, SwapRouter, IGravity } from "src/base/Cellar.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { MockExchange } from "src/mocks/MockExchange.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { MockERC20WithTransferFee } from "src/mocks/MockERC20WithTransferFee.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";

import { Test, console, stdStorage, StdStorage } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";
import "src/Errors.sol";

contract CellarTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    MockCellar private cellar;
    MockGravity private gravity;

    MockExchange private exchange;
    MockPriceRouter private priceRouter;
    SwapRouter private swapRouter;

    Registry private registry;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    MockERC4626 private usdcCLR;

    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    MockERC4626 private wethCLR;

    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    MockERC4626 private wbtcCLR;

    ERC20 private LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    address private immutable strategist = vm.addr(0xBEEF);

    address private immutable cosmos = vm.addr(0xCAAA);

    function setUp() external {
        usdcCLR = new MockERC4626(USDC, "USDC Cellar LP Token", "USDC-CLR", 6);
        vm.label(address(usdcCLR), "usdcCLR");

        wethCLR = new MockERC4626(WETH, "WETH Cellar LP Token", "WETH-CLR", 18);
        vm.label(address(wethCLR), "wethCLR");

        wbtcCLR = new MockERC4626(WBTC, "WBTC Cellar LP Token", "WBTC-CLR", 8);
        vm.label(address(wbtcCLR), "wbtcCLR");

        // Setup Registry and modules:
        priceRouter = new MockPriceRouter();
        exchange = new MockExchange(priceRouter);
        swapRouter = new SwapRouter(IUniswapV2Router(address(exchange)), IUniswapV3Router(address(exchange)));
        gravity = new MockGravity();

        registry = new Registry(
            // Set this contract to the Gravity Bridge for testing to give the permissions usually
            // given to the Gravity Bridge to this contract.
            address(this),
            address(swapRouter),
            address(priceRouter)
        );

        // Setup exchange rates:
        // USDC Simulated Price: $1
        // WETH Simulated Price: $2000
        // WBTC Simulated Price: $30,000

        priceRouter.setExchangeRate(USDC, USDC, 1e6);
        priceRouter.setExchangeRate(WETH, WETH, 1e18);
        priceRouter.setExchangeRate(WBTC, WBTC, 1e8);

        priceRouter.setExchangeRate(USDC, WETH, 0.0005e18);
        priceRouter.setExchangeRate(WETH, USDC, 2000e6);

        priceRouter.setExchangeRate(USDC, WBTC, 0.00003333e8);
        priceRouter.setExchangeRate(WBTC, USDC, 30_000e6);

        priceRouter.setExchangeRate(WETH, WBTC, 0.06666666e8);
        priceRouter.setExchangeRate(WBTC, WETH, 15e18);

        // Setup Cellar:
        address[] memory positions = new address[](5);
        positions[0] = address(USDC);
        positions[1] = address(usdcCLR);
        positions[2] = address(wethCLR);
        positions[3] = address(wbtcCLR);
        positions[4] = address(WETH);

        Cellar.PositionType[] memory positionTypes = new Cellar.PositionType[](5);
        positionTypes[0] = Cellar.PositionType.ERC20;
        positionTypes[1] = Cellar.PositionType.ERC4626;
        positionTypes[2] = Cellar.PositionType.ERC4626;
        positionTypes[3] = Cellar.PositionType.ERC4626;
        positionTypes[4] = Cellar.PositionType.ERC20;

        cellar = new MockCellar(
            registry,
            USDC,
            positions,
            positionTypes,
            address(USDC),
            Cellar.WithdrawType.ORDERLY,
            "Multiposition Cellar LP Token",
            "multiposition-CLR"
        );
        vm.label(address(cellar), "cellar");

        // Mint enough liquidity to swap router for swaps.
        deal(address(USDC), address(exchange), type(uint224).max);
        deal(address(WETH), address(exchange), type(uint224).max);
        deal(address(WBTC), address(exchange), type(uint224).max);

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        WETH.approve(address(cellar), type(uint256).max);
        WBTC.approve(address(cellar), type(uint256).max);

        cellar.setStrategistPayoutAddress(strategist);
    }

    // ============================================ HELPER FUNCTIONS ============================================

    // For some reason `deal(address(position.asset()), address(position), assets)` isn't working at
    // the time of writing but dealing to this address is. This is a workaround.
    function simulateGains(address position, uint256 assets) internal {
        ERC20 asset = ERC4626(position).asset();

        deal(address(asset), address(this), assets);

        asset.safeTransfer(position, assets);
    }

    function simulateLoss(address position, uint256 assets) internal {
        ERC20 asset = ERC4626(position).asset();

        vm.prank(position);
        asset.approve(address(this), assets);

        asset.safeTransferFrom(position, address(1), assets);
    }

    function sendToCosmos(
        address asset,
        bytes32,
        uint256 assets
    ) external {
        ERC20(asset).transferFrom(msg.sender, cosmos, assets);
    }

    // ========================================= INITIALIZATION TEST =========================================
    //TODO constructor emit events if non immuatble storage variables are changed
    //testing initialization of contracts

    function testInitialization() external {}

    // ========================================= DEPOSIT/WITHDRAW TEST =========================================

    function testDepositAndWithdraw(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        deal(address(USDC), address(this), assets);

        (uint256 highWatermarkBeforeDeposit, , , , , , ) = cellar.feeData();

        // Test single deposit.
        uint256 expectedShares = cellar.previewDeposit(assets);
        uint256 shares = cellar.deposit(assets, address(this));

        uint256 expectedHighWatermark = highWatermarkBeforeDeposit + assets;

        (uint256 highWatermarkAfterDeposit, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterDeposit,
            expectedHighWatermark,
            "High watermark should equal high watermark before deposit plus assets deposited by user."
        );

        assertEq(shares, assets.changeDecimals(6, 18), "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assets), shares, "Withdrawing assets should burn shares given.");
        assertEq(shares, expectedShares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        (uint256 highWatermarkBeforeWithdraw, , , , , , ) = cellar.feeData();

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

        expectedHighWatermark = highWatermarkBeforeWithdraw - assets;

        (uint256 highWatermarkAfterWithdraw, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterWithdraw,
            expectedHighWatermark,
            "High watermark should equal high watermark before withdraw minus assets withdrawn by user."
        );

        assertEq(cellar.totalAssets(), 0, "Should have updated total assets with assets withdrawn.");
        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(USDC.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    function testMintAndRedeem(uint256 shares) external {
        shares = bound(shares, 1e18, type(uint112).max);

        deal(address(USDC), address(this), shares.changeDecimals(18, 6));

        (uint256 highWatermarkBeforeMint, , , , , , ) = cellar.feeData();

        // Test single mint.
        uint256 assets = cellar.mint(shares, address(this));

        uint256 expectedHighWatermark = highWatermarkBeforeMint + assets;

        (uint256 highWatermarkAfterMint, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterMint,
            expectedHighWatermark,
            "High watermark should equal high watermark before mint plus assets deposited by user."
        );

        assertEq(shares.changeDecimals(18, 6), assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewRedeem(shares), assets, "Redeeming shares should withdraw assets owed.");
        assertEq(cellar.previewMint(shares), assets, "Minting shares should deposit assets owed.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        (uint256 highWatermarkBeforeRedeem, , , , , , ) = cellar.feeData();

        // Test single redeem.
        cellar.redeem(shares, address(this), address(this));

        expectedHighWatermark = highWatermarkBeforeRedeem - assets;

        (uint256 highWatermarkAfterRedeem, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterRedeem,
            expectedHighWatermark,
            "High watermark should equal high watermark before redeem minus assets redeemed by user."
        );

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(USDC.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    function testFailDepositUsingAssetWithTransferFee() external {
        MockERC20 tokenWithTransferFee = MockERC20(address(new MockERC20WithTransferFee("TKN", 6)));

        stdstore.target(address(cellar)).sig(cellar.asset.selector).checked_write(address(tokenWithTransferFee));

        assertEq(
            address(cellar.asset()),
            address(tokenWithTransferFee),
            "Cellar asset should be token with transfer fee."
        );

        tokenWithTransferFee.mint(address(this), 100e6);
        tokenWithTransferFee.approve(address(cellar), 100e6);
        cellar.deposit(100e6, address(this));
    }

    function testFailMintUsingAssetWithTransferFee() external {
        MockERC20 tokenWithTransferFee = MockERC20(address(new MockERC20WithTransferFee("TKN", 6)));

        stdstore.target(address(cellar)).sig(cellar.asset.selector).checked_write(address(tokenWithTransferFee));

        assertEq(
            address(cellar.asset()),
            address(tokenWithTransferFee),
            "Cellar asset should be token with transfer fee."
        );

        tokenWithTransferFee.mint(address(this), 100e6);
        tokenWithTransferFee.approve(address(cellar), 100e6);
        cellar.mint(100e18, address(this));
    }

    function testWithdrawInOrder() external {
        cellar.depositIntoPosition(address(wethCLR), 1e18); // $2000
        cellar.depositIntoPosition(address(wbtcCLR), 1e8); // $30,000
        assertEq(cellar.totalAssets(), 32_000e6, "Should have updated total assets with assets deposited.");

        // Mint shares to user to redeem.
        deal(address(cellar), address(this), cellar.previewWithdraw(32_000e6));

        // Withdraw from position.
        uint256 shares = cellar.withdraw(32_000e6, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed all shares.");
        assertEq(shares, 32_000e18, "Should returned all redeemed shares.");
        assertEq(WETH.balanceOf(address(this)), 1e18, "Should have transferred position balance to user.");
        assertEq(WBTC.balanceOf(address(this)), 1e8, "Should have transferred position balance to user.");
        assertEq(cellar.totalAssets(), 0, "Should have emptied cellar.");
    }

    //TODO what if a position has a zero balance
    function testWithdrawInProportion() external {
        cellar.depositIntoPosition(address(wethCLR), 1e18); // $2000
        cellar.depositIntoPosition(address(wbtcCLR), 1e8); // $30,000

        assertEq(cellar.totalAssets(), 32_000e6, "Should have updated total assets with assets deposited.");
        assertEq(cellar.totalSupply(), 32_000e18);

        // Mint shares to user to redeem.
        deal(address(cellar), address(this), cellar.previewWithdraw(16_000e6));

        // Withdraw from position.
        cellar.setWithdrawType(Cellar.WithdrawType.PROPORTIONAL);
        uint256 shares = cellar.withdraw(16_000e6, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed all shares.");
        assertEq(shares, 16_000e18, "Should returned all redeemed shares.");
        assertEq(WETH.balanceOf(address(this)), 0.5e18, "Should have transferred position balance to user.");
        assertEq(WBTC.balanceOf(address(this)), 0.5e8, "Should have transferred position balance to user.");
        assertEq(cellar.totalAssets(), 16_000e6, "Should have half of assets remaining in cellar.");
    }

    function testWithdrawWithDuplicateReceivedAssets() external {
        MockERC4626 wethVault = new MockERC4626(WETH, "WETH Vault LP Token", "WETH-VLT", 18);
        cellar.trustPosition(address(wethVault), Cellar.PositionType.ERC4626);
        cellar.pushPosition(address(wethVault));

        cellar.depositIntoPosition(address(wethCLR), 1e18); // $2000
        cellar.depositIntoPosition(address(wethVault), 0.5e18); // $1000

        assertEq(cellar.totalAssets(), 3000e6, "Should have updated total assets with assets deposited.");
        assertEq(cellar.totalSupply(), 3000e18);

        // Mint shares to user to redeem.
        deal(address(cellar), address(this), cellar.previewWithdraw(3000e6));

        // Withdraw from position.
        uint256 shares = cellar.withdraw(3000e6, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed all shares.");
        assertEq(shares, 3000e18, "Should returned all redeemed shares.");
        assertEq(WETH.balanceOf(address(this)), 1.5e18, "Should have transferred position balance to user.");
        assertEq(cellar.totalAssets(), 0, "Should have no assets remaining in cellar.");
    }

    // ========================================== POSITIONS TEST ==========================================

    function testManagingPositions() external {
        uint256 positionLength = cellar.getPositions().length;

        // Check that `removePosition` actually removes it.
        cellar.removePosition(4);

        assertEq(
            positionLength - 1,
            cellar.getPositions().length,
            "Cellar positions array should be equal to previous length minus 1."
        );

        assertTrue(!cellar.isPositionUsed(address(WETH)), "`isPositionUsed` should be false for WETH.");

        // Check that `addPosition` actually adds it.
        cellar.addPosition(4, address(WETH));

        assertEq(
            positionLength,
            cellar.getPositions().length,
            "Cellar positions array should be equal to previous length."
        );

        assertEq(cellar.positions(4), address(WETH), "`positions[4]` should be WETH.");

        assertTrue(cellar.isPositionUsed(address(WETH)), "`isPositionUsed` should be true for WETH.");

        // Check that `popPosition` actually removes it.
        cellar.popPosition();

        assertEq(
            positionLength - 1,
            cellar.getPositions().length,
            "Cellar positions array should be equal to previous length minus 1."
        );

        assertTrue(!cellar.isPositionUsed(address(WETH)), "`isPositionUsed` should be false for WETH.");

        // Check that `pushPosition` actually adds it.
        cellar.pushPosition(address(WETH));

        assertEq(
            positionLength,
            cellar.getPositions().length,
            "Cellar positions array should be equal to previous length."
        );

        assertEq(cellar.positions(4), address(WETH), "`positions[4]` should be WETH.");

        assertTrue(cellar.isPositionUsed(address(WETH)), "`isPositionUsed` should be true for WETH.");

        // Check that `pushPosition` reverts if position is already used.
        vm.expectRevert(bytes(abi.encodeWithSelector(USR_PositionAlreadyUsed.selector, address(WETH))));
        cellar.pushPosition(address(WETH));

        // Check that `addPosition` reverts if position is already used.
        vm.expectRevert(bytes(abi.encodeWithSelector(USR_PositionAlreadyUsed.selector, address(WETH))));
        cellar.addPosition(4, address(WETH));

        // Give Cellar 1 wei of wETH.
        deal(address(WETH), address(cellar), 1);

        // Check that `removePosition` reverts if position has any funds in it.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(USR_PositionNotEmpty.selector, address(WETH), WETH.balanceOf(address(cellar))))
        );
        cellar.removePosition(4);

        // Check that `popPosition` reverts if position has any funds in it.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(USR_PositionNotEmpty.selector, address(WETH), WETH.balanceOf(address(cellar))))
        );
        cellar.popPosition();

        // Check that `pushPosition` reverts if position is not trusted.
        vm.expectRevert(bytes(abi.encodeWithSelector(USR_UntrustedPosition.selector, address(0))));
        cellar.pushPosition(address(0));

        // Check that `addPosition` reverts if position is not trusted.
        vm.expectRevert(bytes(abi.encodeWithSelector(USR_UntrustedPosition.selector, address(0))));
        cellar.addPosition(4, address(0));

        // Set Cellar wETH balance to 0.
        deal(address(WETH), address(cellar), 0);

        // Check that `swapPosition` works as expected.
        cellar.swapPositions(4, 2);
        assertEq(cellar.positions(4), address(wethCLR), "`positions[4]` should be wethCLR.");
        assertEq(cellar.positions(2), address(WETH), "`positions[2]` should be WETH.");

        //replace
        cellar.popPosition();

        cellar.replacePosition(2, address(wethCLR));

        assertEq(cellar.positions(2), address(wethCLR), "`positions[2]` should be wethCLR.");

        // Check that `replacePosition` reverts if new position is not trusted.
        vm.expectRevert(bytes(abi.encodeWithSelector(USR_UntrustedPosition.selector, address(0))));
        cellar.replacePosition(2, address(0));

        //TODO Check that `replacePosition` reverts if new position is already used.
    }

    //TODO Trust Position Tests

    // ========================================== REBALANCE TEST ==========================================

    function testRebalanceBetweenPositions(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        cellar.depositIntoPosition(address(usdcCLR), assets);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        uint256 assetsTo = cellar.rebalance(
            address(usdcCLR),
            address(wethCLR),
            assets,
            SwapRouter.Exchange.UNIV2, // Using a mock exchange to swap, this param does not matter.
            abi.encode(path, assets, 0, address(cellar), address(cellar))
        );

        assertEq(assetsTo, exchange.quote(assets, path), "Should received expected assets from swap.");
        assertEq(usdcCLR.balanceOf(address(cellar)), 0, "Should have rebalanced from position.");
        assertEq(wethCLR.balanceOf(address(cellar)), assetsTo, "Should have rebalanced to position.");
    }

    function testRebalanceBetweenERC20Positions(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), assets);

        // Deposit USDC into Cellar.
        cellar.deposit(assets, address(this));

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        uint256 assetsTo = cellar.rebalance(
            address(USDC),
            address(WETH),
            assets,
            SwapRouter.Exchange.UNIV2, // Using a mock exchange to swap, this param does not matter.
            abi.encode(path, assets, 0, address(cellar), address(cellar))
        );

        assertEq(assetsTo, exchange.quote(assets, path), "Should received expected assets from swap.");
        assertEq(USDC.balanceOf(address(cellar)), 0, "Should have rebalanced from position.");
        assertEq(WETH.balanceOf(address(cellar)), assetsTo, "Should have rebalanced to position.");
    }

    function testRebalanceToSamePosition(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        cellar.depositIntoPosition(address(usdcCLR), assets);

        uint256 assetsTo = cellar.rebalance(
            address(usdcCLR),
            address(usdcCLR),
            assets,
            SwapRouter.Exchange.UNIV2, // Will be ignored because no swap is necessary.
            abi.encode(0) // Will be ignored because no swap is necessary.
        );

        assertEq(assetsTo, assets, "Should received expected assets from swap.");
        assertEq(usdcCLR.balanceOf(address(cellar)), assets, "Should have not changed position balance.");
    }

    function testRebalancingToInvalidPosition() external {
        uint256 assets = 100e6;

        cellar.depositIntoPosition(address(usdcCLR), assets);

        vm.expectRevert(bytes(abi.encodeWithSelector(USR_InvalidPosition.selector, address(0))));
        cellar.rebalance(
            address(usdcCLR),
            address(0), // An Invalid Position
            assets,
            SwapRouter.Exchange.UNIV2, // Will be ignored because no swap is necessary.
            abi.encode(0) // Will be ignored because no swap is necessary.
        );
    }

    function testRebalanceWithInvalidSwapAmount() external {
        uint256 assets = 100e6;

        // Check that encoding the swap prarms with the wrong amount of assets reverts the rebalance call.
        uint256 invalidAssets = assets - 1;

        cellar.depositIntoPosition(address(usdcCLR), assets);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        vm.expectRevert(bytes(abi.encodeWithSelector(STATE_WrongSwapParams.selector)));
        cellar.rebalance(
            address(usdcCLR),
            address(wethCLR),
            assets,
            SwapRouter.Exchange.UNIV2, // Using a mock exchange to swap, this param does not matter.
            abi.encode(path, invalidAssets, 0, address(cellar), address(cellar))
        );
    }

    // ======================================== EMERGENCY TESTS ========================================

    function testShutdown() external {
        cellar.initiateShutdown();

        assertTrue(cellar.isShutdown(), "Should have initiated shutdown.");

        cellar.liftShutdown();

        assertFalse(cellar.isShutdown(), "Should have lifted shutdown.");
    }

    function testWithdrawingWhileShutdown() external {
        deal(address(USDC), address(this), 1);
        cellar.deposit(1, address(this));

        cellar.initiateShutdown();

        cellar.withdraw(1, address(this), address(this));

        assertEq(USDC.balanceOf(address(this)), 1, "Should withdraw while shutdown.");
    }

    function testProhibitedActionsWhileShutdown() external {
        uint256 assets = 100e6;

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), assets);

        // Deposit USDC into Cellar.
        cellar.deposit(assets, address(this));

        cellar.initiateShutdown();

        deal(address(USDC), address(this), 1);

        vm.expectRevert(bytes(abi.encodeWithSelector(STATE_ContractShutdown.selector)));
        cellar.deposit(1, address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(STATE_ContractShutdown.selector)));
        cellar.addPosition(5, address(0));

        vm.expectRevert(bytes(abi.encodeWithSelector(STATE_ContractShutdown.selector)));
        cellar.pushPosition(address(0));

        vm.expectRevert(bytes(abi.encodeWithSelector(STATE_ContractShutdown.selector)));
        cellar.replacePosition(2, address(0));

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        //TODO should rebalancing be prohibited when shut down?
        //vm.expectRevert(bytes(abi.encodeWithSelector(STATE_ContractShutdown.selector)));
        //cellar.rebalance(
        //    address(USDC),
        //    address(WETH),
        //    assets,
        //    SwapRouter.Exchange.UNIV2, // Using a mock exchange to swap, this param does not matter.
        //    abi.encode(path, assets, 0, address(cellar), address(cellar))
        //);

        vm.expectRevert(bytes(abi.encodeWithSelector(STATE_ContractShutdown.selector)));
        cellar.initiateShutdown();
    }

    // ========================================= LIMITS TESTS =========================================

    function testLimits(uint256 amount) external {
        amount = bound(amount, 1, type(uint72).max);

        deal(address(USDC), address(this), amount);
        USDC.approve(address(cellar), amount);
        cellar.deposit(amount, address(this));

        assertEq(cellar.maxDeposit(address(this)), type(uint256).max, "Should have no max deposit.");
        assertEq(cellar.maxMint(address(this)), type(uint256).max, "Should have no max mint.");

        cellar.setDepositLimit(amount * 2);
        cellar.setLiquidityLimit(amount / 2);

        assertEq(cellar.depositLimit(), amount * 2, "Should have changed the deposit limit.");
        assertEq(cellar.liquidityLimit(), amount / 2, "Should have changed the liquidity limit.");
        assertEq(cellar.maxDeposit(address(this)), 0, "Should have reached new max deposit.");
        assertEq(cellar.maxMint(address(this)), 0, "Should have reached new max mint.");

        cellar.setLiquidityLimit(amount * 3);

        assertEq(cellar.maxDeposit(address(this)), amount, "Should not have reached new max deposit.");
        assertEq(cellar.maxMint(address(this)), amount.changeDecimals(6, 18), "Should not have reached new max mint.");

        address otherUser = vm.addr(1);

        assertEq(cellar.maxDeposit(otherUser), amount * 2, "Should have different max deposits for other user.");
        assertEq(
            cellar.maxMint(otherUser),
            (amount * 2).changeDecimals(6, 18),
            "Should have different max mint for other user."
        );

        // Hit global liquidity limit and deposit limit for other user.
        vm.startPrank(otherUser);
        deal(address(USDC), address(otherUser), amount * 2);
        //USDC.mint(otherUser, amount * 2);
        USDC.approve(address(cellar), amount * 2);
        cellar.deposit(amount * 2, otherUser);
        vm.stopPrank();

        assertEq(cellar.maxDeposit(address(this)), 0, "Should have hit liquidity limit for max deposit.");
        assertEq(cellar.maxMint(address(this)), 0, "Should have hit liquidity limit for max mint.");

        // Reduce liquidity limit by withdrawing.
        cellar.withdraw(amount, address(this), address(this));

        assertEq(cellar.maxDeposit(address(this)), amount, "Should have reduced liquidity limit for max deposit.");
        assertEq(
            cellar.maxMint(address(this)),
            amount.changeDecimals(6, 18),
            "Should have reduced liquidity limit for max mint."
        );
        assertEq(
            cellar.maxDeposit(otherUser),
            0,
            "Should have not changed max deposit for other user because they are still at the deposit limit."
        );
        assertEq(
            cellar.maxMint(otherUser),
            0,
            "Should have not changed max mint for other user because they are still at the deposit limit."
        );

        cellar.initiateShutdown();

        assertEq(cellar.maxDeposit(address(this)), 0, "Should show no assets can be deposited when shutdown.");
        assertEq(cellar.maxMint(address(this)), 0, "Should show no shares can be minted when shutdown.");
    }

    function testDepositAboveDepositLimit(uint256 amount) external {
        // Depositing above the deposit limit should revert.
        amount = bound(amount, 101e6, type(uint112).max);

        uint256 limit = 100e6;
        cellar.setDepositLimit(limit);

        deal(address(USDC), address(this), amount);

        vm.expectRevert(bytes(abi.encodeWithSelector(USR_DepositRestricted.selector, amount, limit)));
        cellar.deposit(amount, address(this));
    }

    function testMintAboveDepositLimit(uint256 amount) external {
        // Minting above the deposit limit should revert.
        amount = bound(amount, 101, type(uint112).max);

        uint256 limit = 100e6;
        cellar.setDepositLimit(limit);

        deal(address(USDC), address(this), amount * 1e6);

        vm.expectRevert(bytes(abi.encodeWithSelector(USR_DepositRestricted.selector, amount * 1e6, limit)));
        cellar.mint(amount * 1e18, address(this));
    }

    function testDepositAboveLiquidityLimit(uint256 amount) external {
        // Depositing above the deposit limit should revert.
        amount = bound(amount, 101e6, type(uint112).max);

        uint256 limit = 100e6;
        cellar.setLiquidityLimit(limit);

        deal(address(USDC), address(this), amount);

        vm.expectRevert(bytes(abi.encodeWithSelector(USR_DepositRestricted.selector, amount, limit)));
        cellar.deposit(amount, address(this));
    }

    function testMintAboveLiquidityLimit(uint256 amount) external {
        // Minting above the deposit limit should revert.
        amount = bound(amount, 101, type(uint112).max);

        uint256 limit = 100e6;
        cellar.setLiquidityLimit(limit);

        deal(address(USDC), address(this), amount * 1e6);

        vm.expectRevert(bytes(abi.encodeWithSelector(USR_DepositRestricted.selector, amount * 1e6, limit)));
        cellar.mint(amount * 1e18, address(this));
    }

    //TODO tests for setting the limit values

    // =========================================== TOTAL ASSETS TEST ===========================================

    function testTotalAssets(
        uint256 usdcAmount,
        uint256 usdcCLRAmount,
        uint256 wethCLRAmount,
        uint256 wbtcCLRAmount,
        uint256 wethAmount
    ) external {
        usdcAmount = bound(usdcAmount, 1e6, 1_000_000_000_000e6);
        usdcCLRAmount = bound(usdcCLRAmount, 1e6, 1_000_000_000_000e6);
        wethCLRAmount = bound(wethCLRAmount, 1e18, 200_000_000e18);
        wbtcCLRAmount = bound(wbtcCLRAmount, 1e8, 21_000_000e8);
        wethAmount = bound(wethAmount, 1e18, 200_000_000e18);
        uint256 totalAssets = cellar.totalAssets();

        assertEq(totalAssets, 0, "Cellar total assets should be zero.");

        cellar.depositIntoPosition(address(usdcCLR), usdcCLRAmount);
        cellar.depositIntoPosition(address(wethCLR), wethCLRAmount);
        cellar.depositIntoPosition(address(wbtcCLR), wbtcCLRAmount);
        deal(address(WETH), address(cellar), wethAmount);
        deal(address(USDC), address(cellar), usdcAmount);

        uint256 expectedTotalAssets = usdcAmount + usdcCLRAmount;
        expectedTotalAssets += (wethAmount + wethCLRAmount).mulDivDown(2_000e6, 1e18);
        expectedTotalAssets += wbtcCLRAmount.mulDivDown(30_000e6, 1e8);

        totalAssets = cellar.totalAssets();

        assertApproxEqAbs(
            totalAssets,
            expectedTotalAssets,
            1,
            "totalAssets should equal all asset values summed together."
        );
        (uint256 getDataTotalAssets, , , ) = cellar.getData();
        assertEq(getDataTotalAssets, totalAssets, "getData totalAssets should be the same as cellar totalAssets.");
    }

    // =========================================== PERFORMANCE/PLATFORM FEE TEST ===========================================

    function testChangingFeeData() external {
        //things like setting different platform cuts and confirming that the change does change stuff
        //should also emit events for any storage variables being changed
    }

    //chaning strategist payout address make sure it actuallychanges the location

    function testPreviewFunctionsAccountForPerformanceFee(uint256 deposit, uint256 yield) external {
        deposit = bound(deposit, 1_000e6, 100_000_000e6);
        // Cap yield to 100x deposit
        uint256 yieldUpperBound = 100 * deposit;
        // Floor yield above 1e-6x of the deposit
        uint256 yieldLowerBound = deposit / 1_000_000;
        yield = bound(yield, yieldLowerBound, yieldUpperBound);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), type(uint256).max);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        (uint256 currentHWM, , , , , , ) = cellar.feeData();
        assertEq(currentHWM, deposit, "High Watermark should be equal to deposits.");

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), deposit + yield);

        assertEq(
            cellar.previewMint(100e18),
            cellar.mint(100e18, address(this)),
            "`previewMint` should return the same as `mint`."
        );

        assertEq(
            cellar.previewDeposit(100e6),
            cellar.deposit(100e6, address(this)),
            "`previewDeposit` should return the same as `deposit`."
        );

        cellar.approve(address(cellar), type(uint256).max);
        assertEq(
            cellar.previewWithdraw(100e6),
            cellar.withdraw(100e6, address(this), address(this)),
            "`previewWithdraw` should return the same as `withdraw`."
        );

        assertEq(
            cellar.previewRedeem(100e18),
            cellar.redeem(100e18, address(this), address(this)),
            "`previewRedeem` should return the same as `redeem`."
        );
    }

    function testPerformanceFeesWithPositivePerformance(uint256 deposit, uint256 yield) external {
        deposit = bound(deposit, 100e6, 1_000_000e6);
        yield = bound(yield, 10e6, 10_000e6);
        (, , , , uint64 performanceFee, , ) = cellar.feeData();

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), 3 * deposit);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + yield);

        // Deposit into cellar to trigger performance fee calculation.
        cellar.deposit(deposit, address(this));

        uint256 feeSharesInCellar = cellar.balanceOf(address(cellar));
        assertTrue(feeSharesInCellar > 0, "Cellar should have been minted fee shares.");

        uint256 performanceFeeInAssets = cellar.previewRedeem(feeSharesInCellar);
        uint256 expectedPerformanceFeeInAssets = yield.mulWadDown(performanceFee);
        // It is okay for actual performance fee in assets to be equal to or 1 wei less than expected.
        assertTrue(
            performanceFeeInAssets == expectedPerformanceFeeInAssets ||
                performanceFeeInAssets + 1 == expectedPerformanceFeeInAssets,
            "Actual performance fees should equal expected, or actual can be 1 less wei than expected."
        );

        // Deposit into cellar to trigger performance fee calculation.
        cellar.deposit(deposit, address(this));

        assertTrue(
            feeSharesInCellar == cellar.balanceOf(address(cellar)),
            "Cellar should not have been minted more fee shares."
        );
    }

    function testPerformanceFeesWithNegativePerformance(uint256 deposit, uint256 loss) external {
        deposit = bound(deposit, 100_000e6, 1_000_000e6);
        loss = bound(loss, 10e6, 10_000e6);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), 2 * deposit);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Simulate Cellar losing yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) - loss);

        // Deposit into cellar to trigger performance fee calculation.
        cellar.deposit(deposit, address(this));

        assertTrue(cellar.balanceOf(address(cellar)) == 0, "Cellar should not have any fee shares.");
    }

    function testPerformanceFeesWithNeutralPerformance(uint256 deposit, uint256 amount) external {
        deposit = bound(deposit, 100_000e6, 1_000_000e6);
        amount = bound(amount, 10e6, 10_000e6);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), 2 * deposit);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + amount);

        // Simulate Cellar losing yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) - amount);

        // Deposit into cellar to trigger performance fee calculation.
        cellar.deposit(deposit, address(this)); //deposit into Cellar

        assertTrue(cellar.balanceOf(address(cellar)) == 0, "Cellar should not have any fee shares.");
    }

    function testPlatformFees(uint256 timePassed, uint256 deposit) external {
        // Cap timePassed to 1 year. Platform fees will be collected on the order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 1e6, 1_000_000_000e6);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), deposit);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Calculate expected platform fee.
        (, , uint64 strategistPlatformCut, uint64 platformFee, , , ) = cellar.feeData();
        uint256 expectedPlatformFee = (deposit * platformFee * timePassed) / (365 days * 1e18);

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Call `sendFees` to calculate pending platform fees, and distribute them to strategist, and Cosmos.
        cellar.sendFees();

        uint256 feesInAssetsSentToCosmos = USDC.balanceOf(cosmos);
        uint256 feesInAssetsSentToStrategist = cellar.previewRedeem(cellar.balanceOf(strategist));

        assertEq(
            feesInAssetsSentToCosmos,
            expectedPlatformFee.mulWadDown(1e18 - strategistPlatformCut),
            "Platform fee sent to Cosmos should be equal to expectedPlatformFee * (1 - strategistPlatformCut)."
        );

        uint256 expectedPlatformFeeInAssetsSentToStrategist = expectedPlatformFee.mulWadDown(strategistPlatformCut);
        // It is okay for actual fees sent to strategist to be equal to or 1 wei less than expected.
        assertTrue(
            feesInAssetsSentToStrategist == expectedPlatformFeeInAssetsSentToStrategist ||
                feesInAssetsSentToStrategist + 1 == expectedPlatformFeeInAssetsSentToStrategist,
            "Platform fee sent to strategist should be equal to expectedPlatformFee * (strategistPlatformCut)."
        );

        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have burned all performance fee shares.");
    }

    function testPlatformAndPerformanceFees(
        uint256 timePassed,
        uint256 deposit,
        uint256 yield
    ) external {
        // Cap timePassed to 1 year. Platform fees will be collected on the order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 1e6, 1_000_000_000e6);
        // Cap yield to 10,000% APR
        uint256 yieldUpperBound = 100 * deposit * (timePassed / 365 days);
        // Floor yield above 0.001% APR
        uint256 yieldLowerBound = (deposit * (timePassed / 365 days)) / 100_000;
        yield = bound(yield, yieldLowerBound, yieldUpperBound);
        (
            ,
            uint64 strategistPerformanceCut,
            uint64 strategistPlatformCut,
            uint64 platformFee,
            uint64 performanceFee,
            ,

        ) = cellar.feeData();

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), deposit);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + yield);

        (uint256 highWatermarkBeforeSendFees, , , , , , ) = cellar.feeData();

        // Call `sendFees` to calculate pending performance and platform fees, and distribute them to strategist, and Cosmos.
        cellar.sendFees();

        uint256 expectedPerformanceFees = yield.mulDivDown(performanceFee, 1e18);

        // Minting platform fees dilutes share price, so it also dilutes pending performance fees.
        uint256 expectedPerformanceFeesAdjustedForDilution = (expectedPerformanceFees *
            (1e18 - (platformFee * timePassed) / 365 days)) / 1e18;

        uint256 expectedPlatformFees = ((deposit + yield) * platformFee * timePassed) / (365 days * 1e18);

        uint256 expectedTotalFeesAdjustedForDilution = expectedPerformanceFeesAdjustedForDilution +
            expectedPlatformFees;

        uint256 feesInAssetsSentToCosmos = USDC.balanceOf(cosmos);
        uint256 feesInAssetsSentToStrategist = cellar.previewRedeem(cellar.balanceOf(strategist));

        assertApproxEqAbs(
            feesInAssetsSentToCosmos + feesInAssetsSentToStrategist,
            expectedTotalFeesAdjustedForDilution,
            1,
            "Fees in assets sent to Cosmos + fees in shares sent to strategist should equal the expected total fees after dilution."
        );

        assertApproxEqAbs(
            feesInAssetsSentToStrategist,
            expectedPlatformFees.mulWadDown(strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(strategistPerformanceCut),
            1,
            "Shares converted to assets sent to strategist should be equal to (total platform fees * strategistPlatformCut) + (total performance fees * strategist performance cut)."
        );

        assertApproxEqAbs(
            feesInAssetsSentToCosmos,
            expectedPlatformFees.mulWadDown(1e18 - strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(1e18 - strategistPerformanceCut),
            1,
            "Assets sent to Cosmos should be equal to (total platform fees * (1-strategistPlatformCut)) + (total performance fees * (1-strategist performance cut))."
        );

        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have burned all fee shares.");

        uint256 expectedHighWatermark = highWatermarkBeforeSendFees - feesInAssetsSentToCosmos;

        (uint256 highWatermarkAfterSendFees, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterSendFees,
            expectedHighWatermark,
            "High watermark should equal high watermark before send fees minus assets sent to Cosmos."
        );
    }

    function testResetHighWatermark(
        uint256 deposit,
        uint256 loss,
        uint256 gain
    ) external {
        deposit = bound(deposit, 100_000e6, 1_000_000e6);
        loss = bound(loss, 10e6, 10_000e6);
        gain = bound(gain, 10e6, 10_000e6);

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), (2 * deposit) + 1);

        // Deposit into the Cellar.
        cellar.deposit(deposit, address(this)); //deposit into Cellar

        // Simulate Cellar losing yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) - loss);

        // Deposit into the Cellar to check if performance fees are minted.
        cellar.deposit(deposit, address(this));

        assertEq(
            cellar.balanceOf(address(cellar)),
            0,
            "Cellar should have not been minted any performance fee shares."
        );

        // Reset Cellar's High Watermark value.
        cellar.resetHighWatermark();

        (uint256 currentHighWatermark, , , , uint64 performanceFee, , ) = cellar.feeData();
        uint256 expectedHighWatermark = 2 * deposit - loss;
        assertEq(
            currentHighWatermark,
            expectedHighWatermark,
            "Cellar should have reset high watermark to the current assets."
        );

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + gain);

        // Deposit into the Cellar to check that performance fees are minted.
        cellar.deposit(1, address(this));

        assertTrue(cellar.balanceOf(address(cellar)) > 0, "Cellar should have been minted performance fee shares.");

        uint256 expectedPerformanceFeeInAssets = gain.mulWadDown(performanceFee);

        // Cellars rounds down when using previewRedeem, so it is acceptable to be off by 1 wei.
        assertApproxEqAbs(
            cellar.previewRedeem(cellar.balanceOf(address(cellar))),
            expectedPerformanceFeeInAssets,
            1,
            "Cellar performance fee shares in assets should equal (gain * performanceFee)."
        );
    }

    function testPayoutNotSet() external {
        cellar.setStrategistPayoutAddress(address(0));
        vm.expectRevert(bytes(abi.encodeWithSelector(STATE_PayoutNotSet.selector)));
        cellar.sendFees();
    }

    // ======================================== INTEGRATION TESTS ========================================
    uint256 public saltIndex;

    function mutate(uint256 salt) internal returns (uint256) {
        saltIndex++;
        return uint256(keccak256(abi.encode(salt, saltIndex))) % 1e26;
    }

    function _changeMarketPrices(ERC20[] memory assets, uint256[] memory newPricesInUSD) internal {
        uint256 quoteIndex;
        uint256 exchangeRate;
        for (uint256 i = 0; i < assets.length; i++) {
            for (uint256 j = 1; j < assets.length; j++) {
                quoteIndex = i + j;
                if (quoteIndex >= assets.length) quoteIndex -= assets.length;
                exchangeRate = (10**assets[quoteIndex].decimals()).mulDivDown(
                    newPricesInUSD[i],
                    newPricesInUSD[quoteIndex]
                );
                priceRouter.setExchangeRate(assets[i], assets[quoteIndex], exchangeRate);
            }
        }
    }

    Enum Action
    function _userAction(address user, )

    function testMultipleMintDepositRedeemWithdrawWithGainsLossAndSendFees() external {
        uint8 salt = 100;
        // Initialize Scenario
        address alice = vm.addr(1);
        address bob = vm.addr(2);
        address sam = vm.addr(3);
        address mary = vm.addr(4);

        // Create new cellar with WETH, USDC, and WBTC positions.
        address[] memory positions = new address[](3);
        positions[0] = address(USDC);
        positions[1] = address(WETH);
        positions[2] = address(WBTC);

        Cellar.PositionType[] memory positionTypes = new Cellar.PositionType[](3);
        positionTypes[0] = Cellar.PositionType.ERC20;
        positionTypes[1] = Cellar.PositionType.ERC20;
        positionTypes[2] = Cellar.PositionType.ERC20;

        MockCellar assetManagementCellar = new MockCellar(
            registry,
            USDC,
            positions,
            positionTypes,
            address(USDC),
            Cellar.WithdrawType.ORDERLY,
            "Asset Management Cellar LP Token",
            "assetmanagement-CLR"
        );

        assetManagementCellar.setStrategistPayoutAddress(strategist);

        // Give users USDC to interact with the cellar.
        deal(address(USDC), alice, type(uint256).max);
        deal(address(USDC), bob, type(uint256).max);
        deal(address(USDC), sam, type(uint256).max);
        deal(address(USDC), mary, type(uint256).max);

        // Approve cellar to send user assets.
        vm.prank(alice);
        USDC.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(bob);
        USDC.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(sam);
        USDC.approve(address(assetManagementCellar), type(uint256).max);

        vm.prank(mary);
        USDC.approve(address(assetManagementCellar), type(uint256).max);

        // ====================== BEGIN SCENERIO ======================

        //===== Start Bull Market ====
        //check initialization values
        {
            uint256 amount = mutate(salt);
            amount = 100e6;
            uint256 shares;
            uint256 expectedHighWatermark = amount * 3;
            // Alice joins cellar using deposit.
            vm.startPrank(alice);
            assertEq(
                assetManagementCellar.previewDeposit(amount),
                shares = assetManagementCellar.deposit(amount, alice),
                "Deposit should be equal to previewDeposit"
            );
            assertEq(shares, assetManagementCellar.balanceOf(alice), "Alice should have got shares out from deposit.");
            vm.stopPrank();
            // Bob joins cellar using Mint.
            uint256 bobAssets = USDC.balanceOf(bob);
            vm.startPrank(bob);
            assertEq(
                assetManagementCellar.previewMint(shares),
                amount = assetManagementCellar.mint(shares, alice),
                "Mint should be equal to previewMint"
            );
            assertEq(
                amount,
                bobAssets - USDC.balanceOf(bob),
                "Bob should have `amount` of assets taken from his address."
            );
            vm.stopPrank();

            vm.startPrank(sam);
            assertEq(
                assetManagementCellar.previewDeposit(amount),
                shares = assetManagementCellar.deposit(amount, sam),
                "Deposit should be equal to previewDeposit"
            );
            // Sam withdraws half of his assets.
            assertEq(
                assetManagementCellar.previewWithdraw(amount / 2),
                shares = assetManagementCellar.withdraw(amount / 2, sam, sam),
                "Withdraw should be equal to previewWithdraw"
            );

            // Sam re-enters cellar with Mint
            assertEq(
                assetManagementCellar.previewMint(shares),
                amount = assetManagementCellar.mint(shares, sam),
                "Mint should be equal to previewMint"
            );
            vm.stopPrank();

            // High Watermark should be equal to amount * 3 and it should equal total assets.
            uint256 totalAssets = assetManagementCellar.totalAssets();
            (uint256 highWatermark, , , , , , ) = assetManagementCellar.feeData();
            assertEq(highWatermark, expectedHighWatermark, "High Watermark should equal expectedHighWatermark.");
            assertEq(
                highWatermark,
                totalAssets,
                "High Watermark should equal totalAssets because no yield was earned."
            );
            console.log("HWM:", highWatermark);
        }
        {
            // Strategy providers swaps into WETH and WBTC using USDC, targeting a 20/40/40 split(USDC/WETH/WBTC)
            uint256 totalAssets = assetManagementCellar.totalAssets();
            // Calculate 40% of assets to swap into WETH.
            uint256 usdcToSellForWETH = totalAssets.mulDivDown(4, 10);
            address[] memory path = new address[](2);
            path[0] = address(USDC);
            path[1] = address(WETH);

            uint256 assetsTo = assetManagementCellar.rebalance(
                address(USDC),
                address(WETH),
                usdcToSellForWETH,
                SwapRouter.Exchange.UNIV2, // Using a mock exchange to swap, this param does not matter.
                abi.encode(path, usdcToSellForWETH, 0, address(assetManagementCellar), address(assetManagementCellar))
            );
            // Calculate 40% of assets to swap into WBTC.
            uint256 usdcToSellForWBTC = totalAssets.mulDivDown(4, 10);
            path[0] = address(USDC);
            path[1] = address(WBTC);
            assetsTo = assetManagementCellar.rebalance(
                address(USDC),
                address(WBTC),
                usdcToSellForWBTC,
                SwapRouter.Exchange.UNIV2, // Using a mock exchange to swap, this param does not matter.
                abi.encode(path, usdcToSellForWBTC, 0, address(assetManagementCellar), address(assetManagementCellar))
            );

            (uint256 highWatermark, , , , , , ) = assetManagementCellar.feeData();
            console.log("HWM!:", highWatermark);

            skip(7 days);

            assetManagementCellar.sendFees();
            //TODO check that only platform fees are minted.
        }
        {
            uint256 totalAssets = assetManagementCellar.totalAssets();
            uint256 wBTCValueBefore = priceRouter.getValue(WBTC, WBTC.balanceOf(address(assetManagementCellar)), USDC);
            // WBTC price goes up.
            {
                ERC20[] memory assets = new ERC20[](3);
                uint256[] memory prices = new uint256[](3);
                assets[0] = USDC;
                assets[1] = WETH;
                assets[2] = WBTC;
                prices[0] = 1e8;
                prices[1] = 2_000e8;
                prices[2] = 45_000e8;
                _changeMarketPrices(assets, prices);
            }

            uint256 newTotalAssets = assetManagementCellar.totalAssets();

            uint256 wBTCValueAfter = priceRouter.getValue(WBTC, WBTC.balanceOf(address(assetManagementCellar)), USDC);

            uint256 yieldEarnedFromWBTCPriceIncrease = wBTCValueAfter - wBTCValueBefore;

            console.log("Yield", yieldEarnedFromWBTCPriceIncrease);

            assertEq(
                newTotalAssets,
                (totalAssets + yieldEarnedFromWBTCPriceIncrease),
                "totalAssets after price increased by amount of yield earned."
            );
        }
        {
            //mary joins
            //uint256 amount = mutate(salt);
            uint256 amount = 100e6;
            uint256 shares;
            (uint256 highWatermark, , , , , , ) = assetManagementCellar.feeData();
            console.log("HWM:", highWatermark);
            //
            // Mary joins cellar using deposit.
            vm.startPrank(mary);
            assertEq(
                assetManagementCellar.previewDeposit(amount),
                shares = assetManagementCellar.deposit(amount, mary),
                "Deposit should be equal to previewDeposit"
            );
            vm.stopPrank();
            (highWatermark, , , , , , ) = assetManagementCellar.feeData();
            console.log("HWM:", highWatermark);
            console.log("TVL", assetManagementCellar.totalAssets());
            assertEq(
                highWatermark,
                assetManagementCellar.totalAssets(),
                "High watermark should be equal to totalAssets."
            );
            //performance fees should be minted
            assertTrue(
                assetManagementCellar.balanceOf(address(assetManagementCellar)) > 0,
                "Cellar should have been minted performance fees."
            );

            skip(7 days);

            assetManagementCellar.sendFees();
            //TODO check that only platform/perfamance fees are handled.
        }
        {
            // Set platform fee to 2%.
            assetManagementCellar.setPlatformFee(0.02e18);

            // Set strategist platform cut to 80%.
            assetManagementCellar.setStrategistPlatformCut(0.8e18);

            // Set performance fee to 20%.
            assetManagementCellar.setPerformanceFee(0.2e18);

            // Set strategist performance cut to 85%.
            assetManagementCellar.setStrategistPerformanceCut(0.85e18);

            // WBTC price goes down. WETH price goes up enough to create yield.
            {
                ERC20[] memory assets = new ERC20[](3);
                uint256[] memory prices = new uint256[](3);
                assets[0] = USDC;
                assets[1] = WETH;
                assets[2] = WBTC;
                prices[0] = 1e8;
                prices[1] = 4_000e8;
                prices[2] = 30_000e8;
                _changeMarketPrices(assets, prices);
            }

            // Strategist rebalances all positions to only WETH
            address[] memory path = new address[](2);

            uint256 assetBalanceToRemove = USDC.balanceOf(address(assetManagementCellar));
            path[0] = address(USDC);
            path[1] = address(WETH);

            uint256 assetsTo = assetManagementCellar.rebalance(
                address(USDC),
                address(WETH),
                assetBalanceToRemove,
                SwapRouter.Exchange.UNIV2, // Using a mock exchange to swap, this param does not matter.
                abi.encode(
                    path,
                    assetBalanceToRemove,
                    0,
                    address(assetManagementCellar),
                    address(assetManagementCellar)
                )
            );

            assetBalanceToRemove = WBTC.balanceOf(address(assetManagementCellar));
            path[0] = address(WBTC);
            path[1] = address(WETH);

            assetsTo = assetManagementCellar.rebalance(
                address(WBTC),
                address(WETH),
                assetBalanceToRemove,
                SwapRouter.Exchange.UNIV2, // Using a mock exchange to swap, this param does not matter.
                abi.encode(
                    path,
                    assetBalanceToRemove,
                    0,
                    address(assetManagementCellar),
                    address(assetManagementCellar)
                )
            );
        }
        {
            // Bob enters cellar via Mint.
            //uint256 amount = mutate(salt);
            uint256 shares = 100e18;
            uint256 amount;
            vm.startPrank(bob);
            assertEq(
                assetManagementCellar.previewMint(shares),
                amount = assetManagementCellar.mint(shares, bob),
                "Mint should be equal to previewMint"
            );

            vm.stopPrank();

            vm.startPrank(sam);
            assertEq(
                assetManagementCellar.previewMint(shares),
                amount = assetManagementCellar.mint(shares, sam),
                "Mint should be equal to previewMint"
            );

            vm.stopPrank();
            //TODO make sure sam also doesn't mint performance fees

            skip(21 days);

            assetManagementCellar.sendFees();
            //TODO check that platform/perfamance fees are handled.
        }
        //=========================================================
        {
            //===== Neutral Market ====
            skip(28 days);
            assetManagementCellar.sendFees();
            //TODO no performance fees should be minted, but platform should
            //TODO have some people leave and make sure no performance fees are minted
        }
        //==========================================================
        {
            //===== Start Bear Market ====
            // ETH price goes down.
            {
                ERC20[] memory assets = new ERC20[](3);
                uint256[] memory prices = new uint256[](3);
                assets[0] = USDC;
                assets[1] = WETH;
                assets[2] = WBTC;
                prices[0] = 1e8;
                prices[1] = 3_000e8;
                prices[2] = 30_000e8;
                _changeMarketPrices(assets, prices);
            }

            // Cellar has liquidity in USDC and WETH, rebalance cellar to only Alice some USDC and mainly WETH.
            // Alice withdraws all their assets.
            uint256 shares = assetManagementCellar.balanceOf(alice);
            uint256 assets = assetManagementCellar.previewRedeem(shares);
            // Rebalance Cellar so that it only has 10% of assets needed for Alice's Redeem.
            {
                uint256 amountToRebalance = USDC.balanceOf(address(assetManagementCellar)) - (assets / 10);
                address[] memory path = new address[](2);
                path[0] = address(USDC);
                // Choose to rebalance to WBTC so we can confirm no WBTC is taken from the Cellar on Redeem.
                path[1] = address(WBTC);

                assetManagementCellar.rebalance(
                    address(USDC),
                    address(WBTC),
                    amountToRebalance,
                    SwapRouter.Exchange.UNIV2, // Using a mock exchange to swap, this param does not matter.
                    abi.encode(
                        path,
                        amountToRebalance,
                        0,
                        address(assetManagementCellar),
                        address(assetManagementCellar)
                    )
                );
            }
            //
            deal(address(USDC), alice, 0); // Set Alice's USDC balance to zero to avoid overflow on transfer
            vm.startPrank(alice);
            assertEq(
                assetManagementCellar.previewRedeem(shares),
                assets = assetManagementCellar.redeem(shares, alice, alice),
                "Redeem should be equal to previewRedeem"
            );
            vm.stopPrank();
            //TODO check value out Alice got vs value of Shares
            //TODO check that Alice only gets USDC and WETH, and no WBTC
            //TODO check that assets == valuation of USDC and WETH

            //TODO no performance fees should be minted
            assertTrue(
                assetManagementCellar.balanceOf(address(assetManagementCellar)) == 0,
                "Cellar should have zero performance fees."
            );

            skip(7 days);

            // user joins.
            //TODO this fails if there is not enough USDC in the cellar.
            // `sendFees` will fail because the cellar currently has nothing in the holding asset.
            vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
            assetManagementCellar.sendFees();

            // Strategist rebalances some WETH into USDC to covert `sendFees`.
            {
                // Take 10% of WETH assets in cellar and convert to USDC.
                uint256 amountToRebalance = WETH.balanceOf(address(assetManagementCellar)) / 10;
                address[] memory path = new address[](2);
                path[0] = address(WETH);
                // Choose to rebalance to WBTC so we can confirm no WBTC is taken from the Cellar on Redeem.
                path[1] = address(USDC);

                assetManagementCellar.rebalance(
                    address(WETH),
                    address(USDC),
                    amountToRebalance,
                    SwapRouter.Exchange.UNIV2, // Using a mock exchange to swap, this param does not matter.
                    abi.encode(
                        path,
                        amountToRebalance,
                        0,
                        address(assetManagementCellar),
                        address(assetManagementCellar)
                    )
                );
            }
            assetManagementCellar.sendFees();
        }
        {
            // Alice rejoins via mint.
            uint256 sharesToMint = 100e18;
            deal(address(USDC), alice, assetManagementCellar.previewMint(sharesToMint));
            vm.startPrank(alice);
            assertEq(
                assetManagementCellar.previewMint(sharesToMint),
                assetManagementCellar.mint(sharesToMint, alice),
                "Mint should be equal to previewMint"
            );
            vm.stopPrank();

            skip(1 days);

            assetManagementCellar.sendFees();
        }
        //=========================================================
        (uint256 highWatermark, , , , , , ) = assetManagementCellar.feeData();
        uint256 totalAssets = assetManagementCellar.totalAssets();
        // Cellar is currently above totalAssets, so reset it.
        assertTrue(highWatermark > totalAssets, "High watermark should be greater than total assets in cellar.");
        assetManagementCellar.resetHighWatermark();

        // WBTC goes up a little, USDC depegs to 0.95.
        {
            ERC20[] memory assets = new ERC20[](3);
            uint256[] memory prices = new uint256[](3);
            assets[0] = USDC;
            assets[1] = WETH;
            assets[2] = WBTC;
            prices[0] = 0.95e8;
            prices[1] = 2_700e8;
            prices[2] = 31_000e8;
            _changeMarketPrices(assets, prices);
        }
        //wait 2 weeks
        skip(14 days);
        //call send fees
        //some performance fees should be distributed with platform fees
        assetManagementCellar.sendFees();
        //===============================================================

        //SP adds new positions LINK
        assetManagementCellar.trustPosition(address(LINK), Cellar.PositionType.ERC20);
        assetManagementCellar.pushPosition(address(LINK));
        //Nothing is added to it
        //use swap position to move Link to the front
        assetManagementCellar.swapPositions(3, 0);
        //Asset prices go back down below HWM
        {
            ERC20[] memory assets = new ERC20[](3);
            uint256[] memory prices = new uint256[](3);
            assets[0] = USDC;
            assets[1] = WETH;
            assets[2] = WBTC;
            prices[0] = 0.97e8;
            prices[1] = 2_900e8;
            prices[2] = 36_000e8;
            _changeMarketPrices(assets, prices);
        }

        //wait 1 week
        skip(7 days);
        //call sendFees only platform fees minted
        assetManagementCellar.sendFees();
        //shutdown cellar
        assetManagementCellar.initiateShutdown();
        //TODO at this point try to split Shares evenly between everyone
        //Have user exit where assets balance %s are like so LINK/WETH/WBTC/USDC 0/10/0/90
        //make sure users can leave with redeem and withdraw Alice and Sam
        //force cellar to change to withdraw in proportion
        // have Bob and Mary leave
        //TODO everytime asset prices change confirm cellar totalAssets changes correctly
    }

    //TODO test DOS if SP intentioanlly picks a massive amount of positions, and withdraw forloops fail, what is the max, then implement something to fix this
    //TODO DOS if totalAssets fails
    //TODO any other unbound for loops?
}
