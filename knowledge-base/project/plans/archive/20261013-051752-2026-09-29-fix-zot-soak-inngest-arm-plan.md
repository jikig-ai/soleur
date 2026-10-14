---
title: "fix(followthroughs): retarget the zot-soak-6122 inngest sample arm onto dedicated-host boot evidence"
date: 2026-09-29
slug: fix-zot-soak-inngest-arm
branch: feat-one-shot-9097-zot-soak-inngest-arm
issue: 9097
closes: [9097]
refs: [6122, 6129, 8714, 8503, 6500, 8651, 8036]
type: fix
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix(followthroughs): retarget the zot-soak-6122 inngest sample arm onto dedicated-host boot evidence

## Enhancement Summary

**Deepened on:** 2026-09-29
**Sections enhanced:** Proposed Solution, Implementation Phases, Dependencies & Risks
**Research agents used:** inline orchestrator verification (pipeline context — no Task spawning);
deepen-plan halt gates 4.6 (User-Brand Impact), 4.7 (Observability), 4.8 (PAT-shape), 4.9 (UI
wireframe), 4.10 (Encryption Posture), 4.11 (Guard Contract, `lint-guard-contract.py` green) all
run and pass; Phase 4.4 precedent-diff, 4.45 verify-the-negative, and post-edit self-audit run
inline.

### Key Improvements

1. **Verify-the-negative pass confirmed the load-bearing premises:** `deploy-inngest-image.yml` is
   the only file that *sends* the `deploy inngest` verb (the `deploy inngest` strings in
   `scheduled-inngest-health.yml`, `build-inngest-bootstrap-image.yml`, `cloud-init.yml`,
   `inngest.tf` are all comments/prose); its `push` job is gated `if: github.event_name ==
   'workflow_dispatch'` (2026-09-14 push run concluded `skipped`), and its last real dispatch was
   2026-09-09T12:08:11Z. `restart-inngest-server.yml` sends `restart inngest _ latest` — a restart
   verb with no pull. `registry_pull_event` fires only inside `pull_image_with_fallback`.
   `inngest_quiesced_*_refused` is the scheduler-side chokepoint (`ci-deploy.sh`
   `verify_inngest_quiesced` + `final_write_state`), so even a dispatched deploy refuses.
2. **NB1/NB3/NB6 spec-derivation pinned to substitution, not append:** the stub curl matches
   COUNTS_SPEC keys in order, first match wins — a spec that *appends* `$Q_ZOTING=0` after
   HEALTHY's `$Q_ZOTING=5` still reads 5 and the row never goes RED. The derivation must be bash
   substitution (`${HEALTHY/$Q_ZOTING=5/$Q_ZOTING=0}`), the same shape `G6_NOEV` uses.
3. **All live citations verified:** #6122/#6129/#8714/#8651 OPEN, #6500 CLOSED, #8503 OPEN (T1 is
   literally the `INNGEST_ZOT` denominator), PR #8660 `mergedAt=2026-09-24T03:22:41Z` (the START
   anchor the script reads live), PR #8488 merged. `scripts/zot-soak-6122-arms` is a real
   test-all.sh shard leg (suite-shard-legs.tsv leg 1). `semver:patch` and `follow-through` labels
   exist.

### New Considerations Discovered

- No existing suite row asserts on the `inngest=<n>` output substring — the verdict-line rewording
  to `inngest-boots=` breaks no current assertion; only `FAIL(insufficient-sample)` is pinned.
- The existing thin-sample row (~line 319, `Q_ZOTWEB=1`) still reds post-fix but only exercises
  the *web* leg; the inngest leg's thin-evidence coverage is NB3 (denominator-deleted mutant) —
  its comment should be re-scoped accordingly in the same test edit.
- `FAIL(insufficient-sample)`'s "(need >=3 each)" threshold prose must become per-leg (web needs
  `>=$MIN_SAMPLE`, inngest needs `>=1` boot) — a single shared threshold is now factually wrong.

## Overview

`scripts/followthroughs/zot-soak-6122.sh` arm (b) requires `ZOT_INNGEST >= MIN_SAMPLE` (3), counted
as Sentry `feature:supply-chain op:image-pull registry:"zot" image:"inngest"`. The only emitter of
that event is `registry_pull_event` in `apps/web-platform/infra/ci-deploy.sh`, reached only via
`ci-deploy.sh deploy inngest`, which only a manual `deploy-inngest-image.yml` dispatch sends to the
co-located web-host scheduler — quiesced since the 2026-09-15 dedicated-host cutover (`op=quiesce-web`).
Its last run was 2026-09-09, before the re-armed soak window (`START=2026-09-24T03:22:41`). The arm
is structurally unreachable, so the soak cannot PASS after its `earliest` (2026-10-01T03:22:41Z),
which blocks #6129 (WARN→ENFORCE) and ADR-096 5.6 (#8714).

