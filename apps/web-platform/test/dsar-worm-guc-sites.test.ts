import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";

// WORM-bypass surface gate per `feat-dsar-art15-export-endpoint` AC29 + S1.
//
// The `dsar_export_audit_pii` WORM trigger allows UPDATE/DELETE only when
// the GUC `app.dsar_audit_anonymise_in_progress` is set AND `current_user
// = 'service_role'`. The "function OID allowlist" component of AC29 is
// enforced by this file-parse lint: it asserts the `SET ...
// app.dsar_audit_anonymise_in_progress` token appears EXACTLY ONCE
// across the entire codebase (in the body of the
// `anonymise_dsar_export_audit_pii` RPC inside migration 041).
//
// Prevents:
//   - Accidental WORM-bypass surface widening (a second SET site that
//     could be reached by an unrelated code path).
//   - Cargo-culted reuse of the GUC name in other features that would
//     inadvertently grant WORM-bypass to a different caller.
//
// Failure mode this catches:
//   A future developer adds `SET app.dsar_audit_anonymise_in_progress
//   = 'on'` to a stored procedure or session-config wrapper without
//   reading the AC29 design rationale. The trigger silently grants
//   bypass; the test fails CI before the change merges.

const GUC_NAME = "app.dsar_audit_anonymise_in_progress";
const REPO_ROOT = path.join(__dirname, "..");

// Scan all source roots that could plausibly contain the SET site or a
// shadow of it. We INCLUDE migrations + server code + app routes +
// scripts; we EXCLUDE node_modules + .next + tests (the GUC name will
// appear in this test file itself plus the worm-trigger test).
const SOURCE_ROOTS = [
  "supabase/migrations",
  "server",
  "app",
  "lib",
  "components",
  "scripts",
];

const EXCLUDE_DIR_NAMES = new Set([
  "node_modules",
  ".next",
  "dist",
  "build",
  ".turbo",
]);

function walkFiles(dir: string, acc: string[]): void {
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return;
  }
  for (const e of entries) {
    if (EXCLUDE_DIR_NAMES.has(e)) continue;
    const full = path.join(dir, e);
    let st;
    try {
      st = statSync(full);
    } catch {
      continue;
    }
    if (st.isDirectory()) {
      walkFiles(full, acc);
    } else if (st.isFile()) {
      if (/\.(ts|tsx|js|jsx|mjs|cjs|sql)$/.test(e)) {
        acc.push(full);
      }
    }
  }
}

// Restricted to a single SET form: `SET ... app.dsar_audit_anonymise_in_progress`.
// We tolerate `SET LOCAL`, `SET SESSION`, `SET ...`, and the trailing
// `= '<value>'` so the test focuses on the SET-site count, not the
// assigned value (the trigger's gate is presence + service_role).
const SET_SITE_REGEX =
  /\bSET\s+(?:LOCAL\s+|SESSION\s+)?app\.dsar_audit_anonymise_in_progress\b/gi;

// READ sites (the trigger reading the GUC via current_setting) are
// allowed and unbounded; we don't count them against the SET budget.
// Just ensure the regex is anchored on SET only.

describe("dsar-worm-guc-sites (AC29 + S1)", () => {
  const files: string[] = [];
  for (const root of SOURCE_ROOTS) {
    walkFiles(path.join(REPO_ROOT, root), files);
  }

  const setSites: Array<{ file: string; lineNo: number; snippet: string }> = [];
  for (const f of files) {
    const txt = readFileSync(f, "utf8");
    for (const m of txt.matchAll(SET_SITE_REGEX)) {
      const idx = m.index ?? 0;
      const before = txt.slice(0, idx);
      const lineNo = before.split("\n").length;
      const lineStart = before.lastIndexOf("\n") + 1;
      const lineEnd = txt.indexOf("\n", idx);
      const snippet = txt.slice(lineStart, lineEnd === -1 ? undefined : lineEnd);
      setSites.push({
        file: path.relative(REPO_ROOT, f),
        lineNo,
        snippet: snippet.trim(),
      });
    }
  }

  it("scanned at least one source root (sanity)", () => {
    expect(files.length).toBeGreaterThan(0);
  });

  it(`finds exactly one SET site for ${GUC_NAME}`, () => {
    expect(
      setSites,
      `Expected exactly 1 SET-site for ${GUC_NAME} (inside anonymise_dsar_export_audit_pii RPC body); found ${setSites.length}:\n${setSites
        .map((s) => `  ${s.file}:${s.lineNo}  ${s.snippet}`)
        .join("\n")}`,
    ).toHaveLength(1);
  });

  it("the single SET site lives in migration 041_dsar_export_jobs.sql", () => {
    expect(setSites).toHaveLength(1);
    expect(setSites[0]!.file).toMatch(
      /supabase\/migrations\/041_dsar_export_jobs\.sql$/,
    );
  });
});
