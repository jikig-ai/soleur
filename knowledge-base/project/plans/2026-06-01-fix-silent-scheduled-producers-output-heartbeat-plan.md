---
title: "fix: silent scheduled producers — output-aware Sentry heartbeat"
type: fix
date: 2026-06-01
branch: feat-one-shot-cron-silent-producers-output-heartbeat
lane: cross-domain
brand_survival_threshold: aggregate pattern
closes: [4689, 4686, 4684]
references: [4688, 4710, 4708, 4425]
status: draft
---

# 🐛 fix: Restore the four silent scheduled producers + make their Sentry heartbeat reflect actual output

## Problem Statement

The TR9 migration (PRs #4423 / #4412 / #4443 / #4483, merged 2026-05-25→26) moved four scheduled
producers from GitHub Actions cron to Inngest and **deleted the old GHA workflows in the same PRs**:

| Issue  | Function (file)                  | Cron          | Required output (label)            |
| ------ | -------------------------------- | ------------- | ---------------------------------- |
| #4689  | `cron-roadmap-review.ts`         | `0 9 * * 1`   | `scheduled-roadmap-review`         |
| #4686  | `cron-strategy-review.ts`        | (weekly)      | `scheduled-strategy-review`        |
| #4684  | `cron-content-generator.ts`      | (daily/weekly)| `scheduled-content-generator`      |
| #4688  | `cron-competitive-analysis.ts`   | `0 9 1 * *`   | `scheduled-competitive-analysis`   |

All four functions ARE registered (`apps/web-platform/app/api/inngest/route.ts:83,84,101,107`) and the
crons fire, but **none has produced its `scheduled-<task>` labeled GitHub issue since the migration** —
the artifact that `cron-cloud-task-heartbeat` counts. End-to-end output production is broken.

**The silent-failure gap that let this go unnoticed:** each function reports its per-function Sentry
monitor `ok` based on `spawnResult.ok` (claude exit code === 0), **not** on whether the required issue
was actually created:

- `cron-roadmap-review.ts:277` → `ok: spawnResult.ok`
- `cron-competitive-analysis.ts:252` → `ok: spawnResult.ok`
- `cron-content-generator.ts:201` → `ok: spawnResult.ok`
- `cron-strategy-review.ts:632` → `ok: result.ok`

So the per-function monitors stayed green while the producers went quiet. The only signal was the
separate `cron-cloud-task-heartbeat` watchdog's issue-count — exactly the layer this fix should not have
to depend on. This violates `cq-silent-fallback-must-mirror-to-sentry` and
`hr-observability-as-plan-quality-gate`: a green monitor that does not reflect the function's actual job
is a dark observability surface.

**Broader finding (plan-time survey):** the sibling output-producing crons `cron-growth-audit.ts`,
`cron-ux-audit.ts`, `cron-seo-aeo-audit.ts`, `cron-agent-native-audit.ts`, `cron-campaign-calendar.ts`,
`cron-community-monitor.ts`, `cron-growth-execution.ts`, `cron-legal-audit.ts` **all use the same
`ok: spawnResult.ok` pattern**. The durable fix belongs in the **shared substrate** so every
output-producing cron benefits. Scope is bounded to closing the four cited issues; the substrate change
is the mechanism.

## Premise Validation

Checked the cited references at plan time. **Bash stdout was intermittently dropped this session, so all
command output was round-tripped through `.planscratch/*.txt` and Read back. `gh` / `doppler` / `curl`
returned empty in-sandbox (no network/auth); those results MUST be re-confirmed at /work Phase 0.**

- **Functions exist + are registered:** confirmed by reading `route.ts` and each source file. ✅
- **Heartbeat call-sites match the cited lines** (`:277`, `:252`, `:201`, `:632`): confirmed by
  `grep -n postSentryHeartbeat`. ✅
- **`buildSpawnEnv` allowlist** (PATH/HOME/NODE_ENV/ANTHROPIC_API_KEY/GH_TOKEN, GH_TOKEN = installation
  token) confirmed at `cron-roadmap-review.ts:177`. ✅
- **CORRECTION to the task's premise — test harness location.** The task says "existing harnesses e.g.
  `cron-roadmap-review.test.ts`" implying co-located tests. They are **NOT co-located**; all four (plus
  the watchdog) live at `apps/web-platform/test/inngest/cron-<name>.test.ts` and match the vitest `node`
  project glob `include: ["test/**/*.test.ts"]`. A co-located `server/inngest/functions/*.test.ts` would
  be **silently never run** (the runner only collects under `test/**`). This is the test-path-discovery
  Sharp Edge — the plan's Files-to-Edit targets the correct `test/inngest/` paths.
