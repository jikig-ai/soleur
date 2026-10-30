---
title: "chore: inngest vector delivery — measured-close probes + pin-time trim guard for #11602 and #7596"
date: 2026-10-30
slug: chore-inngest-vector-delivery
branch: feat-one-shot-11602-7596-inngest-vector-delivery
issue: 11602
lane: cross-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# chore: inngest vector delivery — measured-close probes + pin-time trim guard for #11602 and #7596

## Enhancement Summary

**Deepened on:** 2026-10-30
**Sections enhanced:** Proposed Solution (probe floor semantics, leg attribution, PASS-arm naming), Files to Edit (test-all.sh registration, in-place runbook amendment), Acceptance Criteria (AC10-AC12), Observability (comment-noise cost), mutation matrix (row 7).
**Agents used:** `devin -p` headless seats (sequential-fallback — no native Task tool): dhh / kieran / code-simplicity / cto-devex review seats + a soleur:engineering:cto Rule-interface ruling spawn.

### Key Improvements

1. Metric rows carry ONLY `tags.host`/`tags.collector` (native Vector shape, `tag_metrics` remap a measured no-op) — the #11602 probe isolates on `tags.host`, the issue's own grouping field.
2. `leg_journald` is NOT a TRANSIENT reason: arm-2 PASS preempts it; the journald-leg verdict travels inside the PASS output (`pass_arm=boot_stage journald_rows=absent`) — removes a dead code path and a vacuous either/or fixture.
3. `_BOOT_ID` PASS qualification requires positive resolution — unresolvable → TRANSIENT `boot_id_unresolvable` (stale-generation close defense, 10-28 learning).
4. CI reality: `scripts/followthroughs/*.test.sh` needs explicit `run_suite` lines in `scripts/test-all.sh` (orphan-linter-blocking); enrollment is post-merge-ordered (missing `script=` reds the sweep); convention-mandated branch dry-run added as AC11.

### New Considerations Discovered

- Live-state anomaly: the running host (v1.1.61, allowlist-baked) shows ZERO restage/phone-home rows in 14d across two boots — the replace is a diagnostic instrument, not a guaranteed close (CTO ruling recorded).
- The existing `inngest-server.md` `### Post-replace: the boot-trace allowlist (#7596)` section goes stale on landing — amended in place, not appended.

## Overview

The inngest host's vector.toml is birth-frozen: the shared `apps/web-platform/infra/vector.toml` on main already carries the `[memory, filesystem]` + 900s host_metrics trim (#11602) and the #7457 Source-4 allowlist (#7596), and the auto-mint pipeline already baked `vinngest-v1.1.67` with both — but the live host runs `v1.1.61` and only re-reads the file at birth via the bootstrap image. What remains undelivered is (a) proof the next replace carries the trim (a pin-time guard assertion, mirroring #7596's Guard A3), and (b) the measured close conditions for both issues, automated via the follow-through sweeper so the sanctioned operator replace — a prod-mutating dispatch outside this PR's authority — closes the issues on evidence rather than human memory.

## Problem Statement / Motivation

