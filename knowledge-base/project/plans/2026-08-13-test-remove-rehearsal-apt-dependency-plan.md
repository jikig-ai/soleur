---
title: "test(infra): stop the rehearsal's apt failures reading as emitter findings"
date: 2026-08-13
slug: test-remove-rehearsal-apt-dependency
branch: feat-prebake-rehearsal-image-7535
issue: 7535
lane: cross-domain
type: test-infrastructure
priority: p3-low
domain: engineering
brand_survival_threshold: none
---

## Overview

Two changes to `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`, sequenced apart.

**Now:** delete the `e2fsprogs` install that installs an already-present package. Free, and
verifiably conflict-free with the in-flight PR #7507.

**After #7507 merges:** generalize *its own* `fixture_fail` pattern to the apt cycles it does
not cover, so a mirror failure names itself instead of surfacing as a substantive finding about
the emitter.

**What this plan no longer does.** An earlier revision proposed replacing all eight container
spins with a locally-built fixture image, plus three guards and a mutation battery. A seven-agent
review measured the value case and it did not survive: see `## Why the image was cut`. This plan
is the residue that measurement supports.

## Why the image was cut

The image was justified on wall-clock. Measured, that justification is worth nothing:

| Claim | Measured | Command |
|---|---|---|
| Step is "110–119 s" | **88–123 s** across 8 green runs on unchanged code; `infra-validation.yml:513` already commits **96 s** | Actions API step timings |
| Saving ≈ 4–6 runner-hours/week | Worth **$0** — repo is PUBLIC on `ubuntu-24.04` standard runners, so Actions minutes are unbilled | `gh repo view --json visibility` → `PUBLIC` |
| Faster PR feedback | **0 seconds.** Infra Validation is never the critical path — `CI`, `Main Health Monitor` and even `Board status sync` finish after it | per-SHA workflow durations |

Two further findings made the image net-negative rather than merely unjustified:

1. **It would introduce a vacuous-green in the arm that matters most.** Today the apt line sits
   under `set -e` *upstream* of the driver, so a container that cannot provision exits 100 and T5
   reports "exit 100, expected 1" — RED. Move provisioning to build time and it is never
   re-verified at spin time; a fixture whose `curl` cannot complete TLS then satisfies all of T5's
   assertions (rc==1, `stage=doppler_dl`, `level=fatal`, `CHMOD_RAN` absent) **with `sha256sum -c`
   never evaluated**. `command -v curl` does not catch it — `command -v` succeeds for a `curl`
   that cannot do TLS.
2. **It would concentrate an independent failure into a correlated one.** Eight independent apt
   cycles mean a mirror blip kills one spin and seven still produce signal. One build upstream of
   everything means a blip takes out 100% of the only runtime gate in the git-data suite.

The real cost of the apt dependency is neither seconds nor frequency — it is **diagnostic
ambiguity**, and that is what this plan addresses directly. #7501's own title records it: *"the
rehearsal's R3/R4 arms fail nondeterministically with empty captures, **and read as a substantive
emitter finding**."* One transient mirror failure produced #7501, #7535, #7544, PR #7507, a
brainstorm and this plan. Measured frequency is low — 0 of the 10 failures in the last 100
`infra-validation` runs were this step — but the investigative tail is enormous.

Naming the failure closes that at ~5% of the image's cost and introduces neither hazard above.

## Research Insights

### Premise Validation

| Cited reference | Probe | Result |
|---|---|---|
| #7535 | `gh issue view` | OPEN — work target |
| #7507 | `git diff main...origin/<branch>` | OPEN draft; hunks at `44-51, 402-409, 1089-1104, 1130-1148, 1149-1156, 1159-1166, 1445-1453`; **`e2fsprogs` appears 0 times** |
| #7544 | `gh issue view` | OPEN; corrected twice — see below |
| `ubuntu:24.04` ships `e2fsprogs` | `docker run --rm ubuntu:24.04 dpkg -s e2fsprogs` | `1.47.0-2.4~exp1ubuntu4.1`, `Priority: required` |

### Corrections carried in from review

Three claims in the earlier revision were wrong and are recorded here so they are not restored:

