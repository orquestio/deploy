#!/bin/bash
# =============================================================================
# Descarga secrets de AWS SSM Parameter Store y genera .env
# Uso: ./init-env.sh [entorno]   (default: prod)
# =============================================================================
set -euo pipefail

ENV="${1:-prod}"
PREFIX="/orquestio/${ENV}"

echo "Descargando secrets de SSM (${PREFIX})..."

# Variables no-secretas (defaults)
cat > .env << EOF
POSTGRES_DB=orquestio
POSTGRES_USER=orquestio
POSTGRES_HOST=db
POSTGRES_PORT=5432
REDIS_HOST=redis
REDIS_PORT=6379
EOF

# Variables secretas desde SSM
for KEY in POSTGRES_PASSWORD API_KEY ENCRYPTION_KEY CLOUDFLARE_API_TOKEN REDIS_PASSWORD; do
  VALUE=$(aws ssm get-parameter \
    --name "${PREFIX}/${KEY}" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text)
  echo "${KEY}=${VALUE}" >> .env
done

echo ".env generado con $(wc -l < .env) variables."
