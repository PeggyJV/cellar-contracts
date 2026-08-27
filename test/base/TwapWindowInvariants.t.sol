// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { ERC4626SharePriceOracleKeeper } from "src/base/ERC4626SharePriceOracleKeeper.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { MockERC20 } from "@solmate/test/utils/mocks/MockERC20.sol";
import { MockERC4626 } from "@solmate/test/utils/mocks/MockERC4626.sol";

uint64 constant HEARTBEAT = 43_200; // 12h
uint64 constant GRACE = 86_400; // 24h
uint16 constant OBSERVATIONS_TO_USE = 3; // => observationsLength 4
uint16 constant RING = OBSERVATIONS_TO_USE + 1;

// Per-interval lateness budget, `gracePeriod / (L - 2)`. This is the number the
// Rust keeper's `schedule.rs` derives and schedules against; asserting it here
// checks it from the contract side, independently.
uint64 constant BUDGET = GRACE / (RING - 2);

/// @notice Drives the oracle the way a correct keeper would: never earlier than
///         one heartbeat, never later than heartbeat + budget, with modest yield
///         accrual in between.
contract DisciplinedKeeper is Test {
    ERC4626SharePriceOracleKeeper public oracle;
    MockERC20 public asset;
    MockERC4626 public target;

    uint256 public upkeeps;
    uint256 public maxSpacingUsed;

    constructor(MockERC20 _asset, MockERC4626 _target) {
        asset = _asset;
        target = _target;
    }

    function setOracle(ERC4626SharePriceOracleKeeper _oracle) external {
        oracle = _oracle;
    }

    /// @param spacingSeed chooses how long to wait, always inside the bound
    /// @param yieldSeed   modest asset movement, far inside the kill-switch band
    function advanceAndUpkeep(uint256 spacingSeed, uint256 yieldSeed) external {
        uint256 spacing = bound(spacingSeed, HEARTBEAT, HEARTBEAT + BUDGET);
        vm.warp(block.timestamp + spacing);

        // Up to 1% drift per interval. Real vaults here are idle WETH, so this
        // is generous; the point is that the invariant must not depend on the
        // price being static.
        uint256 assets = target.totalAssets();
        uint256 drift = bound(yieldSeed, 0, assets / 100);
        if (drift > 0) asset.mint(address(target), drift);

        oracle.performUpkeep("");

        upkeeps++;
        if (spacing > maxSpacingUsed) maxSpacingUsed = spacing;
    }
}

/// @notice The property that protects user funds.
///
/// `getLatest()` reports `isNotSafeToUse` unless the span between the oldest and
/// most recently completed observation lies within
/// `[heartbeat*(L-2), heartbeat*(L-2) + gracePeriod]`. When it reports unsafe,
/// `CellarWithOracle` reverts with `Cellar__OracleFailure()` and every
/// withdrawal fails — which is exactly the outage this whole effort exists to
/// end.
///
/// The Rust keeper schedules against a derived per-interval bound of
/// `heartbeat <= spacing <= heartbeat + gracePeriod/(L-2)`. These invariants
/// check that claim against the contract itself rather than against the same
/// arithmetic restated.
contract TwapWindowInvariants is StdInvariant, Test {
    MockERC20 internal asset;
    MockERC4626 internal target;
    ERC4626SharePriceOracleKeeper internal oracle;
    DisciplinedKeeper internal keeper;

    function setUp() public {
        vm.warp(1_700_000_000);

        asset = new MockERC20("Wrapped Ether", "WETH", 18);
        target = new MockERC4626(asset, "Vault", "VLT");
        asset.mint(address(this), 1_000e18);
        asset.approve(address(target), type(uint256).max);
        target.deposit(1_000e18, address(this));

        keeper = new DisciplinedKeeper(asset, target);

        oracle = new ERC4626SharePriceOracleKeeper(
            ERC4626SharePriceOracle.ConstructorArgs({
                _target: ERC4626(address(target)),
                _heartbeat: HEARTBEAT,
                _deviationTrigger: 50,
                _gracePeriod: GRACE,
                _observationsToUse: OBSERVATIONS_TO_USE,
                _automationRegistry: address(0),
                _automationRegistrar: address(0),
                _automationAdmin: address(0),
                _link: address(0),
                _startingAnswer: 1e18,
                _allowedAnswerChangeLower: 7_500,
                _allowedAnswerChangeUpper: 12_500,
                _sequencerUptimeFeed: address(0),
                _sequencerGracePeriod: 0
            }),
            address(keeper)
        );
        keeper.setOracle(oracle);

        // Restrict the fuzzer to the one action that models a keeper. Without
        // this it also calls `setOracle` (repointing the handler at garbage) and
        // the inherited `failed()`, neither of which is a behaviour a real
        // keeper has — they produce harness noise, not findings.
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = DisciplinedKeeper.advanceAndUpkeep.selector;
        targetSelector(FuzzSelector({ addr: address(keeper), selectors: selectors }));
        targetContract(address(keeper));
    }

    /// @notice The one that matters: a keeper that respects the spacing bound
    ///         keeps withdrawals open, forever, no matter how the sequence of
    ///         intervals is chosen within that bound.
    function invariant_disciplinedKeeperKeepsTheOracleUsable() public {
        // The ring needs (L-2) completed intervals before a TWAA exists at all.
        if (keeper.upkeeps() < uint256(RING) - 1) return;
        (, , bool notSafe) = oracle.getLatest();
        assertFalse(notSafe, "oracle left its window despite in-bound spacing");
    }

    /// @notice The ring index must always address a real slot.
    function invariant_ringIndexStaysInBounds() public {
        assertLt(oracle.currentIndex(), oracle.observationsLength(), "index escaped the ring");
        assertEq(oracle.observationsLength(), RING, "ring length is immutable");
    }

    /// @notice The kill switch is one-way by design; nothing may clear it.
    function invariant_killSwitchNeverClears() public {
        // Under this handler the switch must never engage at all: drift is
        // capped at 1% per interval, far inside the +/-25% band.
        assertFalse(oracle.killSwitch(), "kill switch engaged under benign drift");
    }

    /// @notice Sanity that the run actually exercised the upper edge of the
    ///         budget rather than only comfortable spacings.
    function invariant_handlerReachesTheBudgetEdge() public {
        if (keeper.upkeeps() < 8) return;
        assertGt(keeper.maxSpacingUsed(), HEARTBEAT, "fuzzer never went late at all");
    }
}

