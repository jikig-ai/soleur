---
title: "feat(observability): host logger -t stderr → Better Stack queryability"
issue: 5499
branch: feat-one-shot-5499-host-stderr-betterstack
date: 2026-06-18
type: feat
lane: cross-domain
status: draft
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan adds NO new infra resource. It edits the existing
     version-pinned vector.toml content (delivered by inngest-bootstrap.sh via cloud-init /
     OCI _files, applied by apply-web-platform-infra.yml on merge). No new server, secret,
     vendor, or runtime process. References to remote-shell / service-restart in the prose are
     EXPLICIT WARNINGS to route through IaC, not prescribed manual steps. -->

# feat(observability): host-script `logger -t` stderr → Better Stack queryable 📡

> Ref #5499 (closed post-deploy via `gh issue close`, NOT `Closes` — see AC7). Deferred from
> #5495 brainstorm (2026-06-17); sibling #5492 (now closed) routed the specific `op=enumerate`
> host stderr to GitHub Actions run logs. This is the general infra-queryability fix, not a one-off.

## Enhancement Summary

**Deepened on:** 2026-06-18
**Sections enhanced:** Apply path, AC7/AC8/AC9, Risks, Sharp Edges, tasks.md Phase 0.3 + Phase 5
**Agents used:** verify-the-negative (sonnet, 8/8 structural claims confirmed),
architecture-strategist (found P0 apply-path error)

### Key Improvements
1. **P0 corrected — apply path was materially wrong.** `vector.toml` is baked into the
   `soleur-inngest-bootstrap` OCI image (built only on `vinngest-v*` tag push), delivered via
   the `deploy inngest` webhook — NOT `apply-web-platform-infra.yml` (terraform-only; a
   vector.toml-only change is a terraform no-op). The original `/work`-grep on the apply
   workflow's path filter was a false-confidence trap (path matches, workflow doesn't deliver).
2. **AC7 `Closes` → `Ref`.** Fix is live only after the post-merge OCI-rebuild + deploy;
   `Closes` would false-resolve #5499 at merge. Actual closure is post-deploy `gh issue close`.
3. **AC8 verification anchored on the installed-config sha** (`vector config installed: sha256=`
   from inngest-bootstrap.sh:430, read via cat-deploy-state.sh — no SSH), not a terraform run.
4. **Per-event row-count measurement** added as a /work step (Risk + tasks 4.5) — #5110 showed
   an unmeasured estimate can be 2.3x off.

### Verified-against-codebase (verify-the-negative, all confirmed)
- 7 `logger -t` scripts + exact tags; `cron-egress-*`/`container-restart-monitor` correctly
  excluded (echo/Sentry, not journald); `system_journald` PRIORITY 0-2 drops these;
  `logger` defaults to PRIORITY 5 (only ci-deploy.sh:665 is PRIORITY 4);
  `pii_scrub_drop_userdata.inputs` is the sole chain entry; validate-vector-config.yml runs the
  fixture on PR; include_matches is exact-value equality.

## Overview

Seven host-script bash files under `apps/web-platform/infra/` log operational events to
the systemd journal via `logger -t "$LOG_TAG"`. Those lines are invisible in Better Stack
today: Vector's `[sources.system_journald]` ships only `PRIORITY ["0","1","2"]` (CRIT+),
and every one of these `logger -t` lines lands at **PRIORITY 5 (user.notice)** — the
`logger` default — except one `ci-deploy.sh:665` line at PRIORITY 4 (user.warning). All of
them are dropped at the source.

The fix: add a **dedicated, narrowly-scoped fourth journald source**
`[sources.host_scripts_journald]` matching the exact `SYSLOG_IDENTIFIER` tag of each of the
7 scripts (systemd `include_matches` is exact-value equality, set by `logger -t <tag>` →
`SYSLOG_IDENTIFIER=<tag>`), wired through the existing PII redaction chain. We deliberately
do **not** widen the `system_journald` PRIORITY filter (that would pull every NOTICE-level
host daemon line — sshd, cron, systemd — into the logs quota).

### Why a dedicated source, not PRIORITY widening (the load-bearing decision)

