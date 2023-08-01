// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Owned } from "@solmate/auth/Owned.sol";

/**
 * @title Custom Fast Gas Feed
 * @notice Serves as the bare minimum implementation of a gas feed needed by
 *         the FeesAndReserves contract.
 * @author crispymangoes
 */
contract CustomFastGasFeed is Owned {
    /**
     * @notice The answer that is reported when `latestAnswer` is called.
     */
    int256 public answer;

    /**
     * @notice For networks where gas is cheap, this contract can be deployed
     *         with `_owner` set to address(0).
     *         Doing this "locks" the fast gas price at 0 wei, so no
     *         FeesAndReserves actions are inhibited from gas price.
     */
    constructor(address _owner) Owned(_owner) {}

    /**
     * @notice Allows owner to update this answer.
     * @dev Owner could be a multisig, bot, or EOA.
     * @dev If owner acts maliciously by setting incorrect gas prices, FeesAndReserves can update
     *      its FastGasFeed with something else.
     */
    function setAnswer(int256 _answer) external onlyOwner {
        answer = _answer;
    }

    /**
     * @notice Reports the latest owner-set answer.
     */
    function latestAnswer() external view returns (int256) {
        return answer;
    }
}