- **CORRECTION — there is NO `_cron-claude-eval-substrate.test.ts` or `_cron-shared.test.ts`.** The new
  substrate-helper unit test is a *create* at `test/inngest/_cron-claude-eval-substrate.test.ts`.
- **Issue states (#4689/#4686/#4684/#4688) + PR merge states:** `gh` returned empty in-sandbox.
  **Re-verify at Phase 0** with `gh issue view <N> --json state` / `gh pr view <N> --json merged` before
  relying on `Closes`. If any target issue is already closed by a merged PR, re-scope per Open Questions.

## User-Brand Impact

**If this lands broken, the user experiences:** the four founder-facing strategic artifacts (roadmap
review, strategy review, generated content, competitive analysis) silently never appear as GitHub issues
— the founder loses the recurring strategic-intelligence cadence the product promises, and the monitors
stay green so no one notices it's gone.

**If this leaks, the user's data/workflow is exposed via:** N/A — no new data surface. The spawned
claude already runs with the installation token (`GH_TOKEN`) in an ephemeral `--depth=1` clone; this fix
adds a read-only GitHub issue-list step using the same token. No new secret, no new egress.

**Brand-survival threshold:** `aggregate pattern` — the harm is a sustained-silence pattern across
recurring producers, not a single per-user incident. No per-PR CPO sign-off required; section present per
`hr-weigh-every-decision-against-target-user-impact`.

## Root-Cause Diagnosis (Phase 0 — MUST complete first; restore shape depends on it)

Two questions, answered before any restore code:

### Q1 — Why does the spawned eval produce no issue?

Candidate causes, refined by plan-time code reading, in likelihood order:

- **(B1) The `gh` Bash sub-command is blocked inside the ephemeral spawn — STRONGEST candidate.**
  `CLAUDE_CODE_FLAGS` (`cron-roadmap-review.ts:87-96`) passes `--allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch`, with the in-code comment (`:78-93`) stating: *"Bash is allowlisted wholesale; individual gh verbs are governed by the repo `.claude/settings.json` allowlist (DEFAULT_SETTINGS overlay)."* BUT the ephemeral workspace is a `--depth=1` clone whose `.claude/settings.json` is **overwritten** by `setupEphemeralWorkspace` with `DEFAULT_CLAUDE_SETTINGS = { permissions: { allow: [] }, sandbox: { enabled: true } }` (`_cron-claude-eval-substrate.ts:63-70,101-107`). An **empty `allow: []` + enabled sandbox** can deny the very `gh issue create` the producer needs — while claude still exits 0. **This is the prime suspect: the comment assumes a repo `.claude/settings.json` allowlist that the substrate clobbers with an empty one.**
- **(B2) `--allowedTools` variadic / `--` end-of-options interaction.** The comment at `:80-83` notes
  `--allowedTools` is variadic and `"--"` must terminate flags before the positional prompt; argv is
  `[...flags, prompt]` (`_cron-claude-eval-substrate.ts:174`). Verify the `"--"` actually stops parsing
  so the prompt is not swallowed as a tool name (a Phase 0 `--help`/exit-code probe of the installed
  `claude` binary, per the CLI-form Sharp Edge — doc absence ≠ flag absence).
- **(A) Label string mismatch / missing repo label — partially ruled out.** Plan-time grep
  (`.planscratch/g.txt`) shows the producer prompts AND the watchdog reference the **same** label strings
  (`scheduled-roadmap-review`, `scheduled-strategy-review`, `scheduled-competitive-analysis`,
  `scheduled-content-generator`). So producer↔watchdog *string* alignment holds. STILL verify at Phase 0
  that each label **exists on `jikig-ai/soleur`** (`gh label list`) — `gh issue create --label X` fails
  if X is absent, and claude may swallow that failure and exit 0.
- **(C) Auth/grant gap.** `gh` reads `GH_TOKEN` (set) — confirm the installation grant includes
  `issues:write`. Note the roadmap prompt itself instructs `gh issue create ... --label
  scheduled-roadmap-review --milestone ...` (`:132,154,159`), so the prompt is correct; the failure is
  at the permission/auth/sandbox layer, not the prompt.

**CHEAPEST + MOST DECISIVE PROBE — run FIRST, no network needed.** Diff the spawn config of the four
silent functions against the issue-creating crons that DO work (`cron-bug-fixer.ts`,
`cron-daily-triage.ts` — both create labeled issues and both go through the same `spawnClaudeEval`
substrate). They are a controlled A/B already in the repo:

```bash
grep -nE "allowedTools|DEFAULT_CLAUDE_SETTINGS|permissions|sandbox|settings\.json|dangerously" \
  apps/web-platform/server/inngest/functions/cron-bug-fixer.ts \
  apps/web-platform/server/inngest/functions/cron-daily-triage.ts \
  apps/web-platform/server/inngest/functions/cron-roadmap-review.ts \
  apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts \
  > .planscratch/permdiff.txt   # Read back
```

If bug-fixer/daily-triage succeed with the **same** empty-allowlist substrate, cause (B1) is wrong and
the divergence is elsewhere (prompt, label existence, auth) — follow the evidence. If they differ in
allowedTools / settings overlay, that asymmetry IS the bug.

### Q2 — Pull Sentry error events (pin the exact failing line)

For features `cron-roadmap-review`, `cron-strategy-review`, `cron-competitive-analysis`,
`cron-content-generator` since 2026-05-25. Creds in **Doppler project `soleur` config `prd`**
(`SENTRY_AUTH_TOKEN` / `SENTRY_ISSUE_RW_TOKEN`, `SENTRY_ORG=jikigai-eu`, `SENTRY_PROJECT=web-platform`).
**sentry-cli is not installed** — query the API directly; write to file, Read back (flaky stdout):

```bash
TOKEN=$(doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd --plain)
for feat in cron-roadmap-review cron-strategy-review cron-competitive-analysis cron-content-generator; do
  curl -s --max-time 30 -H "Authorization: Bearer $TOKEN" \
    "https://sentry.io/api/0/projects/jikigai-eu/web-platform/issues/?query=feature%3A$feat&statsPeriod=90d" \
    > ".planscratch/sentry-$feat.json"
done
# then per issue: GET .../issues/<id>/events/latest/  → read stack + extra
```

**Heads-up (diagnostic inversion):** the substrate's `reportSilentFallback` only fires on spawn *errors*
(`_cron-claude-eval-substrate.ts:238-247`) and timeouts (`cron-roadmap-review.ts:257-273`). A claude that
exits 0 without creating the issue throws **nothing** → **no Sentry event at all**. So an **empty Sentry
result for a feature is itself diagnostic** — it confirms the silent-no-op causes (B1)/(A), not a thrown
error. Do NOT read "0 events" as "no problem."

**Diagnosis output:** a `## Root Cause` note appended to this plan (or a FINDINGS file) naming the exact
failing line/layer per function before any restore code is written.

## Research Reconciliation — Spec vs. Codebase

| Claim (feature description)                                   | Codebase reality (verified)                                                                  | Plan response                                                                   |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Heartbeat ok = `spawnResult.ok` at 4 cited lines             | Confirmed at `:277`, `:252`, `:201`; strategy uses `result.ok` at `:632`                      | Replace each with `ok: <exit-ok> && issueCreated` (output-aware).               |
| `buildSpawnEnv` passes PATH/HOME/NODE_ENV/ANTHROPIC/GH_TOKEN  | Confirmed `cron-roadmap-review.ts:177`; GH_TOKEN = installation token                         | Reuse same token for read-only issue-list verification. No new secret.          |
| "existing harness e.g. `cron-roadmap-review.test.ts`"        | Exists at `test/inngest/`, NOT co-located; glob `test/**/*.test.ts`                           | Edit the four `test/inngest/cron-*.test.ts`; never co-locate.                   |
| Only these four are affected                                 | Same `ok: spawnResult.ok` in ≥8 sibling output crons                                          | Fix in shared substrate; four issues close as scoped deliverable.               |
| Label strings differ producer↔watchdog                       | They MATCH (grep `.planscratch/g.txt`)                                                        | No string-alignment edit needed; only verify labels exist on repo at Phase 0.   |
| Empty Sentry = no problem                                    | Empty Sentry = silent no-op (no throw) = confirms the bug                                     | Treat empty Sentry as evidence, not reassurance.                                |

## Proposed Solution

Three coordinated changes, **diagnosis-gated** (restore shape finalizes after Phase 0):

### A. Restore output production (depends on Phase 0 root cause)

- **If (B1) sandbox/empty-allowlist block:** the durable fix is to make `setupEphemeralWorkspace`'s
  `DEFAULT_CLAUDE_SETTINGS` permit the `gh`/Bash invocation output-producers need (scope the
  `permissions.allow` to exactly the `gh issue create`/`gh label`/`gh issue list` verbs — mirror the
  `.claude/settings.json` overlay the in-code comment assumes), OR align with how bug-fixer/daily-triage
  succeed. Do NOT blanket-disable the sandbox. Name the new ceiling per
  `2026-05-05-defense-relaxation-must-name-new-ceiling.md`.
- **If (A) missing repo label:** add a Phase 0 `gh label create` for any absent `scheduled-<task>` label.
- **If (B2) flag parsing:** correct the `--` placement / flag order in `CLAUDE_CODE_FLAGS`.
- **If (C) auth:** confirm installation grant has `issues:write`.

### B. Close the observability gap (the durable fix — shared substrate)

Add an **issue-verification step** after `claude-eval`, before `sentry-heartbeat`, in the shared
substrate so all output crons inherit it:

1. New helper in `_cron-claude-eval-substrate.ts`:
   `verifyScheduledIssueCreated({ label, sinceIso, installationToken }): Promise<boolean>` — **read-only**
   GitHub list for an issue with `label:scheduled-<task>` created at/after the run-window start
   (`>= sinceIso`). Reuse the **same read path `cron-cloud-task-heartbeat` already uses** to list/count
   these labeled issues (precedent parity — adopt verbatim rather than inventing a new search shape;
   prefer `issues.listForRepo` with `labels` + `since` over the search API for strong consistency).
   Uses the installation token already minted; no new secret.
2. Capture `runStartedAt` (ISO) at function entry so the search is scoped to *this* run's output, not a
   stale issue from a prior week.
3. Each of the four feeds `ok: <exit-ok> && issueCreated` to `postSentryHeartbeat`. On
   `issueCreated === false` while exit-ok is true, also call `reportSilentFallback` with a distinct op
   (`scheduled-output-missing`) so the silent no-op produces a loud Sentry event AND a red monitor —
   satisfying `cq-silent-fallback-must-mirror-to-sentry`.

### C. Tests first (RED → GREEN, per `cq-write-failing-tests-before`)

Extend `test/inngest/cron-roadmap-review.test.ts` (and the other three + a new substrate test): assert
the heartbeat posts `ok: false` when the spawn exits 0 but no `scheduled-<task>` issue exists in the
window. FAILS against current `ok: spawnResult.ok` (RED), passes after the substrate change (GREEN).

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — add
  `verifyScheduledIssueCreated` (read-only issue list via installation token); if (B1), adjust
  `DEFAULT_CLAUDE_SETTINGS.permissions.allow` for output-producing spawns.
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — (optional) export shared
  `SCHEDULED_TASK_LABELS` constant / run-window helper if needed for producer↔watchdog single-source.
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — capture `runStartedAt`; call
  verify; `:277` → `ok: spawnResult.ok && issueCreated`; add missing-output `reportSilentFallback`.
- `apps/web-platform/server/inngest/functions/cron-strategy-review.ts` — same; `:632` `result.ok` →
  `result.ok && issueCreated`.
- `apps/web-platform/server/inngest/functions/cron-content-generator.ts` — same; `:201`.
- `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts` — same; `:252`.
- `apps/web-platform/test/inngest/cron-roadmap-review.test.ts` — RED→GREEN output-aware-ok test.
- `apps/web-platform/test/inngest/cron-strategy-review.test.ts` — same.
- `apps/web-platform/test/inngest/cron-content-generator.test.ts` — same.
- `apps/web-platform/test/inngest/cron-competitive-analysis.test.ts` — same.

## Files to Create

- `apps/web-platform/test/inngest/_cron-claude-eval-substrate.test.ts` — unit test for
  `verifyScheduledIssueCreated` (mock the GitHub list; assert window-scoping + label match + read-only).

> /work Phase 0: confirm `apps/web-platform/vitest.config.ts` `include: ["test/**/*.test.ts"]` (node
> project) collects `test/inngest/*.test.ts` (the four existing files prove it) and check
> `apps/web-platform/bunfig.toml` does not ignore them. Use the package's actual runner (per
> `package.json scripts.test`), not a hardcoded `bun test`.

