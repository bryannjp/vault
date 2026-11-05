# SimpleVault

An ERC-4626 tokenized vault written from scratch in Solidity, tested against OpenZeppelin's implementation.

## What it does
Deposit an ERC-20 asset, receive shares; shares grow in value as the vault earns yield.

v2 adds:
- Deposit cap: limits the total assets the vault accepts (`type(uint256).max` = no cap)
- Pause: the owner can stop deposits and withdrawals in an emergency
- Two-step ownership (`Ownable2Step`); `renounceOwnership` is disabled

## Design decisions
- Rounding always favours the vault (spec rule)
- Virtual share/asset (+1) to make the inflation attack unprofitable
- Assets pulled in before shares are minted; shares burned before assets are paid out
- Limits enforced through the `max…` functions, which return 0 while paused (spec rule)
- Renounce disabled: renouncing while paused would lock funds forever
- Trust assumption: the owner can pause withdrawals

## Testing
- 57 unit/fuzz tests, including a differential test against OpenZeppelin's ERC4626
- 7 invariants (solvency, accounting, supply, nothing moves while paused, cap never exceeded)
- Mutation testing: 82/83 mutants killed (the survivor behaves identically)
- 100% line and branch coverage

## Run it
    forge install
    forge test

## AI usage
Code written by me; Claude used as a reviewer and to write tests. Every claim verified by compiling and running.