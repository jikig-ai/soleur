# Tasks — close four fail-open gates (#7629, #7572, #7574, #7613)

Plan: `knowledge-base/project/plans/2026-08-20-fix-close-four-fail-open-gates-plan.md`
Branch: `feat-one-shot-7629-7572-7574-7613-failopen-gates`
Lane: `cross-domain` (spec lacks a valid `lane:` — TR2 fail-closed)
Brand-survival threshold: `single-user incident` → `requires_cpo_signoff: true`,
`user-impact-reviewer` at review time.

**Ordering is load-bearing.** Contract changes precede consumers, and every RED task is its own
commit — asserted from git history (tasks 1.7, 6.1), never from a pasted transcript.

---

## Phase 0 — Preconditions (no code)

- [ ] 0.1 Confirm `python3 -c 'import yaml'` locally; note the CI runner's version.
- [ ] 0.2 Run `scripts/lint-shell-capture-exit.py` and `scripts/lint-workflow-errexit-capture.py`
      explicitly against both `skill-security-scan-*.yml` files; record verdicts. Expected:
      neither fires today; Phase 2.2 creates the latter's trigger.
- [ ] 0.3 Measure and record the wall-clock of one full
      `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`.
- [ ] 0.4 Record the suite's terminal line; confirm the absolute floor stanza is `total < 49`.
- [ ] 0.5 Confirm `scripts/lint-orphan-test-suites.sh` passes.
- [ ] 0.6 Identify the `TEST_GROUP` block in `scripts/test-all.sh` that CI's `scripts` shard
      runs, so tasks 1.7 and 6.6 register into it.
- [ ] 0.7 **Stripper spike.** Render + extract both artifacts; re-verify 0 `#` in
      `luks-stage.sh`, 1 in `runcmd-all.sh`, zero at-risk tokens. Run the three candidate strip
      shapes against the synthesized fixture; only `[[:space:]]+#([[:space:]].*)?$` may preserve
      all of them. `bash -n` both artifacts before and after. **If the measurement is
      contradicted, drop task 5.1 and close #7613 on the anchoring alone.**

## Phase 1 — #7629 RED (harness only; no workflow edits in this commit)

- [ ] 1.1 Create `scripts/skill-security-scan-step-body.test.sh`; copy the extraction shape from
      `scripts/follow-through-closure-guard.test.sh` (`python3` + `yaml.safe_load`, select by
      step `name`, assert exactly one hit, write body to file, run under `bash -e`).
- [ ] 1.2 Ship the extraction/dispatch guard **first**: the shape predicate (*invokes
      `run-scan.sh`, `parse-override.sh`, or `git diff --diff-filter=A`*), the four in-scope
      bodies, the written-down exclusion set (`Assert jq present` ×2, with its reason), and an
      assertion floor that does **not** route through the suite's own `fail()`.
- [ ] 1.3 Build fixture scaffolding. **Every fixture CWD carries stubs for both `run-scan.sh`
      and `parse-override.sh`, plus `jq` on PATH** — without the `parse-override.sh` stub the
      scan body aborts at its first assignment and a RED fixture passes for the wrong reason.
- [ ] 1.4 Add RED fixtures: 1a (`BASE_SHA=000…000`, expect non-zero + `::error::` naming the
      pair); 1b (stub scanner writes a traceback to stderr, exit 1 — expect non-zero + the
      traceback present); 1c (stub first line `usage: run-scan.sh [file]`, exit 0 — expect
      non-zero + the output names the rejected verdict token); 1d (`no_new_skills=false`, every
      path unreadable — expect non-zero); 1e (postmerge, unresolvable `HEAD^1` — expect
      non-zero).
- [ ] 1.5 Add must-PASS fixtures: 1f (`merge_group` base/head shape); 1g (verdict `REVIEW`;
      `HIGH-RISK` + matching override; scanner emitting leading noise before a valid verdict;
      reformatted-but-equivalent body).
- [ ] 1.6 **Run it against unmodified workflows.** 1a–1e must fail; 1f/1g must pass.
- [ ] 1.7 Register with `run_suite "scripts/skill-security-scan-step-body" bash
      scripts/skill-security-scan-step-body.test.sh` inside the `scripts` `TEST_GROUP`; confirm
      `scripts/lint-orphan-test-suites.sh` passes. **Commit — harness only.**

## Phase 2 — #7629 GREEN

- [ ] 2.1 pr-trailer diff step: separate `git diff` from `grep`; keep the `grep`'s `|| true`
      verbatim; keep the assignment at top level (`local x=$(cmd)` masks the status).
