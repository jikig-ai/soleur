# Tasks: fix-constraints two-stage privileged split (#5814)

Plan: `knowledge-base/project/plans/2026-07-01-feat-fix-constraints-two-stage-privileged-split-plan.md`
Lane: cross-domain · Threshold: single-user incident · Supersedes: PR #5804

## Phase 0 — Preconditions & capability verification
- [ ] 0.1 Re-confirm ADR-074 free + all on-main deps present (anthropic-preflight, extract-api-spend.sh, constraint-gates.sh).
- [ ] 0.2 Verify CodeQL `actions` scanning enabled: `gh api repos/{owner}/{repo}/code-scanning/default-setup` → check `languages` includes `actions`. If absent, enable (or note 0-alerts AC is dashboard-verified).
- [ ] 0.3 Confirm claude-code-action `claude_args` string from held workflow is reused verbatim (no model-id from memory).
- [ ] 0.4 Pin `actions/download-artifact` to the v4 SHA fetched via `gh api repos/actions/download-artifact/git/refs/tags/v4` (do NOT fabricate). Reuse upload-artifact `ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2`.
- [ ] 0.5 Verify Anthropic capped-key automatability (Admin API vs Playwright vs operator). Mark UNVERIFIED until a real attempt.
- [ ] 0.6 Create `constraint-baseline-growth` label (does not exist): `gh label create constraint-baseline-growth --description "Auto-recovery PR grew the dependency-cruiser baseline — heightened review" --color D93F0B`.

## Phase 1 — Stage A workflow
- [ ] 1.1 Create `.github/workflows/fix-constraints-stage-a.yml`: `on: pull_request` (opened/synchronize/reopened) + paths filter; loop-guard skip on `soleur/fix-constraints/*`; `concurrency` keyed on head.sha (key-burn dedup).
- [ ] 1.2 `permissions: contents: read` only (no write, no PR write).
- [ ] 1.3 Steps: SHA-pinned checkout (immutable head.sha) → anthropic-preflight → setup-bun + `bun install --frozen-lockfile --ignore-scripts` → run FULL constraint-gates.sh (not bare depcruise; capture rc).
- [ ] 1.4 If rc!=0 AND key present: dispatch claude-code-action (file edits only, held prompt) → re-run FULL constraint-gates.sh to VERIFY (rc==0 + non-empty diff).
- [ ] 1.5 extract-api-spend.sh → upload api-spend artifact.
- [ ] 1.6 Produce recovery artifact as FULL POST-IMAGE FILE CONTENTS (not a diff): `git diff --name-only` → assert each in allowlist (else abort) → copy current contents preserving repo-relative paths + meta.json (pr_number, head_sha, head_ref, changed-paths, touches_baseline) → upload-artifact `fix-constraints-patch-<pr>`. No artifact when green / no-change / still-red.
- [ ] 1.7 Sanitize all PR-derived strings via `env:`; strip control/Unicode-separator chars before annotations (log-injection).

## Phase 2 — Stage B workflow (Git Data API, NO checkout/NO git apply)
- [ ] 2.1 Create `.github/workflows/fix-constraints-stage-b.yml`: `on: workflow_run` (workflows: fix-constraints-stage-a, types: completed); guard `conclusion == 'success'`.
- [ ] 2.2 `permissions: contents: write, pull-requests: write`.
- [ ] 2.3 Download Stage A artifact via download-artifact `run-id: github.event.workflow_run.id` + github-token; no-op exit 0 if absent.
- [ ] 2.4 Routing identity from EVENT: head_sha = github.event.workflow_run.head_sha; resolve pr_number/head_ref by API from head_sha; cross-check meta.json, reject on mismatch. Validate head_sha `^[0-9a-f]{40}$`, pr_number `^[0-9]+$`.
- [ ] 2.5 Path validation (security crux): normalize each path; reject absolute/`..`/symlink-mode; ALLOW only apps/web-platform/{app,components,server}/** + .dependency-cruiser-known-violations.json; REJECT .github/**, *.cjs, constraint-gates.sh, else. Fail-closed (any unmatched → reject whole artifact).
- [ ] 2.6 Build commit via Git Data API: blob(s) → tree on parent head_sha → commit → ref refs/heads/soleur/fix-constraints/<pr>. NO actions/checkout of head, NO git apply, NO bun install/script exec.
- [ ] 2.7 Baseline-suppression segregation: if touches_baseline, label follow-up PR `constraint-baseline-growth` + enumerate each newly-suppressed edge in body (heightened review).
- [ ] 2.8 Open follow-up PR (`Ref #<pr>`); comment link on original PR. One deterministic comment per terminal state (recovered/rejected-out-of-scope/identity-mismatch/no-fix) — never silent; explicit step-output conditionals, not job-result trichotomy.

## Phase 3 — Scaffold template + generator + tests
- [ ] 3.1 Create `fix-constraints-stage-a.template` + `fix-constraints-stage-b.template` (`__TARGET_DIR__` placeholder).
- [ ] 3.2 Update `constraint-scaffold.sh`: emit both stage workflows; extend refuse-if-exists loop; sed both templates.
- [ ] 3.3 Redesign `emit-fix-constraints.test.sh`: both files emit, placeholder substituted, refuse-if-exists exit 66, anchored trigger greps (pull_request in A / workflow_run in B), forbidden-pattern (no `bun install` in Stage B). Keep `parity.test.sh` green.

## Phase 4 — Wording sweep + ADR + C4
- [ ] 4.1 Flip recovery wording (both dogfood + `.template` layers): SKILL.md §Agent-owns-gates #4-5, constraint-gates.sh 5 `::error::` sites, the 3 reference templates → "auto-recovery follow-up PR (wired, ADR-074)".
- [ ] 4.2 Author ADR-074 (Decision + Alternatives table per plan).
- [ ] 4.3 Amend ADR-071 recovery paragraph → point at ADR-074.
- [ ] 4.4 Edit model.c4 (add fixconstraints component + → anthropic, → webapp edges) + views.c4 (view include); fix falsified descriptions; run c4-code-syntax + c4-render tests.

## Phase 5 — Verify + supersede
- [ ] 5.1 Run scaffold tests + components.test.ts + C4 tests + tsc/lint on touched surfaces.
- [ ] 5.2 (post-merge) CodeQL 0 `actions/untrusted-checkout-toctou` via gh api alerts query.
- [ ] 5.3 (post-merge) Close #5804 with a pointer comment to #5814.
- [ ] 5.4 (post-merge) Re-run multi-agent security review naming the untrusted-checkout-toctou class in the spawn prompt.
- [ ] 5.5 Resolve capped-key automation-status (Admin API / Playwright / documented operator handoff with evidence).
