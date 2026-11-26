import { useState } from "react";
import { formatUnits, type JsonRpcSigner } from "ethers";
import type { UserData, VaultData } from "../hooks/useVaultData";
import { useNow } from "../hooks/useNow";
import { useTx } from "../hooks/useTx";
import { vaultWrite } from "../lib/contracts";
import { formatAmount, formatDuration, parseAmount } from "../lib/format";
import { TxStatus } from "./TxStatus";

type Props = {
  vault: VaultData;
  user: UserData;
  account: string;
  getSigner: () => Promise<JsonRpcSigner>;
};

export function Claim({ vault, user, account, getSigner }: Props) {
  const assets = (v: bigint) => formatAmount(v, vault.decimals, vault.assetSymbol);
  const { run, busy, status, error } = useTx(assets);
  const [input, setInput] = useState("");

  // The contract checks block.timestamp, so count down in chain time: the computer's ticking clock
  // plus how far the chain is ahead of it (on Anvil, after skipping time forward).
  const now = useNow() + vault.clockOffset;
  const secondsLeft = user.claimableAt - now;

  // You can claim your whole request, unless the vault's daily limit has less room left today.
  const claimableToday = user.pendingAssets < vault.remainingToday ? user.pendingAssets : vault.remainingToday;
  const value = parseAmount(input, vault.decimals);

  function problem(): string | null {
    if (vault.paused) return "The vault is paused.";
    if (secondsLeft > 0) return `Claimable in ${formatDuration(secondsLeft)}.`;
    if (vault.remainingToday === 0n) return "The vault's daily claim limit is used up. Try again tomorrow (00:00 UTC).";
    if (input === "") return null;
    if (value === null) return "Enter a valid amount.";
    if (value === 0n) return "Enter an amount above 0.";
    if (value > user.pendingAssets) return `You can claim at most ${assets(user.pendingAssets)}.`;
    if (value > vault.remainingToday)
      return `Daily limit: only ${assets(vault.remainingToday)} can be claimed today. Claim the rest tomorrow.`;
    return null;
  }
  const blocked = problem();

  const claim = () => {
    if (value === null) return;
    run(async (step) => {
      const vaultContract = vaultWrite(await getSigner());
      await step("Claim", () => vaultContract.claim(value, account));
      setInput("");
    }, `Claimed ${assets(value)}`);
  };

  return (
    <section>
      <h2>Claim withdrawal</h2>
      <p>
        Pending: {assets(user.pendingAssets)}. Claimable today: {assets(claimableToday)}.
      </p>
      <input
        value={input}
        onChange={(e) => setInput(e.target.value)}
        placeholder={`Amount in ${vault.assetSymbol}`}
        inputMode="decimal"
        disabled={busy}
      />
      <button onClick={() => setInput(formatUnits(claimableToday, vault.decimals))} disabled={busy}>
        Max
      </button>
      <button onClick={claim} disabled={busy || value === null || value === 0n || blocked !== null}>
        Claim
      </button>
      {blocked && <p style={{ color: "crimson" }}>{blocked}</p>}
      <TxStatus status={status} error={error} />
    </section>
  );
}