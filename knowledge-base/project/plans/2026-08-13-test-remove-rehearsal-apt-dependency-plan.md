---
title: "test(infra): stop the rehearsal's apt failures reading as emitter findings (image cut on measurement)"
date: 2026-08-13
updated: 2026-09-17
slug: test-remove-rehearsal-apt-dependency
branch: feat-one-shot-7535-rehearsal-apt-misattribution
phase1_branch: feat-prebake-rehearsal-image-7535
spec_dir: knowledge-base/project/specs/feat-prebake-rehearsal-image-7535
issue: 7535
closes: 7535
lane: cross-domain
type: test-infrastructure
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

## Overview

Two changes to `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`, sequenced apart.

**Phase 1 — SHIPPED 2026-08-13** as PR #7540, merged `910f237f0`: the redundant `e2fsprogs`
install is gone (9 -> 7 apt invocations at that time), plus a NOFEATURES guard fix in R1(a)/(b).
Its acceptance criteria are frozen below as a historical record and are **not** re-asserted
against today's `main`.

**Phase 2 — this work.** Make the two remaining uncovered apt cycles name themselves, so a
starved mirror is never read as a substantive finding about the emitter or as a finding about the
mutation battery. Phase 2 completes #7535's residual scope, so the PR body uses **`Closes #7535`**
(Phase 1 correctly used `Refs`).

**What this plan no longer does.** An earlier revision proposed replacing all eight container
spins with a locally-built fixture image, plus three guards and a mutation battery. A seven-agent
review measured the value case and it did not survive: see `## Why the image was cut`. This plan
is the residue that measurement supports.

## Phase 2 Reconciliation — [Updated 2026-09-17]

This plan's Phase 2 target list was **stale**. Two of its four named sites were shipped by a
sibling PR while Phase 2 was blocked. The record of the handover:

| Predecessor | State | What it now owns on `main` |
|---|---|---|
| PR #7507 — rung-2 evidence hash | **MERGED** `dfcf7bd26` (2026-08-13) | `fixture_fail()`, `Acquire::Retries=3`, a 3-attempt install loop, post-install `command -v` checks and the `GIT_DATA_REHEARSAL_INJECT` harness — all at the **R4** site, inside the `R4DRV` driver heredoc |
| PR #7510 — T5-mutation network flake | **MERGED** `45ea9f7e9` (2026-08-19) | The **`run_case`** split and the **T5-mutation** split, each carrying the measured mechanism-(b) comment. **Do not re-split these.** |

**Retargeted Phase 2 site list — the complete remaining census.** Every executable `apt-get`
line in the file (`grep -nE '^[^#]*apt-get' <file>`, 2026-09-17) resolves to one of five sites;
three are already owned:

| Site | Anchor | Shape on `main` | Disposition |
|---|---|---|---|
| `run_case` (2 spins) | the `TWO STATEMENTS, NOT ` + "`a && b`" comment above `bash /work/drive.sh` | two separate statements under `set -e` | **owned by #7510** — no work |
| T5-mutation | the same comment inside the `drive.noerrexit.sh` spin, followed by `_t5m_rc=$?` | two separate statements; rc captured; four-rung ladder | **owned by #7510** — no work |
| R4 (`R4DRV`) | `fixture_fail() { echo "FIXTURE-FAIL: $1" >&2; exit 2; }` | six named causes, retry, INJECT | **owned by #7507** — no work |
| **T17 MUTATION** | `# MUTATION: remove the rc guard and prove T17's assertion can FAIL` | one `apt-get update ... && apt-get install ...` AND-OR list; `>/dev/null 2>&1 \|\| true`; one assertion | **SITE 1 — primary** |
| **`_s1_run`** | the `S1DRV` heredoc's `apt-get install -y -qq openssh-server` | two separate statements under `set -e` | **SITE 2 — naming only** |

`grep -cE '^[^#]*apt-get update.*&&.*apt-get install' <file>` returns **1** on `main` — the T17
site is the last AND-OR pair in the file.

**Residual recorded, not planned.** `run_case`'s verdict names the container's rc
(`"$name: exit $rc, expected $want"`) but not the *cause*. That is cause-level naming #7510
chose not to add, and it is not reopened here: the arm is already RED and already makes no claim
about the emitter, which is the property #7535 is about.

## Why the image was cut

The image was justified on wall-clock. Measured, that justification is worth nothing:

| Claim | Measured | Command |
|---|---|---|
| Step is "110–119 s" | **88–123 s** across 8 green runs on unchanged code | Actions API step timings |
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
   everything means a blip takes out 100% of the only *runtime* gate among the git-data gates.

The real cost of the apt dependency is neither seconds nor frequency — it is **diagnostic
ambiguity**, and that is what this plan addresses directly. #7501's own title records it: *"the
rehearsal's R3/R4 arms fail nondeterministically with empty captures, **and read as a substantive
emitter finding**."* One transient mirror failure produced #7501, #7535, #7544, PR #7507, a
brainstorm and this plan. Measured frequency is low — 0 of the 10 failures in the last 100
`infra-validation` runs were this step — but the investigative tail is enormous.

Naming the failure closes that at ~5% of the image's cost and introduces neither hazard above.

**[Updated 2026-09-17] The cut contradicts what ADR-188 records, and that is a deliverable, not a
footnote.** ADR-188's `## Alternatives Considered` still reads *"Pre-bake the container image —
**DEFERRED**, and preferred over retry when it lands"*, and its S1/T5 residual instructs the next
reader that *"if the arm skips on more than 1 in 20 post-merge runs … the deferred pre-baked
container image is owed immediately."* After the measurement above that instruction points at a
design a seven-agent panel cut. Leaving it means the next skip-rate breach builds the image. The
amendment is **D4** below.

## Research Insights

### Premise Validation — re-probed 2026-09-17 against `origin/main`

Every number the earlier revision carried has moved. These are measured, not carried:

