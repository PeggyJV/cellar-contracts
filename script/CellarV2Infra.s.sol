// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Script.sol";
import { Registry } from "src/Registry.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Cellar } from "src/base/Cellar.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";
import { IUniswapV3Router } from "src/interfaces/external/IUniswapV3Router.sol";
import { Denominations } from "@chainlink/contracts/src/v0.8/Denominations.sol";
import { ERC20 } from "src/base/ERC20.sol";
import { CellarInitializable } from "src/base/CellarInitializable.sol";
import { VestingSimple } from "src/modules/vesting/VestingSimple.sol";

import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { UniswapV3Adaptor } from "src/modules/adaptors/UniSwap/UniswapV3Adaptor.sol";
import { AaveATokenAdaptor } from "src/modules/adaptors/Aave/AaveATokenAdaptor.sol";
import { AaveDebtTokenAdaptor } from "src/modules/adaptors/Aave/AaveDebtTokenAdaptor.sol";
import { CTokenAdaptor } from "src/modules/adaptors/Compound/CTokenAdaptor.sol";
import { VestingSimpleAdaptor } from "src/modules/adaptors/VestingSimpleAdaptor.sol";

contract CellarV2InfraScript is Script {
    event Deploy(string name, address addr);

    uint256 private deployerPrivateKey;

    // External contracts
    address private uniswapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private sommMultiSig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private strategist = 0x97238B45C626a4CA4C99E7Eb34e2DAD5e5107D32;
    address private deployer = 0xbaf7d863B4504D520797EFef4434F2067C1142c5;

    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 private COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);

    // Global Cellar Infra
    PriceRouter private priceRouter;
    SwapRouter private swapRouter;
    Registry private registry;
    CellarFactory private cellarFactory;
    VestingSimple private vestingSimple;
    CellarInitializable private cellarTemplate;

    // Adaptors
    ERC20Adaptor private erc20Adaptor;
    UniswapV3Adaptor private uniswapV3Adaptor;
    AaveATokenAdaptor private aaveATokenAdaptor;
    AaveDebtTokenAdaptor private aaveDebtTokenAdaptor;
    CTokenAdaptor private cTokenAdaptor;
    VestingSimpleAdaptor private vestingSimpleAdaptor;

    uint32 private holdingPositionId;
    uint32[] private creditPositions;
    uint32[] private debtPositions;

    function run() external {
        // 0) Load the deployer's private key
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1) through 5)
        deployCoreInfra();

        // 6) through 11)
        deployAdaptors();

        // 12) through 16)
        priceRouterAddAssets();

        // 17) through 22)
        registryTrustAdaptors();

        // 23) through 37)
        registryTrustPositions();

        // 38) through 40)
        setupFactory();

        uint256 shouldDeployCellar = vm.envUint("DEPLOY_CELLAR");

        if (shouldDeployCellar == 1) {
            deployCellar();
        }

        vm.stopBroadcast();
    }

    function deployCoreInfra() internal {
        // 1) Deploy PriceRouter
        priceRouter = new PriceRouter();
        emit Deploy("PriceRouter", address(priceRouter));

        // 2) Deploy SwapRouter
        swapRouter = new SwapRouter(IUniswapV2Router(uniswapV2Router), IUniswapV3Router(uniswapV3Router));
        emit Deploy("SwapRouter", address(swapRouter));

        // 3) Deploy Registry (with deployer as owner)
        registry = new Registry(deployer, address(swapRouter), address(priceRouter));
        emit Deploy("Registry", address(registry));

        // 4) Deploy CellarFactory
        cellarFactory = new CellarFactory();
        emit Deploy("CellarFactory", address(cellarFactory));

        // 5) Deploy vesting contract
        vestingSimple = new VestingSimple(COMP, 1 days, 1e12);
    }

    function deployAdaptors() internal {
        // 6) Deploy ERC20Adaptor
        erc20Adaptor = new ERC20Adaptor();
        emit Deploy("ERC20Adaptor", address(erc20Adaptor));

        // 7) Deploy UniswapV3Adaptor
        uniswapV3Adaptor = new UniswapV3Adaptor();
        emit Deploy("UniswapV3Adaptor", address(uniswapV3Adaptor));

        // 8) Deploy AaveATokenAdaptor
        aaveATokenAdaptor = new AaveATokenAdaptor();
        emit Deploy("AaveATokenAdaptor", address(aaveATokenAdaptor));

        // 9) Deploy AaveDebtTokenAdaptor
        aaveDebtTokenAdaptor = new AaveDebtTokenAdaptor();
        emit Deploy("AaveDebtTokenAdaptor", address(aaveDebtTokenAdaptor));

        // 10) Deploy CTokenAdaptor
        cTokenAdaptor = new CTokenAdaptor();
        emit Deploy("CTokenAdaptor", address(cTokenAdaptor));

        // 11) Deploy VestingSimpleAdaptor
        vestingSimpleAdaptor = new VestingSimpleAdaptor();
        emit Deploy("VestingSimpleAdaptor", address(vestingSimpleAdaptor));
    }

    function priceRouterAddAssets() internal {
        PriceRouter.ChainlinkDerivativeStorage memory s = PriceRouter.ChainlinkDerivativeStorage({
            max: 0,
            min: 0,
            heartbeat: 0,
            inETH: false
        });

        // 12) PriceRouter add USDC
        priceRouter.addAsset(USDC, PriceRouter.AssetSettings(1, 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6), abi.encode(s), 100000000);

        // 13) PriceRouter add DAI
        priceRouter.addAsset(DAI, PriceRouter.AssetSettings(1, 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9), abi.encode(s), 99954763);

        // 14) PriceRouter add USDT
        priceRouter.addAsset(USDT, PriceRouter.AssetSettings(1, 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D), abi.encode(s), 100008000);

        // 15) PriceRouter add WETH
        priceRouter.addAsset(WETH, PriceRouter.AssetSettings(1, 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419), abi.encode(s), 125545000000);

        // 16) PriceRouter add COMP
        priceRouter.addAsset(COMP, PriceRouter.AssetSettings(1, 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5), abi.encode(s), 3270112350);
    }

    function registryTrustAdaptors() internal {
        // 17) Trust ERC20Adaptor
        registry.trustAdaptor(address(erc20Adaptor), 0, 0);

        // 18) Trust UniswapV3Adaptor
        registry.trustAdaptor(address(uniswapV3Adaptor), 0, 0);

        // 19) Trust AaveATokenAdaptor
        registry.trustAdaptor(address(aaveATokenAdaptor), 0, 0);

        // 20) Trust AaveDebtTokenAdaptor
        registry.trustAdaptor(address(aaveDebtTokenAdaptor), 0, 0);

        // 21) Trust CTokenAdaptor
        registry.trustAdaptor(address(cTokenAdaptor), 0, 0);

        // 22) Trust VestingSimpleAdaptor
        registry.trustAdaptor(address(vestingSimpleAdaptor), 0, 0);
    }

    function registryTrustPositions() internal {
        uint32 positionId;

        // 23) Trust ERC20Adaptor USDC position
        positionId = registry.trustPosition(address(erc20Adaptor), abi.encode(USDC), 0, 0);
        creditPositions.push(positionId);

        // 24) Trust ERC20Adaptor DAI position
        positionId = registry.trustPosition(address(erc20Adaptor), abi.encode(DAI), 0, 0);
        creditPositions.push(positionId);


        // 25) Trust ERC20Adaptor USDT position
        positionId = registry.trustPosition(address(erc20Adaptor), abi.encode(USDT), 0, 0);
        creditPositions.push(positionId);


        // 26) Trust UniswapV3Adaptor DAI/USDC Position
        positionId = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(DAI, USDC), 0, 0);
        creditPositions.push(positionId);


        // 27) Trust UniswapV3Adaptor USDC/USDT Position
        positionId = registry.trustPosition(address(uniswapV3Adaptor), abi.encode(USDC, USDT), 0, 0);
        creditPositions.push(positionId);


        // 28) Trust AaveATokenAdaptor aUSDC position
        positionId = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(0xBcca60bB61934080951369a648Fb03DF4F96263C), 0, 2);
        holdingPositionId = positionId;
        creditPositions.push(positionId);


        // 29) Trust AaveDebtTokenAdaptor USDC debt token position
        positionId = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(0x619beb58998eD2278e08620f97007e1116D5D25b), 0, 2);
        debtPositions.push(positionId);


        // 30) Trust AaveATokenAdaptor aDAI position
        positionId = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(0x028171bCA77440897B824Ca71D1c56caC55b68A3), 0, 2);
        creditPositions.push(positionId);


        // 31) Trust AaveDebtTokenAdaptor DAI debt token position
        positionId = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(0x6C3c78838c761c6Ac7bE9F59fe808ea2A6E4379d), 0, 2);
        debtPositions.push(positionId);


        // 32) Trust AaveATokenAdaptor aUSDT position
        positionId = registry.trustPosition(address(aaveATokenAdaptor), abi.encode(0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811), 0, 2);
        creditPositions.push(positionId);


        // 33) Trust AaveDebtTokenAdaptor USDT debt token position
        positionId = registry.trustPosition(address(aaveDebtTokenAdaptor), abi.encode(0x531842cEbbdD378f8ee36D171d6cC9C4fcf475Ec), 0, 2);
        debtPositions.push(positionId);


        // 34) Trust CTokenAdaptor cUSDC position
        positionId = registry.trustPosition(address(cTokenAdaptor), abi.encode(0x39AA39c021dfbaE8faC545936693aC917d5E7563), 0, 2);
        creditPositions.push(positionId);


        // 35) Trust CTokenAdaptor cDAI position
        positionId = registry.trustPosition(address(cTokenAdaptor), abi.encode(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643), 0, 2);
        creditPositions.push(positionId);


        // 36) Trust CTokenAdaptor cUSDT position
        positionId = registry.trustPosition(address(cTokenAdaptor), abi.encode(0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9), 0, 2);
        creditPositions.push(positionId);


        // 37) Trust VestingSimpleAdaptor vesting position
        positionId = registry.trustPosition(address(vestingSimpleAdaptor), abi.encode(address(vestingSimple)), 0, 0);
        creditPositions.push(positionId);

    }

    function setupFactory() internal {
        // 38) Set self to deployer
        cellarFactory.adjustIsDeployer(0xbaf7d863B4504D520797EFef4434F2067C1142c5, true);

        // 39) Deploy CellarInitializeable template
        cellarTemplate = new CellarInitializable(registry);

        // 40) Add implementation to factory
        cellarFactory.addImplementation(address(cellarTemplate), 2, 0);
    }

    function deployCellar() internal {
        // Deploy the cellar via factory
        bytes memory params = abi.encode(
            creditPositions,
            debtPositions,
            new bytes[](creditPositions.length),
            new bytes[](debtPositions.length),
            holdingPositionId,
            strategist,
            100,
            100
        );

        address newCellar = cellarFactory.deploy(
            2,
            0,
            abi.encode(
                registry,
                USDC,
                "CellarV2 Test",
                "cV2 Test",
                params
            ),
            USDC,
            0,
            keccak256(abi.encode(block.timestamp))
        );

        emit Deploy("Cellar", newCellar);

        Cellar cellar = Cellar(newCellar);

        emit Deploy("RegistryOwner", registry.owner());
        emit Deploy("CellarRegistryReport", registry.getAddress(cellar.GRAVITY_BRIDGE_REGISTRY_SLOT()));
        emit Deploy("CellarOwner", cellar.owner());
        emit Deploy("LastCaller", address(this));

        // Set up each adaptor
        cellar.setupAdaptor(address(uniswapV3Adaptor));
        cellar.setupAdaptor(address(aaveATokenAdaptor));
        cellar.setupAdaptor(address(aaveDebtTokenAdaptor));
        cellar.setupAdaptor(address(cTokenAdaptor));
        cellar.setupAdaptor(address(vestingSimpleAdaptor));

        // Send ownership to strategist
        cellar.transferOwnership(address(strategist));
    }
}
