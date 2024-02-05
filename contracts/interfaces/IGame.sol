// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.23;

interface IGame {
    struct UserStats {
        uint256 games;
        uint256 winner;
    }

    function userStats(address user) external view returns(UserStats memory);
}
