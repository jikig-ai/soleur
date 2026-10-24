# Architecture Review — PR #10953 (closes #10921)

Reviewer: `soleur:engineering:review:architecture-strategist`
Scope: `git diff origin/main...HEAD` on `feat-one-shot-10921-corrupt-ancestry-flake`
Diff shape: new shared fixture lib `plugins/soleur/test/lib/git-corrupt-graph.sh` (+241),
two guard-script suites rewired to it (bump +257/−?, mint +103/−?), counted-skip
machinery, t5 monitor probe widened 1→2 run-sources with per-source accounting,
monitor workflow text generalized, plan/spec bookkeeping.

## 1. Architecture Overview

The PR replaces a flaky "delete the loose object by path" corruption fixture
with a **construction-side forgery** (never-written parent/tag objects via
`git hash-object -w` + `update-ref`), consolidated behind a single sourced lib.
It then introduces the repo's second production user of ADR-188's **counted
skip** machinery (`SKIPPED_ASSERTIONS`, `corrupt_skip`, per-suite
`SKIP_CAP`, anti-vacuity `TOTAL` fold) and extends the standing cross-run
observer (`t5-skip-persistence-bound-7510.sh` + its daily monitor workflow) to
a second run-source so the new skip producers are bounded across runs, not just
per run.

Relevant pre-existing architecture this aligns with:

- `plugins/soleur/test/lib/` is already the shared-fixture-lib location
  (`git-fixture-env.sh`, `gitleaks-probe.sh`, `operator-stub-world.sh`); the
  new file is a consistent sibling, consumed the same way (`source
  "$REPO_ROOT/plugins/soleur/test/lib/..."` + `# shellcheck source=`).
- ADR-188's ownership axis: construction invariants are harness-owned →
  fail-only/zero-counted; the walk-contract is runner-git-owned → counted skip.
  The implementation applies that axis correctly and names it at each site.
- The monitor's "un-run instrument must never read clean" invariant is
  preserved and strengthened: per-source `observed >= 1` with **no pooling**,
  and FAIL dominating TRANSIENT across sources.

## 2. Change Assessment

### 2.1 Settled rulings — all honored

- **Forged-oid over repack-aware rm**: `dead_oid`/`corrupt_walk_break`/
  `corrupt_dead_tag` write objects that never existed rather than deleting any;
  `rm`-style construction is gone from both suites (0 `rm -f.*objects/` hits in
  either file). `dead_oid` hashes a BLOB (not `-t commit`), matching the CTO
  fsck correction.
- **Only walk-contract skip-eligible**: B7a's peel failure is a
  construction-invariant `fail`, never re-routed to skip; the B7a probe shape
  is "healthy `--merged` silently drops + clean stderr" per the ruling.
- **Probe extended in this PR**: second run-source added to the standing probe
  rather than a sibling instrument — the correct call (~100 lines of
  subtly-failed-before machinery not duplicated).
- **Tier aggregate pattern**: CI-internal only; SUTs untouched.

### 2.2 Structural quality

- **Chokepoint + self-policing**: the lib is the single spelling of both the
  forgery and the skip verdict, and the bump suite carries two standing
  self-checks (object-store-deletion census over `.github/scripts/test/`,
  roster-parity of `corrupt_skip` names vs. probe-registered prefixes) plus a
  cross-file parity row in the t5 test file (every probe-enumerated prefix has
  a producer). The enforcement triangle (producer → census → observer) is
  well-formed.
- **Probe contract robustness**: the skip contract is "non-empty walk stderr" —
  the SUT's own acceptance criterion — not a specific message string, so it is
  wording- and locale-robust.
- **Test-side coverage is strong**: t5 test rows (l)–(p) cover marker→FAIL for
  both suite prefixes, unobserved→TRANSIENT (non-pooling), FAIL-dominates-
  TRANSIENT, and roster parity; banner discriminators are derived from the
  probe's own literals (anti-drift). Floor raised 22→27, itemized.
- **Monitor workflow**: titles/bodies generalized consistently, per-source
  remediation text names the arm family; streak/dedupe/seal machinery
  untouched; the `0/1/2/*` verdict contract unchanged.

### 2.3 Confirmed carrier assumptions (verified, not assumed)

- `run-all.sh:176` prints `=== $(basename "$t") ===` and invokes each suite
  directly (`bash "$t"`), so both the discriminator banners and the stderr
  `SKIP (loud):` markers reach the Actions job log unwrapped — the
  `SOLEUR| relay` carrier used by the rehearsal source is not needed here.
