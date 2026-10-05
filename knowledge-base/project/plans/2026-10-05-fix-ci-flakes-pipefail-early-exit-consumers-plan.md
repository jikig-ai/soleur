---
title: "fix: remove the pipefail early-exit-consumer flake class from three CI suites and triage the other 2026-10-05 flakes"
type: fix
date: 2026-10-05
slug: ci-flakes-pipefail-early-exit-consumers
branch: feat-one-shot-ci-flakes-queue-slowness-9482
issue: 9482
refs: [9482, 7376, 7432, 7005, 6601, 9217, 8785, 9167, 9170, 8022]
lane: cross-domain
---

# fix: remove the pipefail early-exit-consumer flake class from three CI suites and triage the other 2026-10-05 flakes

`lane:` note: no spec.md exists for this branch (one-shot path), so the lane defaults to
`cross-domain` (fail-closed, TR2). The work is engineering-only.

## Overview

Five CI flakes on 2026-10-05 were re-investigated from the completed run logs. They do **not** share one
root cause, so the work splits into three subsystem-scoped PRs. **This PR (PR-1) carries the group that
shares a root cause**: three suite flakes (items 2, 3 and 4a) that are one defect class, a bash pipeline
whose reader exits before its writer finishes, under `set -o pipefail` (SIGPIPE / EPIPE). The leading
hypothesis from #7376 (contention under `-P`) is **partly right and partly wrong**: contention is the
*trigger* that widens the race window, not the root cause. Evidence is in `## Flake Dossier`.

