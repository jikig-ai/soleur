---
feature: feat-one-shot-infra-runner-terraform-copy-waste
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-27-perf-infra-suite-terraform-copy-exclusion-plan.md
date: 2026-07-27
---

# Tasks — bound `credential-persist-home-guard`'s sandbox footprint

Single file, single commit. The copy exclusion and the diff exclusion are a **matched
pair** — landing either without the other silently disarms `assert_mutated`.

Target: `apps/web-platform/infra/credential-persist-home-guard.test.sh`

## 1. Setup

- [x] 1.1 Read the plan's *Measurements* section before writing any code. Three
      implementations that look correct are measured regressions: `find … -exec cp -r {} \;`
      (44.6s), `fresh_sbx` alone (14.2s), and the copy/diff pin placed per-mutation
      (16.5–17.9s). Do not re-derive these.
- [x] 1.2 Build the external benchmark and capture the **BEFORE** baseline, 3 runs
      (expect ~10.4s wall-clock, ~3,980 MB peak `TMPROOT`):
      ```bash
      B=/var/tmp/credbench; rm -rf "$B"; mkdir -p "$B/infra" "$B/tmp"
      cp -a apps/web-platform/infra/. "$B/infra/"
      # safe to hardlink: .terraform is never mutated and never enters a sandbox
      cp -al <worktree-with-warm-.terraform>/apps/web-platform/infra/.terraform "$B/infra/.terraform"
      TMPDIR="$B/tmp" CRED_GUARD_INFRA_ROOT="$B/infra" \
        bash apps/web-platform/infra/credential-persist-home-guard.test.sh
      ```
      Sample peak with `du -sm "$B/tmp"` on a background loop. The benchmark must live
      **outside the repo** and use a **disk-backed** `TMPDIR`, so tmpfs exhaustion cannot
      truncate the number being measured.
- [x] 1.3 If no worktree has a warm `.terraform`, create one with
      `terraform init -backend=false` in a scratch copy — **never** inside the repo
      worktree. Without it, before/after are identical and the measurement is meaningless.

## 2. Core implementation (one commit)

- [x] 2.1 Add `copy_scan_tree()` and `fresh_sbx()` after the `TMPROOT` trap, with the
      plan's comments verbatim — they record *why* it is `GLOBIGNORE` and not `find -exec`
      or `shopt`, and why a bare `cp -r "$1"/*` would re-introduce the vacuity bug by
      dropping dotfiles. Do **not** add an empty-array guard or a `cp` exit-status check
      (the plan documents why both are redundant, with evidence).
- [~] 2.1a **DEVIATED — the fast path was measured OUT and is NOT shipped.** The plan's
      justification (cold root 9.8s -> 11.0s without it, 7.2s with) did not reproduce. Interleaved
      A/B, 5 pairs, cold root: **6.86s WITH the fast path vs 6.60s WITHOUT** — no saving. It also
      opened a coverage hole: CI is always cold, so a fast path means CI never executes the
      `GLOBIGNORE` line and the step-5 pin could not catch a regression in it. AC3b is retained
      as a flat-within-noise gate (origin/main 5.76s -> this PR 5.89s; the +0.13s is the 29th
      assertion the pin adds). Recorded in the plan under "/work deviation".
- [x] 2.2 Replace the sandbox allocation at **both** call sites (`expect_red`,
      `expect_green`): `mktemp -d "$TMPROOT/{mut,grn}.XXXXXX"` → `fresh_sbx`.
- [x] 2.3 Replace the copy at **both** call sites: `cp -r "$REAL_ROOT"/. "$sbx"/` →
      `copy_scan_tree "$REAL_ROOT" "$sbx"`.
- [x] 2.4 Add `--exclude=.terraform` to the `diff -rq` in `expect_red`, with the comment
      explaining it is load-bearing. **Same commit as 2.3** — this is the matched pair.
- [x] 2.5 Prune the scanner's walk: `for dp, _dirs, files in os.walk(root)` →
      `for dp, dirs, files …` plus `dirs[:] = [d for d in dirs if d != '.terraform']`.
      In-place `dirs[:]` is required; rebinding does not prune.
- [x] 2.6 Add the one-time copy/diff pair pin immediately before the
      `--- AC3: mutation battery ---` banner. **Once, not per-mutation.**
