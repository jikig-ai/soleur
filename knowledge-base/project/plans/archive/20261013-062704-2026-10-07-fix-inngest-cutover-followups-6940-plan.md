---
title: "fix(infra): inngest cutover follow-ups — verify #7632 digest pin, registry-sourced missed-tick discovery (#6940 item 1)"
type: fix
date: 2026-10-07
slug: fix-inngest-cutover-followups-6940
branch: feat-one-shot-6940-7632-cutover-followups
issue: 6940
closes: [7632]
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(infra): inngest cutover follow-ups — verify #7632 digest pin, registry-sourced missed-tick discovery (#6940 item 1)

## Overview

Two issues ride this branch.

**#7632** asked to pin the web host's `soleur-inngest-bootstrap` image in
`apps/web-platform/infra/cloud-init.yml` by digest, matching the dedicated host. That work
**already landed on `main`**: both `IREF=` and `ZIREF=` carry
`v1.1.44@sha256:7a380ca6…` (digest-pinned since #7887, 2026-09-08, and kept in step by every
bump-bot re-pin since — v1.1.42 → v1.1.43 → v1.1.44 each moved tag and digest together), and
Guard B in `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` already sweeps every
`cloud-init*.yml` pin site and fails on any tag-only or digest-divergent ref. Verified locally:
Guard B reports `4 sites / 1 distinct tag / 1 distinct digest / 0 tag-only`. The plan's
response is to record the verification and close the issue — no code change needed.

**#6940** is the post-#6178 deferred list (ADR-146 §Deferred). This plan implements
**item 1** — registry-sourced missed-tick discovery — and deliberately leaves items 2 and 3:

- **Item 1 (implement):** extend `inngest-registry-probe.sh` to emit per-function trigger type
  (`triggers { type value }`), then in `op=verify`'s missed-tick path compute
  `registry_cron_ids − observed` and issue a second, `function_ids`-scoped doublefire-probe
  call over a `2×max_cron_period` window, folding live-but-slow crons into the enumeration
  set. This restores the slow-cron recall #6178 narrowed away.
- **Item 2 (documented deferral):** `CUTOVER_REGISTRY_BASELINE` + `CUTOVER_QUIESCE_PROBES`
  env mapping + completeness guard is gated on AC-V4 being green. Measured AC-V4 state: the
  most recent production `op=verify` (run 35415585389, 2026-09-19) printed
  `DOUBLE-FIRE detected`; the 2026-09-15 runs printed `exactly-once VERIFIED (QUALIFIED)`.
  Per #6178's AC table a QUALIFIED verdict does not satisfy AC-V4 and a detected double-fire
  keeps the issue open. **AC-V4 is not green**, so the mapping stays unmapped and the
  deferral is documented in the workflow env block.
- **Item 3 (out of scope):** `INNGEST_GQL_PAGE_SIZE=500` needs a new hook parameter + host
  hook-config redeploy — a production mutation outside this PR's constraints.

## Research Insights

### Relevant file paths

- `apps/web-platform/infra/inngest-registry-probe.sh` — the on-host probe; emits
  `{registry_empty, function_count, function_ids}` from `query RegistryProbe { functions { id } }`
  (line 51). Delivered to hosts via the infra-config push
  (`apps/web-platform/infra/infra-config-apply.sh:233`,
  `.github/workflows/apply-deploy-pipeline-fix.yml:106`); the `inngest-registry-probe` hook in
  `apps/web-platform/infra/hooks.json.tmpl:280` takes no params — **no hook-config change or
  redeploy needed** for the extended output.
- `apps/web-platform/infra/inngest-registry-probe.test.sh` — 75-assertion suite; fixture seam
  `INNGEST_PROBE_FUNCTIONS_FIXTURE`; runs in ~1.8 s.
- `scripts/cutover-inngest.sh` — the workflow body. `missed_tick_report()` at :1148 takes
  `(gate, body, cron_period, win_from, win_until)`; has a "DO NOT RESHAPE" column-0 extraction
  contract. The `verify)` arm fetches the registry-probe body into `BODY` at :2824-2846
  (reads `.function_count`/`.registry_empty`; `.function_ids` unused there), then `BODY` is
  overwritten by the doublefire fetch at :2917-2930; `missed_tick_report` is called at :3026
  with the runs `$BODY` **after** the verdict and cannot change it.
