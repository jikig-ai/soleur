---
title: "A line scanner is not a lexer, and my guard's own fixture hid the suite from the vacuity guard"
date: 2026-09-24
category: integration-issues
tags: [terraform, doppler, lint, tokenizer, guard-vacuity-floor, sibling-pr, nfc, vendor-cap]
issues: [8209]
prs: [8667, 8668]
---

# A line scanner is not a lexer, and my guard's own fixture hid the suite

## Problem

Doppler's API rejects a project `description` over 255 characters at create time. Neither the
dopplerhq/doppler provider schema nor `terraform plan` checks it, so the first signal is a red push
apply. After the credential-tiering merge (#8563), a 273-character
`doppler_project.infra_privileged` description failed four push applies in a row: 35912754656,
35921899265, 35927849285 and 35951193547. The same cap had already broken `doppler_project.inngest`
in July (#6213). That fix shortened one string and added a comment. It added no guard.

## Solution

1. **The string.** Shipped by sibling PR #8668 (231 characters). Push apply 35963237090 created the
   project and its `prd` environment. The plan was `3 to add, 1 to change, 0 to destroy`, and the
   SSH apply changed nothing (0 added, 0 changed, 0 destroyed). #8667 then reworded the description
   to 230 bytes with an accurate read-path claim, which is an in-place update, never a replace.
2. **The guard.** `scripts/lint-doppler-description-length.py`, registered `-live` and `-unit` in
   the required `test` context. It is a **bracket-depth tokenizer**. It lexes strings (including
   nested `${}` templates), `#`, `//` and `/* */` comments, and heredocs, then tracks blocks by
   bracket depth. A description is measured only when it is a direct attribute of a top-level
   `resource "doppler_*"` block and its value is exactly one template-free literal. Anything else
   fails closed.

## Key Insight

**A lint over a structured language must lex it, not scan its lines.** The plan chose "line-based,
no tokenizer" at plan review, on the argument that `terraform fmt` fixes the layout. A review
panel then found five `fmt`-clean layouts that let an over-cap description through:

- a heredoc opener inside a string;
- a heredoc opener inside a `#` comment;
- an inline `/* c */ description = ...`;
- text after a closing `*/`;
- a `/*` opened mid-line.

Three more layouts get through that `fmt` would fix, but `fmt -check` is not a required check:
unquoted labels, a BOM, and a column-0 continuation line. Each defeat was a different instance of
one gap: the scanner's picture of structure (column 0, line starts) was narrower than the
language's. Patching spellings would have gone on through more review rounds. The tokenizer closes
the class, and it reproduced the line scanner's live reading exactly (79 resources, 30 files, 4
descriptions, max 245), which is an independent check that the rewrite is sound.

Two measurement facts turned up along the way:

- **Raw source bytes are NOT an upper bound.** Terraform NFC-normalises string literals, and a few
  characters expand under NFC: 63 × U+1D160 is 252 source bytes and 756 bytes decoded. The measure
  is max(raw bytes, UTF-8 bytes of the NFC-normalised decoded value). UTF-8 bytes bound both code
  points and UTF-16 units.
- **`git ls-files` lists a conflicted path once per stage.** Mid-merge, the lint counted 83
  resources and 6 descriptions instead of 79 and 4 until it deduplicated paths.

## Session Errors

1. **The resume brief said the replace was gated on a reviewer environment. It is not.**
   `git_data_host_replace` runs in `infra-privileged` (zero reviewers, ADR-241 D2) and takes no
   confirm token, so a dispatch runs immediately. Recovery: I read the job and the environment
   before dispatching and asked the operator for explicit authorization. **Prevention:** before
   any operator dispatch, read the job's `environment:` from the workflow file on `main` and the
   environment's live `protection_rules`. A brief's gating claim is a precondition to check, not a
   fact.
2. **The brief said "merging was O0's apply, so the Doppler project exists". It did not exist:**
   every push apply had failed on its description. Recovery: `doppler projects get` said so, and
   the four failed runs named the cause. **Prevention:** verify a "now exists" claim with a live
   read of the object, never from the merge event.
3. **The scratchpad directory did not exist when I first wrote to it.** Recovery: `mkdir -p`.
   **Prevention:** create it in the same command that first writes to it.
4. **The Write tool refused a full rewrite of a file I had edited by script since reading it.**
   Recovery: read it again, then write. **Prevention:** after a scripted edit, read the file again
   before any whole-file Write.
5. **My fixture's literal heredoc opener inside a `printf` string silently removed the suite from
   `guard-vacuity-floor.test.sh`'s covered population.** The detector read it as a heredoc with no
   terminator and skipped every later line, including the floor. Branch and main both reported 208
   covered. Recovery: build the opener at run time (`hd='<''<'`) and confirm with the guard's own
   `floor_lines_of`. **Prevention:** after adding any `*.test.sh`, check that the guard's covered
   count rises by exactly one against the same base. The guard's fail-open on an unterminated
   heredoc is filed as #8689.
6. **I compared guard-vacuity counts across two different bases** (the branch's old base against a
   newer main) and got a misleading "one lower". Recovery: merge main, then compare. **Prevention:**
   a count delta is valid only between two runs on the same base.
7. **I hand-tallied `MIN_CASES` wrong twice** (37 against 34, then 57 against 60). Recovery: count
   the `cases=$((cases + 1))` sites. **Prevention:** derive the floor from that grep, never from a
   tally.
8. **The scripts shard was refused (rc=4) because a sibling ran a full gate.** Recovery: the
   `affected` scope, then the operator chose CI as the gate. **Prevention:** none needed; rc=4 is the
   designed behaviour.
9. **The plan prescribed a line-based lint that five `fmt`-clean layouts defeat.** Recovery: a
   bracket-depth tokenizer. **Prevention:** routed to plan-sharp-edges ("a guard over a structured
   language lexes it").
10. **Sibling PR #8668 (same one-line fix, auto-merge armed) was opened after my collision probes
    and missed by the post-planning re-probe, which checked only `#N` links.** A history seat found
    it. Recovery: the operator chose to let #8668 ship the string, and I rebased. **Prevention:**
    routed to one-shot. After planning, re-run the anchor probe on the files the plan edits, not
    only on the refs.
11. **A row passed on a Python traceback.** A crash exits 1, and the traceback printed the source
    line containing the expected substring. Recovery: every row anchors on `file:line:` and rejects
    `Traceback`, and the lint exits 2 on its own failures. **Prevention:** already covered by
    `cq-assert-anchor-not-bare-token`. The new detail is that a crash's traceback is a second carrier
    of the anchor.
12. **I wrote a literal U+2028/U+2029 into a regex**, which breaks
    `cq-regex-unicode-separators-escape-only`. Recovery: `  ` escapes. **Prevention:**
    already a rule; a lapse.
13. **Mid-merge, `ls-files` double-counted a conflicted file.** Recovery: dedupe paths. **Prevention:**
    fixed in the lint.
14. **The plan cited two failed runs; there were four.** Recovery: corrected in the plan addendum and
    the runbook. **Prevention:** re-derive counts from `gh run list` at write time, not from the
    brief.
