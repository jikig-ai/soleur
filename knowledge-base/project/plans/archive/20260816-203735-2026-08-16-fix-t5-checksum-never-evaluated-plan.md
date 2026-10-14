---
title: "fix(infra): T5 must prove the CHECKSUM aborted the chain, not merely that something did"
date: 2026-08-16
slug: fix-t5-checksum-never-evaluated
branch: feat-one-shot-7565-t5-checksum-never-evaluated
issue: 7565
closes: 7565
type: bug
lane: cross-domain
domain: engineering
priority: p1-high
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-08-16
**Panel:** Step 4.5 scoped advisor consult (fable) + `dhh-rails-reviewer`, `kieran-rails-reviewer`,
`code-simplicity-reviewer`, `architecture-strategist`. Research: `repo-research-analyst`,
`learnings-researcher`.

### Key improvements from the deepen pass

1. **The plan's central design was falsified and cut.** A probe the panel demanded — `main`'s exact
   `;`-chained instrumentation, CDN blocked, apt healthy — showed the mutation arm **passes**, so
   #7291's flake is apt, not the CDN. The `DL_CURL_OK` marker, the `arm_skip`/`SKIPPED_ASSERTIONS`
   /ceiling apparatus, the `run_case` split, a new ADR, and the supersession of PR 7510 all
   dissolved. Roughly two-thirds of the plan went with them.
2. **Four reviewers converged independently on the same cut**, from four different directions:
   over-engineering (DHH), per-mechanism requirement mapping (code-simplicity), doctrinal conflict
   with ADR-181 property 4 (architecture-strategist), and measurement (the advisor's "cut Phase 2
   unless a decline cell shows a different rc").
3. **Placement constraints that would have broken the suite were found before implementation.**
   `$TMP/dl.case.sh` does not exist at the instrumentation site, and T17 mounts a marker-free copy —
   so an unconditional mounted-artifact check inside `run_case` hard-exits the suite on T17. The
   check is pinned to the mutation arm instead.
4. **Two enumerations offered as exhaustive were wrong and are corrected**: `$CAPTURE` has six
   readers, not three; the file runs eight `docker run --rm`, not the four its own comment claims
   nor the six PR 7510 corrects it to.
5. **Acceptance criteria were re-scoped so each command answers its own question**: AC1's grep
   (a bare `grep -c 'echo CHMOD_RAN'` is non-zero after a *correct* fix), AC11's `lint-guard-contract`
   path pin (a bare invocation sweeps every plan and is flippable by a concurrent session), AC10's
   `git diff --stat` scoping, and AC13's shard scoping.

### Verifications executed in this pass

| Check | Result |
|---|---|
| Halt 4.6 — User-Brand Impact | Initially **FAILED**: threshold `none` with a sensitive-path match (`apps/[^/]+/infra/`) and no literal scope-out bullet. Bullet added; now passes |
| Halt 4.7 — Observability | Passes. All 5 fields present, none an empty key, probe verb `bash` is on the Check 10 allowlist, no `ssh` |
| Halt 4.8 — PAT-shaped variables | Clean, no matches |
| Halt 4.11 — Guard Contract | `lint-guard-contract.py` green: 2 guard entries, both with structural (chokepoint-based) assemblies |
| Halts 4.9 / 4.10 / 4.55 | Do not fire — no UI surface, no persistent store or new cross-component connection, no downtime-inducing operation |
| Halt 4.5 — network outage | Keyword `unreachable` matches, but the plan proposes no network or SSH fix and diagnoses no outage; the L3→L7 ordering has nothing to order. Recorded rather than skipped silently |
| Cited AGENTS rule IDs | All 4 verified ACTIVE in `AGENTS.md` and absent from `scripts/retired-rule-ids.txt` |
| Commit attribution `933635603` | Verified an ancestor of `origin/main`; its subject matches the claim quoted from it verbatim |
| Cited issues/PRs #7565 / #7291 / #7510 | State verified live via `gh` |
| String literals across plan + `tasks.md` | Checked at plan time against a floor of `47`. **Superseded at review**: the floor is now `48` (the mutation arm gained a precondition assertion), and the sweep scope was understated — the literal also appears in `tasks.md`, so the stated "6 places" was 7 |
| **The AC pattern executed against real captured output** | `grep -q '/tmp/doppler\.tar\.gz: FAILED$'` MATCHES the genuine-mismatch cell and does NOT match either the missing-file cell (`FAILED open or read`) or the curl-failure cell — the discrimination the whole fix rests on |
| Locale sensitivity of the verdict token | Probed under unset `LANG`, `LC_ALL=C` and `LC_ALL=fr_FR.UTF-8`; not translated in the pinned image |

### New considerations discovered

- A curl rc of **22** (the pinned release asset deleted or retagged) is a definitive, actionable
  defect in the artifact production boots from — never an environment decline. Harmless under this
  design because no decline path exists; recorded on #7291 so a future decline does not
  reintroduce it.
- The C4 model has the release-CDN **element** but no `gitDataStore -> github` **edge**, so the
  host's boot-time dependency on GitHub Releases is unmodelled. Pre-existing; flagged so it is not
  misread as covered.
- A pre-existing `set -u` hazard (D1 reads `$CAPTURE` before any `run_case` defines it) gets a
  tracking issue rather than a silent fix (`wg-when-an-audit-identifies-pre-existing`).

## Overview

The T5 arms of `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` are the rehearsal's
supply-chain guard. They exist to prove one thing: a wrong `DOPPLER_SHA256` aborts the doppler
install chain before `tar xzf` and `chmod +x /usr/local/bin/doppler` run as root on an unverified
tarball. Both arms report green with the checksum never evaluated.

The primary arm asserts rc==1, `"stage":"doppler_dl"`, `"level":"fatal"`, and the absence of
`CHMOD_RAN`. Every one of those four is satisfied by the *download* failing: `curl` exits non-zero,
`set -e` aborts into `on_err`, and `on_err` emits exactly those markers and exits 1. Nothing in the
arm names which command aborted, so it never distinguishes "the checksum rejected the tarball" from
"the tarball never arrived".

The mutation arm exists to prove `CHMOD_RAN` is reachable, so its absence above is evidence of an
abort rather than evidence that nothing prints it. Its instrumentation is semicolon-chained, so the
emitted line is `chmod +x /usr/local/bin/doppler; echo CHMOD_RAN`. The mutant strips `set -e`, so
execution continues past a failed curl, sha256sum, tar and chmod, and the marker prints regardless.

**The fix is two edits, one new assertion, and a floor bump.** Measurement established that the
deciding evidence is already on a stream the harness captures — `sha256sum` writes its verdict to
**stdout**, not to the redirected stderr — so the checksum-specific assertion needs no
instrumentation at all. The issue's premise that evidence "must be ADDED" is falsified, and with it
the case for a new marker.

The shipped `cloud-init-git-data.yml` runcmd is **not** modified. Instrumentation is applied by the
harness to the *extracted copy* of the block at test time, exactly as `CHMOD_RAN` is today.

No spec exists at `knowledge-base/project/specs/feat-one-shot-7565-t5-checksum-never-evaluated/spec.md`,
so there is no `lane:` to carry forward — defaulted to `cross-domain` (TR2 fail-closed). The Domain
Review below finds only Engineering relevant, on the substance of the change.

### What this plan used to say, and why it changed

An earlier revision proposed a `DL_CURL_OK` download marker, an `arm_skip` / `SKIPPED_ASSERTIONS`
counted-decline apparatus with a ceiling, a new ADR-191, and the supersession of open draft PR 7510
together with closing issue #7291. The Step 4.5 advisor consult and the review panel converged on a
single falsifiable claim underneath all of it, and **the measurement came back against the plan**
(probe (e) below). The apparatus was defending a failure mode that has never occurred in this suite.
It is cut in full; see `## Alternative Approaches Considered`. The diagnosis survived; the remedy did
not.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Probe | Verdict |
|---|---|---|
| Issue #7565 open, not already fixed | `gh issue view 7565 --json state,closedByPullRequestsReferences` | OPEN, `closedByPullRequestsReferences: []`. HOLDS. Labels `priority/p1-high`, `type/bug`, `domain/engineering`, `code-review` |
| Issue #7291 still open | `gh issue view 7291 --json state` | OPEN. HOLDS |
| PR 7510 is an open draft editing the same file | `gh pr view 7510 --json state,isDraft,mergedAt,files` | OPEN, `isDraft: true`, `mergedAt: null`, updated 2026-08-13. Edits this file (+232/-21), adds `ADR-188`. **Not on `origin/main`** |
| The primary arm's four assertions are all satisfiable by a download failure | Container probe (c) | HOLDS. CDN blocked ⇒ `on_err` fires with `rc=6`, driver exits 1, emit carries stage+level, `CHMOD_RAN` absent — all four assertions satisfied |
| The `;`-chained `CHMOD_RAN` prints regardless of chmod | Probe P5c and container probe (e) | HOLDS |
| "The evidence must be ADDED, not merely read — sha256sum's stderr goes to `$GIT_DATA_RUNCMD_DETAIL`" | Probes P1a/P1b in `ubuntu:24.04` | **FALSIFIED for the checksum half.** `2>>` takes only fd 2; the verdict line `/tmp/doppler.tar.gz: FAILED` goes to **stdout**, which `run_case` already captures via `>"$TMP/out/stdout" 2>&1`. Only the WARNING summary is on stderr |
| "fix the `;`-chained instrumentation — use `&&`, not `;`" | Probes P2 / P5 | **HOLDS, with a caveat that changes nothing here.** Measured: under `set -e`, `false && echo X; echo AFTER` prints `AFTER` and exits 0 — errexit does not fire on a failing non-final member of an AND-OR list. On the *chmod* line no arm can observe that difference (see below), so bare `&&` is correct |
| **"landing #7565 on top of PR 7510 re-opens #7291"** — this plan's own earlier claim | Falsification probe (e) | **FALSIFIED.** This is the finding that reshaped the plan |

### The falsification that reshaped the plan

Issue #7291's stated mechanism is: *"When the download is slow or fails, the chain aborts earlier —
at curl, not at the checksum — so `CHMOD_RAN` never prints."* An earlier revision inherited that
causal story and built a CDN-decline apparatus on it.

**Probe (e) — `main`'s exact instrumentation (`;`-chained), CDN blocked, apt healthy, mutant:**

```
/tmp/doppler.tar.gz: FAILED open or read
tar (child): /tmp/doppler.tar.gz: Cannot open: No such file or directory
chmod: cannot access '/usr/local/bin/doppler': No such file or directory
CHMOD_RAN                <-- printed anyway
==> main's mutation arm PASSES
```

A blocked CDN makes `main`'s mutation arm **pass**, not fail. It therefore **cannot** produce
#7291's observed failure (`T5 MUTATION: without set -e the chain still did not reach chmod`,
4 pass / 2 fail over 6 runs).