- **#11602** (OPEN): the live soleur-inngest host ships untrimmed `host_metrics` collectors (~17.8k rows/day measured 2026-10-29→30). The trim (`collectors = ["memory","filesystem"]`, `scrape_interval_secs = 900`) already lives in `apps/web-platform/infra/vector.toml:623-626` but reaches the host only via the baked bootstrap image consumed at birth. The issue asks to ride the next `apply_target=inngest-host-replace` window; its acceptance is a measured read (GROUP BY collector post-replace).
- **#7596** (OPEN): #7457's `inngest-boot-phone-home` / `inngest-bs-token-restage` Source-4 allowlist entries reached web-1 (inert there — Source 4 is a local journald source) but their close evidence on the inngest host has never shipped. The issue's close condition is a measured read: `inngest-bs-token-restage` rows (or the host's own boot-stage markers) observed off-box post-replace.
- **Delivery machinery already exists**: `mint-inngest-bootstrap-tag.yml` auto-mints a `vinngest-*` tag on any `apps/web-platform/infra/vector.*` push; the pin is now `v1.1.67` (carries both payloads — verified against the tag's tree). A probe for #7596 exists (`scripts/followthroughs/inngest-bs-token-restage-7596.sh`) but is **unenrolled** (no `follow-through` label, no directive in the issue body) and unguarded against stale-generation evidence.
- **The only delivery path to the live host remains a host replace**: the ADR-135 config-refresh channel (`inngest-config-refresh-set.txt`) carries only four host-executed `.sh` scripts — vector.toml is not a member and cannot become one (the install engine `infra-config-install.sh` DEST_SPEC is itself a HARD-1 non-member; widening it requires an image bake → a replace anyway). No remote-exec/SSH path exists by design.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view` verified both #11602 and #7596 OPEN, no closing PRs. `collision-precheck.sh` on both: only hit is this pipeline's own draft PR #11604; foreign `proc.sh` hits are unrelated test-all.sh runs in sibling worktrees.
- #7462 (the replace/rebuild epic #7596 cites) is CLOSED; its machinery survives as `apply_target=inngest-host-replace` in `apply-web-platform-infra.yml:1899-2203` (sourced `inngest_host_replace_gate` from `tests/scripts/lib/inngest-host-replace-gate.sh`).
- Live-state read (Better Stack, `scripts/betterstack-query.sh` against `t520508_soleur_inngest_vector_prd_3_logs` UNION s3 archive):
  - Host `hetzner-172544086` reports `image_ref=…/soleur-inngest-bootstrap:v1.1.61@sha256:e3630bca…` (`inngest-server-probe`, 2026-10-28). Born ~2026-10-26; rebooted 2026-10-29 ~08:42Z (kernel + `inngest-luks-stage` rows at 08:44).
  - `vinngest-v1.1.61`'s baked vector.toml **contains the allowlist** (lines 139-140, 207-208, 428-436) and the **untrimmed** collector set (line 570) — consistent with #11602's measured 17.8k rows/day.
  - **Anomaly**: ZERO `inngest-bs-token-restage` / `inngest-boot-phone-home` journald rows in 14d across two boots, while sibling allowlisted identifiers (`inngest-luks-stage`, `inngest-config-refresh`, `inngest-heartbeat`, `inngest-server-probe`) shipped at the same boots. A `bs-token-restage-enabled` BOOT_STAGE phone-home marker exists for the *previous* generation (2026-10-18) but not this one. → The allowlist leg is already live on this host; the dark identifiers localize to the **emit leg** (unit enable / logger→journald), which a replace tests but does not provably fix. The next replace is therefore a *diagnostic instrument* for #7596, not a guaranteed close — CTO ruling below.
  - Probe spot-run (`RESTAGE_WINDOW=30d`): `TRANSIENT: reason=channel_dark` — consistent.
- Sibling queue checked (no silent absorption): #10539 (bind :8288 loopback at next replace), #10544 (replace dispatch confirm/id-pin input), #11011 (replace-preflight meta), #11265/#11336/#11266 (LUKS/prune riders), epic #10390 bucket 2 hosts #7596 + #10112 + #8620 + #9927. All stay queued behind the same window; this PR absorbs none.
- ADR corpus: ADR-135 (config-refresh channel), ADR-100 (host = sole scheduler, replace gated to maintenance window), ADR-117/#7228 (boot-trace channel design), ADR-232 (tag mint/build/digest-pin pipeline), ADR-096 (zot digest pin). None reversed or extended by this plan.
- Runbook `inngest-server.md` A1 row: the last replace consumed the 2026-10-18 owner go; **a fresh per-command operator go is required** for the next window (`hr-prod-host-config-change-immutable-redeploy`).

### Property List (Phase 0.6b)

- P1: the *next* host birth provably carries both vector.toml payloads — `Guard A3` covers the allowlist already; nothing pins the trim at the pinned tag.
- P2: post-replace close evidence is automated, not human-memory — follow-through sweeper + directives (convention exists; probes partially exist).
- P3: the measured read discriminates *which leg* is dark if a replace lands and the identifier still does not ship — per the CTO ruling's sharpening.
- P4: the replace dispatch itself — **operator class** (production-mutating authorization); not this PR's deliverable.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| Add `vector.toml` to `inngest-config-refresh-set.txt` (in-place delivery, no replace) | config delivery to live host | `infra-config-install.sh` DEST_SPEC (the engine) is a HARD-1 non-member; widening requires an engine change shipped only via image bake → same replace. No faster path. Also #11266 currently holds bundle promotion. |
| remote-exec / SSH redelivery to the inngest host | in-place config push | No SSH to this host by design (deny-all-public, init-only cloud-init; the ssh-parity guard has no exclusion path). |
| Dispatch `inngest-host-replace` from this pipeline | the actual delivery | Production-mutating; requires explicit per-command operator go (`hr-prod-host-config-change-immutable-redeploy`); window already tracked by epic #10390. |
| Emit-side change shipped blind (e.g., moving the restage unit's first-boot enable arm earlier in cloud-init) | possibly fixes #7596's emit leg | Undiagnosed hypothesis; unverifiable off-box (#5733 class — blind surface needs a structured probe before the nth fix). Also contaminates the experiment: an emit change + replace in the same window can't attribute the fix. CTO ruled against (below). |

### Relevant files

- `apps/web-platform/infra/vector.toml:623-626` — the trim (`collectors = ["memory","filesystem"]`, `scrape_interval_secs = 900`); `:142-143, :210-211, :479-487` — Source-4 allowlist.
- `apps/web-platform/infra/cloud-init-inngest.yml:991` — `STAGED` file list (docker-cp'd from the baked image); `:1279` — `IREF` pin (`v1.1.67@sha256:aa71d66b…`); `:858-930` — restage unit (write_files + `WantedBy=multi-user.target`); `:2766-2774` — first-boot enable arm.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh:1630-1678` — Guard A3 (#7596): pinned-tag + HEAD allowlist assertions, own counted span, anti-vacuity floor.
- `scripts/followthroughs/inngest-bs-token-restage-7596.sh` — existing probe (unenrolled); semantics: exit 0 PASS on `SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1` rows with `host=soleur-inngest` + `host_name=soleur-inngest-prd`; exit 2 TRANSIENT otherwise; FAIL unreachable.
- `scripts/betterstack-query.sh` — ClickHouse read path; sweeper env already wires `BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD` (`.github/workflows/scheduled-followthrough-sweeper.yml`).
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — directive + exit-code contract; `inngest-server.md` A1 row — replace-window evidence checklist.

### Institutional learnings applied

- `2026-10-28-a-probe-that-could-finally-pass-would-have-closed-its-tracker-on-pre-restart-evidence.md` — PASS must be generation-scoped: pre-replace markers (e.g., the 10-18 `bs-token-restage-enabled` BOOT_STAGE row) must never satisfy it. → both probes carry a **generation floor**; PASS counts only evidence from the current host generation.
- `2026-10-10-a-log-scraping-probe-matched-the-script-it-echoed` — probe greps anchor emitted line shapes, post-decode field isolation (the existing 7596 probe already does this).
- `2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md` — no blind emit-side edit; the probes are the structured probes.
- `2026-09-24-followthrough-retirement-headers-underenumerate-touch-points.md` — probe headers carry `RETIREMENT:` lists.
- `2026-07-07-followthrough-and-shape-gate-silent-falseness.md` — exit-code contract (no `${VAR:?}`, TRANSIENT on credential/query failure).
- `2026-10-29-sentry-events-sort-optional-pin-it-for-coverage-arguments.md` — windowed reads pin ordering/bounds (the probes' SQL windows are explicit, not "newest N" coverage arguments).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality (measured) | Plan response |
|---|---|---|
| #7596: "the inngest host still lacks [the allowlist]" | The live host runs `v1.1.61` whose baked vector.toml **contains** the allowlist — yet the identifiers never shipped across 14d/2 boots. The delivery leg may already be live; the emit leg is dark. | Probes remain the close instrument; the enhanced #7596 probe reports leg attribution (`pre_replace` / `leg_unit` / `boot_id_unresolvable` in its TRANSIENT reason, or `journald_rows=absent` inside an arm-2 PASS) so a post-replace `channel_dark` names the broken leg. Recorded as a hypothesis row, not a fix. |
| #11602: "rides the next inngest-host-replace" | Correct — and the pin (`v1.1.67`) already carries the trim; nothing repo-side blocks delivery. | PR ships the pin-time guard (Guard A4) so a future tag/pin regression reds before the bake, plus the measured-close probe. |
| #7596: "the fix is necessarily **rebuild the bootstrap image, then replace the host**" | Image rebuild is no longer needed — `vinngest-v1.1.67` already carries both payloads (auto-minted on the carrier changes). Only the replace remains. | Plan documents the dispatch as an operator step; no build dispatch required. |

## Proposed Solution

Ship the verification + pinning machinery; leave the prod-mutating dispatch to the operator window:

1. **Guard A4 (#11602)** in `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — mirror Guard A3's shape (pinned-tag blob + HEAD blob, own counted span, own anti-vacuity floor): assert the pinned tag's `vector.toml` `[sources.host_metrics]` block carries `scrape_interval_secs = 900` and `collectors = ["memory", "filesystem"]`, and HEAD's does too. A future pin/tag regression reds at test time, before the bake.
2. **New probe** `scripts/followthroughs/inngest-hostmetrics-trim-11602.sh` (+ `.test.sh`): GROUP BY `tags.collector` over a trailing window, rows isolated on `tags.host='soleur-inngest'` — metric rows ship in **native Vector shape** (`tags.host`/`tags.collector`/`name`/`gauge.value`; top-level `host`, `host_name`, `SYSLOG_IDENTIFIER`, `source_kind` all ABSENT — verified against a live row and `betterstack-log-query.md`, the `tag_metrics` remap is a measured no-op on metric events #6944/#9372). `tags.host` is the only discriminator the metric shape offers; it is also exactly the field the issue's own acceptance query groups by (default 24h, env-overridable); **PASS** iff the observed collector set is exactly `{memory, filesystem}` AND ≥1 row of each (positive liveness — a dark host can never satisfy it); **TRANSIENT** otherwise, with the reason naming the observed set (`untrimmed` / `no_host_metrics`). FAIL unreachable pre-replace by design (mirrors the sibling probe's contract — a FAIL that cannot discriminate is a sweeper misfire). Trailing-window contamination note: within 24h post-replace residual old-generation rows keep it TRANSIENT — fail-safe direction, self-clears.
3. **Enhance** `scripts/followthroughs/inngest-bs-token-restage-7596.sh` (+ **new** `.test.sh`):
   - **Generation floor**: count only evidence from the current host generation — `MIN_DT` baked at filing (the enrollment/filing date, ISO-8601 UTC — asserted by the suite; pre-floor rows are by construction pre-this-PR/pre-replace evidence) AND a PASS-qualifying row must **positively resolve and match** `_BOOT_ID` against the newest generation's boot id (newest `inngest-server-probe` row pins the current boot). `_BOOT_ID` unresolvable (e.g. server-probe dark on the new host while old-generation restage rows linger post-`MIN_DT`) → TRANSIENT `boot_id_unresolvable`, never a degraded MIN_DT-only PASS — that degraded path is exactly the stale-evidence close the 10-28 learning names.
   - **Leg discrimination** (CTO sharpening): on a dark restage leg, additionally query BOOT_STAGE markers (`SOLEUR_INNGEST_BOOT_STAGE stage=bs-token-restaged` / `bs-token-restage-enabled`, post-floor) and report the TRANSIENT reason as one of `pre_replace` (no post-floor evidence of any kind) or `leg_unit` (post-floor non-restage activity proves the host lives, but no restage-unit evidence of any leg — the unit likely never ran/enabled). `leg_journald` is NOT a TRANSIENT reason: post-floor BOOT_STAGE markers fire the second PASS arm first, so that leg's status is carried as `journald_rows=absent` *inside the arm-2 PASS output* — an either/or fixture that permits PASS-or-TRANSIENT asserts nothing.
   - **Second PASS arm** per the issue's own close wording ("or the host's own boot-stage markers"): post-floor BOOT_STAGE `bs-token-restaged` rows also satisfy PASS (they prove the unit ran AND the emit path reached the sink). BOOT_STAGE markers ride the direct-curl ingest leg (`cloud-init-inngest.yml:491,1129`), INDEPENDENT of the journald→vector leg under test — so a PASS must name its arm and the journald leg's state (`pass_arm=journald|boot_stage journald_rows=present|absent`) in the PASS output the sweeper posts — an arm-2 PASS with `journald_rows=absent` is the `leg_journald` verdict delivered at close time, not a hidden one — and arm-1 (journald) is preferred when both are present.
   - Keep the existing contract: xtrace refusal (exit 78), credential-missing → TRANSIENT, no `${VAR:?}`, post-decode field isolation, `host`+`host_name` both required.
4. **Enrollment** (work-phase `gh` calls, operator-visible issue mutations — not prod; **ordered POST-MERGE** — `sweep-followthroughs.sh` fails loudly on a directive whose `script=` isn't executable on main, so enrolling before merge reds the next daily sweep): `follow-through` label + `<!-- soleur:followthrough script=… earliest=<filing-date>T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->` directive pasted **unfenced at column 0** on #11602 and #7596; a comment on each issue recording enrollment, the anomaly evidence, and that the issues ride the sanctioned replace window (epic #10390 bucket 2). PR body uses `Refs` — never `Closes` (merge does not satisfy either acceptance; `wg-use-closes-n-in-pr-body-not-title-to`).
5. **Runbook note** in `inngest-server.md`: amend the **existing** `### Post-replace: the boot-trace allowlist (#7596)` section in place (it currently prescribes the manual `betterstack-query.sh` read and describes the probe pre-enhancement — it goes stale the moment this PR lands); record the `leg_*` verdict taxonomy, the automated sweeper close, and the #11602 counterpart — not merely an appended rider line in the tracked follow-ups table.

## Files to Create

- `scripts/followthroughs/inngest-hostmetrics-trim-11602.sh` — the #11602 measured-close probe (header: credential posture, exit-code contract, TRACKER, directive block, `RETIREMENT:` list naming the directive on #11602 and any suite rows referencing it).
- `scripts/followthroughs/inngest-hostmetrics-trim-11602.test.sh` — fixture-driven tests of the probe's verdict matrix (PASS exact-set, TRANSIENT on superset/absence/credential-miss/query-failure; a mutation battery per the Guard Contract below).
- `scripts/followthroughs/inngest-bs-token-restage-7596.test.sh` — the missing suite for the edited probe (verdict matrix incl. floor exclusion, leg attribution, both PASS arms).

## Files to Edit

- `scripts/followthroughs/inngest-bs-token-restage-7596.sh` — add generation floor (`MIN_DT` baked constant + `_BOOT_ID` match when resolvable), leg-discrimination read (BOOT_STAGE curl-marker leg), second PASS arm, TRANSIENT reasons `pre_replace`/`leg_unit`/`boot_id_unresolvable`; update header's exit-code table + TRACKER note and ADD a `RETIREMENT:` block (absent today) enumerating the new suite file, the #7596 directive, and the runbook section per the 2026-09-24 underenumeration learning.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — insert **Guard A4 (#11602)** after Guard A3: pinned-tag `[sources.host_metrics]` block asserts (`scrape_interval_secs = 900`, `collectors = ["memory", "filesystem"]`) + HEAD twins + anti-vacuity count row; keep the own-span counting discipline (do NOT fold A4 into the A3 span; re-baseline any trailing count-floor comment the suite carries).
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — amend the existing `### Post-replace: the boot-trace allowlist (#7596)` section in place: `leg_*` verdict taxonomy, automated sweeper close, #11602 counterpart.
- `scripts/test-all.sh` — explicit `run_suite` registration lines for the two `.test.sh` files (every existing `scripts/followthroughs/*.test.sh` is registered explicitly; `SUITE_GLOBS` does not cover them and the orphan linter's `EXCLUSIONS=()` is empty — an unregistered suite is a CI blocker, not a warning).

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing artifact — worst case is an internal tracker that auto-closes on weak evidence (a probe false-PASS) or never closes (probe stuck TRANSIENT), i.e., observability bookkeeping drift.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the probes read Better Stack telemetry with the already-wired read-only `BETTERSTACK_QUERY_*` creds; no new credential, store, or egress path.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** verification machinery for an internal observability gap; no user data, no user-facing surface, reversible by reverting the files and deleting the directives.

`threshold: none, reason: the only sensitive-path touch is apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh — a test suite asserting pinned-tag config content; it executes no production path and changes no host.`

## Observability

```yaml
liveness_signal:
  what: follow-through sweeper runs both probes daily; a probe that can never PASS leaves a dated TRANSIENT comment on its tracker (the signal the close is still owed), and a probe that errors reds the sweep run
  cadence: daily (scheduled-followthrough-sweeper.yml)
  alert_target: tracker issue comment (operator-visible) + red sweep run
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml + the two issue directives

error_reporting:
  destination: tracker issue comments (TRANSIENT reason strings: pre_replace / leg_unit / boot_id_unresolvable / untrimmed / no_host_metrics / query_failed / credentials_unprovisioned; the journald-leg verdict rides inside an arm-2 PASS as journald_rows=absent)
  fail_loud: sweeper run conclusion red on probe harness error; exit 78 on traced-credential run

failure_modes:
  - mode: replace lands but emit leg still dark (#7596 anomaly)
    detection: post-floor channel_dark persists; reason names leg_unit | boot_id_unresolvable, or the arm-2 PASS carries journald_rows=absent; in-surface signal is the journald→vector emit itself (the measurement is emitted FROM the host, not a host-side layer)
    alert_route: daily TRANSIENT comment on #7596 → operator files a diagnostic issue naming the leg
  - mode: replace lands with a pin that lost the trim (#11602)
    detection: Guard A4 reds at the pin-bump PR's CI (pre-bake); post-bake, the probe reports untrimmed collectors forever
    alert_route: CI failure on the pin-bump PR; TRANSIENT comment on #11602
  - mode: Better Stack read fails / creds unprovisioned
    detection: TRANSIENT reason=query_failed|credentials_unprovisioned
    alert_route: sweeper comment; sweeper Guard 3 comments REQUIRED SECRET MISSING on empty binding

logs:
  where: tracker issue comment history (last 4KB of probe stdout/stderr per sweep)
  retention: issue comment history (unbounded); KNOWN COST: the sweeper comments on every non-0/1 verdict with no dedup (~30 comments/mo per tracker while pre-replace) — mitigation: bump `earliest=` to the scheduled window date once the operator window is named

discoverability_test:
  command: bash -c 'test -f scripts/followthroughs/inngest-hostmetrics-trim-11602.sh && test -f scripts/followthroughs/inngest-bs-token-restage-7596.sh && echo ok'
  expected_output: ok
```

### Task Design note

Detection does not fire: no new `.github/workflows/*.yml`, no new Inngest function, no `CHECK_REGISTRY`/`arm-checkpoint` entry, no pg_cron, no host timer, no `setInterval` daemon. The probes join the **existing** sweeper (`scheduled-followthrough-sweeper.yml` is unchanged; the directive is issue-body data, not a file). Dedupe is the sweeper's own contract (one comment per sweep per tracker) + probe idempotence (read-only queries, deterministic exits).

## Encryption Posture

Skipped — no new persistent store and no new cross-component connection. The probes reuse the existing Better Stack ClickHouse read path (`scripts/betterstack-query.sh`, TLS to the vendor endpoint, existing `BETTERSTACK_QUERY_*` creds already wired in the sweeper env).

## Guard Contract

### Guard 1 — Guard A4: pinned-tag vector.toml carries the host_metrics trim

**Property.** The bootstrap image the next `inngest-host-replace` boots provably carries `scrape_interval_secs = 900` and `collectors = ["memory", "filesystem"]` in `[sources.host_metrics]` — asserted at the pinned tag's tree AND at HEAD, so neither a stale tag nor a HEAD-side revert can ship the untrimmed set silently.

**Assembly.** Two chokepoints, both asserted: (a) `git show <pinned-tag>:apps/web-platform/infra/vector.toml` resolved through the same `GA_TAG_REF` mechanism Guard A/A3 use (the tag cloud-init-inngest.yml's `IREF` pins — the artifact the host actually boots); (b) `apps/web-platform/infra/vector.toml` at HEAD (what the next mint will bake). Assembly is the pin indirection itself, not a member list — a pin move is exactly what the guard watches.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert HEAD `vector.toml` collectors to `["cpu","memory","disk","filesystem","load"]` (tag blob untouched) | RED (HEAD asserts) |
| 2 | Repoint the pinned tag at a tree whose `vector.toml` lacks the 900s interval (e.g. `vinngest-v1.1.61`) | RED (tag asserts) |
| 3 | Delete the Guard A4 block entirely → anti-vacuity count row must fire | RED |
| 4 | Remove `scrape_interval_secs` line only (collectors kept) at HEAD | RED |
| 5 | Suite harness: stub `GA_TAG_REF` to unresolvable → the non-empty-blob assert must fire, never "nothing to compare" | RED |

**Harness rows.** (a) must-RED-on-suite: run the suite with the Guard A4 assert lines commented out → the `GUARDA4_ASSERTIONS` floor row reports the shortfall (suite RED). (b) must-PASS non-canonical: a pin move to any *later* tag that still carries the trim (e.g. the next auto-minted `vinngest-v1.1.68+`) passes without suite edits — the guard asserts content, not a literal tag name.

**Anchor.** The guard compares two *stored* trees (pinned tag, HEAD) — both move only via reviewed commits to main (tag mints land on main-only commits per #8775; HEAD is the PR merge). A weakening requires a commit that removes the trim or a pin pointing at a pre-trim tag — both cross the guard's own diff in the same PR that would carry it. The tag pin is resolved from `cloud-init-inngest.yml`'s `IREF` at test time, not a duplicated literal, so the anchor is the reviewed pin itself.

### Guard 2 — the two follow-through probes (measured-close drift checks)

**Property.** Each tracker's issue-closing PASS is issued only on evidence from the *current* host generation: (11602) the trailing-24h collector set over `tags.host='soleur-inngest'`-isolated rows is exactly `{memory, filesystem}` with ≥1 row each; (7596) post-floor `inngest-bs-token-restage` journald rows with `ok=1`, or post-floor BOOT_STAGE `bs-token-restaged` markers — never pre-replace evidence, never an empty/vacuous window.

**Assembly.** Three chokepoints: (a) `scripts/followthroughs/inngest-hostmetrics-trim-11602.sh` verdict construction (window query → set equality + per-collector liveness floor); (b) `scripts/followthroughs/inngest-bs-token-restage-7596.sh` verdict construction (floor filter → ident+host+host_name+marker isolation → PASS arms); (c) `scripts/sweep-followthroughs.sh`'s exit-0 → close contract (already shipped; the probes' job is to make exit 0 *mean* delivered). The probes are the only writers of the PASS signal the sweeper consumes.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture: untrimmed collector set (cpu/memory/disk/filesystem/load) in window → `inngest-hostmetrics-trim-11602.sh` must NOT exit 0 | TRANSIENT `untrimmed` |
| 2 | Fixture: zero host_metrics rows in window → must NOT PASS (vacuous-set trap) | TRANSIENT `no_host_metrics` |
| 3 | Fixture: only `memory` rows (filesystem missing) → must NOT PASS on partial set | TRANSIENT |
| 4 | Fixture: restage `ok=1` row whose `_BOOT_ID`/dt predates the floor → `inngest-bs-token-restage-7596.sh` must NOT exit 0 (stale-generation evidence) | TRANSIENT |
| 5 | Fixture: post-floor BOOT_STAGE `bs-token-restaged` marker, journald rows absent → deterministic PASS carrying `pass_arm=boot_stage journald_rows=absent` (the journald-leg verdict travels in the close comment) | PASS arm-2 |
| 6 | Guard's own dispatch: run each `.test.sh` with the probe stubbed to always-TRANSIENT → suite must go RED (a green suite on a neutered probe is vacuous) | RED suite |
| 7 | Fixture: post-floor restage `ok=1` row while the server-probe read is absent (boot id unresolvable) → `inngest-bs-token-restage-7596.sh` must NOT exit 0 | TRANSIENT `boot_id_unresolvable` |

**Harness rows.** (a) must-RED-on-suite: each `.test.sh` includes a self-check that its fixtures actually exercise the verdict path (a probe that never reaches a verdict can't fake green). (b) must-PASS non-canonical: a fixture carrying the exact-set collectors *plus* unrelated SYSLOG_IDENTIFIER noise (stunnel4/doppler rows, as the live census shows) must still PASS — the verdict reads `tags.collector`/`SYSLOG_IDENTIFIER` post-decode, not row shape.

**Anchor.** PASS-vs-TRANSIENT is decided against *live vendor data at sweep time*, not a stored value — the "registry" the probes cannot self-certify is the Better Stack archive itself; the floor constant and ident set are committed in the same PR as the probes but a weakening of them requires a new reviewed diff that the sweeper does not create.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Ride the next `inngest-host-replace` (maintenance-window dispatch; destroys+creates the cpx22 — explicit per-command go-ahead required" [issue #11602] | Recorded as deferred operator step (Deferred Operator Steps, below); NOT executed by this pipeline | mapped — deferral recorded, tracked by the issue itself |
| 2 | "Post-replace, the same GROUP BY collector query shows soleur-inngest limited to `memory` + `filesystem` at 900s." [issue #11602 Acceptance] | New probe `inngest-hostmetrics-trim-11602.sh` + directive enrollment on #11602 | mapped |
| 3 | "the fix is necessarily **rebuild the bootstrap image, then replace the host**" [issue #7596] | Rebuild no longer needed (v1.1.67 already carries both payloads — auto-minted); replace recorded as deferred operator step | mapped — premise corrected in Research Reconciliation |
| 4 | "an off-host query returns rows for `inngest-boot-phone-home` (or the host's own boot-stage markers) from the **inngest** host" [issue #7596 close condition] | Enhanced `inngest-bs-token-restage-7596.sh` (floor + leg discrimination + BOOT_STAGE PASS arm) + directive enrollment on #7596 | mapped |
| 5 | "#11602 #7596 in one PR" [invocation] | Single PR carrying probe + probe-edit + tests + Guard A4 + runbook note + enrollment | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `inngest-hostmetrics-trim-11602.sh` + `.test.sh` | "Post-replace, the same GROUP BY collector query shows soleur-inngest limited to `memory` + `filesystem` at 900s" | asked |
| `inngest-bs-token-restage-7596.sh` edits + new `.test.sh` | "an off-host query returns rows for `inngest-boot-phone-home` (or the host's own boot-stage markers)" | asked |
| Guard A4 in `cloud-init-inngest-bootstrap.test.sh` | — | inferred — the delivery invariant "the next replace carries the trim" has no pin-time assertion; Guard A3 (#7596) is the established shape for exactly this guarantee |
| Issue-body directive + `follow-through` label on #11602/#7596 | — | inferred — the measured-close contract is the issues' own acceptance; enrollment is the machinery that executes it without human memory (followthrough-convention §Why) |
| `inngest-server.md` rider note | — | inferred — the runbook's replace-window checklist is where post-window evidence expectations live; leaving the probes unrecorded there strands the next window's operator |

### Split Assessment

- Subsystems touched: 3 — `scripts/followthroughs/`, `apps/web-platform/infra/`, `knowledge-base/engineering/operations/runbooks/`
- Planned files: 5 (3 create, 2 edit) | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines → all under
- Recommendation: single PR

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/observability tooling change. (Product/UX mechanical override did not fire: no UI-surface file in Files to Create/Edit.)

## Acceptance Criteria

- [ ] AC1: `scripts/followthroughs/inngest-hostmetrics-trim-11602.sh` exists, executable, header carries credential posture + exit-code contract + TRACKER + `RETIREMENT:` list; exit 0 only when the trailing-window collector set over rows with `tags.host='soleur-inngest'` (metric rows carry no `host`/`host_name` — native Vector shape; `tags.host` is the sole discriminator and the issue's own grouping field) is exactly `{memory, filesystem}` with ≥1 row of each; TRANSIENT (exit 2) on superset/absence/credential-miss/query-failure.
- [ ] AC2: `inngest-hostmetrics-trim-11602.test.sh` exists and passes locally; includes the mutation battery rows (Guard Contract Guard 2, rows 1-3, 6) — a stubbed-probe run must go RED.
- [ ] AC3: `inngest-bs-token-restage-7596.sh` carries the generation floor (post-floor-only evidence) and leg-attributed TRANSIENT reasons (`pre_replace` / `leg_unit` / `boot_id_unresolvable`); a BOOT_STAGE `bs-token-restaged` marker post-floor satisfies PASS per the issue's "or the host's own boot-stage markers" wording.
- [ ] AC4: `inngest-bs-token-restage-7596.test.sh` exists and passes; covers the floor-exclusion row (stale-generation evidence must not PASS) and both PASS arms.
- [ ] AC5: Guard A4 block exists in `cloud-init-inngest-bootstrap.test.sh` asserting pinned-tag + HEAD `scrape_interval_secs = 900` and `collectors = ["memory", "filesystem"]`, with own-span anti-vacuity count row; the suite passes against the current `v1.1.67` pin.
- [ ] AC6: `inngest-server.md` records the two riders and the post-window verdict → diagnostic-issue mapping.
- [ ] AC7: Both issues carry the `follow-through` label and an unfenced column-0 `<!-- soleur:followthrough script=… earliest=… secrets=… -->` directive pointing at the correct probe — applied **post-merge** (a pre-merge directive fails the next sweep on the missing `script=`); each issue has a comment recording enrollment + the anomaly evidence + the deferred operator dispatch.
- [ ] AC8: PR body uses `Refs #11602 #7596` (never `Closes`); the deferred operator step names the exact dispatch (`gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason='…'`) as owner-only.
- [ ] AC9: No change to any production-path file: diff is confined to `scripts/followthroughs/`, `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, `scripts/test-all.sh`, `knowledge-base/engineering/operations/runbooks/inngest-server.md`.
- [ ] AC10: `scripts/test-all.sh` registers both new `.test.sh` suites via explicit `run_suite` lines (orphan-linter-clean).
- [ ] AC11: Convention-mandated branch dry-run (`followthrough-convention.md` §Author workflow): `gh workflow run scheduled-followthrough-sweeper.yml --ref <branch> -f dry_run=true` after enrollment rehearsal — both trackers' `exit=` lines report the expected TRANSIENT reasons (never PASS pre-replace).
- [ ] AC12: `_BOOT_ID`-unresolvable path is a named TRANSIENT (`boot_id_unresolvable`), covered by a fixture: post-floor restage row + absent server-probe read → no exit 0.

## Test Scenarios

- `unit` — probe verdict matrix (fixtures: trimmed set / untrimmed set / empty window / partial set / query failure / missing creds → PASS vs named TRANSIENT).
- `unit` — restage-probe floor: fixture rows dated before `MIN_DT` must never produce exit 0; post-floor `ok=1` journald row → PASS; post-floor BOOT_STAGE-only → PASS carrying `pass_arm=boot_stage journald_rows=absent`.
- `unit` — Guard A4: suite red when the pinned-tag blob loses the trim; red when the block is deleted (anti-vacuity).
- `integration` — live probe runs (read-only, doppler `prd_terraform`): `inngest-hostmetrics-trim-11602.sh` currently exits 2 `untrimmed` (matches #11602's measurement); `inngest-bs-token-restage-7596.sh` currently exits 2 with a `channel_dark`-family reason (matches the census).
- `integration` — the shard containing `cloud-init-inngest-bootstrap.test.sh` + the two probe suites is green.

## Dependencies & Risks

- **Operator dependency (deferred):** the actual close requires the sanctioned `inngest-host-replace` window (a fresh per-command go is required — the 2026-10-18 go was spent). This plan does not perform it and blocks PR-ready on nothing: the issues stay open and the sweeper reports TRANSIENT until the replace lands.
- **Emit-leg anomaly (#7596):** the allowlist is already baked in the running image (v1.1.61) yet the identifier is dark — the next replace may not close #7596. The probes' leg attribution exists precisely to name that outcome; a persistent post-replace `leg_*` verdict spawns a diagnostic issue rather than a blind fix.
- **Sweeper close is irreversible** (10-28 learning): both probes' PASS is generation-floored; a false-PASS on stale evidence is the designed-out failure.
- **Trailing-window contamination (#11602):** ≤24h post-replace the probe may still see old-generation rows → TRANSIENT, self-clearing; documented in the probe header.
- **Deferred items:** the `inngest-host-replace` dispatch is tracked by #11602/#7596 themselves + epic #10390 bucket 2 — no new tracking issue needed. Sibling riders (#10539, #10544, #11011, #11265, #11336, #11266) deliberately NOT absorbed.

## Decision Rulings

Ruled by CTO agent, 2026-10-30: Item 1 — Option A (verification machinery only). The anomaly localizes #7596's defect to the emit leg on this host generation; the replace is a diagnostic instrument, not guaranteed delivery. Option B (blind emit-side edit) disqualified — undiagnosed path, unverifiable off-box, contaminates the experiment (#5733 class). Option C (diagnostic issue now, split the pair) disqualified — zero additional discriminating power. Sharpening: the #7596 probe discriminates legs — as applied post-review, `pre_replace`/`leg_unit`/`boot_id_unresolvable` TRANSIENT reasons plus `journald_rows=absent` attribution inside an arm-2 PASS — and the directive maps each verdict to its diagnostic follow-up.

Ruled by CTO agent, 2026-10-30: Item 2 — Option A (Refs + sweeper-driven measured close). `Closes` would false-close at merge on zero evidence; the sweeper's exit-0 contract executes each issue's own acceptance bar. `earliest=` reflects the replace dependency; pre-replace states report TRANSIENT, never FAIL.

## Success Metrics

- Post-merge sweep: both trackers carry directives; probes run daily; first sweep posts TRANSIENT reason strings naming the waiting state.
- Post-replace: #11602 auto-closes on the measured collector-set PASS; #7596 auto-closes on restage-row or BOOT_STAGE-marker PASS — or stays open with a named-leg verdict that seeds the diagnostic issue.

## References & Research

- Issues: #11602, #7596 (targets); #7457 (allowlist origin), #7228 (boot-trace design), #7539 (web-1 half, delivered), #7462 (host restore, closed), #10390 (epic, bucket 2), #10539/#10544/#11011/#11265/#11336/#11266 (replace-window riders — not absorbed).
- PRs: #11494 (ingest cut carrying the trim), #11533 (pin bump to v1.1.67).
- ADRs: ADR-135 (config-refresh channel), ADR-100 (sole scheduler), ADR-117 (boot trace), ADR-232 (mint/digest pipeline), ADR-096 (zot digest pin).
- Runbooks: `followthrough-convention.md`, `inngest-server.md`, `vector-redeliver.md`, `inngest-config-refresh.md`.
- Learnings: `2026-10-28-a-probe-that-could-finally-pass-…`, `2026-10-10-a-log-scraping-probe-…`, `2026-07-01-blind-surface-…`, `2026-09-24-followthrough-retirement-headers-…`, `2026-07-07-followthrough-and-shape-gate-…`.

## Open Code-Review Overlap

None — the open `code-review` issue list (98 issues) names none of the planned file paths; the `scripts/followthroughs/` substring hits (#8435, zot probes, #8800 fixture) are unrelated trackers.

## Deferred Operator Steps (not executed by this pipeline)

1. `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason='deliver vector.toml trim (#11602) + boot-trace allowlist (#7596); riders: epic #10390 bucket 2'` — **owner-only**, maintenance window, fresh per-command go (`hr-prod-host-config-change-immutable-redeploy`); precondition checklist per `inngest-server.md` A1 row. The issues auto-close via the enrolled probes once evidence lands.
