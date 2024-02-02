// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Deployer } from "src/Deployer.sol";

import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

import { ERC4626SharePriceOracle, ERC20 } from "src/base/ERC4626SharePriceOracle.sol";
import { CellarWithMultiAssetDeposit, Cellar } from "src/base/permutations/CellarWithMultiAssetDeposit.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";

import { ArbitrumAddresses } from "test/resources/Arbitrum/ArbitrumAddresses.sol";

/**
 * @dev Run
 *      `source .env && forge script script/Arbitrum/test/DeployTestMultiAssetDeposit.s.sol:DeployTestMultiAssetDepositScript --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 100000000 --verify --etherscan-api-key $ARBISCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployTestMultiAssetDepositScript is Script, ArbitrumAddresses {
    using Address for address;

    Deployer public deployer = Deployer(deployerAddress);

    Registry public registry = Registry(0x43BD96931A47FBABd50727F6982c796B3C9A974C);
    PriceRouter public priceRouter = PriceRouter(0x6aC423c11bb65B1bc7C5Cf292b22e0CBa125f98A);

    address public erc20Adaptor = 0xcaDe581bD66104B278A2F47a43B05a2db64E871f;
    address public uniswapV3Adaptor = 0x4804534106AE70718aaCBe35710D8d4F553F5bcD;
    address public aaveV3ATokenAdaptor = 0x88fe7C31D26c43B8b0d313e45c3d9d1c300F7e18;
    address public aaveV3DebtTokenAdaptor = 0x76Baff5B49Aa06a1c226Db42cDc6210f3b6658C2;
    address public zeroXAdaptor = 0x48B11b282964AF32AA26A5f83323271e02E7fAF0;
    address public oneInchAdaptor = 0xc64A77Aad4c9e1d78EaDe6Ad204Df751eCD30173;

    uint8 public constant CHAINLINK_DERIVATIVE = 1;

    uint32 public usdcPosition = 2;
    uint32 public usdcePosition = 3;
    uint32 public daiPosition = 4;
    uint32 public usdtPosition = 5;
    uint32 public aV3UsdcPosition = 2000002;

    function run() external {
        vm.startBroadcast();

        // Deploy Cellar
        CellarWithMultiAssetDeposit cellar = _createCellar(
            "Test Multi Asset Deposit Cellar",
            "TEST_MULTI_ASSET_DEPOSIT_CELLAR",
            USDC,
            aV3UsdcPosition,
            abi.encode(1.05e18),
            0.01e6,
            0.9e18
        );

        cellar.addAdaptorToCatalogue(aaveV3ATokenAdaptor);

        cellar.addPositionToCatalogue(usdcPosition);
        cellar.addPositionToCatalogue(usdcePosition);
        cellar.addPositionToCatalogue(daiPosition);
        cellar.addPositionToCatalogue(usdtPosition);

        cellar.addPosition(1, usdtPosition, abi.encode(true), false);
        cellar.addPosition(1, daiPosition, abi.encode(true), false);
        cellar.addPosition(1, usdcePosition, abi.encode(true), false);
        cellar.addPosition(1, usdcPosition, abi.encode(true), false);

        cellar.setAlternativeAssetData(USDC, usdcPosition, 0.0005e8);
        cellar.setAlternativeAssetData(USDCe, usdcePosition, 0.0010e8);
        cellar.setAlternativeAssetData(DAI, daiPosition, 0.0050e8);
        cellar.setAlternativeAssetData(USDT, usdtPosition, 0.0020e8);

        cellar.transferOwnership(devStrategist);

        vm.stopBroadcast();
    }

    function _createCellar(
        string memory cellarName,
        string memory cellarSymbol,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithMultiAssetDeposit) {
        // Approve new cellar to spend assets.
        string memory nameToUse = string.concat(cellarName, " V0.1");
        address cellarAddress = deployer.getAddress(nameToUse);
        holdingAsset.approve(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithMultiAssetDeposit).creationCode;
        constructorArgs = abi.encode(
            dev0Address,
            registry,
            holdingAsset,
            cellarName,
            cellarSymbol,
            holdingPosition,
            holdingPositionConfig,
            initialDeposit,
            platformCut,
            type(uint192).max
        );

        return CellarWithMultiAssetDeposit(deployer.deployContract(nameToUse, creationCode, constructorArgs, 0));
    }
}
