---
title: "Refuting a hypothesis by reasoning while its discriminator is invisible — and why 'the probe ships first' was not fiction"
date: 2026-07-16
category: best-practices
tags: [diagnosis, measure-dont-infer, probe-first, systemd, privatetmp, doppler, observability, false-green, merge-ref, ci]
problem_type: logic_error
component: infrastructure
module: apps/web-platform/infra
related_pr: "#6567"
related-issues:
  - 6536
related_learnings:
  - 2026-07-16-a-drift-guard-can-recreate-its-own-bug-and-a-forced-replace-from-a-stale-pin-ships-nothing.md
  - 2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md
  - 2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md
---

# Refuting a hypothesis by reasoning while its discriminator is invisible

#6536: `inngest-heartbeat.service` failed every 60s for 3 days (3,724 fires). A plan with five
review rounds shipped a fix. The host was replaced with it. **The unit kept failing every 60s**,
for a cause the plan had explicitly considered and refuted.

The fix's *observability* half is what revealed that, in two minutes. This file is about why
the diagnosis half was wrong, and why the ordering that would have caught it was discarded.

## 1. A hypothesis refuted by REASONING is not refuted, when the datum that would settle it is the thing you cannot see

### What happened

The plan enumerated five hypotheses and dispositioned each:

| | Hypothesis | Plan's verdict | Basis |
|---|---|---|---|
| H3 | `/tmp/.doppler` ownership clash | **REFUTED** ("real asymmetry, not firing") | **reasoning about systemd semantics** |
| H5 | absent URL → `curl` rc=2 | **CONFIRMED — "the sole live cause"** | a **dev-box** `curl ""` probe + the URL's absence in Doppler |

Both were wrong. The measured cause — visible the moment the unit's stderr could leave the host —
was **H3**:

```
Doppler Error: open /tmp/.doppler/.doppler.yaml.Pbc4Qm46: permission denied
```

`doppler run` died **before exec**, so the ping script never ran and H5's `curl` was never
reached. The plan's own H1 probe had already established that this class means *"the child never
runs"* — it just never connected H1's mechanism to H3's disposition.

### Why the reasoning failed — it reasoned about the wrong pair

The plan's H3 argument, verbatim:

> *"`inngest-server.service` sets `PrivateTmp=true`; the heartbeat sets none — so they use
> **different `/tmp`s and cannot collide**. Nothing `mkdir`s `/tmp/.doppler`; the CLI creates it
> **lazily as `deploy`**."*

Both halves are false, and in the same way — they modelled **heartbeat vs. sibling**:

- The collision was never heartbeat-vs-sibling. It was heartbeat-vs-**root's boot self-check**:
  `cloud-init-inngest.yml` runs `doppler secrets` **as root** with the same
  `DOPPLER_CONFIG_DIR=/tmp/.doppler` (`:212` writes `HOME=/root` + the dir; `:226`/`:289` use it).
- So the CLI *does* create it lazily — **as root**, at boot, before the unit's first fire.

The asymmetry the plan noticed ("the heartbeat sets none") was the *whole bug*. It was observed,
named, and then explained away by comparing it to the wrong thing.

### The tell that should have stopped it

The plan **wrote the disqualifier itself**, in a different section:

> *"We cannot close that gap from the repo — the deciding datum is the unit's own stderr, and it
> is discarded at the source."*

That sentence is a statement that **no hypothesis about the failure mode can be confirmed or
refuted yet**. H5 was nevertheless marked *CONFIRMED — the sole live cause*, and H3 *REFUTED*.
The evidence for H5 was:

- `curl -fsS --max-time 10 ""` → rc=2 — **true, and about a dev box**, not about that unit;
- `INNGEST_HEARTBEAT_URL` absent from `soleur-inngest/prd` — **true, and about Doppler**, not
  about that unit.

Neither is evidence about the failing process. They establish that H5 *could* produce the
symptom, not that it *did*. And #6536 never reported an exit code at all — only
`Failed with result 'exit-code'`, from which the issue *inferred* a post-ping step, which the
plan correctly refuted before substituting an inference of its own.

### Key insight

**When the deciding datum is unavailable, the honest disposition for every hypothesis is
UNKNOWN — including the ones that feel refuted.** A hypothesis "refuted" by reasoning about
component semantics is a *prediction*, and predictions about a system you cannot observe are
exactly what the missing observability was hiding.

Three mechanical tells, in the order they were available here:

1. **The plan says the discriminator is missing.** Then no row in the hypothesis table may read
   CONFIRMED or REFUTED. Grep your own plan for "cannot", "not established", "discarded",
   "invisible" — if such a sentence exists, every verdict above it is provisional.
