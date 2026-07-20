---
title: "fix: stop the daily false page from the Anthropic cost-report cron, and bound the mint window"
date: 2026-07-20
type: fix
branch: feat-one-shot-6297-anthropic-key-missing-false-page
issue: 6297
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# fix: stop the daily false page from the Anthropic cost-report cron, and bound the mint window

## Overview

`cron-anthropic-cost-report` states in its own header that the key-missing state is reported
**"BENIGNLY … NOT a fleet-down page."** The implementation contradicts that: the key-missing branch
routes through `reportSilentFallback`, which emits to Sentry at `level: "error"`. Sentry derives
issue **priority** from level (error → high), and the operator's personal *"Send a notification for
high priority issues"* rule fires on it. The operator has received this page every day since
2026-07-10.

Two defects:

- **D1 (primary, code):** intent says do-not-page; implementation pages daily.
- **D2 (process):** a "temporary mint window" was encoded as an *indefinitely*-tolerated dark state
  with no expiry and no escalation. It sat at `priority/p3-low` with nothing forcing it forward. The
  only thing that surfaced it was the false page itself.

The fix for D1 is a one-symbol swap to the already-existing `warnSilentFallback`. The fix for D2
gives the dark window an **age** (carried in the marker as inert reporting data) and moves escalation
into the **backlog channel** — a `follow-through`-labelled, `priority/p2-medium` tracker with a
self-closing probe — rather than back into the paging channel. A code-level severity escalation was
proposed and **cut at review**; see `decision-challenges.md` DC-1.

**This PR touches no `.tf` file.** See §Infrastructure (IaC) — that is a load-bearing sequencing
constraint, not an omission.

> No `spec.md` exists for this branch (one-shot entry, no preceding brainstorm), so the plan lacks a
> valid `lane:` source and was **defaulted to `cross-domain` (TR2 fail-closed)**.

## Enhancement Summary

**Deepened on:** 2026-07-20
**Passes run:** plan-review (Kieran / code-simplicity / observability-coverage), then deepen
(architecture-strategist, spec-flow-analyzer, learnings-researcher, verify-the-negative sweep).

### Key improvements

1. **Phase 3 cut.** A proposed day-31 severity escalation was removed — three independent findings,
   the decisive one being that `FIRST_DARK_FIRE` is a frozen literal, so a future mint-then-rotate
   would have paged at `level=error` on day one of a fresh benign gap. Recorded in
   `decision-challenges.md` DC-1 with the dissenting view.
2. **P0 — probe echo isolation.** The follow-through probe could have PASSed on the webhook echo of
   this plan's own prose (`--grep` is an unanchored `raw LIKE`; GitHub webhook bodies ship into the
   same Better Stack source). Now field-isolated on `"component":"claude-cost"` in both byte-forms,
   with a contamination fixture arm.
3. **P0 — two mitigations were unimplementable as first written.** The probe runs under `env -i`
   with no persistent state, so the "7 consecutive runs" counter and the Sentry cross-check were both
   unreachable without `GH_TOKEN` and `SENTRY_AUTH_TOKEN` in `secrets=`. Both added; AC14b asserts
   reachability rather than trusting the prose.
4. **P0 — the operator handoff was wrong.** Pasting only into `prd_terraform` would never have
   reached the cron (it reads `prd`), so the promised self-closure could not occur — D2 reconstructed.
   The operator now writes both configs; `ignore_changes = [value]` lets Terraform adopt the value.
5. **`exit 1` made reachable** (ok-then-key-missing), so the sweeper's closed-set reopen path is no
   longer structurally inert.
6. **AC hygiene.** Several ACs were inverted or vacuous: `grep -c` exits 1 on a zero count (AC6/AC10),
   AC21 could not distinguish "not error" from "not emitting" (AC22 added as a positive control), and
   AC6 was scoped to `*.tf` when the auto-apply trigger is the whole `infra/**` tree.

### New considerations discovered

- Better Stack retention on this source is **3 days**, which bounds the probe's query window and was
  a further argument against a 30-day budget.
- `ANTHROPIC_ADMIN_KEY` is deliberately **absent** from `verify-required-secrets.sh`; adding it would
  convert a supported optional-key state into a release-blocking gate.
- The follow-up IaC PR must carry the `-target=` allow-list line or the resource is declared and
  never applied.
- One plan claim was falsified by the verify-the-negative sweep ("19 of 40" banned-form probes →
  actually **14 of 39** under the plan's own comment-stripping method) and corrected.
- **Verified non-applicable:** `2026-05-27-sentry-warning-level-still-triggers-alert-rules.md` shows
  Sentry `EventFrequencyCondition` rules count events regardless of level — so a level downgrade
  would *not* have helped against a tag-keyed frequency rule. Confirmed no such rule exists here:
  `issue-alerts.tf` has 27 rules and none match this cron's `feature`/`op`. The fix works because the
  operator's rule filters on *priority*, which is level-derived.

## Research Reconciliation — Spec vs. Codebase

| Claim (from the issue / prompt) | Verified reality | Plan response |
|---|---|---|
| `reportSilentFallback` surfaces at `level=error` | **CONFIRMED.** `observability.ts` `reportSilentFallback`: `err` is `null` (not an `Error`), so it falls to the `captureMessage` arm with an explicit `level: "error"`. Matches the Sentry tag evidence. | Swap this one branch to `warnSilentFallback` (`level: "warning"`). |
| A Terraform alert rule pages the operator | **FALSE.** `infra/sentry/issue-alerts.tf` contains **no** rule matching `anthropic` / this cron. The page comes from Sentry's built-in level→priority derivation feeding the operator's personal notification rule. | Fix must lower the emitted **level**. Editing alert rules would not help and is out of scope. |
| The `SOLEUR_CLAUDE_COST_DAILY` marker reaches Better Stack | **CONFIRMED by reading the pipeline, not assumed.** `claude-cost-marker.ts` uses a *dedicated* pino instance at **WARN (40)** → stdout → Docker `--log-driver journald` → Vector `[sources.app_container_journald]` → `[transforms.app_container_warn_filter]` (`level_int >= 40`) → `[sinks.betterstack]` (HTTP, `type = "http"`). No pino transport exists in `package.json`. | Any fix MUST keep the pino line at ≥ 40. `warnSilentFallback` logs at `logger.warn` (40) — still ships. An `info`-level fix would have gone dark. |
| Minting an Admin key is Console-only | **PARTLY.** Docs FAQ confirms *"new API keys can only be created through the Claude Console for security reasons. The Admin API can only manage existing API keys."* That verifies **no creation API**. It does **not** verify the Console UI is un-automatable. | Record `automation-status: UNVERIFIED`. /work MUST attempt Playwright before any operator handoff (see §Operator Action). |
| `follow-through` label exists | **CONFIRMED** — `External dependency awaiting verification`, `#C5DEF5`. `priority/p2-medium`, `action-required`, `deferred-automation` also confirmed. Avoid legacy near-misses `P2-medium` / `priority:p3`. | Use the `priority/pN-*` slash forms. |
| `ANTHROPIC_ADMIN_KEY` absent | **CONFIRMED** absent from Doppler `prd`, `dev`, **and `prd_terraform`** (names-only check; no values printed). No `.tf` references it. | The IaC half cannot merge before the mint — see §Infrastructure (IaC). |

## Hypotheses

Not a network/connectivity defect — the L3→L7 checklist does not apply. The causal chain is fully
established by reading (level → priority → notification rule), with the Sentry tag `level=error` as
direct runtime confirmation. No competing hypothesis survives.

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) the daily 08:17 CEST false-page email
continues — the operator keeps triaging a non-incident, and alarm fatigue erodes trust in *every*
Sentry page including real fleet-down ones; or (b) an over-correction silences the branch entirely
and the `SOLEUR_CLAUDE_COST_DAILY {status:"key-missing"}` row stops shipping, so the cost-report
surface goes dark with no positive signal — the exact mis-triage ADR-108 Decision item 4's "positive
`capture_status` on every substrate exit" rule exists to prevent.

