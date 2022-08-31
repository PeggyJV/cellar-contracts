// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, SwapRouter, IGravity } from "src/base/Cellar.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { MockExchange } from "src/mocks/MockExchange.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

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

    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    address private immutable strategist = vm.addr(0xBEEF);

    address private immutable cosmos = vm.addr(0xCAAA);

    CellarAdaptor private cellarAdaptor;

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
        cellarAdaptor = new CellarAdaptor();

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

        Cellar.PositionData[] memory positionData = new Cellar.PositionData[](5);
        positionData[0] = Cellar.PositionData({
            positionType: Cellar.PositionType.ERC20,
            isDebt: false,
            adaptor: address(0),
            adaptorData: abi.encode(0)
        });
        positionData[1] = Cellar.PositionData({
            positionType: Cellar.PositionType.ERC4626,
            isDebt: false,
            adaptor: address(0),
            adaptorData: abi.encode(0)
        });
        positionData[2] = Cellar.PositionData({
            positionType: Cellar.PositionType.ERC4626,
            isDebt: false,
            adaptor: address(0),
            adaptorData: abi.encode(0)
        });
        positionData[3] = Cellar.PositionData({
            positionType: Cellar.PositionType.ERC4626,
            isDebt: false,
            adaptor: address(0),
            adaptorData: abi.encode(0)
        });
        positionData[4] = Cellar.PositionData({
            positionType: Cellar.PositionType.ERC20,
            isDebt: false,
            adaptor: address(0),
            adaptorData: abi.encode(0)
        });

        cellar = new MockCellar(
            registry,
            USDC,
            positions,
            positionData,
            address(USDC),
            Cellar.WithdrawType.ORDERLY,
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            strategist
        );
        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Allow cellar to use CellarAdaptor so it can swap ERC20's and enter/leave other cellar positions.
        cellar.setupAdaptor(address(cellarAdaptor));

        // Mint enough liquidity to swap router for swaps.
        deal(address(USDC), address(exchange), type(uint224).max);
        deal(address(WETH), address(exchange), type(uint224).max);
        deal(address(WBTC), address(exchange), type(uint224).max);

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);
        WETH.approve(address(cellar), type(uint256).max);
        WBTC.approve(address(cellar), type(uint256).max);
    }

    // ========================================= INITIALIZATION TEST =========================================

    function testInitialization() external {
        assertEq(address(cellar.registry()), address(registry), "Should initialize registry to test registry.");

        address[] memory expectedPositions = new address[](5);
        expectedPositions[0] = address(USDC);
        expectedPositions[1] = address(usdcCLR);
        expectedPositions[2] = address(wethCLR);
        expectedPositions[3] = address(wbtcCLR);
        expectedPositions[4] = address(WETH);

        Cellar.PositionType[] memory expectedPositionTypes = new Cellar.PositionType[](5);
        expectedPositionTypes[0] = Cellar.PositionType.ERC20;
        expectedPositionTypes[1] = Cellar.PositionType.ERC4626;
        expectedPositionTypes[2] = Cellar.PositionType.ERC4626;
        expectedPositionTypes[3] = Cellar.PositionType.ERC4626;
        expectedPositionTypes[4] = Cellar.PositionType.ERC20;

        address[] memory positions = cellar.getPositions();

        assertEq(cellar.getPositions().length, 5, "Position length should be 5.");

        for (uint256 i; i < positions.length; i++) {
            (Cellar.PositionType positionType, , , ) = cellar.getPositionData(positions[i]);
            assertEq(positions[i], expectedPositions[i], "Position should be initialized in order.");
            assertEq(uint256(positionType), uint256(expectedPositionTypes[i]), "Position type should be initialized.");
        }

        assertEq(address(cellar.asset()), address(USDC), "Should initialize asset to be USDC.");
        assertEq(cellar.holdingPosition(), address(USDC), "Should initialize holding position to be USDC.");
        assertEq(
            uint256(cellar.withdrawType()),
            uint256(Cellar.WithdrawType.ORDERLY),
            "Should initialize withdraw type."
        );
        assertEq(
            cellar.lastAccrual(),
            uint64(block.timestamp),
            "Should initialize last accrual timestamp to current block timestamp."
        );

        (
            uint256 highWatermark,
            uint64 strategistPerformanceCut,
            uint64 strategistPlatformCut,
            uint64 platformFee,
            uint64 performanceFee,
            bytes32 feeDistributor,
            address strategistPayoutAddress
        ) = cellar.feeData();
        assertEq(highWatermark, 0, "High watermark should be zero.");
        assertEq(strategistPerformanceCut, 0.75e18, "Performance cut should be set to 0.75e18.");
        assertEq(strategistPlatformCut, 0.75e18, "Platform cut should be set to 0.75e18.");
        assertEq(performanceFee, 0.1e18, "Performance fee should be set to 0.1e18.");
        assertEq(platformFee, 0.01e18, "Platform fee should be set to 0.01e18.");
        assertEq(
            feeDistributor,
            hex"000000000000000000000000b813554b423266bbd4c16c32fa383394868c1f55",
            "Fee Distributor should be set to 0x000000000000000000000000b813554b423266bbd4c16c32fa383394868c1f55."
        );
        assertEq(strategistPayoutAddress, strategist, "Strategist payout address should be equal to strategist.");

        assertEq(cellar.liquidityLimit(), type(uint256).max, "Liquidity Limit should be max uint256.");
        assertEq(cellar.depositLimit(), type(uint256).max, "Deposit Limit should be max uint256.");

        assertEq(cellar.owner(), address(this), "Should initialize owner to this contract.");
    }

    // ========================================= DEPOSIT/WITHDRAW TEST =========================================

    function testDepositAndWithdraw(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        deal(address(USDC), address(this), assets);

        (uint256 highWatermarkBeforeDeposit, , , , , , ) = cellar.feeData();

        // Try depositing more assets than balance.
        vm.expectRevert("TRANSFER_FROM_FAILED");
        cellar.deposit(assets + 1, address(this));

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
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have minted fees because no gains.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        (uint256 highWatermarkBeforeWithdraw, , , , , , ) = cellar.feeData();

        // Try withdrawing more assets than allowed.
        vm.expectRevert(bytes(stdError.arithmeticError));
        cellar.withdraw(assets + 1, address(this), address(this));

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
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have minted fees because no gains.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(USDC.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    function testMintAndRedeem(uint256 shares) external {
        shares = bound(shares, 1e18, type(uint112).max);

        // Change decimals from the 18 used by shares to the 6 used by USDC.
        deal(address(USDC), address(this), shares.changeDecimals(18, 6));

        (uint256 highWatermarkBeforeMint, , , , , , ) = cellar.feeData();

        // Try minting more assets than balance.
        vm.expectRevert("TRANSFER_FROM_FAILED");
        cellar.mint(shares + 1e18, address(this));

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
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have minted fees because no gains.");
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
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have minted fees because no gains.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(USDC.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
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
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have minted fees because no gains.");
        assertEq(shares, 32_000e18, "Should returned all redeemed shares.");
        assertEq(WETH.balanceOf(address(this)), 1e18, "Should have transferred position balance to user.");
        assertEq(WBTC.balanceOf(address(this)), 1e8, "Should have transferred position balance to user.");
        assertEq(WETH.balanceOf(address(wethCLR)), 0, "Should have transferred balance from WETH position.");
        assertEq(WBTC.balanceOf(address(wbtcCLR)), 0, "Should have transferred balance from BTC position.");
        assertEq(cellar.totalAssets(), 0, "Should have emptied cellar.");
    }

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
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have minted fees because no gains.");
        assertEq(shares, 16_000e18, "Should returned all redeemed shares.");
        assertEq(WETH.balanceOf(address(this)), 0.5e18, "Should have transferred position balance to user.");
        assertEq(WBTC.balanceOf(address(this)), 0.5e8, "Should have transferred position balance to user.");
        assertEq(WETH.balanceOf(address(wethCLR)), 0.5e18, "Should have transferred balance from WETH position.");
        assertEq(WBTC.balanceOf(address(wbtcCLR)), 0.5e8, "Should have transferred balance from WBTC position.");
        assertEq(cellar.totalAssets(), 16_000e6, "Should have half of assets remaining in cellar.");
    }

    function testWithdrawWithDuplicateReceivedAssets() external {
        MockERC4626 wethVault = new MockERC4626(WETH, "WETH Vault LP Token", "WETH-VLT", 18);
        cellar.trustPosition(address(wethVault), Cellar.PositionType.ERC4626, false, address(0), abi.encode(0));
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
        assertEq(WETH.balanceOf(address(wethCLR)), 0, "Should have transferred balance from WETH cellar position.");
        assertEq(WETH.balanceOf(address(wethVault)), 0, "Should have transferred balance from WETH vault position.");
        assertEq(cellar.totalAssets(), 0, "Should have no assets remaining in cellar.");
    }

    function testDepositMintWithdrawRedeemWithZeroInputs() external {
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ZeroShares.selector)));
        cellar.deposit(0, address(this));

        cellar.mint(0, address(this));
        assertEq(cellar.totalSupply(), 0, "Cellar should not have minted any shares.");
        assertEq(cellar.totalAssets(), 0, "Cellar should not have any assets.");
        assertEq(cellar.balanceOf(address(this)), 0, "Cellar should not have minted any shares to this address.");

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ZeroAssets.selector)));
        cellar.redeem(0, address(this), address(this));

        // Because no assets are deposited, `_withdrawInOrder` for loop
        // continues until it indexes out of the positions array.
        vm.expectRevert(bytes(stdError.indexOOBError));
        cellar.withdraw(0, address(this), address(this));

        // Deal cellar 1 wei of USDC to check that above explanation is correct.
        deal(address(USDC), address(cellar), 1);
        cellar.withdraw(0, address(this), address(this));
        assertEq(USDC.balanceOf(address(this)), 0, "Cellar should not have sent any assets to this address.");
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

        assertFalse(cellar.isPositionUsed(address(WETH)), "`isPositionUsed` should be false for WETH.");

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

        assertFalse(cellar.isPositionUsed(address(WETH)), "`isPositionUsed` should be false for WETH.");

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
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionAlreadyUsed.selector, address(WETH))));
        cellar.pushPosition(address(WETH));

        // Check that `addPosition` reverts if position is already used.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionAlreadyUsed.selector, address(WETH))));
        cellar.addPosition(4, address(WETH));

        // Give Cellar 1 wei of WETH.
        deal(address(WETH), address(cellar), 1);

        // Check that `removePosition` reverts if position has any funds in it.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__PositionNotEmpty.selector,
                    address(WETH),
                    WETH.balanceOf(address(cellar))
                )
            )
        );
        cellar.removePosition(4);

        // Check that `popPosition` reverts if position has any funds in it.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__PositionNotEmpty.selector,
                    address(WETH),
                    WETH.balanceOf(address(cellar))
                )
            )
        );
        cellar.popPosition();

        // Check that `replacePosition` reverts if position has any funds in it.
        address positionA = vm.addr(45);
        cellar.trustPosition(positionA, Cellar.PositionType.ERC20, false, address(0), abi.encode(0));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__PositionNotEmpty.selector,
                    address(WETH),
                    WETH.balanceOf(address(cellar))
                )
            )
        );
        cellar.replacePosition(4, positionA);

        // Check that `pushPosition` reverts if position is not trusted.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__UntrustedPosition.selector, address(0))));
        cellar.pushPosition(address(0));

        // Check that `addPosition` reverts if position is not trusted.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__UntrustedPosition.selector, address(0))));
        cellar.addPosition(4, address(0));

        // Set Cellar WETH balance to 0.
        deal(address(WETH), address(cellar), 0);

        // Check that `swapPosition` works as expected.
        cellar.swapPositions(4, 2);
        assertEq(cellar.positions(4), address(wethCLR), "`positions[4]` should be wethCLR.");
        assertEq(cellar.positions(2), address(WETH), "`positions[2]` should be WETH.");

        cellar.popPosition();

        // Check that replace position works.
        cellar.replacePosition(2, address(wethCLR));
        assertEq(cellar.positions(2), address(wethCLR), "`positions[2]` should be wethCLR.");

        // Check that `replacePosition` reverts if new position is not trusted.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__UntrustedPosition.selector, address(0))));
        cellar.replacePosition(2, address(0));

        // Check that `replacePosition` reverts if new position is already used.
        cellar.pushPosition(address(WETH));
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionAlreadyUsed.selector, address(WETH))));
        cellar.replacePosition(2, address(WETH));

        // Check that removing the holding position reverts.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__RemoveHoldingPosition.selector)));
        cellar.removePosition(0);

        // Check that replacing the holding position reverts.
        address newPosition = vm.addr(45);
        cellar.trustPosition(newPosition, Cellar.PositionType.ERC20, false, address(0), abi.encode(0));
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__RemoveHoldingPosition.selector)));
        cellar.replacePosition(0, newPosition);

        cellar.swapPositions(4, 0);

        // Check that popping the holding position reverts.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__RemoveHoldingPosition.selector)));
        cellar.popPosition();

        // Check that setting holding position to unused position reverts.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidPosition.selector, address(0))));
        cellar.setHoldingPosition(address(0));

        // Check that setting holding position to position with mismatched assets reverts.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Cellar.Cellar__AssetMismatch.selector, address(WETH), address(USDC)))
        );
        cellar.setHoldingPosition(address(WETH));
    }

    function testTrustingPositions() external {
        address newPosition = vm.addr(45);

        cellar.trustPosition(newPosition, Cellar.PositionType.ERC20, false, address(0), abi.encode(0));
        assertTrue(cellar.isTrusted(newPosition), "New position should now be trusted.");
        (Cellar.PositionType positionType, , , ) = cellar.getPositionData(newPosition);
        assertEq(uint256(positionType), uint256(Cellar.PositionType.ERC20), "New position's type should be ERC20.");

        cellar.distrustPosition(newPosition);
        assertFalse(cellar.isTrusted(newPosition), "New position should not be trusted.");

        // Check that distrusting a non empty position reverts.
        deal(address(USDC), address(cellar), 1);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__PositionNotEmpty.selector,
                    address(USDC),
                    USDC.balanceOf(address(cellar))
                )
            )
        );
        cellar.distrustPosition(address(USDC));

        // Check that distrusting the holding position reverts.
        deal(address(USDC), address(cellar), 0);
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__RemoveHoldingPosition.selector)));
        cellar.distrustPosition(address(USDC));
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

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
        cellar.initiateShutdown();

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
        cellar.deposit(1, address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
        cellar.addPosition(5, address(0));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
        cellar.pushPosition(address(0));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
        cellar.replacePosition(2, address(0));

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        Cellar.AdaptorCall[] memory adaptorCallData;
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
        cellar.callOnAdaptor(adaptorCallData);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
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

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__DepositRestricted.selector, amount, limit)));
        cellar.deposit(amount, address(this));
    }

    function testMintAboveDepositLimit(uint256 amount) external {
        // Minting above the deposit limit should revert.
        amount = bound(amount, 101, type(uint112).max);

        uint256 limit = 100e6;
        cellar.setDepositLimit(limit);

        deal(address(USDC), address(this), amount * 1e6);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__DepositRestricted.selector, amount * 1e6, limit)));
        cellar.mint(amount * 1e18, address(this));
    }

    function testDepositAboveLiquidityLimit(uint256 amount) external {
        // Depositing above the deposit limit should revert.
        amount = bound(amount, 101e6, type(uint112).max);

        uint256 limit = 100e6;
        cellar.setLiquidityLimit(limit);

        deal(address(USDC), address(this), amount);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__DepositRestricted.selector, amount, limit)));
        cellar.deposit(amount, address(this));
    }

    function testMintAboveLiquidityLimit(uint256 amount) external {
        // Minting above the deposit limit should revert.
        amount = bound(amount, 101, type(uint112).max);

        uint256 limit = 100e6;
        cellar.setLiquidityLimit(limit);

        deal(address(USDC), address(this), amount * 1e6);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__DepositRestricted.selector, amount * 1e6, limit)));
        cellar.mint(amount * 1e18, address(this));
    }

    function testChangingLimits() external {
        cellar.setLiquidityLimit(777);
        cellar.setDepositLimit(777_777);
        assertEq(cellar.liquidityLimit(), 777, "Liquidity limit should be set to 777.");
        assertEq(cellar.depositLimit(), 777_777, "Deposit limit should be set to 777,777.");
    }

    // ====================================== PERFORMANCE/PLATFORM FEE TEST ======================================

    function testChangingFeeData() external {
        address newStrategistAddress = vm.addr(777);
        bytes32 validCosmosAddress = hex"000000000000000000000000ffffffffffffffffffffffffffffffffffffffff";
        cellar.setPlatformFee(0.2e18);
        cellar.setPerformanceFee(0.03e18);
        cellar.setFeesDistributor(validCosmosAddress);
        cellar.setStrategistPerformanceCut(0.8e18);
        cellar.setStrategistPlatformCut(0.8e18);
        cellar.setStrategistPayoutAddress(newStrategistAddress);
        (
            ,
            uint64 strategistPerformanceCut,
            uint64 strategistPlatformCut,
            uint64 platformFee,
            uint64 performanceFee,
            bytes32 feeDistributor,
            address strategistPayoutAddress
        ) = cellar.feeData();
        assertEq(strategistPerformanceCut, 0.8e18, "Performance cut should be set to 0.8e18.");
        assertEq(strategistPlatformCut, 0.8e18, "Platform cut should be set to 0.8e18.");
        assertEq(platformFee, 0.2e18, "Platform fee should be set to 0.2e18.");
        assertEq(performanceFee, 0.03e18, "Performance fee should be set to 0.03e18.");
        assertEq(feeDistributor, validCosmosAddress, "Fee Distributor should be set to `validCosmosAddress`.");
        assertEq(
            strategistPayoutAddress,
            newStrategistAddress,
            "Strategist payout address should be set to `newStrategistAddress`."
        );

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidFee.selector)));
        cellar.setPlatformFee(0.21e18);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidFee.selector)));
        cellar.setPerformanceFee(0.51e18);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidCosmosAddress.selector)));
        cellar.setFeesDistributor(hex"0000000000000000000000010000000000000000000000000000000000000000");

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidFeeCut.selector)));
        cellar.setStrategistPerformanceCut(1.1e18);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidFeeCut.selector)));
        cellar.setStrategistPlatformCut(1.1e18);
    }

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

        assertApproxEqAbs(
            cellar.previewMint(100e18),
            cellar.mint(100e18, address(this)),
            1,
            "`previewMint` should return the same as `mint`."
        );

        assertApproxEqAbs(
            cellar.previewDeposit(100e6),
            cellar.deposit(100e6, address(this)),
            1,
            "`previewDeposit` should return the same as `deposit`."
        );

        cellar.approve(address(cellar), type(uint256).max);
        assertApproxEqAbs(
            cellar.previewWithdraw(100e6),
            cellar.withdraw(100e6, address(this), address(this)),
            1,
            "`previewWithdraw` should return the same as `withdraw`."
        );

        assertApproxEqAbs(
            cellar.previewRedeem(100e18),
            cellar.redeem(100e18, address(this), address(this)),
            1,
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
        // Cap time passed to 1 year. Platform fees will be collected on the
        // order of weeks possibly months.
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

        // Call `sendFees` to calculate pending platform fees, and distribute
        // them to strategist, and Cosmos.
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
        // Cap time passed to 1 year. Platform fees will be collected on the
        // order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 100e6, 1_000_000_000e6);
        // Cap yield to 10,000% APR
        {
            uint256 yieldUpperBound = (100 * deposit * timePassed) / 365 days;
            // Floor yield above 0.01% APR
            uint256 yieldLowerBound = ((deposit * timePassed) / 365 days) / 10_000;
            yield = bound(yield, yieldLowerBound, yieldUpperBound);
        }
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

        deal(address(USDC), address(cosmos), 0);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Simulate Cellar earning yield.
        uint256 totalAssetsBeforeSendFees = USDC.balanceOf(address(cellar)) + yield;
        deal(address(USDC), address(cellar), totalAssetsBeforeSendFees);

        // Call `sendFees` to calculate pending performance and platform fees,
        // and distribute them to strategist, and Cosmos.
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
            2,
            "Fees in assets sent to Cosmos + fees in shares sent to strategist should equal the expected total fees after dilution."
        );

        assertApproxEqAbs(
            feesInAssetsSentToStrategist,
            expectedPlatformFees.mulWadDown(strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(strategistPerformanceCut),
            2,
            "Shares converted to assets sent to strategist should be equal to (total platform fees * strategistPlatformCut) + (total performance fees * strategist performance cut)."
        );

        assertApproxEqAbs(
            feesInAssetsSentToCosmos,
            expectedPlatformFees.mulWadDown(1e18 - strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(1e18 - strategistPerformanceCut),
            2,
            "Assets sent to Cosmos should be equal to (total platform fees * (1-strategistPlatformCut)) + (total performance fees * (1-strategist performance cut))."
        );

        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have burned all fee shares.");

        uint256 expectedHighWatermark = totalAssetsBeforeSendFees - feesInAssetsSentToCosmos;

        (uint256 highWatermarkAfterSendFees, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterSendFees,
            expectedHighWatermark,
            "High watermark should equal high watermark before send fees minus assets sent to Cosmos."
        );
    }

    function testPerformanceFeesWithZeroPlatformFees(
        uint256 timePassed,
        uint256 deposit,
        uint256 yield
    ) external {
        // Cap time passed to 1 year. Platform fees will be collected on the order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 100e6, 1_000_000_000e6);
        // Cap yield to 10,000% APR
        {
            uint256 yieldUpperBound = (100 * deposit * timePassed) / 365 days;
            // Floor yield above 0.01% APR
            uint256 yieldLowerBound = ((deposit * timePassed) / 365 days) / 10_000;
            yield = bound(yield, yieldLowerBound, yieldUpperBound);
        }

        cellar.setPlatformFee(0);
        (, uint64 strategistPerformanceCut, , , uint64 performanceFee, , ) = cellar.feeData();

        uint256 assetAmount = deposit / 2;
        uint256 sharesAmount = assetAmount.changeDecimals(6, 18);
        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), deposit);

        // Deposit into cellar.
        cellar.deposit(assetAmount, address(this));
        // Mint shares from the cellar.
        cellar.mint(sharesAmount, address(this));

        (uint256 highWatermark, , , , , , ) = cellar.feeData();
        assertEq(highWatermark, cellar.totalAssets(), "High watermark should equal totalAssets.");

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + yield);

        cellar.sendFees();

        // Redeem all shares from the cellar.
        uint256 shares = cellar.balanceOf(address(this));
        cellar.redeem(shares, address(this), address(this));

        uint256 expectedPerformanceFees = yield.mulDivDown(performanceFee, 1e18);

        // Check that no fees are minted.
        uint256 feesInAssetsSentToCosmos = USDC.balanceOf(cosmos);
        uint256 feesInAssetsSentToStrategist = cellar.previewRedeem(cellar.balanceOf(strategist));

        assertApproxEqAbs(
            feesInAssetsSentToCosmos + feesInAssetsSentToStrategist,
            expectedPerformanceFees,
            2,
            "Fees in assets sent to Cosmos + fees in shares sent to strategist should equal the expected performance fee."
        );

        assertApproxEqAbs(
            feesInAssetsSentToStrategist,
            expectedPerformanceFees.mulWadDown(strategistPerformanceCut),
            2,
            "Shares converted to assets sent to strategist should be equal to (total performance fees * strategist performance cut)."
        );

        assertApproxEqAbs(
            feesInAssetsSentToCosmos,
            expectedPerformanceFees.mulWadDown(1e18 - strategistPerformanceCut),
            2,
            "Assets sent to Cosmos should be equal to (total performance fees * (1-strategist performance cut))."
        );

        assertApproxEqAbs(
            cellar.previewRedeem(cellar.balanceOf(address(cellar))),
            0,
            1,
            "Cellar fee shares should be redeemable for zero assets."
        );
    }

    function testPlatformFeesWithZeroPerformanceFees(
        uint256 timePassed,
        uint256 deposit,
        uint256 yield
    ) external {
        // Cap time passed to 1 year. Platform fees will be collected on the order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 100e6, 1_000_000_000e6);
        // Cap yield to 10,000% APR
        {
            uint256 yieldUpperBound = (100 * deposit * timePassed) / 365 days;
            // Floor yield above 0.01% APR
            uint256 yieldLowerBound = ((deposit * timePassed) / 365 days) / 10_000;
            yield = bound(yield, yieldLowerBound, yieldUpperBound);
        }

        cellar.setPerformanceFee(0);
        (, , uint64 strategistPlatformCut, uint64 platformFee, , , ) = cellar.feeData();

        uint256 assetAmount = deposit / 2;
        uint256 sharesAmount = assetAmount.changeDecimals(6, 18);
        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), deposit);

        // Deposit into cellar.
        cellar.deposit(assetAmount, address(this));
        // Mint shares from the cellar.
        cellar.mint(sharesAmount, address(this));

        (uint256 highWatermark, , , , , , ) = cellar.feeData();
        assertEq(highWatermark, cellar.totalAssets(), "High watermark should equal totalAssets.");

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + yield);

        cellar.sendFees();

        // Redeem all shares from the cellar.
        uint256 shares = cellar.balanceOf(address(this));
        cellar.redeem(shares, address(this), address(this));

        uint256 expectedPlatformFees = ((deposit + yield) * platformFee * timePassed) / (365 days * 1e18);

        // Check that no fees are minted.
        uint256 feesInAssetsSentToCosmos = USDC.balanceOf(cosmos);
        uint256 feesInAssetsSentToStrategist = cellar.previewRedeem(cellar.balanceOf(strategist));

        assertApproxEqAbs(
            feesInAssetsSentToCosmos + feesInAssetsSentToStrategist,
            expectedPlatformFees,
            2,
            "Fees in assets sent to Cosmos + fees in shares sent to strategist should equal the expected platform fees."
        );

        assertApproxEqAbs(
            feesInAssetsSentToStrategist,
            expectedPlatformFees.mulWadDown(strategistPlatformCut),
            2,
            "Shares converted to assets sent to strategist should be equal to (total platform fees * strategistPlatformCut)."
        );

        assertApproxEqAbs(
            feesInAssetsSentToCosmos,
            expectedPlatformFees.mulWadDown(1e18 - strategistPlatformCut),
            2,
            "Assets sent to Cosmos should be equal to (total platform fees * (1-strategistPlatformCut))."
        );

        assertApproxEqAbs(
            cellar.previewRedeem(cellar.balanceOf(address(cellar))),
            0,
            1,
            "Cellar fee shares should be redeemable for zero assets."
        );
    }

    function testPlatformAndPerformanceFeesWithZeroFees(
        uint256 timePassed,
        uint256 deposit,
        uint256 yield
    ) external {
        // Cap time passed to 1 year. Platform fees will be collected on the order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 100e6, 1_000_000_000e6);
        // Cap yield to 10,000% APR
        {
            uint256 yieldUpperBound = (100 * deposit * timePassed) / 365 days;
            // Floor yield above 0.01% APR
            uint256 yieldLowerBound = ((deposit * timePassed) / 365 days) / 10_000;
            yield = bound(yield, yieldLowerBound, yieldUpperBound);
        }

        cellar.setPerformanceFee(0);
        cellar.setPlatformFee(0);

        uint256 assetAmount = deposit / 2;
        uint256 sharesAmount = assetAmount.changeDecimals(6, 18);
        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), deposit);

        // Deposit into cellar.
        cellar.deposit(assetAmount, address(this));
        // Mint shares from the cellar.
        cellar.mint(sharesAmount, address(this));

        (uint256 highWatermark, , , , , , ) = cellar.feeData();
        assertEq(highWatermark, cellar.totalAssets(), "High watermark should equal totalAssets.");

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Simulate Cellar earning yield.
        deal(address(USDC), address(cellar), USDC.balanceOf(address(cellar)) + yield);

        cellar.sendFees();

        // Redeem all shares from the cellar.
        uint256 shares = cellar.balanceOf(address(this));
        cellar.redeem(shares, address(this), address(this));

        // Check that no fees are minted.
        uint256 feesInAssetsSentToCosmos = USDC.balanceOf(cosmos);
        uint256 feesInAssetsSentToStrategist = cellar.previewRedeem(cellar.balanceOf(strategist));
        assertEq(feesInAssetsSentToCosmos, 0, "Fees sent to Cosmos should be zero.");
        assertEq(feesInAssetsSentToStrategist, 0, "Fees sent to strategist should be zero.");
        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have zero fee shares");

        (highWatermark, , , , , , ) = cellar.feeData();
        assertEq(highWatermark, 0, "High watermark should equal zero.");
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
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PayoutNotSet.selector)));
        cellar.sendFees();
    }

    function testMaliciousStrategistWithUnboundForLoop() external {
        // Initialize test Cellar.
        MockCellar multiPositionCellar;
        address[] memory positions;
        {
            // Create new cellar with WETH, USDC, and WBTC positions.
            positions = new address[](1);
            positions[0] = address(USDC);

            Cellar.PositionData[] memory positionData = new Cellar.PositionData[](1);
            positionData[0] = Cellar.PositionData({
                positionType: Cellar.PositionType.ERC20,
                isDebt: false,
                adaptor: address(0),
                adaptorData: abi.encode(0)
            });

            multiPositionCellar = new MockCellar(
                registry,
                USDC,
                positions,
                positionData,
                address(USDC),
                Cellar.WithdrawType.ORDERLY,
                "Asset Management Cellar LP Token",
                "assetmanagement-CLR",
                strategist
            );
        }

        MockERC20 position;
        for (uint256 i = 1; i < 32; i++) {
            position = new MockERC20("Howdy", 18);
            multiPositionCellar.trustPosition(
                address(position),
                Cellar.PositionType.ERC20,
                false,
                address(0),
                abi.encode(0)
            );
            multiPositionCellar.pushPosition(address(position));
        }

        assertEq(multiPositionCellar.getPositions().length, 32, "Cellar should have 32 positions.");

        // Adding one more position should revert.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionArrayFull.selector, uint256(32))));
        multiPositionCellar.addPosition(32, vm.addr(777));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionArrayFull.selector, uint256(32))));
        multiPositionCellar.pushPosition(vm.addr(777));

        // Check that users can still interact with the cellar even at max positions size.
        deal(address(USDC), address(this), 100e6);
        USDC.approve(address(multiPositionCellar), 100e6);
        uint256 gas = gasleft();
        multiPositionCellar.deposit(100e6, address(this));
        uint256 remainingGas = gasleft();
        assertLt(
            gas - remainingGas,
            500_000,
            "Gas used on deposit should be comfortably less than the block gas limit."
        );

        gas = gasleft();
        multiPositionCellar.withdraw(100e6, address(this), address(this));
        remainingGas = gasleft();
        assertLt(
            gas - remainingGas,
            500_000,
            "Gas used on withdraw should be comfortably less than the block gas limit."
        );

        // Now check a worst case scenario, SP maxes out positions, and evenly
        // distributes funds to every position, then user withdraws.
        deal(address(USDC), address(this), 32e6);
        USDC.approve(address(multiPositionCellar), 32e6);
        multiPositionCellar.deposit(32e6, address(this));

        uint256 totalAssets = multiPositionCellar.totalAssets();

        // Change the cellars USDC balance, so that we can deal cellar assets in
        // other positions and not change the share price.
        deal(address(USDC), address(multiPositionCellar), 1e6);

        positions = multiPositionCellar.getPositions();
        for (uint256 i = 1; i < positions.length; i++) {
            priceRouter.setExchangeRate(ERC20(positions[i]), USDC, 1e6);
            deal(positions[i], address(multiPositionCellar), 1e18);
        }

        assertEq(multiPositionCellar.totalAssets(), totalAssets, "Cellar total assets should be unchanged.");

        gas = gasleft();
        multiPositionCellar.withdraw(32e6, address(this), address(this));
        remainingGas = gasleft();
        assertLt(
            gas - remainingGas,
            1_200_000,
            "Gas used on worst case scenario withdraw should be comfortably less than the block gas limit."
        );
    }

    function testAllFeesToStrategist(
        uint256 timePassed,
        uint256 deposit,
        uint256 yield
    ) external {
        // Cap time passed to 1 year. Platform fees will be collected on the
        // order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 100e6, 1_000_000_000e6);

        // Cap yield to 10,000% APR
        {
            uint256 yieldUpperBound = (100 * deposit * timePassed) / 365 days;
            // Floor yield above 0.01% APR
            uint256 yieldLowerBound = ((deposit * timePassed) / 365 days) / 10_000;
            yield = bound(yield, yieldLowerBound, yieldUpperBound);
        }

        cellar.setStrategistPerformanceCut(1e18);
        cellar.setStrategistPlatformCut(1e18);

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

        deal(address(USDC), address(cosmos), 0);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Simulate Cellar earning yield.
        uint256 totalAssetsBeforeSendFees = USDC.balanceOf(address(cellar)) + yield;
        deal(address(USDC), address(cellar), totalAssetsBeforeSendFees);

        // Call `sendFees` to calculate pending performance and platform fees,
        // and distribute them to strategist, and Cosmos.
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
            2,
            "Fees in assets sent to Cosmos + fees in shares sent to strategist should equal the expected total fees after dilution."
        );

        assertApproxEqAbs(
            feesInAssetsSentToStrategist,
            expectedPlatformFees.mulWadDown(strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(strategistPerformanceCut),
            2,
            "Shares converted to assets sent to strategist should be equal to (total platform fees * strategistPlatformCut) + (total performance fees * strategist performance cut)."
        );

        assertApproxEqAbs(
            feesInAssetsSentToCosmos,
            expectedPlatformFees.mulWadDown(1e18 - strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(1e18 - strategistPerformanceCut),
            2,
            "Assets sent to Cosmos should be equal to (total platform fees * (1-strategistPlatformCut)) + (total performance fees * (1-strategist performance cut))."
        );

        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have burned all fee shares.");

        uint256 expectedHighWatermark = totalAssetsBeforeSendFees - feesInAssetsSentToCosmos;

        (uint256 highWatermarkAfterSendFees, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterSendFees,
            expectedHighWatermark,
            "High watermark should equal high watermark before send fees minus assets sent to Cosmos."
        );

        vm.startPrank(strategist);
        cellar.redeem(cellar.balanceOf(strategist), strategist, strategist);
        vm.stopPrank();
    }

    function testAllFeesToPlatform(
        uint256 timePassed,
        uint256 deposit,
        uint256 yield
    ) external {
        // Cap time passed to 1 year. Platform fees will be collected on the
        // order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 100e6, 1_000_000_000e6);

        // Cap yield to 10,000% APR
        {
            uint256 yieldUpperBound = (100 * deposit * timePassed) / 365 days;
            // Floor yield above 0.01% APR
            uint256 yieldLowerBound = ((deposit * timePassed) / 365 days) / 10_000;
            yield = bound(yield, yieldLowerBound, yieldUpperBound);
        }

        cellar.setStrategistPerformanceCut(0);
        cellar.setStrategistPlatformCut(0);

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

        deal(address(USDC), address(cosmos), 0);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Simulate Cellar earning yield.
        uint256 totalAssetsBeforeSendFees = USDC.balanceOf(address(cellar)) + yield;
        deal(address(USDC), address(cellar), totalAssetsBeforeSendFees);

        // Call `sendFees` to calculate pending performance and platform fees,
        // and distribute them to strategist, and Cosmos.
        cellar.sendFees();

        uint256 expectedPerformanceFees = yield.mulDivDown(performanceFee, 1e18);

        // Minting platform fees dilutes share price, so it also dilutes pending
        // performance fees.
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
            2,
            "Fees in assets sent to Cosmos + fees in shares sent to strategist should equal the expected total fees after dilution."
        );

        assertApproxEqAbs(
            feesInAssetsSentToStrategist,
            expectedPlatformFees.mulWadDown(strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(strategistPerformanceCut),
            2,
            "Shares converted to assets sent to strategist should be equal to (total platform fees * strategistPlatformCut) + (total performance fees * strategist performance cut)."
        );

        assertApproxEqAbs(
            feesInAssetsSentToCosmos,
            expectedPlatformFees.mulWadDown(1e18 - strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(1e18 - strategistPerformanceCut),
            2,
            "Assets sent to Cosmos should be equal to (total platform fees * (1-strategistPlatformCut)) + (total performance fees * (1-strategist performance cut))."
        );

        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have burned all fee shares.");

        uint256 expectedHighWatermark = totalAssetsBeforeSendFees - feesInAssetsSentToCosmos;

        (uint256 highWatermarkAfterSendFees, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterSendFees,
            expectedHighWatermark,
            "High watermark should equal high watermark before send fees minus assets sent to Cosmos."
        );
    }

    function testPerformanceFeesToStrategistPlatformFeesToPlatform(
        uint256 timePassed,
        uint256 deposit,
        uint256 yield
    ) external {
        // Cap time passed to 1 year. Platform fees will be collected on the
        // order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 100e6, 1_000_000_000e6);

        // Cap yield to 10,000% APR
        {
            uint256 yieldUpperBound = (100 * deposit * timePassed) / 365 days;
            // Floor yield above 0.01% APR
            uint256 yieldLowerBound = ((deposit * timePassed) / 365 days) / 10_000;
            yield = bound(yield, yieldLowerBound, yieldUpperBound);
        }

        cellar.setStrategistPerformanceCut(1e18);
        cellar.setStrategistPlatformCut(0);

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

        deal(address(USDC), address(cosmos), 0);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Simulate Cellar earning yield.
        uint256 totalAssetsBeforeSendFees = USDC.balanceOf(address(cellar)) + yield;
        deal(address(USDC), address(cellar), totalAssetsBeforeSendFees);

        // Call `sendFees` to calculate pending performance and platform fees,
        // and distribute them to strategist, and Cosmos.
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
            2,
            "Fees in assets sent to Cosmos + fees in shares sent to strategist should equal the expected total fees after dilution."
        );

        assertApproxEqAbs(
            feesInAssetsSentToStrategist,
            expectedPlatformFees.mulWadDown(strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(strategistPerformanceCut),
            2,
            "Shares converted to assets sent to strategist should be equal to (total platform fees * strategistPlatformCut) + (total performance fees * strategist performance cut)."
        );

        assertApproxEqAbs(
            feesInAssetsSentToCosmos,
            expectedPlatformFees.mulWadDown(1e18 - strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(1e18 - strategistPerformanceCut),
            2,
            "Assets sent to Cosmos should be equal to (total platform fees * (1-strategistPlatformCut)) + (total performance fees * (1-strategist performance cut))."
        );

        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have burned all fee shares.");

        uint256 expectedHighWatermark = totalAssetsBeforeSendFees - feesInAssetsSentToCosmos;

        (uint256 highWatermarkAfterSendFees, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterSendFees,
            expectedHighWatermark,
            "High watermark should equal high watermark before send fees minus assets sent to Cosmos."
        );

        vm.startPrank(strategist);
        cellar.redeem(cellar.balanceOf(strategist), strategist, strategist);
        vm.stopPrank();
    }

    function testPlatformFeesToStrategistPerformanceFeesToPlatform(
        uint256 timePassed,
        uint256 deposit,
        uint256 yield
    ) external {
        // Cap time passed to 1 year. Platform fees will be collected on the
        // order of weeks possibly months.
        timePassed = bound(timePassed, 1 days, 365 days);
        deposit = bound(deposit, 100e6, 1_000_000_000e6);

        // Cap yield to 10,000% APR
        {
            uint256 yieldUpperBound = (100 * deposit * timePassed) / 365 days;
            // Floor yield above 0.01% APR
            uint256 yieldLowerBound = ((deposit * timePassed) / 365 days) / 10_000;
            yield = bound(yield, yieldLowerBound, yieldUpperBound);
        }

        cellar.setStrategistPerformanceCut(0);
        cellar.setStrategistPlatformCut(1e18);

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

        deal(address(USDC), address(cosmos), 0);

        // Deposit into cellar.
        cellar.deposit(deposit, address(this));

        // Advance time by `timePassed` seconds.
        skip(timePassed);

        // Simulate Cellar earning yield.
        uint256 totalAssetsBeforeSendFees = USDC.balanceOf(address(cellar)) + yield;
        deal(address(USDC), address(cellar), totalAssetsBeforeSendFees);

        // Call `sendFees` to calculate pending performance and platform fees,
        // and distribute them to strategist, and Cosmos.
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
            2,
            "Fees in assets sent to Cosmos + fees in shares sent to strategist should equal the expected total fees after dilution."
        );

        assertApproxEqAbs(
            feesInAssetsSentToStrategist,
            expectedPlatformFees.mulWadDown(strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(strategistPerformanceCut),
            2,
            "Shares converted to assets sent to strategist should be equal to (total platform fees * strategistPlatformCut) + (total performance fees * strategist performance cut)."
        );

        assertApproxEqAbs(
            feesInAssetsSentToCosmos,
            expectedPlatformFees.mulWadDown(1e18 - strategistPlatformCut) +
                expectedPerformanceFeesAdjustedForDilution.mulWadDown(1e18 - strategistPerformanceCut),
            2,
            "Assets sent to Cosmos should be equal to (total platform fees * (1-strategistPlatformCut)) + (total performance fees * (1-strategist performance cut))."
        );

        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have burned all fee shares.");

        uint256 expectedHighWatermark = totalAssetsBeforeSendFees - feesInAssetsSentToCosmos;

        (uint256 highWatermarkAfterSendFees, , , , , , ) = cellar.feeData();

        assertEq(
            highWatermarkAfterSendFees,
            expectedHighWatermark,
            "High watermark should equal high watermark before send fees minus assets sent to Cosmos."
        );

        vm.startPrank(strategist);
        cellar.redeem(cellar.balanceOf(strategist), strategist, strategist);
        vm.stopPrank();
    }

    //TODO
    function testDebtTokensInCellars() external {
        //constructor should set isDebt
        //trust position should set it as debt
        //add/push/remove/replace/pop position should update number of debt positions
        //total Assets and get data should both account for debt positions
        //distrust position should change num of debt positions
    }

    // ======================================== DEPEGGING ASSET TESTS ========================================

    function testDepeggedAssetNotUsedByCellar() external {
        // Scenario 1: Depegged asset is not being used by the cellar.
        // Governance can remove it itself by calling `distrustPosition`.

        // Add asset that will be depegged.
        uint256 positionsLengthBefore = cellar.getPositions().length;
        cellar.trustPosition(address(USDT), Cellar.PositionType.ERC20, false, address(0), abi.encode(0));
        cellar.pushPosition(address(USDT));
        priceRouter.setExchangeRate(USDT, USDC, 1e6);
        priceRouter.setExchangeRate(USDC, USDT, 1e6);

        deal(address(USDC), address(this), 200e6);
        cellar.deposit(100e6, address(this));

        // USDT depeggs to $0.90.
        priceRouter.setExchangeRate(USDT, USDC, 0.9e6);
        priceRouter.setExchangeRate(USDC, USDT, 1.111111e6);

        assertEq(cellar.totalAssets(), 100e6, "Cellar total assets should remain unchanged.");
        assertEq(cellar.deposit(100e6, address(this)), 100e18, "Cellar share price should not change.");

        // Governance votes to distrust USDT position.
        cellar.distrustPosition(address(USDT));
        assertFalse(cellar.isTrusted(address(USDT)), "Cellar should not trust USDT.");
        assertFalse(cellar.isPositionUsed(address(USDT)), "Cellar should not be using USDT.");
        assertEq(
            cellar.getPositions().length,
            positionsLengthBefore,
            "Cellar should have removed USDT from positions array."
        );
    }

    function testDepeggedAssetUsedByTheCellar() external {
        // Scenario 2: Depegged asset is being used by the cellar. Governance
        // uses multicall to rebalance cellar out of position, and to distrust
        // it.

        // Add asset that will be depegged.
        uint256 positionsLengthBefore = cellar.getPositions().length;
        cellar.trustPosition(address(USDT), Cellar.PositionType.ERC20, false, address(0), abi.encode(0));
        cellar.pushPosition(address(USDT));
        priceRouter.setExchangeRate(USDT, USDC, 1e6);
        priceRouter.setExchangeRate(USDC, USDT, 1e6);

        deal(address(USDC), address(this), 200e6);
        cellar.deposit(100e6, address(this));

        //Change Cellar holdings manually to 50/50 USDC/USDT.
        deal(address(USDC), address(cellar), 50e6);
        deal(address(USDT), address(cellar), 50e6);

        // USDT depeggs to $0.90.
        priceRouter.setExchangeRate(USDT, USDC, 0.9e6);
        priceRouter.setExchangeRate(USDC, USDT, 1.111111e6);

        assertEq(cellar.totalAssets(), 95e6, "Cellar total assets should have gone down.");
        assertGt(cellar.deposit(100e6, address(this)), 100e18, "Cellar share price should have decreased.");

        // Governance votes to rebalance out of USDT, and distrust USDT.
        // Manually rebalance into USDC.
        deal(address(USDC), address(cellar), 95e6);
        deal(address(USDT), address(cellar), 0);
        cellar.distrustPosition(address(USDT));
        assertFalse(cellar.isTrusted(address(USDT)), "Cellar should not trust USDT.");
        assertFalse(cellar.isPositionUsed(address(USDT)), "Cellar should not be using USDT.");
        assertEq(
            cellar.getPositions().length,
            positionsLengthBefore,
            "Cellar should have removed USDT from positions array."
        );
    }

    function testDepeggedHoldingPosition() external {
        // Scenario 3: Depegged asset is being used by the cellar, and it is the
        // holding position. Governance uses multicall to rebalance cellar out
        // of position, set a new holding position, and distrust it.

        uint256 positionsLengthBefore = cellar.getPositions().length;
        cellar.setHoldingPosition(address(usdcCLR));

        // Rebalance into USDC. No swap is made because both positions use
        // USDC.
        deal(address(USDC), address(this), 200e6);
        cellar.deposit(100e6, address(this));

        // Make call to adaptor to remove funds from usdcCLR into USDC position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(CellarAdaptor.withdrawFromCellar.selector, usdcCLR, 50e6);
        bool[] memory isRevertOkay = new bool[](1);
        data[0] = Cellar.AdaptorCall({
            adaptor: address(cellarAdaptor),
            callData: adaptorCalls,
            isRevertOkay: isRevertOkay
        });
        cellar.callOnAdaptor(data);

        // usdcCLR depeggs from USDC
        deal(address(USDC), address(usdcCLR), 45e6);

        assertEq(cellar.totalAssets(), 95e6, "Cellar total assets should have gone down.");
        assertGt(cellar.deposit(100e6, address(this)), 100e18, "Cellar share price should have decreased.");

        // Governance votes to rebalance out of usdcCLR, change the holding
        // position, and distrust usdcCLR. No swap is made because both
        // positions use USDC.
        adaptorCalls[0] = abi.encodeWithSelector(
            CellarAdaptor.withdrawFromCellar.selector,
            usdcCLR,
            usdcCLR.maxWithdraw(address(cellar))
        );
        data[0] = Cellar.AdaptorCall({
            adaptor: address(cellarAdaptor),
            callData: adaptorCalls,
            isRevertOkay: isRevertOkay
        });
        cellar.callOnAdaptor(data);

        cellar.setHoldingPosition(address(USDC));
        cellar.distrustPosition(address(usdcCLR));
        assertFalse(cellar.isTrusted(address(usdcCLR)), "Cellar should not trust usdcCLR.");
        assertFalse(cellar.isPositionUsed(address(usdcCLR)), "Cellar should not be using usdcCLR.");
        assertEq(
            cellar.getPositions().length,
            positionsLengthBefore - 1,
            "Cellar should have removed usdcCLR from positions array."
        );
    }

    function testDepeggedCellarAsset() external {
        // Scenario 4: Depegged asset is the cellars asset. Worst case
        // scenario, rebalance out of position into some new stable position,
        // set fees to zero, initiate a shutdown, and have users withdraw funds
        // asap. Want to ensure that attackers can not join using the depegged
        // asset. Emergency governance proposal to move funds into some new
        // safety contract, shutdown old cellar, and allow users to withdraw
        // from the safety contract.

        cellar.trustPosition(address(USDT), Cellar.PositionType.ERC20, false, address(0), abi.encode(0));
        cellar.pushPosition(address(USDT));
        priceRouter.setExchangeRate(USDT, USDC, 1e6);
        priceRouter.setExchangeRate(USDC, USDT, 1e6);

        deal(address(USDC), address(this), 100e6);
        cellar.deposit(100e6, address(this));

        // USDC depeggs to $0.90.
        priceRouter.setExchangeRate(USDC, USDT, 0.9e6);
        priceRouter.setExchangeRate(USDT, USDC, 1.111111e6);

        assertEq(cellar.totalAssets(), 100e6, "Cellar total assets should remain unchanged.");

        // Governance rebalances to USDT, sets performance and platform fees to
        // zero, initiates a shutdown, and has users withdraw their funds.
        // Manually rebalance to USDT.
        deal(address(USDC), address(cellar), 0);
        deal(address(USDT), address(cellar), 90e6);

        // Important to set fees to zero, else performance fees are minted as
        // the cellars asset depeggs further.
        cellar.setPerformanceFee(0);
        cellar.setPlatformFee(0);
        cellar.initiateShutdown();

        // Attacker tries to join with depegged asset.
        address attacker = vm.addr(34534);
        deal(address(USDC), attacker, 1);
        vm.startPrank(attacker);
        USDC.approve(address(cellar), 1);
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
        cellar.deposit(1, attacker);
        vm.stopPrank();

        cellar.redeem(50e18, address(this), address(this));

        // USDC depeggs to $0.10.
        priceRouter.setExchangeRate(USDC, USDT, 0.1e6);
        priceRouter.setExchangeRate(USDT, USDC, 10e6);

        cellar.redeem(50e18, address(this), address(this));

        // Eventhough USDC depegged further, cellar rebalanced out of USDC
        // removing its exposure to it.  So users can expect to get the
        // remaining value out of the cellar.
        assertEq(
            USDT.balanceOf(address(this)),
            90e6,
            "Withdraws should total the amount of USDT in the cellar after rebalance."
        );

        // Governance can not distrust USDC, because it is the holding position,
        // and changing the holding position is pointless because the asset of
        // the new holding position must be USDC.  Therefore the cellar is lost,
        // and should be exitted completely.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__RemoveHoldingPosition.selector)));
        cellar.distrustPosition(address(USDC));
    }

    /**
     * Some notes about the above tests:
     * It will be difficult for Governance to set some safe min asset amount
     * when rebalancing a cellar from a depegging asset. Ideally this would be
     * done by the strategist, but even then if the price is volatile enough,
     * strategists might not be able to set a fair min amount out value. We
     * might be able to use Chainlink price feeds to get around this, and rely
     * on the Chainlink oracle data in order to calculate a fair min amount out
     * on chain.
     *
     * Users will be able to exit the cellar as long as the depegged asset is
     * still within its price envelope defined in the price router as minPrice
     * and maxPrice. Once an asset is outside this envelope, or Chainlink stops
     * reporting pricing data, the situation becomes difficult. Any calls
     * involving `totalAssets()` will fail because the price router will not be
     * able to get a safe price for the depegged asset. With this in mind we
     * should consider creating some emergency fund protector contract, where in
     * the event a violent depegging occurs, Governance can vote to trust the
     * fund protector contract as a position, and all the cellars assets can be
     * converted into some safe asset then deposited into the fund protector
     * contract. Doing this decouples the depegged asset pricing data from
     * assets in the cellar. In order to get their funds out users would go to
     * the fund protector contract, and trade their shares (from the depegged
     * cellar) for assets in the fund protector.
     */

    // ========================================= GRAVITY FUNCTIONS =========================================

    // Since this contract is set as the Gravity Bridge, this will be called by
    // the Cellar's `sendFees` function to send funds Cosmos.
    function sendToCosmos(
        address asset,
        bytes32,
        uint256 assets
    ) external {
        ERC20(asset).transferFrom(msg.sender, cosmos, assets);
    }
}
