// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { LidoStakingAdaptor, StakingAdaptor } from "src/modules/adaptors/Staking/LidoStakingAdaptor.sol";
import { CellarWithNativeSupport } from "src/base/permutations/CellarWithNativeSupport.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract LidoStakingAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    LidoStakingAdaptor private lidoAdaptor;
    CellarWithNativeSupport private cellar;
    WstEthExtension private wstethExtension;

    uint32 public wethPosition = 1;
    uint32 public stEthPosition = 2;
    uint32 public wstEthPosition = 3;
    uint32 public lidoPosition = 4;

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

        lidoAdaptor = new LidoStakingAdaptor(address(WETH), maxRequests, address(STETH), address(WSTETH), unstETH);
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

    function testMint(uint256 mintAmount) external {
        mintAmount = bound(mintAmount, 0.0001e18, 10_000e18);
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));

        // Rebalance Cellar to mint derivative.
        _mintDerivative(mintAmount, 0, hex"");

        assertApproxEqAbs(
            primitive.balanceOf(address(cellar)),
            initialAssets,
            2,
            "Should only have initialAssets of primitive left."
        );
        assertApproxEqAbs(
            derivative.balanceOf(address(cellar)),
            mintAmount,
            2,
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
        _mintDerivative(mintAmount, type(uint256).max, hex"");
    }

    // The max steth withdrawal amount is 1k.
    function testBurn(uint256 mintAmount) external {
        mintAmount = bound(mintAmount, 0.0001e18, 1_000e18);
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));

        // Save the last checkpoint
        uint256 lastCheckpoint = lidoAdaptor.unstETH().getLastCheckpointIndex();

        uint256 startingTotalAssets = cellar.totalAssets();

        _mintDerivative(mintAmount, 0, hex"");

        uint256 burnAmount = derivative.balanceOf(address(cellar));

        // Rebalance cellar to start a burn request.
        _startDerivativeBurnRequest(burnAmount, hex"");

        assertApproxEqAbs(cellar.totalAssets(), startingTotalAssets, 2, "totalAssets should not have changed.");

        uint256 requestId = lidoAdaptor.requestIds(address(cellar), 0);

        _finalizeRequest(requestId, mintAmount);

        assertApproxEqAbs(cellar.totalAssets(), startingTotalAssets, 2, "totalAssets should not have changed.");

        // Rebalance cellar to finalize burn request, specify a hint.
        _completeDerivativeBurnRequest(requestId, 0, abi.encode(lastCheckpoint + 1));

        assertApproxEqAbs(cellar.totalAssets(), startingTotalAssets, 2, "totalAssets should not have changed.");

        assertApproxEqAbs(
            primitive.balanceOf(address(cellar)),
            startingTotalAssets,
            2,
            "Cellar should have all assets in primitive."
        );
    }

    function testBurnMinAmount() external {
        uint256 mintAmount = 10e18;
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));

        _mintDerivative(mintAmount, 0, hex"");

        uint256 burnAmount = derivative.balanceOf(address(cellar));

        // Rebalance cellar to start a burn request.
        _startDerivativeBurnRequest(burnAmount, hex"");

        uint256 requestId = lidoAdaptor.requestIds(address(cellar), 0);

        _finalizeRequest(requestId, mintAmount);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    StakingAdaptor.StakingAdaptor__MinimumAmountNotMet.selector,
                    mintAmount - 1,
                    type(uint256).max
                )
            )
        );
        _completeDerivativeBurnRequest(requestId, type(uint256).max, hex"");
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

            _mintDerivative(mintAmounts[i], 0, hex"");
            burnAmount = derivative.balanceOf(address(cellar));
            _startDerivativeBurnRequest(burnAmount, hex"");

            requests = lidoAdaptor.getRequestIds(address(cellar));
            assertEq(requests.length, i + 1, "Should have i + 1 requests.");
        }

        // Making 1 more burn request should revert.
        _mintDerivative(initialAssets, 0, hex"");
        burnAmount = derivative.balanceOf(address(cellar));
        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__MaximumRequestsExceeded.selector)));
        _startDerivativeBurnRequest(burnAmount, hex"");

        // Finalize requests.
        for (uint256 i; i < maxRequests; ++i) {
            uint256 requestId = lidoAdaptor.requestIds(address(cellar), i);

            _finalizeRequest(requestId, mintAmounts[i]);
        }

        // Complete requests.
        for (uint256 i; i < maxRequests; ++i) {
            uint256 requestId = lidoAdaptor.requestIds(address(cellar), 0);
            _completeDerivativeBurnRequest(requestId, 0, hex"");
        }
        requests = lidoAdaptor.getRequestIds(address(cellar));
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

        _mintDerivative(amount, 0, hex"");

        uint256 derivativeBalance = derivative.balanceOf(address(cellar));

        _wrap(type(uint256).max, 0, hex"");

        assertApproxEqAbs(derivative.balanceOf(address(cellar)), 0, 1, "All derivative should be wrapped.");
        assertGt(wrappedDerivative.balanceOf(address(cellar)), 0, "Should have non zero wrapped derivative amount.");

        _unwrap(type(uint256).max, 0, hex"");

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

        _mintDerivative(amount, 0, hex"");

        uint256 derivativeBalance = derivative.balanceOf(address(cellar));

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    StakingAdaptor.StakingAdaptor__MinimumAmountNotMet.selector,
                    8659557570908870932,
                    type(uint256).max
                )
            )
        );
        _wrap(type(uint256).max, type(uint256).max, hex"");

        _wrap(type(uint256).max, 0, hex"");

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    StakingAdaptor.StakingAdaptor__MinimumAmountNotMet.selector,
                    derivativeBalance - 1,
                    type(uint256).max
                )
            )
        );
        _unwrap(type(uint256).max, type(uint256).max, hex"");
    }

    function testHandlingInvalidRequests(uint256 mintAmount) external {
        mintAmount = bound(mintAmount, 0.0001e18, 1_000e18);
        deal(address(primitive), address(this), mintAmount);
        cellar.deposit(mintAmount, address(this));

        uint256 startingTotalAssets = cellar.totalAssets();

        _mintDerivative(mintAmount, 0, hex"");

        uint256 burnAmount = derivative.balanceOf(address(cellar));

        // Rebalance cellar to start a burn request.
        _startDerivativeBurnRequest(burnAmount, hex"");

        uint256 requestId = lidoAdaptor.requestIds(address(cellar), 0);

        _finalizeRequest(requestId, mintAmount);

        assertApproxEqAbs(cellar.totalAssets(), startingTotalAssets, 2, "totalAssets should not have changed.");

        // Strategist accidentally tries removing the valid request.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__RequestNotClaimed.selector, requestId))
        );
        _removeClaimedRequest(requestId, hex"");

        // Simulate a state where somehow the request is claimed without the strategist calling `completeBurn`
        vm.startPrank(address(cellar));
        lidoAdaptor.unstETH().claimWithdrawal(requestId);
        lidoAdaptor.wrappedPrimitive().deposit{ value: address(cellar).balance }();
        vm.stopPrank();

        // TotalAssets should remain the unchanged since the withdrawn assets go into an ERC20 position.
        // And staking adaptor does not account for value in request because it is not valid.
        assertApproxEqAbs(cellar.totalAssets(), startingTotalAssets, 2, "totalAssets should not have changed.");

        // Strategist should now be able to remove the request.
        _removeClaimedRequest(requestId, hex"");

        // But if they try to remove it again it reverts.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__RequestNotFound.selector, requestId))
        );
        _removeClaimedRequest(requestId, hex"");
    }

    function _removeClaimedRequest(uint256 requestId, bytes memory wildcard) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRemoveClaimedRequest(requestId, wildcard);
        data[0] = Cellar.AdaptorCall({ adaptor: address(lidoAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _finalizeRequest(uint256 requestId, uint256 amount) internal {
        // Spoof unstEth contract into finalizing our request.
        address admin = lidoAdaptor.unstETH().getRoleMember(lidoAdaptor.unstETH().FINALIZE_ROLE(), 0);
        deal(admin, amount);
        vm.startPrank(admin);
        lidoAdaptor.unstETH().finalize{ value: amount }(requestId, type(uint256).max);
        vm.stopPrank();
    }

    function _startDerivativeBurnRequest(uint256 burnAmount, bytes memory wildcard) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRequestBurn(burnAmount, wildcard);

        data[0] = Cellar.AdaptorCall({ adaptor: address(lidoAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _completeDerivativeBurnRequest(uint256 requestId, uint256 minAmountOut, bytes memory wildcard) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToCompleteBurn(requestId, minAmountOut, wildcard);
        data[0] = Cellar.AdaptorCall({ adaptor: address(lidoAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _mintDerivative(uint256 mintAmount, uint256 minAmountOut, bytes memory wildcard) internal {
        // Rebalance Cellar to mint derivative.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMint(mintAmount, minAmountOut, wildcard);

        data[0] = Cellar.AdaptorCall({ adaptor: address(lidoAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _wrap(uint256 amount, uint256 minAmountOut, bytes memory wildcard) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToWrap(amount, minAmountOut, wildcard);

        data[0] = Cellar.AdaptorCall({ adaptor: address(lidoAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _unwrap(uint256 amount, uint256 minAmountOut, bytes memory wildcard) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToUnwrap(amount, minAmountOut, wildcard);

        data[0] = Cellar.AdaptorCall({ adaptor: address(lidoAdaptor), callData: adaptorCalls });
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
