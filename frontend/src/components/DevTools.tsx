import { useState } from "react";
import type { VaultData } from "../hooks/useVaultData";
import { readProvider } from "../lib/contracts";
import { formatDuration } from "../lib/format";

const DAY = 86400;

// The chain's current time. Anvil only makes a block when something happens, so the latest block
// can be old: mine an empty block first, its timestamp is "now" on the chain.
async function chainNow(): Promise<number> {
  await readProvider.send("evm_mine", []);
  const block = await readProvider.getBlock("latest");
  return block!.timestamp;
}

// Moves the chain's clock to `timestamp` and mines a block there, so contracts see the new time.
// These are Anvil-only RPC methods: they don't exist on real networks.
async function jumpTo(timestamp: number) {
  await readProvider.send("evm_setNextBlockTimestamp", [timestamp]);
  await readProvider.send("evm_mine", []);
}

// Only rendered on Anvil (chain 31337). Talks to the node directly, no wallet needed.
export function DevTools({ vault }: { vault: VaultData }) {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const skip = async (label: string, target: (now: number) => number) => {
    setBusy(true);
    try {
      const to = target(await chainNow());
      await jumpTo(to);
      setMessage(`${label}: chain time is now ${new Date(to * 1000).toUTCString()}`);
    } catch (e) {
      setMessage(`Failed: ${(e as Error).message}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <section>
      <h2>Dev tools (Anvil only)</h2>
      <p>Chain time (latest block): {new Date(vault.blockTimestamp * 1000).toUTCString()}</p>
      <button
        onClick={() => skip("Skipped the withdrawal delay", (now) => now + vault.withdrawalDelay + 1)}
        disabled={busy}
      >
        Skip {formatDuration(vault.withdrawalDelay)} (withdrawal delay)
      </button>{" "}
      <button
        onClick={() => skip("Skipped to the next day", (now) => (Math.floor(now / DAY) + 1) * DAY)}
        disabled={busy}
      >
        Skip to next day (00:00 UTC)
      </button>
      {message && <p>{message}</p>}
    </section>
  );
}