// RED-first (cq-write-failing-tests-before) tests for the sync coverage summary
// (#7332, plan Phase 3).
//
// Three constraints here are not stylistic — each is a defect this file exists to
// prevent.
//
// 1. WORDING. The report states what Soleur EXPECTS versus what is PRESENT. It
//    never asserts what the business lacks. A committed, timestamped, git-blamed
//    line saying a customer has no privacy policy is discoverable and reads as
//    documented knowledge of non-compliance, in their own repository, permanently
//    — git history is not erasable.
//
// 2. DETERMINISM. No embedded timestamp, stable ordering. An unchanged KB must
//    produce a byte-identical file or every sync emits a one-field diff forever.
//    knowledge-base/INDEX.md is the in-repo warning: a committed generated
//    artifact with no freshness gate whose regen once produced a +993-line
//    unrelated diff. This is that shape, in a repo where we cannot add a CI gate.
//
// 3. NO REPO-IDENTIFYING DATA. The marker carries counts only. ADR-171 records
//    that a self-hosted CLI must never route repository-derived metadata to
//    Soleur infrastructure; this test keeps that claim true in code rather than
//    only in prose, so a future PR that does route these markers somewhere cannot
//    silently ship paths or repo URLs with them.

import { describe, expect, it } from "bun:test";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import {
  EXPECTED_KB_PATHS,
  MARKER_FIELDS,
  PRODUCERS_MARKER,
  assessCoverage,
  formatErrorMarker,
  formatProducersMarker,
  renderCoverageMarkdown,
} from "../lib/kb-coverage";
import { countAutoInferredRows } from "../lib/kb-coverage";
import { writeCoverage } from "../scripts/write-kb-coverage";

const counts = {
  c4_elements: 7,
  c4_relationships: 5,
  domain_model_rows: 3,
  coverage_present: 2,
  coverage_expected: 9,
};

/** Build a throwaway KB root containing exactly `present`. */
function kbRoot(present: string[]): string {
  const root = mkdtempSync(join(tmpdir(), "kbcov-"));
  for (const rel of present) {
    const full = join(root, rel);
    mkdirSync(join(full, ".."), { recursive: true });
    writeFileSync(full, "# synthesized fixture\n");
  }
  return root;
}

describe("assessCoverage", () => {
  it("reports every expected path with a present flag", () => {
    const root = kbRoot([EXPECTED_KB_PATHS[0]]);
    const entries = assessCoverage(root);
    expect(entries.length).toBe(EXPECTED_KB_PATHS.length);
    expect(entries.find((e) => e.path === EXPECTED_KB_PATHS[0])!.present).toBe(true);
    expect(entries.filter((e) => e.present).length).toBe(1);
  });

  it("is order-stable regardless of which paths exist", () => {
    const a = assessCoverage(kbRoot([])).map((e) => e.path);
    const b = assessCoverage(kbRoot([...EXPECTED_KB_PATHS])).map((e) => e.path);
    expect(a).toEqual(b);
    expect(a).toEqual([...a].sort());
  });
});

describe("renderCoverageMarkdown — wording is a hard constraint", () => {
  const body = renderCoverageMarkdown(assessCoverage(kbRoot([EXPECTED_KB_PATHS[0]])), counts);

  // AC12, both halves. Presence of good phrasing is NOT absence of bad phrasing,
  // so both are asserted — a report could easily carry the expectation framing in
  // its header and still emit a deficiency bullet per row.
  it("contains no anchored deficiency bullet", () => {
    expect(body).not.toMatch(/^[-*] *[Mm]issing:/m);
  });

  it("never uses lack/absence framing anywhere", () => {
    expect(body).not.toMatch(/\b(missing|lacks|lacking|absent|deficien\w*|non-?compliant)\b/i);
  });

  it("uses the expectation-vs-presence phrasing for a path that is not there", () => {
    // The literal contract from the plan: "no `X` present in this knowledge base".
    const notPresent = EXPECTED_KB_PATHS[1];
    expect(body).toContain(`no \`${notPresent}\` present in this knowledge base`);
  });

  it("still records what IS present", () => {
    expect(body).toContain(EXPECTED_KB_PATHS[0]);
  });
});

