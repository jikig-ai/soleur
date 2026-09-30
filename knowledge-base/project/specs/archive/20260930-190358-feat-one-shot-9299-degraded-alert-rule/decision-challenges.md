# Decision challenges — feat-one-shot-9299-degraded-alert-rule

Taste decisions the headless planning phase made while splitting the degraded stage into its own
Sentry rule (#9299). Recorded under ADR-084 so they can be audited outside this session; `ship`
renders them into the PR body. None changes the operator's stated direction (one new rule
`inngest-provision-degraded`, the existing rule narrowed to `provision_attempt_failed`).

This PR resolves **DC-2** of the archived #9176 record
(`knowledge-base/project/specs/archive/20260930-160430-feat-one-shot-9176-provision-failure-sentry-alert/decision-challenges.md`).
It keeps **DC-1** (the degraded stage pages) in force, now through its own rule.

---

## DC-1 — The narrowed rule uses `match = "eq"`, not a one-member `in` list

**Date:** 2026-09-30
**Classification:** Taste. Both spellings match the same events.
**Status:** open. The default holds unless the operator objects.

The brief said "narrow to `stage in provision_attempt_failed`". The plan writes
`{ key = "stage", match = "eq", value = "provision_attempt_failed" }` on both rules instead:

- Every other single-stage filter in `issue-alerts.tf` uses `eq` (the git-data fatal router, the
  private-NIC and web-terminal rules). `in` appears only where a real list exists.
- A one-member `in` list reads as a list that lost its siblings, which invites re-bundling the
  degraded stage into it. Re-bundling is exactly the defect this PR removes.

Cost: one more changed leaf on the live rule (`match` as well as `value`). The reference gate and
the post-merge projection diff both check it.

**How to reverse:** set `match = "in"` on either rule, and mirror it in `alert-reference.json` and
the op-contract T4b / T4c `toEqual` blocks. The union and partition rows accept either spelling.

---

## DC-2 — The degraded rule carries no `detail nc why=inngest_pull_fatal` row

**Date:** 2026-09-30
**Classification:** Taste (a YAGNI cut backed by a code fact).
**Status:** open. The default holds unless the operator objects.

The `nc` row exists to stop `on_exit`'s `provision_attempt_failed why=inngest_pull_fatal` event
from paging a pull miss a second time; the pull miss already paged through
`zot-mirror-fallback-rate`. The degraded event cannot carry that string: its detail is
`why=$_degraded.attempt=$attempt.iid=$IID`, and `$_degraded` is built only from the literals
`.redis-inactive` and `.no-durable-execstart` (`cloud-init-inngest.yml`, degraded block). A
condition that can never be false for this stage adds nothing and is one more AND-ed row that must
stay in sync. The op-contract test pins the degraded rule at exactly one `tagged_event` row, so
adding the row back is a deliberate, visible edit.

**How to reverse:** add the row to `sentry_alert.inngest_provision_degraded`, mirror it in
`alert-reference.json`, and raise the T2b row count from 1 to 2.

---

## DC-3 — `frequency_minutes = 33` for the degraded rule

**Date:** 2026-09-30
**Classification:** Taste (the value); the constraint that it be unused is mechanical.
**Status:** open. The default holds unless the operator objects.

- The degraded stage is emitted once per boot, so the throttle only matters when two degraded
  events land in one window. A short window keeps a second degraded boot (or a real degraded event
  that follows a forged one from the semi-public DSN) from being suppressed for long.
- 33 is unused on `origin/main` (taken: 5, 10-28, 30, 31, 60-63, 120, 240, 1440-1442) and is also
  not claimed by the open draft #9263, which adds 29 and 32. The op-contract test enforces
  uniqueness across every `.tf` in the root.
- 120 (the failure rule's value) was rejected: it must stay unique, and a 2 h window buys nothing
  for a signal that does not repeat.

**How to reverse:** pick another unused value and update the `.tf`, `alert-reference.json`, and
the T7b row.

---

## DC-4 — Trigger stays `event_frequency_count > 0 / 1h`, not `first_seen_event` / `regression_event`

**Date:** 2026-09-30
**Classification:** Mechanical (recorded for audit because the brief asked about it).
**Status:** decided.

Every web and inngest host boot stage lands in the one perpetually active issue group
`WEB-PLATFORM-4S`. `first_seen_event` fires once per group, ever, so it went inert long ago (the
`git_data_boot_warning` comment in `issue-alerts.tf` records the same finding). `regression_event`
fires only when a resolved group recurs, and that group must never be resolved or muted because it
carries every boot stage. `event_frequency_count` with `value = 0` passes on every event of the hot
group, and the stage filter narrows it to this stage. This is the same trigger the sibling rule
uses.

---

## DC-5 — Remove the rule count from the C4 paging edge instead of bumping it

**Date:** 2026-09-30
**Classification:** User-Challenge. The brief names the bump ("35 of the 37" -> "36 of the 38");
three plan reviewers (DHH, code-simplicity, CTO) recommended removing the number.
**Status:** open. The plan follows the brief and bumps the count.

### The case for removing it

No gate derives the count on the `sentry -> founder` edge in `model.c4`:
`plugins/soleur/test/c4-count-parity.test.sh` pins only the heartbeat and cron counts (rows
C1-C6). Every new alert rule therefore needs a hand edit, and draft #9263 (two more rules) will
change it again. The README counts, which T25 does derive, already carry the number.

### The operator's direction (the default)

Bump the count in this PR, as the brief lists it among the lockstep edits.

### How to switch

Replace "35 of the 37 `sentry_alert` rules in issue-alerts.tf" with wording that names no count
(for example "every `sentry_alert` rule in issue-alerts.tf except the two below"), then run
`bash scripts/regenerate-c4-model.sh`. Alternatively, add a row for the count to
`c4-count-parity.test.sh` so it is derived.

---

## DC-6 — Narrow the live rule in this PR rather than in a purely additive first PR

**Date:** 2026-09-30
**Classification:** Taste (raised by the plan Step 4.5 advisor consult).
**Status:** decided for the brief's direction.

The advisor suggested adding the degraded rule first and narrowing the old rule in a follow-up, so
this merge touches no live rule. The brief asks for both in one PR. The one real risk of the
combined apply (a failed create beside a successful narrowing, leaving the degraded stage paged by
nothing) is closed by `depends_on = [sentry_alert.inngest_provision_degraded]` on the narrowed
rule: Terraform skips the update if the create fails, so the old two-stage rule keeps paging.
