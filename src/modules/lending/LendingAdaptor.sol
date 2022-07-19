// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import { IPool } from "@aave/interfaces/IPool.sol";
import { BaseAdaptor } from "src/modules/BaseAdaptor.sol";
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
 * @dev while testing on forked mainnet, aave deposits would sometimes return 1 less aUSDC, and sometimes return the exact amount of USDC you put in
 * Block where USDC in == aUSDC out 15174148
 * Block where USDC-1 in == aUSDC out 15000000
 */

contract LendingAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    function routeCalls(uint8[] memory functionsToCall, bytes[] memory callData) public {
        for (uint8 i = 0; i < functionsToCall.length; i++) {
            if (functionsToCall[i] == 1) {
                depositToAave(callData[i]);
            } else if (functionsToCall[i] == 2) {
                borrowFromAave(callData[i]);
            } else if (functionsToCall[i] == 3) {
                repayAaveDebt(callData[i]);
            } else if (functionsToCall[i] == 4) {
                withdrawFromAave(callData[i]);
            } else if (functionsToCall[i] == 5) {
                addLiquidityAndFarmSushi(callData[i]);
            } else if (functionsToCall[i] == 6) {
                harvestSushiFarms(callData[i]);
            } else if (functionsToCall[i] == 7) {
                withdrawFromFarmAndLPSushi(callData[i]);
            }
        }
    }

    //============================================ Override Hooks ===========================================
    function afterHook(bytes memory hookData) public view override returns (bool) {
        //TODO hookDat would contain a minimum healthFactor or something
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(address(this));

        return true;
    }

    //============================================ High Level Callable Functions ============================================
    function depositToAave(bytes memory callData) public {
        (ERC20 tokenToDeposit, uint256 amountToDeposit) = abi.decode(callData, (ERC20, uint256));
        amountToDeposit = _maxAvailable(tokenToDeposit, amountToDeposit);
        _depositToAave(tokenToDeposit, amountToDeposit);
    }

    function borrowFromAave(bytes memory callData) public {
        (ERC20 tokenToBorrow, uint256 amountToBorrow) = abi.decode(callData, (ERC20, uint256));
        _borrowFromAave(tokenToBorrow, amountToBorrow);
    }

    function repayAaveDebt(bytes memory callData) public {
        (ERC20 tokenToRepay, uint256 amountToRepay) = abi.decode(callData, (ERC20, uint256));
        amountToRepay = _maxAvailable(tokenToRepay, amountToRepay);
        _repayAaveDebt(tokenToRepay, amountToRepay);
    }

    function withdrawFromAave(bytes memory callData) public {
        (ERC20 tokenToWithdraw, uint256 amountToWithdraw) = abi.decode(callData, (ERC20, uint256));
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        address aToken = pool.getReserveData(address(tokenToWithdraw)).aTokenAddress;
        amountToWithdraw = _maxAvailable(ERC20(aToken), amountToWithdraw);
        _withdrawFromAave(tokenToWithdraw, amountToWithdraw);
    }

    function addLiquidityAndFarmSushi(bytes memory callData) public {
        (
            ERC20 tokenA,
            ERC20 tokenB,
            uint256 amountA,
            uint256 amountB,
            uint256 minimumA,
            uint256 minimumB,
            uint256 pid
        ) = abi.decode(callData, (ERC20, ERC20, uint256, uint256, uint256, uint256, uint256));
        _addLiquidityAndFarmSushi(tokenA, tokenB, amountA, amountB, minimumA, minimumB, pid);
    }

    function harvestSushiFarms(bytes memory callData) public {
        (uint256 pid, ERC20[] memory rewardTokens, bytes memory swapData) = abi.decode(
            callData,
            (uint256, ERC20[], bytes)
        );
        _harvestSushiFarms(pid, rewardTokens, swapData);
    }

    function withdrawFromFarmAndLPSushi(bytes memory callData) public {
        (ERC20 tokenA, ERC20 tokenB, uint256 liquidity, uint256 minimumA, uint256 minimumB, uint256 pid) = abi.decode(
            callData,
            (ERC20, ERC20, uint256, uint256, uint256, uint256)
        );
        _withdrawFromFarmAndLPSushi(tokenA, tokenB, liquidity, minimumA, minimumB, pid);
    }

    function getSushiFarmBalance(bytes memory adaptorData) public view returns (uint256) {
        uint256 pid = abi.decode(adaptorData, (uint256));
        IMasterChef chef = IMasterChef(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d);
        return chef.userInfo(pid, address(this)).amount;
    }

    function getSushiFarmAsset(bytes memory adaptorData) public view returns (address) {
        uint256 pid = abi.decode(adaptorData, (uint256));
        IMasterChef chef = IMasterChef(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d);
        return chef.lpToken(pid);
    }

    //============================================ AAVE Logic ============================================
    //TODO might need to add a check that toggles use reserve as collateral
    function _depositToAave(ERC20 tokenToDeposit, uint256 amountToDeposit) internal {
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        tokenToDeposit.safeApprove(address(pool), amountToDeposit);
        pool.deposit(address(tokenToDeposit), amountToDeposit, address(this), 0);
    }

    function _borrowFromAave(ERC20 tokenToBorrow, uint256 amountToBorrow) internal {
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        pool.borrow(address(tokenToBorrow), amountToBorrow, 2, 0, address(this)); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
    }

    function _repayAaveDebt(ERC20 tokenToRepay, uint256 amountToRepay) internal {
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        tokenToRepay.safeApprove(address(pool), amountToRepay);
        pool.repay(address(tokenToRepay), amountToRepay, 2, address(this)); // 2 is the interest rate mode,  ethier 1 for stable or 2 for variable
    }

    function _withdrawFromAave(ERC20 tokenToWithdraw, uint256 amountToWithdraw) internal {
        IPool pool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        pool.withdraw(address(tokenToWithdraw), amountToWithdraw, address(this));
    }

    //============================================ SUSHI Logic ============================================
    function _addLiquidityAndFarmSushi(
        ERC20 tokenA,
        ERC20 tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 minimumA,
        uint256 minimumB,
        uint256 pid
    ) internal {
        IUniswapV2Router router = IUniswapV2Router(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F); //mainnet sushi router
        IMasterChef chef = IMasterChef(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d); //mainnet sushi chef
        tokenA.safeApprove(address(router), amountA);
        tokenB.safeApprove(address(router), amountB);
        uint256 liquidity;
        (amountA, amountB, liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            minimumA,
            minimumB,
            address(this),
            block.timestamp
        );
        //TODO what to do if amountA/B is alot less than amounts[i/i+1]
        //TODO could do a value in vs value out check here
        //add LP tokens to farm
        ERC20(chef.lpToken(pid)).safeApprove(address(chef), liquidity);
        chef.deposit(pid, liquidity, address(this));
    }

    //TODO on polygon sushiswap has run out of rewards several times.
    //when this happens, any harvest TXs revert, might need to take this into account here
    ///@dev rewardToken length must be 2x farms length, each farm is assuemd to have 2 reward tokens, if it only has one, then i+1 reward token should be zero address
    function _harvestSushiFarms(
        uint256 pid,
        ERC20[] memory rewardTokens,
        bytes memory swapData
    ) internal {
        IMasterChef chef = IMasterChef(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d); //mainnet sushi chef
        //SwapRouter swapRouter = SwapRouter(registry.getAddress(1));
        uint256[] memory rewardsOut = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i += 2) {
            if (address(rewardTokens[i]) != address(0)) rewardsOut[i] = rewardTokens[i].balanceOf(address(this));
        }

        chef.harvest(pid, address(this));

        for (uint256 i = 0; i < rewardTokens.length; i += 2) {
            if (address(rewardTokens[i]) != address(0))
                rewardsOut[i] = rewardTokens[i].balanceOf(address(this)) - rewardsOut[i];
        }
    }

    function _withdrawFromFarmAndLPSushi(
        ERC20 tokenA,
        ERC20 tokenB,
        uint256 liquidity,
        uint256 minimumA,
        uint256 minimumB,
        uint256 pid
    ) internal {
        IUniswapV2Router router = IUniswapV2Router(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F); //mainnet sushi router
        IMasterChef chef = IMasterChef(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d); //mainnet sushi chef
        //TODO use the above harvest function to harvest the farms before withdrawing?
        chef.withdraw(pid, liquidity, address(this));
        ERC20(chef.lpToken(1)).safeApprove(address(router), liquidity);
        (uint256 amountA, uint256 amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            minimumA,
            minimumB,
            address(this),
            block.timestamp
        );

        //TODO do a value in vs value out check using fair LP pricing?
    }
}
