---
title: "verify: web-host-replace does not check the replacement host's FIRST deploy — #8743's defect recurred across two web-2 replacements unnoticed"
type: chore
date: 2026-10-29
slug: verify-web-host-replace-first-deploy
branch: feat-one-shot-10585-first-deploy-verify
issue: 10585
closes: 10585
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# verify: web-host-replace checks the replacement host's FIRST deploy

## Overview

The `web_host_replace` dispatch job in `apply-web-platform-infra.yml` ends at boot-trail verification: once `fresh-host-boot-trail.sh` confirms `fresh_boot_ready`, the host is declared replaced and nothing afterward checks whether its first deploy ever completes. The #8743 fchmodat2 defect (deploy-uid `docker cp` cannot seed a cloud-init-root-seeded uid-1001 plugin mount) recurred on both of web-2's replacements (born 2026-09-25, replaced again 2026-09-30) with no signal — deploy health on a fresh host is exercised only by the next release, and a host that never deploys at all emits nothing any gate reads. This plan enrolls the missing boot→first-deploy arm on the existing follow-through sweeper: a standing watchdog probe that derives the population of recent replaces from the dispatch history and asserts a Deploy-succeeded-class journald row for the replacement host's `host_name` within a bounded window after each replace.

## Research Insights

### Premise Validation (Phase 0.6)

- **#10585** — OPEN, unblocked, `closedByPullRequestsReferences` empty. PR #11500 (`feat-one-shot-10585-first-deploy-verify`) is this pipeline's own auto-created draft, not a foreign change. Collision precheck (`collision-precheck.sh 10585`, exit 10): the only PR hit is #11500 (self); the foreign `test-all.sh` processes are sibling one-shot worktrees running their own suites — reported, unrelated.
- Cited issues **#8743, #8651, #9151** — all CLOSED, cited as precedent/context, not as blockers. Premise holds.
- Source postmortem `knowledge-base/engineering/operations/post-mortems/2026-10-19-web2-plugin-mount-fchmodat2-postmortem.md` Action Items table lists #10585 verbatim as the "replace verifies FIRST deploy" item. Sibling **#10584** (OPEN) already tracks the Better Stack/Sentry *alert* tier for deploy-peer abort signatures — the paging half of this gap, deliberately out of scope here.
- Cited artifacts verified on `origin/main`: `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`, `scripts/followthroughs/web-fresh-boot-zot-8651.sh`, `scripts/followthroughs/web-host-replace-rebirth-6969.sh`, `knowledge-base/engineering/operations/runbooks/web-host-replace.md`, the `/hooks/deploy-status` peers merge (`apps/web-platform/infra/cat-deploy-state.sh` `peers_json`), ADR-148. None stale.
- Mechanism vs ADR corpus: the proposed "enroll a follow-through" route instantiates the established directive/sweeper substrate (ADR-298 family); the alternative "standing alert" route is the ADR-218 `logtail_exploration_alert` pattern. Neither sits in a rejected-alternatives table.

### Mechanism Minimality Gate (Phase 0.6b)

**Property List** — the discrete properties the ask buys:

- P1: after every `web_host_replace`, the replacement host's FIRST deploy outcome is positively verified (not merely "the release run was green" — the host's own deploy succeeded).
- P2: a replacement whose first deploy never lands produces a visible signal inside a bounded window — no silent dark standby (the 09-25 → 09-30 recurrence class).
- P3: the obligation is clock-bounded from the replace, independent of when the next release happens.

**Cut List** — mechanisms considered and cut before design:

- *A verification step inside `web_host_replace`* → P1/P3 — cannot buy them: the job ends minutes after apply while the first deploy lands at the next release, hours-to-days later. A job-local check can only wait or assert blind. **Cut** in favor of the sweeper substrate, which exists precisely for clock-bounded obligations.
- *Per-replace tracker auto-filed by the job* → P1 — cut: the sweeper runs probes under `env -i` forwarding only `secrets=` names + `SOLEUR_FT_EARLIEST`; a probe never learns which issue invoked it, so a per-replace directive cannot carry `host=` parameters, and per-replace probes would need a committed file per event. A self-deriving standing probe buys the same property with zero per-event machinery.
- *A `0/1/2` probe that closes the tracker on the first observed good deploy* → P1 for ONE replace only — cut: the obligation recurs on every replace; a closing probe ends coverage exactly when it first proves itself (and per `CLOSED_LOOKBACK_DAYS=14` it stops being invoked ~14d after close — the 2026-10-15 dormancy trap).

Surviving mechanism: one **standing notify-only watchdog probe** (exit vocabulary `5` ACTION REQUIRED / `2` NOT YET / `3` CANNOT ESTABLISH, never `0`/`1`) on a **standing open tracker**, self-deriving its population — covers every future replace with no per-event enrollment.

### Relevant File Paths

