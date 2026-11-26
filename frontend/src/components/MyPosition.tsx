import type { UserData, VaultData } from "../hooks/useVaultData";
import { formatAmount } from "../lib/format";
import { Row } from "./VaultStats";

export function MyPosition({ vault, user }: { vault: VaultData; user: UserData }) {
  const assets = (value: bigint) => formatAmount(value, vault.decimals, vault.assetSymbol);
  const pending =
    user.pendingAssets > 0n
      ? `${assets(user.pendingAssets)} (claimable from ${new Date(user.claimableAt * 1000).toLocaleString()})`
      : "None";

  return (
    <section>
      <h2>My position</h2>
      <table>
        <tbody>
          <Row label="Wallet balance" value={assets(user.tokenBalance)} />
          <Row label="Vault shares" value={formatAmount(user.shares, vault.decimals, vault.shareSymbol)} />
          <Row label="Shares worth" value={assets(user.sharesValue)} />
          <Row label="Pending withdrawal" value={pending} />
        </tbody>
      </table>
    </section>
  );
}