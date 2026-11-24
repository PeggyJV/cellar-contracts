// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {Authority} from "@solmate/auth/Auth.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/mixins/ERC4626.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {AtomicSolverV2} from "src/modules/atomic-queue/AtomicSolverV2.sol";

contract MockVault is ERC4626 {
    constructor(ERC20 asset_) ERC4626(asset_, "Mock Vault", "MV") {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

contract MockWeETH is MockERC20 {
    using SafeTransferLib for ERC20;

    address internal constant EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;

    uint256 internal immutable pooledEETH;
    uint256 internal immutable totalShares;

    constructor(uint256 pooledEETH_, uint256 totalShares_) MockERC20("Wrapped eETH", "weETH", 18) {
        pooledEETH = pooledEETH_;
        totalShares = totalShares_;
    }

    function getRate() external view returns (uint256) {
        return 1e18 * pooledEETH / totalShares;
    }

    function wrap(uint256 amount) external returns (uint256 shares) {
        ERC20(EETH).safeTransferFrom(msg.sender, address(this), amount);
        shares = amount * totalShares / pooledEETH;
        _mint(msg.sender, shares);
    }

    function unwrap(uint256 amount) external returns (uint256 assets) {
        _burn(msg.sender, amount);
        assets = amount * pooledEETH / totalShares;
        MockERC20(EETH).mint(msg.sender, assets);
    }
}

contract AtomicSolverV2Test is Test {
    address internal constant MAINNET_EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address internal constant MAINNET_WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant ARBITRUM_WEETH = 0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe;

    uint256 internal constant MOCK_POOLED_EETH = 105e18 + 1;
    uint256 internal constant MOCK_TOTAL_SHARES = 100e18;
    uint256 internal constant WEETH_RATE = 1.05e18;
    address internal constant SOLVER_ACCOUNT = address(0xBEEF);

    AtomicSolverV2 internal solver;

    function setUp() external {
        vm.chainId(1);

        MockERC20 eETHImplementation = new MockERC20("eETH", "eETH", 18);
        MockWeETH weETHImplementation = new MockWeETH(MOCK_POOLED_EETH, MOCK_TOTAL_SHARES);
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

    function testRedeemSolveRejectsCrossTokenPair() external {
        MockERC20 asset = new MockERC20("Six Decimal Asset", "ASSET", 6);
        MockERC20 want = new MockERC20("Eighteen Decimal Want", "WANT", 18);
        MockVault share = _depositForSolve(asset, 100e6);
        _fundSolver(want, 1);

        bytes4 unsupportedPair = bytes4(keccak256("AtomicSolverV2___UnsupportedRedeemPair(address,address)"));
        vm.expectRevert(abi.encodeWithSelector(unsupportedPair, address(asset), address(want)));
        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM, SOLVER_ACCOUNT, 0, 1),
            address(solver),
            ERC20(address(share)),
            want,
            100e6,
            1
        );
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
        uint256 assetsFromRedeem = 106e18 + 100;
        MockVault share = _depositForSolve(eETH, assetsFromRedeem);
        _fundSolver(weETH, 100e18);

        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM_LIQUID, SOLVER_ACCOUNT, 1e18, 100e18),
            address(solver),
            ERC20(address(share)),
            weETH,
            assetsFromRedeem,
            100e18
        );

        assertEq(eETH.balanceOf(SOLVER_ACCOUNT), assetsFromRedeem);
        assertEq(weETH.allowance(address(solver), address(this)), 100e18);
    }

    function testLiquidSolveWrapFallbackCoversRequestedWeETHAtRoundedRateBoundary() external {
        MockERC20 eETH = MockERC20(MAINNET_EETH);
        MockERC20 weETH = MockERC20(MAINNET_WEETH);
        uint256 requestedWeETH = 1e18;
        uint256 conservativeEETHCost = WEETH_RATE + 1;
        MockVault share = _depositForSolve(eETH, conservativeEETHCost + 1);
        _approveSolver(eETH);

        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM_LIQUID, SOLVER_ACCOUNT, 1, requestedWeETH),
            address(solver),
            ERC20(address(share)),
            weETH,
            conservativeEETHCost + 1,
            requestedWeETH
        );

        assertEq(weETH.balanceOf(address(solver)), requestedWeETH);
        assertEq(weETH.allowance(address(solver), address(this)), requestedWeETH);
    }

    function testLiquidSolveGuardUsesConservativeWrapCost() external {
        MockERC20 eETH = MockERC20(MAINNET_EETH);
        MockERC20 weETH = MockERC20(MAINNET_WEETH);
        uint256 requestedWeETH = 1e18;
        MockVault share = _depositForSolve(eETH, WEETH_RATE);
        _fundSolver(weETH, requestedWeETH);

        vm.expectRevert(
            abi.encodeWithSelector(AtomicSolverV2.AtomicSolverV2___RedeemSolveMinAssetDeltaNotMet.selector, 0, 0)
        );
        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM_LIQUID, SOLVER_ACCOUNT, 0, requestedWeETH),
            address(solver),
            ERC20(address(share)),
            weETH,
            WEETH_RATE,
            requestedWeETH
        );
    }

    function testLiquidSolveRejectsWrapUnderDelivery() external {
        MockERC20 eETH = MockERC20(MAINNET_EETH);
        MockERC20 weETH = MockERC20(MAINNET_WEETH);
        uint256 requestedWeETH = 1e18;
        uint256 conservativeEETHCost = WEETH_RATE + 1;
        MockVault share = _depositForSolve(eETH, conservativeEETHCost + 1);
        _approveSolver(eETH);

        vm.mockCall(
            MAINNET_WEETH,
            abi.encodeWithSelector(bytes4(keccak256("wrap(uint256)")), conservativeEETHCost),
            abi.encode(requestedWeETH - 1)
        );
        vm.expectRevert(AtomicSolverV2.AtomicSolverV2___FailedToSolve.selector);
        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM_LIQUID, SOLVER_ACCOUNT, 1, requestedWeETH),
            address(solver),
            ERC20(address(share)),
            weETH,
            conservativeEETHCost + 1,
            requestedWeETH
        );
    }

    function testLiquidSolveUnwrapFallbackCoversRequestedEETH() external {
        MockERC20 eETH = MockERC20(MAINNET_EETH);
        MockERC20 weETH = MockERC20(MAINNET_WEETH);
        uint256 requestedEETH = 1e18;
        uint256 conservativeWeETHCost = 952_380_952_380_952_381;
        MockVault share = _depositForSolve(weETH, conservativeWeETHCost + 1);
        _approveSolver(weETH);

        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM_LIQUID, SOLVER_ACCOUNT, 1, requestedEETH),
            address(solver),
            ERC20(address(share)),
            eETH,
            conservativeWeETHCost + 1,
            requestedEETH
        );

        assertGe(eETH.balanceOf(address(solver)), requestedEETH);
        assertEq(eETH.allowance(address(solver), address(this)), requestedEETH);
    }

    function testLiquidSolveRejectsUnsupportedCrossTokenPair() external {
        MockERC20 asset = new MockERC20("Asset", "ASSET", 18);
        MockERC20 want = new MockERC20("Want", "WANT", 18);
        MockVault share = _depositForSolve(asset, 101e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                AtomicSolverV2.AtomicSolverV2___UnsupportedLiquidPair.selector, address(asset), address(want)
            )
        );
        solver.finishSolve(
            abi.encode(AtomicSolverV2.SolveType.REDEEM_LIQUID, SOLVER_ACCOUNT, 1e18, 100e18),
            address(solver),
            ERC20(address(share)),
            want,
            101e18,
            100e18
        );
    }

    function testLiquidSolveAllowsSameTokenAcrossDeploymentChains() external {
        uint256[3] memory chainIds = [uint256(1), uint256(42161), uint256(31337)];

        for (uint256 i; i < chainIds.length; ++i) {
            vm.chainId(chainIds[i]);
            solver = new AtomicSolverV2(address(this), Authority(address(0)));
            MockERC20 asset = new MockERC20("Asset", "ASSET", 18);
            MockVault share = _depositForSolve(asset, 101e18);
            _fundSolver(asset, 100e18);

            solver.finishSolve(
                abi.encode(AtomicSolverV2.SolveType.REDEEM_LIQUID, SOLVER_ACCOUNT, 1e18, 100e18),
                address(solver),
                ERC20(address(share)),
                asset,
                101e18,
                100e18
            );

            assertEq(asset.allowance(address(solver), address(this)), 100e18);
        }
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
        _approveSolver(asset);
    }

    function _approveSolver(MockERC20 asset) internal {
        vm.prank(SOLVER_ACCOUNT);
        asset.approve(address(solver), type(uint256).max);
    }
}