| Cited reference | Probe | Result |
|---|---|---|
| #7535 | `gh issue view 7535 --json state,title` | **OPEN**, titled `test(infra): stop the rehearsal's apt failures reading as emitter findings (image cut on measurement)` — already retitled to residual scope by Phase 1 task 1.10. Labels `priority/p2-medium`, `type/bug`, `domain/engineering`, `deferred-scope-out`; milestone `Post-MVP / Later` |
| PR #7507 | `git show -s dfcf7bd26` | **MERGED** 2026-08-13 — `fix(git-data,ci): unblock the rung-2 evidence hash and repair two guards that could not report (#7507)` |
| PR #7510 | `git show -s 45ea9f7e9` + `git log -S` on the split comment | **MERGED** 2026-08-19 — and it is the commit that introduced the `TWO STATEMENTS` comment at both the `run_case` and T5-mutation sites |
| Phase 1 | `git show -s 910f237f0` | **MERGED** 2026-08-13 — `test(infra): drop the rehearsal's redundant e2fsprogs install (2 of 9 apt cycles) (#7540)` |
| The target file | `wc -l` on this worktree and on `origin/main` | **3630 lines, byte-identical**. Every line number in the pre-2026-09-17 revision of this plan has shifted; all anchors below are by content |
| `fixture_fail` | `grep -n 'fixture_fail' <file>` | Defined **inside the `R4DRV` driver heredoc**, not on the host. See `### Conventions` — "reuse `fixture_fail`" means reuse the idiom and the `FIXTURE-FAIL:` marker, because the function is not in scope at either target site |
| Assertion floor | `grep -n -- '-lt 92' <file>` | `if [ "$total" -lt 92 ]; then` — **92**, raised 77 -> 92 by the S2 arm (#8043 F11). The earlier handoff's `-lt 44` is stale by five raises |
| The frozen baseline | the comment above `total=$((passes + fails + SKIPPED_ASSERTIONS))` | `Floor = the ACTUAL assertion count (B1: 1, B2: 1, D1: 2, T5: 4 + 1 mutation, T17: 2 + 1 mutation, S1: 3 + 4 mutation). THIS LIST IS THE FROZEN 19-ERA BASELINE, not a running total` — and the #7572 stanza adds `Do NOT edit the frozen 19-era baseline list higher up to reconcile with this` |
| ADR-188 | `grep -n 'run/sshd' ADR-188-*.md` | Present: *"It must carry a `[ ! -d /run/sshd ]` in-arm assertion: S1's finding depends on that directory not existing at runcmd time, and installing `openssh-server` at build time changes when it could appear."* Recorded as a revival guard only |
| `c4-count-parity` | `bash plugins/soleur/test/c4-count-parity.test.sh` | **10 passed, 0 failed** (2026-09-17). Path is under `plugins/soleur/test/`, not `apps/web-platform/test/` |
| Local docker | `docker info`; `ls -l /var/run/docker.sock`; `getent group docker`; `command -v podman` | **UNAVAILABLE.** Socket `srw-rw---- root:docker`; `docker:x:966:` — the group is **empty**; daemon unreachable; no podman. See `## Verification` |

### Mechanism (b) — measured, because the one-liner LOOKS safe under `set -e`

`set -e` does **not** fire on a failing **non-final** member of an AND-OR list:

```
$ bash -c 'set -e; sh -c "exit 100" && true; echo reached'
reached                       # rc=0
$ bash -c 'set -e; true && sh -c "exit 100"; echo reached'
                              # rc=100 — errexit fires only in final position
```

So at the T17 site a failed `apt-get update` **falls through into `drive.sh` with no `curl` and no
`python3`**, the capture server never binds, and the arm's empty capture is reported as a mutation
battery vacuity finding. This is the third instance of one defect; the first two are already
commented in-file by #7510, in words this plan reuses verbatim at the third site.

**Rejected claim, recorded so it is not restored.** A research pass asserted the opposite — *"a
failed `apt-get update` exits non-zero AND blocks the install from running; the entire script
aborts"* — citing `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`.
That file contains **no** discussion of AND-OR lists (`grep -i -- '&&'` returns nothing), and the
probe above falsifies the claim. The authority is the probe, not the citation.

### Property List — what Phase 2 must buy

- **P1** — A run in which the T17-mutation container never reached the download block does **not**
  emit "the check is vacuous"; it names the container's rc and the absent execution marker.
- **P2** — A run in which the T17 rc-guard mutation did **not land** does not emit "the check is
  vacuous"; it says the mutation did not land. (P1 and P2 together are one property: *the vacuity
  message is emitted only when the arm is genuinely vacuous.*)
- **P3** — At the T17 site, a failing `apt-get update` aborts the container instead of falling
  through into `drive.sh`.
- **P4** — At both target sites, a starved apt emits a distinct literal naming the **site** and the
  **statement**, and that literal reaches the operator's log.
- **P5** — At `_s1_run`, a starved apt keeps routing to `did-not-run` / `arm_skip` (an honest
  declared environment decline per ADR-188) and never to `harness-defect` (hard FAILs).
- **P6** — A healthy run emits none of the new literals.
- **P7** — The recorded architecture no longer instructs a future reader to build the image the
  measurement cut.

### Cut List — mechanisms removed before research, with what already buys them

