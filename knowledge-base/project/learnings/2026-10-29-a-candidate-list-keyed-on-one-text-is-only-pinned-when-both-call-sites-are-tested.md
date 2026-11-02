# Learning: a candidate list keyed on one text is only pinned when BOTH call sites are tested

## Problem

Live-fire 6 of the gated create arm refused `prefer-patch/nearest-not-top3` (nearest rank 34): the prompt stated "your
nearest_skill must be among the server's top 3 matches" but never showed the list. The fix (show the server's per-pattern
top-3 candidates in a fenced block) is a proxy: the list is keyed on the PATTERN text, the gate ranks the PROPOSAL text.

## Solution

`createCandidates` reuses the gate's own `rankOverlap` over ALL skills, drops hidden skills and zero scores, takes
`OVERLAP_TOP_K`. A Sentry-only `nearest_in_offered` (0/1) says whether a refused model ignored the list or a listed skill
fell out of the re-rank. The gate, `OVERLAP_TOP_K` and the threshold stay untouched.

## Key Insight

Three things a green first pass did not show:

1. A helper tested directly leaves its CALL SITES unpinned. `createCandidates(p, visible)` at the prompt site and a
   visible-only list at the gate site both survived 331 green tests; only a population where hiding skills changes the
   candidate set (found by a seeded search, precondition asserted) kills them. Same for `slice` before `filter`: a hidden
   top scorer then eats a slot, and only a fixture with a hidden skill inside the top 3 and enough positive visible skills
   notices.
2. A prose claim about a Sentry-only number needs its three readings written from the code: 0 also covers a skill listed
   only under a sibling pattern and one outside the charset; at the post-fetch recheck it is measured against the
   re-fetched tree.
3. A rule the prompt adds that is stricter than the gate (no candidate line means do not create; no genuine nearest skill
   means no_action) belongs in the ADR and the runbook with the consequence: it can lower the create rate and no field
   separates those declines from the maturity bar.

## Session Errors

- **The outcome-row monitor grepped `create_arm=` text; the marker is a JSON row** — Recovery: unfiltered query, then a
  JSON-key extraction — Prevention: the runbook's "Reading a live-fire row" now carries the extraction and says to run a
  known-positive first (done, verified against rows 4, 5 and 6).
- **A Python edit batch failed to parse and applied nothing** — Recovery: the next run still showed the old state — Prevention:
  write multi-edit scripts to a file with exact-once asserts and print one changed line back before trusting a green run.
- **Charset test asserted over the whole prompt, which the pre-existing skill list also prints** — Recovery: scoped the
  assertion to the candidates block — Prevention: assert the NEW surface, not the whole artifact it sits in.
- **Affected-test gate queued ~20 min behind sibling runs** — Recovery: cancelled for CI (the required full-battery context),
  after the targeted suites, `tsc`, markdownlint and C4 parity were green — Prevention: none in code; read the
  `LOCK_WAIT_HEARTBEAT` `position=` field before waiting.
- **The fix-round seat map returned about 11 of 14 seats for a 104-line range** — Recovery: ran four seats covering the
  changed risk plus semgrep inline, and disclosed the reduction in the evidence comment — Prevention: none; the map is the
  policy.
- **The process-search hook blocked a pattern-match command that would have matched its own wrapper** — Recovery: used the
  `proc.sh` helpers the hook names — Prevention: already hook-enforced (it also fired on this very file's draft text).

## Tags
category: test-failures
module: compound-promote
