// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeERC20, Cellar, PriceRouter } from "src/modules/adaptors/BaseAdaptor.sol";
import { CTokenInterface } from "src/interfaces/external/CTokenInterfaces.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ICompoundToken } from "src/interfaces/external/ICompoundToken.sol";


abstract contract CToken is IERC20Upgradeable {
    function supplyRatePerBlock() external view virtual returns (uint256);

    function mint(uint256 mintAmount) external virtual returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external virtual returns (uint256);

    function balanceOfUnderlying(address owner) external virtual returns (uint256);

    function exchangeRateStored() external view virtual returns (uint256);
}

interface CTokenInterface {
    /// @notice cToken is convertible into an ever increasing quantity of the underlying asset, as interest accrues in
    /// the market. This function returns the exchange rate between a cToken and the underlying asset.
    /// @dev returns the current exchange rate as an uint, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals).
    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function decimals() external returns (uint256);

    function underlying() external view returns (address);

    /// The mint function transfers an asset into the protocol, which begins accumulating interest based
    /// on the current Supply Rate for the asset. The user receives a quantity of cTokens equal to the
    /// underlying tokens supplied, divided by the current Exchange Rate.
    /// @param mintAmount The amount of the asset to be supplied, in units of the underlying asset.
    /// @return 0 on success, otherwise an Error code
    function mint(uint256 mintAmount) external returns (uint256);

    /// The redeem function converts a specified quantity of cTokens into the underlying asset, and returns
    /// them to the user. The amount of underlying tokens received is equal to the quantity of cTokens redeemed,
    /// multiplied by the current Exchange Rate. The amount redeemed must be less than the user's Account Liquidity
    /// and the market's available liquidity.
    /// @param redeemTokens The number of cTokens to be redeemed.
    /// @return 0 on success, otherwise an Error code
    function redeem(uint256 redeemTokens) external returns (uint256);
}

contract CErc20Storage {
    /**
     * @notice Underlying asset for this CToken
     */
    address public underlying;
}

/**
 * @title Compound cToken Adaptor
 * @notice Allows Cellars to interact with Aave aToken positions.
 * @author mnm458 & mrhouzlane
 */