| Mechanism | Property it would buy | What already covers it |
|---|---|---|
| Re-splitting `run_case` and T5-mutation | P3 at those sites | On `main` since `45ea9f7e9` (#7510) |
| `Acquire::Retries` / backoff at the two target sites | "transient mirror failures are retried" | Bought at R4 by `dfcf7bd26` (#7507). Extending it is a separate decision from naming — NG7 |
| Restructuring `_s1_run`'s apt pair into an rc-checked form | "the rc propagates to the classifier" | Already bought: the two statements are separate and in final position, so `set -e` fires and rc 100 reaches `_s1_classify`, which allowlists it. Naming only |
| A `_T17M_ENV_RCS` rc allowlist at T17 | "classify the rc" | Not needed: T17 makes no routing decision, so the rc is **offered** in the message and never asserted as cause (AP-021/ADR-166). The file's enumerate-once convention applies to allowlists that route |
| An `arm_skip` at T17 | "declare the arm's cost on a decline" | **Cut on measured blast radius:** it breaks `[ "$_SKIP_CALL_SITES" -eq 3 ]`, breaks the `_PROBE_NAMED == _SKIP_CALL_SITES` roster identity (which sums only `T5 ` + `S1 ` prefixed sites), forces a `_SKIP_CEILING` raise and its stanza, and touches `scripts/followthroughs/t5-skip-persistence-bound-7510.sh`. Reclassification is not naming |
| Pre-baked image, GHCR/zot publishing, digest-pinning `ubuntu:24.04`, `--network none` | "apt is off the gate path" | Cut on measured evidence. Revival guard preserved in D4 |

### Conventions this file enforces on the edit

- **`fixture_fail` is container-scoped, and it must not be used at `_s1_run`.** It is defined
  inside `R4DRV` and it `exit 2`s. rc 2 is **not** in `_S1_ENV_RCS='100 125'`, so `_s1_classify`
  would route it to `harness-defect`. Counted from the five `_s1_run` call sites' `case` arms, a
  transient mirror blip would then produce **11 hard FAILs** (S1 healthy 2, S1 mutation 3,
  S2(h-j) 3, S2(k-l) 2, S2(n) 1) — the false-FAIL #7291 and ADR-188 exist to remove. The file
  states the constraint in its own words above `echo "S1_FIXTURE_OK"`: *"an apt failure is the
  environment decline ADR-188 accepts, so it must route to `did-not-run`, and emitting the fixture
  marker before apt would convert every apt failure into a hard fixture-defect FAIL."*
- **The frozen 19-era baseline must not be edited.** Each raise gets its own
  `# RAISED <old> -> <new>` stanza; a prior review caught an edit to the baseline that made
  `20 + 14 = 34 != 33`.
- **Re-derive a floor from a measured run, never by incrementing.** The file's own words:
  *"Re-derived from a measured run against the as-written file, not incremented by memory."*
- **`>/dev/null 2>&1` on apt is load-bearing for CONFIDENTIALITY, not noise.** The `run_case`
  comment records it: behind an authenticated apt proxy, apt error text embeds `user:pass@host`,
  and the skip reason tails that capture on a GREEN run. **Every new message is a fixed literal;
  apt's own stderr is never surfaced.**
- **`scripts/lint-shell-capture-exit.baseline.txt` carries 7 grandfathered findings for this
  file** (verified: `grep -c` = 7) and its header states the file may only **SHRINK**. Phase 2
  adds no command substitution.
- **`_T5_MARKER='DRIVER_REACHED_DL'` is defined once and pinned** to the mounted artifact by a
  structural guard. Read it, do not replicate the literal.
- **Read markers with `grep -qx`, not `grep -q`.** The file's reason: bash echoes the offending
  source line on an error, so `bash: /work/drive.sh: line 9: echo DRIVER_REACHED_DL: command not
  found` satisfies a bare `grep -q` and would route a container that never ran to "it ran".
- **The S1 structural marker guard is anchored on the exact emit forms**
  `^\s*echo "S1_DRIVER_REACHED_STAGE"\s*$` and `^\s*echo "S1_FIXTURE_OK"\s*$` in the mounted
  driver. New echoes in `S1DRV` do not disturb it, and must not resemble either marker.
- **The host script runs `set -uo pipefail`, no `-e`** (verified). `cmd; rc=$?` is therefore safe
  on the host; the `; _rc=$?` assignment must stay on the **same line** as the command (the
  T5-mutation comment: a comment block between them makes inserting a command there look safe,
  and any inserted command silently clobbers `$?`).

### Applicable institutional learnings

| Path | Constraint it imposes |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-193-anti-vacuity-floor-contract.md` | *"A floor enforced through the suspect cannot witness the suspect."* The file's floor already `echo … >&2; exit 1`s directly — Phase 2 must not route it through `fail()` |
| `knowledge-base/project/learnings/2026-09-08-both-my-anti-vacuity-gates-ran-through-the-line-that-voided-them.md` | Slack under a floor is attack budget, not padding. The raise must be exact (92 -> 93), not generous |
| `knowledge-base/project/learnings/2026-08-13-the-fixture-shape-decided-what-the-assertion-could-possibly-catch.md` | A fixture that cannot fail at apt never exercises the named path. The `GIT_DATA_REHEARSAL_INJECT` arms are what make the mutation rows executable |
| `knowledge-base/project/learnings/best-practices/2026-05-27-bash-set-e-leaks-from-functions-use-or-true.md` | Never toggle `set -e` inside a function. The naming blocks use `cmd \|\| { …; exit "$_rc"; }`, never `set +e` |
| `knowledge-base/project/learnings/test-failures/2026-06-29-bash-accumulate-then-exit-gate-test-three-footguns.md` | A deliberately-nonzero command inside `$( )` propagates under errexit. Moot here — Phase 2 adds no command substitution (TR4) |
| `knowledge-base/project/learnings/2026-07-06-cloud-init-user-data-cap-bake-bodies-and-set-e-scope-fix-ungates-security-checks.md` | When a check was protected *only* by errexit, making the scope explicit must make it explicitly fail-closed. This is exactly mechanism (b) at the T17 site |

### Research Reconciliation — plan/spec claims vs. `main`

| Claim in the pre-2026-09-17 revision | Reality on `main` 2026-09-17 | Plan response |
|---|---|---|
| Phase 2 targets four sites incl. `run_case` and T5-mutation | Both shipped in `45ea9f7e9` | Retargeted to two sites; handover table added |
| "the `-lt 44` floor" (handoff) / `:1448` | Floor is `-lt 92`; the citation's line number is 3607 | Corrected; all anchors now by content |
| AC1 — `grep -cE '^[^#]*apt-get (update\|install)'` returns **7** | Returns **15** (the #7507 driver added named apt strings) | Phase-1 ACs frozen as historical; **the `discoverability_test` probe that asserted `"7"` is rewritten** — preflight Check 10 *executes* it, so it would have failed at ship |
| AC2 — non-comment `e2fsprogs` drops 2 -> 1 | **2** on `main`, both legitimate message text, neither an install | Frozen as historical |
| Observability `configured_in: infra-validation.yml:1233` | The step is at `:1561` | Replaced with the step-name anchor per `cq-cite-content-anchor-not-line-number` |
| "the only runtime gate in the git-data suite" | True *among git-data gates* (infra-validation.yml: *"Every other git-data gate is static"*), but **two** registered infra suites need docker — `cloud-init-plugin-seed` and this one | Wording tightened in `## Verification` |
| "No ADR, no C4 change" | ADR-188 still records the image as DEFERRED-and-preferred | **D4** amends it; C4 conclusion stands, now backed by a green count-parity run |

## Hypotheses

The `hr-ssh-diagnosis-verify-firewall` gate fired on `openSSH-server` and `unreachable`. **The
match is incidental to the usual trigger class** — nothing here diagnoses a live host's
reachability, and no L3 firewall, DNS, TLS or journal artifact exists to paste, because there is
no incident host. The layer discipline is still answered, because the failure this plan *names* is
genuinely a network-layer one and naming which layer starved apt is the deliverable:

| Layer | Question for this change | Verification |
|---|---|---|
| **L3 — firewall / egress** | Can the runner's egress reach the Ubuntu archive? | **Not verifiable at plan time and deliberately not asserted.** The rc is *offered* as a measured class (100 = apt under the container's outer `set -e`), never asserted as the cause — AP-021/ADR-166. No `hcloud firewall describe` applies: the actor is a GitHub-hosted runner, not a Hetzner host |
| **L3 — DNS / routing** | Did `archive.ubuntu.com` resolve? | Not measured, and cannot be: apt's stderr is suppressed for the confidentiality reason above. Recorded as the deferred `/out/setup.log` item the T5-mutation skip message already names |
| **L7 — TLS / proxy** | Did an authenticated apt proxy reject? | Same. This is precisely why the new messages are **fixed literals** — an apt proxy's error text embeds `user:pass@host` |
| **L7 — application** | Did the container ever run? | **This is the hypothesis the plan makes decidable.** `DRIVER_REACHED_DL` absence plus the container rc plus the named apt literal discriminate "never ran" from "ran and the arm is vacuous" in one read |

Service-layer hypotheses (the emitter changed behaviour; the rc guard regressed; the mutation
battery is vacuous) are **not** entertained until the L7-application question above answers "the
container ran" — which is the ordering discipline the checklist asks for, expressed as code.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` returned 65 issues
(2026-09-17); none mentions `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`,
`git-data-runcmd-rehearsal`, `T17`, `_s1_run`, `fixture_fail` or `arm_skip` in title or body.

## Files to Edit

- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — D1, D2, D3
- `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md` — D4

Also written by the pipeline, and therefore inside the diff-scope AC:

- `knowledge-base/project/plans/2026-08-13-test-remove-rehearsal-apt-dependency-plan.md`
- `knowledge-base/project/specs/feat-prebake-rehearsal-image-7535/{spec.md,tasks.md}`
- `knowledge-base/INDEX.md` (generated)
- `knowledge-base/project/specs/<branch>/session-state.md` (if the pipeline writes one)

No new source file. No workflow edit. No `.tf`. No image, Dockerfile, registry, secret, vendor or
scheduled job. No `.c4` edit.

**Artifact-location note.** The spec directory is `feat-prebake-rehearsal-image-7535` while the
branch is `feat-one-shot-7535-rehearsal-apt-misattribution`. The directory name is historical (the
"prebake" slug predates the image cut) and is kept rather than renamed: it is where the reviewed
spec lives and `git mv` across sibling worktrees is not worth the churn. The frontmatter carries
both `branch:` (current, so the plan selector resolves) and `spec_dir:`.

## Implementation Phases

### Phase 1 — delete the no-op `e2fsprogs` install — **SHIPPED**

Merged 2026-08-13 as `910f237f0` (PR #7540). Deleted the `apt-get update` / `apt-get install -y
-qq e2fsprogs` pair and the then-dead `export DEBIAN_FRONTEND=noninteractive`, replacing them with
a comment recording that `ubuntu:24.04` ships `e2fsprogs 1.47.0-2.4~exp1ubuntu4.1` at
`Priority: required`, and that the deletion narrows R1's `e2fsprogs` source from mirror-current to
image-current — a faithfulness improvement, not a no-op. Verified on CI runs 31711619961 (main)
and 31717913686 (PR), both `44 passed, 0 failed`.

### Phase 2 — name the two remaining apt cycles (this work)

Unblocked: both predecessors are merged. Re-derive every anchor from the post-rebase file by
**content**, never from a line number in this plan.

#### D1 — T17 MUTATION (primary; highest value)

Anchor: `# MUTATION: remove the rc guard and prove T17's assertion can FAIL`.

1. **D1a — split the AND-OR list.** Replace
   `apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq curl python3 >/dev/null 2>&1`
   with the two-statement form already on `main` at `run_case` and T5-mutation, carrying the same
   comment. **The comment must name mechanism (b) explicitly** — that `set -e` does not fire on a
   failing non-final member of an AND-OR list (measured), so the one-liner *looks* safe under
   `set -e` and is not. Keep `>/dev/null 2>&1` on both statements for the confidentiality reason.
2. **D1b — capture the rc through the removed `|| true`.** Replace
   `' >/dev/null 2>&1 || true` with `' >"$TMP/out/stdout" 2>&1; _t17m_rc=$?`. The assignment stays
   on the **same line** as the closing quote. `$TMP/out` is freshly recreated two lines above, so
   the file is this arm's own. Not `local` — this arm is top-level.
3. **D1c — name each apt statement inside the container.** One fixed literal per statement, on
   stderr, distinct, naming the site and the statement, e.g.
   `FIXTURE-APT: T17 mutation container — apt-get update failed (mirror unreachable or index corrupt)`
   and the `install curl python3` counterpart. Never echo apt's own output.
4. **D1d — a three-way verdict, exactly ONE assertion on every route.** Read the execution marker
   from the captured stdout with `grep -qx "$_T5_MARKER"` (the pinned variable, not the literal):
   - capture non-empty → `pass` (unchanged meaning)
   - capture empty **and** marker **absent** → `fail "T17 MUTATION did not run: the container
     never reached the download block, so this arm demonstrated neither that removing the rc guard
     makes a healthy run emit nor that T17's assertion can fail"` with a detail carrying
     `docker rc=${_t17m_rc} (measured classes: 100 apt under the container's outer set -e, 125
     docker CLI/image pull — offered as classification, not asserted as cause); execution marker
     seen: no; tail: $(tail -5 …)`
   - capture empty **and** marker **present** → the existing vacuity message, **byte-unchanged**.
5. **D1e — plumb fault injection with NAMESPACED tokens.** Add
   `-e "GIT_DATA_REHEARSAL_INJECT=${GIT_DATA_REHEARSAL_INJECT:-}"` to this arm's `docker run` and
   honour `t17-apt-update` / `t17-apt-install` inside the inline `bash -c`, each emitting its D1c
   literal and exiting 100. **The tokens must not collide with R4's `apt-update` / `apt-install`**
   — one env var is read by more than one driver, so a shared token would silently starve a
   different arm than the row intends and the row would test nothing.

#### D2 — `_s1_run` (naming only, and NOT restructuring)

Anchor: the `S1DRV` heredoc's `apt-get install -y -qq openssh-server`.

**Why this site is treated differently from the `&&` sites.** The two statements are separate and
each is in final position, so `set -e` **does** fire here and the container rc reaches
`_s1_classify` as 100, which `_S1_ENV_RCS='100 125'` allowlists — the rc-propagation property D1a
buys at T17 is already bought here. What is missing is only the *name*: `S1_NOTE` offers
`100 apt under the container's outer set -e` as a classification, and `tail -3` of the container's
stdout is empty because apt's output is suppressed. So D2 adds a name and changes nothing else.

1. **D2a** — name each statement with a distinct fixed literal on stderr, in the same family as
   D1c, e.g. `FIXTURE-APT: S1 driver — apt-get install openssh-server failed (…)`.
2. **D2b — preserve the measured rc.** `apt-get … || { _rc=$?; echo "<literal>" >&2; exit "$_rc"; }`.
   **Do not pin `exit 100`** — that would launder a non-apt-class rc into the environment
   allowlist and hide a harness defect as a decline.
3. **D2c — do NOT route through `fixture_fail` or any `exit 2`.** Measured blast radius: 11 hard
   FAILs across the five `_s1_run` call sites (see `### Conventions`).
4. **D2d — do NOT move `echo "S1_FIXTURE_OK"` above apt.** The file's comment states that doing so
   converts every apt failure into a hard fixture-defect FAIL.
5. **D2e — the literal deliberately does not match the nested runner's marker ERE.**
   `apps/web-platform/infra/run-registered-suites.sh` anchors its excerpt on
   `MARKER_ERE='^[[:space:]]*(\[FAIL\]|[A-Z][A-Z0-9]*-FAIL|FAIL)([[:space:]:_-]|$)'`, so
   `FIXTURE-FAIL:` matches and `FIXTURE-APT:` does not. That is **intended**: an apt decline at S1
   is an environment decline, not a fixture failure, and giving it a `*-FAIL` marker would both
   anchor a RED excerpt on a non-failure and invite a future reader to reclassify it. Record the
   non-match in the code comment so it reads as a decision rather than an oversight.
6. **D2f** — add `-e "GIT_DATA_REHEARSAL_INJECT=${GIT_DATA_REHEARSAL_INJECT:-}"` to `_s1_run`'s
   `docker run` (it already forwards two `-e`s) and honour `s1-apt-update` / `s1-apt-install`.

#### D3 — the T17 mutation-landed pre-check

P2 is the other half of the same property as P1: today an empty capture is reported as "the check
is vacuous" whether the container failed **or** the mutating `sed` matched nothing. Two of three
legs is a verdict that can still lie.

1. Before the container run, assert the mutation landed, mirroring the S2(m) precedent in this
   file: count the guard line in `$TMP/drive.sh` (expect 1) and in `$TMP/drive.noguard.sh`
   (expect 0). `diff -q` is the T5-noerrexit precedent and is acceptable; the count form is more
   specific about *which* line moved.
2. On not-landed, emit the named fail **plus a substitute fail for the verdict that cannot run**,
   so the arm contributes **exactly 2 assertions on every route** (S2(m)'s shape).
3. **Raise the floor with a NEW itemised stanza and leave the frozen baseline alone:**

   ```
   # RAISED 92 -> 93 (#7535), ITEMISED — one new counted assertion, pure text over $TMP, made on
   # every route the suite reaches this far on:
   #     1  T17 MUTATION: the rc-guard mutation landed (the guard line count went 1 -> 0)
   #   ----
   #     1
   # Re-derived from a measured run against the as-written file, not incremented by memory.
   ```

   Then change `-lt 92` to the **measured** total, not to `92 + 1` by arithmetic.
4. Do **not** touch the frozen 19-era baseline list (`B1: 1, B2: 1, D1: 2, T5: 4 + 1 mutation,
   T17: 2 + 1 mutation, S1: 3 + 4 mutation`) and do not touch any earlier `RAISED` stanza.

**Cut criterion for a reviewer.** If D3 is judged out of #7535's scope, cut it together with the
floor raise and its stanza, file the residual as an issue naming the `sed`-did-not-land leg, and
keep D1/D2 — they stand alone. D1's verdict must then still be three-way, because the
marker-absent leg is P1 and is in scope regardless.

#### D4 — amend ADR-188

Add a dated amendment to `## Alternatives Considered` recording (a) that the pre-baked image is
**CUT**, not deferred, with the three measurements and the two hazards from `## Why the image was
cut`; (b) the replacement re-evaluation trigger below, superseding the skip-rate trigger that
points at the cut design; and (c) that **any** revival must still carry the `[ ! -d /run/sshd ]`
in-arm assertion, because installing `openssh-server` at build time can make `/run/sshd` exist at
runcmd time and **silently invalidate S1 rather than fail it**. No new ADR ordinal, so no
collision probe is needed; no C4 view changes.

Replacement trigger:

```
gh api "repos/jikig-ai/soleur/actions/runs?head_sha=$SHA" \
  --jq '.workflow_runs[]|"\(.run_started_at)|\(.updated_at)|\(.name)"'
```

Infra Validation becomes the longest workflow on a PR's head SHA in >= 3 consecutive runs. That is
checkable, cheap, and tied to something the operator would feel — unlike a step-share threshold,
which measured $0 and 0 seconds.

## Guard Contract

### Guard 1 — the T17-MUTATION anti-vacuity verdict

**Property.** The message *"T17 MUTATION: removing the rc guard did NOT make a healthy run emit —
the check is vacuous"* is emitted **if and only if** the mutation landed, the container executed
the download block, and the capture is still empty.

**Assembly.** The chokepoint is the single verdict that follows this arm's `docker run` — one
`if`/`elif`/`else` over three inputs: `[ -s "$TMP/out/capture.log" ]`,
`grep -qx "$_T5_MARKER" "$TMP/out/stdout"`, and the D3 landed-count. The assembly is *every
message in the file that claims this arm's result*, enumerated by
`grep -n 'T17 MUTATION' <file>` — a census over the file, not a name list, with the D3 and D1d
messages as its floor. There is exactly one container invocation for this arm, in the region
between the `# MUTATION: remove the rc guard` comment and the `# ── S1 —` banner.

**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| 1 | `GIT_DATA_REHEARSAL_INJECT=t17-apt-update` | the update literal appears; the verdict names rc + marker-absent; the vacuity string does **not** appear |
| 2 | `GIT_DATA_REHEARSAL_INJECT=t17-apt-install` | same, naming *install* — and the two literals differ |
| 3 | Rewrite the mutating `sed` expression so it matches nothing | the verdict says the mutation did not land; the vacuity string does **not** appear |
| 4 | **Dispatch row** — delete this arm's `docker run` and its verdict | the arm contributes fewer than its 2 assertions and the floor reds. A verdict that checks nothing must not exit 0 |
| 5 | **Second-member row** — after row 1 passes, add a **third** apt statement to this container's recipe and starve it | the third statement is also rc-checked and named. A check that stops at the first apt statement is the defect this matrix exists to find |
| 6 | **Order row** — move the marker read so it happens **before** the `docker run` writes `$TMP/out/stdout` | a healthy run is then reported as "did not run". Proves the verdict reads the *post-run* file, which a delete-only battery cannot see |

**Harness rows.**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Neuter `fail()` with the two-token bucket swap | the CANARY instrument self-test and the `FAILURES` ledger red. Re-assert after the edit — ADR-193: a floor routed through the suspect cannot witness it |
| H2 | Reword the injected token on one side only (`t17-apt-update` -> `t17-aptupdate` in the container arm but not in the row's env) | row 1 must red. Pin the token once (a variable, or a structural assertion that the file carries it) — this is the unpinned-replicated-literal class the file already closes for `_T5_MARKER` |
| H3 | **Must-PASS, non-canonical:** a healthy run with `GIT_DATA_REHEARSAL_INJECT=apt-update` — R4's token, not a T17 token | the T17 arm **passes** and emits none of the new literals. Proves the namespacing in D1e, and is the only row shape that can detect a guard that rejects everything |

**Anchor.** Guard 1 stores one value a diff could move alongside the thing it protects: the
assertion floor. It is anchored outside the arm by the itemised `# RAISED 92 -> 93` stanza plus the
frozen 19-era baseline that must **not** move with it — an edit that raises the floor without
adding a stanza is visible in review as a bare number change. The stated residual (ADR-188's own)
is unchanged: a substitution that holds the count constant — an arm replaced by a bare `pass` — is
not caught by any floor, and rows 1-3 are what cover it.

### Guard 2 — the `_s1_run` environment-decline classification

**Property.** A starved apt inside the S1 driver reaches `_s1_classify` as `did-not-run` (an
honest declared skip) **and** its cause is named in the operator-visible note. It must never
become `harness-defect` or `fixture-defect`, and never become a silent decline.

**Assembly.** The chokepoint is the container rc returned by `bash /work/sshd-drive.sh`, consumed
at the single `S1_STATE="$(_s1_classify …)"` assignment inside `_s1_run`. Every consumer is a
`case "$S1_STATE"` at an `_s1_run` call site; the census is `grep -n '_s1_run ' <file>` — five
call sites today (S1 healthy, S1 mutation, S2(h-j), S2(k-l), S2(n)) plus the definition, and the
property is quantified over whatever that census returns, not over those five names. The naming
channel is `$TMP/s1out/stdout`, read into `S1_NOTE` by `tail -3`.

**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| 1 | `GIT_DATA_REHEARSAL_INJECT=s1-apt-update` | the update literal appears in `S1_NOTE`'s tail; **every** S1/S2 arm declines via `arm_skip`; **zero** `FAIL:` lines naming S1 or S2 |
| 2 | `GIT_DATA_REHEARSAL_INJECT=s1-apt-install` | same, naming *install*; the two literals differ |
| 3 | Change D2b's `exit "$_rc"` to `exit 2` | all five arms flip to `harness-defect`/`fixture-defect` and the run reds with 11 FAILs. **This row must RED** — it is the measured reason `fixture_fail` is not reused here |
| 4 | **Dispatch row** — delete the naming echo, keep the exit | the arm still declines correctly, but the note's tail is empty. The AC asserting the literal on an injected starve must red |
| 5 | **Second-member row** — add a third apt statement to `S1DRV` and starve it | it is also named. The census in *Assembly* is over statements, not over the two that exist today |

**Harness rows.**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Rename the `-e GIT_DATA_REHEARSAL_INJECT` on the `docker run` but not in the driver | row 1 must red — otherwise every row silently tests a healthy run |
| H2 | **Must-PASS, non-canonical:** `S1_RESTART_MODE=fail` with no INJECT | every S2(h-j) assertion still makes its normal verdict and no new literal appears |

**Anchor.** The floor and `_SKIP_CEILING=7`. Guard 2 adds **no** assertion and **no** `arm_skip`
call site, so both must be **unchanged** — and that invariance is itself an acceptance criterion
(a naming change that moved the skip ceiling would mean it had quietly reclassified something).
`_SKIP_CALL_SITES -eq 3` and the `_PROBE_NAMED == _SKIP_CALL_SITES` roster identity are the
external checks that would red such a drift; neither is edited.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this change ships no
production code path. Its indirect risk is that a rehearsal arm stops discriminating, which would
let a git-data boot regression ship believing it was rehearsed.

**If this leaks:** not applicable. No data surface, no credential, no network egress added. The
one confidentiality-adjacent property is preserved rather than added: apt's own stderr stays
suppressed, because behind an authenticated proxy it embeds `user:pass@host` and the skip reason
tails that capture on a green run.

- **Brand-survival threshold:** `none`.
- **threshold: none, reason:** test-fixture-only change with no production code path, no data
  surface and no credential; the diff adds error messages, one assertion, and an ADR amendment.

> **This diverges from the brainstorm's framing, deliberately.** The brainstorm set
> `single-user incident`, reasoning from the *suite's* importance. Review established that this
> conflates the suite's blast radius with the change's: by that reasoning every edit to any gate
> file inherits the severity of everything the gate defends, which makes the threshold a constant
> and stops it discriminating. The reduced scope here — name two apt cycles, add one landed-check
> — cannot make an arm vacuous; it removes two ways an arm can lie. The earlier revision could
> (see `## Why the image was cut`), and *that* scope warranted the higher threshold.

## Acceptance Criteria

### Phase 1 — SHIPPED 2026-08-13 (`910f237f0`), frozen as a historical record

These were satisfied at their merge commit and are **not** re-asserted against today's `main`;
`main` has moved under every count below. Do not "fix" them.

- **AC1** *(as of 910f237f0)* — `grep -cE '^[^#]*apt-get (update|install)' <file>` returned **7**,
  from 9. *(On `main` 2026-09-17 the same grep returns 15 — PR #7507 added named apt strings to the
  R4 driver. The count is a shared quantity that sibling PRs move; see the Sharp Edge in
  `## Observability`.)*
- **AC2** *(as of 910f237f0)* — non-comment `e2fsprogs` dropped **2 -> 1**. *(On `main` it is 2,
  both legitimate message text.)*
- **AC3** *(as of 910f237f0)* — `DEBIAN_FRONTEND` dropped by exactly 1.
- **AC4** — R1's four arms produced identical verdicts before and after; CI runs 31711619961 and
  31717913686 both reported `44 passed, 0 failed (44 assertions)`.
- **AC5** — the floor and the reported `total` were unchanged at 44.
- **AC6** — `git-data-render-strip-parity.test.sh` passed.
- **AC7** — the suite passed on CI run 31717913686.

### Phase 2 — Pre-merge (PR)

Every AC below must carry an **evidence-provenance tag**: `[local docker]` with the quoted
terminal summary line, or `[CI run <id>]` with the run's conclusion. An AC with neither tag is
**UNVERIFIED** and blocks PR-ready. See `## Verification`.

- **AC8** — Every executable `apt-get update`/`install` in the file is rc-checked at the point of
  failure and emits a distinct literal naming the site and the statement. Verified by the census
  `grep -nE '^[^#]*apt-get' <file>` plus, for each remaining site, one injected-starve run.
- **AC9** — The literals are pairwise distinct across all four new emit points, so a log names
  which spin starved. Asserted as a **set**, not a count.
- **AC10** — Guard 1's mutation matrix rows 1-6 and harness rows H1-H3 all behave as tabled, with
  each row's command and observed output recorded in the PR body.
- **AC11** — Guard 2's mutation matrix rows 1-5 and harness rows H1-H2 all behave as tabled,
  likewise recorded. Row 3 in particular must be **demonstrated RED** — it is the evidence for D2c.
- **AC12** — A **pre-fix control**: with the fix reverted on a scratch copy and the same
  injected starve applied, the T17 arm emits the *"the check is vacuous"* message. An assertion
  nobody has seen fail is not evidence.
- **AC13** — **P6, both sites:** on a healthy run `grep -c 'FIXTURE-APT' <suite stdout+stderr>`
  returns **0**.
- **AC14** — `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
  passes with `scripts/lint-shell-capture-exit.baseline.txt` **unmodified** (`git diff --stat`
  shows zero changes to it). Phase 2 adds no command substitution.
- **AC15** — No `Acquire::Retries`, `sleep`-backoff or retry loop is added outside the R4 site
  #7507 owns. `grep -c 'Acquire::Retries' <file>` is unchanged.
- **AC16** — No new `_skip` call site: `grep -cE '^[[:space:]]*_skip ' <file>` is unchanged.
  `_skip` exits 0 off-CI, so routing a starved provisioning step through it would silently green a
  broken run on a laptop.
- **AC17** — `_SKIP_CEILING` and its itemised stanza are **unchanged**, and
  `grep -cE '^[[:space:]]*arm_skip ' <file>` is still **3** — so the two roster assertions and the
  ceiling assertion all still pass. Guard 2 reclassifies nothing.
- **AC18** — If and only if D3 ships: the floor is re-derived from a **measured** run (quote the
  terminal `… N passed, 0 failed, Skipped: S (T assertions)` line), a new
  `# RAISED 92 -> <measured>` stanza is added, **and** `git diff` shows **zero** changes to the
  frozen 19-era baseline comment and to every earlier `RAISED` stanza.
- **AC19** — The T17 arm contributes the **same** number of assertions on every route
  (2 with D3, 1 without): landed+ran+emitted, landed+ran+empty, landed+never-ran, not-landed. A
  route contributing a different number is indistinguishable at the floor from an arm that partly
  vanished.
- **AC20** — `bash apps/web-platform/infra/git-data-render-strip-parity.test.sh` passes. It reads
  this file and asserts the anchored strip extractor by content, so line churn cannot break it.
- **AC21** — The full suite passes: `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`
  with a **real docker daemon**, or the "Rehearse the git-data runcmd chain (abort ordering + rc
  guard)" step green on CI. Tagged per the provenance rule above.
- **AC22** — ADR-188 carries a dated amendment recording the image as CUT (with the three
  measurements), the replacement re-evaluation trigger, and the `[ ! -d /run/sshd ]` revival guard.
  `grep -c 'run/sshd' ADR-188-*.md` does not decrease.
- **AC23** — `bash plugins/soleur/test/c4-count-parity.test.sh` is green (baseline 2026-09-17:
  10 passed, 0 failed) and `git diff --stat -- knowledge-base/engineering/architecture/diagrams/`
  is empty.
- **AC24** — The `## Observability` `discoverability_test` command is **executed** and its output
  matches the pinned `expected_output`; the value was re-measured on the final tree, not carried.
- **AC25** — Diff scope: the diff touches only the paths in `## Files to Edit`. No workflow, `.tf`,
  Dockerfile, registry step, secret, scheduled job or `.c4` file.
- **AC26** — PR body uses **`Closes #7535`** (in the body, never the title).

## Observability

Phase 2 *is* observability work: the deliverable is that a starved fixture names itself instead of
being read as a finding about the emitter or about the mutation battery.

```yaml
liveness_signal:
  what: the "Rehearse the git-data runcmd chain (abort ordering + rc guard)" step, and the
        suite's terminal "git-data-runcmd-rehearsal: N passed, M failed, Skipped: S (T
        assertions)" line
  cadence: every pull_request and every push to main touching apps/*/infra/**
  alert_target: the PR's own required check — job failure blocks merge
  configured_in: .github/workflows/infra-validation.yml, the step named "Rehearse the git-data
                 runcmd chain (abort ordering + rc guard)" (cited by name, not line: the line
                 moved 1233 -> 1561 between plan revisions)

error_reporting:
  destination: GitHub Actions step logs; the harness's FIXTURE-FAIL / FIXTURE-APT / fail()
               markers on stderr, and arm_skip's "SKIP (loud):" line
  fail_loud: yes — _skip exits 1 under CI=true so a gate that cannot run never reports success,
             and infra-validation.yml carries a SEPARATE `docker info >/dev/null` step ordered
             BEFORE both docker-dependent suites so a daemon-less runner reds the job rather
             than greening it. This plan adds no _skip call site (AC16).

failure_modes:
  - mode: an apt cycle starves at the T17-MUTATION site (mirror unreachable or index corrupt)
    detection: IN-SURFACE. The container itself emits a distinct FIXTURE-APT literal naming the
               statement, and the host verdict emits four discriminating fields in ONE event —
               docker rc, execution-marker-seen, mutation-landed, and the container stdout tail.
               Those four separate every competing hypothesis for an empty capture in one read:
               rc=125 image pull, rc=100 apt (which statement is in the literal), marker absent
               = never reached the download block, landed=no = the sed matched nothing,
               marker present + landed + empty = a genuine vacuity finding, and drive.sh's own
               "FIXTURE: capture server never bound :8099" for the bind case.
               BEFORE this change: none of it — the rc was discarded by `|| true` and the sole
               assertion reported "the check is vacuous", which is the defect #7535 exists to
               close.
    alert_route: step fails with a message that names the container, not the emitter
  - mode: an apt cycle starves inside the S1 driver
    detection: IN-SURFACE. A distinct FIXTURE-APT literal on the driver's stderr, which lands in
               $TMP/s1out/stdout and is carried into S1_NOTE's tail; the preserved rc keeps
               _s1_classify on did-not-run so the arm declines rather than failing.
               BEFORE: the rc reached the classifier but the cause did not — S1_NOTE offered
               "100 apt" as a classification with an empty tail behind it.
    alert_route: a loud declared skip naming the cause, plus the run's Skipped: count and NOTE.
                 LIMITATION, recorded rather than claimed away: a declined run is GREEN, so
                 run-registered-suites.sh prints PASS and dumps no excerpt (its own header says
                 the skip "is NOT visible through this runner"). On the CI path the suite is a
                 DIRECT step, so the whole step log carries the literal.
  - mode: the T17 rc-guard mutation stops landing (the sed expression drifts)
    detection: D3's landed-count pre-check, one assertion on every route
    alert_route: a named fail plus a substitute fail for the verdict that could not run
  - mode: a future edit restores an AND-OR apt pair, or reintroduces `|| true` on a container
    detection: the inline comments record mechanism (b) and the rc-capture reason at all three
               split sites; the discoverability probe below counts a token this PR owns
    alert_route: PR review

logs:
  where: GitHub Actions run logs for infra-validation.yml
  retention: 90 days (GitHub default)

discoverability_test:
  command: grep -c FIXTURE-APT: apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh
  expected_output: "8"
```

**The probe's `expected_output` MUST be re-measured on the final tree before `/ship` (AC24).** The
value `8` is the *design's* expected count — two emit points plus two injection arms at each of
the two target sites — and is **not** a carried number. `FIXTURE-APT` returns **0** on `main`
today, so the token is one this PR owns.

**Sharp Edge — why this probe is not a count of `apt-get`.** The previous revision's probe was
`grep -cE -e '^[^#]*apt-get update' -e '^[^#]*apt-get install' <file>` with
`expected_output: "7"`. That was correct at `910f237f0` and is **wrong today**: the same grep
returns **15**, because PR #7507 added eight named apt strings to the R4 driver three weeks later.
preflight Check 10 *executes* this command, so the stale probe would have failed at ship time on a
correct tree. A discoverability probe must count a token the PR **owns**, never a shared quantity
that sibling PRs move.

Two shapes are forced by Check 10's runtime and both were found by running it rather than reading
it: the command carries **no literal `|`** (the check rejects one anywhere, a reject aimed at pipe
chaining that a regex alternation trips identically — hence no `(update|install)` and no
alternation at all here), and the expected scalar is **unquoted** in the YAML because
`parse-form-a.awk` returns the inline value verbatim, so surrounding double quotes survive into
`bash -c` and the whole probe resolves to "command not found". The probe's first token is `grep`
(allowlisted), it needs no credentials, no `ssh` and no docker, so it is deterministic in the
sandbox. It deliberately is not `bash …test.sh`: without docker that script's `_skip` exits 0 in a
non-CI sandbox, which would make the probe vacuous.

## Verification

The brief's constraints, encoded so they cannot be satisfied by a green that was never obtained.

**1. A green is not evidence unless docker actually ran.** `_skip` exits **0** off-CI
(`if [ "${CI:-}" = "true" ]; then … exit 1; fi; echo "$1" >&2; exit 0`), and the file's first two
preconditions are `command -v docker` and `docker info`. A docker-less local run therefore prints
one SKIP line and exits 0. Worse, `apps/web-platform/infra/run-registered-suites.sh` captures each
suite's output and prints `PASS`, so **that runner reports PASS for a docker-less skip** — its own
header says the skip "is NOT visible through this runner … ~50-65 s of coverage, silently absent".
Neither is evidence.

**2. Docker is UNAVAILABLE on this box (measured 2026-09-17).** `/var/run/docker.sock` is
`srw-rw---- root:docker`; `getent group docker` returns `docker:x:966:` — **the group is empty**;
`docker info` fails; `sudo` needs a password; no `podman`, no rootless daemon. The operator has
been asked to fix it.

**3. Two acceptable evidence sources, and every AC must disclose which one it used.**

| Source | What counts | Tag |
|---|---|---|
| Local | a run in which `docker info` succeeded first, with the terminal `git-data-runcmd-rehearsal: N passed, M failed, Skipped: S (T assertions)` line quoted verbatim | `[local docker]` |
| CI | the "Rehearse the git-data runcmd chain (abort ordering + rc guard)" step, with run id and conclusion. **Authoritative**, because infra-validation.yml's separate `docker info >/dev/null` step is ordered before it, so a daemon-less runner reds the job instead of greening it | `[CI run <id>]` |

Phase 1 already took the CI route for the same reason and recorded why: at load 11.6 with three
sibling sessions, one *local* apt cycle exceeded 19 minutes (tasks 1.5). Expect the same.

**4. Never report a green that was not obtained.** If neither source is available for an AC at
ship time, mark it **UNVERIFIED** and do not mark the PR ready (`wg-block-pr-ready-on-undeferred-operator-steps`).
Do not substitute a docker-less exit 0, a `run-registered-suites.sh` `PASS`, or reasoning.

**5. The mutation matrices need a real daemon.** Each row is one container run, made executable by
the `GIT_DATA_REHEARSAL_INJECT` arms (D1e/D2f) rather than by editing the file under test — the
R4 driver's own rationale: *"A row that can only be executed by editing the heredoc is a row that
does not get executed."* Row form:
`GIT_DATA_REHEARSAL_INJECT=t17-apt-update bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`.
If docker stays unavailable, **the rows cannot be run and AC10-AC12 must not be claimed.** The
fallback is a CI run with the token set — which needs a temporary `workflow_dispatch` input, so
prefer waiting on the local daemon.

**6. Contention: prefer the single-file invocation, shard only if the battery is needed.** Many
sibling worktrees run this same docker suite. Default to
`bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` and
`bash apps/web-platform/infra/git-data-render-strip-parity.test.sh` directly. If `TEST_GROUP=all`
stalls, shard: `TEST_GROUP=infra` is the only group whose `want_infra` reaches
`run-registered-suites.sh`, and `TEST_GROUP=scripts SCRIPTS_SHARD=<n>/<m>` covers the scripts
side. `SCRIPTS_SHARD` is **rejected** unless `TEST_GROUP=scripts`. Valid groups are
`all, webplat, bun, scripts, infra`; anything else exits 2.

## Issue disposition

Phase 2 completes #7535's residual scope, so the PR body uses **`Closes #7535`** — in the body,
never the title (`wg-use-closes-n-in-pr-body-not-title-to`). Phase 1 correctly used `Refs`,
because it reduced the apt dependency without addressing the misattribution the issue is about.

The issue is already retitled to its residual scope and the `## Why the image was cut`
measurements are already posted there (Phase 1 task 1.10), so nothing further is owed on the
issue beyond the close.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| D2 routes a starved apt to `harness-defect` and produces 11 spurious hard FAILs | D2b preserves the measured rc; D2c forbids `exit 2`; Guard 2 mutation row 3 **demonstrates** the failing direction rather than asserting the design is safe |
| The T17 rc capture is silently clobbered | The `; _t17m_rc=$?` assignment stays on the same line as the command (the file's own stated reason); Guard 1 row 6 is the observing row |
| The new INJECT tokens collide with R4's and a row starves the wrong arm | Namespaced tokens (D1e); Guard 1 harness row H3 is the must-PASS control that proves it |
| A token is reworded on one side only, so every mutation row silently tests a healthy run | Guard 1 harness row H2; pin the token once rather than replicating the literal — the `_T5_MARKER` precedent |
| D3's floor raise edits the frozen 19-era baseline | AC18 asserts `git diff` shows zero changes to it and to every earlier stanza; the convention is quoted in `### Conventions` |
| The floor is incremented by arithmetic rather than measured | AC18 requires the measured terminal line to be quoted; the file's own convention says re-derive |
| A new `arm_skip` or `_skip` slips in and breaks the roster/ceiling assertions | AC16 and AC17 assert both counts unchanged |
| Phase 2 trips the shell-capture lint | AC14; the phase adds no command substitution |
| Verification is claimed from a docker-less green | `## Verification` items 1-4; every AC carries a provenance tag |
| The discoverability probe fails at ship on a correct tree | AC24 re-measures it; the Sharp Edge records why the previous probe rotted |
| ADR-188 keeps instructing a reader to build the cut image | D4; AC22 |

## Non-Goals

- **NG1** — A pre-baked fixture image, in any form, published or local. Cut on measured evidence.
  D4 records the cut **and** the `[ ! -d /run/sshd ]` guard any revival would owe.
- **NG2** — `FIXTURE_IMG` / `FIXTURE_PACKAGES` chokepoints, and Guards 1-3 of the earlier
  revision. Cut with the image. (Not to be confused with `## Guard Contract` Guards 1-2 here,
  which are contracts over arms that already exist.)
- **NG3** — Publishing to GHCR or zot.
- **NG4** — `--network none` at any site.
- **NG5** — Digest-pinning `ubuntu:24.04` beyond the pin already in `UBUNTU_BASE` (#7544).
- **NG6** — Changing the floor's comparison operator from `-lt` to `-ne`. The file records the
  rejection and its two grounds; do not reopen it here.
- **NG7** — Adding retry/backoff outside the R4 site #7507 owns.
- **NG8** — Re-splitting or re-wording the `run_case` and T5-mutation sites (#7510's work), or
  adding cause-level naming to `run_case`'s verdict.
- **NG9** — Reclassifying the T17 starvation from a named FAIL to an `arm_skip`. That is a
  reclassification, not naming, and it costs the roster identity, the ceiling stanza and a
  follow-through probe. See the Cut List.
- **NG10** — Modelling Docker Hub in C4 (pre-existing, unchanged).
- **NG11** — Any other suite in `infra-validation.yml`.

## Architecture Decision (ADR/C4)

**[Updated 2026-09-17] One ADR amendment, no new ADR, no C4 change.** The earlier revision said
"No ADR, no C4 change", and the first half of that is now wrong.

### ADR

**Amend ADR-188** (`ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`) — D4. Its
`## Alternatives Considered` records the pre-baked image as *"DEFERRED, and preferred over retry
when it lands"*, and its S1/T5 residual instructs a reader that the image is *"owed immediately"*
past a skip-rate threshold. The 2026-08-13 measurement cut that design; leaving the ADR as-is
means the recorded architecture instructs the next reader to build it. The amendment is a
**deliverable of this plan**, not a follow-up issue. No new ordinal is claimed, so no
ordinal-collision probe across `origin/*` refs is needed; if a later revision does claim one,
re-derive it against freshly-fetched refs immediately before merge and sweep this plan, the spec
and the tasks for the old number in the same edit.

Also amended: ADR-188's decision that an apt starvation is an environment decline for `_s1_run` is
**reinforced**, not reversed — D2 names the cause while preserving the `did-not-run` routing, and
Guard 2 row 3 demonstrates what reversing it would cost (11 hard FAILs).

### C4 views

**No C4 impact**, and here is the enumeration that supports it — read against all three model
files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`), by
content anchor:

- **External human actors.** The only actor this change's surface involves is `contributor`
  (`model.c4`, anchor `contributor = actor "Contributor / PR Author"`, `#external`, with the
  `contributor -> github` edge). Already modeled; its description is not falsified — this change
  adds no execution surface reachable from a PR head.
- **External systems / vendors.** `ghcr` (anchor `ghcr = system "GitHub Container Registry"`),
  `projectZot` (`projectZot = system "project-zot upstream registry (public)"`) and `zotRegistry`
  (`zotRegistry = system "Self-hosted zot registry"`) are all modeled and all included in the two
  `views.c4` view include-lists. No edge is added to any of them — the image is cut, so nothing
  touches the registry path. **Docker Hub** (the `ubuntu:24.04` source) remains **unmodeled**;
  that is pre-existing and unchanged by this diff, and is recorded as NG10 rather than silently
  omitted.
- **Containers / data stores.** None touched. The change is confined to a shell test's messages
  and one assertion.
- **Actor↔surface access relationships.** None change. No new credential, no new boundary, no
  ownership or tenancy move.
- **Derived cardinalities.** `model.c4` embeds counts on several edges (workflow counts, monitor
  counts, emitter counts) that the actor/system rubric does not reach.
  `bash plugins/soleur/test/c4-count-parity.test.sh` is **green** — 10 passed, 0 failed, measured
  2026-09-17 on this branch — so no embedded count moves. AC23 re-asserts it and asserts the
  diagrams directory is untouched.

### Sequencing

None. The ADR amendment describes a decision already taken and measured; it does not describe a
target state contingent on a later slice, so it ships as `accepted` prose inside the existing ADR
rather than as an `adopting` note.

## Domain Review

**Domains relevant:** Engineering, Product.

### Engineering

**Status:** reviewed
**Assessment:** Seven-agent panel (2026-08-13). The image was cut on measured evidence (public
repo → $0; never the critical path → 0 s) plus two hazards it would have introduced. The surviving
work — FR1 and failure-naming — was endorsed by DHH, code-simplicity, CTO and CPO independently as
the highest-ratio subset.
**[Updated 2026-09-17]** Re-scoped, not re-reviewed: two of the four Phase-2 sites were shipped by
#7510 and are cut from scope; the two survivors are re-anchored by content against `main`; and
three new mechanical constraints were measured out of the code rather than assumed — that
`fixture_fail`'s `exit 2` would produce 11 hard FAILs at `_s1_run`, that an `arm_skip` at T17
would break two roster assertions and the ceiling stanza, and that the previous
`discoverability_test` probe now fails on a correct tree. The reduced diff is smaller than the
version the panel endorsed, and no mechanism the panel cut is restored.

### Product

**Status:** reviewed
**Assessment:** CPO measured the value proposition and recommended cutting to FR1, noting #7535
and #7544 both sit in `Post-MVP / Later`. The operator chose FR1 plus failure-naming — the
increment that addresses the misdiagnosis cost, which is the one value the measurement supports.
**[Updated 2026-09-17]** Unchanged. Phase 2 closes the issue, which removes a `Post-MVP / Later`
item and the standing investigative tail behind it.
