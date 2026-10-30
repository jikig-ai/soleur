import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape test for 178_api_data_grants_narrowing.sql (#11193 —
// ADR-303 §Consequences' deferred narrowing of the default-era api-role
// grants migration 174 reproduced verbatim from prd).
//
// File-parse test, not a live-DB test: it pins the SQL contract — every
// narrowed relation gets a `DO $$ to_regclass` precondition block, every
// REVOKE precedes its block's re-GRANTs (a later REVOKE ALL would strip
// them — Guard Contract matrix row 5), the verify file carries the
// check_name/bad contract with coverage of every narrowed relation, and the
// `users` column-grant list matches the Note C census. Live posture is
// proven by verify/178 (run-verify.sh) and the RLS_FUZZ_LOCAL=1 rls-grants
// gate's held==registered assertion over the table-grants.ts OVERRIDES.
//
// Plan: 2026-10-26-chore-narrow-default-era-api-grants-plan.md.

const ROOT = path.resolve(__dirname, "../..");
const UP_PATH = path.join(ROOT, "supabase/migrations/178_api_data_grants_narrowing.sql");
const DOWN_PATH = path.join(ROOT, "supabase/migrations/178_api_data_grants_narrowing.down.sql");
const VERIFY_PATH = path.join(ROOT, "supabase/verify/178_api_data_grants_narrowing.sql");

const stripComments = (sql: string) =>
  sql.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--[^\n]*/g, "");

const up = readFileSync(UP_PATH, "utf8");
const upExec = stripComments(up);
const downExec = stripComments(readFileSync(DOWN_PATH, "utf8"));
const verifyExec = stripComments(readFileSync(VERIFY_PATH, "utf8"));

const FULL_VERBS =
  "DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE";

/** The Note C census: authenticated's complete column-level UPDATE set on users. */
const USERS_CENSUS_COLS = [
  "email",
  "onboarding_completed_at",
  "pwa_banner_dismissed_at",
  "runtime_explainer_dismissed_at",
  "nudges_dismissed",
] as const;

interface RelationSpec {
  rel: string;
  /** Roles named in the block's `REVOKE ALL … FROM` list. */
  revokeFrom: string;
  /** authenticated keeps SELECT → the block re-grants it. */
  regrantAuthSelect: boolean;
}

const RELATIONS: RelationSpec[] = [
  { rel: "_schema_migrations", revokeFrom: "anon, authenticated, service_role", regrantAuthSelect: false },
  { rel: "api_keys", revokeFrom: "anon, authenticated", regrantAuthSelect: true },
  { rel: "audit_byok_use", revokeFrom: "anon, authenticated", regrantAuthSelect: true },
  { rel: "audit_github_token_use", revokeFrom: "anon, authenticated", regrantAuthSelect: true },
  { rel: "dsar_export_jobs", revokeFrom: "anon, authenticated", regrantAuthSelect: true },
  { rel: "flag_flip_audit", revokeFrom: "anon, authenticated", regrantAuthSelect: false },
];

/** Extract the body of a relation's `DO $$ … to_regclass precondition … $$` block. */
function doBlockFor(sql: string, rel: string): string | null {
  const re = new RegExp(
    `DO\\s+\\$\\$\\s*BEGIN\\s+IF\\s+to_regclass\\('public\\."${rel}"'\\)\\s+IS\\s+NOT\\s+NULL\\s+THEN([\\s\\S]*?)END\\s+IF;\\s*END\\s+\\$\\$`,
    "i",
  );
  return sql.match(re)?.[1] ?? null;
}

