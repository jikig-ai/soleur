---
title: "CLO determination — Art. 4(12) / Art. 32 assessment of the #11303 gated-approval-tier bypass"
type: clo-attestation
date: 2026-10-28
issue: 11303
pr: 11443
fix_pr: 11304
adr: ADR-305
attestation-authority: clo
status: SIGNED-OFF PROVISIONAL (CLO-agent-attested, Soleur-as-tenant-zero v1)
reviewed_by: "no human (agent determination; operator veto available)"
disposition: "No Art. 33 duty, no Art. 34 duty on present evidence; no notification clock is running, and that position is time-boxed to the dates in §In plain terms. Art. 32 control-effectiveness gap, conceded. NOT certified clean. Email: no evidence of a send; INCONCLUSIVE for the residual before about 2026-07-30. KB share: INCONCLUSIVE (weak negative). GitHub, account deletion and other gated writes: NOT MEASURED. Autonomy: measured, not discriminating. CRM: measured small, not closed. soleur-web-2: UNOBSERVED."
signed_off_at: 2026-10-28
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-10-27T10:14:19Z — issue #11303 filed (the probe measurement commit was authored 2026-10-27T10:09:53Z). Anchors the VULNERABILITY, not a breach: reachability alone does not start the Art. 33 clock (statutory-response-catalog breach-art33 step 4)."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 4(12) event is established, so no clock started. Controller limb: if a limb flips, a FRESH 72h runs from awareness of the evidence that flips it. Installer (processor-to-controller) limb: without undue delay, no 72h."
exposure_window: "From each tool's introduction on main (§Window) to the fix: start 2026-04-06T14:43:48Z; end NO LATER THAN 2026-10-28T17:53Z for the host that answered /health at the post-merge check (host unidentified, serving start not dated); soleur-web-2 NOT confirmed. The fix entered main at 2026-10-27T20:17:39Z (PR #11304 mergedAt); that is not an end instant."
open_limbs: "E (pre-~2026-07-30 residual); K; G; A; D; W; soleur-web-2. Instruments, owners and dates in §Instruments."
decision_dates: "operator decisions by 2026-11-04; limbs with no decision by 2026-11-11 are recorded INCONCLUSIVE-LAPSED and force a re-ruling (§Notification)"
brand_survival_threshold: single-user incident
tier_classification: "Tier 1 — an internal determination record. No published document is edited, no right is narrowed, no processing is added. The mirror/SHA/heading gates are NOT engaged."
semver: "No TC_VERSION bump."
related: [ADR-305, "knowledge-base/legal/breach-register.md", "knowledge-base/legal/compliance-posture.md", "knowledge-base/legal/article-30-register.md"]
---

# CLO determination — #11303 gated-approval-tier bypass

> **DRAFT — requires professional legal review. Internal v1 sign-off only; not legal advice.**

## In plain terms

**What happened.** For about six months the hosted legacy agent runner told the Agent SDK that every platform tool was pre-approved, so
the Approve/Reject card that the registers and policies describe was skipped for agent email, push, PR, issue, workflow, share, autonomy,
deletion and CRM writes. PR #11304 fixed it (ADR-305). **What is not known:** whether any of those actions ran against a user's intent.
Only email has been looked at properly (no evidence of a send, with a gap before about 2026-07-30). Most other limbs have not been measured,
and the available telemetry cannot measure them. **soleur-web-2** has not been confirmed on the fixed image.

**Decisions needed from the operator** (by **2026-11-04**; "operator" here means the person authorised to decide for Jikigai, and the caller
is whoever runs the read-only reads for them). An item with no decision by **2026-11-11** is recorded INCONCLUSIVE-LAPSED and forces a
re-ruling. A decline **with recorded reasons** is INCONCLUSIVE-BY-DECISION (runbook sense): a recorded risk acceptance that does **not**
discharge the duty to investigate and does not close the limb as clean. Neither authorises anyone to read customer data: every read below
also needs the conditions in its row.