- `guard-script-fixture-tests` has no `if:` gate and runs on both
  `pull_request` and `merge_group` triggers — both sampled event legs carry the
  suites.
- `--event merge_group|pull_request` sampling is the right shape; the old
  `--branch main`/`conclusion==success` filter could not see this workflow.

## 3. Findings

### P1 — must fix before merge

**P1-1. Mint skip-selftest verdict is emitted then erased — fail-open.**
`.github/scripts/test/test-mint-inngest-bootstrap-tag.sh:1186–1192`

```bash
[[ "$fl_fd" == 2 && "$fl_sd" == 5 && ... ]] \
  && pass 'selftest:skip-machinery-both-directions' \
  || fail 'selftest:skip-machinery-both-directions' "..."
PASS=$fl_p0 FAIL=$fl_f0 SKIPPED_ASSERTIONS=$fl_s0
```

The `pass`/`fail` verdict for the selftest row is emitted **inside** the
snapshot window and then `PASS=$fl_p0 FAIL=$fl_f0` restores the pre-block
counters, erasing it. Two consequences:

- **Failure path is fail-open**: if the machinery check fails, `fail()` prints
  `FAIL [selftest:skip-machinery-both-directions]: ...` to the log and
  increments `FAIL` — then the restore wipes the counter and the suite exits 0.
  A broken skip mechanism ships green with a FAIL line nobody gates on —
  precisely the silent-green class this PR exists to close. Nothing downstream
  greps the log for FAIL lines; the exit code is the only contract.
