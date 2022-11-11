// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

contract MockGasFeed {
    int192 answer;

    function latestAnswer() public returns (int192) {
        return answer;
    }

    function setAnswer(int192 ans) public {
        answer = ans;
    }
}
