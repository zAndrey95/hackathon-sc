import { randomInt } from "crypto";
import ethers from "ethers";
import {   CardsGovernor } from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";


// These constants must match the ones used in the smart contract.
const SIGNING_DOMAIN_NAME = "CardsGovernor";
const SIGNING_DOMAIN_VERSION = "1";


class OptionsSigner {
  contract: CardsGovernor;
  signer: SignerWithAddress;
  _domain: object | null;
  chain_id: number
  /**
   * Create a new LazyMinter targeting a deployed instance of the LazyNFT contract.
   *
   * @param {Object} options
   * @param {ethers.Contract} contract an ethers Contract that's wired up to the deployed contract
   * @param {ethers.Signer} signer a Signer whose account is authorized to mint NFTs on the deployed contract
   */
  constructor(contract: CardsGovernor, signer: SignerWithAddress, chain_id: number) {
    this.contract = contract;
    this.signer = signer;
    this._domain = null;
    this.chain_id = chain_id;
  }

  async signOption(
    option: string
  ): Promise<string> {
    const domain = await this._signingDomain();
    const value = {
      option: option
    }
    const types = {
      CardOption: [
        { name: 'option', type: 'string' }
      ],
    };
    // this.signer._signTypedData
    const signature = await this.signer._signTypedData(domain, types, value);
    return signature;
  }

  /**
   * @private
   * @returns {object} the EIP-721 signing domain, tied to the chainId of the signer
   */
  async _signingDomain() {
    if (this._domain != null) {
      return this._domain;
    }
    this._domain = {
      name: SIGNING_DOMAIN_NAME,
      version: SIGNING_DOMAIN_VERSION,
      verifyingContract: this.contract.address,
      chainId: this.chain_id,
    };
    return this._domain;
  }
}

export default OptionsSigner;
