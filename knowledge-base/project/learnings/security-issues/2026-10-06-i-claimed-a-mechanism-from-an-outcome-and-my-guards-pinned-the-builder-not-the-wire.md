# Learning: I claimed a mechanism from an outcome, and my guards pinned the builder, not the wire

## Problem

W1 of the agent-security epic (#9601, PR #9599) withholds the owner's Anthropic key from sandboxed Bash with the SDK's `sandbox.credentials` deny. The first implementation was green on its unit test, an argv test and a hand measurement. Two review rounds (11 + 10 seats, then a verification seat) found the class repeating at every level of the change:

1. **The guards' windows were narrower than the property.** The unit test read `buildAgentSandboxConfig`; the property lives in what the two production call sites hand `query()`. Replacing the builder's `credentials` with an empty list after the fact left every guard green. The injected-set derivation was hand-sampled (two option shapes), so a transformed, option-gated or production-only copy of the credential was invisible. No guard listed the places a CLI session can be started, so a new `query()` with no sandbox would have passed.
2. **I measured an outcome and wrote it up as a mechanism.** A `/proc` probe printed counts (6 pids, 0 decoys) and had no positive control; I wrote "the PID namespace is the barrier, not `denyRead`" into the ADR and two code comments. Two seats' hand-built bubblewrap repros disagreed with each other and with me. Re-measured through the real SDK with a control arm (deny off: the decoy is found in two readable `environ` files; deny on: none), only the OUTCOME held. The mechanism was never established.
3. **I wrote the prose defect I was reviewing for.** The prompt directive's last sentence ("ask for a project's key as you would any project secret") re-opened the failure it existed to stop; four seats flagged it. The ADR said the SDK "strips unknown keys" (inferred from types) and counted a dark-launch gate as a detector; both were unmeasured or false.

## Solution

- Pin the wire at BOTH ends: drive the options builder across every combination of the inputs production varies (32 cases, plus "adds no env key"), assert the sandbox each call site hands the SDK (legacy: the object `query()` receives; dispatcher: identity with the builder's output), and add a census of every module that can start a session.
- Derive the injected set by value flow AND fence the source: the credential value may appear in exactly the two auth assignments (a parser-stripped line allowlist), which covers the shapes value flow cannot see.
- Measure behaviour in CI with a control arm (`sandbox-credential-deny-runtime.test.ts`: real SDK, real bubblewrap, a decoy key). Claim the outcome; leave the mechanism unclaimed unless an ablation arm (one flag removed) isolates it.
- Measure the failure mode of the control itself. Four malformed variants of the `credentials` block (renamed key, renamed `envVars`, wrong type, unknown mode) were each accepted silently with the key still present, so "sessions start normally" is not an acceptance criterion and the argv/behaviour tests are the only detectors.
- Pin security prompt text verbatim, not by substring, and put it in every builder that runs under the control (three Concierge branches plus the legacy runner).

## Key Insight

A control that fails open silently can only be accepted on a behaviour probe that has shown it can see the thing, and a guard on the code that BUILDS a value is not a guard on the value that REACHES the consumer. Before writing "X is the reason", ask which arm removed X: a two-arm control/treatment measurement proves an outcome, and only a third (ablation) arm proves a cause.

## Session Errors

1. **Filing gate refused `gh issue create` three times (forwarded from the earlier phase).** Recovery: read the gate source for the vocabulary file and the measured `Fix-Size`. Prevention: #9604 tracks making the refusal text name the vocabulary.
2. **Background-agent claims refuted by one read (forwarded).** Recovery: read the code. Prevention: treat a seat's claim about code as a lead and re-derive its operands.
3. **Edited the repo while a gate was running (forwarded).** Recovery: killed the run and relaunched on a clean tree. Prevention: hold edits until every seat and gate has returned; this session did so for both review rounds.
4. **A `/proc` probe with no positive control, turned into a mechanism claim.** Recovery: re-ran with a control arm and rewrote the ADR, measurements and comments as an outcome. Prevention: every probe prints a known-positive arm in the same run; a causal sentence needs an ablation arm. Review already documents the positive-control rule; the new part is outcome-vs-mechanism.
5. **My new `doCapture`-options test asserted something false (a 1 ms abort is not observable on a normal capture) and its mutation row scored a false kill.** Recovery: the unmutated control was red, which voided the row; measured the real abort behaviour against a never-answering stand-in and re-proved the row. Prevention: read the control line before any mutation row; a control that is red for the test under mutation means the row is not a kill.
6. **A parser-based comment stripper made the sentinel test time out when run over every file in `server/`, `lib/` and `app/`.** Recovery: raw-text prefilter before stripping (sound, because stripping only removes text). Prevention: when swapping a regex helper for a parser, run it over the whole corpus once for timing.
7. **Prose I added was false or unmeasured** ("both prompt builders carry it" with three branches, "a CI runner" before one had run, a dark-launch gate counted as a detector, a grep summary that omitted hits). Recovery: caught by seats and the verification pass, fixed. Prevention: for each causal or universal sentence a diff adds, name the command that falsifies it and run it before committing.
8. **Skipped the review skill's anti-slop scanner step in the first panel pass** (the diff touched `apps/web-platform/server/*.ts`). Recovery: read the reference and ran it in the fix round (0 findings). Prevention: after the classification gate, grep the skill for conditional hooks keyed on the diff's path set before spawning.
9. **A review seat ran `git checkout --detach` on the shared worktree** despite report-only. Recovery: the seat restored the branch; verified `HEAD` before editing. Prevention: re-check `git branch --show-current` after every panel returns (already in the review skill's sharp edges).
10. **A first ambient-env scrub was a list of variable names and was incomplete.** Recovery: prefix-based scrub in a shared helper. Prevention: scrub by the prefixes the program reads, not by the names you remember.

## Tags

category: security-issues
module: agent-sandbox, agent-runner, claude-agent-sdk
