// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
// import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { MorphoAaveV3ATokenP2PAdaptor, IMorphoV3, BaseAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenP2PAdaptor.sol";
import { MorphoAaveV3ATokenCollateralAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3ATokenCollateralAdaptor.sol";
import { MorphoAaveV3DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV3DebtTokenAdaptor.sol";
import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";

/**
 * @title MorphoAaveV3AdaptorIntegrations
 * @author 0xEinCodes and CrispyMangoes
 * @notice Integrations tests for MorphoAaveV3 Deployment
 * High-Level test scope includes:
 * 1.) Deploy Morpho Adaptors and positions into RYE cellar. Deposit wstETH to Morpho position. In the same tx, borrow wETH against it. Do checks. Then repay it. Finally withdraw it all.
 * 2.) Test RYE cellar lending wETH p2p on morpho v3 and withdraw
 * NOTES: Depositing into Morpho disperses the lending to P2P or other automatically. That is on the Morpho protocol to handle.
 */
contract MorphoAaveV3AdaptorIntegrations is Test {
    using Math for uint256;

    // Sommelier Specific Deployed Mainnet Addresses
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    CellarInitializableV2_2 private rye = CellarInitializableV2_2(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);

    IMorphoV3 private morpho = IMorphoV3(0x33333aea097c193e66081E930c33020272b33333);

    // General Mainnet Addresses
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant WstEth = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    // Aave-Specific Addresses
    ERC20 private constant aWstETH = ERC20(0x0B925eD163218f6662a35e0f0371Ac234f9E9371);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    MorphoAaveV3ATokenCollateralAdaptor public morphoAaveV3ATokenAdaptor =
        MorphoAaveV3ATokenCollateralAdaptor(0xB46E8a03b1AaFFFb50f281397C57b5B87080363E);
    MorphoAaveV3DebtTokenAdaptor public morphoAaveV3DebtTokenAdaptor =
        MorphoAaveV3DebtTokenAdaptor(0x25a61f771aF9a38C10dDd93c2bBAb39a88926fa9);
    MorphoAaveV3ATokenP2PAdaptor public morphoAaveV3P2PAdaptor =
        MorphoAaveV3ATokenP2PAdaptor(0x4fe068cAaD05B82bf3F86E1F7d1A7b8bbf516111);

    address public erc20Adaptor = 0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE;

    uint32 oldRyePosition = 143;
    uint32 aaveV3DebtWethPosition = 114;

    uint32 morphoAaveV3AWstETHPosition = 163;
    uint32 morphoV3P2PWETHPosition = 162;
    uint32 morphoAaveV3DebtWETHPosition = 166;
    uint32 vanillaWSTETHPosition = 142;
    uint32 vanillaWETHPosition = 101;
    uint32 morphoAaveV2WethDebtPosition = 132;
    uint32 morphoAaveV2WethDebtPosition = 132;

    modifier checkBlockNumber() {
        if (block.number < 17579366) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 17579366.");
            return;
        }
        _;
    }

    function setUp() external {
        // Setup positions and CataloguePositions for RYE with WstETH, WETH, MorphoAaveV3AToken && MorphoAaveV3DebtToken

        // TODO: Crispy - the registry has already trusted the adaptors and associated positions right? If YES, then delete the below commented out code blob
        // vm.prank(multisig);
        // // NOTE: uniswapAdaptor and erc20Adaptor should already be trusted adaptors for RYE
        // registry.trustAdaptor(address(morphoAaveV3ATokenAdaptor));
        // registry.trustAdaptor(address(morphoAaveV3DebtTokenAdaptor));
        // registry.trustAdaptor(address(morphoAaveV3P2PAdaptor));
        // morphoAWethPosition = registry.trustPosition(address(p2pATokenAdaptor), abi.encode(WETH));
        // morphoAWstEthPosition = registry.trustPosition(address(collateralATokenAdaptor), abi.encode(WSTETH));
        // morphoDebtWethPosition = registry.trustPosition(address(debtTokenAdaptor), abi.encode(WETH));
        // vm.stopPrank();

        // setup positions in rye cellar
        vm.prank(gravityBridge);

        rye.addAdaptorToCatalogue(address(morphoAaveV3P2PAdaptor));
        rye.addAdaptorToCatalogue(address(morphoAaveV3ATokenAdaptor));
        rye.addAdaptorToCatalogue(address(morphoAaveV3DebtTokenAdaptor));
        rye.addPositionToCatalogue(morphoAaveV3AWstETHPosition);
        rye.addPositionToCatalogue(morphoAaveV3DebtWETHPosition);
        rye.addPositionToCatalogue(morphoAaveV3AWstETHPosition);
        rye.addPositionToCatalogue(vanillaWSTETHPosition);

        // TODO: Crispy - not sure if it starts at position index 0 right now. Need to check.
        rye.addPosition(0, vanillaWETHPosition, abi.encode(0), false); // TODO: I don't think I need this but I have it for now since it was used in unit tests. Could generate position ID and check what is in RYE beforehand.
        rye.addPosition(1, vanillaWSTETHPosition, abi.encode(0), false);
        rye.addPosition(2, morphoAaveV3AWstETHPosition, abi.encode(0), false);
        rye.addPosition(3, morphoV3P2PWETHPosition, abi.encode(0), false);
        rye.addPosition(0, morphoAaveV3DebtWETHPosition, abi.encode(0), true);
        vm.stopPrank();
    }

    // @notice test lending wstETH, borrowing wETH against it, and repaying it.
    function testMorphoAaveV3LendBorrowRepay() external {
        // have RYE w/ liquid wstETH ready to lend into Morpho
        deal(address(WstEth), address(rye), 1_000_000e18);
        deal(address(WETH), address(rye), 0);
        console.log("WstEthBalance: %S", WstEth.balanceOf(address(rye)));
        // deposit into Morpho

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);

        // // TODO: only uncomment if I can't deal wSTETH to myself. Swap WETH for WSTETH.
        // {
        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataForSwap(WETH, WSTETH, 500, assets);
        //     data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        // }

        // Supply WSTETH as collateral on Morpho.
        uint256 wethToBorrow = 1_000_000e18 / 4;
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(WstEth, type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV3ATokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(WETH, wethToBorrow, 4);
            data[2] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV3DebtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        vm.prank(gravityBridge);
        rye.callOnAdaptor(data);

        // Check Morpho balances (supplied wstETH, borrowed wETH)

        console.log("RYE WstETHBalanceAfterLend %s", WstEth.balanceOf(address(rye)));
        console.log("RYE WETHBalanceAfterBorrow %s", WETH.balanceOf(address(rye)));

        assertApproxEqAbs(WstEth.balanceOf(address(rye)), 0, 1, "RYE wstETH balance should equal zero.");
        assertApproxEqAbs(
            WETH.balanceOf(address(rye)),
            wethToBorrow,
            1,
            "RYE WETH balance should equal  amount borrowed from Morpho"
        );

        // Make sure that Cellar has provided collateral to Morpho
        // TODO:
        assertApproxEqAbs(
            morpho.collateralBalance(address(WstEth), address(rye)),
            1_000_000e18,
            1,
            "Morpho balance should equal assets dealt. "
        );
        // Make sure that Cellar has borrowed from Morpho.
        uint256 wethDebt = morpho.borrowBalance(address(WETH), address(rye));

        assertApproxEqAbs(wethDebt, wethToBorrow, 1, "WETH debt should equal assets / 4.");

        // setup repayment phase of test
        uint256 borrowedWETH = WETH.balanceOf(address(rye));
        uint256 newTestWETH = borrowedWETH + 1 ether; // adding for any dust lost
        uint256 expectedFinalWETH = newTestWETH - borrowedWETH;
        deal(address(WETH), address(rye), newTestWETH); // deal more weth for repay due to lost dust in txs
        Cellar.AdaptorCall[] memory data2 = new Cellar.AdaptorCall[](1);

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRepay(WETH, type(uint256).max);
            data2[1] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV3DebtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        vm.prank(gravityBridge);
        rye.callOnAdaptor(data2);

        uint256 wethRemaining = newTestWETH - WETH.balanceOf(address(rye));

        // Checks that the cellar can use the Aave v3 Morpho adaptors
        console.log("RYE WstETHBalanceAfterLend %s", WstEth.balanceOf(address(rye)));
        console.log("RYE WETHBalanceAfterBorrow %s", WETH.balanceOf(address(rye)));

        assertApproxEqAbs(
            WstEth.balanceOf(address(rye)),
            0,
            1,
            "RYE wstETH balance should equal zero since it is still in Morpho."
        );
        assertApproxEqAbs(
            WETH.balanceOf(address(rye)),
            expectedFinalWETH,
            10,
            "RYE WETH borrowed should be returned now."
        );
        assertApproxEqAbs(
            morpho.collateralBalance(address(WstEth), address(rye)),
            1_000_000e18,
            1,
            "Morpho balance should equal assets dealt. "
        );
        assertApproxEqAbs(
            WETH.balanceOf(address(rye)),
            wethToBorrow,
            1,
            "After Repayment: rye WETH debt should be zero in Morpho."
        );

        uint256 maxAssets = rye.maxWithdraw(address(this));
        rye.withdraw(maxAssets, address(this), address(this));
        uint256 expectedOut = priceRouter.getValue(WETH, maxAssets, WstEth);
        assertApproxEqAbs(
            WstEth.balanceOf(address(this)),
            expectedOut,
            1,
            "Withdraw should have sent collateral assets to user."
        );
    }

    // @notice test RYE lending wETH p2p on morpho v3 and withdraw
    // NOTE: not sure if we use the same mutative functions within morpho to just supply vs supplying collateral and lend.
    function testMorphoAaveV3LendWETH() external {
        // initialize new cellar that will have holding position as MorphoAaveV3P2P

        uint256 assets = 1_000_000e18;
        uint256 maxDelta = 10; // adjust for dust loss
        CellarInitializableV2_2 morphoP2PCellar;

        vm.startPrank(gravityBridge);
        morphoP2PCellar = new CellarInitializableV2_2(registry);
        // morphoV3P2PWETHPosition is already registered. It is not added to the adaptor position catalogue though yet.
        morphoP2PCellar.initialize(
            abi.encode(
                address(this),
                registry,
                WETH,
                "MORPHO P2P Cellar",
                "MORPHO-P2P-CLR",
                morphoV3P2PWETHPosition,
                abi.encode(4),
                address(this)
            )
        );

        // TODO: add adaptors to catalogues.
        morphoP2PCellar.addAdaptorToCatalogue(address(p2pATokenAdaptor)); //
        morphoP2PCellar.addAdaptorToCatalogue(address(collateralATokenAdaptor));
        morphoP2PCellar.addAdaptorToCatalogue(address(debtTokenAdaptor));

        morphoP2PCellar.addPositionToCatalogue(vanillaWETHPosition);
        morphoP2PCellar.addPositionToCatalogue(morphoV3P2PWETHPosition);

        vm.stopPrank(); // now cellar is set for holding position

        // have RYE w/ liquid WETH ready to lend into Morpho
        deal(address(WETH), address(rye), 0);

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);

        // Supply WETH as collateral p2p on Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLendP2P(WETH, type(uint256).max, 4);
            data[2] = Cellar.AdaptorCall({ adaptor: address(p2pATokenAdaptor), callData: adaptorCalls });
        }

        morphoP2PCellar.callOnAdaptor(data);
        uint256 wethMorphoNewBalance = getMorphoBalance(WETH, address(rye));
        uint256 ryeWETHBalance = WETH.balanceOf(address(rye));

        assertApproxEqAbs(
            wethMorphoNewBalance,
            assets,
            maxDelta,
            "P2PIntegrationTest: All WETH lent out through Morpho"
        );
        assertApproxEqAbs(
            ryeWETHBalance,
            0,
            maxDelta,
            "P2PIntegrationTest: All rye WETH should be in Morpho, not in cellar"
        );

        // withdraw
        uint256 maxAssets = rye.maxWithdraw(address(this));
        rye.withdraw(maxAssets, address(this), address(this));
        assertApproxEqAbs(
            WETH.balanceOf(address(this)),
            assets,
            10,
            "Withdraw should have sent collateral assets to user."
        );
    }

    /// helpers

    function _createBytesDataToLend(ERC20 tokenToLend, uint256 amountToLend) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3ATokenCollateralAdaptor.depositToAaveV3Morpho.selector,
                tokenToLend,
                amountToLend
            );
    }

    function _createBytesDataToBorrow(
        ERC20 debtToken,
        uint256 amountToBorrow,
        uint256 maxIterations
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3DebtTokenAdaptor.borrowFromAaveV3Morpho.selector,
                debtToken,
                amountToBorrow,
                maxIterations
            );
    }

    function _createBytesDataToRepay(ERC20 tokenToRepay, uint256 amountToRepay) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3DebtTokenAdaptor.repayAaveV3MorphoDebt.selector,
                tokenToRepay,
                amountToRepay
            );
    }

    function _createBytesDataToLendP2P(
        ERC20 tokenToLend,
        uint256 amountToLend,
        uint256 maxIterations
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV3ATokenP2PAdaptor.depositToAaveV3Morpho.selector,
                tokenToLend,
                amountToLend,
                maxIterations
            );
    }

    // TODO: test this out
    function getMorphoBalance(address _underlying, address _user) internal view returns (uint256) {
        uint256 inP2P = morpho.supplyBalance(_underlying, _user);
        uint256 generalCollateral = morpho.collateralBalance(_underlying, _user);

        uint256 balanceInUnderlying;
        if (inP2P > 0) balanceInUnderlying = inP2P.mulDivDown(morpho.p2pSupplyIndex(_underlying), 1e27);
        if (generalCollateral > 0)
            balanceInUnderlying += generalCollateral.mulDivDown(morpho.poolIndexes(_underlying).poolSupplyIndex, 1e27);
        return balanceInUnderlying;
    }
}