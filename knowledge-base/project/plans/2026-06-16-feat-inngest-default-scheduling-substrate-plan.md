---
title: "feat: Make lightweight Inngest the structural default for scheduled fire-time-secret tasks"
date: 2026-06-16
type: feat
branch: feat-one-shot-inngest-default-scheduling-substrate
lane: cross-domain
brand_survival_threshold: aggregate pattern
status: draft
references:
  - "#5417 (first consumer ONLY — this PR MUST NOT close it)"
  - ADR-046, ADR-033, ADR-030
  - knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat: Make lightweight Inngest the structural default for scheduled fire-time-secret tasks

## Enhancement Summary

**Deepened on:** 2026-06-16
**Agents:** security-sentinel, architecture-strategist, framework-docs-researcher (Sentry API), verify-negative/dropped-symbol pass. Gates 4.4 (Inngest-precedent: 43 cron fns — correctly extends Inngest, not GHA), 4.6/4.7/4.8/4.9 passed.

### Key improvements folded in
1. **`close?: boolean` not `close_issue?: number`** (arch P1) — makes the close-scope invariant *structural* (a check cannot name an arbitrary issue); deletes the runtime scope-violation guard/op/test entirely.
2. **Sentry endpoint resolved** (arch P1 + Sentry-docs research, convergent) — use the slug-friendly `project=<slug>` filter; `SENTRY_PROJECT_ID` is EMPTY in config, so the numeric-id branch is dropped. No /work-time fork.
3. **Token-non-leak** (sec P1-1) — `reportSilentFallback` forwards raw `err.message` to `captureException` (`observability.ts:220`); the check must construct token-free errors; test asserts no `Bearer`/token in the reported message.
4. **`tag`→URL injection** (sec P1-2) — `new URL`+`URLSearchParams`, strict `tag` regex, reject URL-control chars.
5. **Param bounds** (sec P2-1) — `window_hours ∈ [1,168]` prevents spurious-pass-via-huge-window; `max_per_day` finite `>0`.
6. **Terse ADR added** (arch P2) — the v1→v1.1 security-boundary relaxation + substrate-default decision warrants an ADR (AP-011 skill-enforced); runbook documents *how*, ADR records *why the boundary moved*.

### Verified against codebase (verify-negative pass)
v1 handler has NO close call; registry-count stays 56 (counts functions, not registry keys); route does NOT import CHECK_REGISTRY; budget counts `description:` frontmatter only; trigger is `{ event: "reminder.scheduled" }` (per-arm, not cron); `SENTRY_AUTH_TOKEN`/`SENTRY_API_HOST` are first-consumer (no existing server REST use).

✨ **Two deliverables, one PR.** (1) Extend the existing reminder primitive's named-check registry with a reusable, parametric `sentry-issue-rate` check (apps/web-platform). (2) Add a "Step 0: Execution-substrate routing gate" to the `soleur:schedule` skill so Inngest becomes the *structural default* for scheduled fire-time-secret work instead of authors generating GHA-cron and getting blocked by the `new-scheduled-cron-prefer-inngest` hook (the hook becomes the backstop).

**This is a NEW feature. There is NO work-target issue to close.** #5417 is named ONLY as the first downstream consumer of Deliverable 1; it stays OPEN per its own AC11/AC12 post-deploy verdict. The PR body MUST use `Ref #5417`, never `Closes #5417`.

## Overview

The project's canonical scheduled-work substrates are:
- **(a) The reminder primitive** — `POST /api/internal/schedule-reminder` → `reminder.scheduled` future-dated event → `event-scheduled-reminder.ts` handler, with an allowlisted discriminated-union action (`issue-comment`, `named-check`) and a server-only `CHECK_REGISTRY`. **Registered-only, zero-deploy-to-arm, fire-time-prd-secret.** This is the substrate to extend.
- **(b) Self-armed oneshots** (ADR-046) — heavyweight: a new `oneshot-*.ts` + boot-arm + deploy per task. For bespoke logic only.
- **(c) The GHA follow-through sweeper** — `scheduled-followthrough-sweeper.yml`, periodic verification with already-allowlisted CI secrets (no fire-time prd Doppler secret).

ADR-046 + ADR-033 I7 REJECT arbitrary-task-spec / arbitrary-script executors as a credential-leak vector. **We do NOT build one.** We add ONE registered, parametric check, and a skill-level routing gate.

