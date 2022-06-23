// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ERC4626 } from "src/base/ERC4626.sol";
import { CellarRouter } from "src/CellarRouter.sol";
import { ISwapRouter as UniswapV3Router } from "src/interfaces/ISwapRouter.sol";
import { IUniswapV2Router02 as UniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockSwapRouter } from "src/mocks/MockSwapRouter.sol";
import { MockWETH } from "src/mocks/MockWETH.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarRouterTest is Test {
    using Math for uint256;

    MockERC20 private ABC;
    MockERC20 private XYZ;
    MockWETH private weth;
    MockSwapRouter private swapRouter;

    MockERC4626 private cellar;
    MockERC4626 private wethCellar;
    CellarRouter private router;

    MockERC4626 private forkedCellar;
    CellarRouter private forkedRouter;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    uint256 private constant privateKey = 0xBEEF;
    address private owner = vm.addr(privateKey);

    // Mainnet contracts:
    address private constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    function setUp() public {
        swapRouter = new MockSwapRouter();

        weth = new MockWETH();

        router = new CellarRouter(
            UniswapV3Router(address(swapRouter)),
            UniswapV2Router(address(swapRouter)),
            address(weth)
        );
        
        forkedRouter = new CellarRouter(
            UniswapV3Router(uniV3Router),
            UniswapV2Router(uniV2Router),
            address(weth)
        );

        ABC = new MockERC20("ABC", 18);
        XYZ = new MockERC20("XYZ", 18);

        // Set up cellars:
        cellar = new MockERC4626(ERC20(address(ABC)), "ABC Cellar", "abcCLR", 18);

        // Set up wethCellar:
        wethCellar = new MockERC4626(ERC20(address(weth)), "WETH Cellar", "wethCLR", 18);

        // Set up forkedCellar for mainnet fork test:
        forkedCellar = new MockERC4626(ERC20(address(WETH)), "WETH Cellar", "WETHCLR", 18);
    }

    // ======================================= DEPOSIT TESTS =======================================

    function testDepositAndSwapIntoCellar(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Mint liquidity for swap.
        ABC.mint(address(swapRouter), 2 * assets);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(XYZ);
        path[1] = address(ABC);

        // Specify the pool fee tiers to use for each swap (none).
        uint24[] memory poolFees;

        // Test deposit and swap.
        vm.startPrank(owner);
        XYZ.approve(address(router), assets);
        XYZ.mint(owner, assets);
        uint256 shares = router.depositAndSwapIntoCellar(ERC4626(address(cellar)), path, poolFees, assets, 0, owner);
        vm.stopPrank();

        // Assets received by the cellar will be different from the amount of assets a user attempted
        // to deposit due to slippage swaps.
        uint256 assetsReceived = swapRouter.quote(assets, path);

        // Run test.
        assertEq(shares, assetsReceived, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assetsReceived), shares, "Withdrawing assets should burn shares given.");
        assertEq(cellar.previewDeposit(assetsReceived), shares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assetsReceived, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(owner), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(owner)), assetsReceived, "Should return all user's assets.");
        assertEq(XYZ.balanceOf(owner), 0, "Should have deposited assets from user.");
    }

    function testDepositAndSwapIntoCellarUsingUniswapV2OnMainnet(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);

        // Specify the pool fee tiers to use for each swap (none).
        uint24[] memory poolFees;

        // Test deposit and swap.
        vm.startPrank(owner);
        deal(address(DAI), owner, assets, true);
        DAI.approve(address(forkedRouter), assets);
        uint256 shares = forkedRouter.depositAndSwapIntoCellar(
            ERC4626(address(forkedCellar)),
            path,
            poolFees,
            assets,
            0,
            owner
        );
        vm.stopPrank();

        // Assets received by the cellar will be equal to WETH currently in forked cellar because no
        // other deposits have been made.
        uint256 assetsReceived = WETH.balanceOf(address(forkedCellar));

        // Run test.
        assertEq(shares, assetsReceived, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(forkedCellar.previewWithdraw(assetsReceived), shares, "Withdrawing assets should burn shares given.");
        assertEq(forkedCellar.previewDeposit(assetsReceived), shares, "Depositing assets should mint shares given.");
        assertEq(forkedCellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(forkedCellar.totalAssets(), assetsReceived, "Should have updated total assets with assets deposited.");
        assertEq(forkedCellar.balanceOf(owner), shares, "Should have updated user's share balance.");
        assertEq(
            forkedCellar.convertToAssets(forkedCellar.balanceOf(owner)),
            assetsReceived,
            "Should return all user's assets."
        );
        assertEq(DAI.balanceOf(owner), 0, "Should have deposited assets from user.");
    }

    function testDepositETHIntoWethCellar(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        uint256 balanceBefore = address(this).balance;

        // Test ETH deposit.
        uint256 shares = router.depositETHIntoCellar{value: assets}(ERC4626(address(wethCellar)), owner);

        // Run test.
        assertEq(shares, assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(wethCellar.previewWithdraw(assets), shares, "Withdrawing assets should burn shares given.");
        assertEq(wethCellar.previewDeposit(assets), shares, "Depositing assets should mint shares given.");
        assertEq(wethCellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(wethCellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(wethCellar.balanceOf(owner), shares, "Should have updated user's share balance.");
        assertEq(wethCellar.convertToAssets(wethCellar.balanceOf(owner)), assets, "Should return all user's assets.");
        assertEq(address(this).balance + assets, balanceBefore, "Should have deposited assets from sender.");
    }
    
    function testFailDepositETHIntoNoWethCellar(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Test ETH deposit.
        router.depositETHIntoCellar{value: assets}(ERC4626(address(cellar)), owner);
    }

    function testDepositAndSwapIntoCellarUsingUniswapV3OnMainnet(uint256 assets) external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        assets = bound(assets, 1e18, type(uint112).max);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(WETH);

        // Specify the pool fee tiers to use for each swap, 0.3% for DAI <-> WETH.
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 3000;

        // Test deposit and swap.
        vm.startPrank(owner);
        deal(address(DAI), owner, assets, true);
        DAI.approve(address(forkedRouter), assets);
        uint256 shares = forkedRouter.depositAndSwapIntoCellar(
            ERC4626(address(forkedCellar)),
            path,
            poolFees,
            assets,
            0,
            owner
        );
        vm.stopPrank();

        // Assets received by the cellar will be equal to WETH currently in forked cellar because no
        // other deposits have been made.
        uint256 assetsReceived = WETH.balanceOf(address(forkedCellar));

        // Run test.
        assertEq(shares, assetsReceived, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(forkedCellar.previewWithdraw(assetsReceived), shares, "Withdrawing assets should burn shares given.");
        assertEq(forkedCellar.previewDeposit(assetsReceived), shares, "Depositing assets should mint shares given.");
        assertEq(forkedCellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(forkedCellar.totalAssets(), assetsReceived, "Should have updated total assets with assets deposited.");
        assertEq(forkedCellar.balanceOf(owner), shares, "Should have updated user's share balance.");
        assertEq(
            forkedCellar.convertToAssets(forkedCellar.balanceOf(owner)),
            assetsReceived,
            "Should return all user's assets."
        );
        assertEq(DAI.balanceOf(owner), 0, "Should have deposited assets from user.");
    }

    // ======================================= WITHDRAW TESTS =======================================

    function testWithdrawAndSwapFromCellar(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Mint liquidity for swap.
        ABC.mint(address(swapRouter), 2 * assets);

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(XYZ);
        path[1] = address(ABC);

        // Specify the pool fee tiers to use for each swap (none).
        uint24[] memory poolFees;

        // Deposit and swap
        vm.startPrank(owner);
        XYZ.approve(address(router), assets);
        XYZ.mint(owner, assets);
        router.depositAndSwapIntoCellar(ERC4626(address(cellar)), path, poolFees, assets, 0, owner);

        // Assets received by the cellar will be different from the amount of assets a user attempted
        // to deposit due to slippage swaps.
        uint256 assetsReceivedAfterDeposit = swapRouter.quote(assets, path);

        // Reverse the swap path.
        (path[0], path[1]) = (path[1], path[0]);

        // Test withdraw and swap.
        cellar.approve(address(router), assetsReceivedAfterDeposit);
        uint256 sharesRedeemed = router.withdrawAndSwapFromCellar(
            ERC4626(address(cellar)),
            path,
            poolFees,
            assetsReceivedAfterDeposit,
            0,
            owner
        );
        vm.stopPrank();

        uint256 assetsReceivedAfterWithdraw = swapRouter.quote(assetsReceivedAfterDeposit, path);

        // Run test.
        assertEq(sharesRedeemed, assetsReceivedAfterDeposit, "Should have 1:1 exchange rate.");
        assertEq(cellar.totalSupply(), 0, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), 0, "Should have updated total assets into account the withdrawn assets.");
        assertEq(cellar.balanceOf(owner), 0, "Should have updated user's share balance.");
        assertEq(XYZ.balanceOf(owner), assetsReceivedAfterWithdraw, "Should have withdrawn assets to the user.");
    }

    function testWithdrawETHFromWethCellar(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Deposit
        router.depositETHIntoCellar{value: assets}(ERC4626(address(wethCellar)), owner);

        uint256 shareBalanceBefore = wethCellar.balanceOf(owner);
        uint256 balanceBefore = owner.balance;

        // Test withdraw.
        vm.startPrank(owner);
        wethCellar.approve(address(router), assets);
        uint256 sharesRedeemed = router.withdrawETHFromCellar(
            ERC4626(address(wethCellar)),
            assets,
            owner
        );

        // Run test.
        assertEq(sharesRedeemed, assets, "Should have 1:1 exchange rate.");
        assertEq(wethCellar.totalSupply(), 0, "Should have updated total supply.");
        assertEq(wethCellar.totalAssets(), 0, "Should have updated total assets into account the withdrawn assets.");
        assertEq(shareBalanceBefore - wethCellar.balanceOf(owner), assets, "Should have updated user's share balance after withdraw.");
        assertEq(owner.balance - balanceBefore, assets, "Should have withdrawn assets to the user.");
    }

    function testWithdrawETHFromWethCellarWithPermit(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Deposit
        router.depositETHIntoCellar{value: assets}(ERC4626(address(wethCellar)), owner);

        uint256 shareBalanceBefore = wethCellar.balanceOf(owner);
        uint256 balanceBefore = owner.balance;

        // Sign permit to allow router to transfer shares.
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    wethCellar.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(router),
                            assets,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        // Test withdraw.
        vm.startPrank(owner);
        uint256 sharesRedeemed = router.withdrawETHFromCellarWithPermit(
            ERC4626(address(wethCellar)),
            assets,
            owner,
            block.timestamp,
            v,
            r,
            s
        );

        // Run test.
        assertEq(sharesRedeemed, assets, "Should have 1:1 exchange rate.");
        assertEq(wethCellar.totalSupply(), 0, "Should have updated total supply.");
        assertEq(wethCellar.totalAssets(), 0, "Should have updated total assets into account the withdrawn assets.");
        assertEq(shareBalanceBefore - wethCellar.balanceOf(owner), assets, "Should have updated user's share balance after withdraw.");
        assertEq(owner.balance - balanceBefore, assets, "Should have withdrawn assets to the user.");
    }
}
