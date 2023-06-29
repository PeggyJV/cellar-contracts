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
import { MockFTokenAdaptor } from "src/mocks/adaptors/MockFTokenAdaptor.sol";
import "forge-std/Script.sol";
import { Math } from "src/utils/Math.sol";

/**
 * @dev Run
 *      `source .env && forge script script/prod/Mainnet/DeployFraximal.s.sol:DeployFraximalScript --rpc-url $MAINNET_RPC_URL  --private-key $PRIVATE_KEY —optimize —optimizer-runs 200 --with-gas-price 25000000000 --verify --etherscan-api-key $ETHERSCAN_KEY --slow --broadcast`
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract DeployFraximalScript is Script {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    CellarInitializableV2_2 private cellar;

    address private devOwner = 0x552acA1343A6383aF32ce1B7c7B1b47959F7ad90;
    address private strategist = 0xA9962a5BfBea6918E958DeE0647E99fD7863b95A;

    // Define Adaptors.
    ERC20Adaptor private erc20Adaptor = ERC20Adaptor(0xB1d08c5a1A67A34d9dC6E9F2C5fAb797BA4cbbaE);
    FTokenAdaptor private fTokenAdaptorV2 = FTokenAdaptor(0x13C7DA01977E6de1dFa8B135DA34BD569650Acb9);
    FTokenAdaptorV1 private fTokenAdaptorV1 = FTokenAdaptorV1(0x4e4E5610885c6c2c8D9ad92e36945FB7092aADae);

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

    Registry private registry = Registry(0xc3ddF6F2512c16d0780Ff03Ec621E81a0919F1CA);
    CellarFactory private factory = CellarFactory(0x0C6B501c3ee7D26D86633A581434105D40DB239B);
    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    ERC20 private FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);

    function run() external {
        uint32[] memory positions = new uint32[](15);

        vm.startBroadcast();

        // positions[0] = ;  // FRAX position
        // positions[1] = ;  // FPI_PAIR_v1 position
        // positions[2] = ;  // FXS_PAIR_v1 position
        // positions[3] = ;  // wBTC_PAIR_v1 position
        // positions[4] = ;  // wETH_PAIR_v1 position
        // positions[5] = ;  // gOHM_PAIR_v1 position
        // positions[6] = ;  // Curve_PAIR_v1 position
        // positions[7] = ;  // Convex_PAIR_v1 position
        // positions[8] = ;  // AAVE_PAIR_v2 position
        // positions[9] = ;  // Uni_PAIR_v2 position
        // positions[10] = ; // MKR_PAIR_v2 position
        // positions[11] = ; // APE_PAIR_v2 position
        // positions[12] = ; // FRAX_USDC_Curve_LP_PAIR_v2 position
        // positions[13] = ; // frxETH_ETH_Curve_LP_PAIR_v2 position
        // positions[14] = ; // sfrxETH_PAIR_v2 position

        {
            // Deploy cellar using factory.
            bytes memory initializeCallData = abi.encode(
                devOwner,
                registry,
                FRAX,
                "FRAXIMAL",
                "FRAXI",
                positions[0],
                abi.encode(0),
                strategist
            );
            address imp = factory.getImplementation(2, 2);
            require(imp != address(0), "Invalid implementation");

            uint256 initialDeposit = 1e18;
            FRAX.approve(address(factory), initialDeposit);

            address clone = factory.deploy(
                2,
                2,
                initializeCallData,
                FRAX,
                initialDeposit,
                keccak256(abi.encode(block.timestamp))
            );
            cellar = CellarInitializableV2_2(clone);

            // Setup all the adaptors the cellar will use.
            cellar.addAdaptorToCatalogue(address(fTokenAdaptorV2));
            cellar.addAdaptorToCatalogue(address(fTokenAdaptorV1));

            for (uint256 i = 1; i < positions.length; ++i) cellar.addPositionToCatalogue(positions[i]);
    }
}
