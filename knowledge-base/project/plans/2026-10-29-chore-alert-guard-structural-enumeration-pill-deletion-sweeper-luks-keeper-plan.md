---
title: "chore: four follow-ups - alert-guard structural enumeration, dead pill variant, dispatch-recovery sweeper ruling, LUKS keeper code side"
date: 2026-10-29
slug: alert-guard-structural-enumeration-pill-deletion-sweeper-luks-keeper
branch: feat-one-shot-11388-11211-11212-11265-followups
issue: 11388
closes: [11388, 11212]
type: chore
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
---

# chore: four follow-ups - alert-guard structural enumeration, dead pill variant, dispatch-recovery sweeper ruling, LUKS keeper code side

## Overview

One PR that works through four open follow-up trackers. The operator asked for all four; the CTO agent
ruled on each technical fork (rows in `knowledge-base/project/specs/feat-one-shot-11388-11211-11212-11265-followups/decision-challenges.md`),
and the result is that two trackers close, two stay open with a comment of what remains.

| Tracker | Outcome in this PR | Issue state after merge |
|---|---|---|
| 11388 alert-guard drift guards | New family-wide structural suite over every `logtail_exploration*` block, a minimal edit to the key-probe guard, docs fixes | `Closes #11388` |
| 11212 dead `enqueue_failed` pill variant | Delete the unreachable `queued` state and `enqueue_failed` prop member, add a type-level test, commit a minimal `.pen` of the surviving states | `Closes #11212` (remaining comment items carried to new tracker #11486) |
| 11211 dispatch-recovery sweeper | Sweeper stays DEFERRED (CTO). Ship a notify-only read-only follow-through probe that reports the day the re-evaluation criteria hold | stays open, `Ref #11211` |
| 11265 standalone LUKS keeper + dead-man conversion trigger | Item 1 (keeper trio, STAGED edit) DEFERRED (CTO); item 2 shipped as a notify-only follow-through probe; ADR-282 addendum and runbook | stays open, `Ref #11265` |

Nothing in this PR writes to Hetzner, Doppler, Supabase or Better Stack, applies Terraform, replaces a host,
rotates a key, builds a bundle or promotes a digest. The dead-man Better Stack alert is neither created nor
changed, and no `query_period` above 900 s appears anywhere. No `[ack-destroy]` is added.

## Research Insights

**Premise Validation (Phase 0.6).** All four trackers are OPEN (`gh issue view`). The collision pre-check
reported only this branch's own draft PR 11483 and three `test-all.sh` processes owned by an unrelated
worktree (`feat-one-shot-11181-cf-notification-route`); no open PR names any of the four issues. Cited
files confirmed on this branch: the key-probe guard, `betterstack-logs-alerts.tf`, `acknowledged-pill.tsx`,
`inngest-cutover-flip.sh` (`luks_key_probe_tick`), `cloud-init-inngest.yml` (`STAGED=`), ADR-282 addendum
2026-10-26. ADR corpus: ADR-282 records the standalone keeper as "not built, remains the intended shape at
the next planned host replace"; ADR-218 owns the Better Stack alert-as-code mechanism; no ADR covers the
sweeper. The 900 s ceiling is evidenced in-repo (four 422s, comment above the key-probe alert in
`betterstack-logs-alerts.tf`); the dead-man (`query_period` 2592000) is absent from the tree and the
key-probe guard's negative rows pin that.

**Live read-only evidence gathered at plan time (2026-10-29, no write of any kind).**

- Sentry (`jikigai-eu`, errors dataset, `SENTRY_ISSUE_RO_TOKEN` via `doppler run -p soleur -c prd`): 0 events
  for `feature:spawn-agent op:inngest-enqueue` over 30 d, and 0 over 14 d for `op:inngest-enqueue`,
  `op:inngest-replay-stale`, `op:replay-draft-changed`, `op:messages-archive-no-row`.
- Supabase prod (Management API `database/query`, SELECT aggregates only, `doppler run -p soleur -c
  prd_terraform`): `public.action_sends` holds 0 rows in total (0 unacknowledged, 0 older than 1 h, 0 with a
  draft message, oldest click null).
- Better Stack Telemetry API (GET `/api/v2/alerts`, `BETTERSTACK_API_TOKEN` from `prd_terraform`): the live
  `soleur-inngest-luks-key-probe-fail-prd` reads check 300, query 900, recovery 3600, `push: true`,
  `email: true`, `call/sms/critical_alert: false`, `paused: false`, `aggregation_interval: 900` (the value the
  API snaps to `query_period`; the `.tf` does not set it). 20 alerts live.
- Better Stack ClickHouse archive arm (`scripts/betterstack-query.sh`, SELECT only): a 40-day window returns
  rows back to 2026-09-19, so a 31-day look-back is readable; the source retention is documented as 90 days
  in `betterstack-log-query.md`. The hot window is about 1 h.

**Research Reconciliation - brief and issue text vs codebase.**

| Claim in the brief or issue | Reality on this branch | Plan response |
|---|---|---|
| #11388 "7 uncovered paths" | Confirmed: no override files, no meta-arguments, no `aggregation_interval`, 19 alerts all carry the same 18 attributes plus one `escalation_target` block; `removed{}`/`moved{}` blocks exist in 5 other `*.tf` files but none names a `logtail_` address; the key-probe census `sed` requires `inngest_luks_key_probe_` so `inngest_luks_key_probe2_fail` escapes (verified) | Phase 1; a root-wide removed/moved forbid would be red today, so the forbid is scoped to `logtail_` addresses |
| #11212 "delete ... and their unit-test cases" | No test references `queued`, `enqueue_failed` or imports `derivePillState`; the `enqueue_failed` -> `queued` case was already rewritten to the 503 contract in PR 11208 | Nothing to delete in tests; a new type-level test is the failing-first test |
| #11265 "standalone keeper added to STAGED" | `STAGED` names assets `docker cp`'d out of the bootstrap OCI image, which `cloud-init-inngest.yml` pins by `@sha256`; the image mint and digest promotion are forbidden to this PR | Item 1 deferred (CTO); order recorded on the issue |
| #11265 "convert the dead-man alert to the count-variable form" | The dead-man (`inngest_luks_key_probe_dark`) does not exist; "count-variable form" is defined nowhere in ADR-282 (it is the issue's phrase) | Item 2 ships as a read-only probe; ADR-282 addendum defines the term |
| #11211 re-evaluation criteria | Neither holds (Sentry 0, table empty) | Sweeper deferred; probe self-reports |

**Property List (Phase 0.6b).**

1. A drift in an alert's effective configuration (periods, channels, existence, count of alerts on one
   exploration) turns a guard red regardless of which Terraform construct carries it.
