---
title: A comment-fix PR's dominant failure mode is writing a NEW false comment — plus the vacuous-AC and ship-gate-trim classes
date: 2026-07-15
category: best-practices
module: apps/web-platform/infra/sentry, apps/web-platform/infra/ci-deploy.sh, plugins/soleur/skills/{plan,review}
issue: 6285
pr: 6424
problem_type: best_practice
component: documentation
symptoms:
  - "retirement tripwire claims 'darkens 3 of the 4 signals' when it darkens 1"
  - "acceptance criterion returns 0 pre-fix and post-fix — structurally cannot fail"
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: high
tags: [comment-rot, acceptance-criteria, sentry, adr, doc-drift, review-catches, ship-gates]
synced_to: [review]
---

# Learning: the comment-fix PR that wrote a new false comment (#6285 / PR #6424)

Sibling to [2026-07-15-sentry-event-frequency-threshold-unreachable-and-data-source-scope-403.md](./2026-07-15-sentry-event-frequency-threshold-unreachable-and-data-source-scope-403.md),
which covers the **mechanism** (why the threshold was unreachable; why `data "sentry_team"` 403s).
This file covers the **doc-fix failure modes** the same PR surfaced — a different problem class
with a different audience.

## Problem

#6424 existed to delete a false comment. `issue-alerts.tf` justified an alarm threshold with:

> a rolling-deploy zot miss drives many hosts onto the SAME `ghcr-fallback (web:<tag>)` group →
> crosses 3/group

False in both halves — and that false sentence is what produced a `value = 3` threshold on a safety
alarm that could never fire. **The replacement comment I wrote was also false, in the same shape.**
Four review agents converged on it.

---

## A (PRIMARY) — the "N of M" arithmetic is where a comment-fix PR writes its new false comment

The new retirement tripwire in `ci-deploy.sh` claimed:

> removing this fallback branch is ADR-096 task 5.3, and it permanently darkens **3 of the 4
> signals** … **retire that alarm in the SAME PR** … It also removes **both** events
> zot-soak-6122.sh reads (:57-58)

Every quantified claim was wrong:

| Claim | Reality |
|---|---|
| "darkens 3 of the 4 signals" | darkens **1** (`registry:ghcr-fallback`) |
| "removes both events the soak reads (:57-58)" | removes **one** (`:57`; `:58` is cloud-init-emitted) |
| "retire that alarm in the SAME PR" | **UNSAFE** — see below |

`ZOT_ACTIVE` appears **0 times** in `cloud-init.yml`. The two `stage:` signals
(`app_ghcr_fallback:536`, `inngest_ghcr_fallback:695`) are a separate fresh-boot path that fires on
the zot **MISS**, *before* any GHCR pull — so neither "remove the fallback branch" nor "stop GHCR
push" darkens them.

**The prescription was worse than the defect.** Retiring the alarm at 5.3 blinds **3 still-live**
signals, including `zot-gate-degraded` — the alarm's *highest-volume* signal (31 events over 4 days,
live right now). The correct action is to **NARROW `filters_v2`**, never retire.

**The comment contained the sentence that falsified itself:**

```
# ... permanently darkens 3 of the 4 signals ... retire that alarm in the SAME PR ...
# NOT darkened: zot_gate_degraded_event (:630) is emitted by the GATE, not this pull path.
```

If a signal survives, the alarm cannot be retired. Both sentences were mine, three lines apart.

**Root cause:** `ADR-096:151` defines task 5.3 as *"remove the pull-site GHCR fallback **branch**"* —
**singular**. There are **three** such branches across two files (`ci-deploy.sh:857`,
`cloud-init.yml:536`, `:695`). I inherited the singular framing and asserted plural consequences off
it, without counting.

> **Rule.** When a comment/doc asserts *"doing X darkens/breaks/removes **N of M** things"*,
> enumerate the M and grep each one's emitter/definition. The **N is the most fragile claim** in the
> comment, because it is inherited from an upstream doc's singular/plural framing rather than
> counted. Two free self-checks: **(a)** a `NOT affected: …` carve-out in the same comment is a
> self-check — reconcile it against the N; **(b)** re-derive any prescription (*"retire it"*,
> *"delete it in the same PR"*) from the corrected count. **A prescription derived from a wrong
> count can be strictly more harmful than the defect being fixed.**

