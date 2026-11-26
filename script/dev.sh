#!/usr/bin/env bash
# Local development in one command:
#   1. starts Anvil (or uses one that is already running)
#   2. deploys the contracts, if they aren't on the chain yet
#   3. exports the ABIs and writes frontend/.env.local
#   4. starts the frontend
# Usage: ./script/dev.sh    (Ctrl+C stops the frontend and the Anvil it started)
set -euo pipefail
cd "$(dirname "$0")/.."

RPC_URL="http://127.0.0.1:8545"
CHAIN_ID=31337
# Anvil's default account #0. A public test key: never use it on a real network.
DEPLOYER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
STATE_DIR=".anvil"
ENV_FILE="frontend/.env.local"

for tool in anvil forge cast jq npm; do
  command -v "$tool" >/dev/null || { echo "Missing '$tool'. Install it first." >&2; exit 1; }
done

chain_is_up() { cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; }
mkdir -p "$STATE_DIR"

# 1. Anvil. The chain is saved to $STATE_DIR/state.json when Anvil stops and loaded when it starts,
#    so contracts, balances and nonces survive restarts (no MetaMask nonce resets needed).
if chain_is_up; then
  echo "Anvil is already running at $RPC_URL, using it."
else
  echo "Starting Anvil (log: $STATE_DIR/anvil.log)..."
  anvil --state "$STATE_DIR/state.json" > "$STATE_DIR/anvil.log" 2>&1 &
  ANVIL_PID=$!
  trap 'echo "Stopping Anvil (saving the chain)..."; kill "$ANVIL_PID"; wait "$ANVIL_PID" 2>/dev/null || true' EXIT
  for _ in $(seq 50); do chain_is_up && break; sleep 0.2; done
  chain_is_up || { echo "Anvil did not start. See $STATE_DIR/anvil.log" >&2; exit 1; }
fi

# 2. Contracts. Skip the deploy if the vault from .env.local already has code on this chain.
VAULT=$(grep -s '^VITE_VAULT_ADDRESS=' "$ENV_FILE" | cut -d= -f2 || true)
if [[ -n "$VAULT" && "$(cast code "$VAULT" --rpc-url "$RPC_URL")" != "0x" ]]; then
  echo "Contracts already deployed (vault $VAULT)."
else
  echo "Deploying contracts..."
  PRIVATE_KEY="$DEPLOYER_KEY" forge script script/Deploy.s.sol --rpc-url "$RPC_URL" --broadcast --quiet
  RUN="broadcast/Deploy.s.sol/$CHAIN_ID/run-latest.json"
  address_of() { cast to-check-sum-address "$(jq -r ".transactions[] | select(.contractName == \"$1\") | .contractAddress" "$RUN")"; }
  TOKEN=$(address_of MockERC20)
  VAULT=$(address_of SimpleVault)
  cat > "$ENV_FILE" <<ENV
VITE_RPC_URL=$RPC_URL
VITE_CHAIN_ID=$CHAIN_ID
VITE_TOKEN_ADDRESS=$TOKEN
VITE_VAULT_ADDRESS=$VAULT
ENV
  echo "Deployed token $TOKEN and vault $VAULT (saved in $ENV_FILE)."
fi

# 3. ABIs, so the frontend always matches the compiled contracts. Output hidden unless it fails.
./script/export-abi.sh > "$STATE_DIR/export-abi.log" 2>&1 || {
  echo "ABI export failed. See $STATE_DIR/export-abi.log" >&2
  exit 1
}

# 4. Frontend. Not with `exec`: this script must stay alive to stop Anvil when you press Ctrl+C.
[[ -d frontend/node_modules ]] || (cd frontend && npm install)
cd frontend
npm run dev