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
`jikigai-eu.sentry.io` is **SaaS** and need not be the same build. Mitigated by AC11 (live-fire) and
by CI failing loudly. Ladder if wrong: `value = 1` → corrected metric alert at `alert_threshold = 0`.
**Never re-ship `3`.**

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — and that is why the miss is
invisible. The fleet keeps deploying successfully off the GHCR fallback; the first signal is the
7-day soak sweeper failing at day 7, resetting the Phase-5 cutover by a week.

**If this lands *working but muted*, the user experiences a full deploy/recovery outage.** All four
signals share one rule (`filter_match = "any"`). If the founder mutes the **rule** to escape the
`zot-gate-degraded` noise this makes live, `registry:ghcr-fallback` — the only no-SSH page gating
the **irreversible** ADR-096 5.5 PAT rotate+revoke — dies with it. The cutover then proceeds on a
false green: 5.3 deletes the fallback branch, 5.5 revokes the PAT, and a host that cannot pull from
zot has **no image source**. Mitigated in this PR: the `.tf` comment and the revert runbook both
now say **mute the ISSUE, never the rule**, and explain why that is safe by construction
(gate-degraded groups on a stable reason literal; `ghcr-fallback` mints a fresh group per deploy,
so no pre-existing mute can pre-suppress it).

**If this leaks, the user's data is exposed via:** N/A. Both emitters carry fixed literals +
`image_kind` + a git tag + a 3-literal reason — no user content, no credential, no PII. `value`
changes **notification**, not **capture**: these events already flow to Sentry today regardless of
the threshold, so this diff cannot mint a new exposure vector.

**Brand-survival threshold:** `single-user incident` (auto per #5175).

> **CPO flag (recorded, not overridden):** the *direct* vector terminates in migration-schedule
> integrity, not a single-user incident — the GHCR fallback is by-design safe degradation. The
> `single-user incident` classification is carried by the **indirect** mute-coupling vector above,
> which `user-impact-reviewer` surfaced at PR review and the plan originally missed.

## Observability

```yaml
liveness_signal:
  what: sentry_issue_alert.zot_mirror_fallback_rate pages on the FIRST event of any of its 4 signals
  cadence: event-driven; frequency=23 throttles re-notification per (rule, issue-group)
  alert_target: IssueOwners → ActiveMembers fallthrough (unchanged; no numeric target — NG3)
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf (applied via apply-sentry-infra.yml:265)
error_reporting:
  destination: Sentry (jikigai-eu, EU cluster) — this change IS the error-reporting layer
  fail_loud: true — value=0 is fire-on-first; value=3 WAS the silent-failure mode
failure_modes:
  - mode: alarm still cannot fire (threshold wrong / not applied)
    detection: AC1-AC3 (source) + AC10 (reads the LIVE rule, not the file) + AC11 (proves it FIRES)
    alert_route: CI fails on AC; AC10/AC11 self-pull post-merge
  - mode: alarm fires but pages nobody
    detection: AC10 projects `.actions` and asserts non-empty
    alert_route: unchanged IssueOwners fallthrough (no notify-target change in this PR)
  - mode: rule muted to escape noise → ghcr-fallback page dies silently
    detection: none automated — this is the residual brand risk
    alert_route: mitigated by doc (mute-the-issue-not-the-rule) in the .tf comment + revert runbook
  - mode: host is Sentry-dark (no Doppler/DOPPLER_TOKEN, or SENTRY_* prefetch soft-fails at :711)
    detection: NOT this alarm — `logger -t ci-deploy` → journald → Vector → Better Stack
      (`vector.toml:129` allowlists the tag). Tracked in #6437.
    alert_route: Better Stack log query; ci-deploy.sh's `FATAL: Doppler CLI not installed` /
      `FATAL: DOPPLER_TOKEN not set` guards bound the Doppler-less case (grep the literals — line
      numbers here rotted once already when this PR's own +14 lines shifted them)
logs:
  where: Sentry issue-group events (registry/stage/image/zot_gate_reason tags); no new log surface
  retention: Sentry default (unchanged)
discoverability_test:
  command: >
    curl -sS -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN"
    "https://sentry.io/api/0/projects/jikigai-eu/web-platform/rules/"
    | jq '.[] | select(.name|test("zot")) | {conditions, actions}'
  expected_output: 'conditions[0].value == 0 AND actions non-empty (NO ssh; token read-only from Doppler prd_terraform)'
```

**Soak follow-through: not required.** #6285 closes on threshold-fixed + applied + fired
(AC10/AC11). The 7-day zero-fallback soak is **#6122's** gate, already enrolled via
`zot-soak-6122.sh`.

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
- [ ] **AC6** ADR-096, **positive-first** (all three verified live — the two positives are absent on
      `origin/main`, so they fail pre-fix):
      `grep -c 'opens when \`ZOT_REGISTRY_URL\` is set' <adr>` → **1** ·
      `grep -c 'closes at task' <adr>` → **1** ·
      `grep -c 'deferred to #6285' <adr> || true` → **0**.
      *Two shapes deliberately NOT used:* a **same-line** `ZOT_REGISTRY_URL` + `5.3` grep is
      unsatisfiable — markdown wraps them onto different lines. And an **absence-grep for the stale
      `> 3/1h`** false-fails correct work: the corrected ADR legitimately quotes it to explain what
      shipped wrong ("Its threshold shipped as `> 3/1h` and could never fire"). That is the
      self-reference trap — AC3 was designed around it; AC6 v2 was not, and it fired here.
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
      zot_gate_reason: "synthetic_ac_probe_6285"}` → confirm the rule fires **via the Sentry API**
      (poll the synthetic issue's activity feed for a triggered-rule entry). **Do NOT verify by
      reading the founder's inbox** — that is an operator step, and this section is automated
      (`hr-never-label-any-step-as-manual-without`). AC11 is also the ONLY check that catches the
      residual TR1 mode AC10 cannot: SaaS **accepts and stores** `value: 0` but never fires (a
      server-side coercion, or a build whose new-group short-circuit differs from OSS `master`) —
      AC10 reads the stored value back and would PASS.
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
| **Alarm goes live on merge and pages several×/day** | **Certain** — `ZOT_REGISTRY_URL` is set and `zot-gate-degraded` emitted **31 events over the 4 days to 2026-07-15** (`probe_unreachable`), incl. **9 in the last 24h** | **Accepted, operator-ruled: these are true signal.** The probe has been unreachable for days while every deploy silently falls back to GHCR, and **#6435 proves the soak is blind to this signal** — this alarm is its *only* coverage. **Rate correction:** the operator ruled on "~2-3/day", which was understated — the emit is once per `ci-deploy.sh` run per host, so it is **deploy-rate-bound (~7-9 events/day observed)**. `frequency = 23` throttles it (the reason-keyed group is stable) but pages land per 23-min bucket, so expect **~4-8/day**, and up to 3 concurrent reason-groups each with an independent bucket (reason-space is bounded at 3 literals). The decision's *rationale* is unaffected; the mute-coupling mitigation above is what makes the higher rate safe. |
| Page-rate on `ghcr-fallback` post-flip | Bounded by **2× deploy rate**, not `frequency` | The message embeds `$img`, so each deploy mints **two** groups (`web:<tag>` and `inngest:<tag>`), each throttled separately. `frequency = 23` throttles only within one deploy's group. Intended: every fallback FAILs the soak gate anyway. |
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