**Deliverable 1** adds a `sentry-issue-rate` entry to `CHECK_REGISTRY` (zero new Inngest function, registry-count test unchanged at 56). Parametric: a tag selector + `max_per_day` + `window_hours` (+ existing `report_to_issue`) + an optional `close_on_pass` boolean. At fire time it queries the Sentry issue stats API summed over the window, computes events/day, comments the evidence on `report_to_issue`, and — if `close_on_pass` and the rate passed — closes the issue. Keeping it parametric means future "did Sentry issue X drop below N/day" checks are zero-new-code, zero-deploy-to-arm.

**Deliverable 2** adds a Step 0 substrate-routing gate to `plugins/soleur/skills/schedule/SKILL.md` that classifies a requested scheduled task BEFORE mode detection and routes it: fire-time prd secrets / autonomous server-side logic → Inngest reminder primitive (named-check, with `sentry-issue-rate` as the worked example) or a oneshot; periodic verification with a sweeper-allowlisted secret → follow-through sweeper; pure-GH ops → GHA-cron. The preamble is updated so the gate is the *primary* route and the hook is the backstop. Optionally tighten the hook override to require asserting "no prd secrets / pure-GH op".

**Doc:** amend `inngest-oneshot-and-reminder-patterns.md` (the runbook already documents the named-check registry — §A) to (i) document `sentry-issue-rate` as the canonical parametric check and (ii) add a "Step 0 routing" section mirroring the skill gate. A separate ADR is unnecessary — the runbook is the cited home and ADR-046/033 already cover the substrate constitution.

## Premise Validation (Phase 0.6)

All cited premises were verified against the worktree / `origin/main`:

- **#5417 is OPEN** (`gh issue view 5417` → `state: OPEN`, title `fix(infra): soleur-web-platform container restarts ~10-60x/day…`). The plan must NOT close it. ✅ Held.
- **All cited file paths EXIST** on `origin/main`: `schedule-reminder/route.ts`, `event-scheduled-reminder.ts`, `lib/inngest/scheduled-reminder-action.ts`, `plugins/soleur/skills/schedule/SKILL.md`, the runbook. ✅ Held.
- **The hook exists** at `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` (+ `.test.sh`). ✅ Held.
- **ADR corpus**: ADR-046 (oneshot self-arm + registered-only), ADR-033 (runtime invariants + arbitrary-executor rejection), ADR-030 (Inngest durable trigger) all present and consistent with extending the registry rather than building an executor. The mechanism (extend registered check) is NOT in any ADR's rejected-alternatives table. ✅ Held.
- **STALE PREMISE CORRECTED — `close_on_pass` is NOT free.** The argument implies the close path "already exists in the reminder handler." It does NOT: the v1 handler is **comment-only**, and the handler header (`event-scheduled-reminder.ts:56`) explicitly states *"v1 entries MUST be read-only or comment-only (no issue close/edit/label mutation)."* The `CheckFn` signature returns only `{ verdict, body }` — there is no close channel. `close_on_pass` therefore requires a **deliberate handler capability extension** (see Research Reconciliation). This is the single biggest shape difference from the argument's framing.
- **STALE PREMISE CORRECTED — Sentry endpoint.** The argument's `?stat=24h` issue-stats endpoint requires an **issue id**, but the check is parametric by **tag** (`event_type=server-startup`). A **two-step** Sentry call is required: resolve tag → issue id, then fetch stats. See Research Reconciliation.

## Research Reconciliation — Spec vs. Codebase

