# Decision Challenges — feat-one-shot-7068-orphan-infra-suites

Recorded by `plan-review` in headless mode (ADR-084 routing: Taste / User-Challenge findings are
surfaced, never silently applied). `ship` Phase 6 renders these into the PR body and files an
`action-required` issue.

Panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
architecture-strategist, spec-flow-analyzer, cto (6 agents, run in parallel 2026-07-29).

---

## DC-1 — Should the PR include Phase 3 (a new fail-closed registration gate)? `decisionClass: taste`

**The operator's stated criterion 3** is "the orphan-detection mechanism itself is unchanged **or
strengthened**". "Unchanged" alone satisfies it, so Phase 3 is elective — which is why this is
surfaced rather than auto-applied.

**Reviewers split, and the split is substantive — not a misunderstanding.**

- **Against (dhh, code-simplicity):** the irreducible core of #7068 is seven `run:` lines plus one
  stale-comment rewrite, in one file. Anything beyond that is scope creep on a chore, and #7068
  itself exists *because* someone obeyed `wg-when-an-audit-identifies-pre-existing` instead of
  folding an unrelated finding into a PR. code-simplicity: "it fixes nothing that risks anything."
- **For (cto):** without it, this is "the third manual cleanup of a generator that is still
  generating" (#7000 left seven → #7025 surfaced them → #7068 cleans up). The prevention the
  2026-06-16 learning records is a *human habit* ("grep the enumerator and add yourself"), and that
  habit has now failed three times. The gate is ~40 lines of bash into an **existing** required
  auto-glob: no new required-check name, no `ruleset-ci-required.tf` or
  `scripts/required-checks.txt` edit, no apt (so #6454 is not tripped), and it starts green.
  spec-flow independently reached the same place from the other direction, noting the detector's
  basename scan is a bare-token proxy that stays comment-satisfiable forever otherwise.

**Plan currently includes it** (Phase 3), on the grounds that it is additive, starts green,
requires no ruleset work, and is what makes the PR fix the *class* rather than the instance.

**If the operator prefers minimum scope:** drop Phase 3 and AC7, and fold its rationale into the
D1 follow-up issue. Criterion 3 is still met by the "unchanged" branch. Nothing else in the plan
depends on Phase 3.

---

## DC-2 — Phase 3's placement implies a policy, not just a script `decisionClass: taste`

Landing the gate in the `.github/scripts/test/test-*.sh` glob makes **infra-suite registration** a
blocking, merge-queue-gating property of every PR in the repo — while the suites' own *verdicts*
remain advisory (that promotion is #6480's, D2). That asymmetry is deliberate and defensible
("registration is blocking, verdicts are advisory"), but it is a policy choice the operator may
want to make explicitly rather than inherit from a plan.

Note it cannot deadlock the queue: the gate is bash-only per that glob's documented contract, and
it starts green because Phase 1 drives the orphan set to zero.

---

## Resolved during review — recorded for the PR body, no operator decision needed

These were reviewer findings that were **verified and applied**, not judgment calls:

1. **An AC that passed on the untouched repo.** The original AC2
   (`--list | grep -cE '^  apps/…'`) returned `7` on clean `main` because `report_orphans()`
   prints with the *same two-space indent* as the derived list. Three reviewers found it
   independently (kieran P0-1, spec-flow P0-1, code-simplicity). The detector's own test documents
   this exact trap. **Cut** and replaced with a job-scoped step grep, verified RED against `main`.
2. **A fabricated citation.** An earlier draft justified ~half its scope as
   `AC3 "unchanged or strengthened"` attributed to issue #7068. The issue has **no acceptance
   criteria at all** (dhh P0-1). The criteria are the operator's task framing; the plan now says
   so explicitly.
3. **A guaranteed local-gate regression, mis-diagnosed as its opposite.** The proposed detector
   widening would have added `workspaces-luks-loopback.test.sh` — which exits **2** unprivileged
   by design — to the local runner's execute set, turning a mandated ship gate permanently RED for
   any operator without passwordless sudo. The draft called it a possible false *green*
   (code-simplicity, architecture P0-1, spec-flow P0-3, cto Finding A). **Deferred to D1** with the
   corrected analysis.
4. **A flake the PR would have introduced.** `cloud-init-plugin-seed.test.sh` uses fixed docker
   container/image names with `docker rm -f`/`rmi -f` in its EXIT trap; registration puts it in the
   local `xargs -P 6` runner, where two concurrent worktree runs would kill each other's container
   (architecture P2, cto Finding B). Phase 2 now `$$`-scopes them.
5. **A dual-mode flag replaced by a call-site assertion.** The draft's `REQUIRE_DOCKER=1` opt-in
   left the fail-closed guarantee in one workflow step's `env:` and kept the unsafe path as the
   default (cto §4, dhh P1). Replaced by a separate preceding `docker info` step — one code path,
   and *separate on purpose*: folding it into the suite's step would make it a multi-line
   `run: |`, which the derivation regex cannot match, silently re-orphaning the suite.
6. **Wrong denominator and a mis-cited anchor.** "~79 registered suites" → **87**; the job's
   container build is at the sandbox-canary **regression** step, not `sandbox-canary-soak.test.sh`
   (kieran P2). Both corrected, since the "no new class of dependency" argument rests on them.
7. **An instruction the plan was about to violate.** The job's timeout comment says "Re-derive this
   if steps are added to the job" (architecture P1-5, spec-flow P1-8). Now in Files to Edit.

---

## Resolutions (operator, 2026-07-30)

- **DC-1 — RESOLVED: include Phase 3.** The operator elected the strengthen branch of criterion 3
  over the "unchanged" branch. Rationale accepted as stated: additive, starts green, lands in an
  existing required auto-glob (no new required-check name, no `ruleset-ci-required.tf` /
  `scripts/required-checks.txt` edit, no apt), and it fixes the class rather than the instance —
  the human habit the 2026-06-16 learning records has now failed three times. Plan already
  includes Phase 3 + AC7; no plan edit required.
- **DC-2 — RESOLVED as an explicit policy choice, not inherited from the plan.** The operator
  accepted the asymmetry: **infra-suite registration is blocking** and merge-queue-gating for every
  PR in the repo, while the suites' own **verdicts remain advisory** (that promotion stays with the
  pre-existing open issue on advisory→blocking, tracked as D2). Recorded here so the policy is
  attributable to a decision rather than to a plan default.

---

## Implementation-time corrections (not plan defects)

### IC-1 — my own Phase 3 gate shipped the hole it existed to close

The first version of `test-infra-suite-registration.sh` anchored on `(sudo )?bash <path>` appearing
anywhere in a non-comment line. That accepts a **multi-line `run: |` block** — so converting a
registered step to that form passed the gate while silently de-registering the suite from
`run-registered-suites.sh`, whose derivation is single-line-only. Since that runner is where the
plan's own two-consumer table locates the teeth, the gate would have blessed exactly the
regression it was built to prevent.

Reading the gate did not reveal this. The **mutation battery** did, on mutation M5. Corrected to
assert the single-line `^[[:space:]]*run: bash <path>$` shape, with the two failure modes reported
distinctly (not-registered vs registered-but-not-derivable) because they have different fixes.

Recorded because the plan's Phase 3 spec said "assert a real invocation step exists", and the
literal reading of that spec is what produced the hole. The spec was not wrong; it was
underspecified, and only mutation testing distinguished the two readings.

### IC-2 — `ci-deploy.test.sh` RED in the parallel infra run is not this diff's

The first full `run-registered-suites.sh` run reported `RED ci-deploy.test.sh` (85 PASS / 1 RED of
86). Provenance established mechanically rather than by re-running until green:

- `git diff origin/main...HEAD` shows this branch modifies **neither** `ci-deploy.test.sh` nor its
  subject `ci-deploy.sh`.
- `ci-deploy.test.sh` reads **none** of this branch's four changed files. Its single
  `infra-validation.yml` mention is prose in a comment at line 3129, not a file read.

So the suite and its subject are byte-identical to `main` and it reads nothing changed here. The
run also happened under a measured load of **28 on 16 cores**, with a sibling session running the
same 6-way-parallel runner from another worktree — the documented contention/false-RED condition.
Re-measured on a quiet machine; see the PR body for the disposition. Either way it is not
attributable to this diff, and per `wg-when-tests-fail-and-are-confirmed-pre` it is documented
rather than folded in.

---

## Review findings (2026-07-30)

Cost-of-filing pass applied to every candidate: all were ≤100 lines / ≤4 files with no
independent technical dissent, so **all fixed inline. Filed as scope-out: 0.**

### RF-1 (P2, pr-introduced, fixed) — the gate false-failed a legitimate trailing comment

The gate anchored on `[[:space:]]*$`, rejecting `run: bash <path>  # note`. But the runner
derives with an unanchored `grep -oE`, so it DOES pick that line up — the suite genuinely runs
in CI and locally. A required, merge-queue-gating check would have red-failed every PR in the
repo on an ordinary comment, while its message asserted the runner "cannot derive it", which is
false. Now permits an optional trailing `#` comment; message corrected. Deliberately not widened
to `&& cmd` / `| cmd` — the runner tolerates those, but they make CI diverge from the local run.

### RF-2 (P2, pr-introduced, fixed) — fail-open in the exclusion arm, introduced by the exclusion

The exclusion waived ANY registration requirement rather than just the shape, so deleting the
excluded suite's invocation outright stopped it running in CI with the gate still green
(measured: rc=0). An excluded suite must now still be invoked in some shape.

### RF-3 (fixed) — a projected job duration my own CI run contradicted

The re-derivation comment projected ~204s; three runs measure 252-270s. The 8 added steps cost
**8s** (API-measured), so the increment was fine — the error was adding it to the comment's
inherited 184-189s baseline, taken from a different branch at a different job composition
(~70s of unrelated growth since). I applied "re-derive, don't extrapolate" to the suite timings
and then failed to apply it to the number I inherited.

### RF-4 (P2, pre-existing-adjacent, fixed) — orphan-reporter misattribution

Header read "#7025 surfaced them", which reads as though #7025 built the detector. The reporter
landed in `2f46570c1` (#6730); #7025 is where the seven were noticed and filed. Surfaced by
`git-history-analyzer`. A false attribution in the file whose subject is untrue comments would
be self-undermining.

### RF-5 (deferred to #7076 by comment, not a new filing) — the runner already derives comments

#7076's Finding 4 called the comment-derivation hazard "a future hazard, not a present one".
Measured: the runner's regex is not line-anchored, so `# run: bash <path>` matches TODAY and
would flow into the executor. Zero such lines exist, so no live gap — but the fix repairs a
latent defect rather than pre-empting a future one. Commented on #7076 with the measurement.

### Method note (the transferable part)

The first equivalence run was **void and looked fine**: the sandbox was not a git repo, the
runner does `cd "$(git rev-parse --show-toplevel)"`, so it exited immediately and every row read
"no derivation" — including the canonical control. A control row that cannot succeed makes every
other row meaningless. Re-ran with `git init` and required the control to derive before believing
any row. RF-1 and RF-2 are both invisible without that.

Also: my own 6/6 mutation battery reported the gate healthy through RF-1 and RF-2. It measured
the mutations I imagined, not the gate.

### Review coverage, stated honestly

A persistent API overload (529) killed **12 of 13** agent attempts (9 initial + 3 retries).
`git-history-analyzer` completed and produced RF-4. The adversarial-construction and
gate-vacuity lenses were run INLINE, which is where RF-1/RF-2/RF-3 came from; destructive-op and
parallel-safety claims were verified directly (cutover-flip mocks in a `mktemp -d` with
`redis-cli` absent from PATH; the flip-guard non-vacuity guard confirmed stronger than claimed —
an `EXPECTED_START_SITES=2` count latch plus an explicit `grep -qx 'flushed'`). shellcheck clean
at `-S style` on all three bash files; semgrep deliberately substituted out (its bash parser
matches ~0 rules, so a clean result would be vacuous).

Lenses NOT covered by an agent: pattern-recognition, performance (measured inline instead),
observability (verified inline: the gate's non-zero exit reaches a red check via run-all.sh),
agent-native, simplicity. Recorded rather than implied-complete.
