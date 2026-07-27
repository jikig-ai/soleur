# Tasks — feat-one-shot-6665-ci-deploy-mock-sleep

Derived from
[`2026-07-27-perf-ci-deploy-test-sleep-mock-default-plan.md`](../../plans/2026-07-27-perf-ci-deploy-test-sleep-mock-default-plan.md)
(v2, post 5-agent plan-review). Issue #6665.

**Run the suite with `run_in_background: true`.** It exceeds the foreground Bash
limit, and a 300 s `Monitor` will time out before it finishes.

**Numbering contract:** step numbers here mirror the plan's exactly — `N.M` means
the same thing in both documents. Where a plan step needs several concrete
actions, they are lettered (`2.2a`, `2.2b`, …) rather than renumbered, so a plan
citation like "Phase 2.2's rewritten comment" always resolves to `2.2*` here. Do
not renumber one file without the other.

---

## Phase 0 — Preconditions (no edits)

- [x] **0.1** Re-confirm `deploy-script-tests` is advisory against the **right**
      file: `grep -n 'deploy-script-tests' infra/github/ruleset-ci-required.tf`
      and the `infra-validate-required` `needs:` list
      (`.github/workflows/infra-validation.yml`). Plan-time result: absent from
      both. Do **not** grep `apps/web-platform/infra/*.tf` — no ruleset lives
      there, so the command cannot falsify the claim.
- [x] **0.2** Repo-wide seam sweep: `grep -rn 'MOCK_SLEEP_NOOP' . --exclude-dir=.git`.
      Record every hit and its disposition. Historical record
      (`knowledge-base/project/learnings/`, `knowledge-base/project/{plans,specs}/`)
      is **excluded from rewriting** — those files legitimately cite the old seam.
- [x] **0.3** Build the **loop-exit classification** table for all **15** `sleep`
      **invocation** sites in `ci-deploy.sh` — `:1200 :1201 :1275 :1278 :1472
      :1851 :1915 :1961 :2471 :2477 :2483 :2491 :2526 :2610 :2678` — labelling
      each enclosing loop *bounded-iteration* / *counter-bounded* /
      *straight-line* / *wall-clock exit*. Must include the five canary
      `sleep 3` sites (`:2471`, `:2477`, `:2483`, `:2491`, `:2526`) inside the
      `:2452` `seq` loop. Conclusion must be zero reachable hot-spin loops. Keep
      for the PR body (AC4).
      **The count is 15.** Verify by RUNNING
      `grep -nE '\bsleep ' apps/web-platform/infra/ci-deploy.sh | grep -vE ':\s*#' | wc -l`.
      A bare `grep -c '\bsleep\b'` is the wrong instrument and reads **16** — the
      one extra is the comment at `:1430`. (The plan originally said 17, blaming
      the `_sleeps` array declaration at `:1437`; that never matched, since `_`
      is a word character. Measured at /work, not reasoned.)
- [x] **0.4** Clean solo baseline for the record:
      `time bash apps/web-platform/infra/ci-deploy.test.sh`. Plan-time reading:
      `real 8m58.232s / user 0m41.805s / sys 1m32.496s`, `184/184 passed`.
      Save the output — it is the `before` side of every name-set diff.

## Phase 1 — RED: make the schedule assertable

- [x] **1.1** Extend `create_mock_sleep` (`ci-deploy.test.sh:676-682`):
      - append `$1` to `$MOCK_SLEEP_LOG` when that var is non-empty (mirror
        `rec()` at `workspaces-luks-harness.sh:163`);
      - add an **~500-invocation cap** that writes a named diagnostic to stderr
        and `exit 1`.
      Leave the gate opt-in at this step — this commit must change no timing.
- [x] **1.2** Upgrade T-6525-8 (`:3943-3969`): assert the recorded default
      schedule is exactly `2` then `4`, alongside the existing 3-pulls assertion.
      Truncate `$MOCK_SLEEP_LOG` before the arm; add it to the `unset` at `:3966`.
- [x] **1.3** **Mutation-prove it.** Back up `ci-deploy.sh`; mutate `:1437`
      `${PULL_TRANSIENT_RETRY_SLEEPS-2 4}` → `-9 9` **in place**; run T-6525-8;
      require **FAIL**; restore from the backup **in a separate Bash call**.
      Paste the mutation output (AC3). Do **not** copy the file to a sandbox —
      it resolves `DEPLOY_SCRIPT` and its siblings relative to its own directory.

## Phase 2 — GREEN: invert the default

