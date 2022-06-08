// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "../interfaces/ERC4626.sol";
import { IAaveIncentivesController } from "../interfaces/IAaveIncentivesController.sol";
import { IStakedTokenV2 } from "../interfaces/IStakedTokenV2.sol";
import { ICurveSwaps } from "../interfaces/ICurveSwaps.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { ISushiSwapRouter } from "../interfaces/ISushiSwapRouter.sol";
import { IGravity } from "../interfaces/IGravity.sol";
import { ILendingPool } from "../interfaces/ILendingPool.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockAToken } from "./mocks/MockAToken.sol";
import { MockCurveSwaps } from "./mocks/MockCurveSwaps.sol";
import { MockSwapRouter } from "./mocks/MockSwapRouter.sol";
import { MockPriceOracle } from "./mocks/MockPriceOracle.sol";
import { MockLendingPool } from "./mocks/MockLendingPool.sol";
import { MockIncentivesController } from "./mocks/MockIncentivesController.sol";
import { MockGravity } from "./mocks/MockGravity.sol";
import { MockStkAAVE } from "./mocks/MockStkAAVE.sol";

import { CellarRouter } from "../CellarRouter.sol";
import { MockAaveCellar } from "./mocks/MockAaveCellar.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";
import { MathUtils } from "../utils/MathUtils.sol";