| Spec/argument claim | Codebase reality (file:line) | Plan response |
|---|---|---|
| "close it via the existing installation-token path the reminder handler already uses for comment/close" | Handler is **comment-only**; `event-scheduled-reminder.ts:56` forbids close/edit/label in v1. `CheckFn` returns `{verdict, body}` only (`:46`). No close call exists. | Widen `CheckResult` with optional `close?: boolean` (deepen: arch P1 — boolean, not a number, so the close target is structurally `action.report_to_issue` and cannot be an arbitrary issue). The registry check RETURNS the close intent (stays pure-data); the HANDLER performs the `PATCH .../issues/{report_to_issue}` close after the comment POST (`:190`), inside the same `step.run`. Octokit mutations stay handler-owned. Document the v1→v1.1 evolution in the handler header. |
| "GET /api/0/organizations/{org}/issues/{id}/stats/?stat=24h" — given an id | The check is parametric by **tag**, not id. We do not know the id at arm time. | Two-step: (1) resolve `tag` → newest matching issue id via the org/project issues endpoint with the tag query + window; (2) `GET /api/0/organizations/{org}/issues/{id}/stats/?stat=24h`, sum the 24h buckets over `window_hours`, divide by `window_hours/24`. Fail-closed (verdict `info`, no close) if zero or >1 issues match the tag. |
| "reuse however the codebase reads Sentry creds server-side (SENTRY_IAC_AUTH_TOKEN / SENTRY_API_TOKEN / SENTRY_AUTH_TOKEN)" | Server code (`_cron-shared.ts:195`) only reads `SENTRY_PROJECT_ID` (numeric, for cron-heartbeat DSN). The REST **API token** `SENTRY_AUTH_TOKEN`, `SENTRY_ORG=jikigai-eu`, `SENTRY_PROJECT=web-platform`, `SENTRY_API_HOST=jikigai-eu.sentry.io` live in `.env.example:76-89` and are **not yet consumed** by any server code. The sweeper uses `SENTRY_IAC_AUTH_TOKEN`. | This check is the **first server-side REST consumer** of `SENTRY_AUTH_TOKEN`. Use `SENTRY_AUTH_TOKEN` for the `Authorization: Bearer` header, `SENTRY_ORG`/`SENTRY_PROJECT` for slugs. **MUST build the base URL from `SENTRY_API_HOST` (`https://jikigai-eu.sentry.io`), NOT `eu.sentry.io`** — the latter rewrites `-eu`-suffixed slugs to the literal `eu` org (learning `2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`). Fail-closed `info` verdict if any of the four env vars is missing. |
| "function-registry-count test — confirm if it needs a bump" | `test/server/inngest/function-registry-count.test.ts:135` asserts `routeEntries.length === 56`. Counts Inngest **functions**, NOT `CHECK_REGISTRY` entries. | **No bump.** A new registry entry is not a new Inngest function. Count stays 56. The runbook's "easy to forget" bump (§B.4) applies only to oneshots, not registry entries. |
| "soleur:schedule skill description budget (1800 cap)" | `plugins/soleur/test/components.test.ts:15` — budget is **2250** (not 1800), and the codebase is **at 2250/2250 (zero headroom)**. Budget sums the `description:` frontmatter field ONLY (`:152`), not SKILL.md body. schedule's `description:` is 33 words. | **Step 0 edits the SKILL.md BODY, not the `description:` frontmatter.** Body edits cost ZERO description-budget. The plan MUST NOT touch the `description:` field of `schedule` or any sibling. If the work phase finds a description edit unavoidable, STOP — a sibling-trim is required (the budget is at cap). Re-run the one-liner at Step 2. |
| "the check can close issues + reads Sentry — high cardinality?" | `reportSilentFallback` does NOT debounce (learning `2026-05-13-mirror-with-debounce…`). | This reminder fires **once per arm** (not a recurring cron), so cardinality is bounded by arm count, not QPS. `reportSilentFallback` is acceptable here. No `mirrorWithDebounce` needed. Note this explicitly so review does not re-flag. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing directly. The blast radius is the shared scheduling substrate: a broken `sentry-issue-rate` check could (a) wrongly close a GitHub issue that was NOT actually resolved (false `close_on_pass`), or (b) comment a misleading rate on an issue. Neither is a user data path — these are operator/maintainer-facing GitHub issues. A broken Step 0 gate would mis-route a future scheduled task author to the wrong substrate (caught by the existing hook backstop).

**If this leaks, the user's data is exposed via:** N/A — the check reads **aggregate Sentry issue event counts** (a number per 24h bucket), not user PII, not user-session data. The only secret it touches is `SENTRY_AUTH_TOKEN`, minted/read server-side inside `step.run`, never returned into persisted step state. The installation token close path is the same trust boundary the operator already holds.

