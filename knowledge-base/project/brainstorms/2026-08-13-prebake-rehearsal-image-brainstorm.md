---
date: 2026-08-13
topic: Remove the rehearsal containers' apt dependency
issue: 7535
branch: feat-prebake-rehearsal-image-7535
pr: 7540
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
---

# Brainstorm — remove the rehearsal containers' apt dependency (#7535)

## What We're Building

A **locally-built, never-published** container image for the git-data runcmd rehearsal
fixture. One `Dockerfile` beside the test installs `curl`, `python3`, `openssh-server` and
`e2fsprogs` in a single layer; `infra-validation.yml`'s `deploy-script-tests` job builds it
once and all eight container spins run on the local tag instead of apt-installing
individually.

No registry. No GHCR push, no zot mirror, no cosign signature, no digest-pin cadence entry.

The `ubuntu:24.04` **digest pin is split into its own change** (see Key Decisions D6) — it is
an independent correctness defect that this cycle merely surfaced, and it should land on its
own merits regardless of what happens to the apt cost.

## Why This Approach

The issue proposed three mechanisms: pre-bake-and-publish, `--network none`, or the shipped
in-place retry. Measurement moved the answer to a fourth the issue did not enumerate.

**The motivating number does not transfer to CI.** #7501's plan measured
`apt-get update && apt-get install -y curl python3` in `ubuntu:24.04` at **107.99 s** — on a
local host. On GitHub-hosted runners apt is Azure-mirrored. The whole rehearsal step measures
**110–119 s (n=6, mean ~114 s)**, so eight spins at 108 s (=864 s) is impossible. The issue's
value case is off by roughly an order of magnitude.

**Publishing buys almost nothing once the number is corrected.** Inline build collapses eight
apt cycles to one; a published image collapses them to a pull. The gap between those two is
~10 s/run — and it is the entire benefit publishing would purchase.

**Publishing costs are real and several are disqualifying:**

- **Fork PRs receive no secrets.** The rehearsal runs on `pull_request`. A zot-pinned or
  private-GHCR-pinned fixture makes the suite unrunnable for external contributors. Only a
  *public* GHCR image avoids this, which is a new public artifact surface.
- **zot is unreachable from a GitHub-hosted runner without a production credential** — the
  only path is the `cf-tunnel-registry-bridge` composite requiring prd-root-scoped
  `DOPPLER_TOKEN_PRD`. Handing a PR-triggered job a prd credential to fetch a test fixture is
  a security downgrade. The bridge is also `continue-on-error` ("a SECONDARY/shadow copy");
  a fixture pull is critical path and cannot be.
- **A published fixture image becomes a supply-chain trust anchor for the one test defending
  against poisoned artifacts.** T5 asserts a wrong-checksum download aborts before
  `chmod`+root-exec. Its assertions are satisfied by *any* early chain failure — expected rc
  is `1` under `set -e` over apt. A tampered image yields rc=1, the EXIT trap still emits
  `stage=doppler_dl`/`level=fatal`, and `CHMOD_RAN` is absent, so **T5 passes green while
  `sha256sum -c` was never evaluated.** Inline building keeps trust rooted in "Dockerfile in
  repo + digest-pinned base" — the same root the code already relies on.
- **Refresh has no cheap home.** New `scheduled-*.yml` files carrying `schedule:` are denied
  by `.claude/hooks/new-scheduled-cron-prefer-inngest.sh`, so a rebuild cron would bolt onto
  `rule-audit.yml`'s bi-monthly cron — a mechanism built for the zot binary pin, made to carry
  an unrelated second consumer. Inline rebuilds every run, so staleness is structurally
  impossible.

