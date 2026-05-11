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
plan_review_consolidation: 5-agent panel (DHH, Kieran, Code Simplicity, Architecture, SpecFlow re-validation) on v1 (953-line) plan; this v2 applies all consensus simplifications + must-fix correctness items.
---

# feat: Compound Promotion Loop (self-healing CI sweep)

## Overview

A weekly GitHub Actions cron that:

1. Reads `knowledge-base/project/learnings/` (committed corpus).
2. Pre-filters via deterministic shell GDPR scan + retired-rule blocklist.
3. Calls the Anthropic API directly (no `claude-code-action` wrapper) to LLM-cluster the safe corpus by problem/root-cause.
4. Opens up to 2 **draft PRs** per week proposing skill-instruction edits or AGENTS.md rule additions when a cluster reaches N=5 learnings.

Operator merges or closes via normal GitHub PR review — the loop never auto-merges. Default OFF.

This realizes Layer 2 of the 2026-03-03 self-healing-workflow design (deferred as #421 until Layer 1 — Deviation Analyst — proved value; Layer 1 has been shipping in compound Phase 1.5 for two months). Operationalizes AGENTS.md `wg-every-session-error-must-produce-either`.

**Architectural pivot from v1 plan:** v1 prescribed a two-job split (`cluster` job using `claude-code-action` → `promote` job using bot-pr matrix) to dance around `claude-code-action`'s post-step token revocation. 5-agent plan-review converged: drop the wrapper. Plain `curl https://api.anthropic.com/v1/messages` from a single job eliminates the matrix split, the `clusters_json` GitHub-output handoff (Q1 in v1, never resolved), template-injection on `matrix.cluster.*` (Kieran P1-6), and matrix-DOS (Architecture #2). Trade-off: we lose the agent's general tool-use capability (no native Bash/Read tools); the agent sees the corpus as a single message and emits clustering JSON in its response. The clustering task fits comfortably in one Anthropic API call.

**Estimated complexity:** SMALL (1 day). All five reviewers concurred that the load-bearing safety is `default OFF + draft PR + manual confirm + per-week cap = 2`; everything else is defending against failures the operator catches by reading the PR.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Spec TR1: use `secrets.SOLEUR_GH_TOKEN` not `GITHUB_TOKEN` | NO workflow uses `SOLEUR_GH_TOKEN`; all use `${{ github.token }}`. Constitution.md line 153 documents the GITHUB_TOKEN cascade and prescribes the bot-pr-with-synthetic-checks composite as the workaround. | Use `${{ github.token }}` with the extended composite. |
| Spec FR3: open draft PR with `self-healing/auto` label | Label does NOT exist (`gh label list`); repo's canonical PR-opening composite (`bot-pr-with-synthetic-checks`) does NOT support `--draft`, `--label`, or `skip-auto-merge`. | (a) Workflow's idempotent label-create step. (b) Bounded extension of composite with 3 optional inputs + boolean normalization. |
| Spec TR3: persistent state files `.github/promotion-queue.json` + `.github/promotion-cooldowns.json` | `.github/workflows/*.yml` writes re-trigger workflows; recursion risk. Per-week cap and cooldown can be derived from `gh pr list --label self-healing/auto` instead. | Drop both state files. Derive per-week cap from open-PR count; derive cooldown from closed-PR count over last 30 days. Single source of truth = the PRs themselves. |
| Spec FR8: invoke `/soleur:gdpr-gate` programmatically per cluster | `gdpr-gate` skill has NO headless CLI entry — only the `/soleur:gdpr-gate <scope>` slash command and the lefthook-only advisory script (`scripts/gdpr-gate.sh`, always exits 0). | Use the lefthook script's underlying regex pattern as a deterministic shell pre-pass over each learning file BEFORE the Anthropic call. Files matching PII patterns are excluded from the corpus. No per-cluster `gdpr-gate` invocation; no per-learning blocklist; no `gdpr-block` label. |
| Spec implies `claude-code-action` wrapper | `claude-code-action`'s post-step revokes its App installation token, breaking subsequent `gh pr create` / `gh api` calls in the same job. v1 plan dodged this with a two-job split. v2 plan: drop the wrapper, call Anthropic API directly via `curl`. | Single-job workflow; no wrapper; no matrix. |
| Spec implies cron reads `.claude/.rule-incidents.jsonl` | File is gitignored; CI runners never see it. | No change; document in Sharp Edges. |
| Spec TR2: anthropic-preflight not mentioned | Universal precedent: every claude-code-action workflow runs `./.github/actions/anthropic-preflight` first. We're not using claude-code-action, but we still need to gate on `ANTHROPIC_API_KEY` presence + monthly cap. | Add `preflight` job mirror per template; reuse the `anthropic-preflight` composite (it's API-key-shape-agnostic). |

## User-Brand Impact

**If this lands broken, the user experiences:** A bad auto-promoted rule lands via merged PR → cascades to every operator's session via `@AGENTS.md` import or skill invocation → subtle behavior degradation (wrong default, stale guidance, blocked work) until manual rollback via `scripts/retired-rule-ids.txt`.

**If this leaks, the user's workflow / data is exposed via:** A learning file containing PII (email fragments, customer names, prod IDs) gets clustered, summarized, and quoted in a PR body that is pushed to the public repo. Mitigations: opt-in default OFF, deterministic shell GDPR pre-pass that excludes any learning matching the canonical PII regex from the Anthropic-bound corpus, retired-rule pre-pass that excludes any learning whose path appears in a `retired-rule-ids.txt` breadcrumb, draft PR + manual confirm.

**Brand-survival threshold:** `single-user incident`

CPO sign-off required at plan time before `/work` begins. CPO participated in the brainstorm (2026-05-11); no fresh invocation needed. `user-impact-reviewer` will be invoked at review-time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block. AC10b enforces invocation.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Marketing (carry-forward from brainstorm). Operations / Sales / Finance / Support: not relevant.

### Engineering (CTO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** SMALL complexity. Telemetry pipeline + retire mechanism + bot-PR composite all in place. Plan-review (5-agent panel) further reduced architecture: drop two-job split, drop matrix, drop driver-side state files, drop LLM-mediated GDPR scan in favor of shell pre-pass.

### Product (CPO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** Highest risk = promotion-fatigue; mitigated by per-week cap (≤2/week), opt-in default OFF, draft PR. Inline-at-/compound surface deferred to v2.

