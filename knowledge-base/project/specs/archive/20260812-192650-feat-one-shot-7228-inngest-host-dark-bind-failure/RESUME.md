# Resume prompt — finish the inngest work and recover the host

Paste the block below into a fresh session. Everything above the block is context for a
human deciding whether to run it; everything inside it is what the next agent needs.

The split matters: **Part A is code that finishes the PR. Part B is the operational recovery
that actually brings the scheduler back.** Part B cannot start until Part A merges, because the
replace dispatched in Part B is the operation that disarms the old cutover latch.

---

```
/soleur:work knowledge-base/project/plans/2026-08-11-fix-inngest-dedicated-host-bind-failure-plan.md

Branch: feat-one-shot-7228-inngest-host-dark-bind-failure
Worktree: .worktrees/feat-one-shot-7228-inngest-host-dark-bind-failure/
PR: #7457 (draft, 14 commits). Targets: #7228, #6617, #7308 — all still OPEN.

RESUME, NOT A FRESH START. Read these three first, in this order:
  knowledge-base/project/specs/feat-one-shot-7228-inngest-host-dark-bind-failure/tasks.md
    — the status block at the bottom is the authoritative resume list, and its ticked
      boxes were verified against artifacts one at a time, not bulk-toggled.
  knowledge-base/project/specs/feat-one-shot-7228-inngest-host-dark-bind-failure/plan-review-findings.md
    — three phases of the first draft were net-negative; the corrections are there.
  the plan itself.

Rebase onto origin/main before touching anything (the branch is ~3 commits behind and this
repo's infra suites carry count-pinned floors that sibling PRs shift).

=== PART A — finish the code, then ship ===

Do these in order; each is small and self-contained. RED before GREEN for every behavioural
change. Every new .test.sh MUST be registered in .github/workflows/infra-validation.yml —
run-registered-suites.sh DERIVES its list from that file (:128), so an unregistered suite runs
in no runner at all while reading as coverage.

  2.1/2.2  Listener gate on the dedicated pusher: ~5 lines in the HEARTBEATSCRIPTEOF heredoc
           in inngest-bootstrap.sh so it pings only on a local /health 200. Today a green beat
           means "a systemd timer fired" — that is the whole #7228 defect, and this is the fix
           for the dedicated-host side of it.
  2.5/2.6  The emitter's two silent exits in cloud-init-inngest.yml:
           `[ -r "$tok_file" ] || exit 0` and a curl under `>/dev/null 2>&1`. Both are real
           cq-silent-fallback-must-mirror-to-sentry violations. Make each emit a `logger -t`
           line on an ALREADY-ALLOWLISTED identifier (check vector.toml Source 4 — a tag with
           no allowlist entry never leaves the box).
  2.7      Per-boot token re-stage oneshot. Every write of /run/inngest-bs-logs-token is inside
           `runcmd:` (first boot only) and /run is tmpfs, so after ANY reboot the boot-trace
           channel is permanently and silently dead. Re-FETCH from Doppler each boot, never a
           baked re-stamp. Assert over the RENDERED userdata, not the source template.
  2.4      Add instance_id, cli_version, cutover_flag to the inngest-server-probe heredoc in
           inngest-bootstrap.sh. KEEP the hourly cadence and add NO timer, NO SYSLOG_IDENTIFIER
           and NO vector.toml entry — the existing comment records why 60s was rejected
           (~1,440 rows/day against a ~25k/day quota, the cost #6617b removed).
  3.5-3.8  Probe-derived, instance-scoped `done`. Set `done` only after a bounded-window
           /health 200 AND a non-empty registry; any failure => `aborted` + a loud marker.
  3.9      scripts/cutover-inngest.sh: `op=arm` copies the SHARED monitor's URL to the
           dedicated host and `op=rollback` unconditionally DELETES it. Both need the new
           consumer heartbeat. (Only the emitter-reason anchor is already done.)
  4.1/4.2  Amend ADR-100 IN PLACE — correct Decision 6a, fold in the terminal-state-must-be-
           re-derived rule, add an addendum that the cutover did not hold and the soak never
           started, rewrite the blockquote implying a running soak, keep status: adopting.
           Mint NO new ordinal (167 and 178 were both lost to contention). Then one C4 model
           line: the web-platform container gains a monitoring probe edge to the dedicated
           host container; run c4-code-syntax.test.ts + c4-render.test.ts.
  6.2      Verify every AC by running its LITERAL command, including that the new suites ran.

TRAPS THIS SESSION ALREADY PAID FOR — do not rediscover them:

  * The instance stamp for 3.6 goes in a SEPARATE Doppler key. Appending it to the flag value
    breaks inngest-server-flip-guard.sh's exact `case` match AND the EXPECTED_START_SITES
    derivation in its test (still 2; nothing this session added a start site).
  * Any new emit_state reason must be added to the `--grep '"reason":"..."'` vocabulary in
    scripts/cutover-inngest.sh, or cutover-inngest-workflow.test.sh reds. Keep reasons as
    stable short tokens (`flushall-failed` style) and put variable detail in a sibling
    `logger` line — the parity extractor takes the literal 3rd positional.
  * Any new artifact delivered by an SSH provisioner in server.tf ALSO needs the fresh-boot
    path (local.host_script_files + soleur-host-bootstrap.sh + web-probe-envwrite.sh +
    cloud-init.yml), or web-host-provisioner-parity.test.sh reds — a rebuilt web-2 would come
    up without it. Adding provisioners/artifacts also RATCHETS the anti-vacuity floors in that
    suite (FLOOR_RESOURCES/FLOOR_DESTS/FLOOR_SEEDED are pinned at the EXACT baseline) and the
    count literals in its -mutation sibling. Derive the new numbers from the guard's own
    `[ok] N: swept ...` lines; do not compute them by hand.
  * inngest-consumer-probe.sh SOURCES inngest-registry-probe.sh for the shared GQL query.
    Do not inline a second query — a drift block pins it, and EXECUTING the registry probe
    instead costs ~4,320 journald rows/day at 60s.
  * The FSM test helpers each build their own `env` invocation; a new seam must be added to
    ALL of them (run_flip, run_flip_failing_sysctl, and the inline flag_set-failure case).
  * CWD drifts between Bash calls in this repo. Pin it in every command.
  * scripts/test-all.sh covers apps/web-platform/infra/ only conditionally — read its epilogue.
    The authoritative infra gate is apps/web-platform/infra/run-registered-suites.sh. Run it
    detached (`setsid nohup`) and read the rc FILE, never the completion notification. Sibling
    worktrees run it too: resolve /proc/<pid>/cwd before concluding a RED is yours.

TWO PLAN CORRECTIONS ALREADY ESTABLISHED — carry them into the PR body, do not re-litigate:

  1. AC13 is UNSATISFIABLE at merge for the consumer heartbeat, by construction. It wants a
     measured beat, but the probe pings only on a non-empty registry from a host that has
     served nothing since 2026-07-30, so it correctly suppresses. arm_one returns 2 for that
     outcome, inngest-consumer is the one caller that distinguishes it, and the arm is
     self-clearing on the first apply after the host serves. Arming is a closing condition of
     #7462, not of this PR.
  2. The plan frontmatter's `closes: [7228, 6617, 7308]` OVER-CLAIMS. This PR ships detection
     and cutover safety without restoring the host. Cite all three as `Ref`. Net issue flow is
     +3 with 0 closed: #7462, #7463, #7464, each justified.

Then run /soleur:review, fix findings inline, /soleur:compound, /soleur:ship.

=== PART B — recover the inngest server (only AFTER Part A merges) ===

This is #7462 and it is the part that actually restores dispatch. Work it as a sequence; each
step is the precondition of the next. Do NOT dispatch the replace before Part A is on main —
the replace is what disarms the old latch, and the monotonic latch is what stops it wiping the
preserved AOF volume.

  B0. Re-measure first, never assume. Self-pull, never ask the operator to fetch
      (hr-no-dashboard-eyeball-pull-data-yourself):
        doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
          "SELECT count(*) n, max(dt) newest FROM (SELECT dt, raw FROM remote($BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3)) WHERE dt > now() - INTERVAL 1 HOUR AND raw LIKE '%ECONNREFUSED%' AND raw LIKE '%10.0.1.40%' FORMAT JSONEachRow"
      As of 2026-08-11 12:15 this was ~600 rows/hour. Also confirm the consumer heartbeat is
      still `paused` and that its probe is running on web-1.

  B1. Arm the diagnostic boot IN DOPPLER — an automated step, not an operator handoff:
        doppler secrets set INNGEST_DIAGNOSTIC_BOOT=1 --project soleur-inngest --config prd
      Nothing sets this for you. Without it the replaced host CANNOT bind: the brake is at
      INNGEST_CUTOVER_FLIP=rollback (measured, run 31486949232), which is outside the flip
      guard's {armed, flipping, flushed, done} allowlist, so every prod-URI start is refused.
      The flag rests at `rollback`, NOT `rolled-back` — do not assert the terminal state.

  B2. Dispatch the replace: apply_target=inngest-host-replace. It is the ONLY delivery path to
      10.0.1.40 for cloud-init/bootstrap changes. Confirm the GitHub environment's required-
      reviewer set is NON-EMPTY before dispatching (a zero-reviewer environment auto-approves).

  B3. Read the boot trace. The host should now come up SQLite-only, bind :8288, and ship the
      staged SOLEUR_INNGEST_BOOT_STAGE markers ending in `net-health`, which carries `bind=`,
      `priv8288=` and `nft=` — the whole diagnosis in one row. Field-isolate on `host`: 1,459
      of 1,839 rows naming inngest-server.service belong to the CO-LOCATED web host, so a
      substring query manufactures a false all-clear. Retention is ~3 days, so read it promptly.
      If the trace is EMPTY, do not read that as "healthy" — check the channel is instrumented
      (the 2.7 token re-stage is what keeps it alive across a reboot) before concluding.

  B4. Fix whatever the trace names. Deliberately not pre-written — the hypotheses (nftables,
      routing, application, bootstrap-never-enabled, the doppler /usr/bin symlink) are all
      UNVERIFIED and the 2026-07-30 discriminator was destroyed by retention.

  B5. Cutover window: quiesce-web -> confirm -> arm -> verify. Atomicity is structurally
      unavailable across two disjoint control planes, so accept a GAP, never an overlap —
      starting inngest on 10.0.1.40 while the co-located scheduler still holds the registry
      double-fires every cron in it. Clear INNGEST_DIAGNOSTIC_BOOT before arming; the guard
      will refuse a diagnostic-flagged start against a durable unit, which is the intended
      fail-closed direction but will block you if you forget.

  B6. Confirm the consumer heartbeat armed itself on the first apply after the host serves
      (status transitions paused -> up via the ADR-117 measured-beat gate), then REMOVE the
      arming_pending row for inngest_consumer from plugins/soleur/lib/heartbeat-manifest.ts so
      a still-paused fed monitor alarms for real again.

OPERATOR DECISIONS — settled, do not reopen:
  * The 12 days of failed dispatches are ACCEPTED AS LOST. No replay, backfill or dead-letter
    path is in scope. This is a decision, not an omission.
  * INNGEST_BASE_URL is NOT repointed as an interim restore. Fix the dedicated host properly.
  * Blast radius, corrected: fleet-wide, not inbound-email only (engineering.pr_review_pending
    was among the failures). The 53 registered crons were UNAFFECTED — execution is still
    pinned to web-1 (#7230).
```
