// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";
import { ERC4626SharePriceOracleKeeper } from "src/base/ERC4626SharePriceOracleKeeper.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { MockERC20 } from "@solmate/test/utils/mocks/MockERC20.sol";
import { MockERC4626 } from "@solmate/test/utils/mocks/MockERC4626.sol";

/// @notice `automationForwarder` is assigned once in the constructor and has no
///         setter anywhere in either contract. Deploying with a zero keeper
///         would therefore brick the oracle permanently: `performUpkeep` requires
///         `msg.sender == automationForwarder`, and no caller can ever be
///         `address(0)`, so the ring could never advance and the vault it backs
///         could never be unfrozen.
contract ZeroKeeperGuardTest {
    MockERC20 internal asset;
    MockERC4626 internal target;

    function _args() internal view returns (ERC4626SharePriceOracle.ConstructorArgs memory) {
        return
            ERC4626SharePriceOracle.ConstructorArgs({
                _target: ERC4626(address(target)),
                _heartbeat: 43_200,
                _deviationTrigger: 50,
                _gracePeriod: 86_400,
                _observationsToUse: 3,
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

    function setUp() public {
        asset = new MockERC20("Wrapped Ether", "WETH", 18);
        target = new MockERC4626(asset, "Vault", "VLT");
    }

    function test_zeroKeeperIsRejected() public {
        bool reverted;
        try new ERC4626SharePriceOracleKeeper(_args(), address(0)) returns (
            ERC4626SharePriceOracleKeeper
        ) {
            reverted = false;
        } catch {
            reverted = true;
        }
        require(reverted, "deploying with a zero keeper must revert");
    }

    function test_realKeeperIsAccepted() public {
        address keeper = address(0xF267823CF091917B3072245566CD073833AFf65B);
        ERC4626SharePriceOracleKeeper oracle = new ERC4626SharePriceOracleKeeper(_args(), keeper);
        require(oracle.automationForwarder() == keeper, "forwarder must be the keeper");
        require(oracle.heartbeat() == 43_200, "heartbeat must survive construction");
        require(oracle.gracePeriod() == 86_400, "grace period must survive construction");
        require(oracle.observationsLength() == 4, "observationsToUse + 1");
    }
}