Caught by `security-sentinel` + `architecture-strategist` converging independently.

## B — a doc-rot fix stales the line-refs pointing INTO it

My comment rewrite was net **+5 lines**, moving the grouping-note paragraph `1352 → 1364`. A sibling
resource's comment at `issue-alerts.tf:1447` reads *"GROUPING NOTE (mirrors
zot_mirror_fallback_rate:**1352**)"* — now pointing at the wrong paragraph. **In the PR whose entire
purpose was fixing comment rot.**

> **Rule.** After any edit that changes line counts, `grep -n '<basename>:[0-9]'` the same file **and**
> its siblings, and fix every hit in the same edit. Prefer section/symbol anchors over bare line
> numbers in NEW prose. Extends
> [2026-06-18-doc-insertion-stales-cross-artifact-line-citations.md](./best-practices/2026-06-18-doc-insertion-stales-cross-artifact-line-citations.md)
> from cross-artifact to **within-file** cross-refs.

Caught by `architecture-strategist`.

## C — a test can pin the exact literal your one-line fix changes

`apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts:68`:

```js
expect(scoped).toMatch(/value\s*=\s*3/);
```

Plan v1's `## Files to Edit` omitted it and no AC ran vitest → **CI red → PR unmergeable → every
post-merge AC unreachable.** Invisible to typecheck and to the plan's own reasoning.

> **Rule.** Before planning a change to a literal value in config/IaC, run
> `git grep -l '<the literal>' -- '**/test/**'`. A drift-guard test that pins the value will block
> the merge.
>
> **Silver lining:** it makes RED/GREEN genuine. The test *passes by pinning the bug*, so flipping it
> to assert the fix fails against the un-fixed source — a real RED — and the one-character change
> turns it green.

Caught by `spec-flow-analyzer` at plan review (P0).

## D — verify EVERY AC against a known-broken control; never generalize from one

Plan v1's shared awk extractor anchored on the resource line (`:1368`):

```bash
ZOT='/^resource "sentry_issue_alert" "zot_mirror_fallback_rate"/{f=1; next} f&&/^}/{f=0} f'
```

AC1/AC2 (resource-**body** assertions) correctly failed pre-fix, so I generalized *"the extractor is
a live verifier"* across the whole block. But **AC4 asserted on the COMMENT block at `:1330-1367` —
ABOVE the anchor.** The extractor structurally could not see it: AC4 returned `0` pre-fix, post-fix,
and if the phase was deleted from the plan. **Four of six** plan-review agents found it
independently. Siblings in the same suite: AC3b dropped the `awk` pipe (returned **18**, not 1 —
false-fails every run); AC8 used a **two-dot** `origin/main` diff (30 files of base drift vs the PR's
real 5).

> **Rule.** An extractor correct for one scope is **not** correct for an adjacent scope. Run EVERY AC
> against the pre-fix tree and confirm it **FAILS**; an AC that passes pre-fix is vacuous. The
> abstraction shared across ACs with *different scopes* is exactly where the silent gap lands.

## E — falsifying one proxy does not immunize you against offering another one bullet later

Plan v2's TR1 discredited Sentry's `rules/preview/` probe honestly:

> returns 200 for `value=0` — **but also 200 for `value=-1`** … a proxy, not the invariant

Then **the next bullet** offered `terraform validate` as TR1 evidence. It also passes `value = -1`.
Same fallacy, one bullet apart. TR1 actually rests on **one** leg (the Sentry OSS source read), with
an unstated OSS-vs-SaaS gap.

> **Rule.** After rejecting evidence E1 as *"a proxy, not the invariant"*, re-run the **same test**
> against every remaining piece of evidence in that section: *"does this distinguish the correct
> value from an obviously-invalid one?"* If `value=-1` passes it too, it proves nothing.

Caught by `kieran-rails-reviewer`.

