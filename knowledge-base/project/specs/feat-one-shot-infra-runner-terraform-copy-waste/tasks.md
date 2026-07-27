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

- [ ] 1.1 Read the plan's *Measurements* section before writing any code. Three
      implementations that look correct are measured regressions: `find … -exec cp -r {} \;`
      (44.6s), `fresh_sbx` alone (14.2s), and the copy/diff pin placed per-mutation
      (16.5–17.9s). Do not re-derive these.
- [ ] 1.2 Build the external benchmark and capture the **BEFORE** baseline, 3 runs
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
- [ ] 1.3 If no worktree has a warm `.terraform`, create one with
      `terraform init -backend=false` in a scratch copy — **never** inside the repo
      worktree. Without it, before/after are identical and the measurement is meaningless.

## 2. Core implementation (one commit)

- [ ] 2.1 Add `copy_scan_tree()` and `fresh_sbx()` after the `TMPROOT` trap, with the
      plan's comments verbatim — they record *why* it is `GLOBIGNORE` and not `find -exec`
      or `shopt`, and why a bare `cp -r "$1"/*` would re-introduce the vacuity bug by
      dropping dotfiles. Do **not** add an empty-array guard or a `cp` exit-status check
      (the plan documents why both are redundant, with evidence).
- [ ] 2.2 Replace the sandbox allocation at **both** call sites (`expect_red`,
      `expect_green`): `mktemp -d "$TMPROOT/{mut,grn}.XXXXXX"` → `fresh_sbx`.
- [ ] 2.3 Replace the copy at **both** call sites: `cp -r "$REAL_ROOT"/. "$sbx"/` →
      `copy_scan_tree "$REAL_ROOT" "$sbx"`.
- [ ] 2.4 Add `--exclude=.terraform` to the `diff -rq` in `expect_red`, with the comment
      explaining it is load-bearing. **Same commit as 2.3** — this is the matched pair.
- [ ] 2.5 Prune the scanner's walk: `for dp, _dirs, files in os.walk(root)` →
      `for dp, dirs, files …` plus `dirs[:] = [d for d in dirs if d != '.terraform']`.
      In-place `dirs[:]` is required; rebinding does not prune.
- [ ] 2.6 Add the one-time copy/diff pair pin immediately before the
      `--- AC3: mutation battery ---` banner. **Once, not per-mutation.**
- [ ] 2.7 Use the literal `.terraform` at every site — no shared shell variable. The
      scanner heredoc cannot read one, so a variable would ship a divergent hardcode
      alongside the indirection meant to prevent it.

## 3. Testing & verification

- [ ] 3.1 `bash apps/web-platform/infra/credential-persist-home-guard.test.sh` →
      `PASS=29 FAIL=0`, exit 0. *(AC1)*
- [ ] 3.2 Benchmark AFTER, 3 runs: peak `TMPROOT` < 250 MB (expect ~5 MB) *(AC2)*; median
      wall-clock ≤ 10.4s (expect ~8.0s) *(AC3)*. Record all 3 runs and the spread.
- [ ] 3.3 Non-vacuity control *(AC3a)*: in a **scratch copy only**, replace the helper body
      with `cp -r "$1"/* "$2"/` and confirm the pin reports
      `FAIL: copy/diff pair BROKEN` → `PASS=28 FAIL=1`. Paste the line into the PR body.
      Do not commit the mutation.
- [ ] 3.4 `git grep -c 'cp -r "$REAL_ROOT"'` and
      `git grep -c 'diff -rq "$REAL_ROOT" "$sbx"'` on the suite both return **0**. *(AC5)*
- [ ] 3.5 `bash apps/web-platform/infra/run-registered-suites.sh` → **72 passed, 0 failed**.
      Required: this edits a *registered* infra suite that `scripts/test-all.sh` does not
      cover. Record the runner wall-clock; **expect it unchanged** (~8m50s) — that is the
      prediction, not a failure. *(AC4)*
- [ ] 3.6 `bash -n` on the suite passes.

## 4. Ship

- [ ] 4.1 PR body must state that the runner's ~8m50s is **unchanged** and bounded by
      `ci-deploy.test.sh` (529.9s), and name **#6665** — so no reader mistakes this PR for
      a runner speedup or closes #6665 against it.
- [ ] 4.2 PR body carries the before/after table: wall-clock (3 runs each) and peak
      `TMPROOT` (3,980 MB → ~5 MB), plus the AC3a control line.
- [ ] 4.3 File the deferred tracking issue for the container-copy class — exclude
      `node_modules` + `infra/.terraform` from `cp -r /src /build` in
      `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` and
      `plugin-root-propagation-verify-in-image.sh`. Include why it was deferred and the
      re-evaluation criteria from the plan's *Alternatives* table; set the milestone from
      `knowledge-base/product/roadmap.md`.
- [ ] 4.4 Render `## Decision Challenges` from the plan into the PR body and file it as an
      `action-required` issue. **Stated default: absent a reply, this PR ships as scoped
      and #6665 stays separate and unclaimed** — it must not block the merge.
- [ ] 4.5 Use `Closes` only if an issue is opened for this work; otherwise `Ref`.
