# Tasks — feat-one-shot-11899-convention-suite-cleanup

Plan: `knowledge-base/project/plans/2026-11-03-chore-convention-suite-cleanup-plan.md`
Issue: #11899 | PR: #11957 | lane: cross-domain (no spec.md — fail-closed default per plan Save-Tasks rule)

## Phase 1 — Meta-guard + groundwork

- [x] 1.1 `scripts/guard-vacuity-floor.test.sh`: delete stale `^PROMOTED_FILES='` sites at :798/:811/:819; hoist grounds comments above live :1104 site; add marker comment (inside `# `) + `grep -cE "^PROMOTED_FILES='" "${BASH_SOURCE[0]}"` == 1 self-pin; add mutation rows (second assignment → RED; deleted assignment → RED; comment-only must-PASS).
- [x] 1.2 Baseline: run all fourteen convention suites + meta-guard locally; record FIRES classification per suite and `MIN_FIRING_SUITES=71` unchanged expectation.

## Phase 2 — Seam + step pins + pre-battery gate

- [x] 2.1 Group A (seam + step pins + fail>0): `bwrap-probe-rollback-alert`, `faithful-canary-sandbox-alert`, `inngest-step-524-alert`, `registry-store-not-luks-alert`, `registry-zot-credential-shape-alert`, `sandbox-alerts`, `workspaces-luks-deadman-fired-alert`
  - [ ] 2.1.1 Fragment set `{MUT_, _SKIP, GUARD, BASH_ENV, SHELLOPTS, BASHOPTS}` absent over `IV_CODE` + `IV_JOB` enclosing-job slice (boundary `^  [a-zA-Z_][a-zA-Z0-9_-]*:`; assert non-empty + run-line-inside) banning `GITHUB_ENV`/`GITHUB_PATH`/`defaults:`; mutation rows: composed `"MUT_""SKIP"`, `GUARD` env, `BASH_ENV`, in-job `GITHUB_ENV` write (RED) + cross-job `GITHUB_ENV` write (must-PASS).
  - [ ] 2.1.2 Step-shape pins ported from ghcr :345-355 (no step `if:`/`continue-on-error:`, job `if:` literal once, no job `continue-on-error:`) + three mutation rows each.
  - [ ] 2.1.3 Pre-battery `fail>0` gate (donor egress-gw :366-370 verbatim) before the battery marker, outside the floor window.
- [x] 2.2 Group B (seam + fail>0 only — step pins already present): `ghcr-blocked-alert`, `web-nic-guard-unpinned-url-alert`, `inngest-cutover-flip-silent-alert`, `registry-clientip-not-rfc1918-alert`, `egress-gw-alert` — same 2.1.1 + 2.1.3 edits.
- [x] 2.3 Group C (no IV seam — fail>0 + SELF only): `inngest-luks-key-probe-alert`, `inngest-luks-wrong-volume-alert` — gate only.
- [x] 2.4 Bump `PRESENCE_ROWS`/`MUT_ROWS`/`MUT_ROWS_RUN` at both write sites (declaration + `mutate_floor_red` `^PRESENCE_ROWS=[0-9]+$` sed anchor) per added row; grep every constant occurrence after each bump.

## Phase 3 — MAIN_PLAN bound + per-file smalls

- [x] 3.1 Six carriers (bwrap :125, fcsb :122, ghcr :137, inngest-cutover :92, sandbox :126, web-nic :125): terminator `rc=\$\?` → `rc=` + terminator-match assertion (count-compare on `tail -1`, never `| grep -q`); mutation rows: `-target=` moved below rc= → RED; rc= deleted → RED; second decoy plan block → must-PASS; `plan_rc=` rename → RED.
- [x] 3.2 `inngest-step-524-alert`: assert `probe_ts` literals (`SOLEUR_CLAUDE_COST`, `claude-cost`, `cost_usd`, `cron:`); extend attr pins to BOTH alerts (periods + name/alert_type/email/escalation, values canon-derived); `//` + `/* */` strip before `re.search`; fold single-element `for`; rewrite stale comments :24/:37.
- [x] 3.3 `web-nic`: extend readability loop to `TF WF EM RB LQ IV` (:92).
- [x] 3.4 `ghcr`: unify `JQ_DIR` (:376) under the single EXIT trap with `MUT_DIR`.
- [x] 3.5 `sandbox-alerts`: `s.count(old) >= 1` (:602) → `== 1`; EMITTER `grep -c '^export function mirrorBashSandboxFailure('` == 1 pin before the awk slice.

## Phase 4 — Cosmetics + documentation

- [x] 4.1 Delete dead `Q = chr(39)` (bwrap, egress-gw, fcsb, ghcr, registry-zot, web-nic, workspaces-luks — `grep -cw Q` == 1 first).
- [x] 4.2 `SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"` in ghcr :430, inngest-cutover :258, key-probe :408, wrong-volume :488, web-nic :316.
- [x] 4.3 `EXPECT_1` → `EXPECT_SQL` in ghcr/web-nic (compare retained); census-vocabulary normalization to donor terms in touched files.
- [x] 4.4 Self-reference caveat comment at each touched suite's floor window (item 8, document-and-keep).
- [x] 4.5 `shellcheck -S warning` clean on every touched file; landmine sweep (no `| grep -q`, no `env -u`, no literal `<<-` in fixture text, `\x24\x24` in unquoted `<<PY`); `grep -F` each `mutate_red` fragment against its `no "…"` message.

## Phase 5 — Verify + ship

- [x] 5.1 Run every touched suite + meta-guard locally; all pass; FIRES classification preserved; `MIN_FIRING_SUITES` still 71.
- [x] 5.2 Rebase onto `origin/main` BEFORE first push/enqueue; measure the `deploy-script-tests` leg runtime; push, wait for `test` check-run on current head (~10-20 min), then enqueue; freeze after enqueue.