**If this leaks, the user's data is exposed via:** no new exposure vector. The key-missing branch
carries no request data; the marker's per-model rows are a strict field allowlist (`api_key_id` /
`workspace_id` are never spread). The change moves a severity level and adds an integer day count.

- **Brand-survival threshold:** `aggregate pattern` — the harm is cumulative alarm fatigue and a
  decayed dark state, not a single-user incident.

## Open Code-Review Overlap

One match, on `observability.ts` only:

- **#3739** — *review: extract `reportSilentFallbackWithUser` helper (collapse 11-site
  `withIsolationScope`+`setUser` duplication)*. **Disposition: acknowledge.** Different concern
  (call-site duplication of the user-scoping wrapper). This plan does not add a call site to that
  pattern — it *removes* one `reportSilentFallback` call and replaces it with `warnSilentFallback`,
  which if anything marginally shrinks #3739's surface. No edit to the helper's signature. #3739
  remains open.

No open code-review issue references `cron-anthropic-cost-report.ts` or `claude-cost-marker.ts`.

## Implementation Phases

### Phase 1 — D1: make the key-missing branch non-paging (failing-first)

**1.1 — RED.** Extend `apps/web-platform/test/server/inngest/cron-anthropic-cost-report.test.ts`.

> **Load-bearing detail:** the existing `vi.mock("@/server/observability", …)` factory exports
> **only** `reportSilentFallback`. Switching the branch to `warnSilentFallback` without extending the
> factory makes the import `undefined` and the test dies with a `TypeError` instead of a clean
> assertion failure. Add `warnSilentFallback` to the factory **in the same edit** as the RED test.

Add a `warnSilentFallbackSpy` to the `vi.hoisted` block and the mock factory, then assert:

- **key-missing does NOT emit at error severity:** `expect(reportSilentFallbackSpy).not.toHaveBeenCalled()`
  and `expect(warnSilentFallbackSpy).toHaveBeenCalledWith(null, expect.objectContaining({ op: "anthropic-admin-key-missing" }))`.
- **content anchor, not a bare token** (`cq-assert-anchor-not-bare-token`): additionally assert the
  message still carries the substring `daily cost report is dark` — the operator-facing string that
  the Better Stack runbook documents. A bare `op:` check would pass against an empty message.
- **401/403 still DOES emit at error severity:** the existing 401 and 403 cases must additionally
  assert `expect(reportSilentFallbackSpy).toHaveBeenCalledWith(expect.any(Error), expect.objectContaining({ op: "anthropic-admin-key-invalid" }))`
  **and** `expect(warnSilentFallbackSpy).not.toHaveBeenCalled()`. This is the regression guard that
  stops a future "just make it all warn" edit from weakening the fatal arms.

**1.2 — GREEN.** In `cron-anthropic-cost-report.ts`:
- add `warnSilentFallback` to the existing `@/server/observability` import;
- change the key-missing branch's `reportSilentFallback(null, {…})` to `warnSilentFallback(null, {…})`.

Leave the options object otherwise unchanged — `feature`, `op`, `message`, `extra` all keep their
current values so existing Better Stack / Sentry queries keyed on `op:anthropic-admin-key-missing`
continue to match.

**1.3 — Do NOT touch** the 401/403 arm, the 429/5xx rethrow, `isFinalAttempt` gating, the schedule,
the concurrency block, or the success path.

**Why `warnSilentFallback` and not "drop the Sentry emission":** dropping it would violate
`cq-silent-fallback-must-mirror-to-sentry`. ADR-108 Decision item 2 ("Dedicated Sentry-mirror-bypassing logger") names the *only* sanctioned exemption to that
rule as the marker emitter itself (`emitClaudeCost*Marker`), explicitly because it uses a
Sentry-mirror-bypassing pino instance. The key-missing branch is not covered by that exemption. A
warn-level mirror keeps the branch queryable in Sentry while dropping it out of the high-priority
notification band.

### Phase 2 — D2a: carry the dark-window age in the marker

**2.0 — two guards to record before touching the interface.**
- **Cross-consumer sweep** (`hr-type-widening-cross-consumer-grep`): `git grep -n "ClaudeCostDailyMarker"`
  and confirm the consumer set is closed. Verified at plan time: the type definition, the two call
  sites in `cron-anthropic-cost-report.ts`, and the test mock — no cross-package consumer. Record the
  sweep output in the PR body rather than asserting it.
- **ADR-029 marker boundary:** `claude-cost-marker.ts` carries a ‼️ BOUNDARY comment — this dedicated
  pino instance has **no** `renameUserIdToHash` formatter and **no** `redact` paths, so any field
  added to these interfaces must stay free of user ids, emails, secrets, and regulated data. An
  integer day count complies; note the check in the ADR-108 amendment so the guard stays alive for
  whoever adds the next field.

**2.1** In `apps/web-platform/server/claude-cost-marker.ts`, extend `ClaudeCostDailyMarker` with an
**optional** field so `status:"ok"` rows are unaffected:

```ts
// Whole UTC days since the FIRST observed dark fire — key-missing path only,
// absent on `status:"ok"`. Deliberately NOT "age of the current dark window":
// this does not reset if the key is minted and later unset (e.g. a rotation
// window — ADR-108 names key exposure a rotation trigger). It is inert
// reporting data; nothing branches on it. Prior art for the shape:
// `days_since_last` on cron-skill-freshness.ts.
days_since_first_dark?: number;
```

**2.2** In `cron-anthropic-cost-report.ts`, add a module-level constant and a pure, unit-testable
helper beside `priorUtcDay`:

```ts
// First observed dark fire (Sentry e0e6f356764b4bb6be8b0a8e74898e9f, release
// web-platform@0.208.0). A frozen historical date, NOT a window start —
// see the field comment in claude-cost-marker.ts. Measured from here rather
// than process start so a container restart never resets the count.
const FIRST_DARK_FIRE = "2026-07-10";
export function daysSinceFirstDark(now: Date = new Date()): number { /* whole UTC days, floored at 0 */ }
```

Pass `days_since_first_dark: daysSinceFirstDark()` on the key-missing `emitClaudeCostDailyMarker`
call, and add it to the `extra` of the `warnSilentFallback` call so it is visible in Sentry too.

**2.3** Unit-test `daysSinceFirstDark` against fixed `Date` inputs (same shape as the existing
`priorUtcDay` test): a date before the constant floors to `0`; `2026-07-20` yields `10`.

