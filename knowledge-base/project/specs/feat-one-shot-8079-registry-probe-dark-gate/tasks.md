# Tasks — fix: route op=registry-probe's non-200 branch through the dark-host gate

Plan: `knowledge-base/project/plans/2026-09-20-fix-registry-probe-dark-gate-plan.md`
Branch: `feat-one-shot-8079-registry-probe-dark-gate`
Issue: #8079
Lane: single-domain (engineering)

> READ THE PLAN'S `## Premise Correction` FIRST. The issue argues from a pre-arm world that ended
> on 2026-09-15 when the cutover completed. `dark` is now the rollback-only branch; `flag_armed`
> under `flag=done` is the branch that will actually fire, and it means production cron scheduling
> may be down.

## 1. Setup and baseline

- [ ] 1.1 Re-confirm live host state: `doppler run -p soleur -c prd_terraform -- bash scripts/inngest-host-state.sh`. Expect `cutover_flag=done`, `server_active=active`, `http_code=200`. If it disagrees, STOP and re-read `## Premise Correction`.
- [ ] 1.2 `bash scripts/test-all.sh --capacity`. On rc=4, do not claim a full gate later.
- [ ] 1.3 Baseline both suites; confirm `cutover-inngest-workflow.test.sh` dispatches exactly `_EXACT_FLOOR` (665).
- [ ] 1.4 Baseline `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` as clean.

## 2. Phase 1 — `_bs_read_remedy` step parameter (D4)

- [ ] 2.1 Read `_bs_read_remedy` and its doc comment before editing.
- [ ] 2.2 Add the leading `<step>` parameter; replace the 8 `2.0 ` prefixes with `$step `.
- [ ] 2.3 Update the doc-comment signature line.
- [ ] 2.4 Update the two `execute)` call sites to pass `"2.0"`.
- [ ] 2.5 Update `mutate_file`'s known-negative `sed` pattern to the new comment text.
- [ ] 2.6 Suite must be green at 665 with NO count change (this is the behaviour-preserving proof).

## 3. Phase 2 — 2.0 text corrections (D9, D8 silent clause)

- [ ] 3.1 Amend `scripts/cutover-inngest.sh:1434` (2.0 `webhook_path`) to key on the `registry_empty=` marker, not the run's colour.
- [ ] 3.2 Amend `:1515` (2.0 `host_serving`) the same way.
- [ ] 3.3 Add the Better Stack ingest/quota clause to 2.0's `silent)` remedy.
- [ ] 3.4 Re-run the suite; both renders pin prefixes only and should stay green.

## 4. Phase 3 — the registry-probe dark arm

- [ ] 4.1 Re-read `scripts/cutover-inngest.sh:821-863` and the 2.0 region.
- [ ] 4.2 Add the region-open marker and the `webhook_path` pre-refusal naming `op=inventory` (D6), before any Better Stack read.
- [ ] 4.3 Add the signature notice + the one plain-line body echo.
- [ ] 4.4 Source the gate lib under an `||` guard.
- [ ] 4.5 `mktemp -d` then IMMEDIATELY `trap 'rm -rf "$RPG_DIR"' EXIT`.
- [ ] 4.6 The two `_bs_query_rows` reads (24h probe / 30m heartbeat), stderr to files, rc into `RPG_PROBE_RC` / `RPG_HB_RC`.
- [ ] 4.7 `: > "$RPG_EMIT"`, then the gate call with `|| RPG_RC=$?`.
- [ ] 4.8 The sentinel-initialised emit-file read loop behind the shape regex.
- [ ] 4.9 `dark)` — rc/token agreement check, then the D2 notice + `ANSWERED:` / `NOT ANSWERED:` warning, NO exit.
- [ ] 4.10 `flag_armed)` — the D8 `done` vs `armed|flipping|flushed` split. The `done` branch must NOT say "the cutover already completed", must not name `op=verify`, and must not name `restart-inngest-server.yml`.
- [ ] 4.11 `host_serving)` and `silent)` per D8.
- [ ] 4.12 `unreadable)` / `fsm_unreadable)` — branch on read rc, call `_bs_read_remedy "registry-probe" …`.
- [ ] 4.13 The remaining tokens, one remedy each; `*)` sanitised and naming the gate as the defect.
- [ ] 4.14 Every non-`dark` arm exits 1; every remedy ends `Do NOT SSH the host.` and obeys D5.
- [ ] 4.15 Region-close marker before the arm's `;;`.
- [ ] 4.16 Confirm the HTTP-200 path is byte-unchanged.

## 5. Phase 4 — suite extension

- [ ] 5.1 Rename `render_2_0` → `render_arm_region` (11 call sites + 3 comment mentions).
- [ ] 5.2 D7 #1 — replace the consumer `-eq 1` with the per-arm census + ≥12-arm dispatch floor.
- [ ] 5.3 D7 #2 — re-aim `#6617 exactly 2 network/tool calls` at INVOCATIONS (strip comments and annotation lines).
- [ ] 5.4 D7 #3 — re-aim `NO retry loop` at loops containing `curl` / `_bs_query_rows`.
- [ ] 5.5 D7 #4 — re-aim `NO flip/quiesce/rearm hook` at the hook-path shape, not the log tag.
- [ ] 5.6 D7 #5 — re-aim the doppler denial at secret WRITES + bare invocations outside `_bs_query_rows`.
- [ ] 5.7 D7 #6 — `FLQ_SITES` 6 → 8, message extended to name the two new sites.
- [ ] 5.8 D10 — three-way token-set parity (exec arm == probe arm == lib).
- [ ] 5.9 Probe-arm static rows: call shape, source guard, token coverage, two reads, mktemp/trap, purity, emit regex, reserved-triple, no-SSH, no-bare-mutating-op, HTTP-200 content pin.
- [ ] 5.10 Probe-region extraction + H3 extraction control.
- [ ] 5.11 Renders: scenarios 1-15 from the plan's `## Test Scenarios`.
- [ ] 5.12 Mutation rows M1.1-M1.4 and M2.1-M2.10; confirm H4's known-negative still reports NOT reddening.
- [ ] 5.13 Run the suite, read `_DISPATCHED` from its own message, set `_EXACT_FLOOR` to exactly that, itemised `665 -> NNN (+k)`. Never increment by guess.

## 6. Phase 5 — runbook and gates

- [ ] 6.1 Runbook edit (a) at ~:1075 (window procedure + the concurrency-group sentence).
- [ ] 6.2 Runbook edit (b) at ~:453 (a green probe without a `registry_empty=` line is the dark verdict).
- [ ] 6.3 Runbook edit (c) at :1657 (widen to the standalone op).
- [ ] 6.4 Optional: fix the `.github/workflows/cutover-inngest.yml:15-16` section pointer.
- [ ] 6.5 Run all gates in plan Phase 5 and record each verbatim, including the four repo-global ratchets BY HAND.
- [ ] 6.6 Confirm every AC1-AC18 is satisfied by a named assertion or render, not by inspection.

## 7. Ship

- [ ] 7.1 Post the plan's `## Premise Correction` to issue #8079 as a comment before merge (plan `## Follow-Through Directives`).
- [ ] 7.2 PR body: `Closes #8079`; state whether a full gate ran or only the diff's suites plus the ratchets.
