// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

/**
 * @title Sommelier Simple Slippage Router
 * @notice A Simple Utility Contract to allow Users to call functions: deposit, withdraw, mint, and redeem with ERC4626 Vault contracts w/ respective specified slippage params.
 * @author crispymangoes, 0xEinCodes
 */
contract SimpleSlippageRouter {
    using SafeTransferLib for ERC20;

    /**
     * @notice attempted to carry out tx with expired deadline.
     * @param deadline specified tx block.timestamp to not pass during tx.
     */
    error SimpleSlippageRouter__ExpiredDeadline(uint256 deadline);

    /**
     * @notice attempted to carry out deposit() tx with less than acceptable minimum shares.
     * @param minimumShares specified acceptable minimum shares amount.
     * @param actualSharesQuoted actual amount of shares to come from proposed tx.
     */
    error SimpleSlippageRouter__DepositMinimumSharesUnmet(uint256 minimumShares, uint256 actualSharesQuoted);

    /**
     * @notice attempted to carry out withdraw() tx where required shares to redeem > maxShares specified by user.
     * @param maxShares specified acceptable max shares amount.
     * @param actualSharesQuoted actual amount of shares to come from proposed tx.
     */
    error SimpleSlippageRouter__WithdrawMaxSharesSurpassed(uint256 maxShares, uint256 actualSharesQuoted);

    /**
     * @notice attempted to carry out mint() tx where resultant required assets for requested shares is too much.
     * @param minShares specified acceptable min shares amount.
     * @param maxAssets specified max assets to spend on mint.
     * @param actualAssetsQuoted actual amount of assets to come from proposed tx, indicating asset amount not enough for specified shares.
     */
    error SimpleSlippageRouter__MintMaxAssetsRqdSurpassed(
        uint256 minShares,
        uint256 maxAssets,
        uint256 actualAssetsQuoted
    );

    /**
     * @notice attempted to carry out redeem() tx where assets returned (the result of redeeming maxShares) < minimumAssets.
     * @param maxShares specified acceptable max shares amount.
     * @param minimumAssets specified minimum amount of assets to be returned.
     * @param actualAssetsQuoted actual amount of assets to come from proposed tx.
     */
    error SimpleSlippageRouter__RedeemMinAssetsUnmet(
        uint256 maxShares,
        uint256 minimumAssets,
        uint256 actualAssetsQuoted
    );

    /**
     * @notice deposits assets into specified ERC4626 Vaults w/ _minimumShares expected and _deadline specified.
     * @dev This function is more gas efficient than the `mint` function, as it does not rely on a preview function.
     * @param _vault specified ERC4626 Vaults to deposit assets into.
     * @param _assets amount of ERC4626 Vaults base assets to deposit.
     * @param _minimumShares amount of shares required at min from tx.
     * @param _deadline block.timestamp that tx must be carried out by.
     */
    function deposit(ERC4626 _vault, uint256 _assets, uint256 _minimumShares, uint256 _deadline) public {
        if (block.timestamp > _deadline) revert SimpleSlippageRouter__ExpiredDeadline(_deadline);
        ERC20 baseAsset = _vault.asset();
        baseAsset.safeTransferFrom(msg.sender, address(this), _assets);
        baseAsset.approve(address(_vault), _assets);
        uint256 shareDelta = _vault.balanceOf(msg.sender);
        _vault.deposit(_assets, msg.sender);
        shareDelta = _vault.balanceOf(msg.sender) - shareDelta;
        if (shareDelta < _minimumShares)
            revert SimpleSlippageRouter__DepositMinimumSharesUnmet(_minimumShares, shareDelta);
        _revokeExternalApproval(baseAsset, address(_vault));
    }

    /**
     * @notice withdraws assets as long as tx returns more than _assets and is done before _deadline.
     * @dev This function is more gas efficient than the `redeem` function, as it does not rely on a preview function.
     * @param _vault specified ERC4626 Vaults to withdraw assets from.
     * @param _assets amount of ERC4626 Vaults base assets to withdraw.
     * @param _maxShares max amount of shares to redeem from tx.
     * @param _deadline block.timestamp that tx must be carried out by.
     */
    function withdraw(ERC4626 _vault, uint256 _assets, uint256 _maxShares, uint256 _deadline) public {
        if (block.timestamp > _deadline) revert SimpleSlippageRouter__ExpiredDeadline(_deadline);
        uint256 shareDelta = _vault.balanceOf(msg.sender);
        _vault.withdraw(_assets, msg.sender, msg.sender); // NOTE: user needs to approve this contract to spend shares
        shareDelta = shareDelta - _vault.balanceOf(msg.sender);
        if (shareDelta > _maxShares) revert SimpleSlippageRouter__WithdrawMaxSharesSurpassed(_maxShares, shareDelta);
    }

    /**
     * @notice mints shares from the ERC4626 Vaults and returns shares to receiver IF shares quoted cost are less than specified _assets amount by the specified _deadline.
     * @param _vault specified ERC4626 Vaults to deposit assets into.
     * @param _shares amount of shares required at min from tx.
     * @param _maxAssets max amount of ERC4626 Vaults base assets to deposit.
     * @param _deadline block.timestamp that tx must be carried out by.
     */
    function mint(ERC4626 _vault, uint256 _shares, uint256 _maxAssets, uint256 _deadline) public {
        if (block.timestamp > _deadline) revert SimpleSlippageRouter__ExpiredDeadline(_deadline);
        uint256 quotedAssetAmount = _vault.previewMint(_shares);
        if (quotedAssetAmount > _maxAssets)
            revert SimpleSlippageRouter__MintMaxAssetsRqdSurpassed(_shares, _maxAssets, quotedAssetAmount);
        ERC20 baseAsset = _vault.asset();
        baseAsset.safeTransferFrom(msg.sender, address(this), quotedAssetAmount);
        baseAsset.approve(address(_vault), quotedAssetAmount);
        _vault.mint(_shares, msg.sender);
        _revokeExternalApproval(baseAsset, address(_vault));
    }

    /**
     * @notice redeem shares to withdraw assets from the ERC4626 Vaults IF withdrawn quotedAssetAmount > _minAssets & tx carried out before _deadline.
     * @param _vault specified ERC4626 Vaults to redeem shares for assets from.
     * @param _shares max amount of shares to redeem from tx.
     * @param _minAssets amount of ERC4626 Vaults base assets to receive upon share redemption.
     * @param _deadline block.timestamp that tx must be carried out by.
     */
    function redeem(ERC4626 _vault, uint256 _shares, uint256 _minAssets, uint256 _deadline) public {
        if (block.timestamp > _deadline) revert SimpleSlippageRouter__ExpiredDeadline(_deadline);
        uint256 quotedAssetAmount = _vault.previewRedeem(_shares);
        if (quotedAssetAmount < _minAssets)
            revert SimpleSlippageRouter__RedeemMinAssetsUnmet(_shares, _minAssets, quotedAssetAmount);
        _vault.redeem(_shares, msg.sender, msg.sender); // NOTE: user needs to approve this contract to spend shares
    }

    /// Helper Functions

    /**
     * @notice Helper function that checks if `spender` has any more approval for `asset`, and if so revokes it.
     */
    function _revokeExternalApproval(ERC20 asset, address spender) internal {
        if (asset.allowance(address(this), spender) > 0) asset.safeApprove(spender, 0);
    }
}
