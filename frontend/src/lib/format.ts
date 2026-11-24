import { formatUnits, MaxUint256 } from "ethers";

// (1234567890n, 6, "mUSD") -> "1,234.5678 mUSD"
// type(uint256).max is the contract's way of saying "no limit".
export function formatAmount(amount: bigint, decimals: number, symbol: string, maxFractionDigits = 4): string {
  if (amount === MaxUint256) return "No limit";
  const [whole, fraction = ""] = formatUnits(amount, decimals).split(".");
  const shownFraction = fraction.slice(0, maxFractionDigits).replace(/0+$/, "");
  const wholeWithCommas = BigInt(whole).toLocaleString("en-US");
  const number = shownFraction ? `${wholeWithCommas}.${shownFraction}` : wholeWithCommas;
  return `${number} ${symbol}`;
}

// 90061 -> "1d 1h 1m 1s"
export function formatDuration(totalSeconds: number): string {
  const parts = [
    [Math.floor(totalSeconds / 86400), "d"],
    [Math.floor((totalSeconds % 86400) / 3600), "h"],
    [Math.floor((totalSeconds % 3600) / 60), "m"],
    [totalSeconds % 60, "s"],
  ] as const;
  const shown = parts.filter(([value]) => value > 0).map(([value, unit]) => `${value}${unit}`);
  return shown.length ? shown.join(" ") : "0s";
}

export function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}