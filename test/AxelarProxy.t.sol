// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MockAxelarGateway } from "src/mocks/MockAxelarGateway.sol";
import { AxelarProxy } from "src/AxelarProxy.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";

import { IPool } from "src/interfaces/external/IPool.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract AxelarProxyTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    Cellar private cellar;
    MockAxelarGateway private mockGateway;
    AxelarProxy private proxy;
    AaveATokenAdaptor private aaveATokenAdaptor;

    IPool public pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    uint32 private usdcPosition = 1;
    uint32 public aV2USDCPosition = 1_000_001;

    string private sender = "Turbo Poggers Sommelier";

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mockGateway = new MockAxelarGateway();

        proxy = new AxelarProxy(address(mockGateway), sender);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(AaveATokenAdaptor).creationCode;
        constructorArgs = abi.encode(address(pool), address(WETH), 1.05e18);
        aaveATokenAdaptor = AaveATokenAdaptor(
            deployer.deployContract("Aave AToken Adaptor V0.0", creationCode, constructorArgs, 0)
        );

        // Setup pricing
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        registry.trustAdaptor(address(aaveATokenAdaptor));
        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(aV2USDCPosition, address(aaveATokenAdaptor), abi.encode(address(aV2USDC)));

        string memory cellarName = "Dummy Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(0), initialDeposit, platformCut);
        vm.label(address(cellar), "usdcCLR");

        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        cellar.addPositionToCatalogue(aV2USDCPosition);

        cellar.addPosition(1, aV2USDCPosition, abi.encode(1.1e18), false);

        cellar.transferOwnership(address(proxy));
    }

    function testGeneralMessage(uint192 newShareSupplyCap) external {
        newShareSupplyCap = uint192(bound(newShareSupplyCap, 1, type(uint192).max - 1));
        bytes32 commandId = hex"01";
        string memory sourceChain = "sommelier";
        bytes memory data = abi.encodeWithSelector(Cellar.decreaseShareSupplyCap.selector, newShareSupplyCap);
        bytes memory payload = abi.encode(0, address(cellar), 1, block.timestamp, data);
        proxy.execute(commandId, sourceChain, sender, payload);

        assertEq(
            cellar.shareSupplyCap(),
            newShareSupplyCap,
            "Target Cellar Share Supply Cap should have been updated."
        );
    }

    function testOwnershipTransferMessage() external {
        bytes32 commandId = hex"01";
        string memory sourceChain = "sommelier";
        address[] memory targets = new address[](1);
        targets[0] = address(cellar);
        bytes memory payload = abi.encode(1, address(this), targets);
        proxy.execute(commandId, sourceChain, sender, payload);

        assertEq(cellar.owner(), address(this), "Target Cellar Owner should have been updated.");
    }

    function testRebalancingMessage(uint256 assets) external {
        assets = bound(assets, 0.1e6, 1_000_000e6);
        deal(address(USDC), address(this), assets);
        USDC.approve(address(cellar), assets);
        cellar.deposit(assets, address(this));

        bytes32 commandId = hex"01";
        string memory sourceChain = "sommelier";

        // Create rebalance data.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToLendOnAaveV2(USDC, assets);

        data[0] = Cellar.AdaptorCall({ adaptor: address(aaveATokenAdaptor), callData: adaptorCalls });

        bytes memory callData = abi.encodeWithSelector(Cellar.callOnAdaptor.selector, data);
        bytes memory payload = abi.encode(0, address(cellar), 1, block.timestamp, callData);

        proxy.execute(commandId, sourceChain, sender, payload);

        assertApproxEqAbs(aV2USDC.balanceOf(address(cellar)), assets, 1, "Cellar should have rebalanced into Aave V2.");
    }

    function testRevertWrongSourceChain() external {
        uint192 newShareSupplyCap = 0;
        bytes32 commandId = hex"01";
        string memory sourceChain = "ethereum";
        bytes memory data = abi.encodeWithSelector(Cellar.decreaseShareSupplyCap.selector, newShareSupplyCap);
        bytes memory payload = abi.encode(0, address(cellar), 1, block.timestamp, data);
        vm.expectRevert(bytes(abi.encodeWithSelector(AxelarProxy.AxelarProxy__WrongSource.selector)));
        proxy.execute(commandId, sourceChain, sender, payload);
    }

    function testRevertWrongSender() external {
        uint192 newShareSupplyCap = 0;
        bytes32 commandId = hex"01";
        string memory sourceChain = "sommelier";
        string memory wrongSender = "Not a Turbo Poggers Sommelier";
        bytes memory data = abi.encodeWithSelector(Cellar.decreaseShareSupplyCap.selector, newShareSupplyCap);
        bytes memory payload = abi.encode(0, address(cellar), 1, block.timestamp, data);
        vm.expectRevert(bytes(abi.encodeWithSelector(AxelarProxy.AxelarProxy__WrongSender.selector)));
        proxy.execute(commandId, sourceChain, wrongSender, payload);
    }

    function testRevertWrongMsgId() external {
        uint192 newShareSupplyCap = 0;
        bytes32 commandId = hex"01";
        string memory sourceChain = "sommelier";
        bytes memory data = abi.encodeWithSelector(Cellar.decreaseShareSupplyCap.selector, newShareSupplyCap);
        bytes memory payload = abi.encode(2, address(cellar), 1, block.timestamp, data);
        vm.expectRevert(bytes(abi.encodeWithSelector(AxelarProxy.AxelarProxy__WrongMsgId.selector)));
        proxy.execute(commandId, sourceChain, sender, payload);
    }

    function testRevertOldNonce() external {
        uint192 newShareSupplyCap = 0;
        bytes32 commandId = hex"01";
        string memory sourceChain = "sommelier";
        bytes memory data = abi.encodeWithSelector(Cellar.decreaseShareSupplyCap.selector, newShareSupplyCap);
        bytes memory payload = abi.encode(0, address(cellar), 0, block.timestamp, data);
        vm.expectRevert(bytes(abi.encodeWithSelector(AxelarProxy.AxelarProxy__NonceTooOld.selector)));
        proxy.execute(commandId, sourceChain, sender, payload);
    }

    function testRevertPastDeadline() external {
        uint192 newShareSupplyCap = 0;
        bytes32 commandId = hex"01";
        string memory sourceChain = "sommelier";
        bytes memory data = abi.encodeWithSelector(Cellar.decreaseShareSupplyCap.selector, newShareSupplyCap);
        bytes memory payload = abi.encode(0, address(cellar), 1, block.timestamp - 1, data);
        vm.expectRevert(bytes(abi.encodeWithSelector(AxelarProxy.AxelarProxy__PastDeadline.selector)));
        proxy.execute(commandId, sourceChain, sender, payload);
    }

    function testRecoveringFromMaxNonce() external {
        uint192 newShareSupplyCap = 0;
        bytes32 commandId = hex"01";
        string memory sourceChain = "sommelier";
        bytes memory data = abi.encodeWithSelector(Cellar.decreaseShareSupplyCap.selector, newShareSupplyCap);
        bytes memory payload = abi.encode(0, address(cellar), type(uint256).max, block.timestamp, data);

        // Call goes through which sets the nonce to type uint256 max.
        proxy.execute(commandId, sourceChain, sender, payload);

        // Subsequent calls fails.
        data = abi.encodeWithSelector(Cellar.increaseShareSupplyCap.selector, type(uint192).max);
        payload = abi.encode(0, address(cellar), 1, block.timestamp, data);

        vm.expectRevert(bytes(abi.encodeWithSelector(AxelarProxy.AxelarProxy__NonceTooOld.selector)));
        proxy.execute(commandId, sourceChain, sender, payload);

        // Sommelier should fix the issue that allowed an attacker to send a large nonce, then migrate to a new proxy.
        AxelarProxy newProxy = new AxelarProxy(address(mockGateway), sender);
        address[] memory targets = new address[](1);
        targets[0] = address(cellar);
        payload = abi.encode(1, address(newProxy), targets);
        proxy.execute(commandId, sourceChain, sender, payload);

        // Now that Cellar has been migrated to a new proxy, commands can continue as normal.
        payload = abi.encode(0, address(cellar), 1, block.timestamp, data);
        newProxy.execute(commandId, sourceChain, sender, payload);

        assertEq(
            cellar.shareSupplyCap(),
            type(uint192).max,
            "Target Cellar Share Supply Cap should have been updated."
        );
    }
}
