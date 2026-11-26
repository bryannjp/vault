import { useEffect, useState } from "react";
import { formatUnits, type JsonRpcSigner } from "ethers";
import type { UserData, VaultData } from "../hooks/useVaultData";
import { useTx } from "../hooks/useTx";
import { VAULT_ADDRESS } from "../lib/config";
import { tokenWrite, vaultRead, vaultWrite } from "../lib/contracts";
import { formatAmount, parseAmount } from "../lib/format";
import { TxStatus } from "./TxStatus";

type Props = {
  vault: VaultData;
  user: UserData;
  account: string;
  getSigner: () => Promise<JsonRpcSigner>;
};

export function Deposit({ vault, user, account, getSigner }: Props) {
  const assets = (v: bigint) => formatAmount(v, vault.decimals, vault.assetSymbol);
  const { run, busy, status, error } = useTx(assets);
  const [input, setInput] = useState("");
  const [preview, setPreview] = useState<{ input: string; shares: bigint } | null>(null);

  const value = parseAmount(input, vault.decimals);
  const needsApproval = value !== null && user.allowance < value;

  // Ask the vault how many shares this amount would mint right now.
  // The result is stored with the input it belongs to, so an old answer is never shown for new input.
  useEffect(() => {
    if (value === null || value === 0n) return;
    let cancelled = false;
    vaultRead
      .previewDeposit(value)
      .then((shares: bigint) => {
        if (!cancelled) setPreview({ input, shares });
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [input, value]);

  // Check the same limits as the contract, so the user sees the problem before paying for a failed transaction.
  function problem(): string | null {
    if (vault.paused) return "The vault is paused.";
    if (input === "") return null;
    if (value === null) return "Enter a valid amount.";
    if (value === 0n) return "Enter an amount above 0.";
    if (value > user.tokenBalance) return `You only have ${assets(user.tokenBalance)}.`;
    if (value > vault.maxDeposit) return `The vault only has room for ${assets(vault.maxDeposit)} more.`;
    return null;
  }
  const blocked = problem();

  // The most you can deposit: your balance, or the room left under the cap if that's smaller.
  const setMax = () => {
    const max = user.tokenBalance < vault.maxDeposit ? user.tokenBalance : vault.maxDeposit;
    setInput(formatUnits(max, vault.decimals));
  };

  const deposit = () => {
    if (value === null) return;
    run(async (step) => {
      const signer = await getSigner();
      // ERC-20 rule: the vault can only pull tokens you've approved it to spend.
      // We approve the exact amount, not "unlimited", so a bug in the vault could never take more.
      if (needsApproval) {
        await step("Step 1 of 2: approve", () => tokenWrite(signer).approve(VAULT_ADDRESS, value));
      }
      await step(needsApproval ? "Step 2 of 2: deposit" : "Deposit", () =>
        vaultWrite(signer).deposit(value, account),
      );
      setInput("");
    }, `Deposited ${assets(value)}`);
  };

  return (
    <section>
      <h2>Deposit</h2>
      <input
        value={input}
        onChange={(e) => setInput(e.target.value)}
        placeholder={`Amount in ${vault.assetSymbol}`}
        inputMode="decimal"
        disabled={busy}
      />
      <button onClick={setMax} disabled={busy}>
        Max
      </button>
      <button onClick={deposit} disabled={busy || value === null || value === 0n || blocked !== null}>
        {needsApproval ? "Approve & deposit" : "Deposit"}
      </button>
      {blocked && <p style={{ color: "crimson" }}>{blocked}</p>}
      {!blocked && value !== null && preview?.input === input && (
        <p>
          You will receive about {formatAmount(preview.shares, vault.decimals, vault.shareSymbol)}.
        </p>
      )}
      <TxStatus status={status} error={error} />
    </section>
  );
}