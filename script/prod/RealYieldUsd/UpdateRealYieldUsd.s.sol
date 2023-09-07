// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC4626, ERC20, SafeTransferLib, PriceRouter } from "src/base/Cellar.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

interface IRegistry {
    function trustAdaptor(address adaptor, uint128 assetRisk, uint128 protocolRisk) external;

    function trustPosition(address adaptor, bytes memory adaptorData, uint128 assetRisk, uint128 protocolRisk) external;
}

interface IRealYieldUsd {
    function addPosition(uint32 index, uint32 positionId, bytes memory congigData, bool inDebtArray) external;
}

interface ICellar {
    function setupAdaptor(address adaptor) external;
}

/**
 * @dev Run
 *      `source .env && forge script script/prod/RealYieldUsd/UpdateRealYieldUsd.s.sol:UpdateRealYieldUsdScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract UpdateRealYieldUsdScript is Script, MainnetAddresses {
    TimelockController private controller = TimelockController(payable(0xaDa78a5E01325B91Bc7879a63c309F7D54d42950));

    IRegistry private registry = IRegistry(0x2Cbd27E034FEE53f79b607430dA7771B22050741);

    address public aaveV2DebtTokenAdaptor = 0xeC86ac06767e911f5FdE7cba5D97f082C0139C01;
    address public aaveV3DebtTokenAdaptor = 0x6DEd49176a69bEBf8dC1a4Ea357faa555df188f7;
    address public morphoV2DebtTokenAdaptor = 0x407D5489F201013EE6A6ca20fCcb05047C548138;

    address public aaveV3ATokenAdaptor = 0x3184CBEa47eD519FA04A23c4207cD15b7545F1A6;

    function run() external {
        // Borrow USDC, DAI, USDT from Aave V2, V3
        // Supply sDAI as collateral
        uint256 numberOfCalls = 1;

        address[] memory targets = new address[](numberOfCalls);
        for (uint256 i; i < numberOfCalls; ++i) targets[i] = address(registry);

        uint256[] memory values = new uint256[](numberOfCalls);

        bytes[] memory payloads = new bytes[](numberOfCalls);
        // Need to trustAdaptors
        payloads[0] = abi.encodeWithSelector(
            IRegistry.trustPosition.selector,
            aaveV3ATokenAdaptor,
            abi.encode(aV3sDAI),
            0,
            0
        );

        bytes32 predecessor = hex"";
        bytes32 salt = hex"";

        uint256 delay = 3 days;

        vm.startBroadcast();
        controller.scheduleBatch(targets, values, payloads, predecessor, salt, delay);
        vm.stopBroadcast();

        // Wait to trust Compound positions cuz RYUSD needs the new compound adaptor in order to fully exit the compound positions.
        // registry.trustPosition(cTokenAdaptor, abi.encode(cUSDC), 0, 0);
        // registry.trustPosition(cTokenAdaptor, abi.encode(cDAI), 0, 0);
        // registry.trustPosition(cTokenAdaptor, abi.encode(cUSDT), 0, 0);
    }
}
