---
title: "feat: instrument one-shot and test-fix-loop to emit run_health.json and phase_prompts"
type: feat
date: 2026-11-20
slug: feat-emit-run-health-artifacts
branch: feat-one-shot-12573-run-health-emit
issue: 12573
closes: 12573
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: instrument one-shot and test-fix-loop to emit run_health.json and phase_prompts

## Overview

A degraded pipeline run needs a sealed on-disk record of which phases ran, whether they errored, what prompt text that phase used, and how the run exited. The helper that writes that record is already on `origin/main`. Neither `one-shot` nor `test-fix-loop` calls it, the versioned schema file the loop already names is absent, and seal today depends on a magic phase name. This plan finishes that contract: one schema, an explicit seal, skill text that actually invokes the helper, and tests. It does not close the parent epic.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Problem Statement / Motivation

Forensics has to correlate a phase prompt to a failure from bytes on disk. A prose promise in a skill, or a self-report written after the run, does not give those bytes. `plugins/soleur/scripts/run-health-emit.sh` already upserts a phase row and copies prompt text to a new file when the phase name is reused. `plugins/soleur/skills/test-fix-loop/SKILL.md` describes the duty and points at `plugins/soleur/skills/one-shot/references/run-health-schema.md`, which is not in the tree. `plugins/soleur/skills/one-shot/SKILL.md` does not mention the helper. `git grep` on `origin/main` for `run-health-emit`, `run_health`, and `phase_prompts` under those two skill directories returns no call. `.gitignore` line `.soleur/` already ignores `.soleur/runs/` (`git check-ignore -v` confirms both `run_health.json` and `phase_prompts/0.md`).

## Proposed Solution

Keep the one helper. Do not add a second ledger, a cron, or a new ignore rule.

1. Document schema version 1 in `plugins/soleur/skills/one-shot/references/run-health-schema.md` and write `schema_version: 1` into the JSON.
2. Seal only when the caller passes `--seal` with a terminal status (`completed`, `failed`, or `budget-capped`). A phase name such as `8`, `exit`, or `ship` must not seal by itself. After `sealed` is true, a later phase upsert must leave `sealed`, `completed_at`, and the terminal `status` unchanged.
3. At `--seal`, copy gate state by running `plugins/soleur/scripts/pipeline-tally.sh show` into `tally_show`, and set `goto_count` by counting `verb=goto` lines in the session-state file the caller passes. Do not invent a second counter. `pipeline-tally.sh` already stores seats, ci cycles, fix rounds, and agent rounds. `plugins/soleur/scripts/retry-budget-ruling.sh` already appends `verb=goto` into `session-state.md`.
4. Tell both skills to call the helper. The snapshot is the step invocation (step id, child skill, args), not the whole skill file. The skill file is already in git. Retries keep the first snapshot and write `phase.attempt-N.md`.
5. Extend `plugins/soleur/scripts/run-health-emit.test.sh`. Do not register a new suite file.

`one-shot` has no shared shell across steps, and the planning step runs in a subagent whose context is discarded. After the worktree exists, record `run_health_dir:` in `knowledge-base/project/specs/<branch>/session-state.md` so a later step can find the same directory after compaction. `test-fix-loop` is one skill execution; it keeps `RUN_DIR` in that execution and seals on the way out.

## Technical Considerations

