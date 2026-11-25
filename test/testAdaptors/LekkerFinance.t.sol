// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, Cellar, ERC4626, ERC20 } from "src/mocks/MockCellar.sol";
import { Registry, PriceRouter, IGravity } from "src/base/Cellar.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { MockERC4626 } from "src/mocks/MockERC4626.sol";
import { MockGravity } from "src/mocks/MockGravity.sol";
import { MockERC20 } from "src/mocks/MockERC20.sol";
import { LekkerFinanceAdaptor } from "src/modules/adaptors/Lekker-Finance/LekkerFinanceAdaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/UniSwap/UniswapV3Adaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { LockedERC4626 } from "src/mocks/LockedERC4626.sol";
import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

// Will test the swapping and cellar position management using adaptors
contract LekkerFinanceAdaptorTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    MockCellar private cellar;
    MockGravity private gravity;

    PriceRouter private priceRouter;
    SwapRouter private swapRouter;

    Registry private registry;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    ERC20 private LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    //our leverage token
    ERC20 private leverageToken = ERC20(address(0));

    address private immutable strategist = vm.addr(0xBEEF);

    address private immutable cosmos = vm.addr(0xCAAA);

    LekkerFinanceAdaptor private lekkerFinanceAdaptor;
    ERC20Adaptor private erc20Adaptor;

    uint32 private usdcPosition;
    uint32 private wethPosition;
    uint32 private daiPosition;
    uint32 private usdcDaiPosition;
    uint32 private usdcWethPosition;

    function setUp() external {
        // Setup Registry and modules:
        priceRouter = new PriceRouter();
        gravity = new MockGravity();
        lekkerFinanceAdaptor = new LekkerFinanceAdaptor();
        erc20Adaptor = new ERC20Adaptor();

        registry = new Registry(
            // Set this contract to the Gravity Bridge for testing to give the permissions usually
            // given to the Gravity Bridge to this contract.
            address(this),
            address(swapRouter),
            address(priceRouter)
        );

        priceRouter.addAsset(USDC, 0, 0, false, 0);
        priceRouter.addAsset(DAI, 0, 0, false, 0);
        priceRouter.addAsset(WETH, 0, 0, false, 0);

        // Cellar positions array.
        uint32[] memory positions = new uint32[](5);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(lekkerFinanceAdaptor), 0, 0);
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);

        usdcPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(USDC), 0, 0);
        daiPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(DAI), 0, 0);
        wethPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(WETH), 0, 0);
        
        positions[0] = usdcPosition;
        positions[1] = daiPosition;
        positions[2] = wethPosition;

        bytes[] memory positionConfigs = new bytes[](5);

        cellar = new MockCellar(
            registry,
            USDC,
            positions,
            positionConfigs,
            "Multiposition Cellar LP Token",
            "multiposition-CLR",
            strategist
        );
        vm.label(address(cellar), "cellar");
        vm.label(strategist, "strategist");

        // Allow cellar to use CellarAdaptor so it can swap ERC20's and enter/leave other cellar positions.
        cellar.setupAdaptor(address(lekkerFinanceAdaptor));

        // Approve cellar to spend all assets.
        USDC.approve(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    // ========================================== POSITION MANAGEMENT TEST ==========================================
    function testOpenLeveragePosition() external {
        deal(address(USDC), address(this), 101_000e6);
        cellar.deposit(101_000e6, address(this));

        // Use `callOnAdaptor` to swap 50,000 USDC for DAI, and enter UniV3 position.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);
        adaptorCalls[0] = _createBytesDataToOpenPosition(100);

        data[0] = Cellar.AdaptorCall({ adaptor: address(lekkerFinanceAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

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

    // ========================================= HELPER FUNCTIONS =========================================
    function _sqrt(uint256 _x) internal pure returns (uint256 y) {
        uint256 z = (_x + 1) / 2;
        y = _x;
        while (z < y) {
            y = z;
            z = (_x / z + z) / 2;
        }
    }

    function _createBytesDataToOpenPosition(
        uint256 amount
    ) internal view returns (bytes memory) {
        bytes memory params = abi.encode(amount);
        return abi.encodeWithSelector(lekkerFinanceAdaptor.openPosition.selector, params);
    }

    function _createBytesDataToClosePosition(uint256 amount) internal view returns (bytes memory) {
        return abi.encodeWithSelector(lekkerFinanceAdaptor.closePosition.selector, amount);
    }

}
