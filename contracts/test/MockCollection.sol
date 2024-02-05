// SPDX-License-Identifier: Apache 2
pragma solidity 0.8.23;

contract MockCollection {
    uint64 public totalSupply;

    constructor(uint64 _totalSupply) {
        totalSupply = _totalSupply;
    }

    function mint(string memory data) external returns(uint256){
        return totalSupply;
    }
}
