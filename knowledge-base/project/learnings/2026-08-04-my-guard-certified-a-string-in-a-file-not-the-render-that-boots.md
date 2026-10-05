---
title: "My guard certified a string in a file, not the render that boots"
date: 2026-08-04
category: test-failures
module: apps/web-platform/infra
issue: 7278
pr: 7280
tags: [mutation-testing, vacuous-guard, cloud-init, terraform, measurement-method, unicode]
---

# Learning: my guard certified a string in a file, not the render that boots

## Problem

`hcloud_server.registry` rendered `user_data` to **34,628 B** against Hetzner's hard **32,768 B**
cap. Over the cap means every registry provisioning event fails at the Hetzner API — and because
ADR-096 makes that host cloud-init-only, a provisioning event is the *only* channel for host-side
change. So the breach silently disabled all three paths that can create the host
(`registry-host-replace`, `registry-luks-recut`, `registry-region-migrate`) regardless of each
lever's own gates, during a live zot crash-loop where those levers were the proposed recovery.

Nothing caught it because `cloud-init-user-data-size.test.ts` guarded the web and git-data hosts
and had **no registry arm at all**.

The fix — a render-time comment strip, ADR-152's technique — was easy. Everything below is about
the three ways I got the *verification* wrong.

## Lesson 1 — extracting a value from a file proves the value, never its application

I made the size test **extract** the strip expression from `zot-registry.tf` rather than restating
it, and wrote in the comment that this made model-vs-production divergence *"unexpressible instead
of merely policed"*. That was the single most confident claim in the PR and it was wrong.

Extraction pins **what the expression is**. It says nothing about whether `user_data` **applies**
it. Five mutants survived, all on that seam:

| Mutation | Effect | Suite |
|---|---|---|
| drop the `replace()` wrapper, orphan the local | 34,628 B, over cap | 33/0 green |
| keep `replace()`, pass an **inline boot-bricking literal** | `#cloud-config` deleted | 33/0 green |
| `#`-commented decoy carrying the good expr shadows a bad live local | boot-brick | 33/0 green |
| strip also eats `^[ \t]*- ` — **32** runcmd/write_files entries gone | host boots, does nothing | 33/0 green |
| `REGISTRY_GZIP_BUDGET`→32_767, `FLOOR`→1 | tripwire + non-vacuity arm removed | 33/0 green |

The second is the one that actually happens. It is not sabotage, it is a plausible cleanup —
*"the `replace()` + local indirection is hard to read, inline the regex"* — and the expression an
engineer would most plausibly copy is git-data's, which deletes `#cloud-config` and dark-boots the
host.

**git-data had already learned this.** `git-data-render-strip-parity.test.sh` says verbatim: *"Arm
1 compares the strip EXPRESSION; nothing checked that the budget harness actually APPLIES it …
removing one `replace()` left this suite 8/8 green while that harness rendered
`git-data-gc.sh` UNSTRIPPED."* I read that file, cited it in the ADR amendment as the thing my
approach improved on, and reproduced its defect.

**Fix that generalizes:** make the model's INPUT depend on the predicate. The size test now asks
whether the render applies the strip and models the un-stripped payload when it does not — so
unwiring the strip reds the **cap** assertion, i.e. it fails for the reason the host would fail,
not via a separate "is it wired" assertion that a future edit could delete on its own.

**Litmus, for any guard that reads a value out of a file:** *does anything fail if the value is
correct and unused?*

## Lesson 2 — a forbidden measurement method, used because it was convenient

My first measurement was `gzip -9 -c file | base64 -w0 | wc -c` = **34,320**. I carried that
number into four places including two production-adjacent code comments.

`git-data-userdata-budget.sh:19-22` forbids exactly this, in prose, in the same directory:

> MEASURE WITH TERRAFORM'S OWN `base64gzip`, NEVER `gzip -9`. They are different compression
> levels and `-9` OVERSTATES headroom … On a hard gate an optimistic measurement is worse than
> none.

The plan's own task 0.5a also said to measure the substituted render, not the raw file. Both were
available before I measured. The real figure is **34,628** — the error was in the *optimistic*
direction, which on a hard gate is the direction that ships.

**Prevention:** when measuring against a hard external limit, find the repo's existing measurement
for that limit before inventing one. A sibling host measured against the same cap is a strong
signal that the method is already decided.

## Lesson 3 — writing about a control character by including it

