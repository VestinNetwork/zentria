import {arbitrum, arbitrumSepolia} from "wagmi/chains";
import type {Address} from "viem";

/// Per-chain deployed addresses. Update after running `forge script Deploy.s.sol`.
/// You can also override these via NEXT_PUBLIC_LAUNCHPAD_<CHAINID> env vars at build time.
export type ChainConfig = {
  launchpad: Address;
  liquidityLocker: Address;
  devVesting: Address;
  router: Address;
  weth: Address;
};

const ZERO: Address = "0x0000000000000000000000000000000000000000";

const env = (key: string, fallback: Address): Address => {
  const v = process.env[key];
  return (v && v.startsWith("0x") ? (v as Address) : fallback);
};

export const chainConfigs: Record<number, ChainConfig> = {
  [arbitrum.id]: {
    launchpad: env("NEXT_PUBLIC_LAUNCHPAD_42161", ZERO),
    liquidityLocker: env("NEXT_PUBLIC_LOCKER_42161", ZERO),
    devVesting: env("NEXT_PUBLIC_VESTING_42161", ZERO),
    // Uniswap V2 router on Arbitrum One.
    router: "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24",
    weth: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
  },
  [arbitrumSepolia.id]: {
    launchpad: env("NEXT_PUBLIC_LAUNCHPAD_421614", ZERO),
    liquidityLocker: env("NEXT_PUBLIC_LOCKER_421614", ZERO),
    devVesting: env("NEXT_PUBLIC_VESTING_421614", ZERO),
    router: env("NEXT_PUBLIC_ROUTER_421614", ZERO),
    weth: env("NEXT_PUBLIC_WETH_421614", ZERO),
  },
};

export const supportedChainIds = Object.keys(chainConfigs).map(Number);

export const getChainConfig = (chainId: number | undefined): ChainConfig | null => {
  if (!chainId) return null;
  return chainConfigs[chainId] ?? null;
};
