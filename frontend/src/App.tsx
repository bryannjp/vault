import { useWallet } from "./hooks/useWallet";
import { useVaultData } from "./hooks/useVaultData";
import { ConnectWallet } from "./components/ConnectWallet";
import { VaultStats } from "./components/VaultStats";
import { MyPosition } from "./components/MyPosition";
import { Faucet } from "./components/Faucet";
import { Deposit } from "./components/Deposit";
import { RequestWithdrawal } from "./components/RequestWithdrawal";
import { Claim } from "./components/Claim";
import { OwnerPanel } from "./components/OwnerPanel";
import { ActivityFeed } from "./components/ActivityFeed";

export default function App() {
  const wallet = useWallet();
  const { vault, user, error } = useVaultData(wallet.account);
  
  // MetaMask gives lowercase addresses, the contract returns checksummed (mixed-case) ones: compare in lowercase.
  const isOwner = vault !== null && wallet.account?.toLowerCase() === vault.owner.toLowerCase();

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
          {/* Transactions only when a wallet is connected to the right chain */}
          {wallet.account && wallet.isCorrectChain && user && (
            <>
              <Faucet vault={vault} account={wallet.account} getSigner={wallet.getSigner} />
              <Deposit vault={vault} user={user} account={wallet.account} getSigner={wallet.getSigner} />
              <RequestWithdrawal vault={vault} user={user} getSigner={wallet.getSigner} />
              {user.pendingAssets > 0n && (
                <Claim vault={vault} user={user} account={wallet.account} getSigner={wallet.getSigner} />
              )}
              {isOwner && <OwnerPanel vault={vault} getSigner={wallet.getSigner} />}
            </>
          )}
          <ActivityFeed vault={vault} />
        </>
      )}
    </main>
  );
}