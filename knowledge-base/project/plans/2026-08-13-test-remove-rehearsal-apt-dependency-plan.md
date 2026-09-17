---
title: "test(infra): stop the rehearsal's apt failures reading as emitter findings (image cut on measurement)"
date: 2026-08-13
updated: 2026-09-17
revision: R2-deepened
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


## Revision R2 — deepen-plan, 2026-09-17 (reconciled against a concurrent implementation)

**An implementation of Phase 2 landed in this worktree WHILE this plan was being deepened, and it
is UNCOMMITTED.** Measured: the target file was 3630 lines and clean (`git diff origin/main...HEAD`
empty) when this plan's site census was taken, and is now 3717 lines with `+101/-14` unstaged;
`scripts/followthroughs/t5-skip-persistence-bound-7510.sh` is also modified. Neither change is
mine — this session's scope is the plans and specs trees only — and nothing here reverts them. What
follows reconciles the plan to them, adopting the tree where the tree is right and naming what it
still owes. **`/work`'s first action is to decide whether that uncommitted work is the baseline
(R2's assumption) or is to be discarded**, and to record the decision.

**Where the tree is RIGHT and R1 was WRONG:**

| R1 position | Why it was wrong | R2 |
|---|---|---|
| The Cut List cut `arm_skip` at T17 on blast radius; **NG9**; the roster AC asserted both counts unchanged | The argument was about **scope** ("reclassification is not naming"), never correctness. ADR-188 is the governing decision and is unambiguous: for a precondition **nobody owns** — the apt archive's state at that instant — the honest verdict is a *declared skip*, not a FAIL. T17-mutation's direct sibling T5-mutation declines on the **identical** condition, with the identical `'100 125'` allowlist and the same image; so does S1. A hard FAIL at T17 alone needed a correctness justification and R1 had only a scope one. The four costs R1 called prohibitive are real, and the tree **paid all four** — `_T17_SKIPS` folded into `_PROBE_NAMED`, the stanza assertion moved to 4, `_SKIP_CEILING` 7 -> 8 with its own itemised row, and the follow-through probe's `SKIP_MARKERS` extended. R1's NG9 was also **unenforceable** (D9) | **Adopted.** NG9 withdrawn; AC17 rewritten from *invariance* to *consistency* |
| The Cut List cut `_T17M_ENV_RCS` — "T17 makes no routing decision" | False under the line above: the arm now routes (decline vs harness-defect), so the allowlist is required for the file's own stated reason — *"Reading every non-zero rc as an environment decline hands the skip bucket every HARNESS defect too"* | **Adopted** |
| D1c/D1d prescribed reusing `_T5_MARKER` (`DRIVER_REACHED_DL`) as the discriminator | Strictly worse: `DRIVER_REACHED_DL` is emitted *after* `drive.sh`'s `:8099` bind guard, so its absence conflates apt starvation with a bind failure. The tree's `_T17M_MARKER='T17M_APT_OK'`, echoed right after the two apt statements, isolates apt | **Adopted** |
| D2e required a new `FIXTURE-APT:` marker family, deliberately not matching the nested runner's `MARKER_ERE` | The ERE reasoning was right; the **channel** reasoning was missing. Measured: the S1 literal reaches the log only through `S1_NOTE`'s `tail -3 … \| tr` fold — mid-line, behind `docker rc=…` — so the `^` anchor never fires on it, and a repo sweep finds **no consumer outside this file** greps `FIXTURE-FAIL`. Against that, `FIXTURE-FAIL:` is the file's established family for "the fixture, not the subject" (the `mktemp` guard, `fixture_fail`, the S1 mount-source guard, the R4/R3 arm), and a second family costs the rename hazard the file spends a hundred lines closing | **Relaxed.** `FIXTURE-FAIL:` is correct; `FIXTURE-APT` is dropped from the plan, spec and tasks |
| The discoverability probe was `grep -c FIXTURE-APT:` expecting `"8"` | `FIXTURE-APT` is **0** everywhere — on `main`, in the tree, and in the whole repo. The probe was dead on arrival, and preflight Check 10 **executes** it. This is the *second* consecutive revision whose probe rotted, the second one inside the Sharp Edge written to prevent the first | **Re-derived** on a token this PR owns |
| Conventions / TR7 / AC14 said "Phase 2 adds no command substitution" | The tree adds two (`_t17m_tail="$(tail -3 …)"`, `_T17_SKIPS=$(grep -cE … "$0")`) and the gate is **still green**: measured `0 new findings, 203 baselined`, baseline untouched. The constraint was always the gate, never the absence of `$( )` | **Restated as the gate** |
| D3 used the S2(m) `pass`-on-landed shape, raising the floor | The signal is **free from the rc**: `on_err`'s `[ "$rc" -eq 0 ] && exit 0` is the line the `sed` removes, so a landed-and-ran mutant exits 1 and a non-landed one exits 0 | **D3 deleted**, folded into D1d(ii) at zero cost |

**Where the tree is WRONG or incomplete.** D1b's sink siting, D1c's per-statement naming, D1d's two
missing rungs, D1e's injection, D2b's rc preservation, and D4/D5/D6/D7/D8 are what remain. D2f is
cut.

**New at R2, from the deepen pass:** **D5** (a structural pin for `_T17M_MARKER` — without it a
one-sided rename turns the arm into a permanent green decline), **D6** (retiring the superseded
"the image is owed" instruction from its two *executable* carriers — the only thing that actually
buys P7), **D7** (an in-suite census, because R1's detector for P8 was a comment), **D8** (a CI
refusal of fault injection, because D1e plus `arm_skip` otherwise makes one env var green a
required gate), and **D9** (recording a pre-existing roster/ceiling defect this PR must not inherit
silently). D1d(i) — the capture-server-bind rung — is the pass's headline finding: on the tree as
built a bind failure is announced as *"a genuine vacuity finding"*, which is the #7535 defect class
reintroduced one hypothesis over.

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
| The target file | `wc -l` + `git status` here and on `origin/main` | `origin/main`: **3630**. **This worktree: 3717, ` M` (uncommitted)** — R1 recorded them byte-identical, true when R1's census was taken; an implementation landed during the deepen pass (see Revision R2). Every R1 line number has shifted; **all anchors are by content** |
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
- **P1** — *"T17 MUTATION … the check is vacuous"* is emitted **only** when the arm is genuinely
  vacuous. Four other causes of an empty capture must each route elsewhere first: the container
  never started, apt starved, the **capture server never bound**, the mutating `sed` **did not
  land**.
- **P2** — A starved apt at the T17 site is named **per statement** (`update` distinguishable from
  `install`).
- **P3** — At the T17 site a failing `apt-get update` aborts the container instead of falling
  through into `drive.sh` with no `curl`/`python3`.
- **P4** — At `_s1_run`, a starved apt is named per statement **and** keeps routing to
  `did-not-run`/`arm_skip` (an honest declared decline per ADR-188), never to `harness-defect`.
- **P5** — A healthy run emits none of the new literals and declares no skip.
- **P6** — The T17 marker cannot be reworded on one side only: a rename that makes it permanently
  absent must red the suite, not turn the arm into a permanent green decline.
- **P7** — Neither the recorded architecture **nor any live automation** instructs a future reader
  to build the pre-baked image the measurement cut.
- **P8** — A future edit that restores an AND-OR apt pair, or drops a container's rc capture, is
  detected by the suite rather than by a comment.
- **P9** — A set `GIT_DATA_REHEARSAL_INJECT` token cannot green a required gate.

### Cut List — mechanisms removed, with what already buys them
| Mechanism | Property | What already covers it |
|---|---|---|
| Re-splitting `run_case` / T5-mutation | P3 there | On `main` since `45ea9f7e9` (#7510) |
| `Acquire::Retries` at the two target sites | retry | Bought at R4 by `dfcf7bd26` (#7507); extending it is a separate decision — NG7 |
| Restructuring `_s1_run`'s apt pair | rc propagation | Already bought: the statements are separate and final-position, so `set -e` fires and rc 100 reaches `_s1_classify`, which allowlists it. **Naming only** |
| **A `diff -q`/count mutation-landed pre-check (R1's D3)** | P1's fourth leg | **Free from the rc.** `on_err` ends `[ "$rc" -eq 0 ] && exit 0` — the exact line the `sed` removes. Landed-and-ran -> `exit 1`; **not landed -> the guard survives -> rc 0**. So `rc == 0` with the marker present *is* the not-landed signature: no `diff`, no assertion, no floor move. **D3 deleted; the rung folds into D1d(ii)** |
| **D2f — INJECT plumbing at `_s1_run`** | executable S1 rows | Cut on proportion: D2 changes **no routing**, so the rows would only prove that an `echo` visible in the driver text reaches a `tail`. Guard 2's rows poison apt in-driver instead — which is also the only form that exercises the `\|\| { … }` handler its row 3 mutates |
| **A new docker-free verdict-ladder harness** | a non-proxy probe | **Declined; a reviewer may overrule.** It is the honest answer to the probe's proxy problem, but it is a new registered suite — nothing auto-discovers it (`lint-orphan-test-suites.sh` produces from `git ls-files '*.test.sh'`; `run-registered-suites.sh` derives from `infra-validation.yml`), so it costs a workflow step plus a registration whose absence would pass silently. **D7** detects P8 in-suite and the proxy limit is declared |
| Pre-baked image, GHCR/zot, digest-pinning, `--network none` | apt off the gate path | Cut on measured evidence; revival guard in D4, superseded instruction retired by D6 |
| ~~`arm_skip` at T17~~ / ~~`_T17M_ENV_RCS`~~ | — | **UNCUT at R2** — both were cut on a scope argument ADR-188 overrides, and NG9 was unenforceable anyway (D9) |

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
- **NO APOSTROPHE inside a `bash -c '…'` recipe.** The T17 recipe is a single-quoted **host**
  string, so one `'` in an added comment, literal or token is a whole-file syntax error — measured,
  `bash -n` rc 2, *"unexpected EOF while looking for matching quote"*. The file's existing
  in-container comments are apostrophe-free by construction (the tree's author wrote `apt-s own rc`
  to dodge it). Host-side strings are unconstrained. D1a, D1c and D1e all add text in that recipe.
- **`_T5_MARKER`'s structural pin covers `drive.noerrexit.sh`, not `drive.noguard.sh`** — measured.
  Coverage of the T17 artifact is transitive only because both are `sed`s of `$TMP/drive.sh`. Do not
  cite that pin as covering T17; **D5** is what pins the T17 marker.
- **The same-line `$?` rule has one standing exception: `run_case` puts `local rc=$?` on the next
  line.** NG8 forbids touching it, so do not "fix" it.
- **Enumerate rc classes ONCE.** `_T5M_ENV_RCS`/`_S1_ENV_RCS` exist *"so the routing and the offered
  classification cannot drift apart"*. The tree's `_t17m_rc_note` re-spells them as a bare literal —
  a third hand-copy. Interpolate a variable.
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
- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — D1, D2, D5, D7, D8
- `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md` — D4
- `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` — D6, plus the `SKIP_MARKERS` entry
  the tree already added. **Missing from R1's list while the tree already modified it, so the
  diff-scope AC was failing at the moment R2 was written.**
- `.github/workflows/scheduled-rehearsal-skip-monitor.yml` — D6. R1 said "No workflow edit"; that
  was wrong. This workflow is one of two *executable* carriers of the superseded *"the deferred
  pre-baked image (#7535) is owed"* instruction, and **P7 is not bought by amending ADR-188 prose
  while a daily monitor keeps emitting it to the operator.**

Also written by the pipeline, and therefore inside the diff-scope AC: this plan, the spec and
tasks under `knowledge-base/project/specs/feat-prebake-rehearsal-image-7535/`, the generated
`knowledge-base/INDEX.md`, and `specs/<branch>/session-state.md` if the pipeline writes one.

No new source file, no new test suite, no `.tf`, no Dockerfile, no registry step, no secret, no
scheduled job, no `.c4` edit.

**Artifact-location note.** The spec directory is `feat-prebake-rehearsal-image-7535` while the
branch is `feat-one-shot-7535-rehearsal-apt-misattribution`. The name is historical (the "prebake"
slug predates the image cut) and is kept rather than renamed: it is where the reviewed spec lives
and a `git mv` across sibling worktrees is not worth the churn. The frontmatter carries both
`branch:` (current, so the plan selector resolves) and `spec_dir:`.

## Implementation Phases

### Phase 1 — delete the no-op `e2fsprogs` install — **SHIPPED**

Merged 2026-08-13 as `910f237f0` (PR #7540). Deleted the `apt-get update` / `apt-get install -y
-qq e2fsprogs` pair and the then-dead `export DEBIAN_FRONTEND=noninteractive`, replacing them with
a comment recording that `ubuntu:24.04` ships `e2fsprogs 1.47.0-2.4~exp1ubuntu4.1` at
`Priority: required`, and that the deletion narrows R1's `e2fsprogs` source from mirror-current to
image-current — a faithfulness improvement, not a no-op. Verified on CI runs 31711619961 (main)
and 31717913686 (PR), both `44 passed, 0 failed`.

### Phase 2 — name the two remaining apt cycles (this work)
Both predecessors are merged. **An uncommitted implementation of D1a/D1b/D1d-partial/D2a already
exists in this worktree** (see `## Revision R2`); each deliverable below says what is done and what
is owed. Re-derive every anchor from the tree by **content**.

#### D1 — T17 MUTATION (primary)

Anchor: `# MUTATION: remove the rc guard and prove T17's assertion can FAIL`.

- **D1a — split the AND-OR list. DONE.** The two-statement form landed with the measured
  mechanism-(b) comment. `grep -cE '^[^#]*apt-get update.*&&.*apt-get install'` is now **0**.
- **D1b — capture the rc through the removed `|| true`. DONE; one correction owed.** The tree has
  `; _t17m_rc=$?` on the same line, not `local`. **OWED: move the sink out of the bind mount** —
  write `$TMP/t17m.stdout`, not `$TMP/out/…`. Two reasons: `$TMP/out` is mounted
  `-v "$TMP/out:/out"`, so the marker's evidence file is writable by the **mutated driver under
  test**; and `$TMP/out/stdout` is `run_case`'s own capture file, into which the
  `run_case "T17 healthy run exits 0"` arm one arm above writes `DRIVER_REACHED_DL` — a reordering
  of the `rm -rf "$TMP/out"` line would make the marker read find the *healthy* run's output and
  print the vacuity message for a container that never started.
- **D1c — name each apt statement. OWED.** The tree emits only the positive `T17M_APT_OK`, so **a
  starved `update` is indistinguishable from a starved `install`** — P2 unbought, and "a CI log
  names which spin starved" was the issue's own language. Add one fixed literal per statement,
  preserving the measured rc: `|| { _rc=$?; echo "FIXTURE-FAIL: T17 mutation container — apt-get <stmt> starved (…)" >&2; exit "$_rc"; }`.
  Never echo apt's own output; keep `>/dev/null 2>&1`.
- **D1d — the verdict. PARTIAL; two rungs owed, and they are the deepen pass's headline finding.**
  The tree has four rungs (pass / `arm_skip` on marker-absent + allowlisted rc / harness-defect
  `fail` on marker-absent + rc outside the allowlist / vacuity `fail`). Two causes still land on
  **vacuity**:
  - **(i) the capture server never bound — OWED; the #7535 defect class reintroduced one hypothesis
    over.** Measured: `echo T17M_APT_OK` precedes `bash /work/drive.sh`, and `drive.sh`'s guard is
    `(echo > /dev/tcp/127.0.0.1/8099) 2>/dev/null || { echo 'FIXTURE: capture server never bound :8099' >&2; exit 2; }`.
    So a bind failure yields **marker PRESENT, rc 2, capture empty** and takes the `else` branch,
    whose detail asserts *"`T17M_APT_OK` present, so apt succeeded and this is a genuine vacuity
    finding"* — a deterministic, actionable fixture defect announced as a vacuity finding. The
    T5-mutation arm already carries the rung that prevents it
    (`elif grep -q "$_T5_FIXTURE_MARKER" … then _t5m_state=fixture-defect`) and the file calls the
    rung's position load-bearing: *"Put the fixture rung any lower and that run satisfies
    `did-not-run` exactly … That is the outcome the whole arm is built to prevent."* Add a
    `FIXTURE:` rung **above** the vacuity branch, reading `$_T5_FIXTURE_MARKER` from the captured
    stdout, ordered as T5 orders its conditions.
  - **(ii) the mutating `sed` did not land — OWED, and FREE.** `on_err`'s
    `[ "$rc" -eq 0 ] && exit 0` is the line the `sed` removes; once removed `on_err` always ends
    `exit 1`. So a landed mutant that ran exits **1** and a non-landed one exits **0**. `rc == 0`
    with the marker present *is* the not-landed signature. This replaces R1's D3 entirely.
  - **Offer the rc classes honestly, from ONE variable.** The classes reachable here are **0**
    (did not land), **1** (the mutant ran), **2** (no bind), **100** (apt), **125** (docker/image
    pull). The tree's note re-spells only two, as a bare literal — a third hand-copy of what
    `_T5M_ENV_RCS`/`_S1_ENV_RCS` exist to state once. Interpolate.
  - Keep `_T17M_ENV_RCS` and `arm_skip` (R2 adopts both) and keep `grep -qx`, never `grep -q`.
- **D1e — fault injection at T17. OWED, with three constraints.** Add
  `-e "GIT_DATA_REHEARSAL_INJECT=${GIT_DATA_REHEARSAL_INJECT:-}"` and honour **namespaced** tokens
  `t17-apt-update` / `t17-apt-install`.
  - **Compare with exact `=` on a quoted `$INJECT`, mirroring R4** — never a `case` glob, never
    `=~`. Measured: R4 tests `[ "$INJECT" = "apt-update" ]`, so `t17-apt-update` cannot reach R4; a
    glob form here would let R4's token starve T17, the collision no row otherwise tests.
  - **Poison apt; do not `exit` directly.** An arm that `exit 100`s never enters the `|| { … }`
    handler, so the injected and real observables diverge and the rc-preservation row cannot be
    demonstrated. R4 gets away with a direct exit only because its handler *is* `fixture_fail`.
  - **D8 is a precondition of D1e, not a nicety.**

#### D2 — `_s1_run` (naming only, NOT restructuring). DONE; one correction owed.

Anchor: the `S1DRV` heredoc's `apt-get install -y -qq openssh-server`.

**Why this site differs from the `&&` sites.** The two statements are separate and each is
final-position, so `set -e` **does** fire and the rc reaches `_s1_classify` as 100, which
`_S1_ENV_RCS='100 125'` allowlists. The rc-propagation property D1a buys at T17 is already bought
here; only the *name* was missing. The tree's comment says this well — keep it.

- **D2a — naming. DONE.** Two distinct literals, emitted **before** `echo "S1_FIXTURE_OK"` so the
  classification stays `did-not-run` rather than `fixture-defect`.
- **D2b — preserve the measured rc. OWED.** The tree pins `exit 100`. apt-get exits 100 for
  essentially every documented failure, so the pin is usually faithful — but it **launders any
  other rc into the environment allowlist**, converting a harness defect into a green decline. Use
  `_rc=$?; …; exit "$_rc"`, **inside the `<<'S1DRV'` heredoc immediately after each `apt-get`** —
  not at `_s1_run`'s `docker run`, where `_rc` would be an unlocalised host global and `exit` would
  end the whole suite.
- **D2c — DONE.** Neither handler uses `fixture_fail` or `exit 2`. Had it, `_s1_classify` would
  return `harness-defect` at all five call sites: **11 hard FAILs** on a mirror blip (S1 healthy 2,
  S1 mutation 3, S2(h-j) 3, S2(k-l) 2, S2(n) 1 — counted from the `case` arms).
- **D2d — extended.** The tree correctly does not move `echo "S1_FIXTURE_OK"` up. **Also forbid
  ADDING an apt statement below it**: one below makes rung 2 fire and produces the same 11 hard
  FAILs, through a door R1's D2d only half-closed.
- **D2e — RELAXED at R2; `FIXTURE-FAIL:` is correct.** R1 required a new `FIXTURE-APT:` family
  because `FIXTURE-FAIL:` matches `run-registered-suites.sh`'s
  `MARKER_ERE='^[[:space:]]*(\[FAIL\]|[A-Z][A-Z0-9]*-FAIL|FAIL)([[:space:]:_-]|$)'`. The ERE
  reasoning was right; the **channel** reasoning was missing. The literal reaches the log only
  through `S1_NOTE`'s `tail -3 … | tr '\n' ' '` — mid-line, behind `docker rc=…` — so the `^`
  anchor never fires, and a repo sweep finds no consumer outside this file that greps
  `FIXTURE-FAIL`. Against that, `FIXTURE-FAIL:` is the file's established family for "the fixture,
  not the subject". Record in the comment that **the `tr` fold is now load-bearing** for the
  non-match.
- **D2f — CUT at R2.** See the Cut List.

#### D3 — DELETED at R2. Folded into D1d(ii) at zero cost.

#### D4 — amend ADR-188. OWED. Scope extended at R2.

R1's scope (image CUT + replacement trigger + revival guard) left four things the cut falsifies:

1. **The image is CUT, not deferred** — with the three measurements and the two hazards.
2. **The retry alternative's reconsideration condition becomes unsatisfiable.** It reads
   *"Reconsider only if the pre-bake lands and the flake persists"*; if the pre-bake can never land
   and **NG7** forbids retry outside R4, retry is closed with no path to reopen — which nobody
   decided. Restate it or record retry as CUT too.
3. **The non-declinable-arm enumeration goes stale.** ADR-188 lists four non-declinable
   container-dependent arms including *"**T17** (`run_case` rc plus its mutation arm)"* and states
   the real invariant is *"at least one container-dependent arm must remain non-declinable"*.
   Making the T17 **mutation** arm declinable narrows the set to T5-primary, T17-healthy (via
   `run_case`, which still hard-fails on an rc mismatch) and R4 — so **the invariant holds and the
   enumeration is now wrong.** Correct it and say so, rather than letting a reader infer a break.
4. **The Carrier note's roster** names *"both T5 and S1"*; T17 joins it, and the
   `### The ceiling moves 2 → 5, itemised` table gains a fourth row.
5. **Preserve the `[ ! -d /run/sshd ]` revival guard** as a precondition on any revival —
   installing `openssh-server` at build time can make `/run/sshd` exist at runcmd time and
   **silently invalidate S1 rather than fail it**. Distinguish it from the separately-deferred
   `/out/setup.log` capture, so "the image is cut" is not read as "all network-observability work
   here is cut".

No new ADR ordinal, so no `origin/*` collision probe. Replacement re-evaluation trigger: Infra
Validation becomes the longest workflow on a PR's head SHA in >= 3 consecutive runs, read with
`gh api "repos/jikig-ai/soleur/actions/runs?head_sha=$SHA"`.

#### D5 — pin `_T17M_MARKER` structurally. OWED.
The tree defines `_T17M_MARKER='T17M_APT_OK'` on the host and emits a bare `echo T17M_APT_OK`
inside the inline recipe, with **nothing pinning the two together** — unlike `_T5_MARKER` and both
S1 markers, each of which carries a structural guard the file spends a hundred lines justifying. A
reword on either side alone makes the marker permanently absent, which now routes **every** run
into `arm_skip`: a silent, permanent GREEN decline — strictly worse than the pre-change state,
where the same mistake would have failed.

The recipe is an inline single-quoted string in this file's own source, not a mounted file, so the
pin is a text check over `"$0"` — the idiom R1-PIN and the `arm_skip` roster already use (five
existing `grep … "$0"` sites). Assert that `"$0"` carries `echo <marker>` exactly once, via the
`$_T17M_MARKER` variable rather than a replicated literal. **+1 assertion.**

#### D6 — retire the superseded "the image is owed" instruction. OWED.
Two *executable* carriers still tell the operator the cut design is owed:
`scripts/followthroughs/t5-skip-persistence-bound-7510.sh` (three sites, including its exit
contract) and `.github/workflows/scheduled-rehearsal-skip-monitor.yml` (one site). Rewrite both to
point at the replacement trigger. Keep the probe's counting behaviour unchanged — it is the **only**
recurrence signal for a green decline, and D1's `arm_skip` adds a fourth arm to it. The tree
already added `'SKIP (loud): T17 '` to `SKIP_MARKERS`; keep and assert it.

#### D7 — an in-suite structural census. OWED.
P8 has no detector today: R1's answer was *a comment* plus a plan-time probe that never runs
post-merge. Add a container-independent text check over `"$0"`, in the R1-PIN idiom: zero
`apt-get update … && apt-get install` AND-OR pairs on non-comment lines, **with an anti-vacuity
floor on its own grep** (the census must confirm it found the apt sites at all, so a narrowed
pattern that matches nothing cannot read as clean); and zero `docker run … || true`.
**+1 to +2 assertions.**

#### D8 — refuse fault injection under CI. OWED; a precondition of D1e.
Combining D1e with the adopted `arm_skip` design creates a **one-env-var vacuous green**, traced
end to end: `GIT_DATA_REHEARSAL_INJECT=t17-apt-update` -> the container exits before the marker ->
rc in `_T17M_ENV_RCS` + marker absent -> `arm_skip … 1`. `arm_skip` increments
`SKIPPED_ASSERTIONS` and **never appends to `FAILURES`**; `total` counts the skip so the floor is
satisfied; `1 <= _SKIP_CEILING`; the roster identity holds; and the verdict is
`exit $(( ${#FAILURES[@]} > 0 ))` -> **0**. *Deleting* the arm reds; *switching it off with one
variable* does not — exactly the residual Guard 1's Anchor names, now reachable from the
environment instead of a code edit.

Refuse it: before any arm runs, a non-empty `GIT_DATA_REHEARSAL_INJECT` under `CI=true` must
`echo … >&2; exit 1` **directly**, not through `fail()` (ADR-193: a floor routed through the
suspect cannot witness the suspect). R4's existing tokens are green-safe only by arithmetic —
measured, `apt-update` at R4 yields four hard FAILs — so D8 generalises the property. See **NG12**
for the workflow-surface corollary.

#### D9 — record the skip-roster and ceiling defect. OWED (record, do not fix).
Measured: the roster guard's `_SKIP_CALL_SITES=$(grep -cE '^[[:space:]]*arm_skip ' "$0")` returns
**4**, while the file has **7** executable `arm_skip` call sites — the three S2 ones are `case`-arm
one-liners (`did-not-run) arm_skip "S2(h-j) …" 3 ;;`) the line anchor cannot see. Consequences, all
pre-existing and all touched by this PR:

- The declarable skip budget is **14** against `_SKIP_CEILING=8`. One unpullable image declines
  every arm, so a legitimate ADR-188 decline already produces `skip ceiling exceeded` — the
  spurious second failure the ceiling's own stanza says it exists to prevent.
- The `-eq N` stanza assertion and the `_PROBE_NAMED == _SKIP_CALL_SITES` identity are blind to
  half the roster, so **R1's NG9 was unenforceable anyway**: a `did-not-run) arm_skip "T17 …" 1 ;;`
  one-liner would have moved neither count.
- `SKIP_MARKERS` in the follow-through probe has no `S2(` entry either.

**Disposition: acknowledge, do not fold in** (NG13). Fixing it means re-deriving the ceiling from a
true seven-site roster and re-anchoring three `case` arms — a different change with its own
mutation matrix. Record it in the plan and in the ceiling stanza's comment, and file it with the
measurements (`wg-when-deferring-a-capability-create-a`). Phase 2 must not *worsen* it: D1's
`arm_skip` is written at line-start so the census does see it.

## Guard Contract
### Guard 1 — the T17-MUTATION anti-vacuity verdict

**Property.** *"T17 MUTATION … the check is vacuous"* is emitted **if and only if** the mutation
landed, the container ran, the capture server bound, and the capture is still empty. Every other
cause of an empty capture routes to a rung that names it.

**Assembly.** The chokepoint is the single `if`/`elif…`/`else` verdict following this arm's one
`docker run`. Its inputs are `[ -s "$TMP/out/capture.log" ]`, the container rc, and two greps over
the captured stdout — `grep -qx "$_T17M_MARKER"` and `grep -q "$_T5_FIXTURE_MARKER"`. The property
quantifies over **every message in the file that claims this arm's result** (census
`grep -n 'T17 MUTATION' "$0"`, not a name list) and over **every rc class reachable at the site**
(`0 1 2 100 125`), not the two the tree currently offers. One container invocation, one verdict,
both between the `# MUTATION: remove the rc guard` comment and the `# ── S1 —` banner.

**Mutation matrix.** Every row is one container run, made executable by D1e/D8.

| # | Edit | Must |
|---|---|---|
| 1 | `GIT_DATA_REHEARSAL_INJECT=t17-apt-update` | the update literal appears; the verdict declines naming rc + marker-absent; the vacuity string does **not** appear |
| 2 | `…=t17-apt-install` | same, naming *install*; the two literals differ. Row 2 is what P2 buys — on the tree as built rows 1 and 2 are **indistinguishable** |
| 3 | Occupy `:8099`, or mount a `capture.py` that exits immediately | the **`FIXTURE:` rung** fires naming a fixture defect; the vacuity string must **not** appear. D1d(i); on the tree as built this row currently *produces* the vacuity message — the row's whole purpose |
| 4 | Rewrite the mutating `sed` so it matches nothing | the container exits **0**, the marker is present, the **not-landed rung** fires; no vacuity string. D1d(ii) |
| 5 | Reword `echo T17M_APT_OK` without touching `_T17M_MARKER` | **D5's pin reds.** Without D5 this silently routes every run to `arm_skip` — a permanent green decline |
| 6 | **Dispatch row:** delete the arm's `docker run` and verdict | the arm contributes fewer assertions than its route budget and the floor reds |
| 7 | **Second-member row:** add a third apt statement to the recipe, unchecked, and starve it | **D7's census reds** on the missing rc check. The instruction form ("the third is also named") is not a mutation — the observable is D7 going red |
| 8 | **Switch-off row:** `CI=true GIT_DATA_REHEARSAL_INJECT=t17-apt-update` | **D8 reds with `exit 1`.** Without D8 the suite exits **0** over an arm that ran nothing |

**Harness rows.**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Reword the injected token on one side only | row 1 reds. Pin the token once rather than replicating it |
| H2 | Implement D1e's comparison as `case "$INJECT" in *apt-update*)` instead of exact `=` | a run with R4's `apt-update` token must then **also** starve T17 — the collision in the direction no other row tests |
| H3 | **Must-PASS, non-canonical:** full suite, real daemon, **no** INJECT | the T17 arm passes, `Skipped: 0`, none of the new literals appear. This — not an R4-token run — is the uncontaminated must-PASS: measured, `GIT_DATA_REHEARSAL_INJECT=apt-update` starves R4 and yields four hard FAILs, so it cannot serve as a healthy control |

**Anchor.** Guard 1 stores two values a single diff could move alongside what they protect: the
assertion floor and `_SKIP_CEILING`. Both are anchored outside the arm by their itemised
`# RAISED <old> -> <measured>` stanzas plus the frozen 19-era baseline that must not move with
them, so a bare number change is visible in review. **Two declared residuals:** (a) a substitution
that holds the count constant — an arm replaced by a bare `pass` — is caught by no floor, and rows
1-5 cover it; (b) the roster census is blind to three call sites and the ceiling is under-itemised
by 6 (**D9**), so `_SKIP_CALL_SITES` is not a trustworthy external anchor until that is fixed.

### Guard 2 — the `_s1_run` environment-decline classification

**Property.** A starved apt inside the S1 driver reaches `_s1_classify` as `did-not-run` (an honest
declared decline) **and** its cause is named per statement. Never `harness-defect`/`fixture-defect`,
and never an unnamed decline.

**Assembly.** The chokepoint is the container rc from `bash /work/sshd-drive.sh`, consumed at the
single `S1_STATE="$(_s1_classify …)"` inside `_s1_run`. Consumers are every `case "$S1_STATE"` at
an `_s1_run` call site — census `grep -n '_s1_run "' "$0"`, five today, and the property is over
whatever that census returns. It also quantifies over **placement**: every apt statement must sit
**above** `echo "S1_FIXTURE_OK"`, because one below makes rung 2 fire and yields 11 hard FAILs. The
naming channel is `$TMP/s1out/stdout`, folded into `S1_NOTE` by `tail -3 … | tr '\n' ' '`.

**Mutation matrix.** D2f is cut, so rows 1-2 poison apt inside the driver rather than injecting a
token — which is also the only form that reaches the `|| { … }` handler row 3 mutates. Each is
paired with a known-negative so a baseline green cannot read as a pass.

| # | Edit | Must |
|---|---|---|
| 1 | Empty `/etc/apt/sources.list` and remove `sources.list.d` at the top of `S1DRV`, so `apt-get update` fails **through its own handler** | its literal appears in `S1_NOTE`'s tail; every S1/S2 arm declines; **zero** `FAIL:` lines name S1 or S2. **Expect `Skipped: 14 > 8` to red the ceiling** — that is D9, a known result, not this row failing |
| 2 | Same, poisoned so `install` is the failing statement | same, naming *install*; the two literals differ |
| 3 | Change D2b's `exit "$_rc"` to `exit 2`, **with row 1's poison applied** | all five call sites flip to `harness-defect`/`fixture-defect` -> 11 hard FAILs. **Must RED** — the evidence for **D2b** (the row mutates rc preservation, not the `fixture_fail` prohibition). Without the paired poison the edited line never executes and the row reports the baseline |
| 4 | Delete a naming echo but keep the exit, **with row 1's poison** | the arm still declines correctly, but the literal-presence AC reds |
| 5 | Add a third apt statement **below** `echo "S1_FIXTURE_OK"` and poison it | the arm flips to `fixture-defect` -> 11 hard FAILs. The placement half of the property; D2d's extension is the fix |

**Harness rows.** H1 — rename `_S1_FIXTURE_MARKER` on one side only: the existing structural guard
must red (verified: it is anchored on `^\s*echo "S1_FIXTURE_OK"\s*$` in the mounted driver, so the
new handler echoes do not disturb it). H2 — **must-PASS, non-canonical:** `S1_RESTART_MODE=fail
_s1_run` with no poison: every S2(h-j) assertion makes its normal verdict and no new literal
appears.

**Anchor.** Guard 2 adds no assertion and no `arm_skip` call site, so the floor and `_SKIP_CEILING`
must be unchanged **by D2** — an acceptance criterion. It is **not** an anchor for the change as a
whole: D1/D5/D7 move both deliberately, which is why the roster AC asserts *consistency* rather
than invariance.

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
### Phase 1 — SHIPPED 2026-08-13 (`910f237f0`), frozen

Satisfied at their merge commit and **not** re-asserted against today's `main`, whose counts have
all moved (the apt census returned 7 then and returns 15 now, because PR #7507 added named apt
strings to the R4 driver). Do not "fix" them. The record: 9 -> 7 apt invocations, non-comment
`e2fsprogs` 2 -> 1, `DEBIAN_FRONTEND` down by 1, R1's four arms identical across the change, floor
and total unchanged at 44, parity suite green, suite green — CI runs 31711619961 and 31717913686.

### Phase 2 — Pre-merge (PR)

Every AC carries an **evidence-provenance tag**: `[local docker]` with the quoted terminal summary
line, or `[CI run <id>]`. Untagged means **UNVERIFIED** and blocks PR-ready. The tag alone is not
enough — see the `Skipped:` clause in `## Verification`.

- **AC8** — At **the two Phase-2 sites** (not all 15 `apt-get` lines: `run_case` and T5-mutation
  have no injection channel and NG8 forbids touching them), every `apt-get update`/`install` is
  rc-checked at the point of failure and emits a distinct literal naming the site and the
  statement. Verified per site by one induced starve — **not** by a census grep, which returns 15
  lines on `main` (mostly R4 message text) and cannot tell a compliant tree from a
  non-compliant one.
- **AC9** — The literals are pairwise distinct as a **set** across the four emit points, so a log
  names which spin starved.
- **AC10** — Guard 1 rows **1-8** and harness rows **H1-H3** behave as tabled, each row's command
  and observed output in the PR body. Rows 3, 4, 5 and 8 currently fail on the tree as built; each
  must be shown flipping.
- **AC11** — Guard 2 rows **1-5** and H1-H2 behave as tabled. Row 3 must be **demonstrated RED**
  with row 1's poison applied — the evidence for **D2b** — and row 1's expected `Skipped: 14 > 8`
  ceiling red must be quoted so it is not read as a regression.
- **AC12** — A **pre-fix control that does not depend on the fix.** Revert the verdict on a scratch
  copy and induce the starve by poisoning apt inside the recipe (`--network none` is NG4). The arm
  must emit *"the check is vacuous"*. An **injected-token control is invalid** — the token is part
  of the fix, so on a reverted copy it is inert, apt succeeds, and the arm passes.
- **AC13** — **Paired, both directions, tagged inline:** on a healthy run the new literals appear
  **0** times; on an induced starve the matching literal appears **>= 1**. The 0-half alone is
  satisfied by the feature not existing, so neither half is claimable without docker.
- **AC14** — `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
  passes with **zero new capture-then-exit findings** and the baseline **unmodified**
  (`git diff --stat` empty on it; 7 entries for this file, may only shrink). *Restated at R2: the
  constraint is the gate, not the absence of `$( )`. The tree adds two command substitutions and
  the gate is green — measured `0 new findings, 203 baselined`.*
- **AC15** — Invariance of what Phase 2 must not touch: `grep -c 'Acquire::Retries'` unchanged at
  **3** (NG7); no new `_skip` call site; no edit to `run_case` or the T5-mutation site (NG8).
- **AC16** — `grep -cE '^[^#]*apt-get update.*&&.*apt-get install' <file>` is **0**, and D7's
  in-suite census asserts the same property with its own anti-vacuity floor.
- **AC17** — **Roster consistency, not invariance** *(rewritten at R2: R1 asserted "unchanged",
  which the tree falsifies and which was unenforceable anyway — D9)*. Five facts must agree:
  `grep -cE '^[[:space:]]*arm_skip '` == the `-eq N` stanza assertion == `_PROBE_NAMED` (with
  `_T17_SKIPS` folded in); `_SKIP_CEILING` == the sum in its itemised stanza; and
  `SKIP_MARKERS` in `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` carries
  `SKIP (loud): T17 `. D1's `arm_skip` must be at line-start so the census sees it.
- **AC18** — The floor is re-derived from a **measured** run (quote the terminal
  `… N passed, M failed, Skipped: S (T assertions)` line), a new `# RAISED 92 -> <measured>` stanza
  covers D5 + D7 + AC19's counter, and `git diff` shows **zero** changes to the frozen 19-era
  baseline comment and to every earlier `RAISED` stanza. Never compute the number arithmetically —
  which is why no literal raise target appears anywhere in this plan.
- **AC19** — The T17 arm contributes the **same** assertion count on every route, asserted
  **executably** in the file's own idiom (a counter snapshot around the arm plus an equality
  assertion, modelled on S1's *"expected exactly 13 on every route"*) — not left to a reviewer's
  arithmetic, as R1 left it. Budget its own assertion into AC18's measured floor.
- **AC20** — `bash apps/web-platform/infra/git-data-render-strip-parity.test.sh` passes. Measured
  green on this branch 2026-09-17: `15 passed, 0 failed`.
- **AC21** — The full suite passes with a **real docker daemon**, `Skipped: 0`, no INJECT set.
- **AC22** — ADR-188 carries a dated amendment covering all five D4 items, asserted on the
  amendment's own dated heading **and** on an *increase* in
  `grep -c 'run/sshd' knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`
  — the **full path**, because a bare `ADR-188-*.md` glob errors from the repo root and therefore
  passes by being ignored; and an *increase*, because "does not decrease" is satisfied by an
  amendment that was never written.
- **AC23** — D6: neither `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` nor
  `.github/workflows/scheduled-rehearsal-skip-monitor.yml` still tells the operator the pre-baked
  image is owed; both point at the replacement trigger; the probe's counting behaviour is unchanged.
- **AC24** — D8: with `CI=true` and a non-empty `GIT_DATA_REHEARSAL_INJECT` the suite exits **1**
  before any arm runs, reporting directly rather than through `fail()`. And no `workflow_dispatch`
  input for that variable ships — `infra-validation.yml`'s `workflow_dispatch:` stays input-free
  (verified today: no inputs, no step-level `env:` on the rehearsal step). NG12.
- **AC25** — `bash plugins/soleur/test/c4-count-parity.test.sh` green (measured 2026-09-17:
  10 passed, 0 failed) and `git diff --stat -- knowledge-base/engineering/architecture/diagrams/`
  empty.
- **AC26** — The `discoverability_test` command is **executed** and matches its pinned
  `expected_output`, re-measured on the final tree.
- **AC27** — Diff scope: only the paths in `## Files to Edit`. *(R1 failed this at the moment R2
  was written — the follow-through probe was already modified and unlisted.)*
- **AC28** — D9 is filed as an issue carrying its three measurements (line-anchored census **4** vs
  **7** true call sites; declarable budget **14** vs ceiling **8**; `SKIP_MARKERS` missing `S2(`),
  and the ceiling stanza's comment records it.
- **AC29** — After every edit inside the `bash -c '…'` recipe, `bash -n <file>` returns 0 — one
  apostrophe there is a whole-file syntax error (measured rc 2).
- **AC30** — PR body uses **`Closes #7535`** in the body, never the title.

## Observability
Phase 2 *is* observability work: the deliverable is that a starved fixture names itself instead of
being read as a finding about the emitter or about the mutation battery.

**Layer citation (`hr-observability-layer-citation`): layer 6 — the workflow run log, and nothing
else.** Layers 1-5 and 7 do not reach a GitHub-hosted runner's docker fixture: no Sentry client, no
Better Stack shipper, no Vector agent, no host journal. The synchronous step log plus the suite's
own stderr markers are the entire channel, and this plan says so rather than implying a richer one.

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
  destination: layer 6 — GitHub Actions step logs; the suite's FIXTURE-FAIL / FIXTURE: / fail()
               markers and arm_skip's "SKIP (loud):" lines, all on stderr
  fail_loud: yes — _skip exits 1 under CI=true (measured: exit 0 off-CI, exit 1 with CI=true),
             and infra-validation.yml carries a SEPARATE `docker info >/dev/null` step ordered
             BEFORE both docker-dependent suites, so a daemon-less runner reds the job rather
             than greening it. No _skip call site is added, and D8 makes a set INJECT token red
             under CI rather than decline.

failure_modes:
  - mode: apt starves at the T17-MUTATION site
    detection: IN-SURFACE, per statement. Each apt statement emits its own fixed literal (D1c)
               and the container exits with apt's own rc; the host verdict offers all five rc
               classes reachable at the site (0 did not land, 1 the mutant ran, 2 no bind,
               100 apt, 125 docker/image pull) plus marker-seen and a tail.
               MEASURED GAP ON THE TREE AS BUILT: no per-statement literal exists, so a starved
               update and a starved install are INDISTINGUISHABLE. D1c closes it.
    alert_route: a declared decline (arm_skip) naming the container, never the emitter
  - mode: the capture server never binds at the T17-MUTATION site
    detection: IN-SURFACE. drive.sh emits "FIXTURE: capture server never bound :8099" and exits
               2; the D1d(i) rung reads that literal ABOVE the vacuity branch, mirroring the
               T5-mutation ladder.
               MEASURED GAP ON THE TREE AS BUILT: the marker is echoed BEFORE drive.sh runs, so
               a bind failure presents as marker-PRESENT and takes the vacuity branch, whose
               detail asserts "apt succeeded and this is a genuine vacuity finding" — a
               deterministic fixture defect announced as a vacuity finding. D1d(i) closes it.
    alert_route: a hard fail naming a fixture defect, distinct from a decline
  - mode: the T17 rc-guard mutation stops landing
    detection: IN-SURFACE and FREE — on_err's `[ "$rc" -eq 0 ] && exit 0` is the line the sed
               removes, so a landed mutant that ran exits 1 and a non-landed one exits 0.
               rc == 0 with the marker present IS the signature (D1d(ii)): no separate
               landed-check, no assertion, no floor move.
    alert_route: a hard fail naming a non-landed mutation
  - mode: apt starves inside the S1 driver
    detection: IN-SURFACE, per statement. A distinct literal per statement on the driver's
               stderr, landing in $TMP/s1out/stdout and carried into S1_NOTE's tail; the
               preserved rc keeps _s1_classify on did-not-run.
    alert_route: a loud declared decline naming the cause, plus the run's Skipped: count and
                 NOTE. RECURRENCE IS COUNTED, not manual: SKIP_MARKERS in
                 scripts/followthroughs/t5-skip-persistence-bound-7510.sh (now carrying
                 "SKIP (loud): T17 ") is polled by
                 .github/workflows/scheduled-rehearsal-skip-monitor.yml, which does not close on
                 a first PASS. LIMITATION, recorded rather than claimed away: a declined run is
                 GREEN, so run-registered-suites.sh prints PASS and dumps no excerpt (its own
                 header says the skip "is NOT visible through this runner"); on the CI path the
                 suite is a DIRECT step, so the whole step log carries the literal.
  - mode: the T17 marker is reworded on one side only
    detection: D5's structural pin over "$0". Without it the arm declines on EVERY run — a
               silent, permanent GREEN, strictly worse than the pre-change state.
    alert_route: a hard fail from the pin
  - mode: a future edit restores an AND-OR apt pair, or drops a container's rc capture
    detection: D7's in-suite census over "$0", with an anti-vacuity floor on its own grep.
               R1's answer here was a COMMENT plus a plan-time probe that never runs
               post-merge; that is not detection.
    alert_route: a hard fail from the census
  - mode: a set INJECT token greens a required gate
    detection: D8's refusal under CI=true, reporting directly (echo >&2; exit 1), never through
               fail() — ADR-193: a floor routed through the suspect cannot witness it.
    alert_route: exit 1 before any arm runs

logs:
  where: GitHub Actions run logs for infra-validation.yml
  retention: 90 days (GitHub default)

discoverability_test:
  command: grep -c T17M_APT_OK apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh
  expected_output: 3
```

**The probe and its honest limits.** It counts a token **this PR owns**: `T17M_APT_OK` is **0** on
`origin/main` and everywhere else in the repo, and **2** on the tree as built (the variable plus
the recipe's `echo`); D5's pin adds the third occurrence, hence `3`. `/work` MUST re-measure and
re-pin the scalar on the final tree (**AC26**) — the value is the design's arithmetic, not a
carried number.

It is a **proxy**: a source-text count proves the marker and its pin *exist*, never that the signal
*reaches the operator*. The delivery half rests on AC10/AC11's induced-starve rows alone, and this
plan says so rather than crediting the probe with it. The non-proxy alternative — a docker-free
harness driving the whole verdict ladder over the hypothesis table — was **considered and declined**
on registration cost; see the Cut List, and a reviewer may overrule.

Two runtime constraints, both measured against `plugins/soleur/skills/preflight/` rather than read:

- **No literal `|` anywhere in the command.** Check 10 rejects `$(`, backtick, `<(`, `>(`, `;`,
  `&&`, `||`, `|`, `>`, `<`, `&`, newline and `${`, so a regex alternation such as
  `(update|install)` trips a reject aimed at pipe chaining. Hence no alternation here — and hence
  a `&&`-census probe is not expressible either.
- The first token is `grep`, on `PROBE_VERB_ALLOWLIST`; verified accepted by
  `plugins/soleur/skills/preflight/scripts/probe-verb-gate.sh`. No credentials, no `ssh`, no
  docker, so it is deterministic in the sandbox. It is deliberately not `bash …test.sh`: without
  docker that script's `_skip` exits 0 in a non-CI sandbox, which would make the probe vacuous.

*(R1 asserted the scalar must be **unquoted** because `parse-form-a.awk` returns the inline value
verbatim. **That was wrong and is deleted.** Measured: `parse-form-a.awk` parses only `command:`;
`expected_output` is read by a separate `awk` in Step 10.4, never reaches `bash -c`, and Step 10.5
states outright that the tokenizer accepts both `200` and `"200"`. The quoting clause was the
mechanism for a quoted **command**, not a quoted expected value.)*

**Sharp Edge — a probe must count a token the PR OWNS.** R1's probe was
`grep -cE -e '^[^#]*apt-get update' -e '^[^#]*apt-get install'` expecting `"7"`. Correct at
`910f237f0`; **15** three weeks later, because PR #7507 added eight named apt strings to the R4
driver. R1 then replaced it with `grep -c FIXTURE-APT:` expecting `"8"` — a token the tree never
adopted, so it returns **0**. Two consecutive revisions shipped a probe that fails on a correct
tree, the second one inside the Sharp Edge written to prevent the first. Preflight Check 10
*executes* this command, so a rotted probe is a ship-time red.

## Verification
The brief's constraints, encoded so they cannot be satisfied by a green that was never obtained.

**1. A green is not evidence unless docker actually ran.** `_skip` exits **0** off-CI
(`if [ "${CI:-}" = "true" ]; then … exit 1; fi; echo "$1" >&2; exit 0`), and the file's first two
preconditions are `command -v docker` and `docker info`. Measured on this box: a bare run prints
`git-data-runcmd-rehearsal: SKIP — docker daemon unreachable` and exits **0**; the same run with
`CI=true` exits **1**. Worse, `apps/web-platform/infra/run-registered-suites.sh` captures each
suite's output and prints `PASS`, so **that runner reports PASS for a docker-less skip** — its own
header says the skip *"is NOT visible through this runner … ~50-65 s of coverage, silently absent"*.
Neither is evidence.

**2. Docker is UNAVAILABLE on this box (measured 2026-09-17).** `/var/run/docker.sock` is
`srw-rw---- root:docker`; `getent group docker` returns `docker:x:966:` — **the group is empty**;
`docker info` fails; `sudo` needs a password; no `podman`, no rootless daemon. The operator has
been asked to fix it.

**3. Two acceptable evidence sources, and every AC must disclose which — plus a `Skipped:` clause.**

| Source | What counts | Tag |
|---|---|---|
| Local | a run in which `docker info` succeeded first, with the terminal `git-data-runcmd-rehearsal: N passed, M failed, Skipped: S (T assertions)` line quoted verbatim | `[local docker]` |
| CI | the "Rehearse the git-data runcmd chain (abort ordering + rc guard)" step, with run id and conclusion. **Authoritative**, because `infra-validation.yml`'s separate `docker info >/dev/null` step is ordered before it | `[CI run <id>]` |

**The `Skipped:` clause, and it closes a third false green.** A decline is green *by design*: an
apt or image-pull starve routes T5-mutation, S1, the three S2 arms **and now T17** to `arm_skip`,
the suite prints its terminal line, and the step **passes**. So `[CI run <id>]` is obtainable from a
run in which **every new code path declined** — the tag records provenance, not execution.
Therefore: the quoted terminal line must show **`Skipped: 0`**, or the run log must be asserted
free of `SKIP (loud): T17 ` / `S1 ` / `T5 `. An AC claimed from a declined run is UNVERIFIED.

**4. Never report a green that was not obtained.** If neither source is available for an AC at ship
time, mark it **UNVERIFIED** and do not mark the PR ready
(`wg-block-pr-ready-on-undeferred-operator-steps`). Do not substitute a docker-less exit 0, a
`run-registered-suites.sh` `PASS`, or reasoning.

**5. The mutation matrices need a real daemon — and must NOT be unblocked with a workflow input.**
Each Guard 1 row is one container run, made executable by D1e's tokens rather than by editing the
file under test (the R4 driver's own rationale: *"A row that can only be executed by editing the
heredoc is a row that does not get executed"*). Guard 2's rows poison apt inside the driver instead,
because an injection arm that `exit`s directly **never enters the `||` handler** whose rc-preservation
row 3 mutates — so a token-only design cannot exercise its own handler.

**The fallback R1 proposed — "a CI run with the token set, which needs a temporary
`workflow_dispatch` input" — is withdrawn.** Measured: `infra-validation.yml`'s `workflow_dispatch:`
has **no inputs** and the rehearsal step has no step-level `env:`, so the variable is not injectable
from any workflow surface today. A free-form string input on a required gate would make **D8's
switch operator-reachable with no ack and no audit**, and per D8 one value of it returns green. If
such an input is ever genuinely needed it must be a `type: choice` enum of the known tokens, never a
free-form `string` — and D8 must land first. **NG12.**

If docker stays unavailable, AC10/AC11/AC12/AC13/AC21 are **UNVERIFIED** and the PR is not ready.

**6. Contention: prefer the single-file invocations.** Many sibling worktrees run this same docker
suite. Default to `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` and
`bash apps/web-platform/infra/git-data-render-strip-parity.test.sh` (measured green here,
`15 passed, 0 failed`). If the battery is needed and `TEST_GROUP=all` stalls, shard:
`TEST_GROUP=infra` is the only group whose `want_infra` reaches `run-registered-suites.sh`, and
`TEST_GROUP=scripts SCRIPTS_SHARD=<n>/<m>` covers the scripts side (`SCRIPTS_SHARD` is **rejected**
unless `TEST_GROUP=scripts`). Valid groups: `all, webplat, bun, scripts, infra`; anything else
exits 2. Phase 1 already took the CI route for the same reason — at load 11.6 with three sibling
sessions, one *local* apt cycle exceeded 19 minutes.

**7. First action for `/work`: resolve the uncommitted tree.** `tasks.md` 2.0.2 halts when the
census has moved, and it has. Decide explicitly whether the uncommitted implementation is the
baseline (R2's assumption) or is to be discarded, and record the decision before editing.

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
| A bind failure is announced as a genuine vacuity finding — the #7535 defect class, one hypothesis over | D1d(i) adds the `FIXTURE:` rung above the vacuity branch, mirroring T5's ladder; Guard 1 row 3 **demonstrates** the flip rather than asserting the design is safe |
| A non-landed `sed` is announced as vacuity | D1d(ii), free from `rc == 0`; Guard 1 row 4 |
| The T17 marker is reworded on one side and every run declines green, forever | D5's structural pin over `"$0"`; Guard 1 row 5 |
| One env var greens a required gate over an arm that ran nothing | D8's CI refusal, reporting directly not through `fail()`; Guard 1 row 8; and NG12 forecloses the `workflow_dispatch` surface |
| D2 routes a starved apt to `harness-defect`, producing 11 spurious hard FAILs | D2b preserves the measured rc; D2c forbids `exit 2`; D2d extends to placement; Guard 2 rows 3 and 5 demonstrate the failing directions |
| An apt killed by SIGKILL/SIGTERM yields 137/143, outside `'100 125'`, and lands on `harness-defect` -> 11 FAILs | **Accepted residual, declared not fixed.** It cannot be absorbed by widening: the file asserts the allowlist's own SIZE (`rung 0 — THE ALLOWLIST'S SIZE`, `-eq 2`) and records that `'1 2 100 125 126 127 137'` was measured and rejected. Frequency is low but not zero — the 19-minute local apt cycle at load 11.6 is the shape of that risk, not evidence against it. Recorded here so the next reader does not rediscover it as a defect |
| The named literal is pushed out of `S1_NOTE`'s `tail -3` window | The driver exits immediately after the echo, so the echo is the last line — **assert that**, do not assume it. Two starved statements cannot co-occur: the first exits |
| An apostrophe added inside the `bash -c '…'` recipe breaks the whole file | Conventions states the constraint with the measured `bash -n` rc 2; `/work` runs `bash -n` on the file after every recipe edit |
| The T17 rc capture is clobbered | The `; _t17m_rc=$?` assignment stays on the same line (the file's own stated reason); the `run_case` next-line exception is recorded so it is not "fixed" |
| The marker's evidence file is writable by the driver under test | D1b moves the sink to `$TMP/t17m.stdout`, outside `-v "$TMP/out:/out"` — which also avoids reusing `run_case`'s `$TMP/out/stdout`, where the healthy T17 arm's own `DRIVER_REACHED_DL` sits one arm above |
| The floor is incremented by arithmetic, or the frozen baseline is edited | AC18 requires a measured terminal line and a zero-diff on the baseline comment; no literal raise target appears anywhere in this plan |
| The roster/ceiling drift apart | AC17 asserts five-way consistency; D9 records the pre-existing census blindness so it is not inherited silently |
| Verification is claimed from a docker-less green, or from a declined CI run | `## Verification` items 1-4, including the `Skipped:` clause |
| The discoverability probe fails at ship on a correct tree | AC26 re-measures; the Sharp Edge records both prior rots and the rule that a probe must count a token the PR owns |
| ADR-188 keeps instructing a reader to build the cut image | D4 (five items) plus **D6**, which retires the instruction from its two *executable* carriers; AC22 and AC23 |

## Non-Goals
- **NG1** — A pre-baked fixture image, in any form, published or local. Cut on measured evidence.
  D4 records the cut **and** the `[ ! -d /run/sshd ]` guard any revival would owe; D6 retires the
  superseded "owed" instruction.
- **NG2** — `FIXTURE_IMG` / `FIXTURE_PACKAGES` chokepoints, and Guards 1-3 of the earlier revision.
  Cut with the image. (Not to be confused with `## Guard Contract` Guards 1-2 here, which are
  contracts over arms that already exist.)
- **NG3** — Publishing to GHCR or zot.
- **NG4** — `--network none` at any site. Starves are induced by poisoning apt's sources inside the
  driver instead.
- **NG5** — Digest-pinning `ubuntu:24.04` beyond the pin already in `UBUNTU_BASE` (#7544).
- **NG6** — Changing the floor's comparison operator from `-lt` to `-ne`. The file records the
  rejection and its two grounds; do not reopen it here.
- **NG7** — Adding retry/backoff outside the R4 site #7507 owns.
- **NG8** — Re-splitting or re-wording the `run_case` and T5-mutation sites (#7510's work), adding
  cause-level naming to `run_case`'s verdict, or "fixing" `run_case`'s next-line `local rc=$?`.
- ~~**NG9** — Reclassifying the T17 starvation to an `arm_skip`.~~ **WITHDRAWN at R2.** ADR-188
  makes the declared decline the correct verdict for a precondition nobody owns; T17-mutation's
  sibling T5-mutation already declines on the identical condition. R1's argument was about scope,
  not correctness — and it was unenforceable anyway, because the roster census that was supposed to
  detect the reclassification is blind to `case`-arm call sites (D9).
- **NG10** — Modelling Docker Hub in C4 (pre-existing, unchanged).
- **NG11** — Any other suite in `infra-validation.yml`.
- **NG12** — A `workflow_dispatch` input for `GIT_DATA_REHEARSAL_INJECT`. Per D8 one value of that
  variable returns green on a required gate; a free-form string input would make the switch
  operator-reachable with no ack and no audit. If ever genuinely needed: a `type: choice` enum of
  the known tokens, and D8 lands first.
- **NG13** — Fixing D9 (the skip-roster census blindness and the under-itemised ceiling). Recorded
  and filed, not fixed here — it needs its own mutation matrix.
- **NG14** — A new docker-free verdict-ladder harness suite. Considered and declined on registration
  cost; D7 detects P8 in-suite instead. See the Cut List.

## Architecture Decision (ADR/C4)
**One ADR amendment, no new ADR, no C4 change.** R1 said "No ADR, no C4 change"; the first half was
wrong.

### ADR

**Amend ADR-188** (`knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`)
— **D4, five items.** Amend-in-place rather than a new ordinal is the right call: the ADR's
`## Decision` is untouched (only an Alternative's status, a residual's instruction, an enumeration
and a roster move), and the file already establishes dated in-place amendment as its convention
(`## Amendment — 2026-08-20 (#7572)`, *"All four are recorded here rather than edited above"*). No
ordinal is claimed, so no `origin/*` collision probe is owed; if a later revision does claim one,
re-derive it against freshly-fetched refs immediately before merge and sweep this plan, the spec
and the tasks for the old number in the same edit.

Note what the amendment does **not** do: ADR-188's decision that an apt starvation is an
environment decline is **reinforced**, not reversed. R2 extends that decision to the T17-mutation
arm — which is why R1's NG9 is withdrawn — and Guard 2 row 3 demonstrates what reversing it would
cost (11 hard FAILs). The only invariant in tension, *"at least one container-dependent arm must
remain non-declinable"*, still holds on T5-primary, T17-healthy and R4; it is the ADR's
**enumeration** that goes stale, and D4 item 3 corrects it explicitly rather than leaving a reader
to infer a break.

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
