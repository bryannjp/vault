import { Interface, isError } from "ethers";
import vaultAbi from "../abi/SimpleVault.json";
import tokenAbi from "../abi/MockERC20.json";

// Both ABIs together know every custom error our contracts can revert with.
const interfaces = [new Interface(vaultAbi), new Interface(tokenAbi)];

// Turns any error from ethers or the wallet into a sentence a user understands.
// `amount` formats a raw token amount (bigint) for display.
export function describeError(error: unknown, amount: (value: bigint) => string): string {
  if (isError(error, "ACTION_REJECTED")) return "You rejected the transaction in your wallet.";

  const decoded = decodeRevert(error);
  if (decoded) {
    const [a, b, c] = decoded.args; // the error's parameters, in order
    switch (decoded.name) {
      case "EnforcedPause":
        return "The vault is paused.";
      case "OwnableUnauthorizedAccount":
        return "Only the vault owner can do this.";
      case "ERC20InsufficientBalance":
        // Can come from the token (not enough mUSD) or the vault (not enough shares).
        return "Insufficient balance for this amount.";
      case "ERC20InsufficientAllowance":
        return "The vault isn't approved to spend that many tokens. Approve first.";
      case "Vault__ExceededMaxDeposit":
        return `Deposit too large: the vault only has room for ${amount(c)} more.`;
      case "Vault__ZeroAssets":
        return "The amount is too small (it's worth 0 tokens).";
      case "Vault__RequestPending":
        return "You already have a pending withdrawal. Claim it before requesting another.";
      case "Vault__NoRequest":
        return "You have no pending withdrawal to claim.";
      case "Vault__NotClaimableYet":
        return `Not claimable yet. Try again after ${new Date(Number(a) * 1000).toLocaleString()}.`;
      case "Vault__ExceedsRequest":
        return `You can claim at most ${amount(b)}.`;
      case "Vault__DailyLimitExceeded":
        return `Daily claim limit reached: only ${amount(b)} can be claimed today.`;
      default:
        return `Transaction reverted: ${decoded.name}`;
    }
  }

  const e = error as { shortMessage?: string; message?: string };
  return e.shortMessage ?? e.message ?? String(error);
}

// A reverted call carries the custom error's encoded bytes. ethers decodes them when it can
// (error.revert); otherwise we decode the raw bytes (error.data) with our ABIs ourselves.
function decodeRevert(error: unknown): { name: string; args: readonly bigint[] } | null {
  if (!isError(error, "CALL_EXCEPTION")) return null;
  if (error.revert) return { name: error.revert.name, args: error.revert.args as bigint[] };
  if (!error.data) return null;
  for (const iface of interfaces) {
    const parsed = iface.parseError(error.data);
    if (parsed) return { name: parsed.name, args: parsed.args as unknown as bigint[] };
  }
  return null;
}