| Option | Quota blast-radius | Verdict |
|---|---|---|
| **A. Add `system_journald` PRIORITY 3,4,5** | Ships ALL host NOTICE+ lines (login session open/close, cron job notices, systemd unit start/stop, fail2ban) — unbounded, continuous | ❌ Rejected — violates the 2026-06-10 quota-discipline learning |
| **B. Dedicated source by 7 exact `SYSLOG_IDENTIFIER` tags** | Ships ONLY the 7 known host-script tags; event-driven (deploy/webhook), not continuous; ~tens of lines/event | ✅ Chosen — narrowly scoped, quota-bounded |

The issue description explicitly asks us to "prefer a narrowly-scoped host-script source over
a broad PRIORITY filter widening." Option B is that source.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body) | Codebase reality | Plan response |
|---|---|---|
| "stderr logged at **WARN** priority" | Reality: `logger -t` defaults to `user.notice` = **PRIORITY 5**. Only `ci-deploy.sh:665` uses `-p user.warning` (PRIORITY 4). | The new source uses **no PRIORITY filter** (SYSLOG_IDENTIFIER scoping is already narrow), so it captures PRIORITY 4 AND 5 host-script lines uniformly. Plan corrects the "WARN" framing to "NOTICE/WARN (PRIORITY 4-5)". |
| "`system_journald` ships only PRIORITY 0–2 (CRIT+)" | ✅ Confirmed — `vector.toml:40`. | No change to `system_journald`. |
| "app-container source is WARN+ but container-only" | ✅ Confirmed — `app_container_journald` matches `CONTAINER_NAME=["soleur-web-platform"]` only (vector.toml:65-69). Host scripts run under `webhook.service` / cron, not in the container. | Host scripts need their own source. |
| Mechanism candidate set: "lower host-journald PRIORITY filter OR add a dedicated source" | Both are technically feasible. | Choose **dedicated source** (Option B above) for quota reasons. |
| Quota headroom (2026-06-10 learning + #5110 verdict) | Current Better Stack volume ~19.9k rows/day, 20% under the 25k/day threshold (vector.toml:101-110). Host-metrics already trimmed. | 7 event-driven sources add tens-to-low-hundreds of rows/day → well within headroom. Document the projection (Quota section). |
| `logger -t` inventory | 7 scripts use `logger -t`: `infra-config-apply`, `infra-config-install`, `ci-deploy`, `inngest-enumerate-reminders`, `inngest-rearm-reminders`, `inngest-wiped-volume-verify`, `inngest-inventory`. The `cron-egress-*` + `container-restart-monitor` scripts set `LOG_TAG` but log via `echo` (stdout) + direct Sentry, NOT `logger -t` journald — out of scope. | Source matches exactly the 7 `SYSLOG_IDENTIFIER` tags. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is an
operator-only observability surface. The failure mode is a *silent miss*: a host-script
failure (e.g. a failed `inngest-rearm-reminders` re-arm, or a failed `infra-config-apply`
file write) stays invisible in Better Stack, forcing remote-shell diagnosis the no-SSH
observability mandate exists to prevent. No user data path is touched.

**If this leaks, the user's data is exposed via:** the new source carries the *same* PII
risk as every other journald source — host-script stderr could in theory contain a userId
or token in an interpolated log line. This is mitigated by wiring the new source through the
**existing** 3-stage redaction chain (`pii_scrub_drop_userdata → pii_scrub_structured →
pii_scrub_string`) — host-script lines are non-JSON, so they hit `pii_scrub_string` (the
regex backstop: userid=, email, Bearer/Basic, OAuth params, control chars), length-bounded
to 10000 chars per `2026-04-17-pii-regex-scrubber-three-invariants`.

**Brand-survival threshold:** none — operator-only observability config; no user-facing
artifact, no per-user data path. (The diff touches `apps/web-platform/infra/vector.toml`, an
infra surface; per preflight Check 6, threshold `none` is recorded with this reason.)

## Implementation Phases

### Phase 1 — Add the dedicated host-script journald source

**File: `apps/web-platform/infra/vector.toml`** (edit)

Add a new `[sources.host_scripts_journald]` block after Source 3 (`app_container_journald`,
ends ~line 69), before the existing `app_container_warn_filter`. Shape:

```toml
# ---------------- Source 5: host-script journald (logger -t tags) (#5499) ----------------
# Seven bash scripts under apps/web-platform/infra/ log operational events to the
# journal via `logger -t "$LOG_TAG"`. They run under webhook.service / cron — NOT
# inside inngest-server.service (Source 1) nor the app container (Source 3) — and
# their PRIORITY 5 (user.notice; ci-deploy.sh:665 is PRIORITY 4 user.warning) lines
# are dropped by Source 2's PRIORITY 0-2 (CRIT+) filter. This source captures them
# by EXACT SYSLOG_IDENTIFIER match (`logger -t <tag>` sets SYSLOG_IDENTIFIER=<tag>;
# systemd include_matches is sd_journal_add_match exact-value equality, NOT prefix).
#
# NO PRIORITY filter (deliberate — differs from Sources 1/2): these lines are
# PRIORITY 4-5, which Source 2 drops; SYSLOG_IDENTIFIER scoping to 7 known tags is
# already the narrowing. We do NOT widen system_journald's PRIORITY filter — that
# would ship every host NOTICE+ line (sshd, cron, systemd units) and blow the
# Better Stack logs quota (per 2026-06-10 quota-diagnosis learning + #5110 verdict).
#
# Quota (#5110 reality check): all 7 are event-driven (deploy/webhook/cron-fire),
# not continuous request-per-line firehoses — projected tens-to-low-hundreds of
# rows/day, well within the current ~20% headroom under the 25k/day threshold.
# Adding a tag here is a quota decision; keep the list to genuinely-diagnostic
# host scripts. A parity fixture in vector-pii-scrub.test.sh pins the exact-tag set.
[sources.host_scripts_journald]
type = "journald"
include_matches.SYSLOG_IDENTIFIER = [
  "infra-config-apply",
  "infra-config-install",
  "ci-deploy",
  "inngest-enumerate-reminders",
  "inngest-rearm-reminders",
  "inngest-wiped-volume-verify",
  "inngest-inventory",
]
journal_directory = "/var/log/journal"
batch_size = 16
```

> **Verify tag set at /work time** before freezing: `grep -rhoP 'LOG_TAG=\K"?[a-z0-9-]+' apps/web-platform/infra/*.sh | tr -d '"' | sort -u` AND cross-check against `grep -l 'logger -t' apps/web-platform/infra/*.sh` (only scripts that actually call `logger -t` belong in the list — `cron-egress-*` + `container-restart-monitor` set LOG_TAG but log via echo/Sentry).

### Phase 2 — Wire the new source through the redaction chain

**File: `apps/web-platform/infra/vector.toml`** (edit)

Add `"host_scripts_journald"` to the `inputs` of `pii_scrub_drop_userdata` (currently
`vector.toml:141`):

```toml
inputs = ["inngest_journald", "system_journald", "app_container_warn_filter", "host_scripts_journald"]
```

This is the ONLY input edit needed — the rest of the chain
(`pii_scrub_structured → pii_scrub_string → tag_journald → betterstack` sink) flows through
unchanged. The `tag_journald` transform (vector.toml:275-286) already sets
`source_kind = "journald"` for any line lacking `CONTAINER_NAME` (host-script lines have no
CONTAINER_NAME), so these lines are correctly tagged `source_kind=journald` for Better Stack
filtering.

> **ADR-029 boundary contract:** wiring through `pii_scrub_drop_userdata` (not direct to the
> sink) is mandatory — every source crossing the Vector→Better Stack boundary must traverse
> the 3-stage redaction. Mirror the `#4773` comment pattern that documents why
> `app_container_warn_filter` is wired here rather than direct.

### Phase 3 — Pin the exact-tag-set + no-priority-filter parity fixture

**File: `apps/web-platform/test/infra/vector-pii-scrub.test.sh`** (edit)

Add a **config-assertion** test case (grep-based, like the existing canary-exclusion parity
fixture referenced at vector.toml:57) — NOT a VRL fixture (the new source has no VRL of its
own; it reuses the shared chain). Assert:

1. `[sources.host_scripts_journald]` exists with `type = "journald"`.
2. Its `include_matches.SYSLOG_IDENTIFIER` array contains exactly the 7 tags AND every tag
   in the array corresponds to a script that actually calls `logger -t` (derive the expected
   set from `apps/web-platform/infra/*.sh` via the grep in Phase 1, so the test fails if a
   script adds/removes a `logger -t` tag without updating the source — a drift guard).
3. The block has **no** `include_matches.PRIORITY` line (regression guard: prevents a future
   edit from silently filtering out the PRIORITY 5 lines this fix exists to capture).
4. `host_scripts_journald` appears in `pii_scrub_drop_userdata`'s `inputs` (redaction-boundary
   guard — a new source bypassing redaction is a GDPR regression).

