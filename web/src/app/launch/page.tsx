"use client";

import {useState} from "react";
import {parseEther} from "viem";
import {useAccount, useChainId, useWaitForTransactionReceipt, useWriteContract} from "wagmi";
import {AlertTriangle, ExternalLink, Loader2, Rocket} from "lucide-react";
import Link from "next/link";

import {launchpadAbi} from "@/abi/launchpad";
import {getChainConfig} from "@/lib/contracts";

type FormState = {
  name: string;
  symbol: string;
  totalSupply: string;
  buyTaxPct: string;
  sellTaxPct: string;
  maxWalletPct: string;
  maxTxPct: string;
  devAllocationPct: string;
  lockMonths: string;
  initialLiquidityEth: string;
};

const INITIAL: FormState = {
  name: "",
  symbol: "",
  totalSupply: "1000000000",
  buyTaxPct: "3",
  sellTaxPct: "3",
  maxWalletPct: "2",
  maxTxPct: "1",
  devAllocationPct: "3",
  lockMonths: "12",
  initialLiquidityEth: "0.5",
};

export default function LaunchPage() {
  const {address, isConnected} = useAccount();
  const chainId = useChainId();
  const config = getChainConfig(chainId);
  const [form, setForm] = useState<FormState>(INITIAL);
  const [validationError, setValidationError] = useState<string | null>(null);

  const {writeContract, data: txHash, isPending, error: writeError} = useWriteContract();
  const {isLoading: isConfirming, isSuccess: isConfirmed} = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const update = (k: keyof FormState) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm((f) => ({...f, [k]: e.target.value}));

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setValidationError(null);

    if (!isConnected || !address) {
      setValidationError("Please connect your wallet first.");
      return;
    }
    if (!config || config.launchpad === "0x0000000000000000000000000000000000000000") {
      setValidationError(
        "Launchpad is not deployed on this network yet. Switch to a supported chain or deploy the contracts.",
      );
      return;
    }

    const buyTaxBps = Math.round(parseFloat(form.buyTaxPct) * 100);
    const sellTaxBps = Math.round(parseFloat(form.sellTaxPct) * 100);
    const maxWalletBps = Math.round(parseFloat(form.maxWalletPct) * 100);
    const maxTxBps = Math.round(parseFloat(form.maxTxPct) * 100);
    const devAllocationBps = Math.round(parseFloat(form.devAllocationPct) * 100);
    const lockDuration = BigInt(Math.round(parseFloat(form.lockMonths) * 30 * 24 * 3600));
    const totalSupply = BigInt(form.totalSupply.replace(/[^0-9]/g, "") || "0");

    if (!form.name || !form.symbol) {
      setValidationError("Name and symbol are required.");
      return;
    }
    if (totalSupply === 0n) {
      setValidationError("Total supply must be > 0.");
      return;
    }
    if (buyTaxBps > 500 || sellTaxBps > 500) {
      setValidationError("Buy/sell tax cannot exceed 5%.");
      return;
    }
    if (devAllocationBps > 500) {
      setValidationError("Dev allocation cannot exceed 5%.");
      return;
    }
    if (maxWalletBps < maxTxBps) {
      setValidationError("Max wallet must be >= max tx.");
      return;
    }
    if (lockDuration < 180n * 24n * 3600n) {
      setValidationError("Lock duration must be at least 6 months.");
      return;
    }

    const value = parseEther(form.initialLiquidityEth);
    if (value < parseEther("0.01")) {
      setValidationError("Initial liquidity must be at least 0.01 ETH.");
      return;
    }

    writeContract({
      abi: launchpadAbi,
      address: config.launchpad,
      functionName: "launch",
      args: [
        {
          name: form.name,
          symbol: form.symbol,
          totalSupply,
          buyTaxBps,
          sellTaxBps,
          maxWalletBps,
          maxTxBps,
          devAllocationBps,
          lockDuration,
        },
      ],
      value,
    });
  };

  const platformFee = parseFloat(form.initialLiquidityEth || "0") * 0.01;
  const lpEth = parseFloat(form.initialLiquidityEth || "0") - platformFee;

  return (
    <div className="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 py-12">
      <div className="mb-8">
        <h1 className="text-3xl font-bold flex items-center gap-2">
          <Rocket className="h-7 w-7 text-emerald-400" />
          Launch a memecoin
        </h1>
        <p className="mt-2 text-zinc-400">
          Configure your token below. Anti-rug guarantees are built into every launch &mdash; you can&apos;t skip them.
        </p>
      </div>

      <form
        onSubmit={handleSubmit}
        className="rounded-2xl border border-zinc-800 bg-zinc-900/40 p-6 sm:p-8 space-y-6"
      >
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
          <Field label="Token name" hint="e.g. Pepe XL">
            <Input value={form.name} onChange={update("name")} placeholder="Pepe XL" />
          </Field>
          <Field label="Symbol" hint="3-6 chars">
            <Input value={form.symbol} onChange={update("symbol")} placeholder="PXL" />
          </Field>
          <Field label="Total supply" hint="whole tokens; 18 decimals are added automatically">
            <Input value={form.totalSupply} onChange={update("totalSupply")} type="text" />
          </Field>
          <Field label="Initial liquidity (ETH)" hint="min 0.01; 1% goes to platform, rest into LP">
            <Input value={form.initialLiquidityEth} onChange={update("initialLiquidityEth")} type="text" />
          </Field>
        </div>

        <Divider label="Tax & limits (immutable after launch)" />
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <Field label="Buy tax %" hint="max 5">
            <Input value={form.buyTaxPct} onChange={update("buyTaxPct")} type="number" step="0.1" max="5" />
          </Field>
          <Field label="Sell tax %" hint="max 5">
            <Input value={form.sellTaxPct} onChange={update("sellTaxPct")} type="number" step="0.1" max="5" />
          </Field>
          <Field label="Max wallet %" hint="of total supply">
            <Input value={form.maxWalletPct} onChange={update("maxWalletPct")} type="number" step="0.1" />
          </Field>
          <Field label="Max tx %" hint="of total supply">
            <Input value={form.maxTxPct} onChange={update("maxTxPct")} type="number" step="0.1" />
          </Field>
        </div>

        <Divider label="Anti-rug guarantees (hardcoded)" />
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Field label="Dev allocation %" hint="max 5; vested 30d cliff + 6mo linear">
            <Input
              value={form.devAllocationPct}
              onChange={update("devAllocationPct")}
              type="number"
              step="0.1"
              max="5"
            />
          </Field>
          <Field label="Liquidity lock (months)" hint="min 6">
            <Input value={form.lockMonths} onChange={update("lockMonths")} type="number" min="6" />
          </Field>
        </div>

        <div className="rounded-lg border border-zinc-800 bg-zinc-950/60 p-4 text-sm text-zinc-300 space-y-1">
          <div className="flex justify-between">
            <span>Platform fee (1%)</span>
            <span className="text-emerald-400 font-medium">{platformFee.toFixed(4)} ETH</span>
          </div>
          <div className="flex justify-between">
            <span>Into LP (Uniswap V2)</span>
            <span className="font-medium">{lpEth.toFixed(4)} ETH</span>
          </div>
        </div>

        {validationError && (
          <div className="flex items-start gap-2 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
            <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
            <span>{validationError}</span>
          </div>
        )}
        {writeError && (
          <div className="flex items-start gap-2 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
            <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
            <span>{writeError.message}</span>
          </div>
        )}
        {isConfirmed && (
          <div className="rounded-lg border border-emerald-900/50 bg-emerald-950/30 p-4 text-sm text-emerald-300">
            <p className="font-medium">Token launched!</p>
            <p className="mt-1 text-emerald-400">
              <Link
                href={`/explore`}
                className="inline-flex items-center gap-1 underline-offset-2 hover:underline"
              >
                See it on the explore page <ExternalLink className="h-3 w-3" />
              </Link>
            </p>
          </div>
        )}

        <button
          type="submit"
          disabled={isPending || isConfirming}
          className="w-full inline-flex items-center justify-center gap-2 rounded-lg bg-emerald-500 px-6 py-3 font-semibold text-zinc-950 hover:bg-emerald-400 transition disabled:opacity-60 disabled:cursor-not-allowed"
        >
          {isPending ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" /> Confirm in wallet...
            </>
          ) : isConfirming ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" /> Waiting for confirmation...
            </>
          ) : (
            <>
              <Rocket className="h-4 w-4" /> Launch token
            </>
          )}
        </button>
      </form>
    </div>
  );
}

function Field({label, hint, children}: {label: string; hint?: string; children: React.ReactNode}) {
  return (
    <label className="block">
      <div className="text-sm font-medium text-zinc-200 mb-1">{label}</div>
      {children}
      {hint && <div className="mt-1 text-xs text-zinc-500">{hint}</div>}
    </label>
  );
}

function Input(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className="w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-2 text-zinc-100 placeholder-zinc-600 focus:border-emerald-500 focus:outline-none focus:ring-1 focus:ring-emerald-500"
    />
  );
}

function Divider({label}: {label: string}) {
  return (
    <div className="flex items-center gap-3 pt-2">
      <div className="h-px flex-1 bg-zinc-800" />
      <span className="text-xs uppercase tracking-wider text-zinc-500">{label}</span>
      <div className="h-px flex-1 bg-zinc-800" />
    </div>
  );
}
