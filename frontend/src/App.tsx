import { useWallet } from "./hooks/useWallet";
import { useVaultData } from "./hooks/useVaultData";
import { ConnectWallet } from "./components/ConnectWallet";
import { VaultStats } from "./components/VaultStats";
import { MyPosition } from "./components/MyPosition";

export default function App() {
  const wallet = useWallet();
  const { vault, user, error } = useVaultData(wallet.account);

  return (
    <main>
      <h1>SimpleVault</h1>
      <ConnectWallet {...wallet} />
      {error && <p style={{ color: "crimson" }}>Could not load vault data: {error}</p>}
      {!vault ? (
        !error && <p>Loading…</p>
      ) : (
        <>
          <VaultStats vault={vault} />
          {user && <MyPosition vault={vault} user={user} />}
        </>
      )}
    </main>
  );
}