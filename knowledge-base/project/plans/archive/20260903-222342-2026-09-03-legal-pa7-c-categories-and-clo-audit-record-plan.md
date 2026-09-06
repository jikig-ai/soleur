---
title: "legal: Art. 30 PA-7 §(c) omits fields the R2 evidence record carries, plus the missing CLO review record for #7622"
date: 2026-09-03
slug: legal-pa7-c-categories-and-clo-audit-record
branch: feat-one-shot-7625-pa7-categories-and-clo-audit-record
issue: 7625
closes: 7625
type: docs
lane: cross-domain
priority: p2-medium
domain: legal
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

> No `spec.md` exists for this branch, so `lane:` could not be carried forward and defaults to
> `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened:** 2026-09-03. **Prior passes:** a plan-time CLO consult, a seven-agent plan review, a CLO
follow-up consult, and two mechanical deepen sweeps.

### What the review passes actually changed

| # | Change | Found by |
|---|---|---|
| 1 | **A false statement was caught before it shipped.** Ruling 3's replacement cell asserted that CLA §0 cross-references the DPD. It does not — §0 names Privacy Policy §§4.5/5.11/10 and GDPR Policy §§3.4/6. The false clause was landing in the one cell whose original defect was that it named no mechanism | Kieran + architecture-strategist, corrected by the CLO in addendum A1 |
| 2 | **The PR was split.** The transparency consequence of the capture predicate requires a `docs/legal/**` edit — a five-gate change class — so it became PR B rather than riding along. Its scope then grew twice: `privacy-policy.md` §5.11 (a false bot-only enumeration) and §8.1 (the section that actually confers a rights route, with carve-outs for three other accountless populations and none for this one) | CLO Ruling 5(B); scope additions from architecture-strategist and spec-flow, endorsed in A6 |
| 3 | **PA-7 gained an `(h) DSAR` cell.** The change mints an involuntary data-subject population; PA-32 and PA-33 carry `(h)` cells for exactly that reason and PA-7 had none. PA-7's answer is materially *better* than theirs — `inspect-evidence.sh by-contributor` filters on `.actor.login` and so reaches a non-signer — which is why it had to be written down rather than inferred | spec-flow GAP-A1, ruled in A4 |
| 4 | **A `CORPUS DIVERGENCE` block was added**, and an AC that would have forbidden it was corrected. Without it the register-vs-corpus divergence is not merely unrecorded but *undetectable*, because #7669 — the sentinel that would catch it — is deliberately not built here | architecture-strategist H2, ruled in A3 |
| 5 | **Active Items rows went from one to four**, with zero DPIA rows and the reason recorded so the count is not re-litigated. An AC asserting "exactly one" would have blocked the correct outcome | architecture-strategist H1, ruled in A5 |
| 6 | **A commit-time blocker was found.** The register carries ten pre-existing markdownlint errors, all outside PA-7, and lefthook runs markdownlint on staged `*.md`. Staging the register blocks the commit, and the natural escape is `--no-verify` — the exact bypass the AC's own rationale warns about | Kieran P0 |
| 7 | **Phase 1's measurement was cut and moved into the PR B issue.** It bought no property in the Property List, the advisory forbids this PR to answer the only question it decides, and it put a live production-credential read inside a documentation-only PR. Its prescribed command was *also* structurally incapable of answering its own question — `by-contributor` filters on `.actor.login`, and an over-captured record has a different login | code-simplicity + Kieran P1 + spec-flow GAP-C2 |
| 8 | **Eleven acceptance criteria were cut and five defective ones rewritten**, including one vacuous by construction after a rename in the same phase, one whose anchor could not match the text the plan itself prescribes, and one asserting a process no command can falsify | code-simplicity, architecture-strategist, spec-flow |
| 9 | **Phases were reordered twice into dependency order.** The filings phase now runs before the amendment (two cells cite an issue number it mints) and before the sweep (a `compliance-posture.md` row needs the same). The same read-before-write inversion was found twice in one plan | architecture-strategist + spec-flow |
| 10 | **Nine factual corrections to this plan's own research**, recorded in place rather than quietly rewritten — including `:658` being PA-33 rather than PA-35, which had propagated into five load-bearing places including two of the CLO's own rulings | the review panel |

### Deepen-plan post-edit self-audit sweep

The revision passes above renumbered phases twice, cut acceptance criteria from thirty to nineteen,
replaced one phase wholesale and appended an addendum. **Stale internal cross-references are the
predictable cost of that, and a mechanical sweep found six**, all now fixed:

- A sentence still saying **Phase 1 measures the archive** — the phase it names had been rewritten to
  hand that measurement to the PR B issue and record UNMEASURED. The exact contradiction the revision
  existed to remove, surviving one section away from the fix.
- Phase 5 step 2 still opening **"net one addition and zero edits"** after the addendum raised it to
  four rows. Phase 2 and the Files list had both been updated; this one sentence had not.
- A reference to **`AC29`**, which no longer exists — leftover from the pre-revision thirty.
- **A duplicate, orphaned `### AC pre-flight` section** sitting under Alternative Approaches
  Considered, carrying pre-revision AC numbers. It should have been deleted when its replacement was
  written; a section inventory earlier in the session had listed it twice and the duplicate was not
  acted on.
- Two **"Phase 4 step 2"** citations pointing at a phase that writes the #7622 record and has no
  step 2; both meant Phase 5.
- **"fourteen of the nineteen" / "the five it does not cover"** in the pre-flight table's own
  preamble, where the table below it covers thirteen and omits six — a counting error in the
  paragraph whose whole subject is honest coverage.

Four adjacent staleness fixes came out of the same read: a Risks row citing `AC22` (cut), one citing
`AC6` where it meant `AC5`, one saying "seven facts wrong" where the count is nine, and one naming
Phase 2 where the anchoring rule now lives at Phase 3.

### The pattern behind this plan's own errors, worth carrying forward

Every one came from **paraphrasing a plausible mirror instead of reading the thing**: `SignerRow` for
the record's shape, the receipt comment for the notice mechanism, line `:242` for a PA-7 block, PA-35
for PA-33, `2026-08-counsel-review-7440.md` for a frontmatter contract it does not carry. The mirror
is always adjacent, always nearly right, and always cheaper to consult than the source. That belongs
in `knowledge-base/project/learnings/` after this ships.

### Deepen-plan verify-the-negative sweep

Every negative claim in the plan body was swept mechanically against the tree — 168 candidate lines,
of which the checkable ones were run as commands. **Twenty-seven confirmed; one contradicted.**

The contradiction was this plan's own grep count for `hereby sign` (corrected in Phase 2 item 2, and
the ninth self-correction in the table above). The twenty-seven that held include every load-bearing
negative the plan's argument rests on: no workflow has a `paths:` filter for `knowledge-base/legal/**`;
nothing in CI validates the register's table integrity, PA numbering or cells; no frontmatter schema
exists for `audits/`; `generate-article-30-register.sh` cannot run and writes elsewhere;
`.markdownlintignore` does not cover the register; `lint-infra-no-human-steps.py` walks only
`legal/runbooks/`; `validate-vector-config.yml` does not fire; all five `docs/legal/**` gates hardcode
the canonical dir; `legal-doc-consistency.test.ts` touches the register only at a PA-15(c) RCS anchor;
PA-7 has no `(h)` cell and the file has exactly 8; `check-pa-22.sh` is wired into zero workflows;
`EvidenceRecordSchema` is non-strict so an undeclared field is silently stripped; `list_keys()`
swallows every `aws` failure; `by-contributor` filters on `.actor.login` and cannot detect
over-capture; and AUP §4.7 is scoped by its own heading to the hosted chat surface.

### Deepen-plan gate results

| Gate | Verdict |
|---|---|
| **4.5 Network-Outage** | **Does not fire.** One `firewall` hit at the plan's own enumeration of the IaC gate's detection strings — a description of a gate, not a network symptom this plan addresses. No SSH, handshake, reset or 5xx trigger in the Overview, Problem Statement or Hypotheses |
| **4.55 Downtime & Cutover** | **Does not fire.** No infra reboot/replace, no lock-taking DDL, no deploy/router change. The diff is three Markdown files |
| **4.6 User-Brand Impact** | **PASS.** Section present, four named populations, concrete artifact and exposure vector, threshold `single-user incident`. Files-to-Edit match no sensitive path |
| **4.7 Observability** | **SKIP (pure-docs).** Every Files-to-Edit path matches `^knowledge-base/` |
| **4.8 PAT-shaped variable** | **PASS.** The four-pattern sweep returns no matches |
| **4.9 UI wireframe** | **SKIP.** No UI-surface path in either Files list |
| **4.10 Encryption Posture** | **SKIP.** No `.tf`, migration, cloud-init or compose file, and the plan introduces no store and no cross-component connection. The R2 bucket it *describes* is pre-existing with its posture already at PA-7 §(g) |
| **4.11 Guard Contract** | **SKIP.** No guard, gate, lint or drift-check in the deliverable — and cutting the one that would have belonged here, in favour of #7669, is what keeps this true |
| **ADR ordinal** | **Not applicable.** No ADR created; `grep -c 'ADR-[0-9]'` returns 0 |
| **Cited rule IDs** | **PASS.** All five (`cq-assert-anchor-not-bare-token`, `cq-cite-content-anchor-not-line-number`, `hr-gdpr-gate-on-regulated-data-surfaces`, `wg-when-an-audit-identifies-pre-existing`, `wg-when-deferring-a-capability-create-a`) resolve to active `[id: …]` entries in `AGENTS.md` and none appears in `scripts/retired-rule-ids.txt` |
| **Cited PR/issue numbers** | **PASS.** All twelve resolve live and match the state the plan claims — #7622 and #7597 are merged **PRs**, #7601/#7624/#7100 closed, #7625/#7668/#7669/#7670/#7671/#7126/#7119 open |

## Overview

Two knowledge-base legal-register artefacts, one PR. Neither touches `docs/legal/**`, so the five
legal CI gates and the mirror/SHA-repin machinery are out of play.

> **The plan-time CLO advisory is binding and it changed the shape of this work. Read
> `## CLO Advisory — Binding Rulings` before anything else; where it and any other section of this
> plan disagree, it governs.** In summary: `None.` in the Special-categories cell is not sustainable;
> §(c) must widen across four record shapes *and* widen its categories of **data subjects**, because
> the evidence-write step gates only on the persisting `license/cla` status and so captures
> commenters who signed nothing; the Art. 6(1)(f) balancing holds for signers on a mechanism the limb
> misnamed, and fails on **necessity** for the non-signer capture; the register carries a
> nine-label amendment vocabulary rather than one; and the transparency consequence of the capture
> predicate **requires a `docs/legal/**` edit**, which is a different change class and is therefore
> **split out of this PR** rather than folded in.

**Deliverable 1 (#7625).** Art. 30 Processing Activity 7 §(c) "Categories of personal data"
describes only the public git-branch record shape. The evidence records written to the
`soleur-cla-evidence` R2 archive carry materially more, and the register does not know it holds
them. Three sub-parts: widen §(c) to describe every record shape the activity actually writes;
re-derive the **Special categories** determination against the one unbounded free-text field
(`comment_body`) via the `clo` agent, recording the reasoning; and correct the Art. 6(1)(f)
balancing limb (iii) if the informing mechanism it rests on does not hold.

**Deliverable 2.** `knowledge-base/legal/audits/` carries a record for one of the two CLO reviews
that came out of the 2026-08-20 PA-7 work but not the other. Write the missing record for the CLO
review of the PA-7 R2-evidence-layer amendment (merged as `28612e8cd`, PR #7622), sourced from that
PR's own review narrative, in the house style of its siblings.

## Research Insights

### Premise Validation (Phase 0.6)

Every reference the brief cites was probed before research was dispatched. All held, and two were
found to understate the position.

| Cited premise | Probe | Result |
|---|---|---|
| #7625 is open work | `gh issue view 7625 --json state,closedByPullRequestsReferences` | `OPEN`, `closedByPullRequestsReferences: []`. Title: *"legal: Art. 30 PA-7 §(c) omits comment_body and five other fields the R2 evidence record actually carries"* |
| `comment_body` absent from the register | `grep -c comment_body knowledge-base/legal/article-30-register.md` | `0` |
| PA-7 §(e) defers §(c) to #7625 | read `article-30-register.md:162` | Holds verbatim: *"§(c) field omissions remain tracked at #7625 and are untouched by this correction."* |
| `build-record.ts` exists and carries the named fields | read `apps/web-platform/scripts/cla-evidence/build-record.ts` + `schema.ts` | Holds, **and the delta is larger than six fields** — see below |
| The receipt step is soft-fail | read `.github/workflows/cla-evidence.yml:194-218` | Holds, **and is narrower than soft-fail** — see below |
| The published corpus already discloses the verbatim body | `docs/legal/gdpr-policy.md:96-103`, `privacy-policy.md:120`, `data-protection-disclosure.md:172` | Holds. gdpr-policy states the R2 layer holds "the verbatim sign-comment body and the document-hash at sign-time **in addition to the public-branch fields**" |
| No audit record exists for the #7622 review | `ls knowledge-base/legal/audits/` | Holds. `2026-08-20-clo-review-7624-…` present; no `7622` record |
| `28612e8cd` is the #7622 merge commit | `git log --oneline -1 28612e8cd` | Holds: `docs(legal): PA-7 omitted the R2 evidence layer — and one of its processors (#7622)` |

### The field delta is four record shapes, not one list

Verified against source, not against the issue body.

1. **Public git-branch canonical record** — `origin/cla-signatures:signatures/cla.json`. Live content
   carries per signer: `name`, **`id`** (GitHub numeric database ID), **`comment_id`**, `created_at`,
   **`repoId`**, `pullRequestNo`. §(c) claims to describe this shape and still omits three of its six
   fields. **Correction (CLO finding 1):** an earlier draft of this section said the shape is
   "mirrored by `SignerRow` at `backfill.ts:10-17`". It is not. `SignerRow` declares `name`, `id`,
   `pullRequestNo`, `comment_id`, `created_at` and optional `signedOnPR` — **no `repoId`**. It is the
   backfill *reader's* view, not the record's shape, and must not be cited as a mirror of it.
2. **R2 evidence record** — `signatures/<sha256-of-payload>.json`, built at `build-record.ts:86-111`,
   schema at `schema.ts:37-56`. Adds `schema_version`, `comment_body`, `comment_body_sha256`,
   `actor.{id,type}`, `pr_of_record.{number,repo}`, `cla_doc.{path,git_sha,content_sha256}`,
   `capture_method`, `workflow_run_id`, and the optional `comment_body_fetch_failed`, `fetch_error`,
   `first_pr_signed_against`.
3. **R2 allowlist-bypass record** — `allowlist/<principal>/<quarter>.json`, shape `BypassRecord` at
   `allowlist-bypass.ts:25-34`: **`schema_version`**, `principal`, `principal_safe`, `db_id`, `quarter`,
   `first_seen_at`, `first_pr`, `allowlist_source`. (`schema_version` was dropped from an earlier draft
   of this list and from Ruling 2's shape (3) — an under-inclusion, in the section whose subject is
   under-inclusion.) Written for any actor on `cla.yml:58`, a list that includes
   `deruelle` — a natural person who signs no CLA and therefore falls outside §(c)'s stated
   categories of data subjects. §(g) already names the `allowlist/` prefix; §(c) names none of it.
4. **R2 tombstone record** — `tombstones/<prior_sha>.deleted.json`, written at
   `gdpr-override.sh:397-408`: `deleted_at`, `admin_actor`, `gdpr_request_ref`, `prior_object_sha`,
   `override_reason`. The residue that survives an Art. 17 erasure, sealed by the same write-once
   floor.

### Limb (iii) — my research reached the right verdict by the wrong route

**Correction (CLO finding 2), recorded rather than quietly rewritten.** This section originally
concluded that limb (iii) fails because the receipt comment is soft-failing. The receipt findings
below are all real and all verified — but **the receipt is not the informing mechanism and never
was**. `.github/workflows/cla.yml`'s `custom-notsigned-prcomment` posts, in-thread and *before*
signing, a link to `docs/legal/individual-cla.md`, whose §0 discloses both copies of the record,
Cloudflare as a US-established processor, the indefinite retention and the erasure route — and the
required sign phrase is an attestation of having read that document. That is a pre-signature,
Art. 13-shaped notice, materially stronger than a post-hoc receipt.

So the limb is **correct in substance and wrong in mechanism** for signers, and fails outright for
the non-signer capture on *necessity* rather than on informing. The receipt findings do not carry the
limb; they are the evidence that the receipt could not have carried it. The advisory's Ruling 3 has
the governing text.

The receipt findings, which remain accurate and are why the receipt cannot be the mechanism —
`.github/workflows/cla-evidence.yml`:

- The receipt step (`:197`) carries `continue-on-error: true`; its own header (`:194-196`) reads
  *"Failure here does NOT block the merge gate; the canonical evidence is the R2 object."* The record
  is written by the earlier step (`:136`) and is not rolled back.
- **The stronger point:** the receipt step's `if:` (`:198-201`) additionally requires
  `github.event.action == 'created'`, while the record-writing step (`:136-140`) fires on `created`,
  `edited` **and** `deleted`. On an edit, `build-record.ts:76-84` writes a fresh second verbatim
  capture and **no receipt is posted at all** — a structural absence, not a soft failure.
- The allowlist-bypass record (`:169`) posts no receipt ever; that step is gated on `issue_comment`.
- The receipt text (`:217`) names the CLA document's git SHA and a retrieval command. It does not
  say the verbatim comment body is retained.

### One question deliberately left UNKNOWN, with the probe prescribed

**There is no signature-text filter anywhere on the capture path.** Neither `cla-evidence.yml`, nor
`build-record.ts`, nor `comment-fetch.ts` compares the fetched body against the required sign phrase
at `cla.yml:69`. The only gate on the write step is `steps.wait_cla.outputs.cla_state == 'success'`.
On its face that means any comment on a PR whose `license/cla` status is green is captured verbatim.

Measured:

- `gh api repos/jikig-ai/soleur/commits/<head-sha>/statuses` for #7793, #7784, #7770 → **no
  `license/cla` status present at all**.
- The three most recent successful `issue_comment` runs of `cla-evidence.yml` (`33796733777`,
  `33752485367`, `33733280897`, all 2026-09-03) each show step *"Build and write evidence record"* =
  **`skipped`**.

Not measured: the bucket itself. `apps/cla-evidence/scripts/inspect-evidence.sh` exists and reads
Doppler `prd_cla`. **The archive's realised contents are UNKNOWN and this plan records them as
UNKNOWN.** A code-path reading is evidence about what the path permits, never about what the archive
holds; the deciding datum is obtainable, so Phase 1 hands the measurement to the PR B issue rather
than reasoning to a verdict here. It was cut from this PR at review — see Phase 1.

**The first draft of Phase 1 prescribed `inspect-evidence.sh --help` and "the script's own listing
verb". Both were fabricated.** The script accepts exactly four modes — `by-pr`, `by-contributor`,
`by-quarter`, `tombstone` — and has **no listing verb at all**; run with no arguments it prints its
usage block to stderr and exits 64 (executed at plan time, output confirmed). **One nuance, since
precision is this plan's whole subject:** `--help` is not a recognised flag, but passing it falls
through the arg-count guard and prints the same usage block, so the observable behaviour is identical.
The fabrication that mattered was the *listing verb*, which exists in no form. Phase 1 now
carries the real invocations. Recorded here rather than quietly corrected, because a prescribed
command that does not exist is the defect class the CLI-verification gate exists to catch, and it
survived the first draft of a plan whose entire subject is records that misdescribe reality.

### The register's own precedent for unbounded free-text

PA-7's bare `None.` is out of step with how this same register treats every other unbounded field:

- `article-30-register.md:74` (PA-2) — "may incidentally contain personal data **and Art. 9
  special-category data the user chooses to upload**".
- `:291` (PA-15) — "None expected. … does not contain Art. 9 disclosure **absent the data subject's
  own posting choice**."
- `:639` (PA-32) — "**None sought; may arrive unsolicited**", plus named controls, a named residual,
  an explicit "X is **not** an Art. 9 special category", and "No Art. 10 data."
- `:658` (**PA-33**, not PA-35 — see the correction below) — same shape, "Reasoned rather than
  denied, in the manner of PA-27."

`knowledge-base/legal/audits/2026-08-counsel-review-7100.md:216` records the house position that
**Art. 9(2)(e) "manifestly made public" is a special-category gateway, not an Art. 6 basis** — the
one argument most likely to be smuggled into the wrong limb here.

### Amendment convention — the register has a vocabulary, not a single label

**Correction (CLO finding 7).** An earlier draft of this section said "§(d) at `:161` and §(e) at
`:242` both record their changes as inline dated `CORRECTION` blocks". Two errors: **`:242` is
PA-12's §(e), not PA-7's**, and PA-7 §(e) carries no `CORRECTION` block at all — it uses
`CORPUS DIVERGENCE` → `DIVERGENCE DISCHARGED` → `OPEN QUESTION`.

`grep -o "\[2026-[0-9-]* [A-Z][A-Z ]*(" knowledge-base/legal/article-30-register.md` returns **nine
distinct labels in use**: `CORRECTION`, `WIDENING`, `NARROWING`, `ADDITION`, `AMENDMENT`, `UPDATE`,
`OPEN QUESTION`, `CORPUS DIVERGENCE`, `DIVERGENCE DISCHARGED`. **The label names the kind of change**
and the block body carries the nuance. A `WIDENING` label already exists, minted at #7100 — so no new
label is needed or permitted here. The advisory's Ruling 4 assigns one per cell.

### CI gates that actually fire on this diff

Verified by walking `.github/workflows/`, `scripts/`, `lefthook.yml` and `.claude/hooks/`. No
workflow carries a `paths:` filter for `knowledge-base/legal/**`; everything that touches it is a
full-scan job.

| Gate | Status | Local command |
|---|---|---|
| `credential-path-guard` (`ci.yml:110-120`) | **Blocking.** Full-scan over `plugins` + `knowledge-base`, so it covers both files | `python3 scripts/lint-credential-path-literals.py` |
| `test` → `legal-doc-consistency.test.ts` | **Blocking.** The only test reading the register. Asserts exactly one distinct `RCS <City>` token across six loaded sites (`:195-241`); does not parse PA-7 | `cd apps/web-platform && npx vitest run --project repo-wide test/legal-doc-consistency.test.ts` |
| `enforce` (`legal-doc-cross-document-gate.yml`) | Required, but `surface_patterns` (`:60-67`) lists DSAR code/migration paths only → `surface_hit=false` → exit 0 | — |
| `validate-vector-config.yml` disclosure-drift | **Does not fire** — triggers are path-filtered to `vector.toml` / `vector.tf` / `infra/*.sh`. When it does fire it `grep -q`s the Better Stack source ID and cluster somewhere in the register; those tokens live outside PA-7 and must not be removed | `awk -F'"' '/^uri = "https:\/\/s[0-9]+\./ {print $2; exit}' apps/web-platform/infra/vector.toml` |
| `lint-infra-no-human-steps.py` | Under `knowledge-base/legal/` it walks **only `runbooks/`** (`:74-80`). Neither target file is in scope — **but `knowledge-base/project/plans` is**, so this plan file itself is scanned | `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` |
| The five `docs/legal/**` mirror / SHA / heading gates | **None engage.** `lint-legal-scope-block-placement.sh:186`, `lint-legal-mirror-drift-baseline.sh:72`, `probe_legal_corpus_truth.py:24-25` and `tc-document-sha-guard` (`ci.yml:363`) all hardcode `docs/legal` / the Eleventy mirror | — |
| `markdown-lint` (lefthook `:18-22`) | Local-only, fires on both files. **Not replicated in CI** | `npx --yes markdownlint-cli <files>` |
| `generate-kb-index` (lefthook `:270-273`) | Local-only. The new audit file must land in `knowledge-base/INDEX.md`. **No CI freshness gate**, so a `--no-verify` commit is silently accepted | `bash scripts/generate-kb-index.sh && git diff --stat knowledge-base/INDEX.md` |
| `scripts/check-pa-22.sh` | Wired into **zero** workflows (accepted residual DEF-2 / #7125). Scopes to PA-22 only, so a PA-7 edit cannot break it | `bash scripts/check-pa-22.sh` |
| `kb-drift-walker.sh` | Nightly, non-blocking. Will flag a broken `](path.md)` link in the new file's `related:` frontmatter | `bash scripts/kb-drift-walker.sh` |

There is **no validator of any kind** on `article-30-register.md` table integrity, PA numbering, or
required cells, and **no frontmatter schema** for `knowledge-base/legal/audits/`. Both are
convention held by precedent only. That absence is already tracked at **#7669** — see the Cut List.

### Research Reconciliation — brief vs. codebase

| Claim | Reality | Plan response |
|---|---|---|
| "six fields the R2 evidence record actually carries" | The evidence record adds more than six; and three further fields (`id`, `comment_id`, `repoId`) are missing from §(c)'s description of the git-branch shape it *does* claim to describe; and two further record shapes exist (bypass, tombstone) | §(c) is rewritten against all four shapes, not patched with a six-item list |
| "the record is still written when the informing step fails" | True, and narrower than the truth: on `edited`/`deleted` and on every bypass write, no receipt is emitted at all | Limb (iii) correction is routed to the CLO with both failure modes on the record |
| Register is generated by `scripts/generate-article-30-register.sh` (implied by a stale learning) | **False for this file.** The script writes `$GIT_ROOT/article-30-register.md` from a template that no longer exists (`knowledge-base/project/specs/archive/20260221-044654-feat-cnil-article-30/` holds only `audit-report.md`), so it exits 1 at its own guard. `git ls-files knowledge-base/legal/article-30-register.md` returns the path; `.gitignore` has no `article-30` entry | The knowledge-base copy is hand-maintained. Direct edit is the correct mechanism, as PR #7622 also concluded |
| Stale learnings describe the Art. 30 register as private / gitignored (`2026-02-21-gdpr-article-30-compliance-audit-pattern.md`, `2026-02-21-private-document-generation-pattern.md`) | Superseded — the register is committed and public in this repository | Not relied upon |

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-03-18-legal-cross-document-audit-review-cycle.md` — legal
  documents carry a cross-reference graph invisible to a section-by-section plan; audit **after** the
  edit, not before. Applied as a post-edit cross-reference sweep, and as the reason PA-7's
  cross-references were enumerated at plan time (`grep -rn "PA-7\b\|Processing Activity 7\b"`).
- `2026-03-20-legal-doc-product-addition-prevention-strategies.md` — anchor structural edits on the
  exact preceding heading, and grep for every term gaining a qualifier before editing.
- `2026-02-21-cookie-free-analytics-legal-update-pattern.md` — a public policy that cites a PA count
  must not diverge from the register. This change adds no PA, so the count is unchanged; the check is
  still prescribed. Related open issue **#5126** already tracks a known undercount.
- `2026-03-03-fix-release-notes-pr-extraction.md` — source PR content via `gh pr view N --json body`
  rather than parsing commit messages. Applied: the #7622 body is already captured.

### Related issues and PRs

- **#7625** — the work target (open).
- **#7622** / commit `28612e8cd` — the PA-7 R2-evidence-layer amendment whose CLO review needs a
  record. Its body carries the review narrative verbatim, including the nine applied findings.
- **#7601** — the issue #7622 closed.
- **#7624** — the published-corpus reconciliation, **closed 2026-08-27**; its audit record is the
  house-style sibling. Not pending work.
- **#7597** — a **merged PR** ("fix(ci): cla-evidence calls bun after its setup was removed"), not an
  issue about an admin bypass. The audit record it produced,
  `2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md`, is the closest topical sibling in
  `audits/` and the shape precedent for a retrospective ruling record. [Gloss corrected at plan
  review.]
- **Adjacent and explicitly out of scope:** #7668 (retention proportionality), #7670
  (importer-identity vs byte-location), #7669 (register-to-corpus sentinels), #7671 (LUKS-header
  bucket absent from the register).

### Property List (Phase 0.6b)

- **P1** — PA-7 §(c) describes every category of personal data the activity actually processes,
  across every record shape it writes.
- **P2** — PA-7's Special-categories cell states a determination that was made against `comment_body`,
  with the reasoning recorded and retrievable.
- **P3** — PA-7's Art. 6(1)(f) balancing limb (iii) claims only what the informing mechanism
  delivers.
- **P4** — The CLO review of the #7622 PA-7 amendment has a durable record in
  `knowledge-base/legal/audits/`, discoverable by the same convention as its siblings.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | What already covers it |
|---|---|---|
| A CI sentinel binding §(c) to `schema.ts` so a field added to the evidence record reddens the register | Drift detection on P1 | **#7669** already owns this exact capability ("bind Art. 30 register cells to the corpus anchors they govern — the sentinels cannot see a register amendment"). Inventing a second one here would duplicate an open, scoped issue. Cut. |
| A new frontmatter validator for `knowledge-base/legal/audits/` | Consistency on P4 | Nothing validates it today and nothing needs to: the convention is held by precedent, and the two sibling records (`2026-08-20-clo-review-7624-…`, `2026-08-counsel-review-7440.md`) are the template. Adding a validator is a guard this ask never requested and would pull Phase 2.12 into a docs PR. Cut. |
| A re-run of `scripts/generate-article-30-register.sh` to regenerate the register | Consistency on P1 | The script cannot run (its template is deleted) and writes to a different path. Cut — direct edit is the mechanism. |

### Value-proposition measurement (Phase 0.6c)

Not applicable — the justification is record accuracy under Art. 30(1), not a cost or performance
saving. No mechanism in this plan survives on an unquantified efficiency claim.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200` returned 63 issues. Matching each
against every path in `## Files to Edit` / `## Files to Create` below
(`knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/audits/`,
`knowledge-base/INDEX.md`) via `jq --arg path … | contains($path)` returned **None**.

Four adjacent legal issues are open but are not `code-review`-labelled and touch none of these paths
as a scope-out. Disposition for each:

- **#7669** (bind register cells to corpus anchors — a CI sentinel) — **Acknowledge.** It owns the
  drift-detection capability this plan deliberately does not build; see the Cut List. Left open.
- **#7668** (proportionality of indefinite retention, PA-7 §(f)) — **Acknowledge.** A controller
  decision about the processing itself, not a documentation question. This plan touches §(f) not at
  all. Left open.
- **#7670** (importer-identity vs byte-location transfer test) — **Acknowledge.** Scoped to §(e),
  which this plan does not edit. Left open.
- **#7671** (LUKS-header R2 bucket absent from the register) — **Acknowledge.** A different bucket
  and a different activity. Left open.

## User-Brand Impact

**If this lands broken, the user experiences:** a data subject of PA-7 reads
`knowledge-base/legal/article-30-register.md` §(c) and is told a narrower set of their data is held
than is actually held. **Four populations, not one** — the first draft of this section named only the
first, which is the brief's population rather than the one Ruling 2 establishes:

1. A **CLA signer**. Two are named in the public `cla-signatures` branch today (`deruelle`,
   `Elvalio`).
2. **Any GitHub account that commented on a pull request** whose `license/cla` status was green.
   They signed nothing, agreed to nothing, and are captured verbatim by the predicate at
   `.github/workflows/cla-evidence.yml:136-140`.
3. A **natural person on the CLA-action allowlist** (`deruelle`), the subject of `allowlist/` bypass
   records without ever signing.
4. The **operator recorded as `admin_actor`** in an erasure tombstone, and any data subject
   identified by that tombstone's `gdpr_request_ref`.

**Population 2 is the sharpest case in the whole plan and it is the one the first draft omitted.** A
stranger with no relationship to Jikigai, whose verbatim text sits behind a write-once floor under
indefinite retention, whom no published document tells anything, and — per the review — for whom
`docs/legal/privacy-policy.md` §8.1 carries carve-outs for two other accountless populations and none
for this one.

If §(c) is widened but the Special-categories cell is left asserting `None.` over a field nobody
analysed, the register carries a positive Art. 9 statement made on an incomplete record. Either way
the artefact a supervisory authority would request under Art. 58(1)(a) misdescribes the processing.

**If this leaks, the user's data is exposed via:** nothing new — this change publishes no data and
opens no path. The exposure this change *describes* already exists: `comment_body` is a verbatim
capture of free text the data subject authored, held under §(f) **Indefinite** retention behind a
10-year write-once floor, erasable only through the `gdpr-override.sh` admin path that §(g) itself
calls not absolute. The risk this plan carries is that the record understates that, not that it
creates it.

**Brand-survival threshold:** `single-user incident`. One signer, reading one cell, is the whole
failure mode — matching `2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md`, which set
the same threshold over the same processing activity.

Consequences of the threshold, per the gate: `requires_cpo_signoff: true` in frontmatter;
`user-impact-reviewer` is invoked at review time; and the CLO consult is obtained at plan time rather
than deferred, which is what the Domain Review section below records.

## Architecture Decision (ADR/C4)

**No ADR.** This plan makes no architectural decision: it changes no data model, no ownership or
tenancy boundary, no substrate, no resolver or trust boundary, and reverses no existing ADR. It
corrects a record *about* an unchanged system. A competent engineer reading the existing ADR corpus
would not be misled about the system after this ships.

**No C4 impact — and here is the enumeration it is asserted from.** All three model files were read
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`), not grepped for the
feature's own noun:

- **External human actors** for PA-7: the CLA signer. Already modelled as
  `contributor = actor "Contributor / PR Author"` with `#external` (`model.c4:35-36`), and included
  in both the `context` and `containers` views (`views.c4:12,31`).
- **External systems** for PA-7: **GitHub** — modelled, `github = system "GitHub" #external`
  (`model.c4:234-235`). **Cloudflare** — modelled, `cloudflare = system "Cloudflare" #external`
  (`model.c4:248-250`), described as "DNS, CDN, R2 storage, zero-trust tunnel". **FreeTSA** — **not
  modelled**, and the register expressly records it as *not* a recipient (`article-30-register.md:161`).
- **Containers / data stores touched:** none. This plan edits no runtime surface.
- **Actor↔surface access relationships that change:** none.

Two pre-existing C4 gaps were observed while performing this enumeration and are **not** created by
this change: FreeTSA has no element, and the `soleur-cla-evidence` R2 edge has no relationship,
though the sibling `soleur-workspaces-luks-header` bucket does appear in a relationship description
at `model.c4:507`. Per `wg-when-an-audit-identifies-pre-existing`, one tracking issue covering both
is filed at ship time — they are the same class (the CLA-evidence layer's external edges are
unmodelled), and neither belongs in this PR.

## Files to Edit

- `knowledge-base/legal/article-30-register.md` — PA-7 only. **Five rows: four amended and one new.**
  Amended: **(c) Categories of data subjects**, **(c) Categories of personal data**,
  **Special categories** (whose row label is also harmonised to **Special categories (Art. 9 / 10)** —
  the form 24 of the register's 31 Special-categories rows already use), and **Lawful basis**. New:
  **(h) DSAR (Art. 15 / 20)**, which PA-7 lacks and which PA-32 and PA-33 both carry for the same
  reason PA-7 now needs one. Cells explicitly **not** in scope: (b), (d), (e), (f), (g). PA-7's §(e)
  `OPEN QUESTION` block stands untouched.
- `knowledge-base/legal/compliance-posture.md` — **four new Active Items rows**, one per Critical
  finding in the addendum's A5 table, each keyed to its own `compliance/critical` issue. Per Ruling 6
  these are *additions*; the existing lines 20 and 44 are **not** edited, because neither is a PA-7
  Art. 9 statement (line 20 is the #5363 entry scoped to PA-2 `turn_summary`; line 44 is the #3988
  entry recording that AUP §§4.7/4.8 were added, which remains an accurate historical record). The
  `last_updated` frontmatter date is bumped, as `compliance-posture.md:190` requires.

  *An earlier draft of this list said "four cells" and "one new Active Items row only". Both were
  left behind by the review revisions that made them five and four — the class of stale
  cross-reference a post-edit sweep exists to catch, found in the plan's own Files list.*
- `knowledge-base/INDEX.md` and `knowledge-base/kb-tags.txt` — regenerated, not hand-edited
  (`bash scripts/generate-kb-index.sh` writes both).

## Files to Create

- `knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md` — deliverable 2.
  The retrospective record of the CLO review of PR #7622 / commit `28612e8cd`. Naming follows the
  newer `<YYYY-MM-DD>-clo-review-<issue>-<slug>.md` precedent set by its 2026-08-20 sibling.
- `knowledge-base/legal/audits/2026-09-counsel-review-7625.md` — the attestation for **this** PR.
  Carries the plan-time CLO advisory (the Art. 9 determination, the §(c) rewrite and the limb (iii)
  correction, with reasoning) and is re-attested against the diff as landed at ship time.

  **This file is not optional and not scope growth.** `/ship` Phase 5.5's Counsel-Review
  CLO-Attestation Gate (`plugins/soleur/skills/ship/SKILL.md:817-847`) fires when
  `git diff main...HEAD --name-only` matches `^knowledge-base/legal/` **and** the plan declares
  `brand_survival_threshold: single-user incident`. Both hold. Producing it at plan time rather than
  discovering it at ship time is the whole point of running the CLO consult in Phase 2.5.

  **The filename is convention, not contract — an earlier draft of this plan overstated it.** The
  gate's prose names `<YYYY-MM>-counsel-review-<issue>.md` as house style, but #7624 had identical
  trigger conditions and discharged the same gate with a single file named
  `2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md`. There is **no**
  `2026-08-counsel-review-7624.md` on `main` (verified). The `counsel-review` name is used here
  because it is the gate's stated form and costs nothing, not because the gate would reject the other.

**Both new files are separate deliverables and neither subsumes the other.** One records a review that
happened on 2026-08-20 about someone else's PR; the other is this PR's own attestation. Deliverable 2
carries no issue of its own, which the split discipline applied to PR B would otherwise argue against
— the reason it rides along is that it is a *missing record of work already done*, not new work: no
CI class changes, no third party is affected, and filing an issue to write a file that this PR is
already touching the directory for would be ceremony. Stated rather than left as an inconsistency a
reader has to notice.

## Implementation Phases

> **Two things called "Phase 4" appear below and they are unrelated.** This plan's **Phase 4** writes
> the #7622 CLO review record. **`Phase 4: Validate + Scale`** in backticks is the GitHub *milestone*
> (number 4) that two of the Phase 2 filings are assigned to. Likewise `Phase 5.5` and `Phase 2.5` in
> running text refer to the `/ship` and `/soleur:plan` skills' own phases, never to this list.
>
> **The order below is dependency order, not narrative order.** The filings phase runs second because
> two register cells and a `compliance-posture.md` row all cite issue numbers it mints. An earlier
> draft had it fifth; the same read-before-write inversion was caught twice in one review pass.

### Phase 0 — Transcribe the binding advisory, before touching the register

The CLO advisory in `## CLO Advisory — Binding Rulings` below is the governing text for every §(c),
Special-categories and lawful-basis edit in this PR. Write it into
`knowledge-base/legal/audits/2026-09-counsel-review-7625.md` **verbatim** first, with the frontmatter
shape taken from `knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md:1-29` (`type`, `issue`,
`pr`, `attestation-authority`, `status`, `disposition`, `tier_classification`, `semver`,
`brand_survival_threshold`, `written_against`, `scope_boundary`, `re_evaluation_triggers`,
`related`). Planning is confined to `knowledge-base/project/{plans,specs}/`, so the audit file is a
`/work` deliverable, not a plan artefact — the same split the 2026-08-20 sibling records at its
`:46-49`.

Where this section and any other section of the plan disagree, **the advisory governs**.

### Phase 1 — Record the archive as UNMEASURED, and hand the measurement to PR B

**Cut at plan review, deliberately.** The first draft of this phase read the live R2 archive under
Doppler `prd_cla` to count objects and inspect `comment_body` values. Two reviewers converged on the
same objection and it is correct: the measurement buys **no property in the Property List**. Ruling 1
states three times that the register text is correct on both arms and that the edit is not gated on
the reading; Ruling 5 forbids this PR to answer the only question the measurement decides (whether an
incident occurred, and whether Art. 14 notice is owed). So the phase was a live production-credential
read, inside a documentation-only PR, whose entire output was a number in a `written_against:` line
that no decision consumed. It also quietly contradicted the Acceptance Criteria preamble's claim that
every criterion is a local command.

What this phase does instead:

1. Write `written_against:` in `2026-09-counsel-review-7625.md` recording the archive's realised
   contents as **UNMEASURED**, with the reason: the capture predicate is a code fact established from
   `.github/workflows/cla-evidence.yml` and `.github/workflows/cla.yml`, and the register records what
   the controller processes rather than what the bucket happens to hold.
2. Carry the measurement into the **PR B issue** (Phase 2 item 1) as a stated prerequisite of drafting
   §3.4, not of this PR. That is where it is load-bearing: per the CTO advisory, if records exist that
   are not sign comments, then disclosing a *closed historic window* while still **holding** the
   artefacts is a worse thing to write than disclosing an open practice you are visibly fixing. So
   PR B's sequencing must be contingent on the measurement, and PR A's must not.

The measurement recipe carried into that issue, **rewritten at review because the first version could
not answer its own question.** `inspect-evidence.sh` has **no listing verb**,
accepts exactly four modes, and with no arguments prints its usage and exits 64. The four Doppler keys
it reads — `R2_CLA_EVIDENCE_ACCESS_KEY_ID`, `R2_CLA_EVIDENCE_SECRET`, `R2_CLA_EVIDENCE_ENDPOINT`,
`R2_CLA_EVIDENCE_BUCKET` — are named identically in `prd_cla`, as
`.github/workflows/cla-evidence.yml:71-74` confirms.

**`by-contributor` cannot detect over-capture, and the first draft prescribed exactly that.**
`inspect-evidence.sh:150-161` lists `signatures/`, fetches each object, and emits it **only if
`.actor.login == $login`**. The two logins available are the two known *signers*. An over-captured
record is by definition authored by someone who is not a signer, carries a different `.actor.login`,
and is filtered out by both invocations — so the command returns sign-comment bodies and nothing
else, on both arms of the world. A structurally vacuous measurement, and the same defect class this
plan already caught once in the fabricated `--help`.

The question needs the raw path, under the same injected environment, with the pagination
`list_keys()` performs at `inspect-evidence.sh:56-77` — a single `list-objects-v2` caps at 1000 keys:

```bash
doppler run -p soleur -c prd_cla -- bash -c '
  set -uo pipefail
  export AWS_ACCESS_KEY_ID="$R2_CLA_EVIDENCE_ACCESS_KEY_ID" \
         AWS_SECRET_ACCESS_KEY="$R2_CLA_EVIDENCE_SECRET" AWS_REGION=auto
  tok=""; n=0
  while :; do
    page=$(aws --endpoint-url "$R2_CLA_EVIDENCE_ENDPOINT" s3api list-objects-v2 \
             --bucket "$R2_CLA_EVIDENCE_BUCKET" --prefix signatures/ --output json \
             ${tok:+--starting-token "$tok"}) || { echo "READ FAILED" >&2; exit 9; }
    for k in $(jq -r ".Contents[]?.Key // empty" <<<"$page"); do
      aws --endpoint-url "$R2_CLA_EVIDENCE_ENDPOINT" s3 cp "s3://$R2_CLA_EVIDENCE_BUCKET/$k" - \
        | jq -r "[\"$k\", .actor.login, .capture_method, (.comment_body // \"<null>\")] | @tsv"
      n=$((n+1))
    done
    tok=$(jq -r ".NextContinuationToken // empty" <<<"$page"); [ -z "$tok" ] && break
  done
  echo "signatures/ objects: $n" >&2'
```

Then compare each emitted body against the phrase at `.github/workflows/cla.yml:69`. Keep
`by-contributor deruelle` / `by-contributor Elvalio` only as the signer-side cross-check they actually
are, and `by-quarter 2026-q3` only if a non-empty result would change something — it does not feed the
§(c) allowlist limb, which is derived from `cla.yml:58` rather than from the bucket.

**Three arms, not two, and a zero is not a measurement.** `list_keys()` swallows every `aws` failure
with `|| break`, so a read-refused token yields empty output that is indistinguishable from an empty
archive — and the `prd_cla` credentials are provisioned for the *write* path, while the retrieval
runbook §3 mints a separate ad-hoc read token. At least two signature records must exist if the path
ever fired, so **treat `signatures/` = 0 as UNMEASURED-suspect, never as measured-empty.** Record
which of the three happened: *measured*, *read-refused*, or *credentials-absent*. A non-zero
`tombstones/` count is separately material — it would mean an erasure has already run, an
`override_reason` exists, and Ruling 1's second Art. 9 surface is realised rather than hypothetical.

### Phase 2 — File what the advisory split out

Ruling 5 hands back work this PR must not do but must not lose either. Each becomes a GitHub issue,
filed in this session — a deferral without a tracking issue is invisible
(`wg-when-deferring-a-capability-create-a`).

**Labels, verified present at plan time** via `gh label list --limit 200`: `compliance/critical`,
`domain/legal`, `domain/engineering`, `type/security`, `action-required`, `chore`, `documentation`,
`deferred-scope-out`, `priority/p2-medium`, `priority/p3-low`. All ten exist — no `gh label create`
step is owed. Do not introduce a label outside this verified set without re-running the listing.

**Milestones are as load-bearing as labels here.** `#7625` itself sits in `Post-MVP / Later`, so every
child inherits that bucket by default — and a split whose other half lands in an undated backlog is a
deferral wearing a split's clothes. `gh api repos/jikig-ai/soleur/milestones` confirms
**`Phase 4: Validate + Scale`** exists (number 4). Items 1 and 2 below go there; items 3 and 4 go to
`Post-MVP / Later`. The precedent is roadmap row 4.12 / #7331, which established that a legal
precondition of onboarding is a phase row rather than backlog: *"Before tester #2 is onboarded — the
determination is a **precondition** of the next onboarding, not a reaction to it."* Phase 4's
objective is recruiting external founders into a **public** repository, and under the current capture
predicate every one of them who comments on a pull request becomes a PA-7 data subject.

**1. PR B — the published-corpus transparency *and rights* gap.** All three documents frame the
archive as processing "CLA signature data when contributors sign"; the code captures commenters who
sign nothing, and no published document tells such a person anything.

Sections, **wider than Ruling 5(B) first scoped them** — review found two more, and the second is the
operative one:

- `docs/legal/gdpr-policy.md` §3.4, `docs/legal/privacy-policy.md` §4.5,
  `docs/legal/data-protection-disclosure.md` §2.3(n) — the collection disclosures Ruling 5(B) named.
- **`docs/legal/privacy-policy.md` §5.11 and `data-protection-disclosure.md` §2.3(n)** additionally
  state that bypass records cover "allowlisted **bot accounts** (`dependabot[bot]`, `renovate[bot]`,
  `claude[bot]`)". `.github/workflows/cla.yml:58` lists six principals including `deruelle`, a natural
  person, and `soleur-ai[bot]`, which the sentence does not enumerate. PR A's own Ruling 2 establishes
  that those records are personal data of an identified individual, so PR B must not leave this
  standing.
- **`docs/legal/privacy-policy.md` §8.1 — the section that actually confers a route, and the half
  without which PR B fixes nothing for the affected person.** It carries named carve-outs for two
  other accountless populations (the community-digest subject, the departed workspace member) and
  **none for the CLA archive**. A non-signer commenter cannot use `/dashboard/settings/privacy`
  (the data is in R2, not a Supabase table), is not addressed by §4.5 (signature-framed), and never
  sees CLA §0. Draft the carve-out on the community-digest precedent.

**All three claims were verified verbatim at plan review, not paraphrased:**

- `docs/legal/privacy-policy.md:383` (§5.11): *"allowlisted **bot accounts** (`dependabot[bot]`,
  `renovate[bot]`, `claude[bot]`) are also recorded; the upstream CLA action filters
  `github-actions[bot]` (DB-id 41898282) before any record is written"*.
- `docs/legal/data-protection-disclosure.md:172` (§2.3(n)): the same enumeration, *"recorded once per
  principal per quarter"*.
- Both omit `deruelle` — a natural person — and `soleur-ai[bot]`, against the six principals at
  `.github/workflows/cla.yml:58`.
- `docs/legal/privacy-policy.md` §8.1 carries carve-outs for **community digests**, **departed
  workspace members** and **LinkedIn-published content**, and mentions the CLA **zero times**
  (`grep -ci "CLA\b"` over the §8.1 body returns `0`).

Plus the three Eleventy mirrors under `plugins/soleur/docs/pages/legal/` and a `legal-doc-shas.ts`
re-pin. **`EXPECTED_COUNT` does not move** — `apps/web-platform/scripts/check-tc-document-sha.sh:47`
sets it to the number of canonical documents (9), and PR B edits three existing documents without
adding one. It was in an earlier draft of this list and is removed.

- Milestone `Phase 4: Validate + Scale`; labels `domain/legal`, `priority/p1-high` if it exists in the
  verified set at filing time, otherwise `priority/p2-medium`.
- Trigger, stated in the body: **before tester #2 comments on a pull request in this repository.**
- Record that this **does not depend on measuring the bucket** — it follows from the workflow `if:`
  conditions alone — and that `TC_VERSION` is unaffected because no T&C body changes.
- Carry Phase 1's measurement commands into this issue as a **prerequisite of drafting §3.4**, with
  the reason: if records exist that are not sign comments, disclosing a closed historic window while
  still holding the artefacts is worse than disclosing an open practice being visibly fixed.
- Mark it **blocked by item 2** — filing order does not bind execution order, so the dependency has to
  be in the body or the sequencing this whole argument rests on lives only in this plan's prose.

**2. Close the cla-evidence capture-predicate gap** — one engineering issue, not two. Milestone
`Phase 4: Validate + Scale`; labels `type/security`, `domain/engineering`.

**Frame it as spec-implementation drift against an approved design, not as an open question.** The
sign-phrase gate was specified and never built:
`knowledge-base/project/plans/2026-05-04-feat-cla-legal-rigor-evidence-layer-plan.md:151` step 3(c)
reads *"On `issue_comment.created` with sign-phrase + accepted by action: continue."* The
implementation shipped only the second conjunct.

**Verified — and the first draft of this sentence miscounted its own grep.** It claimed
`grep -rn "hereby sign" apps/ .github/` returns three hits all in `.github/workflows/cla.yml`. The
command actually returns **eight**: three in `cla.yml` (`:4` a comment, `:66` the instruction body,
`:69` the `custom-pr-sign-comment` value) and **five test fixtures** under
`apps/web-platform/test/cla-evidence/{backfill,comment-fetch,schema,hash}.test.ts`. The draft had
filtered `\.test\.` out of the output and then described the result as though unfiltered — the ninth
instance in this plan of paraphrasing a derived view as if it were the source.

The substantive claim survives and is **stronger** stated correctly:
`grep -rn "hereby sign" apps/ | grep -v '\.test\.'` returns **zero**. The phrase exists in the repo
only as upstream configuration and as test data. **No production code path compares a comment body to
it.** The design decided this in May 2026; the code drifted from it. A ticket that reopens it as
a design question invites a re-litigation that already concluded.

Scope, per the CTO advisory, with the traps that make it a day rather than a one-liner:

- Gate on `github.event.comment.body` from the **event payload**, never on the fetched body — the
  fetch 404s on `deleted`, so a fetch-side gate would silently delete the `deleted` arm and regress
  the spec-flow gap `cla-evidence.yml:22-27` exists for.
- The `edited` arm needs a two-sided predicate over the new body **and** `changes.body.from`; a signer
  editing the phrase out is exactly what `build-record.ts:76-84` captures.
- Mirror the pinned upstream action's matching semantics rather than assuming equality. Stricter than
  upstream means `license/cla` goes green, the sidecar writes nothing, and the archive develops a
  hole. Over-capture is a privacy defect; under-capture is an evidentiary one, and this archive exists
  for the second.
- Record no gate decision in the record itself. `EvidenceRecordSchema` is non-strict, so an undeclared
  field is silently stripped; declaring one properly bumps `SCHEMA_VERSION`, which three read-side
  consumers assert. Gate only, no schema change — which also leaves the content-addressed key and the
  `If-None-Match` dedup untouched.
- Fold in the `override_reason` work, which is the same class on the same path: an enum rather than
  free text, narrative routed to the DPA log the retrieval runbook §7.5 already maintains, plus the
  help-text drift at `gdpr-override.sh:73` (it promises `>=10 chars`; nothing validates length —
  verified) and both runbook sites at `cla-signature-evidence-retrieval.md:206` and `:320`.
- Add a sign-comment mode to `apps/cla-evidence/scripts/sentinel-pr.sh`. It posts only on close today,
  so it exercises the bypass path and never the phrase path — without it the changed path ships with
  no live detector, and its failure mode is indistinguishable from the current steady state, where the
  write step is already `skipped` on nearly every run.

**Correct the advisory's own re-evaluation trigger text when filing.** It says this fix "would retire
the non-signer arm of the Lawful basis cell, narrow the Categories of data subjects cell". That is too
strong: the `allowlist/` bypass arm at `cla-evidence.yml:169` is untouched by the gate and keeps
processing non-signers, `deruelle` among them. If PR B is drafted on the premise that the whole
non-signer category becomes historic, it will be wrong again in the same direction as today.

**3. The over-broad AUP §4.7 citation — FOUR sites, and none is PA-35.** **This item carried a
"Verified at plan review" badge on a false count, and the badge is the worse half: a wrong claim
marked verified is more dangerous than an unmarked one.** The four sites are PA-17's
Special-categories cell, **PA-17's Art. 6(1)(f) balancing limb**, PA-31's Special-categories cell,
and PA-33's Special-categories cell — each citing §4.7 as prohibiting Art. 9/10 content "in
repository submissions" when §4.7 is scoped by its own heading and opening sentence to the hosted
chat surface. An earlier draft attributed this to PA-35, whose Special-categories cell reads a bare
`None identified.` and cites nothing.

**Why the plan-review grep undercounted, twice over.** `grep -n "repository submissions"` returns
**three** hits on `main` — `:313` (PA-17), `:620` (PA-31), `:658` (PA-33) — not the two recorded
here; PA-31 was simply missed while reading the output. And the fourth site cannot be found by that
phrase at all: PA-17's balancing limb spells it as a parenthetical naming § 4.7 beside the
render-time `redactGithubSourcedText` minimisation, so a phrase-anchored sweep is structurally blind to
it. Sweep the CLAIM, not one of its phrasings. Retained rather than silently repaired, and
`awk 'NR<=658 && /^## Processing Activity /{last=NR": "$0} END{print last}'` returns `649: ## Processing Activity 33`. Milestone `Post-MVP / Later`; labels `domain/legal`,
**`compliance/critical`**. That label is not decorative — Phase 5's `compliance-posture.md` row keys
on this issue number, and `/ship` Phase 5.5's gdpr-gate acknowledgment gate verifies every
PR-referenced `compliance/critical` issue has a row there before merge.

> **Line numbers in this section are `origin/main` coordinates and this PR's own `(h)` insertion
> shifted everything below register line 165 by one. Cite these cells by activity and row label, not
> by number — the four AUP § 4.7 sites are PA-17's Special-categories cell and its Art. 6(1)(f)
> balancing limb, PA-31's Special-categories cell, and PA-33's Special-categories cell.**

**3b. The six remaining bare `**Special categories**` row labels** — PA-3, PA-4, PA-5, PA-6, PA-8 and
PA-9, which alone in the register lack the `(Art. 9 / 10)` suffix that the other 24 rows carry.
Measured at plan review: 31 rows total, 24 suffixed, 7 bare, and PA-7 is the seventh. Sweeping them
here would breach Phase 3's "only PA-7's rows" constraint and fail AC9, so they are filed as one
mechanical pass. Milestone `Post-MVP / Later`; labels `domain/legal`, `chore`. **Note for #7669:**
until this lands the register has two spellings and any sentinel must accept both.

**4. The two C4 gaps** enumerated in `## Architecture Decision (ADR/C4)` — FreeTSA has no element and
the `soleur-cla-evidence` R2 edge has no relationship. One issue covering both; they are the same
class. Milestone `Post-MVP / Later`; labels `domain/engineering`, `chore`. Filed under
`wg-when-an-audit-identifies-pre-existing`, and deliberately **not** gated by AC19's filed-and-dated
clause — a reviewer called
this one audit-generates-audit-work, and that is a fair charge against gating a merge on it, though
not against recording it.

**5. The four `compliance/critical` findings**, one issue per Active Items row in the addendum's A5
table: (i) the non-signer capture has no available Art. 6 basis; (ii) `comment_body` Art. 9 ingress
with neither a technical nor an organisational control; (iii) the published corpus does not disclose
the non-signer population and offers it no Art. 21(1) route; (iv) the tombstone `override_reason`
free-text Art. 9 surface. Labels `compliance/critical` + `domain/legal`. **Phase 5's
`compliance-posture.md` rows key on these four numbers**, and `/ship` Phase 5.5's gdpr-gate
acknowledgment gate verifies every PR-referenced `compliance/critical` issue has a row — so these must
exist before Phase 5 runs. Issue (iii) may be the same issue as item 1 (PR B) if the authority's row
and the PR B tracking reference are the same thing; decide once and use one number consistently in
both the row and the `CORPUS DIVERGENCE` block.

**6. The register's ten pre-existing markdownlint errors** — `MD034` at `:26`, `:274`, `:278`,
`:294`, `:686`, `:707`; `MD050` at `:179` (×2); `MD038` at `:432`; `MD055` at `:660`. All outside
PA-7, all pre-existing, and collectively the reason the register cannot be staged through lefthook
without a decision. Milestone `Post-MVP / Later`; labels `chore`, `documentation`. See the note under
AC14.

None of these blocks this PR. **PR A records today's position today.** But note the ordering the
reviewers converged on and which the first draft of this plan had backwards: **PR B outranks PR A in
urgency.** PR A corrects an internal register a supervisory authority would have to ask for; PR B
corrects a public notice that is wrong about who it applies to. PR A ships first because it is cheap
and unblocked, not because it matters more.

### Phase 3 — Amend PA-7

Apply the advisory's exact cell text to `knowledge-base/legal/article-30-register.md`. Anchor each
edit on its own row's `| **<cell name>** |` prefix, not on a line number — line numbers in this file
move under every sibling amendment. Four rows change, and each takes the amendment label Ruling 4
assigns it:

| Row | New text | Amendment label |
|---|---|---|
| `**(c) Categories of data subjects**` | Ruling 2, second code block | `WIDENING` |
| `**(c) Categories of personal data**` | Ruling 2, first code block | `WIDENING` |
| `**Special categories**` → relabelled `**Special categories (Art. 9 / 10)**` | Ruling 1 code block | `CORRECTION` |
| `**Lawful basis**` | Ruling 3 code block, with the A1 corrected limb-(iii) tail | `CORRECTION` |
| `**(c) Categories of data subjects**` (second block) | Addendum A3 | `CORPUS DIVERGENCE` |
| `**(h) DSAR (Art. 15 / 20)**` — **a new row** | Addendum A4 | none — it states no prior position |

The amendment block goes at the end of the cell **content, before the row's terminating `|`** —
following PA-7's own local style at `:161`, and closing `…convention.]**`. Stated explicitly because
Ruling 1's replacement text already ends `… on this path. |`: concatenating naively produces
`… on this path. | **[2026-09-03 CORRECTION …]** |`, a three-pipe row that fails AC2.

**Do not mint a new label.** The register's vocabulary already covers every case here, and #7669
would have to learn any label added. (The count is ten distinct strings, nine of them kind-labels —
see the correction in `## Research Insights`.) **All five blocks are now supplied verbatim**: Ruling 4
gave three, and the fourth and fifth were **sent back to the reviewing authority rather than drafted
here** — see `## CLO Advisory — Addendum after plan review`. Having `/work` author governing legal
text mid-implementation is exactly what obtaining the advisory at plan time exists to prevent.

**This is why the filings phase now runs first.** **Three** PA-7 cells cite numbers this phase mints —
the `CORPUS DIVERGENCE` block and the `(h)` cell both cite the PR B issue (#7812), and the
Special-categories cell cites the AUP § 4.7 issue (#7815) in its sibling-comparison sentence. All
three must exist before those cells can be written. (An earlier draft said "two cells" and missed
the #7815 dependency — which was the least safe one to leave uncounted, since that issue's scope was
still being argued at A7.1.) An
earlier draft had the amendment at Phase 2 and the filings at Phase 4 — the same read-before-write
inversion review caught in the `compliance-posture.md` row, found twice in one plan.

**Carry the dormancy observation into the §(c) capture-predicate sentence and into the attestation's
`written_against:`.** The replacement Lawful-basis cell states, in the present tense, that a fraction
of the processing has no available Art. 6 basis — which an auditor reads as a live admission. This
plan's own measurement is the strongest mitigating datum available and currently ships nowhere: as of
2026-09-03 the write step was observed `skipped` on the three most recent successful `issue_comment`
runs, and no `license/cla` status was present on three sampled pull requests. The predicate is a
property of the path, not an observation of current firing, and both halves of that sentence belong in
the record. Recording only the first would overstate; recording only the second would understate.

Constraints for this phase:

- Touch **only** PA-7's rows. Every other Processing Activity is out of scope.
- Every edited row must still parse as a 2-column Markdown table row (`| … | … |`). Nothing in CI
  checks this — verify it by eye and by the row-count assertion in the Acceptance Criteria.
- Do not remove the Better Stack source-ID or cluster tokens from anywhere in the register; the
  `validate-vector-config.yml` parity step `grep -q`s for them, and although it does not fire on this
  diff it will fire on the next `vector.toml` change.

### Phase 4 — Write the #7622 CLO review record

Create `knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md`, sourced
from the merged PR's own review narrative rather than re-derived:

```bash
gh pr view 7622 --json body --jq .body
```

Its `## CLO review` section carries the disposition (**APPROVE-WITH-CHANGES**, discharged to
**APPROVED**), the two upheld departures from #7601's stated scope, and the nine applied findings.
The nine, grouped as the source groups them:

**§(g)** — (1) the RFC 3161 pre-image is a manifest of `{key, etag, size, last_modified}` rather than
the archive bytes, and the true statement is *stronger*, since each signature key **is** the SHA-256
of its own record, so timestamping the manifest binds every record's content; (2) conditional PUT
covers the content-addressed `signatures/` path, not only the per-quarter key; (3) the absolute WORM
claim contradicted §(f)'s erasure commitment and was retracted — `gdpr-override.sh` is a documented
Art. 17 path and is itself a TOM.

**§(d)** — (4) the meta-reasoning was cut, because house style records facts, not arguments; (5) the
sentence that actually discharges the correction was added, namely that Cloudflare was contractually
covered throughout the omission window, so an Art. 30 record-keeping incompleteness is not an
Art. 4(12) breach and triggers no Art. 33/34 duty; (6) the FreeTSA non-recipient determination was
hardened onto aggregate-manifest reasoning rather than "a digest is not personal data"; (7) the
runner-egress-IP hole was closed.

**§(e)** — (8) the cell never named the third country, which Art. 30(1)(e) requires; the transfer
arises from the **importer's identity** rather than the location of the bytes (EDPB Guidelines
05/2021, criterion 3), after which the placement-hint point does its proper, narrower job; (9) the
re-evaluation trigger was overstated — the EU jurisdiction tier would not, on its own, convert the
cell to a no-transfer posture.

Also record, because the source records them: the reviewing authority verified every factual claim
against source before publishing it (`gdpr-override.sh`, `r2-conditional-put.sh` and its
`If-None-Match` callers, `manifest.jsonl`, the bucket-wide `prefix: ""`); and the review produced two
consequential filings rather than deferrals — #7624 (could not be folded in: it moves ten statements
across `docs/legal/**` and four Eleventy mirrors, a different change class) and #7625 (directed **do
not bundle**, because the Art. 9 consequence needs its own analysis).

**House style records facts, not arguments — keep the meta-reasoning out.** Frontmatter shape from
`2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md:1-25`, with `pr: 7622`, `attested_commits: 28612e8cd`,
`written_against:` naming the register at that commit, and `date: 2026-09-03` — this record is
written on 2026-09-03 *about* a 2026-08-20 review, and the frontmatter must not imply it was written
contemporaneously.

### Phase 5 — Cross-reference sweep, the compliance-posture row, and the index

Per `2026-03-18-legal-cross-document-audit-review-cycle.md`, the audit runs **after** the edit.

1. Re-run the PA-7 cross-reference enumeration and confirm nothing the amendment falsifies:
   `grep -rn "PA-7\b\|Processing Activity 7\b" --include=*.md . | grep -v '/archive/'`. Known
   consumers that make claims about §(c): `knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md:92`
   ("PA-7 §(c) is explicit — GitHub username, signature timestamp, pull-request reference") and
   `knowledge-base/legal/legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md:261`
   (quotes PA-7's balancing limb (i)). Neither is edited by this PR — a superseded quotation in a
   dated audit record is the record of what was believed then. Confirm that reading holds and say so
   in the attestation rather than leaving the next reader to re-derive it.
2. Apply Ruling 6 **as the addendum resolved it: four additions and zero edits.** Ruling 6 first said
   one row; A5 raised it to four, one per Critical finding. Add the rows to
   `## Active Compliance Items` in `knowledge-base/legal/compliance-posture.md` recording that AUP
   §4.7 is scoped by its own heading and opening sentence to the hosted chat surface and does not
   reach the CLA capture path, so that path carries no organisational control.

   **This is why the filings phase runs before this one.** That section's canonical row schema —
   documented in the HTML comment immediately under the heading — requires an `Issue` column carrying
   a real issue number, and `/ship` Phase 5.5's gdpr-gate critical-finding acknowledgment gate
   verifies that every PR-referenced `compliance/critical` issue has a row here before merge. So the
   issue must exist before the row can be written. The phase order is load-bearing, not cosmetic: an
   earlier draft of this plan had the sweep at Phase 4 and the filings at Phase 5, which would have
   had `/work` write a row referencing an issue that did not exist yet.

   **How many rows, and for which findings, is with the reviewing authority and its answer governs.**
   Ruling 6 said one — the AUP §4.7 scope gap. Review challenged that as the least of three: Ruling 1
   (Art. 9 content reachable into an unfiltered, indefinitely-retained field with no organisational
   control) and Ruling 3 (no available Art. 6 basis for the non-signer fraction) are each
   Critical-class by this section's own contract, and PA-32's equivalents carry **three** rows —
   `#7119` (no available lawful basis), `#7120` (Art. 14 notice), `#7121` (full DPIA) — plus a
   matching published sentence in `docs/legal/gdpr-policy.md` §3.3. Write one row per finding the
   authority names, each with its own `compliance/critical` issue from Phase 2, `Status: OPEN`, and a
   `check_id` (`GDPR-Art-9` for the Art. 9 finding, `GDPR-Art-6` for the lawful-basis finding).

   **Also surfaced at review, and folded into the Phase 2 filings rather than done here:** the one operational artefact that
   would have to serve the widened population is signer-only.
   `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` §1's trigger
   table has no Art. 15 access row, §4 is titled "Retrieve evidence by contributor", and §7 is
   Art. 17-only — while `inspect-evidence.sh by-contributor` filters on `.actor.login` and therefore
   *does* reach a non-signer. Fold this into the Phase 2 issue that carries the `(h)` question rather
   than editing it here: that file **is** inside `lint-infra-no-human-steps.py`'s `SCAN_DIRS`
   (`:74-80`), so touching it re-arms a gate this diff currently does not engage.

   Do **not** edit `article-30-register.md:28` (the §0 DPO non-designation cell),
   `compliance-posture.md:20`, or `compliance-posture.md:44` — Ruling 6 gives three independent
   reasons for the first and shows the other two are not PA-7 statements at all.
3. Confirm the public PA count did not change (no Processing Activity added or removed), per
   `2026-02-21-cookie-free-analytics-legal-update-pattern.md`. Note that **#5126** already tracks a
   known undercount in `gdpr-policy.md`; do not fold it in.
4. `bash scripts/generate-kb-index.sh && git add knowledge-base/INDEX.md`.

### Phase 6 — Verify

Run the gate set from `## Research Insights` → *CI gates that actually fire on this diff*. All are
local commands; none needs a deploy or an external console.

## Acceptance Criteria

All pre-merge, and every one is a local command. **Nineteen, down from thirty at plan review** — the
cuts are recorded at the end of this section rather than silently dropped.

Two helpers. `pa7` extracts the PA-7 block with a **flag-based** awk rather than an
`awk '/start/,/end/'` range: a range would close on its own start line here, and the resulting empty
extraction would let every scoped assertion below pass vacuously. `row` narrows to one cell.

```bash
REG=knowledge-base/legal/article-30-register.md
pa7() { awk '/^## Processing Activity 7 /{f=1;next} /^## Processing Activity /{f=0} f' "$REG"; }
row() { pa7 | grep -F "| **$1** |"; }
```

**AC1 — the extraction is non-vacuous, and the row count is exact.** `pa7 | grep -c '^|'` returns
**12** on HEAD, against **11** measured on `main` — the difference is the new `(h) DSAR (Art. 15 / 20)`
row. **Corrected at implementation review: this criterion originally asserted `11` and "adds no
rows", which the PR's own `(h)` row falsifies.** The stale number came from an early draft written
before addendum A4 minted that row, and it survived because the AC set is the only gate on this file
— exactly the condition this section names two paragraphs down. An exact count
is still strictly better than a lower bound: it also catches a row accidentally added or
deleted whose `| **…** |` prefix AC9 would not see. Every scoped AC below depends on this one; if it
reads 0, they are all meaningless.

**AC2 — PA-7 still parses as a 2-column table.** Exits 0:

```bash
pa7 | grep '^|' | sed 's/\\|/§/g' \
  | awk -F'|' '{ if (NF != 4) { printf "BAD ROW (%d fields): %.90s\n", NF, $0; bad=1 } } END { exit bad?1:0 }'
```

**AC3 — §(c) describes all four record shapes and the capture predicate.** Against
`row '(c) Categories of personal data'`, each of these returns ≥ 1: `comment_body`;
`comment_body_sha256`; `principal_safe`; `override_reason`; `repoId`; `capture_method`;
`Capture predicate`. And the cell records the `SignerRow` caveat rather than repeating this plan's own
original error: `grep -c 'backfill reader'` and `grep -cF 'does **not** declare'` each return ≥ 1.
`grep -c comment_body "$REG"` returns ≥ 1 repo-wide; it returned **0** before this change, which is
the defect #7625 filed.

**AC4 — the Special-categories cell carries a determination, asserted positively on the row.**
`R="$(row 'Special categories (Art. 9 / 10)')"` returns one line, and each of these returns ≥ 1 from
`grep -cF` against `$R`:

```text
None sought; may arrive unsolicited
Art. 9(2)(e) is available but does not carry this cell
Art. 9(2)(f)
override_reason
No Art. 10 data
```

plus `printf '%s' "$R" | grep -cF 'None. |'` returns **0**, and
`pa7 | grep -cE '^\| \*\*Special categories\*\* \|'` returns **0** (the un-suffixed label is gone).

**The harmonisation moves PA-7 from the minority form into the majority one, measured:** of the
register's 31 Special-categories rows, **24 carry the `(Art. 9 / 10)` suffix and 7 carry the bare
label** — the seven being PA-3 through PA-9 consecutively, which reads as an early-drafting artefact
rather than a distinction. A reviewer noted that harmonising one of seven leaves two spellings for
issue #7669 to learn. That is true, and it is why the remaining six are filed in Phase 2 rather than
swept here, where they would breach the "only PA-7's rows" constraint and fail AC9.

**Absence alone is a proxy here and the first draft relied on it.** Its anchor required the
*un-suffixed* row label — which the label harmonisation in the same phase removes — so after the
rename it returned `0` regardless of the cell body. The passing-but-broken state was concrete:
rename the label, leave the body `None.`, append the CORRECTION block, and every other AC in the set
also went green while P2 — this plan's headline property — went unguarded. Positive content anchors
on the row are the fix, and they are the same technique AC7 already uses.

**AC5 — limb (iii) no longer claims what the workflow does not deliver.** The old string
`signer is informed of the record at signing time` must not survive in the **live cell text**:

```bash
row 'Lawful basis' | sed 's/\*\*\[2026-.*//' | grep -c 'signer is informed of the record at signing time'
```

returns **0**, and the same command against `main` returns **1** — so the criterion is non-vacuous.

**Amended at implementation; the first form was unsatisfiable by a correct implementation.** It
asserted the string returns 0 from `pa7` — the whole PA-7 block — and scoped away only the *audit
records*. But this register's amendment convention requires every block to quote the text it
supersedes (*"this cell previously read X"*), and Ruling 4's binding CORRECTION block does exactly
that. So the string is necessarily present inside the block, and the original AC forbade the very
convention the advisory mandates. Measured: 1 occurrence in PA-7, 0 of them in live text.

The `sed` strips from the first amendment block onward, leaving only the operative cell. The AC now
tests the real property — the live limb makes no claim the workflow does not deliver — rather than a
proxy that a correct file fails. Fixing the artifact here would have meant deleting a mandated block;
the criterion was the thing that was wrong, and it is amended explicitly rather than quietly replaced
with a looser command at run time.

**AC6 — the lawful-basis cell names the real mechanism and splits the balancing.** Against
`row 'Lawful basis'`: `custom-notsigned-prcomment` returns ≥ 1; `necessity` returns ≥ 1; and
`Art. 9(2)(f)` returns ≥ 1. Together with AC5 this asserts the replacement, not only the removal.

**AC7 — Categories of data subjects widened, asserted on the row and not the block.**
`row '(c) Categories of data subjects' | grep -c 'license/cla'` and the same for `admin_actor` each
return ≥ 1. **The block-scoped form of this AC is vacuous**: both strings also appear in Ruling 2's
*personal-data* cell text, so a `pa7`-scoped grep goes green with the data-subjects row completely
unchanged. Baseline on `main`: `pa7 | grep -c 'license/cla'` returns `0`.

**AC8 — all five amendment blocks are present, each with the label the advisory assigns, and no new
label is minted.** `pa7 | grep -c '2026-09-03 WIDENING (#7625)'` returns **2**;
`pa7 | grep -c '2026-09-03 CORRECTION (#7625)'` returns **2**;
`pa7 | grep -c '2026-09-03 CORPUS DIVERGENCE (#7625)'` returns **1**; and
`pa7 | grep -oE '\[2026-09-03 [A-Z][A-Z ]*\(' | sort -u` returns exactly those three labels — all
three already in the register's vocabulary.

The `CORPUS DIVERGENCE` block's tracking reference must resolve:
`row '(c) Categories of data subjects' | grep -c 'tracked at #[0-9]'` returns ≥ 1 and
`grep -c '#<PR-B-issue>' "$REG"` returns **0**. A divergence block carrying an unsubstituted
unsubstituted marker reads as discharged-somewhere and is worse than none.

Every block closes in PA-7's local style: for each of the four cells that carries one,
`grep -cF 'convention.]**'` returns ≥ 1, matching `:161`. Without that clause a block with the wrong
closing form passes the label count green — which mattered when the fourth block was still "drafted on
the same pattern" rather than supplied verbatim.

**The `(h) DSAR (Art. 15 / 20)` row exists and carries no amendment block** — it states no prior
position, so it takes none. `pa7 | grep -c '^| \*\*(h) DSAR'` returns **1**, and
`grep -c '^| \*\*(h)' "$REG"` returns **9**, up from the 8 measured on `main`.

**AC9 — only the in-scope rows moved, and the register's other tokens survive.** The exclusion is
anchored to the **row-label prefix**, not matched anywhere in the line. Exits 0:

```bash
git diff main...HEAD -- "$REG" | grep -E '^[+-]\| \*\*' \
  | grep -vE '^[+-]\| \*\*((\(c\) )?Categories of (data subjects|personal data)|Special categories.*|Lawful basis|\(h\).*)\*\* \|' \
  && { echo "a row outside the in-scope cells changed"; exit 1; } || exit 0
