"use client";

import {ConnectButton} from "@rainbow-me/rainbowkit";
import {Rocket} from "lucide-react";
import Link from "next/link";

export function Header() {
  return (
    <header className="border-b border-zinc-800 bg-zinc-950/80 backdrop-blur-sm sticky top-0 z-50">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="flex h-16 items-center justify-between">
          <Link href="/" className="flex items-center gap-2 font-bold text-lg">
            <Rocket className="h-5 w-5 text-emerald-400" />
            <span>Rugproof</span>
          </Link>
          <nav className="hidden md:flex items-center gap-6 text-sm">
            <Link href="/launch" className="text-zinc-300 hover:text-white transition">
              Launch
            </Link>
            <Link href="/explore" className="text-zinc-300 hover:text-white transition">
              Explore
            </Link>
            <a
              href="https://github.com/VestinNetwork/zentria"
              target="_blank"
              rel="noreferrer"
              className="text-zinc-300 hover:text-white transition"
            >
              Docs
            </a>
          </nav>
          <ConnectButton showBalance={false} />
        </div>
      </div>
    </header>
  );
}