**Probes (f) and (g) — what actually suppresses `CHMOD_RAN`:**

| apt sub-case | Mechanism | Container stdout | docker rc |
|---|---|---|---|
| `apt-get install` fails | Outer `set -e` fires on the AND-list's **final** member ⇒ `drive.sh` never runs | **0 bytes** — no `FIXTURE:`, no markers, nothing | 100 |
| `apt-get update` fails | AND-list exemption ⇒ falls through to `drive.sh` ⇒ no python3 ⇒ capture server never binds | `FIXTURE: capture server never bound :8099` | 2 |

#7291 is an **apt** flake, not a CDN flake. Three consequences, each reversing an earlier conclusion
in PR 7510's favour:

1. **`DRIVER_REACHED_DL` is the right key for #7291, not the wrong one.** When apt-install fails the
   container emits *zero bytes*, so marker absence is the only signal that exists. PR 7510 got this
   right, and the earlier revision's thesis that "an absence key is a design defect" is wrong for
   precisely this failure mode.
2. **The merge-order entanglement dissolves.** `&&`-conditioning `CHMOD_RAN` does not disturb
   7510's apt-keyed skip. The two PRs may land in either order.
3. **The apt-statement split belongs to 7510, not here** — and doing it *without* 7510's skip
   machinery is a measured regression: the split converts the update sub-case from "`FIXTURE:`
   printed" to "0 bytes", destroying the only signal that sub-case has. It is correct in 7510
   because 7510's verdict reads the absence; it is wrong on its own.

### Measured probe matrix (the evidence base for the surviving fix)

Run in the real `ubuntu:24.04` image the harness uses, against a faithful copy of the extracted
block. "CDN blocked" repoints the release host to an unresolvable name, reproducing the reported
condition — release CDN unreachable while apt works.

| Case | checksum verdict on stdout | `CHMOD_RAN` (after fix) | driver rc |
|---|---|---|---|
| (a) CDN reachable + `set -e` | `/tmp/doppler.tar.gz: FAILED` | absent | 1 |
| (b) CDN reachable + no `set -e` (mutant) | `/tmp/doppler.tar.gz: FAILED` | **present** | 0 |
| (c) CDN blocked + `set -e` | absent | absent | 1 (`on_err rc=6`) |
| (d) CDN blocked + no `set -e` (mutant) | `FAILED open or read` | absent | 1 |

Three facts this pins:

1. **(a) vs (c) is the discrimination #7565 asks for.** Today both cells produce an identical
   verdict. With the `$`-anchored checksum-verdict assertion, (a) passes and (c) **fails with a
   true, specific message** — the checksum was never evaluated.
2. **`: FAILED` must be `$`-anchored.** Case (d) emits `/tmp/doppler.tar.gz: FAILED open or read`.
   An unanchored `: FAILED` matches it, which would make the new assertion satisfiable by a
   *download* failure — this bug re-created in a new disguise.

   > **Falsified on execution (2026-08-16) — see `mutation-transcript.md` G1-2/G1-2a/G1-2b and
   > `decision-challenges.md` §1.** Case (d) is the *mutant* path (`no set -e`); the assertion
   > lives on the errexit-armed primary arm, where a blocked CDN aborts at `curl` **before**
   > `sha256sum` runs, so no verdict line is emitted at all and the over-match cell is
   > unreachable as the suite ships. Reaching it required appending `|| true` to curl. The
   > anchor is retained and is now a whole-line `grep -qxF`, but as defence-in-depth against a
   > future edit — not a guard on a live path. Left in place rather than rewritten: the
   > falsified prediction is evidence.
3. **(b) vs (d) is the mutation arm's discrimination.** On `main` (probe e) both cells print
   `CHMOD_RAN`; after `&&`-conditioning only (b) does.

Supporting probes: `set -e; false && echo M; echo AFTER` → `AFTER`, exit 0. `set -e; false; echo M`
→ exit 1. `sha256sum --version`: GNU coreutils 9.4 in-container, uutils 0.8.0 on this workstation —
both split the same two lines across the same two streams.