```

**The unanchored form is a proxy, not the invariant.** Register rows are multi-kilobyte prose, and
Ruling 2's own replacement §(c) cell contains the literal strings `Lawful basis` and
`Special categories` inside its body — so an unanchored `grep -vE` silently filters out *any*
out-of-scope row that happens to mention one of the four names, including PA-12's `Lawful basis` row
and PA-15's `Special categories (Art. 9 / 10)` row.

**But the anchored form above is ALSO only a proxy, and this was found at implementation.** Its
allowlist is keyed on the row **label** with no Processing-Activity scoping, so `Special categories.*`
and `Lawful basis` match those rows in **all 35** activities. It would pass a full semantic rewrite of
PA-31's `Special categories` cell and fail a trailing-pipe repair on PA-34's `(a) Controller` — it does
not assert "only PA-7's rows" at all. That is the defect class this branch's own learning file names:
a check certifying something narrower than the name it carries.

**Mutation-proven, not reasoned.** A PA-31 Special-categories cell was mutated semantically and the
two forms were run against the same tree: the label limb reported **PASS**, the strengthened form
below reported **FAIL**. A guard whose removal changes no verdict is vacuous; this one's does.

**AC9-STRONG — the invariant itself.** Extract PA-7 from `main` and from the working tree, and assert
that the register's whole changed-line count equals PA-7's:

```bash
extract() { awk '/^## Processing Activity 7 /{f=1;next} /^## Processing Activity /{f=0} f'; }
git show main:"$REG" | extract > /tmp/pa7.main; extract < "$REG" > /tmp/pa7.head
whole=$(git diff main -- "$REG" | grep -c '^[+-][^+-]')
only7=$(git diff --no-index --unified=0 -- /tmp/pa7.main /tmp/pa7.head | grep -c '^[+-][^+-]')
[ "$whole" = "$only7" ]   # every changed line in the file is inside PA-7
```

Reading at implementation: **9 and 9** — 4 rows rewritten (+4/−4) plus the new `(h)` row (+1).

**Use `git diff main`, not `git diff main...HEAD`.** The three-dot form reads the committed tree, so it
reports `0` for an uncommitted edit — which reads as "nothing changed outside PA-7" and passes for the
wrong reason. The two-number comparison is what surfaced this: `whole=0` against `only7=9` is a
contradiction a single-number assertion could not have shown.

The magnitude count the first draft paired here (`= twice the rows rewritten`) is subsumed: it was a
number the plan chose for itself, and the equality above is derived from the file.

This also subsumes the Better Stack disclosure tokens (source ID `2457081`, cluster `eu-fsn-3`), which
live in other Processing Activities' rows: any edit to them fails this AC.
`validate-vector-config.yml` does not fire on this diff, but it will fire on the next `vector.toml`
change and would then blame the wrong PR.

**AC10 — both audit files exist and each carries the frontmatter contract of the sibling it is
modelled on.** They are **not** the same contract; all three existing records were read and no two key
sets are identical, so a single union asserted across both would be wrong for at least one. The
twelve-key common core is required of both:

```text
title  type  date  issue  attestation-authority  status  disposition
tier_classification  semver  brand_survival_threshold  written_against  re_evaluation_triggers
```

| File | Modelled on | Adds | Must NOT carry |
|---|---|---|---|
| `2026-09-counsel-review-7625.md` | `2026-08-20-clo-review-7624-…` | `governing_record`, `scope_boundary`, `related`, and `pr:` once the number exists | — |
| `2026-09-03-clo-review-7622-…` | `2026-08-17-clo-ruling-…-7597.md` | `pr: 7622`, `signed_off_at`, `signed_off_by`, `attested_commits: 28612e8cd` | A new `scope_boundary:` or `governing_record:` written as though this review set them. Its `disposition` and `re_evaluation_triggers` are the 2026-08-20 review's, restated as history — not commitments made today |

Both files also carry the advisory's standing caveat verbatim — that this is v1 internal counsel
review, is not a substitute for external counsel, and that external counsel is reserved for the
frontmatter triggers. Nothing in CI validates any of this; the contract is precedent alone.

**AC11 — the #7622 record carries all nine findings.** Nine content anchors, one per finding, each
returning ≥ 1 from `grep -cF` against
`knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md`:

```text
last_modified
SHA-256 of its record
conditional PUT
is itself a TOM
records facts, not arguments
Art. 4(12)
aggregate-manifest
runner-egress-IP
EDPB Guidelines 05/2021
```

**Three defects in the first draft of this AC, all found at review and all worth naming.** Anchor 8
was `egress IP` with a space, while Phase 4 tells `/work` to write *"the runner-egress-IP hole was
closed"* — hyphenated — so the AC **could not pass against the text the plan itself prescribes**.
Anchors 3, 4 and 7 were `signatures/`, `Art. 17` and `aggregate`: bare tokens satisfied incidentally
by almost any prose about this archive, in an AC that cites `cq-assert-anchor-not-bare-token` while
violating it. And finding 9 (the overstated re-evaluation trigger) had no anchor at all — `EDPB
Guidelines 05/2021` covers finding 8, so "nine anchors, one per finding" was really eight. Ninth
anchor added: `would not, on its own, convert`.

**AC12 — the #7622 record is dated as what it is.** `date: 2026-09-03`, `pr: 7622`,
`attested_commits: 28612e8cd`, and a body stating it records a 2026-08-20 review. A record written
three weeks later that reads as contemporaneous is a worse artefact than no record.

**AC13 — the blocking CI gates are green, each by its own invocation.** All three exit 0:
`python3 scripts/lint-credential-path-literals.py`;
`cd apps/web-platform && npx vitest run --project repo-wide test/legal-doc-consistency.test.ts`;
`python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`. Each runs the gate's real
command over its real scope, never a hand-enumerated file list.

**AC14 — the lefthook-only gate is green on the files this PR authors.**
`npx --yes markdownlint-cli` exits 0 over **the two new audit files and this plan** — deliberately
**not** over `knowledge-base/legal/article-30-register.md`. It has no CI counterpart, so a
`--no-verify` commit would ship it broken, which is why it is asserted separately from AC13.

> **The register cannot pass markdownlint today, and this is a blocker `/work` would otherwise hit at
> commit time.** Measured on unmodified `main`: **ten pre-existing errors, every one outside PA-7** —
> `MD034` bare URLs at `:26`, `:274`, `:278`, `:294`, `:686`, `:707`; `MD050` strong-style at `:179`
> (×2); `MD038` at `:432`; `MD055` missing trailing pipe at `:660`. `.markdownlintignore` does not
> cover the register.
>
> Two consequences. First, an AC requiring markdownlint to pass on the register would be
> **unsatisfiable without editing rows in other Processing Activities** — which Phase 3 forbids and
> AC9 fails on. Second, and worse: `lefthook.yml:18-22` runs
> `npx --yes markdownlint-cli {staged_files}` on `glob: "*.md"`, so **staging the register blocks the
> commit**, and the natural escape is `--no-verify` — the exact bypass this AC's own rationale warns
> about.
>
> **`/work` must not discover this at commit time.** Either add the register to
> `.markdownlintignore` in a separate PR first, or use `--no-verify` for the register commit *with
> the baseline recorded in the PR body* so the bypass is a documented decision rather than a reflex.
> File the ten pre-existing errors as a tracking issue in Phase 2; they are pre-existing, out of
> scope, and `wg-when-an-audit-identifies-pre-existing` covers them.

**AC15 — `INDEX.md` is regenerated, idempotent, and staged.** The invariant is idempotence, not
cleanliness — a *staged* modification always shows with an `M` status flag in `git status --short`,
so the first
draft's "leaves `git status --short` clean after staging" could never be true. Exits 0:

```bash
bash scripts/generate-kb-index.sh \
  && git diff --quiet -- knowledge-base/INDEX.md \
  && git diff --cached --name-only | grep -q knowledge-base/INDEX.md
