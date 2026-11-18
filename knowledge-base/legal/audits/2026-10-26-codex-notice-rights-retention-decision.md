---
title: "Codex notice receipts — internal rights and retention decision proposal"
date: 2026-10-26
actor: soleur:legal:clo
attestation_authority: soleur-legal-clo-agent
reviewed_head: 39cdb743116635277ea23c3e1356b5b5c3f4eecc
reviewed_worktree: pr9051-recovery-20261026
issue: 11170
related_pr: 9051
status: policy-accepted-implementation-and-clearance-pending
processing_clearance: withheld
operator_legal_risk_acceptance: approved-2026-10-26
operator_acceptance_record: "#operator-policy-acceptance-addendum--2026-10-26"
customer_content_status: blocked
reevaluation_triggers:
  - first-arms-length-user-or-noncontractual-member
  - changed-controller-processor-role-or-purpose
  - retention-extension-or-new-copy-of-notice-metadata
  - authenticator-projection-or-provider-route-change
related:
  - knowledge-base/legal/audits/2026-10-26-codex-nonce-ledger-and-hosted-auth-recheck.md
  - knowledge-base/project/plans/2026-10-26-fix-codex-notice-rights-and-retention-plan.md
---

# Internal CLO decision proposal

**The internal legal design can proceed to a concrete approval proposal:
30-minute nonce validity, at most five further minutes for primary-table
cleanup, member-scoped access, and request-time rights preservation. Processing
clearance remains withheld.** These are proposed controller policy limits, not
GDPR-prescribed periods, implemented controls, operator acceptance, professional
counsel advice or permission to contact a database or provider.

This assessment resolves the internal design choices reserved to the CLO. The
plan separately reserves operator acceptance of legal risk before implementation.
No signature or acceptance is inferred from the instruction to continue. PR
#9051 must remain draft with auto-merge disabled. This is a source-based policy
assessment, not independent exact-head engineering review.

## Inventory and factual limits

| Artifact | Source state | Action |
| --- | --- | --- |
| Privacy Policy, GDPR Policy and Data Protection Disclosure; published mirrors | All present in `docs/legal/` and `plugins/soleur/docs/pages/legal/` | Amend together after the final design is accepted and verified. |
| Controller register and compliance posture | Present; latest source commits dated October 26 | Append a migration-conditioned PA-2 amendment; preserve dated prior decisions. |
| Processor register | Present; latest source commit dated October 15 | Check actual capacity before amending; a feature proposal does not establish instructed processing. |
| DPA template and October 26 nonce-ledger audit | Present; source classification is RPC-only Customer Data, outside WORM | Preserve classification; proposed rights and time limits are additional prerequisites. |
| Issue 11170 | Verified OPEN through GitHub metadata on October 26 | Existing rights/retention tracking; no new issue is needed for the decisions below. |

Migration `175_codex_history_notice_issuance.sql` currently stores conversation,
workspace and member references, generation, membership timestamp, nonce hash,
issuance timestamp and nullable delivery timestamp. Its issue RPC replaces the
hash without refreshing `issued_at`; successful acknowledgment deletes the
issuance and inserts a separate acknowledgment. No time-based expiry or sweep
is implemented there. The service role has no direct table privileges.

`dsar-export.ts` exports acknowledgment metadata; the issuance table lacks an
export path. `codex-held-turn-cache.ts` has a 30-minute browser-memory TTL, which
neither expires database rows nor guarantees every draft remains for 30 minutes.
No shared catalog, customer record, credential, provider request or operational
cleanup behavior was inspected. This assessment does not establish the nominated
test member's contract, actual backup retention or controller instructions.

## Per-decision disposition

| Decision | Internal CLO disposition | Remaining condition |
| --- | --- | --- |
| Necessary purpose and basis | DISCHARGED for the limited design described below; account-specific application BLOCKED | Verify affected subject, valid contract and controller capacity before qualification. |
| Lifetime and cleanup | PROPOSED: validity 30 minutes; primary-table deletion within five further minutes | Reserved operator acceptance, bounded-capacity implementation and observed monitoring. |
| Article 15 and deletion after acknowledgment | DISCHARGED subject to faithful metadata projection and request-time preservation | Implement and test the race with acknowledgment, expiry and erasure. |
| Article 20 | DISCHARGED as a conservative inclusion decision for eligible non-secret activity metadata | Contract-basis eligibility must actually hold; preserve distinct acknowledgment semantics. |
| Processing clearance and publication | BLOCKED | Final code, legal wording, account facts, data/runtime/provider and ship gates remain open. |

## Purpose, lawful basis and roles

The sole ordinary purpose of pending issuance is to bind the current member's
attempted continuation to the notice generated for the current provider-account
generation and membership, rejecting a fabricated or replayed acknowledgment.
It is transient service state, not evidence of GDPR consent, proof that a human
read the notice, or an instruction to send saved conversation history. The
delivery marker records the server's send/marker operation only.

