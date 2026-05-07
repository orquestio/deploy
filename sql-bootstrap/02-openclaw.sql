-- =============================================================================
-- Seed data específico de OpenClaw — NO es parte del schema del orquestador.
-- =============================================================================
--
-- Este archivo crea el blueprint + plans de OpenClaw, el primer producto SaaS
-- que corre sobre Orquestio. El orquestador es genérico multi-producto: el
-- schema vive en `init.sql` y cada producto trae su propio archivo de seed.
--
-- Cuándo cargarlo:
--   - Postgres en docker-compose (dev y test) lo carga automáticamente vía
--     `/docker-entrypoint-initdb.d/` después de `init.sql`.
--   - En producción se aplica como migración manual cuando se onboardea
--     OpenClaw en una instancia nueva del orquestador.
--
-- OpenClaw blueprint — docker_image is pinned to an explicit upstream version
-- for traceability. Policy: NEVER use ':latest'. Updating the version is a
-- deliberate action that goes through .agents/workflows/update_openclaw_version.md
-- (or the manual procedure in orchestrator/OPENCLAW_RELEASE_POLICY.md).
-- Current pin: v2026.4.14 (upstream release 2026-04-14).
INSERT INTO blueprints (name, domain, cloudflare_zone_id, docker_image, terraform_module, default_instance_type, container_port, access_url_template, health_check_endpoint, password_read_command)
VALUES ('OpenClaw', 'orquestio.com', 'bc4fea8b9566b34fbc1abc058f273ca7', 'odoopartners/openclaw:v2026.4.14', 'modules/openclaw', 't4g.small', 18789, 'https://{instance_id}.orquestio.com', '/healthz', 'docker exec openclaw-current cat /home/node/.openclaw/openclaw.json | python3 -c "import sys,json;print(json.load(sys.stdin)[''gateway''][''auth''][''password''])"')
ON CONFLICT (name) DO NOTHING;

INSERT INTO plans (plan_id, blueprint_name, name, instance_type, backup_retention_days) VALUES
('openclaw-starter',    'OpenClaw', 'Starter',    't4g.small',  7),
('openclaw-business',   'OpenClaw', 'Business',   't4g.medium', 7),
('openclaw-enterprise', 'OpenClaw', 'Enterprise', 't4g.large',  30)
ON CONFLICT (plan_id) DO UPDATE SET name = EXCLUDED.name;

-- Version registry seed lives in seeds/openclaw_versions.sql (loaded after
-- migration 006 creates the table). See docker-compose mount ordering.
