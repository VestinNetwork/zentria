import { Card } from "@hawas/ui";

export default function LoginPage() {
  return (
    <main style={{ minHeight: "100vh", background: "linear-gradient(135deg, #020617, #172554)", color: "#e5e7eb", padding: 48 }}>
      <Card title="Operator login">
        <form>
          <label>
            Email
            <input name="email" type="email" autoComplete="email" style={{ display: "block", margin: "8px 0 16px", width: "100%" }} />
          </label>
          <label>
            Password
            <input name="password" type="password" autoComplete="current-password" style={{ display: "block", margin: "8px 0 16px", width: "100%" }} />
          </label>
          <label>
            MFA code
            <input name="totp_code" inputMode="numeric" style={{ display: "block", margin: "8px 0 16px", width: "100%" }} />
          </label>
          <p>Admins must provide MFA after enrollment.</p>
          <button type="submit">Sign in</button>
        </form>
      </Card>
    </main>
  );
}