For a subject who is party to a valid Soleur service contract, Article 6(1)(b)
is the proposed basis only to the extent this short-lived binding is objectively
necessary for their requested continuation. A contract with an employer or
workspace owner does not establish a contract with every member. Such a member
requires the actual controller's documented basis and instructions, or a separate
controller assessment, before processing. No Article 6(1)(f) fallback or new
security/accountability retention purpose is approved here. The narrower service
purpose avoids retaining an authenticator for a speculative dispute or analytics
use. The account-specific factual dependency remains a qualification hold.
This application follows the necessity and valid-contract tests in [EDPB
Guidelines 2/2019, sections 2.4–2.5](https://www.edpb.europa.eu/system/files/documents/files/file1/edpb_guidelines-art_6-1-b-adopted_after_public_consultation_en.pdf).

Where Jikigai acts on a customer controller's instructions, Article 28 coverage
does not replace that controller's Article 6 assessment. The PA-2 amendment must
state the capacity actually established; do not silently extend the solo-user
determination to external team members. The notice controls add no provider
permission and leave both hosted App Server authentication modes blocked.

## Proposed retention limits

For an ordinary pending issuance, propose the following reviewable policy:

- At creation of a genuinely new nonce, set database-owned `issued_at` and an
  expiry exactly 30 minutes later. Same-nonce retries and marker repair preserve
  both times. A replacement through the explicit new-notice flow is a new
  issuance; merely reconnecting does not renew a spent notice.
- Reject delivery and acknowledgment at or after expiry using the database
  clock, regardless of whether cleanup has run. Never dispatch provider work or
  delete a held draft as a consequence of this expiry.
- Delete an ordinary expired primary-table row within at most five further
  minutes, including queue, batch, lock, retry and scheduler delay: maximum
  primary-table residence 35 minutes for an abandoned issuance. A cron interval
  alone does not prove this bound. Generation, membership, conversation/account
  deletion and successful acknowledgment can remove it earlier.
- Prove backlog capacity and bounded failure handling before qualification.
  Alert early enough to intervene before the five-minute erasure allowance is
  exhausted; block new issuance when the required cleanup health is unavailable.
  A missed bound is a retention failure to report and remediate, not an implied
  extension or proof that expired rows were deleted.

The proposed 30 minutes is a conservative ceiling for an interactive decision
and brief reconnect, with no ongoing purpose after that interaction has lapsed.
It is a new server policy requiring enforcement; the browser TTL supplies
context, not lawful-basis evidence. Longer retention has no demonstrated benefit
in the inspected source. The five-minute allowance limits disposal latency and
must be reduced if the selected mechanism can safely erase sooner. Neither
duration is asserted to be a statutory safe harbor. Storage limitation and
transparent retention criteria remain applicable under [GDPR Articles 5, 13 and
15](https://eur-lex.europa.eu/eli/reg/2016/679).

This ceiling describes the primary issuance table. It is not a promise that a
managed database backup or PITR copy disappears within 35 minutes. Establish and
disclose the applicable backup window, access restrictions and re-deletion on
restore before clearance; do not export hashes to logs or copy them into rights
preservation. A rights-response copy has a separate, narrowly documented purpose
and lifecycle below, rather than extending the live nonce's lifetime.

## Article 15 projection and post-consumption deletion

Approve a narrow server-only projection, with subject validation, that returns
all retained non-secret subject metadata: `conversation_id`, `workspace_id`,
`member_user_id`, `auth_mode_generation`, `workspace_member_created_at`,
`issued_at`, `delivered_at`, and the new expiry value if stored. Explain the
generation and membership timestamp in the bundle. A faithful intelligible
equivalent is acceptable; calling a field internal is not a reason to omit it.
No other member's row or unrelated workspace data may be returned, and no direct
table grant is authorized.

Exclude the raw nonce and `nonce_hash` from the automatic bulk projection:
the latter can itself satisfy the SQL acknowledgment predicate if disclosed to
an authenticated caller, defeating the notice-possession safeguard. Describe
the omitted authenticator category and its security purpose without its value.
This technical projection is not a blanket legal exemption for an explicit
request seeking that data. The rights case must assess a faithful safe form or
non-replayable disclosure after invalidation, or identify and explain an actual
applicable restriction. Do not cite Article 15(4) without a concrete adverse
effect on others. [Irish DPC access guidance](https://www.dataprotection.ie/en/organisations/know-your-obligations/access-and-portability)
requires a demonstrated, proportionate ground for withholding information.

Routine deletion on acknowledgment is acceptable for this transient purpose;
do not create a permanent issuance history solely to service hypothetical future
requests. A request received after genuine prior deletion does not resurrect
deleted data. The surviving acknowledgment remains a separate export record
and must not be described as a complete history of notices.

**Required plan correction:** scope rights to the time the controller receives
the request, not the later async worker read. Capture or otherwise preserve the
eligible non-secret projection when the request is accepted, with an equivalent
procedure for the email channel. Make races with consume, cleanup and lifecycle
deletion explicit; a queued job cannot silently omit a receipt that existed at
request receipt. No preservation copy may keep a replay authenticator alive.
The preservation operation serves rights fulfillment under Article 6(1)(c),
with controlled retention no longer than necessary to fulfill the request and
the separately justified rights-case lifecycle. Do not equate a seven-day
download-link validity with proven deletion of the underlying archive. These
request-time and prior-deletion distinctions follow [EDPB Guidelines 01/2022,
sections 2.3.3 and 4.2.2](https://www.edpb.europa.eu/system/files/documents/2023-04/edpb_guidelines_202201_data_subject_rights_access_v2_en.pdf).

## Separate Article 20 decision

For the verified Article 6(1)(b) service population, include the same non-secret
issuance/delivery activity projection in the machine-readable portability bundle
and tag that eligible projection `15+20`. This is an intentionally conservative
internal inclusion decision, not a claim that every controller-generated field
is necessarily portable. The record accompanies the member's attempted service
continuation and is raw operational event context; merely being generated by a
server is not enough to exclude observed activity. No inference, risk score or
profile is being exported. The nonce authenticator remains outside that bulk
projection for the specific reason above. [CNIL portability guidance](https://www.cnil.fr/fr/respecter-les-droits-des-personnes/professionnels-comment-repondre-une-demande-de-droit-la-portabilite)
distinguishes declared/observed activity, including event history, from derived
or inferred data. This decision was made separately from the existing
acknowledgment's `15+20` label.

A delivery timestamp still does not assert reading or acknowledgment. Where the
underlying processing is not eligible under Article 20(1), Article 15 remains
available and any voluntary additional machine-readable copy must be described
as such. Processing for that population remains blocked until its basis is
established. Exporting metadata does not transfer a saved transcript or grant
permission to send it to a provider.

## Exact reserved operator acceptance proposal

> Accept this proposed legal-risk policy for the separate notice-rights and
> retention correction: nonce use expires after 30 minutes; ordinary pending
> primary-table rows are erased within at most five further minutes; no permanent
> issuance history is added; access preserves non-secret metadata existing when
> a request arrives; eligible service-activity metadata is also included in
> portability. Contract basis applies only to a verified contracting subject and
> objectively necessary service state; other roles stay blocked until separately
> assessed. This accepts the policy for implementation and isolated testing,
> subject to the controls and final CLO verification in this assessment. It does
> not approve shared evidence capture, database reconciliation/migrations,
> provider requests, customer processing, PR readiness, merge or deployment.

Acceptance is pending. The founder is asked to accept the stated residual legal
risk, not to supply the legal research or certify technical enforcement.
Engineering must update the plan, implement with a new forward migration,
verify request-time completeness and cleanup bounds, and return the final
projections and cross-document wording for internal CLO attestation. Append a
dated PA-2/compliance record and amend the Privacy Policy, DPD and GDPR Policy
with their mirrors, conditioned on the actual correction's merge/application.
No earlier migration bytes or dated legal conclusions are rewritten by this
proposal.

## Assessment execution limits

Primary public legal sources were retrieved on October 26. EUR-Lex's direct
OJ endpoint presented a JavaScript check; the indexed consolidated EUR-Lex text
and EDPB final access/contract PDFs were available. The Commission portability
download returned an unsupported content type and a subsequent EDPB endpoint
returned 429; current CNIL guidance supplied the portability distinction.
No failed retrieval was treated as source evidence. The first restricted
GitHub metadata call failed on network access; its normally approved retry
verified issue state. No shared-data or provider action occurred.

This record provides the internal v1 legal design proposal only. Final source
and legal review, factual basis/capacity evidence, backup and rights-copy
retention verification, operator acceptance, qualification, QA and preflight
remain required. External counsel re-review is triggered by the frontmatter
conditions. No processing or shipping hold is discharged by this record.

## Operator policy acceptance addendum — 2026-10-26

The operator explicitly answered **“Approve the proposed legal-risk policy”**
to the complete proposal in this session, as relayed by the parent
orchestrator. This accepts the stated policy for implementation and isolated
testing: 30-minute nonce validity, deletion of ordinary pending primary-table
rows within at most five further minutes, request-receipt-time preservation of
non-secret access metadata, eligible portability, and no permanent issuance
history. Article 6(1)(b) remains conditional on a verified contracting subject
and objective service necessity; other roles stay blocked until separately
assessed. Final CLO verification remains required.

> **Superseded 2026-10-26, solely as to operator acceptance status:** the original
> proposed-policy text and its statements that acceptance is pending above are
> preserved as the historical pre-approval record. The acceptance prerequisite
> is now satisfied for this exact policy; no implementation or processing fact
> is established by that acceptance.

The approval does not authorize fresh shared capture, database reconciliation
or migrations, provider requests, customer-content processing, PR readiness,
merge, deployment or shipping. Source implementation and testing,
request-time completeness, cleanup-capacity and monitoring verification,
contract/controller-capacity facts, backup and rights-copy retention evidence,
final legal wording and CLO attestation, qualification, QA and preflight remain
open. Processing clearance stays withheld; PR #9051 remains draft with
auto-merge off. No shared-data, provider or production operation was performed
to record this approval.
