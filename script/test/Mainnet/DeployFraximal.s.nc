// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Cellar, ERC4626, ERC20, SafeTransferLib } from "src/base/Cellar.sol";
import { CellarInitializableV2_2 } from "src/base/CellarInitializableV2_2.sol";
import { CellarFactory } from "src/CellarFactory.sol";
import { Registry, PriceRouter } from "src/base/Cellar.sol";
import {  IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";

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
    // Do NOT account for V2 interest.
    MockFTokenAdaptor private fTokenAdaptorV2NoInterest;

    Registry private registry = Registry(0xc3ddF6F2512c16d0780Ff03Ec621E81a0919F1CA);
    CellarFactory private factory = CellarFactory(0x0C6B501c3ee7D26D86633A581434105D40DB239B);
    PriceRouter private priceRouter = PriceRouter(0x138a6d8c49428D4c71dD7596571fbd4699C7D3DA);
    ERC20 private FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);

    // FraxLend Pairs
    address private Curve_PAIR_v1 = 0x3835a58CA93Cdb5f912519ad366826aC9a752510;
    address private sfrxETH_PAIR_v2 = 0x78bB3aEC3d855431bd9289fD98dA13F9ebB7ef15;

    function run() external {
        uint32[] memory positions = new uint32[](15);

        vm.startBroadcast();

        // Deploy Adaptors.
        fTokenAdaptorV2 = new FTokenAdaptor(true, address(FRAX));
        fTokenAdaptorV1 = new FTokenAdaptorV1(true, address(FRAX));
        // Deploy no interest adaptor.
        fTokenAdaptorV2NoInterest = new MockFTokenAdaptor(false, address(FRAX));

        // Trust adaptors.
        registry.trustAdaptor(address(fTokenAdaptorV2));
        registry.trustAdaptor(address(fTokenAdaptorV1));
        registry.trustAdaptor(address(fTokenAdaptorV2NoInterest));

        // Add Positions to registry.
        positions[0] = 108; //registry.trustPosition(address(erc20Adaptor), abi.encode(FRAX));
        // Add FraxLend V2 Positions.
        positions[1] = registry.trustPosition(address(fTokenAdaptorV2), abi.encode(address(sfrxETH_PAIR_v2)));
        positions[2] = registry.trustPosition(address(fTokenAdaptorV2NoInterest), abi.encode(address(sfrxETH_PAIR_v2)));
        // Add FraxLend V1 Positions.
        positions[3] = registry.trustPosition(address(fTokenAdaptorV1), abi.encode(address(Curve_PAIR_v1)));

        {
            // Deploy cellar using factory.
            bytes memory initializeCallData = abi.encode(
                devOwner,
                registry,
                FRAX,
                "Test Fraximal",
                "rawr",
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

            cellar.addPositionToCatalogue(positions[1]);
            cellar.addPositionToCatalogue(positions[3]);

            cellar.addPosition(1, positions[1], abi.encode(0), false);
            cellar.addPosition(2, positions[3], abi.encode(0), false);

            // Deposit 400 FRAX into the cellar.
            FRAX.approve(address(cellar), 500e18);
            cellar.deposit(400e18, devOwner);

            // Rebalance Cellar so 300 FRAX is in Curve and remainder is in sfrx.
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
            {
                bytes[] memory adaptorCalls = new bytes[](1);
                adaptorCalls[0] = _createBytesDataToLend(Curve_PAIR_v1, 300e18);
                data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV1), callData: adaptorCalls });
            }
            {
                bytes[] memory adaptorCalls = new bytes[](1);
                adaptorCalls[0] = _createBytesDataToLend(sfrxETH_PAIR_v2, type(uint256).max);
                data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2), callData: adaptorCalls });
            }

            // Perform callOnAdaptor.
            cellar.callOnAdaptor(data);

            // Now that cellar is in multiple positions, deposit remaining 100e18 FRAX.
            cellar.deposit(100e18, devOwner);
        }
        //---------------------------------------------- Deploy more gas efficient version -----------------------------------
        {
            // Deploy cellar using factory.
            bytes memory initializeCallData = abi.encode(
                devOwner,
                registry,
                FRAX,
                "Test Fraximal No Interest",
                "rawr",
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
                keccak256(abi.encode(block.timestamp + 1))
            );
            cellar = CellarInitializableV2_2(clone);

            // Setup all the adaptors the cellar will use.
            cellar.addAdaptorToCatalogue(address(fTokenAdaptorV2NoInterest));
            cellar.addAdaptorToCatalogue(address(fTokenAdaptorV1));

            cellar.addPositionToCatalogue(positions[2]);
            cellar.addPositionToCatalogue(positions[3]);

            cellar.addPosition(1, positions[2], abi.encode(0), false);
            cellar.addPosition(2, positions[3], abi.encode(0), false);

            // Deposit 400 FRAX into the cellar.
            FRAX.approve(address(cellar), 500e18);
            cellar.deposit(400e18, devOwner);

            // Rebalance Cellar so 300 FRAX is in Curve and remainder is in sfrx.
            Cellar.AdaptorCall[] memory data = new Cellar.AdaptorCall[](2);
            {
                bytes[] memory adaptorCalls = new bytes[](1);
                adaptorCalls[0] = _createBytesDataToLend(Curve_PAIR_v1, 300e18);
                data[0] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV1), callData: adaptorCalls });
            }
            {
                bytes[] memory adaptorCalls = new bytes[](1);
                adaptorCalls[0] = _createBytesDataToLend(sfrxETH_PAIR_v2, type(uint256).max);
                data[1] = Cellar.AdaptorCall({ adaptor: address(fTokenAdaptorV2NoInterest), callData: adaptorCalls });
            }

            // Perform callOnAdaptor.
            cellar.callOnAdaptor(data);

            // Now that cellar is in multiple positions, deposit remaining 100e18 FRAX.
            cellar.deposit(100e18, devOwner);
        }

        vm.stopBroadcast();
    }

    function _createBytesDataToLend(address fToken, uint256 amountToDeposit) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.lendFrax.selector, fToken, amountToDeposit);
    }

    function _createBytesDataToRedeem(address fToken, uint256 amountToRedeem) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.redeemFraxShare.selector, fToken, amountToRedeem);
    }

    function _createBytesDataToWithdraw(address fToken, uint256 amountToWithdraw) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FTokenAdaptor.withdrawFrax.selector, fToken, amountToWithdraw);
    }
}
