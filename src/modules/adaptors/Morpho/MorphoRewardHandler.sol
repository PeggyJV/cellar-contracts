// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface RewardsDistributor {
    function claim(address user, uint256 claimable, bytes32[] memory proof) external;
}

/**
 * @title Morpho Reward Handler
 * @notice Allows Cellars to claim MORPHO rewards.
 * @author crispymangoes
 */
contract MorphoRewardHandler {
    //============================================ Global Functions ===========================================

    /**
     * @notice The Morpho Rewards Distributor contract on Ethereum Mainnet.
     */
    function morphoRewardsDistributor() internal pure returns (RewardsDistributor) {
        return RewardsDistributor(0x3B14E5C73e0A56D607A8688098326fD4b4292135);
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows cellars to claim Morpho Rewards.
     */
    function claim(uint256 claimable, bytes32[] memory proof) public {
        morphoRewardsDistributor().claim(address(this), claimable, proof);
    }
}
