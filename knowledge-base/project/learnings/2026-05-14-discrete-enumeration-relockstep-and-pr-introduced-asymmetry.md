---
title: Trust the grep, not the plan paraphrase — discrete-enumeration re-lockstep at /work, and the provenance trap that mis-classifies PR-introduced asymmetries as pre-existing
date: 2026-05-14
category: best-practices
tags: [plan, work, review, discrete-enumeration, lockstep, docs-sync, eleventy, scope-out, provenance, legal-docs, sentry, dpd, gdpr]
severity: medium
status: closed
related_prs: [3708, 3755]
related_issues: [3708]
synced_to: []
---

# Discrete-enumeration re-lockstep + the pr-introduced-asymmetry provenance trap

## Problem

PR #3755 (#3708) added a new §(l) "Operational telemetry & breach detection" entry to `docs/legal/data-protection-disclosure.md` and its Eleventy mirror `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`. The plan's Research Reconciliation row 1 asserted at length that both files were "in lockstep on §(a)-(k)" — a worktree-aware re-grep had run at deepen-pass to verify this claim. Same deepen-pass even noted "no drift to backfill — corrected at deepen-pass" as a tombstone.

The plan was wrong. At /work, the AC1 verification grep:

```bash
grep -cE '^- \*\*\(l\)\*\* ' docs/legal/data-protection-disclosure.md
```

returned `2` for the canonical file (1 was supposed to be the newly added telemetry entry; the second hit was a pre-existing `§(l) DSAR self-serve export` entry the plan never noticed). The Eleventy mirror returned `1`. Reality: canonical=(a)-(l) with DSAR at §(l); mirror=(a)-(k). The "(a)-(k) lockstep" framing was paraphrase-from-an-incomplete-read.

Both the plan-time grep and the deepen-pass re-grep used a regex that stopped at `[a-l]` or similar — and crucially, the runtime read of those greps was paraphrased into prose ("both files in lockstep at (a)-(k)") that became the binding plan claim. The next-letter insertion target ("§(l) Operational telemetry") was chosen against the prose paraphrase, not against a fresh re-grep.

A second-class problem then surfaced at review time. The new §(m) entry named "Sentry (Functional Software GmbH, DE region, SCCs)" as a Web Platform processor with explicit Art. 6(1)(f)+6(1)(c) dual basis. Two independent review agents (git-history-analyzer + security-sentinel) flagged that the sibling `docs/legal/gdpr-policy.md` §3 and `docs/legal/privacy-policy.md` §5 enumerated every Web Platform processor (Supabase, Stripe, Hetzner, Cloudflare, Resend) but did NOT mention Sentry. Initial reflex was to file the gap as `pre-existing-unrelated` scope-out — "the Sentry processing was introduced by PRs #3701/#3731/#3751 without simultaneous sibling-doc backfill, so the gap pre-dates this PR." Plausible. `code-simplicity-reviewer` DISSENTed in a single sharp paragraph:

> "PR #3708's DPD §(m) introduces Sentry as a named processor for a *new* user-facing telemetry surface and explicitly cites Art. 6(1)(f)+6(1)(c) and 90-day retention; shipping that DPD §(m) entry while the sibling gdpr-policy.md / privacy-policy.md remain Sentry-silent is asymmetric disclosure *caused by this PR's framing*, which exacerbates (not merely preserves) the pre-existing gap and fails the `pre-existing-unrelated` bar."

The DSAR-gap had been pre-existing; the Sentry-asymmetry was *pr-introduced* — by the PR that names Sentry in one disclosure surface while leaving siblings silent. Pre-PR, all three docs were uniformly Sentry-silent (consistent, if incomplete). Post-PR, the silence is selectively contradicted. Provenance-by-analogy is wrong: the asymmetry's provenance is what matters, not the underlying data flow's provenance.

A third small problem: §5.10 insertion into `privacy-policy.md` initially anchored on "Resend (Web Platform Transactional Email)" — the lexically-adjacent block — and placed §5.10 BEFORE §5.9 in the file. Caught by self-review of the diff.

