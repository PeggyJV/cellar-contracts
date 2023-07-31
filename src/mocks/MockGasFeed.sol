// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

contract MockGasFeed {
    int192 answer;

    function latestAnswer() public view returns (int192) {
        return answer;
    }

    function setAnswer(int192 ans) public {
        answer = ans;
    }
}
