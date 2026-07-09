---
title: "fix: bound the inngest cutover pre-flight scans so op=inventory/op=verify stop hanging (HTTP 000) — verify-close #6258"
issue: 6258
type: bug-fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_adrs: [ADR-105, ADR-100]
related_issues: [6178, 6230, 6265, 5509, 5523, 5553]
date: 2026-07-09
---

# fix: bound the inngest cutover pre-flight scans (op=inventory / op=verify) — verify-close #6258

## Deepen-Plan Findings (2026-07-09) — authoritative overrides

Five parallel review/research agents (architecture-strategist, spec-flow-analyzer, data-integrity-guardian,
observability-coverage-reviewer, + an implementation-mechanics research pass) reviewed this plan at the
single-user-incident threshold. Their load-bearing corrections **override** any earlier prose below that
conflicts:

1. **[P0 timeout math — sum bound, not ordering]** `deadline + per_page_max_time ≤ outer_curl` is the real
   invariant, NOT `per_page ≤ deadline < outer`. As first written, inventory `22 + 15 = 37 > 30` (df
   `50 + 15 = 65 > 60`) still 000s on the last page. **Fix:** clamp each page's curl to the *remaining*
   budget — `curl --max-time "$(( deadline_s - elapsed_s ))"` floored at 1 — so no page can overshoot.
   Capture the monotonic start (`date +%s` delta, precedent `ci-deploy.sh:1524-1535`; the repo never uses
   `SECONDS`) at `run_inventory` **entry, before `fetch_functions` (`:175`)**.
2. **[P0 op=verify DoD is unmeetable in scope — re-scope per-op]** op=verify's FIRST step is the
   registry-probe precondition which hard-requires `registry_empty == false` on the **dedicated host
   10.0.1.40** (`cutover-inngest.yml:628-631`). Pre-cutover that host is dark/empty → op=verify's JOB
   legitimately exits non-zero there and the doublefire sub-probe is **never reached**. So "op=verify job →
   HTTP 200" **cannot go green without running the cutover** (forbidden). See the re-scoped DoD + ACs below.
3. **[P0 completeness by construction, not fixture spot-check]** armed_reminders completeness is the
   single-user-incident guard. Guarantee it **by construction**: add a dedicated
   `eventNames:["reminder.scheduled"]` full-365-day query (the filter field is real and already used at
   `inngest-enumerate-reminders.sh:82`) — small, ceiling-immune, zero `receivedAt` narrowing. **Never narrow
   inventory `FROM_TS`.** Cost lever = **raise `PAGE_SIZE`** (lossless round-trip cut). Replace the single-
   fixture AC with a **differential test** (old-unbounded vs new-reduced projection on the same large corpus
   with a `reminder.scheduled` at each `receivedAt`-band boundary + a cron name appearing only past page 1).
4. **[P0 event_names feasibility must be exhibited]** The all-events distinct-name scan (needed for
   `event_names ⊇ current`) has **no cheap server-side distinct source** in v1.19.4 (`totalCount` gives a
   count, not names). Phase 0.5 MUST exhibit that the real corpus fits the budget at raised `PAGE_SIZE`
   (measured pages/latency); if not, raise the inventory deadline + outer curl budget (under the 30-min job
   cap) or reconsider the async-hook alternative. On deadline/ceiling the scan **aborts LOUD (`exit 1`,
   non-200)** — never a silent truncation.
5. **[P1 doublefire: bound by `functionIDs` + page ceiling, NOT a narrowed time window]** op=verify's
   missed-tick auto-enumeration (`cutover-inngest.yml:704-743`) diffs the probe's `runs` against the
   operator's cutover window; a probe window **narrower** than the operator window shows false "missed ticks"
   → operator re-fires → **double-fire** (the exact harm the cutover prevents). So keep the doublefire time
   window ⊇ the cutover window; cut cost via a `functionIDs` filter + page ceiling. The inventory "superset"
   invariant does NOT apply to doublefire — give it a **separate** invariant: "window ⊇ cutover-relevant
   period (`FROM ≤ cutover_instant − 2×max_cron_period`)".
6. **[P1 abort must be `exit 1`, never `break`, and must map to webhook non-200]** Route the ceiling +
   deadline + existing empty-`endCursor` (`:232-238`) exits through ONE shared loud-abort helper — a `break`
   would fall through to the emit and produce a truncated well-formed HTTP-200 body (false-clean, the #6218
   class). Add a workflow-test asserting the abort exit maps to a webhook **non-200** so the `CODE!=200`
   branch surfaces the real `SOLEUR_*_TIMEOUT` cause (not the 200-branch shape guard misattributing it).
   Off-by-one: gate the ceiling as "about to fetch page > MAX_PAGES while `hasNextPage=true`".
7. **[P1 blast radius is NOT preflight-only]** `inngest-inventory.sh` is also consumed by
   **`scheduled-inngest-health.yml:90`** (the 15-min durability probe), **op=execute** DI-C3 gate
   (`cutover-inngest.yml:565`), and **op=rollback** (`:807`). Add an AC that the health-probe path still
   returns 200 under the reduced scan. The completeness invariant protects the op=execute/op=rollback
   consumers too. Correct the IaC "blast radius" line accordingly.
8. **[P1 marker is journald-ONLY; START is the literal first line]** The hook's stdout **is** the pure-JSON
   webhook body — mirror only the FORMAT + control-char/Unicode-separator sanitizer of `marker()`
   (`git-lock-chardevice-sweep.sh:79-84`), **DROP its `echo`**; emit via `logger -t "$LOG_TAG" … 2>/dev/null || true`
   only. Emit `SOLEUR_INNGEST_PREFLIGHT_START` as the literal first line of `run_inventory`, before any
   network call, so absence-of-START unambiguously means transport/host-down.
9. **[P1 discriminator must split stall vs slow-scan]** `HTTP 000` is `curl` exit 28 (empty body), NOT a
   GraphQL `errors[]` envelope — so a `pool_hint` derived only from GraphQL error class reads `ok` for a
   pool-pressure *stall*, indistinguishable from a slow scan. Add a curl-exit/timeout field
   (`pages_timed_out=<n>` / `last_curl_exit=<28|0>`) and derive `pool_hint=pressure` ALSO from repeated
   curl-timeout. Note: a mid-scan `EMAXCONNSESSION` surfaces via the existing `.data` guard `exit 1` as
   `reason=gql_error`, so the PROGRESS `pool_hint=pressure` marker is largely unreachable — reconcile §3.
10. **[DROP the `/usr/bin/timeout` hooks.json wrapper]** The adnanh/webhook static-arg form is unverified
    (zero repo precedent); it only guards non-loop hangs (already `--max-time`-bounded), can fire mid-`logger`
    (losing the marker) or bypass the EXIT trap (leaking the `mktemp` spool), and widens blast radius. The
    in-script `date +%s`-delta deadline is sufficient + abandon-safe (it halts the loop that drives the PG
    load). Moved to rejected alternatives.
