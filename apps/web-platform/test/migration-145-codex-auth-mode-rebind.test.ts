import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";

const root = path.join(__dirname, "../supabase/migrations");
const read = (file: string) => readFileSync(path.join(root, file), "utf8");

describe("migration 145: Codex auth-mode rebinding", () => {
  it("keeps the already-applied migration 144 byte-identical and applies only its delta", () => {
    const applied = readFileSync(path.join(root, "144_codex_auth_mode_rebind.sql"));
    const gitBlob = createHash("sha1")
      .update(Buffer.concat([Buffer.from(`blob ${applied.length}\0`), applied]))
      .digest("hex");
    expect(gitBlob).toBe("be38bcb39d313de4e24ba44f02cdb47aebc3f00b");

    const delta = read("145_codex_auth_mode_rebind.sql");
    expect(delta).not.toMatch(/ADD COLUMN auth_mode_generation/);
    expect(delta).toMatch(/ADD COLUMN accepted_at/);
    expect(delta).toMatch(/ADD COLUMN codex_auth_mode/);
  });

  it("makes the explicit owner choice atomic with Codex conversation rebinding", () => {
    const sql = read("145_codex_auth_mode_rebind.sql");
    expect(sql).toMatch(/BEGIN;\s+SET LOCAL lock_timeout = '30s';\s+SET LOCAL statement_timeout = '5min';/);
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.set_workspace_default_engine\(/);
    expect(sql).toMatch(/p_apply_to_existing_codex_conversations boolean DEFAULT false/);
    expect(sql).toMatch(/p_expected_affected_count integer DEFAULT NULL/);
    expect(sql).toMatch(/ADD COLUMN codex_auth_mode text NOT NULL DEFAULT 'managed'/);
    expect(sql).toMatch(/UPDATE public\.workspace_engine_settings AS settings[\s\S]*SET codex_auth_mode = CASE\s+WHEN settings\.default_engine_id = 'codex' THEN settings\.default_auth_mode/);
    expect(sql).toMatch(/settings\.default_engine_id = 'codex'[\s\S]*OR EXISTS/);
    expect(sql).toMatch(/codex_auth_mode = CASE WHEN p_engine_id = 'codex' OR p_apply_to_existing_codex_conversations THEN p_auth_mode/);
    expect(sql).toMatch(/PERFORM 1 FROM public\.workspaces AS w WHERE w\.id = p_workspace_id FOR UPDATE[\s\S]*SELECT \* INTO v_setting[\s\S]*FROM public\.workspace_engine_settings[\s\S]*FOR UPDATE/);
    expect(sql).toMatch(/CASE WHEN p_apply_to_existing_codex_conversations\s+THEN COALESCE\(v_setting\.default_engine_id, 'claude-code'\)/);
    expect(sql).toMatch(/CASE WHEN p_apply_to_existing_codex_conversations\s+THEN COALESCE\(v_setting\.default_auth_mode, 'managed'\)/);
    expect(sql).toMatch(/SET default_engine_id = CASE WHEN p_apply_to_existing_codex_conversations[\s\S]*THEN public\.workspace_engine_settings\.default_engine_id/);
    expect(sql).toMatch(/default_auth_mode = CASE WHEN p_apply_to_existing_codex_conversations[\s\S]*THEN public\.workspace_engine_settings\.default_auth_mode/);
    expect(sql).toMatch(/RETURNING \* INTO v_setting[\s\S]*'defaultEngineId', v_setting\.default_engine_id[\s\S]*'defaultAuthMode', v_setting\.default_auth_mode/);
    expect(sql).toMatch(/^CREATE INDEX(?: IF NOT EXISTS)? agent_engine_runs_codex_rebind_idx\s+ON public\.agent_engine_runs \(workspace_id, auth_mode\)\s+WHERE execution_kind = 'conversation' AND engine_id = 'codex'/m);
    expect(sql).toMatch(/public\.is_workspace_owner\(p_workspace_id, auth\.uid\(\)\)/);
    expect(sql).toMatch(/execution_kind = 'conversation'[\s\S]*engine_id = 'codex'[\s\S]*auth_mode_generation/);
    expect(sql).toMatch(/DELETE FROM public\.agent_engine_recovery_checkpoints/);
    expect(sql).toMatch(/affectedConversationCount/);
    expect(sql).toMatch(/affected Codex conversation count changed'[\s\S]*ERRCODE = '40001'/);
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.count_codex_conversation_rebinds/);
    expect(sql).toMatch(/^\s*WHEN p_execution_kind = 'conversation'\s+AND COALESCE\(s\.default_engine_id, 'claude-code'\) = 'codex'\s+THEN s\.codex_auth_mode\s+ELSE COALESCE\(s\.default_auth_mode, 'managed'\)/m);
    expect(sql).toMatch(/bind_agent_engine_run[\s\S]*FOR SHARE/);
    expect(sql).toMatch(/set_workspace_default_engine[\s\S]*FOR UPDATE/);
    expect(sql).toMatch(/SET search_path = public, pg_temp/);
  });

  it("pins every attempt to the generation of its Codex binding", () => {
    const prior = read("144_codex_auth_mode_rebind.sql");
    const sql = read("145_codex_auth_mode_rebind.sql");
    expect(prior).toMatch(/ALTER TABLE public\.agent_engine_runs[\s\S]*ADD COLUMN auth_mode_generation bigint NOT NULL DEFAULT 0/);
    expect(prior).toMatch(/ALTER TABLE public\.agent_engine_attempts[\s\S]*ADD COLUMN auth_mode_generation bigint NOT NULL DEFAULT 0/);
    expect(sql).not.toMatch(/ADD COLUMN auth_mode_generation/);
    expect(sql).toMatch(/start_agent_engine_attempt\(\s*p_run_id uuid, p_attempt_key text, p_expected_auth_mode text, p_expected_generation bigint[\s\S]*FOR UPDATE[\s\S]*v_generation IS DISTINCT FROM p_expected_generation[\s\S]*v_auth_mode IS DISTINCT FROM p_expected_auth_mode/);
    expect(sql).toMatch(/REVOKE ALL ON FUNCTION public\.start_agent_engine_attempt\(uuid, text, text, bigint\)[\s\S]*GRANT EXECUTE ON FUNCTION public\.start_agent_engine_attempt\(uuid, text, text, bigint\) TO service_role/);
    expect(sql).toMatch(/assert_agent_engine_attempt_generation[\s\S]*v_attempt_generation IS DISTINCT FROM v_run_generation/);
    expect(sql).toMatch(/p_attempt_id uuid, p_checkpoint jsonb[\s\S]*v_attempt_generation IS DISTINCT FROM v_run_generation/);
    expect(sql).toMatch(/bind_agent_engine_run[\s\S]*FOR SHARE/);
  });

  it("lets an accepted turn finish after a switch while fencing stale writes and retries", () => {
    const sql = read("145_codex_auth_mode_rebind.sql");
    const accept = sql.match(/^CREATE OR REPLACE FUNCTION public\.assert_agent_engine_attempt_generation\([\s\S]*?^\$\$;/m)?.[0] ?? "";
    const transition = sql.match(/CREATE OR REPLACE FUNCTION public\.transition_agent_engine_attempt\([\s\S]*?^\$\$;/m)?.[0] ?? "";
    const lifecycle = sql.match(/CREATE OR REPLACE FUNCTION public\.append_agent_engine_lifecycle_event\([\s\S]*?^\$\$;/m)?.[0] ?? "";
    const checkpoint = sql.match(/CREATE OR REPLACE FUNCTION public\.save_agent_engine_recovery_checkpoint\([\s\S]*?^\$\$;/m)?.[0] ?? "";

    expect(sql).toMatch(/ALTER TABLE public\.agent_engine_attempts[\s\S]*ADD COLUMN accepted_at timestamptz/);
    expect(accept).toMatch(/^\s*UPDATE public\.agent_engine_attempts AS a[\s\S]*SET accepted_at = COALESCE\(a\.accepted_at, now\(\)\)[\s\S]*AND a\.auth_mode_generation = v_run_generation/m);
    expect(transition).toMatch(/v_row\.accepted_at IS NULL[\s\S]*auth_mode_generation IS DISTINCT FROM v_run_generation/);
    expect(lifecycle).toMatch(/v_attempt\.accepted_at IS NULL[\s\S]*auth_mode_generation IS DISTINCT FROM v_run_generation/);
    expect(checkpoint).toMatch(/v_attempt_generation IS DISTINCT FROM v_run_generation/);

    const down = read("145_codex_auth_mode_rebind.down.sql");
    expect(down).toMatch(/DROP COLUMN IF EXISTS accepted_at/);
    expect(down).toMatch(/DROP COLUMN IF EXISTS codex_auth_mode/);
    expect(down).toMatch(/CREATE OR REPLACE FUNCTION public\.transition_agent_engine_attempt\([\s\S]*terminal engine attempt is immutable/);
    expect(down).toMatch(/CREATE OR REPLACE FUNCTION public\.append_agent_engine_lifecycle_event\([\s\S]*lifecycle append requires service role/);
  });

  it("commits every lifecycle status and its attempt transition in one RPC", () => {
    const sql = read("147_codex_lifecycle_state_sync.sql");
    const lifecycle = sql.match(/^CREATE OR REPLACE FUNCTION public\.append_agent_engine_lifecycle_event\([\s\S]*?^\$\$;/m)?.[0] ?? "";

    expect(lifecycle).toMatch(/^\s*INSERT INTO public\.agent_engine_events[\s\S]*RETURNING \* INTO v_row/m);
    expect(lifecycle).toMatch(/IF p_payload->>'source_type' = 'status'[\s\S]*p_payload->>'status' IS DISTINCT FROM v_attempt\.status THEN\s+PERFORM public\.transition_agent_engine_attempt\(p_attempt_id, p_payload->>'status'\)/);
    expect(lifecycle).not.toMatch(/UPDATE public\.agent_engine_attempts AS a SET/);
    const down = read("147_codex_lifecycle_state_sync.down.sql");
    expect(down).toMatch(/FOR UPDATE/);
    expect(down).toMatch(/UPDATE public\.agent_engine_attempts AS a SET[\s\S]*status = p_payload->>'status'/);
  });

  it("keeps applied migrations 145 and 146 immutable and puts lifecycle sync in migration 147", () => {
    const applied = readFileSync(path.join(root, "145_codex_auth_mode_rebind.sql"));
    const gitBlob = createHash("sha1")
      .update(Buffer.concat([Buffer.from(`blob ${applied.length}\0`), applied]))
      .digest("hex");
    expect(gitBlob).toBe("18282434482be03df053d014aa94ad0f153a631b");

    const appliedLifecycle = readFileSync(path.join(root, "146_codex_terminal_lifecycle.sql"));
    const lifecycleBlob = createHash("sha1")
      .update(Buffer.concat([Buffer.from(`blob ${appliedLifecycle.length}\0`), appliedLifecycle]))
      .digest("hex");
    expect(lifecycleBlob).toBe("b006fb01c2544addd8035be4314273e14b7526ab");

    const delta = read("147_codex_lifecycle_state_sync.sql");
    expect(delta).toMatch(/FOR UPDATE/);
    expect(delta).toMatch(/PERFORM public\.transition_agent_engine_attempt\(p_attempt_id, p_payload->>'status'\)/);
  });

  it("restores the prior owner RPC and schema on rollback", () => {
    const down = read("145_codex_auth_mode_rebind.down.sql");
    expect(down).toMatch(/BEGIN;\s+SET LOCAL lock_timeout = '30s';\s+SET LOCAL statement_timeout = '5min';/);
    expect(down).toMatch(/CREATE OR REPLACE FUNCTION public\.set_workspace_default_engine\([\s\S]*p_apply_to_existing_codex_conversations boolean DEFAULT false/);
    expect(down).toMatch(/DROP INDEX IF EXISTS public\.agent_engine_runs_codex_rebind_idx/);
    expect(down).toMatch(/DROP COLUMN IF EXISTS codex_auth_mode/);
    expect(down).toMatch(/CREATE OR REPLACE FUNCTION public\.set_workspace_default_engine\([\s\S]*p_auth_mode text DEFAULT 'managed'/);
    expect(down).not.toMatch(/DROP COLUMN IF EXISTS auth_mode_generation/);
    expect(down).toMatch(/CREATE OR REPLACE FUNCTION public\.save_agent_engine_recovery_checkpoint\([\s\S]*p_run_id uuid, p_attempt_id uuid, p_checkpoint jsonb/);
  });
});
