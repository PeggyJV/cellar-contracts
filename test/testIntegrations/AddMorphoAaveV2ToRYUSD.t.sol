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
    function trustAdaptor(address adaptor, uint128 assetRisk, uint128 protocolRisk) external;

    function trustPosition(
        address adaptor,
        bytes memory adaptorData,
        uint128 assetRisk,
        uint128 protocolRisk
    ) external returns (uint32);
}

interface IRealYieldUsd {
    function addPosition(uint32 index, uint32 positionId, bytes memory congigData, bool inDebtArray) external;
}

interface ICellar {
    function setupAdaptor(address adaptor) external;
}

/// Integration Tests & SetUp

/**
 * @title MorphoAaveV2AdaptorIntegrations
 * @author 0xEinCodes and CrispyMangoes
 * @notice Integrations tests for MorphoAaveV2 Deployment
 * NOTE: Make sure strategist can lend USDT, USDC, DAI
 * Steps include:
 * 1.) Deploy Morpho Adaptors into a Cellar. I guess it'll be... RYUSD? Do basic lending to it.
 * 2.) New test, carry out looping within 1 tx where they're going to be withdrawing from AAVE, depositing into Morpho as collat, borrowing from Morpho, repay Aave debt, withdraw more from Aave and continue loop until they've moved entire Aave position to Morpho effectively.
 */
