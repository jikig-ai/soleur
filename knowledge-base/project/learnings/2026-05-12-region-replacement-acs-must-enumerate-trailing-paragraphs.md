---
title: Region-replacement plan ACs must enumerate trailing/leading paragraphs in the awk range
date: 2026-05-12
category: best-practices
module: planning, legal-docs
tags: [plan-quality, acceptance-criteria, region-replacement, awk-diff]
related_pr: 3669
related_issue: 3666
---

# Region-replacement ACs must enumerate trailing paragraphs in the awk range

## Problem

PR #3669 (#3666) forward-ported plugin-mirror GDPR Policy §3.8 to match canonical. The plan's AC6 prescribed:

```bash
diff <(awk '/^### 3\.8/,/^---$/' plugins/soleur/docs/pages/legal/gdpr-policy.md) \
     <(awk '/^### 3\.8/,/^---$/' docs/legal/gdpr-policy.md)
```

…with expected output: empty (zero divergence).

The plan's edit instruction said: "Replace §3.8 heading + body (heading line 104, body lines 106-107) with canonical §3.8 form (canonical lines 93-100)."

After applying that edit verbatim, AC6 diff was NOT empty — canonical had **two extra lines** in the awk-captured region:

```text
> A balancing test is not required for the contract performance basis used in account, payment, and infrastructure processing above. For the legitimate interest basis applied to unauthenticated CDN/proxy traffic, the balancing test considers...
>
```

## Root cause

`awk '/^### 3\.8/,/^---$/'` captures from the §3.8 heading to the **next `---` rule**, which in canonical includes a closing paragraph that structurally belongs to §3.7 but is **physically located after** `<!-- End: KB sharing -->`.

Plugin (before edit) had the same paragraph at the **end of §3.7**, before `<!-- Added 2026-04-10: KB sharing -->`. Canonical relocated it post-§3.8 in a prior PR but the plan's diff-time inspection focused on heading+body lines only.

The plan AC's awk range was correct; the plan edit instruction was incomplete — it didn't enumerate the trailing paragraph that the awk range would capture.

## Solution

Two-step recovery:

1. **Delete** the balancing-test paragraph from plugin §3.7 trailer (before `<!-- Added 2026-04-10: KB sharing -->`).
2. **Re-insert** it after `<!-- End: KB sharing -->` (between §3.8 close and the `---` rule).

After the move, AC6 diff returned empty. Single follow-up commit: same `Phase 3 — GDPR Policy forward-port` commit; no separate commit needed.

## Key insight

**When a plan's AC uses an awk range delimited by structural markers (`### heading`, `---`, `<!-- End -->`), the plan's edit instruction must enumerate every paragraph the awk range will capture — including paragraphs that semantically belong to neighboring sections but are physically inside the range.**

Concretely: if the awk pattern is `/^### 3\.8/,/^---$/`, then the plan instruction must specify edits for **every** line between (and including) those delimiters, not just the heading + immediately-following body lines.

The general rule: **AC region ⊇ edit-instruction region**. If the AC ranges over more text than the edit instructions describe, the AC will detect drift the implementation cannot fix without scope expansion.

Two ways to align this at plan time:

1. **Tighten the AC range** to match exactly what's being edited (e.g., `awk '/^### 3\.8/,/<!-- End: KB sharing -->/'` instead of `/^---$/`).
2. **Expand the edit instruction** to cover everything inside the AC range (e.g., "Replace §3.8 heading, body, AND the §3.7 balancing-test paragraph that now trails §3.8").

Either works; the failure mode is having the two regions disagree.

## Prevention

- Plans that prescribe `diff <(awk 'A,B') <(awk 'A,B')` ACs must specify edits covering the full A→B region, not just the named section's heading+body.
- A quick pre-write check: run the awk on canonical at plan time, count the paragraphs, and ensure the edit instructions name each one.
- For legal-doc plans specifically: HTML comment markers (`<!-- End: ... -->`) and balancing-test paragraphs often sit at section boundaries; check both sides of the marker when forward-porting.

## Session Errors

1. **AC6 §3.8 awk-region structural drift not anticipated by plan.**
   **Recovery:** Two-step relocation of balancing-test paragraph from §3.7 trailer to §3.8 trailer; AC6 then passed.
   **Prevention:** Plans prescribing `awk '/^heading/,/^delimiter$/'` ACs must enumerate every paragraph in the captured range, not just the named section's body. (Captured in body of this learning.)

2. **AC9 grep regex `Last Updated May 12, 2026` matched only hero `<p>Effective ... | Last Updated May 12, 2026</p>` (one hit), not body `**Last Updated:** May 12, 2026` (zero hits because of colon). Plan expected `2,2,2` count.**
   **Recovery:** Trusted spirit of AC (verified both hero and body dates bumped via separate `grep -n 'Last Updated'` call); did not let literal regex mismatch block phase.
   **Prevention:** Date-grep ACs that span hero+body should either (a) tolerate both punctuation forms in the regex (`Last Updated[: *]+May 12, 2026`), or (b) split into two separate count assertions per location.

3. **Forwarded from session-state.md (plan-deepen phase):** plan v0 cited "PR #3603" when `#3603` is the umbrella issue (state=CLOSED), not a PR. #3662 is the PR (state=MERGED).
   **Recovery:** Corrected at deepen-plan time via `gh issue/pr view` live verification.
   **Prevention:** Live-verify cited PR/issue numbers via `gh pr view <N> --json state,title` and `gh issue view <N> --json state,title` during plan synthesis; never assume an issue number references a PR.
