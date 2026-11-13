---
title: 'A log-marker gate matched the echoed workflow source, and a signal trap inherited the interrupted write''s redirect'
date: 2026-11-13
category: engineering
tags: [sentry, credential-rotation, github-actions, bash, traps, runbooks, review]
module: scripts
component: rotate-sentry-actions-ro-token
problem_type: logic_error
resolution_type: code_fix
severity: high
issues: ['#12736', '#12740', '#8090']
---

# A log-marker gate matched the echoed workflow source, and a signal trap inherited the interrupted write's redirect

## Problem

PR #12736 extended `scripts/rotate-sentry-actions-ro-token.sh` with `--profile iac` (three
stores: GitHub repo secret, Doppler `soleur/prd`, Doppler `soleur/prd_terraform`) and wrote a
runbook "prove, then revoke" gate. Three defects survived the plan, the TDD suite and a 12-row
mutation battery, and were found only by the review panel and its fix round:

1. **The prove gate could never be satisfied, twice over.** Version 1 said "the terraform-drift
   Sentry leg log shows no Sentry 401/403" — the plan output never reaches the log, so the check
   passed on a bad token. Version 2 (the review fix) blocked on bare strings
   (`sentry_iac_token_absent`, `the fidelity probe could not complete`,
   `missing required secret`). GitHub prints each step's `run:` script into the job log under its
   `##[group]Run` header, and those strings live in `echo "::error::…"` lines of that script — so
   they matched on EVERY run, green ones included. Three fix-round seats measured it on real logs.
2. **The partial-state report on SIGTERM went to /dev/null.** A trap handler runs inside the
   redirections of the command it interrupted. The Doppler write is
   `… >/dev/null 2>&1`, so a report printed to fd 2 from the handler was discarded and the
   script exited 143 silently — the operator would see nothing during exactly the window the
   report exists for. The new test row (I15) caught it; an isolated repro confirmed it.
3. **The GitHub store's "listed by name" check proved nothing.** The secret name exists before
   every rotation, so `gh secret list` showing it is true whether or not the write landed (the
   pre-existing ro path still has this shape; ro is proven downstream by the sweeper dispatch).

## Solution

- Gate on what a run EMITS, never on bare strings: errors only in their rendered `##[error]…`
  form, and require a POSITIVE line (`sentry_alert live fidelity: PASS (all …`,
  `divergence(s) between live Sentry`, `No drift detected in web-platform/sentry`,
  `Drift detected in web-platform/sentry`). Strings built from an unexpanded variable
  (`$STACK_NAME`) are safe; literals echoed by `::error::` lines are not. Both commands were run
  read-only against the newest completed runs before merge and print only the positive line.
- `exec 9>&2` at startup; the signal handler and the three-list report write to fd 9. Close fd 9
  for children that may daemonize (`agent-browser … 9>&-`).
- Prove the GitHub write by `updatedAt` changing (read before and after, retried for eventual
  consistency), with `-R github.com/jikig-ai/soleur` pinning repo AND host.

## Key Insight

A check whose oracle is "this text is (not) in the log" must be run against a GREEN log and a RED
log before it is written into a runbook. GitHub echoes the workflow source into the log it
produces, so any marker that is also a source literal is present unconditionally. And any output
emitted from a signal handler inherits the interrupted command's file descriptors — keep a
private dup of stderr for it.

## Session Errors

1. **The brief's "existing test" did not exist** (planning). Recovery: the plan created the suite,
   characterising `ro` first against the unchanged script. **Prevention:** grep for a named test
   before planning to extend it (the plan did).
2. **The brief's premise about postmerge issue reads was stale** (they already used the RO→RW
   ladder). Recovery: CTO ruling kept RO-first and fixed the actual stale pointers.
   **Prevention:** existing premise-validation step caught it.
3. **The plan write was blocked by the IaC write guard.** Recovery: terraform-architect review +
   acknowledgement. **Prevention:** none needed (guard worked).
4. **`technical-ruling-gate.sh` failed the first decision table** (class/ruling shape).
   Recovery: rewrote rows. **Prevention:** none needed (gate worked).
5. **`SHELLOPTS=xtrace bash …` as a prefix assignment failed in the test's own shell** (SHELLOPTS
   is readonly), so the script never ran and three assertions failed for the wrong reason.
   Recovery: `env SHELLOPTS=xtrace bash …`. **Prevention:** set a readonly special var for a
   child via `env`, never a prefix assignment.
6. **The exact assertion count was miscounted three times.** Recovery: set it from the observed
   count after confirming every row ran. **Prevention:** derive the count from a green run and
   compare against a hand tally; a mismatch is a finding either way.
7. **`check … || show` never fired** (`check` always returns 0). Recovery: `check_exit` helper.
   **Prevention:** a diagnostic attached to a helper's exit status needs the helper to return one.
8. **The Bash hook blocked an edit whose command text contained the Doppler store subcommand.**
   Recovery: write the edit script to a file (or use Edit), run it by path. **Prevention:** keep
   that literal out of Bash command text (already documented in the plan's Sharp Edges).
9. **The `--only-names` stub read the config from `$4` instead of `$5`.** Recovery: recount argv.
   **Prevention:** stubs that refuse an unexpected argv surfaced it immediately.
10. **The signal-handler report was written to a /dev/null redirect** (Problem 2). Recovery:
    fd-9 dup. **Prevention:** routed bullet in
    `plugins/soleur/skills/work/references/work-test-harness-sharp-edges.md`.
11. **The first prove gate searched the log for text the workflow never prints** (Problem 1).
    Recovery: exit-code-line markers. **Prevention:** run every log-marker gate against a real
    green and a real red log before writing it down.
12. **The review fix for (11) matched the echoed workflow source** — the fix reintroduced the
    class. Recovery: `##[error]` form + positive markers, measured on real logs. **Prevention:**
    routed bullet in `plugins/soleur/skills/review/references/wfs.md`.
13. **Two inherited claims nearly shipped:** "Doppler branch configs are independent copies"
    (from the plan; an in-repo learning says branches inherit the root unless overridden), and an
    ADR sentence attributing "the CI checkbox grants `org:ci`" to an audit that does not say it.
    Recovery: post-store digest classification instead of the assumption; ADR sentence reworded
    to what the gate enforces. **Prevention:** existing rule — name the falsifying command for
    every causal claim the diff adds (compound Phase 0.5 inherited-framing bullet).
14. **"Listed by name" proved nothing** (Problem 3). Recovery: `updatedAt` before/after.
    **Prevention:** for any "did the write land" check, ask whether the observed state already
    held before the write.
15. **Tooling catches:** a shellcheck file-wide disable placed after the first command
    (ineffective), a lint-shell-capture-exit S4 on a predicate tail, markdownlint MD038 on a code
    span ending in a space. Recovery: each fixed. **Prevention:** the tools worked.
