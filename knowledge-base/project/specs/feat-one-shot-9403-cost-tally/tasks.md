# Tasks — feat-one-shot-9403-cost-tally

Plan: `knowledge-base/project/plans/2026-10-01-feat-pipeline-cost-tally-plan.md`
Issue: #9403 · Follow-up deferrals: #9413 · PR: #9411

## Phase 1 — Counter script

- [x] 1.1 Create `plugins/soleur/scripts/pipeline-tally.sh`
  - [x] 1.1.1 Source `scripts/lib/session-state.sh`; resolve counter file at `<git-common>/soleur-session-state/counters/<_safe_worktree_name($BRANCH)>`; orphan-root fallback appends repo basename
  - [x] 1.1.2 `init` — idempotent merge (preserve counters, merge `--max-*` caps into `cap_<dim>` keys); auto-reset when `capped` set or `started_at` >24h old; `--reset` forces fresh; sweep sibling counter files mtime>30d
  - [x] 1.1.3 `incr <dim> [n]` — flat `key=value` rewrite under `with_lock`; missing/unreadable file → stderr `SOLEUR_TALLY_ERROR reason=missing-file` + stdout `UNKNOWN`, exit 0, never auto-create
  - [x] 1.1.4 `show` — `tally: seats=N ci_cycles=N fix_rounds=N agent_rounds=N` + warned/capped annotations; absent → `UNKNOWN` + ABSENT marker
  - [x] 1.1.5 `gate <dim>` — reads `cap_<dim>` from file; prints `OK`|`WARN` (≥80%, records `warned_<dim>`)|`STOP` (≥cap or `capped` set)|`UNKNOWN`; sets `capped=<dim>` on STOP
  - [x] 1.1.6 `selfcheck` — prints `SOLEUR_TALLY_OK`, write-free (preflight Check-10 sandbox safe)
  - [x] 1.1.7 Header documents the canonical per-skill call-out block verbatim (the snippet each SKILL.md copies)
  - [x] 1.1.8 Flag-parse helper for `--max-<dim>`: `10#` normalization; reject non-numeric/negative/0
- [x] 1.2 Create `plugins/soleur/scripts/pipeline-tally.test.sh` — battery covering: init merge/auto-reset/sweep, incr (incl. missing-file UNKNOWN), 20-way concurrent incr under flock, all gate arms, flag-parse rejects, selfcheck purity
- [x] 1.3 `plugins/soleur/hooks/stop-hook.sh` — `capped` check before the `block` emit: exits 0 + stderr `SOLEUR_TALLY_CAPPED dim=<d> cap=<n>` + resume prompt when set; ignores corrupt/absent files (Guard 4)
- [x] 1.4 Hook test additions on the stop-hook test surface — Guard 4 matrix (capped fixture exits 0/no-block; reset unblocks; corrupt file ignored; absent file unchanged)

## Phase 2a — Pilot: one-shot + review + ship

- [x] 2.1 `plugins/soleur/skills/one-shot/SKILL.md` — `--max-*` flag parse → `init` with caps; `incr` call-outs at plan/work/review/ship child dispatches (`agent_rounds`) and phase-boundary `show`; `gate` before each expensive step; STOP → session-state.md `budget-capped` marker + resume prompt
- [x] 2.2 `plugins/soleur/skills/review/SKILL.md` — `incr seats <n>` at panel spawn; `gate seats` pre-spawn
- [x] 2.3 `plugins/soleur/skills/ship/SKILL.md` Phase 6 — `## Pipeline Tally` section in BOTH body templates (`gh pr edit` + `gh pr create` fallback): counts, warned/capped events, cap-fraction, glossary line, `Pipeline-Tally:` machine line; ABSENT/ZERO/CAP_IGNORED/cap-unenforced tri-state+ sentinels
- [x] 2.4 Live-run verification: one real one-shot run leaves a non-empty counter file before Phase 2b proceeds

## Phase 2b — Roll to remaining skills

- [x] 2.5 `test-fix-loop/SKILL.md` — `--max` aliases `--max-fix-rounds`; `incr fix_rounds` per iteration; `gate` before next iteration
- [x] 2.6 `drain-labeled-backlog/SKILL.md` — `init`/`gate`/`incr agent_rounds`; `--branch <item>` attribution on child dispatches
- [x] 2.7 `resolve-todo-parallel/SKILL.md`, `resolve-pr-parallel/SKILL.md` — same pattern + `--branch` item attribution
- [x] 2.8 `work/SKILL.md` — `init`/`incr`/`gate` at phase boundaries; `incr ci_cycles` where CI is driven
- [x] 2.9 `eval-harness/SKILL.md` — minimal: `init`/`gate`/`incr agent_rounds` at real boundaries only

## Phase 3 — Bridge, sentinel, docs

- [x] 3.1 `counts:{…}` return field in `drain-labeled-backlog`, `resolve-todo-parallel`, `resolve-pr-parallel` workflow ports; invoking prose posts via `incr` (one writer per dimension)
- [x] 3.2 `plugins/soleur/test/components.test.ts` — Guard 2 sentinel: anchored call-form presence per AUTONOMOUS_LOOP_SKILL
- [x] 3.3 ADR-264 (provisional — re-verify ordinal at ship): per-branch unit counters on session-state root, fail-open, classified stop; record alternatives D/E/H/I
- [x] 3.4 `model.c4` plugin-system description: name the `counters/` write surface; run `c4-code-syntax.test.ts` + `c4-render.test.ts`
- [x] 3.5 README component-table update if scripts are counted

## Test Scenarios (from plan)

- selfcheck purity; init/incr/show math; capped → STOP → resume-blocked-until-reset; 20-way flock incr; absent/zero/cap-ignored tri-state; comment-only sentinel red; workflow `counts:` bridge
- Regression: `guardrails.test.sh`, `components.test.ts`, `emit-review-trailer.test.sh`, stop-hook tests
