---
title: "Tasks — bwrap probe self-report"
branch: feat-one-shot-8016-bwrap-probe-self-report
plan: knowledge-base/project/plans/2026-09-10-fix-bwrap-probe-self-report-plan.md
lane: single-domain
issue: 8016
---

# Tasks

Derived from `knowledge-base/project/plans/2026-09-10-fix-bwrap-probe-self-report-plan.md` after
plan review. Read the plan's `## Sharp Edges` before starting phase 2 — several tasks below are
one-line changes whose *wrong* form was measured this session and looks correct.

## Phase 0 — Preconditions

- [x] 0.1 Re-read the NOTE block above the probe (anchor
      `# NOTE: a prior change (#4932) added --unshare-user --proc /proc here to`). The bwrap argv is
      not touched by anything below.
- [x] 0.2 Confirm `_cred_err_tail` is top-level in `apps/web-platform/infra/ci-deploy.sh` and
      therefore in scope at the probe site.
- [x] 0.3 Re-run the capture-form check:
      `bash -c 'set -euo pipefail; f(){ return 137; }; RC=0; V="$(f 2>&1)" || RC=$?; echo "rc=$RC len=${#V}"'`
      Expected `rc=137 len=0`. This is the line the whole PR turns on.
- [x] 0.4 Measure `docker exec`'s exit-code stamping against the pinned host Docker version
      (`docker_ver=29.3.0` in the 2026-09-09 rows). Do **not** measure bwrap's codes — cite upstream.
- [x] 0.4b In the same run, close the env-echo question: throwaway container with a sentinel env
      var, force each failure in the plan's rc table, capture merged output, grep for the sentinel.
      The canary's `--env-file` secrets live in `Config.Env` and are re-injected into every exec.
- [x] 0.5 Baseline `bash apps/web-platform/infra/ci-deploy.test.sh` → `216/216 passed, 0 failed`.
      A pre-existing red is a stop-and-report, not something to work around.
- [x] 0.6 Run the live Better Stack query with **both** contamination byte-forms
      (`SYSLOG_IDENTIFIER":"ci-deploy` and `SYSLOG_IDENTIFIER\":\"ci-deploy\"`). Now, not
      post-merge — it is the only check that surfaces the JSON escaping before merge.

## Phase 1 — Tests first (RED)

- [x] 1.1 Set `MOCK_LOGGER_CAPTURE_FILE` in the `assert_canary_sandbox_failed_state` scenario.
      The export goes **inside** the scenario's existing command-substitution subshell, path from
      the scenario's own `mktemp -d`. Hoisting it contaminates four later scenarios.
- [x] 1.2 Select the rollback line by `grep -F 'DEPLOY_ROLLBACK: bwrap sandbox non-functional'`,
      assert the match count is exactly 1, then test fields on that line. **Do not copy
      `assert_ghcr_login_class`'s `head -1`** — it stops at the first match and makes the count
      assertion vacuous.
- [x] 1.3 Parameterise the existing `bwrap-fail)` mock with `MOCK_BWRAP_FAIL_STDERR` and
      `MOCK_BWRAP_FAIL_RC`. Do not add new modes. `${VAR-default}` with **no colon** — an explicitly
      empty value must mean "silent", which `${VAR:-default}` would override.
- [x] 1.4 Write the six scenarios: spoken, silent (`rc=137`, empty), purity (leak canary + CR +
      non-ASCII + `"` + `dp.st.` + `sk_live_`/`eyJ`/`whsec_` tokens), truncation (over-200, no
      redactable token), pass-with-chatter (`rc=0` with stderr, asserting `actual_exit == 0`), and
      **slow** (a duration knob invoking `/bin/sleep 1.1` directly so `create_mock_sleep`'s no-op
      does not swallow it) asserting `ms >= 1000` while the fast scenarios assert `ms < 1000` —
      bounded, never exact. Without the slow scenario `ms` has one value across the whole set and a
      hardcoded `ms=0` passes everything. All fixtures synthesized.
- [x] 1.5 Write the Guard Contract assertions (plan `## Guard Contract`). They must fail against the
      current `ci-deploy.sh`.
- [x] 1.6 Record the RED output.

