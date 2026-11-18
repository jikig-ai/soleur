---
title: "Codex Web PR 9051 — nonce ledger classification and hosted-auth recheck"
date: 2026-10-26
actor: soleur:legal:clo
attestation_authority: soleur-legal-clo-agent
reviewed_head: 912d84902027b7f37cfdb575f44ed97f77b8323b
reviewed_worktree: pr9051-recovery-20261026
reviewed_source_delta: uncommitted-byte-preserving-migration-renumber-165-through-175
provider_document_retrieval_date: 2026-10-26
pr: 9051
status: source-classification-attested-live-clearance-withheld
nonce_ledger_tom4_classification: shape-iv-customer-data-zero-policy-rpc-only
nonce_ledger_processing_clearance: pending-retention-rights-and-purpose-record
api_key_app_server_auth_disposition: blocked-documented-hosted-auth-restriction
managed_app_server_auth_disposition: blocked-documented-hosted-auth-restriction
alternative_api_funded_route_disposition: pending-exact-route-review
customer_content_status: blocked
prior_audits:
  - knowledge-base/legal/audits/2026-10-12-codex-web-hosted-auth-restriction.md
  - knowledge-base/legal/audits/2026-10-21-codex-web-hosted-auth-recheck.md
  - knowledge-base/legal/audits/2026-10-22-codex-web-route-delta.md
---

# Internal v1 CLO assessment

**Classify `codex_history_transfer_notice_issuances` as TOM 4 shape (iv):
Customer Data protected by RLS with zero policies and narrowly scoped definer
RPCs. The missing classification must be repaired, without a waiver or a
`NOT_CUSTOMER_DATA` exemption. Both hosted App Server authentication modes remain
blocked.** This attestation settles the source classification only. Retention,
rights handling, runtime qualification and provider permission remain separate
conditions.

This is an internal v1 CLO assessment, requiring professional legal review;
it is not external counsel advice, an executed agreement or provider permission.
The CLO agent owns this internal attestation. No legal research or technical
review is delegated to the founder as a substitute for completing it.

## Inventory and evidence limits

The inventory found the compliance posture, Article 30 controller and processor
registers, OpenAI DPA review, DPA template and dated Codex audits. This assessment
supplements their dated records; it does not rewrite prior attestations.

| Source | Relevant anchor and scope |
| --- | --- |
| `knowledge-base/legal/compliance-posture.md` | `Agent-engine processing (migration 138 / PR #8082)` and dated attempts/acknowledgment amendments, including the October 3 correction |
| `knowledge-base/legal/article-30-register.md` | PA-2 and its acknowledgment amendments; the explicit service instruction is distinct from GDPR consent |
| `knowledge-base/legal/article-30-2-register.md` | Processor record inventory; this audit does not infer a fresh executed customer or provider arrangement |
| `knowledge-base/legal/data-processing-agreements/openai.md` | Existing contract/control review and dated corrections; reports about account acceptance, a US$5 setting and key duration remain historical, bounded evidence |
| `knowledge-base/legal/data-processing-agreement-template.md` | Schedule 4, TOM category 4, shape (iv); category 7 distinguishes mutable operational records from WORM accountability ledgers |
| October 12 and October 21 hosted-auth audits; October 22 route delta | Existing mode blocks, API-funded candidate and outstanding account/implementation conditions |
| `apps/web-platform/supabase/migrations/175_codex_history_notice_issuance.sql` | Table, issue/delivery/delete functions, purge triggers and three-argument acknowledgment consumer |
| `apps/web-platform/server/ws-handler.ts` | `dispatchCodexChatTurn`, `persistCodexNoticeDeliveryOnce`, `discardCodexNoticeIssuance`, `codex_history_transfer_acknowledge` case |
| `apps/web-platform/lib/codex-held-turn-cache.ts` | Tab-memory draft/nonce retention, separate from database retention |
| `apps/web-platform/server/dsar-export-allowlist.ts`; `server/dsar-export.ts` | Acknowledgments are included; issuance metadata currently has neither an allowlist entry nor an explicit exclusion/read path |
| `apps/web-platform/test/rls-fuzz/targets.ts` | `EXCLUDED_ISOLATION` explains why a tenant SELECT positive control cannot apply to the private issuance table; it is not a legal exemption |
| `scripts/check-tom4-rls-posture.sh` | `SHAPE_IV`, `NOT_CUSTOMER_DATA`, assertions 3–8 and the requirement to classify new zero-policy tables |

The worktree contains a pending migration filename renumber. The reviewed file
is **175**, retaining the SQL formerly named 173; this audit does not authorize
rewriting its bytes or clearing a Git guard. Its reviewed SHA-256 is
`ddaed3842b9a8de8ee0d7d8126434f30e47dda0a8a336d7fa1fde013abf3f66d`.
This is source review, not an attestation that migration 175 has run anywhere.