1. **The step is not a 110–119 s band.** That was a narrow sample of an 88–123 s distribution.
2. **R1 does not detect an `e2fsprogs` bump.** `git-data-birth-fs-fingerprint.txt:19-30` is an
   explicit argument for an allowlist *precisely so* a benign bump does not red, and `:84-85`
   pre-classify `metadata_csum_seed` and `orphan_file` — the exact features ≥1.47.1 emits.
3. **`fingerprint.txt:57` is not a pin.** Line 56 reads `CONTEXT FOR FAILURE MESSAGES ONLY — not
   asserted:`. R1 asserts feature sets, never versions (`:82-86`).

Both #7544 corrections are posted on that issue.

### Conventions

- **#7507 is the pattern to follow, not to work around.** It ships `fixture_fail()`, an
  `Acquire::Retries=3` + 3-attempt backoff, post-install `command -v` checks, and a
  `GIT_DATA_REHEARSAL_INJECT` harness — at the R4 site. Phase 2 generalizes that, reusing its
  helper rather than inventing a parallel idiom.
- `scripts/lint-shell-capture-exit.baseline.txt` carries **7 grandfathered findings for this
  file** (`:81-87`) and its header states the file *may only SHRINK*. Any new unprotected `$( )`
  capture adds a finding the baseline cannot absorb. Phase 2 adds none.

## Files to Edit

- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`

No new file. No workflow edit. No `.tf`. No image, Dockerfile, registry, secret, vendor or
scheduled job.

## Implementation Phases

### Phase 1 — delete the no-op `e2fsprogs` install (ships now, alone)

1. Delete `apt-get update -qq` / `apt-get install -y -qq e2fsprogs` at `:872-873`, and the
   `export DEBIAN_FRONTEND=noninteractive` at `:871` that becomes dead with them.
2. Replace with a comment recording *why* it is absent, so a future reader does not restore it:
   `ubuntu:24.04` ships `e2fsprogs 1.47.0-2.4~exp1ubuntu4.1` at `Priority: required`.
3. State the behaviour change in that comment. This is **not** a pure no-op: `apt-get install`
   runs after `apt-get update`, so today it resolves against the live archive and can serve a
   version the image layer does not carry. Today the two agree (both `1.47.0-2.4~exp1ubuntu4.1`,
   verified). Deleting the install narrows R1's `e2fsprogs` source from mirror-current to
   image-current — a faithfulness improvement, since the fingerprint's subject is the cloud
   image's own `e2fsprogs` (`fingerprint.txt:22`).
4. Re-run the suite; R1's four arms must produce identical verdicts.

### Phase 2 — name the remaining apt failures (after #7507 merges)

Blocked on #7507 only because it restructures the R4 site and ships the helper this phase reuses.

1. Rebase onto merged `main`.
2. For each apt cycle #7507 does not already cover — the `run_case` site (`:553`, 2 spins), the
   T5-mutation site (`:620`), the T17-mutation site (`:656`), and the `_s1_run` site (`:684-685`,
   2 spins) — wrap `apt-get update` and `apt-get install` in an rc check that calls #7507's
   `fixture_fail` with a message naming the site and the cause.
3. Do **not** add an `Acquire::Retries` backoff at these sites in this PR. Retry is a separate
   decision from naming; #7507 owns it at R4 and extending it is out of scope here.
4. Re-run the suite.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this change ships no
production code path. Its indirect risk is that a rehearsal arm stops discriminating, which would
let a git-data boot regression ship believing it was rehearsed.

**If this leaks:** not applicable. No data surface, no credential, no network egress added.

- **Brand-survival threshold:** `none`.
- **threshold: none, reason:** test-fixture-only change with no production code path, no data
  surface and no credential; the diff adds error messages and deletes a redundant package install.

> **This diverges from the brainstorm's framing, deliberately.** The brainstorm set
> `single-user incident`, reasoning from the *suite's* importance. Review established that this
> conflates the suite's blast radius with the change's: by that reasoning every edit to any gate
> file inherits the severity of everything the gate defends, which makes the threshold a constant
> and stops it discriminating. The reduced scope here — delete a redundant install, add error
> messages — cannot make an arm vacuous. The earlier revision could (see `## Why the image was
> cut`), and *that* scope warranted the higher threshold.

## Acceptance Criteria

### Phase 1

- **AC1** — `grep -cE '^[^#]*apt-get (update|install)' apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`
  returns **7** (from 9). Scoped to executable lines: a bare `grep -c 'apt-get'` returns 10,
  because `:533` legitimately discusses apt in prose.
- **AC2** — `grep -cE '^[^#]*e2fsprogs' <file>` drops **2 → 1**. *(Corrected at implementation:
  this AC originally demanded **0**, which was unreachable. `main` carries two non-comment
  occurrences — the apt install at `:873` and a pre-existing `fail()` message at `:1010` that
  legitimately names the package. Only the first is in scope.)* The survivor must be that
  R1-EXPIRY message; the replacement comment names the shipped version and the
  mirror-current→image-current narrowing.
- **AC3** — `grep -c 'DEBIAN_FRONTEND' <file>` drops by exactly 1 (the dead export at `:871`).
- **AC4** — R1's four arms produce identical verdicts before and after; both runs' R1 output
  quoted in the PR body.
- **AC5** — The assertion floor at `:1448` and the run's reported `total` are both **unchanged**
  — Phase 1 adds and removes no assertion.
- **AC6** — `git-data-render-strip-parity.test.sh` passes. It reads this file (`:42`) and asserts
  the anchored strip extractor by content, not line number, so line churn cannot break it.
- **AC7** — `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` passes.

### Phase 2

- **AC8** — Every remaining `apt-get update`/`install` in the file is rc-checked and reaches
  `fixture_fail` with a distinct message; verified by inducing a failure at each site.
- **AC9** — The messages are distinct per site, so a CI log names which spin starved.
- **AC10** — `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
  passes with `scripts/lint-shell-capture-exit.baseline.txt` **unmodified**
  (`git diff --stat` shows zero changes to it).
