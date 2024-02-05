import { expect } from "chai";
import { ethers } from "hardhat";
import {
  CardsAgainstHumanity,
  MockCollection,
  MockEntropy,
} from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, BytesLike, utils } from "ethers";

const GameStatus = {
  WAITING_FOR_PLAYERS: 0,
  PLAYERS_RECEIVE_CARDS: 1,
  PLAYERS_SUBMIT_ANSWERS: 2,
  JUDGE_SELECTS_WINNER: 3,
  WINNER_SELECTED: 4,
  CANCELLED: 5,
};

const PlayerRole = {
  PLAYER: 0,
  JUDGE: 1,
};

type GameBytes = [BytesLike, BytesLike, BytesLike, BytesLike, BytesLike];

const getRandomInt = (max = 100) => {
  return Math.floor(Math.random() * max);
};

const getUserData = () => {
  const userRandomness = [];
  for (let i = 0; i < 5; i++) {
    userRandomness.push(ethers.utils.randomBytes(32));
  }
  const userCommitments: BytesLike[] = userRandomness.map((el) => {
    return ethers.utils.keccak256(el) as BytesLike;
  });
  return {
    numbers: userRandomness.map((e) =>
      Buffer.from(e).toString("hex")
    ) as GameBytes,
    commitments: userCommitments as GameBytes,
  };
};