**Locale sensitivity — raised at review, probed, not reproduced.** A reviewer flagged that coreutils
localises messages via NLS, so `: FAILED$` could be a hidden English-locale assumption. Measured in
`ubuntu:24.04`: `LANG` unset, `LC_ALL=C`, and `LC_ALL=fr_FR.UTF-8` (after `locale-gen`) all emit
`/tmp/f.bin: FAILED`. The `-c` verdict token is not translated in the image the harness pins.
Recorded as a residual rather than pre-emptively hardened: if it ever matters, `LC_ALL=C` on the
container `bash -c` is the one-token fix, and that line is deliberately left untouched here so PR
7510 rebases cleanly.

### Why a bare `&&` is sufficient on the chmod line

The errexit AND-list exemption is real, but on the chmod line no arm in this suite can observe the
difference between `chmod … && echo CHMOD_RAN` and a heavier errexit-preserving tail, because no arm
can reach a *failing* chmod under `set -e`:

- **Primary arm** — the checksum aborts first; chmod is unreachable by construction. That is the
  property under test.
- **Mutation arm** — `set -e` is already stripped, so errexit preservation is moot.
- **T17** — the block is replaced with `printf 'true\n'` (`:711-713`); there is no chmod at all.

A `cmd && echo M || { … }` tail additionally misfires when the *echo* fails (EPIPE, full disk),
attributing `echo`'s status to `cmd`. Bare `&&` it is. The AND-list fact still earns a code comment,
because the next reader will otherwise reach for the tail.

### Repo facts

- **The file**: `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`, 1760 lines on `main`.
  T5 primary `:658-672`, T5 mutation `:674-704`, instrumentation `:451-467`, `run_case` `:616-637`,
  driver heredoc `:505-554`, `total=$((passes + fails))` `:1702`, floor `if [ "$total" -lt 46 ]`
  `:1752`, verdict `exit $(( fails > 0 ))` `:1760`. Options: `set -uo pipefail` (`:20`).
- **The shipped block**: `apps/web-platform/infra/cloud-init-git-data.yml:493-504`. Both `curl` and
  `sha256sum -c -` carry `2>>"$GIT_DATA_RUNCMD_DETAIL"`; `tar` and `chmod` do not.
- **Extraction**: a python heredoc selects the single `runcmd` string containing `sha256sum -c -`
  under `assert len(blocks) == 1` (`:160-163`), writes `$TMP/doppler-dl.sh`, guarded by `[ -s … ]`
  at `:236`.
- **`$TMP/dl.case.sh` lifetime**: created *inside* `run_case` at `:620`, and separately by the
  mutation arm at `:687`. It does **not** exist at the instrumentation site — and T17 overwrites
  `$TMP/doppler-dl.sh` with `printf 'true\n'` at `:713` before its `run_case` call, so T17's mounted
  copy legitimately carries no marker at all. An unconditional mounted-artifact check inside
  `run_case` would therefore hard-exit the suite on T17.
- **`$CAPTURE` readers** — six, not three: `:652` (D1), `:666`, `:667`, `:668` (T5 primary), `:715`,
  `:716` (T17). First assigned at `:635` inside `run_case`, whose first call is `:665`, so D1's read
  at `:652` is of an *unset* variable under `set -u`, reachable only in D1's failing direction
  (`dash` rc == 2). Pre-existing; see Phase 3 for its disposition.
- **Per-case isolation**: both `run_case` (`:619`) and the mutation arm (`:679`) do
  `rm -rf "$TMP/out"; mkdir -p "$TMP/out"` before each `docker run`, and stdout is `>`-truncated. A
  marker from one container cannot satisfy the next container's grep.
- **CI**: `.github/workflows/infra-validation.yml`, job `deploy-script-tests`, runner
  `ubuntu-24.04`, registered at `:1241` as a single-line `run: bash <path>` step. Docker and network
  egress available. Workflow path filter includes `apps/*/infra/**`. The suite also runs roughly
  every six hours via `main-health-monitor` (`TEST_GROUP=infra`).
- **Structural guard**: `.github/scripts/test/test-infra-suite-registration.sh` requires every
  tracked `apps/web-platform/infra/*.test.sh` to be registered in that job in exactly that
  single-line shape. No new suite file is added, so registration is unchanged.
- **Lint gates** (dispatched from `scripts/test-all.sh:705-707, 753-754`):
  `lint-shell-capture-exit.py --baseline …` — the baseline already carries **7** entries for this
  file, so a new S1/S2 finding reds it; and `lint-guard-contract.py`, which **sweeps every
  non-archived plan** when given no positional path (`find_plan_files`, `sweep = not args.paths`),
  so any AC invoking it must pin this plan's path.
- **`C4_PRODUCER_PATHS`** (`scripts/lib/test-relevance-paths.sh:174`) does not include
  `apps/web-platform/infra`, so the C4 producer suite is untouched by this diff.
- **Stale hand-maintained counts here**: an in-file comment says "four plain `docker run --rm`";
  PR 7510 corrects it to six; `grep -c` on `main` returns **8**.

### Applicable institutional learnings and decisions

| Source | What it binds here |
|---|---|
| `knowledge-base/project/learnings/2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md` | Names this exact file (B1). A guard whose expected set comes from the artifact under test is a tautology — the shape of `grep -q CHMOD_RAN` matching its own source text |
| `knowledge-base/project/learnings/2026-08-05-i-built-a-cadence-on-a-bot-that-never-ran-and-my-battery-certified-the-gate.md` | "A mutation battery scores the gate's INPUTS. It cannot see the gate's own dispatch layer." Drives harness row H1 |
| `knowledge-base/project/learnings/best-practices/2026-07-03-pass-is-not-proof-three-vacuous-green-traps-in-infra-verification.md` | "Does the signal the gate queries actually get written to the sink the gate reads?" — the question that found sha256sum's verdict on stdout |
| `knowledge-base/project/learnings/2026-08-04-my-guard-certified-a-string-in-a-file-not-the-render-that-boots.md` | Extraction pins what an expression *is*, never that it is *applied* — drives the mounted-artifact check and its T17 exemption |
| `knowledge-base/project/learnings/2026-08-09-the-shell-capture-trap-recurred-three-times-and-finally-earned-a-lint.md` | ADR-166 and the origin of `lint-shell-capture-exit.py`, whose baseline must not grow |
| `knowledge-base/project/learnings/2026-08-13-the-guards-i-wrote-to-prove-the-fixes-had-the-defects-the-fixes-were-about.md` | Records that running `lint-shell-capture-exit` **without** `--baseline` and reading exit 1 as a regression is itself a logged mistake |
| `knowledge-base/project/learnings/2026-04-06-doppler-cli-checksum-cloud-init.md` | The original trust-boundary rationale for the pinned version + checksum this arm defends |
| `knowledge-base/engineering/architecture/decisions/ADR-181-local-gate-declines-are-counted-verdicts.md` | Property 4: **"A decline is UNREACHABLE under CI, not merely detected."** Consistent with this plan's central cut (supporting, not dispositive: ADR-181's scope is suite-dispatch declines in `scripts/test-all.sh` and explicitly does NOT extend to CI or to an in-suite, assertion-level decline; the measurement is what carries the cut) — introducing a CI-reachable decline into this suite would have widened ADR-181's carve-out from one mutant container to the supply-chain guard itself |
| `knowledge-base/engineering/architecture/decisions/ADR-180-guard-contract-as-plan-time-deliverable.md` | Requires the Guard Contract below, and its "assembly is structural, not a member snapshot" rule shapes both entries |
| `knowledge-base/engineering/architecture/decisions/ADR-166-a-ci-message-may-only-name-a-cause-the-job-measured.md` | The new failure message names what the arm measured (sha256sum did not reject) and does not claim a cause it did not measure |