describe("renderCoverageMarkdown — determinism", () => {
  it("produces a byte-identical file across two consecutive renders", () => {
    const root = kbRoot([EXPECTED_KB_PATHS[0]]);
    expect(renderCoverageMarkdown(assessCoverage(root), counts)).toBe(
      renderCoverageMarkdown(assessCoverage(root), counts),
    );
  });

  it("embeds no timestamp or date", () => {
    const body = renderCoverageMarkdown(assessCoverage(kbRoot([])), counts);
    expect(body).not.toMatch(/\b\d{4}-\d{2}-\d{2}\b/);
    expect(body).not.toMatch(/\b\d{2}:\d{2}:\d{2}\b/);
    expect(body).not.toMatch(/GMT|UTC|Z\b/);
  });
});

describe("the marker — emitted twice, identical field sets", () => {
  const marker = formatProducersMarker(counts);
  const body = renderCoverageMarkdown(assessCoverage(kbRoot([])), counts);

  it("carries all five counts on the stdout marker", () => {
    for (const f of MARKER_FIELDS) expect(marker).toContain(`${f}=`);
    expect(marker.startsWith(PRODUCERS_MARKER)).toBe(true);
  });

  // THE drift guard. The plan's discoverability_test greps the committed artifact,
  // so if the artifact's marker line ever diverges from the stdout one, that test
  // silently starts verifying something other than what the run reported. This is
  // the in-scope analogue of git-lock-marker-telemetry.test.ts's sentinel pinning.
  it("emits a marker line inside the artifact with a BYTE-IDENTICAL field set", () => {
    const line = body.split("\n").find((l) => l.includes(PRODUCERS_MARKER));
    expect(line).toBeDefined();

    const fields = (s: string) =>
      [...s.matchAll(/(\w+)=(\S+)/g)].map((m) => `${m[1]}=${m[2]}`).sort();
    expect(fields(line!)).toEqual(fields(marker));
  });

  it("is greppable as a single line — the discoverability_test depends on it", () => {
    expect(marker).not.toContain("\n");
    expect(body.split("\n").filter((l) => l.includes(PRODUCERS_MARKER)).length).toBe(1);
  });

  // ADR-171 claim 3, enforced in code.
  it("carries COUNTS ONLY — no path, filename, or repo-identifying data", () => {
    // `[a-z0-9_]` — the field names carry digits (`c4_elements`). The point of the
    // anchored form is that NOTHING but `<name>=<integer>` pairs can appear.
    expect(marker).toMatch(/^SOLEUR_KB_SYNC_PRODUCERS(?: [a-z0-9_]+=\d+){5}$/);
  });

  it("keeps the artifact free of anything resembling a repo URL or absolute path", () => {
    expect(body).not.toMatch(/https?:\/\//);
    expect(body).not.toMatch(/(?:^|\s)\/(?:home|Users|var|tmp)\//);
    expect(body).not.toMatch(/git@/);
  });
});

describe("writeCoverage — derives every count from KB state", () => {
  it("derives ALL five counts from the tree, taking no count flags", () => {
    // The wrapper used to accept --c4-elements/--c4-relationships/--domain-model-rows
    // and expected sync.md to thread them from the C4 producer's marker. An ABSENT
    // flag became 0, which is byte-identical to the plan's headline failure mode —
    // the exact state this artifact exists to detect, forged by forgetting a flag.
    // There is now no flag to forget.
    const root = mkdtempSync(join(tmpdir(), "kbcov-wrap-"));
    mkdirSync(join(root, "knowledge-base", EXPECTED_KB_PATHS[0], ".."), { recursive: true });
    writeFileSync(join(root, "knowledge-base", EXPECTED_KB_PATHS[0]), "x");

    const marker = writeCoverage(root);
    expect(marker).toContain("coverage_present=1");
    expect(marker).toContain(`coverage_expected=${EXPECTED_KB_PATHS.length}`);
    // No model.likec4.json and no register in this tree — reported honestly as 0
    // rather than as a fabricated value.
    expect(marker).toContain("c4_elements=0");
    expect(marker).toContain("domain_model_rows=0");
  });

  it("writes the artifact and its marker line matches the returned marker", () => {
    const root = mkdtempSync(join(tmpdir(), "kbcov-wrap2-"));
    const marker = writeCoverage(root, ["c4: 0 relationships"]);
    const body = readFileSync(join(root, "knowledge-base", "project", "kb-coverage.md"), "utf8");
    expect(body).toContain(marker);
    expect(body).toContain("c4: 0 relationships");
  });

  it("counts ONLY the Auto-inferred rows, never the curated table", () => {
    // The curated table is hand-authored; counting it would make the number move
    // when a human edits the register rather than when sync does.
    const register = [
      "# Register",
      "",
      "## Business Rules",
      "",
      "| ID | Rule | Statement | Source |",
      "|---|---|---|---|",
      "| BR-001 | a | b | c |",
      "| BR-002 | d | e | f |",
      "",
      "## Auto-inferred (unreviewed)",
      "",
      "| Anchor | Candidate statement |",
      "|---|---|",
      "| x.sql > t.a | one |",
      "",
    ].join("\n");
    expect(countAutoInferredRows(register)).toBe(1);
  });

  it("stops at the next heading, so a reversed-order register does not spill", () => {
    const register = [
      "## Auto-inferred (unreviewed)",
      "",
      "| Anchor | Candidate statement |",
      "|---|---|",
      "| x.sql > t.a | one |",
      "",
      "## Business Rules",
      "",
      "| ID | Rule |",
      "|---|---|",
      "| BR-001 | a |",
      "| BR-002 | b |",
      "",
    ].join("\n");
    expect(countAutoInferredRows(register)).toBe(1);
  });

  it("returns 0 for an absent register rather than throwing", () => {
    expect(countAutoInferredRows(null)).toBe(0);
  });
});

describe("formatErrorMarker", () => {
  it("is a single greppable line naming the producer and reason", () => {
    const m = formatErrorMarker("c4", "likec4 exited non-zero");
    expect(m.startsWith("SOLEUR_KB_SYNC_ERROR")).toBe(true);
    expect(m).toContain("producer=c4");
    expect(m).not.toContain("\n");
  });

  it("collapses embedded newlines in the reason rather than emitting a multi-line record", () => {
    expect(formatErrorMarker("c4", "line one\nline two")).not.toContain("\n");
  });
});

describe("EXPECTED_KB_PATHS — entries must be paths a producer really writes", () => {
  // The list shipped with `overview/constitution.md` while sync.md's Definition Sync
  // reads and writes `project/constitution.md`. Nothing caught it because every test
  // indexed the constant it was pinning (`[0]`, `[1]`, `.length`) — fully
  // self-referential — so the artifact would have reported a permanent
  // "no constitution present" line against a file one directory away, in every
  // customer repo.
  const syncMd = readFileSync(
    join(resolve(import.meta.dir, "../../.."), "plugins/soleur/commands/sync.md"),
    "utf8",
  );

  it("the constitution entry matches the path sync.md actually reads and writes", () => {
    const documented = syncMd.match(/knowledge-base\/(project\/constitution\.md)/);
    expect(documented).not.toBeNull();
    expect(EXPECTED_KB_PATHS).toContain(documented![1]);
  });

  it("is sorted, so ordering can never follow edit history", () => {
    expect([...EXPECTED_KB_PATHS]).toEqual([...EXPECTED_KB_PATHS].sort());
  });

  it("contains no duplicate entries", () => {
    expect(new Set(EXPECTED_KB_PATHS).size).toBe(EXPECTED_KB_PATHS.length);
  });
});
