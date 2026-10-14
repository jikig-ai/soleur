---
title: "compliance(art-28-3): three published Better Stack statements survive the NOT EXECUTED correction"
type: fix
date: 2026-10-14
slug: fix-better-stack-published-statements
branch: feat-one-shot-7851-better-stack-scc-wording
issue: 7851
closes: 7851
priority: p1-high
domain: legal
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-14
**Sections enhanced:** Implementation Phases, Dependencies & Risks, Observability
**Research agents used:** soleur-legal-clo (ruling applied); plan-review panel dhh, kieran, code-simplicity, devex CTO, and spec-flow; deepen batch of the 23 engineering review, research, and design agents, each of which returned an empty findings list on 2026-10-14.

### Key Improvements

1. Phase 1 success now fails if span 3 swallows or doubles the DPD semicolon, and if either privacy copy loses the Sentry sentence or the older #7529 sentence.
2. Phase 2 success hashes the full September 7 line and fails when the appended sentence is on the next line, including when all six files break at the same place.
3. `## Observability` names the existing corpus probe as the local signal, because `legal-doc-shas.ts` sits under `apps/web-platform/lib/legal/` and the pure-docs skip does not apply.

### New Considerations Discovered

- `CORPUS-OK` does not prove the appended sentence stayed on the September 7 line. The note hash is a separate check.
- Precedent for this edit is the 2026-09-07 six-file identical note plus the SHA refresh of the canonicals that note touches. No new scheduled job, lock, or SQL function.
- Deepen gates 4.5, 4.55, 4.8, 4.9, 4.10, and 4.11 did not fire. 4.6, 4.7, and 4.12 are satisfied by the sections in this file. 4.45 found no `NEVER` / `MUST NOT` / `does not reach` / `cannot leak` / `is not exposed` claim to verify. The 23-agent deepen batch added no further edit. `tasks.md` already carries the span-3 join, the one-line note hash, and the corpus probe, so this pass did not change it.

## Overview

Issue #7851 asked to stop the published privacy policy and data-protection disclosure from describing a Better Stack processor agreement the controller does not hold. Two of the three statements named in that issue are already gone from the canonical copies and the Eleventy mirrors: the corpus no longer says the log stream flowed under processor-DPA terms, and it no longer cites a paid-tier retention default. What remains is the claim that Standard Contractual Clauses are incorporated into the Better Stack data-processing agreement, next to an instrument the Vendor DPA Status row records as not executed. Signing of that instrument stays an open action on #7529.

This plan retracts that incorporation claim in the privacy policy and the data-protection disclosure, on both the canonical copies under `docs/legal` and the Eleventy mirrors under `plugins/soleur/docs/pages/legal`. It extends the shared 7 September 2026 correction note on all six published surfaces so the note also names this retraction, and the six notes stay byte-identical. The GDPR policy does not carry the incorporation sentence and does not gain one; it receives only the shared note extension. The change does not draft or execute a vendor agreement, does not close #7529, does not reopen the already-published 90-day retention figure or the Article 30 `logs_retention` row, and does not bump the terms version. Every canonical file whose bytes change is re-pinned in the legal-document SHA map in the same change.

## Research Reconciliation — Spec vs. Codebase

The issue body still describes three live published statements. Measured on `origin/main` on 2026-10-14, two of those literals are already gone. The plan follows the corpus, not the stale issue table.

| Spec claim | Reality on origin/main | Plan response |
|---|---|---|
| DPD §2.3(m) still says the stream flowed "under processor-DPA terms" | `git grep` count of that literal under `docs/legal` and `plugins/soleur/docs/pages/legal` is 0 | Do not reintroduce it. No edit targets it |
| Both notices still cite a Better Stack "paid-tier default" retention | `git grep` count of `paid-tier default` on those trees is 0. The privacy-policy retention bullet for this stream already says **90 days** | Do not reopen retention or `logs_retention` |
| Privacy §5.14 still says the Better Stack DPA has SCCs incorporated as belt-and-braces | Present. Canonical `docs/legal/privacy-policy.md` around the §5.14 DPA bullet and the processing-location bullet; the Eleventy mirror carries the same two sentences | Replace those two spans with the CLO strings below |
| The same incorporation claim is the published Art. 46 statement | Also present in DPD prose and in the DPD processor table, canonical and mirror: `SCCs incorporated as belt-and-braces` (4 hits) and `SCCs incorporated belt-and-braces` (2 hits) | Replace those two spans as well |
| GDPR policy needs the same SCC sentence | GDPR canonical and mirror have no Better Stack "SCCs incorporated" / "available for execution" sentence | Do not invent one. GDPR changes only by the shared note |

## Research Insights

### Premise Validation

