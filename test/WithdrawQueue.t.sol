// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ReentrancyERC4626 } from "src/mocks/ReentrancyERC4626.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { ERC20DebtAdaptor } from "src/mocks/ERC20DebtAdaptor.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";
import { WithdrawQueue, ISolver } from "src/modules/withdraw-queue/WithdrawQueue.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract WithdrawQueueTest is MainnetStarterTest, AdaptorHelperFunctions, ISolver {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    Cellar private cellar;
    WithdrawQueue private queue;

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
            abi.encode(0),
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
        vm.expectRevert(bytes(abi.encodeWithSelector(WithdrawQueue.WithdrawQueue__NoShares.selector)));
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

    // TODO tests for malicious solvers that repeat users, or try to add a user who is not in there,
    // basically check for all reverts in solve.
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

    // TODO test showing how user originally wants 100 shares withdrawn, then changes it to 50, make sure only 50 can be withdrawn.

    function finishSolve(bytes calldata runData, uint256, uint256 assetApprovalAmount) external {
        if (solverIsCheapskate) {
            // Malicious solver only approves half the amount needed.
            assetApprovalAmount /= 2;
        }
        (, ERC20 asset) = abi.decode(runData, (ERC4626, ERC20));
        deal(address(asset), address(this), assetApprovalAmount);
        asset.approve(msg.sender, assetApprovalAmount);
    }
}
