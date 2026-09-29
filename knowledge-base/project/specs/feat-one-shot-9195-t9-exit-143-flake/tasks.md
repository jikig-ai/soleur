# Tasks: fix the T9 exit-143 flake in cloud-init-inngest-provision-unit (#9195)

Plan: `knowledge-base/project/plans/2026-09-29-fix-provision-unit-t9-exit-143-flake-plan.md`

Scope: one file — `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`, inside the
`# ---- T9:` block only. The provision script in `cloud-init-inngest.yml` does NOT change.

## Phase 1: Reproduce the flake shape deterministically

- [x] 1.1 Extract the current T9 evidence-capture logic and drive it against a canned log slice
      reproducing the artifact's shape (attempt-1 `emit provision_attempt_failed rc=143.attempt=1.`
      present, attempt-1 `phone provision-attempt-exit-143` absent, `provision-attempt-start
      attempt=2` present) — observe both T9 assertions RED. This is the failing-test-first run.
- [x] 1.2 Re-run the same slice through the NEW matchers as drafted and observe them GREEN with
      `via=emit` before touching the suite body.

## Phase 2: Rework the T9 block

- [x] 2.1 Replace the single-channel `t9_x` capture with the dual-channel, attempt-anchored
      matcher: phone `$3 == "provision-attempt-exit-143" && $4 == "attempt=1"` OR emit
      `$3 == "provision_attempt_failed" && $5 ~ /^rc=143\.attempt=1\./`; record `via=`.
- [x] 2.2 Re-anchor `t9_b` on `phone provision-attempt-start attempt=1`, with last-`bootstrap
      start`-before-`e` as the fallback; keep the `(e - b) <= 15` bound.
- [x] 2.3 Anchor the ordering row on the same attempt-1 exit-evidence row vs the
      `provision-attempt-start attempt=2` row (`e < s` on slice positions).
- [x] 2.4 Widen `poll 40` to `poll 90` for the `attempt=2` wait (parity with T10's bound).
- [x] 2.5 Update both `tb_ok` diagnostics to interpolate `via=` and the observed timestamps; the
      wording must not claim "within 10s of the 5s timeout" when the anchor is the attempt start.

## Phase 3: Negative controls and verification

- [x] 3.1 Guard-matrix rows: run the fixture-level checks — phone-only loss GREEN (row 4),
      emit-only loss GREEN (row 3), both-channels-lost RED (row 5), reorder RED (row 6); where
      practical, the render mutations (TERM trap `exit 1`, deleted `on_exit` trap) via the suite's
      `row` battery.
- [x] 3.2 `bash apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` — full suite
      exits 0 with T9 green (docker required; ~350 s).
- [ ] 3.3 Load check per the SIGPIPE-flake convention: repeated or parallel suite copies under
      load show no T9 miss.
- [ ] 3.4 Confirm AC7: `git diff --name-only origin/main...HEAD` shows the test file as the only
      non-`knowledge-base/` path.
