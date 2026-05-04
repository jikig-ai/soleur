# Brainstorm: CLA Signature Recording — Legal Rigor

**Date:** 2026-05-04
**Status:** Complete
**Participants:** CLO, CTO, CPO, COO (parallel domain assessment), repo-research-analyst (prior-artifact review)
**Trigger:** PR #3196 verification surfaced gaps in CLA evidence quality. User asked: "do we record CLA signatures somewhere — for legal reasons, we need to record them."
**Tracking issue:** #3209 (main); #3210 (deferred: PII + CCLA mechanism); #3211 (deferred: contributor lookup page).
**Branch:** `feat-cla-legal-rigor` · **Draft PR:** #3201
**Predecessor:** `knowledge-base/project/brainstorms/2026-02-26-cla-contributor-agreements-brainstorm.md` (decided to use contributor-assistant action with same-repo storage); `knowledge-base/project/learnings/2026-02-26-cla-system-implementation-and-gdpr-compliance.md` (implementation gotchas).

## User-Brand Impact

- **Artifact at risk:** CLA signature evidence chain on `cla-signatures` branch + future R2 evidence archive.
- **Vector:** Three concurrent threats accepted by user — (1) IP-dispute / cannot relicense BSL → Apache 2.0 if signature provenance is unverifiable, (2) PII leak if identity capture is mishandled, (3) contributor abandonment if signing flow becomes too heavy.
- **Brand-survival threshold:** `single-user incident` for PII axis (one breach is brand-ending for an OSS company); `aggregate pattern` for IP axis (one missing record may not kill us, a dozen do); `aggregate pattern` for friction axis. Plan-side enforcement: Brand-survival threshold inherits from this brainstorm; user-impact-reviewer required at review.

## What We're Building

A sidecar evidence layer that records tamper-evident CLA signature artifacts alongside the existing `contributor-assistant/github-action` flow. Concrete deliverables:

1. **Sidecar workflow** that triggers on the same `issue_comment.created` and `pull_request_target` events as the existing `cla.yml`, computes the doc-hash, fetches the verbatim comment body, and writes a structured evidence record to R2.
2. **R2 bucket** `soleur-cla-evidence` provisioned via new Terraform root `infra/cla-evidence/`, region `weur`, object-lock Governance mode, 10-year retention.
3. **Evidence schema** (sidecar-owned JSON) capturing: GitHub identity, PR-of-record (the actual PR where the comment was posted, fixing gap #5), doc path + git-SHA + content-SHA256, verbatim comment body + body-SHA256, signed-at, capture-method (`live` | `backfilled`), workflow-run-id, allowlist-bypass flag.
4. **Bot receipt comment** appended to the existing CLA Assistant ack: surfaces the doc-hash and a link to the evidence record so contributors can verify what they signed.
5. **Backfill** of the 2 existing signers (deruelle, Elvalio) by synthesizing evidence records from git history of `docs/legal/individual-cla.md` at each sign-time. Tagged `capture_method: backfilled` to preserve evidentiary tier honesty.
6. **Allowlist-bypass logging** — the action allowlists `dependabot[bot]`, `github-actions[bot]`, `renovate[bot]`. Each bypass should produce an evidence record with `allowlist_bypass: true` so relicensing audits have a complete provenance answer.
7. **CLA preamble update** in `docs/legal/individual-cla.md` clarifying that the agreement is a copyright license grant (not consent), so a confused GDPR-Art-7 withdrawal claim cannot collapse the license.
8. **RFC 3161 monthly timestamping** — scheduled job that submits the R2 evidence-bucket manifest to a free Time Stamping Authority (e.g., FreeTSA) and stores the response as additional evidence. Cheap, dramatically improves evidentiary weight per CLO.
9. **Inspection runbook** at `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` — IP-dispute / DMCA / contributor-revocation response procedure.

## Why This Approach

### Sidecar over fork

Forking `contributor-assistant/github-action` traps us into upstream-rebase security review forever. Sidecar adds one workflow file we own, leaves the action's `cla.json` as the canonical signed list, and gives full schema control on the evidence record. Drift risk is mitigated by hard-failing the merge if the evidence layer fails — partial protection is worse than loud failure for legal evidence.

### Per-event upload, not cron mirror

Cron creates a tampering window between sign-time and mirror-time. Per-event puts the evidence on the audit trail at sign-time. A weekly cron diff between `cla-signatures` branch and R2 runs as a *secondary* drift detector, alerting to Sentry on mismatch — not as the primary archive mechanism.

### Document hashing source: in-repo, at PR base SHA

The `soleur.ai/pages/legal/individual-cla.html` URL is a derivative; `docs/legal/individual-cla.md` is the legal source. Hashing the in-repo file at the PR's base-branch tip SHA when the comment was posted is reproducible, version-pinned, and verifiable by anyone with `git show <sha>:docs/legal/individual-cla.md | sha256sum`. Surfaced in the bot receipt comment for contributor-side verification.

### Governance object-lock + 10-year retention

Compliance mode (root-immutable) was CTO's recommendation for max tamper-evidence, but COO flagged that it leaves no escape hatch if a French DPA orders erasure under GDPR Art. 17. Governance preserves admin-override (mitigated by 2FA-enforced admin role + Cloudflare account-level deletion protection). 10 years covers BSL 4-year change date, German statutory 10yr floor, and UK 6yr + buffer; FR art. 2227 Code civil 30yr remains an option for later extension since admin can lengthen but not shorten existing locks.

### Friction budget: ICLA flow stays one-comment

Per CPO, the four zero-friction fixes ship now because they add *zero* contributor-visible cost. Gap #3 (real-name/email PII expansion) and the wired-up CCLA mechanism are split off into a follow-up brainstorm because they are product-strategy decisions about contributor identity capture, not implementation cleanup. Joint CPO+CLO sync is a precondition for that follow-up brainstorm.

### Backfill, not re-sign

Re-signing imposes friction on the two onboarded contributors (deruelle internal, Elvalio external as of 2026-05-04) for evidence we can synthesize from git history. The `capture_method: backfilled` flag preserves the evidentiary distinction without papering over it.

## Key Decisions

| # | Decision | Rationale | Source |
|---|---|---|---|
| 1 | **Scope:** four zero-friction fixes + 3 hidden gaps (revocation clause, allowlist-bypass logging, RFC 3161). PII expansion + CCLA mechanism deferred to a follow-up brainstorm. | Friction budget; legal bar for ICLA is met by zero-friction set. | User Q1 |
| 2 | **Architecture:** sidecar workflow, not action fork. | Avoid upstream-rebase maintenance trap. | CTO |
| 3 | **Archival pattern:** per-event R2 upload at sign-time; weekly cron diff is secondary drift detector. | Per-event has no tampering window. | CTO |
| 4 | **Document hash source:** in-repo `docs/legal/individual-cla.md` at PR base-branch SHA, computed in sidecar at `issue_comment.created` time. | Reproducible, version-pinned, contributor-verifiable. | CTO + CLO |
| 5 | **Object-lock mode:** Governance + admin-override. | Preserve GDPR Art. 17 escape hatch. | User Q2 (COO recommendation) |
| 6 | **Retention duration:** 10 years (extendable to 30yr later). | Covers BSL 4yr change date + DE statutory + UK contract floors. | User Q3 |
| 7 | **R2 region:** `weur` (Western Europe). | EU jurisdiction; even though current scope holds only public-GitHub data, region-pinning the bucket prepares for the follow-up brainstorm's PII work without forcing a migration. | COO |
| 8 | **Doppler config:** `prd_cla` (new) for workflow R2 write keys; `prd_terraform` for state apply. Keys named `R2_CLA_EVIDENCE_ACCESS_KEY_ID` / `R2_CLA_EVIDENCE_SECRET_ACCESS_KEY` (matches existing R2 backend convention). | Scope-isolation; rotate independently of TF state creds. | COO |
| 9 | **Failure mode:** hard-fail the sidecar; block PR merge until evidence layer succeeds. Single check (folded with `cla-check`). | Partial protection is worse than loud failure for evidence; multiple checks confuse first-time contributors per CPO. | CTO + CPO |
| 10 | **Observability:** `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry` on every catch path. R2 outage produces blocking failure with Sentry alert. | Existing pattern; do not reinvent. | CTO |
| 11 | **Backfill strategy:** synthesize evidence records for the 2 existing signers from git history. Do not re-sign. Tag `capture_method: backfilled`. | Asymmetry — re-sign is high-effort for low marginal evidence quality. | CPO + CTO |
| 12 | **Receipt comment:** bot reply surfaces doc-hash + git-SHA + verification one-liner (`git show <sha>:docs/legal/individual-cla.md \| sha256sum`). No `soleur.ai/account/cla` page (deferred). | 80% of trust signal at <5% of cost. | CPO + CTO |
| 13 | **Bucket lifecycle protection:** `lifecycle { prevent_destroy = true }` on `cloudflare_r2_bucket` Terraform resource. Account-level deletion protection enabled. | Object-lock prevents object delete but not necessarily empty-bucket delete. | COO |
| 14 | **TF state isolation:** new TF root uses scoped R2 token *separate* from object-write token to limit state-compromise replay. | Defense-in-depth; cost is one extra Doppler entry. | COO |

## Open Questions

1. **CCLA flow + PII expansion (deferred to follow-up brainstorm).** When to schedule the joint CPO+CLO sync? Trigger should be next CCLA-needing contributor (someone discloses corporate affiliation) or 30 days, whichever first.
2. **RFC 3161 TSA selection.** FreeTSA (free, community-run) vs. paid commercial TSA (DigiCert, GlobalSign). Picked at plan-phase based on availability/SLA assessment.
3. **Allowlist-bypass logging semantics.** `claude[bot]` and `dependabot[bot]` PRs may be high-volume. Should every bypass create a record, or only a single canonical "this principal is allowlisted because..." entry rotated yearly? Plan-phase decision.
4. **Cloudflare R2 IP-allowlist for the workflow token.** GitHub Actions egress IP ranges are documented; whether to enforce IP-allowlist on the R2 token is a plan-phase tradeoff (operational rigidity vs. defense-in-depth).
5. **Right-to-erasure handling under Governance mode.** Process is "admin override + record the override + document in DPA" but the runbook for that scenario doesn't exist yet. Defer to ops runbook creation.

## Domain Assessments

**Assessed:** Engineering (CTO), Legal (CLO), Product (CPO), Operations (COO). Not assessed: Marketing, Sales, Finance, Support — none of these domains have a relevant signal in the feature description.

### Legal (CLO)

**Summary:** Doc hash (gap #1) is must-fix for relicensing in EU jurisdiction; verbatim comment text (gap #4) is must-fix for non-repudiation; off-site archive (gap #2) is must-fix-lite; PII (gap #3) is ICLA-optional / CCLA-blocking — recommend deferring CCLA work to a follow-up; pullRequestNo (gap #5) is theater-adjacent. Surfaced 4 hidden gaps not in original list: CCLA mechanism wiring (#2 priority), revocation/withdrawal-clause clarification, unlogged allowlist bypasses, RFC 3161 timestamping. GDPR balance: the strong-evidence fixes *activate* the Art. 17(3)(e) legal-claims carveout — they reduce GDPR liability rather than add to it. PII expansion adds GDPR liability; defer.

### Engineering (CTO)

**Summary:** Sidecar architecture (not fork) is the correct blast-radius choice. Per-event R2 upload with content-addressed keys (`signatures/<sha256-of-payload>.json`) plus a `signatures/by-pr/<pr>/<comment_id>.json` pointer for navigation. Hash source is `docs/legal/individual-cla.md` at PR base SHA. Evidence schema captures comment body + body-SHA256, GitHub identity, PR-of-record, doc git-SHA, doc content-SHA256, capture method, workflow run ID, edit log. Hard-fail on evidence-layer failure; observability mirrors `reportSilentFallback`. Recommended R2 Compliance mode for max tamper-evidence (overruled by user choice in favor of Governance per COO's GDPR escape-hatch framing). Backfill is clean from git history. Migration risk: if the sidecar workflow fails silently, partial protection — block merge to avoid this.

### Product (CPO)

**Summary:** Four of five user-listed gaps are zero-friction (server-side); ship them now. Gap #3 (PII) is the only one with material UX cost — defer. CCLA mechanism is itself a multi-day product investment with strategy questions (PR-time vs separate web flow); defer to dedicated brainstorm. Backfill, not re-sign — asymmetric effort vs. evidence value. Single folded `cla-check` rather than separate `cla-evidence-check` (multiple checks confuse first-time contributors). Bot receipt comment with doc-hash buys ~80% of trust signal at <5% of contributor-account-page cost. Joint CPO+CLO sync needed before the deferred PII brainstorm — disagreement is on Gap #3 scope.

### Operations (COO)

**Summary:** R2 cost negligible at any plausible scale (sub-cent/month). Recommend Governance mode (not Compliance) to preserve GDPR Art. 17 escape hatch. New Terraform root `infra/cla-evidence/` with R2 backend mirroring `apps/web-platform/infra/main.tf`. EU region (`weur`) on the bucket. Doppler config `prd_cla` (write keys) + `prd_terraform` (state). `lifecycle { prevent_destroy = true }` on the bucket. Inspection runbook required *regardless of technical archival* — current state has no documented IP-dispute response procedure. Operational risks added to the list: bucket-deletion bypassing object-lock semantics, TF-state compromise enabling key-rotation replay, workflow-token leak forging signatures (mitigated by IP-allowlist), TF apply destroying bucket on resource rename. Expense ledger entry template provided.

## Capability Gaps

None. Existing skills and agents cover the full scope:
- Engineering: existing TF + R2 backend pattern (`apps/web-platform/infra/`), existing observability helper (`reportSilentFallback`).
- Operations: `rclone` skill, expense ledger, runbook directory pattern.
- Legal: `legal-compliance-auditor` for the CLA preamble update + DPA/GDPR Policy review.
- Product: standard brainstorm/plan flow.

## Sharp Edges

- **CCLA records must NOT live in `cla-signatures` branch when that scope is added.** That branch is world-readable. CCLA holds employer + signer PII; needs a private store. Out of current scope but flag in the follow-up brainstorm.
- **`pull_request_target` security envelope.** Sidecar reads `comment_id`, computes hash from `base.sha` (trusted), uploads with Doppler creds. Never check out PR head. Same constraint as existing `cla.yml`.
- **Pin `contributor-assistant/github-action` SHA, not tag.** Already done; preserve when bumping.
- **Renovate/Dependabot: do NOT auto-merge action SHA bumps.** Review manually — supply-chain attack surface.
- **Privacy Policy / DPA / GDPR Policy update trigger.** Adding R2 as a sub-processor for CLA archive (sub-processor list in DPA) — verify that R2/Cloudflare is already listed; if not, this fix triggers a DPA update.
- **Right-to-erasure under Governance mode.** When admin override is needed, the override itself must be logged and the DPA must document the override path. This is process work that lives in the inspection runbook, not the workflow.
