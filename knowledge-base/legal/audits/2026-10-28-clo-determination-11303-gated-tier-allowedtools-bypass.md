---
title: "CLO determination — Art. 4(12) / Art. 32 assessment of the #11303 gated-approval-tier bypass"
type: clo-attestation
date: 2026-10-28
issue: 11303
pr: 11304
adr: ADR-305
attestation-authority: clo
status: SIGNED-OFF PROVISIONAL (CLO-agent-attested, Soleur-as-tenant-zero v1)
disposition: "No Art. 33 duty, no Art. 34 duty on present evidence; no notification clock is running. Art. 32 control-effectiveness gap, conceded. NOT certified clean: the email limb is CLEAN on the WORM ledger and CLEAN on Sentry for the last 90 days, and PROVISIONAL only on the earlier part of the window (before about 2026-07-30), which rests on the empty ledger alone; the KB-share limb is INCONCLUSIVE (weak negative); the GitHub, workspace-autonomy, account-deletion and other gated-write limbs are NOT MEASURED."
signed_off_at: 2026-10-28
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-10-27T10:14:19Z — issue #11303 filed. Anchors the VULNERABILITY, not a breach: reachability alone does not start the Art. 33 clock (statutory-response-catalog breach-art33 step 4)."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 4(12) event is established, so no clock started. If a limb flips, a FRESH 72h runs from awareness of the evidence that flips it, not from the anchor above."
exposure_window: "2026-04-06 → 2026-10-28 (caller-supplied; the conservative bound). End confirmed for the host(s) behind the soleur-web-platform check; NOT confirmed for soleur-web-2."
open_limbs: "E (email, provisional on the pre-~2026-07-30 residual only; E-1 and E-2 were run 2026-10-28); K (KB share, inconclusive); G, A, D, W (not measured). Instruments and decision-owners in §What would close the open limbs."
brand_survival_threshold: single-user incident
tier_classification: "Tier 1 — an internal determination record. No published document is edited, no right is narrowed, no processing is added. The mirror/SHA/heading gates are NOT engaged."
semver: "No TC_VERSION bump."
related: [ADR-305, "knowledge-base/legal/breach-register.md", "knowledge-base/legal/compliance-posture.md", "knowledge-base/legal/article-30-register.md"]
---

# CLO determination — #11303 gated-approval-tier bypass

> **DRAFT — requires professional legal review. Internal v1 sign-off only; not legal advice.**

## Ruling in one paragraph

An Art. 32 control-effectiveness gap, not an Art. 4(12) breach, **on present evidence**. The Approve/Reject card that
the register and the published policies describe as the trust boundary for agent email, push, PR, share, autonomy and
deletion actions did not operate in the hosted legacy runner for the whole window. That is conceded. What is **not**
established is that any gated action ran against a user's intent, and for most limbs that is because nobody has
looked, not because anybody looked and found nothing. No Art. 33 or Art. 34 duty arises today. The determination is
not a clean bill: it names what it rests on, what it does not, and what re-opens it.

## Update 2026-10-28 (E-1 and E-2 run)

The caller ran both email instruments read-only on 2026-10-28 (rows E-1, E-2 below). Net: ledger empty all time, sending
enabled, and no record or send errors in Sentry for the last 90 days. The email limb is clean for the last 90 days. The
earlier part of the window rests on the empty ledger alone, because an audit write failing after a dispatch would have
left no row and, before the 90-day period, no retrievable Sentry event. Email tools cannot predate #5325 (June 2026), so
the real uncovered span is roughly June to about 2026-07-30. I keep the verdict **provisional on that residual only**.
The residual is not closable by a further first-party instrument I know of; it closes if the controller accepts it on a
recorded decision, and no other limb changes.

## Revision of my 2026-10-27 note (issue #11303 body, "Legal posture")

The conclusion stands. Three things change: (1) the window is the caller's wider 2026-04-06 start, not 2026-06-15;
(2) the telemetry I named ("GitHub events") does not exist in the form I assumed (see source 3); (3) the limbs now
include account deletion, autonomy and the other gated writes, which my note did not name.

