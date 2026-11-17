# Learning: a presence-grep pin proves the producer exists — the mutant picks the load-bearing line

## Problem

PR #12498 added the #12404 `EVENT_MSGS_JSON` + `jq join` concat to a second reader and
pinned it with T66h: grep the apply job block for the env line and the `jq -r 'join("\n")'`
call. The fix-round mutation tests showed the pin proved *presence*, not *behavior*:

- Deleting only the **append line** (`ALL_MSGS="${ALL_MSGS}"$'\n'"${more_msgs}"`) left
  `more_msgs` assigned-but-dead → the gate silently reverted to tip-only, and every row
  stayed green.
- Deleting `&& "$more_msgs" != "null"` from the same line — also green.

Three independent review seats (pattern-recognition, test-design, data-integrity) found
the same asymmetry: the **preflight** copy of the idiom had executed-span coverage
(T66d–g run the real body), while the apply-side copy had only shape greps — and the
shape greps skipped the one line whose deletion reverts the feature.

## Solution

Presence pins must be **mutant-derived**: enumerate the single-line deletions that revert
the behavior (not the ones that merely remove syntax), and make each red. The fix was one
extended `&&` chain — `grep -qE 'ALL_MSGS=.*more_msgs'` — closing both mutants without a
new assertion (floor arithmetic unchanged).

Sharper form: when an idiom is *duplicated inline* because the cheaper site cannot source
the shared lib (preflight has no `actions/checkout`), the coverage must be duplicated too —
the executed span on copy A proves nothing about copy B. Verify the drift-guard's coverage
of each copy **separately** before shipping "the same fix, pinned the same way."

## Session Errors

1. **Commit-scan block: env mutation + stage + commit in one call** — `export
   CLAUDE_PLUGIN_ROOT=…; git add …; git commit` was rejected ("the commit's own staging
   cannot be simulated safely … the shell's environment before it stages"). **Prevention:**
   when `CLAUDE_PLUGIN_ROOT` changed in the same command, run `git add` as its own call and
   `git commit` as a second call — the scan then reads the real index.
2. **Commit-scan block: `… | bash -n` reads script from stdin** — `awk … | bash -n` was
   rejected as an unresolvable repo context ("a shell reads its script from stdin
   (heredoc, here-string, redirect or pipe)"). **Prevention:** extract the `run:` body to a
   `mktemp` file and `bash -n <file>` — the repo context resolves from the worktree cwd.
3. **`gh issue create` requires `--milestone`** (repo filing hook) — retried with the
   milestone + the filing-exit label `meta/machinery`. **Prevention:** issue filings in this
   repo always carry `--milestone` plus an accepted filing classification.
4. **`delegation-verify.sh` invoked without a subcommand** → usage exit, read as
   unverifiable. **Prevention:** the verifier's contract is `delegation-verify.sh verify` —
   always pass the verb.
5. **Test-authoring bug: over-escaped grep literal** — `'join("\\n")'` (two backslashes)
   never matches the workflow's `join("\n")` (one). **Prevention:** grep the extracted block
   for the literal once by hand before writing the `'"'"'` sandwich; the T66h first run went
   red on exactly this.

## Verified

- `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` → 129/129 with the
  extended T66h; the append-line mutant now reds (fix-round seat re-verified).

See: `knowledge-base/project/plans/2026-11-09-fix-kill-switch-ack-destroy-coalesced-blind-spot-plan.md`,
PR #12498, issue #12403 / #12501.
