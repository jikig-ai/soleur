---
title: "feat: close-loop sweep-completeness gate + reusable enforcement-contract registry"
type: feat
date: 2026-06-14
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5269
branch: feat-close-loop-engineering-gaps
pr: 5257
spec: knowledge-base/project/specs/feat-close-loop-engineering-gaps/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-06-14-close-loop-engineering-gaps-brainstorm.md
semver: minor
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# Plan: Close-Loop Sweep-Completeness Gate + Enforcement-Contract Registry

## Overview

Convert the prose rule `hr-write-boundary-sentinel-sweep-all-write-sites` (and the recurring
cross-file-drift class) into a **mechanical CI gate**, backed by a small **flat registry** that
future gates can grow by data edit, not code. The registry is the "close-loop harness": adding
a covered sibling-set = appending one JSON entry.

**Scope (operator-confirmed 2026-06-14):** Gap 3 (sweep-completeness) + the registry.
**Gap 1 (format-contract) DEFERRED** — its cited classes are already CI-gated (Research
Reconciliation). Mechanism-only; **zero new AGENTS.md rules** (`B_ALWAYS` ~23 B from the 23000
reject ceiling, `scripts/lint-agents-rule-budget.py:50`).

**Plan-review applied (2026-06-14):** DHH + Kieran + code-simplicity + spec-flow-analyzer.
Cut `mode`/`symmetric`/`format_contracts` (YAGNI); fixed two factually-wrong ACs; adopted the
repo's `set -uo pipefail` convention; added fail-closed + registry-self-consistency correctness.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Gap 1: hand-authored artifacts skip format guarantees (blog `ogImage`, distribution format) | **Already CI-gated**: `seo-aeo-drift-guard.test.ts`, `distribution-content-format.test.ts`, `marketing-content-drift.test.ts`, `validate-seo.test.ts` (all `plugins/soleur/test/`, run by `ci.yml` `test-bun` shard) | **Defer Gap 1** |
| Plan/spec frontmatter unenforced | `plugins/soleur/test/lane-frontmatter.test.sh` already validates `lane:` | Not a Gap-1 instance |
| Learning-file frontmatter is an uncovered prose contract | **Trap**: corpus inconsistent (`## Tags` footer vs YAML); a gate fails the corpus en masse | Out of scope |
| Build an AGENTS.md rule-budget gate | **Already wired** — `scripts/test-all.sh:121-122` + `lefthook.yml:96` | Do NOT rebuild |
| Gap 3: no existing co-change/parity registry | **Confirmed** — parity is per-test-suite; no declarative registry | Build it (this PR) |
| Harness = `.claude/hooks/` pair | **Wrong surface** — sweep needs the whole PR changeset (`gh pr diff`), invisible to a per-Write hook | CI bash on `pr-quality-guards.yml` |
| `bash scripts/test-all.sh scripts` runs `.github/scripts/test/` fixtures | **FALSE** (Kieran P0-1) — `run-all.sh` is invoked ONLY by `pr-quality-guards.yml:18`; the `scripts` shard runs a hardcoded suite list | AC for the fixture targets `bash .github/scripts/test/run-all.sh` |
| Scripts use `set -euo pipefail` | **FALSE** — every `.github/scripts/check-*.sh` uses `set -uo pipefail` (no `-e`) so they enumerate all violations | Use `set -uo pipefail` |

## User-Brand Impact

- **If this lands broken, the user experiences:** a false-positive sweep gate blocks a correct
  PR (operator friction), OR — worse — a false-negative lets a cross-file drift ship that
  degrades a user-facing artifact (the 2026-06-11/06-13 class).
- **If this leaks:** N/A — the gate reads file *paths* from the PR diff; no user data, secrets,
  or PII processing.
