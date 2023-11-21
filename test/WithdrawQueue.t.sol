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

    address public user = vm.addr(34);

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        queue = new WithdrawQueue(0.1e6);

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

        uint256 assets = 1_000e6;
        deal(address(USDC), user, assets);

        vm.startPrank(user);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, user);
        cellar.approve(address(queue), 1_000e6);
        vm.stopPrank();

        queue.addNewShare(cellar, 0.001e6);
    }

    function testQueue(uint8 numberOfUsers, uint256 baseAssets) external {
        numberOfUsers = uint8(bound(numberOfUsers, 1, 100));
        baseAssets = bound(baseAssets, 1e6, 1_000_000e6);
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
            vm.stopPrank();
        }
    }

    function testHunch() external {
        WithdrawQueue.WithdrawRequest memory req = WithdrawQueue.WithdrawRequest({
            deadline: uint64(block.timestamp + 100),
            maximumFee: 0.05e6,
            inSolve: false,
            minimumSharePrice: 0,
            sharesToWithdraw: 1_000e6
        });
        vm.prank(user);
        queue.updateWithdrawRequest(cellar, req);

        bytes memory callData = abi.encode(cellar, USDC);
        address[] memory users = new address[](1);
        users[0] = user;
        queue.solve(cellar, users, callData);

        console.log("User USDC Balance", USDC.balanceOf(user));
    }

    // TODO test showing how solvers can only spend up to `sharesToWithdraw` even if the approval is for more
    // TODO tests for malicious solvers that repeat users, or try to add a user who is not in there,
    // basically check for all reverts in solve.
    // TODO if user passes in a true for inSolve when setting up the request it should not write it.

    function finishSolve(bytes calldata runData, uint256 sharesReceived, uint256 assetApprovalAmount) external {
        (ERC4626 share, ERC20 asset) = abi.decode(runData, (ERC4626, ERC20));
        deal(address(asset), address(this), assetApprovalAmount);
        asset.approve(msg.sender, assetApprovalAmount);
    }
}
