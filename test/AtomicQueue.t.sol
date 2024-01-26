// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { ERC20DebtAdaptor } from "src/mocks/ERC20DebtAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { AtomicQueue, IAtomicSolver } from "src/modules/atomic-queue/AtomicQueue.sol";
import { SimpleSolver } from "src/modules/atomic-queue/SimpleSolver.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract AtomicQueueTest is MainnetStarterTest, AdaptorHelperFunctions, ISolver, ERC20 {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    Cellar private cellar;
    WithdrawQueue private queue;
    SimpleSolver private simpleSolver;

    uint32 public usdcPosition = 1;

    bool public solverIsCheapskate;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        queue = new WithdrawQueue();
        simpleSolver = new SimpleSolver(address(queue));

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

    function testQueue(uint8 numberOfUsers, uint256 baseAssets, uint256 executionPrice) external {
        numberOfUsers = uint8(bound(numberOfUsers, 1, 100));
        baseAssets = bound(baseAssets, 1e6, 1_000_000e6);
        executionPrice = bound(executionPrice, 1, 1e6);
        address[] memory users = new address[](numberOfUsers);
        uint256[] memory amountOfShares = new uint256[](numberOfUsers);
        for (uint256 i; i < numberOfUsers; ++i) {
            users[i] = vm.addr(i + 1);
            amountOfShares[i] = baseAssets * (i + 1);
            deal(address(USDC), users[i], amountOfShares[i]);
            vm.startPrank(users[i]);
            USDC.approve(address(cellar), amountOfShares[i]);
            uint256 shares = cellar.deposit(amountOfShares[i], users[i]);
            amountOfShares[i] = shares;
            cellar.approve(address(queue), amountOfShares[i]);

            WithdrawQueue.WithdrawRequest memory req = WithdrawQueue.WithdrawRequest({
                deadline: uint64(block.timestamp + 100),
                inSolve: false,
                executionSharePrice: uint88(executionPrice),
                sharesToWithdraw: uint96(amountOfShares[i])
            });

            queue.updateWithdrawRequest(cellar, req);
            vm.stopPrank();
        }

        bytes memory callData = abi.encode(cellar, USDC);
        queue.solve(cellar, users, callData, address(this));

        for (uint256 i; i < numberOfUsers; ++i) {
            uint256 expectedBalance = amountOfShares[i].mulDivDown(executionPrice, 1e6);
            assertEq(USDC.balanceOf(users[i]), expectedBalance, "User received wrong amount of assets.");
        }
    }

    function testSolverShareSpendingCappedByRequestAmount(uint256 assets, uint256 sharesToRedeem) external {
        assets = bound(assets, 1.000001e6, 1_000_000e6);
        sharesToRedeem = bound(sharesToRedeem, 1e6, assets - 1);
        address user = vm.addr(77);

        WithdrawQueue.WithdrawRequest memory req = WithdrawQueue.WithdrawRequest({
            deadline: uint64(block.timestamp + 100),
            inSolve: false,
            executionSharePrice: 1e6,
            sharesToWithdraw: uint96(sharesToRedeem)
        });

        deal(address(USDC), user, assets);
        vm.startPrank(user);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, user);
        cellar.approve(address(queue), assets);
        queue.updateWithdrawRequest(cellar, req);
        vm.stopPrank();

        // Solver sovles initial request.
        address[] memory users = new address[](1);
        users[0] = user;
        bytes memory callData = abi.encode(cellar, USDC);
        queue.solve(cellar, users, callData, address(this));

        uint256 remainingApproval = cellar.allowance(user, address(queue));
        assertGt(remainingApproval, 0, "Queue should still have some approval.");

        // Solver tries to use remaining approval.
        vm.expectRevert(bytes(abi.encodeWithSelector(WithdrawQueue.WithdrawQueue__NoShares.selector, user)));
        queue.solve(cellar, users, callData, address(this));
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
            WithdrawQueue.WithdrawRequest memory req = WithdrawQueue.WithdrawRequest({
                deadline: uint64(block.timestamp + 100),
                inSolve: false,
                executionSharePrice: 1e6,
                sharesToWithdraw: uint96(assetsA)
            });
            cellar.approve(address(queue), assetsA);
            queue.updateWithdrawRequest(cellar, req);
            vm.stopPrank();
        }
        {
            vm.startPrank(userB);
            WithdrawQueue.WithdrawRequest memory req = WithdrawQueue.WithdrawRequest({
                deadline: uint64(block.timestamp + 100),
                inSolve: false,
                executionSharePrice: 1e6,
                sharesToWithdraw: uint96(assetsB)
            });
            cellar.approve(address(queue), assetsB);
            queue.updateWithdrawRequest(cellar, req);
            vm.stopPrank();
        }
        {
            vm.startPrank(userC);
            WithdrawQueue.WithdrawRequest memory req = WithdrawQueue.WithdrawRequest({
                deadline: uint64(block.timestamp + 100),
                inSolve: false,
                executionSharePrice: 1e6,
                sharesToWithdraw: uint96(assetsC)
            });
            cellar.approve(address(queue), assetsC);
            queue.updateWithdrawRequest(cellar, req);
            vm.stopPrank();
        }

        solverIsCheapskate = true;

        address[] memory users = new address[](3);
        users[0] = userA;
        users[1] = userB;
        users[2] = userC;
        bytes memory callData = abi.encode(cellar, USDC);

        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        queue.solve(cellar, users, callData, address(this));

        // But if solver is not a cheapskate.
        solverIsCheapskate = false;

        // Solve is successful.
        queue.solve(cellar, users, callData, address(this));
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
        WithdrawQueue.WithdrawRequest memory reqA = WithdrawQueue.WithdrawRequest({
            deadline: uint64(block.timestamp + 100),
            inSolve: false,
            executionSharePrice: 1e6,
            sharesToWithdraw: uint96(sharesToWithdraw)
        });
        queue.updateWithdrawRequest(cellar, reqA);
        vm.stopPrank();

        // user B deposits into cellar, and joins queue.
        vm.startPrank(userB);
        USDC.approve(address(cellar), sharesToWithdraw);
        cellar.mint(sharesToWithdraw, userB);
        cellar.approve(address(queue), sharesToWithdraw);
        WithdrawQueue.WithdrawRequest memory reqB = WithdrawQueue.WithdrawRequest({
            deadline: uint64(block.timestamp + 50),
            inSolve: false,
            executionSharePrice: 1e6,
            sharesToWithdraw: uint96(sharesToWithdraw)
        });
        queue.updateWithdrawRequest(cellar, reqB);
        vm.stopPrank();

        // user C deposits into cellar, and joins queue.
        vm.startPrank(userC);
        USDC.approve(address(cellar), sharesToWithdraw);
        cellar.mint(sharesToWithdraw, userC);
        cellar.approve(address(queue), sharesToWithdraw);
        WithdrawQueue.WithdrawRequest memory reqC = WithdrawQueue.WithdrawRequest({
            deadline: uint64(block.timestamp + 100),
            inSolve: false,
            executionSharePrice: 1e6,
            sharesToWithdraw: 0
        });
        queue.updateWithdrawRequest(cellar, reqC);
        vm.stopPrank();

        address[] memory users = new address[](3);
        users[0] = userA;
        users[1] = userA;
        users[2] = userC;
        bytes memory callData = abi.encode(cellar, USDC);

        // Solve is not successful.
        vm.expectRevert(bytes(abi.encodeWithSelector(WithdrawQueue.WithdrawQueue__UserRepeated.selector, userA)));
        queue.solve(cellar, users, callData, address(this));

        users[1] = userB;

        // Time passes, so userBs deadline is passed.
        skip(51);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(WithdrawQueue.WithdrawQueue__RequestDeadlineExceeded.selector, userB))
        );
        queue.solve(cellar, users, callData, address(this));

        // User B updates their deadline
        reqB.deadline = uint64(block.timestamp + 100);
        vm.prank(userB);
        queue.updateWithdrawRequest(cellar, reqB);

        vm.expectRevert(bytes(abi.encodeWithSelector(WithdrawQueue.WithdrawQueue__NoShares.selector, userC)));
        queue.solve(cellar, users, callData, address(this));

        // User C updates the amount, so solve is successful.
        reqC.sharesToWithdraw = uint96(sharesToWithdraw);
        vm.prank(userC);
        queue.updateWithdrawRequest(cellar, reqC);

        queue.solve(cellar, users, callData, address(this));

        // Solver tries to solve using a zero address.
        users = new address[](1);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(WithdrawQueue.WithdrawQueue__RequestDeadlineExceeded.selector, address(0)))
        );
        queue.solve(cellar, users, callData, address(this));
    }

    function testUserRequestWithInSolveTrue() external {
        WithdrawQueue.WithdrawRequest memory req = WithdrawQueue.WithdrawRequest({
            deadline: uint64(block.timestamp + 100),
            inSolve: true,
            executionSharePrice: 1e6,
            sharesToWithdraw: 1
        });

        queue.updateWithdrawRequest(cellar, req);

        WithdrawQueue.WithdrawRequest memory savedReq = queue.getUserWithdrawRequest(address(this), cellar);

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
        WithdrawQueue.WithdrawRequest memory req = WithdrawQueue.WithdrawRequest({
            deadline: uint64(block.timestamp + 100),
            inSolve: false,
            executionSharePrice: 1e6,
            sharesToWithdraw: uint96(sharesToWithdraw)
        });
        queue.updateWithdrawRequest(cellar, req);
        vm.stopPrank();

        // User changes their mind.
        req.sharesToWithdraw /= 2;
        vm.prank(userA);
        queue.updateWithdrawRequest(cellar, req);

        // Solver solves for user A.
        address[] memory users = new address[](1);
        users[0] = userA;
        bytes memory callData = abi.encode(cellar, USDC);

        // Solve is successful.
        queue.solve(cellar, users, callData, address(this));

        assertApproxEqAbs(
            cellar.balanceOf(userA),
            sharesToWithdraw / 2,
            1,
            "User A should still have half of their shares."
        );

        // Trying to solve again reverts.
        vm.expectRevert(bytes(abi.encodeWithSelector(WithdrawQueue.WithdrawQueue__NoShares.selector, userA)));
        queue.solve(cellar, users, callData, address(this));
    }

    function testIsWithdrawRequestValid() external {
        uint256 sharesToWithdraw = 100e6;
        address userA = vm.addr(0xA);

        WithdrawQueue.WithdrawRequest memory req = WithdrawQueue.WithdrawRequest({
            deadline: uint64(block.timestamp - 1),
            inSolve: false,
            executionSharePrice: 0,
            sharesToWithdraw: uint96(sharesToWithdraw)
        });
        queue.updateWithdrawRequest(cellar, req);
        assertTrue(
            !queue.isWithdrawRequestValid(cellar, userA, req),
            "Request should not be valid because user has no shares."
        );

        // Give both users enough USDC to cover their actions.
        deal(address(USDC), userA, sharesToWithdraw);

        vm.startPrank(userA);
        USDC.approve(address(cellar), sharesToWithdraw);
        cellar.mint(sharesToWithdraw, userA);
        vm.stopPrank();
        assertTrue(
            !queue.isWithdrawRequestValid(cellar, userA, req),
            "Request should not be valid because deadline is bad."
        );

        req.deadline = uint64(block.timestamp + 100);
        queue.updateWithdrawRequest(cellar, req);
        assertTrue(
            !queue.isWithdrawRequestValid(cellar, userA, req),
            "Request should not be valid because user has not given queue approval."
        );

        vm.startPrank(userA);
        cellar.approve(address(queue), sharesToWithdraw);
        vm.stopPrank();

        // Change sharesToWithdraw to 0.
        req.sharesToWithdraw = 0;
        queue.updateWithdrawRequest(cellar, req);
        assertTrue(
            !queue.isWithdrawRequestValid(cellar, userA, req),
            "Request should not be valid because shares to withdraw is zero."
        );

        req.sharesToWithdraw = uint96(sharesToWithdraw);
        queue.updateWithdrawRequest(cellar, req);
        assertTrue(
            !queue.isWithdrawRequestValid(cellar, userA, req),
            "Request should not be valid because execution share price is zero."
        );

        req.executionSharePrice = 1e6;
        queue.updateWithdrawRequest(cellar, req);

        assertTrue(queue.isWithdrawRequestValid(cellar, userA, req), "Request should be valid.");
    }

    function _validateViewSolveMetaData(
        ERC4626 share,
        address[] memory users,
        uint8[] memory expectedFlags,
        uint256[] memory expectedSharesToSolve,
        uint256[] memory expectedRequiredAssets
    ) internal {
        (WithdrawQueue.SolveMetaData[] memory metaData, uint256 totalAssets, uint256 totalShares) = queue
            .viewSolveMetaData(share, users);

        for (uint256 i; i < metaData.length; ++i) {
            assertEq(expectedSharesToSolve[i], metaData[i].sharesToSolve, "sharesToSolve does not equal expected.");
            assertEq(expectedRequiredAssets[i], metaData[i].requiredAssets, "requiredAssets does not equal expected.");
            assertEq(expectedFlags[i], metaData[i].flags, "flags does not equal expected.");
            if (metaData[i].flags == 0) {
                assertEq(totalAssets, metaData[i].requiredAssets, "Total Assets should be greater than zero.");
                assertEq(totalShares, metaData[i].sharesToSolve, "Total Shares should be greater than zero.");
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

        WithdrawQueue.WithdrawRequest memory req = WithdrawQueue.WithdrawRequest({
            deadline: uint64(block.timestamp - 1),
            inSolve: false,
            executionSharePrice: 1e6,
            sharesToWithdraw: 0
        });
        queue.updateWithdrawRequest(cellar, req);
        expectedFlags[0] = uint8(3); // Flags = 00000011
        _validateViewSolveMetaData(cellar, users, expectedFlags, expectedSharesToSolve, expectedRequiredAssets);

        req.deadline = uint64(block.timestamp + 1);
        queue.updateWithdrawRequest(cellar, req);
        expectedFlags[0] = uint8(2); // Flags = 00000010
        _validateViewSolveMetaData(cellar, users, expectedFlags, expectedSharesToSolve, expectedRequiredAssets);

        req.sharesToWithdraw = uint96(sharesToWithdraw);
        expectedSharesToSolve[0] = sharesToWithdraw;
        expectedRequiredAssets[0] = sharesToWithdraw.mulDivDown(req.executionSharePrice, 1e6);
        queue.updateWithdrawRequest(cellar, req);
        expectedFlags[0] = uint8(12); // Flags = 00001100
        _validateViewSolveMetaData(cellar, users, expectedFlags, expectedSharesToSolve, expectedRequiredAssets);

        // Give user enough USDC to cover their actions.
        deal(address(USDC), userA, sharesToWithdraw);

        USDC.approve(address(cellar), sharesToWithdraw);
        cellar.mint(sharesToWithdraw, userA);
        expectedFlags[0] = uint8(8); // Flags = 00001000
        _validateViewSolveMetaData(cellar, users, expectedFlags, expectedSharesToSolve, expectedRequiredAssets);

        cellar.approve(address(queue), sharesToWithdraw);
        expectedFlags[0] = 0; // Flags = 00000000
        _validateViewSolveMetaData(cellar, users, expectedFlags, expectedSharesToSolve, expectedRequiredAssets);

        vm.stopPrank();
    }

    // -------------------------------- ISolver Implementation --------------------------------------

    function finishSolve(bytes calldata runData, address initiator, uint256, uint256 assetApprovalAmount) external {
        assertEq(initiator, address(this), "Initiator should be address(this)");
        if (solverIsCheapskate) {
            // Malicious solver only approves half the amount needed.
            assetApprovalAmount /= 2;
        }
        (, ERC20 shareAsset) = abi.decode(runData, (ERC4626, ERC20));
        deal(address(shareAsset), address(this), assetApprovalAmount);
        shareAsset.approve(msg.sender, assetApprovalAmount);
    }
}
