---
title: "fix: trim Vector host_metrics collectors — Better Stack daily rows ≤25k (AC12 FAIL re-open, #5110)"
type: fix
date: 2026-06-10
lane: cross-domain
brand_survival_threshold: none
related_issues: ["#5110 (verdict tracker — keep OPEN; Ref only)", "#4296 (reference only — do NOT close)"]
---

# fix: Trim Vector host_metrics collectors so Better Stack host-metrics rows land ≤25,000/day

> No spec.md exists for this branch (one-shot pipeline entered at plan). Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-06-10 (inline pipeline mode — gates 4.6/4.7/4.8 passed mechanically; 4.9 N/A, no UI surface; subagent spawning unavailable, all passes run inline)
**Key improvements from live probes against the pinned Vector 0.43.1 binary (run THIS pass — not carried forward):**

1. **Positive probe PASSED:** the exact proposed Source 4 TOML (trimmed `collectors` + `mountpoints.includes = ["/", "/mnt/data", "/var/lib/vector"]` under `[sources.host_metrics.filesystem]`) was applied to a /tmp copy of `vector.toml` and `vector validate --no-environment` exited 0 on `vector 0.43.1 (x86_64-unknown-linux-gnu e30bf1f)`. The new filter key is now **binary-verified**, not just docs-verified.
2. **Negative probes re-confirmed the #5105 ground truth for the NEW key:** `mountpoints.include` (misspelled) validates clean (silent no-op) → **AC2's byte-exact grep is the load-bearing spelling guard**; `mountpoints.includes = "/"` (string, not array) is REJECTED by validate (type errors are caught).
3. **Verify-the-negative pass (3/3 confirmed by grep):** (a) zero consumers of Better Stack network series across `infra/`, runbooks, and `scripts/` — dropping the network collector darks no alert (`hr-observability-layer-citation`-style sweep); (b) zero test files reference `collectors`/`host_metrics` literals — no test edits needed; (c) `disk-monitor.sh:26` watches only `/` (`df --output=pcent /`) — confirming `/mnt/data` capacity charting is otherwise uncovered, the reason filesystem is allowlisted rather than dropped.
4. **Plan-time AC self-test:** AC5 + AC6 verification commands run green on the unmodified baseline; AC6 was REWRITTEN at plan time (inclusive sed range → exclusive awk boundary) because the Source 4 marker line itself changes in this PR — the prior plan's AC3 form would false-fail.
5. **Citations verified live:** all 3 cited AGENTS.md rule IDs active; PR/issue attributions #4669 (pin-bump precedent, MERGED), #4675 (drift-guard issue, CLOSED) / #4676 (drift-guard PR, MERGED), #4250 (vector shipper, MERGED), #4293 (PII pipeline, MERGED), #5105/#5112 (MERGED), #5110/#4296 (OPEN) — all consistent with their cited roles; all KB file paths resolve.

## Overview

PR #5105 (300s scrape interval + `loop*`/`dm-*` device excludes, deployed via `vinngest-v1.1.12` on 2026-06-10 ~17:59Z) was **insufficient**: the AC12 quota verdict on #5110 came back `RESULT: FAIL`. Measured steady state is **198 rows per 300s scrape** (flat across all 9 observed cycles) → **~57,024 rows/day projected — 2.3× over the 25,000/day threshold** (plan had predicted ~19.6k). The interval change DID take effect (exactly one scrape per 5-min bucket); the overshoot is per-scrape row count. Verdict comment: <https://github.com/jikig-ai/soleur/issues/5110#issuecomment-4673409548>.

**Measured per-scrape breakdown** (2026-06-10 prd Better Stack query via `scripts/betterstack-query.sh`):

| Collector | Rows/scrape | Notes |
|---|---|---|
| filesystem | 108 | 4 metrics × 27 mountpoints — 21 of 27 are virtual fs (tmpfs, sysfs, proc, cgroup2, debugfs, bpf, pstore, devpts, hugetlbfs, mqueue, securityfs, configfs, tracefs, binfmt_misc, autofs, fusectl, …); real mounts: `/`, `/mnt/data`, `/tmp`, `/var/tmp`, `/var/lib/vector`, `/boot/efi`. The `loop*`/`dm-*` *device* excludes don't touch virtual-fs mountpoints |
| network | ~33 | 8 metrics × ~4 interfaces (eth0 + docker bridge/veth noise) |
| disk | 24 | real-device I/O series |
| cpu | 20 | `cpu_seconds_total` (modes × vCPUs) |
| memory/load/misc | ~13 | |
| **Total** | **198** | → 57,024/day at 288 scrapes/day |

Excluding only the 21 virtual mountpoints lands at ~114 rows/scrape ≈ ~33k/day — **still over threshold**, so the `collectors` list itself must be trimmed, per the next-lever note on #5110. This reverses the #5105 plan's alternatives-table rejection of collector trimming ("less volume impact than the interval") — the interval lever is now spent and the measurement shows the remaining volume is collector-shaped.

**Remediation (one block, `apps/web-platform/infra/vector.toml` Source 4 only):**

