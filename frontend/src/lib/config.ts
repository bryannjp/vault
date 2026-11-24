function required(name: string): string {
  const value = import.meta.env[name];
  if (!value) throw new Error(`Missing env variable ${name} (see frontend/.env.example)`);
  return value;
}

export const RPC_URL = required("VITE_RPC_URL");
export const CHAIN_ID = Number(required("VITE_CHAIN_ID"));
export const TOKEN_ADDRESS = required("VITE_TOKEN_ADDRESS");
export const VAULT_ADDRESS = required("VITE_VAULT_ADDRESS");