The earlier private capture is unavailable after worktree loss. Committed
October 25 recovery summaries/digests preserve historical observations, including
the known legacy two-argument acknowledgment surface; they do not establish the
current live catalog or its writer provenance. No account credential, browser
login, model request, shared database read, flag or production action was used
for this assessment. The reported TOM4 fixture/mutation failures are tracked by
the engineering workflow; this audit does not relabel them as passing tests.

## Source classification and exact gate repair

The table links a conversation, workspace, identified member, authentication
generation and membership epoch to a nonce hash and issuance/delivery times.
There is no message body or raw nonce column, but the linked record remains
pseudonymous personal data and Customer Data. Hashing the nonce does not make
the member-linked row anonymous.

The reviewed SQL enables RLS, creates no table policy and explicitly revokes
**all direct table privileges from PUBLIC, anon, authenticated and service_role**.
Owner execution through `SECURITY DEFINER` functions supplies the intended
reachability; each function pins `search_path = public, pg_temp` and qualifies
relations. The service role can execute the issue, delivery-marker and unsent
delete RPCs. Only `authenticated` can execute the new three-argument
`record_codex_history_transfer_acknowledgment`. The legacy two-argument consumer
is revoked and dropped. The issue and acknowledgment paths recheck the current
owner/workspace binding, generation and membership epoch under locks.

These controls support shape (iv), with a stronger direct-table restriction
than the neighboring acknowledgment table. The generic label
“service-role-only” must not imply a direct service-role SELECT grant here.

Implementation-ready changes:

1. Add exactly `codex_history_transfer_notice_issuances` to `SHAPE_IV`. Leave
   `NOT_CUSTOMER_DATA` unchanged. Against the reviewed sets, shape (iv) increases
   from **12 to 13**, the other zero-policy set remains **9**, and their union
   becomes **22**. The script computes these counts; do not add a hard-coded
   global count exception or disable assertions 3/4.
2. Add the table to Schedule 4 TOM category 4's named enumeration, with its
   actual RPC/role split, current membership/generation checks, nonce consumption
   and lifecycle deletion. Preserve zero policies and explicit direct revokes,
   including service_role. Do not describe issuance as an immutable WORM ledger.
3. Pin the issuance invariant in the gate/regression coverage: an added client
   table grant/policy, a direct service-role grant or broadened RPC grant must
   fail the appropriate assertion. Preserve the owner-bypass invariant and the
   unique `runtime_mint_intent` auth-admin exception. Narrow RPC access is not
   authorization to add another bypass principal.
4. Rerun the full TOM4 baseline and mutation battery after the coordinated
   classification/documentation change. The classification is attested here;
   its implementation and verification remain engineering work.

## Purpose, rights, retention and notice evidence

The local purpose is to bind an issued history-transfer notice to the current
member and generation, prevent replay and avoid recording an acknowledgment
without a matching issuance. Pending issuance is generated before the member's
acknowledgment. It must not inherit a claim that it is already the member's
explicit transfer instruction.

The internal candidate basis remains Article 6(1)(b) only to the extent this
state is objectively necessary to perform the validly requested service.
Independent security/accountability use requires its own necessary purpose and,
if Article 6(1)(f) is chosen, a documented legitimate-interests assessment. This
audit does not attest an unspecified alternative basis or infer GDPR consent.
The GDPR separates purpose, minimisation, storage limitation and lawful basis;
linked hashes are not an exception. [GDPR Articles 4–6](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679).

The following conditions remain before collecting this state for a live cohort:

| Condition | Actual source and required completion |
| --- | --- |
| Retention | One current row per conversation/member/generation/epoch is upserted. Successful acknowledgment consumes it; auth-generation and membership-epoch changes purge it; member/account/conversation deletion cascades. Unsent deletion requires `delivered_at IS NULL`. These are real lifecycle bounds, but there is **no server-side TTL or expiry check**. A delivered, unconsumed row may persist while its parents and generation persist. Record a justified maximum and enforce expiry/cleanup for abandoned issuance before qualification. |
| Timestamp semantics | Reissuing replaces the hash and clears `delivered_at` without resetting `issued_at`. A future expiry implementation must specify whether its clock starts at first issuance or current nonce replacement and test that choice. Do not advertise a fresh nonce lifetime based on the old timestamp accidentally. |
| Browser cache | The held-turn cache's 30-minute tab-memory TTL, bounded entries/bytes and sign-out clearing reduce local draft exposure. They do not expire the database issuance or establish provider retention. |
| Article 15 | Add member-scoped access to issuance metadata or an explicit, functioning alternative subject-access path, plus completeness coverage. Acknowledgment export alone omits issuance/delivery state. Prefer a narrowly scoped export RPC/projection to preserve the direct-table revocation invariant. Any withheld nonce hash needs a specific security rationale and rights handling; “private table” is not a blanket subject-access exemption. |
| Article 20 | Do not automatically copy the acknowledgment row's `15+20` classification. The issuance is controller-generated integrity state. Record the reasoned portability assessment separately from access; access coverage must not wait for it. |
| Article 17 | Verify current account, conversation and membership deletion cascades in the disposable database and document abandoned-row expiry. No new arbitrary long-term legal-retention exception is attested. |

