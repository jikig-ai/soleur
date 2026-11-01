# Learning: a "surface is non-empty" check was satisfied by the error message it should have caught

## Problem

PR #11624 (#9543, ADR-311) is a measurement spike: a real-bubblewrap test records whether a credential-broker mechanism (`mask`, a virtual host, `tlsTerminate`) keeps a decoy secret out of the sandbox, and the ADR chooses a mechanism from those outcomes. Two review rounds found the same defect class four times, each time inside the fix for the one before:

1. The first suite concluded `does-not-work` from absence (the destination did not receive the real value) without proving the premises that make absence meaningful: the sandbox bash completed, the env showed the variable, and a request reached the destination.
2. The fix added premises for the env surface only. A test-design mutant (misspell the echo header name in the harness) left the suite green, because the control arm's `leaks` verdict came from the env scan, not from the echo target. A harness that could not read a delivered secret would have recorded `does-not-work` for every arm.
3. The fix for that required `proc-environ` and `cwd-files` to be non-empty. The verification seat found `/proc` is not mounted in the sandbox: the section held `cat: /proc/self/environ: No such file or directory`, so "non-empty" passed on an error line and the measurements record said "the probe now also reads `/proc/self/environ`", which was false.
4. Prose carried the same shape: ADR-311 said the cc-dispatcher guard is "boot-time" (it is raised per session construction), that ADR-309 "rejects" Option E (it defers it), and issue comments repeated both before the seat that checked them returned.

## Solution

- Tie each negative conclusion to a positive observation made by the same harness: the control arm must show its echo target recorded the real value, and `does-not-work` needs the destination to have received the sentinel the sandbox env held. Anything else is `unmeasurable`.
- Count a surface as scanned only if its content could contain the secret: the floor requires the cwd-files surface non-empty and does not count `proc-environ`. The record states `/proc` was never read.
- A real value at a host outside the allowed set is checked before any `unmeasurable` gate, because it reads only the harness-side log.
- Every surviving mutant is listed in the record (sentinel tie, outside-host check) rather than implied away.
- Prose claims about code were corrected only after a command falsified them (`grep -n readCcMcpAllowlist`, `sed -n` on the call site, `grep "Option E"` in ADR-309); the posted issue comments were edited in place.

## Key Insight

A "not empty" assertion is evidence about bytes, not about the surface it names: an error message is non-empty. For a measurement that concludes from absence, the premise to prove is an observation that only the working path can produce (the secret appears in the control's echo log; `SECRET_VAR=` appears in the section), never the container's size. The cheapest way to find the gap is a mutant that breaks the instrument itself (misspell the header, replace a probe line with `true`, point a read at a path that does not exist) and a check that the suite goes red.

## Session Errors

1. **CTO's first scope ruling rested on a false premise** (`github_push_branch` and `ExecutionGrants` exist only in the legacy runner; entitled sessions run in `cc-dispatcher.ts`) — Recovery: corrected the premise and re-ruled — **Prevention:** when briefing a ruling agent on "X exists", give it the `git grep` that shows where X is wired and which runner executes the affected sessions.
2. **First spike suite passed three mutants that should have failed, and concluded from absence** — Recovery: test-design seat's P1s; outcome floor, premise checks, scan-first ordering — **Prevention:** run the instrument-breaking mutants (empty arm loop, secret not exported, env blanked) before the first review, not after.
3. **The fix for the non-empty surfaces was itself vacuous** (`/proc` absent in the sandbox) — Recovery: verification seat; floor narrowed to cwd-files, record corrected — **Prevention:** after adding a "non-empty" check, point the read at a nonexistent path and confirm the suite fails.
4. **ADR and issue-comment prose stated three unverified facts about code** (boot-time throw, ADR-309 "rejects" Option E, "records the same-uid residual" wording) — Recovery: architecture seat's falsifying commands; ADR reworded, issue comments edited with `gh issue comment --edit-last` — **Prevention:** run the falsifying `grep`/`sed` for each causal sentence before writing it into an ADR or posting it to an issue.
5. **Plan sentence replace silently did not match** (python `replace` without an anchor assertion) — Recovery: re-read the line and re-ran with an `assert s.count(old) == 1` — **Prevention:** every scripted prose edit asserts its anchor count first.
6. **`cd plugins/soleur` failed from inside `apps/web-platform`** and the following `bun test` ran from the wrong directory — Recovery: re-ran from the plugin directory — **Prevention:** use absolute paths in a subshell for cross-tree commands.
7. **A Bash command touching the Claude Code memory directory was blocked** by `hr-never-write-to-claude-code-memory-claude` — Recovery: dropped the command — **Prevention:** none needed; the hook worked.
8. **The affected-test gate was launched on a pre-fix tree and queued behind other sessions** — Recovery: treated as stale; CI is the merge backstop — **Prevention:** launch the gate only after the last fix commit.

## Tags

category: test-failures
module: apps/web-platform/test/broker-mechanism-spike.test.ts
