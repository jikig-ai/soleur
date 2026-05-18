---
date: 2026-05-13
issue: 3724
plan: knowledge-base/project/plans/2026-05-13-feat-brand-survival-threshold-rename-plan.md
brand_survival_threshold: single-user incident
lane: cross-domain
---

# Tasks: brand_survival_threshold rename sweep (#3724)

Derived from `knowledge-base/project/plans/2026-05-13-feat-brand-survival-threshold-rename-plan.md`.

## Phase 1 — FR1: Frontmatter key rename

### 1.1 FR1a — `brand_threshold:` → `brand_survival_threshold:`

- [ ] **1.1.1** Edit `knowledge-base/engineering/ops/post-mortems/dashboard-error-postmortem.md:7` — change `brand_threshold:` to `brand_survival_threshold:`.

### 1.2 FR1b — `brand_survival:` → `brand_survival_threshold:`

- [ ] **1.2.1** Edit `knowledge-base/engineering/ops/runbooks/github-app-drift.md`.
- [ ] **1.2.2** Edit `knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md`.
- [ ] **1.2.3** Edit `knowledge-base/project/plans/2026-05-05-feat-github-app-drift-guard-plan.md`.
- [ ] **1.2.4** Edit `knowledge-base/project/specs/feat-3187-gh-app-drift-guard/spec.md`.
- [ ] **1.2.5** Edit `knowledge-base/project/specs/feat-3187-gh-app-drift-guard/tasks.md`.

### 1.3 FR1c — semantic `threshold:` → `brand_survival_threshold:` (4 files; 2 protected)

- [ ] **1.3.1** Edit `knowledge-base/engineering/ops/runbooks/codeql-bot-coverage.md:6`.
- [ ] **1.3.2** Edit `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md:6`.
- [ ] **1.3.3** Edit `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md:6` (BOTH key + value form: `threshold: single-user-incident` → `brand_survival_threshold: single-user incident`).
- [ ] **1.3.4** Edit `knowledge-base/project/plans/2026-05-11-ops-ci-extend-lint-bot-synthetic-glob-plan.md:7`.
- [ ] **1.3.5** **DO NOT EDIT** `knowledge-base/project/plans/2026-05-11-fix-preflight-...-plan.md:99` (preflight Check 6 sentinel — load-bearing).
- [ ] **1.3.6** **DO NOT EDIT** `plugins/soleur/skills/skill-security-scan/references/test-fixtures/clean-third-party.skill.md:21` (numeric review-threshold, orthogonal vocabulary).

## Phase 2 — FR2: value-form rename `single-user-incident` → `single-user incident`

### 2.1 Per-line judgment files (6 learning files with YAML tag-array uses)

For each: `grep -n "single-user-incident" <file>`. Rename PROSE lines only; preserve tag-array entries.

- [ ] **2.1.1** `knowledge-base/project/learnings/2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md` (line 7 tag — PRESERVE; line 14 prose — RENAME).
- [ ] **2.1.2** `knowledge-base/project/learnings/2026-05-10-plan-time-reviewer-orthogonality-for-security-sensitive-plans.md` (tag-array only — likely no edit, verify).
- [ ] **2.1.3** `knowledge-base/project/learnings/2026-05-11-multi-agent-review-vendor-pipeline-trust-model.md`.
- [ ] **2.1.4** `knowledge-base/project/learnings/2026-05-11-plan-review-caught-git-log-union-trap-and-cross-module-field-assumption.md`.
- [ ] **2.1.5** `knowledge-base/project/learnings/2026-05-12-plan-review-5-agent-panel-and-architecture-only-p1s.md`.
- [ ] **2.1.6** `knowledge-base/project/learnings/security-issues/2026-05-12-multi-agent-review-catches-load-bearing-redaction-primitive-bypasses.md`.

### 2.2 All other prose-only files (~40 files; per-file `Edit`)

- [ ] **2.2.1** Enumerate the remaining file list at /work time via: `comm -23 <(git grep -l "single-user-incident" 2>/dev/null | grep -v archive/ | grep -v "kb-tags.txt" | sort -u) <(printf '%s\n' <the 6 tag-array files from 2.1>)`.
- [ ] **2.2.2** For each enumerated file: `Edit` tool, replace `single-user-incident` → `single-user incident` per line judgment.
- [ ] **2.2.3** Special case: `scripts/lint-rule-ids.py:212,368` uses adjective-suffix forms (`single-user-incident-class`, `single-user-incident-`); rename to `single-user incident-class`, `single-user incident-`. If grammatically awkward, leave with `[skipped]` annotation in PR body.
- [ ] **2.2.4** **DO NOT EDIT** `knowledge-base/kb-tags.txt` — auto-regenerated in Phase 3.

## Phase 3 — Regenerate auto-derived artifacts

- [ ] **3.1** Run `bash scripts/generate-kb-index.sh` from repo root.
- [ ] **3.2** Confirm `knowledge-base/kb-tags.txt` regenerated; `grep -n "^single-user-incident$" knowledge-base/kb-tags.txt` returns 1 line (the canonical tag entry preserved from Phase 2.1).

## Phase 4 — Verification (Acceptance Criteria)

- [ ] **4.1 AC1:** `git grep -nE "^(brand_threshold|brand_survival):" -- '*.md' '*.yml' '*.yaml' '*.json' | grep -v archive/` returns 0 hits.
- [ ] **4.2 AC2:** `git grep -nE "^threshold:" -- '*.md' '*.yml' '*.yaml' '*.json' | grep -v archive/` returns exactly 2 hits (the 2 protected files).
- [ ] **4.3 AC3:** Run the AC3 grep from the plan (excludes tag-array + kb-tags.txt). Returns 0 hits.
- [ ] **4.4 AC4:** `grep -nE "^threshold:[[:space:]]*none,[[:space:]]*reason:" knowledge-base/project/plans/2026-05-11-fix-preflight-work-skills-worktree-and-test-all-gate-plan.md` returns 1 hit (line 99).
- [ ] **4.5 AC5:** `grep -nE "^threshold: 0\.5" plugins/soleur/skills/skill-security-scan/references/test-fixtures/clean-third-party.skill.md` returns 1 hit (line 21).
- [ ] **4.6 AC10:** `git grep -nE "^[[:space:]]*tags:[[:space:]]*\[.*single-user-incident\|^[[:space:]]+-[[:space:]]+single-user-incident\$" -- '*.md' | grep -v archive/` returns same 6 source-line hits as main baseline.
- [ ] **4.7 AC11:** `grep -n "^single-user-incident\$" knowledge-base/kb-tags.txt` returns 1 hit.

## Phase 5 — Commit + PR

- [ ] **5.1** Stage all changes: `git add -p` (interactive — confirm no unintended sweep).
- [ ] **5.2** Single atomic commit: `feat: rename brand_survival_threshold frontmatter key + canonicalize single-user incident value-form (#3724)`.
- [ ] **5.3** Push to remote.
- [ ] **5.4** Open PR with `Ref #2725` (NOT `Closes`) in body.
- [ ] **5.5** Wait for CI; verify AC7 (zero new red checks vs `main`).

## Phase 6 — Post-merge (operator)

- [ ] **6.1** After merge, ping #2725 / draft PR #3721 (PR2) for rebase onto updated `main`.
