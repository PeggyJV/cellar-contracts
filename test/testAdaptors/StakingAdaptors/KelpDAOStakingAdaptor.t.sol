// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { KelpDAOStakingAdaptor, StakingAdaptor } from "src/modules/adaptors/Staking/KelpDAOStakingAdaptor.sol";
import { CellarWithNativeSupport } from "src/base/permutations/CellarWithNativeSupport.sol";
import { RedstonePriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";
import { MockDataFeed } from "src/mocks/MockDataFeed.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract KelpDAOStakingAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    KelpDAOStakingAdaptor private kelpDAOAdaptor;
    CellarWithNativeSupport private cellar;
    RedstonePriceFeedExtension private redstonePriceFeedExtension;
    MockDataFeed public mockRSETHdataFeed;

    uint32 public wethPosition = 1;
    uint32 public rsethPosition = 2;
    uint32 public ethXPosition = 3;

    ERC20 public primitive = WETH;
    ERC20 public derivative = RSETH;
    ERC20 public wrappedDerivative = ERC20(address(0));

    uint256 public initialAssets;

    uint8 public maxRequests = 8;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19077000;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        kelpDAOAdaptor = new KelpDAOStakingAdaptor(address(WETH), 8, lrtDepositPool, address(RSETH));
        redstonePriceFeedExtension = new RedstonePriceFeedExtension(priceRouter);
        mockRSETHdataFeed = new MockDataFeed(WETH_USD_FEED);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Set RSETH to be 1:1 with ETH.
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, address(mockRSETHdataFeed));
        priceRouter.addAsset(RSETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));
        RedstonePriceFeedExtension.ExtensionStorage memory rstor;
        rstor.dataFeedId = 0x4554487800000000000000000000000000000000000000000000000000000000;
        rstor.heartbeat = 1 days;
        rstor.redstoneAdapter = IRedstoneAdapter(ethXAdapter);
        price = IRedstoneAdapter(ethXAdapter).getValueForDataFeed(rstor.dataFeedId);
        priceRouter.addAsset(ETHX, settings, abi.encode(rstor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(kelpDAOAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(rsethPosition, address(erc20Adaptor), abi.encode(RSETH));
        registry.trustPosition(ethXPosition, address(erc20Adaptor), abi.encode(ETHX));

        string memory cellarName = "Renzo Cellar V0.0";
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

        cellar.addAdaptorToCatalogue(address(kelpDAOAdaptor));

        cellar.addPositionToCatalogue(rsethPosition);
        cellar.addPositionToCatalogue(ethXPosition);

        cellar.addPosition(1, rsethPosition, abi.encode(true), false);
        cellar.addPosition(2, ethXPosition, abi.encode(true), false);

        cellar.setRebalanceDeviation(0.03e18);

        initialAssets = initialDeposit;

        WETH.safeApprove(address(cellar), type(uint256).max);
    }

    function testMint(uint256 mintAmount) external {
        mintAmount = bound(mintAmount, 0.001e18, 10_000e18);
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));

        // Simulate a swap/mint.
        uint256 ethXAmount = priceRouter.getValue(WETH, mintAmount, ETHX);
        deal(address(WETH), address(cellar), initialAssets);
        deal(address(ETHX), address(cellar), ethXAmount);

        // Rebalance Cellar to mint derivative.
        _mintDerivativeERC20(ETHX, ethXAmount, 0);
        assertApproxEqAbs(ETHX.balanceOf(address(cellar)), 0, 2, "Should have used all ETHX to mint.");
        uint256 expectedDerivativeAmount = priceRouter.getValue(ETHX, mintAmount, derivative);
        assertApproxEqRel(
            derivative.balanceOf(address(cellar)),
            expectedDerivativeAmount,
            0.05e18,
            "Should have minted wrapped derivative with mintAmount."
        );
    }

    function testIllogicalInputs() external {
        uint256 mintAmount = 1_000e18;
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));

        // Try minting with an asset that is not supported.
        vm.expectRevert();
        _mintDerivativeERC20(LINK, mintAmount, 0);

        // Simulate a swap/mint.
        uint256 ethXAmount = priceRouter.getValue(WETH, mintAmount, ETHX);
        deal(address(WETH), address(cellar), initialAssets);
        deal(address(ETHX), address(cellar), ethXAmount);

        // Check that min amount out works.
        vm.expectRevert();
        _mintDerivativeERC20(ETHX, ethXAmount, type(uint256).max);

        // Check slippage revert.
        uint256 rsETHValue = priceRouter.getPriceInUSD(WETH);
        rsETHValue = rsETHValue.mulDivDown(0.9e4, 1e4);
        mockRSETHdataFeed.setMockAnswer(int256(rsETHValue));

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    KelpDAOStakingAdaptor.KelpDAOStakingAdaptor__Slippage.selector,
                    988978075745340096142,
                    999999999999999999999
                )
            )
        );
        _mintDerivativeERC20(ETHX, ethXAmount, 0);
    }

    function _mintDerivativeERC20(ERC20 depositAsset, uint256 mintAmount, uint256 minMintAmountOut) internal {
        // Rebalance Cellar to mint derivative.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMintERC20(depositAsset, mintAmount, minMintAmountOut, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(kelpDAOAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _createCellarWithNativeSupport(
        string memory cellarName,
        ERC20 holdingAsset,
        uint32 holdingPosition,
        bytes memory holdingPositionConfig,
        uint256 initialDeposit,
        uint64 platformCut
    ) internal returns (CellarWithNativeSupport) {
        // Approve new cellar to spend assets.
        address cellarAddress = deployer.getAddress(cellarName);
        deal(address(holdingAsset), address(this), initialDeposit);
        holdingAsset.approve(cellarAddress, initialDeposit);

        bytes memory creationCode;
        bytes memory constructorArgs;
        creationCode = type(CellarWithNativeSupport).creationCode;
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

        return CellarWithNativeSupport(payable(deployer.deployContract(cellarName, creationCode, constructorArgs, 0)));
    }
}