- `.github/workflows/cutover-inngest.yml` — step env block :140-211 maps `CUTOVER_*`/`FLUSH_*`
  vars; `CUTOVER_REGISTRY_BASELINE`/`CUTOVER_QUIESCE_PROBES` are dereferenced by the script
  (`cutover-inngest.sh:2851,2222,1615`) but deliberately unmapped.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — ~4290-line suite; pins the
  `missed_tick_report` call site byte-exact (`MTR_CALL` :3890), its neighbours (:3904-3907),
  `inngest-doublefire-probe?from=` site count == 2 (:377), `RETRY_N` == 3 bounded retries
  (:432), `DEDUPE_N` == 2 dedupe sites (:2377), and executes the extracted
  `missed_tick_report` over ~26 cases.
- `apps/web-platform/infra/inngest-doublefire-probe.sh` — accepts
  `INNGEST_DOUBLEFIRE_FROM` / `INNGEST_DOUBLEFIRE_FUNCTION_IDS`; hook forwards `?from=` and
  `?function_ids=` (hooks.json.tmpl `#6919` comment block). Open-topped window (no `until`).
- `apps/web-platform/infra/ci-deploy.sh:2978-2984` — precedent consumer of
  `functions { triggers { type value } }` (`"type":"CRON"` substring match, verified vs
  inngest v1.45.1).
- `knowledge-base/project/specs/feat-one-shot-inngest-cutover-no-ssh-5450/inngest-graphql-schema.md`
  — pinned schema: `Function.triggers: [FunctionTrigger!]` with `type: FunctionTriggerTypes`,
  `value: String`; a bare `triggers` is a validation error, subfields are required.
- `knowledge-base/engineering/architecture/decisions/ADR-146-...md` §Deferred — items 1-5;
  item 1 is exactly this design; item 5 already annotates that the same probe extension
  (slug + triggers) serves its proper fix.
- `scripts/followthroughs/inngest-soak-6178.sh:305-336` — consumes `.function_ids` from the
  registry body (additive field is backward-compatible) and already notes the missing
  trigger attribution ("attribute their triggers (cron or event)").

### Premise validation (Phase 0.6)

- **#7632 premise is STALE.** The issue claims `cloud-init.yml` pins `v1.1.25` tag-only.
  Current `main` pins `v1.1.44@sha256:7a380ca635bdcb71192c847133d7158714730860532f00b04f34085fe45e5bc7`
  at both `IREF=` (:712) and `ZIREF=` (:716). The digest pin first landed in #7887
  (`235693e411`, 2026-09-08). Guard B (`cloud-init-inngest-bootstrap.test.sh` :988-1100)
  sweeps `--include='cloud-init*.yml'`, asserts `0 tag-only`, `1 distinct tag`,
  `1 distinct digest`, and row 6 enforces tag+digest move together vs `origin/main`.
  All three ACs are already satisfied; the plan closes #7632 via the PR body with this
  evidence.
- **#6940 items verified live:** registry probe emits ids only (:51 query lacks triggers);
  `CUTOVER_REGISTRY_BASELINE`/`CUTOVER_QUIESCE_PROBES` absent from the step env block
  (workflow :140-211) while read at `cutover-inngest.sh:2851` and `:2222`; AC-V4 **not green**
  (latest verify run 35415585389 = `DOUBLE-FIRE detected`; Sep-15 runs = `QUALIFIED`).
- **Mechanism check vs ADR corpus:** the second-probe design is ADR-146 §Deferred item 1
  verbatim — the sanctioned approach, not a rejected alternative. The `2×max_cron_period`
  term (~182 d) is ADR-106's function-discovery window; the repo's slowest registered cron
  is quarterly (`cron-legal-audit` `0 11 1 1,4,7,10 *`, ~92 d max gap) so 184 d covers 2×
  with margin.
- **grep wrapper caveat:** the interactive shell defines a `grep` function that silently
  nullifies `--include`; in scripts/tests plain `command grep` runs and Guard B behaves
  correctly (verified: suite is 230/230 green on this box).

### Property list / cut list (Phase 0.6b)

Properties the ask actually names:

1. The web host boots a digest-pinned bootstrap image and a guard fails on any tag-only
   site — **already covered** by Guard B + the on-main pins (no new mechanism needed).