- **AC11** — No `Acquire::Retries` is added outside the R4 site #7507 owns.
- **AC12** — The floor at `:1448` is re-derived only if the assertion count actually moved, and
  the itemized ledger at `:1435-1447` is updated in the same edit if so — the file's own
  convention (`:1436`) is that the sum is itemized rather than trusted.

## Observability

This plan's Phase 2 *is* observability work — the deliverable is that a starved fixture names
itself instead of being read as an emitter finding.

```yaml
liveness_signal:
  what: the "Rehearse the git-data runcmd chain (abort ordering + rc guard)" step, and its
        per-assertion pass/fail summary line
  cadence: every pull_request and every push to main touching apps/*/infra/**
  alert_target: the PR's own required check — job failure blocks merge
  configured_in: .github/workflows/infra-validation.yml:1233

error_reporting:
  destination: GitHub Actions step logs; the harness's FIXTURE-FAIL / fail() markers on stderr
  fail_loud: yes — _skip (:32-44) exits 1 under CI=true so a gate that cannot run never
             reports success. This plan adds no _skip call site.

failure_modes:
  - mode: an apt cycle starves (mirror unreachable or index corrupt)
    detection: BEFORE Phase 2 — none; the arm fails and reads as a substantive emitter finding
               (this is the defect, recorded in #7501's title). AFTER Phase 2 — fixture_fail
               with a message naming the site and the cause.
    alert_route: step fails with a FIXTURE-FAIL marker distinguishable from an arm assertion
  - mode: R1's verdicts change after the e2fsprogs deletion
    detection: AC4 compares all four arms across the change
    alert_route: pre-merge; both runs quoted in the PR body
  - mode: a future edit restores the redundant install
    detection: the inline comment records why it is absent; AC2's grep is the merge-time check
    alert_route: PR review

logs:
  where: GitHub Actions run logs for infra-validation.yml
  retention: 90 days (GitHub default)

discoverability_test:
  command: grep -cE -e '^[^#]*apt-get update' -e '^[^#]*apt-get install' apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh
  expected_output: "7"
```

The probe's first token is `grep` (allowlisted), needs no credentials, no `ssh` and no docker, so
it is deterministic in preflight Check 10's sandbox. It asserts Phase 1's outcome — 9 → 7 apt
cycles. It is deliberately not `bash …test.sh`: without docker that script's `_skip` exits 0 in a
non-CI sandbox, which would make the probe vacuous.

