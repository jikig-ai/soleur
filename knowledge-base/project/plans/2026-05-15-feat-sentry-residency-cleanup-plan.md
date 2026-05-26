---
date: 2026-05-15
topic: feat-sentry-residency-cleanup
status: plan
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
triggering_issue: "#3861"
related_issues: ["#3849", "#3858", "#3860"]
brainstorm: knowledge-base/project/brainstorms/2026-05-15-sentry-residency-cleanup-brainstorm.md
spec: knowledge-base/project/specs/feat-sentry-residency-3861/spec.md
related_plan: knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md
related_adr: knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md
branch: feat-sentry-residency-3861
worktree: .worktrees/feat-sentry-residency-3861/
pr: "#3863"
---

# Plan — Sentry Residency Cleanup (Phase A1 only)

## Overview

Article 30 register PA8 claims DE residency for Sentry; the AC14 audit artifact at `knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md` contradicts it (`API host: sentry.io` + 8 cron monitors on a US shadow org). Live DSN probe (`o4511123328466944.ingest.de.sentry.io`) confirms user-event ingest is DE. The bug is in IaC tfstate + workflow defaults, NOT in user-event ingest. No personal data left the EEA; Article 33 does not trigger.

**This PR (#3863) lands Phase A1 only — evidence correction + workflow defaults.** It stops wrong-shape §5(2) accountability evidence from regenerating on each release, and adds a fail-closed mismatch detector so any A1↔A2 half-state cannot produce a contradictory artifact.

**Phase A2 (cluster surgery — `terraform state rm`, US shadow-org API delete, token rotation, DE re-apply) is operator-prereq-gated and ships as a separate plan/PR.** Out of scope here. See `## Follow-up — Phase A2` for the pointer.

## Research Reconciliation — Spec vs. Codebase

| Claim (spec) | Reality (codebase) | Plan response |
|---|---|---|
| `compliance-posture.md` heading is "Completed Work" | Actual heading is `## Completed Compliance Work` at L87, table header `\| Item \| Issue/PR \| Completed \| Notes \|` at L89 (4 columns, verified). | Plan appends a 4-column table row, not a bullet. |
| Spec FR3 expects `links.regionUrl` from `/organizations/{org}/` | Script has no such call; provisioning the call requires `sntryu_` token scope. `sntrys_` (the only CI-mintable scope) 403s on the endpoint. DSN cluster substring is authoritative per learning `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md`. | **Plan drops the `links.regionUrl` call entirely.** Emits `**DSN cluster:**` (from `NEXT_PUBLIC_SENTRY_DSN` substring) and renames the existing `**API host:**` line to `**Probed host:**` to mark the asymmetry. Two signals, no failed API call. |
| Spec FR14 adds an SDK residency guard | (a) ≤20-LOC budget is operator-self-judged theatre. (b) Dockerfile pattern modelled on `BUILD_VERSION` lives in the runner stage at L57-68; FR14 placement at builder-stage L15-26 would silently no-op (multi-stage `COPY --from=builder` discards builder ENV). (c) Workflow-default flip + tfstate alignment fix root cause; FR14 is belt-on-suspenders. | **Plan drops FR14.** Sentinel of the bug class is the fail-closed mismatch detector in `sentry-monitors-audit.sh` (Phase 2 below). If a runtime guard is ever wanted, file a separate scope-out issue with the runner-stage Dockerfile placement spelled out. |
| `configure-sentry-alerts.sh:32` is the probe loop | Probe loop is at **L35**, not L32 (L32 is `api_host="${SENTRY_API_HOST:-}"` assignment, verified by Kieran review). | Plan references L35. |
| `article-30-register.md:157` is the §(c)(iv) line | L157 opens a single multi-line Markdown table cell holding §(c) Categories (including all four sub-bullets i–iv). §(d) starts a new row at L160, §(e) at L161. There is no line boundary for §(c)(iv). | Plan specifies in-cell anchor: append the parenthetical immediately AFTER substring `not user-scoped` AND BEFORE the closing `)` of the §(c)(iv) sub-bullet. AC4 binds on that anchor literal. |
| `apply-sentry-infra.yml` would auto-apply 12 resources in A2 | Workflow auto-applies only `-target=sentry_cron_monitor.*` (8 resources, verified at L144-151 + L188). The 4 `sentry_issue_alert.*` are import-only per `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`. | Captured as A2 concern. **A2 is out of scope for this PR**; see `## Follow-up — Phase A2`. |
| Public legal corpus residency claims already correct | `docs/legal/` Eleventy mirror contains `privacy-policy.md`, `data-protection-disclosure.md`, `gdpr-policy.md`. No Article 30 mirror (register is internal). | CLO scope-out holds. AC11 greps the public files post-merge to confirm hit count is unchanged (substring "DE region" / "Functional Software GmbH"); no edits. |

## User-Brand Impact

(Carried verbatim from the brainstorm. Threshold = `single-user incident`; `requires_cpo_signoff: true` set in frontmatter. CPO sign-off recorded via the brainstorm's `## Domain Assessments` Product section.)

- **If this lands broken, the user experiences:** A regulator-facing Article 30 §5(2) accountability artifact at `knowledge-base/legal/audits/sentry-migration-audit-<date>.md` that contradicts PA8's factual DE residency claim. A CNIL inspector reading `API host: sentry.io` would conclude the platform is US-resident, undermining the trust commitment in the Privacy Policy.
- **If this leaks, the user's data is exposed via:** Vector ruled out by the DSN probe — DE-bound ingest is intact. Residual vector is the accountability artifact itself misrepresenting where data lives. Operational vector: next `apply-sentry-infra` run would have continued producing orphan resources on the wrong cluster (A1 alone does not fix; A2 closes).
- **Brand-survival threshold:** **single-user incident**. The register's residency claim is the load-bearing factual representation to data subjects. Its supporting accountability evidence must not contradict it.
- **CPO sign-off:** Recorded in the brainstorm's `## Domain Assessments` → Product (CPO) section. Plan-time re-invocation not required (Phase 2.6 Step 3 staging — CPO signs once at plan; review uses `user-impact-reviewer`).

## Domain Review

**Domains relevant:** Engineering, Product, Legal.

**Carry-forward:** All three assessments imported verbatim from `knowledge-base/project/brainstorms/2026-05-15-sentry-residency-cleanup-brainstorm.md` `## Domain Assessments`. No specialist re-invocation required at plan time.

**Brainstorm-recommended specialists:** None.

**Product/UX Gate:** Tier NONE — infrastructure + IaC + internal legal artifact; no user-facing surface.

**Legal (CLO) — load-bearing:** Article 33 clock does NOT trigger. Counsel review NOT required. Article 30 §5(2) accountability harm requires (1) timestamped correcting note on the misleading audit artifact (this PR), (2) regenerated DE-region artifact post-cleanup (Phase A2 — out of scope), (3) clarifying parenthetical in PA8 §(c)(iv) (this PR). NO public-corpus changes. GDPR-gate fires at PR time per `hr-gdpr-gate-on-regulated-data-surfaces`. Plan-time pass (Phase 6) returned zero Critical findings.

## Open Code-Review Overlap

| Open issue | Files touched | Plan disposition |
|---|---|---|
| #3829 — CI gate `new monitor type → sentry-scrub.ts must change` | `apps/web-platform/sentry.{client,server}.config.ts` | **No longer overlaps.** This plan dropped FR14, so SDK config files are untouched. Issue stays open as filed. |
| #3703 — `client-pii-grep` CI + lefthook gate | `apps/web-platform/sentry.client.config.ts` | **No longer overlaps.** Same reason. Issue stays open. |

No remaining `code-review` issues match the planned file list.

## Files to Edit (Phase A1 — this PR)

1. **`.github/workflows/reusable-release.yml:308`** — flip `'sentry.io'` → `'de.sentry.io'` in the `SENTRY_API_HOST` default.
2. **`.github/workflows/reusable-release.yml:330`** — flip operator-facing warning prose `"defaults to 'sentry.io'"` → `"defaults to 'de.sentry.io'"`. Same commit as L308.
3. **`apps/web-platform/scripts/sentry-monitors-audit.sh:45`** — reverse probe order: `for candidate in de.sentry.io sentry.io`.
4. **`apps/web-platform/scripts/sentry-monitors-audit.sh` (frontmatter block, around L230)** — emit `**DSN cluster:**` line derived from `${NEXT_PUBLIC_SENTRY_DSN:-${SENTRY_DSN:-}}` substring (regex `ingest\.[a-z0-9]{2,}\.sentry\.io`; absent → `us`). Rename the existing `**API host:**` line to `**Probed host:**` to mark the asymmetry. ADD a fail-closed mismatch detector: if the region segment of `**Probed host:**` (`de` from `de.sentry.io`, `us` from bare `sentry.io`) differs from the DSN cluster, emit a stderr line `ERROR: residency mismatch — probed=<host> DSN cluster=<cluster> — refusing to emit audit artifact (refs #3861)` AND `exit 2`. The audit workflow's existing `set +e` + `::warning::` branch (L329-331) handles the non-zero exit gracefully (no `gh release upload`).
5. **`apps/web-platform/scripts/configure-sentry-alerts.sh:35`** — reverse probe order (same fix, sibling file).
6. **`knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md`** — append a `## Correction (2026-05-15)` section AFTER the L47 sentinel `<!-- ids: ["484097"] -->`. Preserve original content above. Section must include a **Replacement evidence:** forward pointer line: `**Replacement evidence:** pending — tracked at #3861. Until Phase A2 lands, the production DSN (\`o4511123328466944.ingest.de.sentry.io\`) and \`apps/web-platform/infra/sentry/*.tf\` are the authoritative DE residency signals.`
7. **`knowledge-base/legal/article-30-register.md:157`** — locate substring `not user-scoped` inside the §(c)(iv) sub-bullet within the L157 table cell; append " — operational metadata, not Art. 4 personal data" immediately after that substring AND before the closing `)`. **Do NOT modify the closing `)` itself, §(d) L160, §(e) L161, or the Vendor DPAs row at L208.**
8. **`knowledge-base/legal/compliance-posture.md`** — append one row to the `## Completed Compliance Work` table (header at L89): `\| Sentry residency cleanup (Phase A1) \| #3861 / PR #3863 \| 2026-05-15 \| Probe confirmed DE-bound ingest; tfstate captured wrong-cluster US shadow. A1 stops wrong-shape §5(2) evidence regen; A2 cluster surgery follows on operator billing prereqs. \|`

## Files to Create

None.

## Implementation Phases

**Two commits, four logical phases.**

### Phase 1 — Defaults + probe order (commit 1)

Edit files **1, 2, 3, 5** in one commit. Same logical change: align workflow + probe defaults with DE residency.

Commit message: `chore(sentry-residency): flip workflow + probe defaults to de.sentry.io (refs #3861)`

### Phase 2 — Audit-script residency evidence + mismatch guard (commit 1, same commit)

Edit file **4**. The DSN cluster line + fail-closed mismatch detector close the A1→A2 half-state safety hole identified by the architecture-strategist and spec-flow-analyzer reviews. Land in the same commit as Phase 1 — the script and workflow are co-dependent (script must handle the workflow's new default cleanly).

DSN-cluster extraction shape:

```bash
dsn_cluster=$(printf '%s' "${NEXT_PUBLIC_SENTRY_DSN:-${SENTRY_DSN:-}}" \
  | grep -oE 'ingest\.[a-z0-9]{2,}\.sentry\.io' \
  | grep -oE '\.[a-z0-9]{2,}\.' \
  | tr -d '.')
[[ -z "$dsn_cluster" ]] && dsn_cluster="us"
```

Mismatch detector (after `api_host` is resolved, before frontmatter emission):

```bash
host_region="${api_host%%.sentry.io}"
host_region="${host_region##*.}"
[[ "$host_region" == "sentry" ]] && host_region="us"   # bare sentry.io
if [[ "$host_region" != "$dsn_cluster" ]]; then
  echo "ERROR: residency mismatch — probed=${api_host} DSN cluster=${dsn_cluster} — refusing to emit audit artifact (refs #3861)" >&2
  exit 2
fi
```

Frontmatter emission gains two lines (replacing the prior single `**API host:**`):

```
- **Probed host:** <api_host>
- **DSN cluster:** <us|de|...>
```

### Phase 3 — Docs + register edits (commit 2)

Edit files **6, 7, 8** in one commit. All Markdown-only; the register parenthetical, the audit correction note (with forward pointer), and the compliance-posture row.

Commit message: `docs(legal): Article 30 PA8 §(c)(iv) clarifier + audit correction + compliance posture row (refs #3861)`

### Phase 4 — Verify + ship

- Re-read each edited file; confirm post-state matches the AC list.
- Run `bash apps/web-platform/scripts/sentry-monitors-audit.sh` once locally with a known-invalid token AND with a known-mismatched `NEXT_PUBLIC_SENTRY_DSN`+`SENTRY_API_HOST` pair; confirm fail-closed exit 2 fires (or existing L55 fail-closed exit if token rejected first).
- Run `/soleur:gdpr-gate` against the PR diff per `hr-gdpr-gate-on-regulated-data-surfaces`. Plan-time pass returned zero Critical findings (recorded below); PR-time delta MUST be zero new Criticals.
- `/soleur:ship` — push, preflight Check 6 (User-Brand Impact section gate), mark PR ready, await CI green.
- PR body MUST contain: `Refs #3861` (NOT `Closes #3861`); plan-time gdpr-gate output verbatim; one-line callout naming the Article 30 register edit; recovery framing (Sentry US is DPF-certified).

**Plan-time gdpr-gate pass (2026-05-15):** zero Critical findings. All 5 mandatory checks (Art. 6 / 5(1)(e) / 17 / Chapter V / 9) not triggered. No actionable Suggestions for this PR.

## Follow-up — Phase A2 (separate plan + PR)

Phase A2 carries the actual cluster surgery (tfstate alignment + US shadow-org teardown + token rotation + DE re-apply + new §5(2) artifact). It is operator-prereq-gated and ships separately. A separate plan will be drafted when the operator completes:

- **A2.P1 (operator):** add payment method to `jikigai` org on `de.sentry.io`; enable PAYG with ≥ 8 cron seats.
- **A2.P2 (operator):** mint a DE-scoped `SENTRY_AUTH_TOKEN` (internal-integration from `de.sentry.io`) and stage for both Doppler `prd` and GitHub repo secret rotation.

That plan will cover (do NOT execute here): `terraform state rm` × 12 with pre-staged recovery commands; ACK-gated US-org direct-API delete; coordinated GH-secret + Doppler rotation with apply-sentry-infra workflow lock-out during the window; operator-driven local `terraform apply -target=sentry_issue_alert.*` for the 4 import-only alerts; post-apply `curl ... rules/ | jq 'length == 4'` assertion; regeneration of `audits/sentry-migration-audit-<post-fix-date>.md` AND update of PA8 §5(2)'s last-line pointer to the new artifact; closure of #3861.

The A2 plan picks up the architecture-strategist and spec-flow-analyzer findings: token-rotation half-state guard, apply-trigger UX (literal `gh workflow run` form), forget-recovery curl assertion, operator-mint URL+scope+paste+verify enumeration, and the §5(2) dark-window time-bound SLA (CLO-acked target ≤ 30 days post-A1 merge).

## Sharp Edges

- **`Refs #3861`, NOT `Closes #3861`** in PR body. A1 is partial remediation; #3861 stays open until A2 lands.
- **The mismatch detector (Phase 2) is the load-bearing protection for the A1→A2 window.** If somehow the audit script's fail-closed path is bypassed (e.g., manual operator run without `SENTRY_API_HOST` set), the new `**DSN cluster:**` line is the second signal an auditor can read; the `**Probed host:**` line is the first. Two signals beat one.
- **`article-30-register.md:157` is a multi-line table cell, not a line boundary.** Edit by in-cell substring anchor (after `not user-scoped`, before the closing `)`), NOT by line position. AC4 binds on that anchor literal.
- **`reusable-release.yml:330` warning prose must flip with L308.** Leaving the warning text saying `'sentry.io'` while the default is `'de.sentry.io'` is a doc-regression visible only in CI warnings.
- **DSN regex alphabet** is `[a-z0-9]{2,}` to allow future regions like `ap2` (not present today; cheap forward-compat).
- **AC1's grep `'sentry.io'` (single-quoted)** does NOT match `'de.sentry.io'` because the leading single-quote anchors before `s`. Don't loosen the quotes in a future cleanup PR or AC1 silently inverts.
- **The audit artifact at `sentry-migration-audit-2026-05-15.md:43` contains `Vendor DPA: https://sentry.io/legal/dpa/`** — a legitimate URL, not an API host. Future verification greps on this file must scope-out the DPA URL.

## Acceptance Criteria

### Pre-merge (PR #3863)

- **AC1:** `grep -nE "(de\\.sentry\\.io|'sentry\\.io')" .github/workflows/reusable-release.yml | grep -nE "(308|330)"` shows `de.sentry.io` at BOTH L308 and L330. `grep -n "'sentry.io'" .github/workflows/reusable-release.yml | awk -F: '$2 >= 300 && $2 <= 340'` returns no matches.
- **AC2:** `grep -n "for candidate in de.sentry.io sentry.io" apps/web-platform/scripts/sentry-monitors-audit.sh apps/web-platform/scripts/configure-sentry-alerts.sh` returns exactly 2 matches (sentry-monitors-audit.sh:45 + configure-sentry-alerts.sh:35).
- **AC3:** `sentry-monitors-audit.sh` frontmatter emission now contains `**Probed host:**`, `**DSN cluster:**`, AND a fail-closed `exit 2` branch on region mismatch. Local invocation with intentionally-misaligned DSN/host produces stderr `ERROR: residency mismatch — ...` and exits 2.
- **AC4:** `knowledge-base/legal/article-30-register.md` §(c)(iv) sub-bullet contains substring `not user-scoped — operational metadata, not Art. 4 personal data)`. `git diff HEAD~2 -- knowledge-base/legal/article-30-register.md` touches ONLY L157 cell (§(d) L160, §(e) L161, Vendor DPAs L208 byte-identical).
- **AC5:** `knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md` L1-47 are byte-identical to pre-edit; a new `## Correction (2026-05-15)` section follows AND includes the `**Replacement evidence:** pending` forward pointer.
- **AC6:** `knowledge-base/legal/compliance-posture.md` `## Completed Compliance Work` table grows by exactly one row; row references `#3861 / PR #3863` and date `2026-05-15`.
- **AC7:** `/soleur:gdpr-gate` PR-time run produces zero NEW Critical findings vs the plan-time pass recorded under Phase 4. Output captured in PR body.
- **AC8:** PR body contains `Refs #3861` (NOT `Closes #3861`). `gh issue view 3861 --json state` returns `open` after merge.
- **AC9:** Public-corpus drift check — `grep -cE "(DE region|Functional Software GmbH)" docs/legal/privacy-policy.md docs/legal/data-protection-disclosure.md docs/legal/gdpr-policy.md` returns identical counts pre- and post-merge.

### Post-merge (operator follow-up — Phase A2, separate plan/PR)

Tracked in the Phase A2 plan when drafted.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Mismatch detector mis-parses a DSN form not yet seen (e.g., `ingest.us.sentry.io` instead of bare `sentry.io`) | Low | Regex `[a-z0-9]{2,}` covers both `de` and `us` segments. Fail-closed default `us` for bare `ingest.sentry.io` keeps the detector strict — if DSN says `de` and host probes `sentry.io`, mismatch fires correctly. |
| Article 30 register parenthetical edit drifts the §(c)(iv) sub-bullet by accident | Medium | AC4 binds on the literal anchor `not user-scoped — operational metadata, not Art. 4 personal data)` — implementer cannot pass AC4 without the exact in-cell placement. |
| A1↔A2 latency stretches and §5(2) evidence accrues no replacement | Medium | A1 stops wrong-shape regen on its own (mismatch detector fails closed; workflow's existing `::warning::` branch handles non-zero exit). Forward pointer in `## Correction` directs auditor to live signals. CLO-acked SLA target ≤ 30 days post-A1 merge — tracked in the A2 plan. |
| GDPR-gate output non-deterministic across runs (LLM-based skill) | Medium | AC7 binds on **Critical-count delta** (zero new), not verbatim output text. |
| Multi-stage Dockerfile / Doppler injection question never resolved | Low | FR14 dropped; no Dockerfile edits this PR. Question routes to the A2 plan or to a separate follow-up issue. |

## Open Questions

None blocking A1. All A2 open questions move to the A2 plan.

## Resume prompt (copy-paste after `/clear`)

```text
/soleur:work knowledge-base/project/plans/2026-05-15-feat-sentry-residency-cleanup-plan.md.
Branch: feat-sentry-residency-3861. Worktree: .worktrees/feat-sentry-residency-3861/.
Issue: #3861. PR: #3863. Brainstorm + spec + plan-review (5-agent panel) complete.
Phase A1 only (evidence correction + workflow defaults + mismatch detector).
Phase A2 (cluster surgery) is a separate plan/PR gated on operator prereqs.
Use `Refs #3861`, NOT `Closes #3861`, in PR body.
```
