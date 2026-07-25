---
category: operations
tags: [scheduled-tasks, cloud, watchdog, claude-code-cloud, observability]
date: 2026-04-21
---

# Cloud Scheduled Tasks -- Silence Diagnosis and Restore Runbook

**Tracking issue:** #2714
**Watchdog:** `apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts` (Inngest cron, post-TR9; the former `.github/workflows/scheduled-cloud-task-heartbeat.yml` was deleted in the TR9 migration)
**Migration context:** PR #1095 (issue #1094) migrated content-generator, campaign-calendar, and growth-audit execution from GitHub Actions to Claude Code Cloud scheduled tasks on 2026-03-25.
**Foundational learning:** `knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md`

## Symptom

The `scheduled-cloud-task-heartbeat` workflow opened a GitHub issue titled
`ops: <task> Cloud scheduled task has not fired in N days (watchdog)` with label
`cloud-task-silence`. OR: operator observed that a twice-weekly / daily / weekly
audit issue has not appeared in the expected window but the workflow is not yet
flagging (cadence below threshold).

The load-bearing signal is **absence of labeled audit issues**, not "the
workflow failed" — these tasks produce a `[Scheduled] <task> - <date>` issue on
every successful run (and a `FAILED` / `FAIL Citations:` issue on every errored
run). **Silence = neither success nor failure issue was created** = the task
did not run at all.

## When NOT to use this runbook

- **Task ran and errored.** A `FAILED` issue exists with the task's label. The
  watchdog correctly treats this as a signal (the task fired; fix the error
  inside the prompt, do not re-diagnose scheduling). Follow the prompt-fix
  procedure in `2026-04-03-content-cadence-gap-cloud-task-migration.md`.
- **Task ran manually.** `workflow_dispatch` runs also produce labeled audit
  issues, so the watchdog's label-based query counts them as signal. Manual
  runs mask schedule drift — the next scheduled fire is still the authoritative
  check.
- **Label exists but has never been applied (never-produced grace).** When a
  task in `TASK_INVENTORY` has produced **zero** `scheduled-<task>` issues ever
  (the issues query succeeds and returns no rows), the watchdog reports it as
  `pending-first-run`: it emits a Sentry **warning** (`warnSilentFallback`,
  `op: task-pending-first-run`, non-paging) and does **not** flag silence — so no
  `[cloud-task-silence]` GitHub issue is filed and any stale one is auto-closed.
  This is correct for a newly-migrated producer before its first scheduled fire.
  **Worked example (#4875):** `legal-audit` migrated GHA→Inngest on 2026-05-25;
  its first real quarterly fire is 2026-07-01, so it is `pending-first-run` until
  then. Once it fires, the normal 95-day threshold applies. The grace is the
  zero-rows arm ONLY — an API error (`catch`) or an issue with an unparseable
  `created_at` (NaN parse) still flags `silent: true` (those are real anomalies,
  not pending tasks). Liveness for the pre-first-fire window is covered by the
  task's own per-function Sentry cron monitor, not this watchdog.

## Task Inventory

**The heartbeat monitors ONLY output-PRODUCING scheduled tasks** — tasks whose
Inngest cron function actually creates a `scheduled-<task>`-labeled issue. Its
single signal is: *"did this task produce its expected `scheduled-<task>` issue
artifact within its cadence window?"* (`TASK_INVENTORY` in
`apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts`).
Thresholds are derived from each task's real cron cadence + one cadence-cycle of
slack; see Threshold Derivation below.

| Task | Execution surface | Cron (UTC) | Audit label | Threshold (days) |
|------|-------------------|-----------|-------------|------------------|
| content-generator | Inngest cron | `0 10 * * 2,4` (Tue+Thu) | `scheduled-content-generator` | 9 |
| legal-audit | Inngest cron | `0 11 1 1,4,7,10 *` (Quarterly) | `scheduled-legal-audit` | 95 |
| competitive-analysis | Inngest cron | `0 9 1 * *` (Monthly 1st) | `scheduled-competitive-analysis` | 40 |
| community-monitor | Inngest cron | `0 8 * * *` (Daily) | `scheduled-community-monitor` | 3 |
| roadmap-review | Inngest cron | `0 9 * * 1` (Weekly Mon) | `scheduled-roadmap-review` | 9 |

### Excluded NON-PRODUCERS and CONDITIONAL producers (do not re-add)

These scheduled tasks run on their own Inngest crons but do **not**
unconditionally create a `scheduled-<task>` issue, so the heartbeat's
label-presence signal can never reliably observe them. Re-adding any of them is
wrong: a pure non-producer would sit in `pending-first-run` forever (a permanent
daily `op: task-pending-first-run` Sentry warning that never graduates to a real
first fire), and a conditional producer would either false-fire on its legitimate
quiet cycles or mask genuine multi-cycle silence. They were removed deliberately:

