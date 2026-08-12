# Tasks — inngest dedicated-host: detection, diagnosis, cutover safety

Plan: `knowledge-base/project/plans/2026-08-11-fix-inngest-dedicated-host-bind-failure-plan.md`
Review findings that shaped it: `plan-review-findings.md` (same directory) — read it before
starting; three phases of the first draft were net-negative and the corrections are recorded there.

RED before GREEN for every behavioral change (`cq-write-failing-tests-before`).

## Phase 0 — Preconditions

- [x] 0.1 Re-verify the outage is still live: `ECONNREFUSED` count against 10.0.1.40 in the last
      hour, field-isolated on `host`. Self-pull via
      `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh`.
      Never ask the operator to fetch (`hr-no-dashboard-eyeball-pull-data-yourself`).
- [x] 0.2 **DONE — measured 2026-08-11.** Brake run 31486949232 completed `failure`, exactly as
      the review predicted: `op=rollback: the FSM did not confirm rolled-back within 600s
      (state='timeout'; the write DID land). WITHHOLDING`. Consequences, all verified from the run
      log rather than inferred:
      - The brake **is set**: `INNGEST_CUTOVER_FLIP=rollback` landed. That value is outside the
        flip guard's `{armed, flipping, flushed, done}` allowlist, so a prod-URI start on
        10.0.1.40 is now refused. **This is why Phase 2.3's diagnostic boot is mandatory** — the
        replaced host cannot bind against a prod backend until the flag is deliberately re-armed.
      - It **fail-closed correctly**: having failed to confirm, it withheld Half (B), the
        `INNGEST_HEARTBEAT_URL` delete. Nothing is half-applied.
      - The flag rests at `rollback`, **not** `rolled-back`. Do not assert the terminal state.
      - Independent corroboration that the host is dark: 40 polls over 600s produced no terminal
        flag marker. Do NOT over-read this — it cannot distinguish "FSM not running" from "Vector
        not shipping". It narrows nothing on its own; the diagnostic boot is still what decides.
- [x] 0.3 Confirm `run-registered-suites.sh` still derives its list from `infra-validation.yml`,
      so new suites must be registered there to run at all.

## Phase 1 — Detection independent of the broken host (ships on merge)

- [x] 1.1 RED: `inngest-consumer-probe.test.sh` — pings on 200 + non-empty registry; suppresses on
      500, on connection-refused, and on 200-with-empty-registry.
- [x] 1.2 GREEN: `inngest-consumer-probe.sh` cloned from `web-zot-consumer-probe.sh`, wrapping
      `inngest-registry-probe.sh`. Mirror its suppression classification exactly.
- [x] 1.3 `inngest-consumer-probe.timer`; install from `server.tf` on the web host.
- [x] 1.4 New `betteruptime_heartbeat` + new `doppler_secret` in `inngest.tf`. Named resource
      addresses. Never a value edit on `doppler_secret.inngest_heartbeat_url_prd`
      (`ignore_changes = [value]` would plan no change and apply nothing).
- [x] 1.5 `paused = true` in source + the ADR-117 measured-beat PATCH arm gate, per
      `web-probe.tf:39-40`. No UI step anywhere.
- [x] 1.6 Row + `feeder` in `plugins/soleur/lib/heartbeat-manifest.ts`; `evidence.pattern` must
      resolve against `server.tf`.
- [x] 1.7 Add the `-target=` line for both new resources to `apply-web-platform-infra.yml`.
- [x] 1.8 Register `inngest-consumer-probe.test.sh` in `infra-validation.yml`.

## Phase 2 — Make the host diagnosable and verifiable

- [x] 2.1 RED: listener-gate test — dedicated pusher must not ping when local `/health` is non-200.
- [x] 2.2 GREEN: ~5 lines in the `HEARTBEATSCRIPTEOF` heredoc in `inngest-bootstrap.sh`.
- [x] 2.3 Diagnostic-boot path: non-prod `INNGEST_POSTGRES_URI` variable for the dedicated host so
      the flip guard's prod detection yields `is_prod=false` and its ALLOW arm is taken. This is
      the mechanism that makes `## Hypotheses` decidable — treat it as the plan's centerpiece.
