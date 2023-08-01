// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

contract MockRedstoneClassicAdapter {
    mapping(bytes32 => uint256) public answer;
    uint128 public lastUpdatedAt;

    function getTimestampsFromLatestUpdate() external view returns (uint128, uint128) {
        return (lastUpdatedAt, lastUpdatedAt);
    }

    function getValueForDataFeed(bytes32 dataFeedId) external view returns (uint256 price) {
        return answer[dataFeedId];
    }

    function setTimestampsFromLatestUpdate(uint128 _updatedAt) external {
        lastUpdatedAt = _updatedAt;
    }

    function setValueForDataFeed(bytes32 dataFeedId, uint256 price) external {
        answer[dataFeedId] = price;
    }
}
