// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
// import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { CellarAdaptor } from "src/modules/adaptors/Sommelier/CellarAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { MorphoAaveV2ATokenAdaptor, IMorphoV2, BaseAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV2ATokenAdaptor.sol";
import { MorphoAaveV2DebtTokenAdaptor } from "src/modules/adaptors/Morpho/MorphoAaveV2DebtTokenAdaptor.sol";
import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";

/// Interfaces for interacting with RYUSD (as it has different registry contract and a few other interfaces)
interface IRegistry {
    function trustAdaptor(
        address adaptor,
        uint128 assetRisk,
        uint128 protocolRisk
    ) external;

    function trustPosition(
        address adaptor,
        bytes memory adaptorData,
        uint128 assetRisk,
        uint128 protocolRisk
    ) external returns (uint32);
}

interface IRealYieldUsd {
    function addPosition(
        uint32 index,
        uint32 positionId,
        bytes memory congigData,
        bool inDebtArray
    ) external;
}

interface ICellar {
    function setupAdaptor(address adaptor) external;
}

/// Integration Tests & SetUp

/**
 * @title MorphoAaveV2AdaptorIntegrationsRYE
 * @author 0xEinCodes and CrispyMangoes
 * @notice Integrations tests for MorphoAaveV2 Deployment with RYE
 * Steps include:
 * 1.) Deploy Morpho Adaptors into RYE, and test lending out STETH, borrowing WETH, and repaying it.
 * TODO: remove extras or combine new changes into the current AddMorphoAaveV2ToRYUSD and rename the file
 */