## Open Code-Review Overlap

**Check ran at plan time; result: indeterminate in-sandbox (`gh` returned empty — no network/auth).**
MUST be re-run at /work Phase 0 against live state and the result recorded here (Fold-in / Acknowledge /
Defer per match, or `None`):

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in _cron-claude-eval-substrate.ts _cron-shared.ts cron-roadmap-review.ts cron-strategy-review.ts cron-content-generator.ts cron-competitive-analysis.ts; do
  jq -r --arg p "$path" '.[] | select(.body // "" | contains($p)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **Diagnosis pinned:** `## Root Cause` names the exact failing line/layer per function, evidenced by
  Sentry events (or documented "0 events = silent no-op" with the cause it confirms).
- [ ] **RED→GREEN:** a test posts `ok: false` when spawn exits 0 but no `scheduled-<task>` issue is in
  the run window; fails on pre-fix code, passes after (visible in commit order).
- [ ] All four feed `ok: <exit-ok> && issueCreated` to `postSentryHeartbeat` — `grep -nE "&& issueCreated"`
  returns 4 matches across the four functions.
- [ ] On missing output with successful spawn, `reportSilentFallback` is called with op
  `scheduled-output-missing` (grep returns 4 matches).
- [ ] `verifyScheduledIssueCreated` is read-only (no `issues.create`/PATCH in the helper) and scopes to
  `>= runStartedAt` — asserted by the substrate unit test.
