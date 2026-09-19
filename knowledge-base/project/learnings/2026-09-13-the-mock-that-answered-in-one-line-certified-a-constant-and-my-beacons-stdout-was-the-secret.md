---
title: "The mock that answered in one line certified a constant — and the beacon I added inside `$(read_secret)` would have become the secret"
category: test-failures
tags: [inngest, cutover, doppler, credentials, bash, mutation-testing, test-fixtures, observability, better-stack, sentry, review]
module: apps/web-platform/infra/inngest-rearm-reminders.sh, apps/web-platform/infra/inngest-wiped-volume-verify.sh
issue: 8054
pr: 8135
date: 2026-09-13
symptom: "The first `op=execute` to clear 2.0 after #8056 died at 2.1 with `INNGEST_MANUAL_TRIGGER_SECRET unavailable (env + doppler both empty)`; the fix's own diagnostics logged a constant notice for every failure class, and a 36-assertion suite plus three author-run mutations were green."
root_cause: "Two webhook host scripts read Doppler with the unit's token revoked 2026-07-30 (#7095 re-pointed ci-deploy.sh and four units, not these); the fix's verification was written against a one-line mock doppler and a three-file guard, so the head-vs-cause line, the wiped copy's scrub, the `export`, and a beacon writing stdout inside the secret's own capture were all invisible to it."
---

# The mock that answered in one line certified a constant

## Problem

After #8056 shipped, the AC19 dispatch of `cutover-inngest.yml op=execute` cleared 2.0 for the first
time and died one step later: `2.1 capture returned HTTP 500: ERROR: INNGEST_MANUAL_TRIGGER_SECRET
unavailable (env + doppler both empty)`. Better Stack showed the webhook executing
`inngest-rearm-reminders.sh` and its own FATAL. The secret was present in Doppler. The credential the
read ran on was not: `webhook.service` exports the `/etc/default/webhook-deploy` `DOPPLER_TOKEN`
revoked 2026-07-30T11:19:30Z; #7095 re-delivered a fresh one at `/etc/default/soleur-doppler-token`
and re-pointed `ci-deploy.sh` (parsed block) and four units (drop-ins) — the two other webhook
scripts that call `doppler` were never re-pointed, and `2>/dev/null || true` discarded the 401.

The fix was small (a parsed re-read, byte-identical in both files). The review found **41
findings, 1 P1, 5 P2**, and — as with #8054 — every one lived in the verification and the
diagnostics, none in the parse.

## Solution

1. **`soleur_refresh_doppler_token()`** — ci-deploy's parse shape (`IFS='=' read -r … || [[ -n "$k" ]]`,
   never sourced, empty skipped, later-wins), four keys (the token plus the three baked Sentry DSN
   components the same file carries), `SOLEUR_CRED_FILE_STATE` = present|unreadable|absent.
2. **`soleur_doppler_read_class()` + `soleur_log_doppler_read_failure()`** — a closed class enum
   (`invalid_auth | secret_not_found | transport | empty_value | binary_absent | other`) derived from
   the WHOLE stderr, the `Doppler Error:` line (else the last line) with ANSI/control bytes stripped in
   the C locale and `dp\.[a-z]{2,}\.` scrubbed, capped at 160 bytes; emitted as the
   `SOLEUR_DEPLOY_CRED_FAIL` marker Better Stack already keys on, mirrored to stderr so the hook's
   response body (which the run log prints) carries it, plus a Sentry event with the destination
   pinned by shape. **Nothing in it writes stdout** — see Key Insight.
3. **Guard §I derives the consumer set** from `hooks.json.tmpl`'s `execute-command` list (plus
   `ci-deploy.sh` behind its wrapper), requires exactly three readers today, and requires each to
   carry the byte-identical function or ci-deploy's block. A fourth doppler-reading hook script
   reddens it (mutation M16). ADR-159 gained a dated addendum recording the consumer inventory by
   mechanism and the decision against a `webhook.service` drop-in.

## Key Insight

