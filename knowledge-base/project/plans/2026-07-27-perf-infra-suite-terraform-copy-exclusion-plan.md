---
title: "perf(infra): credential-persist-home-guard holds 3.9 GB of sandbox copies in a 4 GB tmpfs"
date: 2026-07-27
type: perf
branch: feat-one-shot-infra-runner-terraform-copy-waste
lane: cross-domain
brand_survival_threshold: none
status: draft
---

# perf(infra): bound `credential-persist-home-guard`'s sandbox footprint

> **Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).** No
> `knowledge-base/project/specs/feat-one-shot-infra-runner-terraform-copy-waste/spec.md`
> exists; this plan is the first artifact for the branch.

## Overview

`apps/web-platform/infra/credential-persist-home-guard.test.sh` builds a sandbox copy of
the **real infra root** for every mutation in its anti-vacuity battery — 24 times per run
(20 `expect_red` + 4 `expect_green`). Two independent defects compound:

1. **Size** — on any machine that has run `terraform init`, `$REAL_ROOT` contains a
   gitignored **162 MB `.terraform/`** provider tree that the scanner has no use for.
2. **Lifetime** — sandboxes are allocated with `mktemp -d "$TMPROOT/…"` and **never
   removed**; the only cleanup is `trap 'rm -rf "$TMPROOT"' EXIT`. All 24 are therefore
   concurrently resident at the end of the run.

Together they peak `TMPROOT` at a **measured 3,980 MB** against a `/tmp` that is
**tmpfs, 4.0 GB total, 2.9 GB free**.

Fixing both takes ~6 lines and is **strictly better on every axis than fixing either
alone** — including wall-clock, where each fix *on its own* is worse than the combination
(and one is worse than doing nothing). See *Measurements*.

**This plan does not reduce the infra runner's 8.5-minute wall-clock.** That claim in the
task framing is falsified by measurement — see *Premise Validation*. The runner is bounded
end-to-end by a different suite, already tracked as **#6665**.

---

## Premise Validation

Every claim in the task framing was probed before any plan structure was written. Three
of five are refuted or corrected.

| # | Task claim | Verdict | Evidence |
|---|---|---|---|
| 1 | "several infra suites copy the entire `.terraform` tree" | **REFUTED — exactly one does** | Exhaustive sweep for `cp -r/-R/-a/-pr`, `rsync`, `tar\|tar`, `cpio`, `find -exec cp`, `git archive`, `shutil.copytree`, `fs.cpSync` across `apps/web-platform/infra/*.test.sh`, `tests/`, `scripts/`, `plugins/`. Only this suite copies the real root. `infra-config-gate.test.sh:181,198` copies `SYNTH="$TMP/infra"` — a synthetic `mktemp -d` fixture. |
| 2 | "~13 copies, moving ~2 GB" | **CORRECTED UPWARD — 24 copies, 3,980 MB** | 20 `expect_red` + 4 `expect_green`. Peak measured. |
| 3 | "The runner takes 8.5 min … largely because of this" | **REFUTED** | Runner measured at **8m49.96s in a worktree where `.terraform` does not exist at all**. |
| 4 | "mutations only need the `.tf` sources, not the vendored provider binaries" | **HOLDS** | `.terraform` holds zero `.tf`/`.sh`/`.service`/`.yml`/`.yaml` files (69 entries: provider binaries, LICENSEs, markdown). The scanner opens only those four extensions. |
| 5 | *(implicit)* "this costs CI time" | **REFUTED for CI** | The suites run in job `deploy-script-tests` (`infra-validation.yml:294`, suite at `:763`), which runs **no `terraform init`** — the only inits are in jobs `validate:` (`:214`) and `plan:` (`:825`). A fresh CI checkout has no `.terraform`. **Local-developer cost only.** |

### The runner's actual critical path (measured, 6-way parallel, 72 suites)

```
total wall-clock        8m49.96s        ci-deploy.test.sh          529.9s  <-- IS the runner
sum of all suites         716.4s        workspaces-luks-g4-mut.     57.5s
                                        credential-persist-guard     9.6s  <-- this plan
```

