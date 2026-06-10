---
title: "fix: cut Better Stack log-quota consumption ~90% via Vector host-metrics tuning"
type: fix
date: 2026-06-10
lane: cross-domain
brand_survival_threshold: none
related_issues: ["#4296 (reference only — do NOT close)"]
---

# fix: Cut Better Stack log-quota consumption ~90% via Vector host-metrics tuning

> Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this branch (one-shot pipeline entered at plan).

## Overview

Better Stack emailed an 80%-of-quota warning for org Jikigai on 2026-06-10 (free tier: 3 GB/month logs, 3-day retention + 30 GB metrics). Per-source measurement via `scripts/betterstack-query.sh` showed the `[sources.host_metrics]` block in `apps/web-platform/infra/vector.toml` is >99% of shipped volume: ~100 metric series scraped every 30s across 6 collectors → ~196k aggregated rows/day (~2–3.5 GB/month ingested), while real log signal is ~50 journald WARN+ rows/day (~0.01 GB/month).

**Operator-approved remediation (decision already made — do not re-litigate): keep host metrics, cut volume ~90%, stay on the free tier ($0.00).** The ledger upgrade trigger ("first paying customer") has not fired. Already done outside this PR (2026-06-10, no action needed): leftover "Onboarding • Real-time flights" Better Stack demo source (id 2327782) deleted via Telemetry API.

Two-file change:

1. `apps/web-platform/infra/vector.toml` — `[sources.host_metrics]`: `scrape_interval_secs` 30 → 300 (10× cut; 5-min granularity is sufficient for the CPU/mem/disk diagnosis use case per the file's own design comments), exclude `loop*` (snap loop devices) and `dm-*` (device-mapper) from the disk + filesystem collectors, and fix the stale `# 30s scrape. Each scrape emits ~80-100 metric series` comment.
2. `knowledge-base/operations/expenses.md` — record the quota-warning incident + resolution in the Better Stack row Notes; bump `last_updated` to 2026-06-10.

**Byte-for-byte invariant:** all three journald sources, the `app_container_warn_filter`, the 3-stage PII scrub pipeline (`pii_scrub_drop_userdata` → `pii_scrub_structured` → `pii_scrub_string`), `tag_journald`, `tag_metrics`, and the `betterstack` sink are untouched. `vector-pii-scrub.test.sh` parity fixtures and `.github/workflows/validate-vector-config.yml` must stay green.

Reference issue #4296 (observability consolidation 60-day re-decision) as related context in the PR body — `Ref #4296`, NOT `Closes` (verified OPEN at plan time).

## Premise Validation

All cited artifacts verified against the repo and live state on 2026-06-10:

- **#4296**: `gh issue view 4296` → `OPEN`, title "follow-up: 60-day re-decision of observability consolidation (checkpoint from #4273)", `closedByPullRequestsReferences: []`. Premise holds — reference-only.
- **`apps/web-platform/infra/vector.toml`**: `[sources.host_metrics]` at line 102 with `scrape_interval_secs = 30` and `collectors = ["cpu", "memory", "disk", "filesystem", "load", "network"]` (lines 99–105). Stale comment at lines 100–101. Premise holds.
- **`apps/web-platform/infra/vector.tf`**: pins `vector_version = "0.43.1"` (line 13). Premise holds.
- **`knowledge-base/operations/expenses.md`**: Better Stack free-tier observability row exists at line 22 (`| Better Stack | Better Stack | observability | 0.00 | free-tier | ...`); frontmatter `last_updated: 2026-05-21`. A second, distinct `Better Stack Responder (DEFERRED)` row at line 20 must NOT be touched. Premise holds.
- **Test/CI surfaces**: `apps/web-platform/test/infra/vector-pii-scrub.test.sh` exists (358 lines); `.github/workflows/validate-vector-config.yml` fires on `pull_request` for the `vector.toml` path and runs `vector validate` against the binary parsed from `vector.tf` + the VRL fixture tests + a Better Stack source/cluster disclosure-parity check. Premise holds.
- **`scripts/betterstack-query.sh`**: exists; raw-SQL mode with `$BS_TABLE` substitution; host-metrics rows are identified by `raw LIKE '%"namespace":"host"%'` (the script's own `--raw-only` exclusion predicate at line ~92).
- **No external premises are stale.**

## Research Reconciliation — Spec vs. Codebase

| Claim (feature description) | Reality (verified) | Plan response |
|---|---|---|
| "verify exact syntax against Vector docs for the pinned Vector version" | Vector docs (`vector.dev/docs/reference/configuration/sources/host_metrics/`, fetched 2026-06-10): disk filter is `[sources.<id>.disk.devices]` with `excludes = [...]`; filesystem has three filters (`devices`, `filesystems`, `mountpoints`), each `includes`/`excludes`, glob-matched, default `["*"]` | Use `devices.excludes = ["loop*", "dm-*"]` under `[sources.host_metrics.disk]` and `[sources.host_metrics.filesystem]`. CI's `vector validate` against the pinned 0.43.1 binary is the mechanical schema gate (host_metrics filters predate 0.43; stable API) |
| "run tests locally (test scripts under apps/web-platform/test/infra/)" | Only `vector-pii-scrub.test.sh` lives there; it requires a `vector` binary (none installed locally) + `SENTRY_USERID_PEPPER=fixture-*` + bun/node_modules for TS parity | Phase 3 downloads the pinned 0.43.1 gnu binary to /tmp (exact form copied from `validate-vector-config.yml:73-75`) and runs both `vector validate` and the test script with `VECTOR_BIN` |
| "vector.toml is provisioned to the Hetzner host (inngest-bootstrap.sh / vector.tf / ci-deploy.sh)" | vector.toml is embedded in the **inngest-bootstrap OCI image** built on `vinngest-vX.Y.Z` tag push (`build-inngest-bootstrap-image.yml`); `ci-deploy.sh`'s `inngest` branch extracts `/vector.toml` → `/tmp/vector.toml` → `inngest-bootstrap.sh` installs to `/etc/vector/vector.toml` + restarts `vector.service`. Merging this PR alone does NOT deploy it | Post-merge sequence (§ Infrastructure): tag `vinngest-v1.1.12` on the merge commit → image build → cloud-init pin-bump follow-up (AC6 drift guard) → deploy webhook (operator-acked) → query-based verification |
| "Better Stack dashboard Settings → Usage" as a verification option | Dashboard-eyeball violates `hr-no-dashboard-eyeball-pull-data-yourself` | Verification prescribed as `scripts/betterstack-query.sh` row-count query with a deterministic verdict rule (post-deploy daily host-metrics rows ≤ 25k vs ~196k baseline) |

## Research Insights

- **Deployment chain** (read from source): `apps/web-platform/infra/ci-deploy.sh:784-824` (extracts `/vector.toml` from OCI image, clears `/tmp/vector.toml` first to prevent stale reuse), `apps/web-platform/infra/inngest-bootstrap.sh:344-427` (installs to `/etc/vector/vector.toml`, systemd `vector.service` restart for clean reload), `apps/web-platform/infra/cloud-init.yml:498-514` (fresh-host path; pins image tag `v1.1.11`).
- **Pin drift guard**: `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` AC6 (#4675/#4676) requires cloud-init's pinned image tag == semver-max published `vinngest-v*` git tag. Latest tag today: `vinngest-v1.1.11`. Pushing `vinngest-v1.1.12` therefore REQUIRES a follow-up cloud-init pin bump (precedent: PR #4669). `v1.1.11` appears 4× in `cloud-init.yml` itself (`grep -c "v1.1.11" apps/web-platform/infra/cloud-init.yml` → 4) — sweep all occurrences in the pin-bump commit.
- **Canonical webhook fire** (no-SSH form, per `hr-no-ssh-fallback-in-runbooks`): `.github/workflows/web-platform-release.yml:370-391` — `PAYLOAD='{"command":"deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.1.12"}'`, HMAC-SHA256 over payload with `WEBHOOK_DEPLOY_SECRET`, CF Access headers, POST `https://deploy.soleur.ai/hooks/deploy`, expect HTTP 202; poll `/hooks/deploy-status` (GET signs empty string). Doppler config: `soleur/prd_terraform`. Precedent: `knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md`.
- **Key learning**: `knowledge-base/project/learnings/2026-05-22-vector-vrl-config-gates-and-pii-redaction-pipeline.md` — VRL transforms compile standalone; Vector's TOML loader preprocesses `${...}`/`$$`. Neither is touched by this change (no VRL edits, no `$` in the new keys), but it is why the byte-for-byte invariant on transforms matters: the parity test extracts VRL from `vector.toml` in place.
- **Volume math** (self-consistent with the ~90% aggregate target): ~196k rows/day ÷ 2880 scrapes/day (30s) ≈ 68 rows/scrape. At 300s → 288 scrapes/day → ~19.6k rows/day from the interval change alone (−90.0%). `loop*`/`dm-*` excludes cut the per-scrape series count further (each snap loop device contributes filesystem + disk series; pure noise on a cx33). Combined: ≥90% reduction, comfortably under the 3 GB/month logs quota with the demo source already deleted.
- **Test runner reality**: both infra suites are plain bash (`bash <file>.sh`) — no bun/vitest assumptions. `vector-pii-scrub.test.sh` additionally shells into `bun -e` for TS HMAC parity (needs `apps/web-platform` node_modules; `bun install --frozen-lockfile` if absent).
- **CLI verification**: the `vector validate --no-environment --config-toml ...` and binary-download invocations in Phase 3 are copied verbatim from `.github/workflows/validate-vector-config.yml:68-88` <!-- verified: 2026-06-10 source: repo workflow file -->.
- **Code-review overlap query** run at plan time (`gh issue list --label code-review --state open`, 200-issue window): zero open issues reference `vector.toml`, `expenses.md`, or `vector-pii-scrub.test.sh`.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is an operator-facing observability config. Worst case: an invalid TOML key ships, the next `vector.service` restart fails, and host metrics + WARN+ log shipping to Better Stack stop (operator blind spot, not user-visible). Guard: CI `vector validate` against the pinned binary rejects unknown keys pre-merge; post-deploy `vector_journal_tail` via `/hooks/deploy-status` confirms a clean reload.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure vector — the change strictly *reduces* data shipped to Better Stack (fewer metric rows; zero new fields). The PII scrub pipeline is byte-for-byte unchanged and pinned by parity fixtures.
- **Brand-survival threshold:** none — `threshold: none, reason: change reduces third-party data egress and touches no user-data processing path; the PII redaction transforms in the same file are diff-locked by AC2 and the CI parity suite.`

## Implementation Phases

### Phase 1 — vector.toml host_metrics tuning

Edit ONLY the Source 4 block (`apps/web-platform/infra/vector.toml:99-105`). Replace:

```toml
# ---------------- Source 4: host metrics (CPU/mem/disk/net) ----------------
# 30s scrape. Each scrape emits ~80-100 metric series on the cx33;
# rate-limited downstream by Vector's internal batching.
[sources.host_metrics]
type = "host_metrics"
scrape_interval_secs = 30
collectors = ["cpu", "memory", "disk", "filesystem", "load", "network"]
```

with:

```toml
# ---------------- Source 4: host metrics (CPU/mem/disk/net) ----------------
# 300s scrape (2026-06-10 quota fix — was 30s). Host metrics were >99% of
# Better Stack ingest (~196k rows/day vs ~50 journald WARN+ rows/day),
# tripping the 80% free-tier (3 GB/mo logs) warning. 5-min granularity is
# sufficient for the CPU/mem/disk diagnosis use case. Snap loop devices
# (loop*) and device-mapper (dm-*) are excluded from the disk + filesystem
# collectors below — pseudo-device series with no diagnostic signal.
# Decision record: knowledge-base/operations/expenses.md (Better Stack row);
# strategic re-decision tracked in #4296.
[sources.host_metrics]
type = "host_metrics"
scrape_interval_secs = 300
collectors = ["cpu", "memory", "disk", "filesystem", "load", "network"]

[sources.host_metrics.disk]
devices.excludes = ["loop*", "dm-*"]

[sources.host_metrics.filesystem]
devices.excludes = ["loop*", "dm-*"]
```

Notes:
- The two filter sub-tables sit between `[sources.host_metrics]` and the `# ---------------- Transform 1/3` marker — valid TOML, adjacent for readability, and invisible to `vector-pii-scrub.test.sh`'s `extract_vrl` awk (which only captures `[transforms.*]` blocks).
- Do NOT touch `[sources.vector_internal]` (`scrape_interval_secs = 60` — internal liveness counters to stdout/journald, not shipped to Better Stack).
- No `$`-containing values are introduced — no TOML `$$`-escape interaction.

### Phase 2 — expense ledger update

`knowledge-base/operations/expenses.md`:

1. Frontmatter: `last_updated: 2026-05-21` → `last_updated: 2026-06-10`.
2. Better Stack row (line 22, the `0.00 | free-tier` row — NOT the line-20 Responder DEFERRED row): append to Notes (keep existing Notes text; no `|` characters in the appended text):

   > 2026-06-10: 80% log-quota warning (free tier 3 GB/mo logs, 3-day retention + 30 GB metrics). Root cause: Vector host_metrics 30s scrape = >99% of ingest (~196k rows/day). Remediated: 300s scrape + loop*/dm-* device excludes (PR #&lt;this-PR&gt;) + deleted leftover "Onboarding • Real-time flights" demo source (id 2327782) via Telemetry API. Decision: stay free tier ($0.00 unchanged); upgrade trigger unchanged (first paying customer). Ref #4296.

   (Replace `#<this-PR>` with the real PR number at /work time, after `gh pr create`.)

### Phase 3 — local verification (pre-push)

```bash
# 1. Pinned binary (form copied from validate-vector-config.yml:68-76)
V=$(awk -F'"' '/vector_version[[:space:]]*=/ { print $2; exit }' apps/web-platform/infra/vector.tf)
curl -sLo /tmp/vector.tar.gz "https://packages.timber.io/vector/${V}/vector-${V}-x86_64-unknown-linux-gnu.tar.gz"
tar -xzf /tmp/vector.tar.gz -C /tmp ./vector-x86_64-unknown-linux-gnu/bin/vector

# 2. Schema validate (rejects unknown host_metrics filter keys)
VECTOR_STRICT_ENV_VARS=false BETTERSTACK_LOGS_TOKEN=dummy SENTRY_USERID_PEPPER=dummy \
  /tmp/vector-x86_64-unknown-linux-gnu/bin/vector validate --no-environment \
  --config-toml apps/web-platform/infra/vector.toml

# 3. PII-scrub parity fixtures (proves transforms untouched AND still extractable)
SENTRY_USERID_PEPPER=fixture-only-do-not-use-in-prod \
  VECTOR_BIN=/tmp/vector-x86_64-unknown-linux-gnu/bin/vector \
  bash apps/web-platform/test/infra/vector-pii-scrub.test.sh
```

Precondition for step 3: `apps/web-platform/node_modules` present (`cd apps/web-platform && bun install --frozen-lockfile` if not) — the script's TS-parity check imports `server/observability.ts` via `bun -e`.

### Phase 4 — PR + post-merge deployment (see § Infrastructure for full apply path)

- PR body: `Ref #4296` (related context only — must NOT auto-close), deployment note (tag → image → pin bump → webhook → verify), and the deterministic verification rule.
- Post-merge steps are enumerated under Acceptance Criteria § Post-merge with automation feasibility per step.

## Files to Edit

1. `apps/web-platform/infra/vector.toml` — Source 4 block only (lines 99–105 + two new sub-tables).
2. `knowledge-base/operations/expenses.md` — frontmatter `last_updated` + Better Stack row Notes.

Post-merge follow-up commit/PR (not this PR; ordering forced by AC6 drift guard — tag must exist first):
3. `apps/web-platform/infra/cloud-init.yml` — bootstrap image pin `v1.1.11` → `v1.1.12` (all occurrences).

## Files NOT to Edit (invariant surfaces)

- `vector.toml` sources 1–3 (`inngest_journald`, `system_journald`, `app_container_journald`), `app_container_warn_filter`, all three `pii_scrub_*` transforms, `tag_journald`, `tag_metrics`, `[sinks.betterstack]`, `[sources.vector_internal]`, `[sinks.vector_console]`.
- `apps/web-platform/test/infra/vector-pii-scrub.test.sh`, `.github/workflows/validate-vector-config.yml`, `apps/web-platform/infra/vector.tf` (no version bump), `inngest-bootstrap.sh`, `ci-deploy.sh`.

## Open Code-Review Overlap

None — plan-time query of open `code-review` issues (limit 200) found zero matches for any planned file path.

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — interval**: `grep -c '^scrape_interval_secs = 300$' apps/web-platform/infra/vector.toml` → `1`; `grep -c '^scrape_interval_secs = 30$' apps/web-platform/infra/vector.toml` → `0`; `grep -c '^scrape_interval_secs = 60$' apps/web-platform/infra/vector.toml` → `1` (vector_internal untouched).
2. **AC2 — pipeline byte-for-byte** (tested green on baseline at plan time; sed `\|...|` delimiter avoids escaping the `/` in `1/3`):
   ```bash
   diff <(git show origin/main:apps/web-platform/infra/vector.toml | sed -n '\|^# ---------------- Transform 1/3|,$p') \
        <(sed -n '\|^# ---------------- Transform 1/3|,$p' apps/web-platform/infra/vector.toml)
   ```
   → exit 0 / empty (everything from the first transform to EOF — all transforms + both sinks + vector_internal — is byte-identical to main).
3. **AC3 — sources 1–3 byte-for-byte**:
   ```bash
   diff <(git show origin/main:apps/web-platform/infra/vector.toml | sed -n '1,\|^# ---------------- Source 4|p') \
        <(sed -n '1,\|^# ---------------- Source 4|p' apps/web-platform/infra/vector.toml)
   ```
   → exit 0 / empty (file header + journald sources + WARN filter unchanged). AC2+AC3 jointly prove the diff is confined to the Source 4 block.
4. **AC4 — device excludes**: `grep -c 'devices.excludes = \["loop\*", "dm-\*"\]' apps/web-platform/infra/vector.toml` → `2`, one under `[sources.host_metrics.disk]`, one under `[sources.host_metrics.filesystem]`.
5. **AC5 — stale comment gone**: `grep -c '30s scrape' apps/web-platform/infra/vector.toml` → `0`; new comment names the 2026-06-10 quota incident and the 300s rationale.
6. **AC6 — schema validate**: Phase 3 step 2 (`vector validate` with pinned 0.43.1) exits 0.
7. **AC7 — parity fixtures**: Phase 3 step 3 (`vector-pii-scrub.test.sh`) exits 0 with all fixtures passing.
8. **AC8 — ledger**: `expenses.md` Better Stack free-tier row Amount still `0.00`, Status still `free-tier`; Notes contain `2026-06-10`, `300s`, `2327782`, and `Ref #4296`-style reference; frontmatter `last_updated: 2026-06-10` (`awk '/^last_updated:/ { print $2; exit }' knowledge-base/operations/expenses.md` → `2026-06-10`). Responder DEFERRED row (line 20) byte-identical to main.
9. **AC9 — PR body**: contains `Ref #4296` (grep `-c 'Closes #4296'` → 0), the deployment note (tag → image build → cloud-init pin bump → webhook → verification query), and the deterministic verdict rule from AC12.
10. **AC10 — CI green**: `validate-vector-config.yml` PR run passes (fires automatically — `vector.toml` is in its `pull_request` path filter), including the Better Stack source/cluster disclosure-parity step (sink URI untouched → trivially green).

### Post-merge (operator)

11. **AC11 — deploy executed** (automation per step):
    a. Tag the merge commit: `git tag vinngest-v1.1.12 <merge-sha> && git push origin vinngest-v1.1.12`. Re-check first that `v1.1.12` is still the next semver (`git tag -l 'vinngest-*' | sort -V | tail -1` → `vinngest-v1.1.11` at plan time); if another tag landed meanwhile, use the next free patch version everywhere `v1.1.12` appears in AC11. *Automation: feasible in-session (git push of a tag; `build-inngest-bootstrap-image.yml` triggers on `vinngest-v*.*.*`).*
    b. Wait for the image build run to succeed: `gh run list --workflow=build-inngest-bootstrap-image.yml --limit 1` → `completed/success`. *Automation: feasible (poll via Monitor).*
    c. Cloud-init pin-bump follow-up PR: `cloud-init.yml` `v1.1.11` → `v1.1.12` (ALL occurrences; AC6 drift guard `cloud-init-inngest-bootstrap.test.sh` requires pin == latest published tag; precedent PR #4669). *Automation: feasible in-session.*
    d. Fire the deploy webhook with the canonical HTTPS HMAC form (PAYLOAD `{"command":"deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.1.12"}`, Doppler `soleur/prd_terraform` for `WEBHOOK_DEPLOY_SECRET` + CF Access creds; expect HTTP 202; form per `web-platform-release.yml:370-391`). *Automation: feasible, but prod write — requires explicit operator ack per `hr-menu-option-ack-not-prod-write-auth`.*
    e. Confirm clean reload: GET `/hooks/deploy-status` (signed empty string) → `exit_code: 0`; `vector_journal_tail` shows no config-load errors. *Automation: feasible (read-only).*
12. **AC12 — quota verdict (deterministic, no dashboard, no SSH)**: ≥24h after deploy, run
    ```bash
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
      "SELECT toDate(dt) AS day, count(*) AS c FROM remote(\$BS_TABLE) WHERE dt >= now() - INTERVAL 3 DAY AND raw LIKE '%\"namespace\":\"host\"%' GROUP BY day ORDER BY day FORMAT JSONEachRow"
    ```
    Verdict rule: the first full post-deploy day shows `c ≤ 25,000` (vs ~196k baseline ≈ ≥87% cut; interval math predicts ~19.6k before device excludes). If `c > 25,000`, re-open the remediation (do not silently accept).
13. **AC13 — issue hygiene**: #4296 still OPEN after merge (reference did not auto-close).

## Domain Review

**Domains relevant:** none requiring leader review — infrastructure/observability tuning with a $0.00, operator-pre-approved ledger annotation.

Assessment notes (semantic sweep performed inline; pipeline context — subagent spawning unavailable in this planning session, recorded for transparency):
- **Engineering/CTO**: the change itself; covered by this plan + CI gates.
- **Finance/CFO**: expense ledger row is annotated but Amount/Status/upgrade-trigger are all unchanged ($0.00, free-tier, first-paying-customer). The spend *decision* was already made by the operator this session ("Tune Vector, stay free") — recording an outcome, not making a financial decision.
- **Legal/CPO/Product/Marketing/Sales/People**: no user-facing surface, no new data processing (volume strictly decreases), no disclosure drift (sink URI/source ID untouched — CI parity step pins the 4 legal disclosure surfaces).

### Product/UX Gate

Not applicable — **NONE** tier. No file in Files to Edit matches any UI-surface glob (`components/**`, `app/**/page.tsx`, etc.); mechanical override did not fire.

## GDPR / Compliance Gate (Phase 2.7)

Skipped with note: no regulated-data surface touched (no schemas/migrations/auth/API routes/SQL; canonical regex misses) and none of the four expanded triggers fire (no new processing activity — data egress to the existing sub-processor strictly decreases; threshold is `none`; no new cron reading learnings/specs; no new distribution surface). The PII redaction pipeline in the same file is diff-locked by AC2.

## Infrastructure (IaC)

No NEW infrastructure — this edits an existing IaC-managed config delivered through the established tag → OCI image → webhook pipeline. Documented here because the apply path is multi-step and the PR body must state it.

### Terraform changes
None. `vector.tf` version pin unchanged (0.43.1). No new providers, variables, or secrets.

### Apply path
Existing-infra path (c-style: content rides the OCI image; no re-provisioning):
1. Merge PR → `main` contains new `vector.toml`.
2. Push `vinngest-v1.1.12` tag on the merge commit → `build-inngest-bootstrap-image.yml` embeds `vector.toml` in the bootstrap image.
3. Follow-up cloud-init pin bump (`v1.1.11` → `v1.1.12`) keeps the AC6 drift guard green (pin must equal semver-max published tag — bump can only land AFTER the tag exists; precedent PR #4669).
4. Operator-acked deploy webhook (`deploy inngest ... v1.1.12`) → `ci-deploy.sh` extracts `/vector.toml` (clears `/tmp/vector.toml` first — stale-reuse guard already in the script) → `inngest-bootstrap.sh` installs + restarts `vector.service`. Expected blast radius: ~5s inngest pause/drain/resume; Vector restart gap of seconds (metrics at 300s cadence anyway).

### Distinctness / drift safeguards
- `cloud-init-inngest-bootstrap.test.sh` AC6: pin == latest `vinngest-v*` tag (the reason step 3 is ordered after step 2).
- `ci-deploy.sh:788-796` stale-`/tmp/vector.toml` guard (already shipped) ensures the NEW config actually lands rather than a cached prior copy.
- Fresh-host path (cloud-init) picks the new image automatically once the pin bump merges.

### Vendor-tier reality check
Better Stack free tier: 3 GB/mo logs (3-day retention) + 30 GB metrics, hard relevance to this change — the remediation exists precisely to stay inside it. No paid-tier-gated resources are created. Upgrade trigger remains "first paying customer" (ledger row).

## Observability

```yaml
liveness_signal:
  what: vector_internal metrics on stdout/journald (vector.service) surfaced via cat-deploy-state.sh `vector_journal_tail` in the /hooks/deploy-status payload
  cadence: 60s (vector_internal scrape — unchanged by this PR)
  alert_target: operator session reading deploy-status post-deploy; Better Stack heartbeat/uptime monitors unaffected
  configured_in: apps/web-platform/infra/vector.toml ([sources.vector_internal] + [sinks.vector_console]) + apps/web-platform/infra/cat-deploy-state.sh
error_reporting:
  destination: CI (`vector validate` in validate-vector-config.yml) pre-merge; vector.service journald (visible in vector_journal_tail via /hooks/deploy-status) post-deploy
  fail_loud: invalid config fails the PR check; a failed vector.service restart appears in deploy-status output — not silently swallowed
failure_modes:
  - mode: invalid host_metrics filter key ships
    detection: vector validate (AC6, pre-merge CI gate with pinned binary)
    alert_route: PR check failure
  - mode: vector.service fails to restart on deploy
    detection: /hooks/deploy-status `vector_journal_tail` (AC11e)
    alert_route: in-session post-merge verification step
  - mode: volume cut insufficient — quota warning recurs
    detection: AC12 query verdict rule (first full post-deploy day ≤ 25k host rows) + Better Stack 80%/100% warning emails to ops@jikigai.com
    alert_route: operator email + re-opened remediation
logs:
  where: Better Stack Logs source 2457081 (eu-fsn-3), queryable via scripts/betterstack-query.sh (ClickHouse HTTP SQL)
  retention: 3 days (free tier)
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "SELECT toDate(dt) AS day, count(*) AS c FROM remote($BS_TABLE) WHERE dt >= now() - INTERVAL 3 DAY AND raw LIKE '%\"namespace\":\"host\"%' GROUP BY day ORDER BY day FORMAT JSONEachRow"
  expected_output: post-deploy day row count ≤ 25,000 (baseline ~196,000)
```

## Test Scenarios

1. Unmodified-baseline sanity (run at plan time, green): AC2 + AC3 diffs are empty against the current tree — proves the verification commands themselves work before the edit exists.
2. Post-edit: AC1–AC8 all pass locally; CI `validate-vector-config.yml` passes on the PR.
3. Negative probe (work-phase, optional but cheap): temporarily misspell `devices.exclude` (singular) and confirm `vector validate` fails — proves the schema gate actually guards the new keys; revert.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| 5-min granularity hides short CPU/mem spikes | Accepted by design (file's own comments scope host metrics to coarse diagnosis); Sentry + deploy-status + uptime monitors carry incident-grade signal. Reversible one-line change; #4296 re-decision can revisit |
| `loop*`/`dm-*` glob accidentally excludes a real device | cx33 root disk is `sda`-class; device-mapper unused on this host. AC12 post-deploy query still shows cpu/memory/load/network + real-disk series present (count > 0) |
| Filter syntax drift across Vector versions | Syntax verified against vector.dev docs 2026-06-10; CI validates against the EXACT pinned 0.43.1 binary (AC6) — fabricated keys cannot merge |
| Demo-source deletion already counted in quota | Free-tier quota is monthly-rolling; the deleted source stops contributing immediately. AC12 measures only the host-metrics source, isolating this PR's effect |
| Pin-bump window: between tag push (AC11a) and pin-bump merge (AC11c), other infra PRs touching the drift-guard paths fail AC6 | Execute a–c back-to-back in the post-merge session (minutes-wide window; precedent #4669) |

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Pay for Better Stack tier | Operator-rejected; ledger upgrade trigger ("first paying customer") not fired. $0.00 stands |
| Drop the host_metrics source entirely | Loses CPU/mem/disk diagnosis capability the source was added for (#4279); operator approved "keep but reduce" |
| Trim `collectors` list (drop network/load) | Less volume impact than the interval (rows scale with scrape count); keeps less signal than interval+excludes for the same cut |
| Filter host_metrics in a transform (VRL) instead of at source | Violates "transforms byte-for-byte untouched"; source-side filters are the documented native mechanism and ship zero bytes instead of dropping post-scrape |
| `mountpoints.excludes = ["/snap/*"]` on filesystem | Redundant with `devices.excludes = ["loop*"]`; device-level exclusion also covers the disk collector with one consistent pattern pair |

No deferred-scope items requiring tracking issues (all alternatives are rejections, not deferrals; the strategic re-decision already has #4296).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — section above is complete with an explicit `threshold: none, reason: ...` scope-out bullet.
- Do NOT touch `scrape_interval_secs = 60` under `[sources.vector_internal]` — AC1's third grep pins it.
- The expenses row append must not introduce `|` characters (markdown table cell).
- `Ref #4296`, never `Closes #4296` — in body only, per `wg-use-closes-n-in-pr-body-not-title-to`.
- Tag push (AC11a) must point at the MERGE commit on main — an image built from a pre-merge ref would ship the OLD vector.toml.

## References

- Vector host_metrics docs: <https://vector.dev/docs/reference/configuration/sources/host_metrics/> (filter syntax verified 2026-06-10)
- `knowledge-base/project/learnings/2026-05-22-vector-vrl-config-gates-and-pii-redaction-pipeline.md`
- `knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md` (webhook HMAC form)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` (upgrade path; note: its SSH-form webhook examples are superseded by the HTTPS form per `hr-no-ssh-fallback-in-runbooks`)
- Prior art: PR #4279 (host metrics added), #4293 (PII pipeline + CI gates), #4786 (last vector.toml change), #4669 (cloud-init pin-bump precedent), #4675/#4676 (AC6 drift guard)
- Issue #4296 — observability consolidation 60-day re-decision (related context; stays open)