describe("CAH logic", function () {
  let cahGame: CardsAgainstHumanity;
  let answersCollection: MockCollection;
  let questionsCollection: MockCollection;
  let entropy: MockEntropy;
  let deployer: SignerWithAddress;
  let accounts: SignerWithAddress[];
  let player1: SignerWithAddress;
  let player2: SignerWithAddress;
  let player3: SignerWithAddress;
  let player4: SignerWithAddress;

  const playersData: {
    [key in string]: { numbers: GameBytes; commitments: GameBytes };
  } = {};

  const joinToGame = async (
    gameContract: CardsAgainstHumanity,
    entropyContract: MockEntropy,
    user: SignerWithAddress
  ) => {
    const data = playersData[user.address];
    const fee = await entropyContract.getFee(entropyContract.address);
    const feeAmount = fee; //.mul(BigNumber.from(5));
    return gameContract
      .connect(user)
      .joinGame(data.commitments, { value: feeAmount });
  };

  const receiveCards = async (
    gameId: BigNumber,
    cahGame: CardsAgainstHumanity,
    user: SignerWithAddress
  ) => {
    const providerRandom = ethers.utils.formatBytes32String(
      getRandomInt().toString()
    );

    if (gameId.eq(0)) {
      throw new Error("Player has no active game");
    }
    const sequenceNumber: any = await cahGame.getPlayerSequenceNumber(
      user.address
    );
    // const commitments: any = await cahGame.getPlayerCommitments(user.address);
    const commitments = playersData[user.address].commitments;

    return cahGame
      .connect(user)
      .playerReceivedCards(gameId, sequenceNumber, commitments, providerRandom);
  };

  before(async () => {
    const [deployerAccount, acc1, acc2, acc3, acc4, ...others] =
      await ethers.getSigners();
    deployer = deployerAccount;
    accounts = others;
    player1 = acc1;
    player2 = acc2;
    player3 = acc3;
    player4 = acc4;

    const AnswersCollection = await ethers.getContractFactory("MockCollection");
    answersCollection = (await AnswersCollection.deploy(100)) as MockCollection;
    await answersCollection.deployed();

    const QuestionsCollection = await ethers.getContractFactory(
      "MockCollection"
    );
    questionsCollection = (await QuestionsCollection.deploy(
      100
    )) as MockCollection;
    await questionsCollection.deployed();

    const Entropy = await ethers.getContractFactory("MockEntropy");
    entropy = (await Entropy.deploy()) as MockEntropy;
    await entropy.deployed();

    const CAH = await ethers.getContractFactory("CardsAgainstHumanity");
    cahGame = (await CAH.deploy(
      entropy.address,
      answersCollection.address,
      questionsCollection.address,
      answersCollection.address
    )) as CardsAgainstHumanity;

    playersData[player1.address] = getUserData();
    playersData[player2.address] = getUserData();
    playersData[player3.address] = getUserData();
    playersData[player4.address] = getUserData();
    accounts.forEach((acc) => (playersData[acc.address] = getUserData()));
  });

  describe("Contract deployment", async () => {
    it("should revert if entropy address is zero", async () => {
      const CAH = await ethers.getContractFactory("CardsAgainstHumanity");
      await expect(
        CAH.deploy(
          ethers.constants.AddressZero,
          answersCollection.address,
          questionsCollection.address,
          answersCollection.address
        )
      ).to.be.revertedWith("ZeroAddress()");
    });
    it("should revert if answers collection address is receiveCardscommzero", async () => {
      const CAH = await ethers.getContractFactory("CardsAgainstHumanity");
      await expect(
        CAH.deploy(
          entropy.address,
          ethers.constants.AddressZero,
          questionsCollection.address,
          answersCollection.address
        )
      ).to.be.revertedWith("ZeroAddress()");
    });
    it("should revert if questions collection address is zero", async () => {
      const CAH = await ethers.getContractFactory("CardsAgainstHumanity");
      await expect(
        CAH.deploy(
          entropy.address,
          answersCollection.address,
          ethers.constants.AddressZero,
          answersCollection.address
        )
      ).to.be.revertedWith("ZeroAddress()");
    });
    it("should revert if random provider address is zero", async () => {
      const CAH = await ethers.getContractFactory("CardsAgainstHumanity");
      await expect(
        CAH.deploy(
          entropy.address,
          answersCollection.address,
          questionsCollection.address,
          ethers.constants.AddressZero
        )
      ).to.be.revertedWith("ZeroAddress()");
    });
  });

  describe("Game flow tests", async () => {
    it("should revert getPlayerAnswerCards if player not receive cards", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await expect(
        cahGame.getPlayerAnswerCards(player1.address, gameId)
      ).to.be.revertedWith("NoCards()");
    });
    it("should revert get player qusetion card if player not receive cards", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await expect(
        cahGame.getPlayerQuestionCard(player1.address, gameId)
      ).to.be.revertedWith("NoCards()");
    });
    it("should revert getPlayerSequenceNumbers if player not part of game", async () => {
      await expect(
        cahGame.getPlayerSequenceNumber(accounts[5].address)
      ).to.be.revertedWith("NoActiveGame()");
    });
    // it("should revert getPlayerCommitments if player not part of game", async () => {
    //   await expect(
    //     cahGame.getPlayerCommitments(accounts[5].address)
    //   ).to.be.revertedWith("NoActiveGame()");
    // });
    it("Should first player join to game", async () => {
      expect(await cahGame.getGameStatus(0)).to.equal(
        GameStatus.WAITING_FOR_PLAYERS
      );
      const gameId = await cahGame.gamesCounter();
      await joinToGame(cahGame, entropy, player1);
      expect(await cahGame.gamesCounter()).to.equal(1);
      expect(await cahGame.isPlayer(player1.address, gameId)).to.equal(true);
    });
    it("should second player join to game", async () => {
      const gameId = await cahGame.gamesCounter();
      await joinToGame(cahGame, entropy, player2);

      expect(await cahGame.gamesCounter()).to.equal(1);
      expect(await cahGame.isPlayer(player2.address, gameId)).to.equal(true);
    });
    it("should revert get player role in game if roles not assigned", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await expect(
        cahGame.getPlayerRoleInGame(player1.address, gameId)
      ).to.be.revertedWith("RolesNotAssigned()");
    });
    it("should revert getPlayerAnswerCards if player not receive cards", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await expect(
        cahGame.getPlayerAnswerCards(player1.address, gameId)
      ).to.be.revertedWith("NoCards()");
    });
    it("should revert get player qusetion card if player not receive cards", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await expect(
        cahGame.getPlayerQuestionCard(player1.address, gameId)
      ).to.be.revertedWith("NoCards()");
    });
    it("should third player join to game", async () => {
      const gameId = await cahGame.gamesCounter();
      await joinToGame(cahGame, entropy, player3);
      expect(await cahGame.gamesCounter()).to.equal(1);
      expect(await cahGame.isPlayer(player3.address, gameId)).to.equal(true);
      expect(await cahGame.getGameStatus(gameId)).to.equal(
        GameStatus.WAITING_FOR_PLAYERS
      );
    });
    // it("should revert receive catds if players not enough", async () => {
    //   const gameId = await cahGame.getPlayerActiveGame(player1.address);
    //   await expect(receiveCards(gameId, cahGame, player1)).to.be.revertedWith(
    //     "InvalidGameStatus()"
    //   );
    // });
    it("should fourth player join to game", async () => {
      const gameId = await cahGame.gamesCounter();
      await joinToGame(cahGame, entropy, player4);

      expect(await cahGame.gamesCounter()).to.equal(2);
      expect(await cahGame.isPlayer(player4.address, gameId)).to.equal(true);
      expect(await cahGame.getGameStatus(gameId)).to.equal(
        GameStatus.PLAYERS_RECEIVE_CARDS
      );
    });
    it("should revert if player already joined to game", async () => {
      await expect(joinToGame(cahGame, entropy, player4)).to.be.revertedWith(
        "HasActiveGame()"
      );
    });

    it("should receive cards for player 1", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await receiveCards(gameId, cahGame, player1);
      const answers = await cahGame.getPlayerAnswerCards(
        player1.address,
        gameId
      );
      expect(answers.length).to.be.equal(await cahGame.totalAnswers());
    });
    it("should receive cards for player 2", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player2.address);
      await receiveCards(gameId, cahGame, player2);
      const answers = await cahGame.getPlayerAnswerCards(
        player2.address,
        gameId
      );
      expect(answers.length).to.be.equal(await cahGame.totalAnswers());
    });
    it("should revert if player already received cards", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await expect(receiveCards(gameId, cahGame, player1)).to.be.revertedWith(
        "AlreadyDone()"
      );
    });
    it("should return player question card", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      const questionCard = await cahGame.getPlayerQuestionCard(
        player1.address,
        gameId
      );
      expect(questionCard).to.be.gt(0);
    });
    it("should revert getPlayerSelectedAnswer if player not submit answer", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await expect(
        cahGame.getPlayerSelectedAnswer(player1.address, gameId)
      ).to.be.revertedWith("NotSubmitted()");
    });
    it("should revert getGameResults if game not finished", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await expect(cahGame.getGameResults(gameId)).to.be.revertedWith(
        "InvalidGameStatus()"
      );
    });
    it("should return random provider fee", async () => {
      const fee = (await entropy.getFee(entropy.address)).mul(
        BigNumber.from(5)
      );
      expect(fee).to.be.equal(await cahGame.getRandomProviderFee());
    });
    it("should revert if player not part of game", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      const providerRandom = ethers.utils.formatBytes32String(
        getRandomInt().toString()
      );

      const sequenceNumbers: any = await cahGame.getPlayerSequenceNumber(
        player3.address
      );
      // const commitments: any = await cahGame.getPlayerCommitments(
      //   player3.address
      // );

      await expect(
        cahGame
          .connect(accounts[5])
          .playerReceivedCards(
            gameId,
            sequenceNumbers,
            playersData[accounts[5].address].commitments,
            providerRandom
          )
      ).to.be.revertedWith("NotParticipate()");
    });
    it("should revert join to game if player have active game", async () => {
      await expect(joinToGame(cahGame, entropy, player3)).to.be.revertedWith(
        "HasActiveGame()"
      );
    });
    it("should receive cards for player 3", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player3.address);
      await receiveCards(gameId, cahGame, player3);
      const answers = await cahGame.getPlayerAnswerCards(
        player3.address,
        gameId
      );
      expect(answers.length).to.be.equal(await cahGame.totalAnswers());
    });
    it("should revert submit answers if players not enough", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await expect(
        cahGame.connect(player1).playerSendSelected(gameId, 0)
      ).to.be.revertedWith("InvalidGameStatus()");
    });
    it("should revert get player role in game if roles not assigned", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await expect(
        cahGame.getPlayerRoleInGame(player1.address, gameId)
      ).to.be.revertedWith("RolesNotAssigned()");
    });
    it("should receive cards for player 4", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player4.address);
      await receiveCards(gameId, cahGame, player4);
      const answers = await cahGame.getPlayerAnswerCards(
        player4.address,
        gameId
      );
      expect(answers.length).to.be.equal(await cahGame.totalAnswers());
      expect(await cahGame.getGameStatus(gameId)).to.equal(
        GameStatus.PLAYERS_SUBMIT_ANSWERS
      );
    });
    it("should revert if player not part of game", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      const playerAnswers = await cahGame.getPlayerAnswerCards(
        player1.address,
        gameId
      );
      await expect(
        cahGame
          .connect(accounts[5])
          .playerSendSelected(gameId, playerAnswers[0])
      ).to.be.revertedWith("NotParticipate()");
    });
    it("should get game players", async () => {
      const players = [player1, player2, player3, player4];
      const gamePlayers = await cahGame.getGamePlayers(1);
      for (let i = 0; i < players.length; i++) {
        expect(players[i].address).to.equal(gamePlayers[i]);
      }
    });
    it("should revert get player role in game if player not part of game", async () => {
      await expect(
        cahGame.getPlayerRoleInGame(accounts[5].address, 1)
      ).to.be.revertedWith("PlayerNotFound()");
    });
    it("should submit answers and select winner", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      const users = [player1, player2, player3, player4];
      let judge = player1;
      for (let i = 0; i < users.length; i++) {
        const playerRole = await cahGame.getPlayerRoleInGame(
          users[i].address,
          gameId
        );
        if (playerRole === PlayerRole.JUDGE) {
          judge = users[i];
        }
      }
      for (let i = 0; i < users.length; i++) {
        const playerRole = await cahGame.getPlayerRoleInGame(
          users[i].address,
          gameId
        );
        if (playerRole === PlayerRole.PLAYER) {
          const playerAnswers = await cahGame.getPlayerAnswerCards(
            users[i].address,
            gameId
          );
          const selectedAnswer = playerAnswers[0];
          await expect(
            cahGame.connect(users[i]).playerSendSelected(gameId, 1000)
          ).to.be.revertedWith("InvalidCard()");

          await cahGame
            .connect(users[i])
            .playerSendSelected(gameId, selectedAnswer);

          const actionsCounter = await cahGame.getActionsCountForRound(gameId);
          if (actionsCounter < 3) {
            await expect(
              cahGame
                .connect(users[i])
                .playerSendSelected(gameId, selectedAnswer)
            ).to.be.revertedWith("AlreadyDone()");
            await expect(
              cahGame.connect(judge).playerSendSelected(gameId, selectedAnswer)
            ).to.be.revertedWith("InvalidGameStatus()");
          }

          expect(
            await cahGame.getPlayerSelectedAnswer(users[i].address, gameId)
          ).to.equal(selectedAnswer);
        }
      }

      expect(await cahGame.getGameStatus(gameId)).to.equal(
        GameStatus.JUDGE_SELECTS_WINNER
      );

      const selectedAnswers = await cahGame.getSelectedAnswers(gameId);

      await expect(
        cahGame.connect(judge).playerSendSelected(gameId, 1000)
      ).to.be.revertedWith("InvalidCard()");
      await cahGame
        .connect(judge)
        .playerSendSelected(gameId, selectedAnswers[0]);
      expect(await cahGame.getGameStatus(gameId)).to.equal(
        GameStatus.WINNER_SELECTED
      );
      const gameResult = await cahGame.getGameResults(gameId);
      expect(gameResult.winner).to.equal(
        await cahGame.getPlayerBySelectedAnswer(gameId, selectedAnswers[0])
      );
      expect(gameResult.winningAnswer).to.equal(selectedAnswers[0]);
    });
  });
  describe("Flow with cancel game", async () => {
    it("should join to game", async () => {
      const gameId = await cahGame.gamesCounter();
      await joinToGame(cahGame, entropy, player1);
      expect(await cahGame.gamesCounter()).to.equal(2);
      expect(await cahGame.isPlayer(player1.address, gameId)).to.equal(true);
    });
    it("should receive cards for player 1", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);
      await receiveCards(gameId, cahGame, player1);
      const answers = await cahGame.getPlayerAnswerCards(
        player1.address,
        gameId
      );
      expect(answers.length).to.be.equal(await cahGame.totalAnswers());
    });
    it("should other players join to game and receive cards", async () => {
      const gameId = await cahGame.gamesCounter();
      await joinToGame(cahGame, entropy, player2);
      await joinToGame(cahGame, entropy, player3);
      await joinToGame(cahGame, entropy, player4);

      expect(await cahGame.gamesCounter()).to.equal(3);
      expect(await cahGame.isPlayer(player2.address, gameId)).to.equal(true);
      expect(await cahGame.isPlayer(player3.address, gameId)).to.equal(true);
      expect(await cahGame.isPlayer(player4.address, gameId)).to.equal(true);
      expect(await cahGame.getGameStatus(gameId)).to.equal(
        GameStatus.PLAYERS_RECEIVE_CARDS
      );

      await receiveCards(gameId, cahGame, player2);
      await receiveCards(gameId, cahGame, player3);
      await receiveCards(gameId, cahGame, player4);
      expect(await cahGame.getGameStatus(gameId)).to.equal(
        GameStatus.PLAYERS_SUBMIT_ANSWERS
      );
    });
    it("should cancel game", async () => {
      const gameId = await cahGame.getPlayerActiveGame(player1.address);

      const players = [player1, player2, player3, player4];
      const user =
        (await cahGame.getPlayerRoleInGame(player1.address, gameId)) == 0
          ? players[0]
          : players[1];
      const playerAnswers = await cahGame.getPlayerAnswerCards(
        user.address,
        gameId
      );
      const selectedAnswer = playerAnswers[0];
      await cahGame.connect(user).playerSendSelected(gameId, selectedAnswer);
      expect(
        await cahGame.getPlayerSelectedAnswer(user.address, gameId)
      ).to.equal(selectedAnswer);
      const activeGamesBefore = await cahGame.getActiveGames();
      expect(activeGamesBefore.length).to.be.equal(1);

      await cahGame.cancelGame(gameId);
      expect(await cahGame.getGameStatus(gameId)).to.equal(
        GameStatus.CANCELLED
      );
      const activeGames = await cahGame.getActiveGames();
      expect(activeGames.length).to.be.equal(0);

      for (let i = 0; i < players.length; i++) {
        const gameId = await cahGame.getPlayerActiveGame(players[i].address);
        expect(gameId).to.equal(0);
      }
    });
  });
});
