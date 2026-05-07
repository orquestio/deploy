# Orquestio — deploy

Runtime deploy orchestration for **Orquestio**: compose files, reverse proxy config, secret pulling, redeploy hooks.

This repo is one of the four mandatory Categoría A repos per [Ganemo governance](https://github.com/getGanemo/docs-company/blob/main/governance/product-structure.md). It exists alongside `infrastructure/` (provisioning, declarative, one-time per machine) to keep a clean **dev/ops handoff** via versioned images.

## What lives here

- Compose files (`docker-compose.yml`, environment-specific overrides) referencing **published images by tag**.
- Reverse proxy config (Nginx) and any host-level integration points.
- Secret pulling scripts (from SSM Parameter Store into the app filesystem at deploy time).
- DB bootstrap SQL mirror for first-init seeding.
- Per-environment runtime variables.

## What does NOT live here

- **`Dockerfile`, `requirements.txt`, application source** — those live with the source code (`orchestrator/`, etc.) per the [build artifacts rule](https://github.com/getGanemo/docs-company/blob/main/governance/product-structure.md#pertenencia-de-build-artifacts). This repo **consumes published images**, never build contexts.
- **Terraform / IaC** — those live in `infrastructure/`. Frontera: provisioning (one-time per machine) → `infrastructure`; runtime orchestration (per deploy) → here.
- **Operational runbooks** — those live in `project_management/runbooks/orchestrator_deploy.md`.

## Boundary with `infrastructure/`

Mnemonic: *if the script runs **once** when the host is created → `infrastructure`. If it runs **on every deploy** → here.*

| Concern | Repo |
|---|---|
| `aws_ec2_instance` definition | `infrastructure` |
| Cloud-init script that installs Docker | `infrastructure` |
| Systemd unit definition for the daemon | `infrastructure` |
| Log rotation config | `infrastructure` |
| `docker-compose.yml` referencing `orchestrator:v0.2.0` | here |
| Script that pulls secrets from SSM into `.env` | here |
| Reverse proxy config block | here |

## Layout

```
deploy/
├── docker-compose.yml      # references ghcr.io/orquestio/orchestrator:<tag>
├── nginx/nginx.conf        # reverse proxy config
├── init-env.sh             # secret puller: SSM → .env
├── sql-bootstrap/          # mounted at /docker-entrypoint-initdb.d/
│   ├── 01-init.sql
│   ├── 02-openclaw.sql
│   └── 03-control-plane.sql
└── .env.example
```

`sql-bootstrap/` runs **only** on first init of the postgres volume. Migrations from `004` onward are applied manually — see "Migrations de schema existente" below.

## Versioning

Semver tags. The orchestrator image tag pinned in `docker-compose.yml` is updated explicitly per deploy — **never use `:latest`**, every tag is immutable.

To bump:

1. Push a `v*` tag in `orquestio/orchestrator`.
2. Wait for the `release.yml` workflow to publish `ghcr.io/orquestio/orchestrator:<tag>`.
3. Verify `gh api /orgs/orquestio/packages/container/orchestrator/versions` lists the tag.
4. PR here updating the `image:` line.

## Procedimiento de deploy (prod EC2 `i-0fc23a55a77a63c8e`)

Ejecutar vía SSM Session Manager (puerto 22 cerrado por seguridad — ver `infrastructure/DEPLOY.md`).

### Pre-requisitos por host

- Docker + docker compose plugin instalados (cloud-init en `infrastructure/`).
- PAT GHCR pull-only en SSM `/orquestio/prod/GHCR_PULL_TOKEN` (mismo patrón que `DOCKERHUB_TOKEN`).
- Clone de este repo en `/opt/orquestio/deploy/`.

### Deploy normal

```bash
cd /opt/orquestio/deploy
git pull

# Refrescar .env desde SSM (variables nuevas, rotación de secrets, etc.)
./init-env.sh prod

# Login a GHCR (usa el PAT de SSM; sólo necesario la primera vez por host
# o si rota el token).
GHCR_TOKEN=$(aws ssm get-parameter --name /orquestio/prod/GHCR_PULL_TOKEN \
  --with-decryption --query 'Parameter.Value' --output text)
echo "$GHCR_TOKEN" | sudo docker login ghcr.io -u orquestio-bot --password-stdin

# Pull de la imagen del tag pineado en docker-compose.yml
sudo docker compose pull

# Down/up coordinado
sudo docker compose down
sudo docker compose up -d

# Verificación
curl -s http://localhost:8000/health
```

## Procedimiento de ROLLBACK

> Si la imagen GHCR no funciona en producción tras el cutover.

```bash
# 1. SSM al EC2 i-0fc23a55a77a63c8e
# 2. El compose viejo sigue vivo en /opt/orquestio/orchestrator/ hasta que
#    se mergee PR-orch-cleanup. Mientras tanto, este path es la red de seguridad.
cd /opt/orquestio/orchestrator
git fetch --tags
git checkout pre-awac-cutover

# 3. Apagar el stack nuevo
cd /opt/orquestio/deploy
sudo docker compose down

# 4. Levantar el stack viejo (build local, sin GHCR)
cd /opt/orquestio/orchestrator
sudo docker compose up -d --build

# 5. Verificar
curl -s http://localhost:8000/health
```

**Pre-requisitos de viabilidad:**

- El tag git `pre-awac-cutover` debe existir en `orquestio/orchestrator` antes del cutover. Se crea como parte de la sesión v26 (AWaC governance refactor).
- `PR-orch-cleanup` no se ha mergeado aún — el compose viejo sigue presente en `orchestrator/`.
- Si pasaron 24-48h sin problemas y `PR-orch-cleanup` ya entró, el rollback ya **no aplica** — la única recuperación es revertir `PR-orch-cleanup` en GitHub o re-clonar el repo a un commit anterior al cleanup.

## Migrations de schema existente

`/docker-entrypoint-initdb.d/` corre **solo** la primera vez que se inicializa el volume de postgres. Sobre una DB existente, las migrations en `orchestrator/sql/migrations/004*` en adelante **no se aplican automáticamente** — hay que correrlas a mano vía SSM contra la db de prod después de cada upgrade.

```bash
# Listar migrations en el deploy actual
ls -1 /opt/orquestio/orchestrator/sql/migrations/

# Aplicar una migration por stdin (cuando no está montada en el contenedor)
sudo docker compose exec -T db psql -U orquestio -d orquestio \
  < /opt/orquestio/orchestrator/sql/migrations/0NN_xxx.sql

# Verificar
sudo docker compose exec -T db psql -U orquestio -d orquestio -c '\dt'
```

Mantener actualizada la tabla "Migrations aplicadas a prod a mano" en `project_management/runbooks/orchestrator_deploy.md`. Si la lista no está al día, la próxima sesión no sabe qué falta correr.

Patrón actual hasta que se introduzca Alembic (ticket pendiente, PR-G futuro). NO agregar un servicio `migrate:` al compose — es scope creep y la convención manual está documentada.

## Ownership

> **TODO**: set CODEOWNERS once the ops team is onboarded. Until then, ownership is implicit (single dev plays both roles); changes go via PR for audit trail.
