---
date: 2026-05-10
issue: 3517
pr: 3521
branch: feat-gosprinto-pin-policy
brainstorm: knowledge-base/project/brainstorms/2026-05-10-gosprinto-pin-policy-brainstorm.md
spec: knowledge-base/project/specs/feat-gosprinto-pin-policy/spec.md
type: feat
classification: governance-and-runtime-gate
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
review_round: 1
review_findings_resolved: P1+P2+P3 inline; 4 scope-outs filed
---

# Plan: Content-Vendoring Pin Policy (gosprinto follow-up, #3517)

## Overview

Land a coordinated set of artifacts that govern any upstream content lifted into the repo under permissive license, with the existing `gosprinto/compliance-skills` lift (5 reference files) as the first registry instance:

1. **Policy doc** at `knowledge-base/engineering/policies/content-vendoring.md` (general; gosprinto is row 1).
2. **Drift workflow** at `.github/workflows/scheduled-content-vendor-drift.yml` (weekly cron + severity-gated auto-PR via inline `git merge-file --diff3`).
3. **Pre-commit gate** as a new `vendor-pin-integrity` lefthook stanza (NOTICE blob SHA vs actual file SHA; prevents silent local edits).
4. **Runtime staleness check** in `gdpr-gate.sh` (≥30d **stdout** banner, ≥90d POSTURE_FAIL stdout line).
5. **Operator runbook** at `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md` for the conflict-marker + manual-review path.