contract MorphoAaveV2AdaptorIntegrationsRYE is Test {
    using Math for uint256;

    // Sommelier Specific Deployed Mainnet Addresses
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private controller = 0xaDa78a5E01325B91Bc7879a63c309F7D54d42950;

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    IRegistry private registry = IRegistry(0x2Cbd27E034FEE53f79b607430dA7771B22050741); // all other cellars use RYE registry: 0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08

    CellarInitializableV2_2 private rye = CellarInitializableV2_2(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);

    IMorphoV2 private morpho = IMorphoV2(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);

    // General Mainnet Addresses
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private WstEth = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ERC20 private STETH = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    // Aave-Specific Addresses
    ERC20 private aWstETH = ERC20(0x0B925eD163218f6662a35e0f0371Ac234f9E9371);
    address public aSTETH = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
    address public aWETH = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;

    // CellarAdaptor private cellarAdaptor = CellarAdaptor(0x3B5CA5de4d808Cd793d3a7b3a731D3E67E707B27);
    MorphoAaveV2ATokenAdaptor private morphoAaveV2ATokenAdaptor =
        MorphoAaveV2ATokenAdaptor(0x1a4cB53eDB8C65C3DF6Aa9D88c1aB4CF35312b73);
    MorphoAaveV2DebtTokenAdaptor private morphoAaveV2DebtTokenAdaptor =
        MorphoAaveV2DebtTokenAdaptor(0x407D5489F201013EE6A6ca20fCcb05047C548138);

    // Aave V3 Positions
    ERC20 public aV3WETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 public dV3WETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);
    ERC20 public aV3Link = ERC20(0x5E8C8A7243651DB1384C0dDfDbE39761E8e7E51a);

    address public erc20Adaptor = 0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE;
    address public oldCellarAdaptor = 0x24EEAa1111DAc1c0fE0Cf3c03bBa03ADde1e7Fe4;

    uint32 oldRyePosition = 143;
    uint32 morphoAaveV2DebtWETHPosition = 161;
    uint32 morphoASTETHV2Position = 155;
    uint32 morphoAWETHPosition = 156;

    modifier checkBlockNumber() {
        if (block.number < 17579366) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 17579366.");
            return;
        }
        _;
    }

    function setUp() external checkBlockNumber {
        // Setup positions and CataloguePositions for RYE with MorphoAaveV2AToken && STETH
        vm.startPrank(gravityBridge); // Check with Crispy as per convo.
        rye.addPosition(1, morphoASTETHV2Position, abi.encode(0), false);
        rye.addPosition(2, morphoAWETHPosition, abi.encode(0), false);
        rye.addPosition(0, morphoAaveV2DebtWETHPosition, abi.encode(0), true);
        vm.stopPrank();
    }

    // TODO: test2: deposit to Morpho (lend)), borrow using MorphoAaveV2, repay. Basically the same one.
    // EIN START

    // test lending wstETH, borrowing wETH against it, and repaying it.
    function testMorphoAaveV2LendBorrowRepay() external {
        // have RYE w/ liquid wstETH ready to lend into Morpho
        deal(address(STETH), address(rye), 1_000_000e18);
        deal(address(WETH), address(rye), 0);
        console.log("STETHBalance: %S", STETH.balanceOf(address(rye)));
        // deposit into Morpho

        // Rebalance Cellar to take on debt.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);

        // // TODO: only uncomment if I can't deal STETH to myself. Swap WETH for STETH. Also need the Uniswap Adaptor then, but that should be already part of RYE
        // {
        //     bytes[] memory adaptorCalls = new bytes[](1);
        //     adaptorCalls[0] = _createBytesDataForSwap(WETH, WSTETH, 500, assets);
        //     data[0] = Cellar.AdaptorCall({ adaptor: address(swapWithUniswapAdaptor), callData: adaptorCalls });
        // }

        // Supply STETH as collateral on MorphoAaveV2, and borrow WETH against it
        uint256 wethToBorrow = 1_000_000e18 / 4;
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToLend(address(STETH), type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV2ATokenAdaptor), callData: adaptorCalls });
        }
        // Borrow WETH from Morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToBorrow(address(WETH), wethToBorrow);
            data[2] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV2DebtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        vm.prank(gravityBridge);
        rye.callOnAdaptor(data);

        // Check Morpho balances (supplied STETH, borrowed wETH)

        console.log("RYE STETHBalanceAfterLend %s", STETH.balanceOf(address(rye)));
        console.log("RYE WETHBalanceAfterBorrow %s", WETH.balanceOf(address(rye)));

        assertApproxEqAbs(STETH.balanceOf(address(rye)), 0, 1, "RYE STETH balance should equal zero.");
        assertApproxEqAbs(
            WETH.balanceOf(address(rye)),
            wethToBorrow,
            1,
            "RYE WETH balance should equal  amount borrowed from Morpho"
        );

        // Make sure that Cellar has provided collateral to Morpho
        // TODO: change for v2
        assertApproxEqAbs(
            getMorphoBalance(address(STETH), address(rye)),
            1_000_000e18,
            1,
            "Morpho balance should equal assets dealt. "
        );
        // Make sure that Cellar has borrowed from Morpho.
        uint256 wethDebt = getMorphoDebt(aWETH, address(rye));

        assertApproxEqAbs(wethDebt, wethToBorrow, 1, "WETH debt should equal assets / 4.");

        uint256 borrowedWETH = WETH.balanceOf(address(rye));

        uint256 newTestWETH = borrowedWETH + 1 ether; // adding for any dust lost
        uint256 expectedFinalWETH = newTestWETH - borrowedWETH;
        deal(address(WETH), address(rye), newTestWETH); // deal more weth for repay due to lost dust in txs
        Cellar.AdaptorCall[] memory data2 = new Cellar.AdaptorCall[](1);

        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToRepay(address(WETH), type(uint256).max);
            data2[1] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV2DebtTokenAdaptor), callData: adaptorCalls });
        }

        // Perform callOnAdaptor.
        vm.prank(gravityBridge);
        rye.callOnAdaptor(data2);

        // Checks that the cellar can use the Aave v3 Morpho adaptors
        console.log("RYE WstETHBalanceAfterLend %s", STETH.balanceOf(address(rye)));
        console.log("RYE WETHBalanceAfterBorrow %s", WETH.balanceOf(address(rye)));

        assertApproxEqAbs(
            STETH.balanceOf(address(rye)),
            0,
            1,
            "RYE wstETH balance should equal zero since it is still in Morpho."
        );
        assertApproxEqAbs(
            WETH.balanceOf(address(rye)),
            expectedFinalWETH,
            10,
            "RYE WETH borrowed should be returned now, and cellar should have basically no WETH (aside from dust)"
        );
    }

    ////EIN END

    /// helpers

    function getMorphoBalance(address poolToken, address user) internal view returns (uint256) {
        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(poolToken, user);

        uint256 balanceInUnderlying;
        if (inP2P > 0) balanceInUnderlying = inP2P.mulDivDown(morpho.p2pSupplyIndex(poolToken), 1e27);
        if (onPool > 0) balanceInUnderlying += onPool.mulDivDown(morpho.poolIndexes(poolToken).poolSupplyIndex, 1e27);
        return balanceInUnderlying;
    }

    function getMorphoDebt(address aToken, address user) public view returns (uint256) {
        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(aToken, user);

        uint256 balanceInUnderlying;
        if (inP2P > 0) balanceInUnderlying = inP2P.mulDivDown(morpho.p2pBorrowIndex(aToken), 1e27);
        if (onPool > 0) balanceInUnderlying += onPool.mulDivDown(morpho.poolIndexes(aToken).poolBorrowIndex, 1e27);
        return balanceInUnderlying;
    }

    // function _createBytesDataForSwap(
    //     ERC20 from,
    //     ERC20 to,
    //     uint24 poolFee,
    //     uint256 fromAmount
    // ) internal pure returns (bytes memory) {
    //     address[] memory path = new address[](2);
    //     path[0] = address(from);
    //     path[1] = address(to);
    //     uint24[] memory poolFees = new uint24[](1);
    //     poolFees[0] = poolFee;
    //     return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV3.selector, path, poolFees, fromAmount, 0);
    // }

    // function _createBytesDataForSwap(ERC20 from, ERC20 to, uint256 fromAmount) internal pure returns (bytes memory) {
    //     address[] memory path = new address[](2);
    //     path[0] = address(from);
    //     path[1] = address(to);
    //     return abi.encodeWithSelector(SwapWithUniswapAdaptor.swapWithUniV2.selector, path, fromAmount, 0);
    // }

    function _createBytesDataToLend(address aToken, uint256 amountToLend) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(MorphoAaveV2ATokenAdaptor.depositToAaveV2Morpho.selector, aToken, amountToLend);
    }

    function _createBytesDataToWithdraw(address aToken, uint256 amountToWithdraw) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2ATokenAdaptor.withdrawFromAaveV2Morpho.selector,
                aToken,
                amountToWithdraw
            );
    }

    function _createBytesDataToBorrow(address debtToken, uint256 amountToBorrow) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2DebtTokenAdaptor.borrowFromAaveV2Morpho.selector,
                debtToken,
                amountToBorrow
            );
    }

    function _createBytesDataToRepay(address debtToken, uint256 amountToRepay) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2DebtTokenAdaptor.repayAaveV2MorphoDebt.selector,
                debtToken,
                amountToRepay
            );
    }
}
