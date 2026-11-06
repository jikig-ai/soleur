---
title: "chore: epic #10390 residual ci/infra-hygiene batch — dedupe-lint surfaces (#12092), scheduled-agent-spawn-stale-settle Sentry route, ci-hygiene session-state cherry-pick"
type: chore
date: 2026-11-06
slug: chore-one-shot-10390-residual-chores
branch: feat-one-shot-10390-residual-chores
issue: 12092
closes: 12092
lane: cross-domain
priority: p3-low
brand_survival_threshold: none
---

# chore: epic #10390 residual ci/infra-hygiene batch

> Spec lacks valid `lane:` — no `spec.md` exists for this branch; defaulted to
> `cross-domain` (TR2 fail-closed).

## Overview

Epic #10390's residual ci/infra-hygiene chore batch, landing in draft PR #12235 (already open;
do not create another). Three workstreams:

- **WS1 — Issue #12092 (OPEN, `type/chore`).** Per-surface disposition of the four read
  surfaces adjacent to `scripts/lint-gh-dedupe-shape.py`'s unquoted `IDENT=$(gh issue|pr
  list|search)` census class. Measured live on this branch (2026-11-06): the quoted-capture
  advisory is **13 sites, not ~19** (issue text is stale; the H6 ceiling is already 13).
  The plan fixes the genuinely-dispositionless sites, marks the already-handled ones,
  normalizes-or-marks the inside-substitution `|| true` close-path reads, records per-site
  decisions for `gh api` issues-GETs and `gh issue|pr view` probes, and extends the lint's
  scan root to `.github/actions/*/action.yml`. The H6 `ADVISORY_CEILING` decrements to the
  post-resolution live count — it is the regression channel, never silently satisfied.
- **WS2 — Route `sentry_cron_monitor.scheduled_agent_spawn_stale_settle` into
  `sentry_alert.cron_monitor_failure.monitor_ids`** (two-PR-rule PR 2; precedent plan
  `plans/archive/20261013-062704-2026-10-11-route-scheduled-integration-suites-monitor-plan.md`).
  Measured check-ins are **verified at plan time** (see Premise Validation): Sentry monitor
  env `production` reports `status=ok`, `activeIncident=null`, `lastCheckIn
  2026-11-06T10:00:01Z` on the `*/15` cadence, `nextCheckIn 10:15` — continuous receipt since
  `dateCreated 2026-11-06T04:32Z` (~22 expected ticks, zero missed-check-in incidents). Live
  detector id: **`2607514`**. Work re-verifies immediately before the `.tf` edit; if the
  evidence has collapsed, the deferral arm (below) applies instead.
- **WS3 — Cherry-pick `5a8ffeefb8`** from `origin/feat-one-shot-10390-ci-hygiene-batch`
  (+8 lines to `knowledge-base/project/specs/archive/20261105-092601-feat-one-shot-10390-ci-hygiene-batch/session-state.md`
  — the merge + post-merge verification record). Dry-run verified: applies cleanly, single
  `M` row, no conflicts. After this PR merges, delete the remote branch
  `feat-one-shot-10390-ci-hygiene-batch` (recorded as a post-merge step).

## Research Insights

### Premise Validation

Every cited premise was re-verified on 2026-11-06:

- `gh issue view 12092` → **OPEN**, `type/chore`, `priority/p3-low`, `domain/engineering`,
  `meta/machinery`. Live and undone.
- `gh pr view 12235` → **OPEN**, `isDraft=true`, `headRefName=feat-one-shot-10390-residual-chores`,
  `mergeable=MERGEABLE`, title `WIP: feat-one-shot-10390-residual-chores`.
- Deferral holds: `#10382` OPEN (operator-reserved — production-mutating), `#10290` OPEN
  (deferred by its own terms to the next probe_schema bump), `#9294` OPEN with blocking
  PR `#10928` OPEN (verified today).
- Cherry-pick source `5a8ffeefb8` exists on `origin/feat-one-shot-10390-ci-hygiene-batch`
  (fetched); `git cherry-pick --no-commit` dry-run produced exactly one `M` row on the
  archive session-state path and was reset cleanly.
- Sentry check-ins — **verified live** (not deferred): `GET
  https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-agent-spawn-stale-settle/`
  under `doppler run -p soleur -c prd` with `SENTRY_AUTH_TOKEN` (bearer via `curl --header @-`
  stdin, destination pinned, `--disable --noproxy '*' --proto '=https'` per the
  `sentry-alert-live-fidelity.sh` transport convention) → HTTP 200, `status=active`,
  environments `[{name: production, status: ok, isMuted: false, activeIncident: null,
  lastCheckIn: 2026-11-06T10:00:01Z, nextCheckIn: 2026-11-06T10:15:00Z, nextCheckInLatest:
  10:45}]`, config `{crontab */15, checkin_margin 30, max_runtime 10, UTC, thresholds 1/1}`
  matching `cron-monitors.tf:943` exactly (proof the IaC apply landed). The check-ins
  endpoint returns the latest check-in (`status=ok`, env `production`); `activeIncident:
  null` plus `status: ok` over ~5.5 h ≈ 22 expected `*/15` ticks is the plural-measured
  evidence — a miss past `nextCheckInLatest` would have flipped the env to error and opened
  an incident. Detector id via `GET …/detectors/?query=scheduled-agent-spawn-stale-settle`
  → `"2607514"`, `type: monitor_check_in_failure`. Token note: `SENTRY_ISSUE_RO_TOKEN`
  ([event:read, org:read]) gets **HTTP 403** on `/monitors/` — the monitors API needs the
  broader `SENTRY_AUTH_TOKEN`/`SENTRY_IAC_AUTH_TOKEN`; the read stays GET-only.
- **Pipeline-arg drift caught and corrected:** the brief said "local doppler is NOT
  configured" — measured false: `doppler configure` shows a `dp.ct.*` token scoped to the
  `soleur` project; `doppler secrets -p soleur -c prd --only-names` lists
  `SENTRY_AUTH_TOKEN`/`SENTRY_IAC_AUTH_TOKEN`/`SENTRY_ISSUE_RO_TOKEN`. This is the reason
  WS2 routes instead of deferring.
- Collision precheck (`scripts/collision-precheck.sh 12092`): **no open PRs** name #12092;
  the reported foreign `proc.sh` hits are `test-all.sh` processes in three unrelated
  worktrees (`feat-one-shot-10112-inngest-residuals`, `feat-one-shot-10865-constraint-scaffold-pairs`,
  `feat-one-shot-12013-replay-a-start-priority`) — no file or issue overlap with this batch.
  `gh pr view 12187 --json files` (the only loose search hit) touches neither
  `cron-monitor-alerts.tf`, `alert-reference.json`, nor the dedupe lint.
- Epic-delegation constraint: delegation on #10390 covers drift dispatch + revert-PR only
  and expires 2026-11-20 — this plan assumes **no** delegated `gh pr ready`/`gh pr merge`
  authority; both need fresh operator go-ahead (`hr-menu-option-ack-not-prod-write-auth`).

### Property List (Phase 0.6b)

The ask restated as observable properties:

1. Every `IDENT="$(gh issue|pr list|search …)"` capture in `.github/workflows/` carries a
   named failure disposition (out-of-capture `||` handler, condition context, or a typed
   `# dedupe:` marker) — no silent abort and no silent collapse.
2. The quoted-advisory class cannot silently re-grow: `ADVISORY_CEILING` in
   `lint-gh-dedupe-shape.test.sh` equals the post-resolution live advisory count.
3. Every `gh api` issues-GET dedupe read and `gh issue|pr view` existence-probe capture in
   `.github/workflows/` has a recorded per-site disposition (handler, marker, or an
   explicit benign-direction ruling).
