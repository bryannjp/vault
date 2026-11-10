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

## Run it
    forge install
    forge test

## AI usage
Code written by me; Claude used as a reviewer and to write tests. Every claim verified by compiling and running.
