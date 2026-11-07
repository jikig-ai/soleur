# Pattern layer seed provenance (plan Phase 5)

Records how the seed pages under `knowledge-base/project/patterns/` were chosen. This file is
deliberately outside the pages: page text stays free of process detail.

## Candidate generation (5.1)

- Command: `SOLEUR_WM_WINDOW_DAYS=90 SOLEUR_WM_DIGEST_PATH=<scratch>/dg90.md bash scripts/weakness-miner.sh`.
  The tracked `knowledge-base/project/learnings/weakness-digest.md` was not written to and is unchanged
  (`git diff` on it is empty).
- The miner scanned 942 learnings first added in the last 90 days and emitted 218 tag-pair
  co-occurrence clusters (>= 3 members).

## Filtering and dedupe (5.2)

- Members were restricted to `git ls-files` tracked, non-`/archive/` learnings under
  `knowledge-base/project/learnings/`; clusters with >= 5 such members: 68.
- Greedy member-set Jaccard dedupe (largest first, drop a cluster whose Jaccard with an already kept
  cluster exceeds 0.5): 64 clusters kept. Dedupe alone barely narrows the set because the clusters
  overlap on shared learnings without sharing a high Jaccard, so the seed choice was made by reading
  the evidence learnings, not by cluster rank.
- 237 distinct member learnings across the kept clusters were screened with the PII_REGEX from
  `cron-compound-promote.ts` plus handle (`@name`), UUID-shape, token-prefix (`ghp_`, `sk-`, `AKIA`,
  `xox`) and `.internal`/`.local` checks. 193 passed; 44 matched (mostly benign `@` or `sk-`
  substrings, one example email address) and were dropped as evidence regardless of benignity.
- Roughly a dozen clusters qualified as describing one recurring failure class with a statable
  shared root cause and fix after reading; seven were written. Remaining clusters are mostly
  topic-specific echoes (for example per-tool tag pairs such as doppler + terraform) of the same
  verification-quality classes, or lacked enough clean evidence.
- Pairs of seed pages were checked for evidence-set Jaccard > 0.5: none.

## Pages and their source clusters

The miner clusters are tag-pair co-occurrence, so a page draws on several; the overlap column is how
many of the page's evidence learnings fall inside the named cluster.

| Page slug | Evidence | Main source clusters (overlap) |
|---|---|---|
| early-exit-reader-under-pipefail | 6 | pipefail + sigpipe (4 of 6); other evidence found via pipefail/sigpipe tag scan |
| fixture-cannot-distinguish-the-cases-it-claims | 6 | fixtures + mutation-testing (5); guards + mutation-testing (4); mutation-testing + vacuity (4) |
| mutation-score-is-not-predicate-correctness | 6 | mutation-testing + vacuity (4); measurement + mutation-testing; fixtures + mutation-testing |
| guard-pins-artifact-not-wiring | 6 | mutation-testing + terraform (3); cloud-init + mutation-testing (3) |
| instrument-answers-instead-of-failing | 5 | guards + mutation-testing (4); fail-open + measurement; guards + observability |
| failure-signal-never-reaches-a-human | 5 | guards + observability (3); observability + review; better-stack + observability |
| verification-scaffolding-carries-the-defect | 5 | guards + mutation-testing (5); mutation-testing + review (3); guards + vacuity (3) |

## Content checks (5.3)

- Evidence learnings: all tracked, non-archived, non-symlink, matching the evidence path regex, and
  free of the PII-shaped strings above.
- Pages: whole-file scan for PII_REGEX and the extra shapes is clean; ASCII only; summaries <= 200
  characters, printable ASCII, single line; no page carries instructions addressed to a model.
- Pages summarize learnings in the maintainer's own words; no long verbatim passages.
