---
title: "Corporate CLA signing mechanism"
date: 2026-09-04
type: brainstorm
lane: cross-domain
brand_survival_threshold: single-user incident
issues: [3210, 3211]
branch: feat-ccla-signing-mechanism
pr: 7828
---

# Corporate CLA (CCLA) signing mechanism

**Participants:** CLO, CTO, CPO (mandatory triad — `USER_BRAND_CRITICAL`), repo-research-analyst, learnings-researcher
**Trigger:** inbound email to `legal@jikigai.com`, 2026-09-04 — Convergence asks to sign the Corporate CLA
**Tracking:** #3210 (deferred CCLA mechanism + PII expansion) · #3211 (contributor signature lookup page)
**Predecessors:** `knowledge-base/project/brainstorms/2026-02-26-cla-contributor-agreements-brainstorm.md`, `knowledge-base/project/brainstorms/2026-05-04-cla-legal-rigor-brainstorm.md`

## What We're Building

An **email-countersigned, maintainer-held roster** that lets `cla-check` recognise a contributor as an Authorized Representative of an organisation with a Corporate CLA on file — plus the corpus corrections that the first real corporate signature makes urgent.

Explicitly **not** building: a PR-time corporate sign phrase, a `soleur.ai` CCLA web flow, an allowlist widening, or a third required status check.

## Why This Approach

### The executed instrument already specifies the mechanism

`docs/legal/corporate-cla.md` §4(c) — *"You have identified all Authorized Representatives … by providing a list of GitHub usernames to Us"* — and §5 — *"To add or remove Authorized Representatives, contact Us at `legal@jikigai.com`. Until We are notified of a change, the most recent list of Authorized Representatives on file shall apply"* — describe an email-countersigned, maintainer-held roster of GitHub usernames.

That is candidate (a) verbatim. Candidates (b) PR-time intake and (c) web flow would each require **amending a signed legal instrument** before they are legally coherent. This is decisive, not a tiebreak.

### Three pre-committed triggers have fired, and one did not need Convergence at all

1. #3210: *"Next contributor self-discloses corporate affiliation … triggers CCLA mechanism need immediately."* Convergence did precisely that.
2. #3210's **second** criterion: *"30 days from #3209 merge — schedule the joint CPO+CLO sync regardless."* #3209 closed **2026-05-16**, so this fired **2026-06-15**. As of today it is **81 days overdue**. The trigger question was already moot before the email arrived.
3. `knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md` lists among its re-evaluation triggers *"First arms-length (non-Jikigai) contributor"* and *"A recurrence while a third-party contributor has an unsigned CLA in flight."*

### We have already published that this mechanism exists

Independent of Convergence: the Art. 30 register declares a processing activity for which no processing machinery exists, and `docs/legal/corporate-cla.md` §5 makes a binding representation about *"the most recent list of Authorized Representatives **on file**"* — there is no file. Not building leaves two compliance artifacts describing a fiction. See "The disclosure defect" below.

### Allowlist widening is a permanent evidential defect, not merely untidy

Adding a corporate contributor to `.github/workflows/cla.yml`'s `allowlist:` causes `apps/web-platform/scripts/cla-evidence/build-bypass.ts` to write `allowlist/<login>/<yyyy-qN>.json` into the `soleur-cla-evidence` R2 bucket, **classifying a corporate contributor as maintainer-class bypass** — into a write-once store with a ten-year deletion floor. The record would be non-erasable through the ordinary write path and factually wrong. Hard no, independent of which mechanism wins.

### Hand-editing the allowlist has already caused a repo-wide outage

`readAllowlist()` in `build-bypass.ts` parses `cla.yml` with a **single regex**, not a YAML parser: `/^\s*allowlist:\s*["']([^"']+)["']\s*$/m`. A trailing inline comment, an unquoted scalar, a wrapped line or a block scalar all fail it — and the step deliberately does not swallow the error, because `cla-evidence` is a **required check**. One malformed hand-edit therefore blocks *every PR in the repo*.

This is not hypothetical: `knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md` records exactly that outage, which needed an admin bypass to escape — because `pull_request_target` runs the *base* copy of the workflow, so the fix PR could not pass the check it repaired. Compounding it, `allowlist.test.ts` tests the string-splitter, **not** the regex against the real file, so a format-breaking edit passes unit tests.

So "the operator hand-edits YAML" is not merely poor UX. It is a repo-wide availability risk with a precedent.

### Both instruments, always

