---
title: "feat(ops): trigger-cron optional event data pass-through + discoverability"
date: 2026-06-01
branch: feat-one-shot-4742-trigger-cron-data-discoverability
issue: 4742
closes: 4742
refs: [4734, 4735]
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat(ops): trigger-cron optional event `data` pass-through + discoverability

Closes #4742. Implements both deferred follow-ups from the review of PR #4735 (Ref #4734).

## Enhancement Summary

**Deepened on:** 2026-06-01
**Sections enhanced:** Security Analysis, Acceptance Criteria (AC-A3), Risks (precedent-diff)
**Gates run inline (Task-agent fan-out unavailable in this env; ran the hard gates + realism passes directly):** 4.4 precedent-diff, 4.45 verify-the-negative + post-edit self-audit, 4.6 User-Brand Impact (PASS), 4.7 Observability (PASS — all 5 fields, no ssh in discoverability_test), 4.8 PAT-shaped variable (PASS — none).

### Key Improvements
1. **AC-A3 back-compat nuance:** the existing dispatch test (`trigger-cron-route.test.ts:132`) uses `toMatchObject` (permissive) — adding a `data` spread would NOT fail it. AC-A3 must add an explicit "no extra `data` keys when `data` is absent" assertion so back-compat is actually gated, not assumed. (verify-the-negative pass)
2. **Precedent-diff confirmed:** the route's auth primitive mirrors `kb-drift-ingest/route.ts`, but kb-drift uses **HMAC** (`createHmac`, L27/L70) while trigger-cron is a Bearer shared-secret compare — the route's own header comment already states this correctly. The `data`-merge widening is NOVEL (no in-repo precedent); Security Analysis stands in for the precedent diff.
3. **Verify-the-negative all-confirm:** route does NOT reference `issue_number` (dumb-forwarder claim holds); current envelope literal at `route.ts:100` confirms the merge target; route is in `PUBLIC_PATHS` (`routes.ts:31`).

### New Considerations Discovered
- No new scheduled job → 4.4 scheduled-work / ADR-033 Inngest-vs-GHA check is N/A.
- The skill-description budget is the single sharpest implementation hazard (1950/1950, zero headroom) — re-flagged in Risks and AC-C2.

## Overview

Two independent sub-features, one PR:

- **(A) Optional event `data` pass-through** — `POST /api/internal/trigger-cron`
  (`apps/web-platform/app/api/internal/trigger-cron/route.ts`) currently hardcodes
  the dispatched Inngest payload to `{ trigger: "manual-api", at }` and exposes no
  way to pass per-cron `event.data`. `cron-bug-fixer` reads `event.data.issue_number`
  (`cron-bug-fixer.ts:594`, positive-integer-validated) to target a specific issue,
  so the route cannot reproduce the runbook's targeted-trigger capability. Accept an
  optional `data` object in the body, merge under route-controlled keys
  (`{ trigger, at, ...body.data }`, **route keys win**), forward via `inngest.send`.
  Add tests asserting `issue_number` passes through AND that `trigger`/`at` cannot be
  overridden by `body.data`.

