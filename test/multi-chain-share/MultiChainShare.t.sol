// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";
import { SourceLockerFactory } from "src/modules/multi-chain-share/SourceLockerFactory.sol";
import { DestinationMinterFactory } from "src/modules/multi-chain-share/DestinationMinterFactory.sol";
import { SourceLocker } from "src/modules/multi-chain-share/SourceLocker.sol";
import { DestinationMinter } from "src/modules/multi-chain-share/DestinationMinter.sol";

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

    function testCreation() external {
        (, address lockerAddress) = sourceLockerFactory.deploy(cellar);

        SourceLocker locker = SourceLocker(lockerAddress);

        // Simulate CCIP Message.
        Client.Any2EVMMessage memory message = router.getLastMessage();

        vm.prank(address(router));
        destinationMinterFactory.ccipReceive(message);

        message = router.getLastMessage();

        vm.prank(address(router));
        sourceLockerFactory.ccipReceive(message);

        DestinationMinter minter = DestinationMinter(locker.targetDestination());

        // Try bridging shares.
        deal(address(cellar), address(this), 10e18);
        cellar.approve(address(locker), 10e18);
        LINK.approve(address(locker), 1e18);
        locker.bridgeToDestination(10e18, address(this), 1e18);

        message = router.getLastMessage();

        vm.prank(address(router));
        minter.ccipReceive(message);

        assertEq(10e18, minter.balanceOf(address(this)), "Should have minted shares.");
        assertEq(0, cellar.balanceOf(address(this)), "Should have spent Cellar shares.");

        // Try bridging the shares back.
        LINK.approve(address(minter), 1e18);
        minter.bridgeToSource(10e18, address(this), 1e18);

        message = router.getLastMessage();

        vm.prank(address(router));
        locker.ccipReceive(message);

        assertEq(0, minter.balanceOf(address(this)), "Should have burned shares.");
        assertEq(10e18, cellar.balanceOf(address(this)), "Should have sent Cellar shares back to this address.");
    }
}
