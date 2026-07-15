---
title: "fix(observability): zot mirror-fallback alarm threshold can never fire"
date: 2026-07-15
issue: 6285
branch: feat-6285-zot-metric-alert
pr: 6424
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: bug-fix
brainstorm: knowledge-base/project/brainstorms/2026-07-15-zot-fallback-alarm-threshold-brainstorm.md
spec: knowledge-base/project/specs/feat-6285-zot-metric-alert/spec.md
---

# fix(observability): the zot mirror-fallback alarm can never fire (#6285)

*v2 — rewritten after a 6-agent review. v1 shipped a merge-blocker (a test pins `value = 3`), a
vacuous AC, an AC that false-failed 18-to-1, and a false window boundary. All corrected below.*

## The bug

`sentry_issue_alert.zot_mirror_fallback_rate` (`issue-alerts.tf:1368`) has never fired. It can't.

**Proof** — Sentry OSS `src/sentry/rules/conditions/event_frequency.py`:

```python
# :174 — new-group short-circuit
# Assumes that the first event in a group will always be below the threshold.
if state.is_new and value > 1:
    return False
return current_value > value     # :195 — STRICT >
```

- `ci-deploy.sh:607` puts the unique deploy tag in the **message** → Sentry groups on message →
  **fresh issue-group per deploy**.
- `var.web_hosts` = 2 (web-1 hel1, web-2 fsn1) + inngest = 1 → **max 2 events per fresh group**.
- `value = 3`: short-circuits on the new group (`3 > 1`), and later `2 > 3` is false. **Never fires.**
- `value = 0`: `0 > 1` false → proceeds; `1 > 0` true → **fires on first event.**

Sentry's own comment *assumes* thresholds are > 1 — the assumption our per-deploy grouping breaks.

**Live confirmation:** the deployed rule reads `.conditions[0].value = 3` (AC6 pulls it read-only).

#6285 asked for a `sentry_metric_alert`. Rejected — at its own `alert_threshold = 3` it is equally
dead. The integer is the bug.

## TR1 — accepted on ONE leg, stated honestly

`value = 0` is accepted server-side: `EventFrequencyForm.value = forms.IntegerField(...)` (`:93`)
declares **no `min_value`**, while the sibling `EventFrequencyPercentForm` declares one at `:854` —
the omission is deliberate.

**That source read is the only evidence.** Two things that look like corroboration are not:

- `rules/preview/` returns 200 for `value=0` — **and also for `value=-1`**. It doesn't range-check.
- `terraform validate` passes `value = 0` — **and also `value = -1`**. It type-checks a `number`.

Both are proxies, not the invariant. **Residual risk:** the read is of Sentry **OSS**;
`jikigai-eu.sentry.io` is **SaaS** and need not be the same build. Mitigated by AC7 (live-fire) and
by CI failing loudly. Ladder if wrong: `value = 1` → corrected metric alert at `alert_threshold = 0`.
**Never re-ship `3`.**

## Changes

**1. `issue-alerts.tf:1380`** — `value = 3` → `value = 0`. Leave `frequency = 23` (Sentry's dedup
key) and `ignore_changes = [environment]` alone.

**2. `issue-alerts.tf:1326-1367`** — the comment block. Four separate false statements live here,
all inside the block we're already opening:

| Line | False claim | Why |
|---|---|---|
| `:1326` | "exceeds >3 in 1h" | describes the dead threshold |
| `:1331` | "Becomes load-bearing at the ADR-096 Phase-5 retirement" | **inverted** — 5.3 deletes the emitter |
| `:1343` | "drives many hosts onto the SAME group → crosses 3/group" | false in **both** halves; **this is what produced `3`** |
| `:1346-1350` | metric alert rejected: "CI-only `SENTRY_IAC_AUTH_TOKEN` … unresolvable" + "tracked as a follow-up" | token **is** in Doppler; points at #6285, which this PR closes |
| `:1352-1362` | ">3/1h is meaningful per-signal" | moot at `value = 0`; a second copy of the same arithmetic error |

Replace with, in this order — **state the invariant, never the host count** (a count rots the day
web-3 lands; that is precisely how the original comment rotted):

1. **Mechanism:** message embeds the unique deploy tag → fresh issue-group per deploy → the
   per-group count is bounded by fleet size and is **not a rate**.