## Solution

### Re-lockstep at /work for any "(a)-(N)" plan assertion

At /work-start, when the plan asserts a paraphrase like "both files in lockstep at sections (a)-(N)", "all 7 entries match", "list is (i) through (v) in both", run a SECOND independent grep with a regex that doesn't pre-constrain the alphabet — `grep -cE '^- \*\*\([a-z]\)\*\* '` (not `[a-N]`) — across both files. Compare counts. If they differ, the plan's lockstep claim is wrong; investigate before inserting.

```bash
# Re-lockstep gate
for f in <file_a> <file_b>; do
  printf '%s: count=%d letters=%s\n' "$f" \
    "$(grep -cE '^- \*\*\([a-z]\)\*\* ' "$f")" \
    "$(grep -oE '^- \*\*\(([a-z])\)\*\* ' "$f" | sed -E 's/.*\(([a-z])\).*/\1/' | tr '\n' ',' )"
done
```

Counts must match AND the letter sets must match. Anything else means the plan's assertion is paraphrase-from-stale-read; correct the plan or file a pre-merge tombstone before insertion.

### Sequential-section insertion anchor

When inserting a new sequentially-numbered section, the Edit anchor MUST target the LAST `### X.N` block before the desired slot — not the lexically-adjacent block, not the structurally-nearest header. Confirm via:

```bash
grep -nE '^### [0-9]+\.[0-9]+ ' <file> | tail -N
```

Pick the line of the last `### X.N` whose `N` is less than your new `N`. Replace its closing line + a blank line + your new section header, not its opening line.

### Provenance triage for scope-out (the asymmetry rule)

When a finding says "X is missing from sibling artifact Y", the provenance question is not "did this PR introduce X?" — it is "did this PR introduce the *asymmetry* between X-present-here and X-absent-there?". If this PR is the surface that names X for the first time in any disclosure / API / type / config across a sibling set, the asymmetry is **pr-introduced** even if the underlying capability X has shipped in 3 prior PRs. The `pre-existing-unrelated` scope-out criterion fails; fix inline.

