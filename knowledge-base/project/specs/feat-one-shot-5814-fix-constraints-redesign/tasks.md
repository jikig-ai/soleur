# Tasks: fix-constraints two-stage privileged split (#5814)

Plan: `knowledge-base/project/plans/2026-07-01-feat-fix-constraints-two-stage-privileged-split-plan.md`
Lane: cross-domain · Threshold: single-user incident · Supersedes: PR #5804

## Phase 0 — Preconditions & capability verification
- [x] 0.1 Re-confirm ADR-074 free + all on-main deps present (anthropic-preflight, extract-api-spend.sh, constraint-gates.sh).
- [x] 0.2 Verify CodeQL `actions` scanning enabled: `gh api repos/{owner}/{repo}/code-scanning/default-setup` → check `languages` includes `actions`. If absent, enable (or note 0-alerts AC is dashboard-verified).
- [x] 0.3 Confirm claude-code-action `claude_args` string from held workflow is reused verbatim (no model-id from memory).
- [x] 0.4 Pin `actions/download-artifact` to the v4 SHA fetched via `gh api repos/actions/download-artifact/git/refs/tags/v4` (do NOT fabricate). Reuse upload-artifact `ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2`.
- [x] 0.5 Verify Anthropic capped-key automatability — Admin API CANNOT create keys (Console-only) or set regular-tier spend limits; /work MUST Playwright the Console. Mark UNVERIFIED until a real attempt.
- [x] 0.6 Pin ADR-074 Decision + artifact-schema before Stage A freezes the artifact format.
- [x] 0.7 Resolve CodeQL `actions`-scanning enablement automatability (PATCH default-setup vs operator) so it's not a late manual gate.
- [x] 0.8 Add `workflow_dispatch` to read-only Stage A (manual retry) + document "push a commit to retry" in ADR-074/SKILL.md. (No `constraint-baseline-growth` label — auto-recovery is fix-only.)

## Phase 1 — Stage A workflow
- [x] 1.1 Create `.github/workflows/fix-constraints-stage-a.yml`: `on: pull_request` (opened/synchronize/reopened) + paths filter; loop-guard skip on `soleur/fix-constraints/*`; `concurrency` keyed on head.sha (key-burn dedup).
- [x] 1.2 `permissions: contents: read` only (no write, no PR write).
- [x] 1.3 Steps: SHA-pinned checkout (immutable head.sha) → anthropic-preflight → setup-bun + `bun install --frozen-lockfile --ignore-scripts` → run FULL constraint-gates.sh (not bare depcruise; capture rc).
- [x] 1.4 If rc!=0 AND key present: dispatch claude-code-action (file edits only, held prompt) → re-run FULL constraint-gates.sh to VERIFY (rc==0 + non-empty diff).
- [x] 1.5 extract-api-spend.sh → upload api-spend artifact.
- [x] 1.6 FIX-ONLY: the agent prompt forbids `--refresh-baseline`/baseline edits. Produce recovery artifact as FULL POST-IMAGE FILE CONTENTS (not a diff): `git diff --name-only` → assert each in allowlist `apps/web-platform/{app,components,server}/**` (else abort — baseline/out-of-scope NOT allowed) → copy current contents + per-file sha256, preserving repo-relative paths + meta.json (pr_number, head_sha, head_ref, changed-paths, per-file sha256) → upload-artifact `fix-constraints-patch-<pr>`. No artifact when green / no-change / still-red / baseline-touched.
- [x] 1.7 Name-coupling: Stage A `name:` MUST equal Stage B `workflows:` string. Sanitize all PR-derived strings via `env:` (escape-sequence strip, not literal chars).