4. A future undispositioned `VAR=$(gh issue|pr list|search)` capture inside
   `.github/actions/*/action.yml` fails the lint (scan-root coverage, not just today's
   clean tree).
5. A missed or failed check-in on `scheduled-agent-spawn-stale-settle` emails the org via
   `sentry_alert.cron_monitor_failure` — not just an un-emailed Sentry issue.
6. The merge + post-merge verification record for the ci-hygiene batch lands on main via
   this PR's history (cherry-pick, not re-author).

### Cut List

- **Extend `GH_DEDUPE_HEAD` to `gh api` / `gh issue|pr view`** — property 3 is the only one
  it would serve; the `gh api` argv grammar (`-X GET` + `/issues` path filtering vs POST
  writes) and the single-issue-read shape of `view` do not share the enumeration-defect
  class the head models, and the dedupe-shaped inventory is ≤2 sites. Per-site decisions
  (markers + handler verification) buy the same property without new grammar. Recorded as
  a decision-challenges row (`pending - assumed`).
- **Promote quoted captures into the census class** (advisory → gate finding) — the issue's
  own acceptance prescribes the ceiling as the regression channel; a `0`-floored ceiling
  delivers the same fail-closed property through the existing test layer.
- **New issue for the Sentry route** — the unrouted map entry already cites #8839 and this
  batch is the tracked follow-through; no new tracker needed unless the deferral arm fires
  (then the deferral is documented in-plan + on the PR).

### Relevant files

- `scripts/lint-gh-dedupe-shape.py` — census head `GH_DEDUPE_HEAD` (`gh issue|pr
  list|search`, deliberately bounded — docstring names these exact residuals), `collect()`
  rooted at `.github/workflows` (line 541), advisory exclusion for handled/marked quoted
  sites (lines 535–537), `_has_marker` 2-line window, vacuity floors (rc=2 on missing dir /
  zero targets / zero census sites).
- `scripts/lint-gh-dedupe-shape.test.sh` — `ADVISORY_CEILING=13` (line 772, H6 at 767–778),
  `mkfix` fixture-root helper (line 76), G-section shape grammar tests, H-section live-tree
  tests. Registered in `scripts/test-all.sh:5735` (`run_suite "scripts/lint-gh-dedupe-shape"`).
- Workflows: the 13 advisory sites (see Disposition table), the `gh api`/view inventories
  (below), plus marker precedent `scheduled-cron-artifact-age.yml:151` (`# dedupe: benign —
  || true inside on a close-path read`) and `scheduled-terraform-drift.yml:1737`
  (`# dedupe: fail-closed — deliberate bare capture: a failed lookup fails the step (the
  Sentry check-in reads this step's outcome)`).
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — `cron_monitor_alert_unrouted`
  map entry at lines 64–66 (comment + key), `monitor_ids` list lines 76–100 (sorted;
  `scheduled_agent_spawn_stale_settle` sorts **first** among `scheduled_*` labels — before
  `sentry_cron_monitor.scheduled_anthropic_credit_probe.id` at line 83).
- `apps/web-platform/infra/sentry/alert-reference.json` — `cron-monitor-failure.detectorIds`,
  string-sorted; `"2607514"` appends after `"2586358"` (last element).
- `apps/web-platform/test/server/inngest/sentry-cron-monitor-routing-parity.test.ts` —
  Guard 1: every declared monitor is in `monitor_ids` XOR the unrouted map, never both.
- `apps/web-platform/infra/sentry/README.md` §"the two-PR rule (#8630)" — PR 2 = move the
  label into `monitor_ids` + regenerate `alert-reference.json` (detectorIds change proved
  by the `plan_pr` `sentry-alert-reference` gate; `sentry-alert-reference-expected-<run>`
  artifact is the reconciliation source on red).
- `.github/workflows/apply-sentry-infra.yml` — applies on merge to `main` (paths cover the
  whole `infra/sentry/` tree); `workflow_dispatch` is the re-run escape hatch.
- `apps/web-platform/server/inngest/functions/_cron-shared.ts:452` — check-in transport
  (`https://<domain>/api/<projectId>/cron/<slug>/<publicKey>/?status=`).
- `apps/web-platform/infra/sentry/cron-monitors.tf:943` — the monitor declaration
  (`*/15 * * * *` UTC, margin 30, runtime 10, thresholds 1/1).

### Institutional learnings

- `2026-10-11 route-scheduled-integration-suites-monitor plan` (archived) — the exact WS2
  precedent: detector id read live at plan time, local `alert-reference.json` derivation
  with the CI gate as proof, post-merge read-back as the only evidence the route fires.
- `#9659`/`#9612` dedupe-lint doctrine — handler OUTSIDE the capture; `|| true`/`|| :`/bare
  `VAR=""` first-elements are silent collapses, not dispositions; unmodelable constructs
  stay unclassified-and-loud.
- `wg-kb-artifacts-archived-in-pr` — live `specs/<dir>/`, `plans/*`, `brainstorms/*` rows
  deny `gh pr merge` via `ship-kb-archive-gate.sh`; ship Phase 6.45 archives this plan +
  spec dir in-PR. The cherry-picked session-state.md is **already** under `archive/` and
  needs no move.
- `hr-observability-as-plan-quality-gate` — `.tf` edit is a live Sentry alert-config
  change → `## Observability` below; discoverability probe runs without SSH (grep-based,
  same shape the precedent plan used).

### Research decisions

- **No external research** — all three workstreams are fully grounded in-repo: the lint
  docstring names the residual scope, the sentry README owns the two-PR rule, and the
  precedent plan supplies the routing-move shape.
- **No research/domain fan-out spawned** — this ran as a planning subagent without a
  Task/Agent tool (`Reviewed-Coverage: sequential-fallback`; cloud-detect reported
  `not-local:no-devin-env`). The enumerations below were executed directly instead.
- **GDPR gate: does not fire** — surfaces are CI lint config, workflow run-blocks, and a
  Sentry alert route; no schemas/migrations/auth/API routes, no new LLM processing of
  session data, no new cron reading learnings/specs, no new distribution surface. The
  plan does not touch user data.
- **Network-outage checklist: does not fire** — no SSH/firewall/timeout-class keywords in
  the ask, and the driven `terraform apply` touches `sentry_alert`/`sentry_cron_monitor`
  (no `provisioner`/`connection` blocks — pure API resources).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality on this branch (2026-11-06) | Plan response |
|---|---|---|
| "~19 advisory sites; H6 ceiling currently 19" | **13** advisory sites; `ADVISORY_CEILING=13` (main and branch agree — the issue text was written against an earlier count) | Dispositions target the 13 live sites; ceiling decrements to the post-resolution count |
| "remaining ~16 sit under step-level `set +e`/`list_rc` handlers" | **9** sites under `set +e`+`list_rc`; **1** (actions-queue-health:228) is `set -euo` + inside-substitution `|| true` (close-path, benign direction); **3** genuinely dispositionless as named | 9 markers + 2 inside-substitution sites dispositioned per the decision-challenges ruling + 3 normalizations |
| "local doppler is NOT configured" | `doppler configure` shows a valid `soleur`-project token; `prd`/`prd_terraform` secrets readable | Check-in verification ran at plan time; WS2 routes |
| "~10 composite action.yml run blocks, clean, unscanned" | 9 `action.yml` files, ~19 `run:` blocks, 0 `gh issue|pr list|search` captures (verified by grep; `bot-pr-with-synthetic-checks` wraps gh as `gh_app`/`gh_gate` — an aliased call shape the `gh` head does not match even after the scan-root extension; recorded as a known bound) | Extend `collect()` to `.github/actions/*/action.yml`; fixture test proves a new capture REDs |

## Per-Surface Dispositions (WS1)

### Surface 1 — quoted captures `IDENT="$(gh …)"` (13 live advisory sites)

