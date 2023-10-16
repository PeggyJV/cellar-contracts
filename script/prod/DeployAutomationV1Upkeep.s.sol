// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { Deployer } from "src/Deployer.sol";

import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

import { RedstoneEthPriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstoneEthPriceFeedExtension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";

interface ILINK {
    function approve(address spender, uint256 value) external;

    function transferAndCall(address _to, uint256 _value, bytes calldata _data) external;
}

interface IRegistrar {
    function register(
        string memory name,
        bytes calldata encryptedEmail,
        address upkeepContract,
        uint32 gasLimit,
        address adminAddress,
        bytes calldata checkData,
        uint96 amount,
        uint8 source,
        address sender
    ) external;
}

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployAutomationV1Upkeep.s.sol:DeployAutomationV1UpkeepScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployAutomationV1UpkeepScript is Script, MainnetAddresses {
    address public upkeepOwner = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;

    address public automationRegistryV1 = 0x02777053d6764996e594c3E88AF1D58D5363a2e6;
    address public automationRegistrarV1 = 0xDb8e8e2ccb5C033938736aa89Fe4fa1eDfD15a1d;
    ILINK public erc677Link = ILINK(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    PriceRouter public priceRouter = PriceRouter(0xA1A0bc3D59e4ee5840c9530e49Bdc2d1f88AaF92);

    Deployer public deployer = Deployer(deployerAddress);

    RedstoneEthPriceFeedExtension public redstoneEthPriceFeedExtension;

    function run() external {
        // Upkeep Params.
        string memory name = "Name";
        bytes memory encryptedEmail = hex"";
        address upkeepContract = address(0);
        uint32 gasLimit = 500_000;
        address adminAddress = upkeepOwner;
        bytes memory checkData = abi.encode(0);
        uint96 amount = 1e18;
        uint8 source = 97;
        address sender = upkeepOwner;

        bytes memory registerData = abi.encodeWithSelector(
            IRegistrar.register.selector,
            name,
            encryptedEmail,
            upkeepContract,
            gasLimit,
            adminAddress,
            checkData,
            amount,
            source,
            sender
        );

        vm.startBroadcast();

        erc677Link.approve(automationRegistrarV1, amount);

        erc677Link.transferAndCall(automationRegistrarV1, amount, registerData);

        vm.stopBroadcast();
    }
}