## Phase 2 — Stage B workflow (Git Data API, NO checkout/NO git apply)
- [x] 2.1 Create `.github/workflows/fix-constraints-stage-b.yml`: `on: workflow_run` (workflows: <Stage A name>, types: completed); guard `conclusion == 'success'`; `concurrency` keyed on pr_number.
- [x] 2.2 `permissions: contents: write, pull-requests: write, actions: read` (actions:read REQUIRED for cross-workflow download).
- [x] 2.3 Download Stage A artifact via `download-artifact@d3f86a1… # v4` `run-id: github.event.workflow_run.id` + github-token; no-op exit 0 if absent. Enforce file-count/size/total bounds.
- [x] 2.4 EXPLICIT SAME-REPO GATE (security P0): resolve PR from head_sha; require isCrossRepository==false AND exactly one matching open PR before any write; fork/0/≥2 → comment + no-op.
- [x] 2.5 Routing identity from EVENT (never meta.json): head_sha = github.event.workflow_run.head_sha; resolve pr_number/head_ref by API; cross-check meta.json, reject on mismatch. Validate head_sha `^[0-9a-f]{40}$`, pr_number `^[0-9]+$` before branch-name construction.
- [x] 2.6 Path validation: normalize; reject absolute/`..`/symlink(120000)/gitlink(160000)/char-outside-`[A-Za-z0-9._/-]`/control-char; ALLOW only apps/web-platform/{app,components,server}/**; REJECT .github/**, *.cjs, constraint-gates.sh, baseline JSON, else. Fail-closed. All paths/contents argv/env-passed, never shell-interpolated.
- [x] 2.7 Build commit via Git Data API: per-file base64 blob (sha256-verified vs meta.json, fail-closed) → tree with MANDATORY base_tree at head_sha, mode-pin 100644 → commit (parent head_sha) → ref refs/heads/soleur/fix-constraints/<pr>. NO checkout of head, NO git apply, NO bun install/script exec. Test: bot tree differs from head_sha only in allowlisted paths (no deletions).
- [x] 2.8 Derive touches_baseline server-side (telemetry only; never trust meta.json field).
- [x] 2.9 Open follow-up PR as DRAFT, no auto-merge label, `Ref #<pr>`, NO "pre-verified green" claim. Sanitize all Stage B output strings (escape sequences). Comment link on original PR. One deterministic comment per terminal state (recovered/rejected-out-of-scope/fork-rejected/identity-mismatch/integrity-fail/no-fix) — never silent.

## Phase 3 — Scaffold template + generator + tests
- [x] 3.1 Create `fix-constraints-stage-a.template` + `fix-constraints-stage-b.template` (`__TARGET_DIR__` placeholder).
- [x] 3.2 Update `constraint-scaffold.sh`: emit both stage workflows; extend refuse-if-exists loop; sed both templates.
- [x] 3.3 Redesign `emit-fix-constraints.test.sh`: both files emit, placeholder substituted, refuse-if-exists exit 66, anchored trigger greps (pull_request in A / workflow_run in B), forbidden-pattern (no `bun install`/`actions/checkout`-of-head/`git apply` in Stage B), NAME-COUPLING assertion (Stage A `^name:` == Stage B `workflows:` string). Keep `parity.test.sh` green.

## Phase 4 — Wording sweep + ADR + C4
- [x] 4.1 Flip recovery wording (both dogfood + `.template` layers): SKILL.md §Agent-owns-gates #4-5, constraint-gates.sh 5 `::error::` sites, the 3 reference templates → "auto-recovery follow-up PR (wired, ADR-074)".
- [x] 4.2 Author ADR-074 (Decision + Alternatives table per plan).
- [x] 4.3 Amend ADR-071 — BOTH edits: (1) recovery paragraph → ADR-074; (2) promote-to-required blocker drops the satisfied #5791 half, keeps #5778.
- [x] 4.4 Edit model.c4: add `contributor` `#external` actor + trust-boundary edge (reconcile into existing scaffold→webapp edge / under `github` system — NOT a duplicate `platform.plugin` component) + views.c4 view include; fix falsified descriptions; run c4-code-syntax + c4-render tests.

## Phase 5 — Verify + supersede
- [x] 5.1 Run scaffold tests + components.test.ts + C4 tests + tsc/lint on touched surfaces.
- [ ] 5.2 (post-merge) CodeQL 0 `actions/untrusted-checkout-toctou` via gh api alerts query.
- [ ] 5.3 (post-merge) Close #5804 with a pointer comment to #5814.
- [ ] 5.4 (post-merge) Re-run multi-agent security review naming the untrusted-checkout-toctou class in the spawn prompt.
- [ ] 5.5 Resolve capped-key automation-status (Admin API / Playwright / documented operator handoff with evidence).
