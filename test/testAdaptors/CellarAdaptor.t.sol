// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";

// Import Everything from Starter file.
import "test/resources/MainnetStarter.t.sol";

import { AdaptorHelperFunctions } from "test/resources/AdaptorHelperFunctions.sol";

contract CellarAdaptorTest is MainnetStarterTest, AdaptorHelperFunctions {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;

    CellarAdaptor private cellarAdaptor;
    Cellar private cellar;

    uint32 private usdcPosition = 1;
    uint32 private wethPosition = 2;
    uint32 private cellarPosition = 3;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 16869780;
        _startFork(rpcKey, blockNumber);

        // Run Starter setUp code.
        _setUp();

        cellarAdaptor = new CellarAdaptor();

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(cellarAdaptor));

        registry.trustPosition(usdcPosition, address(erc20Adaptor), abi.encode(USDC));
        registry.trustPosition(wethPosition, address(erc20Adaptor), abi.encode(WETH));

        string memory cellarName = "Dummy Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        cellar = _createCellar(cellarName, USDC, usdcPosition, abi.encode(true), initialDeposit, platformCut);

        cellar.setRebalanceDeviation(0.01e18);

        USDC.safeApprove(address(cellar), type(uint256).max);
    }

    function testUsingIlliquidCellarPosition() external {
        registry.trustPosition(cellarPosition, address(cellarAdaptor), abi.encode(address(cellar)));

        string memory cellarName = "Meta Cellar V0.0";
        uint256 initialDeposit = 1e6;
        uint64 platformCut = 0.75e18;

        Cellar metaCellar = _createCellar(
            cellarName,
            USDC,
            usdcPosition,
            abi.encode(true),
            initialDeposit,
            platformCut
        );
        uint256 initialAssets = metaCellar.totalAssets();

        metaCellar.addPositionToCatalogue(cellarPosition);
        metaCellar.addAdaptorToCatalogue(address(cellarAdaptor));
        metaCellar.addPosition(0, cellarPosition, abi.encode(false), false);
        metaCellar.setHoldingPosition(cellarPosition);

        USDC.safeApprove(address(metaCellar), type(uint256).max);

        // Deposit into meta cellar.
        uint256 assets = 100_000e6;
        deal(address(USDC), address(this), assets);

        metaCellar.deposit(assets, address(this));

        uint256 assetsDeposited = cellar.totalAssets();
        assertEq(assetsDeposited, assets + initialAssets, "All assets should have been deposited into cellar.");

        uint256 liquidAssets = metaCellar.maxWithdraw(address(this));
        assertEq(
            liquidAssets,
            initialAssets,
            "Meta Cellar only liquid assets should be USDC deposited in constructor."
        );

        // Check logic in the withdraw function by having strategist call withdraw, passing in isLiquid = false.
        bool isLiquid = false;
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        bytes[] memory adaptorCalls = new bytes[](1);
        adaptorCalls[0] = abi.encodeWithSelector(
            CellarAdaptor.withdraw.selector,
            assets,
            address(this),
            abi.encode(cellar),
            abi.encode(isLiquid)
        );

        data[0] = Cellar.AdaptorCall({ adaptor: address(cellarAdaptor), callData: adaptorCalls });

        vm.expectRevert(bytes(abi.encodeWithSelector(BaseAdaptor.BaseAdaptor__UserWithdrawsNotAllowed.selector)));
        metaCellar.callOnAdaptor(data);
    }
}