The CCLA is additive, never substitutive (see Key Decision 1). This is what makes the design cheap: the contributor signs the ICLA through the existing automated path, `cla-check` greens normally, `cla-evidence` writes a normal record, and **`cla.yml` is never edited**. The CCLA layer becomes additive corporate evidence rather than a bypass.

## User-Brand Impact

- **Artifact at risk:** the Corporate CLA signing and evidence path — `docs/legal/corporate-cla.md`, the (absent) CCLA record, and the `soleur-cla-evidence` R2 archive.
- **Vector:** a corporate signatory's identifying data (name, title, corporate email) is captured into a write-once archive whose Art. 9 ingress is uncontrolled (#7814) and whose non-signer capture has no established Art. 6 basis (#7813), via an inbound free-text email body — the highest-entropy uncontrolled-ingress surface in the system, behind a one-way lock rule. Concurrently, two published documents promise a signature record that does not exist.
- **Brand-survival threshold:** `single-user incident`.

## Key Decisions

| # | Decision | Rationale | Source |
|---|---|---|---|
| 1 | **A CCLA-covered employee still signs the ICLA. Both instruments, no exception.** | CPI art. L.113-9 (employer owns employee software) is *French* law; Convergence's contracts are Pakistani, and whether the contribution fell within the employee's functions is unverifiable from here — if it did not, the employer holds nothing and grants nothing (*nemo dat*). Moral rights under CPI L.121-1 are inalienable and *ordre public*; an employer cannot undertake them for its employee. The ICLA is the only instrument that reaches the individual. Cost: zero — one already-automated comment. Apache does the same. | CLO D1 |
| 2 | **Do not block Convergence's `feat-opencode-harness` PR.** It proceeds on the ICLA; the CCLA runs in parallel and is not a merge gate. | The ICLA grant is not void — it is a grant plus a §4(a) representation, and `cla.yml` is a representation-capture mechanism, not a title search. We verify employment scope for nobody. Blocking Convergence would apply a standard we apply to no other contributor, triggered *solely because they disclosed* — punishing disclosure. CCLA §1 covers "present and future Contributions" with no temporal cut-off, so countersigning after merge covers the merged commit; the chain must be complete at relicensing (~4 years out), not at merge. | CLO D2 |
| 3 | **Mechanism = repo-tracked roster at `apps/cla-evidence/roster/ccla-roster.json`, read at the BASE ref.** Not `docs/legal/` (published + gate-watched), not the `cla-signatures` branch (a stale full fork of the repo tree). | `apps/cla-evidence/` is already the CLA machinery's home and already inside the sidecar's base-ref checkout. | CTO §2 |
| 4 | **Match on numeric GitHub `id`, display `login`. Never delete a representative — set `removed_at`.** | Logins are renameable and reusable; the DB id is not — a login-only roster is a takeover vector, a lesson `isAllowlistBypass(login, dbId, allowlist)` already encodes. CCLA §5 makes the roster a *temporal* record, so a merge must be evaluable against the roster as of that merge. | CTO §2 |
| 5 | **Fold roster verification into the existing `cla-evidence` job. Do NOT add a third required check.** | `cla-evidence.yml` already has the base-ref-only checkout, the Doppler→R2 path, zod, and the folded-gate poll. A third check costs a five-file lockstep (`ruleset-cla-required.tf`, the canonical JSON, `create-cla-required-ruleset.sh`, `required-checks.txt`, and a stale comment in `apply-github-infra.yml`) and would deadlock bot PRs if `required-checks.txt` is missed. Reaffirms 2026-05-04 Key Decision 9. | CTO §3 |
| 6 | **No allowlist widening for corporate contributors, ever.** | Writes a permanent, non-erasable "maintainer-class bypass" misstatement into a 10-year write-once archive. | CTO §1 |
| 7 | **CCLA legal record goes to `knowledge-base/legal/ccla-register.md` (enumerated fields, no free text) — NOT to the R2 evidence bucket yet.** Blocked on #7813 + #7814 + #7816. | A CCLA arrives as an inbound *email body* — a third and far worse Art. 9 ingress surface than today's `comment_body` and `override_reason`, behind a one-way lock rule. And §4(c) is structurally non-signer capture, multiplying #7813's data-subject population by the size of the employer's engineering team. The register gets its integrity property free from git being content-addressed. Models already exist: `side-letter-register.md`, `tenant-dpa-register.md` (`type: counterparty-ledger`, `custodian: clo`). | CLO D4 |
| 8 | **Record the doc hash at countersigning** — `git rev-parse HEAD` + `git show <sha>:docs/legal/corporate-cla.md \| sha256sum` — and record `roster_git_sha` + `roster_content_sha256` into the evidence record when the R2 path unblocks. | Reproduces the ICLA's doc-hash discipline at zero infrastructure cost; without the roster hashes the roster is mutable-by-later-commit from the archive's point of view. | CLO D4 + CTO §4 |
| 9 | **`support@convergence.pk` is not an acceptable signatory identifier.** Request a named signatory with title and an individually-attributable mailbox; retain `support@` only as the §5 change-notification channel. | §4(a) is a representation by a *natural person* with capacity; C. civ. art. 1367 requires a signature to identify its author. A role mailbox is also *worse* for GDPR, not better — it makes the record inaccurate under Art. 5(1)(d) and any Art. 15/17 request unanswerable. | CLO D3 |
| 10 | **Fix the two false disclosures in the same PR as the mechanism.** | See "The disclosure defect" below. | CLO D6 |
| 11 | **Do not fork or replace `contributor-assistant/github-action`.** | Verified at the pinned SHA: no org concept, no second signature phrase, no alternate allowlist source. (`remote-organization-name` is about *where signatures are stored*, not contributor organisations — a naming trap.) Migration cost is not the 2-signature ledger but the coupling: `build-bypass.ts`, `sentinel-pr.sh`, `fix-issue/SKILL.md`'s author-email pin, and `cla-signed-author-gate.sh` all encode this action's semantics. EasyCLA is LF-hosted; microsoft/ContributorLicenseAgreement is Azure-Functions-hosted. Both are infrastructure migrations, not action swaps, and both reopen 2026-05-04 Key Decision 2. | CTO §3 |
| 12 | **Roster reads must come from the base ref, and only the base ref.** Plus `apps/cla-evidence/roster/` in CODEOWNERS. | A PR author controls the head ref. A roster read from the head lets a contributor add themselves to the roster in the same PR the roster is meant to authorize. `build-bypass.ts`'s `readFileSync(".github/workflows/cla.yml")` is safe *only* because cwd is the base checkout — an invariant invisible at the call site and worth an explicit comment. | CTO §4 |
| 13 | **Split the CCLA record in two: a PUBLIC coverage map and a PRIVATE signatory record.** | The coverage map (employer legal name → authorized logins → signed-at → CCLA doc hash) contains **no personal data** *(SUPERSEDED 2026-09-04 — see the CLO ruling Section 3, #3210: the second clause is a category error; public availability does not remove data from Art. 4(1), and the map asserts an employment relationship neither component carried alone)* — a corporate entity is not a data subject and GitHub logins are already public — so the bot can read it at PR time to answer *"are you covered?"* without touching PII. The signatory record (name, title, corporate email, representation of authority) holds the PII and stays private. This is what lets the check answer honestly on a public PR while keeping PA-7's personal-data category off a world-readable branch, and it reconciles the CTO's machine-readable roster with the CLO's enumerated-field register. | CPO §5 |
| 14 | **Split #3210. (a) CCLA mechanism → P1, `Phase 4: Validate + Scale`. (b) ICLA PII expansion → new issue, stays P3 / Post-MVP** with its original re-evaluation criteria carried over verbatim. | The issue bundles two things with opposite urgency, which is how it got deferred twice. The corporate trigger says nothing about whether *individuals* should surrender legal names, and the May friction argument is untouched: Elvalio landed **9 merged PRs** (2026-07-16 → 2026-08-06) through the one-comment flow with still zero drop-off data. The CLO's own note stands — "PII expansion adds GDPR liability; defer." | CPO §3 |
| 15 | **#3211 (`soleur.ai/account/cla`) is independent. Stays P2 / Post-MVP.** Add a scope note and one re-evaluation criterion; no priority change. | A corporate signatory is **not a Soleur platform user** and has no account to log into — building the page for them is a *bigger* job now, not smaller. Their trust need is met by two artifacts the CCLA work produces anyway: the countersigned agreement in their own filing cabinet (what corporate counsel actually asks for) and the public coverage map. The CCLA work *reduces* pressure on #3211. One real coupling, recorded as a constraint on #3210 only: design the record schema so a future page can render both record types. | CPO §3 |
| 16 | **Add roadmap row 4.13** for the external-contributor funnel. | The roadmap has **zero rows** for it, so every trigger event restarts this argument from zero — which is exactly what happened. Precedent is row 4.12 ("Before tester #2 is onboarded — the determination is a *precondition* of the next onboarding, not a reaction to it"), which already ruled at n=1 that a legal-posture determination precedes the next onboarding. Required by `wg-every-feature-listed-in-a-roadmap-phase`. | CPO §3 |

## The disclosure defect (found, not sought)

Two published surfaces describe a Corporate CLA record that **has never existed**:

1. `docs/legal/corporate-cla.md` §0 tells signatories *"Two copies are made"* — the public `cla-signatures` branch and the Cloudflare R2 archive, "which includes the authorised signatory's name and corporate email address." No mechanism writes a CCLA record anywhere. Verified: `signatures/cla.json` holds two *individual* signers (`deruelle` PR #328, `Elvalio` PR #3186) and nothing else.
2. `knowledge-base/legal/article-30-register.md` PA-7 §(c) declares: *"For Corporate CLA: signatory name + corporate email + corporate identity."* Also never captured.

Both passed every legal-doc gate, because the gates check canonical↔mirror agreement and SHA pinning, not correspondence to code. This is the #7349 defect class. Because Key Decision 7 defers the R2 write, the fix is to **amend the prose to describe the register**, not to build the write to match the prose.

**The evidence path is hardcoded to the Individual CLA.** `apps/web-platform/scripts/cla-evidence/build-record.ts` sets `path: "docs/legal/individual-cla.md"` as a literal, and `.github/workflows/cla-evidence.yml` hardcodes the same path three more times (the `fetch-depth` comment, the `git show "${base_sha}:docs/legal/individual-cla.md"` hash computation, and the receipt-comment body). Grepping the entire evidence path for `corporate-cla` returns **nothing** — `docs/legal/corporate-cla.md` is never hashed by anything. That literal must become a discriminant before a CCLA record can carry a doc hash at all.

Additionally, `docs/legal/individual-cla.md` §1 and §4(a) carry the Apache tri-branch disjunction — "…received permission…, …employer has waived such rights…, **or** …employer has signed a Corporate CLA" — which is correct as a representation about employer permission and **wrong if read as a signature waiver**. Key Decision 1 requires one clarifying sentence in each.

## Chapter V — the obligation that is actually new

- Receiving the signatory's data *from* Pakistan is **not** a Chapter V transfer (Chapter V governs export from the EEA). Inbound is out of scope.
- The US legs (GitHub, Cloudflare) are unchanged — they turn on importer identity, not on the data subject's location.
- **The new obligation is outbound.** Under §5 we correspond with Convergence about the Authorized Representative list. Sending a named individual's data from Jikigai (France) to a controller established in **Pakistan — no EU adequacy decision** — is a Chapter V transfer to a non-adequate third country. Every transfer entry in the published corpus is US, UK, DE or intra-EU, and those sections read as exhaustive enumerations. After countersignature that is false.
- **Art. 14 finding (not flagged anywhere before):** CCLA §4(c) has the employer hand us GitHub usernames of its people. That data reaches us *from the employer, not the data subjects* → Art. 14 applies, and Art. 14(1)(f) specifically requires telling them about the third-country transfer and the absence of adequacy. Nothing in the corpus gives an Art. 14 notice to a listed representative. **Key Decision 1 is also the Art. 14 remedy** — requiring the ICLA means every representative who actually contributes receives the Art. 13 notice at signing time.

Sections requiring amendment: `privacy-policy.md` §4.5 + §10, `gdpr-policy.md` §3.4 + §6, `data-protection-disclosure.md` §2.3(d) + §6.4, `article-30-register.md` PA-7 §(c) + §(e).

## Open Questions

1. **Does Pakistani law vest software economic rights in the employer**, and did this contribution fall within the employee's functions? The entire value of the CCLA rests on this. Needs Pakistani-qualified input via French counsel. Low urgency (BSL change date ~4 years), high consequence.
2. **Art. 49 derogation vs. SCCs for the outbound Pakistan leg.** Art. 49(1)(b)/(1)(e) look available for occasional correspondence, but Art. 49 is for *occasional, non-repetitive* transfers and §5's list-maintenance duty is recurring by construction. If corporate contributors become a pattern, Art. 46(2)(c) SCCs Module 1 (C2C) become necessary. A counsel call about the *programme*, not about Convergence.
3. **CCLA §3's moral-rights undertaking.** The employer undertakes, for its representatives, that they will not assert moral rights; under CPI L.121-1 that right is inalienable. Reading is that the clause is inoperative rather than tainting — but whether it taints the surrounding grant is a French IP question, and the clause is already published.
4. **#7668 (indefinite-retention proportionality) must be extended to the CCLA population.** Already with counsel for the ICLA field set; the CCLA set is materially more identifying and the answer may differ.
5. **Enrol both CLAs into `BODY_EQUIVALENCE_DOCS`?** Current canonical↔mirror delta on both is front-matter and hero-section only — no body drift. Enrolling a drifted document reds the check on arrival, so now is the cheap moment. (`corporate-cla` is in `LEGAL_DOC_SHAS` but not `BODY_EQUIVALENCE_DOCS`.)
6. **#7670** — the importer-identity vs byte-location divergence between PA-7 §(e) and PA-1 §(e) — is upstream of any CCLA transfer reasoning and remains open.

## Session Errors

1. **learnings-researcher asserted the R2 bucket's `weur` location means "no outbound transfer".** Directly contradicted by PA-7 §(e), which states `location = "WEUR"` is *"a placement hint, not a jurisdiction"* and that the bucket sits on Cloudflare's non-EU-tier `default` jurisdiction. This is the exact error #7624 was raised to correct; the agent reversed a landed correction. Not propagated.
2. **learnings-researcher asserted signatory name + title + corporate email are Art. 9 special-category data.** Art. 9's categories are closed and a job title is not among them. The CLO independently assessed every field under Art. 6(1)(f). Not propagated.
3. **repo-research-analyst presented a reconstructed quote as verbatim PA-7 §(c) text** ("authorised signatory name and corporate email address"); the actual text is "signatory name + corporate email + corporate identity". Substance held, wording did not — caught by grepping the quoted string and getting zero hits.
4. **repo-research-analyst gave two different paths for the allowlist parser.** Real path: `apps/web-platform/scripts/cla-evidence/build-bypass.ts`. There is no `cla-backfill-evidence/build-bypass.ts`.
5. **`knowledge-base/product/roadmap.md` fails `markdown-lint` on `main`**, so the CPO's recommended row 4.13 could not be committed — the hook lints staged files, so any commit touching the roadmap is blocked. Confirmed pre-existing against `git show main:…`. Filed as **#7832**; the row is carried in the spec's Sequencing section so it is not lost. A trap recorded there: `markdownlint-cli2 --fix` clears the errors but **deletes a real space** on line 74, rendering `All-in burn**$643.24/mo**` — the MD037 it "fixes" is a false positive on balanced markers.

## Capability Gaps

- **`soleur:ccla-add` skill — missing.** Without it, "add a corporate contributor" is a hand-edit of a JSON file by someone who knows where it lives, which only moves the non-technical-operator problem from YAML to JSON. Should prompt for org + legal name + representative logins, resolve logins → numeric ids via `gh api`, validate against a zod schema, and open the PR. *This skill, not the roster file, is what satisfies the operator constraint.* Evidence: `git ls-files | grep -iE 'roster|ccla'` returns only unrelated ADR-118 / session-context files — no CCLA tooling exists.
- **`ccla/` R2 evidence writer — missing.** `apps/cla-evidence/scripts/upload-evidence.sh` and `upload-bypass.sh` are keyed to the ICLA-record and bypass shapes; neither accepts an executed-document artifact. Verified by listing `apps/cla-evidence/scripts/upload-*.sh` — only those two exist. Deferred with Key Decision 7 regardless.
- **No ADR governs the CLA mechanism.** Swept `knowledge-base/engineering/architecture/decisions/` for contributor-license / cla-assistant / cla-signatures / corporate-cla — zero hits. This design is architecturally load-bearing and needs one.
- **The legal domain has no operator-facing write-path skill at all.** Only `legal-audit` and `legal-generate` exist, and both are read/generate; the CLO agent enumerates the CCLA as a document to *audit*, never to record. The single runbook, `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md`, is retrieval- and erasure-only with no write path and no CCLA section. Every other domain has one — `flag-create`, `user-set-role`, `admin-ip-refresh` all exist precisely to keep the operator out of config files. Legal is the exception, and this is where it bites.
- **No test covers the allowlist regex against the real `cla.yml`.** `allowlist.test.ts` exercises the string-splitter only, so the format-breaking edit class that caused the #7597 repo-wide outage passes unit tests. Whatever ships should close this.

## Domain Assessments

**Assessed:** Legal, Engineering, Product. Not assessed: Marketing, Operations, Sales, Finance, Support — no relevant signal in the feature description.

### Legal (CLO)

**Summary:** Both instruments required (ICLA reaches the individual; the CCLA cures the employer's rights on top) — French L.113-9 does not travel to Pakistani employment contracts, and L.121-1 moral rights are inalienable. Convergence's PR is not blocked: the CCLA cures retroactively and blocking would punish disclosure. A role mailbox cannot be the signatory. The CCLA record must go to an enumerated-field register, not to the R2 archive, until #7813/#7814/#7816 close — an inbound email body into a one-way-locked store is the widening those issues exist to prevent. Two published surfaces already describe a CCLA record that does not exist. The genuinely new obligation is the *outbound* Pakistan leg plus an unmet Art. 14 notice duty to listed representatives.

### Engineering (CTO)

**Summary:** The executed CCLA already specifies the mechanism (§4(c)/§5 = maintainer-held roster of GitHub usernames), so option (a) is decided by the instrument, not chosen on merit. `contributor-assistant/github-action` has no org concept at the pinned SHA — verified against its full input set — so a sidecar is required; fold it into the existing `cla-evidence` job rather than adding a third required check. Allowlist widening would write a permanent maintainer-class-bypass misstatement into a 10-year write-once archive. Roster keys on numeric GitHub id with `removed_at` tombstones, read strictly from the base ref (head-ref read = self-authorization), CODEOWNERS-protected. Convergence is unblockable today with zero code.

### Product (CPO)

**Summary:** Build it, scoped hard — three pre-committed triggers have fired and one (the 30-day sync, 81 days overdue) never needed Convergence. The cost of doing nothing is not linear: by the fifth corporate contributor the allowlist has become an undocumented shadow-registry of corporate affiliation and relicensing becomes unanswerable, because `allowlist/<login>/<quarter>.json` records the *absence* of a signature — no `cla_doc`, no doc hash, no `signed_at` — writing a false negative into the chain for exactly the contributors with the strongest paper. Split #3210 (mechanism P1/Phase 4; PII expansion stays P3/Post-MVP); #3211 is independent and the CCLA work reduces pressure on it. Split the record into a public no-PII coverage map and a private signatory record. Contributor-visible cost: **zero** — the employee comments one line like everyone else. Refused: making the employee relay their employer's legal details, a second signing artifact, a gating web flow, or any second red check.

## Contributor and operator experience

Today's dead-end, verbatim from `cla.yml` `custom-notsigned-prcomment` and mirrored in `CONTRIBUTING.md`:

> If your employer owns your work, please ask them to sign the [Corporate CLA] by contacting `legal@jikigai.com`.

**The instruction and the gate disagree.** That sentence points at the corporate path; `cla-check` only ever greens on the individual one. There is no state of the world in which following it turns the check green. The failure mode is not confusion but **abandonment** — and it is undetectable, because an abandoned first PR is indistinguishable from lost interest.

Minimum honest fix, three copy changes and zero mechanism:

1. **Invert the order.** Lead with "comment this line and your check goes green." Then, separately: "If your employer owns your work we also need a Corporate CLA from them — **that's ours to chase, not yours.**"
2. **Name an owner and a turnaround.** Replace the bare mailto with a stated SLA. The number is the operator's to set; the requirement is that *some* number appears.
3. **Never leave the check red with no owner.** If a CCLA is in flight, the PR carries a visible "CCLA in progress — maintainer action, not yours" state.

## Strategic flag — the contribution itself (not a CLA question)

Convergence's contribution adds **opencode as a third harness**. `plugins/soleur/lib/harness.ts` declares `export type Harness = "claude" | "grok" | "unknown"`, and `knowledge-base/project/specs/external/opencode.md` already exists, so there is a clean seam. But `competitive-intelligence.md` records an explicit position against breadth-for-its-own-sake ("Do NOT adopt: 14-provider runtime… dilutes Claude-native depth"). Accepting a third harness from an external contributor sets a multi-harness maintenance expectation that should be decided deliberately, **not by merging a PR**.

The union widening also triggers `hr-type-widening-cross-consumer-grep` and `cq-union-widening-grep-three-patterns` — real review burden to warn a first-time external contributor about up front.

This does not block the CCLA work and must not be conflated with it.

## Productize Candidate

`soleur:ccla-add` — corporate-contributor onboarding recurs once per signing organisation and is exactly the "operator must not hand-edit config" class. See Capability Gaps.