| # | Action | Needed because | If declined |
|---|---|---|---|
| 1 | Authorise or decline G-3: a **counts-only** scan of persisted agent session records for gated-tool invocations, **no content read by a human or model, no user-keyed output**. Not itself an authorisation to touch conversation files (§Instruments G-3) | Only instrument that reaches G, A, D, W and K together | G, A, D, W stay open, risk accepted. Conditions: a sanctioned read-only host channel (**not verified**); a zero counts only if retention reaches 2026-04-06; soleur-web-2 is a separate host |
| 2 | **Do not read anything.** Decide whether to ask the 2 installers outside `jikig-ai` (the message needs your approval) or first obtain their written consent/instruction. A metadata-only read of their repositories is **not authorised by this decision** | G cannot be measured first-party. Precondition for any read: the installer's written instruction or consent, or a written legal basis (none exists yet) | G stays open for them, risk accepted |
| 3 | K-1: confirm the 2 share-link owners are Jikigai-controlled **before anyone reviews link content**; if so review the 7 live links created after 2026-04-17 and revoke any whose intent the owner cannot confirm (revoke-by-default). K-2: authorise **counts-only** edge/origin access reads for those tokens (retention unverified) | K | K stays INCONCLUSIVE; 7 links stay public |
| 4 | Confirm no active account disappeared unexpectedly (D-1); authorise D-2 (Stripe cancellation **counts** with no user-initiated trace) and D-3 (anonymised-row residue **counts**) | D is irreversible and invisible after the fact | D stays open |
| 5 | After E-4/E-5 (by 2026-11-04), accept or reject the email residual before about 2026-07-30 | Nothing first-party can close it if E-4/E-5 cannot reach it | Residual stays INCONCLUSIVE |
| 6 | Identify which host answered /health at the post-merge check; confirm which image soleur-web-2 serves and have the SDK-warning absence query re-run on it (W-2) | Window end unconfirmed | The bypass is treated as live on web-2 |
| 7 | Authorise A-1 follow-up: compare the ON workspaces' creation dates with the date migration 099 was applied. For any ON workspace that **pre-dates 099** with no ack and no superseded stamp: **owner confirmation first**, and only if the owner cannot confirm they set it, reset to OFF (§Rulings R-3) | A pre-099 ON can only have been set explicitly | A stays open |
| 8 | Authorise the published-text corrections in §Published text (each in both `docs/legal/` and its `plugins/soleur/docs/pages/legal/` mirror) | The text is inaccurate as a description of the control for the window regardless of outcome | The text stays as published, inaccurate for the window; web-2 unconfirmed |
| 9 | Keep the raw read-outs (owner ids, timestamps, row-level results) privately, not in this public repository. Classify the 17 accounts and the 7 active ones as Jikigai-controlled or arms-length from account records (U-1, counts by class only) | Auditability without publication (§Rulings R-2); classification gates K-1 and G-3 | The determination cannot be reproduced on request; classification stays unverified |

## Ruling

An Art. 32 control-effectiveness gap, not an Art. 4(12) breach, **on present evidence**. The gate did not operate in the legacy runner. That
is conceded. What is **not** established is that any gated action ran against a user's intent; for most limbs that is because nobody has
looked. No Art. 33 or Art. 34 duty arises today. The no-clock position is conditional (§Notification). Rulings below are
**Ruled by CLO agent, 2026-10-28**.

## Window

Facts from the caller's git read of `main` (my clone is shallow, 217 commits, so I could not repeat it). **2026-04-06T14:43:48Z** is the
first platform tool and first pre-approval on `main` (`create_pull_request`, PR 1654); the gated-tier gate itself did not exist until
2026-04-10T22:36:49Z (PR 1925), so **2026-04-06 to 2026-04-10 was pre-approval with no card at all**. Tool landing dates:
`github_push_branch`, `github_trigger_workflow` 2026-04-10; `kb_share_*` 2026-04-17 (PR 2497); `account_export`, `account_delete` 2026-05-26;
`workspace_set_autonomous` 2026-06-03; `create_issue` 2026-06-05; `email_send`, `email_reply`, `email_suppress` 2026-06-15 (PR 5326);
`routine_*` 2026-06-16; `crm_*` 2026-07-08; `workstream_issue_*` writes 2026-07-10. **Merge is not production deploy; deploy dates are
unchecked.** Exposure for each tool therefore runs from its introduction to the fix, not over the whole span for every tool.