contract MorphoAaveV2AdaptorIntegrations is Test {
    using Math for uint256;

    // Sommelier Specific Deployed Mainnet Addresses
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private controller = 0xaDa78a5E01325B91Bc7879a63c309F7D54d42950;

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    IRegistry private registry = IRegistry(0x2Cbd27E034FEE53f79b607430dA7771B22050741); // all other cellars use RYE registry: 0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08

    // CellarInitializableV2_2 private rye = CellarInitializableV2_2(0xb5b29320d2Dde5BA5BAFA1EbcD270052070483ec);
    // CellarInitializableV2_2 private ryLink = CellarInitializableV2_2(0x4068BDD217a45F8F668EF19F1E3A1f043e4c4934);
    CellarInitializableV2_2 private ryUSD = CellarInitializableV2_2(0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E); // might just be CellarInitializableV2_1 not _2
    IRealYieldUsd private ryUSDPositionInterface = IRealYieldUsd(0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E);
    ICellar private ryUSDCellar = ICellar(0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E);

    IMorphoV2 private morpho = IMorphoV2(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);

    // General Mainnet Addresses
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // Aave-Specific Addresses
    address private aDAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address private aUSDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address private aUSDT = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;

    // CellarAdaptor private cellarAdaptor = CellarAdaptor(0x3B5CA5de4d808Cd793d3a7b3a731D3E67E707B27);
    MorphoAaveV2ATokenAdaptor private morphoAaveV2ATokenAdaptor =
        MorphoAaveV2ATokenAdaptor(0x1a4cB53eDB8C65C3DF6Aa9D88c1aB4CF35312b73);

    uint8 private constant CHAINLINK_DERIVATIVE = 1;

    ERC20 public WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

    // Aave V3 Positions
    ERC20 public aV3WETH = ERC20(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);
    ERC20 public dV3WETH = ERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE);
    ERC20 public aV3Link = ERC20(0x5E8C8A7243651DB1384C0dDfDbE39761E8e7E51a);

    AaveV3ATokenAdaptor public aaveV3AtokenAdaptor = AaveV3ATokenAdaptor(0x3184CBEa47eD519FA04A23c4207cD15b7545F1A6);
    AaveV3DebtTokenAdaptor public aaveV3DebtTokenAdaptor =
        AaveV3DebtTokenAdaptor(0x6DEd49176a69bEBf8dC1a4Ea357faa555df188f7);
    AaveATokenAdaptor public aaveATokenAdaptor = AaveATokenAdaptor(0xe3A3b8AbbF3276AD99366811eDf64A0a4b30fDa2); // v2?
    AaveDebtTokenAdaptor public aaveDebtTokenAdaptor = AaveDebtTokenAdaptor(0xeC86ac06767e911f5FdE7cba5D97f082C0139C01);
    address public erc20Adaptor = 0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE;

    address public oldCellarAdaptor = 0x24EEAa1111DAc1c0fE0Cf3c03bBa03ADde1e7Fe4;

    uint32 oldRyePosition = 143;
    uint32 aaveV3ALinkPosition = 153;
    uint32 aaveV3DebtWethPosition = 114;
    uint32 vanillaLinkPosition = 144;
    uint32 morphoAUSDTPosition = 159;
    uint32 morphoAUSDCPosition = 157;
    uint32 morphoADAIPosition = 158;

    modifier checkBlockNumber() {
        if (block.number < 17579366) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 17579366.");
            return;
        }
        _;
    }

    function setUp() external checkBlockNumber {
        // Setup positions and CataloguePositions for RYUSD with MorphoAaveV2AToken && stables
        // trustAdaptor and set up new positions (credit positions) in RYU cellar.
        vm.startPrank(controller); // controller is used to manage the RYUSD registry
        registry.trustAdaptor(address(morphoAaveV2ATokenAdaptor), 0, 0); //address(ryUSD)
        morphoAUSDTPosition = registry.trustPosition(
            address(morphoAaveV2ATokenAdaptor),
            abi.encode(address(aUSDC)),
            0,
            0
        ); //address(ryUSD)
        morphoAUSDCPosition = registry.trustPosition(
            address(morphoAaveV2ATokenAdaptor),
            abi.encode(address(aUSDT)),
            0,
            0
        ); //address(ryUSD)
        morphoADAIPosition = registry.trustPosition(
            address(morphoAaveV2ATokenAdaptor),
            abi.encode(address(aDAI)),
            0,
            0
        ); //address(ryUSD)
        vm.stopPrank();

        vm.startPrank(gravityBridge); // Check with Crispy as per convo.
        ryUSDCellar.setupAdaptor(address(morphoAaveV2ATokenAdaptor));
        ryUSDPositionInterface.addPosition(0, morphoAUSDTPosition, abi.encode(0), false);
        ryUSDPositionInterface.addPosition(0, morphoAUSDCPosition, abi.encode(0), false);
        ryUSDPositionInterface.addPosition(0, morphoADAIPosition, abi.encode(0), false);
        vm.stopPrank(); // stables to be dealt in actual test itself for RYUSD.AaveATokenAdaptor

        // TODO: setup " for RYE with MorphoV3 and looping --> this could be in the separate test altogether
    }

    // test lending USDT, USDC, DAI
    function testMorphoAaveV2Lending() external checkBlockNumber {
        // set up ryUSDCellar to have 1_000_000 of each stablecoin
        deal(address(DAI), address(ryUSDCellar), 1_000_000e18);
        deal(address(USDC), address(ryUSDCellar), 1_000_000e6);
        deal(address(USDT), address(ryUSDCellar), 1_000_000e6);

        // Strategist can now rebalance into RYE.
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](3);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToAaveV2Morpho(address(aDAI), type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV2ATokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToAaveV2Morpho(address(aUSDT), 1_000_000e6);
            data[1] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV2ATokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToDepositToAaveV2Morpho(address(aUSDC), type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV2ATokenAdaptor), callData: adaptorCalls });
        }

        vm.prank(gravityBridge);
        ryUSD.callOnAdaptor(data);

        // Make sure that Cellar has deposited into Morpho.
        assertApproxEqAbs(
            getMorphoBalance(aDAI, address(ryUSD)),
            1_000_000e18,
            1,
            "Morpho balance should equal assets dealt. "
        );
        assertApproxEqAbs(
            getMorphoBalance(aUSDT, address(ryUSD)),
            1_000_000e6,
            1,
            "Morpho balance should equal assets dealt. "
        );
        assertApproxEqAbs(
            getMorphoBalance(aUSDC, address(ryUSD)),
            1_000_000e6,
            1,
            "Morpho balance should equal assets dealt. "
        );

        // Make sure strategist can rebalance out of morpho.
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV2Morpho(address(aDAI), type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV2ATokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV2Morpho(address(aUSDT), type(uint256).max);
            data[1] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV2ATokenAdaptor), callData: adaptorCalls });
        }
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToWithdrawFromAaveV2Morpho(address(aUSDC), type(uint256).max);
            data[2] = Cellar.AdaptorCall({ adaptor: address(morphoAaveV2ATokenAdaptor), callData: adaptorCalls });
        }

        vm.prank(gravityBridge);
        ryUSD.callOnAdaptor(data);

        // Make sure that Cellar has stables.
        assertApproxEqAbs(DAI.balanceOf(address(ryUSD)), 1_000_000e18, 1, "Stable balance should equal assets dealt. ");
        assertApproxEqAbs(USDC.balanceOf(address(ryUSD)), 1_000_000e6, 1, "Stable balance should equal assets dealt. ");
        assertApproxEqAbs(USDT.balanceOf(address(ryUSD)), 1_000_000e6, 1, "Stable balance should equal assets dealt. ");

        assertEq(getMorphoBalance(aDAI, address(ryUSD)), 0, "Morpho balance should equal zero.");
        assertEq(getMorphoBalance(aUSDT, address(ryUSD)), 0, "Morpho balance should equal zero.");
        assertEq(getMorphoBalance(aUSDC, address(ryUSD)), 0, "Morpho balance should equal zero.");
    }

    /// helpers

    function _createBytesDataToDepositToAaveV2Morpho(
        address aToken,
        uint256 amountToDeposit
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(MorphoAaveV2ATokenAdaptor.depositToAaveV2Morpho.selector, aToken, amountToDeposit);
    }

    function _createBytesDataToWithdrawFromAaveV2Morpho(
        address aToken,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                MorphoAaveV2ATokenAdaptor.withdrawFromAaveV2Morpho.selector,
                aToken,
                amountToWithdraw
            );
    }

    function _createBytesDataToDepositToCellar(address cellar, uint256 assets) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CellarAdaptor.depositToCellar.selector, cellar, assets);
    }

    function _createBytesDataToWithdrawFromCellar(address cellar, uint256 assets) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CellarAdaptor.withdrawFromCellar.selector, cellar, assets);
    }

    function getMorphoBalance(address poolToken, address user) internal view returns (uint256) {
        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(poolToken, user);

        uint256 balanceInUnderlying;
        if (inP2P > 0) balanceInUnderlying = inP2P.mulDivDown(morpho.p2pSupplyIndex(poolToken), 1e27);
        if (onPool > 0) balanceInUnderlying += onPool.mulDivDown(morpho.poolIndexes(poolToken).poolSupplyIndex, 1e27);
        return balanceInUnderlying;
    }
}