- **Success path miscounts**: the printed `PASS [selftest:...]` line is not
  counted, so the `MIN_ASSERTIONS=673` derivation comment ("the skip-machinery
  selftest added one row (+1)") is inaccurate — the row contributes 0 counted
  assertions. The floor number itself is presumably green-run-measured and
  therefore self-consistent, but the accounting comment misdescribes reality.

Contrast with the bump suite, which restores only `SKIPPED_ASSERTIONS=$_sk0`
after the verdict lands (and whose `st_run` restores counters *inside* the
driver, verdicts emitted outside). Fix: emit the mint verdict **after** the
restore, or restore only `SKIPPED_ASSERTIONS` (the exercised `fail()`s inside
(a) and (c) still need PASS/FAIL unwinding — so the correct fix is the bump
shape: restore counters first, then emit the verdict on real counters).

### P2 — should fix or consciously accept

**P2-1. `SOLEUR_FIXTURE_PACKED=1` (AC4) has no standing carrier.** The packed
arm exists in `_corrupt_maybe_repack` and is marked done in `tasks.md` 5.2, but
nothing in `.github/workflows/` sets it — it is exercised only if a developer
runs the suite locally with the knob. The layout-immunity claim was measured on
git 2.56.0 and the construction is structurally layout-independent, so this is
not a coverage hole today — but the arm will bit-rot silently (no consumer
asserts it still works). Either wire a periodic/matrix arm or document the knob
as diagnostic-only in the lib header (the header already says "the packed-store
arm (AC4)" without saying who runs it).

**P2-2. Source-2 samples unmerged-branch code — intended, but the noise bound
is only issue-dedupe.** `pull_request` legs run the PR's own code: any branch
that makes a corrupt-walk row skip (or merely adds a `SKIP (loud): g1b.`
emission — including a fork) trips the monitor and files/updates the alert
issue on a *scheduled main* cadence. The comment frames this as a feature
("trips the monitor pre-merge — real evidence"), which is defensible; but be
aware the streak/dedupe machinery is the only throttle, and a long-lived
draft PR iterating on these suites will keep the alert hot. A cheap narrowing
(if ever needed): prefer merge_group legs, which carry the merged-state
result. Also note `gh run list` here has no `--status` filter: in-progress runs
whose logs are fetchable-but-partial can count as `observed` for a unit (banner
present, rows unreached → reads clean). Bounded and fail-safe-ish; flagged for
completeness.

**P2-3. Roster-parity grep matches only single-quoted call sites.**
`grep -oE "corrupt_skip[[:space:]]+'[^']+'"` in both suites. A future
`corrupt_skip "x9.Y" …` (double quotes) evades the roster check *and* produces
a monitor-invisible skip — the failure mode the check exists to catch. The
census has the same shape of best-effort literalism (delete verb + literal
`.git/objects/` on one line; `.` unescaped → over-matches, which is the safe
direction; indirection through a variable evades). Both are documented
best-effort self-checks, so this is acceptable — but a one-character
`['\"]` in the roster regex would close the cheapest evasion.

**P2-4. Source-2 FAIL headline uses `g_sampled`, hits are per-observed-log.**
"FAIL: pr-quality-guards.yml — N loud guard-suite skip(s) across M sampled run
log(s)" — the denominator is all fetched logs, while hits only accrue in logs
carrying a suite banner. The per-unit lines directly below do carry correct
observed denominators, so this is cosmetic — but it is the same
mixed-denominator class the source-1 rewrite deliberately fixed; consider
mirroring "observed (sampled)" phrasing for symmetry.

### P3 — nits / observations

- `pg_ids` conflates "gh failed" with "no runs" (both → empty → TRANSIENT
  "no merge_group/pull_request runs to sample"). Verdict class is correct; the
  reason string can mislabel an auth/outage as an empty window.
- `timeout 600` on the probe step now bounds two sources (~40 `gh run view
  --log` fetches, and pr-quality-guards is a many-job workflow). A timeout →
  rc 124 → `broken` → alert: fail-loud, acceptable, but the headroom roughly
  halved.
- Declared skip costs (8/9/8/3 → `SKIP_CAP=28`; `fl.walk=3` → cap 3) are
  manually maintained constants with the same drift risk as `MIN_ASSERTIONS`.
  The cap+floor brackets bound the blast radius; no action needed beyond what
  the comments already say.
- `corrupt_probe_forced_skip` calls `fail()` without the `declare -F` guard
  that `corrupt_skip` carries — inconsistent defensive depth within the same
  lib (both consumers define `fail`, so this is contract-internal today).
- The PASS line for source 2 references `${unit_obs[bump]}`/`${unit_obs[mint]}`
  literally; under `set -u`, renaming a `GUARD_UNITS` key unbounds the
  reference → non-0/1/2 exit → `broken` verdict → alert. Fail-loud, just
  brittle.
- `corrupt_walk_break` drops multi-parent structure (forges exactly one
  parent) — irrelevant for current fixtures; worth a comment if a merge-tip
  fixture is ever added.
- Two same-shape `rm`-construction sites outside the census scope
  (e.g. `scripts/ci-pr-selection.test.sh`) remain — explicitly deferred to
  #10956; the deferral is documented at the census site.

## 4. Compliance Check

- **Principles register**: no infra provisioning, service, data-model, or
  cross-boundary change — AP-001/AP-011 checks not triggered. No ADR gap: the
  counted-skip pattern is ADR-188's own; the forge construction is recorded in
  the plan file + decision-challenges (an ADR amendment is not warranted for
  CI-internal fixture machinery).
- **SOLID/layering**: single-responsibility honored (mechanism in lib, row
  policy in suites); the `SKIPPED_ASSERTIONS` global coupling is the
  established bash-harness idiom and is documented in CALLER CONTRACT.
- **No new circular dependencies**: lib sources nothing beyond optional
  `assert_fixture_dir` (feature-detected via `declare -F`); suites source
  lib — acyclic.
- **Interface stability**: probe exit contract 0/1/2/78 unchanged; monitor
  verdict vocabulary unchanged; `Results:` lines extended additively
  (`, N skipped`); workflow outputs contract unchanged.
- **`cq-test-fixtures-synthesized-only`** — fixtures are synthesized, yes.
- **`hr-exhaust-all-automated-options`** — self-checks (census, roster parity,
  fed-log rows) substitute for manual vigilance; consistent.

## 5. Recommendations

1. **Fix P1-1** (move the mint selftest verdict outside the restore, or restore
   `SKIPPED_ASSERTIONS` only) and re-verify the `MIN_ASSERTIONS=673` comment's
   "+1" claim matches whatever shape is chosen.
2. Decide P2-1 disposition (wire a packed arm somewhere, or document
   diagnostic-only) — one line in the lib header suffices if the latter.
3. Optionally tighten the roster regex to `['"]` (P2-3) — one character.
4. Land as-is on the monitor generalization otherwise; the per-source
   accounting is the right shape and the test rows cover the load-bearing
   branches.

**Verdict: P1 present — request changes** (single localized fix in the mint
suite; everything else is advisory). The architecture — chokepoint lib,
ownership-axis skip classification, non-pooled per-source observation — is
sound and the settled rulings are all honored.