- **(B) Discoverability + runbook follow-through** — update
  `knowledge-base/engineering/operations/runbooks/inngest-server.md` (2 `inngest send` sites)
  and `oauth-probe-failure.md` (4 sites) to document `POST /api/internal/trigger-cron`
  as the PRIMARY path and demote the SSH `inngest send` loopback examples to a
  Last-resort section. Keep the `issue_number` example annotated (now unblocked by A).
  Add a thin **skill** (`plugins/soleur/skills/trigger-cron/`) wrapping the POST: reads
  `INNGEST_MANUAL_TRIGGER_SECRET` from Doppler (read-only), lists allowlisted events from
  `MANUAL_TRIGGER_EVENTS`, fires the `curl`. This resolves the
  `hr-no-ssh-fallback-in-runbooks` contradiction (#4116 class).

### Why a skill, not an MCP tool

The issue offers "a thin MCP tool **or** skill." There is no in-repo MCP-tool
framework under `plugins/` — MCP tools in this repo are external servers
(`mcp__plugin_*`). The established pattern for an operator/agent action that reads a
Doppler secret and curls an internal route is a **skill + script**: precedents are
`admin-ip-refresh` (Doppler read + corrective mutation), `flag-create`/`flag-set-role`
(Doppler read + API curl), `user-set-role` (Bearer-curl). The `kb-drift-ingest` route
(`infra/kb-drift.tf:81`) is the exact internal-route-Bearer precedent. A skill is also
directly discoverable by the `/soleur:*` surface and by agents, satisfying "surface the
route to agents."

## Research Reconciliation — Spec vs. Codebase

All premises in #4742 verified against `origin/main`/worktree at plan time; the issue
body is accurate. The one material divergence the issue body did NOT mention:

| Claim / assumption | Reality (verified) | Plan response |
| --- | --- | --- |
| Route is reachable; only `data` + docs are missing (A/B) | Route already in `PUBLIC_PATHS` (`lib/routes.ts:31`, added by #4735 after `user-impact-reviewer` caught the trap — see learning `2026-06-01-new-internal-api-route-needs-public-paths-registration.md`) | No `routes.ts` edit needed — A is a pure body-merge change to an already-reachable route. Confirmed, not assumed. |
| Issue cites "thin MCP tool or skill" | No in-repo MCP-tool framework; skill+script is the codebase convention | Build a skill (`plugins/soleur/skills/trigger-cron/`). |
| New skill adds a `description:` | Cumulative skill-description budget is at **1950/1950 words — ZERO headroom** (cap bumped twice: #2725 +50, #4341 +100; test `components.test.ts:15`, runs under `bun test`) | The skill's description MUST be offset: bump `SKILL_DESCRIPTION_WORD_BUDGET` by the new word count OR trim sibling descriptions by ≥ the new count. See Files to Edit. |
| `data` merge is purely a convenience feature | The route was security-signed off **only** in its no-data form ("no replay-sensitive payload" — route header comment L13-15). Forwarding arbitrary `data` to mutating/paid crons (`bug-fixer` opens PRs) at `single-user incident` threshold is a NEW abuse surface. | REQUIRED security-sentinel gate at deepen-plan + review (see Security Analysis). |

## User-Brand Impact

**If this lands broken, the user experiences:** an operator/agent firing
`cron/bug-fixer.manual-trigger` with `{issue_number: N}` either silently drops the
override (bug-fixer runs the default cascade against the WRONG issue, opening an
unwanted PR and spending Anthropic budget) or — worse — a malformed merge lets a
caller override `trigger`/`at`, corrupting the audit signal that distinguishes
manual-api fires from scheduled fires.

**If this leaks, the user's workflow/money is exposed via:** the route forwards
caller-controlled `data` to mutating/paid crons (`bug-fixer` opens PRs;
content-generator / competitive-analysis / growth-execution / daily-triage spend
API budget). A secret-holder who can shape `event.data` gains a strictly larger
abuse surface than the no-data form that was signed off. The shared secret remains
the trust boundary; this PR widens what a secret-holder can do once past it.

**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` — CPO sign-off required at plan time before `/work`.
`user-impact-reviewer` + `security-sentinel` invoked at review time.

## Security Analysis (REQUIRED GATE — A)

This is the load-bearing section. The route was previously signed off ONLY in its
no-data form. The merge order and validation below are the security contract; the
fresh `security-sentinel` pass is mandatory (Phase 2.7 / deepen-plan 4.4 / review).

**Threat model deltas introduced by `data` pass-through:**

1. **Field-override / audit-poisoning.** If `body.data` could override `trigger` or
   `at`, a caller could forge a payload that looks like a scheduled (non-manual) fire,
   defeating the `trigger: "manual-api"` audit marker. **Mitigation:** spread order is
   `{ ...body.data, trigger: "manual-api", at }` — i.e. **route keys are spread LAST so
   they win** (the issue's prose `{ trigger, at, ...body.data }` describes intent, not
   literal spread order; the literal must put route keys last). Add a positive test:
   `data: { trigger: "spoofed", at: "1999-01-01" }` MUST still dispatch with
   `trigger: "manual-api"` and a fresh ISO `at`.
2. **Type confusion.** `body.data` must be a plain object (not array, not primitive,
   not null). Reject non-plain-object `data` with 400 before merge. A non-object spread
   (`...42`, `...null`) is a no-op in JS but `...["a"]` injects index keys — validate
   explicitly. Allowlist remains the event-name gate; `data` validation is additive.
3. **Payload size.** The existing 64 KiB `MAX_BODY_BYTES` 413-before-parse guard already
   bounds `data` size — no new cap needed, but the security section must state that the
   guard covers the widened body (it reads `raw.length` before parse).
4. **Per-cron data semantics are the cron's responsibility, not the route's.** The route
   does NOT validate `issue_number` shape — `cron-bug-fixer.ts:594-610` already validates
   positive-integer and Sentry-reports + early-returns on invalid. The route forwards
   opaque `data`; each consuming cron validates its own fields. Document this boundary.
5. **Blast-radius unchanged on flood.** Mutating crons carry account-scoped Inngest
   concurrency caps (limit 1, key `cron-platform`); a replay/`data`-flood still collapses
   to one in-flight run. `data` pass-through does not change concurrency semantics.

**security-sentinel verdict required before merge.** If the agent is unavailable in the
execution environment, the `/work` + review phases MUST still obtain a security review of
the diff (the `review` skill's conditional security-sentinel block fires at
`single-user incident` threshold). Do NOT merge A without it.

## Acceptance Criteria

### Pre-merge (PR)

**(A) Route + tests** — file: `app/api/internal/trigger-cron/route.ts`, `test/server/internal/trigger-cron-route.test.ts`
- [ ] AC-A1: An allowlisted event with `data: { issue_number: 4383 }` dispatches an
  envelope whose `data` contains `issue_number: 4383` AND `trigger: "manual-api"` AND a
  fresh ISO `at`. (test: `mockInngestSend.mock.calls[0][0].data` deep-match)
- [ ] AC-A2: `data: { trigger: "spoofed", at: "1999-01-01" }` dispatches with
  `trigger: "manual-api"` and `at !== "1999-01-01"` (route keys win — audit-poison guard).
- [ ] AC-A3: A request with NO `data` key still dispatches `{ trigger: "manual-api", at }`
  exactly as today (back-compat). NOTE: the existing dispatch test (`trigger-cron-route.test.ts:132`)
  uses `toMatchObject` (permissive — a stray `data` spread would NOT fail it). Add an EXPLICIT
  assertion that `Object.keys(envelope.data)` equals exactly `["trigger", "at"]` when `data`
  is absent, so back-compat is gated rather than assumed.
- [ ] AC-A4: `data` as a non-plain-object (`42`, `"x"`, `["a"]`, `null` explicit) → 400,
  no dispatch. (`null`/absent treated as no-data; reject any present-but-non-plain-object.)
- [ ] AC-A5: Oversized body (`data` padding > 64 KiB) → 413 before parse, no dispatch
  (existing guard still covers widened body).
- [ ] AC-A6: `tsc --noEmit` clean; full webplat vitest shard green.

**(B) Runbooks** — files: `inngest-server.md`, `oauth-probe-failure.md`
- [ ] AC-B1: `inngest-server.md` documents `POST /api/internal/trigger-cron` (with the
  `curl` form + Bearer + JSON body incl. optional `data`) as the PRIMARY trigger path,
  ABOVE/BEFORE any `inngest send` example. The `issue_number` example is rewritten as a
  `curl … -d '{"event":"cron/bug-fixer.manual-trigger","data":{"issue_number":4383}}'`.
- [ ] AC-B2: All remaining SSH `inngest send` examples in BOTH runbooks live under a
  "Last-resort diagnosis" heading, AFTER the HTTP path, per `hr-no-ssh-fallback-in-runbooks`.
  Verify: `grep -n` each `inngest send` site falls below the HTTP-path section header.
- [ ] AC-B3: `oauth-probe-failure.md`'s 4 `inngest send cron/oauth-probe.manual-trigger`
  sites each gain (or sit under) a primary `curl` equivalent.
- [ ] AC-B4: The `ship-runbook-ssh-gate.sh` hook (and/or the runbook ssh-gate review
  agent) passes on both edited runbooks. Run the hook locally if present.

**(C) Skill** — files: `plugins/soleur/skills/trigger-cron/SKILL.md` (+ `scripts/trigger.sh`)
- [ ] AC-C1: `SKILL.md` frontmatter `description` starts with "This skill" (voice test),
  ≤ 1024 chars (char test).
- [ ] AC-C2: Cumulative skill-description word budget test
  (`components.test.ts` "cumulative description word count under budget") is GREEN — the
  new description is offset by a `SKILL_DESCRIPTION_WORD_BUDGET` bump OR sibling trim of
  ≥ the new word count (see Files to Edit; current baseline 1950/1950, ZERO headroom).
- [ ] AC-C3: The skill's script lists allowlisted events sourced from
  `MANUAL_TRIGGER_EVENTS` (derived from `EXPECTED_CRON_FUNCTIONS` — no parallel hardcoded
  list). Acceptable: the script greps/imports the manifest, OR the SKILL.md instructs the
  agent to read `MANUAL_TRIGGER_EVENTS`; either way there is no second hand-maintained list.
- [ ] AC-C4: The script reads the secret via
  `doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain` (read-only;
  the skill never writes or mutates the secret) and curls
  `https://app.soleur.ai/api/internal/trigger-cron`. A `--dry-run` flag prints the curl
  without firing.
- [ ] AC-C5: `bun test plugins/soleur/test/components.test.ts` green (kebab-case filename,
  third-person voice, char + budget tests all pass for the new skill).
- [ ] AC-C6: README/plugin component counts updated if the repo gates on them
  (run `/soleur:release-docs` or update `.claude-plugin/plugin.json` + README counts;
  verify the components test for counts passes).

### Post-merge (operator)
- [ ] AC-D1: Verify the live route accepts `data` end-to-end with a read-only, NON-mutating
  allowlisted event. **Automation:** fire `cron/workspace-sync-health.manual-trigger` (the
  data-free, side-effect-light AC4 target from #4734) via the new skill's `--dry-run` first,
  then live, and confirm 202. Do NOT post-merge-fire a mutating cron (`bug-fixer`) as a smoke
  test — that opens a real PR / spends budget. `Automation: feasible` via the skill itself.

## Implementation Phases

**Phase order is load-bearing:** A (contract widening) before C (skill that depends on the
widened body), and the security analysis governs A. B and C are docs/tooling and can follow.

### Phase 0 — Preconditions (verify, do not assume)
- Re-read `route.ts` POST body; confirm current envelope is `{ trigger: "manual-api", at }`.
- `grep -n "case \|event?.data" cron-bug-fixer.ts` to reconfirm the consumer reads
  `event.data.issue_number` and validates it (so the route stays a dumb forwarder).
- Confirm `MAX_BODY_BYTES` 413-before-parse guard reads `raw.length` (covers widened body).
- Run the budget test once to capture the exact baseline word count for C.

### Phase 1 — (A) widen the route body merge (TDD)
- RED: add AC-A1..A4 test cases to `trigger-cron-route.test.ts` (new `describe` block
  "optional event data pass-through"). They fail against the current hardcoded envelope.
- GREEN: in `route.ts`, after the allowlist check, parse `body.data`:
  - `const data = (body as {data?: unknown}).data;`
  - validate: if `data !== undefined`, require a plain object (`typeof === "object" &&
    data !== null && !Array.isArray(data)`), else 400.
  - build envelope: `{ ...(isPlainObject(data) ? data : {}), trigger: "manual-api",
    at: new Date().toISOString() }` — **route keys spread LAST**.
- Keep the existing no-data test (AC-A3) unmodified and green.

### Phase 2 — (A) security review gate
- Run `/soleur:gdpr-gate` if Phase 2.7 fires (state-mutating API route → it does).
- Obtain `security-sentinel` verdict on the diff (deepen-plan 4.4 + review). Block merge
  on it. Re-confirm the merge order, type guard, and audit-poison test are present.

### Phase 3 — (B) runbook rewrites
- `inngest-server.md`: add an "On-demand trigger via HTTP (PRIMARY)" section with the
  `curl` form (Bearer + `data`); rewrite the 2 `inngest send` examples (incl.
  `issue_number`) as `curl` equivalents; move any residual SSH loopback example under
  "Last-resort diagnosis".
- `oauth-probe-failure.md`: same treatment for the 4 `inngest send` sites.
- Run the runbook ssh-gate hook/agent on both.

### Phase 4 — (C) the trigger-cron skill
- Create `plugins/soleur/skills/trigger-cron/SKILL.md` (frontmatter: `name: trigger-cron`,
  third-person `description` starting "This skill", ≤ 1024 chars) + `scripts/trigger.sh`.
- Script: `--list` (prints `MANUAL_TRIGGER_EVENTS`), `--event <name> [--data '<json>']
  [--config prd|dev] [--dry-run]`; reads secret via `doppler secrets get … --plain`;
  curls the route; validates the event against the manifest before firing.
- **Budget offset (REQUIRED):** measure the new description's word count; either bump
  `SKILL_DESCRIPTION_WORD_BUDGET` in `components.test.ts:15` by that count (with a
  `// bumped +N for #4742` comment matching the existing convention) OR trim sibling
  skill descriptions by ≥ that count. Prefer the bump (the existing pattern at L15 is
  exactly this) unless a reviewer objects.
- Update plugin component counts (AC-C6) if gated.

### Phase 5 — full suite + AC sweep
- `bun test plugins/soleur/test/components.test.ts` + webplat vitest shard + `tsc --noEmit`.
- Walk AC-A*/B*/C* and check each.

## Files to Edit
- `apps/web-platform/app/api/internal/trigger-cron/route.ts` — widen envelope merge (A).
- `apps/web-platform/test/server/internal/trigger-cron-route.test.ts` — add data-passthrough
  + audit-poison + type-guard tests (A). (vitest node include glob `test/**/*.test.ts` covers it.)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — HTTP primary + demote SSH (B).
- `knowledge-base/engineering/operations/runbooks/oauth-probe-failure.md` — HTTP primary + demote SSH (B).
- `plugins/soleur/test/components.test.ts` — bump `SKILL_DESCRIPTION_WORD_BUDGET` by the new
  skill's description word count (C; baseline 1950/1950, zero headroom). [If trimming siblings
  instead, edit the chosen sibling SKILL.md files instead of this line.]
- `plugins/soleur/.claude-plugin/plugin.json` + `plugins/soleur/README.md` — skill count, IF
  the components test gates on counts (verify in Phase 4).

## Files to Create
- `plugins/soleur/skills/trigger-cron/SKILL.md` — thin wrapper skill (C).
- `plugins/soleur/skills/trigger-cron/scripts/trigger.sh` — Doppler-read + curl + `--list`
  + `--dry-run` (C).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` cross-referenced against all six
planned file paths (route, route test, both runbooks, allowlist module) returned zero
matches at plan time.

## Domain Review

**Domains relevant:** Engineering (security/ops), Product (CPO sign-off at single-user threshold)

### Engineering / Security

**Status:** reviewed (plan-time analysis; security-sentinel verdict pending at review)
**Assessment:** A widens a state-mutating internal route's payload surface to
caller-controlled `data` forwarded to mutating/paid crons. The shared secret remains the
trust boundary; the new risks (field-override/audit-poison, type confusion) are mitigated
by route-keys-win merge order + plain-object validation, both encoded as ACs. Blast radius
unchanged (concurrency cap limit 1). Fresh security-sentinel pass is a hard gate — see
Security Analysis. B/C are docs + read-only tooling (skill reads the secret, never mutates).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (no user-facing UI surface — internal route + runbooks + agent skill)
**Skipped specialists:** none
**Pencil available:** N/A

CPO sign-off is required by `requires_cpo_signoff: true` (threshold = single-user incident),
NOT because of a UI surface. The CPO ack is on the security approach (widening a mutating
route at single-user threshold), carried from the brand-survival framing — not a page design.

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

Phase 2.8 reviewed: this plan introduces NO new infrastructure.
`INNGEST_MANUAL_TRIGGER_SECRET` already exists as a `doppler_secret` Terraform resource
(`apps/web-platform/infra/inngest.tf:117/129`, project `soleur`, configs `prd`+`dev`,
value = `random_id.<name>.hex` — NOT operator-minted; consistent with the self-hosted-SDK
random-secret pattern). The route is already in `PUBLIC_PATHS`. The skill READS the secret
via `doppler secrets get … --plain` (read-only) and never mutates Doppler or any host. No
`.tf` change, no cloud-init, no bootstrap script. Pure code + docs + read-only tooling
against already-provisioned surfaces — the IaC routing gate is satisfied as a no-op.

## Observability

```yaml
liveness_signal:
  what: "POST /api/internal/trigger-cron returns 202 on a valid manual fire"
  cadence: "on-demand (operator/agent invoked); not a continuous signal"
  alert_target: "none (operator-invoked); dispatch failures surface via error_reporting below"
  configured_in: "route.ts POST handler"
error_reporting:
  destination: "Sentry via reportSilentFallback({feature: 'trigger-cron', op: 'dispatch'})"
  fail_loud: true   # existing 502 + reportSilentFallback path is unchanged by A
failure_modes:
  - mode: "data override of trigger/at (audit poison)"
    detection: "AC-A2 unit test (route keys win)"
    alert_route: "CI test failure (pre-merge); not a runtime alert"
  - mode: "malformed data type forwarded to a cron"
    detection: "AC-A4 unit test (400 before dispatch) + each cron's own field validator (e.g. cron-bug-fixer.ts:594 issue_number positive-int Sentry fallback)"
    alert_route: "Sentry (cron-side, existing) on invalid per-cron field"
  - mode: "inngest loopback down on dispatch"
    detection: "existing 502 + reportSilentFallback (unchanged)"
    alert_route: "Sentry"
logs:
  where: "Sentry (reportSilentFallback) + Next.js server logs"
  retention: "per existing Sentry/host retention (unchanged)"
discoverability_test:
  command: "curl -sS -o /dev/null -w '%{http_code}' --max-time 10 -X POST https://app.soleur.ai/api/internal/trigger-cron -H 'content-type: application/json' -d '{\"event\":\"cron/workspace-sync-health.manual-trigger\"}'"
  expected_output: "401"
  note: "Token-free reachability + fail-closed probe (no secret needed, no ssh): an unauthenticated POST proves the route exists and rejects with 401. The authenticated 202 path (with Bearer + optional data) is exercised by the unit suite and the post-merge AC-D1 skill --dry-run/live check."
```

## Test Scenarios

| Scenario | Input | Expected |
| --- | --- | --- |
| issue_number passthrough | `{event: bug-fixer, data: {issue_number: 4383}}` | envelope.data.issue_number === 4383, trigger === "manual-api" |
| audit-poison guard | `{event: X, data: {trigger:"spoofed", at:"1999"}}` | trigger === "manual-api", at fresh ISO |
| back-compat no-data | `{event: X}` | envelope.data === {trigger,at} only (existing test green) |
| type confusion | `{event: X, data: 42}` / `["a"]` / explicit null | 400, no dispatch |
| oversized data | `data` padded > 64 KiB | 413 before parse, no dispatch |
| skill --list | `trigger.sh --list` | prints MANUAL_TRIGGER_EVENTS (manifest-derived) |
| skill --dry-run | `trigger.sh --event X --dry-run` | prints curl, does not fire |

## Risks & Mitigations

- **Risk: spread order inverted** (`{trigger, at, ...data}` literal lets data win) →
  audit-poison. **Mitigation:** route keys spread LAST; AC-A2 positive test. The issue's
  prose order is intent, not literal code order — call this out in the diff comment.
- **Risk: skill description blows the 1950/1950 budget** (zero headroom). **Mitigation:**
  explicit budget-offset task in Phase 4 (bump or trim); AC-C2 gates it.
- **Risk: runbook edits leave an SSH example as primary** → `hr-no-ssh-fallback-in-runbooks`
  violation. **Mitigation:** AC-B2 grep gate + ssh-gate hook (AC-B4).
- **Risk: security-sentinel unavailable in the execution env.** **Mitigation:** the `review`
  skill's conditional security block fires at single-user threshold; do not merge A without
  a recorded security review of the diff.
- **Precedent diff (deepen-plan 4.4):** the route's auth/guard primitive mirrors
  `app/api/internal/kb-drift-ingest/route.ts` (fail-closed readSecret + length-guard +
  timingSafeEqual). The `data`-merge widening has no in-repo precedent for THIS route — it is
  a novel widening; security analysis above stands in for a precedent diff.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above.)
- The cumulative skill-description budget is at the cap (1950/1950) BEFORE this PR; the test
  runs under `bun test` (`import { describe } from "bun:test"`), not vitest — do not try to
  run it with vitest (fails on `Cannot find package 'bun:test'`). Use
  `bun test plugins/soleur/test/components.test.ts`.
- Vitest node include globs are `test/**/*.test.ts` + `lib/**/*.test.ts`; the new data tests
  go in the EXISTING `test/server/internal/trigger-cron-route.test.ts` (already collected) —
  do NOT co-locate a `*.test.ts` next to `route.ts` (not in the include set).
- The route stays a dumb forwarder: it does NOT validate `issue_number` (or any per-cron
  field). `cron-bug-fixer.ts:594-610` owns that validation and Sentry-reports on invalid.
  Do not duplicate per-cron field validation in the route.
- When rewriting runbook examples, the `curl` Bearer form reads the token from a shell var
  (`$TOKEN`) populated by a read-only `doppler secrets get … --plain` — never inline a
  literal secret and never use a Doppler write command in a runbook example.
