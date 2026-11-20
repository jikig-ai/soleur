---
date: 2026-11-16
topic: retry-budget-arbitration
---

# Retry-budget ruling

**Date:** 2026-11-16
**Issue:** #12526 (parent epic #12533)
**Worktree:** feat-12526-retry-budget-arbitration
**Draft PR:** #12815
**Lane:** cross-domain
**USER_BRAND_CRITICAL:** true (auto, per #5175)

**Vocabulary.** "Arbitration" in this document means the three-verb ruling (`continue`, `goto`, `fail`) on a classified budget stop. It does not mean legal dispute arbitration, the ADR-030 cross-domain priority surface, or the ADR-161 note that SessionStart writes share a fleet cap with no owner. `knowledge-base/project/glossary.md` has no entry. The hedge is the whole fix: the word is not yet shared traffic across three skills.

## User-Brand Impact

- **Artifact:** the retry-budget ruling (the one verb a fresh context returns when a child's budget stop halts one-shot).
- **Vector:** a wrong ruling silently continues a broken loop, or stops a fix, with no readable reason.
- **Threshold:** single-user incident

## What We're Building

When one-shot halts because a child's session state contains `budget-capped`, a fresh context reads the attempt evidence and returns exactly one machine-readable verb. The parent executes it.

- `continue` runs exactly one more iteration. `capped=` stays set. The cap is not raised.
- `goto` may name only `plan`, `work`, `review`, `qa`, or `test-fix-loop`. It must not resume `ship` or `merge`.
- `continue` and `goto` share that one exemption. The second exhaustion is `fail`, with no second spawn.
- `fail` is today's halt plus an on-disk ledger.
- A missing ledger, an empty history, or an unparseable line is `fail`.

ADR-268 already classifies a hard-cap crossing as `budget-capped` plus a resume prompt. Nothing in a fresh context reads the attempt evidence and returns a verb the parent executes. The counter file is counts. Checkpoint diffs, failure reasons, and gate outputs are not one file.

Phase 3.55 is skipped. `ui-surface-terms.md` covers pages, components, overlays, navigation, flows, and email. This change is orchestration.

## Why This Approach

The binding CTO ruling (2026-11-16) kept one shared exemption. `pipeline-tally.sh` `incr` does not read the latch, so one extra iteration does not clear `capped=` and does not call `init --max-*` (that call is `capped-reset` and contradicts ADR-268). The stop hook is what must learn the one grant: while the latch is set it declines to keep the loop alive. The grant is recorded in the session-state rewrite the hook already performs, and it is spent once.

The first attachment is one-shot's halt on the child's marker (`one-shot/SKILL.md` lines 50 and 267), not one-shot's own `agent_rounds` gate (line 136), which can stop on an inherited latch before this run has attempt history. Only the parent owns the phase list, so only the parent can execute `goto`.

A fail-only readable report was the CPO's product advice and option B in the ruling. The CTO rejected it as a scope cut: the issue asked for three verbs, and the extra iteration does not require clearing the latch. That advice is recorded below. It is not the decision.

The ledger is written by the parent at the halt, on disk at emission time, in the checkout that owns the counter. The exhausted session's own notes are evidence to re-measure, not a verdict. Anything other than one closed verb the parent parses itself is `fail`.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | One shared exemption. Latch and cap stay. | Ruled by CTO agent, 2026-11-16. Raising the cap inside the skill clears the latch. |
| 2 | `continue` is one iteration. `goto` is an allow-listed earlier phase. They share the exemption. | Second exhaustion is `fail` with no second spawn. |
| 3 | `fail` is today's halt plus an on-disk ledger. A bad or missing verb is `fail`. | The classified stop already writes the resume line. |
| 4 | First attachment is the parent halt on a child's `budget-capped` marker. | The parent owns `goto`. The child's own stop still writes the marker. |
| 5 | The parser accepts exactly one line. The spawn does not increment the dimension it judges. | A prose summary or the word "stop" ends the one-shot turn. |
| 6 | Excluded stops stay excluded, recorded here, not filed as new issues. | Same capability, surfaces with no classified stop or an empty ledger. See Non-Goals in the spec. |
| 7 | Clean-room ceiling is the three outcome words plus Soleur's own ledger. | CLO advisory, 2026-11-16. Not a CLO ruling line. |
| 8 | No public claim that this ships the compared peer, and no "unattended autopilot" positioning. | CMO: marketing is out of scope. |

## Open Questions

Planning owns these. They are not operator questions.

- The one-line grammar and where the one-grant bit sits in the session-state rewrite.
- Ledger path and fields (pointers to checkpoint diffs, failure reasons, gate outputs) in Soleur's own names.
- Which checkout the ledger is keyed to, so a branch-scoped counter is not read as a shared-main count.
- If someone has already read the peer's source, a different author writes the prompt.

## Next Steps

Proceed to planning on this branch. Do not merge the draft PR from this brainstorm.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** CPO advisory, not a ruling. Prefer a fail-only readable report, no new verb, and no silent continue. The binding CTO ruling kept the three verbs because dropping them would be an operator scope cut and the extra iteration is feasible without clearing the latch. Product input stands as dissent beside the decision. This stays internal orchestration. Do not productize a customer surface.

### Legal

**Summary:** CLO advisory, 2026-11-16. Permitted with guardrails. Draft, not legal advice. Not recorded as `Ruled by CLO agent` (the Rule interface was not used). Use the three outcome words and Soleur's own ledger. Do not copy the peer's prompts, code, tests, fixtures, comments, schema names, file layout, decision rubric, or docs text. Do not vendor, submodule, import, or shell out to that tree. Do not paste or closely paraphrase its public methodology sentence. Issue text is enough. No GDPR gate: the verb chooses a workflow phase, not a person. No legal-doc edit, no Article 30 row, no NOTICE, no `TC_VERSION` bump. If the ledger stores personal data, a users foreign key, or customer content, re-open the CLO before merge. PR trailer: derived from Soleur's ledger and this functional spec; zero peer source inspected.

### Engineering

**Summary:** Ruled by CTO agent, 2026-11-16. Decision A on the verb contract and Decision C on the first attachment. Detail is in `decision-challenges.md`. Dissent on ADR-268 lines 79-80 is recorded and not adopted: the extra spend is one consumed grant, not a cleared stop.

### Marketing

**Summary:** Out of scope. Do not claim this ships the compared peer. Do not adopt that peer's "unattended autopilot" line as public positioning.

## Capability Gaps

- **No attempt-ledger artifact.** `rg -l --glob '!**/legal-generate/**' --glob '!**/archive/**' 'attempt.ledger|retry-budget-ruling' plugins/soleur knowledge-base/project` returned no files. `find plugins/soleur -iname '*arbitrat*' -o -iname '*attempt-ledger*' -o -iname '*retry-budget*'` returned none. The tally file stores counts. This brainstorm does not invent a learning that says the ruling already exists.
- **The parent halt does not read a verb.** `plugins/soleur/skills/one-shot/SKILL.md` lines 50 and 267 `grep -q budget-capped` on the child's session state and halt. Line 136 can stop on `agent_rounds` before attempt history exists.
