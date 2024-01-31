// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { ERC20DebtAdaptor } from "src/mocks/ERC20DebtAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { AtomicQueue, IAtomicSolver } from "src/modules/atomic-queue/AtomicQueue.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract AtomicQueueTest is MainnetStarterTest, AdaptorHelperFunctions, IAtomicSolver {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    Cellar private cellar;
    AtomicQueue private queue;

    uint32 public usdcPosition = 1;

    bool public solverIsCheapskate;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        queue = new AtomicQueue();

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));

        string memory cellarName = "Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(USDC), address(this), initialDeposit);
        USDC.approve(cellarAddress, initialDeposit);

        bytes memory creationCode = type(Cellar).creationCode;
        bytes memory constructorArgs = abi.encode(
            address(this),
            registry,
            USDC,
            cellarName,
            cellarName,
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        cellar = Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));
    }

    function testQueueForWithdraws(uint8 numberOfUsers, uint256 baseAssets, uint256 atomicPrice) external {
        numberOfUsers = uint8(bound(numberOfUsers, 1, 100));
        baseAssets = bound(baseAssets, 1e6, 1_000_000e6);
        atomicPrice = bound(atomicPrice, 1, 1e6);
        address[] memory users = new address[](numberOfUsers);
        uint256[] memory offerAmount = new uint256[](numberOfUsers);
        for (uint256 i; i < numberOfUsers; ++i) {
            users[i] = vm.addr(i + 1);
            offerAmount[i] = baseAssets * (i + 1);
            deal(address(USDC), users[i], offerAmount[i]);
            vm.startPrank(users[i]);
            USDC.approve(address(cellar), offerAmount[i]);
            uint256 shares = cellar.deposit(offerAmount[i], users[i]);
            offerAmount[i] = shares;
            cellar.approve(address(queue), offerAmount[i]);

            AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
                deadline: uint64(block.timestamp + 100),
                inSolve: false,
                atomicPrice: uint88(atomicPrice),
                offerAmount: uint96(offerAmount[i])
            });

            queue.updateAtomicRequest(cellar, USDC, req);
            vm.stopPrank();
        }

        bytes memory callData = abi.encode(0);
        queue.solve(cellar, USDC, users, callData, address(this));

        for (uint256 i; i < numberOfUsers; ++i) {
            uint256 expectedBalance = offerAmount[i].mulDivDown(atomicPrice, 1e6);
            assertEq(USDC.balanceOf(users[i]), expectedBalance, "User received wrong amount of assets.");
        }
    }

    function testQueueForDeposits(uint8 numberOfUsers, uint256 baseAssets, uint256 atomicPrice) external {
        numberOfUsers = uint8(bound(numberOfUsers, 1, 100));
        baseAssets = bound(baseAssets, 1e6, 1_000_000e6);
        atomicPrice = bound(atomicPrice, 1, 1e6);
        address[] memory users = new address[](numberOfUsers);
        uint256[] memory offerAmount = new uint256[](numberOfUsers);
        for (uint256 i; i < numberOfUsers; ++i) {
            users[i] = vm.addr(i + 1);
            offerAmount[i] = baseAssets * (i + 1);
            deal(address(USDT), users[i], offerAmount[i]);
            vm.startPrank(users[i]);
            USDT.safeApprove(address(queue), offerAmount[i]);

            AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
                deadline: uint64(block.timestamp + 100),
                inSolve: false,
                atomicPrice: uint88(atomicPrice),
                offerAmount: uint96(offerAmount[i])
            });

            queue.updateAtomicRequest(USDT, cellar, req);
            vm.stopPrank();
        }

        bytes memory callData = abi.encode(1);
        queue.solve(USDT, cellar, users, callData, address(this));

        for (uint256 i; i < numberOfUsers; ++i) {
            uint256 expectedBalance = offerAmount[i].mulDivDown(atomicPrice, 1e6);
            assertEq(cellar.balanceOf(users[i]), expectedBalance, "User received wrong amount of assets.");
        }
    }

    function testSolverShareSpendingCappedByRequestAmount(uint256 assets, uint256 sharesToRedeem) external {
        assets = bound(assets, 1.000001e6, 1_000_000e6);
        sharesToRedeem = bound(sharesToRedeem, 1e6, assets - 1);
        address user = vm.addr(77);

        AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 100),
            inSolve: false,
            atomicPrice: 1e6,
            offerAmount: uint96(sharesToRedeem)
        });

        deal(address(USDC), user, assets);
        vm.startPrank(user);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, user);
        cellar.approve(address(queue), assets);
        queue.updateAtomicRequest(cellar, USDC, req);
        vm.stopPrank();

        // Solver sovles initial request.
        address[] memory users = new address[](1);
        users[0] = user;
        bytes memory callData = abi.encode(0);
        queue.solve(cellar, USDC, users, callData, address(this));

        uint256 remainingApproval = cellar.allowance(user, address(queue));
        assertGt(remainingApproval, 0, "Queue should still have some approval.");

        // Solver tries to use remaining approval.
        vm.expectRevert(bytes(abi.encodeWithSelector(AtomicQueue.AtomicQueue__ZeroOfferAmount.selector, user)));
        queue.solve(cellar, USDC, users, callData, address(this));
    }

    function testSolverIsCheapSkate() external {
        address userA = vm.addr(1);
        address userB = vm.addr(2);
        address userC = vm.addr(3);
        uint256 assetsA = 1e6;
        uint256 assetsB = 1e6;
        uint256 assetsC = 1e6;
        deal(address(cellar), userA, assetsA);
        deal(address(cellar), userB, assetsB);
        deal(address(cellar), userC, assetsC);

        {
            vm.startPrank(userA);
            AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
                deadline: uint64(block.timestamp + 100),
                inSolve: false,
                atomicPrice: 1e6,
                offerAmount: uint96(assetsA)
            });
            cellar.approve(address(queue), assetsA);
            queue.updateAtomicRequest(cellar, USDC, req);
            vm.stopPrank();
        }
        {
            vm.startPrank(userB);
            AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
                deadline: uint64(block.timestamp + 100),
                inSolve: false,
                atomicPrice: 1e6,
                offerAmount: uint96(assetsB)
            });
            cellar.approve(address(queue), assetsB);
            queue.updateAtomicRequest(cellar, USDC, req);
            vm.stopPrank();
        }
        {
            vm.startPrank(userC);
            AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
                deadline: uint64(block.timestamp + 100),
                inSolve: false,
                atomicPrice: 1e6,
                offerAmount: uint96(assetsC)
            });
            cellar.approve(address(queue), assetsC);
            queue.updateAtomicRequest(cellar, USDC, req);
            vm.stopPrank();
        }

        solverIsCheapskate = true;

        address[] memory users = new address[](3);
        users[0] = userA;
        users[1] = userB;
        users[2] = userC;
        bytes memory callData = abi.encode(0);

        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        queue.solve(cellar, USDC, users, callData, address(this));

        // But if solver is not a cheapskate.
        solverIsCheapskate = false;

        // Solve is successful.
        queue.solve(cellar, USDC, users, callData, address(this));
    }

    function testSolverReverts(uint256 sharesToWithdraw) external {
        sharesToWithdraw = bound(sharesToWithdraw, 1e6, type(uint96).max);
        // user A wants to withdraw `sharesToWithdraw` but then changes their mind to only withdraw half.
        // NOTE shares and assets are 1:1.

        address userA = vm.addr(0xA);
        address userB = vm.addr(0xB);
        address userC = vm.addr(0xC);

        // Give both users enough USDC to cover their actions.
        deal(address(USDC), userA, sharesToWithdraw);
        deal(address(USDC), userB, sharesToWithdraw);
        deal(address(USDC), userC, sharesToWithdraw);

        // user A deposits into cellar, and joins queue.
        vm.startPrank(userA);
        USDC.approve(address(cellar), sharesToWithdraw);
        cellar.mint(sharesToWithdraw, userA);
        cellar.approve(address(queue), sharesToWithdraw);
        AtomicQueue.AtomicRequest memory reqA = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 100),
            inSolve: false,
            atomicPrice: 1e6,
            offerAmount: uint96(sharesToWithdraw)
        });
        queue.updateAtomicRequest(cellar, USDC, reqA);
        vm.stopPrank();

        // user B deposits into cellar, and joins queue.
        vm.startPrank(userB);
        USDC.approve(address(cellar), sharesToWithdraw);
        cellar.mint(sharesToWithdraw, userB);
        cellar.approve(address(queue), sharesToWithdraw);
        AtomicQueue.AtomicRequest memory reqB = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 50),
            inSolve: false,
            atomicPrice: 1e6,
            offerAmount: uint96(sharesToWithdraw)
        });
        queue.updateAtomicRequest(cellar, USDC, reqB);
        vm.stopPrank();

        // user C deposits into cellar, and joins queue.
        vm.startPrank(userC);
        USDC.approve(address(cellar), sharesToWithdraw);
        cellar.mint(sharesToWithdraw, userC);
        cellar.approve(address(queue), sharesToWithdraw);
        AtomicQueue.AtomicRequest memory reqC = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 100),
            inSolve: false,
            atomicPrice: 1e6,
            offerAmount: 0
        });
        queue.updateAtomicRequest(cellar, USDC, reqC);
        vm.stopPrank();

        address[] memory users = new address[](3);
        users[0] = userA;
        users[1] = userA;
        users[2] = userC;
        bytes memory callData = abi.encode(0);

        // Solve is not successful.
        vm.expectRevert(bytes(abi.encodeWithSelector(AtomicQueue.AtomicQueue__UserRepeated.selector, userA)));
        queue.solve(cellar, USDC, users, callData, address(this));

        users[1] = userB;

        // Time passes, so userBs deadline is passed.
        skip(51);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(AtomicQueue.AtomicQueue__RequestDeadlineExceeded.selector, userB))
        );
        queue.solve(cellar, USDC, users, callData, address(this));

        // User B updates their deadline
        reqB.deadline = uint64(block.timestamp + 100);
        vm.prank(userB);
        queue.updateAtomicRequest(cellar, USDC, reqB);

        vm.expectRevert(bytes(abi.encodeWithSelector(AtomicQueue.AtomicQueue__ZeroOfferAmount.selector, userC)));
        queue.solve(cellar, USDC, users, callData, address(this));

        // User C updates the amount, so solve can be successful.
        reqC.offerAmount = uint96(sharesToWithdraw);
        vm.prank(userC);
        queue.updateAtomicRequest(cellar, USDC, reqC);

        // Solver tries to give user A an asset they don't want.
        // We first error because the user never set a deadline for a USDT want.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(AtomicQueue.AtomicQueue__RequestDeadlineExceeded.selector, userA))
        );
        queue.solve(cellar, USDT, users, callData, address(this));

        // But even if they set a deadline in the past, we still revert from a zero offer amount.
        reqA.deadline = type(uint64).max;
        reqA.offerAmount = 0;
        vm.prank(userA);
        queue.updateAtomicRequest(cellar, USDT, reqA);

        vm.expectRevert(bytes(abi.encodeWithSelector(AtomicQueue.AtomicQueue__ZeroOfferAmount.selector, userA)));
        queue.solve(cellar, USDT, users, callData, address(this));

        // But solve is successful if proper want asset is given.
        queue.solve(cellar, USDC, users, callData, address(this));

        // Solver tries to solve using a zero address.
        users = new address[](1);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(AtomicQueue.AtomicQueue__RequestDeadlineExceeded.selector, address(0)))
        );
        queue.solve(cellar, USDC, users, callData, address(this));
    }

    function testUserRequestWithInSolveTrue() external {
        AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 100),
            inSolve: true,
            atomicPrice: 1e6,
            offerAmount: 1
        });

        queue.updateAtomicRequest(cellar, USDC, req);

        AtomicQueue.AtomicRequest memory savedReq = queue.getUserAtomicRequest(address(this), cellar, USDC);

        assertTrue(savedReq.inSolve == false, "inSolve should be false");
    }

    function testUserUpdatingWithdrawRequest(uint256 sharesToWithdraw) external {
        sharesToWithdraw = bound(sharesToWithdraw, 1e6, type(uint96).max);
        // user A wants to withdraw `sharesToWithdraw` but then changes their mind to only withdraw half.
        // NOTE shares and assets are 1:1.

        address userA = vm.addr(0xA);

        // Give both users enough USDC to cover their actions.
        deal(address(USDC), userA, sharesToWithdraw);

        // user A deposits into cellar, and joins queue.
        vm.startPrank(userA);
        USDC.approve(address(cellar), sharesToWithdraw);
        cellar.mint(sharesToWithdraw, userA);
        cellar.approve(address(queue), sharesToWithdraw);
        AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 100),
            inSolve: false,
            atomicPrice: 1e6,
            offerAmount: uint96(sharesToWithdraw)
        });
        queue.updateAtomicRequest(cellar, USDC, req);
        vm.stopPrank();

        // User changes their mind.
        req.offerAmount /= 2;
        vm.prank(userA);
        queue.updateAtomicRequest(cellar, USDC, req);

        // Solver solves for user A.
        address[] memory users = new address[](1);
        users[0] = userA;
        bytes memory callData = abi.encode(0);

        // Solve is successful.
        queue.solve(cellar, USDC, users, callData, address(this));

        assertApproxEqAbs(
            cellar.balanceOf(userA),
            sharesToWithdraw / 2,
            1,
            "User A should still have half of their shares."
        );

        // Trying to solve again reverts.
        vm.expectRevert(bytes(abi.encodeWithSelector(AtomicQueue.AtomicQueue__ZeroOfferAmount.selector, userA)));
        queue.solve(cellar, USDC, users, callData, address(this));
    }

    function testIsAtomicRequestValid() external {
        uint256 sharesToWithdraw = 100e6;
        address userA = vm.addr(0xA);

        AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp - 1),
            inSolve: false,
            atomicPrice: 0,
            offerAmount: uint96(sharesToWithdraw)
        });
        queue.updateAtomicRequest(cellar, USDC, req);
        assertTrue(
            !queue.isAtomicRequestValid(cellar, userA, req),
            "Request should not be valid because user has no shares."
        );

        // Give both users enough USDC to cover their actions.
        deal(address(USDC), userA, sharesToWithdraw);

        vm.startPrank(userA);
        USDC.approve(address(cellar), sharesToWithdraw);
        cellar.mint(sharesToWithdraw, userA);
        vm.stopPrank();
        assertTrue(
            !queue.isAtomicRequestValid(cellar, userA, req),
            "Request should not be valid because deadline is bad."
        );

        req.deadline = uint64(block.timestamp + 100);
        queue.updateAtomicRequest(cellar, USDC, req);
        assertTrue(
            !queue.isAtomicRequestValid(cellar, userA, req),
            "Request should not be valid because user has not given queue approval."
        );

        vm.startPrank(userA);
        cellar.approve(address(queue), sharesToWithdraw);
        vm.stopPrank();

        // Change sharesToWithdraw to 0.
        req.offerAmount = 0;
        queue.updateAtomicRequest(cellar, USDC, req);
        assertTrue(
            !queue.isAtomicRequestValid(cellar, userA, req),
            "Request should not be valid because shares to withdraw is zero."
        );

        req.offerAmount = uint96(sharesToWithdraw);
        queue.updateAtomicRequest(cellar, USDC, req);
        assertTrue(
            !queue.isAtomicRequestValid(cellar, userA, req),
            "Request should not be valid because execution share price is zero."
        );

        req.atomicPrice = 1e6;
        queue.updateAtomicRequest(cellar, USDC, req);

        assertTrue(queue.isAtomicRequestValid(cellar, userA, req), "Request should be valid.");
    }

    function _validateViewSolveMetaData(
        ERC20 offer,
        ERC20 want,
        address[] memory users,
        uint8[] memory expectedFlags,
        uint256[] memory expectedSharesToSolve,
        uint256[] memory expectedRequiredAssets
    ) internal {
        (AtomicQueue.SolveMetaData[] memory metaData, uint256 totalAssets, uint256 totalShares) = queue
            .viewSolveMetaData(offer, want, users);

        for (uint256 i; i < metaData.length; ++i) {
            assertEq(expectedSharesToSolve[i], metaData[i].assetsToOffer, "assetsToOffer does not equal expected.");
            assertEq(expectedRequiredAssets[i], metaData[i].assetsForWant, "assetsForWant does not equal expected.");
            assertEq(expectedFlags[i], metaData[i].flags, "flags does not equal expected.");
            if (metaData[i].flags == 0) {
                assertEq(totalAssets, metaData[i].assetsForWant, "Total Assets should be greater than zero.");
                assertEq(totalShares, metaData[i].assetsToOffer, "Total Shares should be greater than zero.");
            } else {
                assertEq(totalAssets, 0, "Total Assets should be zero.");
                assertEq(totalShares, 0, "Total Shares should be zero.");
            }
        }
    }

    function testViewSolveMetaData() external {
        uint256 sharesToWithdraw = 100e6;
        address userA = vm.addr(0xA);
        address[] memory users = new address[](1);
        uint8[] memory expectedFlags = new uint8[](1);
        uint256[] memory expectedSharesToSolve = new uint256[](1);
        uint256[] memory expectedRequiredAssets = new uint256[](1);
        users[0] = userA;

        vm.startPrank(userA);

        AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp - 1),
            inSolve: false,
            atomicPrice: 1e6,
            offerAmount: 0
        });
        queue.updateAtomicRequest(cellar, USDC, req);
        expectedFlags[0] = uint8(3); // Flags = 00000011
        _validateViewSolveMetaData(cellar, USDC, users, expectedFlags, expectedSharesToSolve, expectedRequiredAssets);

        req.deadline = uint64(block.timestamp + 1);
        queue.updateAtomicRequest(cellar, USDC, req);
        expectedFlags[0] = uint8(2); // Flags = 00000010
        _validateViewSolveMetaData(cellar, USDC, users, expectedFlags, expectedSharesToSolve, expectedRequiredAssets);

        req.offerAmount = uint96(sharesToWithdraw);
        expectedSharesToSolve[0] = sharesToWithdraw;
        expectedRequiredAssets[0] = sharesToWithdraw.mulDivDown(req.atomicPrice, 1e6);
        queue.updateAtomicRequest(cellar, USDC, req);
        expectedFlags[0] = uint8(12); // Flags = 00001100
        _validateViewSolveMetaData(cellar, USDC, users, expectedFlags, expectedSharesToSolve, expectedRequiredAssets);

        // Give user enough USDC to cover their actions.
        deal(address(USDC), userA, sharesToWithdraw);

        USDC.approve(address(cellar), sharesToWithdraw);
        cellar.mint(sharesToWithdraw, userA);
        expectedFlags[0] = uint8(8); // Flags = 00001000
        _validateViewSolveMetaData(cellar, USDC, users, expectedFlags, expectedSharesToSolve, expectedRequiredAssets);

        cellar.approve(address(queue), sharesToWithdraw);
        expectedFlags[0] = 0; // Flags = 00000000
        _validateViewSolveMetaData(cellar, USDC, users, expectedFlags, expectedSharesToSolve, expectedRequiredAssets);

        vm.stopPrank();
    }

    // -------------------------------- IAtomicSolver Implementation --------------------------------------

    function finishSolve(
        bytes calldata runData,
        address,
        ERC20 offer,
        ERC20 want,
        uint256 assetsToOffer,
        uint256 assetsForWant
    ) external {
        uint256 option = abi.decode(runData, (uint256));

        if (option == 0) {
            _dealSolve(offer, want, assetsToOffer, assetsForWant);
        }
        if (option == 1) {
            _dealSwapAndDeposit(offer, want, assetsToOffer, assetsForWant);
        }

        if (solverIsCheapskate) {
            // Malicious solver only approves half the amount needed.
            assetsForWant /= 2;
        }
        want.safeApprove(address(queue), assetsForWant);
    }

    // function finishSolve(bytes calldata runData, address initiator, uint256, uint256 assetApprovalAmount) external {
    //     assertEq(initiator, address(this), "Initiator should be address(this)");
    //     if (solverIsCheapskate) {
    //         // Malicious solver only approves half the amount needed.
    //         assetApprovalAmount /= 2;
    //     }
    //     (, ERC20 shareAsset) = abi.decode(runData, (ERC4626, ERC20));
    //     deal(address(shareAsset), address(this), assetApprovalAmount);
    //     shareAsset.approve(msg.sender, assetApprovalAmount);
    // }

    function _dealSolve(ERC20, ERC20 want, uint256, uint256 assetsForWant) internal {
        deal(address(want), address(this), assetsForWant);
    }

    function _dealSwapAndDeposit(ERC20 offer, ERC20 want, uint256, uint256 assetsForWant) internal {
        // Figure out how much of vault base asset we need to deposit.
        ERC4626 vault = ERC4626(address(want));
        uint256 assetsForDeposit = vault.previewMint(assetsForWant);

        ERC20 vaultBaseAsset = vault.asset();

        // Simulate a swap between offer, and vault base asset.
        deal(address(offer), address(this), 0);
        deal(address(vaultBaseAsset), address(this), assetsForDeposit);

        // Mint the vault shares.
        vaultBaseAsset.safeApprove(address(vault), assetsForDeposit);
        vault.mint(assetsForWant, address(this));
    }
}
