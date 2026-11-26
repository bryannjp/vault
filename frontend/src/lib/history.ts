import { Contract } from "web3-eth-contract";
import type { ContractAbi, EventLog } from "web3-types";
import vaultAbi from "../abi/SimpleVault.json";
import { DEPLOY_BLOCK, RPC_URL, VAULT_ADDRESS } from "./config";

export type Activity = {
  event: "Deposit" | "WithdrawalRequested" | "WithdrawalClaimed";
  account: string;
  assets: bigint;
  blockNumber: bigint;
  logIndex: bigint;
  txHash: string;
};

const SHOWN_EVENTS = ["Deposit", "WithdrawalRequested", "WithdrawalClaimed"];

// Reads the vault's past events from the chain with web3.js.
// Events are logs stored with each transaction's receipt: cheap for the contract to emit, and easy to search.
export async function fetchActivity(limit = 20): Promise<Activity[]> {
  const vault = new Contract(vaultAbi as ContractAbi, VAULT_ADDRESS, { provider: RPC_URL });

  // One eth_getLogs query for every event the vault emitted, decoded with the ABI.
  const logs = await vault.getPastEvents("allEvents", { fromBlock: DEPLOY_BLOCK, toBlock: "latest" });

  const items = logs
    .filter((log): log is EventLog => typeof log !== "string" && SHOWN_EVENTS.includes(log.event))
    .map((log) => ({
      event: log.event as Activity["event"],
      account: String(log.returnValues.owner), // all three events have an `owner` field: the user it's about
      assets: BigInt(log.returnValues.assets as bigint),
      blockNumber: BigInt(log.blockNumber ?? 0),
      logIndex: BigInt(log.logIndex ?? 0),
      txHash: String(log.transactionHash),
    }));

  // Newest first: by block, then by position inside the block.
  items.sort((a, b) =>
    a.blockNumber !== b.blockNumber ? Number(b.blockNumber - a.blockNumber) : Number(b.logIndex - a.logIndex),
  );
  return items.slice(0, limit);
}