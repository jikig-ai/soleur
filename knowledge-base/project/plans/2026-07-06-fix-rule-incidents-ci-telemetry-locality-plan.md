---
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
issue: 6042
adr: ADR-091
---

# 🐛 fix(telemetry): rule-incident aggregation belongs where the data lives — stop the CI fresh-checkout all-zero clobber (#6042)

## Overview

`.claude/.rule-incidents.jsonl` is gitignored (`.gitignore:37`, `.claude/.rule-incidents*`) and written **only on the operator's local machine** by PreToolUse hooks (`.claude/hooks/lib/incidents.sh::emit_incident` + the Python sibling `.claude/hooks/security_reminder_hook.py`). The weekly CI cron `.github/workflows/rule-metrics-aggregate.yml` runs `scripts/rule-metrics-aggregate.sh` on a **fresh checkout** where that log does not exist → the aggregator reads zero events → it commits `knowledge-base/project/rule-metrics.json` with `total_rules_tagged: 97, rules_unused_over_8w: 97`.

This is **structural, not transient**: every weekly aggregate commit in the file's history has shown 100% unused (`fd3e9d9b3` 75/75 at first ship 2026-04-15 → `556da160e` 97/97 at 2026-06-30; 66/66, 69/69, 78/78, 87/87, 90/90, 95/95 in between). The rule-utility signal built in #2213 has **never once carried information** in its CI-cron form.

**Root cause (one sentence):** the aggregator runs where the data *isn't*. The telemetry is local-only *by deliberate design* — the raw log's `command_snippet` field (≤1024 chars) carries absolute paths, git/gh identity, and PR-body text, so it is gitignored (mode `0600` locally) and must never be committed. The fix is not to ship raw data to CI; it is to **aggregate on the operator's machine, where the data already exists, and commit only the redaction-safe aggregate** — then stop the CI cron from overwriting that real data with a fresh-checkout zero snapshot.

**Why it matters now.** #6037 (the learnings-based weakness-miner, shipped as PR #6036) explicitly **cut** its obsolescence-candidates output "for exactly this reason" and filed #6042 as the blocker. #6042's re-evaluation criterion — "Revisit when #6037 has shipped" — is now satisfied. Consumer starved today: compound's unused-rules hint (`compound/SKILL.md:248-258`) and (once real data flows) `scripts/rule-prune.sh`.

**Scope (post-review).** A 5-agent plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, plus a prior CTO / spec-flow pass) converged: **ship the two load-bearing moves + the cron cleanup; defer completeness + obsolescence.** This plan ships **3 small phases** — (1) the aggregator no-ops instead of clobbering, (2) compound becomes the authoritative local producer, (3) drop the clobber-producing CI schedule. Cross-worktree read-merge and the `first_observed` obsolescence age-proxy are **deferred to a follow-up issue** (`## Deferred to follow-up`): both simplification reviewers flagged them as disproportionate for a p3 signal, and both correctness reviewers found multiple concrete bugs in them — the textbook "over-architected: cut it" signal (plan-review rule: both panels fire on the same scope → prefer delete over fix). Deferring is coherent: after Phases 1-2 `rule-metrics.json` goes *stale/under-complete* (last-known-good), never *false-zero*, and no consumer breaks (rule-prune reads the committed file, is quarterly + manually `/sync`-triggered, and its `first_seen != null` null-skip already prevents mass false-retirement; `weakness-miner.yml` is fully decoupled).

## Research Reconciliation — Spec vs. Codebase

