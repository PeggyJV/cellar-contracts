// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "../base/ERC4626.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockSwapRouter } from "./mocks/MockSwapRouter.sol";

import { CellarRouter } from "../CellarRouter.sol";
import { MockERC4626 } from "./mocks/MockERC4626.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";
import { Math } from "../utils/Math.sol";

contract CellarRouterTest is DSTestPlus {
    using Math for uint256;

    MockERC20 private ABC;
    MockERC20 private XYZ;
    MockSwapRouter private swapRouter;

    MockERC4626 private cellar;
    CellarRouter private router;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    uint256 private privateKey = 0xBEEF;
    address private owner = hevm.addr(privateKey);

    function setUp() public {
        // Set up cellar router:
        swapRouter = new MockSwapRouter();

        router = new CellarRouter(ISwapRouter(address(swapRouter)));

        // Set up a cellar:
        ABC = new MockERC20("ABC", 18);
        XYZ = new MockERC20("XYZ", 18);

        cellar = new MockERC4626(ERC20(address(ABC)), "ABC Cellar", "abcCLR", 18);
    }

    function testDepositWithPermit(uint256 assets) external {
        assets = bound(assets, 1e18, type(uint72).max);

        // Retrieve signature for permit.
        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ABC.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(router), assets, 0, block.timestamp))
                )
            )
        );

        // Test deposit with permit.
        ABC.mint(owner, assets);
        uint256 shares = router.depositIntoCellarWithPermit(
            ERC4626(address(cellar)),
            assets,
            owner,
            owner,
            block.timestamp,
            v,
            r,
            s
        );

        // Run test.
        assertEq(shares, assets, "Should have 1:1 exchange rate for initial deposit.");
        assertEq(cellar.previewWithdraw(assets), shares, "Withdrawing assets should burn shares given.");
        assertEq(cellar.previewDeposit(assets), shares, "Depositing assets should mint shares given.");
        assertEq(cellar.totalSupply(), shares, "Should have updated total supply with shares minted.");
        assertEq(cellar.totalAssets(), assets, "Should have updated total assets with assets deposited.");
        assertEq(cellar.balanceOf(owner), shares, "Should have updated user's share balance.");
        assertEq(cellar.convertToAssets(cellar.balanceOf(owner)), assets, "Should return all user's assets.");
        assertEq(ABC.balanceOf(owner), 0, "Should have deposited assets from user.");
    }

    function testDepositAndSwapIntoCellar(uint256 assets) external {
        // Attempting to swap 1 will round down to 0 when due to simulating a 95% exchange rate on swaps.
        assets = bound(assets, 1e18, type(uint72).max);

        // Mint liquidity for swap.
        ABC.mint(address(swapRouter), assets.changeDecimals(XYZ.decimals(), ABC.decimals()));

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(XYZ);
        path[1] = address(ABC);

        // Test deposit and swap.
        hevm.prank(owner);
        XYZ.approve(address(router), assets);
        XYZ.mint(owner, assets);
        uint256 shares = router.depositAndSwapIntoCellar(ERC4626(address(cellar)), path, assets, 0, owner, owner);

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
        assertEq(ABC.balanceOf(owner), 0, "Should have deposited assets from user.");
    }

    function testDepositAndSwapIntoCellarWithPermit(uint256 assets) external {
        // Attempting to swap 1 will round down to 0 when due to simulating a 95% exchange rate on swaps.
        assets = bound(assets, 2, type(uint72).max);

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    XYZ.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(router), assets, 0, block.timestamp))
                )
            )
        );

        // Mint liquidity for swap.
        ABC.mint(address(swapRouter), assets.changeDecimals(XYZ.decimals(), ABC.decimals()));

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(XYZ);
        path[1] = address(ABC);

        // Test deposit and swap with permit.
        XYZ.mint(owner, assets);
        uint256 shares = router.depositAndSwapIntoCellarWithPermit(
            ERC4626(address(cellar)),
            path,
            assets,
            0,
            owner,
            owner,
            block.timestamp,
            v,
            r,
            s
        );

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
        assertEq(ABC.balanceOf(owner), 0, "Should have deposited assets from user.");
    }
}