- [ ] Package test runner (`scripts.test`) passes for the inngest suite; `tsc --noEmit` clean for
  `apps/web-platform`.
- [ ] PR body uses `Closes #4689`, `Closes #4686`, `Closes #4684`. For **#4688** (monthly `0 9 1 * *`):
  if Phase 0 confirms it shares the root cause (silent no-op + exit-code-only heartbeat), add
  `Closes #4688`; otherwise leave open + post a root-cause comment (its May 1 fire was still under GHA
  and also produced nothing — confirm whether that was the same output-step failure or earlier degradation).

### Post-merge (operator / automated)

- [ ] **Container restart is automatic:** `web-platform-release.yml` restarts the container on merge to
  `main` touching `apps/web-platform/**` (path-filtered) — the merge IS the deploy/function-sync. No
  manual restart step.
- [ ] **First-fire verification (automatable):** after the next scheduled fire (or via the
  `cron/*.manual-trigger` Inngest event), confirm a `scheduled-<task>` issue was created:
  `gh issue list --label scheduled-roadmap-review --search "created:>=<fire-date>" --json number,createdAt`.
  For the monthly competitive-analysis, use its manual-trigger event to verify without waiting for the
  1st. Prescribe the `gh` query + deterministic pass rule, not dashboard-watching
  (`hr-no-dashboard-eyeball-pull-data-yourself`).