## F — a simplicity trim can delete ship-gate sections

`dhh-rails-reviewer` correctly called plan v1 ~70% ceremony (*"the proof starts at line 95; ninety-four
lines of throat-clearing come first"*). The trim was right — but it removed `## User-Brand Impact`
(preflight **Check 6**, threshold = `single-user incident`) and `## Observability` (plan **Phase
2.9**) **entirely**. Both block ship.

> **Rule.** After trimming a plan on simplicity feedback, re-run the gate predicates:
> `grep -c '^## User-Brand Impact'`, `grep -c '^## Observability'`. Simplicity reviewers optimize for
> reader attention and **do not model the ship gates**.

Caught by `user-impact-reviewer` + `observability-coverage-reviewer`.

## G — sibling artifacts falsified by the fix are in-scope even when absent from Files to Edit

`knowledge-base/engineering/operations/runbooks/zot-registry-revert.md` is the alarm's **only**
on-page triage doc. Fire-on-first falsified it:

- `:30-31` — *"a **single** transient `ghcr-fallback` is self-healing … Revert is for a **sustained**
  degradation, **not one blip**"* → tells the operator to **dismiss the exact page `value = 0`
  creates**.
- `:84` — *"exceeds **X = 3 events in Y = 1 hour**"* → the dead threshold, verbatim.
- *"Arm it in Sentry at cutover (it targets events that do not exist pre-flip)"* → doubly false: the
  rule is apply-created, and `zot-gate-degraded` emits pre-flip.

> **Rule.** When a change alters an alarm's **firing semantics**, grep for its runbook/triage doc and
> treat it as in-scope. **An alarm that pages into a runbook saying "ignore this" is worse than no
> alarm.** Same class as the existing "legal-disclosure prose hallucinated against the migration
> body" rule.

Caught by `observability-coverage-reviewer`.

## H — an ADR can cite an observability layer that does not exist

`ADR-096:89-91` assigned zot liveness to a `betteruptime_heartbeat.registry_prd` push beat *"that
pages if zot stops beating — before it can gate a boot (TR3)"*. That layer **does not exist**:
`ZOT_HEARTBEAT_URL` (`zot-registry.tf:359`) has **zero consumers** repo-wide (no pinger cron was ever
written) and the resource ships `paused = true` (`:350`). Live proof: 31 `probe_unreachable` events
over 4 days, **none of which paged anything**. I edited that bullet's *first half* and left the false
second half standing.

> **Rule.** When editing a bullet that cites an observability layer, `git grep '<ENV_OR_URL_VAR>'`
> for consumers — a **provisioned-but-unconsumed** heartbeat/monitor is a false layer citation.
> *"I only edited half the sentence"* is not an exemption: the "false as a direct consequence of this
> diff" standard applies to the whole bullet you touch (`hr-observability-layer-citation`).

Caught by `observability-coverage-reviewer`.

## Solution

All eight corrected inline in commit `1fa77dec2` (no scope-outs; every finding was `pr-introduced`):
tripwire rewritten to "1 of 4 + NARROW, don't retire"; ADR window corrected (opens at task **1.8**
for 3 of 4 signals; 5.3 deletes **three** branches across two files); heartbeat clause corrected;
back-pointer tripwires added at both `cloud-init.yml` sites; `:1352 → :1364`; plan's two ship-gate
sections restored; spec FR2/FR3 re-synced (FR2 had **demanded the host-count rot the plan forbids**);
page rate corrected; AC11 made API-checkable rather than inbox-checkable.

## Key Insight

**A PR that exists to delete a false comment is not immune to writing one — it is *primed* to.** The
author is deep in a corrected mental model, writing confident replacement prose, and the upstream
doc that seeded the original error (here: ADR-096's singular *"the fallback branch"*) is still there
seeding the next one. The three cheapest guards, in order: **count the M**, **reconcile the comment's
own carve-out against its N**, and **re-derive the prescription from the corrected count**.

## Session Errors

1. **Wrote a NEW false comment in the PR whose purpose was deleting a false comment** — the
   tripwire's "3 of 4" (actual: 1 of 4), "both soak events" (actual: one), and an UNSAFE "retire that
   alarm" prescription.
   **Recovery:** rewritten after 4 agents converged; ADR + spec + cloud-init back-pointers corrected
   in the same commit.
   **Prevention:** Learning A — enumerate + grep each of the M things; reconcile the comment's own
   `NOT affected` carve-out against the N; re-derive the prescription.
2. **My +5-line rewrite broke a `:1352` cross-ref — in the PR about comment rot.**
   **Recovery:** `1352 → 1364`.
   **Prevention:** Learning B — grep `<basename>:[0-9]` after any line-count change.
3. **AC4 was vacuous** (extractor anchored below the comment it policed); **AC3b returned 18 not 1**
   (dropped awk pipe); **AC8 used a two-dot diff** (30 files of base drift).
   **Recovery:** positive-first AC over an `NR`-scoped comment range, verified to fail pre-fix; awk
   pipe restored; three-dot.
   **Prevention:** Learning D — run EVERY AC against the pre-fix tree; never generalize a verifier
   from one AC to an adjacent scope.
4. **Offered `terraform validate` as TR1 evidence one bullet after discrediting the preview probe for
   the identical fallacy.**
   **Recovery:** TR1 restated as one-leg + the OSS-vs-SaaS gap named.
   **Prevention:** Learning E — re-run the proxy test on every remaining piece of evidence.
5. **Cut `## User-Brand Impact` + `## Observability` out of the plan during the DHH trim** — both are
   ship gates.
   **Recovery:** restored, with the mute-coupling vector `user-impact-reviewer` surfaced.
   **Prevention:** Learning F — re-run the gate predicates after a simplicity trim.
6. **Claimed the C4/Sentry gap was "filed as a spin-off" when I had not filed it.**
   **Recovery:** filed #6436.
   **Prevention:** never write "filed" without the issue number in the same edit.
7. **Understated the page rate to the operator as "~2-3/day"** when the emit is deploy-rate-bound
   (~7-9 events/day observed; 9 in the last 24h). The operator ruled on the wrong number (the
   rationale was unaffected, but the number fed a decision).
   **Recovery:** corrected in the Risks table.
   **Prevention:** derive a rate from the EMIT MECHANISM (trigger × fleet), not from a trailing
   sample average over an assumed window.
8. **#6437's filed fix was unimplementable** — the `SENTRY_*` creds come from the very Doppler that
   is absent on that path, so moving the emit changes nothing; and I missed the strictly-worse
   sibling (prefetch soft-fails at `:711` → gate evaluates → Sentry POST skipped at `:633` → deploy
   completes **GREEN** with a real degradation and no page).
   **Recovery:** amended + retitled #6437.
   **Prevention:** when filing an observability gap, trace the emit's **credential source**, not just
   its call site.
9. **Ran a plain `python3 -c yaml.safe_load` on a Terraform `templatefile()` cloud-init.yml** and
   briefly read the parse error as my own regression.
   **Recovery:** control-tested `origin/main` (fails identically at `:664`).
   **Prevention:** already documented — validate the RENDERED output; the raw file always fails on
   un-rendered `${...}`.

## Related

- Sibling (mechanism): [2026-07-15-sentry-event-frequency-threshold-unreachable-and-data-source-scope-403.md](./2026-07-15-sentry-event-frequency-threshold-unreachable-and-data-source-scope-403.md)
- Extends: [2026-06-18-doc-insertion-stales-cross-artifact-line-citations.md](./best-practices/2026-06-18-doc-insertion-stales-cross-artifact-line-citations.md) (cross-artifact → within-file)
- Spin-offs from the same session: **#6435** (zot-soak-6122.sh is blind to 2 of 4 signals → can
  false-PASS the irreversible GHCR-retirement gate — higher value than the fix itself), **#6436**
  (Sentry unmodeled in C4), **#6437** (ci-deploy Sentry-dark paths), **#6429** (sibling
  `sandbox_startup_failure` may share the unreachable-threshold defect), **#6427** (retargeted: 5.3
  must retire/re-point the soak).