Two shapes here are forced by Check 10's runtime, and both were found by running it rather than
reading it. The alternation is spelled as two `-e` patterns instead of `(update|install)` because
the check rejects a literal `|` anywhere in the command — a reject aimed at pipe-chaining, which a
regex alternation trips identically. And the scalar is UNQUOTED: `parse-form-a.awk` returns the
inline value verbatim, so surrounding double quotes survive into `bash -c` and the whole probe
becomes one quoted word that resolves to "command not found". Both forms count the same lines —
verified 7 on this branch against 9 on `origin/main`.

## Issue disposition

#7535 is titled *"remove the rehearsal containers' apt dependency rather than retrying it"*. This
plan does **not** remove it — it deletes one redundant cycle and names the rest.

The PR body therefore uses **`Refs #7535`, not `Closes`**. #7535 stays OPEN, retitled to the
residual scope, with the measurements in `## Why the image was cut` posted as a comment so the
next reader does not re-derive them.

**Replacement re-evaluation trigger** for the image, superseding the one that never fired: Infra
Validation becomes the longest workflow on a PR's head SHA in ≥3 consecutive runs.

```
gh api "repos/jikig-ai/soleur/actions/runs?head_sha=$SHA" \
  --jq '.workflow_runs[]|"\(.run_started_at)|\(.updated_at)|\(.name)"'
```

That is checkable, cheap, and tied to something the operator would actually feel — unlike a
step-share threshold, which measured $0 and 0 seconds.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Phase 1's deletion changes R1's behaviour | AC4 compares all four arms; the narrowing is toward the fingerprint's stated subject |
| A future reader restores the `e2fsprogs` install | Phase 1 step 2's comment records the reason inline |
| Phase 2 collides with #7507 | Phase 2 runs *after* the merge and reuses #7507's helper rather than adding a parallel one |
| Phase 2 trips the shell-capture lint | AC10; the phase adds no command substitution |

## Non-Goals

- **NG1** — A pre-baked fixture image, in any form, published or local. Cut on measured evidence.
- **NG2** — `FIXTURE_IMG` / `FIXTURE_PACKAGES` chokepoints, and Guards 1–3. Cut with the image.
- **NG3** — Publishing to GHCR or zot.
- **NG4** — `--network none` at any site.
- **NG5** — Digest-pinning `ubuntu:24.04` (#7544).
- **NG6** — Changing the assertion floor's comparison operator from `-lt` to equality. That would
  tax every future PR that adds an assertion, for a benign under-count.
- **NG7** — Adding retry/backoff outside the R4 site #7507 owns.
- **NG8** — Modelling Docker Hub in C4 (pre-existing, unchanged).
- **NG9** — Any other suite in `infra-validation.yml`.

## Architecture Decision (ADR/C4)

**No ADR, no C4 change.** With the image cut, the only architectural decision on the table —
putting a fixture image on the registry path — is not merely declined but out of scope. Adding
error messages to a shell test introduces no element, no edge and no boundary.

The C4 enumeration was performed against all three model files while the image was still in
scope, and was verified independently: `contributor` (`model.c4:35`, `#external`) unchanged;
`ghcr` (`:280`), `projectZot` (`:284`), `zotRegistry` (`:288`) all modeled with no edge added;
no containers or stores; no access relationship changes. Docker Hub remains unmodeled and
pre-existing. None of that changes under the reduced scope.

## Domain Review

**Domains relevant:** Engineering, Product.

### Engineering

**Status:** reviewed
**Assessment:** Seven-agent panel. The image was cut on measured evidence (public repo → $0;
never the critical path → 0 s) plus two hazards it would have introduced. The surviving work —
FR1 and failure-naming — was endorsed by DHH, code-simplicity, CTO and CPO independently as the
highest-ratio subset. Phase 2 reuses #7507's shipped helper rather than a parallel idiom.

### Product

**Status:** reviewed
**Assessment:** CPO measured the value proposition and recommended cutting to FR1, noting #7535
and #7544 both sit in `Post-MVP / Later` while Phase 5 is overdue at 0/6 closed. The operator
chose FR1 plus failure-naming — the increment that addresses the misdiagnosis cost, which is the
one value the measurement supports.
