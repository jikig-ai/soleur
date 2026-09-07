---
title: "CLO attestation — the off-host-log denial, the PA-8 §(f) retention bound, and the #7787 trigger (#7786 / #6474 / PR #7881)"
type: clo-attestation
date: 2026-09-07
issue: 7786
also_addresses: [6474, 7851, 7787]
pr: 7881
attestation-authority: clo
status: SIGNED-OFF (CLO-agent-attested and re-issued, Soleur-as-tenant-zero v1)
disposition: "RE-ISSUED SIGNED-OFF 2026-09-07. The disposition as first issued was BLOCKED on B1 + B2 with R1, R2 and R3 required before merge; B1, B2 and R2 are cleared on the working tree, verified in lockstep across both surfaces. R1 (mirror-drift ratchet), R3 (this file's own register waiver) and R4 (the SHA re-pin, which the B1/B2 edits made stale) remain required before merge and are engineering steps, not legal ones. Superseded, not deleted — see §Discharge on re-issue."
signed_off_at: 2026-09-07
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
blocking_findings: []
blocking_findings_cleared: [B1, B2]
required_before_merge: [R1, R3, R4]
required_before_merge_cleared: [R2]
tier_classification: "Tier 1 — a material factual correction to three PUBLISHED notice documents plus their three Eleventy mirrors. Three previously-published statements are retracted as statements about the platform as it runs today (the off-host-shipping denial in five phrasings, the 30 MB json-file retention bound, and the `under processor-DPA terms` ground for the no-notification conclusion), and one recipient relationship is disclosed for the first time (the user-serving application container's WARN-and-above pino stream, shipping since 2026-06-02). All five CI gates over `docs/legal/**` ARE engaged. Recorded per `knowledge-base/legal/tc-version-bump-policy.md` §Non-T&C legal docs step 4, for Art. 30 register and counsel-review-ledger purposes."
semver: "No `TC_VERSION` bump, and `docs/legal/terms-and-conditions.md` is untouched. The eight non-T&C notice documents carry no version constant and no acceptance ledger; the SHA-refresh contract is what applies. It was honoured at `1959995d8` (gate verified green there); the B1/B2 re-issue edits made the pin stale again, which is R4 — the pin must be refreshed once more before merge."
brand_survival_threshold: single-user incident
written_against: "the diff as landed on `feat-one-shot-7874-7786-6474-7787-runbook-ssh-legal-registers` at `1959995d8`, re-derived from `git log -p origin/main..HEAD`, and re-read against the working tree at re-issue. Every implementation-detail claim in the corrected prose was checked against the migration/IaC/test body rather than against the PR description — see §How this was verified. Four of the five gates were run locally; their results are recorded, including the two that are red."
fired_re_evaluation_triggers: []
declined_re_evaluation_triggers:
  - "`Promotion of scripts/lint-legal-registers.sh from advisory to blocking (#7787) — the gate's scope changes what the register's completeness claim is worth.` (from `knowledge-base/legal/audits/2026-09-counsel-review-7717.md`). Put to this review as FIRED. Ruled NOT FIRED on the diff: `scripts/lint-legal-registers.sh` is not in this PR's changed-file set, `scripts/test-all.sh` still reads `run_suite \"scripts/lint-legal-registers-live\" bash scripts/lint-legal-registers.sh --advisory`, the block above that line still reads `ADVISORY FOR ONE MERGE CYCLE (#7717)`, and #7787 is OPEN. The trigger stays ARMED. See §The #7787 trigger."
re_evaluation_triggers:
  - "Promotion of `scripts/lint-legal-registers.sh` from advisory to blocking (#7787). Carried forward from the #7717 counsel review UNDISCHARGED — this PR did not perform it. Whichever PR deletes the `--advisory` flag fires it, and both this attestation and the #7717 review must be re-read then."
  - "Execution of a Better Stack Art. 28(3) instrument, or the recording on #7529 of the specific published vendor terms relied on as the `other legal act`. The Art. 33/34 no-notification conclusion attested here is grounded on three limbs that deliberately exclude a processor DPA; if one is executed, limb (1) and the §2.3(m) ground paragraph both change."
  - "A written vendor statement of the physical processing location and of EEA-only support access for `data_region eu-central-1a` (#7825). That upgrades limb (2) from establishment-plus-contract inference to evidence."
  - "Any change to the Vector `app_container_journald` source's severity filter (`level_int >= 40`), or to where the `userIdHash` is computed for that stream. Limb (3) — pseudonymisation in the application before egress — rests on a measurement, not on a config invariant, and a filter widening changes the data categories every one of these six documents describes."
  - "First arms-length (non-Jikigai-affiliate) data subject whose logs traverse the application-container stream. The Soleur-as-tenant-zero posture that grounds v1 internal attestation ends there, and external counsel re-reads §2.3(m), §5.14 and §3.7 in full."
  - "Any data subject or processing activity outside the EEA/UK, or in a regulated industry (healthcare, finance)."
