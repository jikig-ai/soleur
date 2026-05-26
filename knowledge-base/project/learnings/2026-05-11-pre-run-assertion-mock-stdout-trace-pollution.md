---
title: Pre-run assertion mocks must not pollute stdout in trace mode
date: 2026-05-11
category: test-failures
tags: [ci-deploy, docker, bash-mocks, trace-tests, pre-run-assertion]
related-prs: ["#3601"]
related-issues: ["#2955"]
---

## Problem

Adding a `docker ps --filter "name=^soleur-web-platform$" --format '{{.Names}}' | grep -q .` pre-run assertion inside `apps/web-platform/infra/ci-deploy.sh` (ADR-027 single-replica invariant) immediately broke 5 unrelated trace-order tests in `ci-deploy.test.sh`:

```
FAIL: web-platform: prune runs before pull (prune_line=2 pull_line=3 exit=1)
FAIL: canary success: correct docker trace order
FAIL: production start failure after canary success
FAIL: happy path writes reason=ok
FAIL: production start failure writes reason=production_start_failed
```

The new test for the assertion itself passed; everything else regressed.

## Root cause

The unified docker mock at `apps/web-platform/infra/ci-deploy.test.sh` has multiple `MOCK_DOCKER_MODE` variants. The `trace` mode prints `DOCKER_TRACE:$1` to stdout for every invocation so trace-order tests can parse the sequence:

```bash
trace)
  echo "DOCKER_TRACE:$1"
  ...
```

When the new pre-run assertion called `docker ps ... | grep -q .`, the mock printed `DOCKER_TRACE:ps` to stdout. `grep -q .` matched the non-empty line, the assertion fired (false positive), and `final_write_state 1 "adr027_prod_already_running"` aborted the deploy mid-flow. The 5 trace tests that relied on `MOCK_DOCKER_MODE=trace` lost their post-assertion docker calls (`run`, `stop`, `rm`) because the script exited at the assertion point.

## Solution

Two coordinated edits in `apps/web-platform/infra/ci-deploy.test.sh`:

1. **Route the `ps` trace marker to stderr in `trace` mode**, and emit the container name on stdout only when explicitly armed:

   ```bash
   trace)
     if [[ "${1:-}" == "ps" ]]; then
       echo "DOCKER_TRACE:ps" >&2
       if [[ "${MOCK_DOCKER_PS_PROD_RUNNING:-}" == "1" ]]; then
         echo "soleur-web-platform"
       fi
       exit 0
     fi
     echo "DOCKER_TRACE:$1"
     ...
   ```

2. **Update the expected trace strings** in `assert_canary_trace_order` and `assert_prod_start_failure` to include `ps` between the prod `stop|rm` and the prod `run`:

   ```text
   image|pull|stop|rm|run|exec|stop|rm|ps|run|stop|rm
   ```

   (The test harness redirects stderr to stdout via `2>&1` before parsing, so the DOCKER_TRACE:ps marker still appears in the trace stream — it just doesn't appear on the unmerged stdout that the assertion's pipeline reads.)

After the fix: 67/67 ci-deploy tests pass + 5 vitest single-replica-assertion tests pass.

## Key insight

**When you add a precondition check inside a shell script that grep-parses its mock's stdout, every existing mock-mode variant must be audited for stdout-pollution from the new subcommand.** The check, by design, succeeds only when stdout is non-empty — but the test harness's mock was designed assuming every docker subcommand contributes one trace line to stdout. That contract collides with the assertion's contract. The cheapest fix is to split the mock's output channels: trace markers to stderr (for the harness's `2>&1` parser), real-looking output (or empty) to stdout (for the script's pipeline).

Generalizes to any new check that does `<tool> <args> | grep ...`, `<tool> <args> | wc -l`, etc., inside a script that also runs under a trace-emitting mock.

## Prevention

When adding a pre-run assertion of the shape `<tool> <subcommand> ... | grep -q ...` (or any pipeline that reads `<tool>`'s stdout) to a script that already has a trace-emitting test harness:

1. Grep the test file for every `MOCK_<TOOL>_MODE` variant.
2. For each variant whose default behavior prints a marker on stdout for **every** subcommand, add an early branch for the new subcommand that either:
   - Routes the trace marker to stderr (`echo "MARKER:$1" >&2`) and emits the real expected output on stdout, OR
   - Skips the trace marker entirely for that subcommand.
3. Identify every test that asserts on an ordered trace string and decide whether to include the new subcommand in the expected sequence (recommended — it documents the new step) or to exclude it (preserves backward compat at the cost of hiding the assertion's existence in test prose).

The general principle: **a mock's "trace channel" and a script's "data channel" must be separable, or every new dataflow check is a breaking change to the existing tests.**

## Session Errors

- **Bash CWD non-persistence between calls** — Recovery: chained `cd <abs-path> && <cmd>` per call. **Prevention:** already-enforced via `hr-the-bash-tool-runs-in-a-non-interactive`.
- **Vitest `MockInstance` typing for `process.exit` spy** — Initial generic type failed tsc. **Prevention:** import `MockInstance` from vitest and explicit-type spies on overloaded native methods.
- **Trace-mode docker mock stdout pollution** — primary subject of this learning. **Prevention:** see above.
- **git-history-analyzer false-positive on ADR Bucket A count** — Agent miscounted entries. **Prevention:** review skill's existing cross-artifact-verification rule already covers — pin exact line ranges when reporting counts.
- **Commit message arithmetic ("11 module-level Maps")** — Actually 10 module-level + 1 closure-scoped. **Prevention:** run `grep -c` once before stating counts; never count from memory.

## Route-to-Definition Proposal

Add to `plugins/soleur/skills/work/SKILL.md` Sharp Edges in the "Test environment setup" or "Infrastructure Validation" section:

> When adding a precondition pipeline (`<tool> <args> | grep ...`) inside an infra script that already has a trace-emitting test harness, audit every `MOCK_<TOOL>_MODE` variant for stdout pollution from the new subcommand before running the suite. Cheapest fix: route the trace marker to stderr for the new subcommand and update expected-trace strings to include it.

Placement: domain-scoped (only applies to scripts under `apps/*/infra/` with bash mock harnesses). NOT AGENTS.md material.
