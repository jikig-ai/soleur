---
title: "fix(observability): host_name telemetry mislabel — web-1 self-labels soleur-inngest-prd"
issue: 6616
branch: feat-one-shot-6616-host-name-telemetry-mislabel
date: 2026-07-17
type: fix
lane: single-domain
brand_survival_threshold: aggregate pattern
milestone: "Post-MVP / Later"
status: draft
deepened: 2026-07-17
---

# 🐛 fix(observability): `host_name` telemetry mislabel — web-1 self-labels `soleur-inngest-prd`

Ref #6616. Surfaced by #6594 (CLOSED, superseded by #6613 MERGED); poisons attributions built on `host_name`.

## Enhancement Summary

**Deepened 2026-07-17.** 4-agent review panel (architecture-strategist, observability-coverage-reviewer,
spec-flow-analyzer, code-simplicity-reviewer) + repo/history research. All load-bearing infrastructure
citations were verified live against code (architecture-strategist: "every infrastructure citation checks out").

**Key revisions applied from review:**
1. **Re-keyed the check on the IDENTITY invariant, not bare cardinality.** The true invariant is
   "`soleur-inngest-prd` is emitted only by the dedicated Inngest node." Bare "`≥2` distinct `host`"
   cardinality diverges from it in two ways both spec-flow and architecture caught: (a) a **single**-emitter
   mislabel (web-1 sole emitter, dedicated node silent) reads `1:1` yet is still wrong; (b) a **schema-drift
   false-GREEN** — if Vector's `host` field is renamed/absent, `JSONExtractString(raw,'host')` is empty for
   every row, all labels collapse to one empty `host`, and the check goes vacuously GREEN. Fix: pin the
   dedicated node's OS hostname from an **authoritative source** (`inngest.tf` → `soleur-inngest-server-prd`),
   not from the possibly-poisoned Phase-0 map, and require a **positive schema-liveness marker** (that
   hostname present as a non-empty `host` in the window) before any GREEN/PASS is trusted.
