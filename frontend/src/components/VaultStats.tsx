import type { VaultData } from "../hooks/useVaultData";
import { formatAmount, formatDuration, shortAddress } from "../lib/format";

export function VaultStats({ vault }: { vault: VaultData }) {
  const assets = (value: bigint) => formatAmount(value, vault.decimals, vault.assetSymbol);

  return (
    <section>
      <h2>Vault</h2>
      <table>
        <tbody>
          <Row label="Status" value={vault.paused ? "Paused" : "Active"} />
          <Row label="Total assets" value={assets(vault.totalAssets)} />
          <Row label="Total shares" value={formatAmount(vault.totalSupply, vault.decimals, vault.shareSymbol)} />
          <Row label="Share price" value={`1 ${vault.shareSymbol} = ${assets(vault.sharePrice)}`} />
          <Row label="Deposit cap" value={assets(vault.depositCap)} />
          <Row label="Room left to deposit" value={assets(vault.maxDeposit)} />
          <Row label="Reserved for withdrawals" value={assets(vault.totalPending)} />
          <Row label="Daily claim limit" value={assets(vault.dailyLimit)} />
          <Row label="Left to claim today" value={assets(vault.remainingToday)} />
          <Row label="Withdrawal delay" value={formatDuration(vault.withdrawalDelay)} />
          <Row label="Owner" value={shortAddress(vault.owner)} />
        </tbody>
      </table>
    </section>
  );
}

export function Row({ label, value }: { label: string; value: string }) {
  return (
    <tr>
      <th style={{ textAlign: "left", paddingRight: "1rem" }}>{label}</th>
      <td>{value}</td>
    </tr>
  );
}