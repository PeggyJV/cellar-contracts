// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MellowStakingAdaptor, StakingAdaptor } from "src/modules/adaptors/Staking/MellowStakingAdaptor.sol";
import { Cellar } from "src/base/Cellar.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract MellowStakingAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    MellowStakingAdaptor private mellowAdaptor;
    Cellar private cellar;

    uint32 public wethPosition = 1;
    uint32 public rstETHPosition = 2;

    ERC20 public rstETH = ERC20(0x7a4EffD87C2f3C55CA251080b1343b605f327E3a);
    address public mellowVault = 0xaf108ae0AD8700ac41346aCb620e828c03BB8848;

    ERC20 public primitive = WETH;
    ERC20 public derivative = rstETH;
    ERC20 public wrappedDerivative = ERC20(address(0));

    uint256 public initialAssets;

    uint8 public maxRequests = 8;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 21221543;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        mellowAdaptor = new MellowStakingAdaptor(address(WETH), 8, mellowVault, address(rstETH));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Set rstETH to be 1:1 with ETH.
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(rstETH, settings, abi.encode(stor), price);
        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(mellowAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(rstETHPosition, address(erc20Adaptor), abi.encode(rstETH));

        string memory cellarName = "Mellow Cellar V0.0";
        uint256 initialDeposit = 0.0001e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellarLocal(
            cellarName,
            WETH,
            wethPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );

        cellar.addAdaptorToCatalogue(address(mellowAdaptor));

        cellar.addPositionToCatalogue(rstETHPosition);
        cellar.addPosition(1, rstETHPosition, abi.encode(true), false);

        cellar.setRebalanceDeviation(0.01e18);

        initialAssets = initialDeposit;

        WETH.safeApprove(address(cellar), type(uint256).max);
    }

    function testMint(uint256 mintAmount) external {
        mintAmount = bound(mintAmount, 0.0001e18, 10e18);
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));
        // Rebalance Cellar to mint derivative.
        _mintDerivative(mintAmount, 0);
        assertApproxEqAbs(
            primitive.balanceOf(address(cellar)),
            initialAssets,
            2,
            "Should only have initialAssets of primitive left."
        );
        uint256 expectedDerivativeAmount = priceRouter.getValue(primitive, mintAmount, derivative);
        assertApproxEqRel(
            derivative.balanceOf(address(cellar)),
            expectedDerivativeAmount,
            0.01e18,
            "Should have minted wrapped derivative with mintAmount."
        );
    }

    // function testMintMinAmount() external {
    //     uint256 mintAmount = 10e18;
    //     deal(address(primitive), address(this), mintAmount);
    //     cellar.deposit(mintAmount, address(this));

    //     // Try minting with an excessive minAmountOut.
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 StakingAdaptor.StakingAdaptor__MinimumAmountNotMet.selector,
    //                 9974724809485861084,
    //                 type(uint256).max
    //             )
    //         )
    //     );
    //     _mintDerivative(mintAmount, type(uint256).max);
    // }

    function _mintDerivative(uint256 mintAmount, uint256 minAmountOut) internal {
        // Rebalance Cellar to mint derivative.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMint(mintAmount, minAmountOut, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(mellowAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _createCellarLocal(
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
            platformCut,
            type(uint192).max
        );

        return Cellar(deployer.deployContract(cellarName, creationCode, constructorArgs, 0));
    }
}
