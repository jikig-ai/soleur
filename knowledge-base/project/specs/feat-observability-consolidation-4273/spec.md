---
title: Observability provider consolidation — Phase 1 (P0 compliance) + Phase 2 (D-native) + Phase 3 (60-day re-decide)
date: 2026-05-22
issue: 4273
pr: 4293
branch: feat-observability-consolidation-4273
brainstorm: knowledge-base/project/brainstorms/2026-05-22-observability-consolidation-4273-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec-ready
---

# Feature: Observability provider consolidation (D-native + 60-day window)

## Problem Statement

TR9 PR-5 (#4250) shipped a 5-layer observability stack — Sentry holds Layers 1+2+5 (errors, breadcrumbs, cron monitors, releases), Better Stack holds heartbeats and now Logs (post-#4277/#4278/#4279, all 2026-05-21), Vector 0.43.1 on the Hetzner inngest VM ships journald + host_metrics. The "Path D interim fix" the issue body anticipated already shipped, but in a fallback shape: Vector 0.43.1 lacks the native `better_stack_logs` sink, so #4279 routed events via a generic HTTP sink against `https://in.logs.betterstack.com/`.

Brainstorm domain leaders surfaced two non-negotiable findings that must remediate independent of the long-term consolidation choice:

1. **Better Stack is currently un-disclosed as a sub-processor** in the Article 30 register, Vendor DPA table, Privacy Policy §5.10, Data Protection Disclosure §2.3(m), and GDPR Policy. Heartbeats-only Better Stack was arguably below the materiality threshold; journald shipping is not. Today's posture is non-compliant under Art. 30(1)(d) + Art. 13(1)(e).
2. **`vector.toml` has zero PII redaction** in its VRL transforms. `tag_journald` (`apps/web-platform/infra/vector.toml:48-55`) forwards raw `message` + `host` fields to Better Stack. Journald CRIT entries from `inngest-server` can include workspace IDs, OAuth callback URLs, and email substrings in stack frames.

The remaining strategic question (consolidate to Sentry vs stay multi-provider vs migrate to Datadog) is decided by the brainstorm: **Path B (Datadog) and Path C (defer Layer 3+4) are rejected unconditionally**; **Path D-native (Vector bump → native sink) ships next, with Path A (Sentry-only consolidation) re-evaluated at a 60-day evidence checkpoint.**

## Goals

- Close the Article 30 / Vendor DPA / Privacy Policy / GDPR Policy gap for Better Stack as a sub-processor.
- Add a PII-redacting VRL transform to `vector.toml` before any further Better Stack ingest tuning.
- Verify and pin the Better Stack ingestion endpoint to the EU region.
- Bump Vector to ≥0.44.0 (or whichever release first carries the native `better_stack_logs` sink) and rewrite `vector.toml` to use the native sink instead of generic HTTP.
- Add a `vector validate` CI step to gate substrate-version bumps.
- File a calendar-driven follow-up issue for the 60-day re-decision (~2026-07-21).
- File deferred capability-gap issues: Sentry-envelope contract test (prerequisite for any future Path A); Vector staging VM (`soleur-inngest-dev`); Better Stack residency-check skill (analogue of #3865).

## Non-Goals

- **Migrating to Datadog (Path B).** Rejected unconditionally at alpha-internal scale (+$140-155/mo recurring + $3-4.5k upfront migration; would re-implement 135 Sentry SDK call sites + 10 cron monitors; Datadog APM ingests OAuth tokens / emails in request bodies by default).
- **Deferring Layer 3+4 / pausing Vector (Path C).** Violates `hr-no-ssh-fallback-in-runbooks` for kernel oops / inngest panic class.
- **Consolidating to Sentry-only sidecar (Path A) in this PR.** Re-entering Vector↔Sentry envelope coupling that already burned 6 PRs (#4271-#4279) without the prerequisite envelope-contract test is unsafe. Path A is on the table at the 60-day re-decision, not now.
- **Provisioning a Vector staging VM in this PR.** Mitigated for Phase 2 by `vector validate` in CI. Formal provisioning deferred to a follow-up.
- **Writing the Sentry-envelope contract test in this PR.** Deferred to a follow-up issue; not needed unless 60-day re-decision selects Path A.
- **Touching Sentry's existing residency / TF / Monitors-Alerts split issues** (#3814, #3815, #3865, #3866). Those are independent and unchanged.

## Functional Requirements

### FR1: Article 30 + Vendor DPA disclosure for Better Stack

Add Better Stack as a recipient in:
- `knowledge-base/legal/article-30-register.md` — PA8 §(d) (recipients) + §(c)(i) (categories of recipients) + §(e) (third-country transfers if applicable) + §(f) (retention).
- `knowledge-base/legal/compliance-posture.md` — Vendor DPA table row.
- `docs/legal/privacy-policy.md` §5.10 — sub-processor list.
- `docs/legal/data-protection-disclosure.md` §2.3(m) — sub-processors.
- `docs/legal/gdpr-policy.md` — operational-telemetry recipients bullet.

Each entry must name: vendor, processing purpose ("operational log + metric shipping for incident detection"), data categories (pseudonymised user IDs via FR2, error messages, host metrics — NO raw PII), retention (default Better Stack retention; cite Logs paid-tier value), region (FR3), DPA signing status.

### FR2: PII-redacting VRL transform in `vector.toml`

Add a VRL `remap` transform between `inngest_journald` / `system_journald` sources and the existing `tag_journald` transform that:
- Drops the entire `message` field if it matches any of: email regex (`\b[\w.+-]+@[\w-]+\.[\w.-]+\b`), OAuth callback path regex (`/api/auth/callback/`), or Authorization header substring (`Bearer `, `Basic `).
- Otherwise replaces email substrings inside `message` with `[email]` and OAuth-callback URLs with `/api/auth/callback/[redacted]`.
- Hashes any `user_id`, `userId`, `workspace_id`, `workspaceId` field via HMAC-SHA256 with key from `${VECTOR_HMAC_KEY}` Doppler secret. Output field is `user_id_hash` / `workspace_id_hash`; original field is removed. Matches the ADR-029 rename-at-boundary pattern used by `apps/web-platform/server/sentry-scrub.ts`.

Transform must apply BEFORE any sink ingests the event.

### FR3: Better Stack EU endpoint pin

Verify Better Stack ingestion endpoint region. Update `vector.toml:99` sink URI to the EU-region endpoint (e.g., `https://in.eu.logs.betterstack.com/` if EU ingest is available on the current tier; otherwise document the gap and re-evaluate provider). Add a comment block above the sink declaration recording the verification source (Better Stack docs URL, date, expected region).

### FR4: Vector substrate bump (Path D-native)

Bump Vector binary in `apps/web-platform/infra/inngest-bootstrap.sh` (binary install pin) and `apps/web-platform/infra/vector.tf` (version variable) to the lowest version that carries the native `better_stack_logs` sink. Rewrite `vector.toml:[sinks.betterstack]` from `type = "http"` to `type = "better_stack_logs"` with the corresponding native-sink config. Retain the same `tag_journald` + `tag_metrics` + new FR2 redaction transform pipeline.

Tag the inngest container as `vinngest-v1.2.0` after merge.

### FR5: `vector validate` CI gate

Add a CI step to the existing `apply-web-platform-infra.yml` workflow (or equivalent) that runs `vector validate apps/web-platform/infra/vector.toml` against the new Vector binary version pinned in `vector.tf` BEFORE the binary flip on prd. Failure blocks the deploy.

### FR6: 60-day re-decision calendar trigger

File a new GitHub issue titled `re-evaluate observability consolidation (60-day checkpoint from #4273)`, milestoned for `Post-MVP / Later`, with body containing:
- Re-decision criteria (4 evidence axes from the brainstorm): Sentry log bill at observed volume, Better Stack Logs paid-tier cost at observed volume, Sentry envelope silent-ingestion incidents in window, operator-SSH-RCA incidents in window.
- Upstream constraint state to recheck: #3814 (Sentry Monitors/Alerts split), #3815 (multi-tenant Sentry DPA), #3865 (Sentry residency check skill), #3866 (Doppler TF_VAR_sentry_region).
- Target re-decision date: 2026-07-21.

### FR7: Deferred capability-gap issues

File three new GitHub issues:
- `feat: Sentry-envelope contract test in CI (prerequisite for any future Path A consolidation)` — Post-MVP / Later. Reference brainstorm.
- `feat: Vector staging VM (soleur-inngest-dev) for safe substrate bumps` — Post-MVP / Later. Reference brainstorm.
- `feat: Better Stack residency-check skill (analogue of #3865 Sentry skill)` — Post-MVP / Later. Reference brainstorm.

## Technical Requirements

### TR1: VRL redaction implementation

Use Vector VRL `remap` with `match()` for regex detection (NOT external lookup); `to_string()` + `replace()` for in-place substring replacement; `hmac()` is not a VRL stdlib function — use `sha2()` over `to_string(.field) + ${VECTOR_HMAC_KEY}` as the hashing surrogate, OR (preferred) `encode_base64(hmac(...))` if running on a Vector release that includes the `hmac` VRL function (gate this on Vector ≥0.44.0). The exact hashing primitive is part of FR2 implementation; the contract is "deterministic pseudonymisation that matches the Sentry rename-at-boundary scheme."

Add tests in `apps/web-platform/test/infra/vector-redaction.test.sh` (or equivalent) that feed sample journald events through `vector vrl --input <fixture>` and assert redaction.

### TR2: Article 33 anchor-of-record

The Article 33 breach-notification clock anchor (`first_observed_at`) lives in PA8 §(b)(ii) — Sentry-side today. Document explicitly that under D-native multi-provider, **Sentry remains the canonical anchor**: any Better Stack-only log evidence found post-incident is corroborating, not anchoring. If the 60-day re-decision selects Path A, this is unchanged. If it selects continued multi-provider, file an ADR before that anniversary.

### TR3: GDPR gate at plan Phase 2.7

The implementing plan (`/soleur:plan`) MUST invoke `/soleur:gdpr-gate` at Phase 2.7. Expected findings (per CLO assessment):
- `GDPR-Art-30` finding: Better Stack disclosure gap (closes via FR1).
- `GDPR-Art-13` finding: Privacy Policy §5.10 sub-processor list update (closes via FR1).
- `GDPR-DataMin-1` finding: journald payloads carry un-pseudonymised identifiers (closes via FR2).

### TR4: Observability layer-citation discipline (`hr-observability-layer-citation`)

The implementing plan's `## Observability` block MUST cite Layer 3+4 path explicitly post-bump: `Vector ≥0.44.0 → native better_stack_logs sink → Better Stack Logs (EU endpoint pinned) → query via Better Stack public URL (no SSH, no prod Doppler)`. The `discoverability_test.command` must complete without SSH.

### TR5: No SSH in any runbook step

All operational steps (deploy, rollback, verify) must complete via:
- `gh run` / `gh workflow run` for CI invocation.
- Sentry public dashboard URL for cron-monitor verification.
- Better Stack public URL for log/metric query.
- Doppler CLI (read-only) for env-var checks.

`hr-no-ssh-fallback-in-runbooks` is binding.

### TR6: Reversibility

FR4 (Vector bump) must be reversible by reverting `vector.tf` pin + rolling back the `vinngest-vX.Y.Z` container tag. FR2 (VRL redaction) is independently reversible by reverting `vector.toml`. FR1/FR3 (legal disclosure + endpoint pin) are not auto-reversible; an undo PR would re-introduce a documented un-disclosed-sub-processor posture and must NOT be filed under any path.

### TR7: Sub-processor list propagation

Privacy Policy and Data Protection Disclosure are markdown-sourced. FR1 changes are visible to users on next docs deploy. No active customer notice is required at alpha-internal scale (no signed customers), but the PR description must call out the timing in case a customer signs between PR merge and docs deploy. The `compliance-posture.md` and `article-30-register.md` changes are the binding-record updates regardless of customer count.

## Open questions (carried from brainstorm, to resolve at plan time)

- Pause-or-fix decision: pause `vector.service` until FR2 redaction VRL ships, or bundle redaction with the Phase 1 PR? **Default: bundle.** Operator-incident class (CRIT kernel events without redaction) is bounded; full pause would lose Layer 3+4 observability and the OAuth canary safety net for the duration of the bundle PR.
- Better Stack EU endpoint URI (FR3) — needs verification before vector.toml edit.
- Whether the VRL `hmac` function is available on the bump target Vector version, or whether to fall back to `sha2(... + key)` as the FR2 hashing primitive.

## Plan-Time Corrections

Corrections folded into PR #4293 implementation that diverge from the original spec or brainstorm wording. Tracked here so the spec remains the canonical record of the as-built shape.

- **C1 — Phase 2 "D-native Vector bump" DROPPED.** Spec FR4 and brainstorm Decision #1 prescribed bumping Vector to ≥0.44.0 for the native `better_stack_logs` sink. **The native sink does not exist in any Vector release** — Vector PR #19274 (proposed sink, opened 2023-11-30) closed unmerged 2025-01-27 (verified `gh api repos/vectordotdev/vector/pulls/19274`). Better Stack's own integration docs (`https://betterstack.com/docs/logs/vector/`) prescribe `type = "http"` — generic HTTP IS the canonical vendor-recommended pattern. The `vector validate` + `vector vrl` CI gate (FR5) is retained for VRL safety on future `vector.toml` edits.
- **C2 — Better Stack disclosure is correction-of-falsified-claim, not addition-to-blank-cell.** DPD §2.3(m) line 103 already mentioned Better Stack — but ONLY as the inngest-server heartbeat recipient with the literal "NOT a sub-processor of personal data" claim. PR #4279 falsified that. The Phase 5 remediation REPLACES the sentence (splitting Better Stack into two recipient roles: heartbeat unchanged, Logs newly added) rather than filling a blank cell.
- **C3 — VRL pepper is `SENTRY_USERID_PEPPER` (reused per ADR-029 §I4), NOT a new `${VECTOR_HMAC_KEY}`.** Spec FR3 had implied a separate VRL key; ADR-029 §I4 single-source-of-truth requires reuse. `apps/web-platform/infra/inngest-bootstrap.sh:380` already wraps `vector.service` ExecStart in `doppler run --project soleur --config prd`, and `SENTRY_USERID_PEPPER` is already in Doppler prd (verified Phase 0.3 — 65-char value, read-only check).
- **C4 — Issue #4211 (Inngest cron substrate migration) CLOSED 2026-05-22.** Spec referenced #4211 as IN-PROGRESS. The OAuth canary lives on Sentry cron monitor (`scheduled_oauth_probe`) and is unaffected by Phase 1.
- **C5 — FR2 expanded from ONE transform to THREE.** Original spec FR3 had a single `pii_scrub_*` VRL transform. Plan-time GDPR-gate + spec-flow review surfaced (a) Art-9 user-content key drop must run FIRST (`pii_scrub_drop_userdata`), (b) structured pino-shape rename must run SECOND (`pii_scrub_structured`), (c) string-level regex backstop must run LAST and ONLY on the unparsed branch (`pii_scrub_string`) to avoid JSON corruption per Arch-F2 ordering fix. The three-transform pipeline is the as-built shape; the single-transform shape would have shipped a kernel-oops `userid=<uuid>` substring leak AND would have corrupted clean pino payloads when the regex ran over re-serialized JSON.
- **C6 — FR8 gdpr-gate regex extension DROPPED from this PR; filed as follow-up #4321.** Spec FR8 prescribed extending the `gdpr-gate` skill's canonical regex to include `apps/web-platform/infra/vector\.toml$` so future VRL edits automatically trip the gate. Simplicity review carved this out as a separate follow-up issue to keep PR #4293 scope bounded to the P0 compliance closure. **`hr-gdpr-gate-on-regulated-data-surfaces`** already covers `apps/web-platform/infra/**` heuristically via the operator-driven invocation path; the FR8 extension is a hardening, not a load-bearing closure of the falsified-disclosure gap.
- **C7 — Privacy Policy Better Stack disclosure landed as NEW §5.14, NOT §5.11 with renumber.** Plan §5.3 prescribed inserting §5.11 with renumber of §5.11→§5.12→§5.13. Renumbering would have touched 7+ cross-ref sites across `docs/legal/gdpr-policy.md`, `knowledge-base/legal/compliance-posture.md`, `knowledge-base/legal/audits/2026-05-counsel-review-4051.md`, `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md`, `knowledge-base/legal/article-30-register.md`, the mirror in `plugins/soleur/docs/pages/legal/privacy-policy.md`, and two adjacent plans. The disclosure's load-bearing attributes are the operator/role/region/transfer-mechanism/pseudonymisation paragraph, NOT the section ordinal. Appended at §5.14 in both source and mirror — same DPD parity contract as the original plan.
- **C8 — VRL case-sensitive `userId`/`user_id` match (NOT case-insensitive).** Plan §FR2 §2.1 prescribed case-insensitive matching. The TS contract (`apps/web-platform/server/userid-pseudonymize.ts:53-54`) is case-SENSITIVE — checks `"userId" in obj` and `"user_id" in obj` exactly. Per SF-P0-3 contract-match-TS, the VRL transform matches TS exactly (`parsed_obj.userId` / `parsed_obj.user_id`). A future case-insensitive widening should be a deliberate decision with a fixture flip + ADR amendment per the TS file's own "Widening to nested requires a test fixture flip and ADR update" doctrine.
- **C9 — Better Stack source `2457081` region verified at Phase 0.4 as `eu-fsn-3` (Falkenstein DE), fast-path FR3.1 applied.** Plan §0.4 prescribed Playwright dashboard login as the verification path. Phase 0 used a lower-cost authenticated POST probe against both candidate clusters (`eu-fsn-3` → HTTP 202; `eu-nbg-2` → HTTP 401, confirming token cluster-binding). The probe-based verification is recorded in the `[sinks.betterstack]` comment block in `apps/web-platform/infra/vector.toml`. FR3.2 (US source provisioning + 5-step atomic ordering) DID NOT fire.
