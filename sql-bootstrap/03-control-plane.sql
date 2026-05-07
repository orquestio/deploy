-- =============================================================================
-- Sprint 1.4 — Control plane tasks table
-- =============================================================================
-- Stores individual SSM operations dispatched by ControlPlaneDispatcher.
-- The dispatcher is product-agnostic: it receives full command metadata
-- (script_path, args, timeout) from the caller and only validates that the
-- script_path matches a whitelisted prefix. It does NOT read any operation
-- catalog — that lives in Odoo (saas.product.operation).
--
-- Lock model: SELECT FOR UPDATE on instances(instance_id) during dispatch
-- prevents concurrent operations on the same host. A new dispatch on an
-- instance with a pending/in_progress task gets rejected with 409 Conflict.
-- =============================================================================

CREATE TABLE IF NOT EXISTS tasks (
    id                TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    instance_id       TEXT NOT NULL REFERENCES instances(instance_id),
    operation_code    TEXT NOT NULL,
    script_path       TEXT NOT NULL,
    script_args       JSONB NOT NULL DEFAULT '[]',
    timeout_seconds   INTEGER NOT NULL,
    status            TEXT NOT NULL DEFAULT 'pending',
    ssm_command_id    TEXT,
    result            JSONB,
    error             TEXT,
    idempotency_key   TEXT,
    started_at        TIMESTAMPTZ,
    completed_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT tasks_status_valid CHECK (status IN ('pending', 'in_progress', 'done', 'failed'))
);

-- Index names are prefixed with `idx_cp_` (control plane) to avoid collisions
-- with indexes defined on the legacy task_queue_log table in init.sql (which
-- currently uses idx_tasks_instance / idx_tasks_state). task_queue_log is
-- vestigial and will be removed in Sprint 6; once gone, these can be renamed.
CREATE INDEX IF NOT EXISTS idx_cp_tasks_instance ON tasks(instance_id);
CREATE INDEX IF NOT EXISTS idx_cp_tasks_status ON tasks(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cp_tasks_idempotency
    ON tasks(instance_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
