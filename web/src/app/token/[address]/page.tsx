"use client";

import {useParams} from "next/navigation";
import {formatUnits, isAddress} from "viem";
import {useChainId, useReadContract, useReadContracts} from "wagmi";
import {ArrowLeft, ExternalLink, Lock, ShieldCheck, Timer} from "lucide-react";
import Link from "next/link";

import {launchpadAbi} from "@/abi/launchpad";
import {liquidityLockerAbi} from "@/abi/liquidityLocker";
import {devVestingAbi} from "@/abi/devVesting";
import {memeTokenAbi} from "@/abi/memeToken";
import {getChainConfig} from "@/lib/contracts";

export default function TokenDetailPage() {
  const params = useParams<{address: string}>();
  const chainId = useChainId();
  const config = getChainConfig(chainId);

  const tokenAddress = params.address;
  if (!tokenAddress || !isAddress(tokenAddress)) {
    return <Centered title="Invalid address" body="The token address in the URL is malformed." />;
  }
  if (!config || config.launchpad === "0x0000000000000000000000000000000000000000") {
    return (
      <Centered
        title="Launchpad not deployed"
        body="Switch to a network where the launchpad has been deployed."
      />
    );
  }

  return <TokenDetail tokenAddress={tokenAddress} launchpadAddress={config.launchpad} lockerAddress={config.liquidityLocker} vestingAddress={config.devVesting} />;
}

function TokenDetail({
  tokenAddress,
  launchpadAddress,
  lockerAddress,
  vestingAddress,
}: {
  tokenAddress: `0x${string}`;
  launchpadAddress: `0x${string}`;
  lockerAddress: `0x${string}`;
  vestingAddress: `0x${string}`;
}) {
  const {data: launch, error: launchError} = useReadContract({
    abi: launchpadAbi,
    address: launchpadAddress,
    functionName: "getLaunchByToken",
    args: [tokenAddress],
  });

  const {data: tokenMeta} = useReadContracts({
    contracts: [
      {abi: memeTokenAbi, address: tokenAddress, functionName: "name"},
      {abi: memeTokenAbi, address: tokenAddress, functionName: "symbol"},
      {abi: memeTokenAbi, address: tokenAddress, functionName: "totalSupply"},
      {abi: memeTokenAbi, address: tokenAddress, functionName: "decimals"},
      {abi: memeTokenAbi, address: tokenAddress, functionName: "buyTaxBps"},
      {abi: memeTokenAbi, address: tokenAddress, functionName: "sellTaxBps"},
      {abi: memeTokenAbi, address: tokenAddress, functionName: "tradingOpen"},
      {abi: memeTokenAbi, address: tokenAddress, functionName: "limitsActive"},
      {abi: memeTokenAbi, address: tokenAddress, functionName: "owner"},
    ],
  });

  const {data: lockData} = useReadContract({
    abi: liquidityLockerAbi,
    address: lockerAddress,
    functionName: "getLock",
    args: launch ? [launch.lockId] : undefined,
    query: {enabled: !!launch},
  });

  const hasVesting = launch && launch.vestingId !== 2n ** 256n - 1n;
  const {data: vestingSchedule} = useReadContract({
    abi: devVestingAbi,
    address: vestingAddress,
    functionName: "getSchedule",
    args: hasVesting && launch ? [launch.vestingId] : undefined,
    query: {enabled: hasVesting},
  });

  if (launchError) {
    return (
      <Centered
        title="Token not found"
        body="This token wasn't launched via the platform. We can only show details for tokens launched here."
      />
    );
  }

  const name = tokenMeta?.[0]?.result as string | undefined;
  const symbol = tokenMeta?.[1]?.result as string | undefined;
  const totalSupply = tokenMeta?.[2]?.result as bigint | undefined;
  const decimals = (tokenMeta?.[3]?.result as number | undefined) ?? 18;
  const buyTaxBps = (tokenMeta?.[4]?.result as number | undefined) ?? 0;
  const sellTaxBps = (tokenMeta?.[5]?.result as number | undefined) ?? 0;
  const tradingOpen = tokenMeta?.[6]?.result as boolean | undefined;
  const limitsActive = tokenMeta?.[7]?.result as boolean | undefined;
  const owner = tokenMeta?.[8]?.result as `0x${string}` | undefined;

  const unlockDate = lockData ? new Date(Number(lockData.unlockAt) * 1000) : null;

  return (
    <div className="mx-auto max-w-5xl px-4 sm:px-6 lg:px-8 py-12">
      <Link
        href="/explore"
        className="inline-flex items-center gap-1 text-sm text-zinc-400 hover:text-zinc-200 mb-6"
      >
        <ArrowLeft className="h-4 w-4" /> Back to explore
      </Link>

      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-3xl font-bold">{name ?? "..."}</h1>
          <div className="mt-1 text-zinc-500">
            ${symbol ?? "..."} &middot;{" "}
            <span className="font-mono text-xs">{tokenAddress}</span>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Badge ok={!!tradingOpen} label={tradingOpen ? "Trading live" : "Trading closed"} />
          <Badge ok={true} label="LP locked" />
          {hasVesting && <Badge ok={true} label="Dev vested" />}
          <Badge ok={!owner || owner === "0x0000000000000000000000000000000000000000"} label="Renounced" />
        </div>
      </div>

      <div className="mt-8 grid grid-cols-1 lg:grid-cols-3 gap-4">
        <Card title="Token economics" icon={ShieldCheck}>
          <Row label="Total supply">
            {totalSupply ? Number(formatUnits(totalSupply, decimals)).toLocaleString() : "..."}
          </Row>
          <Row label="Buy tax">{(buyTaxBps / 100).toFixed(2)}%</Row>
          <Row label="Sell tax">{(sellTaxBps / 100).toFixed(2)}%</Row>
          <Row label="Limits">{limitsActive ? "Active" : "Disabled"}</Row>
        </Card>

        <Card title="Liquidity lock" icon={Lock}>
          {lockData ? (
            <>
              <Row label="LP amount">{Number(formatUnits(lockData.amount, 18)).toLocaleString(undefined, {maximumFractionDigits: 4})}</Row>
              <Row label="Unlocks at">{unlockDate?.toLocaleString()}</Row>
              <Row label="Owner">
                <Mono>{lockData.owner}</Mono>
              </Row>
              <Row label="Withdrawn">{lockData.withdrawn ? "Yes" : "No"}</Row>
            </>
          ) : (
            <div className="text-sm text-zinc-500">Loading...</div>
          )}
        </Card>

        <Card title="Dev vesting" icon={Timer}>
          {vestingSchedule ? (
            <>
              <Row label="Total">
                {Number(formatUnits(vestingSchedule.totalAmount, 18)).toLocaleString(undefined, {
                  maximumFractionDigits: 4,
                })}
              </Row>
              <Row label="Released">
                {Number(formatUnits(vestingSchedule.released, 18)).toLocaleString(undefined, {
                  maximumFractionDigits: 4,
                })}
              </Row>
              <Row label="Cliff ends">
                {new Date((Number(vestingSchedule.startAt) + 30 * 86400) * 1000).toLocaleDateString()}
              </Row>
              <Row label="Fully vests">
                {new Date((Number(vestingSchedule.startAt) + (30 + 180) * 86400) * 1000).toLocaleDateString()}
              </Row>
            </>
          ) : hasVesting ? (
            <div className="text-sm text-zinc-500">Loading...</div>
          ) : (
            <div className="text-sm text-zinc-500">No dev allocation for this launch.</div>
          )}
        </Card>
      </div>

      {launch && (
        <Card title="Launch info" icon={ExternalLink} className="mt-4">
          <Row label="Pair (Uniswap V2)">
            <Mono>{launch.pair}</Mono>
          </Row>
          <Row label="Dev wallet">
            <Mono>{launch.dev}</Mono>
          </Row>
          <Row label="Created">
            {new Date(Number(launch.createdAt) * 1000).toLocaleString()}
          </Row>
        </Card>
      )}
    </div>
  );
}

