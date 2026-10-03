---
title: "Codex Web PR 9051 — internal CLO resume disposition"
date: 2026-10-01
custodian: clo
attestation_authority: soleur-legal-clo-agent
reviewed_head: 413254b2a5bf51c32f19810c96335437bb43c921
pr: 9051
status: blocked-privacy-amendment
ack_service_basis: discharged-limited-design-scope
api_key_live_disposition: pending-no-authorization
managed_live_disposition: pending-no-authorization
customer_content_status: blocked
review_by: 2026-10-15
reevaluation_triggers:
  - "Evidence identifying the nominated account and its applicable mode-specific agreement and controls"
  - "Changes to acknowledgment purpose, ownership, retention, export, or transfer scope"
  - "First arms-length user, processing outside the evidenced geography, or regulated-industry use"
---

# Internal CLO disposition

Draft internal v1 attestation by the Soleur legal CLO agent; this is not external
counsel advice or an executed vendor agreement. The review covers the legal
amendment and source behavior at the stated head. Its implementation amendments
take effect only upon merge of PR #9051 and application of the corresponding
migrations; this audit asserts neither event has happened. Any material code or
wording change requires a delta review before discharge.

## Evidence and document inventory

| Artifact | Observed status | Required action |
|---|---|---|
| Privacy Policy, GDPR Policy, Data Protection Disclosure and published mirrors | All exist; this PR proposes attempt/checkpoint and erasure amendments. Privacy Policy also describes the new history acknowledgment. | Correct the acknowledgment rights classification and complete the matching DPD/GDPR disclosure below. |
| Article 30 register and compliance posture | Existing Web Platform activity amended conditionally on merge; acknowledgment basis is marked provisional. | Apply this limited basis determination and accurate owner/rights wording in the entries themselves. |
| OpenAI vendor snapshot, CLO packet, qualification record | Existing public-policy research and local managed smokes; both mode-specific provider relationships remain unverified. | Retain pending status for live Web use until mode-specific private evidence and qualification exist. |
| T&C, AUP, cookie policy, disclaimer, individual CLA, corporate CLA | Existing documents; none is modified by this PR's reviewed legal diff. | No T&C version bump or CLA signing is authorized by this assessment. |
| DPA template | This PR extends TOM 4 and corrects mutable-table exceptions in TOM 7. | State migration 150's conversation-owner check in the acknowledgment RPC description. |

Source records reviewed: `compliance-posture.md` (last_updated 2026-09-30),
`data-processing-agreements/openai.md` (snapshot 2026-09-25),
`clo-decision-packet.md` and `codex-qualification-record.md` in
`knowledge-base/project/specs/feat-one-shot-codex-web-rollout/`, plus the legal
diff and migrations 143, 149, 150 and 152. Stated historical live observations
come from those records; this review did not independently repeat them.

## Account nomination and separate mode dispositions

On 2026-10-01 the operator nominated the account currently signed in to this
session as the synthetic test-account reference. This identifies intent; it
does not resolve which OpenAI account/workspace, Soleur account or browser
identity is meant, or prove those identities match. No account name, email,
credential value or private customer content is recorded here. Engineering
must reconcile the session and intended Web identity through safe references.

| Required field | API-key mode | Managed ChatGPT sign-in mode |
|---|---|---|
| Decision/date | **PENDING — no live Web authorization**, 2026-10-01; not a merits rejection. | **PENDING — no live Web authorization**, 2026-10-01; not a merits rejection. |
| Account/agreement evidence | Operator's session-account nomination; previous records found no valid OpenAI key in the named Soleur test workspace. No API organization/project or accepting entity/agreement is established. | Operator's session-account nomination; recorded local signed-in CLI/App Server smokes. No verified personal/Business/Enterprise plan, provider workspace or accepting entity/agreement is established. |
| Permitted data/cohort now | Offline preparation using wholly invented fixtures only; **no provider egress or live cohort**. | Offline preparation using wholly invented fixtures only; **no provider egress or live cohort**. |
| Geography/transfer basis | Unknown for the nominated account. Public DPA language does not establish this account's coverage or route. | Unknown for the nominated account. Session login does not establish a managed-workspace agreement or its transfer safeguards. |
| Retention/erasure | Project controls and endpoint exceptions unverified. No claim of ZDR or complete remote erasure. | Account controls unverified. Recorded delete acknowledgment and `thread not loaded` response establish neither remote erasure nor residual-log retention. |
| Billing owner/administrators | Unverified; ChatGPT sign-in supplies no API key or API spending authority. | Unverified; no administrator, payer, plan allowance or right to install the session credential in Web is inferred. |
| Restrictions/review date | No credential extraction, provider request, shared-state write, default/cohort flag enablement, repository history, third-party or customer content. Reassess by 2026-10-15 or sooner on new evidence. | Same restrictions and review date; no fallback to a different provider identity. |

