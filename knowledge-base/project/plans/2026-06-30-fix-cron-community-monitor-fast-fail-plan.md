---
title: "fix(cron): root-cause + harden cron-community-monitor daily `error` fast-fail (since 2026-06-22)"
issue: 5732
branch: feat-one-shot-5732-cron-community-monitor-fast-fail
type: bug
lane: cross-domain  # no spec.md present → defaulted to cross-domain (TR2 fail-closed)
brand_survival_threshold: none
created: 2026-06-30
status: draft
---

# fix(cron): root-cause + harden `cron-community-monitor` daily `error` fast-fail 🐛

## Overview

`cron-community-monitor` (Inngest, `0 8 * * *` UTC) has posted a daily Sentry
`?status=error` check-in since **2026-06-22** with a handler wall-clock the issue
reports at **~300 ms** — far too fast for the ~50-min inline `claude-eval`. The
daily community digest is very likely **not being generated**. This is a distinct
defect class from #5728 (the `missed`-not-`error` *delivery* defect for
2026-06-13→06-21) and from H10 Anthropic credit exhaustion (reported resolved by
operator top-up 2026-06-29).

**This plan is investigation-first with a conditional, evidence-gated fix.** The
single most load-bearing rule here is the 2026-06-30 Concierge-strand learning
(`knowledge-base/project/learnings/2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`):
a recurring production symptom that survived prior fixes (#5728/#5674) must be
root-caused from **production observability** — proving *which* code path actually
executes on the affected surface — **before** any code is changed. Phase 0 is that
gate; no implementation phase runs until Phase 0 names the executing path with
runtime evidence.

### Live evidence already pulled at plan time (2026-06-30 ~06:30 UTC)

These reads were performed during planning and shape the hypotheses below. They are
**not** a substitute for the Phase 0 gate (the decisive 06-30 08:00 UTC fire had
not yet occurred at plan time).

1. **Sentry check-in timeline** (`GET de.sentry.io/.../monitors/scheduled-community-monitor/checkins/`, read with `SENTRY_IAC_AUTH_TOKEN` from Doppler `soleur/prd_terraform`):

   | window | status |
   |---|---|
   | 06-10 → 06-12 | `ok` |
   | 06-13 → 06-21 | `missed` (the #5728 SIGKILL/timing window) |
   | 06-22 → 06-29 | `error` daily (the #5732 window) — last `error` 06-29T08:01:31Z |

2. **Fleet correlation.** A sibling output-aware cron, `cron-seo-aeo-audit`, has a
   Sentry exception issue with **`firstSeen` exactly 2026-06-22T08:01:02Z**, titled
   *"cron-seo-aeo-audit spawn exited non-zero AND created no scheduled-seo-aeo-audit
   issue in the run window"* (the `resolveOutputAwareOk` "spawn ran, produced no
   output" RED). This is the **fleet-wide credit-exhaustion (H10) signature** — the
   eval *ran* and failed.

3. **The community-monitor anomaly.** Unlike seo-aeo, community-monitor has **no**
   `scheduled-output-missing` exception event and **no** `setup-ephemeral-workspace`
   /`handler-body-threw` exception event — only the generic Sentry cron-monitor
   alert *"Cron failure: scheduled-community-monitor"* (`firstSeen` 06-16, count 14).
   So community-monitor is posting `?status=error` via a path that emits **no**
   distinguishing exception event, and (per the ~300 ms duration) the eval is **not
   running**. This absence is itself a diagnosis gap (see Hypotheses + the
   observability deliverable).

### Why ~300 ms is decisive

`mintInstallationToken` runs (and succeeds — it does a `GET …/installation` before
minting; an installation-gone error would throw *there*, propagate, and surface as
`missed`, not `error`). A successful `git clone --depth=1` of `jikig-ai/soleur`
takes seconds, not 300 ms. Therefore a 300 ms total handler that posts `error`
means the eval never started — the failure is **pre-eval**, in `setup-workspace`,
and (since mint succeeded) **clone-specific** OR a fast pre-clone fault. See
Hypotheses for the discriminated branches.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase / live reality | Plan response |
|---|---|---|
| `routine_runs` shows **`completed`** for 06-22→29 (+ ~300 ms) | `run-log.ts:161` sets `failed = threw \|\| data?.ok === false`; `run-log.ts:57-60` documents this `{ok:false}→failed` detection was **added by #5674**. A handler that *returns* `{ok:false}` (the `setup-workspace` catch at `cron-community-monitor.ts:356` and the output-aware-RED return at `:524`) logs **`completed` under the pre-#5674 middleware** but **`failed`** after it. | The issue's `completed` is consistent with a `{ok:false}` return under the old middleware (learning `2026-06-29-cron-health-run-log-green-masks-claude-eval-failure.md`). **Phase 0 re-pulls `routine_runs` for 06-22→06-30** to read the *live* `status` + `error_summary` + `duration_ms`; whichever it is now discriminates the path. Do **not** treat "completed" as "succeeded." |
| Fast-fail is `token mint / clone / setup-workspace / classify-fatal early return` | `classify-fatal` (`_cron-shared.ts` `resolveBestEffortEvalOk`) runs **only** for best-effort crons and **only after the eval produced a tail** — it **cannot** fire for community-monitor (an output-aware producer) on a pre-eval failure. Mint failure surfaces as `missed`, not `error`. | Narrow the candidate set to the `setup-workspace` catch (`cron-community-monitor.ts:337-357`) and the output-aware-RED path. Phase 0 confirms which. |
| 06-22→29 `error` is Anthropic **credit exhaustion** (per #5728 body) | Credit affects the **eval** (claude API), not `git clone`; the 300 ms duration excludes a credit failure *inside* the eval for community-monitor. The fleet-wide 06-22 onset (seo-aeo) **is** credit, but community-monitor's path differs (no output-missing event, 300 ms). | Treat credit as the fleet *backdrop* (already topped up 06-29) but **not** community-monitor's proximate cause unless Phase 0 evidence shows its eval actually ran. |

## User-Brand Impact

**If this lands broken, the user experiences:** the operator's daily community
digest GitHub issue (`[Scheduled] Community Monitor - YYYY-MM-DD`) and
`knowledge-base/support/community/<date>-digest.md` silently stop being produced —
the operator loses daily Discord/X/Bluesky/LinkedIn/GitHub/HN visibility while the
generic monitor pages noisily.

**If this leaks, the user's data is exposed via:** N/A — this cron reads only
public/aggregate platform metrics, never stores raw transcripts (prompt enforces
aggregate-only), and the fix touches infra/observability, not data handling. No new
data-movement surface.

**Brand-survival threshold:** none — internal operator-facing monitoring tooling;
single-operator product, no external user data surface. `cron-community-monitor.ts`
is server code but matches no sensitive-path (auth/schema/migration/`.sql`) class.
Reason recorded for preflight Check 6: this plan touches no sensitive path and adds
no data-movement surface; it hardens observability and root-causes a fast-fail.

## Hypotheses

Ranked; **each is a Phase-0-falsifiable branch.** The fix taken depends on which
Phase 0 confirms. Per `hr-no-dashboard-eyeball-pull-data-yourself`, every branch is
discriminated by a pulled datum, not a dashboard glance.

- **H-A — clone fast-fail, `ENOSPC` (disk full).** The 06-13→21 `missed` window was
  mid-eval SIGKILLs (H11a). `teardownEphemeralWorkspace` runs in `finally` and is
  **skipped on SIGKILL**, so each killed run orphaned a `soleur-cron-community-monitor-*`
  workspace under `CRON_WORKSPACE_ROOT` (`/workspaces` on `/mnt/data`). Accumulation
  could cross the volume full ~06-22 → `git clone` fails fast with *"No space left on
  device"* every fire thereafter (monotonic, deterministic, daily — fits the regime
  shape). `warnIfCronWorkspaceLowOnDisk` (`_cron-shared.ts:137`) would have WARNed
  pre-fail. **Signal:** clone stderr in the `setup-ephemeral-workspace` Sentry event
  / Better Stack contains `No space left on device`; `df`-style low-disk WARN events
  present 06-2x. **Fix:** automated orphan-workspace reclaim (a sweep in
  `setupEphemeralWorkspace` and/or a maintenance step) + **promote the low-disk warn
  to a loud, self-diagnosing pre-clone failure** — never an operator SSH (`hr-no-ssh-fallback-in-runbooks`, `hr-all-infrastructure-provisioning-servers`).
- **H-B — clone fast-fail, auth/egress/DNS.** Minted token lacks `contents:read`, or
  the Tier-2 container egress firewall / DNS blocks the clone host. **Signal:** clone
  stderr shows `403`/`Authentication failed`/`Could not resolve host`. **Fix:** token
  scope (`DEFAULT_CRON_TOKEN_PERMISSIONS`) or egress-allowlist (`cron-egress-allowlist.txt`) correction.
- **H-C — eval actually ran; credit (H10).** If Phase 0 shows `duration_ms ≫ 300`,
  a `scheduled-output-missing` event, and spawn-non-zero, then it is the fleet credit
  outage — **already resolved 2026-06-29**. **Fix:** verify recovery only + Sentry
  monitor un-mute (below) + close as resolved-by-#5674-top-up. (Down-weighted: the
  300 ms duration + missing output event argue against this for community-monitor.)
- **H-D — error posted with no exception event (observability hole).** community-monitor
  reaches a `?status=error` with no `reportSilentFallback` exception (the empirically
  observed state). Whatever the proximate cause, the next pre-eval fast-fail is **not
  self-diagnosing without SSH** — a defect in itself. **Fix:** the durable
  observability deliverable below, regardless of A/B/C.

> Network-outage checklist note: the `error`/clone hypotheses are connectivity-adjacent.
> H-B explicitly puts **firewall + egress IP + DNS verification BEFORE** any
> service-layer hypothesis, per `hr-ssh-diagnosis-verify-firewall`.

## Implementation Phases

### Phase 0 — Evidence gate (mandatory; no code until this names the executing path)

0.1 **Trigger a fresh post-top-up run** (satisfies issue acceptance #1 without
   waiting for 08:00). Prefer, in order: (a) the natural `0 8 * * *` fire if planning
   completes near 08:00 UTC; (b) the `cron/community-monitor.manual-trigger` event if
   it is allowlisted in `apps/web-platform/app/api/internal/trigger-cron` /
   `soleur:trigger-cron` (verify the allowlist first — at plan time community-monitor
   was **not** found in the trigger-cron endpoint; if absent, do **not** invent an SSH
   path — fall back to (a) and record `automation-status` accordingly). Capture the
   fire's `run_id`/timestamp.
0.2 **`routine_runs` (authoritative).** Read-only SQL via Doppler `soleur/prd`
   `DATABASE_URL_POOLER` (`:6543`→`:5432` session mode; pooler self-signed →
   `ssl:{rejectUnauthorized:false}` transient verify script — `psql`/`pg` are **not**
   installed in this worktree, so use the runbook's transient node+pg verify script).
   For `cron-community-monitor` rows 06-22→06-30: `status`, `error_summary`,
   `duration_ms`, `started_at` (start_lag vs 08:00), `trigger_source`. Settles the
   `completed`-vs-`failed` reconciliation and the real duration.
0.3 **Sentry exception events** (not just the monitor alert). Confirm/refute the
   plan-time finding that community-monitor has **no** `feature:cron-community-monitor`
   exception (`op:setup-ephemeral-workspace` / `handler-body-threw` /
   `scheduled-output-missing`). If one exists, read its title (the redacted clone
   stderr / spawn tail) — that string discriminates H-A vs H-B vs H-C.
0.4 **Better Stack stdout tail** of the freshest fire (`scripts/betterstack-query.sh`
   under `doppler run -p soleur -c prd_terraform`; hot retention ~1 h, so pull the
   0.1 fire promptly): the `git clone` stderr line, the low-disk WARN, the last
   `claude-eval`/`sentry-heartbeat` log line per run.
0.5 **Disk state** (H-A): from the freshest fire's Better Stack output and any
   `warnIfCronWorkspaceLowOnDisk` event, read the `CRON_WORKSPACE_ROOT` free bytes and
   count orphaned `soleur-cron-community-monitor-*` dirs (read-only; no SSH — derive
   from logged events, not a host shell).
0.6 **Write the verdict** into the plan's Research Reconciliation as a 1-paragraph
   "Phase 0 finding": the named executing path + the discriminated branch (A/B/C/D),
   with the citing datum. **This is the gate** — `/work` proceeds to the matching fix
   branch only; if evidence is ambiguous, fire one more run and re-pull (do not guess
   the layer — `2026-06-30-verify-the-fixed-code-path...`).

### Phase 1 — Sentry monitor un-mute / re-enable (runs regardless of branch)

After 8+ days unhealthy, Sentry auto-mutes then disables a cron monitor; a disabled
monitor ignores a recovery `?status=ok` until re-enabled (runbook H10). Read state
(`GET …/monitors/scheduled-community-monitor/` → `{status, isMuted}`) with
`SENTRY_IAC_AUTH_TOKEN` (`project:admin`); if `disabled`/muted, `PUT
{"status":"active","isMuted":false}`. EU regional host `de.sentry.io`, org in path
(ADR-031). Fall back to the Sentry dashboard **only** on a confirmed API-write 403,
recording a `playwright-attempt:` evidence line. (At plan time only the GET form is
live-verified; the PUT is unverified — treat a 403 as the dashboard-fallback trigger.)

### Phase 2 — Conditional root-cause fix (branch on Phase 0 verdict)

- **If H-A (ENOSPC):** add an **automated** orphan-workspace reclaim — sweep stale
  `soleur-*` dirs older than a TTL under `CRON_WORKSPACE_ROOT` at the start of
  `setupEphemeralWorkspace` (and/or a small maintenance step) — and **promote
  `warnIfCronWorkspaceLowOnDisk` from warn-only to a loud pre-clone failure** below a
  hard free-bytes floor so the next disk-fill is self-diagnosing (`error_summary` +
  Sentry op carry the free-bytes). No SSH/operator disk step.
- **If H-B (auth/egress):** correct `DEFAULT_CRON_TOKEN_PERMISSIONS` scope OR
  `apps/web-platform/infra/cron-egress-allowlist.txt`; verify the firewall/egress IP
  + DNS first (`hr-ssh-diagnosis-verify-firewall`). Egress/firewall changes route
  through IaC (Phase 2.8), never a hand-edit on the host.
- **If H-C (credit, already resolved):** no code fix; Phase 1 un-mute + a Phase-0
  recovery confirmation is the close. Record that #5674's top-up resolved it.

### Phase 3 — Durable observability hardening (runs unless Phase 0 proves it already self-diagnosed)

Close the H-D gap so a pre-eval fast-fail is **self-diagnosing without SSH**: the
`setup-workspace` catch (`cron-community-monitor.ts:337-357`) currently returns
`{ok:false}` with **no `errorSummary` field**, so `routine_runs.error_summary` falls
back to the generic *"cron returned ok:false (see Sentry)"* (`run-log.ts:185-189`)
and the cause lives only in a Sentry event that (empirically) was absent/ungroupable.
Thread the redacted setup-failure reason into the handler's `{ok:false}` return so it
lands in `routine_runs.error_summary` (and verify the `setup-ephemeral-workspace`
Sentry event groups searchably). **Constraint:** preserve ADR-033 I5's deterministic
`step.run` return shape — extend the *handler* return, not the substrate
`SpawnResult`. Apply the same hardening to the cohort siblings only if the precedent
diff (deepen-plan Phase 4.4) shows they share the gap (scope-out otherwise).

### Phase 4 — Regression test (cq-write-failing-tests-before)

The repo-research-analyst confirmed **no** test exercises the `setupEphemeralWorkspace`
throw → `error`-heartbeat flow. Add a RED-first test in
`apps/web-platform/test/server/inngest/cron-community-monitor-heartbeat.test.ts` (or
`cron-community-monitor.test.ts`): mock `setupEphemeralWorkspace` to throw a
clone/ENOSPC error → assert exactly one `?status=error` heartbeat AND (Phase 3) that
the handler return carries the scrubbed reason that the run-log middleware maps to
`routine_runs.error_summary`. For H-A, add a substrate unit test in
`cron-claude-eval-substrate.test.ts` for the orphan-reclaim sweep + the hard low-disk
floor (synthesized fixtures only — `cq-test-fixtures-synthesized-only`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Phase 0 verdict recorded.** The plan/PR body names the executing path
  for the 06-22→ `error` regime with a citing datum (`routine_runs.status` +
  `error_summary` + `duration_ms` for a 06-22→06-30 row, and the Sentry exception
  title or its confirmed absence). No code in the PR predates this verdict.
- [ ] **AC2 — branch-matched fix only.** The diff implements exactly the Phase-0
  branch (A/B/C/D); no fix for a layer Phase 0 did not confirm executes.
- [ ] **AC3 — regression test RED→GREEN.** The Phase 4 test fails on `main` (or a
  stubbed pre-fix tree) and passes post-fix: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor-heartbeat.test.ts test/server/inngest/cron-claude-eval-substrate.test.ts`.
- [ ] **AC4 — observability post-condition (Phase 3).** A simulated `setup-workspace`
  throw yields a non-generic `routine_runs.error_summary` carrying the scrubbed
  reason (asserted in the test against the run-log mapping), not the
  `"cron returned ok:false"` fallback.
- [ ] **AC5 — typecheck.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] **AC6 — no ADR/C4 drift.** `### C4 views` enumeration holds (no new external
  actor/system/relationship); `apps/web-platform/test/c4-code-syntax.test.ts` +
  `c4-render.test.ts` green if touched.
- [ ] **AC7 — PR body uses `Ref #5732`** (not `Closes`) if any verification/close step
  is post-merge/operator-gated; otherwise `Closes #5732`.

### Post-merge (operator/automated)

- [ ] **AC8 — recovery confirmed.** After deploy, the next `cron-community-monitor`
  fire (natural 08:00 or manual-trigger) produces a real digest issue
  `[Scheduled] Community Monitor - <date>` AND a `?status=ok` Sentry check-in. Pulled
  via `routine_runs` + the Sentry checkins endpoint (no dashboard eyeball).
- [ ] **AC9 — monitor healthy.** `GET …/monitors/scheduled-community-monitor/` returns
  `status:active, isMuted:false` and a fresh `ok` check-in (Phase 1).
- [ ] **AC10 — soak follow-through enrolled.** AC8's "stays `ok` for N days" close
  criterion is enrolled as a follow-through probe (see Soak section), not left to
  memory.

## Observability

```yaml
liveness_signal:
  what: scheduled-community-monitor Sentry cron check-in (?status=ok|error) + daily [Scheduled] Community Monitor digest issue
  cadence: daily 08:00 UTC (cron 0 8 * * *)
  alert_target: Sentry cron monitor scheduled-community-monitor (margin 60m) + missed-checkin backstop
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf ; postSentryHeartbeat (_cron-shared.ts:271)
error_reporting:
  destination: Sentry via reportSilentFallback (feature:cron-community-monitor) + routine_runs.error_summary (Supabase, via run-log.ts middleware)
  fail_loud: true  # Phase 3 promotes the setup-workspace catch reason into routine_runs.error_summary (no longer the generic "cron returned ok:false" fallback)
failure_modes:
  - mode: pre-eval clone ENOSPC (H-A)
    detection: clone stderr "No space left on device" in setup-ephemeral-workspace Sentry event + low-disk WARN; routine_runs.error_summary (Phase 3)
    alert_route: Sentry monitor error + scheduled-output-missing audit issue
  - mode: pre-eval clone auth/egress/DNS (H-B)
    detection: clone stderr 403/auth/resolve-host in Sentry event / Better Stack tail
    alert_route: Sentry monitor error
  - mode: eval ran, credit/key (H-C / H10)
    detection: cron-anthropic-credit-probe RED (op=anthropic-credit-exhausted) + scheduled-output-missing event + duration_ms >> 300
    alert_route: scheduled-anthropic-credit-probe monitor + community-monitor monitor
  - mode: error posted with no exception event (H-D)
    detection: Sentry checkin error with NO feature:cron-community-monitor exception (the plan-time observed gap) — closed by Phase 3
    alert_route: Sentry monitor error (generic) → Phase 3 makes it self-diagnosing
logs:
  where: Better Stack (Vector-shipped app stdout/stderr tail; ADR-033 I5 discards full stdout — only the bounded SpawnResult tail + reportSilentFallback reach Sentry) ; routine_runs (Supabase, durable)
  retention: Better Stack hot ~1h ; routine_runs durable (middleware since 2026-06-16)
discoverability_test:
  command: "doppler run -p soleur -c prd -- <transient node+pg verify script> 'select status,error_summary,duration_ms,started_at from routine_runs where routine=$1 and started_at > now() - interval $2 order by started_at desc' (params: cron-community-monitor, '10 days')  AND  doppler run -p soleur -c prd_terraform -- curl -s .../monitors/scheduled-community-monitor/checkins/"
  expected_output: post-fix — most recent row status=completed/ok with a real duration and a digest issue filed; Sentry checkin status=ok
```

## Architecture Decision (ADR/C4)

**No architectural decision.** This is a bug fix + observability hardening inside the
existing Inngest claude-eval cron substrate (ADR-033 governs; no invariant changes —
Phase 3 explicitly preserves I5's deterministic `step.run` return shape by extending
the *handler* return, not `SpawnResult`). If Phase 0 lands H-B (egress/firewall), the
change routes through existing IaC (`cron-egress-allowlist.txt`) under an established
pattern — still not a new decision.

**### C4 views — no impact (enumerated against all three `.c4` files).** Reviewed
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`:
(a) **external human actors** — none added (the operator already models the cron
consumer); (b) **external systems/vendors** — Discord/X/Bluesky/LinkedIn/HN/GitHub
already modeled as the community-monitor's external read sources; no new vendor edge
(Anthropic/Sentry/Better Stack/Supabase already present); (c) **containers/data
stores** — none added (`routine_runs` in Supabase already modeled); (d)
**access relationships** — unchanged. The fix adds no element, tag, or edge — it
reclaims disk / corrects scope / threads an existing error string. `### C4 views`
task: none. (Deepen-plan re-verifies this enumeration against the live `.c4`.)

## Domain Review

**Domains relevant:** Engineering (CTO) — infra/observability/cron. Support (CCO) —
the affected artifact is the community digest, but the FIX is infra, not community
strategy (advisory only).

### Engineering (CTO)
**Status:** to-confirm at deepen-plan/domain-sweep
**Assessment:** Cron substrate bug + observability hardening. Risk surfaces: (1) the
H-A orphan-reclaim sweep must not delete a *live* concurrent run's workspace (TTL +
the `account:cron-platform limit:1` concurrency bounds this); (2) Phase 3 must
preserve ADR-033 I5; (3) any egress/disk remediation must be automated, never SSH.

### Product/UX Gate
**Tier:** NONE — no user-facing surface; `## Files to Edit` contains no `components/**`,
`app/**/page.tsx`, or `app/**/layout.tsx`. Skipped.

## Open Code-Review Overlap

None — to be confirmed at deepen-plan once `## Files to Edit` is finalized
(`gh issue list --label code-review --state open` grep of the touched paths:
`cron-community-monitor.ts`, `_cron-claude-eval-substrate.ts`, `_cron-shared.ts`,
`run-log.ts`, the two test files).

## Files to Edit (provisional — finalized by Phase 0 branch)

- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — Phase 3 (thread setup-failure reason into the `{ok:false}` return).
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — H-A (orphan-reclaim sweep + hard low-disk floor in `setupEphemeralWorkspace`).
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — H-A (`warnIfCronWorkspaceLowOnDisk` → loud failure) / H-B (`DEFAULT_CRON_TOKEN_PERMISSIONS`).
- `apps/web-platform/infra/cron-egress-allowlist.txt` — H-B only.
- `apps/web-platform/test/server/inngest/cron-community-monitor-heartbeat.test.ts` — Phase 4.
- `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` — Phase 4 (H-A sweep/floor).

## Soak Follow-Through Enrollment

AC8/AC9 declare a post-deploy soak ("digest + `ok` check-in hold for N days"). Enroll
a probe `scripts/followthroughs/community-monitor-recovered-<5732>.sh` (mirror
`community-monitor-checkin-soak-5728.sh` / `reconcile-ff-only-sentry-4977.sh`, `start=`
pinned strictly after deploy; exit 0 when the soak holds), add the tracker's
`<!-- soleur:followthrough script=… earliest=<deploy+Nd> secrets=SENTRY_IAC_AUTH_TOKEN,DATABASE_URL_POOLER -->`
directive + `follow-through` label, and wire any new `secrets=` into
`.github/workflows/scheduled-followthrough-sweeper.yml`. Builds at /work, enforced at
ship Phase 5.5.

## Test Scenarios

1. `setupEphemeralWorkspace` throws a clone error → handler posts exactly one
   `?status=error` heartbeat, returns `{ok:false}` carrying the scrubbed reason; no
   second/conflicting heartbeat (memoization-safe).
2. `DeployInProgressError` from `setup-workspace` → bare rethrow, NO heartbeat (benign
   defer; unchanged — regression guard).
3. (H-A) `setupEphemeralWorkspace` with N stale `soleur-*` dirs present → sweep removes
   only those older than the TTL, never the current run's `spawnCwd`.
4. (H-A) free bytes below the hard floor → loud pre-clone failure with free-bytes in
   the error, not a silent warn-and-continue.
5. (Phase 3) run-log middleware maps the handler's `{ok:false, errorSummary}` to a
   non-generic `routine_runs.error_summary`.

## Risks & Sharp Edges

- **Wrong-layer fix (the headline risk).** Shipping a code fix before Phase 0 names
  the executing path repeats the 2026-06-30 Concierge-strand failure (two merged fixes
  the surface never executed). Phase 0 is a hard gate; AC1/AC2 enforce it.
- **A plan whose `## User-Brand Impact` is empty/placeholder fails deepen-plan Phase
  4.6** — filled above (threshold `none` + reason).
- **H-A sweep deleting a live workspace.** Bound by TTL + `cron-platform` concurrency
  limit 1; test scenario 3 guards it.
- **ADR-033 I5 drift.** Phase 3 must extend the handler return, not `SpawnResult`;
  deepen-plan Phase 4.4 precedent-diff against the cohort.
- **`Closes` vs `Ref`.** If recovery/un-mute is post-merge, use `Ref #5732` + a
  post-merge `gh issue close` after AC8 confirms (`wg-use-closes-n-in-pr-body-not-title`
  / the ops-remediation Sharp Edge).
- **Credit self-resolution.** If Phase 0 lands H-C, resist building an ENOSPC/auth fix
  for a cause that already self-resolved — the durable deliverables are Phase 1
  un-mute + Phase 3 observability + Phase 4 test, not a speculative clone fix.
- **`routine_runs` access:** `psql`/`pg` are NOT installed in this worktree and `doppler
  run`'s PATH lacks `psql`; use the runbook transient node+pg verify script
  (`ssl:{rejectUnauthorized:false}`), not a bare `psql`.
