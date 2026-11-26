import { parseUnits, type JsonRpcSigner } from "ethers";
import type { VaultData } from "../hooks/useVaultData";
import { useTx } from "../hooks/useTx";
import { tokenWrite } from "../lib/contracts";
import { formatAmount } from "../lib/format";
import { TxStatus } from "./TxStatus";

const FAUCET_AMOUNT = "1000";

type Props = {
  vault: VaultData;
  account: string;
  getSigner: () => Promise<JsonRpcSigner>;
};

export function Faucet({ vault, account, getSigner }: Props) {
  const { run, busy, status, error } = useTx((v) => formatAmount(v, vault.decimals, vault.assetSymbol));

  const mint = () =>
    run(async (step) => {
      const token = tokenWrite(await getSigner());
      const value = parseUnits(FAUCET_AMOUNT, vault.decimals); // "1000" -> 1000000000n (6 decimals)
      await step("Mint", () => token.mint(account, value));
    }, `Received ${FAUCET_AMOUNT} ${vault.assetSymbol}`);

  return (
    <section>
      <h2>Faucet</h2>
      <button onClick={mint} disabled={busy}>
        Get {FAUCET_AMOUNT} test {vault.assetSymbol}
      </button>
      <TxStatus status={status} error={error} />
    </section>
  );
}