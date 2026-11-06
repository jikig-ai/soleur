# Brainstorm: Founder approval cards (CLI and web app) for owner-only gates

**Date:** 2026-11-03
**Issue:** #12011 (draft PR #12012, branch `feat-founder-approval-cards`)
**Lane:** cross-domain

## What We're Building

A founder-facing way to answer owner-only gates in plain words, with one shared record format that the CLI and the web app both use. First increment, for Jikigai's own gates only (the operator has a web account):

1. A plain-words **CLI approval card** for the existing Standing Delegation question: what will happen in business terms, then Yes / No / Request changes typed in words, no default on Enter.
2. A **web legal-acceptance screen** in the existing approvals area: plain-words summary and consequence, the exact text that will be recorded, three equal choices, and a fresh re-login before Yes is recorded. The answer is stored in a new `legal_acceptance` record that is kept longer than the 30-day text nulling of `approval_request`.
3. A **shared record contract** (text shown, text hash and version, founder identity, answer `method`, timestamp, choice, requested edit, links to the CTO/CLO reasoning), with an honest `method` label: `tty-ack` or `web-session`.
4. A new gate kind (`Gate: web-acceptance <id> <text-hash>`) so `hold-gate-eval.sh` and `delegation-verify.sh` can check the web record by id.

Deferred to later increments: CLI-only customer channel, peer review of delegated acts, notifications and approval history UI, run-sheet RF0 amendment.

## Why This Approach