**Window start.** I rely on **2026-04-06**. A wider window can only add exposure that must be explained; a narrower one
risks excluding the exposure. It matters materially for one source: at least **8 of the 15** `kb_share_links` (April 7,
May 1) fall before 2026-06-15 and would have been outside the read I originally scoped. It does not matter for
`outbound_sends` (all-time) and cannot matter for the SHADOWED-warning log (it covers neither start). I could not date
each tool's first appearance in `allowedTools` myself: the local clone is shallow (217 commits). 2026-04-06 is therefore
**unverified by me**. The email tools cannot predate #5325 (June 2026, per Art. 30 PA-28). End of window: the merge was
2026-10-27T20:17:39Z; the instant the fixed image began serving was not recorded in what I was given, and
`soleur-web-2` is UNOBSERVED (the absence control returned 0 rows). Sessions are instance-local (ADR-305), so a host
keeps the bypass until it runs the new image.

## Facts

The Agent SDK approves a bare `allowedTools` entry before it consults `canUseTool`. The legacy runner listed every
registered platform tool there, so the `gated` tier was skipped for `email_send`, `email_reply`, `email_suppress`,
`github_push_branch`, `create_pull_request`, `github_trigger_workflow`, `kb_share_create`, `workspace_set_autonomous`
and the default-gated rest (`create_issue`, `kb_share_revoke`, `routine_run`, `account_delete_initiate`, the `crm_*` and
`workstream_issue_*` writes). Measured by the real-SDK probe (SDK 0.3.284). Fixed by PR #11304 / ADR-305. Surface: the
legacy runner only; ADR-305 states the cc-soleur-go path already ran the gated `crm_*` tools through the gate (other
tools on that path: not verified). Remedial action taken: `buildAllowedTools` keeps only auto-approve names; a
fail-closed assertion in `buildAgentQueryOptions`; census test; post-merge check recorded on the issue (CI green, health
ok, direct SDK-warning query since 2026-10-28T00:00Z returned 0 rows).

## Legal characterisation

**Art. 4(12)** needs a breach of security *leading to* destruction, loss, alteration, unauthorised disclosure of or
access to personal data. An unenforced approval control is a failed Art. 32 measure; it is a precondition, not an event.
There is no event for limb 1 to attach to until a gated action is shown to have run.

**"Unauthorised" is relative to the user.** An action the user's own agent took at the user's own request is authorised
by that user even without the card. The card separated that case from the injected-prompt or model-error case. Its
absence did not make every action unauthorised; it turned authorisation from *evidenced* into *presumed* for the window.
I do not rest on "nothing could have happened". I rest on "nothing is shown to have happened", and I record that this
is a weaker ground.

**Art. 25 / 32.** The measure the register describes (PA-28 §(g)(1), PA-30 §(g)(8)) was designed correctly and not in
force. Corrected in the registers (below).

**Capacity.** Jikigai is controller for account data and the hosted service, and processor for customer repository
content on GitHub installations (3 installations, 2 outside `jikig-ai`, per the breach register). Art. 33(2) (processor
to controller) uses the same "breach" threshold, so nothing arises there either.

## What each source can and cannot show

