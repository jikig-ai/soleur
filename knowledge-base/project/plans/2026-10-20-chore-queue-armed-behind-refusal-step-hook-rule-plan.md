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

1. **P1** A caller of `sync-pr-behind.sh <PR> --step` that is not a Phase 7 fence cannot push to a BEHIND (not DIRTY), armed PR on a repo whose `main` has a `merge_queue` rule.
2. **P2** For every `gh pr merge` form the hook's parser resolves to one PR (the same forms the queued-skip covers; unresolved spellings stay state L and still sync, pinned by the existing KNOWN LIMITATION case), the hook cannot push a sync to such a PR.
3. **P3** The fences' legitimate sync arms (queue-wait expiry fallback, DIRTY-derived BEHIND, `QUEUE_RULE=0`, armed-read failure) still sync, with no added `gh` calls per tick.
4. **P4** The always-injected BEHIND rule states the queue exception, so it survives a context compaction.
5. **P5** The BEHIND-armed-rule predicate is written once in the script; the standalone loop, flagless `--step` and the hook read it from there.
6. **P6** Unreadable answers resolve in the direction each caller already owns: script callers fail closed (`kind=gh`, exit 4), the hook falls through to today's sync with a named note, never a block.
7. **P7** A new fence never pairs silently with an old script snapshot (and an old fence paired with a new script degrades to a bounded wait, never a false "pushed").

### Cut List (Phase 0.6b)

| Mechanism proposed or implied | Property it would buy | What already covers it / why cut |
|---|---|---|
| Fences call a new `--queue-rule` mode instead of their inline rules read (issue sketch) | P5 for the fences | Fences' `QUEUE_RULE` also folds in the required-check test the script does not read; the fences only need P3, which the `--fence` flag buys. Cut. |
| Per-arm override flags at each fence arm (expiry, DIRTY-derived, QUEUE_RULE=0) | P3 | All arms share ONE call site per fence; one flag there covers them. Cut. |
| Hook also skips the pre-arm sync on queue repos | none requested | The first `gh pr merge --auto` arm is the pre-sync the hook exists for (CTO Fork 3). Cut (non-goal). |
| Migrate the rule body into `workflow-fidelity.ts` (tier-gate "already-enforced" path) | P4 | Defeats P4: the rule line is the one statement injected on every SessionStart. Cut (CTO Fork 4). |
| New exit code for the flagless refusal | P7 | Exit 11 is the fences' uncounted no-op arm already (CTO Fork 2). Cut. |
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

Amend ADR-270 (`knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`) with a new `### Addendum 2026-10-20 (#9869, #9868): --step and the pre-merge hook refuse an armed BEHIND PR on a merge-queue repo` placed after the 2026-10-09 addendum. It records: flagless `--step` refuses (`kind=queue_wait`, exit 11) and the fences opt out with `--fence`; `--queue-wait` read-only mode; the hook skip and its fall-through direction; the `--admin` consequence; supersedes the 2026-10-09 sentence "`--step` stays the Phase 7 fence's unguarded call" and the accepted residual in Decision 5 prose (~line 178) for these two writers. Accepted residuals, stated so they are not rediscovered: (1) a hand-rolled loop that types `--fence` itself; (2) the fences pass `--fence` at their single call site, so the fence's own fail-open arms (armed-read flake, rules-read failure, `QUEUE_RULE=0`) still sync by design (P3), the guard only catches callers that are NOT the fence; (3) an OLD fence paired with the NEW script gets exit 11 from its expiry fallback and re-polls until `MAX_POLL_MIN` without ever syncing an armed, never-enqueued PR — an in-flight session holds a pasted fence that is not re-read from disk, so this pairing is not purely theoretical, and the recovery is the merge-queue-dequeue.md "Armed and green but never enqueued" section; (4) unresolved `gh pr merge` spellings (flag before the number, URL operand) stay state L in the hook and still sync. This is a Phase 2 deliverable of THIS plan, not a follow-up (Phase 6 below).

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
- Planned files: 17 | Estimated changed lines: ~650 (about 70% tests)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The root count exceeds the threshold, but ask 1 states "as one change"; the two issues share the exception phrase and the ADR-270 addendum, and splitting the rule edit away would leave the repo stating the exception in prose while the executable still pushes. The only independent slice (Phase 5, the rule edit) is ~1 line plus two manifest rows and is cheapest reviewed alongside the pin tests that lock the phrase.

## User-Brand Impact

- **If this lands broken, the user experiences:** an agent session whose armed PR is wrongly refused a sync (or wrongly skipped by the hook) sits BEHIND until the Phase 7 poll's expiry fallback syncs it, a bounded delay of up to roughly 6 poll ticks; or, in the other direction, a stray resync push restarts the PR's CI (the status quo this change removes). No user data, auth or billing path is touched.
- **If this leaks, the user's data is exposed via:** no exposure vector — the change adds no credential, network egress or data read beyond existing `gh pr view` / rules reads.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** developer-workflow tooling with a bounded, self-healing failure (expiry fallback, `MAX_POLL_MIN`); no customer-facing surface, so the next tier does not apply.

