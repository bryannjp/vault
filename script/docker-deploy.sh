#!/bin/sh
# Runs inside the "deploy" container (docker-compose.yml). POSIX sh: the image may not have bash.
# Deploys the contracts unless they're already on the chain (the chain is kept between runs).
set -eu

if [ "$(cast code "$VAULT_ADDRESS" --rpc-url "$RPC_URL")" != "0x" ]; then
  echo "Contracts already deployed (vault $VAULT_ADDRESS)."
  exit 0
fi

echo "Deploying contracts..."
forge script script/Deploy.s.sol --rpc-url "$RPC_URL" --broadcast --quiet

# The frontend was built with the expected addresses, so make sure that's where the vault landed.
if [ "$(cast code "$VAULT_ADDRESS" --rpc-url "$RPC_URL")" = "0x" ]; then
  echo "The vault was not deployed at $VAULT_ADDRESS. Reset the chain: docker compose down -v" >&2
  exit 1
fi
echo "Deployed. Vault: $VAULT_ADDRESS"