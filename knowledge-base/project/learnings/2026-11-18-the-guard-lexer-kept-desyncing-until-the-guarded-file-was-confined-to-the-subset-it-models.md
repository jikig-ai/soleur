---
title: The guard's lexer kept desyncing from Terraform until the guarded file was confined to the subset the lexer models
date: 2026-11-18
category: workflow-issues
module: review fix rounds, HCL drift guards, Better Stack alert tests
tags: [review, fix-round, lexer, residuals, hcl, qa, discriminator]
issue: 12726
pr: 12865
---

# Learning: the guard's lexer kept desyncing until the guarded file was confined to the subset it models

## Problem

PR #12865 inverts the Better Stack alert `inngest_cutover_flip_silent` to ADR-218's missing-count form and adds a throwaway canary. The PR is pinned by the guard `apps/web-platform/test/infra/inngest-cutover-flip-silent-alert.test.sh`. That guard grades an "effective" view of the alerts `.tf` file, produced by the shared hand-written lexer `tests/scripts/lib/hcl-effective-text.sh` (`strip_comments` / `blank_heredocs`).

Each review round found a new construct the lexer reads differently from Terraform. That desync lets a decoy line Terraform never evaluates satisfy the pin while the real line is disarmed. The constructs, by round:

- **Round 1:** `/* */` decoys.
- **Round 2:**
  - a pristine copy inside another heredoc;
  - `${"#"}`, `${"/*"}` and `${"\""}` interpolations, which flip the lexer's string and comment state while Terraform's stays put.
- **Verifier pass:** a column-0 `}` cutting the raw block.
- **Escalated panel:**
  - a `<<-EO-T` heredoc marker the lexer cannot see;
  - escaped and unquoted resource labels;
  - a Unicode-space heredoc closer, which Terraform trims with `bytes.TrimSpace`;
  - an interpolation outside the flip blocks hiding whole blocks.

Round 2 had already applied the 2026-11-11 learning. It stated the guard's CONTRACT and RESIDUALS and added two-view agreement: every pin must hold in the raw text AND the effective text, with exactly-one raw cardinality. The escalated panel still found shapes that satisfied every row. The contract claimed a property over full HCL, and the rows only delivered it over the subset the lexer models.

## Solution

Lead ruling R-subset: stop growing the lexer, and confine the INPUT instead. Five file-wide rows refuse anything outside a subset the lexer models exactly:

- **S1:** no `/*` anywhere.
- **S2:** every `${`/`%{` closes on its own line, and its body holds none of `"`, `#`, `/`, `<`, `{`, `}` or `\`.
- **S3:** every `<<` sits inside a whole-line `#` comment or on a canonical `name = <<-?MARKER$` opener, and none appears inside the flip blocks.
- **S4:** resource and data headers are canonical.
- **S5:** non-ASCII bytes appear only in `#` comments or in single-line string assignments (checked with `LC_ALL=C`).

The pristine file already satisfied all five rows. Inside the subset, `strip_comments` / `blank_heredocs` equal Terraform's reading, so the two-view, cardinality and span rows grade what Terraform evaluates. The lexer's missing `${ }` depth tracking (#12917) is unreachable in this file. It stays a stated residual for the lexer's other consumers. The verifier pass after R-subset found no P1 or P2.

## Key Insight

When a hand-written lexer for a language you do not control is the guard's lens, two class fixes are already on record:

1. State the residuals (2026-11-11).
2. Move the property to a runtime recorder (2026-10-30).

This PR adds a third, cheaper than (2) when the guarded input is one file the repo owns. Restrict that file to the subset the lexer models exactly, with file-wide refusal rows. Do it at the second sibling round, not the fourth.

Stating residuals is not enough while the CONTRACT still quantifies over the whole language. Rewrite the contract to quantify over the subset, and the residuals become unreachable rather than merely named.

QA corollary: a discriminator stand-in must keep the production filter and vary only the data. Scenario 3 tested the `JSONType = 'Object'` predicate by swapping in `= 'String'`. That window held 42 string rows, so it returned value 0: it measured the inverted filter, not the shipped one. The valid stand-in conjoins the production filter with an impossible clause. It returns `rows 0 / value 1`, and a `countIf` split (object 3 / string 44) shows the discriminator excludes the string rows.

## Session Errors

1. **The plan sharp-edges reference was read only in part** (forwarded from the plan phase). Recovery: none needed. **Prevention:** read the whole reference, or grep it for the plan's change class before finalizing.
2. **Slow suites timed out during the baseline** (forwarded). Recovery: pinned counts were read from the files. **Prevention:** tracked in #12013. Run the long suites singly with an explicit timeout.
3. **The plan Step 4.5 advisor consult was skipped** (forwarded). Recovery: the CTO rulings served as the strong-model consult. **Prevention:** record the substitution in session-state, as was done.
4. **deepen-plan ran a focused fan-out of 3 agents** (forwarded). Recovery: the review panel covered the remaining lenses. **Prevention:** record the narrowed fan-out in session-state, as was done.
5. **The issue-create hook refused the first filing** three times: no `--milestone`, no literal body-file path, no exit label. Recovery: added `--milestone "Post-MVP / Later"`, a body file and `--label meta/machinery`, then filed #12917. **Prevention:** before the first `gh issue create`, write the body file and set the milestone and label (same prevention as the 2026-11-11 learning).
6. **The commit hook blocked one command that combined a `TMPDIR` export, `git add` and `git commit`.** Recovery: ran `git add` and `git commit` as separate calls. **Prevention:** never chain staging and committing behind an env export in one Bash call.
7. **Fix agents wrote raw non-ASCII bytes (a no-break space and an accented e) into test source.** Recovery: replaced them with backslash-u escapes. **Prevention:** brief fix agents on `cq-regex-unicode-separators-escape-only` by name when a row needs a non-ASCII probe.
8. **`scripts/test-all.sh --affected` hit its timeout (rc=124) after 50 min.** Recovery: treated it as no verdict and ran the touched suites by name. **Prevention:** tracked in #12013. Name the suites a diff touches rather than rely on the affected gate under host load.
9. **A stray `scripts/.h1probe.*.sh` appeared from a concurrent test run.** Recovery: left uncommitted. **Prevention:** tracked in #12340. Check `git status --short` before each commit.
10. **One defect class took 2 targeted rounds, a verifier pass and an escalated panel**, because the contract claimed more than the rows checked even after the residuals were stated. Recovery: R-subset (rows S1-S5). **Prevention:** a bullet routed to `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md`: at the second sibling round of a lexer-desync class, confine the guarded input to the lexer's exact subset.
11. **QA scenario 3's stand-in (`JSONType = 'String'`) measured the inverted filter and returned 0, not the expected 1.** Recovery: re-ran it as an impossible-conjunction stand-in plus a `countIf` split, which passed, and corrected the plan's scenario text. **Prevention:** a bullet routed to `plugins/soleur/skills/plan/references/plan-sharp-edges.md`: a discriminator stand-in keeps the production filter and varies only the data.
12. **Context was auto-compacted three times.** Recovery: worked from session-state and the fix briefs on disk. **Prevention:** keep briefs and rulings in files (done), and recommend a fresh session at the next phase boundary.

## Tags

category: workflow-issues
module: review fix rounds, HCL drift guards