---

> **DRAFT — This document was generated by AI and requires professional legal review before use. It does not constitute legal advice.**

# CLO attestation — #7786 / #6474 / PR #7881

This audit is the load-bearing evidence for the ship Phase 5.5 **Counsel-Review CLO-Attestation
Gate** on PR #7881. It is performed by the `clo` agent under the Soleur-as-tenant-zero v1 posture:
this is the **internal** sign-off, the operator retains an optional veto, and **external** counsel
re-review is reserved for the `re_evaluation_triggers` above. It is not legal advice, and the
operator — a non-lawyer founder — is not the sign-off authority for it.

**Overall disposition: BLOCKED.**

> **RE-ISSUED SIGNED-OFF 2026-09-07 — read the line above, and the B1 / B2 sections below, as of
> first issue.** The frontmatter now reads `SIGNED-OFF`. The `Overall disposition: BLOCKED` line
> immediately above and the two blocking-finding sections describe the disposition **as issued
> against commit `1959995d8`**, and are left standing as that record. They are not live status.
> B1, B2 and R2 are cleared on the working tree and re-verified; R1, R3 and R4 remain required
> before merge. The discharge is at §Discharge on re-issue.
>
> Recorded here rather than repaired in place, because a frontmatter-only re-issue is how the
> #7717 counsel review ended up as one document holding two answers to "was this signed?" — the
> half-applied-replacement defect class (#7349) that this corpus keeps re-learning. The findings
> below are signed text; they are annotated, not overwritten.

The correction is right, and it is the most honest thing this corpus has published about its own
telemetry. The five denial phrasings were false, the 30 MB bound was misattributed rather than
merely stale, and re-grounding the no-notification conclusion on three limbs instead of a DPA that
does not exist is the correct move — it makes the Art. 28(3) gap **more** visible, not less, which
is what a register is for.

It is blocked on one thing, in two places. **This PR widened the SCOPE sentence of Privacy Policy
§5.14 and of GDPR Policy §3.7 to bring the user-serving application container's stream into those
sections, and did not widen the bullets underneath.** Three of those bullets now make statements
about the newly-in-scope stream that the same PR proves false in the Data Protection Disclosure.
One of them is an Art. 32 / Recital 26 safeguard claim, on the published surface a data subject
reads. That is the identical defect class the PR is correcting — a document asserting one thing in
one clause and its contradiction in another — reproduced at a smaller scale in the act of fixing it.

Both fixes are prose edits to text this PR already touches. Nothing here needs a new measurement,
a new instrument, or an operator decision.

## Per-artifact verdicts

| # | Artifact | Verdict |
|---|---|---|
| A1 | `docs/legal/data-protection-disclosure.md` §2.3(m) | **DISCHARGED**, with two corrections recorded (C1, C2) and R2 attaching |
| A2 | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` §2.3(m) | **DISCHARGED.** Mirror carries the edit byte-for-byte; verified |
| A3 | `docs/legal/privacy-policy.md` — §5.10, §5.14, §Retention | **BLOCKED (B1).** §5.10 and the §Retention bullet are DISCHARGED; §5.14's `Data processed` and `Pseudonymisation` bullets are not |
| A4 | `plugins/soleur/docs/pages/legal/privacy-policy.md` | **BLOCKED, coupled to A3.** Mirror parity is correct; it mirrors the defect |
| A5 | `docs/legal/gdpr-policy.md` — §3.7, §4.2 table, §Retention | **BLOCKED (B2).** The §4.2 row and the §Retention paragraph are DISCHARGED; §3.7's balancing-test tail is not |
| A6 | `plugins/soleur/docs/pages/legal/gdpr-policy.md` | **BLOCKED, coupled to A5** |
| A7 | `knowledge-base/legal/article-30-register.md` — PA-8 §(b)(vi), §(f), trigger list | **DISCHARGED.** Every implementation claim verified against the IaC and the test body |
| A8 | `knowledge-base/legal/compliance-posture.md` — the Art. 5(2) control-defect entry | **DISCHARGED** |
| A9 | `knowledge-base/legal/data-processing-agreement-template.md` — Schedule 2, TOM 12, TOM 15, the §4.2-gap note | **DISCHARGED** |
| A10 | `apps/web-platform/lib/legal/legal-doc-shas.ts` | **DISCHARGED.** `check-tc-document-sha.sh` exits 0 against the working tree |
| A11 | `scripts/probe_legal_corpus_truth.py` + its `scripts/test-all.sh` registration | **APPROVED**, with two corrections recorded (C3, C4) |
| A12 | `knowledge-base/engineering/operations/runbooks/recover-userid-from-pino-stdout.md` §Re-verification triggers | **DISCHARGED.** 7/7 parity with PA-8 §(f) verified item by item |
| A13 | The #7787 promotion of `scripts/lint-legal-registers.sh` | **NOT PRESENT IN THIS PR.** The #7717 re-evaluation trigger does **not** fire. See §The #7787 trigger |

> **At re-issue:** A3, A4, A5 and A6 are **DISCHARGED**. The table above records the verdicts as
> issued against `1959995d8`. A13 is unchanged and is not a re-issue item — the trigger did not
> fire then and has not fired since.

## The #7787 trigger — put to this review as FIRED, ruled NOT FIRED

`knowledge-base/legal/audits/2026-09-counsel-review-7717.md` carries, verbatim, the
re-evaluation trigger:

> "Promotion of `scripts/lint-legal-registers.sh` from advisory to blocking (#7787) — the gate's
> scope changes what the register's completeness claim is worth."

This review was told that this PR IS that promotion, and that recording it as FIRED was mandatory.
**It is not, and I decline to record it.** Three independent checks, each of which alone is
dispositive:

1. `scripts/lint-legal-registers.sh` does not appear in `git diff --stat origin/main...HEAD`. The
   file's most recent commit is `6b95920b4` (#7838), which predates this branch.
2. `scripts/test-all.sh` still carries, unchanged by this PR:
   `run_suite "scripts/lint-legal-registers-live" bash scripts/lint-legal-registers.sh --advisory`
   — and the comment block immediately above it still reads `ADVISORY FOR ONE MERGE CYCLE (#7717)`
   with `PROMOTION: delete the --advisory flag on the next line.` The flag is present.
3. `gh issue view 7787` returns **OPEN**.

The branch name contains `7787`, and a new blocking gate over the legal corpus **did** land in this
PR. That is what makes the premise plausible and wrong: the gate that landed is
`scripts/probe-legal-corpus-truth-live` (A11), a **corpus-truth** probe over the six published
documents, which is a different instrument from `lint-legal-registers.sh`, a **completeness** lint
over the two register files. The #7717 trigger is textually specific to the second, and its stated
concern — "what the register's completeness claim is worth" — is about register completeness, not
corpus truth. Recording a trigger as fired on an instrument it does not name would put a false
statement into the ledger that is supposed to be the check on false statements.

**Disposition: the trigger stays ARMED**, and is carried forward into this attestation's own
`re_evaluation_triggers` so that it cannot be lost between the two documents. The standing #7717
counsel review is **not** invalidated by this PR, because the event that would invalidate it has
not occurred. Whichever PR deletes the `--advisory` flag fires it, and must re-read both this
attestation and the #7717 review at that point.

**What A11 does change, stated for the record so the next reader is not left inferring it.** The
truth probe is blocking from the start, and it is the first gate in this repository that measures a
legal document against a fact rather than against its own mirror. My own operating instructions warn
that the five `docs/legal/**` gates "measure agreement, not truth" and that two byte-identical
copies of a false sentence pass every one of them. A11 narrows that hole for the specific claims it
enumerates — but only for those, by literal string. It does not generalise, and it is not a
substitute for reading the prose. B1 and B2 below were both found by reading, and both survive a
fully green A11 run.

## The counsel-review ledger — a ruling, because the policy currently implies a file that does not exist

`knowledge-base/legal/tc-version-bump-policy.md:212` requires that a non-T&C legal-doc edit be
tier-classified because "the classification still applies for Article 30 register +
counsel-review-ledger purposes". `git grep -l 'counsel-review-ledger'` returns that policy line, one
planning document, and one spec — and no artifact. The policy therefore directs the reader to a
ledger it never names.

**Ruled: `knowledge-base/legal/audits/` IS the counsel-review ledger.** It is the only tree in this
repository that holds per-change counsel reviews and CLO attestations under stable filenames, it is
where every `re_evaluation_triggers` list lives, and it is what the ship Phase 5.5 gate reads. The
term in the policy is a description of this directory, not a reference to a missing one. This
attestation is filed into it, and its `tier_classification` frontmatter key is the tier the policy's
step 4 asks for.

Recorded here rather than repaired in `tc-version-bump-policy.md`, because this PR's only permitted
write is this file. **Follow-up, filed to #7892:** replace the bare term at
`tc-version-bump-policy.md:212` with the path. While that file is open, two neighbouring staleness
items in the same section should be swept: its "Body-equivalence scope (interim)" paragraph still
says the guard covers "`terms-and-conditions` **only**", but `BODY_EQUIVALENCE_DOCS` now also
enrols `acceptable-use-policy` and `disclaimer`; and step 3's parenthetical describes the
`legal-doc-consistency` test without mentioning the mirror-drift ratchet that R1 below trips.

## Blocking findings

> **Both cleared at re-issue** — see §Discharge on re-issue. Retained as the record of what was
> found against `1959995d8`.

### B1 [CLEARED at re-issue] — Privacy Policy §5.14: the section's scope was widened, three of its bullets were not

This PR amended `docs/legal/privacy-policy.md:418` (mirror `:427`) to read:

> "**Two emitters reach this source:** the host plane and `inngest-server.service` (since
> 2026-05-21, PR #4279), and the **user-serving `soleur-web-platform` application container's**
> pino stdout at severity WARN and above (since **2026-06-02, PR #4786**). The second is the
> higher-sensitivity of the two and was not previously named here."

That is correct and is the disclosure #7786 exists to make. But the bullets beneath it were written
when §5.14 covered one emitter, and they were not touched:

**(a) `Data processed` (`:420`) is now false on two counts, not one.** It reads "journald log lines
(mirrors pino stdout from `inngest-server.service`) and host_metrics scrapes … shipped from the
Hetzner **inngest VM** via the Vector agent … scoped to the **inngest plane's failure surface**."
The stream the sentence above just disclosed comes from the user-serving web host, not the inngest
VM, and its surface is the user-serving application's WARN-and-above failure surface, not the
inngest plane's. The Data Protection Disclosure, edited in this same PR, now says the opposite —
§2.3(m) dropped exactly that `inngest-server.service` parenthetical and replaced it with the
two-emitter statement. **The two published documents now give a data subject two different answers
to "whose logs go to Better Stack, and from where".** Under Art. 13/14 this is not a locative nit:
it understates the categories of personal data in the disclosed flow.

**(b) `Pseudonymisation` (`:421`) asserts a safeguard at a boundary the same PR proves it does not
sit at.** It reads "User identifiers are pseudonymised **at the Vector boundary** by replacing the
raw `userId` / `user_id` with a keyed cryptographic hash". For the newly-in-scope stream that is
wrong, and §2.3(m) says so in terms:

> "the `userIdHash` is computed **in the application's own pino logger, before the line ever reaches
> journald** — not at the Vector boundary. `pii_scrub_structured` short-circuits when the parsed
> payload carries no raw `userId`, so for this stream the HMAC stage is a no-op backstop that never
> fires; a production record sampled 2026-09-07 carries the tag `pii_scrub_applied:
> "drop_userdata+string"`, with no `+structured`. … Stating that this stream is 'pseudonymised at
> the VRL boundary' would be the same class of error this disclosure is correcting — true of other
> emitters, not of this one."

I have verified the mechanism independently rather than inheriting it: `vector.toml`
`[sources.app_container_journald]` filters on `include_matches.CONTAINER_NAME =
["soleur-web-platform"]` and `level_int >= 40`, and the VRL structured branch is conditional on a
raw `userId` being present.

The data subject is not worse protected — the hash is computed earlier, if anything a stronger
posture. But §5.14 tells them the safeguard is applied by a component that, for their stream, does
not apply it, and it cites `apps/web-platform/test/infra/vector-pii-scrub.test.sh` as the parity
proof for a stage that never fires on this path. An Art. 32 measure described at the wrong layer is
not a demonstrable measure.

**Required:** amend `:420` and `:421` to distinguish the two emitters, mirroring the treatment
§2.3(m) already uses. Mirror to `plugins/soleur/docs/pages/legal/privacy-policy.md:429`/`:430`,
re-pin the SHA, re-run the gates.

### B2 [CLEARED at re-issue] — GDPR Policy §3.7: the lead sentence was widened, the balancing test was not

`docs/legal/gdpr-policy.md:128` (mirror `:136`) had its opening clause correctly amended to disclose
that the WARN-and-above subset is "**additionally shipped off-host to Better Stack Logs since
2026-06-02, PR #4786**". The balancing-test tail of the same line was not amended, and still reads:

> "**Better Stack Logs IS enabled for journald + host_metrics ingestion as of 2026-05-21 (PR
> #4279); VRL pseudonymisation … applies at the Vector boundary before egress**"

Two defects, and the second is the one that matters:

1. It re-states the pre-#7786 scope (`journald + host_metrics`, `as of 2026-05-21`) one sentence
   after the lead clause corrected it — the half-applied-replacement pattern, which is the named
   #7349 defect class and the one this corpus has been bitten by before.
2. It carries the same VRL-boundary pseudonymisation claim as B1(b), and here it is **load-bearing
   in a different way**: this is the Art. 6(1)(f) balancing test. Limb (a) of that test — "processing
   is limited to error and breadcrumb signals plus pseudonymous identifiers necessary to attribute an
   incident to a user lifecycle" — was written against the inngest plane's failure surface, and the
   test has never been run against a user-serving application container's WARN-and-above stream. A
   balancing test that does not name the higher-sensitivity stream it now covers has not balanced it.

My own operating rule is that when a new data-processing activity lands, the GDPR Policy limb — the
balancing test and the processing register — is the one most often missed. It was missed here, in
precisely that shape.

**Required:** update the balancing-test tail to the two-emitter scope and the correct
pseudonymisation locus, and state in limb (a) that the additional stream is severity-gated at WARN
and above with the Art. 9 user-content key drop applied at the Vector boundary before egress —
which is the part of the VRL boundary that IS load-bearing for this stream, and is separately
verified. Mirror; re-pin; re-run.

## Required before merge (as issued)

> **At re-issue:** R2 is cleared; R1 and R3 stand, and R4 is added. Live status is at
> §Remaining before merge.

### R1 — the mirror-drift ratchet is RED, and no accept-reason is recorded

Run locally against the working tree:

```
bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main   →  exit 1
::error::legal mirror drift: 3 document(s) drifted beyond the baseline
  data-protection-disclosure: CONTENT CHANGED: a line that was already drifting was edited in place
    baseline 4 drift line(s) -> HEAD 4; 2 not in the baseline
  gdpr-policy:   baseline 52 -> HEAD 52; 2 not in the baseline
  privacy-policy: baseline 18 -> HEAD 18; 2 not in the baseline
```

**This is not a legal defect, and I record it as such so that it is not mistaken for one.** Drift
did not grow on any document (4→4, 52→52, 18→18). Every one of the six flagged lines is the
`**Last Updated:**` line, whose canonical and mirror copies were already divergent in the baseline;
this PR advanced the date on both, which trips the ratchet's in-place-edit arm by design.

The gate's documented escape hatch is `SOLEUR_LEGAL_DRIFT_ACCEPT='<reason>'`, which downgrades to a
warning and records the reason. Nothing in this PR sets it. **Either** set it with a reason naming
this attestation and the fact that drift count is unchanged, **or** bring the six `Last Updated`
lines to byte parity (the cleaner outcome, since it reduces the baseline). A red required check is
not something to discover at merge.

### R2 [CLEARED at re-issue] — retire the six `*[DRAFT -- pending CLO/counsel review per #7786]*` markers

All six published documents ship this marker on the live page — four occurrences in
`docs/legal/data-protection-disclosure.md` §2.3(m) alone, and one each in the other five files.
**This attestation is that review.** Once B1 and B2 land, the pendency the markers announce is
discharged, and a published legal notice that tells the reader its own disclosure is provisional —
when it is not — asserts something false about its own status. That is the same one-document-two-
answers shape that forced the standing correction marker in the #7717 re-issue.

Sequence: land B1 + B2 → delete the six markers → re-pin `legal-doc-shas.ts` → re-run all five
gates → re-issue this attestation as SIGNED-OFF. Do **not** delete the markers before B1 and B2,
which would leave the documents un-caveated and wrong.

### R3 — this attestation is Art. 33(5)-producer-shaped and needs a waiver, or it reds #7787 on arrival

Running the register lint against the working tree with this file in place:

```
bash scripts/lint-legal-registers.sh --advisory
::error::(c) determination-shaped file is neither indexed nor waived:
         knowledge-base/legal/audits/2026-09-07-clo-attestation-7786-off-host-log-claims.md
lint-legal-registers: 7 assertion(s), 1 failed (registers=4 rows=5 produced=15 waived=10 …)
::warning::lint-legal-registers: 1 finding(s) -- ADVISORY this cycle, not blocking.
```

**Ruled: WAIVE. This is not an Art. 33(5) determination.** Applying the #7717 B1 predicate — two
conjunctive limbs, of which limb 2 is *substantive, not citational* — limb 1 fails on its face.
No security event occurred. This audit reviews a **disclosure correction**: prose about a
processing flow that has run, disclosed-but-incompletely, since 2026-06-02. The text it attests
says so in terms — "this was a disclosed processing change, not an unauthorised disclosure". That
is precisely the ground on which `audits/2026-08-counsel-review-7440.md` was waived and the waiver
UPHELD in the #7717 ruling ("the addition of a recipient role, not an incident"). The file trips the
producer regex because it *quotes* the Art. 33 / Art. 34 no-notification ground it is attesting;
under limb 2 that citation is not what makes a determination.

**Required:** add a `NOT_TRANSCRIBED` entry for this file to `scripts/lint-legal-registers.sh` with
that reason and a citing issue, in the same PR. I cannot make that edit — this attestation file is
this review's only permitted write — so it is handed to the implementer rather than performed.

**And note what this is.** The finding is ADVISORY today and exits 0 only because the
`--advisory` flag is still on the `run_suite` line. **The moment #7787 promotes that gate, an
unwaived attestation file is a red required check.** The #7717 trigger's own wording — "the gate's
scope changes what the register's completeness claim is worth" — is not abstract: the first thing
the promoted gate would refuse is the document you are reading. That is one more reason the trigger
must stay armed rather than be recorded as spent, and it is a concrete item for #7787's promotion
checklist: sweep every `audits/` file the producer regex catches, and waive or index each, **before**
deleting the flag.

## Discharge on re-issue

Re-read against the working tree after this audit was first issued. **B1, B2 and R2 are cleared.**
Verified, not accepted on assertion:

- **B1 cleared.** `docs/legal/privacy-policy.md:420` now enumerates the two emitters separately and
  says of the second, in terms, that it is "scoped to the user-serving application's failure
  surface — **not** the inngest plane's". The "Hetzner inngest VM" locative is gone, and the
  severity gate `level_int >= 40` is stated on the published surface. `:421` is retitled
  "**Pseudonymisation — the locus differs by emitter, and stating a single one would be
  inaccurate**" and gives the application-logger locus for the application-container stream, the
  `pii_scrub_structured` short-circuit, the 2026-09-07 `drop_userdata+string` sample, and what
  Vector *does* contribute (the Art. 9 key drop and the regex backstop) — while preserving the
  VRL-boundary description for emitters that ship a raw identifier, which is where it is true.
  That is the right shape: the old sentence was not deleted, it was correctly scoped.
- **B2 cleared.** `docs/legal/gdpr-policy.md:128`'s balancing-test tail now reads "Better Stack
  Logs IS enabled for off-host ingestion from **two emitters**", names both with their dates, and
  carries the same locus split as B1. Limb (a) of the Art. 6(1)(f) test was extended rather than
  left standing: it now records that for the application-container stream the limitation "is
  enforced twice before egress" — the WARN-and-above severity gate, so routine operation produces
  no off-host record at all, and the Art. 9 key drop. That is the balancing the test was missing,
  and it rests on the severity filter I verified in `vector.toml`.
- **R2 cleared.** Zero occurrences of `DRAFT -- pending CLO/counsel review per #7786` remain in any
  of the six documents.
- **Lockstep verified, not assumed.** Each of the three new passages was hashed in the canonical
  and in its Eleventy mirror: identical in all three cases. The mirror is the published surface;
  a canonical-only fix would have changed nothing a user reads.

Two things this discharge does **not** reach, both engineering rather than legal, and both red on
the working tree right now — see §Remaining before merge: the SHA pin (R4), which the B1/B2 edits
themselves invalidated, and the mirror-drift ratchet (R1). R3 is unchanged.

## Corrections recorded (non-blocking)

- **C1 — `docs/legal/data-protection-disclosure.md` §2.3(m), cross-reference direction.** Limb (3)
  of the no-notification ground reads "the payload is pseudonymised **in the application, before
  egress** (see the pseudonymisation note below)". The note is **above** it in the same paragraph —
  the "Where the pseudonymisation actually happens" block precedes `Legal basis:`, `Retention:` and
  `CI gate:`, which in turn precede the ground paragraph. Read "above". Mirror carries the same
  wording.
- **C2 — the `CI gate:` workflow name, pre-existing and carried forward.** §2.3(m) states the gate
  is "`validate-vector-config` in `.github/workflows/apply-web-platform-infra.yml`". The job
  `validate-vector-config` lives in `.github/workflows/validate-vector-config.yml`;
  `apply-web-platform-infra.yml` only mentions it in a comment at line 368 explaining why it lives
  elsewhere. The same misnaming sits in `compliance-posture.md`'s Better Stack row. Not introduced
  by this PR — but the paragraph was re-published, and a gate citation that names the wrong file is
  the `cq-cite-content-anchor-not-line-number` failure mode one level up. Filed to #7892.
- **C3 — `probe_legal_corpus_truth.py`, the bare `30 MB` literal.** `FORBIDDEN` now includes the
  free-standing string `30 MB`, matched case-insensitively across all six documents. It is correct
  today and it is not scoped to log retention: any future legitimate `30 MB` figure anywhere in the
  corpus (an upload cap, an attachment limit) reds a blocking gate for an unrelated reason. Prefer
  anchoring on `30 MB rolling` or on the `max-size=10m` pairing when the unit arm lands at #7892.
- **C4 — `probe_legal_corpus_truth.py`, the `2026-06-02` required anchor.** Requiring a bare date
  literal in all six documents is a weak affirmative anchor: any unrelated sentence carrying that
  date satisfies it. The `Better Stack` companion entry carries most of the weight. Acceptable as
  shipped; worth strengthening to a phrase in the same follow-up. The anti-vacuity floor
  (`MIN_SURFACES`/`MIN_DOCS` as absolute literals rather than `len(SURFACES) * len(DOCS)`) is
  correct and is commended — it is the exact defect this repository has documented repeatedly, and
  the `REQUIRED`-list widening that lets the probe tell a **correction** from a **deletion** is the
  right instinct: deleting the parenthetical would otherwise have passed.

## How this was verified

Every implementation-detail claim in the corrected prose was checked against the code, not against
the PR description — the drift class recorded at PR #4353 / #4558. What was measured:

| Published claim | Verified against | Result |
|---|---|---|
| Container runs `--log-driver journald` | `apps/web-platform/infra/cloud-init.yml:815` (`docker run -d --name soleur-web-platform --log-driver journald`) | Confirmed |
| The 30 MB figure is the daemon default, governing *other* containers | `cloud-init.yml:458` — `daemon.json` writes `"log-driver": "json-file"`, `max-size: 10m`, `max-file: 3` | Confirmed, and the register's "that block now sits near line 458" is exact |
| `SystemMaxUse=1G` / `SystemKeepFree=2G` / `RuntimeMaxUse=200M` | `apps/web-platform/infra/journald-soleur.conf` `[Journal]` section | Confirmed, all three |
| Bound re-anchored on an executable assertion | `apps/web-platform/infra/journald-config.test.sh:71-72` — `assert "SystemMaxUse=1G"` / `grep -qE '^SystemMaxUse=1G$'` | Confirmed |
| That assertion runs in CI | `.github/workflows/infra-validation.yml:1223` — step `Run journald persistent-storage tests` | Confirmed |
| WARN-and-above (`level_int >= 40`), app container only | `apps/web-platform/infra/vector.toml` — `include_matches.CONTAINER_NAME = ["soleur-web-platform"]`, `level_int >= 40` | Confirmed |
| Driver switch landed 2026-06-02 at #4786; journald bound later at #4800 | `git show 223364c14` (2026-06-02, #4786) and `faf9ea95e` (#4792 → PR #4800) | Confirmed |
| No Art. 28(3) instrument recorded as executed | `compliance-posture.md` Better Stack row — `NOT EXECUTED — no Art. 28(3) instrument recorded`; #7529 and #7825 both OPEN | Confirmed |
| Trigger-list parity, PA-8 §(f) ↔ runbook | Both lists enumerated item by item | 7/7, same numbering and same fired/not-fired states |
| The five denial phrasings are gone from all six documents | Grep sweep over `docs/legal/` and `plugins/soleur/docs/pages/legal/` for each phrasing plus `30 MB` | Zero residual assertions; every surviving occurrence is inside a quoting correction note in the register |
| SHA pin refreshed | `bash apps/web-platform/scripts/check-tc-document-sha.sh` | exit 0 |
| Corpus-truth probe | `bash scripts/probe-legal-corpus-truth.sh` | `CORPUS-OK (6 document(s) examined)`, exit 0 |
| Scope-block placement | `bash scripts/lint-legal-scope-block-placement.sh --base origin/main` | 0 blocks classified, 0 violations |
| Mirror-drift ratchet | `bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main` | **exit 1** — see R1 |

Two claims I checked specifically because they are the kind that get inherited rather than
measured. The register states the previous `cloud-init.yml:303-310` anchor "had already rotted" —
it had; lines 303-310 are now the Sentry fatal-emit trap in `runcmd`, and the `daemon.json`
heredoc begins at line 456. And the live measurement `pii_scrub_applied: "drop_userdata+string"` with no
`+structured` is consistent with the VRL source as written, which is the strongest confirmation
available to a static reviewer; I did not re-query the vendor and do not attest to the sample itself.

## Boundaries — what this attestation does NOT clear

**#7851 remains OPEN.** That issue lists three published Better Stack statements that survived the
NOT-EXECUTED correction. Their state after this PR:

| #7851 row | State after PR #7881 |
|---|---|
| DPD §2.3(m) — data flowed "under processor-DPA terms" | **Corrected in this PR.** The ground is now expressly *not* a DPA: §2.3(m) states "no Art. 28(3) instrument is recorded as executed with this processor" and rests the conclusion on three limbs. Attested at A1 |
| Privacy Policy §5.14 — "SCCs incorporated as belt-and-braces" | **UNTOUCHED and NOT CLEARED.** Still live at `docs/legal/privacy-policy.md:423` and `:424`. An Art. 46 safeguard incorporated into an instrument recorded as non-existent. **Remains open at #7851** |
| "Better Stack paid-tier default" retention | **Not on the published surface, and not cleared by me.** The published copies already carried "**90 days** … read from the processor's own source record" before this PR (#7772, 2026-09-04). The residual instance was in `knowledge-base/legal/data-processing-agreement-template.md` Schedule 2, corrected here (A9). Whether that closes #7851's third row is **#7851's call, not this attestation's** — I record the state, I do not close the row |

**#7529 and #7825 stay OPEN, and this PR widens the gap rather than narrowing it.** Nothing in this
attestation should be read as evidence of Art. 28(3) compliance. The opposite: by disclosing the
user-serving application container as a sixth emitter relying on an unexecuted instrument, this PR
makes the exposure larger and more legible. The Better Stack row in `compliance-posture.md` already
records five emitters and two sinks relying on an instrument recorded as NOT EXECUTED, with a
re-evaluation date of 2026-11-13. That row's directed remedy — execute the Vendor DPA, or record on
#7529 the specific published terms relied on as the "other legal act" under Art. 28(3), with the
date and mechanism of incorporation — is unchanged and undischarged.

**`TC_VERSION` and `docs/legal/terms-and-conditions.md` are untouched**, correctly. The eight
non-T&C notice documents carry no version constant; the SHA-refresh contract applies instead, and
it was honoured.

**Not reviewed here:** the runbook SSH three-way split (#7874), the
`lint-infra-no-human-steps.py` changes, and `lint-orphan-test-suites.sh`. They ride the same PR and
are engineering artifacts with no legal limb; A11 and A12 are the only parts of that work this
attestation reaches.

## Remaining before merge

The legal sign-off is given. Three items are outstanding, none of them a legal question, and each
is a red or soon-red gate rather than a matter of judgement:

1. **R4 — re-pin `apps/web-platform/lib/legal/legal-doc-shas.ts`.** NEW at re-issue, and caused by
   the B1/B2 fixes themselves. `bash apps/web-platform/scripts/check-tc-document-sha.sh` now exits
   1 with three errors — `data-protection-disclosure`, `gdpr-policy` and `privacy-policy` each
   "content changed but `LEGAL_DOC_SHAS[...]` is stale". The SHA-refresh contract at
   `knowledge-base/legal/tc-version-bump-policy.md` §Non-T&C legal docs is unconditional: every
   canonical edit is paired with the refresh in the same PR. It was honoured at `1959995d8` and is
   now stale again. Re-pin last, after any further prose edit.
2. **R1 — the mirror-drift ratchet.** Still exit 1, still confined to the six `**Last Updated:**`
   lines, still no growth in drift count (4→4, 52→52, 18→18). Either set
   `SOLEUR_LEGAL_DRIFT_ACCEPT` with a reason naming this attestation, or bring those six lines to
   byte parity — the better outcome, since it lowers the baseline.
3. **R3 — the `NOT_TRANSCRIBED` waiver for this file** in `scripts/lint-legal-registers.sh`.
   Advisory today; a red required check the day #7787 lands.

After R4, re-run all five: `check-tc-document-sha.sh`, `probe-legal-corpus-truth.sh`,
`lint-legal-scope-block-placement.sh`, `lint-legal-mirror-drift-baseline.sh`, and
`legal-doc-consistency.test.ts`. A green run on those five is **not** evidence that the prose is
true — that is the #7349 lesson, and it is the reason this attestation exists alongside them.

No further CLO review is required for this PR unless the published prose changes again. If it
does, the changed limb comes back here; the discharged artifacts do not.
