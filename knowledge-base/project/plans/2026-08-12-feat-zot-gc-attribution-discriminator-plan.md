---
title: "Growth-attribution discriminator + delivery-probe first-tick grace"
date: 2026-08-12
slug: feat-zot-gc-attribution-discriminator
branch: feat-zot-gc-discriminator-probe-grace
issue: 7456
closes: 7456
lane: cross-domain
type: feat
domain: engineering
priority: p3
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Growth-attribution discriminator + delivery-probe first-tick grace

## Overview

Two deliverables against #7456, both unblocked by a delivery event that landed during the scoping
session:

1. **`scripts/zot-gc-attribution.sh`** — a read-only discriminator that answers *why* the registry
   store is growing, by pairing zot gc starts to completions **per repository** and counting
   `PatchBlobUpload` orphan evidence.
2. **A first-tick grace verdict on `scripts/followthroughs/zot-log-channel-7440.sh`** — the delivery
   probe currently emits its escalate-immediately verdict against a host too young to have run a
   shipper tick. Plus the test harness that probe ships without today.

Items (a) root-fs LUKS and (c) rate-cap retune remain deferred on #7456 and are Non-Goals here.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited | Claim in the tracker | Verified state |
|---|---|---|
| #7456 | work target | **OPEN** |
| #7455 | sibling delivery tracker | **OPEN** — owned by a parallel session; untouched here |
| #7341 | "wire to whichever criterion #7341 carries" | **OPEN**, and its criterion is now concrete — see below |
| #7287 | "delivery rides step-6 `registry-host-replace` on the **open** ordered path" | **CLOSED** 2026-08-12T20:39Z, COMPLETED, no closing PR. Its closing comment records that the atomic 3-way recut replaced the host on 08-10, so *"ordered-path step 6 did not need a separate `registry-host-replace`"* |
| #7440 / PR #7444 | shipper | **CLOSED / MERGED** 2026-08-12T19:38Z — two days *after* that host was born, so the shipper was committed and inert |
| ADR-179 (cited by #7456) | "the shipper ADR" | **WRONG.** ADR-179 is `bare-plugin-root-anchor-for-customer-facing-executables`. The shipper ADR is **ADR-184**, cited correctly by #7455 |
| `scripts/followthroughs/zot-log-channel-7440.sh` | exists | exists; **has no `.test.sh`** |
| `apps/web-platform/infra/zot-log-shipper.test.sh` | test precedent | exists, 961 lines, wired into `.github/workflows/infra-validation.yml` |

**Delivery is verified, not assumed.** A parallel session dispatched `registry_host_replace`
(run 31639782781, success 20:54:12Z). The probe was then run directly:

- 20:56:32Z → `TRANSIENT: reason=delivered_but_silent` (the ACT-NOT-WAIT arm)
- 20:58:45Z → `PASS: envelope=20 control=7 gc_start=1 gc_done=1 gc_blobs=1 patch_upload=0 dropped_rows=1`

No intervention occurred between those two readings. ADR-184's flip condition is "the **first PASS**"
of that probe, so `adopting → accepted` is now earned — landed via **#7455**, not here.

### Measured evidence-class shapes (this is what decides FR1)

Queried live against the warehouse rather than derived from the shipper's config:

| Class | Carries repository? | Rows / 3h |
|---|---|---|
| `executing gc of orphaned blobs for /var/lib/zot/<owner>/<repo>` | **yes** | 1 |
| `gc successfully completed for /var/lib/zot/<owner>/<repo>` | **yes** | 1 |
| `garbage collected blobs` | **no** — bare | 1 |
| `PatchBlobUpload` | — | **0** |

Two consequences:

- **Per-repository pairing is possible**, and it is exactly the zot#4235 signature #7341 names:
  *"gc completes repeatedly for `soleur-inngest-bootstrap` and never for `soleur-web-platform`"*.
  A **global** ratio would read ~50% on that failure and look partially healthy.
- **`garbage collected blobs` cannot be a per-repo numerator** — it is bare. The spec listed it as
  completion evidence; it is demoted to *reclaim* evidence. `PatchBlobUpload` at zero must read as
  healthy, not as missing data.

**The shipped payload is quote-stripped and colon-joined, not JSON.** Measured:

```
SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry {time:2026-08-12T20:54:20.797245158Z,
level:info,message:executing gc of orphaned blobs for /var/lib/zot/jikig-ai/soleur-web-platform,
module:gc,caller:zotregistry.dev/zot/v2/pkg/storage/gc/gc.go:109,...}
```

`cloud-init-registry.yml`'s `JQ_TICK` ships `$m` — the whole journald `MESSAGE` — and `sanitize`
strips `"` and `\`. So the parser must treat the inner payload as **text**; `fromjson` on it fails.
(The outer Better Stack `raw` is separately double-encoded and still needs two decodes.)

Also observed, recorded but **not** concluded: gc *did* complete for `soleur-web-platform` on the
fresh host. One cycle against a near-empty store is consistent with the upstream panic being
content-dependent; it is not evidence the bug is gone.

### Prior art that this plan builds on rather than re-derives

- **`scripts/followthroughs/zot-fill-rate-7341.sh` already exists** and is #7341's enrolled close
  criterion: it fits a slope over current-boot `pcent` samples, closes only when `pcent < 85` and
  the trajectory does not reach 85 within 14 days, scopes to `boot_id`, requires a ≥24h span.
  It is the **detector**. This plan's discriminator is the **attributor**. They are complementary.
- **#7435 is a 14-defect taxonomy for this exact probe class**, same host, same channel, days old.
  Every item below is imported as a design constraint, not rediscovered:
  - **C2 (critical): an unanchored grep over a multiplexed stream is poisonable.** `--grep X`
    compiles to `raw LIKE '%X%'` over a source every host multiplexes into; one GitHub comment
    quoting a marker line flipped a measured `FAIL pcent=78` into `PASS pcent=6`. **Anchor on the
    emission envelope.**
  - Defect 3: a count floor with no **span** floor extrapolates jitter.
  - Defect 5 + verification note: *"the fixture mirrored a bug, so it could not see it"* — the zot
    fixture now emits **production-shaped double-encoded `raw`**; against the old bare-string form a
    correctly hardened parser scored 3/11, so the bad fixture **blocked the fix**.
  - Defect 9: the sweeper posts probe stdout back as a comment, which the next run can read as
    input — self-poisoning.
  - Plumbing: `2>/dev/null` destroyed `betterstack-query.sh`'s rc=3 credential message.
    **The existing delivery probe does exactly this** on its query calls.
  - **`scripts/test-all.sh` registration is by hand** — an unregistered suite never runs in CI,
    *"making the anti-vacuity floors decoration."*
- **`scripts/lib/zot-telemetry-parse.sh`** exists (`zot_trusted_region`, `zot_newest_boot`,
  `zot_scope_to_boot`, `zot_nonsentinel_values`) precisely so consumers cannot drift on these
  invariants; its header calls duplication *"a maintenance hazard."* #7435 records that
  `zot_trusted_region` is a line-oriented `sed` that breaks on JSONEachRow (it removes the closing
  brace; measured n=0 from 144 rows) and that **"a JSON-aware variant belongs in the library."**
  This plan is the third consumer and ships that variant.

### Property List (Phase 0.6b)

- **P1** — When the registry store grows, the cause is attributable to *stalled per-repo gc* vs
  *orphaned upload staging* vs *neither*, from telemetry alone.
- **P2** — The delivery probe does not emit its escalate-immediately verdict during the
  structurally expected pre-first-tick window.
- **P3** — #7456 cites the correct ADR.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| A standing **follow-through tracker** for the discriminator | P1 | Follow-throughs are "wait for X, then close". gc health is a *standing* property with no close event, so the tracker would never close and would post a comment **per sweep forever**. Standing detection is already bought by `zot-fill-rate-7341.sh`. |
| A **Better Stack standing alarm** on the ratio | P1 | The signal is *absence of a completion within a window* — an alert rule expresses that poorly, it cannot be exercised in CI, and it adds vendor config drift. |
| **Extending the delivery probe** instead of a new script | P1 | Window classes are incompatible and the probe's own header forbids it: it is deliberately `--no-archive` on a 30m keyhole, and *"do not copy flags between the days-old and minutes-old cases."* |
| `garbage collected blobs` as a **per-repo completion numerator** | P1 | **Measured bare** — carries no repository. Retained as reclaim evidence only. |
| A new `workflow_dispatch` lever | P1 | The script reads the warehouse, not the host; it needs no host access and no gated vehicle. Add one only if a cadence proves necessary. |

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR1: `gc successfully completed` **and** `garbage collected blobs` are completion evidence | `garbage collected blobs` is bare — no repo | FR1 revised: per-repo pairing uses `gc successfully completed for <path>` only; `garbage collected blobs` becomes reclaim evidence |
| FR1 implies a single global ratio | The zot#4235 signature is **per-repository** | FR1 revised to per-repo pairing; a global ratio is explicitly insufficient |
| FR5: judgements made "on the decoded object" | The inner payload is quote-stripped text, not JSON | FR5 revised: decode the outer `raw` twice, then parse the inner payload as **text** |
| Spec is silent on where the discriminator lives | Follow-through shape does not fit (no close event) | New: `scripts/zot-gc-attribution.sh`, not under `followthroughs/` |
| Spec is silent on a test harness for the delivery probe | **It has none** | New: `scripts/followthroughs/zot-log-channel-7440.test.sh` |
| Spec is silent on the shared parse library | Exists, with a recorded JSON-aware gap | New: ship the envelope-anchored helper into `scripts/lib/zot-telemetry-parse.sh` |

## Implementation Phases

### Phase 1 — Shared envelope-anchored parse helper (contract first)

Add to `scripts/lib/zot-telemetry-parse.sh` a helper that takes raw JSONEachRow on stdin and emits
only the **inner payloads of envelope-anchored rows**: double-decode `raw` → `.message`, then admit
only lines whose decoded message starts with
`SOLEUR_ZOT_LOG shipper=zot-log-shipper host=<host>`. Anchored at offset 0, positively.

This is the C2 fix as a reusable primitive, and it is the JSON-aware variant #7435 says belongs
here. It lands **before** its consumers so neither consumer duplicates the invariant.

Regex anchors must cover the **whole** token (defect 2: a character class not covering the whole
token still matches the longest prefix).

### Phase 2 — `scripts/zot-gc-attribution.sh`

Consumes the Phase 1 helper. Window ≥ 6h (default 24h), **archive arm ON** (no `--no-archive`).

- Discover repositories from the rows; never from a hardcoded list.
- Pair `executing gc of orphaned blobs for <path>` → `gc successfully completed for <path>` per
  repository, within the window.
- **Boundary handling:** a start whose completion would fall outside the window is `indeterminate`,
  never `stalled`.
- **Span floor:** refuse a verdict unless the window holds ≥ N gc periods of history (gc is
  hourly). Zero rows and too-few-rows are distinct reasons.
- Report `PatchBlobUpload` counts as independent orphan evidence; **zero is healthy**.
- Do not swallow stderr on query calls — preserve `betterstack-query.sh` rc=3.
- Exit contract: `0` PASS, `2` TRANSIENT with a distinct `reason=` per arm, `1` genuine regression
  (a confirmed per-repo stall). `${VAR:?msg}` is banned (lint-enforced).
- Redact the anchor in echoed content (defect 9) so stdout can never be re-read as input.

### Phase 3 — First-tick grace on the delivery probe

In `scripts/followthroughs/zot-log-channel-7440.sh`, between "delivery evidence present" and the
`delivered_but_silent` emit, insert an `awaiting_first_tick` arm (still exit 2) when the shipper has
provably never completed a tick **and** the host is inside the grace window.

Discriminators are already read by the probe: `log_shipper_last_ok_age_s == -1` (no row has ever
shipped) and `log_shipper_post_fail == unknown` (state file unreadable). Boot recency comes from the
boot-marker row's own timestamp.

**Grace derived, not magic:** the shipper cron is `4-59/5` (5-minute one-shot), so grace = 2 tick
intervals = 10 minutes. State the derivation in the source.

`delivered_but_silent` must still fire for a host past the grace window (TR3).

### Phase 4 — Test harnesses

- `scripts/zot-gc-attribution.test.sh` — new.
- `scripts/followthroughs/zot-log-channel-7440.test.sh` — new; the probe has none today.

Both follow `cpx22-invoice-reconcile-7431.test.sh`: stubs run **real `jq`**, and stubs **assert
their argv** (without which dropping `--grep`, adding `--no-archive` or shrinking `--limit` all stay
green while wedging the probe at TRANSIENT forever). Fixtures emit **production-shaped
double-encoded `raw`** with the quote-stripped inner payload measured above
(`cq-test-fixtures-synthesized-only`: values synthesized, shape measured).

### Phase 5 — Registration, ADR, citation

- Register both suites in `scripts/test-all.sh` via `run_suite` (by hand — an unregistered suite
  never runs).
- Amend **ADR-184**: its Consequences claims *"the gc start/complete ratio and `PatchBlobUpload`
  counts are readable rather than sampled."* Refine with the measured shapes — per-repo pairing is
  available on the start/complete pair; `garbage collected blobs` is bare; the shipped payload is
  quote-stripped text. Record the `awaiting_first_tick` verdict.
- Correct #7456's ADR-179 → ADR-184 citation.

## Files to Create

- `scripts/zot-gc-attribution.sh`
- `scripts/zot-gc-attribution.test.sh`
- `scripts/followthroughs/zot-log-channel-7440.test.sh`

## Files to Edit

- `scripts/lib/zot-telemetry-parse.sh` — envelope-anchored, JSON-aware helper
- `scripts/followthroughs/zot-log-channel-7440.sh` — `awaiting_first_tick` arm; stop swallowing rc=3
- `scripts/test-all.sh` — register two suites
- `knowledge-base/engineering/architecture/decisions/ADR-184-registry-host-container-log-shipper.md`

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --limit 200` against each target
path (`scripts/followthroughs/zot-log-channel-7440.sh`, `scripts/test-all.sh`,
`scripts/lib/zot-telemetry-parse.sh`, `ADR-184`) — zero matches.

## User-Brand Impact

**If this lands broken, the user experiences:** a registry-host probe that cries wolf — either a
false *"ACT, NOT WAIT"* on a healthy host, or a stall verdict that is a windowing artifact. Both
train the operator to discount the only channel reporting on the fleet's sole container-image pull
path.

**If this leaks, the user's data is exposed via:** shipped rows echoed into a **public** GitHub
comment by the sweeper. Mitigated by the shipper's own `redact()` and by counting-not-quoting; the
discriminator reports counts and repository names, never raw log content.

**Brand-survival threshold:** `single-user incident`. A discounted alarm on the sole pull path is a
silent outage of every deploy.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-184** (no new ADR). Its Consequences section asserts the gc ratio and `PatchBlobUpload`
counts are "readable"; the measurements refine that materially (per-repo pairing available; one
class bare; payload is quote-stripped text). Also record the `awaiting_first_tick` verdict, since
ADR-184 documents the probe's exit contract.

### C4 views

**No C4 impact**, on this enumeration — read against all three of `model.c4` (688 lines),
`views.c4`, `spec.c4`:

- **External human actors:** none added.
- **External systems:** `betterstack` is already modeled, explicitly as a Logs warehouse that is
  "ClickHouse-SQL-queryable" and "polled from GitHub Actions via `betterstack-query.sh` for … the
  zot restart-loop recurrence alarm + follow-through soak probes". `zotRegistry`, `projectZot` and
  `ghcr` are modeled; `betterstack`'s description already names the #7440/ADR-184 shipper edge.
- **Containers / data stores:** none added.
- **Access relationships:** none changed. The discriminator is a **new reader of an
  already-modeled edge**.

**Filed, not folded — two now-false claims in `zotRegistry`'s description**, both falsified by the
2026-08-10 recut rather than by this change: (i) *"the LIVE host still runs v2.1.2 and will until
the registry-host-replace apply fires"* — the observed digest is `95a837a0afac` (v2.1.20); (ii)
*"The LIVE device is still plaintext ext4 … that vehicle shipped UNFIRED (#6929)"* — the recut fired
and the volume is LUKS-encrypted. Kept out of scope because `model.c4` carries whole-file-count ACs
that make unrelated edits regression-prone, and model accuracy is a different concern from probe
logic (the #7435 precedent for exactly this split: *"scope discipline requires its own PR"*).

## Encryption Posture

**Skipped** — introduces no persistent store and no new cross-component connection. The
discriminator reads an existing channel through the existing `betterstack-query.sh` credential path.

## Guard Contract

### Guard 1 — gc attribution discriminator

**Property.** For every repository that started a gc cycle inside the window, either a completion
for **that same repository** is observed within the window, or that repository is reported stalled —
except where the completion would fall outside the window, which is `indeterminate`.

**Assembly.** Every envelope-anchored row in the window whose decoded inner payload matches a gc
evidence class. The chokepoint is the single Phase 1 decode-and-anchor helper; repositories are
**discovered from the rows**, never enumerated in code, so the assembly is structural rather than a
snapshot.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a start row for a **second, new** repository with no completion, after a compliant first repo | **RED** — stalled (catches a check that stops at the first member) |
| 2 | Remove the envelope anchor so an unanchored/pasted row is admitted | **RED** — the C2 poisoning case |
| 3 | Feed a window containing **zero** gc rows and let the probe exit 0 | **RED** — anti-vacuity: "0 repos checked" must never PASS |
| 4 | Drop the span floor and feed one hour of history | **RED** — defect 3 |
| 5 | Move a completion just outside the window boundary | **NOT red** — `indeterminate`, not stalled |

### Guard 2 — delivery-probe first-tick grace

**Property.** A host that has provably never completed a shipper tick and is inside the grace window
reports `awaiting_first_tick`; a host past the grace window with zero envelope rows still reports
`delivered_but_silent`.

**Assembly.** The probe's delivery-discrimination branch — **both** paths that can set
`delivered=1` (`boot_marker`, and `reporter_carries_shipper_fields`) — plus the single verdict emit
site.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Boot inside grace, `last_ok_age_s=-1` | `awaiting_first_tick`, **not** `delivered_but_silent` |
| 2 | Boot **past** grace, zero envelope rows | **still** `delivered_but_silent` (grace must not weaken escalation) |
| 3 | Delivery evidence via the **second** arm (`reporter_carries_shipper_fields`) with no grace handling | **RED** — covers both members, not just `boot_marker` |
| 4 | Remove the grace check entirely | **RED** |

## Observability

```yaml
liveness_signal:
  what: envelope-anchored SOLEUR_ZOT_LOG rows in the Better Stack Logs warehouse
  cadence: 5-minute shipper one-shot (cron 4-59/5); gc hourly
  alert_target: none new — zot-fill-rate-7341.sh remains the standing detector on #7341
  configured_in: apps/web-platform/infra/cloud-init-registry.yml (unchanged by this plan)
error_reporting:
  destination: stdout/stderr with a distinct reason= per arm; sweeper mirrors probe stdout
  fail_loud: true — betterstack-query.sh rc=3 (credential fault) is preserved, not swallowed
failure_modes:
  - mode: per-repo gc stall (upstream zot#4235 signature)
    detection: start without a same-repo completion inside a >=6h window
    alert_route: exit 1 from zot-gc-attribution.sh
  - mode: orphaned .uploads/ staging
    detection: non-zero PatchBlobUpload counts
    alert_route: reason=orphaned_upload_staging (exit 2), escalating on sustained counts
  - mode: read path unavailable / credentials unset
    detection: betterstack-query.sh non-zero rc surfaced verbatim
    alert_route: reason=channel_dark or reason=query_failed (exit 2)
  - mode: too little history to judge
    detection: span floor unmet
    alert_route: reason=below_span_floor (exit 2), never PASS
logs:
  where: Better Stack Logs source 2457081 (ClickHouse-queryable)
  retention: hot window ~40m; archive arm required for the >=6h window
discoverability_test:
  command: bash scripts/zot-gc-attribution.sh
  expected_output: "PASS: <n> repo(s) paired, 0 stalled, patch_upload=0"
  credentials_required: "BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} — the property is a readback
    through the warehouse, which by construction has no unauthenticated substitute"
```

### Soak follow-through enrollment

**Not required.** No acceptance criterion here is time-gated: every AC is decidable at merge against
fixtures plus one live run. The standing post-deploy question ("does the store refill?") is already
enrolled — `zot-fill-rate-7341.sh` on #7341, `earliest=2026-08-14`.

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed (inline — this session's operating instructions forbid Agent-tool invocation
unless the operator requests it; assessment performed against live telemetry and the ADR/producer
sources cited throughout).

**Assessment:** Internal observability tooling on an infra host. No user-facing or regulated
surface, no new vendor, no new persistent store. The material risks are probe-correctness risks,
which the Guard Contract and the #7435 defect taxonomy address directly.

## Acceptance Criteria

### Pre-merge

- **AC1** — Against fixtures, a repo with a start and no same-repo completion reports **stalled**;
  a repo with a paired start/completion reports **healthy**. Distinct verdicts.
- **AC2** — A start within one gc period of the window edge reports `indeterminate`, not stalled.
- **AC3** — A window with zero gc rows exits 2 with a distinct reason; it never exits 0.
- **AC4** — An unanchored row (a pasted marker line, C2 shape) is **not** admitted; fixtures include
  a contaminating row and the verdict is unchanged by it.
- **AC5** — Fixtures emit production-shaped **double-encoded `raw`** with a quote-stripped inner
  payload; a bare-string fixture form is not used anywhere.
- **AC6** — Replaying the observed 20:56Z state (boot marker present, `last_ok_age_s=-1`,
  `post_fail=unknown`, boot < 10 min old) through the patched delivery probe yields
  `awaiting_first_tick`.
- **AC7** — Replaying a post-grace silent host still yields `delivered_but_silent`.
- **AC8** — Both new suites are registered in `scripts/test-all.sh` via `run_suite`, and
  `grep -c 'run_suite "scripts/zot-gc-attribution"' scripts/test-all.sh` returns 1.
- **AC9** — Each test stub asserts its argv (flags `--since`, `--limit`, `--grep`, and the
  presence/absence of `--no-archive`).
- **AC10** — `shellcheck` clean on all four scripts (bash-only diff).
- **AC11** — `bash scripts/lint-followthrough-varq-ban.sh` passes; no `${VAR:?}` in either probe.
- **AC12** — The gc discriminator does **not** pass `--no-archive` (opposite window class from the
  delivery probe); asserted by the argv stub.
- **AC13** — ADR-184 amended: Consequences reflect the measured class shapes, and
  `awaiting_first_tick` is recorded.
- **AC14** — Full suite green via `bash scripts/test-all.sh`.

### Post-merge

- **AC15** — `bash scripts/followthroughs/zot-log-channel-7440.sh` against live production still
  returns PASS (the channel is live as of 20:58Z 2026-08-12).
- **AC16** — `bash scripts/zot-gc-attribution.sh` returns a real verdict against live production
  with credentials from Doppler `prd_terraform`.
- **AC17** — #7456's ADR-179 citation corrected to ADR-184.

## Test Scenarios

Framework: `bash` `.test.sh` harnesses (the convention for `scripts/followthroughs/**`, registered
by hand in `scripts/test-all.sh`). Not bats — not installed.

1. Paired start/completion, single repo → PASS.
2. Start with no same-repo completion → exit 1, names the repo.
3. Two repos, one paired and one not → exit 1 (the second-member case).
4. Completion outside the window → `indeterminate`.
5. Zero gc rows → exit 2, `reason` distinct from too-few-rows.
6. Span floor unmet → exit 2, `reason=below_span_floor`.
7. Contaminating unanchored row present → verdict unchanged.
8. `PatchBlobUpload` non-zero → orphan evidence reported.
9. `betterstack-query.sh` rc=3 → surfaced verbatim, exit 2, not conflated with "no rows".
10. Delivery probe: boot inside grace + `last_ok_age_s=-1` → `awaiting_first_tick`.
11. Delivery probe: boot past grace, zero envelope rows → `delivered_but_silent`.
12. Delivery probe: delivery evidence via `reporter_carries_shipper_fields` → grace still applies.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Editing the delivery probe destabilises #7455, which a parallel session is closing | No open PR touches the file (verified). Scope limited to inserting one arm ahead of an existing emit; TR3 requires the genuine escalation still fire. Coordinate before merge. |
| The 6h/24h window plus archive arm adds an S3 failure mode | Distinct `reason=` for query failure; the probe never PASSes on a failed read. Sibling `zot-inventory-marker-7278.sh` already runs 7d with the archive arm. |
| gc log wording changes on a future zot pin | Anchored on `message:` prefixes that are also the shipper's own cap-exempt keys, so drift breaks both together and is caught by the shipper's suite. |
| One gc cycle on a near-empty store is not evidence the upstream bug is gone | Explicitly recorded as an observation, not a conclusion. The discriminator is forward-looking. |

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Extend `zot-log-channel-7440.sh` to compute the ratio | **Rejected** — incompatible window class; the probe's own header forbids copying flags between them. |
| Enroll the discriminator as a follow-through on its own tracker | **Rejected** — no close event; would post a comment per sweep forever. |
| Better Stack native alert on the ratio | **Rejected** — absence-within-window is poorly expressible, untestable in CI, adds vendor drift. |
| Global (not per-repo) gc ratio | **Rejected** — reads ~50% on the exact zot#4235 signature and looks partially healthy. |
| Couple the discriminator into `zot-fill-rate-7341.sh` | **Rejected** — that probe is #7341's live close criterion; destabilising it to add attribution trades a working detector for a nicety. Wire by reference instead. |
