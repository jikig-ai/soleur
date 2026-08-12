---
module: git-data-userdata / render-time comment strip
date: 2026-08-12
problem_type: logic_error
component: infra_terraform
symptoms:
  - "a one-character regex mutation collapsed the recovered bytes 30,524 -> 68 with every suite green"
  - "deleting the replace() wrapper reverted what a host boots from, on a ForceNew attribute, with every suite green"
  - "the byte cap could not backstop either mutation: the unstripped render is under the cap"
root_cause: guards_pinned_the_expression_not_the_effect
severity: high
tags: [mutation-testing, terraform, cloud-init, guard-design, non-vacuity, forcenew]
issue: 7264
pr: 7458
synced_to: [review]
---

# I proved the transform, and left its application and its size unpinned

## Problem

The change extends an existing render-time comment strip from git-data's injected
payloads to the cloud-init **template body** — one `replace()` around a
`templatefile()` call, plus a second strip local kept deliberately separate from the
payload one (ADR-152 forbids sharing them).

The transform itself was correct and was proven correct, independently, more than
once: `B.sub('', raw) == stripped` byte-for-byte, a deep YAML walk showing identical
structure, `bash -n` clean before and after. An eleven-agent panel confirmed it.

Two mutations then passed every gate.

**M1 — delete one character from the regex's character class**, in both mirrors so
parity still held. Recovered bytes fell from 30,524 to 68. Suites: 5/0, 15/0, 133/0,
71/0. Green.

**M2 — delete the `replace(...)` wrapper**, leaving the local declared, mirrored and
distinct. What a git-data host boots from reverts. `user_data` is ForceNew with no
`ignore_changes`, so this is not a cosmetic revert. Suites: green.

The byte cap cannot backstop either one. The fully unstripped render is **30,092 B**
against a 32,768 B cap — under it. The cap only ever fires for a payload that was
never at risk, so "the cap will catch it" was false for the exact mutations that
mattered.

## Root cause

Every guard pinned a property of the **expression**: that it is declared, that it is
mirrored across `main.tf` and the budget script, that it is distinct from the payload
expression, that stripping recovers `> 0` bytes.

Not one pinned a property of the **effect**:

- *how much* it strips (`> 0 bytes` is satisfied by a regex that strips one line)
- *whether the module calls it at all*

Those are the two things a reader assumes from "the strip is tested," and they were
the two things nothing asserted. The transform being provably correct is what made
this comfortable — the correctness proof is real, and it covers a function that
nothing was required to invoke.

## Solution

**Bound the magnitude, don't merely observe it.** Replace `saving > 0` with a ratio
the mutation cannot satisfy:

```bash
max_ratio=60                      # measured 54% today
str_pct=$(( str_bytes * 100 / raw_bytes ))
[ "$str_pct" -le "$max_ratio" ] || fail "strip recovered too little: ${str_pct}%"
```

A ratio survives the template growing; an absolute byte floor would have to be
re-tuned on every edit and would rot into a rubber stamp.

**Assert the call site, on comment-stripped text.** The wrap's opening *and* its
matching close, so a half-deleted wrapper cannot pass:

```bash
code="$(sed 's/^[[:space:]]*#.*$//' main.tf)"
grep -qF 'replace(templatefile(' <<<"$code" || fail "the render is not wrapped"
grep -qF 'local.git_data_template_rationale_strip, "")' <<<"$code" || fail "wrap not closed with the template local"
```

Comment-stripping the haystack first is not optional here: the file *documents* this
mechanism in prose directly above it, so a comment-blind grep passes on a module that
no longer applies anything (`cq-assert-anchor-not-bare-token`).

**Prove each guard by breaking what it guards, in both directions.** Every fix in
this PR was mutation-proven:

| battery | control | mutated | restored |
|---|---|---|---|
| bash suites | 15/0 | M1 14/1 · M2 13/2 · M3 14/1 | 15/0 |
| TS model | 39/0 | 37/2 | 39/0 |

The restore column is the half that gets skipped and is the half that catches a
"guard" that fails on everything.

## Key insight

**A test that a transform is correct and a test that the transform runs are different
tests, and the first one reads like both.** When a change is *an application of* a
proven function — a wrapper, a decorator, a middleware, a hook registration — the
correctness proof migrates attention away from the call site, which is the only part
the change actually introduced.

