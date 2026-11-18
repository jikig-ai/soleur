---
title: "chore(legal): renew the leg-2 Inngest sdk_url poll exception to its 2026-12-10 hard stop"
date: 2026-11-17
slug: chore-renew-inngest-leg2-exception-to-2026-12-10
branch: feat-one-shot-renew-inngest-leg2-exception
issue: 12742
type: chore
lane: cross-domain
brand_survival_threshold: aggregate pattern
refs: [12742, 10538]
---

# Renew the leg-2 Inngest sdk_url poll exception to 2026-12-10

## Enhancement Summary

**Deepened on:** 2026-11-17 (after plan review). **Sections enhanced:** Rulings, Phases 1-5, Measurement commands, CLO
drafts A-C, Files to Edit, Acceptance Criteria, Architecture Decision. **Inputs:** plan review (DHH, Kieran,
code-simplicity), CLO and CTO agent re-rulings on each review finding, and live verification of every citation.

### Key Improvements

1. One public evidence comment: the separate measurement comment is folded into the #12742 acceptance comment (CLO cut F2),
   which carries every value labelled by reader and time plus its query; the ledger and record cite only `ACCEPT_ID`.
2. The record, the ledger and the comments cite the plan-time reads (CTO 17:04-17:07Z, planner 17:11Z). Work-phase reads only
   decide whether to halt, against one halt predicate that includes the Hetzner void checks. The merge-day re-read is the
   last step before enqueueing, and "unchanged" may be written only over values that were actually re-read.
3. Ledger Draft B is trimmed (CLO cut F3) and keeps the void result in words, the full legacy clause and the measurement times.
4. Three more statements of the superseded 2026-11-20 requirement now get their own markers: counsel-review Q-2, the
   runbook precondition-1 note, and an ADR-294 dated note (the 7th file).
5. Phase 5 order fixed: the relabel comes before the acceptance comment that says it happened. PR #12884 already exists,
   so the work phase fills its number up front.

### New Considerations Discovered

- `git diff -U0` on the 2026-11-13 record shows the one-line `addenda:` array as changed; AC6 now allows exactly the three
  frontmatter lines.
- A PR cannot carry its own merge time. The late-merge gap wording now points at the merge commit's timestamp.
- `lint-legal-registers.sh` checks cited paths with `git ls-files`, so AC8 runs after `git add`.
- MD028 is disabled in `.markdownlint.json`, so adjacent Superseded blockquotes lint clean.
- Verified live on 2026-11-17:
  - every cited issue and PR (including #12884 OPEN draft, and #12876 changing only its own plan and spec files);
  - comment 6846245981;
  - run 43862798565 (12:01:10Z-12:08:55Z, success);
  - all four labels;
  - the nft `legacy_8288` rule's source set (`ip saddr { ${web_host_private_ips} }`).

## Overview

Ledger row 6 of `scripts/encryption-posture-ledger.json` (the plain-HTTP poll from the dedicated
Inngest host to the web app on the private network) carries an accepted-risk exception that expires
on 2026-11-20. The fix tracked on #12742 cannot land by then. The owner accepted, in session on
2026-11-17, a renewal to 2026-12-10, the last date the record allows. This plan covers the ledger
date change, a new A7 audit record, a read-only re-measurement of the compensating controls, the
acceptance comment (on #12742, with a pointer on #10538, per the CLO), and a priority comment on #12742.

The re-measurement (run read-only at plan time by the CTO agent and the planner) found one change since 2026-11-13: the
legacy plaintext counter on the Inngest host rose from 0 to 12 on 2026-11-16, from our own web hosts (leg 1). The CLO ruled
it does not halt the renewal, so the plan also files an issue for it and records a breach-register assessment.

Spec lacks valid lane: (no spec.md for this branch) - defaulted to cross-domain (TR2 fail-closed). This PR references
#12742 and #10538 and closes neither.

## Research Insights

### Premise Validation (Phase 0.6, run 2026-11-17)

- **Ledger row.** `scripts/encryption-posture-ledger.json` `connections[6]` (0-indexed; the leg-2 `sdk_url` poll) reads
  `"tracking_issue": "#12742"`, `"expires_on": "2026-11-20"`, and its justification ends "After 2026-11-20 the row lapses
  again. No acceptance runs past 2026-12-10." Held.
- **Gate deadline (corrects the brief).** `scripts/lint-encryption-posture.py` `check_exception_block` fails when
  `date.fromisoformat(expires_on) < today`. Measured: `python3 scripts/lint-encryption-posture.py --repo-sweep` passes today
  (with a 3-day warning) and `--today 2026-11-21` fails ("expires_on 2026-11-20 is in the past (as of 2026-11-21)"). So the
  required check (`ci.yml` job `encryption-posture`, `ubuntu-24.04`, UTC) goes red at **2026-11-21T00:00Z**, not
  2026-11-20T00:00Z. This matches the precedent: "until 2026-11-12" lapsed at 2026-11-13T00:00Z. The plan keeps the brief's
  earlier target as a goal and the real gate time as the hard limit.
- **Issues.** #10538 OPEN (may close only as "not planned, superseded by #12742", CLO 2026-11-16). #12742 OPEN,
  `priority/p2-medium`. #10136 CLOSED. Draft PR #12876 OPEN (WIP; its four files are plan/spec/tasks only today, but its
  plan edits `knowledge-base/engineering/operations/runbooks/inngest-server.md`).
- **Collision pre-check.** `collision-precheck.sh 12742` -> exit 10, PR #12876 (the parallel work this PR must not touch).
  `collision-precheck.sh 10538` -> exit 0. Open PRs touching the ledger: #8626 only (draft, idle since 2026-11-07, does not
  touch row 6's lines). Acknowledged; no overlap with row 6's hunk.
- **Cited records.** `knowledge-base/legal/audits/2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md` (title already
  relabelled "new acceptance after a lapse"; addendum; "Unsigned owner-record draft" of 12 elements) and
  `2026-11-02-a7-leg2-accepted-risk-ledger-inngest-sdk-url-poll.md` exist. #10538 comments 6840514776 (controls,
  2026-11-13T00:55:51Z) and 6846245981 (acceptance, 06:46:47Z) exist and were read.
