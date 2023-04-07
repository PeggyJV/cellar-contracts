// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib, PriceRouter } from "src/base/Cellar.sol";
import { CellarInitializableV2_1 } from "src/base/CellarInitializableV2_1.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { TickMath } from "@uniswapV3C/libraries/TickMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PoolAddress } from "@uniswapV3P/libraries/PoolAddress.sol";
import { IUniswapV3Factory } from "@uniswapV3C/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswapV3C/interfaces/IUniswapV3Pool.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CTokenAdaptor, BaseAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";

// Import adaptors.
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

interface IRegistry {
    function trustAdaptor(address adaptor, uint128 assetRisk, uint128 protocolRisk) external;

    function trustPosition(address adaptor, bytes memory adaptorData, uint128 assetRisk, uint128 protocolRisk) external;
}

interface IRealYieldUsd {
    function addPosition(uint32 index, uint32 positionId, bytes memory congigData, bool inDebtArray) external;
}

interface ICellar {
    function setupAdaptor(address adaptor) external;
}

contract UpgradeRealYieldUsdTest is Test {
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address internal constant uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant uniV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private otherDevAddress = 0xF3De89fAD937c11e770Bc6291cb5E04d8784aE0C;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;

    TimelockController private controller = TimelockController(payable(0xaDa78a5E01325B91Bc7879a63c309F7D54d42950));

    IUniswapV3Factory internal factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    CellarInitializableV2_1 private cellar = CellarInitializableV2_1(0x97e6E0a40a3D02F12d1cEC30ebfbAE04e37C119E);
    PriceRouter private priceRouter;
    IRegistry private registry = IRegistry(0x2Cbd27E034FEE53f79b607430dA7771B22050741);
    UniswapV3Adaptor private uniswapV3Adaptor = UniswapV3Adaptor(0xDbd750F72a00d01f209FFc6C75e80301eFc789C1);

    INonfungiblePositionManager internal positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    address public vestingSimpleAdaptor = 0x508E6aE090eA92Cb90571e4269B799257CD78CA1;
    address public oneInchAdaptor = 0xB8952ce4010CFF3C74586d712a4402285A3a3AFb;
    address public swapWithUniswapAdaptor = 0xd6BC6Df1ed43e3101bC27a4254593a06598a3fDD;
    address public zeroXAdaptor = 0x1039a9b61DFF6A3fb8dbF4e924AA749E5cFE35ef;
    address public aaveV3DebtTokenAdaptor = 0x6DEd49176a69bEBf8dC1a4Ea357faa555df188f7;
    address public aaveV3AtokenAdaptor = 0x3184CBEa47eD519FA04A23c4207cD15b7545F1A6;
    address public aaveDebtTokenAdaptor = 0x5F4e81E1BC9D7074Fc30aa697855bE4e1AA16F0b;
    address public aaveATokenAdaptor = 0x25570a77dCA06fda89C1ef41FAb6eE48a2377E81;
    address public feesAndReservesAdaptor = 0x647d264d800A2461E594796af61a39b7735d8933;
    address public cTokenAdaptor = 0x9a384Df333588428843D128120Becd72434ec078;

    // Current one
    address public uniV3Adaptor = 0xDbd750F72a00d01f209FFc6C75e80301eFc789C1;
    address public oldCTokenAdaptor = 0x26DbA82495f6189DDe7648Ae88bEAd46C402F078;

    // Values needed to make positions.
    address public usdcVestor = 0xd944D0e62de2ae742C4CA085e80222f58B69b231;
    address private aV2USDC = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    address private aV2DAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
    address private aV2USDT = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
    address private aV3USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address private aV3DAI = 0x018008bfb33d285247A21d44E50697654f754e63;
    address private aV3USDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;
    address private cUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address private cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address private cUSDT = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;

    function setUp() external {}

    function testAddingNewPositions() external {
        if (block.number < 16998288) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 16998288.");
            return;
        }
        vm.startPrank(address(controller));

        // Need to trustAdaptors
        registry.trustAdaptor(vestingSimpleAdaptor, 0, 0);
        registry.trustAdaptor(oneInchAdaptor, 0, 0);
        registry.trustAdaptor(swapWithUniswapAdaptor, 0, 0);
        registry.trustAdaptor(zeroXAdaptor, 0, 0);
        registry.trustAdaptor(aaveV3AtokenAdaptor, 0, 0);
        registry.trustAdaptor(aaveATokenAdaptor, 0, 0);
        registry.trustAdaptor(feesAndReservesAdaptor, 0, 0);
        registry.trustAdaptor(cTokenAdaptor, 0, 0);

        // Need to trustPositions
        registry.trustPosition(aaveATokenAdaptor, abi.encode(aV2USDC), 0, 0);
        registry.trustPosition(aaveATokenAdaptor, abi.encode(aV2DAI), 0, 0);
        registry.trustPosition(aaveATokenAdaptor, abi.encode(aV2USDT), 0, 0);
        registry.trustPosition(aaveV3AtokenAdaptor, abi.encode(aV3USDC), 0, 0);
        registry.trustPosition(aaveV3AtokenAdaptor, abi.encode(aV3DAI), 0, 0);
        registry.trustPosition(aaveV3AtokenAdaptor, abi.encode(aV3USDT), 0, 0);
        registry.trustPosition(vestingSimpleAdaptor, abi.encode(usdcVestor), 0, 0);
        // Wait to trust Compound positions cuz RYUSD needs the new compound adaptor in order to fully exit the compound positions.
        // registry.trustPosition(cTokenAdaptor, abi.encode(cUSDC), 0, 0);
        // registry.trustPosition(cTokenAdaptor, abi.encode(cDAI), 0, 0);
        // registry.trustPosition(cTokenAdaptor, abi.encode(cUSDT), 0, 0);

        vm.stopPrank();

        vm.startPrank(gravityBridge);
        // Strategist updates holding position to be vanilla USDC.
        cellar.setHoldingPosition(1);

        // Strategist could change withdrawal array so that compound is withdraw from first
        // Now rebalance cellar so that money is only in USDC, USDT, DAI
        Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](1);
        {
            bytes[] memory adaptorCalls = new bytes[](1);
            adaptorCalls[0] = _createBytesDataToCloseLP(address(cellar), 3);
            data[0] = Cellar.AdaptorCall({ adaptor: uniV3Adaptor, callData: adaptorCalls });
        }

        // cellar.callOnAdaptor(data);

        // Remove old Aave positions, and old vesting position. Remove index 4,5,6,7 or index 4(x4 times)
        cellar.removePosition(4, false);
        cellar.removePosition(4, false);
        cellar.removePosition(4, false);
        cellar.removePosition(4, false);

        // TODO Steward should be updated to not allow strategist to call add position 4->12, and setup new positions.

        // Strategist can now trust new adaptors.
        ICellar(address(cellar)).setupAdaptor(vestingSimpleAdaptor);
        ICellar(address(cellar)).setupAdaptor(oneInchAdaptor);
        ICellar(address(cellar)).setupAdaptor(swapWithUniswapAdaptor);
        ICellar(address(cellar)).setupAdaptor(zeroXAdaptor);
        ICellar(address(cellar)).setupAdaptor(aaveV3AtokenAdaptor);
        ICellar(address(cellar)).setupAdaptor(aaveATokenAdaptor);
        ICellar(address(cellar)).setupAdaptor(feesAndReservesAdaptor);
        ICellar(address(cellar)).setupAdaptor(cTokenAdaptor);

        // Strategist can now rebalance out of compound positions.
        {
            bytes[] memory adaptorCalls = new bytes[](3);
            adaptorCalls[0] = _createBytesDataToWithdrawFromCompound(cUSDC, type(uint256).max);
            adaptorCalls[1] = _createBytesDataToWithdrawFromCompound(cDAI, type(uint256).max);
            adaptorCalls[2] = _createBytesDataToWithdrawFromCompound(cUSDT, type(uint256).max);
            data[0] = Cellar.AdaptorCall({ adaptor: cTokenAdaptor, callData: adaptorCalls });
        }

        cellar.callOnAdaptor(data);

        uint256 totalAssetsBeforeChanges = cellar.totalAssets();

        // Remove compound positions.
        cellar.removePosition(4, false);
        cellar.removePosition(4, false);
        cellar.removePosition(0, false);
        vm.stopPrank();

        vm.startPrank(address(controller));
        // Trust new compopund positions.
        registry.trustPosition(cTokenAdaptor, abi.encode(cUSDC), 0, 0);
        registry.trustPosition(cTokenAdaptor, abi.encode(cDAI), 0, 0);
        registry.trustPosition(cTokenAdaptor, abi.encode(cUSDT), 0, 0);

        vm.stopPrank();

        // Strategist adds all the new positions to the cellar. 15 ->
        vm.startPrank(gravityBridge);
        cellar.addPosition(0, 15, abi.encode(0), false); // aV2USDC
        cellar.addPosition(0, 16, abi.encode(0), false);
        cellar.addPosition(0, 17, abi.encode(0), false);
        cellar.addPosition(0, 18, abi.encode(0), false); // V3USDC
        cellar.addPosition(0, 19, abi.encode(0), false);
        cellar.addPosition(0, 20, abi.encode(0), false);
        cellar.addPosition(0, 21, abi.encode(0), false);
        cellar.addPosition(0, 22, abi.encode(0), false); //cUSDC
        cellar.addPosition(0, 23, abi.encode(0), false);
        cellar.addPosition(0, 24, abi.encode(0), false);
        vm.stopPrank();

        assertEq(cellar.totalAssets(), totalAssetsBeforeChanges, "Should be the same.");

        deal(address(USDC), address(this), 30e6);
        USDC.approve(address(cellar), 30e6);

        vm.prank(gravityBridge);
        cellar.setHoldingPosition(15);

        cellar.deposit(10e6, address(this));

        vm.prank(gravityBridge);
        cellar.setHoldingPosition(18);

        cellar.deposit(10e6, address(this));

        vm.prank(gravityBridge);
        cellar.setHoldingPosition(22);

        cellar.deposit(10e6, address(this));

        console.log("Total Assets now", cellar.totalAssets());
        console.log("Total Assets before", totalAssetsBeforeChanges);
    }

    function _createBytesDataToCloseLP(address owner, uint256 index) internal view returns (bytes memory) {
        uint256 tokenId = positionManager.tokenOfOwnerByIndex(owner, index);
        return abi.encodeWithSelector(UniswapV3Adaptor.closePosition.selector, tokenId, 0, 0);
    }

    function _createBytesDataToWithdrawFromCompound(
        address market,
        uint256 amountToWithdraw
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(CTokenAdaptor.withdrawFromCompound.selector, market, amountToWithdraw);
    }
}
