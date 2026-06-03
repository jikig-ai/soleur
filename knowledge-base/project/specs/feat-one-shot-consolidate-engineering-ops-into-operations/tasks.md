---
title: "Tasks — Consolidate engineering/ops into engineering/operations"
feature: feat-one-shot-consolidate-engineering-ops-into-operations
lane: procedural
plan: knowledge-base/project/plans/2026-06-03-refactor-consolidate-engineering-ops-into-operations-plan.md
date: 2026-06-03
---

# Tasks — Consolidate `engineering/ops` → `engineering/operations`

Derived from `2026-06-03-refactor-consolidate-engineering-ops-into-operations-plan.md`. Phase order is load-bearing: move (1) before sweep (2).

## Phase 0 — Preconditions

- [ ] **0.1** Confirm CWD == worktree path and branch == `feat-one-shot-consolidate-engineering-ops-into-operations` (not main).
- [ ] **0.2** Re-confirm no name collisions: `diff` of `ops/` vs `operations/` file trees prints empty for `^<` lines.
- [ ] **0.3** Capture baseline counts: total non-operations refs (expect 782); non-archive sweep target (expect 654 refs / 273 files).
- [ ] **0.4** Verify substring-safety: `printf 'engineering/operations' | grep -o 'engineering/ops'` returns NO match.

## Phase 1 — Move files (git mv, preserve history)

- [ ] **1.1** `git mv knowledge-base/engineering/ops/runbooks knowledge-base/engineering/operations/runbooks`
- [ ] **1.2** `git mv knowledge-base/engineering/ops/post-mortems knowledge-base/engineering/operations/post-mortems` (carries the `screenshots/3015/*.png` binary).
- [ ] **1.3** `rmdir knowledge-base/engineering/ops` (now empty).
- [ ] **1.4** Verify: ~41 renames in `git status -R`; `ops/` file count = 0; `operations/` file count = 44; `git log --follow` on a moved runbook shows pre-PR history.

## Phase 2 — Sweep live references (engineering/ops → engineering/operations)

- [ ] **2.1** Rebuild the file list AFTER the move: `git grep -rIl "engineering/ops" | grep -v "engineering/operations" | grep -vE '/archive/'` → ~273 files. (Includes the 11 self-referencing files now at `operations/` paths.)
- [ ] **2.2** Apply boundary-anchored replace per file: `sed -i -E 's#engineering/ops(/|[^a-z]|$)#engineering/operations\1#g' "$f"` over the rebuilt list. All extensions (`.md .sh .ts .tsx .yml .sql .tf .txt .gitignore .example` + extensionless `CODEOWNERS`, `NOTICE`).

## Phase 3 — Index & grep-invisible prose

- [ ] **3.1** `knowledge-base/INDEX.md` — verify post-sweep zero `engineering/ops` and ~40 links resolve.
- [ ] **3.2** Grep for bare `ops/{runbooks,post-mortems}` tree-nodes / prose inside `knowledge-base/engineering/` + `INDEX.md`; fix any path-sweep misses.

## Phase 4 — Verify functional path consumers resolve

- [ ] **4.1** `.claude/hooks/ship-runbook-ssh-gate.sh` glob (line 46) → `operations/runbooks/*.md`; zero `engineering/ops/` left.
- [ ] **4.2** `plugins/soleur/skills/incident/scripts/dry-run.sh` `runbook_dir` (197) + post-mortems writer (429) → `operations/`; dry-run resolves.
- [ ] **4.3** `incident/test/redact-sentinel.test.sh` `NEGATIVE_BASELINE` (22) → moved post-mortem exists; test passes.
- [ ] **4.4** `plugins/soleur/test/ship-followthrough-directive.test.sh` (86) + fixture `expected-issue-body.md` swept; test passes.
- [ ] **4.5** `.gitignore` screenshot negation (68) → `git check-ignore` exits 1 (PNG NOT ignored).
- [ ] **4.6** `.github/CODEOWNERS` (18) → `github-app-drift.md` exists at `operations/runbooks/`.
- [ ] **4.7** `skill-freshness.json` — NO-OP, already `operations/`; confirm consumer + file present.
- [ ] **4.8** Inngest cron functions: zero `engineering/ops/` residue in issue-body URL strings.

## Phase 5 — Residual gate

- [ ] **5.1** Primary: `git grep -rIn "engineering/ops" | grep -v "engineering/operations" | grep -vE '/archive/' | wc -l` == 0.
- [ ] **5.2** Cross-check: `git grep -rIl "engineering/ops" | grep -v "engineering/operations"` lists ONLY `**/archive/**` files + this plan file.

## Phase 6 — Tests

- [ ] **6.1** Targeted: `redact-sentinel.test.sh`, `ship-followthrough-directive.test.sh`, web-platform vitest for `cron-skill-freshness` + `cron-cloud-task-heartbeat`.
- [ ] **6.2** Full gate: `bash scripts/test-all.sh` exits 0.

## Acceptance gate

See plan `## Acceptance Criteria` AC1–AC13. Key: AC4 (residual=0), AC5 (only archive+plan retain old path), AC11 (no `operationserations` artifacts), AC12 (`soleur:operations`/`DevOps`/prose-"ops" untouched).
