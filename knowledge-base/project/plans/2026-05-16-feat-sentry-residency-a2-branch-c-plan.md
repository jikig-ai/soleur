---
date: 2026-05-16
topic: feat-sentry-residency-a2-branch-c
status: draft
type: feature
classification: cross-domain-remediation
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
requires_cpo_signoff: true
triad: [cpo, clo, cto]
brainstorm: knowledge-base/project/brainstorms/2026-05-16-sentry-residency-a2-branch-c-brainstorm.md
spec: knowledge-base/project/specs/feat-sentry-residency-a2-branch-c-1/spec.md
branch: feat-sentry-residency-a2-branch-c-1
worktree: .worktrees/feat-sentry-residency-a2-branch-c-1/
draft_pr: "#3904"
parent_issue: "#3861"
related_issues:
  - "#3861"  # umbrella
  - "#3863"  # A1 (merged 2026-05-15)
  - "#3904"  # PR-α draft (this worktree)
worktrees_planned:
  - feat-sentry-residency-a2-branch-c-1  # PR-α (legal+docs deadline gate)
  - feat-sentry-residency-a2-branch-c-2  # PR-β (runtime+IaC+audit-gate)
  - feat-sentry-residency-a2-branch-c-3  # PR-γ (cleanup+vendor)
art_33_deadline: "2026-05-19T12:50:00Z"
---

# Plan: Sentry Residency A2 — Branch C (new DE org from scratch)

## Overview

Branch C is a **3-PR series** that abandons A2's invalidated "align tfstate to existing DE org" framing and instead provisions a new Jikigai-controllable Sentry org from scratch on `eu.sentry.io`, atomically migrates `SENTRY_DSN` + 9 secret surfaces, drops + serial-re-imports tfstate, and triple-extends the audit gate with destination-controllability probes.

The 3-PR shape decouples the **CNIL Art 33 disclosure deadline (2026-05-19T12:50Z)** — which is procedural, not remediation-driven — from the **runtime atomic-swap risk surface**. PR-α (legal+docs, this worktree) is the deadline gate; PR-β (runtime+IaC+audit-gate) and PR-γ (cleanup+vendor) ship without deadline pressure.

The brainstorm captures 12 key decisions and 3 capability gaps; the spec captures 14 FRs, 7 TRs, 16 ACs, and 6 constraints. This plan adds **TR-level mechanics** for the 5 plan-time open questions and the **sibling-worktree scaffolding** for PR-β/PR-γ.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "11 scheduled GH workflows post cron-checkin beacons" (brainstorm Decision #3; spec FR5 enumerates 9 by name + "2 additional flagged") | `grep -rln "SENTRY_INGEST_DOMAIN\|sentry-cron-checkin\|SENTRY_PUBLIC_KEY\|ingest\..*\.sentry\.io/api/.*/cron" .github/workflows/` returns **9 files**: `scheduled-cf-token-expiry-check.yml` + `scheduled-community-monitor.yml` + `scheduled-content-vendor-drift.yml` + `scheduled-daily-triage.yml` + `scheduled-github-app-drift-guard.yml` + `scheduled-oauth-probe.yml` + `scheduled-realtime-probe.yml` + `scheduled-skill-freshness.yml` + `scheduled-terraform-drift.yml`. `scheduled-cf-token-expiry-check.yml` has its `schedule:` deferred (per `knowledge-base/legal/compliance-posture.md:84`), so 8 active + 1 dormant = 9 total. The PA8 §(c)(iv) cell already says "9 scoped scheduled GitHub Actions workflows" — spec FR5 over-counted to 11. | **Plan corrects FR5 inventory to 9.** PR-β AC11 verifies first-run beacons on all 9 (the dormant one gets credential-rotation parity even though its `schedule:` is off — pre-empts a re-land regression). |
| "PA8 §5(2) recipient cell at `knowledge-base/legal/article-30-register.md`" (spec FR1) | The `§5(2)` reference is the Article 30 register's **sub-clause (5)(2) accountability evidence** marker, currently mentioned in PA8 §(c) at L157. The actionable **(d) Recipients** cell sits at L160: `Sentry (processor — DE region, **Functional Software GmbH**); Hetzner (processor — captures stdout); the on-call Jikigai engineering/CLO rotation (internal).` | **Plan disambiguates target.** PR-α FR1 appends to the **(d) Recipients cell at L160** of `knowledge-base/legal/article-30-register.md`, not to a literal "§5(2)" heading (no such heading exists). AC1's grep anchors on the disclosure phrase, not the section number. |
| "Sentry Terraform provider `base_url` targets `de.sentry.io/api/`" (implicit in spec FR7) | `apps/web-platform/infra/sentry/main.tf:30` sets `provider "sentry" { base_url = var.sentry_region == "de" ? "https://de.sentry.io/api/" : "https://sentry.io/api/" }`. `de.sentry.io` is INGEST-ONLY per today's cascade learning; API + dashboard live at `eu.sentry.io`. Provider's current `base_url` is wrong; A1 didn't fix it (A1 was diagnostic-only). | **PR-β adds explicit `base_url` flip** to `eu.sentry.io/api/` in `apps/web-platform/infra/sentry/main.tf:30` as part of C4 tfstate drop+reimport (otherwise serial re-imports POST to the wrong host and fail silently or 401 — same failure shape as A1's audit-script). |
| "11 scheduled workflows" inventory aligns with PA8 §(c)(iv) "9 scoped scheduled GitHub Actions workflows" | PA8 cell at L157 (iv) says **9**, confirmed by grep above. | **Plan freezes count at 9 across spec FR5, AC11, and PA8 §(c)(iv).** No re-edits to PA8 §(c)(iv) needed — count is already correct there. |
| ".mcp.json contains `--config=playwright-headed.json` flag" (implicit in TR2) | `.mcp.json` actual content: `{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--user-data-dir=/home/jean/.cache/playwright-mcp-profile"]}}}`. NO `--config` flag; uses `@latest` (not pinned); only `--user-data-dir`. Per cascade learning §"Playwright handoff discipline", `@playwright/mcp@0.0.75` ignores `--user-data-dir` and spawns `--headless` regardless. | **Plan adds Phase 0 preflight to PR-β**: `pgrep -fa chromium \| grep -- --headless` MUST return empty before any C1 credential-entry step. If headless detected, abort with operator hand-off note (see TR2 mechanic below). W4 (config-flag plumbing in worktree-manager) is deferred to PR-γ follow-up. |
| "tfstate has 13 resources" (spec FR7 + AC10) | `apps/web-platform/infra/sentry/*.tf` enumerates: 1 `data.sentry_project` (L36) + cron-monitors.tf + issue-alerts.tf + variables.tf + versions.tf + main.tf. A1 captured the exact 13 in pre-flight manifest at `knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md`. | **Plan re-captures the manifest at PR-β Phase 0** to guarantee freshness against any drift between A1 (2026-05-15) and PR-β apply time (next week). Use `apps/web-platform/scripts/sentry-monitors-audit.sh` per existing precedent. |

**Verdict:** 5 spec drifts caught; 1 (CSP cache-purge mechanic) elaborated in TR5 below; 0 (Cloudflare purge precedent) confirmed against `2026-04-18-fix-purge-cf-cache-on-share-revoke-plan.md:15` (POST `/client/v4/zones/<zone>/purge_cache`).

## User-Brand Impact

**Artifact:** Sentry destination cluster — runtime `SENTRY_DSN` + `NEXT_PUBLIC_SENTRY_DSN` + `SENTRY_CSP_REPORT_URI` + `SENTRY_AUTH_TOKEN` + cron-checkin secrets triple + PA8 §5(2) sub-processor entry.

**If this lands broken, the user experiences:** A live production error from the very next signup fires into a half-state DSN — either the now-revoked phantom org (lost forever; no symbolication, no Sentry alert, on-call paged late by Hetzner-pino-only signal) or a partially-swapped client+server pair where browser-side telemetry goes to the new DE org and server-side goes to the old phantom org (or vice versa). The trace is fragmented; the bug recurs because the fix-loop has no end-to-end view.

**If this leaks, the user's data is exposed via:** Same artifacts the PIR enumerates — error messages and stack traces that may incidentally include `user_id`, request paths, request headers. Pre-swap, these went to an unowned third-party org for 49 days (PIR-documented). Post-swap, the audit-gate triple-expansion (C5) prevents recurrence by proving admin-controllability of the new destination at every diff + deploy.