| Task | Why it is not a reliable producer |
|------|---------------------------------------------|
| daily-triage | Labels existing issues only; its prompt forbids `gh issue create`. |
| ux-audit | **Conditional/best-effort producer (#5199, restored live):** files capped `scheduled-ux-audit` issues when it finds UX decay, but a clean run legitimately files zero (caps + dedup). Heartbeat is liveness-not-success (mirrors bug-fixer #4727), so issue-presence is the wrong silence signal. |
| bug-fixer | Opens `bot-fix/*` PRs; never attaches a `scheduled-bug-fixer` label to an issue. |
| strategy-review | **Conditional/idempotent producer (#4874):** opens an issue ONLY per knowledge-base file needing review (title-dedup, skips `up_to_date`), so a quiet week with everything up-to-date legitimately yields zero issues. Issue-presence is the wrong silence signal. |

**Liveness for these (and every cron) is covered separately** by the
per-function Sentry cron monitors (see Self-healing below and **#4708**) — the
heartbeat was never their liveness signal. For strategy-review specifically, the
liveness signal is the Sentry cron monitor `scheduled-strategy-review`. Do NOT
"restore" any of them to `TASK_INVENTORY` to regain coverage; that coverage
already exists in Sentry.

The heartbeat does **not** and **cannot** use Inngest `/v1/*` run-history as a
liveness signal: that introspection API is loopback-gated and unreachable from
the app container (proven in #4708 — see the loopback note in Self-healing
below). The "did the cron fire" question belongs to the per-function Sentry
monitors; this watchdog answers only the orthogonal "did it produce output".

## Diagnosis Checklist

Work hypotheses in order; each has a cheap verification step.

### H6 — Sub-agent auth inheritance (check FIRST if prompt invokes `/soleur:*` skills)

Cloud Routine sub-agent sessions (spawned by `/soleur:content-writer --headless`, `/soleur:social-distribute --headless`, or any other `/soleur:*` skill invocation inside the routine prompt) do NOT inherit GitHub MCP / Doppler auth from the top-level routine session. Any `gh pr create` / `gh issue create` / `gh pr merge` call made after a sub-agent returns operates in an unauthenticated context and silently fails. The Cloud Routines UI still reports "Success" because the MCP loop terminated cleanly.

**Signature (load-bearing):** run history shows SUCCESS rows in the silence window, BUT `gh pr list` and `gh issue list` scoped to the same date range both return `[]`. Content files may have been generated locally and branches may have been pushed via the git proxy — but no GitHub API side effects occurred.

**Verify (do this BEFORE H1):**

1. Cross-check the routine's run history against `gh pr list --state all -L 200 --search "created:<silence-start>..<silence-end>"` and `gh issue list --state all -L 200 --search 'created:<silence-start>..<silence-end> "<label>"'`. If the routine shows runs but GitHub shows zero artifacts → H6 confirmed.
2. Open a single SUCCESS-marked session in Claude Code UI and scroll to the end. Look for model-output strings: `"Doppler returned Forbidden"`, `"GitHub MCP tools unavailable"`, `"gh CLI unauthenticated"`, `"git proxy handles only git operations"`.
3. Compare against a peer routine (e.g., Daily Issue Triage) that invokes `gh` directly from top-level prompt — if peer succeeds and target fails, the sub-agent boundary is the differentiator.

**Restore (H6):**

Revert to GitHub Actions scheduling (the only reliable fix — Cloud Routines do not expose a way to pass auth into sub-agent sessions). Mirror the pattern from Growth Audit rollback PR #2050 / Content Generator rollback PR #2744:

1. In `.github/workflows/<task>.yml`, uncomment the `schedule: - cron: ...` block that was disabled during the #1095 Cloud migration.
2. Via `claude.ai/code/routines/<id>`: toggle Active → off, rename to `<Task Name> (DISABLED — migrated back to GHA)` for historical reference.
3. After PR merge, trigger a manual `gh workflow run <task>.yml` to verify the restored GHA path end-to-end.

**Affected tasks (as of 2026-04-21):** content-generator (this PR), growth-audit (#2050 — already reverted), community-monitor (currently Paused, H6 remediation pending if/when re-enabled).

**Why this is H6 not H1:** H1 assumes the routine is paused/deleted/orphaned — visible in Cloud UI as Inactive or missing. H6 presents as Active + running on schedule + UI-reported Success. The runbook's original H1-H5 set was authored from the pre-rebrand "Scheduled Tasks" model; H6 emerged from the #2742 diagnosis after the UI's rename to "Routines". See `knowledge-base/project/learnings/2026-04-21-cloud-routine-subagent-auth-inheritance-H6.md` for full diagnosis.

### H1 — Cloud task paused, deleted, or orphaned (most likely)

The Cloud task at `claude.ai/code` may have been paused during a failed run,
deleted during cleanup, or orphaned when the authenticated session expired.

**Verify:**

1. Log in to `claude.ai/code`.
2. Open the `soleur-scheduled` environment.
3. List tasks. Confirm the expected task exists with correct schedule and
   status `active`.

**Restore (H1):**

- If paused: un-pause in the UI.
- If deleted: re-create from the prompt preserved in
  `.github/workflows/scheduled-<task>.yml` (the GHA YAML was intentionally kept
  for rollback per migration spec TR5). Adapt the prompt per the 2026-04-03
  learning (frontmatter instruction must be present).
- If orphaned: re-authenticate the Cloud session; re-save the task if needed.

### H2 — Task runs but fails fast before the audit-issue step

A prompt-level error (plugin marketplace load, missing doppler CLI, invalid
queue format) may abort the task before the `create audit issue` step is
reached, producing zero artifacts.

**Verify:** In the Cloud task UI, inspect the last ~30 run logs. Look for
invocations during the silence window with non-zero exit, and read the first
error line.

**Restore (H2):** Fix the prompt's failure path so any abort path still creates
a labeled audit issue BEFORE exiting. Mirror the `STEP 1b / STEP 2 / STEP 3 /
STEP 4` early-exit guards in `scheduled-content-generator.yml` for parity.

> **content-generator has a handler-level fallback (#4960, PR adding
> `ensure-audit-issue`).** Prompt-level guards only cover terminations that
> reach a prompt step — a mid-eval crash, an upstream Anthropic API 500 that
> kills `claude --print`, or a max-turns kill bypasses every prompt step and
> still produces nothing. `cron-content-generator.ts` now runs a handler-level
> `ensure-audit-issue` step AFTER the output-aware `verify-output` check: when
> no `scheduled-content-generator` issue exists in the run window, the handler
> itself files a self-reporting FAILED `[Scheduled] Content Generator - <date>`
> issue (carrying `exitCode` / `durationMs` / redacted `stdoutTail`) so the run
> is never silent. So for content-generator specifically, a silent window now
> means the **handler fallback ALSO failed** — check Sentry for
> `op: ensure-audit-issue-failed` (the GitHub-create itself erred), not just the
> prompt. The 8 other always-create producers still rely on the prompt-only
> guard; generalizing this fallback cohort-wide is a tracked follow-up.

> **bwrap bash-sandbox userns failure was a recurring H2 cause — now removed
> from the cron path (#5000/#5004).** The cron eval substrate spawns
> `claude --print` whose `Bash` tool calls ran inside a bwrap OS sandbox. When
> the cloud runner's kernel `apparmor_restrict_unprivileged_userns` drifted 0→1,
> bwrap could not acquire a user namespace, every `Bash` call failed, and the
> prompt never reached its `gh issue create` / `git push` step — so the
> handler-level fallback self-reported FAILED (#5000 growth-audit, #5004
> roadmap-review, 2026-06-08). The host-side sysctl fix (#4932 boot-persistent
> `bwrap-userns-sysctl.service`) recurred 4 days later, proving the host path is
> not durable for the cron. **Durable fix:** the cron's settings overlay
> (`DEFAULT_CLAUDE_SETTINGS` in
> `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`)
> now sets `sandbox.enabled: false` (drops the bwrap dependency entirely —
> host-independent, immune to sysctl drift) paired with
> `permissions.defaultMode: "bypassPermissions"` (restores the headless bash
> auto-approval the sandbox previously provided via `autoAllowBashIfSandboxed` —
> the pairing is load-bearing; sandbox-off ALONE blocks every `gh`/`git`
> command on an unanswerable prompt). This is the runtime overlay written into
> each ephemeral cron workspace — NOT the repo-root `.claude/settings.json`,
> which governs interactive dev sessions and intentionally stays
> sandbox-enabled. Post-fix, a bwrap host drift can no longer silence a
> producer; the host sysctl (#4932) + non-blocking drift detector (#4944) remain
> as defense-in-depth for any NON-cron sandbox consumer (e.g. the user/agent
> workspace via `server/workspace.ts`). So a post-fix FAILED self-report whose
> `stdoutTail` still names `bwrap` / `Operation not permitted` / `/proc` would be
> a genuinely new regression, not this class.

### H3 — Doppler `prd_scheduled` service token rotated or revoked

Doppler service tokens are per-config. If the `prd_scheduled` service token was
rotated between fires, the Cloud setup script's `eval $(doppler secrets
download ...)` silently exports an empty environment and every subsequent
invocation fails before reaching the audit-issue step. See
`plugins/soleur/skills/ship/references/ci-workflow-authoring.md` for the full
authoring rule (use config-specific GitHub secret names like
`DOPPLER_TOKEN_PRD_SCHEDULED`, never bare `DOPPLER_TOKEN` — service tokens
silently ignore the `-c` flag).

**Verify:** `doppler configs tokens --project soleur --config prd_scheduled`.
Confirm a non-revoked token exists and its value matches the Cloud task env
var.

**Restore (H3):** Rotate the Doppler token, update the Cloud task env var,
dry-run the task.

### H4 — Concurrency deadlock / rate-limit suppression

`claude.ai/code` rate-limits concurrent task invocations. A hung prior
invocation can suppress subsequent fires. (Migration spec TR3 called this out;
monitoring was never implemented.)

**Verify:** Cloud task run history shows suppressed/skipped fires explicitly.

**Restore (H4):** Cancel stuck invocation(s). Re-queue. File a tracking issue
if this recurs — this is the ceiling case for the current deployment and
warrants a 2nd-gen Cloud task definition strategy.

### H5 — Task prompt parses a file whose format changed

The prompt's STEP 1 for content-generator parses
`knowledge-base/marketing/seo-refresh-queue.md`. A malformed row (missing
`generated_date` annotation, table-column drift) can loop the task on a parse
error.

**Verify:** `git log --oneline --since=<silence-start> -- knowledge-base/marketing/seo-refresh-queue.md`
and compare row formats against the prompt's expected pattern.

**Restore (H5):** Fix the file format. Re-run the task.

### H7 — GHA-scheduled-task max-turns starvation

GHA-scheduled tasks (campaign-calendar, competitive-analysis, roadmap-review,
growth-execution, seo-aeo-audit, daily-triage) invoke
`anthropics/claude-code-action` with a `--max-turns` budget. If the budget is
too tight for the task's plugin overhead (~10 turns) + task work (per-step
turn estimate) + error buffer (~5 turns), the agent reaches max turns
mid-STEP and the GHA workflow exits with a `failure` conclusion. The
audit-issue step is typically the LAST step (PR persist), so a starved run
produces zero artifacts → silent gap → watchdog flags after threshold.

**Signature:**

- GHA run conclusion: `failure`
- Run log contains: `Reached maximum number of turns (N)`
- Latest audit issue (label-based query) is older than threshold

**Verify:** `grep -E '\-\-max-turns' .github/workflows/scheduled-*.yml`,
read each row, compute against the 2026-03-20 ratio table.

**Fix:** Raise `--max-turns` to peer median (40), and raise
`timeout-minutes` proportionally (≥ 0.75 min/turn). See
`knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md`.

**Reference incident:** PR #2974 — campaign-calendar at `--max-turns 20`
failed on 2026-04-27 with 3 overdue items to file (#2968/#2969/#2970);
issue #2968 was an exact-title duplicate of the still-open #2146 (filed
2026-04-13), which motivated the STEP 2 dedup logic. The schedule-fire on
2026-04-20 ran at the wall (`num_turns: 21`) and produced no audit issues,
triggering the watchdog (#2896) on 2026-04-25. Fix raised budget to
`--max-turns 40` + `timeout-minutes: 30` (0.75 min/turn ratio) and added
STEP 2 dedup + STEP 2.5 heartbeat issue.

### H8 — Frontmatter parser truncates multi-colon values (`awk -F': '`)

Workflow STEP 2 dedup logic compares a frontmatter-derived title against
existing-issue titles via `gh issue list --state open -L 200 --search "\"$CANONICAL_TITLE\" in:title"`.
If the parser truncates the title at an inner `: ` or leaves a trailing
quote artifact, the search returns no match — dedup misfires and a fresh
duplicate issue is filed each run. Two failure modes share the root cause:

1. **`awk -F': '` field-split.** Sets the awk Field Separator to `: `;
   `$2` returns only the chunk between the first and second `: `. A title
   like `"Show HN: Soleur — agents that call APIs"` parses as `Show HN`.
2. **`sub(/^"|"$/, "", s)` regex alternation.** POSIX `sub()` replaces
   ONE match. Alternation `^"|"$` matches the leading `"` first; the
   trailing `"` survives untouched. `Agents That Use APIs, Not Browsers"`
   carries the trailing quote into the canonical title.

**Signature:**

- New audit issues filed with titles missing inner-colon content
  (`[Content] Overdue: Show HN (was scheduled for …)`).
- New audit issues with trailing `\"` artifact in the canonical title.
- Existing canonical issues remain open in parallel — DEDUP counter
  never increments for those slots.

**Verify:**

```bash
for f in knowledge-base/marketing/distribution-content/*.md; do
  title=$(awk -F': ' '/^title:/{sub(/^"|"$/,"",$2); print $2; exit}' "$f")
  echo "$(basename "$f") | [$title]"
done | grep -E '\["?(Show HN|[^"]*"$)'
```

Any line with `[Show HN]` (truncated) or `…"]` (trailing-quote) is broken.

**Fix:** Replace the FS-based parser with `match() + substr()` and use
TWO `sub()` calls per quote style:

```bash
TITLE_RAW=$(awk 'match($0, /^title: ?/) {
  s = substr($0, RLENGTH + 1)
  sub(/^"/, "", s); sub(/"$/, "", s)
  sub(/^'\''/, "", s); sub(/'\''$/, "", s)
  print s; exit
}' "$FILE")
```

`match()` + `substr()` are POSIX awk and run on `mawk 1.3.4` (GHA
`ubuntu-latest` default), `gawk`, and BSD `nawk`. Fix applies anywhere
a workflow extracts a frontmatter scalar — copy this template instead
of re-deriving an FS-based parser.

**Limitations:** does NOT handle YAML block scalars (`title: >-`) or
multi-line folded strings. The corpus does not currently use them; if
a future content file does, audit the parser before merging.

**Reference incident:** issue #2987 — campaign-calendar run 25043177327
(2026-04-28) filed duplicates #2982/#2983/#2984 against existing
canonical audits #2146/#2969/#2970. Root cause: STEP 2 step (a) inline
parser carried the FS-based form forward from PR #2974. Fixed in
PR #2995 (closes #2987); duplicates closed as duplicate-of-bug
post-merge per `wg-when-fixing-a-workflow-gates-detection`.

### H9 — Inngest server desync after rapid deploy churn (Inngest-fired crons only)

When the web-platform container is redeployed 10+ times in a short window
(e.g., merging a large TR9 batch), each restart triggers an Inngest SDK
function sync via PUT to `/api/inngest`. The self-hosted Inngest server
(`inngest-server.service`, SQLite storage at `/var/lib/inngest/`) reconciles
its cron scheduler state on each sync. Two failure sub-modes exist:

> **#4652 update — polling now auto-recovers both sub-modes.** The server
> ExecStart runs with `--poll-interval 60 --sdk-url http://127.0.0.1:3000/api/inngest`
> (`inngest-bootstrap.sh`), so it re-syncs AND re-plans functions from the app's
> serve manifest within **≤60s** automatically — for BOTH H9a and H9b, with no
> restart. The restart path is now a **backstop** for when polling itself is
> broken (app `/api/inngest` down, poll loop wedged), not the routine fix.

**H9a — Function deregistered (full desync).** A transient loopback HTTP
failure during the Next.js container restart causes the sync response to
be empty or incomplete. The Inngest server drops the affected function(s)
from its registry entirely. Result: cron trigger never fires — until the next
poll (≤60s) re-syncs the function from the SDK manifest.

**H9b — Cron scheduler re-planning failure (partial desync).** The function
IS registered (appears in `/v1/functions`) but the cron trigger was not
re-planned in the scheduler's plan table. This happens when the function
registry write succeeds but the scheduler plan write fails silently (e.g.,
SQLite write lock contention during a rapid sync burst). Result: function
is registered, but cron never fires — until the next poll (≤60s) re-plans the
cron trigger from the SDK manifest.

**Distinguishing H9a from H9b:**

```bash
# If this returns empty → H9a (function missing from registry)
# If this returns the function with triggers → H9b (registered but not scheduled)
curl -s http://127.0.0.1:8288/v1/functions | \
  jq '.[] | select(.slug == "<function-slug>") | {slug, triggers}'
```

**Signature:**

- Sentry cron monitor reports missed check-in
- The affected function is Inngest-fired (not GHA-fired)
- Other Inngest-fired crons (daily-triage, bug-fixer, oauth-probe) may
  or may not be affected — check all cron-fire timestamps
- Recent deploy burst visible in `gh run list --workflow=web-platform-release.yml`
  (10+ deploys in the 48h preceding the miss)
- Sentry heartbeat env vars are present (eliminates H3/Hypothesis D)

**Verify:**

1. Cross-cron health: `cat /var/lib/inngest/cron-fires/scheduled-*.json | jq .last_ok_at`
2. Function registry: `curl -s http://127.0.0.1:8288/v1/functions | jq length` (expect 40)
3. Server health: `journalctl -u inngest-server.service --since "48h ago" | grep -iE "oom|kill|restart|error|sync"`

**Restore (H9):**

> **#5159 reframe — a standalone inngest restart DE-PLANS crons.** Restarting
> `inngest-server.service` on its own wipes the cron scheduler plan; the SDK does
> NOT re-push on a restart (it synced once at its own boot and the server's
> persisted SQLite still lists the app registration, so a loopback
> `PUT /api/inngest` returns `modified:false` and re-arms nothing — proven #5159,
> live-confirmed `inngest_register_http:200, inngest_register_modified:false,
> inngest_crons:{}`). Crons re-arm ONLY via (a) **restarting the web-platform
> container** (a redeploy, or `docker restart soleur-web-platform`) — the app's
> disconnect+reconnect makes the inngest-server re-discover it on the next poll
> and re-arm the cron schedule (this is reconnection-driven; the SDK sets no
> `appVersion`, so it is NOT a version bump — it is the fresh app boot the server
> treats as a new registration, which is why the old `docker restart` step
> worked), or (b) the server's `--poll-interval` self-heal (~minutes, automatic).
> So do NOT reach for `restart-inngest-server.yml` to recover de-planned crons —
> it cannot re-arm them.

**Primary (immediate) — redeploy / restart web-platform.** Restarting the
web-platform container makes the freshly-booted app reconnect; the inngest-server
re-discovers it and re-arms the cron scheduler at once (reconnection-driven — the
app sets no `appVersion`). From any machine with `gh` auth (no SSH), re-run the
latest release (it restarts the container):

```bash
# Re-run the latest web-platform release — restarting the app container is what
# forces the inngest-server to re-discover the app and re-arm crons. Then watch
# deploy-status. (SSH fallback if the workflow is unavailable: `docker restart
# soleur-web-platform`.)
gh run rerun "$(gh run list --workflow=web-platform-release.yml -L1 --json databaseId -q '.[0].databaseId')"
```

**Secondary (automatic, ~minutes) — wait for the `--poll-interval` self-heal.**
With `--poll-interval 60` the server re-syncs/re-plans a dropped (H9a) or
de-planned (H9b) function from the app's `/api/inngest` manifest on its next poll
with no action. **To confirm recovery WITHOUT host access
(`hr-no-dashboard-eyeball`/no-SSH):** watch the affected `scheduled-*` Sentry
cron monitor flip back to `ok` (query the Sentry Crons monitor-list API). The
on-host loopback re-query
`curl -s http://127.0.0.1:8288/v1/functions | jq '[.[]|select(.triggers[]?.cron)]|length'`
(>=1 with the affected cron present) is an on-host confirmation aid only.

> **Note on `restart-inngest-server.yml`:** the workflow restarts
> `inngest-server.service` and gates on `/health` (process liveness); its
> cron-plan check is **advisory** (#5159) — it polls `/v1/functions` best-effort
> and reports success even if no cron is re-armed yet, because a standalone
> restart cannot re-arm crons. Use it to recover a *dead* `inngest-server`
> process, NOT to recover de-planned crons (redeploy or wait-for-poll, above).

**Manual fallback (SSH required — only if the no-SSH paths above are themselves unavailable):**

1. Restart `inngest-server.service`: `sudo systemctl restart inngest-server.service` (NOTE: this de-plans crons; it only recovers a wedged process — crons re-arm via the redeploy or poll below, NOT via this restart)
2. Wait 30s for SQLite reinitialisation, then restart the web-platform container (`docker restart soleur-web-platform`, or the redeploy above) — the app's reconnect makes the inngest-server re-discover it and re-arm crons. A loopback `PUT /api/inngest` against the still-running app will NOT (it returns `modified:false`, #5159)
3. Verify function registry: `curl -s http://127.0.0.1:8288/v1/functions | jq '[.[] | .slug] | sort | length'` (expect 41)
4. Manual trigger to confirm end-to-end: `curl -X POST http://127.0.0.1:8288/e/<event-name> -H "Content-Type: application/json" -d '{"name":"<event-name>","data":{}}' -H "Authorization: Bearer ${INNGEST_EVENT_KEY}"`
5. Verify Sentry check-in: wait for the next natural fire or check manually via Sentry API

**Reference incident:** 2026-05-27 `scheduled-community-monitor` missed
check-in (Sentry incident #5010688). Last successful check-in
2026-05-25T11:56:14Z. Preceded by 15+ web-platform deploys in a 24h window
(TR9 Phase 2 merge burst) and a function-count jump from ~18 to 40. Sentry
alert triggered by `auth-callback-no-code-burst` was coincidental (unrelated
issue alert type).

**Preventive guard:** `function-registry-count.test.ts` asserts route.ts
function count, cron-file ↔ route.ts parity, and SENTRY_MONITOR_SLUG ↔
cron-monitors.tf parity at CI time. This is a *build-time* source-parity check —
it cannot detect a *runtime* desync (see the self-healing watchdog below, which
does).

### Self-healing (automated — primary path, no SSH)

**The H9 self-heal is now `--poll-interval 60` (#4652), not the watchdog.** The
self-hosted server polls the co-located app's `/api/inngest` manifest every 60s
and re-syncs (H9a) AND re-plans (H9b) any dropped/de-planned function within one
interval, with no restart. This is the automatic, no-operator-action repair for
both sub-modes.

**Alerting** is the per-function Sentry cron monitors: each monitored cron has
its own `scheduled-*` monitor with `failure_issue_threshold`, so a cron that
stops checking in pages on its own (that is how the original #4650 regression —
`scheduled-community-monitor` / `scheduled-gh-pages-cert-state` missed check-ins
— was caught). Read any monitor's state via the Sentry Crons API (no SSH):

```bash
curl -s -H "Authorization: Bearer $SENTRY_API_TOKEN" \
  "https://sentry.io/api/0/organizations/$SENTRY_ORG/monitors/?per_page=100" \
  | jq '.[] | {slug, envs: [.environments[]? | {name, status, lastCheckIn}]}'
```

**The `cron-inngest-cron-watchdog` function is RETIRED to a liveness-only beacon
(#4682).** Its original design queried the server's `/v1/functions` registry to
classify MISSING/UNPLANNED crons and manual-trigger/restart to repair — but that
introspection API is **loopback-gated** on the inngest server: from the app
container `/health` returns 200 yet `/v1/functions` returns 404, while the host's
`127.0.0.1:8288/v1/functions` returns 200 (confirmed via the #4682 `/health`
probe). A containerized watchdog therefore can never read the registry, and the
self-heal it provided is redundant with polling + the per-function monitors
above. It now just posts an `ok=true` heartbeat to `scheduled-inngest-cron-watchdog`
proving the cron scheduler fired it (a coarse substrate-liveness signal; if the
whole scheduler dies, this monitor goes missed and pages). It no longer reads the
registry, fires manual-triggers, or restarts. The `inngest-watchdog-restart-dispatch.yml`
workflow + the exported heal/restart helpers in the watchdog module are now
dormant (cleanup tracked separately).

The manual SSH fallback below is retained as a **last resort** only
(`hr-no-ssh-fallback-in-runbooks`); polling + the per-function monitors + the
`restart-inngest-server.yml` workflow (above) are the primary paths.

### H10 — Anthropic credit exhausted / operator key invalid (whole-fleet stall, #5674)

When the operator `ANTHROPIC_API_KEY` cannot do work, EVERY claude-eval cron
no-ops at once. Before #5674 this was silent (green monitors, `status=completed`
rows). Now two signals surface it:

**Primary — the hourly canary `cron-anthropic-credit-probe`** (Sentry monitor
`scheduled-anthropic-credit-probe`). It sends a 1-token ping on the operator key
each hour and pages on the CLASSIFIED failure:

- `op=anthropic-credit-exhausted` + monitor RED → **operator Anthropic credit is
  zero.** Top up the balance at `console.anthropic.com → Billing`. The fleet
  self-recovers on the next scheduled fire once credit is restored (no restart).
- `op=anthropic-key-invalid` + monitor RED → **the operator key is invalid /
  revoked.** Rotate `ANTHROPIC_API_KEY` in Doppler (`prd`) and redeploy.
- A transient (`429`/`500`/`529 overloaded`/network) does NOT page as
  credit-exhausted — the probe re-throws so Inngest retries; the missed-checkin
  margin (30 min) backstops a genuine outage. So a single `scheduled-anthropic
  -credit-probe` missed check-in (not a red page) is "Anthropic was briefly
  unreachable," not "credit gone."

**Secondary — classify-fatal on the eval crons.** A claude-eval cron whose tail
matches a FATAL class (credit/auth/spawn-fault/timeout) now flips its OWN monitor
red (`op=claude-eval-fatal`) and writes a `routine_runs.failed` row with the
scrubbed reason. Query `routine_runs` (Supabase) for `error_summary ILIKE
'%credit balance%'` to confirm the window.

> **Classify-fatal expectation (do NOT misread the monitors):** a claude-eval
> non-zero exit does NOT always page. A **benign** non-zero exit (`claude --print`
> hitting max-turns with no artifact — a healthy, frequent outcome) deliberately
> stays GREEN (`op=claude-eval-nonzero-noop`/`-nofix`, a non-paging WARNING) and
> records its reason in `routine_runs.error_summary` only. Only the FATAL classes
> flip red. So "the agent-native-audit monitor is green" does NOT mean "claude
> filed an issue this run" — it means "no fatal-class failure." This is the
> evidence-backed reversal of a naive flip-all (the #4730/#4727 daily-false-page
> incident). See ADR-033 I8.

> **Margin-backed red flip:** `postSentryHeartbeat` swallows its own POST failure
> (`_cron-shared.ts`), so the red flip is missed-checkin-margin-backed, not
> POST-guaranteed — the Sentry-cron missed-checkin is the backstop signal.

**No balance endpoint exists.** Anthropic exposes no remaining-credit API, so the
canary alerts AT exhaustion (within one hourly interval), not before. True
pre-exhaustion spend-vs-budget alerting is a tracked follow-up (`Ref #5674`,
needs a new `sk-ant-admin` secret + an operator `ANTHROPIC_MONTHLY_BUDGET_USD`).

**After a PROLONGED (multi-day) outage, re-enable the monitor — credit-restore
alone is not enough.** Per Sentry's documented cron-monitor behavior, a monitor
left unhealthy for several days is auto-muted, then disabled (the "we'll
automatically mute or disable them in a few days" warning email). A **disabled**
monitor ignores even a recovery `?status=ok` check-in until it is re-enabled, so
restoring credit does NOT by itself clear the alert. This is NOT a Terraform
change — the `jianyuan/sentry` provider exposes no mute/status
attribute — so check and un-mute/re-enable via the Sentry REST API. This flow
needs a WRITE-capable token: use the IaC token `SENTRY_IAC_AUTH_TOKEN`
(`project:admin` / `alerts:write`) in Doppler `soleur/prd_terraform` — NOT the
read-scoped token in the read-only examples above:

```bash
# Read current state (status: active|disabled, isMuted: true|false).
# ADR-031: for the EU org, prefer the regional host
#   https://${SENTRY_ORG}.sentry.io/api/0/...  — the bare sentry.io host can
#   silently 401 via the slug-rewrite / activeorg-cookie bug.
doppler run -p soleur -c prd_terraform -- bash -c \
  'curl -s -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" \
    "https://sentry.io/api/0/organizations/$SENTRY_ORG/monitors/scheduled-community-monitor/" \
    | jq "{status, isMuted}"'
```

If `status` is `disabled` or `isMuted` is `true`, re-enable with a `PUT` to the
same monitor URL (`{"status":"active","isMuted":false}`) using the same token;
fall back to the Sentry dashboard ONLY on a confirmed API-write failure (record a
`playwright-attempt:` evidence line). (The GET above is live-verified; the
PUT/un-mute form is unverified as of writing — it should succeed under
`project:admin`, but treat a 403 as the dashboard-fallback trigger.) Sibling
claude-eval monitors (roadmap-review, content-generator, …) may be in the same
state after a fleet-wide outage — check each. Then follow the **Restore
Procedure** below to confirm the next check-in goes green.

### H11 — `missed` (not `error`) on a claude-eval cron whose digest WAS produced (delivery/timing, #5728)

A monitor shows daily `missed` check-ins while the cron's GitHub digest issue WAS
filed each of those days (real digests, not the FAILED self-report fallback). The
check-in layer and the GitHub-digest layer **disagree**, and Sentry's alert keys
off the check-in layer. This is a **delivery/timing** defect, NOT a work failure —
and it is **distinct from H10** (H10 is `?status=error`, a delivered check-in that
reports failure; H11 is `missed`, where **no check-in arrived at all**).

**Why `missed` ≠ `error` is the load-bearing distinction.** Sentry generates
`missed` (job didn't check in by the deadline) and `timeout` (exceeded
`max_runtime`) **server-side** — they are NOT client-reported statuses. The cron
only ever POSTs `?status=ok` or `?status=error`. So `missed` means the
`sentry-heartbeat` step **literally never executed** (the single terminal POST was
never sent). `resolveOutputAwareOk` *returns* false (never throws) on
no-output/non-zero-exit and the heartbeat then posts `?status=error` — so a
`missed` is never "the eval failed"; it is "the run never reached its heartbeat."

**Four causes (discriminate per-day AND per-attempt — a single day can be more than one):**

- **H11a — mid-run SIGKILL** (container swap / deploy / OOM) during the long
  (~50-min) `claude-eval`, before the terminal heartbeat. Signature: **zero
  `routine_runs` terminal rows** for that day (the run-log middleware's terminal
  write is skipped too) while sibling crons logged normally + `missed`. **This is
  the dominant 2026-06-13→06-21 cause (#5728 Phase 0).** No in-process fix exists
  (no catch runs on a SIGKILL); the remedy is the **graceful cron drain before
  container swap (ADR-078 / #5686)**, which reduces the kill frequency. `missed`
  is an honest signal for a genuinely killed run.
- **H11b — a throw before the heartbeat step.** A throw inside the handler body
  used to propagate out → the heartbeat step never ran → silent `missed`. **Fixed
  in #5728:** the output-aware cohort now routes the terminal heartbeat through
  `finalizeOutputAwareHeartbeat` (`_cron-shared.ts`) — a throw with no output posts
  a loud `?status=error` on the final attempt (or skips + retries on a non-final
  attempt), so a throw is now `error`, never silent `missed`.
- **H11c — swallowed/transient-failed OK POST** (5xx / network / timeout).
  Signature: a `completed` `routine_runs` row co-timed with a
  `feature:cron-sentry-heartbeat op:fetch` Sentry event. **Fixed in #5728:**
  `postSentryHeartbeat` now inspects `resp.ok` and bounded-retries 5xx/network/
  timeout (never a 4xx), bounded well under the 60-min margin, before falling back
  to `reportSilentFallback`.
- **H11d — dispatch/queue delay.** The output-aware crons share one
  `{ scope: "account", key: "cron-platform", limit: 1 }` slot, so an 08:00 fire can
  queue behind another long cron and *start* 30–50 min late, posting `ok` past the
  margin. Signature: `routine_runs.started_at ≫ 08:00` with no kill/throw. (Refuted
  for the #5728 window — siblings dispatched fine, start_lag <65s.)

**Phase-0 three-layer pull recipe (rank by authority; the green layer you read
first is the one most likely lying — see learning
`2026-06-29-cron-health-run-log-green-masks-claude-eval-failure.md`):**

1. **`routine_runs` (Supabase, authoritative liveness+duration).** Read-only SQL
   via Doppler `DATABASE_URL_POOLER` (`:6543`→`:5432` for session-mode multi-stmt;
   the pooler presents a self-signed chain → `ssl:{rejectUnauthorized:false}` for a
   transient verify script). Per day/attempt: `start_lag` (vs 08:00, H11d),
   `duration_ms` (vs 60-min margin, H11a-slow), `status`, **absent rows** (the
   realizable SIGKILL signature — `ended_at` is `NOT NULL` and the middleware writes
   terminal rows only, so the literal "NULL ended_at orphan" cannot exist),
   `error_summary`, `trigger_source`. NOTE: the middleware predates 2026-06-16, so
   earlier days are routine_runs-blind.
2. **Better Stack stdout tail** (`scripts/betterstack-query.sh` under `doppler run
   -p soleur -c prd_terraform` — query creds are in `prd_terraform`, NOT `prd`; see
   `betterstack-log-query.md`). SIGKILL/container-swap markers, the swallowed-POST
   warning, last `sentry-heartbeat` log line per run. CAVEAT: hot-window retention
   is short (~1h) — the incident window is often already aged out.
3. **Sentry check-in timeline** — `GET https://de.sentry.io/api/0/organizations/<org>/monitors/<slug>/checkins/`
   (read-only; EU **regional** host `de.sentry.io` with the org in the path — the
   live-verified shape, mirrored by `scripts/followthroughs/community-monitor-checkin-soak-5728.sh`; ADR-031). Confirms last-ok +
   the `missed`/`error` boundary. The issues/events endpoint needs `event:read`
   scope the monitor-read token lacks — `routine_runs` independently discriminates
   H11c without it.

**Disambiguation summary:** absent `routine_runs` rows + `missed` ⇒ **H11a (kill)**
→ ADR-078's job, not a code fix. `completed` row + POST-fetch Sentry event ⇒
**H11c** → #5728 Phase 1 retry. `duration_ms` > 60 min OR `start_lag` past margin ⇒
**H11a-slow / H11d** → re-evaluate `checkin_margin_minutes` against the worst-case
retry-chain + shared-slot queue wall-clock (never an `in_progress` two-phase
check-in — ADR-033 I8 rejects it). For #5728 the verdict was H11a-dominant, so the
margin was left at 60 (no TF change). Cross-link: H10 (credit/error regime + the
prolonged-mute re-enable via Sentry REST API).

## Restore Procedure (generalized)

Based on the diagnosed H\* above:

1. **Apply the hypothesis-specific fix** (H1: unpause/recreate, H2: prompt
   patch, H3: doppler rotate, H4: requeue, H5: file fix).
2. **Manual dry-run** via "Run now" in the Cloud UI (Cloud tasks) or
   `gh workflow run scheduled-<task>.yml` (GHA tasks).
3. **Verify success signals** (for content-generator — adapt per task):
   - New issue with task's label created.
   - New PR matching the task's conventional-commit title pattern.
   - Distribution/artifact file frontmatter has correct `publish_date`,
     `status`, `channels` (per 2026-04-03 learning).
   - Eleventy build passes (if applicable).
4. **Record diagnosis + restoration** in a comment on the parent tracking
   issue (e.g., #2714 for the 2026-04-21 silence).
5. **Watchdog auto-closes** the `cloud-task-silence` issue on its next fire
   once the audit-issue label reappears below threshold.

## Threshold Derivation

Each threshold is observed-max-natural-gap + one cadence cycle of slack.
Documented here so a future operator can update without re-deriving.

| Task | Cadence | Max natural gap | Threshold | Slack |
|------|---------|-----------------|-----------|-------|
| content-generator | Tue+Thu | 5 days (Thu→Tue) | 9 | +4 days (one missed cycle) |
| legal-audit | Quarterly (1st Jan/Apr/Jul/Oct) | 92 days (Jul→Oct) | 95 | +3 days |
| competitive-analysis | Monthly 1st | ~31 days | 40 | +9 days (one missed month) |
| community-monitor | Daily | 1 day | 3 | +2 days (weekend/transient) |
| roadmap-review | Weekly Mon | 7 days | 9 | +2 days |

**Why content-generator is 9, not 4:** The Thu→Tue gap alone is 5 days, so the
prior `4`-day threshold false-fired on a perfectly on-time week. 9 = one full
cadence cycle (5d max gap) + one missed firing of slack — it surfaces a genuine
two-cycle outage without alerting on a single transient miss.

**Why legal-audit is 95 (headline defect):** legal-audit runs quarterly; the
longest quarter gap is 92 days (Jul 1 → Oct 1). The prior `9`-day threshold
guaranteed a false `[cloud-task-silence]` alert ~9 days into every quarter. 95 =
92-day floor + 3d slack.

**Why community-monitor is 3, not 9:** it is a daily producer, so a 9-day
threshold would let a real 8-day outage go unnoticed. 3 = 1d cadence + 2d slack
(absorbs a weekend / single transient). This is a tightening that improves
true-positive latency, safe because community-monitor genuinely fires daily.

## Updating the Watchdog

The watchdog is now the `cron-cloud-task-heartbeat` **Inngest cron function**
(`apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts`),
not the (deleted, post-TR9) `.github/workflows/scheduled-cloud-task-heartbeat.yml`.

**Eligibility check FIRST — is the task a producer?** Only add a task to
`TASK_INVENTORY` if its cron function actually creates a `scheduled-<task>`
labeled issue (grep its `cron-<task>.ts` for an `octokit … POST /issues` /
`gh issue create` that attaches the `scheduled-<task>` label). If it does not —
a dry-run, a labels-only triage, a PR-only fixer — do **not** add it; its
liveness is covered by its own per-function Sentry monitor instead (see the
Excluded Non-Producers table above).

When a new producing task is added:

1. Add an entry to `TASK_INVENTORY` in `cron-cloud-task-heartbeat.ts` —
   `{ name, label: "scheduled-<name>", maxGapDays }` — with `maxGapDays` derived
   from the task's real cron cadence (Threshold Derivation above).
2. Add matching rows to the Task Inventory and Threshold Derivation tables here.
3. Update the cardinality + threshold assertions in
   `apps/web-platform/test/server/inngest/cron-cloud-task-heartbeat.test.ts`
   (the `toHaveLength(N)`, the `it.each` table, the non-producer guard).
4. Verify the label exists (`gh label list | grep <label>`); create if missing.

When a task is removed: delete its entry from `TASK_INVENTORY`, update the test
assertions, and update both tables here in the same PR — and add it to the
Excluded Non-Producers table if it was removed for being a non-producer.

## Dedup Contract

The watchdog's open-silence-issue lookup and auto-close lookup both depend on
**exact-prefix match against the title template**. Breaking either half of
this contract will cause duplicate issues or missed auto-closes.

- **Title template (load-bearing):**

  ```text
  ops: <task> Cloud scheduled task has not fired in <N> days (watchdog)
  ```

  where `<task>` is the first colon-delimited field of the `TASKS` row in
  `.github/workflows/scheduled-cloud-task-heartbeat.yml` (the task slug,
  e.g., `content-generator`). `<N>` is the computed day count.

- **Dedup token:** `<task>` (the task slug). The watchdog's
  `find_silence_issue()` helper narrows via GitHub search `"<task> in:title"`
  then filters to titles satisfying `startswith("ops: <task> ")`. The
  trailing space is significant — it is what prevents a prefix collision
  between, e.g., `content-generator` and a future `content-generator-v2`.

- **Label contract:** Every watchdog-opened issue carries the
  `cloud-task-silence` label. The helper filters on this label before
  applying the title prefix — removing the label detaches an issue from
  dedup.

## Warnings

- **Do NOT edit the title of an open `cloud-task-silence` issue.** Stripping
  the `ops: <task>` prefix (including the trailing space) or changing the
  `<task>` slug will break dedup and cause the next run to open a duplicate.
  Add a comment instead.
- **Do NOT remove the `cloud-task-silence` label.** The helper filters on
  this label; an issue without it is invisible to `find_silence_issue()`.
- **Task-name prefix collisions are guarded in code, not convention.** The
  helper uses `startswith("ops: <task> ")` so `content-generator` does NOT
  false-match `content-generator-v2`. New tasks can share prefixes, but
  avoid it anyway for human clarity.
- **Label-based query includes manual dispatches.** A `workflow_dispatch` run
  produces a labeled audit issue and counts as signal. If the schedule is
  broken but operators keep running manually, the watchdog will NOT fire.
  Weekly review of the actual schedule (cron vs. dispatch) is the backstop.

## Cron Containment Model (#5018 / #5000 / #5004)

Cron-spawned `claude --print` agents run with the **OS bash sandbox disabled**
(`sandbox.enabled:false` in the substrate's `DEFAULT_CLAUDE_SETTINGS`). This is the
durable fix for the recurring bwrap-userns drift (#4928/#4932) that broke #5000/#5004 —
the cron no longer depends on unprivileged user namespaces. The host sysctl pin
(#4932/#4944) stays only as defense-in-depth for **non-cron** sandbox consumers.

**Containment = a deny-by-default `PreToolUse` hook**, not the sandbox and not
`--allowedTools`. Phase-0 probes (re-verified on the prod-pinned CLI `2.1.79`) proved
headless `claude --print` does NOT fail-close non-allowlisted commands via
`--allowedTools`/`defaultMode` — only a `permissions.deny` rule or a hook blocks, and an
unhooked tool class / crashed hook fails OPEN. So:

- `cron-bash-allowlist-hook.mjs` is registered under a `*` catch-all matcher
  (`buildCronEvalSettings`); it denies everything except a per-cron allowlist
  (`CRON_BASH_ALLOWLISTS`) + inert internal tools, and denies all secret-reads / egress /
  interpreters / argument-injection. Its decision logic is unit-tested
  (`cron-bash-allowlist-hook.test.ts`, 43 adversarial cases).
- A **spawn-time self-test** (`runHookSelfTest`) aborts the cron with a FAILED
  self-report if the hook does not deny a canonical exfil payload — never an unprotected run.
- The token `bypassPermissions` MUST NOT appear in the overlay (the v1 P1-blocked
  exfil primitive). See ADR-033 **I7**.

### Tier-1 vs Tier-2

- **Tier-1** (hook-contained, scheduled): crons whose entire command surface is a finite
  allowlist — `cron-roadmap-review` (#5004); the two #5046 PR-2 restores
  `cron-agent-native-audit` and `cron-legal-audit` (issue-creator allowlists; the hook's
  catch-all now allows `Task`/`Skill`); the #5199 restore `cron-ux-audit` (issue-creator
  bash allowlist PLUS the FIRST per-cron `mcp__playwright__*` allowance — file-driven via
  `CRON_MCP_ALLOWLISTS` + a `browser_navigate` URL-origin guard + `storage-state.json`
  read-deny; see `cron-bash-allowlist-hook.mjs`); and the **seven `mergeMode:"auto"` PR-flow
  crons restored by #5199** — `cron-growth-audit`, `cron-growth-execution`,
  `cron-competitive-analysis`, `cron-seo-aeo-audit`, `cron-content-generator`,
  `cron-campaign-calendar`, `cron-community-monitor`. Each carries a finite, evidence-gated
  `CRON_BASH_ALLOWLISTS` entry (issue/label verbs only — git/gh-pr persistence runs node-side
  via `safeCommitAndPr`; NO `gh api`; eleventy builds defer to CI) and mints
  `DEFAULT_CRON_TOKEN_PERMISSIONS` (contents/issues/pull_requests:write) scoped to
  `[REPO_NAME]`. The gate was the PR-5200 stale-bot-PR watchdog (issue #5138), which landed.
  **Expected degradation under containment:** the containment hook denies `WebFetch`/`WebSearch`
  (raw web egress = the exfil surface it severs), so the web-research-dependent crons —
  `cron-competitive-analysis` (competitor scanning) and `cron-growth-audit`'s seo-aeo live-page
  fetch — produce REDUCED output; the output-aware heartbeat (`resolveOutputAwareOk`) surfaces a
  no-/thin-output run via `scheduled-output-missing` rather than silently greening. This is the
  intended posture, not a bug; restoring full web research would require a separate
  egress-broadening decision (out of scope).
  The #5199 (final) restore is **`cron-bug-fixer`** — the LAST Tier-2 cron, and the only
  one whose commit step lives in a SKILL (`fix-issue`), NOT `safeCommitAndPr`. It is
  therefore EXEMPT from the safe-commit parity migration and its `CRON_BASH_ALLOWLISTS`
  entry legitimately CARRIES git/gh-pr persistence verbs (`git add -- <path>`, `git commit`,
  `git push -u origin`, `gh pr create`/`edit`) — unlike the seven auto-crons above, whose
  persistence runs node-side. It mints `DEFAULT_CRON_TOKEN_PERMISSIONS` scoped to
  `[REPO_NAME]` (write-capable: it pushes + opens PRs). Its gate — that `bot-fix/*` heads
  were OUTSIDE the stale-bot-PR watchdog's age-scan — was closed in this same PR by adding
  `bot-fix/*` to `BOT_PR_HEAD_PREFIXES` (`cron-cloud-task-heartbeat.ts`), atomic: the
  watchdog landed FIRST, then the cron un-deferred.
  Add a cron here by enumerating its prompt's `gh`/`git` verbs into `CRON_BASH_ALLOWLISTS`
  (sub-command granularity, e.g. `gh issue list` NOT `gh issue`; never `git config`/`git
  remote`) and validating end-to-end via `/soleur:trigger-cron`.
- **Tier-2** (`TIER2_DEFERRED_CRONS`): **EMPTY** — all Tier-2 crons have been restored and
  the Tier-2 boundary is fully retired (#5199 closed). `deferIfTier2Cron` remains in the
  codebase as a defensive no-op (an empty set short-circuits `has()` to `false`), so no
  handler call site needs editing; it simply never defers now.

**Promoting a paused cron to Tier-1:** enumerate its verbs → add to `CRON_BASH_ALLOWLISTS`
→ remove from `TIER2_DEFERRED_CRONS` → `/soleur:trigger-cron <cron>` and confirm it produces
its output end-to-end. If the hook denies a needed verb, the run produces no
output → its monitor stays GREEN (heartbeat) but nothing lands — re-check the allowlist.

**Verifying a trigger — the output signal is cron-specific (issue OR PR).** Do NOT assume the
success signal is a `[Scheduled] <task>` *issue*. `roadmap-review` (and any cron with an
auto-fix path) takes the **PR path** whenever it finds something to fix — it opens a roadmap
PR (author `app/soleur-ai`) carrying the review summary in the PR body and files the standalone
issue only when there is nothing to auto-fix (rare for a living roadmap). So when validating a
Tier-1 cron post-trigger, accept **either** a fresh `[Scheduled]` issue **or** a fresh
`app/soleur-ai` PR as proof the cron ran end-to-end through the hook — a PR proves *more* (its
full `git checkout → add → commit → push -u origin → gh pr create` chain succeeded through the
containment). A monitor that watches only for the issue will false-negative on the PR path.
**Why:** AC11 of #5018 — roadmap-review consistently produced PRs (#5053, #5058), never the
issue; the issue-only check timed out despite the containment working perfectly.

## PR Withheld by safe-commit (#5091, #5111)

Since #5111 (completing #5091), **ALL bot cron PR pipelines — 12 callers — persist
handler-side through `safeCommitAndPr`**
(`apps/web-platform/server/inngest/functions/_cron-safe-commit.ts`); the only
exemptions are roadmap-review (hook-guarded Tier-1 self-commit) and bug-fixer
(the fix-issue skill owns its commit step). ADR-054 records the decision; the
parity test (`cron-safe-commit-parity.test.ts`) enforces it. When persistence
cannot complete, the helper mirrors the failure to Sentry and attempts a
**"PR withheld: …"** comment on the run's scheduled issue — diagnosis never
requires SSH. **Comment-channel scope:** only the claude-spawn crons create
issues carrying their `scheduledIssueLabel`; the 5 pure-TS pipelines
(weekly-analytics, compound-promote, content-publisher, content-vendor-drift,
rule-prune) have no labeled issues, so for them the comment never lands
(Sentry op `safe-commit-comment-no-target` records the drop) and **Sentry is
the only failure signal**. Their cron monitors stay GREEN on a persistence
failure (the cron ran; persistence health is signaled via Sentry ops, not
the heartbeat).

**Three merge modes** (per-cron; ADR-054): `auto` — claude-spawn output PRs, auto-merge
armed and required checks gate the merge; `direct` + synthetic check-runs — deterministic
data-refresh PRs (weekly-analytics, content-publisher, content-vendor-drift, rule-prune)
merged immediately after posting the synthetic checks; `none` — compound-promote's
`self-healing/auto-*` human-review drafts (a long-lived open draft is NORMAL for that
cron, not a stall). For `direct` pipelines, Sentry stage `auto-merge` covers BOTH a
failed direct merge AND a failed auto-merge arm — in both cases the PR exists and
needs a manual merge.

**Expected guard fire:** content-vendor-drift re-vendoring a large upstream
restructure can legitimately delete >10 files under its `references/` allowlist —
the deletion guard aborts loudly by design (mass deletion = review-worthy). Use the
`DEFAULT_MAX_DELETIONS` raise path below for that run, then revert.

**Sentry ops** (filter by `fn=<cron-name>`):

| Op | Meaning | Action |
| --- | --- | --- |
| `safe-commit-deletion-guard` | >10 deletions inside the cron's allowedPaths — the #5026 destructive class. The run's diff was discarded. | Inspect the `sample` paths in the event. If the deletions are legitimate (rare; e.g. a big archive), raise `DEFAULT_MAX_DELETIONS` in `_cron-safe-commit.ts` via a reviewed PR. If not, the spawned model misbehaved — read the run's audit issue. |
| `safe-commit-failed` | Any other stage failed (`stage` in the event extra: workspace-lost, status, dirty-index, checkout, add, commit, push, pr-create, auto-merge, unexpected). | `push`/`pr-create`: usually transient GitHub/network or token expiry — the next scheduled run retries from scratch. `dirty-index`: something pre-staged files in the workspace (should be impossible; investigate). `workspace-lost`: a deploy/restart landed mid-run; work is lost, next run redoes it. `auto-merge`: the PR EXISTS but needs a manual merge — the comment names it. |
| `safe-commit-paths-dropped` | The run changed files outside its allowlist; the PR was opened WITHOUT them (the PR body carries a ⚠️ marker listing the dropped sample). | Check whether the dropped paths should be in the cron's `allowedPaths` (widen via PR) or the model wandered out of scope (prompt fix). |
| `safe-commit-issue-comment-failed` | The visibility comment itself could not post. | Diagnosis falls back to Sentry only; no action unless recurring. |
| `safe-commit-comment-no-target` | No open issue carries the cron's `scheduledIssueLabel` — expected for the 5 pure-TS pipelines (see scope note above). | Confirms Sentry is the only signal for this run; no action unless it fires for a claude-spawn cron (whose issue-create step then failed upstream). |
| `safe-commit-direct-merge-fell-back` | A `direct`-mode pipeline's immediate merge failed; auto-merge was ARMED instead. The PR merges when checks pass — or goes silently stale on a later conflict (armed auto-merge disarms without signal; the #5138 watchdog class, which therefore also covers live direct pipelines, not just the Tier-2-dormant auto cohort). | Check the PR: if still open after the checks window, merge manually and investigate why the direct merge was rejected (branch protection drift?). |
| `safe-commit-label-failed` | PR labels could not be applied (advisory metadata — run continued). | For content-vendor-drift this can mean a merged drift PR lacks its `vendor/*` / `compliance/critical` routing labels — re-apply manually if triage depends on them. |
| `safe-commit-check-run-failed` | A synthetic check-run POST failed on a `direct`/`none` pipeline. | The PR may sit open with auto-merge armed against checks that will never arrive — post the missing check-runs manually or merge manually. |

A **no-PR week with a green monitor and no comment** means the run legitimately
produced no committable changes (`no-changes` — visible in app logs as
`safe-commit-no-changes`) — **after confirming the Sentry window is clean**:
for the 5 pure-TS pipelines a persistence failure ALSO presents as green
monitor + no comment, so the inference is only sound when a Sentry query for
`safe-commit-failed` / `safe-commit-deletion-guard` (fn=<cron>) over the run
window returns empty.

## Stale bot PR (#5138)

The `cron-cloud-task-heartbeat` cron (daily, 09:30 UTC) also scans open PRs
whose head branch matches `ci/*`, `self-healing/auto-*`, or **`bot-fix/*`**
(the last added by #5199 when `cron-bug-fixer` was restored) and flags any open
**>48h**. The trigger: a `mergeMode: "auto"` PR whose `enablePullRequestAutoMerge`
**silently disarmed on a merge conflict** (it leaves the PR open with no signal),
or a `direct` pipeline that fell back to arming auto-merge (`safe-commit-direct-
merge-fell-back`) and then stalled on a later conflict. Compound-promote's
`self-healing/auto-*` **drafts are excluded** (human-review-by-design, legitimately
long-lived) — only a NON-draft `self-healing/auto-*` PR is flagged. `bot-fix/*` PRs
(cron-bug-fixer) carry no `scheduled-<cron>` label, so they route **Sentry-only**
(`scheduledLabelFromHead` returns null — there is no owning issue to comment on).

The scan is **orthogonal to the cron monitor**: a stale PR does NOT turn
`scheduled-cloud-task-heartbeat` red (found-work ≠ liveness). The signals are
instead:

| Sentry op (`feature=cron-cloud-task-heartbeat`) | Meaning | Action |
| --- | --- | --- |
| `stale-bot-pr` | An open `ci/*` / non-draft `self-healing/auto-*` / `bot-fix/*` PR has been open >48h. `extra` carries `pr_number`, `head_ref`, `age_hours`, `owning_cron`. Also comments once (deduped by a `<!-- stale-bot-pr:<n> -->` marker) on the owning cron's `scheduled-<cron>` issue when one is open (`bot-fix/*` has none → Sentry-only). | Open the PR. Rebase the head branch to resolve the conflict and let auto-merge re-fire, or close it if obsolete. |
| `stale-bot-pr-scan-failed` | The `GET …/pulls` list call failed — the watchdog **could not scan this run** (it returns `[]`, so no stale PR can be detected until the next run). | Transient GitHub/network or token expiry usually self-heals next run. If it recurs, the watchdog is blind — investigate the installation token / GitHub API status. |
| `stale-bot-pr-comment-failed` | The owning-issue comment POST failed (the `stale-bot-pr` warn still fired — Sentry is the primary signal). | No action unless recurring. |

All three ops route to the operator via the `sentry_issue_alert.stale_bot_pr`
rule (`apps/web-platform/infra/sentry/issue-alerts.tf`) — no dashboard gaze
required. Discoverability without SSH:
`gh api "/repos/jikig-ai/soleur/pulls?state=open&per_page=100" --jq '[.[] | select(.head.ref|startswith("ci/") or (.head.ref|startswith("self-healing/auto-")) or (.head.ref|startswith("bot-fix/")))] | length'`.

## References

- Migration PR: #1095
- Migration plan: `knowledge-base/project/plans/2026-03-24-feat-scheduled-tasks-cloud-migration-plan.md`
- Migration spec: `knowledge-base/project/specs/archive/20260325-003628-feat-scheduled-tasks-migration/`
- Silence-detection plan: `knowledge-base/project/plans/2026-04-21-fix-scheduled-content-generator-cloud-task-silence-plan.md`
- Prior incident learning: `knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md`
- Doppler token-scope learning: `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
- Peer watchdog pattern: `.github/workflows/scheduled-cf-token-expiry-check.yml`
- Authoring conventions: `plugins/soleur/skills/ship/references/ci-workflow-authoring.md` covers the GH-Actions rules that govern this runbook's workflow files (heredoc/indentation, email notifications, JSON-polling `jq -e` guards, pattern-duplication audits). The `gh issue` conventions (verify `--label` against `gh label list`; pass milestone titles, not numeric IDs) are discoverable via `gh`'s own clear errors and additionally cited in the planning skills (`plan/SKILL.md`, `deepen-plan/SKILL.md`, `/soleur:drain-labeled-backlog`).