**Brand-survival threshold:** aggregate pattern (shared scheduling infra, not a single user's data path). No per-PR CPO sign-off required. `security-sentinel` MUST run at review time (the check can close issues + reads Sentry) per the explicit constraint.

## Implementation Phases

### Phase 1 — Widen the action + check-result contract (lib/, RED tests first)

**File: `apps/web-platform/lib/inngest/scheduled-reminder-action.ts`**
- The `named-check` action variant ALREADY carries `params?: Record<string, unknown>` + `report_to_issue`. The `sentry-issue-rate` parameters (`tag`, `max_per_day`, `window_hours`, `close_on_pass`) ride inside the **untyped `params`** — the check validates them at fire time. **No discriminated-union widening of `ReminderAction` is required** (the union stays `issue-comment | named-check`). This sidesteps the `cq-union-widening` exhaustiveness sweep. State this explicitly so review does not expect a union change.
- ⚠️ Do NOT add a typed `sentry-issue-rate` variant — that would force every `switch (raw.type)` consumer to widen and is unnecessary; the registry key + `params` IS the parametric surface.

**File: `apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts`**
- Widen `CheckResult` (`:46`) from `{ verdict; body }` to `{ verdict; body; close?: boolean }`. **[deepen: arch P1]** Use a **boolean intent**, NOT `close_issue?: number`. The handler already knows the only legitimate close target — `action.report_to_issue`. A boolean makes the scope invariant **structural**: a check literally cannot name an arbitrary issue, so the runtime `close_issue === report_to_issue` scope-assert (and its `named-check-close-scope-violation` op + test) is **deleted** — the violation becomes unrepresentable rather than detected. "Check returns data, handler mutates" is preserved.
- `tsc --noEmit` after the widening — every TS2322 against `CheckResult` is a rail to update (only the seeded `open-silence-issue-count` demonstrator + the new check return `CheckResult`).

### Phase 2 — The `sentry-issue-rate` registered check

**File: `apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts` — add to `CHECK_REGISTRY` (after `:73`)**

A new entry `"sentry-issue-rate": async (octokit, params) => { … }` that:
1. **Validates params at fire time** (defensive — `params` is untyped). Required: `tag` (string `key:value`, strict regex — see below), `max_per_day` (finite number `> 0`), `window_hours` (integer in **`[1, 168]`** — 1h to 7d). Optional: `close_on_pass` (boolean, default false). On any invalid/missing/out-of-bounds param → return `{ verdict: "info", body: "<param error>" }` (no close). On missing Sentry env (`SENTRY_AUTH_TOKEN`/`SENTRY_ORG`/`SENTRY_PROJECT`/`SENTRY_API_HOST`) → `info` + misconfig body (and `reportSilentFallback` op `sentry-issue-rate-misconfig`).
   - **[deepen: sec P2-1]** `window_hours` upper-bound `168` is load-bearing: an unbounded window makes `events_per_day` trivially tiny → spurious `pass` → spurious close. `max_per_day` finite + `>0`. `tag` length-capped (e.g. ≤200 chars).
   - **[deepen: sec P1-2]** `tag` regex: `^[A-Za-z0-9_.-]+:[A-Za-z0-9_.\-/]+$` (a single `key:value` term). Reject any `tag` containing `&`, `?`, `#`, whitespace, or `..` → `info`, no fetch. Sentry uses `key:value` (colon), NOT `key=value`.
2. **Resolves tag → issue id** via the **slug-friendly** endpoint **[deepen: arch P1 + Sentry-docs research convergent]**: `GET https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/issues/?query=<tag>&project=${SENTRY_PROJECT}&statsPeriod=<window>`. The org-issues `project=` filter accepts the project **slug** (`web-platform`) per Sentry docs — so use `SENTRY_PROJECT` (populated), **NOT** `SENTRY_PROJECT_ID` (empty in `.env.example:94` — do NOT depend on it). **[deepen: sec P1-2]** Build the URL with `new URL(path, base)` + `URLSearchParams` / `encodeURIComponent` — NEVER string concatenation. Build base from `SENTRY_API_HOST` (jikigai-eu.sentry.io), never `eu.sentry.io` (slug-rewrite trap). Bounded `fetch` with `AbortController` timeout (e.g. 10s). Fail-closed (`info`, no close) if 0 or >1 issues match.
   - Sentry query field does NOT support boolean OR/AND (learning `sentry-api-boolean-search-not-supported` + confirmed by docs research — AND/OR only in Discover/Dashboards/Monitors). Single `key:value` term only.
3. **Fetches stats** and sums events over `window_hours` → `events_per_day = total / (window_hours / 24)`. **[deepen: Sentry-docs research]** The issue-detail `stats` object schema is **undocumented/ambiguous**; the **deterministic, documented** path is the project-stats endpoint `GET /api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/stats/?stat=received&since=<unix>&until=<unix>&resolution=1d` which returns `[timestamp, count]` tuples — sum the counts. **/work Phase 2 MUST live-probe both** (issue-id stats vs project stats) against `jikigai-eu.sentry.io` and pick the one returning a sum-able shape; prefer project-stats `resolution=1d` if the issue-stats schema is opaque. Document the chosen endpoint inline. (Note: project-stats is project-wide, not issue-scoped — if issue-scoping is required, the issue-detail `?statsPeriod=` `stats` object is the only issue-scoped option and its schema must be probed.)
4. **Verdict**: `events_per_day <= max_per_day` → `verdict: "pass"`, body = evidence (issue id, total events, window, per-day rate, threshold). Set `close: true` in the return **iff** `close_on_pass === true`. Else `verdict: "fail"`, body = finding, `close` absent/false.
5. Returns `CheckResult` with `body` (evidence) + optional `close: boolean`. The check performs NO octokit mutation — returns data; the handler comments + closes.
   - **[deepen: sec P1-1]** The check MUST NOT forward a raw Sentry-`fetch` error/response-body to `reportSilentFallback` — construct a **token-free** error (e.g. `new Error("sentry-issue-rate fetch failed: <status|AbortError>")`). The `Authorization: Bearer …` header value must never appear in any `body`, `extra`, log line, or thrown message (`reportSilentFallback` forwards raw `err.message` to `Sentry.captureException` — `observability.ts:220` — so an unscrubbed message leaks the token into Sentry itself).

**Handler close wiring (in the `run-check` `step.run`, after the comment POST `:190`):**
- After posting the comment, if `result.close === true`, call `octokit.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", { owner: REPO_OWNER, repo: REPO_NAME, issue_number: action.report_to_issue, state: "closed", state_reason: "completed" })`. **[deepen: sec P2-2]** The PATCH target is `action.report_to_issue` (the operator-authenticated arm value) — NOT a check-returned number. Wrap in try/catch → `reportSilentFallback` op `named-check-close-failed` on failure (comment already posted; close is best-effort, idempotent — closing an already-closed issue is a no-op 200).
- Update the handler header comment: v1 was comment-only; v1.1 permits a **registry-check-directed close of its own `report_to_issue` ONLY** (the check returns `close:true` deliberately; the registry is code-reviewed). **[deepen: sec P2-3]** State the testable invariant in the header AND runbook: *"A registry check may direct exactly ONE mutation: closing its own `report_to_issue`. No check may edit, label, or close any other issue. New mutation channels require an ADR."* This is NOT an arbitrary-mutation surface — only a code-reviewed registry entry can request a close, and the boolean shape makes the scope structural (a check cannot name another issue).

### Phase 3 — Tests (mirror existing reminder/named-check tests)

**File: `apps/web-platform/test/server/inngest/event-scheduled-reminder.test.ts`** (extend). Mock `fetch` (Sentry) + octokit.
- `sentry-issue-rate` pass + `close_on_pass:true` → comment posted, PATCH-close called on `action.report_to_issue`, return `ok:true reason: named-check-pass`.
- pass + `close_on_pass` absent/false → comment posted, NO PATCH-close.
- fail (rate > threshold) → comment posted, NO close, `reportSilentFallback` op `named-check-failed` fired.
- Sentry returns 0 matching issues / >1 → `info`, no close, no throw.
- Missing `SENTRY_AUTH_TOKEN` (or other env) → `info` misconfig body, no close, `sentry-issue-rate-misconfig` reported.
- Invalid params (missing `tag` / non-numeric `max_per_day` / `window_hours` > 168) → `info`, no close. **[deepen]** out-of-bounds `window_hours` is its own case.
- **[deepen: sec P1-2]** `tag` containing `&` / `#` / whitespace / `=` → `info`, NO fetch issued (or fetch to the encoded-safe URL only). Assert URL built via `new URL`+`URLSearchParams` (no raw concatenation).
- **[deepen: sec P1-1]** Sentry-fetch-failure path: assert the reported error message contains neither the token value nor the substring `Bearer` (token-non-leak).
- Sentry base URL host is `jikigai-eu.sentry.io`, NOT `eu.sentry.io` — assert the fetched URL host; `project=` filter uses the slug `web-platform`, not an id.
- **[deepen: arch P1]** No `named-check-close-scope-violation` test — the boolean shape makes that case unrepresentable (deleted by design).
- Verify the seeded `open-silence-issue-count` test still passes (CheckResult widening is additive/optional).

**File: `apps/web-platform/test/server/internal/schedule-reminder-route.test.ts`** — add ONE case: a `named-check` with `check:"sentry-issue-rate"` + `params` → 202 (route accepts; registry membership is a fire-time concern; the route does NOT import the registry). Confirms the arm POST shape for AC12.

**File: `apps/web-platform/test/server/inngest/function-registry-count.test.ts`** — **unchanged** (count stays 56). Note in the PR body that this was confirmed, not forgotten.

### Phase 4 — Step 0 routing gate in the schedule skill (BODY only)

**File: `plugins/soleur/skills/schedule/SKILL.md`**
- Insert a **"## Step 0: Execution-substrate routing gate"** BEFORE the current Step 0a mode-detection block (~`:46`). Classify the requested task and route:
  - **(a) Needs fire-time prd secrets** (grep the task description for `doppler`, `SUPABASE_SERVICE_ROLE_KEY`, `SENTRY_*_TOKEN`, server-side env) **OR autonomous server-side logic** → route to the **Inngest reminder primitive** (named-check for verification shapes — point at `sentry-issue-rate` as the worked example) or a **oneshot** (bespoke). **STOP — do not generate GHA.** Cite `knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md`.
  - **(b) Periodic verification needing an already-sweeper-allowlisted secret** → the **follow-through sweeper** (`scheduled-followthrough-sweeper.yml`). Cite `followthrough-convention.md`.
  - **(c) Pure-GH ops (no prd secrets)** → **GHA-cron** (continue to Step 0a mode detection).
- Update the preamble (`:35-38`, already mentions Inngest/oneshot/reminder) so the gate is the **primary** route and the hook is the named backstop. Add the follow-through sweeper to the preamble (currently absent).
- ⚠️ **Do NOT edit the `description:` frontmatter** (budget at 2250/2250). Body-only edit = zero budget cost. Re-run `bun test plugins/soleur/test/components.test.ts` to confirm green.

### Phase 5 — (Optional) tighten the hook override

**File: `.claude/hooks/new-scheduled-cron-prefer-inngest.sh`** + `.test.sh`
- Current override: literal `<!-- gate-override: new-scheduled-cron-prefer-inngest -->`. Tighten to require the override comment to ALSO assert the rationale, e.g. `<!-- gate-override: new-scheduled-cron-prefer-inngest reason: no-prd-secrets-pure-gh-op -->` (the hook greps for the `reason:` clause).
- Update `.test.sh` case (c) to use the tightened marker, and add a case (c2): old bare marker WITHOUT the reason clause → still `deny` (forces the author to assert pure-GH). Keep the fail-open / exit-0-always invariants (cases i/j/k) intact.
- This phase is **optional / lower priority** — if it risks the hook's test budget or scope creep, scope it out with a tracking issue rather than rush it. The Step 0 gate (Phase 4) is the load-bearing deliverable; the hook is the backstop.

### Phase 6 — Documentation

**File: `knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md`** (amend)
- §A: document `sentry-issue-rate` as the canonical **parametric** check (params: `tag`, `max_per_day`, `window_hours`, `close_on_pass`), the two-step Sentry resolution (slug-friendly endpoint, `SENTRY_API_HOST` host trap), and the v1.1 registry-directed-close capability + invariant ("exactly one self-scoped close mutation; new channels require an ADR").
- Add a **"## Step 0: which substrate?"** section mirroring the skill gate (the runbook is the cited source-of-truth for the skill).

**File: new ADR via `/soleur:architecture create` (terse shape)** **[deepen: arch P2 — AP-011 skill-enforced]**
- The v1→v1.1 relaxation of an allowlisted-action security boundary (comment-only → registry-directed close) AND the "reminder-primitive named-check is the structural-default lightweight scheduling substrate + soleur:schedule routing gate" decision warrant a **terse ADR** (Context / Decision / Consequences). AP-011 is skill-enforced and this moves a security boundary; the rich-shape rubric's "teeth-bearing rejected alternatives" trigger is hit (arbitrary-executor per ADR-046/033, typed-union variant, GHA-cron). The runbook amendment documents the *how*; the ADR records *why the boundary moved*. Cite ADR-046/033 as precedent, not duplication.

## Acceptance Criteria

### Pre-merge (PR)
- [x] `CHECK_REGISTRY` has a `sentry-issue-rate` entry; `CheckResult` widened with optional `close?: boolean` (NOT `close_issue?: number`); `ReminderAction` union UNCHANGED (still `issue-comment | named-check`).
- [x] Handler closes `action.report_to_issue` via `PATCH …/issues/{n}` (state=closed, state_reason=completed) IFF `result.close === true`; PATCH target is `action.report_to_issue`, never a check-returned number. No scope-violation guard exists (boolean shape makes it unrepresentable).
- [x] Sentry base URL built via `new URL`+`URLSearchParams` from `SENTRY_API_HOST` (test asserts host `jikigai-eu.sentry.io`, NOT `eu.sentry.io`); `project=` filter uses slug `SENTRY_PROJECT` (NOT empty `SENTRY_PROJECT_ID`); auth via `SENTRY_AUTH_TOKEN`; fetch timeout-bounded.
- [x] `tag` strict-regex validated (`^[A-Za-z0-9_.-]+:[A-Za-z0-9_.\-/]+$`); rejects `&`/`?`/`#`/whitespace/`..` → `info`. `window_hours ∈ [1,168]`; `max_per_day` finite `>0`.
- [x] Token-non-leak: the Sentry-fetch-failure report message contains neither the token value nor `Bearer` (test-asserted); the check constructs a token-free error.
- [x] Fail-closed (`info`, no close) on: missing Sentry env, invalid/out-of-bounds params, 0 or >1 matching issues.
- [x] /work Phase 2 live-probed the Sentry stats endpoint and documented which (issue-stats vs project-stats `resolution=1d`) returns a sum-able shape.
- [x] `function-registry-count.test.ts` asserts `=== 56` UNCHANGED (confirmed, not bumped).
- [x] All new tests pass: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/event-scheduled-reminder.test.ts test/server/internal/schedule-reminder-route.test.ts` (confirm runner against `apps/web-platform/package.json scripts.test` + `vitest.config.ts` include globs at /work Phase 0).
- [x] Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] `plugins/soleur/skills/schedule/SKILL.md` has a "Step 0: Execution-substrate routing gate" BEFORE Step 0a; preamble references the gate as primary + hook as backstop + sweeper; `description:` frontmatter UNCHANGED.
- [x] `bun test plugins/soleur/test/components.test.ts` green (skill-description budget still 2250/2250; no description edit).
- [ ] (If Phase 5 done) hook + `.test.sh` updated; bare-marker-without-reason → `deny`; fail-open/exit-0 invariants intact. Else: scoped out with a tracking issue.
- [x] Runbook amended with `sentry-issue-rate` + Step 0 routing + close-mutation invariant; terse ADR created (v1→v1.1 boundary + substrate-default).
- [x] PR body uses `Ref #5417` (NOT `Closes #5417`); #5417 stays OPEN.
- [ ] `security-sentinel` ran at review (close-capability + Sentry-read surface).

### Post-merge (operator — zero-deploy follow-up, NOT this PR)
- [ ] Once Deliverable 1 is deployed, AC12 for #5417 is armed with a single zero-deploy POST to `/api/internal/schedule-reminder`: `named-check` `check:"sentry-issue-rate"`, `params: { tag:"event_type=server-startup", max_per_day:1, window_hours:72, close_on_pass:true }`, `report_to_issue:5417`, `fire_at:"2026-06-19T..."`. **The operator runs the arm POST after deploy.** `Automation: not feasible from CI` — the arm requires the prd `INNGEST_MANUAL_TRIGGER_SECRET` (operator-held) and must fire against the deployed prd endpoint; document the exact curl in the PR body. This is a deliberate post-deploy verification step (not infrastructure provisioning — see `## Infrastructure (IaC)`).

## Observability

```yaml
liveness_signal:
  what: "event-scheduled-reminder is a oneshot-class Inngest function (fires per-arm, not recurring) — per ADR-033 it gets NO Sentry cron monitor (would false-alert on missed check-ins). Liveness of a sentry-issue-rate arm is the comment it posts to report_to_issue at fire time."
  cadence: "per-arm (one-time future-dated)"
  alert_target: "Sentry (reportSilentFallback ops below) — no cron monitor by design"
  configured_in: "apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts (handler); no terraform cron-monitor resource (oneshot-class)"
error_reporting:
  destination: "Sentry via reportSilentFallback(err, { feature: 'event-scheduled-reminder', op, message, extra })"
  fail_loud: "yes — every failure path reports; no silent catch"
failure_modes:
  - { mode: "Sentry env missing/misconfigured", detection: "param/env validation in check", alert_route: "reportSilentFallback op=sentry-issue-rate-misconfig" }
  - { mode: "Sentry API call fails/timeouts", detection: "fetch try/catch in check throws", alert_route: "handler catch reportSilentFallback op=named-check-threw" }
  - { mode: "0 or more-than-1 issues match tag", detection: "issue-resolution count guard", alert_route: "verdict=info body on report_to_issue; op=sentry-issue-rate-ambiguous-match (warn)" }
  - { mode: "rate over threshold (verdict=fail)", detection: "events_per_day > max_per_day", alert_route: "reportSilentFallback op=named-check-failed (error level)" }
  - { mode: "issue close PATCH fails", detection: "octokit PATCH try/catch", alert_route: "reportSilentFallback op=named-check-close-failed" }
logs:
  where: "Sentry (jikigai-eu) + pino stdout in the web-platform container (reportSilentFallback mirrors both)"
  retention: "Sentry project default"
discoverability_test:
  command: curl -sS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/api/inngest
  expected_output: "401"
  note: "401 = the Inngest serve endpoint requires a signed request; a bare GET proves the function-serving substrate (where event-scheduled-reminder + the sentry-issue-rate check are registered) is LIVE and reachable with NO remote-shell access. The per-arm operational liveness signal remains the evidence comment posted to report_to_issue at fire time (gh issue view <report_to_issue> --comments) plus the reportSilentFallback Sentry ops above for any failure path."
```

## Domain Review

**Domains relevant:** Engineering (infra/observability). Product = NONE (no UI surface — `Files to Create/Edit` contain no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`).

### Engineering
**Status:** carried-forward (CTO assessment embedded in Research Reconciliation + Observability).
**Assessment:** Shared scheduling-substrate change. Key risks surfaced and mitigated: (1) close-capability is NEW (v1 was comment-only) — scoped to registry-check-directed, report_to_issue-only close; (2) first server-side `SENTRY_AUTH_TOKEN` consumer — must use `SENTRY_API_HOST` host; (3) registry-count test confirmed unchanged; (4) fires per-arm (no debounce concern). No new Inngest function, no new cron monitor, no migration.

### Product/UX Gate
NONE — no user-facing surface. Skipped.

## Infrastructure (IaC)

**No new infrastructure.** No new server, systemd unit, secret, vendor, DNS record, or persistent runtime process. The `SENTRY_AUTH_TOKEN`/`SENTRY_ORG`/`SENTRY_PROJECT`/`SENTRY_API_HOST` env vars already exist in `.env.example` and (per operator) in prd Doppler — this PR is the first server-side *reader*, not a provisioner. No `terraform-architect` invocation required.

The single post-merge operator step (the AC12 arm POST) is NOT infrastructure provisioning: it is a zero-deploy verification request to an already-deployed endpoint, explicitly out of scope of this PR per the feature brief, gated by the operator-held `INNGEST_MANUAL_TRIGGER_SECRET`. It is the documented dogfood of the very primitive this PR ships. `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` (top of file) records that Phase 2.8 was reviewed and this step is genuinely operator-only.

If the work phase discovers `SENTRY_AUTH_TOKEN` is absent from prd Doppler, that is a read-only `doppler secrets get` verification surfaced as a precondition for the AC12 arm — NOT a provisioning step in this PR.

## Test Scenarios

Covered by Phase 3. Highest-value: pass+close, fail-no-close, ambiguous-tag fail-closed, env-missing fail-closed, `tag`-injection rejected, token-non-leak, out-of-bounds `window_hours`, `SENTRY_API_HOST` host assertion, registry-count unchanged.

## Risks & Mitigations

- **Wrongly closing an unresolved issue** (false `close_on_pass`). Mitigation: close is best-effort + scoped to `report_to_issue`; the evidence comment is always posted first (operator can re-open); rate computed over a window (not a single day) to avoid a transient quiet hour passing.
- **Sentry EU host slug-rewrite** → wrong org → empty results → wrong "passed". Mitigation: build URL from `SENTRY_API_HOST`; test asserts the host. (learning 2026-05-17)
- **Param-shape drift** (untyped `params`). Mitigation: fire-time validation in the check, fail-closed `info`.
- **Skill-description budget at cap** → accidental `description:` edit breaks `bun test`. Mitigation: Step 0 is a BODY edit; AC asserts `description:` unchanged.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder-only will fail `deepen-plan` Phase 4.6 — this one is filled (threshold: aggregate pattern).
- `close_on_pass` is NOT a free reuse of an existing close path — it is a deliberate v1→v1.1 handler capability. Do not let /work treat it as "already there." The capability is expressed as a `close?: boolean` on `CheckResult` (handler closes `action.report_to_issue` iff true); do NOT reintroduce a `close_issue?: number` shape.
- The `ReminderAction` union does NOT widen — params ride inside the existing `named-check`'s untyped `params`. Do not add a typed `sentry-issue-rate` variant.
- **Sentry `project=` filter takes the SLUG, not an id** (resolved at deepen-plan via Sentry-docs research + architecture review): use `SENTRY_PROJECT=web-platform`, NOT `SENTRY_PROJECT_ID` (empty in `.env.example:94` — depending on it would silently 0-match → permanently broken check). The org-issues endpoint `?project=<slug>` accepts the slug.
- **Sentry issue-stats response schema is undocumented** — /work Phase 2 MUST live-probe (issue-detail `?statsPeriod=` `stats` object vs project-stats `?resolution=1d` `[ts,count]` tuples) before wiring the sum. Prefer the documented project-stats tuple shape if the issue-stats object is opaque; note the issue-scoping trade-off (project-stats is project-wide).
- **AP-007 check on the post-merge arm:** before accepting "arm POST not feasible from CI," confirm the `soleur:trigger-cron` Doppler-read path cannot cover the `INNGEST_MANUAL_TRIGGER_SECRET` arm (it reads a secret read-only from Doppler). If it can, automate per AP-007. Current read: the arm targets the prd `/api/internal/schedule-reminder` endpoint (not a cron trigger), so trigger-cron does not cover it — but verify at /work.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returned no matches against the files this plan edits (event-scheduled-reminder.ts, scheduled-reminder-action.ts, schedule/SKILL.md, the hook, the runbook). Recorded so the next planner sees the check ran.
