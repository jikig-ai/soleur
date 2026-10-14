---
title: "fix(cron): root-cause + harden cron-community-monitor daily `error` fast-fail (since 2026-06-22)"
issue: 5732
branch: feat-one-shot-5732-cron-community-monitor-fast-fail
type: bug
lane: cross-domain  # no spec.md present → defaulted to cross-domain (TR2 fail-closed)
brand_survival_threshold: none
created: 2026-06-30
status: resolved  # Phase 0 verdict H-C: fast-fail self-resolved via Anthropic credit top-up (2026-06-29). No code fix warranted. See "Phase 0 Finding" below.
---

## Phase 0 Finding — VERDICT: H-C (no code fix) — recorded 2026-06-30

**The ~300 ms fast-fail (#5732) was Anthropic credit exhaustion (H10/H-C), resolved
by the operator's 2026-06-29 top-up.** The evidence gate (read-only production pulls
+ one allowlisted manual `cron/community-monitor.manual-trigger`, fired 06:59:37Z)
settled all three hypotheses:

- **H-C CONFIRMED — credit, already resolved.** The fresh post-top-up fire's clone
  **succeeded** and logged `claude-eval spawned` (Better Stack, 06:59→07:05Z); it
  produced **real digest issues `#5737` (07:04Z) + `#5740` (07:08Z)** — full
  platform-status/metrics digests, not error stubs. Contrast: eight consecutive
  `completed` rows with `duration_ms` 241–387 ms and `error_summary = null`,
  06-22→06-29. The eval now runs; the daily digest is producing again.
- **H-B (codeload egress) REFUTED.** The live clone succeeded → codeload was not
  dropped. No `op:setup-ephemeral-workspace` Sentry exception exists (queried by the
  `op:` tag, HTTP 200 empty — not a search artifact). The `codeload.github.com`
  allowlist gap is real but **latent** (resolves inside the `github.com` CIDR set
  today), not the cause. No allowlist/ADR-052 change shipped.
- **H-A (ENOSPC/disk) REFUTED.** `cron-workspace-gc` ran a clean 6 h cadence with
  zero gaps through 06-30 (56 `completed` rows) → no 8-day disk fill.

**Branch outcomes:** Phase 2 H-B/H-A → **none** (both refuted). Phase 1 un-mute →
**not needed** (monitor `scheduled-community-monitor` is `active`/`isMuted=false`).
Phase 3 `:356` threading → **not shipped** (the setup-workspace catch does NOT
execute on the recovered fire — gated out by its own "catch path executes" guard;
hardening a dormant path is the headline wrong-layer risk). Phase 4 regression test
→ **not shipped** (tied to the fast-fail path, which no longer executes).