The generalizable pair, for any guard over a size, a saving, a count, or a ratio:

- **Magnitude:** would a mutation that makes the effect *nearly* vanish still pass?
  `> 0` almost always answers yes. Bound it against the measured value.
- **Application:** would deleting the call site — not the definition — fail anything?
  If the only assertions name the definition, the answer is no.

And a corollary about backstops: **check the backstop's range before relying on it.**
"The byte cap protects us" was stated in the plan and was false, because the
unprotected value sits inside the cap. A backstop that cannot fire for the failure
you are reasoning about is not a backstop.

## Prevention

- When a diff's payload is *applying* an existing transform, write the call-site
  assertion **first** — before the parity, mirror and distinctness arms, which are
  the easy ones and which crowd out the hard one.
- Grep the haystack comment-stripped whenever the file explains the mechanism it
  implements. Self-documenting modules make comment-blind anchors fail open.
- Before citing a cap, floor, or quota as a safety net, compute the unprotected value
  and check it is actually outside the net.

## Session Errors

**Ran the wrong suite under the right floor.** The verification loop substituted
`git-data-emit.test.sh` where the constraint named
`git-data-runcmd-rehearsal.test.sh`. It returned exactly `44 passed` against a floor
of `44`, so it read as a clean pass and was reported as one. — Recovery: caught on
re-reading the constraint list against the loop; the real rehearsal was relaunched. —
**Prevention:** a floor number is not a fingerprint of a suite. Print the resolved
path next to every floor result and compare paths, not counts; when two suites in one
subsystem share a count, the count is the least distinguishing thing about them.

**`nohup ... &` from the Bash tool does not survive the call.** The ~13-minute
rehearsal was launched detached, and a written rc file was polled for 30 minutes
before timing out with a 0-byte output file — the process had been killed when the
tool call returned. — Recovery: relaunched with the harness's `run_in_background`. —
**Prevention:** the rc-file discipline was right and is not the mechanism that keeps
a process alive. Use the harness's own backgrounding; a shell `&` is scoped to the
tool call. Note the failure signature is indistinguishable from a slow test, so an
empty output file after the expected runtime should be read as "it never ran," not
"it is still running." Inverse of
[[2026-05-20-long-running-bench-verify-process-before-relaunch]], same root need:
verify the process, not the artifact.

**Asserted a file path and an arithmetic I had not opened.** A panel finding was
written into the plan as "`git-data-birth-readiness-gate.sh` discounts 2 module `.tf`
files while its glob adds 3." The file is under `tests/scripts/lib/`, not
`apps/web-platform/infra/`; the glob adds 2; and the discounted 2 is the cloud-init
plus `main.tf`. — Recovery: reproduced the defect on a pristine `git archive
origin/main` extract through the production call signature (rc=1, 9 refs vs 11
resolved), filed as #7485, corrected the plan. — **Prevention:** a finding whose
*conclusion* is correct is the most dangerous kind to transcribe, because verifying
the conclusion feels like verifying the finding. When recording someone else's
finding, open the file and re-derive the mechanism; the conclusion surviving is not
evidence that the details did. Related: [[2026-08-06-i-shipped-two-unmeasured-causal-claims-inside-the-lint-that-forbids-them]].

**Proposed one shared strip expression where the ADR forbids sharing.** The initial
design collapsed the payload and template expressions into one tightened regex;
ADR-152 states they are "deliberately not shared, and must not be." — Recovery:
caught at plan review; redesigned as two separate locals mirroring the pattern
`zot-registry.tf` already ships. — **Prevention:** one-off; the ADR was in context
and was not read closely enough before designing against it.

**Added a `head -1 | grep -qx` predicate.** That is the `producer | grep -q` shape
this repo forbids — under `set -uo pipefail` it fails open via SIGPIPE (#7005). —
Recovery: caught in self-review before commit, replaced with a captured-string
comparison. — **Prevention:** already covered by the standing rule; the miss was
writing a pipeline reflexively rather than a herestring.

## Related

- [[2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed]] —
  the same family (assertions certifying a different property), one layer up: there
  the gate could not pass at all; here it passes and pins the wrong half.
- [[2026-08-01-my-mutation-battery-inferred-the-verdict-from-the-input-under-test]] —
  why the restore column matters.
- ADR-152 — the two strip expressions and why they stay separate.
- #7485 — a pre-existing fail-closed abort found by the same panel.