PR-2 (e2e: the Turbopack Google-font compile failure, which ejected two queue entries, plus the
`role=status` strict-mode collision) and PR-3 (live-verify rail FAIL diagnosis) are explicit follow-ups tied
to existing trackers (#8785, #9170, #9167, #8022). No new issues are filed (net-issue-flow gate).

References use `Ref #N` throughout. Nothing here changes merge-queue ruleset parameters
(`infra/github/ruleset-ci-required.tf` is untouched), acts on the three operator decisions on #9482, or
flips ADR-270 from `adopting`.

## Premise Validation (Phase 0.6, run before research)

Every cited run, issue and artifact was re-fetched. What held: all eight runs exist with the cited jobs
failing; #9482, #9167, #9170, #9190, #7376, #8022, #7969, #7215, #5634 are all OPEN; the two infra
artifacts (`infra-suite-logs-0` of run 37296532619, `infra-suite-logs-1` of run 37307152949) were
downloadable and carry the quoted failures verbatim. What was stale or wrong in the brief or its trackers:

- **"The next release run on the identical app code passed" (item 5) is false.** Run 37309168420 (same head
  `0b35762459`) skipped the harness step (`SKIPPED:no-triggering-paths`). The harness has not passed in CI
  since the first release containing #9270.
- **#9167's "dev-Supabase returns `Signups not allowed for otp`" is a log line the test fabricates itself**
  (`apps/web-platform/e2e/otp-login.e2e.ts:141` mocks that exact string). It is present in the passing leg of
  the same runs. The real cascade in the two 64-red e2e runs is the dev-server font compile error.
- **#7432 item 2 / #7005 say a pipe-fed `grep -q` race "cannot fire below 64 KiB".** Falsified twice: the
  repo's own learning
  `knowledge-base/project/learnings/test-failures/2026-09-25-the-flake-was-sigpipe-at-4kib-and-my-fix-leaked-a-pipe-status-through-a-bare-return.md`
  measured it at ~4 KiB, and this investigation reproduced it with a 3-line producer (`git log -3`, 64 of 300
  false negatives serial) and found it in a CI log (`echo: write error: Broken pipe`, item 3).

## Flake Dossier (Task A: failing assertion, hypothesis, evidence for and against)

| # | Flake | Failing test / assertion (from the cited logs) | Verdict |
|---|---|---|---|
| 1a | e2e, runs 37295454362 and 37224723661 (both `merge_group`, PRs 9505 and 9492) | 64 failed / 37 passed / 21 skipped in both. First red: `cc-soleur-go-routing.e2e.ts:140` `Dev server compile error (5xx on chat route)`, then every `[authenticated]` route returns 5xx (`nav-states-*`, `cc-soleur-go-*`) | One flake. **Font compile failure.** PR-2 |
| 1b | e2e, run 37216842585 (`merge_group`, PR 9478) | 1 failed / 114 passed: `otp-login.e2e.ts:127` `strict mode violation: getByRole('status') resolved to 2 elements` (banner plus the nav-pending island `role="status" class="sr-only"`) | = #9170. PR-2 |
| 2 | `workspaces-luks-verify-workflow.test.sh`, run 37296532619 attempt 1 | `FAIL - an otherwise-healthy run with alarm_selftest=true classifies as selftest -> expected 'selftest', got 'unavailable'`, then `fixture set produced only 4 distinct classes`, then `only 311 assertions ran (floor 313)` | SIGPIPE class, **producer side**. PR-1 |
| 3 | `cron-egress-firewall.test.sh`, run 37307152949 | `FAIL: census self-test: unflagged synthetic positives (allowlist: none; server scan: m5 )`, preceded in the same log by `cron-egress-firewall.test.sh: line 1347: echo: write error: Broken pipe` | SIGPIPE class, **consumer side**. PR-1 |
| 4a | `test-scripts (2/8)`, run 37293827216 (PR 8820 queue entry) | `FAIL: G: plan archive commit missing — the mv failure aborted the run` in `plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh` (44 passed, 1 failed). `test` fails only because it aggregates shard results | SIGPIPE class. PR-1 |
| 4b | `lint-bot-statuses`, run 37212108914 (PR 9477 queue entry) | `lint-infra-no-human-steps.py` flagged `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md:538` | **Not a flake.** Deterministic content failure; no code fix |
| 5 | live-verify, run 37307395675 | `RESULT: FAIL — conversation 9347c2c0-… persisted but did NOT appear in the rail within budget (the #5391/#5436 class)` | Possibly a **real regression** (0 FAIL in 8 conclusive CI runs before #9270, 2/2 FAIL after). PR-3 |

### Item 2: `workspaces-luks-verify-workflow.test.sh` (producer-side SIGPIPE)

**Mechanism (reproduced deterministically).** The workflow's probe step runs
`printf 'DOPPLER_TOKEN=…' | ${WEB_HOST_SSH} … > "$probe_log"` under `set -uo pipefail`
(`.github/workflows/workspaces-luks-verify.yml:480-484`). The suite's `sshstub` never reads stdin. If the
forked `printf` subshell is descheduled until after the stub has exited, `printf` takes SIGPIPE (status 141)
or, where SIGPIPE is ignored as on the CI runner, EPIPE (builtin `printf` returns 1) and the pipeline status
becomes non-zero. Neither 141 nor 1 is 0/3/255/127, so the body falls to
`emit_class unavailable "${reason:-unparsed}"` (workflow lines 596-598), exactly the observed
`expected 'selftest', got 'unavailable'`.

Reproduction: extracted the `reassert` step body, ran it with the suite's stub shape, and delayed only the
producer by 0.4 s (what CPU contention does to a freshly forked subshell). Result:
`rc=141 outcome_class=unavailable outcome_reason=unparsed`, `luks-monitor probe rc=141`. Adding
`cat >/dev/null` to the stub's probe arm and re-running the identical delayed body gave
`rc=0 outcome_class=selftest outcome_reason=alarm_selftest`. A model of the race without the delay: 2 of
19,200 pipelines failed at 6x oversubscription of 4 cores (about 1e-4 per drive; the suite makes dozens of
drives, so roughly 0.5% per suite run under load); 0 of 1,500 serial.

Evidence against / limits: 12 parallel copies of the whole suite pinned to 4 cores (`taskset -c 0-3`) all
passed, so the suite-level rate is low and the attribution of the single CI failure to this mechanism is an
inference (the `unavailable` class is reachable here only through a probe rc outside 0/3/255/127, and a
pipe-status of 141 or 1 from the unread stub is the one such source the stubbed fixture has). Production is not affected: real `ssh` reads stdin to EOF.

### Item 3: `cron-egress-firewall.test.sh` (consumer-side SIGPIPE, smoking gun in the log)

`line 1347: echo "$CEN_MEMBER_SCAN" | grep -qxF "HIT $CEN_D/members/m$k.ts" || CEN_MEMBER_MISS+="m$k "`
runs under `set -uo pipefail` (line 19). `grep -q` exits on the match while `echo` is still writing; bash
reports `echo: write error: Broken pipe` (present in the CI log immediately before the FAIL line) and
pipefail turns the match into a miss for member 5 only. The suite has 31 such lines carrying 33 `echo … |
grep -q…` sites (line 1280 has three; lines 1617-1620 are one `&&` chain), counted with the guard's own
`PATTERN`.

Evidence against: not reproducible locally. 6,000 iterations of the census block (10 greps each) at 6x
oversubscription produced 0 misses on bash 5.3. Why the CI bash wrote the scan in more than one `write(2)`
is unmeasured (no `strace` here), so the write-splitting is a hypothesis; the attribution to the early-exit
reader rests on the log line, and the here-string fix does not depend on the write-splitting detail.

### Item 4a: `reap-archive-persistence.test.sh` (consumer-side SIGPIPE, reproduced)

Assertion G is `git -C "$CLONE_G" log --oneline -3 --format=%s feat-actor | grep -q 'chore(archive-kb)'`
under `set -uo pipefail`. `git log` flushes per commit, `grep -q` exits on the first line. A debug copy that
printed `OUT_G` and the real `git log` on failure showed the commit **was present**
(`d4ae135 chore(archive-kb): persist reap archive for feat-victim`); only the pipeline status was wrong.
Measured: 0/1 serial; **3/24 and 6/32 under 24-32 parallel copies on 16 cores; 9 failures in 56 loaded runs,
all on assertion G.** Micro-model: `git log -3 | grep -q` under pipefail failed 64/300 serial, 71-101/300
loaded. The suite has 11 pipe-fed `grep -q` sites (3 `ls … | grep -q`, 6 `git log … | grep -q`, 1 `git show … |
grep -q`, 1 `git diff … | grep -qE`); the `ls` sites cannot lose this race in practice (one short write)
and are converted because the guard's `PATTERN` flags the shape.

### The #7376 hypothesis, tested

#7376's leading hypothesis (shared scratch dirs, timing, `-P` contention) is **refuted as a root cause and
confirmed as a trigger**. Items 2-4a each fail through one mechanism that needs a scheduling gap to fire.
Contention widens the gap (3/24 loaded vs 0/1 serial for 4a); it does not create the defect, and fixing the
pipeline shape removes it at any `-P`. Shared `mktemp` roots were checked: `cron-egress-firewall.test.sh`
isolates itself under a private `SUITE_SCRATCH` (line 41-55); the luks suite uses one `$SCRATCH` per run;
the reap suite uses `mktemp -d` per run. No cross-suite collision explains any of the three.

### Impact on the queue

Only 4a and the e2e flakes eject merge-queue entries (`Infra Validation` does not run on `merge_group`; items
2 and 3 cost PR re-runs and `ci/main-broken` noise, not queue rebuilds). Ejections observed 2026-10-04/05:
font x2, `role=status` x1, reap-archive x1, lint-bot-statuses x1 (deterministic). PR-2 is therefore the
larger queue lever and should start as soon as this PR is up.

## Research Reconciliation: Brief vs Codebase

| Brief / tracker claim | Reality | Plan response |
|---|---|---|
| Items 2 and 3 flake under `-P` contention (#7376) | One defect class, contention is the trigger (see dossier) | Fix the pipeline shapes; no `-P` change, no retries |
| Next release run passed on identical code (item 5) | Harness skipped; 0 CI PASS since #9270; 2/2 FAIL since | PR-3 diagnosis-first; correct #8022 |
| #9167: dev-Supabase rejects OTP signups | String is mocked in `otp-login.e2e.ts:141`; cascade is the font compile error | PR-2; correct #9167 with the evidence |
| #7432 item 2: SIGPIPE mechanism "cannot currently fire" | Fires at 3 lines (`git log`) and appears in a CI log (`echo` EPIPE) | Extend `grep-q-pipe-guard.test.sh` by named files (repo convention) |
| #7005: safe below the 64 KiB pipe buffer | ~4 KiB per stdio chunk; multi-write producers fire at any size | Record the correction once on #9217 (sweep owner) and #7432 |
| lint-bot-statuses is a flake (item 4) | Deterministic failure of a queued PR whose own PR-level run was red | No fix here; observation recorded on #9482 only |

## Research Insights

- **File paths.** Suites: `apps/web-platform/infra/cron-egress-firewall.test.sh` (1897 lines, `set -uo
  pipefail` line 19), `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` (2107 lines, floor
  `WF_MIN_ASSERTIONS=313` line 2102, `drive` line 670, `sshstub` lines 610-660, existing `hk_mutant`
  sed-mutation helper line 834), `plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh`
  (703 lines, helpers `spec_arch`/`plan_arch` lines 221-223). Guard: `.claude/hooks/grep-q-pipe-guard.test.sh`
  (named-file passes `FILES_7024`, `FILES_8664`, `FILES_8855`; `scan_scorers`; non-vacuity probe). Workflow
  under test: `.github/workflows/workspaces-luks-verify.yml`.
- **Institutional learnings applied.** `2026-09-25-the-flake-was-sigpipe-at-4kib-…` (the model fix: capture
  once, match in bash, deterministic padded regression input, positive control that restores the old shape);
  `2026-10-01-a-grep-q-in-a-pipefail-chain-made-the-trigger-miss-its-own-bug-class.md`;
  `2026-09-28-an-ssh-drop-without-a-pty-is-sigpipe-…`; `2026-06-10-parallel-load-flake-two-mechanisms-…`.
- **Convention to follow.** The guard asserts ZERO per named file (never a baseline), strips comment lines,
  and grows only by naming files ("growth by adding a named file, never by widening a glob"). The repo-wide
  sweep stays with #9217 / #7005 / #6601.
- **Remedy idiom.** `grep -q … <<<"$var"` (here-string, written fully by the shell before the reader runs) or
  capture then glob-match; `grep -c` over the pipe is also safe because `-c` reads all input. `grep -q` on a
  FILE operand is safe.
- **Ratchet on the assertion floor.** The luks suite's floor equals its green count ("deleting ANY assertion
  reds the suite"); adding rows requires raising `WF_MIN_ASSERTIONS` in the same edit.
- **Open code-review overlap:** see the section below.

### Property List and Cut List (Phase 0.6b)

Properties the ask needs: (P1) each flake's root cause is named from evidence; (P2) the three suites cannot
report a false verdict from a pipe's early-exit status; (P3) the fix cannot silently regress; (P4) the
non-reproducible flakes carry a stated hypothesis; (P5) evidence lands on existing trackers, no new issues.

| Mechanism proposed or implied | Property it buys | Verdict |
|---|---|---|
| "loop the suite under load, N parallel instances" as a standing regression guard | P3 | **Cut as a CI guard** (37-74 s x N on every run). Kept as a one-off before/after measurement in the PR body. The static named-file pin plus a deterministic race-forcing row buy P3 at ~0 s |
| A new repo-wide `grep -q` linter (#7432 item 2) | P3 | **Cut.** `.claude/hooks/grep-q-pipe-guard.test.sh` already is the linter; its convention is named-file growth |
| Blind retries / widened timeouts | none | Forbidden by the brief; not proposed |
| Quarantine with a tracked issue | P2 | Not needed: all three fixes are small and in scope |
| New issues per flake | P5 | **Cut.** Fold into #7376, #7432, #9217, #8785, #9167, #9170, #8022 |

## Proposed Solution (PR-1, this branch)

1. **`reap-archive-persistence.test.sh`.** Replace the 11 pipe-fed early-exit greps. One idiom for all 11
   sites (no regex-to-glob semantic change): capture then here-string, `reap_out="$(ls DIR 2>/dev/null)"; grep -q X
   <<<"$reap_out"` (and `git …` the same way), negated forms keep their `!`. The capture variable gets a name
   distinct from the `out` locals at lines 203/211. Same assertion text, same count (45).
2. **`cron-egress-firewall.test.sh`.** Mechanically rewrite the 33 `echo "$V" | grep -q… PAT` sites (31
   lines) to `grep -q… PAT <<<"$V"`, globally and quote-aware (patterns contain spaces, parentheses and
   `$((…))`). No pattern text changes. Verified by a throwaway inverse-transform diff (script pasted in the PR
   body, not committed) showing exactly 33 changed segments, plus a rescan with the guard's pattern finding
   zero. Any site whose `$V` can start with `-` is reviewed by hand (`echo` would eat a leading `-n`).
3. **`workspaces-luks-verify-workflow.test.sh`.** (a) `sshstub` drains stdin at the top of the stub, guarded by `[[ -p /dev/stdin ]]` (not a tty test, which
   would hang under a non-closing inherited stdin), so every pipe-fed arm (probe, host-key failure, tar
   extract) cannot see a closed pipe regardless of scheduling; a one-line comment cites the contract (real
   `ssh` reads stdin to EOF). (b) Convert the one `tr … | grep -q` site (line 722) to
   `cr_out="$(tr '\r' '\n' < f)"; grep -q … <<<"$cr_out"`. (c) Two race rows. The producer `printf` sits on
   workflow line 481 and its pipe on continuation line 482, so a line-oriented `sed` cannot wrap it: rewrite
   the single token `printf 'DOPPLER_TOKEN` to `slow_printf 'DOPPLER_TOKEN` and prepend a `slow_printf`
   function that sleeps 0.4 s then calls `printf`, with a `grep -c` check that the edit landed exactly once.
   This needs a small new helper (not `hk_mutant`, which compares only `outcome_reason`): it asserts class,
   reason and probe rc. Row 1 (must-PASS): delayed body vs the draining stub classifies `selftest`. Row 2
   (positive control, same input): the delayed body against `FIXTURE_NO_DRAIN=1` classifies
   `unavailable/unparsed` with a probe rc outside {0,3,127,255}. rc is asserted as "non-zero and not one of
   those", never 141, because CI ignores SIGPIPE and `printf` then returns 1. (d) Raise `WF_MIN_ASSERTIONS`
   to the new exact green count.
4. **`grep-q-pipe-guard.test.sh`.** Add `FILES_7376` (the three suites), its tracked-file check, a member
   count pin (3, distinct), and a pass `grep-q-zero-7376-pass` using a DEDICATED scan function over `PATTERN`
   plus `PATTERN_AWK_EXIT` with the comment filter (not `scan_scorers`, which also applies
   `PATTERN_PIPED_SCORER` and would flag safe `grep -cF --` lines at cron:719/780/1371 and luks:1090); the
   non-vacuity probe drives that same function. Add ONE **runtime control**, reusing the existing
   `yes | grep -q y` control pattern at `tests/scripts/test-sentry-full-root-apply.sh:349/373` rather than
   inventing a third copy: a producer that prints the needle on line 1 and then at least 200 KB of
   non-matching lines (the causal quantity, written after the reader can exit; the producer is generated, so
   the floor is by construction, asserted once with `wc -c`). On that input the old shape must return
   non-zero under pipefail with SIGPIPE default (141) and with `trap '' PIPE` (the CI case, EPIPE, status
   non-zero), and the here-string and capture shapes must return 0. If the environment cannot exhibit the
   failure the control reports `environment cannot exhibit the race` (a distinct, named result), not a generic
   RED, so the control cannot become a flake source; run it 50 times under load before merging. Whether this
   control stays is a Taste item recorded in `decision-challenges.md`.
5. **Trackers** (comments only, posted at ship time): #7376, #7432, #9217, #8785, #9167, #9170, #8022,
   plus one factual observation on #9482 about item 4b. PR body uses `Ref #…`, never `Closes`.

### What this PR deliberately does not do

- No `-P` change, no `JOBS=1` change (that is #7432 item 1), no retry, no timeout widening, no deleted
  assertion.
- No repo-wide sweep of the ~800 other `| grep -q` sites (#9217 / #7005 / #6601; the guard grows by named
  file). The `| head -N` family is out of scope: producers there write one short chunk, and no status of those
  pipelines reaches a verdict in the three suites (census recorded in the PR body).
- No change to the e2e, live-verify, web-platform runtime, `infra/github/**` or ADR-270.

## Follow-up PRs (explicit, tied to existing trackers, not new issues)

### PR-2: e2e (largest queue lever; tracker #8785, folds #9170 and #9167)

**Root cause of 1a (reproduced).** `apps/web-platform/app/fonts.ts` imports `next/font/google`. Under the
Turbopack dev server, when the stylesheet request succeeds but the `fonts.gstatic.com` woff2 fetch fails,
the server throws `Module not found: Can't resolve '@vercel/turbopack-next/internal/font/google/font'`
(`next/font/google queries have exactly one entry`) and **every** route then returns 5xx for the life of
the process, which is why Playwright's retry (`retries: process.env.CI ? 1 : 0`) cannot recover and 64 tests
go red. A fully offline dev server degrades gracefully (200, fallback font), so the failure needs the partial
case. Local repro that yields 500 x3: `NEXT_FONT_GOOGLE_MOCKED_RESPONSES=<mock css file>` plus
`unshare -rn` (network off, loopback up) and `next dev`. Both CI logs carry 7,354 / 7,372
`NextFontGoogleFontFileReplacer` error lines. The same class hit the release Docker build on 2026-09-24
(comment on #8785), so this is also a deploy-availability flake. #8785's own escalation criterion (two
recurrences in a week) is met.

**Fix direction.** Self-host Inter with `next/font/local` (vendored latin variable woff2 plus the OFL text)
so dev, e2e and release builds have no network dependency on Google; a static ban on `next/font/google` in
app code; RED/GREEN via the offline repro. PR-2 starts immediately after this PR is opened, in its own
worktree, and is not gated on this PR merging (it also fixes a deploy-availability flake).

**1b (#9170).** Scope `otp-login.e2e.ts:174/177` to the banner (`getByRole("status").filter({ hasText:
/no Soleur account found/i })`) and add a row that injects a second `role=status` before the assertion.
Mutation: restore the bare locator and the row reds on strict mode.

Sharp edges for PR-2: `next dev` rewrites `apps/web-platform/tsconfig.json` and writes untracked
`apps/web-platform/AGENTS.md`/`CLAUDE.md` (cleaned up here); the font swap changes production build output, so
its plan runs the Product/UX and brand gates; code-review overlap on `app/fonts.ts` is #3564.

**Correction owed to #9167.** Its evidence run's logs have expired, so its original attribution cannot be
re-checked, but both 64-red runs in this dossier are the font failure and the `Signups not allowed for otp`
line is test-fabricated. Recommend retitling #9167 after PR-2 verifies.

### PR-3: live-verify rail FAIL (tracker #8022; also touches #7969, #7215, #5634 context)

**Data (CI, 2026-09-23 to 2026-10-05, 355 release runs):** the harness executed 12 times: PASS 8, rail FAIL 2,
CANT-RUN 2 (`fill` timeout, `signInWithPassword`); the other 343 runs skipped it (`no-triggering-paths`).
All 8 PASS precede `5cb37d0775` (#9270, the first commit that adds
`CONVERSATION_ACTIVITY_EVENT` and a turn-start status write); both runs since FAIL (`36777205959` at
`5cb37d0775`, `37307395675` at `0b35762459`). Local runs on 2026-09-30 failed 3/3 on a *pre*-#9270 build
(`d4dc020e57`), so a host-class effect also exists (#8022 comment).

**Hypotheses (none confirmed).** H-A, out-of-order refetch overwrite: `fetchConversations` in
`hooks/use-conversations.ts` has no request sequencing (`setConversations(enriched)` is last-response-wins),
and #9270 added a debounced activity refetch that can run concurrently with the created-event retry chain, so
a stale snapshot can land after the fresh one. H-B, bounded retry exhausted: the created-event retry spans
about 9.6 s (`BACKOFF_MS`) from `session_started`, but the row commits lazily after Send. H-C, slow list RPC
on the runner. For H-A: correlation with #9270 and the code shape; against: n=2 and the pre-#9270 local fails.

**Plan for PR-3 (diagnosis first, per the blind-surface rule).** Extend the FAIL detail in
`apps/web-platform/scripts/live-verify/run.ts` with discriminating fields in ONE event: rail anchor count,
`list_conversations_enriched` request count and per-request durations after Send, send-to-row-commit latency,
`session_started`-to-Send gap, and whether the realtime INSERT arrived. A product fix (a monotonic sequence
guard in `fetchConversations`) follows only if H-A is confirmed, with a RED vitest that resolves two fetches
out of order. Do not "fix" blind.

## Open Code-Review Overlap

Queried 200 open `code-review` issues against the PR-1 files and the PR-2/PR-3 files. PR-1 files
(`cron-egress-firewall.test.sh`, `workspaces-luks-verify-workflow.test.sh`,
`reap-archive-persistence.test.sh`, `grep-q-pipe-guard.test.sh`): **None.** PR-2/PR-3 files:
`app/fonts.ts` matches #3564 (acknowledge at PR-2 plan time; different concern, a Core Web Vitals
backlog); `otp-login.e2e.ts`, `live-verify/run.ts`, `hooks/use-conversations.ts`: None.

## Files to Edit (PR-1)

- `apps/web-platform/infra/cron-egress-firewall.test.sh` (33 here-string rewrites; ~35 changed lines)
- `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` (stub drain, 1 rewrite, race rows,
  floor; ~60 lines)
- `plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh` (11 rewrites; ~30 lines)
- `.claude/hooks/grep-q-pipe-guard.test.sh` (`FILES_7376` pass, count pin, runtime control; ~55 lines)
- `scripts/lib/test-affected-paths.sh` only if `bash scripts/test-affected-derive.test.sh` fails after the
  guard edit. Consumer of that list: `scripts/test-all.sh --affected`, which reads the
  `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` block so the guard runs when a pinned suite
  changes; the block currently names `FILES_8664` and `FILES_7024` members and not the three new files.
  Regenerate per that suite's message rather than hand-editing.

## Files to Create (PR-1)

- `knowledge-base/project/plans/2026-10-05-fix-ci-flakes-pipefail-early-exit-consumers-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-ci-flakes-queue-slowness-9482/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-ci-flakes-queue-slowness-9482/decision-challenges.md` (Taste
  items from plan review).
- Learning: EXTEND `learnings/test-failures/2026-09-25-the-flake-was-sigpipe-at-4kib-…` with the
  producer-side variant (a stub that never reads stdin behind a `printf |`), the `echo` EPIPE log evidence and
  the ignored-SIGPIPE rc, via `soleur:compound`, rather than a new file.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. A mis-converted assertion could let a
  real regression in the egress firewall, the LUKS verify alarm or the worktree reaper ship green; the
  user-visible effect would arrive later as the underlying regression, not from this change.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector. Test-only edits;
  no secret, credential or runtime path is added or read (the luks stub handles a literal fixture token
  `dp.ct.fixture`).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`, because the diff changes only how
  three test suites read pipe status and ships no runtime code.

`threshold: none, reason: test-only edits to CI suites and a drift guard; no shipped runtime path, schema or
user data is touched, although the paths sit under apps/web-platform/infra and .claude/hooks.`

## Observability

```yaml
liveness_signal:
  what: the guard suite's per-pass PASS lines plus the registered-runner per-suite RED excerpt (#7376 diagnostics)
  cadence: per CI run (Infra Validation deploy-script-tests legs, test-scripts shards, hooks suite)
  alert_target: red required check on the PR; ci/main-broken issue filed by main-health-monitor on main
  configured_in: .claude/hooks/grep-q-pipe-guard.test.sh and apps/web-platform/infra/run-registered-suites.sh
error_reporting:
  destination: GitHub Actions job result and the infra-suite-logs-N artifact (per-suite log, rc, elapsed)
  fail_loud: "FAIL: pipe-into-grep-q found in a file #7376 took to zero" with file:line, and RED <suite> in the runner
failure_modes:
  - mode: a pipe-fed early-exit grep is reintroduced in one of the three pinned suites
    detection: grep-q-zero-7376-pass fails with the offending line
    alert_route: required check red on the introducing PR
  - mode: the luks stub stops draining stdin
    detection: the delayed-producer race row reds with class unavailable and a non-zero probe rc
    alert_route: Infra Validation deploy-script-tests leg red
  - mode: a pinned file is renamed or deleted so its pin matches nothing
    detection: the tracked-file and distinct-member-count pin fails
    alert_route: hooks suite red on the introducing PR
logs:
  where: GitHub Actions step logs and the infra-suite-logs-N / suite-timings-infra-N artifacts
  retention: GitHub artifact retention (default 90 days)
discoverability_test:
  command: bash .claude/hooks/grep-q-pipe-guard.test.sh
  expected_output: PASS: grep-q-zero-7376-pass
```

## Architecture Decision (ADR/C4)

No architectural decision is made or changed: no ownership or tenancy boundary, substrate, resolver or trust
boundary moves, and no existing ADR is reversed. ADR-270 stays `adopting` and is not edited. C4 impact: none;
checked all three model files for external actors, systems, containers and access relationships touched by a
test-only change (none are). The `c4-count-parity` counts are not moved because no monitor, workflow or
heartbeat count changes.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: infrastructure and tooling change. (PR-2 changes production typography
and must run the Product/UX and brand gates at its own plan time.)

## Guard Contract

### Guard 1 — named-file pipe-into-early-exit-grep pin (`FILES_7376`)

**Property.** None of the three suites contains a pipe feeding a `grep` that can stop at its first match, and
the pin cannot go silent.

**Assembly.** The population is every line of the three named files matching the guard's own `PATTERN` or
`PATTERN_AWK_EXIT` after comment lines are stripped: `apps/web-platform/infra/cron-egress-firewall.test.sh`,
`apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`,
`plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh`. The scan is by pattern over whole
files (not a list of today's sites), so a site added later at any line is a member. The chokepoint is the
`FILES_7376` array plus a dedicated scan function (PATTERN + PATTERN_AWK_EXIT, not `scan_scorers`); the tracked-file check and the distinct-count pin protect the array
itself. Not covered, by design and named in the guard header: multi-line pipes, `| head`, wrappers, and files
outside the array (growth is by naming a file, #9217).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `echo "$X" \| grep -q p` to `cron-egress-firewall.test.sh` | RED naming the file and line |
| 2 | Re-add `git -C d log -3 \| grep -q p` to `reap-archive-persistence.test.sh` | RED |
| 3 | Re-add `printf x \| grep -qE p` to `workspaces-luks-verify-workflow.test.sh` | RED |
| 4 | Dispatch: empty the `FILES_7376` array, or point one entry at a renamed path | RED (tracked-file and member-count pin) |
| 5 | Second member after a compliant first: a probe fixture whose last line is a bad site after compliant ones | RED (scan covers every line, not the first) |

**Harness rows.** One edit to the SUITE: delete the runtime SIGPIPE control and the guard must go RED on a
missing-control check, not pass. Rows 1-3 and 5 run as checked-in probe fixtures through the dedicated scan
function (the guard resolves repo-relative paths via `git grep`, so a scratch copy would yield no hits and read
green); row 4 runs with `</dev/null` so an emptied array cannot make `grep` read stdin. Must-PASS input that is not the canonical: a
here-string site, an `a || grep -q p <<<"$x"` site (already in the probe's good fixtures) and a
capture-then-here-string line must stay clean, so a guard that rejects everything cannot pass.

**Anchor.** The pin stores no hash or count of sites, only a member count of the named files. A weakening
(drop a file and lower the count) lands in the same diff as the guard, so this proves consistency, not
integrity; that is the accepted limit of every `FILES_*` pass in this file, backstopped by review and by the
`git ls-files --error-unmatch` check.

### Guard 2 — luks stub drains stdin (race row with positive control)

**Property.** The pipeline `printf … | ${WEB_HOST_SSH} …` in the reassert body cannot report a non-zero pipe
status because the stub always consumes its stdin to EOF, regardless of how the producer is scheduled and
whether SIGPIPE is default or ignored.

**Assembly.** Every arm of `sshstub` that can be the right-hand side of a pipe in the extracted reassert
body: the probe invocation (`printf | sshstub`), the host-key-failure early exit and the `tar xzf` arm (where
the `tar` stub writes nothing, so it is safe only by accident). The drain is hoisted to the top of the stub so
all arms are covered by one chokepoint. The race row drives the real extracted body, not a model.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the stdin drain from the stub | RED: row 1 reports `unavailable/unparsed` with a non-zero probe rc |
| 2 | Dispatch: make the `slow_printf` rewrite match nothing | RED (the helper asserts the derived body differs from the original and the edit landed exactly once) |
| 3 | Delete one new race row | RED (`pass < WF_MIN_ASSERTIONS`; the floor is a lower bound only, so lowering it cannot be detected and is not claimed) |
| 4 | Run row 1 with SIGPIPE ignored (`trap '' PIPE`) | still passes (drain makes both environments safe); with the drain removed it goes RED, rc 1 |

**Harness rows.** Positive control on the same input: the delayed body with `FIXTURE_NO_DRAIN=1` must produce
`unavailable/unparsed` with a probe rc outside {0,3,127,255}, proving the environment can exhibit the race in
whichever SIGPIPE disposition it runs. Must-PASS non-canonical: row 1 itself is a delayed (non-canonical)
producer that must still classify `selftest`.

**Anchor.** The race row compares against the pristine body's class on the same fixture computed in the same
run (the `hk_mutant` technique), so no stored expectation can be edited in the same diff to weaken it.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Pull the failing test names from those completed runs and decide whether it is one flake or several." | Flake Dossier rows 1a/1b; PR-2 | mapped |
| 2 | "workspaces-luks-verify-workflow.test.sh ... the producer-side `alarm_selftest=true` fixture classified `unavailable` instead of `selftest`" | Dossier item 2; PR-1 step 3; Guard 2 | mapped |
| 3 | "cron-egress-firewall.test.sh: failed once on the push run for main commit 0b35762459" | Dossier item 3; PR-1 step 2; Guard 1 | mapped |
| 4 | "test-scripts (2/8) failed ... and lint-bot-statuses failed another (run 37212108914). Find out why." | Dossier items 4a, 4b; PR-1 step 1 | mapped |
| 5 | "live-verify ... check them first." | Dossier item 5; PR-3 | mapped |
| 6 | "Treat that as the leading hypothesis (shared scratch dirs, timing, resource contention) and test it, do not assume it." | `### The #7376 hypothesis, tested` | mapped |
| 7 | "A. For each flake, find the root cause by reproducing it ... or by reading the failing log" | Flake Dossier | mapped |
| 8 | "B. Fix the root cause. No blind retries, no widened timeouts as the fix, no deleting assertions." | PR-1 steps 1-3; non-goals | mapped |
| 9 | "C. Add a regression guard where it is cheap ... and make sure every new assertion can fail (mutation-check it)." | Guard Contract; Phase 3 | mapped |
| 10 | "D. Search existing trackers before filing anything; fold new evidence into #7376, #9167, #9170, #9190 and the live-verify trackers" | PR-1 step 5; Tracker fold list | mapped (#9190: no new evidence in these five flakes, no comment) |
| 11 | "Do not change merge-queue ruleset parameters in this PR" and "do not flip ADR-270 to accepted" | Overview; non-goals | mapped |
| 12 | "split by subsystem (e2e, infra suites, live-verify) if they do not share a root cause" | Overview; Follow-up PRs | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Guard 1 (`FILES_7376` pass) | "Add a regression guard where it is cheap" (ask 9) | asked |
| Guard 2 race rows | "make sure every new assertion can fail (mutation-check it)" (ask 9) | asked |
| Runtime SIGPIPE control in the guard | "make sure every new assertion can fail" (ask 9) | asked |
| Conversions in the three suites | "Fix the root cause" (ask 8) | asked |
| `scripts/lib/test-affected-paths.sh` regeneration | — | inferred — justification: the guard's affected-map block must list its named files or `--affected` runs skip the guard when a pinned suite changes |
| Learning file | — | inferred — justification: wg-every-session-error-must-produce-either (a rule or a learning) for the producer-side variant and the corrected threshold |
| PR-2 / PR-3 specs | "list the rest as explicit follow-ups tied to existing trackers" | asked |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform`, `plugins/soleur`, `.claude`, `scripts`, `knowledge-base`
- Planned files: 8 | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the root-count threshold fires only because one root cause is expressed in
  four directories (three test suites and the guard that pins them) plus plan artifacts. Splitting the guard
  from the fixes would leave either a red pin (guard without the fixes) or unprotected fixes (fixes without
  the guard). The real subsystem splits (e2e, live-verify) are already separate PRs.

## Implementation Phases

### Phase 0: measure RED before touching anything

- [ ] 0.1 Informational baseline on the unfixed tree: `for i in $(seq 1 24); do bash <reap suite> > "$S/b$i" 2>&1 & done; wait`
  and count suites with a `FAIL:` line (measured today: 3 of 24; 9 of 56 across runs). Reap only; the cron
  suite never reproduced locally (0 of 6,000), so no cron stress comparison is claimed.
- [ ] 0.2 Re-run the luks race demonstration (extract the `reassert` step with `python3 -c yaml`, delay the
  producer 0.4 s, run with the suite's stub) and record `unavailable unparsed` and the non-zero probe rc.
- [ ] 0.3 Write the new race rows and the guard's `FILES_7376` pass first (RED against the unfixed suites).

### Phase 1: fixes

- [ ] 1.1 `reap-archive-persistence.test.sh`: 11 sites, helpers first, one capture-then-here-string idiom.
- [ ] 1.2 `cron-egress-firewall.test.sh`: 33 sites rewritten mechanically; prove with the throwaway inverse diff.
- [ ] 1.3 `workspaces-luks-verify-workflow.test.sh`: stub drain, one rewrite, race rows, new exact floor.
- [ ] 1.4 FIRST update the guard header comment (the falsified 64 KiB statements, the most contributor-visible
  change), then the affected-paths edge block (expected to need regeneration, not conditional, whenever a
  pinned file is added; use the owning suite's message).

### Phase 2: mutation checks (each must go RED; paste the load-bearing three in the PR body)

- [ ] 2.1 Guard 1 rows 1-5 and Guard 2 rows 1-4 from the matrices above, one at a time (Guard 1 via checked-in
  probe fixtures, Guard 2 on the suite).
  Assert each mutation LANDED (`cmp` against the original, or a `grep -c` landing count) before reading its
  result; a sed that matches nothing reads as a green row.
- [ ] 2.2 Label any surviving mutant as "fixtures do not exercise it" or "equivalent, proved".

### Phase 3: verification

- [ ] 3.1 The three suites green serially (cron 308/0, reap 45/0, luks 313+k/0).
- [ ] 3.2 Informational: same stress recipe as 0.1 on the fixed tree for reap and luks (record counts); run the
  guard's runtime control 50 times under load.
- [ ] 3.3 `bash .claude/hooks/grep-q-pipe-guard.test.sh` green; `bash scripts/test-affected-derive.test.sh`
  green; `python3 scripts/lint-guard-contract.py` green on this plan.
- [ ] 3.4 Post the tracker comments (list below) and open the PR with `Ref #…` lines only.

### Tracker fold list (comments, no new issues)

| Issue | Evidence to add |
|---|---|
| #7376 | Items 2/3/4a root cause (SIGPIPE class, contention as trigger), the CI `echo: write error: Broken pipe` line, the 0.4 s producer-delay demo, loaded-vs-serial counts, suites fixed by this PR |
| #7432 | Item 2's premise ("cannot fire") is falsified; item 1 (`JOBS=1`) unchanged |
| #9217 | Threshold correction for the whole class (4 KiB chunks, multi-write producers, `git log` at 3 lines), the three newly pinned files; #7005 and #6601 get a one-line cross-link |
| #8785 | Two new occurrences (runs 37224723661, 37295454362), the sticky-5xx mechanism, the offline repro, escalate per its own criterion, PR-2 plan |
| #9167 | The string is mocked at `otp-login.e2e.ts:141`; both 64-red runs are the font failure |
| #9170 | New occurrence (run 37216842585) and the PR-2 fix direction |
| #8022 | The harness history table (8 PASS / 2 FAIL / 2 CANT-RUN), the #9270 boundary, the skipped-not-passed correction, PR-3 plan |
| #9482 | Observation only: PR 9477 entered the queue at 15:12 while its own PR-level run (same head) had failed `lint-bot-statuses`; not acted on |

## Acceptance Criteria

### Functional

- [ ] The three suites contain zero pipe-fed early-exit greps: `bash .claude/hooks/grep-q-pipe-guard.test.sh`
  exits 0 and prints `PASS: grep-q-zero-7376-pass`.
- [ ] Assertion counts are unchanged except for the new rows: cron 308 passed / 0 failed, reap 45 / 0, luks
  313 plus the new rows / 0, and `WF_MIN_ASSERTIONS` equals the new green count exactly.
- [ ] Applying the inverse transform (`grep -q… PAT <<<"$V"` back to `echo "$V" | grep -q… PAT`) to the new
  `cron-egress-firewall.test.sh` yields a file identical to the pre-change file (proves the conversion changed
  no pattern text).
- [ ] The luks race row classifies `selftest` against the draining stub with the producer delayed 0.4 s, and
  `unavailable/unparsed` (probe rc outside {0,3,127,255}) against the `FIXTURE_NO_DRAIN=1` control.
- [ ] Informational, recorded in the PR body and NOT a gate (the rates are probabilistic: 3/24 and 9/56 on the
  unfixed tree): reap-suite loaded runs before and after. The deterministic gates are the luks race rows, the
  guard and the mutation rows.

### Guard / quality gates

- [ ] Every Guard 1 and Guard 2 mutation row was executed and went RED (pasted in the PR body); any survivor
  is labelled.
- [ ] `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] No change under `infra/github/**`; ADR-270 file untouched (`git diff --stat` shows neither).
- [ ] PR body uses `Ref #7376`, `Ref #7432` and `Ref #9217` (no `Closes`; #7005 and #6601 are cross-linked in comments only).
- [ ] Tracker comments posted per the fold list; no new GitHub issue created.

## Test Scenarios

- Given the unfixed reap suite, when 24 copies run in parallel, then at least one reports `FAIL: G:` while
  the commit exists in `git log` (RED); after the fix, none do.
- Given the luks reassert body with a 0.4 s delayed producer, when the stub does not drain stdin, then the
  class is `unavailable`, reason `unparsed`, probe rc non-zero; when it drains, then the class is `selftest`.
- Given a 200 KB producer whose first line matches, when piped to `grep -q` under pipefail, then the status
  is non-zero (141, or 1 with SIGPIPE ignored); when read through a here-string or a captured variable, then it is 0 (guard control).
- Given a new `| grep -q` added to a pinned suite, then the guard reds naming the file and line.
- Browser/API verification: not applicable (no UI or external service); all checks are local shell.

## Risks and Sharp Edges

- Any new `mktemp` in a `*.test.sh` owes an owning EXIT trap placed BEFORE `source test-helpers.sh`
  (`lint-trap-tempfile-ownership` rule (c)); the new rows reuse the existing `$SCRATCH` and need none.
- The stub is a fake for `ssh`; the real contract it must replay is "reads stdin to EOF when the remote
  command does not", which is exactly what the drain adds. A stub that ignores stdin sits above the code under
  test.
- Run `npx markdownlint-cli2` on this plan and on `tasks.md` before the first commit (hard tabs and
  list-after-heading are the recurring violations).
- A here-string appends a trailing newline exactly as `echo` does; `printf '%s'` producers would differ, but
  every converted site is an `echo`. The inverse-transform AC covers it.
- Keep the `!` placement identical to the original `if ! … | grep -q` when converting to the capture idiom;
  under `set -u` an unset capture variable aborts the same way the old `echo "$V"` did.
- The luks floor is exact. Count the new rows by running the suite, then set the floor in the same edit.
- Do not "fix" item 3 by serialising the suite or widening anything: the CI log proves the mechanism, and the
  here-string form removes it at any `-P`.
- A plan whose `## User-Brand Impact` is empty fails deepen-plan Phase 4.6; this one is filled
  (`threshold: none`, scope-out stated).
- Running `next dev` for PR-2 experiments mutates `apps/web-platform/tsconfig.json` and drops untracked
  `apps/web-platform/AGENTS.md`/`CLAUDE.md`; revert them before committing (done for this branch).
- Known accepted gaps (not bugs, not touched): a 403 secondary rate limit is not retried, and a late run on a
  congested runner pool is not detected by the dispatcher.

## Success Metrics

Deterministic proof is the gate (luks race rows, the guard, mutation rows). As a monitor only: no `FAIL:` from
the three suites across the next 20 runs. Queue ejection rates will not visibly change until PR-2 lands, since
PR-1 removes 1 of the 5 observed ejections; the PR body says so.

## References

- Runs: 37295454362, 37224723661, 37216842585, 37293827216, 37212108914, 37296532619, 37307152949,
  37307395675, 37309168420, 36777205959, 36775406221.
- Trackers: #9482, #7376, #7432, #7005, #6601, #9217, #9460, #8785, #9167, #9170, #9190, #8022, #7969, #7215,
  #5634, #3564. Related PRs: #9270, #8848, #9213.
- Code: `.github/workflows/workspaces-luks-verify.yml:480-598`, `apps/web-platform/app/fonts.ts`,
  `apps/web-platform/e2e/otp-login.e2e.ts:127-177`, `apps/web-platform/hooks/use-conversations.ts`
  (`fetchConversations`, created-event retry), `apps/web-platform/scripts/live-verify/run.ts:736-760`.