- [ ] 2.2 pr-trailer scan step: capture output to a variable/file then take the first line
      (**no `head -1` in a status-read pipeline**); capture stderr; capture exit status via
      `set +e` / `|| rc=$?`; accept only `HIGH-RISK`/`REVIEW`/`LOW-RISK`; emit captured stderr in
      the `::error::`; stop discarding `parse-override.sh` stderr; add the **scanned-count ==
      added-count** assertion; keep `SKILL_SECURITY_SCAN_OFFLINE=1`.
- [ ] 2.3 postmerge: apply 2.1 + 2.2 to its single audit body; fix
      `parent=$(git rev-parse HEAD^1 2>/dev/null || git rev-parse HEAD)`; fix
      `gh issue create … || true`.
- [ ] 2.4 `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh`: correct the header's
      exit-code contract.
- [ ] 2.5 Re-run the Phase 1 suite: all RED fixtures now pass, all must-PASS rows still pass.
- [ ] 2.6 Verify the job name `skill-security-scan PR gate` is unchanged.

## Phase 3 — #7572: the S1 arm

- [ ] 3.1 **RED.** Extract a pure classifier over
      `(container_rc, marker_seen, fixture_marker_seen, primary_reached)` returning
      `ran | fixture-defect | harness-defect | did-not-run`, porting T5's four-rung ladder and an
      `_S1_ENV_RCS` allowlist. Add negative controls in the R3(2c) in-file shape; run them; they
      fail today. **Commit.**
- [ ] 3.2 **GREEN.** Emit the in-container execution marker in the `sshd-drive.sh` heredoc
      (above the stage call, below the fixture guard); add the structural guard on the **mounted**
      artifact; capture the container rc in `_s1_run()`; route the five container-dependent
      assertions through the classifier; leave the two container-independent ones unconditional.
- [ ] 3.3 Implement the skip decision tree exactly as the plan states, including: **when the
      mutation did not land, do not also call `arm_skip … 3`** (the existing branch already emits
      3 substitute `fail`s; calling both totals 10).
- [ ] 3.4 Assert `passes + fails + SKIPPED_ASSERTIONS == 7` for S1 **and**
      `SKIPPED_ASSERTIONS_S1 <= 5`, snapshotting the global counters before the assertion reads
      them.
- [ ] 3.5 Skip message carries rc, its `_S1_ENV_RCS` classification, marker seen, healthy-run
      marker seen, stdout tail.
- [ ] 3.6 Raise `_SKIP_CEILING` to the literal `5` with an itemised stanza
      (`T5 mutation 2; S1 healthy 2; S1 mutation 3`); add a call-site-count assertion. **Do not
      derive the ceiling.**
- [ ] 3.7 Assert T5's primary arm is not skip-eligible (the composite bound now rests on it).
- [ ] 3.8 One full end-to-end suite run; reconcile the terminal line against 0.4.

## Phase 4 — ADR amendments (after 0.7, before 5.1)

- [ ] 4.1 Amend `ADR-152`: add the `.code.sh` row to its #7278 rule table; scope the
      *"does not touch mid-line or trailing `#`"* sentence to the render.
- [ ] 4.2 Amend `ADR-188`: the raised ceiling + call-site assertion; why full derivation stays
      rejected (AP-023); S1's lost primary-fails bound and where the composite bound now lives.
- [ ] 4.3 Confirm no new ADR ordinal is claimed.

## Phase 5 — #7613: eight arms, anchored

- [ ] 5.1 **(Contingent on 0.7)** Change both `.code.sh` extraction sites to
      `[[:space:]]+#([[:space:]].*)?$`, **blanking the tail in place, never deleting the line**.
      Ship the live assertions, the synthesized fixture, and the `_b2_strip` byte-parity
      assertion. Record in the file's own comment that this is prophylactic.
