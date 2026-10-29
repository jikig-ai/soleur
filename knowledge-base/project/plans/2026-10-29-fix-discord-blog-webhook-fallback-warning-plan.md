---
title: "fix: Warn when Discord blog webhook falls back to general channel"
date: 2026-10-29
slug: fix-discord-blog-webhook-fallback-warning
branch: feat-one-shot-discord-blog-channel-fallback
type: fix
priority: normal
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: Warn when Discord blog webhook falls back to general channel

## Overview

`post_discord()` in `scripts/content-publisher.sh` resolves its webhook as
`${DISCORD_BLOG_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-}}` — blog channel first,
general channel as the intended fallback (`scripts/content-publisher.sh:330`,
comment at :329 "Prefer blog channel, fall back to general"). When
`DISCORD_BLOG_WEBHOOK_URL` is absent from an environment — as it was in the
`soleur/prd` Doppler config — the script posts blog content to the general
channel and emits **no signal** that the fallback was taken. This plan makes
the fallback path observable end-to-end: a value-free warning + marker on the
script's stderr, and a marker-targeted Sentry/pino mirror in the Inngest cron
harness that currently discards that stderr. The channel-selection order is
unchanged — this is a warning, not a behavior change. The prod credential fix
(Doppler `DISCORD_BLOG_WEBHOOK_URL` in `soleur/prd`) is handled outside this
branch; **no secret writes, Doppler mutations, or webhook creation are planned.**

Spec lacks valid `lane:` (no spec.md exists for this branch) — defaulted to
`cross-domain` (TR2 fail-closed).

## Research Insights

**Relevant file paths:**

- `scripts/content-publisher.sh:326-361` — `post_discord()`; webhook resolution
  at :330; the only existing credential warning (:333) covers the
  *neither-set* skip path, not the fallback path.
- `scripts/content-publisher.sh:9-12` — env-var header comment block
  (`DISCORD_BLOG_WEBHOOK_URL` "preferred; optional",
  `DISCORD_WEBHOOK_URL` "fallback").
- `scripts/content-publisher.sh:~63` — `SKIP_REASON` comment explicitly
  documents **"The Inngest spawn discards stderr"** — the repo already knows a
  stderr-only signal is invisible in prod.
- `apps/web-platform/server/inngest/functions/cron-content-publisher.ts`
  — `PUBLISHER_ENV_KEYS` allowlist (:67-80, forwards both webhook vars — do
  not modify); `spawnScriptCapture` (:171-193) captures stdout+stderr but the
  `run-publisher-script` step (:686-713) returns only `{ exitCode }` —
  captured stderr is **dropped**.
- `apps/web-platform/server/observability.ts:287` — `warnSilentFallback`
  (warn-level pino + Sentry mirror); `:582` `mirrorWarnWithDebounce`
  (5-min dedup sibling). `reportSilentFallback` at :218.
- `test/content-publisher.test.ts:~660` — `describe("post_discord webhook URL
  resolution")` — three tests covering blog-set / fallback / neither-set.
- `scripts/test-content-publisher.sh:100-114` — established stderr-capture
  assertion pattern (`tmp_stderr=$(mktemp -p "$SUITE_TMP")` + `grep -q`).
- `apps/web-platform/test/server/inngest/cron-content-publisher.test.ts`
  — source-shape anchors + exported-symbol unit tests (no step.run runtime
  harness; testable surface must be an exported pure helper or anchors).

**Institutional learnings / conventions:**

- `knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md`
  — the `${DISCORD_<PURPOSE>_WEBHOOK_URL:-$DISCORD_WEBHOOK_URL}` fallback is
  documented, intended design. The fix must warn, never alter resolution.
- `SOLEUR_CREDENTIAL_REFUSED` marker convention
  (`plugins/soleur/skills/community/SKILL.md`, community scripts): a
  **value-free greppable marker line** on stderr is the repo's established
  pattern for surfacing script-level credential conditions to harness
  telemetry. The fallback warning follows this shape.