The dedicated inngest host's zot-served pull happens at boot and already reports
`stage:"inngest_zot" host_name:"soleur-inngest"` — counted by the existing `INNGEST_ZOT`
denominator arm (which FAILs on 0). This plan retargets arm (b)'s inngest leg onto that
already-fetched count (`INNGEST_ZOT >= 1`), retires the `image:"inngest"` deploy-pull query, and
pins the new contract in the exit-code harness.

## Problem Statement / Motivation

Measured 2026-09-28 (issue #9097): `FAIL(insufficient-sample): zot-served pulls web=100 inngest=0
(need >=3 each)` — while in the same window the dedicated host WAS zot-served (2026-09-27 boot,
server 167651172, `stage=inngest_zot` on Better Stack). The only way to satisfy the arm as written
is to dispatch deploys into an intentionally quiesced scheduler — the explicitly-wrong fix.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 9097` → **OPEN**, no `closedByPullRequestsReferences`, label
  `priority/p2-medium`. Premise fresh.
- `apps/web-platform/infra/ci-deploy.sh`: `registry_pull_event()` is the only `op:image-pull`
  emitter; the `zot` breadcrumb fires inside `pull_image_with_fallback` only. No other file calls
  `registry_pull_event` (repo grep).
- `deploy-inngest-image.yml` sends `deploy inngest <ref> <tag>` to `deploy.soleur.ai/hooks/deploy`
  — the co-located web-host scheduler — and only on `workflow_dispatch` (the `push` trigger's job
  is gated `if: github.event_name == 'workflow_dispatch'`; its 2026-09-14 push run concluded
  `skipped`). Last real dispatch: 2026-09-09T12:08:11Z (`gh run list`), before the soak START.
- `restart-inngest-server.yml` sends `restart inngest _ latest` — restarts the CURRENT image, no
  pull, no `image-pull` event (grep: no `registry_pull`/`image-pull` in restart/watchdog
  workflows).
- `build-inngest-bootstrap-image.yml`'s header comment says "the deploy webhook fires: `deploy
  inngest …`" but its only curl calls are Slack notifications — the comment documents the manual
  flow, not a sender. Even if it did fire, the chokepoint is the quiesced scheduler's
  `inngest_quiesced_*_refused`, not the sender list.
- #8503 (OPEN) records that the `INNGEST_ZOT` denominator itself was a reversible judgment call
  of PR #8488 (decision T1) — see Dependencies & Risks for the coupling.
- The dedicated host emits `soleur-boot-emit inngest_zot info` from
  `apps/web-platform/infra/cloud-init-inngest.yml` (~line 1105; `HOST_NAME='soleur-inngest'` ~line
  411), matching the soak's `INNGEST_ZOT` query `stage:"inngest_zot" host_name:"soleur-inngest"`.
- #6122 tracker directive unchanged-compatible: `script=…/zot-soak-6122.sh
  earliest=2026-10-01T03:22:41Z secrets=SENTRY_ACTIONS_RO_TOKEN,GH_TOKEN`. Same script, same
  secrets, same window — the 2026-09-27 `inngest_zot` boot is already inside it. **No re-arm, no
  directive edit, no `earliest` move.**
- ADR corpus check (proposed mechanism): no ADR pins arm (b)'s per-image deploy-pull evidence.
  ADR-096 names only "the soak's insufficient-sample arm" generically (line ~386) and carries an
  amendment convention (`## Amendment YYYY-MM-DD (#issue)`); ADR-169 records operand retirements.
  Nothing in an ADR's Decision/Alternatives rejects this retarget.
- Nothing else greps the soak for `ZOT_INNGEST`/`image:"inngest"`: the op-contract test
  (`apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`) mentions
  `ZOT_INNGEST` in a comment only; its pins cover FAIL_QUERIES parity, emitted stages, and the
  `stage` tag key — all untouched by this change.

### Property List (Phase 0.6b — the ask restated as properties)

- **P1:** arm (b)'s inngest leg must be satisfiable by evidence normal operation actually produces
  post-cutover — the dedicated host's zot-served fresh boot (`inngest_zot`), not a deploy-pull
  event nothing emits.
- **P2:** a window with zero inngest evidence must still not PASS (vacuity protection — the
  existing `INNGEST_ZOT == 0 → FAIL` denominator plus, with this fix, the sample leg itself).
- **P3:** no new emitter and no dispatch into the quiesced scheduler; no host-side change
  (cloud-init is once-per-instance and `user_data` is `ignore_changes`-pinned — a new emitter
  would not even take effect without a host replace, and a restart does not pull).
- **P4:** the suite must pin the retarget: zero-evidence FAILs; accepted evidence counts; the
  retired `image:"inngest"` operand stays out of code lines and out of issued queries.

### Cut List (Phase 0.6b)

- **Add an `op:image-pull registry:"zot" image:"inngest"` emitter to the dedicated host's
  restart/deploy path** (issue's alternative direction) — CUT: P1 is already bought by the
  existing `inngest_zot` beacon the soak counts; a new emitter is host IaC (`cloud-init-inngest.yml`
  is baked, `ignore_changes`-pinned), takes effect only on a host replace, and would emit
  `image-pull` for restart operations that do not pull — a forged-shape signal.
- **Re-arm START / move `earliest`** — CUT: not needed; in-window `inngest_zot` evidence already
  exists (2026-09-27), and moving START would drop real events from the window (the START-anchor
  arm exists to forbid exactly that).
- **Dispatch three `deploy-inngest-image.yml` runs** — CUT: the wrong fix per the issue; it also
  does not work (the job targets the quiesced scheduler, which refuses with
  `inngest_quiesced_*_refused`).

### Applicable institutional learnings

- `2026-09-24-the-gate-the-issue-blamed-was-never-reached.md` — measure whether the mechanism's
  branch ever executed; here the arm's required *input* can never arrive (inverse of the same
  failure class: an arm whose evidence no reachable path emits).
- `2026-09-21-curl-retry-flags-…-stubs-were-looser-than-the-code.md` (same file, PR #8488) — the
  COUNTS_SPEC stub matches URL substrings; a widened/renamed query still answers. The suite's
  `exact_*_query` decoded-URL assertions are the counter — reuse that shape for the residual-zero
  URL pin (assert the issued queries, not just the source text).
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — mutation
  matrix needs a row targeting the guard's own dispatch and a non-canonical must-PASS input.
- `followthrough-convention.md` §soak — "require a positive liveness marker before treating zero
  bad events as PASS"; `inngest_zot` IS that marker for the dedicated host.
- `scripts/followthroughs/zot-soak-6122.sh` header conventions — name-anchored comments (never
  `:NNN`), hardcoded floors with no knobs, comments may name retired operands but code lines must
  not, `SOAK_MIN_PASSES` bumps in the same edit as added rows.

Note: `lane:` — spec lacks a valid `lane:` (no spec.md precedes this pipeline plan) — defaulted to
`cross-domain` (TR2 fail-closed).

### Relevant files

- `scripts/followthroughs/zot-soak-6122.sh` — the gate. `ZOT_INNGEST` sites (verified by grep):
  the `image:"inngest"` query (~line 382), the two-element TRANSIENT guard loop (~line 384), the
  sample `if` (~line 476), and three message interpolations (~lines 477, 530, 673). `INNGEST_ZOT`
  is assigned at ~line 458, before the sample arm — in scope for reuse.
- `scripts/followthroughs/zot-soak-6122.test.sh` — PATH-stub harness (`curl`/`gh` stubs +
  COUNTS_SPEC). `Q_ZOTING='image%3A%22inngest%22'` (~line 202) appears in `HEALTHY` (~line 215)
  and the spec strings at ~lines 221, 301, 308, 319. `SOAK_MIN_PASSES=70` at ~line 819.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
  — gets a short amendment recording the evidence retarget (the soak gates 5.6).
- `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` — comment-only
  touch-up (lines ~252-253 describe the sample queries); assertions unaffected.

### Open Code-Review Overlap

None — queried 87 open `code-review` issues; no body names the planned files.

## Hypotheses

Phase 1.4 fired on the token `SSH` in the task text ("never prescribe SSH"). This is not a
network-connectivity defect; the failure is a measurement-arm whose evidence path no longer
exists. Layer checks, each opted out with its artifact:

1. **L3 firewall/DNS** — not applicable: the soak ran fine 2026-09-28 and returned
   `FAIL(insufficient-sample)` with `web=100`, proving Sentry egress, the token, and the query
   path all work. Artifact: the measured interim run quoted in #9097.
2. **L7 TLS/proxy** — same artifact: the Sentry API answered 200-shaped pages (counts, not
   TRANSIENT).
3. **L7 application** — not a service failure: verified statically that no emitter is reachable
   (`registry_pull_event` grep; `deploy-inngest-image.yml` dispatch-only + last run 2026-09-09)
   rather than hypothesizing one.

The sole live hypothesis — "the arm is unreachable because its only emitter is gated behind a
quiesced scheduler" — is confirmed, not hypothesized.

## Proposed Solution

Adopt the issue's preferred direction, in the "make it satisfiable by `INNGEST_ZOT >= 1`" form:

1. **Retire the `image:"inngest"` sample query.** Delete `ZOT_INNGEST=$(sentry_count
   'feature:supply-chain op:image-pull registry:"zot" image:"inngest"')`. Nothing emits that
   event post-cutover, so the count can only ever read 0 — a permanently-failing leg whose verdict
   text misleads every sweep comment.
2. **Arm (b) keeps two legs, re-sourced:** `ZOT_WEB >= MIN_SAMPLE` (web rolling-deploy pulls —
   still emitted by `ci-deploy.sh deploy web`, which produced `web=100` in-window) **AND**
   `INNGEST_ZOT >= 1` (the already-fetched `stage:"inngest_zot" host_name:"soleur-inngest"`
   count). The inngest floor is a hardcoded `1`, not `MIN_SAMPLE` and not a knob — the dedicated
   host pulls zot only at boot and boots once per host-replace, so `>= 3` would recreate this exact
   unreachable-arm defect; mirroring the `APP_ZOT` arm's documented rationale ("a knob's only
   useful value here is 1").
3. **Keep the leg even though the denominator already FAILs at `INNGEST_ZOT == 0`.** The leg is
   redundant in the current order, deliberately: it keeps every verdict line reporting the inngest
   evidence, and it survives a deletion of the denominator arm — a non-hypothetical scenario:
   open issue #8503 (T1) records that the `INNGEST_ZOT` denominator was itself a reversible
   judgment call from PR #8488. If T1 is ever reversed, the sample leg is what still refuses a
   zero-inngest-evidence window.
4. **Update verdict text** so no line reports a deploy-pull count for inngest: the
   `FAIL(insufficient-sample)` line, the `FAIL(blocked)` line, and the `PASS` line report
   `inngest-boots=$INNGEST_ZOT` (or equivalent wording that names the evidence class) instead of
   `inngest=$ZOT_INNGEST`. The `insufficient-sample` threshold prose must also become per-leg —
   `(need >=$MIN_SAMPLE each)` is factually wrong once the floors differ (web `>=$MIN_SAMPLE`
   deploy-pulls, inngest `>=1` boot).
5. **Update the file's own documentation:** arm (b)'s header comment, the `(b)` bullet in the
   top-of-file contract, and the `MIN_SAMPLE` comment — each must say the inngest exercise proof is
   the dedicated host's zot-served boot, why the deploy-pull leg retired (#9097, quiesced
   scheduler), and that `image:"inngest"` is a retired sample operand that must not be re-added
   (comment-prose is allowed to name it; the residual-zero pin scans code lines only).
6. **ADR-096 amendment** (one short `## Amendment 2026-09-29 (#9097)` section): record that the
   inngest exercise evidence for the 5.6 gate moved from per-image deploy-pull counts to the
   dedicated host's `inngest_zot` boot beacon, and why (dedicated-host cutover quiesced the only
   `deploy inngest` sender).