At `JOBS=6` the floor is `max(529.9, 716.4/6) = max(529.9, 119.4) = 529.9s`. **Deleting
this suite entirely would change runner wall-clock by 0 seconds.** The real lever is
already filed: **#6665** (`ci-deploy.test.sh` real-sleep cost ~407s, broaden the existing
opt-in `MOCK_SLEEP_NOOP=1` gate at `ci-deploy.test.sh:673-699`). This plan does not
re-file, duplicate, or absorb it.

### So why do the work?

Not for wall-clock, and not for CI. For the **tmpfs-exhaustion and cross-suite contention
hazard**: 3,980 MB of concurrently-resident temp against a 4.0 GB tmpfs with 2.9 GB free,
while `run-registered-suites.sh` runs **6 suites sharing that same tmpfs**. Adjacent to
#6789 (parallel-worktree `/tmp` contention, CLOSED) and #6734 (tmpfs leak, CLOSED).

---

## Measurements

All executed against a benchmark that lives **outside the repo** (`/var/tmp/credbench`),
using the suite's own documented `CRED_GUARD_INFRA_ROOT` override and a **disk-backed
`TMPDIR`** (ext4, 545 GB free) — chosen deliberately so tmpfs exhaustion could not
truncate the number being measured. That is why a 3,980 MB peak coexists with
`28 PASS / 0 FAIL` and a 2.9 GB-free `/tmp`: **the run never touched `/tmp`.** 3,980 MB is
the suite's true *demand*; `/tmp` cannot satisfy it. That is the hazard, not a contradiction.

| Variant | Wall-clock | Peak `TMPROOT` | Result |
|---|---|---|---|
| Baseline, **no** `.terraform` present | 6.7s | ~108 MB | 28 PASS / 0 FAIL |
| **BEFORE** — real root with 162 MB `.terraform` | **10.4s** | **3,980 MB** | 28 PASS / 0 FAIL |
| Fix A only — `find … -prune -o -exec cp -r {} \;` | **44.6s** ⚠️ | 108 MB | 28 PASS / 0 FAIL |
| Fix A only — single-`cp` exclusion | 8.0s | 108 MB | 28 PASS / 0 FAIL |
| Fix B only — `fresh_sbx` (delete previous sandbox) | **14.2s** ⚠️ | 166 MB | 28 PASS / 0 FAIL |
| Both + pin **inside** `expect_red` (per-mutation) | **16.5 / 16.8 / 17.9s** ⚠️ | 5 MB | 28 PASS / 0 FAIL |
| **BOTH + one-time pin (prescribed, 3 runs)** | **7.2 / 8.0 / 9.6s** | **5 MB** | **29 PASS / 0 FAIL** |

Three results here are counter-intuitive and each one falsifies an approach a reasonable
engineer would otherwise ship:

- **`find … -exec cp -r {} \;` is 4× slower than doing nothing.** `ls -A` on the infra
  root returns ~236 entries, so per-entry forking costs ~236 × 24 ≈ 5,700 spawns. The
  conclusion holds for any large entry count; the exact number is not load-bearing.
- **`fresh_sbx` alone is a wall-clock regression** (14.2s vs 10.4s): `rm -rf` of a 166 MB
  tree, 24 times, costs more than the concurrency it saves. It is a good fix that must
  not ship alone.
- **Together they beat every variant on both axes** — 7.2–9.6s (against a 10.4s baseline)
  and 5 MB (a **796× peak reduction**), because the exclusion is what makes each `rm -rf`
  cheap.
- **Correct placement of the new pin was also decided by measurement, not taste**: running
  it per-mutation costs ~9s and regresses the suite; running it once costs ~0.4s and pins
  the same property. See step 5.

Run-to-run spread on the prescribed variant is 7.2–9.6s (±17% around ~8.3s), which is
smaller than the 2.1s improvement over baseline but not by a wide margin — AC3 is therefore
written as "does not regress", not as a point estimate.

### Anti-vacuity control (measured both ways)

