// #9089 / ADR-256 — the JS half of the shared filing predicate. The interactive
// gate classifies with `.claude/hooks/lib/filing-shape.pl --classify`; the cron
// hook (and the deny marker, by import) with `filingShape()`. The two are bound
// ONLY through this corpus, which `filing-shape.test.sh` runs through the Perl
// side. A row that passes there and fails here is the two gates drifting.
//
// Repo-wide suite (test/repo-wide-suites.ts): the corpus lives under
// `.claude/hooks/lib/`, so a diff touching only that directory must still run
// this file.
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { filingShape } from "../../../server/inngest/cron-bash-allowlist-hook.mjs";

type Shape = "create" | "api" | "none";
interface CorpusRow {
  id: string;
  tokens: string[];
  shape: Shape;
  why: string;
}

// test/server/inngest -> repo root is five levels up.
const CORPUS = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../../../.claude/hooks/lib/filing-shape-corpus.json",
);

const rows = (JSON.parse(readFileSync(CORPUS, "utf8")) as Array<Partial<CorpusRow> & { _doc?: string }>)
  .filter((r) => !("_doc" in r)) as CorpusRow[];

// Floors count EXECUTED rows, not file rows: a loader that returns [] or a
// loop that asserts only the first row must go red (G3-4, G3-5).
let ran = 0;
const classes = new Set<Shape>();

describe("filingShape() matches the shared corpus (ADR-256)", () => {
  it.each(rows.map((r) => [r.id, r] as const))("%s", (_id, row) => {
    const got = (filingShape(row.tokens) as Shape | null) ?? "none";
    expect(got, `${row.id} ${JSON.stringify(row.tokens)} — ${row.why}`).toBe(row.shape);
    ran++;
    classes.add(row.shape);
  });

  afterAll(() => {
    expect(ran).toBeGreaterThanOrEqual(100);
    expect([...classes].sort()).toEqual(["api", "create", "none"]);
  });
});