- [ ] **Monitor goes red on quiet:** confirm (via the substrate unit test, not prod) that a quiet
  producer turns its own Sentry monitor red without depending on `cron-cloud-task-heartbeat`.

## Observability

```yaml
liveness_signal:
  what: per-function Sentry Crons check-in via postSentryHeartbeat, now gated on actual issue creation
  cadence: each cron fire (weekly / monthly per function)
  alert_target: Sentry monitor per SENTRY_MONITOR_SLUG (one per function); existing alert rules
  configured_in: apps/web-platform/server/inngest/functions/_cron-shared.ts (postSentryHeartbeat) + each cron's sentry-heartbeat step
error_reporting:
  destination: Sentry via reportSilentFallback (feature=cron-<name>, op=scheduled-output-missing)
  fail_loud: true
failure_modes:
  - mode: claude exits 0 but creates no scheduled-<task> issue (the bug)
    detection: verifyScheduledIssueCreated returns false in the run window
    alert_route: monitor red (ok:false) + reportSilentFallback event
  - mode: gh issue create blocked by empty-allowlist sandbox
    detection: same (no issue created) + Phase 0 diagnosis
    alert_route: monitor red; root-cause note
  - mode: spawn error / timeout
    detection: existing reportSilentFallback (substrate :238-247) + timeout guard (:257-273)
    alert_route: existing Sentry event + monitor red
logs:
  where: pino logger.info/.error per spawn line (substrate :181-198), redacted via redactToken
  retention: platform log retention (container logs / Better Stack)
discoverability_test:
  command: "gh issue list --label scheduled-roadmap-review --search 'created:>=<last-fire>' --json number,createdAt"
  expected_output: at least one issue created at/after the most recent scheduled fire (NO ssh)
```

