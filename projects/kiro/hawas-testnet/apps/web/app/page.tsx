import { Card } from "@hawas/ui";
import type { HealthResponse } from "@hawas/types-hawas";

const initialHealth: HealthResponse = {
  status: "ok",
  service: "hawas-backend",
  variant: "testnet",
};

export default function HomePage() {
  return (
    <main style={{ minHeight: "100vh", background: "#050816", color: "#e5e7eb", padding: 48 }}>
      <Card title="HAWAS Operator Dashboard">
        <p>Launch scaffold is online for the {initialHealth.variant} variant.</p>
        <p>Backend health contract: {initialHealth.status}</p>
      </Card>
    </main>
  );
}