While documenting that JS's `m` flag treats U+2028 as a line start and Go RE2 does not, I typed
three **literal** U+2028 characters into the comment. U+2028 *is* a JS line terminator, so the file
stopped parsing. Then I did it again in the test fixture.

Downstream, this cost two more failures that looked like unrelated tooling problems: an `Edit`
that could not match its own target ("String to replace not found" — the chars are invisible), and
a `Bash` call rejected with `command contains control characters`.

**Prevention:** any prose *about* a control character, zero-width character, or line separator must
use the escape spelling (`\u2028`), never the character. The tell that you have made this mistake is
a syntax error whose caret points at text that looks fine.

Related, and the reason this is worth a lesson rather than a shrug: the same class made a real
correctness bug. My model used the `m` flag; production uses Go's `(?m)`. The two disagree on
exactly these bytes, and the disagreement runs in the dangerous direction — the model would strip
a line production keeps, **under-measuring** the payload, i.e. green CI over an over-cap render.

## Key Insight

All three failures are the same shape: **I verified the thing I had built, not the thing that
runs.** The extraction verified an expression rather than a render; `gzip -9` verified a
compression rather than terraform's; the `m` flag verified JS's line grammar rather than Go's.

A guard is only as good as the distance between what it measures and what ships. Every one of
these had a shorter path available in-repo — a sibling parity suite, a sibling budget script, the
engine's own docs — and each was skipped because the version I built already looked green.

## Session Errors

1. **The guard was vacuous in five ways.** — Recovery: mutation battery on a sandbox copy, control
   run first, `diff -q` landing check per mutation; all 8 mutants now RED against a 38/0 control.
   **Prevention:** for any guard reading a value out of a file, ask "does anything fail if the
   value is correct and unused?" and make the model's input depend on the predicate.

2. **Used `gzip -9` against a hard cap the repo forbids measuring that way.** — Recovery:
   re-measured via `terraform console`; reconciled all four sites. **Prevention:** grep for an
   existing measurement of the same limit before inventing one.

3. **Claimed JS/Go regex equivalence was "unexpressible".** — Recovery: measured the divergence,
   anchored the model to `\n` explicitly, added a detector for the bytes. **Prevention:** treat
   "divergence is structurally impossible" as a claim requiring a counter-example attempt.

4. **Wrote literal U+2028 into a file documenting U+2028 (twice).** — Recovery: replaced with
   escape text. **Prevention:** escape spelling only, for any control/invisible character.

5. **`Edit` failed to match a target containing invisible chars; `Bash` rejected a command with
   control characters.** — Recovery: switched to a Python rewrite keyed on codepoints.
   **Prevention:** consequence of #4; same fix.

6. **Ran `vitest` against a `bun test` suite → silent empty output, read as "no tests".** —
   Recovery: found the runner via `scripts/test-all.sh`. **Prevention:** resolve a suite's runner
   from the registration site before concluding anything from empty output.

7. **`cd apps/web-platform/infra` failed on a persisted CWD from a prior call.** — Recovery:
   absolute paths. **Prevention:** already covered by the work skill's CWD guidance.

8. **Foreground 2-min timeout on the infra suite; Monitor under-armed at 500 s.** — Recovery:
   `setsid nohup` + rc file, Monitor re-armed with a liveness branch. **Prevention:** already
   documented; the ownership check (`/proc/<pid>/cwd`) correctly distinguished my run from an
   orphaned sibling worktree's run.

9. **Four review agents died on a weekly API limit mid-run.** — Recovery: `SendMessage` resumed
   three with transcripts intact; the partial "M4 SURVIVES" emitted before the kill is what
   surfaced the whole vacuity class. **Prevention:** resume, never respawn — already in
   `review/SKILL.md` Gate 2b, and it paid here.

10. **Trusted the plan's R4 stock claim.** — Recovery: live Hetzner probe showed `cx23` available
    in nbg1-dc3 but NOT hel1-dc2 where the registry runs; corrected the plan and disclosed the
    pending-REPLACE hazard. **Prevention:** `hr-verify-repo-capability-claim-before-assert` already
    covers this; the miss was not re-probing a plan-quoted *live probe* result.

## Related

- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- `knowledge-base/project/learnings/2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md`
- `apps/web-platform/infra/git-data-render-strip-parity.test.sh` — the suite that had already
  learned Lesson 1
- ADR-152 (amended 2026-08-04) — the technique, and why its expression is not portable between
  "strip injected scripts" and "strip the cloud-init itself"
