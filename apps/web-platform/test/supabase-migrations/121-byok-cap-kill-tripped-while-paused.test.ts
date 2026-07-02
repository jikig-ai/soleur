import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for
// 121_byok_cap_kill_tripped_while_paused.sql (feat-l5-runaway-guard PR-A).
//
// The P0-A fix: 061's `record_byok_use_and_check_cap` set kill_tripped ONLY
// on the NULL→set transition (`v_paused_at IS NULL AND v_total > v_cap`), so
// an already-paused founder's next spawn returned kill_tripped=false and KEPT
// SPENDING. 121 makes kill_tripped reflect the PAUSED STATE — true whenever
// runtime_paused_at IS NOT NULL — a defense-in-depth backstop behind the
// handler's spawn-entry gate (AC1).
//
// vitest mocks `.rpc` and CANNOT observe live SQL behavior (per
// 2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md), so this
// source-shape assertion is the canonical PR-time gate. The behavioral
// invariant (paused founder → zero new audit_byok_use rows via the run) is
// proven at the handler layer + at apply time against dev.

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const up = readFileSync(
  path.join(MIG_DIR, "121_byok_cap_kill_tripped_while_paused.sql"),
  "utf8",
);
const down = readFileSync(
  path.join(MIG_DIR, "121_byok_cap_kill_tripped_while_paused.down.sql"),
  "utf8",
);

// Line comments would false-match structural assertions; strip them.
const upCode = up.replace(/--[^\n]*/g, "");
const downCode = down.replace(/--[^\n]*/g, "");

describe("migration 121 — kill_tripped while paused", () => {
  it("is a body-only CREATE OR REPLACE that preserves the 6-arg return type", () => {
    expect(upCode).toMatch(
      /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_byok_use_and_check_cap/,
    );
    // Return type MUST be unchanged — CREATE OR REPLACE cannot change a
    // function's return type, and changing the signature would strand
    // rolling-deploy callers.
    expect(upCode).toMatch(
      /RETURNS\s+TABLE\(\s*cumulative_cents\s+int\s*,\s*kill_tripped\s+boolean\s*\)/,
    );
    // No DROP of the live 6-arg signature (would break the wrapper mid-deploy).
    expect(upCode).not.toMatch(
      /DROP\s+FUNCTION[^\n;]*record_byok_use_and_check_cap\s*\(\s*uuid\s*,\s*uuid\s*,\s*uuid/,
    );
  });

  it("trips the kill switch unconditionally while paused (P0-A fix)", () => {
    // A branch that sets v_tripped := true when paused, NOT gated on the
    // cap comparison. This is the structural difference from 061.
    expect(upCode).toMatch(
      /IF\s+v_paused_at\s+IS\s+NOT\s+NULL\s+THEN[\s\S]{0,120}v_tripped\s*:=\s*true/,
    );
  });

  it("never clears runtime_paused_at — set-never-clear contract (AC2)", () => {
    // The cap RPC is a WRITER/READER of the pause, never a clearer. The
    // ONLY clearer is the operator-resume route.
    expect(upCode).not.toMatch(/runtime_paused_at\s*=\s*NULL/i);
  });

  it("keeps the SECURITY DEFINER hardening (search_path pin + named REVOKE)", () => {
    expect(upCode).toMatch(/SECURITY\s+DEFINER/);
    expect(upCode).toMatch(/SET\s+search_path\s*=\s*public\s*,\s*pg_temp/);
    expect(upCode).toMatch(
      /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.record_byok_use_and_check_cap\([^)]*\)\s*FROM\s+PUBLIC,\s*anon,\s*authenticated/,
    );
    expect(upCode).toMatch(
      /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.record_byok_use_and_check_cap\([^)]*\)\s*TO\s+service_role/,
    );
  });

  it("down.sql restores the 061 transition-only behavior", () => {
    expect(downCode).toMatch(
      /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.record_byok_use_and_check_cap/,
    );
    // Transition-only guard: flip only on the NULL→set edge.
    expect(downCode).toMatch(
      /v_paused_at\s+IS\s+NULL\s+AND\s+v_total\s*>\s*v_cap/,
    );
  });
});
