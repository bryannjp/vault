import { useState } from "react";
import type { ContractTransactionResponse } from "ethers";
import { describeError } from "../lib/errors";

// Tracks one action's progress: "confirm in wallet" -> "waiting for block" -> "done" (or an error).
export function useTx(amount: (value: bigint) => string) {
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Sends one transaction and waits until it is mined.
  // `send` is a function (not a promise) so nothing happens before we've updated the status.
  async function step(label: string, send: () => Promise<ContractTransactionResponse>) {
    setStatus(`${label}: confirm in your wallet…`);
    const tx = await send();
    setStatus(`${label}: waiting for the transaction to be mined…`);
    await tx.wait();
  }

  // Runs an action made of one or more steps, and reports the result.
  async function run(action: (s: typeof step) => Promise<void>, doneMessage: string) {
    setBusy(true);
    setError(null);
    try {
      await action(step);
      setStatus(doneMessage);
    } catch (e) {
      setStatus(null);
      setError(describeError(e, amount));
    } finally {
      setBusy(false);
    }
  }

  return { run, busy, status, error };
}