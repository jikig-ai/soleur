---
title: Domain-model drift extraction — deterministic-first, last-writer-wins, content-anchored
status: accepted
date: 2026-07-01
related_adrs: [ADR-038, ADR-044, ADR-073]
related: [5754, 5871, 5872, 5773]
related_plans:
  - knowledge-base/project/plans/2026-07-01-feat-sync-domain-model-drift-plan.md
related_specs:
  - knowledge-base/project/specs/feat-sync-domain-model/spec.md
brand_survival_threshold: single-user incident
---

# ADR-076: Domain-model drift extraction — deterministic-first, last-writer-wins, content-anchored

## Context

The business-rules register (`knowledge-base/engineering/architecture/domain-model.md`,
created by #5773) is hand-curated. #5754 adds `/soleur:sync domain-model` — an analyzer that
drift-checks the register against the repo's data model and proposes newly-inferred rows. The
enforcement gates that consume the analyzer's output (plan-flag / review drift-check / ship block)
are tracked separately in #5871; a scheduled drift cron in #5872. This ADR records the durable
extraction conventions those consumers depend on.

## Decision

1. **Deterministic-first extraction.** A bash analyzer (`scripts/domain-model-drift.sh`, tokenizer
   in `scripts/lib/domain-model-lib.sh`) extracts structural facts. The LLM is confined to phrasing a
   candidate statement at interactive approval time — it is NEVER in the drift-detection or write
   path. Consequence: drift detection is a pure deterministic set-diff, so re-runs are byte-identical
   (`LC_ALL=C` sorts + `jq -S`), which is what makes it CI-gateable.

2. **Last-writer-wins policy replay.** RLS policies are reconstructed by replaying `CREATE`/`DROP`
   `POLICY` events in migration order over base migrations only (`*.down.sql` rollbacks are excluded —
   a naive glob would let a rollback DROP silently delete a live policy). Migration filenames are the
   apply order (zero-padded numeric prefixes, `LC_ALL=C`).

3. **Content-anchored citations.** Every fact/candidate cites `<full-migration-filename> › <table>.<object>`
   or `<file> › <symbol>()` — never a line number (which churns on unrelated edits). The full filename
   (not the 3-digit number) disambiguates the 14 shared migration numbers; the table qualifier
   disambiguates non-globally-unique policy names. The anchor is the dedup key that prevents
   re-proposal across statement-phrasing edits and promotions.

4. **Structural-not-semantic scope (the bounded guarantee).** The analyzer detects *documentation
   coverage of statically-extractable structure* — NOT semantic access-control correctness. Dynamic
   RLS (`EXECUTE format`/`DO $$`), function-body predicate logic, service-role bypasses, and un-merged
   `ALTER POLICY` clauses are disclosed as `blind_spots`, never counted as facts. A completeness
   disclaimer ships in the register header and every drift report so a "no drift" result cannot be
   mis-cited as an access-control attestation.

5. **Approval-gated, curation-preserving write.** Inferred rows are written (per-row operator approval)
   only into `## Auto-inferred (unreviewed)` via an atomic, markdown-escaped, secret-scanned,
   anchor-deduped primitive. The curated `## Business Rules` table is never machine-touched; promotion
   to a `BR-*` id is a deliberate human edit.

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| LLM-in-prompt extraction (no deterministic script) | Non-deterministic ⇒ fails idempotency; produces hallucinated drift |
| Naive grep-all-`CREATE POLICY` (no replay) | 72 `ALTER`/`DROP POLICY` mean it mixes dead + live predicates → false "no drift" |
| Authoritative replay against a live Postgres (`run-migrations.sh`) | Needs a DB, is path-locked to web-platform, breaks the generic-`--repo` requirement; the text-replay trade is deterministic + no-DB + repo-agnostic (this ADR's deliberate divergence from `run-migrations.sh`) |
| Line-number citations | Churn on unrelated edits ⇒ spurious diffs |
| Auto-write into curated `## Business Rules` | Corrupts hand-curated supersession lineage (e.g. BR-WS-3) |
| Pin the #5871 consumer JSON contract now | Consumer unbuilt; guarantees a v1→v2 break. The `extract` JSON carries `schema_version` and is marked internal/unstable until #5871 constrains it |

## Consequences

- #5871's enforcement gates consume the `drift` machine-readable output and exit-code contract
  (`0`=clean / `1`=drift / `2`=error / `3`=secret-refuse); pinning these here prevents a moving target.
- The bounded structural-not-semantic guarantee is load-bearing: it is what keeps the register honest
  under GDPR Art. 5(2) / SOC2 mis-citation pressure.

## C4 impact

None. The analyzer is operator-run dev tooling that READS the product model; it adds no external
actor/system/container and changes no ownership/tenancy relationship in `model.c4`/`views.c4`/`spec.c4`.

## Enforcement gates (2026-07-02 amendment, #5871)

The fast-follow enforcement gates this ADR anticipated are now built. Design of record:

1. **Gate on the stale-citation sub-count, NOT the raw exit code.** `drift` exits 1 on
   `stale_n>0 OR undoc_n>0`. The register is a *curated subset* (item 5), so "undocumented source
   facts" flags ~every un-curated table (~50) by design — a blocking gate on it would demand
   documenting every table, contradicting the curation-preserving intent. Enforcement therefore keys
   on **stale register citations** (0 on a healthy register, high-signal, ratchet-safe); undocumented
   facts stay **advisory-only**.
2. **Single blocking chokepoint at preflight `Check 11`** (ship inherits via preflight Phase 5.4);
   an advisory review note carries the undocumented-facts pointer to `/soleur:sync domain-model`.
   Plan-time flagging was intentionally not built (no diff at plan time → unenforceable nudge).
3. **Diff-scoped at the gate, not the analyzer** (no `--since` mode added — consistent with the
   bounded structural scope of item 4). Trigger = migrations + `workspace-resolver.ts` + the register.
4. **Ships blocking directly** (stale=0 on `main`; no advisory-first rollout apparatus). The residual
   citation-parser false-positive risk is covered by an actionable `stale>0` FAIL message.
5. The `name_after()` `public.` default-schema strip (`scripts/lib/domain-model-lib.sh`) **enforces
   item 3** — anchors are `<table>.<object>`, not the previously-corrupt `public.<table>.public.<object>`.

### Scheduled drift cron (2026-07-02 amendment, #5872)

The scheduled drift cron anticipated in `related: [5872]` is now built (dispatch-hybrid per ADR-033:
weekly Inngest cron `cron-domain-model-drift.ts` → `workflow_dispatch` executor
`scheduled-domain-model-drift.yml`). It consumes this ADR's contract unchanged — it gates on the
**stale-citation sub-count** (not the raw exit code, which is 1 on `main` by design from undocumented
facts) using the preflight Check 11 parser verbatim, and files a single idempotent GitHub issue only
when `stale > 0`. No new analyzer behaviour; consume-only. Undocumented facts / blind spots remain
advisory-only.
