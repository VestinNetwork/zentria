import Link from "next/link";
import {ArrowRight, Lock, ShieldCheck, Timer, Users} from "lucide-react";

const FEATURES = [
  {
    icon: Lock,
    title: "Liquidity Locked Forever",
    body: "100% of LP tokens auto-locked for 6+ months in an immutable locker. No early withdrawal, no admin override.",
  },
  {
    icon: Timer,
    title: "Dev Vesting Built-in",
    body: "Dev allocation capped at 5% with 30-day cliff and 6-month linear vesting. No insta-dump possible.",
  },
  {
    icon: ShieldCheck,
    title: "Anti-Bot Limits",
    body: "Configurable max wallet & max tx during launch window auto-expires after 24h. No infinite-mint backdoor.",
  },
  {
    icon: Users,
    title: "Transparent Tax",
    body: "Buy/sell tax capped at 5%. 80% to dev, 20% to platform. Hardcoded on-chain — can't be changed post-launch.",
  },
];

export default function Home() {
  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-16 sm:py-24">
      <section className="text-center">
        <div className="inline-flex items-center gap-2 rounded-full border border-emerald-900/50 bg-emerald-950/30 px-3 py-1 text-xs text-emerald-400 mb-6">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 animate-pulse" />
          Live on Arbitrum
        </div>
        <h1 className="text-4xl sm:text-6xl font-extrabold tracking-tight text-balance">
          Launch a memecoin <span className="text-emerald-400">no one can rug</span>
        </h1>
        <p className="mt-6 max-w-2xl mx-auto text-lg text-zinc-400">
          One transaction. Locked liquidity, vested dev allocation, and on-chain anti-rug guarantees that even the
          deployer can&apos;t bypass.
        </p>
        <div className="mt-10 flex items-center justify-center gap-4">
          <Link
            href="/launch"
            className="inline-flex items-center gap-2 rounded-lg bg-emerald-500 px-6 py-3 font-semibold text-zinc-950 hover:bg-emerald-400 transition"
          >
            Launch your token <ArrowRight className="h-4 w-4" />
          </Link>
          <Link
            href="/explore"
            className="inline-flex items-center gap-2 rounded-lg border border-zinc-700 px-6 py-3 font-semibold text-zinc-100 hover:bg-zinc-900 transition"
          >
            Explore launches
          </Link>
        </div>
      </section>

      <section className="mt-24 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
        {FEATURES.map(({icon: Icon, title, body}) => (
          <div
            key={title}
            className="rounded-xl border border-zinc-800 bg-zinc-900/40 p-6 hover:border-emerald-900 transition"
          >
            <Icon className="h-6 w-6 text-emerald-400 mb-4" />
            <h3 className="font-semibold text-lg mb-2">{title}</h3>
            <p className="text-sm text-zinc-400">{body}</p>
          </div>
        ))}
      </section>

      <section className="mt-24 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-8 sm:p-12">
        <h2 className="text-2xl sm:text-3xl font-bold">How the platform earns</h2>
        <p className="mt-2 text-zinc-400">Transparent, low fees. No hidden costs.</p>
        <div className="mt-8 grid grid-cols-1 sm:grid-cols-3 gap-6">
          <Stat label="Launch fee" value="1%" caption="of initial liquidity ETH" />
          <Stat label="Tax cut" value="20%" caption="of every buy/sell tax" />
          <Stat label="Hidden fees" value="0" caption="ever" />
        </div>
      </section>
    </div>
  );
}

function Stat({label, value, caption}: {label: string; value: string; caption: string}) {
  return (
    <div>
      <div className="text-sm uppercase tracking-wide text-zinc-500">{label}</div>
      <div className="mt-1 text-4xl font-bold text-emerald-400">{value}</div>
      <div className="mt-1 text-sm text-zinc-400">{caption}</div>
    </div>
  );
}
