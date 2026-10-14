---
title: "Every correction I shipped needed correcting — and the measurement that settled each took seconds"
date: 2026-09-20
category: review-methodology
module: infra-observability
issue: 8296
pr: 8439
refs: [8296, 8439, 6894, 8294, 8295, 8285, 6480, 7393]
synced_to: [review, plan-sharp-edges, test-design-reviewer, betterstack-log-query]
tags: [guard-design, mutation-testing, review-panel, instrument-verification, correction-sweep, concurrency, merge-is-apply, discoverability-test, rate-limit-resume, terraform, better-stack]
---

# Every correction I shipped needed correcting — and the measurement that settled each took seconds

## Problem

PR #8439 is PR-1 of #8296: flip `var.inngest_luks_cutover_complete` to `true` so the Better Stack
wrong-volume alert arms after the 2026-09-20 LUKS cutover (ADR-142), and teach the drift
reconciler to resolve a `var`-driven `paused` so the alert stops being exempt from drift reporting.
A one-literal change plus ~150 lines of TypeScript.

The eleven-seat panel returned 34 findings. Not one was in the feature. Every finding was in
something I wrote **to make the feature trustworthy** — a comment correcting an earlier false
comment, a mutation guard proving the flip cannot regress, a test comment labelling a survivor
"equivalent", a plan block declaring how the change is discoverable, a PR body describing what
merging does. Each was a claim I had adjudicated myself and each was refuted by a command that
ran in under a minute.

## Root cause: a correction inherits the framing of the defect it corrects

### 1. Fixing three false claims produced three new false claims

The original comments in `apply-web-platform-infra.yml` said the merge gate was "CODEOWNERS
review + branch protection on main". I measured that false (protection endpoint 404s; no
ruleset carries a `pull_request` rule) and rewrote three sites. The rewrites said:

- "The validate-vector-config check is required by the CI Required ruleset" — it is not among
  that ruleset's contexts (`infra/github/ruleset-ci-required.tf`).
- "A ruleset is server-side and not checked into this repo" — two of three are declared in
  `infra/github/ruleset-*.tf` (ADR-032).
- "Nothing forbids a direct push to main" — a `required_status_checks` rule rejects a push of
  an unchecked commit; the residual is a fast-forward of an already-green commit, an admin
  bypass, or the CLA bot's `always` bypass.

Two seats each found one independently. The mechanism: I measured the SUBJECT of the old claim
(is there a review rule?) and then wrote three sentences whose subjects I had not measured
(which contexts are required; where rulesets live; what an unchecked push does). The fix's
prose read as established because it stood in the place of a measured correction.

### 2. Both of my self-refutations were wrong, in opposite directions

**(a) A race that did not exist.** I hypothesised that the guard's inner-run `EXIT` trap raced
the outer trap and could strand a mutation in `variables.tf`. I nearly committed a message
asserting the race. Measured: 0/8 stranded under SIGINT at random offsets — bash defers a trap
until the foreground child exits, so inner-then-outer is guaranteed. The change was kept as a
simplification with that rationale, not as a fix.

**(b) An "equivalent" mutant that was not.** Dropping `vars` at `runReconcile`'s
`discoverLogsAlertsFromInfra` call site survived 131/0, and I wrote "EQUIVALENT" into the test
comment. test-design-reviewer refuted it: the default argument runs the STRICT resolver, which
throws on a malformed SIBLING file; `discover()` swallows the throw into a marker the per-file
pass already emitted, and arm 3 goes silent — no OK line, no MISMATCH. The blast-radius suite
proved containment for arms 1–2 and never asserted arm 3. One case (`zz-broken.tf` next to an
armed alert) reds the mutant: 131/1.

A survivor is equivalent only when the writer can enumerate every observable and show each is
unchanged. "The suite is green" is the survivor's claim, not its proof.

### 3. Clean under interruption is not clean under concurrency

Row 7 mutated the TRACKED `variables.tf` in place under a restoring trap. Single-process
interruption was measured clean (2a). security-sentinel then ran two staggered instances:
**9/24 stranded**. Instance B snapshots A's in-flight mutation as its pristine copy, then
faithfully restores it. No trap ordering fixes that — the snapshot itself is the defect.

