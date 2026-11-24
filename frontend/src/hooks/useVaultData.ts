import { useEffect, useState } from "react";
import { readProvider, tokenRead, vaultRead } from "../lib/contracts";

const POLL_INTERVAL_MS = 4000;

export type VaultData = {
  decimals: number;
  assetSymbol: string;
  shareSymbol: string;
  paused: boolean;
  totalAssets: bigint;
  totalSupply: bigint;
  sharePrice: bigint; // assets you get for 1 whole share
  depositCap: bigint;
  maxDeposit: bigint;
  totalPending: bigint;
  dailyLimit: bigint;
  remainingToday: bigint;
  withdrawalDelay: number; // seconds
  owner: string;
};

export type UserData = {
  tokenBalance: bigint;
  shares: bigint;
  sharesValue: bigint; // what the shares are worth in assets right now
  pendingAssets: bigint; // requested but not yet claimed
  claimableAt: number; // unix timestamp (seconds)
};

async function fetchVault(): Promise<VaultData> {
  const decimals = Number(await vaultRead.decimals());
  const oneShare = 10n ** BigInt(decimals);

  // All calls in parallel: one round trip instead of twelve.
  const [
    assetSymbol, shareSymbol, paused, totalAssets, totalSupply, sharePrice,
    depositCap, maxDeposit, totalPending, dailyLimit, remainingToday, withdrawalDelay, owner,
  ] = await Promise.all([
    tokenRead.symbol(),
    vaultRead.symbol(),
    vaultRead.paused(),
    vaultRead.totalAssets(),
    vaultRead.totalSupply(),
    vaultRead.convertToAssets(oneShare),
    vaultRead.depositCap(),
    vaultRead.maxDeposit("0x0000000000000000000000000000000000000000"), // same for every address
    vaultRead.totalPending(),
    vaultRead.dailyLimit(),
    vaultRead.remainingToday(),
    vaultRead.withdrawalDelay(),
    vaultRead.owner(),
  ]);

  return {
    decimals, assetSymbol, shareSymbol, paused, totalAssets, totalSupply, sharePrice,
    depositCap, maxDeposit, totalPending, dailyLimit, remainingToday,
    withdrawalDelay: Number(withdrawalDelay),
    owner,
  };
}

async function fetchUser(account: string): Promise<UserData> {
  const [tokenBalance, shares, request] = await Promise.all([
    tokenRead.balanceOf(account),
    vaultRead.balanceOf(account),
    vaultRead.requests(account), // public mapping getter -> (assets, claimableAt)
  ]);
  const sharesValue: bigint = await vaultRead.convertToAssets(shares);

  return {
    tokenBalance,
    shares,
    sharesValue,
    pendingAssets: request.assets,
    claimableAt: Number(request.claimableAt),
  };
}

export function useVaultData(account: string | null) {
  const [vault, setVault] = useState<VaultData | null>(null);
  const [user, setUser] = useState<UserData | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Set to true when the account changes or the component unmounts,
    // so a slow, outdated request can't overwrite newer data.
    let cancelled = false;

    const load = () => {
      Promise.all([fetchVault(), account ? fetchUser(account) : null])
        .then(([v, u]) => {
          if (cancelled) return;
          setVault(v);
          setUser(u);
          setError(null);
        })
        .catch((e) => {
          if (!cancelled) setError(e.shortMessage ?? e.message);
        });
    };

    // Every few seconds, ask the node for the latest block number and reload only if it changed
    // (a new block means a transaction happened). We poll ourselves instead of using ethers'
    // provider.on("block"), which stops firing after the listener is removed and re-added.
    let lastBlock = -1;
    const poll = () => {
      readProvider
        .getBlockNumber()
        .then((block) => {
          if (cancelled || block === lastBlock) return;
          lastBlock = block;
          load();
        })
        .catch((e) => {
          if (!cancelled) setError(e.shortMessage ?? e.message);
        });
    };

    poll();
    const timer = setInterval(poll, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [account]);

  return { vault, user, error };
}