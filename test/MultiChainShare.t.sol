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
            address(LINK),
            2_000_000,
            200_000
        );

        destinationMinterFactory = new DestinationMinterFactory(
            address(this),
            address(router),
            address(sourceLockerFactory),
            router.SOURCE_SELECTOR(),
            router.DESTINATION_SELECTOR(),
            address(LINK),
            200_000,
            200_000
        );

        sourceLockerFactory.setDestinationMinterFactory(address(destinationMinterFactory));

        deal(address(LINK), address(sourceLockerFactory), 1_000e18);
        deal(address(LINK), address(destinationMinterFactory), 1_000e18);
        deal(address(LINK), address(this), 1_000e18);
    }

    function testAdminWithdraw() external {
        // Both factories have an admin withdraw function to withdraw LINK from them.
        uint256 expectedLinkBalance = LINK.balanceOf(address(this));
        uint256 linkBalance = LINK.balanceOf(address(sourceLockerFactory));
        expectedLinkBalance += linkBalance;
        sourceLockerFactory.adminWithdraw(LINK, linkBalance, address(this));

        linkBalance = LINK.balanceOf(address(destinationMinterFactory));
        expectedLinkBalance += linkBalance;
        destinationMinterFactory.adminWithdraw(LINK, linkBalance, address(this));

        assertEq(LINK.balanceOf(address(this)), expectedLinkBalance, "Balance does not equal expected.");

        // Try calling it from a non owner address.
        address nonOwner = vm.addr(1);
        vm.startPrank(nonOwner);
        vm.expectRevert(bytes("UNAUTHORIZED"));
        sourceLockerFactory.adminWithdraw(LINK, linkBalance, address(this));

        vm.expectRevert(bytes("UNAUTHORIZED"));
        destinationMinterFactory.adminWithdraw(LINK, linkBalance, address(this));
        vm.stopPrank();
    }

    function testHappyPath(uint256 amountToDestination, uint256 amountToSource) external {
        amountToDestination = bound(amountToDestination, 1e6, type(uint96).max);
        amountToSource = bound(amountToSource, 0.999e6, amountToDestination);

        (SourceLocker locker, DestinationMinter minter) = _runDeploy();

        // Try bridging shares.
        deal(address(cellar), address(this), amountToDestination);
        cellar.approve(address(locker), amountToDestination);
        uint256 fee = locker.previewFee(amountToDestination, address(this));
        LINK.approve(address(locker), fee);
        locker.bridgeToDestination(amountToDestination, address(this), fee);

        Client.Any2EVMMessage memory message = router.getLastMessage();

        vm.prank(address(router));
        minter.ccipReceive(message);

        assertEq(amountToDestination, minter.balanceOf(address(this)), "Should have minted shares.");
        assertEq(0, cellar.balanceOf(address(this)), "Should have spent Cellar shares.");
        assertEq(cellar.balanceOf(address(locker)), amountToDestination, "Should have sent shares to the locker.");

        // Try bridging the shares back.
        fee = minter.previewFee(amountToSource, address(this));
        LINK.approve(address(minter), 1e18);
        minter.bridgeToSource(amountToSource, address(this), 1e18);

        message = router.getLastMessage();

        vm.prank(address(router));
        locker.ccipReceive(message);

        assertEq(amountToDestination - amountToSource, minter.balanceOf(address(this)), "Should have burned shares.");
        assertEq(
            amountToSource,
            cellar.balanceOf(address(this)),
            "Should have sent Cellar shares back to this address."
        );
        assertEq(
            amountToDestination - amountToSource,
            cellar.balanceOf(address(locker)),
            "Locker should have reduced shares."
        );
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

        badMessage.sourceChainSelector = minter.sourceChainSelector();

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

    function testSourceLockerFactoryReverts() external {
        // Trying to set factory again reverts.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(SourceLockerFactory.SourceLockerFactory___FactoryAlreadySet.selector))
        );
        sourceLockerFactory.setDestinationMinterFactory(address(0));

        // Calling deploy when sourceLockerFactory does not have enough Link.
        deal(address(LINK), address(sourceLockerFactory), 0);
        vm.expectRevert(
            bytes(abi.encodeWithSelector(SourceLockerFactory.SourceLockerFactory___NotEnoughLink.selector))
        );
        sourceLockerFactory.deploy(cellar);
    }

    function testDestinationMinterFactoryRetryCallback() external {
        SourceLocker locker;
        DestinationMinter minter;

        (, address lockerAddress) = sourceLockerFactory.deploy(cellar);

        locker = SourceLocker(lockerAddress);

        // Zero out destination minter facotry Link balance so CCIP call reverts.
        deal(address(LINK), address(destinationMinterFactory), 0);

        // Simulate CCIP Message to destination factory.
        Client.Any2EVMMessage memory message = router.getLastMessage();
        vm.prank(address(router));
        destinationMinterFactory.ccipReceive(message);

        address expectedMinterAddress = 0x5B0091f49210e7B2A57B03dfE1AB9D08289d9294;

        bytes32 messageDataHash = keccak256(abi.encode(address(locker), expectedMinterAddress));
        assertTrue(
            destinationMinterFactory.canRetryFailedMessage(messageDataHash),
            "Should have updated mapping to true."
        );

        // Try retrying callback without sending link to factory.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(DestinationMinterFactory.DestinationMinterFactory___NotEnoughLink.selector))
        );
        destinationMinterFactory.retryCallback(address(locker), expectedMinterAddress);

        // Callback failed, send destination minter link, and retry.
        deal(address(LINK), address(destinationMinterFactory), 1e18);

        destinationMinterFactory.retryCallback(address(locker), expectedMinterAddress);

        // Calling retryCallback again should revert.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(DestinationMinterFactory.DestinationMinterFactory___CanNotRetryCallback.selector)
            )
        );
        destinationMinterFactory.retryCallback(address(locker), expectedMinterAddress);

        assertTrue(
            !destinationMinterFactory.canRetryFailedMessage(messageDataHash),
            "Should have updated mapping to false."
        );

        // Calll can continue as normal.
        // Simulate CCIP message to source factory.
        message = router.getLastMessage();
        vm.prank(address(router));
        sourceLockerFactory.ccipReceive(message);

        minter = DestinationMinter(locker.targetDestination());
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

        uint256 amountToDesintation = 1e18;
        deal(address(cellar), address(this), amountToDesintation);
        cellar.approve(address(locker), amountToDesintation);
        uint256 fee = locker.previewFee(amountToDesintation, address(this));
        LINK.approve(address(locker), fee);

        vm.expectRevert(bytes(abi.encodeWithSelector(SourceLocker.SourceLocker___InvalidTo.selector)));
        locker.bridgeToDestination(amountToDesintation, address(0), fee);

        vm.expectRevert(bytes(abi.encodeWithSelector(SourceLocker.SourceLocker___FeeTooHigh.selector)));
        locker.bridgeToDestination(amountToDesintation, address(this), 0);

        (, address lockerAddress) = sourceLockerFactory.deploy(cellar);

        locker = SourceLocker(lockerAddress);

        cellar.approve(address(lockerAddress), amountToDesintation);

        vm.expectRevert(bytes(abi.encodeWithSelector(SourceLocker.SourceLocker___TargetDestinationNotSet.selector)));
        locker.bridgeToDestination(amountToDesintation, address(this), fee);
    }

    function testDestinationMinterReverts() external {
        (, DestinationMinter minter) = _runDeploy();

        uint256 amountToSource = 10e18;
        deal(address(minter), address(this), 10e18);
        uint256 fee = minter.previewFee(amountToSource, address(this));
        LINK.approve(address(minter), 1e18);

        vm.expectRevert(bytes(abi.encodeWithSelector(DestinationMinter.DestinationMinter___InvalidTo.selector)));
        minter.bridgeToSource(amountToSource, address(0), fee);

        vm.expectRevert(bytes(abi.encodeWithSelector(DestinationMinter.DestinationMinter___FeeTooHigh.selector)));
        minter.bridgeToSource(amountToSource, address(this), 0);

        // Try bridging more than we have.
        vm.expectRevert(stdError.arithmeticError);
        minter.bridgeToSource(amountToSource + 1, address(this), fee);
    }

    function _runDeploy() internal returns (SourceLocker locker, DestinationMinter minter) {
        (, address lockerAddress) = sourceLockerFactory.deploy(cellar);

        locker = SourceLocker(lockerAddress);

        // Simulate CCIP Message to destination factory.
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