```

and `grep -c` for each new audit filename against `knowledge-base/INDEX.md` returns ≥ 1. There is no
CI freshness gate on this file, so a `--no-verify` commit would ship it stale.

**AC16 — the diff touches no `docs/legal/**` surface.** Exits 0:

```bash
git diff main...HEAD --name-only \
  | grep -E '^(docs/legal/|plugins/soleur/docs/pages/legal/|apps/web-platform/lib/legal/)' \
  && { echo "PR class changed — five legal gates + mirror/SHA re-pin now apply"; exit 1; } || exit 0
```

This is what makes the split un-collapsible in the wrong direction.

**AC17 — `vector.toml` is untouched.** `git diff main...HEAD --name-only | grep -c 'vector\.toml'`
returns **0**. **Two reviewers recommended cutting this AC as an invented risk, and it is kept
anyway.** It encodes an explicit constraint the work was handed — editing that file re-fires
`terraform_data.journald_persistent` over a provisioner gated on `var.admin_ips` — and a
simplification that drops requested scope is not a simplification the reviewers were authorised to
make. Cheap, and it fails loudly if a later phase drifts.

**AC18 — every `knowledge-base/` path cited in the new files resolves.** Exits 0:

```bash
grep -ohE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' \
  knowledge-base/legal/audits/2026-09-03-clo-review-7622-pa7-r2-evidence-layer.md \
  knowledge-base/legal/audits/2026-09-counsel-review-7625.md \
  | sort -u | while read -r f; do [[ -f "$f" ]] || { echo "BROKEN: $f"; exit 1; }; done
```

**AC19 — `compliance-posture.md` is addition-only and every row it gains is well-formed, and the
split-out work is filed and dated.** Three parts.

*Addition-only*, with the one documented exception carved out, exits 0:

```bash
git diff main...HEAD -U0 -- knowledge-base/legal/compliance-posture.md \
  | grep -E '^-[^-]' | grep -v '^-last_updated:' \
  && { echo "add only — a line was removed or edited"; exit 1; } || exit 0
```

**The carve-out is required, not a loosening.** `compliance-posture.md` §"How to Update This
Document" states *"Update `last_updated` frontmatter date on every change"* (cited by content anchor:
the line number was already off by one on `main` and this PR's four added rows widen the drift), and the file carries `last_updated: 2026-07-31`.
Bumping it emits a `-last_updated:` line, so the uncarved form would force `/work` to choose between
skipping a documented required bump and failing the AC.

and `git diff main...HEAD -- "$REG" | grep -c 'Art. 9/10 special-category data'` returns **0**, so the
§0 DPO cell is untouched.

*Well-formed*: every added row parses as **five** columns and its `Issue` cell matches `#[0-9]+`.
`git diff main...HEAD -U0 -- knowledge-base/legal/compliance-posture.md | grep '^+|'` piped through
the AC2 field-count awk with `NF != 7` (five columns plus the leading and trailing empties) exits 0,
and every such line greps `#[0-9]\+`.

*Count*: `compliance-posture.md` gains **exactly four** rows under `## Active Compliance Items`, one
per finding in the addendum's A5 table, each carrying **a** `compliance/critical` issue number,
`Status: OPEN`, and a `check_id`. **Zero DPIA rows** — A5 records why, so the count is not
re-litigated later.

**"its own" → "a", ruled at A7.2, and the row count is unaffected.** Four rows carry **three**
distinct numbers: Rows 2 and 4 are the same article (Art. 9) on the same activity, differing only by
population, gateway and remediation, and remediation-splitting is not this register's test. A5's
stated precedent was falsified at implementation — #7119's own title is *"PA-32: minimise or cease the
community republication limb (R1-R5)"*, bundling five remediations under one obligation, and the PA-32
trio splits on Art. 6 / Art. 14 / Art. 35. `compliance-posture.md` already carries multiple rows on a
single number, so the `Issue` column requires a number per row, not a distinct number per row.

Assert instead: four rows, and `sort -u` over their `Issue` cells returns **three** numbers. **Rows 2
and 4 must carry different `Notes` text**, each naming which surface its share of the shared issue
covers — a repeated number with duplicated notes is indistinguishable from a copy-paste error.

An earlier draft asserted *exactly one* row, on Ruling 6's "net one addition". Review challenged that
against the PA-32 precedent (#7119/#7120/#7121 — three rows plus a published sentence) and the
question went back to the reviewing authority, which answered **four**. Had the "exactly one"
assertion survived, it would have blocked the correct outcome — an AC frozen on an unverified count
gating against the right answer.

*Filed and dated*: **all seven Phase 2 issues** exist, are referenced by number in the PR body, and
for each number `gh issue view N --json labels,milestone` returns a non-empty label set drawn from the
verified allowlist. **The four that carry an obligation or a mechanism — #7812, #7813, #7814, #7816 —
additionally carry the `Phase 4: Validate + Scale` milestone**, a merge gate on the milestone and not
merely on the labels, because an issue in `Post-MVP / Later` is where a split quietly becomes a
deferral. #7815, #7817 and #7818 are filed to `Post-MVP / Later` and are **not** gated here.

The first draft asserted that labels "were verified via `gh label list` before the issue was created",
which is a process claim no command can falsify after the fact; asserting the issue's actual label set
is the state-based form.

**Ten planned filings became seven, and the enumeration is restated because the item numbers moved.**
A `code-simplicity-reviewer` CONCUR gate ran as admission control before any issue was created, and
established that the plan's stated blocker for inlining seven of them — that AC9 forbade touching rows
outside PA-7 — was false (see AC9 above). The scope question that survived is a legal one and was
ruled by the attestation authority at A7, not by the reviewer. Net issue flow: **+6**, from a planned
+9.

| Issue | Carries | Milestone |
|---|---|---|
| #7812 | Posture Row 3, and the `CORPUS DIVERGENCE` / `(h)` tracking reference | Phase 4 |
| #7813 | Posture Row 1 — Art. 6 | Phase 4 |
| #7814 | Posture Rows 2 **and** 4 — Art. 9, both surfaces | Phase 4 |
| #7815 | The four over-broad AUP § 4.7 sites (2 correction, 2 determination) | Post-MVP |
| #7816 | The specified-but-unbuilt sign-phrase gate + `override_reason` vocabulary | Phase 4 |
| #7817 | Register hygiene — six bare labels, ten pre-existing lint errors | Post-MVP |
| #7818 | Two C4 gaps | Post-MVP |

### Cut at plan review — recorded, not silently dropped

Eleven criteria came out. `AC4` deferred its own predicate to the implementer ("enumerate the list
from the advisory"), which is a phase instruction wearing an AC's clothes — folded into the enumerated
AC3. `AC3`, `AC7`, `AC9`, `AC19`, `AC22`, `AC24`, `AC30` were each strictly subsumed by a stronger
sibling and are folded above. `AC5`'s "if the advisory rules `None.` stands, this AC inverts" branch
was dead on arrival — the advisory ruled. `AC13`/`AC14`/`AC21` collapsed into one. `AC18` was
recommended for cutting and is kept, for the reason given at AC17 above.

**What survives is not ceremony, and the reason is worth stating.** `## Research Insights` establishes
that **nothing in CI validates this register's table integrity, its PA numbering, or its required
cells, and nothing validates `audits/` frontmatter at all**; markdownlint and the INDEX regeneration
are lefthook-only. When CI checks nothing, the AC set *is* the CI. Nineteen greps standing in for an
absent test suite is a manual stand-in for **#7669** — and cutting that sentinel from scope is exactly
what makes them necessary.

### AC pre-flight — the commands run against `main` before being frozen

The assertions below were executed against the unmodified tree so that a green reading after the
change means something. An AC that has never been observed failing is not a gate.

**This table covers thirteen of the nineteen — AC1-AC5, AC7-AC10, AC13, AC14, AC16 and AC19 — and
the heading used to claim all of them.** The six it does not cover (AC6, AC11, AC12, AC15, AC17,
AC18) assert against artefacts that do not exist yet: the two audit files, the Phase 2 issues, and
the `compliance-posture.md` rows. Naming the gap rather than implying full coverage is the same
standard this plan applies to the register. *An earlier draft of this paragraph said "fourteen" and
"five" — neither matched the table below it.*

| AC | Command run at plan time | Reading on unmodified `main` |
|---|---|---|
| AC1 | `pa7 \| grep -c '^\|'` | `11` — which is why the floor is exact rather than `>= 9` |
| AC2 | the 2-column awk | `rc=0` — PA-7 parses cleanly today, so a post-change failure is attributable |
| AC3 | `grep -c comment_body "$REG"` | `0` — the defect |
| AC4 | `pa7 \| grep -cE '^\| \*\*Special categories\*\* \| None\. \|[[:space:]]*$'` | `1` — **the first draft anchored on `None\.$` and read `0`, because the row ends `None. \|`. It would have passed vacuously on an unchanged file.** Corrected |
| AC5 | `pa7 \| grep -c 'signer is informed of the record at signing time'` | `1` |
| AC7 | `pa7 \| grep -c 'license/cla'` | `0` — and the row-scoped form is the only one that stays honest; see the note at AC7 |
| AC8 | `grep -o "\[2026-[0-9-]* [A-Z][A-Z ]*(" "$REG"` | ten distinct strings, nine of them kind-labels; `WIDENING` used exactly once, confirming the #7100 precedent |
| AC9, AC16 | both `git diff … && { exit 1; } \|\| exit 0` forms | `rc=0` on a clean tree — the shell pattern was smoke-tested, not assumed |
| AC10 | frontmatter key extraction across all three siblings | no two key sets identical — which is what falsified the first draft's single-union assertion |
| AC13 | `lint-credential-path-literals.py` | `rc=0`, 8074 files scanned |
| AC13 | `npx vitest run --project repo-wide test/legal-doc-consistency.test.ts` | `1 passed (1)` / `35 passed (35)` in 725ms — the pre-change baseline |
| AC13 | `lint-infra-no-human-steps.py` on this plan | `OK: no human-run infra steps in 1 scanned file(s)` |
| AC14 | `markdownlint-cli` on this plan | one MD038 error on a nested backtick inside a code span, in an AC that has since been rewritten; clean after |
| AC19 | `gh api repos/jikig-ai/soleur/milestones` + `gh label list --limit 200` | `Phase 4: Validate + Scale` exists (number 4); all ten labels exist |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Nothing in CI validates this file.** No gate checks table integrity, PA numbering, or required cells; no gate validates `audits/` frontmatter. A malformed row or a missing frontmatter key ships silently | AC1/AC2 assert the table shape with an anti-vacuity floor; AC10 asserts the frontmatter contract by hand. The systemic fix is **#7669**, deliberately not built here. **Verified, and it is stronger than "no gate":** `.markdownlint.json` sets `"MD056": false`, so even the linter that *does* run on staged Markdown has table-column-count checking switched off repo-wide — AC2 is the only table guard in existence for this file, not merely the most convenient one |
| **The register cannot be staged through lefthook.** Ten pre-existing markdownlint errors, all outside PA-7, and `.markdownlintignore` covers only `distribution-content/` and `INDEX.md` | AC14 scopes markdownlint to the files this PR authors and records the baseline; Phase 2 item 6 files the ten errors; the commit decision (ignore-file first, or `--no-verify` with the baseline in the PR body) is made deliberately rather than discovered at commit time |
| The §(c) rewrite drifts into deciding the *processing* rather than the *record* — e.g. concluding the capture path should filter | Phase 1's second arm routes that to a separate issue explicitly, matching how #7668 handles retention. The advisory's Ruling 5 sets the boundary and governs |
| The Art. 9 answer moves and a downstream Art. 9 claim is left stale — the §0 DPO non-designation at `:28`, or `compliance-posture.md:20,44` | Ruling 6 as amended by A5 enumerates exactly which must move. Phase 5 step 2 applies only that list |
| An absence-grep AC false-fails because the audit record legitimately quotes the string being removed | AC5 is scoped to the PA-7 block, not the repo. This is the specific trap the plan's own AC set was checked against |
| **The advisory does require a `docs/legal/**` edit — Ruling 5(B).** The published corpus frames the archive as processing "CLA signature data when contributors sign", which is now known to be narrower than the code | Split, not folded. PR B is filed as its own issue in Phase 5 with the full gate list. AC17 fails the build if such an edit lands in this PR, so the split cannot silently collapse. The transparency gap does **not** depend on measuring the bucket — it follows from the workflow `if:` conditions — so PR B is owed regardless of Phase 1's outcome |
| Splitting leaves a real Art. 13/14 gap open on the published surface for as long as PR B takes | Recorded, not minimised. Ruling 5's own sequencing note applies: landing the engineering fix first turns PR B's disclosure into a historic window rather than an ongoing practice. Both are filed in Phase 5 so neither depends on memory |
| The plan's own research got nine facts wrong, four of them load-bearing, and the review panel caught every one | Every one is recorded in place as a visible correction rather than quietly rewritten, in the same spirit the register applies to itself. The pattern is worth naming: each error came from **paraphrasing a plausible mirror** — `SignerRow` for the record shape, the receipt for the notice, `:242` for a PA-7 block — rather than reading the thing itself |
| Line-number citations in this plan go stale as sibling amendments land | Phase 3 anchors every edit on its row's `| **<cell>** |` prefix; line numbers appear only as reading aids, per `cq-cite-content-anchor-not-line-number` |
| The archive cannot be read in-session and the register describes an unmeasured scope | Phase 1 records the archive as UNMEASURED by default and hands the measurement to the PR B issue, where it is load-bearing. The capture-rule description is true on both arms, per Ruling 1 |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Patch §(c) with the six field names from the issue body | The issue body's list is incomplete in three directions: the evidence record carries more, the git-branch shape §(c) claims to describe is itself under-described, and two further record shapes exist. A six-item patch would close the issue while leaving the cell wrong |
| Decide the Art. 9 question inline, as a wording fix | It is a subjective Art. 9 determination over an unbounded free-text field held indefinitely behind a write-once floor. #7622's own review directed **do not bundle** for exactly this reason. Routed to the CLO agent, which the register names as its custodian at `:0` |
| Fold in the #7624-class corpus edits so the published surfaces match | Those live under `docs/legal/**` and fire five legal gates plus a mirror/SHA re-pin — a different change class. #7622's body already reasons this out for the same corpus |
| Build a CI sentinel binding §(c) to `schema.ts` | **#7669** already owns that capability. See the Cut List |
| Fold in #7668 (retention proportionality) or #7670 (transfer test) since both touch PA-7 | Both are controller decisions about the processing, not record-accuracy questions. Each has its own issue and its own analysis |

## Domain Review

**Domains relevant:** Legal.

Assessed against `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` in one
pass. Engineering: no code, no infrastructure, no runtime surface — not relevant. Product: no
user-facing surface; the mechanical UI-surface override does not fire, because neither path in
`## Files to Edit` / `## Files to Create` matches any UI glob. Finance, Marketing, Sales, Operations,
Support: not relevant. Legal is not merely relevant — it is the entire subject.

### Legal

**Status:** reviewed.

**Assessment:** obtained at plan time from the `soleur:legal:clo` agent, which
`knowledge-base/legal/article-30-register.md` §0 names as the register's own custodian ("Register
custodian | Soleur Chief Legal Officer role (CLO agent)"). The advisory is recorded verbatim in
`## CLO Advisory — Binding Rulings` below and governs every other section of this plan.

This follows the flow that produced the sibling record at
`knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md:49-52`,
where the advisory was obtained at plan time and transcribed into the audit file as a `/work`
deliverable. Obtaining it now, rather than prescribing it for `/work`, means `/work` implements a
decided question instead of making a subjective Art. 9 determination mid-implementation — and it
front-loads the artefact that `/ship` Phase 5.5's Counsel-Review CLO-Attestation Gate will demand
anyway.

**Brainstorm-recommended specialists:** none — no brainstorm preceded this plan.

### Product/UX Gate

Not applicable. Product was assessed NONE by the sweep and the mechanical UI-surface override did not
fire, so no tier applies and no gate section is owed.

## GDPR / Compliance Gate (Phase 2.7)

**Triggered, and satisfied by the higher authority rather than skipped.**

The canonical `hr-gdpr-gate-on-regulated-data-surfaces` regex targets schemas, migrations, auth
flows, API routes and `.sql` files — none of which this diff touches. But the trigger fires anyway on
the plan's declared `brand_survival_threshold: single-user incident`, and more obviously on the fact
that the deliverable *is* a GDPR Art. 30 artefact.

`/soleur:gdpr-gate` produces an advisory that routes Critical findings — Art. 9 special-category,
missing lawful basis, Art. 30 trigger — to `compliance-posture.md` Active Items plus a
`compliance/critical` issue. All three of those categories are precisely what the `clo` agent was
asked to rule on in Phase 2.5, on a fuller record than a diff-scoped gate could assemble, and the
CLO is the register's named custodian. Running the gate as well would produce a second, weaker
opinion on the same three questions.

Recorded as satisfied-by-CLO rather than skipped silently, so a future reader can see the reasoning
and disagree with it. If the advisory's Ruling 1 declares an Art. 9 consequence, the
`compliance-posture.md` Active Items row and any `compliance/critical` filing the gate would have
produced are owed regardless of which authority surfaced it — that obligation is carried into
Phase 5 step 2 via Ruling 6 as amended by addendum A5.

## Gates assessed and not applicable

Recorded rather than skipped silently, so the next reader does not re-derive them.

- **Phase 2.8 Infrastructure-as-Code.** No server, service, cron, vendor account, DNS record, cert,
  secret, firewall rule, or persistent runtime process. The diff is two Markdown files and a
  regenerated index. Scanning this plan and the feature description for the gate's own detection
  strings yields exactly one match: the Phase 1 read of Doppler `prd_cla`, which is a `doppler run`
  read against an existing config, not a provisioning step and not a secret write.
- **Phase 2.9 Observability.** Pure-docs: no file under `apps/*/server/`, `apps/*/src/`,
  `apps/*/infra/` or `plugins/*/scripts/`, and no new infrastructure surface. No `## Observability`
  block is owed. No soak-gated or time-gated close criterion appears in any AC, so 2.9.1 does not
  fire either.
- **Phase 2.11 Encryption Posture.** No persistent store and no new cross-component connection. The
  diff matches none of the detection globs (`\.tf$`, `supabase/migrations/.*\.sql$`,
  `cloud-init.*\.ya?ml$`, `docker-compose.*\.ya?ml$`). The R2 bucket this plan *describes* is
  pre-existing and its posture is already recorded in PA-7 §(g).
- **Phase 2.12 Guard Contract.** The deliverable contains no guard, gate, lint, drift-check or
  anti-vacuity control. The one guard that would belong here — a sentinel binding §(c) to
  `schema.ts` — is cut in favour of **#7669**, which already owns it. Cutting it is what keeps this
  gate inapplicable; inventing it would have pulled a full Guard Contract into a docs PR.
- **Phase 4.5 scoped advisor consult.** The riskiest decision in this plan is a subjective Art. 9
  determination, and it was routed in Phase 2.5 to the domain authority the register itself names,
  on a brief that enumerated the disqualifying facts for every option not proposed. A generic
  strong-model second opinion on the same fork would be strictly weaker. Recorded, not skipped.

## CLO Advisory — Binding Rulings

Obtained at plan time from the `soleur:legal:clo` agent against PA-7's `(c) Categories of data
subjects`, `(c) Categories of personal data`, `Special categories` and `Lawful basis` cells. These
rulings are **inputs to `/work`, not review comments.** Where this section and any earlier section of
this plan disagree, **this section governs**. `/work` Phase 0 writes it verbatim to
`knowledge-base/legal/audits/2026-09-counsel-review-7625.md` — planning is confined to
`knowledge-base/project/{plans,specs}/`, so the audit file is a `/work` deliverable.

**Overall disposition: PROCEED-WITH-CHANGES.** `None.` is not sustainable, §(c) is not sustainable,
and limb (iii) is not sustainable as written. None is a blocking defect — there is no notification
duty and no unlawful processing requiring a stop today — but all three move in this PR, and one
changes the PR's class.

### Seven corrections to the brief, made before ruling

Recorded because ruling on the brief's framing would have produced two wrong answers.

1. **`SignerRow` does not declare `repoId`.** `backfill.ts` declares `name`, `id`, `pullRequestNo`,
   `comment_id`, `created_at`, `signedOnPR?`. The live branch content carries `repoId`; the interface
   does not. It is the backfill reader's view, not the record's shape. Do not cite it as a mirror.
2. **The receipt comment is not the informing mechanism, and never was the load-bearing one.**
   `cla.yml`'s `custom-notsigned-prcomment` posts, in-thread and before signing, a link to
   `docs/legal/individual-cla.md`, whose §0 discloses both copies, Cloudflare as a US-established
   processor, indefinite retention and the erasure route — and the required sign phrase is an
   attestation of having read it. A pre-signature Art. 13-shaped notice, materially stronger than a
   post-hoc receipt. This reverses the outcome of Ruling 3 for signers.
3. **The over-capture moves "Categories of data subjects", not only "Categories of personal data".**
   `wait_cla` polls the *persisting* `license/cla` status on the PR head SHA; once green it stays
   green. Every subsequent `issue_comment` on that PR — from any author — writes a record carrying
   that author's `login`, `id`, `type` and verbatim `comment_body`. A reviewer who signs nothing
   becomes a data subject of PA-7.
4. **The `deleted` path is not merely "no receipt".** `build-record.ts` sets
   `capture_method = "live-degraded"`, nulls `comment_body`, sets `fetch_error: "deleted"` — it
   writes a *further* record. The earlier `created` record, holding the body, is not withdrawn and
   cannot be under the §(g) floor.
5. **AUP §4.7 does not reach this surface.** Its heading is "Special-Category and Sensitive Personal
   Data — **Hosted Chat Surface**" and its opening sentence scopes it to `app.soleur.ai` prompt input
   and `chat-attachments`. A GitHub pull-request comment is neither. So there is no filter **and** no
   organisational control on the CLA capture path — weaker than PA-27, PA-32 and PA-35, each of which
   names at least one. (This also means the cells that cite §4.7 as prohibiting Art. 9/10 content
   "in repository submissions" overstate it. **Two such cells, and neither is PA-35**: `:313` (PA-17)
   and `:658` (PA-33) — corrected at plan review. Separate defect — see Ruling 5.)
6. **`compliance-posture.md:20` and `:44` are not PA-7 Art. 9 statements.** Line 20 is the #5363
   entry, scoped to PA-2 `turn_summary`. Line 44 is the #3988 entry recording that AUP §§4.7/4.8 were
   added. Neither says anything about PA-7.
7. **PA-7 §(e) carries no `CORRECTION` block, and line 242 is PA-12, not PA-7.** PA-7 §(e) uses
   `CORPUS DIVERGENCE` → `DIVERGENCE DISCHARGED` → `OPEN QUESTION`. **The register does not have a
   single-label convention. It has a vocabulary** — nine labels in use. `WIDENING` already exists,
   minted at #7100.

### Ruling 1 — Special categories: `None.` is NOT sustainable

`comment_body` is unbounded free text authored by the data subject; no component on the path compares
it to the sign phrase (`grep` for `hereby sign` across `apps/web-platform/scripts/cla-evidence/`,
`apps/cla-evidence/` and `cla-evidence.yml` returns nothing); §(f) is indefinite behind a write-once
floor. The register's own shape for exactly this is "none sought; may arrive unsolicited" plus named
controls and a named residual (PA-27:540, PA-32:639, PA-33:658). PA-7 is out of step with three of
its own siblings, and it is the sibling with the *fewest* controls.

**On Art. 9(2)(e), squarely.** It is genuinely available — a comment on a PR in a public repository
is about as clean a case of "manifestly made public by the data subject" as the Article contemplates.
It does not do the work being asked of it, for three reasons. It is a **gateway, not a denial**:
reaching for it concedes that Art. 9 data may be in the record, and a cell saying `None.` and a cell
relying on (2)(e) cannot both be right. It is **assessed at the moment of processing** while retention
is indefinite: an author who deletes their comment from the public surface removes the very publicity
that opened the gateway, while the archived copy persists behind a floor only `gdpr-override.sh` can
lift — which §(g) itself calls "not absolute". And it is **conditional on the repository being
public**, which nothing in the schema constrains: `pr_of_record.repo` is a free string, so publicness
is a present fact, not a structural invariant. Per `audits/2026-08-counsel-review-7100.md`, (2)(e) is
a special-category gateway, **not** an Art. 6 basis, and must not appear in the Art. 6(1)(f)
balancing. Ruling 3's text keeps it out.

**On `override_reason` — the sharper finding.** `gdpr-override.sh` writes `admin_actor`,
`gdpr_request_ref` and `override_reason`: operator-authored free text stating *why* an erasure was
granted. "Subject asked us to remove a health disclosure" is itself Art. 9 content, is written
*about* a subject rather than *by* them (so (2)(e) is structurally unavailable), and is the one object
in the bucket that an Art. 17 erasure **creates** rather than removes. The available gateway there is
Art. 9(2)(f), pairing with the Art. 17(3)(e) carve-out already relied on at §(f).

**Both arms of the unmeasured question.** This cell is correct whether or not the bucket holds a
realised Art. 9 disclosure, because §(c) records the categories of data the controller *processes*,
and the capture predicate is a property of the code that was read — not of the bucket that was not.
Measurement changes the *severity* question (whether an incident occurred; whether Art. 14 notice is
owed to an over-captured commenter), not the register text. **Do not gate the register edit on the
measurement.**

Also harmonise the row label from `**Special categories**` to `**Special categories (Art. 9 / 10)**`,
matching PA-15/27/32/35. The register is internal-only and in no Eleventy tree, so this touches no
gate today; note it as an input to #7669.

#### Exact replacement cell — Special categories

```text
| **Special categories (Art. 9 / 10)** | **None sought; may arrive unsolicited — and here nothing filters it.** The off-site evidence record persists `comment_body`, the verbatim text of a GitHub pull-request comment authored by the data subject (`EvidenceRecordSchema.comment_body`, `string \| null`, in `apps/web-platform/scripts/cla-evidence/schema.ts`). **No component on the capture path compares that text against the required sign phrase** (`custom-pr-sign-comment` in `.github/workflows/cla.yml`): the write step's only gate is `steps.wait_cla.outputs.cla_state == 'success'`. A signer — or any other commenter, see the capture predicate at §(c) — can therefore place Art. 9 content into an indefinitely-retained, write-once archive. **Art. 9(2)(e) is available but does not carry this cell.** A comment posted on a pull request in a public repository is manifestly made public by its author, so the gateway is open at the moment of processing. Per `knowledge-base/legal/audits/2026-08-counsel-review-7100.md`, Art. 9(2)(e) is a special-category **gateway and not an Art. 6 basis**; it is not relied on in the balancing recorded at "Lawful basis". Two conditions bound it. (i) It holds only while the pull request sits in a **public** repository — `pr_of_record.repo` is unconstrained in the schema, so publicness is a present fact and not a structural invariant. (ii) It is assessed at the moment of processing, whereas §(f) is indefinite behind the §(g) write-once floor — an author who deletes the comment from the public surface removes the publicity that opened the gateway while the archived copy persists, and the `deleted` path writes a further `live-degraded` record without withdrawing the earlier one. **No filter, and no organisational control on this surface:** AUP § 4.7 is scoped by its own heading and opening sentence to the hosted Web Platform at `app.soleur.ai` (prompt field and `chat-attachments`) and does not reach a GitHub pull-request comment. This is a weaker control posture than PA-27, PA-32 or PA-35, each of which names at least one. **The erasure tombstone is a second and distinct Art. 9 surface.** `apps/cla-evidence/scripts/gdpr-override.sh` writes `override_reason` — operator-authored free text stating why an erasure was granted — alongside `gdpr_request_ref`. A reason of the form "subject asked us to remove a health disclosure" is itself Art. 9 content, is written **about** a data subject rather than by them (so Art. 9(2)(e) is structurally unavailable), and is the one object in this bucket that an Art. 17 erasure **creates** rather than removes. Gateway relied on there is Art. 9(2)(f) — establishment, exercise or defence of legal claims — the same ground as the Art. 17(3)(e) carve-out at §(f). **Named residual (accepted at present scale, not as a steady state):** erasure of an Art. 9 disclosure runs only through `gdpr-override.sh`, which §(g) itself records as "not absolute". The signer population is two. Two remediations are recorded as options and are **not** adopted here, being engineering decisions: a sign-phrase equality check before the evidence write, and a closed vocabulary for `override_reason`. A GitHub login, numeric account id and contributor identity are **not** Art. 9 special categories. **No Art. 10 data** is sought or expected on this path. |
```

### Ruling 2 — §(c) Categories of personal data, and Categories of data subjects

**Bypass shape: in scope of §(c), with a carve.** The "mostly bots" argument fails on its own terms —
`deruelle` is on the `cla.yml` allowlist and is a natural person. His `principal`, `db_id`,
`first_seen_at` and `first_pr` are personal data of an identified individual, held in the same bucket
under the same floor. "Mostly not personal data" is not "not personal data."

**Tombstone shape: in scope of §(c).** The "Art. 17 artefact, not a category" argument fails.
Art. 30(1)(c) asks what personal data the controller processes for the activity. `admin_actor`
identifies a natural person; `gdpr_request_ref` may identify the requesting subject; `override_reason`
is free text about them. It is stored in the same bucket, for the same purpose, sealed by the same
rule. Art. 17 machinery is itself processing, and a category of data that exists *only* because of an
erasure is precisely the kind a register must not lose track of.

#### Exact replacement cell — (c) Categories of personal data

```text
| **(c) Categories of personal data** | **Four record shapes.** **(1) Public canonical record** — `origin/cla-signatures:signatures/cla.json`, one entry per signer: `name` (GitHub login), `id` (GitHub numeric account id), `comment_id`, `created_at` (signature timestamp), `repoId`, `pullRequestNo`. (The `SignerRow` interface at `apps/web-platform/scripts/cla-evidence/backfill.ts` is the backfill reader's view and declares `name`, `id`, `pullRequestNo`, `comment_id`, `created_at`, optional `signedOnPR` — it does **not** declare `repoId`, which the live branch content carries. Do not read it as the record's full shape.) **(2) Off-site evidence record** — `signatures/<sha256-of-payload>.json`, `EvidenceRecordSchema` at `apps/web-platform/scripts/cla-evidence/schema.ts`: `schema_version`; `comment_id`; **`comment_body` — the verbatim text of the comment, unbounded free text authored by the data subject** (`string \| null`); `comment_body_sha256`; `actor.{login, id, type}`; `pr_of_record.{number, repo}`; `cla_doc.{path, git_sha, content_sha256}` (a hash of Jikigai's text, not the subject's); `signed_at`; `capture_method` (`live \| live-degraded \| backfilled \| backfilled-pre-existed`); `workflow_run_id`; and, on a fetch failure or a deletion, `comment_body_fetch_failed`, `fetch_error`, `first_pr_signed_against`. On an **edit**, a second record is written carrying the edited body; on a **delete**, a `live-degraded` record is written with `comment_body` null. Neither withdraws the earlier record, which the §(g) floor forbids. **(3) Allowlist-bypass record** — `allowlist/<principal>/<quarter>.json`, `BypassRecord` at `apps/web-platform/scripts/cla-evidence/allowlist-bypass.ts`: `principal`, `principal_safe`, `db_id`, `quarter`, `first_seen_at`, `first_pr`, `allowlist_source`. Most allowlist principals are bot accounts and are not natural persons, so those records carry no personal data; the allowlist at `.github/workflows/cla.yml` also names `deruelle`, a natural person, and that principal's records **are** personal data of an identified individual. **(4) Erasure tombstone** — `tombstones/<prior_sha>.deleted.json`, written by `apps/cla-evidence/scripts/gdpr-override.sh`: `schema_version`, `deleted_at`, `admin_actor` (the operator, an identified natural person), `gdpr_request_ref` (may identify the requesting data subject), `prior_object_sha`, `override_reason` (operator-authored free text). Recorded here rather than treated as an out-of-scope Art. 17 artefact: it is personal data held in the same bucket, for the same purpose, under the same §(g) floor, and Art. 17 machinery is itself processing. **Capture predicate — wider than "signature data".** The evidence-record write step in `.github/workflows/cla-evidence.yml` fires on any `issue_comment` (`created`, `edited`, `deleted`) on a pull request whose `license/cla` commit status is `success`, and `wait_cla` reads that status as it persists on the head SHA rather than as a property of the triggering comment. Nothing on the path tests whether the comment is the sign comment. Consequently `actor` and `comment_body` can carry a commenter who signed nothing and text that is not a signature. Recorded as a finding against the implementation; the lawful-basis consequence is at "Lawful basis" and the Art. 9 consequence at "Special categories". **Corporate CLA:** signatory name, corporate email and corporate identity, supplied out-of-band to legal@jikigai.com per the `custom-notsigned-prcomment` instruction in `.github/workflows/cla.yml`; no automated record is written for this route. |
```

#### Exact replacement cell — (c) Categories of data subjects

```text
| **(c) Categories of data subjects** | Individual contributors signing the ICLA; authorised signatories of corporations signing the CCLA. **Additionally, and not by design — see the capture predicate below:** (i) **any GitHub account that comments on a pull request in this repository while that pull request's `license/cla` commit status is `success`**, whether or not it ever signs anything — the evidence-record write gates on that status alone, so a reviewer, a maintainer or a passer-by becomes the `actor` of an evidence record; (ii) **natural persons named on the CLA-action allowlist** at `.github/workflows/cla.yml` (today: `deruelle`), who are the subjects of `allowlist/` bypass records without signing a CLA — the remaining allowlist principals are bot accounts and are not data subjects; (iii) **the operator recorded as `admin_actor`** in an erasure tombstone, and any data subject identified by that tombstone's `gdpr_request_ref`. |
```

### Ruling 3 — Lawful basis: limb (iii) does NOT hold, and more than limb (iii) moves

**For signers, the limb is correct in substance and wrong in mechanism.** The signer is informed —
better than the limb claims — but not "at signing time" and not by the receipt. The notice is
`custom-notsigned-prcomment` → `individual-cla.md` §0, delivered *before* signing, with the sign
phrase as an attestation of having read it. The three receipt defects are all real and all verified,
and they matter exactly because they show why the receipt cannot be the mechanism:
`continue-on-error: true`; an `if:` requiring `action == 'created'` while the write fires on
`created`/`edited`/`deleted`; and no receipt at all on the `pull_request_target` bypass path.

**For non-signers, Art. 6(1)(f) fails — and it fails at necessity, before balancing.** A record whose
actor signed nothing evidences no grant. Limb (ii) ("minimum necessary to evidence the grant") is not
merely strained; it has no subject matter. That ends the analysis in the manner of PA-32's
publication limb, and no other Art. 6 basis is available: no contract, no consent sought, no
legal-obligation, vital-interests or public-task ground. This is a finding against the
implementation, not a defect in the interest.

**Art. 9(2) gateway now additionally required?** Yes, where Art. 9 content actually arrives — and it
is available: (2)(e) for a public-PR comment, subject to Ruling 1's two bounds; (2)(f) for the
tombstone `override_reason`. Neither is an Art. 6 basis and neither is offered as one.

#### Exact replacement cell — Lawful basis

```text
| **Lawful basis** | Art. 6(1)(f) — legitimate interest in maintaining an enforceable record of IP-license grants. **Balancing test — signature records (shapes (1) and (2) where the actor is a signer):** (i) the data is publicly disclosed by the signer through the act of contributing on a public pull request; (ii) processing is the minimum necessary to evidence the grant; (iii) **the signer is informed before signing, and not by the receipt** — the upstream CLA action posts `custom-notsigned-prcomment` (`.github/workflows/cla.yml`) linking to `docs/legal/individual-cla.md`, whose § 0 discloses both copies of the record, the US-established processor, the indefinite retention and the erasure route, and the required sign phrase ("I have read the CLA Document and I hereby sign the CLA") is an attestation of having read that document; the field-level detail, including that the verbatim comment body is retained, sits in GDPR Policy § 3.4, Privacy Policy § 4.5 and DPD § 2.3(n), which § 0 cross-references; (iv) no automated decision-making. **The receipt comment is not the informing mechanism and must not be treated as one.** The "Post receipt comment" step in `.github/workflows/cla-evidence.yml` carries `continue-on-error: true`, and its `if:` requires `github.event.action == 'created'` while the record-writing step also fires on `edited` and `deleted` — so on an edit or a delete a record is written and no receipt is posted at all, a structural absence rather than a soft failure. The `pull_request_target` bypass path posts no receipt ever. The receipt's text names the CLA document's git SHA and a retrieval command; it does not describe the record's fields. **The balancing test does not reach the non-signer capture.** Where the `actor` of an evidence record is a commenter who signed nothing (see the capture predicate at §(c)), the record evidences no grant, so limb (ii) fails on **necessity** and the analysis stops there, before balancing, in the manner of PA-32. No other Art. 6 basis is available for that fraction of the processing: there is no contract with such a commenter, no consent is sought, and no legal-obligation, vital-interests or public-task ground applies. Recorded as a finding against the implementation, not as a defect in the interest; the remediation is an engineering change and is not decided in this register. **Art. 9(2) gateways, where Art. 9 content arrives** (see Special categories): Art. 9(2)(e) for a comment manifestly made public by its author on a public pull request, subject to the two bounds recorded there; Art. 9(2)(f) — establishment, exercise or defence of legal claims — for the tombstone `override_reason`, which the data subject did not write and to which (2)(e) is therefore unavailable. Neither is an Art. 6 basis and neither is offered as one. |
```

### Ruling 4 — amendment mechanics: three labels, matched to three kinds of change

The premise that the register has one convention (`CORRECTION`) is not what the file shows.
`grep -o "\[2026-[0-9-]* [A-Z][A-Z ]*(" knowledge-base/legal/article-30-register.md` returns
**nine distinct kind-labels** in use: `CORRECTION`, `WIDENING`, `NARROWING`, `ADDITION`,
`AMENDMENT`, `UPDATE`, `OPEN QUESTION`, `CORPUS DIVERGENCE`, `DIVERGENCE DISCHARGED`. The convention
is not one label — **the label names the kind of change**, and the block body carries the nuance.

> **Verified independently, with one refinement to the advisory's count.** Running that grep returns
> **ten** distinct strings, not nine: the tenth is `TWO ITEMS RECORDED`, a one-off descriptor rather
> than a kind-label, which is presumably why the advisory did not list it. Occurrence counts:
> `UPDATE` 9, `CORRECTION` 8, `NARROWING` 2, `AMENDMENT` 2, `ADDITION` 2, and one each of `WIDENING`,
> `TWO ITEMS RECORDED`, `OPEN QUESTION`, `DIVERGENCE DISCHARGED`, `CORPUS DIVERGENCE`. The single
> `WIDENING` use confirms the #7100 precedent the advisory relies on, and the substantive ruling —
> a vocabulary exists, `WIDENING` is already minted, do not invent another — is unaffected.

| Cell | Label | Why |
|---|---|---|
| `(c) Categories of personal data` | **`WIDENING`** | Directly on the #7100 precedent: a statement that was **under-inclusive** while asserting completeness |
| `(c) Categories of data subjects` | **`WIDENING`** | Same kind |
| `Special categories` | **`CORRECTION`** | Not under-inclusive — **false**. `None.` asserts a negative the record does not support; a widening label would understate it |
| `Lawful basis` | **`CORRECTION`** | Limb (iii) misnames the mechanism and is false for the non-signer arm |

**Do not mint a new label.** The vocabulary already covers every case here, and #7669 would have to
learn any tenth label added. **Placement and closing formula** follow PA-7's own local style at line
161: block appended at the end of the cell, closing `…convention.]**`.

#### Exact block — §(c) Categories of personal data

```text
**[2026-09-03 WIDENING (#7625): this cell previously read "GitHub username; signature timestamp; pull-request reference associated with the signing event. For Corporate CLA: signatory name + corporate email + corporate identity." That was a closed enumeration, incomplete about the one record shape it named and silent about three others. It omitted `id`, `comment_id` and `repoId` from the public branch record; the entire off-site evidence record introduced by #3201, including the verbatim `comment_body`; the `allowlist/` bypass record; and the erasure tombstone — the last two already named at §(g), so the register described object prefixes whose contents it did not record. The under-inclusion mattered beyond bookkeeping: a §(c) cell is what a DSAR scope and a breach-scope assessment are read against, and a reader relying on the prior text would have under-reported on both. It also left the internal governing record **narrower than the notice published to the data subject** — GDPR Policy § 3.4, Privacy Policy § 4.5 and DPD § 2.3(n) have disclosed the verbatim comment body since #7624 (2026-08-20) — which is the wrong direction for the two to differ. Separately, and not a prior mis-statement: the capture predicate recorded above was established for the first time in this review and is a finding against the implementation, not a repair of the record. An Art. 30(1) record-keeping incompleteness is not an Art. 4(12) personal-data breach and triggers no Art. 33/34 notification; this widening is the record-keeping discharge. Recorded rather than silently repaired, per this register's amendment-history convention.]**
```

#### Exact block — Special categories

```text
**[2026-09-03 CORRECTION (#7625): this cell previously read "None." That was not sustainable. The evidence record persists an unbounded free-text field authored by the data subject, no filter compares it to the sign phrase, and retention is indefinite behind a write-once floor — the conditions under which this register's own PA-27, PA-32 and PA-35 cells reason rather than deny. The strongest argument for the prior text, that the comment is manifestly made public, is Art. 9(2)(e): a gateway that concedes the point rather than a denial that avoids it, and one whose two conditions are recorded above. Recorded rather than silently repaired, per this register's amendment-history convention.]**
```

#### Exact block — Lawful basis

```text
**[2026-09-03 CORRECTION (#7625): limb (iii) previously read "signer is informed of the record at signing time", which named no mechanism. The mechanism is the pre-signature notice comment and § 0 of the CLA document, not the post-hoc receipt — the receipt is soft-failing and structurally absent on `edited`, `deleted` and the bypass path, and could not have carried the limb had it been the mechanism. The limb is restated on the mechanism that actually exists, and the balancing is split: it holds for signers and is unavailable for the non-signer capture recorded at §(c), where it fails on necessity. Recorded rather than silently repaired, per this register's amendment-history convention.]**
```

A `WIDENING` block is required on `(c) Categories of data subjects` as well; draft it on the same
pattern, naming the three added limbs and citing the capture predicate as the reason.

### Ruling 5 — scope boundary, and the PR split

#### This PR must NOT decide

- **#7668** — proportionality of indefinite retention, and whether a ceiling is adopted. Ruling 1
  *pressures* it (an unerasable Art. 9 disclosure is the strongest argument yet for a ceiling); it
  must not answer it. Record the link in the audit; do not touch §(f).
- **#7670** — importer-identity vs byte-location. §(e) is not amended and its `OPEN QUESTION` block
  stands untouched.
- **#7669** — the corpus-anchor CI sentinel. This PR *adds* anchors (`schema.ts`,
  `allowlist-bypass.ts`, `gdpr-override.sh`, `cla-evidence.yml`, `cla.yml`) and a row-label
  harmonisation; note them as inputs, build nothing.
- **#7671** — the LUKS-header bucket. Unrelated.
- **Whether to add a sign-phrase filter, or a closed vocabulary for `override_reason`.** Engineering
  decisions; defer to the CTO. The register records the position as it is; it does not prescribe the
  fix.
- **Whether the archive's realised contents include over-captured records.** Do not assert either
  arm.
- **Whether Art. 14 notice is owed** to an over-captured non-signer. Contingent on that measurement.
- **A DPIA.** Art. 35 is a separate test, the population is two, and the screening convention in
  `knowledge-base/legal/audits/` exists. Do not open one.
- **The over-broad AUP §4.7 citations.** Real defect, surfaced here. Two cells — PA-17 (`:313`) and
  PA-33 (`:658`), not PA-35, which was a misattribution corrected at plan review. Belongs to those
  activities' own amendments. File it.

#### Does anything here require a `docs/legal/**` edit? Yes. Split the PR.

Two separable questions, with different answers.

**(A) The field-level widening of §(c) — no docs edit.** The published corpus already discloses the
verbatim body, doc-hash, PR-of-record, `signed_at` and `capture_method` (privacy-policy §4.5
enumerates exactly those). Art. 13/14 does not require a field-by-field enumeration, and `actor.id` /
`comment_id` add no category the reader is not already told about. The corpus is *wider* than the
register here, which is why this half is internal-only.

**(B) The capture predicate and the non-signer data subjects — yes, and plainly.** DPD §2.3(n) reads
"For each signature recorded under Section 2.3(d), a content-addressed evidence record is written."
Privacy Policy §4.5 and GDPR Policy §3.4 both frame the archive as processing "CLA signature data
when contributors sign." All three are now known to be narrower than the code. A person whose comment
is archived without signing is told nothing by any published document. That is an Art. 13/14
transparency gap on the published surface, and — not to be softened — **it does not depend on
measuring the bucket.** It depends on the workflow `if:` conditions, which were read. The corpus is
wrong on the code fact alone.

So the PR class changes. **Split:**

- **PR A (this plan — internal only).** `knowledge-base/legal/article-30-register.md` PA-7 (four
  cells) + the audit records under `knowledge-base/legal/audits/` + the `compliance-posture.md`
  Active Items addition. Touches no `docs/legal/**`, so none of the five gates fire. Closes #7625.
- **PR B (separate — five-gate class).** `docs/legal/gdpr-policy.md` §3.4,
  `docs/legal/privacy-policy.md` §4.5, `docs/legal/data-protection-disclosure.md` §2.3(n), each with
  its `plugins/soleur/docs/pages/legal/` mirror (all three mirrors exist — verified), plus a
  `legal-doc-shas.ts` re-pin and the `EXPECTED_COUNT` sentinel. None of the three is in
  `BODY_EQUIVALENCE_DOCS` (verified: `check-tc-document-sha.sh:130` enrolls only
  `terms-and-conditions`, `acceptable-use-policy`, `disclaimer`), so no body-equivalence check
  arrives — but the mirror-drift ratchet, the SHA pin and heading-parity all apply.
  **TC_VERSION: not required** — no T&C body edit.

**Sequencing.** It is cheaper to close the gap than to publish it. If the engineering fix (a
sign-phrase equality check before the write) lands before PR B, PR B discloses a *historic window*
rather than an ongoing practice, and its text is materially easier to write and to defend. **PR A
should not wait for either — the register records today's position today.**

### Ruling 6 — downstream consumers: none move

- **`article-30-register.md:28` (§0 DPO cell) — does NOT move.** Three independent reasons, any one
  sufficient. (a) Ruling 1 is "none sought; may arrive unsolicited", not a positive declaration of
  Art. 9 processing. (b) The cell's predicate is "**large-scale** processing of Art. 9/10 data"
  (Art. 37(1)(c)); the PA-7 signer population is two, and unsolicited arrival in a free-text field is
  not large-scale processing on any reading of WP243. (c) Dispositively: the register already carries
  "may arrive unsolicited" Art. 9 cells — PA-27, PA-31, PA-32 and PA-33 (**not** PA-35, whose cell
  reads a bare `None identified.`) — and the DPO cell has never moved for them. PA-7 joining that set
  changes nothing it did not already have to survive. [Count corrected at plan review; the argument is
  unaffected and if anything stronger at four cells than three.] The
  cell's own "re-assessed quarterly" is the mechanism that catches a scale change.
- **`compliance-posture.md:20` — does NOT move.** The #5363 entry, scoped to PA-2 `turn_summary`.
- **`compliance-posture.md:44` — does NOT move.** The #3988 entry recording that AUP §§4.7/4.8 were
  added; an accurate historical record of that PR. What Ruling 1 surfaces is that §4.7's *scope* does
  not reach the CLA path — a gap, not an error in line 44. That belongs as a **new Active Items
  row**, not an edit to line 44.
- **`audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md:88-92` — checked, does NOT
  move.** It cites §(c)'s enumeration to establish that this surface *does* process personal data.
  The widening strengthens that conclusion; it does not falsify it, and the ruling's holding does not
  turn on the enumeration being complete.
- **`legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md:261` — checked, does
  NOT move.** It quotes PA-7 limb (i), which Ruling 3 preserves verbatim for the signer arm. Line
  510's "CLA coverage — an open question" is untouched.

**Net: one addition** (a new Active Items row for the AUP §4.7 scope gap), **zero edits** to any
existing downstream statement.

### Re-evaluation triggers for the audit frontmatter

```yaml
re_evaluation_triggers:
  - "A sign-phrase equality check is added to the evidence-write path — would retire the non-signer arm of the Lawful basis cell, narrow the Categories of data subjects cell, and close the published-corpus gap prospectively. The historic window would still require disclosure."
  - "The realised contents of `soleur-cla-evidence` are measured (`apps/cla-evidence/scripts/inspect-evidence.sh`, Doppler `prd_cla`). This review rules on the capture predicate, which is a code fact; the archive's realised contents were NOT read and are recorded as UNKNOWN. Measurement decides the severity question — whether an incident occurred, and whether Art. 14 notice is owed to an over-captured commenter — not the register text."
  - "The `cla-evidence` workflow is wired to any repository that is not public, or `jikig-ai/soleur` ceases to be public. Art. 9(2)(e) is conditional on the comment being manifestly made public; `pr_of_record.repo` is unconstrained in the schema, so publicness is a present fact and not a structural invariant."
  - "A closed vocabulary is adopted for `override_reason` in `gdpr-override.sh` — would retire the second Art. 9 surface and the Art. 9(2)(f) reliance in the Special categories cell."
  - "A natural person other than `deruelle` is added to the CLA-action allowlist in `.github/workflows/cla.yml`, or `deruelle` is removed — moves the Categories of data subjects cell limb (ii)."
  - "First arms-length (non-Jikigai) contributor signs the CLA — carried forward from #7624. The first data subject of PA-7 who is not the operator, and the first reader of these cells with an adverse interest. This trigger also converts the 'accepted at present scale' residual in Special categories from a two-person posture into one requiring re-argument."
  - "Adoption of a retention ceiling at #7668 — this review does not decide it, but Ruling 1 supplies a new argument for it (an Art. 9 disclosure that only `gdpr-override.sh` can reach). Re-read Special categories when #7668 closes."
  - "AUP § 4.7 is re-scoped beyond the hosted chat surface — would supply the organisational control this path currently lacks, and would also bear on PA-35's citation of § 4.7 for repository submissions (flagged, not fixed, in this review)."
  - "External counsel re-review reserved for: first arms-length contributor, EEA-out, regulated industry, or any move from 'may arrive unsolicited' to a positive Art. 9 processing declaration."
```

### Standing caveat, to be carried into both audit records and the PR body

This is the v1 internal counsel-review attestation under the Soleur-as-tenant-zero posture, issued as
the attestation authority for a `single-user incident` threshold. It is draft material and is not a
substitute for external counsel, which is reserved for the frontmatter triggers above. The operator
retains a veto.

**Files the reviewing authority read for this advisory:**
`knowledge-base/legal/article-30-register.md` (PA-7 lines 152-164; precedent cells 28, 74, 242, 291,
540, 639, 658) · `knowledge-base/legal/compliance-posture.md` ·
`knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md` ·
`knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md` ·
`knowledge-base/legal/audits/2026-08-counsel-review-7100.md` · `.github/workflows/cla-evidence.yml` ·
`.github/workflows/cla.yml` ·
`apps/web-platform/scripts/cla-evidence/{schema.ts,build-record.ts,backfill.ts,allowlist-bypass.ts}` ·
`apps/cla-evidence/scripts/gdpr-override.sh` · `apps/web-platform/scripts/check-tc-document-sha.sh` ·
`docs/legal/{gdpr-policy.md,privacy-policy.md,data-protection-disclosure.md,acceptable-use-policy.md,individual-cla.md}` ·
`origin/cla-signatures:signatures/cla.json`.

---

## CLO Advisory — Addendum after plan review (2026-09-03)

A five-agent plan review found four gaps in the advisory above and they were sent back to the
reviewing authority rather than papered over here. **All four were confirmed against source; one was
a false statement the authority had itself introduced.** This addendum governs where it and the
advisory above disagree, and it is transcribed into `2026-09-counsel-review-7625.md` alongside it.

### A1 — Ruling 3's cell text carried a false cross-reference. Corrected clause.

Ruling 3's limb (iii) asserted that the field-level detail "sits in GDPR Policy § 3.4, Privacy Policy
§ 4.5 and DPD § 2.3(n), **which § 0 cross-references**". `docs/legal/individual-cla.md` §0 closes by
naming Privacy Policy §§4.5, 5.11 and 10 and GDPR Policy §§3.4 and 6 — **it does not reference the DPD
at all.** A false statement, landing in the very cell whose original defect was that it named no
mechanism, and the exact class of
`knowledge-base/project/learnings/2026-08-20-my-correction-pr-published-three-new-false-statements.md`.

Replace the limb-(iii) tail, from "the field-level detail" to the end of the limb, with:

```text
the field-level detail, including that the verbatim sign-comment body is retained, sits in Privacy Policy § 4.5 ("the bucket contains a content-addressed record per signature (doc-hash, verbatim sign-comment body, PR-of-record, signed_at, capture_method)") and GDPR Policy § 3.4, both of which § 0 cross-references — § 0 names Privacy Policy §§ 4.5, 5.11 and 10 and GDPR Policy §§ 3.4 and 6, and does **not** cross-reference the DPD, so DPD § 2.3(n) carries the same disclosure but is not part of the notice chain relied on in this limb;
```

**And the sharper consequence:** §5.11 *is* inside that notice chain, and §5.11 is where the false
"bypass records for allowlisted **bot accounts**" sentence lives (`privacy-policy.md:383`). A signer
following §0's own pointer is handed an incorrect statement about who the bypass path records. Fixing
§5.11 in PR B is **load-bearing for limb (iii)**, not cosmetic — say so in the PR B rationale.

**Standing instruction carried into `/work`:** re-read *every* cross-reference in the four cells
against the target document before the PR goes ready, not only this one.

### A2 — `(c) Categories of data subjects` WIDENING block, supplied verbatim

Appended at the end of the cell, before the terminating `|`, PA-7 local style:

```text
**[2026-09-03 WIDENING (#7625): this cell previously read "Individual contributors signing the ICLA; authorised signatories of corporations signing the CCLA." That named the population the activity was designed for and omitted three it actually processes. The evidence-record write step in `.github/workflows/cla-evidence.yml` gates on the persisting `license/cla` commit status and not on the content of the triggering comment, so any commenter on a green pull request becomes the `actor` of a record; the `allowlist/` path in the same workflow records natural persons named on the `.github/workflows/cla.yml` allowlist who sign nothing; and `apps/cla-evidence/scripts/gdpr-override.sh` records the operator and, via `gdpr_request_ref`, the subject of an erasure request. The under-inclusion is consequential rather than cosmetic: a categories-of-data-subjects cell determines who is owed Art. 13/14 transparency, who may bring an Art. 15 request, and who must be offered the Art. 21(1) objection route that Art. 6(1)(f) processing requires — and the two populations added at (i) and (ii) hold no account with Jikigai and appear in no published document. The additions were established by reading the workflow conditions in this review: they are a finding against the implementation, not the repair of a prior mis-statement, which is why this is a widening and not a correction. An Art. 30(1) record-keeping incompleteness is not an Art. 4(12) personal-data breach and triggers no Art. 33/34 notification. Recorded rather than silently repaired, per this register's amendment-history convention.]**
```

### A3 — PR A must carry a CORPUS DIVERGENCE block. Ruling 5 had a hole.

The block minted at #7601 exists for exactly this state, and with **#7669 deliberately unbuilt the
divergence would be undetectable rather than merely unrecorded.** **One block, on
`(c) Categories of data subjects`**, immediately after the WIDENING block — not two: the Lawful-basis
divergence follows from the same fact, and a divergence note in two cells is the marked/unmarked
hazard the #7100 `NARROWING` block calls out. Have the Lawful-basis CORRECTION block end with *"the
corpus divergence this creates is recorded at the `(c) Categories of data subjects` cell"* rather than
restating it.

```text
**[2026-09-03 CORPUS DIVERGENCE (#7625): `docs/legal/gdpr-policy.md` §3.4, `docs/legal/privacy-policy.md` §§4.5, 5.11 and 8.1, and `docs/legal/data-protection-disclosure.md` §2.3(n) all frame this archive as processing the data of contributors who sign, and disclose no population beyond them. Three of their statements are superseded by this cell and by "Lawful basis": (i) that an evidence record is written "for each signature" (DPD §2.3(n)) — it is written for any comment on a pull request whose `license/cla` status is green; (ii) that bypass records are for "allowlisted bot accounts (`dependabot[bot]`, `renovate[bot]`, `claude[bot]`)" (privacy-policy §5.11, DPD §2.3(n)) — the allowlist at `.github/workflows/cla.yml` also carries `deruelle`, a natural person, and `soleur-ai[bot]`, neither of which those enumerations name; and (iii) that Art. 6(1)(f) supports this archive without qualification (gdpr-policy §3.4) — it is unavailable for the non-signer fraction, which fails at necessity before balancing. Privacy Policy §8.1 additionally provides no Art. 21(1) route for the involuntary population identified above, while providing one for three comparable populations. The corpus correction is tracked at #<PR-B-issue>. Until that lands, this cell governs. Recorded here rather than left to the register-to-corpus sentinel, which is not built — that work is #7669.]**
```

**Do not land this with `#<PR-B-issue>` unsubstituted.** Mint the PR B issue in Phase 2 first and
write the real number — a divergence block whose tracking reference is unresolvable is worse than none, because it
reads as discharged-somewhere. This is a second, independent reason the filings phase runs before both the amendment and the sweep.

### A4 — PA-7 needs an `(h) DSAR` cell, and it belongs in PR A

PA-32 (`:626`) and PA-33 (`:645`) mint `(h)` cells precisely because they carry involuntary
populations; Ruling 2 mints one for PA-7. Leaving PA-7 without the cell invites a reader to assume it
shares PA-32's "not reachable, no completeness guarantee" posture — and **PA-7's answer is materially
better**, which is exactly why it must be written down rather than inferred:
`inspect-evidence.sh by-contributor` filtering on `.actor.login` is a real enumeration path over
`signatures/` that no PA-32/PA-33 surface has. The register cell goes in PR A; the §8.1 carve-out that
actually confers the route goes in PR B. The `(h)` count moves 8 → 9. No test asserts it —
`legal-doc-consistency.test.ts:195` reads the register only at a PA-15(c) anchor — so PR A trips
nothing. **The `(h)` cell is an addition and takes no amendment block: it states no prior position.**

```text
| **(h) DSAR (Art. 15 / 20)** | **Reachable, unlike PA-32 and PA-33 — and the difference is recorded rather than left to be assumed.** `DSAR_TABLE_ALLOWLIST` (`apps/web-platform/server/dsar-export-allowlist.ts`) enumerates **database tables** and reaches none of this activity's four record shapes, none of which is a table. But an **enumeration path exists** here where none exists over a git history or an issue body: `apps/cla-evidence/scripts/inspect-evidence.sh by-contributor <login>` filters `signatures/` records on `.actor.login`, so it reaches a non-signer commenter as readily as a signer; `by-pr` and `by-quarter` cover the other axes; shape (1) is a single public JSON file and is trivially enumerable; and shape (3) is keyed by principal (`allowlist/<principal>/<quarter>.json`), so it is enumerable by construction. **The honest Art. 15 route today** is a manual request to `legal@jikigai.com`, answered by running `inspect-evidence.sh by-contributor` against the archive and reading the public branch — an operator-only path requiring Doppler `prd_cla` credentials, with **no self-serve surface at `/dashboard/settings/privacy`**, because the subjects of this activity generally hold no Web Platform account. **One shape is not enumerable by its own subject:** the erasure tombstone (shape (4)) is keyed by `prior_object_sha` and by no subject identifier, so a person named in a tombstone's `gdpr_request_ref` cannot be found by searching for themselves — `inspect-evidence.sh tombstone <object-sha>` presupposes knowing the sha. **Art. 20 portability does not apply** to any shape: the lawful basis is Art. 6(1)(f), and Art. 20 is available only for processing grounded on Art. 6(1)(a) consent or Art. 6(1)(b) contract; that a signer authored the comment text does not change that. **Art. 21(1) right to object — mandatory for Art. 6(1)(f) processing, and currently absent for the involuntary population.** `docs/legal/privacy-policy.md` § 8.1 carries named carve-outs for community-digest subjects, departed workspace members, LinkedIn-published content and operator-assisted sessions, and carries **no CLA carve-out** — so a non-signer commenter or an allowlist-bypass principal, neither of whom holds an account with Jikigai, is offered no route anywhere in the published corpus. Same shape as the gap PA-32 and PA-33 record at **DEF-9** (#7126); tracked for the corpus at #<PR-B-issue>. **Art. 17 interaction:** the erasure route is `apps/cla-evidence/scripts/gdpr-override.sh` per §(f) and §(g). Note that honouring an erasure **creates** shape (4), which the §(g) floor then seals — an Art. 17 request against this activity cannot be fully unwound. |
```

### A5 — Four Active Items rows, not one and not three. No DPIA row.

Ruling 6 said one. Review argued three, on the PA-32 precedent. **The answer is four**, and the
acceptance criterion asserts that number.

| Row | Item | Finding | Remediation |
|---|---|---|---|
| 1 | PA-7 non-signer capture has **no available Art. 6 basis** — filter or cease | Ruling 3: Art. 6(1)(f) fails at necessity for any record whose `actor` signed nothing; no other basis available | The sign-phrase check (Phase 2 item 2). Direct analogue of **#7119** |
| 2 | PA-7 `comment_body` **Art. 9 ingress**: no filter, **and no organisational control** | Ruling 1 | Survives Row 1's fix — a strict-equality gate would bound it, a containment-style gate would not, and a signer's own comment can carry Art. 9 content alongside the required sentence. Record that AUP §4.7 does not reach this path, so unlike PA-27/32/33 there is **neither** a technical nor an organisational measure |
| 3 | PA-7 **published corpus does not disclose the non-signer population**; no Art. 21(1) route exists for it | Ruling 5(B) + A3 + A4 | PR B. This is the CORPUS DIVERGENCE block's referent. **Not contingent on measurement — a code fact** |
| 4 | PA-7 tombstone **`override_reason` free-text Art. 9 surface**, un-erasable by construction | Ruling 1's second surface | Distinct population (operator + requesting subject), distinct gateway (Art. 9(2)(f), not (2)(e) — the subject did not write it), distinct remediation (closed vocabulary). PA-32 got separate rows for separate remediations |

Each row carries its own `compliance/critical` issue from Phase 2, `Status: OPEN`, and a `check_id`.

**No DPIA row, and the reason is recorded so the count is not re-litigated.** PA-32 earned #7121
because its screening memo *concluded* a full DPIA was required. No such conclusion exists for PA-7
and this review expressly declines to reach Art. 35: the signer population is two, nothing is
systematic, and Art. 9 arrival is unsolicited rather than a purpose. **The hook instead:** if the
bucket measurement returns realised over-capture at any volume, the Art. 35 screening question
reopens.

**The bucket measurement is the severity determinant for Row 1, not a fifth row.** It decides whether
records exist, not whether the basis is available.

### A6 — accepted corrections to the advisory's own record

- **PR B scope additions endorsed, not merely unopposed:** `privacy-policy.md` §5.11 and §8.1. Ruling
  5(B)'s scope was incomplete. §5.11 is the higher priority of the two, per A1. No change is needed to
  `individual-cla.md` / `corporate-cla.md` §0 — neither enumerates fields or populations, and fixing
  §5.11 repairs what §0 points at.
- **Ten labels, not nine.** `TWO ITEMS RECORDED` at PA-1 §(e). The assignment is unaffected, but the
  count correction is itself recorded in the audit, because the vocabulary was cited as evidence for
  Ruling 4.
- **Ruling 4 now covers five blocks:** `WIDENING` on both §(c) cells, `CORRECTION` on Special
  categories and on Lawful basis, `CORPUS DIVERGENCE` on Categories of data subjects.
