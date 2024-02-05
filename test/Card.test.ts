import { expect } from "chai";
import { ethers } from "hardhat";
import {
  MockCollection,
  MockEntropy,
  MockGame,
  CardsGovernor,
  CAHCard
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
  "Why do I lose sleep at night? ________."
]

const DEFAUTL_CHAIN_ID = 31337;


describe("Card", ()=>{
    let card: CAHCard;
    let deployer: SignerWithAddress;
    let accounts: SignerWithAddress[];
    let player1: SignerWithAddress;
    let player2: SignerWithAddress;
    let player3: SignerWithAddress;
    let player4: SignerWithAddress;
    let signer: SignerWithAddress;
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
    
        const CAH = await ethers.getContractFactory("CAHCard");
        card = (await CAH.deploy(
            "NAME",
            "TTT",
            player1.address,
            []
        )) as CAHCard;

    });

    describe('flow', ()=> {
    
        it('bulk mint', async ()=>{
            const tx = await card.connect(player1).bulkMint(options) 
        })

      
    })


    
})