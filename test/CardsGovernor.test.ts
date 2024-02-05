import { expect } from "chai";
import { ethers } from "hardhat";
import {
  MockCollection,
  MockEntropy,
  MockGame,
  CardsGovernor,
} from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, BytesLike } from "ethers";
import { PromiseOrValue } from "../typechain-types/common";
import exp from "constants";
import OptionsSigner from "./helper";

const options = [
  "I like hackathons for ________.",
  "My life would be incomprehensible without ________.",
  "In the new blockbuster, the main character saved the world using ________.",
  "The next fashion trend is ________.",
  "Why do I lose sleep at night? ________.",
];

const DEFAUTL_CHAIN_ID = 31337;

describe("CardsGovernor", () => {
  let governor: CardsGovernor;
  let game: MockGame;
  let answersCollection: MockCollection;
  let questionsCollection: MockCollection;
  let entropy: MockEntropy;
  let deployer: SignerWithAddress;
  let accounts: SignerWithAddress[];
  let player1: SignerWithAddress;
  let player2: SignerWithAddress;
  let player3: SignerWithAddress;
  let player4: SignerWithAddress;
  let signer: SignerWithAddress;
  let optionsSigner: OptionsSigner;
  const signatures: string[] = [];

  before(async () => {
    const [deployerAccount, acc1, acc2, acc3, acc4, acc5, ...others] =
      await ethers.getSigners();
    deployer = deployerAccount;
    accounts = others;
    player1 = acc1;
    player2 = acc2;
    player3 = acc3;
    player4 = acc4;
    signer = acc5;

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

    const CAH = await ethers.getContractFactory("MockGame");
    game = (await CAH.deploy()) as MockGame;

    const Governor = await ethers.getContractFactory("CardsGovernor");
    governor = await Governor.deploy(
      game.address,
      deployerAccount.address,
      [signer.address],
      [answersCollection.address, questionsCollection.address]
    );

    await game.setMockStats(player1.address, { winner: 50, games: 150 });
    await game.setMockStats(player2.address, { winner: 5, games: 10 });
    optionsSigner = new OptionsSigner(governor, signer, DEFAUTL_CHAIN_ID);
    for (const option of options) {
      signatures.push(await optionsSigner.signOption(option));
    }
  });

  describe("flow", () => {
    it("invalid signature proposal", async () => {
      const invalidSignatures = [...signatures];
      const invalidOption = options[0] + "!";
      invalidSignatures[0] = await optionsSigner.signOption(invalidOption);

      await expect(
        governor
          .connect(player1)
          .propose(questionsCollection.address, options, invalidSignatures)
      ).to.be.revertedWith(`NotAllowedOption("${options[0]}")`);
    });

    it("create proposal", async () => {
      const tx = await governor
        .connect(player1)
        .propose(questionsCollection.address, options, signatures);
      const receipt = await tx.wait();
      const events = receipt.events!.filter(
        (x) => x.event === "ProposalCreated"
      );
      const proposalId = events[0].args!.proposalId;
      const contractHash = await governor.hashProposal(
        questionsCollection.address,
        player1.address,
        options
      );
      expect(proposalId).to.equal(contractHash);
    });

    it("vote", async () => {
      const proposalId = await governor.hashProposal(
        questionsCollection.address,
        player1.address,
        options
      );

      await governor.connect(player2).castVote(proposalId, 3, 3);

      const votes = await governor.proposalVotes(proposalId);

      expect(votes).to.deep.equal([
        BigNumber.from(0),
        BigNumber.from(0),
        BigNumber.from(0),
        BigNumber.from(1),
        BigNumber.from(0),
      ]);
    });
  });

  describe("invalid flow", () => {
    it("invalid proposal", async () => {
      const invalidSignatures = [...signatures];
      const invalidOption = options[0] + "!";
      invalidSignatures[0] = await optionsSigner.signOption(invalidOption);

      await expect(
        governor
          .connect(player1)
          .propose(questionsCollection.address, options, invalidSignatures)
      ).to.be.revertedWith(`NotAllowedOption("${options[0]}")`);
    });
    it("should revert propose if not allowed collection", async () => {
      const invalidCollection = await ethers.getContractFactory(
        "MockCollection"
      );
      const invalidCollectionInstance = (await invalidCollection.deploy(
        100
      )) as MockCollection;
      await invalidCollectionInstance.deployed();
      await expect(
        governor
          .connect(player1)
          .propose(invalidCollectionInstance.address, options, signatures)
      ).to.be.revertedWith("NotAllowedCollection");
    });
    it("should revert propose if not enough wins", async () => {
      await expect(
        governor
          .connect(player4)
          .propose(questionsCollection.address, options, signatures)
      ).to.be.revertedWith(
        `GovernorInsufficientProposerVotes("${player4.address}", 0)`
      );
    });
    it("should return proposal CLOCK_MODE", async () => {
      expect(await governor.CLOCK_MODE()).to.equal("mode=timestamp");
    });
  });
});