contract CompoundTokenAdapter is BaseAdaptor {
    using SafeERC20 for ERC20;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address cToken)
    // Where:
    // `cToken` is the cToken address position this adaptor is working with
    //================= Configuration Data Specification =================
    // configurationData = abi.encode(minimumHealthFactor uint256)
    // Where:
    // `minimumHealthFactor` dictates how much assets can be taken from this position
    // If zero:
    //      position returns ZERO for `withdrawableFrom`
    // else:
    //      position calculates `withdrawableFrom` based off minimum specified
    //      position reverts if a user withdraw lowers health factor below minimum
    //
    // **************************** IMPORTANT ****************************
    // Cellars with multiple cToken positions MUST only specify minimum
    // health factor on ONE of the positions. Failing to do so will result
    // in user withdraws temporarily being blocked.
    //====================================================================

    /**
     @notice Attempted withdraw would lower Cellar health factor too low.
     */
    error CompooundTokenAdaptor__HealthFactorTooLow();

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Compound cToken Adaptor V 0.0"));
    }

    /**
     * @notice
     */
    function isCETH(address target) internal view returns (bool) {
        return keccak256(abi.encodePacked(IERC20Metadata(target).symbol())) == keccak256(abi.encodePacked("cETH"));
    }

    /**
     * @notice The WETH contract on Ethereum Mainnet.
     */
    function WETH() internal pure returns (ERC20) {
        return ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Pool to spend its assets, then call deposit to lend its assets.
     * @param assets the amount of assets to lend on Aave
     * @param adaptorData adaptor data containining the abi encoded cToken
     * @dev configurationData is NOT used because this action will only increase the health factor
     */

    function underlying(bytes memory adaptorData) public view override returns (address) {
        address target = abi.decode(adaptorData, (address));
        return isCETH(target) ? WETH : CTokenInterface(target).underlying();
    }


    function deposit(
        uint256 assets,
        bytes memory adaptorData,
        bytes memory configurationData
    ) public override {

        IERC20Metadata cToken = IERC20Metadata(abi.decode(adaptorData, (address)));
        IERC20Metadata token = IERC20Metadata(underlying());

        token.safeTransferFrom(msg.sender, address(this), assets); // pulls the underlying

        // --- WETH into ETH
        bool _isCETH = isCETH(address(cToken));
        if (_isCETH) {
            IWETH(WETH).withdraw(assets);
        }

        // mint cToken
        uint256 before = cToken.balanceOf(abi.decode(adaptorData, (uint256)));
        if (_isCETH) {
            CEther(cToken).mint{ value: assets }();
        } else {
            require(CTokenInterface(cToken).mint(assets) == 0, "Error");
        }
        uint256 final = cToken.balanceOf(address(this)) - before ;
        cToken.safeTransfer(msg.sender, final);
        return final;
    }
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory configData
    ) public override {

        //Run the external receiver check
        _externalReceiverCheck(receiver);

        //Withdraw from Compound market
        IERC20Metadata cToken = IERC20Metadata(abi.decode(adaptorData, (address)));
        uint256 result = cToken.redeemUnderlying(assets);
        require (result == 0, "Error withdrawing the cTokens");
        cToken.safeTransfer(receiver, assets);

        uint256 minHealthFactor = abi.decode(configData, (uint256));
        if (minHealthFactor == 0) {
            revert BaseAdaptor__UserWithdrawsNotAllowed();
        }
        (, , , , , uint256 healthFactor) = ;
        if (healthFactor < minHealthFactor) revert CompooundTokenAdaptor__HealthFactorTooLow();

        //Transfer assets to receiver
        ERC20(token.UNDERLYING_ASSET_ADDRESS()).safeTransfer(receiver, assets);
    }

   /**
     * @notice Uses configurartion data minimum health factor to calculate withdrawable assets from Compound.
     * @dev Applies a `cushion` value to the health factor checks and calculation.
     *      The goal of this is to minimize scenarios where users are withdrawing a very small amount of
     *      assets from Compound. This function returns zero if
     *      -minimum health factor is NOT set.
     *      -the current health factor is less than the minimum health factor + 2x `cushion`
     *      Otherwise this function calculates the withdrawable amount using
     *      minimum health factor + `cushion` for its calcualtions.
     */
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
            ,
            uint256 currentLiquidationThreshold,
            ,
            uint256 healthFactor
        ) = pool().getUserAccountData(msg.sender);
        uint256 maxBorrowableWithMin;

        // Choose 0.01 for cushion value. Value can be adjusted based off testing results.
        uint256 cushion = 0.01e18;

        // Add cushion to min health factor.
        minHealthFactor += cushion;

        // If Cellar has no Aave debt, then return the cellars balance of the aToken.
        if (totalDebtETH == 0) return ERC20(address(token)).balanceOf(msg.sender);

        // If minHealthFactor is not set, or if current health factor is less than the minHealthFactor + 2X cushion, return 0.
        if (minHealthFactor == cushion || healthFactor < (minHealthFactor + cushion)) return 0;
        // Calculate max amount withdrawable while preserving minimum health factor.
        else {
            maxBorrowableWithMin =
                totalCollateralETH -
                (((minHealthFactor) * totalDebtETH) / (currentLiquidationThreshold * 1e14));
        }

        // If aToken underlying is WETH, then no Price Router conversion is needed.
        ERC20 underlying = ERC20(token.UNDERLYING_ASSET_ADDRESS());
        if (underlying == WETH()) return maxBorrowableWithMin;

        // Else convert `maxBorrowableWithMin` from WETH to position underlying asset.
        PriceRouter priceRouter = PriceRouter(Cellar(msg.sender).registry().getAddress(2));
        return priceRouter.getValue(WETH(), maxBorrowableWithMin, underlying);
    }
}
