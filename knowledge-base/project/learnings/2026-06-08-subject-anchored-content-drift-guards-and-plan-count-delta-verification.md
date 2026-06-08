# Learning: Subject-anchored content-drift guards + verify plan-asserted grep counts by listing matches

date: 2026-06-08
PR: #5048
issue: #5043

## Problem

PR #5043 swept Soleur-subject "open source" → "source-available (BSL 1.1)" across 11 dated blog
posts (Soleur is BSL 1.1, not OSI-approved) while keeping genuine competitor/ecosystem "open
source" claims (CrewAI MIT, Paperclip MIT, Spec Kit) verbatim. It added a content-drift test
(`marketing-content-drift.test.ts` Test 2c2) banning Soleur-subject "open source" in the blog walk.

The first-draft `SOLEUR_OPEN_SOURCE` regex (empirically validated RED-before/GREEN-after at plan
time, 0 misses / 0 false-positives on the *current* corpus) still had two latent defects that
multi-agent review caught — both invisible to the "validate against the current files" oracle:

1. **Bare sentence-lead anchors false-fail on FUTURE third-party copy.** Two alternations
   (`^Open source,\s` and `(?:^|\.\s+|browsers\.\s+)Open source\.\s`) matched ANY sentence-initial
   "Open source." with no subject token. They passed the current-corpus oracle (no competitor line
   currently starts that way) but would block a legitimate future line like
   `"Open source. That's CrewAI's pitch, not ours."` — a false-positive *gate* that breaks the
   build on valid competitor copy, contradicting the test's own KEEP-oracle.
2. **Over-fit / dead branches.** `^Open source,\s` matched 0 lines in the entire corpus (dead);
   `browsers\.\s+` was fully subsumed by `\.\s+` (redundant, hard-coded from one file's string);
   and the lead alternation missed `**Soleur** is an open-source …` because markdown-bold `**`
   sits between `Soleur` and `is` and `\s+` can't cross it (so a regression of the two intro lines
   would slip past).

Separately: the plan asserted "AC2 competitor grep counts unchanged (Paperclip 8)"; after the
sweep the Paperclip count was 7, which looked like a regression.

## Solution

**Subject-anchor the guard.** Rewrote the regex to three frames that each require a subject token
near the claim, deleting the bare-phrase anchors:

```ts
const SOLEUR_OPEN_SOURCE =
  /Soleur\b[^.\n]{0,40}\bopen[- ]source|\bit\s+is\s+(?:public,\s+it\s+is\s+)?open[- ]source\b|open[- ]source\s+(?:CaaS|transparency)/i;
```

- Frame 1 `Soleur\b[^.\n]{0,40}\bopen[- ]source` — "Soleur" within 40 same-line chars of
  "open-source". `[^.\n]` stops at sentence/line boundaries so it can't span a period into a
  competitor clause (e.g. `Paperclip (open-source, MIT) and Soleur (source-available)` does NOT
  match — the "open-source" is before "Soleur", and the bits after "Soleur" have no "open-source").
  Catches the bold-intro `**Soleur** is an open-source` and adverb forms (`Soleur is fully open
  source`) the token-adjacency draft missed.
- Frame 2 pronoun `it is (public, it is) open-source` (Soleur's own first-person copy).
- Frame 3 `open-source CaaS|transparency` (Soleur-specific noun phrases).

Validated with a 3-part oracle (not just "current files clean"): (a) current swept files → 0
(GREEN); (b) reconstructed PRE-sweep Soleur-subject forms incl. bold + adverb shapes → all match
(RED); (c) competitor/ecosystem KEEP lines **plus the reviewers' future-FP examples**
(`"Open source. That's CrewAI's pitch"`, `"Open source, MIT-licensed … Spec Kit"`) → 0 matches.

**Count-delta:** listed the actual `git grep` matches instead of trusting the count. The 8→7 drop
was a deliberate reword (a combined Soleur+Paperclip "most complete open-source stack" line legitimately
dropped "open-source" since the combined stack now includes BSL Soleur) plus a false baseline hit
(the word "co**mmit**ly o**mit**" — `omit` contains `mit`, matched the case-insensitive `MIT`
pattern). No genuine competitor claim was lost.

## Key Insight

A content-drift guard that bans an "**X-subject** claim Y" (where the same phrase Y is *legitimate*
when said about a third party) MUST be **subject-anchored** — require the subject token adjacent to
the phrase — never rely on bare-phrase or sentence-position anchors. Validate it against three sets,
not one: current-corpus GREEN, reconstructed-regression RED, **and a synthesized future-third-party
set the current corpus doesn't yet contain**. The "0 false-positives on today's files" oracle is
blind to the false-positive *gate* that fires the first time someone writes the banned phrase about
a competitor. Bare-phrase anchors reverse-engineered from one current line (`browsers\.`,
`^Open source,`) are the tell — they encode a string, not a rule.

Corollary: when a plan asserts "grep count unchanged at N", verify by **listing the matches**, not
comparing the integer — a benign reword shifts the count, and case-insensitive substring patterns
(`MIT`) get false hits from ordinary words (`omit`, `commit`, `summit`).

## Session Errors

1. **Edit-before-Read (sed ≠ Read).** Inspected blog lines via Bash `sed -n`, then the Edit tool
   rejected 4 edits with "File has not been read yet." Recovery: used the Read tool, re-applied.
   **Prevention:** the Edit tool's read-tracking is satisfied only by the Read tool — never inspect
   via `sed`/`cat` when an Edit follows; Read the target region first. (Harness-level constraint;
   one-off, no rule added.)
2. **AC2 Paperclip count 8→7 looked like a regression.** Resolved by listing matches (benign — see
   above). **Prevention:** captured as the count-delta corollary in this learning.
3. **`git diff HEAD...origin/main` listed unrelated cron files.** The documented stale-`origin/main`
   three-dot false-positive; recognized, diffed against the true merge-base SHA instead. No action.

## Tags
category: test-failures
module: marketing-content-drift