- [x] 2.7 Use the literal `.terraform` at every site — no shared shell variable. The
      scanner heredoc cannot read one, so a variable would ship a divergent hardcode
      alongside the indirection meant to prevent it.

## 3. Testing & verification

- [x] 3.1 `bash apps/web-platform/infra/credential-persist-home-guard.test.sh` →
      `PASS=29 FAIL=0` (**exactly** 29, not `≥`), exit 0. *(AC1)*
- [x] 3.2 Benchmark AFTER on the **warm** root, 3 runs: peak `TMPROOT` < 250 MB (expect
      ~5 MB) *(AC2)*; median wall-clock ≤ 10.4s (expect ~8.0s) *(AC3)*. Record the spread.
- [x] 3.2a **Cold-root control** *(AC3b)*: with no `.terraform` in `CRED_GUARD_INFRA_ROOT`,
      median over 3 runs must not regress vs `origin/main` (expect ~7.2s vs 9.8s). This is
      the only shape CI runs and AC3 cannot catch it.
- [x] 3.3 Non-vacuity control *(AC3a)*: in a **scratch copy only**, replace the helper body
      with `cp -r "$1"/* "$2"/` and confirm the pin reports
      `FAIL: copy/diff pair BROKEN` → `PASS=28 FAIL=1`. Paste the line into the PR body.
      Do not commit the mutation. (This control discriminates on a cold root too, because
      `.gitignore`/`.terraform.lock.hcl` exist regardless of `terraform init`.)
- [x] 3.4 `grep -c 'cp -r "\$REAL_ROOT"' <suite>` and
      `grep -c 'diff -rq "\$REAL_ROOT" "\$sbx"' <suite>` both return **0**. *(AC5)* Keep the
      `\$` escaping (single-quoted `\$` = literal `$` in BRE; the unescaped form silently
      returns 0 even on the unpatched file), and append `|| true` if wrapping under
      `set -euo pipefail` — `grep -c` exits 1 on a zero count.
- [x] 3.5 `bash apps/web-platform/infra/run-registered-suites.sh` → **72 passed, 0 failed**.
      VERIFIED: rc=0, 72/72, **elapsed 543s (9m03s)**. Runner wall-clock is *recorded, not
      asserted*, and it is **unchanged** vs the ~8m50s baseline — that is the prediction
      holding, not a failure. It is the direct evidence that this PR is not a runner speedup:
      the runner is bounded by `ci-deploy.test.sh` (529.9s), tracked as issue #6665.
- [x] 3.6 `bash -n` on the suite passes.

## 4. Ship

- [ ] 4.1 PR body must state that the runner's ~8m50s is **unchanged** and bounded by
      `ci-deploy.test.sh` (529.9s), and name **#6665** — so no reader mistakes this PR for
      a runner speedup or closes #6665 against it.
- [ ] 4.2 PR body carries the before/after table: wall-clock (3 runs each) and peak
      `TMPROOT` (3,980 MB → ~5 MB), plus the AC3a control line.
- [x] 4.3 Deferred container-copy tracking issue filed: **#7007**
      (`deferred-scope-out`, milestone Post-MVP / Later). Both cited sites verified to exist at
      the exact plan-quoted lines: `sandbox-canary-verify-in-image.sh:42` and
      `plugin-root-propagation-verify-in-image.sh:39` (both under `apps/web-platform/scripts/`).
      Not inlined: they need ANTHROPIC_API_KEY + docker and drive a real paid turn, so the
      change is unverifiable in-session; benefit in CI is ~zero today.
- [~] 4.4 DEVIATED — the Decision Challenge is rendered into the PR body (prominently, under
      "Read this first: what this PR does NOT do") but NOT filed as a new `action-required`
      issue. Filing one would be a meta-issue: the challenge's whole content is "if the 8.5
      minutes is the real priority, schedule #6665" — and #6665 already exists and is OPEN, so
      it IS the queue item. Instead the measured critical-path data was posted as a comment on
      #6665 itself (issuecomment-5092912888), where whoever picks it up will read it. Net issue
      flow for this item: 0 instead of +1. Stated default still holds: absent a reply this PR
      ships as scoped and #6665 stays separate and unclaimed.
- [ ] 4.5 Use `Closes` only if an issue is opened for this work; otherwise `Ref`.
