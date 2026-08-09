// Coverage summary for /soleur:sync (#7332, plan Phase 3).
//
// Reports what Soleur EXPECTS a knowledge base to contain versus what is PRESENT,
// as a deterministic committed artifact plus a stdout marker.
//
// ‼️ WORDING IS A HARD CONSTRAINT, NOT A STYLE PREFERENCE. This file lands in the
// CUSTOMER's own repository, committed, timestamped by git, and permanently
// blamed. "missing: privacy policy" is a durable, discoverable assertion that a
// business lacks a compliance artifact — written by us, about them, into a record
// they cannot erase. "no `privacy-policy.md` present in this knowledge base" says
// the same operational thing about OUR expectation without asserting anything
// about their business. Every string below is written to that rule and a test
// enforces both halves of it (no deficiency framing AND the expectation phrasing
// present) — because a report can easily carry the right header and still emit a
// deficiency bullet per row.
//
// ‼️ DETERMINISM IS REQUIRED. No timestamp, no run id, sorted ordering. An
// unchanged KB must render byte-identically or every sync emits a one-field diff
// forever. knowledge-base/INDEX.md is the in-repo warning for exactly this shape.
//
// OBSERVABILITY: layer 7 (`cli-stdout-artifact`). The marker is emitted TWICE —
// on stdout, where the agent and operator read it in-session, and as a line in
// this artifact, so it survives the session. There is no Soleur-side sink for a
// self-hosted CLI run and there must not be one (ADR-171 §Observability
// boundary), which is why the durable artifact IS the queryable surface. The
// marker therefore carries COUNTS ONLY: no path, no filename, no repo URL.

import { existsSync } from "node:fs";
import { join } from "node:path";

/** Marker sentinel. Kept identical on both surfaces so one grep finds either. */
export const PRODUCERS_MARKER = "SOLEUR_KB_SYNC_PRODUCERS";
export const ERROR_MARKER = "SOLEUR_KB_SYNC_ERROR";

/**
 * The five counts, in emission order. Exported so the drift guard can assert the
 * stdout marker and the artifact's marker line carry a byte-identical field set —
 * the plan's discoverability_test greps the ARTIFACT, so a divergence would make
 * that test silently verify something other than what the run reported.
 */
export const MARKER_FIELDS = [
  "c4_elements",
  "c4_relationships",
  "domain_model_rows",
  "coverage_present",
  "coverage_expected",
] as const;

/**
 * ‼️ EVERY FIELD HERE IS A FUNCTION OF KB STATE, NEVER OF THE RUN.
 *
 * That is the invariant that makes this artifact deterministic, and the original
 * design broke it in one place: `domain_model_rows` meant "rows appended by THIS
 * run", which is N on a fresh register and 0 on the next sync once dedup no-ops.
 * Since the marker is embedded in the committed file, an unchanged KB produced a
 * guaranteed one-field diff on every second sync — AC11's byte-stability claim was
 * false by construction, and the determinism test passed only because its fixture
 * handed identical counts to both runs.
 *
 * The field now means "rows the register currently HOLDS", which is state, so
 * determinism follows from the definition instead of from a fixture. Run-scoped
 * facts ("appended 3 rows this run") belong on stdout, which is where run-scoped
 * facts belong — the artifact is a snapshot, the stream is a log.
 *
 * Corollary for callers: derive these counts, do not pass them in. Flags that can be
 * forgotten reconstruct the same failure — an absent `--c4-elements` silently
 * produced `c4_elements=0`, byte-identical to the plan's headline failure mode.
 */
export type CoverageSources = {
  /** Rendered model, if committed. Absent/unparseable ⇒ zeros, reported honestly. */
  modelJson: string | null;
  /** The domain-model register, if present. */
  registerMarkdown: string | null;
};

export type ProducerCounts = Record<(typeof MARKER_FIELDS)[number], number>;

/**
 * What Soleur expects a populated knowledge base to contain, KB-relative.
 *
 * ‼️ Every entry must be a path a Soleur producer ACTUALLY writes. This shipped with
 * `overview/constitution.md` while sync.md's Definition Sync reads and writes
 * `project/constitution.md`, so Soleur's own knowledge base would have reported a
 * permanent "no constitution present" line against a file one directory away — in
 * every customer repo. Nothing caught it because every test indexed the constant it
 * was pinning (`[0]`, `[1]`, `.length`), which is self-referential. A parity test now
 * pins the constitution entry against sync.md.
 *
 * PR 1 keeps this a static list. PR 2 replaces it with the blueprint manifest —
 * that substitution is the ONLY coupling between the two PRs, which is why the
 * shape here is deliberately just an ordered string list.
 *
 * Sorted at module scope so ordering can never depend on edit history.
 */
export const EXPECTED_KB_PATHS: readonly string[] = [
  "engineering/architecture/diagrams/model.likec4.json",
  "engineering/architecture/domain-model.md",
  "project/constitution.md",
  "product/prd",
  "project/README.md",
  "project/components",
  "project/learnings",
  "project/rule-metrics.json",
  "project/specs",
].slice().sort();