**Mechanism evidence.** The real-SDK probe measured the mechanism on SDK 0.3.284 only (in use since 2026-09-30). Earlier pins were 0.2.80,
0.2.85 and 0.3.197 and were not probed. A 2026-03-20 learning (`knowledge-base/project/learnings/2026-03-20-canusertool-caching-verification.md`)
already stated that `allowedTools` resolves before `canUseTool`, so the earlier versions are *inferred* affected, not measured.

**End.** The fix entered `main` at PR #11304's `mergedAt`, 2026-10-27T20:17:39Z. The squash commit `910a0858fa` carries author and committer
date 2026-10-27T16:56:51Z. The two do not reconcile (3h20m) and the gap is **unexplained** (a merge queue or the failed release runs are
plausible and unverified). Neither is a serving time. The only post-fix serving evidence is the issue's post-merge comment of
2026-10-28T17:53:26Z: production `/health` reported build `00f92f98` (a descendant), **host not identified, serving start not dated**; the
merge's own release run failed four times at the zot mirror step; a direct SDK-warning query since 2026-10-28T00:00Z returned 0 rows (weak,
evidence row 6); `soleur-web-2` outcome `unshipping` (control 0 rows) is UNOBSERVED. **The exposure end is therefore no later than
2026-10-28T17:53Z for the host that answered `/health`, and unconfirmed for web-2.** Sessions are instance-local, so a host keeps the bypass
until it serves the new image. All three registers use the same statement.

**Awareness-of-risk facts (Art. 32, not Art. 33).** The probe measurement commit (2026-10-27T10:09:53Z) preceded the issue by about four
minutes, and the 2026-03-20 learning shows the ordering was documented seven months earlier. Neither is a breach fact and neither starts a
clock. They remove any argument that the gap was unforeseeable, which weighs against Jikigai in the Art. 32 assessment.

## Legal characterisation

**Art. 4(12)** needs a breach of security leading to destruction, loss, alteration, unauthorised disclosure of or access to personal data.
An unenforced approval control is a failed Art. 32 measure, a precondition and not an event; there is nothing for limb 1 to attach to
until a gated action is shown to have run.

**"Unauthorised" is relative to the user.** An action the user's own agent took at the user's request is authorised even without the card.
The card separated that from the injected-prompt or model-error case; its absence turned authorisation from *evidenced* into *presumed*. I
rest on "nothing is shown to have happened", not on "nothing could have happened", and that is the weaker ground.

**Capacity.** Jikigai is controller for account data and the hosted service, and processor for customer repository content on GitHub
installations (3, of which 2 are outside `jikig-ai`, per the breach-register rows dated 2026-09-24 to 2026-09-30; the current count was not re-read). Art. 33(2) uses the same "breach" threshold.

## Evidence: what each source can and cannot show

