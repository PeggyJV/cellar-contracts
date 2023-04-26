// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { TEnv } from "script/test/TEnv.sol";
import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { INonfungiblePositionManager } from "@uniswapV3P/interfaces/INonfungiblePositionManager.sol";
import { ComptrollerG7 as Comptroller, CErc20 } from "src/interfaces/external/ICompound.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";

import { FeesAndReserves } from "src/modules/FeesAndReserves.sol";
import { UniswapV3PositionTracker } from "src/modules/adaptors/Uniswap/UniswapV3PositionTracker.sol";

// Import adaptors.
import { FeesAndReservesAdaptor } from "src/modules/adaptors/FeesAndReserves/FeesAndReservesAdaptor.sol";
import { CTokenAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { AaveV3ATokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3ATokenAdaptor.sol";
import { AaveV3DebtTokenAdaptor } from "src/modules/adaptors/Aave/V3/AaveV3DebtTokenAdaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/Uniswap/UniswapV3Adaptor.sol";
import { ZeroXAdaptor } from "src/modules/adaptors/ZeroX/ZeroXAdaptor.sol";
import { SwapWithUniswapAdaptor } from "src/modules/adaptors/Uniswap/SwapWithUniswapAdaptor.sol";
import { OneInchAdaptor } from "src/modules/adaptors/OneInch/OneInchAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

// Import Chainlink helpers.
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/DeployIndexCellar/DeployIndexCellar.s.sol:DeployIndexCellarScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployIndexCellarScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    address private strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;
    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private multisig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;

    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public AAVE = ERC20(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);
    ERC20 public UNI = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    ERC20 public COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ERC20 public MKR = ERC20(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2);
    ERC20 public LDO = ERC20(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32);

    // Compound positions
    CErc20 public cUSDC = CErc20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    CErc20 public cAAVE = CErc20(0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c);
    CErc20 public cUNI = CErc20(0x35A18000230DA775CAc24873d00Ff85BccdeD550);
    CErc20 public cCOMP = CErc20(0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4);

    // Aave V2 Positions.
    ERC20 public aV2USDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    ERC20 public aV2CRV = ERC20(0x8dAE6Cb04688C62d939ed9B68d32Bc62e49970b1);
    ERC20 public aV2MKR = ERC20(0xc713e5E149D5D0715DcD1c156a020976e7E56B88);
    ERC20 public aV2UNI = ERC20(0xB9D7CB55f463405CDfBe4E90a6D2Df01C2B92BF1);

    // Aave V3 positions.
    ERC20 public aV3USDC = ERC20(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
    ERC20 public aV3CRV = ERC20(0x7B95Ec873268a6BFC6427e7a28e396Db9D0ebc65);
    ERC20 public aV3UNI = ERC20(0xF6D2224916DDFbbab6e6bd0D1B7034f4Ae0CaB18);
    ERC20 public aV3MKR = ERC20(0x8A458A9dc9048e005d22849F470891b840296619);
    ERC20 public aV3LDO = ERC20(0x9A44fd41566876A39655f74971a3A6eA0a17a454);

    CellarInitializableV2_2 private cellar;

    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    CellarFactory private factory = CellarFactory(0x9D30672eED8D514cD1ad009Cfe85Ea8f0019D37F);
    SwapRouter private swapRouter = SwapRouter(0x070f43E613B33aD3EFC6B2928f3C01d58D032020);
    Registry private registry = Registry(0x3051e76a62da91D4aD6Be6bD98D8Ab26fdaF9D08);
    FeesAndReserves private feesAndReserves = FeesAndReserves(0xF4279E93a06F9d4b5d0625b1F471AA99Ef9B686b);

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor = ERC20Adaptor(0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE);
    FeesAndReservesAdaptor private feesAndReservesAdaptor =
        FeesAndReservesAdaptor(0x647d264d800A2461E594796af61a39b7735d8933);
    CTokenAdaptor private cTokenAdaptor = CTokenAdaptor(0x9a384Df333588428843D128120Becd72434ec078);
    AaveATokenAdaptor private aaveATokenAdaptor = AaveATokenAdaptor(0xe3A3b8AbbF3276AD99366811eDf64A0a4b30fDa2);
    AaveV3ATokenAdaptor private aaveV3ATokenAdaptor = AaveV3ATokenAdaptor(0x3184CBEa47eD519FA04A23c4207cD15b7545F1A6);
    ZeroXAdaptor private zeroXAdaptor = ZeroXAdaptor(0x1039a9b61DFF6A3fb8dbF4e924AA749E5cFE35ef);
    SwapWithUniswapAdaptor private swapWithUniswapAdaptor =
        SwapWithUniswapAdaptor(0xd6BC6Df1ed43e3101bC27a4254593a06598a3fDD);
    OneInchAdaptor private oneInchAdaptor = OneInchAdaptor(0xB8952ce4010CFF3C74586d712a4402285A3a3AFb);

    function run() external {
        vm.startBroadcast();

        uint32[] memory positionIds = new uint32[](20);

        // Add Positions to registry.
        // TODO add these with the multisig
        positionIds[0] = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC));
        positionIds[1] = registry.trustPosition(address(erc20Adaptor), abi.encode(CRV));
        positionIds[2] = registry.trustPosition(address(erc20Adaptor), abi.encode(AAVE));
        positionIds[3] = registry.trustPosition(address(erc20Adaptor), abi.encode(UNI));
        positionIds[4] = registry.trustPosition(address(erc20Adaptor), abi.encode(COMP));
        positionIds[5] = registry.trustPosition(address(erc20Adaptor), abi.encode(MKR));
        positionIds[6] = registry.trustPosition(address(erc20Adaptor), abi.encode(LDO));
        positionIds[7] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aV2USDC)));
        positionIds[8] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aV2CRV)));
        positionIds[9] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aV2MKR)));
        positionIds[10] = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(address(aV2UNI)));
        positionIds[11] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aV3USDC)));
        positionIds[12] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aV3CRV)));
        positionIds[13] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aV3UNI)));
        positionIds[14] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aV3MKR)));
        positionIds[15] = registry.trustPosition(address(aaveV3ATokenAdaptor), abi.encode(address(aV3LDO)));
        positionIds[16] = registry.trustPosition(address(cTokenAdaptor), abi.encode(cUSDC));
        positionIds[17] = registry.trustPosition(address(cTokenAdaptor), abi.encode(cAAVE));
        positionIds[18] = registry.trustPosition(address(cTokenAdaptor), abi.encode(cUNI));
        positionIds[19] = registry.trustPosition(address(cTokenAdaptor), abi.encode(cCOMP));

        // Deploy cellar using factory.
        bytes memory initializeCallData = abi.encode(
            devOwner,
            registry,
            USDC,
            "BH TODO",
            "TODO",
            positionIds[0],
            abi.encode(0),
            strategist
        );
        address imp = factory.getImplementation(2, 2);
        require(imp != address(0), "Invalid implementation");

        uint256 initialDeposit = 1e6;
        USDC.approve(address(factory), initialDeposit);
        address clone = factory.deploy(
            2,
            2,
            initializeCallData,
            USDC,
            initialDeposit,
            keccak256(abi.encode(block.timestamp))
        );
        cellar = CellarInitializableV2_2(clone);

        // Setup all the adaptors the cellar will use.
        cellar.addAdaptorToCatalogue(address(feesAndReservesAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(aaveV3ATokenAdaptor));
        cellar.addAdaptorToCatalogue(address(zeroXAdaptor));
        cellar.addAdaptorToCatalogue(address(swapWithUniswapAdaptor));
        cellar.addAdaptorToCatalogue(address(oneInchAdaptor));
        cellar.addAdaptorToCatalogue(address(cTokenAdaptor));

        // Setup all the positions the cellar will use.
        cellar.addPositionToCatalogue(positionIds[0]);
        cellar.addPositionToCatalogue(positionIds[1]);
        cellar.addPositionToCatalogue(positionIds[2]);
        cellar.addPositionToCatalogue(positionIds[3]);
        cellar.addPositionToCatalogue(positionIds[4]);
        cellar.addPositionToCatalogue(positionIds[5]);
        cellar.addPositionToCatalogue(positionIds[7]);
        cellar.addPositionToCatalogue(positionIds[8]);
        cellar.addPositionToCatalogue(positionIds[9]);
        cellar.addPositionToCatalogue(positionIds[10]);
        cellar.addPositionToCatalogue(positionIds[11]);
        cellar.addPositionToCatalogue(positionIds[12]);
        cellar.addPositionToCatalogue(positionIds[13]);
        cellar.addPositionToCatalogue(positionIds[14]);
        cellar.addPositionToCatalogue(positionIds[15]);
        cellar.addPositionToCatalogue(positionIds[16]);
        cellar.addPositionToCatalogue(positionIds[17]);

        // cellar.transferOwnership(0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138);

        vm.stopBroadcast();
    }
}
