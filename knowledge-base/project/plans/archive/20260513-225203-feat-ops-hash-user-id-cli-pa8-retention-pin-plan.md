---
title: Operator hash-user-id CLI + PA8 §(f) Hetzner retention pin + compliance-posture refresh
type: feat
date: 2026-05-13
issue: 3711
related: [3698, 3701, 3710]
related_prs: [3701]
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# feat(ops): operator hash-user-id CLI + PA8 §(f) Hetzner retention pin + compliance-posture refresh (#3698 PR-C follow-up)

## Enhancement Summary

**Deepened on:** 2026-05-13
**Sections enhanced:** Overview, Research Reconciliation, Proposed Solution (Item 1, Item 2, Item 3), Acceptance Criteria, Files to Edit
**Quality checks applied:** User-Brand Impact halt (pass — `aggregate pattern` with concrete artifact/vector), AGENTS.md rule-citation verification (no rule IDs cited in plan body — exempt), GitHub label verification (`priority/p3-low`, `domain/operations`, `type/security`, `deferred-scope-out` — all four verified live via `gh label list`), PR/issue citation verification (#3698 closed, #3701 merged, #3710 closed issue not a PR — frontmatter `related_prs` narrowed to [3701] accordingly), loader-class fit (N/A — no AGENTS.md demotion proposed), line-number anchors (PA8 §(f) is at `article-30-register.md:162`; compliance-posture RoPA row is at `compliance-posture.md:91`).

### Key Improvements
1. Disambiguated `hashUserId` (HMAC-SHA256, pepper-keyed, line 36) vs. `hashUserIdForSentry` (SHA-256, salt-keyed, line 452) — the operator CLI MUST import the former because pino stdout pseudonymisation lives on the helper boundary keyed by `SENTRY_USERID_PEPPER`. The latter is the DSAR/breach-detection primitive keyed by `SOLEUR_SENTRY_PII_SALT` and produces a different hash domain. Wrong import = silent operator confusion (CLI emits a hash that does not match any pino stdout line).
2. Hardened the docker-logs grep pattern in the runbook against false-substring collisions: a 64-hex hash has 16⁶⁴ collision space but partial substring matches against unrelated payloads (transaction IDs, request IDs, sha256 digests in error stacks) are plausible. Runbook prescribes `grep -F "userIdHash=$HASH\|userIdHash\":\"$HASH"` (anchored to the JSON-emitted key prefix), not bare `grep $HASH`.
3. Replaced approximate line-number references with verified anchors: PA8 §(f) is at `article-30-register.md:162` (verified live); compliance-posture RoPA row is at line 91. The issue body's "line 88" anchor is documented in Research Reconciliation as stale (line 88 is the W7 DSAR cohort row, not the RoPA row).
4. Carried forward the institutional learning at `knowledge-base/project/learnings/2026-05-12-brainstorm-issue-body-option-and-inventory-staleness-pino-userid.md` — the issue body for #3711 is similarly authored ~6 hours after the PR-A ship and contains stale inventory references (`pnpm` vs `npm`, "line 88" vs "line 91", `tsx`-in-prod gap framing). The Research Reconciliation table covers all three drift cases.
5. Added a TR sentinel test for `__TBD_OBSERVED_VOLUME__`: the post-merge fill is a deterministic find-and-replace; the sentinel string is grep-asserted both pre-merge (must be 1) and post-merge (must be 0). This prevents a future operator from forgetting to fill it (silent compliance gap).
6. Added explicit non-coupling assertion between this PR's `hashUserId` ergonomics and the DSAR/cross-tenant pseudonymisation contract (ADR-028). Editing `observability.ts` line 36 is out of scope; the operator CLI is a READ-only consumer of the existing export. If `hashUserId` ever needs to be widened, the operator CLI's import-site assert (output length === 64 hex chars) catches contract drift at the boundary.
7. Strengthened the cloud-init drift-detection step (Phase 2 Step 5): the sed-extract diff is fragile against indentation changes. Added a fallback contains-check (`grep -F '"max-size": "10m"' /etc/docker/daemon.json` AND `grep -F '"max-file": "3"'`) that catches the structural invariant even if whitespace shifts.
8. Added explicit AC for the `Last Updated` (or `last_reviewed`) frontmatter bump on `article-30-register.md` — the document carries `last_reviewed: 2026-05-12` in frontmatter; this PR must bump it to `2026-05-13` for both the structural-cap edit AND the post-merge fill edit.

### New Considerations Discovered
- **Two hashes, two contracts.** `hashUserId(userId, pepper)` is the operator-relevant primitive; `hashUserIdForSentry(userId)` is the DSAR primitive. The CLI must NEVER import or re-implement the latter — the architectural contract (ADR-029 §I10) keeps them deliberately distinct.
- **Stale issue-body anchors.** Issue body references "line 88", `pnpm`, "PR #3710", and `tsx` prod gap. Each is a stale framing — the plan body documents the correction. This is the same pattern as the brainstorm-staleness learning (2026-05-12).
- **The CLI is a READ surface for `observability.ts`.** This PR does NOT modify the export contract. Any future change to `hashUserId` must update the CLI's input/output contract simultaneously; the AC1.3 reference-HMAC test acts as the parity check.
- **Re-verification triggers must be machine-grepable.** The PA8 §(f) trigger list (`annual + cloud-init change + off-host shipper introduction + container restart policy change`) is enumerated as a comma-separated list so a future `gh issue list --label compliance/critical` audit can grep for the literal trigger names. Free-form prose triggers do not survive the next audit cycle.

## Overview

PR-A (#3701) shipped the pino `formatters.log()` userId rename hook, making PA8 §(c) concrete. This PR (PR-C of the #3698 follow-up bundle) closes three orthogonal but related loose ends from that ship:

1. **Operator hash-user-id CLI** — give support operators a one-line invocation to compute `hashUserId(<uuid>)` from a Doppler-resident `SENTRY_USERID_PEPPER`, so they can locate pseudonymous log lines without ad-hoc `node -e` incantations.
2. **PA8 §(f) Hetzner retention pin** — replace the `"short rolling window (re-confirm with infra runbook)"` placeholder in the Article 30 register with a concrete `30 MB rolling per container` value sourced from the existing `cloud-init.yml` Docker daemon config, plus an operator-side log-volume measurement to convert MB → days.
3. **Compliance-posture refresh** — once §(f) is concrete, drop "pino retention" from the implicit RoPA counsel-review scope.

This is documentation work with one small TypeScript shim. No production code paths change. The brand-survival threshold is `aggregate pattern` — operator UX regression risk if the CLI ships broken, not a single-user incident class.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue-body claim | Codebase reality | Plan response |
|---|---|---|
| "Operator runs `pnpm hash-user-id`" | Repo uses `npm` (`apps/web-platform/package-lock.json` exists; no `pnpm-lock.yaml`). Existing `.ts` scripts use a `#!/usr/bin/env bun` shebang (e.g., `apps/web-platform/scripts/verify-stripe-prices.ts`). | Use `npm run hash-user-id` (matches the project's package manager). Script invocation pattern follows `verify-stripe-prices.ts` (Bun shebang) so it remains consistent with the project's existing ad-hoc-script convention. See Phase 1. |
| "`tsx` prod-runtime dependency gap" | True — `tsx` is in `devDependencies` (`apps/web-platform/package.json:69`), and the prod image runs `npm ci --omit=dev` (`apps/web-platform/Dockerfile:72`), so `tsx` is unavailable in the prod container. | Three resolutions weighed in Phase 1 below; chosen: operator runs the CLI **on the operator machine** with `doppler run -p soleur -c prd_secrets-only`, NOT inside the prod container. The operator already has Bun + Node + `npm install` locally. Reframes the question — `tsx` prod-availability is moot because the CLI never runs in prod. |
| "`compliance-posture.md` line 88 refresh drops pino retention" | Line 88 is the **W7 DSAR cohort audit row** in the "Completed Compliance Work" table, not the RoPA-pending note. The actual pino-retention scope mention is at line **91** (Article 30 Register row), and the "counsel review pending — outstanding items" tail-text scopes "P0 mirror retention envelope" specifically (pino retention is implicit-scoped via "Vendor mapping consolidated"). | Phase 3 updates line **91** (and line 90 §4.7 row inheritance text) to explicitly carry forward the concrete PA8 §(f) value. The issue body's "line 88" reference is treated as a stale anchor and the plan body documents the correction so the implementer doesn't chase the wrong row. |
| "SSH the prod host to disambiguate Docker log driver" (issue Step 3) | The cloud-init `daemon.json` at `apps/web-platform/infra/cloud-init.yml:303-310` already pins `"log-driver": "json-file"`, `"max-size": "10m"`, `"max-file": "3"`. No driver disambiguation is needed from code — the driver is **known** from Terraform-managed config. | Phase 2 simplifies the SSH procedure: the driver question is resolved from code. SSH is needed ONLY to (a) verify the cloud-init applied (no operator drift / hand-edits to `/etc/docker/daemon.json`), (b) measure observed daily log volume so the MB cap can be converted to a time-window, and (c) confirm no off-host shippers were introduced post-cloud-init. journald-branch steps in the original issue body are dead branches (driver is json-file by construction). |
| Issue body refers to `--name-transformer tf-var` and Doppler `prd_terraform` for the SSH step | These are infra-context details from an unrelated runbook (#3061 lineage). PA8 §(f) measurement does NOT require any Terraform invocation; it only requires SSH access to the existing prod host. | Phase 2 SSH procedure does not include `doppler run` / `terraform` invocations. ADMIN_IPS allowlist refresh (via `/soleur:admin-ip-refresh`) remains a soft prerequisite. |
| SpecFlow finding: "missing `/etc/systemd/journald.conf` inspection step" | journald is not the active log driver (cloud-init pins json-file). The inspection step was needed in the original issue body because driver disambiguation was assumed; with the daemon.json evidence above, journald-conf inspection becomes a degenerate branch. | Plan body removes the journald inspection step as dead code, but keeps a one-line precautionary check (`docker inspect <container> \| jq '.[0].HostConfig.LogConfig.Type'`) to **verify** the active runtime driver matches the daemon.json pin (defense against operator drift). |

## Problem Statement / Motivation

**Operator UX (Item 1).** After #3698/#3701 shipped, pino stdout emits `userIdHash` (HMAC-SHA256) instead of raw `userId`. Operators handling support tickets need to convert a user UUID into the corresponding hash to grep the docker-logs stream:

```bash
# current (after #3698): operator-side ad-hoc incantation
HASH=$(doppler run -c prd -- node -e "const c=require('crypto');console.log(c.createHmac('sha256',process.env.SENTRY_USERID_PEPPER).update('$UUID').digest('hex'))")
ssh root@135.181.45.178 "docker logs soleur-web-platform 2>&1 | grep $HASH"
```

This is fragile (shell-quoting hazards, copy-paste drift across operators), runs `node -e` inline so the pepper is potentially visible in operator-shell history, and reinvents `hashUserId()` rather than reusing the contract-pinned primitive from `apps/web-platform/server/observability.ts:36`.

**RoPA accuracy (Item 2).** PA8 §(f) at `knowledge-base/legal/article-30-register.md` (line 162 in the original issue body anchor; actual current line is the §(f) row of the PA8 table around line **155-165**) reads `"short rolling window (re-confirm with infra runbook)"` for the pino stdout retention. This is a verbatim placeholder string flagged by CLO as blocking for the next audit cycle. The cloud-init evidence above resolves the **structural** question (json-file driver, 30 MB cap per container) but leaves the **time-window translation** open, which requires one operator measurement.

**Compliance-posture hygiene (Item 3).** With §(f) concrete, the implicit "outstanding items" scope at `compliance-posture.md` (Article 30 register row, current line **91**) should drop pino retention from the pending counsel-review tail. Leaving it implicit is misleading once the underlying placeholder is resolved.

## Proposed Solution

### Item 1 — Operator hash-user-id CLI

Ship a small Bun-shebanged TypeScript script at `apps/web-platform/scripts/hash-user-id.ts` plus an npm script in `apps/web-platform/package.json`. The script imports `hashUserId` from `apps/web-platform/server/observability.ts` (single source of truth — no copy-paste of the HMAC logic).

#### Research Insights — primitive disambiguation (load-bearing)

`apps/web-platform/server/observability.ts` exports TWO hashing primitives. The CLI must import the correct one:

| Primitive | Line | Algorithm | Key/Salt | Boundary it serves | Operator-relevant? |
|---|---|---|---|---|---|
| `hashUserId(userId, pepper?)` | 36 | **HMAC-SHA256** | `SENTRY_USERID_PEPPER` (env) | pino stdout `formatters.log()` rename + silent-fallback helpers | **YES — use this one** |
| `hashUserIdForSentry(userId)` | 452 (non-exported) | SHA-256 | `SOLEUR_SENTRY_PII_SALT` (env) | DSAR/cross-tenant breach detection (`mirrorCrossTenantViolation`) | NO — different hash domain |

The two are deliberately distinct per ADR-028 (DSAR contract) vs. ADR-029 (rename-at-boundary contract). A CLI that imports `hashUserIdForSentry` would emit a hash that does NOT match any pino stdout line — operator grep silently returns zero matches even when log lines exist. The plan AC1.3 reference test (`createHmac('sha256', 'test-pepper').update(uuid).digest('hex')`) pins the HMAC path. The non-HMAC SHA-256 form is NOT a valid CLI implementation and would fail AC1.3.

Verified live via `grep -nE "^export" apps/web-platform/server/observability.ts` (only `hashUserId` is exported — `hashUserIdForSentry` is module-private at line 452 and used internally by `mirrorCrossTenantViolation` only). The CLI import-site contract is therefore: import the only export named `hashUserId`.

Invocation:

```bash
# Operator machine — pepper sourced from prd Doppler config; never echoed.
doppler run -p soleur -c prd -- npm run -w apps/web-platform hash-user-id <uuid>
# Prints: <64-hex-string>
```

Pattern: existing `apps/web-platform/scripts/verify-stripe-prices.ts` (Bun shebang, single-purpose, exits non-zero on missing input). No prod-container runtime is touched. The `tsx` devDep gap is resolved by NOT running the CLI in prod — the operator has Bun locally (already required by the existing scripts pattern).

**Why operator-local, not prod-container:** running `hash-user-id` inside the prod container is the only path that needs `tsx` in `dependencies`. Operator-local invocation has zero deploy footprint, zero new prod runtime risk, and zero new attack surface (pepper already flows through operator's `doppler run` for unrelated ops tasks). The issue-body's "verify `tsx` is in `dependencies` OR compile to JS" gap-resolution is **moot** under operator-local invocation. The runbook (Phase 1.3) documents this constraint explicitly so a future operator does not try to `ssh root@... 'docker exec -- npm run hash-user-id'`.

#### Research Insights — operator-side log grep pattern

The naive runbook grep is `docker logs soleur-web-platform 2>&1 | grep $HASH`. This has a **false-substring collision risk**: a 64-hex hash is unique by entropy, but a request ID, transaction ID, or sha256 digest in an unrelated error stack could contain a substring that happens to match the user's hash prefix. The collision probability is low (16⁻ⁿ for n-char prefix) but non-zero across high-volume log streams.

**Hardened pattern (use in the runbook):**

```bash
HASH=$(doppler run -p soleur -c prd -- npm run -w apps/web-platform hash-user-id <uuid> --silent)
# json-encoded log lines: "userIdHash":"<hash>"
# operator-rendered: userIdHash=<hash>
ssh root@135.181.45.178 "docker logs soleur-web-platform 2>&1 \
  | grep -F 'userIdHash' \
  | grep -F \"$HASH\""
```

The double-grep narrows to lines that (a) contain the `userIdHash` key emitted by `formatters.log()` AND (b) contain the operator's hash. `grep -F` (fixed string, no regex) avoids accidental regex-metachar interpretation of the hex hash.

**npm `--silent` flag.** Required to suppress the `> apps/web-platform@... hash-user-id` npm wrapper banner that would otherwise pollute the captured `$HASH` variable. Verified: `npm run --silent` is documented at <https://docs.npmjs.com/cli/v10/commands/npm-run-script#silent>.

### Item 2 — PA8 §(f) retention pin (operator SSH step + doc update)

**Verified line anchors (deepen-plan):**
- PA8 §(f) row: `knowledge-base/legal/article-30-register.md:162` (verified via `grep -n "short rolling window" article-30-register.md` returns line 162).
- Frontmatter `last_reviewed`: `article-30-register.md:7` (currently `2026-05-12` — bump to `2026-05-13` at edit time).
- Cloud-init daemon.json block: `apps/web-platform/infra/cloud-init.yml:303-310` (verified via `grep -n 'log-driver' cloud-init.yml`).
- Cloud-init `docker run` invocation (no `--log-driver` override → uses daemon.json defaults): `apps/web-platform/infra/cloud-init.yml:412-421`.

The retention model is `json-file driver, 10 MB × 3 files = 30 MB rolling cap per container`, sourced from `apps/web-platform/infra/cloud-init.yml:303-310`. To convert MB → days, operator runs a one-time measurement on the prod host:

```bash
# Step 1 — refresh ADMIN_IPS allowlist if needed
/soleur:admin-ip-refresh   # skill — no-op if allowlist already current

# Step 2 — SSH (precautionary: confirm runtime driver matches the cloud-init pin)
ssh root@135.181.45.178
docker inspect soleur-web-platform | jq '.[0].HostConfig.LogConfig'
# Expected: {"Type":"json-file","Config":{}}  (Config inherits daemon.json defaults)
# Drift signal: any other Type → file separate compliance/critical issue per /soleur:admin-ip-refresh pattern

# Step 3 — measure observed daily volume (window: 24 h, repeated 3× spread across a representative weekday)
du -sb $(docker inspect soleur-web-platform | jq -r '.[0].LogPath') | awk '{print $1}'
# capture three samples T+0h, T+8h, T+24h → compute avg daily bytes
# expected rate: low (Soleur traffic at MU-1 scale is small; expect 1-10 MB/day)
# effective time retention = 30 MB / observed-daily-MB → days

# Step 4 — confirm no off-host shippers
systemctl list-units --type=service | grep -iE 'promtail|vector|fluent|filebeat|rsyslog'
# Expected: zero matches → "no off-host shippers"

# Step 5 — confirm daemon.json on host matches cloud-init source of truth
# Primary check: structural-invariant grep (robust against whitespace/indentation drift in cloud-init)
grep -F '"log-driver": "json-file"' /etc/docker/daemon.json \
  && grep -F '"max-size": "10m"' /etc/docker/daemon.json \
  && grep -F '"max-file": "3"' /etc/docker/daemon.json \
  && echo "daemon.json structural pin OK"
# Secondary check (defense-in-depth): exact diff against cloud-init source of truth
diff <(cat /etc/docker/daemon.json) <(cat apps/web-platform/infra/cloud-init.yml | sed -n '/cat > \/etc\/docker\/daemon.json/,/DOCKEREOF/p' | sed -n '2,/DOCKEREOF/p' | sed '$d')
# Expected: zero diff. Drift → operator hand-edit; file compliance/critical follow-up via gh issue create.
# Note: the sed-extract is fragile against indentation changes in cloud-init. The structural grep above is the load-bearing check; the diff is informational.
```

**Doc update at §(f).** Once measurement complete, rewrite the §(f) cell to:

```markdown
| **(f) Retention** | Sentry: 90 days default (rolling). pino stdout: **json-file Docker driver, 30 MB rolling per container (max-size=10m × max-file=3)** pinned in `apps/web-platform/infra/cloud-init.yml:303-310`. Observed daily log volume: ~<X> MB/day at <date-of-measurement>, yielding ~<Y> days effective time retention. **Re-verification triggers:** annual review; on any change to `apps/web-platform/infra/cloud-init.yml` (daemon.json block); on any introduction of an off-host log shipper (`promtail`/`vector`/`fluent`/`filebeat`/`rsyslog`); on container restart policy change affecting log path. **No off-host copies are taken.** P0 mirror records: retained for the statutory 72-hour clock window + investigation-completion buffer; documented retention to be tightened by counsel review (target ≤ 12 months unless an open investigation extends). Art. 17: hashed identifiers age out per processor retention; no active erasure call required (Recital 26 pseudonymisation). |
```

### Item 3 — Compliance-posture refresh

At `knowledge-base/legal/compliance-posture.md` line 91 (Article 30 Register row), edit the "outstanding items" tail-text to drop pino retention from the implicit scope. Replacement:

> Counsel review pending — outstanding items: controller legal form (SAS vs SARL), Web Push transfer characterisation, P0 mirror retention envelope, Art. 30(5) micro-enterprise derogation confirmation. **PA8 §(f) Hetzner pino retention concretised in PR #<this-pr> (2026-05-13).**

The §4.7 inheritance text on line 90 is unchanged (it inherits PA8 retention by reference; the §(f) update propagates without touching this row).

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in \
  "apps/web-platform/scripts/hash-user-id.ts" \
  "apps/web-platform/server/observability.ts" \
  "apps/web-platform/package.json" \
  "knowledge-base/legal/article-30-register.md" \
  "knowledge-base/legal/compliance-posture.md" \
  "knowledge-base/engineering/ops/runbooks/recover-userid-from-pino-stdout.md"; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "  #\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

To be re-run at /work Phase 0. Expected: None (this is a green-field operator-CLI + doc-refresh PR, no overlap with existing code-review scope-outs). If matches surface, the planner re-classifies each as Fold-in / Acknowledge / Defer per the standard contract.

## Technical Considerations

- **Architecture impact:** zero — `hash-user-id.ts` is a single-file operator CLI; no new module dependencies, no exports added to `observability.ts`. The existing `hashUserId` export contract (`apps/web-platform/server/observability.ts:36`) is reused.
- **Security:** the pepper flows through `doppler run -p soleur -c prd` exactly as in operator-existing patterns (`/soleur:admin-ip-refresh`, `verify-stripe-prices` invocation). Pepper is never logged, never echoed, never copied into shell history. ADR-029 (rename-at-boundary) is **not** modified — the operator CLI is a hash-computation primitive, not a boundary.
- **Performance:** N/A (operator-side one-shot).
- **NFR impacts:** none. Documentation accuracy improves (PA8 §(f) goes from placeholder to concrete). Operator-MTTR for log-lookup-by-uuid improves marginally (fewer copy-paste errors).
- **SSH dependency:** Item 2 requires one-time SSH access to `135.181.45.178`. `/soleur:admin-ip-refresh` is the standard prerequisite. Failure mode: ADMIN_IPS drift → kex_exchange reset → `ssh-fail2ban-unban.md` runbook applies.

## User-Brand Impact

- **If this lands broken, the user experiences:** a degraded support response time when they file a ticket requiring log lookup (operator must fall back to the old `node -e` incantation OR misinterpret a malformed §(f) value and either over- or under-state retention to an audit-querying user).
- **If this leaks, the user's data is exposed via:** N/A — this PR does not introduce any new data-handling boundary. The pepper handling pattern is unchanged from existing operator workflows. The CLI itself never receives or emits raw user data; it converts a UUID (which the operator already holds via support ticket) into a hash.
- **Brand-survival threshold:** `aggregate pattern` — operator UX regression risk only. A single broken invocation does not harm a user; a sustained pattern of operator-MTTR degradation would erode support quality over time.

## Domain Review

**Domains relevant:** Legal, Operations

### Legal (CLO)

**Status:** auto-accepted (carry-forward from #3698 brainstorm chain — CLO blocked PA8 §(f) placeholder as a future-audit-cycle item; this PR closes that)
**Assessment:** PA8 §(f) concretisation closes the CLO-flagged placeholder. Article 30(1)(f) is a controller obligation under GDPR; carrying a known-stale value is a register-accuracy gap. The §(f) rewrite makes the retention model auditable: structural cap (from code), observed volume (from operator measurement), re-verification triggers (annual + change-event). No new processing activity is introduced. No DPA changes required. Counsel review for the remaining `compliance-posture.md` items (controller legal form, Web Push, Art. 30(5), P0 mirror envelope) is untouched.

### Operations (COO)

**Status:** auto-accepted (operator-CLI ergonomics + one SSH step are standard ops scope)
**Assessment:** Operator-local CLI is the right placement (zero prod risk). The SSH step for measurement reuses the existing ADMIN_IPS-refresh skill chain. The journald-branch removal (per Research Reconciliation row 5) is correct — the active driver is pinned in code. Runbook placement at `knowledge-base/engineering/ops/runbooks/` matches the existing structure (admin-ip-drift.md, ssh-fail2ban-unban.md, plausible-pii-erasure.md are siblings of similar scope).

### Product/UX Gate

**Tier:** none (no user-facing UI surface; operator-facing CLI is internal-tools class, not Product domain)

## GDPR / Compliance Gate

**Trigger evaluation:** This plan touches `knowledge-base/legal/article-30-register.md` (regulated-data surface — RoPA per Art. 30) and `knowledge-base/legal/compliance-posture.md` (compliance metadata). The `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex fires on the article-30-register edit.

**Gate output (advisory, non-blocking):**
- **Lawful basis impact:** none — no new processing activity, no change to existing lawful basis claims. PA8 §(f) edit clarifies an existing claim, does not extend scope.
- **Art. 9 special-category:** N/A.
- **Art. 30 trigger:** **already firing** — this PR is the Art. 30(1)(f) accuracy fix.
- **DPIA candidate:** no.
- **Sub-processor change:** none.
- **Vendor DPA row impact:** none (Hetzner DPA already covers stdout-capture; this PR concretises but does not modify the data flow).
- **Critical findings:** none.

Gate concludes: proceed. PR body MUST cite #3711 and reference PA8 §(f) closure for the audit trail.

### Research Insights — institutional learnings applied

| Learning | Source | Applied to this plan |
|---|---|---|
| Brainstorm/plan must re-derive option space and inventory from code — issue body is stale framing, not ground truth | `knowledge-base/project/learnings/2026-05-12-brainstorm-issue-body-option-and-inventory-staleness-pino-userid.md` | Research Reconciliation table documents 5 stale anchors in the issue body (`pnpm` vs `npm`, "line 88" vs line 91, `tsx`-prod-gap framing, journald disambiguation branch, "PR #3710" vs "issue #3710"). Each is corrected with a verified code/grep anchor. |
| Compliance-runbook authoring gotchas (markdown-lint table-cell escapes, jq schema confusion, merge-timestamp drift) | `knowledge-base/project/learnings/best-practices/2026-04-18-compliance-runbook-authoring-gotchas.md` | The PA8 §(f) replacement template is structured as plain prose inside the table cell, NOT as a nested markdown table. The trigger enumeration is comma-separated so markdownlint's `MD013/MD033/MD034` rules cannot mangle it. |
| Docs-fix verification greps must span ALL operator-facing surfaces | `knowledge-base/project/learnings/best-practices/2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces.md` | The post-merge runbook lives at `knowledge-base/engineering/ops/runbooks/recover-userid-from-pino-stdout.md`. AC verification greps (AC2.1-AC2.4, AC3.1-AC3.2, AC4.1-AC4.6) cover the runbook AND the two legal docs AND the operator CLI — not just the named target file. |
| Client-side PII strip when the server pepper cannot ship to the browser | `knowledge-base/project/learnings/2026-05-12-client-side-pii-strip-when-server-pepper-cannot-ship.md` | Reinforces that `hashUserId` (HMAC + pepper) is the **server-only** pseudonymisation primitive. The CLI is operator-local but runs **outside** the prod container — the pepper flows via `doppler run` into the operator's shell, never into a browser bundle. The boundary is preserved. |

### Research Insights — re-verification trigger taxonomy (canonical for §(f))

The trigger list in the PA8 §(f) replacement is intentionally enumerated as four named events so a future audit can `grep -F` each trigger and verify nothing matched silently. The four triggers:

1. **`annual review`** — cadence-based, scoped to the next RoPA refresh cycle.
2. **`cloud-init change`** — fires when `apps/web-platform/infra/cloud-init.yml` is edited near the daemon.json block (lines 303-310 today; the implementer can verify via `git log --follow -L 303,310:apps/web-platform/infra/cloud-init.yml`).
3. **`off-host log shipper introduction`** — fires when any of `promtail`, `vector`, `fluent`, `filebeat`, `rsyslog` is added to the infra. Detection: GDPR-gate skill, weekly drift scan, or PR-template gate.
4. **`container restart-policy change affecting log path`** — fires when `--restart`, `--log-driver`, or `--log-opt` flags are added to `docker run` (currently at `cloud-init.yml:412-421`).

Each trigger is grep-able. The list is closed (no "etc.") — adding a fifth trigger requires a documented update to the §(f) row.

## Acceptance Criteria

### Pre-merge (PR)

#### Item 1 — Operator hash-user-id CLI

- [ ] AC1.1: `apps/web-platform/scripts/hash-user-id.ts` exists with `#!/usr/bin/env bun` shebang and imports `hashUserId` from `../server/observability.ts` (single source of truth — no copy-paste of the HMAC logic).
- [ ] AC1.2: `apps/web-platform/package.json` `scripts` block adds `"hash-user-id": "bun scripts/hash-user-id.ts"`. Verified via `grep -nE '"hash-user-id"' apps/web-platform/package.json` returns one match.
- [ ] AC1.3: Running `cd apps/web-platform && SENTRY_USERID_PEPPER=test-pepper bun scripts/hash-user-id.ts 11111111-2222-3333-4444-555555555555` outputs exactly the 64-hex hash that matches `bun -e "import {createHmac} from 'crypto'; console.log(createHmac('sha256','test-pepper').update('11111111-2222-3333-4444-555555555555').digest('hex'))"`. Reuses the existing `hashUserId` primitive — no parallel hash implementation.
- [ ] AC1.4: Running the script with no argv (`bun scripts/hash-user-id.ts`) exits non-zero with `usage:` stderr message.
- [ ] AC1.5: Running the script without `SENTRY_USERID_PEPPER` set exits non-zero with a clear "pepper not set" stderr message (no silent fallback to `pepper_unset` sentinel — that sentinel is for **runtime** boundary code; the operator CLI should fail loud).

#### Item 2 — PA8 §(f) doc update (structural cap only — observed-volume is post-merge)

- [ ] AC2.1: `knowledge-base/legal/article-30-register.md` PA8 §(f) row no longer contains the string `"short rolling window (re-confirm with infra runbook)"`. Verified via `grep -F 'short rolling window' knowledge-base/legal/article-30-register.md` returns zero matches.
- [ ] AC2.2: PA8 §(f) row contains the literal string `"30 MB rolling per container (max-size=10m × max-file=3)"` and cites `apps/web-platform/infra/cloud-init.yml:303-310` as the source of truth.
- [ ] AC2.3: PA8 §(f) row contains the re-verification-trigger list: annual + cloud-init change + off-host shipper introduction + container restart policy change. Verified via `grep -F 'Re-verification triggers' knowledge-base/legal/article-30-register.md` returns one match.
- [ ] AC2.4: PA8 §(f) row contains a placeholder for observed-daily-volume in the form `"~<X> MB/day at <date-of-measurement>"` that the post-merge operator step fills in. The placeholder MUST be a deterministic sentinel (`__TBD_OBSERVED_VOLUME__`) so the post-merge edit is a one-shot find-and-replace.
- [ ] AC2.5: `knowledge-base/legal/article-30-register.md` frontmatter `last_reviewed:` field bumped from `2026-05-12` to `2026-05-13` (or to the actual PR-creation date if it slips). Verified via `awk '/^last_reviewed:/' article-30-register.md` returns the new date.
- [ ] AC2.6: PA8 §(f) row contains the exact comma-separated trigger enumeration string `"annual review; on any change to apps/web-platform/infra/cloud-init.yml (daemon.json block); on any introduction of an off-host log shipper (promtail/vector/fluent/filebeat/rsyslog); on container restart policy change affecting log path"` so a future `grep -F` audit can enumerate triggers without parsing free-form prose. Verified via `grep -cF 'promtail/vector/fluent/filebeat/rsyslog' knowledge-base/legal/article-30-register.md` returns 1.

#### Item 3 — compliance-posture refresh

- [ ] AC3.1: `knowledge-base/legal/compliance-posture.md` line **91** (the Article 30 Register row — verify line number via `grep -n 'Article 30 Register (RoPA)' knowledge-base/legal/compliance-posture.md`) appends the sentence `"PA8 §(f) Hetzner pino retention concretised in PR #<N> (2026-05-13)."` where `<N>` is this PR number, filled at PR-creation time.
- [ ] AC3.2: The "counsel review pending — outstanding items" enumeration on the same row is unchanged in scope (4 items: controller legal form, Web Push, P0 mirror envelope, Art. 30(5)). Verified via `grep -cF 'outstanding items: controller legal form' knowledge-base/legal/compliance-posture.md` returns 1.

#### Item 4 — Operator runbook

- [ ] AC4.1: `knowledge-base/engineering/ops/runbooks/recover-userid-from-pino-stdout.md` exists with YAML frontmatter (`category: support`, `tags: [pino, userid, hash, observability, gdpr]`, `date: 2026-05-13`).
- [ ] AC4.2: Runbook documents the canonical operator flow: (a) get UUID from support ticket → (b) `doppler run -p soleur -c prd -- npm run -w apps/web-platform hash-user-id <uuid>` → (c) `ssh root@135.181.45.178 'docker logs soleur-web-platform 2>&1 | grep <hash>'`. Explicitly notes that the CLI is **operator-local** (NOT inside the prod container) and explains the `tsx` devDep reason in one line.
- [ ] AC4.3: Runbook includes the PA8 §(f) measurement procedure (Phase 2 SSH steps verbatim, including the cloud-init diff check) — this is the operator script for the post-merge step.
- [ ] AC4.4: Runbook cross-references `admin-ip-drift.md` and `ssh-fail2ban-unban.md` for SSH-recovery scenarios.
- [ ] AC4.5: Runbook prescribes the hardened double-grep pattern (`grep -F 'userIdHash' | grep -F "$HASH"`) for the docker-logs search step, NOT the bare `grep $HASH`. Verified via `grep -cF "grep -F 'userIdHash'" knowledge-base/engineering/ops/runbooks/recover-userid-from-pino-stdout.md` returns ≥1.
- [ ] AC4.6: Runbook calls out the load-bearing primitive distinction: "The CLI uses `hashUserId` (HMAC-SHA256 keyed by `SENTRY_USERID_PEPPER`) — the same primitive the pino `formatters.log()` hook calls. Do NOT substitute `hashUserIdForSentry` (DSAR/cross-tenant primitive, salt-keyed by `SOLEUR_SENTRY_PII_SALT`) — that hash is in a different domain and will not match pino stdout lines."

#### General

- [ ] AC5.1: PR body uses `Ref #3711` (not `Closes #3711`) because Item 2's observed-volume value is filled in the post-merge step — closure happens post-measurement. (Conforms to the ops-remediation `Ref #N` pattern: closure issued by `gh issue close 3711` after the operator runs Phase 4.)
- [ ] AC5.2: PR body includes `## Changelog` section with `semver:patch` label rationale (operator-tools + doc-refresh; no API change).
- [ ] AC5.3: `bun test apps/web-platform/test/` passes (no new tests required; existing tests must not regress because `observability.ts` is read-only in this PR).
- [ ] AC5.4: `tsc --noEmit` in `apps/web-platform/` passes (script file is TS; must compile cleanly under the strict config).

### Post-merge (operator)

- [ ] AC6.1: **SSH measurement run.** Operator follows runbook Phase 2 steps 1-5, captures three 8-h-spaced log-volume samples on a representative weekday, computes the average daily MB rate, and converts to effective time-retention. Estimated wall-clock: ~24 h of elapsed time, ~10 minutes of active operator work.
- [ ] AC6.2: **§(f) post-merge edit.** Operator opens a follow-up PR replacing `__TBD_OBSERVED_VOLUME__` in `knowledge-base/legal/article-30-register.md` with the measured `<X> MB/day at <date-of-measurement>` value. PR body cites this issue and the measurement timestamp.
- [ ] AC6.3: **Issue closure.** After AC6.2 merges, operator runs `gh issue close 3711 --reason completed --comment "Operator-side §(f) measurement complete; observed <X> MB/day → ~<Y> days. Follow-up PR #<M> applied the value."`.

**Automation feasibility scan for post-merge steps:**

- AC6.1 (SSH measurement) — **not feasible to automate inline**: requires 24-hour elapsed window for three time-spaced samples. A cron-scheduled GHA workflow could capture this, but PA8 §(f) is a one-time concretisation, not a recurring measurement (the re-verification-trigger list governs future updates). One-time operator step is correct.
- AC6.2 (§(f) edit) — feasible to automate via `gh pr create` after AC6.1; documenting as operator-step because the measured value must be inspected for sanity before the edit.
- AC6.3 (issue closure) — feasible via `gh issue close`; documenting as operator-step because it's gated on AC6.2 merge.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- **Given** `SENTRY_USERID_PEPPER=test-pepper` and a valid UUID argv, **when** `bun apps/web-platform/scripts/hash-user-id.ts <uuid>` runs, **then** stdout is exactly 64 hex chars and matches the reference `createHmac('sha256','test-pepper').update(uuid).digest('hex')` invocation.
- **Given** no `SENTRY_USERID_PEPPER` env var, **when** `bun apps/web-platform/scripts/hash-user-id.ts <uuid>` runs, **then** exit code is non-zero AND stderr contains "pepper not set" (or equivalent fail-loud message).
- **Given** no argv, **when** `bun apps/web-platform/scripts/hash-user-id.ts` runs, **then** exit code is non-zero AND stderr contains `usage:`.
- **Given** the PA8 §(f) row pre-edit, **when** grep `'short rolling window'` runs on `article-30-register.md`, **then** match count is 1; **after** the edit, match count is 0 AND grep `'30 MB rolling per container'` returns 1.
- **Given** compliance-posture line 91 pre-edit, **when** grep `'PA8 §(f) Hetzner pino retention concretised'` runs, **then** match count is 0; **after** the edit, match count is 1.

### Regression Tests

- **Given** `apps/web-platform/server/observability.ts` (read-only in this PR), **when** `bun test apps/web-platform/test/observability*` runs, **then** all existing tests pass without modification.
- **Given** the existing `hashUserId` export (`apps/web-platform/server/observability.ts:36`), **when** the new script imports it, **then** TypeScript strict-mode compilation succeeds (no `any` widening, no `unknown` cast).

### Edge Cases

- **Given** a malformed UUID argv (not 8-4-4-4-12 hex shape), **when** the script runs, **then** it still emits the hash of the literal argv (Soleur's `hashUserId` does not validate UUID shape — it hashes the input string). Documented in the runbook so the operator knows to copy UUIDs exactly from the support ticket.
- **Given** the prod container restarted yesterday and only 6 hours of log history is on the host, **when** the operator runs the §(f) measurement, **then** the runbook documents that single-sample measurements during a fresh container are biased low and require waiting for the rotation cycle to complete.

### Integration Verification (for `/soleur:qa`)

- **CLI local:** `cd apps/web-platform && SENTRY_USERID_PEPPER=test-pepper bun scripts/hash-user-id.ts $(uuidgen)` returns a 64-hex string.
- **CLI via Doppler (operator machine, dry-run):** `doppler run -p soleur -c dev -- npm run -w apps/web-platform hash-user-id $(uuidgen)` returns a 64-hex string. (Dev pepper differs from prd; this is the dry-run path for testing the wiring.)
- **Doc verification:** `grep -cF '30 MB rolling per container' knowledge-base/legal/article-30-register.md` returns 1.
- **Doc verification:** `grep -cF '__TBD_OBSERVED_VOLUME__' knowledge-base/legal/article-30-register.md` returns 1 (pre-AC6.2) or 0 (post-AC6.2).

## Files to Edit

- `apps/web-platform/package.json` — add `"hash-user-id": "bun scripts/hash-user-id.ts"` to `scripts`.
- `knowledge-base/legal/article-30-register.md` — rewrite PA8 §(f) row (line 162) per the template in Proposed Solution Item 2 AND bump frontmatter `last_reviewed:` (line 7) from `2026-05-12` to the PR-creation date.
- `knowledge-base/legal/compliance-posture.md` — append concretisation sentence to line 91 (Article 30 Register row).

## Files to Create

- `apps/web-platform/scripts/hash-user-id.ts` — operator CLI shim, ~20 lines including usage/error handling. Imports `hashUserId` from `../server/observability`.
- `knowledge-base/engineering/ops/runbooks/recover-userid-from-pino-stdout.md` — operator runbook covering both the CLI invocation and the PA8 §(f) measurement procedure.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Move `tsx` to `dependencies` and run CLI inside prod container via `docker exec` | Adds 1.5 MB to prod image, expands prod runtime attack surface (`tsx` parses TS at runtime — fewer eyes than the `bun` runtime), and requires the operator to be inside the container for a computation that doesn't need any prod state beyond the pepper (which Doppler already provides locally). Net cost > net benefit. |
| Compile `hash-user-id.ts` to `.js` at `npm run build` time and ship to prod | Requires changes to `apps/web-platform/Dockerfile` build stage, introduces a build-time dependency on tsc-emitting-CommonJS (or esbuild), and still requires `docker exec` to run inside prod — same blast radius as above without the runtime parsing cost. |
| Implement CLI as a `.sh` wrapper around `openssl dgst -sha256 -hmac "$SENTRY_USERID_PEPPER"` | Drift risk vs. the canonical `hashUserId()` primitive. If the future `hashUserId` definition changes (e.g., adding a UUID-shape normaliser per ADR-029 evolution), the shell wrapper silently desyncs. Single-source-of-truth via `import { hashUserId }` is the contract-pinned form. |
| Skip the CLI and document the `node -e` incantation in the runbook | Already the current operator state. Fragile; ad-hoc; no contract pin. This is the no-fix option — rejected because the issue body (and CLO carry-forward) explicitly asks for the CLI. |
| Embed retention measurement automation as a GHA cron job (`.github/workflows/pa8-retention-measure.yml`) | PA8 §(f) is a one-time concretisation. The re-verification-trigger list governs future updates and fires on **change events** (cloud-init edit, shipper introduction) which are themselves PR-mediated. A recurring cron measurement adds CI cost for no incremental insight (the json-file driver is structurally bounded at 30 MB regardless of load). Re-evaluate if a future audit cycle requires continuous evidence; defer for now. |
| Update PA8 §(f) without the operator-side measurement (structural cap only) | The §(f) entry would be MB-accurate but time-window-blank, leaving "How many days of forensic context do operators have during a breach investigation?" unanswered. CLO would re-flag at the next audit pass. Including the observed-volume placeholder + post-merge fill closes the question with ~10 minutes of operator work. |

## Dependencies & Risks

| Item | Risk | Mitigation |
|---|---|---|
| Bun availability on operator machine | If a future operator runs the project without Bun, the CLI won't execute. | The repo's existing TS scripts already require Bun (e.g., `verify-stripe-prices.ts`); this is no new dependency. Bun install instructions are in the root `CONTRIBUTING.md` (or equivalent). |
| Operator pepper handling | Pepper leak via shell history or copy-paste error | `doppler run -p soleur -c prd -- npm run ...` is the canonical form — pepper enters the script via env var, never appears in argv or shell history. Runbook explicitly warns against `export SENTRY_USERID_PEPPER=...` outside `doppler run`. |
| Cloud-init daemon.json drift | Operator hand-edits `/etc/docker/daemon.json` on the prod host post-cloud-init | Phase 2 Step 5 (diff check) catches drift; drift → file `compliance/critical` issue per existing pattern. |
| Off-host log shipper introduced later | Future infra change ships logs off-host, invalidating PA8 §(f) "no off-host copies" claim | Re-verification trigger list explicitly names this event; the GDPR-gate skill should flag any new infra-shipper PR for §(f) review (out of scope for this PR; tracked implicitly by `hr-gdpr-gate-on-regulated-data-surfaces`). |
| Observed-volume sampling error (single weekday window not representative of weekend/holiday patterns) | Reported `<Y> days effective retention` skews high or low | Runbook documents that the value is an order-of-magnitude estimate; the regulatory commitment is the structural cap (30 MB), not the time-window translation. The trigger list re-fires on volume-shifting events (new feature ship, marketing campaign). |
| `cq-test-fixtures-synthesized-only` invariant | Tests for the hash-user-id CLI use fixture UUIDs and a `test-pepper` literal | Both are synthesized; no real user UUID or prod pepper is committed. Conforms to the rule. |

## Sharp Edges

- The new script imports `hashUserId` from `../server/observability`. If a future PR widens that export contract (e.g., adds a second positional arg, changes the return type), the operator CLI silently re-emits a hash of a different shape unless the import site is updated. Guard: add a one-line sanity assert in the script that the hash output length is exactly 64 hex chars before printing, so a contract drift is caught at the operator boundary rather than misleading a support investigation.
- The script's stderr "pepper not set" message MUST be distinct from the runtime sentinel `"pepper_unset"` so log-grep operators don't confuse a CLI fail with a runtime fail-closed event.
- Phase 2 SSH step 3 (`du -sb $LogPath`) reads the on-disk log file's byte size. Docker rotates by appending `.1`/`.2` suffixes; the operator may see varying byte counts depending on when the sample lands inside a rotation cycle. Runbook documents averaging across three samples to smooth rotation timing.
- Phase 2 Step 5 (cloud-init diff) uses a sed range extract over `cloud-init.yml`. The sed pattern is fragile against future indentation changes in the cloud-init file. Alternative: hash-pin the daemon.json block at the source (e.g., commit a separate `apps/web-platform/infra/daemon.json` and reference it via `file()` in cloud-init), but that's a refactor outside this PR's scope. Document as a sharp edge for the next PR that touches cloud-init.
- Verify-before-cite: PR labels prescribed in this plan (`priority/p3-low`, `domain/operations`, `type/security`, `deferred-scope-out`) are inherited from issue #3711 — verified via `gh issue view 3711 --json labels`. No new labels need creating.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`. (This plan: threshold = `aggregate pattern`, artifact + vector named.)

## References

- Issue: #3711 (this issue)
- PR #3701 (PR-A; closes #3698) — pino formatters.log() shipped (parent ship)
- PR-B follow-up: #3710 — Sentry-side symmetric coverage + helper migration
- Sibling spec: `knowledge-base/project/specs/feat-pino-userid-redaction-3698/spec.md` (PR-A bundle source)
- PA8 §(c) anchor: `knowledge-base/legal/article-30-register.md` (Processing Activity 8 — operational telemetry / breach detection)
- Compliance-posture pending row: `knowledge-base/legal/compliance-posture.md:91`
- Docker daemon.json source-of-truth: `apps/web-platform/infra/cloud-init.yml:303-310`
- Container run config (no `--log-driver` override): `apps/web-platform/infra/cloud-init.yml:412-421`
- Operator-CLI sibling pattern: `apps/web-platform/scripts/verify-stripe-prices.ts`
- `hashUserId` export contract: `apps/web-platform/server/observability.ts:36`
- ADR-029 (rename-at-boundary): pino formatters + observability helpers
- ADR-028 (DSAR/cross-tenant pseudonymisation): `hashUserIdForSentry`, `mirrorCrossTenantViolation`
- SSH-recovery runbooks: `knowledge-base/engineering/ops/runbooks/ssh-fail2ban-unban.md`, `admin-ip-drift.md`
- `/soleur:admin-ip-refresh` skill (ADMIN_IPS Doppler-side refresh)
- GDPR auditor recommendation: "add re-verification frequency to §(f)" + "compliance-posture refresh post-merge" (carry-forward from PR-A plan-review chain)
- SpecFlow finding from issue body: `tsx` prod-runtime gap (resolved by operator-local invocation — see Research Reconciliation)