1. **Drop the `network` collector** (−33 rows): no alert, monitor, or runbook consumes Better Stack network series; uptime monitors + Sentry carry incident-grade signal. Re-add path documented (Alternatives) if a future need appears.
2. **Allowlist `filesystem` to 3 diagnostic mountpoints** (`/`, `/mnt/data`, `/var/lib/vector`) via `mountpoints.includes` (−96 rows): root capacity, Hetzner data volume, and Vector's own buffer dir are the load-bearing disk-usage signals. The other real mounts (`/tmp`, `/var/tmp`, `/boot/efi`) are low-signal; `/` capacity is independently covered by `disk-monitor.sh` (5-min systemd timer, Resend email at 80%/95%).
3. Keep `cpu`, `memory`, `disk`, `load` and the 300s interval unchanged.

**Projection grounded in MEASURED counts (not modeled, unlike #5105):** 20 (cpu) + 13 (memory/load) + 24 (disk) + 12 (filesystem: 4 metrics × 3 mounts) = **~69 rows/scrape → ~19,872 rows/day** — 20% under the 25k threshold and 20% under the ≤86 rows/scrape target. The prior 2.9× prediction error came from modeling series counts; every term above is observed.

Deployment rides the established pipeline: merge → tag `vinngest-v1.1.13` → OCI image build → cloud-init pin-bump follow-up PR → deploy webhook (operator-acked) → fast per-bucket verdict (~30 min) → daily AC12-style verdict on #5110 (`RESULT: PASS` gates closure; **#5110 stays open as the tracker — PR body uses `Ref #5110`, never `Closes`**).

## Premise Validation

All cited artifacts verified against repo + live state on 2026-06-10:

- **#5110**: `gh issue view 5110` → `OPEN`, label `follow-through`, latest comment is the operator `RESULT: FAIL` verdict (2026-06-10T18:47Z run; 1,790 rows in the partial first day; 198 rows/bucket × 9 cycles). Premise holds — re-open is warranted; issue stays the tracker.
- **PR #5105**: `MERGED` 2026-06-10T14:29Z — vector.toml 300s + device excludes. **PR #5112**: `MERGED` 2026-06-10T16:02Z — cloud-init pin v1.1.11 → v1.1.12 (4 occurrences swept). Premise holds.
- **`apps/web-platform/infra/vector.toml`**: Source 4 block at lines 99–118: `scrape_interval_secs = 300`, `collectors = ["cpu", "memory", "disk", "filesystem", "load", "network"]`, `[sources.host_metrics.disk]` + `[sources.host_metrics.filesystem]` each with `devices.excludes = ["loop*", "dm-*"]`. Premise holds.
- **Tags**: `git tag -l 'vinngest-v*' | sort -V | tail -1` → `vinngest-v1.1.12`. Next free patch: `v1.1.13`.
- **`scripts/followthroughs/betterstack-quota-verdict-5105.sh`**: greps `^RESULT: PASS$` BEFORE `^RESULT: FAIL$` across ALL issue comments — a later PASS comment closes #5110 despite the existing FAIL comment. No script edit needed. `earliest=2026-06-12T16:00:00Z` in the issue body remains a valid lower bound for the re-verdict.
- **#4296** (observability consolidation 60-day re-decision): `OPEN` — reference-only, must not auto-close.
- **`/mnt/data`**: real Hetzner volume mount (`cloud-init.yml:471-473` fstab entry). `/var/lib/vector` appears as a distinct mountpoint in the measured 27 (and in `vector.service` ReadWritePaths). Premise holds for the allowlist choice.
- **Vector filesystem filter contract**: `vector.dev` host_metrics docs (fetched 2026-06-10 for the #5105 plan, same day): filesystem collector has three filters (`devices`, `filesystems`, `mountpoints`), each `includes`/`excludes`, glob-matched, default `includes = ["*"]`. Binary probes RE-RUN at deepen time on pinned 0.43.1 with the NEW key (see Enhancement Summary): exact proposed TOML validates clean; **misspelled `mountpoints.include` is silently IGNORED by `vector validate`** (wrong value types and unknown top-level keys are rejected) → AC2's byte-exact grep is the load-bearing spelling guard.

## Research Reconciliation — Spec vs. Codebase

| Claim (feature description) | Reality (verified) | Plan response |
|---|---|---|
| "target ≤86 rows per 300s scrape" | 25,000 ÷ 288 scrapes/day = 86.8 — confirmed arithmetic | Design target ~69 rows/scrape (20% margin under 86) using measured per-collector counts |
| "keep cpu, memory, load, disk; drop or heavily filter filesystem and network" | Dropping BOTH filesystem and network = 57/scrape (16.4k/day) but loses all disk-usage charting; `disk-monitor.sh` only watches `/` (not `/mnt/data`) | Hybrid: drop network entirely; keep filesystem mountpoint-allowlisted to `/`, `/mnt/data`, `/var/lib/vector` (12 rows) — preserves `/mnt/data` capacity signal that NO other monitor covers |
| "the fix likely needs a new image tag + pin bump follow-up" | Confirmed: vector.toml is embedded in the inngest-bootstrap OCI image (`build-inngest-bootstrap-image.yml` on `vinngest-v*` tag push); cloud-init pin drift guard (AC6, `cloud-init-inngest-bootstrap.test.sh`) forces the pin bump AFTER the tag exists (precedent PRs #5112, #4669) | Post-merge sequence: tag `vinngest-v1.1.13` → image build → pin-bump follow-up PR → operator-acked deploy webhook |
| "Keep issue #5110 open as the tracker (fresh AC12-style verdict gates closure)" | Follow-through script's PASS grep precedes the FAIL grep, so the existing `RESULT: FAIL` comment does not block a later PASS close; sweeper polls daily | PR body `Ref #5110`; post-deploy re-verdict posts `RESULT: PASS` (exact line) when the first full post-deploy day ≤25k |

## Research Insights

- **Deployment chain** (verified from source, unchanged since #5105): `build-inngest-bootstrap-image.yml` copies `apps/web-platform/infra/vector.toml` into the image at `/vector.toml`; `ci-deploy.sh:784-796` clears `/tmp/vector.toml` then extracts (stale-reuse guard); `inngest-bootstrap.sh:344-427` installs to `/etc/vector/vector.toml` + restarts `vector.service`; `cloud-init.yml:561-574` pins `v1.1.12` (4 occurrences — sweep all in the pin-bump commit).
- **Canonical webhook fire** (no-SSH form per `hr-no-ssh-fallback-in-runbooks`): `.github/workflows/web-platform-release.yml` "Deploy via webhook" step — HMAC-SHA256 over payload with `WEBHOOK_DEPLOY_SECRET`, CF Access headers, POST `https://deploy.soleur.ai/hooks/deploy`, expect HTTP 202; poll `/hooks/deploy-status` (GET signs empty string). Payload here: `{"command":"deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.1.13"}`. Secrets via Doppler `soleur/prd_terraform`. <!-- verified: 2026-06-10 source: .github/workflows/web-platform-release.yml + restart-inngest-server.yml -->
- **Verdict query mechanics**: `scripts/betterstack-query.sh` raw-SQL mode with `$BS_TABLE` substitution; host rows identified by `raw LIKE '%"namespace":"host"%'`. Per-bucket granularity via `toStartOfFiveMinutes(dt)` (the exact group-by the FAIL verdict used) gives a **fast verdict ~30 min post-deploy** — no 24h wait to detect a second overshoot.
- **Test surfaces**: `vector-pii-scrub.test.sh` extracts only `[transforms.*]` blocks (host_metrics source edits are invisible to it); `validate-vector-config.yml` fires on the `vector.toml` PR path and runs pinned-binary `vector validate` + VRL fixtures + disclosure-parity (sink URI untouched → trivially green). No test file references `collectors` or `host_metrics` literals (grep-verified) — no test edits needed.
- **Key learnings applied**: `2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md` (measure per-source first; metrics through the generic HTTP sink bill as logs); `2026-05-22-vector-vrl-config-gates-and-pii-redaction-pipeline.md` (TOML `${...}` preprocessing — no `$` in new keys); #5105 archived-plan deepen probes (validate's filter-sub-key looseness → byte-exact grep is the spelling guard).
- **Code-review overlap query** run at plan time (`gh issue list --label code-review --state open`, 200-issue window): zero open issues reference `vector.toml`, `cloud-init.yml`, `expenses.md`, or `betterstack`.
- **Margin discipline**: the #5105 failure was a *prediction* failure (modeled ~68 rows/scrape; actual 198). This plan's 69-row projection sums **observed** per-collector counts; the only modeled term is filesystem post-filter (4 × 3 = 12, derived from the observed 108 ÷ 27 = exactly 4 metrics/mount). Residual risk is filter runtime semantics, covered by the fast per-bucket verdict (AC13) before the daily verdict (AC14).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — operator-facing observability config. Worst cases: (a) invalid TOML ships → `vector.service` restart fails → host metrics + WARN+ log shipping stop (operator blind spot; guarded by CI `vector validate` pre-merge + `vector_journal_tail` via `/hooks/deploy-status` post-deploy); (b) over-filtering silently drops the `/mnt/data` capacity series → slower diagnosis of a disk-full incident (guarded by AC13's filesystem-presence check; `disk-monitor.sh` independently emails on `/`).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure vector — the change strictly *reduces* data shipped to Better Stack (fewer metric rows; zero new fields). The PII scrub pipeline is byte-for-byte unchanged and pinned by parity fixtures (AC5) + CI.
- **Brand-survival threshold:** none — `threshold: none, reason: change reduces third-party data egress and touches no user-data processing path; the PII redaction transforms in the same file are diff-locked by AC5 and the CI parity suite.`

## Implementation Phases

### Phase 1 — vector.toml Source 4 collector trim

Edit ONLY the Source 4 block (`apps/web-platform/infra/vector.toml:99-118`). Replace the current block (comment lines 99–108 + `[sources.host_metrics]` + the two filter sub-tables) with:

```toml
# ---------------- Source 4: host metrics (CPU/mem/disk) ----------------
# 300s scrape (2026-06-10 quota fix) + trimmed collectors (2026-06-10 second
# pass — AC12 verdict FAIL on #5110: 198 rows/scrape = ~57k rows/day, 2.3x
# the 25k/day threshold; the 300s interval alone was insufficient). Measured
# per-scrape breakdown: filesystem 108 (4 metrics x 27 mountpoints, 21
# virtual-fs), network ~33, disk 24, cpu 20, memory/load ~13. Remedy: drop
# the network collector (no alert/runbook consumes it; uptime monitors +
# Sentry carry incident-grade signal) and allowlist filesystem to the three
# diagnostic mountpoints below (root capacity, Hetzner data volume, Vector's
# own buffer dir — /mnt/data is covered by NO other monitor; / is also
# covered by disk-monitor.sh). Predicted ~69 rows/scrape = ~19.9k rows/day
# (20% under threshold). Snap loop devices (loop*) and device-mapper (dm-*)
# stay excluded from the disk + filesystem collectors — pseudo-device series
# with no diagnostic signal.
# Decision record: knowledge-base/operations/expenses.md (Better Stack row);
# verdict tracker: #5110; strategic re-decision tracked in #4296.
[sources.host_metrics]
type = "host_metrics"
scrape_interval_secs = 300
collectors = ["cpu", "memory", "disk", "filesystem", "load"]

[sources.host_metrics.disk]
devices.excludes = ["loop*", "dm-*"]

[sources.host_metrics.filesystem]
devices.excludes = ["loop*", "dm-*"]
mountpoints.includes = ["/", "/mnt/data", "/var/lib/vector"]
```

Notes:
- `mountpoints.includes` REPLACES the default `["*"]` — glob match is exact-string for patterns with no wildcards, so `/` matches only the root mount, not every path under it (vector.dev filter contract, verified 2026-06-10).
- Do NOT touch `[sources.vector_internal]` (`scrape_interval_secs = 60` — internal liveness to stdout/journald, never shipped to Better Stack).
- No `$`-containing values introduced — no TOML `$$`-escape interaction.
- The literal `"network"` must not remain anywhere in `vector.toml` (AC1 second grep).

### Phase 2 — ledger + post-mortem record updates

1. `knowledge-base/operations/expenses.md` — Better Stack free-tier row (the `0.00 | free-tier` row at line 22, NOT the line-20 Responder DEFERRED row): append to Notes (keep existing text; **no `|` characters** in the appended text):

   > 2026-06-10 second pass: AC12 verdict FAIL (198 rows per 300s scrape, ~57k rows/day projected vs 25k threshold — interval fix alone insufficient). Remediated again: dropped network collector + filesystem mountpoint allowlist (/, /mnt/data, /var/lib/vector), predicted ~19.9k rows/day (PR #&lt;this-PR&gt;). Verdict tracker #5110.

   Frontmatter `last_updated` is already `2026-06-10` — no change.

2. `knowledge-base/engineering/operations/post-mortems/betterstack-quota-near-miss-postmortem.md` — record that the first remediation under-delivered:
   - In the remediation/versions section (the "Version(s) that restored headroom" line citing PR #5105 / `vinngest-v1.1.12`): append `+ PR #<this-PR> (collector trim: network dropped, filesystem mountpoint allowlist) deployed via vinngest-v1.1.13 after the AC12 verdict FAILED at 198 rows/scrape (~57k/day projected)`.
   - In the follow-ups table, the `#5110` row stays `open`; update its description to note the second-pass re-verdict gates closure.
   - Do not rewrite history elsewhere in the PIR — append-only corrections.

### Phase 3 — local verification (pre-push)

```bash
# 1. Pinned binary (form copied from validate-vector-config.yml)
V=$(awk -F'"' '/vector_version[[:space:]]*=/ { print $2; exit }' apps/web-platform/infra/vector.tf)
curl -sLo /tmp/vector.tar.gz "https://packages.timber.io/vector/${V}/vector-${V}-x86_64-unknown-linux-gnu.tar.gz"
tar -xzf /tmp/vector.tar.gz -C /tmp ./vector-x86_64-unknown-linux-gnu/bin/vector

# 2. Schema validate (rejects load errors, wrong value types, unknown TOP-LEVEL
#    source keys — but NOT misspelled filter sub-keys; AC2 grep covers spelling)
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

- PR body: `Ref #5110` + `Ref #4296` (both must NOT auto-close), the deployment note (tag `vinngest-v1.1.13` → image build → cloud-init pin bump → webhook → fast verdict → daily verdict), and the deterministic verdict rules from AC13/AC14.
- Post-merge steps enumerated under Acceptance Criteria § Post-merge with automation feasibility per step.

## Files to Edit

1. `apps/web-platform/infra/vector.toml` — Source 4 block only (lines 99–118 → trimmed-collectors form above).
2. `knowledge-base/operations/expenses.md` — Better Stack row Notes (second-pass sentence).
3. `knowledge-base/engineering/operations/post-mortems/betterstack-quota-near-miss-postmortem.md` — append-only second-pass corrections.

Post-merge follow-up commit/PR (not this PR; ordering forced by the AC6 drift guard — tag must exist first):
4. `apps/web-platform/infra/cloud-init.yml` — bootstrap image pin `v1.1.12` → `v1.1.13` (ALL 4 occurrences; precedent PRs #5112, #4669).

## Files NOT to Edit (invariant surfaces)

- `vector.toml` sources 1–3 (`inngest_journald`, `system_journald`, `app_container_journald`), `app_container_warn_filter`, all three `pii_scrub_*` transforms, `tag_journald`, `tag_metrics`, `[sinks.betterstack]`, `[sources.vector_internal]`, `[sinks.vector_console]`.
- `apps/web-platform/test/infra/vector-pii-scrub.test.sh`, `.github/workflows/validate-vector-config.yml`, `apps/web-platform/infra/vector.tf` (no version bump), `inngest-bootstrap.sh`, `ci-deploy.sh`, `scripts/followthroughs/betterstack-quota-verdict-5105.sh` (PASS-before-FAIL grep order already supports the re-verdict).

## Open Code-Review Overlap

None — plan-time query of open `code-review` issues (limit 200) found zero matches for any planned file path.

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — collectors trimmed**: `grep -c '^collectors = \["cpu", "memory", "disk", "filesystem", "load"\]$' apps/web-platform/infra/vector.toml` → `1`; `grep -c '"network"' apps/web-platform/infra/vector.toml` → `0`.
2. **AC2 — mountpoint allowlist (byte-exact spelling guard — `vector validate` ignores misspelled filter sub-keys)**: `grep -c 'mountpoints.includes = \["/", "/mnt/data", "/var/lib/vector"\]' apps/web-platform/infra/vector.toml` → `1`, located under `[sources.host_metrics.filesystem]`.
3. **AC3 — device excludes retained**: `grep -c 'devices.excludes = \["loop\*", "dm-\*"\]' apps/web-platform/infra/vector.toml` → `2` (one under `.disk`, one under `.filesystem`).
4. **AC4 — intervals unchanged**: `grep -c '^scrape_interval_secs = 300$'` → `1`; `grep -c '^scrape_interval_secs = 60$'` → `1` (vector_internal untouched).
5. **AC5 — pipeline byte-for-byte** (tested green on baseline at plan time; sed `\|...|` delimiter avoids escaping `/`):
   ```bash
   diff <(git show origin/main:apps/web-platform/infra/vector.toml | sed -n '\|^# ---------------- Transform 1/3|,$p') \
        <(sed -n '\|^# ---------------- Transform 1/3|,$p' apps/web-platform/infra/vector.toml)
   ```
   → exit 0 / empty (all transforms + both sinks + vector_internal byte-identical to main).
6. **AC6 — sources 1–3 byte-for-byte** (awk exclusive-boundary form — the Source 4 marker line ITSELF changes in this PR (`(CPU/mem/disk/net)` → `(CPU/mem/disk)`), so the prior plan's inclusive `sed -n '1,\|pat|p'` range would false-fail; `{exit}` fires BEFORE print on the marker, excluding it):
   ```bash
   diff <(git show origin/main:apps/web-platform/infra/vector.toml | awk '/^# ---------------- Source 4/{exit} {print}') \
        <(awk '/^# ---------------- Source 4/{exit} {print}' apps/web-platform/infra/vector.toml)
   ```
   → exit 0 / empty. AC5+AC6 jointly confine the diff to the Source 4 block + its marker/comment.
7. **AC7 — schema validate**: Phase 3 step 2 (`vector validate` with pinned 0.43.1) exits 0.
8. **AC8 — parity fixtures**: Phase 3 step 3 (`vector-pii-scrub.test.sh`) exits 0.
9. **AC9 — records**: expenses.md Better Stack free-tier row Amount still `0.00`, Status still `free-tier`, Notes contain `second pass`, `198`, and `#5110`; no new `|` characters inside the cell; Responder DEFERRED row byte-identical to main. Post-mortem contains the `vinngest-v1.1.13` second-pass sentence.
10. **AC10 — PR body**: contains `Ref #5110` and `Ref #4296`; `grep -c 'Closes #5110'` → `0`; `grep -c 'Closes #4296'` → `0`; includes the deployment note and the AC13/AC14 verdict rules.
11. **AC11 — CI green**: `validate-vector-config.yml` PR run passes (fires automatically on the `vector.toml` path), including the disclosure-parity step (sink URI untouched → trivially green).

### Post-merge (operator)

12. **AC12 — deploy executed** (automation per step):
    a. Tag the merge commit: `git tag vinngest-v1.1.13 <merge-sha> && git push origin vinngest-v1.1.13`. Re-check first that `v1.1.13` is still the next semver (`git tag -l 'vinngest-v*' | sort -V | tail -1` → `vinngest-v1.1.12` at plan time); if another tag landed meanwhile, use the next free patch version everywhere `v1.1.13` appears. *Automation: feasible in-session (tag push triggers `build-inngest-bootstrap-image.yml`).*
    b. Image build run succeeds: `gh run list --workflow=build-inngest-bootstrap-image.yml --limit 1` → `completed/success`. *Automation: feasible (poll via Monitor).*
    c. Cloud-init pin-bump follow-up PR: `cloud-init.yml` `v1.1.12` → `v1.1.13` (ALL 4 occurrences; AC6 drift guard in `cloud-init-inngest-bootstrap.test.sh` requires pin == latest published tag; precedent PRs #5112/#4669). *Automation: feasible in-session.*
    d. Fire the deploy webhook with the canonical HTTPS HMAC form (PAYLOAD `{"command":"deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.1.13"}`, Doppler `soleur/prd_terraform` for `WEBHOOK_DEPLOY_SECRET` + CF Access creds; expect HTTP 202). *Automation: feasible, but prod write — requires explicit operator ack per `hr-menu-option-ack-not-prod-write-auth`.*
    e. Confirm clean reload: GET `/hooks/deploy-status` (signed empty string) → `exit_code: 0`; `vector_journal_tail` shows no config-load errors. *Automation: feasible (read-only).*
    f. Comment on #5110 noting the second-pass remediation deployed (PR number, tag, deploy timestamp) so the re-verdict has context. *Automation: feasible in-session.*
13. **AC13 — fast per-scrape verdict (~30 min post-deploy, ≥3 full scrape cycles; no 24h wait to detect a second overshoot)**:
    ```bash
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
      "SELECT toStartOfFiveMinutes(dt) AS bucket, count(*) AS c FROM remote(\$BS_TABLE) WHERE dt >= now() - INTERVAL 1 HOUR AND raw LIKE '%\"namespace\":\"host\"%' GROUP BY bucket ORDER BY bucket FORMAT JSONEachRow"
    ```
    Verdict rule: every fully-post-deploy bucket shows `c ≤ 86` (predicted ~69). Companion presence check (guards over-filtering): filesystem series still present —
    ```bash
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
      "SELECT count(*) AS c FROM remote(\$BS_TABLE) WHERE dt >= now() - INTERVAL 30 MINUTE AND raw LIKE '%\"namespace\":\"host\"%' AND raw LIKE '%filesystem%' FORMAT JSONEachRow"
    ```
    → `c > 0` (expect ~12 per bucket). If buckets `> 86` OR filesystem `= 0`, re-open immediately (next lever per Alternatives: drop filesystem collector entirely → 57/scrape, or drop the host_metrics source). *Automation: feasible (read-only query).*
14. **AC14 — daily quota verdict (the #5110 AC12-style gate)**: ≥24h after deploy (first full post-deploy day; `earliest=2026-06-12T16:00:00Z` already set on #5110), run the verdict command from the #5110 issue body. Verdict rule: first full post-deploy day shows `c ≤ 25,000` → comment **exactly** `RESULT: PASS` (own line) on #5110; the follow-through sweeper closes it (PASS grep precedes FAIL grep — verified). If `c > 25,000` → comment `RESULT: FAIL` with the new breakdown and re-open the work. *Automation: query feasible in-session; verdict comment per the operator-confirmed follow-through pattern.*
15. **AC15 — issue hygiene**: #5110 and #4296 still OPEN immediately after merge (no auto-close); #5110 closes ONLY via the sweeper after `RESULT: PASS`.

## Domain Review

**Domains relevant:** none requiring leader review — observability/infra volume tuning with no user-facing surface, no spend change ($0.00 stands), no new data processing (egress strictly decreases).

Assessment notes (semantic sweep performed inline; pipeline context — subagent spawning unavailable in this planning session, recorded for transparency):
- **Engineering/CTO**: the change itself; covered by this plan + CI gates + the two-stage post-deploy verdict.
- **Finance/CFO**: ledger row annotated; Amount/Status/upgrade-trigger unchanged. Recording an outcome, not making a financial decision (operator already decided "stay free tier" in the #5105 session).
- **Legal/CPO/Product/Marketing/Sales/People**: no user-facing surface; no disclosure drift (sink URI/source ID untouched — CI parity step pins the 4 legal disclosure surfaces); volume strictly decreases.

### Product/UX Gate

Not applicable — **NONE** tier. No file in Files to Edit matches any UI-surface glob (`components/**`, `app/**/page.tsx`, etc.); mechanical override did not fire.

## GDPR / Compliance Gate (Phase 2.7)

Skipped with note: no regulated-data surface touched (no schemas/migrations/auth/API routes/SQL) and none of the four expanded triggers fire (no new processing activity — egress to the existing sub-processor strictly decreases; threshold `none`; no new cron reading learnings/specs; no new distribution surface). The PII redaction pipeline in the same file is diff-locked by AC5.

## Infrastructure (IaC)

No NEW infrastructure — edits an existing IaC-managed config delivered through the established tag → OCI image → webhook pipeline. Documented because the apply path is multi-step and the PR body must state it.

### Terraform changes
None. `vector.tf` version pin unchanged (0.43.1). No new providers, variables, or secrets.

### Apply path
Existing-infra path (content rides the OCI image; no re-provisioning):
1. Merge PR → `main` contains trimmed `vector.toml`.
2. Push `vinngest-v1.1.13` tag on the merge commit → `build-inngest-bootstrap-image.yml` embeds `vector.toml` in the bootstrap image.
3. Follow-up cloud-init pin bump (`v1.1.12` → `v1.1.13`, 4 occurrences) keeps the AC6 drift guard green (pin must equal semver-max published tag — bump can only land AFTER the tag exists).
4. Operator-acked deploy webhook (`deploy inngest ... v1.1.13`) → `ci-deploy.sh` extracts `/vector.toml` (clears `/tmp/vector.toml` first — stale-reuse guard) → `inngest-bootstrap.sh` installs + restarts `vector.service`. Expected blast radius: ~5s inngest pause/drain/resume; Vector restart gap of seconds (metrics at 300s cadence anyway).

### Distinctness / drift safeguards
- `cloud-init-inngest-bootstrap.test.sh` AC6: pin == latest `vinngest-v*` tag (the reason step 3 follows step 2).
- `ci-deploy.sh:788-796` stale-`/tmp/vector.toml` guard ensures the NEW config lands rather than a cached prior copy.
- Fresh-host path (cloud-init) picks up the new image automatically once the pin bump merges.

### Vendor-tier reality check
Better Stack free tier: 3 GB/mo logs (3-day retention) + 30 GB metrics — this change exists precisely to stay inside it after the first attempt fell short. No paid-tier-gated resources created. Upgrade trigger remains "first paying customer" (ledger row).

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
  - mode: trim insufficient — rows/scrape still > 86 (third overshoot)
    detection: AC13 fast per-bucket query (~30 min post-deploy, deterministic c <= 86 rule) — no 24h wait
    alert_route: in-session post-deploy verification; re-open with next lever (drop filesystem collector / drop source)
  - mode: mountpoint allowlist over-filters — filesystem series vanish (glob semantics surprise)
    detection: AC13 companion presence query (filesystem rows > 0); disk-monitor.sh independently emails on / usage
    alert_route: in-session post-deploy verification step
  - mode: invalid host_metrics key ships
    detection: vector validate (AC7, pre-merge CI gate with pinned binary); byte-exact AC2 grep guards filter sub-key spelling (validate silently ignores sub-key typos)
    alert_route: PR check failure
  - mode: vector.service fails to restart on deploy
    detection: /hooks/deploy-status `vector_journal_tail` (AC12e)
    alert_route: in-session post-merge verification step
  - mode: quota warning recurs at 80%/100%
    detection: AC14 daily verdict on #5110 + Better Stack warning emails to ops@jikigai.com
    alert_route: operator email + re-opened remediation
logs:
  where: Better Stack Logs source 2457081 (eu-fsn-3), queryable via scripts/betterstack-query.sh (ClickHouse HTTP SQL)
  retention: 3 days (free tier)
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --limit 1
  expected_output: dt
```

The `discoverability_test.command` is the pre-merge-runnable liveness probe (proves Better Stack ingestion is alive and queryable, no SSH, no dashboard). The post-deploy QUOTA verdicts are AC13 (fast, ≤86/bucket) and AC14 (daily, ≤25k) — they cannot pass pre-deploy by construction.

## Test Scenarios

1. Unmodified-baseline sanity (RUN at plan time, both green): AC5 + AC6 diff commands return empty against the current tree — proves the verification commands work before the edit exists. (Plan-time self-review caught and fixed an AC6 false-fail: the inclusive sed range would have captured the changing Source 4 marker line; replaced with the exclusive awk form.)
2. Post-edit: AC1–AC9 all pass locally; CI `validate-vector-config.yml` passes on the PR.
3. Schema-strictness ground truth (RE-PROBED at deepen time against pinned 0.43.1 — see Enhancement Summary; do not re-run blindly at /work): the exact proposed Source 4 TOML on a /tmp copy → `vector validate` exit 0 (**PASS**); `mountpoints.include` (misspelled) → **ACCEPTED** (silent no-op); `mountpoints.includes = "/"` (string, not array) → **REJECTED**. Consequence: AC2's byte-exact grep is the spelling guard; AC13 is the runtime backstop.
4. Post-deploy: AC13 buckets ≤ 86 with filesystem present; AC14 first full day ≤ 25,000.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Third prediction miss — actual rows/scrape > 86 despite trim | Projection sums MEASURED per-collector counts (not modeled); 20% margin; AC13 fast verdict at ~30 min (not 24h) with a pre-agreed next lever (drop filesystem → 57/scrape measured-derived, or drop the source) |
| `mountpoints.includes` over-filters (filesystem series vanish) | AC13 companion presence query (`filesystem` rows > 0); `disk-monitor.sh` independently emails on `/` at 80%/95% (5-min timer); reversible one-line change |
| `mountpoints.includes` under-filters (glob/runtime semantics differ from docs) | Filter contract verified against vector.dev docs (2026-06-10) AND the exact proposed TOML binary-validated THIS pass on pinned 0.43.1 (positive probe exit 0); even a fully no-op mountpoint filter still lands ~165/scrape → caught by AC13 within ~30 min |
| Misspelled filter sub-key ships despite green CI | AC2 byte-exact grep (validate silently ignores sub-key typos — probe-verified); AC13 runtime backstop |
| Losing network metrics hides a future network incident | No alert/runbook consumes Better Stack network series today; uptime monitors (external probe) + Sentry + deploy-status carry incident-grade signal; re-add path: `collectors += "network"` + `[sources.host_metrics.network] devices.includes = ["eth0"]` ≈ +8 rows (still ≤86) |
| Losing /tmp, /var/tmp, /boot/efi filesystem series | Low-signal mounts; /tmp-full incidents surface via service errors in WARN+ journald (shipped) and Sentry; accepted by design, reversible by widening the allowlist (+4 rows per mount) |
| Pin-bump window: between tag push (AC12a) and pin-bump merge (AC12c), other infra PRs touching drift-guard paths fail AC6 | Execute a–c back-to-back in the post-merge session (minutes-wide window; precedent #5112/#4669) |
| Stale `RESULT: FAIL` comment on #5110 blocks sweeper close | Verified: sweeper script greps `^RESULT: PASS$` FIRST — a later PASS closes despite the earlier FAIL |

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Pay for Better Stack tier | Operator-rejected (#5105 session); ledger upgrade trigger ("first paying customer") not fired. $0.00 stands |
| Drop the host_metrics source entirely | Loses ALL CPU/mem/disk diagnosis the source exists for (#4250); measured trim reaches threshold with 20% margin while keeping the load-bearing signals. Reserved as the FINAL lever if AC14 fails again |
| Exclude only the 21 virtual mountpoints (`mountpoints.excludes`) | Arithmetic: 198 − 84 = ~114/scrape ≈ ~33k/day — still over the 25k threshold (the verdict comment's own projection). Also denylist rots as new virtual fs appear; allowlist is closed by construction |
| Drop filesystem AND network collectors (issue's literal suggestion) | 57/scrape ≈ 16.4k/day — viable, but loses `/mnt/data` capacity charting that NO other monitor covers (`disk-monitor.sh` watches only `/`). The 3-mount allowlist costs +12 rows and keeps that signal; both land under threshold |
| Keep network with `devices.includes = ["eth0"]` | +8 rows → ~77/scrape ≈ 22.2k/day — only 11% margin after a 2.9× prior prediction miss, for series nothing consumes. Documented as the re-add path instead |
| Widen scrape interval again (300s → 600s/900s) | 198 × 144 = ~28.5k/day at 600s — STILL over threshold without a trim; 900s (15-min granularity) degrades the diagnosis cadence for every collector instead of cutting dead series |
| Filter in a VRL transform instead of at source | Violates the transforms byte-for-byte invariant; source-side filters are the documented native mechanism and ship zero bytes instead of dropping post-scrape |

Note: the #5105 plan's alternatives table rejected "Trim `collectors` list" — that judgment is reversed here by measurement (the interval lever is spent; remaining volume is collector-shaped). No deferred-scope items requiring new tracking issues: #5110 (verdict tracker) and #4296 (strategic re-decision) already exist and stay open.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — section above is complete with an explicit `threshold: none, reason: ...` scope-out bullet.
- `vector validate` does NOT guard filter sub-key spelling (`mountpoints.include` misspelling would be a silent no-op) — AC2's byte-exact grep is load-bearing; do not "simplify" it away.
- Do NOT touch `scrape_interval_secs = 60` under `[sources.vector_internal]` — AC4's second grep pins it.
- The expenses row append must not introduce `|` characters (markdown table cell).
- `Ref #5110` / `Ref #4296` in the PR body only — never `Closes` (#5110 must outlive the merge; closure is sweeper-gated on `RESULT: PASS`, per `wg-use-closes-n-in-pr-body-not-title-to` + the ops-remediation extension).
- Tag `vinngest-v1.1.13` must point at the MERGE commit on main — an image built from a pre-merge ref ships the OLD vector.toml.
- The `RESULT: PASS` comment must be exactly that string on its own line (sweeper greps `^RESULT: PASS$`).
- The new Source 4 comment must not contain the literal `30s scrape` (the #5105 AC5 stale-comment guard precedent); `300s scrape` is safe (not a substring match).

## References

- Verdict comment (AC12 FAIL evidence): <https://github.com/jikig-ai/soleur/issues/5110#issuecomment-4673409548>
- Vector host_metrics docs: <https://vector.dev/docs/reference/configuration/sources/host_metrics/> (filter syntax verified 2026-06-10 for #5105; carried forward same-day)
- Prior plan (template + binary-probe ground truth): `knowledge-base/project/plans/archive/20260610-140837-2026-06-10-fix-betterstack-quota-vector-host-metrics-tuning-plan.md`
- PIR: `knowledge-base/engineering/operations/post-mortems/betterstack-quota-near-miss-postmortem.md`
- Learnings: `knowledge-base/project/learnings/2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md`, `knowledge-base/project/learnings/2026-05-22-vector-vrl-config-gates-and-pii-redaction-pipeline.md`
- Runbooks: `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`, `knowledge-base/engineering/operations/runbooks/inngest-server.md` (upgrade path; SSH-form examples superseded by the HTTPS webhook form per `hr-no-ssh-fallback-in-runbooks`)
- Prior art: PR #5105 (first remediation), PR #5112 / #4669 (pin-bump precedent), #4675/#4676 (AC6 drift guard), #4250 (host metrics added), #4293 (PII pipeline + CI gates), #4296 (observability consolidation 60-day re-decision — stays open)
