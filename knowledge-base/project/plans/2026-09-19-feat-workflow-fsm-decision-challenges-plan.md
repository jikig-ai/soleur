---
title: "feat: resolve the three workflow-FSM decision challenges (postmerge -> work, brainstorm sub-step collapse, measured Sharp Edges saving)"
date: 2026-09-19
slug: feat-workflow-fsm-decision-challenges
branch: feat-one-shot-8325-fsm-decision-challenges
issue: 8325
closes: 8325
type: feat
priority: P2
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

## Overview

Issue #8325 surfaced three places where evidence gathered while implementing and reviewing the workflow-FSM remediation (PR #8301, ADR-229, deployed v0.279.0) bears on decisions the operator had already made. The operator ruled on 2026-09-19: §1 and §2 are delegated to the data-backed decision recorded in the invocation, §3 is "measure first". This plan implements those three rulings and nothing else.

§1 declares the `postmerge -> work` recovery edge in the canonical edge set, mirrors it in the derived view, corrects the doc comment that currently records the recovery edge on the `ship` node, and re-baselines the classifier numbers in ADR-229.

§2 makes the offline classifier honest about `compound` being a designed sub-step of `brainstorm` (the brainstorm skill invokes compound then hands off to plan) without adding `brainstorm -> compound` or `compound -> plan` to the edge set, which would legitimise `review -> compound -> plan` ship skips. The mechanism is a sub-step map in the TS const, mirrored in the JSON view, consumed by the classifier before pairing, and surfaced as a `substep=` count.

§3 builds an offline, read-only measurement script that reads local Claude Code session transcripts and reports how many assistant turns elapse between a `soleur:plan` invocation and the first Read of the extracted Sharp Edges catalogue, so the per-turn cache-read saving the extraction was kept for becomes a measured number in ADR-229 rather than a plausible one.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed); no `spec.md` exists for this branch (one-shot entered `plan` directly).

The decisions are made; this plan does not re-open them. What it adds is the implementation shape, the measured baseline each change must reproduce, and the evidence gathered at plan time about the transcript record shape that the §3 parser depends on.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (verified at plan time) | Plan response |
|---|---|---|
| `bun test plugins/soleur/test/workflow-fidelity.test.ts` passes 73 tests | 83 tests pass today (`Ran 83 tests across 1 file`) | Gate floor is 83 + new tests, not 73 |
| Classifier live reading `undeclared=622 sessions=1275 pairs=5021 nonnode=4013 read=10459` | Same day, later: `undeclared=622 sessions=1275 pairs=5021 nonnode=4014 read=10462 dropped=0` (log grows) | ACs pin structure and CI-safe behaviour; the live numbers are operator-machine snapshots recorded in the PR body |
| Pre-extraction proxy k' = turns to the first Read/Write of a `knowledge-base/project/plans/` file measures "turns before the pass" | Since ADR-176 (2026-08-10) `plan` Phase 0.7 writes a skeleton **before** the research fan-out, so the first plans/ write lands early: measured median 7.5 turns (n=24), i.e. it measures "turns before research", not "turns before the pass". Also, in this harness mode file writes often go through `Bash` heredocs, which a Read/Write/Edit-only proxy misses (6 of 25 runs were invisible until `Bash` `input.command` was included) | Keep k' as specified (it is what the operator asked for) **and** report a second proxy k'_ac = turns to the Write/Edit that lands `## Acceptance Criteria` in the plans/ file — Phase 6.5 runs immediately after that, so it is the faithful pre-extraction stand-in (measured median 45, n=17). The proxy match includes `Bash` commands naming the path. The decision rule applies to the direct post-extraction k |
| Assistant records carry `message.usage.cache_read_input_tokens`; Read tool_use blocks carry `input.file_path` | True. But **one API turn is split across several `assistant` records** (one per content block, same `requestId`, same `message.id`, identical `usage`); the `tool_use` block is usually not in the first record of its turn. Counting records, or de-duplicating by first-seen `requestId` and reading only that record, silently misses the invocation (measured: a first-record dedupe found 0 of 20 subagent plan runs) | The parser groups records by `.requestId // .uuid` and merges their `tool_use` blocks before searching; a turn = one group. Pinned by a fixture whose invocation sits in the third record of its turn |
| Transcripts live at `~/.claude/projects/<slug>/*.jsonl` | Top-level session files are there, but **20 of 25 local plan runs live in subagent transcripts** at `<slug>/<session-uuid>/subagents/agent-<id>.jsonl` (the one-shot planning phase runs `plan` inside an Agent). Those records carry `isSidechain: true`. A worktree-launched session gets its own slug (`<slug>--worktrees-<name>`) | Scan `<projects>/<slug>/**/*.jsonl` and `<projects>/<slug>--worktrees-*/**/*.jsonl` recursively (top-level and `subagents/`), never filter on `isSidechain`, and derive `<slug>` from the main checkout path (`git rev-parse --git-common-dir`), so the script finds the same corpus from a worktree |
| Local transcripts give a per-run k distribution | Local retention is short: the 30 top-level sessions + 702 subagent transcripts span 2026-09-17 → 2026-09-19; `cleanupPeriodDays` is unset. Only 1 of 25 plan runs carries the catalogue Read today. The extraction merged 2026-09-19T00:16:33Z as `50af0436f`, but the merge time is the wrong discriminator: the SKILL.md text the harness loaded arrives as the `user` record right after the invocation, and it names `references/plan-sharp-edges.md` in exactly **2** of the 25 runs (both 2026-09-19T18) — the other 5 runs invoked after the merge loaded the pre-extraction body (stale plugin checkout), so they are `pre`, not "skipped" | Classify each run by the loaded skill text, not by a timestamp: `post` iff the text names the catalogue. No `MEASURE_LANDED_AT`. The summary reports `post=`, `post_skipped=`, `pre=`, `unknown=` so n is never hidden; ADR-229 records n with the numbers; the ≥ 2× break-even rule is applied to the direct k as ruled, with n stated beside it and k'_ac reported as corroboration (not as a substitute); the n-floor question is recorded as a User-Challenge in `knowledge-base/project/specs/feat-one-shot-8325-fsm-decision-challenges/decision-challenges.md` |
| Plan runs start at a `Skill` tool_use with `input.skill == "soleur:plan"` | Also true for an operator-typed `/soleur:plan`, which lands as a `user` record carrying `<command-name>/soleur:plan</command-name>` and no assistant `Skill` block (3 local files carry that form and are invisible to a tool_use-only parser — CTO assessment) | Both forms start a run; for the slash form the start ordinal is the first assistant turn after that record minus one, so k counts the same thing in both |
| The catalogue Read path is `plugins/soleur/skills/plan/references/plan-sharp-edges.md` | Only when the skill loads from a source checkout. An installed plugin loads from `~/.claude/plugins/cache/…/<hash>/skills/plan/references/plan-sharp-edges.md` (no `plugins/soleur/` prefix); all 10 local catalogue Reads are checkout-shaped today, so the prototype could not see this | Match the suffix `skills/plan/references/plan-sharp-edges.md`; a fixture with the cache-shaped path must count as `post` |
| `scripts/*.test.sh` suites are auto-discovered | `scripts/test-all.sh` globs only `scripts/lib/*.test.sh`; top-level `scripts/*.test.sh` are registered by explicit `run_suite` lines (the classifier and ratchet suites are, in the `#8302 / ADR-229` block), and `scripts/lint-orphan-test-suites.sh` fails on an unregistered suite | Register `scripts/measure-plan-sharp-edges-turns.test.sh` in that block in the same commit |

## Problem Statement

- ADR-229's edge set records the post-merge recovery edge on the wrong node: `ship -> work` is documented as "(postmerge failed)", while the observed recovery path is `postmerge -> work` (7 sessions; `ship -> work` occurs 2 times in the same corpus). The classifier reports the real path as undeclared.
- The classifier's largest "undeclared" edge, `brainstorm -> compound` (127 in today's live reading; 125 at ADR-229 adoption) plus its tail `compound -> plan` (111 today; 109 at adoption), is the brainstorm skill's own designed step (`plugins/soleur/skills/brainstorm/SKILL.md`, "Run `skill: soleur:compound` to capture learnings from the brainstorm session", then the plan handoff). ADR-229 misreads `compound -> plan` as second-feature chaining. 238 of 622 undeclared rows are this one designed handoff, which buries the class the classifier exists to surface (review skips).
- The Sharp Edges extraction was kept on a per-turn argument ("~58k × k cache-read tokens per run, k unmeasured, break-even k≈8"). No instrument exists to measure k.

## Proposed Solution

### §1 — declare `postmerge -> work`