threshold: none, reason: the touched paths (`plugins/soleur/scripts`, `.claude/hooks`, `AGENTS.rules.md`) are internal agent-workflow machinery, outside the sensitive-path regex and with no customer data or credential access.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Spawned as the technical-ruling delegate (hr-technical-fork-is-not-an-operator-question) for four forks: guard shape for `--step` (opt-in `--fence`, refuse by default), refusal exit code (11, fail-closed 4 on unreadable), hook scope (armed + `--queue-wait` verdict, fall-through on unreadable, unarmed still syncs, `--admin` consequence disclosed), and rule placement (stay in `AGENTS.rules.md`, state-based wording, hash + ack). Product, marketing, legal, finance, sales, support, operations: no cross-domain implications (internal tooling; no user-facing surface, no regulated data).

## Implementation Phases

Order is test-first: Phase 0 writes RED tests; Phases 1-5 turn them GREEN; Phase 6 records the decision; Phase 7 validates. Edit with the Edit tool on the exact lines named; read each file first.

### Phase 0 — RED tests (before any production edit)

Each new row is added to its existing suite (already registered in its runner). Several suites carry hand-maintained floors that must be bumped in the same edit or the suite fails on its last line: `plugins/soleur/test/sync-pr-behind.test.sh` ends `[[ "$FAIL" -eq 0 && "$PASS" -eq 122 ]]` (exact pass count: set it to the new total), `.claude/hooks/pre-merge-rebase.test.sh` has `EXPECTED_CASES=69` plus a hand-written case list at its tail (add each new `t_q*` function to the list and raise the floor), and `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` has `MIN_VERDICTS=1093` (ratchet up to the new verdict count; never lower it).

