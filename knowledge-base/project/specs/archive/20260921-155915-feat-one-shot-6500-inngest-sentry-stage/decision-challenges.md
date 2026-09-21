# Decision challenges — feat-one-shot-6500-inngest-sentry-stage

These are Taste decisions made headless during planning (plan Step 4.5 and Plan Review). `ship` renders them into the
PR body and files them as an `action-required` issue. Each records a default the plan applied, and the operator can
reverse it.

## T1 — The soak gains a host-pinned `inngest_zot` denominator (tightening beyond the literal ask)

- **Default applied:** `zot-soak-6122.sh` gains an `INNGEST_ZOT` arm (`stage:"inngest_zot" host_name:"soleur-inngest"`).
  A count of 0 FAILs `no-inngest-freshboot-evidence`. After this PR, the soak therefore cannot PASS until an
  `inngest-host-replace` that carries this change runs inside the soak window.
- **Why:** without it, a zero `[freshboot]` count means the dedicated host was *unobserved*, not that it was clean.
  That is the same thesis as #6462's `APP_ZOT` denominator. It is fail-closed only.
- **Alternative:** ship the emitter and the call-site predicate only, and leave the denominator out. The soak would
  then PASS on a window in which the inngest host never booted.

## T2 — The `inngest-host-replace` dispatch does NOT hard-fail on an empty `SENTRY_DSN`

- **Default applied:** an advisory step in the `inngest_host_replace` job ("Warn if SENTRY_DSN is absent (#6500)",
  `continue-on-error: true`, `::warning::` and exit 0 on an empty or unreadable value). At boot an empty DSN is
  surfaced by the emitter's `sentry-emit-FAILED rc=nodsn` Better Stack phone-home, and the soak denominator fails
  closed on it. (The review round briefly made this step a hard fail. Ship reverted that to this default, because
  the job is the documented RECOVERY dispatch after a failed `inngest-volume-recut`.)
- **Why:** `inngest-host-replace` is also the recovery route for a failed LUKS recut. A hard fail there would block an
  emergency recovery over a value the boot does not need.
- **Alternative:** add a non-blocking `::warning::` step (cheap), or a hard fail matching the web-host jobs
  (ADR-128 R1).