| Site | Measured context | Disposition |
|---|---|---|
| `scheduled-machinery-drain.yml:187` `matches="$(gh issue list …)"` | `set -euo pipefail` (step at :169), no handler — gh fault aborts silently mid-step; `matches=""` would take the else branch and **file a duplicate standing issue** | **Normalize fail-closed:** append `|| { echo "::error::scheduled-machinery-drain: keep-open dedupe query failed — refusing to touch the standing issue (a blind read could file a duplicate)"; exit 1; }` outside the capture |
| `codeql-1537-revisit-watch.yml:84` `track_num="$(gh issue list …)"` | `set -euo pipefail` (:62), no handler; the step's own doctrine (:66-70) is "transient → unknown → no-op" and `[[ -z "$track_num" ]]` already warns + exits 0 | **Normalize fail-open-to-warning:** `|| { echo "::warning::codeql-1537-watch: tracking-issue lookup failed (transient?) — no-op this run"; track_num=""; }` — lands on the existing loud no-op path |
| `scheduled-supabase-watchdog.yml:512` `CANDIDATES="$(gh … 2>/dev/null \|\| true)"` | `set -uo pipefail` (no `-e`); inside-substitution `|| true` collapses API fault to "0 titled" `::warning::` — the docstring's worst shape on a close path | `pending - assumed`: `# dedupe: benign — \|\| true inside on a close-path read: a failed lookup yields empty CANDIDATES, the COUNT!=1 ::warning:: still fires, and the audit issue stays open (visible)` — matches `scheduled-cron-artifact-age.yml:151` precedent. Alternative on record: normalize the `||` outside |
| `scheduled-actions-queue-health.yml:228` `matches="$(gh … \|\| true)"` | `set -euo pipefail`; inside-substitution `|| true` on a self-close enumeration — failure keeps alarm issues open | Same disposition as supabase:512 (`# dedupe: benign — close-path read: a failed lookup leaves the action-required issues open, keeping the alarm visible`) |
| `scheduled-devin-docs-drift.yml:400` `EXISTING="$(gh …)"` | `set -uo`+`set +e` (:382/:386), `list_rc` handler | `# dedupe: fail-closed — deliberate list_rc: an unreadable list declines to file rather than create a duplicate ci/devin-docs-drift alarm` |
| `scheduled-devin-docs-drift.yml:465` `OPEN_NUMS="$(gh …)"` | `set +e` (:386… close step), `list_rc`+`::error::`+`exit 0` | `# dedupe: fail-closed — deliberate list_rc: an unreadable list declines to close; a resolved alarm stays open (visible)` |
| `scheduled-marketplace-drift.yml:612` `EXISTING="$(gh …)"` | `set +e`, `list_rc` handler | `# dedupe: fail-closed — deliberate list_rc` (duplicate-filing direction) |
| `scheduled-marketplace-drift.yml:811` `EXISTING="$(gh …)"` (inside `file_or_update()`) | `set +e`, `list_rc` handler | `# dedupe: fail-closed — deliberate list_rc` |
| `scheduled-marketplace-drift.yml:901` `OPEN_NUMS="$(gh …)"` (inside `close_class()`) | `set +e`, `list_rc`+`::error::`+`return` | `# dedupe: fail-closed — deliberate list_rc: declines to close on a blind read` |
| `scheduled-prod-version-drift.yml:263` `EXISTING="$(gh …)"` | `set -uo`+`set +e` (:240/:244), `list_rc` | `# dedupe: fail-closed — deliberate list_rc` |
| `scheduled-prod-version-drift.yml:426` `EXISTING="$(gh …)"` | `set +e` (:410), `list_rc` | `# dedupe: fail-closed — deliberate list_rc` |
| `scheduled-prod-version-drift.yml:561` `open_issues="$(gh …)"` | `set +e` (step's own comment documents the bash -e trap), `list_rc`+`::error::`+`exit 0` | `# dedupe: fail-closed — deliberate list_rc` |
| `scheduled-prod-version-drift.yml:604` `open_issues="$(gh …)"` | `set +e` (:604 area), `list_rc`+`::error::`+`exit 0` | `# dedupe: fail-closed — deliberate list_rc` |

Markers sit on the site's own line or within 2 physical lines above (the `_has_marker`
window). Every normalized/marked site leaves the advisory; `ADVISORY_CEILING` decrements
to the post-resolution live count — **target 0** if all 13 resolve, else the exact
remainder with a per-site reason in the comment above the constant.

### Surface 2 — `gh api` issues-GET dedupe reads

| Site | Measured context | Disposition |
|---|---|---|
| `dev-ledger-reconcile.yml:344` `existing=$(gh api -X GET …/issues …)` | unquoted, `|| lrc=$?` + `::error::` + `exit 1` — fail-closed by construction | Documentary `# dedupe: fail-closed — deliberate lrc: an unreadable list declines to file rather than duplicate the action-required ledger` (inert to the lint — records the decision); no handler change |
| `codeql-1537-revisit-watch.yml:66,68` `state=/reason="$(gh api … \|\| true)"` | inside-substitution `|| true`, but `[[ -z "$state" ]]` → `::warning::`+`exit 0` — deliberate "non-clean read = unknown → no-op" per the step's own comment | No edit (already dispositioned by design); note in the PR-body audit table |

Work phase re-enumerates `gh api` issues-GETs repo-wide (`grep -rnE 'gh api.*issues' 
.github/workflows/`); every dedupe-shaped GET gets the same marker-or-verify treatment.
`gh api` stays out of `GH_DEDUPE_HEAD` (Cut List).

### Surface 3 — `gh issue|pr view` existence-probe captures (13-site inventory)

