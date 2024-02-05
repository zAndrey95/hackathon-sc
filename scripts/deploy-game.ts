import { ethers } from "hardhat";
import { verifyContract } from "./verify";

// Deploy Arguments
const _enthropy = '0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a';
const _randomProvider = '0x6CC14824Ea2918f5De5C2f75A9Da968ad4BD6344'
const _questionsCollection = '0x6445cC914C3F7F128d5Cbef781C8C54094Ab0566';
const _answersCollection = '0x0Ae7eA919296a279EbCfD2F6F6Cb30a8a128C787';

// Deploy && Verify
async function main() {
  const CAH = await ethers.getContractFactory("CardsAgainstHumanity");
  
  const game = await CAH.deploy(_enthropy, _randomProvider, _questionsCollection, _answersCollection);

  await game.deployed();

  console.log("CardsAgainstHumanity deployed to:", game.address);

  try {
    await verifyContract(game.address, [
      _enthropy, _randomProvider, _questionsCollection, _answersCollection
    ]);
  } catch (error) {
    console.log(error);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});