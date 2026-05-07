-- =============================================================================
-- Schema del orquestador
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Blueprints: definición técnica de cada producto SaaS
CREATE TABLE IF NOT EXISTS blueprints (
    name                TEXT PRIMARY KEY,
    domain              TEXT NOT NULL,
    cloudflare_zone_id  TEXT NOT NULL,
    docker_image        TEXT NOT NULL,
    terraform_module    TEXT NOT NULL,
    default_instance_type TEXT NOT NULL DEFAULT 't4g.small',
    container_port      INTEGER NOT NULL,
    access_url_template TEXT NOT NULL,
    health_check_endpoint TEXT NOT NULL DEFAULT '/healthz',
    client_managed_config BOOLEAN NOT NULL DEFAULT true,
    password_read_command TEXT,
    active              BOOLEAN NOT NULL DEFAULT true
);

-- Plans: variantes de un producto con recursos y precio
CREATE TABLE IF NOT EXISTS plans (
    plan_id             TEXT PRIMARY KEY,
    blueprint_name      TEXT NOT NULL REFERENCES blueprints(name),
    name                TEXT NOT NULL,
    instance_type       TEXT NOT NULL,
    backup_retention_days INTEGER NOT NULL DEFAULT 7,
    active              BOOLEAN NOT NULL DEFAULT true
);

-- Instancias: estado operativo
CREATE TABLE IF NOT EXISTS instances (
    instance_id         TEXT PRIMARY KEY,
    tenant_id           TEXT NOT NULL,
    blueprint_name      TEXT NOT NULL REFERENCES blueprints(name),
    plan_id             TEXT REFERENCES plans(plan_id),
    ec2_id              TEXT,
    ip_address          TEXT,
    access_url          TEXT,
    access_password     TEXT,
    gateway_token       TEXT,
    efs_id              TEXT,
    dns_record_id       TEXT,
    secret_arn          TEXT,
    terraform_state_path TEXT,
    state               TEXT NOT NULL DEFAULT 'draft',
    cpu_usage           REAL,
    ram_usage           REAL,
    disk_usage          REAL,
    last_health_check   TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_instances_tenant ON instances(tenant_id);
CREATE INDEX IF NOT EXISTS idx_instances_state ON instances(state);

-- Variables de entorno cifradas por instancia
CREATE TABLE IF NOT EXISTS env_vars (
    id                  SERIAL PRIMARY KEY,
    instance_id         TEXT NOT NULL REFERENCES instances(instance_id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    encrypted_value     BYTEA NOT NULL,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(instance_id, name)
);

-- task_queue_log dropped in Sprint 6 (migration 005). All task routing now
-- goes through the control plane dispatcher (table `tasks`, migration 003).
