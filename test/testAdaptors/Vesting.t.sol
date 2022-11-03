// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { MockCellar, Cellar, ERC20 } from "src/mocks/MockCellar.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { Registry, IGravity } from "src/base/Cellar.sol";
import { MockPriceRouter } from "src/mocks/MockPriceRouter.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract CellarVestingTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    MockCellar private cellar;

    MockPriceRouter private priceRouter;
    SwapRouter private swapRouter;
    Registry private registry;
    VestingSimple private vesting;

    ERC20Adaptor private erc20Adaptor;
    VestingSimpleAdaptor private vestingAdaptor;

    uint32 private usdcPosition;
    uint32 private vestingPosition;

    address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    ERC20 private constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address private immutable strategist = vm.addr(0xBEEF);
    address private immutable user2 = vm.addr(0xFEED);
    uint256 private constant totalDeposit = 100_000e6;
    uint256 private constant vestingPeriod = 1 days;

    function setUp() external {
        priceRouter = new MockPriceRouter();
        swapRouter = new SwapRouter(IUniswapV2Router(uniV2Router), IUniswapV3Router(uniV3Router));

        registry = new Registry(
            // Set this contract to the Gravity Bridge for testing to give the permissions usually
            // given to the Gravity Bridge to this contract.
            address(this),
            address(swapRouter),
            address(priceRouter)
        );

        priceRouter.supportAsset(USDC);
        priceRouter.setExchangeRate(USDC, USDC, 1e6);

        erc20Adaptor = new ERC20Adaptor();
        vestingAdaptor = new VestingSimpleAdaptor();

        // Set up a vesting contract for USDC
        vesting = new VestingSimple(USDC, vestingPeriod, 1e6);

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);
        registry.trustAdaptor(address(vestingAdaptor), 0, 0);
        usdcPosition = registry.trustPosition(address(erc20Adaptor), false, abi.encode(USDC), 0, 0);
        vestingPosition = registry.trustPosition(address(vestingAdaptor), false, abi.encode(vesting), 0, 0);

        // Cellar positions array
        uint32[] memory positions = new uint32[](2);
        positions[0] = usdcPosition;
        positions[1] = vestingPosition;

        bytes[] memory positionConfigs = new bytes[](2);

        // Deploy cellar
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

        cellar.setupAdaptor(address(erc20Adaptor));
        cellar.setupAdaptor(address(vestingAdaptor));

        // Set up share lock period, make approvals, and set larger rebalance
        USDC.approve(address(cellar), type(uint256).max);
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));

        // Allow 10% rebalance deviation, so we can deposit to vesting without triggering totalAssets check
        cellar.setRebalanceDeviation(1e17);

        // Deposit funds to cellar
        deal(address(USDC), address(this), totalDeposit);
        cellar.deposit(totalDeposit, address(this));
    }

    // ========================================== POSITION MANAGEMENT TEST ==========================================

    function testCannotTakeUserDeposits() external {
        // Make the vesting adaptor the first position
        cellar.swapPositions(0, 1);

        // Set up user2 with funds and have them attempt to deposit
        deal(address(USDC), user2, totalDeposit);
        vm.startPrank(user2);
        USDC.approve(address(cellar), type(uint256).max);

        vm.expectRevert(bytes(abi.encodeWithSelector(
            BaseAdaptor.BaseAdaptor__UserDepositsNotAllowed.selector
        )));

        cellar.deposit(totalDeposit, user2);

        vm.stopPrank();

        // Fix positions
        cellar.swapPositions(0, 1);
    }

    function testDepositToVesting() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Deposit 5% of holdings, allowed under deviation
        adaptorCalls[0] = _createBytesDataToDeposit(vesting, totalDeposit / 20);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });

        // Check event emission
        vm.expectEmit(true, false, false, false);
        _emitDeposit(totalDeposit / 20);

        cellar.callOnAdaptor(data);

        // Check TVL change
        assertEq(cellar.totalAssets(), totalDeposit - (totalDeposit / 20), "Cellar totalAssets should decrease by 5%");

        // Check state in vesting contract
        assertApproxEqAbs(vesting.totalBalanceOf(address(cellar)), totalDeposit / 20, 1, "Vesting contract should report deposited funds");
        assertApproxEqAbs(vesting.vestedBalanceOf(address(cellar)), 0, 1, "Vesting contract should not report vested funds");
    }

    function testFailWithdrawMoreThanVested() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Deposit 5% of holdings, allowed under deviation
        adaptorCalls[0] = _createBytesDataToDeposit(vesting, totalDeposit / 20);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });

        // Check event emission
        vm.expectEmit(true, false, false, true);
        _emitDeposit(totalDeposit / 20);

        cellar.callOnAdaptor(data);

        // Move through half of vesting period
        skip(vestingPeriod / 2);

        // Try to withdraw all funds - should not be vested
        adaptorCalls[0] = _createBytesDataToWithdrawAny(vesting, totalDeposit / 20);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });

        // Not looking at specific payload because amount available may be slightly  off
        cellar.callOnAdaptor(data);
    }

    function testDepositAndWithdrawReturnsZero() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](2);

        // Deposit 5% of holdings, allowed under deviation
        adaptorCalls[0] = _createBytesDataToDeposit(vesting, totalDeposit / 20);
        adaptorCalls[1] = _createBytesDataToWithdrawAll(vesting);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });

        // Do deposit, and withdraw, in same tx. Make sure tokens are not reclaimed
        cellar.callOnAdaptor(data);

        // Check state in vesting contract
        assertApproxEqAbs(vesting.totalBalanceOf(address(cellar)), totalDeposit / 20, 1, "Vesting contract should report deposited funds");
        assertApproxEqAbs(vesting.vestedBalanceOf(address(cellar)), 0, 1, "Vesting contract should not report vested funds");

        // Check tokens are in the right place
        assertEq(USDC.balanceOf(address(cellar)), totalDeposit - totalDeposit / 20);
        assertEq(USDC.balanceOf(address(vesting)), totalDeposit / 20);
    }

    function testUserWithdrawFromVesting() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Deposit 5% of holdings, allowed under deviation
        adaptorCalls[0] = _createBytesDataToDeposit(vesting, totalDeposit / 20);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // Swap positions so vesting is first, and skip forward
        skip(vestingPeriod + 1);
        cellar.swapPositions(0, 1);

        vm.expectEmit(true, true, false, false);
        _emitWithdraw(totalDeposit / 20, 1);

        // Withdraw vested positions
        cellar.withdraw(
            totalDeposit / 20,
            address(this),
            address(this)
        );

        // Check state - deposited tokens withdrawn
        assertApproxEqAbs(vesting.totalBalanceOf(address(cellar)), 0, 1, "Vesting contract should not report deposited funds");
        assertApproxEqAbs(vesting.vestedBalanceOf(address(cellar)), 0, 1, "Vesting contract should not report vested funds");

        // Check tokens are in the right place
        assertApproxEqAbs(USDC.balanceOf(address(cellar)), totalDeposit - totalDeposit / 20, 1, "Cellar should have 95% of tokens");
        assertApproxEqAbs(USDC.balanceOf(address(this)), totalDeposit / 20, 1, "User should withdraw 5% of tokens");

        // Swap positions back
        cellar.swapPositions(0, 1);
    }

    function testStrategistWithdrawFromVesting() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Deposit 5% of holdings, allowed under deviation
        adaptorCalls[0] = _createBytesDataToDeposit(vesting, totalDeposit / 20);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // skip forward
        skip(vestingPeriod + 1);

        // Withdraw vested positions as part of strategy 0 - should be deposit 1
        adaptorCalls[0] = _createBytesDataToWithdraw(vesting, 1, totalDeposit / 20);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });

        // Not looking at specific payload because amount available may be slightly off
        vm.expectEmit(true, true, false, false);
        _emitWithdraw(totalDeposit / 20, 1);

        cellar.callOnAdaptor(data);

        // Check state - deposited tokens withdrawn
        assertApproxEqAbs(vesting.totalBalanceOf(address(cellar)), 0, 1, "Vesting contract should not report deposited funds");
        assertApproxEqAbs(vesting.vestedBalanceOf(address(cellar)), 0, 1, "Vesting contract should not report vested funds");

        // Check cellar total assets is back to 100%
        assertApproxEqAbs(cellar.totalAssets(), totalDeposit, 1, "Cellar totalAssets should return to original value");
    }

    function testStrategistWithdrawAnyFromVesting() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Deposit 5% of holdings, allowed under deviation
        adaptorCalls[0] = _createBytesDataToDeposit(vesting, totalDeposit / 20);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // skip forward
        skip(vestingPeriod + 1);

        // Withdraw vested positions as part of strategy 0 - no deposit specified
        adaptorCalls[0] = _createBytesDataToWithdrawAny(vesting, totalDeposit / 20);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });

        // Not looking at specific payload because amount available may be slightly off
        vm.expectEmit(true, true, false, false);
        _emitWithdraw(totalDeposit / 20, 1);

        cellar.callOnAdaptor(data);

        // Check state - deposited tokens withdrawn
        assertApproxEqAbs(vesting.totalBalanceOf(address(cellar)), 0, 1, "Vesting contract should not report deposited funds");
        assertApproxEqAbs(vesting.vestedBalanceOf(address(cellar)), 0, 1, "Vesting contract should not report vested funds");

        // Check cellar total assets is back to 100%
        assertApproxEqAbs(cellar.totalAssets(), totalDeposit, 1, "Cellar totalAssets should return to original value");
    }

    function testStrategistWithdrawAllFromVesting() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Deposit 5% of holdings, allowed under deviation
        adaptorCalls[0] = _createBytesDataToDeposit(vesting, totalDeposit / 20);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // skip forward, half of vesting period
        skip(vestingPeriod / 2);

        // Withdraw vested positions as part of strategy 0 - no deposit specified
        adaptorCalls[0] = _createBytesDataToWithdrawAll(vesting);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });

        // Not looking at specific payload because amount available may be slightly off
        vm.expectEmit(true, true, false, false);
        _emitWithdraw(totalDeposit / 40, 1);

        cellar.callOnAdaptor(data);

        // Check state - deposited tokens withdrawn
        assertApproxEqAbs(vesting.totalBalanceOf(address(cellar)), totalDeposit / 40, 1, "Vesting contract should report deposited funds");
        assertApproxEqAbs(vesting.vestedBalanceOf(address(cellar)), 0, 1, "Vesting contract should not report vested funds");

        // Check cellar total assets is back to 97.5%
        assertApproxEqAbs(cellar.totalAssets(), totalDeposit / 1000 * 975, 1, "Cellar totalAssets should regain half of deposit");
    }

    function testStrategistPartialWithdrawFromVesting() external {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);

        // Deposit 5% of holdings, allowed under deviation
        adaptorCalls[0] = _createBytesDataToDeposit(vesting, totalDeposit / 20);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);

        // skip forward entire vesting period
        skip(vestingPeriod + 1);

        // Withdraw vested positions as part of strategy 0 - no deposit specified
        // Only withdraw half available
        adaptorCalls[0] = _createBytesDataToWithdrawAny(vesting, totalDeposit / 40);
        data[0] = Cellar.AdaptorCall({ adaptor: address(vestingAdaptor), callData: adaptorCalls });

        // Not looking at specific payload because amount available may be slightly off
        vm.expectEmit(true, true, false, false);
        _emitWithdraw(totalDeposit / 40, 1);

        cellar.callOnAdaptor(data);

        // Check state - deposited tokens withdrawn
        assertApproxEqAbs(vesting.totalBalanceOf(address(cellar)), totalDeposit / 40, 1, "Vesting contract should report deposited funds");
        assertApproxEqAbs(vesting.vestedBalanceOf(address(cellar)), totalDeposit / 40, 1, "Vesting contract should report vested funds");

        // Check cellar total assets is back to 100%
        assertApproxEqAbs(cellar.totalAssets(), totalDeposit, 1, "Cellar totalAssets should return to original value");
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _createBytesDataToDeposit(
        VestingSimple _vesting,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            VestingSimpleAdaptor.depositToVesting.selector,
            amount,
            abi.encode(_vesting)
        );
    }

    function _createBytesDataToWithdraw(
        VestingSimple _vesting,
        uint256 depositId,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            VestingSimpleAdaptor.withdrawFromVesting.selector,
            depositId,
            amount,
            abi.encode(_vesting)
        );
    }

    function _createBytesDataToWithdrawAny(
        VestingSimple _vesting,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            VestingSimpleAdaptor.withdrawAnyFromVesting.selector,
            amount,
            abi.encode(_vesting)
        );
    }

    function _createBytesDataToWithdrawAll(
        VestingSimple _vesting
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            VestingSimpleAdaptor.withdrawAllFromVesting.selector,
            abi.encode(_vesting)
        );
    }

    /// @notice Emitted when tokens are deosited for vesting.
    ///
    /// @param user The user receiving the deposit.
    /// @param amount The amount of tokens deposited.
    event Deposit(address indexed user, uint256 amount);

    /// @notice Emitted when vested tokens are withdrawn.
    ///
    /// @param user The user receiving the deposit.
    /// @param depositId The ID of the deposit specified.
    /// @param amount The amount of tokens deposited.
    event Withdraw(address indexed user, uint256 depositId, uint256 amount);

    function _emitDeposit(uint256 amount) internal {
        emit Deposit(address(cellar), amount);
    }

    function _emitWithdraw(uint256 amount, uint256 depositId) internal {
        emit Withdraw(address(cellar), depositId, amount);
    }
}
