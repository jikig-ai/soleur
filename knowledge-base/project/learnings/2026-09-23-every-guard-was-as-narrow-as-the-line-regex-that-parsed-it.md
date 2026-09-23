---
title: Every guard in my ledger lint was as narrow as the line regex that parsed its input, and my mutation harness scored its own failures as kills
date: 2026-09-23
category: workflow-patterns
module: encryption-posture-ledger
tags: [lint, parser-view, mutation-testing, guard-vacuity, gdpr, credentials, inherited-framing]
pr: 8626
---

# Learning: a guard is only as wide as the view of the language it parses

## Problem

PR #8626 (#8532) extended the ADR-140 encryption-posture lint (`scripts/lint-encryption-posture.py`)
with three guards:

- **Guard 1:** exact store accounting.
- **Guard 2:** instance multiplicity for `for_each`/`count` shapes.
- **Guard 3:** equality clauses binding the Article 30 register and `model.c4` to ledger rows.

Before review, the author battery was green with 137 assertions and every mutation row killed. The
12-agent review found three defect classes that the battery could not see.

1. **Every guard was narrower than its property, because the input was parsed with line regexes.**
   HCL and markdown were read line by line with regular expressions, so each guard inherited the
   parser's blind spots:
   - a `}` inside a comment or string ended a block early;
   - unquoted or hyphenated resource labels were never matched;
   - two map keys on one line counted as one;
   - `override.tf` and `*.tf.json` were never read;
   - denial phrasings ("LUKS is planned", "not … and …") and claim tokens ("LUKS2") fell outside the
     regexes;
   - clause spelling variants were silently ignored instead of reported as malformed.

   None of these were exotic. Each is ordinary grammar of the language being linted.
2. **The mutation battery only deleted whole marked regions, and its harness failed open.**
   - **Survivors:** 17 mutants survived, all inside regexes, the section splitter and the gate
     derivation. Deleting a whole region cannot reach a character class.
   - **Missing end marker:** a missing end marker truncated the mutant, and `python3` exits 0 on a
     truncated program, so this read as KILLED.
   - **Crashes:** crashes read as KILLED too.

   The harness was the one guard nobody had mutated.
3. **The first design-pass "fix" reintroduced the class.**
   - **`gated_by`:** the fix for Guard 2's unchecked gate added a free-text `gated_by` field that
     nothing checked, which was a second unchecked list.
   - **Tracked files:** "Tracked files only" was implemented in the main scan while a sibling
     resolver (`resolve_var_map_keys`) still globbed the filesystem.

Two findings sat outside the lint, both from the security and user-impact seats:

- **A false claim inherited into a legal record.** PR #8617's breach-register row said pre-fix
  copies "expire on disclosed bounds". Four web-1 snapshot images hold the unencrypted journal
  outside every disclosed bound. The sentence was carried in from the Better Stack and Sentry
  retention framing without re-checking whether that framing covered the new member.
- **A credential exposure found by measurement, not argument.**
  - The images hold web-1's first-boot `prd` Doppler token. It was revoked on 2026-07-30, so that
    path is closed.
  - The retained image `411798619` very likely holds the live `workspaces-luks-boot` token, which
    fetches `WORKSPACES_LUKS_KEY`. It was installed at 09:33Z on 2026-07-23, and the image was taken
    at 15:34Z. This is tracked at #8632 and needs the operator.

## Solution

- **Parser views first.** `hcl_views()` returns two same-length views of each file. One blanks
  comments (`nc`). The other blanks comments, string bodies and heredoc bodies (`co`). Block
  boundaries, labels, map keys and `for_each`/`count` expressions are all read from `co`, so byte
  offsets stay aligned for error messages. `RESOURCE_RE` accepts quoted and unquoted hyphenated
  labels. `.tf.json` resources are parsed as JSON. The scan covers all tracked `*.tf` and
  `*.tf.json` files through one helper (`_tracked_files`: `git ls-files`, `GIT_*` stripped,
  symlinks refused, a warning on git failure), and every resolver calls that helper.
- **Clauses are detected loosely and validated strictly.** Any token shaped like
  `encryption-posture ledger:` that does not parse exactly is reported as malformed. Only the exact
  maintenance template is exempt. Sections split only at H1 and H2 headings outside fenced code.
