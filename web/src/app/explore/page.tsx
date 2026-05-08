"use client";

import Link from "next/link";
import {useChainId, useReadContract, useReadContracts} from "wagmi";
import {ArrowRight, Lock, Rocket, ShieldCheck} from "lucide-react";

import {launchpadAbi} from "@/abi/launchpad";
import {memeTokenAbi} from "@/abi/memeToken";
import {getChainConfig} from "@/lib/contracts";

export default function ExplorePage() {
  const chainId = useChainId();
  const config = getChainConfig(chainId);
  const launchpadAddress = config?.launchpad;

  const {data: total} = useReadContract({
    abi: launchpadAbi,
    address: launchpadAddress,
    functionName: "totalLaunches",
    query: {enabled: !!launchpadAddress},
  });

  const totalNum = total ? Number(total) : 0;
  const ids = Array.from({length: totalNum}, (_, i) => BigInt(totalNum - 1 - i));

  const {data: launches} = useReadContracts({
    contracts: ids.map((id) => ({
      abi: launchpadAbi,
      address: launchpadAddress,
      functionName: "getLaunch" as const,
      args: [id] as const,
    })),
    query: {enabled: !!launchpadAddress && totalNum > 0},
  });

  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-12">
      <div className="mb-8 flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold flex items-center gap-2">
            <Rocket className="h-7 w-7 text-emerald-400" />
            Explore launches
          </h1>
          <p className="mt-2 text-zinc-400">
            Every token launched here has locked liquidity and dev vesting.{" "}
            <span className="text-emerald-400">{totalNum}</span> launch{totalNum === 1 ? "" : "es"} so far.
          </p>
        </div>
        <Link
          href="/launch"
          className="inline-flex items-center gap-2 rounded-lg bg-emerald-500 px-4 py-2 font-semibold text-zinc-950 hover:bg-emerald-400 transition"
        >
          Launch yours <ArrowRight className="h-4 w-4" />
        </Link>
      </div>

      {!launchpadAddress || launchpadAddress === "0x0000000000000000000000000000000000000000" ? (
        <EmptyState
          title="Launchpad not deployed on this network"
          body="Switch to a supported chain or deploy the contracts (see /contracts/script/Deploy.s.sol)."
        />
      ) : totalNum === 0 ? (
        <EmptyState
          title="No launches yet"
          body="Be the first to launch a token on this chain. Locked LP and vested dev allocation, all in one transaction."
        />
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {launches?.map((res, idx) => {
            const launch = res?.result as LaunchInfo | undefined;
            if (!launch) return null;
            return <LaunchCard key={idx} launch={launch} />;
          })}
        </div>
      )}
    </div>
  );
}

type LaunchInfo = {
  token: `0x${string}`;
  pair: `0x${string}`;
  dev: `0x${string}`;
  lockId: bigint;
  vestingId: bigint;
  createdAt: bigint;
};

function LaunchCard({launch}: {launch: LaunchInfo}) {
  const {data: nameSymbol} = useReadContracts({
    contracts: [
      {abi: memeTokenAbi, address: launch.token, functionName: "name"},
      {abi: memeTokenAbi, address: launch.token, functionName: "symbol"},
    ],
  });

  const name = nameSymbol?.[0]?.result as string | undefined;
  const symbol = nameSymbol?.[1]?.result as string | undefined;
  const ageMin = Math.max(0, Math.floor((Date.now() / 1000 - Number(launch.createdAt)) / 60));

  return (
    <Link
      href={`/token/${launch.token}`}
      className="block rounded-xl border border-zinc-800 bg-zinc-900/40 p-5 hover:border-emerald-700 hover:bg-zinc-900/70 transition"
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="font-semibold text-lg truncate">{name ?? "..."}</div>
          <div className="text-sm text-zinc-500 truncate">${symbol ?? "..."}</div>
        </div>
        <span className="shrink-0 rounded-full bg-emerald-950/50 border border-emerald-900/50 text-emerald-400 text-xs px-2 py-0.5">
          {ageMin < 60 ? `${ageMin}m` : ageMin < 1440 ? `${Math.floor(ageMin / 60)}h` : `${Math.floor(ageMin / 1440)}d`}
        </span>
      </div>
      <div className="mt-4 flex items-center gap-3 text-xs text-zinc-400">
        <span className="inline-flex items-center gap-1 text-emerald-400">
          <Lock className="h-3 w-3" /> LP locked
        </span>
        {launch.vestingId !== 2n ** 256n - 1n && (
          <span className="inline-flex items-center gap-1 text-emerald-400">
            <ShieldCheck className="h-3 w-3" /> Dev vested
          </span>
        )}
      </div>
      <div className="mt-3 text-xs text-zinc-600 font-mono truncate">{launch.token}</div>
    </Link>
  );
}

function EmptyState({title, body}: {title: string; body: string}) {
  return (
    <div className="rounded-2xl border border-dashed border-zinc-800 bg-zinc-900/20 p-12 text-center">
      <Rocket className="mx-auto h-10 w-10 text-zinc-600 mb-3" />
      <h3 className="text-lg font-semibold">{title}</h3>
      <p className="mt-1 text-sm text-zinc-500 max-w-md mx-auto">{body}</p>
    </div>
  );
}
