import { useEffect, useState } from "react";
import { Contract, JsonRpcProvider } from "ethers";
import vaultAbi from "./abi/SimpleVault.json";
import { RPC_URL, VAULT_ADDRESS } from "./lib/config";

export default function App() {
  const [delay, setDelay] = useState("loading…");

  useEffect(() => {
    const provider = new JsonRpcProvider(RPC_URL);
    const vault = new Contract(VAULT_ADDRESS, vaultAbi, provider);
    vault
      .withdrawalDelay()
      .then((d: bigint) => setDelay(`${d} seconds`))
      .catch((e) => setDelay(`error: ${e.shortMessage ?? e.message}`));
  }, []);

  return <h1>Withdrawal delay: {delay}</h1>;
}