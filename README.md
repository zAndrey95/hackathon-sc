# Cards Against Humanity Smart Contracts

## Smart Contracts Overview

- **CardsAgainstHumanity.sol** - Implements the game logic and state transitions for the Cards Against Humanity game.
- **Card.sol** - Its custom collection of cards text for answers and questions.
- **CardsGovernor** - It's a contract that allows users to propose and vote on changes to the game's card collection(answers and questions). One win in game equals one vote. Users can propose new cards, and the community can vote on them. If a proposal is successful, the new card is added to the game's collections.

---

## CardsAgainstHumanity Smart Contract

The **CardsAgainstHumanity** smart contract facilitates the game "Cards Against Humanity" on the Ethereum blockchain. This guide provides a detailed overview of the game process, interactions, and emphasizes the integration of real randomness using an external entropy provider.

### Game Flow

#### Joining the Game:

- Users invoke `joinGame` with commitments, automatically initiating a random number request.

#### Receiving Cards:

- After making a random number request, players receive their cards using `playerReceiveCards`.
- Once all players complete this step, three players and one judge are randomly selected.

#### Submitting Answers:

- The three selected players submit their answers by calling `playersSendSelected`.

#### Winner Selection:

- The judge selects a winning answer, and the player who submitted that answer gains a point.
- The game status transitions to the "WINNER_SELECTED" state, and the active game is removed from the set of active games.

#### Game Cancellation (Owner Only):

- The owner can cancel a game if necessary using the `cancelGame` function. This action updates the game status and removes the game from the set of active games.

---

## CardsGovernor Smart Contract

The `CardsGovernor` smart contract acts as a governance mechanism for managing proposals related to new cards within a game. This guide provides an overview of key rules governing the proposal and voting processes.

### Proposal Rules

1. **Win Threshold for Proposer:**

   - To propose a new card, players must have a minimum threshold of wins (defined by `WIN_PROPOSAL_TRESHOLD` set to 5).

2. **Maximum Options for a Proposal:**

   - Each proposal is limited to a maximum of 5 options (defined by `MAX_OPTIONS_SIZE`).

3. **Voting Delay and Period:**

   - Proposals have a 0-second delay (`VOTING_DELAY`) before being eligible for votes.
   - The voting period for a proposal lasts 1 second (`VOTING_PERIOD`).

4. **Quorum and Success Thresholds:**
   - A quorum is achieved if the total votes cast surpass `QUORUM_REACHED_TRESHOLD` (set to 25).
   - Proposals are considered successful if any option receives votes exceeding `SUCCESS_PROPOSAL_TRESHOLD` (set to 15).

### Voting Rules

1. **Vote Casting:**

   - Players can cast their votes on active proposals, indicating their preferred option.

2. **Vote Weight:**

   - The weight of a player's vote is determined by their total wins, minus the votes they have already used.

3. **Vote Reasons:**
   - When casting a vote, players have the option to provide a reason for their choice.

### Proposal Lifecycle

1. **Proposal States:**

   - A proposal progresses through various states: Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed.

2. **Proposal Execution:**

   - Successful proposals that are neither canceled nor expired can be executed. The winning option is determined, and the associated game collection mints a new card.

3. **Proposal Cancellation:**
   - The proposer retains the ability to cancel a pending proposal.

---

## CAHCard Smart Contract

The CAHCard smart contract functions as a card collection for questions and answers in a game. Governed by the CardsGovernor contract, it allows minting and updating of cards, both individually and in bulk. Minting new cards is restricted to authorized minters, and the contract owner can manage the list of minters. The contract provides functions to retrieve the total supply of cards and the text of individual cards by their token IDs. Additionally, it emits events for minter management and card updates. This contract serves a crucial role in managing the content of the game by facilitating the addition and modification of cards.

---

## Technical Stack

- Solidity
- Hardhat
- JavaScript
- TypeScript
- Ethers.js
- solidity-coverage
- Mocha
- Chai

## Installation

It is recommended to install [Yarn](https://classic.yarnpkg.com) through the `npm` package manager, which comes bundled with [Node.js](https://nodejs.org) when you install it on your system. It is recommended to use a Node.js version `>= 16.0.0`.

Once you have `npm` installed, you can run the following both to install and upgrade Yarn:

```bash
npm install --global yarn
```

After having installed Yarn, simply run:

```bash
yarn install
```

## `.env` File

In the `.env` file place the private key of your wallet in the `PRIVATE_KEY` section. This allows secure access to your wallet to use with both testnet and mainnet funds during Hardhat deployments. For more information on how this works, please read the documentation of the `npm` package [`dotenv`](https://www.npmjs.com/package/dotenv).

### `.env` variables list

- **PRIVATE_KEY** - Private key of wallet that will be used for deployment.
- **PEGASUS_API_KEY** - Api key for smart contracts auto verification on blockchain explorer.

You can see an example of the `.env` file in the `.env.example` file.

### Testing

1. To run TypeScript tests:

```bash
yarn test
```

2. To run tests and view coverage :

```bash
yarn coverage
```

### Compilation

```bash
yarn compile
```

### Deployment

To deploy contracts or running sripts you need set up `.env`

- **PRIVATE_KEY** - Private key of wallet that will be used for deployment.
- **PEGASUS_API_KEY** - Api key for smart contracts auto verification on blockchain explorers.

run:

```bash
npx hardhat run --network [Network] scripts/${script_name}.ts
```

## Contract Verification

Change the contract address to your contract after the deployment has been successful. This works for both testnet and mainnet. You will need to get an API key from [etherscan](https://etherscan.io), [snowtrace](https://snowtrace.io) etc.

**Example:**

```bash
npx hardhat verify --network [network] --constructor-args [...args] <YOUR_CONTRACT_ADDRESS>
```
