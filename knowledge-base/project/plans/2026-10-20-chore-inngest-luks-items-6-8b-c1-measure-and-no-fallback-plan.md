---
title: "chore(infra): Inngest LUKS arc items 6, 8b and C1: three read-only measurements and a no-fallback Hetzner loader"
date: 2026-10-20
slug: inngest-luks-items-6-8b-c1-measure-and-no-fallback
branch: feat-one-shot-9927-inngest-luks-items-6-8b-c1
issue: 9927
closes: none
type: chore
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(infra): Inngest LUKS arc items 6, 8b and C1

Tracker #9927 stays OPEN on purpose. Every commit, the PR body and every follow-up uses `Ref #9927` (and
`Ref #10112` where relevant); no closing keyword anywhere. Draft PR 10652.
[Updated 2026-10-20: revised after the five-seat plan review and a second CTO ruling round; see
`knowledge-base/project/specs/feat-one-shot-9927-inngest-luks-items-6-8b-c1/decision-challenges.md` rows F1b to F5b.]

## Enhancement Summary

**Deepened on:** 2026-10-20
**Sections enhanced:** Overview of P1, Phase 0 to 3, Guard 1, Guard 2, Acceptance Criteria, Dependencies
**Research and review agents used:** repo-research-analyst, learnings-researcher, CTO (three ruling rounds), CLO, CPO, DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, security-sentinel, user-impact-reviewer
**Mechanical gates run:** User-Brand Impact present with a valid threshold; Observability 5-field schema present, command starts with an allowlisted verb and carries no ssh; PAT-shaped scan clean; Scope Check present once and mechanically compliant; `lint-guard-contract.py` green (2 guards); `lint-infra-no-human-steps.py` green; no UI surface (no `.pen` needed); no `.tf` file (Encryption Posture halt does not fire); cited issues and PRs resolved live (#9927, #10112, #7779, #8528, #5697, #8735, #7942, #8659 OPEN; #10355 and #10424 MERGED); cited rule ids exist; labels `deferred-scope-out`, `domain/engineering`, `priority/p3-low`, `compliance/critical` exist.

### Key Improvements
1. P1 is scoped honestly (CTO ruling F6): the loader never exports the read/write token as a read-only reader's token; a legacy-arm job's own `doppler run -c prd_terraform` still reads the read/write token until O10 (Tier-A by design, ADR-241 D4).
2. The C1 probe is hardened against the leaks the security and user-impact reviews found: a spiked and self-proving read-only transaction, a hostile-environment prologue for the PAT, event names printed only from a committed allowlist, exact-key field allowlists for every Doppler `jq`, and a stderr/xtrace leak row.
3. Item 6 gets a decision rule for Route A with a derived-and-cited horizon and a tracked tier arbiter; item 8b gets a computable three-way verdict, shape guards on sites A and B, consumer empty-token rows, an incident-response tag and a break-glass runbook row.

### New Considerations Discovered
- A mis-minted read/write token stored as `HCLOUD_TOKEN_READONLY` is the one path the change cannot see; the O5 write-probe result must be recorded or marked unverified.
- The code read of Inngest event types (`finance.payment_failed`, GitHub action-class events, `agent.spawn.requested`, `email/inbound.received`) shows the "all active users" default may not cover external correspondents; the runbook gets an event-class table.

## Overview

Build three items of the Inngest LUKS residuals tracker in ONE pull request, in the order 6, then 8b, then
C1 (the owner's explicit go of 2026-10-20 overrides the one-item-per-PR rule for these three only). The
commits are two series, `6 + 8b` first and `C1` second, so that `6 + 8b` is green and shippable alone.

- **Item 6.** Measure the Doppler version history of `soleur-inngest/prd`: plan tier, rollback scope,
  activity-log retention. Metadata only, never a diff, value or version content. Record the answer and the
  date measured in an ADR-282 addendum and in the `inngest-luks-cutover-6894.md` runbook.
- **Item 8b.** Confirm with a names-only listing that `HCLOUD_TOKEN_READONLY` exists in Doppler
  `soleur/prd_terraform`, then remove the read/write fallback from three read-only Hetzner token readers
  (site A the loader's legacy arm, site B the PR-plan step, site D the workspaces-luks-cutover volume lookup) so
  none can silently use the destroy-capable token. Tests first. Audit every caller. Site C
  (`scripts/cutover-inngest.sh`) is deferred to a filed follow-up.
- **Item C1.** Measure (existence, shape, retention; never identifiers) whether the Inngest Postgres run
  history or the app logs hold a usable affected-user list after a total loss of the Inngest store. Record
  the answer in the runbook; it also gates the parked ciphertext-backup item (1b).

Authorisation is read-only. No host replace, no `apply_target` dispatch, no Hetzner or Doppler write, no
`terraform apply`, no rotation. web-1 LUKS volume 106443278 is untouched, `rehearsal.tf` is not edited, and the
LUKS passphrase is never handled (not through an agent, a `!` prefix, CI or a recorded session).

## Research Reconciliation: Spec vs. Codebase

| Claim (brief, ADR or code comment) | Reality (measured 2026-10-20 against the worktree at origin/main `f90d49c066`) | Plan response |
|---|---|---|
| Brief: "`action.yml` loops `HCLOUD_TOKEN_READONLY` then falls back to `HCLOUD_TOKEN`" | True, but only in the **legacy arm** (reached when `DOPPLER_TOKEN_INFRA_PRIVILEGED` is empty, which includes a job whose Tier-B environment secret is missing). A YAML walk of every workflow found 33 loader steps, ALL in jobs declaring a Tier-B `environment:` (`infra-privileged`, `web-platform-infra-apply`, `workspaces-luks-cutover`), none with an expression-valued environment, so on `main` they take the Tier-B arm. | Removal changes behaviour only in the degraded state. Floor-guarded census invariant row instead of a committed audit file (F4b). |
| Loader semantics for the absent token | Three callers of the loader (`apply-github-infra.yml`, `apply-sentry-infra.yml`, `web-host-escrow-diagnose.yml`) never reference HCLOUD; the loader takes no per-caller input; `apply-github-infra.yml` detects the legacy arm itself and `git-data-cutover.yml` reads `steps.wipe_loader.outputs.source`; `apply-web-platform-infra.yml` is 488,959 bytes against the 490,000-byte ADR-231 gate (18 call sites), so a new input per call site does not fit. | F2b: rc 0 with a loud `::error` verdict and nothing exported; each consumer fails closed on its own empty token. The first F2 ruling (exit 1) is superseded. |
| Brief names one loader; the same pattern exists elsewhere | Read-only-then-read/write fallback also in: site B `.github/workflows/infra-validation.yml` step "Tier-A plan credentials (bounded substitutes)" (a `pull_request` job); site D `.github/workflows/workspaces-luks-cutover.yml` cutover job volume-id lookup (the live, 1-of-1 member of census G1g's `RO_FIRST` allowance); site C `scripts/cutover-inngest.sh` `_inngest_server_created_epoch`. The census reads workflow `run:` bodies only, so site C is **unscanned** (an earlier draft of this plan wrongly said the allowance held it). | F1/F1b: A, B, D removed; C deferred with a follow-up that includes a census row or script scan over `scripts/`. |
| Brief: "the listing fence in the drift workflow should use the read-only token" | The "fence" is two `echo`ed pasteable bash blocks inside the issue filers of `rung2-rehearsal-orphan-sweep` and `inngest-rehearsal-orphan-sweep` (`scheduled-terraform-drift.yml`, the lines that print `TOKEN="$(doppler secrets get HCLOUD_TOKEN ...)"`) plus prose saying the token "is still the read/write one". The sweep steps themselves read the loader-exported token. | F3: change the two echoed blocks and prose only; follow-up for the sweep steps. |
| `scripts/cutover-inngest.sh` comment: "Measured 2026-09-24: prd_terraform holds only HCLOUD_TOKEN" | Stale: item 9 (merged 2026-10-18) and the 2026-10-15 post-merge read-back both used `HCLOUD_TOKEN_READONLY` successfully. | Phase 2 listing is the arbiter; the stale comment is named in the site C follow-up. |
| `admin-ip-refresh` skill: "`prd_terraform` carries only `HCLOUD_TOKEN_READONLY`" vs ADR-282 addendum 2026-10-16: "`DOPPLER_TOKEN` could still read the read/write token until the O10 eviction" | The two statements disagree on whether O10 happened. | Phase 2 records, names only, whether `HCLOUD_TOKEN` is still listed; the loser is corrected in the same PR. |
| ADR-282 / runbook: "Doppler version history (retained per secret on paid tiers; plan tier and rollback scope NOT measured)" vs `knowledge-base/operations/expenses.md` Doppler row: "Developer plan (free)"; ADR-007 (free tier: 10 projects, 4 environments, 50 service tokens), ADR-241 and ADR-220 (service-account identities and OIDC "need Team or Enterprise", the upgrade being "a cost decision") | Four repo records point at the free Developer plan; none records version-history, rollback or activity-log retention, and none records a Team price. If the plan is Developer, Route A of the "Doppler secret overwritten" recovery may not exist. | Item 6 measures; the finding corrects the wrong document (tier only in the ledger row). An upgrade is money: owner, separately. |
| Runbook: "no per-user list exists, because `schedule-reminder` persists nothing app-side" | Correct for the reminder path: `reminder.scheduled` data carries `reminder_id, fire_at, actor:"platform", action` and NO user id (the `action` can hold a free-text comment body). But other Inngest events carry `founderId` (GitHub action-class events, `finance.payment_failed`, `agent.spawn.requested`) or an email address (`email/inbound.received`). The Postgres half (config and run history, dedicated project) SURVIVES a loss of the Redis AOF volume; the lost half is the queue and run state. | C1 is "which in-flight work was user-bound, and does surviving Postgres history identify it", with the F4 evidence bar. "Complete" is unreachable by shape-and-count probing, so the expected outcome is `partial` or `none` and the default stays. |
| `inngest-server-flip-guard.sh` comment: Better Stack retention "about 3 days" | `betterstack-log-query.md` records the Inngest source 2457081 at 90-day `logs_retention`, corrected 2026-09-04 from a free-tier 3-day figure. | Recorded as `documented, not measured`; the stale comment goes in the follow-up. |
| Article 30 PA-13 (f): history has "NO automatic deletion", AOF retention open | Consistent with the repo (no Inngest-side Postgres retention or prune setting). #7779 (AOF retention) and #8528 (Art. 17 reaches neither Redis copy) are open. | CLO: amend PA-13 (f) and PA-27 (f) in-cell with Superseded markers; link #7779 and #8528 rather than file duplicates. |
| `doppler secrets --only-names` output format | `--help` says "only print the secret names; omit all values" but the repo has no example of its stdout format (table vs lines). | Phase 2 reads the shape with `--json | jq -r 'keys[]'` and a `head` first; an unexpected shape is `could-not-measure`, never "absent". |

## Research Insights

**Premise validation (Phase 0.6, 2026-10-20).** Checked: #9927 is OPEN (priority p3-low); items 8c (PR #10355),
9 (PR #10424) and 5 (state-loss import rehearsal, ADR-282 addendum 2026-10-19) are done, so 6, 8b and C1 are
the remaining measurement items; #10112 is OPEN; `infra-validation.yml` last changed in the TLS PR
(`f90d49c066`), re-diff before editing; the cited files exist on origin/main. The brief's mechanism (a
no-fallback loader) is not in any ADR's rejected-alternatives table: ADR-241 D4 already states that Tier A loses
`HCLOUD_TOKEN` outright at O10, so this PR implements D4's end state ahead of O10. Stale: nothing blocking.

**Property List (Phase 0.6b).**
P1. The loader never exports the read/write Hetzner token, and no read-only Hetzner token reader (sites A, B, D) can silently resolve to it. Scope, by CTO ruling F6: a legacy-arm job's own `doppler run -c prd_terraform` still reads the read/write `HCLOUD_TOKEN` until operator step O10 evicts it (Tier-A by design, ADR-241 D4; the Terraform steps of such a job need it today), and a mis-minted read/write secret stored under the read-only name is undetectable here (control: the O5 write-probe).
P2. Whether Doppler can restore an overwritten `soleur-inngest/prd` key, how far back, and on which plan, is a
dated recorded fact rather than "not measured".
P3. After a total loss of the Inngest store the runbook states what surviving data could narrow the
affected-user set, with an honest evidence class (complete, partial, none) and what was NOT inspected.
P4. No measurement step can read, print, store or transmit a secret value, a diff or a user identifier.

**Cut List (Phase 0.6b, updated after review).**
- New Doppler repair/rollback automation: cut (ADR-282; CTO ruling 2026-10-15).
- A generic read-only Doppler wrapper for item 6: cut; P4 for item 6 is bought by `jq` field extraction in a pipe
  with stderr discarded and by never invoking value-bearing commands (a wrapper would be a second inventory).
- By-name Doppler log-entry count (old M6.4) and the workspace-wide activity pass: cut (they read entry text beside
  the `diff`; oldest-entry age on the one config plus the docs page answers all three asks).
- Committed `caller-audit.md`: cut; replaced by a floor-guarded census invariant plus a PR-body table (F4b).
- Converting the two orphan-sweep steps off the loader token: cut (F3); site C fallback: cut (F1); both ticketed.
- Conditional storage-limitation issue for the Inngest history: no issue filed at plan time; filed in Phase 3 only if
  #7779 and #8528 do not cover the Postgres history.
- A pre-drafted user notice for a total loss (CPO advisory): not in this PR (not asked); ticketed.
- Round-2 probe queries: not pre-specified; only if round 1 shows a typed user-reference column (F3b).

**Value-proposition measurement (Phase 0.6c).** No cost or performance saving is claimed. Not applicable.

**Institutional learnings that bind this work** (under `knowledge-base/project/learnings/`):
- `test-failures/2026-10-19-a-suite-that-nests-its-own-scratch-passed-locally-and-overflowed-the-provider-socket-path-on-ci.md`:
  a suite that spawns itself runs under a CI-shaped `TMPDIR` (under 40 bytes); `lint-trap-tempfile-ownership.py
  --check-highwater` before pushing a new `mktemp`.
- `2026-10-18-sole-copy-drift-check-fixes-were-the-least-audited-surface.md`,
  `test-failures/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`: a timeout or
  unreadable response is its own `could-not-measure` verdict, never the absent or zero verdict.
- `security-issues/2026-10-18-a-fix-that-removes-a-block-must-re-derive-what-the-block-was-bounding-and-a-canary-green-over-an-outage-is-a-claim.md`,
  `2026-05-29-pre-flight-integrity-check-through-unremoved-fallback-gives-false-confidence.md`: re-derive what the
  fallback was bounding (the merge-to-O5 window, now spent); the pre-removal check must not read through the fallback.
- `2026-09-11-every-sentence-my-runbook-inherited-was-false-when-measured.md`: every causal or universal sentence a
  diff adds to a runbook or ADR needs a measurement behind it.
- `workflow-patterns/2026-10-15-removing-a-printed-recipe-owes-a-bounded-replacement-and-a-spelling-guard-is-a-tripwire.md`:
  fence rows assert behaviour (read-only name present, bare fallback absent), not spelling alone.
- `security-issues/2026-05-26-doppler-secrets-delete-dumps-full-config-to-stdout.md`,
  `2026-06-16-supabase-mgmt-api-401-is-often-validation-not-auth.md`.

**Verified CLI surface (2026-10-20, `doppler` v3.77.0, `doppler <cmd> --help` run locally):** `doppler secrets
--only-names`, `doppler activity get`, `doppler settings`, `doppler me`, `doppler configs logs` (subcommands `get`
and `rollback`; `-n/--number`, `--page`, `-p`, `-c`), global `--json`, `--debug`. `rollback` is a WRITE and is
never invoked. Whether `--json` output of `configs logs` carries a `diff` field with values is NOT known. The
probe uses `doppler run --only-secrets SUPABASE_ACCESS_TOKEN` (the flag exists on `doppler run`; confirm with
`doppler run --help` at work time, and confirm which config holds the PAT: `inngest.tf` sources it from
`prd_terraform`, the runbook reads it from `prd`).

**Prior art for the probe transport:** `.github/workflows/scheduled-inngest-health.yml` (the `pg_stat_activity`
POST) and `scripts/cutover-inngest.sh` (the same endpoint) already query this project; `scripts/supabase-advisor-scan.sh`
and `apps/web-platform/scripts/postgrest-reload-schema.sh` are the confined-curl shapes. No repo script uses a
read-only transaction or a statement allowlist, and `scripts/lint-supabase-deprecated-endpoints.sh` (host pin plus a
`.highwater` file) will scan the new script.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "build items 6, 8b and C1 together in ONE PR, in the order 6, then 8b, then C1" [brief] | Phases 1 to 3 in that order, one PR, two commit series | mapped |
| 2 | "Doppler version-history measurement for `soleur-inngest/prd`. Read-only: plan tier, rollback scope and activity-log retention." [brief] | Phase 1 (M6.1 to M6.3) | mapped |
| 3 | "Record the answer (and the date measured) in the ADR-282 addendum and the inngest-luks-cutover runbook." [brief] | Phase 1 recording tasks | mapped |
| 4 | "First confirm with a NAMES-ONLY listing that `HCLOUD_TOKEN_READONLY` exists in Doppler `prd_terraform`" [brief] | Phase 2 step 1 (M8b.1, gates the phase) | mapped |
| 5 | "then remove the fallback so the read-only loader fails instead of using the read/write token, and audit every caller" [brief] | Phase 2 (RED rows, sites A, B, D, caller invariant) | mapped |
| 6 | "Tests first (cq-write-failing-tests-before)" [brief] | Phase 2 step 3 precedes step 4 | mapped |
| 7 | "the listing fence in the drift workflow should use the read-only token with no fallback, only if the caller audit shows it safe" [brief] | Phase 2 step 7 (F3: echoed blocks only) | mapped |
| 8 | "does the Inngest Postgres run history or app logs hold a usable affected-user list after a total loss of the Inngest store, and what is the retention? ... NEVER pull or print any user identifiers or personal data" [brief] | Phase 3 | mapped |
| 9 | "Record the answer in the runbook; it also gates the parked ciphertext-backup item." [brief] | Phase 3 recording tasks | mapped |
| 10 | "The PR body must say what was measured versus not measured, with dates." [brief] | Phase 4 PR body table | mapped |
| 11 | "After the FIRST push of any new or changed suite, read the CI leg that owns it (`deploy-script-tests`) BEFORE spawning review seats." [brief] | Phase 4 step 1 and the Phase 3 CI gate | mapped (owning leg corrected, see Phase 4) |
| 12 | "re-check that file and `infra-credentials` for overlap against current origin/main before editing" [brief] | Phase 0 step 1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Site B (`infra-validation.yml`) and site D (`workspaces-luks-cutover.yml`) fallback removal | "audit every caller (grep all uses of the action and of the read-only loader)" | asked (CTO F1/F1b: both are read-only Hetzner token readers) |
| Probe wrapper script + its test suite | "retention/shape probes for item C1 ... NEVER pull or print any user identifiers" | asked (CTO F4: the only way to make "never print" structural when the credential can run arbitrary SQL) |
| ADR-241 amendment-log entry | "Record the answer ... in the ADR-282 addendum" | inferred - justification: the PR makes ADR-241 D4's end state true in code ahead of O10; plan Phase 2.10 requires the ADR record in the same PR (CTO F5b: one dated entry, D4 body untouched) |
| Article 30 register + compliance-posture entries | "apply the GDPR gate; hr-gdpr-gate-on-regulated-data-surfaces" | asked (CLO conditions) |
| Follow-up issues (a) site C, (b) sweep steps, (c) user notice, (d) project-scoped read-only role | "Technical forks go to soleur:engineering:cto" | inferred - justification: the CTO deferred (a), (b), (d) and the CPO advised (c); a deferral without a tracking issue is invisible |
| `expenses.md` Doppler row (tier only) | "Record the answer (and the date measured)" | inferred - justification: a measured tier contradicting the ledger row leaves a false record; touched only if item 6 falsifies it, tier only |
| Census invariant row "every loader job declares a Tier-B environment" | "audit every caller" | asked (replaces the cut `caller-audit.md`, F4b) |

### Split Assessment

- Subsystems touched: 4 roots - `.github/` (action, workflows), code and suites (`scripts/`, `plugins/soleur/test/`, `tests/scripts/`), `knowledge-base/engineering/` (ADRs, runbooks), `knowledge-base/legal/` + `knowledge-base/operations/` (register, posture, ledger)
- Planned files: 20 (16 to edit, 4 to create) plus the register sibling-marker sweep, counted at work time | Estimated changed lines: 600 to 850, about half prose
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, with the commit boundary unconditional: series 1 = item 6 + item 8b (green and shippable alone), series 2 = item C1. The subsystem count meets the threshold on its face; the owner's explicit 2026-10-20 go is the recorded override. If C1 trips a CLO stop condition, series 2 is removed with revert commits (no history rewrite) and 8b ships from the same branch (CTO F4b).

## Open Code-Review Overlap

Query run 2026-10-20 against open `code-review` issues for every planned path.

- #8735 (infra-validation notify-main-failure misses cancelled jobs) touches `.github/workflows/infra-validation.yml`: **Acknowledge.** Different job; this PR edits only the "Tier-A plan credentials" step.
- #7942 (two `*.mutation.sh` batteries run in no gate) touches `.github/workflows/infra-validation.yml` and `scripts/test-all.sh`: **Acknowledge.** This PR adds one `run_suite` line and no `*.mutation.sh` file.
- #8659 (33 suites replace test-helpers' composed EXIT trap) touches `scripts/test-all.sh`: **Acknowledge.** The new suite keeps the composed trap (`SUITE_TMP` with an owning EXIT trap); not folded in.
- No open code-review issue names `action.yml`, `infra-credentials.test.sh`, `workspaces-luks-cutover.yml`, `scheduled-terraform-drift.yml`, the census, `token-drift-workflow-causes.test.sh`, the ADRs, the runbooks or the register (site D and the lint files were checked again at work time, Phase 0).

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO, advisory)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Two ruling rounds on 2026-10-20 (F1 to F5, then F1b to F5b after the plan review); rulings and rationale are rows in `knowledge-base/project/specs/feat-one-shot-9927-inngest-luks-items-6-8b-c1/decision-challenges.md`. Residual risks: the Supabase personal access token is account-wide (project-scoped read-only role is the durable fix, follow-up); whether the Management API honours `begin read only` is unverified and is probed by the preflight; O10 status and non-emptiness of the read-only secret are unmeasured until Phase 2.

### Legal (CLO)

**Status:** reviewed
**Assessment:** The bounded aggregate/schema probe is acceptable under Art. 32(1)(b) to (d) and Art. 5(1)(b), no new lawful basis, DPIA or processing activity. Conditions are binding in Phase 3. A positive claim states shape and non-null counts only; a negative ("no per-user source exists") cannot be asserted from shape and counts. The did-not-inspect sentence goes into the runbook verbatim. The stop list is in Phase 3, including the halt outcome defined there.

### Product/UX Gate

**Tier:** none (no user-facing surface, no UI file in Files to Create/Edit; mechanical override scanned and did not fire)
**Decision:** auto-accepted (pipeline)
**Agents invoked:** soleur:product:cpo (advisory, threshold sign-off only)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO sign-off 2026-10-20: agrees with Brand-survival threshold `single-user incident`. The harm is a silent, per-user loss that goes unnoticed if the affected set is understated, and C1 must stay aggregate-only. Product concerns carried: (1) absence of evidence is not exoneration, so the runbook keeps "treat all active users as affected" unless the evidence is complete across the outage window and records the evidence class (complete, partial, none) beside the finding; (2) a pre-drafted user notice naming what was lost, the window and the action to take, with the legal notification question routed to the CLO, is a follow-up (not built here: it was not asked for).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly from the loader change unless it breaks infra apply or rollback CI during an incident (a delayed recovery of the product); from item C1, a runbook that states a narrower affected set than is true, so some users whose reminders or in-flight jobs were lost with the store are never told.
- **If this leaks, the user's data is exposed via:** the C1 probe printing, logging or persisting an identifier, email or event payload from the Inngest history (event data holds `founderId`, `installationId` and email addresses for some event types), or the Supabase personal access token (account-wide, reaches the production app project) being printed; the item 6 commands touching `diff` content that carries plaintext secrets.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one user wrongly left out of an affected-user notice, or one identifier printed by the probe, is already a brand-level event; `aggregate pattern` was rejected because neither failure shows up as a rate. CPO sign-off recorded above; `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Architecture Decision (ADR/C4)

### ADR

- **ADR-241 (CTO F5b):** one dated entry appended to its amendment log (via `soleur:architecture`), citing D4 and leaving D4's body and the D4 status-table row untouched: the loader legacy arm, the PR-plan step and the workspaces-luks-cutover lookup no longer fall back to the read/write token (D4's "Tier A loses `HCLOUD_TOKEN` outright" end state, enforced in code ahead of O10 and independent of it); site C named as the remaining fallback with its follow-up; the `source=legacy` rc 0 semantics unchanged. D4 stays `accepted`.
- **ADR-282:** one addendum dated the measurement day covering items 6, 8b and C1 as measured-versus-not-measured tables; the three sentences the findings falsify (loss-mode table "plan tier ... NOT measured here", residual "That token is also the silent fallback of the read-only loader", and "Whether a surviving source exists ... is open") stay in place under `> **Superseded 2026-10-20 (#9927), as to <what>:**` blockquotes, and the addendum states the exception to append-only (the 2026-10-19 addendum is the precedent).

### C4 views

Read in full at work time and cited in the PR: `model.c4`, `views.c4`, `spec.c4` under `knowledge-base/engineering/architecture/diagrams/`. Enumeration: (a) external human actors: the founder (edges `founder -> doppler`, `founder -> github` exist) and agent sessions (modelled agent contexts); no new actor. (b) external systems: Doppler, Hetzner, Better Stack and Supabase (`inngestPostgres`, edge `inngest -> inngestPostgres "Config + run history"`) are modelled; the Supabase Management API is a control-plane read path to the already-modelled `inngestPostgres`. (c) containers/data stores: `inngestPostgres` and `inngestRedis` exist; nothing is created. (d) actor-to-surface access: the model has a CI-to-Supabase Management API edge but, as far as the enumeration shows, none for a founder or agent session using the account-wide personal access token against Supabase. Work-time decision, recorded in the PR: add that one edge (and its `views.c4` include if it must render) if absent, or record that it was deliberately not modelled and why. `bash plugins/soleur/test/c4-count-parity.test.sh` proves derived cardinalities only, NOT the actor reasoning; the PR says so.

### Sequencing

Both ADR edits land in this PR; ADR-282 and ADR-241 D4 are already `accepted`. No ordinal is allocated.

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file is created or edited (`rehearsal.tf` and every rehearsal root stay untouched). No new store, secret, vendor account or host.

### Apply path

Not applicable: the PR changes a composite action, two workflow steps, two issue-body echo blocks, test suites, one agent-side wrapper script and documentation. Nothing is applied; no host is touched.

### Host fan-out

Not applicable (no `terraform_data` SSH provisioner under `apps/web-platform/infra/` is edited).

### Distinctness / drift safeguards

The probe wrapper pins the Inngest Supabase project ref and refuses any other ref (`hr-dev-prd-distinct-supabase-projects`): the web-platform production project holds real user data and the same personal access token reaches it.

### Vendor-tier reality check

Item 6 itself measures the Doppler tier. No tier-gated resource is created.

## Observability

```yaml
liveness_signal:
  what: the loader's own annotation on every run - source=tier_b in the normal arm; an ::error with verdict=legacy_hcloud_readonly_absent (naming privileged_source_missing as the likelier root cause) in the degraded arm
  cadence: per run of each of the 33 loader steps (apply-*, scheduled-terraform-drift every 12h, git-data and inngest rehearsals) and per run of the two direct readers (infra-validation PR plan, workspaces-luks-cutover)
  alert_target: a failed consumer step reaches the operator through notify-ops-email and the standing drift issue; the loader itself pages nobody
  configured_in: .github/actions/infra-credentials/action.yml (the load step)
error_reporting:
  destination: GitHub Actions annotation and job log (observability layer 6, workflow run log / `::error::` annotation; no Sentry in a composite action; the C1 measurement was an operator-session tool, so no layer is claimed and its durable record is specs/.../measurements.md)
  fail_loud: the loader exits 0 on purpose (non-Hetzner callers) but exports nothing and prints the ::error verdict; the Hetzner consumers fail closed on their own empty token, and sites B and D fail their own step with a named message
failure_modes:
  - mode: read-only token deleted or renamed in Doppler prd_terraform while a job takes the legacy arm
    detection: the ::error verdict in the loader step, then the consumer's own fail-closed refusal; never a silent continuation on the read/write token
    alert_route: notify-ops-email for apply workflows; standing infra-drift issue for the drift-check matrix (observability layer 6, workflow run log, plus the existing workflow-failure email). NOT covered, stated plainly (review 2026-10-22): the two orphan-sweep jobs in scheduled-terraform-drift.yml (`rung2-rehearsal-orphan-sweep`, `inngest-rehearsal-orphan-sweep`) have no notification path, so on the legacy arm they fail red with no issue and no email
  - mode: the secret stored as HCLOUD_TOKEN_READONLY is actually a read/write token (mis-minted)
    detection: not detectable by this change; the control is operator step O5's write-probe in infra-credential-tiers-8209.md (stated in the ADR-282 2026-10-16 addendum)
    alert_route: none by design; recorded as an accepted residual
  - mode: the C1 probe receives an unexpected response shape
    detection: the formatter refuses it and exits non-zero with could-not-measure(<enum reason>); nothing from the body is printed
    alert_route: the executing agent session stops and reports; the CLO stop list applies
logs:
  where: GitHub Actions run logs for the loader; the probe prints counts and structure to the agent session only and writes no repository file or log beyond counts, names and timestamps
  retention: GitHub Actions default 90 days (repository setting); probe output is not written to any log or file
discoverability_test:
  command: grep -o "verdict=legacy_hcloud_readonly_absent" .github/actions/infra-credentials/action.yml
  expected_output: verdict=legacy_hcloud_readonly_absent
```

## Guard Contract

### Guard 1 - the Hetzner token readers cannot resolve to the read/write token

**Property.** No code path of the Tier-B credential loader (`.github/actions/infra-credentials/action.yml`), of the PR-plan step "Tier-A plan credentials (bounded substitutes)" (`.github/workflows/infra-validation.yml`) or of the workspaces-luks-cutover volume lookup (`.github/workflows/workspaces-luks-cutover.yml`) reads or exports the read/write Hetzner token name from `prd_terraform`.

**Assembly.** Three sites, not one: every `doppler secrets get <name> ... -c prd_terraform` call in command position inside those three `run:` bodies (today the `for n in HCLOUD_TOKEN_READONLY HCLOUD_TOKEN` loop in the legacy arm and the two sequential reads in each of sites B and D). The static arm is census row G1g with its `RO_FIRST` allowance DELETED, so G1g is strict across every workflow (the allowance's only live member was site D); the existing M-g1-g1 comment-laundering mutation stays RED and M-g1-g2 inverts to RED. The behavioural arm quantifies over the loader stub's read log across every arm the suite drives (legacy with and without the read-only token, Tier-B), so an indirection such as `n=HCLOUD_TOKEN; doppler secrets get "$n"` is caught without parsing. Site C (`scripts/cutover-inngest.sh`) is the one remaining member and is UNSCANNED (the census reads workflow `run:` bodies only); it is held by nothing but its follow-up issue, which must add a census row or script scan over `scripts/`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | restore `for n in HCLOUD_TOKEN_READONLY HCLOUD_TOKEN` in a copy of `action.yml` | RED (row 1c: rw-only present, rc 0, no `HCLOUD_TOKEN` exported, read log never lists `HCLOUD_TOKEN`) |
| 2 | dispatch: rename the `id: load` step so the extraction finds none, and separately feed the census a tree with zero loader-job rows | RED / exit 2 (extraction refuses; the new invariant row has a floor on jobs scanned > 0) |
| 3 | add a SECOND read site after a compliant first: `RO=$(doppler secrets get HCLOUD_TOKEN_READONLY ...)` then `X=$(doppler secrets get HCLOUD_TOKEN ...)` in site B or site D | RED (strict G1g names the job) |
| 4 | indirection: `n=HCLOUD_TOKEN; doppler secrets get "$n" ...` in the legacy arm | RED (behavioural row: the read log contains `HCLOUD_TOKEN`) |
| 5 | comment-launder: a comment naming the read-only read above a bare rw read | RED (M-g1-g1) |
| 6 | change the absent arm to export the read/write token, or to exit non-zero (the F2b semantics are rc 0, nothing exported, the verdict printed) | RED (row 1d asserts rc 0, no export, verdict) |
| 7 | drop the `environment:` key from one loader job in a fixture tree | RED (new census invariant "every loader job declares a Tier-B environment") |
| 8 | the legacy arm or site B accepts a whitespace-only or multi-line read-only value (shape check removed) | RED (must-pass row with metacharacters stays green; a whitespace-only value yields the named refusal and no export) |

**Harness rows.** (a) Suite edit that must go RED: make the stub answer success for every `HCLOUD_TOKEN` read and re-run with mutation 1; the "never requested" assertion must still fail (a stub that cannot see the read would pass it vacuously). (b) Must-PASS non-canonical input: both tokens present with distinct sentinels plus a read-only value containing shell metacharacters and a newline-injection attempt; assert the exported value is the read-only one, the rw sentinel appears in neither `$GITHUB_ENV` nor the read log, and the heredoc form holds. (c) Extraction guard: add `legacy_hcloud_readonly_absent` and keep `privileged_source_missing` in the loader test's marker list so a truncated extraction cannot pass.

**Anchor.** No stored value is compared; the property is behavioural (the stub's read log) plus strict census scanning. The census row has the usual one-diff weakness (a diff can edit the action and the row together); outside anchors are the required `test` check, CODEOWNERS routing for `.github/`, and the live names-only listing recorded in the PR body (no diff can edit it).

### Guard 2 - the C1 probe can only send allowlisted read-only queries to the pinned project and print only shapes

**Property.** Every request the probe sends to the Supabase Management API is byte-equal to a committed literal query wrapped as `begin read only; <query>; rollback;` with bounded `statement_timeout` and `lock_timeout`, addressed to the pinned Inngest project ref, sent only after an identity preflight (sentinel tables present, no app tables, `show transaction_read_only` reads `on`) passed in the same invocation, and nothing but numbers, timestamps and pinned-shape identifiers reaches stdout.

**Assembly.** The single chokepoint is the probe's one `_send` function; members are the allowlist entries keyed by name and the formatter's output branches. A second transport (a second `curl` call site) is itself a RED. The allowlist is small (identity, columns, estimates, time bounds; round-2 entries are added one commit at a time), so the literal lint is a single pass over every `Q_*` literal.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | add a query whose literal contains `select *`, `limit`, `distinct`, a jsonb operator (`->`, `->>`, `#>`, `?`) or a parameter substituted into SQL | RED (literal lint over every `Q_*` entry; this also covers a second member added after a compliant first) |
| 2 | dispatch: make the request-capture stub record nothing, or have the script skip `_send` | RED (the suite asserts >= N captured requests, each mapping to an allowlist name) |
| 3 | unknown query name, or a ref argument accepted | RED (rc 2 with ZERO requests; wrong ref refused before any request) |
| 4 | drop the `begin read only` wrapper or the timeouts from one entry, or skip/reorder the identity preflight | RED (every captured body must match the wrapper pattern; a failing preflight must yield zero further requests) |
| 5 | formatter prints a string that looks like an email, a UUID, a run of 6+ digits or free text from the stub response | RED (leak case: nothing from the body on stdout, non-zero exit) |
| 6 | non-2xx, timeout, empty body or a missing `show transaction_read_only` result treated as a zero | RED (verdict `could-not-measure(<enum>)`, never `measured-absent`; `measured-absent` needs a parseable zero or an empty listing plus a positive control in the same session, and a `reltuples` estimate can support `measured-present` only) |

**Harness rows.** (a) Suite edit that must go RED: replace the stub with one returning the leaky body for every request and confirm mutation 5 is caught. (b) Must-PASS non-canonical: a differently ordered, whitespace-varied but valid response prints the same counts. (c) If the suite re-executes itself as a child it runs under `TMPDIR=/var/tmp/runner-wk/_temp` in addition to the default. (d) A row that the wrapper's child environment holds no secret other than `SUPABASE_ACCESS_TOKEN` (after the prologue unsets). (e) Leak rows on STDERR, under `bash -x`, on the failure exit path and with a stub error body that echoes SQL or a value: nothing from the body, the token or an identifier may appear on any stream. (f) Leak rows for a 32-hex id without dashes, a hash-shaped string, an email local part and a short-digit id.

**Anchor.** The allowlist literals and the pinned ref live in the same file as the check, so a diff can weaken both; outside anchors are CODEOWNERS on `scripts/`, the review seats (security-sentinel, user-impact-reviewer) and the fact that the first live run happens only after the suite is green in CI (Phase 3 gate). The script carries a `SOLEUR-DEBT:` marker with the retire trigger "delete after the C1 finding is recorded and no follow-up probe is scheduled", so it does not become a standing credentialed tool.

## Implementation Phases

Order is fixed by the owner: 6, then 8b, then C1. Phase 0 is shared setup; Phase 4 is shipping. Series 1 = Phases 1 and 2; series 2 = Phase 3.

### Phase 0 - setup and overlap re-check (no production access)

1. `git fetch origin main`, then `git diff --stat HEAD origin/main` over EVERY path in Files to Edit (not only the two workflow paths) and rebase if main moved; the TLS PR merged 2026-10-20 (`f90d49c066`) and touched `infra-validation.yml`. Re-run this diff after any later rebase and before Phase 4. The worktree was created by this session; no other worktree is reused.
2. File the tracking issues this plan defers (each `Ref #9927`, milestone `Post-MVP / Later`, label `deferred-scope-out`; verify not a duplicate with `gh issue list --search`): (a) site C `scripts/cutover-inngest.sh` read-only-then-read/write fallback: re-evaluation trigger "O10 done and the read-only token confirmed", the stale 2026-09-24 comment, and the requirement to add a census row or script scan over `scripts/`; (b) convert the two orphan-sweep steps off the loader-exported token; (c) pre-drafted user notice for a total loss of the Inngest store (CPO advisory; legal question routed to the CLO); (d) a project-scoped read-only role for Inngest-history probes instead of the account-wide personal access token; (e) the stale "about 3 days" Better Stack comment in `inngest-server-flip-guard.sh` (fold into (a) if convenient); (f) the owner dashboard read of the Doppler plan page as the single tier arbiter (an owner step, not a blocker, filed only if M6.2 cannot measure the tier). The conditional storage-limitation issue is Phase 3, not here.
3. Baseline: `bash .github/actions/infra-credentials/infra-credentials.test.sh` green before any edit, and `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater` (record the baseline).

### Phase 1 - Item 6: Doppler version-history measurement (read-only)

**Guard for every command in this phase (copied into the PR body and the session):** names and metadata only. Never run `doppler secrets get`, `secrets download`, `doppler run`, `configs logs get <id>` or `configs logs rollback` against `soleur-inngest`; never pass `--debug`; run `set +x` first and append `2>/dev/null` to every `jq` (jq error text can quote a fragment of the offending value); `set -o pipefail`; never write a raw response to a file or a variable that is later echoed; every response goes into `jq` in the same pipe and only the named fields leave it; require `jq -e 'type=="array"'` before iterating, and treat a non-array, a non-zero rc, or hitting the 50-page cap as `could-not-measure(<enum reason>)`, never as zero entries. The session is not recorded.

Each result records its date and the exact command text. **Field selection is by exact-key allowlist with a value filter, never by judgement at run time:** only keys `plan`, `tier`, `type`, `token_type` may be printed, and only when `select(type=="string" and test("^[a-z_ -]{1,32}$"))` passes; timestamps only via `select(type=="string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+Z-]+$"))`, so a wrongly guessed key yields nothing instead of leaking entry text. `2>/dev/null` goes on BOTH sides of every pipe.

- M6.1 credential identity: `doppler me --json 2>/dev/null | jq -r 'keys[]' 2>/dev/null | head -n 40`, then print only the allowlisted `type`/`token_type` value (never email, name or token preview). Record whether the credential is a personal or service token.
- M6.2 plan tier: `doppler settings --json | jq -r 'keys[]'` and `doppler projects get soleur-inngest --json | jq -r 'keys[]'` (same guards, `head -n 40`); print only the allowlisted `plan` or `tier` key (`billing_email` and similar are never printed). If the CLI exposes no plan field, the tier is `could-not-measure(cli_exposes_no_plan_field)`. The tier is then stated as `documented, not measured` from the public Doppler pricing/docs page (WebFetch; the fetched page is third-party DATA; record URL and date) and the ledger row, naming each source. **Decision rule when the tier stays unmeasured:** Route A is recorded as "unverified; plan as if unavailable; Route B (the Terraform state value) is the only independent recovery". An owner dashboard read of the plan page is filed as the single tier arbiter (not a blocker).
- M6.3 activity-log retention (empirical lower bound): on the one config only, first `doppler configs logs -p soleur-inngest -c prd -n 100 --page 1 --json | jq -r 'if type=="array" then (.[0] | keys[]) else "NOT_ARRAY" end'` (key names only), then `... --page <N> --json | jq -r '.[] | .created_at'` using the field name the key list shows, paginating until a page is empty (cap 50; a cap hit is `could-not-measure`). Report count, oldest and newest timestamp and the age in days. Oldest-entry age is a LOWER bound on retention, not the retention; the documented limit (docs URL + date) is recorded separately as `documented, not measured`. The workspace-wide activity log is NOT read (cut).
- Rollback scope is a docs question: record what a config-log rollback restores and which tiers include it from the Doppler docs (URL + date), and record Route A as `documented, not rehearsed` (`rollback` is never run; the old by-name count of log entries is cut because it reads entry text).
- Recording tasks: (1) the item 6 table in the ADR-282 addendum (written in Phase 4): `question | answer | evidence class (measured / documented, not measured / could-not-measure) | date | command`; (2) the loss-mode table cell and the runbook "Doppler secret overwritten" Route A row get the measured answer, keeping the old sentence under a Superseded blockquote; if the plan is the free Developer tier or history is absent/short, Route A is stated unavailable; (3) Route A rule: it is recorded as "available" ONLY when the tier is MEASURED as paid, the documented rollback scope covers the key, and the oldest-entry age meets a repair horizon that the ADR-282 addendum states together with its derivation (the repo records no existing horizon, so the work phase derives and cites one, for example from the 12-hour drift cadence plus the owner response time); otherwise "unverified; treat as unavailable", and every mention of Route A or Doppler version history is swept in one `git grep -n -i "version history\|Route A" -- knowledge-base plugins` pass (ADR-282 loss-mode table, `infra-credential-tiers-8209.md`, the other runbooks) with the count in the PR body; (4) `knowledge-base/operations/expenses.md` Doppler row corrected on the TIER only if item 6 falsifies it (config count is out of scope; a plan upgrade is money, never proposed here).

### Phase 2 - Item 8b: no-fallback Hetzner token readers

Gate first, then RED, then GREEN.

1. **M8b.1 names-only listing (gates this whole phase).** Same guards as Phase 1 (`set +x`, never `--plain`, never `secrets get`, never echo the captured text because `--json` may carry values). The verdict must be computed from separate return codes, not a pipe (a pipe under `pipefail` makes a `grep` miss indistinguishable from a Doppler failure, and `head` adds SIGPIPE): `names="$(doppler secrets --only-names --json -p soleur -c prd_terraform 2>/dev/null)"; rc=$?`; then `jq -e 'type=="object"' <<<"$names" >/dev/null 2>&1; shape_rc=$?`; only then `jq -r 'keys[]' <<<"$names" 2>/dev/null | grep -xF -e HCLOUD_TOKEN_READONLY -e HCLOUD_TOKEN`. Verdict: **listed** (rc 0, shape ok, name present), **absent** (rc 0, shape ok, grep rc 1), **could-not-measure** (rc not 0, or shape not ok; never reported as "absent"). Record with date for both names (the second is the O10 status). Corroboration under the Tier-A service token's identity, none of which reads a value, each with a POSITIVE CONTROL (at least one qualifying run exists in the window, else the grep result is `could-not-measure`): the recent `infra-validation` plan-step logs lack the warning text `HCLOUD_TOKEN_READONLY is absent from prd_terraform`; recent loader-using runs lack `hcloud_token=absent`; the latest `sole-copy-protection-check` conclusion (`gh run list --workflow scheduled-terraform-drift.yml --limit 6 --json databaseId,createdAt,conclusion`, then `gh run view <id> --json jobs --jq '.jobs[] | select(.name | test("sole-copy")) | .conclusion'`). None can show a non-empty or really-read-only value: record the date and result of the O5 write-probe from `infra-credential-tiers-8209.md` or mark it `unverified`. **If `HCLOUD_TOKEN_READONLY` is absent or could-not-measure:** stop item 8b, edit no file under `.github/` or `tests/`, say so in the PR body, file the finding, continue to Phase 3 (CTO F1/F1b: sites B and D stay, `RO_FIRST` stays). **If it is listed but `HCLOUD_TOKEN` is not (O10 done):** the fallback is dead code; proceed.
2. **Caller invariant, not a committed audit file.** Add to the census a floor-guarded row: every job that uses the loader declares a Tier-B `environment:` (reuse the `has_env_key` and `arms` logic of G1h; floor on jobs scanned; mutation row that drops an `environment:` key). Re-run the YAML walk for the PR-body table (job, environment, whether the job needs a Hetzner token TRANSITIVELY: a `-c prd_terraform` read, `TF_VAR_hcloud_token`, a terraform root with the hcloud provider, or a script that calls `api.hetzner.cloud`; cite the extraction command; reconcile the count against `git grep -c "uses: ./.github/actions/infra-credentials" -- .github/workflows`). Planning measured 33 loader steps and 3 callers with no HCLOUD reference (the reason F2b chose rc 0). **Tag the incident-response jobs** (`apply_target` replace/recut jobs, `git-data-cutover`, `workspaces-luks-cutover`, `web-host-escrow-diagnose`) and assert in the invariant row that each declares a Tier-B environment (so none can reach the legacy arm). **Consumer empty-token rows:** for each Hetzner-needing consumer in the table, record whether it fails closed on an empty token (`bc_curl`, `bc_ok_var` or a `[[ -z ]]` guard) and add a row that drives it with the token unset and expects a red result, not "no drift"; where a consumer cannot be driven, record it as an accepted gap in the PR body. Check whether `apply-web-platform-infra.yml` near its `[[ -z "$HCLOUD_TOKEN" ]]` checks runs under `set -u` (an absent variable would stop there with an unbound-variable error instead of its named abort); fix with `${HCLOUD_TOKEN:-}` only if the file stays under the 490,000-byte ADR-231 gate (currently 488,959).
3. **RED (cq-write-failing-tests-before).** Edit the suites first, commit the RED suite ALONE, run it against the unedited action and record the commit SHA and the failing rows (the loader test hardcodes `ACTION_YML="$HERE/action.yml"`, so a scratchpad copy of the old action is not a usable RED proof). Rows: `.github/actions/infra-credentials/infra-credentials.test.sh` per F2b (1c: only the read/write token present = rc 0, no `HCLOUD_TOKEN` in the env file, rw sentinel absent from env and output, read log never lists `HCLOUD_TOKEN`, `::error` with the verdict and the `privileged_source_missing` hint; 1d: both absent = the same verdict, rc 0, nothing exported, not reported as unauthorized; auth-error case keeps `legacy_token_unauthorized`, rc 0; 1b unchanged; Guard 1 harness rows), `tests/scripts/test-infra-privileged-tier-census.sh` (delete `RO_FIRST`, invert M-g1-g2, add the caller-invariant row and site B coverage), `apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh` (stub models an empty `RO_TOKEN`; add the distinct refusal reason `readonly_absent`), and a source-level row plus mutation row for site B (no suite pins it today; the grep for "Tier-A plan credentials" found none).
4. **GREEN, site A.** `action.yml` legacy arm: the loop becomes one read of `HCLOUD_TOKEN_READONLY`; absent/empty prints `::error title=infra-privileged::source=legacy verdict=legacy_hcloud_readonly_absent` naming `privileged_source_missing` as the likelier root cause, exports nothing, rc 0 (F2b); the auth-failure branch keeps `legacy_token_unauthorized` (rc 0); keep the stderr temp file and the grep split, the heredoc export and per-line masking; run the `_bearer_ok` shape check (site D's pattern) on the value BEFORE masking or exporting and fail with a named reason, because `[[ -n ]]` accepts a whitespace-only value; the new `::error` strings are static (a row asserts they contain no `${`); "export nothing" is deliberate (CTO F6: exporting an empty `HCLOUD_TOKEN` would win under `--preserve-env` and break every legacy-arm Terraform step, which needs the read/write token until O10; cite row 8.8 in the row comment); update the header comments that describe the before-state fallback and the census G1g anchor sentence.
5. **GREEN, site B.** `infra-validation.yml` plan step: single read of `HCLOUD_TOKEN_READONLY`; when absent, fail the step with a named message instead of exporting the read/write token; run the `_bearer_ok` shape check and mask PER LINE (the current `add-mask` covers only line 1, and a value planted via `DOPPLER_TOKEN_WRITE` until O11 could otherwise inject workflow commands in a `pull_request` job). Re-diff against `origin/main` immediately before editing (TLS PR overlap). Only after M8b.1 says listed.
6. **GREEN, site D.** `workspaces-luks-cutover.yml` cutover job volume-id lookup: single read of `HCLOUD_TOKEN_READONLY`; when empty the step fails with a named refusal (`readonly_absent`) before any request, consistent with the shape guard; update the "fallback disappears at O10" comment. Only after M8b.1 says listed.
7. **Listing fence (F3).** In `scheduled-terraform-drift.yml` change the two echoed blocks to `TOKEN="$(doppler secrets get HCLOUD_TOKEN_READONLY -p soleur -c prd_terraform --plain)"` with no fallback and reword the prose that says the token "is still the read/write one" (both filers). Fence rows in `plugins/soleur/test/token-drift-workflow-causes.test.sh`: first a RED-then-GREEN row proving its classifier (the `SCOPE` tuple holds the bare name `HCLOUD_TOKEN`, a substring of the read-only name) handles both an echo of `HCLOUD_TOKEN_READONLY` and the old bare echo, using a word-bounded check; then rows asserting both blocks contain the read-only name, contain no bare `doppler secrets get HCLOUD_TOKEN ` fallback, and the prose no longer says "still the read/write one". The sweep steps keep the loader token (follow-up). Do not touch `sole-copy-drift-check.test.sh` or `stock-preflight-coverage.test.ts` (neither pins loader fallback text).
8. Update the consumer-inventory rows and the O5/O10 notes in `infra-credential-tiers-8209.md` that describe the fallback, and add a break-glass row for the removed implicit fallback: if the read-only token is absent or rotated while an incident PR needs a plan, restore the Tier-B environment secret first (the likelier root cause), otherwise mint a new read-only token in Doppler BEFORE deleting the old one, by the O5 procedure. `scripts/cutover-inngest.sh` is left alone (site C).
9. Run the touched suites and the census. The C4 parity test runs in Phase 4.

### Phase 3 - Item C1: surviving source for the affected-user list (read-only, aggregate only; commit series 2)

**Stop-and-go-to-owner list (CLO, binding):** any output, error or log containing a user identifier, email or payload (stop, do not store, report, assess as possible Art. 33 exposure, do not self-clear); the allowlist or read-only wrapper fails to block a mutating or row-returning statement, or the token reaches a project other than the intended one; a result older than a retention period stated in a published legal document, or contradicting one (`docs/legal/`, data-protection disclosure section 2.3(o), GDPR policy); evidence of special-category data or data of a processor or client; answering "which users" would require reading rows; the result would let the runbook state a narrower affected set or change the ciphertext-backup decision; any need to widen, rotate or share the token. **Halt outcome (defined, not improvised):** leave the PR as a draft, commit nothing from Phase 3 beyond the already-pushed probe and suite (remove them with revert commits if the owner so decides), comment on #9927 with a redacted description (no identifier, no payload), and ship series 1 (items 6 and 8b) from the same branch only with the owner's agreement. Probe output lands in the agent session transcript however it is handled: the claim is "not written to any repository file or log", not "not stored anywhere".

1. **Code read first (no production access; the CLO rule that a negative needs a code read).** Record from the repository which Inngest events carry a user reference, with anchors on content: `reminder.scheduled` (`schedule-reminder` route; data is `reminder_id, fire_at, actor:"platform", action`, no user id; `action` may hold a free-text comment body), GitHub action-class events (`founderId, installationId, deliveryId`), `finance.payment_failed` (`founderId`, `customerEmailHash`), `agent.spawn.requested` (`founderId`), routine events (`actor_id`, `delegating_principal`), `email/inbound.received` (sender, recipients, subject). The code read is FINISHED before the runbook sentence is rewritten: the `cron/*.manual-trigger` payloads and the `bot-fix/*` and `vendor/*` events are read, and the result is an event-class table (event, where the user reference sits, user-visible harm if lost, covered by the "all active users" default or not). The default is reworded to cover external correspondents (inbound email senders) and users who are not currently active, and to name the loss horizon. App-log fields: the arming and firing logs carry `reminder_id` only (no user id); Sentry user ids are HMAC-hashed. Log retention: Better Stack Inngest source 90 days (`documented, not measured`, `betterstack-log-query.md`), Sentry 90 days rolling, host journald bounded by size (`SystemMaxUse=1G`), Supabase edge/Postgres logs about 1 to 2 days (#5697). Better Stack log content and whether it carries user ids are NOT inspected beyond this code read.
2. **Write the probe first (RED, then GREEN), `scripts/inngest-history-probe.sh` + `scripts/inngest-history-probe.test.sh`**, registered with an explicit `run_suite "scripts/inngest-history-probe" bash scripts/inngest-history-probe.test.sh` line in `scripts/test-all.sh` (`scripts/*.test.sh` is not auto-globbed). Build on the transport shape of `scripts/supabase-advisor-scan.sh` / `postgrest-reload-schema.sh` and the prior art in `scheduled-inngest-health.yml`; reuse `scripts/lib/bearer-curl.sh` `bc_curl` (confirm with a stub-driven row that its header/body checks accept `--data` with `Content-Type`). Reconciled to the STRICTER bound: the CTO F4 ruling allowed counting recurring jsonb key names; the CLO conditions reject any jsonb operator or key extraction, so the wrapper has NO jsonb access and payload shape is answered by the code read.
   - **Spike first, in the suite's stub and then once live (round 1 step 0):** whether the Management API returns the result of the last result-bearing statement in `begin read only; ...; rollback;` (it may return only the last statement, i.e. `rollback`). The proof of read-only is carried IN the data request: every body's last result-bearing statement selects `current_setting('transaction_read_only') as ro` beside the measurement, and `ro != 'on'` is `could-not-measure(readonly_unverifiable)` (a separate `show transaction_read_only` request is a different transaction and proves nothing). Check the OpenAPI spec for a dedicated read-only query endpoint and prefer it if one exists; confirm that a missing trailing `rollback` cannot leave an open transaction on the pooled connection.
   - **Hostile-environment prologue (first lines of the script):** assert `[[ $- != *x* ]]`; `set +x`; unset `BASH_XTRACEFD SHELLOPTS BASH_ENV ENV PS4 DOPPLER_TOKEN`; pass the literal NAME `SUPABASE_ACCESS_TOKEN` to `bc_curl` and never assign it to a variable; capture the body with `$(...)` only, never a file; send curl stderr to `/dev/null`; map the transport rc to a fixed enum (`credential_refused` is detected by the `SOLEUR_CREDENTIAL_REFUSED` marker, not by rc 2; `xtrace` for rc 78; `transport` for 7 or 28); the child environment after those unsets contains only `SUPABASE_ACCESS_TOKEN`, `PATH` and `HOME`.
   - No caller-supplied SQL; named queries only; every body is `begin read only; set local statement_timeout='5s'; set local lock_timeout='1s'; <query>; rollback;`; project ref pinned in code (`pigsfuxruiopinouvjwy`), any other ref refused; the token is read via `doppler run --only-secrets SUPABASE_ACCESS_TOKEN --` (confirm the flag and the config at work time), sent on curl's stdin config through `bc_curl`, never argv, never printed; a Supabase host pin literal and the `.highwater` adjustment required by `scripts/lint-supabase-deprecated-endpoints.sh` (add its unit suite to verification).
   - Round 1 (all literal): `identity` = sentinel tables `goose_db_version` and `function_runs` exist, no app-owned table present (the 0b/0c shape of `apps/web-platform/infra/inngest-rls/0001_enable_rls_lockdown.sql`), AND a preceding `show transaction_read_only` that must print `on` (if the API response cannot show that result, stop all probing and record `could-not-measure(readonly_unverifiable)`; this also tests whether the API honours `begin read only`); `columns` = table_name, column_name, data_type from `information_schema.columns` for schema `public` (names and types only); `estimates` = `pg_class.reltuples` / `pg_stat_user_tables.n_live_tup` per table (an estimate can support `measured-present` above zero, never `measured-absent`: absence needs a bounded `select exists(select 1 from <t> limit 1)` literal under the timeout, or the result is `could-not-measure`); `time_bounds` = min and max of timestamp columns that `columns` shows are indexed (named literal entries added after `columns` is read, so no dynamic SQL and no `query_to_xml`).
   - Round 2 only if round 1's `columns` shows a typed user-reference column (the post-mortem names `event_user`, `account_id`, `workspace_id`, `worker_ip`; asserted there, NOT verified): number of distinct event names with the cardinality cap first (abort if high-cardinality or names look like they embed an id), counts grouped by event name, non-null counts of the typed user-reference columns, and the status distribution of `function_runs` if a typed status column exists. Each round-2 entry is its own commit with its own test row and CI green before it is ever sent. Never group by or return values of a user, tenant, account or IP column; no `DISTINCT` on them; no row-returning selects.
   - Output formatter: tri-state per question (`measured-present`, `measured-absent`, `could-not-measure(<fixed enum reason>)`, never a response fragment); table/column names must match `^[a-z0-9_]+$`; an event name is printed ONLY if it is in a fixed allowlist built from the step-1 code read (the shape regex and digit/UUID denylist stay as a second check, but a hex id, a hash such as `customerEmailHash`, a slug or a short-digit id would pass them), and every other name collapses into a single `other: N` count and aborts the run when `other` is above zero; SQLSTATE is printed only from a fixed set and no part of any error body is ever echoed; a hard cap on the number of distinct names and on tables applies before anything is printed; counts, timestamps; an unexpected shape, non-2xx, timeout, auth failure, permission error or empty body is `could-not-measure`; the response body never reaches stdout, a log or a file.
   - Suite per Guard 2. If it self-spawns, run it under `TMPDIR=/var/tmp/runner-wk/_temp` as well as the default; run `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater` (not only the per-file mode) before pushing the new `mktemp`.
3. **CI gate before any live read.** Push, then read the owning CI leg (`test`, where `scripts/inngest-history-probe` and `scripts/infra-credentials-loader` are registered) and only when the suite is green run the probe. Guard 2's anchor depends on this order.
4. **Run the probe (production read, owner's go of 2026-10-20).** Round 1, read the output, extend with round 2 entries only per the condition above, each after its own green CI. Record the queries run (text only) in `measurements.md`; no raw output is written anywhere.
5. **Evidence bar for "a usable affected-user list exists" (CTO F4, all three must hold):** (i) a per-user identifier is derivable from surviving rows (non-null count above zero on a typed user-reference column) - the code read shows the user-bearing events carry the identifier inside the JSON event body, which this probe deliberately does not open, so the honest result is expected to be "a candidate source exists, row-level reconstruction untested"; (ii) those rows can be tied to work lost with the store (events received but not completed; the queue and armed events live in Redis, so event history alone does not prove it); (iii) the retention window (oldest row against PA-13 (f), which says no automatic deletion) covers the loss horizon. An event table merely existing is not sufficient. "Complete" is unreachable by this probe by construction, so the recorded class is `partial` or `none`, and the ciphertext backup (1b) stays parked either way; say both explicitly.
6. **Recording (CLO wording, binding).** Runbook "After a total loss: who tells affected users" and ADR-282 "What losing the store costs": replace "Whether a surviving source exists ... is open and tracked in #9927" with the measured finding (old sentence kept under a Superseded blockquote). A positive claim says only "a table or column capable of holding a user reference exists, and N rows are non-null in it"; the negative form is not asserted. Verbatim sentence: "No row, identifier, email, payload, event body or per-user count was selected, printed, logged or stored. Whether any surviving record identifies WHICH users had armed reminders or in-flight jobs was NOT established. Measured on <date> by <method> against project <ref>." The default "all active users are treated as affected" stays in force; the finding can at most add "a candidate source exists/does not exist; narrowing would need an incident-time row-level reconstruction, which was not tested" (separate processing needing its own owner go). Record the evidence class (complete / partial / none). The ciphertext backup stays parked and the runbook says no second un-erasable copy of identifying payloads may be created before an Art. 17 retention and erasure design exists. If the finding is per-user payloads with no automatic deletion and neither #7779 nor #8528 covers the Postgres history, file the storage-limitation / Art. 17 issue now (CLO), else link them.
7. **Register and posture (CLO conditions).** Amend Article 30 PA-13 (f) and PA-27 (f) in-cell with the measured oldest-row date and counts, with a `> **Superseded <date> (#9927): ...**` marker under each superseded sentence, and the same marker in every sibling cell/file that repeats the statement (PA-14, PA-21, PA-22, PA-31, the ADR-282 sentence, the runbook sentence): list them with ONE `grep` over `knowledge-base/legal/` and `docs/legal/` and record the count in the PR body. Add a dated one-line entry to `knowledge-base/legal/compliance-posture.md`. Compare the result with `docs/legal/` (data-protection disclosure section 2.3(o), GDPR policy): a contradicted published statement is a stop-and-go-to-owner. Cite register cells by cell name and function name, never by line number.
8. `soleur:gdpr-gate` runs against this plan and again at work Phase 2 exit (a regulated-data surface by the ruling above even though no schema or route is edited).

### Phase 4 - verify, ship

1. **CI order and the owning legs.** After the FIRST push of the new/changed suites, read the owning legs BEFORE spawning review seats: the `test` check (test-scripts) owns `scripts/infra-credentials-loader` and the new probe suite (they are registered in `scripts/test-all.sh`, NOT under `apps/web-platform/infra/`); `deploy-script-tests` (suites derived from `apps/web-platform/infra/**.test.sh`, ADR-252) owns `workspaces-luks-cutover-workflow.test.sh` and runs when `.github/actions/infra-credentials/action.yml` or `apps/*/infra/**` changes. If M8b.1 stopped 8b, no `.github/` edit is made and only `test` runs. A red leg blocks review-seat spawning until green. Use Monitor for waiting on CI, never a chained sleep.
2. Never edit tracked files while a `test-all.sh` battery runs on the tree; stop a stuck local battery with `source plugins/soleur/scripts/lib/proc.sh && kill_mine test-all.sh`, never `pkill -f`.
3. Run `bash plugins/soleur/test/c4-count-parity.test.sh`, `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater`, `bash scripts/lint-supabase-deprecated-endpoints.sh` and its suite, the touched suites, and the C4 file re-read recorded in the ADR section. Re-run the Phase 0 step 1 diff after the final rebase.
4. Write the ADR-241 amendment-log entry and the ADR-282 addendum, the runbook edits and the PR body. **PR body** includes a MEASURED / NOT MEASURED table with dates and the evidence class per row (items 6, 8b, C1), the caller table (job, environment, transitive Hetzner need), the rulings (links to `decision-challenges.md`), `Ref #9927` and `Ref #10112` (no closing keyword), the deferred issues filed in Phase 0, and the statement that nothing was written to Doppler, Hetzner or Supabase.
5. Post-merge: nothing is deployed by this PR (no runtime code). Confirm the next scheduled drift run is green (`gh run list`) and that the loader annotation reads `source=tier_b`.

## Files to Edit

- `.github/actions/infra-credentials/action.yml` (legacy-arm single read, verdict, header comments)
- `.github/actions/infra-credentials/infra-credentials.test.sh` (rows 1c, 1d, auth-error case, Guard 1 harness rows, extraction markers)
- `.github/workflows/infra-validation.yml` (step "Tier-A plan credentials (bounded substitutes)" only, after M8b.1)
- `.github/workflows/workspaces-luks-cutover.yml` (cutover job volume-id lookup only, after M8b.1)
- `.github/workflows/scheduled-terraform-drift.yml` (two echoed blocks and their prose in the two orphan-sweep issue filers)
- `apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh` (stub and the `readonly_absent` refusal)
- `plugins/soleur/test/token-drift-workflow-causes.test.sh` (fence rows)
- `tests/scripts/test-infra-privileged-tier-census.sh` (delete `RO_FIRST`, invert M-g1-g2, caller-invariant row, site B coverage, mutation rows)
- `scripts/test-all.sh` (one `run_suite` line for the probe suite)
- `scripts/lint-supabase-deprecated-endpoints.highwater` (only if the new script requires it)
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` (addendum plus three Superseded blockquotes)
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md` (one amendment-log entry)
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` (Route A row, "After a total loss" section)
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (fallback rows, O5/O10 notes, consumer inventory)
- `knowledge-base/legal/article-30-register.md` (PA-13 (f), PA-27 (f), sibling markers) and `knowledge-base/legal/compliance-posture.md` (dated entry)
- `knowledge-base/operations/expenses.md` (Doppler row, tier only, only if falsified) and `plugins/soleur/skills/admin-ip-refresh/SKILL.md` (only if M8b.1 contradicts its sentence)
- `knowledge-base/engineering/architecture/diagrams/model.c4` / `views.c4` (only if the work-time C4 decision adds the one edge)

Path check (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above was verified with `git ls-files` on 2026-10-20 except the two new scripts and the `.highwater` adjustment (conditional); `scripts/*.test.sh` registration is explicit (verified in `scripts/test-all.sh`).

## Files to Create

- `scripts/inngest-history-probe.sh` (closed-allowlist read-only probe wrapper, with a `SOLEUR-DEBT:` retire marker)
- `scripts/inngest-history-probe.test.sh` (Guard 2 suite; stubbed `curl`/`doppler`, no network)
- `knowledge-base/project/specs/feat-one-shot-9927-inngest-luks-items-6-8b-c1/measurements.md` (query text run, dates, tri-state results; names, counts and timestamps only)

## Acceptance Criteria

### Functional

- [ ] M8b.1 recorded with date as a three-way verdict (listed / absent / could-not-measure) for `HCLOUD_TOKEN_READONLY` and for `HCLOUD_TOKEN`. If not listed, no file under `.github/` or `tests/` is edited and the PR body says so.
- [ ] The RED suite commit exists alone and its SHA plus the failing rows (1c, 1d, the new census rows) are cited in the PR body; the loader suite passes at the GREEN commit: `bash .github/actions/infra-credentials/infra-credentials.test.sh`.
- [ ] `git grep -nE "READONLY HCLOUD_TOKEN|secrets get HCLOUD_TOKEN( |$)" -- .github scripts/lint-supabase-deprecated-endpoints.sh` shows no bare read/write read in `action.yml`, `infra-validation.yml`, `workspaces-luks-cutover.yml`, or the two echoed drift blocks; the only remaining hit outside tests is `scripts/cutover-inngest.sh` (site C, named in its follow-up).
- [ ] The census has no `RO_FIRST` and G1g is strict; M-g1-g2 is RED-expected; the caller-invariant row has a floor and a mutation row.
- [ ] Item 6: ADR-282 addendum and the runbook Route A row state tier, rollback scope and retention each with an evidence class and a date; no value, diff or version content appears in any committed file.
- [ ] Item C1: the runbook and ADR-282 carry the measured finding with the CLO did-not-inspect sentence verbatim and the evidence class; the "all active users" default is still present; PA-13 (f) / PA-27 (f) carry Superseded markers; `compliance-posture.md` has the dated entry; the register sibling count is in the PR body.
- [ ] Leak tripwire over ADDED lines of every changed file (not only `measurements.md`): `git diff -U0 origin/main...HEAD | grep '^+' | grep -v '^+++ ' | grep -nE 'dp\.[a-z]{2,5}\.[A-Za-z0-9]|sbp_[A-Za-z0-9]|sb_(secret|publishable)_|eyJ[A-Za-z0-9_-]{10,}|[A-Za-z0-9]{40,}|[0-9]{6,}|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}'` returns nothing except documented benign strings listed in the PR body (cited commit SHAs, run ids, volume ids already public in the repo); the SAME regex is run over the PR body, every issue body and the halt comment before posting.
- [ ] The runbook event-class table exists and covers every Inngest event family read in the code read (including `cron/*.manual-trigger`, `bot-fix/*`, `vendor/*`), and the "all active users" default is reworded as above.
- [ ] Route A text in every mention swept by the Phase 1 `git grep` follows the Route A rule (available only when measured paid, scope documented, oldest-entry age meets the stated horizon).
- [ ] Incident-response jobs are tagged in the PR caller table and the census invariant row asserts each declares a Tier-B environment; the break-glass runbook row exists.

### Non-functional

- [ ] No Doppler, Hetzner or Supabase write was issued: the transcript's Doppler/Supabase commands, listed in the PR body, contain none matching `secrets get|secrets download|doppler run|--debug|configs logs rollback` against `soleur-inngest`, and none of `secrets set|delete`, `-X PUT|DELETE`.
- [ ] The probe suite passes under the default `TMPDIR` and under `TMPDIR=/var/tmp/runner-wk/_temp`; `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater` passes.
- [ ] `gh pr view 10652 --json body` contains `Ref #9927` and no `Closes`/`Fixes`/`Resolves` keyword; #9927 is still OPEN after merge.
- [ ] `soleur:gdpr-gate` ran against the plan and at work Phase 2 exit; Critical findings (if any) filed per its rule.

### Quality gates

- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` green and the three `.c4` files re-read with the enumeration cited in the PR; the PR states that parity proves cardinalities, not the actor reasoning.
- [ ] CI legs `test` and (when `.github/` or `apps/*/infra` changed) `deploy-script-tests` read after the first push, before any review seat was spawned; the probe was run only after its suite was green in CI.
- [ ] Review seats include `security-sentinel`, `user-impact-reviewer` (threshold `single-user incident`), `observability-coverage-reviewer` and `test-design-reviewer`.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | Legacy arm, only `HCLOUD_TOKEN` present | rc 0, `::error` verdict `legacy_hcloud_readonly_absent` naming `privileged_source_missing`, nothing exported, `HCLOUD_TOKEN` never requested (row 1c) |
| T2 | Legacy arm, read-only token present and rw token present, distinct sentinels, metacharacters | read-only value exported via heredoc, rw sentinel absent from env file and read log (must-pass) |
| T3 | Legacy arm, Tier-A token rejected by Doppler | rc 0, verdict `legacy_token_unauthorized`, not reported as a missing secret |
| T4 | Neither token present | same absence verdict as T1, rc 0, no empty `HCLOUD_TOKEN` export |
| T5 | Tier-B arm (token present) | unchanged behaviour: no Tier-A reads (row 1e) |
| T6 | Restore the old loop (mutation 1) | rows 1c and strict G1g go RED |
| T7 | Site B / site D with an empty read-only token | the step fails with a named message before any request; no read/write read |
| T8 | Probe: unknown query name / other project ref | rc 2 / refused, zero requests |
| T9 | Probe: stub returns an email-shaped, UUID-shaped or long-digit string | nothing printed from the body, non-zero exit |
| T10 | Probe: HTTP 500, timeout, empty body, missing `show transaction_read_only` | `could-not-measure(<enum>)`, never a zero |
| T11 | Probe: parseable zero plus positive control | `measured-absent` only then; an estimate only supports `measured-present` |
| T12 | Drift issue filer bodies | both echoed blocks use the read-only name, no bare fallback, prose reworded |
| T13 | Fixture tree where one loader job drops its `environment:` key | caller-invariant row RED |

## Dependencies & Risks

- **O10 / non-emptiness unknown until M8b.1** (a names listing cannot show an empty value, and it runs under the operator's identity): corroborated by identity-matched log greps and the sole-copy job's recent conclusion; a read-only token that exists but is empty makes sites B and D fail their own step and the legacy arm print its verdict, which is the intended behaviour but would block PR plans, hence the gate.
- **Legacy arm also means "environment secret missing"**: the verdict names `privileged_source_missing` first so the operator is not sent to mint a Hetzner token.
- **Supabase personal access token is account-wide**: mitigated by the wrapper, `--only-secrets`, the identity preflight and the pinned ref; durable fix is a follow-up (project-scoped role).
- **`begin read only` honoured by the Management API is unverified**: the preflight tests it (`show transaction_read_only` must be `on`, else probing stops); the allowlist is the real guard either way.
- **`doppler configs logs --json` may carry a `diff` field with values**: key names first, `2>/dev/null`, only timestamps leave the pipe; if safe extraction cannot be proven the item records `could-not-measure`.
- **C1 may legitimately end `could-not-measure` or "candidate source, untested"**: a valid recorded outcome, not a failure; "complete" is unreachable by construction.
- **Doppler tier may be the free plan**: falsifies the "paid tiers" premise of Route A. Recording is in scope; changing the plan is money (owner).
- **The probe's production reads have a load cost on the Inngest history database**: bounded by 5 s statement and 1 s lock timeouts, estimates instead of full scans, and indexed-column min/max only.
- **Deferred issues** (Phase 0 step 2) are the only place the cut items live; none is silently dropped.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, unfilled or missing its threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident` and carries the CPO sign-off line.
- A fallback removed from the loader but left in a sibling reader re-opens the read/write path; Guard 1 names sites A, B and D, and site C is a named, ticketed, UNSCANNED exception (the census reads workflow run bodies only).
- A test asserting "the read log has no `HCLOUD_TOKEN`" is vacuous if the stub cannot see the read; the Guard 1 harness row forces the negative control.
- jq error messages can quote fragments of the value being indexed: every Phase 1 and Phase 2 `jq` discards stderr.
- Do not merge probe output into any committed file beyond counts, timestamps and names; the added-lines tripwire in the acceptance criteria is the check.
- Cite code and register cells by content anchor (function name, cell name, constant), never by line number (`cq-cite-content-anchor-not-line-number`); this plan quotes line numbers only inside rulings copied from the CTO agent.
