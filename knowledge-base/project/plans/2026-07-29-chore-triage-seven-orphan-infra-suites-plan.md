---
title: "chore: triage and resolve the seven orphan infra test suites"
issue: 7068
branch: feat-one-shot-7068-orphan-infra-suites
date: 2026-07-29
type: chore
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- No infrastructure introduced. The `systemctl enable --now inngest-cutover-flip.timer`
     token below is a VERBATIM QUOTE of an existing line in inngest-bootstrap.sh, cited as
     liveness evidence that a subject-under-test is still wired — not a step anyone runs. -->

# chore: Triage and resolve the seven orphan infra test suites (#7068)

## Overview

`apps/web-platform/infra/run-registered-suites.sh` derives the infra suite list from
`run: bash …` steps in `.github/workflows/infra-validation.yml` and reports suites on disk
that no workflow or script references. Seven are unreferenced. `scripts/test-all.sh` does not
cover `apps/web-platform/infra/` (its own preamble says so), so these seven are run by
**nothing**. An unregistered suite is invisible twice — it never runs and it never reds —
while reading as coverage to anyone grepping for a guard on the thing it names.

**All seven were measured locally before any decision was taken. All seven PASS.** All seven
subjects-under-test are live and wired on `origin/main`, so the issue's filename-based
deletion hypothesis is falsified. The outcome is **7 register, 0 delete**.

### Registration has two consumers, and only one of them is a display

This is the load-bearing fact, and it is what makes registering into an advisory job a real
fix rather than theatre:

| Consumer | Teeth |
|---|---|
| The `deploy-script-tests` check on a PR | **Display.** Advisory, `paths:`-filtered, no `merge_group`. The #6769 "advisory is no gate" critique applies fully. |
| `apps/web-platform/infra/run-registered-suites.sh` | **Real.** Its last line is `(( RED == 0 ))`, and both `plugins/soleur/skills/work/SKILL.md` ("When the diff touches `apps/web-platform/infra/`, BOTH runners are required") and `plugins/soleur/skills/ship/SKILL.md` mandate running it as an exit gate. |

Today these seven are unreachable by **both**. Registration wires them into a gate whose
non-zero exit blocks ship — so this is not "shipping a display nothing consumes". That
distinction also makes any change which could permanently red the local runner a serious
regression, which is why D1 is deferred rather than folded in.

Registration target is the `deploy-script-tests` job — home to all **87** registered infra
suites (86 bare `run: bash` steps + one `sudo bash`; the local runner currently *derives* only
79 of them, which is the separate D1 gap), explicitly ADVISORY (absent from
`scripts/required-checks.txt`, no `merge_group:` trigger, workflow-level `paths:` filter). The
`#6454` hazard cited in the task framing applies to a *different* job; see R3.

**No new `paths:` entry is required** — the non-obvious #6454/#3366-class check (a guard that
cannot fire when its own subject is edited). All seven read only
`apps/web-platform/infra/`-local subjects (`mu1-cleanup-guard.mjs`, `live-verify.tf`,
`audit-bwrap-uid.sh`, and self-contained fixtures), each already covered by `apps/*/infra/**`.

## Premise Validation

| Cited reference | Probe | Result |
|---|---|---|
| Issue #7068 | `gh issue view 7068` | **OPEN**, unclaimed, `closedByPullRequestsReferences: []`. Holds. |
| Orphan set (7 suites) | `run-registered-suites.sh --list` | Reproduced **exactly** — same 7 paths. Holds. |
| `test-all.sh` excludes infra | Read preamble | Confirmed at the `COVERAGE BOUNDARY (#6730)` anchor. Holds. |
| `git-data-rung2-rehearsal.test.sh` "IS registered — use as reference shape" | `git ls-files \| grep rung2` → **zero**; `git grep rung2-rehearsal` → **zero** | ❌ **STALE — the file does not exist.** The real suite added by `34654d7ab` is `git-data-runcmd-rehearsal.test.sh`, at step `Rehearse the git-data runcmd chain (abort ordering + rc guard)`. Reference shape re-pinned; carry the **full** step name, since a grep on a short form matches only by luck. |
| "Acceptance criteria" (AC1-AC4) | `gh issue view 7068` grepped for `acceptance`/`strengthen`/`unchanged` → **no matches**; body has only `## Suggested triage, per suite` | ⚠ **The criteria are NOT in the issue** — they come from the **operator's task framing**. Real and binding, but this plan must cite them as *operator criteria*, never "the issue's AC*n*". An earlier draft got this wrong and a reviewer correctly called it a fabricated citation. |
| #6480 (advisory→required) | `gh issue view 6480` | **OPEN**. Owns the promotion; see D2. |
| Detector-gap follow-up already filed? | `gh issue list --state open` grepped for `orphan\|run-registered\|derivation` | **None exists.** A new issue must be filed (D1). |

## Operator Acceptance Criteria (the binding set)

Quoted from the task framing, since the issue carries none:

1. `run-registered-suites.sh --list` reports **ZERO** orphan suites.
2. Every newly-registered suite **passes in CI on this PR**, or is registered as advisory with
   the tooling dependency **recorded at the auto-glob site**.
