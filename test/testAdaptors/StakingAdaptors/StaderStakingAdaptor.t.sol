// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { StaderStakingAdaptor, StakingAdaptor, IUserWithdrawManager } from "src/modules/adaptors/Staking/StaderStakingAdaptor.sol";
import { CellarWithNativeSupport } from "src/base/permutations/CellarWithNativeSupport.sol";
import { RedstonePriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract StaderStakingAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    StaderStakingAdaptor private staderAdaptor;
    CellarWithNativeSupport private cellar;
    RedstonePriceFeedExtension private redstonePriceFeedExtension;

    uint32 public wethPosition = 1;
    uint32 public ethXPosition = 2;
    uint32 public staderPosition = 3;

    ERC20 public primitive = WETH;
    ERC20 public derivative = ETHX;
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

        staderAdaptor = new StaderStakingAdaptor(
            address(WETH),
            maxRequests,
            stakePoolManagerAddress,
            userWithdrawManagerAddress,
            address(ETHX),
            staderConfig
        );
        redstonePriceFeedExtension = new RedstonePriceFeedExtension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(STETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, STETH_USD_FEED);
        priceRouter.addAsset(STETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));
        RedstonePriceFeedExtension.ExtensionStorage memory rstor;
        rstor.dataFeedId = 0x4554487800000000000000000000000000000000000000000000000000000000;
        rstor.heartbeat = 1 days;
        rstor.redstoneAdapter = IRedstoneAdapter(ethXAdapter);
        price = IRedstoneAdapter(ethXAdapter).getValueForDataFeed(rstor.dataFeedId);
        priceRouter.addAsset(ETHX, settings, abi.encode(rstor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(staderAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(ethXPosition, address(erc20Adaptor), abi.encode(ETHX));
        registry.trustPosition(staderPosition, address(staderAdaptor), abi.encode(primitive));

        string memory cellarName = "Stader Cellar V0.0";
        uint256 initialDeposit = 0.001e18;
        uint64 platformCut = 0.75e18;

        cellar = _createCellarWithNativeSupport(
            cellarName,
            WETH,
            wethPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );

        cellar.addAdaptorToCatalogue(address(staderAdaptor));

        cellar.addPositionToCatalogue(ethXPosition);
        cellar.addPositionToCatalogue(staderPosition);
        cellar.addPosition(1, ethXPosition, abi.encode(true), false);
        cellar.addPosition(2, staderPosition, abi.encode(0), false);

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
            "Should have minted derivative with mintAmount."
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
                    9805484752484587657,
                    type(uint256).max
                )
            )
        );
        _mintDerivative(mintAmount, type(uint256).max);
    }

    function testBurn(uint256 mintAmount) external {
        mintAmount = bound(mintAmount, 0.1e18, 1_000e18);
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));

        uint256 startingTotalAssets = cellar.totalAssets();

        _mintDerivative(mintAmount, 0);

        uint256 burnAmount = derivative.balanceOf(address(cellar));

        // Rebalance cellar to start a burn request.
        _startDerivativeBurnRequest(burnAmount);

        assertApproxEqRel(
            cellar.totalAssets(),
            startingTotalAssets,
            0.00000001e18,
            "totalAssets should not have changed."
        );

        uint256 requestId = staderAdaptor.requestIds(address(cellar), 0);

        _finalizeRequests();

        assertApproxEqRel(
            cellar.totalAssets(),
            startingTotalAssets,
            0.00000001e18,
            "totalAssets should not have changed."
        );

        // Rebalance cellar to finalize burn request.
        _completeDerivativeBurnRequest(requestId, 0);

        assertApproxEqRel(
            cellar.totalAssets(),
            startingTotalAssets,
            0.00000001e18,
            "totalAssets should not have changed."
        );

        assertApproxEqRel(
            primitive.balanceOf(address(cellar)),
            startingTotalAssets,
            0.00000001e18,
            "Cellar should have all assets in primitive."
        );
    }

    function testBurnMinAmount() external {
        uint256 mintAmount = 10e18;
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));

        _mintDerivative(mintAmount, 0);

        uint256 burnAmount = derivative.balanceOf(address(cellar));

        // Rebalance cellar to start a burn request.
        _startDerivativeBurnRequest(burnAmount);

        uint256 requestId = staderAdaptor.requestIds(address(cellar), 0);

        _finalizeRequests();

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    StakingAdaptor.StakingAdaptor__MinimumAmountNotMet.selector,
                    mintAmount - 10,
                    type(uint256).max
                )
            )
        );
        _completeDerivativeBurnRequest(requestId, type(uint256).max);
    }

    function testMultipleMintAndBurns(uint256 seed) external {
        uint256[] memory mintAmounts = new uint256[](maxRequests);
        uint256 burnAmount;
        uint256 expectedTotalAssets = initialAssets;
        uint256[] memory requests;
        for (uint256 i; i < maxRequests; ++i) {
            mintAmounts[i] = uint256(keccak256(abi.encodePacked(seed, i))) % 1_000e18; // Cap value to 1k.
            expectedTotalAssets += mintAmounts[i];
            deal(address(primitive), address(this), mintAmounts[i]);
            cellar.deposit(mintAmounts[i], address(this));

            _mintDerivative(mintAmounts[i], 0);
            burnAmount = derivative.balanceOf(address(cellar));
            _startDerivativeBurnRequest(burnAmount);

            requests = staderAdaptor.getRequestIds(address(cellar));
            assertEq(requests.length, i + 1, "Should have i + 1 requests.");
        }

        // Making 1 more burn request should revert.
        _mintDerivative(initialAssets, 0);
        burnAmount = derivative.balanceOf(address(cellar));
        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__MaximumRequestsExceeded.selector)));
        _startDerivativeBurnRequest(burnAmount);

        // Finalize requests.
        _finalizeRequests();

        // Complete requests.
        for (uint256 i; i < maxRequests; ++i) {
            uint256 requestId = staderAdaptor.requestIds(address(cellar), 0);
            _completeDerivativeBurnRequest(requestId, 0);
        }
        requests = staderAdaptor.getRequestIds(address(cellar));
        assertEq(requests.length, 0, "Should have no burn requests left.");
        assertApproxEqRel(
            cellar.totalAssets(),
            expectedTotalAssets,
            0.000001e18,
            "totalAssets should not have changed."
        );
        uint256 expectedPrimitiveBalance = expectedTotalAssets - initialAssets;
        assertApproxEqRel(
            primitive.balanceOf(address(cellar)),
            expectedPrimitiveBalance,
            0.000001e18,
            "primitive balance should equal expected"
        );
        uint256 expectedDerivativeBalance = priceRouter.getValue(primitive, initialAssets, derivative);
        assertApproxEqRel(
            derivative.balanceOf(address(cellar)),
            expectedDerivativeBalance,
            0.01e18,
            "derivative balance should equal expected"
        );
    }

    function testHandlingInvalidRequests(uint256 mintAmount) external {
        mintAmount = bound(mintAmount, 0.1e18, 1_000e18);
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));

        uint256 startingTotalAssets = cellar.totalAssets();

        _mintDerivative(mintAmount, 0);

        uint256 burnAmount = derivative.balanceOf(address(cellar));

        // Rebalance cellar to start a burn request.
        _startDerivativeBurnRequest(burnAmount);

        assertApproxEqRel(
            cellar.totalAssets(),
            startingTotalAssets,
            0.00000001e18,
            "totalAssets should not have changed."
        );

        uint256 requestId = staderAdaptor.requestIds(address(cellar), 0);

        _finalizeRequests();

        assertApproxEqRel(
            cellar.totalAssets(),
            startingTotalAssets,
            0.00000001e18,
            "totalAssets should not have changed."
        );

        // Strategist accidentally tries removing the valid request.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__RequestNotClaimed.selector, requestId))
        );
        _removeClaimedRequest(requestId);

        // Simulate a state where somehow the request is claimed without the strategist calling `completeBurn`
        vm.startPrank(address(cellar));
        staderAdaptor.userWithdrawManager().claim(requestId);
        staderAdaptor.wrappedPrimitive().deposit{ value: address(cellar).balance }();
        vm.stopPrank();

        // TotalAssets should remain the unchanged since the withdrawn assets go into an ERC20 position.
        // And staking adaptor does not account for value in request because it is not valid.
        assertApproxEqRel(
            cellar.totalAssets(),
            startingTotalAssets,
            0.00000001e18,
            "totalAssets should not have changed."
        );

        // Strategist should now be able to remove the request.
        _removeClaimedRequest(requestId);

        // But if they try to remove it again it reverts.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__RequestNotFound.selector, requestId))
        );
        _removeClaimedRequest(requestId);
    }

    function _removeClaimedRequest(uint256 requestId) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRemoveClaimedRequest(requestId, hex"");
        data[0] = Cellar.AdaptorCall({ adaptor: address(staderAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _finalizeRequests() internal {
        // Spoof unstEth contract into finalizing our request.
        // Stader has a minimum block amount for withdraws to become valid.
        vm.roll(block.number + 2_500);

        IUserWithdrawManager(userWithdrawManagerAddress).finalizeUserWithdrawalRequest();
    }

    function _startDerivativeBurnRequest(uint256 burnAmount) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRequestBurn(burnAmount, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(staderAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _completeDerivativeBurnRequest(uint256 requestId, uint256 minAmountOut) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToCompleteBurn(requestId, minAmountOut, hex"");
        data[0] = Cellar.AdaptorCall({ adaptor: address(staderAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _cancelDerivativeBurnRequest(uint256 requestId) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToCancelBurnRequest(requestId, hex"");
        data[0] = Cellar.AdaptorCall({ adaptor: address(staderAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _mintDerivative(uint256 mintAmount, uint256 minAmountOut) internal {
        // Rebalance Cellar to mint derivative.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMint(mintAmount, minAmountOut, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(staderAdaptor), callData: adaptorCalls });
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