> Match the existing test's bash style and run via the same harness. No `vector` binary
> invocation needed for these (pure config grep), so they run even when `VECTOR_BIN` is
> absent — but keep them inside the existing file so `validate-vector-config.yml` picks them
> up on the `apps/web-platform/test/infra/**` path filter.

## Infrastructure (IaC)

### Terraform changes
No `.tf` change. `vector.toml` is version-pinned content delivered to `/etc/vector/vector.toml`
by `inngest-bootstrap.sh` (embedded at OCI build time OR via cloud-init `write_files`); the
version/sha pin lives in `vector.tf` and is unchanged. No new providers, variables, or secrets.
The new source reads the **existing** `/var/log/journal` and ships through the **existing**
`[sinks.betterstack]` (no new `BETTERSTACK_*` token).

### Apply path
**(b) OCI-image rebuild + `deploy inngest` (NOT terraform apply).** [Corrected 2026-06-18 —
deepen-plan P0.] `vector.toml` is **baked into the `soleur-inngest-bootstrap` OCI image at
build time** (`build-inngest-bootstrap-image.yml:164` `cp … vector.toml "$BUILD_DIR/"` →
`:183` `COPY vector.toml /vector.toml`; entrypoint copies it to `/tmp/vector.toml`). It is
NOT in the `infra-config-apply.sh` `FILE_MAP` and is NOT applied by terraform. Crucially:

- **`apply-web-platform-infra.yml` does NOT deliver `vector.toml`.** Its path filter is
  `apps/web-platform/infra/**` (which *does* match `vector.toml`), but the workflow only runs
  `terraform plan/apply` — with no `.tf` change this PR is a terraform no-op. The `vector.toml`
  bytes never move. (This is why the original `/work`-grep `grep -A6 'paths:' apply-web-platform-infra.yml`
  is a **false-confidence trap**: the path matches, but the matching workflow does the wrong thing.)
- The build workflow fires **only on a `vinngest-vX.Y.Z` git-tag push**
  (`build-inngest-bootstrap-image.yml` `on: push: tags: vinngest-v*`). The published GHCR image
  tag is the plain `vX.Y.Z` (the `vinngest-` git-tag prefix is stripped at publish — see
  `inngest-server.md:338-339`).
- The image reaches the host via the no-SSH deploy webhook:
  `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vX.Y.Z` →
  `ci-deploy.sh case "inngest")` → `inngest-bootstrap.sh:421-423` installs `/tmp/vector.toml`
  → `/etc/vector/vector.toml`, restarts vector, and logs
  `vector config installed: sha256=<hash>` (inngest-bootstrap.sh:430).

**Therefore the apply is a post-merge release step, not an automatic merge-time apply.** The
plan's `### Post-merge (operator)` AC8/AC9 sequence (below) reflects this: cut a new
`vinngest-vX.Y.Z` tag (current bootstrap image is ~`v1.1.14`; bump per operator choice), let
the build workflow publish the image, then fire the `deploy inngest …` webhook via the release
pipeline. This is the same cadence documented in
`knowledge-base/engineering/operations/runbooks/inngest-server.md:602-605`.

> **No SSH.** The deploy is routed through the release pipeline / deploy webhook
> (`inngest-server.md:336`), NOT an interactive remote-shell. The tag push + webhook fire are
> the only operator actions; both are CLI/automatable (`git tag … && git push`; the deploy
> webhook via the documented pipeline).

