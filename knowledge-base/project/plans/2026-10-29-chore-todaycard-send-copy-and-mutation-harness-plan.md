---
title: "chore: today-card send-error copy, live messages UPDATE-policy check, shared mutation harness"
type: chore
date: 2026-10-29
slug: chore-todaycard-send-copy-and-mutation-harness
branch: feat-one-shot-11486-11520-todaycard-copy-mutation-harness
issue: 11486
closes: [11486, 11520]
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
requires_cpo_signoff: false
---

# chore: today-card send-error copy, live messages UPDATE-policy check, shared mutation harness

## Overview

One PR resolves two deferred scope-out issues, with the PR body carrying `Closes #11486` and
`Closes #11520` on separate lines.

- **#11486** (carried from the closed #11212): a read-only check of the live UPDATE policies on
  `public.messages`, plus four copy fixes on the dashboard today-card (Edit-409, the
  `approval_expired` split, `not_a_draft`, and the 503 retry line). The split needs an additive
  `reason` field on the send route's 409 body.
- **#11520** (deferred from the PR 11483 review): extract the duplicated mutation harness from the two
  follow-through probe suites into one sourced library, and give both suites a negative control for
  the scorer that decides whether a mutant was caught "for the right reason". Items 3 to 6 of #11520
  are descoped into one deferral issue (ruled below).

Nothing here changes production behaviour except the one additive 409 field and the user-visible
strings. The live database read is read-only and runs in the work phase.

## Research Insights

### Premise Validation (Phase 0.6)

- #11486 and #11520 are both `OPEN`; #11212 (the origin of #11486) is `CLOSED`. Draft PR 11566 is the
  only open change naming either issue. The collision pre-check also listed foreign `test-all.sh`
  processes in other worktrees; none touch these files.
- Cited paths all exist on `origin/main`: the hook, the component, the send, edit and discard routes,
  both probe suites, `betterstack-alert-structure.test.sh`, `scripts/lib/test-affected-paths.sh`.
- Stale premise found: #11520 item 5 says the send route must tag the Sentry environment first.
  `apps/web-platform/sentry.server.config.ts` already sets `environment: process.env.NODE_ENV`, so the
  route needs no change; the real open question is whether preview builds also report `production`.
  Item 5 is therefore a probe-side question that needs a live Sentry read, and it is descoped.
- Stale premise found: the issue names `scripts/followthroughs/lib/mutation-harness.sh`. The repo's
  sourced-lib convention is `scripts/lib/*.sh` (65 tracked files). A lib under `scripts/followthroughs/`
  would fall under the follow-through exec-bit gate and the argv-bearer sweep, neither of which covers
  a sourced lib. Ruled below.
- ADR corpus: the mechanisms (an additive response field, a sourced test lib) sit in no ADR's rejected
  alternatives. The live-catalog read has ADR-111 precedent (`rls-parity-check.ts`).

### Property List and Cut List (Phase 0.6b)

Properties:

1. A founder who hits any of the four send/edit refusals learns what happened and what to do next, in
   plain language, without a status code.
2. An expired approval and a clock-skew refusal are distinguishable on the wire without breaking an
   older client.
3. The live `public.messages` UPDATE policy state is known, not inferred from migrations.
4. The two probe suites share one harness, so a fix to the credit path lands once.
5. A mutant is credited as caught only when it reds for the claimed reason, and a dead scorer turns
   both suites red.

Cut List (mechanism, property, what already covers it):

- A new `.pen` wireframe: buys no property (no structural change); the action-feedback `.pen` files
  already depict the card and the typed-confirm modal.
- An `entryPoint` parameter on `useActionSend` to name "Send" vs "Confirm send": buys property 1,
  but a surface-neutral 503 string buys it with no API change (CTO R4).
- Extracting `betterstack-alert-structure.test.sh` into the lib: buys property 4 for a suite with a
  different scorer protocol and its own M-scorer control already (CTO R7).
- A migration adding an owner UPDATE policy: buys nothing until the live read says it is missing, and
  is a production-mutating change that needs its own plan and the operator's priority call.
- Editing Discard/Edit 403 copy: copy cannot fix an RLS gap and would hide it (CTO R1, CPO (e)).

### Institutional learnings applied

- `2026-10-26-an-approved-action-needs-a-durable-row-...zero-row-update-is-not-an-error.md`: a zero-row
  RLS-hidden UPDATE returns no error; the live `pg_policies` read is the only authority.
- `2026-10-05-registering-a-suite-is-itself-a-runner-edit.md`: adding anything beyond a closed
  single-line array entry to `test-all.sh` or `test-affected-paths.sh` degrades `--affected` to the full
  battery. No suite is added here, so `test-all.sh` is untouched; the two array edits are single lines.
