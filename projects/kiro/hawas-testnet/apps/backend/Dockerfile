FROM python:3.12-slim AS runtime

WORKDIR /app
COPY projects/kiro/hawas-testnet/apps/backend/pyproject.toml projects/kiro/hawas-testnet/apps/backend/uv.lock ./
RUN pip install --no-cache-dir uv \
  && uv export --frozen --no-dev --format requirements-txt --output-file requirements.txt \
  && uv pip install --system --requirement requirements.txt
COPY projects/kiro/hawas-testnet/apps/backend/src ./src

ENV PYTHONPATH=/app/src
CMD ["uvicorn", "hawas.main:app", "--host", "0.0.0.0", "--port", "8000"]
