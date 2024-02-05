// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.23;

import {GovernorStorage} from "@openzeppelin/contracts/governance/extensions/GovernorStorage.sol";
import {IGame} from "./interfaces/IGame.sol";
import {IGameCollection} from "./interfaces/IGameCollection.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IGovernor, IERC6372} from "@openzeppelin/contracts/governance/IGovernor.sol";

/// @title CardsGovernor
/// @notice This contract is responsible for the governance of the Cards game.
contract CardsGovernor is Ownable, EIP712, ERC165 {
    /// @notice treshold of wins required to propose a new card
    uint16 public constant WIN_PROPOSAL_TRESHOLD = 5;
    /// @notice maximum amount of options for a proposal
    uint8 public constant MAX_OPTIONS_SIZE = 5;
    /// @notice delay in seconds before a proposal can be voted
    uint256 public constant VOTING_DELAY = 0;
    /// @notice duration in seconds for a proposal to be voted
    uint256 public constant VOTING_PERIOD = 1;
    /// @notice treshold of votes required to pass a proposal
    uint256 public constant QUORUM_REACHED_TRESHOLD = 25;
    /// @notice treshold of votes required to pass a proposal
    uint256 public constant SUCCESS_PROPOSAL_TRESHOLD = 15;

    /// @notice bitmap of all proposal states
    bytes32 private constant ALL_PROPOSAL_STATES_BITMAP =
        bytes32((2 ** (uint8(type(ProposalState).max) + 1)) - 1);
    /// @notice typehash for the option struct
    bytes32 public constant OPTION_TYPEHASH =
        keccak256("CardOption(string option)");
    /// @notice domain separator for EIP712
    string private constant _SIGNING_DOMAIN = "CardsGovernor";

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    struct ProposalCore {
        address proposer;
        uint48 voteStart;
        uint32 voteDuration;
        bool executed;
        bool canceled;
        // uint48 etaSeconds;
    }

    struct ProposalData {
        uint256 totalVotes;
        uint256[] votes;
    }
    /// @notice Core data for a proposal
    IGame public game;
    /// @notice Mapping of collections allowed to propose
    mapping(address => bool) private collections;
    /// @notice Mapping of votes used by an address
    mapping(address => uint256) private usedVotes;
    /// @notice Mapping of signers allowed to propose
    mapping(address => bool) private signers;
    /// @notice Mapping of proposals
    mapping(uint256 proposalId => ProposalCore) private _proposals;
    /// @notice Mapping of proposals data
    mapping(uint256 proposalId => ProposalData) public _proposalsData;

    struct ProposalVote {
        uint8 size;
        mapping(address voter => bool) hasVoted;
    }

    /// @notice event emitted when a new proposal is created
    /// @param proposalId id of the proposal
    /// @param proposer address of the proposer
    /// @param collection address of the collection
    /// @param options array of options
    /// @param voteStart timestamp of the start of the vote
    /// @param voteEnd timestamp of the end of the vote
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address collection,
        string[] options,
        uint256 voteStart,
        uint256 voteEnd
    );
    /// @notice event emitted when a proposal is executed
    /// @param proposalId id of the proposal
    /// @param newCardId id of the new card
    event ProposalExecuted(uint256 proposalId, uint256 newCardId);
    /// @notice event emitted when a vote is cast
    /// @param voter address of the voter
    /// @param proposalId id of the proposal
    /// @param support option voted
    /// @param weight amount of votes used
    /// @param reason reason for the vote
    event VoteCast(
        address indexed voter,
        uint256 proposalId,
        uint8 support,
        uint256 weight,
        string reason
    );
    /// @notice event emitted when a proposal is canceled
    /// @param proposalId id of the proposal
    event ProposalCanceled(uint256 proposalId);

    /// @notice error returns when the proposal has not enough wins
    error NotEnoughWinsForProposal();
    /// @notice error returns when passed zero address
    error ZeroAddress();
    /// @notice error returns when the collection is not allowed
    error NotAllowedCollection();
    /// @notice error returns when the proposal has too many options
    error TooManyOptions();
    /// @notice error returns when the option is not allowed
    error NotAllowedOption(string option);
    /// @notice error returns when the array length does not match
    error ArrayLengthMissMatch();
    /// @notice error returns when the proposal has not enough votes
    error NotEnoughVotes();
    /// @notice error returns when the support is invalid
    error InvalidSupport();
    /// @notice error returns when the proposer has not enough votes
    error GovernorInsufficientProposerVotes(
        address proposer,
        uint256 proposerVotes
    );
    /// @notice error returns when the proposal state is unexpected
    error GovernorUnexpectedProposalState(
        uint256 proposalId,
        ProposalState current,
        bytes32 expectedStates
    );
    /// @notice error returns when the account is not allowed to propose
    error GovernorOnlyProposer(address account);
    /// @notice error returns when the proposal does not exist
    error GovernorNonexistentProposal(uint256 proposalId);

    constructor(
        IGame game_,
        address owner_,
        address[] memory signers_,
        address[] memory collections_
    ) Ownable(owner_) EIP712(_SIGNING_DOMAIN, version()) {
        game = game_;

        uint256 length = collections_.length;
        for (uint256 i; i < length; ) {
            if (collections_[i] == address(0)) {
                revert ZeroAddress();
            }

            collections[collections_[i]] = true;

            unchecked {
                ++i;
            }
        }

        uint256 signerLength = signers_.length;
        for (uint256 i; i < signerLength; ) {
            if (signers_[i] == address(0)) {
                revert ZeroAddress();
            }

            signers[signers_[i]] = true;

            unchecked {
                ++i;
            }
        }
    }

    function hashProposal(
        address collection,
        address proposer,
        string[] calldata options
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(collection, proposer, options)));
    }

    /**
     * @dev See {IGovernor-state}.
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        // We read the struct fields into the stack at once so Solidity emits a single SLOAD
        ProposalCore storage proposal = _proposals[proposalId];
        bool proposalExecuted = proposal.executed;
        bool proposalCanceled = proposal.canceled;

        if (proposalExecuted) {
            return ProposalState.Executed;
        }

        if (proposalCanceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = _proposals[proposalId].voteStart;

        if (snapshot == 0) {
            revert GovernorNonexistentProposal(proposalId);
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline >= currentTimepoint) {
            return ProposalState.Active;
        } else if (!_quorumReached(proposalId) || !_voteSucceeded(proposalId)) {
            return ProposalState.Defeated;
        } else {
            return ProposalState.Succeeded;
        }
    }

    function version() public pure returns (string memory) {
        return "1";
    }

    function clock() public view returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure returns (string memory) {
        return "mode=timestamp";
    }

    function proposalSnapshot(
        uint256 proposalId
    ) public view returns (uint256) {
        return _proposals[proposalId].voteStart;
    }

    /**
     * @dev See {IGovernor-proposalDeadline}.
     */
    function proposalDeadline(
        uint256 proposalId
    ) public view returns (uint256) {
        return
            _proposals[proposalId].voteStart +
            _proposals[proposalId].voteDuration;
    }

    function proposalProposer(
        uint256 proposalId
    ) public view returns (address) {
        return _proposals[proposalId].proposer;
    }

    function proposalVotes(
        uint256 proposalId
    ) public view returns (uint256[] memory) {
        return _proposalsData[proposalId].votes;
    }

    /**
     * @dev Amount of votes already cast passes the threshold limit.
     */
    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        return QUORUM_REACHED_TRESHOLD < _proposalsData[proposalId].totalVotes;
    }

    /**
     * @dev Is the proposal successful or not.
     */
    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        ProposalData storage data = _proposalsData[proposalId];
        for (uint256 i = 0; i < data.votes.length; i++) {
            if (data.votes[i] > SUCCESS_PROPOSAL_TRESHOLD) {
                return true;
            }
        }
        return false;
    }

    function getVotes(address account) external view returns (uint256) {
        return _getVotes(account);
    }

    function propose(
        address collection,
        string[] calldata options,
        bytes[] calldata signatures
    ) public returns (uint256) {
        address proposer = _msgSender();

        if (!collections[collection]) {
            revert NotAllowedCollection();
        }

        uint256 proposerVotes = _getVotes(proposer);
        if (proposerVotes < WIN_PROPOSAL_TRESHOLD) {
            revert GovernorInsufficientProposerVotes(proposer, proposerVotes);
        }

        _verifyOptions(options, signatures);
        // __updateVotes(proposer, WIN_PROPOSAL_TRESHOLD)

        return _propose(collection, proposer, options);
    }

    function _propose(
        address collection,
        address proposer,
        string[] calldata options
    ) internal returns (uint256) {
        uint256 proposalId = hashProposal(collection, proposer, options);

        if (_proposals[proposalId].voteStart != 0) {
            revert GovernorUnexpectedProposalState(
                proposalId,
                state(proposalId),
                bytes32(0)
            );
        }

        uint256 snapshot = clock() + VOTING_DELAY;
        uint256 duration = VOTING_PERIOD;

        ProposalCore storage proposal = _proposals[proposalId];
        proposal.proposer = proposer;
        proposal.voteStart = SafeCast.toUint48(snapshot);
        proposal.voteDuration = SafeCast.toUint32(duration);

        ProposalData storage proposalData = _proposalsData[proposalId];
        proposalData.votes = new uint256[](options.length);

        emit ProposalCreated(
            proposalId,
            proposer,
            collection,
            options,
            snapshot,
            snapshot + duration
        );

        return proposalId;
    }

    /**
     * @dev See {IGovernor-castVote}.
     */
    function castVote(
        uint256 proposalId,
        uint8 support,
        uint256 amount
    ) public returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, amount, "");
    }

    /**
     * @dev See {IGovernor-castVoteWithReason}.
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        uint256 amount,
        string calldata reason
    ) public returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, amount, reason);
    }

    /**
     * @dev See {IGovernor-execute}.
     */
    function execute(
        address collection,
        address proposer,
        string[] calldata options
    ) public payable returns (uint256) {
        uint256 proposalId = hashProposal(collection, proposer, options);

        _validateStateBitmap(
            proposalId,
            _encodeStateBitmap(ProposalState.Succeeded) |
                _encodeStateBitmap(ProposalState.Queued)
        );

        // mark as executed before calls to avoid reentrancy
        _proposals[proposalId].executed = true;

        uint8 winnerOptionIndex = _getWinnerOptionIndex(proposalId);
        string calldata winnerOption = options[winnerOptionIndex];

        uint256 newCardId = _executeOperations(collection, winnerOption);

        emit ProposalExecuted(proposalId, newCardId);

        return proposalId;
    }

    /**
     * @dev See {IGovernor-cancel}.
     */
    function cancel(
        address collection,
        address proposer,
        string[] calldata options
    ) public returns (uint256) {
        uint256 proposalId = hashProposal(collection, proposer, options);

        // public cancel restrictions (on top of existing _cancel restrictions).
        _validateStateBitmap(
            proposalId,
            _encodeStateBitmap(ProposalState.Pending)
        );

        if (_msgSender() != proposalProposer(proposalId)) {
            revert GovernorOnlyProposer(_msgSender());
        }

        return _cancel(proposalId);
    }

    function _cancel(uint256 proposalId) internal returns (uint256) {
        _validateStateBitmap(
            proposalId,
            ALL_PROPOSAL_STATES_BITMAP ^
                _encodeStateBitmap(ProposalState.Canceled) ^
                _encodeStateBitmap(ProposalState.Expired) ^
                _encodeStateBitmap(ProposalState.Executed)
        );

        _proposals[proposalId].canceled = true;
        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    function _getUserWinnedGames(address user) internal view returns (uint256) {
        return IGame(game).userStats(user).winner;
    }

    function _validateStateBitmap(
        uint256 proposalId,
        bytes32 allowedStates
    ) private view returns (ProposalState) {
        ProposalState currentState = state(proposalId);
        if (_encodeStateBitmap(currentState) & allowedStates == bytes32(0)) {
            revert GovernorUnexpectedProposalState(
                proposalId,
                currentState,
                allowedStates
            );
        }
        return currentState;
    }

    function _encodeStateBitmap(
        ProposalState proposalState
    ) internal pure returns (bytes32) {
        return bytes32(1 << uint8(proposalState));
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function.
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 amount,
        string memory reason
    ) internal returns (uint256) {
        _validateStateBitmap(
            proposalId,
            _encodeStateBitmap(ProposalState.Active)
        );

        uint256 votes = _getVotes(account);
        if (votes == 0 || votes < amount) {
            revert NotEnoughVotes();
        }

        _updateVotes(account, amount);
        _countVote(proposalId, account, support, amount);

        emit VoteCast(account, proposalId, support, amount, reason);

        return amount;
    }

    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight
    ) internal {
        ProposalData storage proposal = _proposalsData[proposalId];
        if (support > proposal.votes.length) {
            revert InvalidSupport();
        }

        proposal.votes[support]++;
        proposal.totalVotes++;
    }

    function _verifyOptions(
        string[] calldata options,
        bytes[] calldata signatures
    ) internal {
        uint256 length = options.length;
        if (length != signatures.length) {
            revert ArrayLengthMissMatch();
        }

        if (length > MAX_OPTIONS_SIZE) {
            revert TooManyOptions();
        }

        for (uint256 i = 0; i < length; i++) {
            address signer = verify(
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            OPTION_TYPEHASH,
                            keccak256(bytes(options[i]))
                        )
                    )
                ),
                signatures[i]
            );

            if (!signers[signer]) {
                revert NotAllowedOption(options[i]);
            }
        }
    }

    function _getVotes(address account) internal view returns (uint256) {
        if (account == owner()) {
            return 99;
        }
        return _getUserWinnedGames(account) - usedVotes[account];
    }

    function _updateVotes(address account, uint256 amount) internal {
        usedVotes[account] = usedVotes[account] + amount;
    }

    function _executeOperations(
        address collection,
        string calldata option
    ) internal returns (uint256) {
        return IGameCollection(collection).mint(option);
    }

    function _getWinnerOptionIndex(
        uint256 proposalId
    ) internal view returns (uint8) {
        ProposalData storage data = _proposalsData[proposalId];
        uint8 index = 0;
        for (uint8 i = 1; i < data.votes.length; i++) {
            if (data.votes[i] > data.votes[index]) {
                index = i;
            }
        }
        return index;
    }

    function verify(
        bytes32 digest,
        bytes calldata signature
    ) public pure returns (address) {
        return ECDSA.recover(digest, signature);
    }
}