The web app already ships a durable approval-request system (PR #11289, dark behind the `approval-queue` flag) for agent tool calls. It has approve/deny only, a closed list of 8 tool names, workspace scoping, and nulls the shown text 30 days after a terminal state. The CLI has nothing: the only recorded founder answer today is a hand-typed GitHub comment, and RF0 says an agent comment posted through the founder's login never counts.

The CTO and CLO agree on the identity point. Nothing an agent shell does is unforgeable, because the agent shares the OS user, the `gh` token and can allocate a TTY. So legal, irreversible and money acts need an answer from the founder's own browser session. Reversible, delegable production acts can be answered in the CLI at `tty-ack` strength, labelled honestly.

The operator chose to include legal acceptances in the first increment ("the gap I actually hit during the cutover") and to split operator-first, customers-later.

## Key Decisions

| # | Decision | Decided by |
|---|---|---|
| 1 | First increment = CLI delegation card + web legal acceptance, for Jikigai's own gates | Operator |
| 2 | Operator first, CLI-only customers later (GitHub environment reviewer, record in the customer's own repo) | Operator, after CTO and CLO rulings |
| 3 | CLI behaviour at a browser-only gate: print one plain-words message with the app link, carry on with work that does not depend on the answer, stop at the point that needs it; list pending cards at next session start | Operator (default, no objection) |
| 4 | Authoritative legal record = new Supabase table `legal_acceptance`, separate from `approval_request`: `authenticated` RPC, `auth.uid()` actor, write-once guard, hash chain, fresh re-auth marker, no ON DELETE SET NULL on founder id, exempt from the 30-day text null and from founder-erasure scrubbing | Ruled by CTO agent, 2026-11-03 |
| 5 | Scripts read the answer through a read-only verify endpoint (id in, text hash, choice, founder id, method, timestamp, chain head out) guarded by a new read-only token; GitHub pointer comments are cosmetic | Ruled by CTO agent, 2026-11-03 |
| 6 | State machine: `pending` -> `accepted` / `declined` / `changes_requested`, terminal per text hash; a revision is a new row with a new hash and `supersedes_id`; withdrawal is a later row, never an update | Ruled by CTO agent, 2026-11-03 |
| 7 | Separate table, reusing the `approval_request` pattern (RPC, guard trigger, forward-only status) not its rows | Ruled by CTO agent, 2026-11-03 |
| 8 | Same-model peer review is an advisory veto only, never presented as independent assurance; deterministic gates stay primary; deferred | Ruled by CTO agent and CLO advisory |
| 9 | Customer-facing wording avoids "verified", "reviewed", "legally binding", "audit-ready", "compliant" | CLO advisory |
| 11 | Re-check before Yes is an in-place email one-time code (password only if the account has one; OAuth redirect as last fallback), recorded as a separate single-use challenge, never a sign-out; requested by the operator at wireframe review | Operator request, ruled by CTO agent, 2026-11-03 |
| 10 | Visual design | Wireframes in `knowledge-base/product/design/approvals/` (see Phase 3.55 note in spec) |

## User-Brand Impact

- **Artifact:** the founder approval card and the `legal_acceptance` record (web legal-acceptance screen, CLI approval card, shared record contract).
- **Vector:** a wrongly recorded or forged acceptance, or an approval taken by reflex, binds the founder to a legal or production act they did not understand, or lets an agent act as the founder.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** The web card and durable record are shipped but dark; the genuinely new parts are the CLI card, "Request changes", legal-acceptance and production-authorization classes, and peer review. Build the record contract first, then the CLI rendering. Roadmap CP2 (#4672) is stale ("Not started") and #12011 has no roadmap row; correct CP2 and place #12011 as a CP2 child or a new Phase 4 row (founder's call).

### Engineering

**Summary:** One versioned record contract; legal acceptance stored in a new `legal_acceptance` table, read by scripts through a verify endpoint. `method` is recorded honestly. Same-model review is advisory only. PR sequence: (1) dark table, RPC, guard, chain, verify function, Art. 30 draft; (2) web card and page behind `approval-queue` with step-up re-auth; (3) verify endpoint, `Gate: web-acceptance`, CLI delegation card (independent, may ship first); (4) RF0 and runbook amendment. For CLI-only customers later: GitHub environment required reviewer, only unforgeable with a second human approver or a browser-only identity.

### Legal

**Summary:** A web click from the founder's own authenticated session is an acceptable accountability record if it carries the minimum fields and integrity properties; a CLI answer is not, unless made outside the agent's reach. `approval_request` retention (PA-38(f)) is incompatible with a legal record, so the class needs its own retention, a new Art. 30 entry or PA-38 amendment, a founder-erasure carve-out and a standalone LIA. Customer-repo storage keeps Jikigai out of controller/processor scope; Jikigai-hosted storage for CLI-only customers needs a new Processing Activity row, policy updates and counsel-reviewed instrument. Not legal advice; counsel review needed before any customer-facing use.

## Capability Gaps

- Peer-review agent with isolated context: `grep` for `isolated.context|peer.review|independent.review` in `plugins/soleur/agents` and `plugins/soleur/skills/*/SKILL.md` found only generic mentions (CPO).
- CLI approval renderer and identity verifier: `grep` of `plugins/soleur/scripts` for "approval" found only `operator-script.sh` (CPO, repo research).
- Legal-acceptance record class: `grep` for `legal_acceptance|clo_acceptance|attestation` in `apps/web-platform/server` and migrations found only unrelated hits (CPO).
- CLI-to-web bridge: `grep -rln 'approval_request\|api/approvals\|decide_approval' plugins` returned only the Data Protection Disclosure page (repo research).

## Open Questions (parked)

- Customer CLI-only channel via GitHub environment required reviewer, record in the customer's repo (needs counsel; tracked as a follow-up).
- Peer review of delegated production acts, including whether a different-model reviewer is worth the cost; kill switch wording ("stop").
- Notification when a card is waiting, approval history UI.
- RF0 and runbook amendment so a web acceptance counts for legal rows (CLO and operator edit; the cutover run sheet and #8211 gates stay as written until this ships).
- Where to anchor the hash-chain head externally (CLO to choose).
- Whether the agent can be kept from holding a JWT secret able to mint a `web-session` (CTO residual, unverified).
- UX test with a non-technical, non-legal founder on both surfaces.
- Roadmap: correct CP2 status and place #12011.
- Productize candidate: none identified.

## Session Errors

- The first CTO ruling on the legal-acceptance record store returned with no result text; it was re-requested and arrived intact.
