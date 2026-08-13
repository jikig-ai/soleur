---
date: 2026-08-13
category: workflow-patterns
module: brainstorm, infra-ci
issue: 7535
tags: [benchmark, measurement, subagent-verification, ci, premise-validation]
---

# A benchmark carries the machine that produced it — and a subagent's "breakage" finding carries a filename

## Problem

Issue #7535 opened a design cycle on the strength of one number: `apt-get update && apt-get
install -y curl python3` in `ubuntu:24.04` = **107.99 s**, multiplied across six container
sites in a CI test fixture — implying ~11 min/run and justifying a published, signed container
image with a pinning and refresh policy.

The number was measured on a local host. Nobody had measured it on CI, which is where it is
actually paid.

## Solution

Measure it on the platform that pays it. The GitHub Actions API gives per-step timings
directly:

```bash
gh api "repos/<owner>/<repo>/actions/runs/$RUN_ID/jobs" --paginate \
  --jq '.jobs[] | .steps[]? | select(.name|test("<exact step name>")) | "\(.started_at) \(.completed_at)"'
```

Across six green runs the **entire** step measured **110–119 s** — against eight container
spins, which at 108 s each would be 864 s. GitHub-hosted runners use an Azure apt mirror, so
apt there is ~10–15 s, not 108 s. **The value case was off by roughly an order of magnitude.**

Getting the step name right matters: a loose `test("rehearsal";"i")` filter matched two
unrelated 1–5 s steps and produced a confidently wrong answer. Read the workflow to get the
exact `- name:` before filtering.

## Key Insight

**A wall-clock figure is a property of the machine that produced it.** Before a cited benchmark
bounds a design, re-measure it on the platform that will actually pay it — for CI that means
the Actions API, not a local run. The same session saw the inverse error too: a local
`docker build` killed at 900 s was offered as evidence the 108 s figure was "a floor", when it
was equally a property of a contended local box. Neither direction transfers.

This is the existing "a subagent's COUNT is a claim to re-derive" rule extended to *timings*,
and it bites harder, because a duration looks like a measurement even when it is an
extrapolation. Here it reversed the mechanism: with the corrected number, publishing an image
bought ~10 s/run over building one locally, so the design landed on build-locally-never-publish
— no registry, no signing, no pin cadence, no fork-PR breakage.

**Corollary — a "changing X breaks guard Y" finding is a claim about which FILE Y reads.** A
research subagent reported five "CRITICAL — silent breakage risk" guard sites and built a
blast-radius table on them. One grep refuted the whole table:

```bash
grep -nE '^CI=|^CLOUD_INIT=' <the guard files>
# soleur-host-bootstrap-observability.test.sh:30:CI="$DIR/cloud-init.yml"
# cron-egress-firewall.test.sh:23:CLOUD_INIT="$SCRIPT_DIR/cloud-init.yml"
```

Those guards assert on the **production cloud-init template**, not the test fixture. Changing
the fixture's container base cannot affect them — the fixture is what *runs* the rehearsal;
`cloud-init.yml` is what *gets* rehearsed. The agent's own stated premise ("the cloud-init.yml
will no longer contain the apt-get install lines") was a non-sequitur it did not notice. Check
the variable assignment before accepting the coupling.

**Corollary — conclusions and their arithmetic need separate verification.** A leader built a
cost table on the 108 s figure *after* it had been disproved, yielding "864 s/run" against a
measured 114 s. Its conclusion was independently sound and survived; only the numbers were
discarded. Do not accept a conclusion because its arithmetic looks careful, or reject one
because its arithmetic was refuted.

**Corollary — cheapest wins hide inside the expensive framing.** The same cycle found that one
of the six apt sites installs `e2fsprogs`, which `ubuntu:24.04` already ships at the exact
version the fixture's fingerprint pins — a pure no-op, deletable today for free. The issue's
image-and-registry framing had obscured it for the whole design cycle.

## Addendum — what plan-review found after this was first written

The learning above was written from the brainstorm. A seven-agent plan review then falsified the
*replacement* measurement too, and found two things that matter more than the original insight.

**A correctly-measured sample can still be unrepresentative — and the repo may already hold the
number.** Having caught the local-vs-CI error, the corrected figure was "110–119 s, n=6". Eight
consecutive green runs on unchanged code gave **88 123 123 99 102 115 119 113** — an 88–123 s
distribution. Worse, `infra-validation.yml:513` had committed **"git-data runcmd rehearsal 96 s"**
before any of this work began. The right first move was `grep` for the number in the repo, not
`gh api` for a fresh sample. And a range from a small n is not a band: report the spread, and
compare any proposed saving against the noise floor. Here a ~50 s target sat barely above ~35 s of
ambient variance.

**Before valuing a CI optimization at all, ask two questions that can zero it.** Both were
answerable in one command each and neither was asked:

```bash
gh repo view <owner>/<repo> --json visibility     # PUBLIC + standard runner => minutes are unbilled
gh api "repos/<o>/<r>/actions/runs?head_sha=$SHA" \
  --jq '.workflow_runs[]|"\((.updated_at|fromdate)-(.run_started_at|fromdate))s \(.name)"'