- **Gates are derived, not declared.**
  - A gated shape (`count`, a module, or a non-variable `for_each`) must declare `instances: []`.
  - Its `reevaluate_when` must name a `var.`, `local.` or `module.` identifier derived from the
    block's own expression.
  - No free-text field carries a gate.
- **The harness is a guard.** `run_mutation` now requires:
  - exactly one non-empty marker region;
  - a mutant that differs from the SUT;
  - a mutant that prints the sweep's summary line, so a truncated or crashed mutant is UNRESOLVED
    and never KILLED;
  - an optional surviving-check needle;
  - an optional must-PASS base.

  Positive controls drive each helper once (ADR-193). The case floor is derived as
  `MIN_STATIC + REAL_N + WEBHOST_N`. Semantic mutants (MB-17 to MB-33) now target the regexes, the
  splitter and gate derivation. The battery is 181/181.
- **The legal records were corrected before merge.** PR #8617's breach register and post-mortem now
  name the four snapshot images. #8624 was widened to the published retention sentence. The
  Art. 5(2) destruction record was committed as a `pending` precondition before any deletion.

## Key Insight

A lint over a structured language has two widths: the property's and the parser's. When the parser
is a line regex, the parser's width wins silently. Every grammar shape the regex does not model (a
comment, a string, a second key on a line, an override file, a JSON encoding) is a place where a
real violation passes. So build the language view first, and derive every guard from it. Then
enumerate the grammar's shapes as fixtures before writing the guard's logic. Mutating the guard
cannot find this, because the mutation reaches the guard and not the view it reads.

