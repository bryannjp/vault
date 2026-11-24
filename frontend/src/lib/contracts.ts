import { Contract, JsonRpcProvider } from "ethers";
import vaultAbi from "../abi/SimpleVault.json";
import tokenAbi from "../abi/MockERC20.json";
import { CHAIN_ID, RPC_URL, TOKEN_ADDRESS, VAULT_ADDRESS } from "./config";

// Read-only connection straight to the node. Works without a wallet.
// staticNetwork: we know the chain, so ethers doesn't need to ask for it on every call.
export const readProvider = new JsonRpcProvider(RPC_URL, CHAIN_ID, { staticNetwork: true });

export const vaultRead = new Contract(VAULT_ADDRESS, vaultAbi, readProvider);
export const tokenRead = new Contract(TOKEN_ADDRESS, tokenAbi, readProvider);