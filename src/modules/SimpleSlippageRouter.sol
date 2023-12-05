// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Math } from "src/utils/Math.sol";
import { ERC4626 } from "@solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Owned } from "@solmate/auth/Owned.sol";

/**
 * @title Sommelier Simple Slippage Router
 * @notice A Simple Utility Contract to allow Cellars to assist Users w/ better UX for slippage w/ minting / redemption
 * @author crispymangoes, 0xEinCodes
 */
contract SimpleSlippageRouter {
    // errors

    /**
     * @notice Attempted to carry out tx with expired deadline.
     */
    error SimpleSlippageAdaptor__ExpiredDeadline(uint64 deadline);

    /**
     * @notice Attempted to carry out tx with less than acceptable minimum shares.
     * @param minimumShares specified acceptable minimum shares amount
     * @param actualSharesQuoted actual amount of shares to come from proposed tx
     */
    error SimpleSlippageAdaptor__MinimumSharesUnmet(uint256 minimumShares, uint256 actualSharesQuoted);

    /**
     * @notice Attempted to carry out tx with less than acceptable max shares.
     * @param maxShares specified acceptable max shares amount
     * @param actualSharesQuoted actual amount of shares to come from proposed tx
     */
    error SimpleSlippageAdaptor__MaxSharesSurpassed(uint256 maxShares, uint256 actualSharesQuoted);

    /**
     * @notice deposits assets into specified cellar w/ minimumShares expected and deadline specified
     * @param _cellar specified cellar to deposit assets into
     * @param _assets amount of cellar base assets to deposit
     * @param _minimumShares amount of shares required at min from tx
     * @param _deadline block.timestamp that tx must be carried out by
     */
    function deposit(Cellar _cellar, uint256 _assets, uint256 _minimumShares, uint64 _deadline) public {
        if (block.timestamp > _deadline) revert SimpleSlippageAdaptor__ExpiredDeadline(_deadline);
        _cellar.asset().safeTransferFrom(msg.sender, address(this), _assets);
        uint256 shares = _cellar.deposit(_assets, msg.sender);
        if (shares < _minimumShares) revert SimpleSlippageAdaptor__MinimumSharesUnmet(_minimumShares, shares);
    }

    /**
     * @notice withdraws assets as long as tx returns more than minimumAssets and is done before deadline.
     * @param _cellar specified cellar to deposit assets into
     * @param _assets amount of cellar base assets to deposit
     * @param _maxShares max amount of shares to redeemed from tx
     * @param _deadline block.timestamp that tx must be carried out by
     */
    function withdraw(Cellar _cellar, uint256 _assets, uint256 _maxShares, uint64 _deadline) public {
        if (block.timestamp > _deadline) revert SimpleSlippageAdaptor__ExpiredDeadline(_deadline);

        uint256 shares = cellar.previewWithdraw(_assets);
        if (shares > _maxShares) revert SimpleSlippageAdaptor__MaxSharesSurpassed(_maxShares, shares);

        ERC20 cellarToken = ERC20(address(_cellar));

        cellarToken.safeTransferFrom(msg.sender, address(this), shares);
        uint256 shares = _cellar.withdraw(_assets, msg.sender, address(this));
    }

    function mint() public {}

    function redeem() public {}
}
