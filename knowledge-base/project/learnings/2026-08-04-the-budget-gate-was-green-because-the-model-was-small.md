---
title: The budget gate was green because the model was small, not because the render fit
date: 2026-08-04
category: build-errors
module: apps/web-platform/infra
tags: [byte-budget, terraform, gzip, measurement-fidelity, fixtures, observability, stale-comments]
issues: [7144, 7158, 7242, 7267]
---

# The budget gate was green because the model was small, not because the render fit

## Problem

`cloud-init-user-data-size.test.ts` asserted `REGISTRY_BUDGET = 32_000` against a **node model** of
terraform's `base64gzip`: `"x".repeat(n)` for every non-file template var, `gzipSync(level: 9)`.

Terraform's own `base64gzip` renders the same template at **32,156 B**. The node model reports
**31,572 B**. So the gate was passing against a render that was **already 156 B over its own
sub-cap**, and the file's recorded "~1,196 B of real headroom" was actually **612 B**.

The gate had never measured the artifact. It measured a model of the artifact, in a different
compression engine, with the incompressible parts replaced by runs of `x`.

## Root cause

Three effects, all pushing the same direction, measured against the as-written files:

| effect | bytes |
|---|---|
| `"x".repeat(n)` stand-ins for real high-entropy values | 340 |
| Go-vs-node zlib match choices at the same level | 228 |
| level 9 vs Go's `gzip.NewWriter` DefaultCompression (6) | 16 |
| **total under-report** | **584** |

The x-run term dominates and is the one that is *structurally* invisible. x-runs compress ~1000:1 —
the test file says so itself, at the `webhook_doppler_token_env` branch. Every registry template var
is a non-file value, and five carry real entropy (the zot image digest, the Doppler CLI sha256, the
Doppler service token, two heartbeat path tokens). So the model does not under-measure a little
everywhere; it under-measures *exactly the part that cannot compress*.

Why it stayed invisible: the web host has ~8.3 KB of headroom and git-data ~6 KB. A 584 B error is
noise there. The registry host has 612 B. Same model, same error, different verdict.

`git-data-userdata-budget.sh` already stated the general rule in its own header — *"on a hard gate
an optimistic measurement is worse than none"* — and nobody had applied it to the tightest of the
three hosts. The rule was written down and still did not fire, because nothing connected it to the
host where the margin had quietly shrunk.

## Solution

