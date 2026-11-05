# SimpleVault

An ERC-4626 tokenized vault written from scratch in Solidity, tested against OpenZeppelin's implementation.

## What it does
Deposit an ERC-20 asset, receive shares; shares grow in value as the vault earns yield.

## Design decisions
- Rounding always favours the vault (spec rule)
- Virtual share/asset (+1) to make the inflation attack unprofitable
- Assets pulled in before shares are minted; shares burned before assets are paid out

## Testing
- 41 unit/fuzz tests, including a differential test against OpenZeppelin's ERC4626
- 5 invariants (solvency, accounting, supply)
- Mutation testing: 58/60 mutants killed (the 2 survivors are unreachable in v1)
- 100% line coverage

## Run it
    forge install
    forge test

## AI usage
Code written by me; Claude used as a reviewer and to write tests. Every claim verified by compiling and running.