2. A guard suite that is not run, or runs with its failure masked, is visible as a red check.
3. The unacknowledged-send deferral reports itself the day its re-evaluation criteria hold.
4. The pill's type and render surface name only states the system can reach.
5. A probe that goes dark for 30 days is reported without a human remembering; the standalone keeper's
   delivery order is written down where the next planner will find it.

**Cut List (Phase 0.6b).**

- Service-role sweeper cron -> buys a recovery property for a failure with no observed instance; the probe on
  `origin/main`'s follow-through convention covers "self-reports" -> CUT (CTO: defer).
- Sentry issue-alert for the spawn-agent ops -> same property, covered by the probe, and a vendor write by
  merge automation -> CUT (CTO).
- Per-guard edits to all 15 alert guards -> property 1 is bought once by a family-wide enumeration -> CUT.
- Forbid in `apply-web-platform-infra.yml` -> the PR-time suite buys the same property without touching the
  apply path -> CUT (CTO).
- Keeper trio, STAGED edit, bootstrap-image copy lines, `luks_key_probe_tick` deletion -> cannot be delivered
  without an image mint -> CUT (CTO), tracked on #11265.
- Creating or probing the dead-man alert -> owner-authorized act, out of scope by the brief -> CUT.

**Institutional learnings applied** (paths under `knowledge-base/project/learnings/` unless noted):
`2026-10-01-the-guards-i-wrote-to-protect-the-sole-copy-scanned-a-shape-the-attack-did-not-take.md`,
`2026-10-01-an-alert-guard-pinned-the-declaration-and-the-command-text-not-the-consumer.md`,
`2026-09-30-an-absence-pin-over-hcl-must-compare-the-whole-shape-not-the-kinds-i-was-guarding.md`,
`2026-09-29-a-source-census-that-checks-the-arguments-name-not-its-binding-and-a-closed-file-list-both-let-guarded-egress-through.md`,
`2026-09-28-every-guard-was-narrower-than-its-name-and-my-battery-mutated-only-whole-chokepoints.md`,
`2026-07-30-a-known-gap-of-seven-was-a-predicate-and-my-battery-mutated-one-axis.md`,
`2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`,
`workflow-patterns/2026-10-28-a-comment-sweep-that-names-every-site-still-misses-one.md`,
`2026-10-01-a-followthrough-probe-s-earliest-gate-was-also-its-deadline.md`,
`2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md`,
`2026-07-07-immutable-redeploy.md`, ADR-282, ADR-218, ADR-135, ADR-100.

## Open Code-Review Overlap

Open `code-review` issues naming files this plan edits (query run 2026-10-29):

- #11388 (`inngest-luks-key-probe-alert.test.sh`, `betterstack-logs-alerts.tf`, `infra-validation.yml`): **Fold in** - this PR is its resolution; `Closes #11388`.
- #8735 (`infra-validation.yml` notify-main-failure misses cancelled jobs) and #7942 (two `*.mutation.sh` batteries run in no gate; names `scripts/test-all.sh`): **Acknowledge** - different concerns; this PR adds registrations to `scripts/test-all.sh` and edits no part of the notify step or those batteries. Both stay open.
- #10243 (nft comment correction in `cloud-init-inngest.yml`): **Acknowledge** - this PR no longer edits `cloud-init-inngest.yml` (keeper deferred), so there is no overlap to fold.

## Domain Review

**Domains relevant:** Engineering, Product (mechanical UI-surface override only)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Four technical forks ruled 2026-10-29 (see `decision-challenges.md`): sweeper deferred plus a read-only probe, no Sentry alert; the pill deletion records an honest exemption AND commits a minimal `.pen`; the guard family gets one new family-wide suite with a required/optional attribute split and no apply-workflow gate; the keeper trio is deferred because the STAGED edit cannot be delivered without an image mint, `luks_key_probe_tick` stays, and the dead-man conversion trigger ships as a notify-only probe.

### Product/UX Gate

**Tier:** blocking (mechanical: `apps/web-platform/components/dashboard/acknowledged-pill.tsx` matches the `components/**/*.tsx` glob in `ui-surface-terms.md`)
**Decision:** reviewed
**Agents invoked:** soleur:product:design:ux-design-lead
**Skipped specialists:** none. spec-flow-analyzer and CPO were scoped as advisory over a behavior-preserving deletion; see the Findings note.
**Pencil available:** yes

#### Findings

Exemption record (CTO ruling): the change is a behavior-preserving dead-branch deletion in `apps/web-platform/components/dashboard/acknowledged-pill.tsx` with zero rendered-output delta (no consumer passes `enqueue_failed`; the hook narrows `degraded` to `"no_artifact_in_pr_a" | undefined`), so in substance it is not a new or changed UI surface. The gate is mechanical (plan Phase 2.5 override; deepen-plan Phase 4.9 has no waiver path), so it escalated to BLOCKING anyway and the committed wireframe satisfies it: `knowledge-base/product/design/dashboard/acknowledged-pill-states.pen` (about 11.8 KB, Pencil file token stripped, three surviving states `ack` / `pending` / `no_artifact`, plus the removed `queued` variant as a dimmed annotation) with its export `knowledge-base/product/design/dashboard/screenshots/acknowledged-pill-states.png`. The gate's skill files are not edited. Wireframes ready for async review at `knowledge-base/product/design/dashboard/`.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing on any user path. The only runtime-reachable edit is the pill's type narrowing, which `tsc` and a new type-level test pin; every other change is test suites, docs and read-only probes that run in CI. A broken new guard reds CI, never production.
- **If this leaks, the user's data is exposed via:** no new vector. The two probes read aggregates only (counts and a newest-timestamp), print no row content, and use credentials the follow-through sweeper already holds; the `action_sends` read is a `SELECT count` with no identifier in any output stream.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the alert these guards protect carries its own `single-user incident` tier under ADR-282; this PR changes no runtime behavior on that path and only hardens its CI text guards, so the aggregate tier is the honest one for this diff. A disputed choice is a decision challenge.

## Implementation Phases

### Phase 1 - #11388: the family-wide structural suite (tests first)

Write the suite and its mutation matrix BEFORE any production-config change; the suite must be green on the
real tree and each matrix row must red a scratch copy.

