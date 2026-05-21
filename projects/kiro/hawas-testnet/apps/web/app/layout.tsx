import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "HAWAS Operator",
  description: "Testnet operator dashboard for HAWAS",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

