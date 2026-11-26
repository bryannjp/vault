import { useWallet } from "../hooks/useWallet";

type Props = ReturnType<typeof useWallet>;

export function ConnectWallet({ hasWallet, account, isCorrectChain, error, connect, switchNetwork }: Props) {
  if (!hasWallet) return <p>No wallet found. Install MetaMask to use this app.</p>;

  return (
    <div>
      {!account ? (
        <button onClick={connect}>Connect wallet</button>
      ) : (
        <p>
          Connected: <code>{account}</code>
        </p>
      )}
      {account && !isCorrectChain && (
        <p>
          Wrong network. <button onClick={switchNetwork}>Switch network</button>
        </p>
      )}
      {error && <p style={{ color: "crimson" }}>{error}</p>}
    </div>
  );
}