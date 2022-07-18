// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { IPool } from "@aave/interfaces/IPool.sol";
import { ERC4626, ERC20 } from "src/base/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/IUniswapV2Router02.sol";
import { IMasterChef } from "src/interfaces/IMasterChef.sol";
import { Registry } from "src/Registry.sol";
import { SwapRouter } from "src/modules/swap-router/SwapRouter.sol";

/**
 * @title Lending Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 */
contract LendingAdaptor {
    using SafeTransferLib for ERC20;

    function routeCalls(uint8[] memory functionsToCall, bytes[] memory callData) public {
        for (uint8 i = 0; i < functionsToCall.length; i++) {
            if (functionsToCall[i] == 1) {
                _depositToAave(callData[i]);
            } else if (functionsToCall[i] == 2) {
                _borrowFromAave(callData[i]);
            } else if (functionsToCall[i] == 3) {
                _repayAaveDebt(callData[i]);
            } else if (functionsToCall[i] == 4) {
                _addLiquidityAndFarmSushi(callData[i]);
            } else if (functionsToCall[i] == 5) {
                _harvestSushiFarms(callData[i]);
            }
        }
    }

    //============================================ AAVE ============================================
    //TODO might need to add a check that toggles use reserve as collateral
    function _depositToAave(bytes memory callData) internal {
        (ERC20[] memory tokens, uint256[] memory amounts) = abi.decode(callData, (ERC20[], uint256[]));
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].safeApprove(address(pool), amounts[i]);
            pool.deposit(address(tokens[i]), amounts[i], address(this), 0);
        }
    }

    function _borrowFromAave(bytes memory callData) internal {
        (ERC20[] memory tokens, uint256[] memory amounts) = abi.decode(callData, (ERC20[], uint256[]));
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        for (uint256 i = 0; i < tokens.length; i++) {
            pool.borrow(address(tokens[i]), amounts[i], 2, 0, address(this)); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
        }
    }

    function _repayAaveDebt(bytes memory callData) internal {
        (ERC20[] memory tokens, uint256[] memory amounts) = abi.decode(callData, (ERC20[], uint256[]));
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].safeApprove(address(pool), amounts[i]);
            pool.repay(address(tokens[i]), amounts[i], 2, address(this)); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
        }
    }

    //============================================ SUSHI ============================================
    function _addLiquidityAndFarmSushi(bytes memory callData) internal {
        (ERC20[] memory tokens, uint256[] memory amounts, uint256[] memory minimums, uint256[] memory farms) = abi
            .decode(callData, (ERC20[], uint256[], uint256[], uint256[]));
        IUniswapV2Router router = IUniswapV2Router(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F); //mainnet sushi router
        IMasterChef chef = IMasterChef(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d); //mainnet sushi chef
        for (uint256 i = 0; i < tokens.length; i += 2) {
            tokens[i].safeApprove(address(router), amounts[i]);
            tokens[i + 1].safeApprove(address(router), amounts[i + 1]);
            (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
                address(tokens[i]),
                address(tokens[i + 1]),
                amounts[i],
                amounts[i + 1],
                minimums[i],
                minimums[i + 1],
                address(this),
                block.timestamp
            );
            //TODO what to do if amountA/B is alot less than amounts[i/i+1]
            //TODO could do a value in vs value out check here
            //add LP tokens to farm
            ERC20(chef.lpToken(farms[i / 2])).safeApprove(address(chef), liquidity);
            chef.deposit(farms[i / 2], liquidity, address(this));
        }
    }

    ///@dev rewardToken length must be 2x farms length, each farm is assuemd to have 2 reward tokens, if it only has one, then i+1 reward token should be zero address
    function _harvestSushiFarms(bytes memory callData) internal {
        (uint256[] memory farms, ERC20[] memory rewardTokens, bytes[] memory swapData) = abi.decode(
            callData,
            (uint256[], ERC20[], bytes[])
        );
        IMasterChef chef = IMasterChef(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d); //mainnet sushi chef
        //SwapRouter swapRouter = SwapRouter(registry.getAddress(1));
        uint256[] memory rewardsOut = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < farms.length; i += 2) {
            rewardsOut[i] = rewardTokens[i].balanceOf(address(this));
            if (address(rewardTokens[i + 1]) != address(0))
                rewardsOut[i + 1] = rewardTokens[i + 1].balanceOf(address(this));

            chef.harvest(farms[i], address(this));

            rewardsOut[i] = rewardTokens[i].balanceOf(address(this)) - rewardsOut[i];
            if (address(rewardTokens[i + 1]) != address(0))
                rewardsOut[i + 1] = rewardTokens[i + 1].balanceOf(address(this)) - rewardsOut[i + 1];
        }
    }
}
