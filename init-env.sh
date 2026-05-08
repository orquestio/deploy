#!/bin/bash
# =============================================================================
# Genera .env desde AWS SSM Parameter Store.
# Uso: ./init-env.sh [entorno]   (default: prod)
#
# Source-of-truth: cualquier parámetro bajo /orquestio/<env>/ se inyecta como
# env var en .env. Para sumar una nueva clave en prod NO hace falta modificar
# este script — basta con declararla en SSM (y en el devvault.yml canónico
# de orquestio/agent-stack, que es el catálogo). Esto previene el incidente
# del 2026-05-08 donde PRYSMID_PORTAL_CUSTOMER_* existía en SSM pero el
# script no la bajaba, dejando a Prysm:ID silenciosamente sin configurar
# después de un redeploy.
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

# 1) Listar todos los nombres bajo el prefix.
NAMES=$(aws ssm get-parameters-by-path \
  --path "${PREFIX}/" \
  --recursive \
  --query 'Parameters[].Name' \
  --output text)

# 2) Bajar cada parámetro individualmente con --output text. Hacerlo per-name
#    (en vez de get-parameters-by-path con TSV multi-columna) garantiza que
#    valores con tabs o newlines no se corrompan en el parsing.
for FULL_NAME in $NAMES; do
  KEY="${FULL_NAME##*/}"
  # SSM permite '/' en nombres; env vars no. Saltar parámetros nested.
  if [ "$FULL_NAME" != "${PREFIX}/${KEY}" ]; then
    echo "  skip nested: $FULL_NAME" >&2
    continue
  fi
  VALUE=$(aws ssm get-parameter \
    --name "$FULL_NAME" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)
  echo "${KEY}=${VALUE}" >> .env
done

echo ".env generado con $(wc -l < .env) variables."
