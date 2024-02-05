// SPDX-License-Identifier: Apache 2
pragma solidity 0.8.23;

contract MockGame {
    mapping(address => UserStats) public stats;

    struct UserStats {
        uint256 games;
        uint256 winner;
    }

    function userStats(address user) external view returns(UserStats memory){
        return stats[user];
    }

    function setMockStats(address user, UserStats memory data) external {
        stats[user] = data;
    }
}