**Brand-survival threshold:** `single-user incident` (forward-looking — the PIR's `none` downgrade is backward-looking only; the prd `auth.users` table held 10 operator-adjacent accounts and **zero arms-length external signups** during the phantom-ingest window 2026-03-28 → 2026-05-16, verified by SQL count + operator categorization at PR-α merge time 2026-05-17. Every Branch C PR determines whether the **next** arms-length signup hits a clean DE residency story or a recurrence).

**Required sign-offs:**
- **CPO sign-off** (plan-time) — captured via brainstorm Domain Assessment Step 2.5 carry-forward; CPO concurred with 3-PR shape, `single-user incident` threshold, and amicable-with-receipts refund posture.
- **CLO sign-off** (PR-α body) — required for PA8 §5(2) disclosure wording (Decision #8 first-of-its-kind drift wording precedent).
- **CTO sign-off** (PR-β body) — required for C2 atomic-swap mechanic (write-new-then-revoke + 2h observation window) + C5 audit-gate triple-expansion + C4 tfstate drop+reimport.
- **`user-impact-reviewer`** (review-time) — invoked on every Branch C PR per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`; enumerates failure modes against the diff.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO).

Carry-forward from brainstorm §Domain Assessments. No fresh assessment — brainstorm Phase 0.5 spawned the triad in parallel and captured structured findings.

### Engineering (CTO)

**Status:** reviewed (carry-forward).
**Assessment:** Manual swap is the only viable shape (C9 ruled out by 30-min probe). Half-state guard: write-new-everywhere → 2h observation → audit-script-green → revoke old. Audit gate triple-expands to reachability + project-scope + write-probe, gated CI on Sentry-touching diffs AND at deploy. tfstate drop+reimport with pre-flight manifest. Five engineering gaps in C1-C9 absorbed: sentry-cli `SENTRY_URL` injection (FR5), audit-script region-probe loop (FR9 adds `eu.sentry.io`), CSP edge-cache purge (TR5 mechanic), source-map orphan disclosure (TR6 → NG3), project-slug default in Terraform (TR3 collision rename).

### Legal (CLO)

**Status:** reviewed (carry-forward).
**Assessment:** Art 33 filing deferred pending Sentry support response (T-24h buffer 2026-05-18T12:50Z). PA8 §5(2) disclosure drafted (appended to recipient cell at L160; `<pending C2 merge>` placeholder pre-PR-β, backfilled in PR-γ). PIR Phase 8 gate = C2 + C5 + Sentry-response-OR-T+14d. PIR satisfies Art 34 self-subject disclosure; one cross-ref in `knowledge-base/legal/compliance-posture.md` only. Refund split into 2 tickets (billing-only + forensics-only) to isolate decision surfaces.

### Product (CPO)

**Status:** reviewed (carry-forward).
**Assessment:** 3-PR series with PR-α (legal+docs) shipping first as deadline gate. C6 (PA8 §5(2) disclosure) — not C2 (runtime swap) — is the Art-33-driven critical path. `single-user incident` threshold load-bearing for forward-looking Branch C. Amicable-with-receipts refund posture preserves vendor relationship on the org we're about to depend on. C9 probe first 30-min capped (executed in brainstorm: ruled out).

### Product/UX Gate

**Tier:** none. No new user-facing pages, no UI components, no modals. Infrastructure + legal-document edits only.

### Brainstorm-recommended specialists

None outside the triad. Operations + Marketing + Sales + Finance + Support not assessed per USER_BRAND_CRITICAL + feature-description scope.

## GDPR / Compliance Gate (Phase 2.7)

**Trigger:** `brand_survival_threshold: single-user incident` declared (clause (b) of the expanded gate criteria) AND PA8 §5(2) Article 30 register edit (regulated-data surface AT the legal disclosure layer).

**Assessment (inline; this plan IS the GDPR remediation):**

- **Art 33 (notification of breach):** Procedural disclosure path is PA8 §5(2) wording + PIR + optional CNIL filing (operator-gated on Sentry-support T-24h buffer per Decision #10). PR-α satisfies the procedural gate by 2026-05-19; remediation (PR-β) carries no Art 33 deadline.
- **Art 30(5) sub-processor accountability:** C6 PA8 §5(2) recipient-cell append documents the recipient drift (phantom org → new DE org); placeholder mechanic prevents premature claim before C2 settles.
- **Art 34 (communication to data subjects):** Self-controller-self-processor framing — 10 operator-adjacent accounts (founders, team, bot, internal QA / test, 2 friends-of-team test signups) and zero arms-length external signups during phantom-ingest window 2026-03-28 → 2026-05-16, verified by SQL count + operator per-row categorization at PR-α merge time 2026-05-17 (recorded in PR #3904 review evidence and `knowledge-base/legal/article-30-register.md` PA8 §(d)). Operator-as-data-subject covered by the PIR itself (committed, dated, git-authored) plus one-line cross-reference in `compliance-posture.md` (FR3); operator-adjacent team / friends-of-team subjects directly reachable by team comms (no formal Art 34 notification machinery needed).
- **Art 25 (data protection by design):** C5 audit-gate triple-expansion is the design-level control that makes silent residency drift impossible to greenlight — the root-cause failure mode A1 documented.

**Critical findings:** None new. The phantom-ingest window is the documented critical finding the PIR already records; Branch C is its closure.

**Disclaimer:** This inline assessment is advisory and reflects the operator-CLO triad's collective view as captured in the brainstorm. It does NOT substitute for licensed-counsel review. Counsel review of the PA8 §5(2) wording is the gating signal on CNIL-filing posture (Decision #10).

**At /work time:** `/soleur:gdpr-gate` re-invoked per PR — PR-α scans the PA8 §5(2) + ADR-031 + compliance-posture.md diff; PR-β scans the secret-surface diff + audit-script extension; PR-γ scans the PIR Phase-8 flip + W1-W5 follow-up issues.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200 → 75 open issues`. Searched bodies for each of the 5 PR-α target files (`apps/web-platform/scripts/sentry-monitors-audit.sh`, `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`, `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md`, `knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md`) and the 5 PR-β audit-script + Terraform-root paths.

**Result:** None. No open code-review issue references any Branch C target file. No fold-in / acknowledge / defer decision needed.

## Files to Edit

### PR-α (this worktree, `feat-sentry-residency-a2-branch-c-1`)

- `knowledge-base/legal/article-30-register.md` — append phantom-ingest disclosure paragraph to PA8 §(d) Recipients cell at **L160** (do NOT replace existing cell content; append). Use `<pending C2 merge>` placeholder for post-swap DE-org reference.
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — replace stale URL `de.sentry.io/settings/account/api/auth-tokens/` at **L95** with `eu.sentry.io/settings/account/api/auth-tokens/`. Add a new `## Cluster / Host Glossary` section before `## Decision` (currently no such section) covering: ingest hosts (`*.ingest.{de,us}.sentry.io`), dashboard hosts (`sentry.io`, `jikigai.sentry.io`, `eu.sentry.io`), API hosts (`{eu,us}.sentry.io/api/0/...`). Update L101 (`Provider docs do not enumerate de.sentry.io; base_url override is inferred.`) to reflect `eu.sentry.io/api/` as the canonical EU API base_url.
- `knowledge-base/legal/compliance-posture.md` — under "Active Compliance Items" (L61-87), add a new row referencing the PIR + this plan + parent issue #3861. **Row schema:** the Active section uses 5 columns `Item | Issue | Status | Deadline | Notes` (see header at L65); do NOT copy the L96 row (that lives in "Completed Compliance Work" and uses a 4-column schema without `Status`/`Deadline`). Reuse the Sentry Monitors row at L72 as the schema template. Deadline column for PR-α: `2026-05-19` (Art 33 procedural gate); Status: `IN-PROGRESS`.

### PR-β (`feat-sentry-residency-a2-branch-c-2`, to be created)

- `apps/web-platform/infra/sentry/main.tf` — L30: flip `base_url = "https://de.sentry.io/api/"` → `base_url = "https://eu.sentry.io/api/"` (DE-region API host, not ingest host). **Atomic with `variables.tf` `var.sentry_org` update below** — same commit (P0 review fix #2: avoids 3-state window where `base_url=eu` but org slug is old).
- `apps/web-platform/infra/sentry/variables.tf` — update `var.sentry_org` default in **same commit** as `main.tf:30` flip if DE org slug collision forces `jikigai-eu`/`jikigai-de` (see TR3 mechanic below). Update `var.sentry_project` default if the new DE-org project slug differs from current.
- `apps/web-platform/scripts/sentry-monitors-audit.sh` — three new gates between L58 (region-probe success exit) and L60 (existing DSN cluster-substring check start). **The triple-gate is ADDITIVE to (not replacing) the existing L60-103 cluster-substring residency-mismatch check** (which catches the SDK-DSN-vs-token-org-id split-state that the triple-gate alone cannot — per Architecture-Strategist F2 and `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md`). New gates: `audit_destination_admin_controllable` (org GET), `audit_project_scope` (project GET), `audit_write_probe` (POST + DELETE release). **Plus 4th gate** `audit_dsn_org_id_matches_token_org_id` (extract `o\d+` from `NEXT_PUBLIC_SENTRY_DSN`; compare to `GET /organizations/{slug}/` `.id` from token's response — catches the split state where audit token rotated but runtime DSN didn't). Extend region-probe loop at **L46** (`for candidate in de.sentry.io sentry.io`) to include `eu.sentry.io` as the first candidate. See TR-C5 mechanic below.
- `.github/workflows/apply-sentry-infra.yml` — add a pre-`terraform plan` step invoking `apps/web-platform/scripts/sentry-monitors-audit.sh` (fail-closed) so the operator-driven re-apply path traverses the new gates. **Without this, the `workflow_dispatch:` + `terraform apply` route is a gate-bypass surface** for any operator running `gh workflow run apply-sentry-infra.yml` against stale credentials (Architecture-Strategist F1).
- `apps/web-platform/sentry.client.config.ts`, `apps/web-platform/sentry.server.config.ts` — no code changes needed (consume `NEXT_PUBLIC_SENTRY_DSN` / `SENTRY_DSN` from env); verify post-deploy that DSN values resolve to new DE org. (Note: `sentry.edge.config.ts` does NOT exist in this codebase — Next.js Sentry SDK supports it but Soleur has not adopted edge instrumentation. Out of scope for PR-β.)
- `apps/web-platform/next.config.ts` — Sentry block: inject `SENTRY_URL=https://eu.sentry.io/` if absent (sentry-cli source-map upload target).
- `apps/web-platform/Dockerfile` — build-args block: ensure `NEXT_PUBLIC_SENTRY_DSN`, `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` carry the new DE-org values via `--build-arg` at CI build. Add `SENTRY_URL=https://eu.sentry.io/` env injection for sentry-cli.
- `apps/web-platform/.env.example` — commented templates updated to new DE-org DSN shape.
- `.github/workflows/reusable-release.yml` — audit-script env block (~L283-330): inject `SENTRY_URL`, ensure `SENTRY_AUTH_TOKEN` resolves to new token. Docker build-args block (~L513-518): same.
- `.github/workflows/scheduled-{cf-token-expiry-check,community-monitor,content-vendor-drift,daily-triage,github-app-drift-guard,oauth-probe,realtime-probe,skill-freshness,terraform-drift}.yml` — verify each consumes the rotated `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY` from GH repo secrets (no inline literals expected; confirm).
- New file: `.github/workflows/sentry-audit-gate.yml` — CI workflow running `apps/web-platform/scripts/sentry-monitors-audit.sh` on diffs touching `sentry.*.config.ts | next.config.ts | infra/sentry/**/*.tf | scripts/sentry-monitors-audit.sh | .github/workflows/*sentry*`. Required check on `main`-bound PRs.

### PR-γ (`feat-sentry-residency-a2-branch-c-3`, to be created)

- `knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md` — flip `status: open` → `status: resolved` at L8. Append `## Phase 8 — Recovery Completeness` section before `## Who was affected (by role)` at L75. See TR4 institutional-precedent mechanic below.
- `knowledge-base/legal/article-30-register.md` — backfill `<pending C2 merge>` placeholder in PA8 §(d) with PR-β merge SHA / commit ref.
- 4 new GH issues filed: W1 (hard rule `hr-prereq-playwright-first-then-credential-handoff`), W2 (extend `soleur:brainstorm` Phase 1.0.5 to named URL substrings), W4 (worktree-manager `.mcp.json` config-flag injection under `SOLEUR_PLAYWRIGHT_HEADED=1`), W5 (`/soleur:compound` fail-friendly on main). W3 absorbed into PR-β C5 — no separate issue.
- US shadow org teardown — operator-driven (admin UI at `sentry.io/settings/jikigai`); document the state transitions (Team trial → free plan → eventual close) in PR-γ body.
- 2 Sentry support tickets — operator-driven via Sentry support portal; ticket IDs captured in PR-γ body per AC13.

## Files to Create

- `.github/workflows/sentry-audit-gate.yml` — PR-β.
- `knowledge-base/legal/audits/sentry-migration-audit-<PR-β-merge-date>.md` — PR-β; auto-generated by `scripts/sentry-monitors-audit.sh` per existing dual-path mechanic (`reusable-release.yml` Phase 2.2).
- GH issues for W1/W2/W4/W5 — PR-γ; created via `gh issue create`.

## Implementation Phases

### PR-α — Legal + Docs Deadline Gate (this worktree)

**Target merge:** 2026-05-17 or 2026-05-18 (Art 33 procedural gate buffer: T-24h to T-48h before 2026-05-19T12:50Z).

**Phase -1 — Deadline-pressure abort checkpoints (P2 review fix).**

The Art 33 gate is the **disclosure**, not the PR. If review changes, CI flake, signed-commits ruleset, or rebase conflicts push the PR past the deadline, the operator-CLO path branches:

- **T-24h checkpoint (2026-05-18T12:50Z):** if PR-α is not in `mergeable: clean` state with all required checks green, operator initiates parallel CNIL filing draft at `knowledge-base/legal/forms/cnil-art-33-draft.md` (create if absent) — the disclosure ships with whatever PA8 wording is in the open PR diff at this moment.
- **T-2h checkpoint (2026-05-19T10:50Z):** if PR-α still blocked, CLO files directly with the diff text in flight; PR #3904 cited as evidence-in-flight in the CNIL submission. **Do NOT** create `-2` worktree from `feat-sentry-residency-a2-branch-c-1` to circumvent the sharp-edge (the worktree must come from `origin/main`); accept that PR-β slips and re-baseline its target merge week.

**Phase 0 — Pre-flight (10 min).**
- Confirm this worktree is on branch `feat-sentry-residency-a2-branch-c-1` and PR #3904 is the draft target.
- Read CLO-drafted PA8 §5(2) wording from brainstorm Decision #8 (operator copies verbatim into editor for FR1).

**Phase 1 — PA8 §(d) Recipients append (FR1).**
- Locate `knowledge-base/legal/article-30-register.md:160` (cell starts: `**(d) Recipients** | Sentry (processor — DE region, **Functional Software GmbH**); ...`).
- Append disclosure paragraph at end of cell (preserve trailing `|`). Wording per Decision #8; `<pending C2 merge>` placeholder for post-swap DE-org slug reference.

**Phase 2 — ADR-031 URL fix + glossary (FR2).**
- Edit `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md:95`: replace `de.sentry.io/settings/account/api/auth-tokens/` → `eu.sentry.io/settings/account/api/auth-tokens/`.
- Edit L101: `Provider docs do not enumerate de.sentry.io; base_url override is inferred.` → updated text acknowledging the cascade learning and pointing at the `eu.sentry.io/api/` canonical EU API base_url.
- Insert new `## Cluster / Host Glossary` section before the existing `## Decision` heading.

**Phase 3 — compliance-posture cross-ref (FR3).**
- Append a new row under "Active Compliance Items" at `knowledge-base/legal/compliance-posture.md` (after L86, before "Completed Compliance Work"). **Row schema** is the 5-column Active form (`Item | Issue | Status | Deadline | Notes`) per L65 header — NOT the 4-column Completed form. Reuse the Sentry Monitors row at L72 as the template. Set Status: `IN-PROGRESS`; Deadline: `2026-05-19` (Art 33 procedural gate).
- Cross-reference PIR + this plan + parent issue #3861 + draft PR #3904.

**Phase 4 — Verification.**
- AC1: `grep -nE "phantom-ingest|destination-unreachable" knowledge-base/legal/article-30-register.md` returns ≥1 match in PA8 §(d) cell.
- AC3: `grep -c "de.sentry.io/settings" knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` returns 0; `grep -c "## Cluster / Host Glossary" knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` returns 1.
- AC4: `grep -nE "sentry-residency-a2|phantom-ingest|3861" knowledge-base/legal/compliance-posture.md` returns ≥1 match under "Active Compliance Items".

**Phase 5 — CLO sign-off + PR ready + merge.**
- AC2: CLO sign-off captured in PR-α body via explicit acknowledgment ("CLO-reviewed: PA8 §(d) phantom-ingest disclosure wording per brainstorm Decision #8").
- Mark PR #3904 ready: `gh pr ready 3904 && gh pr merge 3904 --squash --auto`.
- AC5: PR merged by 2026-05-19T12:50Z.

**Phase 6 — Sibling-worktree creation (post-merge to main).**
After PR-α merges, create `-2` and `-3` worktrees from updated main:
```bash
git fetch origin main
git worktree add .worktrees/feat-sentry-residency-a2-branch-c-2 -b feat-sentry-residency-a2-branch-c-2 origin/main
git worktree add .worktrees/feat-sentry-residency-a2-branch-c-3 -b feat-sentry-residency-a2-branch-c-3 origin/main
```
Each new worktree gets its own `.mcp.json` symlinked from the bare repo (auto by `git worktree add`); each gets its own draft PR opened post-first-commit.

### PR-β — Runtime Atomic Swap + IaC + Audit-Gate Extension (`-2` worktree)

**Target merge:** Week of 2026-05-19 to 2026-05-23 (no deadline). Branch-protection ruleset (the existing `apps/web-platform/infra/sentry/`-touching PR pattern) gates merge on CTO + `user-impact-reviewer` sign-off.

**Phase 0 — Pre-flight (TR2 + TR3).**
- **TR2 (Playwright headed posture):** `pgrep -fa chromium | grep -- --headless` MUST return empty before any C1 credential-entry step. If non-empty (i.e., `@playwright/mcp@latest` resolved to a version that ignores `--user-data-dir`), abort C1 and either (a) pin `@playwright/mcp` to a known-headed version in `.mcp.json` and restart MCP, OR (b) defer C1 to a manual operator-driven signup (no Playwright — operator opens https://eu.sentry.io/auth/register/ in a real browser). The cascade learning §"Playwright handoff discipline" makes this an explicit precondition: **operator at keyboard for credentials, Playwright for navigation only**. The pre-flight is the gate, not the assumption.
- **TR3 (DE org slug collision check):** Playwright navigates to https://eu.sentry.io/organizations/jikigai/ (logged-out) — `404 Not Found` confirms `jikigai` slug is available. If 200/302/auth-wall, slug is taken; operator chooses `jikigai-eu` per Branch C precedent (matches PA8 §5(2) wording vector). Propagate chosen slug to: `var.sentry_org` default in `apps/web-platform/infra/sentry/variables.tf`, 9 scheduled-workflow `SENTRY_ORG` references, `SENTRY_ORG` secret in Doppler `prd` + GH repo + Vercel envs.

**Phase 1 — C1: Provision new DE org (operator-driven, Playwright-narrated).**
- Operator at keyboard. Playwright drives: navigate to `eu.sentry.io/auth/register/`, fill non-credential fields, hand off to operator for email/password/MFA entry.
- Org slug per TR3 outcome. Project slug: keep `web-platform` (matches current `var.sentry_project` default unless TR3 forces rename).
- After org provisioned, mint **new** `SENTRY_AUTH_TOKEN` (org-scoped, internal-integration; scopes: `project:read`, `project:releases`, `project:write`, `org:read`) via the DE-org dashboard at `eu.sentry.io/settings/jikigai-{eu}/auth-tokens/` (or chosen slug). Verify scope via `curl -H "Authorization: Bearer $NEW_TOKEN" https://eu.sentry.io/api/0/users/me/` returns 200.
- **FR6 verify probe MUST target `eu.sentry.io/api/0/users/me/`**, NOT `de.sentry.io/api/...` (per cascade learning §"Solution 1" — `de.sentry.io` is ingest-only and won't serve API).

**Phase 2 — C2: Atomic-swap secret surfaces (write-new-everywhere, do NOT revoke yet).**

The write-new-then-revoke mechanic per Decision #4 + TR1:

1. **Doppler `prd`** (12 keys total): `SENTRY_DSN`, `NEXT_PUBLIC_SENTRY_DSN`, `SENTRY_CSP_REPORT_URI`, `SENTRY_AUTH_TOKEN`, `SENTRY_API_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`, `SENTRY_API_HOST=eu.sentry.io`, `SENTRY_URL=https://eu.sentry.io/`.
2. **GH repo secrets** (parity with Doppler — 11 keys; `SENTRY_CSP_REPORT_URI` is server-resolved per L41 of middleware.ts, not GH-secret-bound).
3. **Vercel envs** (matches Doppler `prd` shape — Vercel envs propagate per-deploy, not per-push, so the 2h observation window per TR1 begins **after** the next prod deploy completes, not at Doppler write).
4. **`apps/web-platform/.env.example`** — commented templates updated (no real values).
5. **`apps/web-platform/Dockerfile`** — `ARG NEXT_PUBLIC_SENTRY_DSN`, `ARG SENTRY_AUTH_TOKEN`, `ARG SENTRY_ORG`, `ARG SENTRY_PROJECT` carry CI-injected values; add `ENV SENTRY_URL=https://eu.sentry.io/` for sentry-cli.
6. **`apps/web-platform/next.config.ts`** Sentry block — inject `SENTRY_URL` if absent (sentry-cli upload-source-map target).
7. **`.github/workflows/reusable-release.yml`** — audit-script env block (~L283-330) + Docker build-args block (~L513-518): add `SENTRY_URL`.
8. **9 scheduled workflows** — verify each pulls `SENTRY_INGEST_DOMAIN` etc. from GH repo secrets (no inline literals; `grep -rE 'SENTRY_(INGEST_DOMAIN|PROJECT_ID|PUBLIC_KEY).*:.*[0-9]' .github/workflows/scheduled-*.yml` MUST return 0 — no hardcoded values).
9. **`apps/web-platform/infra/sentry/main.tf:30`** — `base_url = "https://eu.sentry.io/api/"`. **Atomic in the same commit:** `apps/web-platform/infra/sentry/variables.tf` `var.sentry_org` default update if TR3 forced rename (was in old Phase 6 step 4 — moved here per Kieran P0-2 to avoid the 3-state window). Single commit message: `iac: flip sentry provider to eu.sentry.io + slug rename`.
10. **Cloudflare edge cache purge** for CSP `report-uri` header (TR5 mechanic below).

After write-new-everywhere: **DEPLOY** (`gh workflow run reusable-release.yml` or wait for next push to main). Vercel envs take effect on this deploy; Doppler `prd` propagates to Hetzner via existing pipeline.

**Phase 3 — TR1 observation window (2h).**
- Trigger 1 synthetic Sentry event from new DE org's test project (`curl -X POST` against new DSN — minimal test event).
- Trigger 1 real prod event (operator-driven: visit prod, click a feature that emits a Sentry breadcrumb, or wait for next organic prod error).
- After 2h elapse: confirm both events land in new DE org dashboard at `eu.sentry.io/organizations/jikigai-{eu}/issues/`. If either is missing, **HALT** → Phase 3.5 recovery decision tree (do NOT proceed to Phase 7 revoke).

**Phase 3.5 — Half-state recovery decision tree (P1 review fix #13).**

If either Phase 3 event is missing, the operator is in a known-bad half-state. Decision tree:

1. **Bisect surfaces (≤10 min).** Run `apps/web-platform/scripts/sentry-monitors-audit.sh` with `SENTRY_DSN_DEBUG=1` (add if absent — print resolved DSN at client / server / edge boundary) to identify which surface still points at phantom-org. Common splits: Vercel client env propagated but Hetzner-backed server env didn't (Doppler-to-Hetzner pipeline lag) or vice versa.
2. **Time-bound: 30 min.** If the bisect identifies the lagging surface within 30 min of Phase 3 HALT, force-propagate (re-run Vercel deploy / `doppler secrets download && systemctl restart soleur-web` on Hetzner). Re-trigger one synthetic event; if it lands in new org, resume Phase 4. If not, escalate.
3. **Escalation: 60 min.** If half-state persists >60 min, page CTO via Slack #incidents. Involve `user-impact-reviewer` decision before any subsequent retry.
4. **Rollback (if escalation does not resolve in 30 min).** Old token is **not yet revoked** — this is a reversible state. Re-write OLD DSN/token/secrets to Doppler/Vercel/GH (revert Phase 2). Close PR-β via `gh pr close 3905` without merge. Open PR-β-prime with revised mechanic. The 2h observation window resets on the new attempt.
5. **Forbidden until resolution:** Phase 4 (audit-gate extension), Phase 5 (CI workflow), Phase 6 (tfstate drop), Phase 7 (revoke). The audit gate must not be wired to required-check until ingest is verified end-to-end; tfstate drop with split state would leave Terraform pointing at the new org while runtime emits to old.

**Phase 4 — C5: Audit-gate triple-expansion + DSN-org-id match (4 gates total).**

The 4 new gates are inserted **between L58 (region-probe success exit) and L60 (existing cluster-substring residency-mismatch check at L60-103)** — they are **ADDITIVE to**, not replacing, the existing cluster-substring defense (Architecture-Strategist F2: the existing L60-103 check is what catches the SDK-DSN-vs-token-org-id split-state that admin-controllability alone cannot prove).

Edit `apps/web-platform/scripts/sentry-monitors-audit.sh` between L58 and L60:

```bash
# --- C5: Destination-controllability 4-gate (new in PR-β; additive to L60+ cluster-substring check) ---

# Gate 1: org reachability (proves admin can read org-level config).
org_resp=$(curl -s --max-time 10 \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  -w '\n%{http_code}' \
  "https://${api_host}/api/0/organizations/${SENTRY_ORG}/")
http="${org_resp##*$'\n'}"
org_body="${org_resp%$'\n'*}"
if [[ "$http" != "200" ]]; then
  echo "ERROR: org reachability failed: HTTP $http on /organizations/${SENTRY_ORG}/" >&2
  exit 1
fi

# Gate 2: project scope (proves token is project-scoped, not just org-scoped).
http=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/")
if [[ "$http" != "200" ]]; then
  echo "ERROR: project scope failed: HTTP $http on /projects/${SENTRY_ORG}/${SENTRY_PROJECT}/" >&2
  exit 1
fi

# Gate 3: write probe — POST + DELETE release (proves project:releases scope).
# Sentry's project-level POST release returns 201 on create. The org-level POST
# returns 208 on duplicate version, but the project-level POST documented at
# https://docs.sentry.io/api/releases/create-a-new-release-for-an-organization/
# returns 201-only — probe_ver is timestamp-suffixed so duplicate-version is
# impossible. Treat 208 as a regression signal (Kieran P1-4: drop 208 branch).
probe_ver="audit-probe-$(date -u +%s)"
http=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST -d "{\"version\":\"${probe_ver}\"}" \
  "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/releases/")
if [[ "$http" != "201" ]]; then
  echo "ERROR: write probe (POST release) failed: HTTP $http (expected 201)" >&2
  exit 1
fi
curl -s --max-time 10 -o /dev/null \
  -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
  -X DELETE "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/releases/${probe_ver}/"
# DELETE is best-effort; failure to clean up probe-release does not fail the gate
# (Sentry's release-GC handles orphan probe releases ≥30d untouched).

# Gate 4: DSN org-id matches token org-id (catches split state where audit token
# rotated but runtime DSN didn't — Architecture-Strategist F2). Extract o\d+ from
# NEXT_PUBLIC_SENTRY_DSN and compare to the org's internal id from Gate 1's body.
dsn_org_id=$(echo "${NEXT_PUBLIC_SENTRY_DSN:-}" | grep -oE 'o[0-9]+' | head -1 | tr -d 'o')
token_org_id=$(echo "$org_body" | grep -oE '"id"\s*:\s*"[0-9]+"' | head -1 | grep -oE '[0-9]+')
if [[ -z "$dsn_org_id" || -z "$token_org_id" ]]; then
  echo "ERROR: gate 4 — could not extract org-ids (dsn=$dsn_org_id token=$token_org_id)" >&2
  exit 1
fi
if [[ "$dsn_org_id" != "$token_org_id" ]]; then
  echo "ERROR: gate 4 — DSN org-id ($dsn_org_id) != token org-id ($token_org_id) — split-state detected" >&2
  exit 1
fi
```

Also: extend region-probe loop at L46 from `for candidate in de.sentry.io sentry.io` → `for candidate in eu.sentry.io de.sentry.io sentry.io` (eu first, since new DE-org API host is `eu.sentry.io`).

**Gate-call-graph table (Architecture-Strategist F1).** Every entry-point that mutates the Sentry runtime or IaC state MUST traverse the audit script. Inventory:

| Entry-point | Invokes audit script? | Fix |
|---|---|---|
| `reusable-release.yml` (deploy) | Yes (existing — L320,326) | — |
| `.github/workflows/sentry-audit-gate.yml` (this PR — pull_request) | Yes (new) | — |
| `.github/workflows/apply-sentry-infra.yml` (operator `workflow_dispatch:`) | **No (gate-bypass surface)** | **PR-β adds pre-`terraform plan` step invoking `bash apps/web-platform/scripts/sentry-monitors-audit.sh` (fail-closed) before any tfstate mutation** |
| Operator-local `terraform plan` / `apply` (developer machine) | No | Acceptable — developer-loop ergonomics. Pre-commit hook is out of scope. |

Verification: `grep -rn "sentry-monitors-audit.sh" .github/workflows/` MUST return matches in `reusable-release.yml`, `sentry-audit-gate.yml`, AND `apply-sentry-infra.yml` after PR-β.

**Phase 5 — C5: CI workflow + required-check bootstrap.**

Create `.github/workflows/sentry-audit-gate.yml`:
```yaml
name: Sentry Audit Gate
on:
  pull_request:
    paths:
      - 'apps/web-platform/sentry.*.config.ts'
      - 'apps/web-platform/next.config.ts'
      - 'apps/web-platform/infra/sentry/**/*.tf'
      - 'apps/web-platform/scripts/sentry-monitors-audit.sh'
      - '.github/workflows/*sentry*'
permissions:
  contents: read
jobs:
  audit:
    runs-on: ubuntu-latest
    env:
      SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
      SENTRY_API_HOST: ${{ secrets.SENTRY_API_HOST || 'eu.sentry.io' }}  # Kieran P0-1: must be set or region-probe loop relies on /users/me/ scope
      SENTRY_ORG: ${{ secrets.SENTRY_ORG }}
      SENTRY_PROJECT: ${{ secrets.SENTRY_PROJECT }}
      NEXT_PUBLIC_SENTRY_DSN: ${{ secrets.NEXT_PUBLIC_SENTRY_DSN }}
    steps:
      - uses: actions/checkout@v4
      - name: Verify token scope (fail-loud, not continue-on-error)
        run: |
          http=$(curl -s -o /dev/null -w '%{http_code}' \
            -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
            "https://${SENTRY_API_HOST}/api/0/users/me/")
          if [[ "$http" != "200" ]]; then
            echo "::error::SENTRY_AUTH_TOKEN scope check failed (HTTP $http on /users/me/). The CI token likely lacks 'member:read' or 'org:read'. Reconcile token scope before merging Sentry-touching diffs."
            exit 1
          fi
      - run: bash apps/web-platform/scripts/sentry-monitors-audit.sh
```

**Required-check bootstrap (Spec-Flow P0-1 — chicken-and-egg fix).** A required check that has never run cannot block merge of the commit that introduces it. Two-step mechanic:

1. **Within PR-β**, land the workflow file AND `infra/github/main.tf` ruleset extension as **two sequential commits**:
   - Commit A: `sentry-audit-gate.yml` + a no-op edit to `apps/web-platform/scripts/sentry-monitors-audit.sh` (comment-only, e.g., a Phase-4 banner comment) so the `paths:` filter matches → workflow runs on PR-β's HEAD.
   - Commit B: `infra/github/main.tf` ruleset extension adding `Sentry Audit Gate` as required-check.
2. **Verify before merge:** `gh pr checks <PR-β>` shows `Sentry Audit Gate` as `success` against PR-β's latest SHA before invoking `gh pr merge --auto`.

Alternative (acceptable if Step 1 sequencing is fragile): defer the ruleset extension to a **follow-up commit on `main` after PR-β merges** (separate 5-line PR). PR-β itself ships ungated; the gate protects PR-γ onward. Choose this path if Commit-A-paths-trigger-workflow proves brittle.

**Phase 6 — C4: tfstate drop + manifest + serial reimport.**

Per C-2 constraint (R2 backend `use_lockfile = false` — concurrent imports race silently):

1. Pre-flight manifest: `bash apps/web-platform/scripts/sentry-monitors-audit.sh > knowledge-base/legal/audits/sentry-migration-audit-2026-05-DD.md` (operator-run with new token + new SENTRY_ORG).
2. Capture all current tfstate resource addresses:
   ```bash
   cd apps/web-platform/infra/sentry
   terraform state list > /tmp/pre-drop-state.txt
   ```
3. Drop each: `xargs -a /tmp/pre-drop-state.txt -n1 terraform state rm` (sequential, NOT parallel). Verify `terraform state list` returns empty.
4. (Moved to Phase 2 step 9 per Kieran P0-2 — `var.sentry_org` default is now updated atomic with `main.tf:30` `base_url` flip in the same commit, BEFORE Phase 6.)
5. Re-import each resource **strictly serial**, one `terraform import` per resource:
   ```bash
   terraform import sentry_organization.x <org-id>  # if applicable
   terraform import data.sentry_project.web_platform <org-slug>/<project-slug>
   # ... 13 resources total
   ```
   Between each import: confirm `terraform state list` shows the new resource (catches a silent race against R2 backend).
6. `terraform plan` MUST show 0 changes against new DE org (drift-free post-import).
7. Capture post-import manifest and diff against pre-drop in PR-β body per AC10.

**Phase 7 — TR1 revoke (hard-gated on Phase 4 + 5 + 6 green).**

After Phase 4 (audit-gate triple-expansion runs green against new DE org), Phase 5 (CI workflow added + required), and Phase 6 (tfstate clean against new DE org):

- Old phantom-org token: revoke via `eu.sentry.io/settings/.../auth-tokens/` (or whatever surface that token came from — A1 noted A1's token was unattributable owner-side; that token is part of the phantom-org artifact and dies when the org dies in PR-γ).
- The "old token" that actually exists in our control is the US-shadow-org token from A1's tfstate; revoke it via `sentry.io/settings/jikigai/auth-tokens/`.

**Phase 8 — Verification + PA8 backfill (FR12 moved from PR-γ per Arch F4 / DHH P0 reconciliation).**

Moving the PA8 backfill into PR-β closes the live-document-in-`<pending C2 merge>`-state window: as soon as PR-β is mergeable, the backfill commit can land WITH the runtime swap, so Article 30 register never sits in production with the placeholder visible (Arch F4 caught this; DHH P0's "ship runtime + disclosure together" pressure resolves here without collapsing PRs).

Backfill:
- Edit `knowledge-base/legal/article-30-register.md` PA8 §(d) cell at L160: replace `<pending C2 merge>` with `PR #<PR-β-number> merged <ISO date>` and reference the post-swap DE org slug. Land as the final commit of PR-β (timestamp-as-merge-SHA-placeholder; auto-merge resolves at squash time).

Verification (AC6 rewritten per DHH P1 to test ingest, not string shape):

- **AC6 — DSN org-id substring AND real ingest probe.** String-shape: `echo "$NEXT_PUBLIC_SENTRY_DSN" | grep -oE 'o[0-9]+'` returns new org-id `≠ 4511123328466944`. **Plus real ingest probe:** fire one synthetic event via `POST <DSN>/store/` with body `{"event_id":"<uuid>","message":"audit-probe-<ts>","level":"info"}`; wait ≤60s; `curl -H "Authorization: Bearer $TOKEN" "https://eu.sentry.io/api/0/projects/$ORG/$PROJECT/events/<event_id>/"` returns 200 with matching `event_id`. **This is the only AC that closes the loop the incident itself exposed** — string-shape verification is not sufficient because the phantom-org failure mode produced a string that LOOKED correct.
- AC7: CI run of `.github/workflows/sentry-audit-gate.yml` green; required-check added per Phase 5 bootstrap mechanic.
- **AC8 — Per-surface verification + SENTRY_API_TOKEN sweep (Arch F3).** `doppler secrets get SENTRY_DSN -p soleur -c prd --plain` matches new DSN; `gh secret list | grep SENTRY_` matches Doppler shape; `vercel env ls production | grep SENTRY_` matches; same for `.env.example`, `Dockerfile`, `next.config.ts`, `reusable-release.yml`, 9 scheduled workflows. **PLUS:** `grep -rn 'SENTRY_API_TOKEN' apps/ plugins/soleur/skills/postmerge/ knowledge-base/engineering/ops/runbooks/` — every match MUST resolve to the new DE-cluster token; the `audit-sentry-extra-text-references.sh:99-103` fallback-to-`SENTRY_AUTH_TOKEN` chain MUST be either consistent with the rotated value OR explicitly deprecated by Doppler-side aliasing in this PR.
- AC9: old phantom token returns 401 against `https://eu.sentry.io/api/0/users/me/` (proves revocation).
- AC10: `terraform state list | wc -l` returns 13; PR body contains pre/post manifest diff.
- **AC11-pre (manual surrogate, P0 fix #5):** Each of 9 scheduled workflows manually triggered via `gh workflow run <name>.yml`; the resulting check-in event ID captured in PR-β body. Any workflow lacking `workflow_dispatch:` MUST get one added in this PR's diff (no current-state spot check needed — `grep -L "workflow_dispatch:" .github/workflows/scheduled-{cf-token-expiry-check,community-monitor,content-vendor-drift,daily-triage,github-app-drift-guard,oauth-probe,realtime-probe,skill-freshness,terraform-drift}.yml` enumerates the misses).
- **AC14-pre (moved from PR-γ; widened per PR-α review pattern-recognition P1-A):** `grep -rc "<pending C2 merge>" knowledge-base/legal/article-30-register.md knowledge-base/legal/compliance-posture.md` returns 0 for both files (placeholders backfilled in this PR's final commit — PA8 §(d) cell in `article-30-register.md` plus the two PR-β/PR-γ slots in the `#3861` Active row of `compliance-posture.md`).

### PR-γ — Cleanup + Vendor (`-3` worktree)

**Target merge:** When Sentry support responds OR T+14d from ticket open (per Decision #7 / FR14).

**Phase 0 — Pre-flight.**
- Confirm PR-β merged and 9 scheduled workflows have posted ≥1 successful cron-checkin to new DE org.

**Phase 1 — C8a US shadow org teardown.**
- Document state: Team subscription already cancelled effective 2026-06-14; org remains on free plan during forensics window.
- After Sentry support response (Ticket 2 — forensics), document outcome in PR-γ body. If support confirms third-party owner: close US shadow org via `sentry.io/settings/jikigai/general-settings/` → "Close Account".
- If T+14d elapses without authoritative answer: document residual evidence ceiling per FR14.

**Phase 2 — C8b Sentry support tickets.**
- Ticket 1 (billing): operator submits via `sentry.io/support/` with subject "Team trial activated in error — prorated refund request". Body per Decision #9.
- Ticket 2 (forensics): SEPARATE submission (do NOT thread on Ticket 1) with subject "Article 30 sub-processor audit — owner-history confirmation for org 4511…". Body per Decision #9.
- Capture both ticket IDs in PR-γ body per AC13.

**Phase 3 — (moved to PR-β Phase 8.)** PA8 §(d) backfill landed atomic with PR-β runtime swap per Arch F4 reconciliation. PR-γ no longer touches `article-30-register.md`.

**Phase 4 — PIR Phase 8 flip (FR14).**

Per DHH P1 + Code-Simplicity P1: cut the institutional-precedent prose. The C5 audit-gate triple-expansion (now 4 gates per Arch F2) IS the recurrence-prevention signal; a 3-line closure citing the PR-β SHA is sufficient. If a second PIR ever benefits from the same shape, extract the template then from real n=2 precedent.

Edit `knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md`:
1. L8: `status: open` → `status: resolved`.
2. Append new section `## Phase 8 — Recovery Completeness` before `## Who was affected (by role)` at L75:

```markdown
## Phase 8 — Recovery Completeness

Status flipped from `open` to `resolved` on <ISO date>. Three conditions all held:

- **Phantom emission halted.** Runtime DSN points at new DE org (orgInternalId `o<new-id>`, ≠ `4511123328466944`). Evidence: PR #<PR-β> merged <ISO date>, audit script's 4-gate (org-reachable + project-scope + write-probe + DSN-org-id-match) green against new org.
- **Recurrence prevention deployed.** `.github/workflows/sentry-audit-gate.yml` is a required-check on `main`-bound PRs; `apply-sentry-infra.yml` invokes the audit script pre-`terraform plan`; the existing L60-103 cluster-substring check stays load-bearing as additive defense.
- **Vendor accountability closure** (one of the following):
  - **3a — Authoritative confirmation third-party owner.** Sentry support confirmed org `4511123328466944` is not Jikigai. US shadow org closed per Phase 1. Ticket <ID>, <ISO date>.
  - **3b — "This org is yours" (STOP).** Sentry support contradicts the phantom-org premise. PIR root-cause re-opened; PR-γ blocks until CLO + CTO re-assessment.
  - **3c — Non-disclosure / compliant refusal.** Sentry support declined disclosure per <ticket-ID>, <date>. Residual evidence ceiling: "unknown — declined". PIR resolved with documented residual.
  - **3d — T+14d timeout** (where T = Ticket 2 open ISO date `<date>`, T+14d = `<date>`). Treated as 3c with residual ceiling "no response". Each Sentry follow-up question pauses the clock until operator responds; clock resumes on next vendor message.
```

**Phase 5 — W1/W2/W5 issues filed (W4 dropped per Code-Simplicity P2).**

`gh issue create` for each:
- W1: "Hard rule `hr-prereq-playwright-first-then-credential-handoff` — Playwright must verify host BEFORE operator types credentials." Labels: `domain/process`, `priority/p2-medium`.
- W2: "Extend `soleur:brainstorm` Phase 1.0.5 premise check to named URL substrings (currently checks only numerical claims)." Labels: `domain/engineering`, `skill:brainstorm`, `priority/p3-low`.
- W5: "`/soleur:compound` fail-friendly when on main (offer to create worktree rather than hard-abort)." Labels: `domain/engineering`, `skill:compound`, `priority/p3-low`.

(W4 worktree-manager `.mcp.json` config-flag injection — **dropped**: TR2 operator-handoff already solves headless durably without code; W1 hard-rule codifies the gate behaviorally and is the highest-leverage of the four. W3 absorbed into C5 — already done.)

Verify each label exists via `gh label list | grep -E "^<label>\b"` before filing per `2026-05-06-plan-prescribed-labels-must-be-verified.md`. If a label is missing, substitute closest existing.

**Phase 6 — Verification.**

- AC12: US shadow org status documented in PR-γ body.
- AC13: Both ticket IDs captured.
- AC14: **(moved to PR-β Phase 8 AC14-pre.)** No longer in PR-γ scope.
- AC15: `grep -nE "^status: resolved" knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md` returns L8; Phase 8 section present (4-branch Gate 3 enumerated; 3a/3b/3c/3d resolution selected by operator with evidence).
- AC16: **3 W-issues** (W1/W2/W5; W4 dropped) listed in PR-γ body with `gh issue view <N>` returning `state: open`.

## TR-Level Mechanics (the 5 open questions)

### TR2 — Playwright headed-vs-headless reconciliation

**Problem:** Cascade learning notes `@playwright/mcp@0.0.75` ignores `--user-data-dir` and spawns `--headless`. Today's `.mcp.json` uses `@playwright/mcp@latest` (unpinned) + only `--user-data-dir`. Credential-entry flow at C1 cannot proceed under headless (operator can't type into invisible window).

**Mechanic (PR-β Phase 0):**
1. Before starting C1 navigation, run `pgrep -fa chromium | grep -- --headless`.
2. If output empty → continue to C1 (Playwright spawned headed).
3. If output non-empty → MCP server resolved to a headless-default version. Two recovery paths:
   - **Pin-and-restart:** Edit `.mcp.json` to pin a known-headed version (e.g., `@playwright/mcp@0.0.74` if 0.0.75 is the regression cutoff); restart MCP server via Claude Code session restart.
   - **Operator hand-off (preferred if pin uncertain):** Close Playwright MCP for this step; operator opens https://eu.sentry.io/auth/register/ in a real browser; operator narrates progress textually; Playwright resumes for post-signup navigation (token mint, audit-script run) where headless is fine because no credential entry is involved.

**Why this is a gate, not an assumption:** Cascade learning documents the failure mode directly — the `--config` flag pattern from `2026-05-15-playwright-mcp-headed-and-persistent-profile.md` was assumed to work today; today's session proved it didn't. The pre-flight is the only durable signal.

### TR3 — DE org slug collision check

**Problem:** Decision #3 + Open Question #2: `jikigai` slug may be taken on `eu.sentry.io`.

**Mechanic (PR-β Phase 0):**
1. Logged-out probe: `curl -s -o /dev/null -w '%{http_code}' https://eu.sentry.io/organizations/jikigai/`.
2. `404 Not Found` → slug available; use `jikigai` (matches current `var.sentry_org` default; no cascading rename).
3. `200 OK` / `302 Found` / auth-redirect → slug taken; default to `jikigai-eu` (matches PA8 §5(2) wording vector). Cascade rename through:
   - `var.sentry_org` default in `apps/web-platform/infra/sentry/variables.tf`.
   - 9 scheduled workflows referencing `SENTRY_ORG` (verify via `grep -rn 'SENTRY_ORG' .github/workflows/scheduled-*.yml`).
   - Doppler `prd` `SENTRY_ORG` value.
   - GH repo secret `SENTRY_ORG` value.
   - Vercel envs `SENTRY_ORG` value.
   - PR-β commit message + PR body documenting the slug-collision recovery.

**Slug-rename verification:** `grep -rn 'jikigai\b' apps/web-platform/infra/sentry/ apps/web-platform/sentry.*.config.ts .github/workflows/` MUST return 0 references to bare `jikigai` post-rename (all hits MUST be `jikigai-eu` if rename was forced).

### TR4 — PIR Phase 8 flip criteria

**Problem:** Capability gap #1: no prior PIR Phase-8 precedent. Per DHH P1 + Code-Simplicity P1 + Arch F5 (template doesn't generalize across incident classes): do NOT pre-pave an institutional template on n=1 sample. Author the closure for this specific incident; if a second PIR ever benefits from the same shape, extract the template then.

**Mechanic (PR-γ Phase 4):** 3-bullet `## Phase 8 — Recovery Completeness` section authored inline per PR-γ Phase 4 above (phantom-emission-halted + recurrence-prevention-deployed + vendor-accountability-closed). Gate 3 enumerated as 4 operator-selectable branches (3a/3b/3c/3d) per Spec-Flow P1-4 to disambiguate Sentry response semantics. No template prose; no "future PIRs MUST" claims; no inherited prose dependency.

### TR5 — Cloudflare CSP report-uri cache-purge mechanic

**Problem:** `SENTRY_CSP_REPORT_URI` is set in middleware response headers (`apps/web-platform/middleware.ts:41` consumed by `buildCspHeader` at L4). After secret rotation, server emits the new `report-uri` value, but Cloudflare may cache HTML responses including the CSP header; cached pages browsers see continue to POST CSP violation reports to the old DSN endpoint until cache expires or is purged.

**Mechanic (PR-β Phase 2 step 10):**

Per `2026-04-18-fix-purge-cf-cache-on-share-revoke-plan.md:15` precedent — Cloudflare API endpoint `POST /client/v4/zones/<zone>/purge_cache`.

Plan options (verified against the cloudflare-token Doppler scope):
- **Purge by URL** (preferred — surgical): `POST /client/v4/zones/<zone>/purge_cache` with body `{"files":["https://app.soleur.ai/"]}`. Targets just the root HTML; only HTML responses carry the CSP header. **Action:** add a single Doppler-token-authenticated curl call to PR-β's deploy runbook (operator-run after `reusable-release.yml` completes).
- **Purge everything** (acceptable fallback if URL enumeration is incomplete): `POST /client/v4/zones/<zone>/purge_cache` with body `{"purge_everything":true}`. Triggers cold-cache rebuild — bounded impact (cache refills within minutes of organic traffic).

**Plan response:** PR-β documents the purge-by-URL curl in the deploy runbook; operator runs it within the 2h observation window. CSP violation reports posting to old DSN during the cache-warm window are accepted as documented residual — they go to a now-revoked DSN (Phase 7) and 401, which is harmless.

**Verification:** Post-purge, `curl -sI https://app.soleur.ai/ | grep -i content-security-policy | grep -oE 'report-uri [^;]+'` returns the new DE org `report-uri`. (Note: this verifies origin response, not edge — for edge verification, hit Cloudflare PoPs via `curl --resolve app.soleur.ai:443:<cf-edge-ip>`.)

### TR1 + C-2 — R2 backend serial-import sequencing

**Problem:** R2 backend `use_lockfile = false` (R2 doesn't support S3 conditional writes). Concurrent `terraform import` against the same state file race silently — last writer wins; missing imports go undetected.

**Mechanic (PR-β Phase 6):** Strictly **serial**, one `terraform import` invocation at a time. Between each import:
1. `terraform state list | grep -F "<resource-address>"` MUST return the just-imported resource before invoking the next import.
2. Operator-driven (NOT scripted parallel) — even an `xargs -n1` loop is acceptable, but **NOT** `xargs -P2+` or `parallel` or background `&`.
3. Capture each import's stdout to `/tmp/sentry-import-<N>.log`; concatenate into PR-β body per AC10 evidence.

**Pre-flight gate:** `terraform state list | wc -l` MUST return 0 immediately before re-import (verifies Phase 6 step 3 `state rm` loop fully drained the state).

## Acceptance Criteria

### Pre-merge (PR-α)

- AC1: PA8 §(d) cell at `knowledge-base/legal/article-30-register.md:160` contains phantom-ingest disclosure paragraph. **Verify:** `grep -nE "phantom-ingest|destination-unreachable" knowledge-base/legal/article-30-register.md` returns ≥1 match.
- AC2: CLO sign-off captured in PR-α body.
- AC3: ADR-031 no longer references the 404 URL. **Verify:** `grep -c "de.sentry.io/settings" knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` returns 0. Glossary section present: `grep -c "## Cluster / Host Glossary" knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` returns 1.
- AC4: compliance-posture.md cross-references PIR. **Verify:** `grep -nE "sentry-residency-a2|phantom-ingest|3861" knowledge-base/legal/compliance-posture.md` returns ≥1 match in Active Compliance Items section.
- AC5: PR-α merged by 2026-05-19T12:50Z (Art 33 procedural gate buffer).

### Pre-merge (PR-β)

- **AC6 (DHH P1 — real ingest probe, not string-shape only):** New DE org provisioned AND ingest path closed end-to-end. **Verify (string):** `echo "$NEXT_PUBLIC_SENTRY_DSN" | grep -oE 'o[0-9]+'` returns new org-id; `[[ "$NEW_ORG_ID" != "4511123328466944" ]]`. **Verify (ingest, load-bearing):** fire synthetic event via `POST <DSN>/store/` with body `{"event_id":"<uuid>","message":"audit-probe-<ts>","level":"info"}`; wait ≤60s; `curl -H "Authorization: Bearer $TOKEN" "https://eu.sentry.io/api/0/projects/$ORG/$PROJECT/events/<event_id>/"` returns 200 with matching `event_id`. **The ingest probe is the only verification that closes the loop the incident itself exposed.**
- **AC7:** 4-gate audit-script green (Gate 1 org-reachable + Gate 2 project-scope + Gate 3 write-probe + Gate 4 DSN-org-id-match); CI workflow added with `SENTRY_API_HOST` env (Kieran P0-1) + token-scope pre-check (fail-loud, not `continue-on-error`); required-check bootstrap per Phase 5 mechanic. **Verify:** `gh workflow list | grep -F "Sentry Audit Gate"`; `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[] | .context'` includes `Sentry Audit Gate`.
- **AC8 (Arch F3 — extended SENTRY_API_TOKEN sweep):** All secret surfaces hold new DSN/token values. **Verify per-surface:** `doppler secrets get SENTRY_DSN -p soleur -c prd --plain | grep -F "$NEW_ORG_ID"` AND `gh secret list | grep -F "NEXT_PUBLIC_SENTRY_DSN"` AND `vercel env pull /tmp/.env.vercel && grep -F "$NEW_ORG_ID" /tmp/.env.vercel`. **PLUS namespace-divergence sweep:** `grep -rn 'SENTRY_API_TOKEN' apps/ plugins/soleur/skills/postmerge/ knowledge-base/engineering/ops/runbooks/` — every match MUST resolve to the new DE-cluster value; `audit-sentry-extra-text-references.sh:99-103` fallback-to-`SENTRY_AUTH_TOKEN` documented (and either consistent or explicitly deprecated in this PR).
- **AC9:** Old phantom DSN not referenced in current deployment. **Verify:** `grep -rn "4511123328466944" apps/web-platform/ .github/workflows/scheduled-*.yml` returns 0 hits (after rotation).
- **AC10:** tfstate has 13 resources imported against new DE org. **Verify:** `cd apps/web-platform/infra/sentry && terraform state list | wc -l` returns 13; `terraform plan` shows 0 changes; pre/post manifest diff captured in PR body.
- **AC11-pre (Spec-Flow P0-2 — manual surrogate):** Each of 9 scheduled workflows manually dispatched via `gh workflow run <name>.yml`; first manual-trigger check-in event ID captured in PR-β body. Any workflow lacking `workflow_dispatch:` MUST get one added in this PR's diff.
- **AC14-pre (Arch F4 — moved from PR-γ):** `grep -c "<pending C2 merge>" knowledge-base/legal/article-30-register.md` returns 0 (PA8 §(d) placeholder backfilled with PR-β merge SHA / merge ISO date as part of PR-β's final commit; shrinks the live-pending-state window).
- **AC-gate-coverage (Arch F1):** `grep -l "sentry-monitors-audit.sh" .github/workflows/*.yml` returns at least `reusable-release.yml`, `sentry-audit-gate.yml`, AND `apply-sentry-infra.yml` (confirms `apply-sentry-infra.yml` gate-bypass surface is closed).

### Post-merge (operator)

- **AC9-post:** Old token revoked. **Verify:** `curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer <OLD_TOKEN>" https://eu.sentry.io/api/0/users/me/` returns 401.
- **AC11-post (Spec-Flow P0-2 — reclassified strictly post-merge):** Each of 9 scheduled workflows' first **organic** scheduled run within 7 days of merge lands a cron-checkin in the new DE org's monitor dashboard at `eu.sentry.io/organizations/<slug>/crons/`. Captured in PR-β post-merge follow-up comment OR linked from PR-γ Phase 0 pre-flight gate.

### Pre-merge (PR-γ)

- AC12: US shadow org status documented.
- AC13: Both Sentry support ticket IDs captured.
- AC14: `<pending C2 merge>` placeholder backfilled. **Verify:** `grep -rc "<pending C2 merge>" knowledge-base/legal/article-30-register.md knowledge-base/legal/compliance-posture.md` returns 0 for both files. (Widened per PR-α review pattern-recognition P1-A to cover the placeholder-syntax-unified compliance-posture.md row.)
- AC15: PIR status `resolved`; Phase 8 section present. **Verify:** `grep -nE "^status: resolved" knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md` returns L8; `grep -c "## Phase 8 — Recovery Completeness" ...` returns 1.
- AC16: W1/W2/W4/W5 follow-up issues filed. **Verify:** each `gh issue view <N>` returns `state: open` with title matching W-spec.

### Post-merge (operator) — PR-γ

- AC15-post: Sentry support response received OR T+14d elapsed; residual evidence ceiling documented per Decision #7.
- AC12-post: US shadow org closed (if Sentry support confirms third-party owner) OR documented residual (if T+14d timeout).

## Constraints

- C-1: Art 33 CNIL deadline 2026-05-19T12:50Z gates PR-α merge. Brand-survival threshold `single-user incident` gates all Branch C PRs at review.
- C-2: R2 backend `use_lockfile = false` — `terraform import` strictly serial (TR1 + Phase 6 mechanic).
- C-3: `@playwright/mcp@latest` headless-default regression — TR2 pre-flight required, not assumed.
- C-4: Vendor-relationship preservation — refund posture amicable-with-receipts; aggressive forensics language confined to Ticket 2 separate routing.
- C-5: PIR Phase 8 closure is authored for this incident only (not as institutional template); n=1 sample doesn't justify pre-paved precedent. If a second PIR ever benefits, extract template then.

## Hypotheses

None active. Brainstorm closed all decision points; no SSH/network-connectivity surface in this plan to trigger the network-outage checklist (`hr-ssh-diagnosis-verify-firewall`).

## Sharp Edges

- **Sibling-worktree creation MUST be from updated `main` after PR-α merges.** If `feat-sentry-residency-a2-branch-c-2` is created from this PR-α branch instead of post-merge `main`, the new worktree inherits the unmerged PR-α diff and creates a phantom dependency chain. Use `git worktree add -b feat-sentry-residency-a2-branch-c-2 origin/main` AFTER `git fetch origin main`.
- **Doppler `prd` writes propagate per-deploy to Vercel, not per-push.** PR-β Phase 2 step 3 (Vercel envs) must complete BEFORE the deploy that brings the rotation live; otherwise the deploy serves the new DSN client-side (Vercel env) but old DSN server-side (still-old Doppler value resolved at build time) — the exact split-emit failure mode the brainstorm User-Brand-Impact section names.
- **Old token revocation is hard-gated on 3 prior conditions** (audit-gate green + tfstate clean + 2h observation window with both synthetic and real event). Revoking earlier risks dropping a real prod error into the now-revoked DSN with no fallback signal — a Brand-Survival single-user-incident realization of the very threshold this plan declares.
- **CSP report-uri cache-purge** is a soft-failure surface — CSP violation reports posting to old DSN during cache-warm window 401 against the revoked token (harmless). Operator runs the purge but does NOT need to block on its completion.
- **TR3 slug collision rename** must touch ALL 9 scheduled workflows in the SAME commit as `var.sentry_org` default — a partial rename produces silent half-state where 1 workflow still posts to phantom-named org slug (which now refers to a non-existent org → 404 silent).
- **Sentry support Ticket 2 (forensics) MUST be a separate submission**, NOT a reply to Ticket 1 (billing). Threading the two routes both to the same agent, who must weigh billing-friendly tone against forensics-aggressive language — the asymmetry brainstorm Decision #9 avoids.
- **PIR Phase 8 closure is incident-specific, not a template.** Per DHH P1 / Code-Simplicity P1 / Arch F5 — author the 3-bullet closure for this incident; do NOT pre-pave an institutional template on n=1. The audit-gate's effectiveness comes from the script's exit codes, not the runbook's prose density.
- **`@playwright/mcp@latest` is unpinned**; future MCP version bumps may regress the headed posture again. TR2 operator-handoff path is the durable mitigation; W4 (`.mcp.json` config-flag injection) was dropped per Code-Simplicity P2 — the operator-handoff is sufficient.
- **`apply-sentry-infra.yml` is a gate-bypass surface** unless the pre-`terraform plan` audit-script invocation is wired in PR-β (Arch F1). Any future `workflow_dispatch:` entrypoint mutating Sentry IaC MUST traverse the audit gate; the gate-call-graph table in Phase 4 is the inventory.
- **Required-check chicken-and-egg:** a newly-added required check has no completed runs on the introducing commit. Phase 5 bootstrap mechanic (2-commit sequence with a comment-only paths-trigger in commit A) is load-bearing; do NOT add to ruleset without the trigger.
- **PR-α deadline-pressure abort path:** if the PR slips past 2026-05-19T12:50Z, Phase -1's T-24h / T-2h checkpoints route the CLO to file CNIL directly with PR #3904 as evidence-in-flight. The disclosure is the gate, not the merged commit.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-16-sentry-residency-a2-branch-c-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-sentry-residency-a2-branch-c-1/spec.md`
- PIR: `knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md`
- A1 plan: `knowledge-base/project/plans/2026-05-15-feat-sentry-residency-cleanup-plan.md`
- A1 PR: #3863 (merged 2026-05-15)
- Umbrella issue: #3861
- ADR-031: `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`
- Cascade learning: `knowledge-base/project/learnings/2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline.md`
- Today's load-bearing learnings:
  - `2026-05-16-sentry-relocation-tooling-is-self-hosted-to-saas-only.md`
  - `2026-05-16-procedural-deadline-disclosure-is-the-critical-path-not-remediation.md`
  - `2026-05-16-repo-research-must-inventory-scheduled-ci-workflows-for-secret-sweeps.md`
- Cloudflare purge precedent: `knowledge-base/project/plans/2026-04-18-fix-purge-cf-cache-on-share-revoke-plan.md:15`
- Authoritative residency learnings:
  - `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md`
  - `2026-05-15-token-namespace-divergence-across-secret-stores.md`
  - `2026-05-15-sentry-iac-billing-and-quirks.md`
  - `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`
