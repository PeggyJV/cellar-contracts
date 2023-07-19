// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { LockedERC4626 } from "src/mocks/LockedERC4626.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { ERC20DebtAdaptor } from "src/mocks/ERC20DebtAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarWithShareLockPeriodTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    Cellar private cellar;
    Cellar private usdcCLR;
    Cellar private wethCLR;
    Cellar private wbtcCLR;

    CellarAdaptor private cellarAdaptor;

    MockDataFeed private mockUsdcUsd;
    MockDataFeed private mockWethUsd;
    MockDataFeed private mockWbtcUsd;

    uint32 private usdcPosition = 1;
    uint32 private wethPosition = 2;
    uint32 private wbtcPosition = 3;
    uint32 private usdcCLRPosition = 4;
    uint32 private wethCLRPosition = 5;
    uint32 private wbtcCLRPosition = 6;

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

        // Setup exchange rates:
        // USDC Simulated Price: $1
        // WETH Simulated Price: $2000
        // WBTC Simulated Price: $30,000
        mockUsdcUsd.setMockAnswer(1e8);
        mockWethUsd.setMockAnswer(2_000e8);
        mockWbtcUsd.setMockAnswer(30_000e8);

        // Add adaptors and ERC20 positions to the registry.
        registry.trustAdaptor(address(cellarAdaptor));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(wbtcPosition, address(erc20Adaptor), abi.encode(WBTC));

        // Create Dummy Cellars.
        string memory cellarName = "Dummy Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        usdcCLR = _createCellar(cellarName, USDC, usdcPosition, abi.encode(0), initialDeposit, platformCut);
        vm.label(address(usdcCLR), "usdcCLR");

        cellarName = "Dummy Cellar V0.1";
        initialDeposit = 1e12;
        platformCut = 0.75e18;
        wethCLR = _createCellar(cellarName, WETH, wethPosition, abi.encode(0), initialDeposit, platformCut);
        vm.label(address(wethCLR), "wethCLR");

        cellarName = "Dummy Cellar V0.2";
        initialDeposit = 1e4;
        platformCut = 0.75e18;
        wbtcCLR = _createCellar(cellarName, WBTC, wbtcPosition, abi.encode(0), initialDeposit, platformCut);
        vm.label(address(wbtcCLR), "wbtcCLR");

        // Add Cellar Positions to the registry.
        registry.trustPosition(usdcCLRPosition, address(cellarAdaptor), abi.encode(usdcCLR));
        registry.trustPosition(wethCLRPosition, address(cellarAdaptor), abi.encode(wethCLR));
        registry.trustPosition(wbtcCLRPosition, address(cellarAdaptor), abi.encode(wbtcCLR));

        cellarName = "Cellar V0.0";
        initialDeposit = 1e6;
        platformCut = 0.75e18;
        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(0), initialDeposit, platformCut);

        // Set up remaining cellar positions.
        cellar.addPositionToCatalogue(usdcCLRPosition);
        cellar.addPosition(1, usdcCLRPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wethCLRPosition);
        cellar.addPosition(2, wethCLRPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wbtcCLRPosition);
        cellar.addPosition(3, wbtcCLRPosition, abi.encode(true), false);
        cellar.addPositionToCatalogue(wethPosition);
        cellar.addPosition(4, wethPosition, abi.encode(0), false);
        cellar.addPositionToCatalogue(wbtcPosition);
        cellar.addPosition(5, wbtcPosition, abi.encode(0), false);
        cellar.addAdaptorToCatalogue(address(cellarAdaptor));

        cellar.setStrategistPayoutAddress(strategist);

        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);

        initialAssets = cellar.totalAssets();
        initialShares = cellar.totalSupply();
    }

    // function testTransfer() external {
    //     // Change cellar share lock period.
    //     cellar.setShareLockPeriod(300);

    //     // Deposit into cellar.
    //     uint256 assets = 100e6;
    //     deal(address(USDC), address(this), assets);
    //     uint256 shares = cellar.deposit(assets, address(this));

    //     // Check that withdraw/redeem fails.
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellar.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellar.withdraw(assets, address(this), address(this));

    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellar.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellar.redeem(shares, address(this), address(this));

    //     // Check that transfer and transferFrom fails.
    //     address me = address(this);
    //     address friend = vm.addr(55555);
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellar.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellar.transfer(friend, shares);

    //     cellar.approve(friend, shares / 2);
    //     vm.startPrank(friend);
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellar.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellar.transferFrom(me, friend, shares);
    //     vm.stopPrank();

    //     // Advance time so shares are unlocked.
    //     vm.warp(block.timestamp + cellar.shareLockPeriod());

    //     // Check that transfer complies with ERC20 standards.
    //     assertTrue(cellar.transfer(friend, shares / 2), "transfer should return true.");
    //     assertEq(cellar.balanceOf(friend), shares / 2, "Friend should have received shares.");
    //     assertEq(cellar.balanceOf(me), shares / 2, "I should have sent shares.");

    //     // Check that transferFrom complies with ERC20 standards.
    //     vm.prank(friend);
    //     assertTrue(cellar.transferFrom(me, friend, shares / 2), "transferFrom should return true.");
    //     assertEq(cellar.balanceOf(friend), shares, "Friend should have received shares.");
    //     assertEq(cellar.balanceOf(me), 0, "I should have sent shares.");
    //     assertEq(cellar.allowance(me, friend), 0, "Friend should have used all their allowance.");
    // }

    // //H-1
    // function testChainlinkPriceFeedUpdateSandwichAttack() external {
    //     // Initialize test Cellar.

    //     // Create new cellar with WETH, and USDC positions.
    //     uint32[] memory positions = new uint32[](2);
    //     positions[0] = usdcPosition;
    //     positions[1] = wethPosition;

    //     uint32[] memory debtPositions;
    //     bytes[] memory debtConfigs;

    //     bytes[] memory positionConfigs = new bytes[](2);

    //     MockCellar cellarA = new MockCellar(
    //         registry,
    //         USDC,
    //         "Asset Management Cellar LP Token",
    //         "assetmanagement-CLR",
    //         abi.encode(positions, debtPositions, positionConfigs, debtConfigs, usdcPosition, strategist)
    //     );

    //     // Set up worst case scenario where
    //     // Cellar has all of its funds in mispriced asset(WETH)
    //     // Chainlink updates price because of max price deviation(1%)

    //     uint256 assets = 10_000e6;
    //     deal(address(USDC), address(this), assets);
    //     USDC.approve(address(cellarA), assets);
    //     cellarA.deposit(assets, address(this));
    //     // Manually rebalance funds from USDC to WETH.
    //     deal(address(USDC), address(cellarA), 0);
    //     deal(address(WETH), address(cellarA), 5e18);

    //     // Attacker joins cellar right before price update.
    //     address attacker = vm.addr(8349058);
    //     deal(address(USDC), attacker, assets);
    //     vm.startPrank(attacker);
    //     USDC.approve(address(cellarA), assets);
    //     cellarA.deposit(assets, attacker);
    //     vm.stopPrank();

    //     // Price updates
    //     priceRouter.setExchangeRate(USDC, WETH, 0.000495e18);
    //     priceRouter.setExchangeRate(WETH, USDC, 2020e6);

    //     // Confirm attackers maxWithdraw is zero while shares are locked.
    //     assertEq(cellarA.maxWithdraw(attacker), 0, "Attackers maxWithdraw should be zero while shares are locked.");

    //     // Confirm attackers maxRedeem is zero while shares are locked.
    //     assertEq(cellarA.maxRedeem(attacker), 0, "Attackers maxRedeem should be zero while shares are locked.");

    //     vm.startPrank(attacker);
    //     uint256 shares = cellarA.balanceOf(attacker);
    //     // Attacker tries to redeem their shares.
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellarA.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellarA.redeem(shares, attacker, attacker);

    //     // Attacker tries to transfer shares to another address.
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellarA.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellarA.transfer(address(this), shares);
    //     vm.stopPrank();

    //     vm.warp(block.timestamp + cellarA.shareLockPeriod());

    //     // Confirm attackers shares are worth more once shares are unlocked.
    //     assertGt(cellarA.maxWithdraw(attacker), assets, "Attackers shares should be worth more than deposit.");

    //     // Note the attacker was able to arbitrage the price feed update, but must wait the share lock period in order to capture profit.
    // }

    // function testShareLockUpPeriod() external {
    //     // Try to set lock period to illogical value.
    //     vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidShareLockPeriod.selector)));
    //     cellar.setShareLockPeriod(type(uint32).max);

    //     vm.expectRevert(bytes(abi.encodeWithSelector(Cellar.Cellar__InvalidShareLockPeriod.selector)));
    //     cellar.setShareLockPeriod(0);

    //     // Set lock period to reasonable value.
    //     uint256 newLock = 300;
    //     cellar.setShareLockPeriod(newLock);
    //     assertEq(cellar.shareLockPeriod(), newLock, "Cellar share lock should equal newLock.");

    //     // Make sure user's who join with mint or deposit can not transfer, withdraw, or redeem for the shareLockPeriod.
    //     uint256 assets = 100e6;
    //     uint256 shares = 100e18;
    //     address depositUser = vm.addr(7777);
    //     address mintUser = vm.addr(77777);
    //     vm.startPrank(depositUser);
    //     deal(address(USDC), depositUser, assets);
    //     USDC.approve(address(cellar), assets);
    //     cellar.deposit(assets, depositUser);
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellar.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellar.withdraw(assets, depositUser, depositUser);
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellar.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellar.redeem(shares, depositUser, depositUser);
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellar.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellar.transfer(address(this), shares);
    //     vm.stopPrank();

    //     vm.startPrank(mintUser);
    //     deal(address(USDC), mintUser, assets);
    //     USDC.approve(address(cellar), assets);
    //     cellar.mint(shares, mintUser);
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellar.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellar.withdraw(assets, mintUser, mintUser);
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellar.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellar.redeem(shares, mintUser, mintUser);
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 Cellar.Cellar__SharesAreLocked.selector,
    //                 block.timestamp + cellar.shareLockPeriod(),
    //                 block.timestamp
    //             )
    //         )
    //     );
    //     cellar.transfer(address(this), shares);
    //     vm.stopPrank();

    //     // Advance block timestamp to end of share lock period.
    //     vm.warp(block.timestamp + cellar.shareLockPeriod());

    //     // Users can withdraw.
    //     vm.prank(depositUser);
    //     cellar.withdraw(assets, depositUser, depositUser);

    //     // // Users can transfer.
    //     // vm.prank(mintUser);
    //     // cellar.transfer(depositUser, shares);

    //     // // Users can redeem.
    //     // vm.prank(depositUser);
    //     // cellar.redeem(shares, depositUser, depositUser);

    //     // // Check that if a user has waited the lock period but then decides to deposit again, they must wait for the new lock period to end.
    //     // vm.startPrank(depositUser);
    //     // deal(address(USDC), depositUser, assets);
    //     // USDC.approve(address(cellar), 2 * assets);
    //     // cellar.deposit(assets, depositUser);
    //     // // Advance block timestamp to end of share lock period.
    //     // vm.warp(block.timestamp + cellar.shareLockPeriod());

    //     // // If user joins again, they must wait the lock period again, even if withdrawing previous amount.
    //     // deal(address(USDC), depositUser, assets);
    //     // cellar.deposit(assets, depositUser);
    //     // vm.expectRevert(
    //     //     bytes(
    //     //         abi.encodeWithSelector(
    //     //             Cellar.Cellar__SharesAreLocked.selector,
    //     //             block.timestamp + cellar.shareLockPeriod(),
    //     //             block.timestamp
    //     //         )
    //     //     )
    //     // );
    //     // cellar.withdraw(assets, depositUser, depositUser);
    //     // vm.stopPrank();
    // }

    // function testDepositOnBehalf() external {
    //     address user = vm.addr(1111);
    //     uint256 assets = 100e6;
    //     deal(address(USDC), address(this), assets);
    //     vm.expectRevert(
    //         bytes(abi.encodeWithSelector(Cellar.Cellar__NotApprovedToDepositOnBehalf.selector, address(this)))
    //     );
    //     cellar.deposit(assets, user);

    //     // Add this address as an approved depositor.
    //     registry.setApprovedForDepositOnBehalf(address(this), true);
    //     // Deposits are now allowed.
    //     cellar.deposit(assets, user);
    // }

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
}
