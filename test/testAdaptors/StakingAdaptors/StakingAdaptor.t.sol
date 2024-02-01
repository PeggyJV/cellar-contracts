// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { StakingAdaptor } from "src/modules/adaptors/Staking/StakingAdaptor.sol";
import { CellarWithNativeSupport } from "src/base/permutations/CellarWithNativeSupport.sol";
import { WstEthExtension } from "src/modules/price-router/Extensions/Lido/WstEthExtension.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract StakingAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    StakingAdaptor private stakingAdaptor;
    CellarWithNativeSupport private cellar;

    uint32 public wethPosition = 1;

    ERC20 public primitive = WETH;
    ERC20 public derivative = ERC20(address(0));
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

        stakingAdaptor = new StakingAdaptor(address(WETH), maxRequests);

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(stakingAdaptor));

        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));

        string memory cellarName = "Generic Staking Cellar V0.0";
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

        cellar.addAdaptorToCatalogue(address(stakingAdaptor));

        cellar.setRebalanceDeviation(0.01e18);

        initialAssets = initialDeposit;

        WETH.safeApprove(address(cellar), type(uint256).max);
    }

    function testReverts() external {
        // Zero amount reverts.
        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__ZeroAmount.selector)));
        _mintDerivative(0);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__ZeroAmount.selector)));
        _startDerivativeBurnRequest(0);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__ZeroAmount.selector)));
        _wrap(0);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__ZeroAmount.selector)));
        _unwrap(0);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__ZeroAmount.selector)));
        _mintDerivativeERC20(primitive, 0, 0);

        // Function not implemented revert.
        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__NotSupported.selector)));
        _mintDerivative(1);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__NotSupported.selector)));
        _startDerivativeBurnRequest(1);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__NotSupported.selector)));
        _completeDerivativeBurnRequest(0);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__NotSupported.selector)));
        _cancelDerivativeBurnRequest(0);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__NotSupported.selector)));
        _wrap(1);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__NotSupported.selector)));
        _unwrap(1);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__NotSupported.selector)));
        _mintDerivativeERC20(primitive, 1, 0);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__NotSupported.selector)));
        _removeClaimedRequest(0);

        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__NotSupported.selector)));
        stakingAdaptor.balanceOf(abi.encode());

        uint256 requestId = 777;

        // Request not found revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__RequestNotFound.selector, requestId))
        );
        stakingAdaptor.removeRequestId(requestId);

        // Duplicate request revert.
        stakingAdaptor.addRequestId(requestId);
        vm.expectRevert(
            bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__DuplicateRequest.selector, requestId))
        );
        stakingAdaptor.addRequestId(requestId);

        // Maximum requests revert.
        for (uint256 i; i < maxRequests - 1; ++i) {
            stakingAdaptor.addRequestId(i);
        }
        vm.expectRevert(bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor__MaximumRequestsExceeded.selector)));
        stakingAdaptor.addRequestId(maxRequests);

        // If caller makes a delegate call to adaptors requestId management functions it should revert.
        bytes memory callData = abi.encodeWithSelector(StakingAdaptor.addRequestId.selector, 0);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor___StorageSlotNotInitialized.selector))
        );
        address(stakingAdaptor).functionDelegateCall(callData);

        callData = abi.encodeWithSelector(StakingAdaptor.removeRequestId.selector, 0);

        vm.expectRevert(
            bytes(abi.encodeWithSelector(StakingAdaptor.StakingAdaptor___StorageSlotNotInitialized.selector))
        );
        address(stakingAdaptor).functionDelegateCall(callData);
    }

    function _startDerivativeBurnRequest(uint256 burnAmount) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRequestBurn(burnAmount, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(stakingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _completeDerivativeBurnRequest(uint256 requestId) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToCompleteBurn(requestId, 0, hex"");
        data[0] = Cellar.AdaptorCall({ adaptor: address(stakingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _cancelDerivativeBurnRequest(uint256 requestId) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToCancelBurnRequest(requestId, hex"");
        data[0] = Cellar.AdaptorCall({ adaptor: address(stakingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _removeClaimedRequest(uint256 requestId) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToRemoveClaimedRequest(requestId, hex"");
        data[0] = Cellar.AdaptorCall({ adaptor: address(stakingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _mintDerivative(uint256 mintAmount) internal {
        // Rebalance Cellar to mint derivative.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMint(mintAmount, 0, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(stakingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _wrap(uint256 amount) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToWrap(amount, 0, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(stakingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _unwrap(uint256 amount) internal {
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToUnwrap(amount, 0, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(stakingAdaptor), callData: adaptorCalls });
        cellar.callOnAdaptor(data);
    }

    function _mintDerivativeERC20(ERC20 depositAsset, uint256 mintAmount, uint256 minMintAmountOut) internal {
        // Rebalance Cellar to mint derivative.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = _createBytesDataToMintERC20(depositAsset, mintAmount, minMintAmountOut, hex"");

        data[0] = Cellar.AdaptorCall({ adaptor: address(stakingAdaptor), callData: adaptorCalls });
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
