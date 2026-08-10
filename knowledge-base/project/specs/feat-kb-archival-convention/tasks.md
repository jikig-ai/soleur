---
title: "Tasks — stop indexing per-feature ephemeral state (Tier 1)"
feature: feat-kb-archival-convention
issue: "#7399"
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-08-10-fix-stop-indexing-per-feature-ephemeral-state-plan.md
date: 2026-08-10
---

# Tasks — Tier 1

Phase numbers match the plan exactly (0–6). v1's numbering was offset by one, so ACs citing
"Phase 4" meant different things in each file.

**No task asserts an absolute corpus count.** Every count decays on each KB merge and on
this PR's own artifacts; v1 asserted `7475` and measured `7477`, tripping its own
stop-the-line on the first command.

## Phase 0 — Preconditions (no writes)

- [x] 0.1 Record `before=$(find knowledge-base -type f -name '*.md' -not -path '*/archive/*' -not -name 'INDEX.md' | wc -l)` as a **value**. Do not compare to a literal.
- [x] 0.2 `grep -n 'find "\$LEARNINGS_DIR"' scripts/generate-kb-index.sh` → exactly one line (the faceting walk cannot reach `project/specs/`, so only one `find` changes).
- [x] 0.3 Confirm the suite is **already registered**, glob-aware: `for f in plugins/soleur/test/*.test.sh; do echo "$f"; done | grep -c 'generate-kb-index'` → 1. A filename grep against `test-all.sh` returns 0 and is a false negative — glob registrations never name their files.
- [x] 0.4 Read `scripts/generate-kb-index.sh:15-45` before editing (`hr-always-read-a-file-before-editing-it`).

## Phase 1 — Failing tests first