- The helper stays fail-open. Missing args, a refused phase token, a mkdir failure, and a Python write failure print to stderr and exit 0. Do not switch this file to `set -euo pipefail` or to exit 1 on a bad arg. Constitution exit-1 would abort the pipeline the record is not allowed to abort. The existing test already asserts the missing-arg exit is 0.
- Phase tokens must match `^[A-Za-z0-9._-]+$`. Anything else exits 0 before the first write, so a token cannot escape `phase_prompts/`.
- `--discover` writes a temp directory, seals a one-phase ledger, prints `ok`, and deletes the temp directory. It must not write under the repo. Preflight Check 10 runs with the repo read-only.
- Skill edits stay off the pinned strings. Do not rewrite the overlap-preflight paragraph, the scope-check sentence (`non-zero exit = scope unverified`), the `gh pr diff <M> --name-only` sentence, the anti-bypass markers, or the admin-merge-ready sentence in `one-shot/SKILL.md`. Those strings are pinned by `plugins/soleur/test/pr-overlap-preflight.test.sh`, `plugins/soleur/test/changed-path-readers.test.sh`, `plugins/soleur/test/workflow-fidelity.test.ts`, `plugins/soleur/test/admin-merge-ready-wiring.test.sh`, and `plugins/soleur/test/components.test.ts`.
- `one-shot/SKILL.md` byte ceiling, measured 2026-11-20: `wc -c` is 51995 and `plugins/soleur/test/skill-body-budget.json` key `one-shot` is 52000 (`lint-skill-body-budget.py` uses `stat().st_size` of the whole file). Spare is 5 bytes. After the edit the file must be at most 51950 bytes (50 bytes of spare). Do not raise the ceiling in this diff. `test-fix-loop/SKILL.md` is 19485 bytes and is not a ceiling key.
- The one-shot command list lives in `run-health-schema.md`. The skill file gains only this block, and loses two dated session sentences inside the paragraph that starts `**Why this gate exists.**`: the sentence that starts `The 2026-05-12` and ends at `implementations).`, and the sentence that starts `The 2026-05-29` and ends immediately before `Item 3 now probes`. Those two sentences are history. The re-probe rule and `Item 3 now probes` stay. `git grep` of distinctive slices of those sentences under `plugins/soleur/test` and `plugins/soleur/scripts` returned no pin. Net of a 276-byte block against 676 bytes removed lands near 51595 (`52000 - 51595 = 405` spare). Re-measure with `wc -c` after the edit. If a pin test fails, restore the sentence it needs and trim a different unpinned history clause in that same paragraph until `wc -c` is at most 51950.