contract CellarRouterTest is DSTestPlus {
    using MathUtils for uint256;

    MockERC20 private USDC;
    MockERC20 private DAI;
    MockAToken private aUSDC;
    MockAToken private aDAI;
    MockLendingPool private lendingPool;
    MockPriceOracle private priceOracle;
    MockSwapRouter private swapRouter;

    MockAaveCellar private cellar;
    CellarRouter private router;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    uint256 private privateKey = 0xBEEF;
    address private owner = hevm.addr(privateKey);

    function setUp() public {
        swapRouter = new MockSwapRouter();

        router = new CellarRouter(ISwapRouter(address(swapRouter)));

        USDC = new MockERC20("USDC", 6);
        DAI = new MockERC20("DAI", 18);
        lendingPool = new MockLendingPool();
        aUSDC = new MockAToken(address(lendingPool), address(USDC), "aUSDC");
        aDAI = new MockAToken(address(lendingPool), address(DAI), "aDAI");
        lendingPool.initReserve(address(USDC), address(aUSDC));
        lendingPool.initReserve(address(DAI), address(aDAI));

        // Setup exchange rates:
        swapRouter.setExchangeRate(address(USDC), address(USDC), 1e6);
        swapRouter.setExchangeRate(address(DAI), address(DAI), 1e18);
        swapRouter.setExchangeRate(address(USDC), address(DAI), 1e18);
        swapRouter.setExchangeRate(address(DAI), address(USDC), 1e6);

        // Set up a cellar:
        address[] memory approvedPositions = new address[](1);
        approvedPositions[0] = address(DAI);

        cellar = new MockAaveCellar(
            ERC20(address(USDC)),
            approvedPositions,
            // Declare unnecessary variables with address 0.
            ICurveSwaps(address(0)),
            ISushiSwapRouter(address(0)),
            ILendingPool(address(lendingPool)),
            IAaveIncentivesController(address(0)),
            IGravity(address(this)), // Set to this address to give contract admin privileges.
            IStakedTokenV2(address(0)),
            ERC20(address(0)),
            ERC20(address(0))
        );

        // Ensure restrictions aren't a factor.
        cellar.setLiquidityLimit(type(uint256).max);
        cellar.setDepositLimit(type(uint256).max);
    }

    function testDepositWithPermit(uint256 assets) external {
        assets = bound(assets, 1e6, cellar.maxDeposit(address(this)));

        // Retrieve signature for permit.
        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    USDC.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(router), assets, 0, block.timestamp))
                )
            )
        );

        // Test deposit with permit.
        USDC.mint(owner, assets);
        uint256 shares = router.depositIntoCellarWithPermit(
            ERC4626(payable(address(cellar))),
            assets,
            owner,
            owner,
            block.timestamp,
            v,
            r,
            s
        );

        // Run test.
        assertEq(shares, assets.changeDecimals(6, 18)); // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(cellar.previewWithdraw(assets), shares);
        assertEq(cellar.previewDeposit(assets), shares);
        assertEq(cellar.totalSupply(), shares);
        assertEq(cellar.totalAssets(), assets);
        assertEq(cellar.balanceOf(owner), shares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(owner)), assets);
        assertEq(USDC.balanceOf(owner), 0);
    }

    function testDepositAndSwapIntoCellar(uint256 assets) external {
        assets = bound(assets, 1e18, cellar.maxDeposit(owner));

        // Mint liquidity for swap.
        USDC.mint(address(swapRouter), assets.changeDecimals(DAI.decimals(), USDC.decimals()));

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);

        // Test deposit and swap.
        hevm.prank(owner);
        DAI.approve(address(router), assets);
        DAI.mint(owner, assets);
        uint256 shares = router.depositAndSwapIntoCellar(ERC4626(payable(address(cellar))), path, assets, 0, owner, owner);

        // Assets received by the cellar will be different from the amount of assets a user attempted
        // to deposit due to slippage swaps.
        uint256 assetsReceived = swapRouter.quote(assets, path);

        // Run test.
        assertEq(shares, assetsReceived.changeDecimals(6, 18)); // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(cellar.previewWithdraw(assetsReceived), shares);
        assertEq(cellar.previewDeposit(assetsReceived), shares);
        assertEq(cellar.totalSupply(), shares);
        assertEq(cellar.totalAssets(), assetsReceived);
        assertEq(cellar.balanceOf(owner), shares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(owner)), assetsReceived);
        assertEq(DAI.balanceOf(owner), 0);
    }

    function testDepositAndSwapIntoCellarWhenSwapUnnecessary(uint256 assets) external {
        assets = bound(assets, 1e6, cellar.maxDeposit(owner));

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(USDC);

        // Test deposit without needing to swap.
        hevm.prank(owner);
        USDC.approve(address(router), assets);
        USDC.mint(owner, assets);
        uint256 shares = router.depositAndSwapIntoCellar(ERC4626(payable(address(cellar))), path, assets, assets, owner, owner);

        // Run test.
        assertEq(shares, assets.changeDecimals(6, 18)); // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(cellar.previewWithdraw(assets), shares);
        assertEq(cellar.previewDeposit(assets), shares);
        assertEq(cellar.totalSupply(), shares);
        assertEq(cellar.totalAssets(), assets);
        assertEq(cellar.balanceOf(owner), shares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(owner)), assets);
        assertEq(USDC.balanceOf(owner), 0);
    }

    function testFailDepositAndSwapIntoCellarWithInvalidPath() external {
        // Specify the swap path to an invalid asset.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(DAI);

        // Test deposit without needing to swap.
        hevm.prank(owner);
        DAI.approve(address(router), 1e18);
        DAI.mint(owner, 1e18);
        router.depositAndSwapIntoCellar(ERC4626(payable(address(cellar))), path, 1e18, 0, owner, owner);
    }

    // Test using asset with 18 decimals instead of 6.
    function testDepositAndSwapIntoCellarWithDifferentDecimals(uint256 assets) external {
        assets = bound(assets, 1e6, cellar.maxDeposit(owner));

        // Change cellar current asset to DAI.
        cellar.updatePosition(address(DAI));

        // Mint liquidity for swap.
        DAI.mint(address(swapRouter), assets.changeDecimals(USDC.decimals(), DAI.decimals()));

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(DAI);

        // Test deposit and swap.
        hevm.prank(owner);
        USDC.approve(address(router), assets);
        USDC.mint(owner, assets);
        uint256 shares = router.depositAndSwapIntoCellar(ERC4626(payable(address(cellar))), path, assets, 0, owner, owner);

        // Assets received by the cellar will be different from the amount of assets a user attempted
        // to deposit due to slippage swaps.
        uint256 assetsReceived = swapRouter.quote(assets, path);

        // Run test.
        assertEq(shares, assetsReceived); // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(cellar.previewWithdraw(assetsReceived), shares);
        assertEq(cellar.previewDeposit(assetsReceived), shares);
        assertEq(cellar.totalSupply(), shares);
        assertEq(cellar.totalAssets(), assetsReceived);
        assertEq(cellar.balanceOf(owner), shares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(owner)), assetsReceived);
        assertEq(USDC.balanceOf(owner), 0);
    }

    function testDepositAndSwapIntoCellarWithPermit(uint256 assets) external {
        assets = bound(assets, 1e18, cellar.maxDeposit(owner));

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DAI.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(router), assets, 0, block.timestamp))
                )
            )
        );

        // Mint liquidity for swap.
        USDC.mint(address(swapRouter), assets.changeDecimals(DAI.decimals(), USDC.decimals()));

        // Specify the swap path.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);

        // Test deposit and swap with permit.
        DAI.mint(owner, assets);
        uint256 shares = router.depositAndSwapIntoCellarWithPermit(
            ERC4626(payable(address(cellar))),
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
        assertEq(shares, assetsReceived.changeDecimals(6, 18)); // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(cellar.previewWithdraw(assetsReceived), shares);
        assertEq(cellar.previewDeposit(assetsReceived), shares);
        assertEq(cellar.totalSupply(), shares);
        assertEq(cellar.totalAssets(), assetsReceived);
        assertEq(cellar.balanceOf(owner), shares);
        assertEq(cellar.convertToAssets(cellar.balanceOf(owner)), assetsReceived);
        assertEq(DAI.balanceOf(owner), 0);
    }
}