11. **[KEEP the bounded retry, tightly scoped]** Absorbs the deferred two-writer transient 500 (attempt-1 is
    now abandon-safe → releases connections → attempt-2 succeeds). Wrap ONLY the op=inventory / op=verify
    **transport** curls (000/500) — NOT the `registry_empty` precondition, NOT the op=execute DI-C3 gate
    (`:565`), NOT the health probe (`:83`, which has its own retry). Must land in the same PR as the bounding.
12. **[registry-probe is single-shot]** (`inngest-registry-probe.sh:48-90`, no loop) — needs no
    deadline/ceiling, only the START/DONE marker + `--connect-timeout`. Phase 0.3 resolved: no loop bound.
13. **[Purity test is the SOLE guard for connection strings]** Vector's `pii_scrub_string` does NOT scrub a
    `postgres://<user>:<pass>@<host>/db` URI. The purity test must assert no `://`, no `@…:…@`, and that raw
    GraphQL `errors[].message` never reaches a marker verbatim (map to an enum). Carry the line-injection
    sanitizer onto every interpolated marker field.
14. **[Stale `vector.toml` comment]** `vector-pii-scrub.test.sh` has NO tag-set assertion — the plan's new
    Phase-4 grep-assertion (in the `inngest-*.test.sh` files) is the actual allowlist drift guard; don't rely
    on a non-existent fixture.
15. **[ADR-106 cross-refs ADR-105 §Precondition]** rather than re-deriving the two-writer scoping;
    `amends: ADR-105` (both deployed + orthogonal — footprint vs duration). Mechanism wording: the ratchet is
    the loop *continuing to issue per-page queries after client abandonment*, not connections being "pinned".

## Overview