2. **Collapsed the standing detector into a single identity-keyed follow-through (net −~1300 LOC).** The
   original draft shipped BOTH a born-firing `scheduled-hostname-mislabel` alarm AND a follow-through that
   compute the **same** query. Code-simplicity + spec-flow: the standalone alarm is red-from-birth (web-1
   carries the stale label now, and recreate is blocked indefinitely), so it would open a perpetually-FIRE
   `action-required` issue — training operators to ignore the very channel it creates — while surfacing
   nothing Phase 0 didn't already establish. It is cut. The follow-through is the sole polling artifact; it
   rides the **existing** `scheduled-followthrough-sweeper.yml` (already Sentry-monitored, `BETTERSTACK_QUERY_*`
   already wired) and is **read-only** (resolving observability-coverage's P2 that a discoverability probe must
   not mutate GitHub issue state). *Recorded dissent:* architecture-strategist and observability-coverage
   judged the standing alarm well-designed and "proportionate" if built. The cut is a scope/taste call —
   persisted to `specs/…/decision-challenges.md` for `ship` to surface as an `action-required` issue. It is
   reversible: build a generic multi-host collision detector **if/when a non-web-1 collision is ever observed**
   (YAGNI — the bug class is structurally closed for fresh hosts since #6396/#6344).
3. **Armed the closure loop on #6616 itself** (spec-flow + architecture): the follow-through targets #6616
   with a concrete `earliest` re-evaluation date and an explicit `gh issue close 6616`-on-PASS; the web-1
   recreate is the existing GA host-replaceability work (no redundant tracker).
4. **Added an ADR-100 amendment pointer** (architecture) so the create-time-render invariant is discoverable
   from the decision record, and made the `model.c4` "isolated"↔"shared" contradiction an explicit **edit**
   of both arms (architecture), not just a listed reconcile.

## Overview

A **web** host emits its Better Stack Logs telemetry (source 2457081) stamped
`host_name = "soleur-inngest-prd"`, colliding with the dedicated Inngest host on the sole
per-host discriminator. #6594 recorded the tell: gate rows carry **`host = soleur-web-platform`
AND `host_name = soleur-inngest-prd`** simultaneously. `host` is Vector's auto-derived OS
hostname (correct); `host_name` is the Vector-injected literal (wrong). The mislabeled host is
**web-1** — the only web host shipping telemetry (web-2 is dark: 0 lines/24h per the
2026-07-16 web-2-retire brainstorm).

**The issue's remedy is stale; its symptom is correct.** The proposed fix ("make `host_name`
derive from the actual host identity, not a static literal") **already shipped** in #6396 /
PR #6401: `vector.toml` carries an `@@HOST_NAME@@` sentinel rendered per-host from the
Terraform-injected `SOLEUR_HOST_NAME` (`server.tf`, the `host_name = each.key == "web-1" ? …`
line → `soleur-web-platform` / `soleur-web-2`); the fresh-host bootstrap renders it correctly
(`soleur-host-bootstrap.sh`, the `@@HOST_NAME@@` → `${SOLEUR_HOST_NAME:-$(hostname)}` sed).
**The templating code is not the bug.**

The bug is **create-time-render drift on a long-lived running host** — the class the C4 model
already documents for the #6425/#6594 tunnel-connector coin-flip ("a construction-time gate
presented as a runtime precondition — it governs only future fresh hosts"). web-1 predates #6344
(which gated co-located Inngest behind `web_colocate_inngest`, default false) and #6396/ADR-100
(dedicated Inngest host). It booted in the co-located-Inngest era, so it runs an **inngest-owned
`vector.service`** whose config was `sed`-rendered `host_name=soleur-inngest-prd` (`inngest-bootstrap.sh`,
the `sed -i 's|@@HOST_NAME@@|soleur-inngest-prd|g'` line; unit `EnvironmentFile=/etc/default/inngest-server`).
Because `hcloud_server.web` carries `lifecycle { ignore_changes = [user_data, …] }`, web-1 **never
re-ran cloud-init** to pick up #6396's per-host name — and even a re-run of the web-install path would
**skip** it, by design, while the inngest-owned unit exists (`soleur-host-bootstrap.sh`, the
"inngest-owned vector.service present; skipping web install" guard). All four blockers verified live
by the deepen-plan panel.

**Correcting web-1's running label is impossible in this PR.** It requires an immutable
redeploy (recreate) — SSH edits are forbidden (`hr-no-ssh-fallback-in-runbooks`,
`hr-prod-host-config-change-immutable-redeploy`, principle AP-002) — and there is **no
`web-1-recreate` dispatch target** (`apply-web-platform-infra.yml` options are
`web-2-recreate | inngest-host | inngest-host-replace | registry-host-replace |
registry-region-migrate | git-data-host-replace`; warm-standby targets are hardcoded to web-2),
with recreate itself blocked (cx33 unorderable EU-wide; ADR-119 §(e); sole prod host + plaintext
`/workspaces` volume). So this plan does **not** attempt the physical relabel. It delivers what is
achievable and brand-safe now, in three proportionate parts:

1. **Diagnose from live data** (identity-keyed, not code-reading): a read-only Better Stack
   ClickHouse query that pins exactly which `host` values wear `host_name=soleur-inngest-prd`,
   confirming the web-1 collision before any conclusion is frozen.
2. **Correct the attribution record**: fix the C4 overclaim + "isolated" contradiction, add a
   learning, add an ADR-100 pointer, and re-derive the `host_name`-based readings the issue flags
   as suspect.
3. **Arm automated closure**: a single identity-keyed, read-only, schema-liveness-guarded
   follow-through on #6616 that rides the existing Sentry-monitored sweeper and auto-closes #6616
   when web-1 is eventually recreated (the GA blue-green / ADR-119 host-replaceability work) and
   the label clears.

## Research Reconciliation — Spec vs. Codebase

| Premise (issue #6616 body) | Codebase reality (measured) | Plan response |
|---|---|---|
| "Likely cause: `host_name` is a `sed`-rendered Vector literal (#6396) not re-templated per host" | #6396/PR #6401 **already** re-templated it per-host for FRESH hosts (`vector.toml` `@@HOST_NAME@@`; `server.tf` per-host `host_name`; `soleur-host-bootstrap.sh` render). The `sed`-literal path now renders **only** the dedicated Inngest host (`inngest-bootstrap.sh`) — correct. | Do NOT re-touch templating. Reframe cause as **create-time-render drift on the running pre-#6396 web-1 host**. |
| "Fix: make `host_name` derive from actual host identity, then re-audit" | The derive-from-identity fix is merged; the residual is a running host that predates it and cannot re-run cloud-init (`ignore_changes=[user_data]`). | Diagnose + correct-record + arm closure. No code templating change. |
| "explains the `host=…web-platform` / `host_name=…inngest-prd` conflict #6594 flagged as UNVERIFIED" | **Confirmed as the mechanism.** `host` = Vector auto OS-hostname (`soleur-web-platform`, correct); `host_name` = Vector literal (`soleur-inngest-prd`, stale). Gate rows (`ci-deploy`, `infra-config-apply`) originate on web-1. | Phase 0 query confirms live (identity-keyed) before freezing. |
| "#6425's reading that the false `inngest-down` alarms came from web-2 … should be re-derived once the label is fixed" | #6425's attribution was via **Cloudflare connector colo census** (`model.c4`; #6425 body), **NOT** `host_name` telemetry (web-2 ships 0 lines). It is **unaffected** by this mislabel and stands. | Re-derivation = document that #6425 did not depend on `host_name`; the suspect readings are any that treat `host_name=soleur-inngest-prd` rows as "the dedicated Inngest host." |
| Dedicated Inngest node identity | Hetzner server name `soleur-inngest-server-prd` (`inngest.tf`); cloud-init sets no explicit `hostname:`, so its Vector `host` (auto OS hostname) = `soleur-inngest-server-prd` while its `host_name` literal = `soleur-inngest-prd`. **`host ≠ host_name` by design even on the legitimate host.** | The check keys on the identity `soleur-inngest-prd ↔ soleur-inngest-server-prd`; a naive `host==host_name` check would false-fire on the legitimate node. |
| #6396 / #6594 / #6613 status | PR #6401 MERGED; #6594 CLOSED; #6613 MERGED. | Cite as provenance only. |

**Premise Validation note:** All referenced issues probed (`gh issue/pr view`). #6396's remedy is
already implemented, so the plan is **remediation of a running-host drift + record-correction +
armed closure**, not a templating change. No external premise remained that would re-shape the plan
beyond this reframe.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — Better Stack Logs is a
management-plane surface; `app.soleur.ai` is a direct CF-proxied A-record to web-1 (`dns.tf`) and
never traverses this telemetry path. The user-reaching risk is **indirect and diagnostic**: during
a real web-1 incident, operators/agents reading `host_name` attribute web-1's signal to the
(healthy) dedicated Inngest host — or miss a genuine web-1 problem filed under `soleur-inngest-prd`
— and remediate the wrong host. The sole serving host being the one that lies makes a mis-routed
remediation the acute failure mode.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — no new data surface;
`host_name`/`host` are infra identity labels; journald + host_metrics are already PII-scrubbed
(`vector.toml` `pii_scrub_*`). The follow-through reads telemetry read-only via an existing
Doppler-scoped ClickHouse connection.

**Brand-survival threshold:** `aggregate pattern` — the harm is a *pattern* of poisoned attribution
across analyses ("every attribution built on `host_name` is suspect"), not a single user's
data/money/workflow. The durable record-correction (C4 + learning + ADR pointer) is the structural
mitigation; the armed follow-through closes the loop when the physical fix eventually ships.

## Hypotheses (diagnosis-first — the fix does not begin until H1 is confirmed live)

Per `2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`: the
deciding datum is which physical `host` emits `host_name=soleur-inngest-prd` in source 2457081.
That datum is in Better Stack, not the repo. Code-reading makes H1 the overwhelming favorite but
cannot confirm it — Phase 0 runs the query.

| # | Hypothesis | Status (repo evidence) | Discriminator (Phase 0, identity-keyed) |
|---|---|---|---|
| H1 | web-1's pre-#6396 inngest-owned `vector.service` stamps all its rows `soleur-inngest-prd`; ≥2 distinct hosts collapse on that label. | **Strongly supported, not confirmed.** | `soleur-inngest-prd` is emitted by a `host` set that includes a web hostname (not just `soleur-inngest-server-prd`). |
| H2 | The pairing is a **misread** of source-name vs discriminator (no real mislabel). | **Weakened** — `host` is the auto OS-hostname, not the source name (`soleur-inngest-vector-prd`). | `soleur-inngest-prd` emitted **only** by `soleur-inngest-server-prd`, AND that host is present (schema-liveness). |
| H3 | web-2 (not web-1) is the mislabeled emitter. | **Refuted** — web-2 ships 0 lines/24h. | web-2's OS hostname absent from source 2457081 rows. |
| H4 | web-1 is the **sole** emitter of `soleur-inngest-prd` (dedicated node silent/renamed). | Possible; a `1:1` map that is still WRONG (the cardinality trap spec-flow flagged). | `soleur-inngest-prd`'s single `host` is a web hostname, NOT `soleur-inngest-server-prd`. |

**Verdict rule (identity, not cardinality):** confirm the mislabel iff `host_name=soleur-inngest-prd`
is emitted by any `host` other than the authoritative `soleur-inngest-server-prd` (covers H1 and H4).
Premise is stale (re-scope to close #6616 as not-reproducing) iff `soleur-inngest-prd` is emitted
**only** by `soleur-inngest-server-prd` AND that host is present in the window (schema-liveness — an
all-empty `host` column is a probe/schema fault, not a GREEN). On probe fault / creds-unavailable in
the agent session (as opposed to a data answer), do NOT dead-end: proceed to commit the
record-correction + follow-through with the identity pins taken from `inngest.tf` (authoritative,
not the query), and let the **first prod sweeper run** (which holds `prd_terraform` creds) perform
the live confirmation — the follow-through is fail-safe TRANSIENT until then.

## Implementation Phases

### Phase 0 — Ground-truth diagnosis (read-only, no prod write)
- Run the identity query and record its output verbatim into the spec's `session-state.md` (and a
  durable artifact `ship` folds into the PR body — never author the PR body from `work`/`plan`):
  ```bash
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "
    SELECT JSONExtractString(raw,'host_name') AS host_name,
           JSONExtractString(raw,'host')      AS host,
           count() AS n
    FROM ( SELECT raw FROM remote(\$BS_TABLE)
           UNION ALL
           SELECT raw FROM s3Cluster(primary, \$BS_TABLE_S3) )
    WHERE dt > now() - INTERVAL 24 HOUR
    GROUP BY host_name, host ORDER BY host_name, n DESC FORMAT JSONEachRow"
  ```
  (Archive arm included — the hot window is ~40 min.)
- Apply the identity verdict rule above. Pin the authoritative dedicated-node hostname
  `soleur-inngest-server-prd` from `inngest.tf` (NOT from the query output) for the follow-through's
  expected-good identity + schema-liveness marker.

### Phase 1 — Attribution correction (docs / C4 / learning / ADR pointer)
- **`model.c4`** — two coordinated edits (cite by content anchor, `cq-cite-content-anchor-not-line-number`):
  - the `hetzner -> betterstack` edge whose description asserts "*per-host `host_name` discriminator …
    every web host ships logs post-ADR-100 (#6396)*": add the create-time-drift caveat — web-1 predates
    #6396 and, under `ignore_changes=[user_data]`, still ships `host_name=soleur-inngest-prd` until its
    next recreate, so source 2457081 currently carries a `host_name` collision (web-1 + the dedicated
    Inngest node). Mirror the connector-caveat style already on the tunnel edge.
  - the `inngest -> betterstack` edge that calls source 2457081 the "**isolated** Logs source": reconcile
    with the (correct) "**shared**" description on the web edge — the documented collision **contradicts**
    "isolated". Edit it, do not merely list it.
  - Verify against all three `.c4` files that no new element/relationship/`view include` is needed
    (`betterstack`/`hetzner`/`inngest` already modeled; `views.c4` references `betterstack` as
    inclusion-only). Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- **ADR-100** — add a one-line amendment/pointer note under its per-host-`host_name` decision: the
  discriminator is a **create-time render**, so a host that predates the render (web-1) can carry a stale
  label until recreate; the live invariant is enforced by the #6616 follow-through, not by the render alone.
- **Learning** `knowledge-base/project/learnings/<date>-host-name-create-time-render-drift-web1-mislabel.md`
  (author picks date at write time): the create-time-render-drift class, the web-1 mislabel, the identity
  (not cardinality) discriminator, and the #6425 re-derivation (connector-census-based → `host_name`-independent
  → unaffected; the suspect readings are any treating `soleur-inngest-prd` rows as the dedicated node).
  Verify every `knowledge-base/` citation resolves.

### Phase 2 — Arm automated closure (single read-only follow-through, no standing alarm)
- `scripts/followthroughs/hostname-mislabel-web1-6616.sh` — the **sole** polling artifact, ~46 LOC on the
  `betterstack-quota-verdict-5105.sh` / `chardevice-wedge-nonrecurrence-5934.sh` precedent. Exit contract
  (`scripts/sweep-followthroughs.sh`): `0=PASS (close #6616)`, `1=FAIL (comment, leave open)`, `*=TRANSIENT (retry)`.
  - **PASS iff** `host_name=soleur-inngest-prd` is emitted **only** by `soleur-inngest-server-prd`
    (identity, pinned from `inngest.tf`) over the window.
  - **Schema-liveness / vacuous-pass guard** (`#5934`): require a **positive marker** — `≥1` row whose
    `host = soleur-inngest-server-prd` in the window — BEFORE any PASS; an all-empty/absent `host` column,
    a creds fault, or a query error exits **TRANSIENT**, never PASS. This closes both the "source went dark"
    and the "`host` field renamed → empty → vacuous GREEN" false-close.
  - **FAIL** (collision still present) while web-1 carries the stale label — leaves #6616 open. Read-only:
    the script never mutates GitHub state itself (the sweeper posts the comment/close), resolving the
    discoverability-probe mutation concern.
- **Enroll on #6616 itself** with the directive
  `<!-- soleur:followthrough script=scripts/followthroughs/hostname-mislabel-web1-6616.sh
  earliest=<concrete re-eval date, e.g. merge+90d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
  + label `follow-through`. `earliest` is a **concrete future re-evaluation date** (not a placeholder and not
  merge-day) so the sweep cadence stays low-noise on an indefinitely-blocked fix; the PASS branch
  auto-closes #6616 once web-1 is recreated (the existing GA host-replaceability work — no redundant tracker)
  and the label clears. `BETTERSTACK_QUERY_*` is **already wired** into `scheduled-followthrough-sweeper.yml`
  (verified) — no workflow edit needed; confirm at /work.

## Files to Create
- `scripts/followthroughs/hostname-mislabel-web1-6616.sh`
- `knowledge-base/project/learnings/<date>-host-name-create-time-render-drift-web1-mislabel.md` (date at write time)
- `knowledge-base/project/specs/feat-one-shot-6616-host-name-telemetry-mislabel/decision-challenges.md` (the detector-cut dissent record; `ship` renders it)

## Files to Edit
- `knowledge-base/engineering/architecture/diagrams/model.c4` — the two coordinated edge edits (overclaim caveat + "isolated"→collision reconcile)
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md` — one-line create-time-render pointer
- `knowledge-base/project/specs/feat-one-shot-6616-host-name-telemetry-mislabel/session-state.md` — Phase 0 query output (diagnosis record)

**Explicitly NOT edited:** `vector.toml`, `soleur-host-bootstrap.sh`, `inngest-bootstrap.sh`, `server.tf`
— the templating is already correct (#6396); touching it would be a no-op change that risks the AC22
lockstep guard. **Cut from the pre-review draft:** the standalone `scripts/hostname-mislabel-alarm.sh` +
`.test.sh`, `.github/workflows/scheduled-hostname-mislabel.yml`, and `sentry_cron_monitor.scheduled_hostname_mislabel`
(born-firing + redundant with the follow-through — see Enhancement Summary #2; dissent recorded).

## Open Code-Review Overlap

None. (Checked all planned paths against 61 open `code-review` issues via `jq --arg path … contains`; zero matches.)

## Acceptance Criteria

### Pre-merge (PR)
1. Phase 0 query output is recorded in `session-state.md`; if the query was runnable, its verdict matches
   the identity rule (mislabel confirmed via a non-`soleur-inngest-server-prd` emitter, OR premise-stale
   with schema-liveness present). If creds were unavailable in-session, the record says so and defers live
   confirmation to the first prod sweeper run.
2. `model.c4` edited: the `hetzner -> betterstack` edge carries the create-time-drift caveat AND the
   `inngest -> betterstack` edge no longer calls source 2457081 "isolated" unqualified. `c4-code-syntax.test.ts`
   + `c4-render.test.ts` green. (Grep the caveat via a punctuation-free content anchor, `cq-assert-anchor-not-bare-token`.)
3. ADR-100 contains the one-line create-time-render pointer.
4. Learning file exists under `knowledge-base/project/learnings/`; every `knowledge-base/` path it cites
   resolves (`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' | xargs -I{} test -f {}`).
5. `scripts/followthroughs/hostname-mislabel-web1-6616.sh` exists and: keys PASS on the **identity**
   (`soleur-inngest-prd` only by `soleur-inngest-server-prd`, pinned from `inngest.tf`); exits **TRANSIENT**
   (not PASS) on creds-unset/query-fault AND on a missing schema-liveness marker (no `soleur-inngest-server-prd`
   row); exits FAIL while a web host still emits the label. Assert each branch with a synthesized fixture
   (`cq-test-fixtures-synthesized-only`), including the "`host` column all-empty → TRANSIENT not PASS" case.
6. #6616 carries the `<!-- soleur:followthrough … -->` directive with a concrete `earliest` date +
   `follow-through` label; `BETTERSTACK_QUERY_*` confirmed already wired in `scheduled-followthrough-sweeper.yml`.
7. `decision-challenges.md` records the detector-cut dissent (architecture/obs-coverage found the standing
   alarm well-designed; cut on born-firing + redundancy grounds) for `ship` to file as `action-required`.
8. PR body uses **`Ref #6616`**, not `Closes` — the physical relabel is deferred; #6616 closes via the
   follow-through PASS after web-1 recreate.

### Post-merge (automated)
9. First `scheduled-followthrough-sweeper.yml` run at/after `earliest` executes
   `hostname-mislabel-web1-6616.sh` and reaches FAIL (collision present, expected) or TRANSIENT — never a
   false PASS. Confirm via `gh run list` + the sweep's issue comment. (No new Sentry monitor to verify — the
   check rides the sweeper's existing Sentry cron self-liveness.)

## Domain Review

**Domains relevant:** Engineering (infra / observability).

### Engineering (CTO / platform-strategist)
**Status:** reviewed via the deepen-plan panel (architecture-strategist: no P0/P1; create-time-drift framing
and deferral verified sound; all infra citations confirmed).
**Assessment:** Pure infra/observability, no UI, no data-model change. The decision to defer the physical
relabel (immutable-redeploy blocked) and ship diagnosis + record-correction + armed closure honors
`hr-prod-host-config-change-immutable-redeploy`, `hr-no-ssh-fallback-in-runbooks` (AP-002), and ADR-119 §(e).
Precedent-diff (below) grounds the follow-through in the established Better Stack poller pattern.

## Precedent-Diff (Phase 4.4)

The follow-through is a **pattern-bound behavior** with a canonical repo precedent:

| Aspect | Precedent (`betterstack-quota-verdict-5105.sh` + `chardevice-wedge-nonrecurrence-5934.sh`) | This plan's `hostname-mislabel-web1-6616.sh` |
|---|---|---|
| Query | `betterstack-query.sh` raw SQL, `$BS_TABLE`/`$BS_TABLE_S3` archive arm | Same (identity `GROUP BY host_name, host`) |
| Exit contract | `0=PASS(close) / 1=FAIL / *=TRANSIENT` (`sweep-followthroughs.sh`) | Identical |
| Vacuous-pass guard | `#5934`: positive liveness marker before zero-count PASS; TRANSIENT on any fault | Identical (marker = `≥1 soleur-inngest-server-prd` row) |
| Runner | `scheduled-followthrough-sweeper.yml` (Sentry-monitored, `BETTERSTACK_QUERY_*` wired) | Same runner — no new workflow/monitor |

**Scheduled-work pattern check:** the collapsed design introduces **no new scheduled job** — it rides the
existing sweeper. (The cut standalone alarm would have been a GH-Actions cron; that choice was defensible via
the `gate-override: new-scheduled-cron-prefer-inngest` header + the `scheduled-zot-restart-loop.yml` precedent
— a credential-heavy `betterstack-query.sh` + `gh issue` bash pipeline, ADR-033 I7's uncontained class — but
is now moot since the artifact is cut.)

## Infrastructure (IaC)

**No new Terraform.** The collapsed design adds no `sentry_cron_monitor`, no server, no secret, no vendor
account. The follow-through runs under the existing `scheduled-followthrough-sweeper.yml`, whose own liveness
is already a Sentry cron monitor. `BETTERSTACK_QUERY_*` already exist in Doppler `prd_terraform` and are
already wired into the sweeper. Phase 2.8 IaC gate: skip (pure code/docs against already-provisioned surfaces).

## Downtime & Cutover

**Zero-downtime — no trigger fires.** This PR's Files-to-Edit are scripts + docs + C4 + a follow-through
directive; it touches **no** `hcloud_server`/volume/attachment, no DB DDL, no router/tunnel/connector. The
one downtime-class operation in the problem space — the web-1 recreate that physically clears the label — is
**explicitly deferred** and out of this PR's scope; when it eventually runs it is a **blue-green** recreate
(a fresh `-replace` born with the correct per-host label, drain, cut over, retire the old) per the ADR-068
§(c) / ADR-119 host-replaceability work, never an in-place reboot of the sole serving host.

## Network-Outage Deep-Dive

**N/A.** `SSH` appears in this plan only as a **forbidden remediation path** (`hr-no-ssh-fallback-in-runbooks`);
there is no connectivity symptom, no firewall/DNS/TLS/proxy layer question, and no `terraform apply` on an
SSH-provisioner resource. The keyword-trigger is a false positive; no L3→L7 checklist applies.

## Observability

```yaml
liveness_signal:
  what: scheduled-followthrough-sweeper runs hostname-mislabel-web1-6616.sh at/after earliest and check-ins to Sentry
  cadence: sweeper daily; the follow-through evaluates once earliest passes
  alert_target: the sweeper's existing Sentry cron monitor (a dark sweeper pages)
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml + the #6616 followthrough directive
error_reporting:
  destination: sweeper Sentry check-in (ERRORED on TRANSIENT); FAIL/PASS posted as a comment on #6616
  fail_loud: true  # TRANSIENT on any creds/query/schema-liveness fault — never a false PASS/close (#5934)
failure_modes:
  - mode: web host wearing the dedicated node's host_name (the #6616 collision)
    detection: hostname-mislabel-web1-6616.sh identity check — soleur-inngest-prd emitted by any host != soleur-inngest-server-prd (in-source telemetry, read-only)
    alert_route: FAIL comment on #6616 (leaves it open); resolution auto-closes on PASS post-recreate
  - mode: source 2457081 / the dedicated node goes dark (would vacuously read no collision)
    detection: positive schema-liveness marker required (>=1 soleur-inngest-server-prd row) before any PASS
    alert_route: TRANSIENT — sweeper ERRORED Sentry check-in, no false close
  - mode: the sweeper itself goes dark
    detection: missed sweeper Sentry cron check-in
    alert_route: Sentry issue-alert (no-SSH paging path)
logs:
  where: GitHub Actions sweeper run logs + the #6616 issue comments
  retention: GH Actions default; Better Stack source 2457081 (queried read-only, not written)
discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- scripts/followthroughs/hostname-mislabel-web1-6616.sh; echo exit=$?"
  expected_output: "exit=1 (FAIL, collision present) while web-1 carries the stale label; exit=0 (PASS) after web-1 recreate; read-only, NO ssh, NO gh mutation"
```

### Affected-surface note (2.9.2)
web-1's Vector unit is a blind surface (no SSH). No **new** in-surface probe is needed: web-1 already ships
both discriminating fields — `host` (auto OS identity, ground truth) and `host_name` (the mislabeled literal)
— into source 2457081, so the single identity query discriminates all four hypotheses (H1/H2/H3/H4) from one
event stream, and the schema-liveness marker guards against the empty-`host` false-GREEN.

## Architecture Decision (ADR/C4)

**Detection fires:** a new cross-cutting invariant every telemetry consumer must honor — "`host_name` in
source 2457081 is a create-time render, not a runtime-guaranteed 1:1 discriminator; treat
`host_name=soleur-inngest-prd` as suspect until every emitting host is post-#6396-born."

### ADR
- **No new ADR.** This is remediation *within* ADR-100/#6396/ADR-119 — the same disposition the #6425/#6594
  connector-drift took (a C4 caveat, not a new ADR). Add a **one-line pointer/amendment to ADR-100** (the
  decision that introduced the per-host `host_name` discriminator) so the create-time-render constraint is
  discoverable from the decision record, not only the C4 prose + learning.

### C4 views
- **Edit `model.c4` directly** (workflow-committed): two coordinated edge edits (overclaim caveat on
  `hetzner -> betterstack`; "isolated"→collision reconcile on `inngest -> betterstack`). **C4 completeness
  enumeration** (all three `.c4` files read): external human actors — none new (operator/founder already
  modeled, they *read* telemetry); external systems/vendors — **Better Stack** already modeled (description
  correction, not a new system); containers/data stores — `hetzner` web hosts + `inngest` node already
  modeled; access relationships — the `hetzner -> betterstack` / `inngest -> betterstack` edges already exist,
  only descriptions change. **No new element/tag/`view include`** → `views.c4` unchanged. Asserted against
  this enumeration, not a bare grep.

### Sequencing
- The C4 correction + ADR pointer are true **now** (web-1 is mislabeled now) and ship in this PR. The
  "collision resolved" state is gated on the deferred web-1 recreate (the follow-through auto-closes #6616).

## Test Scenarios
- Follow-through unit behavior: synthesized ClickHouse-JSON fixtures for PASS (identity holds + marker present),
  FAIL (a web host emits the label), TRANSIENT (creds-unset), TRANSIENT (marker absent), TRANSIENT
  (`host` column all-empty → no vacuous PASS).
- C4: `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- Learning: `knowledge-base/` citation-resolution grep.

## Sharp Edges
- **The `## User-Brand Impact` section must be non-placeholder** — filled above (threshold `aggregate pattern`);
  an empty/`TBD` section fails `deepen-plan` Phase 4.6.
- **Do not attempt to fix web-1's running config.** No SSH (AP-002); no `web-1-recreate` dispatch target; recreate
  blocked (cx33 unorderable, ADR-119). Any phase that "just re-runs the bootstrap" is wrong — the skip-guard
  refuses while the inngest-owned unit exists. The relabel rides a future fresh `-replace`.
- **Do not touch the templating** (`vector.toml` / `server.tf` per-host `host_name` / bootstrap `sed`). Already
  correct (#6396); a no-op change risks the AC22 lockstep guard.
- **Identity, not cardinality.** Key PASS on "`soleur-inngest-prd` emitted only by `soleur-inngest-server-prd`"
  (pinned from `inngest.tf`), with a positive schema-liveness marker. The dedicated node has `host ≠ host_name`
  **by design** (`host=soleur-inngest-server-prd`, `host_name=soleur-inngest-prd`), so a naive `host==host_name`
  check false-fires on it, and a bare `≥2`-cardinality check both misses the single-emitter mislabel (H4) and
  goes vacuously GREEN if the `host` field ever empties.
- **`Ref #6616`, not `Closes`** — closure is the follow-through PASS after web-1 recreate, not merge.
- **PR-body record** routes through `ship` (sole PR-body author) via the durable `specs/…` artifact +
  `decision-challenges.md`; `work`/`plan` cannot author the PR body. The deferred relabel + the detector-cut
  dissent surface as `action-required` issues for the non-technical operator (PR bodies are not operator-visible).

## Non-Goals / Deferred
- Physical relabel of web-1 → deferred to the next web-1 recreate (GA blue-green / ADR-119 host-replaceability).
  Enrolled as the #6616 follow-through (Phase 2). No redundant tracking issue.
- Changing the per-host templating (already shipped in #6396).
- A standing **paging** cross-label detector for novel (non-web-1) collisions → YAGNI; the bug class is closed
  for fresh hosts (#6396/#6344). Build if/when such a collision is observed. (Dissent recorded in `decision-challenges.md`.)
- web-2 (dark, being retired per the 2026-07-16 web-2-retire brainstorm) — out of scope; emits nothing to mislabel.
