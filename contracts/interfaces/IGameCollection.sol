// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.23;

interface IGameCollection {
    function totalSupply() external view returns (uint256);
    function mint(string memory data) external returns(uint256);
}