```text
<!-- run-health-emit:start -->
**Run health.** After step 0d and on every return path, read [run-health-schema.md](./references/run-health-schema.md) and run its `bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-health-emit.sh"` lines, including `--seal`.
<!-- run-health-emit:end -->
```

- Reference the schema with a markdown link, not a backtick path. From `one-shot`: `[run-health-schema.md](./references/run-health-schema.md)`. From `test-fix-loop`: `[run-health-schema.md](../one-shot/references/run-health-schema.md)`.
- Do not change either skill's `description:` line. `one-shot` is 17 words. `test-fix-loop` is 27 words.
- Status vocabulary is four tokens. `started` is a phase row only: `--seal` with `started` does not set `sealed`. `completed`, `failed`, and `budget-capped` are terminal: `--seal` with one of those sets `sealed`, `completed_at`, and ledger `status` to that token. Any other token is non-terminal: the phase row may store it, and `--seal` does not set `sealed`. Do not write a stored value `open`.
- `goto_count` counts lines that contain the compact marker `retry-budget-ruling: verb=goto phase=`. A prose mention of `verb=goto` without that prefix does not count. `tally_show` is the full stdout of `pipeline-tally.sh show` at seal. Measured on this worktree 2026-11-20, that stdout is one line: `tally: seats=0 ci_cycles=0 fix_rounds=0 agent_rounds=1 ci_wall_s=unmeasured`. The test stubs that program by placing a same-named script earlier on `PATH`. It does not edit `plugins/soleur/scripts/pipeline-tally.sh`. The stub prints one line of that same shape with different integers, so a hard-coded copy of the live line is not what the assertion matches.
- The parent `one-shot` context runs the helper. The planning subagent does not. Steps 1–2 are recorded by the parent before the spawn and after the return. The subagent's plan-only diff check stays limited to `knowledge-base/project/(plans|specs)/`.
- When replacing the loop's Run Health Emission section, do not cite a closed issue number. Name the consumer by path: `plugins/soleur/agents/engineering/review/session-forensics-analyst.md`.
- NFR register: no row change. The artifact is a local gitignored file. It adds no request-path latency and no hosted availability target.
- Attack surface: the only new write is under `.soleur/runs/<run-id>/`, already ignored. Prompt text can contain whatever the session saw. The defense is the existing ignore plus the check-ignore test, not a new store.

### Implementation Phases

#### Phase 1: Schema and helper

- Add the schema document and the JSON fields `schema_version`, `sealed`, `goto_count`, `tally_show`.
- Replace the phase-name seal heuristic with `--seal`.
- Add `--session-state`, `--import-tally`, `--discover`, and the phase-token refusal.
- Success criterion: the cases in Test Scenarios pass, including "phase `8` without `--seal` does not seal" and "a write after seal does not clear it".

#### Phase 2: Skill calls

- `one-shot`: the short block above is the only addition to `SKILL.md`, plus the two history-sentence deletions. `run-health-schema.md` states the calls: after step 0d, create `RUN_DIR=.soleur/runs/<branch>-<utc>` and record `run_health_dir:` in session-state. The parent calls the helper at each step boundary (0d, 1-2, 3, 4, 5, 5.5, 6, 7, 8) with `--phase` set to that step id and `--prompt-file` pointing at the step invocation text. On every return path, including abort and budget-capped, the parent calls `--seal` before returning. Step 8 seals `completed` only when the completion promise is true; otherwise `failed`.
- `test-fix-loop`: replace the prose-only section with the same helper. Phase ids stay `0`, `iter-N-parse`, `iter-N-fix`, `terminate`, and `exit`. `--seal` runs once, on the way to the diagnostic report, with `completed`, `failed`, or `budget-capped`.
- Success criterion: both skill files contain the literal `run-health-emit.sh` and `--seal`, and the loop no longer points at a missing schema file.

#### Phase 3: Tests

- Extend the existing test file. Cases cover schema version, append-only snapshots, explicit seal, seal immutability, phase-token refusal, goto count from a fixture session-state, tally text stored from a stub, git check-ignore, and the two skill files.
- Do not add a new `*.test.sh` registration. The weight row for this file is already in `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`.
- Success criterion: `bash plugins/soleur/scripts/run-health-emit.test.sh` prints `fails=0`.

## Files to Create

- `plugins/soleur/skills/one-shot/references/run-health-schema.md` — schema version 1 field list, the seal rule, and the one-shot call list (the skill file cannot hold that list under its byte ceiling).

## Files to Edit

- `plugins/soleur/scripts/run-health-emit.sh` — version, explicit seal, imports, discover, phase-token refusal.
- `plugins/soleur/scripts/run-health-emit.test.sh` — schema, seal, wiring, and ignore cases.
- `plugins/soleur/skills/one-shot/SKILL.md` — additive calls at step boundaries and seal on every return path.
- `plugins/soleur/skills/test-fix-loop/SKILL.md` — replace the prose section with real helper calls and a markdown link to the schema.

## User-Brand Impact

- **If this lands broken, the user experiences:** a degraded pipeline run with no sealed `run_health.json`, so a later forensic read has nothing to correlate and only the executing session's self-report remains.
- **If this leaks, the user's workflow is exposed via:** prompt text copied under `.soleur/runs/<run-id>/phase_prompts/` reaching git history if the ignore fails, or sitting readable on the machine that ran the pipeline. That text can include secrets or customer text pasted into the session.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one committed prompt snapshot in the public repo is enough to expose one person's data. The files are local and already covered by `.soleur/`, so this is not an aggregate hosted-data breach. Stricter default because the bytes can be user data. Row in `knowledge-base/project/specs/feat-one-shot-12573-run-health-emit/decision-challenges.md`. `soleur:engineering:review:user-impact-reviewer` runs at review time. Live CPO was not spawned in this headless pass (`Reviewed-Coverage: sequential-fallback`). The 2026-11-10 brainstorm Product note is advisory carry-forward, not sign-off. `requires_cpo_signoff` stays true.

## Observability

```yaml
liveness_signal:
  what: "plugins/soleur/scripts/run-health-emit.sh --discover prints ok after writing and sealing a temp ledger"
  cadence: "per invocation of the discover probe; production emission is once per pipeline phase plus one seal at exit"
  alert_target: "stderr line run-health-emit: on a failed write; the pipeline still continues because the helper exits 0"
  configured_in: "plugins/soleur/scripts/run-health-emit.sh --discover"
error_reporting:
  destination: "stderr prefix run-health-emit:; no Sentry project — the writer is a local gitignored file, not a hosted service"
  fail_loud: "stderr line starting run-health-emit:"
failure_modes:
  - mode: "helper cannot create the run directory or the JSON write fails"
    detection: "stderr line run-health-emit: and no sealed file at the run dir"
    alert_route: "the skill text records the stderr line in the run output; no paging path, the pipeline must not stop"
  - mode: "ledger never sealed"
    detection: "run_health.json exists and sealed is false after the skill's exit call"
    alert_route: "unit test fails if --seal does not set sealed; a live run shows sealed false to the forensic reader"
logs:
  where: "stderr of the helper, plus run_health.json and phase_prompts/ under .soleur/runs/<run-id>/"
  retention: "until the worktree or the local .soleur directory is removed; this issue does not add a purge job"
discoverability_test:
  command: bash plugins/soleur/scripts/run-health-emit.sh --discover
  expected_output: "ok"
