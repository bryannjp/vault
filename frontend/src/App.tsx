import { useWallet } from "./hooks/useWallet";
import { ConnectWallet } from "./components/ConnectWallet";

export default function App() {
  const wallet = useWallet();

  return (
    <main>
      <h1>SimpleVault</h1>
      <ConnectWallet {...wallet} />
    </main>
  );
}