---
title: "chore: record the 2026-11-06 owner decisions on the sole-copy LUKS epic, refresh the Hetzner-project A6 draft, design the arm-token replacement path (Ref #9927)"
date: 2026-11-06
slug: record-owner-decisions-a6-refresh-9927
branch: feat-one-shot-9927-record-owner-decisions-a6-refresh
issue: 9927
ref: [9927, 12158]
closes: none
type: chore
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore: record the 2026-11-06 owner decisions, refresh the Hetzner-project A6 draft, design the #12158 write path

Ref #9927 and Ref #12158. This PR never uses a closing keyword for either issue (the epic stays open).
Spec lacks a valid `lane:` (no spec.md exists for this branch) - defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-06
**Research agents used (plan and deepen passes):** repo-research-analyst, learnings-researcher, CTO (three calls), CLO (two calls), CPO, the five-seat plan-review panel (code-simplicity, DHH lens, Kieran, architecture-strategist, spec-flow), and a sharp-edges verification agent that read the whole catalogue. The deepen pass did not fan out a second 40-agent sweep: this is a docs-and-evidence plan with one small probe script, every axis was already ruled by a domain leader, and no framework or library documentation is involved (Context7 and web research skipped on purpose).

### Key improvements

1. The write-token delivery was corrected twice by repo evidence (shared Tier-B loader exposure -> `inngest-cutover` environment secret, D1b; Terraform-declared token, D1c).
2. The revisit probe was simplified to a date-only config check after two reviewers showed its comment read could never fire (trusted-verdict marker shape, missing `GH_TOKEN`) and the CTO amended D3 (D3-r1).
3. The A6 draft's old agent-written statement block is deleted rather than kept next to the empty owner field (CLO L1-r); the file keeps its name until the signing event (CLO L1 dissent, row O8).
4. Acceptance Criteria now carry runnable commands, a pre-merge and a post-merge split, and a wording gate whose regex cannot match `unsigned`.

### New considerations discovered

- #10136 was closed today; links go to #10382 plus a SHA-based permalink comment on #10136.
- A queued or ejected merge must post no comment; every comment carries an idempotency marker.
- The sweeper refuses a non-executable probe before it checks `earliest=`.
- The registration surface of a new suite includes `scripts/lib/test-affected-paths.sh` (a suite-path entry beside the `zot-soak-6122.test.sh` line and a `glob:` anchor row), or the PR falls back to the full battery.

### Deepen-pass verification (live, 2026-11-06)

Gates 4.6 (User-Brand Impact present, threshold valid), 4.7 (Observability 5-field block added; the scripts and knowledge-base paths make the gate apply; probe command `git ls-files -s scripts/followthroughs/arm-token-revisit-*.sh` expects `100755`), 4.8 (no PAT-shaped match), 4.9 (no UI surface), 4.10 (no store or connection introduced), 4.11 (`lint-guard-contract.py` exit 0), 4.12 (one unfenced `## Scope Check`), 4.13 (not triggered) pass. Live checks: labels `follow-through`, `priority/p3-low`, `type/chore`, `domain/engineering`, `deferred-scope-out` and milestone `Post-MVP / Later` exist; PR 12210 MERGED; #12158, #12218, #8881, #7942, PR 12219 OPEN; commit `b959fe4b84` exists (the last edit of the A6 draft, a SHA candidate for the replacement note; step 2.4 re-derives it from `git log --follow`); rule ids `cq-write-failing-tests-before`, `wg-when-deferring-a-capability-create-a`, `hr-weigh-every-decision-against-target-user-impact` are active in `AGENTS.md`; `scripts/lint-orphan-test-suites.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/suite-shard-legs.tsv` and `scripts/ci-pr-affected-audit.accept.tsv` exist; `bun test plugins/soleur/test/terraform-target-parity.test.ts` printed 365 pass, 0 fail.

## Overview

A docs-and-evidence run for the Inngest sole-copy volume epic (volume `106903269`, ADR-282). Four things, nothing else:

1. **Records six owner asks** (rows O1 to O7 and O9) given in session on 2026-11-06 (each matching a same-day CTO ruling) in an ADR-282 addendum and in `decision-challenges.md`, with the label "owner decision given in session 2026-11-06 (relayed by the agent; not a signed record)".
2. **Refreshes the unsigned Hetzner-project A6 draft** (`knowledge-base/legal/audits/2026-10-30-inngest-a6-no-known-access-record.md`): new dated read-only evidence, corrected A5 and Hetzner-answer cells, the CLO's claim limits, the owner's sentence field left empty. The agent never drafts, signs or attests.
3. **Writes the #12158 design** (replacement write path for `op=rollback` and `op=resume`, flip-read to Tier B, arm-token revoke sequencing) as a design doc. No revoke, no workflow, Terraform or host change.
4. **Closes the loops the rulings opened**: Superseded markers on the live G2e "sunset" text (CTO D5), and a notify-only follow-through probe so the 2027-01-08 arm-token revisit cannot be forgotten (CTO D3/D4, amended by D3-r1 to D3-r3).

Held, not authorised here: dispatching `apply_target=inngest-host-replace`; revoking, scoping or deleting the arm token; any write to Hetzner, Doppler or Better Stack; closing #9927, #12158, #12213 or #11265. Qa for this docs change is the scripted checks in Acceptance Criteria plus the probe suite; there is no UI to browse.

## Research Reconciliation - Spec vs. Codebase

