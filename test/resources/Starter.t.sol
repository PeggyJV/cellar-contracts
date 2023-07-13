// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// Import Protocol Resources
import { Deployer } from "src/Deployer.sol";
import { Cellar } from "src/base/Cellar.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IGravity } from "src/interfaces/external/IGravity.sol";

// Import Helpers
import { Math } from "src/utils/Math.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { MainnetERC20s } from "test/resources/MainnetERC20s.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

// Import Frequently Used Adaptors
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";

// Import Testing Resources
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

/**
 * @notice This base contract should hold the most often repeated test code.
 */
contract StarterTest is Test, MainnetERC20s {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    Deployer public deployer;
    Registry public registry;
    PriceRouter public priceRouter;
    ERC20Adaptor public erc20Adaptor;
    SwapWithUniswapAdaptor public swapWithUniswapAdaptor;

    IGravity public gravityBridge = IGravity(0x69592e6f9d21989a043646fE8225da2600e5A0f7);

    address public uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;

    function _setUp() internal {
        address[] memory deployers = new address[](1);
        deployers[0] = address(this);
        deployer = new Deployer(address(this), deployers);

        bytes memory creationCode;
        bytes memory constructorArgs;

        // Deploy the registry.
        creationCode = type(Registry).creationCode;
        constructorArgs = abi.encode(address(this), address(this), address(this), address(this));
        registry = Registry(deployer.deployContract("Registry V0.0", creationCode, constructorArgs, 0));

        // Deploy the price router.
        creationCode = type(PriceRouter).creationCode;
        constructorArgs = abi.encode(address(this), registry, WETH);
        priceRouter = PriceRouter(deployer.deployContract("PriceRouter V0.0", creationCode, constructorArgs, 0));

        // Update price router in registry.
        registry.setAddress(2, address(priceRouter));

        // Deploy ERC20Adaptor.
        creationCode = type(ERC20Adaptor).creationCode;
        constructorArgs = hex"";
        erc20Adaptor = ERC20Adaptor(deployer.deployContract("ERC20 Adaptor V0.0", creationCode, constructorArgs, 0));

        // Deploy SwapWithUniswapAdaptor.
        creationCode = type(SwapWithUniswapAdaptor).creationCode;
        constructorArgs = abi.encode(uniV2Router, uniV3Router);
        swapWithUniswapAdaptor = SwapWithUniswapAdaptor(
            deployer.deployContract("Swap With Uniswap Adaptor V0.0", creationCode, constructorArgs, 0)
        );

        // Trust Adaptors in Regsitry.
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(swapWithUniswapAdaptor));
    }

    function _startFork(string memory rpcKey, string memory blockNumberKey) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), vm.envUint(blockNumberKey));
        vm.selectFork(forkId);
    }

    function _createCellar(
        string memory cellarName,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (Cellar) {
        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(holdingAsset), address(this), initialDeposit);
        holdingAsset.approve(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(Cellar).creationCode;
        constructorArgs = abi.encode(
            address(this),
            registry,
            holdingAsset,
            cellarName,
            cellarName,
            holdingPosition,
            holdingPositionConfig,
            initialDeposit,
            platformCut
        );

        return Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));
    }
}