> **Phase 3 (code-level day-31 severity escalation) was cut at plan-review.** It is recorded, with
> the full reasoning and the three independent arguments that killed it, in
> `knowledge-base/project/specs/feat-one-shot-6297-anthropic-key-missing-false-page/decision-challenges.md`.
> Summary: it would have re-introduced the exact daily page this PR removes; its own alert route was
> factually inert; and — decisively — because `FIRST_DARK_FIRE` is a frozen literal, a future
> mint-then-rotate would have made the counter read ~120 and paged at `level=error` on day one of a
> fresh, benign gap. Self-escalation is delivered by **Phase 4** instead, through the
> backlog/tracker channel where a "you still need to mint a key" nag belongs.
>
> Phase numbering is left as 1, 2, 4, 5 deliberately — renumbering would break the cross-references
> in `decision-challenges.md` and in the review record.

### Phase 4 — D2c: self-closing follow-through tracker

**4.1** Create `scripts/followthroughs/anthropic-admin-key-6297.sh`, modelled on
`cert-reissue-markers-6698.sh` (the closest prior art: an external observability-state probe that
delegates to `betterstack-query.sh`).

The probe verifies the **end state** — that the cron actually produced a healthy report — rather than
secret presence. This matters: the sweeper's `secrets=` allowlist wires `BETTERSTACK_QUERY_*` but has
**no `ANTHROPIC_*` and no `DOPPLER_TOKEN`**, so a secret-presence probe is not expressible without
new workflow wiring. Verifying the end state is both expressible today and strictly stronger — a
minted-but-broken key does not close the issue.