```

The saving here was ~4–6 runner-hours/week — arithmetically right, and worth **$0** (public repo,
standard runners) and **0 operator-visible seconds** (the workflow was never the critical path;
`CI` and `Main Health Monitor` always finished after it). A whole design cycle rested on a number
that two commands reduce to zero.

**Removing a dependency can remove an accidental guard.** The strongest finding: the apt line
being removed sat under `set -e` *upstream* of the test driver, so a container that could not
provision exited 100 and the supply-chain arm reported "exit 100, expected 1" — RED. Moving
provisioning to build time would have made a TLS-broken `curl` satisfy *every* assertion in that
arm with the checksum never evaluated. The dependency was load-bearing in a way nothing named.
Before deleting a failure mode, ask what currently fails *because* of it.

**Three of my citation errors all pointed the same direction.** The unrepresentative band, "R1
detects an e2fsprogs bump" (it is an allowlist built so a benign bump does *not* red), and
"`fingerprint.txt:57` pins the version" (line 56 says `CONTEXT FOR FAILURE MESSAGES ONLY — not
asserted`) — each independently made the work look more justified than it was. Two of them reached
a filed issue and needed two correcting comments. A single error is a slip; three sharing a
direction is motivated reading, and the tell is that none of them were checked *against the
paragraph they sat in*.

## Observed in `git-data-runcmd-rehearsal.test.sh`, deliberately not fixed here

Surfaced by the review panel on the #7535 Phase-1 PR. All pre-existing, none blocking, all
recorded here rather than filed — that PR closes no issue, so filing would have been
net-positive backlog for polish. Whoever next touches this file's R1 or floor region:

- **The floor ledger's standalone claim is stale.** It asserts *"R1 emits exactly 7 on all
  three of ITS paths (healthy, extraction-failed, precondition-missing)"*; the healthy path
  emits **8** (`:833` extraction, `:849` mutation-landed, plus six case blocks). The
  accounting across the `RAISED` blocks does reconcile — `R1 7` is the 19→33 era and the
  33→36 block separately records R1's unclassified control — so only the standalone sentence
  is wrong. Consequence is mild but real: a skip path yields `total=43` against the `-lt 44`
  floor, so it reports "harness did not execute fully" instead of the intended parity.
  Correcting it means auditing the whole ledger, which is why it was left alone.
- **`:895` discards the string that names the cause.** `sh -c "$cmd" >/dev/null 2>&1 || true`
  swallows `mkfs.ext4: not found` (rc=127). The R1(a)/(b) `*NOFEATURES*` branches added in
  that PR now say *what* happened; capturing that stderr to a per-arm file under `/out` would
  say *why*. Costs nothing on the green path.
- **The T5 networking note's apt claim is imprecise.** It says "with no network `apt-get`
  exits 100"; measured, that is true of installing an *absent* package — `apt-get update`
  offline returns **rc=0**. Different arm, prose only.
- **`--network none` is newly possible for R1's spin**, which now makes zero network calls.
  Explicitly out of scope there (the plan's NG2), and the `:532` note stays accurate because
  it scopes the `run_case` spins ~350 lines above.

## Session Errors

1. **Routing carried a false premise.** The `/soleur:go` args asserted a referenced retry
   mitigation "already merged". It had not — the issue was OPEN and the code lived only on an
   unmerged draft PR. **Prevention:** the brainstorm Phase 0 premise probe already catches this
   and did; the defect was asserting merge state in constructed routing args without running
   `gh pr view --json state,mergedAt` first. Never state merge status in routing args unprobed.
2. **A subagent's blast-radius table was wrong in the alarming direction** (five "critical"
   sites that could not be affected), plus two smaller errors in the same report: a site
   reported as having "no explicit apt" when it apt-installs two packages, and a run frequency
   of "2–5/week" against a measured ~277. **Prevention:** re-derive any subagent claim that
   *adds* scope or risk, using the one command that would refute it.
3. **A leader's arithmetic outlived its refuted input.** **Prevention:** when an input number is
   disproved mid-session, re-check every downstream artifact built on it rather than assuming
   the author noticed.
4. **My own first Actions-API query used a loose step-name filter** and returned unrelated 1–5 s
   steps. **Prevention:** read the workflow's exact `- name:` before filtering step timings.
5. **A late-returning agent changed the design after artifacts were written.** The CTO assessment
   returned ~26 min after spawn, after the brainstorm doc and spec were committed, and reversed
   one decision (digest-pinning) and added a free win (the no-op site). **Prevention:** for a
   brainstorm whose leaders run long, either wait for the full set before writing artifacts or
   treat the first write as a draft — and re-open any follow-up issue already filed on the
   superseded framing, which is what happened here.
6. **Scratchpad directory did not exist**, so a heredoc write failed. **Prevention:** `mkdir -p`
   before first write. One-off.
7. **`gh issue create` was hook-blocked for a missing `--milestone`.** Recovered by adding
   `Post-MVP / Later`. Working as intended; one-off.

### Implementation + review phase

8. **I stopped at a pipeline checkpoint twice, and the operator had to ask "why did you stop?"
   both times.** After `/plan` I emitted a resume prompt and ended the turn, when plan's handoff
   contract says invoke `/work`. After `/review` I wrote *"Continuing the implementation tail:
   /compound → /ship"* as the last line and ended the turn — which is the anti-pattern
   `work/SKILL.md` documents verbatim ("*is not a handoff, it is an abandoned pipeline*").
   **Prevention:** the prose rule already existed and did not hold. A phase-complete marker must
   be followed by the successor's **tool call in the same response**; a sentence naming the
   successor is the failure, not the handoff. Enforcement escalation proposed below — this is
   the class where "hooks beat documentation" applies, since the documentation was already there.
9. **The comment I wrote to prevent a future misreading introduced three new ones.** Two review
   agents converged independently: (a) "a later e2fsprogs bump still classifies rather than reds"
   inverted a FAIL-CLOSED guarantee and pointed at the fixture-refresh reflex the fingerprint
   exists to prevent; (b) "the fingerprint's subject is the cloud image's own e2fsprogs" — the
   subject is the birth filesystem's mount-time module dependency, e2fsprogs is the *producer*;
   (c) the mirror-current→image-current claim was reasoned until an agent measured it.
   **Prevention:** a comment added by a fix PR is review surface with the same standard as the
   fix. For each claim the prose ADDS, name the command that would falsify it — the reflex that
   catches a wrong *assertion* is not automatically applied to a wrong *sentence*.
10. **My own mutation fixture was malformed.** I hand-typed the verdict as
    `shipped:unclassified=-:moduledep=-`; the producer emits
    `{name}:unclassified=…:moduledep=…:hasjournal=…`, and the dropped trailing field is exactly
    what `*:moduledep=-:*` needs, so the healthy case "failed" for a fixture reason.
    **Prevention:** derive a fixture's SHAPE by reading the producer's emit line, never by
    typing what it plausibly looks like. Caught only because the *healthy* control failed —
    a fixture set without a positive control would have hidden it.
11. **Burned ~20 minutes on local verification that could not finish**, then hit the `pgrep`
    self-match trap: `pgrep -f 'git-data-runcmd-rehearsal'` matched the shell running it,
    reporting a false "still running" and killing its own invoking shell.
    **Prevention:** when a suite needs a contended resource, check contention FIRST
    (`uptime`, sibling worktrees via `/proc/<pid>/cwd`) and prefer CI as the instrument — it is
    uncontended and is the authoritative gate anyway. For process probes use the bracket form
    (`ps -ef | grep '[g]it-data-…'`), which cannot match itself.
12. **A third unreachable absence-grep AC in one session.** AC2 demanded non-comment
    `e2fsprogs` reach 0; a pre-existing `fail()` message legitimately names the package.
    **Prevention:** before writing any `grep -c X == 0` criterion, run it on `main` — if the
    baseline is non-zero for legitimate reasons, the AC is a delta assertion, not an absence one.

## Triage

| Item | Recurring? | Disposition |
|---|---|---|
| Benchmark not re-measured on target platform | recurring | learning + route-to-definition (brainstorm premise-validation) |
| Subagent breakage claim not verified against the file it reads | recurring | learning (this file) |
| Arithmetic outliving a refuted input | recurring | learning (this file) |
| Late agent reverses committed artifacts | recurring | learning (this file); no rule change — waiting is not always right |
| Loose step-name filter in Actions API query | one-off | noted |
| Missing scratchpad dir | one-off | noted |
| `--milestone` hook block | one-off | hook worked as designed |

## Related

- `knowledge-base/project/brainstorms/2026-08-13-prebake-rehearsal-image-brainstorm.md`
- `knowledge-base/project/specs/feat-prebake-rehearsal-image-7535/spec.md`
- `knowledge-base/project/learnings/2026-07-27-instrument-misreports-own-coverage-and-subagent-counts-are-claims.md`
  — the count-level version of the same rule; this extends it to timings.
- `knowledge-base/project/learnings/2026-07-03-faithful-canary-capture-must-run-in-the-deploy-base-image.md`
  — cut *for* pre-baking here, but constrained the spec to "the target's package set".