**A mock's output shape is a claim about production, and it is the claim no mutation can test.** The
mock doppler printed `Doppler Error: Invalid Auth token` as one line, so `head -n 1` of stderr was the
cause. The real CLI, under the unit's `DOPPLER_CONFIG_DIR`/`DOPPLER_ENABLE_VERSION_CHECK` env, prints
two `Using … from the environment` notices, then the constant `Unable to fetch secrets`, then the
coloured cause LAST — so the "reason" the PR promised for Better Stack was `Using DOPPLER_CONFIG_DIR
from the environment…` for a revoked token, a network fault and a missing secret alike. Every
mutation of the SUT was scored through that mock; three review agents found it because each ran the
real binary once. `ci-deploy.sh`'s own `_cred_err_tail` says "the TAIL and not the head, because a CLI
error puts its cause at the end" — the discipline existed one file over.

**Everything that runs inside `$(f)` shares f's stdout with f's RETURN VALUE.** `SECRET="$(read_secret)"`
means the Sentry beacon added to the failure path — a `curl -s -o /dev/null` — runs inside the capture
that IS the secret. Real curl prints nothing there; the mock printed `202`, the script proceeded with
`SECRET=202`, and four "fails closed" assertions went red. A mock that is *less* faithful than
production caught a hazard production would have hidden until the day someone added `-w`. Rule: a
function whose stdout is a value may call nothing that can write stdout; say so in the comment.

## Prevention