**Inline is already the house pattern in this exact job.** `deploy-script-tests` builds an
alpine+bubblewrap image inline today (`infra-validation.yml:415-419`), and the workflow
records the convention that an image-building step carries its own `timeout-minutes` "for
attribution — a cold-pull stall names that step instead of cancelling the job at an unrelated
one."

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Build inline in `infra-validation.yml`; **never publish** | Publishing buys ~10 s/run and owes a permanent artifact, fork-PR breakage, and a new trust anchor |
| D2 | One image covering **all six code sites / eight spins** | Three package sets, not one — a curl+python3-only image leaves two sites mirror-dependent |
| D3 | **Do not** convert any site to `--network none` in this change | T5's recorded rationale has a second reason pre-baking does not dissolve (below) |
| D4 | Do not touch #7501's retry logic | Separate PR, actively in flight on PR #7507 |
| D5 | Sequence implementation **after PR #7507 merges** | #7507 is editing this same file; it bounds the R4 site |
| D0 | **Delete the `e2fsprogs` site (`:872-873`) outright** | `ubuntu:24.04` already ships `e2fsprogs 1.47.0-2.4~exp1ubuntu4.1`, the exact version `fingerprint.txt:57` pins — the apt cycle is a no-op. Free, and independent of #7507 |
| D6 | ~~Split the digest pin into its own issue as an independent correctness fix~~ **REVISED** — pinning is contraindicated for R1 | R1(a) is calibrated *against* drift and currently detects an upstream `e2fsprogs` bump; pinning removes that detector. #7544 corrected and retitled; the defensible remainder is a `mke2fs -V` assertion |
| D11 | Build **in the test**, not in the workflow | `sandbox-canary-regression.test.sh:162-168` is the closer precedent — inline Dockerfile + `docker build -q` guarded by `docker image inspect`; keeps the suite runnable locally with no workflow-step coordination |
| D7 | Re-derive `deploy-script-tests`' `timeout-minutes: 8` budget | The workflow explicitly requires this when steps are added |
| D8 | Guard against silent fallback to `ubuntu:24.04` | A missing local image must fail loudly, not quietly re-acquire the apt dependency |
| D9 | Rewrite the networking note at `git-data-runcmd-rehearsal.test.sh:532-537` | It is the recorded rationale the change partially invalidates; leaving it stale misleads the next reader |
| D10 | Exempt from the 2026-08-04 zot pin/freshness cadence | There is no published pin to keep fresh |
| Visual design | N/A — no UI surface | Pure CI/test-fixture change |

### Premise corrections carried from the issue