- `2026-10-14-my-stubs-checked-the-shape-of-argv-...`: attribute each mutant to the check it should
  fail; the scorer control is exactly that attribution.
- `2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md`:
  fixture shape is a coverage axis; the scorer controls need a log with only a `PASS:` line and one with
  a `FAIL:` line for a different row, not just an absent log.
- `2026-07-18-...dev-prod-policy-divergence.md`: never take policy names from prod for a dev migration.

### Research Reconciliation: spec vs codebase

| Claim | Reality | Plan response |
|---|---|---|
| #11520: "about 89 identical lines" | Verified: ~80 code lines plus a 13-line header comment, plus the five `ok/bad/check/has/hasnt` one-liners | Move only what keeps `mutate_helper` landing (see Phase 3) |
| #11520: lib at `scripts/followthroughs/lib/` | Convention is `scripts/lib/`; followthroughs path triggers exec-bit and argv-bearer gates | `scripts/lib/mutation-harness.sh`, mode 100644 |
| #11520 item 5: send route must tag environment first | SDK already tags `environment` from `NODE_ENV` | Descoped; needs a live Sentry read |
| #11486: "send route reports zero-row archive as `messages-archive-no-row`, 0 events in 14 days" | The op fires only after a send succeeds; zero events can mean zero sends | The live `pg_policies` read is mandatory, not optional |
| #11486 item 3: the two cases "share one string" | `refuseStaleReplay(actionSendId, reason: "expired" \| "future_clicked_at")` already carries the discriminator into the Sentry `extra` | Put the same two values on the wire |

### Technical rulings

Recorded in `knowledge-base/project/specs/feat-one-shot-11486-11520-todaycard-copy-mutation-harness/decision-challenges.md`
(rows D1 to D10). Summary: the agent may run the read-only live check; the wireframe gate has a recorded
exemption backed by a diff invariant; `reason` reuses the code-arm values; the lib lives in `scripts/lib/`
and keeps the five helpers in each suite; scorer controls are four rows plus one teeth row, floors rise by
exactly 5 per suite; #11520 items 3 to 6 go to one deferral issue.

## Open Code-Review Overlap

Two open `code-review` issues name files this plan edits:

- #8800 (census sandbox shares inodes with the live repo) names `scripts/lib/test-affected-paths.sh`.
  **Acknowledge:** a different concern (a fixture write-through hazard); this PR adds two single-line
  entries to existing arrays. The issue stays open.
- #7942 (two `*.mutation.sh` batteries run in no gate) names `scripts/test-all.sh`. **Acknowledge:** this
  PR does not edit `test-all.sh` (no suite is added or removed). The issue stays open.

## Proposed Solution

### A. #11486

1. **Live check (read-only).** In the work phase, run the runbook pattern from
   `knowledge-base/engineering/operations/runbooks/egress-audit-dsar.md` against prd, in one read-only
   transaction, DSN expanded inside bash and never printed:

   ```bash
   doppler run -p soleur -c prd -- bash -c 'psql "$DATABASE_URL_POOLER" -X -v ON_ERROR_STOP=1 -f -' <<'SQL'
   BEGIN READ ONLY;
   SELECT policyname, cmd, permissive, roles, qual, with_check
     FROM pg_policies WHERE schemaname = 'public' AND tablename = 'messages' ORDER BY policyname;
   SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE oid = 'public.messages'::regclass;
   ROLLBACK;
   SQL
   ```

   The result is posted as a comment on #11486 (policy names, cmd, roles, date; no DSN). Verdict rule:
   an owner UPDATE policy exists only if a PERMISSIVE policy with cmd `UPDATE` or `ALL` for
   `authenticated` (or `public`) carries an owner predicate; the RESTRICTIVE jti policy from migration 068
   grants nothing. If the harness approval prompt or Doppler blocks the read, record the result as
   *unverified*, put the exact SQL in the PR body, and use `Ref #11486` instead of `Closes #11486`.
   If no owner UPDATE policy exists: file one P1 issue (`priority/p1-high`, `type/bug`,
   `domain/engineering`) naming the symptom (Discard and Edit return 403, `messages-archive-no-row`
   cannot fire), record it in the PR body, write a learning, and **do not add or apply a migration in
   this PR** and do not touch the Discard/Edit 403 copy.