Why: the gdpr-gate skill (PR #3501) lifted 5 reference files at pin `7b58d68` with no policy for what happens when upstream pushes a security-relevant update. Stale rules ship as authoritative narrative claims via the gate's weave-don't-append output → operator merges a regulated-data PR on a false-clean signal → single-user incident. See brainstorm for full design rationale.

## Research Reconciliation — Spec vs. Codebase

| # | Spec / brainstorm claim | Codebase reality | Plan response |
|---|---|---|---|
| 1 | "PR is co-labeled `compliance/critical`" (AC8) | Label does NOT exist (`gh label list` confirmed; `vendor/*` labels also missing) | Phase 0 + workflow `Ensure labels exist` step creates `compliance/critical`, `vendor/pin-drift`, `vendor/license-changed`, `vendor/upstream-archived`, `vendor/upstream-rollback`, `vendor/cron-failure`. Precedent: `scheduled-skill-freshness.yml` |
| 2 | FR6: gate "writes a row to compliance-posture.md" at ≥90d | `compliance-posture.md` lines 39-50 contract: gate NEVER writes there directly; operator-acknowledged write only | **Corrected:** at ≥90d gate emits `POSTURE_FAIL: ...` to **stdout** AND exits 0. Drift workflow opens a `compliance/critical` issue. Operator appends row + commits per existing operator-ack contract |
| 3 | Spec FR3: cron `0 9 * * MON` (top-of-hour, peak cluster) | GH Actions warns about top-of-hour drops; `scheduled-skill-freshness.yml` uses `0 2 1 * *` to dodge clusters | Adjusted to `'17 11 * * MON'` (Monday 11:17 UTC, off-peak / off-cluster). Workflow header documents the choice |
| 4 | FR5: lefthook glob "any registry-listed lifted file path" | lefthook gobwas glob `**` semantics differ from shell (learning `2026-03-21-lefthook-gobwas-glob-double-star.md`); sibling `gdpr-gate-advisory` enumerates paths in array form | Path-array form, enumerated explicitly; integrity script reads NOTICE for canonical SHAs. AC asserts lefthook glob ⊇ NOTICE `lifted-files[].path` (parity test resolves the dual-source-of-truth concern) |
| 5 | Repo-research suggested `bot-pr-with-synthetic-checks` composite | Verified at `.github/actions/bot-pr-with-synthetic-checks/action.yml`; inputs: `add-paths`, `branch-prefix`, `commit-message`, `pr-title-prefix`, `pr-body`, `change-summary`, `gh-token` | Workflow uses this composite; Phase 2.1 step 5 enumerates each input with the value passed |
| 6 | TR7: bash unit tests | No `bats` installed; sibling tests use `.test.sh` (`auto-close-scanner.test.sh`) and `.test.ts` (`gdpr-gate.test.ts`) | Bash scripts use `.test.sh`; runtime banner test extends `gdpr-gate.test.ts` shape via vitest mock |
| 7 | Spec assumed `source notice-frontmatter.sh` from `gdpr-gate.sh` | `gdpr-gate.sh:18` sets `set -euo pipefail`; sourced parser failures abort the gate (advisory-contract violation) | **Corrected:** parser invoked via subshell exec (`days_stale=$(bash notice-frontmatter.sh days-stale 2>/dev/null \|\| echo 999)`). Parser deletion / parse failure / future date all resolve to `days_stale=999` → banner fires → gate exits 0 |
| 8 | Spec FR6: banner "prepended to all output" (stderr by default in existing gate) | Agent runtimes (Claude Code skill harness, MCP servers) frequently surface only stdout; stderr swallowed | **Corrected:** banner → **stdout** (not stderr). AC asserts captured stdout contains banner when staleness mocked. Single most load-bearing fix from review |

## User-Brand Impact

Carried forward from brainstorm `## User-Brand Impact` block.

- **If this lands broken, the user experiences:** a `gdpr-gate` invocation that emits authoritative narrative claims ("no Art. 9 fields detected on this diff") based on stale rules. The operator merges a regulated-data PR on a false-clean signal.
- **If this leaks, the user's data is exposed via:** an upstream-recognized PII category that the operator's downstream user gets matched against — leakage vector is the unflagged code path the operator merged. Specifically: a regulated-PII row written, served, or logged by the operator's product because gdpr-gate's stale rule set didn't flag it.
- **Brand-survival threshold:** `single-user incident`. A 0-finding output on a regulated PR where upstream-current would flag 1 IS a single-user incident; the gate's weave-don't-append shape makes the staleness signal load-bearing for operator trust.
- **Failure-mode coverage table** (per architecture-strategist review):

| Failure mode | Defense layer | Caught by |
|---|---|---|
| Upstream pushes security-relevant patch | Cron + severity classifier | FR3 + FR4 (auto-PR within 14d SLA) |
| Cron workflow disabled / GH Actions outage | Runtime staleness banner | FR6 (≥30d stdout banner) |
| `gh api` 5xx / rate-limit during cron | `if: failure()` issue | FR3 (`vendor/cron-failure` tracking) |
| NOTICE frontmatter corruption / parser deletion | Subshell exec + fallback | TR2 (treat as stale immediately, days_stale=999) |
| `last-verified` future-dated | Parser validation | TR2 (treat as malformed → stale immediately) |
| Upstream rollback (HEAD older than pin) | Ancestor check in classifier | FR3 (label `vendor/upstream-rollback`, no auto-PR) |
| Upstream rename → 404 | `/repos/<o>/<r>` disambiguation | FR3 (label `vendor/upstream-archived` or `-renamed`) |
| Silent local edit to lifted file | Pre-commit lefthook integrity gate | FR5 (`git hash-object --no-filters` mismatch) |
| Lefthook glob diverges from NOTICE registry | Parity assertion test | AC5b |

- **Sign-off:** `requires_cpo_signoff: true`. CPO has reviewed the brainstorm (Phase 0.5 carry-forward) and the threshold/staleness-gate design. Plan-time CPO sign-off treated as covered by brainstorm carry-forward; `user-impact-reviewer` runs at PR-review time.

## Files to Create

| Path | Purpose | FR/TR |
|---|---|---|
| `knowledge-base/engineering/policies/content-vendoring.md` | General content-vendoring policy + registry table (gosprinto = row 1) | FR1 |
| `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md` | Operator runbook: synthetic-drift test + conflict-marker resolution + POSTURE_FAIL response | Kieran P1.3 / SpecFlow P2.6 |
| `.github/workflows/scheduled-content-vendor-drift.yml` | Weekly drift cron + severity-gated auto-PR (3-way merge inline) | FR3, FR4, TR3 |
| `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh` | Pure-bash NOTICE frontmatter parser; subcommands: `days-stale`, `field <name>`, `lifted-files`. Future date → "stale immediately" | TR2 |
| `plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh` | Lefthook target — compares lifted-file blob SHAs against NOTICE | FR5, TR1 |
| `plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh` | Severity classifier regex over upstream diff; exit codes 10/11/12/13/14/15/16 | FR3 |
| `plugins/soleur/test/notice-frontmatter.test.sh` | Bash unit tests; covers happy / missing-frontmatter / malformed-YAML / future-date / p95 <100ms timing | TR2, TR7 |
| `plugins/soleur/test/vendor-pin-integrity.test.sh` | Bash unit tests; covers SHA mismatch + lefthook-glob⊇NOTICE-paths parity | TR7, AC5b |
| `plugins/soleur/test/vendor-drift-classify.test.sh` | Bash unit tests for severity classifier (all 7 exit codes) | TR7 |
| `plugins/soleur/test/vendor-drift-workflow.test.sh` | Integration test (`SKIP_PR_CREATE=1` dry-run) against synthetic-diff fixtures | TR7 |
| `plugins/soleur/test/fixtures/vendor-drift/upstream-fields-art9-add.diff` | Synthetic diff: adds Art. 9 row to `fields.md` (security-relevant; exit 10) | TR7 |
| `plugins/soleur/test/fixtures/vendor-drift/upstream-prose-typo.diff` | Synthetic diff: prose-only edit (batched; exit 13) | TR7 |
| `plugins/soleur/test/fixtures/vendor-drift/upstream-rollback.diff` | Synthetic case: HEAD is ancestor of pinned SHA (exit 15) | SpecFlow P1.2 |
| `plugins/soleur/test/fixtures/vendor-drift/notice-future-dated.frontmatter` | NOTICE fixture with `last-verified: 2099-01-01` (parser must treat as stale) | SpecFlow P1.5 |

## Files to Edit

| Path | Change | FR/TR |
|---|---|---|
| `plugins/soleur/skills/gdpr-gate/NOTICE` | Add YAML frontmatter (`upstream`, `pinned-commit`, `last-verified`, `registry`, `lifted-files`) above existing markdown body | FR2 |
| `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` | Add ~10-line runtime staleness check (subshell-exec parser; stdout banner ≥30d; stdout POSTURE_FAIL ≥90d; gate exits 0 always) | FR6, TR2, TR6 |
| `plugins/soleur/skills/gdpr-gate/SKILL.md` | Document runtime staleness banner contract; cross-link to policy doc | Kieran P2.7 |
| `plugins/soleur/test/gdpr-gate.test.ts` | Extend with vitest mock asserting captured stdout contains banner when NOTICE date mocked stale | TR7 |
| `lefthook.yml` | Add `vendor-pin-integrity` stanza (sibling to `gdpr-gate-advisory` at lines 94-119) | FR5 |
| `knowledge-base/legal/compliance-posture.md` | Add "Vendored Code Provenance" section (sibling to "Vendor DPA Status"); add gosprinto entry with cross-link to registry | FR7 |

## Implementation Phases

### Phase 0: Setup

**0.1** Operator creates 6 GH labels (separate-terminal — labels carry no secrets but operator runs them per AGENTS.md `hr-never-paste-secrets-via-bang-prefix` discipline). The workflow's `Ensure labels exist` step idempotently re-creates them on first run, so this is belt-and-suspenders for pre-merge testing:

```bash
gh label create compliance/critical --description "Compliance Critical (Art. 9, missing lawful basis, etc.)" --color "B60205" 2>/dev/null || true
gh label create vendor/pin-drift --description "Upstream content drift detected on pinned bundle" --color "FBCA04" 2>/dev/null || true
gh label create vendor/license-changed --description "Upstream license file modified — escalate" --color "B60205" 2>/dev/null || true
gh label create vendor/upstream-archived --description "Upstream repo archived — fork-or-drop ADR required" --color "B60205" 2>/dev/null || true
gh label create vendor/upstream-rollback --description "Upstream HEAD is an ancestor of pinned SHA — needs human review" --color "FBCA04" 2>/dev/null || true
gh label create vendor/cron-failure --description "Vendor-drift workflow failed (gh api 5xx, rate-limit, etc.)" --color "B60205" 2>/dev/null || true
```

**0.2** Add YAML frontmatter to `plugins/soleur/skills/gdpr-gate/NOTICE` above the existing markdown body. Frontmatter:

```yaml
---
upstream: github.com/goSprinto/compliance-skills
pinned-commit: 7b58d68461cb1fc033a063e34cc9de63d0b4144b
last-verified: 2026-05-10
registry: knowledge-base/engineering/policies/content-vendoring.md
lifted-files:
  - path: references/fields.md
    upstream-path: pii-detector/patterns/fields.md
    blob-sha: c1bb748fe00a53b283efe66ec937fa39437d2efc
    status: active-eu-extended
  - path: references/leakage-vectors.md
    upstream-path: pii-detector/rules/leakage-vectors.md
    blob-sha: 15a46e529e789930149f4b9bce875bfe5c53e478
    status: active-verbatim
  - path: references/layers/api-layer.md
    upstream-path: pii-detector/layers/api-layer.md
    blob-sha: 9d3202175c1d0225f60a912c489dbdacf4df491c
    status: active-verbatim
  - path: references/layers/data-in-transit.md
    upstream-path: pii-detector/layers/data-in-transit.md
    blob-sha: 6c9eeabf17d1f0ed5660f5eb54d91587c81214ef
    status: active-eu-extended
  - path: references/layers/data-lifecycle.md
    upstream-path: pii-detector/layers/data-lifecycle.md
    blob-sha: a073ef24a0527c2c3a6d738b65ea3ef9d6194abe
    status: active-soleur-rewritten
---
```

Body sentence added: "The frontmatter above is the canonical machine-readable form; the table below is the human-readable form. Drift between them is a bug."

### Phase 1: Helper scripts (TDD)

**1.1** `notice-frontmatter.sh` — pure-bash YAML parser. Subcommands:

- `bash notice-frontmatter.sh field <name>` → prints field value (`upstream`, `pinned-commit`, `last-verified`, `registry`).
- `bash notice-frontmatter.sh days-stale` → prints integer days since `last-verified` (today - last-verified). **Future-dated → prints `999`** (treat as stale immediately, SpecFlow P1.5). Malformed YAML / missing frontmatter → prints `999`. Returns exit 0 always.
- `bash notice-frontmatter.sh lifted-files` → prints one `<path>:<blob-sha>` per line.

`set -euo pipefail` permitted internally; subcommand wrappers catch failures. Target <100ms p95 (TR2; widened from <50ms after PR #3521 added strict-ISO + UTC-anchor on `last-verified`). Test: `notice-frontmatter.test.sh` covers happy / missing-frontmatter / malformed-YAML / future-date / `time` × 100 invocations p95 <100ms.

**1.2** `vendor-pin-integrity.sh` — invoked by lefthook. Per file:

```bash
expected=$(bash notice-frontmatter.sh lifted-files | grep -F "<path>:" | cut -d: -f2)
actual=$(git hash-object --no-filters "<path>")
[[ "$expected" == "$actual" ]] || { echo "BLOB SHA mismatch on <path>"; exit 1; }
```

`--no-filters` is load-bearing per TR1: skips gitattributes line-ending conversion. Test: `vendor-pin-integrity.test.sh` includes (a) mismatched SHA fixture (fails), (b) **parity assertion** that the script's NOTICE-derived path list ⊆ `lefthook.yml` `vendor-pin-integrity` stanza glob (Architecture P1).

**1.3** `vendor-drift-classify.sh` — accepts unified-diff on stdin and (for rollback case) the upstream-old-sha + upstream-new-sha pair as args. Exit codes:

| Exit | Class | Label set |
|---|---|---|
| 0 | no-op (whitespace only) | none |
| 10 | security-relevant content drift | `vendor/pin-drift` + `compliance/critical` |
| 11 | LICENSE diff | `vendor/license-changed` + `compliance/critical` |
| 12 | upstream archived | `vendor/upstream-archived` + `compliance/critical` |
| 13 | batched (prose typo, link update) | `vendor/pin-drift` |
| 14 | (reserved) | — |
| 15 | upstream rollback (HEAD is ancestor of pinned SHA) | `vendor/upstream-rollback` + `needs-human-review` |
| 16 | upstream rename (404 on contents API; redirect on /repos/<o>/<r>) | `vendor/upstream-archived` (treated as same operator action: human-review) |

Security-relevant regex (exit 10):
```bash
- ^\+.*\|.*\|.*$              # added row in any markdown table
- ^\+.*\[CRITICAL\]
- ^\+.*\bMUST\b
- ^\+.*Art\. [0-9]+
- ^\+.*§\s*[0-9]+
- ^\+\+\+ b/.*/layers/         # new file under references/layers/
```

Rollback detection (exit 15): `git merge-base --is-ancestor <upstream-new-sha> <pinned-sha>` returns 0 → upstream HEAD is older than our pin → rollback.

Test: `vendor-drift-classify.test.sh` feeds each fixture diff + sha pair to the script and asserts exit code.

### Phase 2: Drift workflow

**2.1** `.github/workflows/scheduled-content-vendor-drift.yml`. Header documents the cron rationale + the trap dossier (precedent: `scheduled-github-app-drift-guard.yml`). Shape:

- `on.schedule.cron: '17 11 * * MON'` (off-peak, off-cluster).
- `on.workflow_dispatch:` for manual test.
- `concurrency: { group: schedule-content-vendor-drift, cancel-in-progress: false }`.
- `permissions: { contents: write, issues: write, pull-requests: write }` — load-bearing roles documented inline:
  - `contents: write` — push the re-vendor branch.
  - `pull-requests: write` — create the PR object + apply labels.
  - `issues: write` — open `vendor/cron-failure` / `vendor/upstream-rollback` / `vendor/upstream-archived` tracking issues.
- `actions/checkout` pinned to 40-char SHA with `# v4.3.1` comment (per learning `2026-02-27-github-actions-sha-pinning-workflow.md`).
- `Ensure labels exist` step recreates the 6 labels idempotently.
- `CAP_PER_RUN: '3'` — idempotent issue search by title prevents storm; carry-forward via next-week pickup is acceptable (overflow handling deliberate, see Risks).
- Steps:
  1. Read `NOTICE` frontmatter via `notice-frontmatter.sh`.
  2. Per lifted file: try `gh api repos/goSprinto/compliance-skills/contents/<upstream-path>?ref=main --jq .sha`. On HTTP 404, `gh api repos/goSprinto/compliance-skills` to disambiguate {renamed via `full_name` redirect, archived via `.archived: true`, repo-deleted}. Label per disambiguation; open issue.
  3. Compare returned blob SHA to NOTICE pinned SHA. On mismatch, fetch upstream-old (NOTICE pin) + upstream-new (HEAD) blobs.
  4. Run `vendor-drift-classify.sh` with the diff + sha pair. Branch on exit code.
  5. If 10/11 → 3-way merge inline:
     ```bash
     for path in $(notice-frontmatter.sh lifted-files | cut -d: -f1); do
       git merge-file --diff3 "<lifted-path>" "<upstream-old-tmp>" "<upstream-new-tmp>"
     done
     ```
     Conflict gate: `grep -l '<<<<<<<' <lifted-paths>` → if any matches, append `needs-human-review` label and short-circuit auto-merge.
  6. Bump NOTICE `last-verified` to today's date AND bump matching `blob-sha` entries.
  7. Use `bot-pr-with-synthetic-checks` composite to push branch + open PR. Inputs:
     - `add-paths`: changed files (lifted bytes + NOTICE frontmatter).
     - `branch-prefix`: `ci/vendor-drift-`.
     - `commit-message`: `"chore(vendor-drift): re-vendor gosprinto/compliance-skills @ <new-sha>"`.
     - `pr-title-prefix`: `"chore(vendor-drift): "`.
     - `pr-body`: link to runbook + classifier exit code + per-file diff summary.
     - `change-summary`: `"Re-vendor on upstream drift detection — see runbook"`.
     - `gh-token`: `${{ github.token }}`.
  8. Apply labels per classification (built into PR body header for auditability).
  9. **`if: failure()` step** opens a `vendor/cron-failure` tracking issue (idempotent search; precedent: `scheduled-skill-freshness.yml` notify-ops-email pattern). SpecFlow P1.4.

### Phase 3: Lefthook integrity gate

**3.1** Add `vendor-pin-integrity` stanza directly after `gdpr-gate-advisory` (line 119 of `lefthook.yml`). Glob is path-array form per learning `2026-03-21-lefthook-gobwas-glob-double-star.md`:

```yaml
vendor-pin-integrity:
  priority: 6
  glob:
    - "plugins/soleur/skills/gdpr-gate/references/fields.md"
    - "plugins/soleur/skills/gdpr-gate/references/leakage-vectors.md"
    - "plugins/soleur/skills/gdpr-gate/references/layers/api-layer.md"
    - "plugins/soleur/skills/gdpr-gate/references/layers/data-in-transit.md"
    - "plugins/soleur/skills/gdpr-gate/references/layers/data-lifecycle.md"
    - "plugins/soleur/skills/gdpr-gate/NOTICE"
  run: bash plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh {staged_files}
```

The integrity script reads NOTICE for the canonical SHA list — if a staged file is in the lefthook glob but not in NOTICE, the script flags it (silent local addition without registry update).

### Phase 4: Runtime staleness check in gdpr-gate.sh

**4.1** Insert after the `INCIDENTS_LIB` source block, before `CANONICAL_REGEX`:

```bash
# Runtime staleness check (FR6 / TR2 / TR6).
# Sub-value: time-since-last-verified (load-bearing when cron pipeline silently broken — workflow disabled, GH outage, PR queued).
# Distinct from FR3's upstream-drift-detected signal which fires only when the cron successfully runs.
# Banner emits to STDOUT (not stderr) — agent runtimes frequently swallow stderr.
NOTICE_PARSER="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh"
days_stale=$(bash "$NOTICE_PARSER" days-stale 2>/dev/null || echo 999)
last_verified=$(bash "$NOTICE_PARSER" field last-verified 2>/dev/null || echo "unknown")
if (( days_stale > 30 )); then
  printf '⚠ gdpr-gate rules %s days stale (last verified %s) — output is advisory only and may miss recently-patched detection rules. Refresh: see knowledge-base/engineering/policies/content-vendoring.md\n' "$days_stale" "$last_verified"
  emit_incident gdpr-gate-staleness warn "${days_stale}-days-stale"
fi
if (( days_stale > 90 )); then
  printf 'POSTURE_FAIL: gdpr-gate rules >90 days stale — compliance/critical posture row required. Operator chain: knowledge-base/engineering/policies/content-vendoring.md#posture-fail-operator-chain\n'
  emit_incident gdpr-gate-staleness deny "${days_stale}-days-stale-posture-fail"
fi
```

10 lines. Subshell exec (not `source`) — parser failure / deletion / future-date all resolve to `days_stale=999` → banner fires → gate still exits 0 (advisory contract preserved). No env-var idempotency dance — same-process double-call IS two banners by intent (operator should see staleness on every invocation, not once per process). Cross-invocation idempotency tested via `vendor-drift-workflow.test.sh`.

### Phase 5: Compliance-posture + policy doc (merged)

**5.1** Add "Vendored Code Provenance" section to `knowledge-base/legal/compliance-posture.md`, between "Vendor DPA Status" and "Active Compliance Items":

```markdown
## Vendored Code Provenance

Source: `knowledge-base/engineering/policies/content-vendoring.md`

| Upstream | License | Pinned Commit | Lifted Files | Last Verified | Status |
|---|---|---|---|---|---|
| github.com/goSprinto/compliance-skills | MIT | `7b58d68` | 5 (gdpr-gate references) | 2026-05-10 | active |
```

**5.2** Write `knowledge-base/engineering/policies/content-vendoring.md` with sections:

- **Scope:** what the policy governs (any content lifted under permissive license; not service-vendor DPAs).
- **NOTICE schema:** YAML frontmatter spec (mirrors Phase 0.2).
- **Lifting procedure:** when to lift / when to clean-room rebuild / how to record attribution headers.
- **Drift detection:** how the cron + severity classifier work; how the lefthook gate prevents silent edits.
- **Severity classification:** the 7 exit codes from `vendor-drift-classify.sh`.
- **Re-vendor procedure:** inline `git merge-file --diff3` invocation; conflict-marker CI gate; NOTICE update obligations (SHA + last-verified bumped at PR-creation time, not commit time).
- **Pre-vendor diff scan:** **DEFERRED** — see scope-out issue. Future re-vendor PR will introduce the scan as a workflow step before this policy section is filled in.
- **Runtime staleness contract:** ≥30d stdout banner / ≥90d POSTURE_FAIL. Stable, not relaxable without ADR.
- **POSTURE_FAIL operator chain** (SpecFlow P2.7): when `gdpr-gate.sh` emits POSTURE_FAIL during a regulated PR, the operator: (1) does NOT pause the current PR (gate is advisory, exit 0), (2) opens a tracking `compliance/critical` issue, (3) appends row to `compliance-posture.md` Active Compliance Items, (4) commits with `compliance: register vendor-pin-staleness for #<issue>`, (5) opens or pings the in-flight vendor-drift PR. The current regulated PR can ship; the staleness-driven follow-up is a separate cycle.
- **Local-edit hygiene:** `git hash-object --no-filters` is canonical. Use Linux/macOS/WSL for local commits to lifted files; Windows autocrlf may produce non-byte-identical SHA even with `--no-filters` once a file has been EOL-converted on checkout (SpecFlow P3.13 — flag, not block).
- **Registry table:** machine-readable summary of every lifted bundle. First row = gosprinto.

### Phase 6: Operator runbook

**6.1** `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md`. Sections:

- **Synthetic-drift test** (post-merge AC): step-by-step using the committed fixtures. Operator creates a feature branch, mutates NOTICE pinned-commit to a deliberately-wrong SHA, runs `gh workflow run scheduled-content-vendor-drift.yml --ref <branch>`, asserts (a) PR opened with expected labels, (b) `last-verified` bumped on auto-PR.
- **Conflict-marker resolution** (`needs-human-review` label): operator reviews 3-way merge output; manually resolves; commits + bumps NOTICE; merges PR.
- **Rollback case** (`vendor/upstream-rollback`): operator decides whether upstream rollback is intentional (and we should follow) or a force-push accident (and we should freeze + ping upstream). Document the decision tree.
- **Rename case** (`vendor/upstream-archived` triggered by 404 + `full_name` redirect): operator updates NOTICE `upstream` field to the new repo path, re-runs cron.
- **Archived case**: file fork-or-drop ADR via `/soleur:architecture create`.
- **Cron failure (`vendor/cron-failure` issue)**: operator inspects workflow run; if transient (rate-limit), waits for next cron; if persistent, escalates.
- **POSTURE_FAIL operator chain**: cross-link to policy doc Section 8.

Precedent: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md` (cited in AGENTS.md `hr-ssh-diagnosis-verify-firewall`).

### Phase 7: Tests

See Files-to-Create test entries. Naming + framework verified: `.test.sh` (bash, sibling: `auto-close-scanner.test.sh`); `gdpr-gate.test.ts` extension via vitest (existing).

## Acceptance Criteria

### Pre-merge (PR)

- AC1. `knowledge-base/engineering/policies/content-vendoring.md` exists, has 9 sections (Scope, NOTICE schema, Lifting procedure, Drift detection, Severity classification, Re-vendor procedure, Runtime staleness contract, POSTURE_FAIL operator chain, Registry), and lists gosprinto with all 5 lifted files.
- AC2. `plugins/soleur/skills/gdpr-gate/NOTICE` has YAML frontmatter parseable by `notice-frontmatter.sh`. `last-verified: 2026-05-10`. `lifted-files` enumerates all 5 entries with matching blob SHAs.
- AC3. `notice-frontmatter.sh`, `vendor-pin-integrity.sh`, `vendor-drift-classify.sh` exist with header documenting subcommands + exit codes. `set -euo pipefail` is internal-only — subcommand wrappers catch failures so callers (notably `gdpr-gate.sh`) can subshell-exec safely.
- AC4. `.github/workflows/scheduled-content-vendor-drift.yml` exists. Cron `'17 11 * * MON'`. `permissions:` block is documented inline naming each role (contents/issues/pull-requests). `actions/checkout` pinned to 40-char SHA. `Ensure labels exist` step creates the 6 labels. `bot-pr-with-synthetic-checks` composite invoked with all 7 documented inputs.
- AC5a. `lefthook.yml` has `vendor-pin-integrity` stanza placed after `gdpr-gate-advisory`. Glob is path-array form. Modifying any byte of `references/leakage-vectors.md` without bumping NOTICE SHA fails `git commit` with the integrity script's stderr message.
- AC5b. **Lefthook glob ⊇ NOTICE `lifted-files[].path` parity test** (Architecture P1) — `vendor-pin-integrity.test.sh` asserts every `lifted-files[].path` in NOTICE has a matching glob entry in `lefthook.yml`. Failure means a 6th file was added to NOTICE without lefthook update.
- AC6a. Running `gdpr-gate.sh` with NOTICE `last-verified` mocked to 35 days ago prepends the banner to **stdout** exactly once per invocation. (SpecFlow P1.1 — load-bearing fix.)
- AC6b. With NOTICE `last-verified` mocked to 95 days ago, the gate ALSO emits the `POSTURE_FAIL` line to stdout. In both cases gate exits 0.
- AC6c. With NOTICE deleted / parser deleted / `last-verified` future-dated → `days_stale=999`, banner fires, gate exits 0. (SpecFlow P1.5, Architecture P3.5.)
- AC6d. **Stdout-banner test in `gdpr-gate.test.ts`** captures stdout (NOT stderr), asserts banner string present. (SpecFlow P1.1.)
- AC7. `compliance-posture.md` has the "Vendored Code Provenance" section with the gosprinto entry; cross-links to/from the policy doc.
- AC8a. All bash tests pass: `bash plugins/soleur/test/notice-frontmatter.test.sh && bash plugins/soleur/test/vendor-pin-integrity.test.sh && bash plugins/soleur/test/vendor-drift-classify.test.sh && bash plugins/soleur/test/vendor-drift-workflow.test.sh`.
- AC8b. TS tests pass: `cd plugins/soleur && bun test test/gdpr-gate.test.ts`.
- AC8c. **`notice-frontmatter.test.sh` p95 timing assertion** — 100 invocations of `bash notice-frontmatter.sh days-stale`; p95 < 100ms (TR2; widened from <50ms after PR #3521 added strict-ISO + UTC-anchor on `last-verified`).
- AC9. PR body includes `## Changelog` section. Plan-review (5 reviewers) ran and findings resolved (review_round=1, all P1+P2+P3 inline; 4 scope-outs filed). `gdpr-gate-advisory` lefthook hook does NOT fire on these edits (verified — globs at `lefthook.yml:96-118` don't match `plugins/soleur/skills/gdpr-gate/scripts/**`).
- AC10. PR is co-labeled `compliance/critical` (single-user incident threshold; `user-impact-reviewer` runs at PR-review time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block).
- AC11. **PR body uses `Ref #3517` everywhere except the single intentional `Closes #3517` line** (Kieran P1.2 — guards against `wg-use-closes-n-in-pr-body-not-title-to`). Acceptance checkbox phrases that contain `close|fix|resolve` MUST be reworded (e.g., `- [ ] confirm drift workflow runs` rather than `- [ ] resolve drift workflow`).
- AC12. **First-cron poll** (per AGENTS.md `wg-after-merging-a-pr-that-adds-or-modifies`) — operator runs `gh workflow run scheduled-content-vendor-drift.yml --ref main` post-merge AND polls `gh run view <id> --json status,conclusion` until SUCCESS before session-end. Documented in runbook.

### Post-merge (operator)

- AC13. Operator runs synthetic-drift test per runbook §1: creates feature branch with NOTICE pinned-commit mutated to a deliberately-wrong SHA, dispatches workflow, asserts PR opened with `vendor/pin-drift` label and `last-verified` bumped on the auto-PR.
- AC14. Operator confirms the 6 GH labels exist (workflow's `Ensure labels exist` step re-creates idempotently on first cron run; pre-merge Phase 0.1 created them in advance).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `git hash-object` newline normalization mismatch | Use `git hash-object --no-filters` everywhere (TR1). `vendor-pin-integrity.test.sh` includes a fixture with mismatched newlines. Policy doc warns Windows operators (SpecFlow P3.13). |
| GH Actions cron is best-effort | Off-peak time `'17 11 * * MON'`; runtime banner is the load-bearing user-protection layer when cron silently fails (FR6). `if: failure()` step opens `vendor/cron-failure` issue (FR3 step 9). |
| 3-way merge produces conflict markers | `grep -l '<<<<<<<'` gate fails the auto-PR; reviewer must resolve before merge; `needs-human-review` label makes it explicit. Runbook §2 documents resolution. |
| Upstream rollback (HEAD older than pin) | Classifier exit 15; auto-PR suppressed; `vendor/upstream-rollback,needs-human-review` label; operator decision per runbook §3. |
| Upstream rename / 404 ambiguity | `gh api repos/<o>/<r>` disambiguates rename / archived / deleted; classifier exit 16 routes to operator. |
| NOTICE frontmatter corruption / parser deletion | Subshell exec returns `days_stale=999` → banner fires; gate exits 0. Test fixture covers parser-missing case. |
| `last-verified` future-dated | Parser treats future date as malformed → 999. Fixture + test (SpecFlow P1.5). |
| Pre-vendor diff scan deferred | First re-vendor PR will introduce the scan as a workflow step. Until then, the conflict-marker grep + human-review-on-flag-from-classifier is the manual fallback. Issue tracks. |
| `compliance/critical` label semantic dilution (regulated-data PR + vendor drift + posture-fail all share the label) | Triage uses PR title/body markers; future scope-out may introduce sub-labels. Tracked in scope-out issue. |
| `bot-pr-with-synthetic-checks` composite assumes specific repo settings | Composite verified in-tree at `.github/actions/bot-pr-with-synthetic-checks/action.yml`; shape verified by `scheduled-skill-freshness.yml` precedent. Cron-failure step catches any composite-level failure. |

## Test Strategy

- **Unit (bash):** every helper script gets a `.test.sh` sibling. Each test exercises (a) happy path, (b) malformed input, (c) edge case (empty diff, missing frontmatter, future date).
- **Integration (bash):** `vendor-drift-workflow.test.sh` runs the workflow body against fixture diffs + NOTICE in `SKIP_PR_CREATE=1` dry-run mode; asserts label set, branch name, classifier exit code, conflict-marker handling.
- **TS extension:** `gdpr-gate.test.ts` extended with vitest case mocking `notice-frontmatter.sh` output (35d stale, 95d stale, future-dated, parser-deleted) and asserting captured **stdout** contains banner. (SpecFlow P1.1 / AC6d.)
- **Timing assertion:** AC8c — `time` × 100 invocations, p95 < 100ms.
- **No new test framework** — `bats` not installed; `.test.sh` is project convention (verified `ls plugins/soleur/test/`).
- **Fixture seeding:** all fixtures static synthetic data committed to `plugins/soleur/test/fixtures/vendor-drift/`. No external service deps — `gh api` mocked via fixture files.

## Open Code-Review Overlap

3 open code-review issues touch `lefthook.yml` but none touch our specific stanza, file paths, or scripts:

- **#3321 / #3322 / #3323** — Defer; unrelated.

No other plan-file overlap. Verified via `gh issue list --label code-review --state open` + `jq` containment check.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO).

### Engineering (CTO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** Hybrid, weekly cadence, ~80% automatable. Workflow modeled on `scheduled-skill-freshness.yml`; `git merge-file --diff3` for 3-way merge inline; conflict-marker CI gate; severity classifier as regex over upstream diff. Worth an ADR (deferred — see scope-outs).

### Legal (CLO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** MIT requires only copyright + permission. Silent incorporation without bumping NOTICE SHA is the actual breach risk. Pre-vendor diff scan is load-bearing — but per Simplicity review, deferred to first real re-vendor PR (zero current vendor surface in lifted bytes). Stale advisory output while holding out as "GDPR gate" = GDPR Art. 5(2) accountability breach — runtime staleness banner is the load-bearing protection.

### Product (CPO) — carry-forward from brainstorm

**Status:** reviewed
**Assessment:** Pin-policy doc itself is meta-process; freshness SLO carries the single-user-incident threshold. Weave-don't-append output makes 0-finding-on-stale-rules a single-user incident. Runtime staleness gate is the load-bearing user protection independent of the cron. Plan-time CPO sign-off treated as covered by brainstorm carry-forward per Phase 2.6 sign-off lifecycle staging.

### Product/UX Gate

**Tier:** none

No new user-facing pages, no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`. Operator-visible surfaces are CLI stdout (banner) and a GH issue body — neither qualifies as UI per the BLOCKING-tier mechanical criteria. The stdout banner is read by humans + agents, but it's not a UI component.

## Sharp Edges

- `## User-Brand Impact` section MUST stay populated; deepen-plan Phase 4.6 will halt on empty/TBD/placeholder.
- `compliance-posture.md` Active Compliance Items contract: gate NEVER writes there. POSTURE_FAIL behavior emits stderr-line + lets workflow open the issue; OPERATOR appends the row.
- `git hash-object --no-filters` (NOT `sha256sum`, NOT bare `git hash-object`) — `--no-filters` skips gitattributes line-ending conversion that diverges from upstream blob SHAs. TR1 + Risks row 1.
- Lefthook stanza glob is path-array form (NOT `**`) per learning `2026-03-21-lefthook-gobwas-glob-double-star.md`. Add new lifted file → update BOTH NOTICE `lifted-files` AND lefthook glob. AC5b parity test catches divergence.
- Cron schedule uses `'17 11 * * MON'` (off-peak/off-cluster). Top-of-hour clusters are dropped by GH Actions during peak.
- `last-verified` bumped at PR-creation time within the auto-PR's commit, NOT at human-merge time. The workflow step bumps both `pinned-commit` and `last-verified` in the same commit; merging the PR ratifies the bump.
- Banner emits to **stdout** (not stderr). Agent runtimes commonly swallow stderr; the user-protection thesis depends on visibility. AC6d binds the test.
- `notice-frontmatter.sh` invoked from `gdpr-gate.sh` via subshell exec (`days_stale=$(bash ... \|\| echo 999)`), NOT `source`. Sourcing under `set -euo pipefail` would abort the gate on parser failure (advisory contract violation).
- Same-process double-call to `gdpr-gate.sh` produces TWO banners by design — operator should see staleness on every invocation, not once per process. No env-var idempotency dance.
- This plan modifies `gdpr-gate.sh` itself. The `gdpr-gate-advisory` lefthook hook does NOT match `scripts/` — verified by re-reading `lefthook.yml:96-118`. /work Phase 2 exit invocation of `/soleur:gdpr-gate` is the correct gate point per spec TR9 (recursive but valid invocation against the diff, not the live in-progress edits to the gate itself).
- AC11 binds PR body to `Ref #3517` everywhere except one `Closes #3517` line. Auto-close keyword leakage in checkboxes triggers `wg-use-closes-n-in-pr-body-not-title-to`.
- All 6 labels created at Phase 0.1 (operator action) AND idempotently re-created by the workflow's `Ensure labels exist` step (workflow-time defense-in-depth).

## Scope-Outs (filed as separate issues)

The following items are intentionally not in scope for this PR:

1. **`vendor-diff-scan.sh` deferred** — premature defense given zero current vendor surface in lifted bytes. File scope-out issue triggered by first real re-vendor PR landing.
2. **ADR for "Hybrid drift detection for vendored compliance content"** — defer until second content-vendor lift triggers it; CTO recommendation in brainstorm.
3. **`compliance/critical` label semantic dilution** — label is overloaded across regulated-data PRs, vendor-drift, and posture-fail. Sub-label or required body marker design deferred.
4. **`vendor-pins.sh` subcommand consolidation** — Simplicity review proposed collapsing `notice-frontmatter.sh` + `vendor-pin-integrity.sh` into one file with subcommands. Kept separate in this PR to keep the gate hot-path tight (`gdpr-gate.sh` subshell-execs `notice-frontmatter.sh`); revisit if the helper count grows.
