---
title: "Five success signals that never checked the thing they named"
date: 2026-08-03
issue: 7144
pr: 7158
category: process
tags: [false-green, observability, silent-failure, mutation-testing, assertion-floor, digest-pinning, contention, inngest]
module: apps/web-platform/infra
related:
  - 2026-07-30-every-green-signal-i-had-certified-a-gate-with-six-fail-open-paths.md
  - 2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md
  - 2026-07-11-webhook-202-but-handler-never-ran-e2big-ship-component-error-channel-first.md
  - 2026-07-27-my-refutation-measured-a-shim-and-my-safe-fixture-hid-12240-deletions.md
---

# Learning: five success signals that never checked the thing they named

## Problem

A ~3-day inbound-email dispatch outage (#7144) was repaired across eight review
findings. Working through them surfaced the same defect five separate times, in five
unrelated subsystems, plus twice more in my own tooling while fixing it. In every
case a component reported success without checking the thing its name promised.

That recurrence is the finding. Each instance had been reviewed, tested, and shipped
by someone competent; none was caught by the guard nearest to it.

## The five instances

| Signal | What it claimed | What it actually checked |
| --- | --- | --- |
| `derive_dispatch_base` | the app's dispatch target | the FIRST `INNGEST_BASE_URL` in `Config.Env` — but docker lists `--env-file` first and `-e` second, and the process resolves to the LAST |
| `inngest-inventory.test.sh` | 120 passed, 0 failed | that everything which RAN passed — deleting a test function's call left 127/0 and exit 0 |
| the zot mirror | GHCR→zot parity | that a push succeeded. `docker tag` + `docker push` re-creates the manifest, so zot served a DIFFERENT digest for the same tag, for a year, with nothing comparing them |
| `verify_inngest_health` | inngest is healthy | that a port answered. Unauthenticated `/health` returned 200 from a surviving co-located server while every `inngest.send()` was refused |
| the probe-target fallback | the derived target | nothing — its loopback fallback was BYTE-IDENTICAL to a successful co-located derivation, so a green verdict had an unknown subject |

Two more from my own work in the same session:

- A verification one-liner printed `Exit code 1` while `INFRA_RUNNER_EXIT=0`: a
  trailing `[[ $rc -ne 0 ]] && grep` short-circuit set the command's exit. I
  reproduced the trailing-command-owns-the-exit trap **inside a command written to
  check for it**.
- `pkill -f 'ci-deploy.test.sh'` matched its own command line and killed the invoking
  shell (exit 144) — a trap this repo already documents.

## The shape

Every instance is a **proxy that drifted from its referent**, where the proxy is
cheaper to evaluate and the drift is invisible on the success path:

- position (`head -1`) proxying for precedence
- count-of-passes proxying for count-of-run
- push-exit-code proxying for byte identity
- port-answers proxying for send-succeeds
- a default value proxying for a derived value

The failure mode is identical in all five: **the proxy and the referent agree until
exactly the moment they matter.** `head -1` is correct while both duplicates agree.
The assertion count is correct while nothing is unhooked. The mirror digest is
correct until something pins it. `/health` is correct until the app is repointed. The
fallback is correct until derivation fails.

That is why review does not catch these. At review time the proxy IS the referent.

## Solution

The repair that generalises is not "add a check" — each of these HAD a check. It is
**assert the referent, and make the proxy's failure state distinguishable**:

- `tail -1`, plus a duplicate-key fixture. All three existing fixtures were
  single-entry, so the positional selector was pinned by nothing.
- An assertion-count floor. `$FAIL -eq 0` answers "did everything that ran pass?",
  never "did everything run?".
- `crane copy` (registry→registry, manifest-preserving) plus an explicit
  `crane digest` comparison — an empty source digest counts as failure, because
  `"" == ""` would otherwise read as a match.
- An authenticated POST to the app's real dispatch target. A refused connection and a
  401 are different failures; `/health` returns 200 through both.
- A third state: `probe_target_source` ∈ {env, derived, fallback}, on the JSON and
  the journald summary, so a verdict names its own subject.

## Key insight

**A guard that cannot distinguish its success state from its failure state is not a
guard.** The loopback fallback is the purest case — it emitted the byte-identical
string on both paths, so no consumer, however careful, could have told them apart.
Adding a third state cost one variable.

The corollary for test suites: a green run proves the assertions that executed
passed. It says nothing about which assertions executed. Only a floor closes that,
and the floor has to be a number someone must consciously lower.

## Session errors

1. **I reported a regression as mine on one A/B under heavy contention.** A canary
   test failed; I compared against HEAD once and called it "definitively mine". It was
   `/tmp` exhaustion — the canary writes to a FIXED `/tmp/canary-dash-body.html`, and
   the machine-global 4 GiB tmpfs hit zero bytes under four sibling `test-all` runs; a
   failed body write makes `grep -qF` find no sentinel, so the canary reads healthy and
   promotes. Re-running returned 201/201. The repo documents this false-red class and
   prescribes three-way confirmation; I applied the litmus only after asserting the
   opposite. **Confirm before attributing, not after.**

2. **My own comment consumed the budget the security fix needed.** The finding-1
   commit added a 104 B rationale comment to `cloud-init.yml`, which is byte-budgeted
   against Hetzner's 32 KB `user_data` cap. Measured: with it, the `@sha256` digest pin
   required by finding 2 was **8/8 over** budget; without it, **0/8 over**. Prose in a
   byte-budgeted file is not free, and the thing it crowds out may be a security control.

3. **I put URIs in journald lines** that the suite's own purity guard (#5503) forbids.
   Caught by an existing test; fixed by scheme-stripping to host:port, which keeps the
   whole diagnostic value.

4. **I hit the subshell trap while fixing a subshell-adjacent bug.**
   `derived=$(derive_dispatch_base)` runs the function in a subshell, so a global it
   assigns is discarded. The reason now travels on stderr, where the parent's assignment
   catches it.

5. **A `cloud-init.yml` comment placed inside a `docker run` line-continuation** would
   have terminated the command — `#` after a `\` continuation is not a comment in that
   position. Caught before commit.

## Prevention

- When a check's name contains a verb ("verify", "prove", "health"), ask what it
  would return if the thing it names were false. If the answer is "the same", it is a
  proxy, not a check.
- Fixture the shape, not just the value: a positional selector needs a multi-entry
  fixture, a bidirectional guard needs the direction where the weak implementation
  gives a false positive, a port passthrough needs a non-default port.
- Any suite whose count is stable gets a floor. Any fail-open branch gets a third
  state.
- Before attributing a test failure to your own diff, check `/tmp` headroom and
  sibling runs. Contention produces false reds; a single A/B under load proves nothing.