```

## Guard Contract

### Guard 1 — producer skills call the helper and seal

**Property.** Each skill in the producer set has a line that runs `bash` with `run-health-emit.sh` and passes `--seal`. A sentence that merely names both tokens is not a call.

**Assembly.** The producer set is the two skills named by the issue: `plugins/soleur/skills/one-shot/SKILL.md` and `plugins/soleur/skills/test-fix-loop/SKILL.md`. The chokepoint is one array in `plugins/soleur/scripts/run-health-emit.test.sh` listing those paths. The test fails if the array is empty or if any listed file lacks a `bash` line containing both `run-health-emit.sh` and `--seal`. `git grep` on 2026-11-20 shows those two skills do not call the helper yet, and the only executor of the script outside knowledge-base prose is `run-health-emit.test.sh`. Skill markdown is the producer this issue adds. The helper is not a process wrapper around the agent.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `run-health-emit.sh` call from `one-shot/SKILL.md` and leave `test-fix-loop` intact | RED |
| 2 | Set the producer array in the test to empty | RED |
| 3 | Append a third skill path that has no helper call to that array | RED |
| 4 | Remove `--seal` from `test-fix-loop/SKILL.md` while leaving the helper name in place | RED |
| 5 | Replace the `bash` invocation with a sentence that still contains `run-health-emit.sh` and `--seal` and does not run them | RED |

**Harness rows.** Delete the assertion that checks the literals and leave the suite exiting 0: RED. A must-pass input that is not the canonical text: a call that passes `--seal` plus `--import-tally` still passes.

**Anchor.** The literals live in the test in the same commit as the skill text. This proves presence, not an out-of-commit registry. A paired edit of the test and the skill can weaken it; review reads both.

### Guard 2 — a sealed ledger stays sealed

**Property.** After `--seal` succeeds, a later phase upsert does not clear `sealed`, `completed_at`, or the terminal `status`.

**Assembly.** The writer this guard pins is the Python block in `plugins/soleur/scripts/run-health-emit.sh`. Phase upsert, prompt copy, and seal all go through that block. `git grep` of `run_health.json` outside `knowledge-base/` on 2026-11-20 finds that script and its test, not a second writer.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Emit `--phase 8 --status completed` with no `--seal`, then read `sealed` | RED if the test expects `sealed` false and the heuristic sets it true |
| 2 | Remove the seal case from the test so zero seal assertions run and the file still exits 0 | RED |
| 3 | After a successful `--seal --status failed`, upsert `--phase later --status completed` | RED if `sealed` becomes false or `status` becomes `completed` |
| 4 | Call `--seal` before any phase row, then upsert a phase | RED if `sealed` is cleared |

**Harness rows.** A must-pass input that is not the canonical phase name `exit`: `--phase step-3 --status completed --seal` still sets `sealed` true.

**Anchor.** No stored hash. The schema document and the test both require `schema_version` 1. A paired edit can move both; review reads both.

**Exit sites relative to the first write** (`mkdir` of `<run-dir>/phase_prompts`):

| Exit | Position | Proves |
|---|---|---|
| Missing `--run-dir`, `--phase`, or `--status` (except `--discover`) | Before first write | Exit 0, directory absent |
| Phase token outside `^[A-Za-z0-9._-]+$` | Before first write | Exit 0, nothing created |
| `mkdir` fails | At the first write, before the JSON replace | Exit 0, stderr `run-health-emit:` |
| Python replace fails | After `mkdir` | Exit 0, stderr `run-health-emit:` |
| `--seal` with status `started` | Before setting `sealed` | Exit 0, `sealed` stays false |
| Success | After `os.replace` | Exit 0, file is the new JSON |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Instrument `one-shot` and `test-fix-loop` to emit structured run-health artifacts at run exit" | Phase 2 skill edits | mapped |
| 2 | "`run_health.json` (goto counts, gate decisions, which phases errored, exit status)" | schema fields `goto_count`, `tally_show`, `phases`, `errors`, `status` | mapped |
| 3 | "`phase_prompts/` (snapshotted prompt text per phase, append-only per attempt)" | existing copy in `run-health-emit.sh`, kept and tested | mapped |
| 4 | "`run_health.json` schema defined and versioned" | `run-health-schema.md` plus `schema_version` 1 | mapped |
| 5 | "`phase_prompts/` snapshotted before any retry overwrites them" | `phase.md` then `phase.attempt-N.md` | mapped |
| 6 | "Ledger sealed at run exit before forensics spawns" | `--seal` on every return path in both skills | mapped |
| 7 | "Artifacts are gitignored (not committed)" | existing `.gitignore` `.soleur/` plus check-ignore test | mapped |
| 8 | "Unit tests for schema + emission" | `run-health-emit.test.sh` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `run-health-schema.md` | "`run_health.json` schema defined and versioned" | asked |
| `schema_version` and seal fields in `run-health-emit.sh` | "`run_health.json` schema defined and versioned" | asked |
| `--seal` instead of a phase-name heuristic | "Ledger sealed at run exit before forensics spawns" | asked |
| `goto_count` from session-state and `tally_show` from `pipeline-tally.sh show` | "`run_health.json` (goto counts, gate decisions, which phases errored, exit status)" | asked |
| Append-only `phase_prompts/` | "`phase_prompts/` snapshotted before any retry overwrites them" | asked |
| `one-shot/SKILL.md` calls | "Instrument `one-shot` and `test-fix-loop` to emit structured run-health artifacts at run exit" | asked |
| `test-fix-loop/SKILL.md` calls | "Instrument `one-shot` and `test-fix-loop` to emit structured run-health artifacts at run exit" | asked |
| check-ignore assertion | "Artifacts are gitignored (not committed)" | asked |
| `run-health-emit.test.sh` extensions | "Unit tests for schema + emission" | asked |
| `--discover` | — | inferred — preflight Check 10 executes `discoverability_test.command` with the repo read-only and a 15s cap, so the probe has to be a temp-dir write that prints a literal |
| Producer-array wiring test | — | inferred — `test-fix-loop/SKILL.md` already says it must emit and does not call the helper; a presence test is the enforcement contract that stops that regression |
| Phase-token refusal | — | inferred — the phase string is interpolated into a path under the run directory; refusing a token that can leave that directory is the trust-boundary check |
| `run_health_dir:` line in session-state | — | inferred — `one-shot` drops the planning subagent's context, so the directory has to be on disk or later steps write a second ledger |
| Fail-open exit 0 | — | inferred — the suite already on `origin/main` asserts a missing-arg exit of 0, and a non-zero exit would stop the pipeline the record must not stop |
| Step-invocation snapshot instead of the whole skill file | — | inferred — the bytes that differ per phase are the step id, child skill, and args; the skill file is already in git |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 5 | Estimated changed lines: 400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `plugins/soleur/skills/one-shot/references/run-health-schema.md` documents schema version 1, including `goto_count`, `tally_show`, `phases`, `errors`, `status`, `sealed`, and `completed_at`. `run-health-emit.sh` writes `schema_version` 1.
- [ ] A second call with the same phase and a new `--prompt-file` leaves `phase_prompts/<phase>.md` unchanged and writes `phase_prompts/<phase>.attempt-2.md`.
- [ ] `--seal` with `completed`, `failed`, or `budget-capped` sets `sealed` true, `completed_at`, and that status. `--phase 8 --status completed` without `--seal` leaves `sealed` false. A later phase upsert does not clear `sealed` or the terminal status.
- [ ] `git check-ignore -q -- .soleur/runs/example/run_health.json` and the same for `.soleur/runs/example/phase_prompts/0.md` both exit 0, from the existing `.gitignore` `.soleur/` rule, with no new ignore line.
- [ ] `bash plugins/soleur/scripts/run-health-emit.test.sh` exits 0 and prints `fails=0`. The same file asserts each producer skill has a `bash` line containing `run-health-emit.sh` and `--seal`.
- [ ] `one-shot` records `run_health_dir:` in the schema's call list and seals on every return path from the parent context. `test-fix-loop` calls the helper at the phase ids it names and seals once before the diagnostic report.
- [ ] `wc -c plugins/soleur/skills/one-shot/SKILL.md` is at most 51950. The ceiling key `one-shot` in `plugins/soleur/test/skill-body-budget.json` is unchanged at 52000.
- [ ] This plan's `closes` is 12573 only. The parent epic stays open.

## Test Scenarios

- Given a temp run dir, when the helper is called with `--phase 0 --status started --prompt-file` a fixture, then `run_health.json` has `schema_version` 1 and one phase. (`unit`)
- Given that ledger, when the same phase is sent `--status completed` with no new prompt, then `phases` length stays 1. (`unit`)
- Given an existing `phase_prompts/0.md`, when the same phase is sent a different prompt file, then `0.md` still has the first text and `0.attempt-2.md` has the second. (`unit`)
- Given a ledger, when `--phase 8 --status completed` is sent without `--seal`, then `sealed` is false and `completed_at` is absent. (`unit`)
- Given a ledger, when `--phase exit --status failed --seal` is sent, then `sealed` is true, `status` is `failed`, and `completed_at` is set. A following `--phase later --status completed` leaves `sealed` true and `status` `failed`. (`unit`)
- Given `--seal` before any phase row, when a phase upsert follows, then `sealed` stays true. (`unit`)
- Given a fixture session-state with two lines `retry-budget-ruling: verb=goto phase=work` and one prose line that only says `verb=goto`, when `--seal --session-state` that file is used, then `goto_count` is 2. A missing file yields `goto_count` 0 and does not fail the process. (`unit`)
- Given `--import-tally` and a `PATH` stub named `pipeline-tally.sh` that prints `tally: seats=3 ci_cycles=1 fix_rounds=0 agent_rounds=2 ci_wall_s=unmeasured`, when `--seal` runs, then `tally_show` contains that line. The real `pipeline-tally.sh` is not edited. (`unit`)
- Given the repo root, when `git check-ignore -q` is run on `.soleur/runs/example/run_health.json` and `.soleur/runs/example/phase_prompts/0.md`, then both exit 0. (`unit`)
- Given the producer array of the two skill paths, when either file loses its `bash` line that contains `run-health-emit.sh` and `--seal`, then the test exits non-zero. An empty array exits non-zero. A sentence that names both tokens and does not run `bash` exits non-zero. (`unit`)
- Given a phase token `../x`, when the helper is invoked, then it exits 0, writes nothing, and prints `run-health-emit:` on stderr. (`unit`)
- Given missing required args, when the helper is invoked, then the exit code is 0. (`unit`)
- Given `--discover`, when it runs, then stdout contains `ok` and the repo gains no `.soleur/runs` file from that invocation. (`unit`)

No browser flow and no external API. `soleur:qa` has nothing to drive beyond these commands.

## Success Metrics

- Both skills call the helper, measured by the producer-array test, not by a live model run.
- A sealed fixture ledger keeps `sealed` true across a later upsert.
- `bash plugins/soleur/scripts/run-health-emit.sh --discover` prints `ok`.

## Dependencies & Risks

- Skill text is the producer. Nothing in-process can force a model to run the line. The test locks the line's presence. It does not prove a future session obeyed it.
- Editing `one-shot/SKILL.md` can break byte pins. The edit stays inside a new `<!-- run-health-emit:start -->` block and must not touch the pinned paragraphs named above.
- `--import-tally` shells out to `pipeline-tally.sh`. A missing tally file is stored as the script's own `UNKNOWN` line, not as a fatal error.
- Parent-epic retention (purge of old run dirs) is not this issue's ask. No purge job is added here.
- Draft PR 12996 is this branch's empty draft, not a second implementer. Foreign `test-all.sh` processes seen at planning time belong to other worktrees and do not edit these files.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

Reviewed-Coverage: sequential-fallback. Domain leaders were not spawned. Assessments below are carried forward from `knowledge-base/project/brainstorms/2026-11-10-session-retrospective-compound-brainstorm.md` and checked against this plan's file list.

Product/UX Gate does not run. The file list is two skill documents, one schema note, and one shell helper plus its test. The UI-surface term list excludes SKILL.md and orchestration docs. No `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` path. Tier none. Pencil is not applicable. No brainstorm specialist was named for a marketing or design agent.

### Engineering

**Status:** reviewed
**Assessment:** The hidden prerequisite is emission, and the helper already exists. The risk is wiring that looks done because the loop has a paragraph, plus a seal tied to phase names (`8`, `exit`, `ship`) that can close the ledger at the wrong moment. Explicit `--seal` and a presence test are the smaller fix. No new substrate.

### Legal

**Status:** reviewed
**Assessment:** Prompt snapshots are an unbounded local copy of whatever the session saw. They stay on the machine under `.gitignore` `.soleur/`. This plan does not send them to a new vendor and does not add a schema column. GDPR gate output is in Research Insights. No Art. 9 column. Retention purge stays on the open parent epic, not in this diff.

## Research Insights

Reviewed-Coverage: sequential-fallback. Repo research, learnings, community discovery, functional overlap, domain review, the scoped advisor, and plan review ran in this process. No independent subagent ran. No community artifact was installed.

**Premise Validation.** Issue 12573 is OPEN, title `feat: instrument one-shot/test-fix-loop to emit run_health.json + phase_prompts/ (Phase 1 prereq)`, `closedByPullRequestsReferences` empty. Parent epic 12532 is OPEN; this plan does not close it. `git cat-file -e origin/main:plugins/soleur/scripts/run-health-emit.sh` and the matching test file both succeed. `git grep` on `origin/main` under the two skill directories finds no `run-health-emit`, `run_health`, or `phase_prompts` call. The schema path named by the loop is absent (`plugins/soleur/skills/one-shot/references/` lists three other files). `.gitignore` `.soleur/` ignores `.soleur/runs/example/run_health.json` and `.soleur/runs/example/phase_prompts/0.md`. Collision precheck exit 10 names PR 12996, whose head is this branch and whose file list is empty, plus `test-all.sh` pids in other worktrees. Not a foreign implementation of this issue. ADR keyword search for a rejected run-health emitter found no Decision that forbids a local JSON ledger. `pipeline-tally.sh` and `retry-budget-ruling.sh` are the existing counters; this plan copies them at seal instead of replacing them.

**Property List.**

- P1. A consumer can parse `run_health.json` against a documented version.
- P2. Prompt text for a phase survives a retry that would otherwise overwrite it.
- P3. At run exit the ledger is sealed, and a later write does not unseal it, before a forensic reader uses it.
- P4. The artifacts are not committed.
- P5. Schema and emission have unit tests, including a test that the two skills call the helper.
- P6. The record includes a goto count, the tally's gate line, which phases errored, and the exit status.

**Cut List.**

- New `.gitignore` line for `.soleur/runs/` → P4 → `.gitignore` `.soleur/` already matches, verified with `git check-ignore -v`.
- Second emitter or a hook that wraps the agent → P6 → `run-health-emit.sh` is the writer; the skills are the callers.
- Duplicate schema file under `test-fix-loop/references/` → P1 → the loop already points at `one-shot/references/run-health-schema.md`.
- New goto/gate counter → P6 → `retry-budget-ruling.sh` writes `verb=goto` into session-state, and `pipeline-tally.sh show` prints the gate line.
- Full skill-file snapshot each phase → P2 → the step invocation is what differs; the skill body is in git.
- TTL purge job → not a property of issue 12573's acceptance list. The open parent epic still owns retention. Not built here.
- Magic phase-name seal → P3 → it seals on the name `8` or `exit` even when the run is not done. Replaced by `--seal`, not kept beside it.

**Value proposition.** Not a cost-saving claim. 0.6c does not apply.

**Repo research.** Writer: `plugins/soleur/scripts/run-health-emit.sh` (upsert by phase name, append-only prompt copy, fail-open exit 0, seal only when the phase name is in `8|ship|done|final|exit|terminate`). Tests: five cases in `run-health-emit.test.sh`, no schema version, no seal, no ignore, no skill-text check. Weight row already present (`scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`). Consumer already on main: `plugins/soleur/agents/engineering/review/session-forensics-analyst.md` optional `run_health` input. Tally ledger lives under the session-state root (`plugins/soleur/scripts/lib/session-state.sh` `_session_state_root`), not under `.soleur/runs/`. `show` prints `tally: seats=...`.

**Learnings.** A guard that cannot be driven red is vacuous (`knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`). A prose duty that names a file the tree does not contain is the pre-backfill state (`knowledge-base/project/learnings/2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md`). Plans must reconcile spec claims with the tree (`knowledge-base/project/learnings/best-practices/2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`). Glossary **Run** means a trigger-to-finish execution that does not wait on a person mid-flight; this ledger describes that execution, not a human session.

**External research.** Skipped. The writer, the tally, and the two skills are local. No new framework.

**Community discovery.** No uncovered stack from the signature table (`pubspec.yaml`, `Cargo.toml`, `mix.exs`, `go.mod`, `Package.swift`, `build.gradle`, `composer.json` are absent).

**Functional overlap.** No install. The contract is this repo's helper and these two skills. A community skill would not emit this schema.

**CLAUDE.md.** Client/server import boundary and Button primitives are out of scope. This diff does not touch `apps/web-platform`.

**GDPR gate (advisory).** The gate does not inject a checklist into the plan template. Recorded here.

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Planned paths examined against the canonical regex `^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)`: 5 paths, 0 matches. `gdpr-gate: path scan complete — 5 examined, 0 matched`.

- `GDPR-Art-6`: no new schema column. No finding.
- `GDPR-Art-5e`: no new PII table. Local prompt copies have no purge in this diff. Suggestion only. Retention stays on the open parent epic.
- `GDPR-Art-17` and `GDPR-Art-17-caller`: no foreign key to `users`. No finding.
- `GDPR-Chapter-V`: no new vendor env or SDK. Copies stay on the machine that already held the session. No finding.
- `GDPR-Art-9`: no special-category column name. Not Critical. No compliance issue.

**Advisor (sequential, same process).** Riskiest phase is the `one-shot/SKILL.md` edit. The change that avoids rework: a short call block, history sentences removed so the file stays under the byte ceiling, pinned paragraphs untouched, and a test that fails when the `bash` line or `--seal` is missing. Second change: do not seal from the phase name, or a mid-run phase called `exit` closes the ledger early.

**Probes run 2026-11-20.** `bash plugins/soleur/scripts/run-health-emit.sh --discover` prints `run-health-emit: unknown arg --discover` and exits 0. It does not print `ok`. That flag is part of this change. `bash plugins/soleur/scripts/pipeline-tally.sh show` prints `tally: seats=0 ci_cycles=0 fix_rounds=0 agent_rounds=1 ci_wall_s=unmeasured` and exits 0. `git check-ignore -v` attributes both artifact paths to `.gitignore` line `.soleur/`. The discoverability command contains none of `|`, `;`, `&`, `<`, `>`, `$`, or a backtick. `credentials_required` is omitted. The field is not set to the word none.

**Plan review (sequential-fallback).** DHH, Kieran, and code-simplicity, plus architecture and spec-flow because the threshold is `single-user incident`. Named-panel scan: no UI-surface files, so no UX lead. Tooling files make the CTO devex lens relevant; it was not spawned. Findings applied here: the one-shot procedure moves into the schema file because the skill has 5 bytes of spare; seal status tokens are enumerated; `goto_count` uses the compact marker; the tally stub matches the measured line shape; the producer check requires a `bash` line; the planning subagent does not call the helper. No property was cut. The devex note (a process wrapper would be a second producer) stays on the cut list. `requires_cpo_signoff` stays true. Live CPO was not spawned.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| The two skills do not emit `run_health.json` or `phase_prompts/` | `one-shot` has no mention. `test-fix-loop` has a prose section and does not call the helper. The schema file it names is absent. The helper and its test exist on `origin/main`. | Wire calls. Add the missing schema file. Extend the helper. Do not rewrite the helper from scratch. |
| Artifacts must be gitignored | `.gitignore` `.soleur/` already ignores `.soleur/runs/` | Prove it with `git check-ignore`. Do not add a second pattern. |
| Ledger sealed at run exit | Seal runs only when the phase name is `8`, `ship`, `done`, `final`, `exit`, or `terminate` | Replace with explicit `--seal`. |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 96 issues. Standalone `jq --arg` against each planned path found no body match. Snapshot removed after the read.

## References & Research

- Helper: `plugins/soleur/scripts/run-health-emit.sh`
- Tests: `plugins/soleur/scripts/run-health-emit.test.sh`
- Tally show shape: `plugins/soleur/scripts/pipeline-tally.sh` `cmd_show`
- Goto marker: `plugins/soleur/skills/one-shot/references/retry-budget-ruling.md`
- Consumer: `plugins/soleur/agents/engineering/review/session-forensics-analyst.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-11-10-session-retrospective-compound-brainstorm.md`
- Open epic spec (not closed by this plan): `knowledge-base/project/specs/feat-12532-degraded-run-forensics/spec.md`
- Decisions: `knowledge-base/project/specs/feat-one-shot-12573-run-health-emit/decision-challenges.md`

## Sharp Edges

A plan whose `## User-Brand Impact` section is empty, contains only a stand-in token, or omits the threshold fails deepen-plan Phase 4.6. This section is filled. The discover command's first token is `bash` and `expected_output` is the literal `ok`. Catalogue `plan-sharp-edges.md` was read through its last line and applied above: byte ceiling, status vocabulary, compact goto marker, tally line shape, scoped writer grep, and a `bash` invocation check. At `single-user incident` the next step is `soleur:deepen-plan`, which this pipeline runs after the plan artifacts are saved. Technical rows in `decision-challenges.md` are `pending - assumed` because this subagent cannot spawn `soleur:engineering:cto`. The pre-work gate in `one-shot` is what rewrites those cells.