### Property List (Phase 0.6b)

1. The primary arm must not report a pass unless the **checksum** is what aborted the chain.
2. The mutation arm's `CHMOD_RAN` must be emitted only when `chmod` actually ran and succeeded.
3. The instrumentation must land on the artifact the container actually mounts, not merely on the
   source copy — without breaking T17, whose mounted copy legitimately carries no marker.
4. Instrumentation must not alter the errexit semantics the arm exists to measure.
5. The suite must remain unable to satisfy its assertion floor by short-circuiting.

### Cut List (Phase 0.6b, extended after review)

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| Read `$GIT_DATA_RUNCMD_DETAIL` back out of the container | 1 | Already bought. sha256sum's verdict is on **stdout**, already captured (measured) |
| A `DL_CURL_OK` download marker | 1 | Dominated. `/tmp/doppler.tar.gz: FAILED$` is a strictly stronger positive signal at a *later* point in the same chain — it proves curl succeeded, sha256sum ran, **and** sha256sum rejected. `DL_CURL_OK` proves only the first |
| A `DL_CURL_FAILED_RC` marker as a decline key | "a CDN-blocked run must not report a failure either" | Cut with the apparatus below. It would also have mis-declined a **deleted or retagged pinned asset** (curl rc 22 — the server answered and refused), which is a definitive, actionable defect in the artifact production actually boots from, not an environment decline |
| `arm_skip` / `SKIPPED_ASSERTIONS` / `_SKIP_CEILING` / a re-derived floor | that same property | **Cut — the property is not one this issue asks for, and the failure mode is unobserved.** Probe (e) measured that a CDN block makes `main`'s mutation arm *pass*; #7291's real cause is apt. The apparatus defended a cell that has never occurred, at the cost of a counter, a per-call-site cost declaration, a ceiling set to its own maximum reachable value, and a ceiling-guarding-the-floor. ADR-181 property 4 independently disfavours it |
| Splitting `run_case` into `run_case_capture` + `run_case` | letting the primary arm retract an already-counted rc assertion | Cut with the apparatus above — it existed only to serve `arm_skip`. Also removes any need to disturb the pre-existing `set -u` hazard at `:652` |
| An errexit-preserving `\|\| { rc=$?; …; ( exit $rc ); }` tail on the chmod line | 4 | Cut. No arm can observe the difference on that line, and the tail misfires when `echo` fails |
| A `CHMOD_FAILED_RC` marker | — | Cut. No verdict branch would read it |
| Splitting `apt-get update && apt-get install` at the T5 container sites | "an apt failure must not be misread" | **Cut, and measured harmful in isolation** (probes f/g). Correct only alongside 7510's absence-keyed skip |
| Adopting the in-file `fixture_fail()` + bounded-apt + `INJECT` machinery (`:1213-1255`) at the T5 sites | apt classification | Cut — #7291/#7535 scope; #7501 already applied it where it belongs |
| A new ADR | — | Cut. With the decline apparatus gone this plan makes no architectural decision. The one durable insight (the errexit AND-list exemption) is a code comment |
| Superseding PR 7510 / `Closes #7291` | — | Cut. The entanglement was an artifact of the falsified CDN story |

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Issue: "the evidence must be ADDED, not merely read" | sha256sum's verdict is on stdout, already captured | Assertion added with **zero** instrumentation |
| Issue: "emit a `CURL_OK` marker … and require it in T5's primary arm" | Dominated by the checksum verdict; its only other use was the cut decline key | Not implemented; recorded in the Cut List with the measurement |
| Issue: "use `&&`, not `;`" | Correct for this line; the errexit caveat does not bite here | Implemented as bare `&&` |
| Brief: "do not regress PR 7510's skip machinery" | Not on `main`; this change does not touch it | Honoured by *not* re-implementing it. Probes (e)/(f)/(g) are contributed back to #7291 as evidence its key and its apt split are correct |
| Earlier revision: "#7565 and #7291 cannot land independently" | Falsified by probe (e) | Retracted. Either order works |
| Earlier revision: `$CAPTURE` has three readers | Six: `:652, :666, :667, :668, :715, :716` | Corrected. An enumeration offered as exhaustive that misses a member is the very class this plan fixes |
| Earlier revision: the release CDN "is already covered by `github = system "GitHub"`" | True of the **element**, false of the **relationship** — there is no `gitDataStore -> github` edge, so the host's boot-time dependency on GitHub Releases is unmodelled | Wording corrected below. Pre-existing gap, not created by this diff, so "no C4 impact" still stands |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — a CI test harness with no
user-facing surface. The indirect exposure is the point: a green supply-chain guard that proved
nothing lets a regression reach `cloud-init-git-data.yml` in which a tampered doppler tarball is
`tar`'d and `chmod +x`'d as root on the git-data host, which holds the user's repository data.

**If this leaks, the user's data/workflow/money is exposed via:** no new exposure vector. No
credential, no network destination, no persisted artifact is added.

**Brand-survival threshold:** `none`.

- `threshold: none, reason: the diff is confined to a CI test harness's assertion logic and adds no
  credential, network destination, persisted artifact, or runtime code path — the guard it repairs
  defends a host that is declared-but-unprovisioned, so no live user data sits behind this change.`

**Scope-out note.** `apps/web-platform/infra/` is inside the preflight Check 6 sensitive-path regex
(`apps/[^/]+/infra/`), which is why the explicit scope-out bullet above is required rather than
optional. It is a path-shaped match, not a substance-shaped one: the diff touches a `.test.sh` in
that directory and no `.tf`, no cloud-init, no secret, and no provisioning surface.

*Why `none` is nonetheless right for a security-adjacent change:* the diff touches no sensitive
surface under the same regex's substance — no schema, migration, auth flow, API route, `.sql`, or credential
handling. The host the guard defends is declared-but-unprovisioned (`model.c4`: `claude ->
gitDataStore`, "TARGET state — the store is declared but unprovisioned, #6977/ADR-149"), so no live
user data currently sits behind it. The threshold measures *this diff's* blast radius, not the
importance of the property it guards.

## Architecture Decision (ADR/C4)

**No ADR, and no C4 change.** Recorded with the reason rather than omitted.

**The ADR gate does not fire.** With the decline apparatus cut, this plan makes no ownership,
substrate, resolver, trust-boundary or dispatch decision, and reverses no existing ADR. It is a bug
fix on an existing surface: one instrumentation character-class change, one assertion, one floor
bump. The durable, counter-intuitive fact discovered here — bash does not fire errexit on a failing
**non-final** member of an AND-OR list — is a code comment above the transform, and belongs in a
`/compound` learning at ship time rather than the decision corpus.

