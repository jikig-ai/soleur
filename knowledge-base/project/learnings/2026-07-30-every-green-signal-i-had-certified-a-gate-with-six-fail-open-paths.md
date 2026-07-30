# Every green signal I had certified a security gate with six fail-open paths

- **Date:** 2026-07-30
- **PR:** #7081 (local Supabase stack bound to loopback; ADR-153)
- **Category:** security-issues / test-failures
- **Related:** [ADR-153](../../engineering/architecture/decisions/ADR-153-local-supabase-loopback-binding-via-docker-network.md),
  `.claude/hooks/stub-argv-fidelity.test.sh` (the codified argv-blind-stub class),
  `cq-assert-anchor-not-bare-token`

## Problem

A security gate asserting that the local Supabase dev stack binds only to loopback
shipped through **every** verification signal available to me:

- 12 unit tests, green
- `shellcheck` clean on all three scripts
- `tsc --noEmit` clean
- A live end-to-end measurement: direct TCP to the LAN IP **refused** on all five
  ports, loopback **succeeded**, `ss` showed `127.0.0.1` only

Four review agents then found **six fail-open paths in the gate** and **11 of 17
surviving mutations in its tests**. The empirical measurement was real and correct —
it just measured the happy path, which is the one case a fail-open never affects.

## Root cause: one shape, patched one instance at a time

Every gate defect reduced to the same sentence: **the gate inferred safety from the
absence of parsed evidence.**

I found the first instance myself (an empty `HostIp` extracted to an empty string,
which an emptiness check read as "this container publishes nothing"), fixed *that
instance*, and moved on. The class stayed open. Security-sentinel then demonstrated
five more payload shapes — a space after the JSON colon, differing key case
(`hostIP`), a truncated value, empty output, literal `null` — each describing a
`0.0.0.0` stack, each with `docker inspect` exiting 0, each returning:

```
supabase-local: OK — 0 published binding(s) across 1 container(s), all loopback.
EXIT=0
```

The message is self-falsifying and nothing acted on it.

**The fix is a positive-evidence floor, not shape enumeration:**

```bash
if [[ "$containers" -gt 0 && "$checked" -eq 0 && "$unknown" -eq 0 ]]; then
  return 2   # UNKNOWN — the parse produced nothing; that is not "safe"
fi
```

Two siblings of the same shape: `docker inspect`'s exit code was discarded (an
uninspectable container reported SAFE), and `grep ... || true` collapsed "no match"
(legitimate) with "grep errored" and "grep absent" into "publishes nothing".

**Generalizable:** when you fix an "absence read as safety" bug, ask *what else
produces absence here?* — and prefer a floor that requires positive evidence over a
list of the absence-producing inputs you happened to think of.

## Why the tests could not see it

**The fake was argv-blind, so the fixture seam sat ABOVE the code under test.** The
fake `docker` dispatched on `$1` only and returned a fixture regardless of
`--filter`/`--format`. Consequences, all measured with the suite at 12/12 green:

| Mutation | Result |
|---|---|
| `.NetworkSettings.Ports` → `.HostConfig.PortBindings` (the proxy trap the ADR claims is "pinned by a regression test") | **green** |
| Corrupt the project label so the gate matches zero containers forever | **green** |
| `break` after the first container | **green** |
| Delete the `exec supabase …` line entirely | **green** |

The repo already codifies this in `.claude/hooks/stub-argv-fidelity.test.sh` — but
that meta-test scopes to `.claude/hooks/` with `STUB_CMDS="gh|jq|git"`, so a `docker`
stub under `apps/` ships unguarded. **The class was known; the guard's scope did not
reach the new instance.**

**A source-grep assertion was satisfied by the comment above the line it guarded.**
T10 grepped `--network-id[^|]*"$@"` against the SUT. The explanatory comment
`# --network-id MUST precede "$@" …` matched on its own, so deleting the exec line,
or inverting the flag order (*the precise bug the assertion was named for*), both
stayed green. This is `cq-assert-anchor-not-bare-token`, recurring. The durable fix
is behavioural: a fake `supabase` that records argv, asserted against the exact
expected string.

**Nothing asserted that the assertions ran.** No-oping `pass`/`fail` printed
`0 passed, 0 failed` and exited 0; deleting cases T2–T10 also exited 0. The only
merge gate was `[[ "$FAIL" -eq 0 ]]`. Fixed with a `MIN_ASSERTIONS` **floor** — a
floor, not equality, so adding a case cannot spuriously fail.

## A surviving mutation is not automatically a hole

My `grep_rc` branch survived deletion. The reason was informative rather than
alarming: the positive-evidence floor **also** returns 2 for that input, so safety
was preserved either way. What the branch uniquely buys is a *distinguishing
diagnostic*. The correct response was to pin the diagnostic (assert the specific
message), not to delete the branch or panic about coverage.

**Ask what a surviving mutation proves before treating it as a defect** — sometimes
it proves a broader guard subsumes a narrower one.

## Two dark channels

**A SessionStart hook writing to stderr is silent.** `.claude/hooks/README.md`
states plain stderr is DISCARDED for an exit-0 hook; the operator channel is
`systemMessage` on stdout. Layer 3 of a three-layer security control was dark while
ADR-153 claimed it "warns loudly". Same class as the `pre-merge-auto-close-scan.sh`
header's own warning ("Silence is how the PR-body arm stayed dead for 17 days at 8/8
green").