## Technical Considerations

- **Ordering:** `INNGEST_ZOT` is computed (~line 458) before the sample arm (~line 476) — reuse is
  free, no second Sentry query, no change to the TRANSIENT guard on it (its `=~ ^[0-9]+$` guard
  already covers the reuse).
- **The web leg is untouched.** `ZOT_WEB` still queries `op:image-pull registry:"zot"
  image:"web"`; the TRANSIENT guard collapses to `ZOT_WEB` alone (keep whichever minimal form the
  file's style supports — the constraint is only that the sentinel is guarded before arithmetic).
- **`MIN_SAMPLE` semantics narrow to the web leg** — its comment and the `ZOT_SOAK_MIN_SAMPLE`
  override docs must say so.
- **Vacuity is preserved twice.** `INNGEST_ZOT == 0` still FAILs at the denominator; the new leg
  FAILs a zero-evidence window again at arm (b). Nothing about `FAIL_QUERIES`, `WEB_FATAL`,
  `RETIRED_QUERIES`, `APP_ZOT`, the START anchor, or the two blocker arms changes — the
  op-contract test and `FAIL_QUERIES` cardinality floors stay green untouched.
- **No host/workflow/Terraform changes.** The diff is confined to the soak script, its test
  harness, the op-contract test's comment, and the ADR note. No `deploy inngest` dispatch, no
  cloud-init edit, no scheduler interaction.
- **Interface contract unchanged:** same env (`SENTRY_ACTIONS_RO_TOKEN`, `GH_TOKEN`), same exit
  semantics (0/1/TRANSIENT), same directive fields on #6122.

## Files to Edit

- `scripts/followthroughs/zot-soak-6122.sh` — retarget arm (b), retire the query, update messages
  and comments per Proposed Solution.
- `scripts/followthroughs/zot-soak-6122.test.sh` — new fixtures/rows + `SOAK_MIN_PASSES` bump in
  the same edit (see Test Scenarios).
- `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` — comment-only:
  the ~line 252-253 remark about `ZOT_INNGEST` sample queries stays true for `ZOT_WEB`; rephrase
  so it does not cite a removed variable.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
  — append the `#9097` amendment.

## Files to Create

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst case is the #6122
  soak closing (or staying open) on wrong evidence, which delays or mis-times the internal
  GHCR-retirement completion gate (#6129 / ADR-096 5.6). No user surface is touched.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the change
  reads the same Sentry org with the same read-only token over the same window; it removes one
  query and reuses another.
- **Brand-survival threshold:** `none`

## Observability

The deliverable IS an observability instrument; its own observability is the daily sweep verdict.

```yaml
liveness_signal:
  what: "the soak's verdict line, posted by scheduled-followthrough-sweeper.yml as a comment on #6122 — FAIL lines name the failing arm and its counts (e.g. FAIL(insufficient-sample) with web= and inngest-boots=)"
  cadence: "daily, from earliest=2026-10-01T03:22:41Z"
  alert_target: "#6122 tracker comments (the sweep's established channel)"
  configured_in: ".github/workflows/scheduled-followthrough-sweeper.yml + the followthrough directive on the #6122 issue body"
error_reporting:
  destination: "the verdict comment on #6122; exit 2 TRANSIENT on probe failure (Sentry/GitHub unreachable), never a counted verdict"
  fail_loud: "FAIL(<arm>): and TRANSIENT: prefixed lines on the tracker comment"
failure_modes:
  - mode: "the retargeted leg still cannot be satisfied (no inngest_zot boot in-window)"
    detection: "the sweep's daily FAIL(no-inngest-freshboot-evidence) comment — unchanged arm"
    alert_route: "#6122 comment thread"
  - mode: "the retired image:\"inngest\" operand is reintroduced on a code line"
    detection: "the new residual-zero suite row + the issued-URL assertion"
    alert_route: "CI (scripts/zot-soak-6122-arms suite leg)"
logs:
  where: "sweeper workflow run log + #6122 comment history"
  retention: "GitHub Actions run retention; issue comments permanent"
discoverability_test:
  command: rg -l 'host_name:"soleur-inngest"' scripts/followthroughs/zot-soak-6122.sh
  expected_output: zot-soak-6122.sh
```

Follow-through enrollment: unchanged — the existing directive on #6122 (same script, secrets, and
`earliest`) already enrolls this probe; no new soak-gated close criterion is introduced.

## Guard Contract

### Guard 1 — retargeted inngest sample leg (arm b) and its residual-zero pins

**Property.** A soak window with zero dedicated-host zot evidence can never produce exit 0; the
inngest leg of arm (b) is satisfied only by `INNGEST_ZOT >= 1` (the `stage:"inngest_zot"
host_name:"soleur-inngest"` count), and the retired `image:"inngest"` deploy-pull operand appears
on no code line and in no issued query.

**Assembly.** `zot-soak-6122.sh`'s single verdict path: the `INNGEST_ZOT` query site, the
denominator arm (`INNGEST_ZOT == 0 → FAIL(no-inngest-freshboot-evidence)`), the sample arm's
inngest leg, and the file's single `exit 0` at the PASS line — the chokepoint every member gates.
Residual-zero scope: every comment-stripped code line of the file and every URL the stub curl logs
during a PASS run.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Restore `image:"inngest"` deploy-pull counting as arm (b)'s inngest leg (revert the retarget) | RED — a fixture with `soleur-inngest=1`, zero `image:"inngest"` events, and all else healthy must FAIL where the fixed script PASSes |
| 2 | Delete the denominator arm's `if (( INNGEST_ZOT == 0 ))` FAIL block, keeping the `INNGEST_ZOT` query (targets the guard's own dispatch/redundancy) | RED — a `soleur-inngest=0` window must still exit 1 via the sample leg's `FAIL(insufficient-sample)` |
| 3 | Drop the inngest leg from arm (b) entirely (remove the `||` clause) AND delete the denominator FAIL block — the vacuity the guard exists to prevent, expressed as the mutation that reaches it | RED — a `soleur-inngest=0` window must never reach `exit 0`; the suite asserts at least one arm refuses |
| 4 | Weaken the leg — `INNGEST_ZOT -lt 1` → `-lt 0`, or drop the `host_name:"soleur-inngest"` filter so a colocated web host's `inngest_zot` counts | RED — the `soleur-inngest=0` fixture (and the colocated-only `G6_COLOC` variant for the filter) must FAIL |
| 5 | Harness row (suite, not guard): COUNTS_SPEC stops answering the host-pinned query | RED — stub 500 → exit 2 TRANSIENT, never a verdict (existing row 5 shape) |
| 6 | Harness row (must-PASS, non-canonical): `soleur-inngest=2` — more boots than the floor needs | PASS — proves the gate accepts above-floor evidence and is not wired to refuse |

