// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";
import { Cellar } from "src/base/Cellar.sol";
import { ERC4626SharePriceOracle } from "src/base/ERC4626SharePriceOracle.sol";

import { ArbitrumAddresses } from "test/resources/Arbitrum/ArbitrumAddresses.sol";

import "forge-std/Script.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Arbitrum/test/DeployTestLemon.s.sol:DeployTestLemonScript --evm-version london --rpc-url $ARBITRUM_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 100000000 --verify --etherscan-api-key $ARBISCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployTestLemonScript is Script, ArbitrumAddresses {
    Deployer public deployer = Deployer(deployerAddress);

    address public zeroXAdaptor = 0x48B11b282964AF32AA26A5f83323271e02E7fAF0;
    address public oneInchAdaptor = 0xc64A77Aad4c9e1d78EaDe6Ad204Df751eCD30173;

    address public aaveV3DebtTokenAdaptor = 0x76Baff5B49Aa06a1c226Db42cDc6210f3b6658C2;
    address public aaveV3ATokenAdaptor = 0x88fe7C31D26c43B8b0d313e45c3d9d1c300F7e18;

    address public uniswapV3Adaptor = 0x4804534106AE70718aaCBe35710D8d4F553F5bcD;
    address public uniswapV3PositionTracker = 0xd0BAB80e5aBE6fcAdBf07b0F8F15Ac92F7e51B64;

    address public erc20Adaptor = 0xcaDe581bD66104B278A2F47a43B05a2db64E871f;

    address public registry = 0x43BD96931A47FBABd50727F6982c796B3C9A974C;

    Cellar public cellar;

    function run() external {
        address cellarAddress = deployer.getAddress("Test Lemon V0.0");
        bytes memory creationCode = type(Cellar).creationCode;
        bytes memory constructorArgs = abi.encode(
            dev0Address,
            registry,
            USDCe,
            "Test Lemon",
            "TL",
            3,
            abi.encode(0),
            0.01e6,
            0.8e18,
            type(uint192).max
        );

        vm.startBroadcast();
        USDCe.approve(cellarAddress, 0.01e6);
        cellar = Cellar(deployer.deployContract("Test Lemon V0.0", creationCode, constructorArgs, 0));
        cellar.transferOwnership(axelarProxyV0_0);
        vm.stopBroadcast();
    }
}
