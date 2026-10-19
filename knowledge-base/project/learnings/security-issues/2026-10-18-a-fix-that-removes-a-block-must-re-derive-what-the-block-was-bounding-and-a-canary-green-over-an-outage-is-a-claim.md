---
module: System
date: 2026-10-18
problem_type: security_issue
component: tooling
symptoms:
  - "Every hosted Bash call failed with `apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted`, no alert fired"
  - "Faithful sandbox canary stayed green and /health stayed ok for the whole outage"
  - "Fix-round security seat read a sibling tenant's proxy credential out of a persisted Bash output file and replayed it (502, not 407)"
root_cause: config_error
resolution_type: code_fix
severity: critical
tags: [sandbox, seccomp, bwrap, canary, tenant-isolation, af-unix, followthrough, notify-only]
synced_to: []
---

# Learning: removing a protective helper re-opens whatever it bounded, and a green canary over an outage is a claim

## Problem

Issue #10445: from the first production deploy of `web-v0.324.3` (2026-10-06, inferred onset) every hosted agent Bash call failed. The SDK wraps each Bash command in an embedded `apply-seccomp` helper whose first call is `unshare(CLONE_NEWUSER)`; our bwrap-shim seccomp filter (#9595) denies exactly that. The faithful canary replays the setup argv only (ends `-- true`), so it never ran the wrapper and reported green. The tool_result classifier returned null for the helper line, so nothing paged.

## Solution

`network.allowAllUnixSockets: true` makes the vendored builder skip the helper (CTO-ruled; a CLONE_NEWUSER exception in a seccomp filter cannot key on the caller). Detection: classifier maps the exact whole line to `helper_userns_eperm`; a Better Stack alert pages on it. Proof: real-SDK control/treatment tests plus a two-session socket test and a docker run-tuple suite.

## Key Insight

1. **Removing a protective helper re-opens what it bounded.** The helper WAS the per-command AF_UNIX block. Setting the knob fixed Bash and silently made every sibling tenant's bridge socket, peer-messaging socket and transcript reachable. The first panel found two of those channels (masks added); the fix-round security seat found a third that no `denyRead` can close: the CLI persists each Bash command's output (a sibling's `env`, with its per-session proxy credential) under `<tmpdir>/claude-<uid>`, and the vendored builder binds that whole per-uid dir WRITABLE into every sandbox, re-binding it after the deny tmpfs. The fix is structural, not a mask: a per-tenant `CLAUDE_CODE_TMPDIR` under a denied root. Ask of any "skip the wrapper" fix: what did the wrapper bound, and which of those channels can a mask NOT express?
2. **A green canary over an outage is a claim, not evidence.** A readback that exits 0 on "canary green" would have closed its own tracker while the real proof (a hosted Bash call) was never made. A follow-through whose close verb is not the real proof must be NOTIFY-ONLY (exit 2/3/5, never 0/1) and its suite must assert that on every row.
3. **The deploy frame is shared.** `/hooks/deploy-status` `.tag`/`.exit_code`/`.component` is one frame every component's deploy overwrites, and `sandbox_canary` is a separate durable ledger holding the previous deploy's verdict. A readback needs both paths: frame-based when the frame is the component's own deploy, ledger-based (checked after the PR merged) when another component overwrote it, or it sits at NOT YET forever.
4. **A stub that ignores argv cannot pin argv.** The first readback suite passed 12/12 with the compare range swapped, the `web-` prefix dropped and the sanitizer removed. The `gh` stub now answers only the exact expected argv.

## Session Errors

1. **A vacuity-guard floor written in an unrecognised shape.** `ROWS=$((PASSES + ${#FAILURES[@]}))` then `if (( ROWS < 21 ))` made `guard-vacuity-floor` count the suite as an unconstructible mutant (ratchet 15 -> 16); array-length floors also die unbound in the mutant. Recovery: scalar `FAIL_N` counter, floor inline. Prevention: use a scalar failure counter and put the `-lt` floor directly on `PASSES + FAIL_N`; run `guard-vacuity-floor.test.sh` after adding any new `*.test.sh` floor.
2. **Cleanup `rm -rf` of a mktemp dir inside a compound command was blocked by the safety check.** Recovery: left the scratch dir. Prevention: do not chain a cleanup `rm` onto a mutation run; leave unique-named scratch dirs or remove in a separate simple call.
3. **`env -u VAR` placed after other assignments ran `env` with the assignment as a command (rc 127), then a stub's `$1`-only matching.** Recovery: put `-u` options first / run through a second `env`. Prevention: when a test helper needs to unset one variable, test the helper with a known-positive row before relying on it.
4. **Tools denied by hooks: `git stash` hook-blocked, `sleep N;` chained polling blocked.** Recovery: inspected with `git show` and used the notification path. Prevention: already hook-enforced; no change.
5. **A seat's finding was almost lost because the first gate run happened late.** The pending readback P1 (deploy in flight) was found only by a seat, not by the author's 12 rows. Prevention: for any probe that reads a shared status frame, enumerate who else writes that frame before writing fixtures.

## Prevention

- When a fix flips a knob that makes an SDK/vendor stop wrapping or bounding something, enumerate the channel set the wrapper bounded and write one two-session arm per channel with a CONTROL arm that must see the leak.
- A follow-through whose success exit is not the real resolution proof is notify-only.
- Pin external-CLI argv in stubs (exact match), assert the sanitizer by removing it.

## Cross-references

- PIR `knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md`; ADR-075 addendum 2026-10-16; ADR-079; ADR-218 amendment.
- Issues #10445, #10453, #10454, #10455, #10456, #10457; PR #10451.