### Distinctness / drift safeguards
`dev != prd`: vector ships only on the prd Hetzner VM (no dev vector instance). No
`lifecycle.ignore_changes` needed (no `.tf` resource changes). The Phase-3 drift-guard test
keeps the source's tag list in sync with the scripts' actual `logger -t` tags.

### Vendor-tier reality check
Better Stack free tier (3 GB/mo logs). Current usage ~19.9k rows/day (20% under the 25k/day
self-imposed threshold per #5110). The 7 event-driven host scripts add a small bounded volume
(no continuous firehose). No tier gate needed; the ledger upgrade trigger ("first paying
customer") is unchanged.

## Observability

```yaml
liveness_signal:
  what: host-script logger -t lines visible in Better Stack via source_kind=journald
  cadence: on host-script execution (deploy/webhook/cron-fire — event-driven)
  alert_target: none (this IS the observability surface; no meta-alert)
  configured_in: apps/web-platform/infra/vector.toml [sources.host_scripts_journald]
error_reporting:
  destination: Better Stack Logs (ClickHouse warehouse) via [sinks.betterstack]
  fail_loud: vector's own internal_metrics (vector_console sink to journald) already
             surfaces sink failures; cat-deploy-state.sh vector_journal_tail spots crashes
failure_modes:
  - mode: a new host script adds a logger -t tag not in the source list
    detection: Phase-3 drift-guard test (grep logger -t tags vs source array) fails in CI
    alert_route: validate-vector-config.yml red check on PR
  - mode: a future edit adds a PRIORITY filter that drops the PRIORITY 5 lines
    detection: Phase-3 no-PRIORITY-filter regression test fails in CI
    alert_route: validate-vector-config.yml red check on PR
  - mode: new source bypasses pii_scrub redaction (GDPR regression)
    detection: Phase-3 redaction-boundary test (source in pii_scrub_drop_userdata inputs)
    alert_route: validate-vector-config.yml red check on PR
logs:
  where: Better Stack source soleur-inngest-vector-prd (id 2457081), table
         t520508_soleur_inngest_vector_prd_3_logs
  retention: 3 days (Better Stack free tier)
discoverability_test:
  command: |
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh
      --since 24h --grep inngest-rearm-reminders --grep infra-config-apply --limit 20
  expected_output: JSONEachRow rows whose `raw` contains a host-script SYSLOG_IDENTIFIER
                   tag (e.g. inngest-rearm-reminders / infra-config-apply), proving the
                   logger -t lines now reach Better Stack. (Post-apply; pre-apply returns
                   zero rows — that's the bug this fixes.)
```

## Architecture Decision (ADR/C4)

No ADR. This is an observability-config change within the existing Vector→Better Stack
substrate (ADR-029 boundary already governs the PII redaction the new source reuses). It
does not move a tenancy boundary, add a substrate, or change a trust/resolver boundary.

**C4 completeness check (all three model files read):** A new *internal* journald source is
a config detail of the already-modeled Vector→Better Stack edge — no new external human actor
(no new correspondent/sender), no new external system/vendor (Better Stack already modeled as
the log sink), no new container/data-store (journald + Better Stack already present), and no
new actor↔surface access relationship (operator reads logs via the already-modeled query
path). The host scripts and Vector are already inside the platform boundary. → **No C4
impact**, verified against `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`
for: external actors (none added), external systems (Better Stack already present), data
stores (journald/Better Stack already present), access relationships (operator→logs
unchanged).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `apps/web-platform/infra/vector.toml` contains `[sources.host_scripts_journald]`
      with `type = "journald"` and `include_matches.SYSLOG_IDENTIFIER` listing exactly the 7
      tags. Verify: `grep -A12 'sources.host_scripts_journald' apps/web-platform/infra/vector.toml`.
- [ ] **AC2** The source block has NO `include_matches.PRIORITY` line. Verify:
      `awk '/\[sources.host_scripts_journald\]/{f=1} f&&/^\[/&&!/host_scripts_journald/{f=0} f&&/PRIORITY/{print "FAIL"}' apps/web-platform/infra/vector.toml` returns empty.
- [ ] **AC3** The tag set equals the set of scripts that actually call `logger -t`. Verify:
      the Phase-3 drift-guard test passes — array tags == `grep -l 'logger -t' apps/web-platform/infra/*.sh`-derived tag set.
- [ ] **AC4** `host_scripts_journald` is in `pii_scrub_drop_userdata`'s `inputs`. Verify:
      the input line at ~141 contains `host_scripts_journald`.
- [ ] **AC5** `vector validate apps/web-platform/infra/vector.toml` passes (config compiles —
      run in `validate-vector-config.yml` if a validate step exists; else local with VECTOR_BIN).
- [ ] **AC6** `vector-pii-scrub.test.sh` (extended with Phase-3 cases) passes green in
      `validate-vector-config.yml` on the PR.
- [ ] **AC7** PR body uses `Ref #5499` (NOT `Closes #5499`). [Corrected 2026-06-18 — deepen-plan.]
      The fix is only live AFTER the post-merge OCI-rebuild + `deploy inngest` (AC8) — `Closes`
      would auto-close at merge, before the config reaches the host, producing a false-resolved
      state. Actual closure is the post-merge `gh issue close 5499` once AC8's sha matches +
      AC9's discoverability query returns rows. (Matches the ops-remediation `Ref #N` pattern —
      the apply is a post-merge release step, not a merge-time apply.)

### Post-merge (operator / automated)

- [ ] **AC8** `vector.toml` change reaches the running host via the **OCI-image-rebuild +
      deploy-inngest** path (NOT terraform). Steps: (i) cut + push a `vinngest-vX.Y.Z` tag
      (bump from current ~`v1.1.14`); (ii) confirm `build-inngest-bootstrap-image.yml` publishes
      the `vX.Y.Z` GHCR image; (iii) fire `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vX.Y.Z`
      via the release pipeline / deploy webhook (no SSH, per inngest-server.md:336). **Verify
      (no remote-shell):** `cat-deploy-state.sh` journal tail shows
      `vector config installed: sha256=<X>` where `<X>` == `sha256sum apps/web-platform/infra/vector.toml`
      of the merged file. A matching sha proves the new config reached `/etc/vector/vector.toml`;
      a stale sha proves it did NOT (do not treat a terraform-apply run as evidence — it never
      touches vector.toml).
- [ ] **AC9** Discoverability (run ONLY after AC8's sha matches): the §Observability
      `discoverability_test` command returns ≥1 row containing a host-script tag, fired when a
      host-script `logger -t` line next emits (e.g. trigger `inngest-inventory` via the
      allowlisted `/soleur:trigger-cron` path, then query). If zero rows persist after a
      confirmed-sha deploy, re-check the redaction-chain wiring (AC4) — the source matched but
      the line was dropped before the sink.

## Domain Review

**Domains relevant:** Engineering (infra/observability), Legal/Compliance (PII boundary).

### Engineering
**Status:** reviewed
**Assessment:** Pure infra-config change, single new journald source + one input edit + a
config-assertion test. Reuses the existing redaction chain and sink. No new runtime process,
secret, or vendor. Risk is low and bounded by CI (vector validate + fixture).

### Legal / Compliance
**Status:** reviewed
**Assessment:** The new source ships host-script stderr — potentially containing
interpolated identifiers — across the Vector→Better Stack (EU, eu-fsn-3) boundary. Mitigation:
wire through the existing ADR-029 3-stage redaction (`pii_scrub_string` regex backstop covers
non-JSON host lines: userid=, email, Bearer/Basic, OAuth params, length-bound 10000). This is
the SAME boundary contract already in force for `system_journald`/`inngest_journald`; no new
Art. 30 processing activity (same purpose, same sink, same retention, same transfer record
#4293 FR3). Phase-3 AC4 pins the redaction-boundary wiring.

### Product/UX Gate
Not relevant — operator-only observability config, no UI surface (no path under
`components/**`, `app/**/page.tsx`, etc.).

## Test Scenarios

1. **Config compiles** — `vector validate` accepts the new source (AC5).
2. **Exact-tag match** — a journal line with `SYSLOG_IDENTIFIER=inngest-rearm-reminders`
   matches; a near-miss like `inngest-rearm-reminders-canary` does NOT (exact-value semantics,
   same as the canary-exclusion parity at vector.toml:57). (Asserted structurally via the tag
   list; behavioral match is a Vector/systemd invariant, not re-tested here.)
3. **Drift guard** — adding a `logger -t "new-tag"` to an infra script without updating the
   source array fails the Phase-3 test (AC3).
4. **No-PRIORITY-filter regression** — adding `include_matches.PRIORITY` to the new source
   fails the Phase-3 test (AC2).
5. **Redaction boundary** — removing `host_scripts_journald` from `pii_scrub_drop_userdata`
   inputs fails the Phase-3 test (AC4).
6. **End-to-end discoverability** (post-apply) — a real host-script `logger -t` line is
   queryable via `scripts/betterstack-query.sh --grep <tag>` (AC9).

## Risks & Mitigations

- **Quota creep if the tag list grows unbounded.** Mitigation: the source comment + Phase-3
  test make adding a tag an explicit, reviewed quota decision; the 7 scripts are
  event-driven (low volume). Re-measure with `scripts/betterstack-query.sh` grouped by
  `source_kind` if a quota warning recurs (per 2026-06-10 learning).
- **Apply path does NOT auto-fire on a vector.toml-only merge.** [deepen-plan P0.] vector.toml
  is baked into the `soleur-inngest-bootstrap` OCI image; the merge-time terraform apply is a
  no-op for it. Mitigation: §Apply path documents the OCI-rebuild + `deploy inngest` post-merge
  sequence; AC8 verifies via the installed-config sha (not a terraform run); AC7 uses `Ref`
  not `Closes` so the issue isn't false-closed before the deploy.
- **Per-event line count is estimated, not measured.** `ci-deploy` / `infra-config-apply` can
  emit many `logger -t` lines per deploy (one journal entry = one Better Stack row). The ~5k/day
  headroom absorbs this, but #5110 showed an unmeasured estimate can be 2.3x off. Mitigation:
  at /work, replace the estimate with a count — `journalctl -t ci-deploy -t infra-config-apply
  --since '7 days ago' | wc -l` / 7 — and confirm < ~1k rows/day added. (No remote-shell: this
  is a post-apply diagnostic; alternatively project from the deploy frequency × lines-per-run.)
- **PII leak via host-script stderr.** Mitigation: existing 3-stage redaction, AC4 boundary
  guard, length-bound regex.
- **PRIORITY-5 capture surprise.** The issue framed these as "WARN" but they're NOTICE
  (PRIORITY 5). The no-PRIORITY-filter design captures both 4 and 5 — confirmed correct by
  the Research Reconciliation table; no behavioral surprise.

## Open Code-Review Overlap

None — no open `code-review`-labeled issue touches `apps/web-platform/infra/vector.toml` or
`apps/web-platform/test/infra/vector-pii-scrub.test.sh` (verified at plan time).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold `none` with
  reason recorded.)
- `logger -t` defaults to **PRIORITY 5 (user.notice)**, NOT WARN — do not "correct" the source
  to a PRIORITY 0-4 filter thinking it's WARN; that would drop every line. The
  no-PRIORITY-filter design + AC2 regression guard exist precisely to prevent this.
- systemd `include_matches.SYSLOG_IDENTIFIER` is **exact-value** equality, not prefix/regex —
  a tag typo silently matches nothing (no error). The Phase-3 drift guard catches mismatch
  against the scripts' actual tags.
- `vector.toml` is **baked into the `soleur-inngest-bootstrap` OCI image** (NOT the
  `infra-config-apply.sh` FILE_MAP, NOT terraform). Do not add it to FILE_MAP. The apply trigger
  is a `vinngest-vX.Y.Z` tag push (rebuilds the image) + `deploy inngest …` webhook — NOT
  `apply-web-platform-infra.yml` (terraform-only; a vector.toml-only change is a terraform
  no-op). `grep -A6 'paths:' apply-web-platform-infra.yml` matches `vector.toml` but the matching
  workflow does NOT deliver it — a false-confidence trap. Verify delivery via the installed
  `vector config installed: sha256=` log (inngest-bootstrap.sh:430) through `cat-deploy-state.sh`,
  not a terraform run.