Recorded for the next planner: an earlier revision proposed `ADR-191` ("a guard declines on its own
precondition, not an upstream execution marker"). The generalisable half of that principle is real
and is worth writing **when a decline is actually built** — *arrival is not satisfaction*: a
control-flow arrival marker licenses no claim that a precondition was satisfied. It is the
verdict-side twin of ADR-166, which constrains what a message may *name*. It is not written here
because this plan builds no decline, and because the concrete instance chosen to illustrate it was
falsified by probe (e) — an absence key is exactly right when the failing container emits zero
bytes. That principle belongs to #7291, where a decline does exist.

**No C4 impact,** against an enumeration actually performed and independently re-run at review:
`spec.c4` (54 lines) and `views.c4` (74 lines) read in full; `model.c4` (691 lines) read for every
`actor`/`system`/`container`/`database` declaration and every relationship naming this feature's
nouns.

- **External human actors: exactly 4** — `founder` (`:8`), `emailSender` (`:14`), `betaContact`
  (`:22`), `contributor` (`:35`). None gains or loses an edge.
- **External systems: 20**, plus the external database `connectedRepoKb`. The only candidate is the
  release CDN, `https://github.com/DopplerHQ/cli/releases/download/…`. The **element** exists —
  `github = system "GitHub"` (`model.c4:234`), described as "Source control, CI/CD, issue tracking,
  and releases". The **relationship** does not: there is no `gitDataStore -> github` edge, so the
  git-data host's boot-time dependency on GitHub Releases is unmodelled. That is a pre-existing gap
  which this diff neither creates nor widens — the shipped runcmd already carries the dependency and
  is untouched — so "no C4 impact" stands for this change. Flagged so a future author does not read
  the element's presence as evidence the edge exists.
- **`gitDataStore` (`model.c4:218`) has exactly 4 edges** — `hetzner ->` (`:550`), `-> sentry`
  (`:627`), `-> betterstack` (`:630`), `claude ->` (`:654`). None changes.
- No access relationship changes, and no element description is falsified. There is no modelled
  element for a CI test harness at any level.

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200`
(64 open), filtered with `jq --arg path 'apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh'`.

- **#7565** — this issue. **Fold in** (`Closes #7565`).
- **#7291** *(no `code-review` label; found by title search)* — "flaky: git-data-runcmd-rehearsal T5
  mutation arm depends on a real network download". **Acknowledge, do not fold in.** An earlier
  revision proposed closing it here; probe (e) falsified the entanglement. Its real cause is apt,
  its remedy is PR 7510's absence-keyed skip plus bounded apt, and both are correct as drafted. This
  PR contributes probes (e)/(f)/(g) back to it and deliberately leaves the apt lines untouched so
  7510 rebases cleanly. Two interactions to record on #7291: (i) after this PR, `&&`-conditioned
  `CHMOD_RAN` means a CDN-blocked run reaches 7510's `else` branch and reds — a cell that has never
  been observed, and one 7510 may route to `arm_skip` if it ever is; (ii) if 7510 ever keys a
  decline on a curl outcome, connectivity rcs (6/7/28/35/56) and rc 22 must be split — rc 22 means
  the server answered and refused, i.e. the pinned asset is gone, which is a defect in the artifact
  production boots from, not an environment decline.
- **#7535** — "stop the rehearsal's apt failures reading as emitter findings", `deferred-scope-out`,
  `contested-design`. **Acknowledge.** Weighs pre-baking an image vs `--network none` vs in-place apt
  retry. Probe (c) is evidence that T5 specifically cannot move to `--network none` without changing
  what it rehearses. No edit required here.
- **#7544** — "make e2fsprogs drift a named failure in the git-data rehearsal". **Acknowledge.** Same
  file, different arm (R1), no line overlap.

## Implementation Phases

### Phase 0 — preconditions (no edits)

1. Confirm the worktree is on `feat-one-shot-7565-t5-checksum-never-evaluated`, rebased on a freshly
   fetched `origin/main`.
2. Capture a **baseline measured run**: `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`,
   recording the terminal `git-data-runcmd-rehearsal: N passed, M failed (T assertions)` line. The
   floor below is derived from measurement, never from arithmetic on a comment.
3. Confirm `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
   exits 0 **before** any edit. Run it *with* `--baseline`; a bare invocation exits 1 by design.

### Phase 1 — condition the `CHMOD_RAN` marker on chmod actually running

In the python transform at `:457-465`, change `old + "; echo CHMOD_RAN"` to
`old + " && echo CHMOD_RAN"`. The existing `s.count(old) != 1` cardinality assert is retained
unchanged — it is what makes a shipped block that gains a second `chmod` hard-exit rather than
instrument the wrong one.

Replace the post-transform check at `:466` (`grep -q 'echo CHMOD_RAN'`, which matches its own source
text) with a **line-anchored** check over the whole emitted construct
`chmod +x /usr/local/bin/doppler && echo CHMOD_RAN`, so prose naming the marker cannot satisfy it
(`cq-assert-anchor-not-bare-token`).

Add the same anchored check against the artifact the container actually **mounts**. Placement is
constrained and must be respected: `$TMP/dl.case.sh` does not exist at the instrumentation site, and
T17 overwrites `$TMP/doppler-dl.sh` with `printf 'true\n'` at `:713`, so its mounted copy carries no
marker and an unconditional check inside `run_case` would hard-exit the suite on T17. Put the
mounted-artifact check in the **mutation arm**, immediately after its own `cp … "$TMP/dl.case.sh"` +
`sed -i` pair at `:687-688`, where the file provably exists and provably should carry the marker.
Name T17's exemption in the adjacent comment.

### Phase 2 — assert the checksum's own verdict in the primary arm

Keep the `run_case "T5 wrong-checksum aborts" … 1` call at `:665` unchanged, and keep `run_case`
itself unmodified. After the existing `stage` and `level` assertions and before the
`CHMOD_RAN`-absent assertion, add one counted assertion on the captured container stdout:

```
if grep -q '/tmp/doppler\.tar\.gz: FAILED$' "$TMP/out/stdout"; then pass; else
  fail "T5: sha256sum never rejected the tarball — the abort was not the checksum" \
       "$(tail -3 "$TMP/out/stdout")"; fi
```

The `$` anchor is load-bearing: without it `FAILED open or read` satisfies the assertion, which
re-creates this bug in a new disguise. The `.` is escaped so it is not a BRE metacharacter. The
message names only what the arm measured — that sha256sum did not reject — and does not claim a
cause (ADR-166).

This is what makes the CDN-blocked cell honest: it now **fails** with a true, specific message
instead of passing silently. That is a deliberate policy choice — see `## Risks & Mitigations`.

All greps use `if grep -q … ; then` form. No `var=$(grep -c …)` capture, so
`lint-shell-capture-exit.py` gains no new finding and its baseline does not grow.

### Phase 3 — floor, comments, pre-existing-hazard issue, measurement

- Raise the floor from 46 to **48**: the primary arm goes from 4 assertions to 5, and (added at review) the mutation arm gains a precondition assertion that its wrong-digest `sed` actually landed. Itemise the raise
  in-file in the existing style, and correct the stale "four plain `docker run --rm`" comment to the
  measured count in the same edit.
- Update the instrumentation comment block at `:451-456` to state why the marker is `&&`-chained and
  to record the errexit AND-list exemption, so the next reader does not reach for a heavier tail.
- Update the T5 primary comment at `:658-664`: its claim that "the checksum is the ONLY thing that
  can stop the chain" holds only when the environment is healthy, and the new assertion is what
  makes the arm say so.
- **File a tracking issue** for the pre-existing `set -u` / unset-`CAPTURE` hazard at `:652`
  (`wg-when-an-audit-identifies-pre-existing`). Do not fix it here — it is unrelated to this bug and
  touching `run_case` is explicitly out of scope.
- Run the suite end to end, set the floor to the measured `total`, then execute the mutation matrix
  and record each verdict.

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` | Phases 1-3. The only code file |
| `knowledge-base/project/specs/feat-one-shot-7565-t5-checksum-never-evaluated/tasks.md` | Task breakdown |

## Files to Create

None.

## Files Deliberately NOT Edited

| Path | Why |
|---|---|
| `apps/web-platform/infra/cloud-init-git-data.yml` | The shipped runcmd is correct and unchanged. Instrumentation is applied to the extracted copy at test time. No infra change ⇒ no IaC gate, no encryption-posture gate, no host redeploy |
| `run_case` (`:616-637`) | Pinned unmodified by AC6. Its rc assertion is correct in every measured cell, and leaving it alone avoids disturbing six `CAPTURE` readers and the pre-existing `set -u` hazard at `:652` |
| The two T5 `apt-get update && apt-get install` lines (`:631`, `:698`) | Measured harmful in isolation (probes f/g): splitting them destroys the `FIXTURE:` signal in the update sub-case. Correct only alongside PR 7510's absence-keyed skip |
| `.github/workflows/infra-validation.yml` | The suite is already registered at `:1241` in the required single-line shape; no new suite file is added |
| `scripts/lint-shell-capture-exit.baseline.txt` | Growing a debt baseline to accommodate new code is the wrong direction; Phase 2 uses grep forms that produce no new finding |

## Guard Contract

Two arms, two properties, two assemblies — so two entries. `lint-guard-contract.py` would pass on
one, which is precisely the shape ADR-180 warns against.

### Guard 1 — T5 primary: the checksum, and only the checksum, aborted the chain

**Property.** When the release CDN is reachable and `DOPPLER_SHA256` is wrong, the doppler install
chain aborts at `sha256sum -c -` — evidenced by that command's own rejection verdict — and neither
`tar xzf` nor `chmod +x /usr/local/bin/doppler` runs. When the checksum is *not* what aborted the
chain, the arm says so rather than reporting a pass.

**Assembly.** The chokepoint is the single `runcmd` entry containing `sha256sum -c -`, selected from
the rendered cloud-init at `:160-163` under `assert len(blocks) == 1`. Every command the property
quantifies over — `curl`, `sha256sum`, `tar`, `chmod`, `rm` — is inside that one block by
construction, so the block is the assembly and not a snapshot of its five current members: a sixth
command added to the shipped block arrives here automatically. The evidence surfaces are exactly
two: `$TMP/out/stdout` (container stdout+stderr, per-case truncated at `:619`) and
`$TMP/out/capture.log` (the emit payload). The verdict is dispatched by `run_case` at `:665` plus
the four assertions at `:666-672`.

**Mutation matrix.** Every row states its input condition explicitly.

| # | Edit (and input condition) | Must go |
|---|---|---|
| 1 | Delete the new checksum-verdict assertion entirely (targets the guard's **own dispatch**); CDN reachable | RED via the floor — `total` drops against the floor (46 vs 47 as measured; the floor is 48 after review added the mutation arm's precondition assertion). A removed assertion must not be indistinguishable from an arm that ran |
| 2 | **FALSIFIED ON EXECUTION — came back RED; replaced by rows G1-2a/G1-2b, see `mutation-transcript.md`.** Delete the `$` anchor from the pattern (`: FAILED` for `: FAILED$`); **CDN blocked, apt healthy** | Predicted GREEN, and that was to be the finding — `FAILED open or read` satisfies a checksum-specific assertion, i.e. bug #1 in a new disguise. The row is recorded as a must-be-RED only in its corrected form; the uncorrected form's greenness is the evidence the anchor is load-bearing |
| 3 | Leave both fixes in place; **CDN blocked, apt healthy** | RED — primary arm fails with "sha256sum never rejected the tarball". On `origin/main` the identical input is **green with zero findings**: the false pass this PR closes |
| 4 | Point `DOPPLER_SHA256` at the *correct* checksum so the chain completes; CDN reachable | RED — `CHMOD_RAN` appears and the existing absence assertion fires. Confirms the arm still detects a chain that runs to completion |
| 5 | Add a **second** `chmod +x /usr/local/bin/doppler` line to the shipped block after a compliant first (targets the **second-member** case); CDN reachable | RED — `s.count(old) != 1` hard-exits rather than instrumenting one and silently ignoring the other |

### Guard 2 — T5 mutation: `CHMOD_RAN` is emitted only when chmod actually ran

**Property.** The `CHMOD_RAN` marker appears if and only if `chmod +x /usr/local/bin/doppler`
executed and succeeded, so the marker's *absence* in Guard 1 is evidence of an abort rather than
evidence that nothing ever prints it.

**Assembly.** A different assembly from Guard 1 and that is why it is a separate entry: the mutant
driver `$TMP/drive.noerrexit.sh` (produced by the `sed 's/^set -e$/true/'` at `:683`, guarded by the
`diff -q` non-landing check at `:684`), the mutation arm's own `$TMP/dl.case.sh` (`:687-688`), and
its own inline `docker run` at `:689-700` — *not* `run_case`. The instrumentation site is the single
`chmod +x /usr/local/bin/doppler` occurrence in the extracted block, pinned by `s.count(old) != 1`.

**Mutation matrix.**

| # | Edit (and input condition) | Must go |
|---|---|---|
| 1 | Revert the transform to `; echo CHMOD_RAN` (any network) | RED — the Phase 1 line-anchored post-transform check does not match the emitted construct and hard-exits 1. *Note the detector*: behaviourally, `;` and `&&` are indistinguishable when the CDN is reachable (chmod succeeds either way), and under a blocked CDN the `;` form makes this arm **pass**. The anchored check is what catches it, not the arm's own verdict |
| 2 | Keep the `&&` in the transform but revert the post-transform check to a bare `grep -q 'echo CHMOD_RAN'`, then delete the `&&` clause (targets the guard's **own dispatch**) | RED must be the outcome; on `main` this same pair is GREEN, because a bare grep matches its own source text |
| 3 | Rename the emitted marker in the transform but not in either check | Predicted RED twice, independently. **Measured: only the source-level check fires** — it `exit 1`s before the mutation arm is reached, so the two are not observed independently in one run. The mounted check's independence is demonstrated by row 2 instead, where the source-level check was deliberately defeated and the mounted check was the sole detector. |
| 4 | Delete the mounted-artifact check and corrupt `$TMP/dl.case.sh` after the `sed -i` at `:688` | RED must be the outcome — the check is what pins application, not merely presence in the source copy |
| 5 | Leave both fixes in place; **CDN blocked, apt healthy** | RED — `CHMOD_RAN` absent. Documented as an accepted new red path (see Risks); on `main` this input is green |

**Harness rows** (mutations of the SUITE, not of the system under test):

| # | Edit | Must go |
|---|---|---|
| H1 | Neuter `pass()` and `fail()` to no-ops | RED — `total` falls to 0 and the floor fires. Without this row a suite reporting `0 passed, 0 failed` would exit 0 |
| H2 | Leave the floor at 46 after adding the new assertion | GREEN, and that is the finding — it demonstrates that a floor only ever guards work predating it, which is why Phase 3 raises it with the arm that made it necessary |
| H3 | **Must-PASS, non-canonical input:** a healthy run in which `apt-get install` fails once and succeeds on retry — slow but ultimately correct | GREEN. A slow-but-successful run must pass |
| H4 | **Must-PASS, non-canonical input:** the shipped block reordered so `rm /tmp/doppler.tar.gz` precedes `chmod`; CDN reachable | GREEN — the contract is that the checksum aborts before `tar`/`chmod`, not that the block's tail is in a fixed order |

## Observability

```yaml
liveness_signal:
  what: >
    The suite's terminal line — `git-data-runcmd-rehearsal: N passed, M failed (T assertions)` —
    and its exit status.
  cadence: >
    Every push to a branch touching `apps/*/infra/**`, via the `deploy-script-tests` job in
    `.github/workflows/infra-validation.yml` (registered at line 1241); plus roughly every six
    hours via `main-health-monitor` with `TEST_GROUP=infra`.
  alert_target: >
    The GitHub Actions job conclusion for `deploy-script-tests` — which is an **advisory** job,
    not a merge gate: it is absent from `ruleset-ci-required.tf`, so a red check is visible but
    mergeable-past, and on a pull request there is no notification at all. Ops email fires only
    on push-to-main, via `notify-main-failure`. Promotion to required is tracked in #6480.
    Stated here because a supply-chain guard whose alert route is advisory should not be
    presented as if it blocked.
  configured_in: .github/workflows/infra-validation.yml

error_reporting:
  destination: >
    GitHub Actions job log and job conclusion. This suite runs only in CI and on a workstation; it
    has no Sentry or Better Stack path and deliberately acquires none — it is a build-time gate, not
    a runtime surface (observability layer: CI, not the product runtime).
  fail_loud: >
    Yes. Every failing arm prints `FAIL: <reason>` to stderr with a detail line, and the verdict is
    an explicit `exit $(( fails > 0 ))` rather than a trailing test expression. This plan
    deliberately introduces no skip or decline path, so there is no verdict that is green-but-silent
    (ADR-181 property 4).

failure_modes:
  - mode: The chain continues past a failed checksum (the pre-#6982 supply-chain defect returning).
    detection: '`CHMOD_RAN` present in the primary arm''s captured stdout.'
    alert_route: '`fail` -> non-zero suite exit -> `deploy-script-tests` red.'
  - mode: The checksum was never evaluated, because something aborted the chain earlier.
    detection: >
      `/tmp/doppler.tar.gz: FAILED` absent from the primary arm's captured stdout, `$`-anchored so a
      `FAILED open or read` from a missing tarball cannot satisfy it.
    alert_route: >
      `fail`, naming only what was measured ("the abort was not the checksum") plus the last three
      lines of container output as detail.
  - mode: The `CHMOD_RAN` marker is unreachable, making the primary arm's absence check vacuous.
    detection: 'Mutation arm — `CHMOD_RAN` absent with `set -e` stripped.'
    alert_route: '`fail` -> non-zero suite exit.'
  - mode: The instrumentation silently fails to land on the mounted artifact.
    detection: >
      A line-anchored check for the whole emitted construct against `$TMP/dl.case.sh` in the
      mutation arm, run before that container starts.
    alert_route: Uncounted hard `exit 1` with a named reason.
  - mode: An arm vanishes silently via a short-circuited branch or a deleted assertion.
    detection: '`total = passes + fails` measured against the floor of 48.'
    alert_route: '`FAIL: ran only N assertions (<48)` -> exit 1.'
  - mode: An arm vanishes via an early `exit 0` (a skip guard firing).
    detection: >
      NOT the floor — an early `exit 0` returns before the floor check is reached, so the floor
      is structurally blind to it. `CI=true` is the detection: it converts every `_skip` guard
      into `exit 1` with a named reason. The floor comment in the script carried the same false
      clause and is corrected in the same commit.
    alert_route: 'Named `_skip` reason -> exit 1 under CI.'

logs:
  where: >
    GitHub Actions job logs for `deploy-script-tests`; locally, the suite's own stdout/stderr.
    Per-case container output lives at `$TMP/out/stdout` for the duration of the run.
  retention: GitHub Actions default log retention for the repository.

discoverability_test:
  # THE OPERATOR'S COMMAND, and why preflight Check 10 does not execute it.
  #
  # Bare `bash <suite>` is the wrong probe: without CI set, the four `_skip` guards
  # exit 0 before a single assertion, so on any host without a docker daemon it reports
  # success having verified nothing — this plan's own thesis, reproduced in its only
  # executable proof. Prefixing `CI=true` fixes that and breaks two other things: it
  # leads with an env-assignment rather than an allowlisted probe verb, and the suite
  # then legitimately FAILS anywhere docker is absent.
  #
  # Neither form is runnable inside Check 10's sandbox, which has no docker socket and a
  # 15s wall-clock cap against a ~3min, 8-container probe. So this declares the
  # requirement instead of pretending to a verification it cannot perform.
  command: CI=true bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh
  # ONE LINE, deliberately. Check 10's reader is a flat awk over the key line, so a
  # folded (`>-`) or block (`|`) scalar extracts as the bare indicator and is then
  # treated as ABSENT — the probe would execute and fail the verb gate. Verified.
  credentials_required: a docker daemon plus ~3 minutes of wall clock — the probe runs 8 ubuntu:24.04 containers that download the genuine Doppler tarball from the GitHub release CDN and assert the checksum aborts the chain before tar/chmod. Check 10's bwrap sandbox binds no docker socket and caps at 15s, so executing it there would fail for want of the daemon and prove nothing about the guard. There is no unauthenticated, sandbox-runnable substitute: the property under test IS the container-level abort ordering, and the CI job that does run it is `deploy-script-tests` in infra-validation.yml.
  expected_output: >
    A terminal line `git-data-runcmd-rehearsal: <N> passed, 0 failed (<N> assertions)` with `<N>` at
    or above 48, and exit status 0.
```

No `credentials_required`: the suite needs docker and outbound network, both already provided by the
runner, and no credential of any kind.

### Soak follow-through enrollment

Not applicable. No acceptance criterion is time-gated; every criterion is decidable on the first run
after merge.

## Acceptance Criteria

### Pre-merge (PR)

1. The `;`-chained form is gone:
   `grep -Fc -- '"; echo CHMOD_RAN"' apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`
   returns 0, and `grep -Fc -- '" && echo CHMOD_RAN"'` returns 1. (A bare `grep -c 'echo CHMOD_RAN'`
   must not be used — it is non-zero after a *correct* fix, so it answers a different question from
   the one this criterion asks.)
2. The post-transform check is line-anchored on the whole construct
   `chmod +x /usr/local/bin/doppler && echo CHMOD_RAN`, not on a bare token.
3. The same anchored construct is asserted against the **mounted** artifact `$TMP/dl.case.sh` in the
   mutation arm, after its `cp`/`sed -i` pair at `:687-688`. T17's exemption (its mounted copy is
   `printf 'true\n'` and carries no marker) is named in the adjacent comment.
4. The primary arm carries a counted assertion on `/tmp/doppler\.tar\.gz: FAILED$` against
   `$TMP/out/stdout`, with the `$` anchor and the escaped `.` both present.
5. The floor equals the `total` printed by a measured healthy run (measured 48), is itemised in-file
   naming the new assertions, and the stale "four plain `docker run --rm`" comment is corrected to the
   measured count in the same edit.
6. `run_case` is unmodified: `git diff origin/main -- apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`
   shows no change between its `run_case() {` line and its closing brace.
7. No skip/decline machinery is introduced:
   `grep -Ec 'arm_skip|SKIPPED_ASSERTIONS|_SKIP_CEILING' apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`
   returns 0, and `total=$((passes + fails))` is unchanged.
8. A full healthy run passes: `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` prints
   `… 0 failed …` and exits 0.
9. Every mutation-matrix row of Guard 1 (1-5) and Guard 2 (1-5), plus harness rows H1-H4, has been
   executed against a scratch copy, and the **row-by-row transcript** — the edit applied, the
   observed terminal line, and the exit status — is pasted into the PR body. Rows are never left
   applied to the committed file.
10. `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
    exits 0, and `git diff --stat origin/main -- scripts/lint-shell-capture-exit.baseline.txt` is
    empty.
11. `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-08-16-fix-t5-checksum-never-evaluated-plan.md`
    exits 0. (The path is pinned: a bare invocation sweeps every non-archived plan and would be
    flipped by an unrelated concurrent session.)
12. `bash .github/scripts/test/test-infra-suite-registration.sh` exits 0.
13. The shards the diff touches are green — at minimum
    `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` plus the two lint suites above.
    A full `bash scripts/test-all.sh` is run for information; a pre-existing unrelated failure is
    dispositioned per `wg-when-tests-fail-and-are-confirmed-pre` rather than attributed to this diff.
14. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0.
15. A tracking issue exists for the pre-existing `set -u` / unset-`CAPTURE` hazard at `:652`, and its
    number is referenced in the code comment left at that site.
16. The PR body carries `Closes #7565` and **not** `Closes #7291`, and records probes (e)/(f)/(g) as
    evidence contributed to #7291.

### Post-merge

17. The first `deploy-script-tests` run on `main` after merge is green, and its log shows the printed
    assertion total at or above the floor.
18. A comment is added to #7291 carrying probes (e)/(f)/(g), the note that `&&`-conditioned
    `CHMOD_RAN` makes a CDN-blocked run reach PR 7510's `else` branch, and the rc-22-is-not-a-decline
    caveat.

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed
**Assessment:** A CI-only change to one test harness: one instrumentation character-class change,
one new assertion, one floor bump, three comment corrections, and one tracking issue for a
pre-existing hazard. No product surface, no runtime code, no infrastructure, no schema, no
credential, no vendor, no new file. The engineering risk was concentrated in shell semantics under
`errexit`, and that risk was retired by measurement before the plan was written — including one probe
that falsified the plan's own central design and collapsed it by roughly two-thirds. Residual risks
are the hand-maintained floor number (mitigated by deriving it from a measured run) and the
deliberate policy choice to let a CDN-blocked run fail rather than decline (argued in Risks, and
independently supported by ADR-181 property 4).

**Product/UX Gate:** not applicable. The mechanical UI-surface scan over `## Files to Edit` and
`## Files to Create` matches no UI-surface path — the change set is one `.test.sh` and one
`tasks.md`. Product is not relevant and the override does not fire.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **A CDN-blocked run now fails where it previously passed** — a new red path in both arms | **Accepted deliberately.** The failure is true and specific, and for a supply-chain guard a false red is cheap (re-run) while a silent vacuous pass is the defect being fixed. It is also cheap to accept: measured, this cell has **never** been observed — #7291's flake was apt (probes e/f/g). ADR-181 property 4 ("a decline is UNREACHABLE under CI") independently favours failing over declining here. If a CDN decline is ever *observed*, the counted-decline machinery proposed in draft PR 7510 (ADR-188, **unmerged** — it exists only on that branch) is the candidate remedy and #7291 is where it lands — reached by evidence rather than anticipation |
| A deleted or retagged pinned release asset would disarm the guard | Cannot happen under this design: with no decline path, curl rc 22 (server answered and refused) fails the arm exactly like any other non-checksum abort. This was a live hazard in the cut decline design and is recorded on #7291 so a future decline does not reintroduce it |
| The floor number is wrong at merge | Phase 3 derives it from a measured run; AC5 requires the floor to equal the printed `total`. The in-file "four plain `docker run`" comment — wrong at 6 on PR 7510 and at 8 on `main` — is standing evidence that hand-maintained counts here drift |
| The mounted-artifact check hard-exits the suite on T17 | Placement is constrained by AC3 to the mutation arm, after its own `cp`/`sed -i`, where the file exists and must carry the marker. T17 overwrites `$TMP/doppler-dl.sh` with `printf 'true\n'` at `:713`, so its mounted copy legitimately has no marker; the exemption is named in the comment |
| Growing `lint-shell-capture-exit.baseline.txt` | AC10 requires it byte-unchanged against `origin/main`. Phase 2 mandates `if grep -q …` and forbids `var=$(grep -c …)` |
| Conflict with PR 7510 on rebase | Confined to the T5 arms' verdict lines and the instrumentation block. This PR deliberately does not touch the apt lines, the driver heredoc, `run_case`, or the floor's accounting shape, so 7510 rebases with a small, local conflict |
| Touching `run_case` disturbs a `CAPTURE` consumer | Avoided entirely — AC6 pins it unmodified. Enumerated for the record: two call sites (`:665`, `:714`) and six `CAPTURE` readers (`:652`, `:666`, `:667`, `:668`, `:715`, `:716`). The pre-existing `set -u` hazard at `:652` gets a tracking issue (AC15), not a fix |
| The `&&` form changes errexit behaviour on the chmod line | Measured non-observable: no arm can reach a *failing* chmod under `set -e` (primary — unreachable by construction; mutation — errexit stripped; T17 — no chmod). Recorded in the plan and in the code comment |
| `: FAILED$` is locale-dependent | Probed and not reproduced: `LANG` unset, `LC_ALL=C` and `LC_ALL=fr_FR.UTF-8` all emit the same token in `ubuntu:24.04`. Recorded as a residual with `LC_ALL=C` as the one-token hardening if it ever bites |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Add a `DL_CURL_OK` download marker and require it in the primary arm, per the issue's suggestion | Dominated by the `$`-anchored checksum verdict, which is a strictly stronger positive signal later in the same chain — it proves curl succeeded, sha256sum ran, and sha256sum rejected. `DL_CURL_OK` proves only the first |
| A counted-decline apparatus (`arm_skip`, `SKIPPED_ASSERTIONS`, a ceiling, a re-derived floor, a `run_case` split), so a CDN-blocked run declines rather than fails | **Built and then cut on measurement.** Probe (e) showed a CDN block makes `main`'s mutation arm *pass*, so the cell the apparatus defended has never occurred; #7291's real cause is apt. Roughly two-thirds of the plan, one ADR and one PR supersession dissolved with it. ADR-181 property 4 disfavours it independently |
| An errexit-preserving `\|\| { rc=$?; echo …; ( exit $rc ); }` tail on the marker lines | No arm can observe the difference on the chmod line, and the tail misfires when `echo` itself fails, attributing `echo`'s status to the command |
| Split `run_case` into `run_case_capture` + `run_case` | Existed only to let the primary arm retract an already-counted rc assertion into a skip. With the decline apparatus cut there is nothing to retract |
| Assert on the emitted `rc=` extra in `capture.log` (curl fails 6/7/28; sha256sum fails 1) | This file's own history rejects it — commit `933635603`: "rc=1 is a default errno bucket, not a blankness verdict" |
| Bind-mount `$GIT_DATA_RUNCMD_DETAIL` out and assert on sha256sum's stderr WARNING | Unnecessary: the verdict line is already on captured stdout |
| Give T5 a local fixture tarball and stop downloading | Changes what T5 rehearses. The arm's fidelity claim is that curl fetches the *genuine* tarball so the checksum is the only thing that can stop the chain. Related to #7535's `--network none` option, which probe (c) is evidence against for T5 specifically |
| Close #7291 and supersede PR 7510 in this PR | Rested entirely on the falsified CDN story. 7510's `DRIVER_REACHED_DL` key and its apt split are correct for #7291's real cause, and this PR is shaped to let it rebase cleanly |

## Non-Goals

- Changing `cloud-init-git-data.yml` or any shipped runcmd. The block under test is correct.
- Fixing #7291. Its cause is apt, its remedy is PR 7510, and this plan contributes measurement to it
  rather than absorbing it.
- Bounding or splitting apt at the T5 container sites — measured harmful without 7510's skip.
- Fixing the pre-existing `set -u` / unset-`CAPTURE` hazard at `:652`. It gets a tracking issue.
- Resolving #7535's contested design, or #7544's e2fsprogs naming.
- Introducing skip/decline semantics to this suite. If a genuine environment decline is ever observed
  here, the design proposed in draft PR 7510 (ADR-188, unmerged) is the candidate and #7291 is where it lands.
