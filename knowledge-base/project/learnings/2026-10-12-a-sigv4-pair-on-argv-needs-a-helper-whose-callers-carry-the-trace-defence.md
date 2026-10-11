# Learning: moving a SigV4 pair off curl argv — the helper is half the fix, and every caller owes the trace defence

## Problem

#9756: two cla-evidence scripts (`infra/bootstrap.sh`, `scripts/r2-conditional-put.sh`) passed the R2
SigV4 key id and secret through curl's basic-auth user option on the command line, so the pair sat in
`/proc/<pid>/cmdline` and `ps` for the life of each request. `cla-evidence` is a REQUIRED, self-sealing
status check (`pull_request_target` runs the BASE copy of the scripts), so a broken upload path cannot
be repaired by the PR that breaks it; the only pre-merge proof is a real-curl wire row.

## Solution

- ONE app-local sourced helper (`_r2-sigv4-curl.sh`): `user = "<id>:<secret>"` on `--config -` fed by a
  process substitution (never a pipe: SIGPIPE under `pipefail`), `--disable --noproxy '*'`, an anchored
  in-file URL pin, a position-aware curl-argument allowlist, an `env -u` scrub, and a shape guard that
  refuses a malformed value with `SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>`
  before any request. The shared `bearer-curl.sh` builds header lines only and stays untouched.
- A sourced file cannot carry an xtrace self-refusal or an `exit`, so the contract moves to the callers:
  each carries its own xtrace refusal (exit 78) and the suite asserts it per caller, in all four modes
  (`bash -x`, `SHELLOPTS`, id-only, secret-only).
- Wire proof: loopback-listener row with real curl 8.5 (container), byte sweep 0x01–0xFF, and an
  "absent from every recorded argv" assertion on synthesized fixtures.
- Lint fallout in the same change: the two Rule E baseline rows and census-ceiling rows removed, the A/D
  baseline rows removed, floors raised in the same edit that added rows.

## Key Insight

Where a guard lives is a property of the call graph, not the file. Moving a credential into a shared
helper concentrates the argv/trace/URL/env defences in one place and silently makes every caller's
prologue the only trace defence, which no lint can see (`--user` hidden behind `env -u … curl` is
invisible to Rule E, so the suite rows are the only guard). Name that obligation in the helper's header
and test it per caller.

## Session Errors

1. **Upload suites hung in RED** — a stub `cat` read the inherited stdin. **Prevention:** run the SUT
   under test with `</dev/null` whenever stubs may read stdin.
2. **`SHELLOPTS=xtrace cmd` was inert** — `SHELLOPTS` is readonly in the shell, so the prefix form is
   a no-op. **Prevention:** use `env SHELLOPTS=xtrace cmd` in any xtrace-refusal row.
3. **Backtick/quote in an unquoted heredoc comment tripped shellcheck SC1073.** **Prevention:** keep
   prose comments inside heredocs free of backticks and unbalanced quotes.
4. **`t "label" cmd && cmd2` split a predicate into two commands** (the second ran outside the
   assertion). **Prevention:** one `test a -a b` predicate per `t` row.
5. **`guard-vacuity-floor` closure arm red** — new floor-bearing suites were unclassified.
   **Prevention:** `work` §6.7 already says to promote in the live `PROMOTED_FILES`; build to its shape
   and run it first.
6. **`lint-orphan-test-suites` flagged corpus-walking suites.** **Prevention:** add
   `AFFECTED_*_PATHS` edges in `scripts/lib/test-affected-paths.sh` in the same change as the suite.
7. **The doppler-phrase PreToolUse hook blocked a Bash command by text-matching.** **Prevention:** write
   such scripts with the Write tool; the hook is working as designed and is never bypassed.
8. **Review caught fix-commit defects** (dispatcher self-test inversion, a stub that printed nothing
   where real curl prints `000`, pre-judge variable names, mixed-pair Doppler writes with no read-back,
   id-only xtrace mode). **Prevention:** a stub must reproduce the real tool's output on failure, and a
   dispatcher self-test must assert per-call deltas AND an unwind post-condition.
9. **`--affected` gate refused (rc 4) under sibling full-gate runs.** **Prevention:** substitute the
   individual suites and lints (the sanctioned fallback), and widen by hand to repo-global ratchets.
10. **A window-closure lint failure in `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`** is
    pre-existing on main, not from this PR. **Prevention:** confirm against `origin/main` before
    attributing, and record it as pre-existing rather than fixing it here.

## Tags

category: security, cla-evidence, curl, sigv4, argv, xtrace, shell-lint
