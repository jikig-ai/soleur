---
title: "Spec: Art. 32 TOM residual entry + Art. 33(5) assessment of the #9723 window"
issue: 9851
branch: feat-one-shot-9851-art32-tom-art33-5-assessment
lane: single-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-11-03-docs-art32-tom-residual-and-art33-5-assessment-9851-plan.md
---

# Spec: Art. 32 TOM residual entry + Art. 33(5) assessment of the #9723 window

Ref #9851, Ref #9601. Draft v1 internal CLO attestation applies to the wording; it is not external counsel advice.

## Problem Statement

The Art. 30 register's Art. 32 list names the ADR-272 credential deny and the arm-F filesystem wrap but carries no entry for the shared-heap, shared-procfs and shared-network residuals of hosted agent sessions, and its arm-F bullet contains sentences the latest ADR state falsifies. The breach register has no Art. 33(5) record for the window in which the `/proc` deny in the sandbox configuration was declared but not realized (#9723).

## Functional Requirements

- **FR1.** One Art. 32 bullet, status `open residual`, in named-gap order (in force and how far measured; not measured; not covered; reliability limit; exit event; no-public-claim sentence with as-of date; ledger rows by ID; one clause pointing at the breach-register row).
- **FR2.** One additive dated Superseded marker under the arm-F bullet covering six statements, no existing character edited.
- **FR3.** One breach-register row (nine cells, no pipe) recording REACHABILITY-ONLY, PROVISIONAL, evidentiary limbs inconclusive, Art. 33 No, Art. 34 No, for the inner Bash sandbox tier only; canonical source is the ADR-075 record.
- **FR4.** CLO review recorded in decision-challenges.md on the final diff.

## Technical Requirements

- **TR1.** Diff limited to the two registers plus this feature's plan and spec files (plan AC1).
- **TR2.** `scripts/lint-legal-registers.sh`, markdownlint and the related register tests green (plan AC3, AC4, AC11).
- **TR3.** No withheld number, no identifier, credential name, host name, argv token or version string beyond what existing ADRs already carry (plan AC2, AC9).
- **TR4.** No public surface, code, flag, environment or issue is touched or filed.

## Claim-to-source table (work phase fills the resolved anchor column)

| Claim the diff adds | Source anchor (heading or section, never a line number) |
|---|---|
| Inner-tier `/proc` is an empty tmpfs with the container procfs beneath it | ADR-075 addendum "2026-10-11 (#10032)" and nested "2026-10-12 (#10065)" |
| It rests on an unelevated bubblewrap, `--cap-drop ALL` in the vendored tail, unchanged run-tuple posture | ADR-075 nested addendum "2026-10-12 (#10065)" conditions (1) to (3) |
| Faithful canary verdict pass read after the fix | post-mortem `agent-sandbox-proc-mount-eperm-postmortem.md` "Recovery verification" |
| The deploy canary is report-only; denial surfaces as a tool result | same post-mortem, "What went wrong" and "Detection"; runbook `canary-probe-set.md` |
| No ledger row measures the mask as a claim | ledger rows I1, I2, I5, I10 (by ID) |
| File-tool tier shares the container procfs; heap, loopback and sibling-proxy cross-use, HOME state, server-process filesystem access | ADR-075 addendum "2026-10-08 (#5863)" Open residuals; breach-register 2026-10-31 row (HOME, by pointer) |
| AF_UNIX denial is flag-gated and dark | ADR-075 addenda 2026-10-16 and 2026-10-19; ledger I4 |
| Exit is the per-tenant executor only; revisit trigger | ADR-075 addendum "2026-10-09 (#9873 disposition)"; `gh issue view 9773`, `gh issue view 9842` |
| #9723 closed; file-capability arm reverted | `gh issue view 9723 --json state,closedAt`; ADR-075 addendum 2026-10-09 (#9874) |
| Window start/end/evidence dates | `gh pr view 1559`, `gh pr view 5928`, `gh pr view 9768`, `gh pr view 10039`; post-mortem timeline; `git log -S` commands in the plan |
| Awareness anchor | `gh issue view 9723 --json createdAt` |
| Cohort classification open | 2026-10-28 determination (`knowledge-base/legal/audits/2026-10-28-clo-determination-11303-gated-tier-allowedtools-bypass.md`), unverified item U-1 |

## Resolved anchors (work phase, read 2026-11-03)

| Claim | Resolved against |
|---|---|
| Issue #9723 created 2026-10-07T19:14:00Z, closed 2026-10-09T01:58:31Z by PR 9768 (merged 2026-10-09T01:58:29Z) | `gh issue view 9723`, `gh pr view 9768` |
| Deny entry declared from 2026-03-29 | PR 1282 merged 2026-03-29T18:19:42Z, "add /proc to denyRead"; `git log -S'"/proc"'` earliest hit b9bfda0665 |
| Sandbox enabled in production | PR 1559 merged 2026-04-05T22:01:06Z (the commit date 2026-04-06 is local time) |
| Defective command shape repo-evidenced | PR 5928 merged 2026-07-03T09:39:47Z (in-image fixture capture) |
| Window end about 2026-10-09T04:52Z | post-mortem timeline, row "Image carrying the splice begins to ship (approx.)"; ADR-075 addendum 2026-10-11 (#10032) |
| Realization changed afterwards | ADR-075 addenda 2026-10-11 (#10032, PR 10039 merged 2026-10-11T18:29:11Z) and nested 2026-10-12 (#10065); ADR-272 Note 2026-10-08 |
| File-capability arm reverted | PR 9874 merged 2026-10-09T17:13:40Z; ADR-075 addendum 2026-10-09 (#9873 disposition) |
| `proc_mask` is part of the canary verdict | `sandbox-canary.mjs`: the first entry of `HARDENING_PROBES`, defeat classed `sandbox_broken` |
| Canary pass read | post-mortem "Recovery verification": `verdict=pass reason=ok` 2026-10-12 00:51:13Z and 01:01:35Z |
| File-tool barrier is the PreToolUse realpath-containment hook | ADR-075 addendum 2026-10-31 (#10455, PR 1a) and Context; ledger row I3 |
| Account classification unverified | 2026-10-28 determination, instrument U-1; dated decisions due 2026-11-04 |
| 2026-10-09 ruling names the assessment as owed | that ruling, "The #9723 /proc-window Art. 33(5) assessment is owed regardless (epic #9842 Stage 0)" |
| Public documents and mirrors, keyword search (procfs, /proc, sandbox, tenant isolation) | one line in each of the privacy policy, disclaimer, GDPR policy and data protection disclosure, mirrors identical; each concerns agent web access, its audit records or the reader's own safeguards |

## Wording lists (CLO)

May say: reachability on the vendored argv shape; the sandbox mask as intended and canary-observed after deploy; conflicts between measurements, by pointer; no instrument logs a sibling environ read; a zero from any later census reads "not found in retained records", never "none".

Must not say: no exposure; no personal data; not a breach; tenant isolation (outside the existing quoted ceiling); secure; fixed; resolved; closed; anything past-tense about this pull request; any kernel-level control for the file-tool tier.

## Out of scope

Edits to `compliance-posture.md`, the ledger, any `audits/` file, ADRs, C4, docs, code, scripts, workflows; running the retained-records census; reading the live `AGENT_OUTER_WRAP` value; filing issues.
