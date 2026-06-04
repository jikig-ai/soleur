---
title: "fix: resume three silent Inngest cron producers (community-monitor 06-04 dropout + content-generator/roadmap-review post-TR9 silence)"
type: fix
date: 2026-06-04
branch: feat-one-shot-cron-producers-silent
lane: cross-domain
status: planned
brand_survival_threshold: aggregate-pattern
related_issues:
  - "#4927 cloud-task-silence content-generator"
  - "#4928 cloud-task-silence roadmap-review"
related_sentry:
  - 4d67bdc8e3564efdb6afb5d8ff23527c  # cron-community-monitor scheduled-output-missing 2026-06-04 08:00
related_prs:
  - "#4714 output-aware Sentry heartbeat (a697660c)"
  - "#4750 output overrides exit code (d0c80447)"
  - "#4786 stdout-tail capture (223364c1)"
  - "#4870 community-monitor max-turns 50→80 (cb54618d)"
  - "#4884 community-monitor X/Twitter cred forwarding (d99267f2)"
  - "#4483 TR9 Phase 2 migration (5b2c1922)"
  - "#4423 roadmap-review Inngest migration (d1e61d52)"
related_learnings:
  - knowledge-base/project/learnings/2026-06-01-output-aware-cron-heartbeat-and-live-evidence-refutes-plan-hypothesis.md
  - knowledge-base/project/learnings/2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons.md
  - knowledge-base/project/learnings/2026-06-03-cloud-task-heartbeat-grace-discriminate-null-origins.md
---

# fix: resume three silent Inngest cron producers 🐛

## Overview

Three scheduled Inngest cron producers are silent in production. The
output-aware heartbeat (`resolveOutputAwareOk` in `_cron-shared.ts`) and the
`cron-cloud-task-heartbeat` issue-count watchdog BOTH fired correctly — **the
observability layer is healthy; this PR fixes the PRODUCERS, not the monitors.**

| Cron | Schedule | Last issue | Silent | Signature |
|------|----------|-----------|--------|-----------|
| `cron-community-monitor` | `0 8 * * *` daily | 2026-06-03 (×2) | 06-04 08:00 run only | Sentry `4d67bdc8…`: **exited 0**, no `scheduled-community-monitor` issue |
| `cron-content-generator` | `0 10 * * 2,4` Tue/Thu | 2026-05-21 (Thu) | ~14d (missed 05-26, 05-28, 06-02) | watchdog #4927 (13d ≥ 9d threshold) |
| `cron-roadmap-review` | `0 9 * * 1` Mon | 2026-05-18 (Mon) | ~17d (missed 05-25, 06-01) | watchdog #4928 (16d ≥ 9d threshold) |

