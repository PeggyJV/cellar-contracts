// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseAdaptor, ERC20, SafeTransferLib, Cellar, PriceRouter, Math } from "src/modules/adaptors/BaseAdaptor.sol";
import { IPoolV3 } from "src/interfaces/external/IPoolV3.sol";
import { IAaveToken } from "src/interfaces/external/IAaveToken.sol";
import { IAaveOracle } from "src/interfaces/external/IAaveOracle.sol";

/**
 * @title Aave aToken Adaptor
 * @notice Allows Cellars to interact with Aave aToken positions.
 * @author crispymangoes
 */
contract AaveV3ATokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address aToken)
    // Where:
    // `aToken` is the aToken address position this adaptor is working with
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
    // Cellars with multiple aToken positions MUST only specify minimum
    // health factor on ONE of the positions. Failing to do so will result
    // in user withdraws temporarily being blocked.
    //====================================================================

    /**
     @notice Attempted withdraw would lower Cellar health factor too low.
     */
    error AaveV3ATokenAdaptor__HealthFactorTooLow();

    /**
     * @notice Aave V3 oracle uses a different base asset than this contract was designed for.
     */
    error AaveV3ATokenAdaptor__OracleUsesDifferentBase();

    /**
     * @notice The Aave V3 Pool contract on current network.
     * @dev For mainnet use 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2.
     */
    IPoolV3 public immutable pool;

    /**
     * @notice The Aave V3 Oracle on current network.
     * @dev For mainnet use 0x54586bE62E3c3580375aE3723C145253060Ca0C2.
     */
    IAaveOracle public immutable aaveOracle;

    /**
     * @notice Minimum Health Factor enforced after every aToken withdraw.
     * @notice Overwrites strategist set minimums if they are lower.
     */
    uint256 public immutable minimumHealthFactor;

    constructor(address v3Pool, address v3Oracle, uint256 minHealthFactor) {
        _verifyConstructorMinimumHealthFactor(minHealthFactor);
        pool = IPoolV3(v3Pool);
        aaveOracle = IAaveOracle(v3Oracle);
        minimumHealthFactor = minHealthFactor;
    }

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Aave V3 aToken Adaptor V 1.2"));
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve Pool to spend its assets, then call deposit to lend its assets.
     * @param assets the amount of assets to lend on Aave
     * @param adaptorData adaptor data containining the abi encoded aToken
     * @dev configurationData is NOT used because this action will only increase the health factor
     */
    function deposit(uint256 assets, bytes memory adaptorData, bytes memory) public override {
        // Deposit assets to Aave.
        IAaveToken aToken = IAaveToken(abi.decode(adaptorData, (address)));
        ERC20 token = ERC20(aToken.UNDERLYING_ASSET_ADDRESS());
        token.safeApprove(address(pool), assets);
        pool.supply(address(token), assets, address(this), 0);

        // Zero out approvals if necessary.
        _revokeExternalApproval(token, address(pool));
    }

    /**
     @notice Cellars must withdraw from Aave, check if a minimum health factor is specified
     *       then transfer assets to receiver.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Aave
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containining the abi encoded aToken
     * @param configData abi encoded minimum health factor, if zero user withdraws are not allowed.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory configData
    ) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        // Withdraw assets from Aave.
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        pool.withdraw(token.UNDERLYING_ASSET_ADDRESS(), assets, address(this));

        (, uint256 totalDebtBase, , , , uint256 healthFactor) = pool.getUserAccountData(address(this));
        if (totalDebtBase > 0) {
            // If cellar has entered an EMode, and has debt, user withdraws are not allowed.
            if (pool.getUserEMode(msg.sender) != 0) revert BaseAdaptor__UserWithdrawsNotAllowed();

            // Run minimum health factor checks.
            uint256 minHealthFactor = abi.decode(configData, (uint256));
            if (minHealthFactor == 0) {
                revert BaseAdaptor__UserWithdrawsNotAllowed();
            }
            // Check if adaptor minimum health factor is more conservative than strategist set.
            if (minHealthFactor < minimumHealthFactor) minHealthFactor = minimumHealthFactor;
            if (healthFactor < minHealthFactor) revert AaveV3ATokenAdaptor__HealthFactorTooLow();
        }

        // Transfer assets to receiver.
        ERC20(token.UNDERLYING_ASSET_ADDRESS()).safeTransfer(receiver, assets);
    }

    /**
     * @notice Uses configurartion data minimum health factor to calculate withdrawable assets from Aave.
     * @dev Applies a `cushion` value to the health factor checks and calculation.
     *      The goal of this is to minimize scenarios where users are withdrawing a very small amount of
     *      assets from Aave. This function returns zero if
     *      -minimum health factor is NOT set.
     *      -the current health factor is less than the minimum health factor + 2x `cushion`
     *      Otherwise this function calculates the withdrawable amount using
     *      minimum health factor + `cushion` for its calcualtions.
     * @dev It is possible for the math below to lose a small amount of precision since it is only
     *      maintaining 18 decimals during the calculation, but this is desired since
     *      doing so lowers the withdrawable from amount which in turn raises the health factor.
     */
    function withdrawableFrom(
        bytes memory adaptorData,
        bytes memory configData
    ) public view override returns (uint256) {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            uint256 currentLiquidationThreshold,
            ,
            uint256 healthFactor
        ) = pool.getUserAccountData(msg.sender);

        // If Cellar has no Aave debt, then return the cellars balance of the aToken.
        if (totalDebtBase == 0) return ERC20(address(token)).balanceOf(msg.sender);

        // Cellar has Aave debt, so if cellar is entered into a non zero emode, return 0.
        if (pool.getUserEMode(msg.sender) != 0) return 0;

        // Otherwise we need to look at minimum health factor.
        uint256 minHealthFactor = abi.decode(configData, (uint256));
        // Check if minimum health factor is set.
        // If not the strategist does not want users to withdraw from this position.
        if (minHealthFactor == 0) return 0;
        // Check if adaptor minimum health factor is more conservative than strategist set.
        if (minHealthFactor < minimumHealthFactor) minHealthFactor = minimumHealthFactor;

        uint256 maxBorrowableWithMin;

        // Choose 0.01 for cushion value. Value can be adjusted based off testing results.
        uint256 cushion = 0.01e18;

        // Add cushion to min health factor.
        minHealthFactor += cushion;

        // If current health factor is less than the minHealthFactor + 2X cushion, return 0.
        if (healthFactor < (minHealthFactor + cushion)) return 0;
        // Calculate max amount withdrawable while preserving minimum health factor.
        else {
            maxBorrowableWithMin =
                totalCollateralBase -
                minHealthFactor.mulDivDown(totalDebtBase, (currentLiquidationThreshold * 1e14));
        }
        /// @dev We want right side of "-" to have 8 decimals, so we need to dviide by 18 decimals.
        // `currentLiquidationThreshold` has 4 decimals, so multiply by 1e14 to get 18 decimals on denominator.

        // Need to convert Base into position underlying.
        ERC20 underlying = ERC20(token.UNDERLYING_ASSET_ADDRESS());

        // Convert `maxBorrowableWithMin` from Base to position underlying asset.
        PriceRouter priceRouter = Cellar(msg.sender).priceRouter();
        uint256 underlyingToUSD = priceRouter.getPriceInUSD(underlying);
        uint256 withdrawable = maxBorrowableWithMin.mulDivDown(10 ** underlying.decimals(), underlyingToUSD);
        uint256 balance = ERC20(address(token)).balanceOf(msg.sender);
        // Check if withdrawable is greater than the position balance and if so return the balance instead of withdrawable.
        return withdrawable > balance ? balance : withdrawable;
    }

    /**
     * @notice Returns the cellars balance of the positions aToken.
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        address token = abi.decode(adaptorData, (address));
        return ERC20(token).balanceOf(msg.sender);
    }

    /**
     * @notice Returns the positions aToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        IAaveToken token = IAaveToken(abi.decode(adaptorData, (address)));
        return ERC20(token.UNDERLYING_ASSET_ADDRESS());
    }

    function assetsUsed(bytes memory adaptorData) public view override returns (ERC20[] memory assets) {
        assets = new ERC20[](1);
        assets[0] = assetOf(adaptorData);

        // Make sure Aave Oracle uses USD base asset with 8 decimals.
        // BASE_CURRENCY and BASE_CURRENCY_UNIT are both immutable values, so only check this on initial position setup.
        if (aaveOracle.BASE_CURRENCY() != address(0) || aaveOracle.BASE_CURRENCY_UNIT() != 1e8)
            revert AaveV3ATokenAdaptor__OracleUsesDifferentBase();
    }

    /**
     * @notice This adaptor returns collateral, and not debt.
     */
    function isDebt() public pure override returns (bool) {
        return false;
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategists to lend assets on Aave.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param tokenToDeposit the token to lend on Aave
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Aave.
     */
    function depositToAave(ERC20 tokenToDeposit, uint256 amountToDeposit) public {
        amountToDeposit = _maxAvailable(tokenToDeposit, amountToDeposit);
        tokenToDeposit.safeApprove(address(pool), amountToDeposit);
        pool.supply(address(tokenToDeposit), amountToDeposit, address(this), 0);

        // Zero out approvals if necessary.
        _revokeExternalApproval(tokenToDeposit, address(pool));
    }

    /**
     * @notice Allows strategists to withdraw assets from Aave.
     * @param tokenToWithdraw the token to withdraw from Aave.
     * @param amountToWithdraw the amount of `tokenToWithdraw` to withdraw from Aave
     */
    function withdrawFromAave(ERC20 tokenToWithdraw, uint256 amountToWithdraw) public {
        pool.withdraw(address(tokenToWithdraw), amountToWithdraw, address(this));
        // Check that health factor is above adaptor minimum.
        (, , , , , uint256 healthFactor) = pool.getUserAccountData(address(this));
        if (healthFactor < minimumHealthFactor) revert AaveV3ATokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategists to adjust an asset's isolation mode.
     */
    function adjustIsolationModeAssetAsCollateral(ERC20 asset, bool useAsCollateral) public {
        pool.setUserUseReserveAsCollateral(address(asset), useAsCollateral);
        // Check that health factor is above adaptor minimum.
        (, , , , , uint256 healthFactor) = pool.getUserAccountData(address(this));
        if (healthFactor < minimumHealthFactor) revert AaveV3ATokenAdaptor__HealthFactorTooLow();
    }

    /**
     * @notice Allows strategists to enter different EModes.
     */
    function changeEMode(uint8 categoryId) public {
        pool.setUserEMode(categoryId);
        // Check that health factor is above adaptor minimum.
        (, , , , , uint256 healthFactor) = pool.getUserAccountData(address(this));
        if (healthFactor < minimumHealthFactor) revert AaveV3ATokenAdaptor__HealthFactorTooLow();
    }
}
