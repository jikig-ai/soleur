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
