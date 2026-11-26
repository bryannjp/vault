function required(name: string): string {
  const value = import.meta.env[name];
  if (!value) throw new Error(`Missing env variable ${name} (see frontend/.env.example)`);
  return value;
}

export const RPC_URL = required("VITE_RPC_URL");
export const CHAIN_ID = Number(required("VITE_CHAIN_ID"));
export const TOKEN_ADDRESS = required("VITE_TOKEN_ADDRESS");
export const VAULT_ADDRESS = required("VITE_VAULT_ADDRESS");

// Block the vault was deployed in. Event searches start here instead of block 0
// (public RPCs limit how many blocks one query may cover). Optional: defaults to 0, fine on Anvil.
export const DEPLOY_BLOCK = Number(import.meta.env.VITE_DEPLOY_BLOCK ?? 0);