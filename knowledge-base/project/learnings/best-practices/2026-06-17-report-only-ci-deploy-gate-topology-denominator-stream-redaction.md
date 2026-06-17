---
title: "Report-only CI deploy-gate: report-only by topology, one queryable event per run, redact the stream not just the tail"
date: 2026-06-17
category: best-practices
module: ci-workflows
issue: 5487
tags: [github-actions, dark-launch, deploy-gate, observability, redaction, live-verify, report-only]
---

# Learning: designing a report-only CI deploy-gate that a future blocking-flip can trust

## Problem

Re-homing the live-verify harness into `web-platform-release.yml` as a
**report-only** post-deploy gate (#5487, the substrate the #5463 report-only→
blocking flip is gated on) surfaced three design requirements that are easy to
get subtly wrong and that a multi-agent review reliably catches.

## Solution / Key Insights

Three load-bearing properties for a report-only CI deploy-gate that will later be
flipped to blocking:

1. **Report-only by TOPOLOGY, not just `continue-on-error`.** Put the gate in a
   SEPARATE job that NO other job lists in its `needs:`. Then a job-level failure
   can never block or roll back the deploy — by construction, independent of any
   step flag. Keep `continue-on-error: true` on the harness step too (so the
   observability-emit step still runs), but topology is the stronger guarantee:
   either alone is removable; both together are robust. Order "after the deploy
   health-verify" via `needs: [deploy]`, not by nesting a step in the deploy job
   (which would couple a browser-driving verifier to the deploy job's
   runner/concurrency and perturb the system under test).

2. **Emit EXACTLY ONE queryable observability event per run — including the
   skip/can't-run cases.** A future blocking-flip is gated on observing "≥1 real
   green PASS." For that soak to have a *denominator*, "ran and intentionally
   SKIPPED" must be distinguishable from "never ran." So emit a real Sentry event
   (not a breadcrumb — breadcrumbs aren't queryable via the events API) on every
   path: PASS/FAIL, SKIPPED (level=info), and each CANT-RUN class
   (setup-failed / gate-diff-failed / no-result-line) with the exit code embedded.
   Use `if: always()` on the emit step and a fail-closed branch order
   (setup-failed → gate-diff-failed → SKIPPED → no-result-line → PASS/FAIL/CANT-RUN).

3. **Redact the harness STREAM before `tee`, not just the extracted tail.** A raw
   `harness 2>&1 | tee log.out` writes unredacted stderr (an unhandled
   Playwright/bun/CLI stack that could embed a captured secret) verbatim into the
   GitHub Actions run log — visible to any Actions-read principal — even if you
   later scrub the *extracted* tail before forwarding to Sentry. Pipe the merged
   stream through the redaction shim BEFORE `tee`
   (`harness 2>&1 | redact-stdin | tee log.out`) so the run log is scrubbed too.
   `PIPESTATUS[0]` still captures the harness's exit (first pipe stage). And the
   redaction module must cover EVERY token class the job's env carries — a
   Supabase-session-only redactor missed Doppler (`dp.st.*`) and GitHub
   (`ghp_`/`github_pat_`) tokens that `doppler run`/`gh api` could surface
   (security-sentinel P2 + user-impact FINDING 3, both caught at review).

## Session Errors

1. **Workflow-job `Edit` failed on an indentation/em-dash `old_string` mismatch
   (assumed 12-space indent, file used 10).** Recovery: `Read` the exact bytes
   (or `tail -3 | cat -A`) and copy verbatim. **Prevention:** always re-read the
   precise anchor bytes before a workflow/YAML Edit; never assume indentation.
2. **`tsc` failed — `Bun` global is not in the app's tsconfig types.** Recovery:
   read stdin via node's `process.stdin` async-iteration instead of
   `Bun.stdin.stream()`, mirroring run.ts's avoidance of Bun-typed globals.
   **Prevention:** in `apps/web-platform/scripts/*.ts` run by bun, use node APIs
   (`process.stdin`/`process.stdout`), not the `Bun` global, so they typecheck.
3. **An AC self-check grep (`LIVE_VERIFY_BROWSER_(CHANNEL|PATH)`) false-matched
   the COMMENT prose, not an env assignment.** Recovery: reworded the comment to
   not contain the literal the AC greps. **Prevention:** known class (#4864) —
   anchor AC greps on the real construct (`<var>:` env-assignment form), and
   don't put a grepped literal in nearby prose.
4. **A `redact.test.ts` Edit targeted the wrong worktree path (#5485 instead of
   #5487).** Recovery: re-issued with the correct worktree-absolute path.
   **Prevention:** with sibling worktrees open, copy the worktree-absolute path
   from the active branch, not a prior one.
5. **Bash CWD drift in a multi-`cd` validation batch** (cd into app, then `cd ..`,
   then `cd app` again) broke actionlint + a sim. Recovery: re-ran with an
   absolute `cd` per command. **Prevention:** one absolute `cd <abs> && <cmd>`
   per Bash call; the tool does not persist CWD reliably across compound `cd`s.