Synthetic prompts alone do not prove that account or connection metadata is
non-personal or that a provider relationship is permitted. A future narrow
synthetic-egress disposition may be granted separately after identification of
the actual account and permitted usage path; it cannot be inferred from this
offline allowance. Customer-content approval requires the full mode-specific
account/agreement, transfer, retention, erasure, billing and administrator
findings plus the independent Web qualification chain. Keep the feature
default-off and PR draft while those gates remain open.

## Migration 149 acknowledgment basis — limited DISCHARGED finding

The internal design determination is **Article 6(1)(b)** solely for the current
instruction needed to continue an explicitly requested conversation under a
valid Web service contract with that data subject. The protected record binds
the instruction to one conversation, provider auth-mode generation, current
membership epoch and acknowledgment time. The durable generation/epoch check
prevents a subsequent continuation or reconnection from silently reusing an
instruction for another account binding; a browser-only marker would not
provide that service safeguard. Retention is tied to this current instruction,
not a separate indefinite evidentiary archive.

This is a service instruction, not Article 6(1)(a) consent or authorization to
transmit another person's data. It does not supply an Article 9 exception,
Article 28 agreement or Chapter V transfer mechanism. The determination does
not establish the actual contract of the nominated tester or authorize live
egress. Non-contractual internal personnel processing requires its own basis;
the operator nomination does not establish one.

Implementation anchors: migration 149
`record_codex_history_transfer_acknowledgment()` and
`purge_stale_codex_history_transfer_acknowledgments()`;
`purge_codex_history_transfer_acknowledgments_on_member_change()` and account/
conversation CASCADE foreign keys; migration 150's replacements of
`record_codex_history_transfer_acknowledgment()` and
`codex_history_transfer_acknowledged()` require the caller to be both the
conversation owner and a current workspace member. The table has RLS with no
client policies or direct client table grants. `collectDbTables()` in
`server/dsar-export.ts` projects all acknowledgment columns for the subject.
These are source findings, not applied-schema or runtime proof.