| # | Source | Can show | Cannot show |
|---|---|---|---|
| 1 | `outbound_sends`: 0 rows, all time | No send *recorded by the chokepoint* | A send that reached Resend with no row: `record_outbound_send` runs after `getResend().emails.send`, and a process death between them leaves **neither a row nor a Sentry event**; a failed RPC leaves no row and (within Sentry's period) an `outbound.record_error` |
| 2 | `sendCompliantOutbound` (code) | `email_send`/`email_reply` are the only two call sites; every gate throws before Resend; other `resend.emails.send` callers are fixed-template transactional senders | Anything before HEAD (history not read) |
| 3 | `audit_github_token_use`: 0 rows | **Nothing** about the gated GitHub tools. A writer exists (`recordGithubApiCall` via `createGitHubAppClient`), but `createPullRequest` and `createIssue` use `githubFetch` in `github-app.ts`, `triggerWorkflow` uses `githubApiPost` in `github-api.ts` (no audit hook), and `pushBranch` is git. An all-time zero on a ledger that `workstream_issue_*`, the spawn function and the undo route write is itself unexplained | |
| 4 | `messages.tool_calls`: NULL in 2394 of 2394 | That tool calls were never persisted | Which tools ran |
| 5 | `kb_share_links`: 15 rows, 2 owners, 7 live | The earliest row is April 2026; `kb_share_create` reached `main` 2026-04-17, so 2 links pre-date the tool (0 live, cannot be agent-created) and 13 post-date it (7 live) | UI vs agent origin (no source column; both call `createShare`). The "no message within ±10 min" test is blind to headless sessions (auto-sync runs with no user message) and to turns over 10 minutes. No per-view record exists (the share-use audit was deferred) |
| 6 | Pino → Better Stack | The channel works (`git-lock-marker-telemetry.ts`: pino → stdout → journald → vector → Better Stack). Phase-0 §0.6: 58 real SDK shadow-warning rows in 30 days, all web-1, all cc-path, none naming a legacy platform tool, zero rows from web-2. This also explains the single pre-fix warning on 2026-10-27T16:27Z naming only auto-approve entries: it was a cc-path session | That legacy sessions did not use platform tools before 2026-09-30; any web-2 activity. The base rate is about 58 rows per 30 days on web-1 only, so **zero rows since 2026-10-28T00:00Z is weak evidence of fix-serving**, not proof |
| 7 | `soleur-web-2` | Nothing: UNOBSERVED | |
| 8 | Population: 17 users, 7 with conversations in the window | Size | That they are Jikigai-controlled. The register records "10 operator-adjacent accounts" (2026-05-16) and the CLO ruling of 2026-10-09 records "no arms-length user", both older than this read and neither classifying the 17. **Unverified** (instrument U-1). Whether the 2 link owners are among the 7 active users is not known to me |
| 9 | **Survivorship** | Every count above is post-deletion state. `account_delete_initiate` cascades `kb_share_links` (`user_id … on delete cascade`, migration 017), conversations, messages and the users row (migration 065 note), so a deleted account's links, messages and sessions are absent from every count | Anything about accounts that no longer exist |

## Per-limb verdicts

Reach does not lower the weight of any limb. The GitHub tools take `owner`/`repo` from the connected repository, never tool input
(`buildGithubTools`), and push rejects `main`, `master`, the default branch and force (`rejectProtectedBranch`). That confines the **API
calls**, not the **effect**: a pushed branch plus `github_trigger_workflow` can run agent-authored code in the user's CI with its secrets,
deploy permissions and Actions minutes; `create_issue` and PRs notify collaborators; a public repository publishes the branch. Email can
reach any external recipient; a share link is a public URL that needs an onward channel; deletion is irreversible.

| Limb | Tools | Verdict |
|---|---|---|
| **E** | `email_send`, `email_reply` (`email_suppress` only over-suppresses) | **No evidence of a send.** Ledger empty; sending enabled as of 2026-10-28 (earlier state unverified); no `outbound.*` errors in Sentry for 90 days (a negative of unknown sensitivity that covered only `outbound.*` ops). **INCONCLUSIVE for the residual 2026-06-15 → about 2026-07-30** |
| **K** | `kb_share_create`, `kb_share_revoke` | **INCONCLUSIVE, weak negative.** Window for agent-created links starts 2026-04-17: 13 links, 7 live |
| **G** | `github_push_branch`, `create_pull_request`, `create_issue`, `github_trigger_workflow`, `workstream_issue_*` | **NOT MEASURED** |
| **A** | `workspace_set_autonomous` | **Measured, not discriminating.** 4 of 20 workspaces have `bash_autonomous` ON; 1 has an owner ack (October 2026, after migration 159), 3 have none; `autonomous_disclosure_ack_superseded_at` is NULL for all 4, so none had an ack reset by migration 159. ON with a NULL ack is the **default state of a new workspace** (migration 099: DEFAULT true, NULL ack = HOLD) and is **not evidence of a bypass**. The agent tool writes only the toggle; the ack is written only by the owner-only RPC. **In the legacy runner the toggle and the ack hold are inert:** its `createCanUseTool` call passes none of `bashAutonomous`, `autonomousAckAt`, `resolveAckPosture`, `isOwner`, so Bash goes to the review gate there. The hold exists on the cc path only (`cc-dispatcher`, `permission-callback`), covers only the owner's first non-blocked Bash command, and never touches gated platform tools. A persisted ON set through the bypass would therefore bite on later cc-path sessions, and the fix does not reset it |
| **D** | `account_delete_initiate` | **NOT MEASURED.** Irreversible, guarded only by input confirmations an agent can supply. Survivorship applies. It had no explicit tier entry before #11303 (gated by default); `create_issue`, `kb_share_revoke`, `routine_run`, `crm_*` and `workstream_issue_*` already had explicit gated entries |
| **W** | `crm_*` writes: **measured small** (one `beta_contacts` row and one stage transition in the window, one owner, October 2026; UI and agent indistinguishable); `routine_run`, `plausible_*`, `account_export_enqueue`: not measured | **Not closed** |

"NOT MEASURED" means no instrument has been run. It becomes INCONCLUSIVE-EXHAUSTED or INCONCLUSIVE-BY-DECISION
(`breach-access-log-investigation.md`, 2026-09-14 addendum) only after the instruments are run or declined.

## Notification

- **Art. 33(1): not triggered**, on a **conditional** position. The controller is aware of a vulnerability, not a breach. The position
  depends on a prompt, time-boxed investigation: operator decisions by 2026-11-04, instruments run by 2026-11-11. **Which outcomes keep the
  no-clock position:** an instrument run with a non-adverse result; a decline with recorded reasons (INCONCLUSIVE-BY-DECISION), once the
  cheap instruments in my control have run. **Which force a re-ruling:** a lapse (INCONCLUSIVE-LAPSED: no decision by 2026-11-11), because
  "reachability only" is then no longer supported by an investigation and I will re-rule that limb on 2026-11-12; and any adverse result
  (reopen condition 1). A partial outcome is judged per limb: limbs whose instruments ran or were declined with reasons keep the position;
  lapsed limbs are re-ruled.
- **The 2026-06-29 reachability analogy is weaker here.** There the exploitation precondition (a published anon key) was shown absent. Here
  the precondition, a model emitting an unintended tool call (prompt injection or model error), is not absent and cannot be shown absent.
- **Art. 34: not triggered**, not inherited from Art. 33.
- **Installers (Art. 33(2)).** Statutory test: the same "breach" threshold; if met, **without undue delay, no 72h**. Contractual: the only
  notice term I found is DPA template §8.1 ("without undue delay and in any event within 72 hours after Jikigai becoming aware of the breach"); the tenant DPA
  register is `draft-empty-template` (2026-05-14, current state unconfirmed) and the Terms contain no security-incident notice clause.
  Installers' contractual terms are therefore **unverified**.
- **Art. 33(5).** Not strictly engaged without a breach. The record carries the three elements (facts, effects, remedial action) so it can be
  produced unchanged if a limb flips. Breach-register row added.
- **Residual risk: not rated.** Unmeasured on G, A, D, W and soleur-web-2.

## Instruments

All reads are aggregate and read-only unless stated. Unless a row says otherwise, an instrument is run by **2026-11-04**. A row's "else required" cell is a precondition, not a formality.

| ID | Instrument | Result / what it can show | What else is required |
|---|---|---|---|
| E-1 | Sentry `op:outbound.record_error`, `op:outbound.send_error` | **Run 2026-10-28:** 0 issues / 0 events in 90 days (org `jikigai-eu`, all projects; control `op:*` returned 100 issues, which proves queryability only). Does not reach before about 2026-07-30 | Done |
| E-2 | Doppler `prd` `OUTBOUND_SENDING_DOMAIN_VERIFIED` | **Run:** `true` as of 2026-10-28. Earlier state unverified | Done |
| E-3 | Doppler change history for that value | **Run:** the audit log (172 entries, newest 2026-10-28) does not name secrets per entry and could not date the first set | Done; inconclusive |
| E-4 | Sentry `feature:email-triage-tools` `op:email_send` / `email_reply` | Handler-level errors, 90 days | Caller; by 2026-11-04 |
| E-5 | Resend provider-side send count for `outbound.soleur.ai`, over the longest period the provider retains | Independent of the audit write. Content retention is 30 days (register); list/aggregate retention **unverified**. If it does not reach 2026-06-15 the residual stays | Caller; by 2026-11-04 |
| K-1 | Confirm the 2 owners are Jikigai-controlled **before anyone reviews link content** (else this is access to customer content); review and revoke by default the 7 live links created after 2026-04-17 | Closes K only if internal and intended | Operator |
| K-2 | Edge/origin access counts for the 7 live tokens | Whether anyone fetched them. Retention unverified; no application-level view record exists | Operator authorisation; by 2026-11-11 |
| A-1 | Discriminate ON workspaces by creation date against the date migration 099 was applied, then by ack and superseded stamps | A post-099 ON with NULL ack is the default state and is not evidence. Only a **pre-099** ON with NULL ack and NULL superseded stamp could have been set solely by an explicit act, and an owner or agent cannot be told apart from the data. A current-state count alone cannot close a historical limb | Operator authorisation; owner confirmation first, then reset (R-3) |
| D-1 | Operator confirms no active account disappeared | Memory-dependent; not sufficient alone | Operator |
| D-2 | Stripe subscription cancellations with no user-initiated trace | Candidate signal of agent-initiated deletion; existence of such a trace unverified | Operator authorisation |
| D-3 | Anonymised-row residue: `audit_byok_use.founder_id IS NULL` (SET NULL on account deletion, migration 065 note), grouped by month, counts only | Deleted accounts that had BYOK use. `outbound_sends.owner_id` residue is useless (table empty) | Operator authorisation (box action 4); run by the caller |
| G-1 | App-authored artefacts in Jikigai-owned repositories | Confounded: the same App runs Jikigai's own CI and cron, and no marker separates hosted-chat actions. Low value | Operator |
| G-2 | For the 2 installations outside `jikig-ai`: (i) a metadata-only read of bot-authored branches, PRs, issues, runs with Jikigai's App credentials, or (ii) ask the installers to check their own audit logs | **No read is authorised by the operator's decision alone.** (i) is processing of customer repository content as processor: it needs the installer's written instruction or consent, **or** a written legal basis including an Art. 6(4) compatibility analysis (none exists; I do not issue one here), and an Art. 30(2) entry. (ii) is a disclosure to a controller and is in effect a voluntary notice; the message needs approval. I cannot assume the installers are Jikigai-affiliated: that needs their written consent and a check that it is the same legal entity | Operator decision plus the above |
| G-3 | Counts-only scan of persisted agent session records (SDK session JSONL, #3418 per PA-28) for tool-use entries naming the gated tools | Reaches G, A, D, W, K together. **Ruling (narrowed): this is not an authorisation to touch conversation files.** The scan is processing even if it outputs integers. For sessions of Jikigai-controlled accounts (needs U-1 first), Art. 6(1)(f) on Jikigai's own Art. 32 duty covers a scan whose output is integers per tool name, with no content read by a human or model and no user-keyed output. The same files hold processor-held customer content for arms-length users; my ruling does **not** cover those: it needs the G-2(i) preconditions (instruction or consent, or a written basis with Art. 6(4) compatibility, and an Art. 30(2) entry). A non-zero count is a new decision. Needs a sanctioned read-only host channel (none verified); a **zero counts only if file retention covers 2026-04-06 onward**; web-2 is a separate host | Operator authorisation, **plus** the above |
| W-1 | CRM row counts in the window | **Run:** one contact, one transition (see W) | Done |
| U-1 | Classify the 17 accounts, and the 7 with conversations in the window, as Jikigai-controlled or arms-length from account records; counts by class only | Gates K-1 and G-3, reopen condition 3, and the external-counsel trigger. I have no record that classifies them | Operator; by 2026-11-04 |
| W-2 | Confirm soleur-web-2's served image, then re-run the SDK-warning absence query on it | Closes the end-of-window question for web-2 | Operator or CTO; by 2026-11-04 |

## Conditions that reopen this determination

1. Any instrument returns evidence that a gated action ran against a user's intent: re-run Art. 33 and Art. 34 from awareness of that evidence.
2. An `outbound.*` or `email_send`/`email_reply` error event, a Resend record, or any other evidence of a send before about 2026-07-30 or not in the ledger.
3. An arms-length user is found among the 7 active users or the 2 link owners, **or the 2 outside installers are not Jikigai-controlled and are affected**: the volume and severity limbs change and the external-counsel trigger is met.
4. soleur-web-2 is not confirmed on the fixed image, or any evidence shows it ran the bypass at any time.
5. A user or installer report of an unexpected send, push, PR, share, deletion or autonomy change.
6. A regression: the ADR-305 census fails open or the SDK pre-approval behaviour changes (probe canary); or any limb reaches INCONCLUSIVE-LAPSED, which forces a re-ruling of that limb (§Notification).
7. A non-zero G-3 count, or K-2 showing access by an unexpected party.

## Rulings (Ruled by CLO agent, 2026-10-28)

- **R-1, outbound-email LIA.** Its trigger ("removal or bypass of the per-send human-approval gate") fired inadvertently. I **override the
  automatic voiding consequence**, after a limited re-run done now, on stated bases: (a) the trigger was written for a decision to auto-send, and
  the processing mode that actually ran is the one assessed, because **no send is recorded**; (b) the chokepoint, suppression and opt-out
  controls were intact **at HEAD; history before HEAD is unread** (shallow clone), so this limb rests on HEAD plus the no-recorded-send
  facts, and the residual before about 2026-07-30 remains open; (c) balancing: *interest* (promoting the controller's activities by 1:1
  outreach to professionals at published professional addresses, Recital 47), *necessity* (1:1 human-addressed outreach, no less intrusive
  means) and the data subject's *reasonable expectation* (a single message carrying the Art. 14 disclosure) are unchanged, because on the
  evidence no outreach occurred during the window; (d) DPIA screen: unchanged, no full DPIA at single-operator scale. If the residual flips
  to a send, the LIA is void for that send and the full balancing and DPIA screen are mandatory. The beta-CRM LIA trigger ("agent write path
  is de-gated") is overridden on the same reasoning: owner-private store, no third-party recipient, one contact written in the window;
  "every store owner is Jikigai personnel" is inherited and **unverified** (records of 2026-08-11).
- **R-2, publication.** This repository is public. Published at determination grain: aggregate counts, tool names and the mechanism (all already in public ADR-305 and the code). Generalised or withheld from this memo: the literal deletion acknowledgement string, owner creation dates, per-month link counts, exact owner and ack timestamps, the earliest link's exact date (month grain used). Held privately by the operator (action 9): the row-level read-outs. **History:** the first commit of this memo (`f2b01b646f`) is already on the public remote and carries "owners created on or before 2026-03-31"; R-2 cannot remove it. The branch will be squash-merged, and I accept the residual exposure in that commit's history as low-grain (a quarter-level attribute of two accounts, no identifier); a history rewrite of a public branch is not recommended for it. Nothing the determination needs to be auditable was removed.
  already in public ADR-305 and the code). Generalised or withheld: the literal deletion acknowledgement string, owner creation dates,
  per-month link counts, exact owner and ack timestamps. Held privately by the operator (action 9): the row-level read-outs. Nothing the
  determination needs to be auditable was removed.
- **R-3, autonomy reset.** No blanket reset. A reset must not override a recorded owner choice, and ON with a NULL ack is the product default (migration 099), not evidence of a bypass. A reset is warranted only for an ON workspace that **pre-dates migration 099**, has a NULL ack and a NULL superseded stamp (so ON could only have been set explicitly), and only **after owner confirmation fails** (order: owner confirmation first, then reset). Whether any such workspace exists was not read.
  holds the first auto-run. Recommended only for ON workspaces that pre-date migration 099 and have no ack (action 7).
- **R-4, vocabulary.** "CLEAN" is not used for email: it needs full-window coverage, which the ledger cannot give (row 1).

## Register corrections made in this change

`article-30-register.md`: PA-28 (heading note, intro, (a), (c), Special categories, (f), (g)(1), (g)(2), (g)(4), (g)(13)) and PA-30
(g)(8). `breach-register.md`: row and `related`. `compliance-posture.md`: row, header comment, Resend vendor row marked reviewed. Both LIAs:
dated addenda. Registers carry the verdict and a pointer here; the evidence lives once, above. Reviewed, **no change**:
`article-30-2-register.md` (P-1 is local operator-assisted runs, no gate claim), `art30-reverification-triggers.yml` (infra sites only),
PA-4 and PA-17 (no approval claim). The PA-28 heading note, the PA-30 (g)(8) marker and both LIA addenda carry the host qualification ("reported serving the fix at the 2026-10-28T17:53Z check (host unidentified); soleur-web-2 unconfirmed"); the other PA-28 markers point to the heading note.

## Published text: recommended follow-ups (NOT edited; the operator has not authorised published-text edits)

**Every published legal document exists in two places** (`docs/legal/` and `plugins/soleur/docs/pages/legal/`); a correction must change both.

1. **Privacy Policy §4.14** (heading "human-approved"; "every individual message is reviewed and approved by a human before it is sent";
   "the approval is bound to a hash of that exact body and is single-use"; line ~320 "evidence that each cold send was human-approved"; line
   ~321 Art. 22 "every send is individually human-approved"; line ~411 "human-approved 1:1 outbound outreach"), **DPD §2.3(ab)** (heading;
   "body-hash-bound and single-use"; "evidence each cold send was human-approved"; the sub-processor entry near line 297) and **GDPR Policy
   §3.11** (heading; "permanent per-send human-approval gate"; "every body is human-approved"; it has no hash sentence). ADR-305 states the
   hash is a handler-local integrity check, not a binding to the card. The control statements are inaccurate as a *description* for the window
   regardless of outcome; as to outcome they are **not falsified, provisional** on the email residual.
2. **GDPR Policy §3.13** (line ~257 "the decisive safeguard is owner-only RLS + the human-approval gate on agent writes"; ~263 "mitigated by
   the human-approval gate on every agent write") and **DPD §2.3(ad)** ("write tools are human-gated"): accuracy for the window is **not
   shown** (CRM and other writes NOT MEASURED or small).
3. Reviewed, a **different mechanism** (the `scope_grants` / `action_sends` tier system, not the platform-tool gated tier): Acceptable Use
   Policy "drafts everywhere, sends nowhere", Privacy Policy "Opt-in by class and tier", Terms §3a ("Approve every time", "Draft, one click").
   Not affected.
4. No retroactive disclosure of the window is recommended on present evidence. Revisit if E, G or D flips.

## Adjacent findings

- `audit_github_token_use` is not on the call path of the four gated GitHub write tools, so any statement that every App token use is
  recorded is untrue for them; for the CTO and a later register review.
- `outbound_sends` stores hashes and a Resend id and no approver or decision: it is chokepoint-passage evidence, not an approval record.

> **DRAFT — This document was generated by AI and requires professional legal review before use. It does not constitute legal advice.**