- [ ] 5.2 **RED then GREEN, per arm — `luks-stage.code.sh`.** Fixture A: seed relocated below
      `trap luks_err EXIT`, trailing comment naming the token above it. Anchor the call site
      `_r3_ln 'GIT_DATA_LUKS_DETAIL='` and the first-append pattern; keep each call site's
      `[ -n … ]` test.
      - [ ] 5.2a **R3(1)** fails on A before, passes on the unmodified stage after.
      - [ ] 5.2b **R3(2)** fails on A (ordering by line number, not co-presence).
      - [ ] 5.2c **R3(2b)** fails on A.
      - [ ] 5.2d **R3(2c)** — anchor its two inline `grep -n 'GIT_DATA_LUKS_DETAIL='` calls;
            fixture A′ (control's greps left bare) must drive it RED.
- [ ] 5.3 **RED then GREEN, per arm — `runcmd-all.code.sh`.** Reject a `gpat` match whose
      line-prefix contains `#`.
      - [ ] 5.3a **R3(3b)(ii)** — fixture B (one real `[ -s "$_luks_detail" ]` deleted, trailing
            comment naming it left) must report `UNGUARDED` and FAIL.
      - [ ] 5.3b **R3(3b)(i)** — replace the `-ge 6` floor with a **set** comparison keyed on
            `window|arg4`; fixture C (one site deleted, one unrelated added) must FAIL naming
            both members; add a parity assertion so the fatal-message subset is not pinned both
            here and in sub-assertion (iv); keep vacuity in the failure message.
      - [ ] 5.3c **R3(3c)** — fixture B′ (pattern occurs only in a trailing comment); the
            mutation must land on real code and its `cmp -s` did-not-land guard must still fire.
      - [ ] 5.3d **R3(3d)** — fixture B (a trailing comment matching the deletion `sed`'s shape);
            the deletion must remove the real guard and the arm must still flip.
      - [ ] 5.3e **R3(2d)** — fixture D: mutate `_r2d_ordered`'s own anchor and confirm it
            reddens; its behaviour must otherwise be unchanged.
- [ ] 5.4 Must-not-change controls: assert unchanged verdicts for **every** raw-artifact reader —
      B2 (via `_b2_strip`) and S1's `_s1_stage_ln` / `_s1_sete_ln`. Note in the file that after
      5.1 B2 is a redundant-implementation cross-check, not independent evidence.
- [ ] 5.5 Re-derive the absolute floor and the extraction-failure cardinality-parity `fail`
      counts; re-record the terminal line against 0.4.
- [ ] 5.6 Integration proof: one full suite run RED before 5.1, one GREEN after 5.3.

## Phase 6 — #7574: repair, enumerate, re-home

- [ ] 6.1 **RED.** Create `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` with a
      fake `gh` serving fixture logs: (a) terminal + T5 skip → 1; (b) terminal + S1 skip → 1;
      (c) terminal, no skip → 0; (d) terminal + `infra-config-apply.test.sh`'s
      `SKIP (loud): not root…` and no rehearsal skip → **0**; (e) no terminal line → 2;
      (f) `gh` unavailable → 2; (g) zero successful runs → 2. Run it — (a), (b), (c) fail today.
      **Commit — test only.**
- [ ] 6.2 **GREEN.** Replace `printf '%s' "$log" | grep -qF …` with a form that cannot lose a
      match to EPIPE (here-string or captured file); apply the same form to the counting line for
      consistency (note in the comment: `grep -c` reads to EOF and never breaks the pipe).
- [ ] 6.3 Replace `SKIP_MARKER` with the enumerated set `SKIP (loud): T5 `, `SKIP (loud): S1 `;
      make FAIL a per-arm breakdown; leave `SUITE_TERMINAL` untouched; fix the PASS/FAIL
      denominator inconsistency.
- [ ] 6.4 Add an N-consecutive-TRANSIENT escalation.
- [ ] 6.5 Update the script header (it describes a T5-only probe).
- [ ] 6.6 Create `.github/workflows/scheduled-rehearsal-skip-monitor.yml` (daily; opens/updates
      an alert issue on exit 1); retire the `<!-- soleur:followthrough … -->` directive on #7574.
      Header must record why: the sweeper closes on PASS and `closed_precheck` refuses to
      re-litigate, so an enrolled probe retires itself after one run.
- [ ] 6.7 Register the new test with an explicit `run_suite` line in the `scripts` `TEST_GROUP`.

## Phase 7 — Integration

- [ ] 7.1 Full rehearsal-suite run; reconcile the terminal line against 0.4.
- [ ] 7.2 `bash scripts/test-all.sh` for the affected groups, plus
      `scripts/lint-orphan-test-suites.sh` and `scripts/guard-vacuity-floor.test.sh` (which now
      covers **both** new `scripts/` suites).
- [ ] 7.3 Confirm `MAX_DEFERRED=47` has not moved.
- [ ] 7.4 Re-run 0.2's two linters now that 2.2 created the errexit-capture trigger.
- [ ] 7.5 Walk every AC in the plan (AC1–AC38) and record the evidence for each.

## Phase 8 — Deferrals and hand-off

- [ ] 8.1 File the T17/R1 rc-discard + `run_case()` misclassification issue with its event-grep
      re-eval trigger.
- [ ] 8.2 File the cross-run skip residual tracker (labelled `follow-through`), noting that the
      **workflow** is the observer's carrier so closing the tracker cannot retire it.
- [ ] 8.3 Confirm `decision-challenges.md` is committed so `/ship` renders it into the PR body
      and files the `action-required` issue.
- [ ] 8.4 PR body carries `Closes #7629`, `Closes #7572`, `Closes #7574`, `Closes #7613`.