- **Fixture the producer's real shape before pinning a parser on it.** For any CLI/API the code
  reads, capture one real failure response (with a deliberately wrong credential, in an environment
  matching the unit's) and make the mock emit THAT. A one-line mock cannot fail a head-vs-tail bug.
- **Derive a guard's population from the system's own registry** (`hooks.json.tmpl`, a unit list, a
  FILE_MAP), never from a hand-typed file list — the third consumer the #7095 sweep missed is the
  reason §I exists.
- **`grep -q` behind a pipe under `pipefail` is a false-negative generator on long inputs**: `-q`
  exits on the first match, the upstream writer takes SIGPIPE, and the `if` reads false. Use
  `grep … >/dev/null`. Measured: §I missed `ci-deploy.sh` (4,000 lines) and counted 2 readers of 3.
- **Run the P1a/P1b ratchets and `lint-shell-capture-exit` on every new `*.test.sh` before its
  first commit** — six unguarded `"$MOCKBIN/…"` writes reddened the ratchet on this branch one day
  after the same class was recorded on #8056.
- **Review-agent prompts must forbid live credentialed probes.** An agent testing doppler's stderr
  ran `DOPPLER_TOKEN= doppler secrets get <prd secret>`; the EMPTY token fell through to the
  operator's local login and the live value landed in the agent's transcript. Probe with a
  deliberately INVALID token (`DOPPLER_TOKEN=dp.st.invalid`), never an empty one, and never against a
  real secret name.
- **The ci-deploy destination-pin lint follows `${VAR}` / `$VAR` / one derivation hop**, not
  `"${VAR:-}"` — bind a local (`dom="${SENTRY_INGEST_DOMAIN:-}"`) and pin the local.

## Session Errors

1. **The session scratchpad under `/tmp` was swept overnight**, so a Monitor that waited ten hours
   for a launch window then launched the battery into a redirect whose directory no longer existed —
   silently, while the Monitor kept waiting for an rc file that could never appear. Recovery: logs
   under `$(git rev-parse --git-dir)/…`. **Prevention:** any log a Monitor or detached process writes
   for longer than a turn goes under the worktree gitdir, never `/tmp` (the #7828 learning already
   says so; this is the Monitor-shaped instance).
2. **`actions/runs?head_sha=<9-char sha>` returns `total_count:0`**, and "0 pending of 0" read as
   `ALL_RUNS_COMPLETE`. Recovery: full SHA + a `total_count >= N` guard before any verdict.
   **Prevention:** a poll over a set must assert the set is non-empty before reporting it drained.
3. **Two launch races lost to sibling worktrees (rc 4)** and two capacity Monitors timed out at
   their iteration caps. Recovery: one persistent Monitor that waits, launches, and retries on rc 4.
   **Prevention:** the wait-launch-retry loop is the shape; a probe-then-launch in two tool calls
   loses the race by construction.
4. **The soak-followthrough gate fired on the plan's negations** ("not applicable … nothing here
   is soak-gated"). Recovery: override marker with a one-line justification. **Prevention:** recorded
   as the negated-vocabulary false-positive shape on #7800 beside the PIR gate's.
5. **`gh issue create` was refused four times** (milestone; body-file path outside the gate's
   view; no User-Impact/Fix-Size; then "30 lines / 2 files → fix inline"). The gate was right at each
   step; the friction was reaching the fourth verdict by trial. **Prevention:** compute Fix-Size FIRST
   — under 100/4 there is no issue to file.
6. **The Bash tool's 600 s cap cannot host a 50-minute battery**; the first attempt had to be
   stopped and relaunched via `setsid nohup`. **Prevention:** anything longer than the cap is
   detached with its rc written to a file, and a Monitor reads the file.
7. **The Write tool refused a `.git/worktrees/…` path** (it resolves under the main checkout).
   Recovery: scratchpad, recreated after the sweep. **Prevention:** heredoc via Bash for gitdir paths.
8. **The new suite was committed with six P1b ratchet rows RED** — the targeted suites ran, the
   ratchet did not; `#8056`'s learning recorded the same miss the day before. Recovery:
   `assert_fixture_dir` as a statement in every writing window; 62/62 without `--write-baseline`.
   **Prevention:** the `/work` Phase 0.5 §6.5 bullet now names the ratchets explicitly for new
   `*.test.sh` files.
9. **`grep -q` behind a pipe under `pipefail`** made §I miss `ci-deploy.sh`. Recovery:
   `grep >/dev/null`. **Prevention:** review defect-class bullet.
10. **The Sentry beacon's stdout ran inside `$(read_secret)`** and became the secret in the mock
    run. Recovery: `>/dev/null 2>&1` on the curl, invariant named in the comment. **Prevention:**
    constitution Never; the mock's unfaithfulness is what surfaced it — keep at least one mock that is
    *chattier* than production.
11. **The mock doppler's one-line stderr certified `head -n 1` as the cause**; three suites and
    three mutations green. Recovery: real four-line coloured shape in the mock; class enum from the
    whole stderr. **Prevention:** capture the real failure response before writing the parser.
12. **Two inherited sentences were false**: "#7095 re-pointed infra-config-apply.sh" (it delivers
    the file; zero doppler calls) and "every op=execute since the revocation failed here" (two of
    three died at 2.0). Recovery: both corrected in the scripts, test header, ADR addendum and PR body.
    **Prevention:** for every causal sentence the diff adds, run the command that falsifies it
    (`git log -S'doppler secrets' -- infra-config-apply.sh`; `gh run list --workflow …`).
13. **A review agent leaked the live prd secret into its own transcript** by probing with an empty
    `DOPPLER_TOKEN`. Recovery: disclosed to the operator; rotation is the operator's decision.
    **Prevention:** review spawn prompts forbid live credentialed probes; probe with an INVALID token.
14. **`run-registered-suites.sh --help` started the full runner** (no `--help` flag) and was cut by
    `head`. Recovery: `list_runs` showed nothing lingering. **Prevention:** read a runner's argv
    handling before passing it a flag.
15. **A Python batch edit aborted on its own over-strict sanity check** after writing the scripts
    and before the suite. Recovery: re-ran the suite half. **Prevention:** assert anchors before
    writing anything, or write all-or-nothing.
16. **A test seam was misnamed** (`INNGEST_CAPTURE_FILE` for `INNGEST_CUTOVER_CAPTURE_FILE`), making
    three pre-fix-should-pass cases red for the wrong reason. **Prevention:** grep the SUT for the
    seam name before using it.
17. **The destination pin was written as `"${VAR:-}" =~ …`**, which the trace-credential lint's
    pin regex does not recognise. Recovery: a one-hop local. **Prevention:** in the learning above.
18. **`MIN_ASSERTIONS=34` against 36 measured** let a whole section vanish green. Recovery: exact
    count. **Prevention:** the review skill already says exact-count; apply it when writing, not
    after review.