Contract:
- `exit 0` (PASS → sweeper closes #6297) — a **field-isolated** producer row (see below) with
  `"status":"ok"` within the query window.
- `exit 1` (FAIL) — a genuine **regression**, defined concretely so this branch is reachable: the
  window contains a field-isolated `"status":"ok"` row **and** the most recent field-isolated row is
  `"status":"key-missing"` — i.e. the key worked and then stopped. **Not** used for "not yet minted".
- `exit 2` (TRANSIENT) — still `key-missing` with no prior `ok` in the window, or query/auth failure,
  or `betterstack-query.sh` missing/non-executable, or zero producer rows.

> **Exit 1 must be genuinely reachable.** The sweeper's closed-set reopen path acts on **exit 1 only**
> (`sweep-followthroughs.sh:344-360`); exit 0 and transient are full no-ops there. A probe with no
> reachable exit-1 condition leaves that path structurally inert — so if #6297 were ever closed
> prematurely (by a human, or by an echo-PASS slipping past AC12), nothing could reopen it. The
> ok-then-key-missing predicate above is stateless, computable from a single 48h query, and is a real
> regression signal (key revoked, rotated away, or IaC reverted).

> **P0 — the probe must not pass on its own echo.** `betterstack-query.sh --grep` compiles to an
> **unanchored** `raw LIKE '%…%'` over a source that *every* host multiplexes into — and Inngest
> ships GitHub webhook payloads (issue and PR bodies) into that same source. This plan quotes both
> `SOLEUR_CLAUDE_COST_DAILY` and `"status":"ok"` in the PR body, the issue body, and the ADR
> amendment; worse, the sweeper posts the probe's own stdout as a comment on #6297, which then rides
> a webhook straight back into Better Stack. A naive substring probe can therefore PASS on its own
> echo and auto-close the tracker while the key is still unminted — the exact #5934 failure mode
> `followthrough-convention.md:25` exists to prevent, and the guard
> `cert-reissue-markers-6698.sh:28-32` documents.
>
> **The probe MUST field-isolate**, matching the producer's structure rather than a quotable string:
> require **both** the marker key `"SOLEUR_CLAUDE_COST_DAILY":true` **and** `"component":"claude-cost"`
> — the base field stamped by the dedicated pino instance at `claude-cost-marker.ts:32`, which no
> webhook payload carries. Prose that merely *quotes* the marker name cannot satisfy both.
>
> **Match in BOTH byte-forms** — they differ by context, and checking only one silently false-FAILs
> against live prod (`2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md`):
> - **Server-side** (`betterstack-query.sh --grep`, which becomes `raw LIKE '%…%'` against the
>   *unescaped* ClickHouse column): `"component":"claude-cost"`
> - **Client-side** (`grep -F` over the JSONEachRow stdout, where inner quotes are
>   backslash-escaped): `\"component\":\"claude-cost\"`
>
> *(That learning isolates on `SYSLOG_IDENTIFIER` because its producer rides Vector Source 4,
> `host_scripts_journald`. This marker rides **Source 3**, `app_container_journald`, which matches on
> `CONTAINER_NAME` and carries no `SYSLOG_IDENTIFIER` discriminator — so the pino `component` base
> field is the correct analogue here. The two-byte-form requirement transfers unchanged.)*
>
> **Fixtures must include a contamination arm:** a webhook-shaped row embedding both marker strings in
> its payload must **not** satisfy the PASS condition. Mutation-prove it (flip the guard, confirm the
> fixture flips) so the arm is not vacuous.

**Query window:** pin to `--since 48h`. Better Stack retention on this source is **3 days**
(`betterstack-log-query.md:85`), so any window > 72h reads empty regardless of producer health, and
48h covers two daily cron fires with margin.

> **Do NOT copy `ghcr-minter-live-6031.sh:28`.** It uses `: "${VAR:?msg}"`, which
> `followthrough-convention.md:24` explicitly bans — under a non-interactive shell that expansion
> aborts with status **1**, i.e. FAIL, so an unprovisioned secret would accrete a daily false-FAIL
> comment. Use the documented guard: `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: …" >&2; exit 2; fi`.
> Use `set -uo pipefail` (not `-e`), per house style.

Require a **positive liveness marker** before concluding: if the query returns *no* field-isolated
producer rows at all (neither `ok` nor `key-missing`), that means the producer did not run — exit
**2**, never 0. Per `followthrough-convention.md:25`, "zero bad events" is not a PASS without proof
the producer ran.

**Bound the TRANSIENT.** A permanently-TRANSIENT probe is itself the D2 defect in miniature: if the
cron runs and emits but the Better Stack path drops the row (Vector down, sink 4xx, token rotation,
quota exhaustion), the Sentry cron monitor stays **GREEN** (the check-in succeeded) while the probe
reads zero rows and returns `exit 2` *forever* — #6297 never closes, never FAILs, never escalates.
That is an unbounded silent stall of exactly the kind this plan exists to remove, so the probe must
not be allowed to shrug indefinitely:

- On a **zero-producer-rows** result, cross-check the *other* path before concluding. The
  `warnSilentFallback` line travels Layer 2 (shared logger → Sentry breadcrumb → direct HTTPS to
  Sentry), which is a **different** transport from the marker's Layer 3 (Vector → Better Stack). If
  Sentry shows recent `op:anthropic-admin-key-missing` activity while Better Stack shows nothing, the
  producer is alive and the *shipping path* is broken — a real regression. Emit that distinction in
  the probe's stdout (the sweeper posts it as the issue comment) so one shared-mode failure cannot
  hide both signals.
- Escalate a persistent stall rather than repeating an identical TRANSIENT: once the issue already
  carries **7 or more** prior sweeper comments reporting zero producer rows, print an explicit
  `STALLED:` line naming the elapsed span. Keep the exit code at `2` — FAIL (exit 1) would reopen or
  annotate on a shipping-path fault the operator cannot fix by minting a key, and the convention
  reserves exit 1 for "this should NOT close."

> **Both mitigations above require secrets the naive `secrets=` clause omits — this was a real defect
> caught at deepen-review.** The sweeper runs every probe under
> `env -i PATH=… HOME=…` plus *only* the names listed in the directive's `secrets=`
> (`sweep-followthroughs.sh:318`), and the probe gets a fresh checkout with no persistent state —
> `sweep-followthroughs.sh:101` states it outright: *"the script is stateless and runs its
> verification under `env -i`, so an in-process counter cannot survive between sweeps. GitHub's own
> comment history is the state."*
>
> Therefore:
> - **`GH_TOKEN` is mandatory** — without it the probe cannot read its own comment history, and
>   "7 consecutive runs" is **unknowable inside the probe**. The counter must be derived from prior
>   comments via `gh issue view`, not from an in-process variable. `followthrough-convention.md:66-73`
>   already states `secrets=GH_TOKEN` is mandatory for any `gh`-using probe.
> - **`SENTRY_AUTH_TOKEN` is mandatory** for the cross-check. It exists in the sweeper's `env:` block
>   (`scheduled-followthrough-sweeper.yml:62`) but is stripped by `env -i` unless named.
>
> Omitting either does not fail loudly — it silently makes the mitigation unreachable while every AC
> still passes. AC14 must therefore assert all five names, not just the Better Stack three.

**4.2** Update issue #6297:
- relabel: remove `priority/p3-low`, add `priority/p2-medium` + `follow-through`;
- keep `deferred-automation` — and ensure the literal string `deferred-automation` remains in the
  **body**, because `.claude/hooks/ship-operator-step-gate.sh:139` greps the body text, not the label;
- add the directive (`earliest=` is the filing date — the script self-gates via its TRANSIENT exit, so
  a far-future `earliest` would double-gate):

```html
<!-- soleur:followthrough
  script=scripts/followthroughs/anthropic-admin-key-6297.sh
  earliest=2026-07-20T00:00:00Z
  secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD,SENTRY_AUTH_TOKEN,GH_TOKEN
-->
```

All five names are verified present in the sweeper's `env:` block
(`scheduled-followthrough-sweeper.yml`: `GH_TOKEN` at :56, `SENTRY_AUTH_TOKEN` at :62, the three
`BETTERSTACK_QUERY_*` at :72-74). Note the sweeper **fails safe but silently** on a missing name —
`sweep-followthroughs.sh:328` logs *"required secret … not set in workflow env — leaving issue open"*
and returns 0 **without posting a comment**, so a typo'd or unprovisioned name makes the tracker go
quiet rather than erroring. Since the sweeper comment is the *only* push signal for the dark state
(see §Observability), each name must be checked against that block rather than assumed.

**4.3** Rewrite the issue body's operator section in plain language — see §Operator Action.

### Phase 5 — Records

**5.1** Amend **ADR-108** (do not author a new ADR). Phase 1 restores compliance with what ADR-108 Decision item 5 ("Daily Admin cost-report cron")
already decided ("self-reports `{status:"key-missing"}` benignly … no page") — that is a bug fix, not
a new decision. The one genuinely new item is the `days_since_first_dark` marker field, which belongs
in the ADR because the marker convention is ADR-108's subject. Add it to `## Decision`; note in
`## Consequences` that the field measures from a frozen first-observed date and therefore does **not**
reset across a mint-then-rotate cycle.

**5.2** Update `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` §"Querying
Anthropic cost markers" to document three things:
- `days_since_first_dark` and its first-observed (non-resetting) semantics;
- the field-isolation requirement — a trustworthy producer row must match `"component":"claude-cost"`
  as well as the marker key, in **both** byte-forms, since the marker name alone is quotable in any
  issue/PR body that webhooks into the same source;
- **the absent-vs-zero trap:** because the field is omitted on `status:"ok"` rows,
  `JSONExtractInt(raw,'days_since_first_dark')` returns **0** for both "ok row, field absent" and a
  genuine day-0 key-missing row. Any panel or query must filter `status='key-missing'` *first*.

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-108** (`ADR-108-anthropic-cost-attribution-markers.md`), per Phase 5.1. No new ordinal is
claimed, so the ordinal-collision gate is not in play.

### C4 views
**No C4 impact.** Checked against all three of `model.c4`, `views.c4`, `spec.c4` — not a keyword grep.
Enumerated for this change: (a) **external human actors** — none added or changed; the operator is the
only human and their relationship to the platform is unchanged (this alters a notification severity,
not who receives what). (b) **External systems** — Anthropic (Admin API), Sentry, and Better Stack are
all already modelled as external systems with existing edges from the web-platform container; this
change adds no new vendor and no new edge, it changes the severity travelling an existing
web-platform→Sentry edge. (c) **Containers / data stores** — none added; no new persistence (the
dark-window age is computed from a constant, not stored). (d) **Actor↔surface access relationships** —
unchanged. No element description is falsified by this change.

## Observability

```yaml
liveness_signal:
  what: >-
    SOLEUR_CLAUDE_COST_DAILY row (status ok|key-missing, key-missing now
    carrying days_since_first_dark)
  cadence: daily, 17 6 * * * UTC
  alert_target: sentry_cron_monitor.scheduled_anthropic_cost_report (missed check-in)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: >-
    Sentry via warnSilentFallback (level=warning) for the benign key-missing
    branch; via reportSilentFallback (level=error) for 401/403, unchanged.
  fail_loud: true
failure_modes:
  - mode: admin key unprovisioned (benign, expected)
    detection: SOLEUR_CLAUDE_COST_DAILY {status:"key-missing", days_since_first_dark:N}
    alert_route: >-
      vector (Source 3 app_container_journald -> app_container_warn_filter
      level>=40 -> sinks.betterstack). Non-paging by design. Also visible via
      the pino Sentry breadcrumb mirror at level=warning.
  - mode: admin key invalid/revoked (401/403)
    detection: Sentry issue op=anthropic-admin-key-invalid, RED heartbeat
    alert_route: Sentry monitor (scheduled-anthropic-cost-report)
  - mode: transient 429/5xx/network
    detection: rethrow -> Inngest retry; RED heartbeat only on final attempt
    alert_route: Sentry monitor missed check-in
  - mode: producer did not run at all (no marker row of either status)
    detection: absence of a field-isolated SOLEUR_CLAUDE_COST_DAILY row in the window
    alert_route: >-
      Sentry monitor missed check-in; the follow-through probe treats this as
      TRANSIENT (exit 2), never PASS
  - mode: >-
      producer ran and emitted, but the shipping path dropped the row (Vector
      down, sink 4xx, token rotation, quota exhaustion)
    detection: >-
      divergence between the two transports — zero Better Stack producer rows
      while Sentry shows recent op=anthropic-admin-key-missing activity
    alert_route: >-
      Layer 2 (pino -> Sentry breadcrumb mirror, direct HTTPS) is the
      independent cross-check; the probe prints the divergence into its
      #6297 comment and emits STALLED: after 7 consecutive zero-row runs.
      NOTE: the Sentry cron monitor is GREEN in this mode (the check-in
      succeeded), so it is explicitly NOT the detector here.
logs:
  where: Better Stack Logs (ClickHouse remote t520508_..._logs, source 2457081), via Vector
  retention: 3 days (hot window, betterstack-log-query.md:85); quota 3 GB/mo
discoverability_test:
  # Single-line plain scalar, NOT a `>-` folded scalar. preflight Check 10's
  # Form A parser handles `command: <inline>` and `command: |` but NOT `>-`:
  # it strips the key and yields the literal `>-`, which then trips its own
  # shell-active-token reject (`>`) and FAILs the check without ever running
  # the probe. See #6772.
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 48h --grep SOLEUR_CLAUDE_COST_DAILY --limit 20
  expected_output: >-
    a row matching BOTH raw LIKE '%"SOLEUR_CLAUDE_COST_DAILY":true%' and
    '%"component":"claude-cost"%', carrying "status":"key-missing" and a
    "days_since_first_dark" integer (or "status":"ok" post-mint). The
    component field distinguishes a real producer row from a webhook echo of
    this plan's own prose.
```

Layer citations use the canonical vocabulary from
`plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`: **`vector`** (Layer 3)
for the marker, **`Sentry monitor`** for run liveness. Layer 2 (pino→Sentry breadcrumb) is
deliberately **not** available for the marker itself — `claude-cost-marker.ts` uses a dedicated pino
instance with no `mirrorToSentry` hook (ADR-108 Decision item 2). The `warnSilentFallback` line *does* route
through the shared logger and so retains Layer 2.

### Soak Follow-Through Enrollment

Required — the close criterion is time-gated on an external dependency. Deliverable is Phase 4:
script `scripts/followthroughs/anthropic-admin-key-6297.sh`, the `<!-- soleur:followthrough -->`
directive on #6297, and the `follow-through` label. **No new `secrets=` wiring is needed** — all three
`BETTERSTACK_QUERY_*` names are already in
`.github/workflows/scheduled-followthrough-sweeper.yml`'s `env:` block.

## Infrastructure (IaC)

### Terraform changes
**None. This PR must not touch any `.tf` file.**

This is a deliberate sequencing constraint, not an oversight. `apps/web-platform/infra/` is
auto-applied by `apply-web-platform-infra.yml` on any `infra/*.tf` merge, and Terraform resolves
**every** root variable before `-target` pruning. A no-default `ANTHROPIC_ADMIN_KEY` variable whose
`TF_VAR_anthropic_admin_key` is absent from `prd_terraform` (verified absent today) would therefore
fail the **entire** merge-triggered apply, not just its own resource — breaking unrelated
infrastructure. `hr-tf-variable-no-operator-mint-default` forbids giving it a default to dodge this.

Canonical decision: **ADR-065** (`ADR-065-operator-mint-tf-var-secret-before-iac-merge.md`) — the
operator-mint variable must be provisioned in `prd_terraform` *before* the IaC referencing it merges.
Worked precedent: `RESEND_RECEIVING_API_KEY` → split to #5480.

### Apply path
N/A for this PR (no infra surface). The IaC half is a **follow-up PR**, gated on the mint:
1. operator (or Playwright — see §Operator Action) mints the key in the Console;
2. `TF_VAR_anthropic_admin_key` lands in Doppler `prd_terraform` (and the runtime value in `prd` —
   see §Operator Action);
3. *then* a follow-up PR lands **three** things together, mirroring `inngest-betterstack-token.tf`:
   - the no-default sensitive `variable "anthropic_admin_key"` in `variables.tf`;
   - the `doppler_secret` resource writing `ANTHROPIC_ADMIN_KEY` into `soleur/prd`, with
     `lifecycle { ignore_changes = [value] }` so Terraform **adopts** the operator's hand-written
     value rather than fighting it;
   - **the matching `-target=` line in `apply-web-platform-infra.yml`.**

> **The `-target=` line is not optional and is the easiest of the three to forget.** ADR-065's
> Decision enumerates the IaC half as *"the `variable` + the `doppler_secret` + the
> `apply-web-platform-infra.yml` `-target` line"*, and that workflow's own ALLOW-LIST MAINTENANCE note
> states a new resource without a matching `-target=` entry is **never applied** — the merge is green,
> the apply is green, and the secret silently does not exist, with only the 12h
> `scheduled-terraform-drift.yml` cron as backstop. This is the declared-but-never-applied failure
> class the C4 model already records for the Sentry root. Recorded here because this plan is the
> handoff document for that follow-up.

**Answer to the plan question "can the IaC half be fully prepared in advance?"** — the resource *body*
can be written in advance, but it **must not merge** in advance, for the auto-apply reason above. So
the operator's single step really is "paste the minted key", but the paste target is Doppler
`prd_terraform`, and the IaC merge is the step that follows it. Preparing-and-not-merging buys
nothing here and risks an accidental merge breaking the whole apply, so the follow-up PR is filed but
left unopened until step 2 completes.

### Distinctness / drift safeguards
`dev` and `prd` remain distinct; no `dev` counterpart is provisioned (the cron is production-only).
Note ADR-108's standing caveat: `tfstate` will carry the admin key in cleartext once the IaC lands —
the R2 backend must stay encrypted and access-restricted, and exposure is a rotation trigger.

### Vendor-tier reality check
No new vendor and no new spend. The Admin Cost/Usage endpoints are included with the org; ADR-108
already recorded Finance as advisory with "creates no new vendor expense". No
`wg-record-recurring-vendor-expense-before-ready` obligation.

## Operator Action

**`automation-status: VERIFIED operator-only — but NOT for the reason this plan assumed.`**

> **/work ran the Playwright attempt. The result falsified this section's core premise.**
>
> ```
> playwright-attempt: navigated https://console.anthropic.com/settings/keys → redirected to
>   https://platform.claude.com/login?returnTo=%2Fsettings%2Fkeys; reached an unauthenticated
>   sign-in wall (Google OAuth consent / email-OTP / SSO). After the operator authenticated,
>   re-navigated as org "Jean's Individual Org" (role: Admin) and found:
>     - /settings/keys renders WORKSPACE keys only ("API keys are owned by workspaces"),
>       with no Admin key type in the create flow — so this plan's step 3 was wrong;
>     - /settings/admin-keys — the canonical path per the Anthropic docs — returns
>       "Page not found", and no "Admin keys" item exists in Console navigation;
>     - /settings/organization offers "Convert to team organization" → button "Convert to team".
>   Blocking gate: ACCOUNT TIER, not a human-interaction gate. Docs (Admin API overview):
>   "The Admin API is unavailable for individual accounts."
> ```
>
> **The key is not un-minted; it is un-mintable.** No amount of Playwright, credential
> hunting, or IaC resolves it — `/v1/organizations/cost_report` is simply not available to
> this account tier. The prerequisite is converting the individual org to a **team
> organization**, which carries seat/billing implications and is a *product/account* decision
> reserved for the operator (never an agent's call, and not an architecture fork for the CTO
> agent either). It is therefore left un-clicked.
>
> Consequence for sequencing: the mint is **not** a "3-minute paste" and may never happen at
> all if the operator judges a daily cost report not worth converting the account. That is a
> legitimate outcome — the D1 fix stands on its own, the surface is now positively dark and
> non-paging, and the probe reports TRANSIENT indefinitely rather than false-closing. The IaC
> follow-up in §Infrastructure stays unopened.
>
> The original conditional handoff text below is retained for the case where the operator
> **does** convert, but its steps 1–3 are corrected: the key is created at
> **Settings → Admin keys** (which appears only post-conversion), not at Settings → API keys,
> and Console Admin keys carry **no selectable scopes** — every key has full Admin-API access,
> so the "read-only" framing in ADR-108 describes intended use, not an enforced scope.

Verified: the Admin API has **no** key-creation endpoint (docs FAQ: *"new API keys can only be created
through the Claude Console for security reasons"*). That establishes there is no API path — it does
**not** establish that the Console UI is un-automatable. Per
`2026-06-10-playwright-attempt-evidence-before-operator-only.md` and the #5480 post-mortem, a vendor
dashboard action under an authenticated session is **presumptively Playwright-automatable** until a
real attempt reaches a *named* human gate (CAPTCHA / OTP / TOTP / passkey / push-MFA / payment-card /
hardware-token). #5480 is the cautionary case: the "no creation API — vendor limit" assertion was
itself the defect; a later Playwright attempt found a working "Create API key" form and no human gate.

/work must therefore attempt `console.anthropic.com` → Settings → API keys via Playwright and record a
`playwright-attempt:` evidence line (`navigated <URL>; reached <named gate>`) **before** anything is
written as an operator step. Only if a named gate is reached does the text below ship.

If (and only if) the attempt proves a human gate, #6297's body gets this, in plain language:

> **What you need to do (about 3 minutes):**
> 1. Go to **console.anthropic.com** and sign in as the organization owner.
> 2. Open **Settings → API keys**.
> 3. Click **Create key**. Choose the **Admin** key type. Name it `soleur-cost-report-readonly`.
> 4. Copy the key — it starts with `sk-ant-admin01-` and is shown **only once**.
> 5. Paste it into Doppler **twice — same key, two places**. Project `soleur` both times:
>    - config **`prd`**, name it `ANTHROPIC_ADMIN_KEY` — this is the one the daily report reads.
>    - config **`prd_terraform`**, name it `TF_VAR_ANTHROPIC_ADMIN_KEY` — this is the one the
>      infrastructure code reads.
>
>    Do not paste it into chat, a commit, or an issue comment.
> 6. Post a comment on this issue saying you've done it.
>
> That is your whole job. The report starts working within 24 hours and this issue closes itself.

**The two-config paste is load-bearing — an earlier draft of this plan got it wrong, and the error is
worth recording so /work does not re-introduce it.** `prd_terraform` supplies Terraform's *input
variable*; it does **not** put `ANTHROPIC_ADMIN_KEY` into the app container's environment. The cron
reads `process.env.ANTHROPIC_ADMIN_KEY`, sourced from Doppler config **`prd`**. The precedent states
the split explicitly — `resend.tf`: *"set as TF_VAR_resend_receiving_api_key in Doppler
prd_terraform; **this resource publishes it to the `prd` Doppler config** where the Next.js app reads
it at runtime"*. A `prd_terraform`-only paste therefore leaves the cron on its `key-missing` branch
**indefinitely**, the probe returning exit 2 forever — D2 reconstructed exactly, with the operator
told to expect a self-closure that cannot occur.

Having the operator write `prd` directly decouples the fix from the IaC follow-up. `ignore_changes =
[value]` on the `doppler_secret` (the precedent's own shape) means Terraform **adopts** the
hand-written value rather than fighting it, so there is no drift and no ordering hazard.

Full chain, with the actor for each link:

| # | Step | Actor |
|---|---|---|
| 1 | Mint the Admin key in the Console | operator (pending the Playwright attempt above) |
| 2a | Paste as `ANTHROPIC_ADMIN_KEY` into Doppler `soleur/prd` — **this is what makes the cron work** | operator |
| 2b | Paste as `TF_VAR_ANTHROPIC_ADMIN_KEY` into Doppler `soleur/prd_terraform` — Terraform's input | operator |
| 3 | Container picks up the new `prd` value on its next restart (any merge touching `apps/web-platform/**` triggers `web-platform-release.yml`) | automated |
| 4 | Next 06:17 UTC fire reads the key → `status:"ok"` marker | automated |
| 5 | Probe passes → #6297 auto-closes | automated |
| 6 | IaC follow-up PR lands `doppler_secret.anthropic_admin_key` (+ its `-target=` line), adopting the existing value | **agent/pipeline** — no longer on the critical path |

**Container env is a deploy-time snapshot.** `cloud-init.yml` runs `doppler secrets download --config
prd` into a tmp env-file consumed by `docker run --env-file`; there is no in-process Doppler client,
so a running container will not see the new secret until it restarts. If no deploy happens on its own,
step 3 can be forced by any merge to `apps/web-platform/**` — the IaC follow-up (step 6) is one such
merge, which is why the ordering is convenient but not required.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** A test asserting the key-missing path does **not** emit at error severity fails before
      the Phase 1.2 edit and passes after (failing-first evidence in the PR body).
- [ ] **AC2** `vi.mock("@/server/observability", …)` exports **both** `reportSilentFallback` and
      `warnSilentFallback`; no test errors with `TypeError: … is not a function`.
- [ ] **AC3** The key-missing test asserts the content anchor `daily cost report is dark`, not only
      the `op:` token.
- [ ] **AC4** The 401 and 403 tests assert `reportSilentFallback` was called with an `Error` and
      `op: "anthropic-admin-key-invalid"`, **and** that `warnSilentFallback` was not called.
- [ ] **AC5** No change to the schedule, concurrency, retry, or gating lines — **mechanical, not an
      eyeball**: the following prints nothing.
      ```bash
      git diff origin/main...HEAD -- apps/web-platform/server/inngest/functions/cron-anthropic-cost-report.ts \
        | grep -E '^[-+]' | grep -E '17 6 \* \* \*|concurrency|retries:|isFinalAttempt'
      ```
- [ ] **AC6** No file under the auto-applied infra root in the diff. **Scope to the whole
      `infra/` tree, not just `*.tf`** — `apply-web-platform-infra.yml`'s `paths:` filter is
      `apps/web-platform/infra/**`, which also covers ~20 `.sh`/`.service`/`.md` files, so a
      `.tf$`-only check would report clean while an `infra/*.sh` edit still triggers a full apply.
      **Use an `if`, not `grep -c`** — `grep -c` exits **1** on a zero count, inverting the gate:
      ```bash
      if git diff --name-only origin/main...HEAD | grep -qE '^apps/web-platform/infra/'; then
        echo "FAIL: auto-applied infra path in diff"; exit 1
      fi
      ```
- [ ] **AC7** `emitClaudeCostDailyMarker` is still called on the key-missing path with
      `status: "key-missing"` (pre-existing assertion at `cron-anthropic-cost-report.test.ts:135`;
      retained as a regression guard, not a new post-condition).
- [ ] **AC8** `daysSinceFirstDark` unit test: a pre-`FIRST_DARK_FIRE` date → `0`; `2026-07-20` → `10`.
      Tested by passing an explicit `Date` to the pure helper — no fake-timer seam needed.
- [ ] **AC9** The key-missing marker payload carries `days_since_first_dark` as a number, and the
      `status:"ok"` payload does **not** carry the field at all.
- [ ] **AC10** `bash -n scripts/followthroughs/anthropic-admin-key-6297.sh` exits 0, and the banned
      abort-on-unset form is absent from **executable** lines:
      ```bash
      if grep -vE '^\s*#' scripts/followthroughs/anthropic-admin-key-6297.sh \
         | grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?'; then
        echo 'FAIL: banned ${VAR:?} / ${VAR?} abort form present'; exit 1
      fi
      ```
      *Three corrections over the naive form, each verified at plan time.* (i) **Exit inversion** —
      `grep -c … ` returns exit 1 on a clean file, so the earlier "returns 0" phrasing passed the
      dirty script and failed the clean one. (ii) **Under-match** — `${VAR?msg}` (no colon) has
      identical abort-with-status-1 semantics and is invisible to a `:?` pattern; the `:?\?` form
      catches both. (iii) **Comment false-FAIL** — Phase 4.1 instructs the author to *document* the
      banned form, so comment lines are stripped first; this is not hypothetical, 5 existing probes
      match only inside such a comment. Fixtures: known-bad `ghcr-minter-live-6031.sh:28` matches;
      known-good `cert-reissue-markers-6698.sh` does not.
- [ ] **AC11** The probe contains `exit 2` on the still-`key-missing` path, the zero-producer-rows
      path, and the query/auth-failure path (positive-liveness requirement), and `exit 0` appears on
      exactly one path.
- [ ] **AC12 (P0 guard — echo isolation)** The probe's PASS condition is field-isolated and cannot be
      satisfied by a quoted string in an issue/PR body. The PASS branch requires **both**
      `SOLEUR_CLAUDE_COST_DAILY == true` **and** `component == "claude-cost"` as **decoded top-level
      keys** of the log line — not as substrings of the row. In the shipped probe that is the single
      `jq` predicate `select(.SOLEUR_CLAUDE_COST_DAILY == true and .component == "claude-cost")`.
      Negative control: running the probe against a window whose only matching rows are the webhook
      echo of this PR body must **not** exit 0.
      > **Amended during the AC walk (see DC-4).** This AC originally demanded the two *byte-forms*
      > of the literal `"component":"claude-cost"`. Review found substring matching defeatable by an
      > embedded newline, so the code moved to the structural form above and this text follows it.
      > Stated as a literal-substring criterion, this AC would now fail against a probe that is
      > strictly harder to fool — the AC would be certifying the weaker property.
- [ ] **AC13** The probe pins `--since 48h` (≤ the 3-day retention at `betterstack-log-query.md:85`).
- [ ] **AC14** `secrets=` in the #6297 directive names **all five** required secrets, and every one is
      present in the sweeper's `env:` block — scope the check to that block, not the whole file:
      ```bash
      awk '/^ *env:/{f=1;next} f&&/^ *[a-z-]+:$/{f=0} f' .github/workflows/scheduled-followthrough-sweeper.yml \
        | grep -cE '(BETTERSTACK_QUERY_(HOST|USERNAME|PASSWORD)|SENTRY_AUTH_TOKEN|GH_TOKEN):'   # expect 5
      ```
      **Do not shrink this to the Better Stack three.** `GH_TOKEN` makes the `STALLED:` counter
      computable (the probe is stateless under `env -i`) and `SENTRY_AUTH_TOKEN` makes the
      cross-transport check reachable. Omitting either leaves the corresponding Phase 4.1 mitigation
      silently dead while every other AC still passes.
- [ ] **AC14b** The two escalation mitigations are **reachable, not prose**: the probe contains a
      `gh issue view`-derived count of prior zero-row sweeper comments feeding a `STALLED:` branch,
      and a Sentry query branch guarded by `if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]`. Assert both
      branches exist and are exercised by a fixture.
- [ ] **AC14c** The `exit 1` branch is reachable: a fixture where the window contains a `"status":"ok"`
      row followed by a later `"status":"key-missing"` row makes the probe exit 1. Without this the
      sweeper's closed-set reopen path is structurally inert.
- [ ] **AC15** ADR-108 documents the `days_since_first_dark` field; **no** new ADR ordinal is created
      (`git diff --name-only origin/main...HEAD | grep -c 'decisions/ADR-' ` counts only ADR-108).
- [ ] **AC16** Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
      (Not `npm run -w …` — verified: the repo root `package.json` declares no `workspaces` field, so
      any `-w` form aborts with `No workspaces found`.)
- [ ] **AC17** Tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-anthropic-cost-report.test.ts`
      exits 0. (Verified: runner is vitest — `apps/web-platform/bunfig.toml:11` sets
      `pathIgnorePatterns = ["**"]`, so `bun test` matches nothing — and the path satisfies
      `vitest.config.ts:44`'s `test/**/*.test.ts` include glob.)
- [ ] **AC18** PR body uses `Ref #6297`, **not** `Closes #6297` — the issue's real close criterion is
      the post-mint probe passing, and auto-closing at merge would produce a false-resolved state.
- [ ] **AC19** Every knowledge-base citation in this plan resolves — **including bare filenames**,
      which the `knowledge-base/`-prefixed regex alone would miss:
      ```bash
      { grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan>;
        grep -oE '(ADR-[0-9]+|20[0-9]{2}-[0-9]{2}-[0-9]{2})-[A-Za-z0-9_.-]+\.md' <plan> \
          | while read -r f; do find knowledge-base -name "$f" | head -1; done | sed 's|^|FOUND:|'; } \
      | grep -v '^FOUND:' | sort -u | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'
      ```
      plus: every bare `*.md` filename cited resolves under `knowledge-base/` via `find`. *(Both
      bare citations in this plan — `ADR-065-…md` and `2026-06-10-playwright-attempt-…md` — were
      resolved manually at plan time; this AC makes the check mechanical for /work.)*

### Post-merge (automated — no operator step)

- [ ] **AC20** Within 24h of deploy, a field-isolated producer row carries `days_since_first_dark` —
      verify with the §Observability `discoverability_test` command.
- [ ] **AC21 (Sentry negative control)** No event at `level:error` with
      `op:anthropic-admin-key-missing` on a release at or after the fix.
      **Do not phrase this as "no *new issue* appears"** — Sentry fingerprints `captureMessage` on the
      message template, and Phase 1.2 deliberately keeps `message` and `op` unchanged, so post-fix
      events land on the **existing** issue `e0e6f356764b4bb6be8b0a8e74898e9f` and no new issue is
      minted whether the fix worked or not. Query by level+release, not by issue novelty.
- [ ] **AC22 (Sentry positive control)** The latest event on issue `e0e6f356764b4bb6be8b0a8e74898e9f`
      carries `level:warning` — pulled with
      `doppler run -p soleur -c prd -- scripts/sentry-issue.sh e0e6f356764b4bb6be8b0a8e74898e9f`
      (`hr-no-dashboard-eyeball-pull-data-yourself`).
      **This AC is load-bearing:** AC21 alone cannot distinguish "no longer at error level" from "no
      longer emitting at all", so without a positive control the AC set would pass if the branch went
      fully silent — the exact over-correction §User-Brand Impact (b) names as the failure to avoid.
- [ ] **AC23** #6297 carries `follow-through` + `priority/p2-medium`, and the next sweeper run posts a
      TRANSIENT (not FAIL, not PASS) comment while the key is still unprovisioned.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-anthropic-cost-report.ts` — import
  `warnSilentFallback`; swap the key-missing branch; add `FIRST_DARK_FIRE` and
  `daysSinceFirstDark()`; pass `days_since_first_dark`.
- `apps/web-platform/server/claude-cost-marker.ts` — add optional `days_since_first_dark?: number` to
  `ClaudeCostDailyMarker`.
- `apps/web-platform/test/server/inngest/cron-anthropic-cost-report.test.ts` — extend the mock
  factory; RED tests for Phase 1/2/3.
- `knowledge-base/engineering/architecture/decisions/ADR-108-anthropic-cost-attribution-markers.md` —
  amend `## Decision` + `## Consequences`.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — document
  `days_since_first_dark` and the `"component":"claude-cost"` field-isolation requirement in the
  existing Anthropic-cost-markers section.

## Files to Create

- `scripts/followthroughs/anthropic-admin-key-6297.sh` (mode 0775).

## Non-Goals / Out of Scope

- **Spend-vs-budget alerting** — still the other, deferred half of `Ref #5674`; unchanged by this plan
  and already tracked.
- **The `doppler_secret` IaC resource** — deliberately deferred to a post-mint follow-up PR (see
  §Infrastructure). Tracked by #6297 itself; no new deferral issue needed.
- **#3739** (`reportSilentFallbackWithUser` extraction) — acknowledged, not folded in.
- **Editing `infra/sentry/issue-alerts.tf`** — no rule matches this cron; the page is priority-derived.
- **Adding `ANTHROPIC_ADMIN_KEY` to `apps/web-platform/scripts/verify-required-secrets.sh`** —
  deliberately *not* done, and the IaC follow-up must not do it either. Verified: the key is absent
  from that script's `REQUIRED=(` list today, which is correct — "unprovisioned" is a **supported**
  state of this cron (the whole key-missing branch exists for it). Adding it would turn a benign
  optional-key state into a hard release-gate failure and block deploys until the mint. The release
  workflow runs this gate at `web-platform-release.yml:417`.
- **Retrofitting the existing probes that use the banned `${VAR:?}` form** — measured at plan time
  with AC10's own comment-stripping method: **14 of the 39** non-test scripts in
  `scripts/followthroughs/` carry the form `followthrough-convention.md:24` bans on an *executable*
  line, so an unprovisioned secret makes them report FAIL (exit 1) rather than TRANSIENT (exit 2),
  accreting daily false-FAIL comments. The convention is documented but enforced nowhere
  mechanically. Out of scope here (this plan only guarantees the *new* script is compliant, via
  AC10). Per `wg-when-an-audit-identifies-pre-existing`, /work should file a tracking issue proposing
  a CI guard — the exact comment-stripped grep from AC10, run over `scripts/followthroughs/*.sh`.

  > *Methodology note, recorded because it bit this plan:* a first pass reported "19 of 40" using the
  > naive grep. Applying AC10's own comment-stripping rule drops the numerator to 14 (5 files match
  > only inside a comment *documenting why not to use the form*), and the denominator is 39 non-test
  > files (42 including `.test.sh`). The AC10 correction and this measurement must use the same
  > method, or the plan's own guard disagrees with the plan's own prose.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Core change is a one-symbol severity swap backed by an existing, widely-used helper
(60 `warnSilentFallback` call sites, measured `git grep -n "warnSilentFallback(" -- apps/**/*.ts` minus the definition and tests; `email-on-received.ts:496` is the exact `warnSilentFallback(null, …)`
shape). The genuine engineering risk is not the swap but the two adjacent traps, both now pinned in
the plan: (1) the mock factory omission turning a clean assertion failure into a `TypeError`; (2) any
"fix" that lowers the pino line below level 40, which would silently stop the marker shipping to
Better Stack — the plan verified the Vector filter rather than assuming the pipeline. A third trap
surfaced at review and is now the plan's only P0-class item: the follow-through probe can PASS on the
webhook echo of this plan's own prose unless it field-isolates on `"component":"claude-cost"`
(Phase 4.1). The bounded-window escalation originally proposed as Phase 3 was **cut** at review — see
`decision-challenges.md`.

**Product/UX Gate:** not applicable — no path in `## Files to Edit` or `## Files to Create` matches the
UI-surface term list or glob superset (all paths are `server/`, `test/`, `scripts/`, `knowledge-base/`).
Product assessed NONE by the sweep, and the mechanical override did not fire.

**Finance:** not re-invoked. ADR-108 already recorded Finance as advisory for this surface and this
change creates no new vendor expense (no new key, no new tier, no new vendor).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A future edit "simplifies" all branches to warn, silently weakening the 401/403 fatal arm | AC4 asserts `warnSilentFallback` was **not** called on 401/403 — a negative assertion that fails loudly on that edit |
| Someone "fixes" noise later by dropping to `logger.info` or removing the Sentry mirror | ADR-108 amendment + the plan's Observability block record that level ≥ 40 is load-bearing for Vector's `app_container_warn_filter`; `cq-silent-fallback-must-mirror-to-sentry` covers the mirror |
| **Probe PASSes on the webhook echo of this plan's own prose and false-closes #6297 while the key is unminted** | **P0, caught at review.** `--grep` is an unanchored `raw LIKE`, and GitHub webhook bodies ship into the same Better Stack source. Phase 4.1 requires field isolation on `"component":"claude-cost"` (a pino base field no webhook carries); AC12 gates it with an explicit negative control |
| Probe false-closes #6297 on a query failure | Exit-2 TRANSIENT on auth/query failure, on missing `betterstack-query.sh`, **and** on zero producer rows (positive-liveness rule); exit 0 requires an affirmative field-isolated `"status":"ok"` row |
| Probe stalls TRANSIENT forever if the shipping path breaks while the cron stays green | Cross-check against the independent Layer-2 Sentry transport; `STALLED:` line after 7 consecutive zero-row runs (Phase 4.1) |
| A `.tf` file sneaks in and breaks the whole auto-applied root | AC6 — an `if … grep -q` form, deliberately **not** `grep -c` (which exits 1 on a zero count and would invert the gate) |
| `Closes #6297` auto-closes at merge, before the mint | AC18 mandates `Ref #6297` |
| Over-correction silences the branch entirely and the dark signal goes dark | AC22 is a Sentry **positive** control at `level:warning`; AC21 alone could not distinguish "not error" from "not emitting" |
| `days_since_first_dark` misread as "age of the current dark window" | Field and constant are both named for *first observed*, with the non-reset semantics documented at both the field (`claude-cost-marker.ts`) and the constant (`FIRST_DARK_FIRE`); nothing branches on the value, so a stale reading cannot page |

## Test Scenarios

1. Key unset → `warnSilentFallback` only; marker `{status:"key-missing", days_since_first_dark:N}`; heartbeat `ok:true`; no Admin API call; `reportSilentFallback` **not** called.
2. 401 → `reportSilentFallback` (`-invalid`), RED heartbeat, no marker, `warnSilentFallback` **not** called.
3. 403 → as (2). *(The existing 403 test currently asserts nothing about either spy — this adds real coverage.)*
4. 429 non-final → rethrow, no heartbeat, no marker.
5. 429 final → RED heartbeat.
6. Success → GREEN heartbeat, `{status:"ok"}` marker, **no** `days_since_first_dark` field, field-allowlist intact.
7. `daysSinceFirstDark` pure-function boundaries (pre-`FIRST_DARK_FIRE` → 0; 2026-07-20 → 10), driven by an explicit `Date` argument — no fake-timer seam required.
