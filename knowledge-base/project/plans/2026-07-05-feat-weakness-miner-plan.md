---
title: "feat(harness): read-only weakness-miner (Self-Harness Layer 2, detection-only)"
date: 2026-07-05
issue: 6037
branch: feat-self-improving-harness
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-05-self-improving-harness-brainstorm.md
spec: knowledge-base/project/specs/feat-self-improving-harness/spec.md
---

# feat(harness): Read-Only Weakness-Miner (#6037)

## Overview

Add a **weekly, read-only weakness-miner**: a GitHub Actions cron + bash script that clusters
Soleur's committed session-failure signal (the `knowledge-base/project/learnings/` corpus) into a
**ranked recurring-failure-pattern digest** (`knowledge-base/project/weakness-digest.md`), opened as
a bot-PR. A human triages the digest into the existing `/compound` → `cron-compound-promote` →
`eval-gate` pipeline.

This closes the one open stage of Soleur's self-improvement loop (weakness-mining / recurring-pattern
clustering — today 100% human). It is a faithful clone of the still-live `scripts/rule-metrics-aggregate.sh`
precedent: read committed KB → produce a committed snapshot → open a PR via
`.github/actions/bot-pr-with-synthetic-checks`. **Zero mutation surface** (TR1): the miner emits a
digest only; it never edits AGENTS.md, skills, or hooks.