describe("migration 178_api_data_grants_narrowing", () => {
  it("references the driving issue", () => {
    expect(up).toMatch(/#11193/);
  });

  it("has no transaction control (the runner wraps the file)", () => {
    expect(upExec).not.toMatch(/^\s*BEGIN\s*;/im);
    expect(upExec).not.toMatch(/^\s*COMMIT\s*;/im);
    expect(upExec).not.toMatch(/\bCONCURRENTLY\b/i);
  });

  for (const { rel, revokeFrom, regrantAuthSelect } of RELATIONS) {
    it(`${rel}: sits behind a to_regclass('public."${rel}"') precondition`, () => {
      expect(doBlockFor(upExec, rel), `${rel} DO block`).not.toBeNull();
    });

    it(`${rel}: REVOKE ALL … FROM ${revokeFrom}`, () => {
      const block = doBlockFor(upExec, rel)!;
      const roles = revokeFrom.split(/,\s*/).join("\\s*,\\s*");
      expect(block).toMatch(
        new RegExp(
          `REVOKE\\s+ALL\\s+ON\\s+TABLE\\s+public\\."${rel}"\\s+FROM\\s+${roles}`,
          "i",
        ),
      );
    });

    it(`${rel}: every GRANT inside the block comes after the REVOKE`, () => {
      const block = doBlockFor(upExec, rel)!;
      const revokeIdx = block.search(/\bREVOKE\b/i);
      const firstGrantIdx = block.search(/\bGRANT\b/i);
      expect(revokeIdx).toBeGreaterThanOrEqual(0);
      if (regrantAuthSelect) {
        expect(firstGrantIdx, `${rel} re-GRANT must follow the REVOKE`).toBeGreaterThan(revokeIdx);
      }
    });

    if (regrantAuthSelect) {
      it(`${rel}: re-grants exactly SELECT to authenticated (no other re-grant)`, () => {
        const block = doBlockFor(upExec, rel)!;
        expect(block).toMatch(
          new RegExp(`GRANT\\s+SELECT\\s+ON\\s+TABLE\\s+public\\."${rel}"\\s+TO\\s+authenticated`, "i"),
        );
        expect(block.match(/\bGRANT\b/gi)?.length, `${rel} must carry exactly one re-GRANT`).toBe(1);
      });
    } else {
      it(`${rel}: carries no re-GRANT`, () => {
        const block = doBlockFor(upExec, rel)!;
        expect(block).not.toMatch(/\bGRANT\b/i);
      });
    }
  }

  describe("users re-narrowing (restores 006's intent + the Note C census)", () => {
    it("sits behind a to_regclass precondition", () => {
      expect(doBlockFor(upExec, "users")).not.toBeNull();
    });

    it("REVOKE ALL … FROM anon and FROM authenticated precede every re-GRANT", () => {
      const block = doBlockFor(upExec, "users")!;
      const lastRevoke = Math.max(
        ...[...block.matchAll(/\bREVOKE\b/gi)].map((m) => m.index!),
      );
      const firstGrant = block.search(/\bGRANT\b/i);
      expect(block).toMatch(/REVOKE\s+ALL\s+ON\s+TABLE\s+public\."users"\s+FROM\s+anon/i);
      expect(block).toMatch(/REVOKE\s+ALL\s+ON\s+TABLE\s+public\."users"\s+FROM\s+authenticated/i);
      expect(firstGrant).toBeGreaterThan(lastRevoke);
    });

    it("re-grants SELECT to authenticated", () => {
      const block = doBlockFor(upExec, "users")!;
      expect(block).toMatch(/GRANT\s+SELECT\s+ON\s+TABLE\s+public\."users"\s+TO\s+authenticated/i);
    });

    it("re-grants UPDATE on exactly the census column set", () => {
      const block = doBlockFor(upExec, "users")!;
      const m = block.match(
        /GRANT\s+UPDATE\s*\(([^)]*)\)\s+ON\s+TABLE\s+public\."users"\s+TO\s+authenticated/i,
      );
      expect(m, "users column-level UPDATE GRANT").not.toBeNull();
      const cols = m![1]!.split(",").map((c) => c.trim().replace(/^"|"$/g, ""));
      expect([...cols].sort()).toEqual([...USERS_CENSUS_COLS].sort());
    });

    it("does NOT column-grant kb_sync_history (017's RESTRICTIVE policy pins it; append_kb_sync_row owns the write)", () => {
      const block = doBlockFor(upExec, "users")!;
      expect(block).not.toMatch(/kb_sync_history/i);
    });
  });

  describe("untouched relations", () => {
    for (const rel of ["runtime_mint_intent", "dsar_export_audit_pii"]) {
      it(`${rel} is untouched (already narrow — 049 / 175)`, () => {
        expect(doBlockFor(upExec, rel)).toBeNull();
        expect(upExec).not.toMatch(new RegExp(`ON\\s+TABLE\\s+public\\."${rel}"`, "i"));
      });
    }
  });
});