The mechanical test: `git diff origin/main --name-only | xargs grep -l "<X>"` against the sibling set on `main`. If the diff adds `X` to file A and `main` had zero `X` mentions anywhere in {A, B, C}, then this PR creates the (B, C)-silence asymmetry by populating A. The asymmetry is `pr-introduced`. (If `main` already had `X` in A but missing from B, C — that's `pre-existing-unrelated` and scope-out is legitimate.)

## Key Insight

Three distinct lessons compose:

1. **Plan claims about discrete enumerations are paraphrases until re-verified at /work.** A plan that says "files in lockstep at (a)-(k)" is asserting a *boundary*. Boundaries silently shift between plan-write time and /work-start time. The plan-time grep was correct at plan-write time (or it was incomplete and the paraphrase compressed the actual finding); either way, /work cannot trust the prose. Re-grep at /work BEFORE the first letter-inserting Edit.

2. **Sequential-section insertion is anchor-direction-sensitive.** Markdown's `## N.M` numbering doesn't have a parser that catches misnumberings; the Edit tool will happily put §5.10 before §5.9 if the anchor string matches §5.9's block start. The `Edit anchor = LAST sibling before slot` rule is mechanical and cheap. Verify with a grep that returns ALL sibling-section line numbers, not just the matched one.

3. **Provenance triage for scope-out is about the ASYMMETRY, not the data flow.** Filing-by-analogy ("the X-gap was pre-existing, so this similar-looking Y-gap is too") loses the distinction between underlying-capability-provenance and asymmetry-provenance. The cost-of-filing gate already has the cure for this — `code-simplicity-reviewer` DISSENT — but the cure only fires if you actually call the agent. **The DISSENT in this PR was the load-bearing intervention; the agent caught what I almost shipped.**

## Prevention

Three structural changes, in increasing strength:

1. **At /work, for any plan assertion of discrete-enumeration lockstep, run the re-lockstep grep BEFORE the first Edit.** The grep + compare is ≤10 seconds. If counts diverge, halt and revise the plan claim inline (with a tombstone for the next planner). This is a candidate for a /work Phase 1 sharp-edge note.

2. **At /work, for any sequential-section insertion, run `grep -nE '^### [0-9]+\.[0-9]+ ' <file> | tail -3` BEFORE the Edit.** Confirm the chosen anchor is the LAST section before the new slot. Cheap and mechanical.

3. **At review, when filing a scope-out for a missing-from-siblings-X finding, the cost-of-filing pre-check MUST ask: "did this PR's diff add X to one file in the sibling set?" If yes, the asymmetry is `pr-introduced` regardless of when X's underlying capability shipped.** This is a candidate for a /review skill bullet under the cost-of-filing gate.

## Session Errors

- **Plan-claim of "(a)-(k) lockstep" was paraphrase-from-stale-read; canonical DPD actually had §(l) DSAR that the plan-time AND deepen-pass greps both missed.** Recovery: caught at /work AC1 verification (`grep -c` returned 2), renumbered telemetry to §(m), backfilled DSAR §(l) into the Eleventy mirror. Prevention: re-lockstep grep at /work-start for any plan assertion of discrete enumeration.
- **§5.10 in privacy-policy.md was initially inserted BEFORE §5.9 (Resend) because the Edit anchor matched the lexically-adjacent Resend block.** Recovery: caught by self-review of the diff, rewrote the Edit to place §5.10 after §5.9's closing bullet. Prevention: pre-grep `^### [0-9]+\.[0-9]+ ` to confirm the LAST-sibling anchor.
- **Initial scope-out attempt classified gdpr-policy/privacy-policy Sentry-symmetry gap as `pre-existing-unrelated`; `code-simplicity-reviewer` DISSENTed because this PR creates the asymmetry by populating DPD §(m).** Recovery: flipped to fix-inline; backfilled Sentry to all 4 policy files. Prevention: provenance triage for missing-from-siblings findings — the asymmetry-provenance is what matters, not the underlying-capability-provenance.
- **code-quality-analyst review agent stalled mid-run (stream idle timeout, "partial response received").** Recovery: proceeded with synthesis from 3 of 4 returning agents per the parallel-batch-stall sharp edge already documented in `2026-04-17-postgrest-aggregate-disabled-forces-rpc-option.md`. Prevention: existing — no new rule needed; the stall-acceptance protocol is already in `plugins/soleur/skills/review/SKILL.md` Sharp Edges.

## Cross-references

- `knowledge-base/project/learnings/2026-05-13-npm-workspaces-flag-fails-without-root-workspaces-declaration.md` — same defect class (plan-prescribed claim verified by paraphrase, falsified at /work by live invocation).
- `knowledge-base/project/learnings/2026-05-12-hyphenated-python-modules-and-plan-precondition-verification.md` — analogous Python-hyphen import case where 5-agent plan-review echoed a broken prescription.
- `knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md` — broader pattern of plan-quoted preconditions aging out.
- `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md` — every structural DPD change touches BOTH files in the SAME commit; this PR's DSAR-backfill+telemetry edit honors the rule across 6 legal files.
- `knowledge-base/project/learnings/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` — pattern of plan-paraphrase-vs-reality drift falsified by /work execution.
- `knowledge-base/project/learnings/2026-05-11-scope-out-bundling-hides-cheap-inline-fixes.md` — `code-simplicity-reviewer` DISSENT as load-bearing intervention.
- `plugins/soleur/skills/review/SKILL.md` Sharp Edges — where the provenance-triage-for-asymmetry rule could route (Step 8.3 candidate).
- `plugins/soleur/skills/work/SKILL.md` Phase 1 — where the discrete-enumeration re-lockstep and sequential-section anchor checks could route.
- PR #3755 / Issue #3708 — feat(legal): add DPD §(m) operational telemetry & breach detection user-facing entry.