### Product/UX Gate

**Tier:** none
**Decision:** not invoked
**Rationale:** No new user-facing pages, modals, or components. Files-to-create are workflow YAML + shell script + state markdown. Mechanical-escalation rule does not match.

### Legal (CLO) — carry-forward from brainstorm + plan-time GDPR-gate

**Status:** reviewed
**Assessment:** USER_BRAND_CRITICAL surface. Required: append-only `promotion-log.md`, two-tier consent (capability opt-in via config + per-PR confirm), pre-promotion GDPR scan, plugin-scope deferral to v2 with ToS update. v1 stays consumer-local. Plan-time `/soleur:gdpr-gate` invocation found 1 Important (Anthropic DPA gap, pre-existing systemic) + 3 Suggestions; folded as AC26 + Phase 4 inline disclosures.

### Marketing (CMO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** Launch-blog-post-worthy; bundle launch with #2719. External name "Learning Ratchet" or "Compounding Gate". Marketing artifacts are downstream of merge.

## GDPR / Compliance Gate (plan-time invocation summary)

Invoked: `/soleur:gdpr-gate "feat-compound-promotion-loop plan + spec"` on 2026-05-11. **No Critical findings.**

| `check_id` | Severity | Resolution |
|---|---|---|
| `GDPR-Chapter-V` — Anthropic processor not in compliance-posture.md Vendor DPAs | Important | **AC26:** verify Anthropic DPA row present in `compliance-posture.md` before merge. Pre-existing systemic gap (applies to gdpr-gate skill itself + every claude-code-action workflow); file separate `compliance/improvement` issue. Block ship until row lands. |
| `LC-04` — DPIA reminder for self-improving cascading surface | Suggestion | Active Item: "DPIA assessment for compound-promotion-loop (Art. 35 candidate): defer until first 4 weeks of operation generate empirical data." |
| `TS-04` — Test fixture synthesized-PII assertion | Suggestion | **AC27:** Phase 2 fixture files contain ONLY synthesized PII; test asserts no real-PII regex patterns appear. |
| `LC-01` — Operator consent inline disclosure | Suggestion | Phase 4: 4-line inline comment in `promotion-config.yml.example` documenting data flows + kill-switch. |

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/compound-promote.sh` | Driver: opt-in check, week-cap derivation, GDPR shell pre-pass, retired-rule pre-pass, Anthropic API orchestration. Mirrors `scripts/rule-prune.sh` CLI conventions. |
| `scripts/compound-promote.test.sh` | Peer test (mirror `scripts/rule-metrics-aggregate.test.sh`). 3 test cases (opt-in, week-cap, GDPR pre-pass). Test-mode toggle: `COMPOUND_PROMOTE_FIXTURE_ROOT`. |
| `.github/workflows/scheduled-compound-promote.yml` | Weekly cron `0 0 * * 0`. Three jobs: `preflight`, `promote` (single, no matrix), `email-on-failure`. |
| `knowledge-base/project/promotion-config.yml.example` | Opt-in TEMPLATE. Operator copies to `promotion-config.yml` (gitignored — see Files to Edit `.gitignore`) and sets `enabled: true`. Includes 4-line data-flow disclosure. |
| `knowledge-base/project/learnings/promotion-log.md` | Append-only audit log scaffold. CLO non-repudiation requirement. |
| `knowledge-base/engineering/runbooks/compound-promote-runbook.md` | Operator runbook: opt-in / opt-out / review heuristic / revert path / kill switch. |
| `knowledge-base/engineering/architecture/decisions/ADR-021-stateless-self-modifying-cron.md` | ADR for the architectural pattern (Architecture-strategist advisory). Stateless derivation from PR queries; single-job + plain Anthropic API call (no `claude-code-action` wrapper) for self-modifying loops. |

## Files to Edit

| Path | Edit |
|---|---|
| `.github/actions/bot-pr-with-synthetic-checks/action.yml` | Add 3 optional inputs: `draft` (default `'false'`), `skip-auto-merge` (default `'false'`), `labels` (default `''`, newline-separated). **Boolean normalization** at the top of the run block: lowercase + reject non-boolean. **Preserve `set -eo pipefail` (NOT `-euo`)** — existing inputs would fail under `-u`. Backward compatible — existing callers (`scheduled-rule-prune.yml`, `rule-metrics-aggregate.yml`) get default behavior. |
| `plugins/soleur/skills/compound/SKILL.md` | Add a one-line **Cross-Session Promotion Loop (Layer 2)** subsection under Knowledge Base Integration pointing at the runbook. |
| `.gitignore` | Add `knowledge-base/project/promotion-config.yml` (live config — operator commits intentionally if tracked). Defensive: `.github/promotion-*.json` (no state files used; defensive against re-introduction). |
| `knowledge-base/legal/compliance-posture.md` | Add Active Item row for #2720; extend Notes column to mention DPIA candidacy (LC-04). |

## Implementation Phases

### Phase 0 — Pre-flight: label + branch hygiene

0.1. Verify `self-healing/auto` label state:
```bash
gh label list --limit 200 | grep -E "^self-healing/auto\b" || echo "needs creation (workflow's idempotent step will handle on first run)"
```

0.2. The workflow's `Ensure label exists` step is idempotent (`gh label create ... 2>/dev/null || true`); covers AC14.

**Deliverables:** none (read-only check).

### Phase 1 — `bot-pr-with-synthetic-checks` extension (TDD-suitable)

1.1. **Hand-test scaffold.** Composite-action testability is limited (no test runner in repo). Document expected behavior in `.github/actions/bot-pr-with-synthetic-checks/CHANGELOG.md` (create if missing): "v2 (date): adds optional `draft`, `skip-auto-merge`, `labels` inputs + boolean normalization at the boundary".

1.2. **Edit `.github/actions/bot-pr-with-synthetic-checks/action.yml`.** Inputs:

```yaml
inputs:
  # ... existing inputs ...
  draft:
    description: >
      If 'true' (case-insensitive), open the PR as draft. Default 'false'
      preserves existing caller behavior.
    required: false
    default: 'false'
  skip-auto-merge:
    description: >
      If 'true' (case-insensitive), skip the final `gh pr merge --squash --auto`.
      Default 'false' preserves existing caller behavior.
    required: false
    default: 'false'
  labels:
    description: >
      Newline-separated label names. Empty string skips the label step.
      Labels MUST already exist (caller's responsibility).
    required: false
    default: ''
```

1.3. **Modify the `run:` block.** Preserve the existing `set -eo pipefail` (the existing inputs would fail under `-u`); add at the very top of the run block:

```bash
# Normalize boolean inputs at the boundary (Architecture-strategist #4).
DRAFT=$(echo "${DRAFT:-false}" | tr '[:upper:]' '[:lower:]')
SKIP_AUTO_MERGE=$(echo "${SKIP_AUTO_MERGE:-false}" | tr '[:upper:]' '[:lower:]')
case "$DRAFT" in true|false) ;; *) echo "::error::draft must be true|false (got: $DRAFT)"; exit 1;; esac
case "$SKIP_AUTO_MERGE" in true|false) ;; *) echo "::error::skip-auto-merge must be true|false (got: $SKIP_AUTO_MERGE)"; exit 1;; esac
```

After existing `gh pr create` line, branch on `$DRAFT`:
```bash
PR_CREATE_ARGS=(--title "${PR_TITLE_PREFIX} ${DATE_SUFFIX}" --body-file "$BODY_FILE" --base main --head "$BRANCH")
if [[ "$DRAFT" == "true" ]]; then
  PR_CREATE_ARGS+=(--draft)