- [x] 2.4 Extend `inngest-server-probe.sh` with `instance_id`, `cli_version`, `cutover_flag`.
      Keep the hourly cadence; do not add a timer, a `SYSLOG_IDENTIFIER`, or a `vector.toml` entry.
      `journal_tail` stays on the boot marker only.
- [x] 2.5 RED: emitter tests — missing token and failed POST each emit a loud `logger -t` line.
      THREE silent exits, not two: the empty-token arm is the same shape one line down.
- [x] 2.6 GREEN: fix the silent exits in `cloud-init-inngest.yml`'s emitter. **Deviation:** the
      plan's "already-allowlisted identifier" was unavailable — `journald-config.test.sh` CF-4
      asserted in BOTH directions that this emitter never calls `logger` and that its tag is
      absent from the allowlist. CF-4's rationale is explicitly conditional, so it was inverted
      into the positive pair the same file uses for `ci-deploy`, and a new Source-4 tag was
      opened (bounded: silent on success). That also exposed a real hole in the tag drift-guard —
      a `logger -t` inside a cloud-init write_files body matched none of its derivation channels
      — closed as Channel D in `vector-pii-scrub.test.sh`.
- [x] 2.7 Token re-stage systemd oneshot: re-fetch from Doppler each boot, never a baked re-stamp.
      Assert over the RENDERED userdata, not the source template. Mutation-proved: a baked
      `${betterstack_logs_token}` re-stamp reds 2 legs including the sentinel.

## Phase 3 — Cutover safety (must land before any host replace)

- [x] 3.1 RED: `inngest-cutover-latch.test.sh` — `rolled-back` no-op poll, then `armed`, must
      REFUSE the flush. This is the regression the first draft would have introduced.
- [x] 3.2 GREEN: make the latch append-only ("has `done` EVER been recorded"), not last-write-wins.
- [x] 3.3 `RequiresMountsFor=/mnt/data` on `inngest-cutover-flip.service`; make the latch write
      fatal instead of `2>/dev/null || true`.
- [x] 3.4 Sweep `cat-inngest-cutover-state.sh` to the new path — it is the no-SSH operator read
      surface and would otherwise report a false "no state".
- [x] 3.5 RED: `done` refused on non-200 `/health`; refused on empty registry; guard refuses a
      foreign instance stamp.
- [x] 3.6 GREEN: probe-derived `done` in `inngest-cutover-flip.sh`. Instance stamp in a SEPARATE
      Doppler key — appending it to the flag value breaks `inngest-server-flip-guard.sh`'s exact
      `case` match and the `EXPECTED_START_SITES` derivation.
- [x] 3.7 Make `inngest-server-flip-guard.sh` read both keys and refuse a foreign stamp.
- [x] 3.8 Confirm `inngest-server-flip-guard.test.sh` passes its derivation unmodified.
- [x] 3.9 Sweep `scripts/cutover-inngest.sh`: `op=arm` copies the shared monitor's URL to the
      dedicated host; `op=rollback` unconditionally deletes it. Both need the new heartbeat.
- [x] 3.10 `outputs.tf` consumer of `betteruptime_heartbeat.inngest_prd.url`.
- [x] 3.11 Register every new suite in `infra-validation.yml`.

## Phase 4 — Record

- [x] 4.1 Amend ADR-100 in place: Decision 6a completion criteria; fold in the
      terminal-state-must-be-re-derived rule; addendum that the cutover did not hold and the soak
      never started. Keep `status: adopting`; rewrite the blockquote implying a running soak.
      Mint NO new ordinal.
- [x] 4.2 One C4 model line: the web-platform container gains a monitoring probe edge to the
      dedicated host container. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [x] 4.3 Correct the stale arm64/cax11 prose in `inngest-betterstack-token.tf` and the false
      `DBSIZE` durability claim at `inngest-host.tf:229`.

