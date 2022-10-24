// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { IPool } from "src/interfaces/external/IPool.sol";
import { BaseAdaptor } from "src/modules/adaptors/BaseAdaptor.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";
import { DataTypes } from "src/interfaces/external/DataTypes.sol";
import { Cellar } from "src/base/Cellar.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";

import { console } from "@forge-std/Test.sol";

/**
 * @title Lending Adaptor
 * @notice Cellars make delegate call to this contract in order touse
 * @author crispymangoes, Brian Le
 * @dev while testing on forked mainnet, aave deposits would sometimes return 1 less aUSDC, and sometimes return the exact amount of USDC you put in
 * Block where USDC in == aUSDC out 15174148
 * Block where USDC-1 in == aUSDC out 15000000
 */

contract AaveATokenAdaptor is BaseAdaptor {
    using SafeERC20 for ERC20;

    /*
        adaptorData = abi.encode(aToken address)
    */

    //============================================ Global Functions ===========================================
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Aave aToken Adaptor V 0.0"));
    }

    function pool() internal pure returns (IPool) {
        return IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    }

    function WETH() internal pure returns (ERC20) {
        return ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }

    //============================================ Implement Base Functions ===========================================
    // Config data is not used because depositing will only INCREASE health factor.
    function deposit(
        uint256 assets,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        depositToAave(ERC20(token.UNDERLYING_ASSET_ADDRESS()), assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory configData
    ) public override {
        if (receiver != address(this) && Cellar(address(this)).blockExternalReceiver())
            revert("External receivers are not allowed.");
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        withdrawFromAave(ERC20(token.UNDERLYING_ASSET_ADDRESS()), assets);

        // Check that configured min health factor is met.
        uint256 minHealthFactor = abi.decode(configData, (uint256));
        if (minHealthFactor > 0) {
            (, , , , , uint256 healthFactor) = pool().getUserAccountData(msg.sender);
            require(healthFactor > minHealthFactor, "Health Factor too low.");
        }
        ERC20(token.UNDERLYING_ASSET_ADDRESS()).safeTransfer(receiver, assets);
    }

    function withdrawableFrom(bytes memory adaptorData, bytes memory configData)
        public
        view
        override
        returns (uint256)
    {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        uint256 minHealthFactor = abi.decode(configData, (uint256));
        (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool().getUserAccountData(msg.sender);
        uint256 maxBorrowableWithMin;
        if (totalDebtETH == 0) return ERC20(address(token)).balanceOf(msg.sender);
        if (minHealthFactor == 0) maxBorrowableWithMin = availableBorrowsETH;
        else {
            maxBorrowableWithMin =
                ((totalCollateralETH * currentLiquidationThreshold) / minHealthFactor) -
                totalDebtETH;
        }

        PriceRouter priceRouter = PriceRouter(Cellar(msg.sender).registry().getAddress(2));
        return priceRouter.getValue(WETH(), maxBorrowableWithMin, ERC20(token.UNDERLYING_ASSET_ADDRESS()));
    }

    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        address token = abi.decode(adaptorData, (address));
        return ERC20(token).balanceOf(msg.sender);
    }

    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        return ERC20(token.UNDERLYING_ASSET_ADDRESS());
    }

    //============================================ High Level Callable Functions ============================================
    function depositToAave(ERC20 tokenToDeposit, uint256 amountToDeposit) public {
        tokenToDeposit.safeApprove(address(pool()), amountToDeposit);
        pool().deposit(address(tokenToDeposit), amountToDeposit, address(this), 0);
    }

    function withdrawFromAave(ERC20 tokenToWithdraw, uint256 amountToWithdraw) public {
        pool().withdraw(address(tokenToWithdraw), amountToWithdraw, address(this));
    }

    //============================================ AAVE Logic ============================================
}