Checked before the fan-out, against `origin/main` and GitHub, not against the issue body's memory. #7851 is OPEN and is not closed by a pull request. #7529 is OPEN. Draft PR #10291 is open against this branch. The literals `under processor-DPA terms` and `paid-tier default` are absent from the three published documents and their mirrors. Privacy and the data-protection disclosure already say the Better Stack DPA is "available for execution" and point at #7529. The GDPR policy does not carry that sentence. Published retention beside the Better Stack block is already 90 days. The six notes that start `**Corrected September 7, 2026 (#7786 / #6474).**` are byte-identical (sha256 prefix `3451ec53d4dfb514`, 781 bytes, one physical line) and name the off-host and json-file retractions only. No architecture decision in `knowledge-base/engineering/architecture/decisions/` rejects extending that shared note. ADR-269 mentions Standard Contractual Clauses for inbound email routing, not for this Better Stack instrument. Held: the residual false claim is the incorporation sentence next to an unexecuted instrument.

### Property List

1. Privacy and the data-protection disclosure, canonical and mirror, do not assert that Standard Contractual Clauses are incorporated into the unexecuted Better Stack DPA.
2. The six 2026-09-07 notes name this retraction and stay byte-identical.
3. The GDPR policy body does not gain an SCC sentence. Its only edit is the shared note.
4. #7529 stays open. No DPA is drafted or executed.
5. The 90-day retention figure and the Article 30 `logs_retention` row stay.
6. Each edited canonical is re-pinned from `sha256sum` of that file. `TC_VERSION` in `apps/web-platform/lib/legal/tc-version.ts` stays `2.6.0`.
7. Canonical-to-mirror drift does not grow. `Last Updated` lines are not edited.
8. `closes:` is only 7851.

### Cut List

