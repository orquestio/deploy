# Orquestio — deploy

Runtime deploy orchestration for **Orquestio**: compose files, reverse proxy config, secret pulling, redeploy hooks.

This repo is one of the four mandatory Categoría A repos per [Ganemo governance](https://github.com/getGanemo/docs-company/blob/main/governance/product-structure.md). It exists alongside `infrastructure/` (provisioning, declarative, one-time per machine) to keep a clean **dev/ops handoff** via versioned images.

## What lives here

- Compose files (`docker-compose.yml`, environment-specific overrides) referencing **published images by tag**.
- Reverse proxy config (Nginx, Caddy, Traefik) and any host-level integration points.
- Secret pulling scripts (from SSM Parameter Store, Vault, etc. into the app filesystem at deploy time).
- Redeploy hooks, restart policies, healthcheck overrides.
- Per-environment runtime variables.

## What does NOT live here

- **`Dockerfile`, `requirements.txt`, `package.json`, `pyproject.toml`** of any service — those live with the source code (`api/`, `web/`, etc.) per the [build artifacts rule](https://github.com/getGanemo/docs-company/blob/main/governance/product-structure.md#pertenencia-de-build-artifacts). This repo **consumes published images**, never build contexts.
- **Terraform / IaC** — those live in `infrastructure/`. Frontera: provisioning (one-time per machine) → `infrastructure`; runtime orchestration (per deploy) → here.
- **Operational runbooks** — those live in `project_management/runbooks/`.

## Boundary with `infrastructure/`

Mnemonic: *if the script runs **once** when the host is created → `infrastructure`. If it runs **on every deploy** → here.*

Concrete examples:

| Concern | Repo |
|---|---|
| `aws_ec2_instance` definition | `infrastructure` |
| Cloud-init script that installs Docker | `infrastructure` |
| Systemd unit definition for the daemon | `infrastructure` |
| Log rotation config | `infrastructure` |
| `docker-compose.yml` referencing `api:v1.2.3` | here |
| Script that pulls secrets from SSM into `.env` | here |
| Reverse proxy config block | here |
| Restart hook triggered by tag bump | here |

## Versioning

This repo follows **semver tags** matching the deployed bundle. The image tags it references are versioned independently per service.

## Ownership

> **TODO**: set CODEOWNERS once the ops team is onboarded. Until then, ownership is implicit (single dev plays both roles); changes go via PR for audit trail.
