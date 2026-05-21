FROM node:24-slim AS runtime

WORKDIR /repo
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json ./
COPY projects/kiro/hawas-testnet/apps/admin/package.json projects/kiro/hawas-testnet/apps/admin/package.json
COPY projects/kiro/hawas-testnet/packages/ui/package.json projects/kiro/hawas-testnet/packages/ui/package.json
RUN pnpm install --frozen-lockfile --filter @hawas/admin...
COPY projects/kiro/hawas-testnet/apps/admin projects/kiro/hawas-testnet/apps/admin
COPY projects/kiro/hawas-testnet/packages/ui projects/kiro/hawas-testnet/packages/ui

EXPOSE 3100
CMD ["pnpm", "--filter", "@hawas/admin", "dev", "--hostname", "0.0.0.0"]
