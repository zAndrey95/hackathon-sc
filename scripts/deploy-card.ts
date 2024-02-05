import { ethers } from "hardhat";
import { verifyContract } from "./verify";

// Deploy Arguments
const name = "CAH: Answers collection"; // "CAH: Questions collection";
const symbol = "CAH-A1"; //"CAH-Q1";
const owner = "0xC4b0F363125161C63fecb1Eee5dc345F385E7Fab";
const minters: string[] = [];

// Deploy && Verify
async function main() {
  const CARD = await ethers.getContractFactory("CAHCard");
  
  const card = await CARD.deploy(name, symbol, owner, minters);

  await card.deployed();

  console.log("Card deployed to:", card.address);

  try {
    await verifyContract(card.address, [
      name, symbol, owner, minters
    ]);
  } catch (error) {
    console.log(error);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});