1. Create `apps/web-platform/infra/betterstack-alert-structure.test.sh` (bash, `set -uo pipefail`). It sources
   `tests/scripts/lib/hcl-effective-text.sh` from the repo root (the lib's convention: `"$DIR/../../.."`),
   copies `ok()`/`no()`/`assert_fixture_dir()`/instrument self-test from the key-probe guard, and takes a
   `--presence-only` argument that skips the mutation battery (used by the Observability probe below).
2. One chokepoint, `logtail_blocks()`: enumerate every `resource "logtail_exploration"` and
   `resource "logtail_exploration_alert"` header across EVERY `*.tf` in the infra root with
   `strip_comments "$f" | blank_heredocs | grep -E '^resource +"logtail_exploration(_alert)?" +"'`, then extract each block
   as `block_of "$f" "$type" "$name" | blank_heredocs` (brace depth, never an awk range; `block_of` prints heredoc bodies
   unchanged, so the second `blank_heredocs` is what makes `sql_query` text invisible to the meta-argument rows).
   Every row below flows through it; none re-greps raw text.
3. Presence rows, each over the whole enumerated set:
   - **Census floor:** at least 19 alerts and 19 explorations are enumerated (a floor equal to today's count,
     edited with a legitimate removal; kills "0 checked, exit 0").
   - **Failure messages name the offender and the fix.** Every red row prints the alert or file and a one-line
     remedy: unknown key -> "add it to OPTIONAL_ATTRS in this PR"; missing key -> "restore it or edit
     REQUIRED_ATTRS"; floor -> "edit the census floor with the removal"; provider -> "edit the two provider
     constants with the bump"; CI pin -> "restore the plain `bash <path>` step".
   - **Closed attribute set:** top-level keys of each alert block equal `REQUIRED_ATTRS` (the 18 keys: `alert_type`,
     `call`, `check_period`, `confirmation_period`, `critical_alert`, `email`, `exploration_id`,
     `incident_cause`, `metadata`, `name`, `on_missing_data`, `operator`, `paused`, `push`, `query_period`,
     `recovery_period`, `sms`, `value`) plus `OPTIONAL_ATTRS` (empty today); one `escalation_target` block;
     an unknown key fails with "add it to OPTIONAL_ATTRS in this PR"; a missing required key fails. No
     family-wide attribute VALUE pins (the per-alert guards own `push`/`call`).
   - **No meta-arguments:** no `lifecycle`, `count`, `for_each`, `provider`, `depends_on`, `dynamic` as a
     top-level line or nested block inside any enumerated block (the code-only view, so `sql_query` heredoc
     text and comments are invisible).
   - **One alert per exploration, names agree:** each exploration is referenced by exactly one alert
     (`exploration_id = logtail_exploration.<n>.id`), and `<n>` equals the alert's own resource name (kills
     the second-alert-on-the-same-exploration escape, path 7).
   - **No state surgery:** no `removed`, `moved` or `import` block in ANY infra `*.tf` names a
     `logtail_exploration` or `logtail_exploration_alert` address (the five other files' `removed/moved`
     blocks stay legal).
   - **No override files:** reuse `p_b4_no_override_files` for `*override.tf` / `*.tf.json` in the infra root.
   - **Provider tripwire:** the `constraints` line of the `logtail` entry in `.terraform.lock.hcl` equals the
     constraint literal in `main.tf` (`~> 11.2`, read from the lock, not a second constant), and the lock `version`
     (`11.2.0`) equals one constant at the top of the suite; a provider bump edits that constant in the same PR.
     Recorded as a tripwire, not an integrity proof.
   - **CI invocation pin:** every `apps/web-platform/test/infra/*alert*.test.sh` is invoked in
     `.github/workflows/infra-validation.yml` as a plain `bash <path>` step, and that step's block and its job
     carry no `if:`, `continue-on-error:` or `*_GUARD_*` env. Line-based awk over the step block (no PyYAML
     dependency). Scoped to the alert guards so a legitimate `if:` on an unrelated step cannot false-red.
     The new suite's OWN wiring is protected only by the existing registration gate Arm 3b
     (`.github/scripts/test/test-infra-suite-registration.sh`); the suite header says so.
4. Mutation battery (the Guard Contract matrix below): every row copies the tree into a scratch dir, mutates
   the COPY, re-runs the suite against it through `ALERT_STRUCT_{INFRA,WF}` overrides, and requires rc=1
   (rc>=2 is the instrument, not evidence), with an instrument control on the pristine tree first.
5. Register the suite: it lives under `apps/web-platform/infra/`, so the matrix glob
   (`run-registered-suites.sh`) picks it up; add its row with
   `python3 scripts/regenerate-shard-manifest.py --group infra --incremental --write`. No
   `infra-validation.yml` edit is needed (its path filter already covers `apps/*/infra/**`), and the
   existing CODEOWNERS row `/apps/web-platform/infra/` covers the file (CTO: no new row).
6. Edit `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` only: widen the declared-set
   census `sed` stem to `inngest_luks_key_probe[A-Za-z0-9_]*`, add a `mutate_red` row that appends a
   `probe2_fail` exploration+alert pair (RED), add the second `mutate_red` row for the check_period /
   narrowing legs (through `edit(s, FAILAL, "check_period        = 300", ...)`; that line is pinned by the existing
   window row), and add the trailing-comment-after-`{` census row. Counters: `MUT_ROWS` 13 -> 16 (three new
   `mutate_red` rows), `PRESENCE_ROWS` stays 30 unless a presence row is added; measure with an inner `MUT_SKIP=1` run.
7. Docs: reword `betterstack-log-query.md`'s "push once the apply accepts it" as dated history (`push = true`
   in the `.tf` is the source of truth; the apply read-back is the live proof; live read 2026-10-29 confirmed
   `push: true`); document the auto-resolve window (needs at least two consecutive non-`fail_` hourly
   emits) in the runbook and as a `.tf` comment above `inngest_luks_key_probe_fail` in
   `betterstack-logs-alerts.tf`. Comment-only in the `.tf`: no attribute changes, so the merge apply plans no
   diff. Do NOT touch `incident_cause`.

### Phase 2 - #11212: delete the dead pill variant (type-level test first)