- `.github/workflows/apply-web-platform-infra.yml` — `web_host_replace` job (starts ~L5119); "Validate dispatch inputs" step emits `dispatch validated: replacing var.web_hosts["<key>"]` (resolved key — the population anchor); boot-trail step ~L5500 runs `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`; "Dispatch summary" step (~L5515-5531) is the edit point for the tracker pointer line.
- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` — the existing BOOT verification (the arm this plan does NOT re-do).
- `scripts/followthroughs/web-host-replace-rebirth-6969.sh` — precedent: derives replace verdicts via `gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch` + `gh run view --json jobs` on job name `web_host_replace`; carries the #6995 lesson (job conclusion ≠ boot verdict).
- `scripts/followthroughs/web-fresh-boot-zot-8651.sh` — precedent: `awk -F'\t'` parse of a named step's emitted log lines, ANSI-prefixed echoed `run:` source excluded; refusal under xtrace (exit 78).
- `scripts/followthroughs/web2-plugin-seed-8743.sh` — sibling: Better Stack journald verdict via `scripts/betterstack-query.sh`; `JSONExtractString(raw,'host_name')` host scoping; positive-control + marker + absence conjunction; Deploy-succeeded marker set `Deploy succeeded` / `INNGEST_HEALTH_CHECK` / `BWRAP_USERNS_SYSCTL_` / `PLUGIN_SEED_PROBE`.
- `scripts/betterstack-query.sh` — Better Stack Telemetry transport (hot `remote()` + `s3Cluster` archive union; a real soak span needs both).
- `scripts/sweep-followthroughs.sh` — probe launcher contract: `env -i` PATH/HOME + directive `secrets=` only, `SOLEUR_FT_EARLIEST` forwarded; `CLOSED_LOOKBACK_DAYS=14` — a tracker closed-as-completed keeps being probed only 14 more days.
- `.github/workflows/scheduled-followthrough-sweeper.yml` — `env:` already binds `GH_TOKEN`, `BETTERSTACK_QUERY_HOST`, `BETTERSTACK_QUERY_USERNAME`, `BETTERSTACK_QUERY_PASSWORD` (plus `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_{ID,SECRET}`, `SENTRY_ACTIONS_RO_TOKEN`) — **no new secrets to wire**.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — directive contract (column-0, unfenced, `script=` must start `scripts/followthroughs/`); notify-only reserved codes 2/3/5; `secrets=GH_TOKEN` mandatory for gh-using probes; RETIREMENT header convention.
- `.github/workflows/web-platform-release.yml` ~L1864-2050 — the #10577 `Verify peer deploy completion` step (peers merge + fail-closed release gate). Covers RELEASE runs; leaves the replace→first-release window and the never-fanned-to case unobserved — precisely P2/P3.
- `apps/web-platform/infra/variables.tf` L92-140 — `var.web_hosts` default map; roster authority (key → `private_ip`); `WEB_HOST_PRIVATE_IPS` literals are parity-pinned to it by `apps/web-platform/infra/cutover-inngest-workflow.test.sh`.
- `apps/web-platform/infra/betterstack-logs-alerts.tf` — ADR-218 `logtail_exploration_alert` precedent (the standing-alert alternative tier; #10584's substrate).
- `scripts/lint-followthrough-varq-ban.sh` + `scripts/followthrough-exec-bit.test.sh` + `scripts/followthrough-predicate-parity.test.sh` — the probe-shape lints the new file must satisfy (no `${VAR:?}` exits, exec bit, reserved-code vocabulary).

### Institutional Learnings Applied

- `2026-10-15-dormant-followthrough-probe-is-not-a-standing-detector.md` — a check meant to outlive its tracker must either be an ADR-218 standing alert or keep its tracker OPEN; a closing probe silently stops ~14d post-close. Drives the notify-only standing-tracker shape.
- `2026-10-16-i-rescoped-a-pr-and-its-post-merge-probe-still-waited-for-a-boot-the-pr-no-longer-caused.md` — anchor the population gate on the actual event (the emitted boot line), not the run's conclusion or the PR's intent.
- `2026-10-10-a-log-scraping-probe-matched-the-script-it-echoed-...md` — GitHub echoes `run:` source into logs; anchor on EMITTED lines only. The validation step's emitted line carries the resolved `web-N`; the echoed source carries literal `${WEB_HOST_KEY_RAW}` — a `var\.web_hosts\["web-[0-9]+"\]` anchor on non-ANSI lines separates them.
- `2026-09-25-a-fixture-suite-cannot-see-that-the-probe-can-no-longer-take-its-reading.md` — dry-run the real sweeper on the branch (`gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true`) before shipping probe changes.
- `2026-07-07-followthrough-and-shape-gate-silent-falseness.md` — never gate exits on `: "${VAR:?}"`; use the `[[ -z ]]` + `exit 2/3` form (lint-enforced).
- `2026-10-28-a-probe-that-could-finally-pass-would-have-closed-its-tracker-on-pre-restart-evidence.md` — the marker must postdate the boot it accounts for; per-boot timestamp comparison, not a bare count.
- `2026-10-26-a-closing-probe-counted-rows-where-its-property-said-slots.md` — grade the property (per-host latest-boot → deploy-succeeded join), not row counts.

### External Research

Skipped — internal ops machinery; every mechanism (sweeper, directive, Better Stack query, gh-history population) has a local precedent file cited above. No external API surface involved.

### Related Issues / PRs

- #10585 (this), #8743 + PR #10577 (fchmodat2 root fix + peers-merge release gate), #8651 + #9151 (closed precedents), **#10584 (OPEN — the Better Stack/Sentry alert-tier sibling; deliberately out of scope)**, #6969 + PR #6973 (replace-dispatch origin), ADR-148, ADR-218, ADR-263.

## Problem Statement / Motivation

The `web_host_replace` dispatch's verification surface ends at boot. Once `fresh-host-boot-trail.sh` reports `fresh_boot_ready`, the job is done — and the replacement host's deploy health is never checked again until the next release's peer-verify step (which only covers hosts the release fans out to, and only inside that run's poll window). The #8743 fchmodat2 defect is the measured consequence: it broke web-2's deploys on BOTH of its replacements (born 2026-09-25, re-replaced 2026-09-30) and nobody noticed either time, because a clean-booted host that then fails every deploy emits nothing any gate reads. The release-time `Verify peer deploy completion` step (#10577) closes the failure *at release runs*; the residual arm is the clock-bounded obligation — a replaced host owes a verified first deploy within N days of the replace, whether or not a release has run.

## Proposed Solution

Enroll the boot→first-deploy arm on the existing follow-through sweeper as a **standing notify-only watchdog**: one probe file, one permanently-open tracker, zero per-replace machinery.

### The probe — `scripts/followthroughs/web-first-deploy-10585.sh`

Runs daily under `scheduled-followthrough-sweeper.yml`. Exit vocabulary is the notify-only sub-set: **5** ACTION REQUIRED (a proven-fresh host's first deploy is overdue), **2** NOT YET (the standing quiet state — all accounted or inside the window), **3** CANNOT ESTABLISH (could not measure — credentials, gh, jq, or the Better Stack transport), **78** refused under xtrace with a live credential. It never exits `0` (the tracker must never close — `CLOSED_LOOKBACK_DAYS=14` would retire the check ~14d after any closure) and never exits `1` (a FAIL verdict reads as "should not close" — the reserved meaning, not this shape).

**Step 1 — population (the owed set).** `gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch --created ">=<now-30d>" -L 100 --json databaseId,createdAt,status,conclusion`; for each completed run, `gh run view <id> --json jobs` for `web_host_replace`/`web_host_create` jobs with a real conclusion; for each such job, `gh run view --job <jid> --log` and parse the *emitted* lines of the `Surface fresh-host Sentry breadcrumb trail` step (`awk -F'\t'` on field 2 step-name prefix, field 3 output, ANSI-prefixed echoed `run:` source excluded — the #9905 trap). A host enters the owed set only when the step emitted BOTH `web-host-(replace|create) <key> — fresh-host Sentry pointer` AND `fresh-host boot reached fresh_boot_ready`; a trail emitting `booted DARK`/`did not reach cloud_init_complete` contributes nothing (that failure is already loud — the job itself reds). Per host key keep only the NEWEST proven boot + its timestamp — a re-replace supersedes the earlier obligation (web-2 was replaced twice in five days).

**Step 2 — roster gate.** A key is owed only while it remains in `var.web_hosts`: parse `apps/web-platform/infra/variables.tf`'s default map for the `^[[:space:]]*"?<key>"?[[:space:]]*=[[:space:]]*{` entry (same grep shape the job's membership check uses). A host replaced and then retired owes nothing.

**Step 3 — per-host verdict (Better Stack journald).** For each owed host, `scripts/betterstack-query.sh` (hot + archive union) with `JSONExtractString(raw,'host_name') = 'soleur-<key>'` and `dt >= boot_ts`:

- **Positive control** — count of `ci-deploy`/`webhook`-tagged rows since `boot_ts` (channel aliveness; same predicate family as `web2-plugin-seed-8743.sh`).
- **Marker** — a Deploy-succeeded-class row postdating `boot_ts`: `raw LIKE '%Deploy succeeded%' OR raw LIKE '%INNGEST_HEALTH_CHECK%' OR raw LIKE '%BWRAP_USERNS_SYSCTL_%' OR raw LIKE '%PLUGIN_SEED_PROBE%'` (the same marker set #8743's probe grades — each is reachable only past a completed seed+canary+swap).
- marker present → accounted. Absent and `now < boot_ts + 2d` → pending. Absent and `now >= boot_ts + 2d` → **overdue → ACTION REQUIRED** (comment names host key, boot timestamp, the dispatch run URL, and the control count so the reader can see "host dark" vs "host alive, deploy failing"). Control = 0 past the deadline still reads ACTION REQUIRED — a fresh host emitting nothing to the deploy-side channel IS the incident shape; the verdict is not "no evidence of failure" but "no evidence of a completed deploy".

**Deadline constant:** `FIRST_DEPLOY_DEADLINE_S=172800` (2 days — mirrors the `#8743` `earliest=merge+2d` convention; releases land far more often, so a 48h bound catches a never-deploying standby comfortably ahead of the ~5-day blind spot the incident showed).

### What does NOT change

- The `web_host_replace` job's steps: no new verification step inside the job (it cannot span the boot→first-deploy gap), no `issues: write` on a prod-destroy path, no new secrets anywhere — `GH_TOKEN` + `BETTERSTACK_QUERY_*` are already bound in the sweeper `env:`.
- Two cosmetic discoverability edits only: one line in the job's Dispatch summary naming the standing tracker, and one line in `web-host-replace.md` §"Verify the result".

### Alternative approaches considered

| Approach | Why rejected |
|---|---|
| Verification step inside `web_host_replace` | Cannot span hours-to-days; a job-local check waits or asserts blind (Cut List, Research Insights). |
| Per-replace tracker auto-filed by the job | Probes get no per-issue parameters under `env -i` (only `secrets=` + `SOLEUR_FT_EARLIEST`); would need a committed probe per event + `issues: write` on the replace job. |
| `0/1/2` probe closing on first observed good deploy | Ends coverage exactly when it first proves itself (dormancy, 2026-10-15 learning). |
| ADR-218 `logtail_exploration_alert` (Better Stack standing alert, paging) | The paging tier is already scoped to OPEN sibling **#10584**; this issue's "enroll a follow-through" arm is the GitHub-visible tracker tier. If the breach should page rather than comment, that is #10584's deliverable, not a second mechanism here. |
| `/hooks/deploy-status` `peers["<ip>"].exit_code` grade | Viable (creds already bound) but needs the key→IP join from `variables.tf` plus the `.peers` slot's error-object edge shapes; the journald `host_name` join is the proven template (`web2-plugin-seed-8743.sh`) with fewer moving parts. Recorded as the fallback if the journald signal proves unwritable for a fresh host. |

## Technical Considerations

- The emitted-vs-echoed anchor is load-bearing: the log echoes each step's `run:` source, which carries the *unexpanded* `var.web_hosts["${WEB_HOST_KEY_RAW}"]`; only the emitted line carries the resolved `web-N`. Anchoring `web-host-(replace|create) web-[0-9]+ — fresh-host Sentry pointer` on non-ANSI lines satisfies both (echoed source cannot produce a resolved key).
- Job conclusion is not the boot verdict (#6995): a run can fail after the host booted clean. Population therefore keys on the trail step's emitted `fresh_boot_ready`, not `job.conclusion == "success"`.
- gh run-record lifetime: the 30d population window is far inside the ~170d step-list stripping horizon (2026-10-14 learning) and `--created` bounds the enumeration server-side.
- No new autonomous-task surface: the probe is a script the existing daily sweeper invokes — Task-Design gate (plan §2.9.3) does not fire (detection table covers new workflows/Inngest functions/CHECK_REGISTRY/pg_cron/host timers/daemons/TF-emitted workflows, none of which this plan creates).
- IaC routing gate: no new infrastructure (no server/systemd/cron/secret/vendor dashboard) — the probe rides the existing sweeper schedule and already-bound secrets.
- Encryption Posture: no new persistent store and no new cross-component connection — the probe reads Better Stack Telemetry and the GitHub API over the same TLS paths the existing probes use. Skipped.
- GDPR gate: no regulated-data surface, none of the (a)-(d) expansion triggers (no LLM processing, no `single-user incident` threshold, no KB-corpus-reading cron, no artifact distribution). Skipped.

## Files to Create

- `scripts/followthroughs/web-first-deploy-10585.sh` — the watchdog probe (algorithm above; `FT10585_QUERY_SH` test seam mirroring `FT8743_QUERY_SH`; `RETIREMENT:` header listing `scripts/test-all.sh` run_suite line + `suite-shard-legs.tsv` row + tracker directive).
- `scripts/followthroughs/web-first-deploy-10585.test.sh` — synthesized-fixture suite (see Test Scenarios; fakes `gh` + the query transport via the seam; `cq-test-fixtures-synthesized-only`).

## Files to Edit

- `scripts/test-all.sh` — register `run_suite "scripts/web-first-deploy-10585" bash scripts/followthroughs/web-first-deploy-10585.test.sh` (explicit registration — `scripts/followthroughs/*.test.sh` is not in SUITE_GLOBS).
- `scripts/suite-shard-legs.tsv` — regenerated via `python3 scripts/regenerate-shard-manifest.py --incremental --write`.
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md` — §"Verify the result" gains one line: the replace's verification extends to first-deploy via the standing tracker; a dark first deploy lands on the tracker as ACTION REQUIRED within the deadline.
- `.github/workflows/apply-web-platform-infra.yml` — the `web_host_replace` Dispatch summary gains one line naming the standing tracker (the only workflow edit; an echo line inside an existing `run:` body — no new step, no permission change).
- `knowledge-base/engineering/architecture/decisions/ADR-148-web-host-replacement-is-a-distinct-gated-dispatch.md` — one-line addendum recording that post-replace verification now extends past the boot trail to the first deploy (operational note; the gate contract and `-target` set are unchanged).
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — optional one-line note pointing the standing-watchdog shape at this probe (only if the convention wants the pattern named; else skip).

## Implementation Phases

### Phase 1: Probe + fixture suite

- Write `scripts/followthroughs/web-first-deploy-10585.sh` (failing-test-first per `cq-write-failing-tests-before`: fixture suite defines the verdict table before the probe).
- Write `scripts/followthroughs/web-first-deploy-10585.test.sh` with synthesized fixtures (fixture shapes below).
- Register in `scripts/test-all.sh`; run `python3 scripts/regenerate-shard-manifest.py --incremental --write`; run `bash scripts/lint-orphan-test-suites.sh` (or its registered gate) to prove registration.
- Success: suite green; `lint-followthrough-varq-ban.sh`, `followthrough-exec-bit.test.sh`, `followthrough-predicate-parity.test.sh` all pass on the new file.

### Phase 2: Discoverability + docs

- Dispatch-summary line in `apply-web-platform-infra.yml`; runbook line; ADR-148 addendum.
- Success: `actionlint` clean on the workflow; docs lint (`lint-infra-no-human-steps.py --changed`) clean.

### Phase 3: Enrollment (post-merge, automated)

- Dry-run the real sweeper on the branch pre-merge: `gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true`, read the new tracker's `exit=` line in the run log.
- Post-merge: `gh issue create` the standing tracker (title + body + directive per Follow-Through Enrollment below), label `follow-through` (verified to exist — 62 open trackers carry it), then `gh issue close 10585` citing the tracker + run URL.
- Success: `gh issue view <T> --json labels` shows `follow-through`; the directive is unfenced at column 0; the next daily sweep comments NOT YET or ACTION REQUIRED.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — a broken probe means the first-deploy obligation goes unmeasured again (the status quo ante); the blast radius is an ops-telemetry gap, not a user-visible defect.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure — the probe reads CI run metadata and ops journald rows, writes only GitHub issue comments through the existing sweeper.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal machinery change on the ops-verification surface; no user data, no user-facing surface, no destructive capability is added or removed.
- `threshold: none, reason: the diff touches .github/workflows/apply-web-platform-infra.yml (a CI-sensitive path) but adds only an informational summary line — no step, permission, credential, or apply-surface change`.

## Observability

```yaml
liveness_signal:
  what: "Daily sweeper verdict comment on the standing tracker (NOT YET quiet-state / ACTION REQUIRED breach / CANNOT ESTABLISH)"
  cadence: "daily 18:00 UTC (scheduled-followthrough-sweeper.yml cron)"
  alert_target: "GitHub issue comment on the standing tracker (operator-visible; the paging tier is #10584's scope)"
  configured_in: ".github/workflows/scheduled-followthrough-sweeper.yml env: block (no edit — GH_TOKEN + BETTERSTACK_QUERY_* already bound)"
error_reporting:
  destination: "sweeper captures the probe's last 4KB stdout/stderr into the tracker comment"
  fail_loud: "exit 5 → 'ACTION REQUIRED' heading comment; exit 3 → 'CANNOT ESTABLISH' comment naming the missing input; sweeper run reds on REQUIRED-SECRET-MISSING"
failure_modes:
  - mode: "replaced host never deploys (the #8743 recurrence class)"
    detection: "no Deploy-succeeded marker for host_name post-boot_ts past the 2d deadline"
    alert_route: "exit 5 → ACTION REQUIRED comment naming host, boot ts, run URL"
  - mode: "Better Stack channel dark for the fresh host (Vector not shipping)"
    detection: "positive-control count 0 past the deadline"
    alert_route: "exit 5 → ACTION REQUIRED comment (channel-dark is the incident shape, not a quiet pass)"
  - mode: "probe cannot measure (credential unbound, gh/jq missing, transport failure)"
    detection: "preflight checks + transport rc"
    alert_route: "exit 3 → CANNOT ESTABLISH comment naming the input — never a silent quiet-state"
  - mode: "probe accidentally closes the tracker (verdict becomes reachable as PASS)"
    detection: "never exits 0 by construction; the never-0/never-1 invariant is a suite assertion"
    alert_route: "suite red at authoring time; sweeper keeps a closed tracker live only 14d"
logs:
  where: "sweeper run log (gh run view scheduled-followthrough-sweeper.yml); tracker comment history"
  retention: "GitHub Actions log retention; issue comments permanent"
discoverability_test:
  command: "bash scripts/followthroughs/web-first-deploy-10585.sh"
  expected_output: "CANNOT ESTABLISH"
```

## Guard Contract

### Guard 1 — web-first-deploy-10585 watchdog probe

**Property.** Every web host proven freshly booted by a `web_host_replace`/`web_host_create` dispatch and still declared in `var.web_hosts` shows a Deploy-succeeded-class journald row postdating its newest boot before `boot_ts + 2d`, else the tracker reports ACTION REQUIRED.

**Assembly.** Population chokepoint: the `gh run list`/`gh run view` enumeration of `apply-web-platform-infra.yml` dispatch runs joined to the trail step's emitted verdict lines (the ONLY derivation — every owed host must flow through it). Verdict chokepoint: the per-host Better Stack join on `host_name` + `dt >= boot_ts`. Roster chokepoint: the `variables.tf` `web_hosts` membership parse.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Fixture: a dispatch run whose trail emits `booted DARK` (no `fresh_boot_ready`) — host wrongly added to the owed set if the boot gate is dropped | RED |
| 2 | Fixture: the emitted marker line replaced by only echoed `run:` source (`${WEB_HOST_KEY_RAW}` unexpanded / ANSI-prefixed) — population derives no host (guard's own dispatch: a probe enumerating zero owed hosts must still distinguish "nothing owed" from "derivation broken" — paired with the gh-failure → CANNOT ESTABLISH arm) | RED |
| 3 | Fixture: two owed hosts, first accounted, second past-deadline markerless — verdict must still exit 5 (a check that stops at the first member is the defect) | RED |
| 4 | Fixture: marker row exists but predates `boot_ts` (stale evidence, 2026-10-28 learning) — must not account the host | RED |
| 5 | Harness row: probe run with `GH_TOKEN` unset and BETTERSTACK creds set — must exit 3 (CANNOT ESTISH), never 2-as-quiet | RED if it exits 2 |
| 6 | Must-PASS variant: owed host with marker postdating `boot_ts` and control >= 1 — accounted; aggregate verdict NOT YET (2) | PASS |

## Architecture Decision (ADR/C4)

- `### ADR` — amend **ADR-148** with a one-line verification-coverage addendum (operational record; no new ADR — this instantiates the existing follow-through substrate, it does not create a substrate or move a boundary).
- `### C4 views` — **no C4 impact.** Enumeration per the completeness mandate (all three model files read): no new external human actor (tracker comments reach the existing public-issue-reader surface and the operator); no new external system (Better Stack Telemetry, GitHub API, and the sweeper are already modeled elements/edges); no new container or data store; no access-relationship change (the probe consumes the same read edges existing probes use).
- `### Sequencing` — the ADR-148 addendum lands in THIS PR; the tracker enrollment is post-merge Phase 3.

## Open Code-Review Overlap

Open `code-review` issues whose bodies touch the planned paths — all **acknowledged** (different concerns; none is a fold-in for this diff, none double-counted):

- `scripts/followthroughs/`: #11312 (monitor_sig probe), #10464/#10463/#10462 (zot fill-rate probe legs), #8800 (census sandbox fixture), #8435 (gsc-indexing-drain probe) — new probe file touches none of their subjects.
- `scripts/test-all.sh`: #7942 (mutation-battery naming) — unrelated.
- `.github/workflows/apply-web-platform-infra.yml`: #11388 (alert drift guards), #7098 (`run:` bodies `set -e` audit) — the edit adds one `echo` line inside an existing `run:` body, no new `run:` body.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Extend the replace path (or enroll a follow-through) so a web-host replace verifies the replacement host's first deploy completes" | Probe (Files to Create) + tracker enrollment (Phase 3) | mapped |
| 2 | "e.g. grade `peers[\"<ip>\"].exit_code == 0` in /hooks/deploy-status after the next release, or assert a Deploy-succeeded-class journald row for the new host's host_name within N days of the replace" | Step-3 verdict chooses the journald arm (Deploy-succeeded marker per host_name); deploy-status grade recorded as alternative | mapped |
| 3 | "The BOOT verification (fresh-host-boot-trail.sh, web-fresh-boot-zot-8651.sh precedent) already exists; the missing arm is boot→first-deploy" | Step-1 population anchors on the existing trail's emitted verdict; no re-implementation of boot verification | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `web-first-deploy-10585.sh` probe | "or enroll a follow-through so a web-host replace verifies the replacement host's first deploy completes" | asked |
| `web-first-deploy-10585.test.sh` + test-all/shard registration | — | inferred — justification: the probe's exit-code contract is only as real as its suite; the convention requires deterministic exit semantics (`lint-followthrough-varq-ban`, exec-bit, predicate-parity) and orphan-suite registration |
| Dispatch-summary + runbook + ADR-148 lines | — | inferred — justification: discoverability of the standing obligation; without a pointer the next replace's operator has no way to know first-deploy coverage exists (the #6969-shape complaint that produced this issue) |
| Standing tracker via post-merge `gh issue create` | "or enroll a follow-through" | asked |
| web_host_create covered alongside web_host_replace | "The BOOT verification ... already exists; the missing arm is boot→first-deploy" | inferred — justification: the same dark arm exists for births; the population anchor is shared (`web-host-(replace|create)`), so covering both costs one alternation and closes the identical gap |

### Split Assessment

- Subsystems touched: 3 — `scripts/`, `.github/`, `knowledge-base/`
- Planned files: 7 | Estimated changed lines: ~450 (probe ~250, suite ~150, registrations+docs ~50)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `scripts/followthroughs/web-first-deploy-10585.sh` exists, is executable, and passes `bash scripts/lint-followthrough-varq-ban.sh`, `scripts/followthrough-exec-bit.test.sh`, and `scripts/followthrough-predicate-parity.test.sh` with zero findings on the new file.
- [ ] The probe never exits `0` or `1` on ANY fixture path (notify-only invariant asserted in its own suite: every verdict arm is `5`, `2`, `3`, or `78`).
- [ ] `scripts/followthroughs/web-first-deploy-10585.test.sh` covers the mutation-matrix rows (dark-boot exclusion, echoed-source exclusion, second-member overdue, stale-marker exclusion, credential-missing CANNOT ESTABLISH, accounted must-PASS) plus xtrace→78 refusal.
- [ ] `run_suite "scripts/web-first-deploy-10585"` is registered in `scripts/test-all.sh` and `scripts/suite-shard-legs.tsv` carries the regenerated row (`python3 scripts/regenerate-shard-manifest.py --incremental --write` output committed).
- [ ] `web-host-replace.md` §"Verify the result" and the `web_host_replace` Dispatch summary each name the standing tracker; `actionlint` (or the repo's workflow check) is clean on the workflow edit.
- [ ] ADR-148 carries the verification-coverage addendum.
- [ ] Sweeper dry-run on the branch (`gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true`) shows the new tracker's parse/exit line with no REQUIRED-SECRET-MISSING.

### Post-merge (automated)

- [ ] Standing tracker created via `gh issue create` carrying label `follow-through` and the column-0 unfenced directive (`gh issue view <T> --json labels,body` verifies both).
- [ ] `gh issue close 10585` after the tracker is verified filed (PR body uses `Ref #10585`, not `Closes` — enrollment is part of the deliverable).
- [ ] The first real sweep after enrollment reports NOT YET or ACTION REQUIRED (never a script-missing verdict).

## Test Scenarios

All `unit`-layer (fixture-driven `.test.sh`; no external calls — `gh` and `betterstack-query.sh` faked via PATH/ seams):

- Given a completed `web_host_replace` run whose trail step emitted `web-host-replace web-2 — fresh-host Sentry pointer` + `fresh-host boot reached fresh_boot_ready`, when the host has a `Deploy succeeded` row post-boot, then the host is accounted and aggregate verdict is 2.
- Given the same boot and no marker, when `now < boot_ts + 2d`, then verdict is 2 (pending).
- Given the same boot and no marker, when `now >= boot_ts + 2d`, then verdict is 5 naming `soleur-web-2`, the boot ts, and the run URL.
- Given two owed hosts where only the second is overdue, then verdict is still 5 (no early exit on the first).
- Given a run whose trail emitted `booted DARK`, then no obligation is created.
- Given echoed `run:` source containing `var.web_hosts["${WEB_HOST_KEY_RAW}"]` but no emitted line, then no host is derived (echo exclusion).
- Given a replaced host later re-replaced, then only the newest boot's deadline is graded.
- Given a host absent from `variables.tf`'s `web_hosts` map, then no obligation regardless of history.
- Given `BETTERSTACK_QUERY_HOST` unset (or `gh` missing, or the query transport failing), then exit 3 — never 2 and never 5.
- Given `-x` tracing with a live credential bound, then exit 78.
- Property: for any input, the probe's exit code is in `{5,2,3,78}` — a fixture sweep asserts the never-0/never-1 invariant.

## Follow-Through Enrollment (the deliverable's own enrollment)

- **Script:** `scripts/followthroughs/web-first-deploy-10585.sh` — exit 5 when any owed host's deadline elapsed without a Deploy-succeeded marker; exit 2 otherwise; exit 3 unmeasurable.
- **Tracker directive** (Phase 3, on the new standing tracker body — column 0, unfenced):

<!-- soleur:followthrough script=scripts/followthroughs/web-first-deploy-10585.sh earliest=<merge-timestamp-ISO8601Z> secrets=GH_TOKEN,BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->

- **Label:** `follow-through` (verified: 62 open trackers carry it).
- **Secrets:** all four names already bound in `scheduled-followthrough-sweeper.yml` `env:` — **no workflow env edit needed**.
- **Retirement:** the tracker is standing/notify-only by design; ending it is an operator act (close + remove label) per `followthrough-convention.md`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/verification-machinery change (`meta/machinery`); the mechanical UI-surface override does not fire (no UI-surface files in the Files lists).

## Success Metrics

- The next `web_host_replace` (or `web_host_create`) produces a tracker-visible obligation within 24h of the boot.
- A replacement whose first deploy never lands surfaces an ACTION REQUIRED comment within `boot_ts + 2d + one sweep interval`, versus the measured ~5-day blind spot of the 09-25/09-30 recurrence.

## Dependencies & Risks

- **Emitted-line format drift** — the population anchor depends on `fresh-host-boot-trail.sh`'s emitted phrasing (`fresh-host boot reached fresh_boot_ready`, `web-host-<op> <key> — fresh-host Sentry pointer`). The `.test.sh` pins the anchor strings; a boot-trail change that alters the phrasing reds the suite (deliberate coupling — the anchor IS the contract).
- **gh run-record lifetime** — bounded by `--created` 30d; far inside the ~170d step-list horizon.
- **Better Stack host_name keying** — `host_name` regressions flip the control to 0 → CANNOT ESTABLISH/ACTION REQUIRED, never a false quiet (8743-probe discipline).
- **Standing tracker rot** — the anti-goal this file exists to kill; the notify-only vocabulary keeps it open permanently, and the sweeper's daily comment IS the heartbeat. Risk accepted: a permanently-open issue is the intended shape (operator ends it by closing + unlabeling).
- **PR body must use `Ref #10585`** (not `Closes`) — the issue closes post-enrollment, not at merge.

## References & Research

- Issue: #10585 (this), #8743 + PR #10577 (peers-merge release gate), #8651, #9151, #6969 + PR #6973, **#10584** (alert-tier sibling, out of scope).
- ADRs: ADR-148 (replace path — amended here), ADR-218 (standing-alert substrate, alternative), ADR-263 (guest-side fresh-boot LUKS), ADR-128 (fresh-boot observability R1-R5).
- Postmortem: `knowledge-base/engineering/operations/post-mortems/2026-10-19-web2-plugin-mount-fchmodat2-postmortem.md` (Action Items row for #10585).
- Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`; probe precedents `scripts/followthroughs/web2-plugin-seed-8743.sh`, `web-fresh-boot-zot-8651.sh`, `web-host-replace-rebirth-6969.sh`; sweeper `scripts/sweep-followthroughs.sh`.
- Note: `Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).` No spec.md exists for this branch (one-shot pipeline entered at plan); `lane: cross-domain` is the fail-closed default and is informational only at this stage.

## Deepen Gate Results (deepen-plan pass, 2026-10-29)

Mechanical halt gates executed against this file; the agent fan-out phases (per-section research, review agents, learnings sub-agents) require a Task/agent-spawn tool that does not exist in the authoring harness — the equivalent coverage was folded in at plan time via the Research Insights mechanism-minimality work and the sharp-edges read (341 lines, all three pages).

- **4.4 Precedent-diff:** PASS — probe pattern follows `scripts/followthroughs/web2-plugin-seed-8743.sh` (marker set, `FT*_QUERY_SH` seam, positive control); diff documented in Proposed Solution + Alternatives.
- **4.5 Network-outage:** SKIP — zero trigger patterns in Overview/Problem; no `terraform apply` on provisioner-bearing resources.
- **4.55 Downtime & Cutover:** SKIP — no downtime-inducing operation in Files lists.
- **4.6 User-Brand Impact:** PASS — `threshold: none` + scope-out reason line (the sensitive-path regex matches `.github/workflows/apply-web-platform-infra.yml` via `web-platform`; the edit is one summary `echo` line).
- **4.7 Observability:** PASS — all 5 fields populated; `discoverability_test.command` verb `bash` allowlisted, no SSH, no shell metacharacters, <15s; `expected_output` is the literal `CANNOT ESTABLISH` (cred-less sandbox hits the preflight check first by design).
- **4.8 PAT-shaped vars:** PASS — grep clean (the probe declares `secrets=GH_TOKEN`, which is the `secrets.GITHUB_TOKEN` binding, not a PAT shape).
- **4.9 UI wireframe:** SKIP — no UI-surface files.
- **4.10 Encryption Posture:** SKIP — no `.tf`/`.sql`/cloud-init/docker-compose in Files lists; no new store or cross-component connection (probe reuses the sweeper's existing read edges).
- **4.11 Guard Contract:** PASS — `scripts/lint-guard-contract.py` green (1 guard entry); Assembly names chokepoints (the gh-history enumeration, the per-host journald join, the `variables.tf` roster parse), not member lists; Mutation matrix has 6 rows incl. harness + must-PASS.
- **4.12 Scope Check:** PASS — exactly one unfenced section, all three subsections, zero `unmapped`, every `inferred` row justified, `Recommendation:` present.
- **4.13 Task-Design:** SKIP — no new autonomous surface (probe is a script the existing daily sweeper invokes).

**Quality checks:** label `follow-through` verified live (`gh label list` — exists); cited rule IDs (`cq-test-fixtures-synthesized-only`, `cq-write-failing-tests-before`) verified active in `AGENTS.md`; all cited ADRs (148/218/263/128) exist on disk; issue citations verified (`#10585` open, `#10584` open sibling, `#9905` open emitted-vs-echoed precedent, `#6973` merged, `#8743/#8651/#9151` closed); no SHA/tag citations; the negative claim "no new secrets" verified against `scheduled-followthrough-sweeper.yml` `env:` (lines 110, 136-138 bind `GH_TOKEN` + `BETTERSTACK_QUERY_*`).

### Deepen findings folded in

- **Sweeper `env:` binding verified live** (`.github/workflows/scheduled-followthrough-sweeper.yml:110,136-138`) — the probe's `secrets=` line needs no workflow edit; the directive must name exactly `GH_TOKEN,BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD` or the sweeper reports REQUIRED-SECRET-MISSING.
- **#9905 confirmed as the emitted-vs-echoed precedent** (open follow-through; its S4 probe is what taught the anchor-on-emitted-line discipline encoded in Step 1).
- **Notify-only exit vocabulary is the contract:** the sweeper closes on `0`, comments-and-keeps-open on `5`/`2`/`3`. The suite asserts every verdict arm stays in `{5,2,3,78}` — a probe that ever exits `0` retires the watchdog ~14d post-closure (`CLOSED_LOOKBACK_DAYS=14`), reproducing the dormancy this plan exists to kill.
