export interface HawasError {
  code: string;
  message: string;
  details: Record<string, unknown>;
}

export interface HealthResponse {
  status: "ok";
  service: "hawas-backend";
  variant: "testnet" | "mainnet";
}

export interface AuthTokenPair {
  access_token: string;
  refresh_token: string;
  token_type: "bearer";
  expires_in: number;
  roles: string[];
  permissions: string[];
}
