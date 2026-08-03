# Tasks — chore: release-job ceiling + C4 embedded-count parity (#7160)

Plan: `knowledge-base/project/plans/2026-08-03-chore-release-timeout-and-c4-count-parity-plan.md`
Branch: `feat-one-shot-7160-release-timeout-and-c4-count-parity` · Issue: #7160

> **Phase order is load-bearing.** Phase 1 declares the contract; Phase 2 asserts it. Reversing them
> leaves Phase 2 with nothing true to assert.

---

## Phase 0 — Preconditions (no edits)

- [ ] **0.1** Confirm CWD is the worktree; `git branch --show-current` equals the feature branch.
- [ ] **0.2** Run the PR #7206 sequencing rule: `gh pr view 7206 --json state,mergedAt`.
  - [ ] **0.2.1** Merged → `git fetch origin && git rebase origin/main`.
  - [ ] **0.2.2** Open → rebase onto `origin/main` anyway; expect to hand-resolve the `@@ -581` hunk when #7206 lands. Do **not** cherry-pick #7206's commits.
- [ ] **0.3** Re-derive all seven counts C1–C7 (plan §Verified Derivations). Record each. Any drift → correct `model.c4` in Phase 3 and note it.
- [ ] **0.4** Capture baselines:
  - [ ] **0.4.1** `bash scripts/test-all.sh scripts` — must be green *before* any edit.
  - [ ] **0.4.2** `actionlint .github/workflows/reusable-release.yml` — save output verbatim. It exits **1** today on six pre-existing shellcheck findings (SC2129 ×4, SC2012, SC2015). This is AC2's diff baseline.

## Phase 1 — Declare the ceiling

- [ ] **1.1** `.github/workflows/reusable-release.yml`, `jobs.release`: add `timeout-minutes: 60` adjacent to `runs-on: ubuntu-latest`.
- [ ] **1.2** Add the rationale comment. MUST contain: measured worst run (24.33 min, cold-cache Docker build); the arithmetic **by job name** — `max(release, await-ci) + (migrate + verify-migrations + deploy)` — **never the bare total `135`**; that 60 is the largest value leaving `DRIFT_SUSTAINED_THRESHOLD_MIN` untouched; the P8 caveat that this bounds **execution only**; the B9 coupling (mirror the `COUPLED (#7091)` comment style).
- [ ] **1.3** `actionlint .github/workflows/reusable-release.yml` — **no new diagnostic** vs 0.4.2. (Still exits 1; expected.)
- [ ] **1.4** Confirm `web-platform-release.yml`'s `release` job was NOT given a `timeout-minutes` (schema-forbidden, P3).

## Phase 2 — Close the silent-green holes (B9)

- [ ] **2.1** Rewrite the B8 extractor in `scripts/prod-version-drift-check.test.sh`:
  - [ ] **2.1.1** Resolve the reusable workflow from `jobs.release.uses` — no hard-coded filename. Strip with `removeprefix('./')`, **never** `lstrip('./')`.
  - [ ] **2.1.2** Apply **`360` when `timeout-minutes` is absent, uniformly to all five** critical-path jobs; remove every `int(x or 0)` on that path.
  - [ ] **2.1.3** Emit `max(release_ceiling, await-ci) + migrate + verify-migrations + deploy`.
- [ ] **2.2** Add a **real assertion** on the parse-error / unresolvable-`uses:` arm, and remove B9's `:-0` coercion so an unset sum FAILS instead of passing `195 >= 0`.
- [ ] **2.3** Update B9's assertion text + comment: critical path with a `max()` term (not a serial sum); corrected **495** undeclared figure; the P8 execution-only caveat.
- [ ] **2.4** Comment-only corrections to the two files stating the superseded serial arithmetic:
  - [ ] **2.4.1** `scripts/prod-version-drift-check.sh` header comment. **Do not touch `DRIFT_SUSTAINED_THRESHOLD_MIN` — it stays 195.**
  - [ ] **2.4.2** `.github/workflows/web-platform-release.yml` "one of four on the serial critical path" comment. Comment only — no job/key/value change.
