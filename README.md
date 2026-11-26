# SimpleVault

An ERC-4626 tokenized vault written from scratch in Solidity, tested against OpenZeppelin's implementation.

## What it does
Deposit an ERC-20 asset, receive shares; shares grow in value as the vault earns yield.

v2 adds:
- Deposit cap: limits the total assets the vault accepts (`type(uint256).max` = no cap)
- Pause: the owner can stop deposits and withdrawals in an emergency
- Two-step ownership (`Ownable2Step`); `renounceOwnership` is disabled

v3 adds:
- Withdrawals in two steps: `requestRedeem` burns shares and fixes the payout, `claim` pays out after a delay (max 30 days)
- Daily claim limit for the whole vault (resets at 00:00 UTC); big requests can be claimed in parts over several days
- `withdraw`/`redeem` are switched off (`maxWithdraw`/`maxRedeem` return 0)

## Design decisions
- Rounding always favours the vault (spec rule)
- Virtual share/asset (+1) to make the inflation attack unprofitable
- Assets pulled in before shares are minted; a request is settled before assets are paid out (no double claim)
- Limits enforced through the `max…` functions, which return 0 while paused (spec rule)
- Renounce disabled: renouncing while paused would lock funds forever
- Trust assumption: the owner can pause withdrawals
- Payout fixed at request time, so yield during the delay goes to remaining holders (no free option)
- Requested assets are reserved (`totalPending`) and excluded from `totalAssets`, so requests never lower the share price
- Delay is immutable: changing it would affect people already waiting
- Limitation: a fixed daily window allows up to ~2x the limit around midnight UTC
- Inspired by ERC-7540 (async vaults) but not compliant with it

## Testing
- 69 unit/fuzz tests, including a differential test against OpenZeppelin's ERC4626 (deposit and mint paths)
- 10 invariants (accounting, solvency, supply, pending = sum of requests, no early claims, daily limit, nothing moves while paused, cap never exceeded, share price never drops on exit)
- Mutation testing: 92/94 mutants killed (the 2 survivors behave identically)
- 100% line and branch coverage

## Frontend
A React + TypeScript app (Vite) to use the vault from the browser.

![Screenshot](.github/screenshot.png)

- Connect MetaMask (EIP-1193), detect the wrong network and switch to the right one
- Vault stats and your position, refreshed after every new block
- Faucet, approve & deposit, request withdrawal, claim with a countdown and daily-limit handling
- Owner panel: pause/unpause, deposit cap, daily limit
- Activity feed built from the vault's on-chain events
- Custom errors (e.g. `Vault__DailyLimitExceeded`) decoded into readable messages
- Dev tools on Anvil to skip time (withdrawal delay, next UTC day)

ethers.js handles the wallet, reads and transactions; web3.js (`web3-eth-contract`) reads the event history.

### Frontend design decisions
- Reads go straight to the RPC node, writes go through the wallet, so stats work without a wallet
- The UI checks the contract's limits before sending, so users don't pay gas for a transaction that would fail; the contract still enforces them
- Approves the exact deposit amount, not an unlimited allowance
- The claim countdown uses chain time (`block.timestamp`), not the browser clock
- Refreshes by polling the block number: ethers' `provider.on("block")` stopped firing after React re-subscribed
- web3.js is only downloaded when the activity feed is opened, and ethers is split into its own file

## Run it
Contracts:

    forge install
    forge test

Full stack locally (needs Foundry, Node 22 and jq). Starts Anvil, deploys, and starts the frontend on http://localhost:5173:

    ./script/dev.sh

Full stack with Docker only. Opens on http://localhost:8080:

    docker compose up --build

In MetaMask, add the network `http://127.0.0.1:8545` (chain ID 31337) and import an Anvil test account. If you reset the chain (by deleting `.anvil/` or running `docker compose down -v`), also reset MetaMask's activity and nonce data.

## CI
- **Foundry:** format, build, tests, and a check that the frontend's ABIs match the contracts
- **Frontend:** `npm audit`, lint, type-check, build
- **Docker:** builds the images, starts the stack, and smoke-tests it

## AI usage
Code written by me; Claude used as a reviewer and to write tests. 
Frontend and tooling built step by step with Claude. Every claim verified by compiling and running. Every Part can be explained
