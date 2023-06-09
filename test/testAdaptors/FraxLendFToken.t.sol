// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { Registry } from "src/Registry.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import { FTokenAdaptorV1 } from "src/modules/adaptors/Frax/FTokenAdaptorV1.sol";

import { Test, stdStorage, console, StdStorage, stdError } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract FraxLendFTokenAdaptorTest is Test {
    using SafeTransferLib for ERC20;
    using Math for uint256;
    using stdStorage for StdStorage;
    using Address for address;

    ERC20Adaptor private erc20Adaptor;
    FTokenAdaptor private fTokenAdaptorV2;
    FTokenAdaptorV1 private fTokenAdaptor;
    CellarInitializableV2_2 private cellar;
    PriceRouter private priceRouter;
    Registry private registry;

    address private immutable strategist = vm.addr(0xBEEF);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    address private UNTRUSTED_sfrxETH = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15;

    ERC20 public FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // FraxLend fToken pairs.
    address private FXS_FRAX_PAIR = 0xDbe88DBAc39263c47629ebbA02b3eF4cf0752A72;
    address private FPI_FRAX_PAIR = 0x74F82Bd9D0390A4180DaaEc92D64cf0708751759;
    address private SFRXETH_FRAX_PAIR = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15;
    address private WETH_FRAX_PAIR = 0x794F6B13FBd7EB7ef10d1ED205c9a416910207Ff;

    // Chainlink PriceFeeds
    address private FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    uint32 private fraxPosition;
    uint32 private fxsFraxPairPosition;
    uint32 private fpiFraxPairPosition;
    uint32 private sfrxEthFraxPairPosition;
    uint32 private wEthFraxPairPosition;

    modifier checkBlockNumber() {
        if (block.number < 16869780) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16869780.");
            return;
        }
        _;
    }

    function setUp() external {
        fTokenAdaptorV2 = new FTokenAdaptor();
        fTokenAdaptor = new FTokenAdaptorV1();
        erc20Adaptor = new ERC20Adaptor();

        registry = new Registry(address(this), address(this), address(priceRouter));
        priceRouter = new PriceRouter(registry);
        registry.setAddress(2, address(priceRouter));

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(FRAX_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), price);

        price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        // Setup Cellar:

        // Add adaptors and positions to the registry.
        registry.trustAdaptor(address(erc20Adaptor));
        registry.trustAdaptor(address(fTokenAdaptor));
        registry.trustAdaptor(address(fTokenAdaptorV2));

        fraxPosition = registry.trustPosition(address(erc20Adaptor), abi.encode(FRAX));
        fxsFraxPairPosition = registry.trustPosition(address(fTokenAdaptor), abi.encode(FXS_FRAX_PAIR));
        fpiFraxPairPosition = registry.trustPosition(address(fTokenAdaptor), abi.encode(FPI_FRAX_PAIR));
        sfrxEthFraxPairPosition = registry.trustPosition(address(fTokenAdaptorV2), abi.encode(SFRXETH_FRAX_PAIR));
        wEthFraxPairPosition = registry.trustPosition(address(fTokenAdaptor), abi.encode(WETH_FRAX_PAIR));

        cellar = new CellarInitializableV2_2(registry);
        cellar.initialize(
            abi.encode(
                address(this),
                registry,
                FRAX,
                "Fraximal Cellar",
                "oWo",
                fxsFraxPairPosition,
                abi.encode(0),
                strategist
            )
        );

        cellar.addAdaptorToCatalogue(address(fTokenAdaptor));
        cellar.addAdaptorToCatalogue(address(fTokenAdaptorV2));

        cellar.addPositionToCatalogue(fraxPosition);
        cellar.addPositionToCatalogue(fpiFraxPairPosition);
        cellar.addPositionToCatalogue(sfrxEthFraxPairPosition);
        cellar.addPositionToCatalogue(wEthFraxPairPosition);

        FRAX.safeApprove(address(cellar), type(uint256).max);

        // Manipulate test contracts storage so that minimum shareLockPeriod is zero blocks.
        stdstore.target(address(cellar)).sig(cellar.shareLockPeriod.selector).checked_write(uint256(0));
    }

    function testDeposit(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));
    }

    function testWithdraw(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        cellar.withdraw(assets - 2, address(this), address(this));
    }

    function testDepositV2(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        // Adjust Cellar holding position to deposit into a Frax Pair V2.
        cellar.addPosition(0, sfrxEthFraxPairPosition, abi.encode(0), false);
        cellar.setHoldingPosition(sfrxEthFraxPairPosition);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));
    }

    function testWithdrawV2(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        // Adjust Cellar holding position to withdraw from a Frax Pair V2.
        cellar.addPosition(0, sfrxEthFraxPairPosition, abi.encode(0), false);
        cellar.setHoldingPosition(sfrxEthFraxPairPosition);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        cellar.withdraw(assets - 2, address(this), address(this));
    }

    function testTotalAssets(uint256 assets) external {
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));
        assertApproxEqAbs(cellar.totalAssets(), assets, 2, "Total assets should equal assets deposited.");
    }

    function testLendingFrax(uint256 assets) external {
        // Add FRAX position and change holding position to vanilla FRAX.
        cellar.addPosition(0, fraxPosition, abi.encode(0), false);
        cellar.setHoldingPosition(fraxPosition);

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to lend FRAX.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend FRAX on FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(FXS_FRAX_PAIR, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        IFToken pair = IFToken(FXS_FRAX_PAIR);
        uint256 shareBalance = pair.balanceOf(address(cellar));
        assertTrue(shareBalance > 0, "Cellar should own shares.");
        assertApproxEqAbs(
            pair.toAssetAmount(shareBalance, false),
            assets,
            2,
            "Rebalance should have lent all FRAX on FraxLend."
        );
    }

    function testWithdrawingFrax(uint256 assets) external {
        // Add vanilla FRAX as a position in the cellar.
        cellar.addPosition(0, fraxPosition, abi.encode(0), false);

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to withdraw FRAX.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Withdraw FRAX from FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeem(FXS_FRAX_PAIR, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        assertApproxEqAbs(
            FRAX.balanceOf(address(cellar)),
            assets,
            2,
            "Cellar FRAX should have been withdraw from FraxLend."
        );
    }

    function testRebalancingBetweenPairs(uint256 assets) external {
        // Add another Frax Lend pair, and vanilla FRAX.
        cellar.addPosition(0, sfrxEthFraxPairPosition, abi.encode(0), false);
        cellar.addPosition(0, fraxPosition, abi.encode(0), false);

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to withdraw FRAX, and lend in a different pair.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
        // Withdraw FRAX from FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeem(FXS_FRAX_PAIR, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(SFRXETH_FRAX_PAIR, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        IFToken pair = IFToken(SFRXETH_FRAX_PAIR);
        uint256 shareBalance = pair.balanceOf(address(cellar));
        assertTrue(shareBalance > 0, "Cellar should own shares.");
        assertApproxEqAbs(
            pair.toAssetAmount(shareBalance, false, false),
            assets,
            10,
            "Rebalance should have lent in other pair."
        );

        // Withdraw half the assets from Frax Pair V2.
        data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdraw(SFRXETH_FRAX_PAIR, assets / 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);

        assertEq(FRAX.balanceOf(address(cellar)), assets / 2, "Should have withdrawn half the assets from FraxLend.");
    }

    // try lending and redeemin with fTokens that are not positions in the cellar and check for revert.
    function testUsingPairNotSetupAsPosition(uint256 assets) external {
        // Add FRAX position and change holding position to vanilla FRAX.
        cellar.addPosition(0, fraxPosition, abi.encode(0), false);
        cellar.setHoldingPosition(fraxPosition);

        // Have user deposit into cellar.
        assets = bound(assets, 0.01e18, 100_000_000e18);
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Strategist rebalances to lend FRAX.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        // Lend FRAX on FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(UNTRUSTED_sfrxETH, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    FTokenAdaptor.FTokenAdaptor__FTokenPositionsMustBeTracked.selector,
                    (UNTRUSTED_sfrxETH)
                )
            )
        );
        cellar.callOnAdaptor(data);

        address maliciousContract = vm.addr(87345834);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeem(maliciousContract, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    FTokenAdaptor.FTokenAdaptor__FTokenPositionsMustBeTracked.selector,
                    (maliciousContract)
                )
            )
        );
        cellar.callOnAdaptor(data);

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdraw(maliciousContract, assets);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    FTokenAdaptor.FTokenAdaptor__FTokenPositionsMustBeTracked.selector,
                    (maliciousContract)
                )
            )
        );
        cellar.callOnAdaptor(data);
    }

    // Check that FRAX in multiple different pairs is correctly accounted for in total assets.
    function testMultiplePositionsTotalAssets(uint256 assets) external {
        // Have user deposit into cellar
        assets = bound(assets, 0.01e18, 100_000_000e18);
        uint256 expectedAssets = assets;
        uint256 dividedAssetPerMultiPair = assets / 3; // amount of FRAX to distribute between different fraxLendPairs
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Test that users can withdraw from multiple pairs at once.
        _setupMultiplePositions(dividedAssetPerMultiPair);

        assertApproxEqAbs(expectedAssets, cellar.totalAssets(), 10, "Total assets should have been lent out");
    }

    // Check that user able to withdraw from multiple lending positions outright
    function testMultiplePositionsUserWithdraw(uint256 assets) external {
        // Have user deposit into cellar
        assets = bound(assets, 0.01e18, 100_000_000e18);
        uint256 dividedAssetPerMultiPair = assets / 3; // amount of FRAX to distribute between different fraxLendPairs
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        // Test that users can withdraw from multiple pairs at once.
        _setupMultiplePositions(dividedAssetPerMultiPair);

        deal(address(FRAX), address(this), 0);
        uint256 toWithdraw = cellar.maxWithdraw(address(this));
        cellar.withdraw(toWithdraw, address(this), address(this));

        assertApproxEqAbs(
            FRAX.balanceOf(address(this)),
            toWithdraw,
            10,
            "User should have gotten all their FRAX (minus some dust)"
        );
    }

    function testWithdrawableFrom() external {
        // Make cellar deposits lend FRAX into WETH Pair.
        cellar.addPosition(0, wEthFraxPairPosition, abi.encode(0), false);
        cellar.setHoldingPosition(wEthFraxPairPosition);

        uint256 assets = 10_000e18;
        deal(address(FRAX), address(this), assets);
        cellar.deposit(assets, address(this));

        address whaleBorrower = vm.addr(777);

        // Figure out how much the whale must borrow to borrow all the Frax.
        IFToken fToken = IFToken(WETH_FRAX_PAIR);
        (uint128 totalFraxSupplied, , uint128 totalFraxBorrowed, , ) = fToken.getPairAccounting();
        uint256 assetsToBorrow = totalFraxSupplied > totalFraxBorrowed ? totalFraxSupplied - totalFraxBorrowed : 0;
        // Supply 2x the value we are trying to borrow.
        uint256 assetsToSupply = priceRouter.getValue(FRAX, 2 * assetsToBorrow, WETH);

        deal(address(WETH), whaleBorrower, assetsToSupply);
        vm.startPrank(whaleBorrower);
        WETH.approve(WETH_FRAX_PAIR, assetsToSupply);
        fToken.borrowAsset(assetsToBorrow, assetsToSupply, whaleBorrower);
        vm.stopPrank();

        uint256 assetsWithdrawable = cellar.totalAssetsWithdrawable();

        assertEq(assetsWithdrawable, 0, "There should be no assets withdrawable.");

        // Whale repays half of their debt.
        uint256 sharesToRepay = fToken.balanceOf(whaleBorrower) / 2;
        vm.startPrank(whaleBorrower);
        FRAX.approve(WETH_FRAX_PAIR, assetsToBorrow);
        fToken.repayAsset(sharesToRepay, whaleBorrower);
        vm.stopPrank();

        (totalFraxSupplied, , totalFraxBorrowed, , ) = fToken.getPairAccounting();
        uint256 liquidFrax = totalFraxSupplied - totalFraxBorrowed;

        assetsWithdrawable = cellar.totalAssetsWithdrawable();

        assertEq(assetsWithdrawable, liquidFrax, "Should be able to withdraw liquid FRAX.");

        // Have user withdraw the FRAX.
        deal(address(FRAX), address(this), 0);
        cellar.withdraw(liquidFrax, address(this), address(this));
        assertEq(FRAX.balanceOf(address(this)), liquidFrax, "User should have received liquid FRAX.");
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _createBytesDataToLend(address fToken, uint256 amountToDeposit) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.lendFrax.selector, fToken, amountToDeposit);
    }

    function _createBytesDataToRedeem(address fToken, uint256 amountToRedeem) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.redeemFraxShare.selector, fToken, amountToRedeem);
    }

    function _createBytesDataToWithdraw(address fToken, uint256 amountToWithdraw) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.withdrawFrax.selector, fToken, amountToWithdraw);
    }

    // setup multiple lending positions
    function _setupMultiplePositions(uint256 dividedAssetPerMultiPair) internal {
        // add numerous frax pairs atop of holdingPosition (fxs)
        cellar.addPosition(0, sfrxEthFraxPairPosition, abi.encode(0), false);
        cellar.addPosition(0, fpiFraxPairPosition, abi.encode(0), false);

        // Strategist rebalances to withdraw set amount of FRAX, and lend in a different pair.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        // Withdraw 2/3 of cellar FRAX from FraxLend.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRedeem(FXS_FRAX_PAIR, dividedAssetPerMultiPair * 2);
            data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(SFRXETH_FRAX_PAIR, dividedAssetPerMultiPair);
            data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(FPI_FRAX_PAIR, type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        cellar.callOnAdaptor(data);
    }
}
