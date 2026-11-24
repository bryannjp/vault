import { useCallback, useEffect, useState } from "react";
import { BrowserProvider, type JsonRpcSigner } from "ethers";
import { CHAIN_ID, RPC_URL } from "../lib/config";

// The parts of the EIP-1193 provider (window.ethereum) that we use.
type EthereumProvider = {
  request(args: { method: string; params?: unknown[] }): Promise<unknown>;
  on(event: string, listener: (...args: unknown[]) => void): void;
  removeListener(event: string, listener: (...args: unknown[]) => void): void;
};

declare global {
  interface Window {
    ethereum?: EthereumProvider;
  }
}

const CHAIN_ID_HEX = "0x" + CHAIN_ID.toString(16);

export function useWallet() {
  const [account, setAccount] = useState<string | null>(null);
  const [chainId, setChainId] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Keep React state in sync with the wallet.
  useEffect(() => {
    const eth = window.ethereum;
    if (!eth) return;

    const onAccounts = (accounts: unknown) => setAccount((accounts as string[])[0] ?? null);
    const onChain = (id: unknown) => setChainId(Number(id));

    // Restore an existing connection on page load, without a popup.
    eth.request({ method: "eth_accounts" }).then(onAccounts);
    eth.request({ method: "eth_chainId" }).then(onChain);

    eth.on("accountsChanged", onAccounts);
    eth.on("chainChanged", onChain);
    return () => {
      eth.removeListener("accountsChanged", onAccounts);
      eth.removeListener("chainChanged", onChain);
    };
  }, []);

  // Opens the wallet popup asking the user to connect.
  const connect = useCallback(async () => {
    setError(null);
    if (!window.ethereum) return setError("No wallet found. Install MetaMask.");
    try {
      const accounts = await window.ethereum.request({ method: "eth_requestAccounts" });
      setAccount((accounts as string[])[0] ?? null);
    } catch (e) {
      setError((e as Error).message);
    }
  }, []);

  // Asks the wallet to switch to our chain, adding it first if the wallet doesn't know it.
  const switchNetwork = useCallback(async () => {
    const eth = window.ethereum;
    if (!eth) return;
    setError(null);
    try {
      await eth.request({ method: "wallet_switchEthereumChain", params: [{ chainId: CHAIN_ID_HEX }] });
    } catch (e) {
      if ((e as { code?: number }).code !== 4902) return setError((e as Error).message);
      await eth.request({
        method: "wallet_addEthereumChain",
        params: [
          {
            chainId: CHAIN_ID_HEX,
            chainName: CHAIN_ID === 31337 ? "Anvil" : `Chain ${CHAIN_ID}`,
            rpcUrls: [RPC_URL],
            nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
          },
        ],
      });
    }
  }, []);

  // A signer signs transactions with the connected account.
  // A new BrowserProvider each time avoids ethers' "network changed" error after a chain switch.
  const getSigner = useCallback(async (): Promise<JsonRpcSigner> => {
    if (!window.ethereum) throw new Error("No wallet found");
    return new BrowserProvider(window.ethereum).getSigner();
  }, []);

  return {
    hasWallet: Boolean(window.ethereum),
    account,
    chainId,
    isCorrectChain: chainId === CHAIN_ID,
    error,
    connect,
    switchNetwork,
    getSigner,
  };
}