A no-op mutation (`m0noop() { : ; }`) injected as an extra `expect_red`:

| Diff form | Reported failure for a no-op mutation |
|---|---|
| `diff -rq --exclude=.terraform` *(prescribed)* | `mutation did not change the tree (assert_mutated failed)` — **correct attribution** |
| `diff -rq` *(exclusion omitted)* | `guard stayed GREEN on the mutated tree (VACUOUS — pins nothing)` — **misattributed** |

Both go RED, so this is a **diagnostic-attribution** regression, not a correctness hole —
stated precisely rather than inflated. Once `$sbx` lacks `.terraform`, an unexcluded diff
can never report the trees identical, so `assert_mutated` passes unconditionally and every
broken mutation is blamed on the scanner. **This is why the copy and the diff must change
in the same commit.**

### Tested and REFUTED: "a truncated copy under ENOSPC fails open"

The advisor consult raised a serious hypothesis: `cp`'s exit status is unchecked, so under
the very exhaustion this plan cites, a truncated sandbox would scan clean, the pre-mutation
GREEN gate would pass, the five `>>` mutations would *create* the file they append to, and
the suite would report **PASS on a vacuous run**.

**False.** Probed against the extracted scanner:

| Scanner input | Exit | Output |
|---|---|---|
| empty directory | **4** | `ENUM_FAIL: sandboxed_units=0 (<5)` |
| truncated tree (only `ci-deploy.sh`) | **4** | `ENUM_FAIL: sandboxed_units=0 (<5)` |
| truncated tree + M1 `>>` mutation applied | **4** | `ENUM_FAIL: sandboxed_units=0 (<5)` |

The scanner carries its **own per-invocation enumeration floor** (`MIN_SANDBOXED_UNITS = 5`
→ `return 4`) and it runs on *every* sandbox. A truncated copy never reaches rc=0, so the
`if ! python3 "$SCANNER" "$sbx"` gate fires and the suite fails **loud**.

**Consequence: do NOT add a per-sandbox non-vacuity floor or a `cp` exit-status check** —
one already exists a layer down, and duplicating it would mirror an existing predicate at
the same threshold for no named sub-value
(`2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate-document-load-bearing-value`).
This paragraph exists so the next reader does not "fix" a non-problem.