Access and portability have different statutory tests; storage must have a
necessary duration, not merely an eventual parent deletion. [GDPR Articles 15,
17 and 20](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679),
[European Commission storage-limitation guidance](https://commission.europa.eu/law/law-topic/data-protection/information-business-and-organisations/principles-gdpr_en).

Append a dated, merge-and-migration-conditioned nonce-issuance amendment to
PA-2/compliance processing records: purpose, fields/subjects, recipients and
role distinction, provisional basis analysis, access route, retention and
cascade behavior. Preserve the October 3 acknowledgment correction and its
existing Art. 15+20 treatment. Update the processor register only for the actual
processor activity established; this local control adds no permission to send
data to OpenAI. No existing dated register row is changed by this audit.

The source's `delivered_at` means that a bounded service call recorded a marker
after transport delivery/repair. An authenticated client with the nonce can
submit the acknowledgment; the source has no independent proof that the notice
was rendered, read or understood. Nor would a render event prove comprehension.
Describe it as issued/delivery-marked/explicitly acknowledged under this
protocol, and qualify the actual UI notice and member action on the served
build. It is not proof of GDPR consent or provider permission. Acknowledgment
does not itself resume a held provider turn; subsequent dispatch remains gated.

## Fresh hosted-authentication disposition

Official documentation was retrieved on October 26. The App Server
`Auth endpoints` section expressly excludes commercial/hosted App Server
authentication; the restriction precedes the listed API-key, ChatGPT-managed
and external-token modes. Availability of a protocol mode is not permission for
this deployment. This is an authentication-arrangement finding, not a claim
that every use of the executable is prohibited.
[Codex App Server, Auth endpoints](https://learn.chatgpt.com/docs/app-server#auth-endpoints).

Sign in with ChatGPT's public plan-usage documentation covers open-source/local
apps and directs paid or remotely hosted apps to an interest form. It is not a
standing permission for Soleur's hosted managed mode. No form submission or
provider contact is authorized or performed here.
[Sign in with ChatGPT overview](https://developers.openai.com/siwc/token-sharing-open-source).

The SDK documentation describes a server-side TypeScript library, while its
Python library explicitly controls App Server. A dependency rename therefore
cannot discharge the restriction. The October 22 distinct API-funded
TypeScript/`codex exec` candidate remains subject to review of the exact launch,
authentication, endpoint, storage, tools/network and account controls.
[Codex SDK](https://learn.chatgpt.com/docs/codex-sdk).

| Path or data class | October 26 disposition |
| --- | --- |
| Hosted API-key App Server authentication | **BLOCKED** pending provider evidence permitting the precise arrangement or a reviewed distinct integration |
| Hosted managed ChatGPT App Server authentication, including external token substitution | **BLOCKED**; no public hosted permission inferred |
| Distinct API-funded TypeScript SDK/exec candidate | **PENDING** concrete implementation/account review; not an authorization to make a request |
| Offline invented fixtures, isolated recovery rehearsal and build/static/functional QA | May continue within existing engineering containment, with zero provider requests, customer content, account authentication and shared/production mutations |
| Customer-content processing in either proposed mode | **BLOCKED**, including genuine histories offered as “test” data |

The current `codexConversationRuntime` declares customer data with an empty
accepted-data-class set, unverified vendor DPA, unknown geography/deletion
support and approval required. Its endpoint declaration is not evidence of a
completed request. `createCodexAppServerLauncher` launches `app-server --stdio`;
that seam does not implement or approve the distinct candidate. Neither source
fact cures the hosted-authentication condition.

Remaining qualification must establish the actual permitted integration and
entity/agreement coverage; credential custody, revocation/deadline and spend
enforcement; transfer geography and provider retention/deletion; local rights
and retention controls; and authenticated served-build behavior for the exact
head. Previous owner reports remain bounded historical evidence. Broad
non-production approval removes repeated owner permission prompts within its
scope; it supplies none of these missing facts. Keep PR 9051 draft, auto-merge
off and customer content blocked while these conditions remain.

## Attestation boundary

**Discharged here:** the nonce table belongs in the Customer Data zero-policy
TOM4 category, with the stronger RPC-only direct-privilege description above.
**Not discharged:** the gate repair/tests themselves, live catalog recovery or
writer coordination, nonce processing clearance, notice/UI qualification,
provider permission, either hosted mode, customer-content clearance or release
readiness. Later evidence must supplement this dated record rather than silently
replace its conditions.
