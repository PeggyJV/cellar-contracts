// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/mixins/ERC4626.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {AtomicSolverV2} from "src/modules/atomic-queue/AtomicSolverV2.sol";

contract MockVault is ERC4626 {
    constructor(ERC20 asset_) ERC4626(asset_, "Mock Vault", "MV") {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

contract MockWeETH is MockERC20 {
    uint256 internal immutable rate;

    constructor(uint256 rate_) MockERC20("Wrapped eETH", "weETH", 18) {
        rate = rate_;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }

    function wrap(uint256 amount) external view returns (uint256) {
        return amount * 1e18 / rate;
    }

    function unwrap(uint256 amount) external view returns (uint256) {
        return amount * rate / 1e18;
    }
}

contract AtomicSolverV2Test is Test {
    address internal constant MAINNET_EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address internal constant MAINNET_WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant ARBITRUM_WEETH = 0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe;

    uint256 internal constant WEETH_RATE = 1.05e18;
    address internal constant SOLVER_ACCOUNT = address(0xBEEF);

    AtomicSolverV2 internal solver;

    function setUp() external {
        vm.chainId(1);

        MockERC20 eETHImplementation = new MockERC20("eETH", "eETH", 18);
        MockWeETH weETHImplementation = new MockWeETH(WEETH_RATE);
        vm.etch(MAINNET_EETH, address(eETHImplementation).code);
        vm.etch(MAINNET_WEETH, address(weETHImplementation).code);

        solver = new AtomicSolverV2(address(this), Authority(address(0)));
    }

    function testRedeemSolveRejectsLossWhenMinimumDeltaIsZero() external {
        MockERC20 asset = new MockERC20("Asset", "ASSET", 18);
        MockVault share = _depositForSolve(asset, 99e18);
        _fundSolver(asset, 100e18);

        vm.expectRevert(
            abi.encodeWithSelector(AtomicSolverV2.AtomicSolverV2___RedeemSolveMinAssetDeltaNotMet.selector, 0, 0)
        );
        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM, SOLVER_ACCOUNT, 0, 100e18),
            address(solver),
            ERC20(address(share)),
            asset,
            99e18,
            100e18
        );
    }

    function testRedeemSolveRejectsBreakEvenWhenMinimumProfitIsPositive() external {
        MockERC20 asset = new MockERC20("Asset", "ASSET", 18);
        MockVault share = _depositForSolve(asset, 100e18);
        _fundSolver(asset, 100e18);

        vm.expectRevert(
            abi.encodeWithSelector(AtomicSolverV2.AtomicSolverV2___RedeemSolveMinAssetDeltaNotMet.selector, 0, 1)
        );
        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM, SOLVER_ACCOUNT, 1, 100e18),
            address(solver),
            ERC20(address(share)),
            asset,
            100e18,
            100e18
        );
    }

    function testRedeemSolveAllowsMinimumProfit() external {
        MockERC20 asset = new MockERC20("Asset", "ASSET", 18);
        MockVault share = _depositForSolve(asset, 101e18);
        _fundSolver(asset, 100e18);

        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM, SOLVER_ACCOUNT, 1e18, 100e18),
            address(solver),
            ERC20(address(share)),
            asset,
            101e18,
            100e18
        );

        assertEq(asset.balanceOf(SOLVER_ACCOUNT), 101e18);
        assertEq(asset.balanceOf(address(solver)), 100e18);
        assertEq(asset.allowance(address(solver), address(this)), 100e18);
    }

    function testLiquidSolveNormalizesWeETHCostIntoEETHBeforeCheckingDelta() external {
        MockERC20 eETH = MockERC20(MAINNET_EETH);
        MockERC20 weETH = MockERC20(MAINNET_WEETH);
        MockVault share = _depositForSolve(eETH, 105e18);
        _fundSolver(weETH, 100e18);

        vm.expectRevert(
            abi.encodeWithSelector(AtomicSolverV2.AtomicSolverV2___RedeemSolveMinAssetDeltaNotMet.selector, 0, 1)
        );
        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM_LIQUID, SOLVER_ACCOUNT, 1, 100e18),
            address(solver),
            ERC20(address(share)),
            weETH,
            105e18,
            100e18
        );
    }

    function testLiquidSolveNormalizesEETHCostIntoWeETHBeforeCheckingDelta() external {
        MockERC20 eETH = MockERC20(MAINNET_EETH);
        MockERC20 weETH = MockERC20(MAINNET_WEETH);
        MockVault share = _depositForSolve(weETH, 100e18);
        _fundSolver(eETH, 105e18);

        vm.expectRevert(
            abi.encodeWithSelector(AtomicSolverV2.AtomicSolverV2___RedeemSolveMinAssetDeltaNotMet.selector, 0, 1)
        );
        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM_LIQUID, SOLVER_ACCOUNT, 1, 105e18),
            address(solver),
            ERC20(address(share)),
            eETH,
            100e18,
            105e18
        );
    }

    function testLiquidSolveRoundsNormalizedCostUpBeforeCheckingDelta() external {
        MockERC20 eETH = MockERC20(MAINNET_EETH);
        MockERC20 weETH = MockERC20(MAINNET_WEETH);
        MockVault share = _depositForSolve(eETH, 1);
        _fundSolver(weETH, 1);

        vm.expectRevert(
            abi.encodeWithSelector(AtomicSolverV2.AtomicSolverV2___RedeemSolveMinAssetDeltaNotMet.selector, 0, 0)
        );
        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM_LIQUID, SOLVER_ACCOUNT, 0, 1),
            address(solver),
            ERC20(address(share)),
            weETH,
            1,
            1
        );
    }

    function testLiquidSolveAllowsMinimumProfitAfterNormalization() external {
        MockERC20 eETH = MockERC20(MAINNET_EETH);
        MockERC20 weETH = MockERC20(MAINNET_WEETH);
        MockVault share = _depositForSolve(eETH, 106e18);
        _fundSolver(weETH, 100e18);

        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM_LIQUID, SOLVER_ACCOUNT, 1e18, 100e18),
            address(solver),
            ERC20(address(share)),
            weETH,
            106e18,
            100e18
        );

        assertEq(eETH.balanceOf(SOLVER_ACCOUNT), 106e18);
        assertEq(weETH.allowance(address(solver), address(this)), 100e18);
    }

    function testMainnetDeploymentUsesMainnetEtherFiTokens() external {
        (bool eETHSuccess, bytes memory eETHResult) = address(solver).staticcall(abi.encodeWithSignature("eETH()"));
        (bool weETHSuccess, bytes memory weETHResult) = address(solver).staticcall(abi.encodeWithSignature("weETH()"));

        assertTrue(eETHSuccess, "eETH deployment getter missing");
        assertTrue(weETHSuccess, "weETH deployment getter missing");
        assertEq(abi.decode(eETHResult, (address)), MAINNET_EETH);
        assertEq(abi.decode(weETHResult, (address)), MAINNET_WEETH);
    }

    function testArbitrumDeploymentUsesArbitrumEtherFiTokens() external {
        vm.chainId(42161);
        AtomicSolverV2 arbitrumSolver = new AtomicSolverV2(address(this), Authority(address(0)));

        (bool eETHSuccess, bytes memory eETHResult) =
            address(arbitrumSolver).staticcall(abi.encodeWithSignature("eETH()"));
        (bool weETHSuccess, bytes memory weETHResult) =
            address(arbitrumSolver).staticcall(abi.encodeWithSignature("weETH()"));

        assertTrue(eETHSuccess, "eETH deployment getter missing");
        assertTrue(weETHSuccess, "weETH deployment getter missing");
        assertEq(abi.decode(eETHResult, (address)), address(0));
        assertEq(abi.decode(weETHResult, (address)), ARBITRUM_WEETH);
    }

    function _depositForSolve(MockERC20 asset, uint256 assets) internal returns (MockVault share) {
        share = new MockVault(asset);
        asset.mint(address(this), assets);
        asset.approve(address(share), assets);
        share.deposit(assets, address(solver));
    }

    function _fundSolver(MockERC20 asset, uint256 amount) internal {
        asset.mint(SOLVER_ACCOUNT, amount);
        vm.prank(SOLVER_ACCOUNT);
        asset.approve(address(solver), amount);
    }
}