| Site | Measured context | Disposition |
|---|---|---|
| `scheduled-inngest-health.yml:699` `HAS_ESCALATION=$(gh issue view …)` | `set -euo pipefail` (:499), no handler — a failed read aborts mid-escalation-path; sibling `supabase-watchdog.yml:441` already uses `\|\| HAS_ESC_RC=$?` + `::warning::` defer | **Normalize to the sibling shape:** `|| HAS_ESCALATION_RC=$?` + `::warning::` defer-to-next-tick branch (mirror `supabase-watchdog.yml:441-444`) |
| `scheduled-terraform-drift.yml:1746` `LATEST=$(gh issue view …)` | `set -euo pipefail`; deliberate bare capture — the step's own comment (:1735-1737) documents "a failed lookup fails the step (the Sentry check-in reads this step's outcome)" | `# dedupe: fail-closed — deliberate bare capture: a failed read fails the step, which the Sentry check-in reads` (same sentence shape as the OPEN_ISSUES marker 9 lines up) |
| `auto-label-security.yml:30` `TITLE=$(gh issue view …)` | implicit `bash -e`; `github.event.issue.number` always exists; a failed view reds the step | `# dedupe: fail-closed — deliberate bare capture: the event guarantees the issue exists; a failed read fails the step (visible)` |
| `auto-label-security.yml:32` `HAS_LABEL=$(gh issue view … \| grep -c … \|\| true)` | inside-substitution collapse → "0" → idempotent re-apply of the label | `# dedupe: benign — a failed read yields HAS_LABEL=0 and re-applies an already-held label (idempotent); the title prefix (:30) is the gate` |
| `scheduled-supabase-watchdog.yml:441` `HAS_ESC=$(gh issue view …) \|\| HAS_ESC_RC=$?` | already bound + `::warning::` defer | `# dedupe: fail-closed — deliberate HAS_ESC_RC: an unreadable label read defers escalation to the next tick (documentary marker; handler exists)` |
| `scheduled-rehearsal-skip-monitor.yml:341` `cur_title=$(gh issue view …) \|\| cur_title=""` | `|| VAR=""` is a vacuous arm per the lint's own vocabulary — silent collapse; failure direction = stale title unseen | Work phase reads the downstream use then picks: `# dedupe: benign` if an empty title is handled loudly, else normalize to `|| { ::warning::…; cur_title=""; }` |
| `scheduled-terraform-drift.yml:1642` `PRIOR=$(gh issue view … \|\| true)` | inside-substitution `|| true` under `set -euo` (:1555); PRIOR_KEYS parse treats empty as no-prior | Same rule as rehearsal-skip: read the downstream consumer, then marker or normalize |
| `post-merge-monitor.yml:121` `ISSUE_NUM=$(gh pr view … \|\| true)` and `:138` `HAS_BOT_LABEL=$(gh issue view … \|\| true)` | inside-substitution `|| true` (no `set` line — `bash -e` irrelevant, capture can't abort); failure direction needs the consumer read | Same rule |
| `apply-deploy-pipeline-fix.yml:1682` `prev=$(gh issue view …) \|\| prev_rc=$?` | already bound | `# dedupe: fail-closed` documentary marker (or verified-no-edit if the file's comment already records it — the step's own :1672 comment does; mark only if absent) |
| `apply-deploy-pipeline-fix.yml:2448,:2538` `STATE=$(gh issue view 4804 … \|\| echo "MISSING")` | inside-substitution `|| echo "MISSING"` — collapses to a **distinct sentinel**, not `""` | `# dedupe: benign — deliberate MISSING sentinel: a failed read produces a non-empty state the downstream branches on explicitly` (verify the branch reads "MISSING" at work time; if unread, normalize) |
| `reusable-release.yml:253` `PR_JSON=$(gh pr view …) \|\| give_up …` | bound (`||` outside, non-vacuous) | `# dedupe: fail-closed` documentary marker |
| `web-platform-release.yml:1193` `body=$(gh issue view … \|\| echo "")` | inside-substitution collapse to `""` | Same rule: consumer read, then marker or normalize |

`gh issue|pr view` stays out of `GH_DEDUPE_HEAD` (Cut List). Every disposition is recorded
in the PR body's per-surface audit table — the "decide per surface" acceptance asks for the
decision record, not just the diff.

### Surface 4 — composite `action.yml` run blocks

Extend `collect()` in `scripts/lint-gh-dedupe-shape.py` to also enumerate
`.github/actions/*/action.yml` (glob `action.yml|action.yaml`, same symlink-skip
advisory). Docstring SCOPE updates to name both roots; the "scanned N workflow(s)" summary
line updates to count files honestly (e.g. `scanned 113 file(s) across 2 root(s)` or
similar — nothing parses that line today; H5/H6 parse `census site(s)`/`quoted-capture`
only). `main()`'s `.github/workflows`-required usage gate is unchanged — actions coverage
is additive and a tree without `.github/actions` behaves exactly as today. Known bound:
`gh` invoked through wrapper functions (`gh_app`/`gh_gate` in
`bot-pr-with-synthetic-checks/action.yml`) does not match the `gh`-literal head either in
workflows or action files — recorded, not fixed (a wrapper-aware head is new grammar for
zero measured sites).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. A mis-disposition
  either re-grows the silent-abort class (a scheduled alarm files nothing — an internal
  reliability regression) or reds the lint suite/`plan_pr` — an internal gate red. The
  Sentry mis-route either leaves the monitor un-emailed (status quo) or reds
  `apply-sentry-infra`. No runtime path, no user artifact.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no vector — the
  diff is workflow `run:` blocks, a lint, an operator-only email route, and a generated
  projection id; no user data, credentials, or workspace content is read or written.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff touches .github/workflows/ + scripts/ + apps/web-platform/infra/sentry (sensitive paths) only for CI-read hygiene and an operator-only cron-monitor email route — no user data, auth, billing, or runtime behaviour.`

## Observability

Required: Files-to-Edit touches `apps/web-platform/infra/` (live Sentry alert-config) and
`.github/workflows/` + `scripts/` (CI control plane). The WS2 deliverable IS observability
machinery — it wires an existing liveness signal to email.

```yaml
liveness_signal:
  what: "the scheduled-agent-spawn-stale-settle Sentry cron check-in (posted by the Inngest function's terminal sentry-heartbeat step every 15 min); after this change a missed or errored check-in emails via sentry_alert.cron_monitor_failure"
  cadence: "*/15 * * * * UTC; checkin_margin 30m tolerates two dropped ticks, max_runtime 10m"
  alert_target: "email to all active Sentry org members (issue_owners → ActiveMembers fallthrough), throttled to ~1 email per monitor group per 24h (frequency_minutes 1441)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitor-alerts.tf (monitor_ids) and cron-monitors.tf (the monitor)"

error_reporting:
  destination: "Sentry issue group per monitor environment (fingerprint crons:{monitor_env.id}); the sweep's own spawn dead-letter report (reportSpawnDeadLetter) stays the primary channel for run-internal faults"
  fail_loud: "a settle throw posts status=error via postSentryHeartbeat; a dark function pages 'missed check-in' after nextCheckInLatest"

failure_modes:
  - mode: "the sweep stops running (Inngest cron dark, function unregistered)"
    detection: "Sentry monitor missed check-in past nextCheckInLatest"
    alert_route: "sentry_alert.cron_monitor_failure email — THIS change is what adds that route; before it, only an un-emailed Sentry issue existed"
  - mode: "sweep runs but the settle/select throws"
    detection: "error-status check-in + reportSilentFallback durable event + spawn dead-letter report"
    alert_route: "dead-letter report (primary) + Sentry issue; email via cron_monitor_failure after this change"
  - mode: "route drift: committed alert-reference.json diverges from live Sentry"
    detection: "daily scheduled-sentry-alert-drift.yml probe (scripts/sentry-alert-live-fidelity.sh) diffs live workflows vs the committed reference"
    alert_route: "one daily infra-drift GitHub issue naming the regeneration remedy"
  - mode: "a new undispositioned dedupe capture lands in a workflow or action.yml"
    detection: "scripts/lint-gh-dedupe-shape.test.sh live-tree rows (H4 unclassified:0, H6 advisory ceiling) inside scripts/test-all.sh"
    alert_route: "CI red on the suite — the lint is the gate; this change extends its scan root to .github/actions/"

logs:
  where: "GitHub Actions run logs (apply-sentry-infra.yml, plan_pr); Sentry cron monitor check-in history; Inngest function run logs"
  retention: "GitHub run retention; Sentry issue retention"

discoverability_test:
  command: grep -c 'sentry_cron_monitor.scheduled_agent_spawn_stale_settle.id' apps/web-platform/infra/sentry/cron-monitor-alerts.tf
  expected_output: "1"
```

The probe prints `0` pre-change (the label is only an unrouted-map key, which the pattern
does not match) and `1` post-change; the post-merge live read-back (Phase 4) is the
authoritative probe that the route fires. A second local probe for WS1:
`python3 scripts/lint-gh-dedupe-shape.py --root .` printing `unclassified: 0` — run by the
suite, not declared here (single discoverability slot).

## Encryption Posture

Not applicable — no persistent data store introduced and no new cross-component/network
connection: the `sentry_alert` edit wires an existing detector into an existing email
action on an existing API path (detection fires on `\.tf$` but the resource set is
unchanged — one attribute edit plus one locals-map entry removed).

## Infrastructure (IaC)

### Terraform changes

Existing root `apps/web-platform/infra/sentry` (provider pins unchanged). One attribute
edit on `sentry_alert.cron_monitor_failure` (`monitor_ids` +1 element in sorted position)
and one `cron_monitor_alert_unrouted` locals entry + its 3-line comment removed. No new
resource, no new variable, no new secret; `SENTRY_IAC_AUTH_TOKEN` usage unchanged;
`lifecycle.ignore_changes = [environment]` untouched.

### Apply path

The standing `apply-sentry-infra.yml` applies on merge to `main` (full-root plan then
apply; `paths:` covers the whole `infra/sentry/` tree). Expected blast radius: one
in-place update of one alert workflow's `monitor_ids` — no destroy, no downtime, no
`[ack-destroy]`. Never apply locally (`use_lockfile = false`; the root README's standing
rule). Zero-downtime path is intrinsic: an in-place detectorIds update on an alert
workflow does not touch monitors, ingestion, or hosts.

### Host fan-out

No `terraform_data` SSH provisioners are touched — no fleet siblings to classify.

### Distinctness / drift safeguards

Routing-parity Guard 1 (vitest, `sentry-cron-monitor-routing-parity.test.ts`), the
`plan_pr` `sentry-alert-reference` gate (committed projection == plan), the post-apply
live-fidelity probe, and daily `scheduled-sentry-alert-drift.yml` all stay in place and
unchanged; this PR moves data through them, not around them. `dev != prd`: single Sentry
org root, unchanged.

### Vendor-tier reality check

Sentry workflow/detector model unchanged — adding an existing detector (`2607514`) to an
existing workflow's `detectorIds` is a standard in-place update, the same shape the live
org already carries for 23 other detectors.

## Guard Contract

The deliverable modifies a guard (`lint-gh-dedupe-shape.py` scan-root extension) and its
regression channel (`ADVISORY_CEILING`).

### Guard 1 — action.yml scan-root coverage

**Property.** Every `IDENT=$(gh issue|pr list|search …)` dedupe capture without a
disposition fails the lint, whether it lives under `.github/workflows/` or
`.github/actions/*/action.yml` — the census root covers both filing surfaces.

**Assembly.** The chokepoint is `collect()`: every file the census evaluates flows through
its `targets` list. Two enumeration sites (workflows dir today; actions dir added by this
change) feed one scan path — a third root would have to be added at `collect()` or it is
never scanned, which is exactly the blind spot this contract names.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture `action.yml` containing a bare `EXISTING=$(gh issue list …)` with no disposition | RED — a finding naming the action.yml path+line |
| 2 | Revert the actions-dir enumeration in `collect()` (guard's own dispatch narrowed) while the live tree or a fixture carries an action.yml capture | RED — a test asserting an undispositioned action.yml capture is a finding must exist and fire |
| 3 | Fixture with a compliant `action.yml` first and a defect in a second `action.yml` | RED — the second member is the finding (a check that stops at the first member is the defect class) |
| 4 | Fixture `action.yml` whose capture is `||`-handled or `# dedupe:`-marked | PASS — must-PASS input that is not the canonical defect (handled/marked shapes are legal) |
| 5 | `ADVISORY_CEILING` raised above the live advisory count in a test that also requires it to equal the live count | RED — a ceiling the suite does not pin is a silently-satisfiable gate |
| 6 | A new quoted capture added to a live workflow with no disposition, ceiling unchanged | RED via H6 (live count exceeds ceiling) — the channel stays armed post-change |

## Architecture Decision (ADR/C4)

No new ADR and no C4 edit — the dedupe-disposition doctrine is #9659's existing contract,
the scan-root extension is the same guard's reach, and the Sentry route executes ADR-031 +
the #8630 amendment's two-PR rule (a mechanism already recorded). No ownership/tenancy
boundary, substrate, or trust-boundary change: a competent engineer reading the existing
ADRs is not misled by anything here.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "dedupe-lint residual surfaces for scripts/lint-gh-dedupe-shape.py — decide per surface: extend the census class, mark `# dedupe: fail-closed\|benign`, or normalize" | WS1 per-surface disposition tables + Implementation Phase 1 | mapped |
| 2 | "Route `sentry_cron_monitor.scheduled_agent_spawn_stale_settle` into `monitor_ids` … ONLY after verifying measured check-ins" | WS2 + the plan-time verification evidence + work-time re-verify arm | mapped |
| 3 | "If check-ins cannot be verified this session, do NOT route — keep the unrouted entry, sharpen its reason comment … document the deferral in plan Non-Goals" | Deferral arm (Phase 2.0 + Non-Goals) — evidence verified, arm unused unless re-verification fails | mapped |
| 4 | "Cherry-pick origin/feat-one-shot-10390-ci-hygiene-batch tip commit 5a8ffeefb8 … After this PR merges, the remote branch can be deleted" | WS3 + post-merge steps | mapped |
| 5 | "Deferred — do NOT work, record in plan Non-Goals: #10382, #10290, #9294" | Non-Goals | mapped |
| 6 | "the plan must NOT assume delegated merge/ready authority" | Phase 5 gate + AC | mapped |
| 7 | "the plan needs the ## Observability block … discoverability_test.command that runs WITHOUT SSH" | Observability section (grep probe) | mapped |
| 8 | "KB artifacts the PR adds/modifies must already be under archive/ paths" | Cherry-pick lands under `specs/archive/`; ship Phase 6.45 archives the live plan+spec dir in-PR (noted in Phase 5) | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| Extend `collect()` to `.github/actions/*/action.yml` | "composite action.yml run blocks (~10, currently clean, unscanned by a .github/workflows-rooted lint)" | asked |
| `alert-reference.json` `detectorIds` +`"2607514"` | inferred — the README's two-PR rule + precedent plan require the committed reference to move with the `.tf` (the `plan_pr` gate reds otherwise) | inferred, justified |
| `# dedupe:` markers on non-census sites (view/api) | "decide per surface" — markers are the repo's disposition-record mechanism | inferred, justified |
| "scanned N workflow(s)" summary wording update | inferred — the scan root now covers non-workflow files; honest labeling | inferred, trivial |

### Split Assessment

- Subsystems touched: 3 — `scripts/` lint, `.github/workflows/`, `apps/web-platform/infra/sentry/` (plus one archive doc).
- Planned files: ~19 | Estimated changed lines: ~120 (mostly one-line markers + two `||` arms + a collect() block + test rows + 2 tf/json lines).
- Thresholds: ≥4 subsystem roots OR >25 files OR >800 lines — **not crossed**.
- Recommendation: single PR (#12235), matching the batch convention (#11559/#11824/#11994
  and this epic's own #12064 precedent) with per-workstream commits.

## Non-Goals

- **#10382** — operator-reserved (production-mutating `INNGEST_SIGNING_KEY` rotation);
  never self-assigned. Verified OPEN 2026-11-06.
- **#10290** — deferred by its own terms to the next `probe_schema` bump. OPEN.
- **#9294** — deferred while PR #10928 is open; PR verified **OPEN** 2026-11-06.
- **`GH_DEDUPE_HEAD` extension** to `gh api` / `gh issue|pr view` / wrapper-shaped `gh_app`
  calls — cut per 0.6b; if the CTO ruling flips it, that is a follow-up, not this PR.
- **Sentry-route deferral arm** (only if work-time re-verification fails): keep the
  unrouted entry, sharpen the reason comment with the exact evidence checked
  (`GET …/monitors/scheduled-agent-spawn-stale-settle/` env status/lastCheckIn/
  activeIncident on <date>), and document the deferral here — the unrouted entry + #8839
  are the tracker; no new issue unless the deferral persists past the batch.
- **Epic #10390 close-out** — the epic stays open (other residual buckets + operator
  holds); this PR uses `Ref #10390`, never `Closes`.
- **Remote branch cleanup** is a post-merge step, not in-PR work.

## Implementation Phases

### Phase 1 — WS1: dedupe-lint residual surfaces (#12092)

1. **Normalize `scheduled-machinery-drain.yml:187`** — append the fail-closed
   `|| { echo "::error::…refusing to touch the standing issue…"; exit 1; }` arm outside
   the capture (table row 1; fail-open would file a duplicate standing issue).
2. **Normalize `codeql-1537-revisit-watch.yml:84`** — append the
   `|| { echo "::warning::…"; track_num=""; }` arm outside the capture, landing on the
   step's existing loud no-op path (transient→no-op doctrine).
3. **Disposition the two inside-substitution close-path sites** —
   `scheduled-supabase-watchdog.yml:512` and `scheduled-actions-queue-health.yml:228`:
   `# dedupe: benign` markers per the assumed ruling (decision-challenges row); if the
   work-phase CTO consult rules normalize, move each `||` outside with a `::warning::` arm
   instead. One mechanism per site, never both.
4. **Mark the nine `set +e`/`list_rc` sites** `# dedupe: fail-closed — deliberate
   list_rc: …` per the table (devin-docs-drift :400/:465, marketplace-drift :612/:811/:901,
   prod-version-drift :263/:426/:561/:604).
5. **Surface 2** — re-enumerate `gh api` issues-GETs (`grep -rnE 'gh api' 
   .github/workflows/ | grep issues`); marker on `dev-ledger-reconcile.yml:344`; verify
   every other dedupe-shaped GET is bound or dispositioned (codeql:66/68 recorded
   no-edit).
6. **Surface 3** — work the 13-site `gh issue|pr view` inventory: normalize
   `scheduled-inngest-health.yml:699` to the `supabase-watchdog:441` sibling shape; marker
   on `scheduled-terraform-drift.yml:1746`, `auto-label-security.yml:30/32`,
   `supabase-watchdog.yml:441`, `reusable-release.yml:253`, `apply-deploy-pipeline-fix.yml
   :1682/:2448/:2538` (sentinel form); consumer-read then marker-or-normalize on
   `rehearsal-skip-monitor:341`, `terraform-drift:1642`, `post-merge-monitor:121/138`,
   `web-platform-release:1193`. Record every decision in the PR-body audit table.
7. **Surface 4** — extend `collect()` in `scripts/lint-gh-dedupe-shape.py` to enumerate
   `.github/actions/*/action.yml` (same symlink-skip advisory; honest `scanned N file(s)`
   count line; docstring SCOPE + the residual paragraph updated to reflect the new bound).
8. **Test updates** in `scripts/lint-gh-dedupe-shape.test.sh`:
   - `ADVISORY_CEILING` decremented to the post-resolution live count (target `0`) with a
     comment naming the resolved sites — resolved sites decrement, never silently satisfy.
   - New fixtures: (a) undispositioned capture in `.github/actions/x/action.yml` FIRES;
     (b) `||`-handled/marked action.yml capture does not fire (must-PASS); (c) second-
     action.yml-after-compliant-first member check. Fixtures build `.github/workflows/`
     alongside (the usage gate still requires it) plus one clean census site (vacuity).
9. **Run** `bash scripts/lint-gh-dedupe-shape.test.sh` (green) and
   `python3 scripts/lint-gh-dedupe-shape.py --root .` — `unclassified: 0`, advisory count
   == the new ceiling.

### Phase 2 — WS2: route `scheduled_agent_spawn_stale_settle`

0. **Work-time re-verify (gate):** re-run the plan-time read —
   `doppler run -p soleur -c prd -- bash -c 'printf "Authorization: Bearer %s\n"
   "$SENTRY_AUTH_TOKEN" | curl -sS --disable --noproxy "*" --proto "=https" -g --header @-
   "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-agent-spawn-stale-settle/"'`
   — proceed only if env `production` still reports `status=ok`, `activeIncident=null`,
   and `lastCheckIn` within `nextCheckInLatest` (i.e. check-ins still arriving on cadence).
   If not: **deferral arm** (Non-Goals) — keep the unrouted entry, sharpen its reason
   comment with the evidence observed, do not edit `monitor_ids`.
1. `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`: delete the
   `scheduled_agent_spawn_stale_settle` comment block + map entry (lines 64–66); insert
   `    sentry_cron_monitor.scheduled_agent_spawn_stale_settle.id,` into `monitor_ids`
   sorted position — **before** `sentry_cron_monitor.scheduled_anthropic_credit_probe.id`
   (label sort puts `scheduled_agent_spawn_stale_settle` first among `scheduled_*`).
2. `apps/web-platform/infra/sentry/alert-reference.json`: append `"2607514"` to
   `cron-monitor-failure.detectorIds` (string-sorted → after `"2586358"`, last element).
   The detector id was read live at plan time (see Premise Validation); the `plan_pr`
   `sentry-alert-reference` gate is the proof — only if it reds, take the
   `sentry-alert-reference-expected-<run-id>` CI artifact and diff before copying (any
   hunk beyond the one id is a finding), per the precedent plan's arm.
3. Local gates: `bun test apps/web-platform/test/server/inngest/sentry-cron-monitor-routing-parity.test.ts`
   (and `sentry-monitor-iac-parity.test.ts`) — Guard 1 green, exactly-one-home per monitor.

### Phase 3 — WS3: cherry-pick the merge record

`git cherry-pick 5a8ffeefb8` (dry-run verified clean on this branch — single `M` row on
`knowledge-base/project/specs/archive/20261105-092601-feat-one-shot-10390-ci-hygiene-batch/session-state.md`;
keep the cherry-pick metadata, do not re-write). This is a cherry-pick, not a re-author —
`wg-kb-artifacts-archived-in-pr` is satisfied because the target is already under
`specs/archive/`.

### Phase 4 — Commit, push, PR body

- Per-workstream commits (WS1 lint+workflows, WS2 sentry route, WS3 cherry-pick — the
  cherry-pick keeps its own commit).
- Update PR #12235 (no new PR): title e.g. `chore: #10390 residual — dedupe-lint
  dispositions, agent-spawn-settle Sentry route, ci-hygiene merge record`; body carries
  `Closes #12092` on its own line (all four surfaces discharged), `Ref #10390`,
  `Ref #8839`, `Ref #9659` for context, the per-surface audit table (each site's chosen
  disposition), the Sentry check-in evidence, and a `## Changelog` section.
- Ship-time reminders encoded here: `wg-kb-artifacts-archived-in-pr` (ship Phase 6.45
  archives `plans/` + `specs/<branch>/` in-PR), `wg-ship-push-before-merge`, semver label
  (`semver:patch` — chore/docs-class).

### Phase 5 — Merge gate + post-merge (operator-held)

- **`gh pr ready` and `gh pr merge` need fresh operator go-ahead** — the #10390 delegation
  covers drift dispatch + revert-PR only and expires 2026-11-20; neither is assumed here
  (`hr-menu-option-ack-not-prod-write-auth`). This is a held gate, not a plan task the
  agent executes.
- Post-merge verification (after the merge the operator authorizes):
  - `apply-sentry-infra.yml` run on the merge commit completes; live read-back of the
    `cron-monitor-failure` workflow shows detector `2607514` in `detectorIds` (the only
    evidence the route fires).
  - `lint-gh-dedupe-shape` suite leg green on `main`.
  - Delete the remote branch `feat-one-shot-10390-ci-hygiene-batch`
    (`git push origin --delete feat-one-shot-10390-ci-hygiene-batch`) — its tip is now on
    main via the cherry-pick.
  - Close-out note on #12092 linking the per-surface audit (auto-close via `Closes` may
    already fire; verify the issue actually closed).