2. **Invariant:** therefore any `value > 0` is fleet-shape-dependent and silently unreachable
   whenever fleet ≤ value; Sentry additionally short-circuits new groups when `value > 1`
   (`event_frequency.py:174`). **`value = 0` is the only fleet-independent setting.**
3. **Contrast with the sibling:** `web_terminal_boot_fatal:1462` uses `value = 1` — that works only
   because its shared `soleur-boot-emit` group is never new. Do **not** normalize this rule to
   match it.
4. **Change-trigger:** do not raise above 0 without re-deriving against `ci-deploy.sh`'s message
   construction.

Do **not** write "`frequency = 23` throttles re-notification" into the comment — see Risks; it's
false for this rule's grouping and would plant the next rot in the same spot.

**3. `ci-deploy.sh:857-871`** — a one-line tripwire at the 5.3 removal site (the file 5.3 actually
edits; the ADR is not where that executor stands):

```bash
# Removing this fallback branch (ADR-096 task 5.3) permanently darkens 3 of the 4 signals of
# sentry_issue_alert.zot_mirror_fallback_rate (infra/sentry/issue-alerts.tf) — retire it in the
# same PR. (zot_gate_degraded_event at :630 survives; it is emitted by the gate, not the pull path.)
```

**4. `ADR-096:103-106`** — the window, stated correctly:
- **Opens** when `ZOT_REGISTRY_URL` is set in Doppler `prd` (task 1.8) — **not** at the
  `ZOT_ACTIVE=1` flip. `zot_gate_degraded_event` is gated on `ZOT_REGISTRY_URL` (`:779-783`) and
  fires exactly where `ZOT_ACTIVE` stays **0** (`:790` probe_unreachable, `:799` creds_absent,
  `:807` login_failed). The three *pull-fallback* signals additionally require `ZOT_ACTIVE=1`.
- **Closes at 5.3 for 3 of 4 signals**; `zot-gate-degraded` survives.
- Threshold is `value = 0` (fire-on-first), matching `zot-soak-6122.sh`'s zero-tolerance gate.
- Drop "deferred to #6285". Sweep the stale ">3/1h" at `:90` and `:101` too.

**5. `test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`** — `:68` pins
`/value\s*=\s*3/`. **Without this edit CI is red and nothing else in this plan executes.** Update to
`/value\s*=\s*0/`; update the `>3 / 1h` comments at `:10` and `:59`.

## Acceptance Criteria

```bash
F=apps/web-platform/infra/sentry/issue-alerts.tf
ZOT='/^resource "sentry_issue_alert" "zot_mirror_fallback_rate"/{f=1; next} f&&/^}/{f=0} f'
CMT='NR>=1326 && NR<=1367'   # the comment block — ABOVE the resource; $ZOT cannot see it
```

Every expect-0 AC ends `|| true` — `grep -c` prints `0` and **exits 1**, aborting a `set -e` runner
on a passing AC.

### Pre-merge