- `plugins/soleur/lib/workflow-fidelity.ts` › `DECLARED_TRANSITIONS`: `postmerge: ["work"]`. `ship: ["postmerge", "work"]` is unchanged (`ship -> work` remains the pre-merge failure edge — preflight/QA findings that need implementation before merge).
- Doc comment on `DECLARED_TRANSITIONS`: four operator-approved back-edges — `review -> work` (findings to implement), `ship -> work` (pre-merge gate failed), `postmerge -> work` (post-merge verification failed; declared 2026-09-19 on #8325: 7 sessions, 5 re-enter `work -> review -> compound -> ship -> postmerge`, 2 end at `work`, none skip `ship`), `work -> plan` (implementation invalidated the plan). Remove the "REJECTED as redundant" sentence.
- `.claude/workflow-transitions.json` › `transitions.postmerge`: `["work"]`.
- `plugins/soleur/test/workflow-fidelity.test.ts`: `declaredTransitions("postmerge")` → `["work"]` (the `toEqual` already pins that nothing else is declared); rename/extend "the three operator-approved back-edges" to four and add `postmerge -> work`; replace "postmerge -> work is NOT declared" with the positive assertion; add one line `expect(mandatorySuccessors("postmerge")).not.toContain("work")` inside the existing "mandatorySuccessors stays forward-only" test (a back-edge never renders as a directive).
- ADR-229 `## Decision`: the line "Declared back-edges: `review → work`, `ship → work`, `work → plan`." lists four with `postmerge → work`, and the sentence after it ("…considered and rejected as redundant…") gains the dated amendment "Amended 2026-09-19 (#8325): declared; see Consequences." The ADR keeps its ordinal and its history.

### §2 — collapse `compound` as a brainstorm sub-step in the classifier

- `plugins/soleur/lib/workflow-fidelity.ts`: new exported const beside `DECLARED_TRANSITIONS`:

  ```ts
  /**
   * Node skills that another node's SKILL.md invokes as a designed SUB-STEP of
   * its own run, keyed by the invoking node. `brainstorm` runs `compound` to
   * capture learnings and then hands off to `plan`, so the invocation log
   * shows `brainstorm compound plan` for the designed handoff. The classifier
   * drops a record whose skill is a sub-step of the PREVIOUS KEPT node before
   * pairing, so that sequence pairs as `brainstorm -> plan`. This is NOT an
   * edge: `brainstorm -> compound` and `compound -> plan` stay undeclared, so
   * `review -> compound -> plan` (a ship skip) is still reported. Mirrored in
   * .claude/workflow-transitions.json under `sub_steps` (parity-pinned).
   *
   * To add an entry: the key and every value must be DECLARED_TRANSITIONS nodes
   * (a non-node is removed by the classifier's node filter first, so the entry
   * would be dead); a value must not be a declared successor of its key (the
   * collapse would silently delete a declared pair from `pairs`). Edit this
   * const first, mirror the JSON, then run
   * `bun test plugins/soleur/test/workflow-fidelity.test.ts`.
   */
  export const DECLARED_SUB_STEPS: Readonly<Record<string, readonly string[]>> = {
    brainstorm: ["compound"],
  };
  ```

  (The brief's `BRAINSTORM_SUB_STEPS = ["compound"] as const` is the same fact; the map form is chosen because the JSON mirror is keyed by node and the classifier is generic over `sub_steps[<previous kept node>]`, so parity is one deep-equal instead of a hand-built object.)
- `.claude/workflow-transitions.json`: add `"sub_steps": { "brainstorm": ["compound"] }` beside `transitions`; extend `_comment` with one sentence: "`sub_steps` mirrors `DECLARED_SUB_STEPS` (same parity block, same edit-TS-first rule; the entry rules are listed on the TS const); the classifier drops a sub-step record before pairing and reports the count as `substep=`."
- `plugins/soleur/test/workflow-fidelity.test.ts` › "declared-transitions derived view parity": the deep-equal canonical becomes `{ transitions: DECLARED_TRANSITIONS, sub_steps: DECLARED_SUB_STEPS }` (so a view missing `sub_steps`, or carrying an extra key, reds in both directions); add a view→const direction loop for `sub_steps` mirroring the existing one for `transitions`; add exactly three invariant tests, iterating the **const** (`DECLARED_SUB_STEPS`, not the view), each named by its rule in words: "every sub_steps key is a lifecycle node", "every sub_steps value is a lifecycle node — a non-node is removed by the classifier before the collapse, so the entry would be dead", "a sub_steps value is not a declared successor of its key — the collapse would delete a declared pair"; `plan -> ship` absence assertion unchanged.
- `scripts/classify-workflow-transitions.sh`:
  - Fail closed on a view whose `sub_steps` is missing **or not an object** (`jq -e '.sub_steps | type == "object"'` on the view before the main pass; same FATAL/rc 2 shape as the missing view: "declared view carries no `sub_steps` object — stale mirror; edit DECLARED_SUB_STEPS first, then mirror"). A tolerant `// {}` would silently reproduce today's numbers on a stale mirror, and `"sub_steps": null` or `[]` passes a bare `has()` check with the same silent result.
  - In the jq pass, after `$nodes` are grouped by session and sorted by `ts`, reduce each session into `kept` records with an explicit first-record branch: `if (.kept | length) == 0 then .kept += [$r] elif (($SUB[.kept[-1].skill] // []) | index($r.skill)) != null then .sub += 1 else .kept += [$r] end`. The branch is not optional — `.kept[-1]` on an empty array is `null` and `$SUB[null]` throws, which `// []` does not rescue. Previous **kept** node, so `brainstorm compound compound plan` drops both. Pairs are formed from `kept`. Count `substep` = total dropped across sessions. Equal-second `ts` ties keep file order (`sort_by` is stable).
  - Order of filters is load-bearing: non-node removal first, then sub-step drop (`brainstorm one-shot compound plan` → `brainstorm -> plan`, `substep=1`).
  - `--summary` line becomes `undeclared= sessions= pairs= nonnode= substep= read= dropped=`; the null-reading line gains `substep=0`; `--help` and the PROPERTY header comment describe the sub-step collapse.
- `scripts/classify-workflow-transitions.test.sh`: 12 new cases — exactly the twelve classifier scenarios in `## Test Scenarios` (the null-reading `substep=0` key gets its own `--summary` case: the existing absent-log case runs default mode and never prints the line); `MIN_CASES` literal raised to 28 (keep the literal-plus-contiguous-assignment shape `guard-vacuity-floor.test.sh` slices).
- ADR-229 `## Consequences`: correct the interpretation bullet — `compound → plan` is the tail of `brainstorm → compound → plan` (live today: 108 of 111; 2 have no predecessor, 1 follows `ship`), the designed handoff; `plan → compound` (31) is likewise `plan`'s own exit-gate compound (`plugins/soleur/skills/plan/SKILL.md`, "Run `skill: soleur:compound` to capture learnings from the planning session", followed by `work` in 13 of the 16 cases with a successor), not second-feature chaining; `ship → plan` and `postmerge → plan` are the second-feature starts — and replace the trailing pointer "Whether to declare `brainstorm → compound` is the edge-set question recorded in decision-challenges §2" with "Resolved 2026-09-19 (#8325): not declared; collapsed as a classifier sub-step (`DECLARED_SUB_STEPS`)". Add a re-baseline bullet that opens "Re-baselined 2026-09-19 (#8325, after the sub-step collapse and `postmerge → work`):" with the post-change live summary line and the `substep=` count, so the two baselines read in order.

### §3 — measure the per-turn saving

New `scripts/measure-plan-sharp-edges-turns.sh` (repo tooling, never under `plugins/`, ADR-179 d4; offline; read-only; no network; stdout only):

```text
usage: measure-plan-sharp-edges-turns.sh [--rows]
  default  one key=value summary line on stdout, keys in four groups:
           corpus  files= parsed= dropped= window_from= window_to=
           runs    runs= post= post_skipped= pre= unknown=
           direct  median_k= p10_k= p90_k= saving_tokens_per_run=   (over post runs only; na when post=0)
           proxies median_k_first= n_k_first= median_k_ac= n_k_ac=  (pre runs; -1 in rows means absent)
  --rows   before the summary, a '# kind k k_first k_ac turns_in_window' header line then one TSV row per run
env: MEASURE_TRANSCRIPT_ROOT=<dir>  read ONLY that tree (skips slug derivation); tests use it
     MEASURE_PROJECT_PATH=<path>    derive the slug from this path instead of the checkout's common dir
exit: 0 measured (a null reading exits 0 and prints null_reading=1); 2 could not measure (jq missing, unreadable root)
```

- **Corpus.** Without the override: `$HOME/.claude/projects/<slug>` plus every directory `find "$HOME/.claude/projects" -maxdepth 1 -type d -name "<slug>--worktrees-*"` returns — exactly those, never `<slug>*` (a sibling project whose path starts with the slug would be pulled in); enumeration via `find`, never a bare glob (an unmatched glob hands the literal pattern to `find` and fails under `set -e`). `<slug>` is `${MEASURE_PROJECT_PATH:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}` (so a worktree resolves to the main checkout's slug) with every character outside `[A-Za-z0-9]` replaced by `-` (Claude Code maps `/`, `.` and `_` alike: `/.worktrees/` → `--worktrees-`); the derivation is a function tested on the literal `/tmp/a.b_c/x` → `-tmp-a-b-c-x`. Files: every `*.jsonl` under those directories, recursively (top-level sessions and `<session>/subagents/agent-*.jsonl`). Cheap pre-filter: skip files with no `soleur:plan` byte string (`grep -qF`), then run **one jq invocation per file** (`jq -R -n '[inputs | fromjson?] | …'`) so file boundaries are preserved (a window ends at EOF of its own file) and a malformed line is dropped and counted, never fatal; per-file rows are concatenated and the summary computed over the concatenation.
- **Turn.** `assistant` records with `isApiErrorMessage != true`, grouped by `.requestId // .uuid` in first-seen file order (measured: 1,718 distinct `requestId` = 1,718 distinct `message.id`, so no middle fallback); a group's `tool_use` blocks are the union over its records. Never filter on `isSidechain`.
- **Run.** A run starts at (a) an assistant turn carrying at least one `Skill` tool_use with `input.skill == "soleur:plan"` — a turn with several such blocks starts exactly one run — or (b) a `user` record whose text carries `<command-name>/soleur:plan</command-name>` (operator-typed; 3 local files carry this form), whose start ordinal is the ordinal of the first assistant turn after it minus one, so k counts the same thing in both forms. The window ends at the next run start in the same file or EOF; `turns_in_window` = number of assistant turns from the start ordinal (exclusive) to the window end.
- **Which SKILL.md was loaded.** The harness delivers the skill body as `user` record(s) between the invocation turn and the next assistant turn — nothing else can interleave. Concatenate those records' text (`message.content` as a string; `text` blocks; `tool_result` blocks' `content` as a string or as `[].text`) and select the record(s) carrying the harness preamble `Base directory for this skill`; `extracted = true` iff **that** text contains `references/plan-sharp-edges.md` (scoping to the preamble record matters: `plugins/soleur/skills/compound/SKILL.md` and any prompt quoting ADR-229 also name the literal). No record-count window. Content-derived booleans only, never printed. Measured: 2 of 25 local runs are `extracted` (both 2026-09-19T18); the other 5 runs invoked after the merge loaded the pre-extraction body (stale plugin checkout) and are `pre`. If no preamble record is found, `kind = unknown`.
- **Per run.** `k` = ordinal of the first `Read` whose `input.file_path` ends with `skills/plan/references/plan-sharp-edges.md` (suffix, so the installed-plugin cache path `…/plugins/cache/…/<hash>/skills/plan/references/plan-sharp-edges.md` matches and `…/work/references/plan-sharp-edges.md.bak` does not) minus the start ordinal; `k = 0` is legal (same turn, parallel tool call) and enters the percentiles; `-1` means absent. `k_first` = first turn with a `Read`/`Write`/`Edit` whose `input.file_path` contains `knowledge-base/project/plans/`, or a `Bash` whose `input.command` contains it (the brief's k'; the `Bash` branch is kept on evidence — 6 of 25 local runs are invisible without it in this harness mode). `k_ac` = first `Write`/`Edit` to such a path whose `input.content`/`input.new_string` contains `## Acceptance Criteria` (the faithful pre-extraction stand-in, P7). `kind` = `post` (extracted, catalogue Read found), `post_skipped` (extracted, none — the pass was skipped), `pre` (not extracted; the proxies carry their own n, so no `pre_nohit` split), `unknown` (no preamble record; excluded from every statistic, counted).
- **Summary line.** `runs=N post=N post_skipped=N pre=N unknown=N median_k=X p10_k=X p90_k=X saving_tokens_per_run=Y median_k_first=X n_k_first=N median_k_ac=X n_k_ac=N window_from=YYYY-MM-DD window_to=YYYY-MM-DD files=N parsed=N dropped=N`. `median_*` is the conventional median (midpoint of the two middles at even n, one decimal when fractional); `p10_k`/`p90_k` are nearest-rank (rank = ceil(p·n)) as the brief asked — at n ≤ 3 they are the min and max, and the ADR sentence says so; all three over `post` runs only, `na` when `post=0`. `saving_tokens_per_run` = `CATALOGUE_TOKENS × median_k` with `CATALOGUE_TOKENS=58000 # ADR-229, measured 2026-09-18` named once at the top of the script (`na` when `median_k` is). `window_from`/`window_to` are the earliest and latest run-start dates. Null reading (no transcript file, or zero runs): stderr prints `SOLEUR_PLAN_SHARP_EDGES_NULL_READING slug=<slug> files=N reason=no_files|no_runs — set MEASURE_TRANSCRIPT_ROOT=<dir> to point at a transcript tree, or MEASURE_PROJECT_PATH=<path> if the slug is wrong` and stdout prints the same key set with zeros/`na` plus `null_reading=1`, exit 0. `unknown>0` prints `WARNING: unknown=N run(s) had no skill-body record between the invocation and the next assistant turn` on stderr.
- **Privacy.** stdout carries numbers, `na`, the fixed key names, the `#` header and the kind tokens only — never `message.content` text, a prompt, a command, or a file path from inside a transcript; stderr names the slug and file counts, never `$HOME` or a transcript path (`input_filename` is never captured into a record). Nothing read is written anywhere; no temp copy of transcript content.
- **Suite** `scripts/measure-plan-sharp-edges-turns.test.sh`: synthesized JSONL fixtures only (`cq-test-fixtures-synthesized-only`) built by a small family of `rec_*` helpers — `rec_assistant_tool_use`, `rec_assistant_text`, `rec_user_text`, `rec_user_command` — each taking a timestamp ordinal and a request id, with any extra top-level field (`isSidechain`, `isApiErrorMessage`, a missing `usage`) passed as a trailing jq-safe `key=value`; no real session line, no UUID-shaped identifiers (`grep -E '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}'` over the suite returns nothing), `agent-t1`-style ids; strictly increasing timestamps. `assert_fixture_dir` copied byte-identical from `plugins/soleur/test/test-helpers.sh` with the same "copied, not sourced" comment as the classifier suite; no `cd` and no `git -C` on fixture paths (zero new sites in `fixture-dir-operand-assert.baseline.txt`); `pass`/`fail` counters with the instrument self-test and a `MIN_CASES` literal floor in the same shape as the classifier suite (its tail is the exemplar); registered in `scripts/test-all.sh` beside the classifier suite, and that block's comment ("these two do not sit under a globbed directory") updated to cover the third suite with a `#8325` citation.
- **Recording.** The work phase runs the script from the worktree and posts the summary line plus the `--rows` table (numbers only) as a comment on #8325 (`gh issue comment 8325 --body-file`). ADR-229 `## Consequences` gets **one sentence** in place of "That is plausibly large and **unmeasured** — no turn telemetry exists": "Measured on <date> with `scripts/measure-plan-sharp-edges-turns.sh` over local transcripts <window_from> → <window_to> (Skill-tool and slash-typed invocations, n stated per number): post-extraction median k = X (p10 X, p90 X — min/max at this n; n = post, post_skipped = M); pre-extraction proxies k'_first median X (n = N) and k'_ac median X (n = N); implied saving X cache-read tokens per run against a break-even of 8 turns; full line and per-run rows in the #8325 comment." Decision rule, applied as ruled: `median_k` ≥ 16 → the sentence ends "kept on measured evidence (#8325 §3 closed)"; `median_k` < 16, or `na` (post=0) → it ends "referred to #<new> for the keep/revert choice" and a one-line follow-up issue is filed (`gh issue create --label action-required --title "Decide keep/revert of the plan Sharp Edges extraction: measured median k=<value> (post=<n>)"`); nothing is reverted in this PR; no keep sentence is written on `na`. The n-floor question is a recorded User-Challenge (`decision-challenges.md`), not a change to the rule. Plan-time prototype reading (not the recorded number): post k=36 (n=1), k'_first median 7.5 (n=24), k'_ac median 45 (n=17); this pipeline's own plan run adds one `post` data point before the work phase measures.

## Technical Considerations

- **Edit the TS const first, mirror second, parity third** (ADR-229; the view's `_comment`). Both §1 and §2 touch the pair; the parity block is the only thing keeping the mirror honest, and it must red in both directions for `sub_steps` exactly as it does for `transitions`.
- **jq scoping trap** already documented in the classifier: bind `$SUB` before piping; `X | has(.k)` rebinds `.`. The reduce over a session must use `$r` for the incoming record and `.kept[-1].skill` for the previous kept node, and must branch on `(.kept | length) == 0` BEFORE the lookup: `$SUB[null]` throws "Cannot index object with null" and `//` does not catch errors (verified with `jq -n '{} as $S | ([]|.[-1].skill) as $k | $S[$k] // []'`). Equal-second `ts` ties (the logger writes second resolution) keep merged-file order — live log first, then archives — a documented one-second ambiguity, not a tested one; fixtures use strictly increasing timestamps.
- **Generator silence** (`2026-03-10-jq-generator-silent-data-loss.md`): no `select()` inside a binding expression in either jq program; the measurement script builds arrays and indexes them.
- **Malformed lines** (`2026-03-18-stop-hook-jq-invalid-json-guard.md`): `-R` + `fromjson?` in both readers; a `dropped=` count makes the loss visible.
- **`jq` is required** in both scripts (checked up front, rc 2), consistent with the classifier.
- **The invocation log lives in the MAIN checkout's `.claude/`**, not the worktree (`2026-09-18-a-plan-can-specify-a-mechanism-the-packaging-boundary-forbids.md`); the classifier reaches it through `incidents_enumerate_log_roots`. A `null_reading=1` summary during work means the enumeration did not reach it — stop and check, do not record a zero.
- **Transcript slug derivation** must not use `git rev-parse --show-toplevel` (returns the worktree path, whose slug is `<slug>--worktrees-<name>`, a different and much smaller corpus); use the common dir's parent, replace every non-alphanumeric character with `-`, and read `<slug>` plus `<slug>--worktrees-*` only.
- **Do not carry `knowledge-base/project/rule-metrics.json`** (`2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md`): take main's copy before the first sync; the aggregator suites regenerate it locally.
- **Process lookup by full command line is banned (AGENTS.md hard rule); `git stash` in worktrees is banned; no new write sites** — both scripts are read-only over their inputs; the only writes are test scratch dirs under `mktemp -d -t` and the committed files listed below.
- **ADR ordinals:** run `bash scripts/check-adr-ordinals.sh` after every sync; ADR-229 is edited in place and no ADR is created.
- **Expected post-change classifier reading** (plan-time simulation against the live log at 2026-09-19 20:48: `read=10462`): `undeclared=379 pairs=4892 substep=129 nonnode=4014 dropped=0` — i.e. undeclared −243 (the 127 `brainstorm -> compound` and 111 `compound -> plan` rows collapse, 7 `postmerge -> work` rows become declared, and the collapse exposes a handful of `brainstorm -> review`/`brainstorm -> brainstorm`-class pairs that were previously hidden behind `compound`), pairs −129 (= `substep`). `ship -> plan` (50) and `postmerge -> plan` (31) remain, as intended. This is a snapshot for the PR body, never a suite assertion — it moves with the log.
- **Portability of the two scripts** (Sharp Edges, #8231 class): external binaries are `bash`, `git`, `find`, `grep`, `jq`, `zcat` (classifier, pre-existing) and `mktemp -d -t` (tests, pre-existing convention) — no `timeout`, `sed -i`, `date -d`, `stat -c` or `readlink -f`; percentiles are computed in jq, not `bc`. The slug derivation uses `git rev-parse --path-format=absolute --git-common-dir` (verified on this checkout: prints `/data/git-repositories/jikig-ai/soleur/.git` from the worktree, whose dirname is the main checkout).
- **PR body authorship:** `ship` is the sole PR-body author (it full-replaces the body from diff analysis), so the measured numbers reach the PR through the ADR-229 diff and the durable artifacts (`decision-challenges.md`, the #8325 issue comment that `work` posts with `gh issue comment`) — `work` never runs `gh pr edit`.
- **Skill description budget:** no `SKILL.md` `description:` edit is planned; Phase 1.8 does not fire.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Declare `brainstorm -> compound` and `compound -> plan` as edges | `compound -> plan` as a general edge legitimises `review -> compound -> plan`, the ship-skip class the classifier exists to catch (ruled out in the brief) |
| Remove `ship -> work` now that `postmerge -> work` is declared | It is operator-approved (#8302) and occurs (2 sessions) as the pre-merge failure path; the brief adds an edge, it does not remove one |
| Read the TS const from bash via `bun -e` instead of extending the mirror | Weighed and not taken at ADR-229 review; this plan keeps the reviewed mechanism and extends its parity block |
| Tolerate a view without `sub_steps` (`// {}`) | A stale mirror would reproduce today's numbers silently — the null-reading class ADR-229 spends a paragraph on |
| Classify pre/post-extraction runs by the merge timestamp of `50af0436f` | Measured wrong: 5 runs after the merge loaded the pre-extraction SKILL.md from a stale plugin checkout; the loaded skill text is the discriminator |
| Measure k from `.claude/.skill-invocations.jsonl` | The invocation log has no turn granularity and no Read events; only the transcripts carry `requestId` and tool_use blocks |
| Put the measurement script under `plugins/soleur/scripts/` | ADR-179 d4: rule/telemetry instrumentation over operator-private data never ships in the plugin |
| Report only the brief's k' proxy for pre-extraction runs | It measures turns-to-skeleton since ADR-176 (median 7.5) and would misstate the pre-extraction baseline as "at break-even"; reporting it beside k'_ac keeps the requested number and the faithful one |
| Sum actual `cache_read_input_tokens` over the k turns instead of 58000 × k (advisor) | The brief defines the implied saving as 58k × k; the constant is named once (`CATALOGUE_TOKENS`) and cited to ADR-229's measurement |
| Cut `k'_first`, `p10`/`p90`, `saving_tokens_per_run` as padding at n≈2 (plan-review, DHH) | Each is output the brief asked for by name; the ADR sentence states "min/max at this n" so the tails are not over-read |
| Revert or keep-and-close §3 in this PR | Ruled out: "measure first"; the keep/revert choice stays with the operator if the number is below 2× break-even |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing at runtime — no plugin runtime code calls `declaredTransitions()`/`isDeclaredTransition()` (ADR-229), and both scripts are operator-run repo tooling. The failure surface is the operator's own reading: a wrong `substep=` or a wrong k would put a wrong number in ADR-229 and mislead the next edge-set or extraction decision.

**If this leaks, the user's [data / workflow / money] is exposed via:** the measurement script reads the operator's private session transcripts. Exposure vector would be printing transcript content or committing a fixture derived from a real session. Both are closed by construction: the script emits only counts/turn ordinals/token integers (pinned by a sentinel test on stdout and stderr), fixtures are synthesized, and no transcript byte is copied to disk.

**Brand-survival threshold:** none — `threshold: none, reason: repo-only tooling and an ADR edit; no customer-facing surface, no sensitive path in the diff (the canonical regex matches none of the files below)`.

## Guard Contract

### Guard 1 — derived-view parity extended to `sub_steps`

**Property.** `.claude/workflow-transitions.json` (minus `_comment`) deep-equals `{ transitions: DECLARED_TRANSITIONS, sub_steps: DECLARED_SUB_STEPS }`, and every `DECLARED_SUB_STEPS` key and value is a lifecycle node, with no value a declared successor of its key.

**Assembly.** The two files (`plugins/soleur/lib/workflow-fidelity.ts` consts and `.claude/workflow-transitions.json`) and the single chokepoint that compares them: the `describe("declared-transitions derived view parity")` block in `plugins/soleur/test/workflow-fidelity.test.ts`, which runs in the required `grok-fidelity` CI check. The deep-equal covers both directions for both keys; a `sub_steps` view→const loop mirrors the existing `transitions` one; the three invariant tests iterate the const. The classifier (`scripts/classify-workflow-transitions.sh`) is the view's only consumer and reads `sub_steps` through the same file, so a parity failure is the only signal that the classifier's input drifted from the reviewed const.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `"plan"` to `sub_steps.brainstorm` in the JSON only | RED (deep-equal, view → const direction; the `sub_steps` loop also names the edge) |
| 2 | Add `plan: ["work"]` to `DECLARED_SUB_STEPS` in the TS only | RED (deep-equal, const → view direction; also "not a declared successor", since `plan -> work` is an edge) |
| 3 | Delete the `sub_steps` key from the JSON | RED (deep-equal; the classifier would also FATAL, Guard 2 row 5) |
| 4 | Add `sub_steps.compound: ["ship"]` to both files | RED ("not a declared successor" — the collapse would delete a declared pair) |
| 5 | Add `sub_steps.brainstorm: ["deepen-plan"]` to both files | RED ("every value is a lifecycle node" — the node filter would remove it first, so the entry is dead) |
| 6 | Harness row: replace `expect(view).toEqual(canonical)` with `expect(view).toBeDefined()` and re-apply row 1 | Row 1 must go GREEN under the weakened harness — proving the deep-equal is the load-bearing assertion, not the file-exists test (the invariants iterate the const, so they stay green on a view-only edit) |
| 7 | Must-PASS non-canonical: reorder the top-level keys (`sub_steps` before `transitions`) and reformat whitespace in the JSON | GREEN (parity is structural, not textual) |

These rows are design documentation for the work phase, exercised by editing the two tracked files in place and restoring them with `git checkout --` after each row (the test resolves the JSON by walking up from `PLUGIN_ROOT`, so a scratch copy is never read); nothing about the loop is committed or pasted anywhere — the invariant tests are the guard.

**Anchor.** Both files sit in one commit, so this guard proves consistency, not integrity: a PR can edit both. The integrity anchor is review of `DECLARED_TRANSITIONS`/`DECLARED_SUB_STEPS` diffs themselves (the const is the reviewed artefact; the mirror follows) plus the `plan -> ship` absence assertion, which no mirror edit can satisfy.

### Guard 2 — classifier sub-step collapse semantics

**Property.** After non-node removal and per-session timestamp ordering, a record is dropped before pairing iff its skill is in `sub_steps[<skill of the previous kept record in the same session>]`; the dropped count is reported as `substep=` on every summary line, and a view whose `sub_steps` is missing or not an object is a FATAL (rc 2) naming the key, never a silent `substep=0`.

**Assembly.** The single jq program in `scripts/classify-workflow-transitions.sh` (the `read -r -d '' JQ` heredoc: `$nodes` → `group_by(.session_id)` → `sort_by(.t)` → the new per-session reduce → pairs), the pre-pass `jq -e '.sub_steps | type == "object"'` check on the view, and the two summary `echo` lines (real and null-reading), gated by `scripts/classify-workflow-transitions.test.sh` (registered in `scripts/test-all.sh`, `#8302 / ADR-229` block). There is one pairing site; the reduce must sit between sorting and pairing, and nowhere else. The rotated-archive merge before grouping is already pinned by existing case 13 and is not re-pinned here.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the reduce (pair `$nodes` directly) | RED — case "brainstorm compound plan pairs as brainstorm -> plan, substep=1" |
| 2 | Key the lookup on the previous RAW record instead of the previous KEPT record | RED — case "brainstorm compound compound plan → substep=2, pairs=1" (the second compound's raw predecessor is compound) |
| 3 | Move the drop BEFORE non-node removal | RED — case "brainstorm one-shot compound plan → substep=1, pairs=1" (compound's raw predecessor is one-shot) |
| 4 | Do not group by session before the drop | RED — case "session A ends with brainstorm, session B starts with compound → substep=0" |
| 5 | Tolerate a missing or non-object `sub_steps` (`// {}` or a bare `has("sub_steps")`) | RED — one case with two synthesized views, one lacking the key and one with `"sub_steps": null` → rc 2 both times, FATAL names the key (`null["brainstorm"] // []` would otherwise silently reproduce today's numbers) |
| 6 | Omit `substep=` from the null-reading line | RED — its own `--summary` case on an absent log asserting `substep=0 … null_reading=1` |
| 7 | Apply the drop to the first record of a session, or evaluate the `$SUB[...]` lookup before the empty-`kept` branch | RED — case "compound plan (compound first) → not dropped, pairs=1, undeclared=1" (the unconditional lookup throws on `$SUB[null]`, rc 2) |
| 8 | Harness row: neuter `pass()` so it never increments | RED — instrument self-test FATAL at the top of the suite (existing shape) |
| 9 | Post-remediation self-check: `brainstorm compound review` | GREEN for the suite, and the classifier still reports `brainstorm -> review` as undeclared with `substep=1` — the collapse must not launder the edge it exposes |
| 10 | Must-PASS non-canonical: `brainstorm compound brainstorm compound plan` | GREEN — `substep=2 pairs=2 undeclared=1` with the row `brainstorm -> brainstorm` (a self-loop the raw walk already reported; the collapse exposes it rather than hiding it) |

**Anchor.** The suite copies the live `.claude/workflow-transitions.json` into its fixture, so its expectations move with the mirror — which is why row 5 uses synthesized views rather than an edited copy, and why Guard 1 (not this suite) is what pins the mirror's content.

### Guard 3 — measurement script null-reading and privacy

**Property.** `scripts/measure-plan-sharp-edges-turns.sh` reports `null_reading=1` (never a bare zero) when no transcript file or no plan run exists, counts one turn per `requestId` group regardless of how many records the group spans, classifies a run as `post` only when the preamble record of the loaded skill text names the catalogue, and emits no byte of `message.content`, `input.command`, `input.content` or `input.file_path` on stdout or stderr (stderr also never carries `$HOME`).

**Assembly.** The script's slug function, the `find`-based root enumeration (`<slug>` and `<slug>--worktrees-*`, or the override root), the per-file jq invocation that groups records into turns, finds run starts (both forms), reads the preamble record, and searches tool_use blocks, and the two printers (`#` header + rows, summary); gated by `scripts/measure-plan-sharp-edges-turns.test.sh`, registered in `scripts/test-all.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Count assistant records instead of `requestId` groups | RED — fixture with the plan invocation in the third record of a three-record turn and the catalogue Read two turns later (k must be 2, not 4) |
| 2 | Search only the first record of each group for tool_use blocks | RED — same fixture (the invocation is not in the first record) |
| 3 | Match `plan-sharp-edges.md` by bare substring, or by the full `plugins/soleur/skills/plan/…` prefix | RED — fixture Reading `plugins/soleur/skills/work/references/plan-sharp-edges.md.bak` must not count; fixture Reading `…/plugins/cache/x/y/h4sh/skills/plan/references/plan-sharp-edges.md` (installed-plugin shape) must count as `post` |
| 4 | Skip `subagents/agent-*.jsonl` | RED — fixture whose only plan run is a subagent transcript |
| 5 | Filter on `isSidechain != true` | RED — same fixture (subagent records carry `isSidechain: true`) |
| 6 | Print the matched `file_path`, the Bash command, or a transcript path in the output | RED — sentinel test: fixtures carry `SENTINEL-DO-NOT-PRINT-7f3a` inside a text block, a Bash command, a Write content and the fixture root's directory name; stdout+stderr must not contain it |
| 7 | Exit 0 with `runs=0` and no `null_reading=1` when the root has no `.jsonl`, or print `reason=no_runs` for an empty root | RED — null-reading case asserts the key set, `reason=no_files`, and a second root with one non-plan transcript asserts `reason=no_runs` |
| 8 | Window not bounded by the next run start in the same file, or two `soleur:plan` blocks in one turn counted as two runs | RED — fixture with two runs in one file where only the second has a catalogue Read (first `post_skipped`, second `post`); fixture with two `Skill soleur:plan` blocks in one turn → `runs=1` |
| 9 | Classify `post` by the presence of a Read, or by any `user` text naming the catalogue instead of the preamble record | RED — fixture whose preamble record lacks `references/plan-sharp-edges.md` but whose window has a catalogue Read and a later user text quoting the literal → `pre` (with `k_first` from a plans/ touch in the same fixture); fixture whose preamble names it and has no Read → `post_skipped`; fixture with no preamble record → `unknown` and the stderr WARNING |
| 10 | Count `isApiErrorMessage` records as turns, or ignore the slash-typed `<command-name>/soleur:plan</command-name>` start | RED — fixtures for each (k must not grow past an API-error record; the slash run must be counted with the same k as its Skill-tool twin) |
| 11 | Read `<slug>*` instead of `<slug>` and `<slug>--worktrees-*` | RED — fixture `HOME` whose `.claude/projects` holds `<slug>`, `<slug>--worktrees-x` and `<slug>-other`, driven with `MEASURE_PROJECT_PATH=/fixture/proj` and `MEASURE_TRANSCRIPT_ROOT` unset → `files` counts the first two only; the slug function itself is asserted on `/tmp/a.b_c/x` → `-tmp-a-b-c-x` |
| 12 | Harness row: delete the sentinel assertion's `grep -q` (assert nothing) | RED — instrument self-test plus a row that plants the sentinel in a scratch stdout and expects `fail` |
| 13 | Must-PASS non-canonical: a record with no `usage` field, and a record with no `requestId` but a `uuid` | GREEN (fallback identity; nothing reads `usage`) |
| 14 | Percentile correctness: `post` k values `[3, 9, 20, 41, 50]`, then `[36]`, then `[10, 36]` | GREEN only if `median_k=20 p10_k=3 p90_k=50 saving_tokens_per_run=1160000`, then `36/36/36`, then `median_k=23 p10_k=10 p90_k=36 saving_tokens_per_run=1334000` (conventional median, nearest-rank tails) |
| 15 | `k=0` treated as absent | RED — fixture with the catalogue Read in the invocation turn → `post` with `k=0`, included in the median |

**Anchor.** The decision rule in ADR-229 is applied to a number this script prints; the anchor outside the commit is the `--rows` table pasted into the #8325 comment, which a reviewer can reproduce on the same machine with one command.

## Implementation Phases

### Phase 1 — §1 and §2, TS first (RED → GREEN)

1. `plugins/soleur/test/workflow-fidelity.test.ts`: write the new/changed assertions (postmerge `["work"]`, four back-edges, the `mandatorySuccessors("postmerge")` line, parity canonical with `sub_steps`, the `sub_steps` view→const loop, the three invariant tests over the const). Run — RED.
2. `plugins/soleur/lib/workflow-fidelity.ts`: `postmerge: ["work"]`, doc-comment rewrite, `DECLARED_SUB_STEPS` with its "To add an entry" comment.
3. `.claude/workflow-transitions.json`: mirror both; extend `_comment`.
4. `bun test plugins/soleur/test/workflow-fidelity.test.ts` — GREEN, count ≥ 87. Optionally walk Guard 1 rows 1–7 in place with `git checkout --` restores; not recorded anywhere.

### Phase 2 — classifier (RED → GREEN)

1. `scripts/classify-workflow-transitions.test.sh`: add the twelve classifier scenarios as cases 17–28; raise `MIN_CASES` to 28. Run — RED.
2. `scripts/classify-workflow-transitions.sh`: fail-closed `sub_steps` object check; per-session reduce with the explicit empty-`kept` branch; `substep=` in both summary lines; `--help` and header comment.
3. `bash scripts/classify-workflow-transitions.test.sh` — `28 passed, 0 failed`; `bash scripts/classify-workflow-transitions.sh --summary` from the worktree — record the pre- and post-change live lines for the #8325 comment (expected shape `undeclared≈379 … substep≈129`, no `null_reading`).

### Phase 3 — §3 measurement script (RED → GREEN)

1. `scripts/measure-plan-sharp-edges-turns.test.sh` with synthesized fixtures (Guard 3 rows); `assert_fixture_dir` byte-identical; `MIN_CASES` floor. Run — RED (SUT missing).
2. `scripts/measure-plan-sharp-edges-turns.sh` per the specification above (`chmod +x`; `CATALOGUE_TOKENS=58000` named at the top).
3. Register in `scripts/test-all.sh` beside the classifier suite and update that block's comment; run `bash scripts/lint-orphan-test-suites.sh`, `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh` (floor holds; zero new sites), `bash scripts/guard-vacuity-floor.test.sh`.
4. Run the script from the worktree: `bash scripts/measure-plan-sharp-edges-turns.sh --rows`; keep the output for Phase 4.

### Phase 4 — ADR-229, issue comment, follow-up

1. ADR-229 `## Decision`: four declared back-edges + the dated amendment sentence. `## Consequences`: (a) the re-baseline bullet opening "Re-baselined 2026-09-19 (#8325, …)" with the post-change live summary line and `substep=`; (b) the `postmerge → work` bullet rewritten as declared, with the 7-session evidence; (c) the interpretation bullet corrected (`brainstorm → compound → plan` and `plan → compound → work` are designed handoffs; `ship → plan`/`postmerge → plan` are the second-feature starts) and its trailing pointer replaced by the resolution; (d) the economics bullet's "plausibly large and unmeasured" sentence replaced by the one measured sentence (numbers with n, "min/max at this n" for the tails, the decision-rule outcome, pointer to the #8325 comment); (e) `## Verification`: the classifier bullet's "16 assertions" → 28, a new bullet for the measurement suite, the workflow-fidelity bullet gains the `sub_steps` parity and invariants.
2. `bash scripts/check-adr-ordinals.sh` — OK.
3. `gh issue comment 8325 --body-file <file>` with both classifier summary lines, the measurement summary line and the `--rows` table (numbers only). If `median_k` < 16 or `na`: `gh issue create --label action-required --title "Decide keep/revert of the plan Sharp Edges extraction: measured median k=<value> (post=<n>)"` with a one-line body citing ADR-229.
4. Full gate list (Acceptance Criteria) from the worktree; `python3 scripts/lint-skill-body-budget.py --base origin/main` OK (no `SKILL.md` body changes).

## Files to Edit

- `plugins/soleur/lib/workflow-fidelity.ts` — `DECLARED_TRANSITIONS.postmerge`, doc comment, new `DECLARED_SUB_STEPS`
- `.claude/workflow-transitions.json` — `transitions.postmerge`, new `sub_steps`, `_comment`
- `plugins/soleur/test/workflow-fidelity.test.ts` — edge-set tests, parity block, `sub_steps` loop and invariants
- `scripts/classify-workflow-transitions.sh` — fail-closed `sub_steps`, per-session reduce, `substep=`, `--help`, header
- `scripts/classify-workflow-transitions.test.sh` — cases 17–28, `MIN_CASES=28`
- `scripts/test-all.sh` — one `run_suite` line for the new suite and the block comment
- `knowledge-base/engineering/architecture/decisions/ADR-229-workflow-fsm-single-source-and-offline-classification.md` — Decision list + amendment sentence; Consequences and Verification edits in place

## Files to Create

- `scripts/measure-plan-sharp-edges-turns.sh`
- `scripts/measure-plan-sharp-edges-turns.test.sh`

## Open Code-Review Overlap

- #7942 (Two mutation batteries in `plugins/soleur/test/` are named `*.mutation.sh` and run in no gate) names `scripts/test-all.sh`. **Acknowledge:** different concern (mutation-battery registration); this plan adds one `run_suite` line and does not touch the battery naming. The scope-out remains open.

## Acceptance Criteria

CI-verifiable (every one is a command with an exit code, runnable on a fresh checkout):

1. `bun test plugins/soleur/test/workflow-fidelity.test.ts` exits 0 with ≥ 87 tests; the suite asserts `declaredTransitions("postmerge")` equals `["work"]`, `isDeclaredTransition("plan","ship")` is `false`, `mandatorySuccessors("postmerge")` does not contain `work`, the `sub_steps` view→const loop, and the three `sub_steps` invariants over the const (keys are nodes; values are nodes; a value is not a declared successor of its key).
2. `.claude/workflow-transitions.json` minus `_comment` deep-equals `{ transitions: DECLARED_TRANSITIONS, sub_steps: DECLARED_SUB_STEPS }` (the parity test is the check; no separate loop is recorded).
3. `bash scripts/classify-workflow-transitions.test.sh` prints `28 passed, 0 failed` with `MIN_CASES=28`; the twelve new cases are the twelve classifier scenarios in `## Test Scenarios`, one each.
4. `bash scripts/classify-workflow-transitions.sh --summary` on a root with no invocation log prints the null line with the key order `undeclared=0 sessions=0 pairs=0 nonnode=0 substep=0 read=0 dropped=0 null_reading=1`; on a view whose `sub_steps` is missing or `null`, exits 2 with a FATAL naming `sub_steps`.
5. `bash scripts/measure-plan-sharp-edges-turns.test.sh` exits 0 with ≥ 15 cases (Guard 3 rows 1–15, one each); `grep -E '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}' scripts/measure-plan-sharp-edges-turns.test.sh` returns nothing.
6. `MEASURE_TRANSCRIPT_ROOT=<empty dir> bash scripts/measure-plan-sharp-edges-turns.sh` prints exactly one stdout line carrying the full key set `runs= post= post_skipped= pre= unknown= median_k= p10_k= p90_k= saving_tokens_per_run= median_k_first= n_k_first= median_k_ac= n_k_ac= window_from= window_to= files= parsed= dropped= null_reading=1` and exits 0 with `reason=no_files` on stderr; on a fixture with runs, `--rows` stdout is one `# kind k k_first k_ac turns_in_window` header line, then rows matching `^(post|post_skipped|pre|unknown)\t-?[0-9]+(\t-?[0-9]+){3}$`, then the summary line, and stdout contains no `/`.
7. ADR-229 `## Consequences` contains the strings `Re-baselined 2026-09-19`, `substep=`, `Measured on 2026-`, `n =` and no longer contains `plausibly large` or `edge-set question recorded in decision-challenges`; `## Decision` lists four declared back-edges and contains `Amended 2026-09-19 (#8325)`; `## Verification` names `measure-plan-sharp-edges-turns.test.sh`; `bash scripts/check-adr-ordinals.sh` exits 0; `git diff origin/main --name-status -- knowledge-base/engineering/architecture/decisions/` shows only an `M` for ADR-229.
8. `bash scripts/lint-orphan-test-suites.sh` exits 0 with the new suite registered in `scripts/test-all.sh`; `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh` exits 0 (the new suite's `assert_fixture_dir` copy is byte-equal; file-count floor holds); `bash scripts/guard-vacuity-floor.test.sh` exits 0.
9. Exit 0 from the worktree for: `bash scripts/lib/incidents-roots.test.sh`, `bash scripts/rule-metrics-aggregate.test.sh`, `bash tests/scripts/test-rule-metrics-aggregate.sh`, `bash scripts/lint-skill-body-budget.test.sh`, `python3 scripts/lint-skill-body-budget.py --base origin/main` (their reported counts at the time of the brief — 12/0, PASS=90, 12/0, 15/0, OK — are recorded in the #8325 comment, not asserted here).
10. `git diff origin/main --stat` shows no change to `knowledge-base/project/rule-metrics.json`, nothing under `plugins/soleur/scripts/`, and no new file under `plugins/`.

Operator-machine snapshots (verified once during work, recorded verbatim in the #8325 comment; they depend on the main checkout's invocation log and on local transcript retention, so they are not CI assertions):

11. `bash scripts/classify-workflow-transitions.sh --summary` from the worktree prints a line with no `null_reading` (the invocation log in the main checkout was reached); the row output contains no `brainstorm -> compound` and no `postmerge -> work` rows and still contains `ship -> plan` rows; the pre-change and post-change summary lines are both recorded (no numeric floor is asserted — the log is ambient state that grows and rotates under other sessions; the collapse property itself is pinned by the fixture cases in AC3).
12. `bash scripts/measure-plan-sharp-edges-turns.sh --rows` on the operator machine exits 0 without `null_reading`, and the numbers in ADR-229's measured sentence are the ones on the summary line it prints (no `runs`/`post` floor is asserted — local transcript retention is ambient state; the parser's properties are pinned by AC5's fixtures).
13. An issue comment on #8325 carries both classifier summary lines, the measurement summary line and the `--rows` table; if `median_k` < 16 or `na`, exactly one new open issue with label `action-required` names the measured `median_k` and `post` in its title.

## Test Scenarios

Classifier (each is one case in `scripts/classify-workflow-transitions.test.sh`):

- **Given** a session `brainstorm, compound, plan` in the invocation log, **when** the classifier runs, **then** `pairs=1 undeclared=0 substep=1` and no row is printed.
- **Given** `brainstorm, compound, review`, **when** it runs, **then** one row `brainstorm -> review` and `substep=1`.
- **Given** `brainstorm, compound` only, **when** it runs, **then** `pairs=0 substep=1` and the "formed ZERO lifecycle pairs" warning.
- **Given** `review, compound, plan`, **when** it runs, **then** `substep=0`, one row `compound -> plan` (a sub-step is keyed on `brainstorm`, not on every predecessor).
- **Given** `brainstorm, compound, compound, plan`, **when** it runs, **then** `substep=2 pairs=1 undeclared=0`.
- **Given** `brainstorm, compound, brainstorm, compound, plan`, **when** it runs, **then** `substep=2 pairs=2 undeclared=1` with the row `brainstorm -> brainstorm`.
- **Given** `brainstorm, one-shot, compound, plan`, **when** it runs, **then** `nonnode=1 substep=1 pairs=1 undeclared=0`.
- **Given** `compound, plan` as a session's first two records, **when** it runs, **then** `substep=0 pairs=1 undeclared=1` and no jq error.
- **Given** session A `brainstorm` and session B `compound, plan`, **when** it runs, **then** `substep=0`.
- **Given** a view file without `sub_steps`, and a view with `"sub_steps": null`, **when** it runs against each, **then** rc 2 and a FATAL naming `sub_steps` both times.
- **Given** no invocation log, **when** `--summary` runs, **then** the null line contains `substep=0 null_reading=1`.
- **Given** `postmerge, work, review, compound, ship, postmerge`, **when** it runs, **then** `undeclared=0`.

Measurement script (each is one case in `scripts/measure-plan-sharp-edges-turns.test.sh`; fixture timestamps strictly increase):

- **Given** a synthesized transcript whose plan invocation is the third record of a turn, whose next user record carries `Base directory for this skill` and `references/plan-sharp-edges.md`, and whose catalogue Read is two turns later, **when** the script runs with `--rows`, **then** the header line, one row `post\t2\t…`, and `median_k=2`.
- **Given** the same transcript with the catalogue Read at the installed-plugin cache path, **when** it runs, **then** still `post`; **given** a Read of `…/work/references/plan-sharp-edges.md.bak` instead, **then** `post_skipped`.
- **Given** a transcript whose preamble record does not name the catalogue, a later user text that does quote the literal, a `Bash` heredoc to a plans/ path at +4, an `## Acceptance Criteria` Edit at +30, and a catalogue Read at +40, **when** it runs, **then** `pre\t-1\t4\t30\t<turns>`.
- **Given** a transcript whose preamble names the catalogue and has no catalogue Read, **when** it runs, **then** `post_skipped` and `median_k=na`; **given** no preamble record at all, **then** `unknown` and the stderr WARNING.
- **Given** a transcript under `<session>/subagents/agent-t1.jsonl` with `isSidechain: true`, **when** it runs, **then** the run is counted.
- **Given** a transcript whose run starts from a user record carrying `<command-name>/soleur:plan</command-name>`, **when** it runs, **then** the run is counted with the same k as its Skill-tool twin fixture.
- **Given** an `isApiErrorMessage: true` assistant record between invocation and Read, **when** it runs, **then** k does not count it.
- **Given** two `Skill soleur:plan` blocks in one turn, **when** it runs, **then** `runs=1`; **given** two runs in one file where only the second has a catalogue Read, **then** rows `post_skipped` then `post`.
- **Given** fixtures containing the sentinel in a text block, a Bash command, a Write content and the fixture root's directory name, **when** it runs, **then** neither stdout nor stderr contains the sentinel.
- **Given** an empty transcript root, **when** it runs, **then** stdout has the full key set with `null_reading=1`, stderr says `reason=no_files`, exit 0; **given** a root with one non-plan transcript, **then** `reason=no_runs`.
- **Given** `post` k values `[3, 9, 20, 41, 50]`, **when** it runs, **then** `median_k=20 p10_k=3 p90_k=50 saving_tokens_per_run=1160000`; **given** `[10, 36]`, **then** `median_k=23 p10_k=10 p90_k=36`; **given** `[36]`, **then** `36/36/36`.
- **Given** the catalogue Read in the invocation turn, **when** it runs, **then** `post` with `k=0`.
- **Given** a record with no `usage` and a record with no `requestId` but a `uuid`, **when** it runs, **then** both are turns and the run is counted.
- **Given** a fixture `HOME` whose `.claude/projects` holds `<slug>`, `<slug>--worktrees-x` and `<slug>-other`, **when** it runs with `MEASURE_PROJECT_PATH=/fixture/proj` and `MEASURE_TRANSCRIPT_ROOT` unset, **then** `files` counts the first two only; and the slug function maps `/tmp/a.b_c/x` to `-tmp-a-b-c-x`.
- **Given** the suite's sentinel assertion with its `grep -q` removed on a scratch copy, **when** the planted sentinel is checked, **then** the harness reports `fail`.

## Success Metrics

- Undeclared transitions drop from 622 to ≈379 with `substep≈129` and no loss of the review-skip signal (`plan -> ship`, `review -> ship`, `ship -> plan` rows unchanged in count).
- ADR-229 §3 carries a measured k with n, replacing "plausibly large and unmeasured".

## Dependencies & Risks

- **Small post-extraction n.** Local retention is three days; `post` n may be 2–3 at work time. Mitigation: report n beside every number, report `post_skipped` (a pass skipped on an extracted run is itself a finding against "loads on ~95% of plan runs"), report k'_ac as corroboration, and let the decision rule speak on the direct number as ruled; the n-floor question is the recorded User-Challenge.
- **Skill-load staleness.** Runs invoked after the merge but before the operator's plugin checkout pulled `50af0436f` loaded the pre-extraction SKILL.md; the preamble-record discriminator classifies them as `pre` (measured: 5 of the 7 post-merge runs). The script sees *which* body was loaded, not *why* a checkout was stale — the ADR sentence quotes the counts, not the cause.
- **Large transcripts.** `jq` over an 18k-line file is fine; the `grep -qF` pre-filter skips the ~700 files with no plan invocation. Expected runtime under two minutes on the operator machine.
- **CONFLICTING on `knowledge-base/INDEX.md`** is a GitHub-side artefact of the kb-index merge driver; a local sync + push cures it (ship-phase fact from the brief).

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO (`soleur:engineering:cto`) — approve with changes; nothing re-opens the rulings. §1/§2 sit on the reviewed ADR-229 mechanism and the classifier fixtures copy the live view, so the fail-closed check costs no fixture rewrites. Findings folded into this plan: (1) HIGH — match the catalogue by the `skills/plan/references/plan-sharp-edges.md` suffix, since an installed plugin loads from `~/.claude/plugins/cache/…` without the `plugins/soleur/` prefix (Guard 3 row 3, reconciliation table); (2) MEDIUM — operator-typed `/soleur:plan` lands as a `user` record with `<command-name>`, count it as a run start (Guard 3 row 10); (3) MEDIUM — `.kept[-1]` on an empty array is `null` and `$SUB[null]` throws, so the reduce needs an explicit empty branch (Guard 2 row 7); (4) MEDIUM — the fail-closed check must assert `.sub_steps | type == "object"`, not presence (Guard 2 row 5); (5) LOW — the summary line carries the window dates and per-proxy n so the ADR quotes it verbatim; (6) LOW — stderr prints the slug and counts only, and the corpus is `<slug>` + `<slug>--worktrees-*`, not `<slug>*`. On over-build: `pages` dropped; the `Bash` branch of `k_first` kept on measured evidence (6 of 25 runs invisible without it); `cache_read_at_hit` kept because it substantiates the 58k weight; `k'_ac` kept as one median. ADR-179 d4 satisfied. Advisor consult (ADR-083, `fable`): same catalogue/fixture points, plus a recommendation to floor the decision rule on n — recorded as a User-Challenge in `decision-challenges.md`, not applied (the rule is the operator's). SpecFlow (`soleur:product:spec-flow-analyzer`, 21 findings): median definition pinned at n=1/n=2, `median_k=na` arm defined, `$SUB[null]` branch, exact-slug corpus, `unknown` kind, run-is-a-turn, CI-safe vs operator-machine ACs split, self-loop and archive-split scenarios, chained/self `sub_steps` invariants, `k=0` legal, `isApiErrorMessage` excluded, `.`/`_` slug mapping, stdout-only path check, AC2/AC5 made command-verifiable, count drift pinned (today vs adoption).

Plan-review panel (DHH, Kieran, code-simplicity, CTO devex): 40 findings consolidated; mechanical ones applied in place (kind-name drift `post_nohit` → `post_skipped`/`pre`; preamble-record discriminator instead of a 12-record window; `.requestId // .uuid`; `find`-based root enumeration; `MEASURE_PROJECT_PATH`; `#` row header and grouped `--help`; two-reason null line; cut `cache_read_at_hit`, `pre_nohit`, the duplicate §1 assertion, two hygiene invariants, the archive-split and prefix rows, and the pasted mutation loop; one measured sentence in the ADR instead of a verbatim 20-key line; ADR Decision list and pointer sentence updated; twelve enumerated classifier cases with `MIN_CASES=28`). Not applied — operator-requested output: cutting `k'_first`, `p10`/`p90`, `saving_tokens_per_run`. User-Challenge persisted: `plan`/`postmerge` `compound` sub-steps (see `decision-challenges.md` §2).

Product: not relevant (no user-facing surface; the new-capability leader mandate does not fire because the deliverable is repo tooling under `scripts/`, not a plugin skill, agent or user-facing capability). Marketing, Operations, Legal, Sales, Finance, Support: not relevant — the transcript read is local, offline and content-free, and creates no legal document, vendor, or process.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-229** in place (no new ADR, ordinal unchanged): `## Decision` gains the dated amendment sentence declaring `postmerge → work`; `## Consequences` is re-baselined, the `compound → plan` interpretation corrected, and the §3 economics sentence replaced by the measured numbers; `## Verification` lists the new suite. The sub-step map is a classifier view concern and is recorded in the same Consequences bullet, not a new decision.

### C4 views

No C4 impact. Read all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`, 788/96/54 lines) for the actors and systems this change touches: the operator is `founder = actor "Founder / Operator"` (model.c4); the harness is the `platform.engine.claude` container ("Claude Code instances executing agent workflows") with `platform.engine.skillloader` and `platform.engine.hooks` beside it; the plugin is `platform.plugin`. The local transcript store (`~/.claude/projects`) is read by an operator-run repo script on the operator's own machine — it is not a container, a data store the platform owns, or an external system, and no actor↔surface access relationship changes (the founder already runs repo tooling against the plugin checkout). No new external actor or vendor is introduced. `plugins/soleur/test/c4-count-parity.test.sh` was run at plan time (`ALL TESTS PASSED`, `Failed: 0`) and is re-run in the work phase; no workflow, monitor or heartbeat count moves here.

### Sequencing

None — the ADR edit lands with the code in the same PR.

## Research Insights

**Premise Validation (Phase 0.6).** #8325 is OPEN with labels `action-required`, `decision-challenge`, no closing PR; the operator's comment redirects ADR-225 → ADR-229 (PR #8248 took 225 while #8301 was queued). Every cited file exists on the branch: `plugins/soleur/lib/workflow-fidelity.ts` (310 lines; `DECLARED_TRANSITIONS` with `postmerge: []` and the "(postmerge failed)" comment on `ship -> work`), `.claude/workflow-transitions.json` (30 lines, `transitions` only), `scripts/classify-workflow-transitions.sh` (254), its suite (311, 16 cases, copies the live view into fixtures), `plugins/soleur/test/workflow-fidelity.test.ts` (840, 83 tests), ADR-229 (249 lines; the §3 ledger at "plausibly large and **unmeasured**"), `plugins/soleur/skills/plan/references/plan-sharp-edges.md` (177 lines), and the seven gate suites. The extraction merged as `50af0436f` at 2026-09-19T00:16:33Z. The ADR corpus was grepped for the proposed mechanisms: a sub-step/sub-skill collapse is described (not rejected) in ADR-229's node-only walk paragraph; the `bun -e` alternative is recorded as not taken; nothing rejects a transcript-reading measurement script. Live evidence re-derived: `postmerge -> work` 7, `ship -> work` 2; top undeclared edges `brainstorm -> compound` 127, `compound -> plan` 111, `review -> ship` 51, `ship -> plan` 50, `postmerge -> plan` 31. One stale premise: the brief's `workflow-fidelity` count (73) is 83 today.

**Property List (Phase 0.6b).**

- P1 A session that recovers from a failed post-merge verification by re-entering `work` is not reported as undeclared.
- P2 The designed `brainstorm → compound → plan` handoff is not reported as undeclared, while `review → compound → plan` still is.
- P3 The number of records excluded by P2 is visible on every summary line.
- P4 The edge set and the sub-step map have exactly one reviewed source (the TS consts) and the mirror cannot drift silently.
- P5 The per-turn cache-read saving of the Sharp Edges extraction is a measured number with a stated n, reproducible by one offline command that prints no transcript content.
- P6 A null measurement is loud, never a zero.
- P7 The pre-extraction baseline (turns the catalogue sat in context before the pass) is reported beside the post-extraction number with its own n — the brief's k' as asked, plus k'_ac because k' measures turns-to-skeleton since ADR-176.

**Universal negatives, with the enumeration that produced them.** (a) "the view has one consumer": `git grep -n "workflow-transitions.json"` (excluding plans/specs/learnings) → ADR-229 prose, the parity block in `workflow-fidelity.test.ts`, `scripts/classify-workflow-transitions.sh`, its suite's `cp` lines, and the `lint-skill-body-budget.py` header that says it reads no view — no other reader. (b) "top-level `scripts/*.test.sh` are not globbed": `SUITE_GLOBS` in `scripts/test-all.sh` lists `scripts/lib/*.test.sh` only; the classifier and ratchet suites appear as explicit `run_suite` lines. (c) "no ADR rejects a transcript-reading measurement": `grep -li transcript knowledge-base/engineering/architecture/decisions/*.md` → ADR-053, 079, 083, 110, 139, none of which decides on or rejects reading local session transcripts (ADR-083 cites transcript re-send cost as the reason for curated advisor payloads). (d) "no runtime consumer of `DECLARED_TRANSITIONS`": ADR-229's own Consequences sentence, re-checked with `git grep -n "declaredTransitions\|isDeclaredTransition\|DECLARED_TRANSITIONS" plugins/soleur/lib plugins/soleur/scripts` → definitions plus the test file only.

**Cut List (Phase 0.6b).**

- `BRAINSTORM_SUB_STEPS` as a bare tuple **plus** a map → one map const covers P2/P4 (the JSON mirror is a map).
- A `subSteps()` runtime helper → nothing in the plugin runtime reads it (ADR-229: no runtime consumer of `declaredTransitions()` either); the parity test reads the const.
- A follow-through probe for the re-baselined numbers → ADR-229 already records why one cannot PASS where the sweeper runs; the baseline lives in the ADR.
- A JSON output mode for the measurement script → no consumer; the key=value line matches the classifier's convention and the ADR quotes it verbatim.
- Reading transcripts through the `session-report` community skill → surfaces prompt text and renders HTML; the requirement is a content-free number (functional-discovery: no direct overlap, five generic analyzers skipped).

**Value-Proposition Measurement (Phase 0.6c).** The plan's §3 is itself the measurement; the plan-time prototype (jq over the local corpus, not committed) read: 25 plan runs, `post` k=36 (n=1), k'_first median 7.5 (n=24), k'_ac median 45 (n=17), 1 `post_skipped`, 23 `pre` (of which 5 were invoked after the merge but loaded the pre-extraction body). Command shape: the parser specified above; the committed script reproduces it.

**Relevant code anchors.**

- `plugins/soleur/lib/workflow-fidelity.ts` › `DECLARED_TRANSITIONS` (doc comment "The three back-edges are operator-approved (#8302)… `ship -> work` (postmerge failed)… `postmerge -> work` was considered and REJECTED"), `declaredTransitions()`, `isDeclaredTransition()`, `mandatorySuccessors()`.
- `plugins/soleur/test/workflow-fidelity.test.ts` › `describe("declaredTransitions — permitted edges, including back-edges")` (tests "every lifecycle node declares its edge set", "the three operator-approved back-edges are declared", "postmerge -> work is NOT declared", "every mandatory successor is a declared transition") and `describe("declared-transitions derived view parity")` (`delete view._comment`; `canonical = JSON.parse(JSON.stringify({ transitions: DECLARED_TRANSITIONS }))`; `expect(view).toEqual(canonical)`; the view→const direction loop).
- `scripts/classify-workflow-transitions.sh` › the `JQ` heredoc (`$T` bound before piping; `$nodes`; `group_by(.session_id) | map(sort_by(.t))`; pairs via `range(1; length)`), the `--summary` echo and the null-reading echo (`undeclared=0 … dropped=0 null_reading=1`), the FATAL on an unreadable view.
- `scripts/classify-workflow-transitions.test.sh` › `assert_fixture_dir` copy with its "copied rather than sourced" comment, the instrument self-test, `cp "$SCRIPT_DIR/../.claude/workflow-transitions.json"` fixture, `MIN_CASES=16` literal, final `"$REAL_PASSES passed, $fails failed"`.
- `scripts/test-all.sh` › the `#8302 / ADR-229` `run_suite` block (explicit registration; `SUITE_GLOBS` has no `scripts/*.test.sh`).
- `plugins/soleur/test/fixture-dir-operand-assert.test.sh` › copies discovered by grep for `assert_fixture_dir` definitions (byte-equal to `plugins/soleur/test/test-helpers.sh`); baseline `fixture-dir-operand-assert.baseline.txt` lists files with `cd`/`git -C` operand sites — a suite with none adds no row.
- `scripts/lint-skill-body-budget.py` header: "This lint reads no view" — a `sub_steps` key cannot reach the ratchet.
- `plugins/soleur/skills/brainstorm/SKILL.md` › "Run `skill: soleur:compound` to capture learnings from the brainstorm session" followed by the `soleur:plan` resume prompt.
- ADR-229 › `## Decision` ("Declared back-edges: … `postmerge → work` was considered and rejected as redundant with `ship → work`."), `## Consequences` (baseline bullet "604 undeclared transitions of 4,922 lifecycle pairs"; "`postmerge → work` — the edge rejected as redundant — occurs 7 times, recorded here rather than acted on."; interpretation bullet "`compound → plan`, `ship → plan`, `postmerge → plan/work` (~190) are sessions chaining a second feature"; economics bullet "plausibly large and **unmeasured** — no turn telemetry exists — but the break-even is ~8 turns"), `## Verification`.
- ADR-179 decision 4: rule-corpus telemetry is monorepo-only by construction; nothing under `plugins/` reads it.

**Transcript record shape (verified with jq, keys only).** Top-level record types include `assistant`, `user`, `attachment`, `permission-mode`, `pr-link`; assistant records carry `requestId`, `apiBlockIndex`, `isSidechain`, `timestamp`, `message.{id,usage,content[]}`; `usage` carries `cache_read_input_tokens`; content block types `text|thinking|tool_use`; `Read` inputs `{file_path[,limit,offset]}`; `Skill` inputs `{skill[,args]}`; `Bash` inputs carry `command`; `Write` carries `content`, `Edit` carries `new_string`. 3,259 assistant records ↔ 1,718 distinct `requestId` = 1,718 distinct `message.id` in the largest session file. Subagent files: `<session>/subagents/agent-<id>.jsonl` + `.meta.json` (`agentType`, `spawnDepth`, …). The `Skill` tool_result is a short string; the loaded SKILL.md body arrives as the following `user` record(s), and `Base directory for this skill` / `references/plan-sharp-edges.md` are the two literals that identify it (booleans checked per run, nothing printed). 4 `isApiErrorMessage: true` assistant records exist in the largest file, each with its own `requestId`. 3 files carry the slash-typed `<command-name>/soleur:plan</command-name>` form.

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-03-10-jq-generator-silent-data-loss.md` — no `select()` in a binding; index arrays.
- `knowledge-base/project/learnings/2026-03-18-stop-hook-jq-invalid-json-guard.md` — `fromjson?` per line; a parse error must not abort the reading.
- `knowledge-base/project/learnings/2026-03-03-fix-release-notes-pr-extraction.md` — `// empty` / explicit `na` instead of the literal `null`.
- `knowledge-base/project/learnings/2026-09-18-re-verifying-a-stale-audit-and-six-measurement-errors-of-my-own.md` — measurement errors are scope mismatches: the transcript corpus (top-level only vs subagents; retention window) is the scope to state beside every number.
- `knowledge-base/project/learnings/2026-09-18-a-plan-can-specify-a-mechanism-the-packaging-boundary-forbids.md` — the log/view live in the main checkout; nothing in `plugins/` may depend on them.
- `knowledge-base/project/learnings/2026-04-23-agents-md-governance-measure-before-asserting.md` — ADR Consequences claims are measured, with the command named.
- `knowledge-base/project/learnings/2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md` — do not carry `rule-metrics.json`; `assert_fixture_dir` copies are byte-compared.
- AGENTS.md `cq-test-fixtures-synthesized-only` — transcript fixtures are fabricated.

**Related issues.** #8301 (remediation PR), #8302 (edge-set approval), #8305 (body-weight growth report — not a target), #8303 (heading grammar — not a target), #7942 (acknowledged overlap on `scripts/test-all.sh`).

## Observability

Skipped: the diff touches no `apps/*/server|src|infra`, no `plugins/*/scripts/`, and introduces no infrastructure surface. Both scripts are operator-run repo tooling whose "liveness" is the null-reading line each prints on stdout (`null_reading=1`), the same convention the classifier already uses.

## References

- Issue #8325; PR #8301; ADR-229 `knowledge-base/engineering/architecture/decisions/ADR-229-workflow-fsm-single-source-and-offline-classification.md`; ADR-179 decision 4; ADR-176 (Phase 0.7 skeleton, why k'_first is early).
- Archived challenge record: `knowledge-base/project/specs/archive/20260918-171219-feat-workflow-fsm-remediation/decision-challenges.md`.