function Card({
  title,
  icon: Icon,
  children,
  className = "",
}: {
  title: string;
  icon: React.ComponentType<{className?: string}>;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={`rounded-xl border border-zinc-800 bg-zinc-900/40 p-5 ${className}`}>
      <div className="flex items-center gap-2 text-sm font-medium text-zinc-300 mb-3">
        <Icon className="h-4 w-4 text-emerald-400" />
        {title}
      </div>
      <div className="space-y-2 text-sm">{children}</div>
    </div>
  );
}

function Row({label, children}: {label: string; children: React.ReactNode}) {
  return (
    <div className="flex justify-between gap-3">
      <span className="text-zinc-500">{label}</span>
      <span className="text-zinc-100 text-right truncate">{children}</span>
    </div>
  );
}

function Mono({children}: {children: React.ReactNode}) {
  return <span className="font-mono text-xs">{children}</span>;
}

function Badge({ok, label}: {ok: boolean; label: string}) {
  return (
    <span
      className={`inline-flex items-center rounded-full text-xs px-2 py-0.5 border ${
        ok
          ? "border-emerald-900/50 bg-emerald-950/40 text-emerald-400"
          : "border-zinc-800 bg-zinc-900 text-zinc-500"
      }`}
    >
      {label}
    </span>
  );
}

function Centered({title, body}: {title: string; body: string}) {
  return (
    <div className="mx-auto max-w-md px-6 py-24 text-center">
      <h1 className="text-2xl font-semibold">{title}</h1>
      <p className="mt-2 text-zinc-400">{body}</p>
    </div>
  );
}
