---
title: "CLO review — PA-7 omitted the R2 evidence layer and one of its processors (PR #7622)"
type: clo-review-record
date: 2026-09-03
issue: 7601
pr: 7622
attested_commits: 28612e8cd
attestation-authority: clo
status: APPROVED (CLO-agent-reviewed, Soleur-as-tenant-zero v1)
disposition: APPROVE-WITH-CHANGES, discharged to APPROVED
signed_off_at: 2026-08-20
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
tier_classification: "Tier 1 (material) — an omitted processor added to an Art. 30 Recipients cell, a third country named for the first time as Art. 30(1)(e) requires, and a technical-measures cell corrected from understated to accurate"
semver: "N/A — TC_VERSION unaffected; no document under `docs/legal/**` changed in PR #7622"
brand_survival_threshold: single-user incident
written_against: "the Art. 30 register at commit 28612e8cd — Processing Activity 7 cells (d), (e) and (g) — and the IaC under `apps/cla-evidence/infra/` at that commit"
re_evaluation_triggers:
  - "HISTORICAL — recorded as the 2026-08-20 review's own triggers, restated here as history rather than as commitments made on 2026-09-03. Any migration of `soleur-cla-evidence` to Cloudflare's EU jurisdiction tier: per the corrected §(e) this would change the residency position and the `iam.tf` token resource-strings, but would NOT on its own convert the cell to a no-transfer posture — that additionally requires the contracting entity and the access path to cease being US-established."
  - "HISTORICAL — first arms-length (non-Jikigai) contributor signs the CLA. The first data subject of PA-7 who is not the operator."
  - "HISTORICAL — any revision that reverts the FreeTSA rows to REMOVAL rather than re-characterisation, which would falsify two cross-references in the same commit."
  - "HISTORICAL — adoption of a retention ceiling, carved out at the time to #7668, which the review declined to decide."
---

# CLO review — PA-7 omitted the R2 evidence layer, and one of its processors (PR #7622)

## Two frontmatter notes, recorded rather than left to be inferred

**`issue: 7601`, on a file named for 7622.** Both sibling records match their filename number to
their `issue:` key. This one cannot: 7622 is a **pull request**, and the issue it closed is 7601.
The filename carries the PR number because this record is of a PR review; the frontmatter carries the
issue number because that is what the key means. A reader grepping `issue: 7622` will find nothing —
grep `pr: 7622`.

**`type: clo-review-record` is a new value in this directory**, alongside `clo-attestation`,
`counsel-review` and `clo-ruling`. Minted deliberately and named here rather than silently: this is
neither a ruling (it decides nothing) nor an attestation of the PR it sits in (it records another
review, of another PR, three weeks later). The same PR argues against minting a tenth *amendment
label* for the register; that argument turns on #7669 having to learn any new label, and no consumer
parses these `type:` values today.

## What this record is, and when it was written

This is the retrospective audit record of a CLO review conducted on **2026-08-20**, written on
**2026-09-03**. It is not contemporaneous, and it must not be read as though it were.

The record exists because the review left no audit artefact of its own. Its sibling — the review of
the published-corpus reconciliation that landed the same day — was recorded at
`knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md`, and the
absence of the matching record for this one was surfaced while working #7625, a filing this review
itself produced.

Sourced from the merged pull request's own review narrative rather than re-derived, so that it
records what the reviewing authority actually held rather than a 2026-09-03 reconstruction of it.

## Disposition

**APPROVE-WITH-CHANGES**, discharged to **APPROVED**.

The review upheld **both** departures from the filing issue's stated scope:

1. **Adding Cloudflare as a PA-7 recipient**, which the issue had scoped out. Art. 4(9) makes a
   processor a recipient, and an issue's scope note is a work-planning statement rather than a legal
   authorisation boundary.
2. **Declining the instruction to record "EU region"** — ruled not merely permitted but *mandatory*,
   since recording a localisation safeguard that does not exist would be a false Art. 30(1)(e)
   statement.

## Three defects, not the one filed

The issue scoped the work as a §(g) accuracy fix and stated explicitly that there would be no change
to purposes, categories, recipients, retention, or lawful basis. Verifying that scope against the IaC
turned up two further problems — one more serious than the one filed, and one inside the issue's own
proposed wording.

