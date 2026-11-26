import { useState } from "react";
import { MaxUint256, type Contract, type ContractTransactionResponse, type JsonRpcSigner } from "ethers";
import type { VaultData } from "../hooks/useVaultData";
import { useTx } from "../hooks/useTx";
import { vaultWrite } from "../lib/contracts";
import { formatAmount, parseAmount } from "../lib/format";
import { TxStatus } from "./TxStatus";

type Props = {
  vault: VaultData;
  getSigner: () => Promise<JsonRpcSigner>;
};

// Only shown to the owner. Hiding it is just for convenience: the contract's onlyOwner is what actually protects these functions.
export function OwnerPanel({ vault, getSigner }: Props) {
  const assets = (v: bigint) => formatAmount(v, vault.decimals, vault.assetSymbol);
  const { run, busy, status, error } = useTx(assets);

  // Sends one owner transaction to the vault.
  const send = (label: string, call: (v: Contract) => Promise<ContractTransactionResponse>, doneMessage: string) =>
    run(async (step) => {
      const vaultContract = vaultWrite(await getSigner());
      await step(label, () => call(vaultContract));
    }, doneMessage);

  const togglePause = () =>
    vault.paused
      ? send("Unpause", (v) => v.unpause(), "Vault unpaused")
      : send("Pause", (v) => v.pause(), "Vault paused");

  return (
    <section>
      <h2>Owner panel</h2>
      <p>
        Vault is <strong>{vault.paused ? "paused" : "active"}</strong>.{" "}
        <button onClick={togglePause} disabled={busy}>
          {vault.paused ? "Unpause" : "Pause"}
        </button>
      </p>
      <LimitSetting
        label="Deposit cap"
        current={vault.depositCap}
        vault={vault}
        busy={busy}
        onSave={(value) => send("Set deposit cap", (v) => v.setDepositCap(value), `Deposit cap set to ${assets(value)}`)}
      />
      <LimitSetting
        label="Daily claim limit"
        current={vault.dailyLimit}
        vault={vault}
        busy={busy}
        onSave={(value) => send("Set daily limit", (v) => v.setDailyLimit(value), `Daily limit set to ${assets(value)}`)}
      />
      <TxStatus status={status} error={error} />
    </section>
  );
}

type LimitProps = {
  label: string;
  current: bigint;
  vault: VaultData;
  busy: boolean;
  onSave: (value: bigint) => void;
};

// One "current value + new value + Set / Remove limit" row. The contract uses type(uint256).max for "no limit".
function LimitSetting({ label, current, vault, busy, onSave }: LimitProps) {
  const [input, setInput] = useState("");
  const value = parseAmount(input, vault.decimals);

  return (
    <p>
      {label}: <strong>{formatAmount(current, vault.decimals, vault.assetSymbol)}</strong>
      <br />
      <input
        value={input}
        onChange={(e) => setInput(e.target.value)}
        placeholder={`New ${label.toLowerCase()} in ${vault.assetSymbol}`}
        inputMode="decimal"
        disabled={busy}
      />
      <button onClick={() => value !== null && onSave(value)} disabled={busy || value === null}>
        Set
      </button>
      <button onClick={() => onSave(MaxUint256)} disabled={busy || current === MaxUint256}>
        Remove limit
      </button>
    </p>
  );
}