Four claims in #7535's body did not survive probing; all four are recorded on the issue
([comment](https://github.com/jikig-ai/soleur/issues/7535#issuecomment-5281420605)):

1. **#7501 is OPEN and its mitigation is not on `main`.** `-o Acquire::Retries=3`, the
   3-attempt loop and `fixture_fail` exist only on draft PR #7507, where they bound **one** of
   the six sites. On `main` all six are the plain un-rc-checked form.
2. **This issue's re-eval trigger cannot have fired** — it requires `FIXTURE-FAIL: apt-get`
   "in a CI run after #7501 lands", and #7501 has not landed.
3. **Six sites span three package sets**, not one: 4× `curl python3`, 1× `openssh-server`,
   1× `e2fsprogs`.
4. **Pre-baking only half-invalidates the `--network none` rationale.** That rationale
   (`:532-537`) gives two reasons; pre-baking dissolves only "the image needs curl and python3
   from apt". The second — *"With real network T5 is also MORE faithful — it downloads the
   genuine tarball and then fails the checksum, which is exactly the supply-chain case being
   defended against"* — is independent of how the tools arrive.

### Corrected measurements

| Quantity | Issue's value | Measured value | Method |
|---|---|---|---|
| Container spins per run | "six sites" | **8 spins from 6 code sites** | `run_case` ×2 (`:587`,`:636`), `_s1_run` ×2 (`:729`,`:762`), + `:611`, `:647`, `:891`, `:1133` |
| Rehearsal step wall time | ~11 min implied | **110–119 s, mean ~114 s** | `gh api .../jobs`, step `Rehearse the git-data runcmd chain`, n=6 green runs |
| apt cost per cycle | 107.99 s | **~10–15 s on CI** | Derived: 8 cycles cannot exceed the 114 s step |
| Run frequency | not stated | **~277/week (upper bound)** | 100 runs in 2.53 days, `gh run list -L 100` |
| Expected saving | ~11 min/run | **~50–80 s/run ≈ 4–6 runner-hours/week** | Estimate — see Open Questions Q1 |

## Open Questions

**Q1 — What is the actual apt share of the 114 s step? (blocking the value case)**
Nobody has instrumented it. The 50–80 s estimate is a decomposition inferred from the step
total, not a measurement. The whole justification rests on this number, so the plan's first
task is to measure it — time the eight apt cycles inside one CI run before committing to the
change. If apt turns out to be ~30 s of the 114 s, the saving does not justify even a
Dockerfile.

**Q2 — Does pre-baking reduce what the rehearsal proves? — ANSWERED: no, it moves the fixture
toward the target.**
The real target already has these packages at runcmd time. `cloud-init-git-data.yml:11-16`
lists only `git, util-linux, cryptsetup, curl` under `packages:`; `python3`, `openssh-server`
and `e2fsprogs` are absent because the Hetzner Ubuntu 24.04 **server** image ships them — S1's
own comment (`:659-662`) confirms ssh is preinstalled and socket-activated. The fixture's apt
only restores what Docker's *minimal* `ubuntu:24.04` stripped.
`2026-07-03-faithful-canary-capture-must-run-in-the-deploy-base-image.md` therefore cuts **for**
pre-baking (capture-env == replay-env), but sharpens the spec: define the image as *the target
cloud image's package set*, not *whatever the six apt lines name* — otherwise the fixture
becomes a third environment that is neither. Carried into the spec as TR2.

**Q3 — Does digest-pinning disturb R1? — ANSWERED: yes, it removes a live detector.**
`git-data-birth-fs-fingerprint.txt:21-22` and `:84-85` record that `e2fsprogs >= 1.47.1` emits
`orphan_file`/`metadata_csum_seed` and 1.47.0 does not. R1(a) is calibrated *against* the
floating tag, so it currently **detects** the upstream bump. Pinning freezes 1.47.0 and removes
that, leaving only `R1-EXPIRY` (`:1007-1010`) — a wall-clock date deliberately outside the
pass/fail path. This **reverses decision D6's framing**; #7544 has been corrected and retitled
accordingly, with the defensible remainder being an explicit `mke2fs -V` vs `fingerprint.txt:57`
assertion that converts drift into a named failure.

**Q4 — New, from the late CTO assessment: the `/run` persistence class.**
Docker layers persist build-time `/run` writes; the real host boots a fresh tmpfs `/run`. That
is S1's load-bearing precondition — its mutation (`:768-775`) depends on `sshd -t` failing with
`Missing privilege separation directory`. A runtime install does not currently leak
`/run/sshd`, but a build-time one could. Spec TR3 requires asserting `! test -e /run/sshd`.

**Q4 — Vacuous-green regression risk.** Several institutional learnings warn that changing a
fixture's base can make tests pass without exercising the mechanism. The plan must include a
mutation check: break the image deliberately and confirm each of T5/T17/S1/R1/R4 still fails.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** Platform-strategist recommends inline-build-never-publish and resolves the
registry question decisively — zot is unreachable from a GitHub-hosted runner except via a
prd-root-scoped credential, and fork PRs receive no secrets at all, so only a public GHCR image
would work. It further identifies that a published fixture image would become a trust anchor
for T5, the very test defending against poisoned artifacts. The CTO assessment did not return
before write-up; Q2 is the gap it would have covered.

### Product

**Summary:** CPO recommends **do less than asked** — the stated re-eval trigger provably has
not fired, and the motivating 107.99 s measurement is a local figure that does not transfer to
CI (measured: 110–119 s for the entire step). Recommends the inline build as the increment that
captures most of the value with zero durable artifact, and notes #7501's R3/R4 flake is a
bounded-poll/CPU-contention defect, not an apt-availability defect — so pre-baking is not a
substitute for #7501.

### Legal

**Summary:** Not a legal-threshold matter. Private/internal use is not redistribution, so no
GPL/LGPL obligation attaches; the inline-build decision removes the question entirely since
nothing is published. No Article 30 row, no new sub-processor, no new spend, no outside
counsel. Had publishing gone ahead publicly, one `THIRD-PARTY-NOTICES` file would have
satisfied GPLv2 §3(b), and the repo should not have invented an SBOM bar its existing image
workflow does not meet.

## Capability Gaps

None. Every mechanism this design needs already exists in the repo:

- Inline image build in this exact job — `infra-validation.yml:415-419` (verified by read)
- `timeout-minutes` attribution convention for image-building steps — `infra-validation.yml:474-476`
- Dependabot `docker` ecosystem can manage a committed Dockerfile's digest — established in
  `knowledge-base/project/plans/2026-08-04-chore-zot-image-pin-bump-and-freshness-cadence-plan.md`.
  Caveat: no repo `dependabot.yml` exists today, so enabling it would be a small added
  deliverable in the D6 follow-up.

## Session Errors

1. **Routing carried a false premise.** The `/soleur:go` routing args asserted #7501's retry
   "already merged". It had not; #7501 is OPEN and the mitigation lives only on draft PR #7507.
   Caught by the Phase 0 pre-worktree premise probe before any leader spawned.
2. **Two subagent claims were wrong and would have shaped the design.** repo-research reported
   five "critical" sibling guards that would break — they target `cloud-init.yml` (the
   production template), not the fixture, so pre-baking cannot affect them; and it reported the
   R4 site has "no explicit apt" when `r4-drive.sh` apt-installs `curl python3`. It also
   estimated 2–5 runs/week against a measured ~277.
3. **A leader's arithmetic outlived its refuted input.** Platform-strategist built a cost table
   on the 108 s figure after that figure had been disproved for CI, yielding "864 s/run" against
   a measured 114 s. Its *conclusion* was independently sound and survives; only the arithmetic
   was discarded.