## Domain Review

**Domains relevant:** Engineering (observability/reliability) only.

Product: **NONE** — no user-facing UI surface created or modified (the "output" is a GitHub issue in the
ops repo, not an app screen); change is server-side orchestration + monitoring. GDPR/Compliance:
**NONE** — no regulated-data surface (no schema, migration, auth flow, or API route over personal data);
the read-only issue list uses the existing installation token over the ops repo. Running as a one-shot
subagent (Task tool unavailable); domain assessment done inline. No cross-domain implications beyond
engineering reliability — infrastructure/observability change.

## Infrastructure (IaC)

Skip — no new infrastructure. Pure code change against the already-provisioned Inngest substrate and the
existing GitHub App installation token. No new server, secret, vendor, cron, or persistent process (the
crons already exist and fire; the Sentry monitors already exist, one per `SENTRY_MONITOR_SLUG`).

## Hypotheses

Diagnosis hypotheses enumerated in **Root-Cause Diagnosis** (likelihood-ordered): (B1) empty-allowlist
sandbox block ≈ (A) missing repo label > (B2) flag parsing > (C) auth gap. NOT a network-outage class —
no SSH/firewall/connection-reset keywords; the network checklist gate does not fire.

## Test Scenarios

1. Spawn exits 0, issue exists in window → `ok: true`, no silent-fallback event.
2. Spawn exits 0, **no** issue in window → `ok: false` + `reportSilentFallback(op: scheduled-output-missing)`. *(RED test)*
3. Spawn exits non-zero → `ok: false` (existing behavior preserved).
4. Spawn times out → `ok: false` + existing timeout `reportSilentFallback` (regression guard).
5. `verifyScheduledIssueCreated` ignores a stale issue created before `runStartedAt` (window-scoping).
6. `verifyScheduledIssueCreated` matches the correct label string (alignment with watchdog's set).

## Precedent Diff (deepen-plan Phase 4.4)

Pattern-bound behavior: spawning claude in an ephemeral `--depth=1` clone to produce a labeled GitHub
issue. Sibling precedents that DO this successfully (and route through the **same** `spawnClaudeEval` /
`setupEphemeralWorkspace` substrate) are `cron-bug-fixer.ts` and `cron-daily-triage.ts` — both create
labeled issues, both pass `--allowedTools` with a `Bash` entry (bug-fixer `:147`, daily-triage `:139`).

| Dimension                         | Silent four (roadmap et al.)                              | Working precedents (bug-fixer / daily-triage)              | Implication                                                                 |
| --------------------------------- | -------------------------------------------------------- | --------------------------------------------------------- | -------------------------------------------------------------------------- |
| Spawn substrate                   | `spawnClaudeEval` + `setupEphemeralWorkspace`            | same                                                       | Substrate is shared — settings overlay is identical for all.               |
| `.claude/settings.json` in clone  | overwritten with `DEFAULT_CLAUDE_SETTINGS` (`allow:[]`)  | same (shared `setupEphemeralWorkspace`)                    | If this blocked gh, bug-fixer/daily-triage would ALSO be silent — test it. |
| `--allowedTools` Bash entry       | `Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch`     | daily-triage narrows Bash to 4 gh verbs (`:119-139`)      | daily-triage's NARROWER allowlist is the proven-working shape.             |
| Output verb                       | `gh issue create --label scheduled-<task> --milestone`  | `gh issue create` (+ labels)                              | Producer prompt is correct; failure is at permission/sandbox layer.        |

**Decisive Phase 0 action:** confirm bug-fixer/daily-triage are actually producing issues post-migration
(`gh issue list --label scheduled-bug-fixer --search "created:>=2026-05-25"`). Two outcomes:
- **They succeed** → the empty-allowlist substrate is NOT the blocker; the silent four diverge in prompt,
  label existence, or a flag detail — narrow from there.
- **They are ALSO silent** → the bug is substrate-wide (cause B1 confirmed); the fix's blast radius and
  confidence both grow, and the substrate `DEFAULT_CLAUDE_SETTINGS` / allowedTools fix is the root fix.

Adopt daily-triage's narrowed-Bash-to-gh-verbs allowlist shape verbatim if widening is required (it is
the in-repo proven-working precedent), rather than inventing a new allow-list.