## Files to Edit

- `scripts/lint-gh-dedupe-shape.py` — `collect()` scan-root extension, docstring SCOPE +
  residual paragraph, summary count label.
- `scripts/lint-gh-dedupe-shape.test.sh` — `ADVISORY_CEILING` decrement + comment, new
  G/H fixture cases for the actions root (mkfix sibling creating `.github/actions/`).
- `.github/workflows/scheduled-machinery-drain.yml` — :187 normalize.
- `.github/workflows/codeql-1537-revisit-watch.yml` — :84 normalize.
- `.github/workflows/scheduled-supabase-watchdog.yml` — :512 disposition (+:441 marker).
- `.github/workflows/scheduled-actions-queue-health.yml` — :228 disposition.
- `.github/workflows/scheduled-devin-docs-drift.yml` — :400/:465 markers.
- `.github/workflows/scheduled-marketplace-drift.yml` — :612/:811/:901 markers.
- `.github/workflows/scheduled-prod-version-drift.yml` — :263/:426/:561/:604 markers.
- `.github/workflows/dev-ledger-reconcile.yml` — :344 marker.
- `.github/workflows/scheduled-inngest-health.yml` — :699 normalize.
- `.github/workflows/scheduled-terraform-drift.yml` — :1746 marker (+:1642 per rule).
- `.github/workflows/auto-label-security.yml` — :30/:32 markers.
- `.github/workflows/{apply-deploy-pipeline-fix,post-merge-monitor,reusable-release,
  scheduled-rehearsal-skip-monitor,web-platform-release}.yml` — per Surface-3 rule only
  where the consumer read leaves a disposition unrecorded.
