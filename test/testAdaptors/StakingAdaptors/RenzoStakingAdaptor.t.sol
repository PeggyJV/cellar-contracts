// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { RenzoStakingAdaptor, StakingAdaptor } from "src/modules/adaptors/Staking/RenzoStakingAdaptor.sol";
import { CellarWithNativeSupport } from "src/base/permutations/CellarWithNativeSupport.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract RenzoStakingAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    RenzoStakingAdaptor private renzoAdaptor;
    CellarWithNativeSupport private cellar;

    uint32 public wethPosition = 1;
    uint32 public ezethPosition = 2;

    ERC20 public primitive = WETH;
    ERC20 public derivative = EZETH;
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

        renzoAdaptor = new RenzoStakingAdaptor(address(WETH), 8, restakeManager, address(EZETH));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Set EZETH to be 1:1 with ETH.
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(EZETH, settings, abi.encode(stor), price);
        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(renzoAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(ezethPosition, address(erc20Adaptor), abi.encode(EZETH));

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

        cellar.addAdaptorToCatalogue(address(renzoAdaptor));

        cellar.addPositionToCatalogue(ezethPosition);
        cellar.addPosition(1, ezethPosition, abi.encode(true), false);

        cellar.setRebalanceDeviation(0.01e18);

        initialAssets = initialDeposit;

        WETH.safeApprove(address(cellar), type(uint256).max);
    }

    function testMint(uint256 mintAmount) external {
        mintAmount = bound(mintAmount, 0.0001e18, 10_000e18);
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

    function testMintMinAmount() external {
        uint256 mintAmount = 10e18;
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));

        // Try minting with an excessive minAmountOut.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    StakingAdaptor.StakingAdaptor__MinimumAmountNotMet.selector,
                    9974724809485861084,
                    type(uint256).max
                )
            )
        );
        _mintDerivative(mintAmount, type(uint256).max);
    }

    function _mintDerivative(uint256 mintAmount, uint256 minAmountOut) internal {
        // Rebalance Cellar to mint derivative.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMint(mintAmount, minAmountOut, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(renzoAdaptor), callData: adaptorCalls });
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