| Brief says | Reality (checked 2026-11-06) | Plan response |
|---|---|---|
| Rename the A6 draft to the signing date | CLO dissent (L1): a date-named file with status `draft-unsigned` reads as a record of a signing that has not happened; the file's own text ties the rename to the signing event | Keep the file name; add `refreshed: 2026-11-06`; the rename plus every inbound link is one commit at signing. No conditional rename in this run (a pipeline run has no owner turn). Row O8 |
| "New dated console re-read via read-only means" | Members, roles, two-factor and API tokens are console-only (ADR-282 addendum 2026-10-28). `HCLOUD_TOKEN_READONLY` exists in Doppler `soleur/prd_terraform` (names listed) and can read the volume and server list only | Separately headed "API read" section; 2026-10-29 console figures kept as the last console read; the console re-read cell is `PENDING`, filled only by the owner |
| A5 cell | The draft's A5 cell (dated 2026-10-31) says "no". A5 is recorded complete on #10136: `S5-A5-DONE` 2026-11-02T14:28:00Z (agent-posted at owner delegation) and `S5-A5-RELAYED` 2026-11-02T21:51:04Z; it covers the dedicated key pair only; the CLO re-assessment for the other exposed keys is due 2026-11-08 | Update the cell with links and the scope limit; old text stays under a `Superseded 2026-11-06` marker |
| Hetzner-answer cell | Support reply received 2026-11-02 (#9927 comment 6577564178) | Update the cell with a paraphrase (no quotation marks) and the link; add the three claim limits |
| Reconciliation note: trackers #10382 and #10136 link the 2026-11-02 keys record, and name neither the Hetzner draft nor its future signing-date name | - | Links added as described |
| Old agent-written "Statement (to be adopted by the owner)" block | Plan-review finding; CLO L1-r amends L1 to deletion | Delete the block with a one-line replacement note (git SHA from `git log --follow`); the 2026-11-02 banner and any other inbound mention get a `Superseded 2026-11-06` marker. Its claim-limit content must survive in "Claim limits" |
| "Links from the A5/A6 tracker issues" | #10382 open; #10136 closed 2026-11-06T07:58Z; #11218 closed. No tracker names either A6 record | One pre-merge comment on #10382 (the CLO's attestation-readiness conditions, with the PR link); one post-merge link comment on #10382 and on #10136 with a commit-SHA permalink; none on #11218; no `S5-` or `S6-` token in any of them |
| #12213 re-check after the pin bump | Cause is pin drift in `cloud-init-inngest-bootstrap.test.sh` (pin v1.1.68 vs tag v1.1.69). The failing Main Health Monitor run is on `7e5c496ceb`; bump PR 12210 merged 06:02:18Z; #12213 (06:44Z) has no comments | Precondition; re-check read-only; predicate = a Main Health Monitor, merge-queue or dispatch run on a main SHA containing 12210 is green; push-run greens are not evidence; the agent never closes it |
| "ONE comment on #9927" | CTO D5 requires supersession of two older #9927 comments (6614866201, 6620352154), never an edit | The one comment carries the decisions and supersedes both by link |
| G2e "no sunset" | Live sunset text in five places (CTO D5) | Append markers only; archived plans and specs stay |
| Flip-read to Tier B | ADR-282 addendum 2026-11-05 says Tier-B delivery of the read token is "rejected for now" and ends "It is the direction #12158 takes for the write credential" | CTO D2 orders flip-read after the window; D1b moves the write credential to an environment secret. The marker covers both clauses |
| Probe naming `REVISIT-DECISION:` read through trusted-verdict | `scripts/lib/trusted-verdict.sh` accepts only `RESULT:` and `S<n>-...:` lines; a gh read needs a declared `GH_TOKEN` | Replaced by the date-only probe of D3-r1 |

## Research Insights

**Premise validation.** `gh` checked: #9927, #12158, #12213, #10382 OPEN; #10136, #11218, #11215, #9786 CLOSED; #8528, #7671 OPEN. Draft PR 12219 is the only open change naming #9927; PR 12218 (`feat-one-shot-10112-inngest-residuals`, no files yet) may append to ADR-282, so the addendum is append-only and re-fetched before commit. No rejected ADR alternative is reinstated (the "keep, revisit by date" and "pin permanently" mechanisms are ADR-282's own).

**Property List.**

1. Every owner ask of 2026-11-06 is recoverable from the repo with its class, source label and status word, and none reads as a signed or attested record.
2. The A6 draft carries current, correctly dated evidence and stays visibly unsigned, with the owner's sentence field empty.
3. The #12158 design states, as an ordered sequence with checkable preconditions, how the arm token can be revoked without losing the only recovery verbs.
4. The 2027-01-08 arm-token revisit fires without anyone remembering it.
5. No repo text states a G2e sunset without an adjacent `Superseded 2026-11-06` marker (the two older #9927 comments stay as history and are superseded by link).
6. No production, infrastructure or issue-closing action occurs.

**Cut List.** Rename of the A6 draft in this run (property 2 is served without it; L1). A new ADR (the decisions extend ADR-282). A standing flip-read canary (tracked in #12158). Any runbook edit (rows A5/A6 are not falsified). Auto-revoke on the revisit date (CTO D4). The probe's comment read, `GH_TOKEN` and trusted-verdict dependency (D3-r1).

**Learnings that bind a step.** `2026-11-04-a-live-red-proof-has-no-free-baseline-...md` (state each claim as it is; ruling rows only after a same-session spawn; a PreToolUse hook blocks heredocs quoting the Doppler secret-write command, so name it by role); `2026-10-18-sole-copy-drift-check-fixes-were-the-least-audited-surface.md` (bound every external call with `timeout`; rc 124/137 is "could not read", never "no token"); `2026-08-02-the-retraction-pr-was-itself-over-claiming-...md` (an attestation binds to the final committed text; re-check after a rebase); `2026-10-24-credential-tier-cutover-invalidates-recipes-asymmetrically.md` and `2026-07-17-workflow-env-gate-references-unprovisioned-environment-auto-approves.md` (verify write paths; provision any environment in the same change). Others read and not binding here: the user_data gzip-render measurement, the `git tag --merged` shallow-clone caveat for the #12213 selector, the umbrella-stays-open pattern.

**Domain leaders consulted** (outputs are the rows of `decision-challenges.md`): CTO (D1 to D6, D1b, D1c, D3-r1 to D3-r3), CLO (L1 to L4, L1-r), CPO (sign-off below). Plan review ran the five-seat panel (simplicity, DHH lens, Kieran, architecture, spec-flow); findings that contradicted a ruling were batched to the CTO and CLO in one call each; the rest are applied below. The relevance-gated named panel was not re-spawned: CTO, CLO and CPO had already ruled on every axis it covers.

**Repo facts the design rests on.** The arm token is consumed by `scripts/cutover-inngest.sh` arms `rollback)` (reads the flag, writes `INNGEST_CUTOVER_FLIP=rollback`, deletes `INNGEST_HEARTBEAT_URL`) and `resume)` (reads, writes `flushed`), transported by the step "Export Inngest arm token (gated ops only)" in `.github/workflows/cutover-inngest.yml`; mint and `-target` lines in `.github/workflows/apply-web-platform-infra.yml`. The flip-read token is consumed only by the step "Preflight - inherited-done check, fails closed on a blind instrument" of job `inngest_host_replace` (already `environment: infra-privileged`). `inngest-arm-write-token.tf` also defines `github_repository_environment.inngest_cutover` and `github_repository_environment_deployment_policy.inngest_cutover_main`, which gate op=backup, rollback and resume. `cutover-inngest.yml` has one job whose job-level `environment:` expression covers all three, so "the write token and the loader never share a job" holds per dispatch only; the existing ternary shape `(inputs.op == 'rollback' || inputs.op == 'resume') && secrets.X || ''` is the pin. Doppler tokens are config-scoped (`git-data-luks.tf`, `kb-drift.tf`, ADR-282 addendum 2026-11-05); no per-key scope is evidenced. The sweeper (`scripts/sweep-followthroughs.sh`) refuses a non-executable probe before it checks `earliest=`, and skips a tracker before `earliest=` is reached.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A6 Hetzner-project \"no known access\" record: owner will sign now, in their own words. Agent refreshes the draft-unsigned record" [brief 1] | Phase 2 | mapped |
| 2 | "rename to signing date" [brief 1] | Phase 2 (no rename; O8) | descoped - justification: CLO dissent L1; the draft's own text ties the rename to the signing event |
| 3 | "links from the A5/A6 tracker issues" [brief 1] | Phase 6 (6.2, 6.4) | mapped |
| 4 | "leaves the owner's sentence EMPTY. Never draft or sign it." [brief 1] | Phase 2 step 2.4; AC 2 | mapped |
| 5 | "Off-project ciphertext copy: owner funds it in principle. Build waits on CLO conditions ... Record only; build nothing." [brief 2] | Phase 1; rows O2, R4, L2 | mapped |
| 6 | "Host replace: owner approves PLANNING one bundled window. Not authorized to dispatch apply_target=inngest-host-replace" [brief 3] | Phase 1, Phase 3; rows O3, O4, R3, D6 | mapped |
| 7 | "Arm token: KEEP, revisit at next replace or 2027-01-08 at the latest. Do not revoke, scope or delete" [brief 4] | Phases 1, 5; rows O6, R1, D3, D4 | mapped |
| 8 | "G2e pin: KEEP permanently; no sunset." [brief 5] | Phase 4; rows R2, D5 | mapped |
| 9 | "Epic: stays open; closes only after the replace window and the CTO's listed conditions" [brief 6] | Phase 1; AC 11; rows O7, R6 | mapped |
| 10 | "record these decisions and rulings durably (ADR-282 addendum ... and a decision-challenges.md ...)" [brief a] | Phase 1; `decision-challenges.md` | mapped |
| 11 | "a plan step for ONE comment on #9927 stating the owner's decisions using Ref, never Closes" [brief a] | Phase 6 step 6.1 | mapped |
| 12 | "the A6 evidence refresh above (read-only means only ...) otherwise leave a clearly marked pending cell and file nothing; never a production write" [brief b] | Phase 2 steps 2.1 to 2.3 | mapped |
| 13 | "the design work for #12158 only (replacement write path for rollback/resume, flip-read to Tier B, then arm-token revoke sequencing), design doc/plan only, no revoke and no infra change" [brief c] | Phase 3 | mapped |
| 14 | "Seat dissents to batch to the CTO in one call: security seat (hard revisit date on arm token), simplicity seat (favors removing G2e)" [brief] | Plan phase: one CTO call, rows D4 and D5 | mapped |
| 15 | "Main-broken P1 issue #12213 re-check after the pin bump" and the other preconditions [brief 3] | Phase 3 step 3.4; Phase 6 step 6.5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1: ADR-282 addendum | asks 10, 5, 6, 7, 8, 9 | asked |
| Phase 2: A6 draft refresh | asks 1, 4, 12 | asked |
| Phase 3: `arm-token-replacement-design-12158.md` | ask 13 | asked |
| Phase 4: Superseded markers | ask 8 "KEEP permanently; no sunset." | asked |
| Phase 5: revisit tracker, probe, its suite and registration rows | ask 14 "security seat (hard revisit date on arm token)" | inferred - justification: the CTO upheld the security seat's dissent (row D4) only with this mechanism as the compensating control; without it the hard date is prose and the epic condition "arm-token decision recorded with the follow-up tracker carrying the rest" has no carrier |
| Phase 6: GitHub comments (#9927, #12158, #10382, #10136) | asks 3, 7, 11 | asked (the #12158 amendment is CTO D3) |

### Split Assessment

- Subsystems touched: 3 - `knowledge-base`, `scripts`, `plugins`
- Planned files: 12 | Estimated changed lines: about 650 (ADR addendum about 110, design doc about 150, A6 draft about 120, probe and suite about 150, markers and registration about 40, spec files about 80; rulings are pointed to by row id, not recopied)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the brief asks for one merged PR). If probe registration needs more than the rows listed in Files to Edit, split the probe into its own PR and leave the tracker un-enrolled until it lands.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (sign-off only)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rows D1 to D6, D1b, D1c, D3-r1 to D3-r3 in `decision-challenges.md`: write path (a) is a Terraform-declared read/write token delivered as an `inngest-cutover` environment secret read only by rollback and resume (D1b and D1c amend D1's delivery); order replace -> write path -> flip-read to Tier B -> revoke change, only docs before the window; the security seat's dissent upheld with the revisit probe as the compensating control; the simplicity seat's dissent not upheld (G2e kept permanently); the precondition list completed.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Rows L1 to L4 and L1-r: evidence presentation and the empty sentence field; the old statement block is deleted with a replacement note; "funded in principle" is record-only with build conditions C1 to C11; a banned-words list and the exact label; three claim-limit paragraphs. Dissent: no rename in this run. Attestation is not part of this run.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO sign-off: **yes with conditions**, all encoded in Acceptance Criteria: pinned vocabulary and prohibited words; the A6 draft keeps "unsigned, owner sentence pending"; #9927 and #12158 stay open; no user-facing file in the diff; customer-facing wording is "queue and run state is held on a single volume with no off-project copy", recoverability after a project or account loss is "not established".

## User-Brand Impact

**If this lands broken, the user experiences:** a record that reads as signed, attested or backed up when it is not, so that the owner or a reviewer believes the queue and run state of every user's scheduled agents has a safety net it does not have; or an epic read as closed while the volume still has no off-project copy.
**If this leaks, the user's data is exposed via:** nothing in this change handles user data or a secret value. The ADR addendum states the standing exposure of the read/write arm token in words only; the Hetzner API read prints no token and no identifier beyond the volume id already public in the repo.
**Brand-survival threshold:** single-user incident

(Carried from ADR-282's frontmatter. `soleur:engineering:review:user-impact-reviewer` runs at review time.)

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-282 with `## Addendum - 2026-11-06 (#9927 owner decisions, items 1b, 4, 8, 10)`: appended, no new ordinal, status stays `accepted`, nothing above edited except dated `Superseded` markers (below). Statements are tied to the merge ("on the merge of PR 12219 this addendum records ...") and are not in the past tense for the PR's own effects. ADR-241 fit (stated in the design doc): `inngest-cutover` is one of the four Tier-B environments, so D1b conforms to D2 and removes the advisory deviation the repo-scoped arm and flip-read secrets carry; D3 is not engaged (same reasoning as the 2026-11-05 addendum); the ADR-241 amendment-log entry belongs to the build PR.

### C4 views

No C4 change. Checked against `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4` and `spec.c4`: (a) external human actors - `founder` and the Hetzner project members are modelled or out of the model by design; none added. (b) External systems - `hetzner`, `inngest`, `inngestRedis`, `doppler`, `github`, Better Stack are modelled; the off-project copy has no provider chosen and nothing is built, so there is nothing to add until the PR that builds it. (c) Data stores - `inngestRedis` already carries the sole-copy and LUKS text and the token-holder overwrite residual; nothing here falsifies it. (d) Actor-surface relationships - `founder -> doppler` and `founder -> github` approval edges exist and are unchanged. The build PR for the new token and environment secret revisits the `doppler` and `github` descriptions.

### Sequencing

The decisions are true now (recorded). The build steps they describe (write path, Tier-B flip-read, revoke, off-project copy) are future changes recorded as such.

## Guard Contract

### Guard 1 - arm-token revisit probe (the probe's own guard; not ADR-282's Guard 1)

**Property.** `scripts/followthroughs/arm-token-revisit-<N>.sh` exits 5 (ACTION REQUIRED) whenever any of the line `-target=doppler_service_token.inngest_arm_write`, the line `-target=github_actions_secret.doppler_token_inngest_arm` (both in `.github/workflows/apply-web-platform-infra.yml`) or the declaration `resource "doppler_service_token" "inngest_arm_write"` (in `apps/web-platform/infra/inngest-arm-write-token.tf`) is present, exits 2 ("targets gone") only when none of the three is, exits 3 when either file is unreadable, and can never exit 0 or 1.

**Assembly.** The probe script (executable, mode 100755); the sweeper that maps exit codes and refuses a non-executable probe (`scripts/sweep-followthroughs.sh`); the directive in the tracker body (unfenced, column 0, `script=... earliest=2027-01-08T00:00:00Z`); the three members above (a probe that stops at the first is the defect); the suite `scripts/followthroughs/arm-token-revisit-<N>.test.sh`; its registration surfaces `scripts/test-all.sh`, `scripts/suite-shard-legs.tsv` and `scripts/lib/test-affected-paths.sh`. The probe holds no credential and calls no network or `gh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the exit-5 branch with exit 2 (all three members present) | RED |
| 2 | Empty the suite's case list so it reports 0 cases and exits 0 (the probe suite's own dispatch) | RED (case-count floor) |
| 3 | Probe checks only the token `-target` line: fixture with only the secret `-target` line present | RED (must still be exit 5) |
| 4 | Probe checks only the two `-target` lines: fixture with only the resource declaration present | RED (must still be exit 5) |
| 5 | Probe exits 0 or 1 on any branch | RED (exit-set assertion {2,3,5}) |
| 6 | Unreadable file mapped to exit 2 or 0 instead of 3 | RED |
| 7 | Remove the exit-2 "targets gone" branch (falls through to 5) | RED |

**Harness rows.** Delete one case from the suite -> the case-count floor goes RED. Must-PASS non-canonical inputs (the contract permits them): the two `-target` lines in the other order with a trailing comment and CRLF endings -> still exit 5; a fixture where the only remaining text is a commented-out `# -target=...` line and no declaration -> exit 2 (comments are not members). The probe is committed with mode 100755 and the suite asserts it. Comment pointers in `scripts/lib/test-affected-paths.sh` to line numbers of `terraform-target-parity.test.ts` are comment-only and may drift by one after Phase 4.

**Anchor.** None: the probe compares no stored value; it reads two tracked files on every run. Residuals, stated in the probe header and the tracker body: it measures config and not Doppler (a destroy never applied is carried by #12158 step 4 and the owner); the "next host replace" half of the revisit trigger is carried by #12158 step 4 and prose only; revocation stays a human act.

## Acceptance Criteria

Status words are the CPO set: `decided`, `funded in principle, no spend committed, build gated`, `planning only, not dispatched`, `kept, revisit trigger`, `pinned permanently`; never `done` or `closed` for a decision.

### Pre-merge (PR)

1. Wording gate. `git diff origin/main...HEAD -U0 -- knowledge-base | grep -E '^\+[^+]' | grep -inwE 'signed|owner-signed|attested|approved|discharged|verified|confirmed|protected|funded|compliant|durable|safe' | grep -viE 'unsigned|not a signed record|no attestation|in principle, no spend committed'` plus `... | grep -inE 'approved by|no access|backed up|recoverable|DPA in place'`; word boundaries keep `unsigned`, `designed` and `fail-safe` out. Every surviving hit is a negation, a pointer to the 2026-11-02 keys record, the banned-word list itself, or a ruling row quoting the CLO list; the surviving count and each hit's justification are in the PR body.
2. The A6 draft keeps `status: draft-unsigned`, adds `refreshed: 2026-11-06`, keeps its file name, gains directly under its H1 the visible line `unsigned, owner sentence pending` (`grep -c 'owner sentence pending'` prints at least 1; it is not in the draft today), and has an "Owner's own sentence" section whose only content is `[EMPTY: only the owner's words, with a provenance block, per the 2026-11-02 route]`. The old "Statement (to be adopted by the owner)" block is gone (`grep -c 'Statement (to be adopted by the owner)'` on the file prints only the superseded-banner mention or 0), replaced by the CLO's one-line note with the SHA from `git log --follow`; `git diff -U0` shows no added first-person line about access.
3. Customer-facing wording: `grep -c 'held on a single volume with no off-project copy'` is at least 1 in each of the ADR addendum, the design doc and the A6 draft; recoverability after a project or account loss reads "not established"; "delete-protected" appears only for the Hetzner volume flag.
4. Diff scope: `git diff --name-only origin/main...HEAD` is a subset of the Files to Create and Files to Edit lists plus this plan, `tasks.md`, `decision-challenges.md` and `session-state.md`; piped through `grep -E '\.tf$|^\.github/workflows/|^apps/'` it prints nothing; no user-facing file (`docs/legal`, marketing, `apps/web-platform/app`, `components`) is in it. No issue is created or closed other than the revisit tracker and the deferral issues named in the PR body (items without a number today: the dead-man alert PR and the header backup; filing them is Phase 0 step 0.2).
5. `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh knowledge-base/project/specs/feat-one-shot-9927-record-owner-decisions-a6-refresh/decision-challenges.md` prints `[PASS]` (re-run after any review row); `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` and `python3 scripts/lint-guard-contract.py <this plan>` exit 0.
6. The ADR-282 addendum: `grep -c '^## Addendum - 2026-11-06'` prints 1; each owner ask carries the label verbatim with its parenthetical (the count of the label string equals the number of owner rows it renders) and a status word; one line per ruling with its row id, R1 to R6 keeping their `source: ruling relayed in the run brief, not re-asked here` clause; the arm-token exposure statement verbatim (step 1.4), the only place it is written out; CLO conditions C1 to C11 as predicates; the epic close conditions of R6; no edit above the addendum other than dated `Superseded` markers; ends with "What this does not change" naming the holds.
7. The design doc exists at `knowledge-base/project/specs/feat-one-shot-9927-record-owner-decisions-a6-refresh/arm-token-replacement-design-12158.md` and `grep -c` finds each of the headings: the revisit question, "Sequence", "Test pins", "Held", "Recorded now" and "Built after the window"; it points to rows D1, D1b, D1c, D2 instead of restating them, links the ADR exposure statement, states the `inngest_cutover` environment keep and the revoke change with its named rollback, and cites the content anchor in `apps/web-platform/infra/inngest-arm-write-token.tf` that records the Terraform GitHub App cannot write environment secrets.
8. G2e supersession: `git diff origin/main...HEAD -U0 -- plugins/soleur/test/terraform-target-parity.test.ts | grep -cE '^[-+][^-+]'` prints 1 and that line starts `// Superseded 2026-11-06`; `bun test plugins/soleur/test/terraform-target-parity.test.ts` reports `365 pass, 0 fail` (the plan-time baseline) before and after; the ADR marker and the learning marker each sit on their own line after the paragraph they supersede.
9. Probe and enrollment: `git ls-files -s scripts/followthroughs/arm-token-revisit-<N>.sh` prints mode `100755`; `bash scripts/followthroughs/arm-token-revisit-<N>.test.sh` passes (case-count floor met) and the suite is registered once in `scripts/test-all.sh` with its `scripts/suite-shard-legs.tsv` row and `scripts/lib/test-affected-paths.sh` entries; `bash scripts/lint-orphan-test-suites.sh` exits 0 with the suite counted (run after `git add`).
10. Hetzner evidence: the API read section states a UTC time, the volume id, the delete-protection flag, the server count (count and role labels, no names) and the token class (no value), and that it says nothing about members, two-factor or tokens. A failed read is a marked pending cell with the failure class (`unreadable`, `refused`, `could not read`; the 401 mapping is exercised once with an invalid token); a successful read with a surprising value (flag false, volume absent, unexpected count) is recorded verbatim, not presented as clean, and surfaced in the run summary; nothing is filed either way.

### Post-merge (agent-run)

11. `gh issue view 9927 --json state` and `gh issue view 12158 --json state` print `OPEN`; the PR body contains `Ref #9927` and `Ref #12158` and no closing keyword.
12. The revisit tracker's body contains an unfenced column-0 `<!-- soleur:followthrough script=scripts/followthroughs/arm-token-revisit-<N>.sh earliest=2027-01-08T00:00:00Z -->` and the issue carries the `follow-through` label (`gh issue view <N> --json body,labels` shows both); the first sweep logs "earliest=... not yet reached -- skipping".
13. The Phase 6 comments exist once each (idempotency marker count 1), the #9927 comment ends "#9927 stays open." and states that the A6 rename to the signing date is deferred to the signing event (CLO L1) so the owner can reverse it in one message; #12213, #12158 and #11265 are not closed by the agent.

## Implementation Phases

### Phase 0 - Tracker and deferral issues (before any text that cites them)

0.1 File the revisit tracker now WITHOUT the `follow-through` label and WITHOUT the directive (step 5.1 describes it) so the ADR addendum, the design doc and the #12158 comment can cite its number.
0.2 Verify each deferral has its own open issue (`gh issue view`): header backup (#9927 item 1 is only a line in the epic body), the dead-man alert PR (ADR-282, prerequisite of #11266), off-project copy (#9927 item 1b), host-token downgrade and keeper (#11265), flip-read canary and write path (#12158). File one (milestone `Post-MVP / Later`, label `deferred-scope-out`-style per `wg-when-deferring-a-capability-create-a`) for any that lacks it and name them in the PR body.

### Phase 1 - ADR-282 addendum

1.1 `git fetch origin main`; re-read the true tail of ADR-282 (PR 12218 may append); re-fetch before commit and after any rebase; anchor each Superseded marker by content, not position, and put it on its own line after the paragraph it supersedes (the sunset sentence sits mid-paragraph in a long line).
1.2 Append `## Addendum - 2026-11-06 (#9927 owner decisions, items 1b, 4, 8, 10)`: **Decisions** (six, each with the label and a status word); **Rulings** (one line each with the row id: R1 to R6, D1 to D6, D1b, D1c, D3-r1 to D3-r3, L1 to L4, L1-r; R1 to R6 keep their `source: ruling relayed in the run brief, not re-asked here` clause verbatim; seat dissents D4 and D5 and the CLO rename dissent noted as such); an ask-to-row map (ask 1 = O1, ask 2 = O2, ask 3 = O3 + O4 + O5, ask 4 = O6, ask 5 = O9, ask 6 = O7; O8 is the rename override); **Preconditions for the bundled window** (the D6 list: #12213 green on a SHA containing 12210; `inngest-userdata-budget.sh --cap-only` on the dispatch SHA; probe-carrying config bundle and digest promotion #11266 together with the dead-man alert PR; the Better Stack dead-man probe production write, owner-authorised for the window and re-asked in-session at dispatch like the dispatch itself; a per-command in-session go; #11265 as in-or-out; the item-4 host-token downgrade as bundle content to verify afterwards; #9927 is the carrier of the window planning); **Off-project copy** (status `funded in principle, no spend committed, build gated`; C1 to C11; its write-only credential rides the replace; a header-only copy does not help a project loss); **Epic close conditions** (R6); **What this does not change**.
1.3 Dated `Superseded 2026-11-06` markers (no rewrite): under the sunset sentence of the 2026-11-03 addendum; under the 2026-11-05 sentences "Tier-B delivery of the read credential ... rejected for now" and "It is the direction #12158 takes for the write credential", as to flip-read ordered after the window (D2) and the write credential moving to an environment secret (D1b).
1.4 Exposure statement, verbatim (CTO D4): the standing token is `access = "read/write"` (`doppler_service_token.inngest_arm_write` in `inngest-arm-write-token.tf`). It reads every key in `soleur-inngest/prd`, including `INNGEST_REDIS_LUKS_KEY`, `INNGEST_TLS_KEY` and `INNGEST_SIGNING_KEY`; it is a repo-level secret, so any workflow an actor can push to a branch can resolve it; the `inngest-cutover` reviewer gate covers only jobs that declare the environment. Write is the larger risk: overwriting the LUKS key would leave the sole-copy volume unopenable on the next boot; the history that would let someone recover the old value sits in Doppler (not verified).
1.5 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`; wrap only passages that prescribe nothing in an HTML-comment `lint-infra-ignore` region.

### Phase 2 - A6 draft refresh (read-only evidence, no rename, no sentence)

2.1 Hetzner API read, read-only. Fetch `HCLOUD_TOKEN_READONLY` from Doppler `soleur/prd_terraform` into a masked variable (no `-x`, `timeout 60` on every call, never echoed; the token reaches `curl` through a header file descriptor or stdin, not argv). Calls (pinned form): `curl -sS --max-time 30 -o "$out" -w '%{http_code}' -H @"$hdr" https://api.hetzner.cloud/v1/volumes/106903269` and the same for `/v1/servers`, with `$hdr` a mode-600 temp file under the scratchpad holding the Authorization header, removed on exit; read `.volume.protection.delete`, `.volume.status` and `(.servers | length)` with `jq`. Run the 401 mapping once with an invalid token to confirm it renders the pending form. Map 401/403/404, rc 124/137, a non-JSON body and a harness refusal to the pending form with its failure class. No write verb, no retry loop, nothing filed; the brief's "file nothing" prevails over any postmerge issue-filing for an absent token (report it in the run summary instead).
2.2 Edit the draft: frontmatter `refreshed: 2026-11-06` (status unchanged); directly under the H1 the visible line `unsigned, owner sentence pending`; a new section "API read, 2026-11-06T<time>Z (not the console figures)" with the figures and the sentence that it says nothing about members, two-factor or tokens; the 2026-10-29 console figures retitled "last console read, 2026-10-29" with the row "Console re-read of members, two-factor and API tokens: PENDING, owner's own signed-in browser. No agent fills this cell."
2.3 Related-items table: A5 cell -> "recorded complete on #10136: `S5-A5-DONE` 2026-11-02T14:28:00Z (agent-posted at owner delegation) and `S5-A5-RELAYED` 2026-11-02T21:51:04Z (owner's words); covers the dedicated Inngest key pair only; the other exposed keys are still rotating, see the 2026-11-02 keys record and the CLO re-assessment due 2026-11-08"; measured-re-read cell -> point to the 2026-11-02 keys record's tls-health re-read (`nft_rules=7`, `legacy_8288_packets=0`) as available evidence, the owner's own column untouched; Hetzner-answer cell -> "received 2026-11-02, paraphrase of the support reply (#9927 comment 6577564178); a support reply, not a contract term", no quotation marks. Each changed cell keeps its 2026-10-31 text under a `Superseded 2026-11-06` marker.
2.4 Add the "Owner's own sentence" section with only the empty field. Delete the old "Statement (to be adopted by the owner)" block (CLO L1-r) and put the one-line replacement note in its place: "An agent-written evidence-framing block stood here from 2026-10-30 until 2026-11-06. It was removed because an agent never drafts the owner's knowledge sentence. It is recoverable from git history (commit <SHA>)." with the SHA from `git log --follow` on the file (never guessed; no sentence of the block re-quoted). Append `Superseded 2026-11-06: that block was removed` under the top 2026-11-02 banner and under any other inbound mention found by `git grep -n 'Statement (to be adopted by the owner)'` outside `archive/` and the plan/spec folders (at plan time only the file itself matched).
2.5 Under the "CLO review, 2026-10-31" heading add a new paragraph (not a heading edit): "Superseded in part 2026-11-06: the A5 reason is resolved (see the A5 cell); the signing-route reason was superseded by the 2026-11-02 rulings. This refusal was not an attestation, and no attestation exists. The conditions for resubmission are posted on #10382 (<comment URL>)." The URL is written only after the #10382 comment of step 6.2 exists and is verified. Never write "lifted" or "cleared". Signature block and "After signing" stay unfilled.
2.6 "Claim limits": carry the removed block's limits in third person (Hetzner staff access and retention after closure are not established; the console figures are dated 2026-10-29; the owner's knowledge covers the owner's own knowledge at signing) and add the CLO paragraphs verbatim:
   (1) "Hetzner's support reply of 2026-11-02 (paraphrase, #9927 comment 6577564178) says that delete protection does not guarantee data retention after account termination, that Admins and Members can lift protection and delete volumes, and that project deletion checks for protected resources. This record therefore does not establish that the volume survives a project deletion, an account suspension or closure, or deletion by any person holding Admin or Member rights."
   (2) "Delete protection is a guard against accidental deletion by the project's own users. It is not a retention guarantee and not an access control against project members. The volume is the only copy; no off-project copy exists. An off-project ciphertext copy is deferred, not declined, and is not built."
   (3) "The 2026-11-06 API read shows only the volume, its delete-protection flag and the server list as of its UTC time. It does not show members, two-factor status or tokens, and it is not a substitute for the console re-read."
2.7 No rename in this run, and no conditional rename: if an owner sentence appears, stop and hand off (no insertion, no rename). The rename at signing is one commit that also updates every inbound reference: the ADR addendum, the design doc, and the issue comments (which `git grep` cannot find, so the comments' permalinks are SHA-based and the rename step lists them).
2.8 Conditions before the CLO will attest (kept in this plan and posted once in the #10382 comment, never in the draft): the owner's sentence exists in the owner's words via the 2026-11-02 provenance block with "Agent-drafted text: no" and the tracker post is `S6-A6-RELAYED` (or `S6-A6-DONE` typed by the owner); the sentence is scoped to the project's human members and tokens and does not cover Hetzner staff, retention or post-closure; the pending console re-read is filled by the owner, dated after 2026-11-02, with every API token reconciled to a known purpose (without it the CLO attests only a sentence anchored to the 2026-10-29 figures); the measured-re-read cell is linked or marked "n/a" by the owner; the three claim-limit paragraphs are present; the file shows no "signed" or "attested" wording ahead of those events; the 2026-11-12 re-review and the TLS rows are not claimed as discharged.

### Phase 3 - #12158 design doc

3.1 Create `arm-token-replacement-design-12158.md`. Lead with the decision the revisit must produce (revoke, or keep with a new date at most 90 days out) and what makes revoke possible. Then: current-state ledger (consumers by token and verb, with the `git grep` commands that re-derive it); the chosen path by pointer to rows D1, D1b, D1c (not recopied) plus the requirements that are not in those rows: only `cutover-inngest.yml` and `scripts/cutover-inngest.sh` (five sites) change; the existing ternary shape as the pin; the stale-token check; the relay script (`terraform output -raw` of a `sensitive = true` output into `gh secret set --env inngest-cutover` over stdin, never echoed, refuses xtrace, with a test on the script text; it exists because the Terraform GitHub App cannot write environment secrets - cite the comment in `apps/web-platform/infra/inngest-arm-write-token.tf` that records the 403); the verbs' reads could use the flip-read token today (only three writes need a write token: set `rollback`, delete `INNGEST_HEARTBEAT_URL`, set `flushed`).
3.2 Test pins, listed once: the new secret name appears only in `cutover-inngest.yml`, only in steps limited to rollback or resume, never in `.github/actions/infra-credentials/action.yml`; the Tier-B loader step stays `if: inputs.op == 'backup'` and no op arm combines the loader with the new secret; no `github_actions_secret` or `github_actions_environment_secret` resource carries the key (static grep); `tests/scripts/test-infra-privileged-tier-census.sh` gains an environment-scoped-name clause and `DOPPLER_TOKEN_INNGEST_ARM` leaves `REPO_SCOPED_PRIV` in the revoke change; `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, `inngest-host-replace-preflight.test.sh` and `test-inngest-host-replace-gate.sh` move with the changes they pin; to verify at build, not assumed: whether the census or `infra-credential-tiers-8209.md` requires every environment secret to be registered by name, and that `DOPPLER_TOKEN_INFRA_PRIVILEGED` is present on the `inngest-cutover` environment. The new token needs its own revisit coverage once it exists (the probe watches only the arm token).
3.3 Failure modes: blast radius unchanged (a per-config token reads `INNGEST_REDIS_LUKS_KEY`); delivery narrows from any-branch repo secret to main-only environment secret; a stale or unset environment secret makes op=resume refuse with a named verdict such as `write_token_stale` (fail-closed) and blocks the next replace recovery.
3.4 Sequence (CTO D2) with preconditions per step: (0) the D6 list; (1) host replace plus `op=resume` (dispatch is a per-command in-session go, not authorised here); (2) the new write path built and proven (one green gated run of op=resume or op=rollback, or an authenticated Doppler API check that the new token is read/write on `soleur-inngest/prd`); (3) flip-read to Tier B (the `inngest_host_replace` job already runs under `environment: infra-privileged`, so its preflight reads the key from the loader once seeded into `soleur-infra-privileged/prd`); (4) the revoke change: removes `doppler_service_token.inngest_arm_write` and `github_actions_secret.doppler_token_inngest_arm` from config and their two `-target` lines from `apply-web-platform-infra.yml`, drops the export step, keeps `github_repository_environment.inngest_cutover` and `..._deployment_policy.inngest_cutover_main` with their `-target` lines, rewrites the file header, never deletes `inngest-arm-write-token.tf` whole; removing the `-target` lines alone does not revoke - the destroy is a separate owner-gated apply (or `doppler configs tokens revoke`). Named rollback for the revoke: re-mint with `-replace=doppler_service_token.inngest_arm_write` (documented in the file). Only docs may land before the window; a change to `cutover-inngest.yml`, the inherited-done preflight, a new secret or the `-target` lines moves the dispatch SHA and waits until after it. If no window has happened by about 2026-12-08, steps 2 and 3 may move earlier with the dispatch SHA re-checked.
3.5 State the ADR-241 fit (Architecture section), the held list and the recorded-now versus built-later split; lint the doc with `lint-infra-no-human-steps.py` (future steps are workflow or script steps, never a human prescribed to run an apply or SSH).

### Phase 4 - G2e supersession markers

4.1 `plugins/soleur/test/terraform-target-parity.test.ts`: add exactly one comment line below the `SUNSET (deferred, #9927 item 10)` block: `// Superseded 2026-11-06 (CTO ruling, #9927): G2e is kept permanently as the independent different-language anchor; no sunset.` Comment-only. Run `bun test plugins/soleur/test/terraform-target-parity.test.ts` before and after (green, same count) and again after the Phase 5 registration (the G2f pin inspects `scripts/test-all.sh`). The edit triggers the full battery in CI; expected.
4.2 Add a new line after the paragraph in `knowledge-base/project/learnings/2026-10-11-sole-copy-pins-the-required-check-anchor-must-not-be-a-subset-of-the-advisory-guard.md` that holds the `Sunset marker: fold` text: `Superseded 2026-11-06: G2e is kept permanently, no sunset (CTO ruling, #9927).`
4.3 The ADR marker is step 1.3; the two #9927 comments are superseded by link in step 6.1.

### Phase 5 - Arm-token revisit probe (inferred from CTO D3/D4, amended by D3-r1 to D3-r3)

5.1 The tracker (filed in step 0.1 without the label and the directive, to get `<N>`): title "follow-through: arm-token revisit (next host replace or 2027-01-08), Ref #9927 Ref #12158", labels `priority/p3-low`, `type/chore`, `domain/engineering`, milestone `Post-MVP / Later` (the same as #12158). Body: the revisit question, the exposure in one line (link to the ADR addendum), the probe's limits (measures config not Doppler; "next host replace" half is carried by #12158 step 4 and prose), the recorded decision (the appended #12158 comment, then close this tracker and remove its label; a keep decision files the next tracker with a new date at most 90 days out), and the line "not enrolled until the probe is on main". If this PR is abandoned, close the tracker.
5.2 Write the suite first (cq-write-failing-tests-before): `scripts/followthroughs/arm-token-revisit-<N>.test.sh` - the seven mutants of the Guard Contract as mutants, about five cases (exit 5 with all three present, only the target line, only the declaration; exit 2 with none; exit 3 unreadable), the exit-set assertion {2,3,5}, the 100755 mode assertion, synthesized fixtures and a test-only env override for the two file paths (the sweeper runs probes under `env -i`).
5.3 Write the probe from `plugins/soleur/skills/ship/references/followthrough-stub-template.sh`: header with notify-only, credential posture ("none: reads two tracked files; no `secrets=`"), the residuals from the Guard Contract Anchor and a `RETIREMENT:` line listing every site (probe, suite, the three registration files, the directive). `chmod 755`.
5.4 Register once: a `run_suite` line in `scripts/test-all.sh` beside the zot-soak registrations (about line 6067), away from Guard 1's line; one `scripts/suite-shard-legs.tsv` row on a light leg (check the manifest tests); the `AFFECTED_*_PATHS` block and `ALWAYS_ON_SUITES` entry in `scripts/lib/test-affected-paths.sh`, copying the two `zot-soak-6122` entries (the suite path near `scripts/followthroughs/zot-soak-6122.test.sh` and the `glob:scripts/followthroughs/*zot-soak-6122*.sh` anchor row) - otherwise the PR falls back to the full battery. `scripts/ci-pr-affected-audit.accept.tsv` only if the audit demands rows. Run `bash scripts/lint-orphan-test-suites.sh`.
5.5 After the merge shows the probe on main: edit the tracker's own body to add the unfenced column-0 directive and add the label (AC 12); the first sweep logging "earliest=... not yet reached -- skipping" is the enrollment evidence. This step is an owned item of the post-merge phase, not prose.

### Phase 6 - GitHub comments (none of them a closing action)

6.1 After the PR shows MERGED (`gh pr view --json state,mergeCommit`; a queued or ejected PR posts nothing): ONE comment on #9927 with the six owner asks under the label, the sentence "the rename of the A6 draft to the signing date is deferred to the signing event (CLO ruling); say so in one message to reverse it", the rulings by reference to the ADR addendum, the supersession by link of comments 6614866201 and 6620352154 (G2e is kept permanently), the R6 checklist, the #12213 state, `Ref #9927`, and "#9927 stays open." Each posted comment carries a hidden idempotency marker and is checked for it before posting; order: #12158 first, then #9927.
6.2 Before merge (work phase, after the draft is pushed): ONE comment on #10382 headed "Ruled by CLO agent, 2026-11-06 (v1 internal; not external counsel advice): conditions before the CLO will attest. No attestation exists.", the seven conditions of 2.8 as one sentence-list, the PR link, and the owner steps by role (the owner's sentence, the console re-read). Never "ready to attest" or "pending attestation". Its URL goes into the draft (step 2.5).
6.3 After merge: one appended comment on #12158 (its body is never edited): "Re-evaluation trigger amended 2026-11-06: the next host replace or 2027-01-08, whichever is first. The date is enforced by #<tracker>. Decision recorded: KEEP." plus a pointer to the ADR exposure statement, and "item 1 of this body (retire resume and rollback in the same owner-run sequence as the revoke) is superseded by CTO rulings D1, D1b and D2: both verbs are kept and the write path is replaced", `Ref #9927`.
6.4 After merge: one link comment each on #10382 and #10136, a commit-SHA permalink to the A6 draft ("unsigned draft of the Hetzner-project record, refreshed 2026-11-06; not a record until the owner signs it and the CLO attests it separately; the path changes at signing"), no `S5-` or `S6-` token, no closing keyword. Before every post, grep the body for `S5-`, `S6-`, closing keywords and the banned words.
6.5 Read-only re-check of #12213 and of the latest merge-queue or dispatch `ci.yml` run, reported in the #9927 comment; the agent does not close #12213, #12158 or #11265.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9927-record-owner-decisions-a6-refresh/decision-challenges.md` (written in the plan phase)
- `knowledge-base/project/specs/feat-one-shot-9927-record-owner-decisions-a6-refresh/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9927-record-owner-decisions-a6-refresh/arm-token-replacement-design-12158.md`
- `scripts/followthroughs/arm-token-revisit-<N>.sh` (mode 100755; `<N>` = the tracker number from step 5.1)
- `scripts/followthroughs/arm-token-revisit-<N>.test.sh`

## Files to Edit

- `knowledge-base/legal/audits/2026-10-30-inngest-a6-no-known-access-record.md`
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` (append only, plus dated Superseded markers)
- `plugins/soleur/test/terraform-target-parity.test.ts` (one comment line)
- `knowledge-base/project/learnings/2026-10-11-sole-copy-pins-the-required-check-anchor-must-not-be-a-subset-of-the-advisory-guard.md` (one appended line)
- `scripts/test-all.sh` (one `run_suite` registration)
- `scripts/suite-shard-legs.tsv` (one row)
- `scripts/lib/test-affected-paths.sh` (the `AFFECTED_*_PATHS` block and `ALWAYS_ON_SUITES` entry)
- `scripts/ci-pr-affected-audit.accept.tsv` (only if the audit demands rows)

Every path above is exact; `git ls-files <path>` must print each existing file before the work phase edits it.

## Open Code-Review Overlap

Acknowledged: #8881 (`scripts/suite-shard-legs.tsv`) and #7942 (`scripts/test-all.sh`). This PR adds one row or line to each and fixes neither; both stay open.

## Test Scenarios

1. Probe with all three members present, only the token `-target` line, only the secret `-target` line, only the resource declaration -> exit 5 each.
2. Probe with none present (and with only commented-out occurrences) -> exit 2 "targets gone".
3. Probe with an unreadable workflow file, and with an unreadable `.tf` file -> exit 3.
4. Probe exit set is exactly {2,3,5} over the fixture matrix; mode is 100755.
5. `bun test plugins/soleur/test/terraform-target-parity.test.ts` green before and after the comment line and after the registration (same test count).
6. Wording gate (Acceptance Criterion 1) over the diff.

## Observability

The only executed code is the notify-only probe under the existing follow-through sweeper (not a new autonomous-task surface: no workflow, Inngest function, timer or daemon; Task-Design gate not triggered). The Hetzner API read runs once in the work session and its failure classes are written into the record. Not a post-deploy soak: the 2027-01-08 date is a decision date, enrolled through the sweeper's `earliest=` gate.

```yaml
liveness_signal:
  what: the daily follow-through sweeper comment on the revisit tracker, carrying the probe's exit word (NOT YET, ACTION REQUIRED, CANNOT ESTABLISH)
  cadence: daily from 2027-01-08T00:00:00Z (the sweeper skips the tracker before its earliest= date)
  alert_target: the open revisit tracker issue (domain/engineering) and the sweeper's own run summary
  configured_in: the unfenced column-0 directive in the tracker body, scripts/sweep-followthroughs.sh, scripts/followthroughs/arm-token-revisit-<N>.sh

error_reporting:
  destination: the sweeper comment on the tracker (no Sentry project; the probe holds no credential and calls no network)
  fail_loud: probe exit 3 renders CANNOT ESTABLISH in the comment heading when either tracked file is unreadable; exit 5 renders ACTION REQUIRED while any arm-token member is still in config

failure_modes:
  - mode: tracker never enrolled (label or directive missing, or the probe committed non-executable)
    detection: the post-merge predicate in Acceptance Criteria 12 and the sweeper's own "not executable" or "script missing" log line
    alert_route: the sweeper run summary and the PR's post-merge phase
  - mode: probe silenced by a revoke change that removes the target lines but leaves the token resource
    detection: the resource declaration is the third member the probe checks
    alert_route: exit 5 ACTION REQUIRED comment on the tracker
  - mode: the probe measures config and not Doppler (a destroy never applied)
    detection: stated residual, carried by the #12158 comment and the owner-gated destroy step
    alert_route: the #12158 tracker

logs:
  where: the tracker issue comments (gh issue view <N> --comments) and the sweeper workflow run log
  retention: GitHub issue history, indefinite; workflow run logs per repository retention

discoverability_test:
  command: git ls-files -s scripts/followthroughs/arm-token-revisit-*.sh
  expected_output: 100755
```

## Infrastructure and Encryption

No infrastructure is introduced and no persistent store or new connection is added: the design doc describes a future credential and its environment-secret delivery in words only; any Terraform, workflow or loader change belongs to the post-window PRs, which carry their own IaC and encryption-posture sections. The `inngest_cutover` environment is kept, not changed.

## Alternative Approaches Considered

Rename now (CLO L1 dissent), retire rollback and resume (CTO D1), auto-revoke on the date (CTO D4), editing #12158's body (CTO D3), removing the G2e pin (CTO D5), reading #12158 comments in the probe (CTO D3-r1), doing the Tier-B flip-read and write-path builds before the window (CTO D2) are each recorded as rows in `decision-challenges.md` with their reasons; they are not restated here.

Deferrals: header backup (#9927 item 1), off-project copy (#9927 item 1b, `funded in principle`), host-token downgrade and keeper (#11265), flip-read canary and write path (#12158), the revisit (the new tracker, Phase 5), the dead-man alert PR (ADR-282, prerequisite of #11266). The work phase verifies each has an open issue with `gh issue view` and files one (milestone `Post-MVP / Later`) for any that lacks it.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it.
- Never write the owner's sentence, even as an example, stem or "suggested scope".
- No `S5-` or `S6-` token in any comment this run posts: the A5/A6 relay probe parses them.
- The Hetzner API read must not print the token: fetch into a masked variable and pass it on stdin or a descriptor; a PreToolUse hook blocks heredocs that quote the Doppler secret-write command, so describe that command by role.
- `gh issue edit --body` is never used on #9927 or #12158; only appended comments. The new tracker's own body may be edited (CTO D3-r3).
- A comment-only edit to `plugins/soleur/test/terraform-target-parity.test.ts` runs the full CI battery; watch the merge-queue or dispatch run, not the push run.
- ADR addenda use the present tense tied to the merge ("on the merge of PR 12219 this addendum records ...").
- The probe must be committed executable (100755) or the sweeper refuses it before it checks the date.
- A `Superseded` marker is a new line after the paragraph it supersedes, never an in-line edit; the learning and the draft's top banner keep their original text.