describe("migration 178 down", () => {
  for (const { rel, revokeFrom } of RELATIONS) {
    it(`restores the 174 full-DML verb set on ${rel} for ${revokeFrom}`, () => {
      const verbs = FULL_VERBS.split(/,\s*/).join("\\s*,\\s*");
      const roles = revokeFrom.split(/,\s*/).join("\\s*,\\s*");
      expect(downExec).toMatch(
        new RegExp(
          `GRANT\\s+${verbs}\\s+ON\\s+TABLE\\s+public\\."${rel}"\\s+TO\\s+${roles}`,
          "i",
        ),
      );
    });
  }

  it("restores the 174 full-DML verb set on users for anon, authenticated (column grants revoked first)", () => {
    const block = doBlockFor(downExec, "users");
    expect(block).not.toBeNull();
    // Column-level grants survive a table-level REVOKE (attacl is separate
    // from relacl) — restoring the exact 174 posture means clearing them
    // before re-granting the full verb set.
    expect(block).toMatch(/REVOKE\s+UPDATE\s*\([^)]*\)\s+ON\s+TABLE\s+public\."users"\s+FROM\s+authenticated/i);
    const verbs = FULL_VERBS.split(/,\s*/).join("\\s*,\\s*");
    expect(block).toMatch(
      new RegExp(`GRANT\\s+${verbs}\\s+ON\\s+TABLE\\s+public\\."users"\\s+TO\\s+anon\\s*,\\s*authenticated`, "i"),
    );
  });
});

describe("verify 178_api_data_grants_narrowing", () => {
  it("conforms to the (check_name, bad) two-column contract", () => {
    expect(verifyExec).toMatch(/as\s+check_name/i);
    expect(verifyExec).toMatch(/\bas\s+bad\b|,\s*bad\b/i);
  });

  it.each([...RELATIONS.map((r) => r.rel), "users"])(
    "carries at least one check_name row for %s",
    (rel) => {
      expect(verifyExec).toMatch(new RegExp(`'[a-z_]*${rel}[a-z_]*'`, "i"));
    },
  );

  for (const rel of ["api_keys", "audit_byok_use", "audit_github_token_use", "dsar_export_jobs", "flag_flip_audit", "users"]) {
    it(`asserts the kept service_role grant set on ${rel}`, () => {
      expect(verifyExec).toMatch(
        new RegExp(`has_table_privilege\\(\\s*'service_role'\\s*,\\s*'public\\."${rel}"'`, "i"),
      );
    });
  }

  for (const rel of ["api_keys", "audit_byok_use", "audit_github_token_use", "dsar_export_jobs", "users"]) {
    it(`asserts the kept authenticated SELECT on ${rel}`, () => {
      expect(verifyExec).toMatch(
        new RegExp(`has_table_privilege\\(\\s*'authenticated'\\s*,\\s*'public\\."${rel}"'\\s*,\\s*'SELECT'\\s*\\)`, "i"),
      );
    });
  }

  for (const col of USERS_CENSUS_COLS) {
    it(`asserts the kept authenticated column UPDATE on users.${col}`, () => {
      expect(verifyExec).toMatch(
        new RegExp(`has_column_privilege\\(\\s*'authenticated'\\s*,\\s*'public\\."users"'\\s*,\\s*'${col}'\\s*,\\s*'UPDATE'\\s*\\)`, "i"),
      );
    });
  }

  it("asserts authenticated holds NO table-level UPDATE on users", () => {
    expect(verifyExec).toMatch(
      /has_table_privilege\(\s*'authenticated'\s*,\s*'public\."users"'\s*,\s*'UPDATE'\s*\)/i,
    );
  });

  it("carries the complement sweep over attacl (no uncovered column grants)", () => {
    // Table-level REVOKE ALL does not clear attacl — the sentinel must probe
    // the complement, not just the enumerated universe. Pin the row name and
    // that it scopes to the seven narrowed relations via pg_attribute.
    expect(verifyExec).toMatch(/no_uncovered_col_grants_narrowed/i);
    expect(verifyExec).toMatch(/aclexplode|pg_attribute/i);
    for (const col of USERS_CENSUS_COLS) {
      expect(verifyExec).toMatch(new RegExp(`'${col}'`, "i"));
    }
  });
});
