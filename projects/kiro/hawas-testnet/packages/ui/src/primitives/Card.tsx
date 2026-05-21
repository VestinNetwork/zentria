import type { ReactNode } from "react";

export function Card({ title, children }: Readonly<{ title: string; children: ReactNode }>) {
  return (
    <section
      style={{
        border: "1px solid rgba(148, 163, 184, 0.3)",
        borderRadius: 20,
        padding: 24,
        background: "rgba(15, 23, 42, 0.82)",
        boxShadow: "0 24px 80px rgba(0, 0, 0, 0.32)",
        maxWidth: 720,
      }}
    >
      <h1 style={{ marginTop: 0 }}>{title}</h1>
      {children}
    </section>
  );
}

