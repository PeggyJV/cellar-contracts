// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { EtherFiStakingAdaptor, StakingAdaptor, IWithdrawRequestNft, ILiquidityPool } from "src/modules/adaptors/Staking/EtherFiStakingAdaptor.sol";
import { CellarWithNativeSupport } from "src/base/permutations/CellarWithNativeSupport.sol";
import { RedstonePriceFeedExtension } from "src/modules/price-router/Extensions/Redstone/RedstonePriceFeedExtension.sol";
import { IRedstoneAdapter } from "src/interfaces/external/Redstone/IRedstoneAdapter.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract EtherFiStakingAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address payable;

    EtherFiStakingAdaptor private etherFiAdaptor;
    CellarWithNativeSupport private cellar;
    RedstonePriceFeedExtension private redstonePriceFeedExtension;

    uint32 public wethPosition = 1;
    uint32 public eethPosition = 2;
    uint32 public weethPosition = 3;
    uint32 public etherFiPosition = 4;

    ERC20 public primitive = WETH;
    ERC20 public derivative = EETH;
    ERC20 public wrappedDerivative = WEETH;

    uint256 public initialAssets;

    uint8 public maxRequests = 8;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19077000;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        etherFiAdaptor = new EtherFiStakingAdaptor(
            address(WETH),
            8,
            liquidityPool,
            withdrawalRequestNft,
            address(WEETH),
            address(EETH)
        );
        redstonePriceFeedExtension = new RedstonePriceFeedExtension(priceRouter);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Set eETH to be 1:1 with wETH.
        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(EETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(EXTENSION_DERIVATIVE, address(redstonePriceFeedExtension));
        RedstonePriceFeedExtension.ExtensionStorage memory rstor;
        rstor.dataFeedId = weethUsdDataFeedId;
        rstor.heartbeat = 1 days;
        rstor.redstoneAdapter = IRedstoneAdapter(weethAdapter);
        price = IRedstoneAdapter(weethAdapter).getValueForDataFeed(rstor.dataFeedId);
        priceRouter.addAsset(WEETH, settings, abi.encode(rstor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(etherFiAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));
        registry.trustPosition(eethPosition, address(erc20Adaptor), abi.encode(EETH));
        registry.trustPosition(weethPosition, address(erc20Adaptor), abi.encode(WEETH));
        registry.trustPosition(etherFiPosition, address(etherFiAdaptor), abi.encode(primitive));

        string memory cellarName = "EtherFi Cellar V0.0";
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

        cellar.addAdaptorToCatalogue(address(etherFiAdaptor));

        cellar.addPositionToCatalogue(weethPosition);
        cellar.addPositionToCatalogue(eethPosition);
        cellar.addPositionToCatalogue(etherFiPosition);
        cellar.addPosition(1, weethPosition, abi.encode(true), false);
        cellar.addPosition(2, etherFiPosition, abi.encode(0), false);
        cellar.addPosition(3, eethPosition, abi.encode(0), false);

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
                    mintAmount - 1,
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
        // Rebalance cellar to start a burn request.
        _startDerivativeBurnRequest(type(uint256).max);
        assertApproxEqAbs(cellar.totalAssets(), startingTotalAssets, 4, "totalAssets should not have changed.");
        uint256 requestId = etherFiAdaptor.requestIds(address(cellar), 0);
        _finalizeRequest(requestId, mintAmount);
        assertApproxEqAbs(cellar.totalAssets(), startingTotalAssets, 4, "totalAssets should not have changed.");
        // Rebalance cellar to finalize burn request.
        _completeDerivativeBurnRequest(requestId, 0);
        assertApproxEqAbs(cellar.totalAssets(), startingTotalAssets, 4, "totalAssets should not have changed.");
        assertApproxEqAbs(
            primitive.balanceOf(address(cellar)),
            startingTotalAssets,
            4,
            "Cellar should have all assets in primitive."
        );
    }

    function testBurnMinAmount() external {
        uint256 mintAmount = 10e18;
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));
        _mintDerivative(mintAmount, 0);

        // Rebalance cellar to start a burn request.
        _startDerivativeBurnRequest(type(uint256).max);
        uint256 requestId = etherFiAdaptor.requestIds(address(cellar), 0);
        _finalizeRequest(requestId, mintAmount);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    StakingAdaptor.StakingAdaptor__MinimumAmountNotMet.selector,
                    mintAmount - 2,
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

            requests = etherFiAdaptor.getRequestIds(address(cellar));
            assertEq(requests.length, i + 1, "Should have i + 1 requests.");
        }

        // Making 1 more burn request should revert.
        _mintDerivative(initialAssets, 0);
        burnAmount = derivative.balanceOf(address(cellar));
        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__MaximumRequestsExceeded.selector)));
        _startDerivativeBurnRequest(burnAmount);

        // Finalize requests.
        for (uint256 i; i < maxRequests; ++i) {
            uint256 requestId = etherFiAdaptor.requestIds(address(cellar), i);

            _finalizeRequest(requestId, mintAmounts[i]);
        }

        // Complete requests.
        for (uint256 i; i < maxRequests; ++i) {
            uint256 requestId = etherFiAdaptor.requestIds(address(cellar), 0);
            _completeDerivativeBurnRequest(requestId, 0);
        }
        requests = etherFiAdaptor.getRequestIds(address(cellar));
        assertEq(requests.length, 0, "Should have no burn requests left.");
        assertApproxEqRel(
            cellar.totalAssets(),
            expectedTotalAssets,
            0.000001e18,
            "totalAssets should not have changed."
        );
        uint256 expectedPrimitiveBalance = expectedTotalAssets - initialAssets;
        uint256 expectedDerivativeBalance = initialAssets;
        assertApproxEqRel(
            primitive.balanceOf(address(cellar)),
            expectedPrimitiveBalance,
            0.000001e18,
            "primitive balance should equal expected"
        );
        assertApproxEqRel(
            derivative.balanceOf(address(cellar)),
            expectedDerivativeBalance,
            0.000001e18,
            "derivative balance should equal expected"
        );
    }

    function testWrappingAndUnwrapping(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 1_000e18);
        deal(address(primitive), address(this), amount);
        cellar.deposit(amount, address(this));

        _mintDerivative(amount, 0);

        uint256 derivativeBalance = derivative.balanceOf(address(cellar));

        _wrap(type(uint256).max, 0);

        assertApproxEqAbs(derivative.balanceOf(address(cellar)), 0, 1, "All derivative should be wrapped.");
        assertGt(wrappedDerivative.balanceOf(address(cellar)), 0, "Should have non zero wrapped derivative amount.");

        _unwrap(type(uint256).max, 0);

        assertEq(wrappedDerivative.balanceOf(address(cellar)), 0, "All wrapped derivative should be wrapped.");
        assertApproxEqAbs(
            derivative.balanceOf(address(cellar)),
            derivativeBalance,
            2,
            "Should have expected derivative amount."
        );
    }

    function testWrappingAndUnwrappingMinAmount() external {
        uint256 amount = 10e18;
        deal(address(primitive), address(this), amount);
        cellar.deposit(amount, address(this));

        _mintDerivative(amount, 0);

        uint256 derivativeBalance = derivative.balanceOf(address(cellar));

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    StakingAdaptor.StakingAdaptor__MinimumAmountNotMet.selector,
                    9712554852014822056,
                    type(uint256).max
                )
            )
        );
        _wrap(type(uint256).max, type(uint256).max);

        _wrap(type(uint256).max, 0);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    StakingAdaptor.StakingAdaptor__MinimumAmountNotMet.selector,
                    derivativeBalance - 1,
                    type(uint256).max
                )
            )
        );
        _unwrap(type(uint256).max, type(uint256).max);
    }

    function testHandlingInvalidRequests(uint256 mintAmount) external {
        mintAmount = bound(mintAmount, 0.1e18, 1_000e18);
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));
        uint256 startingTotalAssets = cellar.totalAssets();
        _mintDerivative(mintAmount, 0);
        // Rebalance cellar to start a burn request.
        _startDerivativeBurnRequest(type(uint256).max);

        assertApproxEqAbs(cellar.totalAssets(), startingTotalAssets, 4, "totalAssets should not have changed.");

        uint256 requestId = etherFiAdaptor.requestIds(address(cellar), 0);

        _finalizeRequest(requestId, mintAmount);

        assertApproxEqAbs(cellar.totalAssets(), startingTotalAssets, 4, "totalAssets should not have changed.");

        // Strategist accidentally tries removing the valid request.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__RequestNotClaimed.selector, requestId))
        );
        _removeClaimedRequest(requestId);

        // Simulate a state where somehow the request is claimed without the strategist calling `completeBurn`
        vm.startPrank(address(cellar));
        etherFiAdaptor.withdrawRequestNft().claimWithdraw(requestId);
        etherFiAdaptor.wrappedPrimitive().deposit{ value: address(cellar).balance }();
        vm.stopPrank();

        assertApproxEqAbs(cellar.totalAssets(), startingTotalAssets, 4, "totalAssets should not have changed.");

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
        data[0] = Cellar.AdaptorCall({ adaptor: address(etherFiAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _finalizeRequest(uint256 requestId, uint256 amount) internal {
        // Spoof unstEth contract into finalizing our request.
        IWithdrawRequestNft w = IWithdrawRequestNft(withdrawalRequestNft);
        address owner = w.owner();
        vm.startPrank(owner);
        w.updateAdmin(address(this), true);
        vm.stopPrank();

        ILiquidityPool lp = ILiquidityPool(liquidityPool);

        deal(address(this), amount);
        lp.deposit{ value: amount }();
        address admin = lp.etherFiAdminContract();

        vm.startPrank(admin);
        lp.addEthAmountLockedForWithdrawal(uint128(amount));
        vm.stopPrank();

        w.finalizeRequests(requestId);
    }

    function _startDerivativeBurnRequest(uint256 burnAmount) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRequestBurn(burnAmount, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(etherFiAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _completeDerivativeBurnRequest(uint256 requestId, uint256 minAmountOut) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToCompleteBurn(requestId, minAmountOut, hex"");
        data[0] = Cellar.AdaptorCall({ adaptor: address(etherFiAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _cancelDerivativeBurnRequest(uint256 requestId) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToCancelBurnRequest(requestId, hex"");
        data[0] = Cellar.AdaptorCall({ adaptor: address(etherFiAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _mintDerivative(uint256 mintAmount, uint256 minAmountOut) internal {
        // Rebalance Cellar to mint derivative.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMint(mintAmount, minAmountOut, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(etherFiAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _wrap(uint256 amount, uint256 minAmountOut) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToWrap(amount, minAmountOut, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(etherFiAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _unwrap(uint256 amount, uint256 minAmountOut) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToUnwrap(amount, minAmountOut, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(etherFiAdaptor), callData: adaptorCalls });
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
