---
title: "feat(infra): schedule workspaces-luks-verify daily, with the failure-surfacing path a schedule requires"
date: 2026-08-03
type: feat
branch: feat-one-shot-6808-luks-verify-schedule
pr: 7196
refs: [6808, 6588, 6604, 6807, 6812, 7138]
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: "ADR-033 (amended — anti-circularity addendum; no new ordinal minted)"
---

# Schedule `workspaces-luks-verify`, and give it an alarm

> **Spec lacks valid `lane:`** — no `knowledge-base/project/specs/feat-one-shot-6808-luks-verify-schedule/spec.md` exists on this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-08-03 · **Gates run:** 4.5 (network-outage, fired), 4.6, 4.7, 4.8, 4.9, 4.10,
4.55 (no trigger) — all pass · **Panels:** CTO, CLO, code-simplicity, spec-flow-analyzer, plus a
verify-the-negative sweep (12 claims) and a precedent-diff sweep (11 patterns).

### Corrections this pass made to the plan's own first draft

1. **`mapper_path_override_refused` would have fired a P0 legal alarm for a config fault.** It exits
   **1**, not 3 (`luks-monitor.sh` uses `emit_and_die`), so an rc-first classifier routes it to
   `drift` → `type/security` + `priority/p0-critical` + a counsel re-evaluation pointer. Fixed by
   classifying **reason-first, rc-second**. Independently found by the exit-site enumeration and by
   spec-flow. The runbook's own §5 row already called it *"Config fault, not data loss."*
2. **The prescribed alarm `if:` cited the wrong half of its precedent.**
   `scheduled-realtime-probe.yml`'s producer-status-first form is its *heartbeat `status:`* — a
   positive gate on green. Its actual alarm `if:` (line 175) is `steps.probe.outputs.failure_mode != ''`,
   the bare-outputs #7138 shape. Pasting the heartbeat form into an alarm `if:` makes the alarm
   unreachable on every failure. The literal expressions are now written out (§Sharp Edges 2).
3. **`checkin_margin_minutes = 1440` would have made the Sentry layer blind to a single missed fire**
   — i.e. to all three modes it exists for. But dropping the margin alone re-introduces the #4189
   false page. Resolved by pairing margin `420` with `failure_issue_threshold = 2` (§Decision 3).
4. **Every non-200 health result was classed as a data-loss finding**, routing a Cloudflare-edge
   outage into the runbook §5 data-recovery table. Split STRUCTURAL → `readiness`,
   RETRYABLE-exhausted → `unavailable` — and the split needed a *mechanism*, since re-listing the
   codes is forbidden by AC10 (§Decision 2).
5. **The guards this PR adds would never have run on the PRs that break them** —
   `infra-validation.yml`'s `paths:` omits this workflow (§Decision 6a). Now Phase 1 step 1.0.
6. **Severity was assigned on legal salience, not user impact** — irreversible sole-copy data loss
   sat at p1 while an intact-data legal event sat at p0. Inverted per
   `hr-weigh-every-decision-against-target-user-impact`.
7. **`RESEND_API_KEY` was never named**, and a non-2xx from Resend exits 0 with only a `::warning::`
   — so an expired key would drop every page silently (§Decision 2).
8. **Three blocking legal gaps** the engineering framing missed entirely: the Article 30 register and
   the counsel audit's `claim_decay_trigger` both become **false on merge**, and absence detection is
   required because the decay trigger's defeat condition is absence, not failure (§Legal).

### Cuts this pass made (simplicity panel)

Extracted classifier + its test suite, a new ADR ordinal, the follow-through probe, the green-close
step and the two anti-spam mechanisms it forced, two of three `ci/*` labels, four ceremonial ACs, and
the hand-maintained C4 counts. Net: **13 declared files → 9; two new files → one.** Each cut is
recorded in §Files to Create / §Alternatives so a later reader does not re-add it.

### Verified, not assumed

All 12 negative/absolute claims in the plan were grep-confirmed against live files, and one resolved
an open conditional: `sentry-monitor-iac-parity.test.ts` enumerates **every** workflow `.yml` and
greps for `monitor-slug:` — no `scheduled-*` prefix filter — so it needs no edit, but it **will fail**
if the workflow declares a slug whose TF resource is absent. That coupling is now stated.

## Overview

