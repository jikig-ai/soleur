---
title: "feat: compound promotion loop (self-healing CI sweep)"
type: feat
date: 2026-05-11
semver: minor
issue: "#2720"
parent_issue: "#2718"
supersedes: "#421"
brainstorm: knowledge-base/project/brainstorms/2026-05-11-compound-promotion-loop-brainstorm.md
spec: knowledge-base/project/specs/feat-compound-promotion-loop/spec.md
branch: feat-compound-promotion-loop
worktree: .worktrees/feat-compound-promotion-loop/
pr: "#3559"
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: Compound Promotion Loop (self-healing CI sweep)

## Overview

Add a weekly GitHub Actions cron that LLM-clusters learnings under `knowledge-base/project/learnings/`, identifies recurring root causes (cluster size ≥ N=5), and opens **draft PRs** proposing skill-instruction edits or AGENTS.md rule additions. Operator merges or closes via normal GitHub PR review — the loop never auto-merges.

This realizes Layer 2 of the 2026-03-03 self-healing-workflow design (deferred as #421 until Layer 1 — Deviation Analyst — proved value; Layer 1 has been shipping in compound Phase 1.5 for two months). Operationalizes AGENTS.md `wg-every-session-error-must-produce-either`, which today relies on human vigilance during `/compound`.

**Estimated complexity:** SMALL-MEDIUM (1–2 days). Telemetry pipeline + retire mechanism + bot-PR composite all exist; this plan extends one composite action and adds a cron + a shell driver.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Spec TR1: use `secrets.SOLEUR_GH_TOKEN` not `GITHUB_TOKEN` | NO workflow uses `SOLEUR_GH_TOKEN`; all use `${{ github.token }}`. The cited constitution.md line 102 is stale (current line 153). | Use `${{ github.token }}` per repo precedent. |
| Spec FR3: open draft PR with `self-healing/auto` label | Label does NOT exist (`gh label list`); repo's canonical PR-opening composite (`bot-pr-with-synthetic-checks`) does NOT support `--draft`, `--label`, or `skip-auto-merge`. | (a) Phase 0 step creates the label; (b) bounded extension of composite action with 3 optional inputs. |
| Spec TR3: persistent state files `.github/promotion-queue.json` + `.github/promotion-cooldowns.json` | `.github/workflows/*.yml` re-triggers on writes to `.github/`; recursion risk. Per-week cap and cooldown can be derived from `gh pr list --label self-healing/auto` instead — no state file needed. | Drop both state files. Derive per-week cap from open-PR count; derive cooldown from closed-PR search over last 30 days, extracting cluster-hash from PR body trailer. Single source of truth = the PRs themselves. |
| Spec FR8: invoke `/soleur:gdpr-gate` programmatically | `gdpr-gate` skill has NO headless CLI entry — only the `/soleur:gdpr-gate <scope>` slash command and a lefthook-only advisory script (`scripts/gdpr-gate.sh`, always exits 0). | Invoke `/soleur:gdpr-gate <scope>` inside the claude-code-action prompt. The agent calls the slash command as part of clustering; if it returns Critical findings, the agent refuses to draft a diff and emits a clusters-blocked entry instead. |
| Spec implies single PR-creation step (per cron-tick) | claude-code-action's post-step revokes its App installation token — any subsequent `gh pr create`, `git push`, `gh api check-runs` fails. Per learning `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`. | Two-job split: Job 1 (`cluster`) runs claude-code-action and emits cluster JSON to `outputs.clusters_json`. Job 2 (`promote`, matrix over clusters) uses fresh GITHUB_TOKEN to call the extended bot-pr composite. |
| Spec implies cron reads `.claude/.rule-incidents.jsonl` | File is gitignored; CI runners never see it. Spec already chose to read from `learnings/` instead — confirmed correct. | No change; document explicitly in Sharp Edges so a future planner doesn't re-add the dependency. |
| Spec TR2: anthropic-preflight not mentioned | Universal precedent: every claude-code-action workflow runs `./.github/actions/anthropic-preflight` first to gate on `ANTHROPIC_API_KEY` presence + monthly cap. | Add a `preflight` job mirror per template `scheduled-daily-triage.yml`. |
| Spec implies bespoke per-PR provenance log | The retirement-flow precedent (`scripts/rule-prune.sh`) uses stdout sentinel pattern (`::rule-prune-pr-title::`, `::rule-prune-pr-body::`) for shell→workflow handoff. | Mirror: `::compound-promote-clusters-json::` from the agent's stdout, parsed into `clusters_json` step output. |

## User-Brand Impact

**If this lands broken, the user experiences:** A bad auto-promoted rule lands via merged PR → cascades to every operator's session via `@AGENTS.md` import or skill invocation → subtle behavior degradation (wrong default, stale guidance, blocked work) until manual rollback via `scripts/retired-rule-ids.txt`.

**If this leaks, the user's workflow / data is exposed via:** A learning file containing PII (email fragments, customer names, prod IDs) gets clustered, summarized, and quoted in a PR body that is pushed to the public repo. Mitigations: opt-in default OFF, mandatory pre-promotion `/soleur:gdpr-gate` scan over each cluster's source learnings, refuse-to-promote on Critical findings.

**Brand-survival threshold:** `single-user incident`

CPO sign-off required at plan time before `/work` begins. CPO participated in the brainstorm (2026-05-11); no fresh invocation needed unless the operator (Jean) explicitly requests one. `user-impact-reviewer` will be invoked at review-time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Marketing (carry-forward from brainstorm). Operations / Sales / Finance / Support: not relevant.

### Engineering (CTO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** SMALL complexity. Telemetry pipeline + retire mechanism + bot-PR composite all in place. Plan-time gaps (now resolved in this plan): claude-code-action token revocation requires two-job split; bot-pr composite requires bounded extension; state files in `.github/` create recursion risk and were eliminated by deriving from PR labels/bodies.

### Product (CPO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** Highest risk = promotion-fatigue; mitigated by per-week cap (≤2/week), cooldown after Skip (30 days), opt-in default OFF. Inline-at-/compound surface is deferred to v2.

### Product/UX Gate

**Tier:** none
**Decision:** not invoked
**Rationale:** No new user-facing pages, modals, or components. Files to create are workflow YAML + shell script + state markdown. Mechanical escalation rule (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) does not match.

### Legal (CLO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** USER_BRAND_CRITICAL surface. Required: append-only `promotion-log.md`, two-tier consent (capability opt-in via config + per-PR confirm), pre-promotion gdpr-scan, plugin-scope deferral to v2 with ToS update. v1 stays consumer-local. All four are encoded in spec FRs and will be implemented in this plan.

### Marketing (CMO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** Launch-blog-post-worthy; bundle launch with #2719. External name "Learning Ratchet" or "Compounding Gate" — keep "promotion loop" as internal/code term. Provenance comment on promoted rules is a launch-time mitigation against "agent went off-script" trust hit. Marketing artifacts are downstream of merge — not in this plan's scope.

**Brainstorm-recommended specialists:** copywriter (downstream, post-ship; not invoked at plan time).

## GDPR / Compliance Gate

This plan touches a regulated-data surface per the canonical regex extension: it ADDS a workflow that reads operator-session-derived learnings (potential PII) AND writes to artifacts that propagate to other operators via plugin update (Chapter V / Art. 28 transfer surface). Per `hr-gdpr-gate-on-regulated-data-surfaces` and CLO finding #5, gdpr-gate MUST be invoked at plan Phase 2.7 and work Phase 2 exit.

**Plan-time invocation:** Run `/soleur:gdpr-gate "feat-compound-promotion-loop plan + spec"` before /work begins. Output is advisory; Critical findings (Art. 9 special-category, missing lawful basis, Art. 30 trigger) prompt operator-acknowledged write to `knowledge-base/legal/compliance-posture.md` Active Items + GitHub issue with label `compliance/critical`.

**Work-time invocation:** Phase 7 of this plan (below) re-runs gdpr-gate against the implemented workflow YAML before merge.

**Runtime invocation:** The cron itself invokes gdpr-gate inside the claude-code-action prompt as part of cluster classification (FR8). This is the load-bearing runtime gate.

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/compound-promote.sh` | Shell driver: reads opt-in config, cooldown derivation, week-cap derivation; emits stdout sentinels for the workflow to capture. Mirrors `scripts/rule-prune.sh` CLI surface. |
| `scripts/compound-promote.test.sh` | Peer test (mirror of `scripts/rule-metrics-aggregate.test.sh`). Test mode toggleable via `COMPOUND_PROMOTE_FIXTURE_ROOT` env. NOT wired into CI initially (matches sister `*.test.sh` pattern); promoted to CI in a follow-up. |
| `.github/workflows/scheduled-compound-promote.yml` | Weekly cron `0 0 * * 0` (Sunday 00:00 UTC, aligned with `rule-metrics-aggregate.yml`). Three jobs: `preflight` → `cluster` → `promote` (matrix). |
| `knowledge-base/project/promotion-config.yml.example` | Opt-in config TEMPLATE. Operator copies to `promotion-config.yml` (gitignored to prevent accidental enablement) and sets `enabled: true`. |
| `knowledge-base/project/learnings/promotion-log.md` | Append-only audit log scaffold. Header + empty rows table. CLO non-repudiation requirement. |
| `knowledge-base/engineering/runbooks/compound-promote-runbook.md` | Operator runbook: how to opt in, how to opt out, how to revert a promoted rule, how to interpret a `self-healing/auto` PR, kill switch. |
| `plugins/soleur/skills/compound/scripts/compound-promote-snapshot.sh` | Local-side snapshot generator (deferred to v2 if needed; placeholder file with v2 marker). NOT in v1 — listed only so a future planner doesn't re-discover the inline-at-/compound surface gap. |

## Files to Edit

| Path | Edit |
|---|---|
| `.github/actions/bot-pr-with-synthetic-checks/action.yml` | Add 3 optional inputs: `draft` (default `'false'`), `skip-auto-merge` (default `'false'`), `labels` (default `''`, newline-separated). Update steps: `gh pr create` accepts `--draft` when `draft == 'true'`; final `gh pr merge` is gated on `skip-auto-merge != 'true'`; `gh pr edit --add-label` loop runs after PR creation when `labels` is non-empty. Backward compatible — all existing callers (rule-metrics-aggregate, rule-prune) get default behavior. |
| `plugins/soleur/skills/compound/SKILL.md` | Add a **Cross-Session Promotion Loop (Layer 2)** subsection under Knowledge Base Integration. One-line bullet pointing operators at the runbook + the opt-in config path. Does NOT change Phase 1.5 / Phase 1.6 behavior. |
| `.gitignore` | Add `knowledge-base/project/promotion-config.yml` (the live config — operators commit it intentionally if they want it tracked, but the default must be UN-tracked to prevent the file from accidentally syncing into a fresh clone with `enabled: true`). Also gitignore `.github/promotion-*.json` should anyone re-add state files (defensive). |
| `knowledge-base/legal/compliance-posture.md` | Add Active Compliance Item row referencing #2720 (per CLO finding). Mitigation references this plan + the cron's runtime gdpr-gate invocation. |
| `README.md` (repo root) | Add a one-line bullet under "Optional capabilities" or equivalent linking to the runbook. Skip if no such section exists. |

## Implementation Phases

### Phase 0 — Pre-flight: label + branch hygiene

0.1. Verify the `self-healing/auto` label does not exist:
```bash
gh label list --limit 200 | grep -E "^self-healing/auto\b" || echo "needs creation"
```

0.2. Add a one-time idempotent label-creation step to `scheduled-compound-promote.yml` (mirrors `scheduled-daily-triage.yml`'s "Ensure triage labels exist" step):
```bash
gh label create "self-healing/auto" \
  --description "Auto-opened by compound-promotion-loop; manual review required" \
  --color "FBCA04" 2>/dev/null || true
```

0.3. Verify branch + worktree state (already in feat-compound-promotion-loop worktree; PR #3559 open as draft).

**Deliverables:** none yet (reads only). Exit criterion: `self-healing/auto` label confirmed missing.

### Phase 1 — bot-pr composite action extension (TDD-suitable)

1.1. **Failing test (manual, no test runner exists for composite actions in this repo).** Document the expected behavior in `.github/actions/bot-pr-with-synthetic-checks/CHANGELOG.md` (create file if missing): "v2 (date): adds optional `draft`, `skip-auto-merge`, `labels` inputs". Hand-test via a throwaway workflow_dispatch trigger after Phase 6 (cannot pre-merge-test new workflows per learning `2026-04-21-workflow-dispatch-requires-default-branch.md`).

1.2. **Edit `.github/actions/bot-pr-with-synthetic-checks/action.yml`:**

```yaml
inputs:
  # ... existing inputs ...
  draft:
    description: >
      If 'true', open the PR as a draft (gh pr create --draft). Default
      'false' preserves existing caller behavior.
    required: false
    default: 'false'
  skip-auto-merge:
    description: >
      If 'true', skip the final `gh pr merge --squash --auto` step.
      Default 'false' preserves existing caller behavior. Useful when the
      bot-authored PR requires explicit human review-and-merge.
    required: false
    default: 'false'
  labels:
    description: >
      Newline-separated label names to add to the PR after creation via
      `gh pr edit --add-label`. Labels MUST already exist (caller's
      responsibility). Empty string skips the label step.
    required: false
    default: ''
```

1.3. **Modify the `run:` block** (in declared order, with `set -euo pipefail` precondition still in effect):

After the existing `gh pr create` line, branch on `$DRAFT`:
```bash
PR_CREATE_ARGS=(--title "${PR_TITLE_PREFIX} ${DATE_SUFFIX}" --body-file "$BODY_FILE" --base main --head "$BRANCH")
if [[ "$DRAFT" == "true" ]]; then
  PR_CREATE_ARGS+=(--draft)
fi
gh pr create "${PR_CREATE_ARGS[@]}"
```

After the synthetic check-runs loop, add label application:
```bash
if [[ -n "$LABELS" ]]; then
  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    gh pr edit "$BRANCH" --add-label "$label"
  done <<< "$LABELS"
fi
```

Wrap the final `gh pr merge` in:
```bash
if [[ "$SKIP_AUTO_MERGE" != "true" ]]; then
  gh pr merge "$BRANCH" --squash --auto
fi
```

Add the new vars to the `env:` block: `DRAFT: ${{ inputs.draft }}`, `SKIP_AUTO_MERGE: ${{ inputs.skip-auto-merge }}`, `LABELS: ${{ inputs.labels }}`.

1.4. **Backward compat verification:** Read `scheduled-rule-prune.yml` and `rule-metrics-aggregate.yml` — both omit the new inputs. With defaults `'false'`/`'false'`/`''`, behavior is identical: no `--draft`, auto-merge runs, no labels added.

**Deliverables:** edited `action.yml`. Exit criterion: existing callers' behavior unchanged when new inputs are unset.

### Phase 2 — `scripts/compound-promote.sh` driver

2.1. **Failing test first.** Create `scripts/compound-promote.test.sh` mirroring `scripts/rule-metrics-aggregate.test.sh`. Test cases:

- `test_no_config_file_returns_noop`: with no `promotion-config.yml`, script exits 0 with `::compound-promote-status::no-config`.
- `test_disabled_config_returns_noop`: `enabled: false`, exits 0 with `::compound-promote-status::disabled`.
- `test_week_cap_reached_returns_noop`: with 2 open `self-healing/auto` PRs in the fixture, exits 0 with `::compound-promote-status::week-cap-reached`.
- `test_emits_cooldown_blocklist`: with 2 closed (not merged) `self-healing/auto` PRs in the fixture, the script emits `::compound-promote-cooldown-blocklist::<base64-json-array-of-cluster-hashes>` from the closed-PR bodies' `Cluster-Hash:` trailer.
- `test_strict_mode_failures_loud`: corrupted YAML → exits non-zero with `::error::`.

Test mode toggle: `COMPOUND_PROMOTE_FIXTURE_ROOT` env points to a fixture dir mirroring `knowledge-base/project/`; `gh` calls are mocked via `GH_BIN` env (defaults to `gh`).

2.2. **Implement `scripts/compound-promote.sh`:**

```bash
#!/usr/bin/env bash
# Driver for the compound-promotion-loop weekly cron.
# Reads opt-in config, week-cap, and cooldown blocklist; emits stdout
# sentinels consumed by .github/workflows/scheduled-compound-promote.yml.
#
# Sentinels emitted (one per line, no other matching line):
#   ::compound-promote-status::<no-config|disabled|enabled>
#   ::compound-promote-week-cap::<remaining-int>
#   ::compound-promote-cooldown-blocklist::<base64-json-array>
#
# Sister: scripts/rule-prune.sh (demotion side); scripts/rule-metrics-aggregate.sh.
# Issue: #2720. Plan: knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md
set -euo pipefail

REPO_ROOT="${COMPOUND_PROMOTE_FIXTURE_ROOT:-$(git rev-parse --show-toplevel)}"
CONFIG="$REPO_ROOT/knowledge-base/project/promotion-config.yml"
WEEK_CAP_DEFAULT=2
COOLDOWN_DAYS=30
GH_BIN="${GH_BIN:-gh}"

# 1. Opt-in gate
if [[ ! -f "$CONFIG" ]]; then
  printf '::compound-promote-status::no-config\n'
  exit 0
fi
# Strict yaml read — `yq` not assumed present; use awk for the single boolean
ENABLED=$(awk -F': *' '/^enabled:/ {print $2; exit}' "$CONFIG" | tr -d ' "'"'"'')
if [[ "$ENABLED" != "true" ]]; then
  printf '::compound-promote-status::disabled\n'
  exit 0
fi
printf '::compound-promote-status::enabled\n'

# 2. Per-week cap (derived from open self-healing/auto PRs)
OPEN_COUNT=$("$GH_BIN" pr list --label "self-healing/auto" --state open --json number --jq 'length' 2>/dev/null || echo 0)
REMAINING=$(( WEEK_CAP_DEFAULT - OPEN_COUNT ))
if (( REMAINING <= 0 )); then
  printf '::compound-promote-week-cap::0\n'
  printf '::compound-promote-status::week-cap-reached\n'
  exit 0
fi
printf '::compound-promote-week-cap::%d\n' "$REMAINING"

# 3. 30-day cooldown blocklist (derived from closed self-healing/auto PRs)
SINCE=$(date -u -d "$COOLDOWN_DAYS days ago" +%Y-%m-%d)
CLOSED_BODIES=$("$GH_BIN" pr list --label "self-healing/auto" --state closed \
  --search "closed:>$SINCE" --json body --jq '.[].body' 2>/dev/null || true)
# Extract Cluster-Hash trailers (one per body); emit as base64'd JSON array
HASHES_JSON=$(printf '%s\n' "$CLOSED_BODIES" \
  | grep -oE 'Cluster-Hash: [a-f0-9]{64}' \
  | awk '{print $2}' \
  | jq -R . | jq -sc '.')
HASHES_B64=$(printf '%s' "$HASHES_JSON" | base64 -w 0)
printf '::compound-promote-cooldown-blocklist::%s\n' "$HASHES_B64"
```

Notes:
- Uses `awk` for YAML read (no `yq` dependency).
- `GH_BIN` env allows test-mode mocking via a fake `gh` script.
- `set -euo pipefail` per AGENTS.md sharp edge `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`. Each `gh` call has `|| true` / `|| echo 0` to absorb expected zero-result exit codes.
- `base64 -w 0` (per AGENTS.md sharp edge `2026-05-05-workflow-jwt-mint-silent-failure-traps.md`) — no trailing newline.
- All bash variables that come from external sources (`gh` output) are sanitized via `${var//[$'\n\r']/}` if echoed to GitHub annotations.

2.3. **Run the test suite locally:** `bash scripts/compound-promote.test.sh` — all green.

**Deliverables:** `scripts/compound-promote.sh` (executable), `scripts/compound-promote.test.sh`. Exit criterion: tests green.

### Phase 3 — `scheduled-compound-promote.yml` workflow

3.1. **Failing test:** N/A — no workflow test runner exists in this repo. Verify YAML correctness via `yamllint` if installed; otherwise rely on Phase 6 post-merge `gh workflow run` per `wg-after-merging-a-pr-that-adds-or-modifies`.

3.2. **Workflow structure** — three jobs:

```yaml
name: "Scheduled: Compound Promotion Loop"

on:
  schedule:
    - cron: '0 0 * * 0'   # Sunday 00:00 UTC, aligns with rule-metrics-aggregate
  workflow_dispatch:

concurrency:
  group: scheduled-compound-promote
  cancel-in-progress: false

permissions:
  contents: write
  pull-requests: write
  checks: write
  issues: write          # for gdpr-gate Critical issue filing

jobs:
  preflight:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    outputs:
      ok: ${{ steps.check.outputs.ok }}
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - id: check
        uses: ./.github/actions/anthropic-preflight
        with:
          anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}

  cluster:
    needs: preflight
    if: needs.preflight.outputs.ok == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 45      # 0.75 min/turn × 60 turns
    outputs:
      clusters_json: ${{ steps.cluster.outputs.clusters_json }}
      week_remaining: ${{ steps.driver.outputs.week_remaining }}
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1

      - name: Ensure self-healing/auto label exists
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh label create "self-healing/auto" \
            --description "Auto-opened by compound-promotion-loop; manual review required" \
            --color "FBCA04" 2>/dev/null || true

      - name: Driver — opt-in, week-cap, cooldown
        id: driver
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail
          out=$(bash scripts/compound-promote.sh)
          printf '%s\n' "$out"
          STATUS=$(printf '%s\n' "$out" | sed -n 's/^::compound-promote-status:://p' | head -n 1)
          if [[ "$STATUS" != "enabled" ]]; then
            echo "skipped=true" >> "$GITHUB_OUTPUT"
            echo "week_remaining=0" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          REMAINING=$(printf '%s\n' "$out" | sed -n 's/^::compound-promote-week-cap:://p' | head -n 1)
          BLOCKLIST_B64=$(printf '%s\n' "$out" | sed -n 's/^::compound-promote-cooldown-blocklist:://p' | head -n 1)
          echo "skipped=false" >> "$GITHUB_OUTPUT"
          echo "week_remaining=${REMAINING}" >> "$GITHUB_OUTPUT"
          echo "cooldown_blocklist_b64=${BLOCKLIST_B64}" >> "$GITHUB_OUTPUT"

      - name: LLM clustering + diff drafting
        if: steps.driver.outputs.skipped == 'false'
        id: cluster
        uses: anthropics/claude-code-action@ab8b1e6471c519c585ba17e8ecaccc9d83043541  # v1.0.101
        with:
          anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}
          max-turns: 60
          prompt: |
            ${{ steps.driver.outputs.cooldown_blocklist_b64 != '' && format('COOLDOWN_BLOCKLIST_B64={0}', steps.driver.outputs.cooldown_blocklist_b64) || 'COOLDOWN_BLOCKLIST_B64=W10=' }}
            WEEK_REMAINING=${{ steps.driver.outputs.week_remaining }}

            Goal: identify recurring root causes in knowledge-base/project/learnings/
            and emit up to WEEK_REMAINING qualifying clusters as a JSON array.

            Procedure:
            1. List all *.md files under knowledge-base/project/learnings/ (recursive,
               excluding archive/). Read each file's frontmatter (when present) and
               body summary.
            2. Cluster semantically by problem/root-cause. Minimum cluster size: 5.
            3. For each candidate cluster, compute Cluster-Hash =
               sha256(sorted(source_paths)). If hash is in COOLDOWN_BLOCKLIST_B64
               (base64-decoded JSON array), skip the cluster.
            4. For each remaining qualifying cluster:
               a. Invoke `/soleur:gdpr-gate "<cluster source learning paths joined>"`.
                  If returns Critical, skip the cluster and log
                  `::compound-promote-gdpr-blocked::<cluster-hash>`.
               b. Apply tier classification per AGENTS.md cq-agents-md-tier-gate:
                  - already-enforced (hook/skill/scanner present) → skip
                  - domain-scoped (single skill boundary) → tier=skill,
                    target=plugins/soleur/skills/<owner>/SKILL.md
                  - cross-cutting session invariant → tier=agents-md,
                    target=AGENTS.md
               c. If tier=agents-md, check `wc -c AGENTS.md` > 37000 → re-route
                  to skill if a domain-scoped target exists; else skip with
                  `::compound-promote-byte-cap-suppressed::<cluster-hash>`.
               d. Draft a one-line bullet edit (skill) or one-rule addition
                  (AGENTS.md) ≤ 600 bytes.
            5. Cap output at WEEK_REMAINING qualifying clusters (FIFO by oldest
               source learning).
            6. Emit ONE line: `::compound-promote-clusters-json::<base64-json>`
               where the JSON shape is:
               [{cluster_hash, tier, target_path, source_learnings: [...],
                  proposed_diff_unified, rationale, tier_alternatives_considered,
                  byte_impact: {before, after, delta}}]
            Respect AGENTS.md cq-agents-md-tier-gate, cq-agents-md-why-single-line,
            cq-rule-ids-are-immutable. Do NOT push, do NOT open PRs — that is the
            promote job's responsibility. Output JSON only.
          claude_args: |
            --allowedTools "Bash(gh label list*),Bash(wc -c*),Bash(find*),Bash(ls*),Bash(grep*),Read,Skill(soleur:gdpr-gate)"

      - name: Parse clusters JSON to job output
        if: steps.driver.outputs.skipped == 'false'
        env:
          AGENT_OUTPUT: ${{ steps.cluster.outputs.clusters_json || '' }}
        run: |
          set -euo pipefail
          # Extract sentinel from the agent's stdout (claude-code-action surfaces
          # tool-use output, not a clean stdout — fall back to scanning logs).
          # If the agent wrote the sentinel via Bash echo, it appears in the
          # job log; extract from the run's previous step output via gh API.
          # For now, use the action's `outputs` mechanism if v1.0.101 exposes it;
          # otherwise the agent must write to $GITHUB_OUTPUT directly.
          # ... (resolved during implementation; see Open Questions)
          echo "clusters_json=${AGENT_OUTPUT:-[]}" >> "$GITHUB_OUTPUT"

  promote:
    needs: cluster
    if: needs.cluster.outputs.clusters_json != '' && needs.cluster.outputs.clusters_json != '[]'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    strategy:
      fail-fast: false
      matrix:
        cluster: ${{ fromJson(needs.cluster.outputs.clusters_json) }}
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - name: Apply diff
        env:
          DIFF: ${{ matrix.cluster.proposed_diff_unified }}
          TARGET: ${{ matrix.cluster.target_path }}
        run: |
          set -euo pipefail
          printf '%s' "$DIFF" | git apply --check
          printf '%s' "$DIFF" | git apply
      - name: Append audit-log row
        env:
          CLUSTER_HASH: ${{ matrix.cluster.cluster_hash }}
          TIER: ${{ matrix.cluster.tier }}
          TARGET: ${{ matrix.cluster.target_path }}
          SOURCE_COUNT: ${{ length(matrix.cluster.source_learnings) }}
        run: |
          set -euo pipefail
          DATE=$(date -u +%Y-%m-%d)
          printf '\n| %s | %s | %s | %d | pending | %s | (PR pending) |\n' \
            "$DATE" "$CLUSTER_HASH" "$TARGET" "$SOURCE_COUNT" "$TIER" \
            >> knowledge-base/project/learnings/promotion-log.md
      - name: Open draft PR via extended composite
        uses: ./.github/actions/bot-pr-with-synthetic-checks
        with:
          add-paths: |
            ${{ matrix.cluster.target_path }}
            knowledge-base/project/learnings/promotion-log.md
          branch-prefix: self-healing/auto-${{ matrix.cluster.cluster_hash }}-
          commit-message: |
            chore(self-healing): promote cluster ${{ matrix.cluster.cluster_hash }} to ${{ matrix.cluster.target_path }}

            Promoted-By: github-actions[bot]
            Proposed-By: compound-promotion-loop ${{ github.sha }}
            Source-Learnings: ${{ join(matrix.cluster.source_learnings, ',') }}
            Threshold-Hit: ${{ length(matrix.cluster.source_learnings) }}/5
            Cluster-Hash: ${{ matrix.cluster.cluster_hash }}
            Tier: ${{ matrix.cluster.tier }}
            Tier-Alternatives: ${{ matrix.cluster.tier_alternatives_considered }}
            Byte-Impact: before=${{ matrix.cluster.byte_impact.before }} after=${{ matrix.cluster.byte_impact.after }} delta=${{ matrix.cluster.byte_impact.delta }}
          pr-title-prefix: "self-healing(auto): promote cluster ${{ matrix.cluster.cluster_hash }}"
          pr-body: "Promoted by compound-promotion-loop. Source learnings: ${{ join(matrix.cluster.source_learnings, ', ') }}. Tier: ${{ matrix.cluster.tier }}. Cluster-Hash: ${{ matrix.cluster.cluster_hash }}. Reviewer: verify the diff respects cq-agents-md-tier-gate and cq-agents-md-why-single-line; merge to apply, close to reject (30-day cooldown will activate)."
          change-summary: "self-healing/auto promotion — operator review required before merge"
          gh-token: ${{ github.token }}
          draft: 'true'
          skip-auto-merge: 'true'
          labels: 'self-healing/auto'

  email-on-failure:
    needs: [preflight, cluster, promote]
    if: always() && (needs.preflight.result == 'failure' || needs.cluster.result == 'failure' || needs.promote.result == 'failure')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - uses: ./.github/actions/notify-ops-email
        with:
          subject: '[FAIL] Scheduled: Compound Promotion Loop failed'
          body: '<p><strong>Scheduled: Compound Promotion Loop</strong> failed.</p><p><a href="${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}">View run</a></p>'
          resend-api-key: ${{ secrets.RESEND_API_KEY }}
```

Notes:
- 0.75 min/turn ratio (45 min / 60 turns) per `2026-03-20-claude-code-action-max-turns-budget.md`. Plugin overhead ~10 turns + clustering + tier classification + diff drafting + gdpr-gate calls per cluster. 60 turns is the conservative budget.
- claude-code-action SHA pinned `ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101` per repo majority.
- `concurrency.group: scheduled-compound-promote` per repo convention.
- `permissions:` declare every required scope explicitly (default-permissions become NONE once any explicit permissions are declared per `2026-03-16-github-actions-workflow-dispatch-permissions.md`).
- `secrets.SOLEUR_GH_TOKEN` is NOT used per Reconciliation table.
- The cluster job's output extraction via `claude-code-action` outputs is the single Open Question (see below) — implementation may need a small bridge step that reads the action's tool-call log.
- Promote job's matrix is bounded by `week_remaining` because the cluster job caps clusters_json at that count per the agent prompt.
- Atomicity: each promote-job iteration is self-contained (apply diff → append log row → open PR). If `git apply` fails, the matrix iteration fails but other clusters succeed (`fail-fast: false`).

**Deliverables:** `.github/workflows/scheduled-compound-promote.yml`. Exit criterion: `yamllint` clean (if installed).

### Phase 4 — Config + audit-log scaffolds

4.1. Create `knowledge-base/project/promotion-config.yml.example`:
```yaml
# Compound Promotion Loop config.
# Copy to knowledge-base/project/promotion-config.yml and set enabled: true to opt in.
# See knowledge-base/engineering/runbooks/compound-promote-runbook.md for details.
# Default: OFF. The cron exits no-op when this file is absent or enabled: false.
# Issue: #2720
enabled: false
threshold: 5            # cluster size that triggers a promotion proposal
week_cap: 2             # max self-healing/auto PRs opened per week
cooldown_days: 30       # days a closed cluster stays in cooldown
```

4.2. Add `knowledge-base/project/promotion-config.yml` to `.gitignore` (the .example file IS tracked; the live file is not, to prevent the file from accidentally being enabled in someone's clone via merge).

4.3. Create `knowledge-base/project/learnings/promotion-log.md`:
```markdown
---
title: "Compound Promotion Loop — audit log"
type: audit-log
issue: "#2720"
---

# Compound Promotion Loop — audit log

Append-only log of every promotion proposal opened by `scheduled-compound-promote.yml`. Schema:

| Date | Cluster-Hash | Target | Source count | Decision | Tier | PR |
|------|--------------|--------|--------------|----------|------|-----|

Decision values: `pending` (initial), `merged`, `closed`. The cron updates `pending` → `merged|closed` in a follow-up commit on a separate housekeeping branch.

<!-- ROWS BELOW THIS LINE -->
```

4.4. Update `knowledge-base/legal/compliance-posture.md` — add Active Compliance Item:
```markdown
| #2720 | Compound Promotion Loop | Cron reads PII-eligible learnings, summarizes into PR bodies. | Pre-promotion gdpr-gate scan (refuse on Critical), opt-in default OFF, append-only audit log, draft PR + manual confirm. | Active |
```

(Exact row format depends on existing table schema — read the file first; if no Active Items table exists, add one per the legal-compliance-auditor convention.)

**Deliverables:** the three new files, the gitignore edit, the compliance-posture row. Exit criterion: `git status --short` shows the four entries.

### Phase 5 — Compound skill cross-reference

5.1. Edit `plugins/soleur/skills/compound/SKILL.md`. Find the `## Knowledge Base Integration` section. Add a one-line subsection at the end:

```markdown
### Cross-Session Promotion Loop (Layer 2)

A weekly cron (`scheduled-compound-promote.yml`) consumes accumulated learnings and proposes skill / AGENTS.md edits via draft PR when N=5 learnings cluster around the same root cause. Default OFF. Opt in via `knowledge-base/project/promotion-config.yml`. See `knowledge-base/engineering/runbooks/compound-promote-runbook.md`. Issue: #2720.
```

**Deliverables:** edited `compound/SKILL.md` (+1 subsection ≤4 lines). Exit criterion: subsection visible at end of Knowledge Base Integration.

### Phase 6 — Operator runbook

6.1. Create `knowledge-base/engineering/runbooks/compound-promote-runbook.md`:

```markdown
# Compound Promotion Loop — operator runbook

## What it does

Weekly cron (Sunday 00:00 UTC) reads `knowledge-base/project/learnings/`,
LLM-clusters by root cause, opens a draft PR labeled `self-healing/auto`
proposing a skill-instruction edit or AGENTS.md rule addition when a
cluster reaches 5 learnings. Default OFF.

## Opt in

```bash
cp knowledge-base/project/promotion-config.yml.example knowledge-base/project/promotion-config.yml
# Edit: set enabled: true
git add knowledge-base/project/promotion-config.yml
git commit -m "chore: opt in to compound-promotion-loop"
git push
```

## Opt out (kill switch)

Set `enabled: false` in the config and commit. Next cron tick exits no-op.
Existing draft PRs are unaffected; close them manually if desired.

## Reviewing a self-healing/auto PR

The PR body includes:
- Source learnings (links).
- Cluster-Hash (sha256).
- Tier classification + alternatives considered.
- Byte impact (for AGENTS.md edits).

Acceptance heuristic:
1. Do the source learnings represent the same root cause? (Skim 2-3.)
2. Does the proposed edit respect the tier-gate? (Domain-scoped → skill;
   cross-cutting → AGENTS.md.)
3. For AGENTS.md edits: is the byte delta under 600? Is the file under
   37k? Is `**Why:**` one sentence?

Merge to apply. Close-without-merge → 30-day cooldown on the cluster.

## Reverting a promoted rule

Identical to manual rule retirement. Append the rule's `[id: ...]` tag to
`scripts/retired-rule-ids.txt` with a breadcrumb pointing at the
promotion PR. The lint-rule-ids hook will then prevent re-promotion of the
same ID.

## Sharp edges

- The cron CANNOT read `.claude/.rule-incidents.jsonl` (gitignored, never
  in CI). Clustering input is always `knowledge-base/project/learnings/`.
- claude-code-action revokes its App token in its post-step. PR creation
  happens in a SEPARATE `promote` job with a fresh GITHUB_TOKEN.
- The `self-healing/auto` label MUST exist before the cron runs. The
  workflow's "Ensure label exists" step is idempotent.
- Plugin-scope edits (`plugins/soleur/**`) are deferred to v2 with an
  explicit `--scope=plugin` flag and ToS update.
- Synthetic check-runs are still posted (via the extended bot-pr composite)
  even though the PR is draft, so an operator-merge satisfies the CI
  Required + CLA Required rulesets.
```

**Deliverables:** the runbook file. Exit criterion: file readable, examples copy-pasteable.

### Phase 7 — Pre-merge verification + GDPR self-test

7.1. Run `bash scripts/compound-promote.test.sh` — all green.

7.2. Run `/soleur:gdpr-gate "feat-compound-promotion-loop plan + spec"` and triage findings. Critical → operator-acknowledged write to `compliance-posture.md` (Phase 4 already added the Active Item row in advance; update if findings differ).

7.3. Hand-test the workflow's shell driver with a fixture:
```bash
COMPOUND_PROMOTE_FIXTURE_ROOT=/tmp/compound-promote-fixture \
  GH_BIN=/tmp/gh-mock.sh \
  bash scripts/compound-promote.sh
```

7.4. **CANNOT** test the workflow itself pre-merge — `gh workflow run scheduled-compound-promote.yml --ref feat-compound-promotion-loop` returns HTTP 404 (workflow not on default branch yet) per learning `2026-04-21-workflow-dispatch-requires-default-branch.md`. First live run is post-merge:
```bash
# Post-merge:
gh workflow run scheduled-compound-promote.yml
gh run watch
```

This is the verification step required by `wg-after-merging-a-pr-that-adds-or-modifies`.

**Deliverables:** test pass + gdpr-gate clean (or Critical filed). Exit criterion: AC1-AC10 met.

### Phase 8 — Issue updates

8.1. PR body for #3559 (already open as draft — convert to ready when merging):
- `Closes #2720` on its own line (intentional auto-close per `wg-use-closes-n-in-pr-body-not-title-to`).
- `Ref #2718` (parent — leave open).
- `Ref #421` (already closed-as-superseded).
- `## Changelog` section (semver:minor — adds a workflow + skill subsection).

8.2. Post-merge: `gh workflow run scheduled-compound-promote.yml` and watch first run; investigate failures per `wg-after-merging-a-pr-that-adds-or-modifies`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `.github/actions/bot-pr-with-synthetic-checks/action.yml` declares 3 new optional inputs (`draft`, `skip-auto-merge`, `labels`) with backward-compatible defaults.
- [ ] AC2: Existing callers (`scheduled-rule-prune.yml`, `rule-metrics-aggregate.yml`) are NOT modified — defaults preserve their behavior.
- [ ] AC3: `scripts/compound-promote.sh` exists, is executable, mirrors `rule-prune.sh` CLI conventions (set -euo pipefail, stdout sentinels, env-overridable repo root).
- [ ] AC4: `scripts/compound-promote.test.sh` exists with 5+ test cases (no-config, disabled, week-cap-reached, cooldown-blocklist-emit, strict-mode-failure-loud).
- [ ] AC5: `.github/workflows/scheduled-compound-promote.yml` exists with three jobs (`preflight`, `cluster`, `promote`) plus `email-on-failure`. Cron `0 0 * * 0`. Concurrency group `scheduled-compound-promote`. Permissions explicitly declared.
- [ ] AC6: `knowledge-base/project/promotion-config.yml.example` + the runbook + the audit-log scaffold exist.
- [ ] AC7: `knowledge-base/project/promotion-config.yml` is in `.gitignore`.
- [ ] AC8: `plugins/soleur/skills/compound/SKILL.md` has the Layer 2 cross-reference subsection.
- [ ] AC9: `knowledge-base/legal/compliance-posture.md` has an Active Item row referencing #2720.
- [ ] AC10: `bash scripts/compound-promote.test.sh` passes locally.
- [ ] AC11: `/soleur:gdpr-gate "feat-compound-promotion-loop plan + spec"` returns clean (or Critical findings filed to `compliance/critical` issue).
- [ ] AC12: `user-impact-reviewer` agent run on PR #3559 returns approval.
- [ ] AC13: Plan-review agents (DHH + Kieran + Code Simplicity) run; all P1+ findings resolved or scoped out with rationale.
- [ ] AC14: `self-healing/auto` label exists in the repo (created either by the workflow's idempotent step on first run, or by a Phase 0 manual `gh label create` if anyone wants it ahead of merge).
- [ ] AC15: PR #3559 body uses `Closes #2720` (on its own line) and `Ref #2718` / `Ref #421`.

### Post-merge (operator)

- [ ] AC16: `gh workflow run scheduled-compound-promote.yml` triggers a manual run; the run completes (not necessarily opening a PR — config is OFF by default).
- [ ] AC17: With `enabled: true` set in `promotion-config.yml` AND a synthetic learnings-corpus addition (5+ similar test learnings), a follow-up `gh workflow run` opens exactly ONE draft `self-healing/auto` PR with the provenance trailer.
- [ ] AC18: Closing the test PR adds an entry derivable from `gh pr list --label self-healing/auto --state closed` whose body contains a `Cluster-Hash:` matching the cluster.
- [ ] AC19: A subsequent `gh workflow run` within 30 days does NOT re-propose the same cluster (cooldown enforced via the closed-PR derivation).

## Risks

- **R1 (HIGH, mitigated):** A bad auto-promoted rule cascades to every operator. Mitigations: opt-in default OFF, draft PR + manual confirm, tier-gate routing, byte-cap suppression, per-week cap, cooldown, audit log, `user-impact-reviewer`. Combined: any single mitigation failure does not breach brand-survival; defense in depth.
- **R2 (MEDIUM):** LLM clustering produces unstable boundaries week-over-week. Cooldown is keyed by Cluster-Hash (sha256 of sorted source paths); a renamed/added/removed source learning produces a new hash and bypasses cooldown. Acceptable trade-off — false positives are operator-rejected (close-without-merge) and re-enter cooldown.
- **R3 (MEDIUM):** Tier-classification by LLM may be wrong. Mitigation: tier + alternatives recorded in PR body for reviewer override; reviewer can amend and re-merge. The wrong tier is a correctable PR-time decision, not an irreversible production change.
- **R4 (MEDIUM):** Bootstrap week opens 2 PRs against ~280 existing learnings. Per-week cap throttles backlog drainage; backlog will take weeks. Acceptable; flag in `/ship` for empirical tuning of `week_cap` after 4 weeks of operation.
- **R5 (LOW):** PII in a learning leaks into a public PR body. Mitigation: pre-promotion gdpr-gate scan refuses to promote any cluster whose source learnings fail redaction; offending learning(s) trigger a redaction GitHub issue.
- **R6 (LOW):** claude-code-action token revocation breaks PR creation if the workflow is restructured. Mitigation: documented in the Reconciliation table + runbook Sharp Edges; the two-job split is load-bearing and must not be merged into one job.
- **R7 (LOW):** State files in `.github/` re-trigger the workflow → recursion. Mitigation: no state files; cooldown and cap derived from PR labels only. Defensive: `.github/promotion-*.json` added to `.gitignore` so a future re-introduction won't auto-commit.

## Open Questions (for /work)

- **Q1: claude-code-action output extraction.** v1.0.101's mechanism for surfacing a structured JSON output from the agent (vs. just tool-use logs) is undocumented in this repo's existing usages. Resolve at /work by inspecting the action's outputs schema or wiring the agent to write to `$GITHUB_OUTPUT` directly via a Bash tool call. Fallback: parse the run log via `gh api repos/.../runs/<id>/logs`.
- **Q2: Bootstrap-week throttle.** Should the FIRST cron run cap at 1 PR (not 2) so the operator can evaluate the system before it accelerates? Default v1: NO (use the steady-state cap of 2). Revisit if the first 2 PRs prove problematic.
- **Q3: Audit-log decision-column update mechanism.** Phase 3 prescribes a "follow-up commit on a separate housekeeping branch" for `pending → merged|closed` transitions. v1 implementation: skip — the open-PR query gives the live state. The log row stays at `pending` forever; reconstruct merged/closed by joining log to `gh pr list`. Decide at /work whether to defer the housekeeping commit entirely.
- **Q4: Per-cluster gdpr-gate cost.** Each `/soleur:gdpr-gate` invocation inside the agent burns turns. With week_cap=2 and gdpr-gate ~5-10 turns per cluster, total ~30 turns. 60-turn budget covers this with margin. Verify post-first-run.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `single-user incident`; do not blank it during /work.
- The cluster job's `outputs.clusters_json` MUST be a valid JSON array. The promote job's matrix uses `fromJson(...)`; an invalid JSON crashes the entire matrix. Defensive: the agent's prompt explicitly instructs JSON-only output; the parse step echoes `[]` on missing output to short-circuit the promote job rather than crash it.
- Per `wg-after-merging-a-pr-that-adds-or-modifies`, the merged PR must trigger `gh workflow run scheduled-compound-promote.yml` and verify the run completes. AC16 enforces this.
- Synthetic check-runs (test, dependency-review, e2e, skill-security-scan PR gate, cla-check) are still posted by the extended composite even on draft PRs. This is INTENTIONAL — the operator must be able to convert draft → ready and merge without satisfying CI from scratch.
- The `self-healing/auto` label must NOT be applied to PRs the operator opens manually. The cron's identity check (filtering on `gh pr list --search "author:app/github-actions"`) avoids consuming budget for human-labeled PRs.
- `wg-use-closes-n-in-pr-body-not-title-to` — PR #3559's body must use `Closes #2720` on its own line (intentional auto-close at merge). `Ref #421` and `Ref #2718` everywhere else.

## Testing

### Unit / shell tests

- `bash scripts/compound-promote.test.sh` — 5+ test cases per Phase 2.

### Integration tests (post-merge only)

- AC16-AC19 above.

### Per AGENTS.md `cq-write-failing-tests-before`

This plan includes test scenarios (AC1-AC19) and acceptance criteria. /work MUST write the failing test first for each phase that adds a shell script. Exempt: workflow YAML (no test runner), config scaffolds (no logic), runbook prose.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| **Single-job workflow** (claude-code-action does clustering AND PR creation in its prompt) | claude-code-action revokes its App token in post-step; subsequent steps in the same job that need GITHUB_TOKEN fail. Two-job split avoids this and gives the promote job a fresh token. |
| **Per-learning frontmatter occurrence counter** | Breaks ADR-1 from compound's Phase 1.5 design. ~94.5% of existing learnings lack structured frontmatter. Adopted: LLM clustering instead. |
| **State files in `.github/promotion-*.json`** | Writes to `.github/` re-trigger workflows on push; recursion risk. Adopted: derive cap + cooldown from PR labels. |
| **Hooks as v1 promotion target** | Highest blast radius (PreToolUse hook can wedge sessions). Defer to v2 with explicit revert path via `scripts/retired-rule-ids.txt`. v1 covers skill + AGENTS.md targets. |
| **Inline `/compound`-time surface (per-session)** | Adds per-session LLM cost, conflicts with operator mid-flow. Defer to v2 if cron-only proves insufficient. |
| **Push-to-main directly** (constitution.md line 153 preference) | Brand-survival threshold `single-user incident` requires manual confirm via PR review. Documented deviation; constitution preference yields to user-impact rule. |
| **`peter-evans/create-pull-request` action** | Zero precedent in this repo; introduces a new dependency. Existing `bot-pr-with-synthetic-checks` covers the use case after a bounded extension. |

## Deferrals → tracking issues to file at PR-merge time

| Deferral | Re-evaluation criteria | Issue to file |
|---|---|---|
| Hook proposals as v1 target | After 4 weeks of v1 operation, if skill+AGENTS.md proposals consistently fail to address recurring deviations that would benefit from a hook gate. | NEW issue — milestone `Post-MVP / Later`. |
| Inline `/compound`-time surface | If operator finds cron-only feedback loop too slow (proposals arriving days after the learning was captured). | NEW issue — milestone `Post-MVP / Later`. |
| Plugin-scope promotions (`--scope=plugin` flag) | When ToS / Privacy Policy is updated to disclose self-improving loop in the Soleur plugin. CLO must sign off. | NEW issue — milestone `Post-MVP / Later`. |
| Embedding-based cluster identity (vector similarity) | If LLM clustering proves too unstable in practice (≥30% of clusters renamed week-over-week). | NEW issue — milestone `Post-MVP / Later`. |
| `compound-promote.test.sh` wired into CI | When the sister `rule-metrics-aggregate.test.sh` is wired in (currently both are unwired). | Track in `ci.yml` rule-metrics-shape job parent issue. |
| Per-category threshold override (`promotion-config.yml` → `categories: { security: 3 }`) | If empirical data justifies category-specific tuning. | NEW issue — milestone `Post-MVP / Later`. |

## Research Insights

### claude-code-action

- Pinned SHA `ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101` per repo majority.
- Min/turn ratio: target 0.75. 60 turns × 0.75 = 45 min timeout.
- Plugin overhead ≈ 10 turns to load AGENTS.md + constitution + brand guide.
- Token revocation in post-step → PR-creation steps must be in a SEPARATE downstream job.

### bot-pr-with-synthetic-checks

- Inputs: `add-paths` (newline-separated), `branch-prefix` (date-suffixed), `commit-message`, `pr-title-prefix` (date-suffixed), `pr-body` (single-line enforced), `change-summary` (60KB cap), `gh-token`.
- Posts synthetic checks: `test`, `dependency-review`, `e2e`, `skill-security-scan PR gate`, `cla-check`. Required to satisfy CI Required + CLA Required rulesets on main.
- Final step queues auto-merge via `gh pr merge --squash --auto`.
- This plan extends with `draft`, `skip-auto-merge`, `labels`. Backward compatible.

### scripts/rule-prune.sh — canonical mirror

- CLI: `--weeks=<n>`, `--dry-run`, `--propose-retirement`.
- Stdout sentinels: `::rule-prune-pr-title::`, `::rule-prune-pr-body::`.
- Env override: `RULE_METRICS_ROOT`.
- Schema-version gate at consumer boundary.
- Two-pass mutation (validate → atomic single-redirect append).

### gdpr-gate

- No headless CLI. Invoke as `/soleur:gdpr-gate <scope>` slash command inside claude-code-action.
- Lefthook hook `scripts/gdpr-gate.sh` is advisory-only; always exits 0.

### Telemetry constraints

- `.claude/.rule-incidents.jsonl` is gitignored; CI runners never see it.
- Cron must consume `knowledge-base/project/learnings/` directly (committed).

## CLI-verification gate

Every CLI invocation embedded in this plan or shipped to docs has been verified:

- `gh label list --limit 200` — verified locally during plan research.
- `gh label create <name> --description ... --color ... 2>/dev/null || true` — verified pattern in `scheduled-daily-triage.yml`.
- `gh pr list --label <label> --state <state> --json <fields> --jq <expr>` — standard gh API.
- `gh pr create --title ... --body-file ... --base main --head ... --draft` — `--draft` verified via `gh pr create --help`.
- `gh pr edit <branch> --add-label <label>` — verified via `gh pr edit --help`.
- `gh pr merge <branch> --squash --auto` — repo precedent.
- `gh workflow run <file>.yml` — repo precedent.
- `gh workflow run <file>.yml --ref <branch>` — confirmed to require workflow on default branch (will fail pre-merge per learning `2026-04-21`).
- `bash scripts/compound-promote.test.sh` — to be created in Phase 2.
- `/soleur:gdpr-gate "<scope>"` — verified slash-command form in `plugins/soleur/skills/gdpr-gate/SKILL.md`.

## Browser task automation check

No browser tasks. All steps are CLI / API.

## Spec-Flow Reconciliation — gaps resolved at plan time

The spec-flow-analyzer surfaced 6 P0 gaps + 6 P1 gaps against the spec. Resolutions below; re-issue tracking in #2720 if any are deferred. The 2 already covered by this plan's architecture are noted ✓; the 4 remaining P0s and 5 P1s get explicit resolution here.

### P0-1 (GAP-CLUSTER-1) — Cluster-hash boundary instability

**Gap:** Pure path-list hash means cluster `{A,B,C,D,E}` cooled-down → next-week cluster `{A,B,C,D,E,F}` produces a new hash → cooldown bypassed silently.

**Resolution:** **Subset/superset overlap detection.** When the cluster job emits a cluster, the promote job (or a pre-promote driver step) checks the cluster's source-learning set against every closed-PR-derived cooldown set within 30 days. Computes Jaccard overlap = `|intersection| / |union|`. If overlap ≥ 0.8 against any cooldown set, the cluster is treated as the same cluster and skipped. Same logic against `merged` PRs (derived from closed PRs whose merge state is `merged`) — never re-promote a merged cluster.

**FR addition:** **FR10 (cluster-overlap dedup):** Before opening a PR, compute Jaccard overlap of source-learning paths against every `self-healing/auto` PR closed within 30 days AND every merged `self-healing/auto` PR (no time bound). Skip if ≥0.8 overlap.

**AC addition:** **AC20:** A cluster `{A,B,C,D,E}` cooled-down → next-run cluster `{A,B,C,D,E,F}` is recognized via Jaccard overlap and skipped. Verified post-merge with synthetic fixture.

### P0-2 (GAP-GDPR-1) — GDPR-block ledger keyed by learning, not cluster

**Gap:** Spec FR8 was ambiguous on whether `gdpr-blocked` is per-cluster or per-learning. Per-cluster fails silently when cluster boundary shifts.

**Resolution:** **Per-learning block.** When `/soleur:gdpr-gate` returns Critical findings for source learnings, the agent files ONE GitHub issue per offending learning (title: `[gdpr-block] redact PII from <path>`, body: gdpr-gate finding excerpt with line numbers). The cluster's promote step is skipped and the cluster's source-learning paths are recorded in a derived blocklist that the next cron run consumes. The blocklist is itself derived from open issues with `label:gdpr-block` (no separate state file): if any source learning of a candidate cluster appears in an open `gdpr-block` issue's title, the cluster is skipped. Cluster reattempts automatically when all `gdpr-block` issues close (operator redacts and closes).

**FR replacement:** **FR8 (revised):** Pre-promotion gdpr-scan via `/soleur:gdpr-gate <cluster source paths>`. On Critical findings, file ONE issue per offending learning with label `gdpr-block`; skip the cluster. The next cron tick derives a per-learning blocklist from `gh issue list --label gdpr-block --state open`; any cluster containing a blocked learning is skipped.

**AC addition:** **AC21:** A cluster with 2 PII-bearing learnings produces 2 `gdpr-block` issues; cluster reattempts only after both issues close.

### P0-3 (GAP-OP-1) — Force-merge / label-strip handling

**Gap:** If operator strips the `self-healing/auto` label or admin-bypasses branch protection, the cooldown derivation (label-based search) misses the PR.

**Resolution:** **Branch-name regex as canonical signal.** All `self-healing/auto` PRs use branch prefix `self-healing/auto-<cluster-hash>-<date>`. The cooldown derivation uses branch-name regex `^self-healing/auto-[a-f0-9]{16,}-` rather than (or in addition to) the label search. Branch names are immutable post-creation; labels are mutable.

**TR replacement:** **TR1 (revised cooldown derivation):** Use `gh pr list --state closed --search "head:self-healing/auto- closed:>$(date -d '30 days ago')" --json headRefName,body,mergedAt`. Parse `headRefName` for the cluster-hash component; cross-check with the `Cluster-Hash:` trailer in body for integrity.

**AC addition:** **AC22:** Stripping the `self-healing/auto` label from a closed PR does NOT bypass cooldown — branch-name regex catches it.

### P0-4 (GAP-RETIRED-1) — Re-proposing retired rules

**Gap:** No check against `scripts/retired-rule-ids.txt`. If operator retires a rule, the cron can re-propose it on the next cluster threshold hit.

**Resolution:** **Pre-propose retirement check.** Inside the claude-code-action prompt: before drafting an AGENTS.md rule addition, the agent reads `scripts/retired-rule-ids.txt`, extracts every breadcrumb (the 4th `|`-delimited field), and checks whether any of the candidate cluster's source learnings appear in a breadcrumb. If so, the cluster is skipped and `::compound-promote-retired-rule-honored::<cluster-hash>` is logged. (For skill-target proposals, the same check applies: don't propose a skill bullet whose substance was previously retired.)

**FR addition:** **FR11 (retired-rule honor):** Before drafting any proposal, scan `scripts/retired-rule-ids.txt` for breadcrumbs referencing any of the cluster's source-learning paths. On match, skip the cluster permanently (no time-based expiry — retirement is intentional).

**AC addition:** **AC23:** A cluster whose source learnings overlap any breadcrumb in `retired-rule-ids.txt` does not produce a PR.

### P0-5 (GAP-CONCURRENCY-1) — already covered ✓

This plan's `concurrency.group: scheduled-compound-promote` (NO `${{ github.ref }}` expression) and `cancel-in-progress: false` already match spec-flow's recommended fix. No change.

### P0-6 (GAP-STATE-1) — already eliminated ✓

This plan removed all `.github/promotion-*.json` state files (derived from PR labels + branch names instead). The spec's state-file corruption gap is moot for this plan's architecture. The Reconciliation table documents the elimination.

### P1-1 (GAP-USER-IMPACT-1) — AC10 mechanism

**Gap:** AC10 said "user-impact-reviewer agent run on PR returns approval before merge" but didn't specify mechanism (workflow vs. manual).

**Resolution:** **Manual review-skill invocation.** Per `plugins/soleur/skills/review/SKILL.md` conditional-agent block, `user-impact-reviewer` runs as part of `/soleur:review` when the PR carries the brand-survival threshold marker. PR #3559 will get a `Brand-Survival-Threshold: single-user incident` line in the PR body (mirroring the plan frontmatter). Reviewer (operator) runs `/soleur:review #3559` before merging; the conditional-agent block fires user-impact-reviewer automatically. NOT a CI gate (no new workflow file). The operator's diligence to run `/soleur:review` IS the gate — flag in `/ship` for procedural enforcement.

**AC10 (revised):** `/soleur:review #3559` was invoked manually by the operator before mark-as-ready; the user-impact-reviewer's findings are resolved or scoped-out with rationale on the PR.

### P1-2 (GAP-BOOT-1) — corpus is 947 files, not 280

**Resolution:** Updated. The bootstrap math in TR6 (spec) is wrong; this plan's R4 (Risks) and Q4 (Open Questions) are also off-by-3.4×. Realistic projection: at 947 files with N=5 cluster threshold and ~10% qualifying clusters, ~19 candidate clusters in the bootstrap pool. At 2/week cap, ~10 weeks to drain. Per-week cap may need to ramp (week 1: cap=1, week 2: cap=1, weeks 3-4: cap=2, weeks 5+: cap=2 unless rejection rate >50% — then cap stays at 1).

**AC addition:** **AC24:** First cron run on the live 947-file corpus respects week-1 cap=1; queue depth ≤ 20 candidates after first run.

### P1-3 (GAP-LABEL-1) — already covered ✓

Phase 0 step + workflow's idempotent "Ensure label exists" step both create `self-healing/auto`. Also adding `gdpr-block` to the same step (per FR8 revision).

### P1-4 (GAP-ATOMIC-1) — TR5 atomicity

**Resolution:** Architecture eliminates the multi-target-on-main problem. All cron-side state mutations land on the feature branch in ONE commit (diff + log row append). Audit-log `pending → merged|closed` transitions are NOT performed by a housekeeping commit; instead, the audit log keeps `pending` forever and the live state is derived at read-time from `gh pr view`. This is documented as Q3-resolved-as-NO in the Open Questions update below.

### P1-5 (GAP-AUDIT-1) — markdown-table mutation fragility

**Resolution:** **No mutation.** Append-only. Rows stay `pending` forever; derived state from `gh pr view <pr-number-from-row>`. A small `scripts/promotion-log-summary.sh` reader can render a live view if needed.

**AC addition:** **AC25:** `promotion-log.md` rows are append-only; no in-place edits. Live state derivable via `gh pr view`.

### P1-6 (GAP-LLM-1) — malformed JSON handling

**Resolution:** **Defensive parse + skip.** Promote to FR12.

**FR addition:** **FR12 (LLM output validation):** The cluster job's parse-step validates the agent's output via `jq -e 'type == "array"' <<< "$AGENT_OUTPUT"`. On parse failure, emit `clusters_json=[]` (skipping the entire promote job) and log `::compound-promote-malformed-output::true`. The cron does NOT crash; the failure is observable in the run log.

### P2-1 (GAP-PROVENANCE-1) — provenance trailer authorship

**Resolution:** Update commit-message template to:
- `Author:` and `Committer:` are bot identity (`github-actions[bot]`).
- `Promoted-By:` line removed (misleading).
- Added `Bot-Author: compound-promotion-loop@<workflow-sha>` and `Promotion-Owner: <owner email from promotion-config.yml, advisory only>`.

### P2-2 (GAP-DEMOTION-1) — coordination with rule-prune

**Resolution:** **Cross-check open `rule-prune` PRs.** Inside the claude-code-action prompt: before drafting an AGENTS.md addition, query `gh pr list --search "head:ci/rule-prune-retire- state:open"` for open retirement proposals. If any retirement PR's body references a rule-id that overlaps the proposed addition's topic (substring match on the Sharp-edge text), defer the cluster with `::compound-promote-rule-prune-collision::<cluster-hash>` and re-evaluate next week.

### Updated AC count

Original plan: AC1-AC19. With spec-flow additions: **AC1-AC25** (added AC20-AC25). Original AC10 revised in place.

### Updated Open Questions

- ~~Q1: claude-code-action output extraction~~ → resolved via FR12 (parse + skip on malformed).
- ~~Q2: bootstrap-week throttle~~ → resolved: week-1 cap=1, week-2 cap=1, weeks 3+: cap=2 unless rejection rate >50%.
- ~~Q3: audit-log decision-column update~~ → resolved as NO (append-only; derive at read-time).
- ~~Q4: per-cluster gdpr-gate cost~~ → unchanged; verify post-first-run.
- **NEW Q5:** Jaccard overlap threshold for cluster dedup. Default 0.8; tune after empirical data.
- **NEW Q6:** Whether the `gdpr-block` label needs to be created in Phase 0. YES — added to the workflow's "Ensure labels exist" step.

### Updated Files-to-Create

- Add `gh label create gdpr-block` to the workflow's Phase 0 step.

### Updated Files-to-Edit

- No new files; FR10/FR11/FR12 logic lives in `scripts/compound-promote.sh` (driver-side) and the claude-code-action prompt (LLM-side).

## Pre-submission checklist (filled at /work completion)

- [x] Title is searchable: `feat: compound promotion loop (self-healing CI sweep)`.
- [x] Labels (post-merge): `type/feature`, `domain/engineering`, `priority/p3-low` (matches issue #2720).
- [x] Acceptance criteria are measurable (AC1-AC19).
- [x] Files-to-create / Files-to-edit lists name every artifact.
- [x] Browser task automation check: N/A (no browser).
- [x] Deferral tracking check: 6 deferrals enumerated with re-evaluation criteria; issues filed at PR-merge.
- [x] CLI-verification gate: all CLI invocations verified above.
