// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";

// Import adaptors.
import { FTokenAdaptorV1 } from "src/modules/adaptors/Frax/FTokenAdaptorV1.sol";
import { FTokenAdaptor } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import { ERC20Adaptor } from "src/modules/adaptors/ERC20Adaptor.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";

import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/test/Mainnet/DeployFraximal.s.sol:DeployFraximalScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployFraximalScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    CellarInitializableV2_2 private cellar;

    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private strategist = 0xeeF7b7205CAF2Bcd71437D9acDE3874C3388c138;

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor = ERC20Adaptor(0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE);
    FTokenAdaptor private fTokenAdaptorV2;
    FTokenAdaptorV1 private fTokenAdaptorV1;

    Registry private registry = Registry(0xc3ddF6F2512c16d0780Ff03Ec621E81a0919F1CA);
    CellarFactory private factory = CellarFactory(0x0C6B501c3ee7D26D86633A581434105D40DB239B);
    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    ERC20 private FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);

    // FraxLend Pairs
    address private FPI_PAIR_v1 = 0x74F82Bd9D0390A4180DaaEc92D64cf0708751759;
    address private FXS_PAIR_v1 = 0xDbe88DBAc39263c47629ebbA02b3eF4cf0752A72;
    address private wBTC_PAIR_v1 = 0x32467a5fc2d72D21E8DCe990906547A2b012f382;
    address private wETH_PAIR_v1 = 0x794F6B13FBd7EB7ef10d1ED205c9a416910207Ff;
    address private gOHM_PAIR_v1 = 0x66bf36dBa79d4606039f04b32946A260BCd3FF52;
    address private Curve_PAIR_v1 = 0x3835a58CA93Cdb5f912519ad366826aC9a752510;
    address private Convex_PAIR_v1 = 0xa1D100a5bf6BFd2736837c97248853D989a9ED84;
    address private AAVE_PAIR_v2 = 0xc779fEE076EB04b9F8EA424ec19DE27Efd17A68d;
    address private Uni_PAIR_v2 = 0xc6CadA314389430d396C7b0C70c6281e99ca7fe8;
    address private MKR_PAIR_v2 = 0x82Ec28636B77661a95f021090F6bE0C8d379DD5D;
    address private APE_PAIR_v2 = 0x3a25B9aB8c07FfEFEe614531C75905E810d8A239;
    address private FRAX_USDC_Curve_LP_PAIR_v2 = 0x1Fff4a418471a7b44EFa023320e02DCDB486ED77;
    address private frxETH_ETH_Curve_LP_PAIR_v2 = 0x281E6CB341a552E4faCCc6b4eEF1A6fCC523682d;
    address private sfrxETH_PAIR_v2 = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15;

    function run() external {
        uint32[] memory positions = new uint32[](15);

        vm.startBroadcast();

        // Deploy Adaptors.
        fTokenAdaptorV2 = new FTokenAdaptor();
        fTokenAdaptorV1 = new FTokenAdaptorV1();

        // Trust adaptors.
        registry.trustAdaptor(address(fTokenAdaptorV2));
        registry.trustAdaptor(address(fTokenAdaptorV1));

        // Add Positions to registry.
        positions[0] = registry.trustPosition(address(erc20Adaptor), abi.encode(FRAX));
        // Add FraxLend V2 Positions.
        positions[1] = registry.trustPosition(address(fTokenAdaptorV2), abi.encode(address(AAVE_PAIR_v2)));
        positions[2] = registry.trustPosition(address(fTokenAdaptorV2), abi.encode(address(Uni_PAIR_v2)));
        positions[3] = registry.trustPosition(address(fTokenAdaptorV2), abi.encode(address(MKR_PAIR_v2)));
        positions[4] = registry.trustPosition(address(fTokenAdaptorV2), abi.encode(address(APE_PAIR_v2)));
        positions[5] = registry.trustPosition(
            address(fTokenAdaptorV2),
            abi.encode(address(FRAX_USDC_Curve_LP_PAIR_v2))
        );
        positions[6] = registry.trustPosition(
            address(fTokenAdaptorV2),
            abi.encode(address(frxETH_ETH_Curve_LP_PAIR_v2))
        );
        positions[7] = registry.trustPosition(address(fTokenAdaptorV2), abi.encode(address(sfrxETH_PAIR_v2)));
        // Add FraxLend V1 Positions.
        positions[8] = registry.trustPosition(address(fTokenAdaptorV1), abi.encode(address(FPI_PAIR_v1)));
        positions[9] = registry.trustPosition(address(fTokenAdaptorV1), abi.encode(address(FXS_PAIR_v1)));
        positions[10] = registry.trustPosition(address(fTokenAdaptorV1), abi.encode(address(wBTC_PAIR_v1)));
        positions[11] = registry.trustPosition(address(fTokenAdaptorV1), abi.encode(address(wETH_PAIR_v1)));
        positions[12] = registry.trustPosition(address(fTokenAdaptorV1), abi.encode(address(gOHM_PAIR_v1)));
        positions[13] = registry.trustPosition(address(fTokenAdaptorV1), abi.encode(address(Curve_PAIR_v1)));
        positions[14] = registry.trustPosition(address(fTokenAdaptorV1), abi.encode(address(Convex_PAIR_v1)));

        // Deploy cellar using factory.
        bytes memory initializeCallData = abi.encode(
            devOwner,
            registry,
            FRAX,
            "Test Fraximal",
            "rawr",
            positions[13],
            abi.encode(0),
            strategist
        );
        address imp = factory.getImplementation(2, 2);
        require(imp != address(0), "Invalid implementation");

        address clone = factory.deploy(2, 2, initializeCallData, FRAX, 0, keccak256(abi.encode(block.timestamp)));
        cellar = CellarInitializableV2_2(clone);

        // Setup all the adaptors the cellar will use.
        cellar.addAdaptorToCatalogue(address(fTokenAdaptorV2));
        cellar.addAdaptorToCatalogue(address(fTokenAdaptorV1));

        cellar.addPositionToCatalogue(positions[0]);
        cellar.addPositionToCatalogue(positions[1]);
        cellar.addPositionToCatalogue(positions[2]);
        cellar.addPositionToCatalogue(positions[3]);
        cellar.addPositionToCatalogue(positions[4]);
        cellar.addPositionToCatalogue(positions[5]);
        cellar.addPositionToCatalogue(positions[6]);
        cellar.addPositionToCatalogue(positions[7]);
        cellar.addPositionToCatalogue(positions[8]);
        cellar.addPositionToCatalogue(positions[9]);
        cellar.addPositionToCatalogue(positions[10]);
        cellar.addPositionToCatalogue(positions[11]);
        cellar.addPositionToCatalogue(positions[12]);
        cellar.addPositionToCatalogue(positions[14]);

        cellar.transferOwnership(strategist);

        vm.stopBroadcast();
    }
}