The conditional service-necessity interpretation follows the EDPB's requirement
to establish a valid contract and objectively necessary processing; a button
click or contractual clause alone is insufficient. [EDPB Guidelines 2/2019,
paras. 22–33](https://www.edpb.europa.eu/system/files/documents/files/file1/edpb_guidelines-art_6-1-b-adopted_after_public_consultation_en.pdf).

## Tier 1 privacy amendment — BLOCKED findings and replacement text

Classification: **Tier 1 material notice amendment**, because it introduces
attempt keys/protected checkpoint data and new acknowledgment processing, and
clarifies retained lineage after erasure. These are non-T&C notice documents:
no `TC_VERSION` bump is required; canonical/mirror pairing and per-document SHA
refresh remain required by `tc-version-bump-policy.md`. Green mechanical gates
do not attest to substantive truth.

| Artifact | Current verdict |
|---|---|
| Privacy Policy and mirror | **BLOCKED**: blanket “not Article 20 portability” exclusion for the user's acknowledgment. |
| GDPR Policy and mirror | **BLOCKED**: new acknowledgment category/basis/rights missing from the continuity amendment; §3.15's native-handle exclusion needs an express migration-138 scope. |
| DPD and mirror | **BLOCKED**: add the acknowledgment category, service basis, export and purge criteria to the matching disclosure. |
| Article 30 register/compliance posture | **BLOCKED**: replace provisional basis, member-only purpose and Article-20 exclusion consistently. |
| DPA template | **BLOCKED for final attestation**: acknowledgment RPC prose should include migration 150's conversation-owner restriction. |
| ACK data model and purge source | **DISCHARGED for limited design review**; runtime qualification remains separate. |

**1. ACK rights classification.** `DSAR_TABLE_ALLOWLIST` currently calls the
acknowledgment “controller-generated” and gives it Article 15 only. The user
actively supplies the instruction; its raw occurrence/time is observed service
activity, not an inferred profile. On the proposed automated contract basis,
the blanket portability exclusion lacks support. The EDPB includes observed
user behavior within “provided” data for portability. This application to the
ACK is this internal CLO determination. [EDPB rights guide, Right to data
portability](https://www.edpb.europa.eu/sme/be-compliant/respect-individuals-rights_en#toc-9).

Replace that allowlist comment with: “The member actively supplies the
acknowledgment; its occurrence is raw service activity processed under the
requested-service contract. Include the record and its context in access and
portability exports.” Set the ACK entry to `article: "15+20"` and verify the
subject-scoped export behavior. Replace every new “not Article 20 portability”
sentence with: “The acknowledgment and its context are included in the
member's access and portability export (Articles 15 and 20).”

**2. Matching disclosure and register wording.** Add to DPD and GDPR Policy,
with their mirrors, and use in the Article 30/posture amendment:

> Effective only upon merge of PR #9051 and application of migrations 149–150,
> the Web Platform records the conversation owner's explicit instruction to
> continue history under a changed Codex account binding. The owner must also
> be a current workspace member. The protected record contains the conversation
> reference, member reference, auth-mode generation, membership epoch and
> acknowledgment time; it contains no transcript or prompt. Article 6(1)(b)
> applies only where this current instruction is necessary to perform the
> subject's requested Web service under a valid service contract. It is not
> GDPR consent or an independent provider-transfer authorization. The record
> is included in the member's Articles 15 and 20 export and is purged on
> generation or membership-epoch change, account erasure or conversation
> deletion. Provider processing remains blocked by separate mode-specific
> qualification and CLO gates.

For the DPA template RPC sentence use: “The acknowledgment recording and status
RPCs require the caller to own the conversation, be a current workspace member,
and match the current Codex binding generation.”

**3. Native-handle scope.** In GDPR Policy §3.15 replace “these records ... do
not store ... native provider handles” with: “Migration 138's bounded event
payloads exclude prompts, credentials, native provider handles and repository
content. The migration 143 amendment separately describes protected recovery
checkpoints, which may contain provider-native recovery identifiers.” Do not
describe checkpoint contents as absent from all engine records.

The attempt-key/checkpoint self-serve omissions remain expressly disclosed with
an email access path; migration 152 `anonymise_agent_engine_data()` purges
checkpoint contents and clears direct attribution, rather than proving every
retained link is anonymous. This review makes no provider-erasure or timed
lineage-retention claim. The retained-lineage necessity/bound remains a
separate existing operational-lineage assessment, not discharged by the ACK
service-basis determination.

## Public-policy limits and follow-through

The current public OpenAI DPA supplements its Services Agreement, distinguishes
EEA/Swiss contracting parties, provides transfer safeguards and qualifies
post-termination deletion. It does not identify this user's actual applicable
agreement, region or particular thread deletion. [OpenAI DPA](https://openai.com/policies/data-processing-addendum/).
OpenAI's account notice distinguishes administrator-managed and personal
workspaces and their applicable agreements. [Managed-account notice](https://help.openai.com/en/articles/20001067-data-access-for-your-managed-chatgpt-account).
ChatGPT sign-in billing and API-key billing are separate usage paths.
[OpenAI billing guidance](https://help.openai.com/en/articles/20001275-chatgpt-work-and-codex).

Public sources were checked on 2026-10-01; no private account settings,
credentials or provider calls were accessed. The EUR-Lex and one CNIL fetch
did not yield substantive text; the reasoning above relies on the linked
EDPB primary guidance and current OpenAI sources. The AI-vendor-terms threshold
is met: `knowledge-base/legal/recommended-tools.md#ai-vendor-terms` is the
external-specialist pointer for a future actual agreement review, not a reason
to defer this internal assessment to the operator.

Correct the concrete privacy/DSAR findings, then request an internal CLO delta
attestation on the resulting head. Account evidence and live Web qualifications
remain separately pending; no CLA representation, live provider authorization,
cohort permission or production-write approval is issued here.