- [x] 1.1 Change `plugins/soleur/test/generate-kb-index.test.sh:12` to `GEN_SCRIPT="${GEN_SCRIPT:-$REPO_ROOT/scripts/generate-kb-index.sh}"`. Without this the Phase 3 battery cannot point at a mutant and would have to mutate the real script in the working tree.
- [x] 1.2 Add a `setup_kb_specs` sibling to `setup_kb` (which builds only `project/learnings/`).
- [x] 1.3 F1 `specs/feat-x/spec.md` → indexed
- [x] 1.4 F2 `specs/feat-x/session-state.md` → dropped
- [x] 1.5 F3 `specs/feat-x/phase0-evidence.md`, `ac-walk.md` → dropped
- [x] 1.6 F4 `specs/fix-y/`: `spec.md` + `tasks.md` indexed, `session-state.md` dropped
- [x] 1.7 F5 `specs/review-workflow-hardening/`: `spec.md` indexed **+ `session-state.md` dropped**. The sibling is load-bearing — without it F5 is indexed before and after and pins nothing (v1 attributed M7 to it wrongly).
- [x] 1.8 F7 `plans/feat-q/plan.md` → indexed (the nested shape that broke the reverted gate's `-maxdepth 1`)
- [x] 1.9 F8 `plans/2026-01-01-feat-r-plan.md` → indexed
- [x] 1.10 F9 `specs/archive/…/spec.md` → dropped
- [x] 1.11 F10 `specs/feat-x/decision-challenges.md` → dropped from index. **Index half only** — v1's disk-presence half asserted that `find` is not `rm` and no mutation could turn it red.
- [x] 1.12 F11 `INDEX.md` in the fixture root → never a row
- [x] 1.13 F12 `specs/feat-x/diagram.png` → dropped (356 `.png` + 93 `.pen` live under KB)
- [x] 1.14 F13 `product/specs/feat-w/session-state.md` → **indexed** (only `project/specs/` is special; no such dir exists today, which is why nothing pinned it)
- [x] 1.15 F14 `specs/feat-x/tasks.md` → **indexed**
- [x] 1.16 F15 generator with `KB_DIR="$kb/"` → byte-identical output to `KB_DIR="$kb"`
- [x] 1.17 Confirm the drop-fixtures are RED against the unmodified script; the regression guards are GREEN before and after. Do **not** force the guards RED (v1 demanded all-RED, which was impossible and invited weakening fixtures until they went red).
      **Measured: 7 failed / 38 passed.** RED were F2, F3 (×2), F4's drop-half, F5's drop-half, F10 — and F15, which fails against the *unmodified* script because the trailing-slash `KB_DIR` bug already broke the pre-existing `rel=` strip at `:62`. **F12 was GREEN pre-change**, correcting this task as written: `.png` was already excluded by `-name '*.md'`, so F12 is a regression guard on a pre-existing arm (it pins M15), not a drop-fixture.

## Phase 2 — The predicate

- [x] 2.1 `scripts/generate-kb-index.sh:20` — add `KB_DIR="${KB_DIR%/}"` after the default assignment. Fixes the new predicate **and** the pre-existing `rel="${f#"$KB_DIR/"}"` bug at `:62` that emits absolute paths on a trailing slash.
- [x] 2.2 `:36-41` — add `\( -not -path '*/project/specs/*' -o -name 'spec.md' -o -name 'tasks.md' \)` to the existing `find`.
- [x] 2.3 Patterns MUST be single-quoted and non-interpolated. Interpolating `$KB_DIR` makes the predicate form-dependent: a trailing slash silently disables the whole feature (7,477 indexed, exit 0, green suite).
- [x] 2.4 Add a ~10-line WHY block above the group — house style for sharp edges (`test-all.sh:378`, `lefthook.yml:262`). It is the only place a future editor will read.
- [x] 2.5 Update `:10` (`# Excludes archive/ directories and INDEX.md itself.`) — it is `--help` output via the `sed` at `:27` and is now incomplete.
- [x] 2.6 F1–F15 all GREEN. `bash -n scripts/generate-kb-index.sh` clean.

## Phase 3 — Mutation battery

`GEN_SCRIPT=<mutant> bash <suite>` against a `cp`+`sed` mutant under `mktemp -d`. Record the actual RED per row.

- [x] 3.1 M1 delete the whole group → F2, F3, F4, F5
- [x] 3.2 M2 delete `-o -name 'spec.md'` → F1, F4, F5
- [x] 3.3 M4 flip `-not -path` → `-path` → F2, F3, F7, F8
- [x] 3.4 M6 drop `-not -path '*/archive/*'` → F9
- [x] 3.5 M7 narrow arm 1 to `*/project/specs/feat-*` → F4, F5's sibling
- [x] 3.6 M9 drop `-not -name 'INDEX.md'` → F11
- [x] 3.7 M13 loosen arm 1 to `*specs/*` → F13
- [x] 3.8 M14 delete `-o -name 'tasks.md'` → F14
- [x] 3.9 M15 drop `-name '*.md'` → F12
- [x] 3.10 M16 delete the `KB_DIR%/` normalization → F15
- [x] 3.11 Do **not** add a row for `-not -type l` — `-type f` already excludes symlinks, so the mutation is semantically null and no fixture can go red.
- [x] 3.12 `git status --short` clean after the battery (mutants live in `mktemp -d`, never the worktree).

## Phase 4 — Differential real-corpus assertion

- [x] 4.1 `cp -r knowledge-base "$tmp/kb"`; `git show HEAD:scripts/generate-kb-index.sh > "$tmp/pre.sh"`.
- [x] 4.2 Generate with the pre-edit script, record `project/plans` row count; generate with the edited script, record again. Counts MUST be identical.
- [x] 4.3 Assert the set: `sed -n 's|^- \[.*\](\(project/specs/[^)]*\))$|\1|p' "$tmp/kb/INDEX.md" | xargs -n1 basename | sort -u` prints exactly `spec.md` and `tasks.md`. Extract **link targets**, not any line containing `project/specs` — this plan's own title matches that literal.
- [x] 4.4 `rm -rf "$tmp"`.

## Phase 5 — Regenerate INDEX.md

- [x] 5.1 Run `bash scripts/generate-kb-index.sh` in the worktree; commit `INDEX.md`, `kb-tags.txt`, `kb-categories.txt` **alone**, as the final commit.
- [ ] 5.2 Explain the diff in the PR body: accumulated staleness + the exclusion delta.
- [x] 5.3 Comment on #7401 that its remaining scope is the CI freshness gate only, naming `plugins/soleur/test/c4-model-freshness.test.sh` as the precedent.
- [x] 5.4 Comment on #7400 that its start condition is satisfied by this PR's Phase 4 differential, decoupling it from #7401.

## Phase 6 — ADR + consumer prose

- [x] 6.1 `git fetch origin main`, then re-derive the next free ordinal from **fetched** `origin/main`. ADR-172 is taken; expected next is ADR-173.
- [x] 6.2 Author `ADR-173-kb-index-exclusion-supersedes-per-feature-archival.md`, `status: adopting`.
- [x] 6.3 Record: ADR-084 §5 + `ship/SKILL.md` (sentence beginning "The practical consequence: compound is the last point"); the 79%-no-`spec.md` finding; Tier 2 sequencing; Alternatives covering keep-archival, delete-outright, denylist, and `spec.md`-only.
- [x] 6.4 Amend `plugins/soleur/agents/engineering/research/learnings-researcher.md:15` — "INDEX.md lists every non-archived KB file with its title" is now false.
- [x] 6.5 Amend `.openhands/skills/learnings-researcher/SKILL.md:15` — verbatim duplicate of the same claim.
- [x] 6.6 Amend `plugins/soleur/skills/brainstorm/SKILL.md:232` — it reasons from one exclusion class (`/archive/`); there are now two.
- [x] 6.7 Add 3 lines to `plugins/soleur/skills/spec-templates/SKILL.md:73-78` stating the rule where spec dirs are created. Only discoverability fix that reaches authors.
- [x] 6.8 Add a superseded-in-part pointer to `plugins/soleur/skills/archive-kb/SKILL.md` (ADR-173 + #7400). NG2 covers the *script*, not the SKILL.
- [x] 6.9 Amend `knowledge-base/project/specs/feat-kb-archival-convention/spec.md`: rewrite G1 ("a single mechanical predicate, no per-file judgment"), replace FR1 with the allowlist, delete TR2, strike absolute counts from FR3/TR5/ACs.
- [x] 6.10 If the ordinal moved, sweep plan + this file + AC10 in the **same** edit.

## Phase 7 — Exit gate

- [x] 7.1 `git diff --stat plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` empty (NG2).
- [x] 7.2 `git diff --name-status origin/main...HEAD -- knowledge-base/project/specs knowledge-base/project/plans` → only this feature's artifacts, zero `R`/`D`. **Three-dot** — two-dot reports main's movement as this branch's deletions.
- [x] 7.3 `grep -rn "lists every non-archived KB file" plugins/ .openhands/` → zero.
- [x] 7.4 Full `bash scripts/test-all.sh` green, with the suite appearing exactly **once** in the runner output (a duplicate registration would show it twice).
- [ ] 7.5 All 12 plan ACs verified and recorded in the PR body.

## Out of scope — do not do

- No archival gate. Any gate on the `git mv` inherits the ADR-084 §5 collision.
- No change to `archive-kb.sh` itself — #7400's exit criterion.
- No migration of the artifact backlog. Under index-exclusion there is nothing to migrate.
- No exclusion of merged features' `spec.md`/`tasks.md`/plans — #7400, pending a reliable merged signal.
- No widening of `scripts/lint-orphan-test-suites.sh`. The panel found 7 genuine orphan suites repo-wide (4 in `linear-fetch/scripts/`, including a secret-redaction gate) caused by two glob blind spots in `test-all.sh`'s glob loop. **File separately; do not expand this PR.**
- No change to brainstorm indexing.