| Issue/premise claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "rule-metrics.json shows `rules_unused_over_8w: 97` (100% unused)" | **Confirmed and stronger** — 100% unused in *every* weekly commit since 2026-04-15 (`git log -- knowledge-base/project/rule-metrics.json`). | Frame the fix as restoring a *structurally dead* signal. |
| The all-zero metric actively mis-informs consumers (implied) | **False.** `rule-prune.sh:88-90` filters `fire_count==0 AND first_seen != null`. In the all-zero state every rule has `first_seen == null`, so rule-prune yields **zero** candidates (the #3123 fix). The bug is **inert dead telemetry**, not active mis-firing. | User-Brand threshold = `none`. The obsolescence gap (never-fired rules are unprunable even with data) is real but **deferred** — a `first_observed` proxy the correctness panel showed is non-trivial for this repo. |
| "commit a rotated/aggregated incidents snapshot… via a hook or the compound flow" | compound **already runs the aggregator locally** — `compound/SKILL.md:248-258` runs `scripts/rule-metrics-aggregate.sh --dry-run` for the hint. The local touchpoint exists; it just never writes/commits. | Promote that dry-run to an authoritative write + conditional `git add` (Phase 2). No new hook. |
| Aggregator carries prior state forward | **False.** `rule-metrics-aggregate.sh` rebuilds every field from scratch; reads `$OUT` only at `:330-336` to suppress a no-diff commit. | Shipped scope adds no persisted state; `first_observed` (deferred) would need a new read-merge stage. |
| Raw log is safe to commit (Option A premise) | **False.** `command_snippet` verbatim-stores absolute paths, git/gh identity, quoted PR bodies (unscrubbed). Aggregate holds only `rule_id` + counts + timestamps + `section` + a 50-char public `rule_text_prefix`. | Commit only the aggregate. Option A rejected (privacy). |
| Operator telemetry lives in one place | **False — empirically fragmented.** The **bare primary** root holds the canonical `.claude/.rule-incidents.jsonl` (~577 KB); 7 of 12 sibling worktrees carry 4-16 KB scraps (Kieran, verified live). compound runs in a worktree. | Phases 1-2 aggregate the *committing worktree's* log (real, under-complete). Full cross-worktree + bare-primary read-merge is the follow-up's core job. |

## User-Brand Impact

**If this lands broken, the user experiences:** no user-facing artifact changes — internal dev-harness telemetry for a single operator. Worst realistic breakage is the rule-utility metric *stays* structurally zero (status quo).

**If this leaks, the user's data is exposed via:** the only vector is the raw `command_snippet` log (paths / git identity / PR bodies). This plan's central decision is to **keep that log gitignored and commit only the redaction-safe aggregate** — it *reduces* leak surface relative to Option A and introduces none.

**Brand-survival threshold:** none — reason: internal single-operator dev-harness telemetry; no user-facing surface, no user data; commits only the redaction-safe aggregate (rule_id + counts + public 50-char prefix), never the raw command_snippet log. (Sensitive-path scope-out per preflight Check 6: diff touches `scripts/`, `.github/workflows/`, `plugins/soleur/skills/compound/SKILL.md`, `knowledge-base/` — no schema/migration/auth/API surface.)

## Open Code-Review Overlap

None — the 61 open `code-review` issues were queried; none reference `scripts/rule-metrics-aggregate.sh`, `plugins/soleur/skills/compound/SKILL.md`, or `.github/workflows/rule-metrics-aggregate.yml`.

## Architecture Decision (ADR/C4)

Moving the authoritative producer of `rule-metrics.json` from a CI cron to the local compound flow is an architectural decision (new producer/substrate pattern; reverses the 2026-04-14 rule-utility plan's G3), so the ADR is a deliverable of THIS plan (`wg-architecture-decision-is-a-plan-deliverable`).

### ADR

**ADR-091 — Rule-metrics aggregation is a local (compound-flow) producer, not a CI cron** (provisional ordinal; `/ship`'s ADR-Ordinal Collision Gate re-verifies against `origin/main` — if renumbered, sweep this plan + tasks.md + every AC citing the ordinal in one edit).

- **Decision:** The authoritative producer of `knowledge-base/project/rule-metrics.json` is the **local compound flow**, which already runs the aggregator on the operator's machine where `.rule-incidents.jsonl` exists. The fresh-checkout CI cron is removed as a producer (it only ever committed false zeros). The raw incidents log stays gitignored; only the redaction-safe aggregate is committed.
- **Alternatives considered (record in the ADR):** (A) commit rotated raw snapshot to CI — rejected, privacy (command_snippet); (C) accept CI-zero, learnings-only — rejected, leaves a *committed* file asserting false 97/97 that consumers read. Divergence: differs from **ADR-054** (weakness-miner's "CI cron + bot-PR" precedent) *for this sink* because the incidents log is gitignored and CI cannot see it.
- **Relationship to the 2026-04-14 rule-utility plan:** **supersedes** that plan's **ADR-3** premise ("single flock-guarded file, *no per-session fragmentation*"), empirically falsified today (events fragment across ~12 worktrees). This ADR does **not** restore the single-file invariant — cross-worktree completeness is deferred (`## Deferred to follow-up`); it establishes local-compound as the producer and records that the committed metric reflects the committing worktree's log until the follow-up lands read-merge. **Task:** add a one-line back-pointer `> ADR-3 superseded by ADR-091 (#6042)` to `knowledge-base/project/plans/2026-04-14-feat-rule-utility-scoring-plan.md` so the reversal is discoverable from the old side (architecture-strategist finding 6).
- **Status:** `accepted`.

### C4 views

**No C4 impact** — internal dev-harness telemetry, not a modeled C4 container. Enumerated against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: the only actor is the already-modeled solo operator; the rule-metrics cron / incidents log / aggregate are not modeled elements or edges (model.c4 models the web-platform product architecture and plugin *skills* as components — `compound`/`oneshot` at `:111,121` — not their telemetry-write behavior); no product-architecture element's description is falsified. Nothing to add or correct.

## Infrastructure (IaC)

**No new infrastructure.** Modifies an existing workflow and repo-local scripts/skill prose; introduces no new server, secret, vendor account, DNS record, cron *substrate*, or persistent runtime process. Phase 2.8 IaC-routing gate: skip.

## Observability

```yaml
liveness_signal:
  what: committed rule-metrics.json becomes non-degenerate (rules_unused_over_8w < total_rules_tagged) once real local data flows
  cadence: every compound run (on-demand authoritative write); no scheduled producer after this change
  alert_target: compound stderr surfaces the aggregator's write/skip reason; the discoverability_test below is the durable check
  configured_in: plugins/soleur/skills/compound/SKILL.md (Step 8) + scripts/rule-metrics-aggregate.sh
error_reporting:
  destination: local stderr — aggregator prints its no-op skip reason; compound Step 8 prints whether it staged the file
  fail_loud: true (compound already does NOT silently swallow an aggregator crash, SKILL.md:258; the valid_lines==0 no-op guard emits a stderr line naming the skip + any drop-sentinel breakdown)
failure_modes:
  - mode: no-op guard mis-keyed on file-empty instead of valid_lines==0 — a sentinel-only (non-empty) log clobbers committed real data with zeros
    detection: test asserts sentinel-only input -> exit 0, no write; drop counts still echoed to stderr
    alert_route: scripts/rule-metrics-aggregate.test.sh (fails the PR)
  - mode: compound stages an unchanged or malformed-run rule-metrics.json (bad git add)
    detection: git diff --quiet gate skips staging when the aggregator did not write; test/manual confirms no spurious stage
    alert_route: compound stderr
  - mode: future refactor silently re-breaks locality (metric freezes) with no scheduled detector
    detection: known gap after the schedule drop — see Phase 3 note + the deferred read-only canary (architecture-strategist finding 1)
    alert_route: (deferred) read-only assertion on the committed file in an existing scheduled job once real data makes it green
logs:
  where: local stderr + GitHub Actions run logs; no new persistent log
  retention: GitHub default (90d) for CI runs
discoverability_test:
  command: jq -e '.summary.rules_unused_over_8w < .summary.total_rules_tagged' knowledge-base/project/rule-metrics.json
  expected_output: exit 0 (true) after the first local compound aggregation with real data; before the fix this is always false (97==97)
```

## Implementation Phases

Sequenced in dependency order.

### Phase 1 — Aggregator: no-op on zero DATA lines (stop the clobber) — **load-bearing**

Guard `scripts/rule-metrics-aggregate.sh` so it exits 0 **without writing** `rule-metrics.json` and **without rotating** when there are **zero valid rule-carrying lines** — keyed on `valid_lines == 0`, NOT on file size (a sentinel-only file is non-empty but has zero `rule_id` rows and would otherwise clobber — Sharp Edge).

- **Kieran b1 (unbound-var fix):** `valid_lines` and `drops_total` are currently assigned *only inside* `if [[ -s "$INCIDENTS_MERGED" ]]` (`:108`, `valid_lines=0` at `:117`, `drops_total` at `:144`). Under `set -euo pipefail` (`:21`) a guard that reads `valid_lines` on the absent/empty-file path aborts with an unbound-variable error (the AC1 case). **Initialize `valid_lines=0` and `drops_total=0` at top level BEFORE the `if [[ -s ... ]]` block.**
- **Kieran b2 (placement fix):** gate only the **file write at `:339`**, NOT the Stage A/B/C report build (`:197-300`). `--dry-run` (`:314`) must still print computed JSON so compound's hint (`SKILL.md:252-258`, `jq -r '.summary.rules_unused_over_8w'`) does not parse empty and print `[WARN] …failed`. Emit on the write path: `echo "rule-metrics: 0 rule-carrying incident lines; leaving committed rule-metrics.json unchanged." >&2`. On `valid_lines==0` with `drops_total>0`, still echo the drop breakdown so that window's `drops_*` telemetry is not silently swallowed. Rotation (`:368`) is already `[[ -s "$INCIDENTS" ]]`-gated — nothing to archive on empty.
- Files: `scripts/rule-metrics-aggregate.sh`, `scripts/rule-metrics-aggregate.test.sh`.

### Phase 2 — compound: promote local aggregation to authoritative write — **load-bearing**

In `plugins/soleur/skills/compound/SKILL.md` Phase 1.5 Step 8, run the aggregator **for real** (writes `rule-metrics.json`), then stage it only if it actually changed, so it lands in the session's compound commit (compound runs pre-commit per `2026-02-12-review-compound-before-commit-workflow.md`). Redaction-safe (aggregate shape; no `command_snippet`).

- **code-simplicity + Kieran (collapse the exit-code matrix):** use the single gate `git diff --quiet -- <OUT> || git add <OUT>` after the run. Correct against the script: malformed runs (exit 2/3/4) don't write → `diff --quiet` skips; the no-op guard doesn't write → skipped; an orphan-gate run (exit 5) does write → staged. Add one stderr line noting whether the file was staged. Do NOT `git add` unconditionally, and drop the four-way per-exit-code narration (nice-to-have telemetry, not correctness).
- Files: `plugins/soleur/skills/compound/SKILL.md`.

### Phase 3 — CI cron: drop the clobber-producing schedule

Remove the `schedule:` trigger from `.github/workflows/rule-metrics-aggregate.yml` (keep `workflow_dispatch` for on-demand manual runs). Phase 1's guard already makes any fresh-checkout run a self-no-op; dropping the schedule removes the pointless weekly no-op PR path and the false-zero producer.

- Update the workflow header comment to describe the local-producer model and cite ADR-091. Confirm `bot-pr-with-synthetic-checks` no-ops on an empty diff so a rare manual `workflow_dispatch` on a fresh checkout opens no empty PR (Kieran confirmation).
- **Scheduled-canary gap (architecture-strategist finding 1) — deferred, not silently dropped:** dropping the cron also removes the only *automated* detector of a future locality re-break. A read-only assertion (`jq -e '.summary.rules_unused_over_8w < .summary.total_rules_tagged'` on the *committed* file) inside an already-scheduled job (`rule-audit.yml`) would restore it with zero producer — but it can only go green once real local data has flowed, so it is added in the follow-up alongside read-merge, not here (it would be red on merge). Recorded in `## Deferred to follow-up`.
- Files: `.github/workflows/rule-metrics-aggregate.yml`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — Aggregator with **zero rule-carrying lines** — empty log, **sentinel-only** log (non-empty, 0 `rule_id` rows), and **absent** file — exits 0, writes **nothing**, and leaves a pre-existing committed `rule-metrics.json` byte-identical; no unbound-variable abort under `set -euo pipefail`. On sentinel-only input, drop counts are still echoed to stderr. New cases in `scripts/rule-metrics-aggregate.test.sh`.
- [ ] AC2 — With a populated fixture (deny + bypass + applied + warn), the aggregator writes a `rule-metrics.json` where `jq -e '.summary.rules_unused_over_8w < .summary.total_rules_tagged'` exits 0. `--dry-run` on the same fixture prints parseable JSON to stdout (compound-hint path unregressed).
- [ ] AC3 — `compound/SKILL.md` Step 8 instructs an authoritative aggregator run followed by `git diff --quiet -- <OUT> || git add <OUT>` (grep SKILL.md for the diff-gate), with a stderr line on staging. No unconditional `git add`.
- [ ] AC4 — `.github/workflows/rule-metrics-aggregate.yml` has no `schedule:` trigger (retains `workflow_dispatch`); header comment cites ADR-091. No path can commit an all-zero snapshot (fresh checkout ships the tracked real file; empty-log run no-ops → bot-pr sees no diff).
- [ ] AC5 — `knowledge-base/engineering/architecture/decisions/ADR-091-*.md` exists with `## Decision` + `## Alternatives Considered` (A/C rejected) + the ADR-3 **supersession** note + ADR-054 divergence note; a one-line `ADR-3 superseded by ADR-091 (#6042)` back-pointer is added to `2026-04-14-feat-rule-utility-scoring-plan.md`. Provisional-ordinal collision re-verified at ship.
- [ ] AC6 — `bash scripts/rule-metrics-aggregate.test.sh` green; no regression in #3509 drop-sentinel counts or `orphan_rule_ids`; `SCHEMA_VERSION` unchanged (still 1). (No `scripts/rule-prune.test.sh` exists and rule-prune is untouched this PR — Kieran b3.)

### Post-merge (operator)

- [ ] AC7 — after the next local compound run in a session that accumulated real incidents, the committed `rule-metrics.json` shows non-zero `fire_count` for the hooks that fired and `rules_unused_over_8w < total_rules_tagged`. Automation: the operator's own in-session compound run — part of normal flow, not a separate manual step. Use `Ref #6042` (not `Closes`) in the PR body; close #6042 after AC7 is observed once (the fix's real-data proof is post-merge).

## Domain Review

**Domains relevant:** Engineering (CTO + full 5-agent plan-review panel).

### Engineering (CTO)

**Status:** reviewed. **Assessment:** Option B is the decisively correct locality call (A rejected on privacy; C rejected — leaves a committed false-97/97 file). Read-time merge is the right blast-radius call over write-path flock-inode centralization. Ship elements 1-2 (load-bearing, small); the topology/age change amends ADR-3 → captured in ADR-091.

### Plan-review panel (consolidated)

**Status:** reviewed (DHH, Kieran, code-simplicity, architecture-strategist; spec-flow pass folded earlier). **Consolidation:** both simplification reviewers and both correctness reviewers converged on the same scope reduction → **ship Phases 1-3 (was 1+2+5); defer read-merge + `first_observed`.** Findings applied:
- *Mechanical (auto-applied to retained phases):* Kieran b1 (init `valid_lines`/`drops_total` top-level), b2 (gate the write not the report build), b3 (drop nonexistent rule-prune suite from ACs); code-simplicity (collapse compound exit-code matrix to `git diff --quiet` gate); architecture-strategist finding 6 (ADR-3 "supersession" + back-pointer).
- *Deferred with correctness notes carried forward:* Kieran (a) bare-primary-root inclusion + fallback-only-on-git-failure; Kieran (c) git-log anchor unreliable because AGENTS.md is a pointer-index (bodies in `AGENTS.{core,rest,docs}.md`) — prefer a flat past-epoch or search sidecars; Kieran (d1/d2) dual age-proxy + lying `first_seen` breadcrumb sweep; architecture-strategist finding 1 (read-only scheduled canary), 2 (`first_observed` cross-branch non-monotonicity → earliest-across-priors / git-log hardening), 3 (`git worktree list --porcelain` over glob), 4/5 (rotation is size-OR-age; drop-sentinel/orphan counts *aggregate*, not "unchanged"). All recorded in `## Deferred to follow-up`.

### Product/UX Gate

Skipped — Product NONE. No Files-to-Edit match `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or the UI-surface term list; no user-facing surface.

## Test Scenarios

| # | Scenario | Expected | Phase |
|---|---|---|---|
| T1 | Aggregator, empty log / absent file | exit 0, no write, committed file untouched, no unbound-var abort | 1 |
| T2 | Aggregator, sentinel-only log (non-empty, 0 rule_id rows) | exit 0, no write, drop breakdown to stderr | 1 |
| T3 | Aggregator, populated fixture | real counts; unused < total | 1 |
| T4 | `--dry-run` on populated + empty input | prints parseable JSON both times (hint unregressed) | 1 |
| T5 | compound Step 8, populated log | rule-metrics.json written + staged | 2 |
| T6 | compound Step 8, no change / malformed run | `git diff --quiet` → not staged | 2 |
| T7 | CI workflow | no `schedule:`; workflow_dispatch retained; header cites ADR-091 | 3 |
| T8 | Drop-sentinel + orphan behavior | summary.drops_* + orphan_rule_ids unchanged (single-log scope) | 1 |

## Alternatives Considered

| Option | Verdict | Why |
|---|---|---|
| **A — commit rotated/aggregated raw incidents snapshot so CI has data** | Rejected | Raw `command_snippet` carries absolute paths, git/gh identity, PR-body text (unscrubbed). Committing it is a privacy/secret-leak regression + per-worktree merge churn; defeats the deliberate gitignore. |
| **B — aggregate locally (compound), commit the redaction-safe aggregate, stop CI clobber** | **Chosen** | Data lives locally by design; the aggregate is already the committed redaction-safe artifact; compound already runs the aggregator locally. Minimal privacy surface, low churn, real (if under-complete) signal. |
| **C — accept CI-zero, learnings-only** | Rejected | Status quo; leaves a committed file asserting false 97/97 that every consumer reads. |
| **Cross-worktree read-merge + `first_observed` obsolescence in THIS PR** | Deferred | Both simplification reviewers: disproportionate for a p3 signal. Both correctness reviewers: multiple concrete bugs (bare-repo trap, pointer-index git-log anchor, cross-branch non-monotonicity, dual-proxy breadcrumb lie). Cutting dissolves them; build against real data. → `## Deferred to follow-up`. |
| **Write-path log centralization (single shared inode)** | Rejected (CTO) | Mutates three fire-and-forget producers whose flock correctness needs byte-identical inode resolution; disproportionate risk. Read-merge (the deferred approach) delivers the same completeness safely. |

## Deferred to follow-up

File ONE GitHub issue — **"rule-metrics: cross-worktree read-merge + `first_observed` obsolescence (completeness + prunability)"**, milestone `Post-MVP / Later`, `Ref #6042`, re-eval "after #6042 local-aggregation lands and real fire data accumulates ≥8 weeks." It carries the correctness notes the panel surfaced so the follow-up is built right:

1. **Cross-worktree read-merge** (aggregator reads all worktree logs read-only, no flock — commutative counts, tolerant `fromjson?`). Enumerate worktrees via **`git worktree list --porcelain`** (authoritative; includes the primary; de-dupes), NOT a `.worktrees/*` glob (silently misses non-standard paths — architecture-strategist finding 3). **MUST include the bare primary root's `.claude/.rule-incidents.jsonl`** (the ~577 KB canonical log); the git-unavailable fallback must trigger only on `git rev-parse` **non-zero exit**, never on the primary's *bareness* (Kieran (a) — the trap that would drop the largest log). `OUT` stays per-checkout; mark `rule-metrics.json` `merge=ours` in `.gitattributes` (now fully regenerable).
2. **`first_observed` obsolescence age proxy** — persisted per-rule stamp (first AGENTS.md appearance), carried forward by reading the prior committed `$OUT`, so a genuinely never-fired-but-long-present rule becomes prunable (today impossible: never-fired ⇒ `first_seen==null` ⇒ excluded). Backfill anchor: **prefer a flat past-epoch, NOT `git log -S'[id:…]' -- AGENTS.md`** — AGENTS.md is a pointer index (bodies in `AGENTS.{core,rest,docs}.md`), so the git-log date reflects the index-split refactor, not the rule's introduction, risking an all-recent stamp that silently pauses pruning 8 weeks (Kieran (c)). Carry-forward takes the **earliest** observed date across any readable prior to survive `merge=ours` discards (architecture-strategist finding 2). `SCHEMA_VERSION` stays 1 (field-additive).
3. **rule-prune proxy swap** — select on `first_observed`, KEEP `first_observed != null` (mirror #3123 mass-false-retirement guard) + a presence gate ("metrics predate first_observed migration → exit 0"). Sweep the five `first_seen` sites (`rule-prune.sh:66,89-92,172,214,258`) so the candidate TSV / issue body / `retired-rule-ids.txt` breadcrumb don't print "First seen: unknown" while selecting on `first_observed` (Kieran d2). Consider moving `summary.rules_unused_over_8w` to `first_observed` too, or document why the summary keeps first-*fire* semantics (Kieran d1). Add a `scripts/rule-prune.test.sh` for the selection change.
4. **Read-only scheduled canary** — assert `jq -e '.summary.rules_unused_over_8w < .summary.total_rules_tagged'` on the *committed* file inside an existing scheduled job (`rule-audit.yml`), restoring an automated locality-regression detector with zero producer (architecture-strategist finding 1). Add only after real data makes it green.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6 — filled above (threshold `none` with reason).
- **No-op guard must key on `valid_lines == 0`, not file-empty** — a sentinel-only (`error` rows, no `rule_id`) log is non-empty and would otherwise clobber committed real data with zeros. This is the exact failure this PR exists to kill.
- **`valid_lines`/`drops_total` must be initialized at top level** before the `[[ -s "$INCIDENTS_MERGED" ]]` block, or `set -euo pipefail` aborts the empty-file path with an unbound-variable error (the AC1 case).
- **Gate the write, not the report build** — exiting before Stage A/B/C makes `--dry-run` print nothing and regresses compound's unused-rules hint.
- **`git add` in compound must be conditional** (`git diff --quiet -- <OUT> || git add <OUT>`) — an unconditional add stages unchanged files or a malformed (`exit 2/3/4`) run's output.
- **Provisional ADR ordinal:** ADR-091 may be claimed by a sibling PR; `/ship`'s collision gate re-verifies. If renumbered, sweep this plan + tasks.md + all ACs citing the ordinal in the same edit (`2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md`).

## Deferral Tracking

- The single follow-up issue in `## Deferred to follow-up` (cross-worktree read-merge + `first_observed`) must be filed at ship time. Without it the obsolescence half stays deferred (as it was from #6037) and cross-worktree completeness is unfiled — invisible.
