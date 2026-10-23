import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import {
  GIT_DATA_ERASURE_HOST_OUTCOMES,
  GIT_DATA_ERASURE_LEDGER_EXTRA_OUTCOMES,
  GIT_DATA_ERASURE_LEDGER_OUTCOMES,
} from "../server/git-data-erasure-ledger";
import type { GitDataErasureOutcome } from "../server/git-data-replication";

// The first cut restated the outcome words by hand in SQL, TS and tests (and spelled one of them
// differently from the Sentry tag, so a write raised 23514 and the row was lost). This test DERIVES
// the words from the GitDataErasureOutcome union and compares every restatement to it:
//   union (source text) -> TS constants -> migration CHECK -> verify sentinel -> cron + account-delete.
// 'threw' and 'seeded' are the two DELIBERATE extras beyond the union.

const root = path.resolve(__dirname, "..");
const read = (rel: string) => readFileSync(path.join(root, rel), "utf8");
const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'`])\/\/.*$/gm, "$1").replace(/--[^\n]*/g, "");

// Compile-time: an exhaustive map over the union's non-terminal statuses (tsc fails on drift).
type NonTerminal = Exclude<GitDataErasureOutcome, { status: "erased" } | { status: "skipped" }>["status"];
const COMPILE_TIME_PARITY = {
  refused: true, unreachable: true, unauthorized: true, unconfigured: true, host_key_mismatch: true,
} as const satisfies Record<NonTerminal, true>;

function unionStatuses(): string[] {
  const src = read("server/git-data-replication.ts");
  const start = src.indexOf("export type GitDataErasureOutcome =");
  expect(start, "union declaration").toBeGreaterThan(-1);
  const end = src.indexOf(";\n", src.indexOf("host_key_mismatch", start));
  const body = strip(src.slice(start, end + 1));
  return [...body.matchAll(/status:\s*"([a-z_]+)"/g)].map((m) => m[1]);
}

function migrationWords(): string[] {
  const sql = strip(read("supabase/migrations/164_git_data_erasure_pending.sql"));
  const m = sql.match(/last_outcome\s+text\s+CHECK\s*\(\s*last_outcome\s+IN\s*\(([^)]*)\)\s*\)/i);
  expect(m, "migration CHECK").not.toBeNull();
  return [...m![1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]);
}

describe("git-data erasure outcome words: one source of truth", () => {
  const all = unionStatuses();
  const derived = all.filter((s) => s !== "erased" && s !== "skipped");

  it("reads a plausible union (guards the source-text parse against going vacuous)", () => {
    expect(all).toEqual(expect.arrayContaining(["skipped", "erased", "refused", "unauthorized", "unconfigured", "unreachable", "host_key_mismatch"]));
    expect(derived.length).toBeGreaterThanOrEqual(5);
  });

  it("the TS host-outcome constant equals the union's non-terminal statuses (and the compile-time map)", () => {
    expect([...GIT_DATA_ERASURE_HOST_OUTCOMES].sort()).toEqual([...derived].sort());
    expect(Object.keys(COMPILE_TIME_PARITY).sort()).toEqual([...derived].sort());
  });

  it("the ledger constant is the union plus exactly the two named extras, threw and seeded", () => {
    expect([...GIT_DATA_ERASURE_LEDGER_EXTRA_OUTCOMES]).toEqual(["threw", "seeded"]);
    expect([...GIT_DATA_ERASURE_LEDGER_OUTCOMES].sort()).toEqual([...derived, "threw", "seeded"].sort());
  });

  it("the migration CHECK lists exactly the ledger constant's words", () => {
    expect(migrationWords().sort()).toEqual([...GIT_DATA_ERASURE_LEDGER_OUTCOMES].sort());
  });

  it("the verify sentinel's CHECK text lists the same words in the same order as the migration", () => {
    const verify = strip(read("supabase/verify/164_git_data_erasure_pending.sql"));
    const m = verify.match(/last_outcome = ANY \(ARRAY\[([^\]]*)\]/);
    const words = [...(m?.[1] ?? "").matchAll(/''([a-z_]+)''::text/g)].map((x) => x[1]);
    expect(words).toEqual(migrationWords());
  });

  it("account-delete's thrown arm tags AND records the same word 'threw' (one spelling, not two)", () => {
    const ad = strip(read("server/account-delete.ts"));
    expect(ad).toContain('erasure_outcome: "threw"');
    expect(ad).toMatch(/recordGitDataErasurePendingBestEffort\(service, userId, "threw"\)/);
    expect(ad).not.toContain('"thrown"');
  });

  it("the cron derives its host-status set from the constant instead of a hand-copied list", () => {
    const cron = strip(read("server/inngest/functions/cron-git-data-erasure-redrive.ts"));
    expect(cron).toMatch(/new Set<string>\(GIT_DATA_ERASURE_HOST_OUTCOMES\)/);
    for (const w of derived) expect(cron, `cron must not restate "${w}"`).not.toContain(`"${w}"`);
    expect(cron).toContain('word = "threw"');
    expect(cron).not.toContain('"thrown"');
  });
});