**Hardcoding `timeout` makes a hook dark on macOS**, which ships none in the base
system: `rc=127`, the `rc -eq 1` branch never fires, exit 0, no output, over an
exposed stack. Guard it: `TO=(); command -v timeout >/dev/null && TO=(timeout 10)`.

## A destructive bug behind an operator-overridable name

`ensure_network` would `docker network rm` any network whose name matched, so
pointing `SUPABASE_LOCAL_NETWORK` at (say) a compose project's `myapp_default`
**destroyed it**. Reproduced with a stub. Fix: label networks the script creates
(`com.soleur.supabase-local=1`) and refuse to remove one lacking the label.

**Generalizable:** an env-overridable name that feeds a destructive verb needs an
ownership check, not just a correctness check.

## Session Errors

1. **Planning subagent died** (`API Error: Connection closed mid-response`) mid
   `deepen-plan`. **Recovery:** one-shot's partial-artifact path — the plan body was
   on disk with frontmatter + Overview + Acceptance Criteria intact.
   **Prevention:** already covered; the recovery path worked as designed.
2. **A background task notification reported "exit code 0" while the suite's real rc
   was 1.** The notification reads the trailing `echo $? > rc`, not the command.
   **Prevention:** already a documented rule — read the rc FILE and the terminal
   marker, never the notification. It fired here exactly as documented.
3. **Foreground `sleep` is blocked** (exit 144 on a `nohup` wrapper).
   **Prevention:** documented gotcha; use `run_in_background` or Monitor.
4. **`test-all.sh` exceeded the 10-minute foreground cap.** **Prevention:** background
   + Monitor armed on BOTH completion and process-death, so silence is not read as success.
5. **My own gate had an empty-`HostIp` fail-open** — caught by my own test, then
   revealed as one instance of a class. **Prevention:** the positive-evidence floor.
6. **A fixture leaked between test cases.** `VAR=x res=$(fn)` is an *assignment-only
   command*, so bash persists `VAR` as a shell variable rather than scoping it to one
   command; T6's `DOCKER_EXIT=1` bled into T7/T8 and made two cases silently measure
   "docker unreachable" instead of their own fixture. **Prevention:** an explicit
   `reset_fixture` per case, so the suite is order-independent.
7. **The trap-ownership lint (ADR-129) failed on my suite** — per-case `mktemp` with
   `rm` at the end leaks on any abnormal exit. **Prevention:** one owning `WORKROOT`
   + a single `trap … EXIT INT TERM HUP`.
8. **11 of 17 mutations survived my tests** (see above). **Prevention:** argv-asserting
   fakes; behavioural probes over source greps; an assertion-count floor.
9. **Six fail-open paths found by review, four of them introduced by my own fixes.**
   **Prevention:** direct review agents at *what your own checking missed*, never at
   re-running it.
10. **I ended a turn on a mid-pipeline checkpoint** after quoting the rule against
    exactly that, and the operator had to prompt me to continue. **Prevention:** a
    phase-complete marker is a checkpoint; the next tool call in the SAME response
    must be the successor step.
11. **I nearly reported a green `test-all.sh` as evidence for code it never ran
    against** — the run predated six fixes and a rewritten suite. **Prevention:** a
    result is evidence only about the tree it ran on; re-run after any edit.
12. **My test rewrite introduced SC2015** (`A && pass || fail` is not if-then-else),
    turning shellcheck non-zero. **Prevention:** explicit `if/then/else` in assertion
    helpers.
13. **Plan T3 diverged from the implementation** (zero containers: plan said non-zero
    "never a pass", code returned 0 silently). Both were right for different callers.
    **Prevention:** resolved with an explicit `--require-stack` flag + a test pinning
    BOTH directions, rather than leaving an undocumented contradiction.
14. **Two ADR edit anchors silently failed to match** and were caught only by reading
    the file back. **Prevention:** assert the replacement landed (`count == 1` before
    replacing), never trust a string edit that reports nothing.

## Prevention — the one-line version

**Your own green signals are evidence about the cases you imagined.** A mutation
battery measures the mutations its author thought of; a passing suite measures the
fixtures its author wrote; an end-to-end measurement measures the happy path. The
only thing that found these defects was adversarial review pointed explicitly at
*what my checking could not see* — and the instruction that made it work was
"do NOT re-run my mutations; find the vacuity I missed."

## Reference (non-obvious, worth not re-deriving)

- The **Supabase CLI has no bind-address setting**. Upstream implemented one
  (`supabase/cli#4613`) and **closed it unmerged on policy** 2025-12-23, with the
  maintainer prescribing a Docker network instead. So the wrapper is **permanent**,
  not a stopgap awaiting a CLI upgrade.
- **`SUPABASE_SERVICES_HOSTNAME` is a decoy** — dial-side only (which host the CLI
  *connects to* for health checks); it does not affect what containers bind to.
- **`HostConfig.PortBindings` cannot distinguish** the wildcard from the
  loopback-bound state (empty `HostIp` in both). `NetworkSettings.Ports` is the
  resolved view and the only correct source.
