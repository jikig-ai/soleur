import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const root = join(__dirname, "..", "..", "supabase", "migrations");
const migration = readFileSync(join(root, "138_agent_engine_runs.sql"), "utf8");
const accountDelete = readFileSync(join(__dirname, "..", "..", "server", "account-delete.ts"), "utf8");

describe("agent-engine account deletion boundary", () => {
  it("allows identity columns to be anonymized while preserving run lineage", () => {
    expect(migration).toMatch(/updated_by uuid NULL REFERENCES public\.users/);
    expect(migration).toMatch(/created_by uuid NULL REFERENCES public\.users/);
    expect(migration).toMatch(/CREATE OR REPLACE FUNCTION public\.anonymise_agent_engine_data/);
    expect(migration).toMatch(/REVOKE ALL ON FUNCTION public\.anonymise_agent_engine_data/);
    expect(migration).toMatch(/GRANT EXECUTE ON FUNCTION public\.anonymise_agent_engine_data\(uuid\) TO service_role/);
  });

  it("runs engine anonymization before auth deletion", () => {
    const anonymize = accountDelete.indexOf('"anonymise_agent_engine_data"');
    const authDelete = accountDelete.indexOf("service.auth.admin.deleteUser");
    expect(anonymize).toBeGreaterThan(-1);
    expect(anonymize).toBeLessThan(authDelete);
  });
});
