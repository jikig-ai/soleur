---
title: "Corporate CLA signing mechanism"
date: 2026-09-04
slug: feat-ccla-signing-mechanism
branch: feat-ccla-signing-mechanism
type: feature
lane: cross-domain
issue: 3210
closes: [3210]
related: [3211, 7813, 7814, 7816, 7625, 7668, 7670, 7832, 7218]
priority: P1
domain: legal
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
clo_ruling: knowledge-base/legal/audits/2026-09-04-clo-ruling-ccla-register-siting-and-coverage-map-basis-3210.md
brainstorm: knowledge-base/project/brainstorms/2026-09-04-ccla-signing-mechanism-brainstorm.md
spec: knowledge-base/project/specs/feat-ccla-signing-mechanism/spec.md
---

# Corporate CLA signing mechanism

## Overview

`docs/legal/corporate-cla.md` is published and binding, yet no code path records a
Corporate CLA anywhere. Recognising a corporate contributor today means editing the
`allowlist:` string inside a `pull_request_target` workflow, which misclassifies a
contributor who holds a real IP grant as a maintainer-class bypass in a ten-year
write-once archive, and which has already taken every pull request in the repository
offline once (#7597).

This plan records the Corporate CLA through the mechanism the executed instrument itself
specifies — a maintainer-held roster of GitHub usernames, per §4(c) and §5 — splits that
record into a public coverage map carrying no personal data and a private signatory
register carrying the rest, folds roster verification into the existing `cla-evidence`
job rather than adding a third required check, and corrects two published surfaces that
describe a signature record which has never existed.

**The design turns on one rule the spec did not have.** A representative's account enters the
tracked roster **only at or after that person has themselves signed the Individual CLA on a pull
request here** — *contribution-triggered entry*. The CLO ruling adopts it, and it is the spine of
the plan: it collapses B1, B2 and the Art. 17 problem into one answer, because the population that
could not be justified on an irreversible public surface never reaches that surface at all.

**Two scope decisions were taken by the operator at plan review**, both reversing a prior
decision on measured evidence:

1. **The `cla-evidence.yml` roster-verification step is deferred** to the PR that unblocks the R2
   write — reversing CTO Key Decision 5 and spec FR4. Measured: the step is fail-open, writes no
   evidence record (NG6/AC5), and its receipt-comment output is gated on an `issue_comment` sign
   comment a returning contributor never posts — so its only durable output today is a `::notice::`
   in a 90-day log, while P4 is bought permanently by the roster file's git history. Deferring it
   also removes `roster-verify.ts`, Guard 1, AC4 and the base-ref threat model, and leaves a
   simpler, truer ADR. Record the reversal in ADR-201.
2. **The operator affordance is a script, not a skill** — `apps/cla-evidence/scripts/ccla-add.sh`,
   reversing spec FR6. Measured: the two most operator-facing CLA affordances that already exist,
   `gdpr-override.sh` (Art. 17 erasure) and `inspect-evidence.sh`, are both scripts in that
   directory with runbooks, and a `git grep` for either across `plugins/soleur/skills/` returns
   zero. A skill would also cost a bump against a measured **2400/2400 zero-headroom** description
   budget shared by 96 skills.

**One blocking finding changes the spec's shape.** The spec's "private signatory record"
is sited at `knowledge-base/legal/ccla-register.md`. That path is tracked in a repository
whose visibility is `PUBLIC`, so as specified the register publishes exactly the data it
promises to withhold, permanently and irreversibly. See
[Blocking Finding B1](#blocking-finding-b1--ruled-the-private-register-is-public). It gates one
step — writing identity fields into a tracked file — and **not** the rest of Tier 0: the first
corporate contributor can still be served this week.

## Research Reconciliation — Spec vs. Codebase

Every row was measured against `origin/main` at plan time, not paraphrased.

| Spec / brainstorm claim | Reality | Plan response |
|---|---|---|
| KD7/FR2: signatory register at `knowledge-base/legal/ccla-register.md` is **private** | `jikig-ai/soleur` is `visibility=PUBLIC`; `knowledge-base/legal/` holds **69 tracked files** on `origin/main` | **B1 — blocking.** Route to CLO with measured options; Tier 0 gated on the answer |
| KD13: split public coverage map / private signatory record | Sound in principle, but no private surface exists. `knowledge-base/private/` is gitignored (`.gitignore:60`) and **does not exist**; the archived Art. 30 plan tried the same gitignore approach and the register is tracked-and-public today | B1 must pick a surface that is private *by construction*, not by `.gitignore` discipline |
| TR3: "three hardcoded occurrences in `cla-evidence.yml`" plus `build-record.ts` | Confirmed at `:55`, `:128`, `:217` and `build-record.ts:98` — **but a fourth producer was never enumerated**: `backfill.ts:55` writes the same literal. Test fixtures at `schema.test.ts:20` and `hash.test.ts:8,11,17-18` also carry it | Widen the discriminant work-list to **5 producer sites + 2 test fixtures**. Explicitly **exclude** `cla.yml:45`/`:60` — those are the action's ICLA document URL and are correct as-is |
| FR5: add `apps/cla-evidence/roster/` to CODEOWNERS to protect the roster | `.github/CODEOWNERS` already has `* @deruelle` as a default fallback, so the path is covered today. More importantly **CODEOWNERS review is enforced nowhere**: `repos/:owner/:repo/branches/main/protection` returns `404 Branch not protected`, and no active ruleset carries a `pull_request` rule | Keep the row for legibility and future-proofing, but the plan must **not** count it as a control. The self-authorization defense is the base-ref read alone |
| KD12: base-ref read is a new invariant to build | Already built and reviewed: `cla-evidence.yml:51-54` checks out `github.event.pull_request.base.sha` with the inline comment *"Base ref only — never check out PR head under `pull_request_target`."* | Not new machinery. Reduce to a documented invariant + a guard row that reds if the `ref:` moves |
| KD5: a third required check costs "a five-file lockstep" | Undercounted, and the real cost is worse. The lockstep is `infra/github/ruleset-cla-required.tf`, `scripts/ci-cla-required-ruleset-canonical-required-status-checks.json`, `scripts/create-cla-required-ruleset.sh`, `scripts/required-checks.txt`, `plugins/soleur/test/required-checks-canonical-parity.test.sh` (Test 7) and `.github/actions/bot-pr-with-synthetic-checks/action.yml`. Adding a **content-scoped** check to `required-checks.txt` additionally trips the **#6049 auto-fabrication guard** — it fabricates a green for every bot PR unless reproduced in the action's Phase-4 ceiling | KD5 **strengthened**, not weakened. Fold into `cla-evidence`. Cite the real paths — the three the brainstorm named do not exist at the paths it gave |
| Open Question 5: "no body drift on either CLA — now is the cheap moment to enrol in `BODY_EQUIVALENCE_DOCS`" | **False.** Measured with the canonical normaliser (`scripts/lib/legal-normalise.sh`): `individual-cla` **DRIFT**, `corporate-cla` **DRIFT** (control: `terms-and-conditions` ZERO DRIFT). Three classes: the canonical `**Version:**/**Effective Date:**` block vs the mirror hero; a `>` blockquote marker; and a real body divergence `legal@jikigai.com` vs `<legal@jikigai.com>` at §5 and §Signing | **Do not enrol.** The code's own rule is *"Enrolled AFTER each reported ZERO normalised drift, never before"* (`check-tc-document-sha.sh:131-136`). Record the measurement; harmonise only the two autolink instances FR8 already touches |
| `article-30-register.md` may need an Eleventy mirror sync | No mirror. The register exists only at `knowledge-base/legal/`. `scripts/generate-article-30-register.sh` is **vestigial** — it renders an archived Feb-2026 template to a gitignored repo-root file and is invoked by nothing | Triple lockstep applies to `docs/legal/*.md` only. PA-7 is a hand edit |
| PA-7 §(c) declares capture of "signatory name + corporate email + corporate identity" | Verbatim confirmed. But `corporate-cla.md` §Signing asks only for org name+address, signatory name+title, and usernames — **it never asks for the corporate email** the disclosures promise to hold | FR8 must reconcile all three surfaces, not two. Adding the email to §Signing aligns the instrument with what KD9 requires us to collect anyway |
| KD11: the upstream action has no org concept | Confirmed from two sides — the action's inputs, and the data: `origin/cla-signatures:signatures/cla.json` has a flat `signedContributors` array with no org field | No change. Also corroborates KD4: the incumbent ledger **already keys on numeric `id`** (`deruelle`=54279, `Elvalio`=92384917), so id-matching is continuity, not invention |
| Learnings research: *"`pull_request_target` — never add `actions/checkout`"* | **Not propagated.** Over-generalised. `cla-evidence.yml` is `pull_request_target` and *does* check out — at the base ref, which is precisely the safe pattern. The rule is never check out the **head** | Design stands unchanged. Recorded because propagating it would have destroyed the mechanism |
| Learnings research: skill description budget is `1798/1800`, ~2 words headroom | Stale by five months. Measured: `SKILL_DESCRIPTION_WORD_BUDGET = 2400` (`components.test.ts:16`) and the live total is **2400/2400 — exactly zero headroom** | Bump by exactly the new description's word count, following the twelve documented precedents in that constant's own comment |

## Research Insights

### Premise Validation (Phase 0.6)

Every cited reference was probed. **All premises held; none was stale.** Every one of issues #3210, #3211, #7813, #7814, #7816, #7625, #7668, #7670 and #7832 is `OPEN` — so the blockers
KD7 relies on are genuinely unresolved and AC5 is live. #7597 is `MERGED`, #7349/#7624 are
`CLOSED`, #3209 closed `2026-05-16` (making the 30-day CPO+CLO sync trigger **111 days**
overdue as of today, not the 81 the brainstorm computed against a different date). PR #7828
is `OPEN`, `draft=true`, head `feat-ccla-signing-mechanism`. Every cited file path exists on
`origin/main`. The ADR corpus sweep for `contributor-license|cla-assistant|corporate-cla|cla-signatures|contributor-assistant`
over `knowledge-base/engineering/architecture/decisions/` returns **zero hits**, confirming TR8.

`knowledge-base/product/roadmap.md` still fails `markdownlint-cli2` with the same **5**
pre-existing errors, including the MD037 false positive at line 74 — so #7832 still blocks
roadmap row 4.13, and carrying it in the spec rather than this PR remains correct.

### Property List (Phase 0.6b)

- **P1.** A contributor employed by an organisation with a CCLA on file is recognisable as covered, without editing `.github/workflows/cla.yml`.
- **P2.** Signatory PII is on no world-readable surface, and out of `soleur-cla-evidence` while #7813/#7814/#7816 are open.
- **P3.** A corporate contributor's PR merges through the ordinary ICLA path — no second red check, no allowlist entry.
- **P4.** A merge is evaluable against the roster *as of that merge* (CCLA §5 is a temporal record).
- **P5.** A contributor cannot self-authorize by editing the roster in the same PR the roster authorizes.
- **P6.** Adding a corporate contributor never requires opening a config file.
- **P7.** Published surfaces describe a record that actually exists.
- **P8.** A malformed `cla.yml` allowlist edit cannot pass the test suite (the #7597 class).
- **P9.** A CCLA record is bound to the exact document version signed.

### Cut List (Phase 0.6b)

| Mechanism | Property claimed | What already buys it | Disposition |
|---|---|---|---|
| "Read the roster from the base ref" as new machinery | P5 | `cla-evidence.yml:51-54` already checks out `base.sha` for the whole job | **Cut as machinery.** Survives as a placement constraint, an inline comment, and one guard row |
| Explicit CODEOWNERS row for `apps/cla-evidence/roster/` | P5 | `* @deruelle` fallback covers it; and no branch protection or ruleset enforces CODEOWNERS review at all | **Kept, downgraded.** Legibility + future-proofing only. Must not be described as a control |
| A third required status check for roster verification | P1, P4 | The `cla-evidence` job already has base-ref checkout, Doppler→R2, zod, and the folded gate | **Cut.** Six-artifact lockstep plus the #6049 auto-fabrication ceiling |
| A CCLA record written to R2 | P9 | — | **Cut for now** (NG6/AC5). The roster's `git_sha`+`content_sha256` fields are the seam it plugs into later |
| Enrolling the CLAs in `BODY_EQUIVALENCE_DOCS` | corpus hygiene | — | **Cut.** Measured drift is non-zero; enrolment would red a required check |

### Value-Proposition Measurement (Phase 0.6c)

This plan's justification is **correctness and availability**, not a cost saving, so there
is no throughput number to quantify. The one measurable claim is the availability risk, and
it is evidenced rather than asserted: `build-bypass.ts:25-31` reads `.github/workflows/cla.yml`
with `readFileSync` and a single regex, `process.exit(1)` on no-match, inside the **required**
`cla-evidence` check — and `knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md`
records the resulting repo-wide outage and the admin bypass needed to escape it. Blast radius
of one malformed allowlist edit: every open PR in the repository.

### Institutional learnings that constrain this plan

- **Triple lockstep on `docs/legal/*.md`** — canonical edit + Eleventy mirror + `LEGAL_DOC_SHAS` re-pin, all in one commit. Verified live: `legal-doc-shas.ts` pins the *canonical* SHA (`corporate-cla` = `8384674e…`, matching the canonical, not the mirror). Neither the mirror nor the pin is a "touched file" when editing `docs/legal/`, so only the full suite catches drift. (`2026-05-29-legal-doc-triple-lockstep-…`)
- **Two independent mirror gates.** SHA pinning (`check-tc-document-sha.sh`) and heading/date parity (`legal-doc-consistency.test.ts`) are separate; passing one implies nothing about the other. A **new `###` heading** in canonical must appear verbatim in the mirror; prose inside an existing section need not. (`2026-06-15-two-legal-mirror-gates-…`)
- **Legal substance routes to the CLO, not the operator.** B1 is a legal-siting decision; it goes to `soleur:legal:clo` with drafted replacement wording requested back, not surfaced as a choice for a non-technical operator. (`workflow-patterns/2026-08-09-legal-decisions-route-to-clo-not-operator.md`)
- **Correction PRs reproduce their own defect.** Absence-grep ACs false-pass on obligations; verify each amended surface by **positive** grep naming the item. (`2026-08-01-the-correction-pr-reproduced-its-own-defect-…`)
- **CLA allowlist bot identity is a GraphQL surface**, not REST — do not harmonise by analogy with sibling workflows. (`2026-04-27-cla-allowlist-graphql-vs-rest-bot-identity-surface.md`)
- **`markdownlint --fix` mangles `#NNNN` at line start** into a phantom H1. Keep issue refs mid-line in every legal-corpus edit. (`best-practices/2026-04-19-markdownlint-fix-mangles-issue-ref-at-line-start.md`)

### Reusable precedent found

- **login → numeric id** is done in exactly one place: `plugins/soleur/skills/provision-github/scripts/provision-github.sh:100` (`gh api "/users/${X}" --jq .id`), with username validation at `:39`/`:44`. It is not factored into a shared helper; `soleur:ccla-add` is the second caller and therefore the reason to extract one.
- **Single-file PR from a script** has a working precedent at `apps/cla-evidence/scripts/sentinel-pr.sh` — deliberately narrow blast radius, idempotent label creation, and a `SENTINEL_DRY_RUN=1` stub. This is the delivery shape for `ccla-add`, not `model-launch-review`'s multi-file sweep.
- **`schema.ts` is the schema model**: `SCHEMA_VERSION = "1.0"`, `Sha256Hex` regex, `…Schema` suffix, `z.infer` types, and `validateEvidenceRecord()` throwing `SchemaVersionMismatchError` with **exit code 3**. The roster schema **folds into this file** rather than mirroring it from a sibling — copying a 64-hex regex and a parallel error class into `roster-schema.ts` would be duplication wearing a convention's clothes, and `Sha256Hex` needs only to be exported.
- **Register model**: `side-letter-register.md` carries `type: counterparty-ledger`, `custodian: clo`, `schema_version: 1`, `template:`, and a `## Schema` / `## Register` / `## Notes` structure.
- **Test collection**: `apps/web-platform/vitest.config.ts` `unit` project includes `test/**/*.test.ts`, so `apps/web-platform/test/cla-evidence/roster.test.ts` is collected automatically.

### External tooling — nothing to adopt

`cla-assistant` (SAP) closed the corporate-CLA request **wontfix** (#414) and is dormant
since Oct 2023. **EasyCLA** has a genuinely first-class corporate concept but is an
LF-hosted platform migration (LF SSO, DocuSign, Python+Go services).
**microsoft/ContributorLicenseAgreement** is the interesting one: its per-company
`approvedUsers.csv` is **independent convergence on the same design as the roster** —
evidence the shape is right, and simultaneously an argument against adopting it, since the
tool wrapping it was frozen in June 2024. Adopting any of them means replacing
`contributor-assistant`, whose semantics are encoded in four surfaces
(`build-bypass.ts`, `sentinel-pr.sh`, `fix-issue/SKILL.md`'s author-email pin,
`.claude/hooks/cla-signed-author-gate.sh`).

## Blocking Finding B1 — RULED (the "private" register is public)

**Measured.** `gh repo view` → `jikig-ai/soleur visibility=PUBLIC private=false`.
`git ls-tree -r origin/main -- knowledge-base/legal/` → **69 tracked files**.
`.gitignore:60` ignores `knowledge-base/private/`, and that directory **does not exist**.
`side-letter-register.md` — the very model KD7 cites — carries a *"Counterparty | Full legal
name"* column in the public repo; it has gone unnoticed only because the table is empty
(`| (none yet) | | |`).

**Consequence.** FR2, G2 and AC3 promise the signatory record is not world-readable. KD7
sites it in a tracked path in a public repo. Both cannot hold. Writing one signatory row
publishes a named individual's name, title and corporate email to the world, permanently and
irreversibly, in git history — at `brand_survival_threshold: single-user incident`, behind an
Art. 14 notice duty the corpus does not yet discharge.

**This is a legal-siting decision and routes to the CLO** (`hr-technical-fork-is-not-an-operator-question`;
`2026-08-09-legal-decisions-route-to-clo-not-operator`). The plan does not pick. Options,
measured, for the CLO to rule on:

| Option | Keeps git integrity (KD8) | Private by construction | New infrastructure | Note |
|---|---|---|---|---|
| **B1-a** `knowledge-base/private/ccla-register.md`, gitignored | **No** — untracked, unbacked, no content-addressing | No — depends on `.gitignore` discipline | None | This exact approach already failed twice here (Art. 30 register was planned private and is public today) |
| **B1-b** A separate **private** repository | Yes | Yes | A repo + access policy | Highest fidelity to KD7+KD13 as written |
| **B1-c** Reduce the public register to **non-personal fields only** — existence, org legal name, doc hash, `signatory_on_file: yes`, opaque `record_ref` — with identity held only in the executed instrument and the `legal@` mailbox | Yes, for what it holds | Yes — there is no PII to leak | None | Diverges from KD7's "enumerated fields" holding PII; requires PA-7 §(c) to say where identity actually rests |
| **B1-d** R2 evidence bucket | Yes | Yes | None | **Unavailable** — NG6/AC5, blocked on #7813 + #7814 + #7816 |

### CLO RULING — discharged 2026-09-04

**B1-c adopted, with two amendments. B1-a and B1-b refused.** B1-a is refused because privacy by
`.gitignore` discipline is not privacy by construction and destroys the content-addressed
integrity KD8 exists to buy. B1-b is refused *at n=1 organisation* — it buys a repo, an access
policy and a second drift surface to protect a field set that under B1-c need not be in version
control at all; **refusing to store data beats storing it privately.** Re-evaluation trigger: more
than ten organisations, or the first counterparty whose instrument must be jointly auditable.

- **Amendment B1-c-1 — custody is the encrypted operator drive, not "the `legal@` mailbox."** A
  mailbox is a transport, not custody: no retention discipline, no access record, and an Art. 15/17
  request against it is unanswerable. The controlling precedent is already in the corpus —
  `side-letter-register.md` §Notes: *"The executed PDF lives off-repo (encrypted operator drive).
  The repository carries only the template and this register."* **Must-verify before publication:**
  the corpus records a provider for `ops@soleur.ai` but says nothing about `legal@jikigai.com`.
  Establish and record it before any §0 sentence describes where the instrument is received — do
  not assume by analogy, which is the reasoning class #7624 exists to correct.
- **Amendment B1-c-2 — an organisation's legal name is not unconditionally non-personal.** True of
  a *société*; false of a sole trader or anyone trading under their own name, where the legal name
  **is** a natural person's name. The schema carries a rule, not an assumption: such a counterparty
  gets the opaque `Record ref` only, with the legal name held off-repo.

**The ruling's spine — contribution-triggered entry.** B1, B2 and the Art. 17 problem are one
problem seen from three articles: *the roster as specified entered people into an irreversible
public record on a third party's say-so, before they had done anything or been told anything.*
The rule: **a representative's id and employer association are committed only at or after that
representative has signed the ICLA on a PR here.** The employer's §4(c) designation list is held
off-repo and does not by itself write a row. Consequences: B2's balancing becomes comfortable
rather than strained; the never-contributed population — the only one with no Art. 17(3)(e) ground
— never enters git; Art. 14 collapses into Art. 13 for the whole published population, which D1
already discharges; and P4 survives via an `authorized_from` field, the legally operative date,
rather than a commit timestamp. Cost: a first PR may annotate `covered: false` until the roster
catches up — a latency on an annotation, not a gate, and CCLA §1 covers future contributions with
no cut-off. Guard 3 makes it a property of the artifact rather than an instruction.

**Art. 17 ruled.** A `removed_at` marker in a git-tracked file **is not erasure and must never be
described as one**. Art. 17(3)(b) is *not* available — no statute obliges a contributor roster; the
obligation is contractual and self-imposed. Art. 17(3)(e) **is** available, per record: yes for a
representative who contributed (the association proves the merged commit was covered); no for one
who never did — and contribution-triggered entry is what removes that second population entirely.
**Rename the concept**: `removed_at` is a *withdrawal-of-designation marker*, not a tombstone —
"tombstone" already means something erasure-shaped in this codebase (`tombstones/<sha>.deleted.json`
in the R2 path) and reusing it is how a false disclosure appears two documents downstream. **#7668
extends** to this population, scoped to one new question: is indefinite retention of the
association proportionate under Art. 5(1)(e) *on a surface from which it cannot be erased*?

**Corrected gate — the previous draft had it in both directions.** Writing identity columns into a
tracked file is not *gated*, it is **permanently prohibited** (§1 of the ruling removes it from the
schema), so nothing waits on it. But the roster row the previous draft called unblocked **is**
gated: committing the association before its Art. 6(1)(f) basis is recorded publishes personal data
with no documented basis — the #7813 defect class in a fresh location. The gate is exactly two
conditions, both cheap: **(1)** the balancing test is present in `gdpr-policy.md` §3.4 and PA-7's
Lawful basis row (a documentation edit, in this PR); **(2)** that representative has signed the
ICLA. Everything else in Tier 0 is confirmed unblocked, and Convergence is servable this week.

**Superseded recommendation (retained as the audit trail of how the ruling was reached):**

**Recommendation to the CLO: B1-c, strengthened with an executed-instrument hash.**

The objection to B1-c is that stripping identity from the register breaks the evidential
purpose. It does not, once the register is understood as an **index** and the executed
instrument as the **evidence**. The question the record must answer at relicensing is *"was
account N covered by org O's CCLA on date D, under document version H?"* — and none of that
requires the signatory's name. Authority to sign is proven by the executed instrument, not by
a markdown row.

So the roster row carries **two** hashes, not one: the CCLA template hash (already in FR1) and
the **SHA-256 of the executed instrument as received**. The instrument's bytes stay in the
`legal@` mailbox today and drop into R2 when NG6/AC5 unblocks. That gives the private copy
git-grade tamper-evidence without publishing anything about the data subject — which is
exactly the integrity property that made B1-a unattractive.

**Scope of the block — narrower than the spec implies.** B1 rules on one thing: *where the
identity bytes live*. Those bytes already live in the executed instrument and the `legal@`
mailbox, and they stay there under every option. So the only genuinely gated action is
**writing identity fields into a tracked file** — and no Tier 0 step needs to do that.
Concretely:

- **Not blocked:** the FR7 copy fix; replying to request a named signatory with title and an
  individually-attributable mailbox (KD9); Convergence's contributor signing the ICLA and the
  PR merging on its merits (KD2); countersigning; and **recording the roster row itself**,
  which under B2 carries the employer↔login association and no identity fields.
- **Blocked until the ruling:** creating `ccla-register.md` with populated identity columns.

This is a correction to the spec's Tier 0 framing, which read as though the whole tier waited
on a legal ruling. It does not. The first corporate contributor can be served this week.

## GDPR Gate (Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

The canonical regulated-path regex does **not** fire — no file in the work-list matches
`supabase/migrations/`, `lib/auth/`, `server/*auth*`, `app/api/`, or `*.sql`. The gate was
invoked under the Phase 2.7 expansion trigger **(b)**: `brand_survival_threshold:
single-user incident`. No `Critical` finding: name, title and corporate email are **not**
Art. 9 special-category data, so the escalation flow does not fire. (This also re-confirms
the brainstorm's Session Error 2, which correctly rejected the opposite claim.)

### `GDPR-Art-6` — B2: "the coverage map contains no personal data" is false

**Severity:** Important · **Article:** Art. 4(1), Art. 6(1) · **Location:** FR1, AC3, KD13

KD13 justifies publishing the coverage map on the ground that *"a corporate entity is not a
data subject and GitHub logins are already public."* The first clause holds. The second is a
category error: public availability does not remove data from Art. 4(1). And the map does not
merely republish logins — it asserts an **employment relationship** between an identifiable
natural person and a named employer. That association is personal data that neither component
carried alone, and it is precisely the information the map exists to convey.

**The executed instrument already says so, in terms.** `docs/legal/corporate-cla.md` §4(e)
has the employer acknowledge that a record of each Contribution is maintained *"including all
personal information associated with it, **such as GitHub usernames**."* So the binding document
this plan implements classifies GitHub usernames as personal information, while FR1 asserts a
map of those usernames contains none. The instrument settles it; FR1 is the side that must move.

This does not sink the design. The ICLA §1 disjunction already has contributors publicly
representing employer permission, so the association is arguably necessary and defensible
under Art. 6(1)(f). But it must be **analysed and disclosed**, not asserted away.

**Required changes:**

- **FR1** — replace "Contains no personal data" with: *"Contains no special-category data and
  no contact data. The employer↔login association is personal data, processed under a recorded
  Art. 6(1)(f) basis."*
- **AC3** — assert the **field set** positively (the permitted keys are present, the forbidden
  keys are absent). An AC phrased as "contains no personal data" tests a property the artifact
  does not have, and would pass while the premise is false.
- **PA-7 §(c)** — add the employer↔representative association to the categories, and note that
  it is disclosed on a public surface.
- **B1's option (c)** is unaffected — it concerns the *signatory* record. B2 concerns the
  *coverage map*, which stays public under every B1 option.

### `GDPR-Art-17` — B3: `removed_at` does not erase in git

**Severity:** Important · **Article:** Art. 17 · **Location:** FR3, Guard 1 row G1-M4

KD4 says a representative is never deleted, only tombstoned. In a git-tracked file the prior
commit retains the association permanently, so a tombstone cannot satisfy an Art. 17 request.
`apps/cla-evidence/scripts/gdpr-override.sh` provides a controlled erasure path for the R2
archive; **no equivalent exists for a tracked file**, and the plan does not name one.

**Required change:** either name the erasure path, or record the Art. 17(3)(b)/(e) ground on
which the association is retained despite a request. Extend **#7668** (indefinite-retention
proportionality, already with counsel for the ICLA field set) to the CCLA representative
population rather than deferring it — the brainstorm's Open Question 4 flags this, and B2
makes it sharper, because the retained field is now understood to be personal data.

### `GDPR-Art-5e`, `GDPR-Chapter-V` — no new finding

Indefinite retention and the outbound non-adequate-country leg are both already identified in
the plan and routed to counsel.

## User-Brand Impact

**If this lands broken, the user experiences:** a first-time external contributor whose
employer signed a Corporate CLA still sees a red `cla-check` with a bot comment pointing at
a corporate path that can never turn it green — the abandonment failure mode, which is
undetectable because an abandoned first PR is indistinguishable from lost interest. In the
worse direction, a malformed roster or allowlist edit fails the required `cla-evidence`
check and blocks **every open PR in the repository** (#7597 precedent).

**If this leaks, the user's data is exposed via:** the signatory's name, title and corporate
email committed to a `PUBLIC` git repository — permanently, irreversibly, and non-erasable
from history — under an Art. 14 notice duty the corpus does not currently discharge, for a
data subject in a third country with no EU adequacy decision. This is Blocking Finding B1,
and it is the reason Tier 0 is gated.

**Brand-survival threshold:** `single-user incident`.

CPO sign-off is required at plan time before `/work` begins; `user-impact-reviewer` runs at
review time.

## Domain Review

**Domains relevant:** Legal, Engineering, Product (carried forward from the brainstorm's
`## Domain Assessments`).

### Legal (CLO)

**Status:** reviewed (carry-forward) — **plus one new referral**
**Assessment:** Both instruments required; ICLA reaches the individual, the CCLA cures the
employer's rights on top. Convergence's PR is not blocked. A role mailbox cannot be the
signatory. The CCLA record goes to an enumerated-field register, not R2,
until #7813/#7814/#7816 close. Two published surfaces describe a record that does not exist. The
new obligation is the *outbound* Pakistan leg plus an unmet Art. 14 notice duty.
**New at plan time:** Blocking Finding B1 — the register's specified path is world-readable.
Referred to the CLO for a ruling, with drafted replacement wording requested back.

### Engineering (CTO)

**Status:** reviewed (carry-forward) — **two decisions strengthened by measurement**
**Assessment:** The executed instrument specifies the mechanism, so option (a) is decided by
the instrument. Sidecar required; fold into `cla-evidence`. No allowlist widening. Numeric-id
matching with `removed_at` tombstones, base-ref reads, CODEOWNERS-protected.
**Measured refinements:** KD5's lockstep is six artifacts and additionally trips the #6049
auto-fabrication ceiling — the decision is stronger than argued. KD12's CODEOWNERS clause
enforces nothing today (no branch protection exists) and must not be counted as the
self-authorization control; the base-ref read is.

### Product (CPO)

**Status:** reviewed (carry-forward)
**Assessment:** Build it, scoped hard. Split #3210 (mechanism P1/Phase 4; PII expansion stays
P3/Post-MVP). #3211 independent. Split the record into a public coverage map and a private
signatory record. Contributor-visible cost: zero.
**Tier:** Product/UX Gate = **NONE**. No path in the Files tables matches a UI-surface glob
(`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) or term, so the mechanical
override does not fire. No wireframes required.

**Brainstorm-recommended specialists:** none named beyond the CLO/CTO/CPO triad, all carried
forward above.
**Skipped specialists:** none.
**Pencil available:** N/A (no UI surface).

## Architecture Decision (ADR/C4)

### ADR

**ADR-201 (provisional) — "The Corporate CLA is recorded as a repo-tracked roster read at
the base ref, not as an allowlist entry and not as a third required check."** This is a new
architectural decision: it establishes a tenancy/ownership boundary (employer → authorized
contributor), a trust boundary (base-ref-only reads; a head-ref read is self-authorization),
and — stated explicitly, because an earlier draft of this plan wrote the **inverse** into the one
artifact that outlives it — a **fail-open** posture for the additive-evidence path, with the
fail-closed ICLA gate it sits beside left untouched. "Additive evidence must not gate" is the
reusable principle; it generalises past the CCLA and belongs in
`knowledge-base/engineering/architecture/principles-register.md` citing #7597 and ADR-201. `## Alternatives Considered` must record
allowlist widening, a PR-time corporate sign phrase, a hosted `soleur.ai` flow, a third
required check, and each external tool (cla-assistant / EasyCLA / microsoft CLA) with the
measured reason it was rejected.

**The ordinal is provisional.** Probed across **all 69 `origin/*` refs**, not just
`origin/main`: highest on `main` is ADR-198, highest across all refs is **ADR-200** — so a
`main`-scoped probe would have wrongly selected ADR-199. Re-derive immediately before merge
and after every sync; if it moves, sweep `grep -rn 'ADR-201' knowledge-base/project/{plans,specs}/feat-ccla-signing-mechanism/`
in the same edit so no AC is left asserting a nonexistent file.

### C4 views

All three model files were read in full — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`
— not grepped for the feature's own noun.

- **External human actors — corrected after actually reading `model.c4`.** An earlier draft of
  this plan asserted that the corporate representative was an unmodelled external actor. **That
  was wrong, and it was asserted without reading the file.** `model.c4:35` already carries
  `contributor = actor "Contributor / PR Author"` with `#external` and a full description — the
  Authorized Representative *is* that actor, because the Representative is by definition the
  person who opens the PR. No new actor is needed; at most a description amendment noting that a
  contributor may be covered by an employer CCLA.
  The Authorized **Signatory** should **not** be added: by this plan's own description they sign
  and never touch the platform, so they would be an actor with no edge to any container — a box
  in a diagram rather than a model element. Their existence is evidenced by the executed
  instrument and the roster row's `executed_instrument_sha256`.
- **External systems:** GitHub (signature ledger + Actions), Cloudflare R2 (`soleur-cla-evidence`).
  No new vendor — the roster is repo-tracked and the R2 write is deferred.
- **Containers / data stores:** the roster is a new tracked artifact inside the existing repo
  container, not a new store.
- **Access relationships:** a new edge from the employer organisation to the set of authorized
  logins. If B1 resolves to B1-b, a second repository appears in the Container view.

**Revised conclusion: the C4 impact is conditional, not automatic.** The representative is
already modelled (`model.c4:35`); the signatory should not be modelled. The one real C4 change
is **conditional on B1** — if the ruling is B1-b (a separate private repository), a second
repository appears in the Container view. If the ruling is B1-c, there is no C4 change beyond
an optional description amendment.

### Sequencing

The ADR is authored in this PR describing the target state, with `status: adopting` while the
R2 write remains blocked on #7813/#7814/#7816.

## Observability

Scoped to what actually ships. The `cla-evidence.yml` step is deferred, so the previous draft's
`liveness_signal`, four `failure_modes` and the fail-open essay are deferred with it — they
described a mechanism that is no longer in this PR. What remains is a script and two CI guards.

```yaml
liveness_signal:
  what: the roster + contribution-triggered-entry guards run in ci.yml's `test`
        required job on every PR, and report the number of ids cross-checked
  cadence: every PR
  alert_target: the `test` required check
  configured_in: apps/web-platform/test/cla-evidence/ (collected via vitest
                 `unit` project) + apps/web-platform/test/repo-wide-suites.ts
error_reporting:
  destination: non-zero exit failing the `test` check, with the offending id or
               key named in the message
  fail_loud: true. Note this is a CI-time schema guard on a data file, NOT a
             gate on the contributor's own PR — the `cla-evidence` required
             check is untouched by this PR, so nothing here can reproduce the
             #7597 repo-wide block.
failure_modes:
  - mode: roster JSON malformed or not the declared shape
    detection: .strict() zod parse throws at validateRosterRecord()
    alert_route: `test` check red on the PR that introduced it — caught at the
                 head, not only at the base, which is the gap a base-ref-only
                 read would have left open
  - mode: a roster id has no Individual CLA signature
    detection: Guard 3's cross-check against origin/cla-signatures
    alert_route: `test` check red; ccla-add.sh also refuses at write time
  - mode: ccla-add.sh writes a roster that fails its own validation
    detection: the script validates before opening the PR and exits non-zero
    alert_route: script exit code, surfaced to whoever ran it
logs:
  where: CI job output
  retention: the durable record is the roster in git — content-addressed and
             permanent, which is what makes the 90-day log question moot
discoverability_test:
  command: >
    jq -e '.schema_version == "1.0" and (.organizations | type == "array")'
    apps/cla-evidence/roster/ccla-roster.json
  expected_output: "true"
  # schema_version is the STRING "1.0", mirroring schema.ts:9. An integer 1
  # would contradict the precedent TR1 mandates.
  # Runs only once the roster file exists; until the first organisation is
  # recorded, its absence is the expected steady state and this probe is N/A.
```

## Guard Contract

The deliverable includes three guards. Each mutation matrix was derived from the **design**,
before the guard exists. **Guard 1 in the previous draft covered the `cla-evidence.yml`
roster-verification step; that step is deferred (see Overview), so its guard and AC4 are
deferred with it** — a guard for a mechanism that does not ship is the vacuity this gate exists
to prevent.

### Guard 1 — the allowlist regex parses the real `cla.yml`

**Property.** The `allowlist:` line in the actual `.github/workflows/cla.yml` is parseable by the
exact expression `build-bypass.ts` relies on at runtime — closing the #7597 gap, where a
format-breaking hand-edit passes unit tests and then reds a required check for the whole repo.

**Assembly.** The current shape makes this guard **unrunnable**, and the fix is a refactor, not an
export. `build-bypass.ts:24-32` fuses three things: a cwd-relative `readFileSync`, the regex, and
`process.exit(1)` on no-match. Three consequences, all verified: (a) importing anything from the
module runs its top-level `try { main(); }`, which calls `env("ACTOR_LOGIN")` and exits — the test
worker dies rather than failing an assertion; (b) every no-match mutation row lands on that same
`process.exit(1)`, so four of five rows could not be *observed* as RED; (c) the path is
cwd-relative and `scripts/test-all.sh` runs vitest from `apps/web-platform/`, so the read would
resolve to `apps/web-platform/.github/workflows/cla.yml` → ENOENT.

So: extract a **pure** `parseAllowlistLine(yml: string): string[] | null` into `allowlist.ts`
(already a pure module of exports, already imported by `build-bypass.ts`). The `readFileSync` and
the `process.exit` stay in the caller; the test resolves the repo root via `git rev-parse
--show-toplevel`, matching the `REPO_ROOT_HELPER` convention `repo-wide-containment.test.ts`
already recognises. The chokepoint stays singular — `build-bypass.ts` keeps calling the one
implementation — and the regex becomes retirable later, which the roster path must not block by
depending on it.

**Mutation matrix.** Derived from the design, before the guard exists.

| # | Mutation to the real `cla.yml` | Must |
|---|---|---|
| G1-M1 | Unquoted scalar: `allowlist: a,b` | **RED** |
| G1-M2 | Trailing inline comment: `allowlist: "a,b" # bots` | **RED** |
| G1-M3 | Wrapped line or block scalar (`>-` / `\|`) | **RED** |
| G1-M4 | Delete the `allowlist:` line entirely | **RED** — not a vacuous pass |
| G1-M5 | *(dispatch)* Point the test at a fixture instead of the tracked file | **RED** — the test asserts the path it read |

**Harness rows.**

- *Must-RED on suite mutation:* swap the real-file read for the existing `SAMPLE_CLA_YML_ALLOWLIST` constant → the anti-vacuity assertion reds.
- *Must-PASS, non-canonical:* single-quoted form, different internal whitespace, different login set → **PASS**.

### Guard 2 — the roster schema is closed, and `schema_version` is asserted at parse

**Property.** A roster that is not exactly the declared shape fails to parse, loudly, at one
chokepoint — and the permitted key set is closed **by construction**, not by a denylist that a
fifth key name walks through.

**Assembly.** `validateRosterRecord()` in `apps/web-platform/scripts/cla-evidence/schema.ts`.
**The schema folds into the existing `schema.ts` rather than a new `roster-schema.ts` file** — that
module already exports `Sha256Hex`, `SchemaVersionMismatchError` (exit code 3) and the
`validate…Record()` shape, and a second file re-declaring a 64-hex regex and a parallel error class
is duplication wearing a convention's clothes. The zod object is `.strict()`, so an undeclared key
throws at the same chokepoint. `schema_version` is the **string** `"1.0"`, mirroring
`schema.ts:9` — an earlier draft asserted an integer `1`, which would have contradicted the very
precedent TR1 mandates.

**Mutation matrix.** Derived from the design, before the guard exists.

| # | Mutation | Must |
|---|---|---|
| G2-M1 | Bump `schema_version` in the JSON without bumping the constant | **RED**, exit 3 |
| G2-M2 | Remove `schema_version` entirely | **RED** |
| G2-M3 | Add an **undeclared** top-level or per-row key (e.g. `signatory_email`) | **RED** via `.strict()` — this is why the key set is closed rather than denylisted |
| G2-M4 | Add a **second** organisation, valid except for a string `id` where an int is declared, after a valid first | **RED** — a check that stops at the first member is itself the defect |
| G2-M5 | *(dispatch)* Have the validator return the payload unvalidated | **RED** |

**Harness rows.**

- *Must-RED on suite mutation:* delete the fixture-count assertion so the suite could pass having validated nothing → reds.
- *Must-PASS, non-canonical:* a roster carrying an added field **that is declared optional in the schema** → **PASS**. Under `.strict()` this passes precisely because it is declared, which is the intended semantics and not a contradiction of G2-M3.

### Guard 3 — contribution-triggered entry is a property of the artifact

**Property.** Every account id in the tracked roster has a corresponding Individual CLA signature
in `origin/cla-signatures:signatures/cla.json`. This is the CLO ruling's load-bearing mitigation —
the Art. 6(1)(f) balancing, the Art. 14 discharge and the Art. 17(3)(e) ground all rest on it — so
it must be enforced by the artifact, not by an instruction in a script nobody re-reads.

**Assembly.** Two sites, deliberately: the **write** path (`ccla-add.sh` refuses to write an id
absent from the ICLA ledger, exiting non-zero with the reason) and the **CI** path (a test in the
`test` required job parses the **working-tree** roster and cross-checks every id). The CI half is
what makes it a property rather than a convention — without it, one hurried write bypasses the rule
permanently, on a surface from which nothing can be erased.

**Mutation matrix.** Derived from the design, before the guard exists.

| # | Mutation | Must |
|---|---|---|
| G3-M1 | Add a roster row whose id has no ICLA signature | **RED** |
| G3-M2 | Add a **second** such row after a valid first | **RED** — must not stop at the first member |
| G3-M3 | Point the cross-check at an empty/stub signature ledger | **RED** — a check whose reference set is empty passes everything |
| G3-M4 | *(dispatch)* Make the test report "0 ids checked" and exit 0 | **RED** |
| G3-M5 | Make `ccla-add.sh` skip the ledger check | **RED** — both sites are in the assembly |

**Harness rows.**

- *Must-RED on suite mutation:* replace the tracked-roster read with an inline fixture → the anti-vacuity assertion reds.
- *Must-PASS, non-canonical:* a roster with two organisations whose ids are all present in the ledger, one carrying a past `removed_at` → **PASS**.

## Encryption Posture

**Skipped — detection does not fire.** This plan introduces no persistent data store and no
new cross-component connection. No file in `## Files to Create` or `## Files to Edit` matches
`\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$` or `docker-compose.*\.ya?ml$`.
The roster is a git-tracked JSON artifact inside the existing repository; the R2 write that
*would* introduce a store is explicitly deferred (NG6/AC5). If Blocking Finding B1 resolves to
**B1-b** (a separate private repository), this gate must be re-run against that decision.

## Open Code-Review Overlap

One open `code-review` issue intersects this work's subject matter; none intersects its file list.

- **#7218** — *"`cla-signed-author-gate` only detects one hardcoded unsigned identity."*
  Touches `.claude/hooks/cla-signed-author-gate.sh`, which this plan does **not** edit.
  **Disposition: Acknowledge.** Different concern (a local pre-merge hook on commit
  *authorship*) from this plan's concern (CI-side corporate *coverage* recording), and folding
  it in would widen scope into a hook rewrite. Recorded because Guard 2's export of
  `readAllowlist()` gives #7218 a supported way to read the allowlist it currently cannot,
  which makes its fix cheaper afterwards — a coupling worth noting, not a reason to merge the work.

**Operational note for `/work`:** that same hook denies `gh pr ready` / `gh pr merge` when any
commit in `origin/main..HEAD` is authored `noreply@anthropic.com`. Agent-authored commits on
this branch will hit it; author identity must be set correctly from the first commit rather
than rewritten later.

## Files to Create

| Path | Purpose |
|---|---|
| `apps/cla-evidence/roster/ccla-roster.json` | FR1 public coverage map. Two hashes per row (CCLA template + executed instrument). Carries the employer↔account association — **personal data**, under the Art. 6(1)(f) basis recorded by this PR (B2) — and no name, title, email or address |
| `apps/web-platform/scripts/cla-evidence/cla-doc-path.ts` | **The discriminant module.** Named explicitly because the previous draft said "literal → discriminant" six times without ever saying where the discriminant lives — and its natural home sits inside AC7's own grep scope, so the one legitimate definition would have been counted as a violation |
| `apps/web-platform/test/cla-evidence/roster-schema.test.ts` | Guard 2 matrix |
| `apps/web-platform/test/cla-evidence/roster-entry-gate.test.ts` | Guard 3 matrix (contribution-triggered entry) |
| `apps/cla-evidence/scripts/ccla-add.sh` | The operator affordance — **a script, not a skill** (operator decision). Matches the `sentinel-pr.sh` / `gdpr-override.sh` / `inspect-evidence.sh` precedent for this exact surface. Resolves logins → numeric ids, refuses any id absent from the ICLA ledger (Guard 3), validates against the schema, opens a single-file PR. Supports `CCLA_ADD_DRY_RUN=1` |
| `apps/cla-evidence/scripts/ccla-add.test.sh` | Collected by `scripts/test-all.sh`'s `apps/cla-evidence/scripts/*.test.sh` glob — the same glob that already collects `sentinel-pr.test.sh` |
| `knowledge-base/legal/ccla-register.md` | TR2 register, using the CLO's drafted field table (§B1 ruling). Index, not evidence |
| `knowledge-base/legal/audits/2026-09-04-clo-ruling-ccla-register-siting-and-coverage-map-basis-3210.md` | The CLO ruling, with its external-counsel re-review triggers |
| `knowledge-base/engineering/architecture/decisions/ADR-201-*.md` | TR8 |

**Deferred with the `cla-evidence.yml` step** (operator decision): `roster-verify.ts`, its test,
Guard 1's roster matrix, and AC4. **Cut on measurement:** `roster-schema.ts` as a separate file
(folds into `schema.ts`); `allowlist-real-yaml.test.ts` as a separate file (folds into the existing
`allowlist.test.ts`); the login→id helper extraction (two callers, one line of `gh api`); the
`ccla-add` SKILL.md and its budget bump.

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/scripts/cla-evidence/allowlist.ts` | Guard 1: add the pure `parseAllowlistLine()`; the regex moves here from `build-bypass.ts`. **Not** an export from `build-bypass.ts` — that module's top-level `main()` makes it unimportable |
| `apps/web-platform/scripts/cla-evidence/build-bypass.ts` | Call the extracted parser; keep `readFileSync` + `process.exit` at the caller; add the base-ref-cwd invariant comment |
| `apps/web-platform/scripts/cla-evidence/schema.ts` | Add `RosterSchema` (`.strict()`) + `validateRosterRecord()`, reusing `Sha256Hex` and `SchemaVersionMismatchError` |
| `apps/web-platform/test/cla-evidence/allowlist.test.ts` | Guard 1's real-file cases land here |
| **`apps/web-platform/scripts/cla-backfill-evidence.ts:58`** | **The SIXTH producer — found by three reviewers independently, and in a directory the previous AC7 pathspec could not see.** `const pathArg = "docs/legal/individual-cla.md"` feeds `resolveDocSha()` for every backfilled record. The spec named 3 sites, the previous draft widened to 5, and the true count is 6 |
| `apps/web-platform/scripts/cla-evidence/build-record.ts` | `:98` → discriminant |
| `apps/web-platform/scripts/cla-evidence/backfill.ts` | `:55` → discriminant |
| `.github/workflows/cla-evidence.yml` | `:55`, `:128`, `:217` → discriminant. **No roster step in this PR** |
| `apps/web-platform/test/cla-evidence/schema.test.ts` · `hash.test.ts` | Fixture paths follow the discriminant (`hash.test.ts` also carries it at `:3`) |
| `apps/web-platform/test/repo-wide-suites.ts` | Declare the new repo-reading suites. `repo-wide-containment.test.ts` recomputes this manifest from disk and reds on drift; `test/cla-evidence/hash.test.ts` is already listed at `:35` for the same reason. Also fixes local relevance-gating, which would otherwise decline the `unit` project on a roster-only PR |
| `.github/workflows/cla.yml` | **FR7 comment copy only.** `allowlist:` value and format unchanged (TR7); `path-to-document` at `:45` unchanged — correctly the ICLA |
| `CONTRIBUTING.md` | FR7 |
| `.github/CODEOWNERS` | Add `apps/cla-evidence/roster/` — legibility only. `* @deruelle` already covers it, `/.github/workflows/` is already pinned, and no ruleset or branch protection enforces CODEOWNERS review at all |
| `docs/legal/corporate-cla.md` + mirror + `legal-doc-shas.ts` | FR8 §0/§5/§Signing, using the CLO's drafted replacements. §0's erasure promise must be corrected specifically, not just "§0" — it becomes false for a git-tracked record. **Triple lockstep, one commit** |
| `docs/legal/individual-cla.md` + mirror + pin | FR8 §1 (`:40`), §4(a) (`:60`), plus the Art. 13 notice sentence — **triple lockstep** |
| `docs/legal/privacy-policy.md` §4.5/§10 · `gdpr-policy.md` §3.4/§6 · `data-protection-disclosure.md` §2.3(d)/§6.4 (+ mirrors + pins) | FR9. §3.4 gains the **third** balancing test (the coverage map) drafted by the CLO; privacy-policy §4.5 carries the map as a **distinct** disclosure, not a clause inside the CLA-signature paragraph |
| `knowledge-base/legal/article-30-register.md` | PA-7 **§(c), §(d), §(e) and the Lawful basis row**. §(d) because the roster is a third recipient surface; the Lawful basis row because its existing limbs ("disclosed by the signer through the act of contributing", "informed at signing time") are both false for a representative — a different data subject from the signatory. The previous draft scoped this to §(c)/§(e) only |

## Implementation Phases

**Phase 0 — Preconditions.** Both are cheap and land in this PR. (a) Record the Art. 6(1)(f)
balancing test in `gdpr-policy.md` §3.4 and PA-7's Lawful basis row — per the CLO ruling this
is what gates the first roster row, and it is a documentation edit. (b) Re-derive the ADR ordinal
across all `origin/*` refs. The CLO ruling itself is **discharged**, so nothing waits on it.

**Phase 1 — Tier 0.** FR7 copy in `cla.yml` and `CONTRIBUTING.md`. Reply to Convergence requesting
a named signatory with title and an individually-attributable mailbox, plus the §5 notice-delivery
confirmation the ruling now requires. Their contributor signs the ICLA and the PR merges on its
merits. Countersign; hash the executed instrument; create `ccla-register.md` with the ruled schema
and an empty table. **The roster row itself lands after Phase 0(a)** — the previous draft called
it unblocked, which the CLO corrected: committing the association before its basis is recorded is
the #7813 defect class in a fresh location.

**Phase 2 — Contracts, before any consumer.** The discriminant module, `parseAllowlistLine()`, and
`RosterSchema`/`validateRosterRecord()`. **The discriminant moves here from the previous draft's
Phase 4** — a shared path constant read by three scripts, a workflow and two fixtures is exactly
the contract this phase ordering exists to protect. Guard matrices are written here, from the
design, before the guards exist.

**Phase 3 — The discriminant migration.** All **six** producer sites plus the test fixtures, in one
commit.

**Phase 4 — The operator affordance.** `ccla-add.sh` (add path **and** remove path — CCLA §5 makes
removal an email, and a remove path left unbuilt makes withdrawing an ex-employee's authorization a
hand-edit, which is P6 violated in the one direction that is security-relevant), its test, and the
runbook section. Guard 3's write-side half lands here.

**Phase 5 — Corpus corrections.** FR8, FR9, PA-7, each canonical edit paired with its mirror and
SHA re-pin in the same commit. Route the cross-document sweep through `legal-compliance-auditor`.
Verify by **positive** grep per item, never by absence.

**Phase 6 — ADR-201 + C4 + principle.** Ordinal re-derived. Any `.c4` edit is followed by
`scripts/regenerate-c4-model.sh` and a committed `model.likec4.json` in the same commit, or
`c4-model-freshness.test.sh` reds. Propose the principles-register row for "additive evidence must
not gate".

## Acceptance Criteria

Every AC below is a checkable post-condition on file state or command output. ACs that asserted a
process step, an external actor's ruling, or a proxy for the invariant were removed rather than
reworded — they are noted where removed so the deletion is auditable.

### Pre-merge (PR)

- **AC1.** `git show origin/main:.github/workflows/cla.yml | grep -E '^\s*allowlist:'` and the
  working-tree equivalent are **byte-identical**. Scoped to the `allowlist:` line, because FR7
  edits the same file's comment copy and a whole-file diff cannot carry this assertion.
- **AC2.** `scripts/ci-cla-required-ruleset-canonical-required-status-checks.json` still contains
  exactly `cla-check` and `cla-evidence`; `scripts/required-checks.txt` gains no entry.
- **AC3.** Roster field-set assertion, **executed against fixtures at plan time** (clean → `true`,
  exit 0; forbidden key at top level → exit 1; forbidden key nested in a representative → exit 1;
  missing `executed_instrument_sha256` → exit 1; integer `schema_version` → exit 1):

  ```bash
  jq -e '[.. | objects | keys[]] as $k
         | ($k | any(. as $x | ["email","signatory_name","title","address","corporate_email"] | index($x)))
         | not' apps/cla-evidence/roster/ccla-roster.json
  jq -e '.schema_version == "1.0" and (.organizations | type == "array")
         and ([.organizations[] | has("legal_name") and has("signed_at") and has("cla_doc")
               and has("executed_instrument_sha256") and has("representatives")
               and ([.representatives[] | has("id") and has("login") and has("removed_at")] | all)] | all)' \
    apps/cla-evidence/roster/ccla-roster.json
  ```

  The denylist half is belt-and-braces only: the **closed** key set is enforced by `.strict()` in
  `RosterSchema` (Guard 2 row G2-M3), which is what stops a fifth key name like `signatory_email`
  walking through a four-name list.
- **AC5.** Guard 1 rows G1-M1…G1-M5 each drive the suite RED, and both harness rows behave as
  specified. The parser under test is the extracted pure `parseAllowlistLine()`, reading the
  tracked `.github/workflows/cla.yml` resolved from `git rev-parse --show-toplevel`.
- **AC6.** Guard 2 rows G2-M1…G2-M5 each drive the suite RED, with `SchemaVersionMismatchError`
  and exit code 3 where specified.
- **AC6b.** Guard 3 rows G3-M1…G3-M5 each drive the suite RED — including G3-M5, the write-side
  half in `ccla-add.sh`.
- **AC7.** *(rescoped — the previous pathspec was blind to the sixth producer it was meant to
  catch.)* `git grep -n 'docs/legal/individual-cla\.md' -- apps/web-platform .github/workflows`
  returns **only** the discriminant module's own definition line and
  `apps/web-platform/test/legal-doc-consistency.test.ts` (which legitimately names both CLAs).
  Enumerated positively: all six producer sites resolve through `cla-doc-path.ts`. A count is
  printed alongside the scope searched, so a miss is attributable.
- **AC8.** `bash apps/web-platform/scripts/check-tc-document-sha.sh` exits 0 and
  `apps/web-platform/test/legal-doc-consistency.test.ts` passes.
- **AC9.** Positive-grep verification, one grep per item, printing the item id next to hit/miss,
  **any miss blocking**. Items: corporate-cla §0 (specifically the two-copies assertion **and** the
  erasure-procedure assertion, named separately), §5, §Signing; individual-cla §1, §4(a), Art. 13
  notice sentence; PA-7 §(c), §(d), §(e), Lawful basis; privacy-policy §4.5, §10; gdpr-policy §3.4
  (third balancing test), §6; data-protection-disclosure §2.3(d), §6.4; **and both FR7 surfaces** —
  `cla.yml`'s `custom-notsigned-prcomment` and `CONTRIBUTING.md`. FR7 was absent from the previous
  draft's AC9 despite being the only contributor-visible change in the PR.
- **AC10.** *(removed — the skill-description budget bump goes with the skill, which is cut in
  favour of a script.)*
- **AC11.** `bash scripts/test-all.sh` — the **full** battery, not touched-file shards.
- **AC12.** Every `ADR-<N>` occurrence in the plan, spec and `tasks.md` resolves to a file that
  exists in `knowledge-base/engineering/architecture/decisions/`; any miss blocks. The repo's
  existing `adr-ordinals` required check is the mechanism that catches a collision at CI.
- **AC13.** *(corrected — the previously named tests do not validate the model.
  `c4-render.test.ts` mocks `node:child_process` and tests a temp-dir lifecycle;
  `c4-code-syntax.test.ts` tests a CodeMirror tokenizer. Both pass whether or not `model.c4` is
  touched.)* If any `.c4` file is edited, `plugins/soleur/test/c4-model-freshness.test.sh` and
  `c4-count-parity.test.sh` pass, and `model.likec4.json` is regenerated in the same commit. If no
  `.c4` file is edited, this AC is satisfied by asserting that — the C4 change is conditional on
  the B1 outcome, and B1 ruled B1-c, which needs none.
- **AC14.** The `discoverability_test` command prints `true` once the roster file exists.
- **AC15.** *(moved to pre-merge and inverted from an absence-grep.)* The set of R2 write call
  sites is **unchanged from `origin/main`**: `apps/cla-evidence/scripts/` contains exactly
  `upload-evidence.sh` and `upload-bypass.sh` and no third uploader, verified by listing both the
  expected and the actual set.
- **AC18 (FR7).** Positive greps, each printing the item id next to hit/miss: `cla.yml`'s
  `custom-notsigned-prcomment` leads with the ICLA sign line **before** any Corporate-CLA sentence
  (assert the byte offset of the sign phrase is lower than that of `Corporate CLA`); it contains
  the maintainer-ownership sentence; it names a turnaround; and the same three hold in
  `CONTRIBUTING.md`.
- **AC19.** Where a CCLA is in flight, the PR carries a visible *"CCLA in progress — maintainer
  action, not yours"* state. Carried from the brainstorm's third minimum-fix item, which the spec
  dropped silently, and which is the state Convergence's contributor is in now.
- **AC20.** `CCLA_ADD_DRY_RUN=1 bash apps/cla-evidence/scripts/ccla-add.sh …` resolves logins to
  numeric ids, refuses an id absent from the ICLA ledger, emits a schema-valid roster, and opens no
  PR. This is the plan's counterpart to spec AC7, which previously had none.
- **AC21.** The roster and entry-gate suites are declared in
  `apps/web-platform/test/repo-wide-suites.ts` and `repo-wide-containment.test.ts` passes.

**Deferred with the `cla-evidence.yml` step:** AC4 (head-ref self-authorization) and AC17
(roster-step exit behaviour). Both assert properties of a mechanism that is not in this PR.

**Removed as not-an-AC:** the previous AC16 asserted the outcome of a CLO ruling — an external
actor's act that no line of the diff determines (`cq-ac-must-not-depend-on-concurrent-sessions`).
The ruling is a Phase 0 artifact, and the file it lands in is listed under `## Files to Create`.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **B1 unresolved and the register ships public** | Phase 0 is blocking; Tier 0's hand-record is gated. No register row is written before the ruling |
| A malformed roster reds the required check for every PR | The roster is machine-written by `ccla-add` and zod-validated before the PR opens; Guards 1+3 cover the parse paths. This is strictly safer than today's hand-edited YAML |
| Legal-corpus edit lands without its mirror or SHA re-pin | AC8 + AC11 run the full battery; the pin and mirror are not "touched files" when editing `docs/legal/`, which is exactly why the shard-scoped run is insufficient |
| ADR ordinal collides mid-pipeline | Probed across all 69 refs, not `origin/main`; re-derived before merge; renumber sweeps plan + spec + ACs in one edit |
| Roster verification becomes a de-facto merge gate | The step annotates and records; it must not fail a PR for *absence* of coverage — only for a malformed roster. Guard 1 rows encode the distinction |
| Skill description budget blocks the merge | Measured zero headroom; the bump is prescribed with its exact convention rather than discovered at CI |

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Widen `cla.yml`'s `allowlist:` | Writes a permanent, non-erasable "maintainer-class bypass" misstatement into a ten-year write-once archive for a contributor who holds a real grant (KD6) |
| A third required status check | Six-artifact lockstep plus the #6049 auto-fabrication ceiling for a content-scoped gate (KD5, measured) |
| PR-time corporate sign phrase, or a hosted `soleur.ai` flow | Each requires amending a signed legal instrument before it is legally coherent (KD11) |
| Fork or replace `contributor-assistant/github-action` | No org concept at the pinned SHA, confirmed from the action's inputs and from the ledger's flat schema; four surfaces encode its semantics |
| **Record the CCLA in the existing `soleur-cla-evidence` R2 write-once store** | **The central alternative, and it was missing from this table entirely.** The repo already operates a purpose-built CLA evidence bucket with a 10-year Object Lock, `inspect-evidence.sh` retrieval and `gdpr-override.sh` controlled erasure — so "why a git JSON file rather than the store built for exactly this?" is the first question a future reader asks. Rejected **for now, not on merits**: a CCLA arrives as an inbound email body, a third and worse Art. 9 ingress surface behind a one-way lock rule, and §4(c) capture is structurally non-signer. Blocked on #7813 + #7814 + #7816; the roster's `schema_version` and two hashes are the seam it plugs into |
| Adopt EasyCLA / cla-assistant / microsoft CLA | Respectively an LF platform migration, a wontfix + dormant project, and a frozen repo. Microsoft's `approvedUsers.csv` is independent convergence on this same design — evidence the shape is right, not a reason to adopt frozen tooling |
| Enrol both CLAs in `BODY_EQUIVALENCE_DOCS` now | Measured drift is non-zero on both; enrolling a drifted document reds a required check (the code's own enrolment rule) |

## Deferred / tracked elsewhere

- Roadmap row **4.13** — carried in the spec, blocked on **#7832** (5 pre-existing markdownlint errors, re-verified at plan time).
- **ICLA PII expansion** — split from #3210, stays P3/Post-MVP with its original re-evaluation criteria.
- **#3211** `soleur.ai/account/cla` — independent, P2/Post-MVP.
- **R2 CCLA writer** — blocked on #7813 + #7814 + #7816.
- Referred to counsel: Pakistani employment-law vesting, Art. 49 vs SCCs for the outbound leg, CCLA §3 moral rights, and #7668 extended to the CCLA population.
- **`side-letter-register.md` carries the same defect** — a *"Counterparty | Full legal name"*
  column in a public repo, unnoticed only because its table is empty. Same class as B1, but a
  different instrument with its own custodian decision, so it is **recorded and filed, not
  silently edited here**. File as a `domain/legal` issue referencing B1.
- **Vestigial** `scripts/generate-article-30-register.sh` renders an archived Feb-2026 template to a gitignored root path and is invoked by nothing — noted, out of scope.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6. It is filled above.
- `.claude/hooks/cla-signed-author-gate.sh` denies `gh pr ready`/`gh pr merge` for commits authored `noreply@anthropic.com`. Set author identity from the first commit; rewriting later costs a `filter-branch` + force-push (#7218's reproduction).
- Keep `#NNNN` issue refs mid-line in every legal-corpus edit — `markdownlint --fix` turns a line-initial `#7597` into a phantom H1 and does not undo it.
- `git show origin/main:<path>` is the only safe read from the bare root; this branch's work happens in `.worktrees/feat-ccla-signing-mechanism/`.
