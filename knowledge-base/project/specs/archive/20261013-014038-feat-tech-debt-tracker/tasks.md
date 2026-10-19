---
title: Tasks — tech-debt ledger lifecycle (Spec A of #2723)
date: 2026-05-12
issue: 2723
plan: knowledge-base/project/plans/2026-05-12-feat-tech-debt-ledger-lifecycle-plan.md
spec: knowledge-base/project/specs/feat-tech-debt-tracker/spec.md
lane: cross-domain
brand_survival_threshold: single-user incident
status: pending
---

# Tasks — tech-debt ledger lifecycle (Spec A of #2723)

Derived from the post-review plan. Phases follow dependency order; tasks within a phase may run in parallel where noted. After each phase, run a sanity check (named below) before proceeding to the next.

## Phase 1 — Backfill (9 live entries)

- [x] **1.1** Spec amendment: edit `knowledge-base/project/specs/feat-tech-debt-tracker/spec.md` FR1 to "9 live entries (archive excluded)". FR9 + TR8 narrowed to template-only (schema.yaml + references/yaml-schema.md NOT touched).
- [x] **1.2** Run the Phase 1 inline Python snippet (see plan §Phase 1) against `knowledge-base/project/learnings/technical-debt/`. Snippet imports `parse_frontmatter`/`serialize_frontmatter` from `scripts/backfill-frontmatter.py` via `sys.path` insert; MD5 body-verify asserted.
- [x] **1.3** Verify: `git diff knowledge-base/project/learnings/technical-debt/` shows 9 single-line additions, all `status: open`. Re-run snippet to confirm idempotent (zero output diff on re-run).
- [x] **1.4** Sanity check: `grep -c '^status:' knowledge-base/project/learnings/technical-debt/*.md` returns 9.
- [ ] **1.5** Commit: `chore: backfill status:open on tech-debt ledger entries (FR1) + spec FR1/FR9/TR8 amendment`.

## Phase 2 — SKILL.md scaffold

- [x] **2.1** Create `plugins/soleur/skills/resolve-debt/SKILL.md` with `name: resolve-debt` and ≤30-word third-person description: *"This skill should be used when triaging or closing open entries in the technical-debt ledger. Lists open debt, walks the operator through closing one with a linked GitHub issue."* (28 words.)
- [x] **2.2** Body sections: Overview, Commands (`list` / `close` / `help`), Sharp Edges. Model on `plugins/soleur/skills/schedule/SKILL.md`. No `<example>` blocks; per `plugins/soleur/AGENTS.md` skill-compliance checklist.
- [x] **2.3** Sanity: pre-measure cumulative SKILL description words. Expected: 1759 + 28 = 1787 ≤ 1800.

## Phase 3 — `resolve-debt.py` main script

Single Python script. Shebang `#!/usr/bin/env python3`. Imports parse helpers from `scripts/backfill-frontmatter.py` via `sys.path` insert (no separate `_frontmatter.py` module).

- [x] **3.1** Create `plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py`. Module skeleton: `argparse` for `--list`/`--no-verify`/`--help`; default mode interactive.
- [x] **3.2** Implement `list_mode`:
  - Walk `knowledge-base/project/learnings/technical-debt/`, skip `archive/`.
  - Per-file: `safe_parse_frontmatter` (stderr warn + skip on parse failure).
  - Filter `status == 'open'`; sort by `severity` desc (high>medium>low>unset), then `date` asc.
  - Print markdown table; empty-state `No open debt entries.` + exit 0.
- [x] **3.3** Implement `interactive_mode`:
  - Display table; prompt `Select entry (1..N) or q to quit:`; out-of-range re-prompt up to 3x then exit 2.
  - Prompt `Status (resolved | wont-fix):`; enum reject re-prompt.
  - If `resolved`: prompt `linked_issue (integer):`; `int()` parse + range-check `1 <= n <= 9_999_999`; on ValueError or range-fail re-prompt up to 3x then exit 2.
  - If not `--no-verify`: `gh issue view <N> --json state,title` (5s timeout). Non-zero exit → stderr names failure mode + `Re-invoke with --no-verify to skip validation.` + exit 1. No closed-state-warn branch.
- [x] **3.4** Implement `mutate_atomic`: serialize new frontmatter to a tempfile in the same directory; `os.replace`. SIGINT before replace leaves original untouched.
- [x] **3.5** After mutation: print `git diff -- <file>` to stdout; stderr message `Diff above. Review and commit when ready. To undo: git checkout -- <file>. No auto-commit by design.` Exit 0.
- [x] **3.6** Implement `print_help`: usage block enumerating three modes; exit 0.
- [x] **3.7** Smoke-test against the real backfilled ledger: `python3 plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py --list` → 9-row markdown table.

## Phase 4 — README

- [x] **4.1** Create `knowledge-base/project/learnings/technical-debt/README.md`:
  - One-paragraph: *"Operator-facing ledger of known tech debt in the Soleur plugin codebase."*
  - Frontmatter contract: `status` (required, enum), `linked_issue` (required only when `resolved`; optional when `wont-fix`; forbidden when `open`).
  - **Load-bearing-discriminator note** (architecture-strategist P2): `wont-fix` is the discriminator-of-record — without `status`, no way to express "we know about this debt and decided not to fix it." Future schema simplification must preserve `status`.
  - Both legacy and current frontmatter shapes preserved as-is.
  - Link to `/soleur:resolve-debt` and deferred Spec B #3650.
  - Archive note: archive is frozen; `resolve-debt` does not scan it.
  - **Non-Goals (explicit deferrals):** `--undo-close` flag (recovery is `git checkout` / `git revert`); schema unification; bulk-resolve; severity-filter; JSON output.

## Phase 5 — Compound-capture integration (template-only)

- [x] **5.1** Edit `plugins/soleur/skills/compound-capture/assets/resolution-template.md` line 12 (after `severity:`). Insert:
  ```yaml
  status: open  # defaults to open — close via /soleur:resolve-debt
  ```
- [x] **5.2** Do **NOT** edit `compound-capture/schema.yaml` (CORA-vendored). Do **NOT** edit `compound-capture/references/yaml-schema.md` (CORA-derived).
- [x] **5.3** Verify: dry-run compound with a synthesized `problem_type: technical_debt` fixture; new entry has `status: open` at the right slot.

## Phase 6 — Registration + count propagation

- [x] **6.1** Edit `plugins/soleur/docs/_data/skills.js`:
  - Line 11: `(4 categories, 65 skills)` → `(4 categories, 70 skills)`.
  - Line 61: `// Workflow (21)` → `// Workflow (22)`.
  - Between line 75 and 76: insert `"resolve-debt": "Workflow",` alphabetically.
- [x] **6.2** Grep for old counts: `git grep -E '\b(69|65) skills\b' -- ':(exclude).worktrees/' ':(exclude)*.lock'`.
- [x] **6.3** Update each hit to `70`: `plugins/soleur/README.md:45`, root `README.md`, `knowledge-base/overview/brand-guide.md` (×2). Reconcile divergence (skills.js stale at 65 → 70).
- [x] **6.4** Re-grep: same query returns zero hits.

## Phase 7 — Tests + verification

- [x] **7.1** Create synthesized fixtures under `plugins/soleur/test/fixtures/resolve-debt/`:
  - `legacy-schema.md` (one entry with `module/problem_type/component/tags/severity` shape; `status: open`).
  - `current-schema.md` (one entry with `title/category/tags/severity` shape; `status: open`).
  - `malformed-frontmatter.md` (broken YAML to trigger stderr-warn path).
  - `empty-ledger/` (empty directory for empty-state test).
  - `compound-output.md` (compound round-trip fixture).
- [x] **7.2** Create `plugins/soleur/test/resolve-debt.test.sh` covering T1-T12 (see plan §Test Scenarios). `set -euo pipefail` + per-test isolation.
- [x] **7.3** Run `bun test plugins/soleur/test/components.test.ts` (word-budget gate). Expected: green.
- [x] **7.4** Run `bun test plugins/soleur/test/` full suite. Expected: green, including `resolve-debt.test.sh`.
- [x] **7.5** Run docs site build per `plugins/soleur/CLAUDE.md`. Expected: `resolve-debt` rendered under Workflow category at `/skills/`.
- [x] **7.6** Smoke-test interactive flow against fixture: `open` → `resolved` with `linked_issue: 2723`; verify diff printed; verify no auto-commit; verify file mutated atomically; verify stderr undo-hint present.

## Phase 8 — PR preparation

- [ ] **8.1** Update PR #3645 body: add `## Changelog` section (1 line: "Add `/soleur:resolve-debt` skill + ledger-lifecycle frontmatter contract"); ensure `semver:minor` label is applied.
- [ ] **8.2** PR body contains `Closes #2723` on its own body line (per `2026-05-11-plan-r6-closes-after-apply-deferral-pattern.md`). Not in PR title.
- [ ] **8.3** Verify deferred sibling #3650 is referenced in PR body as "Follow-up: #3650 (deferred scheduled scanner; re-evaluation criteria in spec)".
- [ ] **8.4** Mark PR #3645 ready for review. The `user-impact-reviewer` agent will run at review-time per `plugins/soleur/skills/review/SKILL.md` for the `single-user incident` threshold.

## Sanity checks (between phases)

| After phase | Sanity check |
|---|---|
| Phase 1 | `grep -c '^status:' knowledge-base/project/learnings/technical-debt/*.md` == 9 |
| Phase 2 | `bun test plugins/soleur/test/components.test.ts` green (word-budget) |
| Phase 3 | `python3 plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py --help` exit 0 |
| Phase 5 | Compound dry-run round-trip emits `status: open` |
| Phase 6 | `git grep -E '\b(65|69) skills\b' -- ':(exclude).worktrees/'` zero hits |
| Phase 7 | Full test suite + docs site build green |

## Out of scope (deferred / explicit non-goals)

- Scheduled scanner (`tech-debt-tracker` original framing) → #3650 with ALL-must-hold re-evaluation criteria.
- Schema unification of the two ledger frontmatter shapes → separate follow-up issue.
- `--undo-close` flag → recovery is `git checkout -- <file>` (pre-commit) or `git revert` (post-commit).
- Bulk-resolve / severity-filter / JSON output → defer until `--list` + close usage emerges.
- `compound-capture/schema.yaml` + `references/yaml-schema.md` edits → CORA-vendored; out of scope for Spec A.
- WSJF / RICE / ICE cost-of-delay framework → defer to #3650.
