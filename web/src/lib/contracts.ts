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
    // Defaults below are the demo deployment on Arbitrum Sepolia.
    // Override via NEXT_PUBLIC_*_421614 env vars when redeploying.
    launchpad: env("NEXT_PUBLIC_LAUNCHPAD_421614", "0x7cAb69E5dC7bd5f1c3ec57a8cc382b390dDD96B9"),
    liquidityLocker: env("NEXT_PUBLIC_LOCKER_421614", "0x8FCfD2fFDc34a7297425A541bBE4eE794907C95C"),
    devVesting: env("NEXT_PUBLIC_VESTING_421614", "0x55575225fac885920659db05CCE1A67d0F306b8f"),
    router: env("NEXT_PUBLIC_ROUTER_421614", "0x654a5C7504edbe37233d0797f6489e497F98a343"),
    weth: env("NEXT_PUBLIC_WETH_421614", "0xD1c9a9D8Edb0C7A1E751320707A6bE07D5d18558"),
  },
};

export const supportedChainIds = Object.keys(chainConfigs).map(Number);

export const getChainConfig = (chainId: number | undefined): ChainConfig | null => {
  if (!chainId) return null;
  return chainConfigs[chainId] ?? null;
};