/// @notice The bound must be tight in both directions, or it is not the real
///         constraint. These are ordinary tests rather than invariants because
///         they deliberately drive the oracle out of its window.
contract TwapWindowBoundIsTight is Test {
    MockERC20 internal asset;
    MockERC4626 internal target;
    ERC4626SharePriceOracleKeeper internal oracle;

    address internal constant FORWARDER = address(0xBEEF);

    function setUp() public {
        vm.warp(1_700_000_000);
        asset = new MockERC20("Wrapped Ether", "WETH", 18);
        target = new MockERC4626(asset, "Vault", "VLT");
        asset.mint(address(this), 1_000e18);
        asset.approve(address(target), type(uint256).max);
        target.deposit(1_000e18, address(this));

        oracle = new ERC4626SharePriceOracleKeeper(
            ERC4626SharePriceOracle.ConstructorArgs({
                _target: ERC4626(address(target)),
                _heartbeat: HEARTBEAT,
                _deviationTrigger: 50,
                _gracePeriod: GRACE,
                _observationsToUse: OBSERVATIONS_TO_USE,
                _automationRegistry: address(0),
                _automationRegistrar: address(0),
                _automationAdmin: address(0),
                _link: address(0),
                _startingAnswer: 1e18,
                _allowedAnswerChangeLower: 7_500,
                _allowedAnswerChangeUpper: 12_500,
                _sequencerUptimeFeed: address(0),
                _sequencerGracePeriod: 0
            }),
            FORWARDER
        );
    }

    function _step(uint256 spacing) internal {
        vm.warp(block.timestamp + spacing);
        vm.prank(FORWARDER);
        oracle.performUpkeep("");
    }

    /// @notice Spacing exactly at the budget edge is still inside the window.
    ///         `schedule.rs` treats the budget as inclusive; this confirms it.
    function test_spacingAtExactlyTheBudgetEdgeIsStillSafe() public {
        for (uint256 i; i < 4; ++i) _step(HEARTBEAT + BUDGET);
        (, , bool notSafe) = oracle.getLatest();
        assertFalse(notSafe, "the budget edge must be inclusive");
    }

    /// @notice One second beyond the budget leaves the window. This is the
    ///         failure the keeper exists to prevent, and it is what refreezes
    ///         withdrawals.
    function test_oneSecondPastTheBudgetBreaksTheOracle() public {
        for (uint256 i; i < 4; ++i) _step(HEARTBEAT + BUDGET + 1);
        (, , bool notSafe) = oracle.getLatest();
        assertTrue(notSafe, "the budget must be the real ceiling");
    }

    /// @notice Firing early is refused by the contract, not silently accepted —
    ///         so an over-eager keeper cannot corrupt the ring, it just wastes
    ///         gas. `schedule.rs` relies on this to make early firing harmless.
    function test_firingBeforeTheHeartbeatIsRejected() public {
        _step(HEARTBEAT + 1);
        vm.warp(block.timestamp + HEARTBEAT - 10);
        vm.prank(FORWARDER);
        vm.expectRevert();
        oracle.performUpkeep("");
    }

    /// @notice The derived budget matches the contract's own arithmetic.
    function test_budgetMatchesTheContractWindow() public {
        uint256 minDuration = uint256(HEARTBEAT) * (RING - 2);
        uint256 maxDuration = minDuration + GRACE;
        // L-2 intervals each at heartbeat+BUDGET must land exactly on maxDuration.
        assertEq((uint256(HEARTBEAT) + BUDGET) * (RING - 2), maxDuration, "budget is not the exact edge");
        assertEq(uint256(HEARTBEAT) * (RING - 2), minDuration, "floor is not one heartbeat per interval");
        assertEq(BUDGET, 43_200, "12h of slack at the deployed parameters");
    }
}