2. `op=verify`'s missed-tick enumeration can see registered cron functions with zero runs
   in the fsm-anchored window — requires trigger type from the registry probe and one
   scoped re-scan.
3. The mapping of `CUTOVER_REGISTRY_BASELINE`/`CUTOVER_QUIESCE_PROBES` — **deferred** (AC-V4
   not green); only the documentation lands.
4. `INNGEST_GQL_PAGE_SIZE` measurement — **out of scope** (prod redeploy).

Cut list: no new workflow op, no new hook, no cron-expression parser (ADR-146 item 5's
dependency — explicitly out of item 1's scope), no host-side changes beyond the probe script
body (which rides the existing infra-config push).

## Research Reconciliation — Spec vs Codebase

| Spec/issue claim | Reality on `main` | Plan response |
|---|---|---|
| #7632: `cloud-init.yml` pins `v1.1.25` tag-only | Both refs carry `v1.1.44@sha256:…` since #7887 | Verify + close; no code change |
| #6940 item 1: probe emits ids only | True — `functions { id }` | Extend to `id slug triggers { type value }` |
| #6940 item 2: vars unmapped; land after AC-V4 green | True; AC-V4 measured not-green | Defer mapping; document in env block |
| #6940 item 3 | Needs prod hook redeploy | Out of scope |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is internal
  cutover tooling; a defect would corrupt an operator-facing `op=verify` missed-tick report
  (wrong candidate list) or make the registry probe fail loud on the next infra-config push.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the probe output
  gains function slugs + trigger values (e.g. `cron/daily-triage`, `0 8 * * *`) — internal
  function names already visible in the same channel; no user data touches the new fields.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal ops tooling with no user-facing surface;
  a wrong missed-tick candidate list is advisory-only (the lines are non-command-shaped and
  explicitly UNVERIFIED).

*Scope-out override:* `threshold: none, reason: the diff touches internal cutover probes and
workflow plumbing under apps/web-platform/infra + scripts/ — no user-facing artifact changes.`

## Observability

```yaml
liveness_signal:
  what: "the registry probe's SOLEUR_INNGEST_PREFLIGHT_START/DONE journald markers (op=verify-registry) already fire per call; the workflow's op=verify run log gains ::notice::2.6 zero-run discovery lines naming the scoped set size and the probe outcome"
  cadence: "per op=verify dispatch (on-demand)"
  alert_target: "Actions run log + Better Stack (existing journald → vector.toml pipeline)"
  configured_in: "apps/web-platform/infra/inngest-registry-probe.sh (_pf_marker), scripts/cutover-inngest.sh verify arm"
error_reporting:
  destination: "Actions run log ::warning::/::error:: annotations + journald markers"
  fail_loud: "a failed/missing functions field degrades to a ::warning:: and skipped discovery — never a false clean, never a failed op=verify; a probe-side fetch failure stays fail-LOUD (existing exit-1 contract unchanged)"
failure_modes:
  - mode: "on-host probe predates the `functions` field (infra-config push not yet landed)"
    detection: "::warning:: names the absence and discovery is skipped"
    alert_route: "operator reading the verify run log"
  - mode: "second doublefire-probe transport failure"
    detection: "::warning::2.6 zero-run discovery probe failed (HTTP <code>)"
    alert_route: "operator reading the verify run log"
  - mode: "registry reports zero CRON functions"
    detection: "discovery block short-circuits silently — zero-run set is empty by construction"
    alert_route: "none needed (legitimate empty)"
logs:
  where: "journald on the web host (tag inngest-registry-probe) → vector.toml → Better Stack; Actions run log for the workflow side"
  retention: "Better Stack retention window"
discoverability_test:
  command: grep -c 'FUNCTIONS_GQL_QUERY.*triggers { type value }' apps/web-platform/infra/inngest-registry-probe.sh
  expected_output: "1"
```

## Guard Contract

### Guard 1 — registry probe emits trigger type, lossless

**Property.** Every function object in the probe's emitted `functions` array carries its
`id`, `slug`, and `triggers[{type,value}]` exactly as the registry reported them — a dropped
field or a flattened type silently un-discovers crons downstream.

**Assembly.** The single chokepoint is the `.data.functions[]` projection in
`inngest-registry-probe.sh` (`functions { id slug triggers { type value } }` → the `functions`
output field). The workflow-side consumer is the zero-run derivation in `op=verify`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `triggers { type value }` from the GQL query back to `id`-only | RED — the emitted `functions` array loses `triggers` |
| 2 | Emit `function_ids` only (delete the `functions` field) | RED — consumer-side jq reads `.functions[]` as absent → discovery skipped; test asserts the field exists |
| 3 | A second function with a different trigger set — guard must reflect BOTH | RED if the projection is per-first-element only |
| 4 | (harness) fixture with EVENT-only triggers must PASS with `type:"EVENT"` preserved, not coerced | must-PASS |

### Guard 2 — zero-run set derivation is cron-only and shape-checked

**Property.** The second doublefire call's `function_ids=` carries only ids that (a) appear
in the registry's `functions` with a `CRON` trigger, (b) have zero runs in the primary
verify body, and (c) pass the `\A[A-Za-z0-9._-]{1,128}\z` shape check — an event-driven or
host-injected value must never reach the URL.

**Assembly.** The chokepoint is the jq set-difference in `scripts/cutover-inngest.sh`'s
verify arm feeding `function_ids=${ZERO_RUN_IDS}`; the URL is the only sink.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the `select(.type=="CRON")` filter — EVENT functions enter the set | RED — fixture with an EVENT-only registry fn asserts it is absent |
| 2 | Drop the shape check — a glob/hostile id reaches the URL | RED — `*`/`a\rb` fixture id must be skipped and counted |
| 3 | Subtract nothing — a cron WITH an observed run is re-scoped into the second probe | RED — an id present in `.runs[].functionID` must not appear |
| 4 | (harness) empty zero-run set must PASS with NO second call issued | must-PASS |

## Architecture Decision (ADR/C4)

Implements ADR-146 §Deferred **item 1** — the decision was already made there; this plan
does not make a new one. Deliverable: annotate ADR-146's deferred item 1 with a dated
"landed" note matching the existing `[2026-09-25, #6939:]` annotation pattern.

### C4 views

No C4 impact — checked `model.c4` (47 inngest mentions; the dedicated host, probes, and
webhook path are already modeled), `views.c4`, `spec.c4`. The change adds no external actor,
no external system, no container/data-store, and no new access relationship — it extends an
existing probe's response fields and adds a second call to an existing endpoint.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Append `@sha256:<digest>` to both web-host references" | Verified already landed; close #7632 with evidence | mapped (no-op — premise stale) |
| 2 | "Extend the probe to emit trigger type, then implement the design the issue gives" | FR-1 (probe emits `functions` w/ triggers), FR-2 (scoped second probe + merged enumeration) | mapped |
| 3 | "Map `CUTOVER_REGISTRY_BASELINE` + `CUTOVER_QUIESCE_PROBES` into the step env … only AFTER the cutover AC-V4 verification is green" | Verified AC-V4 not green → defer; document in env block | mapped (deferred per the ask's own constraint) |
| 4 | "`INNGEST_GQL_PAGE_SIZE=500` measurement … OUT OF SCOPE" | Excluded | mapped (exclusion honoured) |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| FR-1 registry probe emits triggers | "extending `inngest-registry-probe.sh` to emit trigger type" | asked |
| FR-2 zero-run scoped re-scan | "issue a second doublefire-probe call scoped `function_ids=<zero-run set>` over a `2×max_cron_period` window" | asked |
| New `CUTOVER_DISCOVERY_LOOKBACK_S` env var + mapping | none — new tunable for the lookback; mapped immediately so it is never dead code | inferred (justified: avoids recreating the unmapped-var defect this issue documents) |
| env-block deferral comment for item 2 | "leave item 2 documented" | asked |
| ADR-146 annotation | inferred — the ADR carries a deferred ledger that must stay truthful | inferred |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform/infra/` probes, `scripts/cutover-inngest.sh` + workflow
- Planned files: 6 | Estimated changed lines: ~350 (mostly tests)
- Recommendation: single PR — one coherent cutover-tooling change.

## Domain Review

**Domains relevant:** Engineering only — internal cutover tooling; no product/marketing/legal
surface. Product/UX gate: NONE (mechanical scan: no `*.tsx`, no UI-surface files).

Note: no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain`
(TR2 fail-closed) — the sweep above assessed all domains in a single pass and found only
Engineering implications.

## Implementation Phases

### Phase 1 — registry probe emits trigger type (TDD)

1.1. Extend `inngest-registry-probe.test.sh` FIRST (failing tests):
   - fixture builder accepts per-function `triggers` arrays;
   - new cases: CRON trigger type/value preserved in `.functions`; EVENT-only preserved;
     id-only fixture (pre-extension response shape) emits `functions` entries with
     `triggers: []`; `function_ids`/`function_count`/`registry_empty` unchanged; output
     stays a single pure JSON object.

1.2. `inngest-registry-probe.sh`:
   - `FUNCTIONS_GQL_QUERY` → `query RegistryProbe { functions { id slug triggers { type value } } }`
     (subfields required — bare `triggers` is a GraphQL validation error per the pinned schema).
   - Emit `functions: [{id, slug, triggers: [{type, value}]}]` alongside the existing three
     fields; project with `.triggers[]?` / `// []` tolerance so a registry field absence
     degrades to an empty list, not a crash.
   - DRIFT-PIN CONSEQUENCE (found in CI): the constant is pinned byte-identical across
     `inngest-cutover-flip.sh` (#7228) and `inngest-bootstrap.sh` (#8015) by
     `inngest-cutover-flip.test.sh`'s three-way guard — widen both to the same literal.
     The two baked consumers ignore `slug`/`triggers`. This drifts GuardA
     (baked-carriers vs `vinngest-$PIN`) until the next bake+pin cycle — the same
     advisory-red window `vinngest-v1.1.45`/PR #9716 is already inside (main is
     already 237/240 there). The fourth, UNPINNED copy (`inngest-luks-cutover.sh`'s
     inline serving check, needs only `id`) stays as-is.

### Phase 2 — zero-run discovery in `op=verify` (TDD)

2.1. `cutover-inngest-workflow.test.sh` FIRST (failing assertions):
   - update `MTR_CALL` literal (call now passes `"$MTR_BODY"`) and the neighbour pins;
   - `inngest-doublefire-probe?from=` site count 2 → 3;
   - new structural asserts: discovery block gated on the missed-tick flag + both window
     vars; `function_ids=${ZERO_RUN_IDS}` scoped URL; no `until=` on the new call; single
     bounded curl; failure path is `::warning::` (never `exit 1`); workflow maps
     `CUTOVER_DISCOVERY_LOOKBACK_S` into the step env;
   - pure-function extraction tests for the zero-run set derivation (cron-only filter,
     observed subtraction, shape check, empty-set no-op).

2.2. `scripts/cutover-inngest.sh`:
   - capture `REG_BODY="$BODY"` after the registry precondition (~:2863);
   - extract a pure helper `zero_run_cron_ids(reg_body, runs_body) -> csv` (column-0
     contract like `missed_tick_report`) implementing Guard 2's property;
   - in the verify arm, between the SCOPE CAVEAT echo and the `missed_tick_report` call:
     `MTR_GATE`/`MTR_BODY` locals + the gated discovery block — one
     `GET $BASE/inngest-doublefire-probe?from=<now - CUTOVER_DISCOVERY_LOOKBACK_S>&function_ids=<csv>`,
     bounded `--max-time`, on success merge `.runs` into `MTR_BODY`
     (`{runs:($a.runs + $b.runs)}`), on failure `::warning::` + continue unchanged;
   - `missed_tick_report "$MTR_GATE" "$MTR_BODY" "$CRON_PERIOD" "${CUTOVER_WINDOW_FROM:-}" "${CUTOVER_WINDOW_UNTIL:-}"`.

2.3. `.github/workflows/cutover-inngest.yml` — in the step env block:
   - map `CUTOVER_DISCOVERY_LOOKBACK_S: ${{ vars.CUTOVER_DISCOVERY_LOOKBACK_S }}` (default
     15897600 s ≈ 184 d ≈ 2×max_cron_period for the quarterly slowest registered cron);
   - add the item-2 deferral comment naming `CUTOVER_REGISTRY_BASELINE` +
     `CUTOVER_QUIESCE_PROBES`, the dormant `exit 1` (verify :2856-2858 / re-arm :1621), and
     the AC-V4 precondition.

### Phase 3 — records

3.1. Annotate ADR-146 §Deferred item 1 as landed (dated note, matching the #6939 pattern).
3.2. PR body: `Closes #7632` (with the verified-pin evidence) + `Ref #6940` (item 3 open;
      item 2 deferred on AC-V4).

## Files to Edit

- `apps/web-platform/infra/inngest-registry-probe.sh`
- `apps/web-platform/infra/inngest-registry-probe.test.sh`
- `scripts/cutover-inngest.sh`
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh`
- `.github/workflows/cutover-inngest.yml`
- `knowledge-base/engineering/architecture/decisions/ADR-146-trust-anchor-for-cutover-coexistence-window.md`

## Acceptance Criteria

- [ ] AC1: `inngest-registry-probe.sh` emits `functions: [{id, slug, triggers: [{type, value}]}]`
      in its single pure-JSON stdout object, alongside unchanged `registry_empty`,
      `function_count`, `function_ids` — backward compatible.
- [ ] AC2: `op=verify`, when `missed_tick_candidates=true` and both `CUTOVER_WINDOW_*` are set,
      derives `registry_cron_ids − observed` (cron-filtered, shape-checked) and issues ONE
      additional doublefire-probe GET scoped to that set over a
      `CUTOVER_DISCOVERY_LOOKBACK_S` (default ~184 d) window; its runs are merged into the
      missed-tick enumeration body so live-but-slow crons get enumerated.
- [ ] AC3: the discovery path never fails `op=verify` — probe transport failure or a registry
      body without `.functions` degrades to a `::warning::` and the un-augmented report; the
      exactly-once verdict above is untouched.
- [ ] AC4: `CUTOVER_REGISTRY_BASELINE`/`CUTOVER_QUIESCE_PROBES` remain unmapped; the env block
      carries the dated deferral comment naming the AC-V4 precondition and the dormant
      `exit 1`.
- [ ] AC5: #7632 closed with evidence: both `cloud-init.yml` refs digest-pinned + Guard B
      covers tag-only/digest-drift across `cloud-init*.yml`.
- [ ] AC6: `bash apps/web-platform/infra/inngest-registry-probe.test.sh` and
      `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` green; no new
      `for attempt in 1 2` site (single bounded call) and no `until=` on the new URL.

## Test Scenarios

- Given a registry fixture with `triggers:[{type:"CRON",value:"0 8 * * *"}]`, when the probe
  runs, then `.functions[0].triggers[0].type == "CRON"` and the id set is unchanged.
- Given an id-only fixture (pre-extension shape), when the probe runs, then `functions`
  entries carry `triggers: []` — no crash, no null field.
- Given a registry body with one EVENT-only and one CRON function, and a runs body covering
  the CRON one, when the zero-run derivation runs, then the csv is empty (EVENT excluded,
  CRON observed).
- Given a CRON registry fn absent from runs, when the derivation runs, then the csv names it;
  the emitted URL carries `function_ids=<that id>` and no `until=`.
- Given the second probe returns HTTP 500, when `op=verify` runs, then a `::warning::` prints
  and the missed-tick report proceeds on the primary body — rc unaffected.
- Given `missed_tick_candidates` != true or the window unset, when `op=verify` runs, then no
  second probe call is issued.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain no reference to any
planned file (checked 2026-10-07, 200-issue window).

## Sharp Edges

- The `missed_tick_report` call-site line, its neighbours, the `?from=` site count, the
  bounded-retry count, and the dedupe-site count are all pinned by
  `cutover-inngest-workflow.test.sh` — every one is updated in the SAME diff, never drifted.
- `BODY` inside the verify arm is overwritten by the doublefire fetch at :2926 — `REG_BODY`
  must be captured at :2846, before that overwrite.
- The discovery URL's `function_ids` must carry only shape-checked ids — it is a
  host-influenced value reaching a query string.
- The probe's new `functions` field is consumed via `// []`/`.triggers[]?` tolerance so a
  host still running the pre-push probe script degrades to skip-not-crash.
- Item 2 stays unmapped — landing `CUTOVER_REGISTRY_BASELINE` now would activate the dormant
  precondition `exit 1` upstream of the doublefire check before AC-V4 has ever been green.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6 — filled above.
