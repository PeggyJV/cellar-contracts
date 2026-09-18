// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { ERC4626SharePriceOracleKeeper } from "src/base/ERC4626SharePriceOracleKeeper.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { MockERC20 } from "@solmate/test/utils/mocks/MockERC20.sol";
import { MockERC4626 } from "@solmate/test/utils/mocks/MockERC4626.sol";

/// @notice Equivalence of `ERC4626SharePriceOracleKeeper` to its audited base.
///
/// The subclass exists because Chainlink Automation v2.1 was decommissioned. Its
/// `performUpkeep` body is a verbatim copy of the base's apart from one
/// substitution: it computes
///
///     sharePrice  = _getTargetSharePrice()
///     currentTime = uint64(block.timestamp)
///
/// where the base decodes both from caller-supplied `performData`.
///
/// The claim this file discharges:
///
///     For all reachable states and all inputs, if the caller supplies
///     performData that matches chain state at the write block, then the base
///     and the subclass produce byte-identical storage.
///
/// If that holds, every audit finding about the base transfers to the subclass
/// by construction, which is a far stronger statement than "the bodies diff
/// clean".
///
/// The converse is deliberately NOT claimed, and `test_provenance_*` below
/// documents why: the base accepts performData that does *not* match chain
/// state, and the subclass cannot be given such data at all. The base is
/// therefore weaker on provenance and stronger on atomic-manipulation
/// resistance. Neither dominates, and a proof that asserted plain equivalence
/// would be hiding exactly the asymmetry that matters.
///
/// These run as bounded fuzz tests under `forge test`. The same properties are
/// the right targets for a symbolic runner (halmos, or Certora with a spec
/// translation) if this is ever escalated to a machine-checked proof — the
/// statements are already written as universally-quantified properties over
/// (state change, time change) rather than as examples. Neither tool is
/// installed here, so no invocation is documented; check the tool's own docs
/// for how it selects functions.
contract DerivationEquivalenceTest is Test {
    MockERC20 internal asset;
    MockERC4626 internal target;

    ERC4626SharePriceOracle internal base;
    ERC4626SharePriceOracleKeeper internal keeper;

    address internal constant FORWARDER = address(0xBEEF);

    uint64 internal constant HEARTBEAT = 43_200;
    uint64 internal constant GRACE = 86_400;
    uint16 internal constant OBSERVATIONS_TO_USE = 3;
    uint64 internal constant DEVIATION = 50;

    /// Storage slot holding `automationForwarder` (verified with
    /// `forge inspect ... storage`: slot 2, offset 0).
    uint256 internal constant SLOT_FORWARDER = 2;
    /// Packed slot: answer(27) | currentIndex(2) | observationsLength(2) | killSwitch(1).
    uint256 internal constant SLOT_PACKED = 0;
    /// `observations` dynamic array.
    uint256 internal constant SLOT_OBSERVATIONS = 1;

    function setUp() public {
        asset = new MockERC20("Wrapped Ether", "WETH", 18);
        target = new MockERC4626(asset, "Vault", "VLT");

        // A live vault at a clean 1:1 share price.
        asset.mint(address(this), 1_000e18);
        asset.approve(address(target), type(uint256).max);
        target.deposit(1_000e18, address(this));

        base = new ERC4626SharePriceOracle(_args());
        keeper = new ERC4626SharePriceOracleKeeper(_args(), FORWARDER);

        // The base sets its forwarder inside the Chainlink registration flow,
        // which is exactly what no longer exists. Write it directly so both
        // contracts are callable by the same address and the comparison is
        // about `performUpkeep` alone.
        vm.store(address(base), bytes32(SLOT_FORWARDER), bytes32(uint256(uint160(FORWARDER))));

        // Foundry starts at timestamp 1, which collides with the ring's
        // "never written" sentinel.
        vm.warp(1_700_000_000);
    }

    function _args() internal view returns (ERC4626SharePriceOracle.ConstructorArgs memory) {
        return
            ERC4626SharePriceOracle.ConstructorArgs({
                _target: ERC4626(address(target)),
                _heartbeat: HEARTBEAT,
                _deviationTrigger: DEVIATION,
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
            });
    }

    // ---------------------------------------------------------------- helpers

    /// The share price the subclass will read, computed the way the contract
    /// does: assets scaled to 18 decimals, times ONE_SHARE, over total shares.
    function _honestSharePrice() internal view returns (uint216) {
        uint256 shares = target.totalSupply();
        if (shares == 0) return 0;
        // Mock target and asset are both 18 decimals, so no rescaling is needed
        // here; `changeDecimals` in the contract is the identity in that case.
        return uint216((10 ** 18 * target.totalAssets()) / shares);
    }

    /// Full observable state of an oracle: the packed slot plus every ring entry.
    function _snapshot(address oracle) internal view returns (bytes32[] memory out) {
        uint16 len = ERC4626SharePriceOracle(oracle).observationsLength();
        out = new bytes32[](uint256(len) + 2);
        out[0] = vm.load(oracle, bytes32(SLOT_PACKED));
        out[1] = vm.load(oracle, bytes32(SLOT_OBSERVATIONS)); // array length
        bytes32 elem0 = keccak256(abi.encode(SLOT_OBSERVATIONS));
        for (uint256 i; i < len; ++i) {
            out[i + 2] = vm.load(oracle, bytes32(uint256(elem0) + i));
        }
    }

    function _assertIdentical(string memory ctx) internal {
        bytes32[] memory a = _snapshot(address(base));
        bytes32[] memory b = _snapshot(address(keeper));
        assertEq(a.length, b.length, string.concat(ctx, ": state width differs"));
        for (uint256 i; i < a.length; ++i) {
            assertEq(a[i], b[i], string.concat(ctx, ": storage differs"));
        }
    }

    /// Drive both oracles one step with matching inputs. Returns whether the
    /// base reverted, and asserts the subclass agreed about reverting.
    function _stepBoth() internal returns (bool reverted) {
        uint216 sp = _honestSharePrice();
        uint64 ts = uint64(block.timestamp);

        vm.prank(FORWARDER);
        (bool okBase, ) = address(base).call(
            abi.encodeWithSelector(ERC4626SharePriceOracle.performUpkeep.selector, abi.encode(sp, ts))
        );

        vm.prank(FORWARDER);
        (bool okKeeper, ) = address(keeper).call(
            abi.encodeWithSelector(ERC4626SharePriceOracleKeeper.performUpkeep.selector, bytes(""))
        );

        assertEq(okBase, okKeeper, "base and subclass disagreed about reverting");
        return !okBase;
    }

    /// Fill the ring so `getLatest()` is live on both.
    function _warmUp() internal {
        for (uint256 i; i < 3; ++i) {
            vm.warp(block.timestamp + HEARTBEAT + 60);
            _stepBoth();
        }
    }

    // ----------------------------------------------------------- equivalence

    /// @notice The core property, over a single step from a warmed state.
    ///
    /// `assetDelta` moves the vault's holdings (which is what a real strategist
    /// action, yield accrual, or an attacker's donation all reduce to), and
    /// `timeDelta` moves the clock. Both oracles then see the same world.
    function test_equivalenceUnderHonestPerformData(uint96 assetDelta, uint32 timeDelta) public {
        _warmUp();

        // Keep the move inside the kill-switch band so the interesting write
        // path is exercised rather than the early return.
        assetDelta = uint96(bound(assetDelta, 0, 200e18));
        timeDelta = uint32(bound(timeDelta, 1, 3 * uint256(HEARTBEAT)));

        asset.mint(address(target), assetDelta);
        vm.warp(block.timestamp + timeDelta);

        _stepBoth();
        _assertIdentical("single step");
    }

    /// @notice Equivalence must survive a whole sequence, not just one call.
    ///         Ring rotation, cumulative accumulation and index wrap only show
    ///         up over several steps.
    function test_equivalenceOverASequence(uint96 d0, uint96 d1, uint96 d2, uint32 t0, uint32 t1, uint32 t2) public {
        _warmUp();

        uint96[3] memory deltas = [
            uint96(bound(d0, 0, 100e18)),
            uint96(bound(d1, 0, 100e18)),
            uint96(bound(d2, 0, 100e18))
        ];
        uint32[3] memory times = [
            uint32(bound(t0, 1, 2 * uint256(HEARTBEAT))),
            uint32(bound(t1, 1, 2 * uint256(HEARTBEAT))),
            uint32(bound(t2, 1, 2 * uint256(HEARTBEAT)))
        ];

        for (uint256 i; i < 3; ++i) {
            asset.mint(address(target), deltas[i]);
            vm.warp(block.timestamp + times[i]);
            _stepBoth();
            _assertIdentical("sequence");
        }
    }

    /// @notice Equivalence must also hold on the paths that revert or early-return:
    ///         firing before the heartbeat elapses, and a move large enough to
    ///         trip the kill switch.
    function test_equivalenceOnRejectedUpkeeps(uint32 timeDelta, uint96 assetDelta) public {
        _warmUp();

        // Deliberately unbounded relative to the kill-switch band: a large mint
        // pushes the price beyond +25% and must engage the switch identically
        // on both.
        timeDelta = uint32(bound(timeDelta, 0, uint256(HEARTBEAT)));
        assetDelta = uint96(bound(assetDelta, 0, 5_000e18));

        asset.mint(address(target), assetDelta);
        vm.warp(block.timestamp + timeDelta);

        _stepBoth(); // asserts both agreed about reverting
        _assertIdentical("rejected upkeep");
    }

    /// @notice From construction through warm-up, with no divergence at any point.
    function test_equivalenceFromColdStart() public {
        for (uint256 i; i < 6; ++i) {
            vm.warp(block.timestamp + HEARTBEAT + 1);
            _stepBoth();
            _assertIdentical("cold start");
        }
        (, , bool notSafe) = keeper.getLatest();
        assertFalse(notSafe, "ring should be live after six steps");
    }

    // ------------------------------------------------------------ provenance

    /// @notice The asymmetry the equivalence proof deliberately does not hide.
    ///
    ///         The base writes whatever share price the caller hands it, with no
    ///         check against chain state. Here the vault sits at 1e18 and the
    ///         caller claims 1.2e18; the base records the lie.
    ///
    ///         This is the weakness the subclass removes — and the reason the
    ///         equivalence above is conditional on honest performData rather
    ///         than unconditional.
    function test_provenance_baseAcceptsAPriceThatContradictsChainState() public {
        _warmUp();
        vm.warp(block.timestamp + HEARTBEAT + 60);

        uint216 honest = _honestSharePrice();
        uint216 lie = uint216((uint256(honest) * 120) / 100); // +20%, inside the band

        vm.prank(FORWARDER);
        base.performUpkeep(abi.encode(lie, uint64(block.timestamp)));

        assertEq(base.answer(), lie, "base recorded caller-supplied data verbatim");
        assertTrue(base.answer() != honest, "the recorded value contradicts chain state");
    }

    /// @notice The subclass cannot be handed a price at all: performData is
    ///         ignored, so the written value is always a function of chain state
    ///         at the write block. Passing deliberately hostile bytes changes
    ///         nothing.
    function test_provenance_subclassIgnoresPerformDataEntirely(bytes calldata hostile) public {
        _warmUp();
        vm.warp(block.timestamp + HEARTBEAT + 60);

        uint216 honest = _honestSharePrice();

        vm.prank(FORWARDER);
        keeper.performUpkeep(hostile);

        assertEq(keeper.answer(), honest, "subclass wrote chain state regardless of calldata");
    }

    // -------------------------------------------------------- write ordering

    /// @notice A property of the audited base that the derivation preserves,
    ///         worth stating explicitly because it is easy to assume otherwise:
    ///         the kill switch does not roll back the write that tripped it.
    ///
    ///         The first check compares the incoming price against the previous
    ///         answer and returns early if out of band; if it passes, the answer
    ///         and observation are written. A later kill-switch decision can only
    ///         stop *future* upkeeps. Both contracts behave identically here.
    function test_ordering_killSwitchDoesNotRollBackTheWrite() public {
        _warmUp();
        vm.warp(block.timestamp + HEARTBEAT + 60);

        uint216 before = keeper.answer();
        // +24%: inside the +25% band, so the early return does not fire.
        asset.mint(address(target), (target.totalAssets() * 24) / 100);

        _stepBoth();

        assertTrue(keeper.answer() > before, "the elevated price was written");
        assertFalse(keeper.killSwitch(), "and the switch did not trip at 24%");
        _assertIdentical("kill switch ordering");
    }
}
