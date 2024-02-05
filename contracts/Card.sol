// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGameCollection} from "./interfaces/IGameCollection.sol";

contract CAHCard is Ownable, IGameCollection {
    // Collection name
    string public name;

    // Collection type
    string public symbol;

    uint256 private _totalSupply;
    mapping(uint256 => string) private _allTokens;
    mapping(address => bool) private minters;

    event SetMinter(address minter, bool isAllowed);
    event CardUpdated(uint256 tokenId);

    ///@notice - return when one of parameters is zero address
    error ZeroAddress();
    ///@notice - only minter
    error OnlyMinter();
    ///@notice - card not exists
    error CardNotExists();
    ///@notice - array lengths do not match
    error WrongArrayLength();
    ///@notice - minter already added or removed
    error AlreadySet();

    constructor(
        string memory name_,
        string memory symbol_,
        address _owner,
        address[] memory _minters
    ) Ownable(_owner) {
        name = name_;
        symbol = symbol_;

        uint256 length = _minters.length;
        for (uint256 i; i < length; ) {
            if (_minters[i] == address(0)) {
                revert ZeroAddress();
            }

            minters[_minters[i]] = true;

            unchecked {
                ++i;
            }
        }
        minters[_owner] = true;
    }

    modifier onlyMinter() {
        if (!minters[msg.sender]) {
            revert OnlyMinter();
        }
        _;
    }

    /// @notice - mint a new card
    /// @param data - card text
    function mint(string memory data) external onlyMinter returns (uint256) {
        uint256 newTokenIndex = _totalSupply++;
        _allTokens[newTokenIndex] = data;

        emit CardUpdated(newTokenIndex);

        return newTokenIndex;
    }

    /// @notice - update existing card value
    /// @param tokenId - card id (index)
    /// @param data - card text
    function update(uint256 tokenId, string memory data) external onlyMinter {
        _update(tokenId, data);
    }

    /// @notice - admin mint bulk new cards
    /// @param data - card text
    function bulkMint(string[] memory data) external onlyOwner {
        uint256 newTokenIndex = _totalSupply;
        uint256 length = data.length;
        for (uint256 i; i < length; ) {
            _allTokens[newTokenIndex++] = data[i];
            _totalSupply++;
            unchecked {
                ++i;
            }

            emit CardUpdated(newTokenIndex);
        }
    }

    /// @notice - bulk update existing card values
    /// @param tokenIds - card ids (index)
    /// @param data - card texts
    function bulkUpdate(
        uint256[] memory tokenIds,
        string[] memory data
    ) external onlyOwner {
        uint256 length = data.length;

        if (tokenIds.length != length) {
            revert WrongArrayLength();
        }

        for (uint256 i; i < length; ) {
            _update(tokenIds[i], data[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _update(uint256 _tokenId, string memory _data) internal {
        if (_tokenId >= _totalSupply) {
            revert CardNotExists();
        }

        _allTokens[_tokenId] = _data;

        emit CardUpdated(_tokenId);
    }

    /// @notice - get total cards amount
    function totalSupply() external view virtual returns (uint256) {
        return _totalSupply;
    }

    /// @notice - get card value
    /// @param - card id (index)
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return _allTokens[tokenId];
    }

    /// @notice - removing minter
    /// @param minter - minter address
    function removeMinter(address minter) external onlyOwner {
        if (!minters[minter]) {
            revert AlreadySet();
        }
        minters[minter] = false;
        emit SetMinter(minter, false);
    }

    /// @notice - adding a new minter
    /// @param minter - minter address
    function addMinter(address minter) external onlyOwner {
        if (minter == address(0)) {
            revert ZeroAddress();
        }
        if (minters[minter]) {
            revert AlreadySet();
        }
        minters[minter] = true;
        emit SetMinter(minter, true);
    }
}