**Anchor.** The floor counts live Sentry events; a one-diff weakening must change the query clause
AND the floor together — the exact-clause pin (`exact_inngest_query`, decoded-URL assertion) keys
on the literal `stage:"inngest_zot" host_name:"soleur-inngest"`, so substitution inside the commit
is caught. Outside the commit, the events themselves live in Sentry (forgeable with the public DSN —
disclosed; the PASS line's Better Stack corroboration instruction is unchanged).

## Implementation Phases

### Phase 1 — Failing tests first (TDD RED)

In `scripts/followthroughs/zot-soak-6122.test.sh` (all in one edit with the `SOAK_MIN_PASSES`
bump, per that file's same-edit convention):

0. **Ordering (matters for a readable RED):** do NOT remove `$Q_ZOTING=5` from `HEALTHY` and the
   legacy spec strings in this phase. The unfixed soak still issues the `image:"inngest"` query;
   dropping its COUNTS_SPEC key early makes the stub 500 every HEALTHY-based row → TRANSIENT,
   burying the new rows' semantic REDs. Removal lands in Phase 2's same commit, after GREEN.
1. **NB1 (accepted evidence — the defect's RED row):** spec derived from HEALTHY by bash
   substitution — `${HEALTHY/$Q_ZOTING=5/$Q_ZOTING=0}` — NOT by appending: the stub curl matches
   COUNTS_SPEC keys in order and first match wins, so an appended `=0` after HEALTHY's `=5` still
   reads 5 and the row can never RED (the same shape `G6_NOEV` already uses). Zero
   `image:"inngest"` events is the scenario normal operation now produces; blockers
   CLOSED/COMPLETED, `inngest_fixed=yes` → must exit 0 PASS. On the unfixed script the
   query is still issued and counts 0 → `FAIL(insufficient-sample)`, the exact verdict being
   fixed. Keeping `$Q_ZOTING=0` (not omitting the key) is what makes the RED a real verdict
   instead of a stub-500 TRANSIENT. NB3 and NB6 derive their specs the same substitution way.
2. **NB2 (zero evidence):** `G6_NOEV` (soleur-inngest=0) → still exit 1 —
   `FAIL(no-inngest-freshboot-evidence)` at the denominator. Pre-fix this row is already green;
   it is the requirement's baseline pin.
3. **NB3 (mutation — the leg carries vacuity alone):** on a soak copy with the denominator's
   `if (( INNGEST_ZOT == 0 ))` FAIL block deleted (assignment kept), run a `G6_NOEV`-derived spec
   that also carries `$Q_ZOTING=0` → must still exit 1 with `FAIL(insufficient-sample)`. Green on
   both old and new scripts (old: `image:"inngest"=0 < 3`; new: `INNGEST_ZOT=0 < 1`) — it pins
   that SOME inngest leg refuses a zero-evidence window when the denominator is gone, which is
   the arm's redundancy contract.
4. **NB4 (residual-zero, source):** assert `image:"inngest"` appears on no comment-stripped code
   line of the soak (reuse the `SOAK_CODE`/`retired_hits` pattern) AND assert the sample `if`
   still names `INNGEST_ZOT` (the leg cannot be silently dropped — pairs with mutation row 3 of
   the Guard Contract). RED pre-fix on both halves.
5. **NB5 (residual-zero, runtime):** after a CLOSED/COMPLETED + `inngest_fixed=yes` run, assert
   `$URL_SINK` contains no line matching `image%3A%22inngest%22`. RED pre-fix (the query is
   issued at line ~382 before any verdict).
6. **NB6 (non-canonical must-PASS):** `soleur-inngest=2`, web=5, `$Q_ZOTING=0`, all else healthy →
   exit 0 PASS.
7. Bump `SOAK_MIN_PASSES` by the number of new assertions; extend its comment ("Raised 70 -> NN in
   the SAME edit…" convention).

Run `bash scripts/followthroughs/zot-soak-6122.test.sh` — NB1/NB4/NB5 must be RED.

### Phase 2 — Retarget the soak arm

In `scripts/followthroughs/zot-soak-6122.sh`:

1. Delete the `ZOT_INNGEST` query line; narrow the TRANSIENT guard to `ZOT_WEB`.
2. Change the sample `if` to require `ZOT_WEB >= MIN_SAMPLE` and `INNGEST_ZOT >= 1` (hardcoded
   floor 1, with the "no knob" rationale comment mirroring APP_ZOT's).
3. Update the three message interpolations (`FAIL(insufficient-sample)`, `FAIL(blocked)`, `PASS`)
   to report `inngest-boots=$INNGEST_ZOT`-style evidence, and update the arm (b) header bullet +
   MIN_SAMPLE comment + top-of-file contract bullet so they describe the boot-evidence leg and
   retire `image:"inngest"` by name.
4. In `scripts/followthroughs/zot-soak-6122.test.sh` (same commit, after GREEN): remove
   `$Q_ZOTING` from `HEALTHY` and the legacy spec strings (~lines 221/301/308/319) — the canonical
   healthy world no longer issues that query. Keep the `Q_ZOTING` constant itself: NB1/NB3/NB6
   reference it. In the same edit, re-scope the thin-sample row's comment (~line 316): post-fix it
   exercises only the *web* leg of the sample arm — the inngest leg's thin-evidence coverage is
   NB3's denominator-deleted mutant (a `soleur-inngest=0` window on the stock script reds at the
   denominator before the sample arm is reached).
5. Re-run the suite — GREEN.

### Phase 3 — Record and ship

1. Append `## Amendment 2026-09-29 (#9097)` to ADR-096 (evidence retarget; the soak still gates
   5.6; no behavior change to the authorization itself).
2. Comment-only fix to the op-contract test's stale `ZOT_INNGEST` remark.
3. Post a `gh issue comment` on #6122 recording the arm retarget so the next sweep verdict is
   interpretable in context (agent-run, no operator step).
4. PR body: `Closes #9097`, changelog section, `semver:patch`-appropriate description.

### Operating norms (encoded for the work phase)

- One PR for this fix.
- Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test,web-platform-typecheck` (CPU-contended
  machine): run `bash scripts/followthroughs/zot-soak-6122.test.sh` and
  `bash scripts/followthrough-exec-bit.test.sh` locally; rely on CI for the rest. Run the
  op-contract vitest file locally only if the machine tolerates it (`cd apps/web-platform && bun
  test test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` — static-analysis assertions,
  fast) — it reads the soak file it does not modify.
- Never `git merge` main into the branch; `git rebase origin/main` if BEHIND.

## Alternative Approaches Considered

| Option | Verdict |
|--------|---------|
| Drop `image:"inngest"` from arm (b) entirely (issue's other preferred sub-option) | Not chosen: keeps the same verdicts but loses the fail-closed second check and the per-image evidence on verdict lines. The kept-leg variant is strictly more fail-closed for zero extra queries. |
| New `op:image-pull image:"inngest"` emitter on the dedicated host's restart/deploy path (issue's alternative direction) | Rejected: P1 already provided by `inngest_zot`; the emitter is host IaC taking effect only on a host replace; restart paths do not pull, so the event would misreport. |
| Dispatch deploys into the quiesced web scheduler | Rejected (explicitly the wrong fix; the scheduler refuses `deploy inngest` with `inngest_quiesced_*_refused`). |
| Re-arm the soak window | Rejected: in-window `inngest_zot` evidence already exists; moving START drops real events (the START-anchor arm exists to forbid it). |

No deferred items requiring tracking issues.

## Acceptance Criteria

- [ ] No comment-stripped code line of `zot-soak-6122.sh` contains `image:"inngest"` (retired
  operand; comments may still name it as retired).
- [ ] Arm (b) requires `ZOT_WEB >= MIN_SAMPLE` AND `INNGEST_ZOT >= 1`; the identifier
  `ZOT_INNGEST` no longer exists in the file.
- [ ] Suite: a `soleur-inngest=0` window exits 1 — both on the stock script (denominator) and on a
  denominator-deleted mutant (the new leg) — and a `soleur-inngest>=1` + `image:"inngest"`-zero
  window reaches PASS. All four scenarios are committed rows.
- [ ] `SOAK_MIN_PASSES` raised in the same edit that adds the rows; the suite reports its raised
  floor.
- [ ] `FAIL(insufficient-sample)`, `FAIL(blocked)`, and `PASS` lines report the inngest leg as
  dedicated-host boot evidence, never as an `image:"inngest"` pull count.
- [ ] No `deploy inngest` dispatch, no workflow/`deploy-inngest-image.yml` change, no Terraform,
  no cloud-init or host-side change; the #6122 directive fields (`script`, `earliest`, `secrets`)
  are unchanged.
- [ ] ADR-096 carries the `#9097` amendment recording the evidence retarget.
- [ ] `bash scripts/followthroughs/zot-soak-6122.test.sh` and
  `bash scripts/followthrough-exec-bit.test.sh` pass locally; `scripts/zot-soak-6122-arms` CI leg
  green.

## Test Scenarios

- Given zero watched events, `web=5`, `inngest_zot(soleur-inngest)=1`, and **zero**
  `image:"inngest"` events, when the soak runs, then it reaches the blocker arms — and with both
  blockers CLOSED/COMPLETED, exits 0 PASS.
- Given `inngest_zot(soleur-inngest)=0` and `web>=MIN_SAMPLE`, when the soak runs, then it exits 1
  `FAIL(no-inngest-freshboot-evidence)` — and on the denominator-deleted mutant, still exits 1
  `FAIL(insufficient-sample)`.
- Given `inngest_zot(soleur-inngest)=2`, when the soak runs against an otherwise-healthy window,
  then it PASSes (must-PASS input differing from the canonical fixture).
- Given a mutation restoring `image:"inngest"` deploy-pull counting, when run against the
  accepted-evidence fixture, then it FAILs — proving the retarget, not its absence, passes.
- Verify locally: `bash scripts/followthroughs/zot-soak-6122.test.sh`; CI covers the remainder per
  the LEFTHOOK_EXCLUDE norm.

## Domain Review

**Domains relevant:** engineering (assessed inline — pipeline context with no Task spawning; the
eight-domain sweep against brainstorm-domain-config.md yields no marketing/product/legal/sales/
finance/support/operations implications for a soak-script retarget; engineering is the owning
domain).

### Engineering

**Status:** reviewed (orchestrator self-assessment; no leader Task spawn available in this
subagent context)
**Assessment:** infra-adjacent measurement change on an existing fail-closed gate; no new
substrate, boundary, or trust surface. Main risk is reintroducing vacuity — mitigated by the Guard
Contract matrix and the suite's mutation rows.

## Success Metrics

- The soak can return exit 0 on a healthy fleet from 2026-10-01T03:22:41Z without any dispatch
  into the quiesced scheduler (in-window `inngest_zot` evidence already exists).
- A zero-inngest-evidence window still exits 1 — never TRANSIENT (real condition) and never 0
  (vacuous).

## Dependencies & Risks

- Depends on the existing `inngest_zot` emitter (`cloud-init-inngest.yml`) staying live — pinned by
  the op-contract test's emitted-stages legs and the `exact_inngest_query` clause check.
- **#8503 coupling (recorded, not blocking):** open issue #8503 keeps or reverses PR #8488's two
  judgment calls; T1 is the `INNGEST_ZOT` denominator itself. This plan assumes T1 stands (the
  soak keeps requiring dedicated-host evidence) — consistent with the issue's own analysis. If T1
  is ever reversed (denominator deleted), arm (b)'s new inngest leg still refuses a zero-evidence
  window — one of the reasons the leg is kept rather than dropped, and exactly what mutation row
  NB3 pins.
- Risk: a future operator re-arms START to a window with no host replace → `INNGEST_ZOT=0` → FAIL.
  Same semantics as today's denominator; unchanged by this plan.
- The change narrows `MIN_SAMPLE`'s meaning to the web leg; an out-of-date operator memory of
  "3 per image" is corrected by the amended comments and the ADR note.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails deepen-plan
  Phase 4.6 — filled above.
- The soak's comment conventions are load-bearing: name-anchored (never `:NNN`), comments may name
  retired operands but code lines must not (the residual-zero rows enforce the boundary), and the
  `SOAK_MIN_PASSES` floor moves only in the same edit as the rows it counts.
- Do not "normalize" query prefixes: `stage:` queries stay bare, `feature:`/`op:` queries stay
  prefixed — the header's prefix-asymmetry warning still applies to every line this plan touches.

## References & Research

- Issue: #9097 (defect + fix directions); tracker: #6122; downstream gates: #6129, #8714 (ADR-096
  5.6), #8503.
- `scripts/followthroughs/zot-soak-6122.sh` (the gate) and `scripts/followthroughs/zot-soak-6122.test.sh`
  (PATH-stub harness; `SOAK_MIN_PASSES=70`).
- `apps/web-platform/infra/ci-deploy.sh` `registry_pull_event` (sole `op:image-pull` emitter);
  `.github/workflows/deploy-inngest-image.yml` (dispatch-only sender to the quiesced scheduler).
- `apps/web-platform/infra/cloud-init-inngest.yml` — `soleur-boot-emit inngest_zot info` emit
  site; `HOST_NAME='soleur-inngest'`.
- Learnings: `2026-09-24-the-gate-the-issue-blamed-was-never-reached.md`,
  `2026-09-21-curl-retry-flags-…-stubs-were-looser-than-the-code.md`,
  `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`.
- Runbook: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` (soak
  trigger shape: positive liveness marker required before zero-bad-events can PASS).
