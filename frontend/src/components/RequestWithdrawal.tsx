import { useEffect, useState } from "react";
import { formatUnits, type JsonRpcSigner } from "ethers";
import type { UserData, VaultData } from "../hooks/useVaultData";
import { useTx } from "../hooks/useTx";
import { vaultRead, vaultWrite } from "../lib/contracts";
import { formatAmount, formatDuration, parseAmount } from "../lib/format";
import { TxStatus } from "./TxStatus";

type Props = {
  vault: VaultData;
  user: UserData;
  getSigner: () => Promise<JsonRpcSigner>;
};

export function RequestWithdrawal({ vault, user, getSigner }: Props) {
  const assets = (v: bigint) => formatAmount(v, vault.decimals, vault.assetSymbol);
  const shares = (v: bigint) => formatAmount(v, vault.decimals, vault.shareSymbol);
  const { run, busy, status, error } = useTx(assets);
  const [input, setInput] = useState("");
  const [preview, setPreview] = useState<{ input: string; assets: bigint } | null>(null);

  const value = parseAmount(input, vault.decimals); // shares have the same decimals as the asset
  const previewAssets = preview?.input === input ? preview.assets : null;

  // Ask the vault how many tokens these shares are worth right now. That amount is fixed at request time.
  useEffect(() => {
    if (value === null || value === 0n) return;
    let cancelled = false;
    vaultRead
      .previewRedeem(value)
      .then((result: bigint) => {
        if (!cancelled) setPreview({ input, assets: result });
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [input, value]);

  function problem(): string | null {
    if (vault.paused) return "The vault is paused.";
    if (user.pendingAssets > 0n) return "You already have a pending withdrawal. Claim it before requesting another.";
    if (input === "") return null;
    if (value === null) return "Enter a valid amount.";
    if (value === 0n) return "Enter an amount above 0.";
    if (value > user.shares) return `You only have ${shares(user.shares)}.`;
    if (previewAssets === 0n) return "The amount is too small (it's worth 0 tokens).";
    return null;
  }
  const blocked = problem();

  const request = () => {
    if (value === null) return;
    run(async (step) => {
      const vaultContract = vaultWrite(await getSigner());
      await step("Request withdrawal", () => vaultContract.requestRedeem(value));
      setInput("");
    }, `Withdrawal requested. You can claim it in ${formatDuration(vault.withdrawalDelay)}.`);
  };

  return (
    <section>
      <h2>Request withdrawal</h2>
      <input
        value={input}
        onChange={(e) => setInput(e.target.value)}
        placeholder={`Amount in ${vault.shareSymbol}`}
        inputMode="decimal"
        disabled={busy}
      />
      <button onClick={() => setInput(formatUnits(user.shares, vault.decimals))} disabled={busy}>
        Max
      </button>
      <button onClick={request} disabled={busy || value === null || value === 0n || blocked !== null}>
        Request withdrawal
      </button>
      {blocked && <p style={{ color: "crimson" }}>{blocked}</p>}
      {!blocked && value !== null && previewAssets !== null && (
        <p>
          You will get {assets(previewAssets)}, claimable after {formatDuration(vault.withdrawalDelay)}.
        </p>
      )}
      <TxStatus status={status} error={error} />
    </section>
  );
}