// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/WstEthExtension.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/RealYieldEth/DeployWstEthOracle.s.sol:DeployWstEthOracleScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployWstEthOracleScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ERC20 public wstETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    CellarInitializableV2_2 private cellar;

    uint8 private constant CHAINLINK_DERIVATIVE = 1;


    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    TimelockController private controller = TimelockController(payable(0xaDa78a5E01325B91Bc7879a63c309F7D54d42950));

    WstEthExtension private extension;

    function run() external {
        vm.startBroadcast();

        // Deploy WstEth pricing contract.
        extension = new WstEthExtension();

        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(
            CHAINLINK_DERIVATIVE,
            address(extension)
        );
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            80e18,
            0.1e18,
            0,
            true
        );

        // Create timelock TXs to add wsteth pricing to the price router.
        bytes[] memory addWstEthData = new bytes[](10);
        // Encompasses price ranges
        /*
        1632: 1600 -> 1664
        1697: 1664 -> 1730
        1765: 1730 -> 1800
        
        */ 
        uint256 startingPrice = 1632e9
        for (uint256 i; i<10; ++i) {
            addWstEthData[i] = abi.encodeWithSelector(PriceRouter.addAsset.selector, wstETH, settings, abi.encode(stor), );
        }

        vm.stopBroadcast();
    }
}
