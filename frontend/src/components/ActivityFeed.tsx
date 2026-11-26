import { useState } from "react";
import type { VaultData } from "../hooks/useVaultData";
import type { Activity } from "../lib/history";
import { formatAmount, shortAddress } from "../lib/format";

const LABELS: Record<Activity["event"], string> = {
  Deposit: "Deposit",
  WithdrawalRequested: "Withdrawal requested",
  WithdrawalClaimed: "Withdrawal claimed",
};

export function ActivityFeed({ vault }: { vault: VaultData }) {
  const [items, setItems] = useState<Activity[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      // Dynamic import: web3.js is downloaded as a separate file only when this button is first clicked,
      // so it doesn't make the first page load slower.
      const { fetchActivity } = await import("../lib/history");
      setItems(await fetchActivity());
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <section>
      <h2>Recent activity</h2>
      <button onClick={load} disabled={loading}>
        {loading ? "Loading…" : items ? "Refresh" : "Show activity"}
      </button>
      {error && <p style={{ color: "crimson" }}>Could not load activity: {error}</p>}
      {items && items.length === 0 && <p>No activity yet.</p>}
      {items && items.length > 0 && (
        <table>
          <thead>
            <tr>
              <th>Event</th>
              <th>Account</th>
              <th>Amount</th>
              <th>Block</th>
              <th>Transaction</th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={`${item.txHash}-${item.logIndex}`}>
                <td>{LABELS[item.event]}</td>
                <td>{shortAddress(item.account)}</td>
                <td>{formatAmount(item.assets, vault.decimals, vault.assetSymbol)}</td>
                <td>{item.blockNumber.toString()}</td>
                <td>{shortAddress(item.txHash)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}