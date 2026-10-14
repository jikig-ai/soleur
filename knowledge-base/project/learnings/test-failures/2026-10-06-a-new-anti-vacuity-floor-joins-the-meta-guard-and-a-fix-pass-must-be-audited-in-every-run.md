# Learning: a new anti-vacuity floor joins the vacuity meta-guard, and a hardening pass's own tests must audit every run, not three fixtures

## Problem

Review of the credential-hardening PR (#9632) found its new tests satisfiable by the very defects they were written to catch, and the fixes
for that found a second layer. Two shapes recurred.

## Root cause

- **Fixtures sampled, never walked.** The transport audit ran on three hand-picked runs and judged calls by a deny-list of two flags
  (`--disable`-first, `--noproxy '*'`); a bare curl in an untested branch, `-k`, `--location-trusted` and `--proxy` all survived, and the
  bearer's stdin config was only checked for a prefix, so a second `url =` directive in it survived too.
- **A hand-rolled floor is not free.** Adding a `MIN_CASES` floor to an infra suite makes it a member of `scripts/guard-vacuity-floor.test.sh`'s
  derived population, which then demands (a) the multi-line `if` / literal-bound shape, (b) the `[FATAL] accounting identity` sentinel and
  `if [[ $((PASS + FAIL)) -ne "$CASES" ]]` form so ARM 10 sees it, (c) the case counter moved by a wrapper, never inside the helper that moves
  PASS or FAIL (ARM 10d), and (d) a `PROMOTED_FILES` entry in the LIVE definition (the file assigns it four times and only the last is read).
- A fail-open in the new audit itself: `read -r a b < <(awk ...)` leaves both empty when awk errors, which read as "no bad calls".

## Solution

Audit every run inside `run_guard`; judge each call against a golden argv per class and a golden stdin per class (a POST's stdin is exactly one
bearer line, everything else is empty, the IMDS exemption keys on the exact URL); make the audit fail closed on non-numeric output and on a
stdin-versus-argv call-count mismatch; split `_pass`/`_fail` (verdicts) from `assert` (CASES) and add an instrument self-test that drives the
wrapper on a false and a true condition. Copy the shape of `cron-egress-ghcr-probe.test.sh`, then run the meta-guard.

## Key insight

The vacuity meta-guard is a contract for any suite that grows a floor: build the floor to its shape on day one, because retrofitting it costs two
review rounds. And a deny-list of two flags audits what you thought of; an allowlist of the whole argv audits what the call IS.

## Session Errors

- **A sibling PR changed the lint under this one mid-flight** (Rule E, #9594, merged while this PR was open; the NIC guard sat in its baseline).
  Recovery: merged `origin/main`, converted the bearer to a stdin config, removed the baseline entry. **Prevention:** the review skill's
  merge-tree probe before the panel already catches the conflict; read `git log HEAD..origin/main -- <touched files>` for sibling lint changes too.
- **The first commit hung in the pre-commit hook** and was killed by the tool timeout, leaving files staged and nothing committed. Recovery: re-ran
  the commit detached with an rc log. **Prevention:** run any commit that fires the bun-test hook detached and read `COMMIT_RC` (the work skill already
  says so; I used the inline form first).
- **A hook refused a whole compound command** because it contained `git stash list`, so the edits in it never ran. **Prevention:** keep hook-denied
  words out of compound commands; the denial aborts everything.
- **`gh issue create` was denied three times** (a `$VAR` in `--body-file`, no consequence label, no `Mandated-By`). **Prevention:** literal absolute
  `--body-file`, `Mandated-By:` on its own line for deferral filings, and no other command in the call.
- **A mutation matrix ran against a RED control** (the probe suite needs `apps/web-platform/Dockerfile`, absent in the sandbox). Recovery: caught by
  reading the control line, discarded the rows, re-ran. **Prevention:** the control line is read before any row (already a work-skill rule).
- **A review seat ran `git checkout --detach` on the shared worktree** despite a report-only brief. Recovery: re-attached the branch, verified the SHA.
  **Prevention:** check `git branch --show-current` after the panel returns.
- **Docs I wrote carried unmeasured claims**: "31 of 31 RED" against a 29-row matrix, and "tracked as #9639" for items the issue did not contain.
  Recovery: code-quality seat caught both; matrix re-derived, items added to the issue. **Prevention:** run the falsifying command for each count and each
  tracker reference before writing it.
- **A Python edit asserted a one-occurrence anchor that occurs five times** (`#!/usr/bin/env bash` appears in every stub heredoc); the assert held the
  file untouched. **Prevention:** anchor on the first occurrence explicitly when a literal repeats.

## Tags

category: test-failures
module: infra-tests, guard-vacuity-floor