The Inngest dedicated-host cutover (#6178) is blocked by a pre-flight gate that no longer
works: `gh workflow run cutover-inngest.yml --field op=inventory` and `--field op=verify`
**hang past their curl budget and return `HTTP 000` (empty body)**, and earlier returned
`HTTP 500`. The previously-merged per-pool-cap + idle-drain fix (PR #6265 / ADR-105, deployed
prod ~14:14 UTC 2026-07-09) **bounded the connection *footprint* but not the scan *duration***,
so the hooks still hang — verified today with two fresh `op=inventory` runs (~15:11, ~15:2x UTC)
returning `HTTP 000` **even after a clean restart with the capped build deployed**.

**Root cause (three coupled defects on the pre-flight hook path — all confirmed in code):**

1. **Unbounded scan.** Every pre-flight hook script paginates a GraphQL cursor loop
   (`while :;`) to exhaustion with **no page ceiling and no total wall-clock budget**:
   - `inngest-inventory.sh:210` — `eventsV2` over a **365-day** window with
     `includeInternalEvents:true` (paginates every `cron.*` internal tick — the dominant cost),
     `PAGE_SIZE=50`, per-page `curl --max-time 15` (`:109`).
   - `inngest-doublefire-probe.sh:109` — `runs` over a **365-day / all-function** history,
     `PAGE_SIZE=100`, per-page `curl --max-time 15` (`:97`); the hook passes **no**
     `INNGEST_DOUBLEFIRE_FROM/UNTIL/FUNCTION_IDS`, so it always does the full scan.
   - `inngest-registry-probe.sh:55` — per-page `curl --max-time 15` (bounding to confirm at Phase 0).
   N pages × up to 15s each exceeds the outer curl budget (inventory 30s `cutover-inngest.yml:341`;
   verify = registry-probe 30s `:616` + doublefire 60s `:673`).

2. **No server-side kill + orphaned scan ratchets the pool.** adnanh/webhook **v2.8.2 has no
   `command-timeout`** and `hooks.json.tmpl` sets none (`webhook.service:13`). When the outer curl
   times out (→ `HTTP 000`), the hook script **keeps scanning server-side, orphaned**, still
   holding its inngest→Postgres connections. Those pinned connections — combined with the
   two-writer idle plateau — push the shared 30-slot pool to `EMAXCONNSESSION`, which is why the
   *next* run returns `HTTP 500`, a restart clears it, and the cycle repeats.

3. **The surface is observability-dark on the failure path.** The only telemetry
   (`logger -t inngest-inventory`, `inngest-inventory.sh:275`) fires **only on the success path**,
   at the *end* of `run_inventory`. A hang never reaches it, and the error-path loggers fire only
   on malformed GraphQL — **not** on the timeout. So a hang emits nothing (the reported "0 hits over
   40m"). This makes every occurrence undiagnosable from telemetry (`hr-observability-as-plan-quality-gate`).

**The fix (pre-flight tooling only — NO cutover execution):** bound each pre-flight scan with a
total wall-clock deadline + a page ceiling that is **abandon-safe** (on deadline/ceiling it emits a
LOUD `SOLEUR_*` marker and exits non-zero, releasing connections instead of orphaning the scan);
reduce the inventory/doublefire scan cost so the real corpus completes within budget **without
dropping any armed reminder or event name** from the baseline; align the timeout hierarchy
(in-script deadline < outer curl); and add a monitored `SOLEUR_INNGEST_PREFLIGHT_*` marker on the
START and TIMEOUT/abort paths so the next occurrence self-reports off-box to Better Stack.

**Definition of done (re-scoped per-op — see Deepen Finding 2):** the pre-flight scan **hooks** return
`HTTP 200` (well-formed body) at the transport layer under probe load — no hang, no orphan-scan-driven
`EMAXCONNSESSION`. Concretely: (a) **`op=inventory`** (web-host loopback scan — the direct #6258 subject)
returns `HTTP 200` with a well-formed body, verified by the operator's exact reproduction; (b) the
**op=verify sub-probe scans** (`inngest-registry-probe`, `inngest-doublefire-probe`) are transport-bounded
and observable, verified by unit tests + the shared bounding mechanism proven on op=inventory — the op=verify
**JOB** verdict legitimately halts at its `registry_empty` precondition pre-cutover (a verdict, not a
transport hang) and a green op=verify job is a **post-#6178** concern, out of scope. A `SOLEUR_*` marker
exists on the inventory/verify path and is queryable in Better Stack. #6258 verify-closes on (a) + the marker
evidence + unit-test proof of (b).

### HARD scope guard (carried verbatim from the task)

This fixes the **PRE-FLIGHT TOOLING ONLY**. Do **NOT** run the cutover: no `op=execute`, no Doppler
flip-arm (`INNGEST_CUTOVER_FLIP`), no app-repoint — those are the #6178 execution, **HELD** pending an
operator maintenance window. Do **NOT** close or modify #6178. Do **NOT** touch #6230 (the mandatory
web-2 quiesce — remains a required manual cutover step). Verification uses only the two **read-only**
ops `op=inventory` and `op=verify`.

## Research Reconciliation — Spec vs. Codebase

| Task premise / claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "The per-pool-cap fix is INSUFFICIENT; #6258 not resolved." | Confirmed. ADR-105 (`:145-149`, `:109-139`) bounds the connection **footprint**; it explicitly does **not** bound scan **duration/cost**. The HTTP 000 hang is a distinct, uncovered failure mode. | Address the duration/cost + server-timeout + observability gaps ADR-105 left. Amend it via ADR-106. |
| "The heavy scan behind `GET /hooks/inngest-inventory` hangs past 30s." | Confirmed: `inngest-inventory.sh` unbounded `while :;` (`:210`), per-page `--max-time 15` (`:109`), outer `--max-time 30` (`cutover-inngest.yml:341`). | Bound the loop (deadline + page ceiling) + reduce cost + align timeouts. |
| "Ensure the per-pool cap actually applies to the inventory/verify path, drain stuck sessions." | The cap already applies (all pools honour `--postgres-max-open-conns 5`). The residual `HTTP 500` is **topological** — two co-located writers (web-1 `10.0.1.10` + web-2 `10.0.1.11`) share one 30-slot pool (ADR-105 §Precondition, `:109-139`). No cap/sizing tweak makes two writers fit; the durable fix is #6178, the manual gate is #6230 — **both out of scope**. | Do NOT re-size the pool. Break the *orphan-scan ratchet* (abandon-safety) so a timed-out scan releases connections, removing the tooling-induced contribution to `EMAXCONNSESSION`. The bounded scan + existing idle-drain restore enough headroom for `op=inventory`/`op=verify` to return 200 on the two-writer set; the ultimate single-writer guarantee is #6178. |
| "op=verify hangs on the inventory path." | op=verify does **not** call `/hooks/inngest-inventory`. It calls `inngest-registry-probe` (`:616`, `--max-time 30`) **then** `inngest-doublefire-probe` (`:673`, `--max-time 60`). Both are unbounded scans on their own hooks. | Bound **all three** pre-flight scripts, not just inventory. |
| "Add a SOLEUR_* stdout marker." | The hook's **stdout is the pure-JSON response body** the workflow jq-parses (#5503) — it cannot carry a marker. The off-box carrier is `logger -t <tag>` → journald → Vector → Better Stack. Tags `inngest-inventory`/`inngest-doublefire-probe`/`inngest-registry-probe` are **already** in the `vector.toml` `host_scripts_journald` allowlist (`vector.toml:134` + siblings); Vector runs on the co-located web host (`inngest-bootstrap.sh:654-655`). | Emit the `SOLEUR_*` marker via `logger -t <existing-allowlisted-tag>` (message body carries the marker, mirroring `SOLEUR_CHARDEV_SWEEP_*`). **No `vector.toml` allowlist edit needed** — but AC greps to confirm the tags are present, and Phase 0 verifies Vector actually ships from the web host. |

**Premise Validation (Phase 0.6):** #6258 OPEN (verified), #6178 OPEN (unchanged), #6230 OPEN (unchanged).
Cited artifacts all exist on this branch: `inngest-inventory.sh`, `inngest-doublefire-probe.sh`,
`inngest-registry-probe.sh`, `cutover-inngest.yml`, `hooks.json.tmpl`, `vector.toml`, ADR-105. The
proposed mechanism (bound scan cost + hook timeout + in-surface marker) is **not** in ADR-105's
rejected-alternatives table — ADR-105 rejected only pool-sizing alternatives; scan-duration bounding is
a genuine gap it left. No stale premise.

## User-Brand Impact

**If this lands broken, the user experiences:** the #6178 cutover stays blocked (no *direct* user
regression) — OR, worse, a cost-reduction that narrows the inventory window drops a far-future armed
`reminder.scheduled` from the baseline, the eventual cutover before/after diff goes **false-clean**,
and a scheduled reminder is **silently lost at the real cutover** (an irreversible per-user brand hit).

**If this leaks, the user's data is exposed via:** a marker or error body that prints reminder
payloads, actor identity, or the Postgres/Redis connection string. Mitigated by #5503 purity — markers
and errors carry ENUMs / counts / `reminder_id`s only, never bodies, actors, or URIs (enforced by the
existing per-script tests + an AC below).

**Brand-survival threshold:** single-user incident. The load-bearing guard is the **inventory
completeness invariant** — the bounded/cost-reduced scan MUST NOT drop any armed reminder or distinct
event name that the current unbounded scan would capture. This is the vector the threshold protects; it
is enforced by AC "completeness parity" below. `requires_cpo_signoff: true` — CPO signs off on the
approach at plan time; `user-impact-reviewer` runs at review.

## Implementation Phases

### Phase 0 — Reproduce + measure (diagnosis-first; no mutation)

Per learnings `2026-05-31-diagnose-then-fix...` and `2026-06-30-verify-the-fixed-code-path-actually-executes...`:

0.1 Re-run the operator's exact reproduction and capture the failure shape:
`gh workflow run cutover-inngest.yml --field op=inventory` and `--field op=verify`; read the run logs
(`gh run view <id> --log | grep -E '::error::|::notice::'`) and record the exact `HTTP <code>` per op.
0.2 Read the **live** inngest-attributable pool via the read-only Management-API query (runbook
`inngest-server.md:119-125`) at rest and during a scan — record whether the failure is a 000 (hang) or a
500 (EMAXCONNSESSION), and the inngest connection count. This distinguishes the scan-duration defect from
the two-writer topology.
0.3 **Resolved** (Deepen): `inngest-registry-probe.sh` is single-shot (`:48-90`, no loop) → marker +
`--connect-timeout` only, no deadline/ceiling. (Re-confirm at /work with a grep for a pagination loop.)
0.4 Confirm Vector actually ships from the web host: `scripts/betterstack-query.sh --grep 'inngest' --since 2h`
plus confirm `vector.service` is enabled on the co-located host (`inngest-bootstrap.sh:654-655`). This
resolves the "0 hits" cause: either the success-path logger never fires (the hang) or Vector is dark.
Do NOT assert "Vector ships from web-host" without this check (`hr-verify-repo-capability-claim-before-assert`).
0.5 **Feasibility exhibit (load-bearing — Deepen Finding 4).** Locally capture the `eventsV2`/`runs` GraphQL
cost against the pinned `inngest/inngest:v1.19.4` harness to measure pages-per-corpus and per-page latency
(no SSH). This MUST demonstrate a concrete lever that fits the budget AND preserves `event_names` — i.e. the
all-events distinct-name scan completes within the inventory deadline at the raised `PAGE_SIZE`. If it does
NOT fit, escalate per Finding 4: raise the inventory deadline + outer curl budget (under the 30-min job cap),
or reconsider the async-hook alternative. Do not proceed to /work on an unexhibited mechanism.

### Phase 1 — Bound + reduce every pre-flight scan (abandon-safe)

Write failing tests first (`cq-write-failing-tests-before`). `inngest-registry-probe.sh` is **single-shot**
(no loop — resolved) → it gets only 1.5 marker + 1.4 `--connect-timeout`, NOT the deadline/ceiling of 1.1/1.2.
Apply 1.1–1.4 to the paginated scripts (`inngest-inventory.sh`, `inngest-doublefire-probe.sh`):

1.1 **Total wall-clock deadline (sum-bounded — Deepen Finding 1).** Capture a monotonic start via `date +%s`
delta (precedent `ci-deploy.sh:1524-1535`; the repo never uses `SECONDS`) at `run_inventory`/`run_probe`
**entry, before the pre-loop `fetch_functions`** (`inngest-inventory.sh:175`). The invariant is
`in_script_deadline + per_page_budget ≤ outer_curl` — an ordering is insufficient. **Clamp each page's curl
to the remaining budget:** `curl --max-time "$(( DEADLINE_S - elapsed ))"` (floored ≥1) so no in-flight page
can overshoot the outer curl. On `elapsed ≥ DEADLINE_S`, route through the shared loud-abort helper (1.3a).
`PREFLIGHT_DEADLINE_S` is an env test seam; default inventory `22`, doublefire `50` (both < the outer curl
after the remaining-budget clamp).
1.2 **Page ceiling.** `MAX_PAGES` env-overridable; gate as "about to fetch page > MAX_PAGES **while
`hasNextPage=true`**" (so a corpus that exactly fits breaks clean, never false-aborts). On exceed → shared
loud-abort helper, `reason=page_ceiling`. Sized from Phase 0.5 with headroom for the real corpus.
1.3 **Cost reduction — completeness by CONSTRUCTION (Deepen Findings 3–5).**
   - **armed_reminders (the single-user-incident guard) — lossless by construction.** Add a **dedicated
     second query** `eventNames:["reminder.scheduled"]` over the full 365-day window (the filter field is
     real; precedent `inngest-enumerate-reminders.sh:82`). This is small, ceiling-immune, zero `receivedAt`
     narrowing. **Do NOT narrow inventory `FROM_TS` (`inngest-inventory.sh:60-65`) — strike window-narrowing
     as a lever entirely.**
   - **event_names — cost lever is `PAGE_SIZE` only (lossless).** Keep the all-events distinct-name scan;
     raise `PAGE_SIZE` (`:59`, 50 → e.g. 500) to cut round-trips. There is NO cheap server-side distinct
     source (v1.19.4 `totalCount` is a count, not names), so if the corpus does not fit even at raised
     `PAGE_SIZE`, the scan **aborts LOUD** (1.3a) — never truncates. Phase 0.5 must exhibit feasibility.
   - **doublefire — bound by `functionIDs` + page ceiling, NOT a narrowed time window (Finding 5).** Narrowing
     `INNGEST_DOUBLEFIRE_FROM/UNTIL` below the operator's cutover window feeds false "missed ticks" into the
     enumeration at `cutover-inngest.yml:704-743` → operator re-fire → double-fire. Keep the window ⊇ the
     cutover window (`FROM ≤ cutover_instant − 2×max_cron_period`); cut cost via `functionIDs` + page ceiling.
   - **Inventory invariant (AC):** reduced `functions`/`event_names`/`armed_reminders` ⊇ current, proven by a
     **differential test** (old-unbounded vs new-reduced projection on the SAME large corpus — reminder at
     each `receivedAt`-band boundary + a cron name appearing only past page 1), NOT a single hand-built
     fixture. **doublefire invariant (separate AC):** the probe window ⊇ the cutover-relevant window.
1.3a **Shared loud-abort helper.** Route the deadline exit, the ceiling exit, AND the existing empty-
`endCursor` guard (`inngest-inventory.sh:232-238`, `inngest-doublefire-probe.sh:130-135`) through ONE helper
that emits the `SOLEUR_*_TIMEOUT` marker (Phase 3) + `exit 1` (**never `break`** — a `break` falls through to
the emit and produces a truncated well-formed HTTP-200 body = the #6218 false-clean class). The exit must map
to a webhook **non-200** (verified in Phase 4). The EXIT trap (`:209`) fires on `exit 1` → spool cleaned.
1.4 Add `--connect-timeout` to every per-page curl (bound TCP-connect stalls) — including registry-probe.

### Phase 2 — Timeout hierarchy + bounded retry (NO server-side wrapper)

2.1 **Sum-bounded hierarchy (Deepen Finding 1).** The invariant is
`in_script_deadline + per_page_budget ≤ outer_curl`, enforced by the remaining-budget per-page clamp in 1.1,
NOT the mere ordering `per_page ≤ deadline < outer`. End-to-end:
`per-page curl (--max-time = remaining, --connect-timeout N)` → `in-script deadline (22s inv / 50s df)` →
`outer curl (30s inv / 60s df)` → `job timeout-minutes 30`. A Phase-4 test asserts the sum bound, not the
ordering.
2.2 **NO `/usr/bin/timeout` hooks.json wrapper (Deepen Finding 10 — dropped).** The in-script deadline is the
sole server-side bound; it is sufficient + abandon-safe because it halts the loop that *drives* the PG load.
A `timeout` wrapper only guards non-loop hangs (already `--max-time`-bounded), and its SIGTERM can fire
mid-`logger` (losing the marker) or bypass the EXIT trap (leaking the `mktemp` spool), while widening blast
radius (inngest-inventory is also the health-probe endpoint). The adnanh/webhook static-arg form is
unverified anyway. See rejected alternatives.
2.3 **Bounded outer retry (KEEP — tightly scoped, Deepen Finding 11).** In `cutover-inngest.yml`, wrap ONLY
the op=inventory curl and the op=verify **transport** curls in one bounded retry-with-backoff (e.g. 2
attempts, 5s gap) — it absorbs the deferred two-writer transient 500 (attempt-1 is now abandon-safe →
releases connections → attempt-2 succeeds). Wrap ONLY the transport failure (000/500), **never** the
`registry_empty` precondition, the op=execute DI-C3 gate (`:565`), or the health probe (`:83`, has its own
retry). Fail-closed if both attempts fail. Must land in the same PR as the bounding (retrying a
non-abandon-safe hook stacks orphaned scans).

### Phase 3 — Observability marker (MANDATORY)

Add a structured `SOLEUR_INNGEST_PREFLIGHT_*` marker emitted **journald-only** via
`logger -t "$LOG_TAG" "<line>" 2>/dev/null || true` (tag = the script's existing `LOG_TAG`: `inngest-inventory`
/ `inngest-doublefire-probe` / `inngest-registry-probe`, all already in `vector.toml:134`/`:144`/`:145`).
Mirror the FORMAT + the control-char/Unicode-separator sanitizer of `marker()`
(`git-lock-chardevice-sweep.sh:81-82`: `LC_ALL=C tr -d '\000-\037\177'` + strip U+0085/U+2028/U+2029 on every
interpolated field) but **DROP its `echo`** — the hook's stdout IS the pure-JSON webhook body (#5503); an
`echo` corrupts the parse (Deepen Finding 8). Emit at:

- **START — literal FIRST line of `run_inventory`/`run_probe`, before `fetch_functions` and any network call**
  (Finding 8, so absence-of-START = transport/host-down unambiguously):
  `SOLEUR_INNGEST_PREFLIGHT_START op=<inventory|verify-registry|verify-doublefire> host=<id> window=<from..until> page_ceiling=<N> deadline_s=<D>`
- **DONE / TIMEOUT** — `SOLEUR_INNGEST_PREFLIGHT_DONE pages=<n> elapsed_ms=<e>` on success, or
  `SOLEUR_INNGEST_PREFLIGHT_TIMEOUT pages=<n> elapsed_ms=<e> pages_timed_out=<t> last_curl_exit=<28|0> reason=<deadline|page_ceiling|gql_error>`.

**Blind-surface discriminator (Phase 2.9.2 — Deepen Finding 9).** `HTTP 000` is `curl` exit 28 (a stall with
an EMPTY body), NOT a GraphQL `errors[]` envelope — so a `pool_hint` derived only from GraphQL error class
reads `ok` for a pressure *stall*, indistinguishable from a slow scan. The marker therefore carries a
**curl-exit/timeout class** (`pages_timed_out`, `last_curl_exit`) so `{deadline_hit, pages_scanned,
pages_timed_out, last_curl_exit}` splits the three hypotheses in ONE event: slow-scan (`last_curl_exit=0`,
progressing `pages_scanned`), pool-pressure-stall (`last_curl_exit=28`/repeated timeouts), and host-unreachable
(absence of any START marker for that run). Note: a mid-scan `EMAXCONNSESSION` surfaces via the existing
`.data` guard `exit 1` as `reason=gql_error` (a PROGRESS `pool_hint=pressure` marker is largely unreachable —
the loop `exit 1`s on the first error envelope; do NOT rely on a mid-loop pressure marker). Purity (Finding 13
— the purity test is the SOLE guard; Vector does not scrub `postgres://` URIs): enum/count/id only; assert no
`://`, no `@…:…@`, and that raw GraphQL `errors[].message` never reaches a marker verbatim (map to an enum).

### Phase 4 — Tests (RED→GREEN)

Extend `inngest-inventory.test.sh`, `inngest-doublefire-probe.test.sh`, `inngest-registry-probe.test.sh`,
and `cutover-inngest-workflow.test.sh`:
- deadline hit → `exit 1` (NOT `break`) + `SOLEUR_*_TIMEOUT` marker + well-formed one-line error body, AND a
  positive assertion that stdout does NOT `jq -e '.armed_reminders'`-parse (no truncated `{...}` object);
- page-ceiling hit → same (both abort paths assert non-JSON stdout);
- **completeness — differential test (Deepen Finding 3):** run the old-unbounded projection and the
  new-reduced projection against the SAME large corpus (a `reminder.scheduled` at each `receivedAt`-band
  boundary + a cron name appearing only past page 1) and assert reduced `functions`/`event_names`/
  `armed_reminders` ⊇ old — NOT a single hand-built fixture. Assert `FROM_TS` + `reminder.scheduled`
  inclusion are byte-identical to the current scan (the single-user-incident invariant, by construction);
- **doublefire separate invariant:** the probe window ⊇ the operator cutover window (`FROM ≤ instant − 2×max_cron_period`);
- purity (Finding 13) — no `://`, no `@…:…@`, no actor/body; GraphQL `errors[].message` mapped to an enum, never verbatim;
- **sum-bounded timeout** (Finding 1) — assert `deadline + per_page_budget ≤ outer` (via the remaining-budget clamp), not the mere ordering;
- **abort → webhook non-200** (Finding 6) — workflow-test that a deadline/ceiling abort surfaces via the
  `CODE!=200` cause-branch (the real `SOLEUR_*_TIMEOUT` text), NOT the 200-branch shape guard; verify the
  `include-command-output-in-response-on-error` exit-code→HTTP mapping empirically;
- marker tags are exactly the three already in `vector.toml` allowlist (grep assertion — this IS the drift
  guard; `vector-pii-scrub.test.sh` has none, Finding 14);
- START-marker-first — a functions-query failure still emits a START marker (Finding 8).

### Phase 5 — ADR-106 + runbook + verify-close

5.1 Author `ADR-106` (amends ADR-105) — see §Architecture Decision.
5.2 Update `knowledge-base/engineering/operations/runbooks/inngest-server.md` §"Session-pool pressure /
exhaustion" and §"Dedicated-host cutover": add the pre-flight-hang triage — the `SOLEUR_INNGEST_PREFLIGHT_*`
Better Stack query, that a fast LOUD error ≠ a hang, and that a bounded scan releases connections.
5.3 **Post-merge verify-close (automated, in /ship — NOT operator handoff):** after
`apply-deploy-pipeline-fix.yml` auto-applies, re-run `op=inventory` + `op=verify`, confirm both `HTTP 200`
with well-formed bodies, and query the `SOLEUR_INNGEST_PREFLIGHT_START` marker in Better Stack to prove the
path is now observable. Then `gh issue close 6258` with the evidence. (`Ref #6258` in the PR body, closed in
the post-apply step — NOT `Closes #6258`, per the ops-remediation `Ref` convention: the fix only takes
effect after the auto-apply runs.)

## Files to Edit

- `apps/web-platform/infra/inngest-inventory.sh` — deadline + page ceiling + completeness-preserving cost reduction + `SOLEUR_*` markers (abandon-safe). *(auto-deploys: `apply-deploy-pipeline-fix.yml:89`)*
- `apps/web-platform/infra/inngest-doublefire-probe.sh` — deadline + page ceiling + bounded FROM/UNTIL default + markers. *(`:96`)*
- `apps/web-platform/infra/inngest-registry-probe.sh` — single-shot (resolved): START/DONE marker + `--connect-timeout` only, NO deadline/ceiling. *(`:95`)*
- `.github/workflows/cutover-inngest.yml` — bounded retry on op=inventory + op=verify **transport** curls only (not the `registry_empty` precondition, not the DI-C3 gate `:565`, not the health probe); confirm the sum-bounded timeout.
- `hooks.json.tmpl` is **NOT edited** — the `/usr/bin/timeout` wrapper is dropped (Deepen Finding 10). No new host script; the three script edits already ride `apply-deploy-pipeline-fix.yml`'s existing `paths:`.
- `apps/web-platform/infra/inngest-inventory.test.sh` — deadline/ceiling/marker/completeness/purity.
- `apps/web-platform/infra/inngest-doublefire-probe.test.sh` — same.
- `apps/web-platform/infra/inngest-registry-probe.test.sh` — same.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — timeout-hierarchy + retry assertions.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — pre-flight-hang triage.

**Design constraint — no new host script.** Prefer in-place edits to the existing three scripts (a new
`/usr/local/bin/*.sh` would have to be registered in `infra-config-apply.sh` TRIGGER_FILES +
`push-infra-config.sh` + the `apply-deploy-pipeline-fix.yml` paths + the `ship-deploy-pipeline-fix-gate.test.ts`
parity test — four sites). The deadline/marker logic is ~15 lines of bash per script; keep it in-file.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-106-inngest-cutover-preflight-scan-bounding-and-in-surface-marker.md`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] The two **paginated** pre-flight scripts enforce a wall-clock **deadline** + **page ceiling** via a
      shared loud-abort helper that `exit 1`s (never `break`s) and emits `SOLEUR_INNGEST_PREFLIGHT_TIMEOUT`;
      stdout on abort is NOT a `jq -e '.armed_reminders'`-parseable object — **no orphan, no truncated JSON**.
      `inngest-registry-probe.sh` (single-shot) gets only the marker + `--connect-timeout`, no deadline/ceiling.
- [ ] **Completeness (inventory) — differential proof by construction:** the reduced scan's `functions` /
      `event_names` / `armed_reminders` ⊇ the current scan's on a large corpus (differential test, not a single
      fixture); `FROM_TS` + `reminder.scheduled` inclusion byte-identical; armed set enumerated via a dedicated
      `eventNames:["reminder.scheduled"]` full-365-day query (no window narrowing). **doublefire** (separate):
      probe window ⊇ operator cutover window.
- [ ] **Sum-bounded timeout:** `in-script deadline + per-page budget ≤ outer --max-time` via a remaining-budget
      per-page clamp (`--max-time = DEADLINE_S − elapsed`), NOT the mere ordering (workflow + script tests).
- [ ] **Abort → webhook non-200:** a deadline/ceiling abort maps to a webhook non-200 so the workflow's
      `CODE!=200` branch surfaces the real `SOLEUR_*_TIMEOUT` cause (empirically verified exit-code→HTTP mapping).
- [ ] **Co-consumer safety (Finding 7):** the `inngest-inventory.sh` change is safe for `scheduled-inngest-health.yml`
      (still returns 200 on the reduced scan; no new advisory-issue storm), the op=execute DI-C3 gate, and op=rollback
      — protected by the completeness invariant + abandon-safety.
- [ ] Markers are journald-ONLY (no `echo` to stdout); success-path stdout stays well-formed JSON while the
      `SOLEUR_*` marker appears in journald (test); `--connect-timeout` present on every per-page curl incl. registry-probe.
- [ ] `SOLEUR_INNGEST_PREFLIGHT_{START,DONE,TIMEOUT}` emitted via `logger -t <tag>` where `<tag>` ∈
      {`inngest-inventory`,`inngest-doublefire-probe`,`inngest-registry-probe`}, each **verified present** in
      `vector.toml` `host_scripts_journald` allowlist (grep assertion) — no allowlist edit required.
- [ ] Purity: no reminder body, actor, or connection string in any marker or error path (reuse #5503 purity tests).
- [ ] All `inngest-*.test.sh` + `cutover-inngest-workflow.test.sh` green; `apps/web-platform/infra/*.sh`
      pass shellcheck; `ship-deploy-pipeline-fix-gate.test.ts` still green (TRIGGER_FILES unchanged — no new script).
- [ ] `ADR-106` created (amends ADR-105); runbook pre-flight-hang triage added.
- [ ] PR body says `Ref #6258` (NOT `Closes`) — ops-remediation convention; issue closes post-apply.

### Post-merge (automated in /ship — no operator step)

- [ ] `apply-deploy-pipeline-fix.yml` auto-applies the four edited files (no-SSH infra-config push).
- [ ] Re-run `gh workflow run cutover-inngest.yml --field op=inventory` → **HTTP 200**, well-formed
      `{functions,event_names,armed_reminders,durability_state}` body (the primary #6258 verify-close signal).
- [ ] Re-run `gh workflow run cutover-inngest.yml --field op=verify` → the **registry-probe sub-probe returns
      HTTP 200 at the transport layer** (dark host reachable + well-formed array); the JOB may legitimately
      exit non-zero at the `registry_empty` precondition (a verdict, NOT a transport hang/500). The doublefire
      sub-probe's transport bounding is proven by **unit tests** pre-cutover (it is only reached post-repoint).
      Do NOT gate verify-close on a green op=verify JOB (that is post-#6178). Assert: NO `HTTP 000` and NO
      `HTTP 500` on any op=verify sub-probe transport.
- [ ] The 15-min durability health probe (`scheduled-inngest-health.yml`, a co-consumer of
      `inngest-inventory.sh`) still returns HTTP 200 post-deploy (no new `[ci/inngest-pool]`/`inngest_down`
      advisory storm from the bounded scan).
- [ ] `scripts/betterstack-query.sh --grep 'SOLEUR_INNGEST_PREFLIGHT' --since 1h` returns ≥1 START marker per
      run — the surface is now observable off-box.
- [ ] `gh issue close 6258` with the op=inventory green run URL, the op=verify sub-probe transport evidence,
      the unit-test proof for the doublefire bounding, and the Better Stack marker evidence.

## Infrastructure (IaC)

### Terraform changes
No new Terraform resources. The three host scripts + `hooks.json.tmpl` are webhook-delivered artifacts; their
prod delivery is the existing infra-config push (`push-infra-config.sh` base64 → `/hooks/infra-config` →
`infra-config-apply.sh` writes `/usr/local/bin/*.sh` 755 root:root + renders `/etc/webhook/hooks.json`).

### Apply path
**(b) cloud-init + idempotent bootstrap-equivalent (the infra-config auto-apply).** Merging the four edited
files fires `apply-deploy-pipeline-fix.yml` (`on: push: branches:[main]`, `paths:` already list all four —
`:71,:89,:95,:96`), which runs the infra-config push over the Cloudflare tunnel. **No SSH, no `vinngest-v*`
tag release, no unit restart, no cutover execution.** Expected downtime: none (script bodies swap in place;
next hook invocation uses the new script). **Blast radius (corrected — Deepen Finding 7): NOT preflight-only.**
`inngest-inventory.sh` is also consumed by `scheduled-inngest-health.yml:90` (the 15-min durability probe),
the op=execute DI-C3 gate (`cutover-inngest.yml:565`), and op=rollback (`:807`); `inngest-registry-probe.sh`
by op=rearm/op=execute. The completeness invariant + abandon-safety protect those consumers (bounded scan →
200 or LOUD fail, never truncated false-clean); the health probe converts a former silent hang into a clean
200. A pre-merge AC asserts the health-probe path still returns 200 under the reduced scan.

### Distinctness / drift safeguards
`dev != prd`: N/A (host scripts are prod-only infra). `ship-deploy-pipeline-fix-gate.test.ts` (#5505 parity)
keeps `apply-deploy-pipeline-fix.yml` paths in sync with `infra-config-apply.sh` TRIGGER_FILES — **no new
file is added**, so no parity edit is needed (confirmed all three scripts + `hooks.json.tmpl` already
registered). No secret value lands in state.

### Vendor-tier reality check
Better Stack: the marker rides the **already-provisioned** Vector journald→Better Stack pipe
(source 2457081, `BETTERSTACK_LOGS_TOKEN`); the three tags are already allowlisted. No new sink, no paid-tier
gate. (Alerting is out of scope — markers are queryable telemetry, not a new monitor.)

## Observability

```yaml
liveness_signal:
  what: SOLEUR_INNGEST_PREFLIGHT_{START,DONE,TIMEOUT} via logger -t {inngest-inventory|inngest-doublefire-probe|inngest-registry-probe}
  cadence: one START + one DONE|TIMEOUT per op=inventory/op=verify hook run (the wall-clock deadline caps any silent-but-progressing run, so no mid-scan PROGRESS marker is emitted or relied on)
  alert_target: Better Stack (source 2457081) — queryable; no new auto-alert monitor (out of scope)
  configured_in: apps/web-platform/infra/{inngest-inventory,inngest-doublefire-probe,inngest-registry-probe}.sh + vector.toml host_scripts_journald allowlist (tags already present, L134+)
error_reporting:
  destination: journald tag -> Vector -> Better Stack, AND webhook non-200 body surfaced as ::error:: in the cutover run log
  fail_loud: yes — deadline/ceiling/gql-error emits SOLEUR_*_TIMEOUT then exits non-zero (no silent truncation, no orphaned scan)
failure_modes:
  - {mode: scan exceeds deadline/page-ceiling, detection: SOLEUR_*_TIMEOUT marker w/ pages_scanned+elapsed_ms+reason, alert_route: Better Stack query + cutover ::error::}
  - {mode: pool-pressure stall (curl exit 28, empty body — the HTTP 000 shape), detection: SOLEUR_*_TIMEOUT last_curl_exit=28 / pages_timed_out>0 (splits stall from slow-scan), alert_route: Better Stack + existing [ci/inngest-pool] probe}
  - {mode: pool-pressure envelope (EMAXCONNSESSION mid-scan), detection: existing .data guard exit 1 -> SOLEUR_*_TIMEOUT reason=gql_error (a mid-loop PROGRESS pool_hint=pressure is NOT relied on — loop exit 1s on first error), alert_route: Better Stack + [ci/inngest-pool]}
  - {mode: host unreachable / hook 000, detection: outer curl 000 in run log + ABSENCE of any START marker for that run (START is the literal first line), alert_route: cutover ::error:: + Better Stack absence}
logs:
  where: Better Stack (Vector journald pipe) + on-host journalctl -t inngest-inventory|inngest-doublefire-probe|inngest-registry-probe
  retention: Better Stack default (source 2457081)
discoverability_test:
  command: scripts/betterstack-query.sh --grep 'SOLEUR_INNGEST_PREFLIGHT' --since 1h
  expected_output: ">=1 START marker per op=inventory/op=verify run with fields {op, host, window, page_ceiling, deadline_s}; a bounded/aborted run additionally emits a TIMEOUT marker carrying {pages, elapsed_ms, pages_timed_out, last_curl_exit, reason}"
```

## Architecture Decision (ADR/C4)

### ADR
Create **ADR-106 — "Inngest cutover pre-flight scans: bound duration + abandon-safety + in-surface marker
(amends ADR-105)."** Decision: the cutover pre-flight hooks MUST bound scan *duration/cost* (deadline + page
ceiling) in addition to ADR-105's connection *footprint* cap; a timed-out scan MUST be abandon-safe (release
connections, no orphan) so it cannot ratchet the shared pool; and the path MUST emit an in-surface
`SOLEUR_*` marker on start/timeout so a recurrence self-reports off-box. Records that the `HTTP 000` hang is a
distinct failure mode from the `EMAXCONNSESSION` (500) two-writer topology (the latter unchanged — deferred to
#6178 / gated by #6230). **Cross-reference** ADR-105 §"Precondition — exactly ONE prod-pool writer"
(`ADR-105:109-143`) rather than re-derive the two-writer scoping (Deepen Finding 15). `amends: ADR-105` (both
deployed + orthogonal — footprint vs duration; `supersedes` would be wrong, the pool cap stays in force).
`status: adopting` → `accepted` after the post-apply **op=inventory** re-run is green + the marker is
observable (op=verify's job-green is a post-#6178 concern). Provisional ordinal ADR-106 — re-verify at /ship
(a sibling PR may claim it).

### C4 views
**No C4 impact.** Checked all three model files (`model.c4`, `views.c4`, `spec.c4`): the actors/systems this
change touches — the `inngest` container, its `inngestPostgres` dedicated-project DB (Supavisor session
pooler), and the GitHub-Actions cutover workflow — are already modeled; the fix adds **no** external human
actor, no external system/vendor, no data store, and no access-relationship change (a scan-bounding + timeout
+ log-marker change adds/removes no element, edge, or `#external` boundary). Mirrors ADR-105's "No C4 impact"
reasoning (`ADR-105:151-156`). Run `c4-code-syntax.test.ts` + `c4-render.test.ts` unchanged.

### Sequencing
ADR-106 is authored now describing the target state; `status: adopting` flips to `accepted` on the green
post-apply re-run (Phase 5.3). No separate follow-up issue — the ADR/C4 review is a deliverable of THIS plan.

## Domain Review

**Domains relevant:** Engineering (CTO) — infrastructure/tooling reliability change. Product = NONE (no
user-facing UI surface; the mechanical UI-surface scan finds no `components/**`, `app/**/page.tsx`, or
`app/**/layout.tsx` in Files-to-Edit). No Legal/Finance/Marketing/Sales/Support implications.

### Engineering (CTO)
**Status:** to be reviewed at plan-review (eng panel always runs; escalated to +architecture-strategist
+spec-flow-analyzer at the single-user-incident threshold).
**Assessment:** Infra bug-fix bounding a runaway scan under a capped pool; the sharp edges are (a)
completeness parity of the cost-reduced scan (single-user-incident invariant), (b) timeout-hierarchy
correctness, (c) abandon-safety actually releasing connections. All three are captured as ACs/tests.

### Product/UX Gate
Not applicable — Product = NONE (infrastructure/tooling; no user-facing surface).

## Open Code-Review Overlap

None. Queried open `code-review` issues for `inngest-inventory.sh`, `inngest-doublefire-probe.sh`,
`inngest-registry-probe.sh`, `hooks.json.tmpl`, `cutover-inngest.yml` — zero matches.

## Test Scenarios

1. **Deadline hit** — corpus large enough to exceed `PREFLIGHT_DEADLINE_S=1`: script `exit 1` (via the shared
   loud-abort helper, NOT `break`), emits `SOLEUR_*_TIMEOUT reason=deadline pages_scanned=N elapsed_ms=M
   last_curl_exit=…`, stdout does NOT `jq -e '.armed_reminders'`-parse, spool cleaned (EXIT trap).
2. **Page ceiling hit** — `MAX_PAGES=2` with a 5-page fixture (gate = "about to fetch page 3 while
   hasNextPage=true"): `exit 1`, `reason=page_ceiling`; a corpus that exactly fits `MAX_PAGES` breaks clean.
3. **Completeness differential (inventory)** — old-unbounded vs new-reduced projection on the SAME large corpus
   containing a `reminder.scheduled` at each `receivedAt`-band boundary (incl. >180 days ago) + a cron name
   appearing only past page 1: assert reduced `functions`/`event_names`/`armed_reminders` ⊇ old, and `FROM_TS`
   byte-identical. Armed set via the `eventNames:["reminder.scheduled"]` query.
3b. **doublefire window** — probe window ⊇ operator cutover window; a run inside the operator window but
   nominally "old" is still observed (no false missed-tick).
4. **Sum-bounded no-overshoot** — with `DEADLINE_S=20`, a page starting at elapsed=19 uses `--max-time 1` (not
   15), so total script exit ≤ outer curl; no HTTP 000.
5. **Happy path within budget** — small fixture: well-formed JSON body on stdout, `SOLEUR_*_DONE` in journald
   (NOT stdout), START marker emitted before the functions fetch.
6. **Purity** — no `://`, no `@…:…@`, no actor/body; GraphQL `errors[].message` mapped to enum (grep emitted lines).
7. **Abort → non-200** — workflow test: a deadline/ceiling abort surfaces via the `CODE!=200` cause-branch
   with the real `SOLEUR_*_TIMEOUT` text, not the 200-branch shape guard.
8. **Post-apply integration (Phase 5.3)** — op=inventory HTTP 200 + well-formed body; op=verify sub-probe
   transport has no 000/500 (job verdict may halt at registry_empty); START marker queryable in Better Stack.

## Risks & Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the threshold fails
  deepen-plan Phase 4.6.** Filled above (threshold: single-user incident).
- **Completeness vs cost tension (the single-user-incident core).** Narrowing the eventsV2 window to cut cost
  can silently drop far-future armed reminders because the `from`/`until` filter bounds `receivedAt`, NOT
  fire-time (learning `2026-06-17-inngest-eventsv2-raw-payload-and-receivedat-filter`). The completeness-parity
  AC + test is the guard; deepen-plan MUST finalize a mechanism that provably preserves the armed set.
- **`op=verify` JOB cannot go green pre-cutover (Deepen P0-1 — DoD re-scoped).** Its first step hard-requires
  `registry_empty==false` on the dark dedicated host (`cutover-inngest.yml:628-631`), which legitimately fails
  pre-cutover and never reaches the doublefire sub-probe. So the DoD is per-op: op=inventory HTTP 200 (the
  #6258 verify-close signal) + op=verify sub-probe **transport** bounded (no 000/500), proven by unit tests;
  a green op=verify JOB is post-#6178. State this in the runbook; do NOT gate #6258 on op=verify job-green.
- **The `sum-bound`, not the ordering, governs the timeout hierarchy.** `deadline + per-page ≤ outer`; the
  remaining-budget per-page `--max-time` clamp is what makes it airtight. An ordering-only check (`deadline <
  outer`) ships the 000 back. The abort path MUST be `exit 1` through the shared helper, never `break`
  (a `break` yields a truncated HTTP-200 false-clean body — the #6218 class).
- **Two-writer topology is out of scope.** `op=inventory`/`op=verify` green is achieved by bounding + abandon-
  safety restoring pool headroom, NOT by making two writers fit. The ultimate single-writer guarantee is #6178;
  do not let the fix imply otherwise. If a residual 500 recurs under concurrent heavy load post-fix, that is the
  ADR-105 §Precondition topology, not a regression — the bounded-retry (Phase 2.3) absorbs the transient.
- **adnanh/webhook has no `command-timeout` — and the `/usr/bin/timeout` wrapper is DROPPED (Deepen Finding 10).**
  The in-script `date +%s`-delta deadline is the sole + sufficient server-side bound (it halts the loop that
  drives PG load). A `timeout` wrapper's SIGTERM could fire mid-`logger` (losing the marker the fix exists to
  add) or bypass the EXIT trap (leaking the `mktemp` spool), and the adnanh static-arg form is unverified. Do
  not reintroduce it without empirical evidence of a non-loop hang.
- **Marker carrier is journald, not stdout.** The hook's stdout is the pure-JSON body the workflow parses;
  a marker on stdout would corrupt it. Emit via `logger -t <allowlisted-tag>` only (#5503). Confirmed the three
  tags are already in `vector.toml` — but Phase 0.4 must confirm Vector actually ships from the web host.
- **No new host script.** Adding a shared lib would require 4-site registration + parity test; keep the
  ~15-line deadline/marker logic in each existing script.

## Alternatives Considered

| Approach | Verdict |
|---|---|
| **Bound scan duration + abandon-safety + in-surface marker (chosen).** | Fixes the HTTP 000 hang and breaks the orphan-scan ratchet without touching the pool topology or executing the cutover. |
| `/usr/bin/timeout` hard-kill wrapper in `hooks.json.tmpl`. | **Rejected (Deepen Finding 10).** The adnanh/webhook static-arg form is unverified (zero repo precedent); it only guards non-loop hangs (already `--max-time`-bounded), can fire mid-`logger` (losing the marker) or bypass the EXIT trap (leaking the spool), and widens blast radius (inngest-inventory is also the health-probe endpoint). The codebase convention is a wrapper *script* (`ci-deploy-wrapper.sh:21`), which would be a new file needing 4-site registration. The in-script `date +%s`-delta deadline is sufficient + abandon-safe. |
| Convert the hooks to async (webhook `include-command-output-in-response:false` + 202 + fork + poll `/hooks/*-status`). | Rejected as primary — re-architects the `op=inventory`/`op=verify` contract (they parse the response body synchronously), a large blast radius for a pre-flight fix. Precedent exists (`verify-wiped-volume`). **Reconsider only if** Phase 0.5 proves the `event_names` all-events scan cannot fit the budget even at raised `PAGE_SIZE` with a raised deadline (Deepen Finding 4). |
| Re-size the pool / revert `default_pool_size` / add `pg_terminate_backend` idle-sweep as the fix. | Rejected — ADR-105 already settled these; the 500 is topological (two writers), not sizing. Sweep stays an emergency runbook lever only. |
| Only raise the outer curl `--max-time`. | Rejected — a longer client budget still hangs on an unbounded scan and still orphans the server-side scan (worsens the ratchet). Bounding must be server-side. |
| Run the actual cutover (`op=execute` / flip-arm) to collapse to one writer and remove the 500. | **Explicitly forbidden by scope** — that is #6178 execution, HELD for an operator maintenance window. |