`.github/workflows/workspaces-luks-verify.yml` is `workflow_dispatch`-only. Every run in its
history is manual — 8 runs, all `event=workflow_dispatch` (`gh run list --workflow=workspaces-luks-verify.yml`,
verified 2026-08-03). It is the only mechanical verification that web-1's `/mnt/data` is still on
the LUKS mapper. `WORKSPACES_LUKS_HEARTBEAT_URL` is unwired (#6808, OPEN), so the on-host daily
`luks-monitor` probe runs, succeeds, and pushes nothing. There is therefore **no automatic
verification of that surface at all**, while three published documents assert in the present tense
that the measure "is verified live by the `workspaces-luks-verify` check".

This plan adds a **daily `schedule:` trigger** and, in the same PR, the **failure-surfacing path
that a schedule requires**. The two are inseparable: `workflow_dispatch` implies a human dispatched
the run and is watching it. A schedule removes the watcher. Adding the cron alone would ship a
monitor whose failures land in a tab nobody opens — a check that cannot report, which is
observationally identical to one that passed
([`2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`](../learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md)) —
and *strictly worse than today*, because it would also make people believe the surface is monitored.

Three failure-surfacing layers, each covering a hole the others cannot see:

1. **Verdict classification → GitHub issue**, in three classes with three labels and three
   independent dedupe keys. The class split is not cosmetic: only one of the three is a legal
   event (see §Legal below).
2. **A Sentry Crons monitor** for the schedule itself. Without it, a schedule that silently *stops
   firing* produces no run, no failure, and no alarm — which is the claim-decay trigger's exact
   defeat condition, and the same shape one level up as the bug this PR fixes.
3. **A committed, executing test** that proves each failure branch can fire. A guard whose failure
   path has never been exercised pins nothing.

`Ref #6808`, never `Closes` — see §PR body.

## Premise Validation

Every premise cited by reference was checked against live state on 2026-08-03. Nothing was carried
on trust.

| Cited premise | Verification | Verdict |
|---|---|---|
| #6808 is OPEN | `gh issue view 6808` → `state: OPEN`, labels `priority/p1-high`, `type/bug`, `domain/engineering`, `type/security` | **Holds** |
| Draft PR #7196 exists on this branch | `gh pr view 7196` → `OPEN`, `isDraft: true`, `headRefName: feat-one-shot-6808-luks-verify-schedule` | **Holds** |
| Workflow is `workflow_dispatch`-only, all runs manual | `on:` block has only `workflow_dispatch:`; `gh run list` → 8 runs, every one `event=workflow_dispatch` | **Holds** |
| `claim_decay_trigger` §A3.4 | `knowledge-base/legal/audits/2026-07-counsel-review-6588.md` frontmatter, field `claim_decay_trigger` — verbatim: *"While #6808 is OPEN, `workspaces-luks-verify` is workflow_dispatch-only and no automatic verification of any kind exists… If no successful run lands within any trailing 30-day window while that clause stands, the clause MUST be re-tensed… or withdrawn."* | **Holds** |
| Published present-tense claim | `docs/legal/data-protection-disclosure.md` correction banner: *"it is verified live by the `workspaces-luks-verify` check"*; mirrored in `docs/legal/privacy-policy.md` and `docs/legal/gdpr-policy.md` | **Holds** |
| No LUKS-related `ci/*` label exists | `gh label list --limit 300` → 11 `ci/*` labels, none LUKS/workspaces-related | **Holds** |
| A real inventory baseline exists today | Run `30749271370` (2026-08-02) log: `SOLEUR_WORKSPACES_READYZ ready=true writable=true populated=true workspace_count=8 expected=8 capacity=use=6%,mount=rw` | **Holds** |
| Missing baseline is fail-closed, not vacuous green | `apps/web-platform/infra/luks-monitor.sh`, anchor `case "${WL_WORKSPACE_COUNT_EXPECTED:-}" in` → `''\|0\|*[!0-9]*) emit_readiness_and_die workspace_count_baseline_missing` (exit 3) | **Holds** |
| Precedents `scheduled-zot-restart-loop.yml` + `scheduled-realtime-probe.yml` are schedule + `issues: write` + `gh issue create` + `ci/*` label | Both read in full. Confirmed, plus 9 further sibling workflows | **Holds** |
| Repo is public (runner minutes free) | `gh repo view --json visibility` → `PUBLIC` | **Holds, and deliberately NOT used.** §Decision 1 rejects "minutes are free" as a cadence argument; the real recurring costs are the Sentry seat and the SSH exposure |
| ADR corpus | ADR-033's 2026-06-02 scope note licenses a credential-heavy infra cron in an ephemeral runner | **Holds — no new ordinal minted**; ADR-033 is amended instead (§Architecture Decision) |

**Mechanism vs. the ADR corpus** (`plan` Phase 0.6 item 4). The proposed mechanism is a
GHA-native `schedule:` trigger. The repo's canonical scheduling substrate is Inngest
(ADR-033), enforced mechanically by `.claude/hooks/new-scheduled-cron-prefer-inngest.sh`.
That hook does **not** fire here (it is scoped to `.github/workflows/scheduled-*.yml` files
absent from `origin/main`; this file matches neither condition), but the ADR still governs.
ADR-033's own 2026-06-02 scope note licenses this shape and is quoted in §Alternatives. The
GHA-native `schedule:` — as against ADR-033's Option-C `Inngest → workflow_dispatch` — is a
*further* step whose corollary no ADR records, which is why an ADR-033 **amendment** is a deliverable of this plan (§Architecture Decision).

## Research Reconciliation — Spec vs. Codebase

| Claim as briefed | Codebase reality | Plan response |
|---|---|---|
| "A can't-measure must not read as a clean pass" — implies new logic | The workflow **already** discriminates: rc 255 = "REACHABILITY failure… nothing has been proven", rc 127 = "TOOLING failure… nothing proven", rc 3 splits `PROBE-INTEGRITY` vs `READINESS/INVENTORY` by reason code | Do not invent a taxonomy. **Lift the existing one** into a machine-readable `outcome_class` output. Zero new judgement, and the operator-facing strings stay byte-identical |
| Two labels (finding vs can't-measure) | CLO review: only **at-rest drift** (rc 1 / other non-zero) fires counsel re-evaluation trigger (3). rc 3 readiness/inventory is data-loss-shaped ops, *not* the TOM claim. A two-way split lets a readiness issue swallow the first drift issue | **Three** classes / labels / titles / dedupe keys: `drift`, `readiness`, `unavailable` |
| Dedupe "as the precedents do" (`gh issue list --search`) | `scheduled-supabase-advisor-scan.yml` documents *why* it abandoned `--search`: *"the search API can return empty under some token contexts, which would file a fresh duplicate every single night."* | Dedupe **by label + exact title match via `jq`**, not `--search`. Cite the reason inline |
| `luks-monitor` runs daily on the host, so the mount is covered daily | True for steps 1-5 only. The readyz + inventory assert is behind `LUKS_MONITOR_ASSERT_READYZ`, **default OFF**, because `luks-monitor.service` carries `RequiresMountsFor=/mnt/data` and is structurally inert in the reboot hazard | The readyz + inventory dimension has **no daily coverage today at all**. Strengthens the case for daily, and is stated in the ADR |
| "Adding a schedule is the whole change" | `knowledge-base/legal/article-30-register.md` PA-1(g)(17) + PA-2(g)(21) record verification as two *dated past events*; the counsel audit's `claim_decay_trigger` asserts as fact that "no automatic verification of any kind exists" | Both become **false on merge**. Register + audit annotation are in scope and blocking (CLO) |
| No C4 impact expected | `knowledge-base/engineering/architecture/diagrams/model.c4`, `github -> sentry` edge: *"posts ok\|error check-ins from **6 workflows** — **3 GHA-`schedule:`-fired**… Of **51** cron monitors, **7** check in from here and 44 from webapp"* | Adding a 52nd monitor **falsifies four counts in one description**. C4 edit is mandatory, not optional |
| The workflow's YAML is free to restructure | `workspaces-luks-freeze.test.sh` AC7 greps the file **including comments** for `/api/health[a-z/-]*`; AC10 extracts the case-arm matching `^[[:space:]]*307\|[0-9\|]+\)`; `luks-monitor.test.sh` case (y) extracts the literal `grep -cE` verdict pattern out of this file | Three hard editing constraints. See §Sharp Edges |

## User-Brand Impact

**If this lands broken, the user experiences:** their workspace git data silently reverting off the
LUKS mapper — the #6812 failure mode, which has already happened once on this exact surface for
~27 minutes — with nothing detecting it, while the published page at `/legal/data-protection-disclosure`
continues to tell them the volume "is verified live by the `workspaces-luks-verify` check". The
concrete artifact is a published Article 32 statement that is false, and that stays false silently.
A *broken alarm* is worse than no alarm here, because it converts "unmonitored and known to be so"
into "unmonitored and believed monitored".

**If this leaks, the user's workspace git data is exposed via:** a seized, RMA'd or snapshot-imaged
Hetzner block volume. `model.c4` (`workspacesVolume`) records that store as **sole-copy** — "there
is no durable second copy anywhere (no upstream to rehydrate from)". Guest-side LUKS is the only
control between that disk image and every user's checked-out repository. If the mount reverts to the
retained plaintext `hcloud_volume.workspaces` (still attached-unmounted as the ADR-119 rollback
backstop, per the counsel audit's `accepted_residual`), the data is readable from the image.

**Brand-survival threshold:** `single-user incident`

The threshold is not chosen freshly here — `knowledge-base/legal/audits/2026-07-counsel-review-6588.md`
frontmatter already pins `brand_survival_threshold: single-user incident` on this exact surface, and
this plan inherits it. One user's repository read off a seized volume is a brand-survival event on
its own; no aggregate pattern is required.

`requires_cpo_signoff: true`. CPO sign-off is required at plan time before `/work` begins —
invoke the CPO domain leader if not already covered by Phase 2.5 carry-forward. `user-impact-reviewer`
will be invoked at review time.

## Decision 1 — Cadence: DAILY at `41 4 * * *` (04:41 UTC)

**Margin against the 30-day decay window: ~30×.** Stated precisely, because "30×" is the wrong
framing on its own: the decay trigger fires when *no successful run lands* in a trailing 30-day
window, so the metric that matters is **independent attempts per window**, not cadence-vs-window.

| Cadence | Attempts per 30-day window | Consecutive failures tolerated before the trigger is at risk | Detection latency for a silent revert |
|---|---|---|---|
| Weekly (`4×` margin) | 4 | 3 | ~7 days nominal |
| Every 3 days (`10×`) | 10 | 9 | ~3 days nominal |
| **Daily (`30×`)** | **~30** | **29** | **~24 h nominal** |

**The latency column is nominal, not a bound — do not quote it as one**, least of all in a legal
context. GHA `schedule:` jitter is measured in this repo at up to **339 minutes**, so a revert just
after a fire is realistically detected at ~29 h; if GitHub drops a fire entirely (recorded
2026-05-26), ~53 h. The ordering between cadences is unaffected, which is all the table is for.

**The strongest counter-position, steelmanned** (CTO). The at-rest state is *boot-immutable* —
`luks-monitor.timer`'s own header says so ("the mount topology is boot-immutable, so the steady-state
check is a once-a-day escrow + header-UUID re-test") and `luks-monitor.test.sh` asserts the timer must
**not** be a sub-daily poll. The only mutation source is a reboot or redeploy, roughly monthly. A
daily cron is therefore a poor proxy for an event-shaped signal; the "right" design would be a
post-deploy/post-reboot hook plus a weekly backstop — equal detection of the only real mutation
source at 1/7 the unattended-prod-root-SSH surface and 1/7 the flap noise.

**Rejected, on two facts that defeat its premise:**

1. **It restores the cadence the design already assumes, and #6808 is why that matters.** The host's
   daily probe currently has *no alarm channel at all*. Until #6808 closes, this workflow is the
   compensating channel for a **daily** push (the runbook's failure signal is literally *"a missed
   daily push = a dead probe"*). A compensating channel firing at 1/7 the rate of the thing it
   compensates for is a partial compensation dressed as a full one, and it makes retiring one
   against the other a judgement call rather than a swap.
2. **Half the probe is not boot-immutable.** `LUKS_MONITOR_ASSERT_READYZ` is default-OFF on the host
   and set to `1` only by this workflow, because `luks-monitor.service` carries
   `RequiresMountsFor=/mnt/data` — structurally inert in exactly the reboot hazard it would be
   argued for. So the readyz + inventory dimension has **zero** host-side coverage, and *inventory
   can shrink at any time*. The counter-argument's boot-immutability premise simply does not hold
   for the dimension this workflow uniquely covers.

Two supporting arguments, explicitly **not** load-bearing:

- *Attempt count, not cadence, survives failure.* GHA `schedule:` is best-effort — this repo has
  measured scheduled-dispatch jitter up to **339 minutes** late
  ([`2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons.md`](../learnings/2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons.md)),
  `cron-monitors.tf` records that *"On 2026-05-26 GitHub dropped the scheduled run ENTIRELY"*, and
  `ci/tunnel-connector-drift` exists because the bridge has flapped before. A multi-day bridge
  outage burns 2 of weekly's 4 attempts and 14 of daily's 30. Correct arithmetic, but it argues for
  *more attempts*, not for *daily* specifically — so it corroborates rather than decides.
- *Latency is the actual harm.* While the mount is reverted and undetected, three published
  documents contain a false Article 32 statement; ≤24 h beats ≤7 d.

**Deliberately NOT an argument: "runner minutes are free."** True (`gh repo view --json visibility`
→ `PUBLIC`), and it must stay out of the PR prose — it invites a reviewer to think cost is the axis.
Cost is **not** zero: see §Decision 3 (a $0.78/mo Sentry cron-monitor seat against a PAYG cap 13 days
from renewal) and the security note below.

**The real recurring cost, stated plainly.** This converts 8 lifetime operator-initiated root SSH
sessions into ~365/yr **unattended** sessions to production carrying a `prd_workspaces_luks` Doppler
token over the CF Tunnel. Same credentials and same path the apply workflows already use unattended,
so no new secret and no new trust boundary — but the exposure window moves from "operator-triggered"
to "always". This belongs in the PR body as one line. It is not a reason to prefer weekly on its own,
because weekly carries the same qualitative change at 1/7 the count.

**Sunset note (record in the workflow header, not as deferred scope).** When #6808 closes and the
Better Stack heartbeat is wired, the at-rest dimension becomes redundant with the host heartbeat and
only the readyz + inventory dimension justifies daily — **revisit the cadence then.**

**Slot choice `41 4 * * *`.** Off the top of the hour — the repo's 06:00 UTC slot is already
contended by five workflows, and GH Actions scheduling contention is worst at `:00`. 04:41 collides
with no existing cron (`0 3`, `0 6`, `0 7`, `0 18`, `23 8`, `17 * * * *`, `*/15`, `*/30`). It also
lands **after** the host's own `luks-monitor.timer` daily fire (`OnCalendar=daily` + `RandomizedDelaySec=1800`,
so ≤ 00:30 UTC), so the workflow's readyz assert follows the host probe rather than racing it.

**Revisit trigger, recorded in the workflow header, not deferred to an issue:** when #6808 lands and
the Better Stack heartbeat is wired, the heartbeat covers the mount dimension daily and this
workflow's cadence may be re-argued down to weekly for the readyz + inventory dimension alone. This
is a re-evaluation note, not deferred scope — nothing is being cut.

## Decision 2 — Three alarm classes, not two

The workflow already carries the whole taxonomy in its error strings. The change **lifts it into a
machine-readable output** and routes each class to its own label, title and dedupe key. Operator-facing
`::error::` text and every exit code stay byte-identical.

**One label, three titles.** All three classes share the single label `ci/luks-verify`; the class
lives in the **issue title**, which is what the dedupe key already keys on. Severity and routing come
from labels that already exist repo-wide. This is exactly the shape of
`scheduled-supabase-advisor-scan.yml` — one shared `ci/supabase-advisor` label, two titles, dedupe by
label + exact title — which this plan already cites as the dedupe precedent. Three bespoke labels
would give three dedupe keys the three titles already give, at the cost of three
`gh label create` calls and a colour convention that changes no behaviour.

| `outcome_class` | Trigger | Issue title / labels | Legal meaning |
|---|---|---|---|
| `pass` | rc 0, app health 200, verdict line present | — | Discharges the decay trigger for the day |
| `drift` | rc 1 with `not_mounted`, `mount_not_mapper`, `mapper_absent`, `device_not_luks`, `escrow_passphrase_mismatch`, `header_uuid_unreadable`, `cryptsetup_status_missing`, `mapper_device_link_missing`; or any non-zero rc not otherwise classified | `[ci/luks-verify] at-rest drift on /mnt/data` — `ci/luks-verify`, `type/security`, `priority/p0-critical`, `action-required` | **Counsel re-evaluation trigger (3).** The retained Article 32 claim is false from the moment of regression |
| `readiness` | rc 3 with `workspace_count_shortfall`, `readyz_not_ready`, **or an empty/unparsed reason**; or the app health endpoint returned a **STRUCTURAL** code (the existing `307\|401\|403\|404\|405\|525\|526` arm) | `[ci/luks-verify] readiness or inventory failure` — `ci/luks-verify`, `priority/p1-high`, `action-required` | Data-loss- or routing-shaped ops event, possibly Art. 33-adjacent. **Not** the TOM claim |
| `unavailable` | rc 255 (SSH transport), rc 127 (bundle/tooling), any PROBE-INTEGRITY reason on any rc (`readyz_gate_regression`, `readyz_unparseable`, `readyz_unreachable`, `readiness_helper_unavailable`, `workspace_count_baseline_missing`, `workspace_count_unreadable`, `mapper_path_override_refused`, `doppler_unreachable`), verdict line absent, **the app health endpoint still non-200 with a RETRYABLE code after the full attempt budget**, or an empty/missing class output | `[ci/luks-verify] could not verify — nothing proven` — `ci/luks-verify`, `priority/p1-high`, `action-required` | Not a legal event — the run proved nothing in either direction |

**Health-code split is load-bearing (CTO BLOCKER-2).** Routing every non-200 health result to a
"finding" would contradict the file's own reachability/finding split. `521`/`530`/`000`/`502`/`503`/`504`
are Cloudflare-edge *transport* codes — the workflow retries them precisely because they are transient
(*"STRUCTURAL codes fail fast (no retry burn); everything else retries. 521/530 are CF-edge codes
emitted while the tunnel connector reattaches"*). Budget exhaustion on a retryable code is a
**can't-measure**, and classing it as data loss would route the operator into the runbook §5
data-recovery triage table for what is an edge outage. The STRUCTURAL set is a routing regression and
belongs in `readiness`. **Reuse the existing enumerated case-arm — do not re-list those codes**, or
AC10's byte-equality check will see two competing sets (§Sharp Edges 4).

Note also that a 200 from the app health endpoint is served by the custom server and says nothing
about the volume at rest; it is a secondary liveness check only, which is why it can never produce
`drift`.

**The split needs a mechanism, and "reuse the arm" alone does not supply one.** In the workflow, the
STRUCTURAL set exists only as a `case` arm *inside* the retry `for` loop, whose body is
`echo "::error::…"; break`. Both STRUCTURAL and RETRYABLE-exhaustion then fall through to the same
single `exit 1` (anchor: `app /health returned $health (expected 200) after the full retry budget`),
so by the time the classifier runs, the two are indistinguishable — and re-listing the codes to tell
them apart is forbidden by AC10 (§Sharp Edges 4).

**Prescribed mechanism:** set a flag *inside the existing arm's body* —
`health_class=structural` alongside the existing `echo`/`break` — and read it in the classifier. This
is an **addition** to the arm body, not a re-spelling of the arm's pattern, so AC10's
`^[[:space:]]*307\|[0-9\|]+\)` extraction is untouched and AC4 (no modified `::error::` strings, no
modified exit codes) still holds.

*Fallback if that proves awkward:* `source "$INFRA_DIR/workspaces-luks-emit.sh"` on the runner and
call `wl_http_class "$health"` — it is already the byte-equality reference AC10 compares against.
Rejected as primary only because it adds a runner-side source dependency for one string.

Label colour: `#B60205` (the repo's hard-failure colour), created once, idempotently.

### Classify on `reason` FIRST, `rc` second — a bug this plan's first draft contained

Found while enumerating exit sites, and it is not hypothetical: **`mapper_path_override_refused` is
emitted by `emit_and_die` (exit 1), not `emit_readiness_and_die` (exit 3)** — verified at
`luks-monitor.sh` anchor `WL_MOUNT_SOURCE="override"; emit_and_die mapper_path_override_refused`.
But the workflow's rc-3 PROBE-INTEGRITY `case` arm lists it. Two consequences:

1. **That `case`-arm entry is dead.** rc 3 is the only way into that `case`, and this reason never
   accompanies rc 3. Pre-existing; harmless today.
2. **An rc-first classifier gets it exactly backwards.** `mapper_path_override_refused` would arrive
   as rc 1 → the `exit "$probe_rc"` arm → classed **`drift`** → a `priority/p0-critical` +
   `type/security` issue asserting the retained Article 32 claim is false and demanding CLO review —
   for what is a *refusal to run the probe under an incoherent config*. Nothing was proven about the
   volume. It is a textbook can't-measure, and the loudest possible misfire.

**Therefore: the classifier keys on `reason` first and falls back to `rc`.** Any reason in the
PROBE-INTEGRITY set maps to `unavailable` regardless of which rc carried it; only then does `rc`
decide. This also immunises the classification against future producer/consumer drift of exactly
this kind, which is the same defect class as BLOCKER-2.

**Implementation consequence:** the `sed` reason extraction currently lives *inside* the `rc == 3`
branch. Hoist it above the rc branching so a reason is available for every rc. No test greps that
`sed` line (the grep-anchored lines are the `307|…` case arm, the API-prefixed-health literal, and
the `SOLEUR_WORKSPACES_READYZ` verdict grep — none of them this one), but re-run the four gate suites
to confirm.

Leave the workflow's dead `case`-arm entry **as-is**: removing `mapper_path_override_refused` from it
is a separate, unrelated cleanup, and the reason-first classifier makes it moot.

### Exit-site → class map (complete; every site enumerated, none left implicit)

Enumerated from the current file on 2026-08-03 via `grep -nE '^\s+exit [0-9"$]'` **and**
`grep -nE 'exit 1; \}'` — the inline `|| { …; exit 1; }` guards are the ones a naive scan misses.
Every site below gets an `emit_class` call immediately before it; an unmapped exit is a plan defect.

| Site (content anchor) | Step | Class |
|---|---|---|
| `DOPPLER_TOKEN not configured` | **Verify required secrets present** (a *different* step) | Re-assert never runs → `steps.reassert.outcome == 'skipped'`, empty class → `unavailable` by the fail-closed default. No `emit_class` possible or needed |
| `CF Tunnel SSH bridge did not export WEB_HOST_SSH` | Re-assert | `unavailable` |
| `WORKSPACES_LUKS_BOOT_TOKEN not configured` | Re-assert | `unavailable` |
| `failed to create the remote bundle dir on web-1` | Re-assert | `unavailable` (SSH reachability) |
| `seed_workspace_count must be a positive integer` | Re-assert (dispatch-only branch) | `unavailable` — never alarms, since the alarm is `schedule`-gated and this branch is unreachable on a schedule |
| `refusing to seed WORKSPACES_COUNT=… below the existing baseline` | Re-assert (dispatch-only) | `unavailable`, same |
| `failed to seed the workspace-inventory baseline` | Re-assert (dispatch-only) | `unavailable`, same |
| *(new)* scheduled-seed refusal guard | Re-assert | `unavailable`, reason `scheduled_seed_refused` |
| `exit 255` — SSH transport | Re-assert | `unavailable` |
| `exit 127` — bundle/tooling | Re-assert | `unavailable` |
| `exit 3` — by `reason` | Re-assert | PROBE-INTEGRITY reasons → `unavailable`; `workspace_count_shortfall` / `readyz_not_ready` / empty → `readiness` |
| `exit "$probe_rc"` — any other non-zero rc (rc 1: `not_mounted`, `mount_not_mapper`, `mapper_absent`, `cryptsetup_status_missing`, `mapper_device_link_missing`, `device_not_luks`, `escrow_passphrase_mismatch`, `header_uuid_unreadable`) | Re-assert | `drift` — **except** `mapper_path_override_refused` and `doppler_unreachable`, which are can't-measure and are caught by the reason-first rule above → `unavailable` |
| `exit 1` — app health non-200 after the budget | Re-assert | STRUCTURAL code → `readiness`; RETRYABLE code → `unavailable` |
| `exit 1` — verdict line ABSENT | Re-assert | `unavailable` (the #6807 silent-green shape) |
| fall-through to the PASSED echo | Re-assert | `pass` |

**Why three and not two (CLO ruling).** Dedupe suppresses a second issue of the same class. With a
two-way `finding` / `cannot_measure` split, an open `readyz_not_ready` issue would swallow the *first*
at-rest drift issue — the one alarm that fires a legal re-evaluation. Splitting on
`at-rest-drift vs. everything-else` is what makes trigger (3) detectable in ops noise. This mirrors
`scheduled-inngest-health.yml`'s `case "$FAIL_MODE" → ISSUE_CLASS` reference implementation (8 labels).

**No auto-close on green — and that is the simplification, not an omission.**

An earlier draft auto-closed the `unavailable` class on a green run, which forced two further
mechanisms: reopen-not-recreate (because auto-close + create-if-none-open turns a flapping CF tunnel
into one issue *per flap*, and the bridge has a documented flap class, `ci/tunnel-connector-drift`)
and a running-count line in the body (a read-modify-write against a mutable remote resource — the
most fragile shell in the PR). Both existed only to mitigate a problem auto-close created.

**Dropping the close step deletes all three.** *(Reasoning corrected 2026-08-03 during review: the
original ran "with no close, an open issue always exists for dedupe-by-title to find, so no flap
can produce a second issue" — which contradicts its own next clause. The dedupe query is
`--state open`, and a human closing the issue is stated here as the INTENDED lifecycle, so an
operator who closes an `unavailable` issue mid-flap gets a fresh one on the next run. The
simplification still stands; the honest justification is the bound below, not an impossibility
claim.)* The churn is BOUNDED at one issue per class per day by the cadence, and `unavailable`
sends no ops email, so a re-file after an operator close is acceptable churn rather than a spam
vector; and a human closing an
`action-required` P1 after reading it is the correct lifecycle for every class here. It also removes
the "green run certifies a prior data-loss finding" hazard for `drift` and `readiness` by
construction — the same "certified green" shape the workflow's own downward-re-seed guard already
refuses.

**One anti-spam bound survives, because it is not self-inflicted:** comment on a repeat failure only
when the `reason` **changes**. Daily cadence against a never-closed issue would otherwise accrete
~365 comments/yr. Two lines of comparison; no remote read-modify-write.

**Severity is assigned on user impact, not on legal salience.** `workspace_count_shortfall` is
*irreversible sole-copy user data loss*; `drift` is *encryption not in effect on a volume whose data
is intact*. Ranking the legal-claim event above the data-loss event inverts
`hr-weigh-every-decision-against-target-user-impact`. Therefore within the `readiness` class the
priority label is conditional: `workspace_count_shortfall` → `priority/p0-critical`; every other
`readiness` reason (`readyz_not_ready` capacity/permission faults, structural health codes) →
`priority/p1-high`. One conditional, and it puts the p0 where the user's data is.

**Paging, not just filing.** `drift` and `readiness` additionally send
`./.github/actions/notify-ops-email` (as `scheduled-realtime-probe.yml` and
`scheduled-terraform-drift.yml` do). An issue is not a page, and a `workspace_count_shortfall` is a
sole-copy data-loss signal.

Two things the plan must not claim about this:

- **`RESEND_API_KEY` is a new secret dependency for this workflow.** It is not currently referenced
  by `workspaces-luks-verify.yml`. Add it to the existing `Verify required secrets present` step's
  guard so a missing key fails loudly at the top of the run rather than at page time.
- **A dropped page is nearly silent.** `notify-ops-email` exits 1 on an *empty* key, but on a
  non-2xx (revoked/expired key, Resend outage) it emits `::warning::Email notification failed` and
  **exits 0**. So an expired key drops every `drift`/`readiness` page indefinitely into a log nobody
  reads — the `cq-silent-fallback-must-mirror-to-sentry` shape sitting inside the paging layer.
  Mitigation: the **GitHub issue is the primary channel and the email is best-effort**, stated as
  such; and the alarm step appends the email step's outcome to the issue body, so a dropped page is
  visible in the artifact the operator does read.
- **`unavailable` gets no direct ops-email** — but be honest that this does not mean "no email": its
  Sentry `error` check-in reaches `ops@jikigai.com` through the issue-alert plane only from the
  SECOND consecutive non-ok check-in (`failure_issue_threshold = 2`), so the first `unavailable`
  night is carried by the GitHub issue alone
  (§Observability `alert_target`). The separation is one of *volume and framing*, not of channel;
  Sentry's own grouping dedupes it, which a per-run `notify-ops-email` would not.

**Alarm gating — `schedule` only.** Both the alarm and the Sentry check-in are gated on
`github.event_name == 'schedule'`. Rationale: the alarm exists because a schedule removes the
watcher; a dispatch has one by definition, and filing an issue on every operator experiment (or on a
deliberately-rejected bad seed value) is noise. This also keeps the `workflow_dispatch` path byte-identical.

> **AC1 AMENDED 2026-08-03 (review).** AC1's literal verification command read
> `git diff origin/main -- .github/workflows/workspaces-luks-verify.yml` *shows no change inside
> the `workflow_dispatch:` block*. That is unsatisfiable alongside §Decision 2, which mandates the
> additive `alarm_selftest` input in that same block, so a future reader walking the ACs would hit
> a command that cannot pass. The protected interest is the OPERATOR-FACING DISPATCH CONTRACT, not
> the block's byte count: scope the byte-identity to `seed_workspace_count` (its description,
> `required`, `type` and `default`), which the gate suite asserts structurally, and allow additive
> sibling inputs that default to a no-op.
It mirrors `scheduled-supabase-advisor-scan.yml`, which gates its heartbeat on the dispatch source
"so a manual smoke test cannot forge liveness".

**But that gate plus Sharp Edge 15 means the red path would otherwise NEVER execute in real GHA —
not before merge (`schedule:` does not fire from a PR branch) and not after (only a real failure
would trigger it).** Combined with the fact that the whole operator-reaching path funnels through one
`if:` expression, the alarm could ship permanently unreachable while every layer of verification in
this plan reported green. The committed test evaluates that expression's semantics (§Phase 1.1), but
a test evaluates *our model* of GHA expression evaluation, not GHA's.

**Therefore add one dispatch-only input, `alarm_selftest`** (`type: boolean`, `default: false`), and
extend the alarm gate to
`github.event_name == 'schedule' || inputs.alarm_selftest`. When set, the run classifies as normal
but files under a distinct, unmistakable title (`[ci/luks-verify] SELF-TEST — ignore`) so it can
never be confused with a real alarm, and the operator closes it. This is **additive** — it does not
touch `seed_workspace_count`'s semantics or the existing dispatch path — and it is the only way to
exercise the real GHA `if:` against real expression evaluation, once, post-merge. Fire it once as
part of `/soleur:postmerge`.

## Decision 3 — A Sentry Crons monitor for the schedule itself

Without this, the PR is only half-done. The in-run alarm is structurally blind to **three** failure
modes, each of which produces silence rather than a red run:

1. **The schedule stops firing.** GitHub disables `schedule:` triggers after 60 days of repository
   inactivity, a cron can be dropped under load, a bad edit can disable the trigger, a rename can
   orphan it. `cron-monitors.tf` records a real precedent: *"On 2026-05-26 GitHub dropped the
   scheduled run ENTIRELY."* No run, no failure, no alarm — the claim-decay trigger's exact defeat
   condition, and the same "a check that cannot report" shape one level up as the bug this PR fixes.
2. **FM2 — a pending run cancelled by concurrency supersession** (§Decision 5). It executes no steps
   at all, so no `always()` / `!cancelled()` construction inside the workflow can report it. It is
   detectable only from outside the run.
3. **Job timeout.** `timeout-minutes: 15` against an SSH hang over the CF Tunnel is the single most
   likely failure shape, and when the runner allocation is torn down neither `always()` nor
   `!cancelled()` reliably executes.

`apps/web-platform/infra/sentry/cron-monitors.tf` is the established mechanism (51 existing
monitors) and is **auto-applied on merge** by `.github/workflows/apply-sentry-infra.yml` (FULL-ROOT
since #6589, `paths:` filter covers the whole `infra/sentry/**` tree). No operator step.

```hcl
resource "sentry_cron_monitor" "workspaces_luks_verify" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "workspaces-luks-verify"   # slug == workflow filename minus .yml
  schedule                = { crontab = "41 4 * * *" }
  checkin_margin_minutes  = 420                         # NOT the file's margin==interval convention — see below
  max_runtime_minutes     = 20                          # job timeout-minutes: 15 + setup
  failure_issue_threshold = 2                           # NOT the file's default of 1 — pairs with the margin; see below
  recovery_threshold      = 1
  timezone                = "UTC"
}
```

**`checkin_margin_minutes = 420` AND `failure_issue_threshold = 2` — both depart from the file's
convention, and they only work as a pair.**

Two documented positions collide here, and the plan must not pretend otherwise.

*Position A — the file's convention, backed by a real incident.* `cron-monitors.tf` says
*"margin == interval MAXIMIZES jitter tolerance… while a genuinely dark alarm still pages once the
window closes at the next expected fire"*, and the `scheduled_realtime_probe` block (also daily, also
GHA-fired, margin 1440) carries a comment naming the incident that set it: *"On 2026-05-26 GitHub
dropped the scheduled run ENTIRELY (not jitter — a whole missing run), which paged a 'missed
check-in' on 2026-05-28 even though the last actual run (05-27) passed 5/5. The 180-min margin
tolerated jitter but not a dropped 24h run; widen to 1440 (24h) so a single dropped scheduled run does
not page. See issue #4189."* **A margin below 1440 re-introduces the false page #4189 fixed.**

*Position B — margin 1440 makes this monitor unable to report its own purpose.* With crontab
`41 4 * * *` and margin 1440, day N's expected check-in is not marked missed until 04:41 on day N+1 —
the same instant day N+1's run fires and checks in. A **single** missed fire is absorbed. But all
three modes this monitor exists for (schedule stops, FM2 supersession, job timeout) are, in the common
case, exactly one missed fire.

**Why `scheduled_realtime_probe` can accept Position A and this monitor cannot:** when that probe's
run is dropped, the *next* run's own 5×SUBSCRIBED check still catches a real regression and files
`ci/realtime-broken` — its Sentry monitor is a backstop to a self-reporting probe. Here, the three
modes produce **no issue from the run at all**, so the Sentry monitor is the *only* detector — and
#6808's whole lesson is that a probe which cannot report is indistinguishable from a healthy one.

**The resolution is not to pick a side — it is `failure_issue_threshold`.** The false page in #4189
came from the margin *paired with* `failure_issue_threshold = 1`: one drop, one page.

| margin | threshold | single GitHub drop | genuinely dark schedule |
|---|---|---|---|
| 1440 | 1 | silent ✓ | absorbed / never ✗ |
| 420 | 1 | **false page ✗** (the #4189 regression) | ~7 h ✓ |
| **420** | **2** | **silent ✓** | **~31 h ✓** |

Two consecutive misses are required to open an issue, and `recovery_threshold = 1` resets the counter
on the next successful check-in — so a lone dropped run is absorbed exactly as #4189 requires, while a
schedule that is genuinely dark pages on day 2 instead of never. 420 minutes also covers the repo's
measured worst-case GHA jitter (339 min) with ~24% headroom.

**Record both departures in the resource comment**, citing #4189 and this reasoning, so a future
convention sweep cannot "correct" either value in isolation — reverting the margin alone re-breaks
detection; reverting the threshold alone re-breaks #4189. `failure_issue_threshold = 2` also departs
from the file's own default of 1, so it needs the comment as much as the margin does.

**Residual:** a two-day GitHub outage still pages. Correct — at that point the schedule genuinely has
not run. The vendor-free `gh run list --event=schedule --status=success` query (§L1) remains the
authority for the 30-day decay question.

Slug parity is test-enforced by `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`.
**Verified at deepen-plan:** its `workflowHeartbeatSlugs()` walks every `.yml`/`.yaml` in
`.github/workflows/` and greps for `monitor-slug:` — no `scheduled-*` prefix filter — so it picks up
this workflow automatically and needs no edit. The corollary is a hard coupling: declaring a
`monitor-slug:` without the matching resource **fails that test**, so the workflow step and the TF
resource must land together.

### The cost, and a residual this monitor does not close

**This is not free, and `wg-record-recurring-vendor-expense-before-ready` fires.**
`knowledge-base/operations/expenses.md` (Sentry Team row, verified 2026-08-03): `$71.22/mo`, with a
`$50/mo` PAYG cap (`onDemandMaxSpend`) for cron-monitor seat overages. The row records
`monitorSeats.reserved = 1` (live-verified), *"so every scheduled workflow adds an uncapped
$0.78/mo"*, currently `$42.22` PAYG (49 × $0.78 seats + 4 × $1.00 uptime) — **~9 monitors of
headroom, next cliff 2026-08-16 (`onDemandPeriodEnd`)**, 13 days out.

The 52nd monitor takes PAYG to ~$43.00 of $50. Affordable, but the expenses row **must be updated
before the PR is marked ready**. Re-measure the live figure at /work time rather than incrementing
the written one — it moves.

**A residual this layer does not close, named rather than papered over.** The same expenses row
records the failure mode: *"At renewal, if PAYG cannot cover all active monitors, **every monitor
deactivates at once and check-ins are silently dropped**"* (#3958). So the absence-detection layer
can itself be silently deactivated by a billing event — the very shape it exists to detect, one
level further up. That is why the Article 30 evidence query (§L1, `gh run list … --event=schedule
--status=success`) is named as an independent, vendor-free path to the same fact, and why #3958
stays linked from the Risks table. Do not present the Sentry monitor as a complete answer.

## Decision 4 — Read-only on the scheduled path, enforced rather than assumed

`seed_workspace_count` is `required: false` with `default: ""`, and a `schedule:` event supplies no
inputs, so `${{ inputs.seed_workspace_count }}` interpolates to the empty string, the env var is
set-but-empty, `[[ -n "${SEED_WORKSPACE_COUNT:-}" ]]` is false, and the seed branch is skipped. The
`:-` default also means `set -u` cannot abort. Repo precedent for the same shape:
`scheduled-followthrough-sweeper.yml` (`DRY_RUN: ${{ inputs.dry_run && '1' || '0' }}`) and
`cla-evidence-timestamp.yml` (in-step `${INPUT_YYYY_MM:-}` default, no `github.event_name` branch).

**But the plan does not rest on that.** A seeded run WRITES host state; a scheduled one must never
do that, and "GitHub's `inputs` context is empty on non-dispatch events" is an assumption about a
vendor's expression evaluator sitting between the schedule and a write to production. Convert it
into an enforced, testable invariant — a hard refusal placed **before** any seed handling:

```bash
if [[ "${GITHUB_EVENT_NAME:-}" == "schedule" && -n "${SEED_WORKSPACE_COUNT:-}" ]]; then
  echo "::error::a scheduled run must never seed the inventory baseline. A seed is a host-state WRITE and is operator-only. Refusing."
  emit_class unavailable scheduled_seed_refused
  exit 1
fi
```

The expression-level ternary
(`${{ github.event_name == 'workflow_dispatch' && inputs.seed_workspace_count || '' }}`) was
considered and **rejected**: GHA's `&&`/`||` ternary has an empty-string-falsy footgun, it is not
testable from a shell fixture, and it fails silently rather than loudly.

**Baseline operand.** The fail-closed inventory comparison has a real operand today: run
`30749271370` (2026-08-02) reported `workspace_count=8 expected=8`. If the baseline is ever lost, the
comparison is fail-closed (`workspace_count_baseline_missing` → exit 3), and this plan routes that
reason to `unavailable`, not to a silent pass — so the vacuous-green risk the `seed_workspace_count`
documentation warns about is closed on the scheduled path, not merely absent today.

## Decision 5 — Concurrency with two trigger sources

`concurrency: { group: workspaces-luks-verify, cancel-in-progress: false }` stays **shared and
unchanged**. Enumerated:

GitHub keeps **one** in-progress plus **one** pending run per group; a third arrival cancels the
*older pending* run.

| # | Sequence | Outcome | Severity |
|---|---|---|---|
| FM1 | Dispatch running → schedule fires | Schedule queues, runs after (≤15 min, `timeout-minutes: 15`) | Benign |
| FM2 | Dispatch running → schedule queues → **second dispatch** | The queued **scheduled** run is cancelled, silently. No steps execute → no alarm step, no issue, no summary | **The real hole** |
| FM3 | Schedule running → operator dispatches | Dispatch queues, runs after | Benign — the operator sees "queued" |
| FM4 | Schedule running → dispatch queues → schedule fires again | Impossible at daily cadence | n/a |
| FM5 | Seed dispatch queued behind a scheduled run | Seed lands after; the refuse-to-lower guard makes the ordering safe | Benign |

**Keep the group shared and keep `cancel-in-progress: false`.** Splitting the group is the wrong fix
— it re-permits two concurrent SSH sessions to web-1, which is exactly what the group exists to
prevent, and one of those sessions can be the seed *writer*. `cancel-in-progress: true` is strictly
worse: it would let a schedule kill an operator dispatch mid-SSH, violating the stated requirement
head-on.

**FM2 is not fixable inside the workflow.** A cancelled-while-pending run never runs a step, so no
`always()` / `!cancelled()` construction can report it. FM2 is detectable only from outside the run —
the second independent argument for the Sentry monitor (§Decision 3).

**Use `always()`, not `!cancelled()` — corrected.** An earlier draft chose `!cancelled()` to avoid
"spurious issues from superseded runs". That rationale is wrong: a superseded *pending* run executes
no steps, so `always()` would not fire for it either — `!cancelled()` buys nothing there while being
the construction most likely to **suppress** the alarm on the timeout/cancel path, which is the
single most likely real failure shape. An operator-cancelled hung run filing "nothing was proven" is
the correct outcome. Both the alarm step and the Sentry check-in therefore use `always()`, and the
workflow comment must state this reason rather than the wrong one.

## Decision 6 — Where the classifier lives, and the guard that currently cannot run

### 6a. The drift-guard would be born dead without a `paths:` fix (CTO BLOCKER-1)

`.github/workflows/infra-validation.yml` is `pull_request` + `paths:`, and its path list — verified
2026-08-03 — **does not include `.github/workflows/workspaces-luks-verify.yml`**, while that same
workflow runs the three suites that assert properties of that file (`luks-monitor.test.sh`,
`workspaces-luks-freeze.test.sh`, `workspaces-luks-header.test.sh`). **A PR touching only that
workflow YAML runs none of them.**

This is byte-identical to the defect that file's own `paths:` comments already document for #6454 and
#7025 (*"a PR editing ONLY one of them skipped the suite that guards it"*), and the list already
carries eight sibling workflow paths (`apply-sentry-infra.yml`, `scheduled-terraform-drift.yml`,
`cutover-inngest.yml`, …), so adding one is the established pattern, not a new convention.

**Consequence: every guard this plan adds is unreachable on exactly the PRs that would break it,
until this lands.** Adding `- ".github/workflows/workspaces-luks-verify.yml"` to that `paths:` list
is therefore **Phase 1, step 1** — it is a precondition for the rest of the PR having any value, not
a tidy-up.

### 6b. Extract the NEW classifier only — and not under `.github/`

Four live gates grep this workflow **by shape**, so extracting any *existing* logic breaks them:

| Gate | Anchor | Breaks if you move… |
|---|---|---|
| `workspaces-luks-freeze.test.sh` AC10 | `grep -oE '^[[:space:]]*307\|[0-9\|]+\)' "$VERIFY_WF"` | the health case-arm → set empties → **RED** |
| `workspaces-luks-freeze.test.sh` AC7 | `grep -oE '/api/health[a-z/-]*' "$VERIFY_WF"` | the curl loop → the sweep goes **vacuous** (silent, and worse) |
| `luks-monitor.test.sh` case (y) | extracts the literal `grep -cE '^\[luks-monitor\] SOLEUR_WORKSPACES_READYZ ready=true '` out of `$VERIFY_WF` | the verdict-line positive control → **RED** |
| `workspaces-luks-header.test.sh` H15b / H20 | `p_env_shred_trap "$YML_VERIFY"`, `p_verify_file_execution "$YML_VERIFY"` | the SSH / stdin-`.env` invocation → **RED** |

AC7 is the sharpest: it breaks **silently** (a count of 0 reads as clean) while AC10 breaks loudly.

**Decision: keep the classifier INLINE in the workflow's `run:` body.** No new shell file.

CTO initially recommended extracting the new classifier to
`apps/web-platform/infra/workspaces-luks-classify.sh`, justified on "`apps/*/infra/**` is already in
`infra-validation.yml`'s `paths:`, so it is CI-covered from the first commit." **That argument is
retired by §Decision 6a in this same PR** — once the verify workflow is in `paths:`, the inline code
is equally CI-covered. What extraction would still cost is real: a runtime `source`-from-checkout
dependency, and a new hazard (the classifier must be kept *out* of the
`tar czf - -C "$INFRA_DIR" luks-monitor.sh workspaces-luks-emit.sh` host bundle) that exists only
because of the extraction.

The test reaches the inline code by extracting and executing the `run:` body with `ssh`/`curl`/`tar`/
`doppler` stubbed — which the suite must do **anyway** for the seed-refusal and verdict-absent
branches, so a separate pure-function suite would duplicate the same fixture table twice.

**Dissent recorded:** CTO preferred extraction. If `/work` finds the inline `run:` body has grown past
the point where a fixture can drive it cleanly, extraction to `apps/web-platform/infra/` (never
`.github/workflows/lib/`) is the fallback — and in that case the tar-bundle exclusion becomes a
required assertion.

Either way: leave every existing `exit` line, `::error::` string and grep byte-identical, and emit the
class immediately before each.

## Network-Outage Deep-Dive (deepen-plan Phase 4.5)

The keyword gate fired on `SSH`, `unreachable`, `timeout` and `handshake` — but note **what** those
words are doing here. This plan diagnoses no live outage; those tokens are the *vocabulary of the
`unavailable` class*. There is no current incident whose L3/L7 layers need verifying, so the
checklist's four layers are "not applicable — no live symptom" rather than "not verified".

Where the checklist **is** load-bearing is the runbook remediation row this plan adds (Phase 4.5),
and it converges exactly with the flow review's P1-7 finding: today the runbook's `rc=255` row says
*"Check the bridge step, re-dispatch."* Re-dispatching does not fix a multi-day CF Tunnel outage, and
`hr-no-ssh-fallback-in-runbooks` forecloses the manual path — so an operator holding a 6-day-old
`unavailable` issue has no procedure at all.

**The new escalation row MUST be ordered L3 → L7**, not the reverse (the #2654 → #2681 inversion cost
a misdirected PR and a second incident day):

| Layer | Check | Artifact |
|---|---|---|
| **L3 — tunnel/connector reachability** | The Cloudflare connector census the tunnel-health workflow already reads (`accounts/$CF_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/connections`) — is there a live connector at all? | connector count + colo attribution |
| **L3 — firewall / egress** | The GH runner egress IP is deliberately **not** in `var.admin_ips`; the bridge is the only path. Confirm the bridge action itself failed vs. ssh-after-bridge (the two produce different classes — step-skipped vs `rc=255`) | which step failed |
| **L7 — SSH transport** | Only after both L3 checks: `rc=255` with a live connector and a healthy bridge points at sshd/host, not the network | bridge step log tail |

**Do not** let the runbook row jump straight to sshd or to "re-dispatch". Cross-reference the
existing tunnel-connector remediation (`ci/tunnel-connector-drift`) rather than restating it, and
name a real escalation for the sustained case.

## Sharp Edges

Each of these is a constraint the repo has already been bitten by, verified against current files.

1. **`if:` referencing another step's outcome gets an implicit `success() &&` from GitHub.**
   A bare `if: steps.reassert.outputs.outcome_class != 'pass'` is silently ANDed with `success()`
   and is therefore unreachable on exactly the runs it exists for. Every new conditional step MUST
   lead with an explicit status function — use **`always()`** (see §Decision 5 for why
   `!cancelled()` is the wrong choice here).
1b. **The alarm `if:` must pin all three conjuncts**, not just the producer-status one:
   `always()`, `github.event_name == 'schedule'`, **and** the class clause. Dropping the event-name
   conjunct turns every failed operator dispatch into a filed issue (spam); dropping the class clause
   reverts to #7138.
1c. **`id: reassert` is load-bearing.** `steps.reassert.outputs.*` resolves to `''` without it, which
   the fail-closed condition does catch — but pin the `id`'s presence in the drift-guard anyway, so
   the guard fails loudly rather than relying on the fallback.
2. **Producer-status-first, or a dead producer checks in green (#7138) — and the precedent is only
   half-usable.** `steps.reassert.outputs.outcome_class == ''` is what a step that *never ran* looks
   like, and `'' != 'pass'` must alarm rather than pass.

   **Do not copy `scheduled-realtime-probe.yml`'s alarm `if:`.** That file's alarm step is
   `if: steps.probe.outputs.failure_mode != ''` — a bare outputs reference with no status function,
   which per Sharp Edge 1 is silently ANDed with `success()`. It is the #7138 shape, not the fix.
   The producer-status-first form documented in that file belongs to its **heartbeat `status:`
   expression**, which is a *positive* gate on green — pasting it into an alarm `if:` would require
   the producer to have **succeeded** before the alarm could fire, i.e. unreachable on every failure.
   An earlier draft of this plan made exactly that miscitation.

   **The literal expressions this PR must ship** (write these, do not paraphrase):

   ```yaml
   # alarm step
   if: >-
     ${{ always() && github.event_name == 'schedule'
         && (steps.reassert.outcome != 'success' || steps.reassert.outputs.outcome_class != 'pass') }}

   # Sentry check-in step
   status: ${{ (steps.reassert.outcome == 'success' && steps.reassert.outputs.outcome_class == 'pass') && 'ok' || 'error' }}
   ```

   The heartbeat gates **positively** on `== 'pass'`; the alarm is its negation. Never gate on
   `!= 'failure'` — a negative gate over a closed 4-member enum is "a single-literal gate wearing a
   disguise".
3. **`workspaces-luks-freeze.test.sh` AC7 greps this workflow *including comments* for
   `/api/health[a-z/-]*`.** The workflow's own header says the literal API-prefixed spelling is
   "deliberately ABSENT from this file, comments included". Every line this PR adds — including
   prose comments, issue-body text and `::error::` strings — must refer to "the app health endpoint",
   never the API-prefixed path.
4. **AC10 extracts `^[[:space:]]*307\|[0-9\|]+\)` from this workflow** and asserts byte-equality with
   `wl_http_class`'s structural set. Do not reindent, reorder or re-spell the
   `307|401|403|404|405|525|526)` case arm, **and do not introduce any new case arm whose first
   token is `307|`** — the classification `case` arms must be spelled `drift)`, `readiness)`,
   `unavailable)`, never a numeric alternation.
5. **`luks-monitor.test.sh` case (y) extracts the literal `grep -cE` verdict pattern out of this
   workflow** and runs it against a real emission. Do not touch the
   `^\[luks-monitor\] SOLEUR_WORKSPACES_READYZ ready=true ` grep line.
6. **Dedupe by label + exact title, not `gh issue list --search`.** `scheduled-supabase-advisor-scan.yml`
   records the reason it abandoned `--search`: *"the search API can return empty under some token
   contexts, which would file a fresh duplicate every single night."* Use
   `gh issue list --label <label> --state open --limit 100 --json number,title --jq 'map(select(.title == $t)) | .[0].number // empty'`.
7. **`gh --jq` does not forward `--arg`.** Any `jq` needing `--arg` must be a standalone second-stage
   pipe, not `gh --jq`
   ([`2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`](../learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md)).
8. **`bash -n` on a `.yml` parses YAML as bash and proves nothing.** Syntax-check only *extracted*
   `run:` bodies. `actionlint` validates workflows (this file is a workflow, so `actionlint` applies —
   run `scripts/lint-workflows.sh`); it must not be pointed at composite `action.yml` files.
9. **`grep -q` in a pipeline under `pipefail`** SIGPIPEs the producer for 141 and the negative arm
   fails open. The workflow already uses `grep -c` on a FILE for exactly this reason — keep that
   discipline in the new code and in the test.
10. **The `reason` value crosses the SSH boundary from the host.** It is already constrained to
    `[a-z_]*` by the extraction regex `sed -n 's/^\[luks-monitor\] FAIL (\([a-z_]*\)).*/\1/p'`, so it
    cannot carry CR/LF into a `$GITHUB_OUTPUT` line or an `::error::` annotation. **Do not widen that
    regex.** Any *new* host-derived field routed into an issue body or annotation must go through the
    house `strip_log_injection` helper (`scheduled-realtime-probe.yml`).
11. **`workspaces-luks-verify.test.sh` already exists and does NOT test this workflow** — despite the
    name it covers `verify_byte_identity`. The new suite must be named
    `workspaces-luks-verify-workflow.test.sh` (mirroring `workspaces-luks-cutover-workflow.test.sh`).
12. **Infra suites are not run by `scripts/test-all.sh`.** The authoritative runner is
    `apps/web-platform/infra/run-registered-suites.sh`, which DERIVES its list by grepping
    `run: bash apps/web-platform/infra/<name>.test.sh` out of `.github/workflows/infra-validation.yml`.
    A new suite that is not registered there **is never run** — a test that cannot run is the same
    defect class as an alarm that cannot fire.
13. **`workspaces-luks-header.test.sh` H15b/H20 also grep this workflow** (`p_env_shred_trap`,
    `p_verify_file_execution` against `$YML_VERIFY`). Do not move or reshape the SSH / stdin-`.env`
    invocation. This is the fourth grep-shape coupling to this file — see §Decision 6b for the full
    table.
14. **`gh label create` is Issues-scoped**, so the `permissions: issues: write` bump covers label
    creation as well as issue filing. Confirmed by `scheduled-realtime-probe.yml` doing exactly this
    under `contents: read` + `issues: write`.
15. **The `schedule:` trigger does not fire from a PR branch.** GitHub only honours `schedule:` on the
    default branch, so the first live scheduled run is necessarily **post-merge**. No pre-merge AC may
    claim to have observed one — that is what the committed test and the follow-through probe are for.
16. **Do not add the classifier to the `tar czf -` host bundle.** That list
    (`luks-monitor.sh workspaces-luks-emit.sh`) is deliberate; the classifier runs on the runner.
17. **A plan whose `## User-Brand Impact` section is empty, contains `TBD`/`TODO`/placeholder text,
    or omits the threshold will fail `deepen-plan` Phase 4.6.**

## Files to Edit

| File | Change |
|---|---|
| `.github/workflows/infra-validation.yml` | **(1)** Add `- ".github/workflows/workspaces-luks-verify.yml"` to `paths:` — CTO BLOCKER-1, §Decision 6a. **(2)** Register `workspaces-luks-verify-workflow.test.sh` (adjacent to the existing `workspaces-luks-cutover-workflow.test.sh` registration) |
| `.github/workflows/workspaces-luks-verify.yml` | `schedule:` trigger; `permissions: issues: write`; `id: reassert`; inline classifier + `emit_class` at every exit site; scheduled-seed refusal guard; `alarm_selftest` dispatch input; alarm step (no green-close step); ops-email step (drift/readiness only); Sentry check-in step; header comment carrying the ADR-033 carve-out + anti-circularity corollary, the cadence justification, the `always()` rationale and the #6808 sunset note |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | `resource "sentry_cron_monitor" "workspaces_luks_verify"` (§Decision 3) |
| `knowledge-base/operations/expenses.md` | Sentry Team row — +1 cron-monitor seat (+$0.78/mo PAYG). `wg-record-recurring-vendor-expense-before-ready`. Re-measure the live PAYG figure; do not increment the written one |
| `knowledge-base/legal/article-30-register.md` | PA-1(g)(17) and PA-2(g)(21) — anchor: `**LUKS-at-rest on the live workspaces volume (ADR-119, #6588) — ACTIVE, verified:**` … `Cutover certified 2026-07-23 and re-asserted 2026-07-24 (`workspaces-luks-verify` run 30130277489…)`. Record the daily scheduled verification and re-cite run `30749271370` (2026-08-02) |
| `knowledge-base/legal/audits/2026-07-counsel-review-6588.md` | Annotate the `claim_decay_trigger` frontmatter field (false on merge) + correct §A3.4 recommendation 2. Disposition **unchanged** |
| `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` | Anti-circularity addendum to the 2026-06-02 scope note (§Architecture Decision). No new ADR ordinal |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | `github -> sentry` edge — **remove** the four hand-maintained counts; add `workspaces-luks-verify` to the named GHA-`schedule:`-fired list |
| `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` | §5 already carries a per-`rc`/`reason` verdict triage table (anchors: `` `rc=3` `workspace_count_shortfall` ``, `` `rc=3` `readyz_gate_regression` ``) — **extend it, do not create it**: add an `outcome_class` column mapping each existing row to `drift` / `readiness` / `unavailable`, and amend §5's opening (anchor: `**Verify (read-only, no SSH).**` / `gh workflow run workspaces-luks-verify.yml`) to state the check is now daily-automatic rather than dispatch-only. The `ci/luks-verify` issue bodies must link to this table |

## Files to Create

| File | Purpose |
|---|---|
| `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` | The only new file. Executes the extracted `run:` body over stubbed `ssh`/`curl`/`tar`/`doppler` to prove all four classes are producible, executes the alarm body over a stubbed `gh`, and greps the alarm step's `if:` for the three conjuncts (§Acceptance) |

**Deliberately NOT created** (all cut on the simplicity panel's argument, recorded so a later reader
does not re-add them):

- `workspaces-luks-classify.sh` + `.test.sh` — §Decision 6b; the classifier stays inline.
- A new `ADR-158` — §Architecture Decision; ADR-033 is amended instead.
- `scripts/followthroughs/luks-verify-schedule-*.sh` — the Sentry cron monitor verifies the schedule
  *permanently*, where a follow-through probe verifies it once. Keeping both is redundant, and the
  probe additionally costs a tracker issue, a `follow-through` label, a `varq-ban` lint gate and a
  `secrets=` edit to `scheduled-followthrough-sweeper.yml`. **Consequence: this plan declares no
  soak-gated close criterion**, so `/ship` Phase 5.5's Soak-Gated Follow-Through Enrolment Gate does
  not fire — the post-merge check in §Acceptance is a `/soleur:postmerge` spot-check, not a soak.

**Glob verification.** Every path above was confirmed present via `git ls-files` / direct read on
2026-08-03, except the two Files-to-Create.

## Open Code-Review Overlap

**None.** Queried 62 open `code-review` issues (`gh issue list --label code-review --state open
--json number,title,body --limit 200`) and searched each body for
`.github/workflows/workspaces-luks-verify.yml`, `apps/web-platform/infra/luks-monitor.sh` and
`apps/web-platform/infra/workspaces-luks-emit.sh` via standalone `jq --arg`. Zero matches.

## Architecture Decision (ADR/C4)

### ADR — amend ADR-033, do not mint a new ordinal

**Amend `ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`** with a short
addendum recording the anti-circularity corollary. **No new ADR.**

An earlier draft proposed a new `ADR-158`. Rejected on the simplicity panel's argument, which is
correct: ADR-033's own 2026-06-02 scope note already *licenses* this shape, and three existing
workflows (`scheduled-inngest-health`, `scheduled-zot-restart-loop`, `scheduled-realtime-probe`)
already embody it. A new ADR recording "we did what an existing ADR licenses, following a pattern
three files demonstrate" is a filing, not a decision — and it would drag in a provisional-ordinal
caveat, the `/ship` collision gate, a renumber-sweep instruction across plan + `tasks.md` + ACs, an
AC, and a Risks row.

What *is* genuinely unrecorded is the **corollary**, and it belongs in ADR-033 because ADR-033 is
where a future reader looks: *for a monitor whose subject is host X, the scheduling substrate must
not run on host X.* One paragraph in ADR-033's scope note, plus the same reasoning in the workflow
header (already required at Phase 2.1). The reasoning:

- Inngest is self-hosted on the fleet. This workflow's entire subject is web-1's `/mnt/data`. An
  Inngest-scheduled monitor of web-1's volume dies in exactly the scenario the monitor exists to
  detect — the same circular dependency that already forced `scheduled-inngest-health.yml` onto a
  GHA-native `schedule:`.
- An Inngest-fired run arrives as `event_name == workflow_dispatch`, which would (a) collapse the
  `schedule`-only alarm gate and (b) move the read-only guarantee from the workflow into the Inngest
  function, where the `seed_workspace_count` input becomes settable by the scheduler.
- #4116 (a silently-broken Inngest heartbeat unit, dark for 16+ hours) is the concrete cost of
  importing an Inngest dependency into a legal-claim-carrying monitor.

ADR-033's own carve-out supplies the positive case: this is a *credential-heavy infra cron* whose
execution must stay in an ephemeral runner (`DOPPLER_TOKEN` + `WORKSPACES_LUKS_BOOT_TOKEN` + the CF
Tunnel SSH bridge, with "nothing held on the host"). The addendum records the corollary, names the
three GHA-`schedule:`-fired workflows that already embody it, and states that ADR-033 governs and is
not contradicted.

### C4 views

**There IS a C4 impact, and it is a falsified description, not a new element.** All three model
files were read: `model.c4` (594 lines), `views.c4` (62), `spec.c4` (54).

Enumeration performed, per the C4 completeness mandate:

- **(a) External human actors** — none new. The operator/founder actor already receives via both
  paging planes.
- **(b) External systems / vendors** — none new. `github`, `sentry`, `betterstack`, `cloudflare`,
  `hetzner`, `doppler` are all already modelled.
- **(c) Containers / data stores** — none new. `workspacesVolume` already exists and its description
  already cites `workspaces-luks-verify`.
- **(d) Actor ↔ surface access relationships** — none new. The runner → web-1 SSH edge already exists
  (manual verify, cutover, apply-web-platform-infra all use the same bridge). Only the *cadence*
  changes.

**But `model.c4`'s `github -> sentry` edge description states four counts that this change
falsifies**, verbatim: *"posts ok|error check-ins from **6 workflows** — **3 GHA-`schedule:`-fired**
(scheduled-inngest-health, -zot-restart-loop, -realtime-probe) and 3 `workflow_dispatch`-only that
Inngest DISPATCHES per ADR-033… Of **51** cron monitors, **7** check in from here and 44 from
webapp."* Adding a 52nd monitor checking in from a 7th workflow makes all four numbers wrong, and
`workspaces-luks-verify` is a *fourth* GHA-`schedule:`-fired member of a list that enumerates its
members by name.

**Required edit: DELETE the counts, do not increment them.** A prose description carrying four
hand-maintained numbers is a tax every future PR that touches Sentry must pay, and the plan's own
research found the written numbers may already be stale. Replace them with the qualitative claim the
edge is actually for (*"check-ins arrive from GHA-`schedule:`-fired workflows and from
Inngest-dispatched `workflow_dispatch` ones"*), add `workspaces-luks-verify` to the named
GHA-`schedule:`-fired list, and let `cron-monitors.tf` be the single source for the count. This is a
smaller diff, retires the tax, and makes AC17 a grep for the *absence* of counts.

Optionally also strengthen `workspacesVolume`'s description (it cites the certifying run but not the
cadence). Not required by the mandate; fold in only if it does not bloat the diff.

**After editing, run the C4 validation tests** (`apps/web-platform/test/c4-code-syntax.test.ts` and
`c4-render.test.ts`) — a `view include` referencing an undefined element fails there, not at `tsc`.
No new elements are added here, so no `views.c4` `include` line changes.

### Sequencing

Nothing is soak-gated. The ADR-033 addendum ships in this PR, describing a corollary that is true the
moment the schedule lands.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf` — one added `sentry_cron_monitor` resource
  (§Decision 3). No provider changes, no version-pin changes.
- **No new variables**, therefore no `TF_VAR_*` to provision and no operator mint. The resource uses
  only `var.sentry_org` and `data.sentry_project.web_platform`, both already resolved in this root.
- No secrets are introduced. The workflow's Sentry check-in uses the three existing repository
  secrets the composite action already consumes (`SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`,
  `SENTRY_PUBLIC_KEY`), which 7 sibling workflows already pass.

### Apply path

**(a) Auto-apply on merge, no operator step.** `.github/workflows/apply-sentry-infra.yml` fires on
push to `main` with a `paths:` filter covering the whole `infra/sentry/**` tree and plans FULL-ROOT
(no `-target=`) since #6589. Blast radius: creating one monitor. Expected downtime: none —
`sentry_cron_monitor` is a vendor-side alerting object with no runtime dependency.

**Ordering hazard, and why it is benign here.** The monitor is created *after* the workflow's first
scheduled check-in could theoretically occur. It cannot actually invert: the merge triggers the apply
immediately, and the first scheduled fire is at the next 04:41 UTC. Even if it did, the composite
action's secret-guard exits 0 with a `::warning::` rather than failing the run, and a check-in to a
non-existent monitor is discarded, not fatal.

### Distinctness / drift safeguards

- No `dev`/`prd` distinctness question — the sentry root is single-environment and prd-only.
- No `lifecycle.ignore_changes` needed; `sentry_cron_monitor` is fully declarative and no operator
  edits it in the dashboard.
- No sensitive values land in `terraform.tfstate` from this resource (org slug, project slug, crontab
  string, integers).
- **Destroy-guard interaction:** `apply-sentry-infra.yml` is gated pre-merge by
  `sentry-destroy-required` + `[ack-destroy]`. This PR is a pure create, so that gate must show zero
  destroys — assert it in the ACs rather than assuming it.

### Vendor-tier reality check

Sentry Crons monitors are included in the existing plan — 51 already exist in this same root, so the
52nd carries no tier gate and no new spend. `wg-record-recurring-vendor-expense-before-ready` does
not fire: no new recurring vendor expense.

## Observability

```yaml
liveness_signal:
  what: >-
    Sentry Crons check-in for monitor slug `workspaces-luks-verify`, posted by
    ./.github/actions/sentry-heartbeat as the final step of each SCHEDULED run.
    Status is producer-status-first: ok iff
    (steps.reassert.outcome == 'success' && steps.reassert.outputs.outcome_class == 'pass').
  cadence: >-
    daily, 41 4 * * * UTC. checkin_margin_minutes = 420 + failure_issue_threshold = 2 —
    below the file's margin==interval convention so a dark schedule is detectable, paired with
    a 2-miss threshold so a lone GitHub-dropped run stays silent (#4189). See Decision 3.
  alert_target: >-
    Sentry issue on an error check-in, or on TWO consecutive missed check-ins
    (failure_issue_threshold = 2, ~31 h) -> the
    sentry issue-alert plane -> ops@jikigai.com. Second, independent source:
    the ci/luks-verify GitHub issues (three titles under one label).
  configured_in: >-
    apps/web-platform/infra/sentry/cron-monitors.tf (auto-applied on merge by
    .github/workflows/apply-sentry-infra.yml)

error_reporting:
  destination: >-
    (1) GitHub issue via `gh issue create`, one of three classes/labels;
    (2) the existing host-side Sentry envelope feature=workspaces-luks
        op=workspaces-luks-drift (emitted by luks-monitor.sh via workspaces-luks-emit.sh,
        matched by sentry_issue_alert.workspaces_luks_drift in issue-alerts.tf);
    (3) Sentry Crons `error` check-in;
    (4) the host probe log, shipped to Better Stack Logs source 2457081 by Vector
        under SyslogIdentifier `luks-monitor` (vector.toml include_matches allowlist).
  fail_loud: >-
    yes. An absent or empty outcome_class output is classified `unavailable` and alarms;
    it is never read as a pass. The alarm step leads with always() (NOT !cancelled() —
    see Decision 5), never a bare if: failure(). The Sentry status gates POSITIVELY
    on == 'pass'.

failure_modes:
  - mode: LUKS mount reverted / at-rest drift (rc 1; not_mounted, mount_not_mapper, device_not_luks, escrow_passphrase_mismatch, header_uuid_unreadable)
    detection: luks-monitor.sh exit 1 -> workflow emits outcome_class=drift
    alert_route: GitHub issue "[ci/luks-verify] at-rest drift on /mnt/data" (ci/luks-verify + type/security + priority/p0-critical + action-required, body carries first_observed_at and the counsel trigger-(3) pointer) + host Sentry op=workspaces-luks-drift + Sentry Crons error
  - mode: workspace inventory shortfall (sole-copy data loss) — rc 3 reason=workspace_count_shortfall
    detection: workflow emits outcome_class=readiness
    alert_route: GitHub issue "[ci/luks-verify] readiness or inventory failure" (ci/luks-verify + action-required; priority/p0-critical for workspace_count_shortfall, else priority/p1-high) + Sentry Crons error
  - mode: app cannot serve from the mount — rc 3 reason=readyz_not_ready, or empty/unparsed reason, or the app health endpoint returned a STRUCTURAL code (the enumerated 307|401|403|404|405|525|526 arm — a routing regression)
    detection: workflow emits outcome_class=readiness
    alert_route: same readiness route (issue + ops-email)
  - mode: cannot reach web-1 (rc 255 SSH transport), bundle never landed (rc 127), or the app health endpoint stayed non-200 on a RETRYABLE code (521/530/000/502/503/504 — a Cloudflare-edge outage) after the full attempt budget
    detection: workflow emits outcome_class=unavailable
    alert_route: GitHub issue "[ci/luks-verify] could not verify — nothing proven" (ci/luks-verify + priority/p1-high + action-required) + Sentry Crons error. No DIRECT ops-email (though the Sentry check-in still routes to the issue-alert plane)
  - mode: probe-integrity fault (rc 3 with readyz_gate_regression|readyz_unparseable|readyz_unreachable|readiness_helper_unavailable|workspace_count_baseline_missing|workspace_count_unreadable|mapper_path_override_refused) or the SOLEUR_WORKSPACES_READYZ verdict line absent
    detection: workflow emits outcome_class=unavailable
    alert_route: same unavailable route
  - mode: the step dies before writing any output (runner OOM, step timeout, bridge action failed so the step never ran)
    detection: steps.reassert.outcome != 'success' OR outcome_class == '' -> treated as unavailable
    alert_route: same unavailable route (fail-closed; this is the #7138 shape)
  - mode: the SCHEDULE ITSELF stops firing (workflow disabled after 60d repo inactivity, cron dropped by GitHub as on 2026-05-26, YAML disabled, file renamed)
    detection: Sentry Crons missed check-in on slug `workspaces-luks-verify` past checkin_margin_minutes
    alert_route: Sentry issue after TWO consecutive missed check-ins (~31 h). One of THREE modes only this layer can see.
  - mode: FM2 — a pending scheduled run cancelled by concurrency supersession (executes no steps at all)
    detection: Sentry Crons missed check-in. No in-run construction can report this.
    alert_route: Sentry issue
  - mode: job timeout (SSH hang over the CF Tunnel against timeout-minutes 15; the runner allocation is torn down)
    detection: Sentry Crons missed check-in
    alert_route: Sentry issue
  - mode: the Sentry monitor itself is deactivated by a PAYG renewal shortfall (#3958 — "every monitor deactivates at once and check-ins are silently dropped")
    detection: NOT auto-detected. The vendor-free fallback is the Article 30 evidence query (gh run list --event=schedule --status=success), which is why L1 names it as the PRIMARY durable-evidence path.
    alert_route: none automatic — a named residual, tracked by #3958

logs:
  where: >-
    GitHub Actions run log + $GITHUB_STEP_SUMMARY (public repo); host probe output via
    journald -> Vector -> Better Stack Logs source 2457081; alarm issue bodies retain
    class + reason + run URL.
  retention: >-
    GH Actions logs 90d (run metadata persists beyond); Better Stack Logs per source plan;
    GitHub issues indefinite.

discoverability_test:
  command: >-
    gh run list --workflow=workspaces-luks-verify.yml --event=schedule --limit 10
    --json conclusion,createdAt,databaseId
    && gh issue list --state open --json number,title,labels
    --jq '.[] | select(.labels[].name | startswith("ci/luks-verify"))'
  expected_output: >-
    at least one row with conclusion="success" created within the last 48h; empty issue
    list when healthy. No ssh, no dashboard.
```

## Encryption Posture

Detection fires because `## Files to Edit` includes a `.tf` path. Recorded rather than skipped.

```yaml
at_rest:
  - store: (none introduced)
    mechanism: n/a — this change adds no persistent store. The sentry_cron_monitor is a
      vendor-side alerting object holding a crontab string and integers.
    evidence: apps/web-platform/infra/sentry/cron-monitors.tf; no volume, bucket, table,
      queue, cache or backup target is created.
    defends_against: n/a
    does_not_defend: n/a
    disclosed_as: n/a
    live_verification: n/a
  - store: (existing, unchanged) hcloud_volume.workspaces_luks — the subject of this monitor
    mechanism: guest-side LUKS2, /dev/mapper/workspaces, passphrase in Doppler prd_workspaces_luks
    evidence: ADR-119; article-30-register.md PA-1(g)(17); run 30749271370 device_type=crypto_LUKS
    defends_against: a seized, RMA'd or snapshot-imaged block volume
    does_not_defend: a live host with the mapper open; the retained plaintext
      hcloud_volume.workspaces (the ADR-119 rollback backstop — a ledgered plaintext-exception,
      tracking #6897, expires_on 2026-10-22)
    disclosed_as: docs/legal/data-protection-disclosure.md correction banner (present tense)
    live_verification: THIS workflow. Manual today; daily after this PR — which is the point.

in_transit:
  - connection: GH runner -> web-1:22, over the Cloudflare Tunnel SSH bridge
    tls: yes — cloudflared TLS to the CF edge, plus SSH transport encryption inside it
    cert_verification: >-
      PARTIAL, PRE-EXISTING. cloudflared verifies the CF edge. The SSH layer does NOT
      authenticate the host: .github/actions/cf-tunnel-ssh-bridge sets
      `-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null`, i.e. TOFU with
      no persistence, so the key is re-accepted unverified on every connection.
    does_not_defend: >-
      an adversary in the CF-edge position (Cloudflare itself, or anyone who obtains the tunnel
      credential) impersonating web-1 and returning a forged PASSED verdict. This PR increases
      the exposure only in frequency (daily vs. manual), not in kind, and it is shared with
      workspaces-luks-cutover.yml, git-data-cutover.yml and apply-web-platform-infra.yml.
    disclosed_as: not published — an internal CI control-plane property, no user-facing claim
  - connection: GH runner -> the app health endpoint over public HTTPS
    tls: yes
    cert_verification: on (curl default; no -k)
    does_not_defend: nothing at the transport layer; the endpoint returns 200 unconditionally
      and is a liveness signal only
    disclosed_as: n/a
  - connection: GH runner -> Sentry ingest (Crons check-in)
    tls: yes
    cert_verification: on (curl -fSs, no -k)
    does_not_defend: n/a
    disclosed_as: Art. 30 register — Sentry as a sub-processor, DE residency (de.sentry.io)
  - connection: GH runner -> GitHub API (gh issue create/list/comment/close)
    tls: yes
    cert_verification: on
    does_not_defend: n/a
    disclosed_as: article-30-register.md — GitHub Inc. as a US sub-processor under SCCs

exception:
  - applies_to: "in_transit: GH runner -> web-1:22 (cert_verification partial)"
    justification: >-
      PRE-EXISTING and out of scope for this PR. Host-key pinning lives in the shared
      cf-tunnel-ssh-bridge composite action and would change the SSH contract for the cutover,
      recut, git-data-cutover and apply-web-platform-infra paths simultaneously — a blast radius
      an alarm-wiring PR must not take. Named here rather than left silent because a monitor
      whose verdict an unauthenticated peer could forge is a weaker monitor, and this PR makes
      that monitor load-bearing for a published Article 32 claim.
    tracking_issue: >-
      #7226 — "security: cf-tunnel-ssh-bridge accepts web-1's SSH host key unverified on every
      connection (TOFU with no persistence)". FILED 2026-08-03 at /work time with
      type/security + priority/p2-medium + domain/engineering, and linked from the
      workspaces-luks-verify.yml header. Deliberately NOT #5914 ("Pin git-data host key: replace
      accept-new TOFU on private-net git SSH"), which is the sibling for a DIFFERENT surface
      (git-auth.ts, application-level git SSH over the private network), and not #748
      (CLOSED/COMPLETED 2026-03-20), which covered the appleboy/ssh-action mechanism this
      composite replaced.
    reevaluate_when: >-
      the next change to .github/actions/cf-tunnel-ssh-bridge, or the first arms-length data
      subject (which flips the counsel audit's DC-1 residual to p0 and re-opens every
      CI-control-plane assumption).
    expires_on: 2026-11-03
```

## Legal — what the schedule changes about the published record

Assessed by the CLO domain leader. Three items are **blocking**; none changes the counsel audit's
disposition.

### L1 (blocking) — Article 30 register

`knowledge-base/legal/article-30-register.md` PA-1(g)(17) and PA-2(g)(21) currently record
verification as two *dated past events*, both citing run `30130277489` (2026-07-24). The counsel
audit §A3.6 sets the standard that *"no published sentence is stronger than the Article 30 register
in either direction."* If a daily automatic verification lands and the register is not updated, the
published present-tense claim becomes **stronger than the register** — inverting the exact ordering
the audit signed off on.

Edit both TOM items to record (a) that verification is now performed automatically daily by the
scheduled `workspaces-luks-verify` run, (b) where the durable evidence lives, and (c) the current
discharge run `30749271370` (2026-08-02) in place of the stale `30130277489`.

**Durable evidence location — no human ritual.** The register must name where a future reader proves
"a successful run landed", because the trailing-30-day test is evaluated after the fact and CI logs
are bounded. Two sources, both queryable, neither requiring a recurring operator edit:

1. `gh run list --workflow=workspaces-luks-verify.yml --event=schedule --status=success --created '>=<date>'`
   — run *metadata* (conclusion, timestamp) persists beyond the 90-day log-retention window.
2. The Sentry Crons check-in history for monitor `workspaces-luks-verify`.

**Verify at /work time** that Sentry Crons check-in history is retained ≥ 30 days before citing it as
the second source; if it is not, cite source (1) alone. Do not assert a vendor retention window
without checking it.

### L2 (blocking) — counsel audit annotation

`knowledge-base/legal/audits/2026-07-counsel-review-6588.md` frontmatter field `claim_decay_trigger`
asserts as fact: *"While #6808 is OPEN, `workspaces-luks-verify` is workflow_dispatch-only and no
automatic verification of any kind exists."* #6808 stays open; **the premise dies on merge.** A false
frontmatter field is worse than a stale one, and it is the field a future reader greps.

A **short annotation, not a full Amendment No. 4**:

- Annotate `claim_decay_trigger` in place, recording that the dispatch-only premise was retired by
  this PR, with the merge date and the PR number.
- **Correct §A3.4 recommendation 2 in the same pass.** It reads that #6808 should not be closeable
  until either the heartbeat is wired *or* the schedule exists. On the audit's own terms that
  disjunct is now half-met, so the annotation must state explicitly that the schedule is a
  **compensating** control which does **not** retire the heartbeat requirement, and that #6808's
  closure condition remains heartbeat-wired **and** the Phase-5 plaintext wipe per re-evaluation
  trigger (1). Without this, a future reader closes #6808 on the schedule alone.
- **Disposition unchanged.** SIGNED-OFF WITH ACCEPTED RESIDUAL stands. Re-evaluation trigger (1) is
  NOT satisfied — the heartbeat is still unwired and the plaintext wipe has not happened. The DC-1
  retained-plaintext residual is untouched by this PR.

### L3 (blocking) — absence detection

The decay trigger's defeat condition is *absence*: a schedule that stops firing produces no run, no
failure and no alarm, and an alarm keyed on failure cannot fire on a job that never ran. Discharged
by the Sentry Crons monitor (§Decision 3). This is why that monitor is in scope and not deferred.

### L4 — drift-class issue body requirements

The `drift` class is the only class that is a legal event. Its issue body MUST carry:

- a **`first_observed_at` ISO-8601 UTC timestamp** — the house Art. 33 anchoring convention
  (`knowledge-base/legal/statutory-response-catalog.md`, cross-cutting Art. 32 "Incident response");
- a one-line pointer that this class fires **re-evaluation trigger (3)** of
  `knowledge-base/legal/audits/2026-07-counsel-review-6588.md` and requires CLO review of the three
  published banner sentences.

### L5 — no new Article 30 processing activity, and no published-document edit

- **No new PA entry.** The egress is integers and status codes (`device_type`, `mount_source`,
  `workspace_count`/`expected`, `ready`, HTTP codes). Workspace directory names never cross the SSH
  boundary — `wl_count_workspace_dirs` is pure shell precisely so a permission or symlink error
  cannot carry a user-identifying path into the run log. No new category of personal data, no new
  category of data subject. The in-register precedent is PA-12 (GitHub branch-protection state
  custody), which records `(c) Categories of personal data | None of substance` for this same
  CI-control-plane shape and is *stronger* than a read-only daily verify. State once in the PR that
  failure output stays field-limited to the same integers.
- **No Chapter V analysis opened.** Actions run logs are US-hosted; GitHub Inc. is already mapped as
  a US sub-processor under SCCs in the register, and integers plus status codes carry no personal
  data.
- **Do not edit `docs/legal/*`.** The published clause describes *what the check confirms*, not how
  often it runs — no "continuously", no "daily", no "automatically". The schedule moves the claim
  from narrowly true (true only in the window after each manual dispatch) to robustly true; it
  creates no new claim and falsifies nothing. Three reasons not to touch the banners: publishing a
  cadence converts an internal rhythm into a **published commitment whose breach becomes a new decay
  trigger**; the banner is a Tier-1 corrections-regime artifact and re-opening it across three
  mirrored documents for a change with no user-relevant fact is unjustified churn; and the audit's
  "Door 2" is a remedy for decay, which this PR removes the need for rather than invokes.

> **Standing caveat (CLO):** this is draft material and an internal v1 attestation, not external
> legal advice. External counsel re-review remains reserved for the audit's frontmatter
> re-evaluation triggers — notably the first arms-length data subject, which would flip the DC-1
> residual to p0 regardless of anything in this PR.

## Implementation Phases

Phase order is load-bearing: the classification contract must exist before anything consumes it.

### Phase 0 — Preconditions (verify, do not assume)

0.1 `cd` to the worktree; confirm `git branch --show-current` = `feat-one-shot-6808-luks-verify-schedule`.
0.2 Re-run the §Premise Validation table's live checks. Any divergence halts and re-scopes.
0.3 Read ADR-033's 2026-06-02 scope note in full and confirm the anti-circularity corollary is genuinely absent from it before drafting the addendum. No new ordinal is minted, so no collision sweep is needed.
0.4 Read `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` and determine whether its workflow enumeration assumes a `scheduled-*` filename prefix. Record the answer; it decides whether Phase 3 needs an extra edit.
0.5 Baseline the three grep-anchored constraints so drift is detectable: record current values of AC7 (`grep -c` of the API-prefixed health literal → expect 0), AC10 (the extracted `307|…` set), and `luks-monitor.test.sh` case (y)'s verdict-grep pattern.
0.6 Run `bash apps/web-platform/infra/run-registered-suites.sh --list` and confirm the workspaces-luks suites are green **before** any edit, so a later failure is attributable.

### Phase 1 — Unblock CI, then RED

**1.0 — do this first.** Add `- ".github/workflows/workspaces-luks-verify.yml"` to
`.github/workflows/infra-validation.yml`'s `paths:` list (§Decision 6a). Until this lands, every
guard in this PR is unreachable on the PRs that would break it. Confirm by opening the PR and
checking that the infra-validation job actually runs.

**1.0b** — Register `workspaces-luks-verify-workflow.test.sh` in `infra-validation.yml` (see 1.1).

**1.1 — the workflow-level suite.**
Create `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`, mirroring
`apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh` (the same-feature precedent) and
borrowing the PATH-stub technique from `git-data-rung2-rehearsal.test.sh` arm 13 where `bash -e`
fidelity matters. Structure:

1. **Parse the workflow as YAML with PyYAML** (`python3 -c 'import yaml' || pip3 install --quiet pyyaml`).
   Never grep for structure — a grep passes vacuously.
2. **Extract every `run:` body** to `$SCRATCH/run-N.sh` and `bash -n` each. Empty extraction is a
   hard `fail`, never a skip.
3. **Extract the `id: reassert` step's body** and **execute** it under `bash -e` (what GitHub actually
   uses) with `ssh`, `curl`, `tar` and `doppler` stubbed on `PATH`, driving each branch:
   - probe rc 0 + health 200 + verdict line present → `outcome_class=pass` **(positive control)**
   - probe rc 1 → `drift`
   - probe rc 3 + `workspace_count_shortfall` → `readiness`
   - probe rc 3 + `readyz_not_ready` → `readiness`
   - probe rc 3 + `workspace_count_baseline_missing` → `unavailable`
   - probe rc 3 + `readyz_gate_regression` → `unavailable`
   - probe rc 3 + **empty/unparsed** reason → `readiness` (fail-closed toward louder)
   - probe rc 255 → `unavailable`; probe rc 127 → `unavailable`
   - probe rc 0 but verdict line ABSENT → `unavailable` (the #6807 silent-green shape)
   - probe rc 0 + health **307** (STRUCTURAL) → `readiness`
   - probe rc 0 + health **521** / **530** / **000** after the full attempt budget (RETRYABLE
     exhausted) → `unavailable`, **not** a finding (§Decision 2, CTO BLOCKER-2)
   - `GITHUB_EVENT_NAME=schedule` + non-empty `SEED_WORKSPACE_COUNT` → refused, non-zero exit,
     `outcome_class=unavailable`, **and no seed write reaches the ssh stub**
   - `GITHUB_EVENT_NAME=schedule` + empty `SEED_WORKSPACE_COUNT` → the seed branch is not entered
     (assert the ssh stub records no `WORKSPACES_COUNT=` append)
4. **Non-vacuity floor:** assert the fixture set produced **at least one of each** of `pass`, `drift`,
   `readiness`, `unavailable`. A battery that only ever produces one class proves nothing.
5. **Extract the alarm + close + heartbeat steps as YAML objects** and assert the *wrapper*, not just
   the body — the body observes the shell and nothing around it:
   - the Re-assert step carries `id: reassert`
   - the alarm step's `if:` contains `always()` and does **not** rely on a bare `failure()`
   - the alarm step's `if:` names all three conjuncts: `always()`, `github.event_name == 'schedule'`,
     and the `outcome_class` clause
   - the alarm step's `if:` names `steps.reassert.outcome` as a conjunct (producer-status-first)
   - the alarm step's `if:` and the close step's `if:` are mutually exclusive over the enum
   - the heartbeat `status:` expression gates **positively** on `== 'pass'`
   - the alarm and close steps are not `continue-on-error` (that would make every alarm advisory)
   - the heartbeat step IS `continue-on-error: true` and `always()`
   - `permissions:` contains `issues: write`
   - the `schedule:` cron equals the `sentry_cron_monitor` crontab in `cron-monitors.tf`
     (parity — a drifted pair silently mis-sizes the margin)
   - the classifier is **absent** from the `tar czf -` host-bundle file list
6. **Execute the alarm step's body** with a stub `gh` on `PATH` that records argv, proving:
   - `gh label create … || true` runs for the class's label and a pre-existing label does not fail
     the step
   - dedupe **queries before creating**, and comments instead of creating when an open issue with
     the exact title exists
   - the three classes route to three distinct labels **and** three distinct titles
   - a `drift` body contains `first_observed_at` and the counsel trigger-(3) pointer
   - an empty `outcome_class` routes to `unavailable` (fail-closed)
   - a green scheduled run files nothing and closes nothing (there is no close step)
   - **[SUPERSEDED by §Decision 2 — NOT IMPLEMENTED]** a *recently-closed* `unavailable` issue is **reopened**, not re-created
     (flap-churn guard). Decision 2 deleted auto-close, and with it the reopen path: nothing in
     the shipped workflow ever closes an issue, so there is no closed issue to reopen.
   - a repeat failure with an **unchanged** `reason` does not add a new comment
   - the ops-email step fires for `drift` and `readiness` and **not** for `unavailable`
7. `MIN_ASSERTIONS` floor (≥ 40, matching the sibling suite's `WF_MIN_ASSERTIONS`) — fewer passes is
   a hard exit 1.

Run it. It MUST fail (the workflow has no classification yet). A test that passes before the change
is testing nothing.

### Phase 2 — GREEN: the workflow

2.1 Add the `schedule:` trigger with a header comment carrying the ADR-033 carve-out citation, the
    anti-circularity corollary, the cadence justification and the §Decision 1 sunset note.
    Leave `workflow_dispatch:` and its input **byte-identical**.
2.2 `permissions:` → `contents: read` + `issues: write`.
2.3 Add `id: reassert` to the Re-assert step.
2.4 Implement the inline classifier (reason-first, then rc) against the Phase 1 fixtures, and call
    `emit_class` immediately before **every** `exit`, including the early `WEB_HOST_SSH` guard.
    Hoist the `sed` reason extraction above the rc branching. Change no existing `::error::` string
    and no existing exit code.
2.5 Add the scheduled-seed refusal guard (§Decision 4), placed before any seed handling.
2.6 Add `emit_class pass` before the final PASSED echo.
2.7 Add the alarm step **after** the bridge-teardown steps (so the SSH key is shredded before `gh`
    runs), with the `case`-based class routing, idempotent `gh label create … || true`, label+title
    dedupe, ~~the reopen-not-recreate path for `unavailable`~~ (**SUPERSEDED by §Decision 2 —
    do NOT build this**; it is a build instruction for a mechanism that was deliberately cut),
    and the comment-on-reason-change bound.
2.8 *(no green-close step — §Decision 2. A green run files nothing and closes nothing.)*
2.9 Add the `notify-ops-email` step for `drift` and `readiness` only.
2.10 Add the Sentry check-in step last (`always()`, `continue-on-error: true`,
    `github.event_name == 'schedule'`, producer-status-first `status:` gating positively on `'pass'`).
2.11 Re-run Phase 1's suites until green. Re-run `workspaces-luks-freeze.test.sh`,
     `luks-monitor.test.sh` and `workspaces-luks-header.test.sh` — AC7, AC10, case (y) and H15b/H20
     must all still pass (§Sharp Edges 3-5, 13).
2.12 `bash scripts/lint-workflows.sh` (actionlint).

### Phase 3 — Sentry monitor + vendor expense

3.1 Add the `sentry_cron_monitor` resource to `apps/web-platform/infra/sentry/cron-monitors.tf` with
    a comment explaining the three absence modes it covers that the issue-filing path structurally
    cannot (§Decision 3), and the #3958 deactivation residual.
3.2 Confirm via `bash apps/web-platform/infra/run-registered-suites.sh --list` that both new suites
    appear — the runner derives its list from `infra-validation.yml`, so an unregistered suite never runs.
3.3 Run `sentry-monitor-iac-parity.test.ts` — it auto-discovers the new slug and fails if the TF
    resource is absent. No edit to the test itself.
3.4 Run the sentry-root plan locally and confirm **zero destroys** (the `sentry-destroy-required`
    gate must stay unarmed; creates pass `scripts/sentry-create-gate.sh` silently with no ack).
3.5 Re-measure the live Sentry PAYG figure and update the `knowledge-base/operations/expenses.md`
    Sentry Team row (+1 cron-monitor seat, +$0.78/mo). `wg-record-recurring-vendor-expense-before-ready`
    blocks PR-ready without this.

### Phase 4 — Documentation truth-maintenance

4.1 ADR-033 anti-circularity addendum (§Architecture Decision).
4.2 `model.c4` `github -> sentry` counts, re-derived mechanically, then the C4 validation tests.
4.3 Article 30 register PA-1(g)(17) + PA-2(g)(21) (L1).
4.4 Counsel audit annotation + §A3.4 recommendation-2 correction (L2).
4.5 Runbook §5 triage rows for the three alarm classes; note the check is now daily-automatic.
4.6 File the cf-tunnel-ssh-bridge host-key tracking issue and link it from the Encryption Posture
    exception row and the workflow header.
4.7 **No follow-through enrolment.** The Sentry cron monitor verifies the schedule permanently,
    where a probe would verify it once; keeping both is redundant. This plan therefore declares **no
    soak-gated close criterion**, so `/ship` Phase 5.5's Soak-Gated Follow-Through Enrolment Gate does
    not fire. If a reviewer re-introduces a time-gated close criterion in prose, the enrolment
    becomes mandatory again — do not let one slip in unnoticed.

### Phase 5 — Verification

5.1 `bash apps/web-platform/infra/run-registered-suites.sh` — full infra suite.
5.2 `bash scripts/test-all.sh`.
5.3 Walk every Acceptance Criterion, running its literal command.
5.4 `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <this plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'`.

## Acceptance Criteria

### Pre-merge (PR)

1. `.github/workflows/workspaces-luks-verify.yml` has a `schedule:` trigger with cron `41 4 * * *`,
   and the `workflow_dispatch:` block — including `seed_workspace_count`'s `description`,
   `required`, `type` and `default` — is byte-identical to `origin/main`
   (`git diff origin/main -- .github/workflows/workspaces-luks-verify.yml` shows no change inside
   the `workflow_dispatch:` block).
2. `permissions:` contains both `contents: read` and `issues: write`.
3. The Re-assert step carries `id: reassert` and writes `outcome_class` to `$GITHUB_OUTPUT` before
   every `exit`; `grep -c 'emit_class ' .github/workflows/workspaces-luks-verify.yml` ≥ the number of
   `exit` statements in that step.
4. Every existing `::error::` string and every existing exit code in the Re-assert step is unchanged
   (`git diff origin/main` shows no modified `::error::` line and no modified `exit <n>`).
5. **The alarm's failure branch is proven reachable by a committed, executing test**, not asserted in
   prose: `bash apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` passes, and its
   non-vacuity guard confirms the fixture set produced **all four** of `pass`, `drift`, `readiness`,
   `unavailable`. **Two mutation checks, both required** — the first alone is a proxy:
   (a) reverting the classification block makes the suite RED; (b) **mutating the alarm `if:`** —
   dropping `always()`, flipping `&&` to `||`, or inverting the class clause — also makes it RED.
   Without (b) the suite proves the alarm *body* works, never that the alarm *fires*.
5b. **A PR that touches ONLY the workflow YAML runs the guard suites.**
   `grep -c '".github/workflows/workspaces-luks-verify.yml"' .github/workflows/infra-validation.yml` == 1.
   Do **not** additionally assert "this PR's infra-validation job ran" — that is vacuous, because
   this PR also creates a file under `apps/web-platform/infra/`, which `infra-validation.yml`'s first
   glob (`apps/*/infra/**`) already matches. That file's own comment names this exact trap
   (*"PR #7094 ran this job only incidentally"*). Instead, `workspaces-luks-verify-workflow.test.sh`
   carries a mechanical drift assertion: **every file the suite greps must appear in
   `infra-validation.yml`'s `paths:`.**
6. `bash apps/web-platform/infra/run-registered-suites.sh --list` lists
   `workspaces-luks-verify-workflow.test.sh`.
7. The alarm step's `if:` is asserted by an **evaluated truth table**, not a substring grep: over
   `steps.reassert.outcome ∈ {success, failure, skipped, cancelled}` ×
   `outcome_class ∈ {pass, drift, readiness, unavailable, ''}`, the alarm fires on every cell except
   `(success, pass)`. A substring check passes for an inverted expression, for `||` in place of
   `&&`, and for a negated class clause. Additionally: the Re-assert step carries `id: reassert`, and
   `grep -c 'if: failure()' .github/workflows/workspaces-luks-verify.yml` == 0.
7b. A retryable-code health exhaustion (521/530/000) classifies as `unavailable`, and a STRUCTURAL
   code (307/401/403/404/405/525/526) as `readiness` — asserted by a classifier fixture, and the
   STRUCTURAL set is read from the existing case-arm rather than re-listed (CTO BLOCKER-2).
8. The Sentry check-in `status:` expression gates positively on `steps.reassert.outputs.outcome_class == 'pass'`
   ANDed with `steps.reassert.outcome == 'success'` (no `!=` form).
9. One label `ci/luks-verify` created idempotently (`gh label create … || true`); the three classes
   are distinguished by **title**, and the alarm step declares
   `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` in its `env:` (the `gh` calls are unauthenticated without
   it, and neither AC10 nor the label AC would catch that).
9b. `RESEND_API_KEY` is guarded in the `Verify required secrets present` step, and the alarm step
   records the email step's outcome in the issue body (a non-2xx from Resend exits 0 with only a
   `::warning::`, so the issue is the only durable evidence a page was dropped).
9c. `knowledge-base/operations/expenses.md`'s Sentry Team row records the added cron-monitor seat
   with a re-measured live PAYG figure (`wg-record-recurring-vendor-expense-before-ready`).
9d. `workspace_count_shortfall` carries `priority/p0-critical`; other `readiness` reasons carry
   `priority/p1-high` (severity assigned on user impact per
   `hr-weigh-every-decision-against-target-user-impact`).
10. Dedupe uses `gh issue list --label … --json number,title` plus a standalone `jq`; the file
    contains no `gh issue list --search` (`grep -c -- '--search' … ` == 0).
11. A scheduled run cannot seed: the test drives `GITHUB_EVENT_NAME=schedule` with a non-empty
    `SEED_WORKSPACE_COUNT` and asserts a non-zero exit **and** that the ssh stub recorded no
    `WORKSPACES_COUNT=` append.
12. The workflow's `schedule:` cron and the `sentry_cron_monitor`'s `crontab` are equal (asserted by
    the test); `checkin_margin_minutes = 420` **and** `failure_issue_threshold = 2`; and the resource
    comment cites #4189 and states why BOTH depart from convention — reverting either in isolation
    breaks something (§Decision 3).
13-14. *(folded into AC20 — `run-registered-suites.sh` + `test-all.sh` already run
    `workspaces-luks-freeze.test.sh`, `luks-monitor.test.sh` and `workspaces-luks-header.test.sh`;
    three separate "the pre-existing suite still passes" criteria were restating that.)*
15. `bash scripts/lint-workflows.sh` exits 0.
16. `ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` carries the
    anti-circularity addendum, and no new ADR ordinal is minted.
17. `model.c4`'s `github -> sentry` description no longer carries hand-maintained counts at all
    (`grep -cE '[0-9]+ (workflows|cron monitors)' `→ 0 on that edge) — the counts are **removed**,
    not incremented, retiring a recurring tax on every future Sentry PR. C4 validation tests pass.
18. `knowledge-base/legal/article-30-register.md` PA-1(g)(17) and PA-2(g)(21) both record the daily
    scheduled verification, name the durable evidence query, and cite run `30749271370`;
    `grep -c '30130277489' knowledge-base/legal/article-30-register.md` == 0.
19. `knowledge-base/legal/audits/2026-07-counsel-review-6588.md` `claim_decay_trigger` is annotated
    with the merge-date retirement of the dispatch-only premise, §A3.4 recommendation 2 is corrected
    to state that the schedule does not retire the heartbeat requirement, and the disposition line
    still reads SIGNED-OFF WITH ACCEPTED RESIDUAL.
20. `bash scripts/test-all.sh` passes.
21. The sentry-root `terraform plan` shows a pure create — zero destroys, zero replaces.
22. The PR body uses `Ref #6808` and contains no `Closes #6808` / `Fixes #6808`.
23. A tracking issue exists for the cf-tunnel-ssh-bridge host-key TOFU residual, linked from the
    Encryption Posture exception row (and it is **not** #5914, which covers a different surface).

### Post-merge (operator)

None. Every step is automated:

- The `sentry_cron_monitor` is applied by `.github/workflows/apply-sentry-infra.yml` on push to
  `main` (FULL-ROOT, `paths:` covers `infra/sentry/**`).
- The single `ci/luks-verify` label is created idempotently by the workflow itself on first alarm —
  no pre-seeding needed.
- The first scheduled run fires at the next 04:41 UTC with no dispatch.

**Post-merge verification, by `/soleur:postmerge` — two spot-checks, no soak:**

1. **Fire the alarm self-test once.** `gh workflow run workspaces-luks-verify.yml -f alarm_selftest=true`,
   confirm an issue titled `[ci/luks-verify] SELF-TEST — ignore` is filed, then close it. This is the
   only execution of the alarm path against **real GHA expression evaluation** that will ever happen
   before a genuine failure — everything else tests our model of that evaluation.
2. **Confirm the schedule fired.** After the next 04:41 UTC,
   `gh run list --workflow=workspaces-luks-verify.yml --event=schedule --limit 3` shows a
   `conclusion=success` row, and the Sentry monitor `workspaces-luks-verify` shows a check-in.

Neither is a soak-gated close criterion, so `/ship` Phase 5.5's enrolment gate does not fire; the
Sentry monitor provides the standing verification a follow-through probe would have provided once.

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| **Post-deploy/post-reboot hook + weekly backstop** (the strongest counter — CTO steelman) | The at-rest state is boot-immutable, so an event-shaped signal would match the only real mutation source at 1/7 the SSH surface. Rejected because half the probe is **not** boot-immutable: the readyz + inventory dimension is GHA-only (`LUKS_MONITOR_ASSERT_READYZ` default-OFF on the host) and inventory can shrink at any time — and because while #6808 is open this workflow is the compensating channel for a *daily* push. Fully argued in §Decision 1 |
| **Weekly cron (~4× margin)** | Only 4 attempts per 30-day window and 7-day detection latency on a false published Article 32 claim. GHA `schedule:` jitter is measured at up to 339 min in this repo, `cron-monitors.tf` records GitHub dropping a scheduled run entirely on 2026-05-26, and the CF Tunnel bridge has an outage class (`ci/tunnel-connector-drift`), so 3 consecutive misses is not remote. It also under-fires the daily channel it compensates for |
| **Every 3 days (~10×)** | Satisfies neither the "matches `luks-monitor.timer`'s daily cadence" argument nor the max-attempts argument, and buys nothing measurable since runner minutes are free on a public repo |
| **Inngest cron → `workflow_dispatch`** (ADR-033 Option C, `cron-terraform-drift.ts` shape) | Circular: Inngest **executes** functions on the fleet whose volume this monitors — a single `sdk_url` callback pinned to web-1 — so the **dispatching function never runs** in exactly the scenario the monitor exists to detect (the *scheduler* itself moved to its own host at the #6178 cutover, ADR-100; it is EXECUTION that is pinned) — the same reason `scheduled-inngest-health.yml` is GHA-native. Also collapses the `schedule`-only alarm gate and moves the read-only guarantee into the dispatcher, where `seed_workspace_count` becomes settable. #4116 is the concrete cost of that dependency. **This rejection is what the ADR-033 addendum records** |
| **Cron now, alarm in a follow-up PR** | The explicit anti-goal. Ships a monitor whose failures land in a tab nobody opens, and is strictly worse than today because it makes people believe the surface is monitored |
| **Two alarm classes (`finding` / `cannot_measure`)** | Lets an open readiness issue swallow the *first* at-rest drift issue — the one alarm that fires counsel re-evaluation trigger (3). CLO ruling; see §Decision 2 |
| **Auto-close every class on green** | A green run after a data-loss finding does not prove the missing workspaces came back, and for `drift` it would close a legal re-evaluation no human discharged. Same "certified green" shape the downward-re-seed guard already refuses |
| **Alarm on `workflow_dispatch` too** | A human dispatched it and is watching. Would file issues on every operator experiment and on deliberately-rejected bad seed values. Also alters the dispatch path this PR must leave untouched |
| **Extract EXISTING logic to a sourced lib** | Breaks all four grep-shape gates (§Decision 6b) — AC7 breaks *silently*. Only the new pure classifier is extracted |
| **Put the classifier under `.github/workflows/lib/`** | That directory does not exist (`git ls-files` returns only `.github/scripts/validate-infra-templates.sh`), so creating it is a new repo-wide convention needing its own ADR. `apps/web-platform/infra/` is already in `infra-validation.yml`'s `paths:` and inherits the harness conventions |
| **Route every non-200 health result to the finding class** | Sends the operator to the runbook §5 data-recovery table for a Cloudflare-edge outage. CTO BLOCKER-2; the retryable/structural split is already enumerated in the file |
| **`!cancelled()` on the alarm and heartbeat** | Buys nothing (a superseded pending run executes no steps, so `always()` would not fire either) while being the construction most likely to suppress the alarm on the timeout/cancel path. Corrected to `always()` |
| **Expression-level ternary for the seed guard** (`github.event_name == 'workflow_dispatch' && inputs… \|\| ''`) | GHA's ternary has an empty-string-falsy footgun, is untestable from a shell fixture, and fails silently instead of loudly |
| **Event-scoped concurrency group** | Would let a scheduled run and an operator dispatch interleave SSH sessions to the same host — precisely what the group exists to prevent |
| **Edit the published legal documents to state the cadence** | Converts an internal rhythm into a published commitment whose breach becomes a *new* decay trigger, and re-opens a Tier-1 corrections-regime artifact across three mirrored documents for no user-relevant fact. CLO: do not touch the banners |
| **A separate legal incident register for drift events** | Manufactures an obligation nothing backs. The classed GitHub issue with `first_observed_at` **is** the durable record (CLO) |
| **No Sentry cron monitor** | Leaves absence undetected — a schedule that stops firing produces no run, no failure and no alarm, which is the decay trigger's exact defeat condition. CLO rates this blocking |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The Sentry monitor — the absence-detection layer — can itself be silently deactivated.** `expenses.md` records: at renewal, if PAYG cannot cover all active monitors, *"every monitor deactivates at once and check-ins are silently dropped"* (#3958). Next cliff 2026-08-16, ~9 monitors of headroom | Named, not papered over. This is why §L1 makes the **vendor-free** `gh run list --event=schedule --status=success` query the primary durable-evidence path, with the Sentry history as the second source. Link #3958 from the `cron-monitors.tf` comment. Do not present the monitor as a complete answer |
| **The guards this PR adds do not run on PRs that would break them** | CTO BLOCKER-1 — fixed by the `infra-validation.yml` `paths:` addition, and it is Phase 1 step 1.0 precisely because everything else depends on it |
| A daily prod SSH increases exposure to the pre-existing host-key TOFU gap; 8 lifetime operator-initiated root sessions become ~365/yr unattended | Named in §Encryption Posture with a tracking issue and an `expires_on`, and as one line in the PR body. Frequency-only increase; the credential and path are unchanged and shared with three other workflows |
| Alarm spam during a multi-day bridge outage, or a flapping tunnel producing an issue per flap | Dedupe by label + exact title; comment on the existing `unavailable` issue; ~~**reopen** a recently-closed one~~ (**SUPERSEDED by §Decision 2** — auto-close was cut, so nothing is ever closed to reopen); comment only when `reason` changes. No ops-email on `unavailable` |
| A readiness issue masks a later drift issue | Three independent dedupe keys; `drift` has its own label and title |
| GHA cron jitter, or a GitHub-dropped run, causes a false Sentry page (the #4189 regression) | `checkin_margin_minutes = 420` covers measured jitter (339 min) with headroom, and `failure_issue_threshold = 2` absorbs a lone dropped run — the pair is what makes a sub-1440 margin safe (§Decision 3) |
| The baseline is lost on a rebuilt host, making every run red | `workspace_count_baseline_missing` routes to `unavailable`, whose issue body must name the seed remedy (`workflow_dispatch` with `seed_workspace_count` from an independent proof). Loud and actionable, never a vacuous green |
| **The alarm ships permanently unreachable** because the one `if:` expression is wrong in a way a test of *our model* of GHA evaluation cannot see | The literal expression is written into §Sharp Edges 2; the test asserts an evaluated truth table, not a substring; a second mutation check targets the `if:` itself; and the `alarm_selftest` dispatch input exercises the real GHA expression once post-merge |
| **A dropped `notify-ops-email` page is silent** (non-2xx exits 0 with a `::warning::`) | The GitHub issue is the primary channel and is stated as such; the email step's outcome is recorded in the issue body; `RESEND_API_KEY` is added to the up-front secrets guard |
| The C4 counts drift again | The counts are **removed**, not incremented — `cron-monitors.tf` becomes the single source |

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Operations/Finance (vendor expense)

### Legal (CLO)

**Status:** reviewed
**Assessment:** Three blocking gaps and two high-priority items, all folded in — see §Legal (L1-L5)
and Files to Edit. Summary: the Article 30 register and the counsel audit's `claim_decay_trigger`
both become false on merge and must be corrected in this PR; absence detection (the Sentry cron
monitor) is required because the decay trigger's defeat condition is absence, not failure; the
alarm's class split must isolate at-rest drift, which alone fires re-evaluation trigger (3); the
drift issue body needs `first_observed_at` plus a trigger-(3) pointer; no new Article 30 processing
activity is created and the published `docs/legal/*` documents must **not** be edited. Disposition of
the counsel audit is unchanged (SIGNED-OFF WITH ACCEPTED RESIDUAL).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two blockers raised and both folded in as first-class scope.
**BLOCKER-1** — `infra-validation.yml`'s `paths:` omits this workflow, so every guard the PR adds
would be born unreachable on the PRs that break them (§Decision 6a, Phase 1.0, AC5b).
**BLOCKER-2** — routing every non-200 health result to a data-loss class contradicts the file's own
retryable/structural split and would send the operator into the runbook §5 data-recovery table for a
Cloudflare-edge outage (§Decision 2, AC7b).
Also adopted: `always()` over `!cancelled()` with the corrected rationale (§Decision 5); the classifier
extracted to `apps/web-platform/infra/` rather than a new `.github/workflows/lib/` convention
(§Decision 6b); the FM2 concurrency hole and why only an out-of-run monitor can see it; the Sentry
PAYG cliff and the `wg-record-recurring-vendor-expense-before-ready` trigger (§Decision 3); three
spam bounds; label colours mirroring the `ci/inngest-down` / `ci/inngest-probe-unavailable` pair; the
fourth grep anchor (`workspaces-luks-header.test.sh` H15b/H20); and the demotion of "runner minutes
are free" out of the PR prose. Cadence verdict: **keep daily**, but on justifications (a) and (d)
only. Complexity: medium, ~1 day. No capability gaps.

### Operations / Finance

**Status:** reviewed (via CTO's expense finding — corrected from an earlier "not relevant" sweep)
**Assessment:** `wg-record-recurring-vendor-expense-before-ready` **does** fire. The 52nd Sentry cron
monitor adds an uncapped `$0.78/mo` seat (`monitorSeats.reserved = 1`) to a PAYG line already at
`$42.22` against a `$50` cap, with `onDemandPeriodEnd` on **2026-08-16** — 13 days out and ~9
monitors of headroom. The `knowledge-base/operations/expenses.md` Sentry Team row must be updated
before PR-ready, with a re-measured live figure. No new vendor account, no new operator ritual, and
zero post-merge operator steps.

### Product/UX Gate — NONE

The mechanical UI-surface override does not fire: no path in `## Files to Create` or
`## Files to Edit` matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx` or any
UI-surface glob. This is CI/infra/docs only, with no user-facing surface. No wireframe is required
(`wg-ui-feature-requires-pen-wireframe` does not fire).

### Finance, Marketing, Sales, Support — not relevant

No pricing, revenue, positioning, content or customer-support surface is touched.

## GDPR / Compliance Gate

`/soleur:gdpr-gate` should run against this plan at `/work` Phase 0. The canonical regulated-surface
regex does **not** match (no schema, no migration, no auth flow, no API route, no `.sql`), but
expansion trigger (b) fires — the plan declares `brand_survival_threshold: single-user incident`.
The §Legal section above is the CLO domain leader's output and covers the Article 30, Article 32 and
Chapter V questions; the gate should confirm rather than re-derive, and its output is advisory-only.

## PR body

Use **`Ref #6808`**, never `Closes` / `Fixes`. This PR satisfies only the *"schedule exists"* half of
#6808's recorded closure condition. Per §A3.4 as corrected by L2, #6808 must not close until the
heartbeat is wired **and** the Phase-5 plaintext wipe completes (counsel re-evaluation trigger (1));
the heartbeat remains unwired and #6808 stays open. The schedule is a **compensating** control, not a
substitute.

## Research Insights — canonical in-repo forms to adopt verbatim

Collected by the deepen-plan precedent-diff sweep. **Adopt these; do not invent a variant.** Each is
quoted from a live file; the implementer should re-read the source rather than trust this excerpt if
anything looks off.

**Dedupe — by label + exact title** (`scheduled-supabase-advisor-scan.yml`), including the comment
that explains why `--search` was abandoned:

```bash
# Dedupe by LABEL, not `--search`: the search API can return empty
# under some token contexts, which would file a fresh duplicate every
# single night. Each title dedupes independently.
EXISTING=$(gh issue list --repo "$GH_REPO" --label "ci/supabase-advisor" --state open \
  --limit 100 --json number,title \
  --jq "map(select(.title == \"${TITLE}\")) | .[0].number // empty")
```

**Idempotent label creation** (same file) — note `2>/dev/null` *before* `|| true`:

```bash
gh label create "ci/supabase-advisor" --repo "$GH_REPO" \
  --description "Nightly Supabase advisor/catalog RLS gate" --color "B60205" 2>/dev/null || true
```

**Multi-class routing** — `scheduled-inngest-health.yml` is the reference implementation
(`case "$FAIL_MODE" in … esac` → `ISSUE_CLASS`), and its comment block records why each class needs a
**distinct title**: *"four distinct titles so auto-close never cross-matches"*, and why a mandatory
arm must precede the `*)` default (*"without it a functions_query_degraded verdict falls through to
`down` → a false [ci/inngest-down] P1"*). Our `*)` default must likewise not be `drift`-by-accident —
this is the same trap as the `mapper_path_override_refused` finding.

**`GH_TOKEN` wiring** — `env: { GH_TOKEN: ${{ github.token }}, GH_REPO: ${{ github.repository }} }`
on the filing step (`github.token`, not a PAT).

**Multi-line issue bodies** — `printf` into a `mktemp` file with a `trap`, then `--body-file`. The
comment states the reason: *"Build body via printf to avoid heredoc-leading-whitespace traps (4+
leading spaces would render the body as a code block)."*

**`strip_log_injection`** — copy verbatim from `scheduled-realtime-probe.yml`; needed for any *new*
host-derived field routed into an annotation or issue body (the `reason` is already `[a-z_]*`-safe by
construction — see §Sharp Edges 10):

```bash
strip_log_injection() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' \
    | sed -E 's/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g; s/\xe2\x80\x8b//g; s/\xef\xbb\xbf//g; s/\xc2\x85//g'
}
```

**Test harness** — `workspaces-luks-cutover-workflow.test.sh` is the template. Its header states the
rule this plan's suite inherits: *"EVERY structural assertion parses the file as YAML. A grep would
pass VACUOUSLY… `bash -n` is likewise run only on EXTRACTED `run:` bodies — `bash -n` on the .yml
itself parses YAML as bash and proves nothing."* Mechanism: `python3 -c 'import yaml' || pip3 install
--quiet pyyaml` → a Python leg emitting tab-separated verdicts → a bash `while IFS=$'\t' read` loop
converting them to `ok`/`no` → an assertion floor. Note the Python `check()` helper strips tabs and
newlines from detail strings *because the bash reader splits on tabs* — an embedded tab would
manufacture a phantom verdict.

**PATH-stub technique** — `git-data-rung2-rehearsal.test.sh` arm 13 writes stub binaries into a
per-case `mktemp -d` under one reaped root (an un-reaped `mktemp -d` per call leaked ~6 dirs per run),
exports `GITHUB_OUTPUT`/`GITHUB_STEP_SUMMARY` to scratch files, and runs `bash -e "$body"` in a
subshell. Its header states why it **executes** rather than sources: *"`deadline=$(( SECONDS + 16*60 ))`
reads the shell's own SECONDS, and sourcing would leak this suite's elapsed time and could fire the
deadline immediately."* Our extracted body has no such deadline, but the execute-don't-source
discipline still holds — sourcing would pollute the suite's own shell with the workflow's `set +e`.

**Registration line format** (`infra-validation.yml`) — a `- name:` + `run: bash <path>` pair, with a
comment. The existing sibling's comment states the invariant: *"an unregistered suite is zero
coverage, silently green."*

```yaml
      - name: Run /workspaces LUKS cutover WORKFLOW gate (#6588 mode gating + CLEAN_STRAY reachability)
        run: bash apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh
```

## Test Scenarios

| Scenario | Expected |
|---|---|
| Scheduled run, everything healthy | `outcome_class=pass`, no issue filed, nothing closed, Sentry check-in `ok` |
| GitHub drops ONE scheduled run | Silent — one missed check-in is below `failure_issue_threshold = 2` (#4189) |
| Schedule genuinely dark (disabled/orphaned) | Two consecutive misses → Sentry issue at ~31 h |
| Scheduled run, mount reverted (rc 1) | `drift` issue with `type/security` + `priority/p0-critical` + `action-required`, body carries `first_observed_at` + the trigger-(3) pointer, Sentry check-in `error` |
| Scheduled run, inventory shortfall (rc 3) | `readiness` issue, `priority/p1-high`, Sentry `error`, **no** `drift` issue |
| Scheduled run, bridge down (rc 255) | `unavailable` issue, Sentry `error`, no `drift` or `readiness` issue |
| Scheduled run, app health 521 after the full budget | `unavailable` issue (CF-edge outage), **no** ops-email, **no** `drift` or `readiness` issue |
| Scheduled run, app health 307 | `readiness` issue (routing regression) + ops-email |
| Second consecutive failure, same class, **same reason** | No new comment — the running-count line is updated |
| Second consecutive failure, same class, **different reason** | Comment on the existing issue; no duplicate filed |
| Drift issue open, then a green run | Comment only — the issue stays OPEN |
| Unavailable issue open, then a green run | Nothing happens — the issue stays open until a human closes it. No churn, and dedupe-by-title always finds it |
| Tunnel flaps over 6 days | ONE issue, commented only when the `reason` changes. No second issue is possible, because none is ever closed |
| Re-assert step never runs (bridge action failed) | `steps.reassert.outcome != 'success'`, empty class → `unavailable` issue, Sentry `error` |
| Run cancelled by concurrency supersession (FM2) | No steps execute, so no issue and no check-in from the run itself. Detection is the missed Sentry check-in — silent on a single occurrence (threshold 2), paging at ~31 h if it repeats |
| Operator cancels a hung scheduled run | `always()` fires → `unavailable` issue ("nothing was proven"), Sentry `error` |
| Job exceeds `timeout-minutes: 15` | Runner torn down; detection is the missed Sentry check-in — silent once, paging at ~31 h if it repeats |
| Operator dispatch fails | Red run, **no** issue filed (alarm is `schedule`-gated), dispatch path otherwise identical to today |
| Scheduled run with a non-empty seed somehow present | Refused with a non-zero exit before any host write; `unavailable` issue |
| The schedule stops firing entirely | Sentry Crons missed check-in past 1440 min → Sentry issue. The only layer that sees this |