## Risks & Mitigations

- **GitHub list eventual consistency:** an issue created seconds before verify may lag. *Mitigation:*
  use `issues.listForRepo` with `labels` + `since` (strongly consistent), plus a short bounded retry.
  Cite the precedent: reuse `cron-cloud-task-heartbeat`'s list/count read path for parity.
- **Label-string drift producer↔watchdog:** currently aligned (verified); a shared
  `SCHEDULED_TASK_LABELS` constant keeps it so. AC greps for matches.
- **Widening sandbox permissions (if B1):** scope `permissions.allow` to exactly the `gh` verbs the
  producers need; do not blanket-disable the sandbox. Name the new ceiling per the defense-relaxation learning.
- **Scope creep to all 8+ sibling crons:** intentionally bounded — substrate helper is shared, but only
  the four cited functions are wired + tested here. Siblings inherit the helper; per-function wiring is a
  tracked follow-up.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty / `TBD` / omits the threshold fails `deepen-plan`
  Phase 4.6. (Filled: threshold = `aggregate pattern`.)
- **0 Sentry events for a feature is diagnostic, not reassuring** — a claude that exits 0 without
  creating the issue throws nothing, so `reportSilentFallback` never fires. Empty = silent-no-op confirmation.
- **Test path discovery:** inngest tests live at `test/inngest/*.test.ts` (glob `test/**/*.test.ts`), NOT
  co-located under `server/inngest/functions/`. A co-located test is silently never collected.
- **The in-code comment lies about the allowlist:** `cron-roadmap-review.ts:78-93` says gh verbs are
  "governed by the repo `.claude/settings.json` allowlist" — but `setupEphemeralWorkspace` overwrites
  that file with `DEFAULT_CLAUDE_SETTINGS` (`allow: []`). The comment's assumption is the prime bug suspect.
- **`gh` vs `GITHUB_TOKEN`:** `gh` reads `GH_TOKEN` (set). If any sub-skill the prompt invokes uses
  Octokit expecting `GITHUB_TOKEN`, it would be unauthenticated — grep the prompt/skill chain at Phase 0.
- **Precedent check (deepen-plan Phase 4.4):** ADR-033 (Inngest > GH Actions cron). Compare the verify
  read path against `cron-cloud-task-heartbeat`'s existing labeled-issue list/count and adopt verbatim.
- **`.planscratch/` is untracked scratch** — remove (or gitignore) before commit so it never lands in the PR.

## Alternative Approaches Considered

| Approach                                            | Why not chosen                                                                              |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Rely on `cron-cloud-task-heartbeat` watchdog alone  | That's the status quo that hid the outage; the task requires per-function red-on-quiet.     |
| Parse claude stdout for "created issue #N"          | Brittle (stdout format drift); the GitHub list is the source of truth.                      |
| Restore the deleted GHA workflows                   | Regresses TR9 (ADR-033 Inngest > cron); reintroduces dual-system drift.                     |
| Fix only the four inline (no shared helper)         | Leaves 8+ siblings dark; duplicates verify logic 4×. Shared substrate is DRY + future-proof.|

## Deferral Tracking

- If the substrate helper is added but the 8+ sibling output crons are **not** wired in this PR, file a
  tracking issue ("wire output-aware heartbeat into remaining output-producing crons") with the sibling
  list + re-evaluation criteria + milestone from `knowledge-base/product/roadmap.md`. A deferral without
  a tracking issue is invisible (`wg-when-deferring-a-capability-create-a`).

## Open Questions

- Does #4688 (competitive-analysis) share the exact same root cause, or did it degrade earlier under GHA?
  Resolve in Phase 0 from Sentry + the GHA history; decide `Closes #4688` vs leave-open-with-comment.
- Are bug-fixer/daily-triage actually succeeding at issue creation post-migration? If they are ALSO
  silent, the root cause is substrate-wide and the fix's blast radius (and confidence in cause B1) grows.