- `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — unrouted entry removal +
  `monitor_ids` insert.
- `apps/web-platform/infra/sentry/alert-reference.json` — `detectorIds` + `"2607514"`.
- `knowledge-base/project/specs/archive/20261105-092601-feat-one-shot-10390-ci-hygiene-batch/session-state.md`
  — via `git cherry-pick 5a8ffeefb8` (no re-write).

## Files to Create

None (code/tree). Session artifacts — this plan, `specs/feat-one-shot-10390-residual-chores/{tasks.md,decision-challenges.md}`
— are pipeline records archived in-PR by ship Phase 6.45.

## Open Code-Review Overlap

One hit from the `code-review`-label sweep (`gh issue list --label code-review --state
open`, 95 issues scanned against the planned file set):

- **#3828** "extract composite action for 9-workflow Sentry Crons check-in fan-out" —
  names `scheduled-terraform-drift.yml` (one of the files this plan marks).
  **Disposition: Acknowledge.** Different concern — #3828 proposes extracting the
  in_progress/ok/error check-in *steps* into a composite action; this plan adds a `# dedupe:`
  marker beside a `gh issue view` read in the same file. No semantic overlap; the
  extraction (if it ever lands) would carry the marker comment with the moved lines.
  Left open on its own contested-design terms.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI lint, workflow run-block hygiene, and an