- [ ] **AC1** `awk "$ZOT" "$F" | grep -cE '^[[:space:]]*value[[:space:]]*=[[:space:]]*0$'` → **1**
      (subsumes "no `value = 3` in the block": the only unquoted numeric `value =` in range is
      `event_frequency`'s — `filters_v2` values are quoted strings)
- [ ] **AC2** `awk "$ZOT" "$F" | grep -c 'ignore_changes = \[environment\]'` → **1** and
      `awk "$ZOT" "$F" | grep -cE '^[[:space:]]*frequency[[:space:]]*=[[:space:]]*23$'` → **1**
      (**note the awk pipe** — unpiped this returns 18, all 18 siblings carry the lifecycle block)
- [ ] **AC3** `awk "$CMT" "$F" | grep -cE 'fresh group per deploy|unique deploy tag'` → **≥1** AND
      `awk "$CMT" "$F" | grep -ciE 'many hosts|load-bearing at|CI-only|deferred to #6285' || true`
      → **0**. *Positive-first by design:* a pure absence-grep is a self-reference trap (the
      corrected comment may quote the old phrase to explain the error), and the `$ZOT` extractor
      **cannot see this range at all** — v1's AC4 used it and was structurally incapable of failing.
- [ ] **AC4** `cd apps/web-platform && ./node_modules/.bin/vitest run
      test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` → **5 pass** (baseline verified: 5
      pass today). v1 omitted this entirely; the suite pins `value = 3` at `:68` and turns CI red.
      Use the in-package binary — **not** `npx vitest` and **not** `npm run -w` (the repo root
      declares no `workspaces`, so the `-w` form aborts).
- [ ] **AC5** `cd apps/web-platform/infra/sentry && terraform init -backend=false && terraform
      validate` → success. The `sentry_issue_alert` deprecation warning is **expected** (beta2
      deprecates it for `sentry_alert`; ADR-031 NG9 forbids that until GA) — do not "fix" it.
      *Not TR1 evidence* (it passes `value = -1` too) — this only catches HCL breakage.
- [ ] **AC6** ADR-096: `grep -c 'deferred to #6285' <adr> || true` → **0**; and one line contains
      **both** `ZOT_REGISTRY_URL` and `5.3` (same-line — a bare `5.3` grep matches 3 pre-existing
      lines and is vacuous)
- [ ] **AC7** `grep -c 'zot_mirror_fallback_rate' .github/workflows/apply-sentry-infra.yml` → **≥1**
      (the `-target` at `:265` must survive, else this merges green and never applies)
- [ ] **AC8** `git diff --name-only origin/main...HEAD | grep -cE 'destroy-guard|scope-guard|counter-sentry' || true`
      → **0** (**three-dot** — two-dot includes base drift: 30 files vs the PR's real 5)
- [ ] **AC9** `Ref #6285` in the PR body (**not** `Closes` — closure is post-apply, AC11)

### Post-merge (automated — no operator step)

- [ ] **AC10** live rule reflects the fix, self-pulled read-only (`hr-no-dashboard-eyeball-pull-data-yourself`).
      URL shape matches `zot-soak-6122.sh:32` so the operator reads one shape, not two:
      ```bash
      curl -sS -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" \
        "https://sentry.io/api/0/projects/jikigai-eu/web-platform/rules/" \
      | jq '.[] | select(.name|test("zot")) | {name, conditions, actions}'
      ```
      → `.conditions[0].value == 0` **and** `.actions` non-empty (v1 claimed AC10 proved "pages
      somebody" while never projecting `.actions`).
- [ ] **AC11 — live-fire (the only AC that proves the alarm FIRES).** POST one synthetic event
      mirroring `ci-deploy.sh:630-646` with a **novel** reason so it forms a fresh group:
      `{feature: "supply-chain", op: "image-pull", registry: "zot-gate-degraded",
      zot_gate_reason: "synthetic_ac_probe_6285"}` → confirm the rule fires (an email arrives).
      **Safe on three independent grounds:** (1) `zot-gate-degraded` is matched by **none** of
      `zot-soak-6122.sh`'s four queries (`:57,58,60,61`) — verified live, Sentry tag matching is
      exact (`registry:"zot"` → 0 while `registry:"zot-gate-degraded"` → 31); (2) fired pre-cutover,
      so outside the soak window (`START` is pinned post-cutover, `:38`); (3) it cannot inflate the
      `registry:"zot"` sample either, so it cannot manufacture a false PASS. It exercises the exact
      proof: novel reason → fresh group → `is_new`, `0 > 1` false → `1 > 0` true → fires.
      Side effects (accepted): one page, and one self-identifying synthetic event in prod Sentry.
- [ ] **AC12** `gh issue close 6285` after AC10+AC11 pass.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Sentry rejects `value = 0` at apply | Low — one-leg source read (see TR1); OSS-vs-SaaS gap real | CI fails loudly. Ladder: `value = 1` → metric alert at `alert_threshold = 0`. Never `3`. |
| **Alarm goes live on merge and pages ~2-3×/day** | **Certain** — `ZOT_REGISTRY_URL` is set and `zot-gate-degraded` emitted **31 events in the last 7 days** (`probe_unreachable`) | **Accepted, operator-ruled: these are true signal.** The probe has been unreachable for 7+ days while every deploy silently falls back to GHCR, and **#6435 proves the soak is blind to this signal** — this alarm is its *only* coverage. Throttled by `frequency = 23` (the group is stable, so the throttle does apply here). |
| Page-rate on `ghcr-fallback` post-flip | Bounded by **deploy rate**, not `frequency` | The group is **fresh per deploy**, so `frequency = 23` throttles only within one deploy. Intended: every fallback FAILs the soak gate anyway. |
| Sibling `sandbox_startup_failure:1233` may share the defect | Unknown — **not traced** | Out of scope, #6429. (v1 pinned a file-wide count here; dropped — it coupled this PR to #6429's landing order.) |

## Infrastructure (IaC)

In-place attribute change on one existing resource in an existing root. No new resource/provider/
variable/secret. Auto-applies via `apply-sentry-infra.yml` (`-target` present at `:265`, verified).

**Distinctness / drift safeguards.** Verified, and load-bearing enough to state rather than assume:
- **Dedup-safe by construction.** Sentry's POST-time dedup keys on
  `action_match + filter_match + frequency + actions_v2-shape`
  (`2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md`). This diff
  changes **none** of the four → the rule's dedup hash is bit-identical. And it's an in-place PUT;
  the dedup wall is a create-path wall.
- **Destroy-guard does not trip.** `destroy-guard-filter-sentry.jq:50-54` counts **elements**, not
  content: `1+4+1 = 6` before and after → `nested_deletes: 0`; the update's actions are `["update"]`
  → `resource_deletes: 0`. **No `[ack-destroy]`.** Fail-safe: a forced replacement would set
  `resource_deletes=1` and fail CI loudly.
- **`-target` drags nothing.** Zero `for_each`/`count` in the entire sentry root; the rule
  references only `var.sentry_org` + the read-only `data.sentry_project.web_platform`.
- **`ignore_changes = [environment]`** lists exactly one attribute; `conditions_v2` is **not**
  ignored, so terraform owns it and reasserts `value = 0` against any UI drift.
- Token: `SENTRY_IAC_AUTH_TOKEN`, read-only, Doppler `prd_terraform` (also mirrored in
  `soleur/prd` — that is the config **ADR-031:185** names).

## Architecture Decision (ADR/C4)

**ADR:** amend `ADR-096:103-106` (change 4). No new ADR — a bug fix inside ADR-031's governed root.
Both `:101` ("count > 3/1h") and `:105` ("deferred to #6285") become false **as a direct
consequence of this diff**, so correcting them here is mandatory, not scope creep.

**C4: no element or edge added or changed → no `.c4` edit in this PR.** Enumerated against all
three files (`model.c4` 416 lines, `views.c4` 62, `spec.c4` 54): no external human actor, container,
or access relationship changes. **Sentry IS touched** — it is the only vendor in this diff — **and
is not modeled** (zero element declarations; description-string mentions only, while Better Stack is
modeled at `:262`). That is a deviation from the mandate's literal "touched + not modeled → in
scope", taken under `wg-when-an-audit-identifies-pre-existing`: the gap is identical pre/post, this
diff adds nothing to model, and it is **filed as #6436**. Grepping the feature's own noun (`zot`)
returns "modeled ✓" and misses it — the element was the *vendor*, not the feature.

## Domain Review

**Relevant:** Engineering, Product, Legal — assessed by the CPO+CLO+CTO triad at brainstorm
(carried forward; see `## Domain Assessments` there). **CLO: legally uninteresting, no GDPR gate**
(an alert threshold is not a PII field/auth flow/schema/route; Art. 30 unchanged — same processor,
same EU cluster). **Product/UX: none** — `.tf`/`.sh`/`.ts`/`.md` only, no UI surface.

**One carried-forward rationale is now inverted.** The CPO argued this alarm is near-redundant with
`zot-soak-6122.sh` ("strictly more sensitive"). **False** — the soak queries only 2 of the alarm's 4
signals (#6435), so the alarm is the *only* coverage for `zot-gate-degraded` and `app_ghcr_fallback`.
That strengthens the ship case rather than weakening it.

## Files to Edit

- `apps/web-platform/infra/sentry/issue-alerts.tf` — `:1380` value; `:1326-1367` comment
- `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` — `:68`, `:10`, `:59`
- `apps/web-platform/infra/ci-deploy.sh` — one tripwire comment at `:857-871`
- `knowledge-base/engineering/architecture/decisions/ADR-096-…-zot.md` — `:90`, `:101`, `:103-106`

## Spin-offs (filed, not fixed here)

**#6435** the soak is blind to 2 of 4 signals → can false-PASS the GHCR-retirement gate
(**higher value than this fix**) · **#6436** Sentry unmodeled in C4 · **#6437** a Doppler-less host
falls back emitting no signal at all · **#6429** audit sibling `sandbox_startup_failure` ·
**#6427** retargeted: 5.3 removes the only two signals the soak reads → retire/re-point it in the
same slice · **#4656** comment: the `N=1` premise is falsified (team memberCount=3).