1. Create `apps/web-platform/test/components/acknowledged-pill.test.tsx`: a `// @ts-expect-error` placed on the line
   directly above the offending JSX prop line passing `degraded="enqueue_failed"` (in a `.tsx` file tsc reports the
   unused directive on the wrong line otherwise), plus one render assertion that no `data-pill-state="queued"`
   element exists for the three reachable inputs. Before the deletion `tsc --noEmit` fails with an unused
   `@ts-expect-error` (the failing-first signal; vitest alone cannot see it). The behavior of the three surviving
   states is already pinned by `today-card.click.test.tsx` and `leader-loop-status.test.tsx`.
2. Edit `apps/web-platform/components/dashboard/acknowledged-pill.tsx`: remove `"enqueue_failed"` from the
   `degraded` prop type, `"queued"` from `PillState`, the `enqueue_failed` branch and its precedence comment
   in `derivePillState`, and the whole `state === "queued"` render block. Keep `no_artifact`, `pending`, `ack`.
3. No consumer edit (`today-card.tsx` passes `no_artifact_in_pr_a` at most; `leader-loop-status.tsx` passes
   `undefined`; the hook is already narrowed).
4. Commit the wireframe already produced by the design agent
   (`acknowledged-pill-states.pen` and its screenshot).
5. Flag, do not edit: `knowledge-base/legal/article-30-register.md` TOMs row (g)(6) still says the route
   returns 200 with `degraded: "enqueue_failed"`. A legal record: carried to #11486 (comment) for the counsel
   path.

### Phase 3 - #11211: keep the sweeper deferred, ship the self-reporting probe (tests first)

1. Create `scripts/followthroughs/dispatch-recovery-sweeper-11211.test.sh` first (PATH-stub `curl`, no network).
2. Create `scripts/followthroughs/dispatch-recovery-sweeper-11211.sh`. Template: `autovacuum-thrash-6168.sh` for the
   xtrace refusal (exit 78, before any credential is read) and the token-shape check only; its exit vocabulary
   (2 on an unusable token, 0/1 verdicts) is NOT copied. Exit vocabulary per `followthrough-convention.md`, with
   `image-cve-scan-window-9826.sh` (exit 3 for every cannot-establish, 5 for action required) as the template. Explicit
   `if [[ -z "${VAR:-}" ]]` guards, never `${VAR:?}`; credentials passed to curl on a stdin config, never argv:
   - Criterion 1: Sentry org events API (`SENTRY_ACTIONS_RO_TOKEN`), `feature:spawn-agent op:inngest-enqueue`
     since 2026-10-26.
   - Criterion 2: Supabase Management API `database/query` (`SUPABASE_ACCESS_TOKEN`), a read-only `SELECT
     count` over `action_sends` joined to `messages` where `acknowledged_at`, `failure_reason`, `undone_at`
     and `cancellation_requested_at` are all NULL, `messages.status = 'draft'`, `clicked_at` older than 1 h
     with no upper bound, counted in two buckets (under 23 h recoverable, over 23 h aged-out; two `count(*)
     filter` terms in one query, CTO re-confirmed). No `source_ref` parseability filter: the header states that
     the count over-includes `no_artifact_in_pr_a` drafts (an over-count only moves the probe toward ACTION
     REQUIRED, the fail-safe direction for a notify-only probe, and the table has held 0 rows ever).
   - Exit contract (never 0, never 1): 2 NOT YET (the normal daily state); 5 ACTION REQUIRED only when
     criterion 1 holds AND criterion 2 holds in either bucket; 3 CANNOT ESTABLISH on any read, auth or parse
     failure; 78 under xtrace. Output is counts only: no identifier, no timestamp of an individual row.
   - Header states: notify-only contract, that exits 3 and 5 repeat in the daily comment until the directive or
     label is removed (the sweeper has no dedup and aged-out rows never clear), credential posture (the two secrets already wired in
     `scheduled-followthrough-sweeper.yml`, so no workflow edit), the `RETIREMENT:` line (the probe, its suite,
     the `test-all.sh` registration), and why `earliest=` is not a deadline.
3. Register the suite with an explicit `run_suite` line in `scripts/test-all.sh` (the `followthroughs/*.test.sh`
   glob is not in `SUITE_GLOBS`).
4. At ship time (GitHub-only, no repo change): append the unfenced column-0
   `<!-- soleur:followthrough script=scripts/followthroughs/dispatch-recovery-sweeper-11211.sh earliest=2026-10-30T00:00:00Z secrets=SENTRY_ACTIONS_RO_TOKEN,SUPABASE_ACCESS_TOKEN -->`
   directive to the #11211 body, add the `follow-through` label, and comment the evidence (the plan-time
   counts above) and what remains. The issue stays open.

**What the sweeper does per exit code** (`scripts/sweep-followthroughs.sh`, read for this plan): exit 0 closes the
tracker (and is unreachable here by contract), exit 1 comments FAIL and leaves it open (also unreachable), exit 5
comments ACTION REQUIRED and leaves it open (on a closed issue it comments and does not reopen), exits 2 and 3
comment NOT YET / CANNOT ESTABLISH and leave it open, 78 lands in the TRANSIENT bucket. Both probes therefore
cannot close #11211 or #11265, and a permanent exit 3 is visible, not silent. Suite registration consumer: the
probe suites are listed by explicit `run_suite` lines in `scripts/test-all.sh` (quote the neighbouring lines at
work time); the new infra-dir suite is selected by `apps/web-platform/infra/run-registered-suites.sh` and the
`_infra_in_diff` gate in `scripts/test-all.sh`, with its shard row in `suite-shard-legs.tsv`.

### Phase 4 - #11265: dead-man conversion trigger probe, ADR-282 addendum, delivery order (tests first)

1. Create `scripts/followthroughs/inngest-luks-keeper-dark-11265.test.sh` first, then
   `scripts/followthroughs/inngest-luks-keeper-dark-11265.sh`: a notify-only probe that reads Better Stack
   read-only through `scripts/betterstack-query.sh` (`BETTERSTACK_QUERY_*` already wired in the sweeper; same template and exit vocabulary as Phase 3, header states that exits 3
   and 5 repeat daily until the directive or label is removed). It
   counts MEASURED rows only - `token=ok` or `token=fail_*`, never `indeterminate` - with the marker anchored at
   message position 1 (the same anchor the paging SQL uses; a quoting webhook row must not count), over both the
   hot window and the archive arm with a 60-day look-back. Exit 2 when there are no measured rows or the newest is
   under 30 days old; 5 when measured rows exist and the newest is over 30 days old; 3 on any read or parse
   failure; never 0 or 1; 78 under xtrace. Header documents the residual that zero rows after retention
   expiry looks like "never started", and that the probe is inert until the owner's bundle delivery makes the
   first `token=ok` row.