3. The orphan-detection mechanism itself is **unchanged or strengthened** — do not make the
   detector stop reporting by loosening it.
4. PR body carries the **per-suite decision table with evidence**.

Criterion 3 is satisfied **both** ways, deliberately: the detector's own logic is *unchanged*
(Phase 2 is comment-only), and detection is *strengthened* by a new fail-closed registration
gate (Phase 3) that does not touch the detector at all.

## Research Reconciliation — Spec vs. Codebase

| # | Claim in the issue / task framing | Measured reality | Plan response |
|---|---|---|---|
| **R1** | "several names suggest [deletion]: `inngest-cutover-flip`, `mu1-runbook-cleanup`, `cloud-init-plugin-seed` all read as one-shot migration guards" | **All three guard live, wired mechanisms.** `inngest-cutover-flip.sh` is baked into the bootstrap image by `build-inngest-bootstrap-image.yml`, installed by `inngest-bootstrap.sh`, and enabled as a live systemd timer. `mu1-cleanup-guard.mjs` is imported by the MU1 runbook and named in **ADR-023** as the destructive-cleanup gate. The `/opt/soleur/plugin` seed is live in `cloud-init.yml` + `ci-deploy.sh`. | **Zero deletions.** Filename inference was the hypothesis; the wiring grep refutes it. |
| **R2** | "the current pass/fail state … none of it is known today" | **7/7 PASS**, each ≤1s. | No red-on-arrival risk. |
| **R3** | "do NOT put a package-mirror dependency on a required, path-filter-free `merge_group` job (the #6454 lesson)" | The #6454 lesson is recorded **in this workflow** and names a different job: `guard-script-fixture-tests`, "a bare-bash runner that is REQUIRED, merge_group-triggered and path-filter-free". `deploy-script-tests` is the opposite on all three axes, and already apt-installs `cloud-init` + `cryptsetup-bin` and **already builds a container image** — at the `Run sandbox-canary would-have-caught regression (docker bwrap)` step (running `apps/web-platform/scripts/sandbox-canary-regression.test.sh` under `SDK_SANDBOX_REGRESSION_DOCKER: "1"`), **not** at `sandbox-canary-soak.test.sh`, which builds nothing. The job's timeout comment confirms it: "the #5875 sandbox-canary regression below builds a small alpine+bubblewrap image". | Registering here does **not** trip #6454. Constraint honoured, not waived — and Phase 3's new gate is bash-only precisely to keep honouring it. |
| **R4** | "Register it as advisory" is a distinct third option | There is **no non-advisory registration surface today** — `deploy-script-tests` is advisory for all 87 suites, and the workflow says so. Options 1 and 3 are the same act. | Recast the third axis as what actually varies: **does the suite need its tooling dependency recorded**. Only `cloud-init-plugin-seed` does. |

## Prior Art Consulted