operator-only Sentry alert route. Product domain is not triggered (no UI-surface file in
Files to Create/Edit); the mechanical UI-surface override does not fire.

## Acceptance Criteria

- [ ] AC1: `python3 scripts/lint-gh-dedupe-shape.py --root .` prints
  `dedupe-shape: unclassified: 0` and an advisory count ≤ `ADVISORY_CEILING`.
- [ ] AC2: `grep -n 'ADVISORY_CEILING=' scripts/lint-gh-dedupe-shape.test.sh` equals the
  post-resolution live advisory count (target 0; each of the 13 named sites either left
  the advisory via handler/marker or remains with a reason recorded beside the constant).
- [ ] AC3: `scheduled-machinery-drain.yml`'s `matches="$(gh …)"` capture carries an
  out-of-capture `|| { echo "::error::…"; exit 1; }` arm (no silent abort, no duplicate
  standing-issue filing path on a blind read).
- [ ] AC4: `codeql-1537-revisit-watch.yml`'s `track_num="$(gh …)"` carries an
  out-of-capture `|| { ::warning::…; track_num=""; }` arm landing on the existing loud
  no-op path.
- [ ] AC5: Each of the 9 `set +e`/`list_rc` quoted sites carries a `# dedupe: fail-closed`
  marker on its line or within 2 lines above; each of the 2 inside-substitution
  close-path sites carries the ruling's disposition (marker or normalized arm).
- [ ] AC6: Every `gh api` issues-GET dedupe read and every `gh issue|pr view` capture in
  `.github/workflows/` has a recorded disposition in the PR-body audit table (handler /
  marker / explicit benign-direction ruling — including `scheduled-inngest-health:699`
  normalized to the sibling `rc`-defer shape).
- [ ] AC7: A fixture `.github/actions/x/action.yml` containing an undispositioned
  `VAR=$(gh issue list …)` REDs the lint (new test); a handled/marked action.yml capture
  and the 9-file clean live tree stay green (must-PASS rows).
- [ ] AC8: `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` — `grep -c
  'sentry_cron_monitor.scheduled_agent_spawn_stale_settle.id'` prints `1`, and the label
  no longer appears as a `cron_monitor_alert_unrouted` key; routing-parity vitest green.
- [ ] AC9: `apps/web-platform/infra/sentry/alert-reference.json`
  `cron-monitor-failure.detectorIds` contains `"2607514"` in sorted position; the
  `plan_pr` sentry-alert-reference gate passes (or the expected-artifact diff shows only
  the one id).
- [ ] AC10: `git log --format='%s' | grep -c 'docs(specs): record merge + post-merge verification'`
  ≥ 1 on the branch — the cherry-pick lands with its own hash and the source `5a8ffe`
  is unreachable from this branch, so a `5a8ffe` grep on the branch log is
  unsatisfiable; `git diff` of `session-state.md`
  vs its pre-pick blob shows only the +8 MERGED-record lines.
- [ ] AC11: WS2 work-time re-verification ran and was recorded in the commit message or
  PR body (env `ok` + `lastCheckIn` evidence); if it failed, the unrouted entry persists
  with a sharpened reason instead (deferral arm — AC8/AC9 then N/A by explicit record).
- [ ] AC12: PR #12235 body carries `Closes #12092` on its own line, `Ref #10390`,
  `Ref #8839`, `Ref #9659`, the per-surface audit table, and `## Changelog`.
- [ ] AC13: No `gh pr ready`/`gh pr merge` was run without fresh operator go-ahead; the
  post-merge checklist (apply-sentry-infra read-back, `feat-one-shot-10390-ci-hygiene-batch`
  remote-branch deletion, #12092 close verification) is recorded in the PR body.

## Test Scenarios

- Given an undispositioned `EXISTING=$(gh issue list …)` inside a fixture
  `.github/actions/x/action.yml`, when the lint runs on that root, then it exits 1 naming
  the action.yml path — Guard 1 matrix row 1/3.
- Given a handled (`||`-arm) or marked action.yml capture, when the lint runs, then rc=0 —
  matrix row 4 (must-PASS, non-canonical).
- Given the merged workflows, when `bash scripts/lint-gh-dedupe-shape.test.sh` runs, then
  all fixture + live-tree assertions pass including H4 (`unclassified: 0`), H5 (≥70 census
  sites), and H6 (advisory ≤ the new ceiling).
- Given the edited `cron-monitor-alerts.tf`, when
  `sentry-cron-monitor-routing-parity.test.ts` runs, then green — the label lives in
  exactly one of `monitor_ids`/unrouted.
- Given a deletion of the new `monitor_ids` element (mutation), when the parity guard
  runs, then RED naming `scheduled_agent_spawn_stale_settle` as unrouted.
- Given the merge, when `apply-sentry-infra.yml` completes, then the live workflow's
  `detectorIds` contains `2607514` — post-merge read-back (Phase 5), the only evidence
  the route fires.
- Given a transient `gh` fault on `scheduled-machinery-drain.yml`, when the step runs,
  then it exits 1 with `::error::…refusing to touch the standing issue` — never files a
  duplicate.

## Context

- Issue: #12092 (this batch discharges all four residual surfaces → `Closes`).
- Epic: #10390 (`Ref` — the epic stays open; delegation covers drift dispatch +
  revert-PR only, expires 2026-11-20).
- Origin issues: #9659 (the census class), #8839 (the stale-settle monitor's tracking
  issue), #12064 (the batch that introduced both residuals and shipped the monitor).
- Precedent plan (WS2 shape): `knowledge-base/project/plans/archive/20261013-062704-2026-10-11-route-scheduled-integration-suites-monitor-plan.md`.

