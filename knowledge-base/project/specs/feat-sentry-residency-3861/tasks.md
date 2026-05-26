---
feature: sentry-residency-3861
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan: knowledge-base/project/plans/2026-05-15-feat-sentry-residency-cleanup-plan.md
spec: knowledge-base/project/specs/feat-sentry-residency-3861/spec.md
---

# Tasks — Sentry Residency Cleanup (Phase A1)

Phase A1 only. Phase A2 (cluster surgery) is operator-prereq-gated and tracked in a separate plan.

## 1. Setup

- 1.1 Confirm worktree branch: `git -C .worktrees/feat-sentry-residency-3861 branch --show-current` returns `feat-sentry-residency-3861`.
- 1.2 Confirm canonical DSN unchanged: `doppler secrets get NEXT_PUBLIC_SENTRY_DSN -p soleur -c prd --plain` contains substring `ingest.de.sentry.io`. If not, HALT — the residency picture has shifted.
- 1.3 Verify `gh issue view 3861 --json state,labels` returns `open` with labels `type/security` and `compliance/critical`.

## 2. Core Implementation — Commit 1 (workflow + scripts)

- 2.1 Edit `.github/workflows/reusable-release.yml:308` — flip `'sentry.io'` → `'de.sentry.io'` in the `SENTRY_API_HOST` default.
- 2.2 Edit `.github/workflows/reusable-release.yml:330` — flip operator-facing warning prose `"defaults to 'sentry.io'"` → `"defaults to 'de.sentry.io'"`.
- 2.3 Edit `apps/web-platform/scripts/sentry-monitors-audit.sh:45` — reverse probe order to `for candidate in de.sentry.io sentry.io;`.
- 2.4 Edit `apps/web-platform/scripts/configure-sentry-alerts.sh:35` — reverse probe order (sibling fix). Verify L35 actually carries the probe loop before editing.
- 2.5 Edit `apps/web-platform/scripts/sentry-monitors-audit.sh` frontmatter block (around L230):
   - 2.5.1 Add DSN cluster extraction (regex `ingest\.[a-z0-9]{2,}\.sentry\.io`, default `us` if absent — see plan Phase 2 snippet).
   - 2.5.2 Add fail-closed mismatch detector: derive `host_region` from `api_host` (treat bare `sentry.io` as `us`); if `host_region` != `dsn_cluster`, stderr `ERROR: residency mismatch — probed=<host> DSN cluster=<cluster> — refusing to emit audit artifact (refs #3861)` AND `exit 2`.
   - 2.5.3 Rename existing `**API host:**` frontmatter line to `**Probed host:**`.
   - 2.5.4 Add new `**DSN cluster:**` frontmatter line below.
- 2.6 Smoke test the script with intentionally-misaligned DSN/host pair locally. Confirm `exit 2` fires and stderr message matches AC3 literal.
- 2.7 Smoke test with a known-invalid token. Confirm existing fail-closed exit at L55 still fires (no regression).
- 2.8 Commit: `chore(sentry-residency): flip workflow + probe defaults + add audit residency guard (refs #3861)`.

## 3. Core Implementation — Commit 2 (docs)

- 3.1 Edit `knowledge-base/legal/article-30-register.md:157` (§(c)(iv) sub-bullet inside the L157 table cell):
   - 3.1.1 Locate substring `not user-scoped` inside §(c)(iv).
   - 3.1.2 Append ` — operational metadata, not Art. 4 personal data` AFTER that substring AND BEFORE the closing `)`.
   - 3.1.3 Verify §(d) L160, §(e) L161, and Vendor DPAs row L208 are byte-identical post-edit.
- 3.2 Edit `knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md`:
   - 3.2.1 Append a `## Correction (2026-05-15)` section AFTER the L47 sentinel `<!-- ids: ["484097"] -->`. Preserve L1-47.
   - 3.2.2 Body must include the `**Replacement evidence:** pending — tracked at #3861. Until Phase A2 lands, the production DSN ...` forward-pointer paragraph from plan Files-to-Edit item 6.
- 3.3 Edit `knowledge-base/legal/compliance-posture.md`:
   - 3.3.1 Append one 4-column row to the `## Completed Compliance Work` table (header at L89). Row content per plan Files-to-Edit item 8.
   - 3.3.2 Confirm column alignment with sibling rows.
- 3.4 Commit: `docs(legal): Article 30 PA8 §(c)(iv) clarifier + audit correction + compliance posture row (refs #3861)`.

## 4. Verification (pre-PR-ready)

- 4.1 Re-read every edited file; assert each AC from plan `## Acceptance Criteria → Pre-merge` is satisfied.
   - 4.1.1 AC1 — `grep` post-state of `reusable-release.yml` L300-340.
   - 4.1.2 AC2 — `grep` post-state of both probe scripts.
   - 4.1.3 AC3 — local smoke test outputs (carried from 2.6).
   - 4.1.4 AC4 — `git diff` shows only L157 cell change in `article-30-register.md`.
   - 4.1.5 AC5 — `git diff` shows L1-47 unchanged + new `## Correction` section in audit file.
   - 4.1.6 AC6 — `compliance-posture.md` table row appended.
   - 4.1.7 AC9 — public corpus drift `grep -cE "(DE region|Functional Software GmbH)"` returns identical counts.
- 4.2 Run `/soleur:gdpr-gate` against the PR diff. Capture output. Compare to plan-time pass (zero Critical findings).
- 4.3 `git diff --stat` — confirm only the 7 files listed under plan Files-to-Edit changed.

## 5. Ship

- 5.1 Run `/soleur:ship` — pushes, preflight Check 6 (User-Brand Impact section gate), marks PR ready, awaits CI.
- 5.2 PR body content checklist:
   - 5.2.1 `Refs #3861` (NOT `Closes #3861`).
   - 5.2.2 Plan-time and PR-time gdpr-gate outputs (verbatim or as Critical-count delta per AC7).
   - 5.2.3 One-line callout: "Article 30 register PA8 §(c)(iv) parenthetical edit only — §(d), §(e), Vendor DPAs row unchanged."
   - 5.2.4 Recovery framing: "Sentry US (Functional Software, Inc.) remains DPF-certified; covers any residue scenario pending Phase A2."
   - 5.2.5 Pointer to Phase A2 follow-up tracking under #3861.
- 5.3 After CI green + reviewer approval: `gh pr merge --squash --auto`.
- 5.4 Post-merge: verify `gh issue view 3861 --json state` returns `open` (NOT `closed`).
- 5.5 Run `/soleur:compound` to capture learnings from the cleanup.