| # | Source | Can show | Cannot show | Use |
|---|---|---|---|---|
| 1 | `outbound_sends`: 0 rows, all time (control tables queryable) | No send *recorded by the chokepoint*, ever | A send that reached Resend and whose audit write then failed | Strong negative for email; the residual is stated under E-1 |
| 2 | `sendCompliantOutbound` (code read) | `email_send` and `email_reply` are the only two call sites; every gate throws before Resend; other `resend.emails.send` callers (`notifications.ts`, `cron-email-ingress-probe.ts`) are fixed-template transactional senders, not agent-composed. A precondition (`assertSendingDomainVerified`, env `OUTBOUND_SENDING_DOMAIN_VERIFIED`) must be `"true"` | When the flag was first set `"true"` in production (value read as `true` on 2026-10-28; first-set date NOT verified; not in `.env.example` or `infra`). **`record_outbound_send` runs AFTER `getResend().emails.send`**; on failure the code mirrors `outbound.record_error` to Sentry and throws "audit gap" — the mail is already out. HEAD only: no earlier un-chokepointed agent path is indicated (tool and chokepoint were introduced together, #5325) but I could not read history | Closes the chokepoint-bypass worry at HEAD; opens the dispatch-then-audit-gap residual |
| 3 | `audit_github_token_use`: 0 rows, all time | Nothing about the gated GitHub tools. **Correction to the grep premise:** a writer exists (`recordGithubApiCall` via `createGitHubAppClient` hooks, RPC `record_github_token_use`), so it is not "no writer". But `createPullRequest`, `createIssue`, `triggerWorkflow` use the raw `githubFetch` in `github-app.ts`, and `pushBranch` is git, so none of the four passes through the audited client. Only `workstream_issue_*`, the spawn function and the undo route do | An all-time zero on a ledger that three production call sites write is itself unexplained: either those features never ran, or the writer fails (Sentry `feature=github-audit`). Not read | **Never read as an all-clear.** Adjacent finding, §Adjacent |
| 4 | `messages.tool_calls`: NULL in 2394 of 2394 | That tool calls were never persisted | Anything about which tools ran | Uninstrumented; no inference |
| 5 | `kb_share_links` (15, 2 users, 7 un-revoked) + "no message within ±10 min" | A weak negative for agent creation: an agent-created link normally sits inside a conversation turn | UI vs agent origin (no source column; the UI route and `kb_share_create` both call `createShare`). The test is also **blind to headless sessions**: the auto-sync seam runs sessions with no user message, and an agent link created there would show exactly this "no message" result. A turn longer than 10 minutes escapes it | INCONCLUSIVE, weak negative |
| 6 | SHADOWED warnings, 30 days, no platform tools | That the log sink captured no gated-name warning since ~2026-09-30 | Anything before that; whether the warning enumerates every shadowed name (the one pre-fix warning on 2026-10-27T16:27Z names only auto-approve entries, which I cannot reconcile with "legacy sessions list every platform tool"); whether the sink is complete (pino does not reach Better Stack; Sentry unqueried) | Weak evidence of low recent use; no all-clear |
| 7 | `soleur-web-2` | Nothing: UNOBSERVED | | Window end unconfirmed there |
| 8 | Population: 17 users, 7 with conversations since 2026-04-06; the 2 link owners were created on or before 2026-03-31 | Size of the exposed population | That they are Jikigai-controlled. The KB records "10 operator-adjacent accounts" (2026-05-16 row) and "no arms-length user" (CLO ruling 2026-10-09), both older than this read; I found no record that classifies the 17 | **Unverified.** The caller's belief that the two owners are founder/internal accounts is consistent with those records and not proven by them |

## Per-limb verdicts

Reach decides weight. Email can go to any external recipient. A share link is a public URL needing an onward channel.
GitHub tools take `owner`/`repo` from the user's connected repository, never from tool input (`buildGithubTools`
closure), push rejects `main`, `master`, the default branch and force (`rejectProtectedBranch`), so effects stay inside
the user's own repository (public if the repository is public). Deletion is the only irreversible limb.

| Limb | Tools | Verdict |
|---|---|---|
| **E** email | `email_send`, `email_reply` (`email_suppress` only over-suppresses) | **CLEAN on the ledger** (full coverage, all time), with the send path **enabled** (E-2) and **CLEAN on Sentry for the last 90 days** (E-1). **PROVISIONAL** on the earlier part of the window: before about 2026-07-30 an audit write failing after a dispatch would leave no row and no retrievable Sentry event, so that part rests on the empty ledger alone |
| **K** KB share | `kb_share_create`, `kb_share_revoke` | **INCONCLUSIVE**, weak negative. 7 links are still live |
| **G** GitHub | `github_push_branch`, `create_pull_request`, `create_issue`, `github_trigger_workflow`, `workstream_issue_*` | **NOT MEASURED.** First-party telemetry cannot answer it. Structurally bounded to the user's own repository |
| **A** autonomy | `workspace_set_autonomous` | **NOT MEASURED.** Internal state, no external effect by itself; it lowers later Bash gating |
| **D** deletion | `account_delete_initiate` | **NOT MEASURED.** Irreversible. Needs the literal ack and the user's own email (both in the agent's reach). No durable deletion record found in `account-delete.ts` |
| **W** other writes | `crm_*` writes, `routine_run`, `plausible_*`, `account_export_enqueue` | **NOT MEASURED.** Owner-private or the owner's own services; export needs a re-auth event id |