2. **Copy** (final strings; CPO proposals, one planner correction recorded as D9):

   | State | Where | Final string |
   |---|---|---|
   | Edit 409 `draft_already_approved` | `today-card.tsx` edit branch only | "You already approved this draft, so it can't be edited. Send it or Discard it." Any other status keeps `Edit failed (NNN)` |
   | `approval_expired`, `reason: "expired"` | hook `failureCopy` | "This approval expired, so this attempt didn't go through. Refresh to update this card." |
   | `approval_expired`, `reason: "future_clicked_at"` | hook `failureCopy` | "We couldn't confirm when you approved this, so this attempt didn't go through. Try again in a minute." |
   | `approval_expired`, absent or unknown `reason` | hook `failureCopy` | unchanged: "This approval can no longer run. Refresh to update this card." |
   | `not_a_draft` | hook `failureCopy` | "This draft was already handled, maybe in another tab. Refresh to update this card." |
   | 503 `enqueue_unavailable` | hook `failureCopy` | "Your approval is saved, but we couldn't send it yet. Try again in a moment." |

   The hook stays card-neutral (the CTO S1 comment): no string in the hook names Edit or Discard.
   The Edit string lives in the component because Edit exists only on today-card.

3. **`reason` field.** In `send/route.ts`, `refuseStaleReplay` adds `reason` to the body:
   `{ error: "approval_expired", message_id, reason }`, reusing the parameter's two values. Export the
   closed union type `StaleReplayReason = "expired" | "future_clicked_at"` from
   `server/action-sends/decide-replay.ts` (a route file may export only HTTP handlers); the hook imports
   it with `import type`, exactly as it imports `DenyReason`. The client trusts only those two exact
   strings; anything else falls back to the unchanged copy (deploy skew in either direction).

4. **Wireframe exemption (D2).** `components/dashboard/today-card.tsx` matches the UI-surface glob, so the
   gate is satisfied by an exemption plus a mechanical invariant, not by prose and not by a new `.pen`.
   Design baseline (structure unchanged, cited not created):
   `knowledge-base/product/design/dashboard/action-feedback-variant-a-forge-restraint.pen`,
   `.../action-feedback-variant-b-instrumented-spec.pen`, `.../action-feedback-variant-c-ember-glow.pen`.
   Exemption: the "Pure copy or style tweaks with no structural/layout change" entry of the Excluded list
   in `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`. Invariant (AC4): this command
   prints nothing:
   `git diff -U0 origin/main -- apps/web-platform/components apps/web-platform/hooks | grep -E '^[+-][[:space:]]*(<[A-Za-z]|.*(className|role=|aria-|data-))'`.
   The exemption lapses, and the work stops to design, on any added element, button, retry affordance,
   modal or toast, any layout or class change, or any new file under `components/`.

### B. #11520

5. **Library** `scripts/lib/mutation-harness.sh` (mode 100644, `# shellcheck shell=bash`, sourced, no
   side effects at source time). Provides, as functions: `instrument_selftest`, `run_battery`,
   `mutate_run`, `mutate_sub`, `mutate_helper`, the pure scorer `mh_caught <frag> <outfile>` (returns 0
   only when the log holds a line containing `FAIL: <frag>`; prints nothing; the single place that match
   lives), and `mh_floor <MIN_FIXTURE> <MIN_BATTERY> <suite-arg>` (the floor tail: same messages, same
   `exit 1`; the third parameter is the suite's own `${1:-}` because inside a function `$1` is
   `MIN_FIXTURE`, and `run_battery` needs the `--no-battery` argument). `mutate_run` calls `mh_caught`
   in place of the inline `elif grep -qF`. The lib header names the caller contract: `SELF`, `SUT`,
   `MUT`, `REPO`, `LEDGER`, `PASS`, `FAIL`, `FIX_N`, `FT_INNER`, and the five helpers
   `ok bad check has hasnt` (13 caller-defined names, accepted because the helpers must stay in each
   suite for `mutate_helper`).
   **Stays in each suite:** the five one-liners (so `mutate_helper`'s awk still finds `check()` etc. in
   `$SELF` and the h1 to h5 rows still land), the `LEDGER/PASS/FAIL` globals, the `ROOT`/trap setup, the
   h1 to h5 and m-rows, the `MIN_*` constants, the `LEDGER MISMATCH` check and the summary banner (it
   carries the suite name).
   **Locating the lib:** `source "$REPO/scripts/lib/mutation-harness.sh"` where `REPO="${FT_REPO:-...}"` is
   already exported before any mutant runs. Never a `BASH_SOURCE`-relative path: a mutant copy lives in a
   scratch directory. A failed source prints `mutation-harness lib missing` and exits 4 (the suites treat
   any rc other than 0 or 1 from an inner run as an instrument break; 78 means an xtrace refusal in the
   probes and must not be reused).
   The exported type `StaleReplayReason` (`expired`, `future_clicked_at`) keeps the wire/Sentry
   vocabulary of `refuseStaleReplay`; it differs on purpose from `ReplayDecision`'s kind `clock_skew`,
   which is a decision name, not a wire value.

