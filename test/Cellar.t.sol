// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { ERC20DebtAdaptor } from "src/mocks/ERC20DebtAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { CellarWithViewFunctions } from "src/mocks/CellarWithViewFunctions.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    CellarWithViewFunctions private cellar;
    CellarWithViewFunctions private usdcCLR;
    CellarWithViewFunctions private wethCLR;
    CellarWithViewFunctions private wbtcCLR;

    CellarAdaptor private cellarAdaptor;

    MockDataFeed private mockUsdcUsd;
    MockDataFeed private mockWethUsd;
    MockDataFeed private mockWbtcUsd;
    MockDataFeed private mockUsdtUsd;

    uint32 private usdcPosition = 1;
    uint32 private wethPosition = 2;
    uint32 private wbtcPosition = 3;
    uint32 private usdcCLRPosition = 4;
    uint32 private wethCLRPosition = 5;
    uint32 private wbtcCLRPosition = 6;
    uint32 private usdtPosition = 7;

    uint256 private initialAssets;
    uint256 private initialShares;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockUsdcUsd = new MockDataFeed(USDC_USD_FEED);
        mockWethUsd = new MockDataFeed(WETH_USD_FEED);
        mockWbtcUsd = new MockDataFeed(WBTC_USD_FEED);
        mockUsdtUsd = new MockDataFeed(USDT_USD_FEED);
        cellarAdaptor = new CellarAdaptor();

        // Setup pricing
        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(mockUsdcUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUsdcUsd));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(mockWethUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWethUsd));
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(mockWbtcUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockWbtcUsd));
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        price = uint256(mockUsdtUsd.latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockUsdtUsd));
        priceRouter.addAsset(USDT, settings, abi.encode(stor), price);

        // Setup exchange rates:
        // USDC Simulated Price: $1
        // WETH Simulated Price: $2000
        // WBTC Simulated Price: $30,000
        mockUsdcUsd.setMockAnswer(1e8);
        mockWethUsd.setMockAnswer(2_000e8);
        mockWbtcUsd.setMockAnswer(30_000e8);
        mockUsdtUsd.setMockAnswer(1e8);

        // Add adaptors and ERC20 positions to the registry.
        registry.trustAdaptor(address(cellarAdaptor));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));
        registry.trustPosition(usdtPosition, address(erc20Adaptor), abi.encode(USDT));

        // Create Dummy Cellars.
        string memory cellarName = "Dummy Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        usdcCLR = _createCellarWithViewFunctions(
            cellarName,
            USDC,
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );
        vm.label(address(usdcCLR), "usdcCLR");

        cellarName = "Dummy Cellar V0.1";
        initialDeposit = 1e12;
        platformCut = 0.75e18;
        wethCLR = _createCellarWithViewFunctions(
            cellarName,
            WETH,
            wethPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );
        vm.label(address(wethCLR), "wethCLR");

        cellarName = "Dummy Cellar V0.2";
        initialDeposit = 1e4;
        platformCut = 0.75e18;
        wbtcCLR = _createCellarWithViewFunctions(
            cellarName,
            WBTC,
            wbtcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );
        vm.label(address(wbtcCLR), "wbtcCLR");

        // Add Cellar Positions to the registry.
        registry.trustPosition(usdcCLRPosition, address(cellarAdaptor), abi.encode(usdcCLR));
        registry.trustPosition(wethCLRPosition, address(cellarAdaptor), abi.encode(wethCLR));
        registry.trustPosition(wbtcCLRPosition, address(cellarAdaptor), abi.encode(wbtcCLR));

        cellarName = "Cellar V0.0";
        initialDeposit = 1e6;
        platformCut = 0.75e18;
        cellar = _createCellarWithViewFunctions(
            cellarName,
            USDC,
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );

        // Set up remaining cellar positions.
        cellar.addPositionToCatalogue(usdcCLRPosition);
        cellar.addPosition(1, usdcCLRPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wethCLRPosition);
        cellar.addPosition(2, wethCLRPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wbtcCLRPosition);
        cellar.addPosition(3, wbtcCLRPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(4, wethPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wbtcPosition);
        cellar.addPosition(5, wbtcPosition, abi.encode(true), false);
        cellar.addAdaptorToCatalogue(address(cellarAdaptor));
        cellar.addPositionToCatalogue(usdtPosition);

        cellar.setStrategistPayoutAddress(strategist);

        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
        initialShares = cellar.totalSupply();
    }

    // ========================================= INITIALIZATION TEST =========================================

    function testInitialization() external {
        assertEq(address(cellar.registry()), address(registry), "Should initialize registry to test registry.");

        uint32[] memory expectedPositions = new uint32[](6);
        expectedPositions[0] = usdcPosition;
        expectedPositions[1] = usdcCLRPosition;
        expectedPositions[2] = wethCLRPosition;
        expectedPositions[3] = wbtcCLRPosition;
        expectedPositions[4] = wethPosition;
        expectedPositions[5] = wbtcPosition;

        address[] memory expectedAdaptor = new address[](6);
        expectedAdaptor[0] = address(erc20Adaptor);
        expectedAdaptor[1] = address(cellarAdaptor);
        expectedAdaptor[2] = address(cellarAdaptor);
        expectedAdaptor[3] = address(cellarAdaptor);
        expectedAdaptor[4] = address(erc20Adaptor);
        expectedAdaptor[5] = address(erc20Adaptor);

        bytes[] memory expectedAdaptorData = new bytes[](6);
        expectedAdaptorData[0] = abi.encode(USDC);
        expectedAdaptorData[1] = abi.encode(usdcCLR);
        expectedAdaptorData[2] = abi.encode(wethCLR);
        expectedAdaptorData[3] = abi.encode(wbtcCLR);
        expectedAdaptorData[4] = abi.encode(WETH);
        expectedAdaptorData[5] = abi.encode(WBTC);

        uint32[] memory positions = cellar.getCreditPositions();

        assertEq(cellar.getCreditPositions().length, 6, "Position length should be 5.");

        for (uint256 i = 0; i < 6; i++) {
            assertEq(positions[i], expectedPositions[i], "Positions should have been written to Cellar.");
            uint32 position = positions[i];
            (address adaptor, bool isDebt, bytes memory adaptorData, ) = cellar.getPositionDataView(position);
            assertEq(adaptor, expectedAdaptor[i], "Position adaptor not initialized properly.");
            assertEq(isDebt, false, "There should be no debt positions.");
            assertEq(adaptorData, expectedAdaptorData[i], "Position adaptor data not initialized properly.");
        }

        assertEq(address(cellar.asset()), address(USDC), "Should initialize asset to be USDC.");

        // (, , uint64 lastAccrual, ) = cellar.feeData();

        (uint64 strategistPlatformCut, , , address strategistPayoutAddress) = cellar.feeData();
        assertEq(strategistPlatformCut, 0.75e18, "Platform cut should be set to 0.75e18.");
        assertEq(strategistPayoutAddress, strategist, "Strategist payout address should be equal to strategist.");

        assertEq(cellar.owner(), address(this), "Should initialize owner to this contract.");
    }

    // ========================================= DEPOSIT/WITHDRAW TEST =========================================

    function testDepositAndWithdraw(uint256 assets) external {
        assets = bound(assets, 1, type(uint72).max);

        deal(address(USDC), address(this), assets);

        // Try depositing more assets than balance.
        vm.expectRevert("TRANSFER_FROM_FAILED");
        cellar.deposit(assets + 1, address(this));

        // Test single deposit.
        uint256 expectedShares = cellar.previewDeposit(assets);
        uint256 shares = cellar.deposit(assets, address(this));

        assertEq(shares, assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assets), shares, "Withdrawing assets should burn shares given.");
        assertEq(shares, expectedShares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares + initialShares, "Should have updated total supply with shares minted.");
        assertEq(
            cellar.totalAssets(),
            assets + initialAssets,
            "Should have updated total assets with assets deposited."
        );
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.balanceOf(address(cellar)), 0, "Should not have minted fees because no gains.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // Try withdrawing more assets than allowed.
        vm.expectRevert(stdError.arithmeticError);
        cellar.withdraw(assets + 1, address(this), address(this));

        // Test single withdraw.
        cellar.withdraw(assets, address(this), address(this));

        assertEq(cellar.totalAssets(), initialAssets, "Should have updated total assets with assets withdrawn.");
        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(USDC.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    function testMintAndRedeem(uint256 shares) external {
        shares = bound(shares, 1e6, type(uint112).max);

        // Change decimals from the 18 used by shares to the 6 used by USDC.
        deal(address(USDC), address(this), shares);

        // Try minting more assets than balance.
        vm.expectRevert("TRANSFER_FROM_FAILED");
        cellar.mint(shares + 1e18, address(this));

        // Test single mint.
        uint256 assets = cellar.mint(shares, address(this));

        assertEq(shares, assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewRedeem(shares), assets, "Redeeming shares should withdraw assets owed.");
        assertEq(cellar.previewMint(shares), assets, "Minting shares should deposit assets owed.");
        assertEq(cellar.totalSupply(), shares + initialShares, "Should have updated total supply with shares minted.");
        assertEq(
            cellar.totalAssets(),
            assets + initialAssets,
            "Should have updated total assets with assets deposited."
        );
        assertEq(cellar.balanceOf(address(this)), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), assets, "Should return all user's assets.");
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // Test single redeem.
        cellar.redeem(shares, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(address(this))), 0, "Should return zero assets.");
        assertEq(USDC.balanceOf(address(this)), assets, "Should have withdrawn assets to user.");
    }

    function testWithdrawInOrder() external {
        // Deposit enough assets into the Cellar to rebalance.
        uint256 assets = 32_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        _depositToCellar(cellar, wethCLR, 2_000e6); // 1 Ether
        _depositToCellar(cellar, wbtcCLR, 30_000e6); // 1 WBTC
        assertEq(
            cellar.totalAssets(),
            assets + initialAssets,
            "Should have updated total assets with assets deposited."
        );

        // Move USDC position to the back of the withdraw queue.
        cellar.swapPositions(0, 3, false);

        // Withdraw from position.
        uint256 shares = cellar.withdraw(32_000e6, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed all shares.");
        assertEq(shares, 32_000e6, "Should returned all redeemed shares.");
        assertEq(WETH.balanceOf(address(this)), 1e18, "Should have transferred position balance to user.");
        assertEq(WBTC.balanceOf(address(this)), 1e8, "Should have transferred position balance to user.");
        assertLt(WETH.balanceOf(address(wethCLR)), 1e18, "Should have transferred balance from WETH position.");
        assertLt(WBTC.balanceOf(address(wbtcCLR)), 1e8, "Should have transferred balance from BTC position.");
        assertEq(cellar.totalAssets(), initialAssets, "Cellar total assets should equal initial.");
    }

    function testWithdrawWithDuplicateReceivedAssets() external {
        string memory cellarName = "Dummy Cellar V0.3";
        uint256 initialDeposit = 1e12;
        uint64 platformCut = 0.75e18;
        Cellar wethVault = _createCellarWithViewFunctions(
            cellarName,
            WETH,
            wethPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );

        uint32 newWETHPosition = 10;
        registry.trustPosition(newWETHPosition, address(cellarAdaptor), abi.encode(wethVault));
        cellar.addPositionToCatalogue(newWETHPosition);
        cellar.addPosition(1, newWETHPosition, abi.encode(true), false);

        // Deposit enough assets into the Cellar to rebalance.
        uint256 assets = 3_000e6;
        deal(address(USDC), address(this), assets);
        cellar.deposit(assets, address(this));

        _depositToCellar(cellar, wethCLR, 2_000e6); // 1 Ether
        _depositToCellar(cellar, wethVault, 1_000e6); // 0.5 Ether

        assertEq(
            cellar.totalAssets(),
            3_000e6 + initialAssets,
            "Should have updated total assets with assets deposited."
        );
        assertEq(cellar.totalSupply(), 3_000e6 + initialShares, "Should have updated total supply with deposit");

        // Move USDC position to the back of the withdraw queue.
        cellar.swapPositions(0, 4, false);

        // Withdraw from position.
        uint256 shares = cellar.withdraw(3_000e6, address(this), address(this));

        assertEq(cellar.balanceOf(address(this)), 0, "Should have redeemed all shares.");
        assertEq(shares, 3000e6, "Should returned all redeemed shares.");
        assertEq(WETH.balanceOf(address(this)), 1.5e18, "Should have transferred position balance to user.");
        assertLt(WETH.balanceOf(address(wethCLR)), 1e18, "Should have transferred balance from WETH cellar position.");
        assertLt(
            WETH.balanceOf(address(wethVault)),
            0.5e18,
            "Should have transferred balance from WETH vault position."
        );
        assertEq(cellar.totalAssets(), initialAssets, "Cellar total assets should equal initial.");
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

    // ========================================= LIMITS TEST =========================================

    function testLimits() external {
        // Currently limits are not set, so they should report type(uint256).max
        assertEq(cellar.maxDeposit(address(this)), type(uint256).max, "Max Deposit should equal type(uint256).max");
        assertEq(cellar.maxMint(address(this)), type(uint256).max, "Max Mint should equal type(uint256).max");

        uint192 newCap = 100e6;
        cellar.decreaseShareSupplyCap(newCap);
        assertEq(cellar.shareSupplyCap(), newCap, "Share Supply Cap should have been updated.");
        uint256 totalAssets = cellar.totalAssets();
        // Since shares are currently 1:1 with assets, they are interchangeable in below equation.
        uint256 expectedMax = newCap - totalAssets;
        assertEq(cellar.maxDeposit(address(this)), expectedMax, "Max Deposit should equal expected.");
        assertEq(cellar.maxMint(address(this)), expectedMax, "Max Mint should equal expected.");

        uint256 amountToExceedCap = expectedMax + 1;
        deal(address(USDC), address(this), amountToExceedCap);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ShareSupplyCapExceeded.selector)));
        cellar.deposit(amountToExceedCap, address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ShareSupplyCapExceeded.selector)));
        cellar.mint(amountToExceedCap, address(this));

        // But if 1 wei is removed, deposit works.
        cellar.deposit(amountToExceedCap - 1, address(this));

        // Max function should now return 0.
        assertEq(cellar.maxDeposit(address(this)), 0, "Max Deposit should equal 0");
        assertEq(cellar.maxMint(address(this)), 0, "Max Mint should equal 0");
    }

    // ========================================== POSITIONS TEST ==========================================

    function testInteractingWithDistrustedPositions() external {
        cellar.removePosition(4, false);
        cellar.removePositionFromCatalogue(wethPosition); // Removes WETH position from catalogue.

        // Cellar should not be able to add position to tracked array until it is in the catalogue.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionNotInCatalogue.selector, wethPosition)));
        cellar.addPosition(4, wethPosition, abi.encode(true), false);

        // Since WETH position is trusted, cellar should be able to add it to the catalogue, and to the tracked array.
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(4, wethPosition, abi.encode(true), false);

        // Registry distrusts weth position.
        registry.distrustPosition(wethPosition);

        // Even though position is distrusted Cellar can still operate normally.
        cellar.totalAssets();

        // Distrusted position is still in tracked array, but strategist/governance can remove it.
        cellar.removePosition(4, false);

        // If strategist tries adding it back it reverts.
        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__PositionIsNotTrusted.selector, wethPosition)));
        cellar.addPosition(4, wethPosition, abi.encode(true), false);

        // Governance removes position from cellars catalogue.
        cellar.removePositionFromCatalogue(wethPosition); // Removes WETH position from catalogue.

        // But tries to add it back later which reverts.
        vm.expectRevert(bytes(abi.encodeWithSelector(Registry.Registry__PositionIsNotTrusted.selector, wethPosition)));
        cellar.addPositionToCatalogue(wethPosition);
    }

    function testInteractingWithDistrustedAdaptors() external {
        cellar.removeAdaptorFromCatalogue(address(cellarAdaptor));

        // With adaptor removed, rebalance calls to it revert.
        bytes[] memory emptyCall;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: emptyCall });

        vm.expectRevert(
            bytes(abi.encodeWithSelector(Cellar.Cellar__CallToAdaptorNotAllowed.selector, address(cellarAdaptor)))
        );
        cellar.callOnAdaptor(data);

        // Add the adaptor back to the catalogue.
        cellar.addAdaptorToCatalogue(address(cellarAdaptor));

        // Calls to it now work.
        cellar.callOnAdaptor(data);

        // Registry distrusts the adaptor, but cellar can still use it.
        registry.distrustAdaptor(address(cellarAdaptor));
        cellar.callOnAdaptor(data);

        // But now if adaptor is removed from the catalogue it can not be re-added.
        cellar.removeAdaptorFromCatalogue(address(cellarAdaptor));

        vm.expectRevert(
            bytes(abi.encodeWithSelector(Registry.Registry__AdaptorNotTrusted.selector, address(cellarAdaptor)))
        );
        cellar.addAdaptorToCatalogue(address(cellarAdaptor));
    }

    function testManagingPositions() external {
        uint256 positionLength = cellar.getCreditPositions().length;

        // Check that `removePosition` actually removes it.
        cellar.removePosition(4, false);

        assertEq(
            positionLength - 1,
            cellar.getCreditPositions().length,
            "Cellar positions array should be equal to previous length minus 1."
        );

        assertFalse(cellar.isPositionUsed(wethPosition), "`isPositionUsed` should be false for WETH.");
        (address zeroAddressAdaptor, , , ) = cellar.getPositionDataView(wethPosition);
        assertEq(zeroAddressAdaptor, address(0), "Removing position should have deleted position data.");
        // Check that adding a credit position as debt reverts.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__DebtMismatch.selector, wethPosition)));
        cellar.addPosition(4, wethPosition, abi.encode(true), true);

        // Check that `addPosition` actually adds it.
        cellar.addPosition(4, wethPosition, abi.encode(true), false);

        assertEq(
            positionLength,
            cellar.getCreditPositions().length,
            "Cellar positions array should be equal to previous length."
        );

        assertEq(cellar.getCreditPosition(4), wethPosition, "`positions[4]` should be WETH.");
        assertTrue(cellar.isPositionUsed(wethPosition), "`isPositionUsed` should be true for WETH.");

        // Check that `addPosition` reverts if position is already used.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionAlreadyUsed.selector, wethPosition)));
        cellar.addPosition(4, wethPosition, abi.encode(true), false);

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
        cellar.removePosition(4, false);

        // Check that `addPosition` reverts if position is not trusted.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionNotInCatalogue.selector, 0)));
        cellar.addPosition(4, 0, abi.encode(true), false);

        // Check that `addPosition` reverts if debt position is not trusted.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionNotInCatalogue.selector, 0)));
        cellar.addPosition(4, 0, abi.encode(0), true);

        // Set Cellar WETH balance to 0.
        deal(address(WETH), address(cellar), 0);

        cellar.removePosition(4, false);

        // Check that addPosition sets position data.
        cellar.addPosition(4, wethPosition, abi.encode(true), false);
        (address adaptor, bool isDebt, bytes memory adaptorData, bytes memory configurationData) = cellar
            .getPositionDataView(wethPosition);
        assertEq(adaptor, address(erc20Adaptor), "Adaptor should be the ERC20 adaptor.");
        assertTrue(!isDebt, "Position should not be debt.");
        assertEq(adaptorData, abi.encode((WETH)), "Adaptor data should be abi encoded WETH.");
        assertEq(configurationData, abi.encode(true), "Configuration data should be abi encoded ZERO.");

        // Check that `swapPosition` works as expected.
        cellar.swapPositions(4, 2, false);
        assertEq(cellar.getCreditPosition(4), wethCLRPosition, "`positions[4]` should be wethCLR.");
        assertEq(cellar.getCreditPosition(2), wethPosition, "`positions[2]` should be WETH.");

        // Try setting the holding position to an unused position.
        uint32 invalidPositionId = 100;
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__PositionNotUsed.selector, invalidPositionId)));
        cellar.setHoldingPosition(invalidPositionId);

        // Try setting holding position with a position with different asset.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Cellar.Cellar__AssetMismatch.selector, address(USDC), address(WETH)))
        );
        cellar.setHoldingPosition(wethPosition);

        // Set holding position to usdcCLR.
        cellar.setHoldingPosition(usdcCLRPosition);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__RemovingHoldingPosition.selector)));
        // Try removing the holding position.
        cellar.removePosition(1, false);

        // Set holding position back to USDC.
        cellar.setHoldingPosition(usdcPosition);

        // Work with debt positions now.
        // Try setting holding position to a debt position.
        ERC20DebtAdaptor debtAdaptor = new ERC20DebtAdaptor();
        registry.trustAdaptor(address(debtAdaptor));
        uint32 debtWethPosition = 101;
        registry.trustPosition(debtWethPosition, address(debtAdaptor), abi.encode(WETH));
        uint32 debtWbtcPosition = 102;
        registry.trustPosition(debtWbtcPosition, address(debtAdaptor), abi.encode(WBTC));

        uint32 debtUsdcPosition = 103;
        registry.trustPosition(debtUsdcPosition, address(debtAdaptor), abi.encode(USDC));
        cellar.addPositionToCatalogue(debtUsdcPosition);
        cellar.addPositionToCatalogue(debtWethPosition);
        cellar.addPositionToCatalogue(debtWbtcPosition);
        cellar.addPosition(0, debtUsdcPosition, abi.encode(0), true);
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidHoldingPosition.selector, debtUsdcPosition))
        );
        cellar.setHoldingPosition(debtUsdcPosition);

        registry.distrustPosition(debtUsdcPosition);
        cellar.forcePositionOut(0, debtUsdcPosition, true);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__DebtMismatch.selector, debtWethPosition)));
        cellar.addPosition(0, debtWethPosition, abi.encode(0), false);

        cellar.addPosition(0, debtWethPosition, abi.encode(0), true);
        assertEq(cellar.getDebtPositions().length, 1, "Debt positions should be length 1.");

        cellar.addPosition(0, debtWbtcPosition, abi.encode(0), true);
        assertEq(cellar.getDebtPositions().length, 2, "Debt positions should be length 2.");

        // Remove all debt.
        cellar.removePosition(0, true);
        assertEq(cellar.getDebtPositions().length, 1, "Debt positions should be length 1.");

        cellar.removePosition(0, true);
        assertEq(cellar.getDebtPositions().length, 0, "Debt positions should be length 1.");

        // Add debt positions back.
        cellar.addPosition(0, debtWethPosition, abi.encode(0), true);
        assertEq(cellar.getDebtPositions().length, 1, "Debt positions should be length 1.");

        cellar.addPosition(0, debtWbtcPosition, abi.encode(0), true);
        assertEq(cellar.getDebtPositions().length, 2, "Debt positions should be length 2.");

        // Check force position out logic.
        // Give Cellar 1 WEI WETH.
        deal(address(WETH), address(cellar), 1);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    Cellar.Cellar__PositionNotEmpty.selector,
                    wethPosition,
                    WETH.balanceOf(address(cellar))
                )
            )
        );
        cellar.removePosition(2, false);

        // Try forcing out the wrong position.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__FailedToForceOutPosition.selector)));
        cellar.forcePositionOut(4, wethPosition, false);

        // Try forcing out a position that is trusted
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__FailedToForceOutPosition.selector)));
        cellar.forcePositionOut(2, wethPosition, false);

        // When correct index is used, and position is distrusted call works.
        registry.distrustPosition(wethPosition);
        cellar.forcePositionOut(2, wethPosition, false);

        assertTrue(!cellar.isPositionUsed(wethPosition), "WETH Position should have been forced out.");
    }

    // ========================================== REBALANCE TEST ==========================================

    function testSettingBadRebalanceDeviation() external {
        // Max rebalance deviation value is 10%.
        uint256 deviation = 0.2e18;
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidRebalanceDeviation.selector, deviation, 0.1e18))
        );
        cellar.setRebalanceDeviation(deviation);
    }

    // ======================================== EMERGENCY TESTS ========================================

    function testRegistryPauseStoppingAllCellarActions() external {
        // Empty call on adaptor argument.
        bytes[] memory emptyCall;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: emptyCall });

        address[] memory targets = new address[](1);
        targets[0] = address(cellar);

        registry.batchPause(targets);

        assertEq(cellar.isPaused(), true, "Cellar should be paused.");

        // Cellar is fully paused.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.deposit(1e6, address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.mint(1e6, address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.withdraw(1e6, address(this), address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.redeem(1e6, address(this), address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.totalAssets();

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.totalAssetsWithdrawable();

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.maxWithdraw(address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.maxRedeem(address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.callOnAdaptor(data);

        // Once cellar is unpaused all actions resume as normal.
        registry.batchUnpause(targets);
        assertEq(cellar.isPaused(), false, "Cellar should not be paused.");
        deal(address(USDC), address(this), 100e6);
        cellar.deposit(1e6, address(this));
        cellar.mint(1e6, address(this));
        cellar.withdraw(1e6, address(this), address(this));
        cellar.redeem(1e6, address(this), address(this));
        cellar.totalAssets();
        cellar.totalAssetsWithdrawable();
        cellar.maxWithdraw(address(this));
        cellar.maxRedeem(address(this));
        cellar.callOnAdaptor(data);
    }

    function testRegistryPauseButCellarIgnoringIt() external {
        // Empty call on adaptor argument.
        bytes[] memory emptyCall;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: emptyCall });

        address[] memory targets = new address[](1);
        targets[0] = address(cellar);

        registry.batchPause(targets);

        // Cellar is fully paused, but governance chooses to ignore it.
        cellar.toggleIgnorePause();
        assertEq(cellar.isPaused(), false, "Cellar should not be paused.");

        deal(address(USDC), address(this), 100e6);
        cellar.deposit(1e6, address(this));
        cellar.mint(1e6, address(this));
        cellar.withdraw(1e6, address(this), address(this));
        cellar.redeem(1e6, address(this), address(this));
        cellar.totalAssets();
        cellar.totalAssetsWithdrawable();
        cellar.maxWithdraw(address(this));
        cellar.maxRedeem(address(this));
        cellar.callOnAdaptor(data);

        // Governance chooses to accept the pause.
        cellar.toggleIgnorePause();
        assertEq(cellar.isPaused(), true, "Cellar should be paused.");

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.deposit(1e6, address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.mint(1e18, address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.withdraw(1e6, address(this), address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.redeem(1e6, address(this), address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.totalAssets();

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.totalAssetsWithdrawable();

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.maxWithdraw(address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.maxRedeem(address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__Paused.selector)));
        cellar.callOnAdaptor(data);
    }

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
        cellar.addPosition(5, 0, abi.encode(0), false);

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

    function testCachePriceRouter() external {
        uint256 assets = 100e6;

        // Give this address enough USDC to cover deposits.
        deal(address(USDC), address(this), assets);

        // Deposit USDC into Cellar.
        cellar.deposit(assets, address(this));
        assertEq(
            address(cellar.priceRouter()),
            address(priceRouter),
            "Price Router saved in cellar should equal current."
        );

        // Manipulate state so that stored price router reverts with pricing calls.
        stdstore.target(address(cellar)).sig(cellar.priceRouter.selector).checked_write(address(0));
        vm.expectRevert();
        cellar.totalAssets();

        // Governance can recover cellar by calling `cachePriceRouter(false)`.
        cellar.cachePriceRouter(false, 0.05e4, registry.getAddress(2));
        assertEq(
            address(cellar.priceRouter()),
            address(priceRouter),
            "Price Router saved in cellar should equal current."
        );

        // Now that price router is correct, calling it again should succeed even though it doesn't set anything.
        cellar.cachePriceRouter(true, 0.05e4, registry.getAddress(2));

        // Registry sets a malicious price router.
        registry.setAddress(2, address(this));

        // Try to set it as the cellars price router.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(Cellar.Cellar__TotalAssetDeviatedOutsideRange.selector, 50e6, 95.95e6, 106.05e6)
            )
        );
        cellar.cachePriceRouter(true, 0.05e4, address(this));

        // Set registry back to use old price router.
        registry.setAddress(2, address(priceRouter));

        // Multisig tries to change the price router address once governance prop goes through.
        registry.setAddress(2, address(this));

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ExpectedAddressDoesNotMatchActual.selector)));
        cellar.cachePriceRouter(true, 0.05e4, address(priceRouter));
    }

    function testTotalAssets(
        uint256 usdcAmount,
        uint256 usdcCLRAmount,
        uint256 wethCLRAmount,
        uint256 wbtcCLRAmount,
        uint256 wethAmount
    ) external {
        usdcAmount = bound(usdcAmount, 1e6, 1_000_000e6);
        usdcCLRAmount = bound(usdcCLRAmount, 1e6, 1_000_000e6);
        wethCLRAmount = bound(wethCLRAmount, 1e6, 1_000_000e6);
        wbtcCLRAmount = bound(wbtcCLRAmount, 1e6, 1_000_000e6);
        wethAmount = bound(wethAmount, 1e18, 10_000e18);
        uint256 totalAssets = cellar.totalAssets();

        assertEq(totalAssets, initialAssets, "Cellar total assets should be initialAssets.");

        deal(address(USDC), address(this), usdcCLRAmount + wethCLRAmount + wbtcCLRAmount + usdcAmount);
        cellar.deposit(usdcCLRAmount + wethCLRAmount + wbtcCLRAmount + usdcAmount, address(this));

        _depositToCellar(cellar, usdcCLR, usdcCLRAmount);
        _depositToCellar(cellar, wethCLR, wethCLRAmount);
        _depositToCellar(cellar, wbtcCLR, wbtcCLRAmount);
        deal(address(WETH), address(cellar), wethAmount);

        uint256 expectedTotalAssets = usdcAmount +
            usdcCLRAmount +
            priceRouter.getValue(WETH, wethAmount, USDC) +
            wethCLRAmount +
            wbtcCLRAmount +
            initialAssets;

        totalAssets = cellar.totalAssets();

        assertApproxEqRel(
            totalAssets,
            expectedTotalAssets,
            0.0001e18,
            "`totalAssets` should equal all asset values summed together."
        );
    }

    // ====================================== PLATFORM FEE TEST ======================================

    function testChangingFeeData() external {
        address newStrategistAddress = vm.addr(777);
        cellar.setStrategistPlatformCut(0.8e18);
        cellar.setStrategistPayoutAddress(newStrategistAddress);
        (uint64 strategistPlatformCut, , , address strategistPayoutAddress) = cellar.feeData();
        assertEq(strategistPlatformCut, 0.8e18, "Platform cut should be set to 0.8e18.");
        assertEq(
            strategistPayoutAddress,
            newStrategistAddress,
            "Strategist payout address should be set to `newStrategistAddress`."
        );

        // vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidFee.selector)));
        // cellar.setPlatformFee(0.21e18);

        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidFeeCut.selector)));
        cellar.setStrategistPlatformCut(1.1e18);
    }

    function testDebtTokensInCellars() external {
        ERC20DebtAdaptor debtAdaptor = new ERC20DebtAdaptor();
        registry.trustAdaptor(address(debtAdaptor));
        uint32 debtWethPosition = 10;
        registry.trustPosition(debtWethPosition, address(debtAdaptor), abi.encode(WETH));
        uint32 debtWbtcPosition = 11;
        registry.trustPosition(debtWbtcPosition, address(debtAdaptor), abi.encode(WBTC));

        // Setup Cellar with debt positions:
        string memory cellarName = "Debt Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        CellarWithViewFunctions debtCellar = _createCellarWithViewFunctions(
            cellarName,
            USDC,
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );

        debtCellar.addPositionToCatalogue(debtWethPosition);
        debtCellar.addPositionToCatalogue(debtWbtcPosition);
        debtCellar.addPosition(0, debtWethPosition, abi.encode(0), true);

        //constructor should set isDebt
        (, bool isDebt, , ) = debtCellar.getPositionDataView(debtWethPosition);
        assertTrue(isDebt, "Constructor should have set WETH as a debt position.");
        assertEq(debtCellar.getDebtPositions().length, 1, "Cellar should have 1 debt position");

        //Add another debt position WBTC.
        //adding WBTC should increment number of debt positions.
        debtCellar.addPosition(0, debtWbtcPosition, abi.encode(0), true);
        assertEq(debtCellar.getDebtPositions().length, 2, "Cellar should have 2 debt positions");

        (, isDebt, , ) = debtCellar.getPositionDataView(debtWbtcPosition);
        assertTrue(isDebt, "Constructor should have set WBTC as a debt position.");
        assertEq(debtCellar.getDebtPositions().length, 2, "Cellar should have 2 debt positions");

        // removing WBTC should decrement number of debt positions.
        debtCellar.removePosition(0, true);
        assertEq(debtCellar.getDebtPositions().length, 1, "Cellar should have 1 debt position");

        // Adding a debt position, but specifying it as a credit position should revert.
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__DebtMismatch.selector, debtWbtcPosition)));
        debtCellar.addPosition(0, debtWbtcPosition, abi.encode(0), false);

        debtCellar.addPosition(0, debtWbtcPosition, abi.encode(0), true);

        // Give debt cellar some assets.
        deal(address(USDC), address(debtCellar), 100_000e6);
        deal(address(WBTC), address(debtCellar), 1e8);
        deal(address(WETH), address(debtCellar), 10e18);

        uint256 totalAssets = debtCellar.totalAssets();
        uint256 expectedTotalAssets = 50_000e6;

        assertEq(totalAssets, expectedTotalAssets, "Debt cellar total assets should equal expected.");
    }

    function testCellarWithCellarPositions() external {
        // Cellar A's asset is USDC, holding position is Cellar B shares, whose holding asset is USDC.
        // Initialize test Cellars.

        // Create Cellar B
        string memory cellarName = "Cellar B V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;
        Cellar cellarB = _createCellarWithViewFunctions(
            cellarName,
            USDC,
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );

        uint32 cellarBPosition = 10;
        registry.trustPosition(cellarBPosition, address(cellarAdaptor), abi.encode(cellarB));

        // Create Cellar A
        cellarName = "Cellar A V0.0";
        initialDeposit = 1e6;
        platformCut = 0.75e18;
        Cellar cellarA = _createCellarWithViewFunctions(
            cellarName,
            USDC,
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );

        cellarA.addPositionToCatalogue(cellarBPosition);
        cellarA.addPosition(0, cellarBPosition, abi.encode(true), false);
        cellarA.setHoldingPosition(cellarBPosition);
        cellarA.swapPositions(0, 1, false);

        uint256 assets = 100e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellarA), assets);
        cellarA.deposit(assets, address(this));

        uint256 withdrawAmount = cellarA.maxWithdraw(address(this));
        assertEq(assets, withdrawAmount, "Assets should not have changed.");
        assertEq(cellarA.totalAssets(), cellarB.totalAssets(), "Total assets should be the same.");

        cellarA.withdraw(withdrawAmount, address(this), address(this));
    }

    function testCallerOfCallOnAdaptor() external {
        // Specify a zero length Adaptor Call array.
        Cellar.AdaptorCall[] memory data;

        // address automationActions = vm.addr(5);
        // registry.register(automationActions);
        // cellar.setAutomationActions(3, automationActions);

        // Only owner and automation actions can call `callOnAdaptor`.
        cellar.callOnAdaptor(data);

        // vm.prank(automationActions);
        // cellar.callOnAdaptor(data);

        // // Update Automation Actions contract to zero address.
        // cellar.setAutomationActions(4, address(0));

        // // Call now reverts.
        // vm.startPrank(automationActions);
        // vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__CallerNotApprovedToRebalance.selector)));
        // cellar.callOnAdaptor(data);
        // vm.stopPrank();

        // Owner can still call callOnAdaptor.
        cellar.callOnAdaptor(data);

        // registry.setAddress(3, automationActions);

        // // Governance tries to set automation actions to registry address 3, but malicious multisig changes it after prop passes.
        // registry.setAddress(3, address(this));

        // vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ExpectedAddressDoesNotMatchActual.selector)));
        // cellar.setAutomationActions(3, automationActions);

        // // Try setting automation actions to registry id 0.
        // vm.expectRevert(
        //     bytes(abi.encodeWithSelector(Cellar.Cellar__SettingValueToRegistryIdZeroIsProhibited.selector))
        // );
        // cellar.setAutomationActions(0, automationActions);
    }

    // ======================================== DEPEGGING ASSET TESTS ========================================

    function testDepeggedAssetNotUsedByCellar() external {
        // Scenario 1: Depegged asset is not being used by the cellar.
        // Governance can remove it itself by calling `distrustPosition`.

        // Add asset that will be depegged.
        cellar.addPosition(5, usdtPosition, abi.encode(true), false);

        deal(address(USDC), address(this), 200e6);
        cellar.deposit(100e6, address(this));

        // USDT depeggs to $0.90.
        mockUsdtUsd.setMockAnswer(0.9e8);

        assertEq(cellar.totalAssets(), 100e6 + initialAssets, "Cellar total assets should remain unchanged.");
        assertEq(cellar.deposit(100e6, address(this)), 100e6, "Cellar share price should not change.");
    }

    function testDepeggedAssetUsedByTheCellar() external {
        // Scenario 2: Depegged asset is being used by the cellar. Governance
        // uses multicall to rebalance cellar out of position, and to distrust
        // it.

        // Add asset that will be depegged.
        cellar.addPosition(5, usdtPosition, abi.encode(true), false);

        deal(address(USDC), address(this), 200e6);
        cellar.deposit(100e6, address(this));

        //Change Cellar holdings manually to 50/50 USDC/USDT.
        deal(address(USDC), address(cellar), 50e6);
        deal(address(USDT), address(cellar), 50e6);

        // USDT depeggs to $0.90.
        mockUsdtUsd.setMockAnswer(0.9e8);

        assertEq(cellar.totalAssets(), 95e6, "Cellar total assets should have gone down.");
        assertGt(cellar.deposit(100e6, address(this)), 100e6, "Cellar share price should have decreased.");

        // Governance votes to rebalance out of USDT, and distrust USDT.
        // Manually rebalance into USDC.
        deal(address(USDC), address(cellar), 95e6);
        deal(address(USDT), address(cellar), 0);
    }

    function testDepeggedHoldingPosition() external {
        // Scenario 3: Depegged asset is being used by the cellar, and it is the
        // holding position. Governance uses multicall to rebalance cellar out
        // of position, set a new holding position, and distrust it.

        cellar.setHoldingPosition(usdcCLRPosition);

        // Rebalance into USDC. No swap is made because both positions use
        // USDC.
        deal(address(USDC), address(this), 200e6);
        cellar.deposit(100e6, address(this));

        // Make call to adaptor to remove funds from usdcCLR into USDC position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(CellarAdaptor.withdrawFromCellar.selector, usdcCLR, 50e6);
        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // usdcCLR depeggs from USDC
        deal(address(USDC), address(usdcCLR), 45e6);

        assertLt(cellar.totalAssets(), 100e6, "Cellar total assets should have gone down.");
        assertGt(cellar.deposit(100e6, address(this)), 100e6, "Cellar share price should have decreased.");

        // Governance votes to rebalance out of usdcCLR, change the holding
        // position, and distrust usdcCLR. No swap is made because both
        // positions use USDC.
        adaptorCalls[0] = abi.encodeWithSelector(
            CellarAdaptor.withdrawFromCellar.selector,
            usdcCLR,
            usdcCLR.maxWithdraw(address(cellar))
        );
        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        cellar.setHoldingPosition(usdcPosition);
    }

    function testDepeggedCellarAsset() external {
        // Scenario 4: Depegged asset is the cellars asset. Worst case
        // scenario, rebalance out of position into some new stable position,
        // set fees to zero, initiate a shutdown, and have users withdraw funds
        // asap. Want to ensure that attackers can not join using the depegged
        // asset. Emergency governance proposal to move funds into some new
        // safety contract, shutdown old cellar, and allow users to withdraw
        // from the safety contract.

        cellar.addPosition(5, usdtPosition, abi.encode(true), false);

        deal(address(USDC), address(this), 100e6);
        cellar.deposit(100e6, address(this));

        // USDC depeggs to $0.90.
        mockUsdcUsd.setMockAnswer(0.9e8);

        assertEq(cellar.totalAssets(), 100e6 + initialAssets, "Cellar total assets should remain unchanged.");

        // Governance rebalances to USDT, sets performance and platform fees to
        // zero, initiates a shutdown, and has users withdraw their funds.
        // Manually rebalance to USDT.
        deal(address(USDC), address(cellar), 0);
        deal(address(USDT), address(cellar), 90e6);

        cellar.initiateShutdown();

        // Attacker tries to join with depegged asset.
        address attacker = vm.addr(34534);
        deal(address(USDC), attacker, 1);
        vm.startPrank(attacker);
        USDC.approve(address(cellar), 1);
        vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__ContractShutdown.selector)));
        cellar.deposit(1, attacker);
        vm.stopPrank();

        cellar.redeem(50e6, address(this), address(this));

        // USDC depeggs to $0.10.
        mockUsdcUsd.setMockAnswer(0.1e8);

        cellar.redeem(50e6, address(this), address(this));

        // Eventhough USDC depegged further, cellar rebalanced out of USDC
        // removing its exposure to it.  So users can expect to get the
        // remaining value out of the cellar.
        assertEq(
            USDT.balanceOf(address(this)),
            89108910,
            "Withdraws should total the amount of USDT in the cellar after rebalance."
        );

        // Governance can not distrust USDC, because it is the holding position,
        // and changing the holding position is pointless because the asset of
        // the new holding position must be USDC.  Therefore the cellar is lost,
        // and should be exitted completely.
    }

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
    function sendToCosmos(address asset, bytes32, uint256 assets) external {
        ERC20(asset).transferFrom(msg.sender, cosmos, assets);
    }

    // ========================================= MACRO FINDINGS =========================================

    // H-1 done.

    // H-2 NA, cellars will not increase their TVL during rebalance calls.
    // In future versions this will be fixed by having all yield converted into the cellar's accounting asset, then put into a vestedERC20 contract which gradually releases rewards to the cellar.

    // M5
    function testReentrancyAttack() external {
        // True means this cellar tries to re-enter caller on deposit calls.
        ReentrancyERC4626 maliciousCellar = new ReentrancyERC4626(USDC, "Bad Cellar", "BC", true);

        uint32 maliciousPosition = 20;
        registry.trustPosition(maliciousPosition, address(cellarAdaptor), abi.encode(maliciousCellar));
        cellar.addPositionToCatalogue(maliciousPosition);
        cellar.addPosition(5, maliciousPosition, abi.encode(true), false);

        cellar.setHoldingPosition(maliciousPosition);

        uint256 assets = 10000e6;
        deal(address(USDC), address(this), assets);
        USDC.approve(address(maliciousCellar), assets);

        vm.expectRevert(bytes("REENTRANCY"));
        cellar.deposit(assets, address(this));
    }

    // L-4 handle via using a centralized contract storing valid positions(to reduce num of governance props), and rely on voters to see mismatched position and types.
    //  Will not be added to this code.

    //M-6 handled offchain using a subgraph to verify no weird webs are happening
    // difficult bc we can control downstream, but can't control upstream. IE
    // Cellar A wants to add a position in Cellar B, but Cellar B already has a position in Cellar C. Cellar A could see this, but...
    // If Cellar A takes a postion in Cellar B, then Cellar B takes a position in Cellar C, Cellar B would need to look upstream to see the nested postions which is unreasonable,
    // and it means Cellar A can dictate what positions Cellar B takes which is not good.

    // M-2, changes in trustPosition.
    function testTrustPositionForUnsupportedAssetLocksAllFunds() external {
        // FRAX is not a supported PriceRouter asset.

        uint256 assets = 10e18;

        deal(address(USDC), address(this), assets);

        // Deposit USDC
        cellar.previewDeposit(assets);
        cellar.deposit(assets, address(this));
        assertEq(USDC.balanceOf(address(this)), 0, "Should have deposited assets from user.");

        // FRAX is added as a trusted Cellar position,
        // but is not supported by the PriceRouter.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(Registry.Registry__PositionPricingNotSetUp.selector, address(FRAX)))
        );
        registry.trustPosition(101, address(erc20Adaptor), abi.encode(FRAX));
    }

    // Crowd Audit Tests
    //M-1 Accepted
    //M-2
    function testCellarDNOSPerformanceFeesWithZeroShares() external {
        //Attacker deposits 1 USDC into Cellar.
        uint256 assets = 1e6;
        address attacker = vm.addr(101);
        deal(address(USDC), attacker, assets);
        vm.prank(attacker);
        USDC.transfer(address(cellar), assets);

        address user = vm.addr(10101);
        deal(address(USDC), user, assets);

        vm.startPrank(user);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, user);
        vm.stopPrank();

        assertEq(cellar.maxWithdraw(user), assets, "User should be able to withdraw their assets.");
    }

    //============================================ Helper Functions ===========================================

    function _depositToCellar(Cellar targetFrom, Cellar targetTo, uint256 amountIn) internal {
        ERC20 assetIn = targetFrom.asset();
        ERC20 assetOut = targetTo.asset();

        uint256 amountTo = priceRouter.getValue(assetIn, amountIn, assetOut);

        // Update targetFrom ERC20 balances.
        deal(address(assetIn), address(targetFrom), assetIn.balanceOf(address(targetFrom)) - amountIn);
        deal(address(assetOut), address(targetFrom), assetOut.balanceOf(address(targetFrom)) + amountTo);

        // Rebalance into targetTo.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToCellar(address(targetTo), amountTo);
            data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        targetFrom.callOnAdaptor(data);
    }

    // Used to act like malicious price router under reporting assets.
    function getValuesDelta(
        ERC20[] calldata,
        uint256[] calldata,
        ERC20[] calldata,
        uint256[] calldata,
        ERC20
    ) external pure returns (uint256) {
        return 50e6;
    }
}