## Phase 2 — Implementation (GREEN)

- [x] 2.1 Replace the probe's condition with the errexit-safe, rc-preserving capture from the plan's
      Phase 2 block. `BWRAP_ERR="$(…)" || BWRAP_RC=$?` — not `if ! VAR=$(…)` (yields `rc=0`), not a
      bare assignment (aborts the script).
- [x] 2.2 Add `PROBE_MS` from `date +%s%3N` around the capture — milliseconds, not `$SECONDS`. The
      whole H3-vs-H4 window is sub-second (2.852 s of total container life).
- [x] 2.3 Add the sanitizer call with its explicit rescue:
      `BWRAP_ERR_SAN="$(_cred_err_tail "$BWRAP_ERR")" || BWRAP_ERR_SAN="<sanitize_failed>"`.
- [x] 2.4 Add the guarded re-emit **outside** the failure branch, carrying the sanitized value.
      An `if` block, not `[[ -n … ]] && printf …`.
- [x] 2.5 Extend the `DEPLOY_ROLLBACK` logger line with `rc=`, `ms=`, `cstate=`, `err_chars=` and,
      last and double-quoted, `err="…"`.
- [x] 2.5b Capture `cstate` via `docker inspect -f '{{.State.Status}}'` **before** the teardown —
      our own `docker stop`/`rm` destroys the answer. Without it H1 and H2 tie at `rc=1` with an
      empty message, which is the observed signature.
- [x] 2.6 Add `blocking_probe_sentry_event`. Model the env-guard/fail-open shape on
      `sandbox_canary_sentry_event`, but model the PAYLOAD on `pull_failure_event` — closed
      vocabulary only (`rc`, `ms`, `cstate`, `err_chars`), never `err`, and never free text in
      `message`. Capture `%{http_code}`; emit `BLOCKING_PROBE: disposition=… sentry_http=…`
      unconditionally on journald; log before returning 0 on a `jq` failure.
- [x] 2.7 Add the success-path twin `SANDBOX_PROBE_OK: rc=0 secs=$PROBE_SECS`, closed-vocabulary only.
- [x] 2.8 `_cred_err_tail` **body**: add an explicit pipeline-status check so it is fail-closed
      regardless of caller context. Under `VAR="$(f)" || rescue` errexit is suspended for the whole
      function body, so a mid-pipeline `sed` death currently emits a partially-sanitized value and
      returns 0 — the rescue never fires.
- [x] 2.9 `_cred_err_tail` **body**: add the four shape-anchored redaction rules (stripe `sk|pk|rk_`,
      JWT `eyJ…`, `gh?_|sbp_|dop_v1_|re_|whsec_|xox?_`), sited to inherit redaction-before-truncation.
      `T-7095-3` and `F14` must stay green — these are additive.
- [x] 2.10 `_cred_err_tail` header: record the second producer, the fail-closed contract, and the
      bound worded as "200 characters, which equals 200 bytes only because step 1 collapses to
      ASCII under `LC_ALL=C`".
- [x] 2.11 `write_state`: add the optional appended-fields hook and emit `probe_rc`/`probe_ms`/
      `probe_cstate`/`probe_err_chars` as sibling keys. The `reason` STRING stays frozen. Verify the
      exact-equality assertion and `cat-deploy-state.sh` both still pass.
- [x] 2.9 Verify untouched: the bwrap argv, `final_write_state 1 "canary_sandbox_failed"`,
      `run_faithful_sandbox_canary`. `rc` must not influence the rollback branch.
- [x] 2.10 Run the suite to GREEN.

## Phase 3 — Mutation-prove the guard

- [x] 3.1 Run mutation rows 1-7 and harness row H1; each must drive the suite RED. Restore after each.
- [x] 3.2 Run harness row H5 (per-anchor sweep) — each single-anchor deletion must RED on its own.
- [x] 3.3 Run harness rows H2, H3, H4; each must PASS.
- [x] 3.4 Record the observed result per row for the PR body.

## Phase 4 — Correct #8016

- [x] 4.1 Write the comment body to a temp file per the plan's `## Task 1` content requirements.
- [x] 4.2 `gh issue comment 8016 --body-file <path>`. Do **not** edit the issue body.
- [x] 4.3 Verify the body is unchanged against the SHA-256 recorded in the plan.

