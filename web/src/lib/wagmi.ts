import {getDefaultConfig} from "@rainbow-me/rainbowkit";
import type {ChainFees} from "viem";
import {getBlock} from "viem/actions";
import {arbitrum as arbitrumBase, arbitrumSepolia as arbitrumSepoliaBase} from "wagmi/chains";

const projectId =
  process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "rugproof-launchpad";

// Arbitrum's basefee can swing between blocks by enough to make viem's default
// estimator under-set `maxFeePerGas` by a few wei -> wallet rejects with
// "max fee per gas less than block base fee". Use a custom fee estimator that
// reads the latest basefee and triples it (with a 1 gwei floor).
const ONE_GWEI = 1_000_000_000n;
const bufferedFees: ChainFees = {
  estimateFeesPerGas: async ({client}) => {
    const block = await getBlock(client, {blockTag: "latest"});
    const baseFee = block.baseFeePerGas ?? ONE_GWEI / 10n;
    const tripled = baseFee * 3n;
    const maxFeePerGas = tripled > ONE_GWEI ? tripled : ONE_GWEI;
    return {
      maxFeePerGas,
      maxPriorityFeePerGas: 0n,
    };
  },
};

export const arbitrum = {...arbitrumBase, fees: bufferedFees};
export const arbitrumSepolia = {...arbitrumSepoliaBase, fees: bufferedFees};

export const wagmiConfig = getDefaultConfig({
  appName: "Rugproof Launchpad",
  projectId,
  chains: [arbitrum, arbitrumSepolia],
  ssr: true,
});