- A new `FORBIDDEN` entry for `SCCs incorporated` in `scripts/probe_legal_corpus_truth.py`. The ask did not name a new guard. The probe's current list does not contain that literal. A bare forbid would also red the true Sentry sentence `(Sentry's standard EU-region terms; SCCs incorporated).` Property 1 is bought by editing the four Better Stack spans.
- An edit to `knowledge-base/legal/compliance-posture.md` or `knowledge-base/legal/article-30-register.md`. Both already record NOT EXECUTED and 90 days. The ask is to align the published sentences with that record.
- A new dated correction note. The ask is to extend the shared 7 September 2026 note. A per-document note would break the mirror-drift ratchet's byte-identity of that line.
- An edit to any `Last Updated` line. Those lines already drift (#7465). `scripts/lint-legal-mirror-drift-baseline.sh` fails an in-place edit of an already-drifting line.
- Signing or drafting the vendor DPA, and closing #7529. The ask forbids both.
- An SCC sentence added to the GDPR policy. The ask forbids it.
- Editing Sentry's "SCCs incorporated" sentence. Different vendor, different instrument.
- Re-opening `under processor-DPA terms` or `paid-tier default`. Both are already absent.

### Repo paths

- False spans, privacy canonical: `docs/legal/privacy-policy.md` DPA bullet (`is available for execution under standard EU-region terms (SCCs incorporated as belt-and-braces against any future routing change).`) and the processing-location sentence (`Standard Contractual Clauses are incorporated as belt-and-braces against any future routing change.`). Mirror: `plugins/soleur/docs/pages/legal/privacy-policy.md`, same substrings. Sentry's incorporation sentence in the same files stays.
- False spans, DPD canonical: `docs/legal/data-protection-disclosure.md` prose `The Better Stack DPA is available for execution under standard EU-region terms (SCCs incorporated as belt-and-braces)` and table cell `available for execution under standard EU-region terms (SCCs incorporated belt-and-braces).` Mirror: `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`.
- Shared note line, one physical line, all six files listed under Files to Edit. Probe stripper in `scripts/probe_legal_corpus_truth.py` matches a line-leading `**Corrected|Updated <date>**` paragraph and refuses the strip if a blank line sits inside the note. `DOCUMENTED_NOTE_SHAPES` includes the `**Corrected September 7, 2026 (#7786 / #6474).**` prefix. Keep that prefix. Append with one space. Do not insert a newline.
- SHA map: `apps/web-platform/lib/legal/legal-doc-shas.ts` (`LEGAL_DOC_SHAS`). Guard: `apps/web-platform/scripts/check-tc-document-sha.sh` (name is historical; it pins all nine canonical docs). Non-T&C docs have no `TC_VERSION` bypass. Body-equivalence CI covers terms, AUP, and disclaimer only.
- Heading and `Last Updated` date-token parity: `apps/web-platform/test/legal-doc-consistency.test.ts`. The comment near the #7624 block says two byte-identical copies of a false sentence pass the hash, heading, and drift gates, and that a correction marker for that block must paraphrase the superseded sentence rather than quote it. This retraction is a different proposition. The new note sentence paraphrases; it does not paste `SCCs incorporated`.
- Drift ratchet: `scripts/lint-legal-mirror-drift-baseline.sh`. The six notes are identical today, so they are not in the drift set. An identical edit on both sides of each pair does not grow drift.
- Eleventy: the mirrors are committed markdown. A search of `plugins/soleur/docs` for a generator of `pages/legal` in js, njk, or json returned no match. The implementer edits both sides by hand. No Eleventy filter and no Next.js route is part of this change.
- Posture row to read and not edit: `knowledge-base/legal/compliance-posture.md` Better Stack status `NOT EXECUTED — no Art. 28(3) instrument recorded`, transfer mechanism `N/A (intra-EU; CZ establishment → vendor EU region eu-central-1a)`, signing #7529.
- Version policy: `knowledge-base/legal/tc-version-bump-policy.md`. A `TC_VERSION` bump applies when `docs/legal/terms-and-conditions.md` is edited. This change does not edit that file. Current `TC_VERSION` is `2.6.0`. SHA refresh is not a version bump.
- Glossary: "Ratchet" is a pinned number that may only move in the reducing direction. Do not use "register" alone; the compliance sense is `knowledge-base/legal/*-register.md`.

### Learnings that bind the edit

- `knowledge-base/project/learnings/2026-08-20-my-correction-pr-published-three-new-false-statements.md` — a correction can publish a new falsehood: an unscoped restatement, a claim about a sibling document, or a warranty created by deletion. Do not say the GDPR policy previously stated the incorporation. Do not describe the unread vendor template. Enumerate claims, not files.
- `knowledge-base/project/learnings/2026-09-07-i-widened-the-sentence-and-left-its-clauses-behind.md` — a correction note that contains a forbidden literal trips the probe, and anchors must be asserted on every file before any write. The September 7 prefix must still match `DOCUMENTED_NOTE_SHAPES`.
- `knowledge-base/project/learnings/2026-09-04-every-verification-i-wrote-passed-and-three-of-them-proved-nothing.md` — the mirror-drift gate blocked a `Last Updated` bump on the published notices.
- `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md` — a pin is a measurement. Recompute `LEGAL_DOC_SHAS` from the file bytes. Do not copy a hash from this plan.
- `knowledge-base/project/learnings/2026-05-29-legal-doc-triple-lockstep-and-rpc-grants-invoker-before-definer.md` — the SHA pin and the Eleventy mirror live in different trees and both move in the same change.

### External research and agent status

Data-privacy notices are high-risk, so external research was in scope. The best-practices pass that returned prose (first spawn) stated the impact at name level: leaving the incorporation sentence in place states an Article 46 safeguard the controller's record does not have; because the recorded transfer is intra-EU, that safeguard sentence is not required; an unexecuted data-processing agreement is not the Article 28(3) instrument, so the notice cannot describe it as having incorporated the clauses. The notice keeps non-execution and does not itself become the contract.

The second spawn of `soleur-engineering-cto`, `soleur-engineering-research-repo-research-analyst`, `soleur-engineering-research-learnings-researcher`, `soleur-engineering-discovery-functional-discovery`, `soleur-engineering-research-best-practices-researcher`, and `soleur-engineering-research-framework-docs-researcher` exited on max turns after a preamble. Status: error. Findings above are from the worktree measurement and from the learnings files named. Functional overlap from that measurement: nothing already retracts the Better Stack incorporation sentence. The September 7 note is silent on it, and #7529 tracks signing rather than the published wording.

`soleur-legal-clo` returned a binding ruling on 2026-10-14 (`stricter-than-B`). It is recorded in `knowledge-base/project/specs/feat-one-shot-7851-better-stack-scc-wording/decision-challenges.md` and applied in Proposed Solution. The CLO's extra clause "Leave #7851 and #7529 open" is not applied to #7851; see the operator (scope) row. #7529 stays open, which matches both the CLO and the brief.

### Conventions

`CLAUDE.md` points at `AGENTS.md`. No skill `description:` edit is in this change, so the skill-description budget check does not run.

### Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` (93 issues) was searched with standalone `jq --arg` for each path in Files to Edit. No issue body contains those paths.

## Problem Statement / Motivation

A data subject who reads the privacy policy or the data-protection disclosure is told that Standard Contractual Clauses are incorporated into the Better Stack DPA. The Vendor DPA Status row says that instrument is not executed and that signing is outstanding at #7529. Those are two answers to one Article 28(3) question, on the surface the data subject actually reads. The internal registers were corrected earlier. This change corrects the published sentences and says so in the shared correction note.

## Proposed Solution

Ruled by CLO agent, 2026-10-14: stricter-than-B. On the privacy policy and the data-protection disclosure only, replace the incorporation claim with an explicit negative that does not use a causal "because". Keep "available for execution" and keep the existing signing pointer. State that no Standard Contractual Clauses are in force, that no Article 28(3) instrument is executed, and that signing remains open at #7529. Do not describe the unread vendor template, do not assert that execution would incorporate the clauses, and do not convert the intra-EU N/A transfer record into a third-country transfer. Append one corpus-level sentence to the existing September 7 note on all six surfaces.

Dissent recorded by the CLO, and not adopted: a narrower negative limited to "not incorporated into an executed Better Stack DPA" would also be accurate if some other vehicle already bound the parties. No other executed SCC instrument for this stream is in the evidence, and the posture transfer cell is N/A, so the broader negative stands.

Rejected: deleting the parenthetical only (leaves the Art. 46 retraction in a footer); a "because the instrument is not executed" that can be read as a claim about what the unread template contains; describing the vendor template as containing SCC text.

### Exact substitutions

Assert each old substring on both the canonical file and the mirror before writing. Each old substring occurs on those two copies and nowhere else that this plan edits.

1. Privacy DPA bullet, both copies. Old: `is available for execution under standard EU-region terms (SCCs incorporated as belt-and-braces against any future routing change).` New: `is available for execution under standard EU-region terms (no Standard Contractual Clauses are in force; no Article 28(3) instrument is executed, and signing remains open at issue #7529).` The following sentence stays verbatim on both privacy copies: ``The Vendor DPA Status table in `knowledge-base/legal/compliance-posture.md` tracks the signing state; signing is an open action tracked at **#7529** and will be reflected here on completion.`` The new parenthetical's "issue #7529" does not replace that sentence.
2. Privacy processing-location sentence, both copies. Old: `Standard Contractual Clauses are incorporated as belt-and-braces against any future routing change.` New: `No Standard Contractual Clauses are in force; no Article 28(3) instrument is executed, and signing remains open at issue #7529.`
3. DPD prose, both copies. Old: `The Better Stack DPA is available for execution under standard EU-region terms (SCCs incorporated as belt-and-braces)` New: `The Better Stack DPA is available for execution under standard EU-region terms (no Standard Contractual Clauses are in force; no Article 28(3) instrument is executed, and signing remains open at issue #7529)` The new string has no terminal semicolon. The character immediately after the new closing parenthesis stays `;`, and the clause after that semicolon stays verbatim: ``the Vendor DPA Status table in `knowledge-base/legal/compliance-posture.md` tracks the signing state, an open action tracked at **#7529**.``
4. DPD table cell, both copies. Old: `available for execution under standard EU-region terms (SCCs incorporated belt-and-braces).` New: `available for execution under standard EU-region terms (no Standard Contractual Clauses are in force; no Article 28(3) instrument is executed, and signing remains open at issue #7529).`

### Shared note sentence

On all six files, append this sentence after one space on the existing one-line September 7 note. Do not add a newline. Do not change the `**Corrected September 7, 2026 (#7786 / #6474).**` prefix or the existing #7465 parenthetical.

`The privacy policy and the data-protection disclosure previously stated that Standard Contractual Clauses were incorporated into the Better Stack DPA; that instrument is not executed, so that incorporation is retracted, the GDPR policy did not carry that sentence, and this correction does not attribute Standard Contractual Clauses to any unread vendor template.`

After the append, the six note lines are byte-identical to each other. The GDPR policy's operative sections do not gain an SCC sentence; the note is the only GDPR edit, and that edit is what makes the GDPR canonical hash move.

### What the implementer does not do

- Does not edit any `Last Updated` line.
- Does not edit `(Sentry's standard EU-region terms; SCCs incorporated).` or any other vendor's transfer sentence.
- Does not edit `knowledge-base/legal/compliance-posture.md`, `knowledge-base/legal/article-30-register.md`, `docs/legal/terms-and-conditions.md`, or `apps/web-platform/lib/legal/tc-version.ts`.
- Does not add a probe pattern, a new guard, an ADR, or a C4 diagram.
- Does not draft or execute a contract, and does not close #7529.
- Does not copy the pre-change hashes from Research Insights or from memory. The hashes on origin/main will not match the edited files.

## Implementation Phases

### Phase 1: Retract the four spans

Edit the four old substrings in the privacy policy and the data-protection disclosure, canonical and mirror, using the CLO strings. Leave every other sentence in those bullets in place, including the 90-day retention bullet and the intra-EU processing sentence that precedes span 2.

Span 3 is a substring replace. The CLO string ends at `issue #7529)` and must not gain a semicolon. The existing `;` and the Vendor DPA Status clause that already follow the old substring stay attached. A replace that swallows that semicolon, or that writes a second one, detaches or doubles the following clause and still leaves the old substring absent.

Success: `git grep` of each old substring under `docs/legal` and `plugins/soleur/docs/pages/legal` is empty. `git grep` of `Sentry's standard EU-region terms; SCCs incorporated` still hits in both `docs/legal/privacy-policy.md` and `plugins/soleur/docs/pages/legal/privacy-policy.md`. Both privacy copies still contain `signing is an open action tracked at **#7529** and will be reflected here on completion.` Both DPD copies contain `open at issue #7529); the Vendor DPA Status table` exactly once, and neither contains `issue #7529);;` or `issue #7529;);`.

### Phase 2: Extend the six notes

Append the shared sentence to all six September 7 notes after one space on the existing physical line. Do not insert a newline between the September 7 prefix and the end of the appended sentence. Hashing only the prefix, or hashing a following line, is not the check.

Success: each of the six files has exactly one physical line that starts with `**Corrected September 7, 2026 (#7786 / #6474).**`, and that same line contains the appended sentence after exactly one space, with no newline and no blank line between the prefix and the end of the sentence. The six sha256 digests are of those full lines and are equal. A prefix line that does not contain the appended sentence is a phase failure, including when all six files break at the same place. `CORPUS-OK` is a separate gate and does not prove the sentence stayed on the prefix line.

### Phase 3: Re-pin the three canonical hashes

Run `sha256sum` on `docs/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md`, and `docs/legal/gdpr-policy.md`. Write those three digests into the matching keys of `LEGAL_DOC_SHAS`. Do not edit the other six keys. Do not edit `TC_VERSION`.

Success: `apps/web-platform/scripts/check-tc-document-sha.sh` passes, and `git diff` of `tc-version.ts` is empty.

### Phase 4: Prove the non-touches

Run `bash scripts/probe-legal-corpus-truth.sh` and expect `CORPUS-OK`. Run `scripts/lint-legal-mirror-drift-baseline.sh` and expect the drift set not to grow. Confirm `under processor-DPA terms` and `paid-tier default` are still absent. Confirm #7529 is still open (`gh issue view 7529 --json state`).

## Technical Considerations

- Architecture: no ADR and no C4 change. The published-claim correction does not change a system structure. ADR-222, ADR-218, and ADR-269 mention Better Stack or Standard Contractual Clauses in other roles and are not edited. A reader of those ADRs is not told that this DPA is executed.
- Performance: none. The diff is prose plus three hash literals.
- Security: the false Art. 46 sentence is the defect. The replacement does not add a safeguard the controller does not hold, and it does not remove the intra-EU statement or the signing pointer.
- NFR register: no runtime behavior changes, so no NFR row moves. `soleur:architecture assess` is not required for a notice-text correction.
- Attack surface: not a security-boundary fix. No new read, network, or exec path.
- Lockstep: canonical markdown, Eleventy mirror, and `LEGAL_DOC_SHAS` move together. The probe and the drift ratchet are existing gates; this plan does not author a new one.
- The GDPR hash moves because the shared note moves, even though no operative GDPR sentence is added. Forgetting that third key fails `check-tc-document-sha.sh`.
- Skill-description budget: no `SKILL.md` description edit.

## Files to Edit

- `docs/legal/privacy-policy.md` — spans 1 and 2, and the September 7 note
- `docs/legal/data-protection-disclosure.md` — spans 3 and 4, and the September 7 note
- `docs/legal/gdpr-policy.md` — September 7 note only
- `plugins/soleur/docs/pages/legal/privacy-policy.md` — the same privacy edits as the canonical
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — the same DPD edits as the canonical
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` — September 7 note only
- `apps/web-platform/lib/legal/legal-doc-shas.ts` — three keys: `privacy-policy`, `data-protection-disclosure`, `gdpr-policy`

## Files to Create

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** the public privacy policy or data-protection disclosure still says Standard Contractual Clauses are incorporated into a Better Stack agreement the controller records as not executed, or the correction note disagrees across the six published copies.
- **If this leaks, the user's data is exposed via:** no new flow. The existing log stream is already disclosed. A wrong retraction would misstate the transfer basis to the population of people whose log lines are in that stream.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the false Art. 46 sentence is on the public notice read by the population of log subjects. This pull request corrects that notice. It is not a new single-user data incident, so `requires_cpo_signoff` is not set.

A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.

## Observability

`apps/web-platform/lib/legal/legal-doc-shas.ts` is production code under `apps/`, so the pure-docs skip does not apply. This change adds no runtime service. The signal is the existing corpus probe, which prints a line Check 10 can match. The SHA script exits 0 with no stdout on success, so it is a failure detector and not the discoverability command.

```yaml
liveness_signal:
  what: "CORPUS-OK line from scripts/probe-legal-corpus-truth.sh"
  cadence: per-run
  alert_target: "CI failure of the corpus probe and of apps/web-platform/scripts/check-tc-document-sha.sh"
  configured_in: scripts/probe-legal-corpus-truth.sh
error_reporting:
  destination: "stdout of the corpus probe and stderr of the legal-doc SHA script; this change adds no Sentry event"
  fail_loud: "the probe exits non-zero, or check-tc-document-sha.sh prints ::error:: and exits 1"
failure_modes:
  - mode: "a LEGAL_DOC_SHAS key does not match sha256sum of an edited canonical"
    detection: "apps/web-platform/scripts/check-tc-document-sha.sh prints ::error:: and exits 1"
    alert_route: "workflow run log of the CI job that runs that script"
  - mode: "the September 7 note gains a newline and the stripper stops before the appended sentence"
    detection: "scripts/probe-legal-corpus-truth.sh exits non-zero, and the six-line hash check fails when the sentence leaves the prefix line"
    alert_route: "workflow run log of the CI job that runs the probe"
logs:
  where: "stdout of scripts/probe-legal-corpus-truth.sh"
  retention: "CI log retention for the job that runs the probe; this change adds no log store"
discoverability_test:
  command: bash scripts/probe-legal-corpus-truth.sh
  expected_output: CORPUS-OK
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "[issue #7851] Amend the three statements, mirror to `plugins/soleur/docs/pages/legal/**`, re-run the three-way lockstep, re-pin `apps/web-platform/lib/legal/legal-doc-shas.ts`, and check `TC_VERSION` under `knowledge-base/legal/tc-version-bump-policy.md`." | Phases 1–4; Files to Edit | mapped |
| 2 | "[issue #7851] data flowed post-2026-05-21 \"under processor-DPA terms\"" | Phase 4 absence check | mapped |
| 3 | "[issue #7851] Better Stack DPA … available for execution under standard EU-region terms (**SCCs incorporated** as belt-and-braces)" | Phase 1 spans 1–4 | mapped |
| 4 | "[issue #7851] **Retention:** Better Stack paid-tier default for journald + host_metrics" | Phase 4 absence check; retention bullet not edited | mapped |
| 5 | "[brief] Align those published sentences with the unexecuted state." | Phase 1 | mapped |
| 6 | "[brief] Extend the shared 2026-09-07 correction note on all six published surfaces so it also names this retraction, and keep the six notes byte-identical." | Phase 2 | mapped |
| 7 | "[brief] Do not execute or draft a vendor contract." | Proposed Solution, non-touches | mapped |
| 8 | "[brief] Do not close the open signing-action issue." | #7529 left open; `closes:` is 7851 only | mapped |
| 9 | "[brief] Check the terms-version bump policy and do not bump a version file." | Phase 3 leaves `tc-version.ts` at 2.6.0 | mapped |
| 10 | "[brief] GDPR policy does not currently carry the SCC sentence. Do not invent one." | GDPR file: note only | mapped |
| 11 | "[brief] Published retention for this stream is already \"90 days\", matching the Article 30 register's measured logs_retention. Do not reopen that row." | Phase 1 leaves the 90-day bullet; article-30 file not in Files to Edit | mapped |
| 12 | "[brief] Close open issue #7851 only." | frontmatter `closes: 7851` and `issue: 7851` | mapped |
| 13 | "[brief] The six September 7 correction notes are byte-identical and name two retractions (off-host shipping, json-file retention) and are silent on this SCC/instrument retraction. A per-document note breaks the mirror-drift ratchet. Any fix extends all six identically or moves the disclosure somewhere the ratchet does not compare." | Phase 2 identical append | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 four-span replacement | "What remains false is \"SCCs incorporated\" / \"Standard Contractual Clauses are incorporated\" next to an instrument the controller records as not executed." | asked |
| Phase 2 six-note append | "Extend the shared 2026-09-07 correction note on all six published surfaces so it also names this retraction, and keep the six notes byte-identical." | asked |
| Phase 3 SHA refresh of three canonicals | "re-pin `apps/web-platform/lib/legal/legal-doc-shas.ts`" | asked |
| Phase 3 no TC_VERSION bump | "do not bump a version file" | asked |
| Phase 4 absence checks for the two already-gone literals | "The older literals \"under processor-DPA terms\" and \"paid-tier default\" are already absent from the three published documents." | asked |
| `docs/legal/privacy-policy.md` and its mirror | "the canonical copies under docs/legal and the Eleventy mirrors under plugins/soleur/docs/pages/legal" | asked |
| `docs/legal/data-protection-disclosure.md` and its mirror | "the canonical copies under docs/legal and the Eleventy mirrors under plugins/soleur/docs/pages/legal" | asked |
| `docs/legal/gdpr-policy.md` and its mirror | "Extend the shared 2026-09-07 correction note on all six published surfaces" | asked |
| `apps/web-platform/lib/legal/legal-doc-shas.ts` | "Legal-doc lockstep and the SHA pin apply." | asked |
| Leaving #7529 open and not drafting a DPA | "Do not execute or draft a vendor contract. Do not close the open signing-action issue." | asked |

### Split Assessment

- Subsystems touched: 3 — `docs`, `plugins/soleur`, `apps/web-platform`
- Planned files: 7 | Estimated changed lines: 40
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

Copy these five strings byte for byte. Span 3 has no terminal semicolon. The note sentence is appended after one space and is not a new paragraph.

```text
is available for execution under standard EU-region terms (no Standard Contractual Clauses are in force; no Article 28(3) instrument is executed, and signing remains open at issue #7529).
No Standard Contractual Clauses are in force; no Article 28(3) instrument is executed, and signing remains open at issue #7529.
The Better Stack DPA is available for execution under standard EU-region terms (no Standard Contractual Clauses are in force; no Article 28(3) instrument is executed, and signing remains open at issue #7529)
available for execution under standard EU-region terms (no Standard Contractual Clauses are in force; no Article 28(3) instrument is executed, and signing remains open at issue #7529).
The privacy policy and the data-protection disclosure previously stated that Standard Contractual Clauses were incorporated into the Better Stack DPA; that instrument is not executed, so that incorporation is retracted, the GDPR policy did not carry that sentence, and this correction does not attribute Standard Contractual Clauses to any unread vendor template.
```

- [ ] Privacy policy and data-protection disclosure, canonical and mirror, no longer contain `SCCs incorporated as belt-and-braces` or `SCCs incorporated belt-and-braces` or `Standard Contractual Clauses are incorporated as belt-and-braces`.
- [ ] Those four sites instead contain the CLO replacement strings, including "available for execution" on the DPA bullets and table cell, and "no Standard Contractual Clauses are in force" with signing still pointed at #7529. Span 3's replacement ends at `issue #7529)` with no semicolon of its own. Both data-protection disclosure copies contain `open at issue #7529); the Vendor DPA Status table` exactly once, and neither contains `issue #7529);;` or `issue #7529;);`. Both privacy copies still contain `signing is an open action tracked at **#7529** and will be reflected here on completion.`
- [ ] Both `docs/legal/privacy-policy.md` and `plugins/soleur/docs/pages/legal/privacy-policy.md` still contain `Sentry's standard EU-region terms; SCCs incorporated`. The negative greps stay on the longer Better Stack belt-and-braces strings, so that Sentry sentence is not a replace target.
- [ ] Each of the six files has exactly one physical line that starts `**Corrected September 7, 2026 (#7786 / #6474).**`. That same line contains, after exactly one space, the CLO sentence that the privacy policy and the data-protection disclosure previously stated the incorporation, that the GDPR policy did not carry that sentence, and that the correction does not attribute clauses to an unread vendor template. There is no newline and no blank line between the prefix and the end of that sentence. The six sha256 digests are of those full lines and are equal.
- [ ] `git diff --unified=0 origin/main...HEAD -- docs/legal/gdpr-policy.md plugins/soleur/docs/pages/legal/gdpr-policy.md` changes only the line that starts `**Corrected September 7, 2026 (#7786 / #6474).**` in each file. A hit for the shared sentence on that line is required. It is not a body defect, and deleting it on the GDPR copies alone breaks the six-note identity.
- [ ] `git grep` of `under processor-DPA terms` and `paid-tier default` is still empty when the path is limited to `docs/legal` and `plugins/soleur/docs/pages/legal`. Do not widen that grep to the plan file: this plan quotes those literals as the things already absent. The Better Stack retention bullet still says 90 days. `git diff --quiet origin/main...HEAD -- knowledge-base/legal/article-30-register.md knowledge-base/legal/compliance-posture.md` exits 0 (three-dot, so a sibling merge on main does not fail the branch).
- [ ] `LEGAL_DOC_SHAS` for `privacy-policy`, `data-protection-disclosure`, and `gdpr-policy` equals `sha256sum` of the edited canonical files. The other six keys are unchanged. `TC_VERSION` is still `2.6.0` and `tc-version.ts` is not in the diff.
- [ ] No `Last Updated` line changes. `bash scripts/probe-legal-corpus-truth.sh` prints `CORPUS-OK`. The mirror-drift ratchet does not gain a new drifting line from this edit.
- [ ] The pull request closes #7851 and does not close #7529. #7529 is still open after merge. No vendor contract text is added.

## Domain Review

**Domains relevant:** Legal, Engineering

Fresh assessment against the eight domain questions, with no brainstorm carry-forward. Legal matches: the work updates published privacy notices and a processor-agreement statement. Engineering is the fail-closed second leader, scoped to the SHA pin, the drift ratchet, and the probe, not to the legal wording. Product does not match: Files to Edit and Files to Create contain no UI-surface path (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or the shared UI-term list). Marketing does not match: the text is a statutory notice, not a campaign or value-proposition change. Finance, Sales, Operations, and Support do not match.

**Brainstorm-recommended specialists:** none. No brainstorm document.

### Legal

**Status:** reviewed
**Assessment:** `soleur-legal-clo` ruled stricter-than-B on 2026-10-14. The published belt-and-braces sentence stated that an Article 46 safeguard was already incorporated. The measured posture is the opposite: the instrument is not executed, signing remains #7529, and the transfer-mechanism cell is N/A for an intra-EU path, so a Chapter V safeguard sentence is not the recorded basis. The replacement keeps the availability statement, retracts the incorporation, and does not describe the unread template. The shared note is corpus-level so it stays true on the GDPR copies. Evidence that would flip the ruling is a hash-pinned vendor template actually read in this matter, or a signature record of an executed Article 28(3) instrument. Neither is in the evidence. The correction does not execute a contract and does not close #7529.

### Engineering

**Status:** error
**Assessment:** The research spawn of `soleur-engineering-cto` returned no decision (max turns, preamble only). Planner measurement, not a CTO ruling: no ADR states a Better Stack SCC mechanism that this wording would contradict; the SHA pin is `sha256sum` of the canonical file and is not a `TC_VERSION` bump; a new bare `SCCs incorporated` forbid would red the Sentry sentence; identical edits to the six currently identical notes do not grow mirror drift; `Last Updated` lines must not be edited. The assumed stricter default is recorded in decision-challenges.md. The later plan-review devex spawn completed with an empty findings list. That empty list is not an architecture ruling.

### Product/UX Gate

Not run. Product domain was not flagged, and the mechanical UI-surface override did not fire. No `.pen` is required.

## Test Scenarios

- unit: Given the six published files after the edit, when a script hashes the one physical line in each file that starts with `**Corrected September 7, 2026 (#7786 / #6474).**` and also contains the appended sentence after exactly one space, then the six digests are equal. A prefix line that does not contain that sentence fails. `CORPUS-OK` does not substitute for this check.
- unit: Given `docs/legal/privacy-policy.md` and `plugins/soleur/docs/pages/legal/privacy-policy.md`, when searched for `SCCs incorporated as belt-and-braces`, then there is no hit, and when searched for `Sentry's standard EU-region terms; SCCs incorporated`, then both files still hit.
- unit: Given `git diff --unified=0 origin/main...HEAD` limited to `docs/legal/gdpr-policy.md` and `plugins/soleur/docs/pages/legal/gdpr-policy.md`, when the hunks are read, then each file's only changed line is the September 7 note, and that line still contains the shared sentence.
- integration: Given the three edited canonicals, when `sha256sum` is compared with the three `LEGAL_DOC_SHAS` entries, then they match, and `bash apps/web-platform/scripts/check-tc-document-sha.sh` exits 0. `sha256sum` is GNU coreutils 9.11 on this machine (`sha256sum --version`).
- integration: Given the worktree, when `bash scripts/probe-legal-corpus-truth.sh` runs, then stdout contains `CORPUS-OK`.
- integration: Given the worktree against the merge base, when `scripts/lint-legal-mirror-drift-baseline.sh` runs, then it exits 0.
- integration: Given `gh issue view 7529 --json state`, when the field is read, then it is `OPEN`. This scenario reads GitHub; it is not a property of a sibling worktree's ambient build.

No browser scenario. The pages are committed markdown, and the gates above read those bytes. The replacement text in these scenarios is the fenced block under Acceptance Criteria, copied byte for byte.

## Success Metrics

- The four Better Stack incorporation spans are gone from both published trees, and the Sentry sentence remains.
- The six September 7 notes match byte for byte and name the retraction without claiming the GDPR policy said it.
- `check-tc-document-sha.sh` and `probe-legal-corpus-truth.sh` pass with `TC_VERSION` still `2.6.0`.
- #7851 is the only issue this pull request closes.

## Dependencies & Risks

Precedent: the 2026-09-07 six-file identical note extension, the line that already starts `**Corrected September 7, 2026 (#7786 / #6474).**`, plus the `LEGAL_DOC_SHAS` refresh of every canonical whose bytes change. This plan uses that shape. It does not introduce a SQL function, an atomic-write sequence, a lock, a connection pool, a circuit breaker, or a scheduled job, so there is no Inngest-cron versus GitHub-Actions choice to make.

- The CLO strings repeat #7529 inside a bullet that already points at #7529. That repetition is required by "keep the existing signing pointer" plus the new parenthetical. Do not delete the older pointer to make the prose tighter.
- Span 3's new text has no terminal semicolon. The existing semicolon after the old substring must remain, or the following Vendor DPA Status clause detaches.
- A newline inside the note makes `probe_legal_corpus_truth.py` stop stripping at the paragraph break. If the appended sentence quotes a future forbidden literal, the probe goes red on a correct corpus. The sentence chosen does not quote `SCCs incorporated`.
- Editing a `Last Updated` line fails the drift ratchet even when the date token looks harmless.
- Refreshing only two of the three hashes fails the SHA guard, because the GDPR note changes too.
- #7529 must stay open. A `Closes #7529` trailer would mark the signing action done.

## References & Research

- Issue: #7851. Signing action left open: #7529. Draft pull request: #10291.
- Related history: #7786 and #6474 (the September 7 note), #7465 (`Last Updated` drift), #7624 (probe and paraphrase rule).
- Policy: `knowledge-base/legal/tc-version-bump-policy.md`. Posture: `knowledge-base/legal/compliance-posture.md`.
- CLO ruling: `knowledge-base/project/specs/feat-one-shot-7851-better-stack-scc-wording/decision-challenges.md`.
- Best-practices impact (name level, first research spawn): an unexecuted instrument cannot be described as having incorporated Article 46 clauses; an intra-EU transfer record does not require that safeguard sentence.