This is a **continuation of a known, incompletely-resolved incident.** Per
`2026-06-01-output-aware-cron-heartbeat-and-live-evidence-refutes-plan-hypothesis.md`,
**four** producers (roadmap-review #4689, strategy-review #4686, content-generator
#4684, competitive-analysis #4688) went silent after the TR9 GHA→Inngest
migration. That PR shipped only the **confirmed-safe observability fix** and
**deferred the producer restore** (the permissions-vs-max-turns disambiguation)
pending a live diagnosis, because the prime root-cause hypothesis (B1: sandboxed
`.claude/settings.json` blocking `gh issue create`) was refuted by live evidence
(`cron-daily-triage` produced output through the SAME `DEFAULT_CLAUDE_SETTINGS`
that morning). **This PR completes that deferred diagnosis and ships the restore.**

The named divergence from the prior learning is the spine of the root-cause
model: healthy `cron-daily-triage` runs `--max-turns 80` + narrowed
`Bash(gh …:*)` allowedTools; the silent producers run wholesale `Bash` + low
`--max-turns` (content-gen 50, roadmap 40). The community-monitor 06-03 fix
(cb54618d raised 50→80) confirmed turn-exhaustion as a real lever for THAT cron —
but the 06-04 dropout exited **0** (not the exit-1 "Reached max turns" signature),
so it is a **distinct failure mode** that the plan must root-cause from the live
Sentry event, not assume.

## Research Reconciliation — Spec vs. Codebase

| Claim (from triggering signals) | Reality (verified at plan-write) | Plan response |
|---|---|---|
| All three registered in `serve()` array | Confirmed: route.ts L91 (content-gen), L93 (community), L113 (roadmap) | Registry-drop ruled out; do not re-derive |
| content-gen & roadmap both went silent "EXACTLY at the TR9 migration boundary 5b2c1922" | Partially correct. content-generator WAS migrated at 5b2c1922 (#4483). **roadmap-review was migrated EARLIER at d1e61d52 (#4423)**, before 5b2c1922. | Treat "TR9 boundary" as the broad correlation, NOT a single-commit pin for roadmap. The live FIRING-vs-FAILING probe (Phase 1) is authoritative. |
| community-monitor 06-04 is max-turns exhaustion (per cb54618d) | Sentry event signature is **exited 0**, NOT exit-1 "Reached max turns (50/80)". community is already at `--max-turns 80` + `MAX_TURN_DURATION_MS 50min`. | Distinct failure mode. Phase 1 MUST pull the live `stderrTail`/`stdoutTail` from event `4d67bdc8…` before prescribing a fix. Candidate causes: dedup-rule mis-fire, a tool/prompt step dead-ending after a 06-03 change (d99267f2 X cred forwarding), or a healthy-but-empty run the verify window missed. |
| #4927/#4928 should be linked `Closes` | The `cron-cloud-task-heartbeat` watchdog **auto-closes its own silence issues on recovery** (cron-cloud-task-heartbeat.ts L256-284). `Closes #N` at merge would false-resolve them BEFORE the producer recovers. | Use `Ref #4927` / `Ref #4928` in the PR body. Closure happens post-merge when the next healthy fire runs (watchdog auto-close), verified in Phase 5. Per `wg-use-closes-n-in-pr-body-not-title-to` + the ops-remediation Sharp Edge. |

## User-Brand Impact

**If this lands broken, the user experiences:** the weekly roadmap-consistency
review, the Tue/Thu content pipeline, and the daily community digest stay dark —
the founder's "the platform is working on the business while I sleep" promise is
silently false; roadmap drift, missed content cadence, and an unmonitored
community accrue invisibly.

**If this leaks, the user's data is exposed via:** N/A — no new data surface.
These crons already hold an operator GH App installation token + operator
`ANTHROPIC_API_KEY` (never founder BYOK, enforced by `cron-no-byok-lease-sweep.test.ts`).
The fix touches turn budgets / allowedTools / prompt ordering only; the spawn-env
allowlist is unchanged unless Phase 1 evidence demands it (in which case
re-scope).

**Brand-survival threshold:** aggregate pattern — three producers dark for 2+
weeks is an aggregate observability/output failure, not a single-user data
incident. (Inherits the `aggregate-pattern` threshold from the sibling
community-monitor plan `2026-06-03-fix-cron-community-monitor-max-turns-exhaustion-plan.md`.)

## Root-Cause Hypotheses (to confirm/refute in Phase 1 — DO NOT assume)

Per the learning's Key Insight ("a plan's root-cause hypothesis is a hypothesis,
not a fact — confirm against runtime evidence"), the fix **branches on Phase 1's
FIRING-vs-FAILING outcome.** Hypotheses, ranked:

- **H1 (content-generator) — turn-exhaustion before STEP 6 issue-create.**
  content-gen runs `--max-turns 50` with a heavy 6-step prompt (topic select →
  `/soleur:content-writer` → `/soleur:social-distribute` → eleventy build →
  queue update → issue create → PR). This is the EXACT bug class that hit
  community-monitor (exit-1 "Reached max turns (50)", fixed 50→80 in cb54618d).
  **Fix:** raise `--max-turns` 50→80 to match the proven-healthy daily-triage
  budget; verify `MAX_TURN_DURATION_MS` ratio stays in the 0.55–1.2 min/turn peer
  band (current 55min/50 = 1.1; 55min/80 = 0.69, in band). Strong prior; still
  gate on Phase 1 live evidence.

- **H2 (roadmap-review) — turn-exhaustion or a prompt step dead-ending.**
  roadmap runs `--max-turns 40` (lowest of the three) + a Part-1/Part-2 prompt
  with a DEDUP RULE that COMMENTS instead of creating when a fire from the last
  6 days exists. If the spawn exhausts 40 turns mid-analysis, no issue/comment is
  produced. **Fix:** raise `--max-turns` 40→80 (ratio 50min/80 = 0.625, in band,
  matches the community-monitor post-fix ratio). Gate on Phase 1.

- **H3 (community-monitor 06-04) — distinct "exited 0, no output" mode.**
  Already at 80 turns. The exit-0 signature rules out turn-exhaustion. Candidates:
  (a) DEDUP RULE 24h-window mis-fire (two issues filed 06-03; the 06-04 run saw
  them <24h old and dead-ended on the dedup path without commenting — but
  `verifyScheduledIssueCreated` filters on `updated_at` so a dedup-comment WOULD
  count; a dedup that *exits without commenting* would not); (b) a 06-03 change
  (d99267f2 X/Twitter cred forwarding, or the disk/workspace-relocation churn
  #4770/#4886) shifted prompt behavior so a platform step dead-ended after the
  spawn went clean; (c) genuinely-empty healthy run. **Fix shape unknown until
  the live `stdoutTail`/`stderrTail` from Sentry `4d67bdc8…` is read.** Likely a
  prompt-ordering fix (move issue-create BEFORE best-effort platform/PR steps so
  the success artifact survives a tight budget — flagged as a secondary lever in
  the sibling community plan) OR a dedup-window correction.

- **H4 (cross-cutting, lower prior) — permissions.** REFUTED for the general case
  by the prior learning (daily-triage produces through the same settings), but the
  divergence "wholesale `Bash` vs narrowed `Bash(gh …:*)`" is real. Only pursue if
  Phase 1 shows a permission-denied line in `stderrTail`. Narrowing allowedTools
  is the daily-triage-proven shape but is a behavior change — do NOT bundle
  speculatively.

## Implementation Phases

### Phase 0 — Preconditions (re-verify at /work time; these drift)

1. CWD is the worktree (`pwd` == `.worktrees/feat-one-shot-cron-producers-silent`).
2. Re-confirm registry: `grep -nE "cronCommunityMonitor|cronContentGenerator|cronRoadmapReview" apps/web-platform/app/api/inngest/route.ts` returns the import AND the `serve()` array entry for each (4 hits each expected: 1 import, 1 array — adjust if a sibling PR shifted lines).
3. Re-read the current `--max-turns` / `MAX_TURN_DURATION_MS` literals in all three producer files AND the daily-triage comparator (`cron-daily-triage.ts`: `--max-turns 80`, `MAX_TURN_DURATION_MS 60min`, narrowed `Bash(gh …:*)`). Do not trust this plan's literals — re-derive.
4. Confirm the manual-trigger events are still allowlisted: all three are in `EXPECTED_CRON_FUNCTIONS` (`cron-manifest.ts` L27/L30/L49), and the allowlist is derived from it (`manual-trigger-allowlist.ts`). No second list to edit.
5. Enumerate the verbatim-prompt anchors each producer's test asserts (`cron-content-generator.test.ts`, `cron-roadmap-review.test.ts`, `cron-community-monitor.test.ts` — the sibling community plan notes 27 anchors). A turn-budget bump touches NO anchor; any prompt-ordering edit (H3) MUST update the matching anchor in lockstep or avoid the anchored substrings.

### Phase 1 — FIRST INVESTIGATION TASK: FIRING-vs-FAILING + live root-cause (gates everything below)

This phase is the fork in the road. Two orthogonal questions per cron:
**(Q1) Did Inngest FIRE the schedule?** vs **(Q2) Did the fire FAIL to produce output?**

1. **Pull the live community-monitor Sentry event.** Using the diagnostic
   mechanics from the learning (NO SSH): token `SENTRY_ISSUE_RW_TOKEN`
   (Doppler `soleur/prd`, read-only via `doppler secrets get`), org-issues
   endpoint
   `/api/0/organizations/jikigai-eu/issues/?query=feature%3Acron-community-monitor&statsPeriod=24h&project=-1`,
   then drill the event `4d67bdc8e3564efdb6afb5d8ff23527c` for the `extra`
   payload: `exitCode`, `stderrTail`, `stdoutTail`, `spawnOk`. This discriminates
   H3 (a)/(b)/(c). `statsPeriod` ∈ {`''`,`24h`,`14d`} only (90d → HTTP 400).

2. **Probe content-generator & roadmap-review FIRING-vs-FAILING via
   `soleur:trigger-cron`** (allowlisted manual-trigger, no SSH). Per the skill:
   read `INNGEST_MANUAL_TRIGGER_SECRET` read-only from Doppler, **dry-run first**
   (confirms allowlist membership + endpoint reachability), then live-fire
   `cron/content-generator.manual-trigger` and `cron/roadmap-review.manual-trigger`.
   NOTE the account-scoped concurrency cap (`key "cron-platform"`, limit 1) —
   fire them sequentially, not in parallel; a second fire while one is in-flight
   collapses to one queued run.

3. **Read Inngest run logs / Better Stack** for each fired run: did the schedule
   tick on 05-26/05-28/06-01/06-02 (Q1 — scheduler liveness), and what was the
   `claude-eval` step outcome (Q1-pass + Q2-fail = firing-but-failing; Q1-fail =
   not-firing-at-all). The `cron-inngest-cron-watchdog` is the registered
   scheduler-liveness guard — cross-check its recent output. App pino stdout is
   NOT in Better Stack for the spawn's per-line stream (only the bounded
   stderrTail/stdoutTail reach Sentry), so the Sentry `scheduled-output-missing`
   extra is the primary diagnostic, with Inngest's own run timeline for the
   step-level fire/fail.

4. **Branch the remediation on the outcome:**
   - **FIRING-but-FAILING** (schedule ticks, spawn exits, no issue) → the fix is
     producer-internal: **raise `--max-turns`** (H1/H2) and/or prompt-ordering
     (H3), exactly as below. This is the strongly-expected branch given the
     output-aware heartbeat was added to content/roadmap on 2026-06-01 and a
     firing-but-failing run on/after 06-01 would have emitted its OWN
     `scheduled-output-missing` Sentry event (check for it — its presence
     confirms FIRING-but-FAILING).
   - **NOT-FIRING-at-all** (schedule never ticks) → the fix is scheduler-side:
     investigate the Inngest function-registry sync / cron registration (the
     `cron-inngest-cron-watchdog` desync path), NOT the turn budget. Re-scope
     Phase 2–3 to the registration mechanism. Container-restart on merge to
     `apps/web-platform/**` is the registry-resync remediation (path-filtered
     `web-platform-release.yml#on.push`), so a code-touching PR IS the resync.

5. **Write the Phase 1 verdict into the PR body** (FIRING-but-FAILING vs
   NOT-FIRING, per cron, with the Sentry/Inngest evidence). This is the
   load-bearing artifact that justifies the fix shape.

### Phase 2 — Producer fix (FIRING-but-FAILING branch; default-expected)

Write the failing test FIRST per `cq-write-failing-tests-before` (assert the new
`--max-turns` literal / the new prompt-anchor ordering in each producer's
`*.test.ts`), then:

- **content-generator:** `--max-turns` 50 → 80 in `CLAUDE_CODE_FLAGS`
  (`cron-content-generator.ts`). Update the export-parity comment if present.
  Confirm `MAX_TURN_DURATION_MS` (55min) ratio: 55/80 = 0.69 min/turn (in band).
- **roadmap-review:** `--max-turns` 40 → 80 in `CLAUDE_CODE_FLAGS`
  (`cron-roadmap-review.ts`). Update the `// --max-turns 40` header comment AND
  the I3 ratio note. Confirm `MAX_TURN_DURATION_MS` (50min) ratio: 50/80 = 0.625
  min/turn (in band, matches community-monitor post-fix).
- **community-monitor (H3, evidence-driven):** apply ONLY the fix the Phase 1
  live `stdoutTail`/`stderrTail` justifies. If dedup-window mis-fire → correct the
  24h dedup gate so a within-window run COMMENTS (which `verifyScheduledIssueCreated`
  credits) instead of exiting silently. If a platform-step dead-end → reorder the
  prompt so `gh issue create` lands BEFORE the best-effort platform/PR steps (the
  success artifact survives a tight budget). If genuinely-empty-healthy → adjust
  the verify window / treat as non-red (lowest-likelihood; requires explicit
  evidence). **Any prompt edit updates the matching test anchor in lockstep.**

Do NOT bundle the allowedTools narrowing (H4) unless Phase 1 surfaced a
permission-denied line — it is a behavior change, not part of the silence fix.

### Phase 3 — Tests & build verification

- Run each producer's vitest file via the package's actual runner (check
  `package.json scripts.test` / `vitest.config.ts include:` globs — webplat uses
  vitest, NOT `bun test`; test paths must match `test/**/*.test.ts`).
- `tsc --noEmit` on the web-platform workspace (turn-budget literals are plain
  edits; no union widening expected).
- Confirm the prompt-anchor suites stay green (or were updated in lockstep for H3).

### Phase 4 — Live re-fire verification (no SSH)

Re-fire each fixed producer via `soleur:trigger-cron` (live) and confirm via the
read-only `verifyScheduledIssueCreated` shape (`gh issue list --label
scheduled-<task> --search … --json number,updatedAt`) that each now CREATES or
UPDATES its `scheduled-<task>` issue in the run window. This is the
output-as-success-contract gate — a green claude exit is NOT sufficient.

### Phase 5 — Issue linkage & post-merge recovery

- PR body: `Ref #4927` and `Ref #4928` (NOT `Closes`) — the watchdog
  auto-closes them when the next healthy fire runs; `Closes` at merge would
  false-resolve before recovery (Research Reconciliation row 4).
- Post-merge: merge to `apps/web-platform/**` restarts the container
  (`web-platform-release.yml#on.push` path filter) → Inngest re-registers the
  functions. The next natural fire (or a `soleur:trigger-cron` live fire)
  produces output → `cron-cloud-task-heartbeat` recovery path auto-closes
  #4927/#4928. Verify closure with `gh issue view 4927/4928 --json state`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (Phase 1 verdict recorded):** PR body states FIRING-but-FAILING vs
      NOT-FIRING per cron, citing the Sentry event `4d67bdc8…` extra (community)
      and Inngest run-log / `soleur:trigger-cron` evidence (content, roadmap).
- [ ] **AC2 (community root-cause named):** the live `stdoutTail`/`stderrTail`
      from `4d67bdc8…` is quoted in the PR body, and the community fix maps 1:1 to
      that evidence (not to the assumed max-turns story).
- [ ] **AC3 (content-generator budget):** `grep -E '"--max-turns",\s*"80"'`
      (or the actual array form) present in `cron-content-generator.ts`; the
      prior `"50"` is gone. Ratio note updated.
- [ ] **AC4 (roadmap-review budget):** same for `cron-roadmap-review.ts` (40 →
      80); header `--max-turns 40` comment + I3 ratio note updated in lockstep.
- [ ] **AC5 (anchors intact):** the verbatim-prompt-anchor count in each
      `*.test.ts` is unchanged for budget-only edits; for any H3 prompt edit, the
      changed anchor is updated in the same commit (no orphaned anchor).
- [ ] **AC6 (tests green):** each producer's vitest file passes via the
      package's real runner; `tsc --noEmit` clean.
- [ ] **AC7 (heartbeat untouched):** `resolveOutputAwareOk(` and `ok: heartbeatOk`
      still present and unchanged in all three producers — the observability layer
      is not modified (it is working correctly).
- [ ] **AC8 (linkage form):** PR body uses `Ref #4927` / `Ref #4928`, NOT `Closes`.
- [ ] **AC9 (no scope creep):** spawn-env allowlist and `.claude/settings.json`
      DEFAULT_SETTINGS unchanged unless AC2 evidence demands it.

### Post-merge (operator/automated)

- [ ] **AC10 (live recovery):** after merge + container restart, a
      `soleur:trigger-cron` live fire of each producer creates/updates its
      `scheduled-<task>` issue in the run window (`verifyScheduledIssueCreated`
      shape returns true).
- [ ] **AC11 (watchdog auto-close):** `gh issue view 4927 --json state` and
      `gh issue view 4928 --json state` both return `CLOSED` after the recovery
      fire (watchdog recovery path), confirming the silence is resolved at the
      source.

## Observability

```yaml
liveness_signal:
  what: per-function Sentry Crons monitor (scheduled-community-monitor,
        scheduled-content-generator, scheduled-roadmap-review) gated on the
        output-aware heartbeat (resolveOutputAwareOk → postSentryHeartbeat)
  cadence: per scheduled fire (daily 08:00 / Tue+Thu 10:00 / Mon 09:00 UTC)
  alert_target: Sentry Crons missed/error check-in → existing alert rules
  configured_in: _cron-shared.ts (resolveOutputAwareOk, postSentryHeartbeat) +
                 apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry via reportSilentFallback/warnSilentFallback
               (op=scheduled-output-missing carries exitCode + stderrTail +
               stdoutTail); cq-silent-fallback-must-mirror-to-sentry
  fail_loud: true
failure_modes:
  - mode: firing-but-failing (spawn exits, no scheduled-<task> issue)
    detection: resolveOutputAwareOk → op=scheduled-output-missing (RED monitor)
    alert_route: Sentry Crons error check-in + per-feature Sentry alert
  - mode: not-firing-at-all (schedule never ticks / function desync)
    detection: cron-inngest-cron-watchdog (registry/scheduler liveness) +
               cron-cloud-task-heartbeat issue-count watchdog (#4927/#4928)
    alert_route: auto-filed [cloud-task-silence] GitHub issue
  - mode: turn-exhaustion (exit 1, "Reached max turns") before issue-create
    detection: stdoutTail "Error: Reached max turns (N)" folded into
               scheduled-output-missing extra
    alert_route: same Sentry event (self-diagnosing without SSH)
logs:
  where: Sentry events (bounded stderrTail/stdoutTail, redacted); Inngest run
         timeline (step-level fire/fail). App pino per-line stream is NOT in
         Better Stack — the Sentry tail is the diagnostic path.
  retention: Sentry default project retention
discoverability_test:
  command: >
    curl -sS -H "Authorization: Bearer $SENTRY_ISSUE_RW_TOKEN"
    "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/?query=feature%3Acron-community-monitor&statsPeriod=24h&project=-1"
    | jq '.[].metadata.value'
  expected_output: >
    the scheduled-output-missing event title for the silent run, OR empty array
    after recovery (a healthy producer throws nothing — zero events is itself
    diagnostic per the prior learning). NO ssh.
```

## Domain Review

**Domains relevant:** Engineering (infra/ops). Product NONE (no user-facing
surface — backend cron producers; no file under components/**, app/**/page.tsx,
or app/**/layout.tsx). No GDPR surface (no schema/auth/API-route/.sql change; no
new LLM-on-operator-data processing activity — the crons already spawn claude on
the public repo). No new infrastructure (turn-budget/prompt edits against
already-provisioned Inngest functions; no new server/secret/vendor/runtime).

The mechanical UI-surface override did not fire (Files-to-Edit contains no
UI-surface path). Phase 2.7 GDPR gate and Phase 2.8 IaC gate skip silently
(no regulated-data surface, no new infrastructure). Phase 2.9 Observability gate
SATISFIED (section above).

No cross-domain implications beyond Engineering — backend ops remediation.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-content-generator.ts` — `--max-turns` 50 → 80 (H1).
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts` — `--max-turns` 40 → 80 + header/I3 ratio comments (H2).
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — evidence-driven fix from Phase 1 (H3: dedup-window OR prompt-ordering; ONLY what `4d67bdc8…` justifies).
- `apps/web-platform/test/server/cron-content-generator.test.ts` — failing-test-first for the new budget literal.
- `apps/web-platform/test/server/cron-roadmap-review.test.ts` — same.
- `apps/web-platform/test/server/cron-community-monitor.test.ts` — anchor update IFF a Phase-1-justified prompt edit lands (else untouched).

(Exact test paths to confirm against `vitest.config.ts include:` globs at /work — webplat collects `test/**/*.test.ts`, not co-located.)

## Files NOT to Edit (deliberate scope-out)

- `_cron-shared.ts`, `_cron-claude-eval-substrate.ts`, `cron-cloud-task-heartbeat.ts`, `app/api/inngest/route.ts` — the observability/substrate/registry layers are working correctly (both watchdogs fired). Touching them is scope creep. (Exception: if Phase 1 proves NOT-FIRING-at-all, the registry/scheduler path comes into scope and this plan re-scopes per Phase 1.4.)

## Open Code-Review Overlap

None — to be confirmed at /work via `gh issue list --label code-review --state open --json number,title,body` against the Files-to-Edit list. (Ran the cron-producer file set against open review issues; no current overlap expected, but re-verify after the file list is final per Phase 1.7.5.)

## Alternative Approaches Considered

| Approach | Why not (default) |
|---|---|
| Narrow allowedTools to `Bash(gh …:*)` (daily-triage shape) across all three | REFUTED as the primary cause by the prior learning; a behavior change, not a silence fix. Pursue only if Phase 1 surfaces a permission-denied line (H4). |
| Inngest-dispatches-GHA hybrid (move spawn to a GHA runner) | That shape is for CREDENTIAL-HEAVY INFRA crons (terraform). ADR-033 deliberately keeps agent-loop crons in-process for replay-safety/observability. Out of scope. |
| `Closes #4927/#4928` in PR body | False-resolves before the producer recovers (watchdog auto-closes on recovery). Rejected for `Ref` (Research Reconciliation row 4). |
| Bump turn budget without a live FIRING-vs-FAILING probe | Violates the learning's Key Insight (confirm hypotheses against runtime evidence). Phase 1 is non-negotiable. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- The community-monitor 06-04 event exited **0**, NOT exit-1 "Reached max turns" — do NOT pattern-match it to the cb54618d max-turns story. Read the live `stdoutTail`/`stderrTail` from `4d67bdc8…` first.
- roadmap-review was migrated at #4423 (d1e61d52), NOT at the 5b2c1922 boundary — its silence correlates with the broad TR9 window but is not single-commit-pinned. Trust the live probe.
- `verifyScheduledIssueCreated` credits a dedup-COMMENT (updated_at moves), so a roadmap/community dedup that COMMENTS is healthy/green; a dedup that EXITS WITHOUT commenting is the silent-no-op. Any dedup fix must comment, not just skip.
- Sentry token is `SENTRY_ISSUE_RW_TOKEN` (Doppler `soleur/prd`), org-issues endpoint, `statsPeriod` ∈ {`''`,`24h`,`14d`}. `SENTRY_AUTH_TOKEN`/`SENTRY_API_TOKEN` 403; `90d` → 400.
- Account-scoped Inngest concurrency (`key "cron-platform"`, limit 1) means fire the three manual-triggers SEQUENTIALLY in Phase 1/4 — a parallel fire queues behind the in-flight run.
- Re-derive the route.ts registry line count and the `--max-turns` literals at /work — sibling PRs shift both.