"NOT MEASURED" is not the runbook's INCONCLUSIVE (a measured window that does not cover). It means no instrument has
been run. It takes INCONCLUSIVE-EXHAUSTED or INCONCLUSIVE-BY-DECISION (`breach-access-log-investigation.md`, 2026-09-14
addendum) only after the instruments below are run or declined.

## Notification determination

- **Art. 33(1): not triggered.** No Art. 4(12) event is established; the controller is aware of a vulnerability, not a
  breach. This follows the corpus rule that reachability starts the investigation, not the clock.
- **Art. 34: not triggered**, and not inherited from Art. 33. It needs high risk; none is established.
- **Art. 33(2)/customer communication: none owed.** No installer or user is told anything on present evidence. This is
  re-run, not assumed, if G or K flips (the G-2 option below is, in effect, a voluntary disclosure to installers).
- **Art. 33(1) risk, in the alternative.** If a limb flips to BREACH: E would be the serious one (third-party
  recipient, personal data in the body); K needs an onward channel; G is bounded to the user's own repository and branch
  protections; D is irreversible destruction and would be assessed on its own facts. I do not pre-judge a flip.
- **Art. 33(5).** Not strictly engaged without a breach. The record is nonetheless written to the register's inclusion
  predicate (a suspected event assessed against Art. 4(12)) and carries the three Art. 33(5) elements — facts (§Facts),
  effects (§Per-limb verdicts), remedial action (§Facts, PR #11304) — so it can be produced unchanged if a limb flips.
  Breach-register row added.

## Residual risk

Medium-low, unmeasured on G/A/D/W. The fix is deployed on the verified host(s); the gate fails closed (static deny on
timeout or abort, ADR-305 decision 5). Remaining: web-2 unobserved; the plugin-wildcard pre-approval and the
PreToolUse-`allow` route are not mechanically guarded (ADR-305 decisions 7–8); consent fatigue on the new cards.

## What would close the open limbs

| ID | Instrument | Shows | Decision-owner |
|---|---|---|---|
| E-1 | **RUN 2026-10-28 (caller, read-only).** Sentry org `jikigai-eu`, all projects, 90 days, search control passed (`op:*` returned 100 issues): `op:outbound.record_error` 0 issues / 0 events; `op:outbound.send_error` 0 issues / 0 events | No dispatch-then-audit-gap and no Resend send error in the last 90 days. **Bound:** the period is 90 days, so it does not cover 2026-04-06 to about 2026-07-30; the Resend send list (30 days) is subsumed | Done; counts only |
| E-2 | **RUN 2026-10-28 (caller, read-only).** Doppler `prd` `OUTBOUND_SENDING_DOMAIN_VERIFIED` = `true` | The send path **was enabled** in production, so the chokepoint did not refuse by construction: the empty ledger is evidence of no sends, not of a disabled path. First-set date NOT verified | Done |
| K-1 | Confirm from account records that the 2 link owners are Jikigai-controlled; review the 7 live links' documents; revoke any not intended | Closes K if internal and intended | **Operator** (revocation is theirs) |
| A-1 | Aggregate count of workspaces with autonomous mode ON | 0 closes A; >0 needs owner confirmation. Column not verified; UI and agent indistinguishable | Caller or operator |
| D-1 | Operator confirms no active account disappeared unexpectedly | Operator knowledge; a Supabase auth admin audit count for user deletions is a candidate, existence and retention unverified | **Operator** |
| G-1 | In Jikigai-owned repositories, count App-authored branches, PRs, issues, workflow runs in the window | Confounded: the same App runs Jikigai's own CI and cron, and I know of no marker that separates hosted-chat actions. Low value | Operator (org owner) |
| G-2 | For the **2 installations outside `jikig-ai`**: either (i) a metadata-only read of bot-authored branches, PRs, issues and runs using Jikigai's App credentials, or (ii) ask the installers to check their own repository audit log | (i) uses Jikigai credentials on third-party repositories outside the instructed purpose, and is processor conduct needing an Art. 28(3) basis; (ii) is a disclosure to the installers. **Neither is to be done without the operator's decision.** If those installers are Jikigai-affiliated, (i) is cheap | **Operator decision required** |
| G-3 | Counts-only scan of the agent session records persisted on the web host (SDK session JSONL, #3418 per PA-28) for tool-use entries naming the gated tools, over files modified in the window | The only instrument that answers G, A, D, W and K together. Host read access, so the repository's no-SSH rule applies; I did not verify that a sanctioned read-only channel exists, nor JSONL retention; web-2 is a separate host. Reads customer conversation files, counts only | **Operator authorisation required** |

If G-2 and G-3 are declined, the limbs close INCONCLUSIVE-BY-DECISION with the reason recorded, as at #7945. That is
weaker than EXHAUSTED and the record must say so.

## Conditions that reopen this determination

1. Any instrument above returns evidence that a gated action ran without the user's intent (BREACH): re-run Art. 33
   and Art. 34 from awareness of that evidence; breach-notice-triage engages with a fresh 72h.
2. A `outbound.record_error` or `outbound.send_error` event surfacing for the window (none in the last 90 days), a Resend
   or Doppler-history record showing a send before about 2026-07-30, or any later evidence of a send not in the ledger.
3. An arms-length user is found among the 7 active users or the 2 link owners: the volume and severity limbs change and
   the external-counsel trigger (first arms-length user) is met.
4. A second host (web-2) is shown to have run the bypass after 2026-10-28.
5. A user or installer report of an unexpected send, push, PR, share, deletion or autonomy change.
6. A regression: ADR-305's census fails open, or the SDK's pre-approval behaviour changes (probe canary).

## Register corrections made in this change

- `knowledge-base/legal/article-30-register.md`: PA-28 (intro, (a), (c), Special categories, (f), (g)(1), (g)(2), (g)(4)) and
  PA-30 (g)(8) each carry a dated `Superseded 2026-10-28 (#11303)` marker in the cell. PA-28 (g)(2) also records ADR-305's
  disclosed limit: the body hash is handler-local, the binding is `canUseTool` returning `allow(toolInput)`.
- `knowledge-base/legal/breach-register.md`: row added; `related` extended.
- `knowledge-base/legal/legitimate-interest-assessments/2026-06-15-outbound-email-authority-lia.md` and
  `.../2026-07-07-beta-crm-lia.md`: dated addenda. Their own re-evaluation triggers ("bypass of the per-send human-approval
  gate"; "agent write path is de-gated") fired, inadvertently. Disposition: the balancing is not voided. The gate now
  operates, and for email no send is recorded in the window; for CRM the store is owner-private with no third-party
  recipient. Re-run of the balancing is not required; the addenda say so.
- Reviewed, **no change**: `article-30-2-register.md` (P-1 concerns local operator-assisted runs and makes no approval-gate
  claim); `art30-reverification-triggers.yml` (infra log-driver sites only); PA-4 (share links) and PA-17 (GitHub) make no
  approval claim.

## Published text: recommended follow-ups (NOT edited; the operator has not authorised published-text edits)

1. **Accuracy:** Privacy Policy §4.14, GDPR Policy §3.11 and Data Protection Disclosure §2.3(ab) say "the approval is bound
   to a hash of that exact body". ADR-305 states the honest limit: it is not a binding to the card. Recommend a correction
   through the full canonical+mirror+SHA procedure.
2. **No retroactive disclosure of the window** is recommended on present evidence. The published sentence "every
   individual message is reviewed and approved by a human before it is sent" describes outcomes; with 0 sends recorded
   (provisional on the pre-about-2026-07-30 residual) it was not falsified in fact. Revisit if E or G flips.
3. The Privacy Policy and DPD sentences that the send-audit record is "evidence that each cold send was human-approved"
   overstate it: the row evidences chokepoint passage, not a human decision. Fold into item 1.

## Adjacent findings (not caused by this bypass; recorded so they are not lost)

- **Audit-ledger coverage.** `audit_github_token_use` is written only for calls through `createGitHubAppClient`. The four
  gated GitHub write tools do not use it, so any statement that every App token use is recorded is untrue for them. Not
  edited here; for the CTO and a later register review. The all-time zero is also unexplained for the call sites that do
  write it.
- **`outbound_sends` is not an approval record.** It stores hashes and a Resend id, no approver or decision.

> **DRAFT — This document was generated by AI and requires professional legal review before use. It does not constitute legal advice.**