2. Register the suite in `scripts/test-all.sh`. At ship time (GitHub-only): the unfenced directive with
   `earliest=2026-11-29T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD`
   and the `follow-through` label on #11265, plus the comment of what remains (below).
3. ADR-282: append a dated addendum under the 2026-10-26 section (no new ordinal; status stays `accepted`)
   recording the keeper deferral and its digest-pin reason, the required order, the keeper reusing
   `CUTOVER_LUKS_PROBE_STAMP`, the definition of "count-variable form", the above-900 s caveat on the
   dead-man, and the new probe. Also add the dark-probe pointer to the `Key-continuity probe (#9927 item 2)`
   subsection of `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` (keep the
   heading text exactly: the key-probe guard pins it).
4. The #11265 comment (what remains, all owner-authorized or maintenance-window acts): (a) an image-content PR
   adding the keeper trio to the bootstrap image build and its check script; (b) the image mint and pin-bump;
   (c) a STAGED/cloud-init PR (measure user_data headroom with `inngest-userdata-budget.sh` and confirm an
   image-only PR passes the every-asset-in-STAGED test); (d) the next planned `apply_target=inngest-host-replace`
   (a reboot-forcing hcloud_server update, applied only in the maintenance window, no `[ack-destroy]` from
   this PR); (e) deleting `luks_key_probe_tick` only after the keeper's first measured row, by shipping a
   bundle without it; (f) the dead-man create-and-delete probe on a paused throwaway alert. The merge
   leaves `cloud-init-inngest.yml`, the bootstrap image and `inngest-cutover-flip.sh` byte-identical.

### Phase 5 - verify, record, hand off

Run the verification commands under Acceptance Criteria; write `tasks.md`; the PR body carries `Closes #11388`,
`Closes #11212`, `Ref #11211`, `Ref #11265`, `Ref #11486` and writes "PR 11208" style text, never "fix #N".

## Infrastructure (IaC)

No new infrastructure. The only `.tf` touch is a comment above `inngest_luks_key_probe_fail` in
`apps/web-platform/infra/betterstack-logs-alerts.tf`.

### Terraform changes

None beyond the comment. No provider, variable or resource change.

### Apply path

None. The merge-time push apply of `apply-web-platform-infra.yml` reruns its explicit `-target` allowlist
(which contains no `hcloud_server.*`) and plans no diff for a comment-only change. No dispatch, no replace.

### Host fan-out

Not applicable: no `terraform_data` SSH provisioner is touched.

### Distinctness / drift safeguards

The new suite pins the `logtail` provider constraint and lock version as a tripwire. `hcloud_server.inngest`
keeps `user_data` byte-identical (the keeper is deferred), so the pending-drift question the CTO flagged does
not arise in this PR.

### Vendor-tier reality check

Better Stack: read-only GETs only; no create. The 900 s `query_period` ceiling is respected by construction
(nothing here sets a window).

## Observability

```yaml
liveness_signal:
  what: the daily follow-through sweeper comment on trackers 11211 and 11265 (exit vocabulary 2 NOT YET / 3 CANNOT ESTABLISH / 5 ACTION REQUIRED) and the infra-validation matrix leg that runs the new structure suite on every infra PR and push
  cadence: daily (sweeper) and per infra change (suite)
  alert_target: the tracker issue comment (ACTION REQUIRED heading) and a red infra-validation check
  configured_in: scripts/followthroughs/dispatch-recovery-sweeper-11211.sh, scripts/followthroughs/inngest-luks-keeper-dark-11265.sh, apps/web-platform/infra/betterstack-alert-structure.test.sh

error_reporting:
  destination: the sweeper republishes each probe's last 4 KB as an issue comment; the suite prints a [FAIL] ledger and exits non-zero
  fail_loud: exit 3 CANNOT ESTABLISH with the reason on a read, auth or parse failure; the suite's [FATAL] lines and rc 1 on any red row; a probe never exits 0 or 1 so it can neither close nor read as a regression

failure_modes:
  - mode: Sentry or Supabase read fails in the 11211 probe
    detection: exit 3 CANNOT ESTABLISH in the daily sweeper comment
    alert_route: the 11211 tracker comment
  - mode: Better Stack read or 31-day look-back fails in the 11265 probe
    detection: exit 3 CANNOT ESTABLISH in the daily sweeper comment (a permanent 3 is itself the signal that the look-back cannot be read)
    alert_route: the 11265 tracker comment
  - mode: a new alert is added with an extra attribute, a meta-argument, a second alert on one exploration, or a removed/moved/import block
    detection: the structure suite goes red on the PR
    alert_route: red infra-validation check on the PR

logs:
  where: GitHub Actions run logs for the sweeper and for the infra-validation matrix leg
  retention: GitHub Actions default retention (90 days)

discoverability_test:
  command: bash apps/web-platform/infra/betterstack-alert-structure.test.sh --presence-only
  expected_output: passed, 0 failed
```

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-282 with a dated addendum (no new ordinal, status stays `accepted`) as an in-scope task of Phase 4:
the keeper deferral and its reason (a STAGED line naming assets absent from the `@sha256`-pinned bootstrap
image strands the next replace), the required order, the shared-stamp rule for the future keeper, the
definition of "count-variable form" (the last rung of the fallback ladder: a Terraform variable defaulting to
false, flipped by the owner, replacing the data-derived self-arm), the above-900 s caveat, and the new probe.

### C4 views

No C4 impact. All three model files were read (`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`).
Checked against the change: (a) external human actors - none new (the founder and the owner are already
modeled; no correspondent or recipient is added); (b) external systems - Better Stack (`betterstack` system),
Sentry (`sentry` system), GitHub (`github` system, hosts the sweeper workflow), Doppler (`doppler`) and Supabase
(`supabase` database) are all already modeled, and the probes add no new system; (c) containers and data stores
- none touched; (d) actor-to-surface access relationships - unchanged. `plugins/soleur/test/c4-count-parity.test.sh`
was run on this branch before the change and is green ("ALL TESTS PASSED"); it is re-run in the verification
phase because the probes add no workflow or monitor (counts embedded in edge prose do not move).

### Sequencing

The ADR describes the present state (keeper deferred, probe shipped), not a target state.

## Guard Contract

