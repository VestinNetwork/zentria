FROM node:24-slim AS runtime

WORKDIR /repo
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json ./
COPY projects/kiro/hawas-testnet/apps/web/package.json projects/kiro/hawas-testnet/apps/web/package.json
COPY projects/kiro/hawas-testnet/apps/admin/package.json projects/kiro/hawas-testnet/apps/admin/package.json
COPY projects/kiro/hawas-testnet/packages/ui/package.json projects/kiro/hawas-testnet/packages/ui/package.json
COPY projects/kiro/hawas-testnet/packages/types-hawas/package.json projects/kiro/hawas-testnet/packages/types-hawas/package.json
RUN pnpm install --frozen-lockfile --filter @hawas/web...
COPY projects/kiro/hawas-testnet/apps/web projects/kiro/hawas-testnet/apps/web
COPY projects/kiro/hawas-testnet/packages/ui projects/kiro/hawas-testnet/packages/ui
COPY projects/kiro/hawas-testnet/packages/types-hawas projects/kiro/hawas-testnet/packages/types-hawas

EXPOSE 3000
CMD ["pnpm", "--filter", "@hawas/web", "dev", "--hostname", "0.0.0.0"]