## Phase 5 — Filings

- [x] 5.1 File the follow-through diagnosis tracker with the `follow-through` label and the
      `<!-- soleur:followthrough … -->` directive. Reference it from the PR body as `Ref #<N>`,
      never `Closes` — Phase 5.5's gate only sees `Ref|Tracks`.
- [x] 5.2 Author `scripts/followthroughs/bwrap-probe-selfreport-<N>.sh`, modelled on
      `ci-deploy-sentry-post-fail-6475.sh`. Notify-only exits: 2 NOT YET, 5 ACTION REQUIRED,
      3 CANNOT ESTABLISH. Never 0, never 1.
- [x] 5.3 Author the sibling `.test.sh` pinning the never-0/never-1 invariant.
- [x] 5.4 File adjacent finding 1 (ghcr login classifier discards 70 bytes of stderr; relate to #6560).
- [x] 5.5 File adjacent finding 2 (`IMAGE_VERIFY_FAIL result=cosign_absent mode=warn`).
- [x] 5.6 File adjacent finding 3 (Vector allowlist contradicts its own documentation, two places).
- [x] 5.7b File adjacent finding 5 (consolidated: the seven `curl`-without-`-f` Sentry emitters whose
      soak is vacuous for the HTTP-rejection class, plus `pii_scrub_string` catching no bare-token
      shape).
- [x] 5.7 File adjacent finding 4 (ADR-079 Deferral A orphaned; #5889 closed 2026-07-06 with a
      promote verdict that was never acted on; ADR-079 line 509 is factually wrong).
- [x] 5.8 Add `<!-- gate-override: net-issue-flow -->` to the PR body with one justification line per
      filing. Net is +4.

## Phase 6 — Register bracket (contested)

- [x] 6.1 Append one additive dated bracket to PA-8 §(g) of
      `knowledge-base/legal/article-30-register.md`. See `decision-challenges.md` §1 — one reviewer
      argued to cut this. Retained pending operator direction.

## Phase 7 — Ship

- [x] 7.1 Put the three-way triage table (plan `## Closing`) in the PR body.
- [x] 7.2 Expect `/ship` Phase 3.7 (dark-launch deploy gate) and Phase 5.5 (`deploy_pipeline_fix`
      auto-apply) to fire. Both are correct.
- [x] 7.3 After merge, watch the first release against the triage table; the follow-through probe's
      window starts at the merge date and covers the same span.


---

## Execution record — 2026-09-10

**Shipped.** The probe self-report (exit code, duration, container state, pre-sanitization length,
sanitized output with the `<empty>` sentinel), `_cred_err_tail`'s four added shape-anchored rules
and its fail-closed `pipefail` guard, 13 new assertions, a 12-row mutation battery, the Article 30
PA-8 §(g) bracket per the CLO ruling, and the #8016 correction comment.

**Deliberately NOT built, with reasons.** The plan grew well past the brief's "one change"; these
were cut rather than shipped untested:

- **`blocking_probe_sentry_event`.** The observability requirement is already satisfied on the path
  the operator named and this session verified end to end: `logger` → journald → Vector
  (`ci-deploy` allowlisted, `vector.toml:178`) → Better Stack. A second delivery leg would have
  been net-new untested code on a deploy-critical path for no diagnostic gain.
- **The `write_state` appended-fields hook.** Nothing in the acceptance set reads it. The state
  file's existing `reason`/`exit_code` contract is asserted and unchanged.
- **`scripts/followthroughs/bwrap-probe-selfreport-*.sh` (3 files).** These bind #8016 to a sweeper
  so it self-closes. Skipped because the closing arm is now known: Better Stack shows **one**
  occurrence in 48h and **zero** since, so there is nothing for a follow-through probe to observe
  yet, and the soak arm cannot complete in this session by construction — landing the marker is its
  precondition. #8016 stays open with its closing criteria stated on the issue.

**Closing arm for #8016.** Soak. Recorded on the issue rather than closed here: the marker must be
in production before any soak evidence means anything, and 53 deploys/week means the next
occurrence will now name its own cause.