6. **Scorer controls** in each of the two suites (inside the battery, after the pristine control). All
   five rows are capture-only: each calls `mh_caught` directly in the PARENT shell and emits exactly one
   `check` row (an `ok`/`bad` call inside a subshell would lose the `PASS`/`FAIL` increments and trip
   `LEDGER MISMATCH`). Four controls on synthetic logs written under `$MUT`: a log holding
   `FAIL: frag` mid-line (with surrounding text) is caught; a log with only `PASS: frag` is not; a log
   with a `FAIL:` line for a different row is not; an empty log is not. One teeth row: in a subshell,
   override the function (`mh_caught() { return 0; }`; no lib copy, so no double-source ambiguity), run
   the three "not caught" controls, print how many came back wrongly caught, and assert in the parent
   with one `check` that the count is at least 1 (a dead scorer is visible to the controls). Raise
   `MIN_BATTERY` by exactly 5 in each suite and leave `MIN_FIXTURE` alone; derive the 5 from the
   before/after ledger-label diff of a full pristine run.

7. **Rollout order:** (i) extract as a pure refactor; diff the ledger labels of a full pristine run
   before and after: identical, `MIN_*` unchanged; (ii) add the five new rows per suite and raise
   `MIN_BATTERY` by 5; (iii) hand-run the mutations in the Guard Contract matrix against the lib and
   confirm BOTH suites red (AC9).

8. **Declarations:** add `"scripts/lib/mutation-harness.sh"` as one line to each of
   `AFFECTED_SCRIPTS_FOLLOWTHROUGHS_DISPATCH_RECOVERY_SWEEPER_11211_PATHS` and
   `AFFECTED_SCRIPTS_FOLLOWTHROUGHS_INNGEST_LUKS_KEEPER_DARK_11265_PATHS` in
   `scripts/lib/test-affected-paths.sh` (source closure may not follow a `"$REPO/..."` path). Do not touch
   `scripts/test-all.sh`.

9. **Deferral issue** (one, label `deferred-scope-out`, milestone from `knowledge-base/product/roadmap.md`):
   "#11520 remainder: items 3 to 7", a checklist with a re-evaluation criterion per item: (3) 60-day
   reader timeout, measure the archive arm first; (4) sibling env-settable reader seams; (5) 11211 Sentry
   `environment:` filter, needs a live Sentry read to learn whether preview reports `production`; (6)
   structure-suite edges, plus the structure suite's harness variant (D7); (7) the three
   `DENY_REASON_COPY` 403 strings in `today-card.tsx` ("Click Send again to re-authorize") carry the same
   button-name mismatch in the typed-confirm path (a residual surfaced by the CPO review, from #11486's
   own item 5). Net issue flow: closes 2, files 1. If the live read finds a missing owner UPDATE policy,
   the P1 defect issue is a second new issue; file it and state the exception in the PR body.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Check the live policy on `public.messages` (read-only `pg_policies`, UPDATE command)." [issue #11486] | Proposed Solution A.1, Phase 1 | mapped |