### Guard 1 - betterstack-alert-structure (family-wide)

**Property.** For every `logtail_exploration` and `logtail_exploration_alert` declared anywhere in the infra
root, the effective configuration equals the reviewed text: no override file, meta-argument, extra attribute,
second alert on one exploration, state-surgery block, provider drift or masked CI invocation can change it while
the suite stays green.

**Assembly.** Quantifies over: every `*.tf` in `apps/web-platform/infra/` (not one file), every
`resource "logtail_*"` block in them (enumerated, never named), every `removed`/`moved`/`import` block in any of
those files, the root's `*override.tf` and `*.tf.json` files, the `logtail` constraint in `main.tf` and the
lock-file entry, and every `apps/web-platform/test/infra/*alert*.test.sh` step in `infra-validation.yml`. Single
chokepoint: `logtail_blocks()` (comment- and heredoc-blind enumeration plus brace-depth extraction); every row
reads through it, and a second chokepoint exists only for the workflow rows (the step-block awk), which is
named in the suite header. Members drift; the set is derived each run.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Plant `zz_override.tf` in the scratch infra root | RED |
| 2 | Plant a `*.tf.json` in the scratch infra root | RED |
| 3 | Add `lifecycle { ignore_changes = [query_period] }` to the LAST enumerated alert (not the first: a check that stops at the first member is itself the defect); add `count = 0` to a middle alert | RED each |
| 4 | Add `aggregation_interval = 300` to one alert (unknown key); add a `dynamic "escalation_target"` block to another (sibling-block axis) | RED each |
| 5 | Delete `push` from one alert (missing required key) | RED |
| 6 | Append a second alert (`..._probe2`) whose `exploration_id` points at an existing exploration | RED |
| 7 | Append a `moved {}` block naming a `logtail_exploration_alert` address in a different `*.tf` (`removed {}` and `import {}` go through the same single header matcher in the suite, so the one row exercises it) | RED |
| 8 | Bump the lock `version` for `logtail` | RED |
| 9 | Add `continue-on-error: true` to one alert-guard step; delete another alert-guard step | RED each |
| 10 | Dispatch: point the suite at an infra root with ZERO `logtail_*` blocks | RED (floor), never "0 checked, rc 0" |
| 11 | Must-PASS (rc 0): an attribute-order shuffle; a `# lifecycle` comment; a `sql_query` heredoc containing `count` / `for_each` / `lifecycle`; a `lifecycle {` line inside a heredoc inside an alert; a re-indented alert-guard step; a `moved {}` naming a NON-logtail address | no red |

**Harness rows.** (a) The suite's own `ok()`/`no()` instrument self-test must red if either helper stops moving
its counter. (b) Neuter `strip_comments` to the identity (a function override appended to a scratch copy of the
lib) - the must-PASS comment/heredoc rows must flip RED, proving those rows exercise the lexer. (c) Must-PASS
inputs that are NOT the canonical tree: the attribute-reorder tree, a tree with an extra `moved {}` block naming
a NON-logtail address, a tree where `OPTIONAL_ATTRS` is extended AND an alert uses that attribute. Each outcome is
attributed by rc discrimination (1 = caught; 0 = survived; >=2 = unresolved instrument).

**Anchor.** The stored pins (`REQUIRED_ATTRS`, the census floor, the provider constants) live in the same file
and the same diff as what they protect, so the suite proves consistency, not integrity. The external anchor is
review: `/apps/web-platform/infra/` is a CODEOWNERS row (`@deruelle`) covering the suite (CTO ruled no new row;
branch-protection enforcement of CODEOWNERS is a separate operator-side setting recorded in the CODEOWNERS
header). Accepted limit, written in the suite header: a deliberate in-diff edit of a pin passes.

### Guard 2 - key-probe declared-set census (widened)

**Property.** No resource whose name starts with `inngest_luks_key_probe`, including `inngest_luks_key_probe2_*`
and the bare stem, can exist beside the one declared pair without turning the key-probe guard red.

**Assembly.** The `sed` census over `betterstack-logs-alerts.tf` (the one chokepoint for the declared set), the
`-target=` census over `apply-web-platform-infra.yml`, and the negative dead-man rows; the stem regex is the
shared member of the first and third.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append an exploration+alert pair named `inngest_luks_key_probe2_fail` | RED |
| 2 | Append a pair named `inngest_luks_key_probe` (bare stem) after the compliant first | RED |
| 3 | `check_period = 300` -> `3600` in the paging alert | RED |
| 4 | Dispatch: raise `PRESENCE_ROWS` by 1 (the floor is `pass+fail >= floor`, so only a raise reds; lowering it cannot) | RED (existing floor) |
| 5 | Append the `inngest_luks_key_probe2_fail` header with a trailing comment after the `{` (the census `sed` is anchored on `{$`) | RED |

**Harness rows.** The existing instrument control (pristine inner run must exit 0) stays; a must-PASS row where
the declared set equals the one pair differing only in alert comments.

**Anchor.** Same diff-consistency limit as Guard 1; backed by Guard 1's one-alert-per-exploration and
name-equality rows, an independent second path to the same escape.

### Guard 3 - notify-only probes never close and never read as regression

**Property.** `dispatch-recovery-sweeper-11211.sh` and `inngest-luks-keeper-dark-11265.sh` can exit only 2, 3, 5
or 78 on every path, so the follow-through sweeper can neither close the tracker nor print a regression line.

**Assembly.** Every exit site of each probe (success, each read failure, each parse failure, the xtrace
refusal, an unset or malformed secret, an empty result).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make the criteria-met path `exit 0` | RED |
| 2 | Let a read failure fall through to the implicit exit status of the last command (rc 1 or 0) | RED |
| 3 | Add a SECOND failing source (second stub returning 500 after a compliant first) and require exit 3, not 2 | RED if only the first source is checked |
| 4 | Drop the `*x*` xtrace refusal | RED |
| 5 | Dispatch: stub a reader that returns an empty body (or HTTP 200 with no rows field) and require exit 3 (a probe reading "0 rows" from an empty body is vacuous); this row also covers a curl failure | RED |

**Harness rows.** A must-PASS fixture that is not the canonical: a measured-row timestamp exactly 30 days minus
one second old (exit 2) and plus one second (exit 5); an `indeterminate`-only history (exit 2). Registration of
each suite in `scripts/test-all.sh` is a one-time acceptance grep (no always-run gate covers
`scripts/followthroughs/*.test.sh`, so a suite cannot detect its own missing `run_suite` line).

