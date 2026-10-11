# Learning: pinning a sole-copy volume — the required-check anchor must not be a subset of the advisory guard

## Problem

#9879 pinned the live Inngest LUKS volume (`delete_protection` + `prevent_destroy`) and its
passphrase pair. Two review rounds plus a verification pass still found defects, and almost every
one sat in a FIX commit or in a guard written to catch the previous round's escape:

- The only guard that could read the attribute lines (Guard 1) was **not a required check**, and the
  required-check twin (G2e in the parity test) pinned a strict subset of Guard 1's predicates. One diff
  could add `ignore_changes = [delete_protection]` or `count = 0` and merge green.
- Brace counting differed between three lexers (shared awk lib, Guard 1's `blk_scan`, G2e). A `# {`
  in a trailing comment or a fake `lifecycle { prevent_destroy = true }` inside a heredoc satisfied
  Guard 1 while G2e (a different lexer) caught it. Neither spelling had a regression row.
- A per-merge HALT list that covered only the web-class passphrase let a **create** of the inngest
  passphrase score a clean plan.
- A read-back one-liner with `doppler run --only-secrets X` exits before running when `X` is absent, so
  its `missing-token` word was unreachable; a stub `doppler` in the test hid it.
- Route B (restore the Doppler key from state) piped `terraform state pull | jq -j | doppler secrets set`
  with no `pipefail` and no length check: a missing attribute prints the literal `null` and overwrites the
  live key with a wrong opener.
- CI-only signals the targeted suites could not see: `lint-trap-tempfile-ownership` (a literal
  `/var/tmp` mktemp base in a NEW suite), the collision-gate probe rule (`gh ... list` without `--limit`
  in new skill prose), and CodeQL `js/incomplete-sanitization` (`a.replace(/\./g, "\\.")` before building a
  RegExp).

## Solution

- G2e now rejects `ignore_changes`, depth-0 `count/for_each/provider/provisioner` and counts braces on a
  code-only view; `G2E_PINS` is asserted equal to `SOLE_COPY_ADDRS` and the census literal. Sunset marker: fold
  into Guard 1 when it becomes required (#9927).
- One lexer change (code-only brace counting, heredoc-blanked scans) shared by Guard 1 and web-1's Guard B4,
  with a regression row on each side.
- The jq create-halt now includes `random_password.inngest_redis_luks`; a create of the Doppler copy alone
  stays legal (the legitimate recovery).
- Route B is fail-closed: value captured under `pipefail`, must match `^[A-Za-z0-9]{40}$`, written only from a
  pipe, verified by sha256 comparison without printing; read-back words are distinct (`volume-gone` for 404).
- Address literals interpolated into a RegExp go through one full-metacharacter escape helper.

## Key Insight

When the guard that can see the property is advisory, the required-check anchor is only as strong as the
predicate set you copy into it — copy the predicates that REOPEN the property (`ignore_changes`, meta-arguments,
heredoc/comment lexing), not just the ones that assert it, and tie its address set to the others by an
assertion. And every guard written in a fix round is itself a fix commit: re-drive the previous escape against
it AND run the repo-global ratchets (trap-tempfile, probe `--limit`, CodeQL) that a file-selected suite
structurally cannot reach.

## Session Errors

1. **A fix agent ended its turn with an interim status line and no edits (Guard-2 seat; structural seat).** —
   Recovery: resumed via SendMessage with "no further tool calls, write the report now". — **Prevention:** a
   seat prompt must say "your final message is the deliverable; a status line is not one", and the lead checks for
   the report file before treating a notification as completion.
2. **`guard-vacuity-floor` failed while the new suite was untracked ("no-longer-floor-bearing").** — Recovery:
   committed the suite (the gate derives its population from tracked files). — **Prevention:** commit a new
   promoted suite before running the ratchet that reads `git ls-files`.
3. **Read-only Phase 0 plan failed twice** (`--only-secrets` combined with a tf-var transformer; github provider
   PEM error). — Recovery: dropped the transformer on the outer run and excluded 22 `github_*` targets,
   documented as a deviation in `apply-plan-output.md`. — **Prevention:** none beyond the recorded deviation.
4. **`fixture-relative-assert` +1 site from a variable name reused for a command result.** — Recovery: renamed.
   — **Prevention:** the ratchet already reports it; do not bind one name to both a path and a command result.
5. **Local affected gate sat behind another worktree's lock, then a detached rerun ran while I was still editing
   the tree and in an environment where `python3` could not import `yaml`.** — Recovery: killed own run with
   `proc.sh kill_mine`, rerouted to CI. — **Prevention:** start the gate only after the last edit of a batch;
   never `pgrep -f` (hook blocks it) — `source proc.sh; kill_mine`.
6. **Commit a23839637f is titled `docs` but carries the `.tf` pins.** — Recovery: stated in the PR record. —
   **Prevention:** `git diff --cached --stat` before committing a docs batch.
7. **Three repo-global ratchets reddened only in the broad gate / CI** (trap-tempfile literal base, probe
   `--limit`, CodeQL escape), each in code written during a fix round. — Recovery: fixed and re-pushed. —
   **Prevention:** after a fix round that adds a test file or skill prose, run the three cheap ratchets
   (`lint-trap-tempfile-ownership.test.sh`, `components.test.ts`, a regex-escape grep for `.replace(/\\./g`).
8. **The `/var/tmp/rv9879-*` seat reports disappeared mid-session.** — Recovery: findings were already
   synthesised in-conversation. — **Prevention:** keep review reports under the worktree (uncommitted) or the
   scratchpad, not `/var/tmp`, which the orphan reaper sweeps.
9. **Stop-hook "unkept promise" blocks on closing text that named a next action.** — Recovery: did the action
   or declared a `<stop>` tag. — **Prevention:** when waiting on background agents, end with the `<stop>BLOCKED:`
   form rather than a first-person future.

## Tags
category: infrastructure-guards
module: apps/web-platform/infra, plugins/soleur/test/terraform-target-parity.test.ts
