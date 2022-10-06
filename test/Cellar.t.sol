// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { LockedERC4626 } from "src/mocks/LockedERC4626.sol";
import { Registry, PriceRouter, SwapRouter, IGravity } from "src/base/Cellar.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { MockExchange } from "src/mocks/MockExchange.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";

import { Test, stdStorage, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarTest is Test {
    using SafeERC20 for ERC20;
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
    ERC20Adaptor private erc20Adaptor;

    uint256 private usdcPosition;
    uint256 private wethPosition;
    uint256 private usdcCLRPosition;
    uint256 private wethCLRPosition;
    uint256 private wbtcCLRPosition;

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
        erc20Adaptor = new ERC20Adaptor();

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

        priceRouter.supportAsset(USDC);
        priceRouter.supportAsset(WETH);
        priceRouter.supportAsset(WBTC);

        // Cellar positions array.
        uint256[] memory positions = new uint256[](5);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(cellarAdaptor));
        registry.trustAdaptor(address(erc20Adaptor));

        usdcPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(USDC));
        usdcCLRPosition = registry.trustPosition(address(cellarAdaptor), false, abi.encode(usdcCLR));
        wethCLRPosition = registry.trustPosition(address(cellarAdaptor), false, abi.encode(wethCLR));
        wbtcCLRPosition = registry.trustPosition(address(cellarAdaptor), false, abi.encode(wbtcCLR));
        wethPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(WETH));

        positions[0] = usdcPosition;
        positions[1] = usdcCLRPosition;
        positions[2] = wethCLRPosition;
        positions[3] = wbtcCLRPosition;
        positions[4] = wethPosition;

        cellar = new MockCellar(
            registry,
            USDC,
            positions,
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

        // Manipulate  test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    // ========================================= INITIALIZATION TEST =========================================

    function testInitialization() external {
        assertEq(address(cellar.registry()), address(registry), "Should initialize registry to test registry.");

        uint256[] memory expectedPositions = new uint256[](5);
        expectedPositions[0] = usdcPosition;
        expectedPositions[1] = usdcCLRPosition;
        expectedPositions[2] = wethCLRPosition;
        expectedPositions[3] = wbtcCLRPosition;
        expectedPositions[4] = wethPosition;

        address[] memory expectedAdaptor = new address[](5);
        expectedAdaptor[0] = address(erc20Adaptor);
        expectedAdaptor[1] = address(cellarAdaptor);
        expectedAdaptor[2] = address(cellarAdaptor);
        expectedAdaptor[3] = address(cellarAdaptor);
        expectedAdaptor[4] = address(erc20Adaptor);

        bytes[] memory expectedAdaptorData = new bytes[](5);
        expectedAdaptorData[0] = abi.encode(USDC);
        expectedAdaptorData[1] = abi.encode(usdcCLR);
        expectedAdaptorData[2] = abi.encode(wethCLR);
        expectedAdaptorData[3] = abi.encode(wbtcCLR);
        expectedAdaptorData[4] = abi.encode(WETH);

        uint256[] memory positions = cellar.getPositions();

        assertEq(cellar.getPositions().length, 5, "Position length should be 5.");

        for (uint256 i = 0; i < 5; i++) {
            assertEq(positions[i], expectedPositions[i], "Positions should have been written to Cellar.");
            uint256 position = positions[i];
            (address adaptor, bool isDebt, bytes memory adaptorData) = cellar.getPositionData(position);
            assertEq(adaptor, expectedAdaptor[i], "Position adaptor not initialized properly.");
            assertEq(isDebt, false, "There should be no debt positions.");
            assertEq(adaptorData, expectedAdaptorData[i], "Position adaptor data not initialized properly.");
        }

        assertEq(address(cellar.asset()), address(USDC), "Should initialize asset to be USDC.");

        assertEq(
            cellar.lastAccrual(),
            uint64(block.timestamp),
            "Should initialize last accrual timestamp to current block timestamp."
        );

        (
            uint64 strategistPlatformCut,
            uint64 platformFee,
            bytes32 feeDistributor,
            address strategistPayoutAddress
        ) = cellar.feeData();
        assertEq(strategistPlatformCut, 0.75e18, "Platform cut should be set to 0.75e18.");
        assertEq(platformFee, 0.01e18, "Platform fee should be set to 0.01e18.");
        assertEq(
            feeDistributor,
            hex"000000000000000000000000b813554b423266bbd4c16c32fa383394868c1f55",
            "Fee Distributor should be set to 0x000000000000000000000000b813554b423266bbd4c16c32fa383394868c1f55."
        );
        assertEq(strategistPayoutAddress, strategist, "Strategist payout address should be equal to strategist.");

        assertEq(cellar.owner(), address(this), "Should initialize owner to this contract.");
    }

    // ========================================= DEPOSIT/WITHDRAW TEST =========================================

    function testDepositAndWithdraw(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        deal(address(USDC), address(this), assets);

        // Try depositing more assets than balance.
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        cellar.deposit(assets + 1, address(this));

        // Test single deposit.
        uint256 expectedShares = cellar.previewDeposit(assets);
        uint256 shares = cellar.deposit(assets, address(this));

        assertEq(shares, assets.changeDecimals(6, 18), "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assets), shares, "Withdrawing assets should burn shares given.");
        assertEq(shares, expectedShares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have minted fees because no gains.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // Try withdrawing more assets than allowed.
        vm.expectRevert("ERC20: burn amount exceeds balance");
        cellar.withdraw(assets + 1, address(this), address(this));

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

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

        // Try minting more assets than balance.
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        cellar.mint(shares + 1e18, address(this));

        // Test single mint.
        uint256 assets = cellar.mint(shares, address(this));

        assertEq(shares.changeDecimals(18, 6), assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewRedeem(shares), assets, "Redeeming shares should withdraw assets owed.");
        assertEq(cellar.previewMint(shares), assets, "Minting shares should deposit assets owed.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have minted fees because no gains.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // Test single redeem.
        cellar.redeem(shares, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have minted fees because no gains.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(USDC.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    function testWithdrawInOrder() external {
        cellar.depositIntoPosition(wethCLRPosition, 1e18); // $2000
        cellar.depositIntoPosition(wbtcCLRPosition, 1e8); // $30,000
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

    function testWithdrawWithDuplicateReceivedAssets() external {
        MockERC4626 wethVault = new MockERC4626(WETH, "WETH Vault LP Token", "WETH-VLT", 18);

        priceRouter.supportAsset(WETH);
        uint256 newWETHPosition = registry.trustPosition(address(cellarAdaptor), false, abi.encode(wethVault));
        cellar.addPosition(5, newWETHPosition);

        cellar.depositIntoPosition(wethCLRPosition, 1e18); // $2000
        cellar.depositIntoPosition(newWETHPosition, 0.5e18); // $1000

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

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ZeroAssets.selector)));
        cellar.mint(0, address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ZeroAssets.selector)));
        cellar.redeem(0, address(this), address(this));

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

        assertFalse(cellar.isPositionUsed(wethPosition), "`isPositionUsed` should be false for WETH.");

        // Check that `addPosition` actually adds it.
        cellar.addPosition(4, wethPosition);

        assertEq(
            positionLength,
            cellar.getPositions().length,
            "Cellar positions array should be equal to previous length."
        );

        assertEq(cellar.positions(4), wethPosition, "`positions[4]` should be WETH.");
        assertTrue(cellar.isPositionUsed(wethPosition), "`isPositionUsed` should be true for WETH.");

        // Check that `addPosition` reverts if position is already used.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionAlreadyUsed.selector, wethPosition)));
        cellar.addPosition(4, wethPosition);

        // Give Cellar 1 wei of WETH.
        deal(address(WETH), address(cellar), 1);

        // Check that `removePosition` reverts if position has any funds in it.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__PositionNotEmpty.selector,
                    wethPosition,
                    WETH.balanceOf(address(cellar))
                )
            )
        );
        cellar.removePosition(4);

        // Check that `addPosition` reverts if position is not trusted.
        vm.expectRevert(bytes("Position does not exist."));
        cellar.addPosition(4, 0);

        // Set Cellar WETH balance to 0.
        deal(address(WETH), address(cellar), 0);

        // Check that `swapPosition` works as expected.
        cellar.swapPositions(4, 2);
        assertEq(cellar.positions(4), wethCLRPosition, "`positions[4]` should be wethCLR.");
        assertEq(cellar.positions(2), wethPosition, "`positions[2]` should be WETH.");
    }

    //     function testTrustingPositions() external {
    //         address newPosition = vm.addr(45);

    //         priceRouter.supportAsset(ERC20(newPosition));
    //         cellar.trustPosition(newPosition, Cellar.PositionType.ERC20, false, address(0), abi.encode(0));
    //         assertTrue(cellar.isTrusted(newPosition), "New position should now be trusted.");
    //         (Cellar.PositionType positionType, , , ) = cellar.getPositionData(newPosition);
    //         assertEq(uint256(positionType), uint256(Cellar.PositionType.ERC20), "New position's type should be ERC20.");
    //     }

    // ========================================== REBALANCE TEST ==========================================

    function testSettingBadRebalanceDeviation() external {
        // Max rebalance deviation value is 10%.
        uint256 deviation = 0.2e18;
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__InvalidRebalanceDeviation.selector,
                    deviation,
                    cellar.MAX_REBALANCE_DEVIATION()
                )
            )
        );
        cellar.setRebalanceDeviation(deviation);
    }

    // ======================================== EMERGENCY TESTS ========================================

    function testShutdown() external {
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractNotShutdown.selector)));
        cellar.liftShutdown();

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
        cellar.addPosition(5, 0);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        Cellar.AdaptorCall[] memory adaptorCallData;
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
        cellar.callOnAdaptor(adaptorCallData);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
        cellar.initiateShutdown();
    }

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

        cellar.depositIntoPosition(usdcCLRPosition, usdcCLRAmount);
        cellar.depositIntoPosition(wethCLRPosition, wethCLRAmount);
        cellar.depositIntoPosition(wbtcCLRPosition, wbtcCLRAmount);
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
            "`totalAssets` should equal all asset values summed together."
        );
    }

    // ====================================== PLATFORM FEE TEST ======================================

    function testChangingFeeData() external {
        address newStrategistAddress = vm.addr(777);
        bytes32 validCosmosAddress = hex"000000000000000000000000ffffffffffffffffffffffffffffffffffffffff";
        cellar.setPlatformFee(0.2e18);
        cellar.setFeesDistributor(validCosmosAddress);
        cellar.setStrategistPlatformCut(0.8e18);
        cellar.setStrategistPayoutAddress(newStrategistAddress);
        (
            uint64 strategistPlatformCut,
            uint64 platformFee,
            bytes32 feeDistributor,
            address strategistPayoutAddress
        ) = cellar.feeData();
        assertEq(strategistPlatformCut, 0.8e18, "Platform cut should be set to 0.8e18.");
        assertEq(platformFee, 0.2e18, "Platform fee should be set to 0.2e18.");
        assertEq(feeDistributor, validCosmosAddress, "Fee Distributor should be set to `validCosmosAddress`.");
        assertEq(
            strategistPayoutAddress,
            newStrategistAddress,
            "Strategist payout address should be set to `newStrategistAddress`."
        );

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidFee.selector)));
        cellar.setPlatformFee(0.21e18);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidCosmosAddress.selector)));
        cellar.setFeesDistributor(hex"0000000000000000000000010000000000000000000000000000000000000000");

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidFeeCut.selector)));
        cellar.setStrategistPlatformCut(1.1e18);
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
        (uint64 strategistPlatformCut, uint64 platformFee, , ) = cellar.feeData();
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

        cellar.setPlatformFee(0);

        uint256 assetAmount = deposit / 2;
        uint256 sharesAmount = assetAmount.changeDecimals(6, 18);
        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), deposit);

        // Deposit into cellar.
        cellar.deposit(assetAmount, address(this));
        // Mint shares from the cellar.
        cellar.mint(sharesAmount, address(this));

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
    }

    function testPayoutNotSet() external {
        cellar.setStrategistPayoutAddress(address(0));
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PayoutNotSet.selector)));
        cellar.sendFees();
    }

    function testMaliciousStrategistWithUnboundForLoop() external {
        // Initialize test Cellar.
        MockCellar multiPositionCellar;
        uint256[] memory positions;
        {
            // Create new cellar with USDC position.
            positions = new uint256[](1);
            positions[0] = usdcPosition;

            multiPositionCellar = new MockCellar(
                registry,
                USDC,
                positions,
                "Asset Management Cellar LP Token",
                "assetmanagement-CLR",
                strategist
            );
            stdstore
                .target(address(multiPositionCellar))
                .sig(multiPositionCellar.shareLockPeriod.selector)
                .checked_write(uint256(0));
        }

        MockERC20 position;
        for (uint256 i = 1; i < 32; i++) {
            position = new MockERC20("Howdy", 18);
            priceRouter.supportAsset(position);
            uint256 id = registry.trustPosition(address(erc20Adaptor), false, abi.encode(position));
            multiPositionCellar.addPosition(multiPositionCellar.getPositions().length, id);
        }

        assertEq(multiPositionCellar.getPositions().length, 32, "Cellar should have 32 positions.");

        // Adding one more position should revert.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionArrayFull.selector, uint256(32))));
        multiPositionCellar.addPosition(32, 0);

        // Check that users can still interact with the cellar even at max positions size.
        deal(address(USDC), address(this), 100e6);
        USDC.approve(address(multiPositionCellar), 100e6);
        uint256 gas = gasleft();
        multiPositionCellar.deposit(100e6, address(this));
        uint256 remainingGas = gasleft();
        assertLt(
            gas - remainingGas,
            600_000,
            "Gas used on deposit should be comfortably less than the block gas limit."
        );

        gas = gasleft();
        multiPositionCellar.withdraw(100e6, address(this), address(this));
        remainingGas = gasleft();
        assertLt(
            gas - remainingGas,
            600_000,
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
            (, , bytes memory data) = multiPositionCellar.getPositionData(positions[i]);
            ERC20 token = abi.decode(data, (ERC20));
            priceRouter.setExchangeRate(token, USDC, 1e6);
            deal(address(token), address(multiPositionCellar), 1e18);
        }

        assertEq(multiPositionCellar.totalAssets(), totalAssets, "Cellar total assets should be unchanged.");

        gas = gasleft();
        multiPositionCellar.withdraw(32e6, address(this), address(this));
        remainingGas = gasleft();
        assertLt(
            gas - remainingGas,
            1_700_000,
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

        cellar.setStrategistPlatformCut(1e18);

        (uint64 strategistPlatformCut, uint64 platformFee, , ) = cellar.feeData();

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

        uint256 expectedPlatformFees = ((deposit + yield) * platformFee * timePassed) / (365 days * 1e18);

        uint256 expectedTotalFeesAdjustedForDilution = expectedPlatformFees;

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

        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have burned all fee shares.");

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

        cellar.setStrategistPlatformCut(0);

        (uint64 strategistPlatformCut, uint64 platformFee, , ) = cellar.feeData();

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

        uint256 expectedPlatformFees = ((deposit + yield) * platformFee * timePassed) / (365 days * 1e18);

        uint256 expectedTotalFeesAdjustedForDilution = expectedPlatformFees;

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

        assertEq(cellar.balanceOf(address(cellar)), 0, "Cellar should have burned all fee shares.");
    }

    //TODO
    function testDebtTokensInCellars() external {
        uint256 debtWethPosition = registry.trustPosition(address(erc20Adaptor), true, abi.encode(WETH));
        uint256 debtWbtcPosition = registry.trustPosition(address(erc20Adaptor), true, abi.encode(WBTC));

        // Setup Cellar with debt positions:
        uint256[] memory positions = new uint256[](2);
        positions[0] = usdcPosition;
        positions[1] = debtWethPosition; // not a real debt position, but for test will be treated as such

        MockCellar debtCellar = new MockCellar(
            registry,
            USDC,
            positions,
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            strategist
        );

        //constructor should set isDebt
        (, bool isDebt, ) = debtCellar.getPositionData(debtWethPosition);
        assertTrue(isDebt, "Constructor should have set WETH as a debt position.");
        assertEq(debtCellar.numberOfDebtPositions(), 1, "Debt cellar should have 1 debt position.");

        //Add another debt position WBTC.
        // adding WBTC should increment number of debt positions.
        debtCellar.addPosition(2, debtWbtcPosition);
        assertEq(debtCellar.numberOfDebtPositions(), 2, "Debt cellar should have 2 debt positions.");

        (, isDebt, ) = debtCellar.getPositionData(debtWbtcPosition);
        assertTrue(isDebt, "Constructor should have set WBTC as a debt position.");
        assertEq(debtCellar.numberOfDebtPositions(), 2, "Debt cellar should have 1 debt position.");

        // removing WBTC should decrement number of debt positions.
        debtCellar.removePosition(2);
        assertEq(debtCellar.numberOfDebtPositions(), 1, "Debt cellar should have 1 debt position.");

        debtCellar.addPosition(2, debtWbtcPosition);

        // Give debt cellar some assets.
        deal(address(USDC), address(debtCellar), 100_000e6);
        deal(address(WBTC), address(debtCellar), 1e8);
        deal(address(WETH), address(debtCellar), 10e18);

        uint256 totalAssets = debtCellar.totalAssets();
        uint256 expectedTotalAssets = 50_000e6;

        assertEq(totalAssets, expectedTotalAssets, "Debt cellar total assets should equal expected.");
    }

    // function testCellarWithCellarPositions() external {
    //     // Cellar A's asset is USDC, holding position is Cellar B shares, whose holding asset is USDC.
    //     // Initialize test Cellars.
    //     MockCellar cellarA;
    //     MockCellar cellarB;

    //     address[] memory positions = new address[](1);
    //     positions[0] = address(USDC);

    //     Cellar.PositionData[] memory positionData = new Cellar.PositionData[](1);
    //     positionData[0] = Cellar.PositionData({
    //         positionType: Cellar.PositionType.ERC20,
    //         isDebt: false,
    //         adaptor: address(0),
    //         adaptorData: abi.encode(0)
    //     });

    //     cellarB = new MockCellar(
    //         registry,
    //         USDC,
    //         positions,
    //         positionData,
    //         address(USDC),
    //         "Ultimate Stablecoin cellar",
    //         "USC-CLR",
    //         strategist
    //     );

    //     stdstore.target(address(cellarB)).sig(cellarB.shareLockPeriod.selector).checked_write(uint256(0));

    //     positions[0] = address(cellarB);

    //     positionData[0] = Cellar.PositionData({
    //         positionType: Cellar.PositionType.Cellar,
    //         isDebt: false,
    //         adaptor: address(0),
    //         adaptorData: abi.encode(0)
    //     });

    //     cellarA = new MockCellar(
    //         registry,
    //         USDC,
    //         positions,
    //         positionData,
    //         address(cellarB),
    //         "Stablecoin cellar",
    //         "SC-CLR",
    //         strategist
    //     );

    //     stdstore.target(address(cellarA)).sig(cellarA.shareLockPeriod.selector).checked_write(uint256(0));

    //     uint256 assets = 100e6;
    //     deal(address(USDC), address(this), assets);
    //     USDC.approve(address(cellarA), assets);
    //     cellarA.deposit(assets, address(this));

    //     uint256 withdrawAmount = cellarA.maxWithdraw(address(this));
    //     assertEq(assets, withdrawAmount, "Assets should not have changed.");
    //     assertEq(cellarA.totalAssets(), cellarB.totalAssets(), "Total assets should be the same.");

    //     cellarA.withdraw(withdrawAmount, address(this), address(this));
    // }

    // ======================================== DEPEGGING ASSET TESTS ========================================

    function testDepeggedAssetNotUsedByCellar() external {
        // Scenario 1: Depegged asset is not being used by the cellar.
        // Governance can remove it itself by calling `distrustPosition`.

        // Add asset that will be depegged.
        priceRouter.supportAsset(USDT);
        uint256 usdtPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(USDT));
        cellar.addPosition(5, usdtPosition);
        priceRouter.setExchangeRate(USDT, USDC, 1e6);
        priceRouter.setExchangeRate(USDC, USDT, 1e6);

        deal(address(USDC), address(this), 200e6);
        cellar.deposit(100e6, address(this));

        // USDT depeggs to $0.90.
        priceRouter.setExchangeRate(USDT, USDC, 0.9e6);
        priceRouter.setExchangeRate(USDC, USDT, 1.111111e6);

        assertEq(cellar.totalAssets(), 100e6, "Cellar total assets should remain unchanged.");
        assertEq(cellar.deposit(100e6, address(this)), 100e18, "Cellar share price should not change.");
    }

    //     function testDepeggedAssetUsedByTheCellar() external {
    //         // Scenario 2: Depegged asset is being used by the cellar. Governance
    //         // uses multicall to rebalance cellar out of position, and to distrust
    //         // it.

    //         // Add asset that will be depegged.
    //         priceRouter.supportAsset(USDT);
    //         cellar.trustPosition(address(USDT), Cellar.PositionType.ERC20, false, address(0), abi.encode(0));
    //         cellar.addPosition(5, address(USDT));
    //         priceRouter.setExchangeRate(USDT, USDC, 1e6);
    //         priceRouter.setExchangeRate(USDC, USDT, 1e6);

    //         deal(address(USDC), address(this), 200e6);
    //         cellar.deposit(100e6, address(this));

    //         //Change Cellar holdings manually to 50/50 USDC/USDT.
    //         deal(address(USDC), address(cellar), 50e6);
    //         deal(address(USDT), address(cellar), 50e6);

    //         // USDT depeggs to $0.90.
    //         priceRouter.setExchangeRate(USDT, USDC, 0.9e6);
    //         priceRouter.setExchangeRate(USDC, USDT, 1.111111e6);

    //         assertEq(cellar.totalAssets(), 95e6, "Cellar total assets should have gone down.");
    //         assertGt(cellar.deposit(100e6, address(this)), 100e18, "Cellar share price should have decreased.");

    //         // Governance votes to rebalance out of USDT, and distrust USDT.
    //         // Manually rebalance into USDC.
    //         deal(address(USDC), address(cellar), 95e6);
    //         deal(address(USDT), address(cellar), 0);
    //     }

    //     function testDepeggedHoldingPosition() external {
    //         // Scenario 3: Depegged asset is being used by the cellar, and it is the
    //         // holding position. Governance uses multicall to rebalance cellar out
    //         // of position, set a new holding position, and distrust it.

    //         cellar.setHoldingPosition(address(usdcCLR));

    //         // Rebalance into USDC. No swap is made because both positions use
    //         // USDC.
    //         deal(address(USDC), address(this), 200e6);
    //         cellar.deposit(100e6, address(this));

    //         // Make call to adaptor to remove funds from usdcCLR into USDC position.
    //         Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
    //         bytes[] memory adaptorCalls = new bytes[](1);
    //         adaptorCalls[0] = abi.encodeWithSelector(CellarAdaptor.withdrawFromCellar.selector, usdcCLR, 50e6);
    //         bool[] memory isRevertOkay = new bool[](1);
    //         data[0] = Cellar.AdaptorCall({
    //             adaptor: address(cellarAdaptor),
    //             callData: adaptorCalls,
    //             isRevertOkay: isRevertOkay
    //         });
    //         cellar.callOnAdaptor(data);

    //         // usdcCLR depeggs from USDC
    //         deal(address(USDC), address(usdcCLR), 45e6);

    //         assertEq(cellar.totalAssets(), 95e6, "Cellar total assets should have gone down.");
    //         assertGt(cellar.deposit(100e6, address(this)), 100e18, "Cellar share price should have decreased.");

    //         // Governance votes to rebalance out of usdcCLR, change the holding
    //         // position, and distrust usdcCLR. No swap is made because both
    //         // positions use USDC.
    //         adaptorCalls[0] = abi.encodeWithSelector(
    //             CellarAdaptor.withdrawFromCellar.selector,
    //             usdcCLR,
    //             usdcCLR.maxWithdraw(address(cellar))
    //         );
    //         data[0] = Cellar.AdaptorCall({
    //             adaptor: address(cellarAdaptor),
    //             callData: adaptorCalls,
    //             isRevertOkay: isRevertOkay
    //         });
    //         cellar.callOnAdaptor(data);

    //         cellar.setHoldingPosition(address(USDC));
    //     }

    //     function testDepeggedCellarAsset() external {
    //         // Scenario 4: Depegged asset is the cellars asset. Worst case
    //         // scenario, rebalance out of position into some new stable position,
    //         // set fees to zero, initiate a shutdown, and have users withdraw funds
    //         // asap. Want to ensure that attackers can not join using the depegged
    //         // asset. Emergency governance proposal to move funds into some new
    //         // safety contract, shutdown old cellar, and allow users to withdraw
    //         // from the safety contract.

    //         priceRouter.supportAsset(USDT);
    //         cellar.trustPosition(address(USDT), Cellar.PositionType.ERC20, false, address(0), abi.encode(0));
    //         cellar.addPosition(5, address(USDT));
    //         priceRouter.setExchangeRate(USDT, USDC, 1e6);
    //         priceRouter.setExchangeRate(USDC, USDT, 1e6);

    //         deal(address(USDC), address(this), 100e6);
    //         cellar.deposit(100e6, address(this));

    //         // USDC depeggs to $0.90.
    //         priceRouter.setExchangeRate(USDC, USDT, 0.9e6);
    //         priceRouter.setExchangeRate(USDT, USDC, 1.111111e6);

    //         assertEq(cellar.totalAssets(), 100e6, "Cellar total assets should remain unchanged.");

    //         // Governance rebalances to USDT, sets performance and platform fees to
    //         // zero, initiates a shutdown, and has users withdraw their funds.
    //         // Manually rebalance to USDT.
    //         deal(address(USDC), address(cellar), 0);
    //         deal(address(USDT), address(cellar), 90e6);

    //         // Important to set fees to zero, else performance fees are minted as
    //         // the cellars asset depeggs further.
    //         cellar.setPlatformFee(0);
    //         cellar.initiateShutdown();

    //         // Attacker tries to join with depegged asset.
    //         address attacker = vm.addr(34534);
    //         deal(address(USDC), attacker, 1);
    //         vm.startPrank(attacker);
    //         USDC.approve(address(cellar), 1);
    //         vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
    //         cellar.deposit(1, attacker);
    //         vm.stopPrank();

    //         cellar.redeem(50e18, address(this), address(this));

    //         // USDC depeggs to $0.10.
    //         priceRouter.setExchangeRate(USDC, USDT, 0.1e6);
    //         priceRouter.setExchangeRate(USDT, USDC, 10e6);

    //         cellar.redeem(50e18, address(this), address(this));

    //         // Eventhough USDC depegged further, cellar rebalanced out of USDC
    //         // removing its exposure to it.  So users can expect to get the
    //         // remaining value out of the cellar.
    //         assertEq(
    //             USDT.balanceOf(address(this)),
    //             90e6,
    //             "Withdraws should total the amount of USDT in the cellar after rebalance."
    //         );

    //         // Governance can not distrust USDC, because it is the holding position,
    //         // and changing the holding position is pointless because the asset of
    //         // the new holding position must be USDC.  Therefore the cellar is lost,
    //         // and should be exitted completely.
    //     }

    //     /**
    //      * Some notes about the above tests:
    //      * It will be difficult for Governance to set some safe min asset amount
    //      * when rebalancing a cellar from a depegging asset. Ideally this would be
    //      * done by the strategist, but even then if the price is volatile enough,
    //      * strategists might not be able to set a fair min amount out value. We
    //      * might be able to use Chainlink price feeds to get around this, and rely
    //      * on the Chainlink oracle data in order to calculate a fair min amount out
    //      * on chain.
    //      *
    //      * Users will be able to exit the cellar as long as the depegged asset is
    //      * still within its price envelope defined in the price router as minPrice
    //      * and maxPrice. Once an asset is outside this envelope, or Chainlink stops
    //      * reporting pricing data, the situation becomes difficult. Any calls
    //      * involving `totalAssets()` will fail because the price router will not be
    //      * able to get a safe price for the depegged asset. With this in mind we
    //      * should consider creating some emergency fund protector contract, where in
    //      * the event a violent depegging occurs, Governance can vote to trust the
    //      * fund protector contract as a position, and all the cellars assets can be
    //      * converted into some safe asset then deposited into the fund protector
    //      * contract. Doing this decouples the depegged asset pricing data from
    //      * assets in the cellar. In order to get their funds out users would go to
    //      * the fund protector contract, and trade their shares (from the depegged
    //      * cellar) for assets in the fund protector.
    //      */

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

    //     // ========================================= MACRO FINDINGS =========================================

    //     // H-1 done.

    //     // H-2 NA, cellars will not increase their TVL during rebalance calls.
    //     // In future versions this will be fixed by having all yield converted into the cellar's accounting asset, then put into a vestedERC20 contract which gradually releases rewards to the cellar.

    //     // M-1

    //     // M5
    //     function testReentrancyAttack() external {
    //         // True means this cellar tries to re-enter caller on deposit calls.
    //         ReentrancyERC4626 maliciousCellar = new ReentrancyERC4626(USDC, "Bad Cellar", "BC", true);

    //         cellar.trustPosition(address(maliciousCellar), Cellar.PositionType.ERC4626, false, address(0), abi.encode(0));
    //         cellar.addPosition(5, address(maliciousCellar));
    //         cellar.setHoldingPosition(address(maliciousCellar));

    //         uint256 assets = 10000e6;
    //         deal(address(USDC), address(this), assets);
    //         USDC.approve(address(maliciousCellar), assets);

    //         vm.expectRevert(bytes("ReentrancyGuard: reentrant call"));
    //         cellar.deposit(assets, address(this));
    //     }

    //     // L-4 handle via using a centralized contract storing valid positions(to reduce num of governance props), and rely on voters to see mismatched position and types.
    //     //  Will not be added to this code.

    //     //M-6 handled offchain using a subgraph to verify no weird webs are happening
    //     // difficult bc we can control downstream, but can't control upstream. IE
    //     // Cellar A wants to add a position in Cellar B, but Cellar B already has a position in Cellar C. Cellar A could see this, but...
    //     // If Cellar A takes a postion in Cellar B, then Cellar B takes a position in Cellar C, Cellar B would need to look upstream to see the nested postions which is unreasonable,
    //     // and it means Cellar A can dictate what positions Cellar B takes which is not good.

    //     // M-4, change in mint function
    //     function testAttackOnFirstMint() external {
    //         // An attacker attacks as first minter
    //         address attacker = vm.addr(1337);

    //         vm.startPrank(attacker);

    //         deal(address(USDC), address(attacker), 10000e6);
    //         USDC.approve(address(cellar), 10000e6);

    //         // Attacker mints shares < 1e12 on first mint

    //         vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ZeroAssets.selector)));
    //         cellar.mint(9e11, attacker);

    //         vm.stopPrank();
    //     }

    //     // M-2, changes in trustPosition.
    //     function testTrustPositionForUnsupportedAssetLocksAllFunds() external {
    //         // USDT is not a supported PriceRouter asset.

    //         uint256 assets = 10e18;

    //         deal(address(USDC), address(this), assets);

    //         // Deposit USDC
    //         cellar.previewDeposit(assets);
    //         cellar.deposit(assets, address(this));
    //         assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

    //         // USDT is added as a trusted Cellar position,
    //         // but is not supported by the PriceRouter.
    //         vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionPricingNotSetUp.selector, address(USDT))));
    //         cellar.trustPosition(address(USDT), Cellar.PositionType.ERC20, false, address(0), abi.encode(0));
    //     }

    //     //H-1
    //     function testChainlinkPriceFeedUpdateSandwichAttack() external {
    //         // Initialize test Cellar.

    //         // Create new cellar with WETH, and USDC positions.
    //         address[] memory positions = new address[](2);
    //         positions[0] = address(USDC);
    //         positions[1] = address(WETH);

    //         Cellar.PositionData[] memory positionData = new Cellar.PositionData[](2);
    //         positionData[0] = Cellar.PositionData({
    //             positionType: Cellar.PositionType.ERC20,
    //             isDebt: false,
    //             adaptor: address(0),
    //             adaptorData: abi.encode(0)
    //         });
    //         positionData[1] = Cellar.PositionData({
    //             positionType: Cellar.PositionType.ERC20,
    //             isDebt: false,
    //             adaptor: address(0),
    //             adaptorData: abi.encode(0)
    //         });

    //         MockCellar cellarA = new MockCellar(
    //             registry,
    //             USDC,
    //             positions,
    //             positionData,
    //             address(USDC),
    //             "Asset Management Cellar LP Token",
    //             "assetmanagement-CLR",
    //             strategist
    //         );

    //         // Set up worst case scenario where
    //         // Cellar has all of its funds in mispriced asset(WETH)
    //         // Chainlink updates price because of max price deviation(1%)

    //         uint256 assets = 10_000e6;
    //         deal(address(USDC), address(this), assets);
    //         USDC.approve(address(cellarA), assets);
    //         cellarA.deposit(assets, address(this));
    //         // Manually rebalance funds from USDC to WETH.
    //         deal(address(USDC), address(cellarA), 0);
    //         deal(address(WETH), address(cellarA), 5e18);

    //         // Attacker joins cellar right before price update.
    //         address attacker = vm.addr(8349058);
    //         deal(address(USDC), attacker, assets);
    //         vm.startPrank(attacker);
    //         USDC.approve(address(cellarA), assets);
    //         cellarA.deposit(assets, attacker);
    //         vm.stopPrank();

    //         // Price updates
    //         priceRouter.setExchangeRate(USDC, WETH, 0.000495e18);
    //         priceRouter.setExchangeRate(WETH, USDC, 2020e6);

    //         // Confirm attackers maxWithdraw is zero while shares are locked.
    //         assertEq(cellarA.maxWithdraw(attacker), 0, "Attackers maxWithdraw should be zero while shares are locked.");

    //         vm.startPrank(attacker);
    //         uint256 shares = cellarA.balanceOf(attacker);
    //         // Attacker tries to redeem their shares.
    //         vm.expectRevert(
    //             bytes(
    //                 abi.encodeWithSelector(
    //                     Cellar.Cellar__SharesAreLocked.selector,
    //                     block.number + cellarA.shareLockPeriod(),
    //                     block.number
    //                 )
    //             )
    //         );
    //         cellarA.redeem(shares, attacker, attacker);

    //         // Attacker tries to transfer shares to another address.
    //         vm.expectRevert(
    //             bytes(
    //                 abi.encodeWithSelector(
    //                     Cellar.Cellar__SharesAreLocked.selector,
    //                     block.number + cellarA.shareLockPeriod(),
    //                     block.number
    //                 )
    //             )
    //         );
    //         cellarA.transfer(address(this), shares);
    //         vm.stopPrank();

    //         vm.roll(block.number + cellarA.shareLockPeriod());

    //         // Confirm attackers shares are worth more once shares are unlocked.
    //         assertGt(cellarA.maxWithdraw(attacker), assets, "Attackers shares should be worth more than deposit.");

    //         // Note the attacker was able to arbitrage the price feed update, but must wait the share lock period in order to capture profit.
    //     }

    //     function testShareLockUpPeriod() external {
    //         // Try to set lock period to illogical value.
    //         vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidShareLockPeriod.selector)));
    //         cellar.setShareLockPeriod(type(uint32).max);

    //         vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidShareLockPeriod.selector)));
    //         cellar.setShareLockPeriod(0);

    //         // Set lock period to reasonable value.
    //         uint256 newLock = 8;
    //         cellar.setShareLockPeriod(newLock);
    //         assertEq(cellar.shareLockPeriod(), newLock, "Cellar share lock should equal newLock.");

    //         // Make sure user's who join with mint or deposit can not transfer, withdraw, or redeem for the shareLockPeriod.
    //         uint256 assets = 100e6;
    //         uint256 shares = 100e18;
    //         address depositUser = vm.addr(7777);
    //         address mintUser = vm.addr(77777);
    //         vm.startPrank(depositUser);
    //         deal(address(USDC), depositUser, assets);
    //         USDC.approve(address(cellar), assets);
    //         cellar.deposit(assets, depositUser);
    //         vm.expectRevert(
    //             bytes(
    //                 abi.encodeWithSelector(
    //                     Cellar.Cellar__SharesAreLocked.selector,
    //                     block.number + cellar.shareLockPeriod(),
    //                     block.number
    //                 )
    //             )
    //         );
    //         cellar.withdraw(assets, depositUser, depositUser);
    //         vm.expectRevert(
    //             bytes(
    //                 abi.encodeWithSelector(
    //                     Cellar.Cellar__SharesAreLocked.selector,
    //                     block.number + cellar.shareLockPeriod(),
    //                     block.number
    //                 )
    //             )
    //         );
    //         cellar.redeem(shares, depositUser, depositUser);
    //         vm.expectRevert(
    //             bytes(
    //                 abi.encodeWithSelector(
    //                     Cellar.Cellar__SharesAreLocked.selector,
    //                     block.number + cellar.shareLockPeriod(),
    //                     block.number
    //                 )
    //             )
    //         );
    //         cellar.transfer(address(this), shares);
    //         vm.stopPrank();

    //         vm.startPrank(mintUser);
    //         deal(address(USDC), mintUser, assets);
    //         USDC.approve(address(cellar), assets);
    //         cellar.mint(shares, mintUser);
    //         vm.expectRevert(
    //             bytes(
    //                 abi.encodeWithSelector(
    //                     Cellar.Cellar__SharesAreLocked.selector,
    //                     block.number + cellar.shareLockPeriod(),
    //                     block.number
    //                 )
    //             )
    //         );
    //         cellar.withdraw(assets, mintUser, mintUser);
    //         vm.expectRevert(
    //             bytes(
    //                 abi.encodeWithSelector(
    //                     Cellar.Cellar__SharesAreLocked.selector,
    //                     block.number + cellar.shareLockPeriod(),
    //                     block.number
    //                 )
    //             )
    //         );
    //         cellar.redeem(shares, mintUser, mintUser);
    //         vm.expectRevert(
    //             bytes(
    //                 abi.encodeWithSelector(
    //                     Cellar.Cellar__SharesAreLocked.selector,
    //                     block.number + cellar.shareLockPeriod(),
    //                     block.number
    //                 )
    //             )
    //         );
    //         cellar.transfer(address(this), shares);
    //         vm.stopPrank();

    //         // Advance block number to end of share lock period.
    //         vm.roll(block.number + cellar.shareLockPeriod());

    //         // Users can withdraw.
    //         vm.prank(depositUser);
    //         cellar.withdraw(assets, depositUser, depositUser);

    //         // Users can transfer.
    //         vm.prank(mintUser);
    //         cellar.transfer(depositUser, shares);

    //         // Users can redeem.
    //         vm.prank(depositUser);
    //         cellar.redeem(shares, depositUser, depositUser);

    //         // Check that if a user has waited the lock period but then decides to deposit again, they must wait for the new lock period to end.
    //         vm.startPrank(depositUser);
    //         deal(address(USDC), depositUser, assets);
    //         USDC.approve(address(cellar), 2 * assets);
    //         cellar.deposit(assets, depositUser);
    //         // Advance block number to end of share lock period.
    //         vm.roll(block.number + cellar.shareLockPeriod());

    //         // If user joins again, they must wait the lock period again, even if withdrawing previous amount.
    //         deal(address(USDC), depositUser, assets);
    //         cellar.deposit(assets, depositUser);
    //         vm.expectRevert(
    //             bytes(
    //                 abi.encodeWithSelector(
    //                     Cellar.Cellar__SharesAreLocked.selector,
    //                     block.number + cellar.shareLockPeriod(),
    //                     block.number
    //                 )
    //             )
    //         );
    //         cellar.withdraw(assets, depositUser, depositUser);
    //         vm.stopPrank();
    //     }

    //     function testDepositOnBehalf() external {
    //         address user = vm.addr(1111);
    //         uint256 assets = 100e6;
    //         deal(address(USDC), address(this), assets);
    //         vm.expectRevert(
    //             bytes(abi.encodeWithSelector(Cellar.Cellar__NotApprovedToDepositOnBehalf.selector, address(this)))
    //         );
    //         cellar.deposit(assets, user);

    //         // Add this address as an approved depositor.
    //         registry.setApprovedForDepositOnBehalf(address(this), true);
    //         // Deposits are now allowed.
    //         cellar.deposit(assets, user);
    //     }

    //     // Crowd Audit Tests
    //     //M-1 Accepted
    //     //M-2
    //     function testCellarDNOSPerformanceFeesWithZeroShares() external {
    //         //Attacker deposits 1 USDC into Cellar.
    //         uint256 assets = 1e6;
    //         address attacker = vm.addr(101);
    //         deal(address(USDC), attacker, assets);
    //         vm.prank(attacker);
    //         USDC.transfer(address(cellar), assets);

    //         address user = vm.addr(10101);
    //         deal(address(USDC), user, assets);

    //         vm.startPrank(user);
    //         USDC.approve(address(cellar), assets);
    //         cellar.deposit(assets, user);
    //         vm.stopPrank();

    //         assertEq(
    //             cellar.maxWithdraw(user),
    //             assets.mulWadDown(1.9e18),
    //             "User should be able to withdraw their assets and the attackers(minus performance fees)."
    //         );
    //     }
}