**Anchor.** The exit vocabulary is registered in `followthrough-convention.md` and consumed by
`scripts/sweep-followthroughs.sh`; a probe cannot weaken the sweeper's mapping from inside its own diff without
also editing that script, which has its own suite.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#11388 (alert-guard drift guards pin literal params but not the effective-config paths; add structural enumeration)" [brief] | Phase 1, Guard 1, Guard 2 | mapped |
| 2 | "#11211 (dispatch-recovery sweeper for unacknowledged action_sends rows)" [brief] | Phase 3 (ruled deferred; probe shipped) | mapped |
| 3 | "#11212 (delete the dead enqueue_failed pill variant in acknowledged-pill.tsx)" [brief] | Phase 2 | mapped |
| 4 | "#11265 (standalone LUKS keeper at the next host replace plus dead-man conversion trigger; code side only)" [brief] | Phase 4 (item 1 deferred by CTO; item 2 probe; ADR addendum) | mapped |
| 5 | "do NOT create or change the dead-man Better Stack alert and do not guess a query_period above 900 s" [brief] | Cut List; Guard 1 never sets a window; Phase 4 | mapped |
| 6 | "If part of an issue needs one of those, ship the code-side part, leave that issue open with a comment saying what remains, and do not use Closes for it in the PR body." [brief] | Phase 3 step 4, Phase 4 step 4, PR body | mapped |
| 7 | "If the CTO rules the sweeper should stay deferred, record that ruling, close nothing for it, comment on the issue with the evidence, and ship only the items that are in scope." [brief] | `decision-challenges.md` rows; Phase 3 | mapped |
| 8 | "do not add [ack-destroy]" [brief] | Phase 4 step 4 (d); no apply-path edit | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `apps/web-platform/infra/betterstack-alert-structure.test.sh` | "add structural enumeration" | asked |
| Edit of `inngest-luks-key-probe-alert.test.sh` | "add structural enumeration" (issue #11388 adjacent advisories: second `mutate_red` row, census stem) | asked |
| `.tf` comment + `betterstack-log-query.md` edits | "Adjacent advisories folded in" [issue #11388] | asked |
| `acknowledged-pill.tsx` deletion | "delete the dead enqueue_failed pill variant in acknowledged-pill.tsx" | asked |
| `acknowledged-pill.test.tsx` | "delete ... and their unit-test cases" [issue #11212] | inferred - justification: no unit-test cases exist, so a failing-first type-level test is what keeps `cq-write-failing-tests-before` and pins the narrowed type against regrowth |
| `acknowledged-pill-states.pen` + png | "do not touch ... deferred" n/a; the mechanical UI-surface gate | inferred - justification: `wg-ui-feature-requires-pen-wireframe` is mechanical for any `components/**/*.tsx` path and the CTO ruled a minimal `.pen`; without it deepen-plan Phase 4.9 halts |
| `dispatch-recovery-sweeper-11211.sh` + suite | "ship only the items that are in scope" | inferred - justification: the CTO ruled the probe is the in-scope self-reporting form of the issue's own "re-evaluation criteria"; without it the deferral rots |
| `inngest-luks-keeper-dark-11265.sh` + suite | "dead-man conversion trigger" | asked |
| ADR-282 addendum + `inngest-luks-cutover-6894.md` pointer | "code side only" | inferred - justification: the keeper deferral and the definition of "count-variable form" are architecture facts a reader of ADR-282 would otherwise be misled about (plan Phase 2.10) |
| `scripts/test-all.sh` registrations | "dead-man conversion trigger" | inferred - justification: `followthroughs/*.test.sh` is not in `SUITE_GLOBS`; an unregistered suite is a claim |
| `apps/web-platform/infra/suite-shard-legs.tsv` row | "add structural enumeration" | inferred - justification: the infra matrix runner manifest records the new suite's shard (regenerated by the script, not hand-edited) |
| New tracker 11486 | "leave that issue open ... saying what remains" | inferred - justification: closing #11212 would orphan its comment items (`wg-when-deferring-a-capability-create-a`); CTO ruled `Closes` only with the carrier filed |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform` (infra suite, key-probe guard, component, test), `scripts` (two probes, `test-all.sh`), `knowledge-base` (ADR, runbooks, design, plan artifacts)
- Planned files: 17 | Estimated changed lines: about 900 (the new suite and its battery are about 450, the two probes with suites about 350, the rest edits)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the estimated-lines figure is over the 800 threshold only because of two test-heavy suites that are independent files; the operator asked for a single PR, the four trackers share no code, and the review cost is dominated by the new suite, which is self-contained.

## Files to Create

- `apps/web-platform/infra/betterstack-alert-structure.test.sh`
- `apps/web-platform/test/components/acknowledged-pill.test.tsx`
- `scripts/followthroughs/dispatch-recovery-sweeper-11211.sh`
- `scripts/followthroughs/dispatch-recovery-sweeper-11211.test.sh`
- `scripts/followthroughs/inngest-luks-keeper-dark-11265.sh`
- `scripts/followthroughs/inngest-luks-keeper-dark-11265.test.sh`
- `knowledge-base/product/design/dashboard/acknowledged-pill-states.pen` (created at plan time)
- `knowledge-base/product/design/dashboard/screenshots/acknowledged-pill-states.png` (created at plan time)
- `knowledge-base/project/specs/feat-one-shot-11388-11211-11212-11265-followups/tasks.md`

## Files to Edit

- `apps/web-platform/components/dashboard/acknowledged-pill.tsx`
- `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh`
- `apps/web-platform/infra/betterstack-logs-alerts.tf` (comment only)
- `apps/web-platform/infra/suite-shard-legs.tsv` (generated row; the regenerated diff must touch only the new suite's row)
- `tests/scripts/lib/hcl-effective-text.sh` (header comment only: add the new suite to its consumer list; the lib is already in the `infra-validation.yml` path filter)
- `scripts/test-all.sh` (two `run_suite` lines)
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md`

Path-glob verification: `apps/web-platform/infra/*.test.sh` matches 100+ real files (the matrix glob);
`apps/web-platform/test/infra/*alert*.test.sh` matches 15 real files; `scripts/followthroughs/*.test.sh`
matches real files; `components/**/*.tsx` matches the pill. Sibling lookup for the key-probe guard: the other
14 alert guards are deliberately NOT edited (CTO), the new suite covers them.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Pre-merge (PR)

- [ ] `bash apps/web-platform/infra/betterstack-alert-structure.test.sh` exits 0 on the real tree with its mutation battery (every RED matrix row rc=1, the must-PASS rows rc=0, the pristine control rc=0), and `... --presence-only` prints a final line containing `passed, 0 failed` in under 15 s.
- [ ] Mutating the last enumerated alert, a middle alert and the first alert each reds the suite (Guard 1 rows 3 to 5); a `moved {}` naming a non-logtail address stays green.
- [ ] `bash apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` exits 0; appending a `probe2_fail` pair makes it exit 1 on a scratch copy.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is green after the pill edit and RED (unused `@ts-expect-error`) when the pill edit is reverted; `./node_modules/.bin/vitest run test/components/acknowledged-pill.test.tsx test/components/today-card.click.test.tsx test/components/dashboard/leader-loop-status.test.tsx` is green (the test path matches the vitest `test/**/*.test.tsx` include glob).
- [ ] The gates' OWN invocations are green, not a hand-listed reconstruction: `bash .github/scripts/test/test-infra-suite-registration.sh` (green; the runner derives the new suite from its `*.test.sh` glob over `apps/web-platform/infra/`), `bash apps/web-platform/infra/run-registered-suites.test.sh`, and `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] `git grep -n "enqueue_failed\|\"queued\"" -- apps/web-platform/components/dashboard/acknowledged-pill.tsx` returns nothing (scoped to the pill file: `chat-input.tsx` carries an unrelated `"queued"` comment).
- [ ] Both probe suites exit 0 and assert exit codes only in {2,3,5,78}; `bash scripts/lint-followthrough-varq-ban.sh` is green; `grep -c "followthroughs/dispatch-recovery-sweeper-11211\|followthroughs/inngest-luks-keeper-dark-11265" scripts/test-all.sh` is 2 (the one-time registration check; the convention is the explicit `run_suite` lines near the `sdk-bash-smoke-verdict-10548` entry).
- [ ] `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-29-chore-alert-guard-structural-enumeration-pill-deletion-sweeper-luks-keeper-plan.md` reports three guard entries with no error.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` is green; ADR-282 carries the new dated addendum with no new ordinal and status `accepted`.
- [ ] `git diff --name-only origin/main...HEAD` shows no change to `apps/web-platform/infra/cloud-init-inngest.yml`, `inngest-cutover-flip.sh`, `inngest-host.tf`, any `.github/workflows/*.yml`, or `.terraform.lock.hcl`; the `.tf` diff is comment-only (`git diff -U0 apps/web-platform/infra/betterstack-logs-alerts.tf | grep '^[+-]' | grep -v '^[+-][+-]' | grep -vE '^[+-][[:space:]]*#'` is empty).
- [ ] `knowledge-base/product/design/dashboard/acknowledged-pill-states.pen` and its screenshot are committed and non-empty.
- [ ] PR body: `Closes #11388`, `Closes #11212`, `Ref #11211`, `Ref #11265`, `Ref #11486`; no `Closes` for 11211 or 11265; ends with the Generated-with line.

### Post-merge (GitHub-only, no infrastructure act)

- [ ] #11211 and #11265 bodies carry the unfenced column-0 follow-through directive and the `follow-through` label; each tracker has the comment of what remains (evidence counts for 11211; items a to f for 11265). A dry run of the sweeper on the branch (`gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true`) shows each probe's `exit=` line as 2 or 3.
- [ ] #11211 and #11265 remain OPEN; #11486 exists and is cited.

## Test Scenarios

- Given the real infra tree, when the structure suite runs, then it reports at least 19 alerts enumerated and `passed, 0 failed`.
- Given an alert block with `lifecycle { ignore_changes = [query_period] }` as the last alert, when the suite runs on the copy, then it exits 1 naming the alert.
- Given a `sql_query` heredoc containing the words `count` and `for_each`, when the suite runs, then it stays green.
- Given a second alert pointing at an existing exploration, when the suite runs, then it exits 1 on the one-alert-per-exploration row.
- Given `degraded="enqueue_failed"` passed to `AcknowledgedPill`, when `tsc --noEmit` runs, then it errors; given the three surviving states, when rendered, then each carries its `data-pill-state`.
- Given Sentry 0 and an empty `action_sends`, when the 11211 probe runs, then exit 2; given a Sentry hit and one aged-out draft row, then exit 5; given a 500 from either source, then exit 3; never 0 or 1.
- Given no measured keeper rows, when the 11265 probe runs, then exit 2; given a measured row 31 days old, then exit 5; given only `indeterminate` rows, then exit 2; given an unreadable archive, then exit 3.

## Success Metrics

The next alert added to `betterstack-logs-alerts.tf` is covered by the structure suite with no guard edit; the
11211 tracker comments ACTION REQUIRED on the first day its criteria hold; the 11265 tracker comments if the
probe ever goes dark for 30 days after its first measured row.

## Dependencies & Risks

- Risk: the structure suite's line-based workflow awk false-reds on a legitimate YAML re-indent. Mitigation: anchor on the `- name:` step boundary and a column-agnostic key match; a must-PASS row re-indents a step.
- Risk: the lexer's behavior on exotic HCL (a `/* */` containing braces). Mitigation: the lib's own rows; the must-PASS comment row here.
- Risk: the 31-day Better Stack look-back becomes unreadable if retention shrinks (free-tier change). Mitigation: exit 3 is permanent and visible; the residual is documented.
- Risk: the 11211 `source_ref` SQL filter drifts from `decideReplay()`. Mitigation: omit-and-document fallback, plus the over-count fail-safe direction.
- Dependency: none on another open PR; the two probes use secrets already wired in the sweeper workflow.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds filler text only, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with a stated threshold.
- Any comment edit inside `cloud-init-inngest.yml` is also a `user_data` edit that forces a host replace: this plan does not touch that file.
- `betterstack-logs-alerts.tf` is in the apply workflow's push paths; keep the edit comment-only or the merge apply plans a live Better Stack update.
- Two `1`-vs-`2` rc discriminations matter in every battery: only rc=1 is a caught mutation.

## References

Issues: 11388, 11211, 11212, 11265, 11486 (new). PRs: 11374, 11208, 11260 (cited predecessors), 11483 (this branch's draft).
Files: see Files to Create / Files to Edit. Decisions: `knowledge-base/project/specs/feat-one-shot-11388-11211-11212-11265-followups/decision-challenges.md`.