export type CoverageEntry = { path: string; present: boolean };

/** Probe each expected path under `kbRoot`. Order is the sorted expected order. */
export function assessCoverage(kbRoot: string): CoverageEntry[] {
  return EXPECTED_KB_PATHS.map((path) => ({ path, present: existsSync(join(kbRoot, path)) }));
}

/**
 * Count the rows the register currently holds under `## Auto-inferred (unreviewed)`.
 *
 * Auto-inferred ONLY — the curated `## Business Rules` table is hand-authored and is
 * not coverage this sync produced, so counting it would make the number move when a
 * human edits the register rather than when sync does.
 *
 * Stops at the next `## ` heading so a register whose Auto-inferred section precedes
 * the curated one does not spill into it — the same section-boundary bug that let
 * write-row append into the curated table.
 */
export function countAutoInferredRows(registerMarkdown: string | null): number {
  if (!registerMarkdown) return 0;
  let inSection = false;
  let rows = 0;
  for (const line of registerMarkdown.split("\n")) {
    if (/^## Auto-inferred \(unreviewed\)/.test(line)) {
      inSection = true;
      continue;
    }
    if (inSection && /^## /.test(line)) break;
    if (!inSection) continue;
    // A data row: starts with `|`, and is neither the header nor the `|---` rule.
    if (/^\|/.test(line) && !/^\|[\s-]*-[\s-]*\|/.test(line) && !/^\|\s*Anchor\s*\|/.test(line)) {
      rows++;
    }
  }
  return rows;
}

/**
 * Derive every marker count from KB state. See `CoverageSources` for why these are
 * derived rather than passed in.
 */
export function deriveCounts(
  entries: CoverageEntry[],
  sources: CoverageSources,
): ProducerCounts {
  const model = sources.modelJson
    ? (() => {
        try {
          const m = JSON.parse(sources.modelJson) as Record<string, unknown>;
          const size = (v: unknown) =>
            v && typeof v === "object" && !Array.isArray(v) ? Object.keys(v).length : 0;
          return { elements: size(m.elements), relationships: size(m.relations) };
        } catch {
          return { elements: 0, relationships: 0 };
        }
      })()
    : { elements: 0, relationships: 0 };

  return {
    c4_elements: model.elements,
    c4_relationships: model.relationships,
    domain_model_rows: countAutoInferredRows(sources.registerMarkdown),
    coverage_present: entries.filter((e) => e.present).length,
    coverage_expected: entries.length,
  };
}

/** Collapse to one line — a marker must be greppable as a single record. */
function oneLine(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

/** The stdout marker. Counts only, in `MARKER_FIELDS` order. */
export function formatProducersMarker(counts: ProducerCounts): string {
  const fields = MARKER_FIELDS.map((f) => `${f}=${counts[f]}`).join(" ");
  return `${PRODUCERS_MARKER} ${fields}`;
}

/** The failure marker. Not `reportSilentFallback` — nothing under plugins/ imports Sentry. */
export function formatErrorMarker(producer: string, reason: string): string {
  return oneLine(`${ERROR_MARKER} producer=${producer} reason="${oneLine(reason)}"`);
}

/**
 * Render the committed artifact.
 *
 * `degraded` rows are recorded here as well as on stdout, so a failed run survives
 * the session — on this surface stdout is the only other signal and it evaporates.
 */
export function renderCoverageMarkdown(
  entries: CoverageEntry[],
  counts: ProducerCounts,
  degraded: string[] = [],
): string {
  const present = entries.filter((e) => e.present);
  const notPresent = entries.filter((e) => !e.present);

  const out: string[] = [
    "# Knowledge base coverage",
    "",
    "What Soleur looks for in a knowledge base, and what is present in this one.",
    "This is a description of Soleur's expectations — it is not an assessment of",
    "the business, and it is not a compliance finding. Generated by",
    "`/soleur:sync`; regenerated on every run.",
    "",
    `## Present (${present.length} of ${entries.length})`,
    "",
  ];

  if (present.length === 0) {
    out.push("- none of the expected entries are present yet");
  } else {
    for (const e of present) out.push(`- \`${e.path}\``);
  }

  out.push("", "## Not present", "");

  if (notPresent.length === 0) {
    out.push("- every expected entry is present");
  } else {
    // The exact expectation-vs-presence phrasing. Do not reword to a deficiency
    // form — see the file header.
    for (const e of notPresent) {
      out.push(`- no \`${e.path}\` present in this knowledge base`);
    }
  }

  if (degraded.length > 0) {
    out.push("", "## Producers reporting degraded", "");
    for (const d of degraded.slice().sort()) out.push(`- ${oneLine(d)}`);
  }

  out.push(
    "",
    "## Run counts",
    "",
    "Emitted identically on sync stdout, so this artifact and the run agree.",
    "",
    "```",
    formatProducersMarker(counts),
    "```",
    "",
  );

  return out.join("\n");
}
