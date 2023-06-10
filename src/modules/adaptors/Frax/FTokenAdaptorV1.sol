// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { FTokenAdaptor, IFToken } from "src/modules/adaptors/Frax/FTokenAdaptor.sol";
import { IRateCalculator } from "src/interfaces/external/Frax/IRateCalculator.sol";

/**
 * @title FraxLend fToken Adaptor
 * @notice Allows Cellars to lend FRAX to FraxLend pairs.
 * @author crispymangoes, 0xEinCodes
 */
contract FTokenAdaptorV1 is FTokenAdaptor {
    //============================================ Notice ===========================================
    // Since there is no way to calculate pending interest for this positions balanceOf,
    // The positions balance is only updated when accounts interact with the
    // Frax Lend pair this position is working with.
    // This can lead to a divergence from the Cellars share price, and its real value.
    // This can be mitigated by calling `callAddInterest` on Frax Lend pairs
    // that are not frequently interacted with.

    //============================================ Interface Helper Functions ===========================================

    //============================== Interface Details ==============================
    // The Frax Pair interface can slightly change between versions.
    // To account for this, FTokenAdaptors will use the below internal functions when
    // interacting with Frax Pairs, this way new pairs can be added by creating a
    // new contract that inherits from this one, and overrides any function it needs
    // so it conforms with the new Frax Pair interface. This adaptor exemplifies how
    // the v1 version of `FraxLendPair` needs to be accomodated due to the slight
    // difference compared to the v2 `FraxLendPair` version.

    // Current versions in use for `FraxLendPair` include v1 and v2.

    // IMPORTANT: This `FTokenAdaptorV1.sol` is associated to the v1 version of `FraxLendPair`
    // whereas the inherited `FTokenAdaptor.sol` is actually associated to `FraxLendPairv2`.
    // The reasoning to name it like this was to set up the base FTokenAdaptor for the
    // most current version, v2. This is in anticipation that more FraxLendPairs will
    // be deployed following v2 in the near future. When later versions are deployed,
    // then the described inheritance pattern above will be used.
    //===============================================================================

    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure virtual override returns (bytes32) {
        return keccak256(abi.encode("FraxLend fTokenV1 Adaptor V 0.0"));
    }

    /**
     * @notice Withdraw $FRAX from specified 'v1' FraxLendPair.
     * @dev Since `withdrawableFrom` does NOT account for pending interest,
     *      user withdraws from V1 positions can result in dust being left in the position.
     * @dev If `ACCOUNT_FOR_INTEREST()` is false, then _toAssetShares will use a FraxLend share price that
     *      is slightly lower than what is used in redeem, so users can receive more assets than expected.
     *      The extra assets are influenced by the FraxLend APR, and the time since the interest was last
     *      added to the pair, so in practice this extra amount should be negligible.
     * @param fToken The specified FraxLendPair
     * @param assets The amount to withdraw
     * @param receiver The address to which the Asset Tokens will be transferred
     * @param owner The owner of the Asset Shares (fTokens)
     */
    function _withdraw(IFToken fToken, uint256 assets, address receiver, address owner) internal override {
        // Call `addInterest` before calculating shares to redeem, so we use the most up to date share price.
        fToken.addInterest();
        // NOTE below `_toAssetShares` calculation intentionally has `ACCOUNT_FOR_INTEREST` hard coded to false.
        // Since we call `addInterest` right before this, there is no point in previewing interest, because
        // it was updated this block.
        uint256 shares = _toAssetShares(fToken, assets, false, false);
        fToken.redeem(shares, receiver, owner);
    }

    /**
     * @notice Converts a given number of shares to $FRAX amount from specified 'v1' FraxLendPair
     * @dev versions of FraxLendPair do not have a fourth param whereas v2 does
     * @param fToken The specified FraxLendPair
     * @param shares Shares of asset (fToken)
     * @param roundUp Whether to round up after division
     */
    function _toAssetAmount(
        IFToken fToken,
        uint256 shares,
        bool roundUp,
        bool previewInterest
    ) internal view override returns (uint256) {
        if (previewInterest) {
            (
                uint128 totalAssetAmount,
                uint128 totalAssetShares,
                uint128 totalBorrowAmount,
                uint128 totalBorrowShares,

            ) = fToken.getPairAccounting();
            (totalAssetAmount, totalAssetShares) = _previewInterest(
                fToken,
                totalAssetAmount,
                totalAssetShares,
                totalBorrowAmount,
                totalBorrowShares
            );
            uint256 assets;
            if (totalAssetShares == 0) {
                assets = shares;
            } else {
                assets = (shares * totalAssetAmount) / totalAssetShares;
                if (roundUp && (assets * totalAssetShares) / totalAssetAmount < shares) {
                    assets = assets + 1;
                }
            }
            return assets;
        } else return fToken.toAssetAmount(shares, roundUp);
    }

    /**
     * @notice Converts a given asset amount to a number of asset shares (fTokens) from specified 'v1' FraxLendPair
     * @dev versions of FraxLendPair do not have a fourth param whereas v2 does
     * @param fToken The specified FraxLendPair
     * @param amount The amount of asset
     * @param roundUp Whether to round up after division
     */
    function _toAssetShares(
        IFToken fToken,
        uint256 amount,
        bool roundUp,
        bool previewInterest
    ) internal view override returns (uint256) {
        if (previewInterest) {
            (
                uint128 totalAssetAmount,
                uint128 totalAssetShares,
                uint128 totalBorrowAmount,
                uint128 totalBorrowShares,

            ) = fToken.getPairAccounting();
            (totalAssetAmount, totalAssetShares) = _previewInterest(
                fToken,
                totalAssetAmount,
                totalAssetShares,
                totalBorrowAmount,
                totalBorrowShares
            );
            uint256 shares;
            if (totalAssetAmount == 0) {
                shares = amount;
            } else {
                shares = (amount * totalAssetShares) / totalAssetAmount;
                if (roundUp && (shares * totalAssetAmount) / totalAssetShares < amount) {
                    shares = shares + 1;
                }
            }
            return shares;
        } else return fToken.toAssetShares(amount, roundUp);
    }

    /**
     * @notice Caller calls `addInterest` on specified 'v1' FraxLendPair
     * @dev ftoken.addInterest() calls into the v1 FraxLendPair
     * @param fToken The specified FraxLendPair
     */
    function _addInterest(IFToken fToken) internal override {
        fToken.addInterest();
    }

    // This function is essentially the Frax Lend V1 `_addInterest` function, but
    // adjusted to be a view.
    function _previewInterest(
        IFToken fToken,
        uint128 totalAssetAmount,
        uint128 totalAssetShares,
        uint128 totalBorrowAmount,
        uint128 totalBorrowShares
    ) internal view returns (uint128, uint128) {
        IFToken.CurrentRateInfoV1 memory rateInfo = fToken.currentRateInfo();
        // Interest was already updated this block.
        if (rateInfo.lastTimestamp == block.timestamp) {
            return (totalAssetAmount, totalAssetShares);
        }

        // If there are no borrows or contract is paused, no interest accrues so return current values.
        if (totalBorrowShares == 0 || fToken.paused()) {
            return (totalAssetAmount, totalAssetShares);
        }

        uint256 deltaTime = block.timestamp - rateInfo.lastTimestamp;
        // 1e5 is the FraxLend V1 Contracts `UTIL_PREC` value.
        uint256 _utilizationRate = (1e5 * totalBorrowAmount) / totalAssetAmount;

        uint64 newRate;
        uint256 maturityDate = fToken.maturityDate();
        if (maturityDate != 0 && block.timestamp > maturityDate) {
            newRate = uint64(fToken.penaltyRate());
        } else {
            bytes memory rateData = abi.encode(
                rateInfo.ratePerSec,
                deltaTime,
                _utilizationRate,
                block.number - rateInfo.lastBlock
            );

            newRate = IRateCalculator(fToken.rateContract()).getNewRate(rateData, fToken.rateInitCallData());
        }

        uint256 interestEarned = (deltaTime * totalBorrowAmount * newRate) / 1e18;

        if (
            interestEarned + totalBorrowAmount <= type(uint128).max &&
            interestEarned + totalAssetAmount <= type(uint128).max
        ) {
            totalBorrowAmount += uint128(interestEarned);
            totalAssetAmount += uint128(interestEarned);

            // Check if protocol fee is setup.
            if (rateInfo.feeToProtocolRate > 0) {
                // 1e5 is the FraxLend V1 contracts `FEE_PRECISION`.
                uint256 feesAmount = (interestEarned * rateInfo.feeToProtocolRate) / 1e5;

                uint256 feesShare = (feesAmount * totalAssetShares) / (totalAssetAmount - feesAmount);

                totalAssetShares += uint128(feesShare);
            }
        }

        return (totalAssetAmount, totalAssetShares);
    }
}