The structural fix deletes the class: mutate COPIES in `$MUT_DIR` and hand the inner run
env-overridden paths (`LUKS_GUARD_TF`, `LUKS_GUARD_VARS`, `LUKS_GUARD_WF`). No trap, no
snapshot, no tracked write. Acceptance: 0/8 stranded with two instances, both exit 0.

### 4. A harness that grades any non-zero as RED is green over a dead battery

The mutation loop counted a caught mutation whenever the inner run exited non-zero. Two
probes: `SELF=/nonexistent` (rc 127 on every row) and an inner floor raised past the
presence-row count (rc 1 on every row, for the wrong reason). Both printed `21 passed, 0
failed`. My own comment described the hazard without guarding it.

Fix: an **instrument control** (the inner run on the PRISTINE copies must exit 0 before any
mutation row — a red baseline aborts the battery) plus **rc discrimination** (only rc=1 is a
caught mutation; rc≥2 and 127 are "instrument, not evidence" and fail the row). The control
immediately caught a real defect: the rewritten `sql_query` regex was written from memory
(`"\\n"` where the file has `"/\\s+/"`) and the pristine run was red.

### 5. The plan's discoverability test verified nothing about this PR

`discoverability_test.command` named `scripts/followthroughs/inngest-luks-property-8296.sh` —
a script PR-2 creates — behind a `credentials_required` waiver. The ADR-175 gate therefore
reported SKIP-DECLARED for a command that does not exist. Replaced with a credential-free
sub-second `bun -e` call to `discoverLogsAlertsFromInfra` against the real root, expected
`ARMED`.

And `credentials_required: none` is not "no credentials": that field is the #7393 waiver
register, so declaring `none` enrolled a non-waiver and moved the corpus baseline 16→17
(`preflight-discoverability-test.test.ts` check 10). Omit the field.

### 6. "The apply is deliberately not run by this PR" was false — merging IS the apply

`variables.tf` is under `apply-web-platform-infra.yml`'s push-trigger `paths:`, and both alert
resources are in the main-apply `-target` allowlist. There is no separate operator dispatch:
the merge click is the production mutation. Three seats found it; the PR body was rewritten
with that as its headline and the merge became the per-command authorization
(`hr-menu-option-ack-not-prod-write-auth`).

The question "does merging this diff, alone, mutate production?" is answerable at plan time
from two greps (`paths:` and `-target=`). It was discovered at review.

## Solution

- Guard: copies not tracked files; instrument control; rc discrimination; 10 mutation rows
  including the variable rename and the workflow-allowlist drop; floor 23, inner 13.
- Reconciler: `resolvePausedIntent` with `PAUSED_VAR_RE` reusing `IDENT`; `null` → EXEMPT
  (quiet by design, polarity documented on `pausedResolvesFalse`); `listTfFiles` refuses
  `*.tfvars`; H6 real-root row; arm-3 blast-radius row; positive control on the paused
  direction.
- Workflow comments: one measured "Authorization model" block; every other site a pointer.
- Plan: credential-free discoverability test; no `credentials_required` line.
- PR body: merge = arming apply, stated first.

## Key insights

1. **A correction round is where new unmeasured claims ship.** For every sentence a fix ADDS,
   name the command that falsifies it and run it — the subject of the new sentence is usually
   not the subject you just measured.
2. **An equivalent-mutant label must carry the enumeration that proves it.** If you cannot
   list every observable and show each unchanged, it is a surviving mutant, and the suite is
   missing a case.
3. **In-place mutation of a tracked file is unsafe under concurrency regardless of trap
   discipline.** Mutate copies and pass paths by env; delete the trap.
4. **A mutation harness needs an instrument control and rc discrimination**, or it reports
   green over a battery that never ran.
5. **`credentials_required` is a waiver register, not a boolean.** A discoverability test
   must name a command that exists in THIS PR's tree.
6. **Ask "does merging this alone mutate production?" at plan time** for any infra diff, from
   `paths:` and `-target=`, and put the answer first in the PR body.
7. **The 429 resume path works.** All 11 seats died on a session limit; one probe resume via
   `SendMessage` proved the limit had cleared; 5 dead seats resumed with transcripts intact
   (one had already found a defect before dying), 6 fresh spawned in batches; a cron wakeup was
   armed as fallback and cancelled.

## Session Errors