---

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/credential-persist-home-guard.test.sh` | Add `copy_scan_tree` + `fresh_sbx`; swap both sandbox allocations and both copies; add `--exclude=.terraform` to the `diff -rq`; prune `.terraform` in the embedded scanner's `os.walk`; add the pre-mutation copy/diff pin. |

**Files to Create:** none.

Deliberately not edited: `infra-config-gate.test.sh` (synthetic fixture, not the real
root); `run-registered-suites.sh` (not the bottleneck); `ci-deploy.test.sh` (owned by
**#6665** — folding it in would put a 530s blast radius in this PR).

---

## Implementation

**One commit.** The copy exclusion and the diff exclusion are a matched pair — landing
either without the other silently disarms `assert_mutated` (see *Anti-vacuity control*).

### 1. Two helpers

Insert after the existing `TMPROOT` trap:

```bash
# `.terraform/` is a gitignored Terraform provider cache (~162 MB once `terraform init`
# has run) holding zero .tf/.sh/.service/.yml files — nothing the scanner reads. Copying
# it 24× peaked TMPROOT at ~3.9 GB against a 4 GB tmpfs /tmp.
#
# GLOBIGNORE (not `find -exec`, not `shopt`): setting it non-null implicitly enables
# dotfile matching, so `.gitignore` and `.terraform.lock.hcl` are still copied — a bare
# `cp -r "$1"/* ` would silently DROP them, and `diff -rq` would then report
# "Only in $REAL_ROOT" on every sandbox, permanently satisfying assert_mutated and
# re-introducing the exact vacuity bug this change exists to fix.
# One `cp` invocation is deliberate: `find … -exec cp -r {} \;` forks per entry (~236 of
# them) and measured 44.6s vs 8.0s. Assumes $1 holds no glob metacharacters — true for
# mktemp/SCRIPT_DIR paths.
copy_scan_tree() { ( GLOBIGNORE="$1/.terraform"; cp -r "$1"/* "$2"/; ); }

# Sandboxes were never reclaimed until the EXIT trap, so all 24 were concurrently
# resident. Reclaiming the previous one first bounds the footprint at a single tree and
# keeps the last sandbox alive for post-mortem. Cheap ONLY because of the exclusion above
# (rm -rf of ~4.5 MB, not 166 MB) — on its own this measured a wall-clock REGRESSION.
fresh_sbx() { rm -rf "$TMPROOT"/sbx.*; mktemp -d "$TMPROOT/sbx.XXXXXX"; }
```

An explicit empty-array guard is **not** included: with `set -euo pipefail` (line 48) an
unmatched glob makes `cp` fail loudly, and the scanner's own `ENUM_FAIL` floor catches a
truncated tree. Both verified.

### 2. Both call sites

In `expect_red` and `expect_green`:

```bash
-  local sbx; sbx="$(mktemp -d "$TMPROOT/mut.XXXXXX")"   # grn.XXXXXX in expect_green
-  cp -r "$REAL_ROOT"/. "$sbx"/
+  local sbx; sbx="$(fresh_sbx)"
+  copy_scan_tree "$REAL_ROOT" "$sbx"
```

### 3. The paired diff

```bash
-  if diff -rq "$REAL_ROOT" "$sbx" >/dev/null 2>&1; then
+  # --exclude is load-bearing, not cosmetic: $sbx no longer holds .terraform, so an
+  # unexcluded diff can NEVER report the trees identical — assert_mutated would pass
+  # unconditionally and every broken mutation would be misreported as a vacuous guard.
+  if diff -rq --exclude=.terraform "$REAL_ROOT" "$sbx" >/dev/null 2>&1; then
```

Literal `.terraform`, not a shared variable: the third site is inside the scanner heredoc,
which a shell variable cannot reach, so a variable would ship a divergent hardcode
*alongside* the indirection meant to prevent one — and it would force escaping-heavy greps
in every assertion built on it.

### 4. Prune the scanner walk

```python
-    for dp, _dirs, files in os.walk(root):
+    for dp, dirs, files in os.walk(root):
+        # `.terraform/modules/` holds real .tf files as soon as any `module {}` block with
+        # a registry/git source is added. The REAL_ROOT scan would then enumerate units
+        # from vendored third-party code while every sandbox scan does not — a RED on the
+        # real tree over code the team does not own and cannot fix. Zero `module` blocks
+        # exist today, so this is behaviour-preserving now and cheap insurance later.
+        dirs[:] = [d for d in dirs if d != '.terraform']
```

`dirs[:]` in-place assignment is required — rebinding `dirs` does not prune the walk.
**This line, not the copy change, is what removes the suite's environment-dependence**:
after it, the `REAL_ROOT` scan and the sandbox scans walk the same logical tree whether or
not the developer has run `terraform init`.

### 5. Pin the copy/diff pair — **once**, not per mutation

Insert immediately before the `--- AC3: mutation battery ---` banner:

```bash
# Copy/diff pair pin (ONCE, not per-mutation: this is a property of copy_scan_tree, not of
# any individual mutation). A fresh copy MUST diff-clean against the source under the same
# exclusion — otherwise assert_mutated below can never report "mutation did not land" and
# every broken mutation is misattributed to the scanner.
_pin_sbx="$(mktemp -d "$TMPROOT/pin.XXXXXX")"
copy_scan_tree "$REAL_ROOT" "$_pin_sbx"
if diff -rq --exclude=.terraform "$REAL_ROOT" "$_pin_sbx" >/dev/null 2>&1; then
  pass "copy/diff pair intact: a fresh copy_scan_tree copy diff-cleans against the source"
else
  fail "copy/diff pair BROKEN: fresh copy differs from source (assert_mutated is now vacuous)" \
    "$(diff -rq --exclude=.terraform "$REAL_ROOT" "$_pin_sbx" 2>&1 | head -3)"
fi
rm -rf "$_pin_sbx"
```

**Placement is load-bearing and was corrected by measurement.** The first draft put this
check inside `expect_red`, running it before every mutation. Measured: **16.5–17.9s — a
regression against the 10.4s baseline**, because 20 extra full-tree recursive diffs cost
~9s. Hoisting it to a single invocation costs ~0.4s and pins the identical property, since
the property belongs to the *helper*, not to any mutation.

**Verified non-vacuous:** replacing `copy_scan_tree` with the tempting "simplification"
`cp -r "$1"/* "$2"/` (which silently drops `.gitignore` and `.terraform.lock.hcl` — R5)
makes this pin report `FAIL: copy/diff pair BROKEN`, i.e. `PASS=28 FAIL=1`.

No static self-grep pin is included: a call-site count assertion would go RED when someone
legitimately adds a 25th mutation, and a source-text pin breaks on a rename while seeing
nothing outside this file. AC5's grep covers the one shape that matters (an unexcluded
diff surviving).

### 6. Verify and measure

1. `bash apps/web-platform/infra/credential-persist-home-guard.test.sh` → `FAIL=0`.
2. Rebuild the external benchmark, **3 runs each** before/after, and report the spread
   (`2026-04-22-binary-lcp-gate-vs-measurement-variance`):
   ```bash
   B=/var/tmp/credbench; rm -rf "$B"; mkdir -p "$B/infra" "$B/tmp"
   cp -a apps/web-platform/infra/. "$B/infra/"
   # safe to hardlink here, unlike the R2 case: .terraform is never mutated and never
   # enters a sandbox — no mutation appends to it.
   cp -al <a-worktree-with-warm-.terraform>/apps/web-platform/infra/.terraform "$B/infra/.terraform"
   TMPDIR="$B/tmp" CRED_GUARD_INFRA_ROOT="$B/infra" \
     bash apps/web-platform/infra/credential-persist-home-guard.test.sh
   ```
   Sample peak with `du -sm "$B/tmp"` on a background loop.
3. `bash apps/web-platform/infra/run-registered-suites.sh` → 72/72 green.

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `bash apps/web-platform/infra/credential-persist-home-guard.test.sh` exits **0**
  with `FAIL=0` and `PASS` ≥ **29** (28 existing + the step-5 copy/diff pair pin). Measured
  `PASS=29 FAIL=0`.
- **AC2** Under the external benchmark (162 MB `.terraform`, disk-backed `TMPDIR`), peak
  `TMPROOT` is **< 250 MB** — measured 5 MB, was 3,980 MB. *Threshold basis:* ~6% of the
  4.0 GB tmpfs, i.e. a footprint that stays safe with all 6 parallel runner slots occupied
  and survives growth of both the battery and the infra root. Report the 3-run spread.
- **AC3** Median suite wall-clock over **3 runs** under the benchmark does **not regress**
  versus the 10.4s BEFORE figure (measured 7.2 / 8.0 / 9.6s → median 8.0s). Median, not
  best-of, because the run-to-run spread (±17%) is comparable to the improvement. This is
  the gate that catches all three measured traps: `find -exec` (44.6s), `fresh_sbx`-alone
  (14.2s), and a per-mutation pin (16.5–17.9s). Report all 3 runs.
- **AC3a** A `copy_scan_tree` replaced by a bare `cp -r "$1"/* "$2"/` makes the step-5 pin
  report `FAIL: copy/diff pair BROKEN` — i.e. the pin is non-vacuous. Verified during
  planning; re-verify with a scratch copy at `/work` time and paste the line into the PR
  body. Do **not** commit the mutation.
- **AC4** `bash apps/web-platform/infra/run-registered-suites.sh` reports **72 passed, 0
  failed**. Required because this edits a *registered* infra suite and `scripts/test-all.sh`
  does not cover `apps/web-platform/infra/` — the coverage boundary of
  `2026-07-26-a-green-test-run-is-only-evidence-for-what-it-actually-ran`. Runner
  wall-clock is *recorded, not asserted*: it is predicted unchanged (~8m50s).
- **AC5** `git grep -c 'cp -r "$REAL_ROOT"' -- <suite>` and
  `git grep -c 'diff -rq "$REAL_ROOT" "$sbx"' -- <suite>` both return **0** (no unguarded
  copy or unexcluded diff survives).

### Post-merge (operator)

_None._ Every step is automatable in-session. No operator action, credential mint,
dashboard visit, or `terraform apply`.

**Ship instruction (not an AC):** the PR body must state that the runner's ~8m50s is
unchanged and bounded by `ci-deploy.test.sh`, and name **#6665** — so no reader mistakes
this PR for a runner speedup or closes #6665 against it.

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — an author-time guard
with no runtime path. The realistic failure is indirect: a silently-degraded guard stops
catching the credential-persist-to-`$HOME` class (#6565; 2026-04-06 doppler precedent),
which next surfaces as a **production deploy failing with EROFS under
`ProtectHome=read-only`** — the user's deploy stops working. That is why step 5 pins the
copy/diff pair 20× rather than asserting it once.

**If this leaks, the user's data/workflow/money is exposed via:** no new vector — the
change strictly *reduces* bytes written to local temp.

**Brand-survival threshold:** `none`. Author-time test harness; touches no path in the
sensitive-path regex (no schema, migration, auth flow, API route, `.sql`), so no scope-out
bullet is required.

## Domain Review

**Domains relevant:** none — infrastructure/tooling change to a bash test harness. No UI
surface in `Files to Edit`, so the mechanical UI-surface override does not fire.
Product/UX Gate: **NONE**.

## Architecture Decision (ADR/C4)

**N/A — no architectural decision.** No ownership/tenancy move, no new substrate or
integration pattern, no resolver/trust-boundary change, no ADR reversed. Per the C4
completeness mandate: the change adds no external human actor, no external system or
vendor (a local provider cache is not a modelled system), no container or data store
(`TMPDIR` scratch is not an architectural element), and no actor↔surface access
relationship — so `model.c4` / `views.c4` / `spec.c4` are unaffected and no element
description is falsified.

## Encryption Posture

**N/A** — no persistent store and no new cross-component connection; `Files to Edit`
matches none of the detection globs. The change strictly reduces bytes written to temp.

## Observability

```yaml
liveness_signal:
  what: "suite exit status + `=== credential-persist-home-guard: PASS=N FAIL=M ===` summary"
  cadence: "every PR touching apps/web-platform/infra/**"
  alert_target: "deploy-script-tests required check"
  configured_in: ".github/workflows/infra-validation.yml (job deploy-script-tests, line 763)"
error_reporting:
  destination: "GitHub Actions job log + step annotation; non-zero exit reds the required check"
  fail_loud: true   # sole exit chokepoint: `[[ "$FAIL" -eq 0 ]] || exit 1`
failure_modes:
  - mode: "copy over-strips, or the diff loses its exclusion -> assert_mutated misattributes"
    detection: "in-suite step-5 pin: fresh copy must diff-clean against the source before mutation, 20x"
    alert_route: "FAIL>0 -> deploy-script-tests red"
  - mode: "sandbox copy truncated (ENOSPC)"
    detection: "scanner's own MIN_SANDBOXED_UNITS=5 floor returns rc=4 on every sandbox (verified)"
    alert_route: "`fresh copy not GREEN before mutation` -> deploy-script-tests red"
logs:
  where: "GitHub Actions job log; locally, stdout of run-registered-suites.sh"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: "bash apps/web-platform/infra/credential-persist-home-guard.test.sh; echo rc=$?"
  expected_output: "final line `=== credential-persist-home-guard: PASS=<N> FAIL=0 ===` and rc=0"
```

No `ssh` in any field; every failure mode is detected in-suite. **Soak enrollment:** N/A —
no time-gated criterion.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (60 issues) and
matched every planned path against issue bodies: **0 matches** for
`credential-persist-home-guard.test.sh`, `ci-deploy.test.sh`, `run-registered-suites.sh`.
**None.**

Adjacent, deliberately not folded in: **#6665** (`ci-deploy.test.sh`). **Disposition:
acknowledge** — different file, different mechanism (real `sleep`, not disk I/O), 530s
blast radius, and its remedy risks masking genuine lease/lock/drain timing regressions.

---

## Risks & Mitigations

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| **R1** | Excluding `.terraform` from the copy without excluding it from `diff -rq` makes `assert_mutated` pass unconditionally. | High if split across commits | Single commit; AC5 greps for it; step-5 pins the pair 20×; **measured both ways**. |
| **R2** | Hardlinking instead of excluding would corrupt the developer's real worktree: five mutations (M1/M3/M3b/M3c/M9) append with `>>`, which writes *through* a hardlink. `sed -i` mutations are safe (temp+rename), which makes the hazard easy to miss in review. | Certain if attempted | Rejected in *Alternatives*; rationale recorded inline so a future optimiser does not retry it. |
| **R3** | Implementing the exclusion with `find … -exec cp -r {} \;` regresses wall-clock 4× (44.6s vs 10.4s). | High — it is the obvious first attempt | Prescribed form is a single `cp`; **AC3** is the gate. |
| **R4** | Shipping `fresh_sbx` alone (the tempting "3-line whole fix") regresses wall-clock to 14.2s. | Medium | Both fixes ship together; measured table makes the coupling explicit; **AC3** catches it. |
| **R5** | "Simplifying" `copy_scan_tree` to a bare `cp -r "$1"/*` silently drops `.gitignore` and `.terraform.lock.hcl` (globs skip dotfiles), re-introducing R1's vacuity by a different route. | Medium | `GLOBIGNORE` non-null implicitly enables dotfile matching — **verified**; the helper's comment states why. |
| **R6** | A future gitignored cache (`.terragrunt-cache`, `.venv`, `node_modules`) re-creates the problem, since the exclusion is a one-name denylist. | Low | Accepted. A manifest-parity assertion was considered and rejected as over-built for a directory whose contents are stable; step-5's pin makes any *behavioural* consequence visible. |

## Alternatives Considered

| Approach | Verdict | Rationale |
|---|---|---|
| Exclusion **+** `fresh_sbx` | **Adopted** | Best measured on both axes: 7.5s, 5 MB peak. |
| `fresh_sbx` alone | **Rejected** | Elegant (3 lines, no diff coupling) but **measured 14.2s — a regression**. `rm -rf` of a 166 MB tree 24× costs more than the concurrency it saves. |
| Exclusion alone | **Rejected** | 8.0s / 108 MB — good, but peak still scales with battery size; `fresh_sbx` makes it constant for 2 more lines. |
| Hardlink `.terraform` (`cp -al`) | **Rejected** | Unsafe — see R2. |
| Symlink `.terraform` | **Rejected** | Correct only by accident, via two independent defaults (`os.walk(followlinks=False)`, `diff` treating a symlink as unequal to a directory). |
| `rsync -a --exclude` | **Rejected** | The suite's header advertises *"pure bash + python3"*; adding a dependency contradicts a documented invariant for no measured gain. |
| `cp --reflink=auto` | **Rejected** | Free on btrfs/xfs, a silent no-op on ext4 — environment-dependent, so it would fix the problem on some machines only. |
| Point `TMPROOT` at disk-backed storage | **Rejected** | Hides the waste rather than removing it. |
| Minimal fixture instead of the real root | **Rejected** | This battery's value *is* scanning the real tree; a curated fixture would drift and re-open the false-GREEN class the suite exists to close. |
| Per-sandbox non-vacuity floor / `cp` exit check | **Rejected** | The scanner's `ENUM_FAIL` floor already does this on every sandbox — **verified**. Duplicating it mirrors an existing predicate for no named sub-value. |
| Fold in **#6665** | **Rejected — acknowledge** | It *is* the lever for the 8.5-minute goal, but separate file, separate mechanism, separate open issue, 530s blast radius. |
| Fix `cp -r /src /build` in `sandbox-canary-verify-in-image.sh:42` / `plugin-root-propagation-verify-in-image.sh:39` | **Scoped out** | Genuine adjacent waste (they copy `apps/web-platform`, which contains `infra/.terraform` *and* `node_modules`, into a container layer) — but not infra suites, not run by the infra runner, live in `ci.yml`, exit early without `ANTHROPIC_API_KEY`, and run `npm ci` immediately after. **Requires a tracking issue at `/work` time** — *what:* exclude `node_modules` + `infra/.terraform` from that copy; *why deferred:* different class, zero effect on the runner; *re-evaluate when:* either script's local runtime exceeds ~60s or a contributor reports container-layer disk pressure; *milestone:* from `roadmap.md` at filing time. |

## Decision Challenges

Recorded rather than surfaced interactively — this phase ran headless inside a pipeline
Task subagent, so `AskUserQuestion` is unavailable by construction. `/ship` should render
this into the PR body and file it as an `action-required` issue.
**Stated default, so this cannot block the merge: absent a reply, this PR ships as scoped
and #6665 stays separate and unclaimed.**

**Challenge 1 — the stated goal is not achievable by the stated fix.** The task directs:
*"measure the wall-clock improvement of the infra half of the runner before/after."* The
improvement is **zero**, and necessarily so: the runner is bounded by `ci-deploy.test.sh`
at 529.9s while this suite costs 9.6s. An AC asserting a runner improvement could only
pass by measurement noise. The plan still performs the requested fix — it has independent,
measured value (3,980 MB → 5 MB peak against a 4.0 GB tmpfs) — but changes the *claim*:
AC4 asserts the runner stays green, and the ship instruction requires the PR body to say
the runner time is unchanged. **If the operator's real priority is the 8.5 minutes rather
than this specific fix, the work to schedule is #6665, not this plan.**

**Challenge 2 — "several infra suites" is one.** An exhaustive sweep found exactly one.
The instruction is satisfied by the single-suite fix; the sweep predicates are recorded in
*Premise Validation* so the negative result is not re-derived later.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.**
- **Excluding a path from a copy silently disarms any `diff` that pairs with it.** Once
  the sandbox can never be byte-identical to the source, an unexcluded `diff -rq` returns
  "different" unconditionally and every `assert_mutated`-style guard built on it passes for
  free. Whenever a copy narrows, grep every consumer that compares the two trees and narrow
  it in the *same commit*.
- **A test whose fixture is a gitignored build artifact behaves differently per machine.**
  `.terraform` exists only after `terraform init`; CI never has it. Any measurement in a
  fresh worktree shows **zero** improvement because the pathology is absent — reproduce it
  deliberately before claiming a before/after delta.
- **`/tmp` here is a 4.0 GB tmpfs and the infra runner puts 6 suites into it
  concurrently.** Peak-footprint regressions in one suite are a cross-suite contention
  source. Prefer `du -sm` sampling over wall-clock assertions when pinning this —
  wall-clock gates on a loaded parallel runner are the flake class of #6496.
- **Fixes that are individually obvious can each be regressions while their combination
  wins.** Both single-fix variants here are slower than the pair; two of the three
  candidate implementations are slower than doing nothing. Measure combinations, not just
  candidates.

## Related

- **#6665** (OPEN, P2) — `ci-deploy.test.sh` real-sleep cost; the actual lever for the 8.5 min.
- **#6730** — why `run-registered-suites.sh` exists. **#6789**, **#6734** (both CLOSED) — `/tmp` contention and tmpfs leak.
- `knowledge-base/project/learnings/2026-07-26-a-green-test-run-is-only-evidence-for-what-it-actually-ran.md`
- `knowledge-base/project/learnings/best-practices/2026-04-22-binary-lcp-gate-vs-measurement-variance.md`
- `knowledge-base/project/learnings/best-practices/2026-06-08-migration-gate-test-must-use-minimal-fixture-not-whole-dir-copy.md`
- `knowledge-base/project/learnings/workflow-patterns/2026-07-17-source-scan-guard-battery-must-vary-shape-not-just-value.md`