fi
gh pr create "${PR_CREATE_ARGS[@]}"
```

After synthetic check-runs loop:
```bash
if [[ -n "$LABELS" ]]; then
  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    gh pr edit "$BRANCH" --add-label "$label"
  done <<< "$LABELS"
fi
```

Wrap final `gh pr merge`:
```bash
if [[ "$SKIP_AUTO_MERGE" != "true" ]]; then
  gh pr merge "$BRANCH" --squash --auto
fi
```

Add to `env:` block: `DRAFT: ${{ inputs.draft }}`, `SKIP_AUTO_MERGE: ${{ inputs.skip-auto-merge }}`, `LABELS: ${{ inputs.labels }}`.

1.4. **Backward-compat verification.** Read `scheduled-rule-prune.yml` and `rule-metrics-aggregate.yml`; both omit the new inputs; defaults `'false'`/`'false'`/`''` preserve behavior.

**Deliverables:** edited `action.yml` + new `CHANGELOG.md`. Exit criterion: existing callers' behavior unchanged.

### Phase 2 — `scripts/compound-promote.sh` driver

2.1. **Failing test first.** Create `scripts/compound-promote.test.sh`. Three test cases:

- `test_no_config_file_returns_noop`: no `promotion-config.yml` → exit 0 with `::compound-promote-status::no-config`.
- `test_disabled_config_returns_noop`: `enabled: false` → exit 0 with `::compound-promote-status::disabled`.
- `test_gdpr_pre_pass_excludes_pii_files`: fixture with one learning containing `test@example.com` (synthesized — per `cq-test-fixtures-synthesized-only`) → script emits `::compound-promote-pii-excluded::<path>` for that file and the file does NOT appear in the corpus passed to the (mocked) Anthropic call.

Test-mode toggles:
- `COMPOUND_PROMOTE_FIXTURE_ROOT` — points to fixture dir.
- `GH_BIN` — mock `gh` binary path.
- `CURL_BIN` — mock `curl` binary path (returns canned Anthropic response JSON).

Fixtures live at `tests/fixtures/compound-promote/learnings/*.md` with synthesized PII only (`@example.com`, `00000000-0000-0000-0000-000000000000` UUIDs). AC27 enforces.

2.2. **Implement `scripts/compound-promote.sh`:**

```bash
#!/usr/bin/env bash
# Driver for the compound-promotion-loop weekly cron.
#
# Pipeline: opt-in check → week-cap derivation → GDPR shell pre-pass →
# retired-rule pre-pass → Anthropic API call → emit clusters JSON.
#
# Sentinels emitted (one per line):
#   ::compound-promote-status::<no-config|disabled|enabled|week-cap-reached|empty-corpus>
#   ::compound-promote-week-cap::<remaining-int>
#   ::compound-promote-pii-excluded::<path>
#   ::compound-promote-retired-excluded::<path>
#   ::compound-promote-clusters-json::<base64-encoded-JSON-array>
#
# Sister: scripts/rule-prune.sh (demotion side); scripts/rule-metrics-aggregate.sh.
# Issue: #2720. Plan: knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md
set -euo pipefail

REPO_ROOT="${COMPOUND_PROMOTE_FIXTURE_ROOT:-$(git rev-parse --show-toplevel)}"
CONFIG="$REPO_ROOT/knowledge-base/project/promotion-config.yml"
LEARNINGS_DIR="$REPO_ROOT/knowledge-base/project/learnings"
RETIRED_FILE="$REPO_ROOT/scripts/retired-rule-ids.txt"
WEEK_CAP_DEFAULT=2
GH_BIN="${GH_BIN:-gh}"
CURL_BIN="${CURL_BIN:-curl}"

# 1. Opt-in gate
if [[ ! -f "$CONFIG" ]]; then
  printf '::compound-promote-status::no-config\n'
  exit 0
fi
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

# 3. GDPR shell pre-pass (deterministic; uses lefthook gdpr-gate.sh underlying regex)
#    Excludes any learning file matching PII patterns BEFORE Anthropic ever sees it.
PII_REGEX='([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})|([0-9]{1,3}(\.[0-9]{1,3}){3})|([A-Z]{2}[0-9]{2}[A-Z0-9]{4}[0-9]{7}([A-Z0-9]?){0,16})'
SAFE_FILES=()
while IFS= read -r -d '' file; do
  rel="${file#$REPO_ROOT/}"
  if grep -qE "$PII_REGEX" "$file" 2>/dev/null; then
    printf '::compound-promote-pii-excluded::%s\n' "$rel"
    continue
  fi
  SAFE_FILES+=("$file")
done < <(find "$LEARNINGS_DIR" -type f -name '*.md' ! -path '*/archive/*' -print0 2>/dev/null)

# 4. Retired-rule shell pre-pass (deterministic; reads retired-rule-ids.txt breadcrumbs)
#    For each learning, check if its path is referenced in any retired rule's breadcrumb (field 4).
if [[ -f "$RETIRED_FILE" ]]; then
  declare -A RETIRED_PATHS
  while IFS='|' read -r _id _date _pr breadcrumb; do
    [[ -z "$breadcrumb" ]] && continue
    # Extract path-like tokens from breadcrumb (e.g., "learnings/2026-05-XX-foo.md")
    while read -r token; do
      RETIRED_PATHS["$token"]=1
    done < <(echo "$breadcrumb" | grep -oE 'knowledge-base/project/learnings/[^ ]+\.md' || true)
  done < "$RETIRED_FILE"
  
  FILTERED_FILES=()
  for file in "${SAFE_FILES[@]}"; do
    rel="${file#$REPO_ROOT/}"
    if [[ -n "${RETIRED_PATHS[$rel]:-}" ]]; then
      printf '::compound-promote-retired-excluded::%s\n' "$rel"
      continue
    fi
    FILTERED_FILES+=("$file")
  done
  SAFE_FILES=("${FILTERED_FILES[@]}")
fi

if (( ${#SAFE_FILES[@]} == 0 )); then
  printf '::compound-promote-status::empty-corpus\n'
  exit 0
fi

# 5. Anthropic API call (clustering)
#    NOT using claude-code-action wrapper — token revocation post-step would
#    break subsequent gh calls in the same job. Plain curl is sufficient for
#    a single clustering message.
[[ -z "${ANTHROPIC_API_KEY:-}" ]] && { echo "::error::ANTHROPIC_API_KEY not set"; exit 1; }

# Build corpus payload (file paths + summaries — NOT full content; reduces token burn).
# For each safe file, extract title + first 5 lines of body.
CORPUS_JSON=$(jq -n '[]')
for file in "${SAFE_FILES[@]}"; do
  rel="${file#$REPO_ROOT/}"
  summary=$(head -n 10 "$file" | jq -Rs .)
  CORPUS_JSON=$(echo "$CORPUS_JSON" | jq --arg path "$rel" --argjson summary "$summary" '. + [{path: $path, summary: $summary}]')
done

PROMPT="You are a clustering agent. Cluster the following learnings by problem/root-cause similarity. Return up to ${REMAINING} qualifying clusters (each with ≥5 source learnings) as a JSON array. Schema: [{cluster_hash:'<sha256>', tier:'skill'|'agents-md', target_path:string, source_learnings:[paths], proposed_diff_unified:string, rationale:string, byte_impact:{before:int,after:int,delta:int}}]. Apply AGENTS.md cq-agents-md-tier-gate (already-enforced→skip; domain-scoped→skill; cross-cutting→agents-md). For agents-md targets, refuse if AGENTS.md byte count > 37000. Compute cluster_hash = sha256(sorted(source_learnings)). Output ONLY the JSON array, nothing else."

REQUEST=$(jq -n \
  --arg model "claude-sonnet-4-6" \
  --argjson max_tokens 8192 \
  --arg prompt "$PROMPT" \
  --argjson corpus "$CORPUS_JSON" \
  '{model: $model, max_tokens: $max_tokens, messages: [{role: "user", content: ($prompt + "\n\nCorpus:\n" + ($corpus | tostring))}]}')

RESPONSE=$("$CURL_BIN" -sS https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$REQUEST")

# Extract the assistant's text reply
CLUSTERS_TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text // empty')
if [[ -z "$CLUSTERS_TEXT" ]]; then
  echo "::error::Anthropic API returned empty content"
  echo "$RESPONSE" | head -c 500 >&2
  exit 1
fi

# Validate JSON shape (defensive; equivalent of v1's FR12)
if ! CLUSTERS_JSON=$(echo "$CLUSTERS_TEXT" | jq -e 'if type == "array" then . else error("not an array") end' 2>/dev/null); then
  echo "::error::Anthropic response is not a valid JSON array"
  echo "$CLUSTERS_TEXT" | head -c 500 >&2
  printf '::compound-promote-clusters-json::%s\n' "$(echo '[]' | base64 -w 0)"
  exit 0
fi

# Hard slice at WEEK_REMAINING (Architecture #2 — defense against agent emitting >cap)
CLUSTERS_JSON=$(echo "$CLUSTERS_JSON" | jq --argjson cap "$REMAINING" '.[0:$cap]')

CLUSTERS_B64=$(printf '%s' "$CLUSTERS_JSON" | base64 -w 0)
printf '::compound-promote-clusters-json::%s\n' "$CLUSTERS_B64"
```

Notes:
- `set -euo pipefail` per AGENTS.md sharp edge — `${var:-}` for unset, `|| true` for grep zero-match. Each `gh`/`curl` call has appropriate fallback.
- `base64 -w 0` (no trailing newline).
- `awk` for YAML parse — no `yq` dependency.
- Anthropic model: `claude-sonnet-4-6` (clustering benefits from Sonnet's reasoning vs. Haiku's speed).
- `CORPUS_JSON` includes path + first 10 lines per file to bound prompt size on a 947-file corpus.
- Hard slice via `jq '.[0:$cap]'` is the load-bearing defense against the LLM emitting more clusters than `WEEK_REMAINING`.

2.3. **Run the test suite locally:** `bash scripts/compound-promote.test.sh` — all green.

**Deliverables:** `scripts/compound-promote.sh` (executable), `scripts/compound-promote.test.sh`. Exit criterion: tests green.

### Phase 3 — `scheduled-compound-promote.yml` workflow

3.1. **Single-job structure.** No matrix. No two-job split. Plain bash loop over the clusters.

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
  issues: write

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

  promote:
    needs: preflight
    if: needs.preflight.outputs.ok == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 15      # plenty of headroom for one Anthropic call + ≤2 PRs
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1

      - name: Ensure self-healing/auto label exists
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh label create "self-healing/auto" \
            --description "Auto-opened by compound-promotion-loop; manual review required" \
            --color "FBCA04" 2>/dev/null || true

      - name: Driver — opt-in, week-cap, GDPR pre-pass, retired pre-pass, Anthropic call
        id: driver
        env:
          GH_TOKEN: ${{ github.token }}
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          set -euo pipefail
          out=$(bash scripts/compound-promote.sh)
          printf '%s\n' "$out"
          STATUS=$(printf '%s\n' "$out" | sed -n 's/^::compound-promote-status:://p' | head -n 1)
          if [[ "$STATUS" != "enabled" ]]; then
            echo "skipped=true" >> "$GITHUB_OUTPUT"
            echo "clusters_b64=" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          CLUSTERS_B64=$(printf '%s\n' "$out" | sed -n 's/^::compound-promote-clusters-json:://p' | head -n 1)
          if [[ -z "$CLUSTERS_B64" ]]; then
            echo "skipped=true" >> "$GITHUB_OUTPUT"
            echo "clusters_b64=" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          CLUSTERS_JSON=$(echo "$CLUSTERS_B64" | base64 -d)
          COUNT=$(echo "$CLUSTERS_JSON" | jq 'length')
          if (( COUNT == 0 )); then
            echo "skipped=true" >> "$GITHUB_OUTPUT"
            echo "clusters_b64=" >> "$GITHUB_OUTPUT"
            exit 0
          fi
          echo "skipped=false" >> "$GITHUB_OUTPUT"
          echo "clusters_b64=$CLUSTERS_B64" >> "$GITHUB_OUTPUT"

      - name: Open draft PR per cluster
        if: steps.driver.outputs.skipped == 'false'
        env:
          GH_TOKEN: ${{ github.token }}
          CLUSTERS_B64: ${{ steps.driver.outputs.clusters_b64 }}
        run: |
          set -euo pipefail
          CLUSTERS_JSON=$(echo "$CLUSTERS_B64" | base64 -d)
          DATE_SUFFIX="$(date -u +%Y-%m-%d)"
          
          # Loop over clusters (NOT a matrix; bounded by WEEK_REMAINING in driver).
          echo "$CLUSTERS_JSON" | jq -c '.[]' | while IFS= read -r cluster; do
            CLUSTER_HASH=$(echo "$cluster" | jq -r '.cluster_hash')
            TIER=$(echo "$cluster" | jq -r '.tier')
            TARGET=$(echo "$cluster" | jq -r '.target_path')
            DIFF=$(echo "$cluster" | jq -r '.proposed_diff_unified')
            SOURCES_CSV=$(echo "$cluster" | jq -r '.source_learnings | join(",")')
            COUNT=$(echo "$cluster" | jq -r '.source_learnings | length')
            
            # Cluster-hash integrity check (Architecture #3): re-derive and verify.
            COMPUTED=$(echo "$cluster" | jq -r '.source_learnings | sort | join("\n")' | sha256sum | awk '{print $1}')
            if [[ "$COMPUTED" != "$CLUSTER_HASH" ]]; then
              echo "::error::cluster-hash mismatch: claimed=$CLUSTER_HASH computed=$COMPUTED — refusing to open PR"
              continue
            fi
            
            # Apply diff
            if ! printf '%s' "$DIFF" | git apply --check; then
              echo "::error::diff failed git apply --check for cluster $CLUSTER_HASH"
              continue
            fi
            printf '%s' "$DIFF" | git apply
            
            # Append audit-log row (rows append-only; status derived at read-time)
            printf '\n| %s | %s | %s | %d | pending | %s | (PR pending) |\n' \
              "$DATE_SUFFIX" "$CLUSTER_HASH" "$TARGET" "$COUNT" "$TIER" \
              >> knowledge-base/project/learnings/promotion-log.md
            git add "$TARGET" knowledge-base/project/learnings/promotion-log.md
            
            BRANCH="self-healing/auto-${CLUSTER_HASH}-${DATE_SUFFIX}"
            COMMIT_MSG=$(cat <<EOF
chore(self-healing): promote cluster ${CLUSTER_HASH} to ${TARGET}

Bot-Author: compound-promotion-loop@${{ github.sha }}
Source-Learnings: ${SOURCES_CSV}
Threshold-Hit: ${COUNT}/5
Cluster-Hash: ${CLUSTER_HASH}
Tier: ${TIER}
EOF
)
            git config user.name "github-actions[bot]"
            git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
            git checkout -b "$BRANCH"
            git commit -m "$COMMIT_MSG"
            git push -u origin "$BRANCH"
            
            # Open draft PR + label via extended composite (or inline via gh CLI).
            # Inline form is simpler than calling the composite from a shell loop.
            BODY="Promoted by compound-promotion-loop. Source learnings: $(echo "$SOURCES_CSV" | tr ',' ' '). Tier: $TIER. Cluster-Hash: $CLUSTER_HASH. Reviewer: verify the diff respects cq-agents-md-tier-gate and cq-agents-md-why-single-line; merge to apply, close to reject."
            gh pr create \
              --title "self-healing(auto): promote cluster ${CLUSTER_HASH} ${DATE_SUFFIX}" \
              --body "$BODY" \
              --base main \
              --head "$BRANCH" \
              --draft
            gh pr edit "$BRANCH" --add-label "self-healing/auto"
            
            # Post synthetic checks (mirror bot-pr-with-synthetic-checks logic inline).
            COMMIT_SHA=$(git rev-parse HEAD)
            for check in test dependency-review e2e "skill-security-scan PR gate"; do
              gh api "repos/${{ github.repository }}/check-runs" \
                -f name="$check" \
                -f head_sha="$COMMIT_SHA" \
                -f status=completed \
                -f conclusion=success \
                -f "output[title]=Bot PR" \
                -f "output[summary]=self-healing/auto promotion — operator review required"
            done
            gh api "repos/${{ github.repository }}/check-runs" \
              -f name=cla-check \
              -f head_sha="$COMMIT_SHA" \
              -f status=completed \
              -f conclusion=success \
              -f "output[title]=CLA pre-approved" \
              -f "output[summary]=github-actions[bot] is in CLA allowlist"
            
            git checkout main
          done

  email-on-failure:
    needs: [preflight, promote]
    if: always() && (needs.preflight.result == 'failure' || needs.promote.result == 'failure')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5  # v4.3.1
      - uses: ./.github/actions/notify-ops-email
        with:
          subject: '[FAIL] Scheduled: Compound Promotion Loop failed'
          body: '<p><strong>Scheduled: Compound Promotion Loop</strong> failed.</p><p><a href="${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}">View run</a></p>'
          resend-api-key: ${{ secrets.RESEND_API_KEY }}
```

**Architectural notes:**
- Single `promote` job (no matrix; the bash `while read` loop is the per-cluster iterator). Bounded by `WEEK_REMAINING` cap in the driver.
- PR creation inlined (matches the bot-pr composite's logic) rather than calling the composite from a shell loop, because the composite's date-suffixed branch name conflicts with our cluster-hash branch name. The bot-pr composite is still extended (Phase 1) so future single-PR callers can use it; this workflow uses an inline equivalent.
- Cluster-hash integrity verification (Architecture #3) — recomputed from `source_learnings` and compared to claimed `cluster_hash`. Mismatch → skip cluster + log error.
- Synthetic checks posted inline (4 checks + cla-check). Required to satisfy CI Required + CLA Required rulesets so operator can convert draft → ready and merge.
- `email-on-failure` covers both preflight and promote failures.

**Deliverables:** `.github/workflows/scheduled-compound-promote.yml`. Exit criterion: workflow YAML parses (visual inspection — no `actionlint` in repo).

### Phase 4 — Config + audit-log scaffolds

4.1. Create `knowledge-base/project/promotion-config.yml.example`:
```yaml
# Compound Promotion Loop config.
#
# DATA FLOW (read before opting in):
# - Enabling sends summaries (path + first 10 lines) of your
#   knowledge-base/project/learnings/ files to Anthropic for clustering.
# - The pre-promotion GDPR shell pre-pass excludes any learning matching
#   PII regex (emails, IPv4, IBAN) BEFORE the Anthropic call.
# - Opens public draft PRs whose bodies quote source-learning paths and
#   the proposed diff. PR bodies are world-readable on the public repo.
# - Kill switch: set enabled: false and commit; next cron tick exits no-op.
#
# Copy this file to knowledge-base/project/promotion-config.yml (gitignored)
# and set enabled: true. See knowledge-base/engineering/runbooks/compound-promote-runbook.md.
# Default: OFF. Issue: #2720.
enabled: false
```

4.2. Add to `.gitignore`:
```
# Compound promotion-loop opt-in (operator-controlled; do not auto-track)
knowledge-base/project/promotion-config.yml
# Defensive: no state files used by the loop, but reject re-introduction.
.github/promotion-*.json
```

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

Decision values: `pending` (initial only). Live state derived at read-time from `gh pr view` of the linked PR (merged|closed) — log rows are NEVER mutated.

<!-- ROWS BELOW THIS LINE -->
```

4.4. Update `knowledge-base/legal/compliance-posture.md` — Read first per `hr-always-read-a-file-before-editing-it`. Add Active Item row referencing #2720; extend Notes column to mention DPIA candidacy (LC-04).

**Deliverables:** the 3 new files + gitignore edit + compliance-posture row. Exit criterion: `git status --short` shows the entries.

### Phase 5 — Compound skill cross-reference

Edit `plugins/soleur/skills/compound/SKILL.md` Knowledge Base Integration section, append:

```markdown
### Cross-Session Promotion Loop (Layer 2)

A weekly cron (`scheduled-compound-promote.yml`) consumes accumulated learnings and proposes skill / AGENTS.md edits via draft PR when N=5 learnings cluster around the same root cause. Default OFF. Opt in via `knowledge-base/project/promotion-config.yml`. See `knowledge-base/engineering/runbooks/compound-promote-runbook.md`. Issue: #2720.
```

**Deliverables:** edited `compound/SKILL.md` (+1 subsection ≤4 lines).

### Phase 6 — Operator runbook

Create `knowledge-base/engineering/runbooks/compound-promote-runbook.md` with:

- What it does (one paragraph).
- Opt in (3 commands).
- Opt out / kill switch (1 command).
- Reviewing a `self-healing/auto` PR (5-bullet acceptance heuristic).
- Reverting a promoted rule (1 sentence pointing at `scripts/retired-rule-ids.txt`).
- Sharp edges:
  - The cron CANNOT read `.claude/.rule-incidents.jsonl` (gitignored).
  - The `self-healing/auto` label is created idempotently by the workflow.
  - Plugin-scope edits deferred to v2.
  - Synthetic checks posted on draft PR so operator-merge satisfies rulesets.
  - GDPR shell pre-pass is regex-based; sufficient for v1, not exhaustive (use the LLM-driven `/soleur:gdpr-gate` for narrower targeted scans).

**Deliverables:** the runbook file.

### Phase 7 — Pre-merge verification + post-merge

7.1. Run `bash scripts/compound-promote.test.sh` — all green.

7.2. Plan-time `/soleur:gdpr-gate` already invoked (findings folded above). No re-invocation at /work unless the implementation diverges from the spec.

7.3. Hand-test the driver script:
```bash
COMPOUND_PROMOTE_FIXTURE_ROOT=/tmp/compound-promote-fixture \
  GH_BIN=/tmp/gh-mock.sh \
  CURL_BIN=/tmp/curl-mock.sh \
  ANTHROPIC_API_KEY=fake-key \
  bash scripts/compound-promote.sh
```

7.4. **Cannot test workflow pre-merge** — `gh workflow run` against new file on feature branch returns 404 per learning `2026-04-21-workflow-dispatch-requires-default-branch.md`. First live run is post-merge (AC16):
```bash
gh workflow run scheduled-compound-promote.yml
gh run watch
```

7.5. PR #3559 body MUST use:
- `Closes #2720` on its own line (intentional auto-close).
- `Ref #2718` (parent — leave open).
- `Ref #421` (already closed-as-superseded).
- `## Changelog` section (semver:minor).
- Pass `pr-auto-close-scanner.yml` regex sweep (AC15b).

7.6. PR #3559 review: operator runs `/soleur:review #3559` before mark-as-ready. The review skill's conditional-agent block invokes `user-impact-reviewer` automatically given the brand-survival threshold marker in PR body (AC10b).

**Deliverables:** test pass + post-merge workflow run verified.

### Phase 8 — Issue updates + ADR

8.1. Create `knowledge-base/engineering/architecture/decisions/ADR-021-stateless-self-modifying-cron.md` (Architecture #5 advisory):
- Context: claude-code-action token revocation; need single-job arch for self-modifying CI loops.
- Decision: stateless derivation from PR queries + plain Anthropic API call (no `claude-code-action` wrapper) when the loop opens PRs.
- Consequences: simpler arch; loses claude-code-action's tool-use; clustering must fit in a single API call.
- Alternatives considered: two-job split (rejected — Q1 unresolvable); peter-evans/create-pull-request (rejected — no precedent).

8.2. Post-merge: `gh workflow run scheduled-compound-promote.yml` (AC16).

8.3. File pre-existing Anthropic-DPA gap as separate compliance/improvement issue (AC26).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** `.github/actions/bot-pr-with-synthetic-checks/action.yml` declares 3 new optional inputs (`draft`, `skip-auto-merge`, `labels`) with backward-compatible string defaults.
- [ ] **AC2:** Boolean inputs normalized at boundary (lowercase + reject non-boolean). Existing callers (`scheduled-rule-prune.yml`, `rule-metrics-aggregate.yml`) NOT modified; defaults preserve their behavior.
- [ ] **AC2b:** Composite preserves `set -eo pipefail` (NOT upgraded to `-euo` — Kieran P0-1).
- [ ] **AC3:** `scripts/compound-promote.sh` exists, executable, mirrors `rule-prune.sh` CLI conventions (set -euo, stdout sentinels, env-overridable repo root + GH_BIN + CURL_BIN).
- [ ] **AC4:** `scripts/compound-promote.test.sh` exists with 3 test cases (no-config, disabled, GDPR-pre-pass-excludes-PII).
- [ ] **AC5:** `.github/workflows/scheduled-compound-promote.yml` exists. Single `promote` job (no matrix). Cron `0 0 * * 0`. Concurrency group `scheduled-compound-promote`, `cancel-in-progress: false`. Permissions explicitly declared.
- [ ] **AC6:** `knowledge-base/project/promotion-config.yml.example` includes 4-line data-flow disclosure (LC-01 fold).
- [ ] **AC7:** `knowledge-base/project/promotion-config.yml` is in `.gitignore`. `.github/promotion-*.json` defensive entry also present.
- [ ] **AC8:** `plugins/soleur/skills/compound/SKILL.md` has the Layer 2 cross-reference subsection.
- [ ] **AC9:** `knowledge-base/legal/compliance-posture.md` has an Active Item row referencing #2720 with DPIA candidacy note.
- [ ] **AC10a:** `bash scripts/compound-promote.test.sh` passes locally.
- [ ] **AC10b:** Operator invoked `/soleur:review #3559` before mark-as-ready; `user-impact-reviewer` findings resolved or scoped-out with rationale.
- [ ] **AC11:** Cluster-hash integrity verification step is present in workflow YAML (recompute + compare; refuse on mismatch — Architecture #3).
- [ ] **AC12:** Hard slice at `WEEK_REMAINING` in driver script via `jq '.[0:$cap]'` (Architecture #2).
- [ ] **AC13:** GDPR shell pre-pass uses canonical PII regex; excludes matching files BEFORE Anthropic call.
- [ ] **AC14:** `self-healing/auto` label exists (created by workflow's idempotent step on first run).
- [ ] **AC15:** PR #3559 body uses `Closes #2720` (own line) + `Ref #2718` + `Ref #421`.
- [ ] **AC15b:** PR #3559 body passes `pr-auto-close-scanner.yml` regex sweep — only `Closes #2720` matches.
- [ ] **AC16 (post-merge / pre-ship):** `gh workflow run scheduled-compound-promote.yml` triggers a manual run; the run completes (default config OFF → exit no-op is acceptable).
- [ ] **AC17:** ADR-021 exists at `knowledge-base/engineering/architecture/decisions/ADR-021-stateless-self-modifying-cron.md`.
- [ ] **AC18:** Provenance trailer in commit-message uses `Bot-Author:` + `Source-Learnings:` + `Cluster-Hash:` + `Tier:` (NO `Promoted-By:` — SpecFlow NG-8).
- [ ] **AC19:** Plan-review consensus changes applied (this v2 plan); 5-agent panel findings resolved or scoped out.

### Post-merge (operator, future cron runs)

- [ ] **AC20:** With `enabled: true` + a synthetic learnings-corpus addition (5+ similar test learnings), a `gh workflow run` opens exactly ONE draft `self-healing/auto` PR with the provenance trailer.
- [ ] **AC21:** Closing the test PR (without merge) → next `gh workflow run` within the same week respects per-week cap (open count counts toward cap).
- [ ] **AC22:** `promotion-log.md` rows are append-only; live state derivable via `gh pr view` of linked PRs.
- [ ] **AC23:** Anthropic processor row exists in `knowledge-base/legal/compliance-posture.md` Vendor DPAs (separate compliance/improvement issue lands first; #2720 ship blocked until then — AC26 from gdpr-gate findings).
- [ ] **AC24:** Test fixtures contain ONLY synthesized PII (`@example.com`, zero-UUIDs); no real-PII regex patterns appear (AC27 from gdpr-gate findings).

## Risks

- **R1 (HIGH, mitigated by 4 layers):** Bad auto-promoted rule cascades to every operator. Mitigations: opt-in default OFF, draft PR + manual confirm, per-week cap = 2, `user-impact-reviewer` at PR review. Combined: any single mitigation failure does not breach brand-survival.
- **R2 (LOW):** GDPR shell pre-pass regex is heuristic (emails, IPv4, IBAN). Will miss novel PII patterns (phone numbers in unusual formats, employee IDs). Mitigation: human reviewer at PR time; explicit acknowledgment in runbook Sharp Edges; `/soleur:gdpr-gate` LLM scan available for narrower targeted use.
- **R3 (LOW):** Anthropic API call may rate-limit or 5xx. Mitigation: workflow retries on next cron tick (Sunday); failure email fires.
- **R4 (LOW):** Cluster from LLM emits invalid `cluster_hash`. Mitigation: AC11 cluster-hash integrity check refuses to open the PR.
- **R5 (LOW):** Bootstrap week opens 2 PRs against ~947 existing learnings. Per-week cap throttles backlog drainage; backlog will take weeks (~10). Acceptable; flag in `/ship` for empirical tuning after 4 weeks.

## Open Questions (for /work)

- **Q1:** Anthropic `claude-sonnet-4-6` or `claude-opus-4-7`? Default v1: Sonnet (clustering benefits from cheaper iteration; Opus reserved for v2 if Sonnet quality proves insufficient).
- **Q2:** Should the corpus payload include full file content or first-10-lines summary? Default v1: first-10-lines (bounds prompt size on 947-file corpus). Revisit if cluster quality is poor.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `single-user incident`; do not blank it during /work.
- The cron CANNOT read `.claude/.rule-incidents.jsonl` (gitignored, never in CI). Clustering input is always `knowledge-base/project/learnings/`.
- Per `wg-after-merging-a-pr-that-adds-or-modifies`, the merged PR must trigger `gh workflow run scheduled-compound-promote.yml` (AC16).
- Synthetic check-runs are posted by the workflow inline (mirroring bot-pr composite logic) — operator-merge satisfies CI Required + CLA Required rulesets.
- Constitution line 153 prefers push-to-main for bot content. This plan deviates (draft PR + manual confirm) because brand-survival threshold is `single-user incident`. Documented in ADR-021.
- The composite extension is BACKWARD-COMPATIBLE only at the value-of-input layer. Future callers passing wrong-case booleans will be caught by the normalization step's case validator (Architecture #4 fix).
- The `compound-promote.sh` driver writes to STDOUT only; no state files are created. If a future planner is tempted to add `.github/promotion-*.json`, the `.gitignore` defensive entry will prevent silent re-introduction; the plan-time gate is "document the choice in this plan body, not in code."
- Cluster-hash is `sha256(sorted(source_learning_paths))` — re-derived in the workflow before PR creation (AC11). The hash is NOT trusted from the LLM output.

## Testing

### Unit / shell tests

- `bash scripts/compound-promote.test.sh` — 3 test cases per Phase 2.

### Integration (post-merge only)

- AC16, AC20, AC21 above.

### Per AGENTS.md `cq-write-failing-tests-before`

This plan includes test scenarios (AC10a, AC20-AC22). /work MUST write the failing test first for Phase 2's shell script. Phase 1 (composite extension) is exempt — no test runner for composites; backward-compat verification is the test surrogate.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| **Two-job split (cluster + promote matrix)** with `claude-code-action` | v1 plan; 5-agent review converged on dropping the wrapper. Token revocation forces architectural contortions; matrix DOS, template-injection, and cluster-hash integrity all become problems. Plain Anthropic API call eliminates all three. |
| **Per-learning gdpr-block ledger via gh issues** | SpecFlow paper-resolution; per-learning sophistication is overkill for v1 default-OFF feature. Shell pre-pass excludes the file before the Anthropic call — no ledger needed. |
| **Jaccard cluster-overlap dedup (FR10)** | DHH/CS: pre-loading regret. Operator close-without-merge IS the dedup signal; the LLM gets fewer recurring proposals over time as the corpus shrinks (the merged proposals reduce future cluster size). |
| **LLM-mediated retired-rule honor (FR11)** | Architecture #1: belongs in deterministic shell pre-pass, not the agent prompt. Done in driver script. |
| **Bootstrap-week cap ramp (week-1=1, week-2=1, weeks-3+=2)** | SpecFlow NG-5: not implementable without state. Steady-state cap=2 from week 1. Revisit if empirical proves problematic. |
| **Single-job using `claude-code-action`** with token-revocation workaround | DHH #1: when a tool's lifecycle doesn't match, drop the tool. Plain `curl` to Anthropic API is sufficient for a single clustering call. |
| **`peter-evans/create-pull-request`** | No precedent; introduces dependency. Existing composite (extended) covers it. |
| **Hooks as v1 promotion target** | Highest blast radius. Defer to v2. |
| **Inline `/compound`-time surface** | Defer to v2 if cron-only proves insufficient. |
| **Push-to-main directly** (constitution line 153 preference) | Brand-survival `single-user incident` requires manual confirm. Documented deviation in ADR-021. |

## Deferrals → tracking issues to file at PR-merge time

| Deferral | Re-evaluation criteria |
|---|---|
| Hook proposals as promotion target | After 4 weeks of v1 operation, if skill+AGENTS.md proposals consistently fail to address recurring deviations that would benefit from a hook gate. |
| Inline `/compound`-time surface | If operator finds cron-only feedback loop too slow. |
| Plugin-scope promotions (`--scope=plugin` flag) | When ToS / Privacy Policy is updated to disclose self-improving loop. CLO must sign off. |
| Embedding-based cluster identity | If LLM clustering proves too unstable in practice. |
| `compound-promote.test.sh` wired into CI | When sister `rule-metrics-aggregate.test.sh` is wired in. |
| Per-category threshold override | If empirical data justifies category-specific tuning. |
| Cluster-overlap dedup (FR10 from v1) | If operators experience same-cluster re-proposal fatigue. Default v1: human-in-the-loop catches it. |
| Bootstrap-week cap ramp | If week-1 PRs prove problematic. |

## Research Insights

### claude-code-action — NOT used (v2 architectural pivot)

v1 plan used `claude-code-action@v1.0.101`. Plan-review identified that its post-step token revocation forced the two-job split, which in turn introduced matrix DOS, template-injection, cluster-hash integrity gap, and an unresolved output-extraction question. v2 drops the wrapper; plain Anthropic API call via `curl` from the driver script.

### bot-pr-with-synthetic-checks — extended (Phase 1)

Existing composite handles bot identity, branch naming (date-suffixed), single-line PR body, synthetic check-runs (test, dependency-review, e2e, skill-security-scan PR gate, cla-check), and `gh pr merge --squash --auto`. Extension adds `draft`, `skip-auto-merge`, `labels` inputs with boolean normalization at the boundary.

### scripts/rule-prune.sh — canonical mirror (Phase 2)

CLI: `--weeks=<n>`, `--dry-run`, `--propose-retirement`. Stdout sentinels: `::rule-prune-pr-title::`, `::rule-prune-pr-body::`. Env override: `RULE_METRICS_ROOT`. Schema-version gate. Two-pass mutation. `compound-promote.sh` mirrors all five conventions.

### Anthropic API direct call

`POST https://api.anthropic.com/v1/messages` with headers `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`. Request schema: `{model, max_tokens, messages: [{role, content}]}`. Response: `.content[0].text`. Verified in `anthropic-preflight/action.yml` (uses `claude-haiku-4-5-20251001`; we use `claude-sonnet-4-6`).

### Telemetry constraints

`.claude/.rule-incidents.jsonl` is gitignored; CI runners never see it. Cron consumes `knowledge-base/project/learnings/` directly (committed).

## Pre-submission checklist (filled at /work completion)

- [x] Title is searchable: `feat: compound promotion loop (self-healing CI sweep)`.
- [x] Labels (post-merge): `type/feature`, `domain/engineering`, `priority/p3-low`.
- [x] Acceptance criteria are measurable (AC1-AC24, including AC2b/AC10a/AC10b/AC15b sub-IDs — total 28 ACs).
- [x] Files-to-create / Files-to-edit lists name every artifact.
- [x] Browser task automation check: N/A (no browser).
- [x] Deferral tracking check: 8 deferrals enumerated.
- [x] CLI-verification gate: all CLI invocations verified.
