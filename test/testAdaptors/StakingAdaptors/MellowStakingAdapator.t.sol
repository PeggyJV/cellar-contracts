// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MellowStakingAdaptor, StakingAdaptor } from "src/modules/adaptors/Staking/MellowStakingAdaptor.sol";
import { CellarWithNativeSupport } from "src/base/permutations/CellarWithNativeSupport.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

//Test the P2P Mellow Contract

contract MellowStakingAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    MellowStakingAdaptor private mellowAdaptor;
    CellarWithNativeSupport private cellar;

    uint32 public wethPosition = 1;
    uint32 public wstEthPosition = 2;

    ERC20 public primitive = WETH;
    ERC20 public derivative = STETH;
    ERC20 public wrappedDerivative = WSTETH;

    uint256 public initialAssets;

    uint8 public maxRequests = 16;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19077000;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        lidoAdaptor = new MellowStakingAdaptor(address(WETH), maxRequests, address(STETH), address(WSTETH), unstETH);
        wstethExtension = new WstEthExtension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_USD_FEED);
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        uint256 wstethToStethConversion = wstethExtension.stEth().getPooledEthByShares(1e18);
        price = price.mulDivDown(wstethToStethConversion, 1e18);
        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(wstethExtension));
        priceRouter.addAsset(WSTETH, settings, abi.encode(0), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(lidoAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(stEthPosition, address(erc20Adaptor), abi.encode(STETH));
        registry.trustPosition(wstEthPosition, address(erc20Adaptor), abi.encode(WSTETH));
        registry.trustPosition(lidoPosition, address(lidoAdaptor), abi.encode(primitive));

        string memory cellarName = "Lido Cellar V0.0";
        uint256 initialDeposit = 0.0001e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellarWithNativeSupport(
            cellarName,
            WETH,
            wethPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );

        cellar.addAdaptorToCatalogue(address(lidoAdaptor));

        cellar.addPositionToCatalogue(stEthPosition);
        cellar.addPositionToCatalogue(wstEthPosition);
        cellar.addPositionToCatalogue(lidoPosition);
        cellar.addPosition(1, stEthPosition, abi.encode(true), false);
        cellar.addPosition(2, wstEthPosition, abi.encode(true), false);
        cellar.addPosition(3, lidoPosition, abi.encode(0), false);

        cellar.setRebalanceDeviation(0.01e18);

        initialAssets = initialDeposit;

        WETH.safeApprove(address(cellar), type(uint256).max);
    }
}
