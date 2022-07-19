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

contract SushiAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;

    //============================================ High Level Callable Functions ============================================
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
        return chef.userInfo(pid, msg.sender).amount;
    }

    function getSushiFarmAsset(bytes memory adaptorData) public view returns (address) {
        uint256 pid = abi.decode(adaptorData, (uint256));
        IMasterChef chef = IMasterChef(0xEF0881eC094552b2e128Cf945EF17a6752B4Ec5d);
        return chef.lpToken(pid);
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