0.1 `plugins/soleur/test/sync-pr-behind.test.sh` (helpers `make_pair`, `install_gh_forbidden`, `install_gql`, `run_step`, `qw_run`, `qw_mutant`):
- Rename `run_step` to `run_step_fence` and make it pass `--fence` (so every existing `--step` row keeps asserting the fence path); add `run_step_bare` for the flagless rows. The ~40 existing rows are RED until Phase 1 (unknown arg exits 2) — the intended initial state.
- Re-anchor the existing in-suite `qw_mutant` rows (they require each anchor to occur exactly once in the SUT): the anchors that name `queue_wait_gate` / `[[ "$am" == armed ]] || return 0` move into `queue_wait_eval` in Phase 1; update their anchor strings and the "may land outside queue_wait_gate" message in this phase and keep them green against the current SUT before adding new rows.
- New rows, each also asserting HEAD unchanged and zero pushes via the recording git shim wherever the case is "refused":
  - **F1** `run_step_bare`, state BEHIND, armed, `merge_queue` rule present → rc 11, `kind=queue_wait rc=11`, nothing fetched/merged/pushed.
  - **F2** bare, BEHIND, armed, NO rule → syncs, rc 0. **F3** bare, BEHIND, NOT armed → syncs, rc 0. **F4** bare, DIRTY (armed, rule present) → syncs (DIRTY exclusion survives).
  - **F5** bare, rules read fails; bare, `gh pr view` fails; bare, `gh pr view` hangs (timeout) → each `kind=gh` rc 4, nothing moved, no ESC bytes echoed.
  - **F6** `run_step_fence` on the SAME logging-gh fixture as F1 (armed, BEHIND, rule present) → syncs rc 0 and the gh call log contains NO `pr view` and NO rules-endpoint call (guard skipped entirely, including the extra reads); only the queue GraphQL read. Replaces R8's "unguarded" assertion.
  - **F7** `--fence` without `--step` → rc 2 `kind=usage`; `--help` names `--fence`, `--queue-wait` and cross-references `--queue-state`.
  - **F8** bare, PR IN the queue → unchanged `kind=queued rc=11`, no rules read, no `pr view`.
  - **W1** `--queue-wait` from OUTSIDE a worktree: armed+BEHIND+rule → first stdout line `queue_wait`; **W2** unarmed / no rule / DIRTY / not BEHIND → `proceed`; in-queue PR → `queued`; **W3** queue read, `pr view`, or rules read fails or hangs → `kind=gh` rc 4; **W4** a PR with a CURRENT removal event (`not_queued`, armed, BEHIND, rule) → `queue_wait` (the mode answers the BEHIND/armed/rule predicate only; dequeue evidence is `--queue-state`'s job and callers call it first — this row pins that contract) and no seen-queued marker is ever written.
- Mutation rows (extend the `qw_scenario` table; each mutant must differ from the SUT and land inside the predicate or the `--step` branch): (a) delete the guard call in the `--step` branch → F1 red; (b) drop the `DIRTY` exclusion → F4 red; (c) drop the armed check → F3 red; (d) make `--fence` run the guard anyway (extra reads) → F6 red; (e) make an unreadable read return "proceed" → F5 red; (f) evaluate the predicate only on the first standalone attempt (existing R6 second-attempt row) → R6 red.
- Anti-vacuity control: the existing H1 non-recording-git-shim row is reused (assert F1's "no push" check goes red under it).

0.2 `.claude/hooks/pre-merge-rebase.test.sh`. Existing ids T-Q1..T-Q16 are taken (T-Q12 relative path, T-Q13 the pinned unparsed-spelling limitation, T-Q14 stdout noise, T-Q15 plugins dir absent, T-Q16 note on deny exits); new rows are **T-Q17..T-Q22**. Extend the `gh` stub BEFORE adding rows: (i) branch `pr view` on `--json` content — a call without `headRefName` is the `--queue-wait` read and is answered from a per-PR `mss-<N>` file (default `OPEN BEHIND`) with the `--jq` program applied, ahead of the existing `STUB-MISS` guard; (ii) add an `api repos/…/rules/branches/main…` case (key `$1 $2`) answering the merge_queue count from a `rules-merge-queue` file (default `0`, so every existing `not_queued` row — which is armed — keeps its "syncs, no warn" assertion); (iii) log every call to a `calls` file. Rows:
  - **T-Q17** not_queued + OPEN + armed + BEHIND + merge_queue rule → hook skips: no merge commit, no push, `additionalContext` names the merge queue, gives the sanctioned exit (merge-queue-dequeue.md "Armed and green but never enqueued"; the Phase 7 poll's expiry fallback) and carries the static `--admin` sentence. Also assert the `gh pr merge 4242 --squash --admin` form (number BEFORE the flags — flag-first is state L per T-Q13) skips the same way.
  - **T-Q18** same but UNARMED → syncs as before and the calls log shows no `--queue-wait` read; the existing T-Q1 (queued) gets the same calls-log assertion.
  - **T-Q19** armed, rules count 0 → syncs, no warn.
  - **T-Q20** `--queue-wait` unreadable — parametrized over: non-zero rc, no matching stdout line, hung read (bounded) — → syncs AND a named note (`cause=queue_wait_unreadable`) rides every exit path through the existing `_Q_NOTE` plumbing (disjoint-skip, conflict deny, push-fail deny, success); never a block.
  - **T-Q21** `--queue-wait` answers `queued` (race after the hook's own read) → skip with the queued context, no push.
  - **T-Q22** `--queue-wait` answers `proceed` → syncs silently (no note, no warn).
  - Parity: `.claude/hooks/pre-merge-rebase-parity.test.sh` and `-headless.test.sh` re-run unchanged (read first; extend only if they enumerate output shapes).

0.3 `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (covers both the ship block and the merge-pr mirror): update the literal-string assertions (~lines 214-215, ~1075, ~1624; the call-count check `grep -cF 'bash "$SYNC_SNAP" "$PR" --step'` still matches `--step --fence`) to the new call string and probe text; add one fixture where the fence's `qwait_expired` fallback runs the REAL script child under an armed+BEHIND+rule stub and still syncs (P3); one where the snapshot's `--help` lacks `--fence` → the precondition arm prints `its --help has no --fence (an older copy)` and sync is disabled (P7); and one parity row asserting the fence's inline rules read and the script's rules read use the same selector (`select(.type == "merge_queue")`), so the two copies of that read cannot drift apart silently. Ratchet `MIN_VERDICTS`.

0.4 `plugins/soleur/test/pr-merge-poll.test.ts`: change the pin at ~line 113 from `never yours; unguarded by design` to the Phase 4 wording; add an exit-11 pin that the claude surface names `kind=queue_wait` beside `kind=noop`/`kind=queued`. Keep the CANON / marker-ban tests unchanged.

0.5 `plugins/soleur/test/workflow-fidelity.test.ts` (~line 639): add positive expectations that `AGENTS.rules.md` still contains `BEHIND` and `resync main` AND `merge-queue repo` and `queue makes it current`. (The marker-conditioned ban already walks the root AGENTS files in `pr-merge-poll.test.ts`; do not duplicate it.)

0.6 Confirm RED and keep the failing-row list for the PR description: `bash plugins/soleur/test/sync-pr-behind.test.sh`, `bash .claude/hooks/pre-merge-rebase.test.sh`, `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`, `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/workflow-fidelity.test.ts`. Long suites run through the repo's rc-file wrapper pattern (see `ship/SKILL.md` test-battery guidance), never with unbounded output.

### Phase 1 — `plugins/soleur/scripts/sync-pr-behind.sh`

1.1 Refactor `queue_wait_gate` into an evaluator `queue_wait_eval <state_line>` that ALWAYS returns 0 and sets `QW_VERDICT=wait|proceed|unreadable` plus `QW_DETAIL` (including the attempt count `n`, which the failure message needs; the `mktemp` failure becomes `QW_VERDICT=unreadable` with its own detail instead of `exit 4`). Returning distinct non-zero codes is a trap under `set -euo pipefail` (a bare call on the common `proceed` path would kill the script). Keep every current behaviour byte-for-byte for the standalone caller: the 100-rule page, selection by `.type`, `PR_QUEUE_ATTEMPTS`/`TIMEOUT`/`RETRY_SLEEP`, the `tr -c` sanitising of the detail, the `lint-trap-ownership` comment on the `mktemp`. `queue_wait_gate` becomes a wrapper: `wait` → `tag queue_wait 0 …; exit 0`; `unreadable` → `tag gh 4 …; exit 4`.
1.2 Argument parser: add `--fence` (sets `FENCE=1`) and `--queue-wait` (sets `MODE=queue_wait`). `--fence` is valid only with `--step` (else `usage_err`, kept for the script's strictness invariant); `--queue-wait` takes no `--max-attempts`.
1.3 `--step` branch (after `queue_gate`, which leaves `QS_OUT` fresh): when `FENCE != 1`, read `gh pr view "$PR" --json state,mergeStateStatus --jq '"\(.state) \(.mergeStateStatus)"'` inside the same `timeout`/`gtimeout` array and `PR_QUEUE_REPO` handling the other reads use (failure → `tag gh 4 …; exit 4`), then `queue_wait_eval`; `wait` → `tag queue_wait 11 "…"` and `exit 11`; `unreadable` → `tag gh 4 …; exit 4`. The refusal text is self-resolving and does NOT advertise `--fence`: "PR #N is BEHIND with auto-merge armed and main has a merge queue: not syncing — the queue makes it current; do nothing. A PR that stays armed, green and never enqueued: plugins/soleur/skills/ship/references/merge-queue-dequeue.md ('Armed and green but never enqueued'); the Phase 7 poll's expiry fallback is the sanctioned sync." When `FENCE == 1` skip the guard entirely (no extra read).
1.4 `--queue-wait` mode, handled beside `--queue-state` before the worktree check: plain `queue_state_read` (failure → `kind=gh` rc 4); a `queued` verdict prints `queued`; otherwise the same bounded `pr view` + `queue_wait_eval`; prints exactly one stdout line `queue_wait` or `proceed` and exits 0; `unreadable` → `kind=gh` rc 4. Writes nothing (no marker). Contract (documented in `--help`): answers the BEHIND/armed/rule predicate only; callers read `--queue-state` first for dequeue evidence.
1.5 Text: `usage()` gains `--step [--fence]` and `--queue-wait` lines (one clause defining `--fence`: "the Phase 7 / merge-pr poll fences pass this; nobody else"; `--queue-wait` cross-references `--queue-state`: "`--queue-state`: is the PR in the queue; `--queue-wait`: should a sync be skipped"); the exit-code table row 11 gains "flagless `--step` on an armed BEHIND PR of a merge-queue repo (kind=queue_wait)" and a note that `kind=queue_wait` carries rc 0 standalone and rc 11 under `--step`, so no consumer keys on `kind` alone; header comments at ~lines 51-55 and ~325-337 drop "`--step` is NOT guarded".
1.6 `shellcheck -S warning plugins/soleur/scripts/sync-pr-behind.sh`; Phase 0.1 suite GREEN, existing and new mutation rows green against the real SUT.

### Phase 2 — `.claude/hooks/pre-merge-rebase.sh`

2.1 After the queued-skip block (~line 748) and before the disjoint-delta skip: parse fields 2-3 of `_q_first`; when `_q_state == not_queued`, field 2 is `OPEN` and field 3 is `armed`, run `(cd "$WORK_DIR" && PR_QUEUE_ATTEMPTS=1 PR_QUEUE_TIMEOUT=5 ${_to[@]+"${_to[@]}"} bash "$_QS_SH" "$PR_HEAD_NUMBER" --queue-wait 2>/dev/null)` — the existing `_to` (10 s overall) wraps the whole call so a hung read cannot hold the hook (worst case without the wrapper would be three sequential 5 s reads plus kill grace). Verdict table, explicit: first stdout line `queue_wait` or `queued` with rc 0 → skip (`headless_or_stderr info …`, `additionalContext`, `exit 0`; `queued` reuses the queued context); `proceed` with rc 0 → sync silently; anything else (non-zero rc incl. 124, no matching line) → append a `queue_wait_unreadable` sentence to the existing `_Q_NOTE` (reusing its four exit-path plumbing) and fall through to today's sync. The skip context says: no sync needed, the queue makes it current; a PR that stays armed, green and unenqueued → merge-queue-dequeue.md "Armed and green but never enqueued" / the Phase 7 poll's expiry fallback; and one static sentence that `--admin` bypasses the queue and lands the head as pushed (gate it with `plugins/soleur/scripts/admin-merge-ready.sh`) — no new `--admin` parsing.
2.2 Update the header comment (~line 20); keep stdout/JSON hygiene (all git output redirected).
2.3 `shellcheck -S warning .claude/hooks/pre-merge-rebase.sh`; Phase 0.2 suites GREEN.

### Phase 3 — the two fences

3.1 `plugins/soleur/skills/ship/SKILL.md`: probe `grep -q -- '--step'` → `grep -q -- '--fence'` with message `its --help has no --fence (an older copy)` (~line 2278) and the stale comment at ~2267; call `bash "$SYNC_SNAP" "$PR" --step || sync_rc=$?` → `bash "$SYNC_SNAP" "$PR" --step --fence || sync_rc=$?` (~line 2457). In the "Auto-sync on BEHIND" paragraph (~line 2514) extend the exit-11 description to `kind=noop`, `kind=queued` or `kind=queue_wait` (a flagless `--step`; the fence passes `--fence`, so it never sees this) — a few bytes, no new prose block.
3.2 `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 mirror fence: the same probe and call edits (~lines 408 and 552).
3.3 Update the fixture assertions (Phase 0.3); run `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`; confirm `ship` stays <= 273955 B.

### Phase 4 — text surfaces that state the old behaviour (one line each; the ADR addendum is the record)

4.1 `plugins/soleur/lib/pr-merge-poll.ts`: replace "(the Phase 7 fence's call, never yours; unguarded by design)" (~line 82) with a wording that keeps "never yours" and says the script refuses a flagless `--step` on an armed BEHIND PR of a merge-queue repo (`kind=queue_wait`, exit 11); extend the exit-11 line (~line 75) with `kind=queue_wait`. Matches the Phase 0.4 pins; CANON phrase and other surfaces untouched.
4.2 `plugins/soleur/skills/ship/references/queue-mode.md`: rewrite ONLY boundary (1) of "Standalone guard" (the `--step` unguarded bullet) to a one-line pointer to the ADR-270 2026-10-20 addendum; no new Hook section.
4.3 `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/harness.test.ts plugins/soleur/test/antigravity-harness.test.ts` GREEN.

### Phase 5 — the rule edit (#9868), under the AGENTS gates

5.1 In `AGENTS.rules.md` line 65 change only the tail `BEHIND→resync main` to `BEHIND→resync main, unless armed on a merge-queue repo (the queue makes it current; only the Phase 7 poll's expiry fallback syncs it)`. Do all wording edits FIRST — the hash and the ack below bind to the final text. Keep the id, the `[skill-enforced: workflow-fidelity.ts]` tag and the one-line `**Why:** #6325.` Do NOT mention `[ship.phase7.queue_wait]` (marker-conditioned class is test-banned). Measure: the line grows from 234 B to ~355 B (cap ~600 B per rule, cq-agents-md-why-single-line); payload 39160 B to ~39280 B (warn 44000).
5.2 `python3 scripts/lint-rule-bodies.py --write` regenerates `.claude/rule-body-hashes.txt` (only the one row changes).
5.3 Append one line to `.claude/rule-weakening-acks.txt` (append-only, WORM; never edit an existing line): `hr-pipeline-skills-never-inline-after-go-route|<new sha256 from the manifest>|2026-10-20|10655|adds the merge-queue armed-BEHIND exception (clarification: matches queue-mode.md and the sync script refusal; the default resync is unchanged elsewhere)`. Automated step by the implementing agent. `.claude/rule-weakening-acks.txt` is CODEOWNERS-owned (`@deruelle`); the CODEOWNERS header says branch-protection enforcement of code-owner review is a separate operator follow-up, so no operator step is added — the `rule-body-lint` job verifies the hash-bound ack mechanically.
5.4 `cq-rule-ids-are-immutable`: the id string is unchanged; `python3 scripts/lint-rule-ids.py` passes. `cq-agents-md-tier-gate`: record in the PR body why this stays in AGENTS (cross-cutting session invariant; the issue's premise is compaction survival) rather than migrating to the enforcer (CTO Fork 4).
5.5 `python3 scripts/lint-agents-rule-budget.py`, `python3 scripts/lint-agents-enforcement-tags.py`, `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` and `bun test plugins/soleur/test/workflow-fidelity.test.ts` GREEN.

### Phase 6 — ADR addendum

Author the ADR-270 addendum named in "Architecture Decision (ADR/C4)" via the `soleur:architecture` skill workflow (state the residuals once, here); `bash scripts/check-adr-ordinals.sh` (no new ordinal) and `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 7 — validation

Run all suites above to GREEN (long suites through the rc-file wrapper), then `bash scripts/test-all.sh --affected` once under the lock. Confirm AC-X1.

## Files to Edit

- `plugins/soleur/scripts/sync-pr-behind.sh`
- `.claude/hooks/pre-merge-rebase.sh`
- `plugins/soleur/skills/ship/SKILL.md` (fence probe + call site only)
- `plugins/soleur/skills/merge-pr/SKILL.md` (mirror fence probe + call site only)
- `plugins/soleur/skills/ship/references/queue-mode.md`
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

**Property.** No `sync-pr-behind.sh <PR> --step` invocation made without the fence-only opt-in flag fetches, merges or pushes when GitHub reports the PR BEHIND (not DIRTY), auto-merge is armed and `main` has a `merge_queue` rule.

**Assembly.** The chokepoint is the `--step` branch of `sync-pr-behind.sh` (`if [[ "$MODE" == step ]]`) between `queue_gate` and `sync_step`; the predicate is the single `queue_wait_eval` function shared with the standalone loop's `queue_wait_gate` and the `--queue-wait` mode. Push writers on this path: `sync_step` (reached by `--step` AND by the standalone loop) and the standalone loop's DIRTY arm (`resolve-regenerable-conflicts.sh` commits locally, reached only after `queue_wait_gate`); the hook's own push is Guard 2. The only sanctioned `--fence` callers are the two fences, each with exactly ONE `--step` call site (asserted by the fixture's call-count check); a third copy of the fence would be a new member and fails that assertion.

**Mutation matrix.**

| # | Mutation (edit that MUST drive the suite RED) | Row that goes red |
|---|---|---|
| 1 | Delete the guard call in the `--step` branch (also covers the dispatch: a guard that is never reached) | F1 (flagless armed BEHIND rule: moved/pushed) |
| 2 | Drop the `DIRTY` exclusion from the predicate | F4 (DIRTY armed must still sync) |
| 3 | Drop the `armed` check from the predicate | F3 (unarmed must still sync) |
| 4 | Treat an unreadable rules / `pr view` read as "proceed" | F5 (must be `kind=gh` rc 4) |
| 5 | Make `--fence` run the guard anyway (extra `gh pr view`) | F6 (the call log must hold no `pr view` / rules call) |
| 6 | Evaluate the predicate only on the first standalone attempt (second member after a compliant first sync) | R6 (second attempt must still answer `kind=queue_wait`) |
| 7 | Accept `--fence` without `--step` | F7 (`--fence` alone must exit 2) |

**Harness rows.** (a) A SUITE edit that must go RED: swap the recording git shim for a non-recording one (the existing H1 control) and require F1's "no push" check to fail, so "refused" cannot pass vacuously. (b) Must-PASS inputs that are not the canonical refused case and differ in a way the contract permits: F2 (no rule), F3 (unarmed), F4 (DIRTY), F8 (in the queue) — a guard that refuses everything fails them.

**Anchor.** The suite's expected values are literals in the test file, in the same diff as the script, so one diff could weaken both. The outside anchors are the fence fixture (it drives the REAL script as a child with `--fence` and asserts P3 independently, plus the exactly-one-call-site count), the pre-existing `qw_mutant` anchors re-pointed in Phase 0.1, and the merge-base `lint-skill-body-budget` / `rule-body-lint` CI jobs.

### Guard 2 — pre-merge hook skip

**Property.** For every `gh pr merge` form the hook's parser resolves to one PR, the hook performs no `git merge origin/main` and no `git push` when that PR is OPEN, GitHub-BEHIND, armed, and `main` has a `merge_queue` rule (or the PR is already in the queue).

**Assembly.** The chokepoint is the hook's single sync section (`git merge origin/main` at ~line 804, `git push origin HEAD` at ~line 858), reached only through the flow after the queued-skip block; every resolvable `gh pr merge` argument form flows through it (the T-Q8 family: number after flags, `-R`, `#N`, chained `cd`), including `--admin` written after the number. The skip is placed before the disjoint-delta skip and the `rebase-main` lock so no later path can reach the push. Unresolved spellings (T-Q13) are out of the property by construction and pinned as such.

**Mutation matrix.**

| # | Mutation (edit that MUST drive the suite RED) | Row that goes red |
|---|---|---|
| 1 | Remove the new skip block | T-Q17 (merge/push happened) |
| 2 | Read `armed` from the wrong field so an unarmed PR is skipped | T-Q18 (unarmed must still sync) |
| 3 | Treat a non-zero `--queue-wait` exit or no matching line as `queue_wait` | T-Q20 (unreadable must fall through with the note) |
| 4 | Fall through on a `queued` answer instead of skipping | T-Q21 |
| 5 | Make the skip apply to the bare-number form only (not `-R` / admin-after-number forms) | T-Q17 admin-form assertion and the T-Q8-style `-R` assertion (second member: same PR, a different resolvable spelling, after a compliant first) |
| 6 | Remove the `_to` wrapper / `PR_QUEUE_*` bound | T-Q20 hung-read case (must return inside the bound) |
| 7 | Call `--queue-wait` on every merge instead of only armed not_queued | T-Q18 and T-Q1 calls-log assertions |

**Harness rows.** (a) A SUITE edit that must go RED: make the stub answer rules count 1 for every PR and require the must-PASS rows T-Q18 / T-Q19 to fail. (b) Must-PASS inputs: T-Q18 (unarmed), T-Q19 (no rule), T-Q22 (`proceed`) and the existing T-Q2 (not queued, armed, default rules 0) still sync, proving the skip does not fire on everything.

**Anchor.** The hook calls the script's `--queue-wait` rather than re-implementing the predicate, so the hook suite proves wiring and the script suite (W1-W4) proves the predicate; neither can pass by editing only the other. The parity suite `pre-merge-rebase-parity.test.sh` is the outside check that the hook's output shapes did not drift.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC-S1** `bash plugins/soleur/test/sync-pr-behind.test.sh` exits 0 with the new F/W rows and mutation rows present (grep the suite output for `F1`..`F8`, `W1`..`W4`) and the exact-pass-count pin on its last line equals the new total (greater than 122).
- [ ] **AC-S2** Flagless `--step` on an armed BEHIND PR of a merge-queue repo prints `[pr-behind-sync] kind=queue_wait rc=11` and exits 11 with HEAD unchanged; `--step --fence` on the same fixture syncs and makes no `gh` call beyond the queue read.
- [ ] **AC-S3** `bash plugins/soleur/scripts/sync-pr-behind.sh --help` contains `--fence`, `--queue-wait` and the exit-11 queue_wait row; `--fence` without `--step` exits 2.
- [ ] **AC-H1** `bash .claude/hooks/pre-merge-rebase.test.sh`, `-parity.test.sh` and `-headless.test.sh` exit 0; T-Q17..T-Q22 present and listed in the case list with `EXPECTED_CASES` raised; an unarmed, no-rule, `proceed` or unreadable case still syncs (never blocks).
- [ ] **AC-F1** `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` exits 0 with `MIN_VERDICTS` ratcheted up; both fences contain exactly one `--step --fence` call and probe `--fence`; an old-snapshot fixture disables auto-sync with the `--fence` precondition message.
- [ ] **AC-F2** `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` exits 0 and `wc -c plugins/soleur/skills/ship/SKILL.md` is <= 273955.
- [ ] **AC-T1** `bun test plugins/soleur/test/pr-merge-poll.test.ts plugins/soleur/test/workflow-fidelity.test.ts plugins/soleur/test/harness.test.ts` exits 0; the old `unguarded by design` string is gone from `plugins/soleur/lib/pr-merge-poll.ts` (`grep -c 'unguarded by design' plugins/soleur/lib/pr-merge-poll.ts` prints 0).
- [ ] **AC-R1** `AGENTS.rules.md` line for `hr-pipeline-skills-never-inline-after-go-route` contains `BEHIND→resync main (not when armed on a merge-queue repo: the queue makes it current)`, keeps its `[id: ...]` and `[skill-enforced: workflow-fidelity.ts]` tags, names the Phase 7 poll's expiry fallback as the only sanctioned sync, and is <= 600 B (`awk` on that line).
- [ ] **AC-R2** `python3 scripts/lint-rule-ids.py` and `python3 scripts/lint-agents-rule-budget.py` and `python3 scripts/lint-agents-enforcement-tags.py` exit 0; `wc -c AGENTS.rules.md` < 44000.
- [ ] **AC-R3** `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` exits 0 (manifest regenerated and exactly one new ack line appended; `git diff origin/main -- .claude/rule-weakening-acks.txt` shows additions only).
- [ ] **AC-R4** `git diff origin/main -- scripts/retired-rule-ids.txt` is empty and the rule id string is byte-identical (rule ids immutable).
- [ ] **AC-A1** The ADR-270 addendum exists (`grep -n 'Addendum 2026-10-20' knowledge-base/engineering/architecture/decisions/ADR-270-*.md`), and `bash scripts/check-adr-ordinals.sh` and `bash plugins/soleur/test/c4-count-parity.test.sh` exit 0.
- [ ] **AC-X1** No file outside the Files-to-Edit/Create lists is modified, plus this plan and its spec directory (`git diff --name-only origin/main...HEAD` is a subset of those); comment-only edits inside listed files (e.g. the fence comment at `ship/SKILL.md` ~2267) are in scope.
- [ ] **AC-X2** The PR #10655 body uses `Ref #9869` and `Ref #9868` and contains none of `closes`/`fixes`/`resolves` adjacent to those numbers (the ship step owns the body); the PR title is not `WIP:`.

### Post-merge

None. #9869's re-evaluation criterion (a `kind=pushed` line on an armed, not-yet-enqueued PR) is an observational recurrence trigger that depends on unrelated sessions, so it is deliberately not an acceptance criterion (plan-review standing check `cq-ac-must-not-depend-on-concurrent-sessions`); the deterministic fixtures F1/T-Q12 carry the property, and a recurrence reopens the issue.

## Test Scenarios

(see Phase 0.1-0.5 for the row-level lists; summary of intent)

1. Flagless `--step` on armed+BEHIND+queue repo: refused with exit 11 and no git side effects (F1); fence call with `--fence` still syncs (F6) — an expiry fallback and a DIRTY-derived BEHIND each get a fixture through the real script child (P3).
2. Predicate edges: unarmed (F3), no rule (F2), DIRTY (F4), in-queue (F8), unreadable (F5), `--fence` misuse (F7).
3. `--queue-wait` read-only verdicts and failure modes without a worktree (W1-W4).
4. Hook: skip on armed+BEHIND+rule (incl. admin-after-number form), `queued` race skip, silent sync on `proceed`, fall-through with a named note on unreadable/hung read, no extra call on queued/unarmed paths (T-Q17..T-Q22).
5. Fences: probe tightening against an old snapshot (P7) and an old fence against a new script degrades to exit 11 "polling on" (documented; bounded by `MAX_POLL_MIN`).
6. Rule text: exception present, tags intact, marker-ban class not matched, hash + ack consistent.

## Observability

```yaml
liveness_signal:
  what: "[pr-behind-sync] kind=queue_wait rc=11 (flagless --step) and kind=queue_wait rc=0 (standalone) tagged stdout lines; hook additionalContext 'is BEHIND with auto-merge armed' — local developer-machine tooling, no daemon"
  cadence: "per invocation (per Phase 7 tick that reaches the sync arm; per gh pr merge for the hook)"
  alert_target: "the invoking agent session (Monitor streams stdout) — the refusal line names the next action"
  configured_in: "plugins/soleur/scripts/sync-pr-behind.sh (tag/usage) and .claude/hooks/pre-merge-rebase.sh (additionalContext)"

error_reporting:
  destination: "stdout tagged lines (Monitor streams stdout only); the hook's stderr is routed by headless_or_stderr to the session-state log when headless; no Sentry (CLI tooling on the developer host, not a server surface)"
  fail_loud: "unreadable reads print kind=gh rc=4 (script) or a named queue_wait_unreadable note in additionalContext (hook) — never silent"

failure_modes:
  - mode: "false refusal: a legitimate fence sync is refused (old fence + new script, or flag omitted)"
    detection: "fence prints [ship.phase7.sync_noop] repeatedly; Phase 7 poll runs to MAX_POLL_MIN; ship fixture asserts both fences pass --fence and probe for it"
    alert_route: "agent session output; the AC-F1 fixture fails pre-merge"
  - mode: "false skip: the hook skips a sync for a PR that is not actually waiting on the queue (stale armed read)"
    detection: "additionalContext names the skip; merge then fails with GitHub's not-up-to-date refusal; recipe in the context points at gh pr update-branch / admin-merge-ready.sh"
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
- An OLD fence paired with the NEW script: the fence's expiry fallback runs flagless `--step`, gets exit 11 and keeps polling (bounded by `MAX_POLL_MIN`); an OLD script with a NEW fence is stopped by the tightened `--fence` probe. In-flight sessions hold a pasted fence that is not re-read from disk, so the old-fence pairing is not purely theoretical (ADR addendum residual 3).
- The hook skip also applies to `--admin` (consistent with the queued skip). `--admin` bypasses the queue, so "the queue makes it current" does not hold there — the context says so and points at `admin-merge-ready.sh`. If harm is observed, flip to "keep syncing for `--admin`" (CTO Fork 3 risk note).
- The existing hook tests' `not_queued` stub is ARMED; the new hook call would STUB-MISS in every such row unless the stub answers the `--queue-wait` reads (a `pr view --json state,mergeStateStatus` branch ahead of the existing `--json headRefName,…` STUB-MISS guard, with the `--jq` program applied, and an `api repos/…/rules/branches/main` case) with defaults (rules count 0). Phase 0.2 extends the stub first; do not weaken the "no warn" assertions to compensate.
- The script runs under `set -euo pipefail`: `queue_wait_eval` must always return 0 and report through `QW_VERDICT` (a distinct non-zero return would kill the script on the common `proceed` path), and every new `gh pr view` read goes through the same `timeout`/`gtimeout` array as the other reads (a hung read inside a PreToolUse hook that then takes the 60 s `rebase-main` lock is the worst case).
- Floors are hand-maintained: `sync-pr-behind.test.sh` pass-count pin (122), `pre-merge-rebase.test.sh` `EXPECTED_CASES=69` and case list, `ship-phase-7-poll-fixtures.test.sh` `MIN_VERDICTS=1093`. Forgetting one fails the suite on its last line, not on the new row.
- Existing hook test ids T-Q1..T-Q16 are taken; new rows start at T-Q17, and `gh pr merge --squash --admin 4242` (flag before the number) is state L (T-Q13) and never reaches the queue read — use `gh pr merge 4242 --squash --admin`.
- `run_step_fence` (the renamed `run_step`) carries `--fence` in the script suite so the ~40 existing `--step` rows keep asserting the fence path; only the F-rows run flagless. Do not delete a row to make Phase 1 pass.
- `rule-weakening-acks.txt` is append-only and hash-bound: run `--write`, then copy the NEW hash from `.claude/rule-body-hashes.txt` into the ack; an ack written before the final wording edit is a stale hash and reds `rule-body-lint`.
- Sanitise: the refusal text includes the PR number only (digits-validated) — no stderr text from `gh` is echoed raw (the existing `tr -c` pass stays on `QW_DETAIL`).
- Do not paste the `[ship.phase7.queue_wait]` marker into the AGENTS rule: `pr-merge-poll.test.ts` bans marker-conditioned exception wording across the root AGENTS files.