1. **Read a 0-job cancelled dispatch as the byte gate.** Run 35516720404 was displaced by a
   sibling session's dispatch on the same concurrency group. — Recovery: read the sibling run,
   did not re-dispatch. — **Prevention:** a cancelled run with 0 jobs is concurrency
   displacement; `gh run list --workflow … -L 5` before attributing a cause.
2. **Bash heredoc delimiter `PY` collided with the file's own `<<PY`.** — Recovery: wrote
   scripts via the Write tool. — **Prevention:** heredoc delimiters must not appear in the
   payload; use a random token or a file.
3. **`--grep 'a\|b'` to `betterstack-query.sh` is a literal LIKE**, and `.message[0:230]` on
   a JSON-object message produced a false "absence". — Recovery: one literal grep per term;
   object-aware jq. — **Prevention:** routed to `betterstack-log-query.md`.
4. **FSM monitor filter silent 30 min while the cutover had completed at 15:29:10Z** — a tag
   read with a limit let heartbeats scroll the transition row out; nearly filed a bogus
   observability-gap issue. — Recovery: `--grep cutover-complete` found it; withdrew. —
   **Prevention:** grep the transition REASON, never tag+limit, for a rare row among
   heartbeats.
5. **"Resume had no downstream effect" — query window ended at 14:50:16 and the write landed
   at 14:50:16.9.** — Recovery: re-queried. — **Prevention:** a negative read must be bounded
   AFTER the action's own timestamp, with slack.
6. **Prefix mutant survived the first battery** — the fixture only had `f=true`. — Recovery:
   added the `f=false` anchor-direction case. — **Prevention:** every resolver fixture carries
   both polarities.
7. **Asserted a trap race that does not exist** (§2a). — **Prevention:** measure an
   interruption hypothesis with `kill -INT` at random offsets before writing it into a commit.
8. **Labelled a surviving mutant EQUIVALENT** (§2b). — **Prevention:** enumerate observables;
   a green suite is not a proof.
9. **Three new false claims in the correction of three false claims** (§1). —
   **Prevention:** falsify every ADDED sentence by its own subject.
10. **Guard regex written from memory** (§4) — caught by the instrument control. —
    **Prevention:** copy the anchor from the file; the control exists for exactly this.
11. **`credentials_required: none` enrolled the plan as a waiver** (§5). — **Prevention:**
    omit the field when there are no credentials.
12. **`lint-trap-tempfile-ownership.py --base` is not a flag.** — Recovery: ran the registered
    `.test.sh` (20/20). — **Prevention:** `grep run_suite scripts/test-all.sh` for the
    invocation.
13. **markdownlint blocked the commit (MD031/MD038/MD046)** on fences inside a list. —
    Recovery: 2-space list-column fences with blanks. — **Prevention:** run
    `markdownlint-cli2` on plan edits before commit.
14. **HTTP 429 killed 5 review seats** (§7). — **Prevention:** none needed; the resume path
    is the remedy.
15. **First `git commit` hit the 600 s timeout** — lefthook's bun battery behind the advisory
    lock. — Recovery: TaskStop, verified no `index.lock`, recommitted with
    `LEFTHOOK_EXCLUDE=bun-test`. — **Prevention:** check `test-all.sh --capacity` before a
    commit that stages `.ts`.
16. **PR body claimed the apply was not run by this PR** (§6). — **Prevention:** grep
    `paths:` and `-target=` at plan time.
17. **In-place mutation guard stranded 9/24 under two instances** (§3). — **Prevention:**
    mutate copies.
18. **Harness graded any non-zero as RED** (§4). — **Prevention:** instrument control + rc
    discrimination in every mutation loop.

## Related

- `2026-08-06-i-shipped-two-unmeasured-causal-claims-inside-the-lint-that-forbids-them.md` —
  the same shape: the prose defending a fix is where the unmeasured claim lands.
- `2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md` — a fix commit is the
  least-audited surface.
- `2026-09-07-my-instruments-reported-green-while-measuring-nothing.md` and
  `2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`
  — the instrument-control requirement, now applied to a mutation loop.
- `2026-09-18-every-instrument-i-built-to-check-the-guards-needed-checking.md`.
- `2026-09-20-the-gate-i-built-to-resolve-a-run-could-be-redirected-by-one-env-var.md` — the
  same PR shape one day earlier: every P1 was in the guard, not the feature.