- **`knowledge-base/project/learnings/2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md`** (#3366) — the "silent AND green" precedent: a flagship harness carrying a PR's whole value claim was registered in zero runners, and mutation testing proved the gate worked zero times. The defect class this PR closes.
- **`knowledge-base/project/learnings/2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md`** — enumerated (named-step) CI discovery is a standing **orphan generator**; the prevention it records is "grep the enumerator and add yourself", i.e. a human habit. That habit has now failed at least three times (#7000 left seven, #7025 surfaced them, #7068 is the cleanup) — which is the argument for Phase 3.
- **Advisory-gate tension, resolved by measurement, not rhetoric:** `knowledge-base/project/learnings/2026-07-20-an-advisory-gate-is-not-a-weak-gate-it-is-no-gate-and-a-ratio-needs-its-denominator-checked.md` (#6769) and `knowledge-base/project/learnings/2026-07-16-advisory-first-precedent-is-a-claim-to-measure-and-a-coordinate-citation-carries-no-claim.md` (#6517). The resolution is the two-consumer table in the Overview: the local runner's `(( RED == 0 ))` is a mandated ship gate, so registration confers real teeth. Promotion of the *display* stays with the open #6480 (D2).
- **In-workflow precedents to mirror:** the `#7000` two-orphan adoption block (the shape for this PR); `git-data-runcmd-rehearsal.test.sh`, registered plainly with "Skips cleanly without docker"; the `REGISTRATION IS NOT ENVIRONMENT` block, whose real lesson is *make the environment right at the call site* ("Installing it is what makes the registration real"); and the `timeout-minutes: 3` step on `ci-deploy.test.sh`, justified as "ATTRIBUTION, not budget".
- **`scripts/lint-orphan-test-suites.sh`** — a **fail-closed** orphan gate (exit 1) for `scripts/*.test.sh` wired into `ci.yml`. It already solves "a comment satisfies a bare-name grep" by anchoring on the **call shape** and citing `cq-assert-anchor-not-bare-token`, and requires every exclusion to carry a reason **and** a tracking issue. The model for Phase 3.
- **`apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh`** — already self-asserts its own registration, failing with *"no `run: bash …/scan-workflow.test.sh` step in infra-validation.yml — this guard would never run in CI"*. The pattern exists in-repo; Phase 3 generalizes it.

## Per-Suite Decision Table

Runs: `TMPDIR=/var/tmp bash apps/web-platform/infra/<name>.test.sh`, on
`feat-one-shot-7068-orphan-infra-suites` at `5eba7ec07` (clean `main` baseline), 2026-07-29.
Liveness gives the **first decisive** call site, not an exhaustive list.

| Suite | Local result | Liveness of the subject under test | Decision |
|---|---|---|---|
| `audit-bwrap-uid.test.sh` | **PASS** `8 passed, 0 failed` | `audit-bwrap-uid.sh` exists on `origin/main`; the MU1 runbook names it as the AC-4 verification. Mocks docker — no daemon needed. | **Register** |
| `cat-infra-config-state.test.sh` | **PASS** `6 passed, 0 failed` | `cat-infra-config-state.sh` is delivered by `server.tf` and invoked by `hooks.json.tmpl` as `/usr/local/bin/cat-infra-config-state.sh`. Needs `jq`. | **Register** |
| `cloud-init-plugin-seed.test.sh` | **PASS** (real `docker build` ran) | The `/opt/soleur/plugin` seed is live in `cloud-init.yml`. **Only suite of the seven needing a real docker daemon.** Self-skips when docker is absent. | **Register + assert docker at the call site** |
| `inngest-cutover-flip.test.sh` | **PASS** `68 passed, 0 failed` | `inngest-cutover-flip.sh` is installed by `inngest-bootstrap.sh` and enabled as a live systemd timer. Highest-stakes of the seven: an 8-state FSM gating a **destructive Redis `FLUSHALL`** (#6178 / ADR-100). Mocks `systemctl` + `redis` in a `mktemp -d` — no real Redis, no `FLUSHALL` executed. Needs `jq`. | **Register** |
| `inngest-server-flip-guard.test.sh` | **PASS** `16 passed, 0 failed` | `inngest-server-flip-guard.sh` is the live `ExecStartPre` guard (`FLIP_GUARD_LINE`), in documented lockstep with the cutover FSM (#6553). Registering it makes that ADR-100 lockstep CI-enforced for the first time. No external tooling. | **Register** |
| `live-verify.tf.test.sh` | **PASS** `6 ok` | `live-verify.tf` is a hard `[[ -f ]]` precondition of `bootstrap-live-verify.sh`. Asserts the provider-side mint **and the absence of an operator-mint variable** — it guards `hr-tf-variable-no-operator-mint-default`. Pure grep. | **Register** |
| `mu1-runbook-cleanup.test.sh` | **PASS** `8 passed, 0 failed` | `mu1-cleanup-guard.mjs` is imported by the MU1 runbook and named in **ADR-023** as a destructive-cleanup gate; its cases include a credential-exfiltration bypass class (`<ref>.supabase.co.evil.com` rejected). Needs `node`. | **Register** |

**Summary: 7 register, 0 delete.**

## Implementation Phases

### Phase 1 — Register the seven

Add seven steps to `deploy-script-tests` in `.github/workflows/infra-validation.yml`, mirroring
the `Rehearse the git-data runcmd chain (abort ordering + rc guard)` shape (a comment saying
what the suite guards, then a named step). Place them adjacent to the `#7000` orphan-adoption
block under one block comment citing #7068.

`cloud-init-plugin-seed` gets two extras, and only it:

1. **A separate preceding step** that asserts the daemon is live — e.g.
   `- name: Assert docker is available (cloud-init-plugin-seed needs a real daemon)` with
   `run: docker info >/dev/null`. This is the fail-closed half, and it is a **separate step on
   purpose**: folding the assertion into the suite's own step would turn that step into a
   multi-line `run: |`, which the derivation regex cannot match — silently re-orphaning the
   suite (exactly the D1 bug, self-inflicted). It also keeps the suite at **one** code path,
   so no `REQUIRE_DOCKER`-style dual mode is needed and the local skip stays intact for a
   docker-less laptop.
2. **A step-level `timeout-minutes`**, mirroring the `ci-deploy.test.sh` attribution
   precedent, because it is the one suite that builds a container and its ≤1s measurement was
   against a **warm** cache. Headroom is ample (job ceiling `timeout-minutes: 8` = 480s against
   a measured whole-job 184-189s), so this is attribution, not budget: a cold-pull stall must
   name this step rather than cancel an unrelated one. State the measured cost and the
   multiple, per that precedent's form.

**Rewrite the now-false `#7000` comment.** It enumerates the seven as deliberately unadopted,
ending "Left deliberately", and reasons that adopting them "would put a container dependency on
this job for unrelated scope" — independently false, since the job already builds an image (R3).
Replace the enumeration with a pointer to #7068; keep the two suites #7000 adopted attributed
to #7000. **Rewrite the paragraph, not just the four words a string-grep would catch.**

**Also update the job's timeout rationale comment**, which carries an explicit instruction:
*"Re-derive this if steps are added to the job — the numbers above are a property of its current
composition, not of the suite alone."* This PR adds seven steps. Honour it, or the PR ships the
same stale-rationale defect it is correcting in the `#7000` block.

> ⚠ **Two invariants of the registration shape — both load-bearing.**
>
> 1. **A comment can satisfy the orphan report.** The scan greps
>    `git grep -qF -- "$(basename "$f")" -- .github/workflows/ scripts/`, so prose naming
>    `<suite>.test.sh` silences it while running nothing. This is why the current `#7000`
>    comment names all seven *without* the `.test.sh` suffix — that suffix is the only reason
>    they still report. **AC2 therefore asserts the `run:` step, never the orphan report**, and
>    the new #7068 block comment must **not** contain the string
>    `bash apps/web-platform/infra/<name>.test.sh`.
> 2. **Nothing may sit between `run: bash` and the path.** The derivation is literal and
>    single-line. A step-level `env:` block between `name:` and `run:` is safe (precedented),
>    but an inline `run: FOO=1 bash …` or a multi-line `run: |` silently de-registers the suite
>    from the local runner — the D1 bug, self-inflicted. This is why the docker assertion is
>    its own step.

### Phase 2 — Record the dependency, and make the suite safe to run in parallel

- **Record the tooling dependency at the auto-glob site** (operator criterion 2, second
  branch): a short **comment-only** note in `run-registered-suites.sh`'s preamble naming
  `cloud-init-plugin-seed.test.sh` as the one registered suite needing a real docker daemon, so
  an operator whose local run skips it knows why. **No logic change** — derivation, the
  fail-closed zero-guard, and the orphan scan are untouched, keeping criterion 3 on its
  "unchanged" branch.
- **`$$`-scope the docker fixture identifiers** in `cloud-init-plugin-seed.test.sh`. It uses
  fixed names (container `soleur-plugin-seed-test`, image `soleur-plugin-seed-test:fixture`)
  and its `EXIT` trap runs `docker rm -f` / `docker rmi -f` on them. Registration newly places
  it in the **local** parallel runner (`xargs -P 6`), and parallel worktrees are this repo's
  normal workflow — so two concurrent runs would have one teardown delete the other's
  container mid-test, producing a non-reproducible RED on an unrelated suite. The sibling
  `workspaces-luks-loopback.test.sh` header states the convention: dm names and backing files
  are `$$`-scoped "so two concurrent runs cannot collide." This is a flake the PR would
  otherwise **introduce** into the gate it is widening.

### Phase 3 — Stop the class: a fail-closed registration gate

Phases 1-2 fix seven instances. Nothing yet stops orphan #8: `report_orphans()` prints a NOTE
and returns 0, deliberately ("Advisory, not a failure: this runner's job is to run what CI runs,
not to police the rest"). That separation of concerns is correct DX — someone else's
unregistered suite must not red *your* infra run — so **do not** flip the runner to fail. Put
the teeth in a separate gate.

Add `.github/scripts/test/test-infra-suite-registration.sh`: for every
`apps/web-platform/infra/**/*.test.sh` on disk, assert a real invocation step exists in
`infra-validation.yml`, else exit non-zero. Model it on `scripts/lint-orphan-test-suites.sh`:

- **Anchor on the invocation shape, not a bare basename** (`cq-assert-anchor-not-bare-token`) —
  the bare name also appears in comments and in the script's own exclusion list, either of
  which would let an unregistered suite pass vacuously.
- **Exclusions must carry a reason AND a tracking issue**; a reasonless or issue-less exclusion
  is itself an error, so skipping is a recorded decision rather than a silent absorption.

**Why this placement is the unlock.** The `test-*.sh` glob in `.github/scripts/test/run-all.sh`
feeds `guard-script-fixture-tests` — a check that is **REQUIRED, `merge_group`-triggered and
path-filter-free**. So the gate is genuinely blocking, yet:

- it adds **no new required-check name**, so no `ruleset-ci-required.tf` edit and no
  `scripts/required-checks.txt` edit (that file is CODEOWNERS-gated and carries the #6049
  auto-fabrication guard);
- it honours that glob's **BASH-ONLY contract** verbatim (`git grep` + reading YAML as text) —
  **no apt**, so the #6454 hazard is not tripped. #6454 was about a *package-mirror* dependency
  on the merge-queue critical path, not about any dependency at all;
- it **starts green**, because Phase 1 drives the orphan set to zero — a ratchet, not a backlog;
- it does **not** pre-empt #6480. #6480 makes the *suites' verdicts* blocking; this makes
  *registration* blocking. Orthogonal, and the second is the invariant #7068 is about.

Per `cq-write-failing-tests-before`, show it RED first (remove one of Phase 1's `run:` lines in a
scratch copy → must exit non-zero), then green.

**This is also what closes the deeper proxy.** `report_orphans()`'s basename grep is a bare-token
assert — the very shape `cq-assert-anchor-not-bare-token` forbids and that
`scripts/lint-orphan-test-suites.sh` explicitly refuses ("the bare name also appears in comments …
either of which would let an unregistered suite pass vacuously"). Hardening only this PR's ACs
would leave the detector comment-satisfiable forever, so the next PR could silence it with prose.
Phase 3's gate anchors on the **invocation shape**, so it cannot be satisfied by a comment — the
loose scan stays advisory (correctly: someone else's unregistered suite must not red *your* infra
run), and the blocking answer lives in a gate that cannot be talked out of. Any change to the
runner's own scan belongs to D1.

### Phase 4 — Verify

1. `bash apps/web-platform/infra/run-registered-suites.sh --list` → no orphan NOTE; record the
   new measured local wall-clock, not just that the count rose.
2. `bash apps/web-platform/infra/run-registered-suites.test.sh` → all 11 assertions pass.
3. `bash .github/scripts/test/run-all.sh` → the new gate is picked up and green.
4. `bash scripts/lint-workflows.sh` (**not** bare `actionlint` — see AC6).
5. Re-run each of the seven for the PR-body table.
6. File the D1 follow-up issue and link it from the PR body.

## Files to Edit

| File | Change |
|---|---|
| `.github/workflows/infra-validation.yml` | 7 `run: bash …` steps + block comment; a preceding docker-assert step and `timeout-minutes` for plugin-seed; **rewrite the stale `#7000` paragraph**; **update the job's timeout-rationale comment** per its own re-derive instruction |
| `apps/web-platform/infra/cloud-init-plugin-seed.test.sh` | `$$`-scope the container name and image tag (parallel-run safety) |
| `apps/web-platform/infra/run-registered-suites.sh` | **Comment only** — preamble note recording the docker dependency (no logic change) |

**Files to Create:** `.github/scripts/test/test-infra-suite-registration.sh` (Phase 3).

No `.tf`, migration, `cloud-init*.yml`, or `docker-compose` — the Encryption Posture (2.11) and
IaC Routing (2.8) gates do not fire.

## Acceptance Criteria

### Pre-merge (PR)

Eight, each falsifiable. An earlier draft had eleven; five asserted the same fact through
different instruments, restated standing repo rules, or pinned an English phrase — and one
**passed on an untouched repo** (it counted the orphan report, whose two-space indent is
identical to the derived list's; the detector's own test documents that exact trap).

1. **AC1 — zero orphans.** `run-registered-suites.sh --list` emits no
   `NOTE: … referenced by NO workflow or script` block. *(Operator criterion 1, verbatim.)*
2. **AC2 — each is a real executable step in the RIGHT job.** Scoped to `deploy-script-tests`:
   a step landing in `validate`, `check-secrets`, or `plan` would otherwise pass while
   violating R3's entire registration-target argument. **Verified RED against current `main`**
   (reports all seven missing), so the assertion is known to be able to fail:
   ```bash
   JOB=$(awk '/^  deploy-script-tests:/{f=1;next} /^  [A-Za-z0-9_-]+:/{f=0} f' \
          .github/workflows/infra-validation.yml)
   for s in audit-bwrap-uid cat-infra-config-state cloud-init-plugin-seed \
            inngest-cutover-flip inngest-server-flip-guard live-verify.tf mu1-runbook-cleanup; do
     printf '%s\n' "$JOB" \
       | grep -qE "^[[:space:]]+run: bash apps/web-platform/infra/${s//./\\.}\.test\.sh[[:space:]]*$" \
       || echo "MISSING STEP: $s"
   done
   # → no output
   ```
3. **AC3 — all seven green in CI on this PR, and not masked.** This is the only AC that binds
   *execution*, so it gets a procedure rather than a principle. AC2 proves the steps exist in
   the right job; a step can still be neutralised by `continue-on-error: true` (which the
   workflow warns yields "conclusion=success over outcome=failure") or by a false `if:`.
   Both halves:
   ```bash
   # (a) nothing in the job masks a failure — baseline verified 0 and 0 on current main
   awk '/^  deploy-script-tests:/{f=1;next} /^  [a-z0-9-]+:/{f=0} f' \
     .github/workflows/infra-validation.yml > /tmp/job.yml
   grep -cE '^[[:space:]]+continue-on-error:' /tmp/job.yml   # → 0
   grep -cE '^[[:space:]]+if:' /tmp/job.yml                  # → 0

   # (b) the job's OWN result names all seven steps as success (not skipped, not neutral)
   sha=$(git rev-parse HEAD)
   run=$(gh run list --workflow infra-validation.yml --commit "$sha" \
          --json databaseId -q '.[0].databaseId')
   job=$(gh api "repos/{owner}/{repo}/actions/runs/$run/jobs" \
          -q '.jobs[]|select(.name=="deploy-script-tests")|.id')
   gh api "repos/{owner}/{repo}/actions/jobs/$job" \
     -q '.steps[]|select(.name|test("audit-bwrap-uid|cat-infra-config-state|plugin seed|cutover-flip|flip-guard|live-verify|mu1-runbook"))|"\(.conclusion) \(.name)"'
   # → exactly 7 lines, every conclusion == "success"
   ```
   Per `cq-assert-anchor-not-bare-token` the claim is the job's **own** result, not a local
   reconstruction of its input set. Preconditions verified: `deploy-script-tests` has no
   `needs:`/`if:`, and the workflow's `paths:` covers both `apps/*/infra/**` and
   `.github/workflows/infra-validation.yml`, so this diff does trigger the job.
4. **AC4 — the `#7000` block no longer asserts the seven are unadopted.** Asserts the fact, not
   the phrase (deleting "Left deliberately" while leaving the enumeration would pass a
   phrase-grep):
   ```bash
   awk '/\(#7000\) Two ORPHAN suites adopted/,/^      - name:/' \
     .github/workflows/infra-validation.yml | grep -cE 'audit-bwrap-uid|mu1-runbook-cleanup'
   # → 0
   ```
5. **AC5 — detector not loosened.** `bash apps/web-platform/infra/run-registered-suites.test.sh`
   exits 0 with **all 11** assertions passing (`T1`, `T2a`-`T2d`, `T3a`-`T3c`, `T4`,
   `T5a`-`T5b`) — including `T3a` (zero-derivation still exits 2) and `T5a`/`T5b` (the orphan
   scan still reports a freshly-created fixture orphan). Combined with the diff carrying **no
   logic change** to `run-registered-suites.sh`, this satisfies criterion 3's "unchanged" branch.
6. **AC6 — workflow lints.** `bash scripts/lint-workflows.sh` exits 0. Use the wrapper, not bare
   `actionlint`: actionlint pipes each `run:` body into shellcheck and **deadlocks** on a body
   over the 65536-byte pipe buffer (#7002), and there are **93 pre-existing findings** across 20
   files — so "actionlint reports no errors" is not a satisfiable assertion. The wrapper exits 0
   on clean *and* on findings, non-zero only on the hang.
7. **AC7 — the new registration gate is fail-closed and wired.** `bash .github/scripts/test/run-all.sh`
   exits 0 (the new suite is picked up by the `test-*.sh` glob), **and** the gate exits non-zero
   when a registration is removed — demonstrated by deleting one Phase 1 `run:` line in a
   scratch copy. A gate that cannot fail is the defect this PR exists to remove.
8. **AC8 — PR body carries the per-suite decision table** with each suite's local result and
   liveness evidence, plus a link to the D1 follow-up issue. *(Operator criterion 4.)*

Standing repo rules deliberately **not** restated as ACs: `Closes #7068` in the body not the
title (`wg-use-closes-n-in-pr-body-not-title-to`) and the review-before-merge gates.

`scripts/test-all.sh` is deliberately **not** an AC: it structurally cannot observe this diff
(it does not cover `apps/web-platform/infra/`), so asserting it would be the same
false-assurance shape #7068 is about.

### Post-merge (operator)

**None.** Suites run locally via bash; the workflow edit is verified by
`scripts/lint-workflows.sh` plus the CI run. No infrastructure to provision, no secret to mint,
no vendor dashboard to touch.

## Deferred, With Evidence

### D1 — the detector's own derivation gap (file as a new issue)

Measured during this investigation, **not** in the issue's scope, and deferred under
`wg-when-an-audit-identifies-pre-existing` — the rule under which #7068 itself was filed rather
than folded into an unrelated PR. Folding it in here would break the rule this plan relies on.

**Finding 1 — the runner and CI *do* drift, by 8 suites.** `run-registered-suites.sh`'s preamble
claims "this runner and CI cannot drift". The derivation's character class `[A-Za-z0-9._-]`
excludes `/`, so all 7 subdirectory suites (`inngest-rls/`, `scripts/`, `supabase-advisor/`) are
invisible despite carrying proper `run: bash …` steps; and `workspaces-luks-loopback.test.sh` is
invoked as `sudo bash` inside a `run: |` block, which the `run: bash` anchor cannot match.
Narrow derivation = **79**, permissive = **87**. CI runs all 8; the local runner runs none.

**Finding 2 — the test cannot catch it.** `run-registered-suites.test.sh`'s `T2b` computes
`EXPECTED` with the *same* regex as the SUT, so it passes however wrong that regex is — which is
how the gap survived. Any fix must also widen the `DERIVED` character class on the neighbouring
line and expect `T2d` (header-vs-list identity) to red on a counting artifact: measured, a naive
widening gives `HEADER_N=87` vs `DERIVED=80` vs `EXPECTED=79`, so **T2b and T2d both fail** for
reasons a one-line regex change does not explain. An implementer under AC5's "all assertions
passing" would then be under precisely the pressure Risk 5 forbids.

**Finding 3 — why it is not a one-line widening: the blast radius is the point.**
`workspaces-luks-loopback.test.sh` **already fails closed** — `unavailable()` prints
`LOOPBACK_UNAVAILABLE` and `exit 2` when not root and passwordless sudo is unavailable
(measured on this machine: `sudo -n true` fails). So naively widening the derivation adds a
suite that **exits 2 on every unprivileged invocation** to the local runner's execute set,
turning `run-registered-suites.sh` **permanently RED for every operator without passwordless
sudo** — and because the runner discards output (`bash "{}" >/dev/null 2>&1`), they get a bare
`RED` with no diagnostic. That destroys the mandated ship gate this plan's own Overview
identifies as the real teeth of registration. On a laptop that *does* have passwordless sudo the
outcome is worse: the runner silently self-elevates and performs real `losetup` / `luksFormat` /
`mkfs.ext4` / privileged `mount` six-way parallel with output swallowed. An earlier draft of this
plan proposed the widening and mischaracterised the risk as a possible false *green*; it is a
guaranteed *red* or an unannounced root escalation. That inversion is why this needs its own plan.

**Finding 4 — a second trap.** Dropping the `run:` anchor to catch the `sudo` case would make
**any comment** a registration: a prose line naming a suite would enter the derived list and the
execute set while no `run:` step exists — re-opening, inside the derivation, the exact
prose-loophole Phase 1 closes for the orphan report. (Zero comment lines carry such a token
today — verified — so this is a future hazard, not a present one.) Any fix must strip
`^[[:space:]]*#` lines before deriving, and add a non-vacuity case asserting a commented-out
invocation is **not** derived.

**Finding 5 — loopback is the SOLE offender, which makes the follow-up tractable.** Measured
unprivileged: all 7 subdirectory suites exit **0** (`inngest-rls/{apply-inngest-rls-dev-workflow,
inngest-rls-mutation,inngest-rls}`, `scripts/{gen-github-egress-cidr,sigpipe-triage-feasibility}`,
`supabase-advisor/{scan-workflow,scan-workflow-mutation}`; ~19s serial, 12s worst single). Only
`workspaces-luks-loopback.test.sh` exits 2. So the follow-up is "widen the regex + exclude exactly
one suite", not a broad triage. Note also the arithmetic the fix should land on:
`79 derived + 7 orphans + 8 invisible = 94 on disk`, exactly.

**Recommended shape for the follow-up:** derive-but-do-not-execute — split the derived set into
an executable bucket and a privileged bucket, print the skipped set explicitly with a count and a
reason, and never have the runner invoke `sudo` itself. Model the exclusion list on
`scripts/lint-orphan-test-suites.sh`'s `name|reason` array, fail-closed when a reason is empty or
cites no `#NNNN`, so the exclusion is machine-checkable rather than a comment a human adjudicates.
Also scope the preamble's rewritten claim to `infra-validation.yml`: `web-platform-release.yml`
and `workspaces-luks-cutover.yml` also register infra suites (both happen to appear in
`infra-validation.yml` today, so there is no gap now, but an unqualified "cannot drift" is false
the moment one is registered only there).

**Also fold into the follow-up (pre-existing, found while researching R3):**
`plugins/soleur/scripts/grok-pre-push-gate.sh` asserts of the infra suites "**It is a required
check**". That is false — `deploy-script-tests` is absent from `scripts/required-checks.txt` and
`infra-validate-required` is explicitly not a required context yet (#6480). Recorded here rather
than fixed inline, per `wg-when-an-audit-identifies-pre-existing`; it is unrelated to the seven
suites and touching it would widen this PR's blast radius into the Grok gate.

### D2 — advisory → blocking promotion of the suites' verdicts

Owned by the **open #6480**. Disposition: **acknowledge, do not fold in.** Promotion requires
dropping `paths:`, adding `merge_group:`, and registering the context in both
`ruleset-ci-required.tf` and `scripts/required-checks.txt`; and because `deploy-script-tests`
and `check-secrets` carry no `needs:`/`if:`, dropping `paths:` would put an 8-minute docker
build on every docs-only PR. Doing it for seven suites would strand the other 80.

## Observability

Files to Edit include `apps/web-platform/infra/`, so the Phase 2.9 gate fires. The surface is CI
test-registration — no new runtime process — so the signal is the gate's own result.

```yaml
liveness_signal:
  what: deploy-script-tests job result (now executing 7 more suites) + the run-registered-suites.sh exit code, which work/ship mandate as an infra exit gate
  cadence: every pull_request touching apps/*/infra/**, infra/**, or the workflow itself; the local runner on every infra diff
  alert_target: GitHub Checks UI (advisory display) + non-zero local exit (blocking ship gate); verdict promotion tracked in #6480
  configured_in: .github/workflows/infra-validation.yml (deploy-script-tests job)

error_reporting:
  destination: GitHub Actions run log; one step per suite, so a failure names the suite exactly
  fail_loud: true   # no continue-on-error on any step in this job — the workflow rejects it because it yields conclusion=success over outcome=failure

failure_modes:
  - mode: a NEW infra suite is added and never registered (the #7068 class recurring)
    detection: .github/scripts/test/test-infra-suite-registration.sh exits non-zero
    alert_route: guard-script-fixture-tests — REQUIRED, merge_group-triggered, path-filter-free. Fail-closed as of this PR; previously only an advisory NOTE from the local runner.

logs:
  where: GitHub Actions run logs for infra-validation.yml and pr-quality-guards.yml
  retention: GitHub default (90 days)

discoverability_test:
  command: bash apps/web-platform/infra/run-registered-suites.sh --list
  expected_output: "no 'referenced by NO workflow or script' block; the seven appear in the derived list"
```

No `ssh` in any verification path.

## Architecture Decision (ADR/C4)

**Not required.** Read all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) rather than
grepping for the feature's own noun. Enumerated against the C4 completeness mandate: **no**
external human actor, **no** external system/vendor (GitHub Actions is the existing CI substrate;
docker on the runner pre-exists via the sandbox-canary regression step), **no** container or data
store, and **no** actor↔surface access relationship change. No ADR is reversed or extended —
infra-suite registration is established practice; Phase 3 reuses the existing
`guard-script-fixture-tests` check name and its auto-glob, so there is no ruleset-producer change
(if a *new* required check name were ever preferred instead, that variant belongs in #6480, where
the #5780 wire-all-producers lesson and the #6049 auto-fabrication guard both apply).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — CI registration with no
runtime surface. The realistic harm is second-order: a mis-registration that reads as coverage
while running nothing would leave the `inngest-cutover-flip` FSM (destructive Redis `FLUSHALL`)
and `mu1-cleanup-guard` (wrong-project deletion) unguarded on some *later* PR that breaks them.

**If this leaks:** no new exposure vector. Nothing reads, writes, or logs user data; no secret is
added or moved; the suites are hermetic (mocks, fixtures, a locally-built busybox image).

**Brand-survival threshold:** `aggregate pattern` — harm requires a later regression passing
through a falsely-green gate, so no single user is at risk from this diff. No CPO sign-off at this
threshold. The diff touches no preflight-Check-6 sensitive path (no schema, migration, auth flow,
API route, or `.sql`), so no `threshold: none` scope-out bullet is needed.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CI/CD + infra tooling, squarely CTO domain. Four judgements carry the plan:
(1) the target must be `deploy-script-tests`, the only established infra-suite home, advisory and
path-filtered, so #6454's package-mirror hazard — which names the REQUIRED,
merge_group-triggered `guard-script-fixture-tests` — does not apply; (2) registration is
worthwhile *because* the local runner's exit code is a mandated ship gate, not because the PR
check is pretty (the two-consumer table); (3) the recurrence gate belongs in the existing
bash-only required glob, which buys blocking enforcement with no ruleset edit and no apt; (4) the
detector's derivation gap is real but deferred to D1, because the naive fix regresses that same
ship gate to permanently-red, and criterion 3 is satisfied by "unchanged" plus Phase 3's
strengthening.

**Product/UX Gate:** NONE. Scanned Files to Edit/Create against the UI-surface term list and glob
superset — no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`, no user-facing
surface. The mechanical override does not fire and the semantic sweep agrees, so no `.pen` is
required under `wg-ui-feature-requires-pen-wireframe`.

Not relevant: Marketing, Sales, Finance, Legal, Operations, Support, Product.

**GDPR / Compliance Gate (2.7):** skipped — no regulated-data surface, and none of the four
expansion triggers fire (no LLM/external-API processing of operator data, threshold is
`aggregate pattern`, no new cron reading `learnings/`/`specs/`, no new distribution surface).

## Open Code-Review Overlap

**None.** Queried all 60 open `code-review` issues for the planned file paths — zero matches.
Adjacent open issues #6480 and the D1 follow-up are handled in `## Deferred, With Evidence`.

## Risks & Sharp Edges

1. **A comment can satisfy the orphan report; only a `run:` step makes a suite run.** AC2 asserts
   the step, never the report. Restoring the `.test.sh` suffix in prose alone would satisfy AC1
   fraudulently — and the new #7068 block comment must not contain a full
   `bash apps/web-platform/infra/<name>.test.sh` token.
2. **Nothing may sit between `run: bash` and the path.** The derivation is literal and
   single-line, so an inline env prefix or a multi-line `run: |` silently de-registers a suite
   from the local runner while it still looks registered. Step-level `env:` is safe; the docker
   assertion is therefore its own step.
3. **Rewrite the false `#7000` paragraph, not its closing words.** AC4 asserts the enumeration is
   gone, not that a phrase was deleted.
4. **`live-verify.tf.test.sh` has a literal dot before `.test.sh`.** AC2 escapes it via
   `${s//./\\.}` (verified working). Keep the escaping if the ACs are edited.
5. **Do not weaken a suite to get green.** If one reds in CI despite passing locally (no docker
   cache, different `jq`/`node`, no `sudo`), fix the environment at the call site per
   `REGISTRATION IS NOT ENVIRONMENT`. Weakening the assertion is the pressure the issue forbids.
6. **The flip-guard suite is textually coupled to `inngest-cutover-flip.sh`.** Its lockstep check
   awk-derives the FSM's `start_server` states from that script and asserts they are a subset of
   the guard's ALLOW allowlist (with a non-vacuity check that `flushed` was really derived). A
   legitimate FSM refactor will therefore red it with a "derivation broken" message. That is
   intended tripwire behaviour, but note it in the PR body so reviewers know it is deliberate —
   registering this suite makes a live prod script's textual shape CI-load-bearing for the first
   time.
7. **Phase 3's gate must start green and be shown able to fail.** AC7 covers both halves; a gate
   that cannot go red is the defect class this PR closes.

## Test Strategy

No new framework: infra convention is self-contained `*.test.sh` run by bash (94 such files; no
`bats` in the tree, so prescribing it would add an undeclared dependency), and Phase 3's new file
follows the `.github/scripts/test/test-*.sh` bash-only contract. Verification:

- `run-registered-suites.test.sh` — the detector's own 11 assertions, expected to stay green
  (Phase 2 is comment-only).
- AC2's job-scoped step grep — **already verified RED** against current `main`, so it can fail.
- The `deploy-script-tests` job result itself (AC3).
- Phase 3's gate shown RED with a `run:` line removed, then green (AC7), per
  `cq-write-failing-tests-before`.
