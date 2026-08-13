---
feature: prebake-rehearsal-image
issue: 7535
branch: feat-prebake-rehearsal-image-7535
pr: 7540
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-13-test-remove-rehearsal-apt-dependency-plan.md
date: 2026-08-13
---

# Tasks — stop the rehearsal's apt failures reading as emitter findings (#7535)

Target file for every task: `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`.

> **Scope note.** An earlier revision proposed a locally-built fixture image plus three guards.
> Seven-agent review measured the value case at **$0 and 0 operator-visible seconds** and found
> the image would introduce a T5 vacuous-green. It is cut. See the plan's
> `## Why the image was cut`. Do not reintroduce it.

## Phase 1 — delete the no-op `e2fsprogs` install (ships now, independently)

Unblocked. Verified conflict-free with PR #7507 (`e2fsprogs` appears 0 times in its diff).

- [ ] **1.1** Record the pre-change baseline for comparison:
      `grep -cE '^[^#]*apt-get (update|install)' <file>` → expect **9**;
      run the suite and save R1's four arm verdicts.
- [ ] **1.2** Delete `apt-get update -qq` and `apt-get install -y -qq e2fsprogs` (`:872-873`).
- [ ] **1.3** Delete the now-dead `export DEBIAN_FRONTEND=noninteractive` (`:871`).
- [ ] **1.4** Add a replacement comment stating: `ubuntu:24.04` ships
      `e2fsprogs 1.47.0-2.4~exp1ubuntu4.1` at `Priority: required`; and that removing the install
      narrows R1's `e2fsprogs` source from **mirror-current to image-current** — a behaviour
      change, not a no-op, and a faithfulness improvement because the fingerprint's subject is the
      cloud image's own `e2fsprogs` (`git-data-birth-fs-fingerprint.txt:22`).
      Do **not** describe `fingerprint.txt:57` as a pin — `:56` marks that block
      `CONTEXT FOR FAILURE MESSAGES ONLY — not asserted`.
- [ ] **1.5** Re-run the suite; confirm R1's four arms produce verdicts identical to 1.1 (AC4).
- [ ] **1.6** Confirm the assertion floor at `:1448` and the reported `total` are **unchanged**
      (AC5) — this phase adds and removes no assertion.
- [ ] **1.7** Run `bash apps/web-platform/infra/git-data-render-strip-parity.test.sh` (AC6).
- [ ] **1.8** Verify AC1 (`→ 7`), AC2 (`e2fsprogs` gone outside comments), AC3
      (`DEBIAN_FRONTEND` count −1).
- [ ] **1.9** Push. PR body uses **`Refs #7535`, never `Closes`** — this does not remove the apt
      dependency, and the issue stays open at residual scope.
- [ ] **1.10** Post the plan's `## Why the image was cut` measurements as a comment on #7535, and
      retitle it to the residual scope.

## Phase 2 — name the remaining apt failures (BLOCKED on #7507 merging)

Do not start until `gh pr view 7507 --json state,mergedAt` shows merged. #7507 restructures the R4
site and ships the `fixture_fail` helper this phase reuses.

- [ ] **2.1** Rebase onto merged `main`; re-run the suite to establish a post-rebase baseline.
- [ ] **2.2** Confirm which apt cycles #7507 already covers, and scope this phase to the
      remainder — expected: the `run_case` site (`:553`, 2 spins), the T5-mutation site (`:620`),
      the T17-mutation site (`:656`), and the `_s1_run` site (`:684-685`, 2 spins). Re-derive
      these line numbers post-rebase rather than trusting them.
- [ ] **2.3** For each, rc-check `apt-get update` and `apt-get install` and route failure to
      #7507's `fixture_fail` with a message naming **the site and the cause**, distinct per site
      (AC8, AC9).
- [ ] **2.4** Add **no** `Acquire::Retries` or backoff outside the R4 site (AC11) — retry is a
      separate decision from naming.
- [ ] **2.5** Add **no** new command substitution. Then run
      `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
      and confirm `git diff --stat` shows **zero** changes to the baseline file (AC10) — it carries
      7 grandfathered findings for this file and may only shrink.
- [ ] **2.6** Induce a failure at each site (e.g. point apt at an unreachable mirror) and confirm
      each produces its own distinct named message (AC8).
- [ ] **2.7** If the assertion count moved, re-derive the floor at `:1448` **and** extend the
      itemized ledger at `:1435-1447` in the same edit (AC12) — the file's convention (`:1436`) is
      that the sum is itemized so the next author can check it rather than trust it.
- [ ] **2.8** Re-run the full suite; push.

## Verification

- [ ] **3.1** Run `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (AC7).
- [ ] **3.2** Confirm the diff touches exactly one file and adds no workflow, `.tf`, Dockerfile,
      registry step, secret or scheduled job.
- [ ] **3.3** Confirm no `_skip` call site was added — a failed provisioning step must never route
      through `_skip`, which exits 0 off-CI (`:37-38`).
