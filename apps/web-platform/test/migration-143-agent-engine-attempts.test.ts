import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

const root = path.join(__dirname, "../supabase/migrations");
const read = (file: string) => readFileSync(path.join(root, file), "utf8");

describe("migration 143: durable engine turn attempts", () => {
  it("separates attempts from immutable conversation bindings and cascades erasure", () => {
    const sql = read("143_agent_engine_attempts.sql");
    expect(sql).toMatch(/CREATE TABLE public\.agent_engine_attempts/);
    expect(sql).toMatch(/run_id uuid NOT NULL REFERENCES public\.agent_engine_runs\(id\) ON DELETE CASCADE/);
    expect(sql).toMatch(/UNIQUE \(run_id, attempt_key\)/);
    expect(sql).toMatch(/REVOKE ALL ON TABLE public\.agent_engine_attempts FROM anon, authenticated/);
    expect(sql).toMatch(/attempt_id uuid REFERENCES public\.agent_engine_attempts\(id\) ON DELETE CASCADE/);
    expect(sql).not.toMatch(/UPDATE public\.agent_engine_runs\s+SET status/);
  });

  it("rejects replaying an already-used attempt key instead of returning the old attempt", () => {
    const sql = read("143_agent_engine_attempts.sql");
    expect(sql).toMatch(/ON CONFLICT \(run_id, attempt_key\) DO NOTHING/);
    expect(sql).toMatch(/attempt key already exists/);
  });

  it("allows only forward attempt transitions and keeps terminal rows immutable", () => {
    const sql = read("143_agent_engine_attempts.sql");
    expect(sql).toMatch(/WHEN 'queued' THEN p_status IN \('running','cancel_requested','failed','cancelled'\)/);
    expect(sql).toMatch(/WHEN 'running' THEN p_status IN \('waiting','cancel_requested','completed','failed','cancelled'\)/);
    expect(sql).toMatch(/WHEN 'waiting' THEN p_status IN \('running','cancel_requested','failed','cancelled'\)/);
    expect(sql).toMatch(/WHEN 'cancel_requested' THEN p_status IN \('completed','failed','cancelled'\)/);
    expect(sql).toMatch(/terminal engine attempt is immutable/);
  });

  it("allocates event sequence under a row lock and stores bounded lifecycle metadata only", () => {
    const sql = read("143_agent_engine_attempts.sql");
    expect(sql).toMatch(/FOR UPDATE/);
    expect(sql).toMatch(/INSERT INTO public\.agent_engine_events/);
    expect(sql).toMatch(/source_type' NOT IN \('status','approval','error'\)/);
    expect(sql).toMatch(/p_payload - 'type' - 'source_type' - 'status'/);
  });

  it("protects native checkpoints from member reads and writes", () => {
    const sql = read("143_agent_engine_attempts.sql");
    expect(sql).toMatch(/CREATE TABLE public\.agent_engine_recovery_checkpoints/);
    expect(sql).toMatch(/REVOKE ALL ON TABLE public\.agent_engine_recovery_checkpoints FROM anon, authenticated/);
    expect(sql).toMatch(/ENABLE ROW LEVEL SECURITY/);
    expect(sql).toMatch(/auth\.role\(\) <> 'service_role'/);
    expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.get_agent_engine_recovery_checkpoint\(uuid\) TO service_role/);
    expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.save_agent_engine_recovery_checkpoint\(uuid, jsonb\) TO service_role/);
    expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.start_agent_engine_attempt\(uuid, text\) TO service_role/);
    expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.append_agent_engine_lifecycle_event\(uuid, uuid, jsonb\) TO service_role/);
    expect(sql).toMatch(/SET search_path = public, pg_temp/);
  });

  it("has a down migration", () => {
    const down = read("143_agent_engine_attempts.down.sql");
    expect(down).toMatch(/DROP TABLE IF EXISTS public\.agent_engine_recovery_checkpoints/);
    expect(down).toMatch(/DROP TABLE IF EXISTS public\.agent_engine_attempts/);
  });
});
