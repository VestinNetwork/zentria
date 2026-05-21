import { Card } from "@hawas/ui";

export default function AdminLoginPage() {
  return (
    <main style={{ minHeight: "100vh", background: "linear-gradient(135deg, #450a0a, #581c87)", color: "#fee2e2", padding: 48 }}>
      <Card title="Admin login">
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
            <input name="totp_code" inputMode="numeric" required style={{ display: "block", margin: "8px 0 16px", width: "100%" }} />
          </label>
          <p>MFA is mandatory for admin sessions.</p>
          <button type="submit">Sign in</button>
        </form>
      </Card>
    </main>
  );
}