Out of scope (deferred): the eval-gated additive-only auto-proposer (#6038), the product legibility
changelog (#6039), the single LLM classification pass (v1.1 — see Deferred Items), and the
obsolescence/rule-fire output (cut — see Research Reconciliation, tracked in #6042).

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Substrate = learnings corpus **+ raw `.claude/.rule-incidents.jsonl`** | `.rule-incidents.jsonl` is **gitignored** (`.gitignore:37`) and local-only. A fresh-checkout CI cron sees it empty. | v1 mines the **committed** substrate only: `knowledge-base/project/learnings/*.md`. The raw jsonl is never read in CI. |
| Secondary output = unused-rule / obsolescence candidates from `rule-metrics.json` (FR4/FR5) | `rule-metrics.json.summary` = `total_rules_tagged: 97, rules_unused_over_8w: 97` — 100% unused, because CI's incidents log is empty. In CI this can **only ever** render "no signal." | **Cut from v1** (code-simplicity + Kieran review): building a suppression detector whose only CI output is "no output" is YAGNI, and any count-equality detector is a fragile proxy for "the aggregate had zero input events." The gitignored-jsonl-in-CI gap is filed as **#6042**; add obsolescence output only if/when that lands. |
| FR2: "deterministic aggregation **+ one bounded classification pass**" | The LLM pass sends learnings (session-derived) to Anthropic → fires GDPR triggers (a)+(c) and needs an `ANTHROPIC_API_KEY` workflow secret → fires the IaC gate. | v1 = **deterministic-only**. LLM theme-naming deferred to v1.1 (#TBD). |
| Recency = "window the corpus" | 1793 committed learnings, 1303 with `## Session Errors`. Last-touch date resurrects learnings on unrelated bulk commits; rolling 30d re-ranks the same cluster ~4× → trains the triager to ignore the PR. | **7-day lookback on git first-appearance date** (`git log --diff-filter=A --format=%cI -- <file> \| tail -1`), matching the weekly cadence so each learning falls in exactly one window (no repetition) and the first run is naturally bounded (no 1303-file backlog). Explicit `>=` lower / `<` upper boundary. Rejected: last-touch date (Kieran), rolling 30d (advisor), since-last-digest high-water-mark (heavier; needs prior-digest parsing). |
| Cluster key = frontmatter `category`/`tags`/`module` | Frontmatter is a **taxonomy**, not a failure signature — `category: workflow` trivially forms a giant ≥3 cluster (advisor). | Phase 0.4 **go/no-go real-corpus spike** validates the key on real data; if it echoes taxonomy, switch to normalized error-signature n-grams from the `## Session Errors` body **before** fixtures encode the wrong key. |

## User-Brand Impact

**If this lands broken, the user experiences:** a mis-ranked or empty weekly digest — bounded, because
the digest only *informs* a human's `/compound` triage; it cannot itself change harness behavior.

**If this leaks, the user's data is exposed via:** N/A for v1 — the miner reads Soleur's own committed
internal dev-learnings (not customer workspace data) and performs **no external processing**. (The
deferred LLM pass would send internal learnings to Anthropic under the existing relationship; tracked
on the v1.1 issue.)

**Brand-survival threshold:** single-user incident.

CPO sign-off carried from brainstorm Phase 0.1 (CPO reviewed the brainstorm). `user-impact-reviewer`
runs at review time. Zero-mutation is the primary control; every downstream harness edit still passes
the compound-promote guardrails + eval-gate.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `scripts/weakness-miner.sh` selects learnings whose **git first-appearance date**
  (`git log --diff-filter=A --format=%cI -- <file> | tail -1`) is within the last 7 days (explicit
  `>=` lower boundary), then clusters by the Phase-0.4-validated key + a **column-anchored**
  `^## Session Errors` match (not a bare substring — learnings that *quote* the heading, like this
  plan's own artifacts, false-positive otherwise). Verify against a synthetic fixture: ranked digest
  lists ≥3-member clusters, omits <3-member and out-of-window ones. (`scripts/weakness-miner.sh`)
- [ ] **AC2** Recurrence threshold ≥ 3; clusters with < 3 members are omitted from the ranked
  section. Verify against a fixture with a 2-member and a 3-member cluster: only the 3-member appears.
- [ ] **AC3** First-run correctness: with no prior digest and a fixture where only K learnings first
  appeared in the last 7 days, exactly those K are considered (NOT the full backlog). (Guards the
  seed-digest-excludes-backlog trap.)
- [ ] **AC4** Zero-mutation, two independent boundaries (both asserted — they can drift):
  (a) the script has exactly **one write sink** (the digest path); a test tempts a second write and
  asserts non-zero abort; (b) the workflow's `bot-pr-with-synthetic-checks` `add-paths` is exactly
  `knowledge-base/project/weakness-digest.md` and a test asserts it never widens. The `add-paths`
  staging — not a bash guard — is the real mutation boundary (Kieran + architecture review). (TR1)
- [ ] **AC5** `.github/workflows/weakness-miner.yml` runs weekly (`schedule` cron), calls the script,
  opens a PR via `./.github/actions/bot-pr-with-synthetic-checks`. `actionlint` passes; `run:`
  snippet `bash -c`-checks. (`.github/workflows/weakness-miner.yml`)
- [ ] **AC6** Failure path: `notify-ops-email` on `failure()` (mirrors `rule-metrics-aggregate.yml`).
  No SSH anywhere. (`.github/workflows/weakness-miner.yml`)
- [ ] **AC7** `operator-digest` renders a one-line pointer to `weakness-digest.md` (FR6).
  (`plugins/soleur/skills/operator-digest/SKILL.md`)
- [ ] **AC8** Test suite exercises the operative path, not presence: clustering on synthetic fixtures,
  the ≥3 threshold, the 7-day first-appearance window (in/out), first-run bounding, and both
  zero-mutation boundaries. Runner verified against repo convention (Phase 0) before freezing paths.

### Post-merge (operator)

- [ ] **AC9** After the first weekly fire, confirm the bot-PR opened with a non-empty ranked digest.
  Automation: `gh run list --workflow=weakness-miner.yml` + `gh pr list --search "weakness-miner"
  --json number` (search the *workflow/branch* token, not `weakness-digest`, to avoid self-matching
  the digest/plan files). Folded into `/ship` post-merge verification (`hr-no-dashboard-eyeball`).

## Implementation Phases

### Phase 0 — Preconditions

1. Confirm the test runner: read the sibling `rule-metrics-aggregate` test + `bunfig.toml` to pick
   the harness (`.test.sh` vs bun/vitest) and the discovery glob. Do NOT assume; freeze the test path
   only after confirming.
2. Read `scripts/rule-metrics-aggregate.sh` header + `bot-pr-with-synthetic-checks` `action.yml`
   inputs to reuse the exact PR contract (add-paths, branch-prefix, commit-message, pr-body ≥50%
   path-cited per the #2905 body-vs-diff guard).
3. Confirm the first-appearance recency command against a real learning file; reuse the canonical
   gsub awk (`skill-security-scan/scripts/run-scan.sh:34`) for reading frontmatter fields only.

### Phase 0.4 — Clustering-key go/no-go spike (real corpus, BEFORE writing the pipeline)

Run a ≤20-line awk/jq spike applying the proposed key to the **actual** last-7-day corpus; eyeball the
top clusters. If they are genuine recurring failure patterns → proceed with the frontmatter key. If
they are taxonomy echoes → switch to **normalized error-signature n-grams from the `## Session Errors`
body** before any fixture is written. This is the load-bearing design decision; synthetic fixtures pass
regardless of real signal. Record the chosen key + spike output in the PR body.

### Phase 1 — Deterministic miner script (RED → GREEN)

1. Write the failing test (AC8) first: synthetic fixture learnings dir with controlled git
   first-appearance dates.
2. Implement `scripts/weakness-miner.sh`:
   - Select learnings by 7-day git first-appearance window (`--diff-filter=A`).
   - Cluster by the Phase-0.4-validated key + column-anchored `^## Session Errors`; count occurrences.
   - Rank clusters with ≥3 members.
   - Emit `knowledge-base/project/weakness-digest.md` through a single write sink (AC4a).
3. GREEN the test.

### Phase 2 — Workflow + wiring

1. `.github/workflows/weakness-miner.yml`: weekly `schedule` + `workflow_dispatch`; run the script;
   `bot-pr-with-synthetic-checks` PR with single-path `add-paths` (AC4b/AC5); `notify-ops-email` on
   `failure()` (AC6). Pin action SHAs like the sibling. `actionlint` + `bash -c` the `run:` snippet.
2. `operator-digest` one-line pointer (AC7).
3. Seed an initial `weakness-digest.md` (header + "first run pending"). AC3 guards that this seed does
   not swallow the backlog.

### Phase 3 — Verify

1. Full test suite via the Phase-0 runner. `actionlint`.
2. Dry-run the script against the real 7-day window; eyeball the digest; assert `git status
   --porcelain` touches only the digest path (AC4a).

## Non-Goals

- **NG1** No LLM classification pass in v1 (v1.1 — Deferred Items).
- **NG2** No auto-proposal / auto-edit of AGENTS.md or skills (#6038).
- **NG3** No user-facing changelog (#6039).
- **NG4** No obsolescence / rule-fire output — CI's `rule-metrics.json` is structurally all-zero
  (empty incidents log); tracked in **#6042**.
- **NG5** No fix to the `.rule-incidents.jsonl`-not-in-CI gap here (#6042).
- **NG6** No HarnessX processor-combo / AEGIS search (over-engineering at markdown scale — CTO).

## Deferred Items (tracking issues)

- **LLM theme-naming pass (v1.1) — #TBD:** one bounded Anthropic call per digest to name cluster
  themes. **Substrate-lock (architecture review):** this recreates `cron-compound-promote`'s exact
  shape (Anthropic call + `ANTHROPIC_API_KEY`), which was deliberately migrated GHA → Inngest (#3948,
  ADR-033). v1.1 likely belongs on the **Inngest** substrate — where ADR-054's `safeCommitAndPr()`
  sole-write-path actually applies — NOT bolted onto this GHA workflow. Re-eval: v1 shipped ≥1 month
  of digests the operator found actionable; reuse compound-promote's resolved Anthropic-DPA path;
  adds a secret (→ IaC gate) and re-fires GDPR triggers (a)+(c).

## Domain Review

**Domains relevant:** Engineering, Product (carried forward from brainstorm `## Domain Assessments`).

### Engineering

**Status:** reviewed (carry-forward + plan-time verification + 4-agent plan review)
**Assessment:** Weakness-mining is the only read-only stage → correct first increment. Faithful clone
of the still-live `rule-metrics-aggregate` GHA cron; ADR-027 *principle* holds. Plan review tightened:
cut the always-empty obsolescence output, fixed recency to 7-day first-appearance, split zero-mutation
into two asserted boundaries, corrected the ADR-054 mis-citation. Complexity: small.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — mechanical UI-surface scan of Files to Create (`.sh`, `.yml`, `.md`, test) matched
no UI path. Pure dev-harness automation.
**Agents invoked:** none · **Skipped specialists:** none · **Pencil available:** N/A (no UI surface)

## Infrastructure (IaC)

Skip — v1 introduces no new infrastructure (reuses the existing GHA runner + committed
`bot-pr-with-synthetic-checks` action; no new secret, server, vendor, or DNS). The deferred LLM pass
(v1.1, likely Inngest) routes through the IaC gate at that time.

## Observability

```yaml
liveness_signal:
  what: weekly weakness-miner workflow run + bot-PR opened
  cadence: weekly (schedule cron)
  alert_target: notify-ops-email on failure() (mirrors rule-metrics-aggregate.yml)
  configured_in: .github/workflows/weakness-miner.yml
error_reporting:
  destination: GitHub Actions run status + notify-ops-email
  fail_loud: true
failure_modes:
  - mode: aggregation script error
    detection: workflow job fails (non-zero exit)
    alert_route: notify-ops-email + gh run status
  - mode: no ≥3 cluster in the 7-day window (empty ranked section)
    detection: digest renders "no recurring pattern this window" (benign)
    alert_route: none (expected quiet state)
logs:
  where: GitHub Actions run logs
  retention: default GH Actions retention
discoverability_test:
  command: gh run list --workflow=weakness-miner.yml
  expected_output: most-recent run status (success/failure); no ssh
```

## Architecture Decision (ADR/C4)

**ADR:** None required — a faithful clone of the unmodeled `rule-metrics-aggregate` dev-harness cron;
no new trust/mutation/tenancy boundary. **Citation correction (architecture review):** the write path
is the GHA `bot-pr-with-synthetic-checks` action, whose governing precedent is `rule-metrics-aggregate`
— **NOT ADR-054**, which scopes only the *Inngest*-side `safeCommitAndPr()` helper (its parity test
walks `server/inngest/functions/`). ADR-027 is cited as *principle* (stateless self-modifying cron);
its own implementation has since migrated GHA → Inngest (#3948, ADR-033), so v1 mirrors the still-live
`rule-metrics-aggregate` GHA, not ADR-027's current substrate.

**C4 views:** No C4 impact. Checked all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`): the sibling
dev-tooling crons (`rule-metrics-aggregate`, `compound-promote`) are **not** modeled — C4 scope is the
product system, not the dev-harness. The miner introduces no new external actor, external system/vendor
(v1 has no Anthropic edge), data store, or access relationship.

## Sharp Edges

- `## User-Brand Impact` is filled (single-user incident) — deepen-plan Phase 4.6 passes.
- Recency uses **git first-appearance** (`--diff-filter=A`), NOT last-touch — a bulk lint/rename commit
  must not resurrect an already-digested learning (Kieran). 7-day window on a 7-day cron ⇒ each learning
  falls in exactly one digest (no repetition; the failure mode is a skipped weekly run dropping that
  week — acceptable for a dev-tooling digest; a manual `workflow_dispatch` catches up).
- Zero-mutation is TWO boundaries that can drift independently — assert both (script single-sink AND
  workflow single `add-paths`); the `add-paths` staging is the operative one.
- `^## Session Errors` must be column-anchored — learnings (and this plan) *quote* the heading.
- The clustering **key** is load-bearing and unvalidatable by synthetic fixtures — run the Phase-0.4
  real-corpus spike first.

## Open Code-Review Overlap

None. Checked `gh issue list --label code-review --state open` against the planned files
(`scripts/weakness-miner.sh`, `.github/workflows/weakness-miner.yml`, `weakness-digest.md`,
`operator-digest/SKILL.md`) — no open scope-out names them. (Grep excluded the plan/digest paths to
avoid self-match.)