**Residual (NOT #5732, NOT new):** the recovered 06-30 fires still show a `missed`
Sentry check-in ("digest produced, check-in not delivered") — this is precisely the
**#5728** delivery-defect class (closed 2026-06-30T06:10Z, fix `b1c560dad`), pending
deploy. A possible duplicate-digest anomaly (`#5737` + `#5740` from one trigger) is
noted for the operator but not chased here. Ongoing `error`-regime regression is
covered by the Sentry cron monitor's auto-page; `missed` regression by the #5728
delivery soak. **No new probe added** (plan's simplicity caveat; AC10 N/A for H-C).

# fix(cron): root-cause + harden `cron-community-monitor` daily `error` fast-fail 🐛

## Enhancement Summary (deepen-plan 2026-06-30)

Deepened with 5 parallel agents (observability-coverage, architecture-strategist,
code-simplicity, silent-failure-hunter, Network-Outage L3 deep-dive) + 2 research
agents. Load-bearing corrections folded in:

1. **Leading pre-eval hypothesis is now concrete (H-B / codeload egress).** Network L3
   deep-dive: `apps/web-platform/infra/cron-egress-allowlist.txt` allowlists
   `github.com` + `api.github.com` but **NOT `codeload.github.com`** — the host a
   `git clone --depth=1` redirects to for shallow pack delivery. nftables default-drop
   (`cron-egress-nftables.sh:151,154`) → immediate kernel rejection → ~300 ms fast-fail.
   This explains the symptom precisely. Open reconciliation: the gap is *standing* (no
   allowlist change in-window), yet the eval ran 06-13→21 — so the 06-22 onset must be a
   **CIDR/IP-rotation drift** (codeload's Fastly IPs falling out of the resolved
   `github.com` CIDR set; cf. #5413 grace-window commit `f743bc263`). Phase 0 settles it.
2. **H-A's reclaim already has an owner — my "no precedent" claim was WRONG.**
   `apps/web-platform/server/inngest/functions/cron-workspace-gc.ts` already sweeps
   `soleur-*` dirs >60 min every 6 h (built for the leaked-clone→ENOSPC mode). H-A must
   **route through / harden the GC**, never add a second divergent sweep; Phase 0 must
   pull the GC's own health (was it down 06-13→22? — else H-A's accumulation narrative is
   incoherent). New Phase 0.7.
3. **Do NOT mutate `warnIfCronWorkspaceLowOnDisk`** — its docstring is an explicit
   MUST-NEVER-THROW fleet-wide contract (`_cron-shared.ts:129-133`); flipping it fatal
   could dark the whole cron fleet. Use a *separate* `assertCronWorkspaceFloor` fn if a
   hard floor is wanted.
4. **H-D was a category error** — it is a Phase-3 *deliverable*, not a cause. Demoted to a
   Phase-0 **fork**: per observability review, `reportSilentFallback` emits on 3 channels
   (`observability.ts:210,219-220` — Better Stack + pino→Sentry + direct
   `captureException` with `feature`/`op` tags), and the sibling seo-aeo cron *does* carry
   such an exception, proving the transport works. So the plan-time "no
   `setup-ephemeral-workspace` exception" is EITHER (a) my fuzzy Sentry search missing it
   (the catch ran — codeload H-B), OR (b) the catch did not run (re-discriminate). Phase 0
   must definitively confirm presence/absence of that exception.
5. **Decision collapsed to 1 datum then 1 datum** (simplicity): `duration_ms` forks
   credit-ran (H-C, already resolved) vs pre-eval; then the clone-stderr / Sentry-exception
   forks codeload-egress (H-B) vs disk (H-A). The H-A *build* is deferred until Phase 0
   reproduces ENOSPC AND shows the GC failed.
6. ADR-033 I5 widening confirmed sound (middleware already reads `data.errorSummary`,
   `run-log.ts:158-189` — zero middleware change). Phase 4 test must assert the **literal**
   `errorSummary` field name + exact scrubbed reason. Soak-enrollment + C4 prose trimmed.

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
single-operator product, no external user data surface.

`threshold: none, reason: the diff touches apps/web-platform/server/** (a sensitive
path) but adds no auth/data-movement/credential surface — it reclaims disk / corrects
a token scope or egress allowlist / threads an existing scrubbed error string into
routine_runs, and hardens observability for a cron fast-fail.` (scope-out bullet for
preflight Check 6 / deepen Phase 4.6, since `cron-community-monitor.ts` lives under
`apps/web-platform/server`.)

## Hypotheses

**The whole investigation is a 2-step decision tree on pulled data** (`hr-no-dashboard-eyeball-pull-data-yourself`), not four co-equal branches:

```
Step 1 — routine_runs.duration_ms of a fresh post-top-up fire (Phase 0.1/0.2):
  ≫ 300 ms  → the eval RAN → H-C (Anthropic credit / H10) → already resolved 06-29 → NO code fix
  ≈ 300 ms  → pre-eval fast-fail → go to Step 2
Step 2 — the setup-workspace failure signal (clone stderr + Sentry exception, Phase 0.3/0.4):
  "Connection refused"/firewall-drop on a codeload redirect → H-B (egress allowlist)
  "No space left on device" + GC was down (Phase 0.7)         → H-A (disk / cron-workspace-gc)
```

- **H-B — clone fast-fail on egress (LEADING pre-eval hypothesis; strong repo evidence).**
  `cron-egress-allowlist.txt` allowlists `github.com` + `api.github.com` but **NOT
  `codeload.github.com`** — the host `git clone --depth=1` redirects to for shallow pack
  delivery (documented off-allowlist in `learnings/bug-fixes/2026-06-10-sandbox-network-plane-not-token-plane-error-shape-triage.md:60-61`).
  The nftables ruleset default-drops un-allowlisted dests at the kernel
  (`cron-egress-nftables.sh:151,154`) → immediate rejection → ~300 ms (mint to
  api.github.com succeeds; clone to codeload is dropped). **Open reconciliation Phase 0
  must close:** the gap is *standing* (no in-window allowlist change) yet the eval ran
  06-13→21, so the 06-22 onset is an **IP/CIDR drift** — codeload's Fastly IPs falling
  out of the resolved `github.com` CIDR set the allowlist pins (`cron-egress-resolve.sh`;
  cf. #5413 grace-window commit `f743bc263`, 06-16). **Signal:** clone stderr =
  `Connection refused`/`Could not resolve host` (NOT a 403 auth error). **Fix:** add
  `codeload.github.com` to `cron-egress-allowlist.txt` (+ the CIDR resolve set) with an
  evidence comment, and amend ADR-052 (whose two-host model omits codeload). Verify
  firewall/egress-IP/DNS BEFORE any token-scope hypothesis (`hr-ssh-diagnosis-verify-firewall`).
- **H-A — clone fast-fail, `ENOSPC` (disk full) — reclaim already has an owner.** The
  06-13→21 SIGKILLs (`teardownEphemeralWorkspace` runs in `finally`, skipped on SIGKILL)
  orphan `soleur-*` workspaces under `CRON_WORKSPACE_ROOT` (`/workspaces`). **BUT
  `apps/web-platform/server/inngest/functions/cron-workspace-gc.ts` already sweeps
  `soleur-*` dirs >60 min every 6 h** for exactly this leak — so H-A is **incoherent
  unless the GC was itself down/failing 06-13→22** (a healthy GC would have reclaimed
  ~36 times before 06-22). **Phase 0.7 pulls the GC health.** **Signal:** clone stderr =
  `No space left on device` AND GC unhealthy in-window. **Fix (only if confirmed):** fix
  the **GC** (its outage is the root cause) and/or tune its cadence/TTL; if a *synchronous*
  pre-clone guard is genuinely needed, reuse the GC's exported `isSweepable` (do NOT fork
  a second policy) and add a *separate* `assertCronWorkspaceFloor` fn (do NOT mutate the
  MUST-NEVER-THROW `warnIfCronWorkspaceLowOnDisk`, `_cron-shared.ts:129-133`). **Defer the
  build until Phase 0 reproduces ENOSPC + GC-down.**
- **H-C — eval actually ran; credit (H10), already resolved.** `duration_ms ≫ 300` + a
  `scheduled-output-missing` event + spawn-non-zero ⇒ the fleet credit outage (the sibling
  seo-aeo signature) — topped up 2026-06-29. **Fix:** Phase 1 un-mute + a recovery
  confirmation; no code. (Down-weighted for community-monitor by the 300 ms duration.)

**Fork note (was "H-D") — the observability contradiction Phase 0 MUST resolve.** Whatever
the cause, the durable diagnosis gap is real: the `setup-workspace` catch returns
`{ok:false}` with no `errorSummary`, so `routine_runs.error_summary` is the generic
`"cron returned ok:false"` fallback (`run-log.ts:185-189`). **However**,
`reportSilentFallback` (`observability.ts:210,219-220`) emits on **three** channels —
`logger.error`→Better Stack, pino→Sentry, and a direct `Sentry.captureException` tagged
`feature:cron-community-monitor op:setup-ephemeral-workspace` — and the sibling seo-aeo
cron *does* carry such an exception, proving the transport works.

**The plan-time "no exception" finding is a SEARCH ARTIFACT, not evidence (silent-failure
review, HIGH).** `Sentry.captureException(err, {tags, extra})` (`observability.ts:218-221`)
does **not** pass the human `message` arg — so the Sentry issue **title = `err.message`**,
which for the setup catch is the redacted git-clone stderr built at
`_cron-claude-eval-substrate.ts:628-631` (e.g. `"git clone failed (exit 128 …): …"`). My
plan-time free-text searches (`"setup-ephemeral-workspace"` = only a `tags.op` value;
`"scaffold ephemeral"` = only the *dropped* `message` arg) appear **nowhere** in the title
or body → a guaranteed false-negative. So the exception **very likely exists** under its
git-clone-error title and my search simply could not match it. **Phase 0.3 MUST query by
the `op:` TAG (`op:setup-ephemeral-workspace`), never free text.** The likely truth: the
catch DID run (codeload H-B), and its exception title carries the decisive clone stderr.
(DSN-unset — which would make `captureException` a silent no-op while `?status=error` still
posts via the separate Crons-ingest `fetch` — is *refuted* by seo-aeo's event delivering
fleet-wide.) The Phase-3 `error_summary` threading is the durable fix for the diagnosis gap
**regardless of cause**, gated on Phase 0 confirming the catch is the executing path.

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
0.3 **Sentry exception events — query by `op:` TAG, NOT free text.** The plan-time
   free-text search was a guaranteed false-negative (the issue title = `err.message` =
   the git-clone stderr, NOT the `op` tag / dropped message arg — see the fork note).
   Pull `feature:cron-community-monitor` events filtered by tag
   `op:setup-ephemeral-workspace` (and `op:handler-body-threw`,
   `op:scheduled-output-missing`, `op:ensure-audit-issue-failed`). If the
   `op:setup-ephemeral-workspace` event exists, **its title is the redacted git-clone
   stderr**: `Connection refused`/`Could not resolve host` ⇒ H-B (codeload egress);
   `No space left on device` ⇒ H-A; absence across ALL ops ⇒ the catch did not run,
   re-discriminate. Also pull `feature:cron-sentry-heartbeat op:fetch` (the cross-tag
   heartbeat-POST-failure blind spot a community-monitor-scoped search misses).
0.4 **Better Stack stdout tail** of the freshest fire (`scripts/betterstack-query.sh`
   under `doppler run -p soleur -c prd_terraform`; hot retention ~1 h, so pull the
   0.1 fire promptly): the `git clone` stderr line (codeload `Connection refused`
   ⇒ H-B), the low-disk WARN, the last `claude-eval`/`sentry-heartbeat` log line per run.
0.5 **Disk state** (H-A): from the freshest fire's Better Stack output and any
   `warnIfCronWorkspaceLowOnDisk` event, read the `CRON_WORKSPACE_ROOT` free bytes and
   count orphaned `soleur-*` dirs (read-only; no SSH). **Chicken-and-egg caveat:** if no
   logged event carries free-bytes, H-A is **unconfirmable non-SSH on the current build**
   — do NOT read absence as refutation; ship the Phase-2 H-A instrumentation and
   discriminate on the next fire.
0.7 **`cron-workspace-gc` health for 06-13→22** (load-bearing for H-A; the GC owns
   orphan reclaim). Pull its Sentry monitor `scheduled-workspace-gc` check-ins +
   `routine_runs` rows + the `workspace-gc-sweep-complete`/`workspace-gc-low-after-sweep`
   freed-bytes events. **If the GC was healthy in-window, H-A's "disk filled over 8 days"
   is REFUTED** (a 6 h-cadence GC reclaims orphans ~36× before 06-22) — so H-A stands
   ONLY if the GC was itself down/failing, in which case **the GC outage is the root
   cause**, not a reason to duplicate its sweep.
0.6 **Write the verdict** into the plan's Research Reconciliation as a 1-paragraph
   "Phase 0 finding": the named executing path + the discriminated branch (H-B / H-A /
   H-C) + the citing datum (`duration_ms`, the `op:`-tag exception title, GC health).
   **This is the gate** — `/work` proceeds to the matching fix branch only; if evidence
   is ambiguous, fire one more run and re-pull (do not guess the layer —
   `2026-06-30-verify-the-fixed-code-path...`).

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

- **If H-B (codeload egress — leading):** add `codeload.github.com` to
  `apps/web-platform/infra/cron-egress-allowlist.txt` (+ the resolved CIDR set in
  `cron-egress-resolve.sh`) with an evidence comment, and amend **ADR-052** (two-host →
  three-host shallow-clone model). Verify firewall/egress-IP/DNS first
  (`hr-ssh-diagnosis-verify-firewall`); route via IaC (Phase 2.8), never a host edit. If
  Phase 0 instead shows a 403/auth stderr (not a firewall drop), the fix is
  `DEFAULT_CRON_TOKEN_PERMISSIONS` scope, not the allowlist.
- **If H-A (ENOSPC) — route through the EXISTING GC, do NOT add a second sweep.**
  `apps/web-platform/server/inngest/functions/cron-workspace-gc.ts` already owns
  `soleur-*` reclaim. Fix is the **GC** (Phase 0.7 names its outage as root cause)
  and/or tuning its cadence/TTL (`CRON_WORKSPACE_GC_MAX_AGE_MS`). If — and only if —
  Phase 0 proves a *synchronous* pre-clone reclaim is genuinely required, **reuse the
  GC's exported `isSweepable`** (extract a shared helper; never fork the policy), scoped
  to `soleur-${cronName}-`, with a TTL exceeding worst-case total wall-clock ×
  `retries:1`. For a hard low-disk floor, add a **separate** `assertCronWorkspaceFloor`
  fn — do **NOT** mutate `warnIfCronWorkspaceLowOnDisk` (its `_cron-shared.ts:129-133`
  docstring is a MUST-NEVER-THROW fleet-wide contract; flipping it fatal could dark the
  whole cron fleet). **Defer this build until Phase 0 reproduces ENOSPC AND shows the GC
  failed.** Also narrow H-A's orphan trigger: only a **Node/handler-process** kill
  (container swap / OOM / deploy) skips the `finally` teardown — the I3 SIGTERM→SIGKILL
  escalation kills the *claude child* and Node survives, so teardown still runs.
- **If H-C (credit, already resolved):** no code fix; Phase 1 un-mute + a Phase-0
  recovery confirmation is the close. Record that #5674's top-up resolved it.

### Phase 3 — Durable observability hardening (gated on Phase 0 confirming the catch path executes)

Close the diagnosis gap so a pre-eval fast-fail is **self-diagnosing without SSH**. Two
terminal `{ok:false}` sites in the handler currently drop the reason into the generic
`routine_runs.error_summary` fallback *"cron returned ok:false (see Sentry)"*
(`run-log.ts:64,185-189`):

1. the `setup-workspace` catch return (`cron-community-monitor.ts:356`) — thread the
   redacted clone/setup reason;
2. **`return { ok: heartbeatOk }` (`:524`)** — the output-missing / body-threw /
   ensure-audit-issue-failed paths — thread a scrubbed reason from `spawnResult.stderrTail`
   / the captured `threw` error. (Silent-failure review: Phase 3 scoped to only `:356`
   leaves these classes still-generic.)

The middleware **already reads `data.errorSummary`** (`run-log.ts:158-189`, added by
#5674) — **zero middleware change**; only the handler return widens
`{ok:boolean}` → `{ok:boolean, errorSummary?:string}` (ADR-033 I5 preserved — the
*handler* return, not `SpawnResult`). The `routine_runs` row is the durable, SSH-free fix;
the Sentry `op:`-tagged exception already delivers (the "ungroupable" framing was a
search-method artifact, not a code gap). Apply to cohort siblings only if the precedent
diff (Phase 4.4) shows the shared gap. **Gate:** only ship Phase 3's `:356` threading if
Phase 0 confirms the setup catch is the executing path (else it hardens a dormant path).

### Phase 4 — Regression test (cq-write-failing-tests-before)

No existing test exercises the `setupEphemeralWorkspace`-throw → `error`-heartbeat flow.
Add a RED-first test in `cron-community-monitor-heartbeat.test.ts`: mock
`setupEphemeralWorkspace` to throw a clone error → assert (a) exactly one `?status=error`
heartbeat, (b) on a **non-final** attempt the heartbeat step is skipped + the handler
rethrows (memoization contract), and (c) the handler return carries the **literal**
`errorSummary` field whose value the run-log middleware maps **exactly** to
`routine_runs.error_summary` (assert string equality with the scrubbed reason, not merely
"non-generic" — a typo'd field name compiles fine and silently degrades). Add a second
case for the `:524` return path (output-missing). For H-A only, add a substrate test
reusing `isSweepable` (synthesized fixtures — `cq-test-fixtures-synthesized-only`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Phase 0 verdict + branch-matched diff (checkable post-condition).** The
  PR body cites the selecting datum — `routine_runs.duration_ms` (+ `status`/`error_summary`)
  for a 06-22→06-30 row AND, if pre-eval, the `op:`-tag Sentry exception title (clone
  stderr) and `cron-workspace-gc` health — and the diff touches **only** that branch's
  files (H-B: `cron-egress-allowlist.txt`/ADR-052; H-A: `cron-workspace-gc.ts`; H-C: none).
  (Replaces the prior AC1+AC2; drops the unverifiable "no code predates verdict" clause.)
- [ ] **AC3 — regression test RED→GREEN.** The Phase 4 test fails on `main` (or a
  stubbed pre-fix tree) and passes post-fix: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor-heartbeat.test.ts test/server/inngest/cron-claude-eval-substrate.test.ts`.
- [ ] **AC4 — observability post-condition (Phase 3).** A simulated throw at **both**
  return sites (`:356` setup catch AND `:524`) yields a `routine_runs.error_summary`
  **equal** (string equality) to the scrubbed reason, not the
  `"cron returned ok:false (see Sentry)"` fallback — asserted via the run-log mapping with
  the literal `errorSummary` field name.
- [ ] **AC5 — typecheck.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] **AC6 — ADR/C4.** No C4 drift (no new external actor/system/relationship). On
  branch H-B, ADR-052 is **amended** (two-host → three-host) in this PR — not deferred.
  `c4-code-syntax.test.ts` + `c4-render.test.ts` green if any `.c4` touched (none expected).
- [ ] **AC7 — PR body uses `Ref #5732`** (not `Closes`) if any verification/close step
  is post-merge/operator-gated; otherwise `Closes #5732`.

### Post-merge (operator/automated)

- [ ] **AC8 — recovery confirmed.** After deploy, the next `cron-community-monitor`
  fire (natural 08:00 or manual-trigger) produces a real digest issue
  `[Scheduled] Community Monitor - <date>` AND a `?status=ok` Sentry check-in. Pulled
  via `routine_runs` + the Sentry checkins endpoint (no dashboard eyeball).
- [ ] **AC9 — monitor healthy.** `GET …/monitors/scheduled-community-monitor/` returns
  `status:active, isMuted:false` and a fresh `ok` check-in (Phase 1).
- [ ] **AC10 — soak follow-through enrolled by REUSING the existing probe.** AC8's
  "stays `ok` for N days" is tracked by re-pointing
  `scripts/followthroughs/community-monitor-checkin-soak-5728.sh`'s tracker directive at
  #5732 (`earliest=<deploy+Nd>`), not by building a new script (see Soak section).

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
  - mode: pre-eval clone egress drop — codeload.github.com not allowlisted (H-B, leading)
    detection: setup-ephemeral-workspace Sentry exception (query op: TAG) titled with clone stderr "Connection refused"/"Could not resolve host"; Better Stack tail; routine_runs.error_summary (after Phase 3)
    alert_route: Sentry monitor scheduled-community-monitor error
  - mode: pre-eval clone ENOSPC — orphan workspaces, GC outage (H-A)
    detection: setup-ephemeral-workspace Sentry exception titled "No space left on device" + scheduled-workspace-gc monitor unhealthy + workspace-gc-low-after-sweep freed-bytes events
    alert_route: Sentry monitor scheduled-community-monitor error + scheduled-workspace-gc monitor
  - mode: eval ran, credit/key (H-C / H10)
    detection: scheduled-anthropic-credit-probe RED (op=anthropic-credit-exhausted) + scheduled-output-missing event + duration_ms >> 300
    alert_route: Sentry monitor scheduled-anthropic-credit-probe + scheduled-community-monitor
  - mode: heartbeat POST itself fails (cross-tag blind spot)
    detection: feature:cron-sentry-heartbeat op:fetch Sentry event (NOT under feature:cron-community-monitor); monitor then sees neither ok nor error -> missed
    alert_route: Sentry monitor missed-checkin backstop (margin 60m)
logs:
  where: Better Stack (Vector-shipped app stdout/stderr tail; ADR-033 I5 discards full stdout — only the bounded SpawnResult tail + reportSilentFallback reach Sentry) ; routine_runs (Supabase, durable)
  retention: Better Stack hot ~1h ; routine_runs durable (middleware since 2026-06-16)
discoverability_test:
  command: "doppler run -p soleur -c prd -- node scripts/<routine-runs-verify>.mjs cron-community-monitor 10   # transient node+pg read per the routine_runs runbook (no SSH)  AND  doppler run -p soleur -c prd_terraform -- curl -s -H \"Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN\" https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-community-monitor/checkins/"
  expected_output: "recovered: most recent routine_runs row status=completed with multi-second duration + a [Scheduled] Community Monitor digest issue; Sentry checkin status=ok. failure (Phase 3 proof): a setup fast-fail row is status=failed with error_summary = the scrubbed clone reason (NOT 'cron returned ok:false')."
```

## Architecture Decision (ADR/C4)

**No architectural decision.** Bug fix + observability hardening inside the existing
Inngest claude-eval cron substrate (ADR-033 governs; no invariant change — Phase 3
preserves I5 by widening the *handler* return, not `SpawnResult`). **One amendment, not
a new ADR:** if Phase 0 lands H-B, adding `codeload.github.com` to the egress allowlist
**amends ADR-052** (whose two-host model omits codeload) — an extension of an existing
decision, authored in this PR per `wg-architecture-decision-is-a-plan-deliverable`.

**### C4 views — no impact.** Enumerated against all three `.c4` files
(`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`): no external
human actor, vendor edge (codeload is the same GitHub system already modeled), data
store, or access relationship is added. `### C4 views` task: none. (Deepen re-verifies
against the live `.c4`.)

## Domain Review

**Domains relevant:** Engineering (CTO) — infra/observability/cron. Support (CCO) —
the affected artifact is the community digest, but the FIX is infra, not community
strategy (advisory only).

### Engineering (CTO)
**Status:** to-confirm at deepen-plan/domain-sweep
**Assessment:** Cron substrate bug + observability hardening. Risk surfaces: (1) H-A
reclaim is **owned by the existing `cron-workspace-gc.ts`** — do not add a duplicate
sweep; if a synchronous guard is needed reuse `isSweepable` (the `cron-platform limit:1`
concurrency + the GC's >maxAge mtime gate already bound live-workspace deletion); (2)
do NOT flip the MUST-NEVER-THROW `warnIfCronWorkspaceLowOnDisk` fatal (fleet blast
radius) — use a separate fn; (3) Phase 3 preserves ADR-033 I5; (4) all egress/disk
remediation automated, never SSH.

### Product/UX Gate
**Tier:** NONE — no user-facing surface; `## Files to Edit` contains no `components/**`,
`app/**/page.tsx`, or `app/**/layout.tsx`. Skipped.

## Open Code-Review Overlap

None — to be confirmed at deepen-plan once `## Files to Edit` is finalized
(`gh issue list --label code-review --state open` grep of the touched paths:
`cron-community-monitor.ts`, `_cron-claude-eval-substrate.ts`, `_cron-shared.ts`,
`run-log.ts`, the two test files).

## Files to Edit (provisional — finalized by Phase 0 branch)

- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — Phase 3 (thread scrubbed reason into BOTH `{ok:false}` returns: `:356` + `:524`).
- `apps/web-platform/infra/cron-egress-allowlist.txt` + `apps/web-platform/infra/cron-egress-resolve.sh` — **H-B** (add `codeload.github.com`).
- `knowledge-base/engineering/architecture/decisions/ADR-052-*.md` — **H-B** (two-host → three-host amendment).
- `apps/web-platform/server/inngest/functions/cron-workspace-gc.ts` — **H-A only** (fix/tune the GC; reuse `isSweepable` if a synchronous guard is needed). Do NOT add a new sweep to `setupEphemeralWorkspace`; do NOT mutate `warnIfCronWorkspaceLowOnDisk`.
- `apps/web-platform/test/server/inngest/cron-community-monitor-heartbeat.test.ts` — Phase 4 (both return sites + non-final-attempt suppression).
- `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` — Phase 4 (H-A only, `isSweepable`).

## Soak Follow-Through Enrollment

AC8/AC9 declare a post-deploy soak ("digest + `ok` check-in hold for N days"). **Reuse the
existing probe — do NOT build a new one** (simplicity review: a new script + secrets +
sweeper wiring for an internal cron is gold-plating). `scripts/followthroughs/community-monitor-checkin-soak-5728.sh`
already soaks the `scheduled-community-monitor` check-in timeline; re-point its tracker
directive at #5732 with `earliest=<deploy+Nd>` (and `start=` strictly after this deploy)
and the `follow-through` label. Only add a new probe if Phase 0 lands H-A/H-B and the close
criterion needs a `routine_runs`-duration assertion the checkin soak can't express.

## Test Scenarios

1. `setupEphemeralWorkspace` throws a clone error → handler posts exactly one
   `?status=error` heartbeat AND the `{ok:false}` return carries the scrubbed reason; no
   second/conflicting heartbeat (memoization-safe).
2. **Non-final attempt:** body throws with no output on attempt 0 (maxAttempts 2) →
   heartbeat step skipped + handler rethrows (no interim `routine_runs` row).
3. `DeployInProgressError` from `setup-workspace` → bare rethrow, NO heartbeat (benign
   defer; unchanged — regression guard).
4. (Phase 3) run-log middleware maps the handler's `{ok:false, errorSummary}` to a
   `routine_runs.error_summary` **equal** to the scrubbed reason — for BOTH the `:356`
   setup-catch return AND the `:524` output-missing return.
5. (H-A only) `isSweepable` removes only `soleur-*` dirs older than the GC TTL, never the
   current run's `spawnCwd`.

## Risks & Sharp Edges

- **Wrong-layer fix (the headline risk).** Shipping a code fix before Phase 0 names the
  executing path repeats the 2026-06-30 Concierge-strand failure (two merged fixes the
  surface never executed). Phase 0 is a hard gate; AC1 enforces it. Acute here because the
  plan-time "no Sentry exception" was a *search artifact* (title = clone stderr, not the
  `op` tag) — Phase 0.3 MUST query by `op:` tag before concluding anything.
- **A plan whose `## User-Brand Impact` is empty/placeholder fails deepen-plan Phase
  4.6** — filled above (threshold `none` + scope-out reason).
- **H-A duplicating `cron-workspace-gc`.** Reclaim already has an owner; route through it
  (Phase 0.7 confirms whether the GC was the failing layer). Do not add a second sweep; do
  not flip `warnIfCronWorkspaceLowOnDisk` fatal (fleet blast radius).
- **Phase 3 under-scope.** Two `{ok:false}` return sites (`:356`, `:524`) — both must
  carry `errorSummary` or the output-missing/body-threw classes stay generic.
- **ADR-033 I5 drift.** Phase 3 widens the handler return, not `SpawnResult`; Phase 4.4
  precedent-diff against the cohort.
- **`Closes` vs `Ref`.** If recovery/un-mute is post-merge, use `Ref #5732` + a
  post-merge `gh issue close` after AC8 confirms (`wg-use-closes-n-in-pr-body-not-title`
  / the ops-remediation Sharp Edge).
- **Credit self-resolution.** If Phase 0 lands H-C, resist building an ENOSPC/auth fix
  for a cause that already self-resolved — the durable deliverables are Phase 1
  un-mute + Phase 3 observability + Phase 4 test, not a speculative clone fix.
- **`routine_runs` access:** `psql`/`pg` are NOT installed in this worktree and `doppler
  run`'s PATH lacks `psql`; use the runbook transient node+pg verify script
  (`ssl:{rejectUnauthorized:false}`), not a bare `psql`.
