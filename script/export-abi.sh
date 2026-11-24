#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

forge build
mkdir -p frontend/src/abi
for c in SimpleVault MockERC20; do
  jq '.abi' "out/$c.sol/$c.json" > "frontend/src/abi/$c.json"
  echo "exported $c"
done