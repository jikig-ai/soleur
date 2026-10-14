---
title: "ADR-219: Multi-bundle vendor enrollment is schema-keyed, and emit strips are license-scoped"
status: Accepted
date: 2026-09-13
supersedes: []
amends: []
tags: [vendoring, cron, legal, licensing]
---

# ADR-219: Multi-bundle vendor enrollment is schema-keyed, and emit strips are license-scoped

## Status

Accepted — 2026-09-13. Implements #8122.

## Context

The vendored-content stack (NOTICE registry, pin-integrity lefthook, drift cron,
PR-time upstream verify) was built for exactly one bundle — `gdpr-gate`'s
goSprinto compliance rules — and every layer hard-coded that bundle's path.
Landing a second bundle (the General-Legal CC0 legal-template corpus under
`legal-generate`) forced a generalization decision in each layer, and two
sub-decisions carried enough blast radius to record here.

### The `*/NOTICE` glob already matches a file it must not enroll

`plugins/soleur/skills/incident/NOTICE` is a prose attribution file with no
frontmatter. A naive `skills/*/NOTICE` discovery glob enrolls it, after which
the cron throws on it weekly and coverage guards count it forever. Enrollment
is therefore **schema-keyed**: a bundle is a `*/NOTICE` whose frontmatter parses
AND declares `upstream` + `pinned-commit`. The identical predicate feeds cron
discovery, the bundle-coverage guard, the verify workflow, and the
discoverability command — four surfaces that must never disagree about what is
enrolled.

### Inngest `step.run` memoizes by step ID

A per-bundle loop over `step.run("detect-drift", …)` returns bundle A's
memoized result for bundle B — silently correct-looking output that never ran.
Every per-bundle step ID is slug-suffixed (`detect-drift-<slug>`); run-level
steps (`mint-installation-token`, `setup-workspace`, `ensure-labels`,
`discover-bundles`) stay unsuffixed. The same hazard applies to write paths:
`safeCommitAndPr` branches from HEAD, so each write arm resets the worktree to
`origin/main` first — otherwise bundle B's attestation PR can carry bundle A's
unmerged re-vendor commits. Dedup queries are scoped per bundle slug; an open
bundle-A PR must never suppress bundle-B (the #7710 skipped-open-pr defect
class). Legacy un-suffixed branches/issues classify as `gdpr-gate`'s.

### Embedded vendor promotion is a corpus-vs-emit question, not a keep-or-delete one

Each General-Legal template ends with a credit block naming the vendor. The
corpus retains it verbatim — provenance and byte-fidelity are what make the
blob pins meaningful. The emit path strips it deterministically
(`strip-vendor-credit.sh`), anchored on the credit-paragraph marker text rather
than a bare `---` (which also terminates legitimate document sections), and
fails loud (exit 2) on input lacking the marker. **The strip doctrine is
scoped to no-attribution licenses** — under a CC-BY bundle, stripping would be
a license violation, so the license field is the authority on whether a strip
path may exist at all (see `content-vendoring.md` §9a).

## Decision

1. **Schema-keyed enrollment.** One predicate — parseable frontmatter +
   `upstream` + `pinned-commit` — shared by all four discovery surfaces.
2. **Per-bundle identity everywhere.** Slugged step IDs, cron names, branch
   prefixes, dedup queries, `NOTICE_FILE` env, upstream refs, `allowedPaths`,
   outcomes; AND-aggregated run health so no sibling masks another.
3. **License-scoped emit-strip.** Corpus keeps promotion verbatim; emit strips
   it; the doctrine applies only where the license requires no attribution.

## Consequences

- A third bundle enrolls by dropping a conforming NOTICE into a skill — no
  cron/workflow/lefthook edits beyond the file-glob coverage Guard 2 asserts.
- The shared single monitor is a deliberate trade-off: one Sentry heartbeat
  covering the AND of all bundles. Per-bundle failure detail lives in the
  handler result and the `reportSilentFallback` Sentry event each arm emits
  (`op=bundle-arm`), not in separate monitors or filed issues.
- Known limitation: the drift classifier's path handling is anchored on
  `references/`/`layers/` shapes; a bundle vendoring under a different
  directory shape needs a classifier audit before enrollment.
- Acknowledged residual gap: `MAX_RUN_DURATION_MS` is exported but no outer
  `Promise.race` wraps the handler (pre-existing ADR-033 I3 gap, unchanged).
