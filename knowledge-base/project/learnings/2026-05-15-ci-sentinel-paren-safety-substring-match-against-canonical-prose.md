# Learning: CI sentinel paren-safety when substring-matching canonical prose

## Problem

Plan v1 for PR #3819 (API-budget preamble backport) prescribed a CI assertion that asserted each of six skill SKILL.md files contained a `<decision_gate>` block whose body contains the literal substring `BSL 1.1 disclaims warranty`. The intent was: surface that the skill's disclosure block includes the BSL 1.1 warranty disclaimer verbatim from the canonical source at `plugins/soleur/docs/pages/goal-primitive.md:59`.

The canonical source sentence is:

> The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate `/goal` against your own budget.

The plan's six per-skill disclosure blocks copy this sentence verbatim. So they all contain the substring `(BSL 1.1) disclaims warranty for runtime cost` — with a `)` separating `1.1` and ` disclaims`.

The sentinel `BSL 1.1 disclaims warranty` does **not** appear anywhere in the actual disclosure text, because the canonical prose has `(BSL 1.1)` with a closing paren before `disclaims`. A `.includes("BSL 1.1 disclaims warranty")` check against `"(BSL 1.1) disclaims warranty"` returns `false`. AC1 and AC6 would have failed at first CI run; the gate would have looked broken to the work-phase implementer and required a sentinel rewrite mid-implementation.

Kieran plan-review caught it pre-merge by reading the canonical source line and matching against the plan's sentinel. Plan v2 switched to `disclaims warranty for runtime cost` — a substring that doesn't span any punctuation boundary in the source.

## Solution

When choosing a CI assertion sentinel that substring-matches canonical prose:

1. Read the actual canonical source line. Don't paraphrase from memory or from the issue body.
2. Audit punctuation **between** the words of the candidate sentinel: parentheses, commas, em-dashes (`—`), colons, brackets, slashes, periods inside abbreviations.
3. Pick a phrase that spans **no punctuation boundary** in the source. Words separated only by a single space are safe; words separated by `) ` or `, ` or ` — ` or `: ` are not.
4. If no paren-safe phrase exists in the canonical sentence, either (a) ask the canonical source to be slightly reworded (only viable if you control both sides), or (b) split the assertion into two substring checks against safe sub-phrases.

For PR #3819 specifically: `disclaims warranty for runtime cost` is the canonical phrase that is unique to this disclosure and contains no punctuation in the source.

## Key Insight

CI sentinels look like cheap literals but they encode a **micro-contract** between the source prose and the test. The contract breaks silently when the source prose contains punctuation the sentinel didn't anticipate. Substring-match (`.includes()`, `grep -F`) is the most brittle form because it doesn't normalize whitespace, doesn't tolerate punctuation, and doesn't show the user a diff when it fails — it just reports "not found." The fix is to choose sentinels that are *robust under punctuation-preserving copy-paste* of the canonical prose into the consuming files.

This is a sibling of `cq-regex-unicode-separators-escape-only` (regex over user-controlled input must handle U+2028/2029) and `cq-test-fixtures-synthesized-only` (fixtures must be deterministic). All three say: when your test compares against text, audit every byte of the text.

The catch was free at plan-review time. At work-phase, the implementer would have needed to (a) notice the CI failure, (b) trace it to the sentinel-vs-canonical mismatch, (c) update the sentinel, (d) update the rule body in `AGENTS.docs.md`, (e) update the plan's AC1/AC6, (f) update the route-to-definition skill-enforced tag. Five fix sites for a one-character drift. Plan-time review pays for itself.

## Tags

- category: best-practices
- module: plugins/soleur/skills/plan, plugins/soleur/skills/review
- related-prs: #3819 (caught at plan-review), #3809 (canonical source)
- related-rules: cq-regex-unicode-separators-escape-only (sibling defect class)

## Session Errors

Session error inventory: none detected.

The three "issues" surfaced during plan review (sentinel mismatch, arithmetic drift, `|| true` escape hatch) were caught BEFORE any code shipped — the plan-review multi-agent gate did its job. They are not session errors in the AGENTS.md `wg-every-session-error-must-produce-either` sense; they are examples of the review gate succeeding.