- **§(g) understated the posture, as filed.** PA-7 described its technical measures purely as the
  public append-only git branch and its content-addressed commit hashes; the R2 sidecar was absent,
  so the register omitted the strongest measures actually in place. This direction errs safe: the
  register claimed *less* protection than exists.
- **§(d)/(e) omitted a processor — outside the issue's scope, and this does not err safe.** The
  Recipients cell listed only GitHub Inc, while the CLA evidence is under object custody in
  Cloudflare R2. An understated technical measure errs safe; an omitted processor does not. That
  asymmetry is why it was corrected in place rather than deferred.
- **A defect in the issue's own proposed wording**, corrected before it landed.

## The nine applied findings

Grouped as the source groups them.

### §(g) — technical and organisational measures

1. The RFC 3161 pre-image is a **manifest** of `{key, etag, size, last_modified}` rather than the
   archive bytes. The true statement is *stronger* than the one filed: each signature key **is the
   SHA-256 of its record**, so timestamping the manifest binds every record's content.
2. The first-write-wins **conditional PUT** covers the content-addressed `signatures/` path, not only
   the per-quarter canonical key.
3. The absolute WORM claim contradicted §(f)'s erasure commitment and was retracted.
   `gdpr-override.sh` is a documented Art. 17 path and **is itself a TOM** — a measure, not a hole in
   one.

### §(d) — recipients

1. The meta-reasoning was cut: house style **records facts, not arguments**.
2. The sentence that actually discharges the correction was added — Cloudflare was contractually
   covered throughout the omission window, so an Art. 30 record-keeping incompleteness is not an
   **Art. 4(12)** personal-data breach and triggers no Art. 33/34 notification duty.
3. The FreeTSA non-recipient determination was hardened onto **aggregate-manifest** reasoning rather
   than the weaker "a digest is not personal data" claim.
4. The **runner-egress-IP** hole was closed: the HTTPS submission necessarily discloses the
   GitHub-hosted runner's egress address to the TSA, and that address belongs to GitHub's ephemeral
   Actions fleet and to no data subject of this activity.

### §(e) — third-country transfers

1. The cell never named the third country, which **Art. 30(1)(e)** requires. The transfer arises from
   the **importer's identity** rather than the location of the bytes (**EDPB Guidelines 05/2021**,
   criterion 3), after which the placement-hint point does its proper, narrower job.
2. The reviewing authority's own re-evaluation trigger was overstated: the EU jurisdiction tier
   **would not, on its own, convert** the cell to a no-transfer posture.

## Verification and filings

Every CLO factual claim was verified against source before publication — `gdpr-override.sh`,
`r2-conditional-put.sh` and its `If-None-Match` callers, `manifest.jsonl`, and the bucket-wide
`prefix: ""`.

The review produced two **filings rather than deferrals**, and the distinction was stated at the time:
neither was work the pull request could have done.

- **#7624 — published-corpus divergence.** Could not be folded in: it corrects ten statements across
  three canonical documents under `docs/legal/**` and four Eleventy mirrors, a change class that
  fires all five legal CI gates and requires canonical and mirror to move atomically with a
  document-SHA re-pin. Also the more serious defect — Art. 13(1)(f) transparency rather than Art. 30
  record-keeping. **Those figures are the scope as estimated on 2026-08-20 and are transcribed here
  rather than re-derived; the correction actually shipped as #7664, touching five canonical documents
  and five mirrors.**
- **#7625 — PA-7 §(c) omits `comment_body`.** Directed **do not bundle**, because the Art. 9
  consequence needed its own analysis: `comment_body` is the only unbounded-content field in PA-7,
  and the Special-categories cell asserted "None" over it. Re-deriving that determination was held
  not to be a wording fix and not to be decidable as a side effect.

Both are consequences the review surfaced *because* the pull request forced the register to be read
against reality. #7625 is the issue this record's own PR closes; its determination is at
`knowledge-base/legal/audits/2026-09-counsel-review-7625.md`.

## Standing caveat

This is the v1 internal counsel-review posture under Soleur-as-tenant-zero. It is draft material and
is **not a substitute for external counsel**, which is reserved for the frontmatter triggers above.
The operator retains a veto.
