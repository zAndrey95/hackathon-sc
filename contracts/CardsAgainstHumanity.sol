// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IEntropy} from "@pythnetwork/entropy-sdk-solidity/IEntropy.sol";
import {IGameCollection} from "./interfaces/IGameCollection.sol";

/// @dev returns when transfer ETH failed
error TransferFailed();
/// @dev returns when user has active game
error HasActiveGame();
/// @dev returns when user has insufficient funds
error InsufficientFunds();
/// @dev returns when roles not assigned
error RolesNotAssigned();
/// @dev returns when player not found
error PlayerNotFound();
/// @dev returns when invalid game status
error InvalidGameStatus();
/// @dev returns when not participate
error NotParticipate();
/// @dev returns when already done
error AlreadyDone();
/// @dev returns when invalid card
error InvalidCard();
/// @dev returns when zero address
error ZeroAddress();
/// @dev returns when incorrect sequence number
error IncorrectSequenceNumber();
/// @dev returns when no cards
error NoCards();
/// @dev returns when no active game
error NoActiveGame();
/// @dev returns when not submitted
error NotSubmitted();

contract CardsAgainstHumanity is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    enum GameStatus {
        WAITING_FOR_PLAYERS,
        PLAYERS_RECEIVE_CARDS,
        PLAYERS_SUBMIT_ANSWERS,
        JUDGE_SELECTS_WINNER,
        WINNER_SELECTED,
        CANCELED_BY_OWNER
    }

    enum UserStatus {
        NOT_JOINED,
        JOINED,
        RECEIVED_CARDS,
        SUBMITTED_ANSWERS,
        JUDGE_SELECTED_WINNER
    }

    enum PlayerRole {
        PLAYER,
        JUDGE
    }

    struct UserStats {
        uint256 games;
        uint256 winner;
    }

    /// @notice user stats
    /// @dev user => UserStats struct
    mapping(address => UserStats) public userStats;
    /// @notice entropy contract address
    address public entropy;
    /// @notice random provider contract address
    address public randomProvider;
    /// @notice questions collection contract address
    address public questionsCollection;
    /// @notice answers collection contract address
    address public answersCollection;
    /// @notice games counter
    uint256 public gamesCounter;
    /// @notice max players in game
    uint16 public constant maxPlayers = 4;
    /// @notice total answers cards
    uint16 public constant totalAnswers = 4;
    /// @notice total questions cards
    uint16 public constant totalQuestions = 1;
    /// @notice active games set
    EnumerableSet.UintSet private activeGames;
    /// @notice user sequence number for random request
    mapping(address => uint64) private userSequenceNumber;
    /// @notice requested randoms
    mapping(uint64 => address) private requestedRandoms;
    /// @notice player role in game
    /// @dev player => gameID => role
    mapping(address => mapping(uint256 => PlayerRole)) private playerRole;
    /// @notice user status in game
    /// @dev player => gameID => status
    mapping(address => mapping(uint256 => UserStatus)) private userStatus;
    /// @notice user current game
    /// @dev player => gameID
    mapping(address => uint256 userCurrentGame) private userCurrentGame;
    /// @notice player answers
    /// @dev player => gameID => answers
    mapping(address => mapping(uint256 => EnumerableSet.UintSet))
        private playerAnswers;
    /// @notice player question
    /// @dev player => gameID => question
    mapping(address => mapping(uint256 => uint64)) private playerQuestion;
    /// @notice players in game
    /// @dev gameID => players
    mapping(uint256 => EnumerableSet.AddressSet) private players;
    /// @notice game status
    /// @dev gameID => status
    mapping(uint256 => GameStatus) private gameStatus;
    /// @notice actions counter. Needed to track actions in game round
    /// @dev status => count
    mapping(uint256 => uint16) private actionsCounter;
    /// @notice game question
    /// @dev gameID => question
    mapping(uint256 => uint64) private gameQuestion;
    /// @notice win answer
    /// @dev gameID => answer
    mapping(uint256 => uint64) private winAnswer;
    /// @notice player selected answer
    /// @dev gameID => player => answer
    mapping(uint256 => mapping(address => uint64)) private playerSelectedAnswer;
    /// @notice submitted answers
    /// @dev gameID => cards
    mapping(uint256 => EnumerableSet.UintSet) private submittedAnswers;
    /// @notice player by selected answer
    /// @dev gameID => answer => player
    mapping(uint256 => mapping(uint256 => address))
        private playerBySelectedAnswer;
    /// @notice available cards for random distribution
    /// @dev gameID => collectionAddress => cardId => cardId
    mapping(uint256 => mapping(address => mapping(uint256 => uint256)))
        private _availableCards;
    /// @notice num available cards for random distribution
    /// @dev gameID => collectionAddress => numAvailableCards
    mapping(uint256 => mapping(address => uint256)) private _numAvailableCards;
    /// @notice questioner commitment
    mapping(uint256 => bytes32) questionerCommitment;

    /// @notice emits when game created
    /// @param gameId game id
    event GameCreated(uint256 indexed gameId);
    /// @notice emits when user random request
    /// @param gameId game id
    /// @param player player address
    event UserRandomRequstested(uint256 indexed gameId, address indexed player);
    /// @notice emits when player joined game
    /// @param gameId game id
    /// @param player player address
    event PlayerJoined(uint256 indexed gameId, address indexed player);
    /// @notice emits when player received cards
    /// @param gameId game id
    /// @param player player address
    event PlayerReceivedCards(uint256 indexed gameId, address indexed player);
    /// @notice emits when judge selected
    /// @param gameId game id
    /// @param judge judge address
    event JudgeSelected(uint256 indexed gameId, address indexed judge);
    /// @notice emits when player submit answer
    /// @param gameId game id
    /// @param player player address
    /// @param answer answer
    event PlayerSubmitAnswer(
        uint256 indexed gameId,
        address indexed player,
        uint64 answer
    );
    /// @notice emits when judge selected winner
    /// @param gameId game id
    /// @param winner winner address
    /// @param answer answer
    event JudgeSelectedWinner(
        uint256 indexed gameId,
        address indexed winner,
        uint64 answer
    );
    /// @notice emits when game canceled by owner
    /// @param gameId game id
    event GameCanceledByOwner(uint256 indexed gameId);

    constructor(
        address _enthropy,
        address _randomProvider,
        address _questionsCollection,
        address _answersCollection
    ) Ownable(msg.sender) {
        if (
            _enthropy == address(0) ||
            _randomProvider == address(0) ||
            _questionsCollection == address(0) ||
            _answersCollection == address(0)
        ) {
            revert ZeroAddress();
        }
        entropy = _enthropy;
        randomProvider = _randomProvider;
        questionsCollection = _questionsCollection;
        answersCollection = _answersCollection;
        gamesCounter++;
    }

    /// @notice function that allows users to join the game.
    /// @dev users can join the game by sending a payment for the random number request.
    /// @param _commitments array of commitments
    function joinGame(bytes32[5] memory _commitments) external payable {
        _checkUsersActiveGames(msg.sender);
        _approvePayment(msg.sender, msg.value);

        uint256 gameID = gamesCounter;
        if (players[gameID].length() == 0) {
            gameStatus[gameID] = GameStatus.WAITING_FOR_PLAYERS;
            _numAvailableCards[gamesCounter][
                answersCollection
            ] = IGameCollection(answersCollection).totalSupply();
            _numAvailableCards[gamesCounter][
                questionsCollection
            ] = IGameCollection(questionsCollection).totalSupply();
            emit GameCreated(gameID);
        }

        uint256 enthropyfee = IEntropy(entropy).getFee(randomProvider);
        uint64 sequenceNumber = _requestRandom(
            randomProvider,
            _getCombineCommitment(_commitments),
            enthropyfee
        );
        requestedRandoms[sequenceNumber] = msg.sender;
        userSequenceNumber[msg.sender] = sequenceNumber;

        players[gameID].add(msg.sender);
        userStatus[msg.sender][gameID] = UserStatus.JOINED;
        userStats[msg.sender].games += 1;
        userCurrentGame[msg.sender] = gameID;
        emit PlayerJoined(gameID, msg.sender);

        if (players[gameID].length() == maxPlayers) {
            gameStatus[gameID] = GameStatus.PLAYERS_RECEIVE_CARDS;
            activeGames.add(gameID);
            ++gamesCounter;
        }
    }

    /// @notice function that allows users to receive cards.
    /// @param gameId game id
    /// @param sequenceNumber sequence number
    /// @param userRandoms array of user randoms
    /// @param providerRandom provider random
    function playerReceivedCards(
        uint256 gameId,
        uint64 sequenceNumber,
        bytes32[5] memory userRandoms,
        bytes32 providerRandom
    ) external {
        GameStatus status = gameStatus[gameId];
        if (
            status == GameStatus.PLAYERS_RECEIVE_CARDS ||
            status == GameStatus.WAITING_FOR_PLAYERS
        ) {
            if (!players[gameId].contains(msg.sender)) {
                revert NotParticipate();
            }

            if (userStatus[msg.sender][gameId] == UserStatus.RECEIVED_CARDS) {
                revert AlreadyDone();
            }

            bytes32 randomNumber = _getRandom(
                sequenceNumber,
                _getCombineNumber(userRandoms),
                providerRandom
            );
            for (uint16 i; i < userRandoms.length; i++) {
                if (i != userRandoms.length - 1) {
                    bytes32 combinedRandom = keccak256(
                        abi.encodePacked(
                            randomNumber,
                            userRandoms[i],
                            providerRandom
                        )
                    );
                    uint256 random = uint256(combinedRandom) %
                        _numAvailableCards[gameId][answersCollection];

                    uint256 cardId = _getAvailableCardAtIndexForCollection(
                        gameId,
                        answersCollection,
                        random,
                        _numAvailableCards[gameId][answersCollection]
                    );
                    _numAvailableCards[gameId][answersCollection] -= 1;
                    playerAnswers[msg.sender][gameId].add(cardId);
                } else {
                    uint256 random = uint256(randomNumber) %
                        _numAvailableCards[gameId][questionsCollection];
                    questionerCommitment[gameId] = keccak256(
                        abi.encodePacked(
                            questionerCommitment[gameId],
                            randomNumber
                        )
                    );

                    uint256 cardId = _getAvailableCardAtIndexForCollection(
                        gameId,
                        questionsCollection,
                        random,
                        _numAvailableCards[gameId][questionsCollection]
                    );
                    _numAvailableCards[gameId][questionsCollection] -= 1;

                    playerQuestion[msg.sender][gameId] = uint64(cardId);
                }
            }
            actionsCounter[gameId] += 1;
            userStatus[msg.sender][gameId] = UserStatus.RECEIVED_CARDS;

            delete userSequenceNumber[msg.sender];
            emit PlayerReceivedCards(gameId, msg.sender);

            if (actionsCounter[gameId] == maxPlayers) {
                uint256 questionnerRandom = ((
                    uint256(questionerCommitment[gameId])
                ) % maxPlayers);
                gameStatus[gameId] = GameStatus.PLAYERS_SUBMIT_ANSWERS;
                address judge = players[gameId].at(questionnerRandom);
                playerRole[judge][gameId] = PlayerRole.JUDGE;
                gameQuestion[gameId] = playerQuestion[judge][gameId];
                delete actionsCounter[gameId];
                emit JudgeSelected(gameId, judge);
            }
        } else {
            revert InvalidGameStatus();
        }
    }

    /// @notice function that allows users to submit answers or judge to select winner.
    /// @param gameId game id
    /// @param card card
    function playerSendSelected(uint256 gameId, uint64 card) external {
        GameStatus status = gameStatus[gameId];
        PlayerRole role = playerRole[msg.sender][gameId];
        uint16 totalUsersAnswers = maxPlayers - 1;
        if (!players[gameId].contains(msg.sender)) {
            revert NotParticipate();
        }

        if (role == PlayerRole.PLAYER) {
            if (status != GameStatus.PLAYERS_SUBMIT_ANSWERS) {
                revert InvalidGameStatus();
            }
            if (!playerAnswers[msg.sender][gameId].contains(card)) {
                revert InvalidCard();
            }
            if (
                userStatus[msg.sender][gameId] == UserStatus.SUBMITTED_ANSWERS
            ) {
                revert AlreadyDone();
            }
            userStatus[msg.sender][gameId] = UserStatus.SUBMITTED_ANSWERS;
            playerSelectedAnswer[gameId][msg.sender] = card;
            actionsCounter[gameId] += 1;
            userCurrentGame[msg.sender] = 0;
            submittedAnswers[gameId].add(card);
            playerBySelectedAnswer[gameId][card] = msg.sender;
            if (actionsCounter[gameId] == totalUsersAnswers) {
                gameStatus[gameId] = GameStatus.JUDGE_SELECTS_WINNER;
            }
            emit PlayerSubmitAnswer(gameId, msg.sender, card);
        }

        if (role == PlayerRole.JUDGE) {
            if (status != GameStatus.JUDGE_SELECTS_WINNER) {
                revert InvalidGameStatus();
            }
            if (!submittedAnswers[gameId].contains(card)) {
                revert InvalidCard();
            }
            winAnswer[gameId] = card;
            userStats[playerBySelectedAnswer[gameId][card]].winner += 1;
            userStatus[msg.sender][gameId] = UserStatus.JUDGE_SELECTED_WINNER;
            gameStatus[gameId] = GameStatus.WINNER_SELECTED;
            activeGames.remove(gameId);
            userCurrentGame[msg.sender] = 0;
            emit JudgeSelectedWinner(gameId, msg.sender, card);
        }
    }

    /// @notice function that allows owner to cancel game if something went wrong.
    /// @param gameId game id
    function cancelGame(uint256 gameId) external onlyOwner {
        GameStatus status = gameStatus[gameId];
        if (
            status == GameStatus.PLAYERS_RECEIVE_CARDS ||
            status == GameStatus.PLAYERS_SUBMIT_ANSWERS ||
            status == GameStatus.JUDGE_SELECTS_WINNER
        ) {
            gameStatus[gameId] = GameStatus.CANCELED_BY_OWNER;
            activeGames.remove(gameId);

            for (uint256 i; i < players[gameId].length(); i++) {
                address player = players[gameId].at(i);
                userCurrentGame[player] = 0;
            }
            emit GameCanceledByOwner(gameId);
        } else {
            revert InvalidGameStatus();
        }
    }

    /// @notice function make checks if player is in passed game
    /// @param player player address
    /// @param gameId game id
    /// @return bool true if player is in game
    function isPlayer(
        address player,
        uint256 gameId
    ) external view returns (bool) {
        return players[gameId].contains(player);
    }

    /// @notice function that returns active games ids
    /// @return array of active games ids
    function getActiveGames() external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](activeGames.length());
        for (uint256 i; i < activeGames.length(); i++) {
            result[i] = activeGames.at(i);
        }
        return result;
    }

    /// @notice function that returns game status
    /// @param gameId game id
    /// @return GameStatus game status
    function getGameStatus(uint256 gameId) external view returns (GameStatus) {
        return gameStatus[gameId];
    }

    /// @notice function that returns user status in game
    /// @param player player address
    /// @param gameId game id
    /// @return UserStatus user status
    function getUserStatus(
        address player,
        uint256 gameId
    ) external view returns (UserStatus) {
        return userStatus[player][gameId];
    }

    /// @notice function that returns game players addresses array
    /// @param gameId game id
    /// @return array of players addresses
    function getGamePlayers(
        uint256 gameId
    ) external view returns (address[] memory) {
        address[] memory result = new address[](players[gameId].length());
        for (uint256 i; i < players[gameId].length(); i++) {
            result[i] = players[gameId].at(i);
        }
        return result;
    }

    /// @notice function that returns player role in game
    /// @param player player address
    /// @param gameId game id
    /// @return PlayerRole player role
    function getPlayerRoleInGame(
        address player,
        uint256 gameId
    ) external view returns (PlayerRole) {
        GameStatus status = gameStatus[gameId];
        if (!players[gameId].contains(player)) {
            revert PlayerNotFound();
        }
        if (
            status == GameStatus.WAITING_FOR_PLAYERS ||
            status == GameStatus.PLAYERS_RECEIVE_CARDS
        ) {
            revert RolesNotAssigned();
        }
        return playerRole[player][gameId];
    }

    /// @notice function that returns game question
    /// @param gameId game id
    /// @return uint64 question
    function getActionsCountForRound(
        uint256 gameId
    ) external view returns (uint16) {
        return actionsCounter[gameId];
    }

    /// @notice function that returns player answer cards array in game
    /// @param player player address
    /// @param gameId game id
    /// @return array of player answer cards
    function getPlayerAnswerCards(
        address player,
        uint256 gameId
    ) external view returns (uint256[] memory) {
        if (
            userStatus[player][gameId] == UserStatus.NOT_JOINED ||
            userStatus[player][gameId] == UserStatus.JOINED
        ) {
            revert NoCards();
        }
        uint256[] memory result = new uint256[](
            playerAnswers[player][gameId].length()
        );
        for (uint256 i; i < playerAnswers[player][gameId].length(); i++) {
            result[i] = playerAnswers[player][gameId].at(i);
        }
        return result;
    }

    /// @notice function that returns player question card in game
    /// @param player player address
    /// @param gameId game id
    /// @return uint64 question card
    function getPlayerQuestionCard(
        address player,
        uint256 gameId
    ) external view returns (uint256) {
        if (
            userStatus[player][gameId] == UserStatus.NOT_JOINED ||
            userStatus[player][gameId] == UserStatus.JOINED
        ) {
            revert NoCards();
        }
        return playerQuestion[player][gameId];
    }

    /// @notice function that returns player current active game
    /// @param player player address
    /// @return uint256 game id
    function getPlayerActiveGame(
        address player
    ) external view returns (uint256) {
        return userCurrentGame[player];
    }

    /// @notice function that returns player sequence number for random request
    /// @param player player address
    /// @return uint64 sequence number
    function getPlayerSequenceNumber(
        address player
    ) external view returns (uint64) {
        if (userCurrentGame[player] == 0) {
            revert NoActiveGame();
        }
        return userSequenceNumber[player];
    }

    /// @notice function that returns player stats
    /// @param player player address
    /// @return UserStats user stats
    function getPlayerSelectedAnswer(
        address player,
        uint256 gameId
    ) external view returns (uint64) {
        if (userStatus[player][gameId] != UserStatus.SUBMITTED_ANSWERS) {
            revert NotSubmitted();
        }
        return playerSelectedAnswer[gameId][player];
    }

    /// @notice function that returns players selected answers
    /// @param gameId game id
    /// @return array of selected answers
    function getSelectedAnswers(
        uint256 gameId
    ) external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](
            submittedAnswers[gameId].length()
        );
        for (uint256 i; i < submittedAnswers[gameId].length(); i++) {
            result[i] = submittedAnswers[gameId].at(i);
        }
        return result;
    }

    /// @notice function that returns player by selected answer in game
    /// @param gameId game id
    /// @param answer answer
    /// @return address player
    function getPlayerBySelectedAnswer(
        uint256 gameId,
        uint64 answer
    ) external view returns (address) {
        return playerBySelectedAnswer[gameId][answer];
    }

    /// @notice function that returns game results
    /// @param gameId game id
    /// @return winner winner address
    /// @return winningAnswer winning answer
    /// @return question question
    function getGameResults(
        uint256 gameId
    )
        external
        view
        returns (address winner, uint64 winningAnswer, uint64 question)
    {
        if (gameStatus[gameId] != GameStatus.WINNER_SELECTED) {
            revert InvalidGameStatus();
        }
        winner = playerBySelectedAnswer[gameId][winAnswer[gameId]];
        winningAnswer = winAnswer[gameId];
        question = gameQuestion[gameId];
    }

    /// @notice function that returns random provider fee
    /// @return uint256 fee
    function getRandomProviderFee() external view returns (uint256) {
        return
            IEntropy(entropy).getFee(randomProvider) *
            (totalAnswers + totalQuestions);
    }

    /// @notice internal function that approves payment from user
    /// @param user user address
    /// @param value value
    function _approvePayment(address user, uint256 value) private {
        uint256 enthropyfee = IEntropy(entropy).getFee(randomProvider);
        if (value >= enthropyfee) {
            uint256 excess = value > enthropyfee ? value - enthropyfee : 0;
            if (excess > 0) {
                _sendNative(user, excess);
            }
        } else {
            revert InsufficientFunds();
        }
    }

    /// @notice internal function that gets random number from entropy
    /// @param sequenceNumber sequence number
    /// @param userRandom user random
    /// @param providerRandom provider random
    /// @return bytes32 random number
    function _getRandom(
        uint64 sequenceNumber,
        bytes32 userRandom,
        bytes32 providerRandom
    ) internal returns (bytes32) {
        if (requestedRandoms[sequenceNumber] != msg.sender) {
            revert IncorrectSequenceNumber();
        }
        delete requestedRandoms[sequenceNumber];

        return
            IEntropy(entropy).reveal(
                randomProvider,
                sequenceNumber,
                userRandom,
                providerRandom
            );
    }

    /// @notice internal function that requests random number from entropy
    /// @param provider provider address
    /// @param commitment commitment
    /// @param fee fee
    /// @return uint64 sequence number
    function _requestRandom(
        address provider,
        bytes32 commitment,
        uint256 fee
    ) internal returns (uint64) {
        uint64 sequenceNumber = IEntropy(entropy).request{value: fee}(
            provider,
            commitment,
            false
        );
        return sequenceNumber;
    }

    /// @notice internal function that sends native token
    /// @param to_ to address
    /// @param amount_ amount
    function _sendNative(address to_, uint256 amount_) internal {
        (bool success, ) = to_.call{value: amount_}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    /// @notice internal function that combines commitments
    /// @param commitments array of commitments
    /// @return bytes32 combined commitment
    function _getCombineCommitment(
        bytes32[5] memory commitments
    ) internal pure returns (bytes32) {
        return
            keccak256(
                bytes.concat(
                    keccak256(
                        abi.encodePacked(
                            commitments[0],
                            commitments[1],
                            commitments[2],
                            commitments[3],
                            commitments[4]
                        )
                    )
                )
            );
    }

    /// @notice internal function that combines numbers
    /// @param numbers array of numbers
    /// @return bytes32 combined number
    function _getCombineNumber(
        bytes32[5] memory numbers
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    keccak256(bytes.concat(numbers[0])),
                    keccak256(bytes.concat(numbers[1])),
                    keccak256(bytes.concat(numbers[2])),
                    keccak256(bytes.concat(numbers[3])),
                    keccak256(bytes.concat(numbers[4]))
                )
            );
    }

    /// @notice internal function that checks if user has active game
    /// @param _player player address
    function _checkUsersActiveGames(address _player) internal view {
        if (userCurrentGame[_player] != 0) {
            revert HasActiveGame();
        }
    }

    /// @notice internal function that gets available card index for collection.
    /// @dev it needed for random distribution and checks duplicates
    /// @param gameId game id
    /// @param collection collection address
    /// @param indexToUse index to use
    /// @param updatedNumAvailableTokens updated num available tokens
    /// @return uint256 available card index
    function _getAvailableCardAtIndexForCollection(
        uint256 gameId,
        address collection,
        uint256 indexToUse,
        uint256 updatedNumAvailableTokens
    ) internal returns (uint256) {
        uint256 valAtIndex = _availableCards[gameId][collection][indexToUse];
        uint256 result;
        if (valAtIndex == 0) {
            result = indexToUse;
        } else {
            result = valAtIndex;
        }

        uint256 lastIndex = updatedNumAvailableTokens - 1;
        if (indexToUse != lastIndex) {
            uint256 lastValInArray = _availableCards[gameId][collection][
                lastIndex
            ];
            if (lastValInArray == 0) {
                _availableCards[gameId][collection][indexToUse] = lastIndex;
            } else {
                _availableCards[gameId][collection][
                    indexToUse
                ] = lastValInArray;
            }
        }

        return result;
    }
}
