// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface RewardsDistributor {
    function claim(address user, uint256 claimable, bytes32[] memory proof) external;
}

/**
 * @title Morpho Reward Handler
 * @notice Allows Cellars to claim MORPHO rewards.
 * @author crispymangoes
 */
contract MorphoRewardHandler {
    /**
     * @notice The Morpho Aave V3 rewards handler contract on current network.
     * @notice For mainnet use 0x3B14E5C73e0A56D607A8688098326fD4b4292135.
     */
    RewardsDistributor public immutable morphoRewardsDistributor;

    constructor(address _morphoRewardsDistributor) {
        morphoRewardsDistributor = RewardsDistributor(_morphoRewardsDistributor);
    }

    //============================================ Strategist Functions ===========================================

    /**
     * @notice Allows cellars to claim Morpho Rewards.
     */
    function claim(uint256 claimable, bytes32[] memory proof) public {
        morphoRewardsDistributor.claim(address(this), claimable, proof);
    }
}