- `cq-silent-fallback-must-mirror-to-sentry` (AGENTS.rules.md:121): a
  degraded-condition path must mirror to Sentry — `warnSilentFallback` is the
  warn-level vehicle; error level would over-page an intended-design fallback.
- ADR-033 cron invariants: `reportSilentFallback`/`mirrorWarnWithDebounce`
  already run inside `step.run` elsewhere in this file (:584, :599, :663) —
  mirroring inside `run-publisher-script` is consistent. I5 keeps the step's
  return shape deterministic; adding a boolean field is compatible.
- ADR-273 / #7122: `cron-community-monitor` deliberately does NOT forward
  `DISCORD_WEBHOOK_URL` — a different function, untouched.

**Premise validation (Phase 0.6).** All cited artifacts verified on
`origin/main`: `post_discord` at `scripts/content-publisher.sh:326`,
resolution at :330, header block at :9-31, the
`post_discord webhook URL resolution` describe at
`test/content-publisher.test.ts:~660`, `scripts/test-content-publisher.sh`,
and `PUBLISHER_ENV_KEYS` forwarding `DISCORD_BLOG_WEBHOOK_URL` at
`cron-content-publisher.ts:68`. No GitHub issues cited — no `gh` state checks
or collision pre-check needed. One premise **corrected**: the brief's expected
shape ("emit a stderr warning inside `post_discord()`") is necessary but **not
sufficient** — the Inngest spawn captures stderr into `result.stderr` and
returns only `{ exitCode }` (`cron-content-publisher.ts:712`), so a
stderr-only warning is invisible in the prod path where the defect fired. The
plan therefore adds a marker-targeted mirror in the same file (still "the
content-publisher path"; env forwarding untouched).

**Second-posting-path census (required by scope).** All `DISCORD_WEBHOOK_URL`
consumers on `origin/main` outside tests/docs:

| Consumer | Can misroute blog content to #general? |
|---|---|
| `scripts/content-publisher.sh` via `cron-content-publisher` (prod cron) | **Yes — the confirmed path** |
| `cron-weekly-analytics.ts:190` | No — digest targets general by design; throws `DISCORD_WEBHOOK_URL not set` when absent (fail-loud) |
| `social-distribute/SKILL.md:297` | Same `${BLOG:-GENERAL}` shape, but interactive skill inside an agent session — output is visible to the running agent/operator; not a prod cron path. Out of scope per directive. |
| `changelog/SKILL.md`, `discord-content/SKILL.md`, `agents/support/community-manager.md` | Manual/interactive general-channel consumers by design |
| `cron-community-monitor.ts:632` | Webhook deliberately NOT forwarded (#7122) — cannot post |
| `discord-setup.sh` (community skill) | `write-env` provisioning only — not a posting path |

Conclusion: the prod blog-misroute symptom can only originate from
`content-publisher.sh`. Fix scope is confirmed correct.

**Property List (Phase 0.6b):**

- P1 — When the blog webhook is absent/empty at publish time and the general
  fallback is about to be used, a signal naming the condition is emitted.
- P2 — That signal reaches an observable surface in the prod cron path
  (pino + Sentry), not only local stderr.
- P3 — The signal is value-free (env-var names + fixed tokens; never a webhook
  URL or secret material).
- P4 — Channel-selection order and payload (`allowed_mentions` suppression)
  are unchanged.

**Mechanism check.** (a) stderr warning+marker in `post_discord` buys P1+P3;
no existing mechanism covers it (the :333 warning covers the neither-set case
only). (b) Marker grep + `warnSilentFallback` in the cron step buys P2;
`reportSilentFallback` exists but is unreachable from bash, and the spawn
discards stderr — no repo mechanism already covers it. **Cut List:**
- "Fail the run when `DISCORD_BLOG_WEBHOOK_URL` is absent" — cut; the fallback
  is intended design (bot-identity learning), failing would break dev/ci.
- "Forward all captured stderr to Sentry" — cut; marker-targeted mirror is
  cheaper and noise-free.
- "Doppler prd-config drift assertion in CI" — cut; no IaC hook exists for
  asserting Doppler config contents, and the prod credential fix is handled
  outside this branch (explicitly excluded by the brief).
- "`action-required` GitHub issue on fallback" — cut; too loud for an
  intended-design degraded path that self-resolves once the secret lands;
  warn-level Sentry suffices. Re-evaluate if the fallback persists.

## Problem Statement / Motivation

Blog content posted to Discord `#general` instead of `#blog` in production.
Root cause is diagnosed: `DISCORD_BLOG_WEBHOOK_URL` exists only in the `ci`
Doppler config, not `soleur/prd`, so `post_discord()` silently resolved the
general-channel fallback. The fallback itself is intended; the **silence** is
the defect — a missing or misnamed env var produced zero observable signal on
the only surface (Inngest cron) that matters in prod. Code hardening only.

## Proposed Solution

Two coordinated, value-free emits:

1. **Script-side warning + marker** (`scripts/content-publisher.sh`): after
   the existing neither-set early-return, emit one stderr line when
   `DISCORD_BLOG_WEBHOOK_URL` is unset/empty (i.e., the resolved webhook is
   the general fallback):

   ```bash
   if [[ -z "${DISCORD_BLOG_WEBHOOK_URL:-}" ]]; then
     echo "Warning: DISCORD_BLOG_WEBHOOK_URL unset — posting to fallback webhook (general channel) [SOLEUR_PUBLISHER_FALLBACK]" >&2
   fi
   ```

   The `SOLEUR_PUBLISHER_FALLBACK` token follows the `SOLEUR_CREDENTIAL_REFUSED`
   marker convention — fixed strings only, never the URL.

2. **Cron-side marker surfacing** (`cron-content-publisher.ts`): inside the
   `run-publisher-script` step, grep captured `result.stderr` for
   `SOLEUR_PUBLISHER_FALLBACK` via a small exported pure helper
   (`publisherStderrSignals(stderr): string[]`, kept exported so the existing
   test file can unit-test it), and on match emit
   `warnSilentFallback(null, { feature: "cron-content-publisher",
   op: "discord-blog-webhook-fallback", message: "…", extra: { fn } })` —
   a **fixed message**, raw stderr is not forwarded. Extend the step's return
   to `{ exitCode, discordBlogFallback }` so the Inngest run record also
   carries the flag. `warnSilentFallback` joins the existing
   `@/server/observability` import block. `PUBLISHER_ENV_KEYS` /
   `buildPublisherEnv` are untouched.

## Technical Considerations

- **Placement**: the warning sits AFTER the `[[ -z "$webhook_url" ]]`
  early-return so it cannot fire on the neither-set skip path (that path
  already has its own warning and returns 3).
- **Empty vs unset**: `[[ -z "${DISCORD_BLOG_WEBHOOK_URL:-}" ]]` matches the
  `:-` resolution semantics exactly — unset and empty-string both warn.
- **Step.run determinism (ADR-033 I5/I1)**: the marker grep is a pure function
  of the captured stderr inside the same step; the Sentry side-effect mirrors
  the established pattern (:584, :599). Return shape stays deterministic.
- **allowed_mentions suppression** (`{parse: []}`) and avatar/username payload
  are untouched.
- **Replay safety**: `step.run` memoizes the return; the mirror fires once on
  first execution — same as existing mirrors in this handler.
- **NFR**: observability (hr-observability-as-plan-quality-gate,
  cq-silent-fallback-must-mirror-to-sentry). No performance impact (one grep
  on an in-memory string per daily run).
- **Lint surfaces**: `content-publisher.sh` is covered by
  `lint-shell-capture-exit` and `lint-shell-trace-credential-refusal`
  baselines (`scripts/lint-*.baseline.txt`) — the added lines introduce no
  `xtrace`/`curl`-capture shape changes; verify baselines stay clean.
- **Attack surface enumeration** (credential-adjacent change): the only
  env-driven secret on this path is the webhook URL. Paths that could print
  it: the `echo` warning (fixed strings — no expansion of `webhook_url`),
  the error path (`DISCORD_LAST_ERROR` carries the Discord *response body*,
  unchanged), and the Sentry mirror (fixed message, raw stderr NOT
  forwarded — so even an attacker-influenced stderr line cannot exfiltrate
  through it). No unchecked path introduced.

## User-Brand Impact

- **If this lands broken, the user experiences:** the status quo — a
  missing/misnamed `DISCORD_BLOG_WEBHOOK_URL` continues to misroute blog posts
  to `#general` silently. No new user-facing failure is introduced (the post
  itself is unchanged).
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing — the emitted strings are fixed; the Sentry mirror carries a fixed
  message and never raw stderr or credential material.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** observability-only change emitting
  value-free markers; the worst outcome of a defect here is reduced
  observability, not user harm.

- Scope-out override: `threshold: none, reason: diff touches
  apps/web-platform/server (sensitive-path regex) but only adds a
  value-free marker grep + warn-level mirror — no credential, user-data,
  or tenancy surface is altered`

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor "scheduled-content-publisher" (postSentryHeartbeat, unchanged)
  cadence: daily 14:00 UTC
  alert_target: Sentry issue stream
  configured_in: apps/web-platform/server/inngest/functions/cron-content-publisher.ts:59

error_reporting:
  destination: Sentry web-platform via existing SENTRY_DSN; pino stdout mirror via warnSilentFallback
  fail_loud: warn-level event tagged feature=cron-content-publisher op=discord-blog-webhook-fallback

failure_modes:
  - mode: DISCORD_BLOG_WEBHOOK_URL absent/misnamed in the publisher spawn env → post goes to #general
    detection: SOLEUR_PUBLISHER_FALLBACK marker on captured stderr, grepped inside run-publisher-script step
    alert_route: warnSilentFallback → Sentry warning + pino log line
  - mode: marker emit or grep regresses (warning never fires)
    detection: unit tests asserting marker presence/absence per env combination
    alert_route: CI test failure on PR

logs:
  where: pino stdout (container logs → aggregator) + Inngest step return { exitCode, discordBlogFallback }
  retention: per container log retention / Inngest run history

discoverability_test:
  command: bash -c 'source scripts/content-publisher.sh; curl(){ printf 204; }; DISCORD_WEBHOOK_URL=https://example.test/hook post_discord probe 2>&1 | grep -oF SOLEUR_PUBLISHER_FALLBACK'
  expected_output: SOLEUR_PUBLISHER_FALLBACK
```

## Guard Contract

### Guard 1 — Discord fallback marker emit + surfacing pin

**Property.** Whenever `post_discord` is about to post through the
general-channel fallback, stderr carries exactly the
`SOLEUR_PUBLISHER_FALLBACK` marker (and never when the blog webhook is set),
and the cron harness mirrors a marker match to Sentry at warn level.

**Assembly.** Two chokepoints, both pinned: (1) `post_discord()` in
`scripts/content-publisher.sh` — the single function through which every
Discord post from this pipeline flows (one resolution site, one emit site);
(2) `publisherStderrSignals` + the `warnSilentFallback` call inside the
`run-publisher-script` step of `cron-content-publisher.ts` — the single
spawn site through which all prod stderr flows.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the `if [[ -z "${DISCORD_BLOG_WEBHOOK_URL:-}" ]]` warning block | RED — fallback test asserts marker absent→required |
| 2 | Move the warning above the `[[ -z "$webhook_url" ]]` early-return so it fires on the neither-set skip path | RED — neither-set test asserts no marker |
| 3 | Emit the warning unconditionally (drop the `-z` test) | RED — blog-set test asserts no marker |
| 4 | Rename marker token in the script only (`SOLEUR_PUBLISHER_FALLBAK`) | RED — marker-grep unit test + TS helper test |
| 5 | In `publisherStderrSignals`, match `stderr.startsWith(marker)` instead of `includes` — marker mid-stream no longer detected | RED — helper test with marker not at offset 0 |
| 6 | (harness) Invert the bash test's contains → not-contains | RED — the mutated assertion fails against correct code |
| 7 | (harness, must-PASS) `DISCORD_BLOG_WEBHOOK_URL=""` (empty string, not unset) + general set → marker fires | PASS — `-z` semantics treat empty as missing, matching `:-` resolution |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "emit a stderr warning inside post_discord() when DISCORD_BLOG_WEBHOOK_URL is unset/empty and the script is about to use the DISCORD_WEBHOOK_URL fallback" | FR-1 / `scripts/content-publisher.sh` | mapped |
| 2 | "Update the header comment block documenting env vars if needed" | FR-2 / `scripts/content-publisher.sh:9-12` | mapped |
| 3 | "Add/extend test coverage in test/content-publisher.test.ts (the \"post_discord webhook URL resolution\" describe block ~line 661) and/or scripts/test-content-publisher.sh to assert the warning fires on fallback and does NOT fire when DISCORD_BLOG_WEBHOOK_URL is set" | FR-3 / both test files | mapped |
| 4 | "Check whether the prd symptom could ALSO come from a second posting path … and report findings in the plan; fix only the content-publisher path" | Second-posting-path census (Research Insights + Context) | mapped |
| 5 | "make the fallback path observable so a missing/misnamed DISCORD_BLOG_WEBHOOK_URL can never again misroute silently" | FR-1 + FR-4 (marker surfacing in cron step) | mapped |
| 6 | "never print or write any real webhook URL or secret value" | P3 design constraint + AC-4 | mapped |
| 7 | "do NOT plan any secret writes, Doppler mutations, or webhook creation" | Out-of-scope declaration (Overview) | mapped |
| 8 | "do not modify apps/web-platform env forwarding (PUBLISHER_ENV_KEYS already forwards the key)" | Constraint; AC-7 pins the allowlist unchanged | mapped |
| 9 | "keeping allowed_mentions suppression" | AC-6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| FR-1 stderr warning + marker in `post_discord` | ask 1 | asked |
| FR-2 header comment update | ask 2 | asked |
| FR-3 test coverage (bun + shell suites) | ask 3 | asked |
| FR-4 `SOLEUR_PUBLISHER_FALLBACK` grep + `warnSilentFallback` in `run-publisher-script` | ask 5 ("never again misroute silently") | inferred — justification: `spawnScriptCapture`'s `result.stderr` is captured then discarded (`cron-content-publisher.ts:696-712` returns `{ exitCode }` only; the `SKIP_REASON` comment at `content-publisher.sh:~63` states "The Inngest spawn discards stderr"). A stderr-only warning is invisible in the prod path where the defect fired, so ask 5 cannot be met without surfacing the marker. |
| FR-5 `publisherStderrSignals` exported helper + unit tests | — | inferred — justification: the cron test file's established pattern requires an exported symbol or source-shape anchors; an exported pure helper is the minimal testable surface for FR-4. |

### Split Assessment

- Subsystems touched: 3 — `scripts/`, `test/`, `apps/web-platform`
- Planned files: 5 | Estimated changed lines: ~90
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Files to Edit

- `scripts/content-publisher.sh` — add fallback warning + `SOLEUR_PUBLISHER_FALLBACK` marker in `post_discord` (~:330); update env-var header comment (~:11-12).
- `apps/web-platform/server/inngest/functions/cron-content-publisher.ts` — add `warnSilentFallback` to the observability import; add exported `publisherStderrSignals(stderr: string): string[]` helper; in `run-publisher-script`, grep `result.stderr` for the marker, mirror on match, extend step return with `discordBlogFallback: boolean`. Do NOT touch `PUBLISHER_ENV_KEYS` / `buildPublisherEnv`.
- `test/content-publisher.test.ts` — extend `describe("post_discord webhook URL resolution")` (~:660): assert marker on fallback, assert absence when blog URL set, assert absence on the neither-set skip path, add empty-string case.
- `scripts/test-content-publisher.sh` — add stderr-capture assertions (existing `tmp_stderr` + `grep -q` pattern, :100-114) for marker-fires-on-fallback and marker-absent-when-blog-set.
- `apps/web-platform/test/server/inngest/cron-content-publisher.test.ts` — unit tests for `publisherStderrSignals` (marker present / absent / mid-stream) + source-shape anchors for `SOLEUR_PUBLISHER_FALLBACK` and `discord-blog-webhook-fallback`.

## Files to Create

None.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 issues) contains
no body reference to any of the five planned files.

## Domain Review

**Domains relevant:** Engineering, Marketing

(Inline assessments — subagent fan-out unavailable in this pipeline context;
each domain's Assessment Question applied by the orchestrator.)

### Engineering

**Status:** reviewed
**Assessment:** Credential-adjacent observability hardening on an ADR-033
cron. The marker-grep + `warnSilentFallback` surfacing mirrors patterns
already in this handler (`reportSilentFallback` at :584, `mirrorWarnWithDebounce`
at :599); step-return stays deterministic (I5). Risk is low: pure function of
in-memory stderr, no new subprocess, no env-forwarding change. Technical
rulings are recorded in `decision-challenges.md` (CTO spawn unavailable —
`pending - assumed` rows).

### Marketing

**Status:** reviewed
**Assessment:** The defect was a channel-targeting failure (brand content in
`#general` vs `#blog`); this change restores *visibility* into that routing,
it does not change messaging, copy, or audience. No content-surface
implications; no copywriter involvement warranted.

### Product/UX Gate

**Tier:** none — no user-facing surface; Files lists contain no
`components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx` (mechanical
override did not fire) and the change implements no UI concept.
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] AC-1 — Given only `DISCORD_WEBHOOK_URL` set, `post_discord` posts to the general webhook AND emits an stderr line containing `SOLEUR_PUBLISHER_FALLBACK` naming `DISCORD_BLOG_WEBHOOK_URL` unset and the general-channel fallback (`test/content-publisher.test.ts` + `scripts/test-content-publisher.sh`).
- [ ] AC-2 — Given `DISCORD_BLOG_WEBHOOK_URL` set (non-empty), `post_discord` stderr does NOT contain `SOLEUR_PUBLISHER_FALLBACK`.
- [ ] AC-3 — Given `DISCORD_BLOG_WEBHOOK_URL=""` (empty) and `DISCORD_WEBHOOK_URL` set, the marker fires (empty ≡ unset, matching `:-` semantics).
- [ ] AC-4 — Given neither var set, `post_discord` returns 3 with the existing "No Discord webhook URL set" warning and NO `SOLEUR_PUBLISHER_FALLBACK` marker.
- [ ] AC-5 — No emitted line (warning, marker, or Sentry mirror) contains a webhook URL: the added emit sites are fixed strings — `grep` of the added lines shows no `$webhook_url` / `${DISCORD_*}` interpolation, and the cron mirror's `message`/`extra` contain no raw stderr.
- [ ] AC-6 — `allowed_mentions: {parse: []}` payload and the `DISCORD_BLOG_WEBHOOK_URL → DISCORD_WEBHOOK_URL` resolution order are byte-identical after the change (`git diff` on those lines shows only added code).
- [ ] AC-7 — `PUBLISHER_ENV_KEYS` and `buildPublisherEnv` are unchanged (`git diff` shows no edit to those blocks); `grep -n '"DISCORD_BLOG_WEBHOOK_URL"' cron-content-publisher.ts` still lists it.
- [ ] AC-8 — `run-publisher-script` calls `publisherStderrSignals(result.stderr)` and fires `warnSilentFallback` with `op: "discord-blog-webhook-fallback"` on marker match; the step return carries `discordBlogFallback`; raw stderr is never forwarded to Sentry (fixed `message` only).
- [ ] AC-9 — Header env-var comment updated to document the fallback warning/marker.
- [ ] AC-10 — Existing behavior tests pass: rc 0 success, rc 1 HTTP-failure, rc 3 skip, "[ok] Discord message posted", and both shell-lint baselines (`lint-shell-capture-exit`, `lint-shell-trace-credential-refusal`) stay clean.

## Test Scenarios

- `unit` — Given `DISCORD_WEBHOOK_URL` set + `DISCORD_BLOG_WEBHOOK_URL` unset, when `post_discord` runs with stubbed curl, then stderr contains `SOLEUR_PUBLISHER_FALLBACK` and `CALLED_URL=https://general-webhook`, rc 0.
- `unit` — Given both URLs set, when `post_discord` runs, then stderr does NOT contain the marker, `CALLED_URL=https://blog-webhook`, rc 0.
- `unit` — Given `DISCORD_BLOG_WEBHOOK_URL=""` + general set, when `post_discord` runs, then marker fires.
- `unit` — Given neither set, when `post_discord` runs, then rc 3, "No Discord webhook URL set" on stderr, no marker.
- `unit` — Given a captured stderr containing `SOLEUR_PUBLISHER_FALLBACK` mid-stream, when `publisherStderrSignals` runs, then it returns the matched signal; given stderr without the marker, empty result.
- `unit` — Shell suite (`scripts/test-content-publisher.sh`): `post_discord` stderr captured to a tmp file (existing `tmp_stderr` pattern) asserts marker present on fallback / absent with blog URL set.
- `unit` (regression) — Given the prd condition (blog var absent), the marker that would have caught it is asserted present — this is the exact silent-misroute trigger.

## Success Metrics

- A future missing/misnamed `DISCORD_BLOG_WEBHOOK_URL` produces a Sentry warning + pino line on the first affected run (daily cadence), instead of zero signal.
- Zero change in posting behavior: resolution order, payload, and rc conventions unchanged (all existing tests stay green).

## Dependencies & Risks

- **Risk:** marker-text drift between script and cron grep — mitigated by both sides pinning the literal token in tests (Guard 1 row 4).
- **Risk:** noise — `warnSilentFallback` (not `reportSilentFallback`) keeps the event at warn level; one event per affected daily run, self-resolving once the secret lands.
- **Dependency:** none. The prod `DISCORD_BLOG_WEBHOOK_URL` Doppler secret is set outside this branch; the code is correct with or without it (marker silences itself once set).

## Context

- Symptom: blog posts in `#general` (channel id of the minted prd webhook: `1481578783000629329` — set by operator outside this branch).
- The `SKIP_REASON` comment at `scripts/content-publisher.sh:~63` documents that the Inngest spawn discards stderr — the reason the marker-surfacing half of this change exists.
- Related env-boundary precedent: ADR-273, #7122 (community monitor drops the webhook), ADR-033 (cron spawn invariants), `cq-silent-fallback-must-mirror-to-sentry`.

## References & Research

- `scripts/content-publisher.sh:326-361` (post_discord), `:9-12` (header), `:63` (stderr-discard note)
- `apps/web-platform/server/inngest/functions/cron-content-publisher.ts:67-80, 154-193, 686-713`
- `apps/web-platform/server/observability.ts:287` (`warnSilentFallback`)
- `knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md` (fallback convention)
- Marker convention: `SOLEUR_CREDENTIAL_REFUSED` in `plugins/soleur/skills/community/SKILL.md` + community scripts
- `test/content-publisher.test.ts:~660`, `scripts/test-content-publisher.sh:100-114`