The same session showed the harness corollary a third time (#7438, #7828, now #8626). A harness
counts as a guard only if it can report "did not measure". A mutant that did not run to its own
summary line has not been killed.

## Session Errors

1. **The 12-agent review found line-regex parsing behind every guard** (brace in comment or string,
   unquoted or hyphenated labels, two keys per line, `override.tf`, denial phrasings, clause
   variants). Recovery: comment- and string-aware `hcl_views()`, loose clause detection, and new
   fixture families. **Prevention:** write the language's view and its grammar-shape fixtures
   before any guard logic. This is routed to `work/SKILL.md` below.
2. **The mutation battery only deleted marked regions, so 17 survivors sat inside regexes, the
   splitter and gate derivation.** Recovery: semantic mutants MB-17 to MB-33. **Prevention:** the
   `review/SKILL.md` #7438 bullet already requires enumerating the battery's AXES. The author side
   never read it, so the work-skill bullet below points the author at it before any battery is
   claimed.
3. **`run_mutation` scored a missing end marker (a truncated mutant exits 0) and crashes as
   KILLED.** Recovery: unique-region, mutant-differs and summary-line checks, plus positive
   controls. **Prevention:** the same routed bullet requires "prints its own summary line" as the
   kill precondition.
4. **The first design-pass fix (a free-text `gated_by` field) was itself an unchecked-list
   bypass.** Recovery: `instances: []` plus a `reevaluate_when` derived from the block expression.
   **Prevention:** when fixing a "nothing checks X" finding, the fix must not add a new field that
   nothing checks. Grade the fix commit as its own change (the review skill's fix-commit rule
   already says this).
5. **"Tracked files only" was violated by a sibling resolver that still globbed.** Recovery: every
   resolver calls `_tracked_files`. **Prevention:** after changing how a corpus is enumerated,
   grep every `glob(`, `os.walk(` and `Path.rglob(` in the file. The fix belongs to the class, not
   the instance.
6. **The design-pass test fixture for H3 and fenced headings was vacuous**, because the clause came
   before the sub-structure, so a stale splitter passed. Recovery: the clause was moved after the H3
   and the fence. **Prevention:** a fixture for "X does not split a section" must put the subject
   after X. Name the mutation it kills before writing it.
7. **Rejecting unknown keys surfaced pre-existing schema drift.** `hcloud_volume.inngest_redis`
   carried `reassessed_on` and `expires_on_not_extended`, added by #7778. Recovery: both were
   admitted to `EXCEPTION_KEYS` and the schema. **Prevention:** when tightening a schema, run it
   against the committed data first and triage each hit as drift or intent before writing the
   rejection.
8. **The regex defects the new fixtures found:** "LUKS is planned" was not treated as a denial,
   "LUKS2" was not treated as a claim, and a benign negation matched a denial across "and".
   Recovery: the patterns were fixed. **Prevention:** covered by item 1 (enumerate phrasings as
   fixtures in both directions).
9. **PR #8617's breach-register row said pre-fix copies "expire on disclosed bounds"** while four
   snapshot images hold the journal. This was an inherited framing. Recovery: corrected before
   merge, and #8624 was widened. **Prevention:** the compound skill's inherited-framing bullet
   already applies. For a retention claim, the falsifying command is the provider's snapshot and
   backup listing (`GET /v1/images?type=snapshot`), run before writing the sentence.
10. **A `sed` using `#` as its delimiter collided with `##` in the replacement.** Recovery: switched
    to `|`. **Prevention:** in markdown edits, use `|` or a Python `str.replace` with an
    exactly-once assert.
11. **A Python raw string ending in a backslash broke parsing.** Recovery: the text moved into block
    files. **Prevention:** keep multi-line literal payloads in files and never in inline `r"..."`.
12. **Rewriting the schema through `json.dumps` reformatted the whole file.** Recovery: reverted,
    and the edits were redone in place as text. **Prevention:** edit hand-formatted JSON as text
    (Edit tool), or diff `--stat` before staging a machine rewrite.
13. **The MB-17 and MB-33 markers left an empty `for` body, and the MB-16 and MB-28 mutants
    crashed** because `continue` sat inside the markers. Recovery: the markers now wrap the whole
    loop, and `continue` moved outside them. **Prevention:** the summary-line kill precondition
    (item 3) now reports these as UNRESOLVED instead of KILLED.
14. **The `fixture-relative-assert` ratchet tripped twice on new redirects, and
    `lint-shell-capture-exit` flagged new captures.** Recovery: output routed through `write_file`
    under `$TMPDIR_TEST`, and `|| true` added. **Prevention:** already routed in
    `work/SKILL.md` ("A FILE-SELECTED SUITE SET CANNOT SEE A REPO-GLOBAL RATCHET"). Widen the
    selection by hand to the repo-global ratchets before pushing a new test file.
15. **A hook blocked `gh issue create` because `$S` appeared in `--body-file`, and the body file was
    never written, because the whole compound command was blocked.** Recovery: write the file in
    one call, then pass a literal path. **Prevention:** never combine the write of a body file and
    its consumer in one Bash call. Write, then consume.
16. **`gh issue create` was denied five times in total.** Four were
    `wg-defer-only-after-inline-triage` denies and one was a `guardrails-require-milestone` deny,
    because each body lacked the triage, scope-out and milestone shape. Recovery: added a
    `## Scope-Out Justification`, a re-evaluation trigger, a milestone, and a `Mandated-By` line or
    the `meta/machinery` label. **Prevention:** already hook-enforced. Copy the deny message's
    required sections into the body file BEFORE the first attempt, not after the deny.
17. **The Stop hook repeatedly caught future-tense commitments at the end of a turn.** Recovery:
    turns end with an explicit `<stop>` state. **Prevention:** already hook-enforced. End a turn
    with a state and not a promise.
18. **A Monitor expired silently.** Recovery: re-armed it and re-read the PR state directly.
    **Prevention:** `hr-monitor-not-run-in-background-for-polling` already applies. Treat a monitor's
    absence of events as UNRESOLVED and re-read the state before any verdict.
19. **Two review seats left their `/var/tmp` sandboxes behind** (`/var/tmp/prs-8626-exp2` and
    `/var/tmp/prs-8626-other`, 180 KB in total, not git worktrees). The rm guard will not let the
    orchestrator remove them. `/var/tmp` is correct: `review/SKILL.md` prescribes it because `/tmp`
    has a quota (#8292). The defect is that the "deleted before the seat returns" instruction was
    never checked. Recovery: left for manual removal. **Prevention:** when collecting seat results,
    `ls -d /var/tmp/<brief-prefix>*`, and name any survivor in the review summary so the operator
    sees it. This is one-off at 180 KB, so no rule change.

## Tags

category: workflow-patterns
module: encryption-posture-ledger
