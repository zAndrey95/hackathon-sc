// SPDX-License-Identifier: Apache 2
pragma solidity 0.8.23;

interface IEntropy {
    function request(
        address provider,
        bytes32 userCommitment,
        bool useBlockHash
    ) external payable returns (uint64 assignedSequenceNumber);

    function reveal(
        address provider,
        uint64 sequenceNumber,
        bytes32 userRandomness,
        bytes32 providerRevelation
    ) external returns (bytes32 randomNumber);

    function getFee(address provider) external view returns (uint128 feeAmount);
}

contract MockEntropy is IEntropy {
    uint256 public sequenceNumberCounter = 0;
    uint128 public feeInWei = 0.01 ether;

    constructor() {}

    function request(
        address provider,
        bytes32 userCommitment,
        bool useBlockHash
    ) external payable override returns (uint64 assignedSequenceNumber) {
        sequenceNumberCounter += 1;
        return uint64(sequenceNumberCounter);
    }

    function reveal(
        address provider,
        uint64 sequenceNumber,
        bytes32 userRandomness,
        bytes32 providerRevelation
    ) external override returns (bytes32 randomNumber) {
        return
            keccak256(
                abi.encodePacked(
                    userRandomness,
                    providerRevelation,
                    sequenceNumber
                )
            );
    }

    function getFee(
        address provider
    ) external view override returns (uint128 feeAmount) {
        return feeInWei;
    }
}
