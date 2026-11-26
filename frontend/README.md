## Summary
Adds a browser frontend for SimpleVault, plus tooling to run and check the whole stack.

## What's included
- **Frontend** (`frontend/`): React + TypeScript + Vite
  - Wallet connection and network switching (MetaMask, EIP-1193)
  - Vault stats and user position, refreshed on every new block
  - Faucet, approve & deposit, request withdrawal, claim (countdown, daily limit)
  - Owner panel: pause, deposit cap, daily limit
  - Activity feed from on-chain events (web3.js, lazy-loaded)
  - Custom-error decoding into readable messages
  - Anvil-only dev tools to skip time
- **Deploy script** (`script/Deploy.s.sol`): test token + vault
- **`script/dev.sh`**: starts Anvil (state kept between runs), deploys if needed, exports ABIs, starts the frontend
- **Docker**: `docker compose up --build` runs Anvil, a deploy job and the frontend (nginx)
- **CI**: new frontend and Docker jobs; the Foundry job also checks that the ABIs are up to date

## How to test
    ./script/dev.sh        # or: docker compose up --build

1. Add the Anvil network to MetaMask (`http://127.0.0.1:8545`, chain ID 31337) and import an Anvil test account
2. Faucet → deposit → request withdrawal → "Skip withdrawal delay" → claim
3. With account #0 (owner): pause, then set a deposit cap and a daily limit

## Notes
- Contracts unchanged
- All CI jobs pass
