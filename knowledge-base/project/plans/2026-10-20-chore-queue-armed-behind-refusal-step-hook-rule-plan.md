---
title: "chore(ship): extend the queue-armed BEHIND refusal to --step and the pre-merge hook, and add the queue exception to the BEHIND rule"
date: 2026-10-20
slug: queue-armed-behind-refusal-step-hook-rule
branch: feat-one-shot-9869-9868-queue-behind-refusal
issue: 9869
lane: cross-domain
type: chore
related_issues: [9869, 9868, 9710, 9862]
draft_pr: 10655
---

# chore(ship): extend the queue-armed BEHIND refusal to `--step` and the pre-merge hook, and add the queue exception to the BEHIND rule

## Overview

On a repository whose `main` carries a `merge_queue` rule (ADR-270), a PR that GitHub reports BEHIND while
auto-merge is armed is made current by the queue itself; a hand sync pushes a commit that restarts every required
check for nothing. PR 9862 taught the standalone `sync-pr-behind.sh <PR>` loop to refuse that case
(`kind=queue_wait`, exit 0). Two writers still push to such a PR, and one always-injected rule still tells agents to
resync:

1. `sync-pr-behind.sh <PR> --step` (the Phase 7 fence call and the merge-pr mirror fence call) is unguarded by design (#9869).
2. `.claude/hooks/pre-merge-rebase.sh` (runs before every resolvable `gh pr merge`) merges `origin/main` and pushes,
   skipping only a PR already in the queue (#9869).
3. `AGENTS.rules.md` rule `hr-pipeline-skills-never-inline-after-go-route` ends `...BEHIND→resync main` with no queue
   exception; it is the one BEHIND statement that survives a context compaction (#9868).

This plan closes all three as one change on draft PR #10655. Design forks were ruled by the CTO agent (see
`knowledge-base/project/specs/feat-one-shot-9869-9868-queue-behind-refusal/decision-challenges.md`).

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief / issues | Reality (verified on this branch) | Plan response |
|---|---|---|
| #9868: "`AGENTS.rules.md` is 37928 B" | 39160 B now (`wc -c AGENTS.rules.md`); warn line is 44000 B | Adding ~70 B is safe; re-measure at the end (AC). |
| #9868: rule "tells agents to resync main on BEHIND without the queue exception" | Confirmed: `AGENTS.rules.md:65` reads `...ship polls merge→postmerge; BEHIND→resync main [id: hr-pipeline-skills-never-inline-after-go-route] [skill-enforced: workflow-fidelity.ts]. **Why:** #6325.` | Append a short state-based exception (Phase 5). |
| #9869: "`--step` and the hook are the two unguarded writers" | Confirmed: `sync-pr-behind.sh` header lines ~54-55 and ~335-336 say `--step` is not guarded; ADR-270 addendum 2026-10-09 lists both as accepted residuals | Guard both (Phases 1-2). |
| #9869: "a read-only `--queue-rule` mode the fences and the hook both call, so the predicate lives once" | The predicate is three-part (BEHIND-not-DIRTY, armed, rule present); a rule-only mode would not answer it, and the fences already compute `QUEUE_RULE` inline together with the required-check test the script does not read | One shared predicate function inside the script, exposed as a read-only `--queue-wait` verdict mode for the hook (not `--queue-rule`); fences keep their own inline logic (Cut List). |
| #9869: "needs an override at each fence arm that legitimately syncs (expiry, DIRTY-derived, QUEUE_RULE=0)" | All three arms funnel through ONE call site per fence (`ship/SKILL.md` ~2457, `merge-pr/SKILL.md` ~552), reached only after the fence's own queue-wait branch declined | One opt-in flag `--fence` at that single site per fence, not per-arm overrides. |
| Brief: "verify the files are shared" | The two issues share the exception PHRASE and the ADR-270/queue-mode.md record, not code files: #9868 edits `AGENTS.rules.md` (+ its hash manifest, ack, `workflow-fidelity.test.ts` pin); #9869 edits the script, hook, two fences and their suites. `pr-merge-poll.ts`, `harness.ts`, codex and devin INSTRUCTIONS already carry the exception (checked by grep) | Single PR justified in Split Assessment; shared surfaces are the ADR-270 addendum and `queue-mode.md`. |
| Brief: "never touch files under another open PR" | `gh pr list` file census: only #7390 (stale, CONFLICTING since 2026-10-14) touches a file we edit, `AGENTS.rules.md`, and its hunk is a NEW rule line (`hr-no-secret-in-buildarg-or-image-metadata`), disjoint from line 65 | Acknowledged in Open Code-Review Overlap / PR-overlap note; our hunk is the one rule line. |

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 9869` / `9868`: both OPEN, no closing PR. `gh pr view 9862`: MERGED 2026-10-09 (the standalone guard exists on this branch: `queue_wait_gate()` in `plugins/soleur/scripts/sync-pr-behind.sh`). Draft PR #10655 is OPEN with no files yet.
- Cited symbols exist on this branch: `queue_wait_gate`, `queue_gate`, `queue_state_read`, `--queue-state` (script); the queued-skip block at `pre-merge-rebase.sh` ~699-748; the single `--step` call sites in both fences; the `workflow-fidelity.test.ts` pin at ~line 639 (`BEHIND`, `resync main`).
- Mechanism vs ADR corpus: ADR-270 addendum 2026-10-09 explicitly leaves `--step` and the hook as "accepted residual (tracked in #9869)"; it does not reject guarding them. No rejected-alternative collision.
- Capability claims verified by reading the authority, not a consumer: `sync-pr-behind.sh` (the script, not the SKILL prose) for the exit-code table; `pre-merge-rebase.sh` parses only field 1 of the `--queue-state` line today (field 3 is `armed|disarmed`).

### Property List (Phase 0.6b)

1. **P1** A caller of `sync-pr-behind.sh <PR> --step` that is not a Phase 7 fence cannot push to an OPEN, armed PR whose GitHub state is BEHIND or UNKNOWN (recompute lag; never DIRTY) on a repo whose `main` has a `merge_queue` rule.
2. **P2** For every `gh pr merge` form the hook's parser resolves to one PR (the same forms the queued-skip covers; unresolved spellings stay state L and still sync, pinned by the existing KNOWN LIMITATION case), the hook cannot push a sync to such a PR.
3. **P3** The fences' legitimate sync arms (queue-wait expiry fallback, DIRTY-derived BEHIND, `QUEUE_RULE=0`, armed-read failure) still sync, with no added `gh` calls per tick.
4. **P4** The always-injected BEHIND rule states the queue exception, so it survives a context compaction.
5. **P5** The BEHIND-armed-rule predicate is written once in the script; the standalone loop, flagless `--step` and the hook read it from there.
6. **P6** Unreadable answers resolve in the direction each caller already owns: script callers fail closed (`kind=gh`, exit 4), the hook falls through to today's sync with a named note, never a block.
7. **P7** A new fence never pairs silently with an old script snapshot, and an OLD pasted fence paired with the NEW script stops LOUDLY (its `sync_failed` arm on a dedicated exit code 14 with the action named), never a false "pushed" and never a silent no-op livelock.

### Cut List (Phase 0.6b)

| Mechanism proposed or implied | Property it would buy | What already covers it / why cut |
|---|---|---|
| Fences call a new `--queue-rule` mode instead of their inline rules read (issue sketch) | P5 for the fences | Fences' `QUEUE_RULE` also folds in the required-check test the script does not read; the fences only need P3, which the `--fence` flag buys. Cut. |
| Per-arm override flags at each fence arm (expiry, DIRTY-derived, QUEUE_RULE=0) | P3 | All arms share ONE call site per fence; one flag there covers them. Cut. |
| Hook also skips the pre-arm sync on queue repos | none requested | The first `gh pr merge --auto` arm is the pre-sync the hook exists for (CTO Fork 3). Cut (non-goal). |
| Migrate the rule body into `workflow-fidelity.ts` (tier-gate "already-enforced" path) | P4 | Defeats P4: the rule line is the one statement injected on every SessionStart. Cut (CTO Fork 4). |
| Reusing exit 11 for the flagless refusal | P7 | REVERSED (CTO Fork 2', 2026-10-20): 11 is the fences' uncounted "no sync needed" arm, so an old pasted fence would livelock silently for up to `MAX_POLL_MIN`; a dedicated exit 14 hits the old fence's loud `sync_failed` stop. Not cut: replaced by 14. |
| Hook also skips when GitHub says CLEAN / BLOCKED / UNSTABLE while the branch is locally behind | none requested | GitHub is not reporting BEHIND there, so today's sync is unchanged; only BEHIND and UNKNOWN (recompute lag) are in the predicate (CTO Fork 6). Cut (non-goal). |
| Base-branch check (PR targeting a non-`main` base on a queue repo) | none requested | "Base is `main`, as everywhere in the script" is queue-mode.md boundary (2); unchanged. Cut (accepted residual). |
| Hook behaviour for a re-arm after a dequeue | none requested | A dequeued PR reads `dequeued` / disarmed and syncs as today; the dequeue recipe's step 2 IS that sync. Cut (deliberate non-goal). |
| Environment variable instead of `--fence` | P3 | Invisible to the fences' `--help` probe, so P7 fails (CTO Fork 1). Cut. |

### Institutional learnings applied

- `2026-10-09-an-exception-conditioned-on-a-marker-only-the-fence-prints-was-vacuous-for-the-reader-who-needed-it.md`: enforce in the executable, state the exception on facts; the rule wording therefore omits the `[ship.phase7.queue_wait]` marker (the class is test-banned in `pr-merge-poll.test.ts`).
- `2026-10-07-a-sync-that-defers-to-a-queue-needs-a-bounded-wait-and-a-reset-that-a-deleted-read-took-with-it.md`: a refusal needs a bounded exit; here the bound is unchanged (the fence's 6-idle-tick expiry and `MAX_POLL_MIN`); mutation rows run against a green control.
- `2026-10-10-an-error-must-not-borrow-a-success-states-vocabulary-and-every-consumer-stub-hid-it.md`: SKILL.md byte ceilings are design inputs. `ship/SKILL.md` is 272416 B against a 273955 B ceiling (1539 B headroom); the fence edit is a few bytes and no prose is added to the fences.
- `2026-03-03-pre-merge-rebase-hook-implementation.md`: keep the hook's stdout/JSON hygiene and its fail-open on infrastructure errors / fail-closed on logical ones.
- `2026-07-06-detection-control-verify-threat-rule-covered-and-prefer-human-gate-over-classifier.md`: an `hr-*` body edit needs the regenerated hash manifest plus a hash-bound ack.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 limit) bodies were searched for every file in Files to Edit; no matches.

PR overlap (brief rule "never touch files under another open PR"): open PR #7390 (stale, CONFLICTING) touches `AGENTS.rules.md` by ADDING a new rule line; this plan edits only the existing line for `hr-pipeline-skills-never-inline-after-go-route`. Hunks are disjoint. Acknowledged; no other open PR touches a file in this plan.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-270 (`knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`) with a new `### Addendum 2026-10-20 (#9869, #9868): --step and the pre-merge hook refuse an armed BEHIND PR on a merge-queue repo` placed after the 2026-10-09 addendum. It records: flagless `--step` refuses (`kind=queue_wait`, exit 14) and the fences opt out with `--fence`; `--queue-wait` read-only mode; the hook skip and its fall-through direction; the `--admin` consequence; supersedes the 2026-10-09 sentence "`--step` stays the Phase 7 fence's unguarded call" and the accepted residual in Decision 5 prose (~line 178) for these two writers. Accepted residuals, stated so they are not rediscovered: (1) a hand-rolled loop that types `--fence` itself (a test pins that no instruction surface teaches the flag outside the two fences and `--help`); (2) the fences pass `--fence` at their single call site, so the fence's own fail-open arms (armed-read flake, rules-read failure, `QUEUE_RULE=0`) still sync by design (P3) — the guard only catches callers that are NOT the fence; (3) an OLD pasted fence paired with the NEW script now STOPS the poll with `[ship.phase7.sync_failed] … exited 14` plus the script's own `kind=queue_wait` line naming the action (re-paste the fence from the current SKILL.md) — a loud, bounded stop where it previously synced (CTO Fork 2' reversal; in-flight sessions hold pasted fences that are never re-read from disk); (4) unresolved `gh pr merge` spellings (flag before the number, URL operand) stay state L in the hook and still sync; (5) a PR GitHub never enqueues or that stays UNKNOWN makes the hook skip its push indefinitely, which is quiet and bounded — the fence's queue-wait expiry fallback performs the sync.

### C4 views

No C4 change. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`): no new external human actor, external system/vendor, container or data store; the actor-to-surface access relationships (agent session to GitHub merge queue, repo to CI) are unchanged — only which local script/hook writes a push changes. Derived cardinalities in edge prose are unaffected (no workflow, monitor or slug added); `bash plugins/soleur/test/c4-count-parity.test.sh` must stay green (AC).

### Sequencing

The ADR is authored in the same PR as the code (Phase 6); no soak-gated slice.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Close #9869 and #9868 as one change (the draft PR for this branch is #10655)" | Whole plan; single PR #10655 | mapped |
| 2 | "#9869: the existing queue-armed BEHIND refusal does not yet cover `sync-pr-behind.sh --step` or the pre-merge-rebase hook; extend it." | Phases 1, 2, 3 | mapped |
| 3 | "#9868: ... needs the queue exception in its text." | Phase 5 | mapped |
| 4 | "Read both issues in full first" | Research Insights / Premise Validation | mapped |
| 5 | "find the existing refusal implementation ... and verify the files are shared" | Research Reconciliation row "verify the files are shared"; Split Assessment | mapped |
| 6 | "Follow cq-agents-md-why-single-line, cq-rule-ids-are-immutable and cq-agents-md-tier-gate for the AGENTS rule edit." | Phase 5, AC-R1..R5 | mapped |
| 7 | "Write failing tests first (cq-write-failing-tests-before)." | Phase 0 (RED) before Phases 1-5 | mapped |
| 8 | "PR bodies must use `Ref #N`, never closes/fixes/resolves adjacency" | AC-X2 | mapped |
| 9 | "for a threshold/design A-vs-B/architecture fork spawn `soleur:engineering:cto` ..." | `decision-challenges.md` rows 1-4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/scripts/sync-pr-behind.sh` guard + `--fence` + `--queue-wait` | "the existing queue-armed BEHIND refusal does not yet cover `sync-pr-behind.sh --step` ... extend it." | asked |
| `.claude/hooks/pre-merge-rebase.sh` skip | "or the pre-merge-rebase hook; extend it." | asked |
| `ship/SKILL.md` and `merge-pr/SKILL.md` fence call site + probe | "(#9869 issue) Guarding `--step` needs an override at each fence arm that legitimately syncs" (asks 2) | asked (issue body, ask 2 origin) |
| `AGENTS.rules.md` line, `.claude/rule-body-hashes.txt`, `.claude/rule-weakening-acks.txt` | "needs the queue exception in its text" | asked |
| `plugins/soleur/test/workflow-fidelity.test.ts` pin | "Write failing tests first" (ask 7) | asked |
| `plugins/soleur/test/sync-pr-behind.test.sh`, `.claude/hooks/pre-merge-rebase.test.sh`, `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` | "Write failing tests first" (ask 7) | asked |
| `plugins/soleur/lib/pr-merge-poll.ts` + `plugins/soleur/test/pr-merge-poll.test.ts` text | — | inferred — justification: the text says `--step` is "never yours; unguarded by design" and a test pins that string; after Phase 1 it is false and the pin would redden |
| `plugins/soleur/skills/ship/references/queue-mode.md` boundary (1) | — | inferred — justification: boundary (1) states "`--step` ... is not guarded ... follow-on tracked in #9869"; leaving it rots the reference agents read before changing queue mode |
| ADR-270 addendum | — | inferred — justification: Phase 2.10 gate — the change reverses the 2026-10-09 addendum's "`--step` stays unguarded" decision; ADR must ship in the same plan |
| `sync-pr-behind.sh` header/usage/exit table text | — | inferred — justification: `--help` is the fences' version probe and the exit-code table is the one table (script header); stale text is the failure class #8383 closed |

### Split Assessment

- Subsystems touched: 6 — `plugins/soleur/scripts`, `.claude/hooks`, `plugins/soleur/skills` + `lib`, `plugins/soleur/test`, `AGENTS.rules.md` + `.claude` manifests, `knowledge-base`
- Planned files: 19 | Estimated changed lines: ~700 (about 70% tests)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The root count exceeds the threshold, but ask 1 states "as one change"; the two issues share the exception phrase and the ADR-270 addendum, and splitting the rule edit away would leave the repo stating the exception in prose while the executable still pushes. The only independent slice (Phase 5, the rule edit) is ~1 line plus two manifest rows and is cheapest reviewed alongside the pin tests that lock the phrase.

## User-Brand Impact

- **If this lands broken, the user experiences:** an agent session whose armed PR is wrongly refused a sync (or wrongly skipped by the hook) sits BEHIND until the Phase 7 poll's expiry fallback syncs it, a bounded delay of up to roughly 6 poll ticks; or, in the other direction, a stray resync push restarts the PR's CI (the status quo this change removes). No user data, auth or billing path is touched.
- **If this leaks, the user's data is exposed via:** no exposure vector — the change adds no credential, network egress or data read beyond existing `gh pr view` / rules reads.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** developer-workflow tooling with a bounded, self-healing failure (expiry fallback, `MAX_POLL_MIN`; an old fence stops loudly on exit 14); no customer-facing surface, so the next tier does not apply.

threshold: none, reason: the touched paths (`plugins/soleur/scripts`, `.claude/hooks`, `AGENTS.rules.md`) are internal agent-workflow machinery, outside the sensitive-path regex and with no customer data or credential access.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Spawned as the technical-ruling delegate (hr-technical-fork-is-not-an-operator-question) for four forks: guard shape for `--step` (opt-in `--fence`, refuse by default), refusal exit code (11, fail-closed 4 on unreadable), hook scope (armed + `--queue-wait` verdict, fall-through on unreadable, unarmed still syncs, `--admin` consequence disclosed), and rule placement (stay in `AGENTS.rules.md`, state-based wording, hash + ack). Product, marketing, legal, finance, sales, support, operations: no cross-domain implications (internal tooling; no user-facing surface, no regulated data).

## Implementation Phases

Order is test-first: Phase 0 writes RED tests; Phases 1-5 turn them GREEN; Phase 6 records the decision; Phase 7 validates. Edit with the Edit tool on the exact lines named; read each file first.

### Phase 0 — RED tests (before any production edit)

Each new row is added to its existing suite (already registered in its runner). Hand-maintained floors must be bumped in the same edit or the suite fails on its LAST line, not on the new row: `plugins/soleur/test/sync-pr-behind.test.sh` ends `[[ "$FAIL" -eq 0 && "$PASS" -eq 122 ]]` (exact pass count: recompute after the final row set), `.claude/hooks/pre-merge-rebase.test.sh` has `EXPECTED_CASES=69` plus a hand-written case list at its tail (it counts case FUNCTIONS: raise it by exactly the number of new `t_q*` functions and add each to the list; add a structural check that the list equals the defined `t_q*` functions so an omission cannot pass), and `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` has `MIN_VERDICTS=1093` (ratchet up; never lower). `scripts/suite-durations.tsv` is generated (`regenerate-shard-manifest.py`); do not hand-edit it.

0.1 `plugins/soleur/test/sync-pr-behind.test.sh` (helpers `make_pair`, `install_gh`, `install_gh_forbidden`, `install_gql`, `install_rules`, `run_loop`, `run_step`, `qw_run`, `qw_scenario`, `qw_mutant`, `argv_rc`):
- Do NOT rename or flip `run_step` in Phase 0 (flipping it makes every existing step row fail with exit 2 and the RED list undiscriminating). Add `run_step_bare` (flagless) for the new rows. In the Phase 1 commit flip `run_step` to pass `--fence` AND fix the one direct caller that bypasses it: the S1 trace-env row (~line 672) invokes `sync-pr-behind.sh 1 --step` directly and must gain `--fence`. There are 17 `run_step` call sites. Also refresh the stale comments (~463-466 "makes exactly ONE gh call", ~1253 R8 "unguarded by design").
- New helper `install_gh_wait` (one definition, used by F1, F5, F6, W1-W4): serves the queue GraphQL as `install_gql` does, the rules endpoint via `install_rules` (answers the `?per_page=100` form), and `gh pr view <N> --json state,mergeStateStatus,autoMergeRequest` per a `pr-view-mode` of `ok:<state>:<armed|disarmed>`, `fail`, `hang`, `garbage`; it logs every call to a calls file (`install_gh` has only a counter and `install_gh_forbidden` exits 99 on any non-GraphQL call, so neither can express F5/F6).
- Re-anchor the existing `qw_mutant` rows on the UNCHANGED literal lines (e.g. `[[ "$am" == armed ]] || return 0`) and change only the "may land outside queue_wait_gate" message text in Phase 0, so they stay green on the current SUT and survive the Phase 1 move into `queue_wait_eval` (each anchor must still occur exactly once; do not duplicate the predicate in the `--queue-wait` branch). Extend `qw_scenario` with a runner-mode parameter (loop, bare step, fenced step, `--queue-wait`), add an `r6` kind for the existing second-attempt row, and give `argv_rc` a `QW_SUT` parameter so `qw_mutant` can drive F7; keep the `rc 2/127` instrument-failure guard for the new modes.
- Rows, each asserting HEAD unchanged and zero pushes via the recording git shim wherever the case is "refused" (F1 gets its OWN `f1_ok` predicate and its own H1-style control: swap in the non-recording shim and require `f1_ok` to go red):
  - **F1** `run_step_bare`, `ok:OPEN BEHIND:armed`, rule present → rc 14, `kind=queue_wait rc=14` (NOT `kind=queued`, which is also an rc-11 tag), nothing fetched/merged/pushed. **F1b** same with `UNKNOWN` → refused; **F1c** `UNKNOWN`, disarmed → syncs; **F1d** `UNKNOWN`, armed, no rule → syncs.
  - **F2** bare, BEHIND, armed, NO rule → syncs rc 0. **F3** bare, BEHIND, disarmed → syncs rc 0. **F4** bare, DIRTY, armed, rule present → syncs. (F2-F4 pass today: label them green-on-arrival controls, not RED.) **F4b** bare, CLEAN, armed, rule present → syncs (out of the predicate).
  - **F5** bare, parametrized over: rules read fails; `pr-view-mode=fail`; `pr-view-mode=hang` (bounded); `pr-view-mode=garbage` → each `kind=gh` rc 4, nothing moved, no ESC bytes echoed (including through the `queue_state_read` failure path, which echoes raw `gh` stderr today — see Phase 1.2).
  - **F6** `run_step` (now fenced) on the SAME `install_gh_wait` fixture as F1 → syncs rc 0 and the calls file holds NO `pr view` and NO rules call (guard skipped entirely); only the queue GraphQL read. Replaces R8's "unguarded" assertion.
  - **F7** mode combinations: `--fence` alone, `--fence --queue-state`, `--fence --queue-wait`, `--step --queue-wait`, `--queue-wait --queue-state`, `--queue-wait --max-attempts 2` → rc 2 `kind=usage`; `--help` names `--fence`, `--queue-wait`, exit 14 and cross-references `--queue-state`, and the existing `^  11 .*kind=noop` prefix of the exit table is preserved (an existing row asserts it, ~line 1346).
  - **F8** bare, PR IN the queue → unchanged `kind=queued rc=11`, no rules read, no `pr view`.
  - **W1** `--queue-wait` from OUTSIDE a worktree: `ok:OPEN BEHIND:armed` + rule → first stdout line exactly `queue_wait`; **W2** disarmed / no rule / DIRTY / CLEAN → `proceed`; **W3** `pr view` or rules read fails / hangs / garbage → `kind=gh` rc 4; **W4** a variant run INSIDE a worktree with a pre-seeded seen-queued marker asserts the marker is neither written nor consumed (outside a worktree there is no git dir, so a "no marker written" check there is vacuous); the mode makes exactly one `pr view` and one rules call and NO GraphQL queue read.
- Mutation rows (each mutant must differ from the SUT and land inside the predicate or the `--step` branch; one row per Guard 1 matrix line below): guard call deleted → F1; `DIRTY` exclusion dropped → F4; armed check dropped → F3; `--fence` runs the guard anyway → F6 (calls file); unreadable read treated as proceed, for the rules read AND for the `pr view` read separately → F5 variants; `UNKNOWN` dropped from the predicate → F1b; evaluate only on the first standalone attempt → R6; `--fence` accepted without `--step` → F7.

0.2 `.claude/hooks/pre-merge-rebase.test.sh`. Existing ids T-Q1..T-Q16 are taken (T-Q12 relative path, T-Q13 the pinned unparsed-spelling limitation, T-Q14 stdout noise, T-Q15 plugins dir absent, T-Q16 note on deny exits); new rows are **T-Q17..T-Q22**. Extend the `gh` stub BEFORE adding rows with explicit knobs: (i) a `pr view` branch ahead of the existing `--json headRefName,…` STUB-MISS guard, keyed on `autoMergeRequest`/`mergeStateStatus` in `--json`, answered from `mss-<N>` (`OPEN BEHIND`, `OPEN UNKNOWN`, `OPEN CLEAN`, or the failure modes `fail`, `hang`, `garbage`, `empty`) with the `--jq` program applied and the armed bit from the same file; (ii) an `api repos/…/rules/branches/main…` case (key `$1 $2`) answering the merge_queue count from `rules-merge-queue` (`0` default so every existing armed `not_queued` row keeps "syncs, no warn"; also `1`, `fail`, `hang`, `garbage`, `empty`); (iii) the queue answer for PR N may be a SEQUENCE (`not_queued,queued`, indexed by the count of lines in `gql-number`) so a read that flips between the hook's own `--queue-state` and a later read is expressible; (iv) reuse the existing `gh.log` / `_gh_logged_any` for call assertions (do not add a new log). The hook sets `PR_QUEUE_TIMEOUT="${PR_QUEUE_TIMEOUT:-5}"` so tests can inject 1 for hung variants; a hung-read row needs a "why this needs a real wait" comment (as T-Q5 has). Rows:
  - **T-Q17** `not_queued` + OPEN + armed + BEHIND + rule 1 → hook skips: no merge commit, no push, `additionalContext` names the merge queue, the sanctioned exits (red required check: push the fix, not a resync; green and never enqueued: merge-queue-dequeue.md "Armed and green but never enqueued"; the Phase 7 poll's expiry fallback) and the static `--admin` sentence. The same assertion loops over the resolvable spellings in the existing T-Q8 array (hoist it into a shared variable; includes `gh pr merge 4242 --squash --admin`-style forms with the number FIRST — flag-first is state L per T-Q13), so a skip that only handled the bare-number form is caught.
  - **T-Q18** UNARMED (stub mode `dequeued`) → syncs as before AND `gh.log` shows no `pr view … autoMergeRequest` call; the existing T-Q1 (queued) gets the same absence assertion. **T-Q18b** `OPEN UNKNOWN` armed + rule → skips; `OPEN CLEAN` armed + rule → syncs (outside the predicate).
  - **T-Q19** armed, rules count 0 → syncs, no warn. **T-Q22** `--queue-wait` answers `proceed` → syncs silently (no note, no warn).
  - **T-Q20** unreadable, parametrized over (non-zero rc incl. a fake old script whose `--queue-wait` exits 2; no matching stdout line; a forged `queue_wait` line followed by `proceed`; a verdict with a trailing suffix such as `queue_wait_x`; hung read) → syncs AND a named note (`cause=queue_wait_unreadable`) in `additionalContext` and on stderr. One variant is run across all four exit paths (disjoint-skip, conflict deny, push-fail deny, success — the T-Q10/T-Q16 shape); the rest on the success path only. The hook accepts a verdict ONLY when rc is 0 and exactly one line of the CR-stripped stdout matches `^(queue_wait|proceed)$`.
  - **T-Q21** the stub's queue answer sequence `not_queued,queued` (a PR that entered the queue between the hook's reads): the hook's own later checks never push to it; if the first read is `not_queued` and `--queue-wait` runs, `autoMergeRequest` set means `queue_wait` (stricter direction).
  - Instrument rows: the gh stub records `PR_QUEUE_ATTEMPTS` and `PR_QUEUE_TIMEOUT` of the `--queue-wait` invocation and the test asserts them (kills the "drop the bound" mutant deterministically); the `_to` wrapper is exercised with the T-Q6/T-Q14 helper-copy technique (a `--queue-wait` branch that sleeps past it). Assert `dt <= bound`, never equality.
  - Parity: `.claude/hooks/pre-merge-rebase-parity.test.sh` and `-headless.test.sh` re-run unchanged (read first; extend only if they enumerate output shapes).

0.3 `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (covers both the ship block and the merge-pr mirror): (a) update the literal-string assertions (~214-215, ~1075, ~1624) and the skew fixture at ~1067 whose fake script's `--help` lacks `--step` — add a SECOND skew fixture whose `--help` has `--step` but no `--fence`, the only row that goes red if the probe is reverted, expecting `its --help has no --fence (an older copy)` and sync disabled; pin exactly one `--step --fence` call per block (the existing `grep -cF '… --step'` count matches both spellings); (b) the QGH stub's rules arm matches `rules/branches/main` but the child asks for `…main?per_page=100`, so the child gets an empty answer and exits 4 — change the arm to a `main*` glob, otherwise the existing Q6/Q6e/Q6b/`Q6-settled-*` rows go red for the wrong reason; (c) add ONE new row: run the fence with `--fence` stripped from the block via `sed` and assert it stops with `sync_failed … exited 14` (never reaching its `11)` arm, never printing `pushed`) — this pins ADR residual 3. The expiry-fallback-still-syncs behaviour is already covered by the existing Q6 rows (do not duplicate), and the selector-parity row is dropped (already covered by `pr-merge-poll.test.ts` "the merge_queue rule selector is the same literal in the script and both fences"). Ratchet `MIN_VERDICTS`.

0.4 `plugins/soleur/test/pr-merge-poll.test.ts`: change the pin at ~line 113 (regex `--step\`[^.]*never yours; unguarded by design`) to the new wording — keep the backtick right after `--step`, no `.` before the pinned phrase, and the literal `sync-pr-behind.sh <PR-number> --step` at ~line 47 verbatim (do NOT append `--fence` anywhere in an instruction surface); update the exit-11 pins at ~83-84 for the new 14 row; change the probe assertion at ~225-226 from `--step` to `--fence`; add a test that no instruction surface other than the two fence blocks and the script's own `--help` contains the string `--fence` (walk `behindSyncInstructions` for every harness, `drain-prs/SKILL.md`, `harness.ts`, the codex/devin INSTRUCTIONS files, `plugins/` and `.github/`), and that nothing but the two fences and the tests calls `sync-pr-behind.sh … --step` (`grep` over `plugins/` and `.github/`).

0.5 `plugins/soleur/test/workflow-fidelity.test.ts` (~line 639): add positive expectations that `AGENTS.rules.md` still contains `BEHIND` and `resync main` AND `merge-queue repo` and `queue makes it current` (the final wording is fixed in Phase 5.1 before the pins and the hash are written).

0.6 Confirm RED and keep the failing-row list for the PR description. Long suites run through the repo's rc-file wrapper pattern (see `ship/SKILL.md` test-battery guidance), never with unbounded output.

### Phase 1 — `plugins/soleur/scripts/sync-pr-behind.sh`

1.1 Refactor `queue_wait_gate` into an evaluator `queue_wait_eval <state_line> <armed|disarmed|->` that ALWAYS returns 0 and reports through `QW_VERDICT=wait|proceed|unreadable` plus `QW_DETAIL` (preset `QW_VERDICT=proceed` before any early return so `set -u` is safe; distinct non-zero returns are a trap under `set -euo pipefail`). Predicate: `state` OPEN, `mergeStateStatus` BEHIND or UNKNOWN and not DIRTY, armed, and the `merge_queue` rule count >= 1 (rules read selected by `.type`, 100-rule page, `PR_QUEUE_ATTEMPTS`/`TIMEOUT`/`RETRY_SLEEP`, `tr -c` sanitising of the detail, attempt count `n` carried in `QW_DETAIL`; the `mktemp` failure becomes `QW_VERDICT=unreadable`, no `exit`). The standalone loop keeps its current behaviour byte-for-byte: `queue_wait_gate` passes its own `state_line` and the `$am` from `queue_gate`'s `QS_OUT`, then wraps the verdict (`wait` → `tag queue_wait 0 …; exit 0`; `unreadable` → `tag gh 4 …; exit 4`). One shared refusal-message constant is used by all callers (standalone, flagless `--step`), and it is the existing standalone guidance: the queue makes it current; with no poll running re-arm the Phase 7 poll with `CLAUDE_PLUGIN_ROOT` exported (its expiry fallback is the sanctioned sync); red required check → push the fix, not a resync; green and never enqueued → merge-queue-dequeue.md "Armed and green but never enqueued".
1.2 Hardening that the new reads make reachable: in `queue_state_read` run the same `tr -c '[:alnum:] ._:/=-' '?'` pass over `QS_DETAIL` (today it strips only newlines, so ESC/CR from `gh` stderr reach the `kind=gh rc=4` line a Monitor streams to the model); every new `gh pr view` read goes through the same `timeout`/`gtimeout` array and `PR_QUEUE_REPO` handling as the other reads (`--repo "$PR_QUEUE_REPO"` when set), with `2>/dev/null` (never merged into the string the predicate tests) and a strict match `^(OPEN|CLOSED|MERGED) [A-Z_]+$` on the `<state> <mergeStateStatus>` line (the armed bit is read as a separate `autoMergeRequest != null` field of the same snapshot).
1.3 Argument parser: add `--fence` (sets `FENCE=1`) and `--queue-wait` (sets `MODE=queue_wait`). After the loop validate: `FENCE=1` requires `MODE=step`; at most one mode flag; `--queue-wait` takes no `--max-attempts` (extend the existing `MODE != loop && MAX_ATTEMPTS != 1` check). Violations are `usage_err` (the script's strictness invariant: an older copy that ignored unknown flags once printed a false "pushed").
1.4 `--step` branch (after `queue_gate`): when `FENCE != 1`, take ONE bounded `gh pr view "$PR" --json state,mergeStateStatus,autoMergeRequest` snapshot, run `queue_wait_eval` on it; `wait` → `tag queue_wait 14 "<shared message>; if this copy of the fence predates --fence, re-paste the fence from the current ship/SKILL.md"` and `exit 14`; `unreadable` → `tag gh 4 …; exit 4` (fail closed, same as standalone). When `FENCE == 1` skip the guard entirely (no extra read). The refusal line does not advertise the flag beyond that one re-paste clause, and opens with "NOT AN ERROR in itself" so an errexit reader does not fall back to a hand merge.
1.5 `--queue-wait` mode, handled beside `--queue-state` before the worktree check: ONE bounded `pr view` snapshot (no `queue_state_read`: the hook already classified queued/not_queued, so there is no duplicate GraphQL read and no just-dequeued-still-reads-armed race), then the same rules read and `queue_wait_eval`; prints exactly one stdout line `queue_wait` or `proceed` and exits 0; any failed/hung/garbage read → `kind=gh` rc 4 (fail closed: never read as "not armed"). Armed means `autoMergeRequest != null` from that snapshot, so an armed PR already in the queue also reads `queue_wait` (the stricter, safe direction). Writes nothing (no marker). Contract in `--help`: answers the OPEN/BEHIND-or-UNKNOWN/armed/rule predicate only; callers read `--queue-state` first.
1.6 Text: `usage()` gains `--step [--fence]` and `--queue-wait` lines (one clause defining `--fence`: "the Phase 7 / merge-pr poll fences pass this; nobody else"; `--queue-wait` cross-references `--queue-state`: "`--queue-state`: is the PR in the queue; `--queue-wait`: should a sync be skipped"); a new exit-code table row `14  flagless --step on an armed BEHIND/UNKNOWN PR of a merge-queue repo (kind=queue_wait): nothing fetched, merged or pushed` plus a note that `kind=queue_wait` carries rc 0 standalone and rc 14 under `--step`, so no consumer keys on `kind` alone; row 11 keeps its `kind=noop` prefix; header comments at ~lines 4-9 (caller list: the fences pass `--fence`), ~51-55 and ~325-337 drop "`--step` is NOT guarded".
1.7 `shellcheck -S warning plugins/soleur/scripts/sync-pr-behind.sh`; flip `run_step` to `--fence` (and the S1 row); Phase 0.1 suite GREEN, existing and new mutation rows green against the real SUT.

### Phase 2 — `.claude/hooks/pre-merge-rebase.sh`

2.1 After the queued-skip block (~line 748) and before the disjoint-delta skip: parse fields 2-3 of `_q_first`; when `_q_state == not_queued`, field 2 is `OPEN` and field 3 is `armed`, run `(cd "$WORK_DIR" && PR_QUEUE_ATTEMPTS=1 PR_QUEUE_TIMEOUT="${PR_QUEUE_TIMEOUT:-5}" ${_to20[@]+"${_to20[@]}"} bash "$_QS_SH" "$PR_HEAD_NUMBER" --queue-wait 2>/dev/null)` where `_to20` is a 20-second `timeout -k 2` / `gtimeout` wrapper (the existing `_to` is 10 s; the call is two reads of at most 5 s each plus kill grace, and a wrapper shorter than the reads would fail OPEN into the push the guard exists to prevent). Verdict table, explicit: rc 0 AND exactly one line of the CR-stripped stdout matching `^(queue_wait|proceed)$` — `queue_wait` → skip (`headless_or_stderr info …`, `additionalContext`, `exit 0`); `proceed` → sync silently; anything else (non-zero rc incl. 124, zero or several matching lines, a suffix) → append a `queue_wait_unreadable` sentence to the existing `_Q_NOTE` (reusing its four exit-path plumbing; no second note variable) and fall through to today's sync. Never parse text out of the script's `kind=gh` line for this path. The skip context carries ONE copy of the guidance (no sync needed — the queue makes it current; red required check: push the fix, not a resync; green and never enqueued: merge-queue-dequeue.md "Armed and green but never enqueued"; the Phase 7 poll's expiry fallback is the sanctioned sync) and one static sentence that a `--admin` merge bypasses the queue and lands the head as pushed (gate it with `plugins/soleur/scripts/admin-merge-ready.sh`) — no new `--admin` parsing. A comment states that a PR GitHub never enqueues or that stays UNKNOWN makes this skip quiet and bounded, with the fence's expiry fallback performing the sync.
2.2 Update the header comment (~line 20) and keep stdout/JSON hygiene (all git output redirected).
2.3 `shellcheck -S warning .claude/hooks/pre-merge-rebase.sh`; Phase 0.2 suites GREEN.

### Phase 3 — the two fences

3.1 `plugins/soleur/skills/ship/SKILL.md`: probe `grep -q -- '--step'` → `grep -q -- '--fence'` with message `its --help has no --fence (an older copy)` (~line 2278) and the stale comment at ~2267; call `bash "$SYNC_SNAP" "$PR" --step || sync_rc=$?` → `bash "$SYNC_SNAP" "$PR" --step --fence || sync_rc=$?` (~line 2457). In the "Auto-sync on BEHIND" paragraph (~line 2514) keep exit 11 as `kind=noop` / `kind=queued` and add one clause that any other non-zero exit (including 14 `kind=queue_wait` from a copy that predates `--fence`) stops the poll with the line above it naming the action. Correct ~line 2544 ("The two surfaces don't overlap") to say the hook also skips an armed BEHIND PR on a queue repo.
3.2 `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 mirror fence: the same probe and call edits (~lines 408 and 552) and the comment at ~405.
3.3 Update the fixture assertions (Phase 0.3); run `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`; confirm `ship` stays <= 273955 B.

### Phase 4 — text surfaces that state the old behaviour (one line each; the ADR addendum is the record)

4.1 `plugins/soleur/lib/pr-merge-poll.ts`: replace "(the Phase 7 fence's call, never yours; unguarded by design)" (~line 82) with a wording that keeps `--step\`` immediately followed by "never yours" with no `.` between, and says the script refuses a flagless `--step` on an armed BEHIND PR of a merge-queue repo (`kind=queue_wait`, exit 14); do NOT print the flag name. Add the 14 row where exit codes are listed (~lines 75, 83-84). CANON phrase and other surfaces untouched.
4.2 `plugins/soleur/skills/ship/references/queue-mode.md`: rewrite ONLY boundary (1) of "Standalone guard" (the `--step` unguarded bullet) to a one-line pointer to the ADR-270 2026-10-20 addendum; `plugins/soleur/skills/ship/references/merge-queue-dequeue.md` line ~15 ("the pre-merge hook … only skips the sync for a queued PR") gets the armed-BEHIND clause; `knowledge-base/project/constitution.md` ~line 177 (the `[hook-enforced: pre-merge-rebase.sh]` merge-main rule) gets one clause that the hook skips an armed BEHIND PR on a queue repo.
4.3 `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/harness.test.ts plugins/soleur/test/antigravity-harness.test.ts` GREEN.

### Phase 5 — the rule edit (#9868), under the AGENTS gates

5.1 FIX THE WORDING FIRST (the pins, the hash and the ack bind to it). In `AGENTS.rules.md` line 65 change only the tail `BEHIND→resync main` to `BEHIND→resync main via the Phase 7 poll, except an armed PR on a merge-queue repo (the queue makes it current; sync-pr-behind.sh refuses it)`. It contains the pinned substrings `BEHIND`, `resync main`, `merge-queue repo` and `queue makes it current`, makes no "only the expiry fallback syncs it" claim (the fence also syncs on `QUEUE_RULE=0`, DIRTY-derived BEHIND and an armed-read failure), points a post-compaction reader at the executable that decides, and omits the test-banned `[ship.phase7.queue_wait]` marker. Keep the id, the `[skill-enforced: workflow-fidelity.ts]` tag and the one-line `**Why:** #6325.` Measure: the line grows from 234 B to ~360 B (cap ~600 B per rule, cq-agents-md-why-single-line); payload 39160 B to ~39290 B (warn 44000).
5.2 `python3 scripts/lint-rule-bodies.py --write` regenerates `.claude/rule-body-hashes.txt` (only the one row changes).
5.3 Append one line to `.claude/rule-weakening-acks.txt` (append-only, WORM; never edit an existing line): `hr-pipeline-skills-never-inline-after-go-route|<new sha256 from the manifest>|2026-10-20|10655|adds the merge-queue armed-BEHIND exception to the resync default (a narrowing, stated as such; matches queue-mode.md and the sync script refusal; the default resync is unchanged elsewhere)`. Automated step by the implementing agent. `.claude/rule-weakening-acks.txt`, `AGENTS.rules.md` and the manifests are CODEOWNERS-owned (`@deruelle`) and the ack is self-attested by the author of the edit; the PR body must say the change adds an exception to a hard rule and is awaiting code-owner review, and ship must not treat its own approval as that review. No operator step is added: the `rule-body-lint` job verifies the hash-bound ack mechanically.
5.4 `cq-rule-ids-are-immutable`: the id string is unchanged; `python3 scripts/lint-rule-ids.py` passes. `cq-agents-md-tier-gate`: record in the PR body why this stays in AGENTS (cross-cutting session invariant; the issue's premise is compaction survival) rather than migrating to the enforcer (CTO Fork 4).
5.5 `python3 scripts/lint-agents-rule-budget.py`, `python3 scripts/lint-agents-enforcement-tags.py`, `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` and `bun test plugins/soleur/test/workflow-fidelity.test.ts` GREEN.

### Phase 6 — ADR addendum

Author the ADR-270 addendum named in "Architecture Decision (ADR/C4)" via the `soleur:architecture` skill workflow (state the residuals once, here); also add a one-line pointer to it at the ADR's older sentences (~lines 178-180 and 187) rather than only a supersedes sentence. `bash scripts/check-adr-ordinals.sh` (no new ordinal) and `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 7 — validation

Run all suites above to GREEN (long suites through the rc-file wrapper), then `bash scripts/test-all.sh --affected` once under the lock. Confirm AC-X1.

## Files to Edit

- `plugins/soleur/scripts/sync-pr-behind.sh`
- `.claude/hooks/pre-merge-rebase.sh`
- `plugins/soleur/skills/ship/SKILL.md` (fence probe + call site, the exit-code clause at ~2514, the "surfaces don't overlap" sentence at ~2544)
- `plugins/soleur/skills/merge-pr/SKILL.md` (mirror fence probe + call site only)
- `plugins/soleur/skills/ship/references/queue-mode.md`
- `plugins/soleur/skills/ship/references/merge-queue-dequeue.md` (one clause, ~line 15)
- `knowledge-base/project/constitution.md` (one clause, ~line 177)
- `plugins/soleur/lib/pr-merge-poll.ts`
- `AGENTS.rules.md`
- `.claude/rule-body-hashes.txt`
- `.claude/rule-weakening-acks.txt`
- `plugins/soleur/test/sync-pr-behind.test.sh`
- `.claude/hooks/pre-merge-rebase.test.sh`
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`
- `plugins/soleur/test/pr-merge-poll.test.ts`
- `plugins/soleur/test/workflow-fidelity.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9869-9868-queue-behind-refusal/tasks.md` (derived from this plan)
- (already created) `knowledge-base/project/specs/feat-one-shot-9869-9868-queue-behind-refusal/decision-challenges.md`

Glob/path verification: every Files-to-Edit path was confirmed with `git ls-files` on this branch (the two same-named suites `plugins/soleur/scripts/sync-pr-behind.test.sh` — a different, regen-arm suite — and `plugins/soleur/test/sync-pr-behind.test.sh` — the one this plan extends — differ; only the `test/` one is edited).

## Guard Contract

### Guard 1 — flagless `--step` refusal

**Property.** No `sync-pr-behind.sh <PR> --step` invocation made without the fence-only opt-in flag fetches, merges or pushes when the PR is OPEN, GitHub reports BEHIND or UNKNOWN (never DIRTY), auto-merge is armed and `main` has a `merge_queue` rule.

**Assembly.** The chokepoint is the `--step` branch of `sync-pr-behind.sh` (`if [[ "$MODE" == step ]]`) between `queue_gate` and `sync_step`; the predicate is the single `queue_wait_eval` function shared with the standalone loop's `queue_wait_gate` and the `--queue-wait` mode. Push writers on this path: `sync_step` (reached by `--step` AND by the standalone loop) and the standalone loop's DIRTY arm (`resolve-regenerable-conflicts.sh` commits locally, reached only after `queue_wait_gate`); the hook's own push is Guard 2. The only sanctioned `--fence` callers are the two fences, each with exactly ONE `--step --fence` call site (pinned per block by the fixture); a third copy of the fence, or any other caller of `--step` under `plugins/` or `.github/`, fails the grep test in Phase 0.4.

**Mutation matrix.**

| # | Mutation (edit that MUST drive the suite RED) | Row that goes red |
|---|---|---|
| 1 | Delete the guard call in the `--step` branch (also covers a guard that is never reached) | F1 (flagless armed BEHIND rule: moved/pushed) |
| 2 | Drop the `DIRTY` exclusion from the predicate | F4 (DIRTY armed must still sync) |
| 3 | Drop the `armed` check from the predicate | F3 (disarmed must still sync) |
| 4 | Treat an unreadable rules read as "proceed"; separately, an unreadable `pr view` read as "proceed" | F5 variants (must be `kind=gh` rc 4) |
| 5 | Make `--fence` run the guard anyway (extra `pr view`) | F6 (the calls file must hold no `pr view` / rules call) |
| 6 | Evaluate the predicate only on the first standalone attempt (second member after a compliant first sync) | R6 (second attempt must still answer `kind=queue_wait`) |
| 7 | Accept `--fence` without `--step`, or accept two mode flags | F7 |
| 8 | Drop `UNKNOWN` from the predicate | F1b |

**Harness rows.** (a) A SUITE edit that must go RED: swap the recording git shim for a non-recording one and require F1's own `f1_ok` ("no push") to fail, so "refused" cannot pass vacuously. (b) Must-PASS inputs that are not the canonical refused case and differ in a way the contract permits: F2 (no rule), F3 (disarmed), F1c/F1d (UNKNOWN unarmed / no rule), F4 and F4b (DIRTY, CLEAN), F8 (in the queue) — a guard that refuses everything fails them.

**Anchor.** The suite's expected values are literals in the test file, in the same diff as the script, so one diff could weaken both. The outside anchors are the fence fixture (it drives the REAL script as a child and pins one `--step --fence` call per block plus the stripped-flag exit-14 stop), the pre-existing `qw_mutant` anchors, the grep test that no surface teaches `--fence`, and the merge-base `lint-skill-body-budget` / `rule-body-lint` CI jobs.

### Guard 2 — pre-merge hook skip

**Property.** For every `gh pr merge` form the hook's parser resolves to one PR, the hook performs no `git merge origin/main` and no `git push` when that PR is OPEN, armed, GitHub-BEHIND or UNKNOWN, and `main` has a `merge_queue` rule (or the PR is already in the queue).

**Assembly.** The chokepoint is the hook's single sync section (`git merge origin/main` at ~line 804, `git push origin HEAD` at ~line 858), reached only through the flow after the queued-skip block; every resolvable `gh pr merge` argument form flows through it (the T-Q8 spelling array: number after flags, `-R`, `#N`, chained `cd`, `--admin` written after the number). The skip is placed before the disjoint-delta skip and the `rebase-main` lock so no later path can reach the push. Unresolved spellings (T-Q13) are out of the property by construction and pinned as such.

**Mutation matrix.**

| # | Mutation (edit that MUST drive the suite RED) | Row that goes red |
|---|---|---|
| 1 | Remove the new skip block | T-Q17 (merge/push happened) |
| 2 | Read `armed` from the wrong field (unarmed PR skipped) | T-Q18 (unarmed must sync; `gh.log` must hold no `autoMergeRequest` pr view) |
| 3 | Treat a non-zero `--queue-wait` exit, a forged/suffixed line or no matching line as `queue_wait` | T-Q20 variants |
| 4 | Accept a verdict line without requiring exactly one match | T-Q20 forged-then-proceed variant |
| 5 | Make the skip apply to only some spellings of the T-Q8 array | T-Q17 looped assertion |
| 6 | Drop `PR_QUEUE_ATTEMPTS=1` / the `PR_QUEUE_TIMEOUT` bound, or shorten the outer wrapper below the reads | the instrument row (stub records the env) and the wrapper helper-copy row |
| 7 | Call `--queue-wait` on every merge instead of only armed not_queued | T-Q18 and T-Q1 `gh.log` absence assertions |
| 8 | Drop `UNKNOWN` from the predicate | T-Q18b |

**Harness rows.** (a) A SUITE edit that must go RED: make the stub answer rules count 1 for every PR and require the must-PASS rows T-Q18 / T-Q19 to fail. (b) Must-PASS inputs: T-Q18 (unarmed), T-Q19 (no rule), T-Q22 (`proceed`), `OPEN CLEAN` armed, and the existing T-Q2 (not queued, armed, default rules 0) still sync, proving the skip does not fire on everything.

**Anchor.** The hook calls the script's `--queue-wait` rather than re-implementing the predicate, so the hook suite proves wiring and the script suite (W1-W4) proves the predicate; neither can pass by editing only the other. The parity suite `pre-merge-rebase-parity.test.sh` is the outside check that the hook's output shapes did not drift.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC-S1** `bash plugins/soleur/test/sync-pr-behind.test.sh` exits 0 with the new F/W rows and mutation rows present (grep the suite output for `F1`..`F8`, `W1`..`W4`) and the exact-pass-count pin on its last line equals the new total (greater than 122).
- [ ] **AC-S2** Flagless `--step` on an armed BEHIND (or UNKNOWN) PR of a merge-queue repo prints `[pr-behind-sync] kind=queue_wait rc=14` and exits 14 with HEAD unchanged; `--step --fence` on the same fixture syncs and the calls file holds no `pr view` and no rules call.
- [ ] **AC-S3** `bash plugins/soleur/scripts/sync-pr-behind.sh --help` contains `--fence`, `--queue-wait` and an exit-14 row, still starts the exit-11 row with `kind=noop`; `--fence` without `--step` and any two mode flags exit 2.
- [ ] **AC-H1** `bash .claude/hooks/pre-merge-rebase.test.sh`, `-parity.test.sh` and `-headless.test.sh` exit 0; T-Q17..T-Q22 present and listed in the case list with `EXPECTED_CASES` raised; an unarmed, no-rule, `proceed` or unreadable case still syncs (never blocks).
- [ ] **AC-F1** `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` exits 0 with `MIN_VERDICTS` ratcheted up; both fences contain exactly one `--step --fence` call and probe `--fence`; a has-`--step`-but-no-`--fence` snapshot fixture disables auto-sync with the `--fence` precondition message; the fence with `--fence` stripped stops with `sync_failed … exited 14`.
- [ ] **AC-F2** `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` exits 0 and `wc -c plugins/soleur/skills/ship/SKILL.md` is <= 273955.
- [ ] **AC-T1** `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/workflow-fidelity.test.ts plugins/soleur/test/harness.test.ts` exits 0; the old `unguarded by design` string is gone from `plugins/soleur/lib/pr-merge-poll.ts` (`grep -c 'unguarded by design' plugins/soleur/lib/pr-merge-poll.ts` prints 0).
- [ ] **AC-R1** `AGENTS.rules.md` line for `hr-pipeline-skills-never-inline-after-go-route` contains `BEHIND→resync main via the Phase 7 poll, except an armed PR on a merge-queue repo (the queue makes it current; sync-pr-behind.sh refuses it)`, keeps its `[id: ...]` and `[skill-enforced: workflow-fidelity.ts]` tags, and is <= 600 B (`awk` on that line).
- [ ] **AC-R2** `python3 scripts/lint-rule-ids.py` and `python3 scripts/lint-agents-rule-budget.py` and `python3 scripts/lint-agents-enforcement-tags.py` exit 0; `wc -c AGENTS.rules.md` < 44000.
- [ ] **AC-R3** `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` exits 0 (manifest regenerated and exactly one new ack line appended; `git diff origin/main -- .claude/rule-weakening-acks.txt` shows additions only).
- [ ] **AC-R4** `git diff origin/main -- scripts/retired-rule-ids.txt` is empty and the rule id string is byte-identical (rule ids immutable).
- [ ] **AC-A1** The ADR-270 addendum exists (`grep -n 'Addendum 2026-10-20' knowledge-base/engineering/architecture/decisions/ADR-270-*.md`), and `bash scripts/check-adr-ordinals.sh` and `bash plugins/soleur/test/c4-count-parity.test.sh` exit 0.
- [ ] **AC-G1** `grep -rn -e '--fence' plugins .github --include=* ` (excluding the two fence blocks, `sync-pr-behind.sh`, the test files and this plan/spec directory) returns nothing; no caller of `sync-pr-behind.sh … --step` exists outside the two fences and the tests (Phase 0.4 test).
- [ ] **AC-X1** No file outside the Files-to-Edit/Create lists is modified, plus this plan and its spec directory (`git diff --name-only origin/main...HEAD` is a subset of those); comment-only edits inside listed files (e.g. the fence comment at `ship/SKILL.md` ~2267) are in scope.
- [ ] **AC-X2** The PR #10655 body uses `Ref #9869` and `Ref #9868` and contains none of `closes`/`fixes`/`resolves` adjacent to those numbers (the ship step owns the body); the PR title is not `WIP:`.

### Post-merge

None. #9869's re-evaluation criterion (a `kind=pushed` line on an armed, not-yet-enqueued PR) is an observational recurrence trigger that depends on unrelated sessions, so it is deliberately not an acceptance criterion (plan-review standing check `cq-ac-must-not-depend-on-concurrent-sessions`); the deterministic fixtures F1/T-Q12 carry the property, and a recurrence reopens the issue.

## Test Scenarios

(see Phase 0.1-0.5 for the row-level lists; summary of intent)

1. Flagless `--step` on armed+BEHIND+queue repo: refused with exit 14 and no git side effects (F1); fence call with `--fence` still syncs (F6) — an expiry fallback and a DIRTY-derived BEHIND each get a fixture through the real script child (P3).
2. Predicate edges: disarmed (F3), no rule (F2), DIRTY (F4), CLEAN (F4b), UNKNOWN armed/disarmed/no-rule (F1b-d), in-queue (F8), unreadable x4 (F5), mode-flag misuse (F7).
3. `--queue-wait` read-only verdicts and failure modes without a worktree (W1-W4).
4. Hook: skip on armed+BEHIND/UNKNOWN+rule across the T-Q8 spelling array, queue-sequence race, silent sync on `proceed`/CLEAN, fall-through with a named note on unreadable/forged/hung read, no extra call on queued/unarmed paths (T-Q17..T-Q22).
5. Fences: probe tightening against an old snapshot (P7); an old fence against a new script stops loudly on exit 14 (pinned by stripping `--fence` from the block).
6. Rule text: exception present, tags intact, marker-ban class not matched, hash + ack consistent.

## Observability

```yaml
liveness_signal:
  what: "[pr-behind-sync] kind=queue_wait rc=14 (flagless --step) and kind=queue_wait rc=0 (standalone) tagged stdout lines; hook additionalContext 'is BEHIND with auto-merge armed' — local developer-machine tooling, no daemon"
  cadence: "per invocation (per Phase 7 tick that reaches the sync arm; per gh pr merge for the hook)"
  alert_target: "the invoking agent session (Monitor streams stdout) — the refusal line names the next action"
  configured_in: "plugins/soleur/scripts/sync-pr-behind.sh (tag/usage) and .claude/hooks/pre-merge-rebase.sh (additionalContext)"

error_reporting:
  destination: "stdout tagged lines (Monitor streams stdout only); the hook's stderr is routed by headless_or_stderr to the session-state log when headless; no Sentry (CLI tooling on the developer host, not a server surface)"
  fail_loud: "unreadable reads print kind=gh rc=4 (script) or a named queue_wait_unreadable note in additionalContext (hook) — never silent"

failure_modes:
  - mode: "false refusal: a legitimate fence sync is refused (old fence + new script, or flag omitted)"
    detection: "an old pasted fence stops with [ship.phase7.sync_failed] … exited 14 plus the kind=queue_wait line above it; the ship fixture asserts both fences pass --fence and probe for it"
    alert_route: "agent session output; the AC-F1 fixture fails pre-merge"
  - mode: "false skip: the hook skips a sync for a PR that is not actually waiting on the queue (stale armed read)"
    detection: "additionalContext names the skip; a later GitHub not-up-to-date refusal is the signal; the context itself carries the recipe (push the fix for a red check; merge-queue-dequeue.md for armed-green-never-enqueued)"
    alert_route: "agent session output"
  - mode: "rules/state read unreadable"
    detection: "kind=gh rc=4 line (script) / queue_wait_unreadable note (hook), grep-able in session logs"
    alert_route: "agent session output; retry guidance is on the line"

logs:
  where: "stdout of the invoking Monitor / Bash call; hook output in the session transcript and $GIT_COMMON_DIR/soleur-session-state/logs when headless"
  retention: "session transcript lifetime"

discoverability_test:
  command: bash plugins/soleur/scripts/sync-pr-behind.sh --help
  expected_output: "--fence"
```

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this plan fills it (threshold `none`, with the scope-out reason).
- `--fence` is accident prevention, not authentication: a hand-rolled loop that types it bypasses the guard (documented residual in the ADR addendum; the usage text says "only the fences pass this").
- An OLD fence paired with the NEW script: its sync arm runs flagless `--step` and gets exit 14, which its `*)` arm turns into `[ship.phase7.sync_failed] … Stopping the poll.` — loud and bounded, with the script's `kind=queue_wait` line above it naming the action (re-paste the fence). Exit 11 was rejected for this because the old `11)` arm prints "no sync needed" and livelocks silently (CTO Fork 2'). A NEW fence with an OLD script is stopped by the tightened `--fence` probe. In-flight sessions hold pasted fences that are never re-read from disk, so this pairing is not purely theoretical (ADR addendum residual 3).
- The hook skip also applies to `--admin` (consistent with the queued skip). `--admin` bypasses the queue, so "the queue makes it current" does not hold there — the context says so and points at `admin-merge-ready.sh`. If harm is observed, flip to "keep syncing for `--admin`" (CTO Fork 3 risk note).
- The existing hook tests' `not_queued` stub is ARMED; the new hook call would STUB-MISS in every such row unless the stub answers the `--queue-wait` reads (a `pr view --json state,mergeStateStatus` branch ahead of the existing `--json headRefName,…` STUB-MISS guard, with the `--jq` program applied, and an `api repos/…/rules/branches/main` case) with defaults (rules count 0). Phase 0.2 extends the stub first; do not weaken the "no warn" assertions to compensate.
- The script runs under `set -euo pipefail`: `queue_wait_eval` must always return 0 and report through `QW_VERDICT` (a distinct non-zero return would kill the script on the common `proceed` path), and every new `gh pr view` read goes through the same `timeout`/`gtimeout` array as the other reads (a hung read inside a PreToolUse hook that then takes the 60 s `rebase-main` lock is the worst case).
- Floors are hand-maintained: `sync-pr-behind.test.sh` pass-count pin (122), `pre-merge-rebase.test.sh` `EXPECTED_CASES=69` and case list, `ship-phase-7-poll-fixtures.test.sh` `MIN_VERDICTS=1093`. Forgetting one fails the suite on its last line, not on the new row.
- Existing hook test ids T-Q1..T-Q16 are taken; new rows start at T-Q17, and `gh pr merge --squash --admin 4242` (flag before the number) is state L (T-Q13) and never reaches the queue read — use `gh pr merge 4242 --squash --admin`.
- `run_step_fence` (the renamed `run_step`) carries `--fence` in the script suite so the ~40 existing `--step` rows keep asserting the fence path; only the F-rows run flagless. Do not delete a row to make Phase 1 pass.
- `rule-weakening-acks.txt` is append-only and hash-bound: run `--write`, then copy the NEW hash from `.claude/rule-body-hashes.txt` into the ack; an ack written before the final wording edit is a stale hash and reds `rule-body-lint`.
- Sanitise: the refusal text includes the PR number only (digits-validated) — no stderr text from `gh` is echoed raw (the existing `tr -c` pass stays on `QW_DETAIL`).
- Do not paste the `[ship.phase7.queue_wait]` marker into the AGENTS rule: `pr-merge-poll.test.ts` bans marker-conditioned exception wording across the root AGENTS files.
