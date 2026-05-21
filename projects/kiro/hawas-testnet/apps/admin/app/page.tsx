import { Card } from "@hawas/ui";

export default function AdminHomePage() {
  return (
    <main style={{ minHeight: "100vh", background: "#16050b", color: "#fee2e2", padding: 48 }}>
      <Card title="HAWAS Admin Dashboard">
        <p>Admin surface scaffold is ready for policies, risk rules, agents, and health.</p>
      </Card>
    </main>
  );
}

