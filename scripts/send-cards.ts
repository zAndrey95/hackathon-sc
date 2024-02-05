import { ethers } from "hardhat";
import questions from  '../assets/questions' ;
import answers from "../assets/answers";

const contractAddress = '0x0Ae7eA919296a279EbCfD2F6F6Cb30a8a128C787';
const data = answers;

// Send cards 
async function main() {
    
    const card = await ethers.getContractAt("CAHCard", contractAddress);

    try {
        // console.log(await card.estimateGas.bulkMint(data))
        const res =  await card.bulkMint(data);
        console.log(res)
    } catch (error) {
      console.log(error);
    }
  }
  
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });