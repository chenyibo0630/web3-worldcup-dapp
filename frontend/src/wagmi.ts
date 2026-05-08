import { createConfig, http } from "wagmi";
import { sepolia, mainnet } from "wagmi/chains";
import { defineChain } from "viem";
import { injected } from "wagmi/connectors";

// 本地 anvil 链
const anvil = defineChain({
  id: 31337,
  name: "Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://localhost:8545"] },
  },
});

export const config = createConfig({
  chains: [anvil, sepolia, mainnet],
  connectors: [injected()],
  transports: {
    [anvil.id]: http(),
    [sepolia.id]: http(),
    [mainnet.id]: http(),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof config;
  }
}
