// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { SourceLockerFactory } from "src/modules/multi-chain-share/SourceLockerFactory.sol";
import { DestinationMinterFactory } from "src/modules/multi-chain-share/DestinationMinterFactory.sol";
import { SourceLocker } from "src/modules/multi-chain-share/SourceLocker.sol";
import { DestinationMinter } from "src/modules/multi-chain-share/DestinationMinter.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";

import { MockCCIPRouter } from "src/mocks/MockCCIPRouter.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

contract MultiChainShareTest is MainnetStarterTest, AdaptorHelperFunctions {
    SourceLockerFactory public sourceLockerFactory;
    DestinationMinterFactory public destinationMinterFactory;

    MockCCIPRouter public router;

    // Use Real Yield USD.
    ERC4626 public cellar = ERC4626(0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E);

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();
        router = new MockCCIPRouter(address(LINK));

        sourceLockerFactory = new SourceLockerFactory(
            address(this),
            address(router),
            router.SOURCE_SELECTOR(),
            router.DESTINATION_SELECTOR(),
            address(LINK)
        );

        destinationMinterFactory = new DestinationMinterFactory(
            address(this),
            address(router),
            address(sourceLockerFactory),
            router.SOURCE_SELECTOR(),
            router.DESTINATION_SELECTOR(),
            address(LINK)
        );

        sourceLockerFactory.setDestinationMinterFactory(address(destinationMinterFactory));

        deal(address(LINK), address(sourceLockerFactory), 1_000e18);
        deal(address(LINK), address(destinationMinterFactory), 1_000e18);
        deal(address(LINK), address(this), 1_000e18);
    }

    // TODO test admin withdraw on factories.

    // TODO add fuzzing for the amounts being bridged, but make sure amount going back is less than amount sent.
    function testHappyPath() external {
        (, address lockerAddress) = sourceLockerFactory.deploy(cellar);

        SourceLocker locker = SourceLocker(lockerAddress);

        // Simulate CCIP Message to destinateion factory.
        Client.Any2EVMMessage memory message = router.getLastMessage();
        vm.prank(address(router));
        destinationMinterFactory.ccipReceive(message);

        // Simulate CCIP message to source factory.
        message = router.getLastMessage();
        vm.prank(address(router));
        sourceLockerFactory.ccipReceive(message);

        DestinationMinter minter = DestinationMinter(locker.targetDestination());

        // Try bridging shares.
        deal(address(cellar), address(this), 10e18);
        cellar.approve(address(locker), 10e18);
        uint256 fee = locker.previewFee(10e18, address(this));
        LINK.approve(address(locker), fee);
        locker.bridgeToDestination(10e18, address(this), fee);

        message = router.getLastMessage();

        vm.prank(address(router));
        minter.ccipReceive(message);

        assertEq(10e18, minter.balanceOf(address(this)), "Should have minted shares.");
        assertEq(0, cellar.balanceOf(address(this)), "Should have spent Cellar shares.");

        // Try bridging the shares back.
        fee = minter.previewFee(10e18, address(this));
        LINK.approve(address(minter), 1e18);
        minter.bridgeToSource(10e18, address(this), 1e18);

        message = router.getLastMessage();

        vm.prank(address(router));
        locker.ccipReceive(message);

        assertEq(0, minter.balanceOf(address(this)), "Should have burned shares.");
        assertEq(10e18, cellar.balanceOf(address(this)), "Should have sent Cellar shares back to this address.");
    }

    //---------------------------------------- REVERT TESTS ----------------------------------------

    function testCcipReceiveChecks() external {
        // Deploy a source and minter.
        (SourceLocker locker, DestinationMinter minter) = _runDeploy();
        // Try calling ccipReceive function on all contracts using attacker contract.
        address attacker = vm.addr(0xBAD);
        uint64 badSourceChain = 1;

        Client.Any2EVMMessage memory badMessage;
        badMessage.sender = abi.encode(attacker);
        badMessage.sourceChainSelector = badSourceChain;

        vm.startPrank(attacker);
        // Revert if caller is not CCIP Router.
        vm.expectRevert(bytes(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, attacker)));
        sourceLockerFactory.ccipReceive(badMessage);

        vm.expectRevert(bytes(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, attacker)));
        destinationMinterFactory.ccipReceive(badMessage);

        vm.expectRevert(bytes(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, attacker)));
        locker.ccipReceive(badMessage);

        vm.expectRevert(bytes(abi.encodeWithSelector(CCIPReceiver.InvalidRouter.selector, attacker)));
        minter.ccipReceive(badMessage);
        vm.stopPrank();

        // Revert if source chain selector is wrong.
        vm.startPrank(address(router));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    SourceLockerFactory.SourceLockerFactory___SourceChainNotAllowlisted.selector,
                    badSourceChain
                )
            )
        );
        sourceLockerFactory.ccipReceive(badMessage);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    DestinationMinterFactory.DestinationMinterFactory___SourceChainNotAllowlisted.selector,
                    badSourceChain
                )
            )
        );
        destinationMinterFactory.ccipReceive(badMessage);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(SourceLocker.SourceLocker___SourceChainNotAllowlisted.selector, badSourceChain)
            )
        );
        locker.ccipReceive(badMessage);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    DestinationMinter.DestinationMinter___SourceChainNotAllowlisted.selector,
                    badSourceChain
                )
            )
        );
        minter.ccipReceive(badMessage);

        // Revert if message sender is wrong.
        badMessage.sourceChainSelector = locker.destinationChainSelector();
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    SourceLockerFactory.SourceLockerFactory___SenderNotAllowlisted.selector,
                    attacker
                )
            )
        );
        sourceLockerFactory.ccipReceive(badMessage);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(SourceLocker.SourceLocker___SenderNotAllowlisted.selector, attacker))
        );
        locker.ccipReceive(badMessage);

        badMessage.sourceChainSelector = locker.sourceChainSelector();

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    DestinationMinterFactory.DestinationMinterFactory___SenderNotAllowlisted.selector,
                    attacker
                )
            )
        );
        destinationMinterFactory.ccipReceive(badMessage);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(DestinationMinter.DestinationMinter___SenderNotAllowlisted.selector, attacker))
        );
        minter.ccipReceive(badMessage);

        vm.stopPrank();
    }

    function testSourceLockerReverts() external {
        (SourceLocker locker, ) = _runDeploy();

        // Only callable by source locker factory.
        vm.expectRevert(bytes(abi.encodeWithSelector(SourceLocker.SourceLocker___OnlyFactory.selector)));
        locker.setTargetDestination(address(this));

        // Can only be set once.
        vm.startPrank(address(sourceLockerFactory));
        vm.expectRevert(
            bytes(abi.encodeWithSelector(SourceLocker.SourceLocker___TargetDestinationAlreadySet.selector))
        );
        locker.setTargetDestination(address(this));
        vm.stopPrank();

        // TODO check bridge to destination reverts.
    }

    function testDestinationMinterReverts() external {
        // TODO check bridge to source reverts.
        // TODO test where we try burning more than we have.
    }

    function _runDeploy() internal returns (SourceLocker locker, DestinationMinter minter) {
        (, address lockerAddress) = sourceLockerFactory.deploy(cellar);

        locker = SourceLocker(lockerAddress);

        // Simulate CCIP Message to destinateion factory.
        Client.Any2EVMMessage memory message = router.getLastMessage();
        vm.prank(address(router));
        destinationMinterFactory.ccipReceive(message);

        // Simulate CCIP message to source factory.
        message = router.getLastMessage();
        vm.prank(address(router));
        sourceLockerFactory.ccipReceive(message);

        minter = DestinationMinter(locker.targetDestination());
    }
}