- **Statements that require an owner-typed record after 2026-11-20** (to be reconciled by the CLO ruling, not silently
  overridden): the 2026-11-13 record body ("needs a record that begins 'SIGNED BY OWNER (human, not an agent)' or a fresh
  in-session instruction the CLO rules sufficient"); its addendum and draft; #12742 item 8; #12742 comment 6893812351
  ("Before 2026-11-20 the owner either renews row 6 with their own typed record or converts it"); runbook
  `inngest-server.md` precondition 4 and the 2026-11-13 CLO notes near "The legal bridge date" and the #10538 row of
  "Tracked follow-ups"; `2026-11-counsel-review-10479.md` ("The acceptance lapses again after 2026-11-20 unless the owner's
  replace has run or an owner-typed record exists.").

### How the 2026-11-13 controls were measured (to reproduce read-only, never SSH)

From #10538 comment 6840514776:

- **Hetzner:** `GET https://api.hetzner.cloud/v1/servers` with `HCLOUD_TOKEN_READONLY` (Doppler `soleur/prd_terraform`).
  Result: 5 servers, all Jikigai: `soleur-web-platform` 10.0.1.10, `soleur-web-2` 10.0.1.11, `soleur-git-data` 10.0.1.20,
  `soleur-registry` 10.0.1.30, `soleur-inngest` 10.0.1.40. The header-from-stdin curl pattern
  (`--disable --noproxy "*" --config -`) is in `plugins/soleur/skills/postmerge/SKILL.md`.
- **tls-health:** the host's `stage=tls-health` phone-home rows (every 5 minutes, Better Stack source 2457081), read with
  `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since ... --grep stage=tls-health`. The rows
  are double-encoded (`.raw | fromjson`) and must be field-isolated on `marker == "SOLEUR_INNGEST_BOOT_STAGE"`,
  `stage == "tls-health"`, `shipper == "cloud-init-phone-home"` (header of `scripts/followthroughs/inngest-tls-soak-10136.sh`).
  Detail fields (emitter `apps/web-platform/infra/cloud-init-inngest.yml` ~line 458): `unit`, `listener`, `served_sha256`,
  `cert_sha256`, `legacy_8288_packets`, `tls_8443_packets`, `nft8443_sha256`, `nft_rules`, `boot_id`. 2026-11-13 values:
  `nft_rules=7`, `nft8443_sha256` present, `legacy_8288=0`, `served_sha256==cert_sha256`, `unit=active`.

### Precedent

PR #12733 (commit 03bbba9d90, merged 2026-11-13): changed only `scripts/encryption-posture-ledger.json` (row 6
justification and `expires_on`; row 7 date) and added one audit file. No lint, `ci.yml` or ruleset change. Test plan:
`lint-encryption-posture.py --repo-sweep` FAIL on main / PASS on branch, `lint-encryption-posture.test.sh`, markdownlint.

### Consumers of the row

No test pins row 6's `expires_on` or justification. `apps/web-platform/test/seo-config-rules.test.ts` reads the live ledger
but only selects the row `disclosed_as` the Privacy Policy anchor (row 7). `scripts/lint-encryption-posture.test.sh` WC-30
reads the live ledger but rewrites only `hcloud_volume.workspaces`.

### Institutional learnings applied

- `2026-10-12-a-ledger-renewal-restated-the-plans-unmeasured-claims-as-facts.md`: a renewal must not restate unmeasured
  claims as fact; every measurement in the row and record carries its date and source.
- `2026-11-05-a-ledger-that-guards-a-clobber-needs-its-own-integrity-pins-...md`: the diff must touch only row 6's
  `justification` and `expires_on` (checked by a JSON diff of every other field).
- `workflow-issues/2026-10-07-a-one-line-operational-ask-became-a-day-long-pipeline-...md`: use `HCLOUD_TOKEN_READONLY`,
  never the write token; an empty ad-hoc Better Stack read is not evidence of absence.
- `2026-08-16-every-mechanism-i-shipped-to-prove-the-fix-was-itself-unproven.md`: decode rows before matching; a raw-grep
  zero proves nothing.
- `security-issues/2026-09-25-an-accepted-residual-named-an-actor-that-never-existed.md`: the record names the real act
  that ends the risk (the owner's `inngest-host-replace` under #12742) and a check that actually runs.
- `2026-11-04-a-pr-body-and-closing-report-bypassed-the-only-gate-that-read-owner-lists.md`: never describe an
  agent-posted comment as "SIGNED BY OWNER"; run `technical-ruling-gate.sh` on the PR body.

### Property List (Phase 0.6b)

1. P1: the required `encryption-posture` check stays green on every PR through 2026-12-10.
2. P2: the ledger row and an audit record state who accepted the risk, when, in what words, until when, under which
   voids, and against which controls measured on which date.
3. P3: the record states that no acceptance of leg 2 can run past 2026-12-10.
4. P4: the acceptance is visible on #10538, where the prior ones were posted.
5. P5: #12742's remaining work is visibly prioritized against the 2026-12-10 hard stop (owner: "let's make sure we
   prioritize the work to avoid extending another time").

### Cut List (Phase 0.6b)

- A new follow-through probe or scheduled alert for the 2026-12-10 hard stop -> P1/P5 -> already covered by the lint's
  built-in 14-day `::warning::` (`EXPIRY_WARN_DAYS = 14`), which fires on every CI run from 2026-11-26, plus the #12742
  comment. (Confirmed by CTO ruling 5.)
- Any lint, `ci.yml`, ruleset or test change -> no property needs it (precedent #12733 changed none).

### Credential coverage (checked at plan time, names only)

`doppler secrets --only-names -p soleur -c prd_terraform` lists `HCLOUD_TOKEN_READONLY`, `BETTERSTACK_QUERY_HOST`,
`BETTERSTACK_QUERY_USERNAME` and `BETTERSTACK_QUERY_PASSWORD`. The 2026-11-13 record body's "no read-only Hetzner
credential available" does not apply to this session.

## Rulings that shape this plan

Full rows are in `knowledge-base/project/specs/feat-one-shot-renew-inngest-leg2-exception/decision-challenges.md`.

- **Sufficiency (CLO, 2026-11-17).** The owner's in-session renewal is sufficient. The ledger change may merge without an
  owner-typed "SIGNED BY OWNER (human, not an agent)" record. The 2026-11-13 record body allows this route ("or a fresh
  in-session instruction the CLO rules sufficient"); the renewal keeps the same terms, has no gap, stays inside the
  2026-11-02 outer limit, and carries the owner's own typed words with a time.
- **Label (CLO).** "Owner renewal before expiry". Not "extension" (the 2026-11-02 conditional extension is dead) and not
  "new acceptance" (nothing lapsed). Ledger label: `OWNER RENEWAL BEFORE EXPIRY, 2026-11-17`.
- **Outer limit (CLO).** 2026-12-10 is permitted and final. Wording everywhere: "After 2026-12-10 the row lapses and is not
  accepted again: no renewal and no new acceptance, by any route." On 2026-12-11 the only cure is ending the plain-HTTP poll
  and measuring that it stopped; weakening the lint, `ci.yml` or the ruleset is not a cure.
- **Where to post (CLO; refines the brief).** The full acceptance comment goes on #12742 (the row's `tracking_issue`, where
  the owner's own words were asked for). #10538 gets a short pointer comment, so the acceptance is still visible where the
  prior one was posted. The ledger cites the #12742 comment. After plan review the CLO folded the separate measurement
  comment into the acceptance comment (cut F2): the acceptance comment is the only public evidence, so it carries every
  value, labelled by who measured and when (CTO 17:04-17:07Z, planner 17:11Z), and the query each came from; the ledger and
  record cite only `ACCEPT_ID`.
- **What stays pending (CLO).** The owner's own words for the 2026-11-13 acceptance (Q-3) stay owner-pending on #12742; they
  no longer gate anything. The owner-typed record "if late" (#12742 item 8, runbook precondition 4, the 2026-11-13 addendum and
  its 12-element draft) is **superseded, not discharged**: no longer required for a replace before 2026-12-10.
- **Legal files edited here (CLO).** Supersession markers in the 2026-11-13 record and in `2026-11-counsel-review-10479.md`
  (plus a correction of its `re_evaluation_triggers` field). Text as filed is never rewritten. PR #12876 touches no legal file.
- **Runbook (CTO collision ruling, CLO wording).** The CLO deferred the collision question to the CTO ("If the CTO rules
  the edit collision-free, the markers may go in this PR instead, using the same wording"). The CTO ruled: edit
  `inngest-server.md` in this PR, append-only, three separate notes, original lines kept, because #12876's planned runbook
  edits are in the confirm sections and its branch changes only plan/spec files today.
- **Merge deadline (CTO).** Target: on main before 2026-11-20T00:00Z. Hard gate: the first merge-group run that starts on or
  after 2026-11-21T00:00Z UTC. This PR is self-healing (its own merge-group run carries 2026-12-10).
- **Void or drift (CLO, re-ruled after the CTO measurement).** A void halts the merge and opens a breach-register
  assessment. A drift halts the merge and goes to the CTO only if the legacy counter rises again after 12, rises with no
  disclosed leg-1 cause, or comes with a void or any other control change (new `boot_id`, `nft_rules`, `nft8443_sha256`,
  served != cert, unit not active). A measurement that cannot be taken does not block: if still impossible at
  2026-11-20T20:00Z, merge with the "not re-measured" wording and a follow-up on #12742.
- **The measured 0 -> 12 leg-1 event (CLO re-ruling).** `legacy_8288_packets` rose 0 -> 12 on 2026-11-16 between
  12:04:32Z and 12:09:34Z and has been flat since. It is a leg-1 residual already disclosed in ledger row 5, not a leg-2
  void, so it does not halt the renewal. It is stated as measured fact (never "legacy_8288=0"), filed as its own issue,
  and assessed in the breach register (not a personal data breach on the measured facts; limbs inconclusive), with the
  determination on record before 2026-11-20T17:07Z. The owner is told in plain words and keeps a veto; no re-acceptance
  is asked.
- **Priority (CLO + owner direction).** The owner's words are recorded verbatim as an instruction to the work, not a term of
  the acceptance. #12742 is raised to `priority/p1-high`. Recommended internal target: the replace measured by 2026-12-03.

## Implementation Phases

All steps run from the worktree root. Nothing here uses SSH, writes to production, dispatches a workflow, or touches PR
#12876, its worktree (`feat-one-shot-12742-public-sdk-url-poll`) or the inngest host replace.

### Phase 1: Re-measure the compensating controls (read-only, before any ledger edit)

The controls were already measured read-only at plan time: by the CTO agent (2026-11-17T17:04-17:07Z) and re-run by the
planner (Hetzner 17:11:41Z; tls-health 17:11Z, 1,330 rows). **The record, the ledger and the comments cite those plan-time
values, each labelled with its time** (CTO fallback ruling: the plan-time reads may be cited with their timestamps). The
work phase does not refill row counts or times from a later run; its own reads only decide whether to halt, and their
result is one line ("re-read <UTC>: unchanged", or the not-read form, see Phase 5.8) in the acceptance comment and the PR
body. This keeps every citation
consistent with its source (learning `2026-10-12-a-ledger-renewal-restated-the-plans-unmeasured-claims-as-facts.md`).

1. Run both `## Measurement commands` once (keep raw output in the scratchpad, never committed).
2. Evaluate the **halt predicate** (the single list, in `## Measurement commands`). On a **void**: stop, do not edit the
   ledger, post the finding on #12742, tell the owner in plain words, send the cure to the CTO, and open a breach-register
   assessment (CLO ruling 9). On a **halting drift**: stop and route to the CTO (CLO re-ruling 9). On `limit_filled ==
   true`: the read is invalid, not a result; raise `--limit` and re-run. On a credential or read failure: retry once, then
   follow the CLO "cannot be done" ruling (keep retrying; if still impossible at 2026-11-20T20:00Z, merge with the not-re-measured wording; the plan-time reads
   stay citable with their times).
3. **The known non-halting fact.** `legacy_8288_packets` rose 0 -> 12 between the 2026-11-16T12:04:32Z and 12:09:34Z rows
   on boot `5319e63a` and has been flat since (measured by the CTO at 17:06Z and re-run by the planner at 17:11Z: 1,330
   rows, `legacy_values ["0","12"]`, `legacy_last 12`). The counter counts plaintext to the legacy :8288 listener from the two
   web hosts' private IPs only (`apps/web-platform/infra/cloud-init-inngest.yml` nft rule `counter name "legacy_8288"`):
   leg 1 (row 5), not this leg. Likely cause (unverified): the web-2 host replace, `apply-web-platform-infra.yml` run
   43862798565 (2026-11-16T12:01:10Z-12:08:55Z), the new-host residual row 5's `does_not_defend` already discloses. CLO
   re-ruling: no halt; state it as measured fact; never write "legacy_8288=0"; never reset the counter (a reboot would stop
   the TLS listener, `fetch_rc=93`, #11081).
4. No separate measurement comment (CLO cut F2, 2026-11-17): the values go into the acceptance comment (Draft C) in
   Phase 5.

### Phase 1b: The leg-1 plaintext event (issue + breach-register assessment; clock runs to 2026-11-20T17:07Z)

Awareness: 2026-11-17T17:07Z (CTO measurement). The Art. 33(1) assessment must be on record before 2026-11-20T17:07Z, so
this phase runs right after Phase 1, before the PR is opened.

1. File a new issue (no existing one covers it: `gh issue list --search "legacy_8288"` returns only #10539, #10545,
   #10205): title "inngest: 12 plaintext packets on the legacy :8288 listener from a web host on 2026-11-16 (leg 1)", labels
   `domain/engineering`, `type/security`, `priority/p2-medium`. Body: the two `dt` values, boot `5319e63a`, run 43862798565,
   the nft rule's source set (web hosts' private IPs only), row 5's disclosed new-host residual, "cause unverified", "packet
   contents not measured", "do not reboot to reset (#11081)", "key rotation is the CTO's call (#10540 closed; the rotate route
   exists)", and `Ref #12742`. Not #10545 (rule count and hash unchanged). Capture `CLASS_R`.
2. Post on that issue, as a dated comment, the CLO determination verbatim (see `## CLO drafts` D): not a personal data breach
   on the measured facts; Art. 33 No; Art. 34 No; evidentiary limbs inconclusive Yes (packet contents and cause not
   measured); reopen trigger. Capture the comment ID as `CLASS_R_COMMENT_ID` (the A7 record links it).
3. The breach-register row is written in Phase 3 (it lands with this PR).

### Phase 2: Ledger row 6 (`scripts/encryption-posture-ledger.json`)

1. Replace exactly the closing text `After 2026-11-20 the row lapses again. No acceptance runs past 2026-12-10.` of
   `connections[6].in_transit.exception.justification` with the CLO's Draft B text (in `decision-challenges.md` and in the
   CLO ruling block below), filling `<CLASS_R>`. `<ACCEPT_ID>` is filled in Phase 5.
2. Set `connections[6].in_transit.exception.expires_on` to `"2026-12-10"`.
3. Leave `tracking_issue` (`#12742`), `reevaluate_when`, `does_not_defend`, `enforced_at`, `tls`, `cert_verification` and
   `disclosed_as` unchanged. Edit with a targeted string replacement (Edit tool), not a JSON re-serialization, so the file's
   1-space indentation and key order stay byte-identical outside the two values.

### Phase 3: New A7 record and supersession markers (legal files)

1. Create `knowledge-base/legal/audits/2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md` from the CLO's Draft A,
   filling the measured values, the comment IDs and the PR number. Follow every bracketed rule in the draft (measured values
   only; the "not re-measured" alternative; the gap alternative if the merge lands after 2026-11-21T00:00Z). Delete the
   bracketed instruction lines from the final file.
2. The question-wording line: the record quotes only the verbatim question text available to this pipeline (in the CLO
   ruling). Keep "It did not name the addresses, the voids or the compensating controls" unless the session transcript shows
   an option description naming 10.0.1.40 or 10.0.1.10:3000/api/inngest, in which case quote that text verbatim too
   (see decision-challenges row "Question wording").
3. In `knowledge-base/legal/audits/2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md`: add the four CLO markers, each
   directly under the sentence it names, plus a frontmatter `addenda` entry "2026-11-17 supersession markers (owner renewal to
   2026-12-10; ledger date fires on the merge of PR #12884)". Do not rewrite any filed text.
4. In `knowledge-base/legal/audits/2026-11-counsel-review-10479.md`: replace inside the `re_evaluation_triggers` value the
   clause "the A7 leg-2 acceptance lapsing (2026-11-20) without an owner-typed record" with "the A7 leg-2 acceptance lapsing
   (2026-12-10, the outer limit; renewed 2026-11-17 from 2026-11-20)", and add the CLO marker under the body bullet "The
   acceptance lapses again after 2026-11-20 unless the owner's replace has run or an owner-typed record exists." Leave the
   dated readings ("accepted to 2026-11-20" in evidence and the consistency table) untouched. Also append, inside the
   double-quoted Q-2 item of `open_follow_ups` (after its last sentence, before its closing quote, same form as Q-1's
   bracket; CLO 2026-11-17, text exact):

   ```text
   [Superseded 2026-11-17 (#12742), as to 'The replace must run by 2026-11-20, or else an owner-typed record beginning SIGNED BY OWNER (human, not an agent) is required': the owner renewed the acceptance before expiry, in session, to 2026-12-10, and the CLO agent ruled that sufficient (2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md; ledger date on the merge of PR #12884). A replace before 2026-12-10 needs no owner-typed record. The outer limit stands: nothing is accepted after 2026-12-10.]
   ```

5. In `knowledge-base/legal/breach-register.md` §Index of determinations, append one dated row (9 cells, header
   `| Date | Event | PA(s) touched | Awareness anchor (Art. 33(1) clock origin) | Determination | Art. 33 engaged? | Art. 34 engaged? | Evidentiary limbs inconclusive? | Canonical source |`)
   after the last dated row: Date 2026-11-17; Event: the 0 -> 12 plaintext packets to the legacy :8288 listener from the web
   hosts' private IPs on 2026-11-16T12:04:32Z-12:09:34Z (leg 1, ledger row 5; cause unverified, coinciding with the web-2
   replace, run 43862798565; packet contents not measured); PA(s): follow the 2026-10-29 Inngest-key row's form ("None
   established. ... Inngest execution plane ...; no PA-level personal-data access ... is shown"); Awareness anchor: 2026-11-17T17:07Z (CTO read-only measurement, not a monitor);
   Determination: not a personal data breach on the measured facts (the network's only members are the controller's own
   servers; nothing shows unauthorised access or disclosure); Art. 33: No; Art. 34: No; Evidentiary limbs inconclusive: Yes
   (packet contents; cause); Canonical source: the backticked path of the new A7 record. **Lint constraint:**
   `scripts/lint-legal-registers.sh` (b) accepts only backticked repo-relative paths in the canonical-source cell, so the
   row cites the A7 record (which carries the determination section and links the issue comment), not the issue comment the
   CLO named. The A7 record is determination-shaped (it says "Art. 33"), so (c) requires exactly this citation anyway.

6. In `knowledge-base/engineering/architecture/decisions/ADR-294-inngest-link-tls-terminator-and-flagged-flip.md`, add a
   blank line and then this blockquote directly after the existing "> **Superseded 2026-11-13 (#10479/#10538, PR #12737):**"
   blockquote (anchor: "the acceptance runs to 2026-11-20, and the 2026-12-10 extension is dead"). Append-only; CLO
   2026-11-17, text exact (MD028 is disabled in `.markdownlint.json`, so adjacent blockquotes lint clean):

   ```markdown
   > **Superseded 2026-11-17 (#12742), as to "the acceptance runs to 2026-11-20":** before that date the owner renewed the leg-2 acceptance in session, on the same terms, to 2026-12-10, and the CLO agent ruled that sufficient (`knowledge-base/legal/audits/2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md`; ledger date on the merge of PR #12884). This is a renewal, not the 2026-11-02 conditional extension, which stays dead. 2026-12-10 is the outer limit; nothing is accepted after it.
   ```

### Phase 4: Runbook supersession notes (`knowledge-base/engineering/operations/runbooks/inngest-server.md`)

Append-only (CTO ruling); wording is the CLO's. Never rewrite or delete an original line. Locate each site by its quoted
text, not by line number (line numbers below are as of `origin/main` e4c5828c5a).

1. After the 2026-11-13 CLO note in the legal bridge-date item (anchor: "the owner acceptance recorded by PR #12733 runs
   to 2026-11-20 only (see [Public sdk_url poll", ~line 2173-2174), add one line, indented to the item (CTO ruling 2 as
   refined after plan review: a one-line pointer, not a restatement):
   `*Superseded 2026-11-17:* the acceptance now runs to 2026-12-10; see the note under precondition 4 of 'Public sdk_url poll (#10538 remedy (c))'.`
2. At the end of the #10538 row of "Tracked follow-ups" (anchor: "The 2026-12-10 extension is dead (CLO): the owner
   acceptance runs to 2026-11-20.", ~line 2180), append the same pointer sentence inside the same table cell. Keep the row
   one line and add no `|`.
3. Directly under the existing precondition-1 note (the indented "> **Superseded 2026-11-17 (#10479), as to \"#10479 is
   closed\":**" blockquote, whose text ends "Items 2 to 4 are unchanged, and so is the 2026-11-20 limit in item 4."), after
   a blank line, at the same indentation, a separate one-line marker (CLO 2026-11-17: each superseded sentence gets its own
   marker; the precondition-4 blockquote's lead stays "as to precondition 4"):

   ```markdown
   > **Superseded 2026-11-17 (#12742), as to "and so is the 2026-11-20 limit in item 4":** that limit is superseded; see the marker under item 4 and `knowledge-base/legal/audits/2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md`. Items 2 and 3 are unchanged.
   ```

4. After replace precondition 4 (anchor: "4. If the replace lands after 2026-11-20, the owner-typed record the CLO ruling
   requires exists first", ~lines 2704-2705), add an indented blockquote, keeping the blank line that follows:

   ```markdown
   > **Superseded 2026-11-17 (#12742), as to precondition 4:** met by the owner's 2026-11-17 renewal before expiry (CLO ruling 2026-11-17): the owner-typed record is no longer required for a replace before 2026-12-10 (superseded, not discharged). After 2026-12-10 no record of any kind extends ledger row 6; the replace and its measurements must land before 2026-12-11T00:00Z.
   ```


### Phase 5: GitHub comments, issue marker and label

The draft PR already exists: #12884 (`WIP: feat-one-shot-renew-inngest-leg2-exception`, opened by the pipeline), so every
`PR #` reference is filled as #12884 from the start and only the comment IDs are filled late.

Order is fixed by the CLO ruling as revised after plan review: PR #12884 (exists) -> acceptance comment on #12742 ->
pointer on #10538 -> commit the comment IDs into the ledger and the record. The leg-1 determination comment (Phase 1b) is
separate and must be posted before 2026-11-20T17:07Z whatever the merge time.

1. Relabel #12742 first, so the acceptance comment's "Priority raised to p1-high" states a done act:
   `gh issue edit 12742 --remove-label priority/p2-medium --add-label priority/p1-high`.
2. Post the CLO Draft C acceptance comment on #12742 (fill `<CLASS_R>` and the re-read line from Phase 1). Capture
   `ACCEPT_ID`.
3. Post the CLO Draft C pointer comment on #10538 (fill `ACCEPT_ID`).
4. Re-read #12742's body immediately before editing, then append the CLO marker line directly under item 8 (do not rewrite
   item 8): "Superseded 2026-11-17 (CLO): renewed before expiry to 2026-12-10 in session; the owner-typed record is no longer
   required for a replace before 2026-12-10. No acceptance may run past 2026-12-10. See comment <ACCEPT_ID>." Use
   `gh issue view 12742 --json body` -> edit locally -> `gh issue edit 12742 --body-file`, and diff old vs new body to prove
   only that one line was added.
5. Post the prioritization comment on #12742 (wording and order per the CTO ruling, see `## Priority comment on #12742`).
6. Commit `ACCEPT_ID`, `CLASS_R` and `CLASS_R_COMMENT_ID` into the ledger justification and the records; push.
7. **Tell the owner (CLO re-ruling (c)), in the session's closing message, without asking them to accept again**, in these
   words: "One thing changed since 13 Nov. On 16 Nov, for about five minutes, our own web servers sent 12 unencrypted
   messages to the background-jobs server's old port. This was most likely while the second web server was being rebuilt,
   and it has not happened again. No outside machine is on that network. It does not change what you accepted. If you want
   to withdraw the renewal because of it, say so."
8. **Before merge** (CLO re-ruling (a), conditions of 2026-11-17): on merge day, as the last step before enqueueing, re-run
   measurements (a) and (b) and apply the halt predicate (every void check and every halt condition). Write "re-read
   <UTC>: unchanged" in the PR body only if every value equals its plan-time value; never write "unchanged" over a value
   that was not re-read. Any difference halts the merge, is written out, and goes to the CTO. If a source cannot be read,
   write "re-read <UTC>: <source> not read (<reason>)"; the ruling-9 fallback then applies: merge no earlier than
   2026-11-20T20:00Z and post a #12742 follow-up to measure within 48 hours.

### Phase 6: Verify

Run AC1-AC9 (and AC11 on the PR body).

## Measurement commands

Ruled by the CTO; both were run read-only by the CTO (17:04-17:07Z) and re-run by the planner (17:11Z) and work as written.
No secret is printed. Write the jq program to the session scratchpad, never to the repo.

**(a) Hetzner servers and networks** (token on stdin, `sh -c` so `$HCLOUD_TOKEN_READONLY` expands inside Doppler's env):

```bash
doppler run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN_READONLY --no-exit-on-missing-only-secrets -- sh -c '[ -n "$HCLOUD_TOKEN_READONLY" ] || { echo missing-token; exit 3; }; h(){ printf "header = \"Authorization: Bearer %s\"\n" "$HCLOUD_TOKEN_READONLY" | curl --disable --noproxy "*" -sS --fail --config - --max-time 30 "https://api.hetzner.cloud/v1/$1?per_page=50"; }; s=$(h servers) || { echo read-failed; exit 2; }; n=$(h networks) || { echo read-failed; exit 2; }; jq -n --argjson s "$s" --argjson n "$n" "{at:(now|todate), servers_total:\$s.meta.pagination.total_entries, networks_total:\$n.meta.pagination.total_entries, servers:[\$s.servers[]|{id,name,status,priv:[.private_net[]|\"\\(.network)=\\(.ip)\"]}]|sort_by(.priv), network:[\$n.networks[]|{id,name,ip_range,subnets:[.subnets[].ip_range],servers_attached:(.servers|length),lbs:(.load_balancers|length),vswitch:.expose_routes_to_vswitch}], attached_ids_all_owned:(([\$n.networks[].servers[]]|sort)==([\$s.servers[]|select(.private_net|length>0)|.id]|sort))}"'
```

Pass: `servers_total == 5`; names and IPs exactly `soleur-web-platform` 10.0.1.10, `soleur-web-2` .11, `soleur-git-data` .20,
`soleur-registry` .30, `soleur-inngest` .40; `networks_total == 1`; the only subnet `10.0.1.0/24`; `servers_attached == 5`;
`lbs == 0`; `vswitch == false`; `attached_ids_all_owned == true`. Planner run 2026-11-17T17:11:41Z: all pass (network
12414183 `soleur-private`).

**(b) tls-health since the last measurement:**

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2026-11-13T00:43:00Z --grep stage=tls-health --limit 3000 2>/dev/null | jq -s -f "$SCRATCH/tls.jq" -c
```

`$SCRATCH/tls.jq`:

```jq
[.[] | .raw | (fromjson? // empty) | select(.marker=="SOLEUR_INNGEST_BOOT_STAGE" and .stage=="tls-health" and .shipper=="cloud-init-phone-home") | . as $r | ($r.detail|[splits(" ")]|map(select(test("="))|capture("^(?<k>[^=]+)=(?<v>.*)$")|{key:.k,value:.v})|from_entries) + {dt:$r.dt,host:$r.host}] | sort_by(.dt) as $x | {rows:($x|length), limit_filled:(($x|length)>=3000), first:$x[0].dt, last:$x[-1].dt, hosts:($x|map(.host)|unique), boot_ids:($x|map(.boot_id)|unique), units:($x|map(.unit)|unique), listeners:($x|map(.listener)|unique), nft_rules:($x|map(.nft_rules)|unique), nft8443:($x|map(.nft8443_sha256)|unique), served_eq_cert:($x|all(.served_sha256==.cert_sha256 and (.served_sha256|length)==64)), min_notafter:($x|map(.notafter_days|tonumber)|min), legacy_values:($x|map(.legacy_8288_packets)|unique), legacy_first_nonzero:([$x[]|select(.legacy_8288_packets!="0")][0].dt), legacy_last:$x[-1].legacy_8288_packets, tls_first:$x[0].tls_8443_packets, tls_last:$x[-1].tls_8443_packets, max_gap_s:([range(1;$x|length) as $i | (($x[$i].dt|fromdate)-($x[$i-1].dt|fromdate))]|max), fetch_rc:($x|map(.fetch_rc)|unique)}
```

**Halt predicate (the only list; Phase 1 and the pre-merge re-read both use it).** Halt if any of:
`hosts != ["soleur-inngest"]`; more than one `boot_id` or a `boot_id` other than `5319e63a`; `units != ["active"]`;
`listeners != ["1"]`; `nft_rules != ["7"]`; `nft8443 != ["1d224d030f2deb1d65007f876e3bf527df443f61beb4e46220334e363358e4cf"]`
(the exact 2026-11-13 value); `served_eq_cert != true`; `legacy_last` above `"12"` or `legacy_values` other than
`["0","12"]` (the known, non-halting leg-1 event is exactly 0 then 12). **And** halt on any miss of the (a) pass list
(`servers_total` 5, the exact five names and IPs, `networks_total` 1, subnet `10.0.1.0/24`, `servers_attached` 5, `lbs` 0,
`vswitch` false, `attached_ids_all_owned` true): that check is what tests the record's voids (CTO, 2026-11-17).

**Read validity (not a control result).** `limit_filled == true` means the newest rows may have pushed out older ones:
raise `--limit` and re-run (about 288 rows a day; ~2,300 by 2026-11-21).

**Reported, not halting.** `max_gap_s` (a value above 400 s, the soak probe's `MAX_GAP_SEC` in
`scripts/followthroughs/inngest-tls-soak-10136.sh`, means at least one missed emit; report it), `min_notafter` (certificate
days left; report it), `tls_first`/`tls_last` (the TLS positive control; report the rise), `fetch_rc` (`["0","93"]` since
2026-11-13/14, #11081, not an A7 control).

Planner run 17:11Z: 1,330 rows, `limit_filled false`, `max_gap_s 320`, one host, boot `5319e63a`, unit active, listener 1,
`nft_rules 7`, hash unchanged, served == cert, `min_notafter 3621`, `legacy_values ["0","12"]`, `legacy_last 12`, `tls_8443`
22342 -> 312569, `fetch_rc ["0","93"]`. No halt.

## CLO drafts (verbatim, with the re-ruling substitutions)

The work phase fills every `<...>` and deletes every bracketed instruction line. These are agent drafts, not signatures.

### A. New record `knowledge-base/legal/audits/2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md`

The full draft is in `knowledge-base/project/specs/feat-one-shot-renew-inngest-leg2-exception/clo-draft-a7-record.md`
(moved out of this plan so its `## ` headings are not read as plan sections). Copy it to the record path, fill every
`<...>`, write the section "Leg-1 plaintext event: breach assessment" from D below, and delete every bracketed
instruction line.

### Markers for the 2026-11-13 record

Placement (markdown-safe, so agent text never joins the owner's quote or splits a list): the "I will not extend past that
date" marker goes after the blank line that follows the owner's verbatim blockquote, before "The owner chose the date…";
a marker for a sentence inside a list bullet goes after the whole bullet, with a blank line before it, indented two spaces
(`  > …`). Run markdownlint (MD027, MD032) on the file. Also a frontmatter `addenda` entry: "2026-11-17 supersession markers (owner
renewal to 2026-12-10; ledger date fires on the merge of PR #12884)".

```markdown
> **Superseded 2026-11-17 (#12742), as to "After 2026-11-20 the row lapses again":** before that date the owner renewed this acceptance in session, on the same terms, until 2026-12-10, and the CLO agent ruled the in-session renewal sufficient (`2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md`). The ledger row carries 2026-12-10 on the merge of PR #12884. The second sentence stands: this renewal is the "fresh in-session instruction the CLO rules sufficient".

> **Superseded 2026-11-17 by the owner's own act, as to "I will not extend past that date":** the owner renewed to 2026-12-10 in session, typing "1 but let's make sure we prioritize the work to avoid extending another time" (`2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md`).

> **Superseded 2026-11-17 (#12742), as to "If the owner's act lands after 2026-11-20, a record that the owner types … is required":** no longer required for a replace before 2026-12-10, which the 2026-11-17 renewal covers. Superseded, not discharged. After 2026-12-10 no record of any kind extends the row.

> **Superseded 2026-11-17 (#12742), as to "Required only if … lands after 2026-11-20":** no longer required (see the 2026-11-17 renewal record); kept as filed, it records nothing.
```

### Marker for `2026-11-counsel-review-10479.md` (under the body bullet "The acceptance lapses again after 2026-11-20…")

```markdown
  > **Superseded 2026-11-17 (#12742), as to "The acceptance lapses again after 2026-11-20 unless the owner's replace has run or an owner-typed record exists":** the owner renewed the acceptance before expiry, in session, to 2026-12-10, and the CLO agent ruled that sufficient (`2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md`; ledger date on the merge of PR #12884). It lapses after 2026-12-10 and is not accepted again; no record of any kind extends it.
```

### B. Ledger row 6 `exception.justification`

Replace exactly `After 2026-11-20 the row lapses again. No acceptance runs past 2026-12-10.` with (one JSON string; escape the
inner double quotes as `\"`):

```text
OWNER RENEWAL BEFORE EXPIRY, 2026-11-17 (not the 2026-11-02 conditional extension, which is dead): before the 2026-11-20 acceptance ran out, the owner renewed it in session, on the same terms, until 2026-12-10, at about 16:55Z, choosing 'Renew until 10 Dec' and typing: "1 but let's make sure we prioritize the work to avoid extending another time". This act supersedes the owner's 2026-11-13 "I will not extend past that date". CLO ruling 2026-11-17: the in-session renewal suffices; no owner-typed record is required for it. Agent-filed, not a signature (record knowledge-base/legal/audits/2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md). The 2026-11-02 voids stand. Controls re-measured 2026-11-17T17:04-17:11Z, read-only (values in the record and in #12742 comment <ACCEPT_ID>): 5 servers, all Jikigai's, one network, nothing foreign attached: no void. legacy_8288 rose 0->12 between 2026-11-16T12:04:32Z and 12:09:34Z, flat since; leg 1, from the web hosts' own IPs, not this leg and not a foreign peer; #<CLASS_R>; not a personal data breach on the measured facts. Accepted until 2026-12-10, the outer limit set on 2026-11-02. After 2026-12-10 the row lapses and is not accepted again: no renewal and no new acceptance, by any route.
```

- Merge after 2026-11-21T00:00Z: insert before "Accepted until 2026-12-10" (CLO 2026-11-17; a PR cannot carry its own
  merge time): "The ledger recorded the renewal only at the merge of PR #12884 (the merge commit's timestamp is the
  record), so the required encryption-posture check failed from 2026-11-21T00:00Z until then. Recorded, not backdated."
- Trimmed after plan review (CLO cut F3): the server list, row count and hash live in the record and the acceptance
  comment, not in the ledger cell; the void result, the full legacy clause and the measurement times stay.
- `expires_on` -> `"2026-12-10"`. `reevaluate_when` unchanged.

### C. Comments

**#12742, acceptance (PR #12884 exists; this is the only public evidence of the re-measurement, so it carries every value):**

```markdown
Posted by a Claude Code agent session, 2026-11-17. Not the owner's signature.

**Owner renewal before expiry of the leg-2 accepted risk, to 2026-12-10 (agent-posted on the owner's in-session answer).** On 2026-11-13 the owner accepted the leg-2 poll (10.0.1.40 to 10.0.1.10:3000/api/inngest, plain HTTP on 10.0.1.0/24) until 2026-11-20 (#10538 comment 6846245981). The replace this issue tracks cannot finish by then. On 2026-11-17, at about 16:55Z, the owner was shown this question in session:

> Background-jobs link: on 13 Nov you accepted, until 20 Nov, that the background-jobs server keeps calling the app over unencrypted HTTP on the private network. The fix (switching it to the public encrypted address and replacing that server) is still a draft and its safety checks are not green, so it cannot be done by the 20th. If nothing is accepted, the required encryption check fails on every PR from the 20th. Renew the acceptance until 10 Dec? Your earlier record says 10 Dec is the last date that can ever be accepted.

The owner chose "Renew until 10 Dec" and typed, verbatim:

> 1 but let's make sure we prioritize the work to avoid extending another time

- **Terms:** the same as 13 Nov; the question did not restate them. The 2026-11-02 voids stand: a server beyond the five on 10.0.1.0/24 or any public or cross-network exposure of the poll; any non-Jikigai peer; `--sdk-url` at the public host while Cloudflare to origin is flexible.
- **Controls re-measured read-only today.** Hetzner `GET /v1/servers` and `GET /v1/networks` with the read-only token `HCLOUD_TOKEN_READONLY`, read by the CTO agent at 17:04Z and 17:07Z and by the planner at 17:11:41Z: 5 servers, all ours (soleur-web-platform 10.0.1.10, soleur-web-2 .11, soleur-git-data .20, soleur-registry .30, soleur-inngest .40); one network, soleur-private (12414183), only subnet 10.0.1.0/24, 5 servers attached, their ids equal to our own server ids, 0 load balancers, `expose_routes_to_vswitch` false: no void. Better Stack tls-health rows for 2026-11-13T00:43Z to 2026-11-17T17:07Z, read by the CTO agent at 17:06Z (1,329 rows) and by the planner at 17:11Z (1,330 rows): one host, one boot (5319e63a), unit active, listener 1, `nft_rules=7`, `nft8443_sha256` unchanged from 13 Nov (1d224d03…58e4cf), served certificate hash equal to the issued one, max gap 320 s. Work-phase read before this comment: <Phase 1 re-read line>. The merge-day re-read is recorded in the body of PR #12884.
- **One change since 13 Nov:** on 16 Nov, between 12:04:32Z and 12:09:34Z, `legacy_8288` rose from 0 to 12: 12 unencrypted packets reached the scheduler's old port from our own web servers, most likely while the second web server was being rebuilt (run 43862798565; cause not verified, packet contents not measured). It has stayed at 12 since. That is the other direction (app to scheduler, leg 1), it is already disclosed in ledger row 5, and it is not a stranger on the network. The counter is not reset (a reboot would stop the TLS listener, #11081). Tracked in #<CLASS_R>; assessed as not a personal data breach on the measured facts.
- This supersedes, by the owner's own act, the owner's 2026-11-13 statement "I will not extend past that date".
- **2026-12-10 is the outer limit.** After 2026-12-10 the row lapses and is not accepted again, by any route. If ledger row 6 is not converted by then, the required `encryption-posture` check fails on every PR from 2026-12-11T00:00Z. The only cure is ending the plain-HTTP poll and measuring that it stopped.
- **CLO ruling 2026-11-17:** the in-session renewal suffices. Item 8's owner-typed record and the runbook's replace precondition 4 are no longer required for a replace before 2026-12-10 (superseded, not discharged); the runbook lines carry Superseded notes in PR #12884. The owner's own words for the 2026-11-13 acceptance stay owner-pending here.
- **Owner instruction:** prioritize this issue so no further extension is needed. Priority raised to p1-high.

Record and ledger change: PR #12884 (`knowledge-base/legal/audits/2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md`). No lint, workflow or ruleset change.
```

**#10538, pointer only:**

```markdown
Posted by a Claude Code agent session, 2026-11-17. Not the owner's signature.

The 2026-11-13 acceptance recorded in comment 6846245981 was renewed by the owner before expiry, on the same terms, until 2026-12-10, the outer limit after which nothing is accepted again. Record: #12742 comment <ACCEPT_ID> and PR #12884. This issue stays open and may close only as "not planned, superseded by #12742".
```

### D. Breach determination (CLO, 2026-11-17; for the A7 record section and the #<CLASS_R> comment)

- Awareness: 2026-11-17T17:07Z (CTO read-only measurement). The 72 hours run to 2026-11-20T17:07Z.
- Determination: not a personal data breach on the measured facts. Art. 33: No. Art. 34: No. Nothing shows unauthorised
  access or disclosure; the only members of the network are the controller's own servers; Hetzner runs the network as
  processor.
- Evidentiary limbs inconclusive: Yes. Not measured: what the packets contained (by code read they may carry
  `INNGEST_EVENT_KEY` and event payloads, which can include personal data) and the cause.
- Key rotation is not legally required on these facts; whether to rotate is the CTO's call (#10540; row 5 already says a
  sniffed key stays valid until it is rotated).
- Reopen trigger: any later evidence of a foreign peer, or exposure of the network, during 2026-11-16T12:04-12:10Z.
- Row 5's ledger cell is not edited: its disclosure already covers the event.

## Priority comment on #12742

Posted after the acceptance comment (provenance line first). Content (CTO ruling 7, owner's words as authority):

- The owner's words, verbatim, and the label change `priority/p2-medium` -> `priority/p1-high`.
- Hard stop: ledger row 6 lapses for good after 2026-12-10; the required check fails every PR from 2026-12-11T00:00Z; the
  lint's `::warning::` starts on 2026-11-26; internal target: row 6 converted on main by 2026-12-03.
- Order of the remaining items: (1) item 1 sync-evidence probe field (draft PR #12876); (2) item 3 hop-1 measurement
  (replace precondition 3); (3) item 2 the owner's `inngest-host-replace` (item 8 is now a met gate, not a step); (4) item 4
  private-URL poll measured as stopped; (5) item 5 ledger row 6 converted (target 2026-12-03); (6) item 7 published wording
  (CLO); (7) item 6 C4; (8) item 9 stale comment when that file next changes.
- No edit to PR #12876 or its branch; this is a comment only.

## Files to Edit

- `scripts/encryption-posture-ledger.json` (row 6 `justification` closing text and `expires_on` only)
- `knowledge-base/legal/audits/2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md` (four markers, one `addenda` entry)
- `knowledge-base/legal/audits/2026-11-counsel-review-10479.md` (`re_evaluation_triggers` clause, Q-2 inline bracket, one
  marker)
- `knowledge-base/legal/breach-register.md` (one dated row)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` (four append-only notes)
- `knowledge-base/engineering/architecture/decisions/ADR-294-inngest-link-tls-terminator-and-flagged-flip.md` (one append-only
  Superseded note, CLO 2026-11-17)

## Files to Create

- `knowledge-base/legal/audits/2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md`
- Pipeline-written (not plan-edited): `knowledge-base/project/specs/feat-one-shot-renew-inngest-leg2-exception/tasks.md`,
  `decision-challenges.md`, and this plan; any `session-state.md` the pipeline writes.

GitHub-side acts (no file): the acceptance and priority comments and the item-8 marker on #12742; the pointer
on #10538; the new leg-1 event issue and its determination comment; the #12742 label change.

## Open Code-Review Overlap

None. Checked the open `code-review` issues' bodies for `scripts/encryption-posture-ledger.json`,
`knowledge-base/legal/audits/2026-11-13-a7-leg2-owner-extension-inngest-sdk-url-poll.md` and `knowledge-base/legal/audits/`:
no match.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly; but a wrong ledger date either freezes every merge
  from 2026-11-21 (fixes stop shipping) or, if renewed without the owner, misstates the encryption posture that the
  Privacy Policy and DPA wording about traffic "between our web servers and our job scheduler" rely on.
- **If this leaks, the user's data is exposed via:** no new exposure is created; the existing leg-2 poll carries an
  HMAC-signed request and public function metadata (no user content, no key material) on the private network. The leg-1
  event recorded here may have carried `INNGEST_EVENT_KEY`-authenticated event sends from our own web hosts; it is
  assessed in the breach register.
- **Brand-survival threshold:** aggregate pattern
- **Threshold decision (challengeable):** the record is posture-wide (every user's processing relies on the disclosed
  wording), but this change creates no new path to any one user's data, so it is not a single-user incident.

## Observability

```yaml
liveness_signal:
  what: the required CI check `encryption-posture` (ci.yml job, `python3 scripts/lint-encryption-posture.py --repo-sweep`)
  cadence: every PR and merge-group run
  alert_target: the PR's required-check status (red blocks merge); the sweep prints a ::warning:: from 14 days before expires_on
  configured_in: .github/workflows/ci.yml job encryption-posture; scripts/lint-encryption-posture.py check_exception_block
error_reporting:
  destination: GitHub Actions check output on every PR
  fail_loud: yes, the check fails (exit 1) once expires_on is in the past
failure_modes:
  - mode: the row lapses (merge after 2026-11-21T00:00Z, or no conversion by 2026-12-10)
    detection: lint FAIL line naming row 6 "expires_on ... is in the past"
    alert_route: required check red on every PR; ::warning:: from 2026-11-26
  - mode: a void on the private network (a foreign server, a load balancer, exposure)
    detection: the Hetzner servers+networks read in this plan (attached_ids_all_owned false, servers_total not 5)
    alert_route: work-phase halt, finding posted on #12742, CTO and CLO routing
  - mode: legacy :8288 plaintext rises again
    detection: tls-health rows in Better Stack (legacy_8288_packets above 12)
    alert_route: work-phase halt before merge; the new leg-1 event issue
logs:
  where: GitHub Actions logs for the check; Better Stack source 2457081 for tls-health rows
  retention: GitHub default run retention; Better Stack plan retention
discoverability_test:
  command: grep -c -e '"expires_on": "2026-12-10"' scripts/encryption-posture-ledger.json
  expected_output: "1"
```

The probe prints `0` (exit 1) on `origin/main` today and `1` after the change; no other row carries 2026-12-10 (the
others are 2026-12-31 and 2027-01-31).

## Encryption Posture

This plan changes no store and adds no connection. It renews the exception of an existing connection (ledger
`connections[6]`), whose posture is unchanged:

```yaml
in_transit:
  - connection: dedicated inngest host -> web-platform app sdk_url poll (10.0.1.10:3000/api/inngest; leg 2)
    tls: none (plain HTTP on the Hetzner private network, every 60 s)
    cert_verification: off
    does_not_defend: a passive on-net attacker on 10.0.1.0/24 could read the poll's HMAC-signed request and the public function metadata it returns (no user content, no key material, by code read); unchanged by this plan
    disclosed_as: not-publicly-claimed
exception:
  justification: owner renewal before expiry, 2026-11-17, in session, CLO-ruled sufficient; voids of 2026-11-02 stand; controls re-measured 2026-11-17
  tracking_issue: "#12742"
  reevaluate_when: unchanged (the owner's inngest-host-replace runs and the private-URL poll is measured as stopped, a non-Jikigai peer or tenant joins 10.0.1.0/24, or the poll is exposed)
  expires_on: 2026-12-10
```

## Infrastructure (IaC)

Not applicable: no server, service, secret, DNS record, firewall rule or vendor account is created or changed. The
Hetzner and Better Stack reads are read-only measurements.

## Architecture Decision (ADR/C4)

None. No architectural decision is made or changed: the remedy (c) decision and the leg-1/leg-2 split stand (ADR-294,
2026-11-13 rulings). ADR-294 gets only an append-only dated Superseded note on a stale date (CLO), not a decision change. C4 checked: the `inngest -> api` edge stays as modeled until #12742 item 6.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "[brief] Renew the leg-2 accepted-risk exception ... (encryption-posture ledger row 6, scripts/encryption-posture-ledger.json, expires_on 2026-11-20) to 2026-12-10" | Phase 2; Files to Edit (ledger) | mapped |
| 2 | "[brief] Must merge before 2026-11-20T00:00Z or the required encryption-posture check fails on every PR." | Rulings (merge deadline); Acceptance Criteria | mapped (gate time corrected to 2026-11-21T00:00Z; target kept) |
| 3 | "[brief] write a new A7 audit record under knowledge-base/legal/audits/" | Phase 3.1; Files to Create | mapped |
| 4 | "[brief] re-measure the compensating controls read-only exactly as the 2026-11-13 record did" | Phase 1; Measurement commands | mapped |
| 5 | "[brief] keep the 2026-11-02 voids, and state that no further renewal is possible after 2026-12-10" | CLO draft A (Voids, No further renewal); draft B | mapped |
| 6 | "[brief] Post the acceptance on #10538 like the prior one." | Phase 5.1-5.2 | mapped (CLO: full comment on #12742 plus pointer on #10538) |
| 7 | "[brief] tracking_issue stays #12742." | Phase 2.3 | mapped |
| 8 | "[brief] Do NOT touch the parallel in-flight work on #12742 (draft PR #12876, worktree feat-one-shot-12742-public-sdk-url-poll) or the inngest host replace" | Implementation Phases preamble; Acceptance Criteria | mapped |
| 9 | "[brief] Ref #12742 and Ref #10538, never Closes." | Acceptance Criteria (PR body) | mapped |
| 10 | "[owner] let's make sure we prioritize the work to avoid extending another time" | Phase 5.4-5.5; Priority comment | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Ledger edit | asks 1, 7 | asked |
| New A7 record | ask 3 | asked |
| Markers in the 2026-11-13 record and counsel-review-10479 | — | inferred — justification: CLO ruling 8; leaving "lapses again after 2026-11-20" unmarked would make the legal records contradict the ledger |
| Runbook notes in inngest-server.md | — | inferred — justification: CTO ruling 2; precondition 4 would otherwise gate the replace on a superseded requirement |
| Breach-register row and leg-1 event issue | — | inferred — justification: CLO re-ruling (d); the re-measurement (ask 4) surfaced a plaintext event whose Art. 33(1) assessment must be recorded within 72 hours |
| Acceptance comment on #12742 (carrying the measurements); pointer on #10538 | ask 6 | asked (location per CLO ruling 6) |
| #12742 item-8 marker | — | inferred — justification: CLO ruling 8; item 8 otherwise demands a record the CLO ruled no longer required |
| #12742 label and priority comment | ask 10 | asked |
| Telling the owner about the 0->12 event | — | inferred — justification: CLO re-ruling (c); the owner keeps a veto over a renewal whose evidence changed |

### Split Assessment

- Subsystems touched: 3 — `scripts/` (ledger data), `knowledge-base/legal/`, `knowledge-base/engineering/operations/`
- Planned files: 7 | Estimated changed lines: about 200 (mostly the new record)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `git diff origin/main...HEAD -U0 -- scripts/encryption-posture-ledger.json` shows exactly two changed lines, row 6's
  `justification` and `expires_on`, and `jq -S 'del(.connections[6].in_transit.exception.justification, .connections[6].in_transit.exception.expires_on)'`
  is byte-equal on `origin/main` and on the branch. `jq empty` passes.
- [ ] AC2: `jq -r '.connections[6].in_transit.exception | .expires_on, .tracking_issue' scripts/encryption-posture-ledger.json`
  prints `2026-12-10` and `#12742`.
- [ ] AC3: `python3 scripts/lint-encryption-posture.py --repo-sweep --today <D>` exits 0 for D = 2026-11-17, 2026-11-21 and
  2026-12-10, and exits 1 for D = 2026-12-11 with exactly one failing check, naming row 6.
- [ ] AC4: the justification contains "OWNER RENEWAL BEFORE EXPIRY, 2026-11-17", the owner's typed words verbatim, the CLO
  sufficiency ruling, the `ACCEPT_ID` comment ID, "no void", "legacy_8288 rose 0->12", and ends with "no renewal and
  no new acceptance, by any route."; the substring after "OWNER RENEWAL BEFORE EXPIRY, 2026-11-17" contains no
  `legacy_8288=0` (`jq -r '.connections[6].in_transit.exception.justification' scripts/encryption-posture-ledger.json | sed -n
  's/.*OWNER RENEWAL BEFORE EXPIRY, 2026-11-17//p' | grep -c 'legacy_8288=0'` prints 0), and the whole string's count of `legacy_8288=0` equals origin/main's (2, the dated 2026-11-02 and
  2026-11-13 readings, which stay as filed).
- [ ] AC5: the new record exists, follows draft A with every `<...>` filled and no bracketed instruction left
  (`grep -nE '<[A-Za-z_][A-Za-z_ ]*>|PR #N\b|^\[|\[(If|Write) ' <record>` prints nothing; run after Phase 5.6 fills
  `ACCEPT_ID`), quotes both owner
  sentences, keeps the voids verbatim, carries the breach section and the no-further-renewal section.
- [ ] AC6: the 2026-11-13 record and counsel-review-10479 diffs are additions only, except one frontmatter line in each
  (`git diff -U0 origin/main...HEAD -- <both files> | grep -E '^-[^-]' | grep -vE '^-(addenda|re_evaluation_triggers|open_follow_ups): '`
  prints nothing: the 2026-11-13 record's `addenda:` line gains an entry, counsel-review-10479's `re_evaluation_triggers:`
  clause is replaced and its `open_follow_ups:` Q-2 item gains the bracket).
- [ ] AC7: `inngest-server.md` and ADR-294 diffs are additions only, except the #10538 row of "Tracked follow-ups" (an
  in-cell append: its `-` line is a prefix of its `+` line), checked by `git diff -U0 origin/main...HEAD -- <both files> |
  grep -E '^-[^-]' | grep -vF '| #10538 | the'` printing nothing; the four runbook notes sit at their four
  anchors and the ADR-294 note directly after the 2026-11-13 blockquote.
- [ ] AC8: `breach-register.md` gains exactly one dated row with 9 cells and a backticked canonical-source path that
  resolves; `bash scripts/lint-legal-registers.sh` exits 0 (run after `git add` of the new record: the lint runs
  `git ls-files --error-unmatch` on each cited path).
- [ ] AC9: `bash scripts/lint-encryption-posture.test.sh` passes; `bash scripts/markdown-lint.sh` passes on every changed
  `.md` file (`knowledge-base/project/` is outside that lint's scope by `.markdownlintignore`).
- [ ] AC10: GitHub: on #12742 the acceptance comment (with every measured value, labelled by reader and time) and the priority comment exist with the provenance line, the item-8
  marker was added with no other body change (old/new body diff is one added line), and the label is `priority/p1-high`;
  on #10538 the pointer comment exists; the leg-1 event issue exists with its determination comment dated before
  2026-11-20T17:07Z.
- [ ] AC11: the PR body says `Ref #12742` and `Ref #10538` and contains no `Closes`, `Fixes` or `Resolves` keyword; it
  carries a `## Changelog` section; `technical-ruling-gate.sh --pr-body` passes.
- [ ] AC12: no file under the #12876 branch's scope changed (`git diff --name-only origin/main...HEAD` lists only the seven files
  above plus this feature's plan/spec artifacts), and no workflow was dispatched.
- [ ] AC13: merged to main before 2026-11-20T00:00Z (target); in any case before the first merge-group run on or after
  2026-11-21T00:00Z, or the record and ledger carry the gap wording.

## Domain Review

**Domains relevant:** Legal, Engineering

### Legal

**Status:** reviewed
**Assessment:** CLO agent ruled (2026-11-17, two rounds): the in-session renewal suffices; label "owner renewal before
expiry"; 2026-12-10 final; full acceptance on #12742 with a pointer on #10538; supersession markers in the legal records;
the 0->12 leg-1 event does not halt the renewal but needs a breach-register assessment (not a personal data breach on the
measured facts; limbs inconclusive) recorded before 2026-11-20T17:07Z; the owner is told in plain words and keeps a veto.

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled (2026-11-17): target 2026-11-20T00:00Z, hard gate 2026-11-21T00:00Z; runbook notes in this
PR, append-only; servers+networks read with an id-set ownership check; tls-health read with exact hash comparison and the
legacy counter as a delta; no new guardrails; the verification set; the #12742 item order and the p1 label. Measured the
0->12 legacy counter rise.

No Product/UX surface: no UI file is created or edited.

## Test Scenarios

The acceptance criteria are the tests (AC1-AC9, run in Phase 6); the CTO-ruled checks are AC1 (structural `jq -S` diff and
two-line `git diff -U0`) and AC3 (four lint dates). The pre-merge tls-health re-read is Phase 5.8.

## Risks

- **Merge slips past 2026-11-21T00:00Z.** Every other PR's required check goes red until this merges; this PR's own run
  stays green. Mitigation: target 2026-11-20T00:00Z; gap wording ready in drafts A and B.
- **Concurrent edit of #12742's body** by the #12876 session. Mitigation: re-read immediately before editing and diff.
- **Runbook merge conflict with #12876.** Mitigation: append-only, separated insertions; #12876 edits other sections.
- **The legacy counter rises again before merge.** Halts the merge (CLO re-ruling (a)); route to the CTO.
- **The 72-hour assessment window** (to 2026-11-20T17:07Z): the determination comment on the new issue is posted in Phase 1b,
  independent of the PR's merge time.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6.
- Never write "legacy_8288=0" for 2026-11-17 anywhere; the value is 12 (CLO re-ruling (c)).
- Never reboot or restart anything on the Inngest host to reset the counter (`fetch_rc=93`, #11081; and
  `inngest-nftables.service` is not idempotent, #10545).
- `doppler run -- cmd "$VAR"` expands in the caller's shell; the Hetzner command wraps in `sh -c '...'` on purpose.
- The breach-register canonical-source cell accepts only backticked repo paths (`lint-legal-registers.sh` (b)); an issue
  comment URL there fails the required `test` context.
- Edit the ledger with a targeted string replacement; `jq` re-serialization changes the file's layout (2-space vs 1-space).
- The owner's question text is quoted verbatim from the CLO ruling; do not paraphrase it into the record, and do not add the
  addresses to the question unless the transcript shows them.
- `decision-challenges.md` rows start `Ruled by CTO agent, <date>:` or `Ruled by CLO agent, <date>:`; run
  `technical-ruling-gate.sh --branch` after any edit.
- Post comments in the CLO's order (PR #12884, acceptance, pointer), then commit the IDs; a record citing a comment
  that does not exist yet is a false citation.
