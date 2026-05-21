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