## Sharp Edges

- **`|| true` / `|| :` / bare `VAR=""` are NOT dispositions** — inside OR outside the
  capture they are the silent collapse the lint exists to name. The `||` arm must sit
  outside the `$(…)` and be non-vacuous.
- **`set -e` aborts a capture mid-step with no breadcrumb** — the two normalized sites
  are the only places the failure could hide a duplicate-filing or silently-suppressed
  alarm; every other site already has a step-level handler the per-line model cannot see
  (which is why markers, not handler edits, are the disposition there).
- **Markers must sit within 2 physical lines above (or on) the site's first physical
  line** — a marker lower or further away does not clear the advisory.
- **`ADVISORY_CEILING` is a floor-on-growth, not a target** — decrement it to the
  measured remainder; a number set by guess re-opens the silent re-grow channel.
- **The detector id (`2607514`) was read live at plan time** — work does not re-derive it
  from the API, but the `plan_pr` gate is authoritative; a red means reconcile against the
  `sentry-alert-reference-expected-<run>` artifact, not re-edit blindly.
- **Do NOT `terraform apply` locally** — the standing apply path is
  `apply-sentry-infra.yml` on merge; local applies are forbidden (`use_lockfile = false`).
- **`gh pr ready`/`merge` are operator-held this run** — delegation scope on #10390 does
  not cover them.
- **A plan whose `## User-Brand Impact` is empty or omits the threshold fails
  deepen-plan Phase 4.6** — filled above.
- **plan-review agent fan-out was not spawned** — planning ran as a subagent without a
  Task tool; `Reviewed-Coverage: sequential-fallback`. Mechanical findings were applied
  directly; the two contested dispositions are in `decision-challenges.md` as
  `pending - assumed` rows for ship-time surfacing.

## Deepen-Plan Enhancements

**Deepened on:** 2026-11-06 | **Mode:** in-process sequential fallback (planning subagent;
no Task/Agent spawn — `Reviewed-Coverage: sequential-fallback`, `cloud-detect` →
`not-local:no-devin-env`) | **Halt gates:** all pass or skip-clean

### Gate results

- **4.5 Network-Outage Deep-Dive:** SKIP — no SSH/firewall/timeout-class trigger tokens in
  the ask or plan body; the driven `terraform apply` touches `sentry_alert` /
  `sentry_cron_monitor` only (no `provisioner`/`connection` blocks — verified by reading
  `cron-monitor-alerts.tf` and `cron-monitors.tf:943-954`).
- **4.55 Downtime & Cutover:** SKIP — no offline-inducing operation. The `.tf` change is
  an in-place `monitor_ids` attribute update on an alert workflow; no host replace, no
  DDL, no container/router swap. The zero-downtime path is intrinsic and named in the
  Apply path subsection.
- **4.6 User-Brand Impact:** PASS — section present, threshold `none`, sensitive-path
  scope-out bullet present (`apps/web-platform/infra/` and the `.github/workflows/`
  keyword shapes both match the canonical regex).
- **4.7 Observability:** PASS — all 5 fields populated; `discoverability_test.command`
  (`grep -c …`) starts with the allowlisted `grep`, contains no `ssh`, finishes sub-second;
  `expected_output: "1"` is a matchable literal.
- **4.8 PAT-shaped variable:** PASS — zero hits on the four-pattern sweep.
- **4.9 UI-Wireframe:** SKIP — no UI-surface path in Files to Edit/Create.
- **4.10 Encryption Posture:** PASS — detection fires on `\.tf$`; section present with the
  N/A rationale (no new store, no new connection — the alert's email action and API path
  pre-exist; same disposition the precedent plan carried).
- **4.11 Guard Contract:** PASS — `python3 scripts/lint-guard-contract.py` green (1 guard
  entry); Assembly names the `collect()` chokepoint, not today's member list; 6-row
  mutation matrix incl. own-dispatch (row 2), second-member (row 3), must-PASS (row 4),
  and harness rows (5–6).
- **4.12 Scope Check:** PASS — 1 unfenced `## Scope Check`; all Ask Mapping rows `mapped`;
  every `inferred` Provenance row carries a justification; Split Assessment carries a
  `Recommendation:`.
- **4.13 Task-Design:** SKIP — no new autonomous-task surface (no new workflow, Inngest
  function, cron, or daemon; the plan edits existing surfaces only).

### Research/enhancement applied in-process

- **Live Sentry evidence deepened WS2 past the brief's assumption.** The brief budgeted
  for a probable deferral ("local doppler is NOT configured"); the measured-config check
  found a working `soleur/prd` Doppler token, so the monitors API was queried directly —
  `status=ok`, `activeIncident=null`, `lastCheckIn` on cadence, detector id `2607514`.
  WS2 therefore routes (with a work-time re-verify gate), and `alert-reference.json`
  gained a concrete pre-derived id rather than an artifact-fetch arm as the primary path.
- **Stale-figure reconciliation.** The issue's `~19` advisory count and `ADVISORY_CEILING
  19` were measured stale against both branch and `origin/main` (13/13); the disposition
  table is built on the live enumeration, and the "~16 under `set +e`" claim was
  re-derived to 9 + 1 inside-substitution close-path site + 3 dispositionless.
- **Surface inventories made concrete.** The `gh issue|pr view` surface is a 13-site
  enumeration (8 files) and `gh api` issues-GETs a 2-site set — each row carries a
  measured `set`-context and a named disposition, so work executes a checklist rather
  than re-deriving the census.
- **Marker conventions verified against the tree** (`scheduled-cron-artifact-age.yml:151`,
  `scheduled-terraform-drift.yml:1737`, `apply-deploy-pipeline-fix.yml:1645`,
  `inngest-health.yml:408`) — the assumed `benign`/`fail-closed` buckets reuse the repo's
  own marker sentences, not invented vocabulary.
- **Precedent-diff gate:** WS2 pattern-binds to the archived
  `route-scheduled-integration-suites-monitor` plan (same two-PR-rule move) — the diff is
  the label, the detector id, and the sorted-insert position; everything else mirrors.
- **Verify-the-negative sweep (manual).** Negative claims checked against the tree:
  "no `gh issue|pr list|search` captures in action.yml" → `grep -rln` over
  `.github/actions/*/action.yml` returns zero; "0 sites under census in actions" →
  confirmed; "`# dedupe:` marker clears advisory" → `_has_marker` read at
  `lint-gh-dedupe-shape.py:536`; "`gh api`/`view` not in head" → `GH_DEDUPE_HEAD` read at
  line 103.
- **Scoped advisor consult (plan Step 4.5):** not spawned — no Task tool in this context;
  the contested dispositions are `pending - assumed` rows in
  `specs/feat-one-shot-10390-residual-chores/decision-challenges.md` for ship-time
  surfacing (the headless path the skill prescribes).

### Quality checks

- Original content preserved; enhancement confined to this section plus the pre-written
  gate-targeted sections.
- Literal consistency: `scheduled_agent_spawn_stale_settle` (tf label),
  `scheduled-agent-spawn-stale-settle` (Sentry slug + monitor name), and detector id
  `2607514` used consistently across Premise Validation, Observability, Phases, and ACs.
- No contradictions: the deferral arm in Non-Goals agrees with Phase 2.0's gate and
  AC11's N/A-by-record clause; AC2's ceiling target agrees with the Cut List's
  ceiling-vs-census rationale.
- `Closes #12092` is scoped to the issue's four named surfaces — all discharged by the
  disposition tables; epic/issues context stays `Ref`-only.
- Sensitive-path scan for the `none` threshold scope-out: `apps/web-platform/infra/` and
  `apply-deploy-pipeline-fix.yml`/`web-platform-release.yml`/`reusable-release.yml`
  (keyword-matched workflow names) all fall inside the canonical regex — the scope-out
  bullet is present and non-empty.