2. **The confirming probe ran somewhere other than the failing host.** A dev-box `curl`, a local
   `psql`, a laptop `systemctl` — these establish *capability*, never *actuality*. Ask: *does
   this evidence distinguish my hypothesis from its rivals, or is it merely consistent with
   mine?* H5's evidence was equally consistent with H3.
3. **A refutation that compares A-vs-B when the environment contains C.** "They can't collide"
   is only sound over an *enumerated* set of actors. Enumerate every writer of the contested
   resource (here: `grep -rn DOPPLER_CONFIG_DIR` would have surfaced the root-run cloud-init
   self-check immediately).

**The controlled-comparison test that settles this class in one command.** Once measured, the fix
was provable from source alone — all three doppler units were identical in `User=deploy` and
`EnvironmentFile`, and differed on exactly one variable:

| unit | `PrivateTmp` | works? |
|---|---|---|
| `inngest-server` | ✅ | yes |
| `vector` | ✅ | yes |
| **`inngest-heartbeat`** | ❌ | **no — since first boot** |

When a unit fails and its siblings don't, **diff the units before theorising about semantics**.
One asymmetry across an otherwise-identical set is a stronger signal than any argument about how
`PrivateTmp` is supposed to behave.

### Bonus: the unattributed onset was the same miss

The plan hunted the `13:00:38Z` onset through deploys and commits, found nothing, and filed it as
*"not established"*. It is the **host's boot time**. Root-owned `/tmp/.doppler` exists from
cloud-init onward, so the unit had failed since its **very first fire** — it never worked once.
"Onset == host birth" was invisible while the search space was "what changed?", because *nothing*
changed. **When an onset resists attribution to any change, test the hypothesis that nothing
changed and the thing never worked.**

## 2. "The probe ships first" was not fiction — it was the one ordering that could have caught this

### What happened

The plan's Phase 1 was explicitly *observability first*:

> *"Phase order is load-bearing: the **probe ships before the fixes** so the next fire
> self-reports which defect was live, and the fix is verified against evidence."*

v5 removed it:

> *"v5: dropped the 'probe ships BEFORE the fix' ordering. **It was fiction** — FR3/FR4/FR5 ride
> one image, one bump, one replace, so no fire occurs between them. And there is nothing left to
> discriminate: H5 is confirmed, H4 refuted+descoped."*

Both justifications are false, and the second one is circular:

- *"Nothing left to discriminate"* rests on **H5 confirmed / H3 refuted** — the very verdicts the
  probe existed to test. The plan retired the instrument on the strength of the readings it had
  not taken.
- *"No fire occurs between them"* is true **only within one image**. It quietly redefines
  "before" as *before in build order* rather than *before in evidence order*. The probe cannot
  self-report which defect was live if it lands in the same artifact as the fix for the defect
  you guessed.

### The cost, exactly

One full host replace, spent on a defect that was never reached. It was affordable only because
the host was dark — after #6178 arms the flip, the same mistake is a **cron outage**. The replace
window is the budget the probe-first ordering was protecting.

### Key insight

**Probe-first is not a nice-to-have sequencing preference; it is what converts a hypothesis into
a measurement.** Its cost is one extra delivery cycle. Its value is not spending the *expensive*
cycle on the wrong defect.

The rule that generalises:

> **If a plan's own text says the deciding datum is currently unavailable, the FIRST deliverable
> is the thing that makes it available — and it ships ALONE, in its own artifact, ahead of any
> fix.** "They ride the same image so ordering is meaningless" is the argument to reject: it
> means the ordering was never real, which is the problem, not a reason to drop it.

And the specific anti-pattern to name, because it is seductive:

> **Never justify removing a probe with a conclusion the probe was meant to test.** If the
> reasoning for dropping the probe reads *"there's nothing left to discriminate — X is
> confirmed"*, ask how X was confirmed. If the answer is "by reasoning" or "by a probe run
> elsewhere", the probe is still load-bearing.

### What the probe half actually bought, when it finally shipped

`SyslogIdentifier=inngest-heartbeat` + the `vector.toml` Source 4 entry. The plan called it
*"the highest-value line in the PR"* and was righter than it knew: **zero rows in 3 days → root
cause in 2 minutes**, off-box, no SSH. It diagnosed the failure of the fix it shipped with.

That is the honest summary of #6536: **the observability half worked and the diagnosis half did
not, and the observability half is why we know.**

## 3. A conflicted PR reports "all checks green" — because the checks never ran

### Problem

After a force-push, `gh pr checks` reported **all checks settled, zero failures**. CI and Infra
Validation had *never dispatched* on that SHA. Merging on that green would have shipped an
unverified tree.

### Root cause

A `pull_request` workflow runs against **`refs/pull/N/merge`** — a ref GitHub cannot compute when
the PR conflicts with the base. The PR was `mergeable=CONFLICTING` (8 commits behind main, a
conflict in a file both sides appended to). So:

- `pull_request` workflows (CI, Infra Validation) — **never dispatched**;
- `pull_request_target` workflows (CLA) — run against the **base**, so they dispatched and went
  **green**.

`gh pr checks` reports the checks that exist. Zero failures among zero relevant checks is
"green".

### Key insight

**"No failures" and "the checks ran" are different claims, and a conflicted PR silently produces
the first without the second.** Before trusting a green:

```bash
gh pr view <N> --json mergeable,mergeStateStatus   # CONFLICTING/DIRTY => pull_request CI is NOT running
gh api "repos/<o>/<r>/actions/runs?head_sha=$(git rev-parse HEAD)" --jq '[.workflow_runs[].name]'
```

Assert the checks you *expect* are **present**, not merely non-failing. The asymmetry is the
trap: `pull_request_target` jobs keep reporting green through a conflict, so the check list looks
populated and healthy.

## Session Errors

- **I inherited the plan's H5 inference without challenging it.** The handoff said "verified
  facts — do not re-derive: `curl -fsS --max-time 10 "" ⇒ rc=2`". That fact is true and I was
  right not to re-derive it — but it was never evidence that H5 was *live*, and I treated the
  do-not-re-derive framing as covering the *conclusion* as well as the *measurement*.
  **Prevention:** "do not re-derive X" protects a **measurement** from being re-run; it never
  ratifies the **inference built on X**. When a handoff pre-commits a cause, ask what would
  distinguish it from its rivals — and if the answer is "the datum we don't have", treat the
  cause as unknown regardless of how settled the handoff sounds.
- **A whole host replace was spent on a defect that was never reached.** Recovery: the
  observability half diagnosed it in 2 minutes and a second cycle shipped the real fix; it was
  free only because the host was dark. **Prevention:** §2 — probe ships alone, first.
- **I nearly merged on a false green.** `gh pr checks` reported "all settled, zero failures"
  while CI had never dispatched (conflicted PR ⇒ no merge ref). Recovery: noticed CI/Infra
  Validation were missing from the run list, found `mergeable=CONFLICTING`, merged main, and both
  dispatched and went green. **Prevention:** §3 — assert expected checks are *present*, and check
  `mergeStateStatus` before trusting a green.
- **`grep` on this machine is a shell FUNCTION wrapping ugrep 7.5.0**, while `/usr/bin/grep` is
  GNU grep 3.12. It is **not exported**, so `bash script.sh` correctly gets GNU grep — local
  suite results stand — but every bare interactive `grep` runs ugrep. This produced the stray
  `ugrep: warning:` lines and is the mechanism behind the known NUL-byte trap.
  **Prevention:** for anything whose result you will *act on*, invoke `/usr/bin/grep` explicitly;
  `type grep` before trusting an interactive grep's semantics.
- **Reached for `git stash list`** (a read-only subcommand) and the guardrail hook denied it.
  **Prevention:** none needed — the rule is mechanical and correct; the hook caught it instantly.
  Don't reach for `stash` at all in a worktree, even read-only subcommands.
- **Guessed a script path in a repro** (`apps/.../scan-supabase-advisors.sh`) instead of reading
  the test's own `$SCRIPT` var; the repro failed on "No such file" and cost a cycle.
  **Prevention:** when reproducing a test's logic, read its variable definitions first — the same
  rule as "run the real code, don't reimplement it" from the sibling learning.
- **A flaky blocking gate false-FAILed the pin PR** (`scan-workflow.test.sh`, `pipefail` +
  `grep -q` SIGPIPEs the producer → reports a source line missing that sits at `:49`). Confirmed
  flaky by a clean re-run of the identical tree. **Prevention:** filed as **#6572** with the
  mechanism and three candidate fixes; different subsystem, so it stays its own issue and PR.

## Prevention

- Before accepting any hypothesis table: grep the plan for its own "we cannot establish X" line.
  Every verdict above it is provisional. A CONFIRMED that co-exists with "the deciding datum is
  discarded at the source" is a contradiction the plan is carrying.
- Ask of every confirming probe: **did this run on the failing host?** If not, it establishes
  capability, not actuality — and is probably equally consistent with the hypothesis you refuted.
- Before theorising about component semantics, **diff the failing component against its working
  siblings**. One asymmetry across an otherwise-identical set beats any argument about how the
  mechanism is supposed to behave.
- Enumerate every writer of a contested shared resource (`grep -rn <THE_PATH_VAR>`) before
  concluding two actors "cannot collide". The collision is usually with an actor not in your
  comparison.
- When an onset resists attribution to any change, test "nothing changed and it never worked".
- Never delete a probe using a conclusion the probe was meant to test.
