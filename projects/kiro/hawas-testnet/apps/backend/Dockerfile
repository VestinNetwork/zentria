FROM python:3.12-slim AS runtime

WORKDIR /app
COPY projects/kiro/hawas-testnet/apps/backend/pyproject.toml ./
RUN pip install --no-cache-dir uv \
  && uv pip install --system .
COPY projects/kiro/hawas-testnet/apps/backend/src ./src

ENV PYTHONPATH=/app/src
CMD ["uvicorn", "hawas.main:app", "--host", "0.0.0.0", "--port", "8000"]