- [ ] **2.5** Raise `MIN_ASSERTIONS` / `MIN_B` by exactly the number of assertions added, computed from **post-rebase** values. Never hardcode from the plan.
- [ ] **2.6** Verify by **mutation**, recording all three outputs:
  - [ ] **2.6.1** Remove the Phase-1 ceiling → suite **RED**.
  - [ ] **2.6.2** Remove `deploy`'s `timeout-minutes` → suite **RED** *(silently green before this change)*.
  - [ ] **2.6.3** Point `jobs.release.uses` at a nonexistent path → suite **RED** *(passes today via `:-0`)*.
  - [ ] **2.6.4** Restore all three → **GREEN**.

## Phase 3 — C4 count parity test

- [ ] **3.1** Create `plugins/soleur/test/c4-count-parity.test.sh` (executable). Follow `plugins/soleur/test/c4-model-freshness.test.sh`: `source test-helpers.sh`, `PASS`/`FAIL`/`print_results`, and `REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"` — never assume CWD.
- [ ] **3.2** Implement the C1–C7 registry with **clause-anchored** regexes (never a bare numeral).
  - [ ] **3.2.1** C1 (7 files) and C5 (8 slugs) MUST use **two different derivations**; do not assert they are equal. `scheduled-terraform-drift.yml` declares two slugs.
  - [ ] **3.2.2** C7 is the number-**word** "ten" — handle explicitly (word→int map, or rewrite the clause to a numeral). State which.
  - [ ] **3.2.3** C2/C3: PyYAML parses `on:` as boolean `True`. Use `d.get("on", d.get(True))` or the `yq` equivalent, else the split silently reads 0/7.
- [ ] **3.3** Implement the mutation/negative check: a synthetic prose copy with a perturbed number must FAIL, and the message must name edge, clause, both values, and the derivation.
- [ ] **3.4** Do **not** implement a completeness guard over unregistered numerals (cut in v2 — verified to red a correct model; see plan §Test design).
- [ ] **3.5** Do **not** register anything in `scripts/test-all.sh` — `plugins/soleur/test/*.test.sh` is auto-globbed. Prove it in 4.1, don't assert it by reading.

## Phase 4 — Verification

- [ ] **4.1** `bash scripts/test-all.sh scripts` — exits 0 **and** output contains the new suite's label.
- [ ] **4.2** `actionlint` on both release workflows — no new diagnostic vs 0.4.2.
- [ ] **4.3** Record Phase 2.6 and 3.3 mutation outputs in the PR body.
- [ ] **4.4** If `model.c4` was edited: regenerate `model.likec4.json` and re-run `plugins/soleur/test/c4-model-freshness.test.sh`.
- [ ] **4.5** Walk all 13 ACs in the plan; record evidence per AC.

## Phase 5 — Ship

- [ ] **5.1** File the two deferral issues (plan §Deferrals): (1) `hetzner -> tunnel` embedded-count staleness (12 vs 18 `connection{}`; THREE vs four `ingress_rule`); (2) unbounded queue/concurrency latency in the commit→deployed path (P8), re-evaluate on the alerter's first false positive.
- [ ] **5.2** Update `CHANGELOG.md`.
- [ ] **5.3** PR body carries `Closes #7160`, the three mutation outputs, the `MIN_*` before→after→delta, and the rendered `decision-challenges.md` (DC1–DC3).
- [ ] **5.4** Run `/soleur:ship`.

---

## Guardrails (violating any of these is a defect, not a style choice)

| Guardrail | Why |
|---|---|
| Never add `timeout-minutes` to `web-platform-release.yml`'s `release` job | Schema-forbidden on a `uses:` job (P3, actionlint-verified) |
| Never claim the bound is "provable"/"strict"/"guaranteed" | False (P8); AC12 forbids it in the diff |
| Never hardcode `MIN_ASSERTIONS` / `MIN_B` from the plan | PR #7206 moves them; a stale value weakens the anti-vacuity floor |
| Never change `DRIFT_SUSTAINED_THRESHOLD_MIN` | Recomputed bound is 195 = current value; no threshold move is triggered |
| Never use `lstrip('./')` | Character-class strip; use `removeprefix('./')` |
| Never write `135` as a bare constant in a comment | Stales silently if any of the three jobs changes |
| Never assert a count with a bare-numeral grep | `cq-assert-anchor-not-bare-token`; `#7138` and ADR ordinals collide |
| Never add a `scripts/*.test.sh` for this work | Not auto-globbed; policed only by an advisory job (orphan-suite class) |