`apps/web-platform/infra/registry-userdata-budget.sh` — the `git-data-userdata-budget.sh` shape:
render through `terraform console`, measure with terraform's own `base64gzip`, hard cap 32,768 plus
a 32,450 sub-cap tripwire (294 B for an ordinary edit; 318 B between a CI red and a failed apply).
Registered in `infra-validation.yml`'s terraform-bearing job — anywhere else it SKIPs into a fake
gate (#6454).

The node budget is kept as a cheap fast-suite proxy, re-baselined to `31_866` with an explicit
`REGISTRY_NODE_OFFSET = 584`, so `BUDGET + OFFSET` lands exactly on the script's sub-cap and both
gates trip at the same **real** size. `registry-userdata-budget.test.sh` pins that relation as a
one-sided **under-statement** guard (`terraform_stored <= BUDGET + OFFSET`) — an offset that is too
generous is merely conservative; one that is too small is unsound.

## Key insights

### 1. A budget gate modelled in a different engine than the thing it gates

Ask two questions of any budget assertion: *what engine produced this number*, and *what is the
margin*. The product of "approximate model" and "large margin" is fine. The product of "approximate
model" and "small margin" is a gate that reports on itself. The fix is not a better model — it is a
gate that runs the real renderer.

### 2. A shape fixture must match LENGTH **and** ENTROPY, and both directions are defects

A same-length but low-entropy stub gzips away and silently restores the exact optimism the
byte-exact gate exists to remove. Equally, the first draft here *over*-modelled: it assumed 40-char
Better Stack heartbeat tokens. A live length-only probe (`doppler secrets get --plain | wc -c`,
value never printed) gave 72-char URLs — a 48-char prefix plus a 24-char credential segment — and
43-char Doppler token bodies. That was ~30 incompressible bytes of pessimism on a sub-1 KB margin.

On a tight margin a pessimistic gate is its own defect: it reds CI on edits that would have fit.
Assert the **exact** length, not a floor — the exact assertion is what caught a 1-character error
in the first fixture.

### 3. A synthesized secret-SHAPE fixture trips the repo's own guards, not just Push Protection

The synthetic heartbeat URLs tripped `inngest.test.sh` 1.6.2 — *"no Better Stack heartbeat URL
literal is baked into a delivered infra artifact"* — which exempts `*.test.sh` but not a budget
script. The guard exists because a baked heartbeat URL arms a second pusher on one monitor (#6552).

The right answer to a shape guard is to **stop carrying the shape**, not to widen the guard's
exclusions. Split it across `join("", [...])` — the precedent already sitting two lines below for
the Doppler token. Widening a security guard to accommodate a convenience file is the move that
looks cheapest and costs the most.

### 4. Replacing a stale claim with an INFERRED one is not an improvement

Correcting `web-probe.tf`'s "web-2 retired 2026-07-17", I wrote that web-2 has no probe feeder,
reasoning from `server.tf`'s web-1-only SSH provisioners. Better Stack refuted it in one query:
`web-zot-consumer-probe.service` emits from `soleur-web-2` as well as `soleur-web-platform`.

A fresh host gets the timer from `cloud-init.yml`'s runcmd; the web-1-only provisioners exist
because web-1 carries `ignore_changes=[user_data]` and is the unrebuildable pet, so they are its
**re**-provisioning path, not the only install path. **The resource that installs on the pet is not
the resource that installs on the cattle.** Read the telemetry before asserting which hosts run a
unit — `hr-no-dashboard-eyeball-pull-data-yourself` applies to your own comments, not just to
incident loops.

### 5. Deleting a false clause can strengthen the false claim that leaned on it

The documented class, hit again. Removing "web-2 retired 2026-07-17" from `inngest.tf` left its
"TWO co-located inngest schedulers" sentence dangling as a **live-state** claim — strictly worse
than the falsehood removed, because the reader now believes it describes today.

The honest replacement names the actual mechanism (`web_colocate_inngest` flipped default-false
2026-07-11; web-2 was born after it) **and** why it matters: the variable is GLOBAL, so flipping it
re-arms the 40 > 30 pool ceiling on either host's next fresh boot. The original comment hid that
behind an assertion the host was gone.

### 6. An anti-masking rule must name the DIRECTION or it gets cited against the safe one

`architecture-strategist` read the ALL-MUST-SERVE multi-repo probe list as contradicting the
anti-masking rule 30 lines below it, which read *"folding would re-introduce OR-masking across two
distinct failure domains"*.

OR-masking (fire if EITHER healthy) loses alarms. AND can only **over**-suppress, never
under-suppress — it strictly ADDS detection, since nothing verified the bootstrap repo before. The
rule said "folding" generically, so it was applied against the safe direction. Rules about masking
must name the direction.

The real cost of AND is **discriminability**, and it is repaid in the observability layer (the
suppress branch names the failing repo in journald), not with a second heartbeat that would cost a
`betteruptime_heartbeat` + `doppler_secret` per host and re-provision web-1 via `triggers_replace`.
Named residual: the fold changed the SUBJECT of an existing beat, so absences read across the
boundary are ambiguous.

### 7. A closed blocker is not a cleared condition — and closing it can delete the only tracker

#7242 ("blocked at the zot mirror") was closed at 13:28Z when #7244 fixed the error's *self-refuted
diagnosis*. The outage itself continued: **68 SUPPRESS rows / 0 successful probes in 48h**, both web
hosts, still failing at 13:33Z — five minutes after the close.

The registry host reads healthy from its own side (`ping_rc=0`) with `zot_restarts=4888`, i.e.
flapping: up when the local cron checks, down when consumers do. That asymmetry is why the closure
looked safe.

`hr-before-asserting-github-issue-status` applies to a blocker's **closure** as much as to its
status. When a blocker closes, verify the condition, not the issue — and check whether closing it
left the live condition with no tracker at all. Filed #7267.

## Session Errors

1. **Launched a long test runner, then kept editing under it — twice.** The documented
   self-inflicted-failure shape. The first `run-registered-suites.sh` run returned 1 RED while I was
   mid-edit on `.tf` files, so the RED could not be attributed without a clean re-run.
   **Prevention:** `git status --porcelain` must be empty before launching, and if an edit cannot
   wait, kill the run rather than reinterpreting its output. (Already in `work/SKILL.md`; I read it
   and did it anyway — the gap is that nothing mechanically checks.)

2. **Ran `run-registered-suites.sh` twice in one command** (two invocations piped to different
   greps), causing a 2-minute timeout and a wasted duplicate run of an expensive suite.
   **Prevention:** run once into a log, then grep the log.

3. **`git stash list` in a command despite `hr-never-git-stash-in-worktrees`** — the hook denied the
   entire Bash call, taking three unrelated commands with it. The rule explicitly covers the
   read-only form. **Prevention:** already hook-enforced; this was a knowledge-application failure,
   not a missing guard.

4. **Heredoc'd an issue body into the same Bash call as a hook-gated `gh issue create`.** The
   `--milestone` gate denied the call and the heredoc never ran, so the retry failed `no such file`.
   The exact trap documented in `work/SKILL.md`. **Prevention:** already documented; use the Write
   tool for the body first, then a separate Bash call for `gh`.

5. **Unbounded grep matched a large generated artifact.** A sweep for `1196` hit
   `model.likec4.json` and produced 635 KB of output — `hr-never-run-commands-with-unbounded-output`.
   **Prevention:** scope value-sweeps with `--include` and exclude generated artifacts; prefer the
   formatted form (`1,196`) over the bare digits when sweeping prose figures.

6. **Over-modelled the heartbeat stub at 87 chars** (assumed 40-char tokens) instead of the measured
   72. **Prevention:** measure fixture lengths from the live value (length only, never the value)
   before writing a byte-exact model. Caught by my own exact-length assertion — which is the
   argument for exact over floor.

7. **First draft carried literal heartbeat URLs**, tripping `inngest.test.sh` 1.6.2.
   **Prevention:** before adding a credential-shaped literal to any non-`*.test.sh` file under
   `infra/`, grep the infra suites for a guard on that shape.

8. **Wrote an inferred claim into a comment** (web-2 has no feeder) that telemetry refuted.
   **Prevention:** see Key Insight 4 — one Better Stack query, before the assertion.

9. **Left a dangling claim when deleting a false clause** in `inngest.tf`. Caught on re-read.
   **Prevention:** after removing an entity from prose, re-read the following two sentences asking
   "what does this attach to now?"

10. **Two silent extraction bugs in the new test suite**, both of which *passed* their downstream
    arithmetic assertions: `grep -oE '[0-9_]+'` matched the underscore in the constant NAME
    (`REGISTRY_BUDGET`), and quote-pairing over a `join("", [...])` mis-scanned off the empty first
    argument, yielding a 5-char "48-char prefix". Bash arithmetic coerced both malformed values
    silently. **Prevention:** the `=~ ^[0-9]+$` shape assertions caught both — every extracted
    operand needs a shape assertion, not just a use. This is why the drift-guard rule says extract
    *and validate* each operand.

11. **CWD drift between Bash calls.** After an earlier `cd apps/web-platform/infra`, a `bun test`
    with a repo-relative path found no files. **Prevention:** documented in `work/SKILL.md`; chain
    `cd <abs> && <cmd>` in a single call.

12. **`$?` read in an assert argument** — correct only while nothing is inserted between the two
    lines. **Prevention:** capture into a named `rc_*` variable.

13. **`sed` splice of a filesystem path** into the scratch `main.tf`, where `&` expands to the whole
    match and `|` was the delimiter. **Prevention:** bash parameter substitution treats the
    replacement literally; assert the placeholder is gone afterwards.

## Recurring-vs-one-off triage

| item | recurring? | disposition |
|---|---|---|
| 1 edit-under-a-running-gate | recurring | file-tracked — a mechanical pre-launch clean-tree check belongs in the runner, not in prose that is already there and already ignored |
| 2 duplicate expensive run | one-off | noted |
| 3 `git stash list` | one-off | already hook-enforced |
| 4 heredoc + gated `gh` | recurring | already documented in `work/SKILL.md`; no further action |
| 5 unbounded grep | recurring | fix-now-inline — none needed beyond the note; the rule exists |
| 6 fixture length assumed | recurring | fixed inline (measured + exact-length assertion in the suite) |
| 7 credential-shaped literal | recurring | fixed inline (`join()` split) |
| 8 inferred claim in a comment | recurring | fix-now-inline — done; Key Insight 4 is the durable form |
| 9 dangling claim after deletion | recurring | fixed inline; the class is already documented |
| 10 unvalidated extraction operands | recurring | fixed inline (shape assertions) |
| 11 CWD drift | one-off | already documented |
| 12 `$?` positional fragility | one-off | fixed inline |
| 13 `sed` `&`/`|` splice | recurring | fixed inline (bash substitution) |

Only item 1 is proposed for tracking; everything else was either fixed in this PR or is already
covered by an existing rule or hook.

## Verification

- Registered infra suites **88/88** (clean tree)
- `registry-userdata-budget.test.sh` **45/0**, floor mutation-proven (deleting one assertion → rc=1
  at 44)
- `web-zot-consumer-probe.test.sh` **59/0**
- `cloud-init-user-data-size.test.ts` **31/0**
- `inngest.test.sh` **181/181** (was 180/181 before the `join()` split)
- `terraform fmt -check` + `terraform validate` clean
- Budget script deterministic across 3 runs: `stored=32156, headroom=612`

## Related

- `knowledge-base/project/learnings/2026-08-03-five-success-signals-that-never-checked-the-thing-they-named.md`
- `knowledge-base/project/learnings/2026-07-16-removing-a-false-claim-can-strengthen-the-false-claim-that-leaned-on-it.md`
- `apps/web-platform/infra/git-data-userdata-budget.sh` — the shape this follows, and the header
  that already stated the rule