| 2 | "Edit-409 copy." [issue #11486] | A.2 row 1, Phase 2 | mapped |
| 3 | "`approval_expired` copy split." [issue #11486] | A.2 rows 2 to 4, A.3, Phase 2 | mapped |
| 4 | "`not_a_draft` copy usually means the send already succeeded" [issue #11486] | A.2 row 5, Phase 2 | mapped |
| 5 | "503 copy says \"Click Send again\" while the typed-confirm modal button reads \"Confirm send\"." [issue #11486] | A.2 row 6, Phase 2 | mapped |
| 6 | "Extract one `scripts/followthroughs/lib/mutation-harness.sh`." [issue #11520] | B.5 (path moved to `scripts/lib/`, ruling D5) | mapped |
| 7 | "Scorer negative controls in the two probe suites." [issue #11520] | B.6 | mapped |
| 8 | "60-day scan is one `--max-time 60` read." [issue #11520 item 3] | B.9 | descoped: needs a live Better Stack read and changes a probe's exit-code behaviour (D8) |
| 9 | "Sibling follow-through probes keep env-settable reader seams" [issue #11520 item 4] | B.9 | descoped: each seam needs its own suite update, outside this PR's blast radius (D8) |
| 10 | "11211 Sentry queries have no `environment:` filter." [issue #11520 item 5] | B.9 | descoped: a wrong filter turns the probe into a silent false zero; needs a live Sentry read (D8) |
| 11 | "Remaining structure-suite edges" [issue #11520 item 6] | B.9 | descoped: follows D7 (the structure suite is out of the extraction) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `use-action-send.ts` edit | "consider \"already handled, refresh\"" | asked (asks 3 to 5) |
| `today-card.tsx` edit branch | "Add copy such as \"already approved, Send or Discard\"." | asked (ask 2) |
| `send/route.ts` + `decide-replay.ts` type | "An additive `reason` field on the 409 body can ship independently" | asked (ask 3) |
| Test updates (hook, click, replay) | "Each needs either a component edit ... or a read-only database check." | inferred, justification: the existing tests pin the old strings and the old `toStrictEqual` body, so CI reds without them |
| `scripts/lib/mutation-harness.sh` | "Extract one `scripts/followthroughs/lib/mutation-harness.sh`." | asked (path ruled to `scripts/lib/`) |
| Two suite edits | "Scorer negative controls in the two probe suites" | asked (asks 6, 7) |
| `scripts/lib/test-affected-paths.sh` two single lines | "Adding a lib file that suites source may need an AFFECTED_*_PATHS declaration." (orchestrator note) | inferred, justification: without it the two suites do not rerun when only the lib changes |
| Deferral issue | "Items 3-6 are optional hygiene; scope them in or out with a recorded ruling" (orchestrator note) | inferred, justification: `wg-when-deferring-a-capability-create-a` requires a tracking issue for any deferral |
| decision-challenges.md, tasks.md | "Persist every decision as a row of the `| Item | Class | Ruling |` table" (orchestrator note) | asked |

### Split Assessment

- Subsystems touched: 3 (`apps/web-platform`, `scripts`, `knowledge-base`)
- Planned files: 14 | Estimated changed lines: ~420
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the operator asked for one PR; the two halves share no files)

## Implementation Phases

### Phase 1: Live policy read (read-only)

1. Run the A.1 command. Capture only policy names, cmd, roles, permissive flag and the RLS flags.
2. Post the result as a comment on #11486 (no DSN, no tokens). Record the one-line result for the PR body.
3. Branch on the verdict per A.1 (unverified, present, or missing). Never apply a migration.

### Phase 2: Copy and the `reason` field (tests first)

1. Write failing tests: `use-action-send.test.tsx` (new constants and table rows for the six states;
   both `reason` values plus absent plus unknown; the 503 string), `today-card.click.test.tsx` (the 503
   regex becomes the new string; a new test: Edit answered 409 `draft_already_approved` shows the new
   string, Edit answered 409 with another body and a 500 keep `Edit failed (NNN)`),
   `send-route.replay.test.ts` (the `toStrictEqual` body gains `reason: "expired"` and a
   `future_clicked_at` body assertion).
2. Implement: `decide-replay.ts` exports `StaleReplayReason`; `refuseStaleReplay` puts it on the body;
   `failureCopy` splits on `json.reason` (extend the parsed-body type); `today-card.tsx` edit branch
   parses `{error}` from a 409 response (with a `.catch` to `{}`) and sets the new string.
3. Verify AC4 (the JSX/className diff invariant), then `tsc --noEmit` in the same command as vitest.
4. One phone-width screenshot of the card error line and the modal `role="alert"` line (strings reach
   about 100 characters) to confirm wrapping; a QA check, not a design step.

### Phase 3: Harness extraction (pure refactor)

1. Capture the ledger labels of a full pristine run of each suite (`bash <suite>`) to a scratch file.
2. Create `scripts/lib/mutation-harness.sh` per B.5; replace the duplicated blocks in both suites with
   `source` plus calls; leave the five one-liners, globals, h1 to h5, m-rows and `MIN_*`.
3. Re-run both suites; diff the labels (identical) and confirm `MIN_*` unchanged. Run `bash -n` and
   shellcheck on the lib (add `# shellcheck disable=SC2154` for the caller-supplied globals).

### Phase 4: Scorer controls and declarations

1. Add the four capture-only controls and the teeth row to each suite (B.6); make `mutate_run` call `mh_caught`; move the floor tail to `mh_floor` with the suite-arg parameter.
2. Raise `MIN_BATTERY` by exactly 5 per suite (from the label diff, not "measured minus slack").
3. Hand-run AC9. Add the two array lines to `scripts/lib/test-affected-paths.sh`.
4. File the deferral issue; update `decision-challenges.md` only with rulings in hand.

### Phase 5: Pre-push ratchets

Run, in the worktree, before the first push: `bash scripts/lint-supabase-deprecated-endpoints.sh` and
`bash tests/scripts/test-lint-supabase-deprecated-endpoints.sh`; `bash scripts/lint-betterstack-emitter-read.sh`
and `bash scripts/lint-betterstack-emitter-read.test.sh`; `bash scripts/test-affected-kb-consumers.test.sh`;
`bash .claude/hooks/grep-q-pipe-guard.test.sh`; `bash scripts/followthrough-exec-bit.test.sh`;
`bash tests/scripts/test-argv-bearer-sweep.sh`; `bash scripts/lint-orphan-test-suites.sh`;
`python3 scripts/lint-guard-contract.py` on this plan. `lint-skill-body-budget.py` is not applicable (no
skill body is edited). Then the two probe suites and the web-platform vitest files touched.

## Files to Edit

- `apps/web-platform/hooks/use-action-send.ts`
- `apps/web-platform/components/dashboard/today-card.tsx`
- `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts`
- `apps/web-platform/server/action-sends/decide-replay.ts` (add the type below `REPLAY_MAX_AGE_MS`: the 11211 suite greps the 12 lines above `export const REPLAY_MAX_AGE_MS` for a back-pointer comment, so nothing may be inserted above it)
- `apps/web-platform/test/hooks/use-action-send.test.tsx`
- `apps/web-platform/test/components/today-card.click.test.tsx`
- `apps/web-platform/test/api/dashboard/today/send-route.replay.test.ts`
- `scripts/followthroughs/inngest-luks-keeper-dark-11265.test.sh`
- `scripts/followthroughs/dispatch-recovery-sweeper-11211.test.sh`
- `scripts/lib/test-affected-paths.sh` (two single-line array entries)

## Files to Create

- `scripts/lib/mutation-harness.sh`
- `knowledge-base/project/specs/feat-one-shot-11486-11520-todaycard-copy-mutation-harness/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-11486-11520-todaycard-copy-mutation-harness/tasks.md`

Verified unaffected (no edit): `send-route.spawn.test.ts` (503 body unchanged), `typed-confirm-modal-pending.test.tsx`
(asserts `Send failed (500)` and the modal copy, not the changed strings), `edit/route.ts` (409 body unchanged),
`scripts/test-all.sh` (no suite added or removed), `betterstack-alert-structure.test.sh`.

## Acceptance Criteria

### Pre-merge (PR)

- AC1. The live read ran, or is recorded as unverified with the SQL in the PR body; its result is a comment on #11486. No DSN or token appears in any comment, commit or log.
- AC2. The six strings in A.2 are exactly as written; `grep -rn "start the agent\|Click Send again to retry" apps/web-platform/hooks apps/web-platform/test` returns no hit for the old 503 string.
- AC3. The 409 `approval_expired` body carries `reason` equal to `expired` on the archive arm and `future_clicked_at` on the skew arm; an absent or unknown `reason` renders the unchanged copy (tested both ways).
- AC4. `git diff -U0 origin/main -- apps/web-platform/components apps/web-platform/hooks | grep -E '^[+-][[:space:]]*(<[A-Za-z]|.*(className|role=|aria-|data-))'` prints nothing, and no new file exists under `components/`.
- AC5. The hook stays card-neutral: `grep -n -i "edit\|discard" apps/web-platform/hooks/use-action-send.ts | grep -v '^[0-9]*:[[:space:]]*//'` prints nothing (only comment lines mention them), and the stale comment above `failureCopy` that says the 503 line "only says to click Send again" is updated to match the new string.
- AC6. A full pristine run of each probe suite before and after the extraction produces identical ledger labels, with `MIN_FIXTURE` and `MIN_BATTERY` unchanged at that step.
- AC7. After Phase 4, each suite's `MIN_BATTERY` equals its pristine battery row count (old value plus exactly 5, from the label diff) and a pristine run exits 0; a `--no-battery` run of each suite still exits 0 (the `mh_floor` third parameter).
- AC8. `mh_caught` is the only place the `FAIL: <frag>` match lives; neither suite contains an inline `grep -qF -- "FAIL: $frag"`, and `grep -n "mh_caught" scripts/lib/mutation-harness.sh` shows `mutate_run` calling it (the glue between the scorer and `mutate_run` is grep-pinned, not suite-detected: see the Guard Contract residual).
- AC9. Hand-run, each against a scratch copy of the lib: (a) `mh_caught() { return 0; }` (the `elif true` equivalent), (b) `mh_caught` matching any `FAIL:` line ignoring the fragment, (c) `mh_caught` also counting `PASS: <frag>` lines. All three make BOTH suites exit non-zero, each with a named `FAIL:` line from a control or the teeth row.
- AC10. `scripts/lib/mutation-harness.sh` is tracked at mode 100644, `bash -n` and shellcheck clean, and defines functions only (no assignment, `set` or `trap` at source time).
- AC11. `scripts/lib/test-affected-paths.sh` lists the lib in both arrays; `scripts/test-all.sh` is not in the diff; `lint-betterstack-emitter-read.sh`, `followthrough-exec-bit.test.sh` and the argv-bearer sweep stay green.
- AC12. One deferral issue exists for #11520 items 3 to 6 plus the residual 403 copy (item 7); `gh issue list` net flow for this PR is closes 2, files 1 (or files 2 with the stated P1 exception).
- AC13. PR body: `Closes #11486` and `Closes #11520` on separate lines (or `Ref #11486` when the read is unverified), no "fix" word adjacent to an issue number, ends with the generated-with line.

### Post-merge (operator)

- None. The deferral issue and any P1 are tracked issues, not operator checklist items.

## Guard Contract

### Guard 1 — scorer wrong-reason control (`mh_caught`)

**Property.** A mutant is credited as caught only when its inner run printed its own `FAIL: <claimed fragment>` line, and a dead scorer turns both probe suites red.

**Assembly.** The scorer is one function, `mh_caught` in `scripts/lib/mutation-harness.sh`, reached through one chokepoint: `mutate_run`, which `mutate_sub` calls and which the suites' direct `mutate_run` rows call. Members: the two probe suites (`inngest-luks-keeper-dark-11265.test.sh`, `dispatch-recovery-sweeper-11211.test.sh`) each source the lib and each carry the same four controls plus a teeth row. Not covered by design: `betterstack-alert-structure.test.sh` (own `fail_line_has` scorer and M-scorer row) and `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` (own `_red_verdict`); they keep separate scorers (D7).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Lib: `mh_caught() { return 0; }` (the `elif true` equivalent) | RED in both suites (the three "not caught" controls and the teeth row) |
| 2 | Lib: `mh_caught` matches any `FAIL:` line and ignores the fragment | RED in both suites (the different-row control) |
| 3 | Lib: `mh_caught` also counts a `PASS: <frag>` line | RED in both suites (the PASS-only control) |
| 4 | Suite: delete the five control rows from the SECOND suite after a compliant first, leaving `MIN_BATTERY` at the new value | RED for that suite (its own battery floor; run it for the first suite too) |
| 5 | Suite: the teeth row's subshell does not override `mh_caught` (runs the pristine scorer) | RED (the row asserts at least one control reds under a dead scorer, so a vacuous teeth row fails itself) |

**Harness rows.** Edit to the suite: row 4 (and row 5, which edits the suite's teeth row). Must-PASS input that is not the canonical: the first control's log holds the fragment mid-line inside surrounding text, so the scorer is shown to be a substring-on-`FAIL:` match and not an exact-line match against a canonical log; and the pristine-run diff (AC6) shows every existing mutant is still credited.

**Residual (accepted).** Nothing in the suite detects `mutate_run` ceasing to call `mh_caught`: the controls call the scorer directly and every existing mutant carries a correct fragment. AC8's grep pins that glue; driving `mutate_run` itself with a wrong-reason inner run would need an isolated ledger per suite and is not worth the fragility for a function with two callers.

**Anchor.** The control and the lib move together in one diff, so a diff-only check proves consistency, not integrity. The outside anchors are (a) the pristine ledger-label list captured BEFORE the extraction (AC6), which a weakening cannot also edit, and (b) the rule that `MIN_BATTERY` rises by the label-diff count (AC7), not by a number read off the run. The wrong-reason log fixtures are synthetic and committed in the suites, never recorded from a real run.

## User-Brand Impact

- **If this lands broken, the user experiences:** a send-error line on the Concierge draft card that points the founder at the wrong action (for example telling them to click a button that is not on screen), or an Edit refusal that still reads as a bare status code, so they abandon an approval they could have completed.
- **If this leaks, the user's workflow is exposed via:** nothing new; the added `reason` value is a fixed two-value enum on a response to the authenticated owner, and the live read prints only policy metadata, never row data or the DSN.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** every state is recoverable by a refresh or a re-click and non-destructive (the prior send-retry plan ruled the same tier), so it is not a single-user incident; it is above `none` because it is the trust-critical approval surface and the diff touches a send route.

## Observability

```yaml
liveness_signal:
  what:            Sentry events on the send route (feature spawn-agent, op inngest-replay-stale) carry extra.reason; the new wire field uses the same two values
  cadence:         per refused replay
  alert_target:    Sentry issue stream for the web-platform project (no new alert; the #11211 sweeper probe already counts STALE events)
  configured_in:   apps/web-platform/app/api/dashboard/today/[id]/send/route.ts (refuseStaleReplay)
error_reporting:
  destination:     Sentry via reportSilentFallback / warnSilentFallback (SENTRY_DSN server env)
  fail_loud:       a 0-row archive reports op messages-archive-no-row; a lookup error returns 500 internal_error with op action-sends-lookup
failure_modes:
  - mode:          the live messages UPDATE policy is missing (Discard/Edit 403, archive no-ops)
    detection:     Phase 1 live pg_policies read, recorded on #11486; thereafter op messages-archive-no-row on any successful send
    alert_route:   Sentry issue stream; a P1 issue if the read shows the gap
  - mode:          a client sees an unknown reason value (deploy skew)
    detection:     hook tests pin the fallback copy; no runtime signal needed (copy degrades to the unchanged string)
    alert_route:   none required
  - mode:          the scorer silently stops discriminating
    detection:     the four controls plus the teeth row in both probe suites, and the MIN_BATTERY floor
    alert_route:   CI red on the scripts shard
logs:
  where:           Sentry (route events); CI logs for the probe suites
  retention:       Sentry project retention; CI log retention
discoverability_test:
  command:         grep -o 'op: "inngest-replay-stale"' "apps/web-platform/app/api/dashboard/today/[id]/send/route.ts"
  expected_output: op: "inngest-replay-stale"
```

## Domain Review

**Domains relevant:** Product, Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO rulings D1 to D10, plan-review dispositions D11 to D13 (decision-challenges.md): the agent may run the read-only live check; `reason` reuses the code-arm values with no ADR; the harness lib belongs in `scripts/lib/` with the five helpers staying in each suite; the scorer control is four rows plus a teeth row; #11520 items 3 to 6 and the structure suite are descoped into one deferral issue.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline); CPO reviewed
**Agents invoked:** soleur:product:cpo, soleur:engineering:cto
**Skipped specialists:** soleur:marketing:copywriter (CPO: five short strings, voice-checked; not needed), soleur:product:design:ux-design-lead (copy-only, no structural change; exemption D2 with a mechanical diff invariant, AC4)
**Pencil available:** N/A (no UI surface change: copy-only exemption D2)

#### Findings

CPO: advisory tier, no wireframe; the strings fail today in four ways (dead-end Edit message, two situations on one string, a success the founder does not know about, a button name that is not in the modal). One planner correction to the CPO strings (D9): "nothing was sent" is replaced by "this attempt didn't go through" because a replay refusal can follow an enqueue that was accepted but never acknowledged, so the stronger claim could be false. Residual: the three `DENY_REASON_COPY` 403 strings in `today-card.tsx` also say "Click Send again to re-authorize" and have the same button-name mismatch in the modal path; tracked as item 7 of the deferral issue.

## Test Scenarios

- Given a 409 `approval_expired` with `reason: "expired"`, when Send fails, then the card shows the expired copy and not the fallback.
- Given a 409 `approval_expired` with `reason: "future_clicked_at"`, then the skew copy shows and it names neither Send nor Confirm send.
- Given a 409 `approval_expired` with no `reason`, with `reason: "other"`, and with `reason: 7`, then the unchanged fallback copy shows.
- Given a 409 `not_a_draft`, then the "already handled" copy shows and no string names Edit or Discard.
- Given a 503 `enqueue_unavailable` from the card and from the typed-confirm modal, then the same surface-neutral string shows in both and the modal stays open.
- Given an Edit POST answered 409 `draft_already_approved`, then the card shows the approval string; given a 500 or a 409 with another body, then `Edit failed (NNN)` shows.
- Given the send route replay at 23h01m, then the body is `{ error, message_id, reason: "expired" }` and the draft is archived; given a future `clicked_at`, then `reason: "future_clicked_at"` and no archive.
- Given the lib scorer neutered, then both probe suites exit non-zero (AC9).

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or carries placeholder text fails `deepen-plan` Phase 4.6; this one is filled.
- `mutate_helper` neuters `check()`/`has()`/`hasnt()` by awk over the suite file, so those definitions MUST stay as suite lines; moving them into the lib silently makes the h1 to h5 rows report "did not land".
- A mutant copy of the suite lives in `$MUT`; any lib path derived from `BASH_SOURCE` resolves to the scratch dir. Use `$REPO` (already exported as `FT_REPO`).
- `MIN_BATTERY` is a ratchet: derive the +5 from the ledger-label diff. A floor set to "measured minus slack" or left unchanged lets a dropped control pass.
- The 11211 suite reads `decide-replay.ts` for a back-pointer within 12 lines above `export const REPLAY_MAX_AGE_MS` and reads the route's op/feature tags by grep; the route edit must not rename or reformat either, and the new type goes below the constant.
- The `reason` wire value `future_clicked_at` is an internal term; the client never displays it.
- Do not claim "nothing was sent", and do not claim the draft was cleared, in any refusal string (D9, D12): the archive is best-effort and a replay refusal can follow an enqueue that was accepted but never acknowledged.
- If the live read shows a missing UPDATE policy, do not "fix it with copy" and do not add a migration here.
- The affected-set derivation does not follow `"$REPO/..."` paths; the two array lines are the only thing that reruns the suites on a lib-only change.

## Non-Goals

- No new `.pen`, no new component, no new element; no change to the Discard/Edit 403 copy.
- No migration, no production write of any kind; no terraform; the bundle build, digest promotion and dead-man alert are untouched.
- `betterstack-alert-structure.test.sh` keeps its own harness; #11520 items 3 to 6 are in the deferral issue.

## References

- #11486, #11520; origin #11212 and the PR 11483 review; draft PR 11566.
- `knowledge-base/project/specs/feat-one-shot-11486-11520-todaycard-copy-mutation-harness/decision-challenges.md`
- `knowledge-base/engineering/operations/runbooks/egress-audit-dsar.md` (the read-only psql pattern); `apps/web-platform/scripts/rls-parity-check.ts` (ADR-111 precedent)
- `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` (Excluded list)