- [x] **2.1a** `create_base_mocks:699` → install the mock **unless**
      `MOCK_SLEEP_REAL=1`. Keep the `if [[ … ]]; then … fi` form. **Never** a
      bare `[[ … ]] && cmd` statement — under `set -euo pipefail` a false
      condition aborts the entire suite.
- [x] **2.1b** Confirm no runner subshell's `unset` list clears `MOCK_SLEEP_REAL`
      (`grep -n 'unset ' ci-deploy.test.sh`).
- [x] **2.2a** Rewrite the comment at `:673-675` as an **ADR-139-shaped tripwire**:
      the inverted contract, the opt-out, and the two properties the safety now
      rests on — `create_mock_seq` is the sole loop brake, and the mock shadows
      only a **bare** `sleep`. Do not paste a sibling regex literal near a count
      guard.
- [x] **2.2b** Drop `MOCK_SLEEP_NOOP` from `:3946`, `:3951`, `:3966`.
- [x] **2.2c** Update `workspaces-luks-harness.sh:308-314` — it describes the
      idiom as "an opt-in gate", which this PR falsifies. Update the
      cross-reference only; **do not unify the two mechanisms** (that comment is
      correct that they are different).
- [x] **2.3a** **Behavioural-equivalence gate.** Full run, then
      `diff <(grep -o 'PASS: .*' before.txt | sort) <(grep -o 'PASS: .*' after.txt | sort)`
      → must be empty, and `=== Results: ===` must read `184/184` (AC2).
- [x] **2.3b** **Stability gate.** Repeat the full run 5×, at least one under
      artificial CPU load; all five PASS name-sets must be identical (AC2b).
      This is the only detector for a real `sleep` that was acting as an
      undeclared synchronization barrier — that failure is intermittent and
      invisible to a single run.
- [x] **2.3c** Record the after wall clock + the CPU floor (`user + sys`) for AC1;
      confirm no single test block exceeds 60 s.
- [x] **2.3d** Hot-spin probe (T7): arm a large `MOCK_CRON_INFLIGHT_FILE` countdown
      with the default `CRON_DRAIN_TIMEOUT` and confirm the invocation cap aborts
      in seconds with a named cause rather than hanging.

## Phase 3 — Return the budget against real CI numbers

- [x] **3.1a** Push Phases 0-2 with `timeout-minutes` **unchanged at 12**.
- [x] **3.1b** Let CI run, then `gh run rerun` — a **second observation is
      mandatory**, not "if available". `n=1` is not a ceiling policy.
- [x] **3.2** Read job + step seconds from the API (never a dashboard) for both
      runs; take the max:
      ```
      gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs \
        --jq '.jobs[] | select(.name=="deploy-script-tests")
              | {conclusion,
                 job_secs: ((.completed_at|fromdate) - (.started_at|fromdate)),
                 steps: [.steps[] | {name, secs: ((.completed_at|fromdate) - (.started_at|fromdate))}]
                        | sort_by(-.secs) | .[0:5]}'
      ```
- [x] **3.3a** Set `timeout-minutes` per the rule: **8** if max job seconds ≤ ~240 s
      (ceiling ≈ 2× observed); **10** if max lands 240-360 s — and say which and
      why. Replace `:296-306` with a comment naming measured step seconds,
      measured job seconds, and the run IDs.
- [x] **3.3b** **Delete** the stale note at `:604-608`. Verify with
      `grep -c 'of slack under timeout-minutes' .github/workflows/infra-validation.yml`
      → `0`. Do **not** use the pattern `~12s of slack`: that phrase is split
      across `:607`/`:608` and can never match a line-oriented grep, while its
      only single-line occurrence sits inside the block 3.3a replaces anyway.
- [x] **3.3c** Push, and require a **green `deploy-script-tests` run at the new
      ceiling** with `job_secs ≤ 0.5 × ceiling` before ship (AC7). A YAML grep
      alone cannot show the ceiling holds.

## Phase 4 — Ship

- [ ] **4.1** Verify every AC (AC1, AC2, AC2b, AC3, AC4, AC5, AC6, AC7). For
      absence assertions use `grep -c`, never `git grep -c` — the latter prints
      nothing and exits 1 on zero matches, so it cannot express "returns 0".
- [ ] **4.2** `/soleur:ship`. Use `Closes #6665` in the PR **body**, not the title.
- [ ] **4.3** PR body carries: the before/after + CPU-floor table, the loop-exit
      classification, the mutation output, and the 5-run stability result.
- [ ] **4.4** `ship` Phase 6 renders
      [`decision-challenges.md`](./decision-challenges.md) (DC-1..DC-4) into the
      PR body and files it as an `action-required` issue.
