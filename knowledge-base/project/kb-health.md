---
title: KB Health — learnings-corpus redundancy snapshot
date: 2026-06-14
category: engineering
tags: [knowledge-base, metrics, redundancy]
issue: "#5298"
---

# KB Health Snapshot

Stable, SSH-free surface for the deterministic learnings-corpus redundancy metric
(`scripts/kb-staleness-metric.sh`). Readable via the app.soleur.ai KB viewer + GitHub — no SSH, no
dashboard-pull (`hr-no-dashboard-eyeball-pull-data-yourself`). The date-stamped JSON snapshots live
alongside at `knowledge-base/project/kb-redundancy-metrics-<date>.json`.

This metric is the **deterministic gate signal** for the deferred consolidation pass (#5292). See the
authoritative decision rule in `knowledge-base/project/specs/feat-compound-consolidate/spec.md`
§Re-Evaluation Criteria.

## Latest snapshot — 2026-06-14 (baseline)

| Field | Value |
|---|---|
| corpus_count (non-archive learnings) | **1550** |
| exempt (compliance / security-issues / incident / `regulation:`) | 59 |
| Jaccard threshold | 0.6 |
| redundant_pairs (non-exempt) | **3** |
| **redundancy density** | **0.19 %** |
| JSON | `kb-redundancy-metrics-2026-06-14.json` |

**Top redundant pairs:**
1. `0.875` — `2026-03-14-content-publisher-channel-extension-pattern.md` ⟷ `2026-03-19-content-pipeline-channel-extension-pattern.md`
2. `0.778` — `2026-03-10-codex-portability-scan-methodology.md` ⟷ `2026-04-07-openhands-portability-scan-methodology.md`
3. `0.667` — `bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` ⟷ `bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md`

**Gate reading:** baseline density **0.19 % is far below the 15 % absolute floor**, so the absolute
shortcut in clause 1 is **inert** — only the **+5 pp delta** arm governs at the 2026-08-13 checkpoint.
The gate is therefore not pre-decided (it can still fire BUILD if redundancy genuinely grows ≥ +5 pp,
i.e. past ~5.2 %), but on this evidence the corpus's problem was never bloat and the honest expectation
is **close #5292 as wontfix**.

## How to refresh

```bash
bash scripts/kb-staleness-metric.sh        # writes kb-redundancy-metrics-<today>.json + prints summary
bash scripts/kb-staleness-metric.sh --json # JSON to stdout (used by the checkpoint)
```

The 2026-08-13 checkpoint runs automatically via the `scripts/sweep-followthroughs.sh` daily sweeper
(directive on #5292 → `scripts/followthroughs/kb-consolidation-checkpoint.sh`, `earliest=2026-08-13`).
No new cron, no Anthropic, no SSH.

## Closure-lifecycle convention (reserved for #5292)

When the consolidation pass (#5292) is eventually built (only if the gate fires BUILD), it records
supersession with **additive frontmatter only** on the older learning:

```yaml
superseded_by: <path-to-newer-learning>
status: superseded   # optional
```

It MUST never edit/delete a source learning body, and never merge/archive an exempt class
(`compliance/`, `security-issues/`, incident/PIR) — see spec §CLO Guardrails (G1–G5). This convention
is recorded here as enabling infrastructure; its first real use lands with #5292, its only consumer.