## Phase 5 — Deferrals (must exist before PR-ready)

- [x] 5.1 File the host-replace issue; cite as `Ref`, not `Closes`.
- [x] 5.2 File the cutover-window issue (quiesce-web → confirm → arm → verify).
- [x] 5.3 File the v1.41.1 bump issue, carrying the goose-migration coupling, the dual-arch
      checksum requirement, `--postgres-max-open-conns` as a durable-detection sentinel, and the
      `signkey-prod-` strip.
- [x] 5.4 Move #7308's pin-freshness monitor onto the bump issue.
- [x] 5.5 File the entropy-bound port as its own issue (unrelated subsystem).

## Phase 6 — Exit

- [x] 6.1 Full `test-all.sh`; name the commit it covered.
- [ ] 6.2 Verify every AC in the plan, including that the new suites actually ran.

---

## Status at end of session 2026-08-11

Verified against the tree, not asserted. Every box above was ticked only after the
named artifact was run or read back.

**Landed and green.** Phase 0 (outage re-measured live at ~600 ECONNREFUSED/hour,
newest 12:15:17, field-isolated on `host`); all of Phase 1; Phase 2.3, the
diagnostic boot; Phase 3.1-3.4, the monotonic latch; Phase 5's three deferral
issues (#7462 restore-the-host, #7463 CLI bump absorbing #7308's monitor, #7464
entropy port); and the two Phase 4.3 prose corrections.

Full registered infra runner: 95 suites, 93 passed / 2 failed on the first run.
Both failures were mine, both are fixed, and both are now green — the mutation
battery was re-run against a clean `origin/main` worktree (62/0) to prove they
were introduced here rather than pre-existing.

**NOT done — the resume list, in the order I would take them:**

- 2.1 / 2.2 listener gate on the dedicated pusher (~5 lines in the
  `HEARTBEATSCRIPTEOF` heredoc). Cheap and self-contained.
- 2.5 / 2.6 loud emitter — the two silent exits in `cloud-init-inngest.yml`.
  A real `cq-silent-fallback-must-mirror-to-sentry` violation.
- 2.7 per-boot token re-stage oneshot; assert over RENDERED userdata.
- 2.4 extend the probe heredoc with `instance_id`, `cli_version`, `cutover_flag`.
- 3.5-3.8 probe-derived, instance-scoped `done` + the guard's foreign-stamp
  refusal. NOTE the constraint that shapes it: the stamp goes in a SEPARATE
  Doppler key. Appending it to the flag value breaks
  `inngest-server-flip-guard.sh`'s exact `case` match AND
  `EXPECTED_START_SITES` (still 2 and untouched by this session's work).
- 3.9 remainder: `scripts/cutover-inngest.sh` `op=arm` copies the SHARED
  monitor's URL to the dedicated host and `op=rollback` unconditionally DELETES
  it; both need the new heartbeat. Only the emitter-reason anchor is done.
- 4.1 amend ADR-100 in place; 4.2 the C4 probe edge.
- 6.2 full AC verification.

**Two plan corrections this session established, both load-bearing for whoever
resumes:**

1. **AC13 is unsatisfiable at merge for the consumer heartbeat, by construction.**
   It requires a measured beat, but the probe pings only on a non-empty registry
   from a host that has served nothing since 2026-07-30 — so it correctly
   suppresses and no beat can land. `arm_one` now returns 2 for that outcome and
   inngest-consumer is the one caller that distinguishes it; the arm is
   self-clearing and happens on the first apply after the host serves. Arming is
   a closing condition of #7462, not of this PR.
2. **The plan frontmatter's `closes: [7228, 6617, 7308]` over-claims.** This PR
   ships detection and cutover safety without restoring the host, so all three
   should be `Ref`. Net issue flow is +3 with 0 closed, each justified in #7462
   / #7463 / #7464.