- **Brand-survival threshold:** single-user incident (carried from brainstorm, #5175 policy).
  CPO signed off at brainstorm (carry-forward); `user-impact-reviewer` runs at PR review.

## Compliance (GDPR Gate — Phase 2.7)

Trigger (b) (single-user-incident threshold) fired → recorded explicitly, not skipped silently.
**Inline assessment:** no schema/migration/auth/API/SQL surface, no data movement — the gate
computes set-membership over PR file *paths*. No regulated-data surface. `/soleur:gdpr-gate`
not spawned (no data processing to audit). Advisory: **N/A**.

## Architecture

### The registry (`.github/enforcement-contracts.json`)

Flat list; read by `jq`. Self-documenting via a `_doc` key (JSON has no comments; co-located
with the data, no extra surface, no AGENTS.md rule-budget cost):

```json
{
  "_doc": "Sweep-completeness contracts. To cover a new set: append to sibling_sets. Each entry: name, trigger[], dependents[], reason. Paths are repo-root-relative exact full paths (no globs). A trigger change with any dependent unchanged fails the gate. See .github/scripts/check-sweep-completeness.sh.",
  "sibling_sets": [
    {
      "name": "cron-tier2-parity",
      "trigger": ["apps/web-platform/server/inngest/cron-manifest.ts"],
      "dependents": [
        "apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts",
        "apps/web-platform/test/server/inngest/cron-shared.test.ts"
      ],
      "reason": "TIER2_DEFERRED_CRONS in cron-manifest.ts is asserted by both parity tests; changing the set obligates updating both. Evidence: 2026-06-13 session error #6 (missed cron-shared.test.ts)."
    }
  ]
}
```

- **No `mode` field, no `symmetric` mode, no `format_contracts` key** (cut at plan-review — speculative; one legal value is noise; reserved keys for deferred features are tombstones). Re-introduce a `mode` field the day a second, evidenced shape appears — a ~10-line change, the same argument that justifies the registry.
- **Seed = ONE evidenced entry** (2026-06-13). Adding more = a data edit. Candidate next: `github-app-manifest-parity` — verify its exact invariant at /work before adding; do not seed unverified (paraphrase-without-verification is the #1 plan-drift class).

### The executor (`.github/scripts/check-sweep-completeness.sh`)

Semantics — for each `sibling_sets[]` entry, gate **FAILS** iff `(any trigger ∈ changed) AND (any dependent ∉ changed)`. Editing a dependent alone is allowed (kills the false-positive a symmetric touch-all would cause on a lone typo fix).

Required behaviors (each maps to a review finding):

1. `#!/usr/bin/env bash` + `set -uo pipefail` — **no `-e`** (repo convention; `-e` would abort before enumerating all violations). [Kieran P0-2 / spec-flow P0-1]
2. **Args:** `$1` = registry path (default `.github/enforcement-contracts.json`); `$2` = path to a file of newline-separated changed paths, or `-` for stdin (optional). **`$2` short-circuits ALL `gh`/`PR_NUMBER` access** — if `$2` is set, never touch `gh` or env (offline fixture contract). [spec-flow P1-5 / Kieran P2-2]
3. **Changeset derivation (CI path, `$2` unset):** `gh pr diff "$PR_NUMBER" --repo "$GH_REPO" --name-only`. If the diff fetch fails OR yields empty, **`exit 1` with `::error::` ("cannot derive changeset → gate cannot prove the invariant; fail-closed")** — never `exit 0` on an unobtainable changeset (avoids the silent-fallback false-negative). [spec-flow P0-1]
4. **Registry parse:** `jq empty "$1" 2>/dev/null || { echo "::error::malformed registry"; exit 1; }` BEFORE iterating; iterate via `while … done < <(jq -c '.sibling_sets[]? // empty' "$1")` (the `?` tolerates a missing key without crashing). [spec-flow P0-4]
5. **Registry self-consistency (runs every invocation, before set evaluation):** every `trigger[]` and `dependents[]` path must exist on disk; any missing → `exit 1` ("registry references missing path X — update the registry"). A `trigger-dependents` entry with `dependents: []` → `exit 1` (misconfiguration). This is the guarantee the registry can't rot silently, and it makes a legitimate dependent-deletion obligate a same-PR registry edit (self-enforcing close-loop). [spec-flow P0-3 / P1-2 / Kieran P1-2]
6. **Exact full-path matching** via `grep -Fxq` against the normalized changeset (strip blank lines / CRLF). Globs are **not** supported. `cron-manifest.ts` must NOT match `legacy-cron-manifest.ts`. [spec-flow P0-2 / P2-1]
7. **Aggregate across ALL sets** — collect every violation, print **every** missing dependent (work-list discipline), single `exit 1` at the end; one passing set must never mask a failing set. [spec-flow P1-1]
8. **Positive confirmation** per evaluated set on success (constitution: "Diagnostic scripts must print positive confirmation on success", line 282) — descriptive line, not claiming an existing `[ok]` token. Use `.name // "(unnamed)"` in messages. [Kieran P2-1 / P2-2]

### CI wiring (`.github/workflows/pr-quality-guards.yml`)

New job, peer to the existing checkout-based jobs (`userid-bypass-lint`, `client-pii-grep`):
- **`actions/checkout`** the PR head (the self-consistency `test -f` needs the working tree — unlike `stray-worktree-marker-block`, which is checkout-free). [new — required by behavior #5]
- env: `GH_TOKEN: ${{ github.token }}`, `PR_NUMBER: ${{ github.event.pull_request.number }}`, `GH_REPO: ${{ github.repository }}`; workflow-level `permissions: contents: read, pull-requests: read` already present (no per-job block).
- **No opt-out label** (model on `pii-grep`, with a one-line rationale comment) — at single-user-incident threshold the gate should not carry a `claude-config-change` bypass. [Kieran P1-1]

### Fixture (`.github/scripts/test/test-check-sweep-completeness.sh`)

Auto-discovered by `.github/scripts/test/run-all.sh` (the `guard-script-fixture-tests` job in `pr-quality-guards.yml:18`). Drives the executor with a **synthetic temp registry** + synthetic changeset files (`cq-test-fixtures-synthesized-only`; never the live registry, never `gh`). PASS/FAIL counter; **`exit 1` if any case fails** (so a fixture that prints FAIL but exits 0 is itself caught). Runs offline with `PR_NUMBER`/`GH_REPO` unset. [spec-flow P2 / Kieran P0-1]

## Files to Create

- `.github/enforcement-contracts.json` — registry (seed: 1 set, `_doc` key).
- `.github/scripts/check-sweep-completeness.sh` — executor (behaviors 1-8).
- `.github/scripts/test/test-check-sweep-completeness.sh` — fixture (TS1-TS8).

## Files to Edit

- `.github/workflows/pr-quality-guards.yml` — add the checkout-based sweep-completeness job.
- (No edits to the 4 existing format tests — Gap 1 deferred.)

## Test Scenarios (Given/When/Then) — the behavioral source of truth

The fixture implements these; the ACs reference the fixture rather than restating each branch.

- **TS1 (RED, the 2026-06-13 regression):** synthetic registry (cron-tier2-parity, all paths `test -f`-present via temp stubs); changeset = only the trigger → exit 1, names **both** dependents missing.
- **TS2 (GREEN):** changeset = trigger + both dependents → exit 0.
- **TS3 (no false positive):** changeset = only a dependent (no trigger) → exit 0.
- **TS4 (anchoring):** trigger `cron-manifest.ts`; changeset contains only `legacy-cron-manifest.ts` → exit 0 (no substring match). [spec-flow P0-2]
- **TS5 (registry integrity):** (a) `sibling_sets: []` → exit 0; (b) malformed JSON → exit 1; (c) key absent → exit 0 (treated as no sets); (d) a `dependents: []` entry → exit 1; (e) a trigger/dependent path that does not exist on disk → exit 1. [spec-flow P0-3/P0-4/P1-2]
- **TS6 (multi-set aggregation):** two sets, both violated → output names missing dependents from **both**, single exit 1. [spec-flow P1-1]
- **TS7 (no masking):** set A satisfied + set B violated → exit 1 (a pass must not mask a fail). [spec-flow P1-1]
- **TS8 (fail-closed changeset):** `$2` unset, `gh` unavailable/empty → exit 1, not exit 0. [spec-flow P0-1]

## Acceptance Criteria

### Pre-merge (PR / CI)

- AC1. `jq empty .github/enforcement-contracts.json` exits 0; `jq '.sibling_sets | length' …` ≥ 1. (No `format_contracts` assertion — key cut.)
- AC2. `bash .github/scripts/test/test-check-sweep-completeness.sh` exits 0 and reports every case TS1-TS8 PASS; it is driven by a synthetic temp registry and runs with `PR_NUMBER`/`GH_REPO` unset.
- AC3. `bash .github/scripts/test/run-all.sh` exits 0 and its output includes `=== test-check-sweep-completeness.sh ===` (proves the fixture is actually discovered/run by the real CI harness). [Kieran P0-1]
- AC4. The new `pr-quality-guards.yml` job executes on this PR's `pull_request` event and exits 0 — i.e., the job is wired and does not error on a non-triggering PR (no seeded trigger is in this diff, so the gate is correctly a no-op here; real RED/GREEN proof lives in AC2). [Kieran P1-3]
- AC5. Registry baseline on main: `jq -r '.sibling_sets[] | (.trigger[], .dependents[])' .github/enforcement-contracts.json | while read -r f; do test -f "$f" || echo "MISSING: $f"; done` prints no `MISSING` lines (every declared path exists). [Kieran P1-2 / spec-flow P0-3]
- AC6. Zero new AGENTS.md rules: `git diff origin/main...HEAD -- AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` adds no `[id: …]` line; `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` exits 0.
- AC7. `check-sweep-completeness.sh` opens with `set -uo pipefail` (not `-euo`); `grep -n 'set -' .github/scripts/check-sweep-completeness.sh` confirms.

### Post-merge (operator)

- AC8. None required — pure CI/config change; no migration, infra, or external state. The merge is the deployment (the gate is live on the next PR). `Automation: not applicable`.

## Observability

```yaml
liveness_signal:
  what: sweep-completeness job runs on every pull_request event
  cadence: per-PR (opened/synchronize/reopened/edited)
  alert_target: GitHub PR checks (red X blocks merge via branch protection)
  configured_in: .github/workflows/pr-quality-guards.yml
error_reporting:
  destination: GitHub Actions job log + the check script's ::error:: + stdout naming each missing dependent
  fail_loud: true (exit 1 -> job fails -> PR check red; fail-closed on unobtainable changeset / malformed or inconsistent registry)
failure_modes:
  - mode: false negative (a real drift not yet in the registry ships)
    detection: post-merge surfaces as a future session error; mitigated by appending a registry entry
    alert_route: compound learning -> registry entry
  - mode: false positive (legitimate lone-dependent edit blocked)
    detection: PR author sees the named dependent + reason; trigger->dependents mode minimizes this
    alert_route: PR comment / registry reason field
  - mode: malformed / inconsistent registry, or unobtainable changeset
    detection: jq parse / test -f / gh diff failure -> exit 1 (fail-closed)
    alert_route: CI job log ::error::
logs:
  where: GitHub Actions run logs for pr-quality-guards.yml
  retention: GitHub default (90 days)
discoverability_test:
  command: bash .github/scripts/test/test-check-sweep-completeness.sh   # NO ssh
  expected_output: all TS1-TS8 cases PASS; exit 0
```

## Domain Review

**Domains relevant:** Engineering (carry-forward), Product (carry-forward)

### Engineering (CTO)
**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Cleanest deterministic win (pure set-math over `gh pr diff`). No architecture decision triggered (no new service/data-model/boundary). Zero rule budget. Surface = CI bash on the proven `pr-quality-guards.yml` + `run-all.sh` fixture convention.

### Product/UX Gate
**Tier:** none
**Decision:** N/A — Files-to-Create/Edit contain no UI-surface paths; mechanical UI override did not fire. Pure CI/config/orchestration.
**Pencil available:** N/A (no UI surface)

## Infrastructure (IaC) — Phase 2.8

Reviewed; **skipped** — no new server/service/cron/secret/vendor/DNS/firewall. A new GitHub
Actions job + a bash script + a JSON config is not infrastructure provisioning (no SSH, no
`systemctl`, no Doppler secret write, no vendor dashboard, no Terraform resource). The
`iac-routing-ack` comment opts out of the false-positive substring match on infra-pattern
examples quoted herein.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Symmetric "touch-one-touch-all" sweep / a `mode` field | Rejected (plan-review) — false-positive friction; one legal value is noise. Re-add a mode field when an evidenced second shape appears. |
| `.claude/hooks/` PreToolUse pair | Rejected — a per-Write hook never sees the whole PR changeset. |
| Hardcode the one sibling set in bash | Rejected — operator wants data-driven growth; flat JSON is barely larger and a 2nd entry is on deck. |
| Build Gap 1 format-contract now / consolidate existing format tests | Deferred (operator) — cited classes already CI-gated; consolidation = churn, no new protection. |
| `format_contracts: []` reserved key, extension note in AGENTS.md | Cut (plan-review) — tombstone for a deferred feature; AGENTS.md is at budget. Doc lives in the registry `_doc` key. |

## Deferrals to Track (Phase 6)

- **Gap 1 (format-contract)** — file a tracking issue: cited classes (blog/distribution) already
  CI-gated; build a registry consumer only if a real bypass recurs in an uncovered class.
  Re-eval criterion: a new session error showing a hand-authored artifact format bug that no
  existing test caught.
- Existing brainstorm defers stand: #5270 (gaps 2/5/6), #5271 (gap 4), #5272 (gap 7).

## Sharp Edges

- **Rename limitation (v1, documented):** `gh pr diff --name-only` reports only the NEW path of
  a rename. A *renamed* (not edited) trigger file won't appear under its old registry path →
  trigger won't fire → false negative even though the rename likely broke the dependents'
  imports. Accepted for v1 (YAGNI); the registry self-consistency check (behavior #5) catches
  the *next* PR that edits the renamed trigger, because the old path no longer exists on disk →
  exit 1 forces a registry update. State this; do not imply trigger-on-change is complete. [spec-flow P1-3]
- The `## User-Brand Impact` section must stay filled (no TBD) — deepen-plan 4.6 + preflight Check 6.
- Fixture uses a synthetic temp registry, NOT the live `.github/enforcement-contracts.json`.
- The CI *job* needs `actions/checkout` + `gh` auth + PR context; the *fixture* must NOT call
  `gh` (drive via `$2`) so it runs offline in `run-all.sh`.
- Don't seed unverified sibling sets — confirm each trigger->dependents invariant against the
  actual asserting test before adding.
- AC4/AC5 are clean-state proofs (vacuous-green on a non-triggering PR / existence-only); the
  real predicate coverage lives in the fixture (AC2). Don't over-trust AC4. [Kieran P1-3 / Simplicity]
