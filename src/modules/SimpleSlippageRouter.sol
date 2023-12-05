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
     * @notice deposits assets into specified cellar w/ minimumShares expected and deadline specified
     * @param cellar specified cellar to deposit assets into
     * @param assets amount of cellar base assets to deposit
     * @param minimumShares amount of shares required at miniimum from tx
     * @param deadline block.timestamp that tx must be carried out by
     */
    function deposit(Cellar _cellar, uint256 _assets, uint256 _minimumShares, uint64 _deadline) public {
        if (block.timestamp > _deadline) revert SimpleSlippageAdaptor__ExpiredDeadline(_deadline);
        _cellar.asset().safeTransferFrom(msg.sender, address(this), _assets);
        uint256 shares = cellar.deposit(_assets, msg.sender);
        if (shares < _minimumShares) revert SimpleSlippageAdaptor__MinimumSharesUnmet(_minimumShares, shares);
    }

    /**
     * @notice withdraws assets in return for shares to be redeemed.
     * @dev
     */
    function withdraw() public {}

    function mint() public {}

    function redeem() public {}
}
