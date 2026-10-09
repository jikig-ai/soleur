# Learning: a revert-recipe dry run must run every gate the revert PR will face, and no openssl option reads an HMAC key from stdin

## Problem

PR #9805 (tracker #9799 items 2 and 3) decoupled the zot version claim from `ci-deploy.sh` (a
`deploy_pipeline_fix` trigger file) and took the peer fan-out HMAC key off argv. Two things
surprised us.

1. The tracker asked for the key to be fed "via stdin/fd". No such openssl option exists:
   `openssl dgst -help` offers only `-hmac val`, `-mac val`, `-macopt val` and `-sign`, and
   `openssl mac -help` only `-macopt val`. `-macopt hexkey:` is still argv.
2. The sidecar's wholesale-revert recipe (the rollback for the registry pin) was dry-run in a
   scratch worktree, found to conflict in three files, and documented as "keep the current side of
   every conflict; the staleness gate then exits 0". That was wrong for `ci-deploy.sh`: the
   conflict spans only the `curl` line, and the next hunk (`-H "X-Signature-256: sha256=${sig}"`)
   does not conflict, so the revert silently put the signature back on curl's argv. The dry run
   never saw it because it ran one gate (the staleness gate); the credential lint, which the
   revert PR also faces, would have failed with three violations at `ci-deploy.sh:375`.

## Solution

1. Use the repo's canonical keyed-HMAC snippet (python3 `hmac`, key in the child's environment via
   a per-command prefix, never exported): `sig=$(printf '%s' "$payload" | HMAC_KEY="$secret" python3 -I -c '...') || sig=""`,
   followed by a 64-hex shape guard that logs and `return 1`s. `/proc/<pid>/environ` is mode 0400
   (owner and root); `/proc/<pid>/cmdline` is world-readable. Byte-identity with the old
   `openssl dgst -hmac` form is asserted over an 11-secret x 3-command matrix.
2. Rewrite the revert recipe from the measured result: keep the CURRENT `ci-deploy.sh` wholesale
   (`git checkout HEAD -- <file>`), keep the CURRENT `ci-deploy.test.sh` and change only the claim
   tokens, take the sidecar's reverted side, restore the two Rule E baseline rows before
   committing, and state that the kill-switch markers defer (not drop) the web-host delivery.

## Key Insight

A rollback recipe is first executed during an incident, so its dry run is its only test. Judge the
dry run by every gate the resulting PR will face (lints included, not just the suite the change
was about), and enumerate the NON-conflicting hunks of the revert, not only the conflicts: a
conflict marks where git needed help, never where the revert is wrong. This is the review
skill's "a fix's own verification inherits the framing of the defect it removes", seen from the
recovery-documentation side.

Companion measurements from the same PR:

- A mutation sandbox for a suite that resolves paths outside its own directory (`../Dockerfile`)
  must be a detached git worktree, not a subtree copy; the unmutated control dies on a missing
  file and every row measures nothing.
- Six full `ci-deploy.test.sh` runs in parallel put the unmutated control itself 3-6 rows red
  (`7.x`/canary load flake). Attribute only the rows you mutated and run the control in the same
  batch.
- Every caller of `fan_out_to_peers` sits in an `if` condition, where errexit is off for the whole
  function, so the `|| sig=""` guard is defence for a future bare call. Pin it with a row that
  calls the function bare under `bash -euo pipefail`.

## Session Errors

1. **Planner shortcuts (forwarded):** the planning subagent did research inline and skipped the
   plan-review panel. **Prevention:** the 7-seat post-implementation panel and the fix-round
   covered the same lenses; no rule change.
2. **Subtree sandbox for `ci-deploy.test.sh` died on `../Dockerfile`.** **Prevention:** use a
   detached worktree (`git worktree add --detach`), already stated in review/SKILL.md; check the
   unmutated control before reading any row.
3. **Parallel full-suite mutation runs flaked on unrelated rows.** **Prevention:** compare only the
   mutated rows (T-9799-*) and run the control in the same batch.
4. **`pgrep -f` blocked by the self-match hook.** **Prevention:** none needed; the hook did its
   job. Use a captured PID or a rc/marker file.
5. **Turns ended on "I'll ..." while waiting on background work (stop hook x3).**
   **Prevention:** when blocked on a background task, arm a Monitor or state the block with a
   `<stop>BLOCKED: ...</stop>` tag instead of narrating the next action.
6. **Review trailer emitted with `--findings 0` ("review: no findings").** **Prevention:** pass the
   real triaged-finding count; the script is idempotent only per commit, so reset the (empty,
   unpushed) trailer commit and re-run.
7. **Revert recipe resolved hunk by hunk and verified by one gate.** **Prevention:** dry-run the
   recipe through every gate the revert PR runs (staleness gate AND credential lint) and list the
   revert's non-conflicting hunks.

## Tags
category: workflow-issues
module: apps/web-platform/infra
