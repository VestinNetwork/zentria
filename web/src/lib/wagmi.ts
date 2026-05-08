import {getDefaultConfig} from "@rainbow-me/rainbowkit";
import {arbitrum, arbitrumSepolia} from "wagmi/chains";

const projectId =
  process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "rugproof-launchpad";

export const wagmiConfig = getDefaultConfig({
  appName: "Rugproof Launchpad",
  projectId,
  chains: [arbitrum, arbitrumSepolia],
  ssr: true,
});

export {arbitrum, arbitrumSepolia};
